//
//  OCRRecipeImportView.swift
//  RecipeCard
//
//  Scans one or more photos of a printed recipe (cookbook, recipe card, handwritten page).
//  Vision OCR runs on every photo; all text is combined and shown in OCRTextReviewView
//  so the user can fix handwriting misreads before Claude structures the recipe.
//

import SwiftUI
import Vision
import PhotosUI
import BiteLedgerCore

// MARK: - Camera picker (UIKit bridge)

private struct CameraPickerView: UIViewControllerRepresentable {
    let onImage: (UIImage) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onImage: onImage) }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    final class Coordinator: NSObject, UINavigationControllerDelegate, UIImagePickerControllerDelegate {
        let onImage: (UIImage) -> Void
        init(onImage: @escaping (UIImage) -> Void) { self.onImage = onImage }

        func imagePickerController(_ picker: UIImagePickerController,
                                   didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            picker.dismiss(animated: true)
            if let img = info[.originalImage] as? UIImage { onImage(img) }
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            picker.dismiss(animated: true)
        }
    }
}

// MARK: - Main View

struct OCRRecipeImportView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    private let service = RecipeImportService.fromPlist()

    // Photos
    @State private var images: [UIImage] = []
    @State private var photoItems: [PhotosPickerItem] = []
    @State private var showingCamera = false

    // Processing
    @State private var status: Status = .idle
    @State private var rawLines: [String]?
    @State private var showingTextReview = false

    private enum Status: Equatable {
        case idle
        case scanning
        case failed(String)
    }

    private var canScan: Bool { !images.isEmpty && status == .idle }

    var body: some View {
        NavigationStack {
            Form {
                // MARK: Photos
                Section {
                    // Thumbnail strip
                    if !images.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 10) {
                                ForEach(images.indices, id: \.self) { i in
                                    ZStack(alignment: .topTrailing) {
                                        Image(uiImage: images[i])
                                            .resizable()
                                            .scaledToFill()
                                            .frame(width: 100, height: 130)
                                            .clipShape(RoundedRectangle(cornerRadius: 8))

                                        Button {
                                            images.remove(at: i)
                                        } label: {
                                            Image(systemName: "xmark.circle.fill")
                                                .font(.title3)
                                                .foregroundStyle(.white, .black.opacity(0.7))
                                                .padding(4)
                                        }
                                    }
                                }
                            }
                            .padding(.vertical, 4)
                        }
                        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                    }

                    // Add buttons
                    HStack(spacing: 16) {
                        Button {
                            showingCamera = true
                        } label: {
                            Label("Camera", systemImage: "camera")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .disabled(status != .idle)

                        PhotosPicker(selection: $photoItems,
                                     maxSelectionCount: 20,
                                     matching: .images) {
                            Label("Library", systemImage: "photo.on.rectangle")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .disabled(status != .idle)
                    }
                } header: {
                    Text(images.isEmpty
                         ? "Add Photos"
                         : "Photos (\(images.count))")
                } footer: {
                    Text("Add the front and back of a recipe card, or as many pages as needed.")
                }

                // MARK: Scan button
                Section {
                    Button {
                        Task { await scan() }
                    } label: {
                        HStack {
                            Spacer()
                            if status == .scanning {
                                ProgressView().padding(.trailing, 8)
                                Text("Reading text…")
                            } else {
                                Text(images.count > 1
                                     ? "Scan \(images.count) Photos"
                                     : "Scan Photo")
                                    .bold()
                            }
                            Spacer()
                        }
                    }
                    .disabled(!canScan)
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
            .navigationTitle("Scan Recipe")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .fullScreenCover(isPresented: $showingCamera) {
                CameraPickerView { image in
                    images.append(image)
                }
                .ignoresSafeArea()
            }
            .onChange(of: photoItems) { _, newItems in
                guard !newItems.isEmpty else { return }
                Task {
                    for item in newItems {
                        if let data = try? await item.loadTransferable(type: Data.self),
                           let image = UIImage(data: data) {
                            images.append(image)
                        }
                    }
                    photoItems = []  // reset so picker can be opened again
                }
            }
            .navigationDestination(isPresented: $showingTextReview) {
                if let lines = rawLines {
                    OCRTextReviewView(
                        rawLines: lines,
                        scannedImage: images.first,
                        onSave: { dismiss() }
                    )
                }
            }
        }
    }

    // MARK: - OCR Pipeline

    @MainActor
    private func scan() async {
        status = .scanning

        var allLines: [String] = []
        for image in images {
            if let lines = await recognizeText(in: image) {
                allLines.append(contentsOf: lines)
            }
        }

        guard !allLines.isEmpty else {
            status = .failed("No text found in the photos. Try clearer images with good lighting.")
            return
        }

        print("📷 OCR extracted \(allLines.count) lines from \(images.count) photo(s)")
        // Normalise before showing to user: strip "(N)" quantity parens, expand T→tbsp, fix misreads
        rawLines = service.preprocessOCRLines(allLines)
        status = .idle
        showingTextReview = true
    }

    private func recognizeText(in image: UIImage) async -> [String]? {
        await withCheckedContinuation { continuation in
            guard let cgImage = image.cgImage else {
                continuation.resume(returning: nil)
                return
            }

            let request = VNRecognizeTextRequest { req, error in
                guard error == nil,
                      let observations = req.results as? [VNRecognizedTextObservation]
                else {
                    continuation.resume(returning: nil)
                    return
                }
                // Vision coordinates: Y=0 is BOTTOM of image, Y=1 is TOP.
                // Top-to-bottom reading order = descending Vision Y (high Y first).
                let sorted = observations.sorted {
                    let dy = $1.boundingBox.minY - $0.boundingBox.minY
                    if abs(dy) > 0.01 { return dy < 0 }   // $0 before $1 when $0.minY > $1.minY
                    return $0.boundingBox.minX < $1.boundingBox.minX
                }
                let lines = sorted.compactMap { $0.topCandidates(1).first?.string }
                continuation.resume(returning: lines)
            }
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            request.recognitionLanguages = ["en-US"]

            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            try? handler.perform([request])
        }
    }
}
