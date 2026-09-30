import SwiftUI

struct BottomControls: View {
    @Bindable var model: CameraViewModel

    var body: some View {
        VStack(spacing: 14) {
            ZoomPresetBar(model: model)
                .padding(.top, 10)

            FilterCarousel(selection: $model.filter)

            if model.filter != .original {
                IntensitySlider(value: $model.intensity)
                    .padding(.horizontal, 40)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            }

            Spacer(minLength: 0)

            HStack {
                ThumbnailButton(image: model.lastThumbnail)

                Spacer()

                ShutterButton(isBusy: model.isCapturing) {
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
