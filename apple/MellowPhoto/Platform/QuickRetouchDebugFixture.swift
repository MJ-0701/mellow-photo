#if DEBUG
    import CoreImage
    import Foundation
    import ImageIO
    import MellowExport
    import MellowLibrary
    import MellowRendering
    import MellowShared

    /// UI 테스트 전용. 출시 빌드에는 없으며 사용자 세션·사진 경로에 접근하지 않는다.
    extension AppModel {
        static func quickRetouchDebugFixture() throws -> AppModel {
            if ProcessInfo.processInfo.arguments.contains("--portrait-overrides") {
                return try oneTouchDebugFixture()
            }
            let root = FileManager.default.temporaryDirectory
                .appendingPathComponent("MellowQuickRetouch-\(UUID().uuidString)", isDirectory: true)
            let copies = WorkingCopyStore(directory: root.appendingPathComponent("Library", isDirectory: true))
            try copies.prepareDirectory()
            let session = ProjectSession(
                store: JSONSessionStore(fileURL: root.appendingPathComponent("session.json")), maxPhotos: 3)
            for index in 0..<3 {
                let filename = "synthetic-\(index).png"
                let image = CIImage(color: CIColor(red: 0.12 + Double(index) * 0.2, green: 0.2, blue: 0.28))
                    .cropped(to: CGRect(x: 0, y: 0, width: 480, height: 320))
                let cg = try Renderer().makeCGImage(image)
                guard
                    let destination = CGImageDestinationCreateWithURL(
                        copies.url(for: filename) as CFURL, "public.png" as CFString, 1, nil)
                else {
                    throw MellowError.cannotWriteToFolder
                }
                CGImageDestinationAddImage(destination, cg, nil)
                guard CGImageDestinationFinalize(destination) else { throw MellowError.cannotWriteToFolder }
                try session.add(PhotoEntry(id: PhotoID(), filename: filename, displayName: "합성 사진 \(index + 1)"))
            }
            let looks = bundledLookCatalog() ?? .empty
            return AppModel(
                session: session,
                pipeline: PhotoPipeline(
                    analyzer: QuickRetouchDebugAnalyzer(), tuning: RenderTuning(), lookCatalog: looks),
                copies: copies, importer: SystemPhotoImporter(), exporter: Exporter(renderer: Renderer()),
                lookCatalog: looks, makeupCatalog: .empty)
        }
    }

    /// 복원 3건 뒤의 재분석만 잠깐 지연해 실제 취소 버튼 접근성을 확인한다.
    private final class QuickRetouchDebugAnalyzer: FaceAnalyzer, @unchecked Sendable {
        private let lock = NSLock()
        private var calls = 0
        func analyze(_ image: CIImage) throws -> [FaceGeometry] {
            lock.lock()
            calls += 1
            let delays = calls > 3
            lock.unlock()
            if delays { Thread.sleep(forTimeInterval: 2) }
            return []
        }
    }
#endif
