//
//  RecipeImportReviewView.swift
//  BiteLedgerCore
//
//  Shared ingredient-matching review screen used by both BiteLedger (URL + manual)
//  and BiteRecipe (URL + OCR). Pass scannedImage: nil for URL-import paths.
//

import Combine
import SwiftUI
import SwiftData

// MARK: - Matched Ingredient (working model for the review screen)

private final class MatchedIngredient: Identifiable, ObservableObject {
    let id = UUID()
    let parsed: RecipeImportResult.ParsedIngredient

    @Published var matchedFood: FoodItem?
    @Published var matchedServing: ServingSize?
    @Published var quantity: Double
    @Published var skip: Bool = false
    @Published var isRematching: Bool = false

    /// Pre-computed gram amount from the recipe's own quantity+unit.
    /// More reliable than deriving grams from whichever serving happened to be selected.
    @Published var resolvedGramAmount: Double? = nil

    /// Mutable raw text — starts as the OCR/import value; user can correct it.
    @Published var editedRawText: String
    /// Search term to pre-fill in the food picker. Updated when editedRawText changes.
    @Published var currentSearchTerm: String
    /// Unit from the most-recently parsed text (may differ from parsed.unit after user edits).
    @Published var editedUnit: String

    init(parsed: RecipeImportResult.ParsedIngredient) {
        self.parsed = parsed
        self.quantity = parsed.quantity
        self.editedRawText = parsed.rawString
        self.currentSearchTerm = parsed.searchTerm
        self.editedUnit = parsed.unit
    }

    var displayCalories: Double {
        guard let food = matchedFood else { return 0 }
        if let g = resolvedGramAmount {
            return NutritionCalculator.calculate(food: food, gramAmount: g).calories
        }
        return NutritionCalculator.calculate(food: food, serving: matchedServing, quantity: quantity).calories
    }
}

// MARK: - Review View

public struct RecipeImportReviewView: View {
    @Environment(\.modelContext) private var modelContext

    let result: RecipeImportResult
    /// Scanned photo from `OCRRecipeImportView`. Not yet on disk — written in `save()`.
    let scannedImage: UIImage?
    let onSave: () -> Void

    @State private var name: String
    @State private var servingsYield: String
    @State private var source: String
    @State private var editableDirections: [String]

    // Editable metadata pre-filled from Claude/Schema.org extraction — user can correct before save
    @State private var recipeDesc: String
    @State private var prepMinutes: String
    @State private var cookMinutes: String
    @State private var totalMinutes: String
    @State private var recipeCategory: String
    @State private var recipeCuisine: String
    @State private var prevAutoTotal: Int
    @State private var matchedIngredients: [MatchedIngredient] = []
    @State private var isMatching = true
    @State private var isSaving = false
    @State private var selectedIngredient: MatchedIngredient?
    @State private var matchVersion = 0      // incremented on every manual food pick to force header refresh

    private let importService = RecipeImportService.fromPlist()

    /// True for OCR scans — source is a free-text field. False for URL imports — domain shown as label.
    private var isOCR: Bool { result.sourceURL == "ocr://scan" }

    public init(result: RecipeImportResult, prefilledSource: String = "", scannedImage: UIImage? = nil, onSave: @escaping () -> Void) {
        self.result = result
        self.scannedImage = scannedImage
        self.onSave = onSave
        _name = State(initialValue: result.name)
        _servingsYield = State(initialValue: String(Int(result.servingsYield)))
        _source = State(initialValue: prefilledSource)
        _editableDirections = State(initialValue: result.directions.map(expandUnitAbbreviations))
        _recipeDesc      = State(initialValue: result.recipeDescription ?? "")
        _prepMinutes     = State(initialValue: result.prepMinutes.map(String.init) ?? "")
        _cookMinutes     = State(initialValue: result.cookMinutes.map(String.init) ?? "")
        _totalMinutes    = State(initialValue: result.totalMinutes.map(String.init) ?? "")
        _recipeCategory  = State(initialValue: result.recipeCategory ?? "")
        _recipeCuisine   = State(initialValue: result.recipeCuisine ?? "")
        let p = result.prepMinutes ?? 0
        let c = result.cookMinutes ?? 0
        _prevAutoTotal   = State(initialValue: p + c)
    }

    private var activeIngredients: [MatchedIngredient] {
        matchedIngredients.filter { !$0.skip }
    }

    private var totals: NutritionCalculator.Result {
        activeIngredients.reduce(.zero) { acc, m in
            guard let food = m.matchedFood else { return acc }
            if let g = m.resolvedGramAmount {
                return acc + NutritionCalculator.calculate(food: food, gramAmount: g)
            }
            return acc + NutritionCalculator.calculate(
                food: food, serving: m.matchedServing, quantity: m.quantity
            )
        }
    }

    private var perServing: NutritionCalculator.Result {
        let d = Double(Int(servingsYield) ?? 1)
        return NutritionCalculator.Result(
            calories: totals.calories / d, protein: totals.protein / d,
            carbs: totals.carbs / d, fat: totals.fat / d,
            fiber: totals.fiber.map { $0 / d }
        )
    }

    public var body: some View {
        Form {
            // MARK: Recipe Info
            Section("Recipe Info") {
                // Hero photo preview — confirms the user imported the right recipe.
                // OCR: show the scanned UIImage directly (not yet written to disk).
                // URL: load from the remote imageURL via AsyncImage.
                if let image = scannedImage {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(maxWidth: .infinity).frame(height: 180)
                        .clipped()
                        .listRowInsets(EdgeInsets())
                } else if let urlStr = result.imageURL, let url = URL(string: urlStr) {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .success(let img):
                            img.resizable().scaledToFill()
                                .frame(maxWidth: .infinity).frame(height: 180)
                                .clipped()
                        default:
                            Color.secondary.opacity(0.08)
                                .frame(maxWidth: .infinity).frame(height: 180)
                                .overlay { ProgressView() }
                        }
                    }
                    .listRowInsets(EdgeInsets())
                }
                TextField("Name", text: $name)
                HStack {
                    Text("Servings")
                    Spacer()
                    TextField("1", text: $servingsYield)
                        .keyboardType(.numberPad)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 60)
                }
                if isOCR {
                    HStack {
                        Text("Source")
                        Spacer()
                        TextField("e.g. Debbie's Kitchen", text: $source)
                            .multilineTextAlignment(.trailing)
                            .foregroundStyle(.secondary)
                    }
                } else if let domain = URL(string: result.sourceURL)?.host {
                    Label(domain, systemImage: "link")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            // MARK: Nutrition (from Schema.org or calculated)
            Section("Nutrition Per Serving") {
                if let n = result.nutrition {
                    // Website nutrition is the source of truth — always show it
                    NutritionRow(label: "Calories", value: n.calories,  unit: "", note: "from website")
                    NutritionRow(label: "Protein",  value: n.protein,   unit: "g")
                    NutritionRow(label: "Carbs",    value: n.carbs,     unit: "g")
                    NutritionRow(label: "Fat",      value: n.fat,       unit: "g")
                    if let fiber = n.fiber { NutritionRow(label: "Fiber", value: fiber, unit: "g") }

                    // Show calculated total vs website so user can see how complete matching is
                    if perServing.calories > 0 {
                        let pct = Int((perServing.calories / n.calories * 100).rounded())
                        let color: Color = pct >= 80 ? .green : pct >= 50 ? .orange : .red
                        HStack {
                            Text("Matched ingredients")
                                .font(.caption).foregroundStyle(.secondary)
                            Spacer()
                            Text("\(Int(perServing.calories)) cal (\(pct)% of website)")
                                .font(.caption).foregroundStyle(color)
                        }
                        .padding(.top, 2)
                    }
                } else if perServing.calories > 0 {
                    // No website nutrition — show what we can calculate from matched ingredients
                    NutritionRow(label: "Calories", value: perServing.calories, unit: "", note: "calculated")
                    NutritionRow(label: "Protein",  value: perServing.protein,  unit: "g")
                    NutritionRow(label: "Carbs",    value: perServing.carbs,    unit: "g")
                    NutritionRow(label: "Fat",      value: perServing.fat,      unit: "g")
                    if let fiber = perServing.fiber { NutritionRow(label: "Fiber", value: fiber, unit: "g") }
                } else {
                    Text("Match ingredients above to calculate nutrition.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }

            // MARK: Ingredients
            Section {
                ForEach(matchedIngredients) { m in
                    IngredientMatchRow(matched: m, onTap: {
                        selectedIngredient = m
                    }, onEditText: { newText in
                        let parsed = importService.parseIngredientText(newText)
                        m.editedRawText = newText
                        m.currentSearchTerm = parsed.searchTerm
                        m.quantity = parsed.quantity
                        m.editedUnit = parsed.unit
                        m.matchedFood = nil
                        m.matchedServing = nil
                        m.resolvedGramAmount = nil
                        m.isRematching = true
                        Task {
                            await matchSingle(m, searchTerm: parsed.searchTerm, recipeContext: name)
                            matchVersion += 1   // refresh the nutrition header
                        }
                    })
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        Button(role: .destructive) {
                            m.skip = true
                        } label: {
                            Label("Remove", systemImage: "trash")
                        }
                    }
                    .swipeActions(edge: .leading, allowsFullSwipe: true) {
                        if m.skip {
                            Button {
                                m.skip = false
                            } label: {
                                Label("Restore", systemImage: "arrow.uturn.backward")
                            }
                            .tint(.green)
                        }
                    }
                }
            } header: {
                HStack {
                    Text("Ingredients")
                    Spacer()
                    if isMatching {
                        HStack(spacing: 4) {
                            ProgressView().scaleEffect(0.7)
                            Text("Matching…")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    } else {
                        let matched = matchedIngredients.filter { $0.matchedFood != nil && !$0.skip }.count
                        let total   = matchedIngredients.filter { !$0.skip }.count
                        Text("\(matched)/\(total) matched")
                            .id(matchVersion)
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            } footer: {
                Text("Tap to match to a food for nutrition tracking. Unmatched ingredients still save as text.")
                    .font(.caption)
            }

            // MARK: Directions (editable)
            Section {
                ForEach(editableDirections.indices, id: \.self) { i in
                    HStack(alignment: .top, spacing: 10) {
                        Text("\(i + 1).")
                            .foregroundStyle(.secondary)
                            .frame(width: 24, alignment: .trailing)
                        TextField("Step \(i + 1)", text: $editableDirections[i], axis: .vertical)
                            .font(.subheadline)
                    }
                }
                .onDelete { editableDirections.remove(atOffsets: $0) }
                Button {
                    editableDirections.append("")
                } label: {
                    Label("Add Step", systemImage: "plus")
                        .font(.subheadline)
                }
            } header: {
                Text("Directions")
            } footer: {
                if !editableDirections.isEmpty {
                    Text("Swipe to delete a step.")
                        .font(.caption)
                }
            }

            // MARK: Details (editable — pre-filled from Claude/Schema.org extraction)
            Section("Details") {
                TextField("Description (optional)", text: $recipeDesc, axis: .vertical)
                    .lineLimit(2...4)
                HStack {
                    Text("Prep Time")
                    Spacer()
                    TextField("0", text: $prepMinutes)
                        .keyboardType(.numberPad)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 60)
                    Text("min")
                        .foregroundStyle(.secondary)
                }
                HStack {
                    Text("Cook Time")
                    Spacer()
                    TextField("0", text: $cookMinutes)
                        .keyboardType(.numberPad)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 60)
                    Text("min")
                        .foregroundStyle(.secondary)
                }
                HStack {
                    Text("Total Time")
                    Spacer()
                    TextField("0", text: $totalMinutes)
                        .keyboardType(.numberPad)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 60)
                    Text("min")
                        .foregroundStyle(.secondary)
                }
                Picker("Category", selection: $recipeCategory) {
                    Text("None").tag("")
                    ForEach(RecipeEditorView.categoryOptions, id: \.self) { cat in
                        Text(cat).tag(cat)
                    }
                }
                .pickerStyle(.menu)
                Picker("Cuisine", selection: $recipeCuisine) {
                    Text("None").tag("")
                    ForEach(RecipeEditorView.cuisineOptions, id: \.self) { cuisine in
                        Text(cuisine).tag(cuisine)
                    }
                }
                .pickerStyle(.menu)
            }

            // MARK: Save
            Section {
                Button {
                    save()
                } label: {
                    HStack {
                        Spacer()
                        if isSaving {
                            ProgressView().padding(.trailing, 8)
                            Text("Saving…")
                        } else {
                            Text("Save Recipe").bold()
                        }
                        Spacer()
                    }
                }
                .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || isSaving)
            }
        }
        .navigationTitle("Review Recipe")
        .navigationBarTitleDisplayMode(.inline)
        .task { await autoMatch(); isMatching = false }
        .onChange(of: prepMinutes) { _, _ in autoUpdateTotal() }
        .onChange(of: cookMinutes) { _, _ in autoUpdateTotal() }
        .sheet(item: $selectedIngredient) { m in
            IngredientFoodPickerView(matched: m, onUpdate: { matchVersion += 1 })
        }

    }

    // MARK: - Auto-match

    private func autoMatch() async {
        let items = result.parsedIngredients.map { MatchedIngredient(parsed: $0) }
        // Show the list immediately in the original recipe order so the user can
        // see all ingredients while matching runs, rather than waiting for everything
        // to finish before the list appears.
        matchedIngredients = items
        for m in items {
            m.isRematching = true
            await matchSingle(m, searchTerm: m.parsed.searchTerm, recipeContext: name)
        }
    }

    /// Matches a single ingredient to a FoodItem using the local DB and live API.
    /// `recipeContext` is the recipe name — used to disambiguate generic terms like "broth"
    /// by preferring foods that share the same protein (e.g. chicken broth in a chicken recipe).
    private func matchSingle(_ m: MatchedIngredient, searchTerm rawTerm: String, recipeContext: String = "") async {
        let rawTerm = rawTerm.trimmingCharacters(in: .whitespaces)
        guard !rawTerm.isEmpty else { m.isRematching = false; return }

        let termAliases: [String: String] = [
            "pepper": "black pepper",
            "ground pepper": "black pepper",
            "black pepper ground": "black pepper",
            "seasoning": "salt",
            "chicken cutlet": "chicken breast",
            "chicken cutlets": "chicken breast",
            "canned chicken": "chicken breast",   // canned chicken ≈ cooked chicken breast nutritionally
            "chicken canned": "chicken breast",
        ]
        var term = termAliases[rawTerm.lowercased()] ?? rawTerm

        let keptCheesePhrases: Set<String> = [
            "cream cheese", "cottage cheese", "goat cheese", "american cheese",
            "swiss cheese", "blue cheese", "brie cheese"
        ]
        if term.lowercased().hasSuffix(" cheese") && !keptCheesePhrases.contains(term.lowercased()) {
            term = String(term.dropLast(7))
        }

        // --- Local DB search ---
        let descriptor = FetchDescriptor<FoodItem>(
            predicate: #Predicate { $0.name.localizedStandardContains(term) },
            sortBy: [SortDescriptor(\.name)]
        )
        let localCandidates = (try? modelContext.fetch(descriptor)) ?? []
        let localScored: [(FoodItem, Int)] = localCandidates.map { food in
            var score = ingredientScore(foodName: food.name, term: term)
            let isAuthoritative = food.source.hasPrefix("usda_seed") || food.source.hasPrefix("built_in")
            if isAuthoritative { score += 20 }
            return (food, score)
        }
        let bestLocal = localScored.max(by: { lhs, rhs in
            lhs.1 != rhs.1 ? lhs.1 < rhs.1 : lhs.0.name.count > rhs.0.name.count
        })
        let localScore = bestLocal?.1 ?? 0

        var food: FoodItem? = localScore >= 30 ? bestLocal?.0 : nil
        let localIsAuthoritative = (food?.source.hasPrefix("usda_seed") ?? false)
                                || (food?.source.hasPrefix("built_in") ?? false)

        // --- Live API fallback ---
        if !localIsAuthoritative {
            if let products = try? await UnifiedFoodSearchService.shared.searchAllDatabases(query: term),
               !products.isEmpty {
                let apiScored = products.map { ($0, ingredientScore(foodName: $0.displayName, term: term)) }
                if let bestAPI = apiScored.max(by: { $0.1 < $1.1 }),
                   bestAPI.1 >= 30, bestAPI.1 >= localScore,
                   let usdaFood = await createOrFetchUSDAFood(product: bestAPI.0) {
                    food = usdaFood
                }
            }
        }

        m.isRematching = false
        guard var food else { return }

        // Context refinement: if the recipe name contains a protein (e.g. "chicken") and
        // the search term does NOT already specify it, look for a more specific match.
        // "broth" in "Chicken Squares" → prefer "chicken broth" over "beef broth".
        let proteinWords: Set<String> = [
            "chicken","beef","pork","turkey","lamb","fish","shrimp","tuna","salmon","ham","veal"
        ]
        let contextWords = Set(recipeContext.lowercased().components(separatedBy: .whitespaces))
        let termWords    = Set(term.lowercased().components(separatedBy: .whitespaces))
        if let contextProtein = contextWords.first(where: { proteinWords.contains($0) }),
           !termWords.contains(contextProtein) {
            let contextTerm = "\(contextProtein) \(term)"
            let ctxDescriptor = FetchDescriptor<FoodItem>(
                predicate: #Predicate { $0.name.localizedStandardContains(contextTerm) }
            )
            if let contextFood = try? modelContext.fetch(ctxDescriptor).first {
                food = contextFood
            }
        }

        m.matchedFood    = food
        m.matchedServing = food.defaultServing

        let (gramAmount, bestServing) = resolveGrams(
            quantity: m.quantity, unit: m.editedUnit, food: food
        )
        m.resolvedGramAmount = gramAmount
        if let s = bestServing { m.matchedServing = s }
    }

    /// Looks up an existing FoodItem by USDA code, or fetches full details from USDA and
    /// creates a new per-100g FoodItem with real serving gram weights. Saves to the shared store
    /// so the same food is reused instantly on future recipe imports.
    @MainActor
    private func createOrFetchUSDAFood(product: ProductInfo) async -> FoodItem? {
        let code = product.code
        if !code.isEmpty {
            let descriptor = FetchDescriptor<FoodItem>(
                predicate: #Predicate { $0.barcode == code }
            )
            if let existing = try? modelContext.fetch(descriptor).first {
                return existing
            }
        }

        // Fetch full details to get USDA portions with real gram weights
        let detailed = (try? await UnifiedFoodSearchService.shared.getProductDetails(code: code)) ?? product

        guard let n = detailed.nutriments,
              let cal = n.energyKcal100g?.value, cal > 0 else { return nil }

        // Micronutrients in ProductInfo are stored as g/100g (OpenFoodFacts convention).
        // FoodItem stores them in mg/100g (sodium, cholesterol, etc.) or mcg/100g (vitamins A, D).
        let food = FoodItem(
            name: detailed.displayName,
            brand: detailed.brands,
            barcode: code.isEmpty ? nil : code,
            source: "USDA",
            nutritionMode: .per100g,
            calories:     cal,
            protein:      n.proteins100g?.value ?? 0,
            carbs:        n.carbohydrates100g?.value ?? 0,
            fat:          n.fat100g?.value ?? 0,
            fiber:        n.fiber100g?.value,
            sugar:        n.sugars100g?.value,
            saturatedFat: n.saturatedFat100g?.value,
            sodium:       n.sodium100g.map      { $0.value * 1_000 },
            cholesterol:  n.cholesterol100g.map { $0.value * 1_000 },
            potassium:    n.potassium100g.map   { $0.value * 1_000 },
            calcium:      n.calcium100g.map     { $0.value * 1_000 },
            iron:         n.iron100g.map        { $0.value * 1_000 },
            vitaminA:     n.vitaminA100g.map    { $0.value * 1_000_000 },
            vitaminC:     n.vitaminC100g.map    { $0.value * 1_000 }
        )
        modelContext.insert(food)

        if let portions = detailed.portions, !portions.isEmpty {
            for (i, portion) in portions.enumerated() {
                let amtStr = portion.amount == portion.amount.rounded()
                    ? String(Int(portion.amount)) : String(format: "%.2g", portion.amount)
                let label = "\(amtStr) \(portion.modifier)"
                let serving = ServingSize(
                    label: label,
                    gramWeight: portion.gramWeight,
                    isDefault: i == 0,
                    sortOrder: i,
                    unit: ServingSizeParser.parseUnit(portion.modifier)?.abbreviation,
                    amount: portion.amount
                )
                serving.foodItem = food
                modelContext.insert(serving)
            }
        } else {
            let serving = ServingSize(label: "100g", gramWeight: 100, isDefault: true,
                                      sortOrder: 0, unit: "g", amount: 100)
            serving.foodItem = food
            modelContext.insert(serving)
        }

        try? modelContext.save()
        return food
    }

    // MARK: - Auto-total

    private func autoUpdateTotal() {
        let p = Int(prepMinutes) ?? 0
        let c = Int(cookMinutes) ?? 0
        let newSum = p + c
        let currentTotal = Int(totalMinutes)
        if totalMinutes.isEmpty || currentTotal == prevAutoTotal {
            totalMinutes = newSum > 0 ? String(newSum) : ""
            prevAutoTotal = newSum
        }
    }

    // MARK: - Save

    private func save() {
        isSaving = true
        let yield = Double(Int(servingsYield) ?? 1)

        // For OCR imports, save the human-readable source text (or nil if blank).
        // For URL imports, preserve the original URL.
        let savedSourceURL: String?
        if isOCR {
            let trimmed = source.trimmingCharacters(in: .whitespaces)
            savedSourceURL = trimmed.isEmpty ? nil : trimmed
        } else {
            savedSourceURL = result.sourceURL
        }

        let recipe = Recipe(
            name: name.trimmingCharacters(in: .whitespaces),
            servingsYield: yield,
            sourceURL: savedSourceURL,
            directions: editableDirections.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                                          .filter { !$0.isEmpty }
        )

        // Always store website nutrition when available — it is the authoritative source
        if let n = result.nutrition {
            recipe.importedNutrition = n
        }

        // Rich metadata — use editable state (user may have corrected Claude's extraction)
        let descTrimmed = recipeDesc.trimmingCharacters(in: .whitespaces)
        recipe.prepMinutes       = Int(prepMinutes)
        recipe.cookMinutes       = Int(cookMinutes)
        recipe.totalMinutes      = Int(totalMinutes)
        recipe.recipeDescription = descTrimmed.isEmpty ? nil : descTrimmed
        recipe.recipeCategory    = recipeCategory.isEmpty ? nil : recipeCategory
        recipe.recipeCuisine     = recipeCuisine.trimmingCharacters(in: .whitespaces).isEmpty ? nil : recipeCuisine.trimmingCharacters(in: .whitespaces)
        recipe.ratingValue       = result.ratingValue
        recipe.ratingCount       = result.ratingCount
        recipe.keywords          = result.keywords
        recipe.dietTags          = result.dietTags

        if isOCR {
            // For OCR recipes: write the scanned photo to disk now (user confirmed save).
            // The source field doubles as the author attribution (auto-filled from detectedSource).
            if let image = scannedImage,
               let jpegData = image.jpegData(compressionQuality: 0.82) {
                recipe.imageURL = RecipeImportService.saveImageDataLocally(jpegData, appGroupIdentifier: "group.com.ridepro.biteledger")
            }
            let trimmedAuthor = source.trimmingCharacters(in: .whitespaces)
            recipe.author = trimmedAuthor.isEmpty ? nil : trimmedAuthor
        } else {
            recipe.imageURL = result.imageURL
            recipe.author   = result.author
        }

        var sortOrder = 0
        for m in matchedIngredients where !m.skip {
            // When a gram amount was resolved from recipe units (oz, lb, cross-unit volume),
            // convert it back to a quantity in terms of the matched serving so the saved
            // recipe displays the same calories as the import review.
            let savedQuantity: Double
            if let gram = m.resolvedGramAmount,
               let gw = m.matchedServing?.gramWeight, gw > 0 {
                savedQuantity = gram / gw
            } else {
                savedQuantity = m.quantity
            }

            let ing = RecipeIngredient(
                quantity: savedQuantity,
                sortOrder: sortOrder,
                recipeQuantity: m.parsed.quantity,
                recipeUnit: m.parsed.unit.isEmpty ? nil : m.parsed.unit
            )
            ing.rawText     = m.editedRawText       // always store raw text (may be user-edited)
            ing.foodItem    = m.matchedFood         // optional
            ing.servingSize = m.matchedServing      // optional
            ing.recipe      = recipe
            modelContext.insert(ing)
            sortOrder += 1
        }

        modelContext.insert(recipe)
        try? modelContext.save()
        isSaving = false
        onSave()
    }
}

// MARK: - Ingredient Match Row

private struct IngredientMatchRow: View {
    @ObservedObject var matched: MatchedIngredient
    let onTap: () -> Void
    let onEditText: (String) -> Void

    @State private var showingEdit = false
    @State private var pendingText = ""

    var body: some View {
        HStack(spacing: 0) {
            // Main tap area → food picker
            Button {
                onTap()
            } label: {
                HStack(spacing: 12) {
                    // Status indicator
                    Group {
                        if matched.isRematching {
                            ProgressView().scaleEffect(0.7)
                        } else {
                            Image(systemName: matched.skip ? "minus.circle.fill" :
                                              matched.matchedFood != nil ? "checkmark.circle.fill" : "questionmark.circle.fill")
                                .foregroundColor(matched.skip ? .secondary :
                                                 matched.matchedFood != nil ? .green : .orange)
                        }
                    }
                    .frame(width: 22)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(matched.editedRawText)
                            .font(.subheadline)
                            .foregroundStyle(matched.skip ? .secondary : .primary)
                            .strikethrough(matched.skip)

                    if matched.skip {
                        Text("Removed — tap to restore")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else if let food = matched.matchedFood {
                        let cal = matched.displayCalories
                        let quantityDetail: String = {
                            if let g = matched.resolvedGramAmount {
                                return "\(Int(g.rounded()))g"
                            } else if let s = matched.matchedServing {
                                let q = matched.quantity
                                let qStr = q == q.rounded() ? "\(Int(q))" : String(format: "%.1f", q)
                                return "\(qStr)× \(s.label)"
                            }
                            return ""
                        }()
                        Text("→ \(food.name)  ·  \(quantityDetail)  ·  \(Int(cal.rounded())) cal")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("Tap to match food")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }
            }
            }
            .buttonStyle(.plain)

            Spacer(minLength: 0)

            // Pencil button — edit raw ingredient text
            Button {
                pendingText = matched.editedRawText
                showingEdit = true
            } label: {
                Image(systemName: "pencil")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.leading, 8)
                    .padding(.vertical, 4)
            }
            .buttonStyle(.plain)
        }
        .sheet(isPresented: $showingEdit) {
            NavigationStack {
                Form {
                    Section {
                        TextField("e.g. 2 cups flour", text: $pendingText, axis: .vertical)
                            .font(.subheadline)
                    } header: {
                        Text("Ingredient Text")
                    } footer: {
                        Text("Edit to correct OCR errors. The app will re-match automatically.")
                    }
                }
                .navigationTitle("Edit Ingredient")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") {
                            let trimmed = pendingText.trimmingCharacters(in: .whitespacesAndNewlines)
                            if !trimmed.isEmpty { onEditText(trimmed) }
                            showingEdit = false
                        }
                        .bold()
                    }
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { showingEdit = false }
                    }
                }
            }
            .presentationDetents([.medium])
        }
    }
}

// MARK: - Ingredient Food Picker (sheet)

private struct IngredientFoodPickerView: View {
    @ObservedObject var matched: MatchedIngredient
    let onUpdate: () -> Void
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var searchText = ""
    @State private var localResults: [FoodItem] = []
    /// API results held as ProductInfo — NOT saved to the DB until the user selects one.
    /// Prevents browsed-but-rejected foods from polluting the shared store.
    @State private var apiResults: [ProductInfo] = []

    var body: some View {
        NavigationStack {
            List {
                // Currently matched food — shown at top so user can see what's already selected
                if let currentFood = matched.matchedFood {
                    Section("Currently matched") {
                        Button { selectFood(currentFood) } label: {
                            HStack(spacing: 10) {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.green)
                                foodRow(currentFood)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }

                // Keep without nutrition
                Button {
                    matched.matchedFood    = nil
                    matched.matchedServing = nil
                    matched.skip           = false
                    onUpdate()
                    dismiss()
                } label: {
                    Label("Keep as text (no nutrition)", systemImage: "text.badge.checkmark")
                        .foregroundStyle(.blue)
                }

                // Remove entirely
                Button(role: .destructive) {
                    matched.matchedFood    = nil
                    matched.matchedServing = nil
                    matched.skip           = true
                    onUpdate()
                    dismiss()
                } label: {
                    Label("Remove from recipe", systemImage: "trash")
                }

                // Local DB results (seeded / previously saved)
                ForEach(localResults) { food in
                    Button { selectFood(food) } label: { foodRow(food) }
                }

                // API results — transient, saved only when selected
                ForEach(apiResults, id: \.displayName) { product in
                    Button {
                        Task { @MainActor in
                            if let food = await createAndSaveFood(product) {
                                selectFood(food)
                            }
                        }
                    } label: { apiRow(product) }
                }

                if localResults.isEmpty && apiResults.isEmpty && !searchText.isEmpty {
                    ContentUnavailableView.search(text: searchText)
                }
            }
            .navigationTitle(matched.editedRawText)
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $searchText, prompt: "Search foods")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .onChange(of: searchText) { _, q in search(q) }
            .onAppear {
                // Use currentSearchTerm (quantity/unit stripped) not the raw text
                searchText = matched.currentSearchTerm
                search(matched.currentSearchTerm)
            }
        }
    }

    // MARK: - Food selection

    private func selectFood(_ food: FoodItem) {
        matched.matchedFood = food
        matched.skip        = false
        let (gram, bestServing) = resolveGrams(
            quantity: matched.quantity,
            unit: matched.editedUnit,
            food: food
        )
        matched.resolvedGramAmount = gram
        matched.matchedServing     = bestServing ?? food.defaultServing
        onUpdate()
        dismiss()
    }

    // MARK: - Row views

    @ViewBuilder
    private func foodRow(_ food: FoodItem) -> some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                Text(food.name).foregroundStyle(.primary)
                if let brand = food.brand {
                    Text(brand).font(.caption).foregroundStyle(.secondary)
                }
                if let cal = food.defaultServing.flatMap({ s -> Double? in
                    guard s.gramWeight != nil else { return nil }
                    return NutritionCalculator.preview(food: food, serving: s, quantity: 1).calories
                }) {
                    Text("\(Int(cal)) cal / \(food.defaultServing?.label ?? "serving")")
                        .font(.caption2).foregroundStyle(.secondary)
                }
            }
            Spacer()
            sourceTag(food.source)
        }
    }

    @ViewBuilder
    private func apiRow(_ product: ProductInfo) -> some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                Text(product.displayName).foregroundStyle(.primary)
                if let brand = product.brands, !brand.isEmpty {
                    Text(brand).font(.caption).foregroundStyle(.secondary)
                }
                if let cal = product.nutriments?.energyKcal100g?.value {
                    if let portion = product.portions?.first {
                        let displayCal = NutritionCalculator.perPortionCalories(caloriesPer100g: cal, gramWeight: portion.gramWeight)
                        Text("\(Int(displayCal)) cal / \(portion.modifier)")
                            .font(.caption2).foregroundStyle(.secondary)
                    } else {
                        Text("\(Int(cal)) cal/100g")
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                }
            }
            Spacer()
            sourceTag("USDA")
        }
    }

    @ViewBuilder
    private func sourceTag(_ source: String) -> some View {
        let label: String = {
            if source.hasPrefix("usda_seed") || source.hasPrefix("built_in") { return "DB" }
            if source == "USDA" || source.hasPrefix("usda_") { return "USDA" }
            if source.hasPrefix("fatsecret") { return "FS" }
            if source.isEmpty { return "OFx" }
            return "DB"
        }()
        let color: Color = {
            if source.hasPrefix("usda_seed") || source.hasPrefix("built_in") { return .green }
            if source == "USDA" || source.hasPrefix("usda_") { return .blue }
            if source.hasPrefix("fatsecret") { return .orange }
            if source.isEmpty { return .purple }   // OpenFoodFacts / barcode
            return .green                           // any other local DB food
        }()
        Text(label)
            .font(.caption2)
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(color.opacity(0.15))
            .foregroundStyle(color)
            .clipShape(Capsule())
    }

    // MARK: - Search

    private func search(_ query: String) {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { localResults = []; apiResults = []; return }

        let descriptor = FetchDescriptor<FoodItem>(
            predicate: #Predicate { $0.name.localizedStandardContains(q) }
        )
        let local = (try? modelContext.fetch(descriptor)) ?? []
        localResults = local.sorted { a, b in
            let sa = ingredientScore(foodName: a.name, term: q)
            let sb = ingredientScore(foodName: b.name, term: q)
            if sa != sb { return sa > sb }
            return a.name.count < b.name.count
        }

        // Fetch API results as ProductInfo only — do NOT save to DB here
        apiResults = []
        Task { @MainActor in
            guard let products = try? await UnifiedFoodSearchService.shared.searchAllDatabases(query: q)
            else { return }
            let localNames = Set(local.map { $0.name.lowercased() })
            apiResults = products
                .filter { !localNames.contains($0.displayName.lowercased()) }
                .filter { ($0.nutriments?.energyKcal100g?.value ?? 0) > 0 }
                .sorted { a, b in
                    let sa = ingredientScore(foodName: a.displayName, term: q)
                    let sb = ingredientScore(foodName: b.displayName, term: q)
                    if sa != sb { return sa > sb }
                    return a.displayName.count < b.displayName.count
                }
                .prefix(10)
                .map { $0 }
        }
    }

    // MARK: - Create food on selection (only called when user picks an API result)

    @MainActor
    private func createAndSaveFood(_ product: ProductInfo) async -> FoodItem? {
        let code = product.code
        if !code.isEmpty,
           let existing = try? modelContext.fetch(
               FetchDescriptor<FoodItem>(predicate: #Predicate { $0.barcode == code })
           ).first {
            return existing
        }

        let detailed = (try? await UnifiedFoodSearchService.shared.getProductDetails(code: code)) ?? product
        guard let n = detailed.nutriments,
              let cal = n.energyKcal100g?.value, cal > 0 else { return nil }

        let food = FoodItem(
            name: detailed.displayName, brand: detailed.brands,
            barcode: code.isEmpty ? nil : code, source: "USDA",
            nutritionMode: .per100g,
            calories:     cal,
            protein:      n.proteins100g?.value     ?? 0,
            carbs:        n.carbohydrates100g?.value ?? 0,
            fat:          n.fat100g?.value           ?? 0,
            fiber:        n.fiber100g?.value,
            sugar:        n.sugars100g?.value,
            saturatedFat: n.saturatedFat100g?.value,
            sodium:       n.sodium100g.map      { $0.value * 1_000 },
            cholesterol:  n.cholesterol100g.map { $0.value * 1_000 },
            potassium:    n.potassium100g.map   { $0.value * 1_000 },
            calcium:      n.calcium100g.map     { $0.value * 1_000 },
            iron:         n.iron100g.map        { $0.value * 1_000 },
            vitaminA:     n.vitaminA100g.map    { $0.value * 1_000_000 },
            vitaminC:     n.vitaminC100g.map    { $0.value * 1_000 }
        )
        modelContext.insert(food)

        if let portions = detailed.portions, !portions.isEmpty {
            for (i, portion) in portions.enumerated() {
                let amtStr = portion.amount == portion.amount.rounded()
                    ? String(Int(portion.amount)) : String(format: "%.2g", portion.amount)
                let serving = ServingSize(
                    label: "\(amtStr) \(portion.modifier)",
                    gramWeight: portion.gramWeight,
                    isDefault: i == 0, sortOrder: i,
                    unit: ServingSizeParser.parseUnit(portion.modifier)?.abbreviation,
                    amount: portion.amount
                )
                serving.foodItem = food
                modelContext.insert(serving)
            }
        } else {
            let serving = ServingSize(label: "100g", gramWeight: 100, isDefault: true,
                                      sortOrder: 0, unit: "g", amount: 100)
            serving.foodItem = food
            modelContext.insert(serving)
        }

        try? modelContext.save()
        return food
    }
}

// MARK: - Helpers

private func expandUnitAbbreviations(_ text: String) -> String {
    var s = text
    // \b word boundaries ensure we only match standalone T/t, not letters inside words.
    s = s.replacingOccurrences(of: #"\bT\b"#, with: "tbsp", options: .regularExpression)
    s = s.replacingOccurrences(of: #"\bt\b"#, with: "tsp",  options: .regularExpression)
    return s
}

private struct NutritionRow: View {
    let label: String
    let value: Double
    let unit: String
    var note: String? = nil

    var body: some View {
        HStack {
            Text(label)
            if let note {
                Text("(\(note))").font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Text("\(Int(value))\(unit)").foregroundStyle(.secondary)
        }
    }
}
