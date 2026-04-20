//
//  RecipeBundleImportView.swift
//  BiteRecipe
//
//  Receiver-side sheet. Parses the .biterecipe ZIP, checks for duplicates,
//  then auto-imports — no "Add" tap required. Duplicate detection surfaces
//  an alert before committing.
//

import SwiftUI
import SwiftData
import BiteLedgerCore

extension Notification.Name {
    static let biteRecipeBundleImported = Notification.Name("biteRecipeBundleImported")
}

struct RecipeBundleImportView: View {
    let bundleURL: URL
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var bundle: RecipeShareBundle? = nil
    @State private var imageData: Data? = nil
    @State private var parseError: String? = nil
    @State private var importError: String? = nil
    @State private var isImporting = false

    @State private var duplicate: Recipe? = nil
    @State private var showingDuplicateAlert = false

    var body: some View {
        NavigationStack {
            Group {
                if let err = parseError ?? importError {
                    errorView(err)
                } else {
                    loadingView
                }
            }
            .navigationTitle("Incoming Recipe")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .disabled(isImporting)
                }
            }
        }
        .task { await loadAndImport() }
        .alert("Recipe Already Exists", isPresented: $showingDuplicateAlert) {
            Button("Replace", role: .destructive) {
                performImport(replacing: duplicate)
            }
            Button("Keep Both") {
                performImport(replacing: nil)
            }
            Button("Cancel", role: .cancel) { dismiss() }
        } message: {
            if let dup = duplicate {
                Text("You already have a recipe named \"\(dup.name)\". What would you like to do?")
            }
        }
    }

    // MARK: - Views

    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
            Text(isImporting ? "Adding to library…" : "Loading recipe…")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func errorView(_ message: String) -> some View {
        VStack(spacing: 24) {
            Spacer()
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 48))
                .foregroundStyle(.orange)
            Text(message)
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Button("Dismiss") { dismiss() }
                .buttonStyle(.bordered)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Load + Auto-Import

    private func loadAndImport() async {
        // Step 1: file I/O + parse (off main thread is fine inside Task)
        let parseResult: Result<(RecipeShareBundle, Data?), Error>
        do {
            // Security-scoped URL: AirDrop delivers a scoped URL when
            // LSSupportsOpeningDocumentsInPlace = true. Copy to temp so we can
            // release the scope grant before the async parse runs.
            let needsScope = bundleURL.startAccessingSecurityScopedResource()
            let workingURL: URL
            do {
                let tmp = FileManager.default.temporaryDirectory
                    .appendingPathComponent(bundleURL.lastPathComponent)
                try? FileManager.default.removeItem(at: tmp)
                try FileManager.default.copyItem(at: bundleURL, to: tmp)
                workingURL = tmp
            } catch {
                if needsScope { bundleURL.stopAccessingSecurityScopedResource() }
                throw error
            }
            if needsScope { bundleURL.stopAccessingSecurityScopedResource() }

            let parsed = try RecipeShareBundleService.parseBundle(at: workingURL)
            let imgData = RecipeShareBundleService.extractImageData(from: workingURL)
            try? FileManager.default.removeItem(at: workingURL)
            parseResult = .success((parsed, imgData))
        } catch {
            parseResult = .failure(error)
        }

        // Step 2: back to main thread for SwiftData + state
        await MainActor.run {
            switch parseResult {
            case .failure(let e):
                parseError = e.localizedDescription
            case .success(let (parsed, imgData)):
                bundle = parsed
                imageData = imgData
                triggerImport(bundle: parsed)
            }
        }
    }

    @MainActor
    private func triggerImport(bundle: RecipeShareBundle) {
        do {
            duplicate = try RecipeShareBundleService.findDuplicate(for: bundle, in: modelContext)
            if duplicate != nil {
                showingDuplicateAlert = true
            } else {
                performImport(replacing: nil)
            }
        } catch {
            importError = error.localizedDescription
        }
    }

    // MARK: - Import

    private func performImport(replacing dup: Recipe?) {
        guard let b = bundle else { return }
        Task { @MainActor in
            isImporting = true
            importError = nil
            do {
                let recipe = try RecipeShareBundleService.importBundle(
                    b,
                    imageData: imageData,
                    into: modelContext,
                    replacing: dup
                )
                // Explicit save: autosave won't fire before the view is deallocated
                // on dismiss, so changes would be lost without this.
                try modelContext.save()
                NotificationCenter.default.post(
                    name: .biteRecipeBundleImported,
                    object: nil,
                    userInfo: ["recipeID": recipe.id, "recipeName": recipe.name]
                )
                dismiss()
            } catch {
                importError = error.localizedDescription
                isImporting = false
            }
        }
    }
}
