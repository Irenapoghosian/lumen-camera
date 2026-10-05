import AVFoundation
import XCTest
@testable import Lumen

@MainActor
final class CameraViewModelTests: XCTestCase {

    private var camera: MockCamera!
    private var library: MockLibrary!
    private var model: CameraViewModel!

    override func setUp() async throws {
        camera = MockCamera()
        library = MockLibrary()
        model = CameraViewModel(camera: camera, library: library, renderer: nil)
    }

    // MARK: Lifecycle

    func testStartWithoutPermissionShowsDenied() async {
        camera.accessGranted = false
        await model.start()
        XCTAssertEqual(model.status, .denied)
        XCTAssertEqual(camera.startCount, 0)
    }

    func testStartRunsAndOpensOnMainLens() async {
        await model.start()
        XCTAssertEqual(model.status, .running)
        XCTAssertEqual(model.zoom, 2)          // main lens on a device with ultra-wide
        XCTAssertEqual(model.displayZoom, 1)   // shown to the user as 1×
        XCTAssertEqual(camera.zoomCalls.last, 2)
    }

    func testStartFailureIsReported() async {
        camera.startError = TestError()
        await model.start()
        XCTAssertEqual(model.status, .failed("Something went wrong."))
    }

    func testRestartKeepsUserZoom() async {
        await model.start()
        model.selectZoomPreset(3)
        await model.start() // e.g. coming back from background
        XCTAssertEqual(model.displayZoom, 3)
        XCTAssertEqual(camera.startCount, 2)
    }

    // MARK: Zoom

    func testPresetsIncludeUltraWideWhenAvailable() async {
        await model.start()
        XCTAssertEqual(model.zoomPresets, [0.5, 1, 2, 3])
    }

    func testPresetsWithoutUltraWide() async {
        camera.capabilities = CameraCapabilities(minZoom: 1, maxZoom: 10, baseZoom: 1)
        await model.start()
        XCTAssertEqual(model.zoomPresets, [1, 2, 3])
    }

    func testPinchZoomIsRelativeToGestureStartAndClamped() async {
        await model.start()
        model.beginZoom()
        model.updateZoom(magnification: 2)
        XCTAssertEqual(model.zoom, 4)
        model.updateZoom(magnification: 100)
        XCTAssertEqual(model.zoom, 20)
    }

    // MARK: Filters

    func testChangingFilterResetsIntensityAndUpdatesEngine() {
        model.filter = .noir
        model.intensity = 0.3
        model.filter = .warm

        XCTAssertEqual(model.intensity, 1)
        XCTAssertEqual(camera.engine.filter, .warm)
        XCTAssertEqual(camera.engine.intensity, 1)
    }

    func testIntensityIsForwardedToEngine() {
        model.filter = .mono
        model.intensity = 0.4
        XCTAssertEqual(camera.engine.intensity, 0.4, accuracy: 0.0001)
    }

    // MARK: Focus & exposure

    func testTapToFocusForwardsPointAndResetsExposure() async {
        await model.start()
        model.setExposure(1.5)
        model.focus(atTap: CGPoint(x: 150, y: 200), in: CGSize(width: 300, height: 400))

        XCTAssertEqual(camera.focusPoints.count, 1)
        XCTAssertEqual(model.exposureBias, 0)
        XCTAssertEqual(model.focusPoint, CGPoint(x: 150, y: 200))
    }

    func testExposureIsClampedToDeviceRange() async {
        await model.start()
        model.setExposure(20)
        XCTAssertEqual(model.exposureBias, 8)
        XCTAssertEqual(camera.biasCalls.last, 8)
    }

    // MARK: Flash & camera switching

    func testFlashCyclesOffAutoOn() {
        XCTAssertEqual(model.flashMode, .off)
        model.cycleFlash(); XCTAssertEqual(model.flashMode, .auto)
        model.cycleFlash(); XCTAssertEqual(model.flashMode, .on)
        model.cycleFlash(); XCTAssertEqual(model.flashMode, .off)
    }

    func testSwitchingToCameraWithoutFlashTurnsFlashOff() async {
        await model.start()
        model.flashMode = .on
        await model.flipCamera()

        XCTAssertEqual(model.capabilities.position, .front)
        XCTAssertEqual(model.flashMode, .off)
        XCTAssertEqual(model.displayZoom, 1)
    }

    // MARK: Capture

    func testCaptureSavesPhotoWithCurrentFlash() async {
        await model.start()
        model.flashMode = .auto
        await model.capture()

        XCTAssertEqual(library.saved.count, 1)
        XCTAssertEqual(camera.capturedFlashModes, [.auto])
        XCTAssertEqual(model.captureCount, 1)
        XCTAssertFalse(model.isCapturing)
    }

    func testCaptureFailureShowsToast() async {
        await model.start()
        camera.captureResult = .failure(TestError())
        await model.capture()

        XCTAssertEqual(model.toast, "Something went wrong.")
        XCTAssertTrue(library.saved.isEmpty)
    }

    func testSaveFailureShowsToast() async {
        await model.start()
        library.error = PhotoLibraryError.notAuthorized
        await model.capture()
        XCTAssertNotNil(model.toast)
    }

    func testCaptureIsIgnoredBeforeStart() async {
        await model.capture()
        XCTAssertTrue(camera.capturedFlashModes.isEmpty)
    }

    // MARK: Interruptions

    func testInterruptionPausesCaptureUntilItEnds() async {
        await model.start()

        camera.onInterruption?(.inUseByAnotherApp)
        await settle { self.model.interruption != nil }
        XCTAssertEqual(model.interruption, .inUseByAnotherApp)

        await model.capture()
        XCTAssertTrue(camera.capturedFlashModes.isEmpty)

        camera.onInterruption?(nil)
        await settle { self.model.interruption == nil }
        XCTAssertNil(model.interruption)

        await model.capture()
        XCTAssertEqual(camera.capturedFlashModes.count, 1)
    }

    func testBackgroundInterruptionIsNotShown() {
        XCTAssertNil(CameraInterruption(reason: .videoDeviceNotAvailableInBackground))
        XCTAssertEqual(CameraInterruption(reason: .videoDeviceInUseByAnotherClient), .inUseByAnotherApp)
    }

    /// The interruption callback hops to the main actor; give it a moment to land.
    private func settle(until condition: () -> Bool) async {
        for _ in 0..<100 where !condition() {
            try? await Task.sleep(for: .milliseconds(10))
        }
    }
}
