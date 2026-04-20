//
//  ShareConfirmationView.swift
//  BiteRecipe
//
//  Sender-side sheet. Packages the recipe into a .biterecipe ZIP, then
//  presents the iOS share sheet. Resizes local images to 1024×1024 before
//  handing bytes to RecipeShareBundleService (UIKit resize stays in app layer).
//

import SwiftUI
import SwiftData
import UIKit
import BiteLedgerCore

struct ShareConfirmationView: View {
    let recipe: Recipe
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var bundleURL: URL? = nil
    @State private var isPreparing = true
    @State private var prepError: String? = nil
    @State private var showingShareSheet = false

    private var ingredientCount: Int { recipe.sortedIngredients.count }

    private var subtitle: String {
        let parts: [String] = [
            "\(ingredientCount) ingredient\(ingredientCount == 1 ? "" : "s")",
            recipe.displayTime.map { $0 }
        ].compactMap { $0 }
        return parts.joined(separator: " · ")
    }

    var body: some View {
        VStack(spacing: 0) {
            // Drag handle
            Capsule()
                .fill(Color.secondary.opacity(0.4))
                .frame(width: 36, height: 5)
                .padding(.top, 12)
                .padding(.bottom, 16)

            // Recipe identity row
            HStack(spacing: 12) {
                RecipePhotoView(urlString: recipe.imageURL, contentMode: .fill) {
                    ZStack {
                        Color(Color.surfaceCard)
                        Image(systemName: "fork.knife")
                            .font(.system(size: 20))
                            .foregroundStyle(Color(Color.textTertiary))
                    }
                }
                .frame(width: 56, height: 56)
                .clipShape(RoundedRectangle(cornerRadius: 8))

                VStack(alignment: .leading, spacing: 4) {
                    Text(recipe.name)
                        .font(.title3.bold())
                        .lineLimit(2)
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(Color(Color.textSecondary))
                }
                Spacer()
            }
            .padding(.horizontal, 20)

            Divider()
                .padding(.vertical, 20)

            // State: preparing / error / ready
            if isPreparing {
                VStack(spacing: 12) {
                    ProgressView()
                        .controlSize(.regular)
                    Text("Preparing recipe…")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 24)

            } else if let errorMessage = prepError {
                VStack(spacing: 16) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 32))
                        .foregroundStyle(.orange)
                    Text(errorMessage)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                    Button("Try Again") { prepareBundle() }
                        .buttonStyle(.bordered)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
            }

            Spacer(minLength: 20)
        }
        .presentationDetents([.medium])
        .presentationDragIndicator(.hidden)   // we draw our own
        .task { prepareBundle() }
        .sheet(isPresented: $showingShareSheet, onDismiss: { dismiss() }) {
            if let url = bundleURL {
                RecipeShareSheet(url: url) {
                    try? FileManager.default.removeItem(at: url)
                    bundleURL = nil
                }
            }
        }
    }

    // MARK: - Bundle Preparation

    private func prepareBundle() {
        Task { @MainActor in
            isPreparing = true
            prepError = nil
            do {
                let imageData = prepareImageData()
                bundleURL = try RecipeShareBundleService.createBundle(
                    recipe: recipe,
                    context: modelContext,
                    imageData: imageData
                )
                showingShareSheet = true  // Auto-present share sheet when ready
            } catch {
                prepError = error.localizedDescription
            }
            isPreparing = false
        }
    }

    /// Loads the local recipe image, resizes to 1024×1024, and returns JPEG data.
    /// Returns nil for remote https:// images (URL travels in recipe.json instead).
    @MainActor
    private func prepareImageData() -> Data? {
        guard let urlStr = recipe.imageURL,
              urlStr.hasPrefix("file://"),
              let fileURL = URL(string: urlStr),
              let rawData = try? Data(contentsOf: fileURL),
              let image = UIImage(data: rawData) else { return nil }

        let maxDimension: CGFloat = 1024
        let size = image.size
        if size.width <= maxDimension && size.height <= maxDimension {
            return image.jpegData(compressionQuality: 0.8)
        }
        let scale = min(maxDimension / size.width, maxDimension / size.height)
        let newSize = CGSize(width: (size.width * scale).rounded(),
                             height: (size.height * scale).rounded())
        guard let thumbnail = image.preparingThumbnail(of: newSize) else {
            return image.jpegData(compressionQuality: 0.8)
        }
        return thumbnail.jpegData(compressionQuality: 0.8)
    }
}

// MARK: - Share Sheet with Cleanup

/// UIActivityViewController wrapper that fires `onComplete` when the sheet dismisses.
private struct RecipeShareSheet: UIViewControllerRepresentable {
    let url: URL
    let onComplete: () -> Void

    func makeUIViewController(context: Context) -> UIActivityViewController {
        // Explicitly register the UTI so AirDrop and Messages tag the file as
        // com.ridepro.biterecipe.bundle. Passing a bare URL lets iOS look up the
        // UTI from the file extension, which is unreliable for custom types and
        // causes AirDrop to tag it as public.data — the receiver's device can't
        // find a handler and saves it to Files instead of opening BiteRecipe.
        let provider = NSItemProvider()
        provider.registerFileRepresentation(
            forTypeIdentifier: "com.ridepro.biterecipe.bundle",
            fileOptions: [],
            visibility: .all
        ) { completion in
            completion(self.url, false, nil)
            return nil
        }
        let ac = UIActivityViewController(activityItems: [provider], applicationActivities: nil)
        ac.completionWithItemsHandler = { _, _, _, _ in
            onComplete()
        }
        return ac
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
