import MellowLibrary
import MellowRendering
import MellowShared
import XCTest

@testable import Mellow_Photo

@MainActor
final class ImportPhotosTests: XCTestCase {
    private var root: URL!
    private var copies: WorkingCopyStore!
    private var session: ProjectSession!
    private var pipeline: PhotoPipeline!

    override func setUp() async throws {
        root = try TestSupport.temporaryDirectory()
        copies = WorkingCopyStore(directory: root.appendingPathComponent("Library"))
        try copies.prepareDirectory()
        session = ProjectSession(store: MemorySessionStore(), maxPhotos: 2)
        pipeline = PhotoPipeline(analyzer: StubFaceAnalyzer(), tuning: RenderTuning())
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: root)
    }

    private func useCase() -> ImportPhotos {
        ImportPhotos(session: session, pipeline: pipeline, copies: copies)
    }

    func testImportMovesCopyPreparesAndAddsToSession() async throws {
        let staged = try TestSupport.solidPNG(in: root, name: "IMG_1")
        let report = await useCase().run(staged: [.success(StagedPhoto(url: staged, displayName: "IMG_1"))]) { _, _ in }
        XCTAssertEqual(report.added.count, 1)
        XCTAssertTrue(report.failures.isEmpty)
        XCTAssertEqual(session.photos.count, 1)
        XCTAssertEqual(session.photos[0].displayName, "IMG_1")
        XCTAssertFalse(FileManager.default.fileExists(atPath: staged.path), "임시 파일은 사본으로 이동된다")
        XCTAssertTrue(FileManager.default.fileExists(atPath: copies.url(for: session.photos[0].filename).path))
        XCTAssertEqual(report.added[0].prepared.pixelSize, CGSize(width: 128, height: 128))
    }

    func testImportStopsAtCapacityAndReportsSkipped() async throws {
        let files = try (1...3).map { try TestSupport.solidPNG(in: root, name: "IMG_\($0)") }
        let staged = files.map { Result<StagedPhoto, Error>.success(StagedPhoto(url: $0, displayName: nil)) }
        let report = await useCase().run(staged: staged) { _, _ in }
        XCTAssertEqual(report.added.count, 2)
        XCTAssertEqual(report.skippedForCapacity, 1)
        XCTAssertEqual(session.photos.map(\.displayName), ["사진 1", "사진 2"])
        XCTAssertFalse(FileManager.default.fileExists(atPath: files[2].path), "건너뛴 임시 파일도 정리한다")
    }

    func testBrokenFileIsReportedAndCopyIsRemoved() async throws {
        let broken = root.appendingPathComponent("broken.png")
        try Data([0, 1, 2]).write(to: broken)
        let report = await useCase().run(staged: [.success(StagedPhoto(url: broken, displayName: nil))]) { _, _ in }
        XCTAssertEqual(report.failures.count, 1)
        XCTAssertEqual(report.failures[0].stage, .prepare)
        XCTAssertTrue(session.photos.isEmpty)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: copies.directory.path), [], "실패한 사본은 남지 않는다")
    }

    func testStagingFailureIsReportedWithStage() async throws {
        let report = await useCase().run(staged: [.failure(MellowError.cannotOpenPhoto(filename: "x"))]) { _, _ in }
        XCTAssertEqual(report.failures.first?.stage, .stage)
    }

    func testFaceAnalysisFailureBecomesWarningNotFailure() async throws {
        pipeline = PhotoPipeline(
            analyzer: StubFaceAnalyzer(result: .failure(.faceAnalysisUnavailable(reason: "test"))),
            tuning: RenderTuning())
        let staged = try TestSupport.solidPNG(in: root)
        let report = await useCase().run(staged: [.success(StagedPhoto(url: staged, displayName: nil))]) { _, _ in }
        XCTAssertEqual(report.added.count, 1)
        XCTAssertEqual(report.warnings.count, 1)
    }
}
