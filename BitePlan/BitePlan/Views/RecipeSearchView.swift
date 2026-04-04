//
//  RecipeSearchView.swift
//  BitePlan
//

import SwiftUI
import SwiftData
import BiteLedgerCore

struct RecipeSearchView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var searchText = ""
    @State private var results: [Recipe] = []

    private let gridColumns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12)
    ]

    var body: some View {
        NavigationStack {
            Group {
                if results.isEmpty {
                    ContentUnavailableView(
                        searchText.isEmpty ? "No Recipes" : "No Results",
                        systemImage: "magnifyingglass",
                        description: Text(searchText.isEmpty
                            ? "Create recipes in the Recipes tab."
                            : "Try a different search term.")
                    )
                } else {
                    ScrollView {
                        LazyVGrid(columns: gridColumns, spacing: 12) {
                            ForEach(results) { recipe in
                                NavigationLink(destination: RecipeDetailView(recipe: recipe)) {
                                    RecipeCardView(recipe: recipe)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                    }
                }
            }
            .navigationTitle("Search")
            .searchable(text: $searchText, prompt: "Search recipes")
            .onChange(of: searchText) { _, query in search(query) }
            .onAppear { search("") }
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
