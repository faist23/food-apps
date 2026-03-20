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

// MARK: - Migration plan (active)
//
// Wired into ModelContainer in RecipeCardApp.loadContainer().
// Must stay in sync with BiteLedgerMigrationPlan.
//
enum RecipeCardMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [RecipeCardSchemaV1.self]
    }
    static var stages: [MigrationStage] { [] }
}
