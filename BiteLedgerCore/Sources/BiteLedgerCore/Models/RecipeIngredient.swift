//
//  RecipeIngredient.swift
//  BiteLedger
//
//  Created by Craig Faist on 2/16/26.
//

import SwiftData
import Foundation

// MARK: - RecipeIngredient

@Model
public final class RecipeIngredient {

    // MARK: Identity
    // CloudKit requires all stored properties to be optional or have default values.
    public var id: UUID = UUID()

    /// Number of servings of this ingredient (e.g., 2.0 = two servings of the chosen ServingSize).
    public var quantity: Double = 1.0

    /// Controls display order in the recipe ingredient list. Lower = shown first.
    public var sortOrder: Int = 0

    /// The original recipe ingredient line as written (e.g., "1.5 lbs chicken breast, boneless").
    /// When set, this is shown to the user instead of the quantity × serving format.
    public var rawText: String? = nil

    /// The ingredient quantity in original recipe units (e.g., 1.5 for "1.5 lbs chicken").
    /// nil for ingredients added manually via the serving picker.
    /// Pair with `recipeUnit` for display and scaling in RecipeCard.
    public var recipeQuantity: Double? = nil

    /// The original recipe unit string, normalised (e.g., "lb", "cup", "tbsp").
    /// nil for ingredients added manually via the serving picker.
    public var recipeUnit: String? = nil

    // MARK: Relationships

    /// The recipe this ingredient belongs to.
    public var recipe: Recipe?

    /// The food item used as this ingredient.
    /// Nullified if the food item is deleted — check for nil in the UI.
    @Relationship(deleteRule: .nullify) public var foodItem: FoodItem?

    /// The specific serving size selected for this ingredient.
    /// Nullified if the serving size is deleted. Falls back to food's default serving.
    @Relationship(deleteRule: .nullify) public var servingSize: ServingSize?

    // MARK: Init

    public init(
        id: UUID = UUID(),
        quantity: Double = 1.0,
        sortOrder: Int = 0,
        recipeQuantity: Double? = nil,
        recipeUnit: String? = nil
    ) {
        self.id = id
        self.quantity = quantity
        self.sortOrder = sortOrder
        self.recipeQuantity = recipeQuantity
        self.recipeUnit = recipeUnit
    }

    // MARK: Computed Helpers

    /// A display label for this ingredient line.
    /// Uses rawText when available (preserves the original recipe wording).
    public var displayLabel: String {
        if let raw = rawText, !raw.isEmpty { return raw }
        let foodName = foodItem?.name ?? "Deleted Food"
        let servingLabel = servingSize?.label ?? foodItem?.defaultServing?.label ?? "1 serving"
        let qty = quantity.truncatingRemainder(dividingBy: 1) == 0
            ? String(Int(quantity))
            : String(format: "%.2g", quantity)
        return "\(qty) × \(servingLabel) — \(foodName)"
    }
}
