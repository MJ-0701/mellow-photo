import MellowEditing
import MellowExport
import MellowLibrary
import MellowRendering
import MellowShared
import XCTest

@testable import Mellow_Photo

@MainActor
final class ExportPhotosTests: XCTestCase {
    private var root: URL!
    private var copies: WorkingCopyStore!
    private var pipeline: PhotoPipeline!

    override func setUp() async throws {
        root = try TestSupport.temporaryDirectory()
        copies = WorkingCopyStore(directory: root.appendingPathComponent("Library"))
        try copies.prepareDirectory()
        pipeline = PhotoPipeline(analyzer: StubFaceAnalyzer(), tuning: RenderTuning())
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: root)
    }

    private func entry(named name: String, recipe: EditRecipe = EditRecipe()) async throws -> PhotoEntry {
        let id = PhotoID()
        let filename = try copies.adopt(temporaryFile: try TestSupport.solidPNG(in: root, name: name), as: id)
        _ = try await pipeline.prepare(id, at: copies.url(for: filename))
        return PhotoEntry(id: id, filename: filename, displayName: name, document: EditDocument(recipe: recipe))
    }

    private func useCase() -> ExportPhotos {
        ExportPhotos(
            pipeline: pipeline, copies: copies, exporter: Exporter(renderer: Renderer()), temporaryDirectory: root)
    }

    /// 테스트 전용 임시 폴더만 본다. 다른 프로세스가 시스템 임시 폴더에 남긴 파일과 섞이지 않는다.
    private func temporaryExports() throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: root.path).filter { $0.hasPrefix("mellow-export-") }
    }

    func testExportPublishesEachPhotoAndReportsFailures() async throws {
        let a = try await entry(named: "A")
        let b = try await entry(named: "B")
        let destination = RecordingDestination()
        destination.failOnNames = ["B_mellow"]
        var progress: [Double] = []
        let report = await useCase().run(
            entries: [a, b], options: ExportOptions(format: .jpeg), destination: destination
        ) { progress.append($0) }
        XCTAssertEqual(report.saved, 1)
        XCTAssertEqual(report.failures.count, 1)
        XCTAssertEqual(destination.published.map(\.name), ["A_mellow"])
        XCTAssertGreaterThan(destination.published[0].bytes, 0)
        XCTAssertEqual(progress, [0.5, 1.0])
        XCTAssertEqual(try temporaryExports(), [])
    }

    func testCancelledExportCleansTemporaryFilesAndCanRunAgain() async throws {
        let entries = try await [entry(named: "A"), entry(named: "B"), entry(named: "C")]
        let destination = RecordingDestination()
        destination.delayNanoseconds = 150_000_000
        let useCase = useCase()
        let task = Task {
            await useCase.run(entries: entries, options: ExportOptions(), destination: destination) { _ in }
        }
        try await Task.sleep(nanoseconds: 50_000_000)
        task.cancel()
        let report = await task.value
        XCTAssertTrue(report.cancelled)
        XCTAssertLessThan(report.saved, 3)
        XCTAssertEqual(try temporaryExports(), [])
        destination.delayNanoseconds = 0
        let second = await useCase.run(entries: entries, options: ExportOptions(), destination: destination) { _ in }
        XCTAssertEqual(second.saved, 3)
        XCTAssertFalse(second.cancelled)
    }

    func testFaceEditsWithFailedAnalysisAreRefused() async throws {
        pipeline = PhotoPipeline(
            analyzer: StubFaceAnalyzer(result: .failure(.faceAnalysisUnavailable(reason: "test"))),
            tuning: RenderTuning())
        var recipe = EditRecipe()
        recipe.portrait.skinSmoothing = 0.3
        let photo = try await entry(named: "A", recipe: recipe)
        let destination = RecordingDestination()
        let report = await useCase().run(entries: [photo], options: ExportOptions(), destination: destination) { _ in }
        XCTAssertEqual(report.saved, 0)
        XCTAssertEqual(report.failures.first?.error, .faceAnalysisUnavailable(reason: "test"))
        XCTAssertTrue(destination.published.isEmpty)
    }
}
