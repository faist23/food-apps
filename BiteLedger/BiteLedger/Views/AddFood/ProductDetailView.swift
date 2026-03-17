import SwiftUI
import SwiftData
import BiteLedgerCore

/// View for displaying product details and selecting serving size
struct ProductDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    
    let product: ProductInfo
    
    @State private var servingAmount: Double = 1.0
    @State private var selectedUnit: ServingUnit = .gram
    @State private var customGrams: String = "100"
    @State private var selectedMealType: MealType = .breakfast
    @State private var showingSuccessAlert = false
    
    private var servingSizeGrams: Double {
        switch selectedUnit {
        case .gram:
            return Double(customGrams) ?? 100
        case .serving:
            // Parse serving size from product (e.g., "30g" -> 30)
            return parseServingSize(product.servingSize) * servingAmount
        case .container:
            // Parse quantity from product (e.g., "250g" -> 250)
            return parseServingSize(product.quantity) * servingAmount
        default:
            return Double(customGrams) ?? 100
        }
    }
    
    private var nutritionMultiplier: Double {
        // For items with per-serving nutrition (like FatSecret), servingSizeGrams might be 0
        // In that case, use servingAmount directly as the multiplier
        if servingSizeGrams > 0 {
            return servingSizeGrams / 100.0
        } else if selectedUnit == .serving {
            // For serving-based items with no grams, use servingAmount as multiplier
            return servingAmount
        } else {
            return 1.0
        }
    }
    
    private var calculatedNutrition: NutritionFacts? {
        product.nutriments?.toNutritionFacts(servingMultiplier: nutritionMultiplier)
    }
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Product header
                    VStack(alignment: .leading, spacing: 8) {
                        if let imageUrl = product.imageUrl, let url = URL(string: imageUrl) {
                            AsyncImage(url: url) { image in
                                image
                                    .resizable()
                                    .aspectRatio(contentMode: .fit)
                                    .frame(maxHeight: 200)
                                    .clipShape(RoundedRectangle(cornerRadius: 12))
                            } placeholder: {
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(.quaternary)
                                    .frame(height: 200)
                                    .overlay {
                                        ProgressView()
                                    }
                            }
                        }
                        
                        Text(product.displayName)
                            .font(.title2)
                            .fontWeight(.bold)
                        
                        Text(product.displayBrand)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        
                        if let servingSize = product.servingSize {
                            Label("Serving: \(servingSize)", systemImage: "scalemass")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 12))
                    
                    // Serving size picker
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Serving Size")
                            .font(.headline)
                        
                        Picker("Unit", selection: $selectedUnit) {
                            Text("Grams").tag(ServingUnit.gram)
                            if product.servingSize != nil {
                                Text("Serving").tag(ServingUnit.serving)
                            }
                            if product.quantity != nil {
                                Text("Container").tag(ServingUnit.container)
                            }
                        }
                        .pickerStyle(.segmented)
                        
                        switch selectedUnit {
                        case .gram:
                            HStack {
                                TextField("Amount", text: $customGrams)
                                    .keyboardType(.decimalPad)
                                    .textFieldStyle(.roundedBorder)
                                    .frame(width: 100)
                                
                                Text("grams")
                                    .foregroundStyle(.secondary)
                            }
                            
                        case .serving:
                            HStack {
                                Text("Amount:")
                                    .foregroundStyle(.secondary)
                                
                                Stepper(value: $servingAmount, in: 0.25...20, step: 0.25) {
                                    Text("\(servingAmount, specifier: "%.2f") servings")
                                        .font(.headline)
                                }
                            }
                            
                            if let servingSize = product.servingSize {
                                Text("1 serving = \(servingSize)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            
                        case .container:
                            HStack {
                                Text("Amount:")
                                    .foregroundStyle(.secondary)
                                
                                Stepper(value: $servingAmount, in: 0.25...20, step: 0.25) {
                                    Text("\(servingAmount, specifier: "%.2f") containers")
                                        .font(.headline)
                                }
                            }
                            
                            if let quantity = product.quantity {
                                Text("1 container = \(quantity)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        
                        default:
                            HStack {
                                TextField("Amount", text: $customGrams)
                                    .keyboardType(.decimalPad)
                                    .textFieldStyle(.roundedBorder)
                                    .frame(width: 100)
                                
                                Text(selectedUnit.abbreviation)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .padding()
                    .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 12))
                    
                    // Meal type picker
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Meal Type")
                            .font(.headline)
                        
                        Picker("Meal Type", selection: $selectedMealType) {
                            ForEach(MealType.allCases, id: \.self) { type in
                                Label(type.rawValue.capitalized, systemImage: type.icon)
                                    .tag(type)
                            }
                        }
                        .pickerStyle(.segmented)
                    }
                    .padding()
                    .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 12))
                    
                    // Nutrition summary
                    if let nutrition = calculatedNutrition {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Nutrition Facts")
                                .font(.headline)
                            
                            Text("For \(servingSizeGrams, specifier: "%.0f")g")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            
                            VStack(spacing: 8) {
                                NutritionRow(label: "Calories", value: nutrition.caloriesPer100g, unit: "kcal")
                                Divider()
                                NutritionRow(label: "Protein", value: nutrition.proteinPer100g, unit: "g")
                                NutritionRow(label: "Carbs", value: nutrition.carbsPer100g, unit: "g")
                                if let sugar = nutrition.sugarPer100g {
                                    NutritionRow(label: "  Sugar", value: sugar, unit: "g", isSubItem: true)
                                }
                                NutritionRow(label: "Fat", value: nutrition.fatPer100g, unit: "g")
                                if let fiber = nutrition.fiberPer100g {
                                    NutritionRow(label: "Fiber", value: fiber, unit: "g")
                                }
                                if let sodium = nutrition.sodiumPer100g {
                                    NutritionRow(label: "Sodium", value: sodium, unit: "mg")
                                }
                            }
                        }
                        .padding()
                        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 12))
                    }
                }
                .padding()
            }
            .navigationTitle("Add Food")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        addFoodLog()
                    }
                    .disabled(calculatedNutrition == nil)
                }
            }
            .alert("Added to Log", isPresented: $showingSuccessAlert) {
                Button("OK") {
                    dismiss()
                }
            } message: {
                Text("\(product.displayName) added to your \(selectedMealType.rawValue) log.")
            }
        }
    }
    
    private func addFoodLog() {
        guard calculatedNutrition != nil else { return }

        // Check if a FoodItem with this barcode already exists
        let barcode = product.code
        let descriptor = FetchDescriptor<FoodItem>(
            predicate: #Predicate { $0.barcode == barcode }
        )

        let foodItem: FoodItem
        if let existingByBarcode = try? modelContext.fetch(descriptor).first {
            print("✅ Found existing FoodItem by barcode: \(existingByBarcode.name)")
            foodItem = existingByBarcode
        } else {
            // Create new FoodItem with serving-based nutrition

            // Determine source
            let source: String
            if product.code.hasPrefix("usda_") {
                source = "USDA"
            } else if product.code.hasPrefix("fatsecret_") {
                source = "FatSecret"
            } else {
                source = "OpenFoodFacts"
            }

            // Extract per-100g nutrition from OpenFoodFacts data
            let nutritionFacts = product.nutriments?.toNutritionFacts(servingMultiplier: 1.0) ?? NutritionFacts(caloriesPer100g: 0, proteinPer100g: 0, carbsPer100g: 0, fatPer100g: 0)

            // DEBUG: Print nutrition facts to verify values
            print("🔍 Creating FoodItem: \(product.displayName)")
            print("   Nutrition mode: per100g")
            print("   Calories per 100g: \(nutritionFacts.caloriesPer100g)")
            print("   Protein per 100g: \(nutritionFacts.proteinPer100g)")
            print("   Carbs per 100g: \(nutritionFacts.carbsPer100g)")
            print("   Fat per 100g: \(nutritionFacts.fatPer100g)")

            // Create FoodItem with per-100g nutrition (OpenFoodFacts standard)
            foodItem = FoodItem(
                name: product.displayName,
                brand: product.brands,
                barcode: product.code,
                source: source,
                nutritionMode: .per100g,
                calories: nutritionFacts.caloriesPer100g,
                protein: nutritionFacts.proteinPer100g,
                carbs: nutritionFacts.carbsPer100g,
                fat: nutritionFacts.fatPer100g,
                fiber: product.nutriments?.fiber100g?.value,
                sugar: product.nutriments?.sugars100g?.value,
                saturatedFat: product.nutriments?.saturatedFat100g?.value,
                sodium: product.nutriments?.sodium100g.map { $0.value * 1000 }  // g → mg
            )
            
            print("   ✅ FoodItem created with calories: \(foodItem.calories)")

            modelContext.insert(foodItem)

            // Create default serving size based on product info
            let servingLabel: String
            let servingGrams: Double?
            
            if let servingSize = product.servingSize {
                servingLabel = servingSize
                servingGrams = parseServingSize(servingSize)
            } else {
                servingLabel = "100g"
                servingGrams = 100.0
            }
            
            let servingUnit = ServingSizeParser.parse(servingLabel).flatMap { parsed in
                parsed.unit == .serving ? nil : parsed.unit.rawValue
            } ?? ServingSizeParser.parseUnit(servingLabel)?.rawValue

            let defaultServing = ServingSize(
                label: servingLabel,
                gramWeight: servingGrams,
                isDefault: true,
                sortOrder: 0,
                unit: servingUnit
            )
            defaultServing.foodItem = foodItem
            modelContext.insert(defaultServing)
            foodItem.servingSizes.append(defaultServing)
        }

        // Find the default serving size
        guard let servingSize = foodItem.defaultServing else {
            print("❌ Failed to find default ServingSize")
            return
        }

        // Calculate the actual quantity to log
        // For gram-based selection: if user entered "88" in the custom grams field, 
        // and the default serving is "88g", quantity should be 1.0
        // If default serving is "100g" and user entered "88g", quantity should be 0.88
        let logQuantity: Double
        if selectedUnit == .gram, let defaultGrams = servingSize.gramWeight, defaultGrams > 0 {
            // User selected grams mode - quantity is ratio of entered grams to default serving grams
            logQuantity = servingSizeGrams / defaultGrams
        } else {
            // For serving or container mode, use servingAmount directly
            logQuantity = servingAmount
        }

        // Create food log using factory method (freezes nutrition at log time)
        let foodLog = FoodLog.create(
            mealType: selectedMealType,
            quantity: logQuantity,
            food: foodItem,
            serving: servingSize,
            timestamp: Date()
        )

        modelContext.insert(foodLog)

        do {
            try modelContext.save()
            showingSuccessAlert = true
        } catch {
            print("Failed to save food log: \(error)")
        }
    }
    
    private func parseServingSize(_ sizeString: String?) -> Double {
        guard let sizeString = sizeString else { return 100 }
        
        // Extract numeric value from strings like "30g", "250ml", "1.5oz"
        let numericString = sizeString.components(separatedBy: CharacterSet.decimalDigits.inverted).joined()
        return Double(numericString) ?? 100
    }
}

// MARK: - Supporting Views

struct NutritionRow: View {
    let label: String
    let value: Double
    let unit: String
    var isSubItem: Bool = false
    
    var body: some View {
        HStack {
            Text(label)
                .foregroundStyle(isSubItem ? .secondary : .primary)
            Spacer()
            Text("\(value, specifier: "%.1f") \(unit)")
                .fontWeight(.medium)
        }
        .font(.subheadline)
    }
}

// MARK: - Models
// ServingUnit moved to Models/ServingUnit.swift



#Preview {
    let sampleProduct = ProductInfo(
        code: "123456789",
        productName: "Organic Oatmeal",
        brands: "Nature's Best",
        imageUrl: nil,
        nutriments: Nutriments(
            energyKcal100g: FlexibleDouble(350),
            energyKcalComputed: 350,
            proteins100g: FlexibleDouble(12),
            carbohydrates100g: FlexibleDouble(60),
            sugars100g: FlexibleDouble(1),
            fat100g: FlexibleDouble(6),
            saturatedFat100g: FlexibleDouble(1),
            transFat100g: nil,
            monounsaturatedFat100g: nil,
            polyunsaturatedFat100g: nil,
            fiber100g: FlexibleDouble(10),
            sodium100g: FlexibleDouble(0.01),
            salt100g: FlexibleDouble(0.025),
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
            energyKcalServing: FlexibleDouble(175),
            proteinsServing: FlexibleDouble(6),
            carbohydratesServing: FlexibleDouble(30),
            sugarsServing: FlexibleDouble(0.5),
            fatServing: FlexibleDouble(3),
            saturatedFatServing: FlexibleDouble(0.5),
            fiberServing: FlexibleDouble(5),
            sodiumServing: FlexibleDouble(0.005)
        ),
        servingSize: "50g",
        quantity: "500g",
        portions: nil,
        countriesTags: nil,
        lastUsed: nil
    )
    
    ProductDetailView(product: sampleProduct)
        .modelContainer(for: FoodLog.self, inMemory: true)
}
