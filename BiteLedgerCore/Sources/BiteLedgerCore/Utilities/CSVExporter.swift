//
//  CSVExporter.swift
//  BiteLedger
//
//  Created by Craig Faist on 2/27/26.
//


import Foundation
import SwiftData

// MARK: - CSVExporter
//
// Exports BiteLedger data as CSV files for full round-trip restore.
// foods.csv → servings.csv → logs.csv → recipes.csv → ingredients.csv
// → meal_plans.csv → meal_meals.csv → meal_items.csv  (SchemaV5, T-12-RestoreUpdate)
//
// Design guarantee: export → delete app → import produces identical data.
//
// JSON array fields (directions, keywords, dietTags, importedNutrition) are stored
// as base64-encoded JSON data to keep the CSV single-line and unambiguous.

public struct CSVExporter {

    // MARK: - Export Package

    public struct ExportPackage: Sendable {
        public let foodsCSV: String
        public let servingsCSV: String
        public let logsCSV: String
        public let recipesCSV: String
        public let ingredientsCSV: String
        // Meal plan CSVs (SchemaV5 — T-12-RestoreUpdate)
        public let mealPlansCSV: String
        public let mealMealsCSV: String
        public let mealItemsCSV: String
        /// Local recipe images: (filename e.g. "{uuid}.jpg", jpeg data).
        /// Only populated for recipes whose imageURL starts with "file://".
        /// Remote https:// images are not included — AsyncImage re-fetches them.
        public let recipeImages: [(filename: String, data: Data)]
        public let exportDate: Date

        /// Suggested filename prefix
        public var filePrefix: String {
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd"
            return "BiteLedger_\(formatter.string(from: exportDate))"
        }
    }

    // MARK: - Full Export

    /// Exports all data for a full round-trip backup.
    @MainActor
    public static func exportAll(context: ModelContext) throws -> ExportPackage {
        let foods       = try context.fetch(FetchDescriptor<FoodItem>())
        let servings    = try context.fetch(FetchDescriptor<ServingSize>())
        let logs        = try context.fetch(FetchDescriptor<FoodLog>())
        let recipes     = try context.fetch(FetchDescriptor<Recipe>())
        let ingredients = try context.fetch(FetchDescriptor<RecipeIngredient>())
        let mealPlans   = try context.fetch(FetchDescriptor<MealPlan>())
        let mealMeals   = try context.fetch(FetchDescriptor<MealPlanMeal>())
        let mealItems   = try context.fetch(FetchDescriptor<MealPlanMealItem>())

        // Collect local recipe images as (filename, jpegData) pairs.
        // Filename is "{recipeId}.jpg" so the importer can match by UUID.
        var recipeImages: [(filename: String, data: Data)] = []
        for recipe in recipes {
            guard let urlString = recipe.imageURL,
                  urlString.hasPrefix("file://"),
                  let url = URL(string: urlString),
                  let data = try? Data(contentsOf: url)
            else { continue }
            recipeImages.append(("\(recipe.id.uuidString).jpg", data))
        }

        return ExportPackage(
            foodsCSV:       exportFoods(foods),
            servingsCSV:    exportServings(servings),
            logsCSV:        exportLogs(logs),
            recipesCSV:     exportRecipes(recipes),
            ingredientsCSV: exportIngredients(ingredients),
            mealPlansCSV:   exportMealPlans(mealPlans),
            mealMealsCSV:   exportMealMeals(mealMeals),
            mealItemsCSV:   exportMealItems(mealItems),
            recipeImages:   recipeImages,
            exportDate:     Date()
        )
    }

    // MARK: - Foods CSV

    public static func exportFoods(_ foods: [FoodItem]) -> String {
        let headers = [
            "id", "name", "brand", "barcode", "source", "dateAdded",
            "nutritionMode",
            "calories", "protein", "carbs", "fat",
            "fiber", "sugar", "saturatedFat", "transFat",
            "polyunsaturatedFat", "monounsaturatedFat",
            "sodium", "cholesterol", "potassium", "calcium", "iron",
            "magnesium", "zinc",
            "vitaminA", "vitaminC", "vitaminD", "vitaminE", "vitaminK",
            "vitaminB6", "vitaminB12", "folate", "choline", "caffeine"
        ]

        var rows: [[String]] = [headers]

        for food in foods {
            let row: [String] = [
                food.id.uuidString,
                food.name,
                food.brand ?? "",
                food.barcode ?? "",
                food.source,
                ISO8601DateFormatter().string(from: food.dateAdded),
                food.nutritionMode.rawValue,
                String(food.calories),
                String(food.protein),
                String(food.carbs),
                String(food.fat),
                optStr(food.fiber),
                optStr(food.sugar),
                optStr(food.saturatedFat),
                optStr(food.transFat),
                optStr(food.polyunsaturatedFat),
                optStr(food.monounsaturatedFat),
                optStr(food.sodium),
                optStr(food.cholesterol),
                optStr(food.potassium),
                optStr(food.calcium),
                optStr(food.iron),
                optStr(food.magnesium),
                optStr(food.zinc),
                optStr(food.vitaminA),
                optStr(food.vitaminC),
                optStr(food.vitaminD),
                optStr(food.vitaminE),
                optStr(food.vitaminK),
                optStr(food.vitaminB6),
                optStr(food.vitaminB12),
                optStr(food.folate),
                optStr(food.choline),
                optStr(food.caffeine)
            ]
            rows.append(row)
        }

        return csvString(rows)
    }

    // MARK: - Servings CSV

    public static func exportServings(_ servings: [ServingSize]) -> String {
        let headers = ["id", "foodId", "label", "gramWeight", "isDefault", "sortOrder", "dateAdded", "unit"]
        var rows: [[String]] = [headers]

        for serving in servings {
            guard let foodId = serving.foodItem?.id else { continue }
            let row: [String] = [
                serving.id.uuidString,
                foodId.uuidString,
                serving.label,
                optStr(serving.gramWeight),
                String(serving.isDefault),
                String(serving.sortOrder),
                ISO8601DateFormatter().string(from: serving.dateAdded),
                serving.unit ?? ""
            ]
            rows.append(row)
        }

        return csvString(rows)
    }

    // MARK: - Logs CSV

    public static func exportLogs(_ logs: [FoodLog]) -> String {
        let headers = [
            "id", "foodId", "servingId", "timestamp", "mealType", "quantity",
            "caloriesAtLogTime", "proteinAtLogTime", "carbsAtLogTime", "fatAtLogTime",
            "fiberAtLogTime", "sodiumAtLogTime", "sugarAtLogTime", "saturatedFatAtLogTime",
            "transFatAtLogTime", "monounsaturatedFatAtLogTime", "polyunsaturatedFatAtLogTime",
            "cholesterolAtLogTime", "potassiumAtLogTime", "calciumAtLogTime", "ironAtLogTime",
            "magnesiumAtLogTime", "zincAtLogTime",
            "vitaminAAtLogTime", "vitaminCAtLogTime", "vitaminDAtLogTime",
            "vitaminEAtLogTime", "vitaminKAtLogTime",
            "vitaminB6AtLogTime", "vitaminB12AtLogTime",
            "folateAtLogTime", "cholineAtLogTime", "caffeineAtLogTime"
        ]
        var rows: [[String]] = [headers]

        let iso = ISO8601DateFormatter()

        for log in logs {
            guard let foodId = log.foodItem?.id else { continue }
            let row: [String] = [
                log.id.uuidString,
                foodId.uuidString,
                log.servingSize?.id.uuidString ?? "",
                iso.string(from: log.timestamp),
                log.mealType.rawValue,
                String(log.quantity),
                String(log.caloriesAtLogTime),
                String(log.proteinAtLogTime),
                String(log.carbsAtLogTime),
                String(log.fatAtLogTime),
                optStr(log.fiberAtLogTime),
                optStr(log.sodiumAtLogTime),
                optStr(log.sugarAtLogTime),
                optStr(log.saturatedFatAtLogTime),
                optStr(log.transFatAtLogTime),
                optStr(log.monounsaturatedFatAtLogTime),
                optStr(log.polyunsaturatedFatAtLogTime),
                optStr(log.cholesterolAtLogTime),
                optStr(log.potassiumAtLogTime),
                optStr(log.calciumAtLogTime),
                optStr(log.ironAtLogTime),
                optStr(log.magnesiumAtLogTime),
                optStr(log.zincAtLogTime),
                optStr(log.vitaminAAtLogTime),
                optStr(log.vitaminCAtLogTime),
                optStr(log.vitaminDAtLogTime),
                optStr(log.vitaminEAtLogTime),
                optStr(log.vitaminKAtLogTime),
                optStr(log.vitaminB6AtLogTime),
                optStr(log.vitaminB12AtLogTime),
                optStr(log.folateAtLogTime),
                optStr(log.cholineAtLogTime),
                optStr(log.caffeineAtLogTime)
            ]
            rows.append(row)
        }

        return csvString(rows)
    }

    // MARK: - Recipes CSV
    //
    // JSON array fields (directions, keywords, dietTags, importedNutrition) are
    // base64-encoded to avoid embedded commas/newlines breaking CSV line parsing.

    public static func exportRecipes(_ recipes: [Recipe]) -> String {
        let headers = [
            "id", "name", "servingsYield", "sourceURL",
            "prepMinutes", "cookMinutes", "totalMinutes",
            "imageURL",
            "recipeDescription", "recipeCategory", "recipeCuisine",
            "author", "ratingValue", "ratingCount", "notes",
            "keywords", "dietTags", "directions", "importedNutrition",
            "dateAdded", "foodItemId"
        ]
        var rows: [[String]] = [headers]
        let iso = ISO8601DateFormatter()

        for recipe in recipes {
            let row: [String] = [
                recipe.id.uuidString,
                recipe.name,
                String(recipe.servingsYield),
                recipe.sourceURL ?? "",
                recipe.prepMinutes.map(String.init) ?? "",
                recipe.cookMinutes.map(String.init) ?? "",
                recipe.totalMinutes.map(String.init) ?? "",
                recipe.imageURL ?? "",
                recipe.recipeDescription ?? "",
                recipe.recipeCategory ?? "",
                recipe.recipeCuisine ?? "",
                recipe.author ?? "",
                recipe.ratingValue.map { String(format: "%.2g", $0) } ?? "",
                recipe.ratingCount.map(String.init) ?? "",
                recipe.notes ?? "",
                base64Data(recipe.keywordsData),
                base64Data(recipe.dietTagsData),
                base64Data(recipe.directionsData),
                base64Data(recipe.importedNutritionData),
                iso.string(from: recipe.dateAdded),
                recipe.foodItem?.id.uuidString ?? ""
            ]
            rows.append(row)
        }

        return csvString(rows)
    }

    // MARK: - Ingredients CSV

    public static func exportIngredients(_ ingredients: [RecipeIngredient]) -> String {
        let headers = [
            "id", "recipeId", "foodItemId", "servingSizeId",
            "quantity", "sortOrder", "rawText", "recipeQuantity", "recipeUnit"
        ]
        var rows: [[String]] = [headers]

        for ingredient in ingredients {
            guard let recipeId = ingredient.recipe?.id else { continue }
            let row: [String] = [
                ingredient.id.uuidString,
                recipeId.uuidString,
                ingredient.foodItem?.id.uuidString ?? "",
                ingredient.servingSize?.id.uuidString ?? "",
                String(ingredient.quantity),
                String(ingredient.sortOrder),
                ingredient.rawText ?? "",
                ingredient.recipeQuantity.map { String(format: "%.4g", $0) } ?? "",
                ingredient.recipeUnit ?? ""
            ]
            rows.append(row)
        }

        return csvString(rows)
    }

    // MARK: - Meal Plans CSV (SchemaV5 — T-12-RestoreUpdate)

    public static func exportMealPlans(_ plans: [MealPlan]) -> String {
        let headers = ["id", "weekStartDate"]
        var rows: [[String]] = [headers]
        let iso = ISO8601DateFormatter()
        for plan in plans {
            rows.append([plan.id.uuidString, iso.string(from: plan.weekStartDate)])
        }
        return csvString(rows)
    }

    // MARK: - Meal Meals CSV

    public static func exportMealMeals(_ meals: [MealPlanMeal]) -> String {
        let headers = ["id", "planId", "date", "mealType", "name"]
        var rows: [[String]] = [headers]
        let iso = ISO8601DateFormatter()
        for meal in meals {
            guard let planId = meal.mealPlan?.id else { continue }
            rows.append([
                meal.id.uuidString,
                planId.uuidString,
                iso.string(from: meal.date),
                meal.mealType.rawValue,
                meal.name ?? ""
            ])
        }
        return csvString(rows)
    }

    // MARK: - Meal Items CSV

    public static func exportMealItems(_ items: [MealPlanMealItem]) -> String {
        let headers = ["id", "mealId", "recipeId", "foodItemId", "servingSizeId", "note", "servingCount"]
        var rows: [[String]] = [headers]
        for item in items {
            guard let mealId = item.meal?.id else { continue }
            rows.append([
                item.id.uuidString,
                mealId.uuidString,
                item.recipe?.id.uuidString ?? "",
                item.foodItem?.id.uuidString ?? "",
                item.servingSize?.id.uuidString ?? "",
                item.note ?? "",
                String(format: "%.4g", item.servingCount)
            ])
        }
        return csvString(rows)
    }

    // MARK: - Helpers

    private static func optStr(_ value: Double?) -> String {
        guard let v = value else { return "" }
        // Use integer representation if no decimal part to keep CSV clean
        return v.truncatingRemainder(dividingBy: 1) == 0
            ? String(Int(v))
            : String(format: "%.4g", v)
    }

    /// Base64-encodes a Data blob for safe storage in a CSV cell.
    /// Empty string when data is nil. Decode with Data(base64Encoded:).
    private static func base64Data(_ data: Data?) -> String {
        data?.base64EncodedString() ?? ""
    }

    private static func csvString(_ rows: [[String]]) -> String {
        rows.map { row in
            row.map { field in
                // Quote fields that contain commas, quotes, or newlines
                if field.contains(",") || field.contains("\"") || field.contains("\n") {
                    return "\"\(field.replacingOccurrences(of: "\"", with: "\"\""))\""
                }
                return field
            }.joined(separator: ",")
        }.joined(separator: "\n")
    }
}
