//
//  MealPlan.swift
//  BiteLedgerCore
//
//  SwiftData model representing a week's meal plan.
//  One MealPlan per calendar week, anchored to Sunday midnight (user's local timezone).
//
//  SchemaV3 — coordinates with MealPlanEntry.
//  Both BiteLedger and RecipeCard must register this model in their schema arrays
//  even though only RecipeCard queries it.
//

import SwiftData
import Foundation

@Model
public final class MealPlan {
    // Sunday of the week, midnight in the user's local timezone.
    // Always normalized via Calendar.current.startOfDay — never UTC midnight.
    public var weekStartDate: Date

    @Relationship(deleteRule: .cascade, inverse: \MealPlanEntry.mealPlan)
    public var entries: [MealPlanEntry] = []

    // SchemaV4: named meal clusters (replaces single-entry model for UI).
    // entries is kept for schema backward compat but cleared on first V4 launch.
    @Relationship(deleteRule: .cascade, inverse: \MealPlanMeal.mealPlan)
    public var meals: [MealPlanMeal] = []

    public init(weekStartDate: Date) {
        self.weekStartDate = weekStartDate
    }

    // MARK: - Week helpers

    /// Returns the Sunday midnight date for the week containing `date`,
    /// in the user's local timezone.
    ///
    /// Uses .weekday component (1 = Sunday in Gregorian) to find the preceding Sunday.
    /// Normalizes to midnight via Calendar.current.startOfDay so the result is stable
    /// for equality comparisons when used as a SwiftData predicate.
    public static func startOfWeek(for date: Date = .now, calendar: Calendar = .current) -> Date {
        let weekday = calendar.component(.weekday, from: date)
        // weekday 1 = Sunday in Gregorian calendar
        let daysBack = weekday - 1
        let sunday = calendar.date(byAdding: .day, value: -daysBack, to: date) ?? date
        return calendar.startOfDay(for: sunday)
    }

    /// The 7 dates in this week (Sunday through Saturday), at midnight local time.
    public func weekDates(calendar: Calendar = .current) -> [Date] {
        (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: weekStartDate) }
    }
}
