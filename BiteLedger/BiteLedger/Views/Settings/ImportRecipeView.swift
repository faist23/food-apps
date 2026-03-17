//
//  ImportRecipeView.swift
//  BiteLedger
//
//  Multi-step sheet:
//    Step 1 — URL entry
//    Step 2 — Review parsed recipe (name, yield, ingredients, directions)
//    Step 3 — "Apply to Recipe" pre-fills RecipeEditorView
//

import SwiftUI
import SwiftData
import BiteLedgerCore

// MARK: - Callback data passed back to RecipeEditorView

struct ImportedRecipeData {
    let name: String
    let servingsYield: Double
    let sourceURL: String
    let directions: [String]
    /// Ingredients that were auto-matched to a FoodItem in My Foods.
    /// `rawText` is the original recipe line (e.g. "1.5 lbs chicken breast") for display.
    /// `quantity` and `unit` are the parsed recipe amount (e.g. 1.5, "lbs").
    let matchedIngredients: [(food: FoodItem, serving: ServingSize, quantity: Double, rawText: String, unit: String)]
    /// Parsed ingredients that had no match — carries quantity/unit/searchTerm for the Find flow.
    let unmatchedIngredients: [UnmatchedHint]
    /// Per-serving nutrition from the recipe website's Schema.org markup. nil if not found.
    let nutrition: RecipeNutrition?

    struct UnmatchedHint: Identifiable {
        let id       = UUID()
        let raw:        String  // "1/2 cup salted butter"
        let searchTerm: String  // "salted butter"
        let quantity:   Double  // 0.5
        let unit:       String  // "cup"
    }
}

// MARK: - ImportRecipeView

struct ImportRecipeView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    let onImport: (ImportedRecipeData) -> Void

    // MARK: State

    @State private var urlText: String = ""
    @State private var isLoading = false
    @State private var result: RecipeImportResult?
    @State private var errorMessage: String?
    @State private var matchResults: [MatchResult] = []
    @State private var editingMatchIndex: Int?

    struct MatchResult: Identifiable {
        let id: UUID
        let raw: String
        let searchTerm: String
        let quantity: Double
        let unit: String
        var matchedFood: FoodItem?
        var matchedServing: ServingSize?
    }

    private let service = RecipeImportService.fromPlist()

    // MARK: Body

    var body: some View {
        NavigationStack {
            Group {
                if let result {
                    reviewPage(result)
                } else {
                    urlEntryPage
                }
            }
            .navigationTitle("Import from Web")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                if result != nil {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Back") {
                            withAnimation { self.result = nil; matchResults = [] }
                        }
                    }
                }
            }
        }
    }

    // MARK: - Page 1: URL Entry

    private var urlEntryPage: some View {
        VStack(spacing: 24) {
            VStack(spacing: 8) {
                Image(systemName: "link.circle.fill")
                    .font(.system(size: 60))
                    .foregroundStyle(Color("BrandAccent"))
                Text("Paste a recipe URL")
                    .font(.title3.bold())
                Text("Works with most recipe websites that display a structured recipe card (Allrecipes, Food Network, NYT Cooking, and thousands more).")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }
            .padding(.top, 20)

            TextField("https://example.com/recipe", text: $urlText)
                .textFieldStyle(.roundedBorder)
                .keyboardType(.URL)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .padding(.horizontal)

            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }

            Button {
                Task { await fetchRecipe() }
            } label: {
                Group {
                    if isLoading {
                        HStack(spacing: 10) {
                            ProgressView().tint(.white)
                            Text("Fetching…")
                        }
                    } else {
                        Text("Fetch Recipe")
                    }
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(urlText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isLoading
                            ? Color.gray : Color("BrandAccent"))
                .foregroundStyle(.white)
                .clipShape(RoundedRectangle(cornerRadius: 14))
            }
            .disabled(urlText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isLoading)
            .padding(.horizontal)

            Spacer()
        }
        .background(Color("SurfacePrimary"))
    }

    // MARK: - Page 2: Review

    private func reviewPage(_ result: RecipeImportResult) -> some View {
        ScrollView {
            VStack(spacing: 16) {
                // Recipe summary card
                ElevatedCard(padding: 16, cornerRadius: 20) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(result.name)
                            .font(.title3.bold())
                        let yieldStr = result.servingsYield.truncatingRemainder(dividingBy: 1) == 0
                            ? "\(Int(result.servingsYield))"
                            : String(format: "%.1f", result.servingsYield)
                        Text("Makes \(yieldStr) serving\(result.servingsYield == 1 ? "" : "s")")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        if let domain = URL(string: result.sourceURL)?.host {
                            let clean = domain.hasPrefix("www.") ? String(domain.dropFirst(4)) : domain
                            Label(clean, systemImage: "link")
                                .font(.caption)
                                .foregroundStyle(.orange)
                        }
                    }
                }

                // Ingredients card
                ElevatedCard(padding: 16, cornerRadius: 20) {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text("Ingredients")
                                .font(.headline)
                                .foregroundStyle(Color("TextSecondary"))
                            Spacer()
                            Text("\(matchResults.count) found")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        if matchResults.isEmpty {
                            Text("No ingredients were found on this page.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(matchResults) { match in
                                ingredientMatchRow(match)
                                if match.id != matchResults.last?.id {
                                    Divider()
                                }
                            }
                        }
                    }
                }

                // Directions card
                if !result.directions.isEmpty {
                    ElevatedCard(padding: 16, cornerRadius: 20) {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("Directions")
                                    .font(.headline)
                                    .foregroundStyle(Color("TextSecondary"))
                                Spacer()
                                Text("\(result.directions.count) step\(result.directions.count == 1 ? "" : "s")")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            ForEach(Array(result.directions.prefix(3).enumerated()), id: \.offset) { i, step in
                                HStack(alignment: .top, spacing: 8) {
                                    Text("\(i + 1).")
                                        .font(.caption)
                                        .fontWeight(.semibold)
                                        .foregroundStyle(Color("BrandAccent"))
                                        .frame(width: 16, alignment: .leading)
                                    Text(step)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(2)
                                }
                            }
                            if result.directions.count > 3 {
                                Text("… and \(result.directions.count - 3) more step\(result.directions.count - 3 == 1 ? "" : "s")")
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                            }
                        }
                    }
                }

                // Website nutrition card (when Schema.org nutrition was found)
                if let n = result.nutrition {
                    ElevatedCard(padding: 16, cornerRadius: 20) {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack(spacing: 6) {
                                Image(systemName: "checkmark.seal.fill")
                                    .foregroundStyle(.green)
                                Text("Nutrition from website")
                                    .font(.headline)
                                Spacer()
                            }
                            Text("Per serving · automatically applied when saved")
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            HStack(spacing: 0) {
                                nutritionPill(label: "Cal", value: Int(n.calories))
                                Spacer()
                                nutritionPill(label: "Protein", value: Int(n.protein), unit: "g")
                                Spacer()
                                nutritionPill(label: "Carbs", value: Int(n.carbs), unit: "g")
                                Spacer()
                                nutritionPill(label: "Fat", value: Int(n.fat), unit: "g")
                            }
                        }
                    }
                }

                // Match summary
                let matched   = matchResults.filter { $0.matchedFood != nil }.count
                let unmatched = matchResults.count - matched
                ElevatedCard(padding: 16, cornerRadius: 20) {
                    VStack(spacing: 6) {
                        HStack {
                            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                            Text("\(matched) ingredient\(matched == 1 ? "" : "s") matched to My Foods")
                            Spacer()
                        }
                        .font(.subheadline)
                        if unmatched > 0 {
                            HStack {
                                Image(systemName: "magnifyingglass.circle").foregroundStyle(.orange)
                                Text("\(unmatched) ingredient\(unmatched == 1 ? "" : "s") not found — add manually in the editor")
                                Spacer()
                            }
                            .font(.subheadline)
                        }
                    }
                }

                // Apply button
                Button {
                    applyRecipe(result)
                } label: {
                    Text("Apply to Recipe")
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color("BrandAccent"))
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                }
            }
            .padding()
        }
        .background(Color("SurfacePrimary"))
        .sheet(isPresented: Binding(
            get: { editingMatchIndex != nil },
            set: { if !$0 { editingMatchIndex = nil } }
        )) {
            if let idx = editingMatchIndex {
                MatchFoodPickerSheet(
                    rawIngredient: matchResults[idx].raw,
                    searchTerm:    matchResults[idx].searchTerm,
                    current:       matchResults[idx].matchedFood
                ) { selectedFood in
                    matchResults[idx].matchedFood   = selectedFood
                    matchResults[idx].matchedServing = selectedFood?.defaultServing
                    editingMatchIndex = nil
                }
            }
        }
    }

    @ViewBuilder
    private func nutritionPill(label: String, value: Int, unit: String = "") -> some View {
        VStack(spacing: 2) {
            Text("\(value)\(unit)")
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(Color("TextPrimary"))
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(minWidth: 56)
        .padding(.vertical, 6)
        .padding(.horizontal, 8)
        .background(Color(.systemBackground).opacity(0.6))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    @ViewBuilder
    private func ingredientMatchRow(_ match: MatchResult) -> some View {
        Button {
            if let idx = matchResults.firstIndex(where: { $0.id == match.id }) {
                editingMatchIndex = idx
            }
        } label: {
            HStack(alignment: .center, spacing: 10) {
                if match.matchedFood != nil {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .font(.subheadline)
                } else {
                    Image(systemName: "questionmark.circle")
                        .foregroundStyle(.orange)
                        .font(.subheadline)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(match.raw)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    if let food = match.matchedFood {
                        Text("→ \(food.name)")
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundStyle(.primary)
                    } else {
                        Text("Search term: \"\(match.searchTerm)\"")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
                Spacer()
                Image(systemName: "pencil.circle")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .padding(.vertical, 2)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Fetch Logic

    @MainActor
    private func fetchRecipe() async {
        isLoading    = true
        errorMessage = nil

        do {
            let fetched = try await service.importRecipe(from: urlText)
            result      = fetched
            matchResults = await buildMatchResults(for: fetched.parsedIngredients)
        } catch let e as RecipeImportError {
            errorMessage = e.errorDescription
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    private func buildMatchResults(for parsed: [RecipeImportResult.ParsedIngredient]) async -> [MatchResult] {
        let allFoods = (try? modelContext.fetch(FetchDescriptor<FoodItem>())) ?? []

        return parsed.map { p in
            let food = autoMatch(searchTerm: p.searchTerm, in: allFoods)
            return MatchResult(
                id:            p.id,
                raw:           p.rawString,
                searchTerm:    p.searchTerm,
                quantity:      p.quantity,
                unit:          p.unit,
                matchedFood:   food,
                matchedServing: food?.defaultServing
            )
        }
    }

    /// Conservative auto-match: a wrong match is worse than no match.
    ///
    /// Rules:
    ///   1. Exact name match (always tried).
    ///   2. Multi-word terms (≥ 2 words): every word in the search term must appear
    ///      as a complete word in the food name, and the food name has at most
    ///      1 extra word beyond the search term. Prevents "parmesan" matching
    ///      "Chicken with Garlic Parmesan Potatoes".
    ///   3. Single-word terms ≥ 6 chars: food name starts with the term AND is
    ///      short (≤ term length + 12 chars). Matches "Parmesan Cheese" for
    ///      "parmesan" but not a 40-char composite dish name.
    ///   4. No broad "contains" fallback — single short words like "salt",
    ///      "pepper", "lemon" return nil rather than matching the wrong food.
    private func autoMatch(searchTerm: String, in foods: [FoodItem]) -> FoodItem? {
        let term      = searchTerm.lowercased().trimmingCharacters(in: .whitespaces)
        let termWords = term.components(separatedBy: .whitespaces).filter { !$0.isEmpty }

        // 1. Exact name match
        if let exact = foods.first(where: { $0.name.lowercased() == term }) { return exact }

        // 2. Multi-word search terms: all words must appear as complete words in the food name
        if termWords.count >= 2 {
            return foods.first { food in
                let foodWords = food.name.lowercased()
                    .components(separatedBy: .whitespaces)
                    .filter { !$0.isEmpty }
                let allMatch = termWords.allSatisfy { tw in foodWords.contains { $0 == tw } }
                return allMatch && foodWords.count <= termWords.count + 1
            }
        }

        // 3. Single-word terms ≥ 6 chars: starts-with at a word boundary AND food name is short.
        //    "pepper" must NOT match "pepperoni" — the next char after the term must be a space or end.
        if term.count >= 6 {
            return foods.first { food in
                let foodLower = food.name.lowercased()
                let wordBoundaryMatch = foodLower == term || foodLower.hasPrefix(term + " ")
                return wordBoundaryMatch && food.name.count <= term.count + 12
            }
        }

        // 4. Single short words (< 6 chars): exact only, already handled above — return nil
        return nil
    }

    // MARK: - Apply

    private func applyRecipe(_ result: RecipeImportResult) {
        let matched: [(food: FoodItem, serving: ServingSize, quantity: Double, rawText: String, unit: String)] = matchResults.compactMap { match in
            guard let food = match.matchedFood,
                  let serving = match.matchedServing else { return nil }
            return (food: food, serving: serving, quantity: match.quantity, rawText: match.raw, unit: match.unit)
        }

        let unmatched = matchResults
            .filter { $0.matchedFood == nil }
            .map { ImportedRecipeData.UnmatchedHint(
                raw:        $0.raw,
                searchTerm: $0.searchTerm,
                quantity:   $0.quantity,
                unit:       $0.unit
            )}

        onImport(ImportedRecipeData(
            name:               result.name,
            servingsYield:      result.servingsYield,
            sourceURL:          result.sourceURL,
            directions:         result.directions,
            matchedIngredients: matched,
            unmatchedIngredients: unmatched,
            nutrition:          result.nutrition
        ))
        dismiss()
    }
}

// MARK: - Match Food Picker Sheet

/// Lets the user manually assign (or clear) the food match for one ingredient line.
/// Shows My Foods first, then searches USDA / FatSecret / OpenFoodFacts online.
/// Picking an online result creates and saves the FoodItem automatically.
/// Opens with the ingredient's search term pre-filled so results load immediately.
@MainActor
private struct MatchFoodPickerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    let rawIngredient: String
    let searchTerm: String          // pre-fills the search bar on open
    let current: FoodItem?
    let onSelect: (FoodItem?) -> Void

    @State private var searchText        = ""
    @State private var myFoods: [FoodItem]      = []
    @State private var onlineResults: [ProductInfo] = []
    @State private var isSearchingOnline = false
    @State private var isSaving          = false
    @State private var searchError: String?
    @State private var searchTask: Task<Void, Never>?

    var body: some View {
        NavigationStack {
            List {
                // ── Clear / skip ────────────────────────────────────────────
                Section {
                    Button { onSelect(nil) } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "xmark.circle").foregroundStyle(.secondary)
                            Text("No match — skip this ingredient").foregroundStyle(.secondary)
                            Spacer()
                            if current == nil {
                                Image(systemName: "checkmark").foregroundStyle(.blue)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }

                // ── My Foods ─────────────────────────────────────────────────
                if !myFoods.isEmpty {
                    Section("My Foods") {
                        ForEach(myFoods) { food in
                            Button { onSelect(food) } label: { myFoodRow(food) }
                                .buttonStyle(.plain)
                        }
                    }
                }

                // ── Online (USDA + FatSecret + OFf) ─────────────────────────
                if !searchText.trimmingCharacters(in: .whitespaces).isEmpty {
                    Section {
                        if isSearchingOnline {
                            HStack(spacing: 10) {
                                ProgressView()
                                Text("Searching online…").foregroundStyle(.secondary)
                            }
                        } else if let err = searchError {
                            Text(err).font(.caption).foregroundStyle(.red)
                        } else if onlineResults.isEmpty {
                            Text("No online results found.")
                                .font(.caption).foregroundStyle(.secondary)
                        } else {
                            ForEach(onlineResults) { product in
                                Button {
                                    Task { await selectOnlineResult(product) }
                                } label: {
                                    onlineResultRow(product)
                                }
                                .buttonStyle(.plain)
                                .disabled(isSaving)
                            }
                        }
                    } header: {
                        HStack {
                            Text("Search Online")
                            if isSaving {
                                ProgressView().scaleEffect(0.75).padding(.leading, 4)
                            }
                        }
                    }
                }
            }
            .listStyle(.plain)
            .searchable(text: $searchText, prompt: "Search foods or type to search online")
            .onChange(of: searchText) { _, new in
                loadMyFoods()
                scheduleOnlineSearch(query: new)
            }
            .navigationTitle("Assign Food")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .safeAreaInset(edge: .top) {
                HStack(spacing: 8) {
                    Image(systemName: "list.bullet").font(.caption).foregroundStyle(.secondary)
                    Text(rawIngredient).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                    Spacer()
                }
                .padding(.horizontal).padding(.vertical, 8)
                .background(Color(.secondarySystemBackground))
            }
        }
        .task {
            // Pre-fill search with the ingredient's parsed search term and fire immediately
            searchText = searchTerm
            loadMyFoods()
            scheduleOnlineSearch(query: searchTerm)
        }
    }

    // MARK: - Row Views

    @ViewBuilder
    private func myFoodRow(_ food: FoodItem) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(food.name).fontWeight(.medium).foregroundStyle(.primary)
                if let brand = food.brand, !brand.isEmpty {
                    Text(brand).font(.caption).foregroundStyle(.secondary)
                }
                Text("\(Int(food.calories)) cal · \(food.source)")
                    .font(.caption2).foregroundStyle(.blue)
            }
            Spacer()
            if food.id == current?.id {
                Image(systemName: "checkmark").foregroundStyle(.blue)
            }
        }
    }

    @ViewBuilder
    private func onlineResultRow(_ product: ProductInfo) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(product.displayName).fontWeight(.medium).foregroundStyle(.primary)
                if let brand = product.brands, !brand.isEmpty {
                    Text(brand).font(.caption).foregroundStyle(.secondary)
                }
                HStack(spacing: 6) {
                    Text(sourceLabel(product.code)).font(.caption2).foregroundStyle(.orange)
                    if let serving = product.servingSize {
                        Text(serving).font(.caption2).foregroundStyle(.tertiary)
                    }
                }
            }
            Spacer()
            Image(systemName: "plus.circle").foregroundStyle(Color("BrandAccent"))
        }
    }

    private func sourceLabel(_ code: String) -> String {
        if code.hasPrefix("usda_")       { return "USDA" }
        if code.hasPrefix("fatsecret_")  { return "FatSecret" }
        return "Open Food Facts"
    }

    // MARK: - My Foods Loading

    private func loadMyFoods() {
        let descriptor = FetchDescriptor<FoodItem>(sortBy: [SortDescriptor(\.name)])
        var results = (try? modelContext.fetch(descriptor)) ?? []
        if !searchText.isEmpty {
            results = results.filter {
                $0.name.localizedCaseInsensitiveContains(searchText)
                || ($0.brand?.localizedCaseInsensitiveContains(searchText) ?? false)
            }
        }
        myFoods = results
    }

    // MARK: - Online Search (debounced 400 ms)

    private func scheduleOnlineSearch(query: String) {
        searchTask?.cancel()
        onlineResults     = []
        searchError       = nil
        isSearchingOnline = false
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard trimmed.count >= 2 else { return }
        isSearchingOnline = true
        searchTask = Task {
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            do {
                let results = try await UnifiedFoodSearchService.shared.searchAllDatabases(query: trimmed)
                guard !Task.isCancelled else { return }
                onlineResults     = Array(results.prefix(20))
                isSearchingOnline = false
            } catch {
                guard !Task.isCancelled else { return }
                isSearchingOnline = false
                searchError = "Search failed — check your connection."
            }
        }
    }

    // MARK: - Select Online Result → Create FoodItem

    @MainActor
    private func selectOnlineResult(_ product: ProductInfo) async {
        isSaving = true
        defer { isSaving = false }

        // Reuse if already saved under this barcode/code
        let code = product.code
        if let existing = (try? modelContext.fetch(
            FetchDescriptor<FoodItem>(predicate: #Predicate { $0.barcode == code })
        ))?.first {
            onSelect(existing)
            return
        }

        // Fetch full details for accurate nutrition + portions
        let detailed: ProductInfo
        do { detailed = try await UnifiedFoodSearchService.shared.getProductDetails(code: code) }
        catch { detailed = product }

        onSelect(makeFoodItem(from: detailed))
    }

    // MARK: - FoodItem Factory

    @MainActor
    private func makeFoodItem(from product: ProductInfo) -> FoodItem {
        let n          = product.nutriments
        let isFatSecret = product.code.hasPrefix("fatsecret_")
        let isUSDA      = product.code.hasPrefix("usda_")

        // ── Serving resolution ─────────────────────────────────────────────
        let servingLabel: String
        let servingGrams: Double?

        if isUSDA, let portions = product.portions, !portions.isEmpty {
            let bulk = ["package", "bag", "box", "container", "can", "pouch"]
            let sorted = portions.sorted { a, b in
                let bulkA = bulk.contains { a.modifier.lowercased().contains($0) }
                let bulkB = bulk.contains { b.modifier.lowercased().contains($0) }
                if bulkA != bulkB { return !bulkA }
                return a.gramWeight < b.gramWeight
            }
            let p = sorted[0]
            servingLabel = p.amount == 1.0 ? p.modifier
                : "\(p.amount.truncatingRemainder(dividingBy:1)==0 ? "\(Int(p.amount))" : "\(p.amount)") \(p.modifier)"
            servingGrams = p.gramWeight
        } else if let s = product.servingSize, !s.isEmpty {
            servingLabel = s
            servingGrams = gramWeightFromLabel(s)
        } else {
            servingLabel = "1 serving"
            servingGrams = nil
        }

        // ── Macro nutrition ────────────────────────────────────────────────
        let calories: Double
        let protein:  Double
        let carbs:    Double
        let fat:      Double

        if isFatSecret {
            calories = n?.energyKcalServing?.value ?? 0
            protein  = n?.proteinsServing?.value   ?? 0
            carbs    = n?.carbohydratesServing?.value ?? 0
            fat      = n?.fatServing?.value        ?? 0
        } else if let grams = servingGrams, grams > 0,
                  let n100 = n?.energyKcal100g?.value, n100 > 0 {
            let scale = grams / 100.0
            calories = n100 * scale
            protein  = (n?.proteins100g?.value      ?? 0) * scale
            carbs    = (n?.carbohydrates100g?.value ?? 0) * scale
            fat      = (n?.fat100g?.value           ?? 0) * scale
        } else {
            calories = n?.energyKcalServing?.value    ?? 0
            protein  = n?.proteinsServing?.value      ?? 0
            carbs    = n?.carbohydratesServing?.value ?? 0
            fat      = n?.fatServing?.value           ?? 0
        }

        // ── Micronutrients (g-based fields → per-serving g) ───────────────
        func gramMicro(_ per100g: FlexibleDouble?, perServing: FlexibleDouble?) -> Double? {
            if isFatSecret { return perServing?.value }
            if let grams = servingGrams, let v = per100g?.value { return v * grams / 100.0 }
            return perServing?.value
        }
        // Sodium: stored as g/100g in Nutriments (OFf convention).
        // FoodItem.sodium is mg (perServing mode → mg/serving).
        func sodiumMg() -> Double? {
            if isFatSecret { return n?.sodiumServing?.value }   // FatSecret sends mg directly
            if let grams = servingGrams, let v = n?.sodium100g?.value { return v * 1000 * grams / 100.0 }
            if let v = n?.sodiumServing?.value { return v * 1000 }  // OFf serving is g → mg
            return nil
        }

        let source = isUSDA ? "USDA" : isFatSecret ? "FatSecret" : "OpenFoodFacts"

        let food = FoodItem(
            name: product.displayName,
            brand: product.brands,
            barcode: product.code,
            source: source,
            nutritionMode: .perServing,
            calories: calories, protein: protein, carbs: carbs, fat: fat,
            fiber:        gramMicro(n?.fiber100g,        perServing: n?.fiberServing),
            sugar:        gramMicro(n?.sugars100g,       perServing: n?.sugarsServing),
            saturatedFat: gramMicro(n?.saturatedFat100g, perServing: n?.saturatedFatServing),
            sodium:       sodiumMg()
        )
        // Normalize to per-100g. servingGrams nil → 100g nominal (factor = 1.0).
        let effectiveGrams = servingGrams ?? 100.0
        food.normalizeToPerHundredGrams(gramWeightPerServing: servingGrams)
        modelContext.insert(food)

        // Default serving — always provide gramWeight.
        let servingUnit = ServingSizeParser.parse(servingLabel).flatMap { parsed in
            parsed.unit == .serving ? nil : parsed.unit.rawValue
        } ?? ServingSizeParser.parseUnit(servingLabel)?.rawValue
        let defServing = ServingSize(
            label: servingLabel, gramWeight: effectiveGrams,
            isDefault: true, sortOrder: 0, unit: servingUnit
        )
        defServing.foodItem = food
        modelContext.insert(defServing)
        food.servingSizes.append(defServing)

        // USDA: add all other portions as additional ServingSizes
        if isUSDA, let portions = product.portions, portions.count > 1 {
            let bulk = ["package", "bag", "box", "container", "can", "pouch"]
            let sorted = portions.sorted { a, b in
                let bulkA = bulk.contains { a.modifier.lowercased().contains($0) }
                let bulkB = bulk.contains { b.modifier.lowercased().contains($0) }
                if bulkA != bulkB { return !bulkA }
                return a.gramWeight < b.gramWeight
            }
            for (i, p) in sorted.dropFirst().enumerated() {
                let lbl = p.amount == 1.0 ? p.modifier
                    : "\(p.amount.truncatingRemainder(dividingBy:1)==0 ? "\(Int(p.amount))" : "\(p.amount)") \(p.modifier)"
                let portionUnit = ServingSizeParser.parse(lbl).flatMap { parsed in
                    parsed.unit == .serving ? nil : parsed.unit.rawValue
                } ?? ServingSizeParser.parseUnit(lbl)?.rawValue
                let s = ServingSize(
                    label: lbl, gramWeight: p.gramWeight,
                    isDefault: false, sortOrder: i + 1, unit: portionUnit
                )
                s.foodItem = food
                modelContext.insert(s)
                food.servingSizes.append(s)
            }
        }

        return food
    }

    /// Extract gram weight from a serving label like "1 cup (240g)" → 240.0
    private func gramWeightFromLabel(_ label: String) -> Double? {
        let pattern = #"\((\d+(?:\.\d+)?)g\)"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: label, range: NSRange(label.startIndex..., in: label)),
              let range = Range(match.range(at: 1), in: label) else { return nil }
        return Double(label[range])
    }
}
