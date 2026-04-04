//
//  IngredientPickerView.swift
//  BiteRecipe
//

import SwiftUI
import SwiftData
import BiteLedgerCore

struct IngredientPickerView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    let onAdd: (FoodItem, ServingSize?, Double) -> Void

    @State private var searchText = ""
    @State private var results: [FoodItem] = []
    @State private var selectedFood: FoodItem?
    @State private var selectedServing: ServingSize?
    @State private var quantity: Double = 1.0

    var body: some View {
        NavigationStack {
            Group {
                if let food = selectedFood {
                    servingSelectionView(food: food)
                } else {
                    foodSearchView
                }
            }
            .navigationTitle("Add Ingredient")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                if selectedFood != nil {
                    ToolbarItem(placement: .navigationBarLeading) {
                        Button("Back") {
                            selectedFood = nil
                            selectedServing = nil
                            quantity = 1.0
                        }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Add") {
                            if let food = selectedFood {
                                onAdd(food, selectedServing, quantity)
                                dismiss()
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: - Food Search

    private var foodSearchView: some View {
        List(results) { food in
            Button {
                selectedFood = food
                selectedServing = food.defaultServing
            } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Text(food.name)
                        .foregroundStyle(.primary)
                    if let brand = food.brand {
                        Text(brand)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .searchable(text: $searchText, prompt: "Search your foods")
        .onChange(of: searchText) { _, query in
            searchLocalFoods(query: query)
        }
        .onAppear { searchLocalFoods(query: "") }
        .overlay {
            if results.isEmpty && !searchText.isEmpty {
                ContentUnavailableView.search(text: searchText)
            }
        }
    }

    private func searchLocalFoods(query: String) {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        let descriptor: FetchDescriptor<FoodItem>
        if trimmed.isEmpty {
            descriptor = FetchDescriptor<FoodItem>(
                sortBy: [SortDescriptor(\.name)]
            )
        } else {
            descriptor = FetchDescriptor<FoodItem>(
                predicate: #Predicate { $0.name.localizedStandardContains(trimmed) },
                sortBy: [SortDescriptor(\.name)]
            )
        }
        results = (try? modelContext.fetch(descriptor)) ?? []
    }

    // MARK: - Serving Selection

    private func servingSelectionView(food: FoodItem) -> some View {
        Form {
            Section("Food") {
                Text(food.name).font(.headline)
                if let brand = food.brand {
                    Text(brand).foregroundStyle(.secondary)
                }
            }

            Section("Serving Size") {
                ForEach(food.servingSizes.sorted(by: { $0.sortOrder < $1.sortOrder })) { serving in
                    Button {
                        selectedServing = serving
                    } label: {
                        HStack {
                            Text(serving.label)
                                .foregroundStyle(.primary)
                            Spacer()
                            if selectedServing?.id == serving.id {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(.blue)
                            }
                        }
                    }
                }
            }

            Section("Quantity") {
                HStack {
                    Text("Amount")
                    Spacer()
                    TextField("1", value: $quantity, format: .number)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 80)
                    if let serving = selectedServing {
                        Text(serving.label)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Section("Nutrition Preview") {
                let r = NutritionCalculator.calculate(
                    food: food, serving: selectedServing, quantity: quantity
                )
                NutritionPreviewRow(label: "Calories", value: r.calories, unit: "")
                NutritionPreviewRow(label: "Protein",  value: r.protein,  unit: "g")
                NutritionPreviewRow(label: "Carbs",    value: r.carbs,    unit: "g")
                NutritionPreviewRow(label: "Fat",      value: r.fat,      unit: "g")
            }
        }
    }
}

private struct NutritionPreviewRow: View {
    let label: String
    let value: Double
    let unit: String
    var body: some View {
        HStack {
            Text(label)
            Spacer()
            Text("\(Int(value))\(unit)")
                .foregroundStyle(.secondary)
        }
    }
}
