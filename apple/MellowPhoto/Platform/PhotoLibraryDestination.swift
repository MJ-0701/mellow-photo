#if os(iOS)
    import Foundation
    import MellowExport
    import MellowShared
    import Photos
    import os

    /// 사진 앱에 새 사진으로 추가한다. 원본 자산은 건드리지 않는다.
    struct PhotoLibraryDestination: ExportDestination {
        func publish(fileURL: URL, suggestedName: String) async throws {
            let permission = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
            guard permission == .authorized || permission == .limited else {
                throw MellowError.photoLibraryAccessDenied
            }
            // 변경 블록은 던질 수 없어서, 요청이 만들어졌는지 기록해 두고 끝난 뒤 확인한다.
            let created = OSAllocatedUnfairLock(initialState: false)
            do {
                try await PHPhotoLibrary.shared().performChanges {
                    let request = PHAssetChangeRequest.creationRequestForAssetFromImage(atFileURL: fileURL)
                    let wasCreated = request != nil
                    created.withLock { $0 = wasCreated }
                }
            } catch {
                throw MellowError.exportFailed(reason: error.localizedDescription)
            }
            guard created.withLock({ $0 }) else {
                throw MellowError.exportFailed(reason: UserMessage.photoLibraryCouldNotCreateAsset)
            }
        }
    }
#endif
