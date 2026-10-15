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

    func testEditingStillRendersAfterImportsEvictPreviewCache() async throws {
        let files = try ["A", "B", "C", "D"].map { try TestSupport.solidPNG(in: root, name: $0) }
        let model = TestSupport.makeModel(root: root, importer: FakeImporter(passesThroughFileURLs: true))
        await model.importFromFiles([files[0]])
        try await waitUntil { model.isReady && model.preview != nil }
        let selected = model.session.selectedPhotoID
        await model.importFromFiles(Array(files[1...]))
        try await waitUntil { !model.isImporting }
        XCTAssertEqual(model.session.photos.count, 4)
        XCTAssertEqual(model.session.selectedPhotoID, selected, "새로 가져와도 선택은 그대로다")
        model.edit(.exposure(0.5))
        try await waitUntil { !model.isRendering }
        XCTAssertNil(model.presentedError, "미리보기 캐시에서 밀려난 사진도 편집 렌더가 실패하지 않는다")
        XCTAssertNotNil(model.preview)
        XCTAssertEqual(model.currentRecipe.color.exposure, 0.5)
        XCTAssertEqual(model.thumbnails.count, 4)
    }

    func testImportIsRejectedWhileBusyWithoutLeakingStagedFiles() async throws {
        let staged = try TestSupport.solidPNG(in: root)
        let importer = FakeImporter(passesThroughFileURLs: true)
        let model = TestSupport.makeModel(root: root, importer: importer)
        model.isExporting = true
        await model.importFromFiles([staged])
        XCTAssertTrue(model.session.photos.isEmpty)
        XCTAssertFalse(model.isImporting)
        // 바쁜 상태는 스테이징 전에 거부하므로 임시 파일이 만들어지지 않는다. 원본은 그대로다.
        XCTAssertEqual(importer.log.calls, 0, "바쁠 때는 스테이징 자체를 하지 않는다")
        XCTAssertTrue(FileManager.default.fileExists(atPath: staged.path))
        let library = model.copies.directory.path
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: library), [])
    }

    func testStopWorkClearsRenderingFlagAndResumeRerenders() async throws {
        let staged = try TestSupport.solidPNG(in: root)
        let model = TestSupport.makeModel(root: root, importer: FakeImporter(passesThroughFileURLs: true))
        await model.importFromFiles([staged])
        try await waitUntil { model.isReady && model.preview != nil }
        let before = try XCTUnwrap(model.preview)
        model.edit(.exposure(0.5))
        XCTAssertTrue(model.isRendering)
        model.stopWork()
        XCTAssertFalse(model.isRendering, "취소된 렌더가 진행 표시를 남기지 않는다")
        model.resumeWork()
        XCTAssertTrue(model.isRendering)
        try await waitUntil { !model.isRendering }
        XCTAssertNil(model.presentedError)
        XCTAssertFalse(model.preview === before, "재개하면 편집을 반영해 다시 렌더한다")
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

    func testRestoreRunsOnlyOnceAndKeepsSelection() async throws {
        let store = MemorySessionStore()
        let copies = WorkingCopyStore(directory: root.appendingPathComponent("Library"))
        try copies.prepareDirectory()
        let first = PhotoID()
        let second = PhotoID()
        let firstName = try copies.adopt(temporaryFile: try TestSupport.solidPNG(in: root), as: first)
        let secondName = try copies.adopt(temporaryFile: try TestSupport.solidPNG(in: root), as: second)
        store.saved = SessionSnapshot(
            photos: [
                PhotoEntry(id: first, filename: firstName, displayName: "A"),
                PhotoEntry(id: second, filename: secondName, displayName: "B"),
            ],
            selectedPhotoID: first, presets: [])
        let analyzer = StubFaceAnalyzer()
        let model = TestSupport.makeModel(root: root, analyzer: analyzer, store: store)
        await model.restore()
        try await waitUntil { model.isReady && model.preview != nil }
        model.select(second)
        try await waitUntil { model.isReady && model.preview != nil }
        let preview = try XCTUnwrap(model.preview)
        let analyzed = analyzer.log.calls
        XCTAssertEqual(analyzed, 2, "사진마다 한 번씩 준비한다")
        // 새 창을 열면 화면의 .task가 다시 restore()를 부른다.
        await model.restore()
        XCTAssertEqual(analyzer.log.calls, analyzed, "두 번째 restore는 사진을 다시 준비하지 않는다")
        XCTAssertEqual(model.session.selectedPhotoID, second)
        XCTAssertTrue(model.isReady)
        XCTAssertTrue(model.preview === preview, "선택과 미리보기를 초기화하지 않는다")
    }

    func testSavedPresetNeverCarriesTargetFace() async throws {
        let staged = try TestSupport.solidPNG(in: root)
        let model = TestSupport.makeModel(
            root: root, importer: FakeImporter(staged: [.success(StagedPhoto(url: staged, displayName: nil))]))
        await model.importFromFiles([staged])
        try await waitUntil { model.isReady && model.preview != nil }
        model.edit(.faceSlim(0.4))
        model.edit(.targetFace(1))
        XCTAssertEqual(model.currentRecipe.portrait.targetFace, 1)
        model.savePreset(named: "대상 얼굴")
        let saved = try XCTUnwrap(model.session.presets.last)
        XCTAssertNil(saved.values.portrait.targetFace, "프리셋은 얼굴을 고르지 않는다")
        XCTAssertEqual(saved.values.portrait.faceSlim, 0.4)
    }

    func testSliderDragSavesSessionOnceAtEnd() async throws {
        let staged = try TestSupport.solidPNG(in: root)
        let store = MemorySessionStore()
        let model = TestSupport.makeModel(
            root: root, importer: FakeImporter(staged: [.success(StagedPhoto(url: staged, displayName: nil))]),
            store: store)
        await model.importFromFiles([staged])
        try await waitUntil { model.isReady && model.preview != nil }
        let before = store.saveCount
        model.beginSliderEdit()
        model.edit(.exposure(0.1))
        model.edit(.exposure(0.2))
        model.edit(.exposure(0.3))
        XCTAssertEqual(store.saveCount, before, "드래그 중에는 세션을 쓰지 않는다")
        model.endSliderEdit()
        XCTAssertEqual(store.saveCount, before + 1, "드래그가 끝날 때 한 번 저장한다")
        XCTAssertEqual(store.saved?.photos.first?.document.recipe.color.exposure, 0.3)
    }

    func testLegacyPresetImportRunsAfterSessionRestoreAndKeepsPhotos() async throws {
        let store = MemorySessionStore()
        let copies = WorkingCopyStore(directory: root.appendingPathComponent("Library"))
        try copies.prepareDirectory()
        let id = PhotoID()
        let filename = try copies.adopt(temporaryFile: try TestSupport.solidPNG(in: root), as: id)
        store.saved = SessionSnapshot(
            photos: [PhotoEntry(id: id, filename: filename, displayName: "복원")], selectedPhotoID: id, presets: [])
        let model = TestSupport.makeModel(root: root, store: store)
        model.afterSessionRestored = { $0.addPreset(named: "옛날", values: PresetValues()) }
        await model.restore()
        XCTAssertEqual(model.session.photos.count, 1)
        XCTAssertEqual(model.session.presets.map(\.name), ["옛날"])
        XCTAssertEqual(store.saved?.photos.map(\.id), [id], "프리셋 흡수가 저장된 사진 목록을 덮어쓰면 안 된다")
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

    func testSelectingAnotherPhotoSavesOnceNotTwice() async throws {
        let first = try TestSupport.solidPNG(in: root, name: "A")
        let second = try TestSupport.solidPNG(in: root, name: "B")
        let store = MemorySessionStore()
        let importer = FakeImporter(staged: [
            .success(StagedPhoto(url: first, displayName: "A")), .success(StagedPhoto(url: second, displayName: "B")),
        ])
        let model = TestSupport.makeModel(root: root, importer: importer, store: store)
        await model.importFromFiles([first, second])
        try await waitUntil { model.isReady }
        let before = store.saveCount
        model.select(model.session.photos[1].id)
        XCTAssertEqual(store.saveCount, before + 1, "선택 변경은 세션을 한 번만 저장한다")
    }

    func testFlushPendingEditsSavesOpenDrag() async throws {
        let staged = try TestSupport.solidPNG(in: root)
        let store = MemorySessionStore()
        let model = TestSupport.makeModel(
            root: root, importer: FakeImporter(staged: [.success(StagedPhoto(url: staged, displayName: nil))]),
            store: store)
        await model.importFromFiles([staged])
        try await waitUntil { model.isReady && model.preview != nil }
        model.beginSliderEdit()
        model.edit(.exposure(0.5))
        let before = store.saveCount
        model.flushPendingEdits()
        XCTAssertEqual(store.saveCount, before + 1)
        XCTAssertEqual(store.saved?.photos.first?.document.recipe.color.exposure, 0.5)
        XCTAssertFalse(model.session.isPersistenceDeferred)
    }
}
