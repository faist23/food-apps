//
//  RecipeSearchView.swift
//  RecipeCard
//

import SwiftUI
import SwiftData
import BiteLedgerCore

struct RecipeSearchView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var searchText = ""
    @State private var results: [Recipe] = []

    var body: some View {
        NavigationStack {
            List {
                ForEach(results) { recipe in
                    NavigationLink(destination: RecipeDetailView(recipe: recipe)) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(recipe.name)
                                .font(.headline)
                            if let servings = Optional(recipe.servingsYield) {
                                Text("\(Int(servings)) servings")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                }
            }
            .navigationTitle("Search")
            .searchable(text: $searchText, prompt: "Search recipes")
            .onChange(of: searchText) { _, query in search(query) }
            .onAppear { search("") }
            .overlay {
                if results.isEmpty {
                    ContentUnavailableView(
                        searchText.isEmpty ? "No Recipes" : "No Results",
                        systemImage: "magnifyingglass",
                        description: Text(searchText.isEmpty
                            ? "Create recipes in the Recipes tab."
                            : "Try a different search term.")
                    )
                }
            }
        }
    }

    private func search(_ query: String) {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        let descriptor: FetchDescriptor<Recipe>
        if trimmed.isEmpty {
            descriptor = FetchDescriptor<Recipe>(sortBy: [SortDescriptor(\.name)])
        } else {
            descriptor = FetchDescriptor<Recipe>(
                predicate: #Predicate { $0.name.localizedStandardContains(trimmed) },
                sortBy: [SortDescriptor(\.name)]
            )
        }
        results = (try? modelContext.fetch(descriptor)) ?? []
    }
}
