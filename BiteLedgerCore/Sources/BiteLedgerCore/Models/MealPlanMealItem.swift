//
//  MealPlanMealItem.swift
//  BiteLedgerCore
//
//  SwiftData model representing one item in a MealPlanMeal cluster.
//  Exactly one of recipe, foodItem, or note should be non-nil.
//
//  SchemaV4 — coordinates with MealPlanMeal.
//

import SwiftData
import Foundation

@Model
public final class MealPlanMealItem {
    // Relationship back to the parent meal (nullify on MealPlanMeal delete).
    public var meal: MealPlanMeal?

    // Exactly one of these should be non-nil:
    public var recipe: Recipe?       // nullify on Recipe delete
    public var foodItem: FoodItem?   // nullify on FoodItem delete
    public var note: String?         // free text (restaurant name, meal note, etc.)

    // ServingSize for FoodItem entries; nil for Recipe and note entries.
    public var servingSize: ServingSize?

    // Serving count / batch count.
    // Recipe: 1.0 = full batch, 0.5 = half batch
    // FoodItem: number of servingSize units
    // Note: not displayed (isNoteOnly == true)
    public var servingCount: Double

    // MARK: - Computed helpers

    /// True when the item has meaningful nutritional content to contribute.
    /// Note-only items are valid for display but contribute no nutrition.
    public var isValid: Bool { recipe != nil || foodItem != nil || note != nil }

    /// True when the item is a free-text note with no food or recipe attached.
    /// Note-only items are skipped by shopping list generation and logDay().
    public var isNoteOnly: Bool { recipe == nil && foodItem == nil && note != nil }

    /// Display name for chips, collapsed row, and Added strip.
    /// Precedence: recipe → food → note → "Unknown"
    public var displayName: String {
        recipe?.name ?? foodItem?.name ?? note ?? "Unknown"
    }

    public init(meal: MealPlanMeal) {
        self.meal = meal
        self.servingCount = 1.0
    }
}
