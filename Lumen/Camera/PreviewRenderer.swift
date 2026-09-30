import CoreImage
import MetalKit
import SwiftUI

/// Draws the latest filtered camera frame into an MTKView with Core Image on the GPU.
final class PreviewRenderer: NSObject, MTKViewDelegate, @unchecked Sendable {

    let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    private let context: CIContext
    private let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!

    private let lock = NSLock()
    private var latestImage: CIImage?
    private var hasNewFrame = false

    init?(device: MTLDevice? = MTLCreateSystemDefaultDevice()) {
        guard let device, let queue = device.makeCommandQueue() else { return nil }
        self.device = device
        self.commandQueue = queue
        self.context = CIContext(mtlDevice: device, options: [.cacheIntermediates: false])
        super.init()
    }

    /// Safe to call from any thread.
    func enqueue(_ image: CIImage) {
        lock.withLock {
            latestImage = image
            hasNewFrame = true
        }
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        lock.withLock { hasNewFrame = latestImage != nil }
    }

    func draw(in view: MTKView) {
        // Skip the GPU work when the camera hasn't delivered anything new.
        let next: CIImage? = lock.withLock {
            defer { hasNewFrame = false }
            return hasNewFrame ? latestImage : nil
        }
        guard
            let image = next,
            let drawable = view.currentDrawable,
            let commandBuffer = commandQueue.makeCommandBuffer()
        else { return }

        let target = view.drawableSize
        let filled = Self.aspectFill(image, into: target)

        let destination = CIRenderDestination(
            width: Int(target.width),
            height: Int(target.height),
            pixelFormat: view.colorPixelFormat,
            commandBuffer: commandBuffer,
            mtlTextureProvider: { drawable.texture }
        )
        destination.colorSpace = colorSpace

        _ = try? context.startTask(toClear: destination)
        _ = try? context.startTask(
            toRender: filled,
            from: CGRect(origin: .zero, size: target),
            to: destination,
            at: .zero
        )

        commandBuffer.present(drawable)
        commandBuffer.commit()
    }

    /// Scales and centres `image` so it covers `size`, cropping the overflow.
    static func aspectFill(_ image: CIImage, into size: CGSize) -> CIImage {
        let extent = image.extent
        guard extent.width > 0, extent.height > 0 else { return image }
        let scale = max(size.width / extent.width, size.height / extent.height)
        let scaledWidth = extent.width * scale
        let scaledHeight = extent.height * scale
        return image
            .transformed(by: CGAffineTransform(translationX: -extent.minX, y: -extent.minY))
            .transformed(by: CGAffineTransform(scaleX: scale, y: scale))
            .transformed(by: CGAffineTransform(
                translationX: (size.width - scaledWidth) / 2,
                y: (size.height - scaledHeight) / 2
            ))
    }
}

/// SwiftUI wrapper for the Metal preview.
struct CameraPreview: UIViewRepresentable {
    let renderer: PreviewRenderer

    func makeUIView(context: Context) -> MTKView {
        let view = MTKView(frame: .zero, device: renderer.device)
        view.delegate = renderer
        view.framebufferOnly = false
        view.colorPixelFormat = .bgra8Unorm
        view.preferredFramesPerSecond = 60
        view.backgroundColor = .black
        view.clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
        view.contentMode = .scaleAspectFill
        view.isUserInteractionEnabled = false
        return view
    }

    func updateUIView(_ uiView: MTKView, context: Context) {}
}
