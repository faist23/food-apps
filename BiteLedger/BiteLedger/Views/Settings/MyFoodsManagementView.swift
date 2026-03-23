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

    private func loadFoods() {
        let descriptor: FetchDescriptor<FoodItem>
        
        switch sortOrder {
        case .name:
            descriptor = FetchDescriptor<FoodItem>(
                sortBy: [SortDescriptor(\FoodItem.name)]
            )
        case .dateAdded:
            descriptor = FetchDescriptor<FoodItem>(
                sortBy: [SortDescriptor(\FoodItem.dateAdded, order: .reverse)]
            )
        case .lastUsed:
            descriptor = FetchDescriptor<FoodItem>()
        }

        do {
            let allFoods = try modelContext.fetch(descriptor)

            // Build the set of food IDs the user has personally logged, using
            // FoodHistoryEntry as the canonical logged-foods index (no N+1 faults).
            let historyEntries = (try? modelContext.fetch(FetchDescriptor<FoodHistoryEntry>())) ?? []
            let loggedIDs = Set(historyEntries.compactMap { $0.food?.id })

            let userFoods = allFoods.filter { food in
                // Always exclude seeded catalog items.
                guard !food.source.hasPrefix("usda_seed"),
                      !food.source.hasPrefix("built_in") else { return false }
                // Known user-created sources — always show.
                if food.source.isEmpty ||
                   food.source == "Manual" ||
                   food.source == "Quick Add" ||
                   food.source.hasPrefix("recipe") ||
                   food.source.hasPrefix("LoseIt") ||
                   food.source.hasPrefix("CSV Import") {
                    return true
                }
                // API-fetched sources (usda_*, fatsecret_*, OFacts barcodes, etc.)
                // only appear if personally logged.
                return loggedIDs.contains(food.id)
            }

            // Apply search filter
            if searchText.isEmpty {
                displayedFoods = userFoods
            } else {
                displayedFoods = userFoods.filter { food in
                    food.name.localizedCaseInsensitiveContains(searchText) ||
                    (food.brand?.localizedCaseInsensitiveContains(searchText) ?? false)
                }
            }

            // Apply last-used sort.
            // Pass 1: FoodHistoryEntry index (fast, no faults).
            // Pass 2: food.foodLogs fallback for any food the backfill missed —
            //         runs once at load time on the full list, not per-row in the view.
            if sortOrder == .lastUsed {
                var lastUsedMap: [UUID: Date] = [:]
                for entry in historyEntries {
                    guard let food = entry.food, lastUsedMap[food.id] == nil else { continue }
                    lastUsedMap[food.id] = entry.lastLoggedDate
                }
                for food in displayedFoods where lastUsedMap[food.id] == nil {
                    lastUsedMap[food.id] = food.foodLogs.max(by: { $0.timestamp < $1.timestamp })?.timestamp
                }
                displayedFoods.sort { a, b in
                    switch (lastUsedMap[a.id], lastUsedMap[b.id]) {
                    case (.some(let d1), .some(let d2)): return d1 > d2
                    case (.some, .none): return true
                    case (.none, .some): return false
                    case (.none, .none): return a.name < b.name
                    }
                }
            }
        } catch {
            print("Error loading foods: \(error)")
            displayedFoods = []
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
                loadFoods()
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
