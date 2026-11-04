import AVFoundation
import CoreImage
import SwiftUI
import UIKit
import Vision

/// The back camera, ready to take still photos for scanning.
///
/// Live card tracking: besides the photo output, a video data output feeds frames (upright,
/// BGRA) to `captureOutput` on its own queue. About ten times a second Vision looks for one
/// card-shaped rectangle; its four corners (0...1, Vision's space: origin bottom-left, in the
/// upright frame) go to `onCard` on the main queue, where `CardTracker` smooths them and the
/// scanner draws the border. `snapshotCard()` asks the next frame for a flattened crop of the
/// card (perspective-corrected) so it can be read before you tap. Frames are only processed
/// while `setTracking(true)`: the scanner turns it off when it's covered or closed.
final class Camera: NSObject, ObservableObject {
    enum State { case starting, running, denied, unavailable }

    @Published var state: State = .starting
    let session = AVCaptureSession()

    private let output = AVCapturePhotoOutput()
    private let queue = DispatchQueue(label: "holo.camera")

    // Live tracking (see the header). `videoQueue` owns `rectangles` and `lastDetection`;
    // everything shared with other threads sits behind `lock`.
    private let videoOutput = AVCaptureVideoDataOutput()
    private let videoQueue = DispatchQueue(label: "holo.camera.video", qos: .userInitiated)
    private var hasVideoOutput = false
    private var lastDetection: CFTimeInterval = 0
    private lazy var rectangles: VNDetectRectanglesRequest = {
        let r = VNDetectRectanglesRequest()
        // A trading card is 63 x 88 mm (0.716); allow for tilt and perspective.
        r.minimumAspectRatio = 0.55
        r.maximumAspectRatio = 0.9
        r.minimumSize = 0.2
        r.quadratureTolerance = 20
        r.maximumObservations = 1
        r.minimumConfidence = 0.6
        return r
    }()
    private var trackingOn = false
    private var cardHandler: ((CardQuad?, CGSize) -> Void)?
    private var snapshotWaiter: CheckedContinuation<CardCrop?, Never>?
    private static let ciContext = CIContext()

    /// Called on the main queue for each processed frame: the card's corners (nil when none
    /// was found) and the upright frame's size in pixels.
    var onCard: ((CardQuad?, CGSize) -> Void)? {
        get { lock.lock(); defer { lock.unlock() }; return cardHandler }
        set { lock.lock(); cardHandler = newValue; lock.unlock() }
    }
    private var configured = false
    private var device: AVCaptureDevice?
    /// Whether this camera has a light to turn on.
    var hasTorch: Bool { device?.hasTorch ?? false }

    /// The light on or off (for dim card shows).
    func setTorch(_ on: Bool) {
        queue.async { [weak self] in
            guard let device = self?.device, device.hasTorch, (try? device.lockForConfiguration()) != nil else { return }
            device.torchMode = on ? .on : .off
            device.unlockForConfiguration()
        }
    }
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
        setTracking(false)
        queue.async { [session] in if session.isRunning { session.stopRunning() } }
    }

    /// Process frames for live tracking, or stop (no Vision work at all while off).
    func setTracking(_ on: Bool) {
        lock.lock()
        let changed = trackingOn != on
        trackingOn = on
        let waiter = on ? nil : snapshotWaiter
        if !on { snapshotWaiter = nil }
        lock.unlock()
        waiter?.resume(returning: nil)
        guard changed else { return }
        queue.async { [weak self] in
            guard let self, self.hasVideoOutput else { return }
            self.videoOutput.setSampleBufferDelegate(on ? self : nil, queue: on ? self.videoQueue : nil)
        }
    }

    /// A flattened, upright crop of the card in the next frame, or nil when no card is found
    /// there (or tracking is off). One at a time: a second call while one waits gets nil.
    func snapshotCard() async -> CardCrop? {
        await withCheckedContinuation { (cont: CheckedContinuation<CardCrop?, Never>) in
            lock.lock()
            guard trackingOn, snapshotWaiter == nil else {
                lock.unlock()
                cont.resume(returning: nil)
                return
            }
            snapshotWaiter = cont
            lock.unlock()
        }
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
                self.observeInterruptions()
            }
            if !self.session.isRunning { self.session.startRunning() }
            self.set(.running)
        }
    }

    /// After a call, another app taking the camera or a runtime error, start again so the
    /// picture comes back by itself.
    private func observeInterruptions() {
        let center = NotificationCenter.default
        for name in [AVCaptureSession.interruptionEndedNotification, AVCaptureSession.runtimeErrorNotification] {
            center.addObserver(forName: name, object: session, queue: nil) { [weak self] _ in
                guard let self else { return }
                self.queue.async {
                    if !self.session.isRunning { self.session.startRunning() }
                    self.set(.running)
                }
            }
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
        self.device = device
        output.maxPhotoQualityPrioritization = .speed
        // Live tracking frames: optional, the scanner works without them.
        videoOutput.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA)]
        videoOutput.alwaysDiscardsLateVideoFrames = true
        if session.canAddOutput(videoOutput) {
            session.addOutput(videoOutput)
            hasVideoOutput = true
            // Upright like the preview, so Vision's corners map straight onto it.
            if let connection = videoOutput.connection(with: .video), connection.isVideoRotationAngleSupported(90) {
                connection.videoRotationAngle = 90
            }
            lock.lock()
            let on = trackingOn
            lock.unlock()
            if on { videoOutput.setSampleBufferDelegate(self, queue: videoQueue) }
        }
        // Cards are close up: keep focusing continuously.
        if (try? device.lockForConfiguration()) != nil {
            if device.isFocusModeSupported(.continuousAutoFocus) { device.focusMode = .continuousAutoFocus }
            if device.isAutoFocusRangeRestrictionSupported { device.autoFocusRangeRestriction = .near }
            device.unlockForConfiguration()
        }
        return true
    }

    /// Take a photo and return it as a JPEG no larger than `maxEdge` pixels on its long side.
    func capture(maxEdge: CGFloat = 1400, quality: CGFloat = 0.85) async throws -> Data {
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
        return Camera.downscale(raw, maxEdge: maxEdge, quality: quality) ?? raw
    }

    static func downscale(_ data: Data, maxEdge: CGFloat, quality: CGFloat = 0.85) -> Data? {
        guard let image = UIImage(data: data) else { return nil }
        let size = image.size
        let scale = min(1, maxEdge / max(size.width, size.height))
        let target = CGSize(width: (size.width * scale).rounded(), height: (size.height * scale).rounded())
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let resized = UIGraphicsImageRenderer(size: target, format: format).image { _ in image.draw(in: CGRect(origin: .zero, size: target)) }
        return resized.jpegData(compressionQuality: quality)
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

// MARK: - Live tracking

extension Camera: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        lock.lock()
        let on = trackingOn
        let wantsSnapshot = snapshotWaiter != nil
        lock.unlock()
        guard on else { return }
        // About ten a second; frames that arrive while one is being read are dropped by the
        // output itself (this queue is serial and Vision runs synchronously on it).
        let now = CACurrentMediaTime()
        guard wantsSnapshot || now - lastDetection >= 0.1 else { return }
        lastDetection = now
        guard let pixels = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

        // Rotated by the connection: already upright. Otherwise the sensor's landscape frame.
        let rotated = connection.videoRotationAngle == 90
        let orientation: CGImagePropertyOrientation = rotated ? .up : .right
        let w = CGFloat(CVPixelBufferGetWidth(pixels)), h = CGFloat(CVPixelBufferGetHeight(pixels))
        let size = rotated ? CGSize(width: w, height: h) : CGSize(width: h, height: w)

        let handler = VNImageRequestHandler(cvPixelBuffer: pixels, orientation: orientation, options: [:])
        var quad: CardQuad?
        if (try? handler.perform([rectangles])) != nil, let r = rectangles.results?.first {
            quad = CardQuad(topLeft: r.topLeft, topRight: r.topRight, bottomRight: r.bottomRight, bottomLeft: r.bottomLeft)
        }

        if wantsSnapshot {
            lock.lock()
            let waiter = snapshotWaiter
            snapshotWaiter = nil
            lock.unlock()
            var crop: CardCrop?
            if let quad {
                crop = Camera.flatten(CIImage(cvPixelBuffer: pixels).oriented(orientation), quad: quad, maxEdge: 1200)
            }
            waiter?.resume(returning: crop)
        }

        let deliver = onCard
        DispatchQueue.main.async { deliver?(quad, size) }
    }

    /// The card in `photo` (a JPEG from `capture`) flattened to its four corners, or nil.
    static func crop(photo: Data, to quad: CardQuad, maxEdge: CGFloat = 1400) -> CardCrop? {
        guard let image = CIImage(data: photo, options: [.applyOrientationProperty: true]) else { return nil }
        return flatten(image, quad: quad, maxEdge: maxEdge)
    }

    /// Perspective-corrects the quad (0...1, origin bottom-left like Core Image) out of `image`,
    /// a little wider than the detected edge so the border isn't clipped.
    static func flatten(_ image: CIImage, quad: CardQuad, maxEdge: CGFloat) -> CardCrop? {
        let e = image.extent
        guard e.width > 0, e.height > 0, let filter = CIFilter(name: "CIPerspectiveCorrection") else { return nil }
        let q = quad.expanded(by: 0.03)
        func vector(_ p: CGPoint) -> CIVector { CIVector(x: e.minX + p.x * e.width, y: e.minY + p.y * e.height) }
        filter.setValue(image, forKey: kCIInputImageKey)
        filter.setValue(vector(q.topLeft), forKey: "inputTopLeft")
        filter.setValue(vector(q.topRight), forKey: "inputTopRight")
        filter.setValue(vector(q.bottomRight), forKey: "inputBottomRight")
        filter.setValue(vector(q.bottomLeft), forKey: "inputBottomLeft")
        guard var flat = filter.outputImage, flat.extent.width >= 1, flat.extent.height >= 1 else { return nil }
        let long = max(flat.extent.width, flat.extent.height)
        if long > maxEdge {
            let s = maxEdge / long
            flat = flat.transformed(by: CGAffineTransform(scaleX: s, y: s))
        }
        guard let cg = ciContext.createCGImage(flat, from: flat.extent.integral) else { return nil }
        let ui = UIImage(cgImage: cg)
        guard let jpeg = ui.jpegData(compressionQuality: 0.85) else { return nil }
        return CardCrop(jpeg: jpeg, image: ui)
    }
}

/// A flattened picture of one card: the JPEG to read or scan, and the image for the strip.
struct CardCrop: @unchecked Sendable {
    var jpeg: Data
    var image: UIImage
}

/// The live camera picture, filling its frame.
struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession
    /// Whether the camera is running; when it starts, the preview reconnects to it (newer iOS
    /// can leave a preview attached before the session started showing nothing).
    var running = true

    final class PreviewView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }

        override func layoutSubviews() {
            super.layoutSubviews()
            previewLayer.frame = bounds
            // Upright, whatever the phone reports (the screen is portrait only).
            if let connection = previewLayer.connection, connection.isVideoRotationAngleSupported(90) {
                connection.videoRotationAngle = 90
            }
        }
    }

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.previewLayer.videoGravity = .resizeAspectFill
        view.backgroundColor = .black
        view.previewLayer.session = session
        return view
    }

    final class Coordinator { var attachedWhileRunning = false }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func updateUIView(_ uiView: PreviewView, context: Context) {
        guard running else {
            context.coordinator.attachedWhileRunning = false
            return
        }
        // Reattach once each time the session starts running, so the picture appears.
        if !context.coordinator.attachedWhileRunning || uiView.previewLayer.connection == nil {
            context.coordinator.attachedWhileRunning = true
            uiView.previewLayer.session = nil
            uiView.previewLayer.session = session
            uiView.setNeedsLayout()
        }
    }
}
