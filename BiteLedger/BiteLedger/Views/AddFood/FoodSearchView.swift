import SwiftUI
import SwiftData
import BiteLedgerCore

/// Returns true if `text` contains `query` as a contiguous phrase OR contains
/// every whitespace-separated word in `query` (any order). Trims trailing spaces.
/// Used by My Foods, Meals, and Recipes tab filters for consistent local search.
private func matchesQuery(_ text: String, query: String) -> Bool {
    let t = text.lowercased()
    let q = query.lowercased().trimmingCharacters(in: .whitespaces)
    guard !q.isEmpty else { return true }
    if t.contains(q) { return true }
    return q.split(separator: " ").allSatisfy { t.contains($0) }
}

/// Unified food search view - handles barcode, search, and manual entry
struct FoodSearchView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    // allLogs: capped at 1000 — used for Recent Foods, serving-size lookups, and
    // fallback for searchMyFoods() before the T-14 backfill completes.
    // @Query avoided — .task loads after first render so keyboard appears immediately.
    @State private var allLogs: [FoodLog] = []
    // mealSearchLogs: logs matching the current Meals search query. Populated
    // asynchronously (debounced 400ms) via a FoodItem name predicate so SwiftData
    // filters in SQL — avoids loading all logs and lazy-faulting foodItem per row.
    @State private var mealSearchLogs: [FoodLog] = []
    @State private var mealSearchTask: Task<Void, Never>?
    // T-14: personal food history index — powers searchMyFoods() with no log cap.
    @State private var foodHistory: [FoodHistoryEntry] = []
    
    let mealType: MealType
    let onFoodAdded: (AddedFoodItem) -> Void
    
    @State private var searchText = ""
    @State private var selectedTab: SearchTab = .search
    @State private var searchResults: [ProductInfo] = []
    @State private var isSearching = false
    @State private var showBarcodeScanner = false
    @State private var showManualEntry = false
    @State private var selectedProduct: ProductInfo?
    @State private var selectedProductContext: (product: ProductInfo, existingFood: FoodItem?, initialAmount: Double?, initialPortionId: Int?, initialUnit: String?)? // Combined context
    @State private var selectedMeal: [FoodLog]?
    @State private var allRecipes: [Recipe] = []
    @State private var selectedRecipeForLog: Recipe?
    @State private var errorMessage: String?
    @State private var searchTask: Task<Void, Never>? // Track current search task
    @State private var debounceTask: Task<Void, Never>? // Track debounce task
    
    private let foodService = UnifiedFoodSearchService.shared
    
    enum SearchTab: String, CaseIterable {
        case search = "Search"
        case myFoods = "My Foods"
        case meals = "Meals"
        case recipes = "Recipes"
    }
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {

                // MARK: Search Bar
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(Color("TextSecondary"))

                    TextField("Search", text: $searchText)
                        .textFieldStyle(.plain)
                        .onChange(of: searchText) { _, newValue in
                            if selectedTab == .meals {
                                startMealSearch(query: newValue)
                            }
                            if selectedTab == .search {
                                // Cancel any existing debounce task
                                debounceTask?.cancel()
                                
                                // Clear results if search is empty
                                if newValue.isEmpty {
                                    searchTask?.cancel()
                                    searchResults = []
                                    errorMessage = nil
                                    isSearching = false
                                    return
                                }
                                
                                // Don't search until at least 3 characters
                                guard newValue.count >= 3 else {
                                    searchTask?.cancel()
                                    searchResults = []
                                    isSearching = false
                                    return
                                }
                                
                                // Debounce search by 400ms
                                debounceTask = Task {
                                    try? await Task.sleep(for: .milliseconds(400))
                                    if !Task.isCancelled {
                                        performSearch(query: newValue)
                                    }
                                }
                            }
                        }
                        .onChange(of: selectedTab) { _, newTab in
                            if newTab == .myFoods {
                                // Re-fetch in case the app-launch backfill completed after the sheet opened.
                                foodHistory = (try? modelContext.fetch(
                                    FetchDescriptor<FoodHistoryEntry>(
                                        sortBy: [SortDescriptor(\FoodHistoryEntry.lastLoggedDate, order: .reverse)]
                                    )
                                )) ?? []
                            }
                            if newTab == .meals {
                                // searchText doesn't change on tab switch, so onChange(of: searchText)
                                // won't fire. Re-trigger the meal search if a query is already typed.
                                startMealSearch(query: searchText)
                            }
                        }

                    if isSearching {
                        ProgressView()
                            .scaleEffect(0.8)
                    } else if !searchText.isEmpty {
                        Button {
                            searchText = ""
                            searchResults = []
                            errorMessage = nil
                            searchTask?.cancel()
                            debounceTask?.cancel()
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(Color("TextSecondary"))
                        }
                    }
                }
                .padding(14)
                .background(
                    RoundedRectangle(cornerRadius: 14)
                        .fill(Color("SurfaceCard"))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(Color("DividerSubtle"), lineWidth: 1)
                )
                .padding(.horizontal, 20)
                .padding(.top, 16)

                // MARK: Segmented Tabs
                Picker("Search Type", selection: $selectedTab) {
                    ForEach(SearchTab.allCases, id: \.self) { tab in
                        Text(tab.rawValue).tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .tint(Color("BrandAccent"))
                .padding(.horizontal, 20)
                .padding(.top, 16)

                // MARK: Quick Actions
                if selectedTab == .search {
                    HStack(spacing: 14) {
                        Button {
                            showBarcodeScanner = true
                        } label: {
                            Label("Scan", systemImage: "barcode.viewfinder")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .tint(Color("BrandAccent"))

                        Button {
                            quickAddWater()
                        } label: {
                            Label("Water", systemImage: "drop.fill")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .tint(Color("BrandAccent"))

                        Button {
                            showManualEntry = true
                        } label: {
                            Label("Manual", systemImage: "pencil")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .tint(Color("BrandAccent"))
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 16)
                }

                // MARK: Content
                Group {
                    switch selectedTab {
                    case .search:
                        searchTabContent
                    case .myFoods:
                        myFoodsTabContent
                    case .meals:
                        mealsTabContent
                    case .recipes:
                        recipesTabContent
                    }
                }
                .padding(.top, 16)

                Spacer(minLength: 0)
            }
            .background(Color("SurfacePrimary"))
            .task {
                // Load asynchronously so the sheet + keyboard appear without delay.
                // allLogs: Meals tab + serving-size lookups only (capped at 1000).
                var d = FetchDescriptor<FoodLog>(
                    sortBy: [SortDescriptor(\FoodLog.timestamp, order: .reverse)]
                )
                d.fetchLimit = 1000
                allLogs = (try? modelContext.fetch(d)) ?? []

                // T-14: FoodHistoryEntry — powers Recent Foods + My Foods (no cutoff).
                foodHistory = (try? modelContext.fetch(
                    FetchDescriptor<FoodHistoryEntry>(
                        sortBy: [SortDescriptor(\FoodHistoryEntry.lastLoggedDate, order: .reverse)]
                    )
                )) ?? []

                let rd = FetchDescriptor<Recipe>(sortBy: [SortDescriptor(\Recipe.name)])
                allRecipes = (try? modelContext.fetch(rd)) ?? []
            }
            .navigationTitle("Add Food")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .foregroundStyle(Color("BrandAccent"))
                }
            }
            .fullScreenCover(isPresented: $showBarcodeScanner) {
                BarcodeScannerView { barcode in
                    fetchProductByBarcode(barcode)
                }
            }
            .sheet(item: $selectedProduct) { product in
                ImprovedServingPicker(
                    product: product,
                    mealType: mealType
                ) { addedItem in
                    onFoodAdded(addedItem)
                    refreshLogs()
                    dismiss()
                }
            }
            .sheet(item: Binding(
                get: {
                    selectedProductContext.map {
                        ProductContext(
                            id: UUID(),
                            product: $0.product,
                            existingFood: $0.existingFood,
                            initialServingAmount: $0.initialAmount,
                            initialPortionId: $0.initialPortionId,
                            initialUnit: $0.initialUnit
                        )
                    }
                },
                set: {
                    selectedProductContext = $0.map {
                        ($0.product, $0.existingFood, $0.initialServingAmount, $0.initialPortionId, $0.initialUnit)
                    }
                }
            )) { context in
                ImprovedServingPicker(
                    product: context.product,
                    mealType: mealType,
                    existingFoodItem: context.existingFood,
                    initialServingAmount: context.initialServingAmount,
                    initialPortionId: context.initialPortionId,
                    initialUnit: context.initialUnit
                ) { addedItem in
                    onFoodAdded(addedItem)
                    refreshLogs()
                    selectedProductContext = nil
                    dismiss()
                }
            }
            .sheet(isPresented: $showManualEntry) {
                ManualFoodEntryView(mealType: mealType) { addedItem in
                    onFoodAdded(addedItem)
                    refreshLogs()
                    dismiss()
                }
            }
        }
    }
    
    // MARK: - Tab Content Views
    
    @ViewBuilder
    private var searchTabContent: some View {
        if let errorMessage {
                ContentUnavailableView {
                    Label("Error", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(errorMessage)
                }
            } else if searchResults.isEmpty && !searchText.isEmpty && !isSearching {
                ContentUnavailableView {
                    Label("No Results", systemImage: "magnifyingglass")
                } description: {
                    Text("Try a different search term or use manual entry")
                }
            } else if searchResults.isEmpty && searchText.isEmpty {
                // Show recent foods for this meal type
                RecentFoodsForMealView(
                    allLogs: allLogs,
                    mealType: mealType,
                    onFoodSelected: { foodItem in
                        // Find the most recent log entry for this food item
                        let mostRecentLog = allLogs.first { $0.foodItem?.id == foodItem.id }
                        _ = mostRecentLog?.quantity ?? 1.0
                        
                        let servingSizeString: String
                        if let recentLog = mostRecentLog,
                           let servingSize = recentLog.servingSize,
                           let gramWeight = servingSize.gramWeight {
                            servingSizeString = "\(servingSize.label) (\(Int(gramWeight))g)"
                        } else if let defaultServing = foodItem.defaultServing,
                                  let gramWeight = defaultServing.gramWeight {
                            servingSizeString = "\(defaultServing.label) (\(Int(gramWeight))g)"
                        } else if let defaultServing = foodItem.defaultServing {
                            let label = defaultServing.label
                            servingSizeString = label.first?.isNumber == true ? label : "1 \(label)"
                        } else {
                            servingSizeString = "1 serving"
                        }

                        // Convert FoodItem to per-100g for ProductInfo (which expects per-100g)
                        let per100gCalories: Double
                        let per100gProtein: Double
                        let per100gCarbs: Double
                        let per100gFat: Double
                        let baseGrams: Double
                        
                        if foodItem.nutritionMode == .per100g {
                            // Already per 100g
                            per100gCalories = foodItem.calories
                            per100gProtein = foodItem.protein
                            per100gCarbs = foodItem.carbs
                            per100gFat = foodItem.fat
                            baseGrams = 100.0
                        } else if let gw = foodItem.defaultServing?.gramWeight {
                            baseGrams = gw
                            per100gCalories = (foodItem.calories / baseGrams) * 100.0
                            per100gProtein = (foodItem.protein / baseGrams) * 100.0
                            per100gCarbs = (foodItem.carbs / baseGrams) * 100.0
                            per100gFat = (foodItem.fat / baseGrams) * 100.0
                        } else {
                            // perServing, no gramWeight (tablets, slices, etc.)
                            // baseGrams=1 → per100g = perServing × 100
                            // picker's totalGrams/100 multiplier then recovers the per-serving value
                            baseGrams = 1.0
                            per100gCalories = foodItem.calories * 100.0
                            per100gProtein = foodItem.protein * 100.0
                            per100gCarbs = foodItem.carbs * 100.0
                            per100gFat = foodItem.fat * 100.0
                        }
                        
                        // Helper function to convert optional nutrient to per-100g
                        func toPer100g(_ value: Double?) -> FlexibleDouble? {
                            guard let value = value else { return nil }
                            if foodItem.nutritionMode == .per100g {
                                return FlexibleDouble(value)
                            } else {
                                return FlexibleDouble((value / baseGrams) * 100.0)
                            }
                        }
                        
                        // Helper for mg → g conversion
                        // Returns nil when baseGrams=1 (perServing, no gramWeight) to avoid garbage per-100g values
                        func mgToPer100g(_ mg: Double?) -> FlexibleDouble? {
                            guard let mg = mg, baseGrams > 1.0 else { return nil }
                            let grams = mg / 1000.0
                            if foodItem.nutritionMode == .per100g {
                                return FlexibleDouble(grams)
                            } else {
                                return FlexibleDouble((grams / baseGrams) * 100.0)
                            }
                        }

                        // Helper for mcg → g conversion
                        func mcgToPer100g(_ mcg: Double?) -> FlexibleDouble? {
                            guard let mcg = mcg, baseGrams > 1.0 else { return nil }
                            let grams = mcg / 1_000_000.0
                            if foodItem.nutritionMode == .per100g {
                                return FlexibleDouble(grams)
                            } else {
                                return FlexibleDouble((grams / baseGrams) * 100.0)
                            }
                        }
                        
                        let productInfo = ProductInfo(
                            code: foodItem.barcode ?? "",
                            productName: foodItem.name,
                            brands: foodItem.brand,
                            imageUrl: nil,
                            nutriments: Nutriments(
                                energyKcal100g: FlexibleDouble(per100gCalories),
                                energyKcalComputed: per100gCalories,
                                proteins100g: FlexibleDouble(per100gProtein),
                                carbohydrates100g: FlexibleDouble(per100gCarbs),
                                sugars100g: toPer100g(foodItem.sugar),
                                fat100g: FlexibleDouble(per100gFat),
                                saturatedFat100g: toPer100g(foodItem.saturatedFat),
                                transFat100g: toPer100g(foodItem.transFat),
                                monounsaturatedFat100g: toPer100g(foodItem.monounsaturatedFat),
                                polyunsaturatedFat100g: toPer100g(foodItem.polyunsaturatedFat),
                                fiber100g: toPer100g(foodItem.fiber),
                                sodium100g: mgToPer100g(foodItem.sodium),
                                salt100g: nil,
                                cholesterol100g: mgToPer100g(foodItem.cholesterol),
                                vitaminA100g: mcgToPer100g(foodItem.vitaminA),
                                vitaminC100g: mgToPer100g(foodItem.vitaminC),
                                vitaminD100g: mcgToPer100g(foodItem.vitaminD),
                                vitaminE100g: mgToPer100g(foodItem.vitaminE),
                                vitaminK100g: mcgToPer100g(foodItem.vitaminK),
                                vitaminB6100g: mgToPer100g(foodItem.vitaminB6),
                                vitaminB12100g: mcgToPer100g(foodItem.vitaminB12),
                                folate100g: mcgToPer100g(foodItem.folate),
                                choline100g: mgToPer100g(foodItem.choline),
                                calcium100g: mgToPer100g(foodItem.calcium),
                                iron100g: mgToPer100g(foodItem.iron),
                                potassium100g: mgToPer100g(foodItem.potassium),
                                magnesium100g: mgToPer100g(foodItem.magnesium),
                                zinc100g: mgToPer100g(foodItem.zinc),
                                caffeine100g: mgToPer100g(foodItem.caffeine),
                                energyKcalServing: FlexibleDouble(foodItem.calories),
                                proteinsServing: FlexibleDouble(foodItem.protein),
                                carbohydratesServing: FlexibleDouble(foodItem.carbs),
                                sugarsServing: foodItem.sugar.map { FlexibleDouble($0) },
                                fatServing: FlexibleDouble(foodItem.fat),
                                saturatedFatServing: foodItem.saturatedFat.map { FlexibleDouble($0) },
                                fiberServing: foodItem.fiber.map { FlexibleDouble($0) },
                                sodiumServing: foodItem.sodium.map { FlexibleDouble($0 / 1000.0) },  // mg → g
                                potassiumServing: baseGrams <= 1.0 ? foodItem.potassium.map { FlexibleDouble($0) } : nil,
                                calciumServing: baseGrams <= 1.0 ? foodItem.calcium.map { FlexibleDouble($0) } : nil,
                                ironServing: baseGrams <= 1.0 ? foodItem.iron.map { FlexibleDouble($0) } : nil,
                                caffeineServing: baseGrams <= 1.0 ? foodItem.caffeine.map { FlexibleDouble($0) } : nil
                            ),
                            servingSize: servingSizeString,
                            quantity: foodItem.nutritionMode == .perServing && foodItem.defaultServing?.gramWeight == nil
                                ? servingSizeString
                                : "\(Int(baseGrams))g",
                            portions: nil,
                            countriesTags: nil,
                            lastUsed: mostRecentLog?.timestamp
                        )
                        let initAmount: Double
                        let initUnit: String?
                        if let log = mostRecentLog, let label = log.servingSize?.label,
                           let parsed = ServingSizeParser.parse(label), parsed.unit != .serving {
                            initAmount = log.quantity * parsed.amount
                            initUnit = parsed.unit.abbreviation
                        } else {
                            initAmount = mostRecentLog?.quantity ?? 1.0
                            initUnit = nil
                        }
                        selectedProductContext = (productInfo, foodItem, initAmount, nil, initUnit)
                    }
                )
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(searchResults, id: \.code) { product in
                            ProductQuickRow(product: product)
                                .onTapGesture {
                                    handleProductSelection(product)
                                }
                        }
                    }
                    .padding()
                }
            }
    }
    
    private var myFoodsTabContent: some View {
        MyFoodsListView(
            allLogs: allLogs,
            searchText: searchText,
            mealType: mealType,
            onFoodSelected: { foodItem in
                // Find the most recent log entry for this food item to get the last used serving
                let mostRecentLog = allLogs.first { $0.foodItem?.id == foodItem.id }
                
                // Convert FoodItem to ProductInfo for the serving picker
                // Use the most recent quantity if available
                _ = mostRecentLog?.quantity ?? 1.0
                let servingSizeString: String
                
                if let recentLog = mostRecentLog,
                   let servingSize = recentLog.servingSize,
                   let gramWeight = servingSize.gramWeight {
                    servingSizeString = "\(servingSize.label) (\(Int(gramWeight))g)"
                } else if let defaultServing = foodItem.defaultServing,
                          let gramWeight = defaultServing.gramWeight {
                    servingSizeString = "\(defaultServing.label) (\(Int(gramWeight))g)"
                } else if let defaultServing = foodItem.defaultServing {
                    let label = defaultServing.label
                    servingSizeString = label.first?.isNumber == true ? label : "1 \(label)"
                } else {
                    servingSizeString = "1 serving"
                }

                // Convert FoodItem to per-100g for ProductInfo (which expects per-100g)
                let per100gCalories: Double
                let per100gProtein: Double
                let per100gCarbs: Double
                let per100gFat: Double
                let baseGrams: Double
                
                if foodItem.nutritionMode == .per100g {
                    per100gCalories = foodItem.calories
                    per100gProtein = foodItem.protein
                    per100gCarbs = foodItem.carbs
                    per100gFat = foodItem.fat
                    baseGrams = 100.0
                } else if let gw = foodItem.defaultServing?.gramWeight {
                    baseGrams = gw
                    per100gCalories = (foodItem.calories / baseGrams) * 100.0
                    per100gProtein = (foodItem.protein / baseGrams) * 100.0
                    per100gCarbs = (foodItem.carbs / baseGrams) * 100.0
                    per100gFat = (foodItem.fat / baseGrams) * 100.0
                } else {
                    // perServing, no gramWeight (tablets, slices, etc.)
                    // baseGrams=1 → per100g = perServing × 100
                    // picker's totalGrams/100 multiplier then recovers the per-serving value
                    baseGrams = 1.0
                    per100gCalories = foodItem.calories * 100.0
                    per100gProtein = foodItem.protein * 100.0
                    per100gCarbs = foodItem.carbs * 100.0
                    per100gFat = foodItem.fat * 100.0
                }

                func toPer100g(_ value: Double?) -> FlexibleDouble? {
                    guard let value = value else { return nil }
                    return foodItem.nutritionMode == .per100g ? FlexibleDouble(value) : FlexibleDouble((value / baseGrams) * 100.0)
                }
                
                func mgToPer100g(_ mg: Double?) -> FlexibleDouble? {
                    guard let mg = mg, baseGrams > 1.0 else { return nil }
                    let grams = mg / 1000.0
                    return foodItem.nutritionMode == .per100g ? FlexibleDouble(grams) : FlexibleDouble((grams / baseGrams) * 100.0)
                }

                func mcgToPer100g(_ mcg: Double?) -> FlexibleDouble? {
                    guard let mcg = mcg, baseGrams > 1.0 else { return nil }
                    let grams = mcg / 1_000_000.0
                    return foodItem.nutritionMode == .per100g ? FlexibleDouble(grams) : FlexibleDouble((grams / baseGrams) * 100.0)
                }

                let productInfo = ProductInfo(
                    code: foodItem.barcode ?? "",
                    productName: foodItem.name,
                    brands: foodItem.brand,
                    imageUrl: nil,
                    nutriments: Nutriments(
                        energyKcal100g: FlexibleDouble(per100gCalories),
                        energyKcalComputed: per100gCalories,
                        proteins100g: FlexibleDouble(per100gProtein),
                        carbohydrates100g: FlexibleDouble(per100gCarbs),
                        sugars100g: toPer100g(foodItem.sugar),
                        fat100g: FlexibleDouble(per100gFat),
                        saturatedFat100g: toPer100g(foodItem.saturatedFat),
                        transFat100g: toPer100g(foodItem.transFat),
                        monounsaturatedFat100g: toPer100g(foodItem.monounsaturatedFat),
                        polyunsaturatedFat100g: toPer100g(foodItem.polyunsaturatedFat),
                        fiber100g: toPer100g(foodItem.fiber),
                        sodium100g: mgToPer100g(foodItem.sodium),
                        salt100g: nil,
                        cholesterol100g: mgToPer100g(foodItem.cholesterol),
                        vitaminA100g: mcgToPer100g(foodItem.vitaminA),
                        vitaminC100g: mgToPer100g(foodItem.vitaminC),
                        vitaminD100g: mcgToPer100g(foodItem.vitaminD),
                        vitaminE100g: mgToPer100g(foodItem.vitaminE),
                        vitaminK100g: mcgToPer100g(foodItem.vitaminK),
                        vitaminB6100g: mgToPer100g(foodItem.vitaminB6),
                        vitaminB12100g: mcgToPer100g(foodItem.vitaminB12),
                        folate100g: mcgToPer100g(foodItem.folate),
                        choline100g: mgToPer100g(foodItem.choline),
                        calcium100g: mgToPer100g(foodItem.calcium),
                        iron100g: mgToPer100g(foodItem.iron),
                        potassium100g: mgToPer100g(foodItem.potassium),
                        magnesium100g: mgToPer100g(foodItem.magnesium),
                        zinc100g: mgToPer100g(foodItem.zinc),
                        caffeine100g: mgToPer100g(foodItem.caffeine),
                        energyKcalServing: FlexibleDouble(foodItem.calories),
                        proteinsServing: FlexibleDouble(foodItem.protein),
                        carbohydratesServing: FlexibleDouble(foodItem.carbs),
                        sugarsServing: foodItem.sugar.map { FlexibleDouble($0) },
                        fatServing: FlexibleDouble(foodItem.fat),
                        saturatedFatServing: foodItem.saturatedFat.map { FlexibleDouble($0) },
                        fiberServing: foodItem.fiber.map { FlexibleDouble($0) },
                        sodiumServing: foodItem.sodium.map { FlexibleDouble($0 / 1000.0) },  // mg → g
                        potassiumServing: baseGrams <= 1.0 ? foodItem.potassium.map { FlexibleDouble($0) } : nil,
                        calciumServing: baseGrams <= 1.0 ? foodItem.calcium.map { FlexibleDouble($0) } : nil,
                        ironServing: baseGrams <= 1.0 ? foodItem.iron.map { FlexibleDouble($0) } : nil,
                        caffeineServing: baseGrams <= 1.0 ? foodItem.caffeine.map { FlexibleDouble($0) } : nil
                    ),
                    servingSize: servingSizeString,
                    quantity: foodItem.nutritionMode == .perServing && foodItem.defaultServing?.gramWeight == nil
                        ? servingSizeString
                        : "\(Int(baseGrams))g",
                    portions: nil,
                    countriesTags: nil,
                    lastUsed: mostRecentLog?.timestamp
                )
                let initAmount: Double
                let initUnit: String?
                if let log = mostRecentLog, let label = log.servingSize?.label,
                   let parsed = ServingSizeParser.parse(label), parsed.unit != .serving {
                    initAmount = log.quantity * parsed.amount
                    initUnit = parsed.unit.abbreviation
                } else {
                    initAmount = mostRecentLog?.quantity ?? 1.0
                    initUnit = nil
                }
                selectedProductContext = (productInfo, foodItem, initAmount, nil, initUnit)
            }
        )
    }

    // MARK: - Recipes Tab

    private var filteredRecipes: [Recipe] {
        guard !searchText.isEmpty else { return allRecipes }
        return allRecipes.filter { matchesQuery($0.name, query: searchText) }
    }

    @ViewBuilder
    private var recipesTabContent: some View {
        Group {
            if filteredRecipes.isEmpty {
                ContentUnavailableView {
                    Label(
                        searchText.isEmpty ? "No Recipes Yet" : "No Matching Recipes",
                        systemImage: "fork.knife"
                    )
                } description: {
                    Text(searchText.isEmpty
                         ? "Import or create recipes in the Recipes tab"
                         : "No recipes match '\(searchText)'")
                }
            } else {
                List(filteredRecipes) { recipe in
                    RecipeLogRow(recipe: recipe, perServing: recipePerServingNutrition(recipe))
                        .contentShape(Rectangle())
                        .onTapGesture { selectedRecipeForLog = recipe }
                }
                .listStyle(.plain)
            }
        }
        .sheet(item: $selectedRecipeForLog) { recipe in
            RecipeServingSheet(
                recipe: recipe,
                mealType: mealType,
                perServing: recipePerServingNutrition(recipe)
            ) { servingCount in
                logRecipe(recipe, servingCount: servingCount)
            }
        }
    }

    private func recipePerServingNutrition(_ recipe: Recipe) -> NutritionCalculator.Result {
        if let n = recipe.importedNutrition {
            return NutritionCalculator.Result(
                calories: n.calories, protein: n.protein, carbs: n.carbs, fat: n.fat,
                fiber: n.fiber, sugar: n.sugar, saturatedFat: n.saturatedFat,
                sodium: n.sodium, cholesterol: n.cholesterol, potassium: n.potassium,
                calcium: n.calcium, iron: n.iron, vitaminA: n.vitaminA, vitaminC: n.vitaminC
            )
        }
        let total = recipe.sortedIngredients.reduce(NutritionCalculator.Result.zero) { acc, ing in
            guard let food = ing.foodItem else { return acc }
            return acc + NutritionCalculator.calculate(food: food, serving: ing.servingSize, quantity: ing.quantity)
        }
        guard total.calories > 0 else { return .zero }
        let d = recipe.servingsYield > 0 ? recipe.servingsYield : 1
        return NutritionCalculator.Result(
            calories: total.calories / d, protein: total.protein / d,
            carbs: total.carbs / d, fat: total.fat / d,
            fiber: total.fiber.map { $0 / d }
        )
    }

    private func logRecipe(_ recipe: Recipe, servingCount: Int) {
        let (foodItem, servingSize) = findOrCreateRecipeFoodItem(for: recipe)
        let addedItem = AddedFoodItem(
            foodItem: foodItem,
            servingSize: servingSize,
            quantity: Double(servingCount),
            loggedAmount: Double(servingCount),
            loggedUnit: servingCount == 1 ? "serving" : "servings"
        )
        onFoodAdded(addedItem)
        refreshLogs()
        dismiss()
    }

    private func findOrCreateRecipeFoodItem(for recipe: Recipe) -> (FoodItem, ServingSize) {
        let source = "recipe_\(recipe.id.uuidString)"
        var descriptor = FetchDescriptor<FoodItem>(predicate: #Predicate { $0.source == source })
        descriptor.fetchLimit = 1
        let perServing = recipePerServingNutrition(recipe)

        if let existing = (try? modelContext.fetch(descriptor))?.first {
            // Refresh nutrition in case recipe ingredients changed since last log
            existing.calories = perServing.calories
            existing.protein  = perServing.protein
            existing.carbs    = perServing.carbs
            existing.fat      = perServing.fat
            existing.fiber    = perServing.fiber
            existing.sugar    = perServing.sugar
            existing.sodium   = perServing.sodium
            if let serving = existing.defaultServing ?? existing.servingSizes.first {
                return (existing, serving)
            }
        }

        // Create a synthetic perServing FoodItem for this recipe
        let food = FoodItem(
            name: recipe.name,
            source: source,
            nutritionMode: .perServing,
            calories: perServing.calories,
            protein: perServing.protein,
            carbs: perServing.carbs,
            fat: perServing.fat,
            fiber: perServing.fiber,
            sugar: perServing.sugar,
            sodium: perServing.sodium
        )
        food.recipe = recipe

        let serving = ServingSize(label: "1 serving", isDefault: true)
        serving.foodItem = food

        modelContext.insert(food)
        modelContext.insert(serving)
        try? modelContext.save()

        return (food, serving)
    }

    // MARK: - Meals Tab

    private var groupedMeals: [(date: Date, mealType: MealType, logs: [FoodLog])] {
        // When a debounced meal search is in flight or complete, use mealSearchLogs —
        // these are pre-filtered by FoodItem name predicate (SQL), so no per-row
        // relationship faulting needed. When browsing with no query, use allLogs (1000 cap).
        let usingSearchResults = !searchText.isEmpty && !mealSearchLogs.isEmpty
        let logsSource = usingSearchResults ? mealSearchLogs : allLogs
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: logsSource) { log -> String in
            let dateComponents = calendar.dateComponents([.year, .month, .day], from: log.timestamp)
            let dateKey = calendar.date(from: dateComponents) ?? log.timestamp
            return "\(dateKey)-\(log.mealType.rawValue)"
        }

        // Meal sort priority: snack=0, dinner=1, lunch=2, breakfast=3
        // Combined with date descending, this puts the last meal of the day at the top of each group.
        let mealPriority: [MealType: Int] = [.snack: 0, .dinner: 1, .lunch: 2, .breakfast: 3]

        let sorted = grouped.map { (_, logs) -> (date: Date, mealType: MealType, logs: [FoodLog]) in
            let firstLog = logs.first!
            return (firstLog.timestamp, firstLog.mealType, logs.sorted { $0.timestamp < $1.timestamp })
        }
        .sorted { a, b in
            let aDay = calendar.startOfDay(for: a.date)
            let bDay = calendar.startOfDay(for: b.date)
            if aDay != bDay { return aDay > bDay }
            return (mealPriority[a.mealType] ?? 99) < (mealPriority[b.mealType] ?? 99)
        }

        // Three cases:
        //   searchText empty           → show all recent meals (allLogs path)
        //   searchText set + results   → show mealSearchLogs (already SQL-filtered)
        //   searchText set + no results yet → return [] to avoid N lazy-fault reads
        //     during the 400ms debounce window. ContentUnavailableView handles display.
        let filtered: [(date: Date, mealType: MealType, logs: [FoodLog])]
        if searchText.isEmpty || usingSearchResults {
            filtered = sorted
        } else {
            // Debounce still pending — nothing to show yet.
            filtered = []
        }

        // Cap at 60 meal groups to keep the list fast to render
        return Array(filtered.prefix(60))
    }
    
    private var mealsTabContent: some View {
        Group {
            if groupedMeals.isEmpty {
                ContentUnavailableView {
                    Label(searchText.isEmpty ? "No Meals Yet" : "No Matching Meals", systemImage: "list.bullet.clipboard")
                } description: {
                    Text(searchText.isEmpty ? "Your logged meals will appear here" : "No meals contain '\(searchText)'")
                }
            } else {
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(groupedMeals.indices, id: \.self) { index in
                            let meal = groupedMeals[index]
                            VStack(alignment: .leading, spacing: 8) {
                                // Meal header
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(meal.mealType.rawValue)
                                            .font(.subheadline)
                                            .fontWeight(.semibold)
                                        
                                        Text(meal.date.lastUsedDisplay)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    
                                    Spacer()
                                    
                                    VStack(alignment: .trailing, spacing: 2) {
                                        Text("\(meal.logs.count) items")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                        
                                        Text("\(Int(meal.logs.reduce(0) { $0 + $1.caloriesAtLogTime })) cal")
                                            .font(.caption)
                                            .fontWeight(.medium)
                                            .foregroundStyle(.blue)
                                    }
                                }
                                
                                // Food items preview
                                VStack(alignment: .leading, spacing: 4) {
                                    ForEach(meal.logs.prefix(3)) { log in
                                        if let foodItem = log.foodItem {
                                            HStack {
                                                Text("• \(foodItem.name)")
                                                    .font(.caption)
                                                    .foregroundStyle(.secondary)
                                                    .lineLimit(1)
                                                
                                                Spacer()
                                                
                                                Text("\(Int(log.caloriesAtLogTime)) cal")
                                                    .font(.caption2)
                                                    .foregroundStyle(.tertiary)
                                            }
                                        }
                                    }
                                    
                                    if meal.logs.count > 3 {
                                        Text("+ \(meal.logs.count - 3) more")
                                            .font(.caption2)
                                            .foregroundStyle(.tertiary)
                                    }
                                }
                            }
                            .padding()
                            .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
                            .onTapGesture {
                                selectedMeal = meal.logs
                            }
                        }
                    }
                    .padding()
                }
            }
        }
        .sheet(item: Binding(
            get: { selectedMeal != nil ? SelectedMeal(logs: selectedMeal!) : nil },
            set: { selectedMeal = $0?.logs }
        )) { mealWrapper in
            MealItemSelectionView(
                sourceLogs: mealWrapper.logs,
                targetMealType: mealType,
                onAdd: { selectedLogs in
                    // Batch add selected logs - preserve exact gram amounts
                    for log in selectedLogs {
                        if let foodItem = log.foodItem,
                           let servingSize = log.servingSize {
                            let addedItem = AddedFoodItem(
                                foodItem: foodItem,
                                servingSize: servingSize,
                                quantity: log.quantity
                            )
                            onFoodAdded(addedItem)
                        }
                    }
                    refreshLogs()
                    dismiss()
                }
            )
        }
    }
    
    /// Debounced async meal search. Cancels any in-flight task before starting.
    /// Finds FoodItems matching the first query word via SQL predicate, collects
    /// complete meals from allLogs (recent) and individual matched logs (older).
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
            // Older meals: just the matched food's own log.
            let olderMatched = matchingFoodLogs.filter { !coveredKeys.contains(mealKey($0)) }
            mealSearchLogs = (recentComplete + olderMatched)
                .sorted { $0.timestamp > $1.timestamp }
        }
    }

    private func performSearch(query: String) {
        guard !query.isEmpty, query.count >= 3 else { return }

        // Cancel any previous search task
        searchTask?.cancel()

        isSearching = true
        errorMessage = nil

        // Create a new search task
        searchTask = Task {
            // Capture the query to ensure we only update results if this is still the current search
            let currentQuery = query
            
            // Search My Foods first (synchronous)
            let myFoodsResults = searchMyFoods(query: currentQuery)
            print("📱 Found \(myFoodsResults.count) My Foods results")

            do {
                print("🔍 Searching for: \(currentQuery)")
                let results = try await foodService.searchAllDatabases(query: currentQuery)
                
                // Check if task was cancelled or query changed
                guard !Task.isCancelled, searchText == currentQuery else {
                    print("⚠️ Search cancelled or query changed")
                    return
                }
                
                print("📦 Got \(results.count) database results")

                await MainActor.run {
                    // Double-check that this result still matches the current search text
                    guard searchText == currentQuery else {
                        print("⚠️ Query changed during search, ignoring results")
                        return
                    }
                    
                    // Filter out products without nutrition data
                    let filteredResults = results.filter {
                        if let nutriments = $0.nutriments {
                            let hasCalories = nutriments.calories > 0
                            if !hasCalories {
                                print("⚠️ Filtered out \($0.displayName) - no calories")
                            }
                            return hasCalories
                        }
                        print("⚠️ Filtered out \($0.displayName) - no nutriments")
                        return false
                    }

                    // Combine My Foods (first) + database results
                    searchResults = myFoodsResults + filteredResults

                    print("✅ Total results: \(searchResults.count) (\(myFoodsResults.count) from My Foods)")

                    if searchResults.isEmpty {
                        errorMessage = "No results found for '\(currentQuery)'"
                    }
                    isSearching = false
                }
            } catch is CancellationError {
                print("🔄 Search cancelled")
                // Don't update UI on cancellation
            } catch {
                print("❌ Search error: \(error)")
                
                // Check if task was cancelled
                guard !Task.isCancelled, searchText == currentQuery else {
                    return
                }
                
                await MainActor.run {
                    // Double-check query still matches
                    guard searchText == currentQuery else {
                        return
                    }
                    
                    // Even if database search fails, show My Foods results
                    searchResults = myFoodsResults

                    if searchResults.isEmpty {
                        errorMessage = "Search failed: \(error.localizedDescription)"
                    }
                    isSearching = false
                }
            }
        }
    }
    
    private func quickAddWater() {
        // Create a standard water FoodItem (1 cup = 8 fl oz / 237ml)
        let waterItem = FoodItem(
            name: "Water",
            brand: nil,
            barcode: nil,
            source: "Quick Add",
            nutritionMode: .per100g,
            calories: 0,
            protein: 0,
            carbs: 0,
            fat: 0
        )
        
        // Add to model context so it's saved
        modelContext.insert(waterItem)
        
        // Create default serving size (1 cup = 237g)
        let cupServing = ServingSize(
            label: "1 cup",
            gramWeight: 237.0,
            isDefault: true,
            sortOrder: 0,
            unit: ServingUnit.cup.rawValue
        )
        cupServing.foodItem = waterItem
        modelContext.insert(cupServing)
        
        // Add 1 cup (8 fl oz / 237g)
        let addedItem = AddedFoodItem(
            foodItem: waterItem,
            servingSize: cupServing,
            quantity: 1.0
        )
        
        onFoodAdded(addedItem)
        refreshLogs()
        dismiss()
    }

    private func refreshLogs() {
        var d = FetchDescriptor<FoodLog>(sortBy: [SortDescriptor(\FoodLog.timestamp, order: .reverse)])
        d.fetchLimit = 1000
        allLogs = (try? modelContext.fetch(d)) ?? []
        // Refresh the history index to reflect the food just logged.
        foodHistory = (try? modelContext.fetch(
            FetchDescriptor<FoodHistoryEntry>(
                sortBy: [SortDescriptor(\FoodHistoryEntry.lastLoggedDate, order: .reverse)]
            )
        )) ?? []
    }

    private func searchMyFoods(query: String) -> [ProductInfo] {
        // T-14: Use FoodHistoryEntry for the food list when the backfill index is populated —
        // no 1000-entry cap, so foods logged 6+ months ago appear in results.
        // Fall back to allLogs (capped at 1000) when foodHistory is empty, which happens on
        // first launch until backfillFoodHistory() completes. The fallback ensures the search
        // tab works correctly during the bootstrap period.
        var seenIDs = Set<UUID>()
        let uniqueFoods: [FoodItem]
        if !foodHistory.isEmpty {
            uniqueFoods = foodHistory.compactMap { entry in
                guard let food = entry.food, seenIDs.insert(food.id).inserted else { return nil }
                return food
            }
        } else {
            // Pre-backfill fallback: derive unique foods from the top-1000 recent logs.
            uniqueFoods = allLogs.compactMap { log in
                guard let food = log.foodItem, seenIDs.insert(food.id).inserted else { return nil }
                return food
            }
        }

        // Split search query into words (word-split matching — see CLAUDE.md).
        let searchWords = query.lowercased().split(separator: " ").map { String($0) }

        // Filter foods that contain ALL search words.
        let matchingFoods = uniqueFoods.filter { foodItem in
            let name = foodItem.name.lowercased()
            let brand = foodItem.brand?.lowercased() ?? ""
            let combinedText = "\(name) \(brand)"
            return searchWords.allSatisfy { combinedText.contains($0) }
        }

        // Convert to ProductInfo.
        return matchingFoods.map { foodItem in
            // Last-used date comes from FoodHistoryEntry (no allLogs scan needed).
            let lastUsedDate = foodHistory.first { $0.food?.id == foodItem.id }?.lastLoggedDate
                           ?? allLogs.first { $0.foodItem?.id == foodItem.id }?.timestamp
            // Most recent log for serving/calorie display accuracy (top-1000 only; falls back
            // to foodItem.nutrition for older history — correct for all display paths).
            let mostRecentLog = allLogs.first { $0.foodItem?.id == foodItem.id }
            
            // Use the actual logged values from most recent log for display accuracy
            let actualCalories = mostRecentLog?.caloriesAtLogTime ?? foodItem.calories
            let actualProtein = mostRecentLog?.proteinAtLogTime ?? foodItem.protein
            let actualCarbs = mostRecentLog?.carbsAtLogTime ?? foodItem.carbs
            let actualFat = mostRecentLog?.fatAtLogTime ?? foodItem.fat
            
            // Calculate actual grams from the log
            let actualGrams: Double
            if let log = mostRecentLog, let servingSize = log.servingSize, let gramWeight = servingSize.gramWeight {
                actualGrams = log.quantity * gramWeight
            } else if let defaultServing = foodItem.defaultServing, let gramWeight = defaultServing.gramWeight {
                actualGrams = gramWeight
            } else {
                // perServing foods with no gram weight use baseGrams=1 so the mineral/caffeine
                // per-100g values are computed as value*100, matching how paths 1 & 2 work.
                // Per-100g foods without a serving fall back to 100g as before.
                actualGrams = foodItem.nutritionMode == .perServing ? 1.0 : 100.0
            }
            
            // Convert to per-100g for ProductInfo display
            let baseGrams = actualGrams
            let per100gCalories = (actualCalories / baseGrams) * 100.0
            let per100gProtein = (actualProtein / baseGrams) * 100.0
            let per100gCarbs = (actualCarbs / baseGrams) * 100.0
            let per100gFat = (actualFat / baseGrams) * 100.0
            
            return ProductInfo(
                code: foodItem.barcode ?? "myfoods_\(foodItem.id.uuidString)",
                productName: foodItem.name,
                brands: foodItem.brand,
                imageUrl: nil,
                nutriments: Nutriments(
                    energyKcal100g: FlexibleDouble(per100gCalories),
                    energyKcalComputed: per100gCalories,
                    proteins100g: FlexibleDouble(per100gProtein),
                    carbohydrates100g: FlexibleDouble(per100gCarbs),
                    sugars100g: foodItem.sugar.map { FlexibleDouble(($0 / actualGrams) * 100.0) },
                    fat100g: FlexibleDouble(per100gFat),
                    saturatedFat100g: foodItem.saturatedFat.map { FlexibleDouble(($0 / actualGrams) * 100.0) },
                    transFat100g: foodItem.transFat.map { FlexibleDouble(($0 / actualGrams) * 100.0) },
                    monounsaturatedFat100g: foodItem.monounsaturatedFat.map { FlexibleDouble(($0 / actualGrams) * 100.0) },
                    polyunsaturatedFat100g: foodItem.polyunsaturatedFat.map { FlexibleDouble(($0 / actualGrams) * 100.0) },
                    fiber100g: foodItem.fiber.map { FlexibleDouble(($0 / actualGrams) * 100.0) },
                    sodium100g: foodItem.sodium.map { FlexibleDouble((($0 / 1000.0) / actualGrams) * 100.0) },  // mg → g
                    salt100g: nil,
                    cholesterol100g: foodItem.cholesterol.map { FlexibleDouble((($0 / 1000.0) / actualGrams) * 100.0) },  // mg → g
                    vitaminA100g: foodItem.vitaminA.map { FlexibleDouble((($0 / 1_000_000.0) / actualGrams) * 100.0) },  // mcg → g
                    vitaminC100g: foodItem.vitaminC.map { FlexibleDouble((($0 / 1000.0) / actualGrams) * 100.0) },  // mg → g
                    vitaminD100g: foodItem.vitaminD.map { FlexibleDouble((($0 / 1_000_000.0) / actualGrams) * 100.0) },  // mcg → g
                    vitaminE100g: foodItem.vitaminE.map { FlexibleDouble((($0 / 1000.0) / actualGrams) * 100.0) },  // mg → g
                    vitaminK100g: foodItem.vitaminK.map { FlexibleDouble((($0 / 1_000_000.0) / actualGrams) * 100.0) },  // mcg → g
                    vitaminB6100g: foodItem.vitaminB6.map { FlexibleDouble((($0 / 1000.0) / actualGrams) * 100.0) },  // mg → g
                    vitaminB12100g: foodItem.vitaminB12.map { FlexibleDouble((($0 / 1_000_000.0) / actualGrams) * 100.0) },  // mcg → g
                    folate100g: foodItem.folate.map { FlexibleDouble((($0 / 1_000_000.0) / actualGrams) * 100.0) },  // mcg → g
                    choline100g: foodItem.choline.map { FlexibleDouble((($0 / 1000.0) / actualGrams) * 100.0) },  // mg → g
                    calcium100g: foodItem.calcium.map { FlexibleDouble((($0 / 1000.0) / actualGrams) * 100.0) },  // mg → g
                    iron100g: foodItem.iron.map { FlexibleDouble((($0 / 1000.0) / actualGrams) * 100.0) },  // mg → g
                    potassium100g: foodItem.potassium.map { FlexibleDouble((($0 / 1000.0) / actualGrams) * 100.0) },  // mg → g
                    magnesium100g: foodItem.magnesium.map { FlexibleDouble((($0 / 1000.0) / actualGrams) * 100.0) },  // mg → g
                    zinc100g: foodItem.zinc.map { FlexibleDouble((($0 / 1000.0) / actualGrams) * 100.0) },  // mg → g
                    caffeine100g: foodItem.caffeine.map { FlexibleDouble((($0 / 1000.0) / actualGrams) * 100.0) },  // mg → g
                    energyKcalServing: FlexibleDouble(foodItem.calories),
                    proteinsServing: FlexibleDouble(foodItem.protein),
                    carbohydratesServing: FlexibleDouble(foodItem.carbs),
                    sugarsServing: foodItem.sugar.map { FlexibleDouble($0) },
                    fatServing: FlexibleDouble(actualFat),
                    saturatedFatServing: foodItem.saturatedFat.map { FlexibleDouble($0) },
                    fiberServing: foodItem.fiber.map { FlexibleDouble($0) },
                    sodiumServing: foodItem.sodium.map { FlexibleDouble($0 / 1000.0) },  // mg → g
                    potassiumServing: foodItem.nutritionMode == .perServing && foodItem.defaultServing?.gramWeight == nil ? foodItem.potassium.map { FlexibleDouble($0) } : nil,
                    calciumServing: foodItem.nutritionMode == .perServing && foodItem.defaultServing?.gramWeight == nil ? foodItem.calcium.map { FlexibleDouble($0) } : nil,
                    ironServing: foodItem.nutritionMode == .perServing && foodItem.defaultServing?.gramWeight == nil ? foodItem.iron.map { FlexibleDouble($0) } : nil,
                    caffeineServing: foodItem.nutritionMode == .perServing && foodItem.defaultServing?.gramWeight == nil ? foodItem.caffeine.map { FlexibleDouble($0) } : nil
                ),
                servingSize: {
                    if let defaultServing = foodItem.defaultServing {
                        if let gramWeight = defaultServing.gramWeight, gramWeight > 0 {
                            return "\(defaultServing.label) (\(Int(gramWeight))g)"
                        } else {
                            let label = defaultServing.label
                            return label.first?.isNumber == true ? label : "1 \(label)"
                        }
                    } else {
                        return "1 serving"
                    }
                }(),
                quantity: nil,
                portions: nil,
                countriesTags: nil,
                lastUsed: lastUsedDate
            )
        }
    }
    
    private func fetchProductByBarcode(_ barcode: String) {
        errorMessage = nil
        
        Task {
            do {
                // Barcode lookup only works with OpenFoodFacts
                let product = try await OpenFoodFactsService.shared.fetchProduct(barcode: barcode)
                await MainActor.run {
                    if let nutriments = product.nutriments, nutriments.calories > 0 {
                        selectedProduct = product
                    } else {
                        errorMessage = "Product found but missing nutrition data. Use manual entry."
                    }
                }
            } catch {
                await MainActor.run {
                    errorMessage = "Product not found in database. Try manual entry."
                }
            }
        }
    }
    
    private func handleProductSelection(_ product: ProductInfo) {
        print("🔍 handleProductSelection called for: \(product.displayName)")
        print("🔍 Product code: \(product.code)")
        
        // Check if this is from My Foods (code starts with "myfoods_")
        if product.code.hasPrefix("myfoods_") {
            let uuidString = String(product.code.dropFirst("myfoods_".count))
            if let uuid = UUID(uuidString: uuidString),
               let foodItem = allLogs.compactMap({ $0.foodItem }).first(where: { $0.id == uuid }) {
                let mostRecentLog = allLogs.first(where: { $0.foodItem?.id == uuid })
                let initAmount: Double
                let initUnit: String?
                if let log = mostRecentLog, let label = log.servingSize?.label,
                   let parsed = ServingSizeParser.parse(label), parsed.unit != .serving {
                    initAmount = log.quantity * parsed.amount
                    initUnit = parsed.unit.abbreviation
                } else {
                    initAmount = mostRecentLog?.quantity ?? 1.0
                    initUnit = nil
                }
                selectedProductContext = (product, foodItem, initAmount, nil, initUnit)
            }
            return
        }
        
        // Check if we already have this food item saved (to preserve any edits)
        let existingFood = allLogs.compactMap { $0.foodItem }
            .first { $0.barcode == product.code }
        
        if let existingFood = existingFood {
            // Use the existing food item to preserve edits
            print("✅ Found existing food item for \(product.code), using saved version with edits")
            
            // Find the most recent log entry for this food item to get the last used serving and portion
            let mostRecentLog = allLogs.first { $0.foodItem?.id == existingFood.id }
            
            print("🔍 Most recent log found: \(mostRecentLog != nil)")
            print("🔍 ServingSize: \(mostRecentLog?.servingSize?.label ?? "nil")")
            if let log = mostRecentLog, let servingSize = log.servingSize, let gramWeight = servingSize.gramWeight {
                print("🔍 TotalGrams: \(log.quantity * gramWeight)")
            }
            print("🔍 Quantity: \(mostRecentLog?.quantity ?? 0)")
            
            print("⚠️ Showing picker with last-used values")
            
            // Fallback if no recent log - use the product selection flow
            let lastServingAmount = mostRecentLog?.quantity ?? 1.0
            
            
            // Convert existing FoodItem to ProductInfo to pass to serving picker
            let per100gCalories: Double
            let per100gProtein: Double
            let per100gCarbs: Double
            let per100gFat: Double
            let baseGrams: Double
            
            if existingFood.nutritionMode == .per100g {
                per100gCalories = existingFood.calories
                per100gProtein = existingFood.protein
                per100gCarbs = existingFood.carbs
                per100gFat = existingFood.fat
                baseGrams = 100.0
            } else if let gw = existingFood.defaultServing?.gramWeight {
                baseGrams = gw
                per100gCalories = (existingFood.calories / baseGrams) * 100.0
                per100gProtein = (existingFood.protein / baseGrams) * 100.0
                per100gCarbs = (existingFood.carbs / baseGrams) * 100.0
                per100gFat = (existingFood.fat / baseGrams) * 100.0
            } else {
                // perServing, no gramWeight (tablets, slices, etc.)
                baseGrams = 1.0
                per100gCalories = existingFood.calories * 100.0
                per100gProtein = existingFood.protein * 100.0
                per100gCarbs = existingFood.carbs * 100.0
                per100gFat = existingFood.fat * 100.0
            }
            
            func toPer100g(_ value: Double?) -> FlexibleDouble? {
                guard let value = value else { return nil }
                return existingFood.nutritionMode == .per100g ? FlexibleDouble(value) : FlexibleDouble((value / baseGrams) * 100.0)
            }
            
            func mgToPer100g(_ mg: Double?) -> FlexibleDouble? {
                guard let mg = mg, baseGrams > 1.0 else { return nil }
                let grams = mg / 1000.0
                return existingFood.nutritionMode == .per100g ? FlexibleDouble(grams) : FlexibleDouble((grams / baseGrams) * 100.0)
            }

            func mcgToPer100g(_ mcg: Double?) -> FlexibleDouble? {
                guard let mcg = mcg, baseGrams > 1.0 else { return nil }
                let grams = mcg / 1_000_000.0
                return existingFood.nutritionMode == .per100g ? FlexibleDouble(grams) : FlexibleDouble((grams / baseGrams) * 100.0)
            }
            
            let productInfo = ProductInfo(
                code: existingFood.barcode ?? product.code,
                productName: existingFood.name,
                brands: existingFood.brand,
                imageUrl: nil,
                nutriments: Nutriments(
                    energyKcal100g: FlexibleDouble(per100gCalories),
                    energyKcalComputed: per100gCalories,
                    proteins100g: FlexibleDouble(per100gProtein),
                    carbohydrates100g: FlexibleDouble(per100gCarbs),
                    sugars100g: toPer100g(existingFood.sugar),
                    fat100g: FlexibleDouble(per100gFat),
                    saturatedFat100g: toPer100g(existingFood.saturatedFat),
                    transFat100g: toPer100g(existingFood.transFat),
                    monounsaturatedFat100g: toPer100g(existingFood.monounsaturatedFat),
                    polyunsaturatedFat100g: toPer100g(existingFood.polyunsaturatedFat),
                    fiber100g: toPer100g(existingFood.fiber),
                    sodium100g: mgToPer100g(existingFood.sodium),
                    salt100g: nil,
                    cholesterol100g: mgToPer100g(existingFood.cholesterol),
                    vitaminA100g: mcgToPer100g(existingFood.vitaminA),
                    vitaminC100g: mgToPer100g(existingFood.vitaminC),
                    vitaminD100g: mcgToPer100g(existingFood.vitaminD),
                    vitaminE100g: mgToPer100g(existingFood.vitaminE),
                    vitaminK100g: mcgToPer100g(existingFood.vitaminK),
                    vitaminB6100g: mgToPer100g(existingFood.vitaminB6),
                    vitaminB12100g: mcgToPer100g(existingFood.vitaminB12),
                    folate100g: mcgToPer100g(existingFood.folate),
                    choline100g: mgToPer100g(existingFood.choline),
                    calcium100g: mgToPer100g(existingFood.calcium),
                    iron100g: mgToPer100g(existingFood.iron),
                    potassium100g: mgToPer100g(existingFood.potassium),
                    magnesium100g: mgToPer100g(existingFood.magnesium),
                    zinc100g: mgToPer100g(existingFood.zinc),
                    caffeine100g: mgToPer100g(existingFood.caffeine),
                    energyKcalServing: FlexibleDouble(existingFood.calories),
                    proteinsServing: FlexibleDouble(existingFood.protein),
                    carbohydratesServing: FlexibleDouble(existingFood.carbs),
                    sugarsServing: existingFood.sugar.map { FlexibleDouble($0) },
                    fatServing: FlexibleDouble(existingFood.fat),
                    saturatedFatServing: existingFood.saturatedFat.map { FlexibleDouble($0) },
                    fiberServing: existingFood.fiber.map { FlexibleDouble($0) },
                    sodiumServing: existingFood.sodium.map { FlexibleDouble($0 / 1000.0) },  // mg → g
                    potassiumServing: baseGrams <= 1.0 ? existingFood.potassium.map { FlexibleDouble($0) } : nil,
                    calciumServing: baseGrams <= 1.0 ? existingFood.calcium.map { FlexibleDouble($0) } : nil,
                    ironServing: baseGrams <= 1.0 ? existingFood.iron.map { FlexibleDouble($0) } : nil,
                    caffeineServing: baseGrams <= 1.0 ? existingFood.caffeine.map { FlexibleDouble($0) } : nil
                ),
                servingSize: {
                    if let defaultServing = existingFood.defaultServing {
                        if let gramWeight = defaultServing.gramWeight, gramWeight > 0 {
                            return "\(defaultServing.label) (\(Int(gramWeight))g)"
                        } else {
                            let label = defaultServing.label
                            return label.first?.isNumber == true ? label : "1 \(label)"
                        }
                    } else {
                        return "1 serving"
                    }
                }(),
                quantity: nil,
                portions: nil,
                countriesTags: nil,
                lastUsed: mostRecentLog?.timestamp
            )
            
            let initAmount: Double
            let initUnit: String?
            if let log = mostRecentLog, let label = log.servingSize?.label,
               let parsed = ServingSizeParser.parse(label), parsed.unit != .serving {
                initAmount = log.quantity * parsed.amount
                initUnit = parsed.unit.abbreviation
            } else {
                initAmount = lastServingAmount
                initUnit = nil
            }
            selectedProductContext = (productInfo, existingFood, initAmount, nil, initUnit)
        } else if product.code.hasPrefix("usda_") {
            // New USDA product - fetch full details to get portions
            Task {
                do {
                    let detailedProduct = try await UnifiedFoodSearchService.shared.getProductDetails(code: product.code)
                    await MainActor.run {
                        selectedProduct = detailedProduct
                    }
                } catch {
                    print("❌ Failed to fetch USDA details: \(error)")
                    await MainActor.run {
                        selectedProduct = product
                    }
                }
            }
        } else if product.code.hasPrefix("fatsecret_") {
            // New FatSecret product - fetch full details to get sodium, fiber, sugar, etc.
            let foodId = String(product.code.dropFirst("fatsecret_".count))
            Task {
                do {
                    let detailedFood = try await FatSecretService.shared.getFoodDetails(foodId: foodId)
                    await MainActor.run {
                        selectedProduct = detailedFood.toProductInfo() ?? product
                    }
                } catch {
                    print("❌ Failed to fetch FatSecret details: \(error)")
                    await MainActor.run {
                        selectedProduct = product
                    }
                }
            }
        } else {
            // OpenFoodFacts product - use as is
            selectedProduct = product
        }
    }
}

// MARK: - Supporting Views

// Helper struct for meal selection sheet binding
private struct SelectedMeal: Identifiable {
    let id = UUID()
    let logs: [FoodLog]
}

// Helper struct for product + existing food context
private struct ProductContext: Identifiable {
    let id: UUID
    let product: ProductInfo
    let existingFood: FoodItem?
    let initialServingAmount: Double?
    let initialPortionId: Int?
    let initialUnit: String?
}

struct ProductQuickRow: View {
    let product: ProductInfo
    
    var body: some View {
        ElevatedCard(padding: 16, cornerRadius: 20) {
            HStack(spacing: 16) {
                
                // MARK: - Product Image
                
                productImage
                
                // MARK: - Text Content
                
                VStack(alignment: .leading, spacing: 6) {
                    
                    HStack(spacing: 6) {
                        Text(product.displayName)
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundStyle(Color("TextPrimary"))
                            .lineLimit(2)
                        
                        Spacer()
                        
                        // Database source badge (only if not My Foods)
                        if product.lastUsed == nil {
                            databaseBadge
                        }
                    }
                    
                    if let brand = product.brands,
                       !brand.isEmpty {
                        Text(brand)
                            .font(.caption)
                            .foregroundStyle(Color("TextSecondary"))
                            .lineLimit(1)
                    }
                    
                    HStack(spacing: 4) {
                        if let nutriments = product.nutriments {
                            // Show calories per serving if available, otherwise per 100g
                            if let servingCal = nutriments.energyKcalServing?.value,
                               servingCal > 0,
                               let servingSize = product.servingSize,
                               !servingSize.isEmpty {
                                Text("\(Int(servingCal)) cal per \(servingSize)")
                                    .font(.caption)
                                    .fontWeight(.medium)
                                    .foregroundStyle(Color("BrandAccent"))
                            } else if let portions = product.portions,
                                      let firstPortion = portions.first {
                                // USDA foods with portions - show cal per portion
                                let gramsInPortion = firstPortion.gramWeight
                                let calPer100g = nutriments.calories
                                let calPerPortion = (calPer100g / 100.0) * gramsInPortion
                                Text("\(Int(calPerPortion)) cal per \(firstPortion.modifier)")
                                    .font(.caption)
                                    .fontWeight(.medium)
                                    .foregroundStyle(Color("BrandAccent"))
                            } else {
                                // Fallback to per 100g
                                Text("\(Int(nutriments.calories)) cal per 100g")
                                    .font(.caption)
                                    .fontWeight(.medium)
                                    .foregroundStyle(Color("BrandAccent"))
                            }
                        }
                        
                        if let lastUsed = product.lastUsed {
                            Text("•")
                                .foregroundStyle(Color("TextSecondary"))
                                .font(.caption)
                            Text(lastUsed.lastUsedDisplay)
                                .font(.caption)
                                .foregroundStyle(Color("TextSecondary"))
                        }
                    }
                }
                
                Spacer(minLength: 0)
                
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(Color("TextTertiary"))
            }
        }
    }
    
    // MARK: - Image
    
    @ViewBuilder
    private var productImage: some View {
        if let imageUrl = product.imageUrl,
           let url = URL(string: imageUrl) {
            
            AsyncImage(url: url) { image in
                image
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } placeholder: {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color("SurfaceElevated"))
            }
            .frame(width: 56, height: 56)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            
        } else {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color("SurfaceElevated"))
                .frame(width: 56, height: 56)
                .overlay {
                    Image(systemName: "fork.knife")
                        .font(.caption)
                        .foregroundStyle(Color("TextSecondary"))
                }
        }
    }
    
    // MARK: - Database Badge
    
    @ViewBuilder
    private var databaseBadge: some View {
        let (label, color) = databaseSource
        
        Text(label)
            .font(.system(size: 9, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(color, in: Capsule())
    }
    
    private var databaseSource: (String, Color) {
        if product.code.hasPrefix("usda_") {
            // Check if it's FNDDS or SR Legacy based on product name patterns
            // FNDDS tends to have more specific restaurant/brand items
            let name = product.displayName.lowercased()
            
            // Common FNDDS indicators
            if name.contains("mcdonald") || name.contains("burger king") || 
               name.contains("taco bell") || name.contains("subway") ||
               name.contains("pizza hut") || name.contains("wendy") ||
               name.contains("kfc") || name.contains("domino") ||
               name.contains("chick-fil-a") || name.contains("panera") ||
               name.contains("chipotle") || name.contains("arby") {
                return ("FNDDS", .orange)
            }
            
            return ("USDA", .green)
        } else if product.code.hasPrefix("fatsecret_") {
            return ("FS", .red)
        } else if product.code.hasPrefix("myfoods_") {
            return ("MINE", .purple)
        } else {
            return ("OFF", .blue)
        }
    }
    
}

struct MyFoodsListView: View {
    @Environment(\.modelContext) private var modelContext

    // @Query keeps this live — updates automatically as the app-launch backfill
    // creates records and as new foods are logged. Solves the timing race where
    // the parent's .task snapshot was stale during the backfill window.
    // FoodHistoryEntry is small (one record per food+mealType) so @Query is fast here.
    @Query(sort: \FoodHistoryEntry.lastLoggedDate, order: .reverse)
    private var foodHistory: [FoodHistoryEntry]

    // SQL search state — populated by startMyFoodsSearch when searchText is non-empty.
    // Using a direct FetchDescriptor<FoodItem> predicate (same as the Meals tab) avoids
    // the cap on allLogs and finds foods from any point in history.
    @State private var sqlSearchResults: [FoodItem] = []
    @State private var sqlLastUsedDates: [UUID: Date] = [:]
    @State private var sqlSearchTask: Task<Void, Never>? = nil

    let allLogs: [FoodLog]
    let searchText: String
    let mealType: MealType
    let onFoodSelected: (FoodItem) -> Void

    // When a query is active: use SQL results (full history, no cap).
    // When browsing (empty query): use the history+allLogs hybrid sorted by recency.
    private var sortedFoods: [FoodItem] {
        if !searchText.isEmpty {
            return sqlSearchResults.sorted { $0.name < $1.name }
        }

        var seenIDs = Set<UUID>()
        var items: [FoodItem] = []

        // T-14: history index has no log cap. Start here so recently-used foods
        // (sorted by lastLoggedDate) surface first in the deduplication pass.
        for entry in foodHistory {
            guard let food = entry.food, seenIDs.insert(food.id).inserted else { continue }
            items.append(food)
        }

        // Supplement with allLogs for any foods not yet in the history index.
        // This covers: backfill still in progress, LoseIt imports logged before
        // T-14 shipped, and any other gap where a FoodHistoryEntry record is missing.
        for log in allLogs {
            guard let food = log.foodItem, seenIDs.insert(food.id).inserted else { continue }
            items.append(food)
        }

        return items
    }

    private func startMyFoodsSearch(query: String) {
        sqlSearchTask?.cancel()
        guard !query.isEmpty else {
            sqlSearchResults = []
            sqlLastUsedDates = [:]
            return
        }
        sqlSearchTask = Task {
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }

            // SQL predicate search — hits the full store, no recency cap.
            let candidates = (try? modelContext.fetch(
                FetchDescriptor<FoodItem>(
                    predicate: #Predicate { $0.name.localizedStandardContains(query) }
                )
            )) ?? []

            // Build the set of personally-logged food IDs — used only to guard
            // API-sourced foods (usda_*, fatsecret_*) against ghost foods that
            // were fetched by RecipeCard's ingredient matcher but never logged.
            // Manual entries, LoseIt imports, and recipe foods are always included.
            var loggedIDs = Set(foodHistory.compactMap { $0.food?.id })
            for log in allLogs {
                if let food = log.foodItem { loggedIDs.insert(food.id) }
            }

            let filtered = candidates.filter { food in
                // Always exclude seeded catalog items.
                guard !food.source.hasPrefix("usda_seed"),
                      !food.source.hasPrefix("built_in") else { return false }
                // Known user-created sources — always show even if backfill is incomplete.
                // "Manual", "Quick Add", "LoseIt Import", "CSV Import*", "recipe*", and
                // legacy empty-source records are all user-owned by definition.
                if food.source.isEmpty ||
                   food.source == "Manual" ||
                   food.source == "Quick Add" ||
                   food.source.hasPrefix("recipe") ||
                   food.source.hasPrefix("LoseIt") ||
                   food.source.hasPrefix("CSV Import") {
                    return true
                }
                // All other sources (usda_*, fatsecret_*, OFacts barcodes, etc.) are
                // API-fetched and may be ghost foods — require personal log history.
                return loggedIDs.contains(food.id)
            }

            // Pre-compute last-used dates for every result so FoodItemRow
            // never needs to fire lazy foodLogs relationship loads.
            //   Pass 1: FoodHistoryEntry index (fast, no faults)
            //   Pass 2: allLogs buffer (covers recently-logged foods)
            //   Pass 3: food.foodLogs direct access for any remainder
            //           (acceptable: small result set, runs on main actor)
            var dates: [UUID: Date] = [:]
            for entry in foodHistory {
                guard let food = entry.food, dates[food.id] == nil else { continue }
                dates[food.id] = entry.lastLoggedDate
            }
            for log in allLogs {
                guard let food = log.foodItem, dates[food.id] == nil else { continue }
                dates[food.id] = log.timestamp
            }
            for food in filtered where dates[food.id] == nil {
                dates[food.id] = food.foodLogs.max(by: { $0.timestamp < $1.timestamp })?.timestamp
            }

            guard !Task.isCancelled else { return }
            sqlSearchResults = filtered
            sqlLastUsedDates = dates
        }
    }

    var body: some View {
        Group {
            if sortedFoods.isEmpty {
                emptyStateView
            } else {
                foodListView
            }
        }
        .onAppear {
            if !searchText.isEmpty {
                startMyFoodsSearch(query: searchText)
            }
        }
        .onChange(of: searchText) { _, newValue in
            startMyFoodsSearch(query: newValue)
        }
    }
    
    private var emptyStateView: some View {
        ContentUnavailableView {
            Label(searchText.isEmpty ? "No Foods Yet" : "No Matching Foods", systemImage: "fork.knife")
        } description: {
            Text(searchText.isEmpty ? "Foods you add will appear here" : "No foods match '\(searchText)'")
        }
    }
    
    // Pre-compute last-used dates so FoodItemRow doesn't fire lazy relationship loads.
    // When search is active: use sqlLastUsedDates (built by the Task, includes a
    // food.foodLogs fallback for foods not in the history index).
    // When browsing: use FoodHistoryEntry + allLogs as before.
    private var lastUsedDates: [UUID: Date] {
        if !searchText.isEmpty {
            return sqlLastUsedDates
        }
        var result: [UUID: Date] = [:]
        for entry in foodHistory {
            guard let food = entry.food, result[food.id] == nil else { continue }
            result[food.id] = entry.lastLoggedDate
        }
        for log in allLogs {
            guard let food = log.foodItem, result[food.id] == nil else { continue }
            result[food.id] = log.timestamp
        }
        return result
    }

    private var foodListView: some View {
        ScrollView {
            LazyVStack(spacing: 8) {
                ForEach(sortedFoods, id: \.id) { foodItem in
                    FoodItemRow(foodItem: foodItem, lastUsed: lastUsedDates[foodItem.id], onTap: {
                        onFoodSelected(foodItem)
                    })
                }
            }
            .padding()
        }
    }
}

struct FoodItemRow: View {
    let foodItem: FoodItem
    let lastUsed: Date?
    let onTap: () -> Void
    
    var body: some View {
        HStack(spacing: 12) {
            foodImageView
            
            VStack(alignment: .leading, spacing: 2) {
                Text(foodItem.name)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .lineLimit(1)
                
                if let brand = foodItem.brand, !brand.isEmpty {
                    Text(brand)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                
                HStack(spacing: 4) {
                    // Display calories per base serving
                    if let defaultServing = foodItem.defaultServing {
                        Text(caloriesDisplayText(for: foodItem, serving: defaultServing))
                            .font(.caption2)
                            .foregroundStyle(.blue)
                    } else {
                        Text("\(Int(foodItem.calories)) cal")
                            .font(.caption2)
                            .foregroundStyle(.blue)
                    }

                    if let lastUsed {
                        Text("•")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                        Text(lastUsed.lastUsedDisplay)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            
            Spacer(minLength: 0)
            
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(12)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
        .onTapGesture {
            onTap()
        }
    }
    
    @ViewBuilder
    private var foodImageView: some View {
        RoundedRectangle(cornerRadius: 8)
            .fill(.quaternary)
            .frame(width: 50, height: 50)
            .overlay {
                Image(systemName: "fork.knife")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
    }
    
    private func caloriesDisplayText(for foodItem: FoodItem, serving: ServingSize) -> String {
        if foodItem.nutritionMode == .per100g, let gramWeight = serving.gramWeight, gramWeight > 0 {
            // For per-100g foods, calculate calories for the serving
            let displayCalories = Int((foodItem.calories / 100.0) * gramWeight)
            
            // Format serving size nicely
            let gramsText = gramWeight.truncatingRemainder(dividingBy: 1) == 0
                ? String(Int(gramWeight))
                : String(format: "%.0f", gramWeight)
            return "\(displayCalories) cal per \(gramsText)g"
        } else {
            // For per-serving foods, use calories directly
            let displayCalories = Int(foodItem.calories)
            return "\(displayCalories) cal/\(serving.label)"
        }
    }
}

// MARK: - Recent Foods View

struct RecentFoodsForMealView: View {
    let allLogs: [FoodLog]
    let mealType: MealType
    let onFoodSelected: (FoodItem) -> Void

    private var lastUsedDates: [UUID: Date] {
        var result: [UUID: Date] = [:]
        for log in allLogs {
            guard let food = log.foodItem, result[food.id] == nil else { continue }
            result[food.id] = log.timestamp
        }
        return result
    }

    /// Top 8 most-frequently logged foods for this meal type, excluding foods
    /// already logged today.
    private var recentFoods: [FoodItem] {
        let todaysFoodIDs = Set(
            allLogs
                .filter { Calendar.current.isDate($0.timestamp, inSameDayAs: Date()) && $0.mealType == mealType }
                .compactMap { $0.foodItem?.id }
        )

        var freq: [UUID: (food: FoodItem, count: Int)] = [:]
        for log in allLogs where log.mealType == mealType {
            guard let food = log.foodItem else { continue }
            freq[food.id] = (food, (freq[food.id]?.count ?? 0) + 1)
        }

        return freq.values
            .filter { !todaysFoodIDs.contains($0.food.id) }
            .sorted { $0.count > $1.count }
            .prefix(8)
            .map { $0.food }
    }

    var body: some View {
        Group {
            if recentFoods.isEmpty {
                ContentUnavailableView {
                    Label("Search for Food", systemImage: "magnifyingglass")
                } description: {
                    Text("Type to search 900,000+ foods, scan a barcode, or add manually")
                }
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Recent \(mealType.rawValue)")
                            .font(.headline)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal)
                            .padding(.top, 8)

                        LazyVStack(spacing: 8) {
                            ForEach(recentFoods, id: \.id) { foodItem in
                                FoodItemRow(foodItem: foodItem, lastUsed: lastUsedDates[foodItem.id], onTap: {
                                    onFoodSelected(foodItem)
                                })
                            }
                        }
                        .padding(.horizontal)
                    }
                }
            }
        }
    }
}

// MARK: - Recipe List Row

private struct RecipeLogRow: View {
    let recipe: Recipe
    let perServing: NutritionCalculator.Result

    var body: some View {
        HStack(spacing: 12) {
            // Thumbnail
            if let urlStr = recipe.imageURL, let url = URL(string: urlStr) {
                AsyncImage(url: url) { phase in
                    if let img = phase.image { img.resizable().scaledToFill() }
                    else { Color.secondary.opacity(0.12) }
                }
                .frame(width: 52, height: 52)
                .clipShape(RoundedRectangle(cornerRadius: 8))
            } else {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.secondary.opacity(0.12))
                    .frame(width: 52, height: 52)
                    .overlay {
                        Image(systemName: "fork.knife")
                            .foregroundStyle(.secondary)
                    }
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(recipe.name)
                    .font(.body)
                    .lineLimit(1)
                HStack(spacing: 8) {
                    if perServing.calories > 0 {
                        Text("\(Int(perServing.calories)) cal/serving")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if let time = recipe.displayTime {
                        Text("·")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                        Label(time, systemImage: "clock")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Recipe Serving Picker Sheet

private struct RecipeServingSheet: View {
    let recipe: Recipe
    let mealType: MealType
    let perServing: NutritionCalculator.Result
    let onAdd: (Int) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var servingCount: Int = 1

    private var totalCalories: Double { perServing.calories * Double(servingCount) }
    private var totalProtein: Double  { perServing.protein  * Double(servingCount) }
    private var totalCarbs: Double    { perServing.carbs    * Double(servingCount) }
    private var totalFat: Double      { perServing.fat      * Double(servingCount) }

    var body: some View {
        NavigationStack {
            Form {
                // Hero photo
                if let urlStr = recipe.imageURL, let url = URL(string: urlStr) {
                    AsyncImage(url: url) { phase in
                        if let img = phase.image { img.resizable().scaledToFill() }
                        else { Color.secondary.opacity(0.1) }
                    }
                    .frame(maxWidth: .infinity).frame(height: 180)
                    .clipped()
                    .listRowInsets(EdgeInsets())
                }

                // Serving stepper
                Section {
                    Stepper(value: $servingCount, in: 1...20) {
                        HStack {
                            Text("Servings")
                            Spacer()
                            Text("\(servingCount)")
                                .fontWeight(.semibold)
                        }
                    }
                } footer: {
                    if let author = recipe.author, !author.isEmpty {
                        Text("From \(author)")
                    }
                }

                // Nutrition summary
                if totalCalories > 0 {
                    Section("Nutrition\(servingCount > 1 ? " (\(servingCount) servings)" : " per serving")") {
                        HStack { Text("Calories"); Spacer(); Text("\(Int(totalCalories))").foregroundStyle(.secondary) }
                        HStack { Text("Protein");  Spacer(); Text("\(Int(totalProtein))g").foregroundStyle(.secondary) }
                        HStack { Text("Carbs");    Spacer(); Text("\(Int(totalCarbs))g").foregroundStyle(.secondary) }
                        HStack { Text("Fat");      Spacer(); Text("\(Int(totalFat))g").foregroundStyle(.secondary) }
                    }
                }

                // Add button
                Section {
                    Button {
                        onAdd(servingCount)
                    } label: {
                        HStack {
                            Spacer()
                            Text("Add to \(mealType.rawValue)")
                                .fontWeight(.semibold)
                            Spacer()
                        }
                    }
                }
            }
            .navigationTitle(recipe.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}

#Preview {
    FoodSearchView(mealType: .breakfast) { _ in }
        .modelContainer(for: FoodLog.self, inMemory: true)
}
