//
//  ShoppingCart.swift
//  BitePlan
//

import Foundation
import Observation
import BiteLedgerCore

// MARK: - ShoppingCategory

enum ShoppingCategory: String, CaseIterable, Identifiable, Codable {
    case produce = "Produce"
    case dairy   = "Dairy"
    case meat    = "Meat"
    case pantry  = "Pantry"
    case other   = "Other"

    var id: String { rawValue }

    // Keyword match on ingredient display label (case-insensitive).
    // Specific compound terms are checked before broad single-word lists to
    // prevent "garlic" matching "garlic powder" as produce, etc.
    static func detect(for name: String) -> ShoppingCategory {
        let lower = name.lowercased()

        // Specific overrides — most specific first, before broad keyword lists.
        let specificProduce = ["bell pepper","red pepper","green pepper","yellow pepper",
                               "garlic clove","fresh garlic","hot pepper","jalapeño"]
        let specificPantry  = ["garlic powder","onion powder","chili powder","baking powder",
                               "baking soda","black pepper","white pepper","ground pepper",
                               "cayenne","paprika","cumin","coriander","cinnamon","nutmeg",
                               "oregano","thyme","italian seasoning","crushed red pepper"]

        for kw in specificProduce { if lower.contains(kw) { return .produce } }
        for kw in specificPantry  { if lower.contains(kw) { return .pantry  } }

        // Broad single-word lists. "pepper" moved to pantry; "bell pepper" caught above.
        let produce = ["apple","avocado","basil","broccoli","carrot","celery","cilantro",
                       "garlic","ginger","kale","lemon","lettuce","lime","onion","parsley",
                       "potato","spinach","tomato","zucchini"]
        let dairy   = ["butter","cheese","cream","egg","milk","yogurt"]
        let meat    = ["bacon","beef","chicken","fish","lamb","pork","salmon","sausage",
                       "shrimp","steak","tuna","turkey"]
        let pantry  = ["flour","oil","pasta","pepper","powder","rice","salt","sauce",
                       "spice","sugar","vinegar"]

        for kw in produce { if lower.contains(kw) { return .produce } }
        for kw in dairy   { if lower.contains(kw) { return .dairy   } }
        for kw in meat    { if lower.contains(kw) { return .meat    } }
        for kw in pantry  { if lower.contains(kw) { return .pantry  } }
        return .other
    }
}

// MARK: - ShoppingCartItem

struct ShoppingCartItem: Identifiable, Codable {
    let id: UUID
    /// Tags this item to its source recipe (for replace-on-re-add).
    let recipeTag: String
    /// Human-readable display text, e.g. "1.5 cups flour".
    var displayText: String
    var category: ShoppingCategory
    var isChecked: Bool

    init(recipeTag: String, displayText: String, category: ShoppingCategory) {
        self.id = UUID()
        self.recipeTag = recipeTag
        self.displayText = displayText
        self.category = category
        self.isChecked = false
    }
}

// MARK: - ShoppingCart

/// Persistent shopping list backed by UserDefaults.
/// Survives app restarts. Injected as a SwiftUI environment value from BitePlanApp.
@Observable
final class ShoppingCart {

    private static let defaultsKey = "ShoppingCart.items"

    private(set) var items: [ShoppingCartItem] = [] {
        didSet { save() }
    }

    init() {
        load()
    }

    /// Count of unchecked items — drives the tab badge.
    var uncheckedCount: Int { items.filter { !$0.isChecked }.count }

    var isEmpty: Bool { items.isEmpty }

    // MARK: Mutations

    /// Add or replace all ingredients from a recipe at the given scale factor.
    /// Re-tapping the same recipe at any scale wipes previous entries and inserts fresh ones.
    func addRecipe(_ recipe: Recipe, scaleFactor: Double) {
        let tag = recipe.id.uuidString
        items.removeAll { $0.recipeTag == tag }

        for ing in recipe.sortedIngredients {
            let text = scaledDisplayText(for: ing, scaleFactor: scaleFactor)
            let category = ShoppingCategory.detect(for: ing.displayLabel)
            items.append(ShoppingCartItem(recipeTag: tag, displayText: text, category: category))
        }
    }

    func toggleChecked(_ item: ShoppingCartItem) {
        guard let idx = items.firstIndex(where: { $0.id == item.id }) else { return }
        items[idx].isChecked.toggle()
    }

    func removeItem(_ item: ShoppingCartItem) {
        items.removeAll { $0.id == item.id }
    }

    func moveToCategory(_ item: ShoppingCartItem, to category: ShoppingCategory) {
        guard let idx = items.firstIndex(where: { $0.id == item.id }) else { return }
        items[idx].category = category
    }

    func clearAll() {
        items.removeAll()
    }

    /// Replaces all cart items with ingredients derived from the given meal plan meals (SchemaV4).
    ///
    /// Algorithm:
    /// - Recipe items: iterate ingredients, scale by item.servingCount.
    ///   If the ingredient has a gram weight, accumulate into a per-food-item gram total
    ///   (same food from multiple items is summed). If no gram weight, list separately.
    /// - FoodItem items: add directly with qty = servingCount.
    ///   If servingSize has a gram weight, accumulate into the gram total.
    /// - Note-only items (isNoteOnly == true) are skipped (no food to buy).
    /// - Invalid items (isValid == false) are skipped silently.
    /// - Orphaned items (meal == nil) are skipped.
    ///
    /// ObjectIdentifier is used as the dedup key — stable within a synchronous call on
    /// a single ModelContext (SwiftData guarantees one in-memory instance per persistent record).
    ///
    /// All generated items are tagged recipeTag = "meal_plan".
    func populateFromMealPlan(meals: [MealPlanMeal]) {
        items.removeAll()

        var gramAccumulator: [ObjectIdentifier: (FoodItem, Double)] = [:]
        var noGramItems: [ShoppingCartItem] = []

        for meal in meals {
            for item in meal.items where item.isValid {
                guard item.meal != nil else { continue }  // orphan guard
                if item.isNoteOnly { continue }           // notes have nothing to buy

                if let recipe = item.recipe {
                    for ingredient in recipe.sortedIngredients {
                        guard let food = ingredient.foodItem else { continue }
                        let scaledQty = ingredient.quantity * item.servingCount
                        let servingGrams = ingredient.servingSize?.gramWeight ?? food.defaultServing?.gramWeight
                        if let gw = servingGrams, gw > 0 {
                            let key = ObjectIdentifier(food)
                            gramAccumulator[key] = (food, (gramAccumulator[key]?.1 ?? 0) + gw * scaledQty)
                        } else {
                            let text = scaledDisplayText(for: ingredient, scaleFactor: item.servingCount)
                            noGramItems.append(ShoppingCartItem(
                                recipeTag: "meal_plan",
                                displayText: text,
                                category: ShoppingCategory.detect(for: food.name)
                            ))
                        }
                    }
                } else if let food = item.foodItem {
                    if let serving = item.servingSize, let gw = serving.gramWeight, gw > 0 {
                        let key = ObjectIdentifier(food)
                        gramAccumulator[key] = (food, (gramAccumulator[key]?.1 ?? 0) + gw * item.servingCount)
                    } else {
                        let qty = item.servingCount.truncatingRemainder(dividingBy: 1) == 0
                            ? String(Int(item.servingCount))
                            : String(format: "%.1g", item.servingCount)
                        let label = item.servingSize?.label ?? "serving"
                        noGramItems.append(ShoppingCartItem(
                            recipeTag: "meal_plan",
                            displayText: "\(qty) \(label) \(food.name)",
                            category: ShoppingCategory.detect(for: food.name)
                        ))
                    }
                }
            }
        }

        let mergedItems = gramAccumulator.values.map { food, grams -> ShoppingCartItem in
            ShoppingCartItem(
                recipeTag: "meal_plan",
                displayText: "\(Int(grams.rounded()))g \(food.name)",
                category: ShoppingCategory.detect(for: food.name)
            )
        }
        items = mergedItems + noGramItems
    }

    // MARK: Persistence

    private func save() {
        guard let data = try? JSONEncoder().encode(items) else { return }
        UserDefaults.standard.set(data, forKey: Self.defaultsKey)
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: Self.defaultsKey),
              let saved = try? JSONDecoder().decode([ShoppingCartItem].self, from: data) else { return }
        items = saved
    }

    // MARK: Sharing

    /// Plain-text checklist formatted for sharing via iOS ShareLink.
    var shareText: String {
        var lines: [String] = []
        for cat in ShoppingCategory.allCases {
            let unchecked = items.filter { $0.category == cat && !$0.isChecked }
            guard !unchecked.isEmpty else { continue }
            lines.append("--- \(cat.rawValue) ---")
            lines.append(contentsOf: unchecked.map { "[ ] \($0.displayText)" })
        }
        return lines.joined(separator: "\n")
    }

    // MARK: Private helpers

    private func scaledDisplayText(for ing: RecipeIngredient, scaleFactor: Double) -> String {
        guard let qty = ing.recipeQuantity,
              let unit = ing.recipeUnit, !unit.isEmpty else {
            return ing.displayLabel
        }

        let scaled = qty * scaleFactor
        let qtyStr = scaled.truncatingRemainder(dividingBy: 1) == 0
            ? String(Int(scaled))
            : String(format: "%.2g", scaled)

        // Build the ingredient name without any quantity prefix.
        // Prefer the matched food item name (clean, no quantity baked in).
        // Fall back to stripping the leading quantity+unit from rawText.
        let name: String
        if let food = ing.foodItem {
            name = food.name
        } else if let raw = ing.rawText {
            name = Self.stripLeadingQuantity(from: raw)
        } else {
            // Manual ingredient — displayLabel is name+serving, no qty prefix.
            return ing.displayLabel
        }

        return "\(qtyStr) \(unit) \(name)"
    }

    /// Strips a leading quantity expression (e.g. "1/4 tsp ", "2 ", "1 1/2 cups ")
    /// from a raw ingredient string so only the ingredient name remains.
    private static func stripLeadingQuantity(from text: String) -> String {
        // Matches: optional mixed number (e.g. "1 1/2"), or decimal/integer, then optional unit word.
        // Examples stripped: "1/4 tsp ", "2 tbsp ", "1 1/2 cups ", "8oz "
        let pattern = #"^\s*(?:\d+\s+)?\d+(?:[./]\d+)?\s*(?:[a-zA-Z]+\.?\s+)?"#
        if let range = text.range(of: pattern, options: .regularExpression) {
            let stripped = String(text[range.upperBound...])
            return stripped.isEmpty ? text : stripped
        }
        return text
    }
}
