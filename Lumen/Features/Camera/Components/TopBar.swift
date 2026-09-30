import AVFoundation
import SwiftUI

struct TopBar: View {
    @Bindable var model: CameraViewModel

    var body: some View {
        HStack {
            if model.capabilities.hasFlash {
                IconButton(systemName: flashIcon, isActive: model.flashMode != .off, label: flashLabel) {
                    model.cycleFlash()
                }
            } else {
                Color.clear.frame(width: 40, height: 40)
            }

            Spacer()

            Text(String(format: "%.1f×", model.displayZoom))
                .font(.system(.footnote, design: .rounded).monospacedDigit().weight(.semibold))
                .foregroundStyle(.white.opacity(0.7))
                .accessibilityLabel("Zoom \(String(format: "%.1f", model.displayZoom)) times")

            Spacer()

            HStack(spacing: 8) {
                IconButton(systemName: "plusminus.circle", isActive: model.showExposure, label: "Exposure") {
                    withAnimation(.snappy) { model.showExposure.toggle() }
                }
                IconButton(systemName: "grid", isActive: model.showGrid, label: "Grid") {
                    model.showGrid.toggle()
                }
            }
        }
    }

    private var flashIcon: String {
        switch model.flashMode {
        case .on: "bolt.fill"
        case .auto: "bolt.badge.automatic.fill"
        default: "bolt.slash.fill"
        }
    }

    private var flashLabel: String {
        switch model.flashMode {
        case .on: "Flash on"
        case .auto: "Flash auto"
        default: "Flash off"
        }
    }
}

struct IconButton: View {
    let systemName: String
    var isActive = false
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(isActive ? Color.accentColor : .white)
                .frame(width: 40, height: 40)
                .background(.white.opacity(0.08), in: Circle())
                .contentTransition(.symbolEffect(.replace))
        }
        .accessibilityLabel(label)
        .accessibilityAddTraits(isActive ? .isSelected : [])
    }
}
