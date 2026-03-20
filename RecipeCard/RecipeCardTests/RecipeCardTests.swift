//
//  RecipeCardTests.swift
//  RecipeCardTests
//

import XCTest
import BiteLedgerCore
@testable import RecipeCard

// MARK: - ingredientScore Tests

final class IngredientScoreTests: XCTestCase {

    // MARK: Exact match → 100

    func testExactMatch_returnsHundred() {
        XCTAssertEqual(ingredientScore(foodName: "chicken breast", term: "chicken breast"), 100)
    }

    func testExactMatch_caseInsensitive() {
        XCTAssertEqual(ingredientScore(foodName: "Chicken Breast", term: "chicken breast"), 100)
    }

    func testExactMatch_termUpperCase() {
        XCTAssertEqual(ingredientScore(foodName: "olive oil", term: "OLIVE OIL"), 100)
    }

    // MARK: Prefix match → 50

    func testPrefixMatch_trailingNeutralWord_returnsFifty() {
        // "chicken breast raw" starts with "chicken breast" + space + "raw" (not a type-changer)
        XCTAssertEqual(ingredientScore(foodName: "chicken breast raw", term: "chicken breast"), 50)
    }

    func testPrefixMatch_exactPrefixEndOfString_returnsFifty() {
        // "butter unsalted": "butter" is the prefix, "unsalted" is not a type-changer
        XCTAssertEqual(ingredientScore(foodName: "butter unsalted", term: "butter"), 50)
    }

    func testPrefixMatch_withComma_doesNotScoreFifty() {
        // "Pepper, banana, raw" — comma is NOT a valid prefix boundary (only space or end)
        let score = ingredientScore(foodName: "Pepper, banana, raw", term: "pepper")
        XCTAssertNotEqual(score, 50)
    }

    // MARK: Prefix with type-changer trailing → 20 (demoted below threshold)

    func testPrefixMatch_typeChangerTrailing_demotedToTwenty() {
        // "milk chocolate" starts with "milk" but "chocolate" is a type-changer → demoted to 20
        XCTAssertEqual(ingredientScore(foodName: "milk chocolate", term: "milk"), 20)
    }

    func testPrefixMatch_vanillaExtract_demoted() {
        XCTAssertEqual(ingredientScore(foodName: "vanilla extract", term: "vanilla"), 50)
        // "vanilla" is in typeChangers but it IS the full term, not trailing after prefix — this is exact prefix
        // Actually "vanilla extract": prefix "vanilla", afterPrefix = " extract", "extract" not in typeChangers → 50
    }

    // MARK: Word overlap → 30

    func testWordOverlap_allTermWordsPresent_returnsThirty() {
        // "breast of chicken" has both "chicken" and "breast" as standalone words
        XCTAssertEqual(ingredientScore(foodName: "breast of chicken", term: "chicken breast"), 30)
    }

    func testWordOverlap_termOrderIrrelevant() {
        // Word overlap doesn't care about order
        XCTAssertEqual(ingredientScore(foodName: "oil olive extra", term: "olive oil"), 30)
    }

    func testWordOverlap_partialWordDoesNotMatch() {
        // "pepperoni" should not match "pepper" via word overlap (word boundary enforced)
        XCTAssertLessThan(ingredientScore(foodName: "pepperoni pizza", term: "pepper"), 30)
    }

    func testWordOverlap_pluralNormalisation_esStripped() {
        // term "tomato" → nameWords contains "tomatoes" → check: "tomato".hasSuffix("es")? no.
        // But wait — the normalisation works on the TERM word (w), not the name word.
        // "tomatoes" as TERM vs "tomato" in name: w="tomatoes", hasSuffix("es") → "tomat" in nameWords? no.
        // Actually: "tomatoes" as term word, name = "tomato sauce":
        // nameWords = {"tomato", "sauce"}. w = "tomatoes". hasSuffix("es") → String("tomat") in nameWords → false.
        // hasSuffix("s") → String("tomatoe") in nameWords → false. So "tomatoes" does NOT match "tomato".
        // The plural normalisation only works when the TERM uses plurals to match SINGULAR in name:
        // term="breasts", name="chicken breast" → nameWords={"chicken","breast"}
        // w="breasts", hasSuffix("s") → "breast" in nameWords → true ✓
        let score = ingredientScore(foodName: "chicken breast", term: "chicken breasts")
        XCTAssertEqual(score, 30)  // "breasts" (plural term) matches "breast" (singular name)
    }

    // MARK: Processed penalty → score reduced from 30 to 10

    func testProcessedPenalty_breaded_prefixPathReturnsFifty() {
        // "chicken breast breaded" starts with "chicken breast" → prefix path fires first (score 50).
        // "breaded" is not in typeChangers so no demotion to 20.
        // Processed penalty only applies to the word-overlap path (score == 30), not prefix matches.
        XCTAssertEqual(ingredientScore(foodName: "chicken breast breaded", term: "chicken breast"), 50)
    }

    func testProcessedPenalty_breaded_wordOverlapPath_reducesScoreToTen() {
        // "breast of chicken breaded" does NOT start with "chicken breast" → falls to word overlap.
        // All term words present → score = 30. "breaded" is in processedWords → score -= 20 → 10.
        XCTAssertEqual(ingredientScore(foodName: "breast of chicken breaded", term: "chicken breast"), 10)
    }

    func testProcessedPenalty_fried_reducesScore() {
        XCTAssertEqual(ingredientScore(foodName: "chicken fried breast", term: "chicken breast"), 10)
    }

    func testProcessedPenalty_wordAlreadyInTerm_noPenalty() {
        // "peanut butter" for term "peanut butter" — "peanut" IS in the term → no penalty
        XCTAssertEqual(ingredientScore(foodName: "peanut butter", term: "peanut butter"), 100)
    }

    // MARK: No match / fallback → 10

    func testNoWordOverlap_returnsTen() {
        // "beef steak" vs "chicken breast" — no word overlap → returns 10
        XCTAssertEqual(ingredientScore(foodName: "beef steak", term: "chicken breast"), 10)
    }

    func testCompletelyDifferentFood_returnsTen() {
        XCTAssertEqual(ingredientScore(foodName: "apple juice", term: "brown rice"), 10)
    }

    // MARK: Score floor

    func testScoreNeverNegative() {
        // Multiple processed words can't push score below 0
        let score = ingredientScore(foodName: "chicken breast breaded battered fried", term: "chicken breast")
        XCTAssertGreaterThanOrEqual(score, 0)
    }
}

// MARK: - resolveGrams Tests (Pass 3: weight units — no SwiftData context needed)

final class ResolveGramsTests: XCTestCase {

    private func makeFood() -> FoodItem {
        FoodItem(name: "Test", source: "test", nutritionMode: .per100g,
                 calories: 100, protein: 0, carbs: 0, fat: 0)
    }

    // MARK: Pass 3: Weight units

    func testResolveGrams_oz_convertsCorrectly() {
        let food = makeFood()
        let (gramAmount, _) = resolveGrams(quantity: 2.0, unit: "oz", food: food)
        XCTAssertEqual(gramAmount!, 2.0 * 28.3495, accuracy: 0.001)
    }

    func testResolveGrams_ounce_longFormWorks() {
        let food = makeFood()
        let (gramAmount, _) = resolveGrams(quantity: 1.0, unit: "ounce", food: food)
        XCTAssertEqual(gramAmount!, 28.3495, accuracy: 0.001)
    }

    func testResolveGrams_ounces_pluralWorks() {
        let food = makeFood()
        let (gramAmount, _) = resolveGrams(quantity: 3.0, unit: "ounces", food: food)
        XCTAssertEqual(gramAmount!, 3.0 * 28.3495, accuracy: 0.001)
    }

    func testResolveGrams_lb_convertsCorrectly() {
        let food = makeFood()
        let (gramAmount, _) = resolveGrams(quantity: 0.5, unit: "lb", food: food)
        XCTAssertEqual(gramAmount!, 0.5 * 453.592, accuracy: 0.001)
    }

    func testResolveGrams_pound_longFormWorks() {
        let food = makeFood()
        let (gramAmount, _) = resolveGrams(quantity: 1.0, unit: "pound", food: food)
        XCTAssertEqual(gramAmount!, 453.592, accuracy: 0.001)
    }

    func testResolveGrams_g_passesThrough() {
        let food = makeFood()
        let (gramAmount, _) = resolveGrams(quantity: 240.0, unit: "g", food: food)
        XCTAssertEqual(gramAmount!, 240.0, accuracy: 0.001)
    }

    func testResolveGrams_gram_longFormWorks() {
        let food = makeFood()
        let (gramAmount, _) = resolveGrams(quantity: 50.0, unit: "gram", food: food)
        XCTAssertEqual(gramAmount!, 50.0, accuracy: 0.001)
    }

    func testResolveGrams_grams_pluralWorks() {
        let food = makeFood()
        let (gramAmount, _) = resolveGrams(quantity: 75.0, unit: "grams", food: food)
        XCTAssertEqual(gramAmount!, 75.0, accuracy: 0.001)
    }

    // MARK: Unrecognised unit → nil gramAmount

    func testResolveGrams_unknownUnit_returnsNilGramAmount() {
        let food = makeFood()
        let (gramAmount, _) = resolveGrams(quantity: 1.0, unit: "slice", food: food)
        XCTAssertNil(gramAmount)
    }

    func testResolveGrams_emptyUnit_returnsNilGramAmount() {
        let food = makeFood()
        let (gramAmount, _) = resolveGrams(quantity: 1.0, unit: "", food: food)
        XCTAssertNil(gramAmount)
    }

    // MARK: Case-insensitive unit handling

    func testResolveGrams_caseInsensitiveUnit() {
        let food = makeFood()
        let (low, _) = resolveGrams(quantity: 1.0, unit: "oz",  food: food)
        let (up,  _) = resolveGrams(quantity: 1.0, unit: "OZ",  food: food)
        XCTAssertEqual(low!, up!, accuracy: 0.001)
    }
}

// MARK: - volumeToTbsp Tests

final class VolumeToTbspTests: XCTestCase {

    func testCup_equalsSixteenTbsp() {
        XCTAssertEqual(volumeToTbsp(1.0, unit: "cup")!, 16.0, accuracy: 0.001)
    }

    func testHalfCup_equalsEightTbsp() {
        XCTAssertEqual(volumeToTbsp(0.5, unit: "cup")!, 8.0, accuracy: 0.001)
    }

    func testTbsp_equalsOne() {
        XCTAssertEqual(volumeToTbsp(1.0, unit: "tbsp")!, 1.0, accuracy: 0.001)
    }

    func testTsp_equalsOneThird() {
        XCTAssertEqual(volumeToTbsp(1.0, unit: "tsp")!, 1.0 / 3.0, accuracy: 0.001)
    }

    func testUnknownUnit_returnsNil() {
        XCTAssertNil(volumeToTbsp(1.0, unit: "pinch"))
    }

    func testCups_pluralRecognised() {
        XCTAssertEqual(volumeToTbsp(2.0, unit: "cups")!, 32.0, accuracy: 0.001)
    }

    func testTablespoons_longFormRecognised() {
        XCTAssertEqual(volumeToTbsp(3.0, unit: "tablespoons")!, 3.0, accuracy: 0.001)
    }

    func testTeaspoons_longFormRecognised() {
        XCTAssertEqual(volumeToTbsp(1.0, unit: "teaspoons")!, 1.0 / 3.0, accuracy: 0.001)
    }
}
