//
//  BiteLedgerSchema.swift
//  BiteLedger
//
//  Defines the versioned SwiftData schema history and migration plan.
//
//  ## Why there is no active migration plan yet
//
//  SwiftData's MigrationStage.custom requires each VersionedSchema to produce
//  a DISTINCT schema fingerprint. That only works when old schema versions are
//  defined as FROZEN nested model types inside their schema enum (like Core Data
//  NSManagedObject subclasses per version). If both SchemaV1 and SchemaV2
//  reference the same live Swift model types, SwiftData sees identical fingerprints
//  and throws "current model reference and next model reference cannot be equal."
//
//  Adding `unit: String?` (an optional with a nil default) is a lightweight
//  migration that SwiftData handles automatically at the SQLite level — it just
//  adds a nullable column. No explicit migration plan is needed for this change.
//  Existing records get `unit = nil`; the startup backfill in BiteLedgerApp.swift
//  then populates them using ServingSizeParser.
//
//  ## When to add a real migration plan
//
//  Use VersionedSchema + SchemaMigrationPlan when a future change CANNOT be
//  handled automatically:
//    - Renaming a stored property
//    - Changing a property type (e.g. String → Int)
//    - Splitting or merging model types
//    - Adding a required (non-optional) property with a non-nil default
//
//  For those cases, define frozen nested model types inside the old schema enum
//  (separate Swift classes mirroring the old model structure), then reference
//  those frozen types in the fromVersion schema and the live types in toVersion.
//  Wire BiteLedgerMigrationPlan back into ModelContainer at that point.
//

import SwiftData
import BiteLedgerCore

// MARK: - SchemaV1 (current)
//
// Lists all 9 live model types in canonical order (must match RecipeCardApp.swift).
// Used as the baseline for any future SchemaMigrationPlan.
// Nullable field additions (Bool?, Date?) are handled automatically by SwiftData —
// no explicit migration stage needed; just define SchemaV2 with the same models.
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

// MARK: - Future migration plan (uncomment when a breaking schema change is needed)
//
// enum BiteLedgerMigrationPlan: SchemaMigrationPlan {
//     static var schemas: [any VersionedSchema.Type] { [BiteLedgerSchemaV1.self] }
//     static var stages: [MigrationStage] { [] }
// }
