//
//  NutritionEnrichmentView.swift
//  BiteLedger
//

import SwiftUI
import SwiftData
import BiteLedgerCore

// MARK: - EnrichmentField

struct EnrichmentField: Identifiable {
    let id = UUID()
    let name: String
    let unit: String
    let newValue: Double
    var isSelected: Bool
}

// MARK: - NutritionEnrichmentView

struct NutritionEnrichmentView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    let foodItem: FoodItem
    let onEnriched: () -> Void

    @State private var searchQuery: String
    @State private var searchResults: [ProductInfo] = []
    @State private var isSearching = false
    @State private var searchError: String?
    @State private var isFetchingDetails = false
    @State private var detailedProduct: ProductInfo?
    @State private var enrichmentFields: [EnrichmentField] = []

    init(foodItem: FoodItem, onEnriched: @escaping () -> Void) {
        self.foodItem = foodItem
        self.onEnriched = onEnriched
        let query = [foodItem.brand, foodItem.name].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " ")
        _searchQuery = State(initialValue: query)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                searchBar
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)

                Divider()

                if isSearching || isFetchingDetails {
                    loadingView
                } else if let error = searchError {
                    errorView(error)
                } else if let product = detailedProduct, !enrichmentFields.isEmpty {
                    confirmationView(product: product)
                } else if detailedProduct != nil && enrichmentFields.isEmpty {
                    noNewFieldsView
                } else if !searchResults.isEmpty {
                    resultsList
                } else {
                    emptyState
                }
            }
            .navigationTitle("Find Nutrition Data")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    // MARK: - Search Bar

    private var searchBar: some View {
        HStack(spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search foods...", text: $searchQuery)
                    .autocorrectionDisabled()
                    .onSubmit { performSearch() }
                if !searchQuery.isEmpty {
                    Button {
                        searchQuery = ""
                        searchResults = []
                        searchError = nil
                        detailedProduct = nil
                        enrichmentFields = []
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(10)
            .background(Color(.systemGray6))
            .cornerRadius(10)

            Button("Search") {
                performSearch()
            }
            .buttonStyle(.borderedProminent)
            .disabled(searchQuery.trimmingCharacters(in: .whitespaces).isEmpty)
        }
    }

    // MARK: - Results List

    private var resultsList: some View {
        List(searchResults) { product in
            Button {
                fetchDetails(for: product)
            } label: {
                VStack(alignment: .leading, spacing: 4) {
                    Text(product.displayName)
                        .font(.body)
                        .foregroundStyle(.primary)
                        .multilineTextAlignment(.leading)
                    HStack(spacing: 8) {
                        if let brand = product.brands, !brand.isEmpty {
                            Text(brand)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        sourceBadge(for: product.code)
                        if let serving = product.servingSize {
                            Text(serving)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .listStyle(.plain)
    }

    // MARK: - Confirmation View

    @ViewBuilder
    private func confirmationView(product: ProductInfo) -> some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(product.displayName)
                            .font(.headline)
                        HStack(spacing: 8) {
                            if let brand = product.brands, !brand.isEmpty {
                                Text(brand).font(.caption).foregroundStyle(.secondary)
                            }
                            sourceBadge(for: product.code)
                        }
                    }
                    Spacer()
                    Button("Back") {
                        detailedProduct = nil
                        enrichmentFields = []
                    }
                    .font(.caption)
                    .foregroundStyle(Color("BrandAccent"))
                }

                let selectedCount = enrichmentFields.filter { $0.isSelected }.count
                Text("\(selectedCount) of \(enrichmentFields.count) fields selected")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(16)
            .background(Color(.systemGray6))

            List {
                Section {
                    ForEach($enrichmentFields) { $field in
                        Toggle(isOn: $field.isSelected) {
                            HStack {
                                Text(field.name)
                                    .font(.subheadline)
                                Spacer()
                                Text("\(formatValue(field.newValue)) \(field.unit)")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                } header: {
                    Text("Missing fields to fill in")
                } footer: {
                    Text("Only empty fields are shown. Existing values will not be overwritten.")
                }
            }
            .listStyle(.insetGrouped)

            Button {
                applyEnrichment()
            } label: {
                Text("Apply Selected Fields")
                    .fontWeight(.semibold)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(enrichmentFields.filter { $0.isSelected }.isEmpty ? Color.gray : Color("BrandAccent"))
                    .foregroundStyle(.white)
                    .cornerRadius(12)
            }
            .disabled(enrichmentFields.filter { $0.isSelected }.isEmpty)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
    }

    // MARK: - Helper Views

    private var loadingView: some View {
        VStack(spacing: 16) {
            Spacer()
            ProgressView()
                .scaleEffect(1.2)
            Text(isFetchingDetails ? "Fetching nutrition details..." : "Searching databases...")
                .foregroundStyle(.secondary)
            Spacer()
        }
    }

    private func errorView(_ error: String) -> some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 44))
                .foregroundStyle(.orange)
            Text(error)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 32)
            Button("Try Again") {
                searchError = nil
                searchResults = []
            }
            .buttonStyle(.borderedProminent)
            Spacer()
        }
    }

    private var noNewFieldsView: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "checkmark.circle")
                .font(.system(size: 44))
                .foregroundStyle(.green)
            Text("No new data available")
                .font(.headline)
            Text("This food already has all the nutrition data that this source provides.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 32)
            Button("Search Again") {
                detailedProduct = nil
                enrichmentFields = []
            }
            .buttonStyle(.borderedProminent)
            Spacer()
        }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "text.magnifyingglass")
                .font(.system(size: 50))
                .foregroundStyle(.secondary)
            Text("Find a matching food")
                .font(.headline)
            Text("Search to fill in missing nutrition fields. Only empty fields will be updated.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 32)
            Spacer()
        }
    }

    private func sourceBadge(for code: String) -> some View {
        let (label, color): (String, Color) = {
            if code.hasPrefix("usda_") { return ("USDA", .green) }
            if code.hasPrefix("fatsecret_") { return ("FatSecret", .orange) }
            return ("Open Food Facts", .blue)
        }()
        return Text(label)
            .font(.system(size: 10, weight: .semibold))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.15))
            .foregroundStyle(color)
            .cornerRadius(4)
    }

    private func formatValue(_ value: Double) -> String {
        if value >= 10 { return String(format: "%.0f", value) }
        if value >= 1  { return String(format: "%.1f", value) }
        return String(format: "%.2f", value)
    }

    // MARK: - Search & Fetch

    private func performSearch() {
        let query = searchQuery.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return }

        isSearching = true
        searchError = nil
        searchResults = []
        detailedProduct = nil
        enrichmentFields = []

        Task {
            do {
                let results = try await UnifiedFoodSearchService.shared.searchAllDatabases(query: query)
                searchResults = results
                isSearching = false
            } catch {
                searchError = "No results found. Try a different search term."
                isSearching = false
            }
        }
    }

    private func fetchDetails(for product: ProductInfo) {
        isFetchingDetails = true
        detailedProduct = nil
        enrichmentFields = []

        Task {
            do {
                var detailed = product
                // FatSecret search results only have macros; fetch full details for micronutrients
                if product.code.hasPrefix("fatsecret_") {
                    detailed = try await UnifiedFoodSearchService.shared.getProductDetails(code: product.code)
                }
                let fields = buildEnrichmentFields(from: detailed)
                detailedProduct = detailed
                enrichmentFields = fields
                isFetchingDetails = false
            } catch {
                isFetchingDetails = false
                searchError = "Failed to fetch details: \(error.localizedDescription)"
            }
        }
    }

    // MARK: - Enrichment Logic

    private func buildEnrichmentFields(from product: ProductInfo) -> [EnrichmentField] {
        guard let nutriments = product.nutriments else { return [] }

        let gramWeight = foodItem.defaultServing?.gramWeight
        let mode = foodItem.nutritionMode
        let extracted = extractValues(from: nutriments, mode: mode, gramWeight: gramWeight)

        var fields: [EnrichmentField] = []

        func add(name: String, unit: String, current: Double?, proposed: Double?) {
            guard current == nil, let val = proposed, val > 0 else { return }
            fields.append(EnrichmentField(name: name, unit: unit, newValue: val, isSelected: true))
        }

        add(name: "Saturated Fat",       unit: "g",   current: foodItem.saturatedFat,       proposed: extracted.saturatedFat)
        add(name: "Trans Fat",           unit: "g",   current: foodItem.transFat,           proposed: extracted.transFat)
        add(name: "Monounsaturated Fat", unit: "g",   current: foodItem.monounsaturatedFat, proposed: extracted.monounsaturatedFat)
        add(name: "Polyunsaturated Fat", unit: "g",   current: foodItem.polyunsaturatedFat, proposed: extracted.polyunsaturatedFat)
        add(name: "Cholesterol",         unit: "mg",  current: foodItem.cholesterol,        proposed: extracted.cholesterol)
        add(name: "Sodium",              unit: "mg",  current: foodItem.sodium,             proposed: extracted.sodium)
        add(name: "Fiber",               unit: "g",   current: foodItem.fiber,              proposed: extracted.fiber)
        add(name: "Sugar",               unit: "g",   current: foodItem.sugar,              proposed: extracted.sugar)
        add(name: "Vitamin A",           unit: "mcg", current: foodItem.vitaminA,           proposed: extracted.vitaminA)
        add(name: "Vitamin C",           unit: "mg",  current: foodItem.vitaminC,           proposed: extracted.vitaminC)
        add(name: "Vitamin D",           unit: "mcg", current: foodItem.vitaminD,           proposed: extracted.vitaminD)
        add(name: "Vitamin E",           unit: "mg",  current: foodItem.vitaminE,           proposed: extracted.vitaminE)
        add(name: "Vitamin K",           unit: "mcg", current: foodItem.vitaminK,           proposed: extracted.vitaminK)
        add(name: "Vitamin B6",          unit: "mg",  current: foodItem.vitaminB6,          proposed: extracted.vitaminB6)
        add(name: "Vitamin B12",         unit: "mcg", current: foodItem.vitaminB12,         proposed: extracted.vitaminB12)
        add(name: "Folate",              unit: "mcg", current: foodItem.folate,             proposed: extracted.folate)
        add(name: "Choline",             unit: "mg",  current: foodItem.choline,            proposed: extracted.choline)
        add(name: "Calcium",             unit: "mg",  current: foodItem.calcium,            proposed: extracted.calcium)
        add(name: "Iron",                unit: "mg",  current: foodItem.iron,               proposed: extracted.iron)
        add(name: "Potassium",           unit: "mg",  current: foodItem.potassium,          proposed: extracted.potassium)
        add(name: "Magnesium",           unit: "mg",  current: foodItem.magnesium,          proposed: extracted.magnesium)
        add(name: "Zinc",                unit: "mg",  current: foodItem.zinc,               proposed: extracted.zinc)
        add(name: "Caffeine",            unit: "mg",  current: foodItem.caffeine,            proposed: extracted.caffeine)

        return fields
    }

    // MARK: - Unit Extraction

    private struct ExtractedValues {
        var saturatedFat: Double?
        var transFat: Double?
        var monounsaturatedFat: Double?
        var polyunsaturatedFat: Double?
        var cholesterol: Double?
        var sodium: Double?
        var fiber: Double?
        var sugar: Double?
        var vitaminA: Double?
        var vitaminC: Double?
        var vitaminD: Double?
        var vitaminE: Double?
        var vitaminK: Double?
        var vitaminB6: Double?
        var vitaminB12: Double?
        var folate: Double?
        var choline: Double?
        var calcium: Double?
        var iron: Double?
        var potassium: Double?
        var magnesium: Double?
        var zinc: Double?
        var caffeine: Double?
    }

    /// Extracts nutrient values from a ProductInfo's Nutriments, converting to the units
    /// FoodItem expects for its nutritionMode:
    ///   - per100g:   values are per 100g (mg/100g, mcg/100g, g/100g)
    ///   - perServing: values are per 1 default serving (mg, mcg, g)
    private func extractValues(from n: Nutriments, mode: NutritionMode, gramWeight: Double?) -> ExtractedValues {
        let hasPer100g    = (n.energyKcal100g?.value ?? 0) > 0
        let hasPerServing = (n.energyKcalServing?.value ?? 0) > 0

        var r = ExtractedValues()

        switch mode {

        case .per100g:
            if hasPer100g {
                // Source is per-100g, target is per-100g.
                // Nutriments stores: g/100g for grams, g/100g for mg nutrients (÷1000), g/100g for mcg (÷1_000_000)
                // FoodItem expects: g/100g for grams, mg/100g for mg nutrients, mcg/100g for mcg nutrients
                r.saturatedFat       = n.saturatedFat100g?.value                    // g/100g
                r.transFat           = n.transFat100g?.value                        // g/100g
                r.monounsaturatedFat = n.monounsaturatedFat100g?.value              // g/100g
                r.polyunsaturatedFat = n.polyunsaturatedFat100g?.value              // g/100g
                r.fiber              = n.fiber100g?.value                           // g/100g
                r.sugar              = n.sugars100g?.value                          // g/100g
                r.cholesterol        = n.cholesterol100g.map { $0.value * 1000 }    // g→mg per 100g
                r.sodium             = n.sodium100g.map { $0.value * 1000 }         // g→mg per 100g
                r.vitaminA           = n.vitaminA100g.map { $0.value * 1_000_000 }  // g→mcg per 100g
                r.vitaminC           = n.vitaminC100g.map { $0.value * 1000 }       // g→mg per 100g
                r.vitaminD           = n.vitaminD100g.map { $0.value * 1_000_000 }  // g→mcg per 100g
                r.vitaminE           = n.vitaminE100g.map { $0.value * 1000 }       // g→mg per 100g
                r.vitaminK           = n.vitaminK100g.map { $0.value * 1_000_000 }  // g→mcg per 100g
                r.vitaminB6          = n.vitaminB6100g.map { $0.value * 1000 }      // g→mg per 100g
                r.vitaminB12         = n.vitaminB12100g.map { $0.value * 1_000_000 }// g→mcg per 100g
                r.folate             = n.folate100g.map { $0.value * 1_000_000 }    // g→mcg per 100g
                r.choline            = n.choline100g.map { $0.value * 1000 }        // g→mg per 100g
                r.calcium            = n.calcium100g.map { $0.value * 1000 }        // g→mg per 100g
                r.iron               = n.iron100g.map { $0.value * 1000 }           // g→mg per 100g
                r.potassium          = n.potassium100g.map { $0.value * 1000 }      // g→mg per 100g
                r.magnesium          = n.magnesium100g.map { $0.value * 1000 }      // g→mg per 100g
                r.zinc               = n.zinc100g.map { $0.value * 1000 }           // g→mg per 100g
                r.caffeine           = n.caffeine100g.map { $0.value * 1000 }       // g→mg per 100g
            } else if hasPerServing, let gw = gramWeight, gw > 0 {
                // Source is per-serving (FatSecret), target is per-100g — scale up
                let factor = 100.0 / gw
                r.saturatedFat = n.saturatedFatServing.map { $0.value * factor }
                r.fiber        = n.fiberServing.map { $0.value * factor }
                r.sugar        = n.sugarsServing.map { $0.value * factor }
                r.sodium       = n.sodiumServing.map { $0.value * factor * 1000 }   // g→mg, scale to /100g
                r.potassium    = n.potassiumServing.map { $0.value * factor }        // already mg, scale to /100g
                r.cholesterol  = n.cholesterolServing.map { $0.value * factor }      // already mg, scale to /100g
                r.calcium      = n.calciumServing.map { $0.value * factor }          // already mg, scale to /100g
                r.iron         = n.ironServing.map { $0.value * factor }             // already mg, scale to /100g
                r.vitaminA     = n.vitaminAServing.map { $0.value * factor }         // already mcg, scale to /100g
                r.vitaminC     = n.vitaminCServing.map { $0.value * factor }         // already mg, scale to /100g
            }

        case .perServing:
            if hasPerServing {
                // Source has per-serving data. FatSecret specific: sodiumServing is in g, others are mg/mcg.
                r.saturatedFat = n.saturatedFatServing?.value               // g/serving
                r.fiber        = n.fiberServing?.value                      // g/serving
                r.sugar        = n.sugarsServing?.value                     // g/serving
                r.sodium       = n.sodiumServing.map { $0.value * 1000 }    // g→mg per serving
                r.potassium    = n.potassiumServing?.value                   // mg/serving (FatSecret)
                r.cholesterol  = n.cholesterolServing?.value                 // mg/serving (FatSecret)
                r.calcium      = n.calciumServing?.value                     // mg/serving (FatSecret %DV→mg)
                r.iron         = n.ironServing?.value                        // mg/serving (FatSecret %DV→mg)
                r.vitaminA     = n.vitaminAServing?.value                    // mcg/serving (FatSecret %DV→mcg)
                r.vitaminC     = n.vitaminCServing?.value                    // mg/serving (FatSecret %DV→mg)
            } else if hasPer100g, let gw = gramWeight, gw > 0 {
                // Source is per-100g (USDA/OFf), target is per-serving — scale down
                let factor = gw / 100.0
                r.saturatedFat       = n.saturatedFat100g.map { $0.value * factor }
                r.transFat           = n.transFat100g.map { $0.value * factor }
                r.monounsaturatedFat = n.monounsaturatedFat100g.map { $0.value * factor }
                r.polyunsaturatedFat = n.polyunsaturatedFat100g.map { $0.value * factor }
                r.fiber              = n.fiber100g.map { $0.value * factor }
                r.sugar              = n.sugars100g.map { $0.value * factor }
                r.cholesterol        = n.cholesterol100g.map { $0.value * factor * 1000 }
                r.sodium             = n.sodium100g.map { $0.value * factor * 1000 }
                r.vitaminA           = n.vitaminA100g.map { $0.value * factor * 1_000_000 }
                r.vitaminC           = n.vitaminC100g.map { $0.value * factor * 1000 }
                r.vitaminD           = n.vitaminD100g.map { $0.value * factor * 1_000_000 }
                r.vitaminE           = n.vitaminE100g.map { $0.value * factor * 1000 }
                r.vitaminK           = n.vitaminK100g.map { $0.value * factor * 1_000_000 }
                r.vitaminB6          = n.vitaminB6100g.map { $0.value * factor * 1000 }
                r.vitaminB12         = n.vitaminB12100g.map { $0.value * factor * 1_000_000 }
                r.folate             = n.folate100g.map { $0.value * factor * 1_000_000 }
                r.choline            = n.choline100g.map { $0.value * factor * 1000 }
                r.calcium            = n.calcium100g.map { $0.value * factor * 1000 }
                r.iron               = n.iron100g.map { $0.value * factor * 1000 }
                r.potassium          = n.potassium100g.map { $0.value * factor * 1000 }
                r.magnesium          = n.magnesium100g.map { $0.value * factor * 1000 }
                r.zinc               = n.zinc100g.map { $0.value * factor * 1000 }
                r.caffeine           = n.caffeine100g.map { $0.value * factor * 1000 }
            }
        }

        return r
    }

    // MARK: - Apply

    private func applyEnrichment() {
        for field in enrichmentFields where field.isSelected {
            switch field.name {
            case "Saturated Fat":       foodItem.saturatedFat       = field.newValue
            case "Trans Fat":           foodItem.transFat           = field.newValue
            case "Monounsaturated Fat": foodItem.monounsaturatedFat = field.newValue
            case "Polyunsaturated Fat": foodItem.polyunsaturatedFat = field.newValue
            case "Cholesterol":         foodItem.cholesterol        = field.newValue
            case "Sodium":              foodItem.sodium             = field.newValue
            case "Fiber":               foodItem.fiber              = field.newValue
            case "Sugar":               foodItem.sugar              = field.newValue
            case "Vitamin A":           foodItem.vitaminA           = field.newValue
            case "Vitamin C":           foodItem.vitaminC           = field.newValue
            case "Vitamin D":           foodItem.vitaminD           = field.newValue
            case "Vitamin E":           foodItem.vitaminE           = field.newValue
            case "Vitamin K":           foodItem.vitaminK           = field.newValue
            case "Vitamin B6":          foodItem.vitaminB6          = field.newValue
            case "Vitamin B12":         foodItem.vitaminB12         = field.newValue
            case "Folate":              foodItem.folate             = field.newValue
            case "Choline":             foodItem.choline            = field.newValue
            case "Calcium":             foodItem.calcium            = field.newValue
            case "Iron":                foodItem.iron               = field.newValue
            case "Potassium":           foodItem.potassium          = field.newValue
            case "Magnesium":           foodItem.magnesium          = field.newValue
            case "Zinc":                foodItem.zinc               = field.newValue
            case "Caffeine":            foodItem.caffeine           = field.newValue
            default: break
            }
        }
        try? modelContext.save()
        onEnriched()
        dismiss()
    }
}
