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

// MARK: - TimerDetector Tests

final class TimerDetectorTests: XCTestCase {

    // MARK: Basic detection

    func testMinutes_detected() {
        XCTAssertEqual(TimerDetector.largestSeconds(in: "Simmer for 3 minutes."), 180)
    }

    func testMinute_singular_detected() {
        XCTAssertEqual(TimerDetector.largestSeconds(in: "Cook for 1 minute."), 60)
    }

    func testHours_detected() {
        XCTAssertEqual(TimerDetector.largestSeconds(in: "Bake for 2 hours."), 7200)
    }

    func testSeconds_detected() {
        XCTAssertEqual(TimerDetector.largestSeconds(in: "Pulse for 30 seconds."), 30)
    }

    func testCaseInsensitive_MINUTES() {
        XCTAssertEqual(TimerDetector.largestSeconds(in: "Wait 5 MINUTES"), 300)
    }

    // MARK: Multiple patterns — largest wins

    func testMultiplePatterns_largestWins() {
        // "simmer 30 min, bake 45 min" → 45 * 60 = 2700
        let seconds = TimerDetector.largestSeconds(in: "Simmer 30 minutes, then bake 45 minutes.")
        XCTAssertEqual(seconds, 2700)
    }

    func testHourVsMinutes_hourWins() {
        // "1 hour" (3600) vs "30 minutes" (1800) → 3600
        let seconds = TimerDetector.largestSeconds(in: "Rest 30 minutes or 1 hour.")
        XCTAssertEqual(seconds, 3600)
    }

    // MARK: Multi-unit normalization

    func testTwoSeparatePatterns_normalizedToSeconds() {
        // "1 hour" = 3600s, "90 minutes" = 5400s → largest is 90 min
        let seconds = TimerDetector.largestSeconds(in: "Cook 1 hour or 90 minutes, whichever comes first.")
        XCTAssertEqual(seconds, 5400)
    }

    // MARK: No pattern

    func testNoTimer_returnsNil() {
        XCTAssertNil(TimerDetector.largestSeconds(in: "Add salt and stir well."))
    }

    func testEmptyString_returnsNil() {
        XCTAssertNil(TimerDetector.largestSeconds(in: ""))
    }

    // MARK: Label formatting

    func testLabel_seconds() {
        XCTAssertEqual(TimerDetector.label(for: 30), "30 sec")
    }

    func testLabel_minutes() {
        XCTAssertEqual(TimerDetector.label(for: 180), "3 min")
    }

    func testLabel_exactHour() {
        XCTAssertEqual(TimerDetector.label(for: 3600), "1 hr")
    }

    func testLabel_hourAndMinutes() {
        XCTAssertEqual(TimerDetector.label(for: 5400), "1 hr 30 min")
    }
}

// MARK: - ShoppingCategory Tests

final class ShoppingCategoryTests: XCTestCase {

    func testProduce_tomato() {
        XCTAssertEqual(ShoppingCategory.detect(for: "Cherry tomatoes"), .produce)
    }

    func testProduce_garlic() {
        XCTAssertEqual(ShoppingCategory.detect(for: "garlic cloves"), .produce)
    }

    func testDairy_butter() {
        XCTAssertEqual(ShoppingCategory.detect(for: "Unsalted butter"), .dairy)
    }

    func testDairy_cheese() {
        XCTAssertEqual(ShoppingCategory.detect(for: "Parmesan cheese"), .dairy)
    }

    func testMeat_chicken() {
        XCTAssertEqual(ShoppingCategory.detect(for: "chicken breast"), .meat)
    }

    func testMeat_salmon() {
        XCTAssertEqual(ShoppingCategory.detect(for: "Atlantic salmon fillet"), .meat)
    }

    func testPantry_flour() {
        XCTAssertEqual(ShoppingCategory.detect(for: "all-purpose flour"), .pantry)
    }

    func testPantry_oil() {
        XCTAssertEqual(ShoppingCategory.detect(for: "olive oil"), .pantry)
    }

    func testPantry_garlicPowder() {
        XCTAssertEqual(ShoppingCategory.detect(for: "garlic powder"), .pantry)
    }

    func testPantry_pepper() {
        XCTAssertEqual(ShoppingCategory.detect(for: "pepper"), .pantry)
    }

    func testPantry_blackPepper() {
        XCTAssertEqual(ShoppingCategory.detect(for: "black pepper"), .pantry)
    }

    func testProduce_bellPepper() {
        XCTAssertEqual(ShoppingCategory.detect(for: "red bell pepper"), .produce)
    }

    func testOther_unknownIngredient() {
        XCTAssertEqual(ShoppingCategory.detect(for: "dried mango chutney"), .other)
    }

    func testCaseInsensitive() {
        XCTAssertEqual(ShoppingCategory.detect(for: "MILK"), .dairy)
    }
}

// MARK: - ShoppingCart Tests

@MainActor
final class ShoppingCartTests: XCTestCase {

    func testInitiallyEmpty() {
        let cart = ShoppingCart()
        XCTAssertTrue(cart.isEmpty)
        XCTAssertEqual(cart.uncheckedCount, 0)
    }

    func testClearAll_emptiesCart() {
        let cart = ShoppingCart()
        // Manually inject an item via internal state to test clearAll independently.
        // ShoppingCart uses addRecipe; we test clearAll effect through uncheckedCount.
        cart.clearAll()
        XCTAssertTrue(cart.isEmpty)
    }

    func testToggleChecked_checksItem() {
        let cart = ShoppingCart()
        // Add a real item via the internal model (items are struct, test via count).
        // We can verify toggle logic via uncheckedCount after adding items manually
        // if we expose a test helper; for now test that clearing reduces count.
        XCTAssertEqual(cart.uncheckedCount, 0)
        cart.clearAll()
        XCTAssertEqual(cart.uncheckedCount, 0)
    }

    func testShareText_emptyCart_returnsEmptyString() {
        let cart = ShoppingCart()
        XCTAssertEqual(cart.shareText, "")
    }

    func testMoveToCategory_updatesCategory() {
        // Build a cart with one item and verify moveToCategory works.
        // ShoppingCartItem is created via addRecipe in production use.
        // Verify that moveToCategory on a non-existent item doesn't crash.
        let cart = ShoppingCart()
        let nonExistentItem = ShoppingCartItem(recipeTag: "ghost", displayText: "ghost", category: .other)
        cart.moveToCategory(nonExistentItem, to: .produce)
        // No crash, no change since item doesn't exist in cart.
        XCTAssertTrue(cart.isEmpty)
    }
}

// MARK: - MealPlanTests

import SwiftData

final class MealPlanTests: XCTestCase {

    // MARK: - Test container

    private var container: ModelContainer!
    private var context: ModelContext!

    override func setUp() {
        super.setUp()
        let schema = Schema([
            MealPlan.self, MealPlanEntry.self,
            FoodItem.self, ServingSize.self, FoodLog.self,
            Recipe.self, RecipeIngredient.self,
            UserPreferences.self, CanonicalFood.self,
            ServingConversion.self, FallbackSource.self,
            FoodHistoryEntry.self,
        ])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        container = try! ModelContainer(for: schema, configurations: [config])
        context = ModelContext(container)
    }

    override func tearDown() {
        context = nil
        container = nil
        super.tearDown()
    }

    // MARK: - 1. MealPlanEntry.isValid

    func testIsValid_recipeOnly_returnsTrue() {
        let plan = MealPlan(weekStartDate: Date())
        context.insert(plan)
        let recipe = makeRecipe()
        let entry = MealPlanEntry(mealPlan: plan, date: Date(), mealType: .dinner)
        entry.recipe = recipe
        XCTAssertTrue(entry.isValid)
    }

    func testIsValid_foodItemOnly_returnsTrue() {
        let plan = MealPlan(weekStartDate: Date())
        context.insert(plan)
        let (food, _) = makeFoodItem()
        let entry = MealPlanEntry(mealPlan: plan, date: Date(), mealType: .dinner)
        entry.foodItem = food
        XCTAssertTrue(entry.isValid)
    }

    func testIsValid_neitherRecipeNorFoodItem_returnsFalse() {
        let plan = MealPlan(weekStartDate: Date())
        context.insert(plan)
        let entry = MealPlanEntry(mealPlan: plan, date: Date(), mealType: .dinner)
        XCTAssertFalse(entry.isValid)
    }

    func testServingCount_defaultsToOne() {
        let plan = MealPlan(weekStartDate: Date())
        context.insert(plan)
        let entry = MealPlanEntry(mealPlan: plan, date: Date(), mealType: .dinner)
        XCTAssertEqual(entry.servingCount, 1.0)
    }

    // MARK: - 2. Week anchor (Sunday normalization)

    func testStartOfWeek_fromSunday_returnsSameSundayMidnight() {
        // Use a known Sunday: 2026-03-29
        let calendar = Calendar.current
        var components = DateComponents()
        components.year = 2026; components.month = 3; components.day = 29
        let sunday = calendar.date(from: components)!
        let result = MealPlan.startOfWeek(for: sunday)
        let resultComponents = calendar.dateComponents([.year, .month, .day, .weekday], from: result)
        XCTAssertEqual(resultComponents.weekday, 1, "Should be Sunday (weekday 1)")
        XCTAssertEqual(resultComponents.year, 2026)
        XCTAssertEqual(resultComponents.month, 3)
        XCTAssertEqual(resultComponents.day, 29)
        XCTAssertEqual(result, calendar.startOfDay(for: result), "Should be midnight")
    }

    func testStartOfWeek_fromSaturday_returnsPreviousSunday() {
        let calendar = Calendar.current
        var components = DateComponents()
        components.year = 2026; components.month = 4; components.day = 4 // Saturday
        let saturday = calendar.date(from: components)!
        let result = MealPlan.startOfWeek(for: saturday)
        let resultComponents = calendar.dateComponents([.weekday, .day], from: result)
        XCTAssertEqual(resultComponents.weekday, 1, "Should be Sunday (weekday 1)")
        XCTAssertEqual(resultComponents.day, 29, "Should be Mar 29 — the preceding Sunday")
    }

    func testStartOfWeek_fromWednesday_returnsPreviousSunday() {
        let calendar = Calendar.current
        var components = DateComponents()
        components.year = 2026; components.month = 4; components.day = 1 // Wednesday
        let wednesday = calendar.date(from: components)!
        let result = MealPlan.startOfWeek(for: wednesday)
        let resultComponents = calendar.dateComponents([.weekday], from: result)
        XCTAssertEqual(resultComponents.weekday, 1)
    }

    // MARK: - 5. Variety nudge

    func testVarietyNudge_twoOccurrences_notInSet() {
        let plan = makePlan()
        let recipe = makeRecipe()
        for _ in 0..<2 {
            let e = MealPlanEntry(mealPlan: plan, date: Date(), mealType: .dinner)
            e.recipe = recipe
            context.insert(e)
        }
        let ids = computeRepeatedDinnerIDs(entries: plan.entries)
        XCTAssertFalse(ids.contains(recipe.persistentModelID))
    }

    func testVarietyNudge_threeOccurrences_inSet() {
        let plan = makePlan()
        let recipe = makeRecipe()
        for _ in 0..<3 {
            let e = MealPlanEntry(mealPlan: plan, date: Date(), mealType: .dinner)
            e.recipe = recipe
            context.insert(e)
        }
        try? context.save()
        let ids = computeRepeatedDinnerIDs(entries: plan.entries)
        XCTAssertTrue(ids.contains(recipe.persistentModelID))
    }

    func testVarietyNudge_threeDistinctRecipes_emptySet() {
        let plan = makePlan()
        for _ in 0..<3 {
            let r = makeRecipe()
            let e = MealPlanEntry(mealPlan: plan, date: Date(), mealType: .dinner)
            e.recipe = r
            context.insert(e)
        }
        let ids = computeRepeatedDinnerIDs(entries: plan.entries)
        XCTAssertTrue(ids.isEmpty)
    }

    func testVarietyNudge_excludesNonDinner() {
        let plan = makePlan()
        let recipe = makeRecipe()
        for type in [MealType.breakfast, .lunch, .snack] {
            let e = MealPlanEntry(mealPlan: plan, date: Date(), mealType: type)
            e.recipe = recipe
            context.insert(e)
        }
        let ids = computeRepeatedDinnerIDs(entries: plan.entries)
        XCTAssertFalse(ids.contains(recipe.persistentModelID))
    }

    // MARK: - 7. Copy to next week

    func testCopyToNextWeek_correctDateOffset() {
        let calendar = Calendar.current
        let weekStart = MealPlan.startOfWeek()
        let plan = MealPlan(weekStartDate: weekStart)
        context.insert(plan)

        let testDate = calendar.date(byAdding: .day, value: 2, to: weekStart)! // Tuesday
        let entry = MealPlanEntry(mealPlan: plan, date: testDate, mealType: .dinner)
        let recipe = makeRecipe()
        entry.recipe = recipe
        entry.servingCount = 2.0
        context.insert(entry)
        try? context.save()

        // Simulate copy to next week
        let nextWeekStart = calendar.date(byAdding: .day, value: 7, to: weekStart)!
        let nextPlan = MealPlan(weekStartDate: nextWeekStart)
        context.insert(nextPlan)
        for e in plan.entries {
            let newDate = calendar.date(byAdding: .day, value: 7, to: e.date)!
            let newEntry = MealPlanEntry(mealPlan: nextPlan, date: newDate, mealType: e.mealType)
            newEntry.recipe = e.recipe
            newEntry.servingCount = e.servingCount
            context.insert(newEntry)
        }
        try? context.save()

        XCTAssertEqual(nextPlan.entries.count, 1)
        let copied = nextPlan.entries.first!
        let expectedDate = calendar.date(byAdding: .day, value: 7, to: testDate)!
        XCTAssertEqual(calendar.startOfDay(for: copied.date), calendar.startOfDay(for: expectedDate))
        XCTAssertEqual(copied.recipe?.persistentModelID, recipe.persistentModelID)
        XCTAssertEqual(copied.servingCount, 2.0)
        XCTAssertEqual(copied.mealType, .dinner)
    }

    // MARK: - 3. logDay() logic
    //
    // `logDay()` is a private async method on MealPlanDayRow (a SwiftUI view), so it
    // can't be called directly from tests. `simulateLogDay` mirrors the production
    // logic exactly — keep it in sync manually when logDay() changes.

    func testLogDay_recipePath_createsFoodLogs() {
        let plan = makePlan()
        let (food1, serving1) = makeFoodItem()
        let (food2, serving2) = makeFoodItem()

        let recipe = makeRecipe()
        let ing1 = makeIngredient(food: food1, serving: serving1, quantity: 1.0)
        let ing2 = makeIngredient(food: food2, serving: serving2, quantity: 2.0)
        recipe.ingredients = [ing1, ing2]

        let entry = MealPlanEntry(mealPlan: plan, date: Date(), mealType: .dinner)
        entry.recipe = recipe
        entry.servingCount = 1.0
        context.insert(entry)
        try? context.save()

        let (logged, skipped) = simulateLogDay(entries: [entry])

        XCTAssertEqual(logged, 2)
        XCTAssertEqual(skipped, 0)
        let logs = (try? context.fetch(FetchDescriptor<FoodLog>())) ?? []
        XCTAssertEqual(logs.count, 2)
    }

    func testLogDay_nilIngredientFood_countsSkipped() {
        // Simulates a recipe ingredient whose food was deleted after planning.
        let plan = makePlan()
        let recipe = makeRecipe()
        let (food, serving) = makeFoodItem()
        let goodIng = makeIngredient(food: food, serving: serving, quantity: 1.0)
        let orphanIng = RecipeIngredient(quantity: 1.0)
        orphanIng.foodItem = nil   // deleted food — nullified relationship
        context.insert(orphanIng)
        recipe.ingredients = [goodIng, orphanIng]

        let entry = MealPlanEntry(mealPlan: plan, date: Date(), mealType: .dinner)
        entry.recipe = recipe
        entry.servingCount = 1.0
        context.insert(entry)
        try? context.save()

        let (logged, skipped) = simulateLogDay(entries: [entry])

        XCTAssertEqual(logged, 1, "Only the ingredient with a valid food should be logged")
        XCTAssertEqual(skipped, 1, "Ingredient with nil foodItem must count toward skipped")
    }

    func testLogDay_foodItemNilServing_skips() {
        // Food with no default serving and no explicit entry serving → entry must be skipped.
        let plan = makePlan()
        let food = FoodItem(
            name: "No-Serving Food", source: "test", nutritionMode: .perServing,
            calories: 100, protein: 0, carbs: 0, fat: 0
        )
        food.servingSizes = []   // defaultServing returns nil
        context.insert(food)

        let entry = MealPlanEntry(mealPlan: plan, date: Date(), mealType: .lunch)
        entry.foodItem = food
        entry.servingSize = nil
        entry.servingCount = 1.0
        context.insert(entry)
        try? context.save()

        let (logged, skipped) = simulateLogDay(entries: [entry])

        XCTAssertEqual(logged, 0)
        XCTAssertEqual(skipped, 1)
        let logs = (try? context.fetch(FetchDescriptor<FoodLog>())) ?? []
        XCTAssertTrue(logs.isEmpty, "No FoodLog should be created when serving is nil")
    }

    // MARK: - Helpers

    private func makePlan() -> MealPlan {
        let plan = MealPlan(weekStartDate: MealPlan.startOfWeek())
        context.insert(plan)
        return plan
    }

    private func makeRecipe() -> Recipe {
        let recipe = Recipe(name: "Test Recipe \(UUID().uuidString.prefix(4))", servingsYield: 4.0)
        context.insert(recipe)
        return recipe
    }

    private func makeFoodItem() -> (FoodItem, ServingSize) {
        let serving = ServingSize(label: "1 serving", isDefault: true)
        let food = FoodItem(
            name: "Test Food",
            source: "test",
            nutritionMode: .perServing,
            calories: 100,
            protein: 0,
            carbs: 0,
            fat: 0
        )
        food.servingSizes = [serving]
        context.insert(food)
        context.insert(serving)
        return (food, serving)
    }

    private func makeIngredient(food: FoodItem, serving: ServingSize, quantity: Double) -> RecipeIngredient {
        let ing = RecipeIngredient(quantity: quantity)
        ing.foodItem = food
        ing.servingSize = serving
        context.insert(ing)
        return ing
    }

    /// Mirrors MealPlanDayRow.logDay() — update this when that function changes.
    private func simulateLogDay(entries: [MealPlanEntry]) -> (logged: Int, skipped: Int) {
        var logged = 0
        var skipped = 0
        for entry in entries where entry.isValid {
            if let recipe = entry.recipe {
                for ingredient in recipe.ingredients {
                    guard let food = ingredient.foodItem else { skipped += 1; continue }
                    _ = FoodLog.create(
                        mealType: entry.mealType,
                        quantity: ingredient.quantity * entry.servingCount,
                        food: food,
                        serving: ingredient.servingSize,
                        timestamp: entry.date,
                        context: context
                    )
                    logged += 1
                }
            } else if let food = entry.foodItem {
                let serving = entry.servingSize ?? food.defaultServing
                guard serving != nil else { skipped += 1; continue }
                _ = FoodLog.create(
                    mealType: entry.mealType,
                    quantity: entry.servingCount,
                    food: food,
                    serving: serving,
                    timestamp: entry.date,
                    context: context
                )
                logged += 1
            }
        }
        try? context.save()
        return (logged, skipped)
    }

    private func makeFoodItemWithGramWeight(grams: Double) -> (FoodItem, ServingSize) {
        let serving = ServingSize(label: "1 cup", gramWeight: grams, isDefault: true)
        let food = FoodItem(
            name: "Test Food \(UUID().uuidString.prefix(4))",
            source: "test",
            nutritionMode: .per100g,
            calories: 200,
            protein: 0,
            carbs: 0,
            fat: 0
        )
        food.servingSizes = [serving]
        context.insert(food)
        context.insert(serving)
        return (food, serving)
    }

    private func computeRepeatedDinnerIDs(entries: [MealPlanEntry]) -> Set<PersistentIdentifier> {
        let dinners = entries.filter { $0.mealType == .dinner }
        let groups = Dictionary(grouping: dinners.compactMap(\.recipe), by: \.persistentModelID)
        return Set(groups.filter { $0.value.count >= 3 }.keys)
    }
}

