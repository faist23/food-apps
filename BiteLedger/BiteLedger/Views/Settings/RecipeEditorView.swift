//
//  RecipeEditorView.swift
//  BiteLedger
//
//  Created by Craig Faist on 2/16/26.
//

import SwiftUI
import SwiftData
import BiteLedgerCore

// MARK: - RecipeEditorView

struct RecipeEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    /// nil = creating a new recipe; non-nil = editing an existing one.
    let recipe: Recipe?

    // MARK: Form State

    @State private var recipeName: String
    @State private var servingsYield: Double
    @State private var servingsYieldText: String
    @State private var sourceURL: String
    @State private var directions: [String]

    /// Local working copy of the ingredient list. Sourced from the recipe on appear;
    /// written back to the model only when Save is tapped.
    @State private var pendingIngredients: [PendingIngredient] = []

    // MARK: UI State

    @State private var showIngredientPicker = false
    @State private var showImportSheet = false
    @State private var unmatchedHints: [ImportedRecipeData.UnmatchedHint] = []
    @State private var hintBeingSearched: ImportedRecipeData.UnmatchedHint? = nil
    @State private var nutritionDisplay: NutritionDisplay = .perServing
    /// Per-serving nutrition imported from the recipe website (Schema.org). When set,
    /// this takes priority over ingredient-based calculation.
    @State private var importedNutrition: RecipeNutrition? = nil
    @State private var showAddDirection = false
    @State private var showEditDirection = false
    @State private var editingDirectionIndex: Int? = nil
    @State private var editingDirectionText: String = ""
    @State private var newDirectionText: String = ""

    // MARK: - Supporting Types

    enum NutritionDisplay: String, CaseIterable {
        case perServing   = "Per Serving"
        case wholeRecipe  = "Whole Recipe"
    }

    struct PendingIngredient: Identifiable {
        let id: UUID = UUID()
        let food: FoodItem
        let serving: ServingSize
        var quantity: Double
        /// Original recipe text (e.g. "1.5 lbs chicken breast"). Shown instead of qty×serving when set.
        var rawText: String? = nil
        /// Parsed recipe quantity (e.g. 1.5 for "1.5 lbs"). Stored on RecipeIngredient for future display.
        var recipeQuantity: Double? = nil
        /// Parsed recipe unit (e.g. "lbs"). Stored on RecipeIngredient for future display.
        var recipeUnit: String? = nil
    }

    // MARK: - Init

    init(recipe: Recipe?) {
        self.recipe = recipe
        let yield = recipe?.servingsYield ?? 4.0
        _recipeName       = State(initialValue: recipe?.name ?? "")
        _servingsYield    = State(initialValue: yield)
        _servingsYieldText = State(initialValue: yield.truncatingRemainder(dividingBy: 1) == 0
                                   ? String(Int(yield))
                                   : String(format: "%.1f", yield))
        _sourceURL        = State(initialValue: recipe?.sourceURL ?? "")
        _directions       = State(initialValue: recipe?.directions ?? [])
        _importedNutrition = State(initialValue: recipe?.importedNutrition)
    }

    // MARK: - Computed

    private var isValid: Bool {
        !recipeName.trimmingCharacters(in: .whitespaces).isEmpty && servingsYield > 0
    }

    /// Per-serving nutrition for the recipe.
    /// Uses website-scraped data when available; otherwise sums ingredients.
    private var calculatedPerServing: NutritionCalculator.Result {
        if let n = importedNutrition {
            return NutritionCalculator.Result(
                calories:     n.calories,
                protein:      n.protein,
                carbs:        n.carbs,
                fat:          n.fat,
                fiber:        n.fiber,
                sugar:        n.sugar,
                saturatedFat: n.saturatedFat,
                sodium:       n.sodium,
                cholesterol:  n.cholesterol,
                potassium:    n.potassium,
                calcium:      n.calcium,
                iron:         n.iron,
                vitaminA:     n.vitaminA,
                vitaminC:     n.vitaminC
            )
        }
        guard servingsYield > 0 else { return .zero }
        let total = pendingIngredients.reduce(NutritionCalculator.Result.zero) { sum, pending in
            sum + NutritionCalculator.preview(
                food: pending.food,
                serving: pending.serving,
                quantity: pending.quantity
            )
        }
        return total.scaled(by: 1.0 / servingsYield)
    }

    private var displayedNutrition: NutritionCalculator.Result {
        switch nutritionDisplay {
        case .perServing:  return calculatedPerServing
        case .wholeRecipe: return calculatedPerServing.scaled(by: servingsYield)
        }
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    basicInfoCard
                    ingredientsCard
                    directionsCard
                    nutritionLabelCard
                    if recipe != nil { metadataCard }
                }
                .padding()
            }
            .background(Color("SurfacePrimary"))
            .navigationTitle(recipe == nil ? "New Recipe" : "Edit Recipe")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        showImportSheet = true
                    } label: {
                        Label("Import from Web", systemImage: "link")
                    }
                    .foregroundStyle(Color("BrandAccent"))
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { saveChanges() }
                        .disabled(!isValid)
                        .fontWeight(.semibold)
                }
            }
            .onAppear { loadIngredientsFromRecipe() }
            .sheet(isPresented: $showIngredientPicker, onDismiss: { hintBeingSearched = nil }) {
                RecipeIngredientPickerView(
                    initialSearch:   hintBeingSearched?.searchTerm ?? "",
                    initialQuantity: hintBeingSearched?.quantity   ?? 1.0
                ) { food, serving, quantity in
                    pendingIngredients.append(
                        PendingIngredient(food: food, serving: serving, quantity: quantity)
                    )
                    // Remove the hint that triggered this "Find"
                    if let hint = hintBeingSearched {
                        unmatchedHints.removeAll { $0.id == hint.id }
                    }
                    hintBeingSearched = nil
                }
            }
            .sheet(isPresented: $showImportSheet) {
                ImportRecipeView { imported in
                    applyImport(imported)
                }
            }
            .sheet(isPresented: $showAddDirection) {
                addDirectionSheet
            }
            .sheet(isPresented: $showEditDirection) {
                editDirectionSheet
            }
        }
    }

    // MARK: - Card: Basic Info

    private var basicInfoCard: some View {
        ElevatedCard(padding: 16, cornerRadius: 20) {
            VStack(alignment: .leading, spacing: 12) {
                Text("Recipe Details")
                    .font(.headline)
                    .foregroundStyle(Color("TextSecondary"))

                TextField("Recipe Name", text: $recipeName)
                    .textFieldStyle(.roundedBorder)
                    .textInputAutocapitalization(.words)

                HStack {
                    Text("Makes")
                        .font(.subheadline)
                    Spacer()
                    TextField("4", text: $servingsYieldText)
                        .keyboardType(.decimalPad)
                        .textFieldStyle(.roundedBorder)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 70)
                        .onChange(of: servingsYieldText) { _, newValue in
                            if let parsed = Double(newValue), parsed > 0 {
                                servingsYield = parsed
                            }
                        }
                    Text("serving\(servingsYield == 1 ? "" : "s")")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                if !sourceURL.isEmpty {
                    HStack(spacing: 6) {
                        Image(systemName: "link")
                            .font(.caption)
                            .foregroundStyle(.orange)
                        Text("Based on \(sourceDomain(from: sourceURL))")
                            .font(.caption)
                            .foregroundStyle(.orange)
                            .lineLimit(1)
                        Spacer()
                        Button {
                            sourceURL = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    // MARK: - Card: Ingredients

    private var ingredientsCard: some View {
        ElevatedCard(padding: 16, cornerRadius: 20) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Ingredients")
                        .font(.headline)
                        .foregroundStyle(Color("TextSecondary"))
                    Spacer()
                    Button {
                        showIngredientPicker = true
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .foregroundStyle(Color("BrandAccent"))
                    }
                    .buttonStyle(.plain)
                }

                if pendingIngredients.isEmpty {
                    Text("No ingredients added yet. Tap + to add.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 8)
                } else {
                    VStack(spacing: 0) {
                        ForEach(Array(pendingIngredients.enumerated()), id: \.element.id) { index, ingredient in
                            VStack(spacing: 0) {
                                ingredientRow(ingredient, at: index)
                                if index < pendingIngredients.count - 1 {
                                    thinDivider()
                                }
                            }
                        }
                    }

                    // Unmatched hints from web import
                    if !unmatchedHints.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            thinDivider()
                            Text("Not yet added (from import):")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .padding(.top, 4)
                            ForEach(unmatchedHints) { hint in
                                HStack(spacing: 6) {
                                    Image(systemName: "magnifyingglass")
                                        .font(.caption2)
                                        .foregroundStyle(.orange)
                                    Text(hint.raw)
                                        .font(.caption)
                                        .foregroundStyle(.orange)
                                    Spacer()
                                    Button {
                                        hintBeingSearched = hint
                                        showIngredientPicker = true
                                    } label: {
                                        Text("Find")
                                            .font(.caption)
                                            .foregroundStyle(Color("BrandAccent"))
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }

                    // Ingredient subtotal — only meaningful when all ingredients use qty×serving math.
                    // When website nutrition is present, or any ingredient has rawText (recipe units),
                    // the sum is wrong. Show a note instead.
                    if importedNutrition != nil {
                        HStack {
                            Image(systemName: "checkmark.seal.fill").foregroundStyle(.green).font(.caption2)
                            Text("Nutrition from website — see label below")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Spacer()
                        }
                        .padding(.top, 8)
                    } else {
                        let hasRawIngredients = pendingIngredients.contains { $0.rawText != nil }
                        if !hasRawIngredients {
                            let total = pendingIngredients.reduce(NutritionCalculator.Result.zero) { sum, p in
                                sum + NutritionCalculator.preview(food: p.food, serving: p.serving, quantity: p.quantity)
                            }
                            HStack {
                                Text("Total (all servings)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Text("\(Int(total.calories)) cal")
                                    .font(.caption)
                                    .foregroundStyle(.blue)
                            }
                            .padding(.top, 8)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func ingredientRow(_ ingredient: PendingIngredient, at index: Int) -> some View {
        HStack(alignment: .center, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                if let raw = ingredient.rawText, !raw.isEmpty {
                    // Show the original recipe line (e.g. "1.5 lbs chicken breast")
                    Text(raw)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .lineLimit(2)
                    Text(ingredient.food.name)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                } else {
                    Text(ingredient.food.name)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .lineLimit(1)
                    let qtyStr = ingredient.quantity.truncatingRemainder(dividingBy: 1) == 0
                        ? "\(Int(ingredient.quantity))"
                        : String(format: "%.2g", ingredient.quantity)
                    Text("\(qtyStr) × \(ingredient.serving.label)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            // Only show per-ingredient calories when quantity×serving is meaningful.
            // When rawText is set (URL import), the quantity is in recipe units (lbs, cups)
            // not serving-count units, so the math is wrong — hide it.
            if ingredient.rawText == nil {
                let preview = NutritionCalculator.preview(
                    food: ingredient.food,
                    serving: ingredient.serving,
                    quantity: ingredient.quantity
                )
                Text("\(Int(preview.calories)) cal")
                    .font(.caption2)
                    .foregroundStyle(.blue)
            }

            Button(role: .destructive) {
                pendingIngredients.remove(at: index)
            } label: {
                Image(systemName: "minus.circle.fill")
                    .foregroundStyle(.red)
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 6)
    }

    // MARK: - Card: Directions

    private var directionsCard: some View {
        ElevatedCard(padding: 16, cornerRadius: 20) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Directions")
                        .font(.headline)
                        .foregroundStyle(Color("TextSecondary"))
                    Spacer()
                    Button {
                        newDirectionText = ""
                        showAddDirection = true
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .foregroundStyle(Color("BrandAccent"))
                    }
                    .buttonStyle(.plain)
                }

                if directions.isEmpty {
                    Text("No steps added yet. Tap + to add directions.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 8)
                } else {
                    VStack(spacing: 0) {
                        ForEach(Array(directions.enumerated()), id: \.offset) { index, step in
                            VStack(spacing: 0) {
                                directionRow(step, at: index)
                                if index < directions.count - 1 {
                                    thinDivider()
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func directionRow(_ step: String, at index: Int) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text("\(index + 1).")
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundStyle(Color("BrandAccent"))
                .frame(width: 24, alignment: .leading)

            Text(step)
                .font(.subheadline)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
                .onTapGesture {
                    editingDirectionIndex = index
                    editingDirectionText = step
                    showEditDirection = true
                }

            Spacer()

            Button(role: .destructive) {
                directions.remove(at: index)
            } label: {
                Image(systemName: "minus.circle.fill")
                    .foregroundStyle(.red)
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 8)
    }

    // MARK: - Card: Nutrition Label

    private var nutritionLabelCard: some View {
        ElevatedCard(padding: 0, cornerRadius: 20) {
            VStack(alignment: .leading, spacing: 0) {
                // Header
                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .firstTextBaseline) {
                        Text("Nutrition Facts")
                            .font(.system(size: 32, weight: .black))
                            .foregroundStyle(Color("TextPrimary"))
                        Spacer()
                        if importedNutrition != nil {
                            Label("From website", systemImage: "checkmark.seal.fill")
                                .font(.caption2)
                                .foregroundStyle(.green)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 3)
                                .background(Color.green.opacity(0.12))
                                .clipShape(Capsule())
                        }
                    }
                    Rectangle()
                        .fill(Color("TextPrimary"))
                        .frame(height: 8)
                }
                .padding(.horizontal, 16)
                .padding(.top, 16)

                // Per Serving / Whole Recipe toggle
                Picker("Display", selection: $nutritionDisplay) {
                    ForEach(NutritionDisplay.allCases, id: \.self) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 16)
                .padding(.top, 12)

                VStack(spacing: 0) {
                    nutritionFactsContent
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
            }
        }
    }

    private var nutritionFactsContent: some View {
        let n = displayedNutrition
        let serving = nutritionDisplay == .perServing
            ? "1 serving of \(recipeName.isEmpty ? "recipe" : recipeName)"
            : "Whole recipe (\(servingsYieldText) servings)"

        return VStack(spacing: 0) {
            Text(serving)
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
                Text(n.calories.truncatingRemainder(dividingBy: 1) == 0
                     ? "\(Int(n.calories))"
                     : String(format: "%.0f", n.calories))
                    .font(.system(size: 44, weight: .black))
            }
            .padding(.vertical, 4)

            Rectangle().fill(Color("TextPrimary")).frame(height: 6).padding(.vertical, 4)

            HStack { Spacer(); Text("% Daily Value*").font(.system(size: 12, weight: .bold)) }
                .padding(.bottom, 4)

            thinDivider()
            readOnlyRow("Total Fat",          n.fat,          "g",  dv: 78,   bold: true)
            thinDivider()
            readOnlyRowIndented("Saturated Fat",  n.saturatedFat, "g",  dv: 20)
            thinDivider()
            readOnlyRowIndented("Trans Fat",      n.transFat,     "g",  dv: nil)
            thinDivider()
            readOnlyRow("Cholesterol",         n.cholesterol,  "mg", dv: 300,  bold: true)
            thinDivider()
            readOnlyRow("Sodium",              n.sodium,       "mg", dv: 2300, bold: true)
            thinDivider()
            readOnlyRow("Total Carbohydrate",  n.carbs,        "g",  dv: 275,  bold: true)
            thinDivider()
            readOnlyRowIndented("Dietary Fiber", n.fiber,       "g",  dv: 28)
            thinDivider()
            readOnlyRowIndented("Total Sugars",  n.sugar,       "g",  dv: nil)
            thinDivider()
            readOnlyRow("Protein",             n.protein,      "g",  dv: 50,   bold: true)

            Rectangle().fill(Color("TextPrimary")).frame(height: 8).padding(.vertical, 4)

            Group {
                readOnlyRow("Vitamin D",  n.vitaminD,  "mcg", dv: 20)
                thinDivider()
                readOnlyRow("Calcium",    n.calcium,   "mg",  dv: 1300)
                thinDivider()
                readOnlyRow("Iron",       n.iron,      "mg",  dv: 18)
                thinDivider()
                readOnlyRow("Potassium",  n.potassium, "mg",  dv: 4700)
                thinDivider()
                readOnlyRow("Vitamin A",  n.vitaminA,  "mcg", dv: 900)
                thinDivider()
                readOnlyRow("Vitamin C",  n.vitaminC,  "mg",  dv: 90)
            }

            Rectangle().fill(Color("TextPrimary")).frame(height: 4).padding(.top, 4)

            Text("* The % Daily Value (DV) tells you how much a nutrient in a serving of food contributes to a daily diet. 2,000 calories a day is used for general nutrition advice.")
                .font(.system(size: 9))
                .foregroundStyle(Color("TextSecondary"))
                .padding(.top, 8)
                .fixedSize(horizontal: false, vertical: true)

            if importedNutrition != nil {
                Text("Nutrition sourced from the recipe website.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.top, 8)
            } else if pendingIngredients.isEmpty {
                Text("Add ingredients above to see calculated nutrition.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.top, 8)
            }
        }
    }

    // MARK: - Card: Metadata

    private var metadataCard: some View {
        ElevatedCard(padding: 16, cornerRadius: 20) {
            VStack(alignment: .leading, spacing: 12) {
                Text("Metadata")
                    .font(.headline)
                    .foregroundStyle(Color("TextSecondary"))

                if let added = recipe?.dateAdded {
                    HStack {
                        Text("Date Added")
                        Spacer()
                        Text(added.formatted(date: .abbreviated, time: .omitted))
                            .foregroundStyle(.secondary)
                    }
                }

                if let url = recipe?.sourceURL, !url.isEmpty {
                    HStack {
                        Text("Source")
                        Spacer()
                        Link(sourceDomain(from: url), destination: URL(string: url) ?? URL(string: "https://example.com")!)
                            .font(.subheadline)
                            .foregroundStyle(.orange)
                            .lineLimit(1)
                    }
                }
            }
        }
    }

    // MARK: - Direction Sheets

    private var addDirectionSheet: some View {
        NavigationStack {
            VStack(spacing: 0) {
                TextEditor(text: $newDirectionText)
                    .padding()
                    .frame(minHeight: 120)
                Divider()
                Text("Describe one step clearly. You can edit steps by tapping them.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding()
                Spacer()
            }
            .navigationTitle("Add Step")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        newDirectionText = ""
                        showAddDirection = false
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        let trimmed = newDirectionText.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !trimmed.isEmpty { directions.append(trimmed) }
                        newDirectionText = ""
                        showAddDirection = false
                    }
                    .disabled(newDirectionText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .fontWeight(.semibold)
                }
            }
        }
    }

    private var editDirectionSheet: some View {
        NavigationStack {
            VStack(spacing: 0) {
                TextEditor(text: $editingDirectionText)
                    .padding()
                    .frame(minHeight: 120)
                Divider()
                Spacer()
            }
            .navigationTitle("Edit Step")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { showEditDirection = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        if let index = editingDirectionIndex {
                            let trimmed = editingDirectionText.trimmingCharacters(in: .whitespacesAndNewlines)
                            if !trimmed.isEmpty { directions[index] = trimmed }
                        }
                        showEditDirection = false
                    }
                    .disabled(editingDirectionText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .fontWeight(.semibold)
                }
            }
        }
    }

    // MARK: - Helper Views

    private func thinDivider() -> some View {
        Rectangle()
            .fill(Color("TextPrimary"))
            .frame(height: 1)
    }

    @ViewBuilder
    private func readOnlyRow(
        _ label: String,
        _ value: Double?,
        _ unit: String,
        dv: Double?,
        bold: Bool = false
    ) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text(label)
                .font(.system(size: 14))
                .fontWeight(bold ? .black : .regular)

            Spacer()

            if let value {
                Text(value.truncatingRemainder(dividingBy: 1) == 0
                     ? "\(Int(value))\(unit)"
                     : String(format: "%.1f\(unit)", value))
                    .font(.system(size: 14))
                    .fontWeight(bold ? .bold : .regular)
            } else {
                Text("—")
                    .font(.system(size: 14))
                    .foregroundStyle(.tertiary)
            }

            if let value, let dv, dv > 0 {
                Text("\(Int((value / dv * 100).rounded()))%")
                    .font(.system(size: 13))
                    .fontWeight(.light)
                    .foregroundStyle(Color("TextSecondary"))
                    .frame(width: 50, alignment: .trailing)
            } else {
                Text("").frame(width: 50)
            }
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private func readOnlyRowIndented(
        _ label: String,
        _ value: Double?,
        _ unit: String,
        dv: Double?
    ) -> some View {
        readOnlyRow(label, value, unit, dv: dv)
            .padding(.leading, 20)
    }

    // MARK: - Helpers

    private func sourceDomain(from urlString: String) -> String {
        guard let url = URL(string: urlString), let host = url.host else { return urlString }
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }

    private func loadIngredientsFromRecipe() {
        guard let recipe else { return }
        pendingIngredients = recipe.sortedIngredients.compactMap { ingredient in
            guard let food = ingredient.foodItem else { return nil }
            let serving = ingredient.servingSize ?? food.defaultServing ?? food.servingSizes.first
            guard let serving else { return nil }
            return PendingIngredient(food: food, serving: serving,
                                     quantity: ingredient.quantity, rawText: ingredient.rawText,
                                     recipeQuantity: ingredient.recipeQuantity,
                                     recipeUnit: ingredient.recipeUnit)
        }
    }

    // MARK: - Apply Import

    private func applyImport(_ imported: ImportedRecipeData) {
        recipeName         = imported.name
        let y              = imported.servingsYield
        servingsYield      = y
        servingsYieldText  = y.truncatingRemainder(dividingBy: 1) == 0
                             ? String(Int(y)) : String(format: "%.1f", y)
        sourceURL          = imported.sourceURL
        directions         = imported.directions
        unmatchedHints     = imported.unmatchedIngredients
        importedNutrition  = imported.nutrition

        for item in imported.matchedIngredients {
            pendingIngredients.append(
                PendingIngredient(food: item.food, serving: item.serving,
                                  quantity: item.quantity, rawText: item.rawText,
                                  recipeQuantity: item.quantity, recipeUnit: item.unit)
            )
        }
    }

    // MARK: - Save

    private func saveChanges() {
        let trimmedName = recipeName.trimmingCharacters(in: .whitespaces)
        guard !trimmedName.isEmpty, servingsYield > 0 else { return }

        let nutrition = calculatedPerServing
        let urlToStore = sourceURL.trimmingCharacters(in: .whitespaces).isEmpty ? nil : sourceURL.trimmingCharacters(in: .whitespaces)

        if let existing = recipe {
            // --- UPDATE EXISTING RECIPE ---
            existing.name = trimmedName
            existing.servingsYield = servingsYield
            existing.sourceURL = urlToStore
            existing.directions = directions
            existing.importedNutrition = importedNutrition

            // Replace ingredient list
            for old in existing.ingredients { modelContext.delete(old) }
            for (index, pending) in pendingIngredients.enumerated() {
                let ingredient = RecipeIngredient(quantity: pending.quantity, sortOrder: index)
                ingredient.foodItem       = pending.food
                ingredient.servingSize    = pending.serving
                ingredient.rawText        = pending.rawText
                ingredient.recipeQuantity = pending.recipeQuantity
                ingredient.recipeUnit     = pending.recipeUnit
                ingredient.recipe         = existing
                modelContext.insert(ingredient)
            }

            // Update the associated FoodItem nutrition
            if let food = existing.foodItem {
                food.name           = trimmedName
                food.calories       = nutrition.calories
                food.protein        = nutrition.protein
                food.carbs          = nutrition.carbs
                food.fat            = nutrition.fat
                food.fiber          = nutrition.fiber
                food.sugar          = nutrition.sugar
                food.saturatedFat   = nutrition.saturatedFat
                food.transFat       = nutrition.transFat
                food.monounsaturatedFat = nutrition.monounsaturatedFat
                food.polyunsaturatedFat = nutrition.polyunsaturatedFat
                food.sodium         = nutrition.sodium
                food.cholesterol    = nutrition.cholesterol
                food.potassium      = nutrition.potassium
                food.calcium        = nutrition.calcium
                food.iron           = nutrition.iron
                food.magnesium      = nutrition.magnesium
                food.zinc           = nutrition.zinc
                food.vitaminA       = nutrition.vitaminA
                food.vitaminC       = nutrition.vitaminC
                food.vitaminD       = nutrition.vitaminD
                food.vitaminE       = nutrition.vitaminE
                food.vitaminK       = nutrition.vitaminK
                food.vitaminB6      = nutrition.vitaminB6
                food.vitaminB12     = nutrition.vitaminB12
                food.folate         = nutrition.folate
                food.choline        = nutrition.choline
                food.caffeine       = nutrition.caffeine
            }

        } else {
            // --- CREATE NEW RECIPE ---

            // 1. Create the FoodItem
            let foodItem = FoodItem(
                name:          trimmedName,
                source:        "recipe",
                nutritionMode: .perServing,
                calories:      nutrition.calories,
                protein:       nutrition.protein,
                carbs:         nutrition.carbs,
                fat:           nutrition.fat,
                fiber:         nutrition.fiber,
                sugar:         nutrition.sugar,
                saturatedFat:  nutrition.saturatedFat,
                transFat:      nutrition.transFat,
                polyunsaturatedFat: nutrition.polyunsaturatedFat,
                monounsaturatedFat: nutrition.monounsaturatedFat,
                sodium:        nutrition.sodium,
                cholesterol:   nutrition.cholesterol,
                potassium:     nutrition.potassium,
                calcium:       nutrition.calcium,
                iron:          nutrition.iron,
                magnesium:     nutrition.magnesium,
                zinc:          nutrition.zinc,
                vitaminA:      nutrition.vitaminA,
                vitaminC:      nutrition.vitaminC,
                vitaminD:      nutrition.vitaminD,
                vitaminE:      nutrition.vitaminE,
                vitaminK:      nutrition.vitaminK,
                vitaminB6:     nutrition.vitaminB6,
                vitaminB12:    nutrition.vitaminB12,
                folate:        nutrition.folate,
                choline:       nutrition.choline,
                caffeine:      nutrition.caffeine
            )
            // Recipe nutrition is per-serving. Normalize to per-100g with 100g nominal.
            foodItem.normalizeToPerHundredGrams(gramWeightPerServing: nil)
            let serving = ServingSize(
                label: "1 serving",
                gramWeight: 100.0,
                isDefault: true,
                sortOrder: 0,
                unit: ServingUnit.serving.rawValue
            )
            serving.foodItem = foodItem
            modelContext.insert(foodItem)
            modelContext.insert(serving)
            foodItem.servingSizes.append(serving)

            // 2. Create the Recipe
            let newRecipe = Recipe(
                name:          trimmedName,
                servingsYield: servingsYield,
                sourceURL:     urlToStore,
                directions:    directions
            )
            newRecipe.foodItem = foodItem
            newRecipe.importedNutrition = importedNutrition
            modelContext.insert(newRecipe)

            // 3. Create RecipeIngredients
            for (index, pending) in pendingIngredients.enumerated() {
                let ingredient = RecipeIngredient(quantity: pending.quantity, sortOrder: index)
                ingredient.foodItem       = pending.food
                ingredient.servingSize    = pending.serving
                ingredient.rawText        = pending.rawText
                ingredient.recipeQuantity = pending.recipeQuantity
                ingredient.recipeUnit     = pending.recipeUnit
                ingredient.recipe         = newRecipe
                modelContext.insert(ingredient)
            }
        }

        try? modelContext.save()
        dismiss()
    }
}
