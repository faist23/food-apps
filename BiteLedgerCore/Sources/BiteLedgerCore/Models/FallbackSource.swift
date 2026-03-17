//
//  FallbackSource.swift
//  BiteLedger
//
//  Created by Craig Faist on 3/14/26.
//

import SwiftData
import Foundation

// MARK: - FallbackSource

/// Persistent record linking a FoodItem to the external data source that
/// provided its micronutrient enrichment (USDA FoodData Central or FatSecret).
///
/// Created during LoseIt enrichment import and stored on `FoodItem.fallbackSourceID`.
/// Enables data provenance display ("Enriched from USDA") and future on-demand
/// re-enrichment without re-running the full import tool.
@Model
public final class FallbackSource {

    // MARK: Identity
    public var id: UUID = UUID()

    /// "usda" | "fatsecret" | "manual"
    public var sourceType: String = ""

    /// External identifier: USDA fdcId (as String) or FatSecret food_id.
    public var externalID: String = ""

    /// Display name from the external source (e.g. "PEANUT BUTTER, CREAMY").
    public var externalName: String = ""

    /// Match confidence in [0, 1]. Meaningful for USDA matches; 0 for FatSecret/manual.
    public var confidence: Double = 1.0

    /// When enrichment was applied.
    public var appliedAt: Date = Date()

    // MARK: Init

    public init(
        sourceType: String,
        externalID: String,
        externalName: String,
        confidence: Double
    ) {
        self.sourceType = sourceType
        self.externalID = externalID
        self.externalName = externalName
        self.confidence = confidence
        self.appliedAt = Date()
    }

    // MARK: Display

    /// Short label for the metadata row, e.g. "USDA #12345" or "FatSecret".
    public var displayLabel: String {
        switch sourceType {
        case "usda":       return "USDA #\(externalID)"
        case "fatsecret":  return "FatSecret"
        case "manual":     return "Manual"
        default:           return sourceType.capitalized
        }
    }

    /// Confidence formatted as a percentage string, or nil when not applicable.
    public var confidenceLabel: String? {
        guard sourceType == "usda", confidence > 0 else { return nil }
        return "\(Int(confidence * 100))% match"
    }
}

// MARK: - FallbackSourceInfo

/// Lightweight DTO used to communicate enrichment provenance from
/// `LoseItEnrichmentService.buildFallbackSourceMap()` to
/// `CSVImporter.importLoseItEnriched()` without coupling those two types.
public struct FallbackSourceInfo {
    public let sourceType: String
    public let externalID: String
    public let externalName: String
    public let confidence: Double

    public init(sourceType: String, externalID: String, externalName: String, confidence: Double) {
        self.sourceType = sourceType
        self.externalID = externalID
        self.externalName = externalName
        self.confidence = confidence
    }
}

// MARK: - ManualNutrientOverride

/// User-entered per-serving micronutrient values applied during LoseIt enrichment.
/// Lives in the package so `CSVImporter.importLoseItEnriched` can reference it
/// without depending on `LoseItEnrichmentService`.
public struct ManualNutrientOverride {
    public var potassium:  Double? // mg
    public var calcium:    Double? // mg
    public var iron:       Double? // mg
    public var magnesium:  Double? // mg
    public var zinc:       Double? // mg
    public var vitaminA:   Double? // mcg
    public var vitaminC:   Double? // mg
    public var vitaminD:   Double? // mcg
    public var vitaminE:   Double? // mg
    public var vitaminK:   Double? // mcg
    public var vitaminB6:  Double? // mg
    public var vitaminB12: Double? // mcg
    public var folate:     Double? // mcg
    public var choline:    Double? // mg
    public var caffeine:   Double? // mg

    public var isEmpty: Bool {
        [potassium, calcium, iron, magnesium, zinc,
         vitaminA, vitaminC, vitaminD, vitaminE, vitaminK,
         vitaminB6, vitaminB12, folate, choline, caffeine].allSatisfy { $0 == nil }
    }

    public init(
        potassium: Double? = nil, calcium: Double? = nil, iron: Double? = nil,
        magnesium: Double? = nil, zinc: Double? = nil, vitaminA: Double? = nil,
        vitaminC: Double? = nil, vitaminD: Double? = nil, vitaminE: Double? = nil,
        vitaminK: Double? = nil, vitaminB6: Double? = nil, vitaminB12: Double? = nil,
        folate: Double? = nil, choline: Double? = nil, caffeine: Double? = nil
    ) {
        self.potassium = potassium; self.calcium = calcium; self.iron = iron
        self.magnesium = magnesium; self.zinc = zinc; self.vitaminA = vitaminA
        self.vitaminC = vitaminC; self.vitaminD = vitaminD; self.vitaminE = vitaminE
        self.vitaminK = vitaminK; self.vitaminB6 = vitaminB6; self.vitaminB12 = vitaminB12
        self.folate = folate; self.choline = choline; self.caffeine = caffeine
    }
}
