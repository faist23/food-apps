//
//  ServingSize.swift
//  BiteLedger
//
//  Created by Craig Faist on 2/25/26.
//

import SwiftData
import Foundation

// MARK: - ServingSize

@Model
public final class ServingSize {

    // MARK: Identity
    // CloudKit requires all stored properties to be optional or have default values.
    public var id: UUID = UUID()
    public var dateAdded: Date = Date()

    // MARK: Display
    /// Human-readable label shown in the UI.
    /// Examples: "1 cup", "1 medium banana", "1 sandwich", "2 cookies", "1 slice"
    /// Kept for display and backward compatibility. `amount` + `unit` are the source of truth.
    public var label: String = ""

    /// The numeric amount for this serving (e.g. 1 for "1 cup", 2 for "2 cookies", 8 for "8 fl oz").
    /// Defaults to 1.0. Backfilled from label by `backfillServingAmounts()` on first launch.
    /// gramsPerUnit = gramWeight / amount (when both are set).
    public var amount: Double = 1.0

    /// Weight in grams for this serving. nil when unknown or not applicable.
    ///
    /// Rules:
    ///   - Set for per100g foods when gram weight is known from a data source
    ///   - Always nil for perServing foods
    ///   - Never estimated using generic density tables
    ///   - Never faked — if you don't know it, store nil
    public var gramWeight: Double?

    /// True for the serving shown by default in search results and log pickers.
    /// Exactly one ServingSize per FoodItem should have isDefault = true.
    public var isDefault: Bool = false

    /// Controls display order in serving pickers. Lower = shown first.
    public var sortOrder: Int = 0

    /// The `ServingUnit.rawValue` for this serving, stored at creation time.
    /// Populated on all new records. `nil` for records created before schema V2
    /// (use `ServingSizeParser` on `label` as a fallback when `nil`).
    public var unit: String? = nil

    // MARK: Relationships
    public var foodItem: FoodItem?

    @Relationship(deleteRule: .nullify) public var foodLogs: [FoodLog] = []

    // MARK: Init
    public init(
        id: UUID = UUID(),
        label: String,
        gramWeight: Double? = nil,
        isDefault: Bool = false,
        sortOrder: Int = 0,
        dateAdded: Date = Date(),
        unit: String? = nil,
        amount: Double = 1.0
    ) {
        self.id = id
        self.label = label
        self.gramWeight = gramWeight
        self.isDefault = isDefault
        self.sortOrder = sortOrder
        self.dateAdded = dateAdded
        self.unit = unit
        self.amount = amount
    }

    // MARK: Computed

    /// Grams per single unit of this serving.
    /// e.g. for "2 cookies (30g)": gramWeight=30, amount=2 → gramsPerUnit=15
    /// nil when gramWeight is unknown.
    public var gramsPerUnit: Double? {
        guard let gw = gramWeight, amount > 0 else { return nil }
        return gw / amount
    }

    /// Supplementary display string showing gram weight if known.
    /// Example: "1 cup (42g)" or just "1 sandwich"
    public var displayLabel: String {
        if let grams = gramWeight {
            let formatted = grams.truncatingRemainder(dividingBy: 1) == 0
                ? String(Int(grams))
                : String(format: "%.1f", grams)
            return "\(label) (\(formatted)g)"
        }
        return label
    }

    /// Safely deletes a ServingSize, nullifying every reference to it first.
    ///
    /// `FoodLog.servingSize` pairs with the declared `ServingSize.foodLogs` relationship,
    /// so SwiftData should nullify it automatically — this loop is a defensive no-op that
    /// preserves the safety net that existed before this method was extracted.
    /// `RecipeIngredient.servingSize` has **no** declared inverse — SwiftData cannot
    /// propagate the delete, and touching an ingredient that still points at a deleted
    /// ServingSize crashes with "model instance was invalidated". Nullify it explicitly
    /// before every delete.
    public static func safeDelete(_ servingSize: ServingSize, in context: ModelContext) throws {
        let servingSizeId = servingSize.id

        let affectedLogs = try context.fetch(
            FetchDescriptor<FoodLog>(
                predicate: #Predicate<FoodLog> { $0.servingSize?.id == servingSizeId }
            )
        )
        for log in affectedLogs {
            log.servingSize = nil
        }

        let affectedIngredients = try context.fetch(
            FetchDescriptor<RecipeIngredient>(
                predicate: #Predicate<RecipeIngredient> { $0.servingSize?.id == servingSizeId }
            )
        )
        for ingredient in affectedIngredients {
            ingredient.servingSize = nil
        }

        context.delete(servingSize)
    }
}
