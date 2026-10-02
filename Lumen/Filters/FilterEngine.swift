import CoreImage
import CoreImage.CIFilterBuiltins

/// Applies a `FilterKind` at a given intensity. Pure and thread-safe, so the same
/// code path renders the live preview and the full-resolution photo.
struct FilterEngine: Sendable {
    var filter: FilterKind = .original
    /// 0 = untouched, 1 = full effect.
    var intensity: Double = 1.0

    func apply(to image: CIImage) -> CIImage {
        let amount = min(max(intensity, 0), 1)
        guard filter != .original, amount > 0 else { return image }

        let full = filter.filtered(image).cropped(to: image.extent)
        guard amount < 1 else { return full }

        let blend = CIFilter.dissolveTransition()
        blend.inputImage = image
        blend.targetImage = full
        blend.time = Float(amount)
        return blend.outputImage?.cropped(to: image.extent) ?? full
    }
}

