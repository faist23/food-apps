//
//  RecipeDetailView.swift
//  RecipeCard
//

import SwiftUI
import SwiftData
import BiteLedgerCore

struct RecipeDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Bindable var recipe: Recipe
    @State private var showingEditor = false
    @State private var showingNutrition = false
    @State private var scaleFactor: Double = 1.0

    /// True when nutrition is sourced from the website rather than ingredient calculations.
    private var usingWebsiteNutrition: Bool {
        recipe.importedNutrition != nil
    }

    private let scaleOptions: [(label: String, value: Double)] = [
        ("1/2x", 0.5), ("1x", 1.0), ("2x", 2.0), ("3x", 3.0)
    ]

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

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {

                // Source URL
                if let domain = recipe.sourceDomain {
                    Label(domain, systemImage: "link")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal)
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
        }
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
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
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
                Text(ingredient.displayLabel).font(.body)
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
                        .font(.caption).foregroundColor(.accentColor)
                } else if ingredient.rawText != nil, let food = ingredient.foodItem {
                    Text("→ \(food.name)").font(.caption).foregroundStyle(.secondary)
                } else if ingredient.rawText == nil {
                    Text(servingDescription).font(.caption).foregroundStyle(.secondary)
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

    private var servingDescription: String {
        guard let s = ingredient.servingSize else { return "\(ingredient.quantity.formatted()) serving" }
        return ingredient.quantity == 1 ? s.label : "\(ingredient.quantity.formatted()) x \(s.label)"
    }
}
