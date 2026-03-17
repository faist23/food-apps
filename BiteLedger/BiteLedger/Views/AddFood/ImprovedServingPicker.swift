import SwiftUI
import SwiftData
import BiteLedgerCore

/// Improved serving picker with unit conversion like LoseIt
struct ImprovedServingPicker: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    
    let product: ProductInfo
    let mealType: MealType
    let existingFoodItem: FoodItem? // If provided, reuse this instead of creating new
    let initialServingAmount: Double? // If provided, use this as the default amount
    let initialPortionId: Int? // If provided, use this as the initial selected portion
    let initialUnit: String? // If provided, use this as the initial unit (e.g., "g", "oz", "serving")
    let onAdd: (AddedFoodItem) -> Void
    
    @State private var wholeNumber: Int
    @State private var fraction: Fraction
    @State private var selectedUnit: ServingUnit
    @State private var availableUnits: [ServingUnit] = []
    @State private var selectedPortion: ServingPortion?
    
    private let foodType: FoodType
    private let productServingGrams: Double?
    private let hasPortions: Bool
    private let hasServingSize: Bool  // True if product has a serving size (even without grams)
    private let parsedServingAmount: Double?   // e.g. 8 for "8 fl oz"
    private let parsedServingUnit: ServingUnit? // e.g. .fluidOunce for "8 fl oz" (nil if .serving)
    
    enum Fraction: Double, CaseIterable, Identifiable {
        case zero = 0.0
        case quarter = 0.25
        case third = 0.33
        case half = 0.5
        case twoThirds = 0.67
        case threeQuarters = 0.75
        
        var id: Double { rawValue }
        
        var displayName: String {
            switch self {
            case .zero: return "0"
            case .quarter: return "1/4"
            case .third: return "1/3"
            case .half: return "1/2"
            case .twoThirds: return "2/3"
            case .threeQuarters: return "3/4"
            }
        }
    }
    
    init(product: ProductInfo, mealType: MealType, existingFoodItem: FoodItem? = nil, initialServingAmount: Double? = nil, initialPortionId: Int? = nil, initialUnit: String? = nil, onAdd: @escaping (AddedFoodItem) -> Void) {
        self.product = product
        self.mealType = mealType
        self.existingFoodItem = existingFoodItem
        self.initialServingAmount = initialServingAmount
        self.initialPortionId = initialPortionId
        self.initialUnit = initialUnit
        self.onAdd = onAdd
        
        // Infer food type for density calculations
        self.foodType = FoodType.infer(from: product.displayName)
        
        // Check if product has portions
        self.hasPortions = (product.portions?.count ?? 0) > 0
        
        // Check if product has a serving size
        self.hasServingSize = product.servingSize != nil
        
        // Set initial portion - use initialPortionId if provided, otherwise first portion
        if let portionId = initialPortionId,
           let portions = product.portions,
           let portion = portions.first(where: { $0.id == portionId }) {
            print("✅ Setting initial portion to previously selected: \(portion.modifier)")
            _selectedPortion = State(initialValue: portion)
        } else if let firstPortion = product.portions?.first {
            print("⚠️ No initial portion specified, defaulting to first: \(firstPortion.modifier)")
            _selectedPortion = State(initialValue: firstPortion)
        }
        
        print("🔍 Product: \(product.displayName)")
        print("🔍 Serving size string from API: '\(product.servingSize ?? "nil")'")
        print("🔍 Has portions: \(self.hasPortions), count: \(product.portions?.count ?? 0)")
        print("🔍 Initial serving amount: \(initialServingAmount ?? 0)")
        
        // Parse product's natural serving size
        if let parsed = ServingSizeParser.parse(product.servingSize) {
            print("✅ Parsed serving: \(parsed.amount) \(parsed.unit.rawValue), grams: \(parsed.grams ?? 0)")
            
            // Use initialServingAmount if provided, otherwise use parsed amount
            let amount = initialServingAmount ?? parsed.amount
            
            // Split amount into whole and fractional parts
            let whole = Int(amount)
            let fractionalPart = amount - Double(whole)
            
            // Find closest fraction
            let closestFraction = Fraction.allCases.min(by: { abs($0.rawValue - fractionalPart) < abs($1.rawValue - fractionalPart) }) ?? .zero
            
            print("✅ Setting initial amount to: \(whole) + \(closestFraction.displayName)")
            _wholeNumber = State(initialValue: whole)
            _fraction = State(initialValue: closestFraction)
            
            // Use initialUnit if provided, otherwise use parsed unit
            if let unitString = initialUnit,
               let unit = ServingUnit.fromAbbreviation(unitString) {
                print("✅ Using initial unit: \(unitString)")
                _selectedUnit = State(initialValue: unit)
            } else {
                _selectedUnit = State(initialValue: parsed.unit)
            }
            
            // Prefer existingFoodItem's baseServingGrams over parsed value
            // This ensures when re-adding from My Foods, we use the stored gram weight
            if let existingGrams = existingFoodItem?.defaultServing?.gramWeight, existingGrams > 0 {
                print("✅ Using existing food item's baseServingGrams: \(existingGrams)")
                self.productServingGrams = existingGrams
            } else {
                self.productServingGrams = parsed.grams
            }
            self.parsedServingAmount = parsed.amount
            self.parsedServingUnit = (parsed.unit == .serving) ? nil : parsed.unit
        } else {
            print("⚠️ Failed to parse serving size, using initial amount or defaulting to 100g")
            // Use initialServingAmount if provided, otherwise default to 100g
            let amount = initialServingAmount ?? 100
            let whole = Int(amount)
            let fractionalPart = amount - Double(whole)
            let closestFraction = Fraction.allCases.min(by: { abs($0.rawValue - fractionalPart) < abs($1.rawValue - fractionalPart) }) ?? .zero
            
            _wholeNumber = State(initialValue: whole)
            _fraction = State(initialValue: closestFraction)
            
            // Use initialUnit if provided, otherwise default to gram
            if let unitString = initialUnit,
               let unit = ServingUnit.fromAbbreviation(unitString) {
                print("✅ Using initial unit: \(unitString)")
                _selectedUnit = State(initialValue: unit)
            } else {
                _selectedUnit = State(initialValue: .gram)
            }
            
            self.productServingGrams = amount
            self.parsedServingAmount = nil
            self.parsedServingUnit = nil
        }
    }

    private var amountValue: Double {
        Double(wholeNumber) + fraction.rawValue
    }

    /// Converts the current picker state (amountValue + selectedUnit) into a
    /// number-of-product-servings for use with per-serving nutrition data.
    private var resolvedServingCount: Double {
        // .serving mode or a USDA portion: amountValue is already the serving count
        if selectedUnit == .serving || selectedPortion != nil { return amountValue }
        // Same unit as the natural serving (e.g. user picks fl oz, label says "8 fl oz")
        if let parsedUnit = parsedServingUnit,
           let parsedAmount = parsedServingAmount,
           parsedUnit == selectedUnit, parsedAmount > 0 {
            return amountValue / parsedAmount
        }
        // Gram-weight path (serving has an explicit gramWeight)
        if let servingGrams = productServingGrams, servingGrams > 0 {
            return totalGrams / servingGrams
        }
        // Fallback: treat amountValue as serving count
        return amountValue
    }

    private var totalGrams: Double {
        // If we have a selected portion, use its gram weight
        if let portion = selectedPortion {
            return amountValue * portion.gramWeight
        }
        
        // If we have an existing FoodItem with serving sizes, try to find a matching one
        if let existingFoodItem = existingFoodItem,
           !existingFoodItem.servingSizes.isEmpty,
           let baseGrams = existingFoodItem.defaultServing?.gramWeight {
            
            // Look for a serving size that matches the selected unit
            let unitName = selectedUnit.rawValue.lowercased()
            
            if selectedUnit == .serving {
                // Use the default serving (baseMultiplier = 1.0)
                return amountValue * baseGrams
            } else if let matchingServing = existingFoodItem.servingSizes.first(where: { serving in
                serving.label.lowercased().contains(unitName)
            }), let gramWeight = matchingServing.gramWeight {
                // Divide by the label's parsed amount so "2 tablespoons (32g)" gives 16g/tbsp,
                // not 32g/tbsp (which would make 3 tbsp = 96g instead of 48g).
                let gramsPerUnit: Double
                if let parsed = ServingSizeParser.parse(matchingServing.label), parsed.amount > 0 {
                    gramsPerUnit = gramWeight / parsed.amount
                } else {
                    gramsPerUnit = gramWeight
                }
                return amountValue * gramsPerUnit
            }
        }
        
        // Otherwise use the standard unit conversion
        if selectedUnit == .serving {
            if let servingGrams = productServingGrams, servingGrams > 0 {
                return amountValue * servingGrams
            } else {
                // No gram data for serving (e.g., some FatSecret items)
                // For per-serving items without gram weights, store the serving count as "grams"
                // The FoodItem.nutritionFor() method will interpret this correctly
                return amountValue
            }
        }
        let density = ServingUnit.densityFor(foodType: foodType)
        return selectedUnit.toGrams(amount: amountValue, density: density)
    }
    
    private var nutritionMultiplier: Double {
        let hasServingData = product.nutriments?.energyKcalServing?.value ?? 0 > 0
        if hasServingData {
            // resolvedServingCount converts (amountValue + selectedUnit) → number of product servings
            return resolvedServingCount
        } else if totalGrams > 0 {
            return totalGrams / 100.0
        } else {
            return 1.0
        }
    }
    
    private var calculatedNutrition: NutritionFacts? {
        product.nutriments?.toNutritionFacts(servingMultiplier: nutritionMultiplier, servingGrams: productServingGrams ?? 0)
    }
    
    private var nutritionPer100g: NutritionFacts? {
        product.nutriments?.toNutritionFacts(servingMultiplier: 1.0, servingGrams: productServingGrams ?? 0)
    }
    
    private var currentServingDisplayText: String {
        // If a portion is selected, show it with amount
        if let portion = selectedPortion {
            return formatAmount(amountValue) + " " + portion.modifier
        }
        
        // Otherwise format based on selected unit
        let amountText = formatAmount(amountValue)
        let unitText = displayNameForUnit(selectedUnit)
        
        return "\(amountText) \(unitText)"
    }
    
    private var nutritionLabel: some View {
        ElevatedCard(padding: 0, cornerRadius: 20) {
            VStack(alignment: .leading, spacing: 0) {
                // Nutrition Facts Header
                HStack {
                    Text("Nutrition Facts")
                        .font(.system(size: 32, weight: .black))
                        .foregroundStyle(Color("TextPrimary"))
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.top, 16)
                
                // Heavy divider under header
                Rectangle()
                    .fill(Color("TextPrimary"))
                    .frame(height: 8)
                    .padding(.horizontal, 16)
                    .padding(.top, 4)
                
                VStack(spacing: 0) {
                    nutritionFactsContent
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
            }
        }
    }
    
    private var nutritionFactsContent: some View {
        VStack(spacing: 0) {
            if let nutrition = calculatedNutrition {
                // Serving size info
                Text(currentServingDisplayText)
                    .font(.system(size: 13, weight: .semibold))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 8)
                
                Text("Amount per serving")
                    .font(.system(size: 11, weight: .semibold))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 4)
                
                // Calories
                HStack(alignment: .firstTextBaseline) {
                    Text("Calories")
                        .font(.system(size: 32, weight: .black))
                    Spacer()
                    Text("\(Int(nutrition.caloriesPer100g))")
                        .font(.system(size: 44, weight: .black))
                }
                .padding(.vertical, 4)
                
                // Heavy divider
                Rectangle()
                    .fill(Color("TextPrimary"))
                    .frame(height: 6)
                    .padding(.vertical, 4)
                
                // % Daily Value header
                HStack {
                    Spacer()
                    Text("% Daily Value*")
                        .font(.system(size: 12, weight: .bold))
                }
                .padding(.bottom, 4)
                
                // Thin divider
                thinDivider()
                
                // Macronutrients
                nutrientRow("Total Fat", nutrition.fatPer100g, "g", bold: true)
                thinDivider()
                
                if let satFat = nutrition.saturatedFatPer100g, satFat > 0 {
                    indentedNutrientRow("Saturated Fat", satFat, "g")
                    thinDivider()
                }
                
                if let sodium = nutrition.sodiumPer100g, sodium > 0 {
                    nutrientRow("Sodium", sodium * 1000, "mg", bold: true)
                    thinDivider()
                }
                
                nutrientRow("Total Carbohydrate", nutrition.carbsPer100g, "g", bold: true)
                thinDivider()
                
                if let fiber = nutrition.fiberPer100g, fiber > 0 {
                    indentedNutrientRow("Dietary Fiber", fiber, "g")
                    thinDivider()
                }
                
                if let sugar = nutrition.sugarPer100g, sugar > 0 {
                    indentedNutrientRow("Total Sugars", sugar, "g")
                    thinDivider()
                }
                
                nutrientRow("Protein", nutrition.proteinPer100g, "g", bold: true)
                
                // Heavy divider before vitamins/minerals
                Rectangle()
                    .fill(Color("TextPrimary"))
                    .frame(height: 8)
                    .padding(.vertical, 4)
                
                // Vitamins and Minerals
                VStack(spacing: 0) {
                    if let vitaminD = product.nutriments?.vitaminD100g?.value, vitaminD > 0 {
                        let multiplier = nutritionMultiplier(for: nutrition)
                        nutrientRow("Vitamin D", vitaminD * multiplier * 1_000_000, "mcg")
                        thinDivider()
                    }
                    
                    if let calcium = product.nutriments?.calcium100g?.value, calcium > 0 {
                        let multiplier = nutritionMultiplier(for: nutrition)
                        nutrientRow("Calcium", calcium * multiplier * 1000, "mg")
                        thinDivider()
                    } else if let calciumMg = product.nutriments?.calciumServing?.value, calciumMg > 0 {
                        nutrientRow("Calcium", calciumMg * resolvedServingCount, "mg")
                        thinDivider()
                    }

                    if let iron = product.nutriments?.iron100g?.value, iron > 0 {
                        let multiplier = nutritionMultiplier(for: nutrition)
                        nutrientRow("Iron", iron * multiplier * 1000, "mg")
                        thinDivider()
                    } else if let ironMg = product.nutriments?.ironServing?.value, ironMg > 0 {
                        nutrientRow("Iron", ironMg * resolvedServingCount, "mg")
                        thinDivider()
                    }

                    if let potassium = product.nutriments?.potassium100g?.value, potassium > 0 {
                        let multiplier = nutritionMultiplier(for: nutrition)
                        nutrientRow("Potassium", potassium * multiplier * 1000, "mg")
                        thinDivider()
                    } else if let potassiumMg = product.nutriments?.potassiumServing?.value, potassiumMg > 0 {
                        nutrientRow("Potassium", potassiumMg * resolvedServingCount, "mg")
                        thinDivider()
                    }

                    if let vitaminA = product.nutriments?.vitaminA100g?.value, vitaminA > 0 {
                        let multiplier = nutritionMultiplier(for: nutrition)
                        nutrientRow("Vitamin A", vitaminA * multiplier * 1_000_000, "mcg")
                        thinDivider()
                    } else if let vitaminAMcg = product.nutriments?.vitaminAServing?.value, vitaminAMcg > 0 {
                        nutrientRow("Vitamin A", vitaminAMcg * resolvedServingCount, "mcg")
                        thinDivider()
                    }

                    if let vitaminC = product.nutriments?.vitaminC100g?.value, vitaminC > 0 {
                        let multiplier = nutritionMultiplier(for: nutrition)
                        nutrientRow("Vitamin C", vitaminC * multiplier * 1000, "mg")
                        thinDivider()
                    } else if let vitaminCMg = product.nutriments?.vitaminCServing?.value, vitaminCMg > 0 {
                        nutrientRow("Vitamin C", vitaminCMg * resolvedServingCount, "mg")
                        thinDivider()
                    }
                    
                    if let vitaminE = product.nutriments?.vitaminE100g?.value, vitaminE > 0 {
                        let multiplier = nutritionMultiplier(for: nutrition)
                        nutrientRow("Vitamin E", vitaminE * multiplier * 1000, "mg")
                        thinDivider()
                    }
                    
                    if let vitaminK = product.nutriments?.vitaminK100g?.value, vitaminK > 0 {
                        let multiplier = nutritionMultiplier(for: nutrition)
                        nutrientRow("Vitamin K", vitaminK * multiplier * 1_000_000, "mcg")
                        thinDivider()
                    }
                    
                    if let vitaminB6 = product.nutriments?.vitaminB6100g?.value, vitaminB6 > 0 {
                        let multiplier = nutritionMultiplier(for: nutrition)
                        nutrientRow("Vitamin B6", vitaminB6 * multiplier * 1000, "mg")
                        thinDivider()
                    }
                    
                    if let vitaminB12 = product.nutriments?.vitaminB12100g?.value, vitaminB12 > 0 {
                        let multiplier = nutritionMultiplier(for: nutrition)
                        nutrientRow("Vitamin B12", vitaminB12 * multiplier * 1_000_000, "mcg")
                        thinDivider()
                    }
                    
                    if let folate = product.nutriments?.folate100g?.value, folate > 0 {
                        let multiplier = nutritionMultiplier(for: nutrition)
                        nutrientRow("Folate", folate * multiplier * 1_000_000, "mcg")
                        thinDivider()
                    }
                    
                    if let choline = product.nutriments?.choline100g?.value, choline > 0 {
                        let multiplier = nutritionMultiplier(for: nutrition)
                        nutrientRow("Choline", choline * multiplier * 1000, "mg")
                        thinDivider()
                    }
                    
                    if let magnesium = product.nutriments?.magnesium100g?.value, magnesium > 0 {
                        let multiplier = nutritionMultiplier(for: nutrition)
                        nutrientRow("Magnesium", magnesium * multiplier * 1000, "mg")
                        thinDivider()
                    }
                    
                    if let zinc = product.nutriments?.zinc100g?.value, zinc > 0 {
                        let multiplier = nutritionMultiplier(for: nutrition)
                        nutrientRow("Zinc", zinc * multiplier * 1000, "mg")
                        thinDivider()
                    }
                    
                    if let caffeine = product.nutriments?.caffeine100g?.value, caffeine > 0 {
                        let multiplier = nutritionMultiplier(for: nutrition)
                        nutrientRow("Caffeine", caffeine * multiplier * 1000, "mg")
                        thinDivider()
                    } else if let caffeineMg = product.nutriments?.caffeineServing?.value, caffeineMg > 0 {
                        nutrientRow("Caffeine", caffeineMg * resolvedServingCount, "mg")
                        thinDivider()
                    }
                }
                
                // Heavy divider at bottom
                Rectangle()
                    .fill(Color("TextPrimary"))
                    .frame(height: 4)
                    .padding(.top, 4)
                
                // FDA Disclaimer
                Text("* The % Daily Value (DV) tells you how much a nutrient in a serving of food contributes to a daily diet. 2,000 calories a day is used for general nutrition advice.")
                    .font(.system(size: 9))
                    .foregroundStyle(Color("TextSecondary"))
                    .padding(.top, 8)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
    
    // Helper to scale vitamins/minerals (always per-100g fields) for the current amount
    private func nutritionMultiplier(for nutrition: NutritionFacts) -> Double {
        totalGrams > 0 ? totalGrams / 100.0 : 1.0
    }
    
    // Helper functions
    private func thinDivider() -> some View {
        Rectangle()
            .fill(Color("TextPrimary"))
            .frame(height: 1)
    }
    
    private func nutrientRow(_ label: String, _ value: Double, _ unit: String, bold: Bool = false) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 16) {
            Text(label)
                .font(.system(size: 14))
                .fontWeight(bold ? .black : .regular)
            
            Spacer()
            
            Text(formatValue(value) + unit)
                .font(.system(size: 14))
                .fontWeight(bold ? .bold : .regular)
                .frame(minWidth: 60, alignment: .trailing)
            
            if let percent = percentDV(value, for: label) {
                Text("\(percent)%")
                    .font(.system(size: 13))
                    .fontWeight(.light)
                    .foregroundStyle(Color("TextSecondary"))
                    .frame(width: 50, alignment: .trailing)
            } else {
                Text("")
                    .frame(width: 50)
            }
        }
        .padding(.vertical, 2)
    }
    
    private func indentedNutrientRow(_ label: String, _ value: Double, _ unit: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 16) {
            Text(label)
                .font(.system(size: 14))
                .padding(.leading, 20)
            
            Spacer()
            
            Text(formatValue(value) + unit)
                .font(.system(size: 14))
                .frame(minWidth: 60, alignment: .trailing)
            
            if let percent = percentDV(value, for: label) {
                Text("\(percent)%")
                    .font(.system(size: 13))
                    .fontWeight(.light)
                    .foregroundStyle(Color("TextSecondary"))
                    .frame(width: 50, alignment: .trailing)
            } else {
                Text("")
                    .frame(width: 50)
            }
        }
        .padding(.vertical, 2)
    }
    
    private func formatValue(_ value: Double) -> String {
        if value >= 100 {
            return "\(Int(value))"
        } else if value >= 10 {
            return String(format: "%.1f", value)
        } else {
            return String(format: "%.2f", value)
        }
    }
    
    private func fdaDailyValue(for nutrient: String) -> Double? {
        switch nutrient {
        case "Total Fat": return 78
        case "Saturated Fat": return 20
        case "Cholesterol": return 300
        case "Sodium": return 2300
        case "Total Carbohydrate": return 275
        case "Dietary Fiber": return 28
        case "Total Sugars": return 50
        case "Protein": return 50
        case "Vitamin A": return 900
        case "Vitamin C": return 90
        case "Vitamin D": return 20
        case "Vitamin E": return 15
        case "Vitamin K": return 120
        case "Vitamin B6": return 1.7
        case "Vitamin B12": return 2.4
        case "Folate": return 400
        case "Choline": return 550
        case "Calcium": return 1300
        case "Iron": return 18
        case "Potassium": return 4700
        case "Magnesium": return 420
        case "Zinc": return 11
        default: return nil
        }
    }
    
    private func percentDV(_ value: Double, for label: String) -> Int? {
        guard let dv = fdaDailyValue(for: label), dv > 0 else { return nil }
        return Int((value / dv * 100).rounded())
    }
    
    private func formatAmount(_ value: Double) -> String {
        let whole = Int(value)
        let fractionalPart = value - Double(whole)
        
        if fractionalPart < 0.01 {
            return "\(whole)"
        }
        
        // Find closest fraction for display
        let fractionText: String
        if abs(fractionalPart - 0.25) < 0.01 {
            fractionText = "¼"
        } else if abs(fractionalPart - 0.33) < 0.02 {
            fractionText = "⅓"
        } else if abs(fractionalPart - 0.5) < 0.01 {
            fractionText = "½"
        } else if abs(fractionalPart - 0.67) < 0.02 {
            fractionText = "⅔"
        } else if abs(fractionalPart - 0.75) < 0.01 {
            fractionText = "¾"
        } else {
            return String(format: "%.2f", value)
        }
        
        if whole == 0 {
            return fractionText
        } else {
            return "\(whole) \(fractionText)"
        }
    }
    
    private func displayNameForUnit(_ unit: ServingUnit) -> String {
        // For .serving, we want to show the actual serving description
        if unit == .serving {
            // If the serving string has a non-standard unit word (e.g. "caplet", "tablet"),
            // extract and display it instead of the generic "Serving"
            if let servingStr = product.servingSize, !servingStr.isEmpty {
                let stripped = servingStr
                    .drop(while: { $0.isNumber || $0 == "." || $0 == "/" })
                    .trimmingCharacters(in: .whitespaces)
                // Strip a trailing "(Xg)" annotation if present
                let unitWord: String
                if let parenIdx = stripped.firstIndex(of: "(") {
                    unitWord = String(stripped[..<parenIdx]).trimmingCharacters(in: .whitespaces)
                } else {
                    unitWord = stripped
                }
                let lower = unitWord.lowercased()
                if !unitWord.isEmpty,
                   unitWord.contains(where: { $0.isLetter }),
                   !lower.hasPrefix("serving"),
                   !lower.hasPrefix("portion") {
                    return unitWord.capitalized
                }
            }
            return "Serving"
        }
        return unit.rawValue
    }
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Product header
                HStack(spacing: 12) {
                    if let imageUrl = product.imageUrl, let url = URL(string: imageUrl) {
                        AsyncImage(url: url) { image in
                            image
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                        } placeholder: {
                            Color.gray.opacity(0.2)
                        }
                        .frame(width: 50, height: 50)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text(product.displayName)
                            .font(.headline)
                            .lineLimit(2)
                        
                        if let brand = product.brands {
                            Text(brand)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    
                    Spacer()
                }
                .padding()
                .background(Color(.systemGroupedBackground))
                
                ScrollView {
                    VStack(spacing: 0) {
                        nutritionLabel
                    }
                    .padding()
                }
                
                Spacer(minLength: 16)
                
                // Portion size selector (if portions are available)
                if hasPortions, let portions = product.portions {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Size")
                            .font(.headline)
                            .foregroundStyle(.secondary)
                        
                        Menu {
                            ForEach(portions) { portion in
                                Button {
                                    selectedPortion = portion
                                } label: {
                                    HStack {
                                        Text(portion.modifier.capitalized)
                                        Spacer()
                                        if selectedPortion?.id == portion.id {
                                            Image(systemName: "checkmark")
                                        }
                                    }
                                }
                            }
                        } label: {
                            HStack {
                                Text(selectedPortion?.modifier.capitalized ?? "Select size")
                                    .foregroundStyle(.primary)
                                Spacer()
                                Image(systemName: "chevron.up.chevron.down")
                                    .foregroundStyle(.secondary)
                                    .font(.caption)
                            }
                            .padding()
                            .background(Color(.systemGray6))
                            .cornerRadius(10)
                        }
                    }
                    .padding(.horizontal)
                    .padding(.bottom, 8)
                }
                
                // Amount label
                Text("Amount")
                    .font(.headline)
                    .foregroundStyle(.secondary)
                    .padding(.bottom, 8)
                
                // Unified picker area - like LoseIt with 3 wheels side by side
                HStack(spacing: 0) {
                    // Whole number picker
                    Picker("Whole", selection: $wholeNumber) {
                        ForEach(0...500, id: \.self) { number in
                            Text("\(number)").tag(number)
                        }
                    }
                    .pickerStyle(.wheel)
                    .frame(width: 80)
                    
                    // Fraction picker
                    Picker("Fraction", selection: $fraction) {
                        ForEach(Fraction.allCases) { frac in
                            Text(frac.displayName).tag(frac)
                        }
                    }
                    .pickerStyle(.wheel)
                    .frame(width: 80)
                    
                    // Unit picker
                    Picker("Unit", selection: $selectedUnit) {
                        ForEach(getAvailableUnits(), id: \.id) { unit in
                            Text(unit.rawValue).tag(unit)
                        }
                    }
                    .pickerStyle(.wheel)
                    .frame(maxWidth: .infinity)
                    .onChange(of: selectedUnit) { oldUnit, newUnit in
                        convertAmount(from: oldUnit, to: newUnit)
                    }
                }
                .frame(height: 150)
                .background(Color(.secondarySystemGroupedBackground))
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Add to \(mealType.rawValue)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        addToMeal()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
    }
    
    private func getAvailableUnits() -> [ServingUnit] {
        var units: [ServingUnit] = []
        
        // If we have an existing FoodItem with custom portions, prioritize showing those
        if let existingFoodItem = existingFoodItem,
           !existingFoodItem.servingSizes.isEmpty {
            // Add units based on the defined portion sizes
            for servingSize in existingFoodItem.servingSizes {
                let measure = servingSize.label.lowercased()
                
                // Map common portion names to ServingUnit
                if measure.contains("cup") {
                    if !units.contains(.cup) {
                        units.append(.cup)
                    }
                } else if measure.contains("tablespoon") || measure.contains("tbsp") {
                    if !units.contains(.tablespoon) {
                        units.append(.tablespoon)
                    }
                } else if measure.contains("teaspoon") || measure.contains("tsp") {
                    if !units.contains(.teaspoon) {
                        units.append(.teaspoon)
                    }
                } else if measure.contains("oz") && !measure.contains("fl") {
                    if !units.contains(.ounce) {
                        units.append(.ounce)
                    }
                } else if measure.contains("fl oz") || measure.contains("fluid ounce") {
                    if !units.contains(.fluidOunce) {
                        units.append(.fluidOunce)
                    }
                } else if measure.contains("gram") || measure == "g" {
                    if !units.contains(.gram) {
                        units.append(.gram)
                    }
                } else if servingSize.isDefault {
                    // Default serving gets shown as "Serving"
                    if !units.contains(.serving) {
                        units.insert(.serving, at: 0)
                    }
                }
            }
        }
        
        // Always include weight units if not already added
        if !units.contains(.gram) {
            units.append(.gram)
        }
        if !units.contains(.ounce) {
            units.append(.ounce)
        }
        
        // Add volume units for liquids and semi-liquids
        if foodType == .liquid || foodType == .milk || foodType == .peanutButter || foodType == .honey || foodType == .oil {
            if !units.contains(.cup) {
                units.append(.cup)
            }
            if !units.contains(.fluidOunce) {
                units.append(.fluidOunce)
            }
            if !units.contains(.tablespoon) {
                units.append(.tablespoon)
            }
            if !units.contains(.teaspoon) {
                units.append(.teaspoon)
            }
        }
        
        // Add serving if product has one (even without grams, e.g., FatSecret items)
        if hasServingSize && !units.contains(.serving) {
            units.insert(.serving, at: 0)
        }
        
        return units
    }
    
    private func addToMeal() {
        guard calculatedNutrition != nil else { return }

        // If we have an existing FoodItem, reuse it
        let foodItem: FoodItem
        if let existing = existingFoodItem {
            foodItem = existing
        } else {
            // Check if a FoodItem with this barcode already exists in the database
            let barcode = product.code
            let descriptor = FetchDescriptor<FoodItem>(
                predicate: #Predicate { $0.barcode == barcode }
            )

            if let existingByBarcode = try? modelContext.fetch(descriptor).first {
                print("✅ Found existing FoodItem by barcode: \(existingByBarcode.name)")
                print("🔬 nutritionMode=\(existingByBarcode.nutritionMode), calories=\(existingByBarcode.calories), resolvedServingCount=\(resolvedServingCount), defaultServing gramWeight=\(existingByBarcode.defaultServing?.gramWeight as Any)")
                foodItem = existingByBarcode
                // Backfill any micronutrient fields that are nil (e.g. food was saved before
                // per-serving micronutrient support was added to FatSecretService).
                let reuseScale = existingByBarcode.defaultServing?.gramWeight.map { $0 / 100.0 } ?? 1.0
                let n = product.nutriments
                if existingByBarcode.fiber        == nil { existingByBarcode.fiber        = n?.fiber100g.map        { $0.value * reuseScale }       ?? n?.fiberServing.map        { $0.value } }
                if existingByBarcode.sugar        == nil { existingByBarcode.sugar        = n?.sugars100g.map       { $0.value * reuseScale }       ?? n?.sugarsServing.map       { $0.value } }
                if existingByBarcode.saturatedFat == nil { existingByBarcode.saturatedFat = n?.saturatedFat100g.map { $0.value * reuseScale }       ?? n?.saturatedFatServing.map { $0.value } }
                if existingByBarcode.sodium       == nil { existingByBarcode.sodium       = n?.sodium100g.map       { $0.value * 1000.0 * reuseScale } ?? n?.sodiumServing.map    { $0.value * 1000.0 } }
                if existingByBarcode.cholesterol  == nil { existingByBarcode.cholesterol  = n?.cholesterol100g.map  { $0.value * 1000.0 * reuseScale } ?? n?.cholesterolServing.map { $0.value } }
                if existingByBarcode.potassium    == nil { existingByBarcode.potassium    = n?.potassium100g.map    { $0.value * 1000.0 * reuseScale } ?? n?.potassiumServing.map  { $0.value } }
                if existingByBarcode.calcium      == nil { existingByBarcode.calcium      = n?.calcium100g.map      { $0.value * 1000.0 * reuseScale } ?? n?.calciumServing.map    { $0.value } }
                if existingByBarcode.iron         == nil { existingByBarcode.iron         = n?.iron100g.map         { $0.value * 1000.0 * reuseScale } ?? n?.ironServing.map       { $0.value } }
                if existingByBarcode.vitaminA     == nil { existingByBarcode.vitaminA     = n?.vitaminA100g.map     { $0.value * 1_000_000.0 * reuseScale } ?? n?.vitaminAServing.map { $0.value } }
                if existingByBarcode.vitaminC     == nil { existingByBarcode.vitaminC     = n?.vitaminC100g.map     { $0.value * 1000.0 * reuseScale } ?? n?.vitaminCServing.map   { $0.value } }

                // Repair FoodItems whose core nutrition was stored incorrectly by the
                // old double-scaling bug (perServing food stored as 60×0.26=15.6 instead
                // of 60). If the API has authoritative per-serving data and it disagrees
                // with what's stored, overwrite the core macros. This is safe for
                // barcode-scanned foods which were never manually edited.
                if !product.code.hasPrefix("usda_"),
                   let servingCal = n?.energyKcalServing?.value, servingCal > 0,
                   existingByBarcode.nutritionMode == .perServing,
                   abs(existingByBarcode.calories - servingCal) > 0.5 {
                    print("🔧 Repairing FoodItem core nutrition: was \(existingByBarcode.calories) cal, API says \(servingCal)")
                    existingByBarcode.calories = servingCal
                    existingByBarcode.protein = n?.proteinsServing?.value ?? existingByBarcode.protein
                    existingByBarcode.carbs = n?.carbohydratesServing?.value ?? existingByBarcode.carbs
                    existingByBarcode.fat = n?.fatServing?.value ?? existingByBarcode.fat
                }
            } else {
                // Create new FoodItem with serving-based nutrition
                // Convert API's per-100g or per-serving nutrition to base serving nutrition

                // Determine base serving description and grams
                let baseServingDesc: String
                let baseServingGrams: Double?

                if let portion = selectedPortion {
                    // User selected a USDA portion
                    baseServingDesc = "\(portion.amount) \(portion.modifier)"
                    baseServingGrams = portion.gramWeight
                } else if selectedUnit == .serving, let servingSize = product.servingSize {
                    // Use the product's natural serving
                    baseServingDesc = servingSize
                    baseServingGrams = productServingGrams
                } else if let servingSize = product.servingSize {
                    // Product has a serving size, use it as base
                    baseServingDesc = servingSize
                    baseServingGrams = productServingGrams
                } else {
                    // No serving info, default to 100g
                    baseServingDesc = "100g"
                    baseServingGrams = 100.0
                }

                // Calculate nutrition for ONE base serving
                // If we have per-100g data, convert it to per-serving
                let perServingNutrition: (calories: Double, protein: Double, carbs: Double, fat: Double)

                if let baseGrams = baseServingGrams, baseGrams > 0 {
                    if let nutriments = product.nutriments {
                        let hasServingData = nutriments.energyKcalServing?.value ?? 0 > 0
                        if hasServingData {
                            // Product has per-serving nutrition — use it directly.
                            // Do NOT multiply by servingMultiplier: the API already gives
                            // calories/protein/etc. for one serving.
                            perServingNutrition = (
                                calories: nutriments.energyKcalServing?.value ?? 0,
                                protein: nutriments.proteinsServing?.value ?? 0,
                                carbs: nutriments.carbohydratesServing?.value ?? 0,
                                fat: nutriments.fatServing?.value ?? 0
                            )
                        } else {
                            // Only per-100g data — scale to this serving's gram weight.
                            let servingMultiplier = baseGrams / 100.0
                            let nutritionFacts = nutriments.toNutritionFacts(servingMultiplier: 1.0)
                            perServingNutrition = (
                                calories: nutritionFacts.caloriesPer100g * servingMultiplier,
                                protein: nutritionFacts.proteinPer100g * servingMultiplier,
                                carbs: nutritionFacts.carbsPer100g * servingMultiplier,
                                fat: nutritionFacts.fatPer100g * servingMultiplier
                            )
                        }
                    } else {
                        perServingNutrition = (0, 0, 0, 0)
                    }
                } else {
                    // No gram weight (e.g., FatSecret with per-serving data only)
                    // Use the per-serving nutrition directly
                    if let nutriments = product.nutriments,
                       let servingCal = nutriments.energyKcalServing?.value, servingCal > 0 {
                        perServingNutrition = (
                            calories: servingCal,
                            protein: nutriments.proteinsServing?.value ?? 0,
                            carbs: nutriments.carbohydratesServing?.value ?? 0,
                            fat: nutriments.fatServing?.value ?? 0
                        )
                    } else {
                        perServingNutrition = (0, 0, 0, 0)
                    }
                }

                // Determine source
                let source: String
                if product.code.hasPrefix("usda_") {
                    source = "USDA"
                } else if product.code.hasPrefix("fatsecret_") {
                    source = "FatSecret"
                } else {
                    source = "OpenFoodFacts"
                }

                // Create FoodItem — will be normalized to per-100g below
                let servingScale = baseServingGrams.map { $0 / 100.0 } ?? 1.0
                foodItem = FoodItem(
                    name: product.displayName,
                    brand: product.brands,
                    barcode: product.code,
                    source: source,
                    nutritionMode: .perServing,
                    calories: perServingNutrition.calories,
                    protein: perServingNutrition.protein,
                    carbs: perServingNutrition.carbs,
                    fat: perServingNutrition.fat,
                    // per-100g fields scaled to serving; fall back to per-serving fields (e.g. FatSecret)
                    fiber: product.nutriments?.fiber100g.map { $0.value * servingScale }
                        ?? product.nutriments?.fiberServing.map { $0.value },
                    sugar: product.nutriments?.sugars100g.map { $0.value * servingScale }
                        ?? product.nutriments?.sugarsServing.map { $0.value },
                    saturatedFat: product.nutriments?.saturatedFat100g.map { $0.value * servingScale }
                        ?? product.nutriments?.saturatedFatServing.map { $0.value },
                    sodium: product.nutriments?.sodium100g.map { $0.value * 1000.0 * servingScale }  // g → mg
                        ?? product.nutriments?.sodiumServing.map { $0.value * 1000.0 },  // g → mg
                    cholesterol: product.nutriments?.cholesterol100g.map { $0.value * 1000.0 * servingScale }  // g → mg
                        ?? product.nutriments?.cholesterolServing.map { $0.value },
                    potassium: product.nutriments?.potassium100g.map { $0.value * 1000.0 * servingScale }  // g → mg
                        ?? product.nutriments?.potassiumServing.map { $0.value },
                    calcium: product.nutriments?.calcium100g.map { $0.value * 1000.0 * servingScale }  // g → mg
                        ?? product.nutriments?.calciumServing.map { $0.value },
                    iron: product.nutriments?.iron100g.map { $0.value * 1000.0 * servingScale }  // g → mg
                        ?? product.nutriments?.ironServing.map { $0.value },
                    vitaminA: product.nutriments?.vitaminA100g.map { $0.value * 1_000_000.0 * servingScale }  // g → mcg
                        ?? product.nutriments?.vitaminAServing.map { $0.value },
                    vitaminC: product.nutriments?.vitaminC100g.map { $0.value * 1000.0 * servingScale }  // g → mg
                        ?? product.nutriments?.vitaminCServing.map { $0.value }
                )

                // Normalize nutrition to per-100g using the base serving gram weight.
                // When baseServingGrams is nil (FatSecret no-gram): factor = 1.0,
                // values are unchanged, and gramWeight is set to 100g nominal.
                let effectiveGrams = baseServingGrams ?? 100.0
                foodItem.normalizeToPerHundredGrams(gramWeightPerServing: baseServingGrams)
                modelContext.insert(foodItem)

                // Create default serving — always set gramWeight so NutritionCalculator
                // has a concrete gram anchor for every food.
                let defaultServingUnit = ServingSizeParser.parse(baseServingDesc).flatMap {
                    $0.unit == .serving ? nil : $0.unit.rawValue
                }
                let defaultServing = ServingSize(
                    label: baseServingDesc,
                    gramWeight: effectiveGrams,
                    isDefault: true,
                    sortOrder: 0,
                    unit: defaultServingUnit
                )
                defaultServing.foodItem = foodItem
                modelContext.insert(defaultServing)
                foodItem.servingSizes.append(defaultServing)

                // Link to canonical food for authoritative unit→gram conversions.
                foodItem.canonicalFoodID = CanonicalFoodMatcher.match(
                    foodName: foodItem.name, context: modelContext
                )?.id

                // If product has USDA portions, create ServingSize entries for each
                if let productPortions = product.portions {
                    for (index, portion) in productPortions.enumerated() {
                        let portionLabel = "\(portion.amount) \(portion.modifier)"
                        let portionUnit = ServingSizeParser.parse(portionLabel).flatMap {
                            $0.unit == .serving ? nil : $0.unit.rawValue
                        }
                        let servingSize = ServingSize(
                            label: portionLabel,
                            gramWeight: portion.gramWeight,
                            isDefault: false,
                            sortOrder: index + 1,
                            unit: portionUnit
                        )
                        servingSize.foodItem = foodItem
                        modelContext.insert(servingSize)
                        foodItem.servingSizes.append(servingSize)
                    }
                }
            }
        }

        // Find or create the appropriate ServingSize for what the user selected
        var selectedServingSize: ServingSize?

        if let portion = selectedPortion {
            // Find the ServingSize matching this portion
            selectedServingSize = foodItem.servingSizes.first { servingSize in
                servingSize.label == portion.displayName
            }
        } else {
            // Find or create ServingSize for the selected unit
            selectedServingSize = foodItem.servingSizes.first { servingSize in
                servingSize.isDefault
            }
        }

        // If we still don't have a serving size, use the default
        if selectedServingSize == nil {
            selectedServingSize = foodItem.defaultServing
        }

        guard let servingSize = selectedServingSize else {
            print("❌ Failed to find or create ServingSize")
            return
        }

        let addedItem = AddedFoodItem(
            foodItem: foodItem,
            servingSize: servingSize,
            quantity: resolvedServingCount,
            loggedAmount: amountValue,
            loggedUnit: selectedUnit.rawValue
        )

        onAdd(addedItem)
    }

    private func convertAmount(from oldUnit: ServingUnit, to newUnit: ServingUnit) {
        guard oldUnit != newUnit,
              oldUnit != .serving,
              newUnit != .serving,
              selectedPortion == nil else { return }
        // Compute grams from OLD unit + current amountValue.
        // Do NOT use totalGrams here — selectedUnit has already changed to newUnit
        // by the time onChange fires, so totalGrams would give wrong results.
        let density = ServingUnit.densityFor(foodType: foodType)
        let oldGrams = oldUnit.toGrams(amount: amountValue, density: density)
        guard oldGrams > 0 else { return }
        let newRaw = oldGrams / newUnit.toGrams(amount: 1.0, density: density)
        guard newRaw.isFinite, newRaw > 0 else { return }
        let whole = max(0, Int(newRaw))
        let fractionalPart = newRaw - Double(whole)
        wholeNumber = whole
        fraction = Fraction.allCases.min(by: {
            abs($0.rawValue - fractionalPart) < abs($1.rawValue - fractionalPart)
        }) ?? .zero
    }
}

// MARK: - Supporting Views

struct MacroColumn: View {
    let label: String
    let value: Double
    let unit: String
    
    var body: some View {
        VStack(spacing: 4) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text("\(value, specifier: "%.1f")\(unit)")
                .font(.subheadline)
                .fontWeight(.medium)
        }
        .frame(maxWidth: .infinity)
    }
}

#Preview {
    let sampleProduct = ProductInfo(
        code: "123456",
        productName: "Peanut Butter",
        brands: "Jif",
        imageUrl: nil,
        nutriments: Nutriments(
            energyKcal100g: FlexibleDouble(588),
            energyKcalComputed: 588,
            proteins100g: FlexibleDouble(25),
            carbohydrates100g: FlexibleDouble(20),
            sugars100g: FlexibleDouble(10),
            fat100g: FlexibleDouble(50),
            saturatedFat100g: FlexibleDouble(10),
            transFat100g: nil,
            monounsaturatedFat100g: nil,
            polyunsaturatedFat100g: nil,
            fiber100g: FlexibleDouble(6),
            sodium100g: FlexibleDouble(0.45),
            salt100g: FlexibleDouble(1.1),
            cholesterol100g: nil,
            vitaminA100g: nil,
            vitaminC100g: nil,
            vitaminD100g: nil,
            vitaminE100g: nil,
            vitaminK100g: nil,
            vitaminB6100g: nil,
            vitaminB12100g: nil,
            folate100g: nil,
            choline100g: nil,
            calcium100g: nil,
            iron100g: nil,
            potassium100g: nil,
            magnesium100g: nil,
            zinc100g: nil,
            caffeine100g: nil,
            energyKcalServing: nil,
            proteinsServing: nil,
            carbohydratesServing: nil,
            sugarsServing: nil,
            fatServing: nil,
            saturatedFatServing: nil,
            fiberServing: nil,
            sodiumServing: nil
        ),
        servingSize: "2 tbsp (32g)",
        quantity: nil,
        portions: nil,
        countriesTags: nil,
        lastUsed: nil
    )
    
    ImprovedServingPicker(product: sampleProduct, mealType: .breakfast) { _ in }
}
