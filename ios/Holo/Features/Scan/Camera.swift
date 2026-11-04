import AVFoundation
import CoreImage
import ImageIO
import SwiftUI
import UIKit
import Vision

/// The back camera, streaming 1080p frames for scanning.
///
/// One output only: a video data output feeds frames (upright, BGRA) to `captureOutput` on its
/// own queue, and everything is taken from those frames. `capture()` returns the next frame as
/// a JPEG (the "photo" for a scan); `snapshotCard()` returns a flattened crop of the card in the
/// next frame (perspective-corrected) so it can be read before you tap. While `setTracking(true)`
/// (the scanner is up and uncovered), about ten times a second Vision looks for one card-shaped
/// rectangle; its four corners (0...1, Vision's space: origin bottom-left, in the upright frame)
/// go to `onCard` on the main queue, where `CardTracker` smooths them and the scanner draws the
/// border. With tracking off the frames are dropped unread.
///
/// There is no photo output on purpose. On recent iOS, taking a still through
/// `AVCapturePhotoOutput` can leave the phone's camera black for every app, Apple's Camera
/// included, until the phone is restarted; a frame from the stream the camera is already
/// producing (the same 1080p the preview shows) asks nothing extra of it.
final class Camera: NSObject, ObservableObject {
    enum State { case starting, running, denied, unavailable }

    /// The camera couldn't hand over a frame (stopped or interrupted while a scan was asked for).
    struct NoFrame: Error {}

    @Published var state: State = .starting
    let session = AVCaptureSession()

    private let queue = DispatchQueue(label: "holo.camera")

    // Frames (see the header). `videoQueue` owns `rectangles` and `lastDetection`; everything
    // shared with other threads sits behind `lock`.
    private let videoOutput = AVCaptureVideoDataOutput()
    private let videoQueue = DispatchQueue(label: "holo.camera.video", qos: .userInitiated)
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
    /// A scan waiting for the next frame as a JPEG, how big it wants it, and which request it is
    /// (so a timeout can't fail a later one).
    private var frameWaiter: (cont: CheckedContinuation<Data, Error>, maxEdge: CGFloat, quality: CGFloat, id: Int)?
    private var frameRequests = 0
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
    private let lock = NSLock()

    /// True only while the scanner is on screen. The camera is never started, or restarted after
    /// an interruption, unless the scanner wants it and Lucent is in front, so Lucent never holds
    /// the camera away from other apps (Apple's Camera included).
    private var wanted = false
    private var appObservers: [NSObjectProtocol] = []
    private var sessionObservers: [NSObjectProtocol] = []

    func start() {
        wanted = true
        watchApp()
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
        wanted = false
        setTracking(false)
        failFrameWaiter()
        // Holds on to `self` so the camera is never stopped twice at once (here and in `deinit`).
        queue.async { [self] in if session.isRunning { session.stopRunning() } }
    }

    deinit {
        (appObservers + sessionObservers).forEach(NotificationCenter.default.removeObserver)
        failFrameWaiter()
        // Everything that touches the session runs on `queue`, this included.
        let session = self.session
        queue.async { if session.isRunning { session.stopRunning() } }
    }

    /// Fails the waiting scan (only request `id`, when given).
    private func failFrameWaiter(id: Int? = nil) {
        lock.lock()
        let waiter = frameWaiter
        if let id, waiter?.id != id {
            lock.unlock()
            return
        }
        frameWaiter = nil
        lock.unlock()
        waiter?.cont.resume(throwing: NoFrame())
    }

    /// Let go of the camera the moment Lucent leaves the front; take it back on return only if
    /// the scanner is still open.
    private func watchApp() {
        guard appObservers.isEmpty else { return }
        let center = NotificationCenter.default
        appObservers.append(center.addObserver(forName: UIApplication.willResignActiveNotification, object: nil, queue: .main) { [weak self] _ in
            guard let self else { return }
            self.queue.async { if self.session.isRunning { self.session.stopRunning() } }
        })
        appObservers.append(center.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            guard let self, self.wanted else { return }
            self.queue.async { if self.wanted, !self.session.isRunning { self.session.startRunning() } }
        })
    }

    /// Read frames for live tracking, or stop (no Vision work at all while off). The frames
    /// keep arriving either way; the camera itself is never reconfigured for this.
    func setTracking(_ on: Bool) {
        lock.lock()
        trackingOn = on
        let waiter = on ? nil : snapshotWaiter
        if !on { snapshotWaiter = nil }
        lock.unlock()
        waiter?.resume(returning: nil)
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
            // Closed again before the camera was ready: don't start it.
            guard self.wanted else { return }
            if !self.session.isRunning { self.session.startRunning() }
            self.set(.running)
        }
    }

    /// After a call, another app taking the camera or a runtime error, start again so the
    /// picture comes back by itself.
    private func observeInterruptions() {
        let center = NotificationCenter.default
        for name in [AVCaptureSession.interruptionEndedNotification, AVCaptureSession.runtimeErrorNotification] {
            sessionObservers.append(center.addObserver(forName: name, object: session, queue: nil) { [weak self] _ in
                guard let self else { return }
                // Only while the scanner is open and Lucent is in front: never fight another app
                // (or the system) for the camera.
                DispatchQueue.main.async {
                    guard self.wanted, UIApplication.shared.applicationState == .active else { return }
                    self.queue.async {
                        guard self.wanted, !self.session.isRunning else { return }
                        self.session.startRunning()
                        self.set(.running)
                    }
                }
            })
        }
    }

    private func configure() -> Bool {
        session.beginConfiguration()
        defer { session.commitConfiguration() }
        // 1080p: plenty for a card (scans are shrunk to 1000–1400px anyway) and a light pipeline.
        session.sessionPreset = session.canSetSessionPreset(.hd1920x1080) ? .hd1920x1080 : .high
        guard
            let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
            let input = try? AVCaptureDeviceInput(device: device),
            session.canAddInput(input)
        else { return false }
        session.addInput(input)
        self.device = device
        // The one output: live frames, for tracking and for the scans themselves.
        videoOutput.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA)]
        videoOutput.alwaysDiscardsLateVideoFrames = true
        guard session.canAddOutput(videoOutput) else { return false }
        session.addOutput(videoOutput)
        // Upright like the preview, so Vision's corners map straight onto it.
        if let connection = videoOutput.connection(with: .video), connection.isVideoRotationAngleSupported(90) {
            connection.videoRotationAngle = 90
        }
        videoOutput.setSampleBufferDelegate(self, queue: videoQueue)
        // Cards are close up: keep focusing continuously.
        if (try? device.lockForConfiguration()) != nil {
            if device.isFocusModeSupported(.continuousAutoFocus) { device.focusMode = .continuousAutoFocus }
            if device.isAutoFocusRangeRestrictionSupported { device.autoFocusRangeRestriction = .near }
            device.unlockForConfiguration()
        }
        return true
    }

    /// The next frame as a JPEG no larger than `maxEdge` pixels on its long side: the "photo"
    /// for a scan. Fails if no frame comes within a second (the camera is stopped or
    /// interrupted), so the shutter never hangs. One at a time.
    func capture(maxEdge: CGFloat = 1400, quality: CGFloat = 0.85) async throws -> Data {
        let data: Data = try await withCheckedThrowingContinuation { cont in
            lock.lock()
            guard frameWaiter == nil else {
                lock.unlock()
                cont.resume(throwing: NoFrame())
                return
            }
            frameRequests += 1
            let id = frameRequests
            frameWaiter = (cont, maxEdge, quality, id)
            lock.unlock()
            // No frame in a second: the camera isn't delivering; give up on this scan.
            queue.asyncAfter(deadline: .now() + 1) { [weak self] in self?.failFrameWaiter(id: id) }
        }
        return data
    }
}

// MARK: - Live tracking

extension Camera: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        lock.lock()
        let on = trackingOn
        let wantsSnapshot = snapshotWaiter != nil
        let wantsFrame = frameWaiter
        frameWaiter = nil
        lock.unlock()
        guard let pixels = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            wantsFrame?.cont.resume(throwing: NoFrame())
            return
        }

        // Rotated by the connection: already upright. Otherwise the sensor's landscape frame.
        let rotated = connection.videoRotationAngle == 90
        let orientation: CGImagePropertyOrientation = rotated ? .up : .right

        // A scan asked for this frame: hand it over as a JPEG, whether or not tracking is on.
        if let wantsFrame {
            let image = CIImage(cvPixelBuffer: pixels).oriented(orientation)
            if let jpeg = Camera.jpeg(image, maxEdge: wantsFrame.maxEdge, quality: wantsFrame.quality) {
                wantsFrame.cont.resume(returning: jpeg)
            } else {
                wantsFrame.cont.resume(throwing: NoFrame())
            }
        }

        guard on else { return }
        // About ten a second; frames that arrive while one is being read are dropped by the
        // output itself (this queue is serial and Vision runs synchronously on it).
        let now = CACurrentMediaTime()
        guard wantsSnapshot || now - lastDetection >= 0.1 else { return }
        lastDetection = now
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

    /// `image` (upright) as a JPEG no larger than `maxEdge` on its long side.
    static func jpeg(_ image: CIImage, maxEdge: CGFloat, quality: CGFloat) -> Data? {
        var out = image
        let long = max(out.extent.width, out.extent.height)
        guard long > 0 else { return nil }
        if long > maxEdge {
            let s = maxEdge / long
            out = out.transformed(by: CGAffineTransform(scaleX: s, y: s))
        }
        let space = out.colorSpace ?? CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        return ciContext.jpegRepresentation(of: out, colorSpace: space, options: [CIImageRepresentationOption(rawValue: kCGImageDestinationLossyCompressionQuality as String): quality])
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
    /// Whether the camera is running. The preview is attached only once it is, so it never
    /// touches the session while that is being set up on the camera's queue, and a preview
    /// attached before the session started (which newer iOS can leave blank) can't happen.
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
        return view
    }

    func updateUIView(_ uiView: PreviewView, context: Context) {
        guard running else { return }
        // Attach once the camera runs, and again only if the link has come loose.
        if uiView.previewLayer.session !== session || uiView.previewLayer.connection == nil {
            if uiView.previewLayer.session != nil { uiView.previewLayer.session = nil }
            uiView.previewLayer.session = session
            uiView.setNeedsLayout()
        }
    }
}
