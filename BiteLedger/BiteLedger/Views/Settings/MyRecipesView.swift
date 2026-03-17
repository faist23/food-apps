//
//  MyRecipesView.swift
//  BiteLedger
//
//  Created by Craig Faist on 2/16/26.
//

import SwiftUI
import SwiftData
import BiteLedgerCore

struct MyRecipesView: View {
    @Environment(\.modelContext) private var modelContext

    @State private var searchText = ""
    @State private var sortOrder: SortOrder = .dateAdded
    @State private var displayedRecipes: [Recipe] = []

    @State private var recipeToDelete: Recipe?
    @State private var showDeleteConfirmation = false

    @State private var showingCreateEditor = false
    @State private var recipeToEdit: Recipe?

    enum SortOrder: String, CaseIterable {
        case name      = "Name"
        case dateAdded = "Date Added"
        case lastUsed  = "Last Used"
    }

    // MARK: - Load

    private func loadRecipes() {
        let descriptor: FetchDescriptor<Recipe>

        switch sortOrder {
        case .name:
            descriptor = FetchDescriptor<Recipe>(
                sortBy: [SortDescriptor(\Recipe.name)]
            )
        case .dateAdded:
            descriptor = FetchDescriptor<Recipe>(
                sortBy: [SortDescriptor(\Recipe.dateAdded, order: .reverse)]
            )
        case .lastUsed:
            descriptor = FetchDescriptor<Recipe>()
        }

        do {
            var all = try modelContext.fetch(descriptor)

            if !searchText.isEmpty {
                all = all.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
            }

            if sortOrder == .lastUsed {
                all.sort { a, b in
                    let aDate = a.foodItem?.foodLogs.max(by: { $0.timestamp < $1.timestamp })?.timestamp
                    let bDate = b.foodItem?.foodLogs.max(by: { $0.timestamp < $1.timestamp })?.timestamp
                    switch (aDate, bDate) {
                    case (.some(let d1), .some(let d2)): return d1 > d2
                    case (.some, .none):                 return true
                    case (.none, .some):                 return false
                    case (.none, .none):                 return a.name < b.name
                    }
                }
            }

            displayedRecipes = all
        } catch {
            print("Error loading recipes: \(error)")
            displayedRecipes = []
        }
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if displayedRecipes.isEmpty {
                    ContentUnavailableView {
                        Label(
                            searchText.isEmpty ? "No Recipes Yet" : "No Results",
                            systemImage: searchText.isEmpty ? "fork.knife.circle" : "magnifyingglass"
                        )
                    } description: {
                        Text(searchText.isEmpty
                             ? "Create a recipe or import one from the web"
                             : "No recipes match '\(searchText)'")
                    }
                } else {
                    List {
                        ForEach(displayedRecipes) { recipe in
                            Button {
                                recipeToEdit = recipe
                            } label: {
                                recipeRow(recipe)
                            }
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                Button(role: .destructive) {
                                    recipeToDelete = recipe
                                    showDeleteConfirmation = true
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                            .contextMenu {
                                Button {
                                    recipeToEdit = recipe
                                } label: {
                                    Label("Edit", systemImage: "pencil")
                                }

                                Button {
                                    duplicateRecipe(recipe)
                                } label: {
                                    Label("Duplicate", systemImage: "plus.square.on.square")
                                }

                                Divider()

                                Button(role: .destructive) {
                                    recipeToDelete = recipe
                                    showDeleteConfirmation = true
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("My Recipes")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $searchText, prompt: "Search recipes")
            .onAppear { loadRecipes() }
            .onChange(of: searchText)  { _, _ in loadRecipes() }
            .onChange(of: sortOrder)   { _, _ in loadRecipes() }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Menu {
                        Picker("Sort By", selection: $sortOrder) {
                            ForEach(SortOrder.allCases, id: \.self) { order in
                                Text(order.rawValue).tag(order)
                            }
                        }
                    } label: {
                        Label("Sort", systemImage: "arrow.up.arrow.down")
                    }
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showingCreateEditor = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $showingCreateEditor, onDismiss: loadRecipes) {
                RecipeEditorView(recipe: nil)
            }
            .sheet(item: $recipeToEdit, onDismiss: loadRecipes) { recipe in
                RecipeEditorView(recipe: recipe)
            }
            .alert(deleteAlertTitle, isPresented: $showDeleteConfirmation) {
                Button("Cancel", role: .cancel) {
                    recipeToDelete = nil
                }
                Button("Delete", role: .destructive) {
                    if let recipe = recipeToDelete {
                        deleteRecipe(recipe)
                    }
                }
            } message: {
                if let recipe = recipeToDelete {
                    Text(deleteAlertMessage(for: recipe))
                }
            }
        }
    }

    // MARK: - Row

    @ViewBuilder
    private func recipeRow(_ recipe: Recipe) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(recipe.name)
                    .foregroundStyle(.primary)
                    .fontWeight(.medium)

                let yieldText = recipe.servingsYield.truncatingRemainder(dividingBy: 1) == 0
                    ? "Makes \(Int(recipe.servingsYield)) serving\(Int(recipe.servingsYield) == 1 ? "" : "s")"
                    : String(format: "Makes %.1f servings", recipe.servingsYield)

                Text(yieldText)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                HStack(spacing: 8) {
                    if let food = recipe.foodItem {
                        Text("\(Int(food.calories)) cal / serving")
                            .font(.caption2)
                            .foregroundStyle(.blue)
                    }

                    if let domain = recipe.sourceDomain {
                        Text(domain)
                            .font(.caption2)
                            .foregroundStyle(.orange)
                    }

                    if recipe.hasOrphanedIngredients {
                        Label("Missing ingredient", systemImage: "exclamationmark.triangle.fill")
                            .font(.caption2)
                            .foregroundStyle(.yellow)
                    }
                }

                if let lastDate = recipe.foodItem?.foodLogs
                    .max(by: { $0.timestamp < $1.timestamp })?.timestamp {
                    Text("Last logged \(lastDate.lastUsedDisplay)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
    }

    // MARK: - Delete

    private var deleteAlertTitle: String {
        "Delete Recipe?"
    }

    private func deleteAlertMessage(for recipe: Recipe) -> String {
        let logCount = recipe.foodItem?.foodLogs.count ?? 0
        if logCount > 0 {
            return "'\(recipe.name)' has been logged \(logCount) time\(logCount == 1 ? "" : "s"). The log history will be preserved, but the recipe will be permanently removed."
        }
        return "'\(recipe.name)' will be permanently deleted. This cannot be undone."
    }

    private func deleteRecipe(_ recipe: Recipe) {
        modelContext.delete(recipe)
        try? modelContext.save()
        recipeToDelete = nil
        loadRecipes()
    }

    // MARK: - Duplicate

    private func duplicateRecipe(_ recipe: Recipe) {
        let copy = Recipe(
            name: "\(recipe.name) Copy",
            servingsYield: recipe.servingsYield,
            sourceURL: recipe.sourceURL,
            directions: recipe.directions
        )
        modelContext.insert(copy)

        for (index, ingredient) in recipe.sortedIngredients.enumerated() {
            let ingredientCopy = RecipeIngredient(
                quantity: ingredient.quantity,
                sortOrder: index
            )
            ingredientCopy.foodItem = ingredient.foodItem
            ingredientCopy.servingSize = ingredient.servingSize
            ingredientCopy.recipe = copy
            modelContext.insert(ingredientCopy)
        }

        // Copy the associated FoodItem so the duplicate can be logged immediately
        if let original = recipe.foodItem {
            let foodCopy = FoodItem(
                name: copy.name,
                source: "recipe",
                nutritionMode: .perServing,
                calories: original.calories,
                protein: original.protein,
                carbs: original.carbs,
                fat: original.fat,
                fiber: original.fiber,
                sugar: original.sugar,
                saturatedFat: original.saturatedFat,
                transFat: original.transFat,
                polyunsaturatedFat: original.polyunsaturatedFat,
                monounsaturatedFat: original.monounsaturatedFat,
                sodium: original.sodium,
                cholesterol: original.cholesterol,
                potassium: original.potassium,
                calcium: original.calcium,
                iron: original.iron,
                magnesium: original.magnesium,
                zinc: original.zinc,
                vitaminA: original.vitaminA,
                vitaminC: original.vitaminC,
                vitaminD: original.vitaminD,
                vitaminE: original.vitaminE,
                vitaminK: original.vitaminK,
                vitaminB6: original.vitaminB6,
                vitaminB12: original.vitaminB12,
                folate: original.folate,
                choline: original.choline,
                caffeine: original.caffeine
            )
            // The original recipe FoodItem is already per-100g (normalized at creation).
            // The copy preserves the same nutrition values and mode.
            let serving = ServingSize(
                label: "1 serving",
                gramWeight: original.defaultServing?.gramWeight ?? 100.0,
                isDefault: true,
                sortOrder: 0,
                unit: ServingUnit.serving.rawValue
            )
            foodCopy.servingSizes.append(serving)
            modelContext.insert(serving)
            modelContext.insert(foodCopy)
            copy.foodItem = foodCopy
        }

        try? modelContext.save()
        loadRecipes()
        recipeToEdit = copy
    }
}
