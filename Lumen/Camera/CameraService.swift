import AVFoundation
import CoreImage

/// What the active camera can do; drives the UI's limits.
struct CameraCapabilities: Equatable, Sendable {
    var position: AVCaptureDevice.Position = .back
    var minZoom: CGFloat = 1
    var maxZoom: CGFloat = 1
    /// Zoom factor that matches the main wide lens ("1×"). Above 1 when an
    /// ultra-wide lens is part of a virtual device, so 0.5× is available.
    var baseZoom: CGFloat = 1
    var minBias: Float = 0
    var maxBias: Float = 0
    var hasFlash = false
}

enum CameraError: LocalizedError {
    case notAuthorized
    case noDevice
    case configurationFailed
    case captureFailed

    var errorDescription: String? {
        switch self {
        case .notAuthorized: "Camera access is turned off."
        case .noDevice: "No camera is available on this device."
        case .configurationFailed: "The camera couldn't be set up."
        case .captureFailed: "The photo couldn't be captured."
        }
    }
}

/// Owns the AVCaptureSession. All session work happens on `sessionQueue`;
/// frames are delivered on `videoQueue`.
final class CameraService: NSObject, @unchecked Sendable {

    private let session = AVCaptureSession()
    private let sessionQueue = DispatchQueue(label: "com.irenapoghosian.lumen.session")
    private let videoQueue = DispatchQueue(label: "com.irenapoghosian.lumen.video", qos: .userInitiated)
    private let videoOutput = AVCaptureVideoDataOutput()
    private let photoOutput = AVCapturePhotoOutput()
    private var deviceInput: AVCaptureDeviceInput?
    private var isConfigured = false
    private var captureProcessors: [Int64: PhotoCaptureProcessor] = [:]
    private var subjectAreaObserver: NSObjectProtocol?
    private var runtimeErrorObserver: NSObjectProtocol?

    /// Shared with the photo pipeline so every capture matches the preview.
    private let photoContext = CIContext(options: [.cacheIntermediates: false])

    private let engineLock = NSLock()
    private var _engine = FilterEngine()
    var engine: FilterEngine {
        get { engineLock.withLock { _engine } }
        set { engineLock.withLock { _engine = newValue } }
    }

    /// Called on a background queue with each filtered, upright preview frame.
    var onFrame: (@Sendable (CIImage) -> Void)?

    // MARK: - Permission

    static func requestAccess() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: return true
        case .notDetermined: return await AVCaptureDevice.requestAccess(for: .video)
        default: return false
        }
    }

    // MARK: - Lifecycle

    func start() async throws -> CameraCapabilities {
        try await onSessionQueue { [self] in
            if !isConfigured {
                try configureSession(position: .back)
                observeRuntimeErrors()
                isConfigured = true
            }
            if !session.isRunning { session.startRunning() }
            return try capabilities()
        }
    }

    func stop() {
        sessionQueue.async { [self] in
            if session.isRunning { session.stopRunning() }
        }
    }

    func switchCamera() async throws -> CameraCapabilities {
        try await onSessionQueue { [self] in
            let next: AVCaptureDevice.Position = deviceInput?.device.position == .front ? .back : .front
            try configureSession(position: next)
            return try capabilities()
        }
    }

    // MARK: - Controls

    func setZoom(_ factor: CGFloat) {
        sessionQueue.async { [self] in
            guard let device = deviceInput?.device else { return }
            let value = CameraMath.clampedZoom(
                factor,
                min: device.minAvailableVideoZoomFactor,
                max: maxUsableZoom(for: device)
            )
            try? withLockedDevice(device) { $0.videoZoomFactor = value }
        }
    }

    /// `point` is in AVFoundation point-of-interest space (see `CameraMath`).
    func focus(at point: CGPoint) {
        sessionQueue.async { [self] in
            guard let device = deviceInput?.device else { return }
            try? withLockedDevice(device) { d in
                if d.isFocusPointOfInterestSupported, d.isFocusModeSupported(.autoFocus) {
                    d.focusPointOfInterest = point
                    d.focusMode = .autoFocus
                }
                if d.isExposurePointOfInterestSupported, d.isExposureModeSupported(.autoExpose) {
                    d.exposurePointOfInterest = point
                    d.exposureMode = .autoExpose
                }
                d.setExposureTargetBias(0, completionHandler: nil)
                d.isSubjectAreaChangeMonitoringEnabled = true
            }
        }
    }

    func setExposureBias(_ bias: Float) {
        sessionQueue.async { [self] in
            guard let device = deviceInput?.device else { return }
            let value = CameraMath.clampedBias(
                bias,
                min: device.minExposureTargetBias,
                max: device.maxExposureTargetBias
            )
            try? withLockedDevice(device) { $0.setExposureTargetBias(value, completionHandler: nil) }
        }
    }

    // MARK: - Capture

    /// Captures a photo, applies the current filter at full resolution and
    /// returns encoded HEIC (or JPEG) data. `willCapture` fires at the shutter moment.
    func capturePhoto(
        flash: AVCaptureDevice.FlashMode,
        willCapture: @escaping @Sendable () -> Void
    ) async throws -> Data {
        let engine = self.engine
        return try await withCheckedThrowingContinuation { continuation in
            sessionQueue.async { [self] in
                guard session.isRunning else {
                    continuation.resume(throwing: CameraError.captureFailed)
                    return
                }

                let settings: AVCapturePhotoSettings
                if photoOutput.availablePhotoCodecTypes.contains(.hevc) {
                    settings = AVCapturePhotoSettings(format: [AVVideoCodecKey: AVVideoCodecType.hevc])
                } else {
                    settings = AVCapturePhotoSettings()
                }
                if photoOutput.supportedFlashModes.contains(flash) {
                    settings.flashMode = flash
                }
                settings.photoQualityPrioritization = .balanced

                if let connection = photoOutput.connection(with: .video) {
                    if connection.isVideoRotationAngleSupported(90) { connection.videoRotationAngle = 90 }
                    if connection.isVideoMirroringSupported {
                        connection.automaticallyAdjustsVideoMirroring = false
                        connection.isVideoMirrored = deviceInput?.device.position == .front
                    }
                }

                let id = settings.uniqueID
                let processor = PhotoCaptureProcessor(
                    engine: engine,
                    context: photoContext,
                    willCapture: willCapture
                ) { [weak self] result in
                    self?.sessionQueue.async { self?.captureProcessors[id] = nil }
                    continuation.resume(with: result)
                }
                captureProcessors[id] = processor
                photoOutput.capturePhoto(with: settings, delegate: processor)
            }
        }
    }

    // MARK: - Session configuration (sessionQueue only)

    private func configureSession(position: AVCaptureDevice.Position) throws {
        guard let device = Self.bestDevice(for: position) else { throw CameraError.noDevice }
        let input = try AVCaptureDeviceInput(device: device)

        session.beginConfiguration()
        defer { session.commitConfiguration() }

        session.sessionPreset = .photo

        if let current = deviceInput { session.removeInput(current) }
        guard session.canAddInput(input) else {
            if let current = deviceInput { session.addInput(current) }
            throw CameraError.configurationFailed
        }
        session.addInput(input)
        deviceInput = input
        observeSubjectAreaChanges(of: device)

        if !session.outputs.contains(videoOutput) {
            videoOutput.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
            videoOutput.alwaysDiscardsLateVideoFrames = true
            videoOutput.setSampleBufferDelegate(self, queue: videoQueue)
            guard session.canAddOutput(videoOutput) else { throw CameraError.configurationFailed }
            session.addOutput(videoOutput)
        }

        if !session.outputs.contains(photoOutput) {
            guard session.canAddOutput(photoOutput) else { throw CameraError.configurationFailed }
            session.addOutput(photoOutput)
            photoOutput.maxPhotoQualityPrioritization = .balanced
        }

        // Deliver preview frames upright and mirrored like a selfie on the front camera.
        if let connection = videoOutput.connection(with: .video) {
            if connection.isVideoRotationAngleSupported(90) { connection.videoRotationAngle = 90 }
            if connection.isVideoMirroringSupported {
                connection.automaticallyAdjustsVideoMirroring = false
                connection.isVideoMirrored = position == .front
            }
        }

        // Use the full-resolution sensor size for stills.
        if let dimensions = device.activeFormat.supportedMaxPhotoDimensions.last {
            photoOutput.maxPhotoDimensions = dimensions
        }

        try withLockedDevice(device) { d in
            if d.isFocusModeSupported(.continuousAutoFocus) { d.focusMode = .continuousAutoFocus }
            if d.isExposureModeSupported(.continuousAutoExposure) { d.exposureMode = .continuousAutoExposure }
            if d.isSmoothAutoFocusSupported { d.isSmoothAutoFocusEnabled = true }
        }
    }
    
    /// Media services can be reset by the system (e.g. another app grabbing the
    /// camera hardware); restart the session instead of leaving a black preview.
    
    private func observeRuntimeErrors() {
        runtimeErrorObserver = NotificationCenter.default.addObserver(
            forName: AVCaptureSession.runtimeErrorNotification,
            object: session,
            queue: nil
        ) { [weak self] _ in
            self?.sessionQueue.async {
                guard let self, !self.session.isRunning else { return }
                self.session.startRunning()
            }
        }
    }

    /// After a tap-to-focus, return to continuous autofocus once the scene changes.
    private func observeSubjectAreaChanges(of device: AVCaptureDevice) {
        if let subjectAreaObserver { NotificationCenter.default.removeObserver(subjectAreaObserver) }
        subjectAreaObserver = NotificationCenter.default.addObserver(
            forName: AVCaptureDevice.subjectAreaDidChangeNotification,
            object: device,
            queue: nil
        ) { [weak self] _ in
            self?.sessionQueue.async { self?.resetToContinuousFocus() }
        }
    }

    private func resetToContinuousFocus() {
        guard let device = deviceInput?.device else { return }
        let center = CGPoint(x: 0.5, y: 0.5)
        try? withLockedDevice(device) { d in
            if d.isFocusPointOfInterestSupported { d.focusPointOfInterest = center }
            if d.isFocusModeSupported(.continuousAutoFocus) { d.focusMode = .continuousAutoFocus }
            if d.isExposurePointOfInterestSupported { d.exposurePointOfInterest = center }
            if d.isExposureModeSupported(.continuousAutoExposure) { d.exposureMode = .continuousAutoExposure }
            d.isSubjectAreaChangeMonitoringEnabled = false
        }
    }

    private func capabilities() throws -> CameraCapabilities {
        guard let device = deviceInput?.device else { throw CameraError.noDevice }
        return CameraCapabilities(
            position: device.position,
            minZoom: device.minAvailableVideoZoomFactor,
            maxZoom: maxUsableZoom(for: device),
            baseZoom: Self.wideLensZoom(for: device),
            minBias: device.minExposureTargetBias,
            maxBias: device.maxExposureTargetBias,
            hasFlash: device.hasFlash
        )
    }

    /// Digital zoom past ~10× just looks bad, so cap it.
    private func maxUsableZoom(for device: AVCaptureDevice) -> CGFloat {
        min(device.maxAvailableVideoZoomFactor, 10 * Self.wideLensZoom(for: device))
    }

    private static func wideLensZoom(for device: AVCaptureDevice) -> CGFloat {
        let hasUltraWide = device.constituentDevices.contains { $0.deviceType == .builtInUltraWideCamera }
        guard hasUltraWide, let first = device.virtualDeviceSwitchOverVideoZoomFactors.first else { return 1 }
        return CGFloat(first.doubleValue)
    }

    private static func bestDevice(for position: AVCaptureDevice.Position) -> AVCaptureDevice? {
        let types: [AVCaptureDevice.DeviceType] = position == .back
            ? [.builtInTripleCamera, .builtInDualWideCamera, .builtInDualCamera, .builtInWideAngleCamera]
            : [.builtInTrueDepthCamera, .builtInWideAngleCamera]
        return AVCaptureDevice.DiscoverySession(
            deviceTypes: types,
            mediaType: .video,
            position: position
        ).devices.first
    }

    private func withLockedDevice(_ device: AVCaptureDevice, _ body: (AVCaptureDevice) -> Void) throws {
        try device.lockForConfiguration()
        body(device)
        device.unlockForConfiguration()
    }

    private func onSessionQueue<T>(_ work: @escaping () throws -> T) async throws -> T {
        try await withCheckedThrowingContinuation { continuation in
            sessionQueue.async {
                continuation.resume(with: Result { try work() })
            }
        }
    }
}

// MARK: - Preview frames

extension CameraService: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        guard let onFrame, let pixelBuffer = sampleBuffer.imageBuffer else { return }
        let image = CIImage(cvPixelBuffer: pixelBuffer)
        onFrame(engine.apply(to: image))
    }
}
