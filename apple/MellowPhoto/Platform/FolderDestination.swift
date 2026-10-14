#if os(macOS)
    import Foundation
    import MellowExport
    import MellowShared

    /// 사용자가 고른 폴더에 "<이름>.<확장자>"로 복사한다. 충돌하면 번호를 붙인다.
    struct FolderDestination: ExportDestination {
        let folder: URL

        func publish(fileURL: URL, suggestedName: String) async throws {
            let accessed = folder.startAccessingSecurityScopedResource()
            defer {
                if accessed {
                    folder.stopAccessingSecurityScopedResource()
                }
            }
            // 이름 정책이 접미사를 다시 붙이므로 이미 붙은 접미사는 뗀다.
            let suffix = FileNamingPolicy.suffix
            let stem = suggestedName.hasSuffix(suffix) ? String(suggestedName.dropLast(suffix.count)) : suggestedName
            let target = FileNamingPolicy.availableURL(in: folder, stem: stem, fileExtension: fileURL.pathExtension) {
                FileManager.default.fileExists(atPath: $0.path)
            }
            do {
                try FileManager.default.copyItem(at: fileURL, to: target)
            } catch {
                throw MellowError.exportFailed(reason: error.localizedDescription)
            }
        }
    }
#endif
