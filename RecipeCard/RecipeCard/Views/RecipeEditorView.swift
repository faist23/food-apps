//
//  RecipeEditorView.swift
//  RecipeCard
//

import SwiftUI
import SwiftData
import BiteLedgerCore

struct RecipeEditorView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    let existingRecipe: Recipe?

    @State private var name: String
    @State private var servingsYield: String
    @State private var sourceURL: String
    @State private var directions: [String]
    @State private var ingredients: [RecipeIngredient]
    @State private var newDirection: String = ""
    @State private var showingIngredientPicker = false

    init(recipe: Recipe?) {
        self.existingRecipe = recipe
        _name          = State(initialValue: recipe?.name ?? "")
        _servingsYield = State(initialValue: recipe.map { String(Int($0.servingsYield)) } ?? "1")
        _sourceURL     = State(initialValue: recipe?.sourceURL ?? "")
        _directions    = State(initialValue: recipe?.directions ?? [])
        _ingredients   = State(initialValue: recipe?.sortedIngredients ?? [])
    }

    private var totals: NutritionCalculator.Result {
        ingredients.reduce(.zero) { acc, ing in
            guard let food = ing.foodItem else { return acc }
            return acc + NutritionCalculator.calculate(food: food, serving: ing.servingSize, quantity: ing.quantity)
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

    var body: some View {
        NavigationStack {
            Form {
                Section("Recipe Info") {
                    TextField("Name", text: $name)
                    HStack {
                        Text("Servings")
                        Spacer()
                        TextField("1", text: $servingsYield)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 60)
                    }
                    TextField("Source URL (optional)", text: $sourceURL)
                        .keyboardType(.URL)
                        .autocorrectionDisabled()
                }

                Section("Ingredients") {
                    ForEach(ingredients) { ing in
                        IngredientEditorRow(ingredient: ing)
                    }
                    .onDelete { offsets in
                        for i in offsets { modelContext.delete(ingredients[i]) }
                        ingredients.remove(atOffsets: offsets)
                    }
                    .onMove { from, to in ingredients.move(fromOffsets: from, toOffset: to) }
                    Button {
                        showingIngredientPicker = true
                    } label: {
                        Label("Add Ingredient", systemImage: "plus.circle.fill")
                    }
                }

                if !ingredients.isEmpty {
                    Section("Nutrition Per Serving") {
                        NutritionRow(label: "Calories", value: perServing.calories, unit: "")
                        NutritionRow(label: "Protein",  value: perServing.protein,  unit: "g")
                        NutritionRow(label: "Carbs",    value: perServing.carbs,    unit: "g")
                        NutritionRow(label: "Fat",      value: perServing.fat,      unit: "g")
                        if let fiber = perServing.fiber {
                            NutritionRow(label: "Fiber", value: fiber, unit: "g")
                        }
                    }
                }

                Section("Directions") {
                    ForEach(Array(directions.enumerated()), id: \.offset) { i, step in
                        HStack(alignment: .top, spacing: 8) {
                            Text("\(i + 1).").foregroundStyle(.secondary)
                            Text(step)
                        }
                    }
                    .onDelete { directions.remove(atOffsets: $0) }
                    .onMove { directions.move(fromOffsets: $0, toOffset: $1) }

                    HStack {
                        TextField("Add a step…", text: $newDirection, axis: .vertical)
                            .lineLimit(2...4)
                        Button {
                            let trimmed = newDirection.trimmingCharacters(in: .whitespaces)
                            guard !trimmed.isEmpty else { return }
                            directions.append(trimmed)
                            newDirection = ""
                        } label: {
                            Image(systemName: "plus.circle.fill")
                        }
                        .disabled(newDirection.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }
            }
            .navigationTitle(existingRecipe == nil ? "New Recipe" : "Edit Recipe")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .sheet(isPresented: $showingIngredientPicker) {
                IngredientPickerView { food, serving, qty in
                    let ing = RecipeIngredient(quantity: qty, sortOrder: ingredients.count)
                    ing.foodItem = food
                    ing.servingSize = serving
                    modelContext.insert(ing)
                    ingredients.append(ing)
                }
            }
        }
    }

    private func save() {
        let yield = Double(Int(servingsYield) ?? 1)
        let url = sourceURL.trimmingCharacters(in: .whitespaces).isEmpty ? nil : sourceURL.trimmingCharacters(in: .whitespaces)

        if let recipe = existingRecipe {
            recipe.name = name.trimmingCharacters(in: .whitespaces)
            recipe.servingsYield = yield
            recipe.sourceURL = url
            recipe.directions = directions
            for (i, ing) in ingredients.enumerated() { ing.sortOrder = i; ing.recipe = recipe }
        } else {
            let recipe = Recipe(
                name: name.trimmingCharacters(in: .whitespaces),
                servingsYield: yield,
                sourceURL: url,
                directions: directions
            )
            for (i, ing) in ingredients.enumerated() { ing.sortOrder = i; ing.recipe = recipe }
            modelContext.insert(recipe)
        }
        try? modelContext.save()
        dismiss()
    }
}

private struct IngredientEditorRow: View {
    @Bindable var ingredient: RecipeIngredient
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(ingredient.displayLabel).font(.body)
                if ingredient.rawText != nil, let food = ingredient.foodItem {
                    Text("→ \(food.name)").font(.caption).foregroundStyle(.secondary)
                } else if ingredient.rawText == nil {
                    Text(ingredient.servingSize?.label ?? "1 serving").font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
            // Only show quantity editor for matched (foodItem-linked) ingredients
            if ingredient.foodItem != nil {
                TextField("Qty", value: $ingredient.quantity, format: .number)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 60)
            }
        }
    }
}

private struct NutritionRow: View {
    let label: String; let value: Double; let unit: String
    var body: some View {
        HStack {
            Text(label)
            Spacer()
            Text("\(Int(value))\(unit)").foregroundStyle(.secondary)
        }
    }
}
