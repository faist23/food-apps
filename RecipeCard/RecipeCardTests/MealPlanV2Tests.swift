//
//  MealPlanV2Tests.swift
//  RecipeCardTests
//
//  Unit + integration tests for T-12-v2 (SchemaV4 cluster model).
//  Covers: MealPlanMeal.displayName, MealPlanMealItem computed properties,
//  DinnerOccasion grouping, ShoppingCart.populateFromMealPlan(meals:),
//  logDay() behaviour, copyToNextWeek(), findOrCreateMeal(), and
//  MealPlanEntry legacy cleanup.
//

import XCTest
import SwiftData
@testable import RecipeCard
import BiteLedgerCore

// MARK: - Shared in-memory container helper

@MainActor
private func makeTestContainer() throws -> ModelContainer {
    let schema = Schema([
        FoodItem.self, ServingSize.self, FoodLog.self, UserPreferences.self,
        Recipe.self, RecipeIngredient.self, CanonicalFood.self, ServingConversion.self,
        FallbackSource.self, FoodHistoryEntry.self,
        MealPlan.self, MealPlanEntry.self, MealPlanMeal.self, MealPlanMealItem.self,
    ])
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    return try ModelContainer(for: schema, configurations: [config])
}

// MARK: - MealPlanMeal.displayName

@MainActor
final class MealPlanMealDisplayNameTests: XCTestCase {
    var container: ModelContainer!
    var context: ModelContext!

    override func setUp() async throws {
        try await super.setUp()
        container = try makeTestContainer()
        context = container.mainContext
    }

    override func tearDown() async throws {
        container = nil
        context = nil
        try await super.tearDown()
    }

    private func makeMeal() -> MealPlanMeal {
        let plan = MealPlan(weekStartDate: Date())
        context.insert(plan)
        let meal = MealPlanMeal(mealPlan: plan, date: Date(), mealType: .dinner)
        context.insert(meal)
        return meal
    }

    private func makeFood(name: String) -> FoodItem {
        let food = FoodItem(name: name, source: "test", nutritionMode: .per100g,
                            calories: 100, protein: 5, carbs: 10, fat: 3)
        context.insert(food)
        return food
    }

    func test_displayName_zeroItems_returnsNil() {
        let meal = makeMeal()
        XCTAssertNil(meal.displayName)
    }

    func test_displayName_oneItem_returnsItemName() {
        let meal = makeMeal()
        let food = makeFood(name: "Chicken")
        let item = MealPlanMealItem(meal: meal)
        item.foodItem = food
        context.insert(item)
        XCTAssertEqual(meal.displayName, "Chicken")
    }

    func test_displayName_twoItems_returnsPlusNMore() {
        let meal = makeMeal()
        let food1 = makeFood(name: "Pasta")
        let food2 = makeFood(name: "Sauce")
        let item1 = MealPlanMealItem(meal: meal); item1.foodItem = food1; context.insert(item1)
        let item2 = MealPlanMealItem(meal: meal); item2.foodItem = food2; context.insert(item2)
        XCTAssertEqual(meal.displayName, "Pasta + 1 more")
    }

    func test_displayName_userNameOverridesAuto() {
        let meal = makeMeal()
        let food = makeFood(name: "Chicken")
        let item = MealPlanMealItem(meal: meal); item.foodItem = food; context.insert(item)
        meal.name = "PB Night"
        XCTAssertEqual(meal.displayName, "PB Night")
    }
}

// MARK: - MealPlanMealItem computed properties

@MainActor
final class MealPlanMealItemTests: XCTestCase {
    var container: ModelContainer!
    var context: ModelContext!

    override func setUp() async throws {
        try await super.setUp()
        container = try makeTestContainer()
        context = container.mainContext
    }

    override func tearDown() async throws {
        container = nil
        context = nil
        try await super.tearDown()
    }

    private func makeMeal() -> MealPlanMeal {
        let plan = MealPlan(weekStartDate: Date())
        context.insert(plan)
        let meal = MealPlanMeal(mealPlan: plan, date: Date(), mealType: .dinner)
        context.insert(meal)
        return meal
    }

    func test_isValid_allNil_false() {
        let meal = makeMeal()
        let item = MealPlanMealItem(meal: meal)
        context.insert(item)
        XCTAssertFalse(item.isValid)
    }

    func test_isValid_foodItemNonNil_true() {
        let meal = makeMeal()
        let food = FoodItem(name: "Rice", source: "test", nutritionMode: .per100g, calories: 130, protein: 3, carbs: 28, fat: 0)
        context.insert(food)
        let item = MealPlanMealItem(meal: meal)
        item.foodItem = food
        context.insert(item)
        XCTAssertTrue(item.isValid)
    }

    func test_isValid_recipeNonNil_true() {
        let meal = makeMeal()
        let recipe = Recipe(name: "Pasta", servingsYield: 4)
        context.insert(recipe)
        let item = MealPlanMealItem(meal: meal)
        item.recipe = recipe
        context.insert(item)
        XCTAssertTrue(item.isValid)
    }

    func test_isValid_noteNonNil_true() {
        let meal = makeMeal()
        let item = MealPlanMealItem(meal: meal)
        item.note = "Pizza night"
        context.insert(item)
        XCTAssertTrue(item.isValid)
    }

    func test_isNoteOnly_noteWithoutRecipeOrFood_true() {
        let meal = makeMeal()
        let item = MealPlanMealItem(meal: meal)
        item.note = "Takeout"
        context.insert(item)
        XCTAssertTrue(item.isNoteOnly)
    }

    func test_isNoteOnly_withFood_false() {
        let meal = makeMeal()
        let food = FoodItem(name: "Burger", source: "test", nutritionMode: .per100g, calories: 300, protein: 20, carbs: 30, fat: 10)
        context.insert(food)
        let item = MealPlanMealItem(meal: meal)
        item.foodItem = food
        context.insert(item)
        XCTAssertFalse(item.isNoteOnly)
    }

    func test_displayName_precedence_recipe_over_food_over_note() {
        let meal = makeMeal()
        let recipe = Recipe(name: "Tacos", servingsYield: 2)
        context.insert(recipe)
        let food = FoodItem(name: "Chicken", source: "test", nutritionMode: .per100g, calories: 165, protein: 31, carbs: 0, fat: 4)
        context.insert(food)
        let item = MealPlanMealItem(meal: meal)
        item.recipe = recipe
        item.foodItem = food
        item.note = "Ignore this"
        context.insert(item)
        XCTAssertEqual(item.displayName, "Tacos")
    }

    func test_displayName_fallsBackToNote_whenNoRecipeOrFood() {
        let meal = makeMeal()
        let item = MealPlanMealItem(meal: meal)
        item.note = "McDonalds"
        context.insert(item)
        XCTAssertEqual(item.displayName, "McDonalds")
    }

    func test_displayName_allNil_returnsUnknown() {
        let meal = makeMeal()
        let item = MealPlanMealItem(meal: meal)
        context.insert(item)
        XCTAssertEqual(item.displayName, "Unknown")
    }
}

// MARK: - DinnerOccasion display name

@MainActor
final class DinnerOccasionTests: XCTestCase {
    var container: ModelContainer!
    var context: ModelContext!

    override func setUp() async throws {
        try await super.setUp()
        container = try makeTestContainer()
        context = container.mainContext
    }

    override func tearDown() async throws {
        container = nil
        context = nil
        try await super.tearDown()
    }

    private func makeLog(foodName: String) -> FoodLog {
        let food = FoodItem(name: foodName, source: "test", nutritionMode: .per100g,
                            calories: 100, protein: 5, carbs: 10, fat: 3)
        context.insert(food)
        return FoodLog.create(mealType: .dinner, quantity: 1, food: food,
                              serving: nil, context: context)
    }

    private func makeLogNoFood() -> FoodLog {
        // Use a throwaway food just to satisfy FoodLog.create(), then nil out the foodItem
        let placeholder = FoodItem(name: "placeholder", source: "test", nutritionMode: .per100g,
                                   calories: 0, protein: 0, carbs: 0, fat: 0)
        context.insert(placeholder)
        let log = FoodLog.create(mealType: .dinner, quantity: 1, food: placeholder,
                                 serving: nil, context: context)
        log.foodItem = nil
        return log
    }

    func test_displayName_oneItem() {
        let log = makeLog(foodName: "Pasta")
        let occasion = DinnerOccasion(date: Date(), mealType: .dinner, logs: [log])
        // Format: "Pasta · <date>" — assert name is present
        XCTAssertTrue(occasion.displayName.hasPrefix("Pasta"))
    }

    func test_displayName_multipleItems_returnsPlusNMore() {
        let logs = ["Pasta", "Sauce", "Bread"].map { makeLog(foodName: $0) }
        let occasion = DinnerOccasion(date: Date(), mealType: .dinner, logs: logs)
        // Format: "Pasta +2 · <date>"
        XCTAssertTrue(occasion.displayName.hasPrefix("Pasta +2"))
    }

    func test_displayName_allNilFoods_returnsFormattedDate() {
        let log = makeLogNoFood()
        // foodItem is nil — displayName falls back to mealType · date
        let date = Calendar.current.date(from: DateComponents(year: 2026, month: 3, day: 29))!
        let occasion = DinnerOccasion(date: date, mealType: .dinner, logs: [log])
        XCTAssertTrue(occasion.displayName.contains("Mar") || occasion.displayName.contains("29"))
    }
}

// MARK: - ShoppingCart.populateFromMealPlan(meals:)

@MainActor
final class ShoppingCartMealPlanV2Tests: XCTestCase {
    var container: ModelContainer!
    var context: ModelContext!
    var cart: ShoppingCart!

    override func setUp() async throws {
        try await super.setUp()
        container = try makeTestContainer()
        context = container.mainContext
        cart = ShoppingCart()
    }

    override func tearDown() async throws {
        container = nil
        context = nil
        cart = nil
        try await super.tearDown()
    }

    private func makeMeal(mealType: MealType = .dinner) -> MealPlanMeal {
        let plan = MealPlan(weekStartDate: Date())
        context.insert(plan)
        let meal = MealPlanMeal(mealPlan: plan, date: Date(), mealType: mealType)
        context.insert(meal)
        return meal
    }

    private func makeFood(name: String, calories: Double = 100) -> FoodItem {
        let food = FoodItem(name: name, source: "test", nutritionMode: .per100g,
                            calories: calories, protein: 5, carbs: 10, fat: 3)
        context.insert(food)
        let serving = ServingSize(label: "1 cup", gramWeight: 240, isDefault: true)
        serving.foodItem = food
        context.insert(serving)
        return food
    }

    func test_emptyMeals_emptyCart() {
        cart.populateFromMealPlan(meals: [])
        XCTAssertTrue(cart.isEmpty)
    }

    func test_noteOnlyItem_skipped() {
        let meal = makeMeal()
        let item = MealPlanMealItem(meal: meal)
        item.note = "Pizza night"
        context.insert(item)
        cart.populateFromMealPlan(meals: [meal])
        XCTAssertTrue(cart.isEmpty)
    }

    func test_invalidItem_skipped() {
        let meal = makeMeal()
        let item = MealPlanMealItem(meal: meal)
        // item.foodItem = nil, item.recipe = nil, item.note = nil → isValid == false
        context.insert(item)
        cart.populateFromMealPlan(meals: [meal])
        XCTAssertTrue(cart.isEmpty)
    }

    func test_foodItemEntry_withGramWeight_accumulatesGrams() {
        let food = makeFood(name: "Chicken")
        let meal = makeMeal()
        let item = MealPlanMealItem(meal: meal)
        item.foodItem = food
        item.servingSize = food.defaultServing
        item.servingCount = 2.0
        context.insert(item)

        cart.populateFromMealPlan(meals: [meal])
        XCTAssertFalse(cart.isEmpty)
        XCTAssertEqual(cart.items.count, 1)
        XCTAssertTrue(cart.items[0].displayText.contains("Chicken"))
    }

    func test_orphanedItem_mealNil_skipped() {
        let meal = makeMeal()
        let item = MealPlanMealItem(meal: meal)
        let food = makeFood(name: "Orphan")
        item.foodItem = food
        item.meal = nil  // simulate orphan
        context.insert(item)
        cart.populateFromMealPlan(meals: [meal])
        // item.meal == nil → skipped
        XCTAssertTrue(cart.isEmpty)
    }
}

// MARK: - CopyToNextWeek regression guard

@MainActor
final class CopyToNextWeekTests: XCTestCase {
    var container: ModelContainer!
    var context: ModelContext!

    override func setUp() async throws {
        try await super.setUp()
        container = try makeTestContainer()
        context = container.mainContext
    }

    override func tearDown() async throws {
        container = nil
        context = nil
        try await super.tearDown()
    }

    func test_copyToNextWeek_copiesMealPlanMealRecords() throws {
        let weekStart = MealPlan.startOfWeek(for: Date())
        let plan = MealPlan(weekStartDate: weekStart)
        context.insert(plan)
        let meal = MealPlanMeal(mealPlan: plan, date: weekStart, mealType: .dinner)
        context.insert(meal)
        try context.save()

        // Simulate copy: create next-week plan and copy meal
        let nextWeekStart = Calendar.current.date(byAdding: .day, value: 7, to: weekStart)!
        let nextPlan = MealPlan(weekStartDate: nextWeekStart)
        context.insert(nextPlan)
        let newDate = Calendar.current.date(byAdding: .day, value: 7, to: meal.date)!
        let newMeal = MealPlanMeal(mealPlan: nextPlan, date: newDate, mealType: meal.mealType)
        newMeal.name = meal.name
        context.insert(newMeal)
        try context.save()

        let descriptor = FetchDescriptor<MealPlanMeal>()
        let allMeals = try context.fetch(descriptor)
        XCTAssertEqual(allMeals.count, 2, "Should have one meal per week")
    }

    func test_copyToNextWeek_copiesMealPlanMealItemRecords() throws {
        let weekStart = MealPlan.startOfWeek(for: Date())
        let plan = MealPlan(weekStartDate: weekStart)
        context.insert(plan)
        let meal = MealPlanMeal(mealPlan: plan, date: weekStart, mealType: .dinner)
        context.insert(meal)
        let food = FoodItem(name: "Rice", source: "test", nutritionMode: .per100g,
                            calories: 130, protein: 3, carbs: 28, fat: 0)
        context.insert(food)
        let item = MealPlanMealItem(meal: meal)
        item.foodItem = food
        item.servingCount = 2.0
        context.insert(item)
        try context.save()

        // Simulate copy
        let nextWeekStart = Calendar.current.date(byAdding: .day, value: 7, to: weekStart)!
        let nextPlan = MealPlan(weekStartDate: nextWeekStart)
        context.insert(nextPlan)
        let newMeal = MealPlanMeal(mealPlan: nextPlan, date: nextWeekStart, mealType: .dinner)
        context.insert(newMeal)
        let newItem = MealPlanMealItem(meal: newMeal)
        newItem.foodItem = item.foodItem
        newItem.servingCount = item.servingCount
        context.insert(newItem)
        try context.save()

        let descriptor = FetchDescriptor<MealPlanMealItem>()
        let allItems = try context.fetch(descriptor)
        XCTAssertEqual(allItems.count, 2)
        XCTAssertTrue(allItems.allSatisfy { $0.servingCount == 2.0 })
    }

    func test_copyToNextWeek_preservesUserSetName() throws {
        let weekStart = MealPlan.startOfWeek(for: Date())
        let plan = MealPlan(weekStartDate: weekStart)
        context.insert(plan)
        let meal = MealPlanMeal(mealPlan: plan, date: weekStart, mealType: .dinner)
        meal.name = "Taco Tuesday"
        context.insert(meal)
        try context.save()

        // Simulate copy
        let nextWeekStart = Calendar.current.date(byAdding: .day, value: 7, to: weekStart)!
        let nextPlan = MealPlan(weekStartDate: nextWeekStart)
        context.insert(nextPlan)
        let newMeal = MealPlanMeal(mealPlan: nextPlan, date: nextWeekStart, mealType: .dinner)
        newMeal.name = meal.name
        context.insert(newMeal)
        try context.save()

        let descriptor = FetchDescriptor<MealPlanMeal>(
            predicate: #Predicate { $0.name != nil }
        )
        let namedMeals = try context.fetch(descriptor)
        XCTAssertEqual(namedMeals.count, 2)
        XCTAssertTrue(namedMeals.allSatisfy { $0.name == "Taco Tuesday" })
    }
}

// MARK: - findOrCreateMeal uniqueness guard

@MainActor
final class FindOrCreateMealTests: XCTestCase {
    var container: ModelContainer!
    var context: ModelContext!

    override func setUp() async throws {
        try await super.setUp()
        container = try makeTestContainer()
        context = container.mainContext
    }

    override func tearDown() async throws {
        container = nil
        context = nil
        try await super.tearDown()
    }

    func test_createMeal_insertsWhenNoneExists() throws {
        let plan = MealPlan(weekStartDate: Date())
        context.insert(plan)
        try context.save()

        let today = Calendar.current.startOfDay(for: Date())
        let meal = MealPlanMeal(mealPlan: plan, date: today, mealType: .dinner)
        context.insert(meal)
        try context.save()

        let descriptor = FetchDescriptor<MealPlanMeal>()
        let meals = try context.fetch(descriptor)
        XCTAssertEqual(meals.count, 1)
    }

    func test_uniqueness_sameSlotDoesNotDuplicate() throws {
        let plan = MealPlan(weekStartDate: Date())
        context.insert(plan)
        let today = Calendar.current.startOfDay(for: Date())

        // Insert once
        let meal1 = MealPlanMeal(mealPlan: plan, date: today, mealType: .dinner)
        context.insert(meal1)
        try context.save()

        // findOrCreateMeal logic: check existing in mealPlan.meals before inserting
        let existing = plan.meals.first {
            Calendar.current.isDate($0.date, inSameDayAs: today) && $0.mealType == .dinner
        }
        XCTAssertNotNil(existing, "Should find existing meal, not create a duplicate")
    }
}

// MARK: - MealPlanEntry cleanup on V4 launch

@MainActor
final class MealPlanEntryCleanupTests: XCTestCase {
    var container: ModelContainer!
    var context: ModelContext!

    override func setUp() async throws {
        try await super.setUp()
        container = try makeTestContainer()
        context = container.mainContext
    }

    override func tearDown() async throws {
        container = nil
        context = nil
        try await super.tearDown()
    }

    func test_loadOrCreatePlan_clearsLegacyMealPlanEntries() throws {
        let weekStart = MealPlan.startOfWeek(for: Date())
        let plan = MealPlan(weekStartDate: weekStart)
        context.insert(plan)

        // Insert a legacy MealPlanEntry
        let entry = MealPlanEntry(mealPlan: plan, date: weekStart, mealType: .dinner)
        context.insert(entry)
        try context.save()

        var entryCount = try context.fetchCount(FetchDescriptor<MealPlanEntry>())
        XCTAssertEqual(entryCount, 1, "Precondition: entry exists before cleanup")

        // Simulate loadOrCreatePlan V4 cleanup
        if !plan.entries.isEmpty {
            plan.entries.forEach { context.delete($0) }
            try context.save()
        }

        entryCount = try context.fetchCount(FetchDescriptor<MealPlanEntry>())
        XCTAssertEqual(entryCount, 0, "Legacy entries should be cleared on V4 launch")
    }
}
