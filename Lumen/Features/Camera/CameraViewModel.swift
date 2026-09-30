import AVFoundation
import Observation
import UIKit

@MainActor
@Observable
final class CameraViewModel {

    enum Status: Equatable {
        case idle
        case running
        case denied
        case failed(String)
    }

    // MARK: State

    private(set) var status: Status = .idle
    private(set) var capabilities = CameraCapabilities()
    private(set) var isCapturing = false
    private(set) var shutterFlash = false
    private(set) var captureCount = 0
    private(set) var lastThumbnail: UIImage?
    private(set) var focusPoint: CGPoint?
    var toast: String?

    var filter: FilterKind = .original { didSet { syncEngine() } }
    var intensity: Double = 1.0 { didSet { syncEngine() } }
    var flashMode: AVCaptureDevice.FlashMode = .off
    var showGrid = false
    var showExposure = false

    private(set) var zoom: CGFloat = 1
    private(set) var exposureBias: Float = 0

    // MARK: Dependencies

    let renderer: PreviewRenderer?
    private let camera: CameraService
    private let library: PhotoLibraryService
    private var zoomAtGestureStart: CGFloat = 1
    private var focusResetTask: Task<Void, Never>?

    init(camera: CameraService = CameraService(), library: PhotoLibraryService = PhotoLibraryService()) {
        self.camera = camera
        self.library = library
        self.renderer = PreviewRenderer()

        let renderer = self.renderer
        camera.onFrame = { image in renderer?.enqueue(image) }
    }

    // MARK: Lifecycle

    func start() async {
        guard status != .running else { return }
        guard await CameraService.requestAccess() else {
            status = .denied
            return
        }
        do {
            capabilities = try await camera.start()
            setZoom(capabilities.baseZoom)
            status = .running
        } catch {
            status = .failed(error.localizedDescription)
        }
    }

    func stop() {
        camera.stop()
        if status == .running { status = .idle }
    }

    // MARK: Controls

    func flipCamera() async {
        do {
            capabilities = try await camera.switchCamera()
            setZoom(capabilities.baseZoom)
            exposureBias = 0
            focusPoint = nil
            if !capabilities.hasFlash { flashMode = .off }
        } catch {
            toast = error.localizedDescription
        }
    }

    func cycleFlash() {
        flashMode = switch flashMode {
        case .off: .auto
        case .auto: .on
        default: .off
        }
    }

    func beginZoom() {
        zoomAtGestureStart = zoom
    }

    func updateZoom(magnification: CGFloat) {
        setZoom(zoomAtGestureStart * magnification)
    }

    func setZoom(_ factor: CGFloat) {
        zoom = CameraMath.clampedZoom(factor, min: capabilities.minZoom, max: capabilities.maxZoom)
        camera.setZoom(zoom)
    }

    /// Zoom as the user thinks of it: 1× = main lens, 0.5× = ultra-wide.
    var displayZoom: CGFloat { zoom / capabilities.baseZoom }

    /// Lens shortcuts shown above the shutter.
    var zoomPresets: [CGFloat] {
        let base = capabilities.baseZoom
        return [0.5, 1, 2, 3].filter { preset in
            let factor = preset * base
            return factor >= capabilities.minZoom - 0.001 && factor <= capabilities.maxZoom + 0.001
        }
    }

    func selectZoomPreset(_ preset: CGFloat) {
        setZoom(preset * capabilities.baseZoom)
    }

    func setExposure(_ bias: Float) {
        exposureBias = CameraMath.clampedBias(bias, min: capabilities.minBias, max: capabilities.maxBias)
        camera.setExposureBias(exposureBias)
    }

    func focus(atTap tap: CGPoint, in size: CGSize) {
        let point = CameraMath.pointOfInterest(
            forTap: tap,
            in: size,
            isMirrored: capabilities.position == .front
        )
        camera.focus(at: point)
        exposureBias = 0
        focusPoint = tap

        focusResetTask?.cancel()
        focusResetTask = Task {
            try? await Task.sleep(for: .seconds(1.5))
            guard !Task.isCancelled else { return }
            focusPoint = nil
        }
    }

    // MARK: Capture

    func capture() async {
        guard status == .running, !isCapturing else { return }
        isCapturing = true
        defer { isCapturing = false }

        do {
            let data = try await camera.capturePhoto(flash: flashMode) { [weak self] in
                Task { @MainActor in self?.flashShutter() }
            }
            captureCount += 1
            lastThumbnail = await Self.makeThumbnail(from: data)
            try await library.save(data)
        } catch {
            toast = error.localizedDescription
        }
    }

    // MARK: Private

    private func syncEngine() {
        camera.engine = FilterEngine(filter: filter, intensity: intensity)
    }

    private func flashShutter() {
        shutterFlash = true
        Task {
            try? await Task.sleep(for: .milliseconds(120))
            shutterFlash = false
        }
    }

    /// Decodes off the main actor and keeps the aspect ratio (the button crops it).
    nonisolated private static func makeThumbnail(from data: Data) async -> UIImage? {
        guard let image = UIImage(data: data), image.size.width > 0, image.size.height > 0 else { return nil }
        let scale = 200 / min(image.size.width, image.size.height)
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        return await image.byPreparingThumbnail(ofSize: size)
    }
}
