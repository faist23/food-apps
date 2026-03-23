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

// MARK: - Migration plan (NOT currently wired in — see BiteLedgerSchema.swift for explanation)
//
enum RecipeCardMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [RecipeCardSchemaV1.self, RecipeCardSchemaV2.self]
    }
    static var stages: [MigrationStage] {
        [
            .lightweight(fromVersion: RecipeCardSchemaV1.self, toVersion: RecipeCardSchemaV2.self),
        ]
    }
}
