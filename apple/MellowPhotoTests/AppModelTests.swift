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
        model.edit(.faceShape(.width, -0.2))
        try await waitUntil { !model.isRendering }
        model.tool = .retouch
        model.touch(from: NormalizedPoint(x: 0.3, y: 0.3), to: NormalizedPoint(x: 0.3, y: 0.3))
        XCTAssertFalse(model.isChoosingCloneSource)
        model.touch(from: NormalizedPoint(x: 0.5, y: 0.5), to: NormalizedPoint(x: 0.5, y: 0.5))
        XCTAssertEqual(model.currentRecipe.operations.count, 1)
        try await waitUntil { !model.isRendering }
        model.edit(.faceShape(.width, -0.9))
        XCTAssertEqual(model.currentRecipe.portrait.face.width, -0.2)
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

    func testReprepareAfterEvictionRefreshesPhotoInfo() async throws {
        let files = try ["A", "B", "C", "D"].map { try TestSupport.solidPNG(in: root, name: $0) }
        let failure = MellowError.personAnalysisUnavailable(reason: "first")
        let mask = TestSupport.personMask(NormalizedRect(x: 0.3, y: 0, width: 0.4, height: 0.8))
        let queue = PersonResultQueue([.failure(failure), .success(mask)])
        let model = TestSupport.makeModel(
            root: root, personAnalyzer: StubPersonAnalyzer(queue: queue),
            importer: FakeImporter(passesThroughFileURLs: true))
        await model.importFromFiles([files[0]])
        try await waitUntil { model.isReady && model.preview != nil }
        let first = try XCTUnwrap(model.session.selectedPhotoID)
        XCTAssertEqual(model.backgroundAvailability, .unavailable(failure), "첫 준비의 인물 분석은 실패한다")
        await model.importFromFiles(Array(files[1...]))
        try await waitUntil { !model.isImporting }
        XCTAssertEqual(queue.calls, 4, "사진마다 한 번씩 분석한다")
        model.select(first)
        try await waitUntil { model.isReady && model.preview != nil }
        XCTAssertEqual(queue.calls, 5, "밀려난 첫 사진을 다시 준비하며 다시 분석한다")
        XCTAssertNil(model.photoInfo[first]?.personAnalysisFailure, "다시 준비한 분석이 이전 실패를 지운다")
        XCTAssertEqual(model.backgroundAvailability, .ready)
        XCTAssertNil(model.presentedError)
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
        model.edit(.faceShape(.width, -0.4))
        model.edit(.targetFace(1))
        XCTAssertEqual(model.currentRecipe.portrait.targetFace, 1)
        model.savePreset(named: "대상 얼굴")
        let saved = try XCTUnwrap(model.session.presets.last)
        XCTAssertNil(saved.values.portrait.targetFace, "프리셋은 얼굴을 고르지 않는다")
        XCTAssertEqual(saved.values.portrait.face.width, -0.4)
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

    func testAdjustToolEditsEffectsOneUndoStepEach() async throws {
        let staged = try TestSupport.solidPNG(in: root)
        let model = TestSupport.makeModel(
            root: root, importer: FakeImporter(staged: [.success(StagedPhoto(url: staged, displayName: nil))]))
        try await importOne(model, staged)
        model.selectTool(.adjust)
        for (offset, key) in EffectKey.allCases.enumerated() {
            model.beginSliderEdit()
            model.edit(.effect(key, 0.2))
            model.edit(.effect(key, 0.6))
            model.endSliderEdit()
            XCTAssertEqual(model.session.selected?.document.undoStack.count, offset + 1, "\(key)")
        }
        XCTAssertEqual(model.currentRecipe.effects, EffectAdjustments(grain: 0.6, glow: 0.6))
        try await waitUntil { !model.isRendering }
        XCTAssertNil(model.presentedError)
        XCTAssertEqual(EffectKey.allCases.map(UserMessage.effectTitle), ["그레인", "글로우"])
        model.undo()
        XCTAssertEqual(model.currentRecipe.effects, EffectAdjustments(grain: 0.6))
    }

    private func importOne(_ model: AppModel, _ url: URL) async throws {
        await model.importFromFiles([url])
        try await waitUntil { model.isReady && model.preview != nil }
    }

    func testAutoEnhanceIsOneUndoStepAndIdempotent() async throws {
        let staged = try TestSupport.solidPNG(in: root)
        let model = TestSupport.makeModel(
            root: root, importer: FakeImporter(staged: [.success(StagedPhoto(url: staged, displayName: nil))]))
        try await importOne(model, staged)
        await model.autoEnhance()
        let first = model.currentRecipe
        XCTAssertNotEqual(first, EditRecipe())
        XCTAssertEqual(model.session.selected?.document.undoStack.count, 1)
        await model.autoEnhance()
        XCTAssertEqual(model.currentRecipe, first, "두 번 눌러도 누적되지 않는다")
        XCTAssertEqual(model.session.selected?.document.undoStack.count, 1, "연타해도 실행 취소 단계는 하나")
        model.undo()
        XCTAssertTrue(model.currentRecipe.isDefault, "⌘Z 한 번에 자동 보정 전으로 돌아간다")
        XCTAssertFalse(model.canUndo)
    }

    func testCropToolShowsUncroppedPreview() async throws {
        let staged = try TestSupport.solidPNG(in: root, size: 200)
        let model = TestSupport.makeModel(
            root: root, importer: FakeImporter(staged: [.success(StagedPhoto(url: staged, displayName: nil))]))
        try await importOne(model, staged)
        model.edit(.crop(NormalizedRect(x: 0, y: 0, width: 0.5, height: 0.5)))
        try await waitUntil { !model.isRendering }
        XCTAssertEqual(model.preview?.width, 100)
        model.selectTool(.crop)
        try await waitUntil { !model.isRendering && model.preview?.width == 200 }
        XCTAssertTrue(model.canvasShowsUncropped)
        model.selectTool(.adjust)
        try await waitUntil { !model.isRendering && model.preview?.width == 100 }
    }

    func testRetouchTapWhileCroppedIsStoredInOriginalCoordinates() async throws {
        let staged = try TestSupport.solidPNG(in: root, size: 200)
        let model = TestSupport.makeModel(
            root: root, importer: FakeImporter(staged: [.success(StagedPhoto(url: staged, displayName: nil))]))
        try await importOne(model, staged)
        // 비대칭 자르기와 x ≠ y인 탭으로 축이 뒤바뀌거나 y가 뒤집히는 실수를 잡는다.
        let crop = NormalizedRect(x: 0.1, y: 0.4, width: 0.6, height: 0.5)
        model.edit(.crop(crop))
        try await waitUntil { !model.isRendering }
        model.selectTool(.retouch)
        let transform = GeometryTransform(geometry: model.currentRecipe.geometry, sourceAspect: 1)
        let sourceTap = NormalizedPoint(x: 0.5, y: 0.8)
        let expectedSource = transform.toOriginal(sourceTap)
        XCTAssertEqual(expectedSource.x, 0.4, accuracy: 1e-9)
        XCTAssertEqual(expectedSource.y, 0.8, accuracy: 1e-9)
        model.touch(from: sourceTap, to: sourceTap)
        let source = try XCTUnwrap(model.cloneSource)
        XCTAssertEqual(source.x, expectedSource.x, accuracy: 1e-9)
        XCTAssertEqual(source.y, expectedSource.y, accuracy: 1e-9)
        let marker = try XCTUnwrap(model.cloneSourceOnCanvas)
        XCTAssertEqual(marker.x, sourceTap.x, accuracy: 1e-9)
        XCTAssertEqual(marker.y, sourceTap.y, accuracy: 1e-9)
        let targetTap = NormalizedPoint(x: 0.2, y: 0.6)
        let expectedTarget = transform.toOriginal(targetTap)
        XCTAssertEqual(expectedTarget.x, 0.22, accuracy: 1e-9)
        XCTAssertEqual(expectedTarget.y, 0.7, accuracy: 1e-9)
        model.touch(from: targetTap, to: targetTap)
        let spot = try XCTUnwrap(model.currentRecipe.spots.first)
        XCTAssertEqual(spot.x, expectedTarget.x, accuracy: 1e-9)
        XCTAssertEqual(spot.y, expectedTarget.y, accuracy: 1e-9)
        XCTAssertEqual(spot.sourceX, expectedSource.x, accuracy: 1e-9)
        XCTAssertEqual(spot.sourceY, expectedSource.y, accuracy: 1e-9)
    }

    func testLookThumbnailsIgnoreStaleResults() async throws {
        let first = try TestSupport.solidPNG(in: root, name: "A", size: 300)
        let second = try TestSupport.solidPNG(in: root, name: "B", size: 300)
        let importer = FakeImporter(staged: [
            .success(StagedPhoto(url: first, displayName: "A")), .success(StagedPhoto(url: second, displayName: "B")),
        ])
        let model = TestSupport.makeModel(root: root, importer: importer)
        await model.importFromFiles([first, second])
        try await waitUntil { model.isReady }
        let a = model.session.photos[0].id
        let b = model.session.photos[1].id
        model.selectTool(.look)
        model.select(b)
        try await waitUntil { model.lookThumbnails[a]?.count == 10 || model.lookThumbnails[b]?.count == 10 }
        try await waitUntil { model.lookThumbnails[b]?.count == 10 }
        XCTAssertNotNil(model.lookThumbnails[b]?["mono"])
        if let aThumbs = model.lookThumbnails[a] {
            XCTAssertEqual(aThumbs.count, 10, "A의 결과가 왔다면 A 키 아래에만 있다")
        }
    }

    func testCropAspectSetsCenteredRectAndResetGeometryIsOneUndoStep() async throws {
        let staged = try TestSupport.solidPNG(in: root, size: 200)
        let model = TestSupport.makeModel(
            root: root, importer: FakeImporter(staged: [.success(StagedPhoto(url: staged, displayName: nil))]))
        try await importOne(model, staged)
        model.setCropAspect(.square)
        XCTAssertEqual(model.currentRecipe.geometry.crop, NormalizedRect(x: 0, y: 0, width: 1, height: 1))
        model.edit(.quarterTurns(1))
        model.setCropAspect(.nineSixteen)
        let crop = try XCTUnwrap(model.currentRecipe.geometry.crop)
        XCTAssertEqual(crop.width, 9.0 / 16.0, accuracy: 1e-9)
        XCTAssertEqual(crop.x, (1 - 9.0 / 16.0) / 2, accuracy: 1e-9)
        let before = model.session.selected?.document.undoStack.count ?? 0
        model.resetGeometry()
        XCTAssertTrue(model.currentRecipe.geometry.isIdentity)
        XCTAssertEqual(model.session.selected?.document.undoStack.count, before + 1)
    }

    func testTurnClearsNonSquareAspectAndKeepsSquare() async throws {
        let staged = try TestSupport.solidPNG(in: root, size: 200)
        let model = TestSupport.makeModel(
            root: root, importer: FakeImporter(staged: [.success(StagedPhoto(url: staged, displayName: nil))]))
        try await importOne(model, staged)
        model.selectTool(.crop)
        model.setCropAspect(.fourFive)
        model.turnClockwise()
        XCTAssertEqual(model.currentRecipe.geometry.quarterTurns, 1)
        XCTAssertNil(model.cropAspect, "돌린 4:5는 5:4라 비율 선택을 비운다")
        let transform = GeometryTransform(geometry: model.currentRecipe.geometry, sourceAspect: 1)
        XCTAssertEqual(transform.outputAspect, 5.0 / 4.0, accuracy: 1e-9)
        model.setCropAspect(.square)
        model.turnClockwise()
        XCTAssertEqual(model.cropAspect, .square)
        model.setCropAspect(.original)
        model.turnClockwise()
        XCTAssertEqual(model.cropAspect, .original)
    }

    func testUndoAndRedoClearCropAspect() async throws {
        let staged = try TestSupport.solidPNG(in: root, size: 200)
        let model = TestSupport.makeModel(
            root: root, importer: FakeImporter(staged: [.success(StagedPhoto(url: staged, displayName: nil))]))
        try await importOne(model, staged)
        model.selectTool(.crop)
        model.setCropAspect(.nineSixteen)
        model.undo()
        XCTAssertNil(model.cropAspect, "되돌린 자르기는 9:16이 아니다")
        model.setCropAspect(.square)
        model.redo()
        XCTAssertNil(model.cropAspect)
    }

    func testCropDragIsOneUndoStepAndRendersOnlyAtEnd() async throws {
        let staged = try TestSupport.solidPNG(in: root, size: 200)
        let model = TestSupport.makeModel(
            root: root, importer: FakeImporter(staged: [.success(StagedPhoto(url: staged, displayName: nil))]))
        try await importOne(model, staged)
        model.selectTool(.crop)
        try await waitUntil { !model.isRendering }
        let before = model.session.selected?.document.undoStack.count ?? 0
        model.beginCropDrag()
        for width in [0.9, 0.8, 0.7] {
            model.edit(.crop(NormalizedRect(x: 0, y: 0, width: width, height: width)))
            XCTAssertFalse(model.isRendering, "자르기 전 화면은 드래그 중에 바뀌지 않으므로 다시 그리지 않는다")
        }
        model.endCropDrag()
        XCTAssertTrue(model.isRendering, "드래그가 끝나면 한 번 그린다")
        XCTAssertEqual(model.session.selected?.document.undoStack.count, before + 1)
        XCTAssertEqual(model.currentRecipe.geometry.crop?.width, 0.7)
        model.undo()
        XCTAssertNil(model.currentRecipe.geometry.crop, "실행 취소 한 번에 드래그 전으로")
    }

    func testBeautyToolEditsSkinOneUndoStepEach() async throws {
        let staged = try TestSupport.solidPNG(in: root)
        let model = TestSupport.makeModel(
            root: root, importer: FakeImporter(staged: [.success(StagedPhoto(url: staged, displayName: nil))]))
        try await importOne(model, staged)
        model.selectTool(.beauty)
        XCTAssertEqual(model.beautyTab, .skin)
        model.beginSliderEdit()
        model.edit(.skinSmoothing(0.4))
        model.edit(.skinSmoothing(0.5))
        model.endSliderEdit()
        model.edit(.autoBlemish(true))
        XCTAssertEqual(model.currentRecipe.portrait.skin, SkinAdjustments(smoothing: 0.5, autoBlemish: true))
        model.undo()
        XCTAssertEqual(model.currentRecipe.portrait.skin, SkinAdjustments(smoothing: 0.5))
        model.undo()
        XCTAssertTrue(model.currentRecipe.isDefault)
    }

    func testSkinTabEditsEveryRefinementKeyOneUndoStepEach() async throws {
        let staged = try TestSupport.solidPNG(in: root)
        let face = TestSupport.landmarkedFace(in: NormalizedRect(x: 0.2, y: 0.2, width: 0.6, height: 0.6))
        let model = TestSupport.makeModel(
            root: root, analyzer: StubFaceAnalyzer(result: .success([face])),
            importer: FakeImporter(staged: [.success(StagedPhoto(url: staged, displayName: nil))]))
        try await importOne(model, staged)
        model.selectTool(.beauty)
        model.beautyTab = .skin
        for (offset, key) in SkinRefinementKey.allCases.enumerated() {
            model.beginSliderEdit()
            model.edit(.skinRefinement(key, 0.3))
            model.edit(.skinRefinement(key, key == .redness ? -0.5 : 0.6))
            model.endSliderEdit()
            XCTAssertEqual(model.session.selected?.document.undoStack.count, offset + 1, "\(key) 드래그 한 번이 한 단계")
        }
        XCTAssertEqual(
            model.currentRecipe.portrait.skin,
            SkinAdjustments(
                darkCircles: 0.6, nasolabial: 0.6, marionette: 0.6, glabella: 0.6, toneEvening: 0.6, redness: -0.5,
                shine: 0.6))
        try await waitUntil { !model.isRendering }
        XCTAssertNil(model.presentedError)
        model.undo()
        XCTAssertEqual(model.currentRecipe.portrait.skin.shine, 0)
        XCTAssertEqual(
            SkinRefinementKey.allCases.map(UserMessage.skinRefinementTitle),
            ["다크서클", "팔자주름", "마리오네트 주름", "미간 주름", "피부 얼룩 고르기", "붉은기", "번들거림"])
    }

    func testAutoEnhanceWithFaceTurnsOnAutoBlemishAndKeepsFaceWidth() async throws {
        let staged = try TestSupport.solidPNG(in: root)
        let face = FaceGeometry(boundingBox: NormalizedRect(x: 0.2, y: 0.2, width: 0.6, height: 0.6))
        let model = TestSupport.makeModel(
            root: root, analyzer: StubFaceAnalyzer(result: .success([face])),
            importer: FakeImporter(staged: [.success(StagedPhoto(url: staged, displayName: nil))]))
        try await importOne(model, staged)
        model.edit(.faceShape(.width, -0.4))
        await model.autoEnhance()
        XCTAssertEqual(
            model.currentRecipe.portrait.skin,
            SkinAdjustments(smoothing: RenderTuning().autoSkinSmoothing, autoBlemish: true))
        XCTAssertEqual(model.currentRecipe.portrait.face.width, -0.4, "자동 보정은 얼굴형을 건드리지 않는다")
        XCTAssertEqual(
            model.currentRecipe.portrait.features.eyeBrighten, RenderTuning().autoEyeBrighten, "자동 보정은 눈 또렷하게를 켠다")
    }

    func testBeautyTabSurvivesToolSwitch() {
        let model = TestSupport.makeModel(root: root)
        model.selectTool(.beauty)
        model.beautyTab = .face
        model.selectTool(.adjust)
        model.selectTool(.beauty)
        XCTAssertEqual(model.beautyTab, .face)
    }

    func testFaceTabEditsEveryShapeKeyOneUndoStepEach() async throws {
        let staged = try TestSupport.solidPNG(in: root)
        let model = TestSupport.makeModel(
            root: root, importer: FakeImporter(staged: [.success(StagedPhoto(url: staged, displayName: nil))]))
        try await importOne(model, staged)
        model.selectTool(.beauty)
        model.beautyTab = .face
        for key in FaceShapeKey.allCases {
            model.beginSliderEdit()
            model.edit(.faceShape(key, 0.3))
            model.edit(.faceShape(key, 0.4))
            model.endSliderEdit()
        }
        for key in FaceShapeKey.allCases {
            XCTAssertEqual(model.currentRecipe.portrait.face[key], 0.4, accuracy: 1e-9, "\(key)")
        }
        XCTAssertEqual(model.session.selected?.document.undoStack.count, FaceShapeKey.allCases.count)
        let titles = FaceShapeKey.allCases.map(UserMessage.faceShapeTitle)
        XCTAssertEqual(Set(titles).count, FaceShapeKey.allCases.count, "슬라이더 이름이 겹치지 않는다")
        XCTAssertEqual(titles.first, "얼굴 폭")
        model.undo()
        XCTAssertEqual(model.currentRecipe.portrait.face.chinLength, 0, "실행 취소 한 번에 마지막 슬라이더만")
        XCTAssertEqual(model.currentRecipe.portrait.face.forehead, 0.4, accuracy: 1e-9)
    }

    func testGeometryLockRejectsEveryFaceShapeKey() async throws {
        let staged = try TestSupport.solidPNG(in: root)
        let model = TestSupport.makeModel(
            root: root, importer: FakeImporter(staged: [.success(StagedPhoto(url: staged, displayName: nil))]))
        try await importOne(model, staged)
        model.tool = .retouch
        model.touch(from: NormalizedPoint(x: 0.3, y: 0.3), to: NormalizedPoint(x: 0.3, y: 0.3))
        model.touch(from: NormalizedPoint(x: 0.5, y: 0.5), to: NormalizedPoint(x: 0.5, y: 0.5))
        XCTAssertEqual(model.currentRecipe.operations.count, 1)
        try await waitUntil { !model.isRendering }
        XCTAssertTrue(model.isGeometryLocked)
        for key in FaceShapeKey.allCases {
            model.edit(.faceShape(key, 0.5))
            XCTAssertEqual(model.currentRecipe.portrait.face[key], 0, "\(key)는 잠겨 있다")
        }
        XCTAssertEqual(model.statusMessage, UserMessage.geometryLocked)
    }

    func testFeaturesTabEditsEachKeyAndIsNotLockedByLocalEdits() async throws {
        let staged = try TestSupport.solidPNG(in: root)
        let model = TestSupport.makeModel(
            root: root, importer: FakeImporter(staged: [.success(StagedPhoto(url: staged, displayName: nil))]))
        try await importOne(model, staged)
        XCTAssertEqual(BeautyTab.allCases, [.skin, .face, .features, .skinTone])
        XCTAssertEqual(BeautyTab.features.title, "눈·입")
        model.tool = .retouch
        model.touch(from: NormalizedPoint(x: 0.3, y: 0.3), to: NormalizedPoint(x: 0.3, y: 0.3))
        model.touch(from: NormalizedPoint(x: 0.5, y: 0.5), to: NormalizedPoint(x: 0.5, y: 0.5))
        try await waitUntil { !model.isRendering }
        XCTAssertTrue(model.isGeometryLocked)
        model.selectTool(.beauty)
        model.beautyTab = .features
        for key in FeatureKey.allCases {
            model.beginSliderEdit()
            model.edit(.feature(key, 0.3))
            model.edit(.feature(key, 0.6))
            model.endSliderEdit()
        }
        for key in FeatureKey.allCases {
            XCTAssertEqual(model.currentRecipe.portrait.features[key], 0.6, accuracy: 1e-9, "\(key)는 잠기지 않는다")
        }
        XCTAssertEqual(FeatureKey.allCases.map(UserMessage.featureTitle), ["눈 또렷하게", "치아 미백", "입술 생기"])
        model.undo()
        XCTAssertEqual(model.currentRecipe.portrait.features.lipVitality, 0, "실행 취소 한 번에 마지막 슬라이더만")
        XCTAssertEqual(model.currentRecipe.portrait.features.teethWhiten, 0.6, accuracy: 1e-9)
    }

    func testSkinToneTabEditsEveryKeyOneUndoStepEachWhenPersonFound() async throws {
        let staged = try TestSupport.solidPNG(in: root)
        let face = TestSupport.landmarkedFace(in: NormalizedRect(x: 0.2, y: 0.3, width: 0.6, height: 0.6))
        let mask = TestSupport.personMask(NormalizedRect(x: 0.1, y: 0, width: 0.8, height: 0.95))
        let model = TestSupport.makeModel(
            root: root, analyzer: StubFaceAnalyzer(result: .success([face])),
            personAnalyzer: StubPersonAnalyzer(result: .success(mask)),
            importer: FakeImporter(staged: [.success(StagedPhoto(url: staged, displayName: nil))]))
        try await importOne(model, staged)
        model.selectTool(.beauty)
        model.beautyTab = .skinTone
        XCTAssertEqual(BeautyTab.allCases.count, 4)
        XCTAssertEqual(BeautyTab.skinTone.title, "피부톤")
        XCTAssertEqual(model.backgroundAvailability, .ready)
        for key in BodySkinKey.allCases {
            XCTAssertTrue(model.canAdjustBodySkin(key), "\(key)")
        }
        for (offset, key) in BodySkinKey.allCases.enumerated() {
            model.beginSliderEdit()
            model.edit(.bodySkin(key, 0.2))
            model.edit(.bodySkin(key, key == .tone ? -0.4 : 0.7))
            model.endSliderEdit()
            XCTAssertEqual(model.session.selected?.document.undoStack.count, offset + 1, "\(key) 드래그 한 번이 한 단계")
        }
        XCTAssertEqual(model.currentRecipe.bodySkin, BodySkinAdjustments(brightness: 0.7, tone: -0.4, smoothing: 0.7))
        try await waitUntil { !model.isRendering }
        XCTAssertNil(model.presentedError)
        XCTAssertEqual(BodySkinKey.allCases.map(UserMessage.bodySkinTitle), ["피부 밝기", "피부 톤", "바디 피부 매끄럽게"])
        model.selectTool(.adjust)
        model.selectTool(.beauty)
        XCTAssertEqual(model.beautyTab, .skinTone, "탭은 도구를 바꿔도 유지")
    }

    func testSkinToneSlidersFollowPersonAvailabilityAndPresetValues() async throws {
        let staged = try TestSupport.solidPNG(in: root)
        let face = FaceGeometry(boundingBox: NormalizedRect(x: 0.2, y: 0.2, width: 0.6, height: 0.6))
        let model = TestSupport.makeModel(
            root: root, analyzer: StubFaceAnalyzer(result: .success([face])),
            importer: FakeImporter(staged: [.success(StagedPhoto(url: staged, displayName: nil))]))
        try await importOne(model, staged)
        XCTAssertEqual(model.backgroundAvailability, .noPerson)
        XCTAssertFalse(model.canAdjustBodySkin(.brightness), "사람이 없으면 끈다")
        model.applyPreset(PresetValues(bodySkin: BodySkinAdjustments(brightness: 0.4)))
        XCTAssertTrue(model.canAdjustBodySkin(.brightness), "프리셋으로 들어온 값은 0으로 되돌릴 수 있다")
        XCTAssertFalse(model.canAdjustBodySkin(.tone), "0인 항목은 계속 끈다")
        try await waitUntil { !model.isRendering }
        XCTAssertNil(model.presentedError, "사람이 없으면 몸 피부만 건너뛰고 오류를 띄우지 않는다")
        model.beginSliderEdit()
        model.edit(.bodySkin(.brightness, 0))
        XCTAssertTrue(model.canAdjustBodySkin(.brightness), "드래그 중에는 0에 닿아도 끄지 않는다")
        model.endSliderEdit()
        XCTAssertFalse(model.canAdjustBodySkin(.brightness))
    }

    func testBackgroundToolEditsBlurOneUndoStepWhenPersonFound() async throws {
        let staged = try TestSupport.solidPNG(in: root)
        let mask = TestSupport.personMask(NormalizedRect(x: 0.3, y: 0, width: 0.4, height: 0.8))
        let model = TestSupport.makeModel(
            root: root, personAnalyzer: StubPersonAnalyzer(result: .success(mask)),
            importer: FakeImporter(staged: [.success(StagedPhoto(url: staged, displayName: nil))]))
        try await importOne(model, staged)
        model.selectTool(.background)
        XCTAssertEqual(EditorTool.background.title, "배경")
        XCTAssertEqual(model.backgroundAvailability, .ready)
        model.beginSliderEdit()
        model.edit(.backgroundBlur(0.3))
        model.edit(.backgroundBlur(0.5))
        model.endSliderEdit()
        XCTAssertEqual(model.currentRecipe.background.blur, 0.5, accuracy: 1e-9)
        try await waitUntil { !model.isRendering }
        XCTAssertNil(model.presentedError)
        model.undo()
        XCTAssertEqual(model.currentRecipe.background.blur, 0, "드래그 한 번이 실행 취소 한 단계")
    }

    func testBackgroundToolReportsNoPersonAndAnalysisFailureWithoutBlockingRender() async throws {
        let staged = try TestSupport.solidPNG(in: root)
        let empty = TestSupport.makeModel(
            root: root, importer: FakeImporter(staged: [.success(StagedPhoto(url: staged, displayName: nil))]))
        try await importOne(empty, staged)
        XCTAssertEqual(empty.backgroundAvailability, .noPerson)

        let otherRoot = try TestSupport.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: otherRoot) }
        let otherStaged = try TestSupport.solidPNG(in: otherRoot)
        let failure = MellowError.personAnalysisUnavailable(reason: "test")
        let failing = TestSupport.makeModel(
            root: otherRoot, personAnalyzer: StubPersonAnalyzer(result: .failure(failure)),
            importer: FakeImporter(staged: [.success(StagedPhoto(url: otherStaged, displayName: nil))]))
        try await importOne(failing, otherStaged)
        XCTAssertNil(failing.presentedError, "인물 분석 실패는 가져오기 경고로 띄우지 않는다")
        XCTAssertEqual(failing.backgroundAvailability, .unavailable(failure))
        failing.edit(.backgroundBlur(0.5))
        try await waitUntil { !failing.isRendering }
        XCTAssertEqual(failing.currentRecipe.background.blur, 0.5, "값은 저장된다")
        XCTAssertNil(failing.presentedError, "렌더는 흐림만 건너뛰고 오류를 띄우지 않는다")
    }

    func testBodyToolEditsEveryKeyOneUndoStepEachWhenBodyFound() async throws {
        let staged = try TestSupport.solidPNG(in: root)
        let body = TestSupport.standingBody(in: NormalizedRect(x: 0.1, y: 0, width: 0.8, height: 1))
        let model = TestSupport.makeModel(
            root: root, bodyAnalyzer: StubBodyAnalyzer(result: .success([body])),
            importer: FakeImporter(staged: [.success(StagedPhoto(url: staged, displayName: nil))]))
        try await importOne(model, staged)
        XCTAssertEqual(
            EditorTool.allCases, [.look, .crop, .adjust, .beauty, .makeup, .body, .background, .retouch, .warp])
        model.selectTool(.body)
        XCTAssertEqual(EditorTool.body.title, "체형")
        XCTAssertEqual(model.bodyAvailability, .ready)
        for key in BodyShapeKey.allCases {
            model.beginSliderEdit()
            model.edit(.bodyShape(key, 0.2))
            model.edit(.bodyShape(key, 0.4))
            model.endSliderEdit()
        }
        for key in BodyShapeKey.allCases {
            XCTAssertEqual(model.currentRecipe.body[key], 0.4, accuracy: 1e-9, "\(key)")
        }
        XCTAssertEqual(
            BodyShapeKey.allCases.map(UserMessage.bodyShapeTitle), ["다리 길게", "허리", "몸 전체", "팔", "허벅지", "어깨", "목"])
        try await waitUntil { !model.isRendering }
        XCTAssertNil(model.presentedError)
        model.undo()
        XCTAssertEqual(model.currentRecipe.body.neck, 0, "드래그 한 번이 실행 취소 한 단계")
        XCTAssertEqual(model.currentRecipe.body.shoulders, 0.4, accuracy: 1e-9)
    }

    func testBodyToolReportsNoBodyAndAnalysisFailureWithoutBlockingRender() async throws {
        let staged = try TestSupport.solidPNG(in: root)
        let empty = TestSupport.makeModel(
            root: root, importer: FakeImporter(staged: [.success(StagedPhoto(url: staged, displayName: nil))]))
        try await importOne(empty, staged)
        XCTAssertEqual(empty.bodyAvailability, .noBody)
        XCTAssertEqual(UserMessage.noBodyHint, "전신이 보이는 사진에서 동작합니다.")

        let otherRoot = try TestSupport.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: otherRoot) }
        let otherStaged = try TestSupport.solidPNG(in: otherRoot)
        let failure = MellowError.bodyAnalysisUnavailable(reason: "test")
        let failing = TestSupport.makeModel(
            root: otherRoot, bodyAnalyzer: StubBodyAnalyzer(result: .failure(failure)),
            importer: FakeImporter(staged: [.success(StagedPhoto(url: otherStaged, displayName: nil))]))
        try await importOne(failing, otherStaged)
        XCTAssertNil(failing.presentedError, "체형 분석 실패는 가져오기 경고로 띄우지 않는다")
        XCTAssertEqual(failing.bodyAvailability, .unavailable(failure))
        failing.edit(.bodyShape(.legLength, 0.5))
        try await waitUntil { !failing.isRendering }
        XCTAssertEqual(failing.currentRecipe.body.legLength, 0.5, "값은 저장된다")
        XCTAssertNil(failing.presentedError, "렌더는 체형만 건너뛰고 오류를 띄우지 않는다")
    }

    func testReprepareAfterEvictionRefreshesBodyInfo() async throws {
        let files = try ["A", "B", "C", "D"].map { try TestSupport.solidPNG(in: root, name: $0) }
        let failure = MellowError.bodyAnalysisUnavailable(reason: "first")
        let body = TestSupport.standingBody(in: NormalizedRect(x: 0.1, y: 0, width: 0.8, height: 1))
        let queue = BodyResultQueue([.failure(failure), .success([body])])
        let model = TestSupport.makeModel(
            root: root, bodyAnalyzer: StubBodyAnalyzer(queue: queue),
            importer: FakeImporter(passesThroughFileURLs: true))
        await model.importFromFiles([files[0]])
        try await waitUntil { model.isReady && model.preview != nil }
        let first = try XCTUnwrap(model.session.selectedPhotoID)
        XCTAssertEqual(model.bodyAvailability, .unavailable(failure), "첫 준비의 체형 분석은 실패한다")
        await model.importFromFiles(Array(files[1...]))
        try await waitUntil { !model.isImporting }
        XCTAssertEqual(queue.calls, 4, "사진마다 한 번씩 분석한다")
        model.select(first)
        try await waitUntil { model.isReady && model.preview != nil }
        XCTAssertEqual(queue.calls, 5, "밀려난 첫 사진을 다시 준비하며 다시 분석한다")
        XCTAssertNil(model.photoInfo[first]?.bodyAnalysisFailure, "다시 준비한 분석이 이전 실패를 지운다")
        XCTAssertEqual(model.photoInfo[first]?.hasBody, true, "다시 준비한 분석의 전신 여부를 저장한다")
        XCTAssertEqual(model.bodyAvailability, .ready)
        XCTAssertNil(model.presentedError)
    }

    func testGeometryLockRejectsEveryBodyShapeKey() async throws {
        let staged = try TestSupport.solidPNG(in: root)
        let body = TestSupport.standingBody(in: NormalizedRect(x: 0.1, y: 0, width: 0.8, height: 1))
        let model = TestSupport.makeModel(
            root: root, bodyAnalyzer: StubBodyAnalyzer(result: .success([body])),
            importer: FakeImporter(staged: [.success(StagedPhoto(url: staged, displayName: nil))]))
        try await importOne(model, staged)
        model.tool = .retouch
        model.touch(from: NormalizedPoint(x: 0.3, y: 0.3), to: NormalizedPoint(x: 0.3, y: 0.3))
        model.touch(from: NormalizedPoint(x: 0.5, y: 0.5), to: NormalizedPoint(x: 0.5, y: 0.5))
        XCTAssertEqual(model.currentRecipe.operations.count, 1)
        try await waitUntil { !model.isRendering }
        XCTAssertTrue(model.isGeometryLocked)
        model.selectTool(.body)
        for key in BodyShapeKey.allCases {
            model.edit(.bodyShape(key, 0.5))
            XCTAssertEqual(model.currentRecipe.body[key], 0, "\(key)는 잠겨 있다")
        }
        XCTAssertEqual(model.statusMessage, UserMessage.geometryLocked)
        XCTAssertTrue(UserMessage.geometryLocked.contains("체형"), "잠금 문구가 체형도 말한다")
    }

    func testFaceAvailabilityReportsMissingLandmarksForTargetFaces() async throws {
        let staged = try TestSupport.solidPNG(in: root)
        let landmarked = TestSupport.landmarkedFace(in: NormalizedRect(x: 0.05, y: 0.3, width: 0.35, height: 0.4))
        let boxOnly = FaceGeometry(boundingBox: NormalizedRect(x: 0.55, y: 0.3, width: 0.35, height: 0.4))
        let model = TestSupport.makeModel(
            root: root, analyzer: StubFaceAnalyzer(result: .success([landmarked, boxOnly])),
            importer: FakeImporter(staged: [.success(StagedPhoto(url: staged, displayName: nil))]))
        try await importOne(model, staged)
        XCTAssertEqual(model.faceAvailability, .ready, "특징점이 있는 얼굴이 대상에 있으면 준비됨")
        model.edit(.targetFace(1))
        XCTAssertEqual(model.faceAvailability, .noLandmarks)
        XCTAssertTrue(UserMessage.noLandmarksHint.contains("메이크업"))
        model.edit(.targetFace(0))
        XCTAssertEqual(model.faceAvailability, .ready)

        let otherRoot = try TestSupport.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: otherRoot) }
        let otherStaged = try TestSupport.solidPNG(in: otherRoot)
        let empty = TestSupport.makeModel(
            root: otherRoot,
            importer: FakeImporter(staged: [.success(StagedPhoto(url: otherStaged, displayName: nil))]))
        try await importOne(empty, otherStaged)
        XCTAssertEqual(empty.faceAvailability, .noFace)
    }

    func testBackgroundAndBodySlidersStayUsableToResetPresetValues() async throws {
        let staged = try TestSupport.solidPNG(in: root)
        let model = TestSupport.makeModel(
            root: root, importer: FakeImporter(staged: [.success(StagedPhoto(url: staged, displayName: nil))]))
        try await importOne(model, staged)
        XCTAssertEqual(model.backgroundAvailability, .noPerson)
        XCTAssertEqual(model.bodyAvailability, .noBody)
        XCTAssertFalse(model.canAdjustBackgroundBlur)
        XCTAssertFalse(model.canAdjustBodyShape(.waist))
        model.applyPreset(
            PresetValues(background: BackgroundAdjustments(blur: 0.4), body: BodyShapeAdjustments(waist: -0.3)))
        XCTAssertTrue(model.canAdjustBackgroundBlur, "프리셋으로 들어온 흐림은 0으로 되돌릴 수 있다")
        XCTAssertTrue(model.canAdjustBodyShape(.waist))
        XCTAssertFalse(model.canAdjustBodyShape(.arms), "0인 항목은 효과가 없어 계속 끈다")
        model.edit(.backgroundBlur(0))
        model.edit(.bodyShape(.waist, 0))
        XCTAssertFalse(model.canAdjustBackgroundBlur)
        XCTAssertFalse(model.canAdjustBodyShape(.waist))
        try await waitUntil { !model.isRendering }
        XCTAssertNil(model.presentedError)
    }

    func testMakeupToolAppliesLookOnceAndPartEditsDetachLook() async throws {
        let staged = try TestSupport.solidPNG(in: root)
        let face = TestSupport.landmarkedFace(in: NormalizedRect(x: 0.2, y: 0.2, width: 0.6, height: 0.6))
        let model = TestSupport.makeModel(
            root: root, analyzer: StubFaceAnalyzer(result: .success([face])),
            importer: FakeImporter(staged: [.success(StagedPhoto(url: staged, displayName: nil))]))
        try await importOne(model, staged)
        model.selectTool(.makeup)
        XCTAssertEqual(EditorTool.makeup.title, "메이크업")
        XCTAssertEqual(model.makeupCatalog.looks.map(\.name), ["데일리", "쿨톤", "웜피치", "로지", "스모키"])
        XCTAssertEqual(
            MakeupPart.allCases.map(UserMessage.makeupPartTitle), ["립", "블러셔", "아이섀도", "눈썹", "쉐딩"])
        let daily = try XCTUnwrap(model.makeupCatalog.look(id: "daily"))
        model.applyMakeupLook(id: "daily")
        XCTAssertEqual(model.currentRecipe.makeup, daily.adjustments)
        model.applyMakeupLook(id: "nope")
        XCTAssertEqual(model.currentRecipe.makeup, daily.adjustments, "모르는 룩은 무시한다")
        model.makeupPart = .blush
        model.beginSliderEdit()
        model.edit(.makeupIntensity(.blush, 0.6))
        model.edit(.makeupIntensity(.blush, 0.8))
        model.endSliderEdit()
        XCTAssertEqual(model.currentRecipe.makeup.blush.intensity, 0.8, accuracy: 1e-9)
        XCTAssertNil(model.currentRecipe.makeup.lookID, "부위를 바꾸면 룩 이름이 풀린다")
        try await waitUntil { !model.isRendering }
        XCTAssertNil(model.presentedError)
        model.undo()
        XCTAssertEqual(model.currentRecipe.makeup, daily.adjustments, "드래그 한 번이 실행 취소 한 단계")
        model.undo()
        XCTAssertEqual(model.currentRecipe.makeup, MakeupAdjustments(), "룩 적용도 실행 취소 한 번")
        model.redo()
        model.applyMakeupLook(id: nil)
        XCTAssertEqual(model.currentRecipe.makeup, MakeupAdjustments(), "없음은 메이크업을 모두 지운다")
    }

    func testMakeupWorksWithLocalEditsAndFallsBackWithoutCatalog() async throws {
        let staged = try TestSupport.solidPNG(in: root)
        let model = TestSupport.makeModel(
            root: root, importer: FakeImporter(staged: [.success(StagedPhoto(url: staged, displayName: nil))]))
        try await importOne(model, staged)
        model.tool = .retouch
        model.touch(from: NormalizedPoint(x: 0.3, y: 0.3), to: NormalizedPoint(x: 0.3, y: 0.3))
        model.touch(from: NormalizedPoint(x: 0.5, y: 0.5), to: NormalizedPoint(x: 0.5, y: 0.5))
        try await waitUntil { !model.isRendering }
        XCTAssertTrue(model.isGeometryLocked)
        model.selectTool(.makeup)
        model.edit(.makeupColor(.lip, "lip-coral"))
        XCTAssertEqual(model.currentRecipe.makeup.lip.colorID, "lip-coral", "메이크업은 수동 편집이 있어도 잠기지 않는다")
        XCTAssertNotEqual(model.statusMessage, UserMessage.geometryLocked)
        model.applyMakeupLook(id: "smoky")
        XCTAssertEqual(model.currentRecipe.makeup.lookID, "smoky")

        let otherRoot = try TestSupport.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: otherRoot) }
        let otherStaged = try TestSupport.solidPNG(in: otherRoot)
        let bare = TestSupport.makeModel(
            root: otherRoot, makeupCatalog: .empty,
            importer: FakeImporter(staged: [.success(StagedPhoto(url: otherStaged, displayName: nil))]))
        try await importOne(bare, otherStaged)
        bare.applyMakeupLook(id: "daily")
        XCTAssertEqual(bare.currentRecipe.makeup, MakeupAdjustments(), "카탈로그가 없으면 룩을 고를 수 없다")
        XCTAssertTrue(bare.makeupCatalog.isEmpty)
        XCTAssertTrue(UserMessage.makeupCatalogUnavailable.contains("메이크업"))
        XCTAssertNil(
            AppModel.bundledMakeupCatalog(in: Bundle(for: AppModelTests.self)), "파일이 없는 번들은 nil(안내 문구로 바뀐다)")
        XCTAssertEqual(AppModel.bundledMakeupCatalog()?.looks.count, 5, "앱 번들에서는 읽힌다")
    }

    func testMakeupLookDuringSliderDragEndsDragFirst() async throws {
        let staged = try TestSupport.solidPNG(in: root)
        let model = TestSupport.makeModel(
            root: root, importer: FakeImporter(staged: [.success(StagedPhoto(url: staged, displayName: nil))]))
        try await importOne(model, staged)
        model.selectTool(.makeup)
        model.beginSliderEdit()
        model.edit(.makeupIntensity(.contour, 0.7))
        XCTAssertTrue(model.session.isPersistenceDeferred)
        model.applyMakeupLook(id: "daily")
        XCTAssertFalse(model.session.isPersistenceDeferred, "룩 적용 전에 열린 드래그를 끝낸다")
        let daily = try XCTUnwrap(model.makeupCatalog.look(id: "daily"))
        XCTAssertEqual(model.currentRecipe.makeup, daily.adjustments)
        try await waitUntil { !model.isRendering }
        model.undo()
        XCTAssertEqual(model.currentRecipe.makeup.contour.intensity, 0.7, accuracy: 1e-9, "룩 적용은 자기 단계를 갖는다")
        model.undo()
        XCTAssertEqual(model.currentRecipe.makeup, MakeupAdjustments(), "드래그도 자기 단계를 갖는다")
    }

    func testMakeupControlsLockWhenFaceAnalysisFailedUnlessMakeupNeedsClearing() async throws {
        let staged = try TestSupport.solidPNG(in: root)
        let failed = TestSupport.makeModel(
            root: root, analyzer: StubFaceAnalyzer(result: .failure(.faceAnalysisUnavailable(reason: "test"))),
            importer: FakeImporter(staged: [.success(StagedPhoto(url: staged, displayName: nil))]))
        try await importOne(failed, staged)
        failed.selectTool(.makeup)
        XCTAssertEqual(failed.faceAvailability, .unavailable(.faceAnalysisUnavailable(reason: "test")))
        XCTAssertFalse(failed.canAdjustMakeup, "분석이 실패한 사진에 메이크업을 넣으면 저장이 실패한다")
        let daily = try XCTUnwrap(failed.makeupCatalog.look(id: "daily"))
        failed.applyPreset(PresetValues(makeup: daily.adjustments))
        XCTAssertTrue(failed.canAdjustMakeup, "프리셋으로 들어온 메이크업은 줄이거나 지울 수 있다")
        failed.applyMakeupLook(id: nil)
        XCTAssertEqual(failed.currentRecipe.makeup, MakeupAdjustments(), "없음은 언제나 메이크업을 지운다")
        XCTAssertFalse(failed.canAdjustMakeup)
        failed.applyPreset(PresetValues(makeup: daily.adjustments))
        failed.beginSliderEdit()
        for part in MakeupPart.allCases {
            failed.edit(.makeupIntensity(part, 0))
        }
        XCTAssertTrue(failed.canAdjustMakeup, "드래그 중에는 효과가 0이 돼도 끄지 않는다")
        failed.endSliderEdit()
        XCTAssertFalse(failed.canAdjustMakeup)

        let otherRoot = try TestSupport.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: otherRoot) }
        let otherStaged = try TestSupport.solidPNG(in: otherRoot)
        let face = TestSupport.landmarkedFace(in: NormalizedRect(x: 0.2, y: 0.2, width: 0.6, height: 0.6))
        let ready = TestSupport.makeModel(
            root: otherRoot, analyzer: StubFaceAnalyzer(result: .success([face])),
            importer: FakeImporter(staged: [.success(StagedPhoto(url: otherStaged, displayName: nil))]))
        try await importOne(ready, otherStaged)
        XCTAssertEqual(ready.faceAvailability, .ready)
        XCTAssertTrue(ready.canAdjustMakeup)
    }

    func testMakeupStaysAdjustableWithoutFacesBecauseExportStillWorks() async throws {
        let staged = try TestSupport.solidPNG(in: root)
        let model = TestSupport.makeModel(
            root: root, importer: FakeImporter(staged: [.success(StagedPhoto(url: staged, displayName: nil))]))
        try await importOne(model, staged)
        XCTAssertEqual(model.faceAvailability, .noFace)
        XCTAssertTrue(model.canAdjustMakeup, "얼굴이 없으면 메이크업은 효과만 없고 저장은 된다")
    }

    func testSelectingToolDuringSliderDragEndsDrag() async throws {
        let staged = try TestSupport.solidPNG(in: root)
        let model = TestSupport.makeModel(
            root: root, importer: FakeImporter(staged: [.success(StagedPhoto(url: staged, displayName: nil))]))
        try await importOne(model, staged)
        model.selectTool(.makeup)
        model.beginSliderEdit()
        model.edit(.makeupIntensity(.lip, 0.4))
        XCTAssertTrue(model.isSliderEditActive)
        model.selectTool(.adjust)
        XCTAssertFalse(model.isSliderEditActive, "도구를 바꾸면 열린 드래그를 끝낸다")
        model.edit(.exposure(0.2))
        try await waitUntil { !model.isRendering }
        model.undo()
        XCTAssertEqual(model.currentRecipe.makeup.lip.intensity, 0.4, accuracy: 1e-9, "도구 전환 뒤 편집은 자기 단계를 갖는다")
        model.undo()
        XCTAssertEqual(model.currentRecipe.makeup.lip.intensity, 0, "드래그가 한 단계")
    }

    func testSliderDraggedToZeroWithoutBodyStaysEnabledUntilDragEnds() async throws {
        let staged = try TestSupport.solidPNG(in: root)
        let store = MemorySessionStore()
        let model = TestSupport.makeModel(
            root: root, importer: FakeImporter(staged: [.success(StagedPhoto(url: staged, displayName: nil))]),
            store: store)
        try await importOne(model, staged)
        model.applyPreset(
            PresetValues(background: BackgroundAdjustments(blur: 0.4), body: BodyShapeAdjustments(waist: -0.3)))
        model.beginSliderEdit()
        model.edit(.bodyShape(.waist, 0))
        XCTAssertTrue(model.canAdjustBodyShape(.waist), "드래그 중에는 0이 돼도 끄지 않아 드래그가 정상으로 끝난다")
        model.endSliderEdit()
        XCTAssertFalse(model.session.isPersistenceDeferred, "드래그가 끝나면 미룬 저장도 끝난다")
        XCTAssertFalse(model.canAdjustBodyShape(.waist), "드래그가 끝난 뒤에 끈다")
        model.beginSliderEdit()
        model.edit(.backgroundBlur(0))
        XCTAssertTrue(model.canAdjustBackgroundBlur, "배경 흐림도 드래그 중에는 끄지 않는다")
        model.endSliderEdit()
        XCTAssertFalse(model.session.isPersistenceDeferred)
        XCTAssertFalse(model.canAdjustBackgroundBlur)
        let saves = store.saveCount
        model.edit(.makeupIntensity(.lip, 0.4))
        XCTAssertEqual(store.saveCount, saves + 1, "다음 편집은 바로 저장된다")
        model.undo()
        XCTAssertEqual(model.currentRecipe.background.blur, 0, "다음 편집은 자기 단계를 갖는다")
        model.undo()
        XCTAssertEqual(model.currentRecipe.background.blur, 0.4, accuracy: 1e-9, "흐림 드래그가 한 단계")
        XCTAssertEqual(model.currentRecipe.body.waist, 0, "허리 드래그는 그 앞 단계")
        try await waitUntil { !model.isRendering }
        XCTAssertNil(model.presentedError)
    }
}
