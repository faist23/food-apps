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
//  │       │     count days > base * dvMultiplier             │
//  │       │     qualify if count ≥ minDaysAbove             │
//  │       └─ return [SpotlightResult] sorted desc           │
//  │                                                         │
//  │  TodayView chip: results[0] (max 1)                     │
//  │  HistoryView card: results.prefix(2) (max 2)            │
//  └─────────────────────────────────────────────────────────┘

import Foundation

// MARK: - FoodContribution

public struct FoodContribution: Sendable {
    public let foodName: String
    public let totalAmount: Double
    public let unit: String
    public let percentOfTotal: Double
}

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
    ///   - userGoals: User's saved NutrientGoal map (keyed by Nutrient.rawValue). When a goal
    ///     of type `.maximum` or `.range` exists for a nutrient, its `targetValue` is used as
    ///     the threshold base instead of the FDA daily value. Minimum goals are ignored —
    ///     spotlight flags high-side only.
    ///   - minDaysAbove: Minimum number of days above threshold to qualify. Default: 3.
    ///   - dvMultiplier: Fraction of goal (or FDA DV) that defines "high". Default: 1.2 (120%).
    /// - Returns: Qualifying nutrients sorted by daysAboveThreshold descending.
    ///   Returns [] if logs is empty or fewer than minDaysAbove distinct calendar days are logged.
    public static func compute(
        logs: [FoodLog],
        userGoals: [String: NutrientGoal] = [:],
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
            // If the user has a minimum goal for this nutrient, eating more is intentional —
            // suppress the high-side flag entirely.
            if let goal = userGoals[nutrient.rawValue], goal.goalType == .minimum {
                continue
            }

            // Use user's goal value when set as a maximum or range — those goal types
            // define an upper ceiling, matching the high-side nature of spotlight.
            // Fall back to the FDA daily value when no goal is set.
            let base: Double
            if let goal = userGoals[nutrient.rawValue], goal.goalType == .maximum || goal.goalType == .range {
                base = goal.targetValue
            } else {
                base = nutrient.defaultGoalValue
            }
            let threshold = base * dvMultiplier

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

    /// Rank foods by their total contribution to a nutrient over the log window.
    ///
    /// - Parameters:
    ///   - nutrient: The nutrient to aggregate.
    ///   - logs: FoodLog entries for the window (same slice passed to `compute`).
    ///   - topN: Maximum number of results to return. Default: 5.
    /// - Returns: Foods sorted by total contribution descending, with percent-of-total.
    ///   Returns [] when no logs contain a value for the nutrient.
    public static func topContributors(
        for nutrient: Nutrient,
        logs: [FoodLog],
        topN: Int = 5
    ) -> [FoodContribution] {
        var totals: [String: Double] = [:]
        for log in logs {
            guard let value = nutrient.value(from: log) else { continue }
            let name = log.foodItem?.name ?? "Unknown Food"
            totals[name, default: 0] += value
        }
        let weekTotal = totals.values.reduce(0, +)
        guard weekTotal > 0 else { return [] }
        return totals
            .sorted { $0.value > $1.value }
            .prefix(topN)
            .map { FoodContribution(
                foodName: $0.key,
                totalAmount: $0.value,
                unit: nutrient.unit,
                percentOfTotal: $0.value / weekTotal
            )}
    }
}
