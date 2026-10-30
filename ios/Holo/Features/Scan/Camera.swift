import AVFoundation
import SwiftUI
import UIKit

/// The back camera, ready to take still photos for scanning.
final class Camera: NSObject, ObservableObject {
    enum State { case starting, running, denied, unavailable }

    @Published var state: State = .starting
    let session = AVCaptureSession()

    private let output = AVCapturePhotoOutput()
    private let queue = DispatchQueue(label: "holo.camera")
    private var configured = false
    private var pending: [Int64: CheckedContinuation<Data, Error>] = [:]
    private let lock = NSLock()

    func start() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            run()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                if granted { self?.run() } else { self?.set(.denied) }
            }
        default:
            set(.denied)
        }
    }

    func stop() {
        queue.async { [session] in if session.isRunning { session.stopRunning() } }
    }

    private func set(_ s: State) {
        DispatchQueue.main.async { self.state = s }
    }

    private func run() {
        queue.async { [weak self] in
            guard let self else { return }
            if !self.configured {
                guard self.configure() else { return self.set(.unavailable) }
                self.configured = true
            }
            if !self.session.isRunning { self.session.startRunning() }
            self.set(.running)
        }
    }

    private func configure() -> Bool {
        session.beginConfiguration()
        defer { session.commitConfiguration() }
        session.sessionPreset = .photo
        guard
            let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
            let input = try? AVCaptureDeviceInput(device: device),
            session.canAddInput(input), session.canAddOutput(output)
        else { return false }
        session.addInput(input)
        session.addOutput(output)
        output.maxPhotoQualityPrioritization = .speed
        // Cards are close up: keep focusing continuously.
        if (try? device.lockForConfiguration()) != nil {
            if device.isFocusModeSupported(.continuousAutoFocus) { device.focusMode = .continuousAutoFocus }
            if device.isAutoFocusRangeRestrictionSupported { device.autoFocusRangeRestriction = .near }
            device.unlockForConfiguration()
        }
        return true
    }

    /// Take a photo and return it as a JPEG no larger than `maxEdge` pixels on its long side.
    func capture(maxEdge: CGFloat = 1400) async throws -> Data {
        let raw: Data = try await withCheckedThrowingContinuation { cont in
            queue.async { [weak self] in
                guard let self else { return }
                let settings = AVCapturePhotoSettings(format: [AVVideoCodecKey: AVVideoCodecType.jpeg])
                settings.photoQualityPrioritization = .speed
                self.lock.lock()
                self.pending[settings.uniqueID] = cont
                self.lock.unlock()
                self.output.capturePhoto(with: settings, delegate: self)
            }
        }
        return Camera.downscale(raw, maxEdge: maxEdge) ?? raw
    }

    static func downscale(_ data: Data, maxEdge: CGFloat) -> Data? {
        guard let image = UIImage(data: data) else { return nil }
        let size = image.size
        let scale = min(1, maxEdge / max(size.width, size.height))
        let target = CGSize(width: (size.width * scale).rounded(), height: (size.height * scale).rounded())
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let resized = UIGraphicsImageRenderer(size: target, format: format).image { _ in image.draw(in: CGRect(origin: .zero, size: target)) }
        return resized.jpegData(compressionQuality: 0.85)
    }
}

extension Camera: AVCapturePhotoCaptureDelegate {
    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        lock.lock()
        let cont = pending.removeValue(forKey: photo.resolvedSettings.uniqueID)
        lock.unlock()
        if let error { cont?.resume(throwing: error) }
        else if let data = photo.fileDataRepresentation() { cont?.resume(returning: data) }
        else { cont?.resume(throwing: CocoaError(.fileReadCorruptFile)) }
    }
}

/// The live camera picture, filling its frame.
struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession

    final class PreviewView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
    }

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.previewLayer.session = session
        view.previewLayer.videoGravity = .resizeAspectFill
        view.backgroundColor = .black
        return view
    }

    func updateUIView(_ uiView: PreviewView, context: Context) {}
}
