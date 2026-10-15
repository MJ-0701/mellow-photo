import CoreImage
import Foundation
import ImageIO
import MellowExport
import MellowLibrary
import MellowRendering
import MellowShared
import PhotosUI
import SwiftUI
import XCTest

@testable import Mellow_Photo

final class MemorySessionStore: SessionStore, @unchecked Sendable {
    var saved: SessionSnapshot?
    var saveCount = 0
    func load() throws -> SessionSnapshot? { saved }
    func save(_ snapshot: SessionSnapshot) throws {
        saveCount += 1
        saved = snapshot
    }
}

/// 얼굴 분석 호출 횟수. 값 타입인 StubFaceAnalyzer가 복사돼도 같은 기록을 공유한다.
final class AnalysisLog: @unchecked Sendable {
    var calls = 0
}

struct StubFaceAnalyzer: FaceAnalyzer {
    var result: Result<[FaceGeometry], MellowError> = .success([])
    var log = AnalysisLog()
    func analyze(_ image: CIImage) throws -> [FaceGeometry] {
        log.calls += 1
        return try result.get()
    }
}

/// 스테이징 호출 횟수. 값 타입인 FakeImporter가 복사돼도 같은 기록을 공유한다.
final class StagingLog: @unchecked Sendable {
    var calls = 0
}

struct FakeImporter: PhotoImporter {
    var staged: [Result<StagedPhoto, Error>] = []
    /// true면 `staged` 대신 받은 파일 URL을 그대로 스테이징 결과로 돌려준다. 여러 번 가져오기 테스트용.
    var passesThroughFileURLs = false
    var log = StagingLog()
    func stage(_ items: [PhotosPickerItem]) async -> [Result<StagedPhoto, Error>] {
        log.calls += 1
        return staged
    }
    func stage(fileURLs: [URL]) async -> [Result<StagedPhoto, Error>] {
        log.calls += 1
        guard passesThroughFileURLs else { return staged }
        return fileURLs.map {
            .success(StagedPhoto(url: $0, displayName: $0.deletingPathExtension().lastPathComponent))
        }
    }
}

final class RecordingDestination: ExportDestination, @unchecked Sendable {
    var published: [(name: String, bytes: Int)] = []
    var failOnNames: Set<String> = []
    var delayNanoseconds: UInt64 = 0

    func publish(fileURL: URL, suggestedName: String) async throws {
        if delayNanoseconds > 0 { try await Task.sleep(nanoseconds: delayNanoseconds) }
        if failOnNames.contains(suggestedName) { throw MellowError.exportFailed(reason: "test") }
        published.append((suggestedName, try Data(contentsOf: fileURL).count))
    }
}

enum TestSupport {
    static func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// 단색 PNG를 임시 폴더에 쓴다. 가져오기 테스트의 "선택된 사진" 역할.
    static func solidPNG(in directory: URL, name: String = UUID().uuidString, size: Int = 128) throws -> URL {
        let url = directory.appendingPathComponent("\(name).png")
        let image = CIImage(color: CIColor(red: 0.5, green: 0.4, blue: 0.3)).cropped(
            to: CGRect(x: 0, y: 0, width: size, height: size))
        let cg = try Renderer().makeCGImage(image)
        let destination = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil)!
        CGImageDestinationAddImage(destination, cg, nil)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        return url
    }

    /// 저장소의 공용 룩 카탈로그. 앱 번들과 같은 파일이다.
    static func sharedLookCatalog() throws -> LookCatalog {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("shared/looks/looks.v1.json")
        return try LookCatalog(data: Data(contentsOf: url))
    }

    @MainActor
    static func makeModel(
        root: URL, maxPhotos: Int = 40, analyzer: StubFaceAnalyzer = StubFaceAnalyzer(),
        importer: FakeImporter = FakeImporter(), store: MemorySessionStore = MemorySessionStore()
    ) -> AppModel {
        let copies = WorkingCopyStore(directory: root.appendingPathComponent("Library"))
        try? copies.prepareDirectory()
        let catalog = (try? sharedLookCatalog()) ?? .empty
        return AppModel(
            session: ProjectSession(store: store, maxPhotos: maxPhotos),
            pipeline: PhotoPipeline(analyzer: analyzer, tuning: RenderTuning(), lookCatalog: catalog),
            copies: copies,
            importer: importer,
            exporter: Exporter(renderer: Renderer()),
            lookCatalog: catalog,
            renderDebounce: .milliseconds(10))
    }
}
