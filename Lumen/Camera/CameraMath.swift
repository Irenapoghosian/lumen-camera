import CoreGraphics

/// Pure camera math, kept free of AVFoundation so it can be unit tested.
enum CameraMath {

    /// Converts a tap in the portrait preview into AVFoundation's point-of-interest
    /// space (landscape-right sensor coordinates, 0...1, origin top-left).
    ///
    /// The preview is aspect-filled, so part of the sensor image is cropped
    /// off-screen; `imageAspect` (sensor width / height in portrait) lets us undo that.
    static func pointOfInterest(
        forTap tap: CGPoint,
        in viewSize: CGSize,
        imageAspect: CGFloat = 3.0 / 4.0,
        isMirrored: Bool
    ) -> CGPoint {
        guard viewSize.width > 0, viewSize.height > 0 else { return CGPoint(x: 0.5, y: 0.5) }

        // Size of the portrait image once aspect-filled into the view.
        let viewAspect = viewSize.width / viewSize.height
        var drawn = viewSize
        if viewAspect > imageAspect {
            drawn.height = viewSize.width / imageAspect   // image taller than view
        } else {
            drawn.width = viewSize.height * imageAspect   // image wider than view
        }
        let offsetX = (drawn.width - viewSize.width) / 2
        let offsetY = (drawn.height - viewSize.height) / 2

        // Normalised position in the portrait image.
        var u = (tap.x + offsetX) / drawn.width
        let v = (tap.y + offsetY) / drawn.height
        if isMirrored { u = 1 - u }

        // Portrait → sensor (rotated 90°).
        return CGPoint(x: clamp01(v), y: clamp01(1 - u))
    }

    static func clampedZoom(_ factor: CGFloat, min minFactor: CGFloat, max maxFactor: CGFloat) -> CGFloat {
        Swift.min(Swift.max(factor, minFactor), maxFactor)
    }

    static func clampedBias(_ bias: Float, min minBias: Float, max maxBias: Float) -> Float {
        Swift.min(Swift.max(bias, minBias), maxBias)
    }

    private static func clamp01(_ value: CGFloat) -> CGFloat {
        Swift.min(Swift.max(value, 0), 1)
    }
}
