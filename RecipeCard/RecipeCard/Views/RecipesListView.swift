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
    @State private var showingOCRImport = false
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
                        Label("Import from URL", systemImage: "link.badge.plus")
                    }
                }
                ToolbarItem(placement: .navigationBarLeading) {
                    Button { showingOCRImport = true } label: {
                        Label("Scan Recipe", systemImage: "camera.viewfinder")
                    }
                }
                if !recipes.isEmpty {
                    ToolbarItem(placement: .navigationBarLeading) { EditButton() }
                }
            }
            .sheet(isPresented: $showingImport, onDismiss: { pendingImportURL = nil }) {
                ImportRecipeView(prefilledURL: pendingImportURL)
            }
            .sheet(isPresented: $showingOCRImport) {
                OCRRecipeImportView()
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
        for index in offsets {
            let recipe = recipes[index]
            if let url = recipe.imageURL { RecipeImportService.deleteLocalImage(urlString: url) }
            modelContext.delete(recipe)
        }
    }
}

private struct RecipeRowView: View {
    let recipe: Recipe

    var caloriesPerServing: Double? {
        if let n = recipe.importedNutrition { return n.calories }
        let total = recipe.sortedIngredients.reduce(NutritionCalculator.Result.zero) { acc, ing in
            guard let food = ing.foodItem else { return acc }
            return acc + NutritionCalculator.calculate(food: food, serving: ing.servingSize, quantity: ing.quantity)
        }
        guard total.calories > 0 else { return nil }
        return total.calories / recipe.servingsYield
    }

    var body: some View {
        HStack(spacing: 12) {
            // Thumbnail
            if let urlStr = recipe.imageURL, let url = URL(string: urlStr) {
                AsyncImage(url: url) { phase in
                    if let img = phase.image {
                        img.resizable().scaledToFill()
                    } else {
                        Color.secondary.opacity(0.12)
                    }
                }
                .frame(width: 56, height: 56)
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(recipe.name).font(.headline)
                HStack(spacing: 10) {
                    if let time = recipe.displayTime {
                        Label(time, systemImage: "clock")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Label("\(Int(recipe.servingsYield)) servings", systemImage: "person.2")
                        .font(.caption).foregroundStyle(.secondary)
                    if let cal = caloriesPerServing {
                        Text("\(Int(cal)) cal")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding(.vertical, 2)
    }
}
