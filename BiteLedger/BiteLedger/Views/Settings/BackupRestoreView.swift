//
//  BackupRestoreView.swift
//  BiteLedger
//
//  Unified Backup & Restore screen. iOS Settings aesthetic — Form/List,
//  no decorative hero icons. Replaces DataExportView.
//

import SwiftUI
import SwiftData
import BiteLedgerCore
import UniformTypeIdentifiers

struct BackupRestoreView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var preferences: [UserPreferences]
    @Query private var allLogs: [FoodLog]
    @Query private var allFoods: [FoodItem]
    @Query private var allRecipes: [Recipe]

    // Backup
    @State private var isExporting = false
    @State private var backupURL: URL?
    @State private var showingShareSheet = false

    // Restore
    @State private var showingFilePicker = false
    @State private var isImporting = false
    @State private var conflictMode: BackupConflictMode = .replaceAll
    @State private var importProgress = ""

    // Results
    @State private var showingResult = false
    @State private var resultTitle = ""
    @State private var resultMessage = ""

    // Factory Reset
    @State private var resetScope: BackupResetScope = .everything
    @State private var showingResetConfirmation = false
    @State private var isResetting = false

    // Error
    @State private var errorMessage: String?
    @State private var showingError = false

    private var storeIsEmpty: Bool {
        allLogs.isEmpty && allFoods.isEmpty && allRecipes.isEmpty
    }

    private var storeSummary: String {
        var parts: [String] = []
        if !allLogs.isEmpty { parts.append("\(allLogs.count) logs") }
        if !allFoods.isEmpty { parts.append("\(allFoods.count) foods") }
        if !allRecipes.isEmpty { parts.append("\(allRecipes.count) recipes") }
        return parts.isEmpty ? "Nothing to back up" : parts.joined(separator: ", ")
    }

    private var resetButtonLabel: String {
        switch resetScope {
        case .logsOnly:    return "Delete Food Logs"
        case .allFoodData: return "Delete Food Data"
        case .recipesOnly: return "Delete Recipes"
        case .everything:  return "Delete Everything"
        }
    }

    private var resetConfirmationMessage: String {
        switch resetScope {
        case .logsOnly:
            return "Permanently delete all \(allLogs.count) food logs? Your food items and recipes will remain."
        case .allFoodData:
            return "Permanently delete all food logs and food items? Your recipes will remain."
        case .recipesOnly:
            return "Permanently delete all \(allRecipes.count) recipes and their ingredients? Your food logs will remain."
        case .everything:
            return "Permanently delete all \(allLogs.count) food logs, all food items, and all \(allRecipes.count) recipes? This cannot be undone."
        }
    }

    var body: some View {
        Form {
            // MARK: — Backup
            Section {
                LabeledContent("Contents", value: storeSummary)
                    .foregroundStyle(storeIsEmpty ? Color("TextSecondary") : .primary)

                Button {
                    createBackup()
                } label: {
                    HStack {
                        if isExporting {
                            ProgressView()
                                .scaleEffect(0.85)
                        } else {
                            Image(systemName: "arrow.down.doc")
                                .foregroundStyle(storeIsEmpty ? Color("TextSecondary") : Color("BrandPrimary"))
                        }
                        Text(isExporting ? "Creating backup…" : "Create Backup")
                            .foregroundStyle(storeIsEmpty ? Color("TextSecondary") : Color("BrandPrimary"))
                    }
                }
                .disabled(storeIsEmpty || isExporting)
            } header: {
                Text("Backup")
            } footer: {
                Text("Creates a .zip file you can save to Files, iCloud Drive, or AirDrop to another device. Includes all food items, logs, and recipes.")
            }

            // MARK: — Restore
            Section {
                Picker("When restoring", selection: $conflictMode) {
                    Text("Replace All Data").tag(BackupConflictMode.replaceAll)
                    Text("Merge (keep existing)").tag(BackupConflictMode.merge)
                }

                Button {
                    showingFilePicker = true
                } label: {
                    HStack {
                        if isImporting {
                            ProgressView()
                                .scaleEffect(0.85)
                        } else {
                            Image(systemName: "arrow.up.doc")
                                .foregroundStyle(Color("BrandPrimary"))
                        }
                        Text(isImporting ? importProgress : "Restore from Backup File")
                            .foregroundStyle(Color("BrandPrimary"))
                    }
                }
                .disabled(isImporting)
            } header: {
                Text("Restore")
            } footer: {
                Text(conflictMode == .replaceAll
                    ? "Replace All removes all existing data before restoring. Use to move to a new device."
                    : "Merge adds backup data alongside your existing data, skipping items that already exist.")
            }

            // MARK: — Import Legacy CSV
            Section {
                NavigationLink {
                    LoseItImportView()
                } label: {
                    HStack {
                        Image(systemName: "tablecells")
                            .foregroundStyle(Color("BrandAccent"))
                        Text("Import from CSV")
                            .foregroundStyle(.primary)
                    }
                }
            } header: {
                Text("Legacy Import")
            } footer: {
                Text("Import a LoseIt export or older BiteLedger CSV export.")
            }

            // MARK: — Danger Zone
            Section {
                // Inline radio list — 3 tappable rows
                resetScopeRow("Delete logs only", .logsOnly,
                               detail: "Removes food logs; keeps food items and recipes.")
                resetScopeRow("Delete all food data", .allFoodData,
                               detail: "Removes logs and food items; keeps recipes.")
                resetScopeRow("Delete everything", .everything,
                               detail: "Removes all logs, food items, and recipes.")

                Button(role: .destructive) {
                    showingResetConfirmation = true
                } label: {
                    HStack {
                        if isResetting {
                            ProgressView()
                                .scaleEffect(0.85)
                        } else {
                            Image(systemName: "trash")
                        }
                        Text(isResetting ? "Resetting…" : resetButtonLabel)
                    }
                }
                .disabled(isResetting)
            } header: {
                Text("Danger Zone")
            } footer: {
                Text("Factory reset cannot be undone. Create a backup first.")
            }
        }
        .navigationTitle("Backup & Restore")
        .navigationBarTitleDisplayMode(.large)
        .sheet(isPresented: $showingShareSheet, onDismiss: {
            if let url = backupURL {
                BackupService.deleteBackupFile(at: url)
                backupURL = nil
            }
        }) {
            if let url = backupURL {
                ShareSheet(items: [url])
            }
        }
        .fileImporter(
            isPresented: $showingFilePicker,
            allowedContentTypes: [UTType(filenameExtension: "zip") ?? .data],
            allowsMultipleSelection: false
        ) { result in
            handleFileSelection(result)
        }
        .alert(resultTitle, isPresented: $showingResult) {
            Button("OK") { }
        } message: {
            Text(resultMessage)
        }
        .alert("Reset Data?", isPresented: $showingResetConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button(resetButtonLabel, role: .destructive) {
                performReset()
            }
        } message: {
            Text(resetConfirmationMessage)
        }
        .alert("Error", isPresented: $showingError) {
            Button("OK") { }
        } message: {
            if let msg = errorMessage { Text(msg) }
        }
    }

    // MARK: - Helper Views

    @ViewBuilder
    private func resetScopeRow(_ label: String, _ scope: BackupResetScope, detail: String) -> some View {
        Button {
            resetScope = scope
        } label: {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: resetScope == scope ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(resetScope == scope ? Color("BrandPrimary") : Color("TextSecondary"))
                    .font(.body)
                    .padding(.top, 1)
                VStack(alignment: .leading, spacing: 2) {
                    Text(label)
                        .foregroundStyle(.primary)
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(Color("TextSecondary"))
                }
                Spacer()
            }
        }
    }

    // MARK: - Actions

    private func createBackup() {
        isExporting = true
        Task {
            do {
                let url = try await BackupService.createBackup(context: modelContext)
                await MainActor.run {
                    backupURL = url
                    isExporting = false
                    showingShareSheet = true
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    isExporting = false
                    showingError = true
                }
            }
        }
    }

    private func handleFileSelection(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            restoreBackup(from: url)
        case .failure(let error):
            errorMessage = error.localizedDescription
            showingError = true
        }
    }

    private func restoreBackup(from url: URL) {
        isImporting = true
        importProgress = "Restoring…"

        Task {
            do {
                let gotAccess = url.startAccessingSecurityScopedResource()
                defer { if gotAccess { url.stopAccessingSecurityScopedResource() } }

                let restoreResult = try await BackupService.restoreBackup(
                    from: url,
                    conflictMode: conflictMode,
                    context: modelContext
                )

                await MainActor.run {
                    isImporting = false
                    importProgress = ""
                    resultTitle = "Restore Complete"
                    var parts: [String] = []
                    if restoreResult.foodsImported > 0 { parts.append("\(restoreResult.foodsImported) foods") }
                    if restoreResult.logsImported > 0 { parts.append("\(restoreResult.logsImported) logs") }
                    if restoreResult.recipesImported > 0 { parts.append("\(restoreResult.recipesImported) recipes") }
                    resultMessage = parts.isEmpty
                        ? "No new items were imported."
                        : "Imported \(parts.joined(separator: ", "))."
                    if !restoreResult.errors.isEmpty {
                        resultMessage += " \(restoreResult.errors.count) item(s) had warnings."
                    }
                    showingResult = true
                }
            } catch {
                await MainActor.run {
                    isImporting = false
                    importProgress = ""
                    errorMessage = error.localizedDescription
                    showingError = true
                }
            }
        }
    }

    private func performReset() {
        isResetting = true
        Task {
            await BackupService.resetDatabase(scope: resetScope, context: modelContext)
            await MainActor.run {
                isResetting = false
                resultTitle = "Reset Complete"
                resultMessage = "Your data has been deleted."
                showingResult = true
            }
        }
    }
}

#Preview {
    NavigationStack {
        BackupRestoreView()
    }
}
