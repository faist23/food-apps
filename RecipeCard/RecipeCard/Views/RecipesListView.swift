//
//  RecipesListView.swift
//  RecipeCard
//

import SwiftUI
import SwiftData
import BiteLedgerCore

struct RecipesListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Recipe.name) private var recipes: [Recipe]
    @State private var showingNewRecipe = false
    @State private var showingImport = false
    @State private var pendingImportURL: String? = nil

    var body: some View {
        NavigationStack {
            Group {
                if recipes.isEmpty {
                    ContentUnavailableView(
                        "No Recipes Yet",
                        systemImage: "fork.knife.circle",
                        description: Text("Tap + to create your first recipe.")
                    )
                } else {
                    List {
                        ForEach(recipes) { recipe in
                            NavigationLink(destination: RecipeDetailView(recipe: recipe)) {
                                RecipeRowView(recipe: recipe)
                            }
                        }
                        .onDelete(perform: deleteRecipes)
                    }
                }
            }
            .navigationTitle("Recipes")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button { showingNewRecipe = true } label: { Image(systemName: "plus") }
                }
                ToolbarItem(placement: .navigationBarLeading) {
                    Button { showingImport = true } label: {
                        Label("Import", systemImage: "link.badge.plus")
                    }
                }
                if !recipes.isEmpty {
                    ToolbarItem(placement: .navigationBarLeading) { EditButton() }
                }
            }
            .sheet(isPresented: $showingImport, onDismiss: { pendingImportURL = nil }) {
                ImportRecipeView(prefilledURL: pendingImportURL)
            }
            .sheet(isPresented: $showingNewRecipe) {
                RecipeEditorView(recipe: nil)
            }
            .onReceive(NotificationCenter.default.publisher(for: .recipeCardImportURL)) { note in
                if let url = note.userInfo?["url"] as? URL {
                    pendingImportURL = url.absoluteString
                    showingImport = true
                }
            }
        }
    }

    private func deleteRecipes(offsets: IndexSet) {
        for index in offsets { modelContext.delete(recipes[index]) }
    }
}

private struct RecipeRowView: View {
    let recipe: Recipe

    var caloriesPerServing: Double? {
        let total = recipe.sortedIngredients.reduce(NutritionCalculator.Result.zero) { acc, ing in
            guard let food = ing.foodItem else { return acc }
            return acc + NutritionCalculator.calculate(food: food, serving: ing.servingSize, quantity: ing.quantity)
        }
        guard total.calories > 0 else { return nil }
        return total.calories / recipe.servingsYield
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(recipe.name).font(.headline)
            HStack(spacing: 12) {
                Label("\(Int(recipe.servingsYield)) servings", systemImage: "person.2")
                    .font(.caption).foregroundStyle(.secondary)
                if let cal = caloriesPerServing {
                    Text("\(Int(cal)) cal/serving")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 2)
    }
}
