import SwiftUI

struct CameraScreen: View {
    @State private var model = CameraViewModel()
    @State private var isPinching = false
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            switch model.status {
            case .denied:
                PermissionView()
            case .failed(let message):
                PermissionView(title: "Camera unavailable", message: message, showsSettings: false)
            case .idle, .running:
                camera
            }
        }
        .preferredColorScheme(.dark)
        .task { await model.start() }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active: Task { await model.start() }
            case .background: model.stop()
            default: break
            }
        }
        .sensoryFeedback(.impact(weight: .medium), trigger: model.captureCount)
        .sensoryFeedback(.selection, trigger: model.filter)
    }

    private var camera: some View {
        VStack(spacing: 0) {
            TopBar(model: model)
                .padding(.horizontal, 20)
                .frame(height: 52)

            viewfinder

            BottomControls(model: model)
                .frame(maxHeight: .infinity)
        }
        .overlay(alignment: .top) { toast }
    }

    // MARK: Viewfinder (3:4 so the preview matches the captured photo exactly)

    private var viewfinder: some View {
        GeometryReader { geo in
            ZStack {
                if let renderer = model.renderer {
                    CameraPreview(renderer: renderer)
                }

                if model.showGrid {
                    GridOverlay().allowsHitTesting(false)
                }

                if let point = model.focusPoint {
                    FocusIndicator()
                        .position(point)
                        .allowsHitTesting(false)
                        .id(point.x + point.y) // restart the animation on every tap
                }

                if model.showExposure {
                    ExposureSlider(
                        value: Binding(get: { model.exposureBias }, set: { model.setExposure($0) }),
                        range: model.capabilities.minBias...max(model.capabilities.maxBias, model.capabilities.minBias + 0.1)
                    )
                    .frame(maxHeight: .infinity, alignment: .center)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .padding(.trailing, 12)
                }

                Color.white
                    .opacity(model.shutterFlash ? 0.85 : 0)
                    .animation(.easeOut(duration: 0.12), value: model.shutterFlash)
                    .allowsHitTesting(false)
            }
            .contentShape(Rectangle())
            .gesture(
                SpatialTapGesture().onEnded { value in
                    model.focus(atTap: value.location, in: geo.size)
                }
            )
            .simultaneousGesture(
                MagnifyGesture()
                    .onChanged { value in
                        if !isPinching {
                            isPinching = true
                            model.beginZoom()
                        }
                        model.updateZoom(magnification: value.magnification)
                    }
                    .onEnded { _ in isPinching = false }
            )
        }
        .aspectRatio(3.0 / 4.0, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .accessibilityElement()
        .accessibilityLabel("Viewfinder")
        .accessibilityHint("Tap to focus, pinch to zoom")
    }

    @ViewBuilder
    private var toast: some View {
        if let message = model.toast {
            Text(message)
                .font(.footnote.weight(.medium))
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(.ultraThinMaterial, in: Capsule())
                .padding(.top, 60)
                .transition(.move(edge: .top).combined(with: .opacity))
                .task(id: message) {
                    try? await Task.sleep(for: .seconds(2.5))
                    withAnimation { model.toast = nil }
                }
        }
    }
}

#Preview {
    CameraScreen()
}
