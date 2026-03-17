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

            // Apply search filter
            if searchText.isEmpty {
                displayedFoods = allFoods
            } else {
                displayedFoods = allFoods.filter { food in
                    food.name.localizedCaseInsensitiveContains(searchText) ||
                    (food.brand?.localizedCaseInsensitiveContains(searchText) ?? false)
                }
            }

            // Apply last-used sort in memory (can't do this in FetchDescriptor)
            if sortOrder == .lastUsed {
                displayedFoods.sort { a, b in
                    let aDate = a.foodLogs.max(by: { $0.timestamp < $1.timestamp })?.timestamp
                    let bDate = b.foodLogs.max(by: { $0.timestamp < $1.timestamp })?.timestamp
                    switch (aDate, bDate) {
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

                                            Text(food.source)
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
