//
//  BackupService.swift
//  BiteLedgerCore
//
//  ZIP-based backup and restore for the shared SwiftData store.
//  Creates a single .zip containing manifest.json, 5 CSV files, and
//  optional recipe images. Works for BiteLedger-only, RecipeCard-only,
//  and both-apps users (shared App Group store).
//

import Foundation
import SwiftData
import ZIPFoundation

// MARK: - Public Types

public struct BackupManifest: Codable, Sendable {
    public let version: Int          // format version — bump if ZIP structure changes
    public let exportDate: Date
    public let exportedBy: String    // "BiteLedger" | "RecipeCard"
    public let stats: Stats

    public struct Stats: Codable, Sendable {
        public let foods: Int
        public let logs: Int
        public let recipes: Int
    }

    public init(version: Int, exportDate: Date, exportedBy: String, stats: Stats) {
        self.version = version
        self.exportDate = exportDate
        self.exportedBy = exportedBy
        self.stats = stats
    }
}

public enum BackupConflictMode: Sendable {
    /// Delete all existing data first, then import. Produces an exact replica.
    case replaceAll
    /// Skip items whose UUIDs already exist. Adds backup data alongside existing data.
    case merge
}

public enum BackupResetScope: Sendable {
    /// Delete FoodLog records only. Keeps foods, recipes.
    case logsOnly
    /// Delete FoodLog + FoodItem + ServingSize. Keeps recipes.
    case allFoodData
    /// Delete Recipe + RecipeIngredient only. Keeps food logs and food items.
    case recipesOnly
    /// Delete everything in the shared store.
    case everything
}

public struct BackupRestoreResult: Sendable {
    public let foodsImported: Int
    public let servingsImported: Int
    public let logsImported: Int
    public let recipesImported: Int
    public let ingredientsImported: Int
    public let errors: [String]
    public let manifest: BackupManifest?

    public init(
        foodsImported: Int,
        servingsImported: Int,
        logsImported: Int,
        recipesImported: Int,
        ingredientsImported: Int,
        errors: [String],
        manifest: BackupManifest?
    ) {
        self.foodsImported = foodsImported
        self.servingsImported = servingsImported
        self.logsImported = logsImported
        self.recipesImported = recipesImported
        self.ingredientsImported = ingredientsImported
        self.errors = errors
        self.manifest = manifest
    }
}

public enum BackupError: LocalizedError {
    case archiveCreationFailed
    case invalidArchive
    case missingRequiredFiles
    case exportFailed(String)

    public var errorDescription: String? {
        switch self {
        case .archiveCreationFailed:  return "Failed to create backup archive."
        case .invalidArchive:         return "The selected file is not a valid backup."
        case .missingRequiredFiles:   return "Backup is missing required data files."
        case .exportFailed(let msg):  return "Export failed: \(msg)"
        }
    }
}

// MARK: - BackupService

public struct BackupService {

    // MARK: - Create Backup

    /// Exports the full shared store as a single ZIP file.
    /// Returns a `file://` URL to the ZIP in the temp directory.
    /// Caller is responsible for deleting the ZIP after the share sheet dismisses.
    @MainActor
    public static func createBackup(
        context: ModelContext,
        exportedBy: String = "BiteLedger"
    ) async throws -> URL {

        // 1. Export all data as CSVs (reads from shared store on main actor)
        let package = try CSVExporter.exportAll(context: context)

        // 2. Collect recipe image file:// URLs for streaming (no Data in memory)
        let recipes = try context.fetch(FetchDescriptor<Recipe>())
        let imageFileURLs: [(filename: String, url: URL)] = recipes.compactMap { recipe in
            guard let urlString = recipe.imageURL,
                  urlString.hasPrefix("file://"),
                  let url = URL(string: urlString),
                  FileManager.default.fileExists(atPath: url.path) else { return nil }
            return ("\(recipe.id.uuidString).jpg", url)
        }

        // 3. Build manifest
        let csvLineCount: (String) -> Int = { csv in
            max(0, csv.components(separatedBy: "\n").filter { !$0.isEmpty }.count - 1)
        }
        let manifest = BackupManifest(
            version: 1,
            exportDate: Date(),
            exportedBy: exportedBy,
            stats: BackupManifest.Stats(
                foods: csvLineCount(package.foodsCSV),
                logs: csvLineCount(package.logsCSV),
                recipes: csvLineCount(package.recipesCSV)
            )
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = .prettyPrinted
        let manifestData = try encoder.encode(manifest)

        // 4. Create temp staging directory
        let stagingDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("BLBackupStage_\(Int(Date().timeIntervalSince1970))", isDirectory: true)
        try FileManager.default.createDirectory(at: stagingDir, withIntermediateDirectories: true)

        // Always clean up staging dir when done
        defer { try? FileManager.default.removeItem(at: stagingDir) }

        // 5. Write manifest and CSVs to staging dir
        try manifestData.write(to: stagingDir.appendingPathComponent("manifest.json"))
        try package.foodsCSV.write(to: stagingDir.appendingPathComponent("foods.csv"), atomically: true, encoding: .utf8)
        try package.servingsCSV.write(to: stagingDir.appendingPathComponent("servings.csv"), atomically: true, encoding: .utf8)
        try package.logsCSV.write(to: stagingDir.appendingPathComponent("logs.csv"), atomically: true, encoding: .utf8)
        try package.recipesCSV.write(to: stagingDir.appendingPathComponent("recipes.csv"), atomically: true, encoding: .utf8)
        try package.ingredientsCSV.write(to: stagingDir.appendingPathComponent("ingredients.csv"), atomically: true, encoding: .utf8)

        // 6. Copy recipe images to staging/images/
        if !imageFileURLs.isEmpty {
            let imagesDir = stagingDir.appendingPathComponent("images", isDirectory: true)
            try FileManager.default.createDirectory(at: imagesDir, withIntermediateDirectories: true)
            for (filename, sourceURL) in imageFileURLs {
                let destURL = imagesDir.appendingPathComponent(filename)
                try FileManager.default.copyItem(at: sourceURL, to: destURL)
            }
        }

        // 7. Build ZIP archive from staging dir
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let zipName = "BiteLedger_Backup_\(formatter.string(from: Date())).zip"
        let zipURL = FileManager.default.temporaryDirectory.appendingPathComponent(zipName)
        try? FileManager.default.removeItem(at: zipURL)  // remove stale file if present

        let archive = try Archive(url: zipURL, accessMode: .create)

        // Enumerate staging dir and add each file to the archive
        let enumerator = FileManager.default.enumerator(
            at: stagingDir,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        )
        while let fileURL = enumerator?.nextObject() as? URL {
            guard let resourceValues = try? fileURL.resourceValues(forKeys: [.isRegularFileKey]),
                  resourceValues.isRegularFile == true else { continue }
            // Relative path inside the ZIP (strip staging dir prefix + path separator)
            let relativePath = String(fileURL.path.dropFirst(stagingDir.path.count + 1))
            try archive.addEntry(with: relativePath, fileURL: fileURL)
        }

        return zipURL
    }

    // MARK: - Restore Backup

    /// Restores from a backup ZIP file.
    /// - `conflictMode`: `.replaceAll` wipes all data first; `.merge` skips existing UUIDs.
    @MainActor
    public static func restoreBackup(
        from zipURL: URL,
        conflictMode: BackupConflictMode,
        context: ModelContext
    ) async throws -> BackupRestoreResult {

        // 1. Create temp extraction directory
        let extractDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("BLRestore_\(Int(Date().timeIntervalSince1970))", isDirectory: true)
        try FileManager.default.createDirectory(at: extractDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: extractDir) }

        // 2. Extract ZIP
        let archive = try Archive(url: zipURL, accessMode: .read)
        for entry in archive where entry.type == .file {
            let destURL = extractDir.appendingPathComponent(entry.path)
            try FileManager.default.createDirectory(
                at: destURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            _ = try archive.extract(entry, to: destURL)
        }

        // 3. Read manifest (optional — resilient to missing/malformed)
        var manifest: BackupManifest?
        let manifestURL = extractDir.appendingPathComponent("manifest.json")
        if let manifestData = try? Data(contentsOf: manifestURL) {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            manifest = try? decoder.decode(BackupManifest.self, from: manifestData)
        }

        // 4. Validate required CSV files
        let foodsURL = extractDir.appendingPathComponent("foods.csv")
        let servingsURL = extractDir.appendingPathComponent("servings.csv")
        let logsURL = extractDir.appendingPathComponent("logs.csv")
        guard FileManager.default.fileExists(atPath: foodsURL.path),
              FileManager.default.fileExists(atPath: servingsURL.path),
              FileManager.default.fileExists(atPath: logsURL.path) else {
            throw BackupError.missingRequiredFiles
        }

        // 5. Build image map from images/ subdirectory
        var imageMap: [String: Data] = [:]
        let imagesDir = extractDir.appendingPathComponent("images")
        if FileManager.default.fileExists(atPath: imagesDir.path),
           let imageFiles = try? FileManager.default.contentsOfDirectory(
               at: imagesDir,
               includingPropertiesForKeys: nil
           ) {
            for imageURL in imageFiles {
                let uuidString = imageURL.deletingPathExtension().lastPathComponent
                if let data = try? Data(contentsOf: imageURL), !uuidString.isEmpty {
                    imageMap[uuidString] = data
                }
            }
        }

        // 6. Read CSVs
        let foodsCSV = try String(contentsOf: foodsURL, encoding: .utf8)
        let servingsCSV = try String(contentsOf: servingsURL, encoding: .utf8)
        let logsCSV = try String(contentsOf: logsURL, encoding: .utf8)

        let recipesURL = extractDir.appendingPathComponent("recipes.csv")
        let recipesCSV: String? = FileManager.default.fileExists(atPath: recipesURL.path)
            ? (try? String(contentsOf: recipesURL, encoding: .utf8)) : nil

        let ingredientsURL = extractDir.appendingPathComponent("ingredients.csv")
        let ingredientsCSV: String? = FileManager.default.fileExists(atPath: ingredientsURL.path)
            ? (try? String(contentsOf: ingredientsURL, encoding: .utf8)) : nil

        // 7. For replaceAll: wipe database before importing
        if conflictMode == .replaceAll {
            await resetDatabase(scope: .everything, context: context)
        }

        // 8. Import
        let importResult = try CSVImporter.importBiteLedger(
            foodsCSV: foodsCSV,
            servingsCSV: servingsCSV,
            logsCSV: logsCSV,
            recipesCSV: recipesCSV,
            ingredientsCSV: ingredientsCSV,
            imageMap: imageMap,
            skipExistingUUIDs: conflictMode == .merge,
            context: context
        )

        return BackupRestoreResult(
            foodsImported: importResult.foodsCreated,
            servingsImported: importResult.servingsCreated,
            logsImported: importResult.logsCreated,
            recipesImported: importResult.recipesCreated,
            ingredientsImported: importResult.ingredientsCreated,
            errors: importResult.errors,
            manifest: manifest
        )
    }

    // MARK: - Factory Reset

    /// Deletes data from the shared store according to the specified scope.
    /// Runs deletions on a background ModelContext to avoid blocking the main thread.
    @MainActor
    public static func resetDatabase(
        scope: BackupResetScope,
        context: ModelContext
    ) async {
        let container = context.container

        await Task.detached(priority: .userInitiated) {
            let ctx = ModelContext(container)

            if scope == .recipesOnly {
                // Delete recipe ingredients first (no cascade from Recipe to RecipeIngredient for ingredients)
                if let ingredients = try? ctx.fetch(FetchDescriptor<RecipeIngredient>()) {
                    for i in ingredients { ctx.delete(i) }
                    try? ctx.save()
                }
                // Delete recipes and their local images
                if let recipes = try? ctx.fetch(FetchDescriptor<Recipe>()) {
                    for r in recipes {
                        if let urlString = r.imageURL, urlString.hasPrefix("file://") {
                            RecipeImportService.deleteLocalImage(urlString: urlString)
                        }
                        ctx.delete(r)
                    }
                    try? ctx.save()
                }
                return
            }

            // Delete food logs
            if let logs = try? ctx.fetch(FetchDescriptor<FoodLog>()) {
                for log in logs { ctx.delete(log) }
                try? ctx.save()
            }

            if scope == .logsOnly { return }

            // Nullify RecipeIngredient.servingSize before deleting ServingSizes
            // (no declared inverse relationship — must be done manually to avoid crash)
            if let ingredients = try? ctx.fetch(FetchDescriptor<RecipeIngredient>()) {
                for ing in ingredients { ing.servingSize = nil }
                try? ctx.save()
            }

            // Delete serving sizes
            if let servings = try? ctx.fetch(FetchDescriptor<ServingSize>()) {
                for s in servings { ctx.delete(s) }
                try? ctx.save()
            }

            // Delete food items
            if let foods = try? ctx.fetch(FetchDescriptor<FoodItem>()) {
                for f in foods { ctx.delete(f) }
                try? ctx.save()
            }

            if scope == .allFoodData { return }

            // Delete recipe ingredients
            if let ingredients = try? ctx.fetch(FetchDescriptor<RecipeIngredient>()) {
                for i in ingredients { ctx.delete(i) }
                try? ctx.save()
            }

            // Delete recipes and their local images
            if let recipes = try? ctx.fetch(FetchDescriptor<Recipe>()) {
                for r in recipes {
                    if let urlString = r.imageURL, urlString.hasPrefix("file://") {
                        RecipeImportService.deleteLocalImage(urlString: urlString)
                    }
                    ctx.delete(r)
                }
                try? ctx.save()
            }
        }.value

        // Reset streak cache on main context (UserPreferences lives in shared store)
        if let prefs = (try? context.fetch(FetchDescriptor<UserPreferences>()))?.first {
            prefs.cachedStreak = 0
            prefs.streakCachedDate = nil
            try? context.save()
        }
    }

    // MARK: - Helpers

    /// Deletes a backup ZIP file that is no longer needed (e.g. after share sheet dismisses).
    public static func deleteBackupFile(at url: URL) {
        guard url.pathExtension == "zip" else { return }
        try? FileManager.default.removeItem(at: url)
    }
}
