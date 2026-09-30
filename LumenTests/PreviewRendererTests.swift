import CoreImage
import XCTest
@testable import Lumen

final class PreviewRendererTests: XCTestCase {

    func testAspectFillCoversTargetAndIsCentered() {
        let image = CIImage(color: .white).cropped(to: CGRect(x: 40, y: 20, width: 300, height: 400))
        let target = CGSize(width: 1170, height: 1560)

        let filled = PreviewRenderer.aspectFill(image, into: target).extent

        XCTAssertGreaterThanOrEqual(filled.width, target.width - 0.5)
        XCTAssertGreaterThanOrEqual(filled.height, target.height - 0.5)
        XCTAssertEqual(filled.midX, target.width / 2, accuracy: 0.5)
        XCTAssertEqual(filled.midY, target.height / 2, accuracy: 0.5)
    }

    func testAspectFillCropsWhenAspectDiffers() {
        let image = CIImage(color: .white).cropped(to: CGRect(x: 0, y: 0, width: 300, height: 400))
        let target = CGSize(width: 900, height: 1600) // taller than 3:4

        let filled = PreviewRenderer.aspectFill(image, into: target).extent

        XCTAssertEqual(filled.height, 1600, accuracy: 0.5)
        XCTAssertGreaterThan(filled.width, target.width) // sides overflow
    }
}
