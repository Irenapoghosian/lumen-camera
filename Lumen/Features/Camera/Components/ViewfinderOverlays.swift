import SwiftUI

struct ZoomPresetBar: View {
    let model: CameraViewModel

    var body: some View {
        HStack(spacing: 6) {
            ForEach(model.zoomPresets, id: \.self) { preset in
                let isCurrent = abs(model.displayZoom - preset) < 0.05
                Button {
                    withAnimation(.snappy) { model.selectZoomPreset(preset) }
                } label: {
                    Text(label(for: preset, isCurrent: isCurrent))
                        .font(.system(size: isCurrent ? 13 : 11, weight: .bold, design: .rounded).monospacedDigit())
                        .foregroundStyle(isCurrent ? Color.accentColor : .white)
                        .frame(width: isCurrent ? 42 : 34, height: isCurrent ? 42 : 34)
                        .background(.black.opacity(0.45), in: Circle())
                }
                .accessibilityLabel("Zoom \(label(for: preset, isCurrent: false))")
            }
        }
        .padding(4)
        .background(.white.opacity(0.06), in: Capsule())
        .frame(height: 50)
    }

    private func label(for preset: CGFloat, isCurrent: Bool) -> String {
        let text = preset < 1 ? ".5" : String(format: "%.0f", preset)
        return isCurrent ? text + "×" : text
    }
}

struct GridOverlay: View {
    var body: some View {
        GeometryReader { geo in
            Path { path in
                for i in 1...2 {
                    let x = geo.size.width * CGFloat(i) / 3
                    let y = geo.size.height * CGFloat(i) / 3
                    path.move(to: CGPoint(x: x, y: 0))
                    path.addLine(to: CGPoint(x: x, y: geo.size.height))
                    path.move(to: CGPoint(x: 0, y: y))
                    path.addLine(to: CGPoint(x: geo.size.width, y: y))
                }
            }
            .stroke(.white.opacity(0.35), lineWidth: 0.5)
        }
    }
}

struct FocusIndicator: View {
    @State private var appeared = false

    var body: some View {
        RoundedRectangle(cornerRadius: 4)
            .stroke(Color.accentColor, lineWidth: 1.5)
            .frame(width: 72, height: 72)
            .scaleEffect(appeared ? 1 : 1.4)
            .opacity(appeared ? 1 : 0)
            .onAppear {
                withAnimation(.spring(duration: 0.3)) { appeared = true }
            }
    }
}

struct ExposureSlider: View {
    @Binding var value: Float
    let range: ClosedRange<Float>

    /// Most phones report ±8 EV; ±2 is the useful range.
    private var usable: ClosedRange<Float> {
        max(range.lowerBound, -2)...min(range.upperBound, 2)
    }

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "sun.max.fill")
                .font(.caption)
                .foregroundStyle(Color.accentColor)
            Slider(value: $value, in: usable)
                .tint(.accentColor)
                .frame(width: 180)
                .rotationEffect(.degrees(-90))
                .frame(width: 30, height: 180)
            Text(String(format: "%+.1f", value))
                .font(.system(.caption2, design: .rounded).monospacedDigit())
                .foregroundStyle(.white)
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 6)
        .background(.black.opacity(0.35), in: Capsule())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Exposure")
        .accessibilityValue(String(format: "%+.1f EV", value))
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: value = min(value + 0.3, usable.upperBound)
            case .decrement: value = max(value - 0.3, usable.lowerBound)
            @unknown default: break
            }
        }
    }
}
