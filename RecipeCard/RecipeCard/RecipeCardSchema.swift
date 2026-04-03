//
//  RecipeCardSchema.swift
//  RecipeCard
//
//  Versioned SwiftData schema history and migration plan for RecipeCard.
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
enum RecipeCardSchemaV1: VersionedSchema {
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
// RecipeCard registers FoodHistoryEntry but never queries it — the shared store
// requires identical schemas across both apps.
//
enum RecipeCardSchemaV2: VersionedSchema {
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
// RecipeCard reads MealPlan/MealPlanEntry. BiteLedger registers them but does
// not query them in v1.
//
enum RecipeCardSchemaV3: VersionedSchema {
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
enum RecipeCardSchemaV4: VersionedSchema {
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
enum RecipeCardMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [RecipeCardSchemaV1.self, RecipeCardSchemaV2.self, RecipeCardSchemaV3.self, RecipeCardSchemaV4.self]
    }
    static var stages: [MigrationStage] {
        [
            .lightweight(fromVersion: RecipeCardSchemaV1.self, toVersion: RecipeCardSchemaV2.self),
            .lightweight(fromVersion: RecipeCardSchemaV2.self, toVersion: RecipeCardSchemaV3.self),
            .lightweight(fromVersion: RecipeCardSchemaV3.self, toVersion: RecipeCardSchemaV4.self),
        ]
    }
}
