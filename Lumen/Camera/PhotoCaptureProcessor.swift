import AVFoundation
import CoreImage
import ImageIO

/// Handles one photo capture: grabs the full-res frame, applies the same
/// filter used in the preview and encodes the result.
final class PhotoCaptureProcessor: NSObject, AVCapturePhotoCaptureDelegate {

    private let engine: FilterEngine
    private let context: CIContext
    private let willCapture: @Sendable () -> Void
    private let completion: (Result<Data, Error>) -> Void
    private var didComplete = false

    init(
        engine: FilterEngine,
        context: CIContext,
        willCapture: @escaping @Sendable () -> Void,
        completion: @escaping (Result<Data, Error>) -> Void
    ) {
        self.engine = engine
        self.context = context
        self.willCapture = willCapture
        self.completion = completion
    }

    func photoOutput(_ output: AVCapturePhotoOutput, willCapturePhotoFor resolvedSettings: AVCaptureResolvedPhotoSettings) {
        willCapture()
    }

    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        if let error { return finish(.failure(error)) }

        guard
            let data = photo.fileDataRepresentation(),
            let source = CIImage(data: data, options: [.applyOrientationProperty: true])
        else { return finish(.failure(CameraError.captureFailed)) }

        // Nothing to do for the untouched look — keep the original file and its metadata.
        guard engine.filter != .original, engine.intensity > 0 else { return finish(.success(data)) }

        let output = engine.apply(to: source)
            .settingProperties(Self.metadata(from: photo.metadata))
        let colorSpace = source.colorSpace ?? CGColorSpace(name: CGColorSpace.displayP3)!

        if let heif = context.heifRepresentation(of: output, format: .RGBA8, colorSpace: colorSpace, options: [:]) {
            finish(.success(heif))
        } else if let jpeg = context.jpegRepresentation(of: output, colorSpace: colorSpace, options: [:]) {
            finish(.success(jpeg))
        } else {
            finish(.failure(CameraError.captureFailed))
        }
    }

    func photoOutput(_ output: AVCapturePhotoOutput, didFinishCaptureFor resolvedSettings: AVCaptureResolvedPhotoSettings, error: Error?) {
        if let error { finish(.failure(error)) }
    }

    /// Keeps the original EXIF/TIFF metadata (date, lens, exposure…) on the
    /// re-encoded photo. The pixels are already upright, so orientation is reset.
    static func metadata(from original: [String: Any]) -> [String: Any] {
        var metadata = original
        metadata[kCGImagePropertyOrientation as String] = 1

        if var tiff = metadata[kCGImagePropertyTIFFDictionary as String] as? [String: Any] {
            tiff[kCGImagePropertyTIFFOrientation as String] = 1
            metadata[kCGImagePropertyTIFFDictionary as String] = tiff
        }
        // Dimensions are rewritten by the encoder; stale values would be wrong after rotation.
        if var exif = metadata[kCGImagePropertyExifDictionary as String] as? [String: Any] {
            exif[kCGImagePropertyExifPixelXDimension as String] = nil
            exif[kCGImagePropertyExifPixelYDimension as String] = nil
            metadata[kCGImagePropertyExifDictionary as String] = exif
        }
        metadata[kCGImagePropertyPixelWidth as String] = nil
        metadata[kCGImagePropertyPixelHeight as String] = nil
        return metadata
    }

    private func finish(_ result: Result<Data, Error>) {
        guard !didComplete else { return }
        didComplete = true
        completion(result)
    }
}
