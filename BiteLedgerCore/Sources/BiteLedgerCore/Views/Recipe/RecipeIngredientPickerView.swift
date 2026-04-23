import SwiftUI
import SwiftData

// MARK: - RecipeIngredientPickerView

/// A two-page sheet for adding an ingredient to a recipe.
///
/// Page 1: Search My Foods, with a live online search (USDA / FatSecret / OFf)
///         that appears as a second section when the user types.
/// Page 2: Pick a serving size and quantity, with a live nutrition preview.
///
/// Pass `initialSearch` to pre-fill and auto-fire the search (used by the
/// "Find" hint buttons in RecipeEditorView).
///
/// Calls `onAdd(food, serving, quantity)` when the user confirms.
@MainActor
public struct RecipeIngredientPickerView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    let initialSearch: String
    let initialQuantity: Double
    let onAdd: (FoodItem, ServingSize, Double) -> Void

    public init(initialSearch: String = "", initialQuantity: Double = 1.0,
                onAdd: @escaping (FoodItem, ServingSize, Double) -> Void) {
        self.initialSearch   = initialSearch
        self.initialQuantity = initialQuantity
        self.onAdd           = onAdd
        _searchText = State(initialValue: initialSearch)
    }

    @State private var searchText: String
    @State private var allFoods: [FoodItem] = []

    // Online search
    @State private var onlineResults: [ProductInfo] = []
    @State private var isSearchingOnline  = false
    @State private var isSavingOnline     = false
    @State private var onlineSearchTask: Task<Void, Never>?

    // Online → Page 2 navigation
    @State private var pendingOnlineFood: FoodItem?
    @State private var showOnlineServingPage = false

    // MARK: - Body

    public var body: some View {
        NavigationStack {
            foodSearchPage
                .navigationTitle("Add Ingredient")
                .navigationBarTitleDisplayMode(.inline)
                .navigationDestination(isPresented: $showOnlineServingPage) {
                    if let food = pendingOnlineFood {
                        IngredientServingPage(food: food, initialQuantity: initialQuantity) { serving, quantity in
                            onAdd(food, serving, quantity)
                            dismiss()
                        }
                    }
                }
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { dismiss() }
                    }
                }
        }
        .task {
            loadFoods()
            if !initialSearch.trimmingCharacters(in: .whitespaces).isEmpty {
                scheduleOnlineSearch(query: initialSearch)
            }
        }
    }

    // MARK: - Page 1: Food Search

    private var foodSearchPage: some View {
        List {
            // ── My Foods ────────────────────────────────────────────────────
            if !allFoods.isEmpty {
                Section(searchText.isEmpty ? "" : "My Foods") {
                    ForEach(allFoods) { food in
                        NavigationLink {
                            IngredientServingPage(food: food, initialQuantity: initialQuantity) { serving, quantity in
                                onAdd(food, serving, quantity)
                                dismiss()
                            }
                        } label: {
                            foodRow(food)
                        }
                    }
                }
            } else if !searchText.isEmpty && !isSearchingOnline {
                Section("My Foods") {
                    Text("No matches in My Foods")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }

            // ── Online (USDA + FatSecret + OFf) ─────────────────────────────
            if !searchText.trimmingCharacters(in: .whitespaces).isEmpty {
                Section {
                    if isSearchingOnline {
                        HStack(spacing: 10) {
                            ProgressView()
                            Text("Searching online…").foregroundStyle(.secondary)
                        }
                    } else if onlineResults.isEmpty {
                        Text("No online results found.")
                            .font(.caption).foregroundStyle(.secondary)
                    } else {
                        ForEach(onlineResults) { product in
                            Button {
                                Task { await selectOnlineProduct(product) }
                            } label: {
                                onlineRow(product)
                            }
                            .buttonStyle(.plain)
                            .disabled(isSavingOnline)
                        }
                    }
                } header: {
                    HStack {
                        Text("Search Online")
                        if isSavingOnline {
                            ProgressView().scaleEffect(0.75).padding(.leading, 4)
                        }
                    }
                }
            }
        }
        .listStyle(.plain)
        .overlay {
            if searchText.isEmpty && allFoods.isEmpty {
                ContentUnavailableView {
                    Label("No Foods Yet", systemImage: "fork.knife")
                } description: {
                    Text("Add foods in the main food log, or type above to search online.")
                }
            }
        }
        .searchable(text: $searchText, prompt: "Search foods or type to search online")
        .onChange(of: searchText) { _, new in
            loadFoods()
            scheduleOnlineSearch(query: new)
        }
    }

    // MARK: - Row Views

    @ViewBuilder
    private func foodRow(_ food: FoodItem) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(food.name).foregroundStyle(.primary).fontWeight(.medium)
            if let brand = food.brand, !brand.isEmpty {
                Text(brand).font(.caption).foregroundStyle(.secondary)
            }
            HStack(spacing: 8) {
                Text("\(Int(food.calories)) cal").font(.caption2).foregroundStyle(.blue)
                if let serving = food.defaultServing {
                    Text(serving.label).font(.caption2).foregroundStyle(.tertiary)
                }
                Text(food.source).font(.caption2).foregroundStyle(.orange)
            }
        }
    }

    @ViewBuilder
    private func onlineRow(_ product: ProductInfo) -> some View {
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
            Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
        }
    }

    private func sourceLabel(_ code: String) -> String {
        if code.hasPrefix("usda_")      { return "USDA" }
        if code.hasPrefix("fatsecret_") { return "FatSecret" }
        return "Open Food Facts"
    }

    // MARK: - My Foods Loading

    private func loadFoods() {
        do {
            let descriptor = FetchDescriptor<FoodItem>(sortBy: [SortDescriptor(\FoodItem.name)])
            var foods = try modelContext.fetch(descriptor)
            if !searchText.isEmpty {
                foods = foods.filter {
                    $0.name.localizedCaseInsensitiveContains(searchText)
                    || ($0.brand?.localizedCaseInsensitiveContains(searchText) ?? false)
                }
            }
            allFoods = foods
        } catch {
            print("RecipeIngredientPickerView: failed to load foods: \(error)")
            allFoods = []
        }
    }

    // MARK: - Online Search (debounced 400 ms)

    private func scheduleOnlineSearch(query: String) {
        onlineSearchTask?.cancel()
        onlineResults     = []
        isSearchingOnline = false
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard trimmed.count >= 2 else { return }
        isSearchingOnline = true
        onlineSearchTask = Task {
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
            }
        }
    }

    // MARK: - Online Result Selection → Create FoodItem → Page 2

    private func selectOnlineProduct(_ product: ProductInfo) async {
        isSavingOnline = true
        defer { isSavingOnline = false }

        let code = product.code
        if let existing = (try? modelContext.fetch(
            FetchDescriptor<FoodItem>(predicate: #Predicate { $0.barcode == code })
        ))?.first {
            pendingOnlineFood    = existing
            showOnlineServingPage = true
            return
        }

        let detailed: ProductInfo
        do { detailed = try await UnifiedFoodSearchService.shared.getProductDetails(code: code) }
        catch { detailed = product }

        pendingOnlineFood    = makeFoodItem(from: detailed)
        showOnlineServingPage = true
    }

    // MARK: - FoodItem Factory

    private func makeFoodItem(from product: ProductInfo) -> FoodItem {
        let n           = product.nutriments
        let isFatSecret = product.code.hasPrefix("fatsecret_")
        let isUSDA      = product.code.hasPrefix("usda_")

        let servingLabel: String
        let servingGrams: Double?

        if isUSDA, let portions = product.portions, !portions.isEmpty {
            let bulk   = ["package", "bag", "box", "container", "can", "pouch"]
            let sorted = portions.sorted { a, b in
                let ba = bulk.contains { a.modifier.lowercased().contains($0) }
                let bb = bulk.contains { b.modifier.lowercased().contains($0) }
                if ba != bb { return !ba }
                return a.gramWeight < b.gramWeight
            }
            let p = sorted[0]
            let amtStr = p.amount.truncatingRemainder(dividingBy: 1) == 0
                ? "\(Int(p.amount))" : "\(p.amount)"
            servingLabel = p.amount == 1.0 ? p.modifier : "\(amtStr) \(p.modifier)"
            servingGrams = p.gramWeight
        } else if let s = product.servingSize, !s.isEmpty {
            servingLabel = s
            servingGrams = gramWeightFromLabel(s)
        } else {
            servingLabel = "1 serving"
            servingGrams = nil
        }

        let calories: Double; let protein: Double; let carbs: Double; let fat: Double
        if isFatSecret {
            calories = n?.energyKcalServing?.value ?? 0
            protein  = n?.proteinsServing?.value   ?? 0
            carbs    = n?.carbohydratesServing?.value ?? 0
            fat      = n?.fatServing?.value        ?? 0
        } else if let grams = servingGrams, grams > 0,
                  let cal100 = n?.energyKcal100g?.value, cal100 > 0 {
            let scale = grams / 100.0
            calories = cal100 * scale
            protein  = (n?.proteins100g?.value      ?? 0) * scale
            carbs    = (n?.carbohydrates100g?.value ?? 0) * scale
            fat      = (n?.fat100g?.value           ?? 0) * scale
        } else {
            calories = n?.energyKcalServing?.value    ?? 0
            protein  = n?.proteinsServing?.value      ?? 0
            carbs    = n?.carbohydratesServing?.value ?? 0
            fat      = n?.fatServing?.value           ?? 0
        }

        func gramMicro(_ per100g: FlexibleDouble?, perServing: FlexibleDouble?) -> Double? {
            if isFatSecret { return perServing?.value }
            if let g = servingGrams, let v = per100g?.value { return v * g / 100.0 }
            return perServing?.value
        }
        func sodiumMg() -> Double? {
            if isFatSecret { return n?.sodiumServing?.value }
            if let g = servingGrams, let v = n?.sodium100g?.value { return v * 1000 * g / 100.0 }
            if let v = n?.sodiumServing?.value { return v * 1000 }
            return nil
        }

        let source = isUSDA ? "USDA" : isFatSecret ? "FatSecret" : "OpenFoodFacts"
        let food = FoodItem(
            name: product.displayName, brand: product.brands, barcode: product.code,
            source: source, nutritionMode: .perServing,
            calories: calories, protein: protein, carbs: carbs, fat: fat,
            fiber:        gramMicro(n?.fiber100g,        perServing: n?.fiberServing),
            sugar:        gramMicro(n?.sugars100g,       perServing: n?.sugarsServing),
            saturatedFat: gramMicro(n?.saturatedFat100g, perServing: n?.saturatedFatServing),
            sodium:       sodiumMg()
        )
        let effectiveGrams = servingGrams ?? 100.0
        food.normalizeToPerHundredGrams(gramWeightPerServing: servingGrams)
        modelContext.insert(food)

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

        if isUSDA, let portions = product.portions, portions.count > 1 {
            let bulk   = ["package", "bag", "box", "container", "can", "pouch"]
            let sorted = portions.sorted { a, b in
                let ba = bulk.contains { a.modifier.lowercased().contains($0) }
                let bb = bulk.contains { b.modifier.lowercased().contains($0) }
                if ba != bb { return !ba }
                return a.gramWeight < b.gramWeight
            }
            for (i, p) in sorted.dropFirst().enumerated() {
                let amtStr = p.amount.truncatingRemainder(dividingBy: 1) == 0
                    ? "\(Int(p.amount))" : "\(p.amount)"
                let lbl = p.amount == 1.0 ? p.modifier : "\(amtStr) \(p.modifier)"
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

    private func gramWeightFromLabel(_ label: String) -> Double? {
        let pattern = #"\((\d+(?:\.\d+)?)g\)"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: label, range: NSRange(label.startIndex..., in: label)),
              let range = Range(match.range(at: 1), in: label) else { return nil }
        return Double(label[range])
    }
}

// MARK: - Page 2: Serving + Quantity Picker

/// Shown after the user selects a food. Lets them pick a serving size,
/// set a quantity, and see a live nutrition preview before confirming.
private struct IngredientServingPage: View {
    let food: FoodItem
    let initialQuantity: Double
    let onConfirm: (ServingSize, Double) -> Void

    init(food: FoodItem, initialQuantity: Double = 1.0, onConfirm: @escaping (ServingSize, Double) -> Void) {
        self.food            = food
        self.initialQuantity = initialQuantity
        self.onConfirm       = onConfirm
        let qty = max(0.5, initialQuantity)
        _quantity     = State(initialValue: qty)
        _quantityText = State(initialValue: qty.truncatingRemainder(dividingBy: 1) == 0
            ? String(Int(qty)) : String(format: "%.2g", qty))
    }

    @State private var selectedServing: ServingSize?
    @State private var quantity: Double
    @State private var quantityText: String

    private var resolvedServing: ServingSize? {
        selectedServing ?? food.defaultServing ?? food.servingSizes.first
    }

    private var preview: NutritionCalculator.Result {
        guard let serving = resolvedServing else { return .zero }
        return NutritionCalculator.preview(food: food, serving: serving, quantity: quantity)
    }

    private var sortedServings: [ServingSize] {
        food.servingSizes.sorted { $0.sortOrder < $1.sortOrder }
    }

    var body: some View {
        Form {
            Section("Serving Size") {
                if sortedServings.isEmpty {
                    Text("No serving sizes available").foregroundStyle(.secondary)
                } else if sortedServings.count == 1 {
                    Text(sortedServings[0].displayLabel).foregroundStyle(.secondary)
                } else {
                    Picker("Serving", selection: $selectedServing) {
                        ForEach(sortedServings) { serving in
                            Text(serving.displayLabel).tag(serving as ServingSize?)
                        }
                    }
                    .pickerStyle(.wheel)
                    .frame(height: 120)
                }
            }

            Section("Quantity") {
                HStack {
                    Button { adjustQuantity(by: -0.5) } label: {
                        Image(systemName: "minus.circle.fill")
                            .font(.title2)
                            .foregroundStyle(quantity > 0.5 ? Color.brandAccent : .gray)
                    }
                    .buttonStyle(.plain).disabled(quantity <= 0.5)

                    Spacer()

                    TextField("Qty", text: $quantityText)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.center)
                        .font(.title2.monospacedDigit())
                        .frame(width: 80)
                        .onChange(of: quantityText) { _, newValue in
                            if let parsed = Double(newValue), parsed > 0 { quantity = parsed }
                        }

                    Spacer()

                    Button { adjustQuantity(by: 0.5) } label: {
                        Image(systemName: "plus.circle.fill")
                            .font(.title2).foregroundStyle(Color.brandAccent)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.vertical, 4)
            }

            Section {
                nutritionLabel
            }
        }
        .navigationTitle(food.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Add") {
                    guard let serving = resolvedServing else { return }
                    onConfirm(serving, quantity)
                }
                .fontWeight(.semibold)
                .disabled(resolvedServing == nil || quantity <= 0)
            }
        }
        .onAppear {
            selectedServing = food.defaultServing ?? food.servingSizes.first
        }
    }

    private func adjustQuantity(by delta: Double) {
        let newValue = max(0.5, (quantity + delta * 2).rounded() / 2)
        quantity = newValue
        quantityText = newValue.truncatingRemainder(dividingBy: 1) == 0
            ? String(Int(newValue)) : String(format: "%.1f", newValue)
    }

    // MARK: - FDA Nutrition Label

    private var nutritionLabel: some View {
        ElevatedCard(padding: 0, cornerRadius: 20) {
            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Nutrition Facts")
                        .font(.system(size: 28, weight: .black))
                        .foregroundStyle(Color.textPrimary)
                    Rectangle().fill(Color.textPrimary).frame(height: 8)
                }
                .padding(.horizontal, 16).padding(.top, 16)

                VStack(spacing: 0) {
                    Text("Amount per serving")
                        .font(.system(size: 11, weight: .semibold))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 8)

                    HStack(alignment: .firstTextBaseline) {
                        Text("Calories").font(.system(size: 28, weight: .black))
                        Spacer()
                        Text("\(Int(preview.calories))").font(.system(size: 40, weight: .black))
                    }
                    .padding(.vertical, 4)

                    Rectangle().fill(Color.textPrimary).frame(height: 6).padding(.vertical, 4)

                    HStack {
                        Spacer()
                        Text("% Daily Value*").font(.system(size: 12, weight: .bold))
                    }
                    .padding(.bottom, 4)

                    thinLine()
                    labelRow("Total Fat",         preview.fat,                "g",  bold: true,  dv: 78)
                    if let v = preview.saturatedFat, v > 0 {
                        thinLine(); indentRow("Saturated Fat", v, "g", dv: 20)
                    }
                    if let v = preview.transFat, v > 0 {
                        thinLine(); indentRow("Trans Fat", v, "g", dv: nil)
                    }
                    thinLine()
                    labelRow("Cholesterol",       preview.cholesterol ?? 0,   "mg", bold: true,  dv: 300)
                    thinLine()
                    labelRow("Sodium",            preview.sodium ?? 0,        "mg", bold: true,  dv: 2300)
                    thinLine()
                    labelRow("Total Carbohydrate", preview.carbs,             "g",  bold: true,  dv: 275)
                    if let v = preview.fiber, v > 0 {
                        thinLine(); indentRow("Dietary Fiber", v, "g", dv: 28)
                    }
                    if let v = preview.sugar, v > 0 {
                        thinLine(); indentRow("Total Sugars", v, "g", dv: nil)
                    }
                    thinLine()
                    labelRow("Protein",           preview.protein,            "g",  bold: true,  dv: 50)

                    let hasVitMins = [preview.vitaminD, preview.calcium, preview.iron, preview.potassium]
                        .contains { $0 != nil && $0! > 0 }
                    if hasVitMins {
                        Rectangle().fill(Color.textPrimary).frame(height: 8).padding(.vertical, 4)
                        if let v = preview.vitaminD,  v > 0 { labelRow("Vitamin D",  v, "mcg", bold: false, dv: 20);    thinLine() }
                        if let v = preview.calcium,   v > 0 { labelRow("Calcium",    v, "mg",  bold: false, dv: 1300);  thinLine() }
                        if let v = preview.iron,      v > 0 { labelRow("Iron",       v, "mg",  bold: false, dv: 18);    thinLine() }
                        if let v = preview.potassium, v > 0 { labelRow("Potassium",  v, "mg",  bold: false, dv: 4700) }
                    }

                    Rectangle().fill(Color.textPrimary).frame(height: 4).padding(.top, 4)
                    Text("* The % Daily Value tells you how much a nutrient in a serving of food contributes to a daily diet. 2,000 calories a day is used for general nutrition advice.")
                        .font(.system(size: 9))
                        .foregroundStyle(Color.textSecondary)
                        .padding(.top, 6)
                }
                .padding(.horizontal, 16).padding(.bottom, 16)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, -16)
    }

    private func thinLine() -> some View {
        Rectangle().fill(Color.textPrimary).frame(height: 1)
    }

    private func labelRow(_ label: String, _ value: Double, _ unit: String,
                           bold: Bool, dv: Double?) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text(label)
                .font(.system(size: 14))
                .fontWeight(bold ? .black : .regular)
            Spacer()
            Text(fmtVal(value) + unit)
                .font(.system(size: 14))
                .fontWeight(bold ? .bold : .regular)
                .frame(minWidth: 55, alignment: .trailing)
            if let dv, dv > 0 {
                Text("\(max(0, Int((value / dv * 100).rounded())))%")
                    .font(.system(size: 13, weight: .light))
                    .foregroundStyle(Color.textSecondary)
                    .frame(width: 46, alignment: .trailing)
            } else {
                Text("").frame(width: 46)
            }
        }
        .padding(.vertical, 2)
    }

    private func indentRow(_ label: String, _ value: Double, _ unit: String, dv: Double?) -> some View {
        labelRow(label, value, unit, bold: false, dv: dv)
            .padding(.leading, 20)
    }

    private func fmtVal(_ v: Double) -> String {
        if v >= 100 { return "\(Int(v))" }
        if v >= 10  { return String(format: "%.1f", v) }
        return String(format: "%.2f", v)
    }
}
