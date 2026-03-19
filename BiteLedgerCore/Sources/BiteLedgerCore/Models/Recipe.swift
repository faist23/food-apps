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

    // MARK: - Rich Metadata (populated on URL import from Schema.org)

    /// Prep time in minutes (from ISO 8601 `prepTime`, e.g. "PT15M" → 15). nil if not specified.
    public var prepMinutes: Int? = nil
    /// Active cook time in minutes. nil if not specified.
    public var cookMinutes: Int? = nil
    /// Total time in minutes (prep + cook). nil if not specified.
    public var totalMinutes: Int? = nil
    /// Remote URL for the recipe hero image. Display with AsyncImage.
    public var imageURL: String? = nil
    /// Description / intro paragraph from the recipe website.
    public var recipeDescription: String? = nil
    /// Recipe category (e.g. "Dinner", "Dessert", "Appetizer").
    public var recipeCategory: String? = nil
    /// Cuisine type (e.g. "Italian", "Mexican").
    public var recipeCuisine: String? = nil
    /// Recipe author name.
    public var author: String? = nil
    /// Aggregate star rating from the source site (e.g. 4.5).
    public var ratingValue: Double? = nil
    /// Number of ratings/reviews at the source site.
    public var ratingCount: Int? = nil
    /// JSON-encoded [String] — keyword tags from the website.
    public var keywordsData: Data? = nil
    /// JSON-encoded [String] — diet restriction labels ("Vegan", "Gluten-Free", etc.).
    public var dietTagsData: Data? = nil
    /// Free-text notes the user adds after cooking a recipe.
    public var notes: String? = nil

    public var keywords: [String] {
        get { (try? JSONDecoder().decode([String].self, from: keywordsData ?? Data())) ?? [] }
        set { keywordsData = try? JSONEncoder().encode(newValue) }
    }

    public var dietTags: [String] {
        get { (try? JSONDecoder().decode([String].self, from: dietTagsData ?? Data())) ?? [] }
        set { dietTagsData = try? JSONEncoder().encode(newValue) }
    }

    /// Best available time string — total if known, else prep+cook sum, else either alone.
    public var displayTime: String? {
        if let t = totalMinutes, t > 0 { return formatMinutes(t) }
        if let p = prepMinutes, let c = cookMinutes, p + c > 0 { return formatMinutes(p + c) }
        if let p = prepMinutes, p > 0 { return formatMinutes(p) }
        if let c = cookMinutes, c > 0 { return formatMinutes(c) }
        return nil
    }

    private func formatMinutes(_ m: Int) -> String {
        guard m > 0 else { return "" }
        if m < 60 { return "\(m) min" }
        let h = m / 60; let r = m % 60
        return r == 0 ? "\(h) hr" : "\(h) hr \(r) min"
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
