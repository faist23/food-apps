//
//  RecipeCardRootView.swift
//  RecipeCard
//

import SwiftUI
import BiteLedgerCore

struct RecipeCardRootView: View {
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
        }
    }
}
