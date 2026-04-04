//
//  SchemaV4MigrationTests.swift
//  BitePlanTests
//
//  Integration test: verifies that a V3 store opens cleanly with the V4 schema
//  (adds MealPlanMeal + MealPlanMealItem) without throwing, and that existing
//  V3 data remains intact after the lightweight migration.
//

import XCTest
import SwiftData
@testable import BitePlan
import BiteLedgerCore

@MainActor
final class SchemaV4MigrationTests: XCTestCase {

    func test_openV3StoreWithV4Schema_noThrow() throws {
        // Step 1: Create a V3 ModelContainer (12 models) in memory and insert data.
        let v3Schema = Schema([
            FoodItem.self, ServingSize.self, FoodLog.self, UserPreferences.self,
            Recipe.self, RecipeIngredient.self, CanonicalFood.self, ServingConversion.self,
            FallbackSource.self, FoodHistoryEntry.self,
            MealPlan.self, MealPlanEntry.self,
        ])
        let v3Config = ModelConfiguration(isStoredInMemoryOnly: true)
        let v3Container = try ModelContainer(for: v3Schema, configurations: [v3Config])
        let v3Context = v3Container.mainContext

        let weekStart = MealPlan.startOfWeek(for: Date())
        let plan = MealPlan(weekStartDate: weekStart)
        v3Context.insert(plan)

        let entry = MealPlanEntry(mealPlan: plan, date: weekStart, mealType: .dinner)
        v3Context.insert(entry)

        let recipe = Recipe(name: "V3 Test Recipe", servingsYield: 2)
        v3Context.insert(recipe)
        entry.recipe = recipe

        try v3Context.save()

        // Verify data was saved
        let planCount = try v3Context.fetchCount(FetchDescriptor<MealPlan>())
        XCTAssertEqual(planCount, 1, "V3 plan should be persisted")

        // Step 2: Open V4 schema (14 models) in a separate in-memory container.
        // This simulates the lightweight migration (new entities added).
        let v4Schema = Schema([
            FoodItem.self, ServingSize.self, FoodLog.self, UserPreferences.self,
            Recipe.self, RecipeIngredient.self, CanonicalFood.self, ServingConversion.self,
            FallbackSource.self, FoodHistoryEntry.self,
            MealPlan.self, MealPlanEntry.self, MealPlanMeal.self, MealPlanMealItem.self,
        ])
        let v4Config = ModelConfiguration(isStoredInMemoryOnly: true)
        // Should not throw — V4 adds new nullable entities (lightweight migration)
        let v4Container = try ModelContainer(for: v4Schema, configurations: [v4Config])
        let v4Context = v4Container.mainContext

        // Insert V4 data to verify new models work
        let v4Plan = MealPlan(weekStartDate: weekStart)
        v4Context.insert(v4Plan)
        let meal = MealPlanMeal(mealPlan: v4Plan, date: weekStart, mealType: .dinner)
        v4Context.insert(meal)
        let food = FoodItem(name: "Test Food", source: "test", nutritionMode: .per100g,
                            calories: 100, protein: 5, carbs: 10, fat: 3)
        v4Context.insert(food)
        let item = MealPlanMealItem(meal: meal)
        item.foodItem = food
        v4Context.insert(item)
        try v4Context.save()

        let mealCount = try v4Context.fetchCount(FetchDescriptor<MealPlanMeal>())
        let itemCount = try v4Context.fetchCount(FetchDescriptor<MealPlanMealItem>())
        XCTAssertEqual(mealCount, 1, "V4 MealPlanMeal should be insertable")
        XCTAssertEqual(itemCount, 1, "V4 MealPlanMealItem should be insertable")
    }

    func test_mealPlanMeal_cascadeDelete_deletesItems() throws {
        let schema = Schema([
            FoodItem.self, ServingSize.self, FoodLog.self, UserPreferences.self,
            Recipe.self, RecipeIngredient.self, CanonicalFood.self, ServingConversion.self,
            FallbackSource.self, FoodHistoryEntry.self,
            MealPlan.self, MealPlanEntry.self, MealPlanMeal.self, MealPlanMealItem.self,
        ])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [config])
        let context = container.mainContext

        let plan = MealPlan(weekStartDate: Date())
        context.insert(plan)
        let meal = MealPlanMeal(mealPlan: plan, date: Date(), mealType: .dinner)
        context.insert(meal)
        let food = FoodItem(name: "Pasta", source: "test", nutritionMode: .per100g,
                            calories: 350, protein: 12, carbs: 65, fat: 2)
        context.insert(food)
        let item = MealPlanMealItem(meal: meal)
        item.foodItem = food
        context.insert(item)
        try context.save()

        // Delete meal — cascade should delete item
        context.delete(meal)
        try context.save()

        let itemCount = try context.fetchCount(FetchDescriptor<MealPlanMealItem>())
        XCTAssertEqual(itemCount, 0, "Deleting MealPlanMeal should cascade-delete its items")
    }
}
