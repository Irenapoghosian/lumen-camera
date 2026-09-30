import CoreImage
import CoreImage.CIFilterBuiltins

/// A creative look that can be applied to a live frame or a captured photo.
enum FilterKind: String, CaseIterable, Identifiable, Sendable {
    case original
    case vivid
    case warm
    case cool
    case fade
    case chrome
    case mono
    case noir

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .original: "Original"
        case .vivid: "Vivid"
        case .warm: "Warm"
        case .cool: "Cool"
        case .fade: "Fade"
        case .chrome: "Chrome"
        case .mono: "Mono"
        case .noir: "Noir"
        }
    }

    /// Returns the fully-filtered image (intensity is handled by `FilterEngine`).
    func filtered(_ image: CIImage) -> CIImage {
        switch self {
        case .original:
            return image

        case .vivid:
            let f = CIFilter.colorControls()
            f.inputImage = image
            f.saturation = 1.35
            f.contrast = 1.08
            f.brightness = 0.01
            return f.outputImage ?? image

        case .warm, .cool:
            let f = CIFilter.temperatureAndTint()
            f.inputImage = image
            f.neutral = CIVector(x: 6500, y: 0)
            // A higher target temperature than the source neutral shifts toward amber.
            f.targetNeutral = CIVector(x: self == .warm ? 7800 : 5200, y: 0)
            return f.outputImage ?? image

        case .fade:
            let f = CIFilter.photoEffectFade()
            f.inputImage = image
            return f.outputImage ?? image

        case .chrome:
            let f = CIFilter.photoEffectChrome()
            f.inputImage = image
            return f.outputImage ?? image

        case .mono:
            let f = CIFilter.photoEffectMono()
            f.inputImage = image
            return f.outputImage ?? image

        case .noir:
            let f = CIFilter.photoEffectNoir()
            f.inputImage = image
            return f.outputImage ?? image
        }
    }
}
