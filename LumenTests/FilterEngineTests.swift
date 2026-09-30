import CoreImage
import XCTest
@testable import Lumen

final class FilterEngineTests: XCTestCase {

    private let context = CIContext(options: [.useSoftwareRenderer: false])
    private let red = CIImage(color: CIColor(red: 0.9, green: 0.2, blue: 0.1))
        .cropped(to: CGRect(x: 0, y: 0, width: 8, height: 8))

    func testOriginalReturnsSameImage() {
        let engine = FilterEngine(filter: .original, intensity: 1)
        XCTAssertTrue(engine.apply(to: red) === red)
    }

    func testZeroIntensityIsUntouched() {
        let engine = FilterEngine(filter: .noir, intensity: 0)
        XCTAssertTrue(engine.apply(to: red) === red)
    }

    func testEveryFilterPreservesExtent() {
        for filter in FilterKind.allCases {
            for intensity in [0.0, 0.5, 1.0] {
                let output = FilterEngine(filter: filter, intensity: intensity).apply(to: red)
                XCTAssertEqual(output.extent, red.extent, "\(filter) @ \(intensity)")
            }
        }
    }

    func testMonoRemovesColor() {
        let pixel = render(FilterEngine(filter: .mono, intensity: 1).apply(to: red))
        XCTAssertEqual(pixel.r, pixel.g, accuracy: 0.02)
        XCTAssertEqual(pixel.g, pixel.b, accuracy: 0.02)
    }

    func testHalfIntensitySitsBetweenOriginalAndFull() {
        let original = render(red)
        let full = render(FilterEngine(filter: .mono, intensity: 1).apply(to: red))
        let half = render(FilterEngine(filter: .mono, intensity: 0.5).apply(to: red))

        XCTAssertLessThan(half.r, original.r)
        XCTAssertGreaterThan(half.r, full.r)
    }

    func testIntensityIsClamped() {
        let over = render(FilterEngine(filter: .mono, intensity: 3).apply(to: red))
        let full = render(FilterEngine(filter: .mono, intensity: 1).apply(to: red))
        XCTAssertEqual(over.r, full.r, accuracy: 0.001)
    }

    func testFilterNamesAreUnique() {
        let names = FilterKind.allCases.map(\.displayName)
        XCTAssertEqual(Set(names).count, names.count)
    }

    // MARK: Helpers

    private func render(_ image: CIImage) -> (r: Double, g: Double, b: Double) {
        var bytes = [UInt8](repeating: 0, count: 4)
        context.render(
            image,
            toBitmap: &bytes,
            rowBytes: 4,
            bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
            format: .RGBA8,
            colorSpace: CGColorSpace(name: CGColorSpace.sRGB)
        )
        return (Double(bytes[0]) / 255, Double(bytes[1]) / 255, Double(bytes[2]) / 255)
    }
}
