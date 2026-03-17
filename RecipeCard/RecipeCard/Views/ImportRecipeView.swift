//
//  ImportRecipeView.swift
//  RecipeCard
//

import SwiftUI
import SwiftData
import BiteLedgerCore

struct ImportRecipeView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    var prefilledURL: String? = nil

    @State private var urlText = ""
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var importResult: RecipeImportResult?
    @State private var showingReview = false

    private let service = RecipeImportService.fromPlist()

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("https://", text: $urlText)
                        .keyboardType(.URL)
                        .autocorrectionDisabled()
                        .autocapitalization(.none)
                } header: {
                    Text("Recipe URL")
                } footer: {
                    Text("Paste a link from any recipe site that uses standard recipe markup (AllRecipes, Food Network, NYT Cooking, etc.).")
                }

                if let error = errorMessage {
                    Section {
                        Label(error, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.red)
                            .font(.subheadline)
                    }
                }

                Section {
                    Button {
                        Task { await importRecipe() }
                    } label: {
                        HStack {
                            Spacer()
                            if isLoading {
                                ProgressView()
                                    .padding(.trailing, 8)
                                Text("Importing…")
                            } else {
                                Text("Import Recipe")
                                    .bold()
                            }
                            Spacer()
                        }
                    }
                    .disabled(urlText.trimmingCharacters(in: .whitespaces).isEmpty || isLoading)
                }
            }
            .navigationTitle("Import from URL")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                // Use prefilledURL if provided by the notification path, otherwise
                // check UserDefaults directly (handles cold-launch via URL scheme where
                // the notification fires before RecipesListView is in the hierarchy).
                let resolved: String? = {
                    if let url = prefilledURL, !url.isEmpty { return url }
                    let defaults = UserDefaults(suiteName: "group.com.ridepro.biteledger")
                    if let stored = defaults?.string(forKey: "pendingRecipeURL"), !stored.isEmpty {
                        defaults?.removeObject(forKey: "pendingRecipeURL")
                        return stored
                    }
                    return nil
                }()
                if let url = resolved {
                    urlText = url
                    Task { await importRecipe() }
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .navigationDestination(isPresented: $showingReview) {
                if let result = importResult {
                    RecipeImportReviewView(result: result, onSave: { dismiss() })
                }
            }
        }
    }

    private func importRecipe() async {
        errorMessage = nil
        isLoading = true
        defer { isLoading = false }

        do {
            let result = try await service.importRecipe(from: urlText)
            importResult = result
            showingReview = true
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
