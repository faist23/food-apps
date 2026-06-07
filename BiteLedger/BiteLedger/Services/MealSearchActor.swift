import SwiftData
import BiteLedgerCore
import Foundation

/// Runs all meal-search fetches on a dedicated background ModelContext so the main
/// thread (and the keyboard) stay responsive while queries execute.
@ModelActor
actor MealSearchActor {

    /// Returns the `id` (UUID) of every FoodLog that belongs to a meal matching all
    /// words in `query`. Requires at least 2 characters; returns [] for shorter input.
    ///
    /// UUIDs are returned (not model objects) so they cross the actor boundary safely.
    /// The caller re-fetches by ID on the main context to get live, main-context-bound objects.
    func search(query: String) -> [UUID] {
        guard query.count >= 2 else { return [] }

        let words = query.split(separator: " ").map(String.init)
        let calendar = Calendar.current

        func mealKey(_ log: FoodLog) -> String {
            let day = calendar.startOfDay(for: log.timestamp)
            return "\(day.timeIntervalSince1970)-\(log.mealType.rawValue)"
        }

        var perWordMealKeys: [Set<String>] = []
        var allMatchingLogs: [FoodLog] = []
        var allMatchingLogIDs = Set<UUID>()

        for word in words {
            let nameLogs = (try? modelContext.fetch(
                FetchDescriptor<FoodLog>(
                    predicate: #Predicate { $0.foodItem?.name.localizedStandardContains(word) == true },
                    sortBy: [SortDescriptor(\FoodLog.timestamp, order: .reverse)]
                )
            )) ?? []

            // Brand search: CONTAINS[cdl] through an optional relationship crashes CoreData ("bad
            // RHS"). Fetch FoodItems by brand first, then access foodLogs. Relationship faulting
            // happens here but on this background context — the main thread stays free.
            let brandFoods = (try? modelContext.fetch(
                FetchDescriptor<FoodItem>(
                    predicate: #Predicate { $0.brand?.localizedStandardContains(word) == true }
                )
            )) ?? []
            let brandLogs = brandFoods.flatMap { $0.foodLogs }

            var seenIDs = Set(nameLogs.map { $0.id })
            let wordLogs = nameLogs + brandLogs.filter { seenIDs.insert($0.id).inserted }

            perWordMealKeys.append(Set(wordLogs.map { mealKey($0) }))
            for log in wordLogs where allMatchingLogIDs.insert(log.id).inserted {
                allMatchingLogs.append(log)
            }
        }

        guard let firstSet = perWordMealKeys.first else { return [] }
        let matchedMealKeys = perWordMealKeys.dropFirst().reduce(firstSet) { $0.intersection($1) }
        guard !matchedMealKeys.isEmpty else { return [] }

        // Timestamp-range fetch — uncapped, so older meal logs are never silently dropped.
        let anchorLogs = allMatchingLogs.filter { matchedMealKeys.contains(mealKey($0)) }
        guard let minTime = anchorLogs.map({ $0.timestamp }).min(),
              let maxTime = anchorLogs.map({ $0.timestamp }).max() else { return [] }

        let rangeStart = calendar.startOfDay(for: minTime)
        let rangeEnd = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: maxTime)) ?? maxTime
        let rangeLogs = (try? modelContext.fetch(
            FetchDescriptor<FoodLog>(
                predicate: #Predicate { $0.timestamp >= rangeStart && $0.timestamp < rangeEnd },
                sortBy: [SortDescriptor(\FoodLog.timestamp, order: .reverse)]
            )
        )) ?? []

        return rangeLogs
            .filter { matchedMealKeys.contains(mealKey($0)) }
            .map { $0.id }
    }
}
