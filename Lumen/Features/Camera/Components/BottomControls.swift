import SwiftUI

struct BottomControls: View {
    @Bindable var model: CameraViewModel

    var body: some View {
        VStack(spacing: 14) {
            ZoomPresetBar(model: model)
                .padding(.top, 10)

            FilterCarousel(selection: $model.filter)

            if model.filter != .original {
                HStack(spacing: 14) {
                    IntensitySlider(value: $model.intensity)
                    CompareButton(isComparing: $model.isComparing)
                }
                .padding(.leading, 40)
                .padding(.trailing, 24)
                .transition(.opacity.combined(with: .move(edge: .bottom)))
            }

            Spacer(minLength: 0)

            HStack {
                ThumbnailButton(image: model.lastThumbnail)

                Spacer()

                ShutterButton(isBusy: model.isCapturing || model.interruption != nil) {
                    Task { await model.capture() }
                }

                Spacer()

                IconButton(systemName: "arrow.triangle.2.circlepath", label: "Switch camera") {
                    Task { await model.flipCamera() }
                }
                .frame(width: 56, height: 56)
            }
            .padding(.horizontal, 32)
            .padding(.bottom, 12)
        }
        .animation(.snappy, value: model.filter == .original)
    }
}

/// Press and hold to see the frame without the filter, like Instagram's editor.
struct CompareButton: View {
    @Binding var isComparing: Bool

    var body: some View {
        Image(systemName: "square.split.2x1")
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(isComparing ? Color.black : .white)
            .frame(width: 36, height: 36)
            .background(isComparing ? Color.accentColor : .white.opacity(0.08), in: Circle())
            .contentShape(Circle())
            .onLongPressGesture(minimumDuration: .infinity, maximumDistance: 60) {
                // Never fires: the gesture only exists to track pressing.
            } onPressingChanged: { pressing in
                isComparing = pressing
            }
            .sensoryFeedback(.selection, trigger: isComparing)
            .accessibilityLabel("Compare with original")
            .accessibilityHint("Hold to see the photo without the filter")
            .accessibilityAddTraits(.isButton)
    }
}

struct ThumbnailButton: View {
    let image: UIImage?

    var body: some View {
        Button {
            if let url = URL(string: "photos-redirect://") { UIApplication.shared.open(url) }
        } label: {
            ZStack {
                RoundedRectangle(cornerRadius: 10).fill(.white.opacity(0.1))
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .transition(.scale(scale: 0.6).combined(with: .opacity))
                }
            }
            .frame(width: 56, height: 56)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(.white.opacity(0.25), lineWidth: 1))
            .animation(.spring(duration: 0.35), value: image)
        }
        .disabled(image == nil)
        .accessibilityLabel("Last photo")
        .accessibilityHint("Opens Photos")
    }
}
