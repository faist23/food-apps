//
//  RecipeDetailView.swift
//  BiteRecipe
//

import SwiftUI
import SwiftData
import BiteLedgerCore

struct RecipeDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(ShoppingCart.self) private var shoppingCart
    @Bindable var recipe: Recipe
    @State private var showingEditor = false
    @State private var showingNutrition = false
    @State private var showingCookingMode = false
    @State private var scaleFactor: Double = 1.0
    @State private var showingAddedToast = false

    /// True when nutrition is sourced from the website rather than ingredient calculations.
    private var usingWebsiteNutrition: Bool {
        recipe.importedNutrition != nil
    }

    private let scaleOptions: [(label: String, value: Double)] = [
        ("1/2x", 0.5), ("1x", 1.0), ("1.5x", 1.5), ("2x", 2.0), ("3x", 3.0)
    ]

    private func formatMinutes(_ m: Int) -> String {
        guard m > 0 else { return "" }
        if m < 60 { return "\(m) min" }
        let h = m / 60; let r = m % 60
        return r == 0 ? "\(h) hr" : "\(h) hr \(r) min"
    }

    private var perServing: NutritionCalculator.Result {
        // Website nutrition is the authoritative source — always prefer it when available.
        // Ingredient-level calculation is only a fallback for recipes with no website data.
        if let n = recipe.importedNutrition {
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
        // No website nutrition — calculate from matched ingredients
        let total: NutritionCalculator.Result = recipe.sortedIngredients.reduce(.zero) { acc, ing in
            guard let food = ing.foodItem else { return acc }
            return acc + NutritionCalculator.calculate(food: food, serving: ing.servingSize, quantity: ing.quantity)
        }
        guard total.calories > 0 else { return .zero }
        let d = recipe.servingsYield > 0 ? recipe.servingsYield : 1
        return NutritionCalculator.Result(
            calories:     total.calories / d,
            protein:      total.protein / d,
            carbs:        total.carbs / d,
            fat:          total.fat / d,
            fiber:        total.fiber.map { $0 / d },
            sugar:        total.sugar.map { $0 / d },
            saturatedFat: total.saturatedFat.map { $0 / d },
            transFat:     total.transFat.map { $0 / d },
            sodium:       total.sodium.map { $0 / d },
            cholesterol:  total.cholesterol.map { $0 / d },
            potassium:    total.potassium.map { $0 / d },
            calcium:      total.calcium.map { $0 / d },
            iron:         total.iron.map { $0 / d }
        )
    }

    private var hasDirections: Bool { !recipe.directions.isEmpty }

    var body: some View {
        ZStack(alignment: .bottom) {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {

                // D-8: Hero photo — always show 220pt frame; placeholder when no image
                RecipePhotoView(urlString: recipe.imageURL, contentMode: .fill) {
                    recipeHeroPlaceholder
                }
                .frame(maxWidth: .infinity).frame(height: 220)
                .clipped()

                // Source + author
                VStack(alignment: .leading, spacing: 4) {
                    if let domain = recipe.sourceDomain {
                        Label(domain, systemImage: "link")
                            .font(.subheadline).foregroundStyle(.secondary)
                    } else if let src = recipe.sourceURL, !src.isEmpty {
                        Label(src, systemImage: "book.closed")
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                    if let author = recipe.author {
                        Text("By \(author)")
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal)

                // Rating
                if let rating = recipe.ratingValue {
                    HStack(spacing: 4) {
                        Image(systemName: "star.fill").foregroundStyle(.yellow)
                        Text(String(format: "%.1f", rating)).fontWeight(.semibold)
                        if let count = recipe.ratingCount {
                            Text("(\(count.formatted()))")
                                .foregroundStyle(.secondary)
                        }
                    }
                    .font(.subheadline)
                    .padding(.horizontal)
                }

                // Time row
                let times: [(String, Int)] = [
                    ("Prep", recipe.prepMinutes ?? 0),
                    ("Cook", recipe.cookMinutes ?? 0),
                    ("Total", recipe.totalMinutes ?? (recipe.prepMinutes ?? 0) + (recipe.cookMinutes ?? 0))
                ].filter { $0.1 > 0 }
                if !times.isEmpty {
                    HStack(spacing: 0) {
                        ForEach(Array(times.enumerated()), id: \.offset) { i, pair in
                            if i > 0 { Divider().frame(height: 32) }
                            VStack(spacing: 2) {
                                Text(pair.0).font(.caption).foregroundStyle(.secondary)
                                Text(formatMinutes(pair.1)).font(.subheadline.bold())
                            }
                            .frame(maxWidth: .infinity)
                        }
                    }
                    .padding(.vertical, 10)
                    .background(Color.surfaceCard, in: RoundedRectangle(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.dividerSubtle, lineWidth: 1))
                    .padding(.horizontal)
                }

                // Description
                if let desc = recipe.recipeDescription {
                    Text(desc)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal)
                }

                // Tags (category, cuisine, diet)
                let tags: [String] = ([recipe.recipeCategory, recipe.recipeCuisine].compactMap { $0 }
                    + recipe.dietTags).filter { !$0.isEmpty }
                if !tags.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(tags, id: \.self) { tag in
                                Text(tag)
                                    .font(.caption.weight(.medium))
                                    .padding(.horizontal, 10).padding(.vertical, 4)
                                    .background(.tint.opacity(0.12), in: Capsule())
                                    .foregroundStyle(.tint)
                            }
                        }
                        .padding(.horizontal)
                    }
                }

                // Scale picker
                VStack(alignment: .leading, spacing: 6) {
                    Text("Scale Recipe")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal)
                    Picker("Scale", selection: $scaleFactor) {
                        ForEach(scaleOptions, id: \.value) { opt in
                            Text(opt.label).tag(opt.value)
                        }
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal)
                    if scaleFactor != 1.0 {
                        let scaled = recipe.servingsYield * scaleFactor
                        Text("Makes \(Int(scaled)) servings")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal)
                    }
                }

                // Nutrition per serving — tap for full label
                if perServing.calories > 0 {
                    Button { showingNutrition = true } label: {
                        NutritionSummaryCard(
                            servings: recipe.servingsYield * scaleFactor,
                            result: perServing
                        )
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal)
                    .overlay(alignment: .bottomTrailing) {
                        VStack(alignment: .trailing, spacing: 2) {
                            if usingWebsiteNutrition {
                                Text("from website")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            Text("Tap for full label")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.trailing, 20)
                        .padding(.bottom, 6)
                    }
                }

                // Ingredients
                VStack(alignment: .leading, spacing: 8) {
                    Text("Ingredients")
                        .font(.title3.bold())
                        .padding(.horizontal)

                    if recipe.sortedIngredients.isEmpty {
                        Text("No ingredients added yet.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal)
                    } else {
                        ForEach(recipe.sortedIngredients) { ing in
                            IngredientRowView(ingredient: ing, scaleFactor: scaleFactor)
                                .padding(.horizontal)
                            Divider().padding(.leading)
                        }
                    }
                }

                // Directions
                if !recipe.directions.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Directions")
                            .font(.title3.bold())
                            .padding(.horizontal)
                        ForEach(Array(recipe.directions.enumerated()), id: \.offset) { i, step in
                            HStack(alignment: .top, spacing: 12) {
                                Text("\(i + 1)")
                                    .font(.headline)
                                    .foregroundStyle(.secondary)
                                    .frame(width: 24, alignment: .trailing)
                                Text(step)
                            }
                            .padding(.horizontal)
                        }
                    }
                }
            }
            .padding(.vertical)
            // Bottom padding so sticky bar doesn't obscure last content
            .padding(.bottom, 80)
        }

        // Sticky bottom action bar
        stickyActionBar

        } // end ZStack
        .navigationTitle(recipe.name)
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                HStack {
                    if perServing.calories > 0 {
                        Button("Nutrition") { showingNutrition = true }
                    }
                    Button("Edit") { showingEditor = true }
                }
            }
        }
        .sheet(isPresented: $showingEditor) {
            RecipeEditorView(recipe: recipe)
        }
        .sheet(isPresented: $showingNutrition) {
            RecipeNutritionLabelView(
                recipeName: recipe.name,
                servings: recipe.servingsYield,
                perServing: perServing
            )
        }
        .fullScreenCover(isPresented: $showingCookingMode) {
            CookingModeView(recipe: recipe)
        }
    }

    // MARK: - Sticky bottom action bar

    private var stickyActionBar: some View {
        VStack(spacing: 0) {
            Divider()
            HStack(spacing: 12) {
                // Primary: Start Cooking — disabled when no directions
                Button {
                    showingCookingMode = true
                } label: {
                    Label("Start Cooking", systemImage: "frying.pan")
                        .frame(maxWidth: .infinity)
                        .frame(height: 44)
                }
                .buttonStyle(.borderedProminent)
                .disabled(!hasDirections)
                .overlay(alignment: .bottom) {
                    if !hasDirections {
                        Text("Add directions first.")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .offset(y: 16)
                    }
                }

                // Secondary: Add to Shopping List
                Button {
                    shoppingCart.addRecipe(recipe, scaleFactor: scaleFactor)
                    withAnimation { showingAddedToast = true }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                        withAnimation { showingAddedToast = false }
                    }
                } label: {
                    Label("Shopping", systemImage: "cart.badge.plus")
                        .frame(maxWidth: .infinity)
                        .frame(height: 44)
                }
                .buttonStyle(.bordered)
                .tint(Color.brandPrimary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(.regularMaterial)
        }
        .overlay(alignment: .top) {
            if showingAddedToast {
                Text("Added to shopping list")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(Color.brandPrimary, in: Capsule())
                    .offset(y: -52)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
    }

    private var recipeHeroPlaceholder: some View {
        ZStack {
            Color.surfaceCard
            VStack(spacing: 8) {
                Image(systemName: "fork.knife")
                    .font(.system(size: 40))
                    .foregroundStyle(.secondary)
                Text(recipe.name)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 20)
            }
        }
    }
}

private struct NutritionSummaryCard: View {
    let servings: Double
    let result: NutritionCalculator.Result

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Per serving (\(Int(servings)) servings total)")
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack(spacing: 0) {
                MacroTile(label: "Calories", value: result.calories, unit: "")
                Divider()
                MacroTile(label: "Protein", value: result.protein, unit: "g")
                Divider()
                MacroTile(label: "Carbs",   value: result.carbs,   unit: "g")
                Divider()
                MacroTile(label: "Fat",     value: result.fat,     unit: "g")
            }
            .frame(maxWidth: .infinity)
            .padding()
            .background(Color.surfaceCard, in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.dividerSubtle, lineWidth: 1))
        }
    }
}

private struct MacroTile: View {
    let label: String; let value: Double; let unit: String
    var body: some View {
        VStack(spacing: 2) {
            Text("\(Int(value))\(unit)").font(.title3.bold())
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

private struct IngredientRowView: View {
    let ingredient: RecipeIngredient
    var scaleFactor: Double = 1.0

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                // URL/OCR imports: show the original recipe text (rawText).
                // Manually-added: show the food name — serving info goes in the caption.
                Text(ingredient.rawText == nil
                     ? (ingredient.foodItem?.name ?? "Deleted Food")
                     : ingredient.displayLabel)
                    .font(.body)
                // When scaled and original units are known, show the scaled amount
                if scaleFactor != 1.0,
                   let rqty = ingredient.recipeQuantity,
                   let runit = ingredient.recipeUnit, !runit.isEmpty {
                    let scaled = rqty * scaleFactor
                    let s = scaled.truncatingRemainder(dividingBy: 1) == 0
                        ? String(Int(scaled)) : String(format: "%.2g", scaled)
                    let scaleStr = scaleFactor.truncatingRemainder(dividingBy: 1) == 0
                        ? String(Int(scaleFactor)) : String(format: "%.2g", scaleFactor)
                    Text("→ \(s) \(runit) (x\(scaleStr))")
                        .font(.caption).foregroundStyle(Color.brandPrimary)
                } else if ingredient.rawText != nil, let food = ingredient.foodItem {
                    Text("→ \(food.name)").font(.caption).foregroundStyle(.secondary)
                } else if ingredient.rawText == nil {
                    Text(scaledServingDescription).font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
            if let food = ingredient.foodItem {
                let r = NutritionCalculator.calculate(
                    food: food, serving: ingredient.servingSize,
                    quantity: ingredient.quantity * scaleFactor
                )
                Text("\(Int(r.calories)) cal").font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }

    /// Serving description for manually-added ingredients, scaled by `scaleFactor`.
    private var scaledServingDescription: String {
        let scaledQty = ingredient.quantity * scaleFactor
        guard let s = ingredient.servingSize else {
            let qtyStr = scaledQty.truncatingRemainder(dividingBy: 1) == 0
                ? String(Int(scaledQty)) : String(format: "%.2g", scaledQty)
            return "\(qtyStr) serving"
        }
        // Resolve (servingUnit, amountPerServing) — stored unit field first,
        // then ServingSizeParser on the label for older records where unit==nil.
        let resolvedUnit: ServingUnit?
        let resolvedAmount: Double
        if let unitRaw = s.unit, let su = ServingUnit(rawValue: unitRaw) {
            resolvedUnit = su
            resolvedAmount = s.amount > 0 ? s.amount : 1.0
        } else if let parsed = ServingSizeParser.parse(s.label),
                  parsed.unit != .serving, parsed.unit != .container {
            resolvedUnit = parsed.unit
            resolvedAmount = parsed.amount > 0 ? parsed.amount : 1.0
        } else {
            resolvedUnit = nil
            resolvedAmount = 1.0
        }
        // Express as a natural quantity (e.g. 0.75 cup, 1.5 cup, 4.5 cup).
        if let su = resolvedUnit {
            let total = scaledQty * resolvedAmount
            let totalStr = total.truncatingRemainder(dividingBy: 1) == 0
                ? String(Int(total)) : String(format: "%.2g", total)
            return "\(totalStr) \(su.abbreviation)"
        }
        // Opaque units (package, slice, etc.) — show qty × label only when > 1.
        if scaledQty == 1.0 { return s.label }
        let qtyStr = scaledQty.truncatingRemainder(dividingBy: 1) == 0
            ? String(Int(scaledQty)) : String(format: "%.2g", scaledQty)
        return "\(qtyStr) × \(s.label)"
    }
}
