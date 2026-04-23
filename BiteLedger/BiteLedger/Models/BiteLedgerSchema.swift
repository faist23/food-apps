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
//    4. Do the same in BitePlanSchema.swift (coordinated release required).
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
// Must match BitePlanSchema.swift exactly.
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
// Must match BitePlanSchemaV2 exactly (same models, same order, same version).
// BitePlan registers FoodHistoryEntry but never queries it — shared store
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
// MARK: - SchemaV3 (T-12 — MealPlan + MealPlanEntry week planner)
//
// Adds two new entities: MealPlan (one per calendar week) and MealPlanEntry
// (one per meal slot per day). This is a lightweight migration — new entities
// with no required fields.
//
// Do NOT wire migrationPlan: into ModelContainer — see comment above.
// Must match BitePlanSchemaV3 exactly (same models, same order, same version).
// BitePlan reads MealPlan/MealPlanEntry. BiteLedger registers them but does
// not query them in v1.
//
enum BiteLedgerSchemaV3: VersionedSchema {
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
// Adds two new entities: MealPlanMeal (named cluster per meal slot per day) and
// MealPlanMealItem (one item in a cluster). Schema grows to 14 models.
//
// MealPlan.meals relationship added (cascade delete to MealPlanMeal).
// MealPlanEntry is retained for backward compat but UI no longer populates it.
// Existing MealPlanEntry records are cleared on first V4 launch in loadOrCreatePlan().
//
// Do NOT wire migrationPlan: into ModelContainer — same policy as V2/V3.
// Must match BitePlanSchemaV4 exactly (same models, same order, same version).
//
enum BiteLedgerSchemaV4: VersionedSchema {
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

// MARK: - SchemaV5 (T-12-RestoreUpdate — id: UUID on MealPlan/MealPlanMeal/MealPlanMealItem)
//
// Adds a plain `var id: UUID = UUID()` property to MealPlan, MealPlanMeal, and
// MealPlanMealItem. No @Attribute(.unique) — lightweight migration safe.
// These IDs are used by CSVExporter/CSVImporter for the meal plan backup round-trip.
//
// Do NOT wire migrationPlan: into ModelContainer — same policy as V2/V3/V4.
// Must match BiteRecipeSchemaV5 exactly (same models, same order, same version).
//
enum BiteLedgerSchemaV5: VersionedSchema {
    static let versionIdentifier = Schema.Version(5, 0, 0)
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
            MealPlanMeal.self,
            MealPlanMealItem.self,
        ]
    }
}

enum BiteLedgerMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [BiteLedgerSchemaV1.self, BiteLedgerSchemaV2.self, BiteLedgerSchemaV3.self, BiteLedgerSchemaV4.self, BiteLedgerSchemaV5.self]
    }
    static var stages: [MigrationStage] {
        [
            .lightweight(fromVersion: BiteLedgerSchemaV1.self, toVersion: BiteLedgerSchemaV2.self),
            .lightweight(fromVersion: BiteLedgerSchemaV2.self, toVersion: BiteLedgerSchemaV3.self),
            .lightweight(fromVersion: BiteLedgerSchemaV3.self, toVersion: BiteLedgerSchemaV4.self),
            .lightweight(fromVersion: BiteLedgerSchemaV4.self, toVersion: BiteLedgerSchemaV5.self),
        ]
    }
}
