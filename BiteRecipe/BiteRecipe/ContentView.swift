//
//  BiteRecipeRootView.swift
//  BiteRecipe
//

import SwiftUI
import BiteLedgerCore

struct BiteRecipeRootView: View {
    @Environment(ShoppingCart.self) private var shoppingCart
    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var selectedRecipe: Recipe? = nil

    var body: some View {
        if sizeClass == .regular {
            ipadLayout
        } else {
            iphoneLayout
        }
    }

    // MARK: - iPhone (compact)

    private var iphoneLayout: some View {
        TabView {
            RecipesListView()
                .tabItem { Label("Recipes", systemImage: "fork.knife") }

            ShoppingListView()
                .tabItem { Label("Shopping", systemImage: "cart") }
                .badge(shoppingCart.uncheckedCount > 0 ? shoppingCart.uncheckedCount : 0)
        }
    }

    // MARK: - iPad (regular)
    //
    // NavigationSplitView requires RecipesListView to render WITHOUT its own
    // NavigationStack in sidebar mode (nested nav = undefined behavior).
    // RecipesListView detects sidebar mode via the selectedRecipe binding.

    private var ipadLayout: some View {
        TabView {
            NavigationSplitView {
                RecipesListView(selectedRecipe: $selectedRecipe)
            } detail: {
                if let recipe = selectedRecipe {
                    NavigationStack {
                        RecipeDetailView(recipe: recipe)
                    }
                } else {
                    ContentUnavailableView(
                        "Select a Recipe",
                        systemImage: "fork.knife.circle",
                        description: Text("Choose a recipe from the sidebar.")
                    )
                }
            }
            .tabItem { Label("Recipes", systemImage: "fork.knife") }

            ShoppingListView()
                .tabItem { Label("Shopping", systemImage: "cart") }
                .badge(shoppingCart.uncheckedCount > 0 ? shoppingCart.uncheckedCount : 0)
        }
    }
}
