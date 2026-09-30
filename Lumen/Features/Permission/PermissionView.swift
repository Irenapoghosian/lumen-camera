import SwiftUI

struct PermissionView: View {
    var title = "Lumen needs the camera"
    var message = "Allow camera access in Settings to start shooting with live filters."
    var showsSettings = true

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "camera.aperture")
                .font(.system(size: 56, weight: .light))
                .foregroundStyle(Color.accentColor)
            Text(title)
                .font(.title3.weight(.semibold))
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            if showsSettings {
                Button("Open Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
                .buttonStyle(.borderedProminent)
                .foregroundStyle(.black)
                .padding(.top, 8)
            }
        }
        .padding(32)
    }
}

#Preview {
    PermissionView().preferredColorScheme(.dark)
}
