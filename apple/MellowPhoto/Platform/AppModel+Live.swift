import Foundation
import MellowExport
import MellowLibrary
import MellowRendering

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
        let model = AppModel(
            session: session,
            pipeline: PhotoPipeline(analyzer: VisionFaceAnalyzer(), tuning: RenderTuning.forCurrentDevice()),
            copies: copies,
            importer: SystemPhotoImporter(),
            exporter: Exporter(renderer: Renderer()))
        do {
            try copies.prepareDirectory()
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
}
