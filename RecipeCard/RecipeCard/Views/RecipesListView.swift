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
                    recipeEmptyState
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
                // D-1: Consolidate import actions into ⋯ More menu
                ToolbarItem(placement: .navigationBarTrailing) {
                    Menu {
                        Button { showingImport = true } label: {
                            Label("Import from URL", systemImage: "link.badge.plus")
                        }
                        Button { showingOCRImport = true } label: {
                            Label("Scan Recipe Card", systemImage: "camera.viewfinder")
                        }
                        Button { showingNewRecipe = true } label: {
                            Label("New Recipe", systemImage: "square.and.pencil")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                    .accessibilityLabel("More options")
                }
                ToolbarItem(placement: .primaryAction) {
                    Button { showingImport = true } label: { Image(systemName: "plus") }
                        .accessibilityLabel("Import recipe from URL")
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

    // D-2: Custom empty state with 3 import options
    private var recipeEmptyState: some View {
        VStack(spacing: 32) {
            Spacer()

            Image(systemName: "fork.knife.circle")
                .font(.system(size: 64))
                .foregroundStyle(.secondary)

            VStack(spacing: 8) {
                Text("No Recipes Yet")
                    .font(.title2.bold())
                Text("Add your first recipe one of three ways:")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            VStack(spacing: 12) {
                Button {
                    showingImport = true
                } label: {
                    Label("Import from URL", systemImage: "link.badge.plus")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)

                Button {
                    showingOCRImport = true
                } label: {
                    Label("Scan Recipe Card", systemImage: "camera.viewfinder")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)

                Button {
                    showingNewRecipe = true
                } label: {
                    Label("Create Manually", systemImage: "square.and.pencil")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
            }
            .padding(.horizontal, 32)

            Spacer()
            Spacer()
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
            // D-3: Thumbnail — show fork.knife placeholder on SurfaceCard when no image
            RecipePhotoView(urlString: recipe.imageURL, contentMode: .fill) {
                recipeThumbnailPlaceholder
            }
            .frame(width: 56, height: 56)
            .clipShape(RoundedRectangle(cornerRadius: 8))

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

    private var recipeThumbnailPlaceholder: some View {
        ZStack {
            Color("SurfaceCard")
            Image(systemName: "fork.knife")
                .font(.system(size: 22))
                .foregroundStyle(.secondary)
        }
    }
}

/// Loads a recipe photo from either a remote https:// URL (via AsyncImage) or a
/// local file:// URL (via UIImage(contentsOfFile:)).  AsyncImage silently fails
/// on file:// URLs in some iOS versions; using UIImage avoids that issue.
struct RecipePhotoView<Placeholder: View>: View {
    let urlString: String?
    let contentMode: ContentMode
    @ViewBuilder let placeholder: () -> Placeholder

    var body: some View {
        if let urlStr = urlString {
            if urlStr.hasPrefix("file://"),
               let url = URL(string: urlStr),
               let path = url.path.removingPercentEncoding,
               let uiImage = UIImage(contentsOfFile: path) {
                Image(uiImage: uiImage)
                    .resizable()
                    .aspectRatio(contentMode: contentMode)
            } else if let url = URL(string: urlStr) {
                AsyncImage(url: url) { phase in
                    if let img = phase.image {
                        img.resizable().aspectRatio(contentMode: contentMode)
                    } else {
                        placeholder()
                    }
                }
            } else {
                placeholder()
            }
        } else {
            placeholder()
        }
    }
}
