import SwiftUI
import SwiftData
import BiteLedgerCore

/// Manual food entry for when barcode/search fails or user wants custom entry
struct ManualFoodEntryView: View {
    @Environment(\.dismiss) private var dismiss
    
    let mealType: MealType
    let onAdd: (AddedFoodItem) -> Void
    
    @State private var foodName = ""
    @State private var brand = ""
    @State private var servingDescription = "1 serving"
    @State private var servingWeight = "" // Weight in grams
    @State private var servingVolume = "" // Volume if applicable
    
    // Amount to add
    @State private var amountToAdd = "1"
    
    // Nutrition Facts (per serving)
    @State private var calories = ""
    @State private var totalFat = ""
    @State private var saturatedFat = ""
    @State private var transFat = ""
    @State private var cholesterol = ""
    @State private var sodium = ""
    @State private var totalCarbs = ""
    @State private var fiber = ""
    @State private var sugar = ""
    @State private var protein = ""
    
    // Vitamins & Minerals
    @State private var vitaminA = ""
    @State private var vitaminC = ""
    @State private var vitaminD = ""
    @State private var vitaminE = ""
    @State private var vitaminK = ""
    @State private var vitaminB6 = ""
    @State private var vitaminB12 = ""
    @State private var folate = ""
    @State private var choline = ""
    @State private var calcium = ""
    @State private var iron = ""
    @State private var potassium = ""
    @State private var magnesium = ""
    @State private var zinc = ""
    @State private var caffeine = ""
    @State private var monounsaturatedFat = ""
    @State private var polyunsaturatedFat = ""

    @State private var dvMode = DVMode()

    @State private var showingServingSizePicker = false
    @State private var showingAmountPicker = false
    @State private var showingScanner = false
    @State private var portions: [CustomPortion] = []
    @State private var showingPortionEditor = false
    @State private var selectedNutritionPortion: CustomPortion?  // Which portion the nutrition is for
    @State private var showingValidationAlert = false
    @State private var validationMessage = ""
    
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Food Name (e.g., Salad)", text: $foodName)
                        .textInputAutocapitalization(.words)
                    TextField("Brand (e.g., McDonald's)", text: $brand)
                        .textInputAutocapitalization(.words)
                }
                
                Section {
                    NavigationLink {
                        ServingSizeEditorView(
                            servingDescription: $servingDescription,
                            servingWeight: $servingWeight,
                            servingVolume: $servingVolume
                        )
                    } label: {
                        HStack {
                            Text("Serving Size")
                            Spacer()
                            Text(servingDescription)
                                .foregroundStyle(.secondary)
                        }
                    }
                    
                    NavigationLink {
                        AmountPickerView(amount: $amountToAdd)
                    } label: {
                        HStack {
                            Text("Amount to Add")
                            Spacer()
                            Text(amountToAdd.isEmpty ? "None" : amountToAdd)
                                .foregroundStyle(.secondary)
                        }
                    }
                } header: {
                    Text("Serving Information")
                } footer: {
                    if !portions.isEmpty {
                        Text("This is your reference size for entering nutrition facts below.")
                            .font(.caption)
                    }
                }
                
                // Portion sizes (optional)
                Section {
                    if portions.isEmpty {
                        // Quick add common sizes
                        VStack(spacing: 12) {
                            Text("Quick Add Common Sizes:")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            
                            HStack(spacing: 12) {
                                Button("Small + Medium + Large") {
                                    showingPortionEditor = true
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                            }
                        }
                        .padding(.vertical, 4)
                    } else {
                        ForEach(portions) { portion in
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    HStack {
                                        Text(portion.name.capitalized)
                                            .font(.body)
                                            .fontWeight(selectedNutritionPortion?.id == portion.id ? .semibold : .regular)
                                        if selectedNutritionPortion?.id == portion.id {
                                            Image(systemName: "checkmark.circle.fill")
                                                .foregroundStyle(.green)
                                                .font(.caption)
                                        }
                                    }
                                    if selectedNutritionPortion?.id == portion.id {
                                        Text("Nutrition reference")
                                            .font(.caption2)
                                            .foregroundStyle(.green)
                                    } else {
                                        Text("Tap to use as reference")
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                
                                Spacer()
                                
                                VStack(alignment: .trailing, spacing: 2) {
                                    Text(portion.displayText)
                                        .foregroundStyle(.primary)
                                    Text("(\(Int(portion.grams))g)")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .padding(12)
                            .background(selectedNutritionPortion?.id == portion.id ? 
                                       Color.green.opacity(0.1) : Color(.systemGray6))
                            .cornerRadius(8)
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(selectedNutritionPortion?.id == portion.id ? 
                                           Color.green : Color.clear, lineWidth: 2)
                            )
                            .contentShape(Rectangle())
                            .onTapGesture {
                                selectedNutritionPortion = portion
                                servingDescription = "1 \(portion.name)"
                                servingWeight = String(Int(portion.grams))
                            }
                        }
                        .onDelete { indexSet in
                            portions.remove(atOffsets: indexSet)
                            if portions.isEmpty {
                                selectedNutritionPortion = nil
                            }
                        }
                        
                        Button {
                            showingPortionEditor = true
                        } label: {
                            Label("Add Another Size", systemImage: "plus.circle")
                        }
                    }
                } header: {
                    Text("Portion Sizes (Optional)")
                } footer: {
                    if portions.isEmpty {
                        Text("Add different sizes to make logging easier. Tap a size above to set it as your nutrition reference.")
                            .font(.caption)
                    } else if selectedNutritionPortion == nil {
                        HStack {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(.orange)
                            Text("⚠️ Tap a portion (e.g., Medium) to set it as your nutrition reference before entering values below.")
                        }
                        .font(.caption)
                        .foregroundStyle(.orange)
                    } else {
                        Text("✓ Nutrition values below are for: \(selectedNutritionPortion!.name.capitalized). Other sizes will be automatically calculated.")
                            .font(.caption)
                            .foregroundStyle(.green)
                    }
                }
                
                // Autofill options
                Section {
                    Button {
                        showingScanner = true
                    } label: {
                        HStack {
                            Image(systemName: "camera.fill")
                                .foregroundStyle(.orange)
                            Text("Scan Nutrition Label")
                                .foregroundStyle(.orange)
                        }
                    }
                    
                    NavigationLink {
                        WebsiteImportView { nutritionData in
                            populateFromScan(nutritionData)
                        }
                    } label: {
                        HStack {
                            Image(systemName: "link.circle.fill")
                                .foregroundStyle(.blue)
                            Text("Import from Website URL")
                                .foregroundStyle(.blue)
                        }
                    }
                    
                    NavigationLink {
                        PasteTextImportView { nutritionData in
                            populateFromScan(nutritionData)
                        }
                    } label: {
                        HStack {
                            Image(systemName: "doc.on.clipboard.fill")
                                .foregroundStyle(.green)
                            Text("Paste Nutrition Text")
                                .foregroundStyle(.green)
                        }
                    }
                } header: {
                    Text("Quick Fill")
                } footer: {
                    Text("Scan a label, paste a URL, or copy nutrition text from a website popup")
                        .font(.caption)
                }
                
                Section {
                    nutritionLabelCard
                        .listRowInsets(EdgeInsets())
                }
            }
            .navigationTitle("New Food")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        if foodName.isEmpty && calories.isEmpty {
                            validationMessage = "Please enter a food name and calories."
                            showingValidationAlert = true
                        } else if foodName.isEmpty {
                            validationMessage = "Please enter a food name."
                            showingValidationAlert = true
                        } else if calories.isEmpty {
                            validationMessage = "Please enter calories (use 0 if the food has no calories)."
                            showingValidationAlert = true
                        } else {
                            addManualFood()
                        }
                    } label: {
                        Image(systemName: "checkmark")
                            .fontWeight(.semibold)
                            .foregroundStyle(.orange)
                    }
                }
            }
            .alert("Required Fields Missing", isPresented: $showingValidationAlert) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(validationMessage)
            }
            .fullScreenCover(isPresented: $showingScanner) {
                NutritionLabelScannerView { nutritionData in
                    populateFromScan(nutritionData)
                }
            }
            .sheet(isPresented: $showingPortionEditor) {
                PortionEditorView { portion in
                    portions.append(portion)
                }
            }
        }
    }
    
    // MARK: - FDA Nutrition Label Card

    private var nutritionLabelCard: some View {
        ElevatedCard(padding: 0, cornerRadius: 20) {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            VStack(alignment: .leading, spacing: 4) {
                Text("Nutrition Facts")
                    .font(.system(size: 32, weight: .black))
                    .foregroundStyle(Color("TextPrimary"))
                Rectangle()
                    .fill(Color("TextPrimary"))
                    .frame(height: 8)
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)

            VStack(alignment: .leading, spacing: 0) {
            // Serving description
            Text(servingDescription)
                .font(.system(size: 13, weight: .semibold))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 8)
            Text("Amount per serving")
                .font(.system(size: 11, weight: .semibold))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 2)

            // Calories row
            HStack(alignment: .firstTextBaseline) {
                Text("Calories")
                    .font(.system(size: 32, weight: .black))
                Spacer()
                TextField("0", text: $calories)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .font(.system(size: 44, weight: .black))
                    .frame(width: 120)
            }
            .padding(.vertical, 4)

            Rectangle()
                .fill(Color("TextPrimary"))
                .frame(height: 5)

            // % DV header
            Text("% Daily Value*")
                .font(.system(size: 11))
                .frame(maxWidth: .infinity, alignment: .trailing)
                .padding(.top, 4)
                .padding(.bottom, 2)

            // Main nutrient block
            LabelNutrientRow(label: "Total Fat", value: $totalFat, unit: "g", dailyValue: nil, usePercent: .constant(false), bold: true, indented: false)
            LabelNutrientRow(label: "Saturated Fat", value: $saturatedFat, unit: "g", dailyValue: 20, usePercent: $dvMode.saturatedFat, bold: false, indented: true)
            LabelNutrientRow(label: "Trans Fat", value: $transFat, unit: "g", dailyValue: nil, usePercent: .constant(false), bold: false, indented: true)
            LabelNutrientRow(label: "Monounsaturated Fat", value: $monounsaturatedFat, unit: "g", dailyValue: nil, usePercent: .constant(false), bold: false, indented: true)
            LabelNutrientRow(label: "Polyunsaturated Fat", value: $polyunsaturatedFat, unit: "g", dailyValue: nil, usePercent: .constant(false), bold: false, indented: true)
            LabelNutrientRow(label: "Cholesterol", value: $cholesterol, unit: "mg", dailyValue: 300, usePercent: $dvMode.cholesterol, bold: true, indented: false)
            LabelNutrientRow(label: "Sodium", value: $sodium, unit: "mg", dailyValue: 2300, usePercent: $dvMode.sodium, bold: true, indented: false)
            LabelNutrientRow(label: "Total Carbohydrate", value: $totalCarbs, unit: "g", dailyValue: nil, usePercent: .constant(false), bold: true, indented: false)
            LabelNutrientRow(label: "Dietary Fiber", value: $fiber, unit: "g", dailyValue: 28, usePercent: $dvMode.fiber, bold: false, indented: true)
            LabelNutrientRow(label: "Total Sugars", value: $sugar, unit: "g", dailyValue: nil, usePercent: .constant(false), bold: false, indented: true)
            LabelNutrientRow(label: "Protein", value: $protein, unit: "g", dailyValue: nil, usePercent: .constant(false), bold: true, indented: false)

            Rectangle()
                .fill(Color("TextPrimary"))
                .frame(height: 6)

            // Vitamins & Minerals block
            LabelNutrientRow(label: "Vitamin D", value: $vitaminD, unit: "mcg", dailyValue: 20, usePercent: $dvMode.vitaminD, bold: false, indented: false)
            LabelNutrientRow(label: "Calcium", value: $calcium, unit: "mg", dailyValue: 1300, usePercent: $dvMode.calcium, bold: false, indented: false)
            LabelNutrientRow(label: "Iron", value: $iron, unit: "mg", dailyValue: 18, usePercent: $dvMode.iron, bold: false, indented: false)
            LabelNutrientRow(label: "Potassium", value: $potassium, unit: "mg", dailyValue: 4700, usePercent: $dvMode.potassium, bold: false, indented: false)
            LabelNutrientRow(label: "Vitamin A", value: $vitaminA, unit: "mcg", dailyValue: 900, usePercent: $dvMode.vitaminA, bold: false, indented: false)
            LabelNutrientRow(label: "Vitamin C", value: $vitaminC, unit: "mg", dailyValue: 90, usePercent: $dvMode.vitaminC, bold: false, indented: false)
            LabelNutrientRow(label: "Vitamin E", value: $vitaminE, unit: "mg", dailyValue: 15, usePercent: $dvMode.vitaminE, bold: false, indented: false)
            LabelNutrientRow(label: "Vitamin K", value: $vitaminK, unit: "mcg", dailyValue: 120, usePercent: $dvMode.vitaminK, bold: false, indented: false)
            LabelNutrientRow(label: "Vitamin B6", value: $vitaminB6, unit: "mg", dailyValue: 1.7, usePercent: $dvMode.vitaminB6, bold: false, indented: false)
            LabelNutrientRow(label: "Vitamin B12", value: $vitaminB12, unit: "mcg", dailyValue: 2.4, usePercent: $dvMode.vitaminB12, bold: false, indented: false)
            LabelNutrientRow(label: "Folate", value: $folate, unit: "mcg", dailyValue: 400, usePercent: $dvMode.folate, bold: false, indented: false)
            LabelNutrientRow(label: "Choline", value: $choline, unit: "mg", dailyValue: 550, usePercent: $dvMode.choline, bold: false, indented: false)
            LabelNutrientRow(label: "Magnesium", value: $magnesium, unit: "mg", dailyValue: 420, usePercent: $dvMode.magnesium, bold: false, indented: false)
            LabelNutrientRow(label: "Zinc", value: $zinc, unit: "mg", dailyValue: 11, usePercent: $dvMode.zinc, bold: false, indented: false)
            LabelNutrientRow(label: "Caffeine", value: $caffeine, unit: "mg", dailyValue: nil, usePercent: .constant(false), bold: false, indented: false)

            Rectangle()
                .fill(Color("TextPrimary"))
                .frame(height: 4)

            Text("* The % Daily Value (DV) tells you how much a nutrient in a serving of food contributes to a daily diet. 2,000 calories a day is used for general nutrition advice. Tap unit to switch between amount and % DV.")
                .font(.system(size: 9))
                .foregroundStyle(Color("TextSecondary"))
                .padding(.top, 8)
                .fixedSize(horizontal: false, vertical: true)
            } // end inner VStack
            .padding(.horizontal, 16)
            .padding(.bottom, 16)
        } // end outer VStack
        } // end ElevatedCard
    }

    private func populateFromScan(_ data: NutritionData) {
        // Fill in serving size if detected
        if let servingSize = data.servingSize {
            servingDescription = servingSize
        }
        
        // Fill in serving weight if detected from serving size
        if let grams = data.servingSizeGrams {
            servingWeight = String(format: "%.0f", grams)
        }
        
        // Fill in nutrition values
        if let cal = data.calories {
            calories = String(format: "%.0f", cal)
        }
        if let fat = data.totalFat {
            totalFat = String(format: "%.1f", fat)
        }
        if let satFat = data.saturatedFat {
            saturatedFat = String(format: "%.1f", satFat)
        }
        if let trans = data.transFat {
            transFat = String(format: "%.1f", trans)
        }
        if let chol = data.cholesterol {
            cholesterol = String(format: "%.0f", chol)
        }
        if let sod = data.sodium {
            sodium = String(format: "%.0f", sod)
        }
        if let carbs = data.totalCarbs {
            totalCarbs = String(format: "%.1f", carbs)
        }
        if let fib = data.fiber {
            fiber = String(format: "%.1f", fib)
        }
        if let sug = data.sugars {
            sugar = String(format: "%.1f", sug)
        }
        if let prot = data.protein {
            protein = String(format: "%.1f", prot)
        }
        if let vitD = data.vitaminD {
            vitaminD = String(format: "%.1f", vitD)
        }
        if let calc = data.calcium {
            calcium = String(format: "%.0f", calc)
        }
        if let fe = data.iron {
            iron = String(format: "%.1f", fe)
        }
        if let pot = data.potassium {
            potassium = String(format: "%.0f", pot)
        }
        if let vitA = data.vitaminA {
            vitaminA = String(format: "%.1f", vitA)
        }
        if let vitC = data.vitaminC {
            vitaminC = String(format: "%.1f", vitC)
        }
        if let vitE = data.vitaminE {
            vitaminE = String(format: "%.1f", vitE)
        }
        if let vitK = data.vitaminK {
            vitaminK = String(format: "%.1f", vitK)
        }
        if let vitB6 = data.vitaminB6 {
            vitaminB6 = String(format: "%.1f", vitB6)
        }
        if let vitB12 = data.vitaminB12 {
            vitaminB12 = String(format: "%.1f", vitB12)
        }
        if let fol = data.folate {
            folate = String(format: "%.1f", fol)
        }
        if let chol = data.choline {
            choline = String(format: "%.1f", chol)
        }
        if let mag = data.magnesium {
            magnesium = String(format: "%.0f", mag)
        }
        if let zn = data.zinc {
            zinc = String(format: "%.1f", zn)
        }
        if let caff = data.caffeine {
            caffeine = String(format: "%.0f", caff)
        }
        if let monoFat = data.monounsaturatedFat {
            monounsaturatedFat = String(format: "%.1f", monoFat)
        }
        if let polyFat = data.polyunsaturatedFat {
            polyunsaturatedFat = String(format: "%.1f", polyFat)
        }
    }
    
    private func parseDV(_ str: String, dv: Double, usePercent: Bool) -> Double? {
        guard !str.isEmpty, let val = Double(str) else { return nil }
        return usePercent ? val / 100.0 * dv : val
    }

    private func addManualFood() {
        guard let caloriesVal = Double(calories) else { return }
        
        // Get optional nutrition values (entered per serving)
        let proteinVal = Double(protein) ?? 0
        let carbsVal = Double(totalCarbs) ?? 0
        let fatVal = Double(totalFat) ?? 0
        
        // Get the actual grams per serving if provided, otherwise estimate as 1g
        let actualGramsPerServing = Double(servingWeight) ?? 1.0

        // Helper to parse optional nutrient values
        // Values are stored in their natural units (mg or mcg), no conversion needed
        let parseOptional: (String) -> Double? = { str in
            guard !str.isEmpty, let val = Double(str) else { return nil }
            return val
        }

        // Store nutrition values — will be normalized to per-100g below
        let foodItem = FoodItem(
            name: foodName,
            brand: brand.isEmpty ? nil : brand,
            source: "Manual",
            nutritionMode: .perServing,
            calories: caloriesVal,
            protein: proteinVal,
            carbs: carbsVal,
            fat: fatVal,
            fiber: parseDV(fiber, dv: 28, usePercent: dvMode.fiber),
            sugar: sugar.isEmpty ? nil : Double(sugar)!,
            saturatedFat: parseDV(saturatedFat, dv: 20, usePercent: dvMode.saturatedFat),
            transFat: transFat.isEmpty ? nil : Double(transFat)!,
            polyunsaturatedFat: polyunsaturatedFat.isEmpty ? nil : Double(polyunsaturatedFat)!,
            monounsaturatedFat: monounsaturatedFat.isEmpty ? nil : Double(monounsaturatedFat)!,
            sodium: parseDV(sodium, dv: 2300, usePercent: dvMode.sodium),
            cholesterol: parseDV(cholesterol, dv: 300, usePercent: dvMode.cholesterol),
            potassium: parseDV(potassium, dv: 4700, usePercent: dvMode.potassium),
            calcium: parseDV(calcium, dv: 1300, usePercent: dvMode.calcium),
            iron: parseDV(iron, dv: 18, usePercent: dvMode.iron),
            magnesium: parseDV(magnesium, dv: 420, usePercent: dvMode.magnesium),
            zinc: parseDV(zinc, dv: 11, usePercent: dvMode.zinc),
            vitaminA: parseDV(vitaminA, dv: 900, usePercent: dvMode.vitaminA),
            vitaminC: parseDV(vitaminC, dv: 90, usePercent: dvMode.vitaminC),
            vitaminD: parseDV(vitaminD, dv: 20, usePercent: dvMode.vitaminD),
            vitaminE: parseDV(vitaminE, dv: 15, usePercent: dvMode.vitaminE),
            vitaminK: parseDV(vitaminK, dv: 120, usePercent: dvMode.vitaminK),
            vitaminB6: parseDV(vitaminB6, dv: 1.7, usePercent: dvMode.vitaminB6),
            vitaminB12: parseDV(vitaminB12, dv: 2.4, usePercent: dvMode.vitaminB12),
            folate: parseDV(folate, dv: 400, usePercent: dvMode.folate),
            choline: parseDV(choline, dv: 550, usePercent: dvMode.choline),
            caffeine: parseOptional(caffeine)
        )
        
        // Normalize to per-100g. When no gram weight provided: 100g nominal (factor = 1.0).
        let effectiveGrams: Double? = servingWeight.isEmpty ? nil : actualGramsPerServing
        foodItem.normalizeToPerHundredGrams(gramWeightPerServing: effectiveGrams)

        // Create default base serving — always provide gramWeight so NutritionCalculator
        // has a concrete gram anchor. Use actual if known, 100g nominal otherwise.
        let baseServingUnit = ServingSizeParser.parse(servingDescription).flatMap {
            $0.unit == .serving ? nil : $0.unit.rawValue
        } ?? ServingSizeParser.parseUnit(servingDescription)?.rawValue
        let baseServing = ServingSize(
            label: servingDescription,
            gramWeight: effectiveGrams ?? 100.0,
            isDefault: true,
            sortOrder: 0,
            unit: baseServingUnit
        )
        baseServing.foodItem = foodItem

        // Note: servingSizes will be created when foodItem is inserted by the callback handler
        // We'll pass them along in a temporary array for now
        var additionalServings: [ServingSize] = [baseServing]

        // Add 100g serving if we have gram weight
        if !servingWeight.isEmpty {
            let hundredGramServing = ServingSize(
                label: "100g",
                gramWeight: 100.0,
                isDefault: false,
                sortOrder: 1,
                unit: ServingUnit.gram.rawValue
            )
            hundredGramServing.foodItem = foodItem
            additionalServings.append(hundredGramServing)
        }

        // Add additional portion sizes if any were defined
        if !portions.isEmpty {
            for (index, portion) in portions.enumerated() {
                let portionUnit = ServingSizeParser.parse(portion.name).flatMap {
                    $0.unit == .serving ? nil : $0.unit.rawValue
                } ?? ServingSizeParser.parseUnit(portion.name)?.rawValue
                let servingSize = ServingSize(
                    label: portion.name,
                    gramWeight: portion.grams,
                    isDefault: false,
                    sortOrder: additionalServings.count + index,
                    unit: portionUnit
                )
                servingSize.foodItem = foodItem
                additionalServings.append(servingSize)
            }
        }
        
        let amount = Double(amountToAdd) ?? 1.0
        
        let addedItem = AddedFoodItem(
            foodItem: foodItem,
            servingSize: baseServing,
            quantity: amount
        )
        
        onAdd(addedItem)
        dismiss()
    }
}

// MARK: - Supporting Types

private struct DVMode {
    var vitaminA = false;  var vitaminC = false;  var vitaminD = false
    var vitaminE = false;  var vitaminK = false;  var vitaminB6 = false
    var vitaminB12 = false; var folate = false;   var choline = false
    var calcium = false;   var iron = false;      var potassium = false
    var magnesium = false; var zinc = false
    var cholesterol = false; var sodium = false
    var saturatedFat = false; var fiber = false
}

// MARK: - Supporting Views

struct ManualNutritionRow: View {
    let label: String
    @Binding var value: String
    let unit: String
    var isIndented: Bool = false
    
    var body: some View {
        HStack {
            if isIndented {
                Text(label)
                    .font(.subheadline)
            } else {
                Text(label)
            }
            
            Spacer()
            
            TextField("0", text: $value)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .frame(width: 80)
            
            if !unit.isEmpty {
                Text(unit)
                    .foregroundStyle(.secondary)
                    .frame(width: 40, alignment: .leading)
            }
        }
    }
}

struct DVNutrientRow: View {
    let label: String
    @Binding var value: String
    let unit: String
    let dailyValue: Double
    @Binding var usePercent: Bool
    var isIndented: Bool = false

    var body: some View {
        HStack {
            if isIndented {
                Text(label).font(.subheadline)
            } else {
                Text(label)
            }
            Spacer()
            TextField("0", text: $value)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .frame(width: 80)
            Button { toggleUnit() } label: {
                Text(usePercent ? "%" : unit)
                    .foregroundStyle(usePercent ? Color.accentColor : .secondary)
                    .fontWeight(usePercent ? .semibold : .regular)
                    .frame(width: 40, alignment: .leading)
            }
            .buttonStyle(.plain)
        }
    }

    private func toggleUnit() {
        if let num = Double(value), num > 0 {
            let converted = usePercent
                ? num / 100.0 * dailyValue   // % → absolute
                : num / dailyValue * 100      // absolute → %
            value = converted.truncatingRemainder(dividingBy: 1) == 0
                ? String(format: "%.0f", converted)
                : String(format: "%.1f", converted)
        }
        usePercent.toggle()
    }
}

private struct LabelNutrientRow: View {
    let label: String
    @Binding var value: String
    let unit: String
    let dailyValue: Double?
    @Binding var usePercent: Bool
    var bold: Bool = false
    var indented: Bool = false

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 16) {
                if indented {
                    Spacer().frame(width: 16)
                }
                Text(label)
                    .font(.system(size: 14))
                    .fontWeight(bold ? .black : .regular)
                Spacer()
                HStack(spacing: 4) {
                    TextField("0", text: $value)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 60)
                        .font(.system(size: 14))
                        .fontWeight(bold ? .bold : .regular)
                    if let dv = dailyValue {
                        Button {
                            toggleUnit(dv: dv)
                        } label: {
                            Text(usePercent ? "%" : unit)
                                .font(.system(size: 14, weight: usePercent ? .semibold : .regular))
                                .foregroundStyle(usePercent ? Color.blue : Color("TextSecondary"))
                        }
                        .buttonStyle(.plain)
                    } else {
                        Text(unit)
                            .font(.system(size: 14))
                            .foregroundStyle(Color("TextSecondary"))
                    }
                }
            }
            .padding(.vertical, 4)

            Rectangle()
                .fill(Color("TextPrimary"))
                .frame(height: 1)
        }
    }

    private func toggleUnit(dv: Double) {
        if let num = Double(value), num > 0 {
            let converted = usePercent
                ? num / 100.0 * dv
                : num / dv * 100
            value = converted.truncatingRemainder(dividingBy: 1) == 0
                ? String(format: "%.0f", converted)
                : String(format: "%.1f", converted)
        }
        usePercent.toggle()
    }
}

struct ServingSizeEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var servingDescription: String
    @Binding var servingWeight: String
    @Binding var servingVolume: String
    
    var body: some View {
        Form {
            Section {
                TextField("e.g., 1 cup, 2 tbsp, 1 banana", text: $servingDescription)
            } header: {
                Text("Serving Description")
            } footer: {
                Text("Describe one serving (e.g., \"1 cup\", \"2 slices\", \"1 medium banana\")")
            }
            
            Section {
                HStack {
                    TextField("Optional", text: $servingWeight)
                        .keyboardType(.decimalPad)
                    Text("g")
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("Serving Weight")
            } footer: {
                Text("Enter the weight in grams for one serving (optional)")
            }
            
            Section {
                HStack {
                    TextField("Optional", text: $servingVolume)
                        .keyboardType(.decimalPad)
                    Text("mL")
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("Serving Volume")
            } footer: {
                Text("Enter the volume in mL for one serving (optional)")
            }
        }
        .navigationTitle("Serving Size")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") {
                    dismiss()
                }
                .fontWeight(.semibold)
            }
        }
    }
}

struct AmountPickerView: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var amount: String
    
    @State private var wholeNumber: Int = 1
    @State private var fraction: Fraction = .zero
    
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
    
    var body: some View {
        VStack(spacing: 0) {
            Text("Select Amount")
                .font(.headline)
                .padding()
            
            HStack(spacing: 0) {
                Picker("Whole", selection: $wholeNumber) {
                    ForEach(0...100, id: \.self) { number in
                        Text("\(number)").tag(number)
                    }
                }
                .pickerStyle(.wheel)
                .frame(width: 100)
                
                Picker("Fraction", selection: $fraction) {
                    ForEach(Fraction.allCases) { frac in
                        Text(frac.displayName).tag(frac)
                    }
                }
                .pickerStyle(.wheel)
                .frame(width: 100)
            }
            .frame(height: 200)
            
            Button {
                let total = Double(wholeNumber) + fraction.rawValue
                amount = String(format: "%.2f", total).replacingOccurrences(of: ".00", with: "")
                dismiss()
            } label: {
                Text("Done")
                    .font(.headline)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.orange)
                    .cornerRadius(12)
            }
            .padding()
        }
        .onAppear {
            if let val = Double(amount) {
                wholeNumber = Int(val)
                let fractionalPart = val - Double(wholeNumber)
                fraction = Fraction.allCases.min(by: {
                    abs($0.rawValue - fractionalPart) < abs($1.rawValue - fractionalPart)
                }) ?? .zero
            }
        }
    }
}

// MARK: - Custom Portion

struct CustomPortion: Identifiable {
    let id: Int
    let name: String
    let amount: Double
    let unit: String
    let grams: Double  // Converted value for storage
    
    init(name: String, amount: Double, unit: String, grams: Double) {
        self.id = Int.random(in: 0..<Int.max)
        self.name = name
        self.amount = amount
        self.unit = unit
        self.grams = grams
    }
    
    var displayText: String {
        if amount == 1.0 {
            return unit
        }
        let amountStr = amount.truncatingRemainder(dividingBy: 1) == 0 ? String(Int(amount)) : String(format: "%.1f", amount)
        return "\(amountStr) \(unit)"
    }
}

// MARK: - Portion Editor View

struct PortionEditorView: View {
    @Environment(\.dismiss) private var dismiss
    
    let onAdd: (CustomPortion) -> Void
    
    enum EditorMode {
        case single
        case multipleCommon
    }
    
    @State private var editorMode: EditorMode = .multipleCommon
    
    // Single portion mode
    @State private var portionName = ""
    @State private var portionAmount = ""
    @State private var selectedUnit: ServingUnit = .fluidOunce
    
    // Multiple portions mode
    @State private var smallAmount = ""
    @State private var mediumAmount = ""
    @State private var largeAmount = ""
    @State private var commonUnit: ServingUnit = .fluidOunce
    
    // Common units for portions
    private let availableUnits: [ServingUnit] = [
        .fluidOunce, .ounce, .gram, .cup, .milliliter, .tablespoon, .teaspoon
    ]
    
    private func calculateGrams(amount: String, unit: ServingUnit) -> Double? {
        guard let amt = Double(amount) else { return nil }
        
        if unit == .gram {
            return amt
        } else {
            let density = 1.0  // Standard density for liquids
            return unit.toGrams(amount: amt, density: density)
        }
    }
    
    var body: some View {
        NavigationStack {
            Form {
                // Mode picker
                Section {
                    Picker("Add", selection: $editorMode) {
                        Text("Small, Medium, Large").tag(EditorMode.multipleCommon)
                        Text("Single Size").tag(EditorMode.single)
                    }
                    .pickerStyle(.segmented)
                }
                
                if editorMode == .multipleCommon {
                    // Quick add Small, Medium, Large
                    Section {
                        Picker("Unit", selection: $commonUnit) {
                            ForEach(availableUnits, id: \.id) { unit in
                                Text(unit.rawValue).tag(unit)
                            }
                        }
                        
                        HStack {
                            Text("Small")
                                .frame(width: 70, alignment: .leading)
                            TextField("Amount", text: $smallAmount)
                                .keyboardType(.decimalPad)
                            if let grams = calculateGrams(amount: smallAmount, unit: commonUnit) {
                                Text("(\(Int(grams))g)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        
                        HStack {
                            Text("Medium")
                                .frame(width: 70, alignment: .leading)
                            TextField("Amount", text: $mediumAmount)
                                .keyboardType(.decimalPad)
                            if let grams = calculateGrams(amount: mediumAmount, unit: commonUnit) {
                                Text("(\(Int(grams))g)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        
                        HStack {
                            Text("Large")
                                .frame(width: 70, alignment: .leading)
                            TextField("Amount", text: $largeAmount)
                                .keyboardType(.decimalPad)
                            if let grams = calculateGrams(amount: largeAmount, unit: commonUnit) {
                                Text("(\(Int(grams))g)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    } header: {
                        Text("Portion Sizes")
                    } footer: {
                        Text("Enter amounts for each size. Example: 12, 20, 24 for fl oz")
                            .font(.caption)
                    }
                } else {
                    // Single portion entry
                    Section {
                        TextField("Name (e.g., Tall, Grande, Venti)", text: $portionName)
                    } header: {
                        Text("Portion Name")
                    }
                    
                    Section {
                        HStack {
                            TextField("Amount", text: $portionAmount)
                                .keyboardType(.decimalPad)
                            
                            Picker("Unit", selection: $selectedUnit) {
                                ForEach(availableUnits, id: \.id) { unit in
                                    Text(unit.rawValue).tag(unit)
                                }
                            }
                            .pickerStyle(.menu)
                        }
                        
                        if let grams = calculateGrams(amount: portionAmount, unit: selectedUnit) {
                            HStack {
                                Text("Equivalent Weight")
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Text("\(Int(grams))g")
                                    .foregroundStyle(.blue)
                            }
                        }
                    } header: {
                        Text("Portion Size")
                    }
                }
            }
            .navigationTitle("Add Portions")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        if editorMode == .multipleCommon {
                            // Add Small, Medium, Large
                            if let smallGrams = calculateGrams(amount: smallAmount, unit: commonUnit),
                               let small = Double(smallAmount) {
                                onAdd(CustomPortion(name: "small", amount: small, unit: commonUnit.rawValue, grams: smallGrams))
                            }
                            if let mediumGrams = calculateGrams(amount: mediumAmount, unit: commonUnit),
                               let medium = Double(mediumAmount) {
                                onAdd(CustomPortion(name: "medium", amount: medium, unit: commonUnit.rawValue, grams: mediumGrams))
                            }
                            if let largeGrams = calculateGrams(amount: largeAmount, unit: commonUnit),
                               let large = Double(largeAmount) {
                                onAdd(CustomPortion(name: "large", amount: large, unit: commonUnit.rawValue, grams: largeGrams))
                            }
                        } else {
                            // Add single portion
                            if let amount = Double(portionAmount),
                               let grams = calculateGrams(amount: portionAmount, unit: selectedUnit),
                               !portionName.isEmpty {
                                onAdd(CustomPortion(name: portionName, amount: amount, unit: selectedUnit.rawValue, grams: grams))
                            }
                        }
                        dismiss()
                    }
                    .disabled(editorMode == .multipleCommon ? 
                             (smallAmount.isEmpty && mediumAmount.isEmpty && largeAmount.isEmpty) :
                             (portionName.isEmpty || portionAmount.isEmpty))
                }
            }
        }
    }
}

// MARK: - Website Import View

struct WebsiteImportView: View {
    @Environment(\.dismiss) private var dismiss
    
    let onImport: (NutritionData) -> Void
    
    @State private var urlText = ""
    @State private var isLoading = false
    @State private var errorMessage: String?
    
    var body: some View {
        Form {
            Section {
                TextField("Paste website URL", text: $urlText)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
            } header: {
                Text("Website URL")
            } footer: {
                Text("Paste a link from a restaurant nutrition page (e.g., Tim Hortons, McDonald's)")
                    .font(.caption)
            }
            
            if let error = errorMessage {
                Section {
                    Text(error)
                        .foregroundStyle(.red)
                        .font(.caption)
                }
            }
            
            Section {
                Button {
                    Task {
                        await fetchNutrition()
                    }
                } label: {
                    if isLoading {
                        HStack {
                            Spacer()
                            ProgressView()
                            Text("Fetching...")
                            Spacer()
                        }
                    } else {
                        HStack {
                            Spacer()
                            Text("Import Nutrition")
                            Spacer()
                        }
                    }
                }
                .disabled(urlText.isEmpty || isLoading)
            }
        }
        .navigationTitle("Import from Website")
        .navigationBarTitleDisplayMode(.inline)
    }
    
    private func fetchNutrition() async {
        isLoading = true
        errorMessage = nil
        
        guard let url = URL(string: urlText) else {
            errorMessage = "Invalid URL"
            isLoading = false
            return
        }
        
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            guard let html = String(data: data, encoding: .utf8) else {
                errorMessage = "Could not read webpage"
                isLoading = false
                return
            }
            
            // Try to parse nutrition from HTML
            if let nutritionData = parseNutritionFromHTML(html) {
                await MainActor.run {
                    onImport(nutritionData)
                    dismiss()
                }
            } else {
                errorMessage = "Could not find nutrition information. Many websites load nutrition data with JavaScript which can't be imported. Try using 'Paste Nutrition Text' instead - copy the nutrition facts from the website and paste them."
            }
        } catch {
            errorMessage = "Error fetching page: \(error.localizedDescription)"
        }
        
        isLoading = false
    }
    
    private func parseNutritionFromHTML(_ html: String) -> NutritionData? {
        // Strip HTML tags and normalize whitespace for easier parsing
        let cleanedHTML = html.replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        
        print("🌐 Cleaned HTML preview (first 500 chars):")
        print(String(cleanedHTML.prefix(500)))
        print("---")
        
        // Try to find JSON-LD structured data which many sites use for nutrition
        if let jsonLDMatch = html.range(of: #"<script type=\"application\/ld\+json\">(.*?)<\/script>"#, options: .regularExpression) {
            let jsonString = String(html[jsonLDMatch])
            print("📊 Found JSON-LD data")
            // Try to parse nutrition from structured data
            if let nutrition = parseStructuredData(jsonString) {
                return nutrition
            }
        }
        
        var nutritionData = NutritionData()
        
        // Calories - try multiple patterns
        let caloriePatterns = [
            #"(?i)calories[\s:]+(\d+(?:\.\d+)?)"#,
            #"(?i)(\d+(?:\.\d+)?)\s*calories"#,
            #"(?i)(\d+(?:\.\d+)?)\s*kcal"#,
            #"(?i)energy[\s:]+(\d+(?:\.\d+)?)"#
        ]
        for pattern in caloriePatterns {
            if let match = cleanedHTML.range(of: pattern, options: .regularExpression),
               let value = extractNumber(from: String(cleanedHTML[match])) {
                nutritionData.calories = value
                print("✅ Found calories: \(value)")
                break
            }
        }
        
        // Total Fat
        if let fatMatch = cleanedHTML.range(of: #"(?i)total\s+fat[\s:]+(\d+(?:\.\d+)?)\s*g"#, options: .regularExpression) {
            if let value = extractNumber(from: String(cleanedHTML[fatMatch])) {
                nutritionData.totalFat = value
            }
        }
        
        // Saturated Fat
        if let satFatMatch = cleanedHTML.range(of: #"(?i)saturated\s+fat[\s:]+(\d+(?:\.\d+)?)\s*g"#, options: .regularExpression) {
            if let value = extractNumber(from: String(cleanedHTML[satFatMatch])) {
                nutritionData.saturatedFat = value
            }
        }
        
        // Trans Fat
        if let transFatMatch = cleanedHTML.range(of: #"(?i)trans\s+fat[\s:]+(\d+(?:\.\d+)?)\s*g"#, options: .regularExpression) {
            if let value = extractNumber(from: String(cleanedHTML[transFatMatch])) {
                nutritionData.transFat = value
            }
        }
        
        // Monounsaturated Fat
        if let monoFatMatch = cleanedHTML.range(of: #"(?i)monounsaturated\s+fat[\s:]+(\d+(?:\.\d+)?)\s*g"#, options: .regularExpression) {
            if let value = extractNumber(from: String(cleanedHTML[monoFatMatch])) {
                nutritionData.monounsaturatedFat = value
            }
        }
        
        // Polyunsaturated Fat
        if let polyFatMatch = cleanedHTML.range(of: #"(?i)polyunsaturated\s+fat[\s:]+(\d+(?:\.\d+)?)\s*g"#, options: .regularExpression) {
            if let value = extractNumber(from: String(cleanedHTML[polyFatMatch])) {
                nutritionData.polyunsaturatedFat = value
            }
        }
        
        // Cholesterol
        if let cholMatch = cleanedHTML.range(of: #"(?i)cholesterol[\s:]+(\d+(?:\.\d+)?)\s*mg"#, options: .regularExpression) {
            if let value = extractNumber(from: String(cleanedHTML[cholMatch])) {
                nutritionData.cholesterol = value
            }
        }
        
        // Sodium
        if let sodiumMatch = cleanedHTML.range(of: #"(?i)sodium[\s:]+(\d+(?:\.\d+)?)\s*mg"#, options: .regularExpression) {
            if let value = extractNumber(from: String(cleanedHTML[sodiumMatch])) {
                nutritionData.sodium = value
            }
        }
        
        // Total Carbohydrates
        if let carbsMatch = cleanedHTML.range(of: #"(?i)total\s+carbohydrate(?:s)?[\s:]+(\d+(?:\.\d+)?)\s*g"#, options: .regularExpression) {
            if let value = extractNumber(from: String(cleanedHTML[carbsMatch])) {
                nutritionData.totalCarbs = value
            }
        }
        
        // Dietary Fiber
        if let fiberMatch = cleanedHTML.range(of: #"(?i)dietary\s+fiber[\s:]+(\d+(?:\.\d+)?)\s*g"#, options: .regularExpression) {
            if let value = extractNumber(from: String(cleanedHTML[fiberMatch])) {
                nutritionData.fiber = value
            }
        }
        
        // Total Sugars
        if let sugarMatch = cleanedHTML.range(of: #"(?i)total\s+sugars[\s:]+(\d+(?:\.\d+)?)\s*g"#, options: .regularExpression) {
            if let value = extractNumber(from: String(cleanedHTML[sugarMatch])) {
                nutritionData.sugars = value
            }
        }
        
        // Added Sugars
        if let addedSugarMatch = cleanedHTML.range(of: #"(?i)(?:incl\.\s+)?added\s+sugars[\s:]+(\d+(?:\.\d+)?)\s*g"#, options: .regularExpression) {
            if let value = extractNumber(from: String(cleanedHTML[addedSugarMatch])) {
                nutritionData.addedSugars = value
            }
        }
        
        // Protein
        if let proteinMatch = cleanedHTML.range(of: #"(?i)proteins?[\s:]+(\d+(?:\.\d+)?)\s*g"#, options: .regularExpression) {
            if let value = extractNumber(from: String(cleanedHTML[proteinMatch])) {
                nutritionData.protein = value
            }
        }
        
        // Vitamin D
        if let vitDMatch = cleanedHTML.range(of: #"(?i)vitamin\s+d[\s:]+(\d+(?:\.\d+)?)\s*[µu]g"#, options: .regularExpression) {
            if let value = extractNumber(from: String(cleanedHTML[vitDMatch])) {
                nutritionData.vitaminD = value
            }
        }
        
        // Calcium
        if let calciumMatch = cleanedHTML.range(of: #"(?i)calcium[\s:]+(\d+(?:\.\d+)?)\s*mg"#, options: .regularExpression) {
            if let value = extractNumber(from: String(cleanedHTML[calciumMatch])) {
                nutritionData.calcium = value
            }
        }
        
        // Iron
        if let ironMatch = cleanedHTML.range(of: #"(?i)iron[\s:]+(\d+(?:\.\d+)?)\s*mg"#, options: .regularExpression) {
            if let value = extractNumber(from: String(cleanedHTML[ironMatch])) {
                nutritionData.iron = value
            }
        }
        
        // Potassium
        if let potassiumMatch = cleanedHTML.range(of: #"(?i)potassium[\s:]+(\d+(?:\.\d+)?)\s*mg"#, options: .regularExpression) {
            if let value = extractNumber(from: String(cleanedHTML[potassiumMatch])) {
                nutritionData.potassium = value
            }
        }
        
        // Vitamin A
        if let vitAMatch = cleanedHTML.range(of: #"(?i)vitamin\s+a[\s:]+(\d+(?:\.\d+)?)\s*[µu]g"#, options: .regularExpression) {
            if let value = extractNumber(from: String(cleanedHTML[vitAMatch])) {
                nutritionData.vitaminA = value
            }
        }
        
        // Vitamin C
        if let vitCMatch = cleanedHTML.range(of: #"(?i)vitamin\s+c[\s:]+(\d+(?:\.\d+)?)\s*mg"#, options: .regularExpression) {
            if let value = extractNumber(from: String(cleanedHTML[vitCMatch])) {
                nutritionData.vitaminC = value
            }
        }
        
        // Vitamin E
        if let vitEMatch = cleanedHTML.range(of: #"(?i)vitamin\s+e[\s:]+(\d+(?:\.\d+)?)\s*mg"#, options: .regularExpression) {
            if let value = extractNumber(from: String(cleanedHTML[vitEMatch])) {
                nutritionData.vitaminE = value
            }
        }
        
        // Vitamin K
        if let vitKMatch = cleanedHTML.range(of: #"(?i)vitamin\s+k[\s:]+(\d+(?:\.\d+)?)\s*[µu]g"#, options: .regularExpression) {
            if let value = extractNumber(from: String(cleanedHTML[vitKMatch])) {
                nutritionData.vitaminK = value
            }
        }
        
        // Vitamin B6
        if let vitB6Match = cleanedHTML.range(of: #"(?i)vitamin\s+b[\s-]?6[\s:]+(\d+(?:\.\d+)?)\s*mg"#, options: .regularExpression) {
            if let value = extractNumber(from: String(cleanedHTML[vitB6Match])) {
                nutritionData.vitaminB6 = value
            }
        }
        
        // Vitamin B12
        if let vitB12Match = cleanedHTML.range(of: #"(?i)vitamin\s+b[\s-]?12[\s:]+(\d+(?:\.\d+)?)\s*[µu]g"#, options: .regularExpression) {
            if let value = extractNumber(from: String(cleanedHTML[vitB12Match])) {
                nutritionData.vitaminB12 = value
            }
        }
        
        // Folate
        if let folateMatch = cleanedHTML.range(of: #"(?i)folate[\s:]+(\d+(?:\.\d+)?)\s*[µu]g"#, options: .regularExpression) {
            if let value = extractNumber(from: String(cleanedHTML[folateMatch])) {
                nutritionData.folate = value
            }
        }
        
        // Choline
        if let cholineMatch = cleanedHTML.range(of: #"(?i)choline[\s:]+(\d+(?:\.\d+)?)\s*mg"#, options: .regularExpression) {
            if let value = extractNumber(from: String(cleanedHTML[cholineMatch])) {
                nutritionData.choline = value
            }
        }
        
        // Magnesium
        if let magnesiumMatch = cleanedHTML.range(of: #"(?i)magnesium[\s:]+(\d+(?:\.\d+)?)\s*mg"#, options: .regularExpression) {
            if let value = extractNumber(from: String(cleanedHTML[magnesiumMatch])) {
                nutritionData.magnesium = value
            }
        }
        
        // Zinc
        if let zincMatch = cleanedHTML.range(of: #"(?i)zinc[\s:]+(\d+(?:\.\d+)?)\s*mg"#, options: .regularExpression) {
            if let value = extractNumber(from: String(cleanedHTML[zincMatch])) {
                nutritionData.zinc = value
            }
        }
        
        // Caffeine
        if let caffeineMatch = cleanedHTML.range(of: #"(?i)caffeine[\s:]+(\d+(?:\.\d+)?)\s*mg"#, options: .regularExpression) {
            if let value = extractNumber(from: String(cleanedHTML[caffeineMatch])) {
                nutritionData.caffeine = value
            }
        }
        
        // Only return if we found at least calories
        return nutritionData.calories != nil ? nutritionData : nil
    }
    
    private func extractNumber(from text: String) -> Double? {
        let pattern = #"(\d+(?:\.\d+)?)"#
        guard let range = text.range(of: pattern, options: .regularExpression) else { return nil }
        return Double(String(text[range]))
    }
    
    private func parseStructuredData(_ jsonString: String) -> NutritionData? {
        // Extract JSON content between script tags
        guard let jsonStart = jsonString.range(of: ">")?.upperBound,
              let jsonEnd = jsonString.range(of: "</script>", options: .backwards)?.lowerBound else {
            return nil
        }
        
        let jsonContent = String(jsonString[jsonStart..<jsonEnd])
        guard let jsonData = jsonContent.data(using: .utf8) else { return nil }
        
        do {
            if let json = try JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
               let nutrition = json["nutrition"] as? [String: Any] {
                
                var nutritionData = NutritionData()
                
                if let calories = nutrition["calories"] as? Double {
                    nutritionData.calories = calories
                } else if let caloriesStr = nutrition["calories"] as? String,
                          let calories = Double(caloriesStr) {
                    nutritionData.calories = calories
                }
                
                // Add more nutrient parsing as needed
                print("✅ Parsed nutrition from JSON-LD")
                return nutritionData
            }
        } catch {
            print("❌ Failed to parse JSON: \(error)")
        }
        
        return nil
    }
}

// MARK: - Paste Text Import View

struct PasteTextImportView: View {
    @Environment(\.dismiss) private var dismiss
    
    let onImport: (NutritionData) -> Void
    
    @State private var pastedText = ""
    
    var body: some View {
        Form {
            Section {
                TextEditor(text: $pastedText)
                    .frame(minHeight: 200)
                    .font(.system(.body, design: .monospaced))
            } header: {
                Text("Nutrition Text")
            } footer: {
                Text("Copy nutrition info from a website popup (e.g., Tim Hortons) and paste here")
                    .font(.caption)
            }
            
            Section {
                Button {
                    if let nutritionData = parseNutritionFromText(pastedText) {
                        onImport(nutritionData)
                        dismiss()
                    }
                } label: {
                    HStack {
                        Spacer()
                        Text("Import Nutrition")
                        Spacer()
                    }
                }
                .disabled(pastedText.isEmpty)
            }
        }
        .navigationTitle("Paste Nutrition")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Clear") {
                    pastedText = ""
                }
                .disabled(pastedText.isEmpty)
            }
        }
    }
    
    private func parseNutritionFromText(_ text: String) -> NutritionData? {
        var nutritionData = NutritionData()
        
        // Normalize text - collapse multiple spaces but keep basic structure
        let normalizedText = text.replacingOccurrences(of: "[ \\t]+", with: " ", options: .regularExpression)
        
        // Calories - match patterns like "Calories 190" or "Calories: 190" or "190 kcal"
        let caloriesPatterns = [
            #"(?i)calories[\s:]+(\d+(?:\.\d+)?)"#,
            #"(\d+(?:\.\d+)?)\s*kcal"#
        ]
        for pattern in caloriesPatterns {
            if let match = normalizedText.range(of: pattern, options: .regularExpression),
               let value = extractNumber(from: String(normalizedText[match])) {
                nutritionData.calories = value
                break
            }
        }
        
        // Total Fat
        if let fatMatch = normalizedText.range(of: #"(?i)total\s+fat[\s:]+(\d+(?:\.\d+)?)\s*g"#, options: .regularExpression),
           let value = extractNumber(from: String(normalizedText[fatMatch])) {
            nutritionData.totalFat = value
        }
        
        // Saturated Fat
        if let satFatMatch = normalizedText.range(of: #"(?i)saturated\s+fat[\s:]+(\d+(?:\.\d+)?)\s*g"#, options: .regularExpression),
           let value = extractNumber(from: String(normalizedText[satFatMatch])) {
            nutritionData.saturatedFat = value
        }
        
        // Trans Fat
        if let transFatMatch = normalizedText.range(of: #"(?i)trans\s+fat[\s:]+(\d+(?:\.\d+)?)\s*g"#, options: .regularExpression),
           let value = extractNumber(from: String(normalizedText[transFatMatch])) {
            nutritionData.transFat = value
        }
        
        // Monounsaturated Fat
        if let monoFatMatch = normalizedText.range(of: #"(?i)monounsaturated\s+fat[\s:]+(\d+(?:\.\d+)?)\s*g"#, options: .regularExpression),
           let value = extractNumber(from: String(normalizedText[monoFatMatch])) {
            nutritionData.monounsaturatedFat = value
        }
        
        // Polyunsaturated Fat
        if let polyFatMatch = normalizedText.range(of: #"(?i)polyunsaturated\s+fat[\s:]+(\d+(?:\.\d+)?)\s*g"#, options: .regularExpression),
           let value = extractNumber(from: String(normalizedText[polyFatMatch])) {
            nutritionData.polyunsaturatedFat = value
        }
        
        // Cholesterol
        if let cholMatch = normalizedText.range(of: #"(?i)cholesterol[\s:]+(\d+(?:\.\d+)?)\s*mg"#, options: .regularExpression),
           let value = extractNumber(from: String(normalizedText[cholMatch])) {
            nutritionData.cholesterol = value
        }
        
        // Sodium
        if let sodiumMatch = normalizedText.range(of: #"(?i)sodium[\s:]+(\d+(?:\.\d+)?)\s*mg"#, options: .regularExpression),
           let value = extractNumber(from: String(normalizedText[sodiumMatch])) {
            nutritionData.sodium = value
        }
        
        // Total Carbohydrates
        if let carbsMatch = normalizedText.range(of: #"(?i)total\s+carbohydrate(?:s)?[\s:]+(\d+(?:\.\d+)?)\s*g"#, options: .regularExpression),
           let value = extractNumber(from: String(normalizedText[carbsMatch])) {
            nutritionData.totalCarbs = value
        }
        
        // Dietary Fiber
        if let fiberMatch = normalizedText.range(of: #"(?i)dietary\s+fiber[\s:]+(\d+(?:\.\d+)?)\s*g"#, options: .regularExpression),
           let value = extractNumber(from: String(normalizedText[fiberMatch])) {
            nutritionData.fiber = value
        }
        
        // Total Sugars (prioritize "Total Sugars" over just "Sugars")
        if let sugarMatch = normalizedText.range(of: #"(?i)total\s+sugars[\s:]+(\d+(?:\.\d+)?)\s*g"#, options: .regularExpression),
           let value = extractNumber(from: String(normalizedText[sugarMatch])) {
            nutritionData.sugars = value
        } else if let sugarMatch = normalizedText.range(of: #"(?i)(?<!added\s)(?<!total\s)sugars[\s:]+(\d+(?:\.\d+)?)\s*g"#, options: .regularExpression),
                  let value = extractNumber(from: String(normalizedText[sugarMatch])) {
            nutritionData.sugars = value
        }
        
        // Added Sugars
        if let addedSugarMatch = normalizedText.range(of: #"(?i)(?:incl\.\s+)?added\s+sugars[\s:]+(\d+(?:\.\d+)?)\s*g"#, options: .regularExpression),
           let value = extractNumber(from: String(normalizedText[addedSugarMatch])) {
            nutritionData.addedSugars = value
        }
        
        // Protein
        if let proteinMatch = normalizedText.range(of: #"(?i)proteins?[\s:]+(\d+(?:\.\d+)?)\s*g"#, options: .regularExpression),
           let value = extractNumber(from: String(normalizedText[proteinMatch])) {
            nutritionData.protein = value
        }
        
        // Vitamin D
        if let vitDMatch = normalizedText.range(of: #"(?i)vitamin\s+d[\s:]+(\d+(?:\.\d+)?)\s*[µu]g"#, options: .regularExpression),
           let value = extractNumber(from: String(normalizedText[vitDMatch])) {
            nutritionData.vitaminD = value
        }
        
        // Calcium
        if let calciumMatch = normalizedText.range(of: #"(?i)calcium[\s:]+(\d+(?:\.\d+)?)\s*mg"#, options: .regularExpression),
           let value = extractNumber(from: String(normalizedText[calciumMatch])) {
            nutritionData.calcium = value
        }
        
        // Iron
        if let ironMatch = normalizedText.range(of: #"(?i)iron[\s:]+(\d+(?:\.\d+)?)\s*mg"#, options: .regularExpression),
           let value = extractNumber(from: String(normalizedText[ironMatch])) {
            nutritionData.iron = value
        }
        
        // Potassium
        if let potassiumMatch = normalizedText.range(of: #"(?i)potassium[\s:]+(\d+(?:\.\d+)?)\s*mg"#, options: .regularExpression),
           let value = extractNumber(from: String(normalizedText[potassiumMatch])) {
            nutritionData.potassium = value
        }
        
        // Vitamin A
        if let vitAMatch = normalizedText.range(of: #"(?i)vitamin\s+a[\s:]+(\d+(?:\.\d+)?)\s*[µu]g"#, options: .regularExpression),
           let value = extractNumber(from: String(normalizedText[vitAMatch])) {
            nutritionData.vitaminA = value
        }
        
        // Vitamin C
        if let vitCMatch = normalizedText.range(of: #"(?i)vitamin\s+c[\s:]+(\d+(?:\.\d+)?)\s*mg"#, options: .regularExpression),
           let value = extractNumber(from: String(normalizedText[vitCMatch])) {
            nutritionData.vitaminC = value
        }
        
        // Vitamin E
        if let vitEMatch = normalizedText.range(of: #"(?i)vitamin\s+e[\s:]+(\d+(?:\.\d+)?)\s*mg"#, options: .regularExpression),
           let value = extractNumber(from: String(normalizedText[vitEMatch])) {
            nutritionData.vitaminE = value
        }
        
        // Vitamin K
        if let vitKMatch = normalizedText.range(of: #"(?i)vitamin\s+k[\s:]+(\d+(?:\.\d+)?)\s*[µu]g"#, options: .regularExpression),
           let value = extractNumber(from: String(normalizedText[vitKMatch])) {
            nutritionData.vitaminK = value
        }
        
        // Vitamin B6
        if let vitB6Match = normalizedText.range(of: #"(?i)vitamin\s+b[\s-]?6[\s:]+(\d+(?:\.\d+)?)\s*mg"#, options: .regularExpression),
           let value = extractNumber(from: String(normalizedText[vitB6Match])) {
            nutritionData.vitaminB6 = value
        }
        
        // Vitamin B12
        if let vitB12Match = normalizedText.range(of: #"(?i)vitamin\s+b[\s-]?12[\s:]+(\d+(?:\.\d+)?)\s*[µu]g"#, options: .regularExpression),
           let value = extractNumber(from: String(normalizedText[vitB12Match])) {
            nutritionData.vitaminB12 = value
        }
        
        // Folate
        if let folateMatch = normalizedText.range(of: #"(?i)folate[\s:]+(\d+(?:\.\d+)?)\s*[µu]g"#, options: .regularExpression),
           let value = extractNumber(from: String(normalizedText[folateMatch])) {
            nutritionData.folate = value
        }
        
        // Choline
        if let cholineMatch = normalizedText.range(of: #"(?i)choline[\s:]+(\d+(?:\.\d+)?)\s*mg"#, options: .regularExpression),
           let value = extractNumber(from: String(normalizedText[cholineMatch])) {
            nutritionData.choline = value
        }
        
        // Magnesium
        if let magnesiumMatch = normalizedText.range(of: #"(?i)magnesium[\s:]+(\d+(?:\.\d+)?)\s*mg"#, options: .regularExpression),
           let value = extractNumber(from: String(normalizedText[magnesiumMatch])) {
            nutritionData.magnesium = value
        }
        
        // Zinc
        if let zincMatch = normalizedText.range(of: #"(?i)zinc[\s:]+(\d+(?:\.\d+)?)\s*mg"#, options: .regularExpression),
           let value = extractNumber(from: String(normalizedText[zincMatch])) {
            nutritionData.zinc = value
        }
        
        // Caffeine
        if let caffeineMatch = normalizedText.range(of: #"(?i)caffeine[\s:]+(\d+(?:\.\d+)?)\s*mg"#, options: .regularExpression),
           let value = extractNumber(from: String(normalizedText[caffeineMatch])) {
            nutritionData.caffeine = value
        }
        
        // Only return if we found at least calories
        return nutritionData.calories != nil ? nutritionData : nil
    }
    
    private func extractNumber(from text: String) -> Double? {
        let pattern = #"(\d+(?:\.\d+)?)"#
        guard let range = text.range(of: pattern, options: .regularExpression) else { return nil }
        return Double(String(text[range]))
    }

}

#Preview {
    ManualFoodEntryView(mealType: .breakfast) { _ in }
}
