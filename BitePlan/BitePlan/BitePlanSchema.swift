//
//  BitePlanSchema.swift
//  BitePlan
//
//  Versioned SwiftData schema history and migration plan for BitePlan.
//
//  IMPORTANT: This file must always mirror BiteLedgerSchema.swift exactly.
//  Both apps share the same physical store (biteledger.store via App Group).
//  Any schema version added here must also be added in BiteLedgerSchema.swift
//  and released at the same time.
//
//  See BiteLedgerSchema.swift for instructions on adding new schema versions.
//

import SwiftData
import BiteLedgerCore

// MARK: - SchemaV1 (baseline — shipping v1.0)
//
// Must match BiteLedgerSchemaV1 exactly (same models, same order, same version).
//
enum BitePlanSchemaV1: VersionedSchema {
    static let versionIdentifier = Schema.Version(1, 0, 0)
    static var models: [any PersistentModel.Type] {
        [
            FoodItem.self,
            ServingSize.self,
            FoodLog.self,
            UserPreferences.self,
            Recipe.self,
            RecipeIngredient.self,
            CanonicalFood.self,
            ServingConversion.self,
            FallbackSource.self,
        ]
    }
}

// MARK: - SchemaV2 (T-14 — FoodHistoryEntry personal food history index)
//
// Must match BiteLedgerSchemaV2 exactly (same models, same order, same version).
// BitePlan registers FoodHistoryEntry but never queries it — the shared store
// requires identical schemas across both apps.
//
enum BitePlanSchemaV2: VersionedSchema {
    static let versionIdentifier = Schema.Version(2, 0, 0)
    static var models: [any PersistentModel.Type] {
        [
            FoodItem.self,
            ServingSize.self,
            FoodLog.self,
            UserPreferences.self,
            Recipe.self,
            RecipeIngredient.self,
            CanonicalFood.self,
            ServingConversion.self,
            FallbackSource.self,
            FoodHistoryEntry.self,   // T-14: personal food history index
        ]
    }
}

// MARK: - SchemaV3 (T-12 — MealPlan + MealPlanEntry week planner)
//
// Must match BiteLedgerSchemaV3 exactly (same models, same order, same version).
// BitePlan reads MealPlan/MealPlanEntry. BiteLedger registers them but does
// not query them in v1.
//
enum BitePlanSchemaV3: VersionedSchema {
    static let versionIdentifier = Schema.Version(3, 0, 0)
    static var models: [any PersistentModel.Type] {
        [
            FoodItem.self,
            ServingSize.self,
            FoodLog.self,
            UserPreferences.self,
            Recipe.self,
            RecipeIngredient.self,
            CanonicalFood.self,
            ServingConversion.self,
            FallbackSource.self,
            FoodHistoryEntry.self,
            MealPlan.self,        // T-12: week meal planner
            MealPlanEntry.self,   // T-12: individual meal plan slot
        ]
    }
}

// MARK: - SchemaV4 (T-12-v2 — MealPlanMeal + MealPlanMealItem cluster model)
//
// Must match BiteLedgerSchemaV4 exactly (same models, same order, same version).
//
enum BitePlanSchemaV4: VersionedSchema {
    static let versionIdentifier = Schema.Version(4, 0, 0)
    static var models: [any PersistentModel.Type] {
        [
            FoodItem.self,
            ServingSize.self,
            FoodLog.self,
            UserPreferences.self,
            Recipe.self,
            RecipeIngredient.self,
            CanonicalFood.self,
            ServingConversion.self,
            FallbackSource.self,
            FoodHistoryEntry.self,
            MealPlan.self,
            MealPlanEntry.self,
            MealPlanMeal.self,       // T-12-v2: named dinner cluster
            MealPlanMealItem.self,   // T-12-v2: one item in a cluster
        ]
    }
}

// MARK: - Migration plan (NOT currently wired in — see BiteLedgerSchema.swift for explanation)
//
enum BitePlanMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [BitePlanSchemaV1.self, BitePlanSchemaV2.self, BitePlanSchemaV3.self, BitePlanSchemaV4.self]
    }
    static var stages: [MigrationStage] {
        [
            .lightweight(fromVersion: BitePlanSchemaV1.self, toVersion: BitePlanSchemaV2.self),
            .lightweight(fromVersion: BitePlanSchemaV2.self, toVersion: BitePlanSchemaV3.self),
            .lightweight(fromVersion: BitePlanSchemaV3.self, toVersion: BitePlanSchemaV4.self),
        ]
    }
}
