//
//  FoodItemEditorView.swift
//  BiteLedger
//
//  Created by Craig Faist on 2/25/26.
//

import SwiftUI
import SwiftData
import BiteLedgerCore

struct FoodItemEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    let foodItem: FoodItem
    @State private var showError = false
    @State private var fallbackSource: FallbackSource?

    // Basic info
    @State private var foodName: String
    @State private var brand: String
    @State private var nutritionMode: NutritionMode

    // Macros (now stored per-serving, displayed per-serving)
    @State private var calories: String
    @State private var protein: String
    @State private var carbs: String
    @State private var fat: String

    // Fats
    @State private var saturatedFat: String
    @State private var transFat: String
    @State private var monounsaturatedFat: String
    @State private var polyunsaturatedFat: String

    // Other nutrients
    @State private var cholesterol: String
    @State private var sodium: String
    @State private var fiber: String
    @State private var sugar: String

    // Vitamins
    @State private var vitaminA: String
    @State private var vitaminC: String
    @State private var vitaminD: String
    @State private var vitaminE: String
    @State private var vitaminK: String
    @State private var vitaminB6: String
    @State private var vitaminB12: String
    @State private var folate: String
    @State private var choline: String

    // Minerals
    @State private var calcium: String
    @State private var iron: String
    @State private var potassium: String
    @State private var magnesium: String
    @State private var zinc: String

    // Other
    @State private var caffeine: String
    
    // Base serving
    @State private var servingDescription: String
    @State private var gramsPerServing: String
    
    // Portion sizes management
    @State private var showingAddPortion = false
    @State private var newPortionLabel: String = ""
    @State private var newPortionGrams: String = ""

    // Enrichment
    @State private var showingEnrichment = false

    init(foodItem: FoodItem) {
        self.foodItem = foodItem

        _foodName = State(initialValue: foodItem.name)
        _brand = State(initialValue: foodItem.brand ?? "")
        _nutritionMode = State(initialValue: foodItem.nutritionMode)

        // Macros (already per serving)
        _calories = State(initialValue: String(format: "%.0f", foodItem.calories))
        _protein = State(initialValue: String(format: "%.1f", foodItem.protein))
        _carbs = State(initialValue: String(format: "%.1f", foodItem.carbs))
        _fat = State(initialValue: String(format: "%.1f", foodItem.fat))

        // Fats
        _saturatedFat = State(initialValue: foodItem.saturatedFat.map { String(format: "%.1f", $0) } ?? "")
        _transFat = State(initialValue: foodItem.transFat.map { String(format: "%.1f", $0) } ?? "")
        _monounsaturatedFat = State(initialValue: foodItem.monounsaturatedFat.map { String(format: "%.1f", $0) } ?? "")
        _polyunsaturatedFat = State(initialValue: foodItem.polyunsaturatedFat.map { String(format: "%.1f", $0) } ?? "")

        // Other nutrients (already stored in mg, no conversion needed)
        _cholesterol = State(initialValue: foodItem.cholesterol.map { String(format: "%.0f", $0) } ?? "")
        _sodium = State(initialValue: foodItem.sodium.map { String(format: "%.0f", $0) } ?? "")
        _fiber = State(initialValue: foodItem.fiber.map { String(format: "%.1f", $0) } ?? "")
        _sugar = State(initialValue: foodItem.sugar.map { String(format: "%.1f", $0) } ?? "")

        // Vitamins (stored in their natural units)
        _vitaminA = State(initialValue: foodItem.vitaminA.map { String(format: "%.0f", $0) } ?? "") // mcg
        _vitaminC = State(initialValue: foodItem.vitaminC.map { String(format: "%.1f", $0) } ?? "") // mg
        _vitaminD = State(initialValue: foodItem.vitaminD.map { String(format: "%.0f", $0) } ?? "") // mcg
        _vitaminE = State(initialValue: foodItem.vitaminE.map { String(format: "%.1f", $0) } ?? "") // mg
        _vitaminK = State(initialValue: foodItem.vitaminK.map { String(format: "%.0f", $0) } ?? "") // mcg
        _vitaminB6 = State(initialValue: foodItem.vitaminB6.map { String(format: "%.1f", $0) } ?? "") // mg
        _vitaminB12 = State(initialValue: foodItem.vitaminB12.map { String(format: "%.0f", $0) } ?? "") // mcg
        _folate = State(initialValue: foodItem.folate.map { String(format: "%.0f", $0) } ?? "") // mcg
        _choline = State(initialValue: foodItem.choline.map { String(format: "%.1f", $0) } ?? "") // mg

        // Minerals (stored in mg, display in mg)
        _calcium = State(initialValue: foodItem.calcium.map { String(format: "%.1f", $0) } ?? "")
        _iron = State(initialValue: foodItem.iron.map { String(format: "%.1f", $0) } ?? "")
        _potassium = State(initialValue: foodItem.potassium.map { String(format: "%.1f", $0) } ?? "")
        _magnesium = State(initialValue: foodItem.magnesium.map { String(format: "%.1f", $0) } ?? "")
        _zinc = State(initialValue: foodItem.zinc.map { String(format: "%.1f", $0) } ?? "")

        // Other (stored in mg, display in mg)
        _caffeine = State(initialValue: foodItem.caffeine.map { String(format: "%.1f", $0) } ?? "")
        
        // Base serving
        _servingDescription = State(initialValue: foodItem.defaultServing?.label ?? "serving")
        _gramsPerServing = State(initialValue: foodItem.defaultServing?.gramWeight.map { String(format: "%.0f", $0) } ?? "")
    }

    private var isValid: Bool {
        !foodName.isEmpty &&
        !calories.isEmpty
        // gramsPerServing is now optional (e.g., FatSecret items without weight)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    // Basic Info Card
                    basicInfoCard

                    // Enrichment Button
                    enrichmentCard

                    // Base Serving Card
                    baseServingCard
                    
                    // Portion Sizes Card
                    portionSizesCard

                    // Nutrition Label Card
                    nutritionLabelCard

                    // Metadata Card
                    metadataCard
                }
                .padding()
            }
            .background(Color("SurfacePrimary"))
            .navigationTitle("Edit Food")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        saveChanges()
                    }
                    .disabled(!isValid)
                    .fontWeight(.semibold)
                }
            }
            .sheet(isPresented: $showingEnrichment) {
                NutritionEnrichmentView(foodItem: foodItem) {
                    refreshFromFoodItem()
                }
            }
            .alert("Food Not Found", isPresented: $showError) {
                Button("OK") {
                    dismiss()
                }
            } message: {
                Text("This food item has been deleted.")
            }
            .task {
                guard let sourceID = foodItem.fallbackSourceID else { return }
                fallbackSource = try? modelContext.fetch(
                    FetchDescriptor<FallbackSource>(predicate: #Predicate { $0.id == sourceID })
                ).first
            }
        }
    }

    // MARK: - Card Views

    private var enrichmentCard: some View {
        ElevatedCard(padding: 16, cornerRadius: 20) {
            Button {
                showingEnrichment = true
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "sparkle.magnifyingglass")
                        .font(.title2)
                        .foregroundStyle(Color("BrandAccent"))
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Find Nutrition Data")
                            .font(.headline)
                            .foregroundStyle(.primary)
                        Text("Search USDA, FatSecret, and Open Food Facts to fill in missing fields")
                            .font(.caption)
                            .foregroundStyle(Color("TextSecondary"))
                            .multilineTextAlignment(.leading)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(Color("TextTertiary"))
                }
            }
        }
    }

    private var basicInfoCard: some View {
        ElevatedCard(padding: 16, cornerRadius: 20) {
            VStack(alignment: .leading, spacing: 12) {
                Text("Basic Information")
                    .font(.headline)
                    .foregroundStyle(Color("TextSecondary"))

                TextField("Food Name", text: $foodName)
                    .textFieldStyle(.roundedBorder)
                    .textInputAutocapitalization(.words)

                TextField("Brand (Optional)", text: $brand)
                    .textFieldStyle(.roundedBorder)
                    .textInputAutocapitalization(.words)
            }
        }
    }

    private var baseServingCard: some View {
        ElevatedCard(padding: 16, cornerRadius: 20) {
            VStack(alignment: .leading, spacing: 12) {
                Text("Base Serving")
                    .font(.headline)
                    .foregroundStyle(Color("TextSecondary"))

                TextField("Serving Description", text: $servingDescription)
                    .textFieldStyle(.roundedBorder)
                    .textInputAutocapitalization(.words)

                HStack {
                    Text("Serving Weight (Optional)")
                        .font(.subheadline)
                    Spacer()
                    TextField("0", text: $gramsPerServing)
                        .keyboardType(.decimalPad)
                        .textFieldStyle(.roundedBorder)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 80)
                    Text("g")
                        .foregroundStyle(.secondary)
                }

                Text("All nutrition values below are for: \(servingDescription)" + (gramsPerServing.isEmpty ? "" : " (\(gramsPerServing)g)"))
                    .font(.caption)
                    .foregroundStyle(Color("TextSecondary"))
            }
        }
    }
    
    private var portionSizesCard: some View {
        ElevatedCard(padding: 16, cornerRadius: 20) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Portion Sizes")
                        .font(.headline)
                        .foregroundStyle(Color("TextSecondary"))
                    
                    Spacer()
                    
                    Button {
                        showingAddPortion = true
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .foregroundStyle(Color("BrandAccent"))
                    }
                }
                
                if !foodItem.servingSizes.isEmpty {
                    VStack(spacing: 8) {
                        ForEach(foodItem.servingSizes) { servingSize in
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(servingSize.label)
                                        .font(.subheadline)
                                    if let gramWeight = servingSize.gramWeight {
                                        Text("\(String(format: "%.0f", gramWeight))g")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                
                                Spacer()
                                
                                Button(role: .destructive) {
                                    deletePortionSize(servingSize)
                                } label: {
                                    Image(systemName: "minus.circle.fill")
                                        .foregroundStyle(.red)
                                }
                            }
                            .padding(.vertical, 4)
                        }
                        .id(foodItem.servingSizes.map { $0.id })
                    }
                } else {
                    Text("No additional portion sizes")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 8)
                }
            }
        }
        .sheet(isPresented: $showingAddPortion) {
            addPortionSheet
        }
    }
    
    private var addPortionSheet: some View {
        NavigationStack {
            Form {
                Section("Portion Details") {
                    TextField("Portion Name", text: $newPortionLabel)
                        .textInputAutocapitalization(.words)
                    
                    HStack {
                        Text("Grams")
                        Spacer()
                        TextField("0", text: $newPortionGrams)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 80)
                        Text("g")
                            .foregroundStyle(.secondary)
                    }
                }
                
                Section {
                    Text("Example: \"1 Cup\" weighing 240g")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Add Portion Size")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        showingAddPortion = false
                        clearNewPortionFields()
                    }
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        addNewPortion()
                    }
                    .disabled(newPortionLabel.isEmpty || newPortionGrams.isEmpty)
                }
            }
        }
    }

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
            // Serving info
            Text(servingDescription + (gramsPerServing.isEmpty ? "" : " (\(gramsPerServing)g)"))
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
                TextField("0", text: $calories)
                    .keyboardType(.decimalPad)
                    .font(.system(size: 44, weight: .black))
                    .multilineTextAlignment(.trailing)
                    .frame(width: 120)
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

            // Total Fat
            editableNutrientRow("Total Fat", $fat, "g", bold: true)
            thinDivider()

            // Saturated Fat (indented)
            editableIndentedNutrientRow("Saturated Fat", $saturatedFat, "g")
            thinDivider()

            // Trans Fat (indented)
            editableIndentedNutrientRow("Trans Fat", $transFat, "g")
            thinDivider()

            // Monounsaturated Fat (indented)
            editableIndentedNutrientRow("Monounsaturated Fat", $monounsaturatedFat, "g")
            thinDivider()

            // Polyunsaturated Fat (indented)
            editableIndentedNutrientRow("Polyunsaturated Fat", $polyunsaturatedFat, "g")
            thinDivider()

            // Cholesterol
            editableNutrientRow("Cholesterol", $cholesterol, "mg", bold: true)
            thinDivider()

            // Sodium
            editableNutrientRow("Sodium", $sodium, "mg", bold: true)
            thinDivider()

            // Total Carbohydrate
            editableNutrientRow("Total Carbohydrate", $carbs, "g", bold: true)
            thinDivider()

            // Fiber (indented)
            editableIndentedNutrientRow("Dietary Fiber", $fiber, "g")
            thinDivider()

            // Sugar (indented)
            editableIndentedNutrientRow("Total Sugars", $sugar, "g")
            thinDivider()

            // Protein
            editableNutrientRow("Protein", $protein, "g", bold: true)

            // Heavy divider before vitamins/minerals
            Rectangle()
                .fill(Color("TextPrimary"))
                .frame(height: 8)
                .padding(.vertical, 4)

            // Vitamins and Minerals
            VStack(spacing: 0) {
                editableNutrientRow("Vitamin D", $vitaminD, "mcg")
                thinDivider()

                editableNutrientRow("Calcium", $calcium, "mg")
                thinDivider()

                editableNutrientRow("Iron", $iron, "mg")
                thinDivider()

                editableNutrientRow("Potassium", $potassium, "mg")
                thinDivider()

                editableNutrientRow("Vitamin A", $vitaminA, "mcg")
                thinDivider()

                editableNutrientRow("Vitamin C", $vitaminC, "mg")
                thinDivider()

                editableNutrientRow("Vitamin E", $vitaminE, "mg")
                thinDivider()

                editableNutrientRow("Vitamin K", $vitaminK, "mcg")
                thinDivider()

                editableNutrientRow("Vitamin B6", $vitaminB6, "mg")
                thinDivider()

                editableNutrientRow("Vitamin B12", $vitaminB12, "mcg")
                thinDivider()

                editableNutrientRow("Folate", $folate, "mcg")
                thinDivider()

                editableNutrientRow("Choline", $choline, "mg")
                thinDivider()

                editableNutrientRow("Magnesium", $magnesium, "mg")
                thinDivider()

                editableNutrientRow("Zinc", $zinc, "mg")
                thinDivider()

                editableNutrientRow("Caffeine", $caffeine, "mg")
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

    private var metadataCard: some View {
        ElevatedCard(padding: 16, cornerRadius: 20) {
            VStack(alignment: .leading, spacing: 12) {
                Text("Metadata")
                    .font(.headline)
                    .foregroundStyle(Color("TextSecondary"))

                HStack {
                    Text("Source")
                    Spacer()
                    Text(foodItem.source)
                        .foregroundStyle(.secondary)
                }

                if let source = fallbackSource {
                    HStack {
                        Text("Enriched from")
                        Spacer()
                        VStack(alignment: .trailing, spacing: 2) {
                            Text(source.displayLabel)
                                .foregroundStyle(.secondary)
                            if let conf = source.confidenceLabel {
                                Text(conf)
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                            }
                        }
                    }
                }

                HStack {
                    Text("Date Added")
                    Spacer()
                    Text(foodItem.dateAdded.formatted(date: .abbreviated, time: .omitted))
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: - Helper Views

    private func editableNutrientRow(
        _ label: String,
        _ value: Binding<String>,
        _ unit: String,
        bold: Bool = false
    ) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 16) {
            Text(label)
                .font(.system(size: 14))
                .fontWeight(bold ? .black : .regular)

            Spacer()

            HStack(spacing: 4) {
                TextField("0", text: value)
                    .keyboardType(.decimalPad)
                    .font(.system(size: 14))
                    .fontWeight(bold ? .bold : .regular)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 60)

                Text(unit)
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
            }

            // % DV display (calculated, not editable)
            if let percent = calculatePercentDV(value: value.wrappedValue, for: label) {
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

    private func editableIndentedNutrientRow(
        _ label: String,
        _ value: Binding<String>,
        _ unit: String
    ) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 16) {
            Text(label)
                .font(.system(size: 14))
                .padding(.leading, 20)

            Spacer()

            HStack(spacing: 4) {
                TextField("0", text: value)
                    .keyboardType(.decimalPad)
                    .font(.system(size: 14))
                    .multilineTextAlignment(.trailing)
                    .frame(width: 60)

                Text(unit)
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
            }

            // % DV display (calculated, not editable)
            if let percent = calculatePercentDV(value: value.wrappedValue, for: label) {
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

    private func thinDivider() -> some View {
        Rectangle()
            .fill(Color("TextPrimary"))
            .frame(height: 1)
    }

    // MARK: - Helper Functions

    private func calculatePercentDV(value: String, for label: String) -> Int? {
        guard let numValue = Double(value), numValue > 0,
              let dv = fdaDailyValue(for: label), dv > 0 else { return nil }
        return Int((numValue / dv * 100).rounded())
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

    // MARK: - Portion Size Management
    
    private func addNewPortion() {
        guard let grams = Double(newPortionGrams),
              grams > 0,
              !newPortionLabel.isEmpty else {
            showingAddPortion = false
            clearNewPortionFields()
            return
        }
        
        let portionUnit = ServingSizeParser.parse(newPortionLabel).flatMap {
            $0.unit == .serving ? nil : $0.unit.rawValue
        } ?? ServingSizeParser.parseUnit(newPortionLabel)?.rawValue
        let newServingSize = ServingSize(
            label: newPortionLabel,
            gramWeight: grams,
            isDefault: false,
            sortOrder: foodItem.servingSizes.count,
            unit: portionUnit
        )
        newServingSize.foodItem = foodItem
        
        modelContext.insert(newServingSize)
        foodItem.servingSizes.append(newServingSize)
        
        try? modelContext.save()
        
        showingAddPortion = false
        clearNewPortionFields()
    }
    
    private func deletePortionSize(_ servingSize: ServingSize) {
        // First, find all FoodLog entries that reference this ServingSize and set their servingSize to nil
        let servingSizeId = servingSize.id
        let descriptor = FetchDescriptor<FoodLog>(
            predicate: #Predicate<FoodLog> { log in
                log.servingSize?.id == servingSizeId
            }
        )
        
        do {
            let affectedLogs = try modelContext.fetch(descriptor)
            for log in affectedLogs {
                log.servingSize = nil  // Nullify the reference
            }
            
            // Remove from the array
            if let index = foodItem.servingSizes.firstIndex(where: { $0.id == servingSize.id }) {
                foodItem.servingSizes.remove(at: index)
            }
            
            // Delete the ServingSize
            modelContext.delete(servingSize)
            
            // Save all changes
            try modelContext.save()
        } catch {
            print("Error deleting portion size: \(error)")
        }
    }
    
    private func clearNewPortionFields() {
        newPortionLabel = ""
        newPortionGrams = ""
    }
    
    private func refreshFromFoodItem() {
        saturatedFat       = foodItem.saturatedFat.map       { String(format: "%.1f", $0) } ?? ""
        transFat           = foodItem.transFat.map           { String(format: "%.1f", $0) } ?? ""
        monounsaturatedFat = foodItem.monounsaturatedFat.map { String(format: "%.1f", $0) } ?? ""
        polyunsaturatedFat = foodItem.polyunsaturatedFat.map { String(format: "%.1f", $0) } ?? ""
        cholesterol        = foodItem.cholesterol.map        { String(format: "%.0f", $0) } ?? ""
        sodium             = foodItem.sodium.map             { String(format: "%.0f", $0) } ?? ""
        fiber              = foodItem.fiber.map              { String(format: "%.1f", $0) } ?? ""
        sugar              = foodItem.sugar.map              { String(format: "%.1f", $0) } ?? ""
        vitaminA           = foodItem.vitaminA.map           { String(format: "%.0f", $0) } ?? ""
        vitaminC           = foodItem.vitaminC.map           { String(format: "%.1f", $0) } ?? ""
        vitaminD           = foodItem.vitaminD.map           { String(format: "%.0f", $0) } ?? ""
        vitaminE           = foodItem.vitaminE.map           { String(format: "%.1f", $0) } ?? ""
        vitaminK           = foodItem.vitaminK.map           { String(format: "%.0f", $0) } ?? ""
        vitaminB6          = foodItem.vitaminB6.map          { String(format: "%.1f", $0) } ?? ""
        vitaminB12         = foodItem.vitaminB12.map         { String(format: "%.0f", $0) } ?? ""
        folate             = foodItem.folate.map             { String(format: "%.0f", $0) } ?? ""
        choline            = foodItem.choline.map            { String(format: "%.1f", $0) } ?? ""
        calcium            = foodItem.calcium.map            { String(format: "%.1f", $0) } ?? ""
        iron               = foodItem.iron.map               { String(format: "%.1f", $0) } ?? ""
        potassium          = foodItem.potassium.map          { String(format: "%.1f", $0) } ?? ""
        magnesium          = foodItem.magnesium.map          { String(format: "%.1f", $0) } ?? ""
        zinc               = foodItem.zinc.map               { String(format: "%.1f", $0) } ?? ""
        caffeine           = foodItem.caffeine.map           { String(format: "%.1f", $0) } ?? ""
    }

    private func saveChanges() {
        // Verify the food item still exists
        let itemId = foodItem.id
        let descriptor = FetchDescriptor<FoodItem>(
            predicate: #Predicate<FoodItem> { item in
                item.id == itemId
            }
        )
        guard let validFood = try? modelContext.fetch(descriptor).first else {
            showError = true
            return
        }

        // Helper function to parse optional Double values
        let parseOptionalDouble: (String) -> Double? = { str in
            guard !str.isEmpty, let val = Double(str) else { return nil }
            return val
        }

        // Update basic info on the valid food item
        validFood.name = foodName
        validFood.brand = brand.isEmpty ? nil : brand

        // Update macros (stored directly as per-serving now - no conversion needed!)
        if let cal = Double(calories) {
            validFood.calories = cal
        }
        if let prot = Double(protein) {
            validFood.protein = prot
        }
        if let carb = Double(carbs) {
            validFood.carbs = carb
        }
        if let f = Double(fat) {
            validFood.fat = f
        }

        // Update fats
        validFood.saturatedFat = saturatedFat.isEmpty ? nil : Double(saturatedFat)
        validFood.transFat = transFat.isEmpty ? nil : Double(transFat)
        validFood.monounsaturatedFat = monounsaturatedFat.isEmpty ? nil : Double(monounsaturatedFat)
        validFood.polyunsaturatedFat = polyunsaturatedFat.isEmpty ? nil : Double(polyunsaturatedFat)

        // Update other nutrients (stored in mg)
        validFood.cholesterol = parseOptionalDouble(cholesterol)
        validFood.sodium = parseOptionalDouble(sodium)
        validFood.fiber = fiber.isEmpty ? nil : Double(fiber)
        validFood.sugar = sugar.isEmpty ? nil : Double(sugar)

        // Update vitamins (A, D, K, B12, Folate in mcg; C, E, B6, Choline in mg)
        validFood.vitaminA = parseOptionalDouble(vitaminA) // mcg
        validFood.vitaminC = parseOptionalDouble(vitaminC) // mg
        validFood.vitaminD = parseOptionalDouble(vitaminD) // mcg
        validFood.vitaminE = parseOptionalDouble(vitaminE) // mg
        validFood.vitaminK = parseOptionalDouble(vitaminK) // mcg
        validFood.vitaminB6 = parseOptionalDouble(vitaminB6) // mg
        validFood.vitaminB12 = parseOptionalDouble(vitaminB12) // mcg
        validFood.folate = parseOptionalDouble(folate) // mcg
        validFood.choline = parseOptionalDouble(choline) // mg

        // Update minerals (stored in mg)
        validFood.calcium = parseOptionalDouble(calcium)
        validFood.iron = parseOptionalDouble(iron)
        validFood.potassium = parseOptionalDouble(potassium)
        validFood.magnesium = parseOptionalDouble(magnesium)
        validFood.zinc = parseOptionalDouble(zinc)

        // Update other (stored in mg)
        validFood.caffeine = parseOptionalDouble(caffeine)

        // Update or create the default serving
        if let defaultServing = validFood.defaultServing {
            let oldGramWeight = defaultServing.gramWeight
            let oldUnit = defaultServing.unit.flatMap { ServingUnit(rawValue: $0) }

            let newGramWeight = gramsPerServing.isEmpty ? nil : Double(gramsPerServing)
            defaultServing.label = servingDescription
            defaultServing.gramWeight = newGramWeight

            // Always keep unit in sync with the label so resolvedQuantity stays correct.
            let newUnit = ServingSizeParser.parse(servingDescription).flatMap {
                $0.unit == .serving ? nil : $0.unit.rawValue
            } ?? ServingSizeParser.parseUnit(servingDescription)?.rawValue
            defaultServing.unit = newUnit

            // When the old serving was a bare-gram serving (unit=gram, gramWeight≤1 or nil)
            // and we're now assigning a real gramWeight, any FoodLog that references it stored
            // quantity as grams (1 serving = 1g). Rescale to new serving count so calorie
            // math remains accurate.
            let wasGramPerServing = (oldUnit == .gram) && ((oldGramWeight ?? 0) <= 1)
            if wasGramPerServing, let newGW = newGramWeight, newGW > 1 {
                let servingId = defaultServing.id
                let descriptor = FetchDescriptor<FoodLog>(
                    predicate: #Predicate<FoodLog> { $0.servingSize?.id == servingId }
                )
                if let logs = try? modelContext.fetch(descriptor) {
                    for log in logs {
                        log.quantity = log.quantity / newGW
                    }
                }
            }
        } else {
            // Create new default serving
            let defaultUnit = ServingSizeParser.parse(servingDescription).flatMap {
                $0.unit == .serving ? nil : $0.unit.rawValue
            } ?? ServingSizeParser.parseUnit(servingDescription)?.rawValue
            let defaultServing = ServingSize(
                label: servingDescription,
                gramWeight: gramsPerServing.isEmpty ? nil : Double(gramsPerServing),
                isDefault: true,
                sortOrder: 0,
                unit: defaultUnit
            )
            defaultServing.foodItem = validFood
            modelContext.insert(defaultServing)
            validFood.servingSizes.append(defaultServing)
        }

        // Save changes
        try? modelContext.save()
        dismiss()
    }
}
