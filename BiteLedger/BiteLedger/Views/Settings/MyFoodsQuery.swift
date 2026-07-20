//
//  MyFoodsQuery.swift
//  BiteLedger
//

import Foundation
import SwiftData
import BiteLedgerCore

// MARK: - MyFoodsQuery
//
// Extracted from MyFoodsManagementView.loadFoods() so the search-narrowing logic is
// unit-testable (SwiftUI @State/@Environment aren't testable directly — see T-16 in
// TODOS.md for the established pattern of extracting view logic to pure functions).
//
// The active-search path pushes the name/brand substring match into the SQL predicate
// instead of fetching every FoodItem and filtering in memory — mirrors
// MyFoodsListView.startMyFoodsSearch() in FoodSearchView.swift.

enum MyFoodsQuery {

    /// Same three-tier filter logic as `startMyFoodsSearch()` (FoodSearchView.swift) —
    /// per the "MyFoodsManagementView — Filter Invariant" section of BiteLedger's CLAUDE.md,
    /// this must stay identical wherever My Foods is filtered.
    static func fetch(
        searchText: String,
        sortOrder: MyFoodsManagementView.SortOrder,
        context: ModelContext
    ) -> [FoodItem] {
        let trimmed = searchText.trimmingCharacters(in: .whitespaces)

        let descriptor: FetchDescriptor<FoodItem>
        if trimmed.isEmpty {
            switch sortOrder {
            case .name:
                descriptor = FetchDescriptor<FoodItem>(sortBy: [SortDescriptor(\FoodItem.name)])
            case .dateAdded:
                descriptor = FetchDescriptor<FoodItem>(sortBy: [SortDescriptor(\FoodItem.dateAdded, order: .reverse)])
            case .lastUsed:
                descriptor = FetchDescriptor<FoodItem>()
            }
        } else {
            // Push the substring match into SQL so typing doesn't scan the whole table.
            let predicate = #Predicate<FoodItem> {
                $0.name.localizedStandardContains(trimmed) ||
                $0.brand?.localizedStandardContains(trimmed) == true
            }
            switch sortOrder {
            case .name:
                descriptor = FetchDescriptor<FoodItem>(predicate: predicate, sortBy: [SortDescriptor(\FoodItem.name)])
            case .dateAdded:
                descriptor = FetchDescriptor<FoodItem>(predicate: predicate, sortBy: [SortDescriptor(\FoodItem.dateAdded, order: .reverse)])
            case .lastUsed:
                descriptor = FetchDescriptor<FoodItem>(predicate: predicate)
            }
        }

        guard let candidates = try? context.fetch(descriptor) else { return [] }

        // Build the set of food IDs the user has personally logged, using
        // FoodHistoryEntry as the canonical logged-foods index (no N+1 faults).
        let historyEntries = (try? context.fetch(FetchDescriptor<FoodHistoryEntry>())) ?? []
        let loggedIDs = Set(historyEntries.compactMap { $0.food?.id })

        var userFoods = candidates.filter { food in
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

        guard sortOrder == .lastUsed else { return userFoods }

        // Pass 1: FoodHistoryEntry index (fast, no faults).
        // Pass 2: food.foodLogs fallback for any food the backfill missed —
        //         runs once here, on the filtered result set, not per-row in the view.
        var lastUsedMap: [UUID: Date] = [:]
        for entry in historyEntries {
            guard let food = entry.food, lastUsedMap[food.id] == nil else { continue }
            lastUsedMap[food.id] = entry.lastLoggedDate
        }
        for food in userFoods where lastUsedMap[food.id] == nil {
            lastUsedMap[food.id] = food.foodLogs.max(by: { $0.timestamp < $1.timestamp })?.timestamp
        }
        userFoods.sort { a, b in
            switch (lastUsedMap[a.id], lastUsedMap[b.id]) {
            case (.some(let d1), .some(let d2)): return d1 > d2
            case (.some, .none): return true
            case (.none, .some): return false
            case (.none, .none): return a.name < b.name
            }
        }
        return userFoods
    }
}
