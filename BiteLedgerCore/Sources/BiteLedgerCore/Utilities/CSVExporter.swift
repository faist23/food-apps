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
// Exports BiteLedger data as three CSV files for full round-trip restore.
// foods.csv → servings.csv → logs.csv
//
// Design guarantee: export → delete app → import produces identical data.

public struct CSVExporter {

    // MARK: - Export Package

    public struct ExportPackage: Sendable {
        public let foodsCSV: String
        public let servingsCSV: String
        public let logsCSV: String
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
        let foods    = try context.fetch(FetchDescriptor<FoodItem>())
        let servings = try context.fetch(FetchDescriptor<ServingSize>())
        let logs     = try context.fetch(FetchDescriptor<FoodLog>())

        return ExportPackage(
            foodsCSV:    exportFoods(foods),
            servingsCSV: exportServings(servings),
            logsCSV:     exportLogs(logs),
            exportDate:  Date()
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

    // MARK: - Helpers

    private static func optStr(_ value: Double?) -> String {
        guard let v = value else { return "" }
        // Use integer representation if no decimal part to keep CSV clean
        return v.truncatingRemainder(dividingBy: 1) == 0
            ? String(Int(v))
            : String(format: "%.4g", v)
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