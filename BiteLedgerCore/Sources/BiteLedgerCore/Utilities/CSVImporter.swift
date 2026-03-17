//
//  CSVImporter.swift
//  BiteLedger
//
//  Created by Craig Faist on 2/27/26.
//


import Foundation
import SwiftData

// MARK: - CSVImporter
//
// Handles two import formats:
//   1. LoseIt export (single CSV with daily logs)
//   2. BiteLedger full export (three CSVs: foods, servings, logs)

public struct CSVImporter {

    // MARK: - Errors

    public enum ImportError: LocalizedError {
        case fileNotFound
        case invalidFormat(String)
        case missingRequiredColumn(String)
        case parseError(row: Int, message: String)

        public var errorDescription: String? {
            switch self {
            case .fileNotFound:
                return "File not found."
            case .invalidFormat(let detail):
                return "Invalid format: \(detail)"
            case .missingRequiredColumn(let col):
                return "Missing required column: \(col)"
            case .parseError(let row, let msg):
                return "Parse error on row \(row): \(msg)"
            }
        }
    }

    // MARK: - Import Result

    public struct ImportResult: Sendable {
        public var foodsCreated: Int = 0
        public var foodsSkipped: Int = 0
        public var servingsCreated: Int = 0
        public var logsCreated: Int = 0
        public var errors: [String] = []

        public init() {}

        public var summary: String {
            "Imported \(foodsCreated) foods, \(logsCreated) log entries."
            + (errors.isEmpty ? "" : " \(errors.count) warnings.")
        }
    }

    // MARK: - Auto-Detect Import
    
    /// Auto-detects format and imports accordingly
    @MainActor
    public static func importAuto(
        csvString: String,
        context: ModelContext
    ) throws -> ImportResult {
        // parseCSV auto-detects separator (tab vs comma)
        let rows = parseCSV(csvString)
        guard !rows.isEmpty else {
            throw ImportError.invalidFormat("File appears to be empty.")
        }

        let headers = rows[0].map { $0.lowercased().trimmingCharacters(in: .whitespaces) }
        
        // Check if it's LoseIt format (has "protein (g)" column)
        if headers.contains("protein (g)") {
            return try importLoseIt(csvString: csvString, context: context)
        }
        
        // Check if it's legacy BiteLedger format (has "date" and "time" as separate columns, or has "grams" column)
        if (headers.contains("date") && headers.contains("time")) || headers.contains("grams") {
            return try importLegacyBiteLedger(csvString: csvString, context: context)
        }
        
        // Default to LoseIt
        return try importLoseIt(csvString: csvString, context: context)
    }
    
    // MARK: - LoseIt Import

    /// Imports a LoseIt export CSV file.
    ///
    /// LoseIt format (tab-separated, columns matched by header name):
    ///   Date, Name, Icon, Meal, Quantity, Units, Calories, Deleted,
    ///   Fat (g), Protein (g), Carbohydrates (g), Saturated Fat (g),
    ///   Sugars (g), Fiber (g), Cholesterol (mg), Sodium (mg)
    ///
    /// - All LoseIt foods are imported as nutritionMode = .perServing
    /// - Nutrition in each row is the total for the logged quantity;
    ///   it is normalized to per-1-serving on import
    /// - No gram weights (LoseIt doesn't provide them)
    /// - Rows with Deleted = 1 are skipped
    @MainActor
    public static func importLoseIt(
        csvString: String,
        context: ModelContext
    ) throws -> ImportResult {
        var result = ImportResult()
        // parseCSV auto-detects tab vs comma separator
        let rows = parseCSV(csvString)
        guard !rows.isEmpty else {
            throw ImportError.invalidFormat("File appears to be empty.")
        }

        let headers = rows[0].map { $0.lowercased().trimmingCharacters(in: .whitespaces) }

        // Required columns
        guard
            let nameIdx  = headers.firstIndex(of: "name"),
            let calIdx   = headers.firstIndex(of: "calories"),
            let protIdx  = headers.firstIndex(of: "protein (g)"),
            let carbIdx  = headers.firstIndex(of: "carbohydrates (g)"),
            let fatIdx   = headers.firstIndex(of: "fat (g)"),
            let qtyIdx   = headers.firstIndex(of: "quantity"),
            let unitsIdx = headers.firstIndex(of: "units"),
            let dateIdx  = headers.firstIndex(of: "date")
        else {
            throw ImportError.missingRequiredColumn(
                "Expected LoseIt columns not found (name, calories, protein, carbs, fat, quantity, units, date).")
        }

        // Optional columns — present in modern LoseIt exports
        let mealIdx        = headers.firstIndex(of: "meal")
        let deletedIdx     = headers.firstIndex(of: "deleted")
        let sodiumIdx      = headers.firstIndex(of: "sodium (mg)")
        let cholesterolIdx = headers.firstIndex(of: "cholesterol (mg)")
        let saturatedFatIdx = headers.firstIndex(of: "saturated fat (g)")
        let sugarIdx       = headers.firstIndex(of: "sugars (g)")
        let fiberIdx       = headers.firstIndex(of: "fiber (g)")

        var foodCache: [String: FoodItem] = [:]
        let dateFormatter = DateFormatter()
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")

        // Fetch canonical foods once — used to set canonicalFoodID on new FoodItems.
        let canonicalFoods = (try? context.fetch(FetchDescriptor<CanonicalFood>())) ?? []

        let minIdx = max(nameIdx, calIdx, protIdx, carbIdx, fatIdx, qtyIdx, unitsIdx, dateIdx)

        for (rowIndex, row) in rows.dropFirst().enumerated() {
            let rowNum = rowIndex + 2
            guard row.count > minIdx else {
                result.errors.append("Row \(rowNum): not enough columns, skipped.")
                continue
            }

            // Skip rows the user deleted in LoseIt
            if let dIdx = deletedIdx,
               row[safe: dIdx]?.trimmingCharacters(in: .whitespaces) == "1" {
                continue
            }

            let name    = row[nameIdx].trimmingCharacters(in: .whitespaces)
            let units   = row[unitsIdx].trimmingCharacters(in: .whitespaces)
            let qtyStr  = row[qtyIdx].trimmingCharacters(in: .whitespaces)
            let dateStr = row[dateIdx].trimmingCharacters(in: .whitespaces)

            guard !name.isEmpty else { continue }

            let qty     = Double(qtyStr) ?? 1.0
            let divisor = qty > 0 ? qty : 1.0

            // LoseIt nutrition values are totals for the logged quantity.
            // parseLoseItDouble handles "n/a" → nil gracefully.
            let rawCal    = parseLoseItDouble(row[calIdx])  ?? 0
            let rawProt   = parseLoseItDouble(row[protIdx]) ?? 0
            let rawCarb   = parseLoseItDouble(row[carbIdx]) ?? 0
            let rawFat    = parseLoseItDouble(row[fatIdx])  ?? 0
            let rawSod    = sodiumIdx.flatMap       { parseLoseItDouble(row[safe: $0] ?? "") }
            let rawChol   = cholesterolIdx.flatMap  { parseLoseItDouble(row[safe: $0] ?? "") }
            let rawSatFat = saturatedFatIdx.flatMap { parseLoseItDouble(row[safe: $0] ?? "") }
            let rawSugar  = sugarIdx.flatMap        { parseLoseItDouble(row[safe: $0] ?? "") }
            let rawFiber  = fiberIdx.flatMap        { parseLoseItDouble(row[safe: $0] ?? "") }

            // Normalize to per-1-serving
            let calPer1    = rawCal  / divisor
            let protPer1   = rawProt / divisor
            let carbPer1   = rawCarb / divisor
            let fatPer1    = rawFat  / divisor
            let sodPer1    = rawSod.map    { $0 / divisor }
            let cholPer1   = rawChol.map   { $0 / divisor }
            let satFatPer1 = rawSatFat.map { $0 / divisor }
            let sugarPer1  = rawSugar.map  { $0 / divisor }
            let fiberPer1  = rawFiber.map  { $0 / divisor }

            // Cache key = name + units (e.g., "oatmeal|cups" vs "oatmeal|grams")
            let cacheKey = "\(name.lowercased())|\(units.lowercased())"

            let food: FoodItem
            if let cached = foodCache[cacheKey] {
                food = cached
                result.foodsSkipped += 1
            } else {
                // Match on both name AND units so "Life Cereal (Cups)" and
                // "Life Cereal (Grams)" are kept as separate FoodItems.
                let existingFood = findLoseItFood(name: name, units: units, context: context)
                if let existing = existingFood {
                    food = existing
                    result.foodsSkipped += 1
                } else {
                    food = FoodItem(
                        name: name,
                        source: "LoseIt Import",
                        nutritionMode: .perServing,
                        calories: calPer1,
                        protein: protPer1,
                        carbs: carbPer1,
                        fat: fatPer1,
                        fiber: fiberPer1,
                        sugar: sugarPer1,
                        saturatedFat: satFatPer1,
                        sodium: sodPer1,
                        cholesterol: cholPer1
                    )
                    // No gram data from LoseIt — normalize with 100g nominal (factor = 1.0)
                    food.normalizeToPerHundredGrams(gramWeightPerServing: nil)
                    food.canonicalFoodID = CanonicalFoodMatcher.match(
                        foodName: name, in: canonicalFoods
                    )?.id
                    context.insert(food)

                    let (servingLabel, servingUnit): (String, String?)
                    if units.isEmpty {
                        servingLabel = "1 serving"
                        servingUnit = ServingUnit.serving.rawValue
                    } else if let knownUnit = ServingSizeParser.parseUnit(units) {
                        servingLabel = "1 \(knownUnit.abbreviation)"
                        servingUnit = knownUnit.rawValue
                    } else {
                        servingLabel = "1 \(units)"
                        servingUnit = nil
                    }
                    let serving = ServingSize(
                        label: servingLabel,
                        gramWeight: 100.0,
                        isDefault: true,
                        sortOrder: 0,
                        unit: servingUnit
                    )
                    serving.foodItem = food
                    context.insert(serving)
                    result.servingsCreated += 1
                    result.foodsCreated += 1
                }
                foodCache[cacheKey] = food
            }

            // Parse date — LoseIt uses M/d/yy (two-digit year)
            let timestamp = parseDate(dateStr, formatter: dateFormatter) ?? Date()

            // Meal type from "Meal" column (Breakfast / Lunch / Dinner / Snacks)
            let mealStr  = mealIdx.flatMap { row[safe: $0]?.trimmingCharacters(in: .whitespaces) } ?? ""
            let mealType = mealTypeFromLoseIt(mealStr)

            let serving = food.defaultServing ?? food.servingSizes.first
            let log = FoodLog.create(
                mealType: mealType,
                quantity: qty,
                food: food,
                serving: serving,
                timestamp: timestamp
            )
            context.insert(log)
            result.logsCreated += 1
        }

        try context.save()
        return result
    }

    // MARK: - LoseIt Enriched Import

    /// Same as importLoseIt but applies USDA micronutrients to each FoodItem
    /// before FoodLog.create() is called, so *AtLogTime fields capture the full
    /// nutrition naturally — no retroactive patching needed.
    ///
    /// - Parameter enrichmentMap: keyed by "name|units" (lowercased), value is
    ///   the accepted USDAFoodItem whose per-100g nutrients will be scaled to
    ///   the LoseIt per-serving calorie ratio.
    @MainActor
    public static func importLoseItEnriched(
        csvString: String,
        enrichmentMap: [String: USDAFoodItem],
        fatSecretMap: [String: FatSecretServingData] = [:],
        manualMap: [String: ManualNutrientOverride] = [:],
        fallbackSourceMap: [String: FallbackSourceInfo] = [:],
        context: ModelContext
    ) throws -> ImportResult {
        var result = ImportResult()
        let rows = parseCSV(csvString)
        guard !rows.isEmpty else {
            throw ImportError.invalidFormat("File appears to be empty.")
        }

        let headers = rows[0].map { $0.lowercased().trimmingCharacters(in: .whitespaces) }

        guard
            let nameIdx  = headers.firstIndex(of: "name"),
            let calIdx   = headers.firstIndex(of: "calories"),
            let protIdx  = headers.firstIndex(of: "protein (g)"),
            let carbIdx  = headers.firstIndex(of: "carbohydrates (g)"),
            let fatIdx   = headers.firstIndex(of: "fat (g)"),
            let qtyIdx   = headers.firstIndex(of: "quantity"),
            let unitsIdx = headers.firstIndex(of: "units"),
            let dateIdx  = headers.firstIndex(of: "date")
        else {
            throw ImportError.missingRequiredColumn(
                "Expected LoseIt columns not found.")
        }

        let mealIdx         = headers.firstIndex(of: "meal")
        let deletedIdx      = headers.firstIndex(of: "deleted")
        let sodiumIdx       = headers.firstIndex(of: "sodium (mg)")
        let cholesterolIdx  = headers.firstIndex(of: "cholesterol (mg)")
        let saturatedFatIdx = headers.firstIndex(of: "saturated fat (g)")
        let sugarIdx        = headers.firstIndex(of: "sugars (g)")
        let fiberIdx        = headers.firstIndex(of: "fiber (g)")

        var foodCache: [String: FoodItem] = [:]
        let dateFormatter = DateFormatter()
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")

        // Fetch canonical foods once — used to set canonicalFoodID on new FoodItems.
        let canonicalFoodsEnriched = (try? context.fetch(FetchDescriptor<CanonicalFood>())) ?? []

        let minIdx = max(nameIdx, calIdx, protIdx, carbIdx, fatIdx, qtyIdx, unitsIdx, dateIdx)

        for (rowIndex, row) in rows.dropFirst().enumerated() {
            let rowNum = rowIndex + 2
            guard row.count > minIdx else {
                result.errors.append("Row \(rowNum): not enough columns, skipped.")
                continue
            }

            if let dIdx = deletedIdx,
               row[safe: dIdx]?.trimmingCharacters(in: .whitespaces) == "1" { continue }

            let name    = row[nameIdx].trimmingCharacters(in: .whitespaces)
            let units   = row[unitsIdx].trimmingCharacters(in: .whitespaces)
            let qtyStr  = row[qtyIdx].trimmingCharacters(in: .whitespaces)
            let dateStr = row[dateIdx].trimmingCharacters(in: .whitespaces)

            guard !name.isEmpty else { continue }

            let qty     = Double(qtyStr) ?? 1.0
            let divisor = qty > 0 ? qty : 1.0

            let rawCal    = parseLoseItDouble(row[calIdx])  ?? 0
            let rawProt   = parseLoseItDouble(row[protIdx]) ?? 0
            let rawCarb   = parseLoseItDouble(row[carbIdx]) ?? 0
            let rawFat    = parseLoseItDouble(row[fatIdx])  ?? 0
            let rawSod    = sodiumIdx.flatMap       { parseLoseItDouble(row[safe: $0] ?? "") }
            let rawChol   = cholesterolIdx.flatMap  { parseLoseItDouble(row[safe: $0] ?? "") }
            let rawSatFat = saturatedFatIdx.flatMap { parseLoseItDouble(row[safe: $0] ?? "") }
            let rawSugar  = sugarIdx.flatMap        { parseLoseItDouble(row[safe: $0] ?? "") }
            let rawFiber  = fiberIdx.flatMap        { parseLoseItDouble(row[safe: $0] ?? "") }

            let calPer1    = rawCal  / divisor
            let protPer1   = rawProt / divisor
            let carbPer1   = rawCarb / divisor
            let fatPer1    = rawFat  / divisor
            let sodPer1    = rawSod.map    { $0 / divisor }
            let cholPer1   = rawChol.map   { $0 / divisor }
            let satFatPer1 = rawSatFat.map { $0 / divisor }
            let sugarPer1  = rawSugar.map  { $0 / divisor }
            let fiberPer1  = rawFiber.map  { $0 / divisor }

            let cacheKey = "\(name.lowercased())|\(units.lowercased())"

            let food: FoodItem
            if let cached = foodCache[cacheKey] {
                food = cached
                result.foodsSkipped += 1
            } else {
                let existingFood = findLoseItFood(name: name, units: units, context: context)
                if let existing = existingFood {
                    food = existing
                    result.foodsSkipped += 1
                } else {
                    food = FoodItem(
                        name: name,
                        source: "LoseIt Import",
                        nutritionMode: .perServing,
                        calories: calPer1,
                        protein: protPer1,
                        carbs: carbPer1,
                        fat: fatPer1,
                        fiber: fiberPer1,
                        sugar: sugarPer1,
                        saturatedFat: satFatPer1,
                        sodium: sodPer1,
                        cholesterol: cholPer1
                    )
                    context.insert(food)

                    // Apply USDA micronutrients if a match was accepted.
                    // Scale factor = loseIt_cal_per_serving / usda_cal_per_100g
                    // This estimates grams per serving without needing a gramWeight.
                    if let usdaFood = enrichmentMap[cacheKey] {
                        let micros = usdaFood.microsPer100g
                        if micros.caloriesPer100g > 0 && calPer1 > 0 {
                            let scale = calPer1 / micros.caloriesPer100g
                            food.potassium  = micros.potassium.map  { $0 * scale }
                            food.calcium    = micros.calcium.map    { $0 * scale }
                            food.iron       = micros.iron.map       { $0 * scale }
                            food.magnesium  = micros.magnesium.map  { $0 * scale }
                            food.zinc       = micros.zinc.map       { $0 * scale }
                            food.vitaminA   = micros.vitaminA.map   { $0 * scale }
                            food.vitaminC   = micros.vitaminC.map   { $0 * scale }
                            food.vitaminD   = micros.vitaminD.map   { $0 * scale }
                            food.vitaminE   = micros.vitaminE.map   { $0 * scale }
                            food.vitaminK   = micros.vitaminK.map   { $0 * scale }
                            food.vitaminB6  = micros.vitaminB6.map  { $0 * scale }
                            food.vitaminB12 = micros.vitaminB12.map { $0 * scale }
                            food.folate     = micros.folate.map     { $0 * scale }
                            food.choline    = micros.choline.map    { $0 * scale }
                            food.caffeine   = micros.caffeine.map   { $0 * scale }
                        }
                    }

                    // FatSecret fallback: potassium + vitamins via % DV conversion
                    if enrichmentMap[cacheKey] == nil,
                       let fsData = fatSecretMap[cacheKey] {
                        food.potassium = fsData.potassiumMg
                        food.calcium   = fsData.calciumMg
                        food.iron      = fsData.ironMg
                        food.vitaminA  = fsData.vitaminAMcg
                        food.vitaminC  = fsData.vitaminCMg
                    }

                    // Manual override: user-entered per-serving values applied directly
                    if enrichmentMap[cacheKey] == nil, fatSecretMap[cacheKey] == nil,
                       let manual = manualMap[cacheKey] {
                        food.potassium  = manual.potassium
                        food.calcium    = manual.calcium
                        food.iron       = manual.iron
                        food.magnesium  = manual.magnesium
                        food.zinc       = manual.zinc
                        food.vitaminA   = manual.vitaminA
                        food.vitaminC   = manual.vitaminC
                        food.vitaminD   = manual.vitaminD
                        food.vitaminE   = manual.vitaminE
                        food.vitaminK   = manual.vitaminK
                        food.vitaminB6  = manual.vitaminB6
                        food.vitaminB12 = manual.vitaminB12
                        food.folate     = manual.folate
                        food.choline    = manual.choline
                        food.caffeine   = manual.caffeine
                    }

                    // Normalize to per-100g after all enrichment writes.
                    // 100g nominal: factor = 1.0, values unchanged, mode → per100g.
                    food.normalizeToPerHundredGrams(gramWeightPerServing: nil)
                    food.canonicalFoodID = CanonicalFoodMatcher.match(
                        foodName: name, in: canonicalFoodsEnriched
                    )?.id

                    // Persist a FallbackSource record so data provenance survives the import.
                    if let info = fallbackSourceMap[cacheKey] {
                        let source = FallbackSource(
                            sourceType: info.sourceType,
                            externalID: info.externalID,
                            externalName: info.externalName,
                            confidence: info.confidence
                        )
                        context.insert(source)
                        food.fallbackSourceID = source.id
                    }

                    let (servingLabel, servingUnit): (String, String?)
                    if units.isEmpty {
                        servingLabel = "1 serving"
                        servingUnit = ServingUnit.serving.rawValue
                    } else if let knownUnit = ServingSizeParser.parseUnit(units) {
                        servingLabel = "1 \(knownUnit.abbreviation)"
                        servingUnit = knownUnit.rawValue
                    } else {
                        servingLabel = "1 \(units)"
                        servingUnit = nil
                    }
                    let serving = ServingSize(
                        label: servingLabel,
                        gramWeight: 100.0,
                        isDefault: true,
                        sortOrder: 0,
                        unit: servingUnit
                    )
                    serving.foodItem = food
                    context.insert(serving)
                    result.servingsCreated += 1
                    result.foodsCreated += 1
                }
                foodCache[cacheKey] = food
            }

            let timestamp = parseDate(dateStr, formatter: dateFormatter) ?? Date()
            let mealStr   = mealIdx.flatMap { row[safe: $0]?.trimmingCharacters(in: .whitespaces) } ?? ""
            let mealType  = mealTypeFromLoseIt(mealStr)
            let serving   = food.defaultServing ?? food.servingSizes.first
            let log = FoodLog.create(
                mealType: mealType,
                quantity: qty,
                food: food,
                serving: serving,
                timestamp: timestamp
            )
            context.insert(log)
            result.logsCreated += 1
        }

        try context.save()
        return result
    }

    // MARK: - BiteLedger Full Import

    /// Imports BiteLedger's own 3-file export format for full round-trip restore.
    ///
    /// Pass the contents of all three CSV files.
    /// Import order: foods → servings → logs (maintains referential integrity)
    @MainActor
    public static func importBiteLedger(
        foodsCSV: String,
        servingsCSV: String,
        logsCSV: String,
        context: ModelContext
    ) throws -> ImportResult {
        var result = ImportResult()

        // 1. Import foods first
        let foodMap = try importBiteLedgerFoods(csv: foodsCSV, context: context, result: &result)

        // 2. Import servings, linking to foods by ID
        let servingMap = try importBiteLedgerServings(csv: servingsCSV, foodMap: foodMap, context: context, result: &result)

        // 3. Import logs, linking to foods and servings by ID
        try importBiteLedgerLogs(csv: logsCSV, foodMap: foodMap, servingMap: servingMap, context: context, result: &result)

        try context.save()
        return result
    }

    // MARK: - BiteLedger Foods Import

    @MainActor
    private static func importBiteLedgerFoods(
        csv: String,
        context: ModelContext,
        result: inout ImportResult
    ) throws -> [UUID: FoodItem] {
        let rows = parseCSV(csv)
        guard !rows.isEmpty else { return [:] }

        let headers = rows[0].map { $0.lowercased().trimmingCharacters(in: .whitespaces) }

        // Required columns
        guard
            let idIdx       = headers.firstIndex(of: "id"),
            let nameIdx     = headers.firstIndex(of: "name"),
            let modeIdx     = headers.firstIndex(of: "nutritionmode"),
            let calIdx      = headers.firstIndex(of: "calories"),
            let protIdx     = headers.firstIndex(of: "protein"),
            let carbIdx     = headers.firstIndex(of: "carbs"),
            let fatIdx      = headers.firstIndex(of: "fat")
        else {
            throw ImportError.missingRequiredColumn("foods.csv missing required columns")
        }

        var foodMap: [UUID: FoodItem] = [:]

        for row in rows.dropFirst() {
            guard row.count > max(idIdx, nameIdx, modeIdx, calIdx, protIdx, carbIdx, fatIdx) else { continue }

            guard
                let id = UUID(uuidString: row[idIdx]),
                !row[nameIdx].isEmpty
            else { continue }

            let mode: NutritionMode = row[modeIdx] == "per100g" ? .per100g : .perServing

            func col(_ name: String) -> Double? {
                headers.firstIndex(of: name).flatMap { Double(row[safe: $0] ?? "") }
            }

            let food = FoodItem(
                id: id,
                name: row[nameIdx],
                brand: headers.firstIndex(of: "brand").flatMap { row[safe: $0] }.flatMap { $0.isEmpty ? nil : $0 },
                barcode: headers.firstIndex(of: "barcode").flatMap { row[safe: $0] }.flatMap { $0.isEmpty ? nil : $0 },
                source: headers.firstIndex(of: "source").flatMap { row[safe: $0] } ?? "CSV Import",
                nutritionMode: mode,
                calories: Double(row[calIdx]) ?? 0,
                protein: Double(row[protIdx]) ?? 0,
                carbs: Double(row[carbIdx]) ?? 0,
                fat: Double(row[fatIdx]) ?? 0,
                fiber:               col("fiber"),
                sugar:               col("sugar"),
                saturatedFat:        col("saturatedfat"),
                transFat:            col("transfat"),
                polyunsaturatedFat:  col("polyunsaturatedfat"),
                monounsaturatedFat:  col("monounsaturatedfat"),
                sodium:              col("sodium"),
                cholesterol:         col("cholesterol"),
                potassium:           col("potassium"),
                calcium:             col("calcium"),
                iron:                col("iron"),
                magnesium:           col("magnesium"),
                zinc:                col("zinc"),
                vitaminA:            col("vitamina"),
                vitaminC:            col("vitaminc"),
                vitaminD:            col("vitamind"),
                vitaminE:            col("vitamine"),
                vitaminK:            col("vitamink"),
                vitaminB6:           col("vitaminb6"),
                vitaminB12:          col("vitaminb12"),
                folate:              col("folate"),
                choline:             col("choline"),
                caffeine:            col("caffeine")
            )
            context.insert(food)
            foodMap[id] = food
            result.foodsCreated += 1
        }

        return foodMap
    }

    // MARK: - BiteLedger Servings Import

    @MainActor
    private static func importBiteLedgerServings(
        csv: String,
        foodMap: [UUID: FoodItem],
        context: ModelContext,
        result: inout ImportResult
    ) throws -> [UUID: ServingSize] {
        let rows = parseCSV(csv)
        guard !rows.isEmpty else { return [:] }

        let headers = rows[0].map { $0.lowercased().trimmingCharacters(in: .whitespaces) }

        guard
            let idIdx       = headers.firstIndex(of: "id"),
            let foodIdIdx   = headers.firstIndex(of: "foodid"),
            let labelIdx    = headers.firstIndex(of: "label"),
            let defaultIdx  = headers.firstIndex(of: "isdefault"),
            let orderIdx    = headers.firstIndex(of: "sortorder")
        else {
            throw ImportError.missingRequiredColumn("servings.csv missing required columns")
        }

        let gramIdx = headers.firstIndex(of: "gramweight")
        let unitIdx = headers.firstIndex(of: "unit")
        var servingMap: [UUID: ServingSize] = [:]

        for row in rows.dropFirst() {
            guard row.count > max(idIdx, foodIdIdx, labelIdx, defaultIdx, orderIdx) else { continue }
            guard
                let id = UUID(uuidString: row[idIdx]),
                let foodId = UUID(uuidString: row[foodIdIdx]),
                let food = foodMap[foodId]
            else { continue }

            let storedUnit = unitIdx.flatMap { row[safe: $0] }.flatMap { $0.isEmpty ? nil : $0 }
            let serving = ServingSize(
                id: id,
                label: row[labelIdx],
                gramWeight: gramIdx.flatMap { Double(row[safe: $0] ?? "") },
                isDefault: row[defaultIdx].lowercased() == "true",
                sortOrder: Int(row[orderIdx]) ?? 0,
                unit: storedUnit
            )
            serving.foodItem = food
            context.insert(serving)
            servingMap[id] = serving
            result.servingsCreated += 1
        }

        return servingMap
    }

    // MARK: - BiteLedger Logs Import

    @MainActor
    private static func importBiteLedgerLogs(
        csv: String,
        foodMap: [UUID: FoodItem],
        servingMap: [UUID: ServingSize],
        context: ModelContext,
        result: inout ImportResult
    ) throws {
        let rows = parseCSV(csv)
        guard !rows.isEmpty else { return }

        let headers = rows[0].map { $0.lowercased().trimmingCharacters(in: .whitespaces) }

        guard
            let foodIdIdx = headers.firstIndex(of: "foodid"),
            let mealIdx   = headers.firstIndex(of: "mealtype"),
            let qtyIdx    = headers.firstIndex(of: "quantity"),
            let tsIdx     = headers.firstIndex(of: "timestamp"),
            let calIdx    = headers.firstIndex(of: "caloriesatlogtime"),
            let protIdx   = headers.firstIndex(of: "proteinatlogtime"),
            let carbIdx   = headers.firstIndex(of: "carbsatlogtime"),
            let fatIdx    = headers.firstIndex(of: "fatatlogtime")
        else {
            throw ImportError.missingRequiredColumn("logs.csv missing required columns")
        }

        let servingIdIdx = headers.firstIndex(of: "servingid")
        let dateFormatter = ISO8601DateFormatter()

        func col(_ name: String, row: [String]) -> Double? {
            headers.firstIndex(of: name).flatMap { Double(row[safe: $0] ?? "") }
        }

        for row in rows.dropFirst() {
            guard row.count > max(foodIdIdx, mealIdx, qtyIdx, tsIdx, calIdx, protIdx, carbIdx, fatIdx) else { continue }
            guard
                let foodId = UUID(uuidString: row[foodIdIdx]),
                let food = foodMap[foodId]
            else { continue }

            let mealType  = MealType(rawValue: row[mealIdx]) ?? .snack
            let quantity  = Double(row[qtyIdx]) ?? 1.0
            let timestamp = dateFormatter.date(from: row[tsIdx]) ?? Date()

            // Resolve the serving that was active when the log was created
            let serving: ServingSize? = servingIdIdx.flatMap { idx in
                guard let uuidStr = row[safe: idx], !uuidStr.isEmpty,
                      let uuid = UUID(uuidString: uuidStr) else { return nil }
                return servingMap[uuid]
            }

            // Restore frozen nutrition directly — do NOT recalculate
            let log = FoodLog(
                timestamp: timestamp,
                mealType: mealType,
                quantity: quantity,
                foodItem: food,
                servingSize: serving,
                caloriesAtLogTime:            Double(row[calIdx]) ?? 0,
                proteinAtLogTime:             Double(row[protIdx]) ?? 0,
                carbsAtLogTime:               Double(row[carbIdx]) ?? 0,
                fatAtLogTime:                 Double(row[fatIdx]) ?? 0,
                fiberAtLogTime:               col("fiberatlogtime", row: row),
                sodiumAtLogTime:              col("sodiumatlogtime", row: row),
                sugarAtLogTime:               col("sugaratlogtime", row: row),
                saturatedFatAtLogTime:        col("saturatedfatatlogtime", row: row),
                transFatAtLogTime:            col("transfatatlogtime", row: row),
                monounsaturatedFatAtLogTime:  col("monounsaturatedfatatlogtime", row: row),
                polyunsaturatedFatAtLogTime:  col("polyunsaturatedfatatlogtime", row: row),
                cholesterolAtLogTime:         col("cholesterolatlogtime", row: row),
                potassiumAtLogTime:           col("potassiumatlogtime", row: row),
                calciumAtLogTime:             col("calciumatlogtime", row: row),
                ironAtLogTime:                col("ironatlogtime", row: row),
                magnesiumAtLogTime:           col("magnesiumatlogtime", row: row),
                zincAtLogTime:                col("zincatlogtime", row: row),
                vitaminAAtLogTime:            col("vitaminaatlogtime", row: row),
                vitaminCAtLogTime:            col("vitamincatlogtime", row: row),
                vitaminDAtLogTime:            col("vitamindatlogtime", row: row),
                vitaminEAtLogTime:            col("vitamineatlogtime", row: row),
                vitaminKAtLogTime:            col("vitaminkatlogtime", row: row),
                vitaminB6AtLogTime:           col("vitaminb6atlogtime", row: row),
                vitaminB12AtLogTime:          col("vitaminb12atlogtime", row: row),
                folateAtLogTime:              col("folateatlogtime", row: row),
                cholineAtLogTime:             col("cholineatlogtime", row: row),
                caffeineAtLogTime:            col("caffeineatlogtime", row: row)
            )
            context.insert(log)
            result.logsCreated += 1
        }
    }

    // MARK: - CSV Parsing

    /// Parses a CSV string into rows of fields.
    /// Accepts an explicit separator, or pass nil to auto-detect (tab vs comma).
    public static func parseCSV(_ csv: String, separator: Character? = nil) -> [[String]] {
        let sep: Character = separator ?? {
            let first = csv.components(separatedBy: .newlines).first ?? ""
            return first.filter({ $0 == "\t" }).count > first.filter({ $0 == "," }).count ? "\t" : ","
        }()

        var rows: [[String]] = []
        for line in csv.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            rows.append(parseCSVLine(trimmed, separator: sep))
        }
        return rows
    }

    private static func parseCSVLine(_ line: String, separator: Character = ",") -> [String] {
        // Tab-delimited files don't use quoting — fast path
        if separator == "\t" {
            return line.components(separatedBy: "\t")
                .map { $0.trimmingCharacters(in: .whitespaces) }
        }
        var fields: [String] = []
        var current = ""
        var inQuotes = false
        for char in line {
            if char == "\"" {
                inQuotes.toggle()
            } else if char == separator && !inQuotes {
                fields.append(current)
                current = ""
            } else {
                current.append(char)
            }
        }
        fields.append(current)
        return fields
    }

    /// Parses a numeric string from a LoseIt CSV cell.
    /// Returns nil for empty, "n/a", or any non-numeric value.
    private static func parseLoseItDouble(_ s: String) -> Double? {
        let t = s.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty, t.lowercased() != "n/a" else { return nil }
        return Double(t)
    }

    // MARK: - Legacy BiteLedger Import
    
    /// Imports old single-file BiteLedger CSV exports (before 3-file format)
    /// Each CSV row represents a complete food log entry with nutrition already calculated
    @MainActor
    public static func importLegacyBiteLedger(
        csvString: String,
        context: ModelContext
    ) throws -> ImportResult {
        var result = ImportResult()
        let rows = parseCSV(csvString)
        guard !rows.isEmpty else {
            throw ImportError.invalidFormat("File appears to be empty.")
        }
        
        let headers = rows[0].map { $0.lowercased().trimmingCharacters(in: .whitespaces) }
        
        // Map required columns - be flexible with column names
        guard
            let nameIdx = headers.firstIndex(where: { $0.contains("foodname") || $0 == "name" }),
            let calIdx = headers.firstIndex(where: { $0.contains("calorie") }),
            let protIdx = headers.firstIndex(where: { $0.contains("protein") }),
            let carbIdx = headers.firstIndex(where: { $0.contains("carb") }),
            let fatIdx = headers.firstIndex(where: { $0 == "fat" || ($0.contains("fat") && !$0.contains("saturated") && !$0.contains("trans") && !$0.contains("monounsaturated") && !$0.contains("polyunsaturated")) }),
            let dateIdx = headers.firstIndex(where: { $0.contains("timestamp") || $0 == "date" }),
            let qtyIdx = headers.firstIndex(where: { $0.contains("quantity") || $0 == "qty" || $0 == "amount" })
        else {
            throw ImportError.missingRequiredColumn("Expected BiteLedger columns not found. Need: name, calories, protein, carbs, fat, date, amount")
        }
        
        // Optional columns
        let timeIdx = headers.firstIndex(where: { $0 == "time" })
        let brandIdx = headers.firstIndex(where: { $0.contains("brand") })
        let mealIdx = headers.firstIndex(where: { $0.contains("meal") })
        let gramsIdx = headers.firstIndex(where: { $0 == "grams" })
        let fiberIdx = headers.firstIndex(where: { $0.contains("fiber") })
        let sugarIdx = headers.firstIndex(where: { $0.contains("sugar") })
        let sodiumIdx = headers.firstIndex(where: { $0.contains("sodium") })
        let saturatedFatIdx = headers.firstIndex(where: { $0.contains("saturated") })
        let transFatIdx = headers.firstIndex(where: { $0.contains("trans") })
        let monounsaturatedFatIdx = headers.firstIndex(where: { $0.contains("monounsaturated") })
        let polyunsaturatedFatIdx = headers.firstIndex(where: { $0.contains("polyunsaturated") })
        let cholesterolIdx = headers.firstIndex(where: { $0.contains("cholesterol") })
        let vitaminAIdx = headers.firstIndex(where: { $0.contains("vitamin a") })
        let vitaminCIdx = headers.firstIndex(where: { $0.contains("vitamin c") })
        let vitaminDIdx = headers.firstIndex(where: { $0.contains("vitamin d") })
        let vitaminEIdx = headers.firstIndex(where: { $0.contains("vitamin e") })
        let vitaminKIdx = headers.firstIndex(where: { $0.contains("vitamin k") })
        let vitaminB6Idx = headers.firstIndex(where: { $0.contains("vitamin b6") || $0.contains("vitaminb6") })
        let vitaminB12Idx = headers.firstIndex(where: { $0.contains("vitamin b12") || $0.contains("vitaminb12") })
        let folateIdx = headers.firstIndex(where: { $0.contains("folate") })
        let cholineIdx = headers.firstIndex(where: { $0.contains("choline") })
        let calciumIdx = headers.firstIndex(where: { $0.contains("calcium") })
        let ironIdx = headers.firstIndex(where: { $0.contains("iron") })
        let potassiumIdx = headers.firstIndex(where: { $0.contains("potassium") })
        let magnesiumIdx = headers.firstIndex(where: { $0.contains("magnesium") })
        let zincIdx = headers.firstIndex(where: { $0.contains("zinc") })
        let caffeineIdx = headers.firstIndex(where: { $0.contains("caffeine") })
        
        // Debug: Print what vitamin columns we found
        print("🔍 CSV Column Mapping:")
        print("   Vitamin A index: \(vitaminAIdx?.description ?? "nil")")
        print("   Vitamin C index: \(vitaminCIdx?.description ?? "nil")")
        print("   Vitamin D index: \(vitaminDIdx?.description ?? "nil")")
        print("   Calcium index: \(calciumIdx?.description ?? "nil")")
        print("   Iron index: \(ironIdx?.description ?? "nil")")
        
        var foodCache: [String: FoodItem] = [:]
        var servingCache: [String: ServingSize] = [:]
        let dateFormatter = DateFormatter()
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")
        
        for (rowIndex, row) in rows.dropFirst().enumerated() {
            let rowNum = rowIndex + 2
            guard row.count > max(nameIdx, calIdx, protIdx, carbIdx, fatIdx, dateIdx, qtyIdx) else {
                result.errors.append("Row \(rowNum): Not enough columns, skipped.")
                continue
            }
            
            let name = row[nameIdx].trimmingCharacters(in: .whitespaces)
            let brand = brandIdx.flatMap { row[safe: $0]?.trimmingCharacters(in: .whitespaces) }
            let servingDescription = row[qtyIdx].trimmingCharacters(in: .whitespaces) // e.g., "80 g", "2 cup", "1 Each"
            
            // Parse the serving description to extract quantity and unit
            // e.g., "80 g" → quantity=80, unit="g"
            // e.g., "2 caplet" → quantity=2, unit="caplet"
            let (parsedQuantity, parsedUnit) = parseServingDescription(servingDescription)
            let dateStr = row[dateIdx].trimmingCharacters(in: .whitespaces)
            let timeStr = timeIdx.flatMap { row[safe: $0]?.trimmingCharacters(in: .whitespaces) } ?? ""
            
            guard !name.isEmpty else { continue }
            
            // Parse nutrition - these are the TOTAL values for this specific log entry
            let cal = Double(row[calIdx]) ?? 0
            let prot = Double(row[protIdx]) ?? 0
            let carb = Double(row[carbIdx]) ?? 0
            let fat = Double(row[fatIdx]) ?? 0
            let fiber = fiberIdx.flatMap { Double(row[safe: $0] ?? "") }
            let sugar = sugarIdx.flatMap { Double(row[safe: $0] ?? "") }
            let sodium = sodiumIdx.flatMap { Double(row[safe: $0] ?? "") }
            let saturatedFat = saturatedFatIdx.flatMap { Double(row[safe: $0] ?? "") }
            let transFat = transFatIdx.flatMap { Double(row[safe: $0] ?? "") }
            let monounsaturatedFat = monounsaturatedFatIdx.flatMap { Double(row[safe: $0] ?? "") }
            let polyunsaturatedFat = polyunsaturatedFatIdx.flatMap { Double(row[safe: $0] ?? "") }
            let cholesterol = cholesterolIdx.flatMap { Double(row[safe: $0] ?? "") }
            let vitaminA = vitaminAIdx.flatMap { Double(row[safe: $0] ?? "") }
            let vitaminC = vitaminCIdx.flatMap { Double(row[safe: $0] ?? "") }
            let vitaminD = vitaminDIdx.flatMap { Double(row[safe: $0] ?? "") }
            let vitaminE = vitaminEIdx.flatMap { Double(row[safe: $0] ?? "") }
            let vitaminK = vitaminKIdx.flatMap { Double(row[safe: $0] ?? "") }
            let vitaminB6 = vitaminB6Idx.flatMap { Double(row[safe: $0] ?? "") }
            let vitaminB12 = vitaminB12Idx.flatMap { Double(row[safe: $0] ?? "") }
            let folate = folateIdx.flatMap { Double(row[safe: $0] ?? "") }
            let choline = cholineIdx.flatMap { Double(row[safe: $0] ?? "") }
            let calcium = calciumIdx.flatMap { Double(row[safe: $0] ?? "") }
            let iron = ironIdx.flatMap { Double(row[safe: $0] ?? "") }
            let potassium = potassiumIdx.flatMap { Double(row[safe: $0] ?? "") }
            let magnesium = magnesiumIdx.flatMap { Double(row[safe: $0] ?? "") }
            let zinc = zincIdx.flatMap { Double(row[safe: $0] ?? "") }
            let caffeine = caffeineIdx.flatMap { Double(row[safe: $0] ?? "") }
            
            // Debug: Print parsed values for Centrum
            if name.contains("Centrum") {
                print("🔍 Parsing Centrum row:")
                print("   Raw Vitamin A: \(vitaminAIdx.flatMap { row[safe: $0] } ?? "nil")")
                print("   Parsed Vitamin A: \(vitaminA?.description ?? "nil")")
                print("   Raw Vitamin C: \(vitaminCIdx.flatMap { row[safe: $0] } ?? "nil")")
                print("   Parsed Vitamin C: \(vitaminC?.description ?? "nil")")
                print("   Raw Calcium: \(calciumIdx.flatMap { row[safe: $0] } ?? "nil")")
                print("   Parsed Calcium: \(calcium?.description ?? "nil")")
            }
            
            // Create a simple FoodItem for this log (one per unique food name+brand)
            let cacheKey = "\(name.lowercased())|\(brand?.lowercased() ?? "")"
            
            let food: FoodItem
            if let cached = foodCache[cacheKey] {
                food = cached
            } else {
                // Create a placeholder FoodItem with minimal info
                food = FoodItem(
                    name: name,
                    brand: brand?.isEmpty == false ? brand : nil,
                    source: "CSV Import (Legacy)",
                    nutritionMode: .per100g,
                    calories: 0, // Placeholder — nutrition is frozen in log AtLogTime fields
                    protein: 0,
                    carbs: 0,
                    fat: 0
                )
                context.insert(food)
                foodCache[cacheKey] = food
                result.foodsCreated += 1
            }
            
            // Parse date and time
            var timestamp: Date
            if !timeStr.isEmpty {
                let combinedStr = "\(dateStr) \(timeStr)"
                timestamp = parseDateTime(combinedStr, formatter: dateFormatter) ?? parseDate(dateStr, formatter: dateFormatter) ?? Date()
            } else {
                timestamp = parseDate(dateStr, formatter: dateFormatter) ?? Date()
            }
            
            // Determine meal type
            let mealStr = mealIdx.flatMap { row[safe: $0] } ?? ""
            let mealType = mealTypeFromLoseIt(mealStr)
            
            // Create or reuse a ServingSize for the base unit (without quantity)
            // e.g., "80 g" creates serving "g", "2 caplet" creates serving "caplet"
            let servingCacheKey = "\(cacheKey)|\(parsedUnit.lowercased())"
            let servingForThisLog: ServingSize
            
            if let cached = servingCache[servingCacheKey] {
                servingForThisLog = cached
            } else {
                servingForThisLog = ServingSize(
                    label: parsedUnit,
                    gramWeight: nil, // We don't know gram weights from CSV
                    isDefault: food.servingSizes.isEmpty, // First one is default
                    sortOrder: food.servingSizes.count,
                    unit: ServingSizeParser.parseUnit(parsedUnit)?.rawValue
                )
                servingForThisLog.foodItem = food
                context.insert(servingForThisLog)
                food.servingSizes.append(servingForThisLog)
                servingCache[servingCacheKey] = servingForThisLog
            }
            
            // Create FoodLog with frozen nutrition values directly from CSV
            let log = FoodLog(
                timestamp: timestamp,
                mealType: mealType,
                quantity: parsedQuantity, // Use the parsed quantity (e.g., 80 for "80 g", 2 for "2 caplet")
                foodItem: food,
                servingSize: servingForThisLog, // Use the base unit serving
                caloriesAtLogTime: cal,
                proteinAtLogTime: prot,
                carbsAtLogTime: carb,
                fatAtLogTime: fat,
                fiberAtLogTime: fiber,
                sodiumAtLogTime: sodium,
                sugarAtLogTime: sugar,
                saturatedFatAtLogTime: saturatedFat,
                transFatAtLogTime: transFat,
                monounsaturatedFatAtLogTime: monounsaturatedFat,
                polyunsaturatedFatAtLogTime: polyunsaturatedFat,
                cholesterolAtLogTime: cholesterol,
                potassiumAtLogTime: potassium,
                calciumAtLogTime: calcium,
                ironAtLogTime: iron,
                magnesiumAtLogTime: magnesium,
                zincAtLogTime: zinc,
                vitaminAAtLogTime: vitaminA,
                vitaminCAtLogTime: vitaminC,
                vitaminDAtLogTime: vitaminD,
                vitaminEAtLogTime: vitaminE,
                vitaminKAtLogTime: vitaminK,
                vitaminB6AtLogTime: vitaminB6,
                vitaminB12AtLogTime: vitaminB12,
                folateAtLogTime: folate,
                cholineAtLogTime: choline,
                caffeineAtLogTime: caffeine
            )
            context.insert(log)
            result.logsCreated += 1
        }
        
        try context.save()
        
        // CRITICAL FIX: After importing all logs, backfill FoodItem nutrition values
        // Legacy CSV creates placeholder FoodItems with 0 values because each row only has
        // total nutrition for that log entry. We need to calculate per-serving nutrition.
        backfillFoodItemNutrition(from: foodCache, context: context)
        
        return result
    }
    
    // MARK: - Backfill Nutrition
    
    /// Calculates and sets FoodItem nutrition values based on their food logs
    /// For legacy imports, FoodItems are created with 0 values and nutrition is only in logs
    @MainActor
    private static func backfillFoodItemNutrition(from foodCache: [String: FoodItem], context: ModelContext) {
        print("🔧 Backfilling nutrition for \(foodCache.count) imported foods...")
        
        for (_, food) in foodCache {
            // Get all logs for this food
            let foodId = food.id
            let descriptor = FetchDescriptor<FoodLog>(
                predicate: #Predicate { $0.foodItem?.id == foodId }
            )
            
            guard let logs = try? context.fetch(descriptor), !logs.isEmpty else {
                print("⚠️ No logs found for \(food.name)")
                continue
            }
            
            // Calculate average per-serving nutrition from all logs
            // Strategy: Use the log with quantity closest to 1.0 as the base serving
            let closestToOne = logs.min { abs($0.quantity - 1.0) < abs($1.quantity - 1.0) }
            
            if let baseLog = closestToOne {
                // Calculate per-serving values by dividing by quantity
                let divisor = baseLog.quantity > 0 ? baseLog.quantity : 1.0
                
                food.calories = baseLog.caloriesAtLogTime / divisor
                food.protein = baseLog.proteinAtLogTime / divisor
                food.carbs = baseLog.carbsAtLogTime / divisor
                food.fat = baseLog.fatAtLogTime / divisor
                food.fiber = baseLog.fiberAtLogTime.map { $0 / divisor }
                food.sugar = baseLog.sugarAtLogTime.map { $0 / divisor }
                food.sodium = baseLog.sodiumAtLogTime.map { $0 / divisor }
                food.saturatedFat = baseLog.saturatedFatAtLogTime.map { $0 / divisor }
                food.transFat = baseLog.transFatAtLogTime.map { $0 / divisor }
                food.monounsaturatedFat = baseLog.monounsaturatedFatAtLogTime.map { $0 / divisor }
                food.polyunsaturatedFat = baseLog.polyunsaturatedFatAtLogTime.map { $0 / divisor }
                food.cholesterol = baseLog.cholesterolAtLogTime.map { $0 / divisor }
                food.potassium = baseLog.potassiumAtLogTime.map { $0 / divisor }
                food.calcium = baseLog.calciumAtLogTime.map { $0 / divisor }
                food.iron = baseLog.ironAtLogTime.map { $0 / divisor }
                food.magnesium = baseLog.magnesiumAtLogTime.map { $0 / divisor }
                food.zinc = baseLog.zincAtLogTime.map { $0 / divisor }
                food.vitaminA = baseLog.vitaminAAtLogTime.map { $0 / divisor }
                food.vitaminC = baseLog.vitaminCAtLogTime.map { $0 / divisor }
                food.vitaminD = baseLog.vitaminDAtLogTime.map { $0 / divisor }
                food.vitaminE = baseLog.vitaminEAtLogTime.map { $0 / divisor }
                food.vitaminK = baseLog.vitaminKAtLogTime.map { $0 / divisor }
                food.vitaminB6 = baseLog.vitaminB6AtLogTime.map { $0 / divisor }
                food.vitaminB12 = baseLog.vitaminB12AtLogTime.map { $0 / divisor }
                food.folate = baseLog.folateAtLogTime.map { $0 / divisor }
                food.choline = baseLog.cholineAtLogTime.map { $0 / divisor }
                food.caffeine = baseLog.caffeineAtLogTime.map { $0 / divisor }
                
                print("✅ \(food.name): \(Int(food.calories)) cal per serving (from log with qty=\(String(format: "%.2f", baseLog.quantity)))")
            }
        }
        
        try? context.save()
        print("✅ Backfill complete")
    }
    
    // MARK: - Helpers

    private static func findFood(name: String, brand: String?, context: ModelContext) -> FoodItem? {
        let descriptor = FetchDescriptor<FoodItem>(
            predicate: #Predicate { $0.name == name }
        )
        return try? context.fetch(descriptor).first
    }

    /// Like findFood, but also requires a matching serving size label.
    /// Used by the LoseIt importer so "Life Cereal (Cups)" and
    /// "Life Cereal (Grams)" are never treated as the same FoodItem.
    private static func findLoseItFood(name: String, units: String, context: ModelContext) -> FoodItem? {
        let descriptor = FetchDescriptor<FoodItem>(
            predicate: #Predicate { $0.name == name }
        )
        guard let matches = try? context.fetch(descriptor) else { return nil }
        let unitsLower = units.lowercased()
        return matches.first { food in
            food.servingSizes.contains { $0.label.lowercased() == unitsLower }
        }
    }

    private static func mealTypeFromLoseIt(_ type: String) -> MealType {
        switch type.lowercased() {
        case "breakfast": return .breakfast
        case "lunch":     return .lunch
        case "dinner":    return .dinner
        default:          return .snack
        }
    }

    private static func parseDate(_ string: String, formatter: DateFormatter) -> Date? {
        // Anchor 2-digit years to the 21st century (00 → 2000, 99 → 2099)
        formatter.defaultDate = Date(timeIntervalSince1970: 946684800) // Jan 1, 2000

        // LoseIt uses M/d/yy — try 2-digit year formats first so "1/1/24" → 2024, not 1901
        let formats = [
            "M/d/yy", "MM/dd/yy", "dd/MM/yy",          // 2-digit year (LoseIt)
            "M/d/yyyy", "MM/dd/yyyy", "yyyy-MM-dd", "dd/MM/yyyy"  // 4-digit year
        ]
        for format in formats {
            formatter.dateFormat = format
            if let date = formatter.date(from: string) { return date }
        }
        return nil
    }
    
    private static func parseDateTime(_ string: String, formatter: DateFormatter) -> Date? {
        // Set default century for 2-digit years (00-99 → 2000-2099)
        formatter.defaultDate = Date(timeIntervalSince1970: 946684800) // Jan 1, 2000
        
        // Try common date+time formats
        let formats = [
            "MM/dd/yyyy HH:mm:ss", "MM/dd/yyyy HH:mm", "MM/dd/yyyy h:mm:ss a", "MM/dd/yyyy h:mm a",
            "M/d/yyyy HH:mm:ss", "M/d/yyyy HH:mm", "M/d/yyyy h:mm:ss a", "M/d/yyyy h:mm a",
            "yyyy-MM-dd HH:mm:ss", "yyyy-MM-dd HH:mm", "yyyy-MM-dd'T'HH:mm:ss",
            "MM/dd/yy HH:mm:ss", "MM/dd/yy HH:mm", "MM/dd/yy h:mm:ss a", "MM/dd/yy h:mm a",
            "M/d/yy HH:mm:ss", "M/d/yy HH:mm", "M/d/yy h:mm:ss a", "M/d/yy h:mm a"
        ]
        for format in formats {
            formatter.dateFormat = format
            if let date = formatter.date(from: string) { return date }
        }
        return nil
    }
    
    /// Parse serving description like "80 g", "2 caplet", "1.5 cup" into (quantity, unit)
    private static func parseServingDescription(_ description: String) -> (quantity: Double, unit: String) {
        let trimmed = description.trimmingCharacters(in: .whitespaces)
        
        // Extract leading number (including decimals)
        var numberStr = ""
        var remainingStr = trimmed
        
        for char in trimmed {
            if char.isNumber || char == "." {
                numberStr.append(char)
            } else if char == " " {
                // Skip space between number and unit
                remainingStr = String(trimmed.dropFirst(numberStr.count)).trimmingCharacters(in: .whitespaces)
                break
            } else {
                // Hit non-numeric, non-space character
                remainingStr = String(trimmed.dropFirst(numberStr.count)).trimmingCharacters(in: .whitespaces)
                break
            }
        }
        
        let quantity = Double(numberStr) ?? 1.0
        let unit = remainingStr.isEmpty ? "serving" : remainingStr
        
        return (quantity, unit)
    }
}

// MARK: - Safe Array Subscript

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
