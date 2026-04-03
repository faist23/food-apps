//
//  RecipeCardRootView.swift
//  RecipeCard
//

import SwiftUI
import BiteLedgerCore

struct RecipeCardRootView: View {
    @Environment(ShoppingCart.self) private var shoppingCart
    @State private var selectedTab = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            RecipesListView()
                .tabItem { Label("Recipes", systemImage: "fork.knife") }
                .tag(0)

            RecipeSearchView()
                .tabItem { Label("Search", systemImage: "magnifyingglass") }
                .tag(1)

            ShoppingListView()
                .tabItem { Label("Shopping", systemImage: "cart") }
                .tag(2)
                .badge(shoppingCart.uncheckedCount > 0 ? shoppingCart.uncheckedCount : 0)

            MealPlannerView(selectedTab: $selectedTab)
                .tabItem { Label("Plan", systemImage: "calendar") }
                .tag(3)
        }
    }
}
