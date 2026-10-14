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
    func load() throws -> SessionSnapshot? { saved }
    func save(_ snapshot: SessionSnapshot) throws { saved = snapshot }
}

struct StubFaceAnalyzer: FaceAnalyzer {
    var result: Result<[FaceGeometry], MellowError> = .success([])
    func analyze(_ image: CIImage) throws -> [FaceGeometry] { try result.get() }
}

struct FakeImporter: PhotoImporter {
    var staged: [Result<StagedPhoto, Error>] = []
    func stage(_ items: [PhotosPickerItem]) async -> [Result<StagedPhoto, Error>] { staged }
    func stage(fileURLs: [URL]) async -> [Result<StagedPhoto, Error>] { staged }
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

    @MainActor
    static func makeModel(
        root: URL, maxPhotos: Int = 40, analyzer: StubFaceAnalyzer = StubFaceAnalyzer(),
        importer: FakeImporter = FakeImporter(), store: MemorySessionStore = MemorySessionStore()
    ) -> AppModel {
        let copies = WorkingCopyStore(directory: root.appendingPathComponent("Library"))
        try? copies.prepareDirectory()
        return AppModel(
            session: ProjectSession(store: store, maxPhotos: maxPhotos),
            pipeline: PhotoPipeline(analyzer: analyzer, tuning: RenderTuning()),
            copies: copies,
            importer: importer,
            exporter: Exporter(renderer: Renderer()),
            renderDebounce: .milliseconds(10))
    }
}
