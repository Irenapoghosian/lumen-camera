import Photos

enum PhotoLibraryError: LocalizedError {
    case notAuthorized

    var errorDescription: String? {
        "Allow Lumen to add photos in Settings to save your shots."
    }
}

/// Saves encoded image data to the user's photo library (add-only access).
struct PhotoLibraryService: PhotoSaving {

    func save(_ data: Data) async throws {
        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard status == .authorized || status == .limited else { throw PhotoLibraryError.notAuthorized }

        try await PHPhotoLibrary.shared().performChanges {
            let request = PHAssetCreationRequest.forAsset()
            request.addResource(with: .photo, data: data, options: nil)
        }
    }
}
