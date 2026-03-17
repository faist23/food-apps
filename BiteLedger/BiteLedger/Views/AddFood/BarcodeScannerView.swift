import SwiftUI
import AVFoundation
import Vision
import Observation
import BiteLedgerCore

/// A view that provides barcode scanning functionality using the device camera
struct BarcodeScannerView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var scannerViewModel = BarcodeScannerViewModel()
    
    var onBarcodeDetected: (String) -> Void
    
    var body: some View {
        ZStack {
            // Camera preview
            CameraPreviewView(session: scannerViewModel.captureSession)
                .ignoresSafeArea()
            
            // Scanning overlay
            VStack {
                // Header
                HStack {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.title2)
                            .foregroundStyle(.white)
                            .padding()
                            .background(.ultraThinMaterial, in: Circle())
                    }
                    
                    Spacer()
                }
                .padding()
                
                Spacer()
                
                // Scanning frame
                RoundedRectangle(cornerRadius: 20)
                    .strokeBorder(.white, lineWidth: 3)
                    .frame(width: 280, height: 200)
                    .overlay {
                        if scannerViewModel.isScanning {
                            VStack {
                                ProgressView()
                                    .tint(.white)
                                Text("Scanning...")
                                    .foregroundStyle(.white)
                                    .padding(.top, 8)
                            }
                        }
                    }
                
                Spacer()
                
                // Instructions
                VStack(spacing: 12) {
                    Text("Align barcode within frame")
                        .font(.headline)
                    
                    if let error = scannerViewModel.errorMessage {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.red)
                    } else {
                        Text("Position the barcode clearly in view")
                            .font(.caption)
                    }
                }
                .foregroundStyle(.white)
                .padding()
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
                .padding()
            }
        }
        .onAppear {
            scannerViewModel.startScanning()
        }
        .onDisappear {
            scannerViewModel.stopScanning()
        }
        .onChange(of: scannerViewModel.detectedBarcode) { oldValue, newValue in
            if let barcode = newValue {
                onBarcodeDetected(barcode)
                dismiss()
            }
        }
    }
}

/// ViewModel managing barcode scanning logic
@Observable
class BarcodeScannerViewModel: NSObject {
    var detectedBarcode: String?
    var isScanning = false
    var errorMessage: String?
    
    nonisolated(unsafe) let captureSession = AVCaptureSession()
    private nonisolated(unsafe) let videoOutput = AVCaptureVideoDataOutput()
    private let sessionQueue = DispatchQueue(label: "com.biteledger.barcodescanner")
    
    override init() {
        super.init()
        checkCameraPermission()
    }
    
    /// Check and request camera permission
    private func checkCameraPermission() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            setupCamera()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                if granted {
                    self?.setupCamera()
                } else {
                    Task { @MainActor [weak self] in
                        self?.errorMessage = "Camera access required"
                    }
                }
            }
        case .denied, .restricted:
            errorMessage = "Camera access denied. Enable in Settings."
        @unknown default:
            errorMessage = "Unknown camera authorization status"
        }
    }
    
    /// Configure the camera capture session
    private func setupCamera() {
        sessionQueue.async { [weak self] in
            guard let self = self else { return }
            
            self.captureSession.beginConfiguration()
            
            // Add video input
            guard let videoDevice = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
                  let videoInput = try? AVCaptureDeviceInput(device: videoDevice),
                  self.captureSession.canAddInput(videoInput) else {
                Task { @MainActor [weak self] in
                    self?.errorMessage = "Failed to access camera"
                }
                self.captureSession.commitConfiguration()
                return
            }
            
            self.captureSession.addInput(videoInput)
            
            // Add video output
            self.videoOutput.setSampleBufferDelegate(self, queue: self.sessionQueue)
            self.videoOutput.alwaysDiscardsLateVideoFrames = true
            
            if self.captureSession.canAddOutput(self.videoOutput) {
                self.captureSession.addOutput(self.videoOutput)
            }
            
            self.captureSession.commitConfiguration()
        }
    }
    
    /// Start the camera session
    func startScanning() {
        sessionQueue.async { [weak self] in
            guard let self = self else { return }
            self.captureSession.startRunning()
            Task { @MainActor [weak self] in
                self?.isScanning = true
            }
        }
    }
    
    /// Stop the camera session
    func stopScanning() {
        sessionQueue.async { [weak self] in
            guard let self = self else { return }
            self.captureSession.stopRunning()
            Task { @MainActor [weak self] in
                self?.isScanning = false
            }
        }
    }
}

// MARK: - AVCaptureVideoDataOutputSampleBufferDelegate
extension BarcodeScannerViewModel: AVCaptureVideoDataOutputSampleBufferDelegate {
    nonisolated func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        
        // Create barcode detection request
        let request = VNDetectBarcodesRequest { [weak self] request, error in
            guard let self = self,
                  error == nil,
                  let results = request.results as? [VNBarcodeObservation],
                  let firstBarcode = results.first,
                  let payloadString = firstBarcode.payloadStringValue else {
                return
            }
            
            // Update on main thread
            Task { @MainActor in
                // Only detect once per session
                if self.detectedBarcode == nil {
                    self.detectedBarcode = payloadString
                    self.stopScanning()
                }
            }
        }
        
        // Specify barcode symbologies (common food product types)
        request.symbologies = [
            .ean8,
            .ean13,
            .upce,
            .code39,
            .code128
        ]
        
        // Perform request
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, options: [:])
        try? handler.perform([request])
    }
}

/// UIViewRepresentable wrapper for camera preview
struct CameraPreviewView: UIViewRepresentable {
    let session: AVCaptureSession
    
    func makeUIView(context: Context) -> UIView {
        let view = UIView(frame: .zero)
        view.backgroundColor = .black
        
        let previewLayer = AVCaptureVideoPreviewLayer(session: session)
        previewLayer.videoGravity = .resizeAspectFill
        view.layer.addSublayer(previewLayer)
        
        // Store layer in context for frame updates
        context.coordinator.previewLayer = previewLayer
        
        return view
    }
    
    func updateUIView(_ uiView: UIView, context: Context) {
        // Update preview layer frame when view size changes
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

#Preview {
    BarcodeScannerView { barcode in
        print("Detected barcode: \(barcode)")
    }
}
