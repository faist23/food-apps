//
//  CanonicalFood.swift
//  BiteLedger
//
//  Created by Craig Faist on 3/14/26.
//

import SwiftData
import Foundation

// MARK: - CanonicalFood

/// A reference food entry that provides authoritative serving-unit → gram conversions
/// for a class of foods (e.g., "Peanut Butter", "Whole Milk", "All-Purpose Flour").
///
/// FoodItems link to a CanonicalFood via `canonicalFoodID` when a match is found
/// at import time. This allows density-based gram estimates even when a data source
/// (e.g., FatSecret) does not supply `metric_serving_amount`.
///
/// Population: seed data written once by `CanonicalFoodSeeder` at first launch.
/// Never edited by the user.
@Model
public final class CanonicalFood {

    // MARK: Identity
    public var id: UUID = UUID()

    /// Display name (title-cased), e.g. "Peanut Butter"
    public var name: String = ""

    /// Normalized lowercase key used for fuzzy matching at import time.
    /// e.g. "peanut butter"
    public var canonicalName: String = ""

    // MARK: Relationships

    /// Unit → gram conversions specific to this food class.
    /// e.g. "tbsp" = 16g for Peanut Butter, "cup" = 258g.
    @Relationship(deleteRule: .cascade) public var servingConversions: [ServingConversion] = []

    // MARK: Init

    public init(name: String) {
        self.name = name
        self.canonicalName = name.lowercased()
    }

    // MARK: Lookup

    /// Returns the gram-per-unit value for a given unit abbreviation, or nil if not found.
    public func gramsPerUnit(for unit: String) -> Double? {
        let lower = unit.lowercased()
        return servingConversions.first { $0.unit.lowercased() == lower }?.gramsPerUnit
    }
}
