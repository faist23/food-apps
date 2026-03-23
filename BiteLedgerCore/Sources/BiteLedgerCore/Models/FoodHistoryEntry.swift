//
//  FoodHistoryEntry.swift
//  BiteLedgerCore
//
//  Personal food history index — one record per (FoodItem, MealType) pair.
//
//  Purpose: Replace the O(N) FoodLog scan in RecentFoodsForMealView with an
//  indexed O(1) query. Each record tracks the last logged date and total log
//  count for a (food, mealType) combination.
//
//  Lifecycle:
//  - Created/updated by FoodHistoryEntry.upsert(), called from FoodLog.create().
//  - Backfilled from existing FoodLogs on first launch after SchemaV2 migration
//    (guarded by UserPreferences.hasBackfilledFoodHistory flag).
//  - When a FoodItem is deleted, SwiftData nullifies food → nil (default .nullify rule).
//    Orphaned entries (food == nil) are filtered at display time via compactMap { $0.food }.
//    No back-reference on FoodItem — avoids "Duplicate version checksums" in migration plan.
//
//  Schema: Added in BiteLedgerSchemaV2 / RecipeCardSchemaV2 (lightweight migration).
//

import SwiftData
import Foundation

// MARK: - FoodHistoryEntry

@Model
public final class FoodHistoryEntry {

    // MARK: Identity
    public var id: UUID = UUID()

    // MARK: Relationships
    /// The food this entry tracks. Nil if FoodItem was deleted (should not occur
    /// in normal use — cascade delete on FoodItem.historyEntries removes this record).
    public var food: FoodItem?

    // MARK: Index Key
    /// The meal type context — part of the composite key with food.
    public var mealType: MealType = MealType.breakfast

    // MARK: Metrics
    /// Timestamp of the most recent log for this (food, mealType).
    public var lastLoggedDate: Date = Date()

    /// Total number of times this food has been logged for this meal type.
    public var logCount: Int = 1

    // MARK: Init
    public init(food: FoodItem, mealType: MealType) {
        self.food = food
        self.mealType = mealType
        self.lastLoggedDate = Date()
        self.logCount = 1
    }
}

// MARK: - Upsert

extension FoodHistoryEntry {
    /// Updates the history index for a logged food.
    ///
    /// Called by `FoodLog.create()` after creating the log entry.
    /// Finds the existing `FoodHistoryEntry` for this (food, mealType) pair and
    /// increments it, or inserts a new entry if none exists.
    ///
    /// Safe to call multiple times with the same arguments — idempotent in the
    /// sense that it never creates duplicates. If duplicates exist (e.g., from
    /// an interrupted backfill), they are merged: logCounts summed, latest
    /// lastLoggedDate kept, older records deleted.
    ///
    /// Runs on @MainActor (same as all SwiftData mutations in this app).
    public static func upsert(food: FoodItem, mealType: MealType, in context: ModelContext) {
        let foodID = food.id
        var descriptor = FetchDescriptor<FoodHistoryEntry>(
            predicate: #Predicate { $0.mealType == mealType && $0.food?.id == foodID }
        )
        // Fetch at most 2 — if we get 2, there's a duplicate to merge.
        descriptor.fetchLimit = 2

        guard let existing = try? context.fetch(descriptor) else { return }

        switch existing.count {
        case 0:
            // First log for this (food, mealType) — create a new entry.
            let entry = FoodHistoryEntry(food: food, mealType: mealType)
            context.insert(entry)

        case 1:
            // Normal case — increment the existing entry.
            existing[0].logCount += 1
            existing[0].lastLoggedDate = Date()

        default:
            // Duplicate entries (should not happen in normal use).
            // Merge: sum logCounts, keep latest lastLoggedDate, delete extras.
            let primary = existing[0]
            primary.logCount = existing.reduce(0) { $0 + $1.logCount } + 1
            primary.lastLoggedDate = Date()
            for duplicate in existing.dropFirst() {
                context.delete(duplicate)
            }
        }
    }
}
