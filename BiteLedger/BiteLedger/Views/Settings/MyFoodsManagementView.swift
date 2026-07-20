//
//  MyFoodsManagementView.swift
//  BiteLedger
//
//  Created by Craig Faist on 2/25/26.
//

import SwiftUI
import SwiftData
import BiteLedgerCore

struct MyFoodsManagementView: View {
    @Environment(\.modelContext) private var modelContext

    @State private var searchText = ""
    @State private var selectedFood: FoodItem?
    @State private var showDeleteConfirmation = false
    @State private var foodToDelete: FoodItem?
    @State private var sortOrder: SortOrder = .dateAdded
    @State private var displayedFoods: [FoodItem] = []
    @State private var loadTask: Task<Void, Never>?

    enum SortOrder: String, CaseIterable {
        case name = "Name"
        case dateAdded = "Date Added"
        case lastUsed = "Last Used"
    }

    private func sourceLabel(_ source: String) -> String {
        if source.hasPrefix("recipe_") { return "Recipe" }
        if source.hasPrefix("usda_") { return "USDA" }
        if source.hasPrefix("fatsecret_") { return "FatSecret" }
        if source.isEmpty { return "Manual" }
        return source
    }

    // Debounced for active search so typing doesn't re-scan the whole table on every
    // keystroke (MyFoodsQuery.fetch pushes the name/brand match into SQL instead of
    // fetching every FoodItem and filtering in memory). Sort-order changes and the
    // initial load run immediately.
    private func loadFoods(debounce: Bool = false) {
        loadTask?.cancel()
        let text = searchText
        let order = sortOrder

        guard debounce, !text.isEmpty else {
            displayedFoods = MyFoodsQuery.fetch(searchText: text, sortOrder: order, context: modelContext)
            return
        }

        loadTask = Task {
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            displayedFoods = MyFoodsQuery.fetch(searchText: text, sortOrder: order, context: modelContext)
        }
    }
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if displayedFoods.isEmpty {
                    ContentUnavailableView {
                        Label(searchText.isEmpty ? "No Foods Yet" : "No Results", 
                              systemImage: searchText.isEmpty ? "fork.knife" : "magnifyingglass")
                    } description: {
                        Text(searchText.isEmpty ? 
                             "Foods you create will appear here" : 
                             "No foods match '\(searchText)'")
                    }
                } else {
                    List {
                        ForEach(displayedFoods) { food in
                            Button {
                                selectedFood = food
                            } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(food.name)
                                            .foregroundStyle(.primary)
                                            .fontWeight(.medium)
                                        
                                        if let brand = food.brand, !brand.isEmpty {
                                            Text(brand)
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                        
                                        HStack(spacing: 8) {
                                            Text("\(Int(food.calories)) cal")
                                                .font(.caption2)
                                                .foregroundStyle(.blue)

                                            if let servingLabel = food.defaultServing?.label {
                                                Text(servingLabel)
                                                    .font(.caption2)
                                                    .foregroundStyle(.tertiary)
                                            }

                                            Text(sourceLabel(food.source))
                                                .font(.caption2)
                                                .foregroundStyle(.orange)
                                        }

                                        if let lastDate = food.foodLogs.max(by: { $0.timestamp < $1.timestamp })?.timestamp {
                                            Text("Last used \(lastDate.lastUsedDisplay)")
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
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                Button(role: .destructive) {
                                    foodToDelete = food
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
            .navigationTitle("My Foods")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $searchText, prompt: "Search foods")
            .onAppear {
                loadFoods()
            }
            .onChange(of: searchText) { _, _ in
                loadFoods(debounce: true)
            }
            .onChange(of: sortOrder) { _, _ in
                loadFoods()
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
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
            }
            .sheet(item: $selectedFood) { food in
                FoodItemEditorView(foodItem: food)
            }
            .alert("Delete Food?", isPresented: $showDeleteConfirmation) {
                Button("Cancel", role: .cancel) {
                    foodToDelete = nil
                }
                Button("Delete", role: .destructive) {
                    if let food = foodToDelete {
                        deleteFood(food)
                    }
                }
            } message: {
                if let food = foodToDelete {
                    Text("Are you sure you want to delete '\(food.name)'? This cannot be undone.")
                }
            }
        }
    }
    

    private func deleteFood(_ food: FoodItem) {
        modelContext.delete(food)
        try? modelContext.save()
        foodToDelete = nil
        loadFoods()
    }
}
