#if os(iOS)
    import Foundation
    import MellowExport
    import MellowShared
    import Photos

    /// 사진 앱에 새 사진으로 추가한다. 원본 자산은 건드리지 않는다.
    struct PhotoLibraryDestination: ExportDestination {
        func publish(fileURL: URL, suggestedName: String) async throws {
            let permission = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
            guard permission == .authorized || permission == .limited else {
                throw MellowError.photoLibraryAccessDenied
            }
            do {
                try await PHPhotoLibrary.shared().performChanges {
                    PHAssetChangeRequest.creationRequestForAssetFromImage(atFileURL: fileURL)
                }
            } catch {
                throw MellowError.exportFailed(reason: error.localizedDescription)
            }
        }
    }
#endif
