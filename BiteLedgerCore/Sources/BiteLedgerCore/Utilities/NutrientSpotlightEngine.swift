//
//  NutrientSpotlightEngine.swift
//  BiteLedgerCore
//
//  Phase 2, Feature 1: Nutrient Spotlight
//  Pure struct — no SwiftData dependency, fully unit-testable.
//
//  ┌─────────────────────────────────────────────────────────┐
//  │  [7-day FoodLogs]                                       │
//  │       │                                                 │
//  │       ▼                                                 │
//  │  NutrientSpotlightEngine.compute()                      │
//  │       │                                                 │
//  │       ├─ group logs by calendar day                     │
//  │       ├─ for each spotlight nutrient:                   │
//  │       │     sum *AtLogTime per day (skip nil-only days) │
//  │       │     count days > fdaDV * dvMultiplier           │
//  │       │     qualify if count ≥ minDaysAbove             │
//  │       └─ return [SpotlightResult] sorted desc           │
//  │                                                         │
//  │  TodayView chip: results[0] (max 1)                     │
//  │  HistoryView card: results.prefix(2) (max 2)            │
//  └─────────────────────────────────────────────────────────┘

import Foundation

// MARK: - SpotlightResult

public struct SpotlightResult: Sendable {
    public let nutrient: Nutrient
    public let daysAboveThreshold: Int
    /// "{Display name} has been high this week."
    public let message: String

    public init(nutrient: Nutrient, daysAboveThreshold: Int) {
        self.nutrient = nutrient
        self.daysAboveThreshold = daysAboveThreshold
        self.message = "\(nutrient.spotlightDisplayName) has been high this week."
    }
}

// MARK: - NutrientSpotlightEngine

public struct NutrientSpotlightEngine {

    // Product-level constants — not user preferences, not stored in schema.
    // Injectable so unit tests can vary them and future personalized-baseline
    // mode can pass different values at the call site.
    public static let defaultMinDays: Int = 3
    public static let defaultDVMultiplier: Double = 1.2

    /// Curiosity prompt — same for all nutrients in v1.
    public static let curiosityPrompt = "Curious where it's coming from?"

    /// Spotlight nutrients (high-side only in v1).
    /// Order determines priority when daysAbove is tied.
    /// Computed var avoids Swift 6 mutable-global-variable warning.
    static var spotlightNutrients: [Nutrient] {
        [.sodium, .saturatedFat, .fat, .cholesterol, .carbs]
    }

    /// Compute spotlight results from pre-fetched logs.
    ///
    /// - Parameters:
    ///   - logs: FoodLog entries — caller pre-filters to the desired window (7 calendar days).
    ///   - minDaysAbove: Minimum number of days above threshold to qualify. Default: 3.
    ///   - dvMultiplier: Fraction of FDA DV that defines "high". Default: 1.2 (120%).
    /// - Returns: Qualifying nutrients sorted by daysAboveThreshold descending.
    ///   Returns [] if logs is empty or fewer than minDaysAbove distinct calendar days are logged.
    public static func compute(
        logs: [FoodLog],
        minDaysAbove: Int = defaultMinDays,
        dvMultiplier: Double = defaultDVMultiplier
    ) -> [SpotlightResult] {
        guard !logs.isEmpty else { return [] }

        let calendar = Calendar.current

        // Guard: need at least minDaysAbove distinct logged days in the window.
        let uniqueDays = Set(logs.map { calendar.startOfDay(for: $0.timestamp) })
        guard uniqueDays.count >= minDaysAbove else { return [] }

        var results: [SpotlightResult] = []

        for nutrient in spotlightNutrients {
            let threshold = nutrient.defaultGoalValue * dvMultiplier

            // Sum *AtLogTime per calendar day.
            // Days where ALL logs have nil for this nutrient are excluded
            // entirely — they contribute no entry to dailySums.
            var dailySums: [Date: Double] = [:]
            for log in logs {
                guard let value = nutrient.value(from: log) else { continue }
                let day = calendar.startOfDay(for: log.timestamp)
                dailySums[day, default: 0] += value
            }

            let daysAbove = dailySums.values.filter { $0 > threshold }.count
            if daysAbove >= minDaysAbove {
                results.append(SpotlightResult(nutrient: nutrient, daysAboveThreshold: daysAbove))
            }
        }

        return results.sorted { $0.daysAboveThreshold > $1.daysAboveThreshold }
    }
}
