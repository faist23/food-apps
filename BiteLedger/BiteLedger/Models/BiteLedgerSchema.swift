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

// MARK: - SchemaV2 (T-14 — FoodHistoryEntry personal food history index)
//
// Adds FoodHistoryEntry: one record per (FoodItem, MealType), tracking
// lastLoggedDate and logCount. Powers the "Recently logged" section in
// FoodSearchView with an indexed O(1) query instead of scanning FoodLogs.
//
// Migration: lightweight (additive — new model, new relationship on FoodItem,
// new nullable field on UserPreferences). No data transform required.
// Backfill is handled at startup by backfillFoodHistory() in BiteLedgerApp,
// guarded by UserPreferences.hasBackfilledFoodHistory.
//
// Must match RecipeCardSchemaV2 exactly (same models, same order, same version).
// RecipeCard registers FoodHistoryEntry but never queries it — shared store
// requires identical schemas across both apps.
//
enum BiteLedgerSchemaV2: VersionedSchema {
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

// MARK: - Migration plan (NOT currently wired in — see note below)
//
// ⚠️  NOT passed to ModelContainer in BiteLedgerApp.loadContainer().
//
// SwiftData generates CoreData MOMs for each schema version by inspecting the live
// @Model types at runtime.  Because all schema versions reference the same compiled
// @Model classes, SwiftData sees identical entity definitions in every version —
// including implicit inverse relationships that CoreData auto-generates even when
// not declared in Swift.  The result: V1 and V2 produce the same schema checksum,
// causing "Duplicate version checksums detected" at launch.
//
// Workaround: omit the migrationPlan parameter and let SwiftData perform the
// lightweight migration automatically.  Additive changes (new entity, new optional
// fields) are always handled correctly by SwiftData's automatic migration.
//
// Re-introduce the migration plan for SchemaV3 only if a CUSTOM (non-lightweight)
// migration stage is required.  At that point, frozen nested @Model types must be
// defined inside the old schema enums so SwiftData sees genuinely distinct MOMs.
//
enum BiteLedgerMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [BiteLedgerSchemaV1.self, BiteLedgerSchemaV2.self]
    }
    static var stages: [MigrationStage] {
        [
            .lightweight(fromVersion: BiteLedgerSchemaV1.self, toVersion: BiteLedgerSchemaV2.self),
        ]
    }
}
