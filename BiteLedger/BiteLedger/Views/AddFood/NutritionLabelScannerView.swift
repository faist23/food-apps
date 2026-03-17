import SwiftUI
import AVFoundation
@preconcurrency import Vision
import Combine
import BiteLedgerCore

/// Camera view that scans nutrition labels and extracts data
struct NutritionLabelScannerView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel = ScannerViewModel()
    
    let onScan: (NutritionData) -> Void
    
    var body: some View {
        ZStack {
            // Camera preview
            CameraPreview(session: viewModel.captureSession)
                .ignoresSafeArea()
            
            // Overlay with guidance
            VStack {
                // Top bar
                HStack {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.title2)
                            .foregroundStyle(.white)
                            .padding()
                            .background(.black.opacity(0.5))
                            .clipShape(Circle())
                    }
                    
                    Spacer()
                    
                    // Flash toggle
                    Button {
                        viewModel.toggleFlash()
                    } label: {
                        Image(systemName: viewModel.isFlashOn ? "bolt.fill" : "bolt.slash.fill")
                            .font(.title2)
                            .foregroundStyle(.white)
                            .padding()
                            .background(.black.opacity(0.5))
                            .clipShape(Circle())
                    }
                }
                .padding()
                
                Spacer()
                
                // Center guidance frame
                VStack(spacing: 16) {
                    Text("Position Nutrition Facts label in frame")
                        .font(.headline)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 10)
                        .background(.black.opacity(0.7))
                        .cornerRadius(10)
                    
                    // Scanning frame overlay
                    RoundedRectangle(cornerRadius: 20)
                        .stroke(viewModel.isScanning ? Color.green : Color.white, lineWidth: 3)
                        .frame(width: 300, height: 400)
                        .overlay {
                            if viewModel.isScanning {
                                ProgressView()
                                    .scaleEffect(1.5)
                                    .tint(.white)
                            }
                        }
                }
                
                Spacer()
                
                // Bottom controls
                VStack(spacing: 16) {
                    if let error = viewModel.errorMessage {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.red)
                            .padding(.horizontal, 20)
                            .padding(.vertical, 10)
                            .background(.black.opacity(0.7))
                            .cornerRadius(10)
                    }
                    
                    if let nutritionData = viewModel.scannedData {
                        VStack(spacing: 8) {
                            Text("✓ Label Detected")
                                .font(.headline)
                                .foregroundStyle(.green)
                            
                            Text("Calories: \(nutritionData.calories ?? 0, specifier: "%.0f")")
                                .font(.caption)
                                .foregroundStyle(.white)
                            
                            Button {
                                onScan(nutritionData)
                                dismiss()
                            } label: {
                                Text("Use This Data")
                                    .font(.headline)
                                    .foregroundStyle(.white)
                                    .frame(maxWidth: .infinity)
                                    .padding()
                                    .background(Color.green)
                                    .cornerRadius(12)
                            }
                        }
                        .padding()
                        .background(.black.opacity(0.7))
                        .cornerRadius(16)
                        .padding()
                    } else {
                        Button {
                            viewModel.capturePhoto()
                        } label: {
                            Text(viewModel.isScanning ? "Scanning..." : "Capture Photo")
                                .font(.headline)
                                .foregroundStyle(.white)
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(viewModel.isScanning ? Color.gray : Color.orange)
                                .cornerRadius(12)
                        }
                        .disabled(viewModel.isScanning)
                        .padding()
                    }
                }
            }
        }
        .onAppear {
            viewModel.startSession()
        }
        .onDisappear {
            viewModel.stopSession()
        }
    }
}

// MARK: - Camera Preview

struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession
    
    func makeUIView(context: Context) -> UIView {
        let view = UIView(frame: .zero)
        
        let previewLayer = AVCaptureVideoPreviewLayer(session: session)
        previewLayer.videoGravity = .resizeAspectFill
        view.layer.addSublayer(previewLayer)
        
        context.coordinator.previewLayer = previewLayer
        
        return view
    }
    
    func updateUIView(_ uiView: UIView, context: Context) {
        if let previewLayer = context.coordinator.previewLayer {
            DispatchQueue.main.async {
                previewLayer.frame = uiView.bounds
            }
        }
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator()
    }
    
    class Coordinator {
        var previewLayer: AVCaptureVideoPreviewLayer?
    }
}

// MARK: - Scanner ViewModel

@MainActor
class ScannerViewModel: NSObject, ObservableObject {
    @Published var isScanning = false
    @Published var scannedData: NutritionData?
    @Published var errorMessage: String?
    @Published var isFlashOn = false
    
    let captureSession = AVCaptureSession()
    private var videoOutput: AVCaptureVideoDataOutput?
    private var photoOutput: AVCapturePhotoOutput?
    
    override init() {
        super.init()
        setupCamera()
    }
    
    private func setupCamera() {
        captureSession.sessionPreset = .high
        
        guard let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) else {
            errorMessage = "Camera not available"
            return
        }
        
        do {
            let input = try AVCaptureDeviceInput(device: camera)
            
            if captureSession.canAddInput(input) {
                captureSession.addInput(input)
            }
            
            // Photo output for capture
            let photoOutput = AVCapturePhotoOutput()
            if captureSession.canAddOutput(photoOutput) {
                captureSession.addOutput(photoOutput)
                self.photoOutput = photoOutput
            }
            
        } catch {
            errorMessage = "Failed to setup camera: \(error.localizedDescription)"
        }
    }
    
    func startSession() {
        Task.detached { [weak self] in
            await self?.captureSession.startRunning()
        }
    }
    
    func stopSession() {
        Task.detached { [weak self] in
            await self?.captureSession.stopRunning()
        }
    }
    
    func toggleFlash() {
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
              device.hasTorch else { return }
        
        do {
            try device.lockForConfiguration()
            if isFlashOn {
                device.torchMode = .off
                isFlashOn = false
            } else {
                device.torchMode = .on
                isFlashOn = true
            }
            device.unlockForConfiguration()
        } catch {
            print("Failed to toggle flash: \(error)")
        }
    }
    
    func capturePhoto() {
        guard let photoOutput = photoOutput else { return }
        
        isScanning = true
        errorMessage = nil
        
        let settings = AVCapturePhotoSettings()
        photoOutput.capturePhoto(with: settings, delegate: self)
    }
}

// MARK: - Photo Capture Delegate

extension ScannerViewModel: AVCapturePhotoCaptureDelegate {
    nonisolated func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        guard let imageData = photo.fileDataRepresentation(),
              let image = UIImage(data: imageData) else {
            Task { @MainActor in
                self.errorMessage = "Failed to capture photo"
                self.isScanning = false
            }
            return
        }
        
        // Process the image with Vision
        Task {
            await processImage(image)
        }
    }
    
    private func processImage(_ image: UIImage) async {
        guard let cgImage = image.cgImage else {
            Task { @MainActor in
                self.errorMessage = "Failed to process image"
                self.isScanning = false
            }
            return
        }
        
        let request = VNRecognizeTextRequest { [weak self] request, error in
            guard let self = self else { return }
            
            if let error = error {
                Task { @MainActor in
                    self.errorMessage = "Text recognition failed: \(error.localizedDescription)"
                    self.isScanning = false
                }
                return
            }
            
            guard let observations = request.results as? [VNRecognizedTextObservation] else {
                Task { @MainActor in
                    self.errorMessage = "No text found"
                    self.isScanning = false
                }
                return
            }
            
            // Extract text from observations
            let recognizedText = observations.compactMap { observation in
                observation.topCandidates(1).first?.string
            }
            
            print("📸 OCR recognized \(recognizedText.count) lines of text")
            for (index, line) in recognizedText.prefix(20).enumerated() {
                print("  Line \(index): \"\(line)\"")
            }
            
            // Parse nutrition data
            if let nutritionData = NutritionLabelParser.parse(recognizedText) {
                Task { @MainActor in
                    self.scannedData = nutritionData
                    self.isScanning = false
                    self.errorMessage = nil
                }
            } else {
                Task { @MainActor in
                    self.errorMessage = "Could not find nutrition information. Try again with better lighting."
                    self.isScanning = false
                }
            }
        }
        
        // Configure for accurate text recognition
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        
        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        
        do {
            try handler.perform([request])
        } catch {
            await MainActor.run {
                self.errorMessage = "Failed to analyze image: \(error.localizedDescription)"
                self.isScanning = false
            }
        }
    }
}
