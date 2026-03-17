//
//  BasicIngredientSeeder.swift
//  BiteLedgerCore
//
//  Seeds ~50 essential cooking ingredients as FoodItem + ServingSize records on first launch.
//  All nutrition values are per 100g (USDA SR28 / FoodData Central). Minerals in mg/100g.
//  These provide reliable recipe-ingredient matching for basic foods that may not
//  exist in the user's personal food library (pepper, salt, flour, etc.).
//
//  Identified by source = "built_in". Seeder is a no-op if any built_in records exist.
//

import SwiftData
import Foundation

public enum BasicIngredientSeeder {

    // MARK: - Public Entry Point

    /// Bump this string whenever you edit ingredient data.
    /// The seeder deletes all existing built_in_* records and re-seeds on next launch.
    private static let currentSource = "built_in_v1"

    @MainActor
    public static func seedIfNeeded(container: ModelContainer) async {
        let context = container.mainContext
        do {
            // Already seeded at this version — nothing to do
            let current = try context.fetchCount(
                FetchDescriptor<FoodItem>(predicate: #Predicate { $0.source == currentSource })
            )
            guard current == 0 else { return }

            // Delete any records from previous versions (source starts with "built_in")
            let allBuiltIn = try context.fetch(
                FetchDescriptor<FoodItem>(
                    predicate: #Predicate { $0.source.localizedStandardContains("built_in") }
                )
            )
            for food in allBuiltIn { context.delete(food) }
            if !allBuiltIn.isEmpty { try context.save() }

            for entry in ingredients {
                let food = FoodItem(
                    name:          entry.name,
                    source:        currentSource,
                    nutritionMode: .per100g,
                    calories:      entry.cal,
                    protein:       entry.pro,
                    carbs:         entry.carb,
                    fat:           entry.fat,
                    fiber:         entry.fiber,
                    sugar:         entry.sugar,
                    saturatedFat:  entry.satFat,
                    sodium:        entry.sodium,
                    cholesterol:   entry.chol,
                    potassium:     entry.pot,
                    calcium:       entry.cal2,
                    iron:          entry.iron
                )
                context.insert(food)

                for (i, sv) in entry.servings.enumerated() {
                    let serving = ServingSize(
                        label:      sv.label,
                        gramWeight: sv.grams,
                        isDefault:  i == 0,
                        sortOrder:  i,
                        unit:       sv.unit,
                        amount:     sv.amount
                    )
                    serving.foodItem = food
                    context.insert(serving)
                }
            }
            try context.save()
            print("✅ BasicIngredientSeeder \(currentSource): seeded \(ingredients.count) built-in ingredients")
        } catch {
            print("⚠️ BasicIngredientSeeder failed: \(error)")
        }
    }

    // MARK: - Data Model

    private struct Serving {
        let label: String
        let grams: Double
        let unit:  String
        let amount: Double
    }

    private struct Ingredient {
        let name: String
        // Macros — per 100g
        let cal:  Double          // kcal
        let pro:  Double          // g
        let carb: Double          // g
        let fat:  Double          // g
        // Optional macros — per 100g
        var fiber:  Double? = nil
        var sugar:  Double? = nil
        var satFat: Double? = nil
        // Minerals — mg per 100g
        var sodium: Double? = nil
        var chol:   Double? = nil  // cholesterol mg
        var pot:    Double? = nil  // potassium mg
        var cal2:   Double? = nil  // calcium mg
        var iron:   Double? = nil  // mg
        // Serving sizes
        let servings: [Serving]
    }

    // MARK: - Seed Data (USDA SR28 / FoodData Central, per 100g)

    private static let ingredients: [Ingredient] = [

        // ── Spices & Seasonings ──────────────────────────────────────────

        Ingredient(name: "Black Pepper",
            cal: 251, pro: 10.4, carb: 63.9, fat: 3.3,
            fiber: 25.3, sodium: 20, pot: 1329, cal2: 443, iron: 9.7,
            servings: [
                Serving(label: "1 tsp",  grams: 2.6,  unit: "tsp",  amount: 1),
                Serving(label: "1 tbsp", grams: 7.8,  unit: "tbsp", amount: 1),
            ]),

        Ingredient(name: "Salt",
            cal: 0, pro: 0, carb: 0, fat: 0,
            sodium: 38758,
            servings: [
                Serving(label: "1 tsp",  grams: 6.0,  unit: "tsp",  amount: 1),
                Serving(label: "1 tbsp", grams: 18.0, unit: "tbsp", amount: 1),
                Serving(label: "1/4 tsp", grams: 1.5, unit: "tsp",  amount: 0.25),
            ]),

        Ingredient(name: "Kosher Salt",
            cal: 0, pro: 0, carb: 0, fat: 0,
            sodium: 38758,
            servings: [
                Serving(label: "1 tsp",  grams: 4.8,  unit: "tsp",  amount: 1),
                Serving(label: "1 tbsp", grams: 14.4, unit: "tbsp", amount: 1),
            ]),

        Ingredient(name: "Garlic Powder",
            cal: 331, pro: 14.1, carb: 72.7, fat: 0.7,
            fiber: 9.0, sodium: 26, pot: 1193, cal2: 79, iron: 2.3,
            servings: [
                Serving(label: "1 tsp",  grams: 3.1,  unit: "tsp",  amount: 1),
                Serving(label: "1 tbsp", grams: 9.2,  unit: "tbsp", amount: 1),
            ]),

        Ingredient(name: "Onion Powder",
            cal: 341, pro: 10.4, carb: 79.1, fat: 1.0,
            fiber: 9.2, sodium: 46,
            servings: [
                Serving(label: "1 tsp",  grams: 2.4,  unit: "tsp",  amount: 1),
                Serving(label: "1 tbsp", grams: 7.1,  unit: "tbsp", amount: 1),
            ]),

        Ingredient(name: "Paprika",
            cal: 282, pro: 14.1, carb: 53.9, fat: 12.9,
            fiber: 34.9, sodium: 68, pot: 2280, cal2: 229, iron: 21.1,
            servings: [
                Serving(label: "1 tsp",  grams: 2.3,  unit: "tsp",  amount: 1),
                Serving(label: "1 tbsp", grams: 6.9,  unit: "tbsp", amount: 1),
            ]),

        Ingredient(name: "Smoked Paprika",
            cal: 282, pro: 14.1, carb: 53.9, fat: 12.9,
            fiber: 34.9, sodium: 68,
            servings: [
                Serving(label: "1 tsp",  grams: 2.3,  unit: "tsp",  amount: 1),
                Serving(label: "1 tbsp", grams: 6.9,  unit: "tbsp", amount: 1),
            ]),

        Ingredient(name: "Cumin",
            cal: 375, pro: 17.8, carb: 44.2, fat: 22.3,
            fiber: 10.5, sodium: 168, pot: 1788, cal2: 931, iron: 66.4,
            servings: [
                Serving(label: "1 tsp",  grams: 2.1,  unit: "tsp",  amount: 1),
                Serving(label: "1 tbsp", grams: 6.3,  unit: "tbsp", amount: 1),
            ]),

        Ingredient(name: "Chili Powder",
            cal: 282, pro: 13.5, carb: 49.7, fat: 14.3,
            fiber: 34.8, sodium: 1524,
            servings: [
                Serving(label: "1 tsp",  grams: 2.7,  unit: "tsp",  amount: 1),
                Serving(label: "1 tbsp", grams: 8.0,  unit: "tbsp", amount: 1),
            ]),

        Ingredient(name: "Oregano",
            cal: 265, pro: 9.0, carb: 68.9, fat: 4.3,
            fiber: 42.5, sodium: 25, pot: 1669, cal2: 1576, iron: 36.8,
            servings: [
                Serving(label: "1 tsp",  grams: 1.0,  unit: "tsp",  amount: 1),
                Serving(label: "1 tbsp", grams: 3.0,  unit: "tbsp", amount: 1),
            ]),

        Ingredient(name: "Basil",
            cal: 22, pro: 3.2, carb: 2.7, fat: 0.6,
            fiber: 1.6, sodium: 4, pot: 295, cal2: 177, iron: 3.2,
            servings: [
                Serving(label: "1 tsp",  grams: 0.7,  unit: "tsp",  amount: 1),
                Serving(label: "1 tbsp", grams: 2.1,  unit: "tbsp", amount: 1),
                Serving(label: "1 cup",  grams: 24.0, unit: "cup",  amount: 1),
            ]),

        Ingredient(name: "Thyme",
            cal: 276, pro: 9.1, carb: 63.9, fat: 7.4,
            fiber: 37.0, sodium: 55, pot: 814, cal2: 1890, iron: 123.6,
            servings: [
                Serving(label: "1 tsp",  grams: 0.8,  unit: "tsp",  amount: 1),
                Serving(label: "1 tbsp", grams: 2.3,  unit: "tbsp", amount: 1),
            ]),

        Ingredient(name: "Rosemary",
            cal: 131, pro: 3.3, carb: 20.7, fat: 5.9,
            fiber: 14.1, sodium: 26,
            servings: [
                Serving(label: "1 tsp",  grams: 1.2,  unit: "tsp",  amount: 1),
                Serving(label: "1 tbsp", grams: 3.5,  unit: "tbsp", amount: 1),
                Serving(label: "1 sprig", grams: 1.5, unit: "piece", amount: 1),
            ]),

        Ingredient(name: "Cinnamon",
            cal: 247, pro: 4.0, carb: 80.6, fat: 1.2,
            fiber: 53.1, sodium: 10, pot: 431, cal2: 1002, iron: 8.3,
            servings: [
                Serving(label: "1 tsp",  grams: 2.6,  unit: "tsp",  amount: 1),
                Serving(label: "1 tbsp", grams: 7.8,  unit: "tbsp", amount: 1),
            ]),

        Ingredient(name: "Red Pepper Flakes",
            cal: 318, pro: 12.0, carb: 56.6, fat: 17.3,
            fiber: 27.4, sodium: 30,
            servings: [
                Serving(label: "1 tsp",  grams: 2.3,  unit: "tsp",  amount: 1),
                Serving(label: "1 tbsp", grams: 6.8,  unit: "tbsp", amount: 1),
                Serving(label: "1/4 tsp", grams: 0.6, unit: "tsp",  amount: 0.25),
            ]),

        Ingredient(name: "Cayenne Pepper",
            cal: 318, pro: 12.0, carb: 56.6, fat: 17.3,
            fiber: 27.4, sodium: 30,
            servings: [
                Serving(label: "1 tsp",  grams: 1.8,  unit: "tsp",  amount: 1),
                Serving(label: "1 tbsp", grams: 5.3,  unit: "tbsp", amount: 1),
                Serving(label: "1/4 tsp", grams: 0.5, unit: "tsp",  amount: 0.25),
            ]),

        Ingredient(name: "Italian Seasoning",
            cal: 260, pro: 8.0, carb: 60.0, fat: 5.0,
            fiber: 40.0, sodium: 30,
            servings: [
                Serving(label: "1 tsp",  grams: 1.0,  unit: "tsp",  amount: 1),
                Serving(label: "1 tbsp", grams: 3.0,  unit: "tbsp", amount: 1),
            ]),

        Ingredient(name: "Vanilla Extract",
            cal: 288, pro: 0.1, carb: 12.7, fat: 0.1,
            sodium: 9,
            servings: [
                Serving(label: "1 tsp",  grams: 4.2,  unit: "tsp",  amount: 1),
                Serving(label: "1 tbsp", grams: 12.6, unit: "tbsp", amount: 1),
            ]),

        // ── Aromatics & Fresh Produce ────────────────────────────────────

        Ingredient(name: "Garlic",
            cal: 149, pro: 6.4, carb: 33.1, fat: 0.5,
            fiber: 2.1, sodium: 17, pot: 401, cal2: 181, iron: 1.7,
            servings: [
                Serving(label: "1 clove",  grams: 3.0,  unit: "piece", amount: 1),
                Serving(label: "1 tsp minced", grams: 4.0, unit: "tsp", amount: 1),
                Serving(label: "1 tbsp minced", grams: 12.0, unit: "tbsp", amount: 1),
                Serving(label: "1 head",   grams: 56.0, unit: "piece", amount: 1),
            ]),

        Ingredient(name: "Onion",
            cal: 40, pro: 1.1, carb: 9.3, fat: 0.1,
            fiber: 1.7, sugar: 4.2, sodium: 4, pot: 146, cal2: 23, iron: 0.2,
            servings: [
                Serving(label: "1 medium onion", grams: 110.0, unit: "piece", amount: 1),
                Serving(label: "1 large onion",  grams: 150.0, unit: "piece", amount: 1),
                Serving(label: "1 cup chopped",  grams: 160.0, unit: "cup",   amount: 1),
                Serving(label: "1 tbsp chopped", grams: 10.0,  unit: "tbsp",  amount: 1),
            ]),

        Ingredient(name: "Lemon Juice",
            cal: 22, pro: 0.4, carb: 6.9, fat: 0.2,
            fiber: 0.3, sodium: 1, pot: 138, cal2: 7, iron: 0.1,
            servings: [
                Serving(label: "1 tbsp",   grams: 15.2, unit: "tbsp", amount: 1),
                Serving(label: "1/4 cup",  grams: 61.0, unit: "cup",  amount: 0.25),
                Serving(label: "1 lemon",  grams: 47.0, unit: "piece", amount: 1),
            ]),

        Ingredient(name: "Lime Juice",
            cal: 25, pro: 0.4, carb: 8.4, fat: 0.1,
            sodium: 2, pot: 117,
            servings: [
                Serving(label: "1 tbsp",  grams: 15.2, unit: "tbsp", amount: 1),
                Serving(label: "1 lime",  grams: 38.0, unit: "piece", amount: 1),
            ]),

        // ── Fats & Oils ──────────────────────────────────────────────────

        Ingredient(name: "Olive Oil",
            cal: 884, pro: 0, carb: 0, fat: 100.0,
            satFat: 13.8, sodium: 2,
            servings: [
                Serving(label: "1 tsp",  grams: 4.5,  unit: "tsp",  amount: 1),
                Serving(label: "1 tbsp", grams: 13.5, unit: "tbsp", amount: 1),
                Serving(label: "1/4 cup", grams: 54.0, unit: "cup", amount: 0.25),
            ]),

        Ingredient(name: "Butter",
            cal: 717, pro: 0.9, carb: 0.1, fat: 81.1,
            satFat: 51.4, sodium: 576, chol: 215,
            servings: [
                Serving(label: "1 tbsp", grams: 14.2, unit: "tbsp", amount: 1),
                Serving(label: "1 tsp",  grams: 4.7,  unit: "tsp",  amount: 1),
                Serving(label: "1/4 cup", grams: 56.8, unit: "cup", amount: 0.25),
                Serving(label: "1 stick", grams: 113.4, unit: "piece", amount: 1),
            ]),

        Ingredient(name: "Vegetable Oil",
            cal: 884, pro: 0, carb: 0, fat: 100.0,
            satFat: 13.6, sodium: 0,
            servings: [
                Serving(label: "1 tsp",  grams: 4.7,  unit: "tsp",  amount: 1),
                Serving(label: "1 tbsp", grams: 14.0, unit: "tbsp", amount: 1),
                Serving(label: "1/4 cup", grams: 56.0, unit: "cup", amount: 0.25),
            ]),

        Ingredient(name: "Coconut Oil",
            cal: 892, pro: 0, carb: 0, fat: 99.1,
            satFat: 82.5, sodium: 0,
            servings: [
                Serving(label: "1 tbsp", grams: 14.0, unit: "tbsp", amount: 1),
                Serving(label: "1 tsp",  grams: 4.7,  unit: "tsp",  amount: 1),
            ]),

        // ── Baking Staples ───────────────────────────────────────────────

        Ingredient(name: "All-Purpose Flour",
            cal: 364, pro: 10.3, carb: 76.3, fat: 1.0,
            fiber: 2.7, sodium: 2,
            servings: [
                Serving(label: "1 cup",  grams: 125.0, unit: "cup",  amount: 1),
                Serving(label: "1 tbsp", grams: 7.8,   unit: "tbsp", amount: 1),
                Serving(label: "1/4 cup", grams: 31.0, unit: "cup",  amount: 0.25),
            ]),

        Ingredient(name: "Whole Wheat Flour",
            cal: 340, pro: 13.7, carb: 72.6, fat: 2.5,
            fiber: 10.7, sodium: 2,
            servings: [
                Serving(label: "1 cup",  grams: 120.0, unit: "cup",  amount: 1),
                Serving(label: "1 tbsp", grams: 7.5,   unit: "tbsp", amount: 1),
            ]),

        Ingredient(name: "Bread Flour",
            cal: 361, pro: 12.0, carb: 73.0, fat: 1.5,
            fiber: 2.4, sodium: 2,
            servings: [
                Serving(label: "1 cup",  grams: 127.0, unit: "cup",  amount: 1),
                Serving(label: "1 tbsp", grams: 7.9,   unit: "tbsp", amount: 1),
            ]),

        Ingredient(name: "Sugar",
            cal: 387, pro: 0, carb: 100.0, fat: 0,
            sugar: 99.8, sodium: 1,
            servings: [
                Serving(label: "1 cup",  grams: 200.0, unit: "cup",  amount: 1),
                Serving(label: "1 tbsp", grams: 12.6,  unit: "tbsp", amount: 1),
                Serving(label: "1 tsp",  grams: 4.2,   unit: "tsp",  amount: 1),
            ]),

        Ingredient(name: "Brown Sugar",
            cal: 380, pro: 0, carb: 98.1, fat: 0,
            sugar: 97.0, sodium: 28,
            servings: [
                Serving(label: "1 cup",  grams: 220.0, unit: "cup",  amount: 1),
                Serving(label: "1 tbsp", grams: 13.8,  unit: "tbsp", amount: 1),
                Serving(label: "1 tsp",  grams: 4.6,   unit: "tsp",  amount: 1),
            ]),

        Ingredient(name: "Powdered Sugar",
            cal: 389, pro: 0, carb: 99.8, fat: 0,
            sugar: 97.8, sodium: 2,
            servings: [
                Serving(label: "1 cup",  grams: 120.0, unit: "cup",  amount: 1),
                Serving(label: "1 tbsp", grams: 7.5,   unit: "tbsp", amount: 1),
            ]),

        Ingredient(name: "Honey",
            cal: 304, pro: 0.3, carb: 82.4, fat: 0,
            sugar: 82.1, sodium: 4, pot: 52, cal2: 6,
            servings: [
                Serving(label: "1 tbsp", grams: 21.0, unit: "tbsp", amount: 1),
                Serving(label: "1 tsp",  grams: 7.0,  unit: "tsp",  amount: 1),
                Serving(label: "1/4 cup", grams: 84.0, unit: "cup", amount: 0.25),
            ]),

        Ingredient(name: "Maple Syrup",
            cal: 260, pro: 0, carb: 67.0, fat: 0.1,
            sugar: 60.0, sodium: 12, pot: 212,
            servings: [
                Serving(label: "1 tbsp", grams: 20.0, unit: "tbsp", amount: 1),
                Serving(label: "1 tsp",  grams: 6.7,  unit: "tsp",  amount: 1),
                Serving(label: "1/4 cup", grams: 80.0, unit: "cup", amount: 0.25),
            ]),

        Ingredient(name: "Baking Powder",
            cal: 53, pro: 0, carb: 27.7, fat: 0,
            sodium: 10105,
            servings: [
                Serving(label: "1 tsp",  grams: 4.0,  unit: "tsp",  amount: 1),
                Serving(label: "1 tbsp", grams: 12.0, unit: "tbsp", amount: 1),
            ]),

        Ingredient(name: "Baking Soda",
            cal: 0, pro: 0, carb: 0, fat: 0,
            sodium: 27360,
            servings: [
                Serving(label: "1 tsp",  grams: 4.6,  unit: "tsp",  amount: 1),
                Serving(label: "1 tbsp", grams: 13.8, unit: "tbsp", amount: 1),
                Serving(label: "1/4 tsp", grams: 1.2, unit: "tsp",  amount: 0.25),
            ]),

        Ingredient(name: "Cornstarch",
            cal: 381, pro: 0.3, carb: 91.3, fat: 0.1,
            sodium: 9,
            servings: [
                Serving(label: "1 tbsp", grams: 8.0,  unit: "tbsp", amount: 1),
                Serving(label: "1 tsp",  grams: 2.7,  unit: "tsp",  amount: 1),
                Serving(label: "1/4 cup", grams: 32.0, unit: "cup", amount: 0.25),
            ]),

        Ingredient(name: "Cocoa Powder",
            cal: 228, pro: 19.6, carb: 57.9, fat: 13.7,
            fiber: 37.0, satFat: 8.1, sodium: 21, pot: 1524, cal2: 128, iron: 13.9,
            servings: [
                Serving(label: "1 tbsp", grams: 7.4,  unit: "tbsp", amount: 1),
                Serving(label: "1/4 cup", grams: 29.6, unit: "cup", amount: 0.25),
            ]),

        // ── Dairy & Eggs ─────────────────────────────────────────────────

        Ingredient(name: "Egg",
            cal: 143, pro: 12.6, carb: 0.7, fat: 9.5,
            satFat: 3.1, sodium: 142, chol: 373, pot: 138, cal2: 50, iron: 1.8,
            servings: [
                Serving(label: "1 large egg", grams: 50.0, unit: "piece", amount: 1),
                Serving(label: "1 egg white", grams: 33.0, unit: "piece", amount: 1),
                Serving(label: "1 egg yolk",  grams: 17.0, unit: "piece", amount: 1),
            ]),

        Ingredient(name: "Whole Milk",
            cal: 61, pro: 3.2, carb: 4.8, fat: 3.3,
            satFat: 1.9, sodium: 43, chol: 10, pot: 132, cal2: 113,
            servings: [
                Serving(label: "1 cup",   grams: 244.0, unit: "cup",  amount: 1),
                Serving(label: "1 tbsp",  grams: 15.3,  unit: "tbsp", amount: 1),
                Serving(label: "1/2 cup", grams: 122.0, unit: "cup",  amount: 0.5),
            ]),

        Ingredient(name: "Heavy Cream",
            cal: 340, pro: 2.8, carb: 2.7, fat: 36.1,
            satFat: 22.6, sodium: 38, chol: 135, pot: 97,
            servings: [
                Serving(label: "1 cup",   grams: 238.0, unit: "cup",  amount: 1),
                Serving(label: "1 tbsp",  grams: 15.0,  unit: "tbsp", amount: 1),
                Serving(label: "1/2 cup", grams: 119.0, unit: "cup",  amount: 0.5),
            ]),

        Ingredient(name: "Cream Cheese",
            cal: 342, pro: 6.2, carb: 4.1, fat: 34.2,
            satFat: 19.3, sodium: 321, chol: 110, pot: 138, cal2: 83,
            servings: [
                Serving(label: "1 tbsp",  grams: 14.5,  unit: "tbsp", amount: 1),
                Serving(label: "1 oz",    grams: 28.35, unit: "oz",   amount: 1),
                Serving(label: "8 oz block", grams: 227.0, unit: "piece", amount: 1),
            ]),

        Ingredient(name: "Parmesan Cheese",
            cal: 392, pro: 35.8, carb: 3.2, fat: 25.8,
            satFat: 16.4, sodium: 1602, chol: 68, pot: 92, cal2: 1184, iron: 0.8,
            servings: [
                Serving(label: "1 tbsp grated", grams: 5.0,  unit: "tbsp", amount: 1),
                Serving(label: "1/4 cup grated", grams: 25.0, unit: "cup", amount: 0.25),
                Serving(label: "1 oz",           grams: 28.35, unit: "oz", amount: 1),
            ]),

        Ingredient(name: "Mozzarella",
            cal: 280, pro: 19.4, carb: 2.2, fat: 22.4,
            satFat: 14.4, sodium: 399, chol: 79, pot: 76, cal2: 575, iron: 0.4,
            servings: [
                Serving(label: "1 oz",    grams: 28.35, unit: "oz",  amount: 1),
                Serving(label: "1 cup shredded", grams: 113.0, unit: "cup", amount: 1),
                Serving(label: "1/4 cup shredded", grams: 28.0, unit: "cup", amount: 0.25),
            ]),

        Ingredient(name: "Cheddar Cheese",
            cal: 403, pro: 24.9, carb: 1.3, fat: 33.1,
            satFat: 21.1, sodium: 621, chol: 105, pot: 98, cal2: 710, iron: 0.7,
            servings: [
                Serving(label: "1 oz",    grams: 28.35, unit: "oz",  amount: 1),
                Serving(label: "1 cup shredded", grams: 113.0, unit: "cup", amount: 1),
                Serving(label: "1/4 cup shredded", grams: 28.0, unit: "cup", amount: 0.25),
            ]),

        Ingredient(name: "Greek Yogurt",
            cal: 59, pro: 10.2, carb: 3.6, fat: 0.4,
            sodium: 36, pot: 141, cal2: 111,
            servings: [
                Serving(label: "1 cup",   grams: 245.0, unit: "cup",  amount: 1),
                Serving(label: "1 tbsp",  grams: 15.3,  unit: "tbsp", amount: 1),
                Serving(label: "6 oz",    grams: 170.0, unit: "oz",   amount: 6),
            ]),

        Ingredient(name: "Sour Cream",
            cal: 193, pro: 2.9, carb: 4.6, fat: 19.4,
            satFat: 11.5, sodium: 53, chol: 52, pot: 166, cal2: 93,
            servings: [
                Serving(label: "1 tbsp",  grams: 14.4,  unit: "tbsp", amount: 1),
                Serving(label: "1 cup",   grams: 230.0, unit: "cup",  amount: 1),
                Serving(label: "1/4 cup", grams: 57.5,  unit: "cup",  amount: 0.25),
            ]),

        // ── Broths & Liquids ─────────────────────────────────────────────

        Ingredient(name: "Chicken Broth",
            cal: 11, pro: 1.3, carb: 0.9, fat: 0.2,
            sodium: 519, pot: 115,
            servings: [
                Serving(label: "1 cup",   grams: 240.0, unit: "cup",  amount: 1),
                Serving(label: "1 tbsp",  grams: 15.0,  unit: "tbsp", amount: 1),
                Serving(label: "14 oz can", grams: 397.0, unit: "piece", amount: 1),
            ]),

        Ingredient(name: "Beef Broth",
            cal: 8, pro: 1.2, carb: 0.7, fat: 0.2,
            sodium: 372, pot: 145,
            servings: [
                Serving(label: "1 cup",   grams: 240.0, unit: "cup",  amount: 1),
                Serving(label: "1 tbsp",  grams: 15.0,  unit: "tbsp", amount: 1),
                Serving(label: "14 oz can", grams: 397.0, unit: "piece", amount: 1),
            ]),

        Ingredient(name: "Apple Cider Vinegar",
            cal: 22, pro: 0, carb: 0.9, fat: 0,
            sodium: 5,
            servings: [
                Serving(label: "1 tbsp", grams: 14.9, unit: "tbsp", amount: 1),
                Serving(label: "1 tsp",  grams: 5.0,  unit: "tsp",  amount: 1),
            ]),

        Ingredient(name: "White Vinegar",
            cal: 18, pro: 0, carb: 0.9, fat: 0,
            sodium: 2,
            servings: [
                Serving(label: "1 tbsp", grams: 14.9, unit: "tbsp", amount: 1),
                Serving(label: "1 tsp",  grams: 5.0,  unit: "tsp",  amount: 1),
            ]),

        // ── Condiments & Sauces ──────────────────────────────────────────

        Ingredient(name: "Soy Sauce",
            cal: 53, pro: 8.1, carb: 4.9, fat: 0.1,
            sodium: 5493, pot: 435, iron: 2.5,
            servings: [
                Serving(label: "1 tbsp", grams: 16.0, unit: "tbsp", amount: 1),
                Serving(label: "1 tsp",  grams: 5.3,  unit: "tsp",  amount: 1),
            ]),

        Ingredient(name: "Worcestershire Sauce",
            cal: 78, pro: 0, carb: 19.5, fat: 0.1,
            sodium: 980,
            servings: [
                Serving(label: "1 tbsp", grams: 17.0, unit: "tbsp", amount: 1),
                Serving(label: "1 tsp",  grams: 5.7,  unit: "tsp",  amount: 1),
            ]),

        Ingredient(name: "Tomato Paste",
            cal: 82, pro: 4.3, carb: 18.9, fat: 0.5,
            fiber: 3.0, sodium: 59, pot: 1014, cal2: 31, iron: 3.9,
            servings: [
                Serving(label: "1 tbsp",  grams: 16.0, unit: "tbsp", amount: 1),
                Serving(label: "6 oz can", grams: 170.0, unit: "piece", amount: 1),
            ]),

        Ingredient(name: "Dijon Mustard",
            cal: 66, pro: 3.7, carb: 8.2, fat: 3.3,
            sodium: 1135,
            servings: [
                Serving(label: "1 tbsp", grams: 15.0, unit: "tbsp", amount: 1),
                Serving(label: "1 tsp",  grams: 5.0,  unit: "tsp",  amount: 1),
            ]),

        Ingredient(name: "Hot Sauce",
            cal: 35, pro: 1.4, carb: 5.0, fat: 0.5,
            sodium: 4000,
            servings: [
                Serving(label: "1 tsp",  grams: 4.7,  unit: "tsp",  amount: 1),
                Serving(label: "1 tbsp", grams: 14.0, unit: "tbsp", amount: 1),
            ]),

        // ── Tomato Products ──────────────────────────────────────────────

        Ingredient(name: "Diced Tomatoes",
            cal: 20, pro: 1.0, carb: 4.0, fat: 0.2,
            fiber: 1.4, sodium: 150,
            servings: [
                Serving(label: "1 cup",    grams: 240.0, unit: "cup",  amount: 1),
                Serving(label: "14 oz can", grams: 397.0, unit: "piece", amount: 1),
            ]),

        Ingredient(name: "Tomato Sauce",
            cal: 29, pro: 1.6, carb: 6.3, fat: 0.2,
            fiber: 1.5, sodium: 325, pot: 389,
            servings: [
                Serving(label: "1 cup",    grams: 245.0, unit: "cup",  amount: 1),
                Serving(label: "8 oz can",  grams: 227.0, unit: "piece", amount: 1),
                Serving(label: "15 oz can", grams: 425.0, unit: "piece", amount: 1),
            ]),

        Ingredient(name: "Crushed Tomatoes",
            cal: 32, pro: 1.6, carb: 7.3, fat: 0.3,
            fiber: 2.0, sodium: 180,
            servings: [
                Serving(label: "1 cup",    grams: 245.0, unit: "cup",  amount: 1),
                Serving(label: "28 oz can", grams: 794.0, unit: "piece", amount: 1),
            ]),

        // ── Pantry Carbs ─────────────────────────────────────────────────

        Ingredient(name: "Pasta",
            cal: 371, pro: 13.0, carb: 74.7, fat: 1.5,
            fiber: 3.2, sodium: 6,
            servings: [
                Serving(label: "1 cup dry",  grams: 91.0,  unit: "cup",  amount: 1),
                Serving(label: "2 oz dry",   grams: 56.7,  unit: "oz",   amount: 2),
                Serving(label: "1 cup cooked", grams: 140.0, unit: "cup", amount: 1),
            ]),

        Ingredient(name: "White Rice",
            cal: 365, pro: 7.1, carb: 79.9, fat: 0.7,
            fiber: 1.3, sodium: 5,
            servings: [
                Serving(label: "1 cup dry",    grams: 185.0, unit: "cup", amount: 1),
                Serving(label: "1 cup cooked", grams: 186.0, unit: "cup", amount: 1),
            ]),

        Ingredient(name: "Brown Rice",
            cal: 362, pro: 7.5, carb: 77.2, fat: 2.7,
            fiber: 3.5, sodium: 4,
            servings: [
                Serving(label: "1 cup dry",    grams: 185.0, unit: "cup", amount: 1),
                Serving(label: "1 cup cooked", grams: 195.0, unit: "cup", amount: 1),
            ]),

        Ingredient(name: "Breadcrumbs",
            cal: 395, pro: 12.4, carb: 73.4, fat: 5.3,
            fiber: 4.4, sodium: 732,
            servings: [
                Serving(label: "1 cup",  grams: 108.0, unit: "cup",  amount: 1),
                Serving(label: "1 tbsp", grams: 6.8,   unit: "tbsp", amount: 1),
            ]),

        Ingredient(name: "Panko Breadcrumbs",
            cal: 380, pro: 10.0, carb: 74.0, fat: 4.5,
            fiber: 3.0, sodium: 640,
            servings: [
                Serving(label: "1 cup",  grams: 60.0,  unit: "cup",  amount: 1),
                Serving(label: "1 tbsp", grams: 3.8,   unit: "tbsp", amount: 1),
            ]),

        // ── Coconut & Specialty ──────────────────────────────────────────

        Ingredient(name: "Coconut Milk",
            cal: 230, pro: 2.3, carb: 5.5, fat: 23.8,
            satFat: 21.1, sodium: 15,
            servings: [
                Serving(label: "1 cup",    grams: 240.0, unit: "cup",  amount: 1),
                Serving(label: "1 tbsp",   grams: 15.0,  unit: "tbsp", amount: 1),
                Serving(label: "14 oz can", grams: 397.0, unit: "piece", amount: 1),
            ]),

        Ingredient(name: "Pesto",
            cal: 280, pro: 6.0, carb: 8.0, fat: 26.0,
            satFat: 5.0, sodium: 580,
            servings: [
                Serving(label: "1 tbsp",  grams: 15.0, unit: "tbsp", amount: 1),
                Serving(label: "1/4 cup", grams: 60.0, unit: "cup",  amount: 0.25),
            ]),
    ]
}
