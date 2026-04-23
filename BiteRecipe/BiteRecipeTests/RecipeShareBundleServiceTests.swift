//
//  RecipeShareBundleServiceTests.swift
//  BiteRecipeTests
//
//  Round-trip tests for RecipeShareBundleService: create a .biterecipe ZIP bundle
//  from fixture data, parse it back, import it into an in-memory store, and verify
//  all fields survive the round-trip.
//

import XCTest
import SwiftData
@testable import BiteRecipe
import BiteLedgerCore

@MainActor
final class RecipeShareBundleServiceTests: XCTestCase {

    // MARK: - Helpers

    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([
            FoodItem.self, ServingSize.self, FoodLog.self, UserPreferences.self,
            Recipe.self, RecipeIngredient.self, CanonicalFood.self, ServingConversion.self,
            FallbackSource.self, FoodHistoryEntry.self, MealPlan.self, MealPlanEntry.self,
            MealPlanMeal.self, MealPlanMealItem.self,
        ])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: [config])
    }

    /// Inserts a Recipe with two ingredients (one per100g USDA seed, one custom perServing).
    /// Returns (container, recipe) — container must stay in scope for the duration of the test.
    private func makeFixtureRecipe(in context: ModelContext) -> Recipe {
        // Food 1: USDA seed, per100g
        let food1 = FoodItem(
            name: "Chicken Breast",
            source: "usda_seed_v4",
            nutritionMode: .per100g,
            calories: 165, protein: 31, carbs: 0, fat: 3.6,
            sodium: 74
        )
        let serving1 = ServingSize(label: "3 oz", gramWeight: 85, isDefault: true,
                                   sortOrder: 0, unit: "oz", amount: 3)
        food1.servingSizes.append(serving1)
        context.insert(food1)

        // Food 2: Custom, perServing
        let food2 = FoodItem(
            name: "Homemade Sauce",
            source: "manual",
            nutritionMode: .perServing,
            calories: 45, protein: 1, carbs: 8, fat: 1.5
        )
        let serving2 = ServingSize(label: "2 tbsp", isDefault: true,
                                   sortOrder: 0, unit: "tbsp", amount: 2)
        food2.servingSizes.append(serving2)
        context.insert(food2)

        // Recipe
        let recipe = Recipe(name: "Test Chicken", servingsYield: 4,
                            sourceURL: "https://example.com/chicken",
                            directions: ["Season chicken.", "Cook 20 min."])
        recipe.recipeCategory = "Main Dish"
        recipe.recipeCuisine  = "American"
        recipe.author         = "Test Chef"
        recipe.prepMinutes    = 10
        recipe.cookMinutes    = 20
        recipe.keywords       = ["chicken", "easy"]
        context.insert(recipe)

        let ing1 = RecipeIngredient(quantity: 2, sortOrder: 0, recipeQuantity: 6, recipeUnit: "oz")
        ing1.rawText   = "6 oz chicken breast"
        ing1.recipe    = recipe
        ing1.foodItem  = food1
        ing1.servingSize = serving1
        context.insert(ing1)
        recipe.ingredients.append(ing1)

        let ing2 = RecipeIngredient(quantity: 1, sortOrder: 1)
        ing2.rawText   = "2 tbsp homemade sauce"
        ing2.recipe    = recipe
        ing2.foodItem  = food2
        ing2.servingSize = serving2
        context.insert(ing2)
        recipe.ingredients.append(ing2)

        return recipe
    }

    private func cleanupURL(_ url: URL?) {
        guard let url else { return }
        try? FileManager.default.removeItem(at: url)
    }

    // MARK: - Tests

    func test_createBundle_roundTrip_noImage() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let recipe = makeFixtureRecipe(in: ctx)

        let archiveURL = try RecipeShareBundleService.createBundle(
            recipe: recipe, context: ctx, imageData: nil
        )
        defer { cleanupURL(archiveURL) }

        XCTAssertTrue(FileManager.default.fileExists(atPath: archiveURL.path))
        XCTAssertEqual(archiveURL.pathExtension, "biterecipe")

        let bundle = try RecipeShareBundleService.parseBundle(at: archiveURL)

        // Manifest
        XCTAssertEqual(bundle.manifest.schemaVersion, 1)
        XCTAssertFalse(bundle.manifest.exportDate.isEmpty)

        // Recipe fields
        XCTAssertEqual(bundle.recipe.name, "Test Chicken")
        XCTAssertEqual(bundle.recipe.servingsYield, 4)
        XCTAssertEqual(bundle.recipe.sourceURL, "https://example.com/chicken")
        XCTAssertEqual(bundle.recipe.directions, ["Season chicken.", "Cook 20 min."])
        XCTAssertEqual(bundle.recipe.recipeCategory, "Main Dish")
        XCTAssertEqual(bundle.recipe.recipeCuisine, "American")
        XCTAssertEqual(bundle.recipe.author, "Test Chef")
        XCTAssertEqual(bundle.recipe.prepMinutes, 10)
        XCTAssertEqual(bundle.recipe.cookMinutes, 20)
        XCTAssertEqual(bundle.recipe.keywords, ["chicken", "easy"])

        // Both foods present
        XCTAssertEqual(bundle.foods.count, 2)
        let foodNames = Set(bundle.foods.map { $0.name })
        XCTAssertEqual(foodNames, ["Chicken Breast", "Homemade Sauce"])

        // Both ingredients
        XCTAssertEqual(bundle.ingredients.count, 2)
        let sortedIngs = bundle.ingredients.sorted { $0.sortOrder < $1.sortOrder }
        XCTAssertEqual(sortedIngs[0].rawText, "6 oz chicken breast")
        XCTAssertEqual(sortedIngs[1].rawText, "2 tbsp homemade sauce")

        // Servings
        XCTAssertEqual(bundle.servings.count, 2)

        // No image
        XCTAssertFalse(bundle.hasImage)
        XCTAssertNil(RecipeShareBundleService.extractImageData(from: archiveURL))
    }

    func test_createBundle_withImage_roundTrip() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let recipe = makeFixtureRecipe(in: ctx)

        // Create a minimal valid JPEG (1×1 pixel)
        let tinyJPEG = makeTinyJPEG()
        XCTAssertFalse(tinyJPEG.isEmpty)

        let archiveURL = try RecipeShareBundleService.createBundle(
            recipe: recipe, context: ctx, imageData: tinyJPEG
        )
        defer { cleanupURL(archiveURL) }

        let bundle = try RecipeShareBundleService.parseBundle(at: archiveURL)
        XCTAssertTrue(bundle.hasImage)

        let extracted = RecipeShareBundleService.extractImageData(from: archiveURL)
        XCTAssertNotNil(extracted)
        XCTAssertEqual(extracted, tinyJPEG)
    }

    func test_importBundle_createsRecipe() throws {
        let senderContainer = try makeContainer()
        let senderCtx = senderContainer.mainContext
        let senderRecipe = makeFixtureRecipe(in: senderCtx)

        let archiveURL = try RecipeShareBundleService.createBundle(
            recipe: senderRecipe, context: senderCtx, imageData: nil
        )
        defer { cleanupURL(archiveURL) }

        // Import into a fresh empty store (simulates receiver)
        let receiverContainer = try makeContainer()
        let receiverCtx = receiverContainer.mainContext

        let bundle = try RecipeShareBundleService.parseBundle(at: archiveURL)
        let imported = try RecipeShareBundleService.importBundle(
            bundle, imageData: nil, into: receiverCtx
        )

        XCTAssertEqual(imported.name, "Test Chicken")
        XCTAssertEqual(imported.servingsYield, 4)
        XCTAssertEqual(imported.sortedIngredients.count, 2)
        XCTAssertEqual(imported.sortedIngredients[0].rawText, "6 oz chicken breast")
        XCTAssertNotNil(imported.sortedIngredients[0].foodItem)
        XCTAssertEqual(imported.sortedIngredients[0].foodItem?.name, "Chicken Breast")
        XCTAssertNotNil(imported.sortedIngredients[0].servingSize)
        XCTAssertEqual(imported.sortedIngredients[0].servingSize?.label, "3 oz")
    }

    func test_importBundle_dedupesExistingFood() throws {
        let container = try makeContainer()
        let ctx = container.mainContext

        // Pre-seed the "Chicken Breast" food in receiver's store
        let existingFood = FoodItem(
            name: "Chicken Breast",
            source: "usda_seed_v4",
            nutritionMode: .per100g,
            calories: 165, protein: 31, carbs: 0, fat: 3.6
        )
        ctx.insert(existingFood)

        // Build bundle in a separate sender store
        let senderContainer = try makeContainer()
        let senderCtx = senderContainer.mainContext
        let senderRecipe = makeFixtureRecipe(in: senderCtx)
        let archiveURL = try RecipeShareBundleService.createBundle(
            recipe: senderRecipe, context: senderCtx, imageData: nil
        )
        defer { cleanupURL(archiveURL) }

        let bundle = try RecipeShareBundleService.parseBundle(at: archiveURL)
        _ = try RecipeShareBundleService.importBundle(bundle, imageData: nil, into: ctx)

        // Should not have created a duplicate "Chicken Breast" food
        let allFoods = try ctx.fetch(FetchDescriptor<FoodItem>())
        let chickenCount = allFoods.filter { $0.name == "Chicken Breast" }.count
        XCTAssertEqual(chickenCount, 1, "Expected exactly 1 Chicken Breast; got \(chickenCount)")
    }

    func test_findDuplicate_byName() throws {
        let container = try makeContainer()
        let ctx = container.mainContext

        let existing = Recipe(name: "Test Chicken", servingsYield: 2)
        ctx.insert(existing)

        let senderContainer = try makeContainer()
        let senderCtx = senderContainer.mainContext
        let senderRecipe = makeFixtureRecipe(in: senderCtx)
        let archiveURL = try RecipeShareBundleService.createBundle(
            recipe: senderRecipe, context: senderCtx, imageData: nil
        )
        defer { cleanupURL(archiveURL) }

        let bundle = try RecipeShareBundleService.parseBundle(at: archiveURL)
        let dup = try RecipeShareBundleService.findDuplicate(for: bundle, in: ctx)
        XCTAssertNotNil(dup)
        XCTAssertEqual(dup?.name, "Test Chicken")
    }

    func test_findDuplicate_bySourceURL() throws {
        let container = try makeContainer()
        let ctx = container.mainContext

        // Different name, same source URL
        let existing = Recipe(name: "Completely Different Name", servingsYield: 2,
                              sourceURL: "https://example.com/chicken")
        ctx.insert(existing)

        let senderContainer = try makeContainer()
        let senderCtx = senderContainer.mainContext
        let senderRecipe = makeFixtureRecipe(in: senderCtx)
        let archiveURL = try RecipeShareBundleService.createBundle(
            recipe: senderRecipe, context: senderCtx, imageData: nil
        )
        defer { cleanupURL(archiveURL) }

        let bundle = try RecipeShareBundleService.parseBundle(at: archiveURL)
        let dup = try RecipeShareBundleService.findDuplicate(for: bundle, in: ctx)
        XCTAssertNotNil(dup)
    }

    func test_findDuplicate_noMatch() throws {
        let container = try makeContainer()
        let ctx = container.mainContext

        let existing = Recipe(name: "Completely Unrelated Recipe", servingsYield: 2)
        ctx.insert(existing)

        let senderContainer = try makeContainer()
        let senderCtx = senderContainer.mainContext
        let senderRecipe = makeFixtureRecipe(in: senderCtx)
        let archiveURL = try RecipeShareBundleService.createBundle(
            recipe: senderRecipe, context: senderCtx, imageData: nil
        )
        defer { cleanupURL(archiveURL) }

        let bundle = try RecipeShareBundleService.parseBundle(at: archiveURL)
        let dup = try RecipeShareBundleService.findDuplicate(for: bundle, in: ctx)
        XCTAssertNil(dup)
    }

    func test_parseBundle_corruptData_throws() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("corrupt-\(UUID().uuidString).biterecipe")
        try Data("not a zip archive at all".utf8).write(to: url)
        defer { cleanupURL(url) }

        XCTAssertThrowsError(try RecipeShareBundleService.parseBundle(at: url)) { error in
            XCTAssertTrue(error is RecipeShareBundleError)
        }
    }

    func test_parseBundle_schemaVersionTooHigh_throws() throws {
        // Build a valid archive but with schemaVersion = 99
        let tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("BRShareTest_\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        let encoder = JSONEncoder()
        let manifest = RecipeShareBundle.Manifest(schemaVersion: 99,
                                                   exportDate: "2026-01-01T00:00:00Z",
                                                   senderAppVersion: "9.9")
        try encoder.encode(manifest).write(to: tmpDir.appendingPathComponent("manifest.json"))
        let emptyArray = try encoder.encode([String]())
        try emptyArray.write(to: tmpDir.appendingPathComponent("ingredients.json"))
        try emptyArray.write(to: tmpDir.appendingPathComponent("foods.json"))
        try emptyArray.write(to: tmpDir.appendingPathComponent("servings.json"))

        // Minimal recipe.json
        let rDTO = RecipeShareBundle.RecipeDTO(name: "x", servingsYield: 1, sourceURL: nil,
            directions: [], prepMinutes: nil, cookMinutes: nil, totalMinutes: nil,
            recipeDescription: nil, recipeCategory: nil, recipeCuisine: nil, author: nil,
            ratingValue: nil, ratingCount: nil, keywords: [], dietTags: [], imageURL: nil)
        try encoder.encode(rDTO).write(to: tmpDir.appendingPathComponent("recipe.json"))

        // Create archive using ZIPFoundation the same way RecipeShareBundleService does
        let archiveURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("test-v99-\(UUID().uuidString).biterecipe")
        defer { cleanupURL(archiveURL) }

        let archive = try ZIPFoundation.Archive(url: archiveURL, accessMode: .create)
        let enumerator = FileManager.default.enumerator(
            at: tmpDir, includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        )
        while let fileURL = enumerator?.nextObject() as? URL {
            guard let rv = try? fileURL.resourceValues(forKeys: [.isRegularFileKey]),
                  rv.isRegularFile == true else { continue }
            let relativePath = String(fileURL.path.dropFirst(tmpDir.path.count + 1))
            try archive.addEntry(with: relativePath, fileURL: fileURL)
        }

        XCTAssertThrowsError(try RecipeShareBundleService.parseBundle(at: archiveURL)) { error in
            guard case RecipeShareBundleError.unsupportedSchemaVersion(99) = error else {
                XCTFail("Expected unsupportedSchemaVersion(99), got \(error)")
                return
            }
        }
    }

    func test_importBundle_replace_deletesOldRecipe() throws {
        let container = try makeContainer()
        let ctx = container.mainContext

        let oldRecipe = Recipe(name: "Test Chicken", servingsYield: 1)
        ctx.insert(oldRecipe)

        let senderContainer = try makeContainer()
        let senderCtx = senderContainer.mainContext
        let senderRecipe = makeFixtureRecipe(in: senderCtx)
        let archiveURL = try RecipeShareBundleService.createBundle(
            recipe: senderRecipe, context: senderCtx, imageData: nil
        )
        defer { cleanupURL(archiveURL) }

        let bundle = try RecipeShareBundleService.parseBundle(at: archiveURL)
        let imported = try RecipeShareBundleService.importBundle(
            bundle, imageData: nil, into: ctx, replacing: oldRecipe
        )

        let allRecipes = try ctx.fetch(FetchDescriptor<Recipe>())
        XCTAssertEqual(allRecipes.count, 1)
        XCTAssertEqual(allRecipes[0].id, imported.id)
        XCTAssertEqual(imported.servingsYield, 4)   // new value, not old 1
    }

    // MARK: - Test Utilities

    /// Makes a minimal 1×1 JPEG suitable for testing image round-trips.
    private func makeTinyJPEG() -> Data {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 1, height: 1))
        let image = renderer.image { ctx in
            UIColor.red.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: 1, height: 1))
        }
        return image.jpegData(compressionQuality: 0.5) ?? Data()
    }
}

// Needed to reference ZIPFoundation.Archive in the schema-version test
import ZIPFoundation
