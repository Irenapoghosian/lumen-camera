import SwiftUI

struct ShutterButton: View {
    let isBusy: Bool
    let action: () -> Void

    @State private var isPressed = false

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .stroke(.white, lineWidth: 4)
                    .frame(width: 78, height: 78)
                Circle()
                    .fill(.white)
                    .frame(width: 64, height: 64)
                    .scaleEffect(isPressed ? 0.86 : 1)
                    .opacity(isBusy ? 0.5 : 1)
            }
        }
        .buttonStyle(PressTrackingStyle(isPressed: $isPressed))
        .disabled(isBusy)
        .accessibilityLabel("Take photo")
    }
}

/// Exposes the pressed state so the inner disc can shrink like the system camera.
private struct PressTrackingStyle: ButtonStyle {
    @Binding var isPressed: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .onChange(of: configuration.isPressed) { _, pressed in
                withAnimation(.spring(duration: 0.2)) { isPressed = pressed }
            }
    }
}
