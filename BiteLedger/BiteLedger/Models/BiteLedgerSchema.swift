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

// Placeholder — wire into ModelContainer when a real migration plan is needed.
// enum BiteLedgerMigrationPlan: SchemaMigrationPlan { ... }
