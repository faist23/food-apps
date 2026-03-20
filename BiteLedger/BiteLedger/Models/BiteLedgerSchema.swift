//
//  BiteLedgerSchema.swift
//  BiteLedger
//
//  Defines the versioned SwiftData schema history and migration plan.
//
//  ## Adding a new schema version
//
//  For LIGHTWEIGHT changes (nullable field additions, removing properties):
//    1. Define a new BiteLedgerSchemaVN enum with the same live model types
//       and a bumped versionIdentifier.
//    2. Add a MigrationStage.lightweight(fromVersion:toVersion:) stage to
//       BiteLedgerMigrationPlan.stages.
//    3. Append the new version to BiteLedgerMigrationPlan.schemas.
//    4. Do the same in RecipeCardSchema.swift (coordinated release required).
//
//  For BREAKING changes (rename, type change, required field with non-nil default):
//    1. Add FROZEN nested model types inside the old schema enum — separate
//       @Model classes that mirror the old structure exactly.
//    2. Reference the frozen types in the fromVersion schema and the live types
//       in the toVersion schema (gives SwiftData distinct fingerprints).
//    3. Use MigrationStage.custom(fromVersion:toVersion:willMigrate:didMigrate:)
//       to transform data.
//    4. Coordinate both apps — both must ship the migration in the same release.
//

import SwiftData
import BiteLedgerCore

// MARK: - SchemaV1 (baseline — shipping v1.0)
//
// Lists all 9 live model types in canonical order.
// Must match RecipeCardSchema.swift exactly.
//
// Includes all fields present at v1.0 launch:
//   - ServingSize.unit (String?) — auto-migrated, nullable
//   - UserPreferences.lastShareCardGeneratedWeek (Date?) — auto-migrated, nullable
//   All nullable field additions are handled automatically by SwiftData
//   (no explicit migration stage required).
//
enum BiteLedgerSchemaV1: VersionedSchema {
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
// Wired into ModelContainer in BiteLedgerApp.loadContainer().
// Add new schema versions and stages here as the app evolves.
//
enum BiteLedgerMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [BiteLedgerSchemaV1.self]
    }
    static var stages: [MigrationStage] { [] }
}
