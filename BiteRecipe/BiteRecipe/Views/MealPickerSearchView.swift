//
//  MealPickerSearchView.swift
//  BiteRecipe
//
//  Four-tab search inside MealEntrySheet:
//    Tab 0 — Recipes: local SwiftData search
//    Tab 1 — Foods: all FoodItems + live UnifiedFoodSearchService API
//    Tab 2 — Meals: past BiteLedger logged meals grouped by (day, mealType)
//    Tab 3 — Note: free-text note entry (no nutrition, no stepper)
//
//  Callback: (recipe, foodItem, note, servingSize, count)
//  Note tab passes note non-nil; recipe/food/meal tabs pass note nil.
//  Caller decides whether to dismiss the sheet or stay open.
//

import SwiftUI
import SwiftData
import BiteLedgerCore

// Identifiable wrapper for a tapped meal group — drives the OccasionSelectionView sheet.
private struct PlannerMealGroup: Identifiable {
    let id = UUID()
    let date: Date
    let mealType: MealType
    let logs: [FoodLog]
}

struct MealPickerSearchView: View {
    @Environment(\.modelContext) private var modelContext

    var onSelect: (Recipe?, FoodItem?, String?, ServingSize?, Double) -> Void

    // MARK: - State

    @State private var selectedTab = 0
    @State private var searchText = ""
    @State private var recipes: [Recipe] = []
    @State private var localFoods: [FoodItem] = []
    @State private var liveResults: [ProductInfo] = []
    @State private var isSearchingLive = false
    @State private var isLoadingMeals = false
    @State private var selectedItem: PickerSelection? = nil
    @State private var servingCount: Double = 1.0
    @State private var isCommitting = false
    @State private var liveSearchTask: Task<Void, Never>? = nil

    // Meals tab
    @State private var allLogs: [FoodLog] = []
    @State private var mealSearchLogs: [FoodLog] = []
    @State private var mealSearchTask: Task<Void, Never>? = nil
    @State private var selectedMealGroup: PlannerMealGroup? = nil

    private enum PickerSelection {
        case recipe(Recipe)
        case foodItem(FoodItem, ServingSize?)
        case liveProduct(ProductInfo)
    }

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            // Tab picker
            Picker("", selection: $selectedTab) {
                Text("Recipes").tag(0)
                Text("Foods").tag(1)
                Text("Meals").tag(2)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 4)
            .onChange(of: selectedTab) { _, newTab in
                selectedItem = nil
                liveResults = []
                if newTab == 2 {
                    startMealSearch(query: searchText)
                } else {
                    search(searchText)
                }
            }

            // Shared search bar for Recipes, Foods, and Meals tabs
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(Color.textSecondary)
                TextField(
                    selectedTab == 0 ? "Search recipes…"
                        : selectedTab == 2 ? "Search past meals…"
                        : "Search foods…",
                    text: $searchText
                )
                .autocorrectionDisabled()
                if isSearchingLive || (selectedTab == 2 && isLoadingMeals) {
                    ProgressView().scaleEffect(0.7)
                } else if !searchText.isEmpty {
                    Button {
                        searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(Color.textSecondary)
                    }
                }
            }
            .padding(14)
            .background(Color.surfaceCard, in: RoundedRectangle(cornerRadius: 14))
            .padding(.horizontal, 16)
            .padding(.vertical, 8)

            if let selection = selectedItem {
                selectionConfirmView(selection: selection)
            } else if selectedTab == 2 {
                mealsListView
            } else {
                resultsListView
            }
        }
        .onChange(of: searchText) { _, query in
            if selectedTab == 2 {
                startMealSearch(query: query)
            } else {
                search(query)
            }
        }
        .onAppear { search("") }
        .task {
            // Load recent logs once — Meals tab groups these by (day, mealType).
            // Shared store means BiteLedger-logged meals appear here automatically.
            isLoadingMeals = true
            let cutoff = Calendar.current.date(byAdding: .day, value: -90, to: Date()) ?? Date()
            var descriptor = FetchDescriptor<FoodLog>(
                predicate: #Predicate { $0.timestamp > cutoff },
                sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
            )
            descriptor.fetchLimit = 500
            allLogs = (try? modelContext.fetch(descriptor)) ?? []
            isLoadingMeals = false
        }
        .sheet(item: $selectedMealGroup) { group in
            // Logs are already sorted by calories desc in groupedMeals.
            let occasion = DinnerOccasion(date: group.date, mealType: group.mealType,
                                          logs: group.logs)
            OccasionSelectionView(occasion: occasion) { selectedLogs in
                for log in selectedLogs {
                    guard let food = log.foodItem else { continue }
                    onSelect(nil, food, nil, log.servingSize, log.quantity)
                }
            }
        }
    }

    // MARK: - Meals tab

    private var groupedMeals: [(date: Date, mealType: MealType, logs: [FoodLog])] {
        // When search is active and results are ready, use mealSearchLogs (SQL-filtered).
        // When browsing (empty query), use allLogs.
        // During the 400ms debounce window, return [] so we don't trigger lazy faults.
        let usingSearchResults = !searchText.isEmpty && !mealSearchLogs.isEmpty
        let logsSource = usingSearchResults ? mealSearchLogs : allLogs

        let calendar = Calendar.current
        let grouped = Dictionary(grouping: logsSource) { log -> String in
            let day = calendar.startOfDay(for: log.timestamp)
            return "\(day.timeIntervalSince1970)-\(log.mealType.rawValue)"
        }

        // Dinner first within a day (dinner=1, lunch=2, breakfast=3, snack=0)
        let mealPriority: [MealType: Int] = [.snack: 0, .dinner: 1, .lunch: 2, .breakfast: 3]

        let sorted = grouped.map { _, logs -> (date: Date, mealType: MealType, logs: [FoodLog]) in
            let first = logs.first!
            let day = calendar.startOfDay(for: first.timestamp)
            // Sort items by calories desc so main dish leads in OccasionSelectionView
            let sortedLogs = logs.sorted { $0.caloriesAtLogTime > $1.caloriesAtLogTime }
            return (day, first.mealType, sortedLogs)
        }
        .sorted { a, b in
            if a.date != b.date { return a.date > b.date }
            return (mealPriority[a.mealType] ?? 99) < (mealPriority[b.mealType] ?? 99)
        }

        let filtered: [(date: Date, mealType: MealType, logs: [FoodLog])]
        if searchText.isEmpty || usingSearchResults {
            filtered = sorted
        } else {
            filtered = []  // debounce pending — avoid lazy-faulting N relationships
        }
        return Array(filtered.prefix(60))
    }

    private var mealsListView: some View {
        Group {
            if isLoadingMeals {
                ProgressView()
                    .frame(maxWidth: .infinity, minHeight: 200)
            } else if groupedMeals.isEmpty {
                ContentUnavailableView(
                    searchText.isEmpty ? "No Meals Yet" : "No Matching Meals",
                    systemImage: "list.bullet.clipboard",
                    description: Text(searchText.isEmpty
                        ? "Log meals in BiteLedger to see them here."
                        : "No meals match '\(searchText)'.")
                )
                .frame(minHeight: 200)
            } else {
                LazyVStack(spacing: 10) {
                    ForEach(groupedMeals.indices, id: \.self) { idx in
                        let meal = groupedMeals[idx]
                        mealGroupCard(meal)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
            }
        }
    }

    private func mealGroupCard(
        _ meal: (date: Date, mealType: MealType, logs: [FoodLog])
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(meal.mealType.rawValue.capitalized)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.textPrimary)
                    Text(meal.date.lastUsedDisplay)
                        .font(.caption)
                        .foregroundStyle(Color.textSecondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text("\(meal.logs.count) item\(meal.logs.count == 1 ? "" : "s")")
                        .font(.caption)
                        .foregroundStyle(Color.textSecondary)
                    Text("\(Int(meal.logs.reduce(0) { $0 + $1.caloriesAtLogTime })) cal")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(Color.brandAccent)
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                ForEach(meal.logs.prefix(3), id: \.persistentModelID) { log in
                    if let food = log.foodItem {
                        HStack(spacing: 6) {
                            Image(systemName: "fork.knife")
                                .font(.system(size: 10))
                                .foregroundStyle(Color.textTertiary)
                                .frame(width: 14)
                            Text(food.name)
                                .font(.caption)
                                .foregroundStyle(Color.textSecondary)
                                .lineLimit(1)
                            Spacer()
                            Text("\(Int(log.caloriesAtLogTime)) cal")
                                .font(.caption2)
                                .foregroundStyle(Color.textTertiary)
                        }
                    }
                }
                if meal.logs.count > 3 {
                    Text("+ \(meal.logs.count - 3) more")
                        .font(.caption2)
                        .foregroundStyle(Color.textTertiary)
                        .padding(.leading, 20)
                }
            }
        }
        .padding(12)
        .background(Color.surfaceCard, in: RoundedRectangle(cornerRadius: 12))
        .contentShape(Rectangle())
        .accessibilityLabel(
            "\(meal.mealType.rawValue.capitalized), \(meal.date.lastUsedDisplay), \(meal.logs.count) items, \(Int(meal.logs.reduce(0) { $0 + $1.caloriesAtLogTime })) calories"
        )
        .accessibilityHint("Tap to select items to add to your plan")
        .onTapGesture {
            selectedMealGroup = PlannerMealGroup(
                date: meal.date, mealType: meal.mealType, logs: meal.logs
            )
        }
    }

    // MARK: - Recipes / Foods results list
    //
    // NOTE: lives inside MealEntrySheet's ScrollView — use LazyVStack, not List.
    // List collapses to zero height inside a parent ScrollView.

    private var resultsListView: some View {
        let isEmpty = selectedTab == 0
            ? recipes.isEmpty
            : (localFoods.isEmpty && liveResults.isEmpty)

        return Group {
            if isEmpty {
                ContentUnavailableView(
                    searchText.isEmpty
                        ? (selectedTab == 0 ? "No Recipes" : "No Foods")
                        : "No Results",
                    systemImage: searchText.isEmpty ? "fork.knife" : "magnifyingglass",
                    description: Text(searchText.isEmpty
                        ? (selectedTab == 0
                           ? "Add recipes in the Recipes tab."
                           : "Search above or log foods in BiteLedger.")
                        : "Try a different search term.")
                )
                .frame(minHeight: 200)
            } else {
                LazyVStack(spacing: 0) {
                    if selectedTab == 0 {
                        ForEach(recipes) { recipe in
                            Button {
                                selectedItem = .recipe(recipe)
                                servingCount = 1.0
                            } label: {
                                recipeRow(recipe)
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 10)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .background(Color.surfacePrimary)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            Divider().padding(.leading, 16)
                        }
                    } else {
                        if !localFoods.isEmpty {
                            rowSectionHeader(searchText.isEmpty ? "All Foods" : "Foods")
                            ForEach(localFoods) { food in
                                Button {
                                    selectedItem = .foodItem(food, food.defaultServing)
                                    servingCount = 1.0
                                } label: {
                                    foodRow(food)
                                        .padding(.horizontal, 16)
                                        .padding(.vertical, 10)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .background(Color.surfacePrimary)
                                        .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                Divider().padding(.leading, 16)
                            }
                        }
                        if !liveResults.isEmpty {
                            rowSectionHeader("Search Results")
                            ForEach(liveResults, id: \.code) { product in
                                Button {
                                    selectedItem = .liveProduct(product)
                                    servingCount = 1.0
                                } label: {
                                    liveProductRow(product)
                                        .padding(.horizontal, 16)
                                        .padding(.vertical, 10)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .background(Color.surfacePrimary)
                                        .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                Divider().padding(.leading, 16)
                            }
                        }
                    }
                }
            }
        }
    }

    private func rowSectionHeader(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(Color.textSecondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.top, 10)
            .padding(.bottom, 4)
            .background(Color.surfacePrimary)
    }

    // MARK: - Row views

    private func recipeRow(_ recipe: Recipe) -> some View {
        HStack(spacing: 12) {
            RecipeThumbnail(imageURL: recipe.imageURL, size: 44)
            VStack(alignment: .leading, spacing: 2) {
                Text(recipe.name)
                    .font(.subheadline)
                    .foregroundStyle(Color.textPrimary)
                if let category = recipe.recipeCategory {
                    Text(category)
                        .font(.caption)
                        .foregroundStyle(Color.textSecondary)
                }
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(Color.textTertiary)
        }
    }

    private func foodRow(_ food: FoodItem) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "fork.knife")
                .frame(width: 44, height: 44)
                .background(Color.surfaceCard, in: RoundedRectangle(cornerRadius: 8))
                .foregroundStyle(Color.textSecondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(food.name)
                    .font(.subheadline)
                    .foregroundStyle(Color.textPrimary)
                if let serving = food.defaultServing {
                    Text(serving.label)
                        .font(.caption)
                        .foregroundStyle(Color.textSecondary)
                }
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(Color.textTertiary)
        }
    }

    private func liveProductRow(_ product: ProductInfo) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .frame(width: 44, height: 44)
                .background(Color.surfaceCard, in: RoundedRectangle(cornerRadius: 8))
                .foregroundStyle(Color.textSecondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(product.displayName)
                    .font(.subheadline)
                    .foregroundStyle(Color.textPrimary)
                if let brand = product.brands, !brand.isEmpty {
                    Text(brand)
                        .font(.caption)
                        .foregroundStyle(Color.textSecondary)
                }
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(Color.textTertiary)
        }
    }

    // MARK: - Selection confirmation (serving stepper + Add button)

    private func selectionConfirmView(selection: PickerSelection) -> some View {
        VStack(spacing: 24) {
            HStack(spacing: 12) {
                switch selection {
                case .recipe(let recipe):
                    RecipeThumbnail(imageURL: recipe.imageURL, size: 56)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(recipe.name)
                            .font(.headline)
                            .foregroundStyle(Color.textPrimary)
                        if let category = recipe.recipeCategory {
                            Text(category)
                                .font(.caption)
                                .foregroundStyle(Color.textSecondary)
                        }
                    }
                case .foodItem(let food, _):
                    Image(systemName: "fork.knife")
                        .frame(width: 56, height: 56)
                        .background(Color.surfaceCard, in: RoundedRectangle(cornerRadius: 8))
                        .foregroundStyle(Color.textSecondary)
                    Text(food.name)
                        .font(.headline)
                        .foregroundStyle(Color.textPrimary)
                case .liveProduct(let product):
                    Image(systemName: "magnifyingglass")
                        .frame(width: 56, height: 56)
                        .background(Color.surfaceCard, in: RoundedRectangle(cornerRadius: 8))
                        .foregroundStyle(Color.textSecondary)
                    Text(product.displayName)
                        .font(.headline)
                        .foregroundStyle(Color.textPrimary)
                }
                Spacer()
                Button {
                    selectedItem = nil
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(Color.textSecondary)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)

            Divider()

            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    switch selection {
                    case .recipe:
                        Text("Batches")
                            .font(.subheadline)
                            .foregroundStyle(Color.textPrimary)
                        Text("1 = full recipe")
                            .font(.caption)
                            .foregroundStyle(Color.textTertiary)
                    case .foodItem, .liveProduct:
                        Text("Servings")
                            .font(.subheadline)
                            .foregroundStyle(Color.textPrimary)
                    }
                }
                Spacer()
                Stepper(
                    value: $servingCount,
                    in: 0.5...10.0,
                    step: 0.5
                ) {
                    Text(servingCount.truncatingRemainder(dividingBy: 1) == 0
                         ? String(Int(servingCount))
                         : String(format: "%.1g", servingCount))
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(Color.textPrimary)
                    .frame(minWidth: 32, alignment: .center)
                }
            }
            .padding(.horizontal, 16)

            Divider()

            Button {
                commitSelection(selection)
            } label: {
                Group {
                    if isCommitting {
                        HStack(spacing: 8) {
                            ProgressView().tint(.white).scaleEffect(0.85)
                            Text("Adding…")
                        }
                    } else {
                        Text("Add")
                    }
                }
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(Color.brandPrimary, in: RoundedRectangle(cornerRadius: 14))
                .foregroundStyle(.white)
            }
            .disabled(isCommitting)
            .padding(.horizontal, 16)
            .padding(.bottom, 8)
        }
    }

    // MARK: - Commit selection

    private func commitSelection(_ selection: PickerSelection) {
        switch selection {
        case .recipe(let recipe):
            onSelect(recipe, nil, nil, nil, servingCount)
            resetPicker()
        case .foodItem(let food, let serving):
            onSelect(nil, food, nil, serving, servingCount)
            resetPicker()
        case .liveProduct(let product):
            isCommitting = true
            Task {
                if let food = await createOrFetchFood(product: product) {
                    onSelect(nil, food, nil, food.defaultServing, servingCount)
                    resetPicker()
                }
                isCommitting = false
            }
        }
    }

    private func resetPicker() {
        selectedItem = nil
        searchText = ""
        liveResults = []
        servingCount = 1.0
        search("")
    }

    // MARK: - Search (Recipes + Foods tabs)

    private func search(_ query: String) {
        let trimmed = query.trimmingCharacters(in: .whitespaces)

        if selectedTab == 0 {
            // Recipes — local only
            if trimmed.isEmpty {
                recipes = (try? modelContext.fetch(
                    FetchDescriptor<Recipe>(sortBy: [SortDescriptor(\.name)])
                )) ?? []
            } else {
                recipes = (try? modelContext.fetch(FetchDescriptor<Recipe>(
                    predicate: #Predicate { $0.name.localizedStandardContains(trimmed) },
                    sortBy: [SortDescriptor(\.name)]
                ))) ?? []
            }
        } else if selectedTab == 1 {
            // Foods — all FoodItems when empty, local match + live API when searching
            if trimmed.isEmpty {
                localFoods = (try? modelContext.fetch(
                    FetchDescriptor<FoodItem>(sortBy: [SortDescriptor(\.name)])
                )) ?? []
                liveResults = []
            } else {
                localFoods = (try? modelContext.fetch(FetchDescriptor<FoodItem>(
                    predicate: #Predicate { $0.name.localizedStandardContains(trimmed) },
                    sortBy: [SortDescriptor(\.name)]
                ))) ?? []
                searchLiveAPI(query: trimmed)
            }
        }
    }

    private func searchLiveAPI(query: String) {
        liveSearchTask?.cancel()
        isSearchingLive = true
        liveSearchTask = Task {
            do {
                let results = try await UnifiedFoodSearchService.shared.searchAllDatabases(query: query)
                guard !Task.isCancelled else { return }
                liveResults = results
            } catch {
                guard !Task.isCancelled else { return }
                liveResults = []
            }
            isSearchingLive = false
        }
    }

    // MARK: - Meals tab search (debounced SQL — mirrors BiteLedger FoodSearchView)

    /// Debounced async meal search. Finds FoodItems matching the first query word via SQL
    /// predicate, then collects complete meals from allLogs (recent) and individual
    /// matched logs (older). Matches BiteLedger's FoodSearchView.startMealSearch() exactly.
    private func startMealSearch(query: String) {
        mealSearchTask?.cancel()
        guard !query.isEmpty else {
            mealSearchLogs = []
            return
        }
        mealSearchTask = Task {
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            let firstWord = query.split(separator: " ").first.map(String.init) ?? query
            let matchingFoods = (try? modelContext.fetch(
                FetchDescriptor<FoodItem>(
                    predicate: #Predicate { $0.name.localizedStandardContains(firstWord) }
                )
            )) ?? []
            let calendar = Calendar.current
            func mealKey(_ log: FoodLog) -> String {
                let day = calendar.startOfDay(for: log.timestamp)
                return "\(day.timeIntervalSince1970)-\(log.mealType.rawValue)"
            }
            let matchingFoodLogs = matchingFoods.flatMap { $0.foodLogs }
            let matchedMealKeys = Set(matchingFoodLogs.map { mealKey($0) })
            // Recent meals: pull ALL logs for the matching meal from allLogs (complete meal).
            let recentComplete = allLogs.filter { matchedMealKeys.contains(mealKey($0)) }
            let coveredKeys = Set(recentComplete.map { mealKey($0) })
            // Older meals: fetch complete meals from DB for each uncovered (day, mealType) pair.
            // Group by key first to avoid one DB fetch per matched food in the same meal.
            let olderByKey = Dictionary(
                grouping: matchingFoodLogs.filter { !coveredKeys.contains(mealKey($0)) },
                by: { mealKey($0) }
            )
            var olderComplete: [FoodLog] = []
            for (_, repLogs) in olderByKey {
                guard let rep = repLogs.first else { continue }
                let dayStart = calendar.startOfDay(for: rep.timestamp)
                guard let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) else { continue }
                let mt = rep.mealType
                // Fetch all logs for this day; filter mealType in Swift (enum predicate unreliable).
                let dayLogs = (try? modelContext.fetch(FetchDescriptor<FoodLog>(
                    predicate: #Predicate { $0.timestamp >= dayStart && $0.timestamp < dayEnd }
                ))) ?? repLogs
                olderComplete.append(contentsOf: dayLogs.filter { $0.mealType == mt })
            }
            guard !Task.isCancelled else { return }
            mealSearchLogs = (recentComplete + olderComplete)
                .sorted { $0.timestamp > $1.timestamp }
        }
    }

    // MARK: - Food item creation (mirrors RecipeImportReviewView.createOrFetchUSDAFood)

    @MainActor
    private func createOrFetchFood(product: ProductInfo) async -> FoodItem? {
        let code = product.code
        if !code.isEmpty {
            let descriptor = FetchDescriptor<FoodItem>(
                predicate: #Predicate { $0.source == code }
            )
            if let existing = try? modelContext.fetch(descriptor).first {
                return existing
            }
        }

        let detailed = (try? await UnifiedFoodSearchService.shared.getProductDetails(code: code)) ?? product

        guard let n = detailed.nutriments,
              let cal = n.energyKcal100g?.value, cal > 0 else { return nil }

        let food = FoodItem(
            name: detailed.displayName,
            brand: detailed.brands,
            barcode: code.isEmpty ? nil : code,
            source: code.isEmpty ? "manual" : code,
            nutritionMode: .per100g,
            calories: cal,
            protein: n.proteins100g?.value ?? 0,
            carbs: n.carbohydrates100g?.value ?? 0,
            fat: n.fat100g?.value ?? 0,
            fiber: n.fiber100g?.value,
            sugar: n.sugars100g?.value,
            saturatedFat: n.saturatedFat100g?.value,
            sodium: n.sodium100g.map { $0.value * 1_000 },
            cholesterol: n.cholesterol100g.map { $0.value * 1_000 },
            potassium: n.potassium100g.map { $0.value * 1_000 },
            calcium: n.calcium100g.map { $0.value * 1_000 },
            iron: n.iron100g.map { $0.value * 1_000 },
            vitaminA: n.vitaminA100g.map { $0.value * 1_000_000 },
            vitaminC: n.vitaminC100g.map { $0.value * 1_000 }
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
            let serving = ServingSize(
                label: detailed.servingSize ?? "1 serving",
                isDefault: true
            )
            serving.foodItem = food
            modelContext.insert(serving)
        }

        try? modelContext.save()
        return food
    }
}

// MARK: - RecipeThumbnail

private struct RecipeThumbnail: View {
    let imageURL: String?
    let size: CGFloat

    var body: some View {
        Group {
            if let urlString = imageURL, let url = URL(string: urlString) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().scaledToFill()
                    default:
                        placeholderContent
                    }
                }
            } else {
                placeholderContent
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var placeholderContent: some View {
        ZStack {
            Color.surfaceCard
            Image(systemName: "fork.knife")
                .font(.system(size: size * 0.35))
                .foregroundStyle(Color.textTertiary)
        }
    }
}
