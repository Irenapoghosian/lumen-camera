import ImageIO
import XCTest
@testable import Lumen

final class PhotoMetadataTests: XCTestCase {

    private let original: [String: Any] = [
        kCGImagePropertyOrientation as String: 6,
        kCGImagePropertyPixelWidth as String: 4032,
        kCGImagePropertyPixelHeight as String: 3024,
        kCGImagePropertyTIFFDictionary as String: [
            kCGImagePropertyTIFFOrientation as String: 6,
            kCGImagePropertyTIFFModel as String: "iPhone",
        ],
        kCGImagePropertyExifDictionary as String: [
            kCGImagePropertyExifLensModel as String: "Back Triple Camera",
            kCGImagePropertyExifISOSpeedRatings as String: [64],
            kCGImagePropertyExifPixelXDimension as String: 4032,
            kCGImagePropertyExifPixelYDimension as String: 3024,
        ],
    ]

    func testOrientationIsResetBecausePixelsAreAlreadyUpright() {
        let metadata = PhotoCaptureProcessor.metadata(from: original)
        let tiff = metadata[kCGImagePropertyTIFFDictionary as String] as? [String: Any]

        XCTAssertEqual(metadata[kCGImagePropertyOrientation as String] as? Int, 1)
        XCTAssertEqual(tiff?[kCGImagePropertyTIFFOrientation as String] as? Int, 1)
    }

    func testCameraDetailsAreKept() {
        let metadata = PhotoCaptureProcessor.metadata(from: original)
        let exif = metadata[kCGImagePropertyExifDictionary as String] as? [String: Any]
        let tiff = metadata[kCGImagePropertyTIFFDictionary as String] as? [String: Any]

        XCTAssertEqual(exif?[kCGImagePropertyExifLensModel as String] as? String, "Back Triple Camera")
        XCTAssertEqual(tiff?[kCGImagePropertyTIFFModel as String] as? String, "iPhone")
    }

    func testStaleDimensionsAreRemoved() {
        let metadata = PhotoCaptureProcessor.metadata(from: original)
        let exif = metadata[kCGImagePropertyExifDictionary as String] as? [String: Any]

        XCTAssertNil(metadata[kCGImagePropertyPixelWidth as String])
        XCTAssertNil(exif?[kCGImagePropertyExifPixelXDimension as String])
    }
}
