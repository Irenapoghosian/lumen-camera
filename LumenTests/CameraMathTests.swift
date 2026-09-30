import XCTest
@testable import Lumen

final class CameraMathTests: XCTestCase {

    // A 3:4 view shows the whole 3:4 image, so mapping is a pure rotation.
    private let exact = CGSize(width: 300, height: 400)

    func testCenterMapsToCenter() {
        let p = CameraMath.pointOfInterest(forTap: CGPoint(x: 150, y: 200), in: exact, isMirrored: false)
        XCTAssertEqual(p.x, 0.5, accuracy: 0.0001)
        XCTAssertEqual(p.y, 0.5, accuracy: 0.0001)
    }

    func testTopLeftOfPortraitIsSensorBottomLeft() {
        // Portrait top-left → sensor (x: 0, y: 1) for the back camera.
        let p = CameraMath.pointOfInterest(forTap: .zero, in: exact, isMirrored: false)
        XCTAssertEqual(p.x, 0, accuracy: 0.0001)
        XCTAssertEqual(p.y, 1, accuracy: 0.0001)
    }

    func testMirroringFlipsHorizontalAxis() {
        let tap = CGPoint(x: 60, y: 100)
        let back = CameraMath.pointOfInterest(forTap: tap, in: exact, isMirrored: false)
        let front = CameraMath.pointOfInterest(forTap: tap, in: exact, isMirrored: true)
        XCTAssertEqual(back.x, front.x, accuracy: 0.0001)
        XCTAssertEqual(back.y, 1 - front.y, accuracy: 0.0001)
    }

    func testAspectFillAccountsForCroppedEdges() {
        // Tall view (9:16) crops the sides of a 3:4 image, so the view's left
        // edge is not the image's left edge.
        let tall = CGSize(width: 900, height: 1600)
        let p = CameraMath.pointOfInterest(forTap: CGPoint(x: 0, y: 800), in: tall, isMirrored: false)
        XCTAssertGreaterThan(1 - p.y, 0.05)
        XCTAssertEqual(p.x, 0.5, accuracy: 0.0001)
    }

    func testResultIsAlwaysNormalized() {
        let p = CameraMath.pointOfInterest(forTap: CGPoint(x: -50, y: 900), in: exact, isMirrored: false)
        XCTAssertTrue((0...1).contains(p.x))
        XCTAssertTrue((0...1).contains(p.y))
    }

    func testEmptyViewFallsBackToCenter() {
        let p = CameraMath.pointOfInterest(forTap: CGPoint(x: 10, y: 10), in: .zero, isMirrored: false)
        XCTAssertEqual(p, CGPoint(x: 0.5, y: 0.5))
    }

    func testZoomClamp() {
        XCTAssertEqual(CameraMath.clampedZoom(0.2, min: 1, max: 10), 1)
        XCTAssertEqual(CameraMath.clampedZoom(4, min: 1, max: 10), 4)
        XCTAssertEqual(CameraMath.clampedZoom(40, min: 1, max: 10), 10)
    }

    func testBiasClamp() {
        XCTAssertEqual(CameraMath.clampedBias(-9, min: -8, max: 8), -8)
        XCTAssertEqual(CameraMath.clampedBias(1.5, min: -8, max: 8), 1.5)
    }
}
