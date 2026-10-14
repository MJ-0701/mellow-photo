import MellowEditing
import MellowExport
import MellowLibrary
import MellowRendering
import MellowShared
import XCTest

@testable import Mellow_Photo

@MainActor
final class AppModelTests: XCTestCase {
    private var root: URL!

    override func setUp() async throws {
        root = try TestSupport.temporaryDirectory()
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: root)
    }

    private func waitUntil(_ condition: @escaping () -> Bool, timeout: TimeInterval = 5) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() && Date() < deadline {
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        XCTAssertTrue(condition())
    }

    func testImportSelectsFirstPhotoAndRendersPreview() async throws {
        let staged = try TestSupport.solidPNG(in: root, name: "IMG_1")
        let model = TestSupport.makeModel(
            root: root, importer: FakeImporter(staged: [.success(StagedPhoto(url: staged, displayName: "IMG_1"))]))
        await model.importFromFiles([staged])
        XCTAssertEqual(model.session.photos.count, 1)
        XCTAssertNotNil(model.thumbnails[model.session.photos[0].id])
        try await waitUntil { model.isReady && model.preview != nil }
        XCTAssertEqual(model.statusMessage, "1장 · 편집 기록은 이 기기에 저장됩니다.")
    }

    func testSliderEditUpdatesRecipeAndRerenders() async throws {
        let staged = try TestSupport.solidPNG(in: root)
        let model = TestSupport.makeModel(
            root: root, importer: FakeImporter(staged: [.success(StagedPhoto(url: staged, displayName: nil))]))
        await model.importFromFiles([staged])
        try await waitUntil { model.isReady && model.preview != nil }
        model.beginSliderEdit()
        model.edit(.exposure(0.5))
        model.edit(.exposure(0.6))
        model.endSliderEdit()
        XCTAssertEqual(model.currentRecipe.color.exposure, 0.6)
        XCTAssertEqual(model.session.selected?.document.undoStack.count, 1)
        XCTAssertTrue(model.canUndo)
        model.undo()
        XCTAssertEqual(model.currentRecipe.color.exposure, 0)
    }

    func testGeometryLockShowsStatusInsteadOfChanging() async throws {
        let staged = try TestSupport.solidPNG(in: root)
        let model = TestSupport.makeModel(
            root: root, importer: FakeImporter(staged: [.success(StagedPhoto(url: staged, displayName: nil))]))
        await model.importFromFiles([staged])
        try await waitUntil { model.isReady && model.preview != nil }
        model.edit(.faceSlim(0.2))
        try await waitUntil { !model.isRendering }
        model.tool = .retouch
        model.touch(from: NormalizedPoint(x: 0.3, y: 0.3), to: NormalizedPoint(x: 0.3, y: 0.3))
        XCTAssertFalse(model.isChoosingCloneSource)
        model.touch(from: NormalizedPoint(x: 0.5, y: 0.5), to: NormalizedPoint(x: 0.5, y: 0.5))
        XCTAssertEqual(model.currentRecipe.operations.count, 1)
        try await waitUntil { !model.isRendering }
        model.edit(.faceSlim(0.9))
        XCTAssertEqual(model.currentRecipe.portrait.faceSlim, 0.2)
        XCTAssertEqual(model.statusMessage, UserMessage.geometryLocked)
    }

    func testRemoveSelectedDeletesWorkingCopyAndSelectsNext() async throws {
        let first = try TestSupport.solidPNG(in: root, name: "A")
        let second = try TestSupport.solidPNG(in: root, name: "B")
        let importer = FakeImporter(staged: [
            .success(StagedPhoto(url: first, displayName: "A")), .success(StagedPhoto(url: second, displayName: "B")),
        ])
        let model = TestSupport.makeModel(root: root, importer: importer)
        await model.importFromFiles([first, second])
        let removed = try XCTUnwrap(model.session.photos.first)
        model.removeSelectedPhoto()
        XCTAssertEqual(model.session.photos.map(\.displayName), ["B"])
        XCTAssertEqual(model.session.selectedPhotoID, model.session.photos[0].id)
        XCTAssertFalse(FileManager.default.fileExists(atPath: model.copies.url(for: removed.filename).path))
        XCTAssertNil(model.thumbnails[removed.id])
    }

    func testRestoreRebuildsThumbnailsFromSession() async throws {
        let store = MemorySessionStore()
        let copies = WorkingCopyStore(directory: root.appendingPathComponent("Library"))
        try copies.prepareDirectory()
        let id = PhotoID()
        let filename = try copies.adopt(temporaryFile: try TestSupport.solidPNG(in: root), as: id)
        store.saved = SessionSnapshot(
            photos: [PhotoEntry(id: id, filename: filename, displayName: "복원")], selectedPhotoID: id, presets: [])
        let model = TestSupport.makeModel(root: root, store: store)
        await model.restore()
        XCTAssertNotNil(model.thumbnails[id])
        try await waitUntil { model.isReady }
        XCTAssertEqual(model.session.selectedPhotoID, id)
    }

    func testRestoreWithUnreadableSessionKeepsAppUsable() async throws {
        let store = JSONSessionStore(fileURL: root.appendingPathComponent("session.json"))
        try Data("{ broken".utf8).write(to: store.fileURL)
        let copies = WorkingCopyStore(directory: root.appendingPathComponent("Library"))
        try copies.prepareDirectory()
        let model = AppModel(
            session: ProjectSession(store: store, maxPhotos: 40),
            pipeline: PhotoPipeline(analyzer: StubFaceAnalyzer(), tuning: RenderTuning()),
            copies: copies, importer: FakeImporter(), exporter: Exporter(renderer: Renderer()),
            renderDebounce: .milliseconds(10))
        await model.restore()
        XCTAssertNotNil(model.presentedError)
        XCTAssertNotNil(store.recoveryFileURL)
        XCTAssertFalse(model.isBusy)
    }
}
