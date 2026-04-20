//
//  RecipeShareBundleService.swift
//  BiteLedgerCore
//
//  Creates, parses, and imports .biterecipe ZIP bundles for user-to-user recipe sharing.
//  The bundle is self-contained: all FoodItem + ServingSize data travels with the recipe,
//  so the receiver needs no ingredient matching (autoMatch is <50% accurate).
//
//  ZIP structure:
//    recipe-name-XXXX.biterecipe
//    ├── manifest.json
//    ├── recipe.json
//    ├── ingredients.json
//    ├── foods.json
//    ├── servings.json
//    └── image.jpg  (optional — only for local file:// images)
//
//  NOTE: @Model classes cannot conform to Codable (SwiftData macro conflict).
//  All data is serialized through Codable DTO structs defined below.
//

import Foundation
import SwiftData
import ZIPFoundation

// MARK: - Bundle DTOs

public struct RecipeShareBundle: Sendable {

    public struct Manifest: Codable, Sendable {
        public let schemaVersion: Int     // = 1; bump for breaking format changes
        public let exportDate: String     // ISO 8601
        public let senderAppVersion: String

        public init(schemaVersion: Int, exportDate: String, senderAppVersion: String) {
            self.schemaVersion = schemaVersion
            self.exportDate = exportDate
            self.senderAppVersion = senderAppVersion
        }
    }

    public struct RecipeDTO: Codable, Sendable {
        public let name: String
        public let servingsYield: Double
        public let sourceURL: String?
        public let directions: [String]
        public let prepMinutes: Int?
        public let cookMinutes: Int?
        public let totalMinutes: Int?
        public let recipeDescription: String?
        public let recipeCategory: String?
        public let recipeCuisine: String?
        public let author: String?
        public let ratingValue: Double?
        public let ratingCount: Int?
        public let keywords: [String]
        public let dietTags: [String]
        /// https:// URLs are portable and stored here. Local file:// images go in image.jpg.
        public let imageURL: String?

        public init(
            name: String, servingsYield: Double, sourceURL: String?,
            directions: [String], prepMinutes: Int?, cookMinutes: Int?,
            totalMinutes: Int?, recipeDescription: String?, recipeCategory: String?,
            recipeCuisine: String?, author: String?, ratingValue: Double?,
            ratingCount: Int?, keywords: [String], dietTags: [String], imageURL: String?
        ) {
            self.name = name
            self.servingsYield = servingsYield
            self.sourceURL = sourceURL
            self.directions = directions
            self.prepMinutes = prepMinutes
            self.cookMinutes = cookMinutes
            self.totalMinutes = totalMinutes
            self.recipeDescription = recipeDescription
            self.recipeCategory = recipeCategory
            self.recipeCuisine = recipeCuisine
            self.author = author
            self.ratingValue = ratingValue
            self.ratingCount = ratingCount
            self.keywords = keywords
            self.dietTags = dietTags
            self.imageURL = imageURL
        }
    }

    public struct FoodDTO: Codable, Sendable {
        /// Bundle-local UUID for cross-referencing. Never a PersistentIdentifier.
        public let bundleID: String
        public let name: String
        public let brand: String?
        public let source: String
        public let nutritionMode: String      // "per100g" | "perServing"
        public let calories: Double
        public let protein: Double
        public let carbs: Double
        public let fat: Double
        public let fiber: Double?
        public let sugar: Double?
        public let saturatedFat: Double?
        public let transFat: Double?
        public let polyunsaturatedFat: Double?
        public let monounsaturatedFat: Double?
        public let sodium: Double?
        public let cholesterol: Double?
        public let potassium: Double?
        public let calcium: Double?
        public let iron: Double?
        public let magnesium: Double?
        public let zinc: Double?
        public let vitaminA: Double?
        public let vitaminC: Double?
        public let vitaminD: Double?
        public let vitaminE: Double?
        public let vitaminK: Double?
        public let vitaminB6: Double?
        public let vitaminB12: Double?
        public let folate: Double?
        public let choline: Double?
        public let caffeine: Double?

        public init(
            bundleID: String, name: String, brand: String?, source: String,
            nutritionMode: String, calories: Double, protein: Double, carbs: Double,
            fat: Double, fiber: Double?, sugar: Double?, saturatedFat: Double?,
            transFat: Double?, polyunsaturatedFat: Double?, monounsaturatedFat: Double?,
            sodium: Double?, cholesterol: Double?, potassium: Double?, calcium: Double?,
            iron: Double?, magnesium: Double?, zinc: Double?, vitaminA: Double?,
            vitaminC: Double?, vitaminD: Double?, vitaminE: Double?, vitaminK: Double?,
            vitaminB6: Double?, vitaminB12: Double?, folate: Double?,
            choline: Double?, caffeine: Double?
        ) {
            self.bundleID = bundleID; self.name = name; self.brand = brand
            self.source = source; self.nutritionMode = nutritionMode
            self.calories = calories; self.protein = protein; self.carbs = carbs
            self.fat = fat; self.fiber = fiber; self.sugar = sugar
            self.saturatedFat = saturatedFat; self.transFat = transFat
            self.polyunsaturatedFat = polyunsaturatedFat
            self.monounsaturatedFat = monounsaturatedFat
            self.sodium = sodium; self.cholesterol = cholesterol
            self.potassium = potassium; self.calcium = calcium; self.iron = iron
            self.magnesium = magnesium; self.zinc = zinc; self.vitaminA = vitaminA
            self.vitaminC = vitaminC; self.vitaminD = vitaminD; self.vitaminE = vitaminE
            self.vitaminK = vitaminK; self.vitaminB6 = vitaminB6
            self.vitaminB12 = vitaminB12; self.folate = folate
            self.choline = choline; self.caffeine = caffeine
        }
    }

    public struct ServingDTO: Codable, Sendable {
        public let foodBundleID: String
        public let label: String
        public let gramWeight: Double?
        public let unit: String?
        public let amount: Double
        public let isDefault: Bool
        public let sortOrder: Int

        public init(foodBundleID: String, label: String, gramWeight: Double?,
                    unit: String?, amount: Double, isDefault: Bool, sortOrder: Int) {
            self.foodBundleID = foodBundleID; self.label = label
            self.gramWeight = gramWeight; self.unit = unit; self.amount = amount
            self.isDefault = isDefault; self.sortOrder = sortOrder
        }
    }

    public struct IngredientDTO: Codable, Sendable {
        public let foodBundleID: String
        public let servingLabel: String?   // re-links to ServingDTO on import
        public let quantity: Double
        public let rawText: String?
        public let recipeQuantity: Double?
        public let recipeUnit: String?
        public let sortOrder: Int

        public init(foodBundleID: String, servingLabel: String?, quantity: Double,
                    rawText: String?, recipeQuantity: Double?, recipeUnit: String?,
                    sortOrder: Int) {
            self.foodBundleID = foodBundleID; self.servingLabel = servingLabel
            self.quantity = quantity; self.rawText = rawText
            self.recipeQuantity = recipeQuantity; self.recipeUnit = recipeUnit
            self.sortOrder = sortOrder
        }
    }

    public let manifest: Manifest
    public let recipe: RecipeDTO
    public let ingredients: [IngredientDTO]
    public let foods: [FoodDTO]
    public let servings: [ServingDTO]
    /// True when image.jpg is present in the archive.
    public let hasImage: Bool

    public init(manifest: Manifest, recipe: RecipeDTO, ingredients: [IngredientDTO],
                foods: [FoodDTO], servings: [ServingDTO], hasImage: Bool) {
        self.manifest = manifest; self.recipe = recipe
        self.ingredients = ingredients; self.foods = foods
        self.servings = servings; self.hasImage = hasImage
    }
}

// MARK: - Errors

public enum RecipeShareBundleError: Error, LocalizedError, Sendable {
    case encodingFailed
    case archiveCreationFailed
    case bundleFileUnreadable
    case invalidBundleData(String)
    case unsupportedSchemaVersion(Int)

    public var errorDescription: String? {
        switch self {
        case .encodingFailed:
            return "Couldn't package the recipe. Try again."
        case .archiveCreationFailed:
            return "Couldn't create the recipe file. Check available storage."
        case .bundleFileUnreadable:
            return "This file doesn't look like a BiteRecipe recipe. Try sharing again."
        case .invalidBundleData(let detail):
            return "Couldn't load recipe — the file may be corrupted. (\(detail))"
        case .unsupportedSchemaVersion(let v):
            return "This recipe was created with a newer version of BiteRecipe (bundle v\(v)). Please update the app."
        }
    }
}

// MARK: - Service

public struct RecipeShareBundleService: Sendable {

    // MARK: Create Bundle

    /// Builds a .biterecipe ZIP archive and writes it to the App Group tmp/ directory.
    ///
    /// - Parameter imageData: Pre-processed JPEG bytes, or nil. The caller is responsible
    ///   for resizing (BiteLedgerCore has no UIKit dependency). Pass nil for recipes with
    ///   only a remote https:// image — the URL is preserved in recipe.json.
    /// - Returns: URL of the .biterecipe file. **Caller must delete it after the share
    ///   sheet's `completionWithItemsHandler` fires.**
    @MainActor
    public static func createBundle(
        recipe: Recipe,
        context: ModelContext,
        imageData: Data? = nil
    ) throws -> URL {
        let ingredients = recipe.sortedIngredients

        var foodDTOs: [RecipeShareBundle.FoodDTO] = []
        var servingDTOs: [RecipeShareBundle.ServingDTO] = []
        var ingredientDTOs: [RecipeShareBundle.IngredientDTO] = []
        var foodBundleIDs: [UUID: String] = [:]  // PersistentID → bundle-local UUID

        for ingredient in ingredients {
            guard let food = ingredient.foodItem else { continue }

            let bundleID: String
            if let existing = foodBundleIDs[food.id] {
                bundleID = existing
            } else {
                let newID = UUID().uuidString
                bundleID = newID
                foodBundleIDs[food.id] = newID
                foodDTOs.append(RecipeShareBundle.FoodDTO(
                    bundleID: newID,
                    name: food.name,
                    brand: food.brand,
                    source: food.source,
                    nutritionMode: food.nutritionMode.rawValue,
                    calories: food.calories,
                    protein: food.protein,
                    carbs: food.carbs,
                    fat: food.fat,
                    fiber: food.fiber,
                    sugar: food.sugar,
                    saturatedFat: food.saturatedFat,
                    transFat: food.transFat,
                    polyunsaturatedFat: food.polyunsaturatedFat,
                    monounsaturatedFat: food.monounsaturatedFat,
                    sodium: food.sodium,
                    cholesterol: food.cholesterol,
                    potassium: food.potassium,
                    calcium: food.calcium,
                    iron: food.iron,
                    magnesium: food.magnesium,
                    zinc: food.zinc,
                    vitaminA: food.vitaminA,
                    vitaminC: food.vitaminC,
                    vitaminD: food.vitaminD,
                    vitaminE: food.vitaminE,
                    vitaminK: food.vitaminK,
                    vitaminB6: food.vitaminB6,
                    vitaminB12: food.vitaminB12,
                    folate: food.folate,
                    choline: food.choline,
                    caffeine: food.caffeine
                ))
                for serving in food.servingSizes {
                    servingDTOs.append(RecipeShareBundle.ServingDTO(
                        foodBundleID: newID,
                        label: serving.label,
                        gramWeight: serving.gramWeight,
                        unit: serving.unit,
                        amount: serving.amount,
                        isDefault: serving.isDefault,
                        sortOrder: serving.sortOrder
                    ))
                }
            }

            ingredientDTOs.append(RecipeShareBundle.IngredientDTO(
                foodBundleID: bundleID,
                servingLabel: ingredient.servingSize?.label,
                quantity: ingredient.quantity,
                rawText: ingredient.rawText,
                recipeQuantity: ingredient.recipeQuantity,
                recipeUnit: ingredient.recipeUnit,
                sortOrder: ingredient.sortOrder
            ))
        }

        let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown"
        let manifest = RecipeShareBundle.Manifest(
            schemaVersion: 1,
            exportDate: ISO8601DateFormatter().string(from: Date()),
            senderAppVersion: appVersion
        )

        // Only https:// URLs are portable across devices; file:// paths are meaningless on the receiver
        let portableImageURL: String?
        if let url = recipe.imageURL, url.hasPrefix("http") {
            portableImageURL = url
        } else {
            portableImageURL = nil
        }

        let recipeDTO = RecipeShareBundle.RecipeDTO(
            name: recipe.name,
            servingsYield: recipe.servingsYield,
            sourceURL: recipe.sourceURL,
            directions: recipe.directions,
            prepMinutes: recipe.prepMinutes,
            cookMinutes: recipe.cookMinutes,
            totalMinutes: recipe.totalMinutes,
            recipeDescription: recipe.recipeDescription,
            recipeCategory: recipe.recipeCategory,
            recipeCuisine: recipe.recipeCuisine,
            author: recipe.author,
            ratingValue: recipe.ratingValue,
            ratingCount: recipe.ratingCount,
            keywords: recipe.keywords,
            dietTags: recipe.dietTags,
            imageURL: portableImageURL
        )

        // Write JSON files to a staging directory, then ZIP into the final archive
        let staging = FileManager.default.temporaryDirectory
            .appendingPathComponent("BRShare_\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: staging) }

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        func writeJSON<T: Encodable>(_ value: T, filename: String) throws {
            let data = try encoder.encode(value)
            try data.write(to: staging.appendingPathComponent(filename))
        }

        do {
            try writeJSON(manifest,        filename: "manifest.json")
            try writeJSON(recipeDTO,       filename: "recipe.json")
            try writeJSON(ingredientDTOs,  filename: "ingredients.json")
            try writeJSON(foodDTOs,        filename: "foods.json")
            try writeJSON(servingDTOs,     filename: "servings.json")
        } catch {
            throw RecipeShareBundleError.encodingFailed
        }

        if let jpegData = imageData {
            try jpegData.write(to: staging.appendingPathComponent("image.jpg"))
        }

        // Determine output path (App Group tmp/ dir if available, else system temp)
        let groupID = RecipeImportService.sharedAppGroupIdentifier
        let outputDir: URL
        if let groupURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: groupID) {
            outputDir = groupURL.appendingPathComponent("tmp", isDirectory: true)
            try? FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)
        } else {
            outputDir = FileManager.default.temporaryDirectory
        }

        let safeName = recipe.name
            .components(separatedBy: CharacterSet(charactersIn: "/\\:?*\"<>|"))
            .joined(separator: "_")
            .trimmingCharacters(in: .whitespaces)
        let filename = "\(safeName.isEmpty ? "recipe" : safeName)-\(UUID().uuidString.prefix(8)).biterecipe"
        let archiveURL = outputDir.appendingPathComponent(filename)
        try? FileManager.default.removeItem(at: archiveURL)   // remove stale file

        do {
            let archive = try Archive(url: archiveURL, accessMode: .create)
            let enumerator = FileManager.default.enumerator(
                at: staging,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles]
            )
            while let fileURL = enumerator?.nextObject() as? URL {
                guard let rv = try? fileURL.resourceValues(forKeys: [.isRegularFileKey]),
                      rv.isRegularFile == true else { continue }
                let relativePath = String(fileURL.path.dropFirst(staging.path.count + 1))
                try archive.addEntry(with: relativePath, fileURL: fileURL)
            }
        } catch {
            throw RecipeShareBundleError.archiveCreationFailed
        }

        return archiveURL
    }

    // MARK: Parse Bundle

    /// Parses a .biterecipe ZIP file into a `RecipeShareBundle` value.
    /// Pure function — no SwiftData context needed, safe to call off main actor.
    public static func parseBundle(at url: URL) throws -> RecipeShareBundle {
        let archive: Archive
        do {
            archive = try Archive(url: url, accessMode: .read)
        } catch {
            throw RecipeShareBundleError.bundleFileUnreadable
        }

        func readJSON<T: Decodable>(_ filename: String, as type: T.Type) throws -> T {
            guard let entry = archive[filename] else {
                throw RecipeShareBundleError.invalidBundleData("missing \(filename)")
            }
            var data = Data()
            _ = try archive.extract(entry) { data.append($0) }
            do {
                return try JSONDecoder().decode(type, from: data)
            } catch {
                throw RecipeShareBundleError.invalidBundleData("malformed \(filename): \(error.localizedDescription)")
            }
        }

        let manifest     = try readJSON("manifest.json",     as: RecipeShareBundle.Manifest.self)
        guard manifest.schemaVersion <= 1 else {
            throw RecipeShareBundleError.unsupportedSchemaVersion(manifest.schemaVersion)
        }
        let recipe       = try readJSON("recipe.json",       as: RecipeShareBundle.RecipeDTO.self)
        let ingredients  = try readJSON("ingredients.json",  as: [RecipeShareBundle.IngredientDTO].self)
        let foods        = try readJSON("foods.json",        as: [RecipeShareBundle.FoodDTO].self)
        let servings     = try readJSON("servings.json",     as: [RecipeShareBundle.ServingDTO].self)
        let hasImage     = archive["image.jpg"] != nil

        return RecipeShareBundle(
            manifest: manifest,
            recipe: recipe,
            ingredients: ingredients,
            foods: foods,
            servings: servings,
            hasImage: hasImage
        )
    }

    /// Extracts the image.jpg bytes from an archive, or nil if not present.
    public static func extractImageData(from url: URL) -> Data? {
        do {
            let archive = try Archive(url: url, accessMode: .read)
            guard let entry = archive["image.jpg"] else { return nil }
            var data = Data()
            _ = try archive.extract(entry) { data.append($0) }
            return data.isEmpty ? nil : data
        } catch {
            return nil
        }
    }

    // MARK: Import Bundle

    /// Inserts all bundle content into the SwiftData context and returns the new Recipe.
    ///
    /// - Parameters:
    ///   - imageData: JPEG bytes extracted from the archive (caller calls `extractImageData`).
    ///   - replacing: If non-nil, this Recipe is deleted before inserting the new one (Replace mode).
    ///     Pass nil for Keep Both — both the old and new Recipe survive.
    @MainActor
    public static func importBundle(
        _ bundle: RecipeShareBundle,
        imageData: Data?,
        into context: ModelContext,
        replacing duplicate: Recipe? = nil
    ) throws -> Recipe {

        if let dup = duplicate {
            if let url = dup.imageURL { RecipeImportService.deleteLocalImage(urlString: url) }
            context.delete(dup)
        }

        // Build food map: bundleID → FoodItem (silent dedup by name + source)
        var foodMap: [String: FoodItem] = [:]
        for fDTO in bundle.foods {
            if let existing = try findExistingFood(name: fDTO.name, source: fDTO.source, in: context) {
                foodMap[fDTO.bundleID] = existing
            } else {
                let mode = NutritionMode(rawValue: fDTO.nutritionMode) ?? .perServing
                let food = FoodItem(
                    name: fDTO.name,
                    brand: fDTO.brand,
                    source: fDTO.source,
                    nutritionMode: mode,
                    calories: fDTO.calories,
                    protein: fDTO.protein,
                    carbs: fDTO.carbs,
                    fat: fDTO.fat,
                    fiber: fDTO.fiber,
                    sugar: fDTO.sugar,
                    saturatedFat: fDTO.saturatedFat,
                    transFat: fDTO.transFat,
                    polyunsaturatedFat: fDTO.polyunsaturatedFat,
                    monounsaturatedFat: fDTO.monounsaturatedFat,
                    sodium: fDTO.sodium,
                    cholesterol: fDTO.cholesterol,
                    potassium: fDTO.potassium,
                    calcium: fDTO.calcium,
                    iron: fDTO.iron,
                    magnesium: fDTO.magnesium,
                    zinc: fDTO.zinc,
                    vitaminA: fDTO.vitaminA,
                    vitaminC: fDTO.vitaminC,
                    vitaminD: fDTO.vitaminD,
                    vitaminE: fDTO.vitaminE,
                    vitaminK: fDTO.vitaminK,
                    vitaminB6: fDTO.vitaminB6,
                    vitaminB12: fDTO.vitaminB12,
                    folate: fDTO.folate,
                    choline: fDTO.choline,
                    caffeine: fDTO.caffeine
                )
                context.insert(food)
                foodMap[fDTO.bundleID] = food
            }
        }

        // Build serving map: foodBundleID → (label → ServingSize)
        var servingMap: [String: [String: ServingSize]] = [:]
        for sDTO in bundle.servings {
            guard let food = foodMap[sDTO.foodBundleID] else { continue }
            if let existing = food.servingSizes.first(where: { $0.label == sDTO.label }) {
                servingMap[sDTO.foodBundleID, default: [:]][sDTO.label] = existing
            } else {
                let serving = ServingSize(
                    label: sDTO.label,
                    gramWeight: sDTO.gramWeight,
                    isDefault: sDTO.isDefault,
                    sortOrder: sDTO.sortOrder,
                    unit: sDTO.unit,
                    amount: sDTO.amount
                )
                food.servingSizes.append(serving)
                context.insert(serving)
                servingMap[sDTO.foodBundleID, default: [:]][sDTO.label] = serving
            }
        }

        // Resolve final image URL
        var finalImageURL: String? = nil
        if let jpegData = imageData {
            finalImageURL = RecipeImportService.saveImageDataLocally(jpegData)
        } else if let remoteURL = bundle.recipe.imageURL, remoteURL.hasPrefix("http") {
            finalImageURL = remoteURL
        }

        // Create Recipe
        let rDTO = bundle.recipe
        let recipe = Recipe(
            name: rDTO.name,
            servingsYield: rDTO.servingsYield,
            sourceURL: rDTO.sourceURL,
            directions: rDTO.directions
        )
        recipe.prepMinutes       = rDTO.prepMinutes
        recipe.cookMinutes       = rDTO.cookMinutes
        recipe.totalMinutes      = rDTO.totalMinutes
        recipe.recipeDescription = rDTO.recipeDescription
        recipe.recipeCategory    = rDTO.recipeCategory
        recipe.recipeCuisine     = rDTO.recipeCuisine
        recipe.author            = rDTO.author
        recipe.ratingValue       = rDTO.ratingValue
        recipe.ratingCount       = rDTO.ratingCount
        recipe.keywords          = rDTO.keywords
        recipe.dietTags          = rDTO.dietTags
        recipe.imageURL          = finalImageURL
        context.insert(recipe)

        // Create RecipeIngredients
        for iDTO in bundle.ingredients.sorted(by: { $0.sortOrder < $1.sortOrder }) {
            guard let food = foodMap[iDTO.foodBundleID] else { continue }
            let ingredient = RecipeIngredient(
                quantity: iDTO.quantity,
                sortOrder: iDTO.sortOrder,
                recipeQuantity: iDTO.recipeQuantity,
                recipeUnit: iDTO.recipeUnit
            )
            ingredient.rawText  = iDTO.rawText
            ingredient.recipe   = recipe
            ingredient.foodItem = food
            if let label = iDTO.servingLabel {
                ingredient.servingSize = servingMap[iDTO.foodBundleID]?[label]
                    ?? food.servingSizes.first(where: { $0.label == label })
            }
            context.insert(ingredient)
            recipe.ingredients.append(ingredient)
        }

        return recipe
    }

    // MARK: Duplicate Detection

    /// Returns the first existing Recipe whose name or sourceURL matches the bundle.
    @MainActor
    public static func findDuplicate(for bundle: RecipeShareBundle, in context: ModelContext) throws -> Recipe? {
        let name = bundle.recipe.name.lowercased()
        let sourceURL = bundle.recipe.sourceURL
        let all = try context.fetch(FetchDescriptor<Recipe>())
        return all.first { r in
            r.name.lowercased() == name
            || (sourceURL != nil && r.sourceURL != nil && r.sourceURL == sourceURL)
        }
    }

    // MARK: Private Helpers

    @MainActor
    private static func findExistingFood(name: String, source: String, in context: ModelContext) throws -> FoodItem? {
        let lower = name.lowercased()
        let sourceLower = source.lowercased()
        let all = try context.fetch(FetchDescriptor<FoodItem>())
        return all.first { $0.name.lowercased() == lower && $0.source.lowercased() == sourceLower }
    }
}
