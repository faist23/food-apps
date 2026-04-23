//
//  MealPlanEntry.swift
//  BiteLedgerCore
//
//  SwiftData model representing a single meal slot in a MealPlan week.
//
//  Invariant: exactly one of `recipe` or `foodItem` must be non-nil for a valid entry.
//  `isValid` is a computed helper — SwiftData will persist invalid entries (e.g. after
//  recipe/food deletion nullifies the relationship). UI display shows invalid entries
//  as "Removed food" with a warning icon. Log Day and shopping list generation guard
//  on isValid.
//
//  SchemaV3 — coordinates with MealPlan.
//

import SwiftData
import Foundation

@Model
public final class MealPlanEntry {
    // Relationship back to the parent week (nullify on MealPlan delete).
    public var mealPlan: MealPlan?

    // Specific day this entry belongs to (midnight, user's local timezone).
    public var date: Date

    // Which meal type this slot is for.
    public var mealType: MealType

    // Exactly one of these should be non-nil (recipe OR foodItem, never both).
    public var recipe: Recipe?       // nullify on Recipe delete
    public var foodItem: FoodItem?   // nullify on FoodItem delete
    public var servingSize: ServingSize?  // used for FoodItem entries; nil for Recipe entries

    // For Recipe entries: scale factor applied to the recipe yield.
    //   e.g. servingCount = 2.0 means "make this recipe twice" — ingredients × 2.
    // For FoodItem entries: number of servingSize units.
    public var servingCount: Double

    /// True when the entry references a valid food (recipe or foodItem is non-nil).
    /// Invalid entries occur when the referenced food was deleted after planning.
    public var isValid: Bool { recipe != nil || foodItem != nil }

    public init(mealPlan: MealPlan, date: Date, mealType: MealType) {
        self.mealPlan = mealPlan
        self.date = date
        self.mealType = mealType
        self.servingCount = 1.0
    }
}
