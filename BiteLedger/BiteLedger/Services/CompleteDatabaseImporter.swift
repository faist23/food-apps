//
//  CompleteDatabaseImporter.swift
//  BiteLedger
//
//  Created by Claude on 2/27/26.
//

import Foundation
import SwiftData
import BiteLedgerCore

/// Service to import complete database from multi-file CSV export
struct CompleteDatabaseImporter {

    struct ImportResult {
        let foodsImported: Int
        let portionsImported: Int
        let logsImported: Int
        let errors: [String]
    }

    /// Import complete database from folder containing FoodItems.csv, PortionSizes.csv, and FoodLogs.csv
    static func importCompleteDatabase(from folderURL: URL, modelContext: ModelContext) async throws -> ImportResult {
        var foodsImported = 0
        var portionsImported = 0
        var logsImported = 0
        var errors: [String] = []

        // Check for required files
        let foodItemsURL = folderURL.appendingPathComponent("FoodItems.csv")
        let portionSizesURL = folderURL.appendingPathComponent("PortionSizes.csv")
        let foodLogsURL = folderURL.appendingPathComponent("FoodLogs.csv")

        guard FileManager.default.fileExists(atPath: foodItemsURL.path) else {
            throw ImportError.missingFile("FoodItems.csv")
        }

        // Step 1: Import FoodItems first (required)
        do {
            let foodsResult = try await importFoodItems(from: foodItemsURL, modelContext: modelContext)
            foodsImported = foodsResult.count
            print("✅ Imported \(foodsImported) foods")
        } catch {
            errors.append("FoodItems import failed: \(error.localizedDescription)")
            throw error
        }

        // Step 2: Import PortionSizes (optional, links to foods by name+brand)
        if FileManager.default.fileExists(atPath: portionSizesURL.path) {
            do {
                portionsImported = try await importPortionSizes(from: portionSizesURL, modelContext: modelContext)
                print("✅ Imported \(portionsImported) portion sizes")
            } catch {
                errors.append("PortionSizes import failed: \(error.localizedDescription)")
            }
        }

        // Step 3: Import FoodLogs (optional, links to foods by name+brand)
        if FileManager.default.fileExists(atPath: foodLogsURL.path) {
            do {
                logsImported = try await importFoodLogs(from: foodLogsURL, modelContext: modelContext)
                print("✅ Imported \(logsImported) food logs")
            } catch {
                errors.append("FoodLogs import failed: \(error.localizedDescription)")
            }
        }

        return ImportResult(
            foodsImported: foodsImported,
            portionsImported: portionsImported,
            logsImported: logsImported,
            errors: errors
        )
    }

    // MARK: - FoodItems Import

    private static func importFoodItems(from url: URL, modelContext: ModelContext) async throws -> [FoodItem] {
        let csvString = try String(contentsOf: url, encoding: .utf8)
        let lines = csvString.components(separatedBy: .newlines).filter { !$0.isEmpty }

        guard lines.count > 1 else {
            throw ImportError.emptyFile
        }

        let header = lines[0].components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        let columnMap = parseHeader(header)

        var importedFoods: [FoodItem] = []

        // Fetch canonical foods once for all food creation in this import.
        let canonicalFoods = (try? modelContext.fetch(FetchDescriptor<CanonicalFood>())) ?? []

        for (index, line) in lines.dropFirst().enumerated() {
            do {
                let columns = parseCSVLine(line)
                let food = try createFoodItem(from: columns, columnMap: columnMap, modelContext: modelContext)
                food.canonicalFoodID = CanonicalFoodMatcher.match(foodName: food.name, in: canonicalFoods)?.id
                modelContext.insert(food)
                importedFoods.append(food)

                // Batch save every 100 items
                if importedFoods.count % 100 == 0 {
                    try modelContext.save()
                }
            } catch {
                print("⚠️ Failed to import food at line \(index + 2): \(error)")
            }
        }

        try modelContext.save()
        return importedFoods
    }

    private static func createFoodItem(from columns: [String], columnMap: [String: Int], modelContext: ModelContext) throws -> FoodItem {
        guard let name = getValue(from: columns, columnMap: columnMap, key: "name") else {
            throw ImportError.missingRequiredField("name")
        }

        let brand = getValue(from: columns, columnMap: columnMap, key: "brand")
        _ = getValue(from: columns, columnMap: columnMap, key: "baseservingdescription")
        _ = getNumericValue(from: columns, columnMap: columnMap, key: "baseservinggrams")

        let calories = getNumericValue(from: columns, columnMap: columnMap, key: "calories") ?? 0
        let protein = getNumericValue(from: columns, columnMap: columnMap, key: "protein") ?? 0
        let carbs = getNumericValue(from: columns, columnMap: columnMap, key: "carbs") ?? 0
        let fat = getNumericValue(from: columns, columnMap: columnMap, key: "fat") ?? 0
        let fiber = getNumericValue(from: columns, columnMap: columnMap, key: "fiber")
        let sugar = getNumericValue(from: columns, columnMap: columnMap, key: "sugar")
        let sodium = getNumericValue(from: columns, columnMap: columnMap, key: "sodium")
        let saturatedFat = getNumericValue(from: columns, columnMap: columnMap, key: "saturated fat")
        let transFat = getNumericValue(from: columns, columnMap: columnMap, key: "trans fat")
        let monounsaturatedFat = getNumericValue(from: columns, columnMap: columnMap, key: "monounsaturated fat")
        let polyunsaturatedFat = getNumericValue(from: columns, columnMap: columnMap, key: "polyunsaturated fat")
        let cholesterol = getNumericValue(from: columns, columnMap: columnMap, key: "cholesterol")

        let vitaminA = getNumericValue(from: columns, columnMap: columnMap, key: "vitamin a")
        let vitaminC = getNumericValue(from: columns, columnMap: columnMap, key: "vitamin c")
        let vitaminD = getNumericValue(from: columns, columnMap: columnMap, key: "vitamin d")
        let vitaminE = getNumericValue(from: columns, columnMap: columnMap, key: "vitamin e")
        let vitaminK = getNumericValue(from: columns, columnMap: columnMap, key: "vitamin k")
        let vitaminB6 = getNumericValue(from: columns, columnMap: columnMap, key: "vitamin b6")
        let vitaminB12 = getNumericValue(from: columns, columnMap: columnMap, key: "vitamin b12")
        let folate = getNumericValue(from: columns, columnMap: columnMap, key: "folate")
        let choline = getNumericValue(from: columns, columnMap: columnMap, key: "choline")

        let calcium = getNumericValue(from: columns, columnMap: columnMap, key: "calcium")
        let iron = getNumericValue(from: columns, columnMap: columnMap, key: "iron")
        let potassium = getNumericValue(from: columns, columnMap: columnMap, key: "potassium")
        let magnesium = getNumericValue(from: columns, columnMap: columnMap, key: "magnesium")
        let zinc = getNumericValue(from: columns, columnMap: columnMap, key: "zinc")
        let caffeine = getNumericValue(from: columns, columnMap: columnMap, key: "caffeine")

        let source = getValue(from: columns, columnMap: columnMap, key: "source") ?? "CSV Import"

        // Old exports stored per-serving values. Normalize at import time so all foods
        // are per-100g. servingGrams is read from the serving data by the caller, but
        // this importer doesn't have gram data, so use 100g nominal (factor = 1.0).
        let food = FoodItem(
            name: name,
            brand: brand?.isEmpty == false ? brand : nil,
            source: source,
            nutritionMode: .perServing,
            calories: calories,
            protein: protein,
            carbs: carbs,
            fat: fat,
            fiber: fiber,
            sugar: sugar,
            saturatedFat: saturatedFat,
            transFat: transFat,
            polyunsaturatedFat: polyunsaturatedFat,
            monounsaturatedFat: monounsaturatedFat,
            sodium: sodium,
            cholesterol: cholesterol,
            potassium: potassium,
            calcium: calcium,
            iron: iron,
            magnesium: magnesium,
            zinc: zinc,
            vitaminA: vitaminA,
            vitaminC: vitaminC,
            vitaminD: vitaminD,
            vitaminE: vitaminE,
            vitaminK: vitaminK,
            vitaminB6: vitaminB6,
            vitaminB12: vitaminB12,
            folate: folate,
            choline: choline,
            caffeine: caffeine
        )
        // Normalize to per-100g using 100g nominal (no gram data available in this importer).
        food.normalizeToPerHundredGrams(gramWeightPerServing: nil)

        return food
    }

    // MARK: - PortionSizes Import

    private static func importPortionSizes(from url: URL, modelContext: ModelContext) async throws -> Int {
        let csvString = try String(contentsOf: url, encoding: .utf8)
        let lines = csvString.components(separatedBy: .newlines).filter { !$0.isEmpty }

        guard lines.count > 1 else { return 0 }

        let header = lines[0].components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        let columnMap = parseHeader(header)

        // Fetch all foods for lookup
        let foodDescriptor = FetchDescriptor<FoodItem>()
        let allFoods = try modelContext.fetch(foodDescriptor)
        let foodLookup = Dictionary(grouping: allFoods) { "\($0.name)|\($0.brand ?? "")" }

        var imported = 0

        for (index, line) in lines.dropFirst().enumerated() {
            do {
                let columns = parseCSVLine(line)

                guard let foodName = getValue(from: columns, columnMap: columnMap, key: "foodname"),
                      let portionName = getValue(from: columns, columnMap: columnMap, key: "portionname"),
                      let _ = getNumericValue(from: columns, columnMap: columnMap, key: "quantity"),
                      let baseMultiplier = getNumericValue(from: columns, columnMap: columnMap, key: "basemultiplier") else {
                    continue
                }

                let foodBrand = getValue(from: columns, columnMap: columnMap, key: "foodbrand") ?? ""
                let isDefault = getValue(from: columns, columnMap: columnMap, key: "isdefault")?.lowercased() == "true"

                // Find matching food
                let lookupKey = "\(foodName)|\(foodBrand)"
                guard let foods = foodLookup[lookupKey], let food = foods.first else {
                    print("⚠️ Could not find food for portion: \(foodName)")
                    continue
                }

                // Create serving size with new structure
                // Old format had quantity * baseMultiplier to get final gram weight
                // New format just stores gramWeight directly
                let calculatedGrams = (baseMultiplier * 100.0) // Since we're using perServing mode now
                
                let portionUnit = ServingSizeParser.parse(portionName).flatMap {
                    $0.unit == .serving ? nil : $0.unit.rawValue
                } ?? ServingSizeParser.parseUnit(portionName)?.rawValue
                let serving = ServingSize(
                    label: portionName,
                    gramWeight: calculatedGrams > 0 ? calculatedGrams : nil,
                    isDefault: isDefault,
                    sortOrder: imported,
                    unit: portionUnit
                )
                serving.foodItem = food

                modelContext.insert(serving)
                food.servingSizes.append(serving)
                imported += 1

                if imported % 100 == 0 {
                    try modelContext.save()
                }
            } catch {
                print("⚠️ Failed to import portion at line \(index + 2): \(error)")
            }
        }

        try modelContext.save()
        return imported
    }

    // MARK: - FoodLogs Import

    private static func importFoodLogs(from url: URL, modelContext: ModelContext) async throws -> Int {
        // Use CSVImporter for LoseIt format
        let csvString = try String(contentsOf: url, encoding: .utf8)
        let result = try CSVImporter.importLoseIt(csvString: csvString, context: modelContext)
        return result.logsCreated
    }

    // MARK: - Helper Functions

    private static func parseHeader(_ header: [String]) -> [String: Int] {
        var map: [String: Int] = [:]
        for (index, column) in header.enumerated() {
            map[column.lowercased()] = index
        }
        return map
    }

    private static func parseCSVLine(_ line: String) -> [String] {
        var columns: [String] = []
        var currentColumn = ""
        var insideQuotes = false

        for char in line {
            if char == "\"" {
                insideQuotes.toggle()
            } else if char == "," && !insideQuotes {
                columns.append(currentColumn.trimmingCharacters(in: .whitespaces))
                currentColumn = ""
            } else {
                currentColumn.append(char)
            }
        }
        columns.append(currentColumn.trimmingCharacters(in: .whitespaces))
        return columns
    }

    private static func getValue(from columns: [String], columnMap: [String: Int], key: String) -> String? {
        guard let index = columnMap[key.lowercased()], index < columns.count else {
            return nil
        }
        let value = columns[index].trimmingCharacters(in: CharacterSet(charactersIn: "\""))
        return value.isEmpty ? nil : value
    }

    private static func getNumericValue(from columns: [String], columnMap: [String: Int], key: String) -> Double? {
        guard let stringValue = getValue(from: columns, columnMap: columnMap, key: key) else {
            return nil
        }
        let cleanedValue = stringValue.replacingOccurrences(of: ",", with: "")
        return Double(cleanedValue)
    }

    enum ImportError: LocalizedError {
        case emptyFile
        case missingFile(String)
        case missingRequiredField(String)

        var errorDescription: String? {
            switch self {
            case .emptyFile: return "The CSV file is empty"
            case .missingFile(let name): return "Missing required file: \(name)"
            case .missingRequiredField(let field): return "Missing required field: \(field)"
            }
        }
    }
}
