//
//  RecipeCardRootView.swift
//  RecipeCard
//

import SwiftUI
import BiteLedgerCore

struct RecipeCardRootView: View {
    @Environment(ShoppingCart.self) private var shoppingCart

    var body: some View {
        TabView {
            RecipesListView()
                .tabItem {
                    Label("Recipes", systemImage: "fork.knife")
                }

            RecipeSearchView()
                .tabItem {
                    Label("Search", systemImage: "magnifyingglass")
                }

            ShoppingListView()
                .tabItem {
                    Label("Shopping", systemImage: "cart")
                }
                .badge(shoppingCart.uncheckedCount > 0 ? shoppingCart.uncheckedCount : 0)
        }
    }
}
