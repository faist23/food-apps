//
//  CanonicalFoodSeeder.swift
//  BiteLedger
//
//  Created by Craig Faist on 3/14/26.
//

import SwiftData
import Foundation

// MARK: - CanonicalFoodSeeder

/// Writes the authoritative CanonicalFood + ServingConversion seed data on first launch.
/// All gram values are sourced from USDA SR28 or manufacturer data.
/// Safe to call on every launch — no-op if seed data already exists.
public enum CanonicalFoodSeeder {

    @MainActor
    public static func seedIfNeeded(container: ModelContainer) async {
        let context = container.mainContext
        do {
            let existing = try context.fetchCount(FetchDescriptor<CanonicalFood>())
            guard existing == 0 else { return }
            for entry in seedData {
                let canonical = CanonicalFood(name: entry.name)
                context.insert(canonical)
                for conv in entry.conversions {
                    let sc = ServingConversion(unit: conv.unit, gramsPerUnit: conv.gramsPerUnit)
                    sc.canonicalFood = canonical
                    context.insert(sc)
                }
            }
            try context.save()
            print("✅ CanonicalFoodSeeder: wrote \(seedData.count) canonical food(s)")
        } catch {
            print("⚠️ CanonicalFoodSeeder failed: \(error)")
        }
    }

    // MARK: - Seed Data

    private struct SeedEntry {
        public let name: String
        public let conversions: [(unit: String, gramsPerUnit: Double)]
    }

    /// Authoritative unit→gram conversions per food class.
    /// Units use ServingUnit abbreviations ("tbsp", "tsp", "cup", "oz", "fl oz", "g", "ml").
    private static let seedData: [SeedEntry] = [

        // MARK: Nut Butters
        SeedEntry(name: "Peanut Butter", conversions: [
            (unit: "tbsp",  gramsPerUnit: 16.0),
            (unit: "tsp",   gramsPerUnit: 5.3),
            (unit: "cup",   gramsPerUnit: 258.0),
            (unit: "oz",    gramsPerUnit: 28.35),
            (unit: "g",     gramsPerUnit: 1.0),
        ]),
        SeedEntry(name: "Almond Butter", conversions: [
            (unit: "tbsp",  gramsPerUnit: 16.0),
            (unit: "tsp",   gramsPerUnit: 5.3),
            (unit: "cup",   gramsPerUnit: 258.0),
            (unit: "oz",    gramsPerUnit: 28.35),
            (unit: "g",     gramsPerUnit: 1.0),
        ]),
        SeedEntry(name: "Cashew Butter", conversions: [
            (unit: "tbsp",  gramsPerUnit: 16.0),
            (unit: "tsp",   gramsPerUnit: 5.3),
            (unit: "cup",   gramsPerUnit: 258.0),
            (unit: "g",     gramsPerUnit: 1.0),
        ]),

        // MARK: Oils & Fats
        SeedEntry(name: "Olive Oil", conversions: [
            (unit: "tbsp",  gramsPerUnit: 13.5),
            (unit: "tsp",   gramsPerUnit: 4.5),
            (unit: "cup",   gramsPerUnit: 216.0),
            (unit: "ml",    gramsPerUnit: 0.92),
            (unit: "g",     gramsPerUnit: 1.0),
        ]),
        SeedEntry(name: "Vegetable Oil", conversions: [
            (unit: "tbsp",  gramsPerUnit: 14.0),
            (unit: "tsp",   gramsPerUnit: 4.7),
            (unit: "cup",   gramsPerUnit: 224.0),
            (unit: "g",     gramsPerUnit: 1.0),
        ]),
        SeedEntry(name: "Coconut Oil", conversions: [
            (unit: "tbsp",  gramsPerUnit: 14.0),
            (unit: "tsp",   gramsPerUnit: 4.7),
            (unit: "cup",   gramsPerUnit: 218.0),
            (unit: "g",     gramsPerUnit: 1.0),
        ]),
        SeedEntry(name: "Butter", conversions: [
            (unit: "tbsp",  gramsPerUnit: 14.2),
            (unit: "tsp",   gramsPerUnit: 4.7),
            (unit: "cup",   gramsPerUnit: 227.0),
            (unit: "oz",    gramsPerUnit: 28.35),
            (unit: "g",     gramsPerUnit: 1.0),
        ]),

        // MARK: Sweeteners
        SeedEntry(name: "Honey", conversions: [
            (unit: "tbsp",  gramsPerUnit: 21.0),
            (unit: "tsp",   gramsPerUnit: 7.0),
            (unit: "cup",   gramsPerUnit: 339.0),
            (unit: "g",     gramsPerUnit: 1.0),
        ]),
        SeedEntry(name: "Maple Syrup", conversions: [
            (unit: "tbsp",  gramsPerUnit: 20.0),
            (unit: "tsp",   gramsPerUnit: 6.7),
            (unit: "cup",   gramsPerUnit: 322.0),
            (unit: "g",     gramsPerUnit: 1.0),
        ]),
        SeedEntry(name: "Sugar", conversions: [
            (unit: "tbsp",  gramsPerUnit: 12.6),
            (unit: "tsp",   gramsPerUnit: 4.2),
            (unit: "cup",   gramsPerUnit: 200.0),
            (unit: "g",     gramsPerUnit: 1.0),
        ]),
        SeedEntry(name: "Brown Sugar", conversions: [
            (unit: "tbsp",  gramsPerUnit: 13.8),
            (unit: "tsp",   gramsPerUnit: 4.6),
            (unit: "cup",   gramsPerUnit: 220.0),
            (unit: "g",     gramsPerUnit: 1.0),
        ]),
        SeedEntry(name: "Powdered Sugar", conversions: [
            (unit: "tbsp",  gramsPerUnit: 7.5),
            (unit: "tsp",   gramsPerUnit: 2.5),
            (unit: "cup",   gramsPerUnit: 120.0),
            (unit: "g",     gramsPerUnit: 1.0),
        ]),

        // MARK: Flours & Starches
        SeedEntry(name: "All-Purpose Flour", conversions: [
            (unit: "tbsp",  gramsPerUnit: 7.8),
            (unit: "tsp",   gramsPerUnit: 2.6),
            (unit: "cup",   gramsPerUnit: 125.0),
            (unit: "g",     gramsPerUnit: 1.0),
        ]),
        SeedEntry(name: "Whole Wheat Flour", conversions: [
            (unit: "tbsp",  gramsPerUnit: 9.4),
            (unit: "tsp",   gramsPerUnit: 3.1),
            (unit: "cup",   gramsPerUnit: 120.0),
            (unit: "g",     gramsPerUnit: 1.0),
        ]),
        SeedEntry(name: "Cornstarch", conversions: [
            (unit: "tbsp",  gramsPerUnit: 8.0),
            (unit: "tsp",   gramsPerUnit: 2.7),
            (unit: "cup",   gramsPerUnit: 128.0),
            (unit: "g",     gramsPerUnit: 1.0),
        ]),
        SeedEntry(name: "Oats", conversions: [
            (unit: "cup",   gramsPerUnit: 81.0),
            (unit: "tbsp",  gramsPerUnit: 5.1),
            (unit: "g",     gramsPerUnit: 1.0),
        ]),

        // MARK: Dairy — Liquid
        SeedEntry(name: "Whole Milk", conversions: [
            (unit: "cup",   gramsPerUnit: 244.0),
            (unit: "fl oz", gramsPerUnit: 30.5),
            (unit: "ml",    gramsPerUnit: 1.03),
            (unit: "tbsp",  gramsPerUnit: 15.4),
            (unit: "g",     gramsPerUnit: 1.0),
        ]),
        SeedEntry(name: "Skim Milk", conversions: [
            (unit: "cup",   gramsPerUnit: 245.0),
            (unit: "fl oz", gramsPerUnit: 30.6),
            (unit: "ml",    gramsPerUnit: 1.03),
            (unit: "g",     gramsPerUnit: 1.0),
        ]),
        SeedEntry(name: "Oat Milk", conversions: [
            (unit: "cup",   gramsPerUnit: 240.0),
            (unit: "fl oz", gramsPerUnit: 30.0),
            (unit: "ml",    gramsPerUnit: 1.0),
            (unit: "g",     gramsPerUnit: 1.0),
        ]),
        SeedEntry(name: "Almond Milk", conversions: [
            (unit: "cup",   gramsPerUnit: 240.0),
            (unit: "fl oz", gramsPerUnit: 30.0),
            (unit: "ml",    gramsPerUnit: 1.0),
            (unit: "g",     gramsPerUnit: 1.0),
        ]),
        SeedEntry(name: "Heavy Cream", conversions: [
            (unit: "cup",   gramsPerUnit: 238.0),
            (unit: "tbsp",  gramsPerUnit: 15.0),
            (unit: "fl oz", gramsPerUnit: 29.8),
            (unit: "ml",    gramsPerUnit: 1.01),
            (unit: "g",     gramsPerUnit: 1.0),
        ]),
        SeedEntry(name: "Greek Yogurt", conversions: [
            (unit: "cup",   gramsPerUnit: 245.0),
            (unit: "tbsp",  gramsPerUnit: 15.3),
            (unit: "oz",    gramsPerUnit: 28.35),
            (unit: "g",     gramsPerUnit: 1.0),
        ]),

        // MARK: Beverages
        SeedEntry(name: "Water", conversions: [
            (unit: "cup",   gramsPerUnit: 237.0),
            (unit: "fl oz", gramsPerUnit: 29.6),
            (unit: "ml",    gramsPerUnit: 1.0),
            (unit: "L",     gramsPerUnit: 1000.0),
            (unit: "g",     gramsPerUnit: 1.0),
        ]),
        SeedEntry(name: "Orange Juice", conversions: [
            (unit: "cup",   gramsPerUnit: 248.0),
            (unit: "fl oz", gramsPerUnit: 31.0),
            (unit: "ml",    gramsPerUnit: 1.05),
            (unit: "g",     gramsPerUnit: 1.0),
        ]),
        SeedEntry(name: "Coffee", conversions: [
            (unit: "cup",   gramsPerUnit: 237.0),
            (unit: "fl oz", gramsPerUnit: 29.6),
            (unit: "ml",    gramsPerUnit: 1.0),
            (unit: "g",     gramsPerUnit: 1.0),
        ]),

        // MARK: Condiments & Sauces
        SeedEntry(name: "Ketchup", conversions: [
            (unit: "tbsp",  gramsPerUnit: 17.0),
            (unit: "tsp",   gramsPerUnit: 5.7),
            (unit: "cup",   gramsPerUnit: 272.0),
            (unit: "g",     gramsPerUnit: 1.0),
        ]),
        SeedEntry(name: "Mustard", conversions: [
            (unit: "tbsp",  gramsPerUnit: 16.0),
            (unit: "tsp",   gramsPerUnit: 5.3),
            (unit: "g",     gramsPerUnit: 1.0),
        ]),
        SeedEntry(name: "Mayonnaise", conversions: [
            (unit: "tbsp",  gramsPerUnit: 14.7),
            (unit: "tsp",   gramsPerUnit: 4.9),
            (unit: "cup",   gramsPerUnit: 232.0),
            (unit: "g",     gramsPerUnit: 1.0),
        ]),
        SeedEntry(name: "Soy Sauce", conversions: [
            (unit: "tbsp",  gramsPerUnit: 16.0),
            (unit: "tsp",   gramsPerUnit: 5.3),
            (unit: "g",     gramsPerUnit: 1.0),
        ]),

        // MARK: Proteins
        SeedEntry(name: "Protein Powder", conversions: [
            (unit: "tbsp",  gramsPerUnit: 10.0),
            (unit: "cup",   gramsPerUnit: 90.0),
            (unit: "oz",    gramsPerUnit: 28.35),
            (unit: "g",     gramsPerUnit: 1.0),
        ]),

        // MARK: Miscellaneous
        SeedEntry(name: "Baking Soda", conversions: [
            (unit: "tsp",   gramsPerUnit: 4.6),
            (unit: "tbsp",  gramsPerUnit: 13.8),
            (unit: "g",     gramsPerUnit: 1.0),
        ]),
        SeedEntry(name: "Baking Powder", conversions: [
            (unit: "tsp",   gramsPerUnit: 4.0),
            (unit: "tbsp",  gramsPerUnit: 12.0),
            (unit: "g",     gramsPerUnit: 1.0),
        ]),
        SeedEntry(name: "Salt", conversions: [
            (unit: "tsp",   gramsPerUnit: 6.0),
            (unit: "tbsp",  gramsPerUnit: 18.0),
            (unit: "g",     gramsPerUnit: 1.0),
        ]),
        SeedEntry(name: "Cocoa Powder", conversions: [
            (unit: "tbsp",  gramsPerUnit: 7.4),
            (unit: "tsp",   gramsPerUnit: 2.5),
            (unit: "cup",   gramsPerUnit: 118.0),
            (unit: "g",     gramsPerUnit: 1.0),
        ]),
        SeedEntry(name: "Cream Cheese", conversions: [
            (unit: "tbsp",  gramsPerUnit: 14.5),
            (unit: "oz",    gramsPerUnit: 28.35),
            (unit: "cup",   gramsPerUnit: 232.0),
            (unit: "g",     gramsPerUnit: 1.0),
        ]),
        SeedEntry(name: "Sour Cream", conversions: [
            (unit: "tbsp",  gramsPerUnit: 14.4),
            (unit: "cup",   gramsPerUnit: 230.0),
            (unit: "g",     gramsPerUnit: 1.0),
        ]),
    ]
}
