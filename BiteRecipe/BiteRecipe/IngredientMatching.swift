//
//  IngredientMatching.swift
//  BiteRecipe
//
//  Extracted from RecipeImportReviewView so these pure functions are
//  accessible from unit tests via @testable import BiteRecipe.
//

import Foundation
import BiteLedgerCore

// MARK: - Gram Resolution

/// Resolves a recipe ingredient's quantity+unit to a gram amount using the matched food's servings.
/// Returns (gramAmount, bestServing) — gramAmount is nil when the unit is unrecognised.
///
/// Pass 1: exact unit match against a food serving (e.g. recipe "cup" → serving "1 cup = 112g")
/// Pass 2: cross-unit volume via tbsp equivalents (e.g. "1/2 cup" → "1 tbsp = 14.2g")
/// Pass 3: weight unit constants (oz, lb, g)
func resolveGrams(
    quantity: Double, unit: String, food: FoodItem
) -> (gramAmount: Double?, serving: ServingSize?) {
    let parsedUnit = unit.lowercased()
    guard !parsedUnit.isEmpty else { return (nil, food.defaultServing) }

    // Pass 1: exact unit match
    if let unitServing = food.servingSizes.first(where: {
        let u = $0.unit ?? ServingSizeParser.parseUnit($0.label)?.abbreviation ?? ""
        return u.lowercased() == parsedUnit
    }), let gw = unitServing.gramWeight, unitServing.amount > 0 {
        return ((quantity / unitServing.amount) * gw, unitServing)
    }

    // Pass 2: cross-unit volume conversion
    if let parsedTbsp = volumeToTbsp(quantity, unit: parsedUnit) {
        for serving in food.servingSizes {
            guard let gw = serving.gramWeight, gw > 0, serving.amount > 0 else { continue }
            let servUnitStr = serving.unit
                ?? ServingSizeParser.parseUnit(serving.label)?.abbreviation
                ?? ""
            if let servTbsp = volumeToTbsp(serving.amount, unit: servUnitStr.lowercased()),
               servTbsp > 0 {
                return (parsedTbsp * (gw / servTbsp), serving)
            }
        }
    }

    // Pass 3: weight units
    switch parsedUnit {
    case "oz", "ounce", "ounces":        return (quantity * 28.3495, food.defaultServing)
    case "lb", "lbs", "pound", "pounds": return (quantity * 453.592, food.defaultServing)
    case "g", "gram", "grams":           return (quantity,            food.defaultServing)
    default:                              return (nil,                 food.defaultServing)
    }
}

// MARK: - Volume Unit Conversion

/// Converts a volume amount+unit to tablespoon equivalents, or nil if not a volume unit.
/// Used for cross-unit gram estimation (e.g. "1/2 cup" → 8 tbsp, then × grams/tbsp).
func volumeToTbsp(_ amount: Double, unit: String) -> Double? {
    switch unit.lowercased() {
    case "cup", "cups":                             return amount * 16
    case "tbsp", "tablespoon", "tablespoons":       return amount * 1
    case "tsp", "teaspoon", "teaspoons":            return amount * (1.0 / 3.0)
    case "fl oz", "fl_oz", "fluid oz", "floz":     return amount * 2
    case "ml", "milliliter", "milliliters":         return amount * (1.0 / 14.7868)
    default: return nil
    }
}

// MARK: - Relevance Scoring

/// Returns a relevance score for how well `foodName` matches `term`.
/// Uses word-boundary checks so "pepper" never matches "pepperoni".
///
/// 100 — exact match
///  50 — food name starts with term, followed by word boundary (space or end)
///  30 — every word in term appears as a whole word in the food name
///  10 — raw substring match (kept for completeness; callers threshold at 30)
///   0 — no match
func ingredientScore(foodName: String, term: String) -> Int {
    let name    = foodName.lowercased()
    let termLow = term.lowercased()
    if name == termLow { return 100 }

    // Words that fundamentally change what the food is — "milk chocolate" is not "milk",
    // "brown sugar" is not the same as plain "sugar" in most contexts.
    let typeChangers: Set<String> = [
        "chocolate","dark","white","vanilla","strawberry","caramel","maple",
        "lemon","lime","orange","cherry","blueberry","raspberry","mocha","mint",
        "peanut","almond","coconut","butterscotch","hazelnut","brown","golden",
        "flavored","flavoured","infused","sweetened","spiced"
    ]

    // Prefix must be followed by a word boundary (space or end-of-string only, not comma —
    // "Pepper, banana, raw" must NOT score 50 for term "pepper")
    if name.hasPrefix(termLow) {
        let afterPrefix = name.dropFirst(termLow.count)
        if afterPrefix.isEmpty || afterPrefix.first == " " {
            // If the trailing words change the food type, demote below the 30 threshold
            let trailingWords = afterPrefix.trimmingCharacters(in: .whitespaces)
                .components(separatedBy: .whitespaces).filter { !$0.isEmpty }
            if trailingWords.contains(where: { typeChangers.contains($0) }) {
                return 20   // below 30 threshold → treated as no match
            }
            return 50
        }
    }

    // Every word in the search term must appear as a standalone word in the food name.
    // Simple plural normalisation: "breasts" matches "breast", "tomatoes" matches "tomato", etc.
    let sep = CharacterSet.whitespaces.union(.punctuationCharacters)
    let nameWords = Set(name.components(separatedBy: sep).filter { !$0.isEmpty })
    let termWords =      termLow.components(separatedBy: sep).filter { !$0.isEmpty }

    func wordMatches(_ w: String) -> Bool {
        if nameWords.contains(w) { return true }
        // strip trailing 's' or 'es' for basic plurals
        if w.hasSuffix("es"), nameWords.contains(String(w.dropLast(2))) { return true }
        if w.hasSuffix("s"),  nameWords.contains(String(w.dropLast(1))) { return true }
        return false
    }

    var score = 0
    if !termWords.isEmpty, termWords.allSatisfy({ wordMatches($0) }) { score = 30 }

    if score == 0 { return 10 }

    // Penalise processed/flavoured products so raw/plain foods win, e.g.
    // "Chicken breast tenders, breaded" or "Tri-Color Rotini Product with Dried Vegetables".
    // Also penalise type-changer words that appear in the food name but NOT in the search term
    // (so "brown sugar" loses to "granulated sugar" when term is "sugar").
    let processedWords: Set<String> = [
        "breaded","battered","fried","tenders","nuggets","strips","patty","patties",
        "canned","stewed","flavored","flavoured","product","seasoned","prepared",
        "tri-color","tri","multicolor"
    ]
    let penaltyWords = processedWords.union(typeChangers)
    let termWordSet  = Set(termWords)
    let foodWordArr  = name.components(separatedBy: sep).filter { !$0.isEmpty }
    // Only penalise for words that aren't already in the search term
    // ("peanut butter" for term "peanut butter" should NOT penalise "peanut")
    if foodWordArr.contains(where: { penaltyWords.contains($0) && !termWordSet.contains($0) }) {
        score -= 20
    }

    return max(0, score)
}
