//
//  Recipe.swift
//  BiteLedger
//
//  Created by Craig Faist on 2/16/26.
//

import SwiftData
import Foundation

// MARK: - Recipe

@Model
public final class Recipe {

    // MARK: Identity
    // CloudKit requires all stored properties to be optional or have default values.
    public var id: UUID = UUID()
    public var name: String = ""
    public var dateAdded: Date = Date()

    // MARK: Recipe Metadata

    /// Number of servings this recipe produces (e.g., 4 or 6.0).
    public var servingsYield: Double = 1.0

    /// Original URL this recipe was imported from. nil for manually created recipes.
    public var sourceURL: String?

    // MARK: Directions

    /// Ordered list of instruction steps, JSON-encoded as [String].
    /// Decode with `directions` computed property.
    public var directionsData: Data?

    /// Decoded ordered list of direction steps. Empty array if none stored.
    public var directions: [String] {
        get {
            guard let data = directionsData,
                  let steps = try? JSONDecoder().decode([String].self, from: data)
            else { return [] }
            return steps
        }
        set {
            directionsData = try? JSONEncoder().encode(newValue)
        }
    }

    // MARK: Imported Nutrition

    /// JSON-encoded RecipeNutrition — per-serving nutrition scraped from the recipe website.
    /// nil when no website nutrition was found or for manually entered recipes.
    public var importedNutritionData: Data? = nil

    /// Decoded website nutrition. Set this to encode and persist; read it to restore
    /// `importedNutrition` state in RecipeEditorView when editing an existing recipe.
    public var importedNutrition: RecipeNutrition? {
        get {
            guard let data = importedNutritionData,
                  let n = try? JSONDecoder().decode(RecipeNutrition.self, from: data)
            else { return nil }
            return n
        }
        set {
            importedNutritionData = try? JSONEncoder().encode(newValue)
        }
    }

    // MARK: Relationships

    /// The FoodItem generated from this recipe's nutrition. Used when logging.
    /// Cascade-deleted when the Recipe is deleted.
    @Relationship(deleteRule: .cascade) public var foodItem: FoodItem?

    /// The ingredient list for this recipe.
    /// Cascade-deleted when the Recipe is deleted.
    @Relationship(deleteRule: .cascade) public var ingredients: [RecipeIngredient] = []

    // MARK: Init

    public init(
        id: UUID = UUID(),
        name: String,
        servingsYield: Double = 1.0,
        sourceURL: String? = nil,
        directions: [String] = [],
        dateAdded: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.servingsYield = servingsYield
        self.sourceURL = sourceURL
        self.dateAdded = dateAdded
        self.directions = directions
    }

    // MARK: Computed Helpers

    /// The domain portion of the source URL for compact display (e.g., "themagicalslowcooker.com").
    public var sourceDomain: String? {
        guard let urlString = sourceURL,
              let url = URL(string: urlString),
              let host = url.host
        else { return nil }
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }

    /// Ingredients sorted by their display order.
    public var sortedIngredients: [RecipeIngredient] {
        ingredients.sorted { $0.sortOrder < $1.sortOrder }
    }

    /// True if any ingredient's food item has been deleted from the database.
    public var hasOrphanedIngredients: Bool {
        ingredients.contains { $0.foodItem == nil }
    }
}
