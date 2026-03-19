//
//  OCRTextReviewView.swift
//  RecipeCard
//
//  Intermediate screen between camera OCR and RecipeImportReviewView.
//  Shows raw OCR lines in an editable TextEditor so the user can fix
//  handwriting misreads before sending the text to Claude for structuring.
//

import SwiftUI
import UIKit
import BiteLedgerCore

struct OCRTextReviewView: View {
    let rawLines: [String]
    /// First scanned photo — passed forward to RecipeImportReviewView so it can be
    /// saved to disk when the user confirms and saves the recipe.
    let scannedImage: UIImage?
    let onSave: () -> Void

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    private let service = RecipeImportService.fromPlist()

    @State private var editedText: String
    @State private var source: String = ""
    @State private var status: Status = .idle
    @State private var importResult: RecipeImportResult?
    @State private var showingReview = false

    private enum Status: Equatable {
        case idle
        case parsing
        case failed(String)
    }

    init(rawLines: [String], scannedImage: UIImage? = nil, onSave: @escaping () -> Void) {
        self.rawLines = rawLines
        self.scannedImage = scannedImage
        self.onSave = onSave
        _editedText = State(initialValue: rawLines.joined(separator: "\n"))
    }

    var body: some View {
        Form {
            // MARK: Scanned Text
            Section {
                TextEditor(text: $editedText)
                    .font(.system(.body, design: .monospaced))
                    .frame(minHeight: 300)
                    .disabled(status == .parsing)
            } header: {
                Text("Scanned Text")
            } footer: {
                Text("Fix any OCR errors before processing — each line should be exactly as written on the recipe card.")
            }

            // MARK: Recipe Source
            Section {
                TextField("e.g. Pat Faist, NY Times", text: $source)
                    .autocorrectionDisabled()
                    .disabled(status == .parsing)
            } header: {
                Text("Recipe Source")
            } footer: {
                Text("Where this recipe comes from. Optional.")
            }

            // MARK: Process button
            Section {
                Button {
                    Task { await process() }
                } label: {
                    HStack {
                        Spacer()
                        if status == .parsing {
                            ProgressView().padding(.trailing, 8)
                            Text("Structuring recipe…")
                        } else {
                            Text("Process Recipe")
                                .bold()
                        }
                        Spacer()
                    }
                }
                .disabled(
                    status == .parsing ||
                    editedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                )
            }

            // MARK: Error
            if case .failed(let msg) = status {
                Section {
                    Label(msg, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.red)
                        .font(.subheadline)
                }
            }
        }
        .navigationTitle("Review Scan")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(isPresented: $showingReview) {
            if let result = importResult {
                RecipeImportReviewView(
                    result: result,
                    prefilledSource: source.trimmingCharacters(in: .whitespaces),
                    scannedImage: scannedImage,
                    onSave: onSave
                )
            }
        }
    }

    // MARK: - Pipeline

    @MainActor
    private func process() async {
        let lines = editedText
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        guard !lines.isEmpty else {
            status = .failed("No text to process. Add or fix the scanned text above.")
            return
        }

        // Inject user-typed source as a hint so Claude can see it
        var linesForService = lines
        let trimmedSource = source.trimmingCharacters(in: .whitespaces)
        if !trimmedSource.isEmpty {
            linesForService.insert("Source: \(trimmedSource)", at: 0)
        }

        status = .parsing
        do {
            let result = try await service.importFromOCRLines(linesForService)
            // Auto-fill source from the card if user left it blank
            if source.trimmingCharacters(in: .whitespaces).isEmpty,
               let detected = result.detectedSource, !detected.isEmpty {
                source = detected
            }
            importResult = result
            status = .idle
            showingReview = true
        } catch RecipeImportError.noIngredients {
            status = .failed("No ingredients found. Try correcting the scanned text above.")
        } catch RecipeImportError.noRecipeFound {
            status = .failed("Couldn't identify a recipe. Make sure the ingredient list is visible in the text.")
        } catch {
            status = .failed(error.localizedDescription)
        }
    }
}
