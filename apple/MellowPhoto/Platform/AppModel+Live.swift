import Foundation
import MellowExport
import MellowLibrary
import MellowRendering
import MellowShared

extension AppModel {
    /// 실제 기기용 조립. 테스트는 TestSupport.makeModel을 쓴다.
    /// 경로는 출시된 iPhone 앱과 같아서 v1 세션 파일을 그대로 읽는다.
    static func live() -> AppModel {
        let applicationSupport = URL.applicationSupportDirectory
        let root = applicationSupport.appendingPathComponent("MellowPhoto", isDirectory: true)
        let copies = WorkingCopyStore(directory: root.appendingPathComponent("Library", isDirectory: true))
        let session = ProjectSession(
            store: JSONSessionStore(fileURL: root.appendingPathComponent("session.json")),
            maxPhotos: LibraryPolicy.maxPhotosForCurrentDevice)
        let bundledCatalog = bundledLookCatalog()
        let lookCatalog = bundledCatalog ?? .empty
        let model = AppModel(
            session: session,
            pipeline: PhotoPipeline(
                analyzer: VisionFaceAnalyzer(), personAnalyzer: VisionPersonAnalyzer(),
                tuning: RenderTuning.forCurrentDevice(), lookCatalog: lookCatalog),
            copies: copies,
            importer: SystemPhotoImporter(),
            exporter: Exporter(renderer: Renderer()),
            lookCatalog: lookCatalog)
        if bundledCatalog == nil {
            model.present(message: UserMessage.lookCatalogUnavailable)
        }
        do {
            try copies.prepareDirectory()
            try excludeFromBackup(root)
        } catch {
            model.present(message: UserMessage.workingFolderUnavailable(error.localizedDescription))
        }
        #if os(macOS)
            // 샌드박스 밖의 구 Mac 앱 폴더는 Resources/container-migration.plist가 첫 실행 때 컨테이너로 옮긴다.
            // 복원된 세션 위에 더해야 저장된 사진 목록을 덮어쓰지 않는다.
            model.afterSessionRestored = { session in
                LegacyMacPresets.importIfPresent(into: session, applicationSupport: applicationSupport)
            }
        #endif
        return model
    }

    /// 번들 카탈로그를 읽는다. 파일이 없거나 형식이 틀리면(DecodingError 포함) nil이고, 호출자가 빈 카탈로그와 안내 문구로 바꾼다.
    private static func bundledLookCatalog() -> LookCatalog? {
        guard
            let url = Bundle.main.url(
                forResource: Policy.bundledLookCatalogName, withExtension: Policy.bundledLookCatalogExtension)
        else { return nil }
        do {
            return try LookCatalog(data: Data(contentsOf: url))
        } catch {
            return nil
        }
    }

    /// 출시본처럼 session.json을 포함한 MellowPhoto 폴더 전체를 백업에서 뺀다. 사진 원본은 사용자 쪽에 있다.
    private static func excludeFromBackup(_ folder: URL) throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        var target = folder
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try target.setResourceValues(values)
    }
}
