//
//  MealPlanMeal.swift
//  BiteLedgerCore
//
//  SwiftData model representing a named cluster of items for one meal slot (mealType) on one day.
//  e.g. "PB Night" = PB + bread + honey (items).
//
//  SchemaV4 — coordinates with MealPlanMealItem and MealPlan.
//  Both BiteLedger and BitePlan must register this model in their schema arrays
//  even though only BitePlan queries it.
//
//  Relationship hierarchy:
//    MealPlan ─(cascade)→ MealPlanMeal ─(cascade)→ MealPlanMealItem
//
//  Uniqueness invariant: exactly one MealPlanMeal per (mealPlan, date, mealType).
//  Enforced by findOrCreateMeal() in MealPlanDayRow — see that file for the full
//  SwiftData lazy-load-safe implementation.
//

import SwiftData
import Foundation

@Model
public final class MealPlanMeal {
    // Stable identifier for CSV export/import round-trips (SchemaV5).
    public var id: UUID = UUID()

    // Relationship back to the parent week (nullify on MealPlan delete).
    public var mealPlan: MealPlan?

    // Specific day this meal belongs to (midnight, user's local timezone).
    public var date: Date

    // Which meal type. v1 UI creates only .dinner; model supports all types.
    public var mealType: MealType

    // User-set custom name. nil = use computed displayName (derived from items).
    public var name: String?

    @Relationship(deleteRule: .cascade, inverse: \MealPlanMealItem.meal)
    public var items: [MealPlanMealItem] = []

    // MARK: - Computed display name (not stored — derived at render time)
    //
    // 0 items → nil (slot is empty, UI shows "Add dinner")
    // 1 item  → items[0].displayName
    // 2+ items → "<first> + N more"
    // user name set → name (overrides auto)
    public var displayName: String? {
        if let name { return name }
        guard !items.isEmpty else { return nil }
        if items.count == 1 { return items[0].displayName }
        return "\(items[0].displayName) + \(items.count - 1) more"
    }

    public init(mealPlan: MealPlan, date: Date, mealType: MealType) {
        self.mealPlan = mealPlan
        self.date = date
        self.mealType = mealType
    }
}
