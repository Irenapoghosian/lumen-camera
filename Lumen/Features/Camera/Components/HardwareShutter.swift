import AVKit
import SwiftUI

/// Lets the volume buttons (and the Camera Control on newer iPhones) take a
/// photo, like the system Camera app. Requires iOS 17.2; does nothing earlier.
struct HardwareShutter: UIViewRepresentable {
    let action: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(action: action) }

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        if #available(iOS 17.2, *) {
            let coordinator = context.coordinator
            let interaction = AVCaptureEventInteraction { event in
                // Fire on release so a long press doesn't take a burst.
                if event.phase == .ended { coordinator.action() }
            }
            view.addInteraction(interaction)
        }
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        context.coordinator.action = action
    }

    final class Coordinator {
        var action: () -> Void
        init(action: @escaping () -> Void) { self.action = action }
    }
}
