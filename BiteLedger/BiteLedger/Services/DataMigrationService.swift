//
//  DataMigrationService.swift
//  BiteLedger
//
//  Created by Craig Faist on 2/25/26.
//

import SwiftData
import Foundation
import BiteLedgerCore

/// Service to migrate existing per-100g data to serving-based model
actor DataMigrationService {
    
    /// Check if migration has already been completed
    private static func needsMigration(container: ModelContainer) -> Bool {
        let context = ModelContext(container)

        // Check if any ServingSize entries exist
        let servingDescriptor = FetchDescriptor<ServingSize>()
        let servingCount = (try? context.fetchCount(servingDescriptor)) ?? 0

        // If we have FoodItems but no ServingSizes, we need to migrate
        let foodDescriptor = FetchDescriptor<FoodItem>()
        let foodCount = (try? context.fetchCount(foodDescriptor)) ?? 0

        return foodCount > 0 && servingCount == 0
    }
    
    /// Main migration function - converts per-100g data to serving-based
    static func migrateToServingBasedModel(container: ModelContainer) async {
        // Check if migration is needed
        guard needsMigration(container: container) else {
            print("Migration not needed - already migrated or no data")
            return
        }
        
        print("🔄 Starting migration to serving-based model...")
        
        // This migration is DESTRUCTIVE because the old model is incompatible
        // We need to delete all data and start fresh
        // The user should export their data first using the old CSV export

        print("⚠️ Migration requires fresh start - incompatible schema changes")
        print("💡 User should have exported data using old app version")

        // The new schema is incompatible, so SwiftData will handle this
        // by creating new tables. Old data will be lost unless user imports
        // from CSV export
    }
}
