//
//  BackupRestoreView.swift
//  BitePlan
//
//  Backup & Restore screen for BitePlan. Shares the same ZIP format and
//  BackupService as BiteLedger — both apps back up the full shared store.
//

import SwiftUI
import SwiftData
import BiteLedgerCore
import UniformTypeIdentifiers

struct BackupRestoreView: View {
    @Environment(\.modelContext) private var modelContext
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
    @State private var showingResetConfirmation = false
    @State private var isResetting = false

    // Error
    @State private var errorMessage: String?
    @State private var showingError = false

    private var storeIsEmpty: Bool { allRecipes.isEmpty }

    private var storeSummary: String {
        allRecipes.isEmpty ? "No recipes" : "\(allRecipes.count) recipe\(allRecipes.count == 1 ? "" : "s")"
    }

    private var resetConfirmationMessage: String {
        "Permanently delete all \(allRecipes.count) recipes and their ingredients? This cannot be undone."
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
                Text("Creates a .zip file you can save to Files, iCloud Drive, or AirDrop to another device. Includes all recipes, ingredients, and photos.")
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
                    : "Merge adds backup data alongside your existing recipes, skipping recipes that already exist.")
            }

            // MARK: — Danger Zone
            Section {
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
                        Text(isResetting ? "Resetting…" : "Delete All Recipes")
                    }
                }
                .disabled(isResetting || storeIsEmpty)
            } header: {
                Text("Danger Zone")
            } footer: {
                Text("Permanently deletes all recipes and their ingredients. Cannot be undone. Create a backup first.")
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
        .alert("Delete All Recipes?", isPresented: $showingResetConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Delete All Recipes", role: .destructive) {
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

    // MARK: - Actions

    private func createBackup() {
        isExporting = true
        Task {
            do {
                let url = try await BackupService.createBackup(
                    context: modelContext,
                    exportedBy: "BitePlan"
                )
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
                    if restoreResult.recipesImported > 0 { parts.append("\(restoreResult.recipesImported) recipes") }
                    if restoreResult.foodsImported > 0 { parts.append("\(restoreResult.foodsImported) foods") }
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
            await BackupService.resetDatabase(scope: .recipesOnly, context: modelContext)
            await MainActor.run {
                isResetting = false
                resultTitle = "Recipes Deleted"
                resultMessage = "All recipes and their ingredients have been deleted."
                showingResult = true
            }
        }
    }
}

// MARK: - Share Sheet

private struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

#Preview {
    NavigationStack {
        BackupRestoreView()
    }
}
