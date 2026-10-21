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

    func testSavedPresetCarriesGroupLayersNotIndividuals() async throws {
        let staged = try TestSupport.solidPNG(in: root)
        let face = TestSupport.landmarkedFace(in: NormalizedRect(x: 0.2, y: 0.2, width: 0.6, height: 0.6))
        let model = TestSupport.makeModel(
            root: root, analyzer: StubFaceAnalyzer(result: .success([face])),
            importer: FakeImporter(staged: [.success(StagedPhoto(url: staged, displayName: nil))]))
        try await importOne(model, staged)
        model.setBeautyTarget(.gender(.female))
        model.edit(.skinSmoothing(0.5))
        model.setBeautyTarget(.face(0))
        model.edit(.faceShape(.width, -0.4))
        XCTAssertEqual(model.currentRecipe.people.groups[.female], PortraitLayer(skinSmoothing: 0.5))
        XCTAssertEqual(model.currentRecipe.people.individuals.count, 1)
        XCTAssertEqual(model.scopedValues.portrait.face.width, -0.4, "패널은 대상 층까지 겹친 값을 보인다")
        model.savePreset(named: "남녀")
        let saved = try XCTUnwrap(model.session.presets.last)
        XCTAssertEqual(saved.values.people.groups[.female], PortraitLayer(skinSmoothing: 0.5))
        XCTAssertTrue(saved.values.people.individuals.isEmpty, "프리셋은 사람을 고르지 않는다")
        XCTAssertEqual(saved.values.portrait.face.width, 0, "개인 층 값은 전체 층에 섞이지 않는다")
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

    func testApplyToAllCopiesOnlyChosenCategories() async throws {
        let first = try TestSupport.solidPNG(in: root, name: "A")
        let second = try TestSupport.solidPNG(in: root, name: "B")
        let model = TestSupport.makeModel(root: root, importer: FakeImporter(passesThroughFileURLs: true))
        await model.importFromFiles([first, second])
        try await waitUntil { model.isReady && model.preview != nil }
        XCTAssertEqual(model.session.photos.count, 2)
        XCTAssertEqual(model.syncCategories, SyncCategory.all, "기본은 전부")
        XCTAssertTrue(model.canApplyToAll)
        model.edit(.exposure(0.3))
        model.edit(.skinSmoothing(0.4))
        model.setSyncCategory(.skin, enabled: false)
        model.applyToAll()
        let other = model.session.photos[1].document.recipe
        XCTAssertEqual(other.color.exposure, 0.3)
        XCTAssertEqual(other.portrait.skin.smoothing, 0, "끈 항목은 복사하지 않는다")
        XCTAssertEqual(model.statusMessage, UserMessage.appliedToAll(categoryCount: 8, total: 9))
        for category in SyncCategory.allCases {
            model.setSyncCategory(category, enabled: false)
        }
        XCTAssertFalse(model.canApplyToAll, "아무것도 고르지 않으면 끈다")
        model.edit(.exposure(0.5))
        model.applyToAll()
        XCTAssertEqual(model.session.photos[1].document.recipe.color.exposure, 0.3, "빈 선택은 적용하지 않는다")
        model.setSyncCategory(.color, enabled: true)
        XCTAssertEqual(model.syncCategories, [.color])
        XCTAssertEqual(
            SyncCategory.allCases.map(UserMessage.syncCategoryTitle),
            ["색감·디테일", "효과", "피부", "얼굴형", "눈·입", "메이크업", "배경", "체형", "피부톤"])
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
                shine: 0.6, spots: 0.6))
        try await waitUntil { !model.isRendering }
        XCTAssertNil(model.presentedError)
        model.undo()
        XCTAssertEqual(model.currentRecipe.portrait.skin.spots, 0)
        XCTAssertEqual(model.currentRecipe.portrait.skin.shine, 0.6)
        XCTAssertEqual(
            SkinRefinementKey.allCases.map(UserMessage.skinRefinementTitle),
            ["다크서클", "팔자주름", "마리오네트 주름", "미간 주름", "피부 얼룩 고르기", "붉은기", "번들거림", "점 지우기"])
    }

    func testAutoEnhanceWithFaceAppliesOneTouchSkinAndKeepsFaceWidth() async throws {
        let staged = try TestSupport.solidPNG(in: root)
        let face = FaceGeometry(boundingBox: NormalizedRect(x: 0.2, y: 0.2, width: 0.6, height: 0.6))
        let model = TestSupport.makeModel(
            root: root, analyzer: StubFaceAnalyzer(result: .success([face])),
            importer: FakeImporter(staged: [.success(StagedPhoto(url: staged, displayName: nil))]))
        try await importOne(model, staged)
        model.edit(.faceShape(.width, -0.4))
        await model.autoEnhance()
        // 자동은 원터치를 포함하므로(Policy.autoIncludesOneTouch) 인물 값은 공통 표 × 기본 강도다.
        let common = OneTouchBundle.layer(for: nil, strength: EditingPolicy.oneTouchDefaultStrength)
        XCTAssertEqual(model.currentRecipe.portrait.skin.smoothing, common.skinSmoothing)
        XCTAssertFalse(model.currentRecipe.portrait.skin.autoBlemish, "원터치는 복제 원 대신 점 지우기를 쓴다(스펙 G5 판정 4b)")
        XCTAssertEqual(model.currentRecipe.portrait.skin.spots, common.skinRefinement[.spots])
        XCTAssertEqual(model.currentRecipe.portrait.face.width, -0.4, "자동 보정은 얼굴형을 건드리지 않는다")
        XCTAssertEqual(
            model.currentRecipe.portrait.features.eyeBrighten, common.features[.eyeBrighten], "자동 보정은 눈 또렷하게를 켠다")
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

    func testSkinToneStatusLineReflectsPersonAndFaceConditions() async throws {
        let staged = try TestSupport.solidPNG(in: root)
        let face = FaceGeometry(boundingBox: NormalizedRect(x: 0.2, y: 0.2, width: 0.6, height: 0.6))
        let model = TestSupport.makeModel(
            root: root, analyzer: StubFaceAnalyzer(result: .success([face])),
            importer: FakeImporter(staged: [.success(StagedPhoto(url: staged, displayName: nil))]))
        try await importOne(model, staged)
        XCTAssertEqual(model.backgroundAvailability, .noPerson)
        XCTAssertEqual(model.bodySkinStatus, .fallback, "사람 영역이 없어도 얼굴이 있으면 대체 영역")
        XCTAssertTrue(model.canAdjustBodySkin(.brightness), "대체 영역에서도 켠다")
        XCTAssertEqual(UserMessage.bodySkinStatus(.fallback), "사람 영역 없음 → 얼굴 둘레로 대신 적용해요")
        XCTAssertEqual(UserMessage.bodySkinStatus(.ready), "사람 영역 ✓ · 기준 얼굴 ✓")
        XCTAssertEqual(UserMessage.bodySkinStatus(.noFace), "기준 얼굴이 없어 피부 밝기·톤·매끄럽게가 적용되지 않아요")
        model.beginSliderEdit()
        model.edit(.bodySkin(.brightness, 0.4))
        model.endSliderEdit()
        try await waitUntil { !model.isRendering }
        XCTAssertNil(model.presentedError)
        let failingRoot = root.appendingPathComponent("person-failure")
        try FileManager.default.createDirectory(at: failingRoot, withIntermediateDirectories: true)
        let failingStaged = try TestSupport.solidPNG(in: failingRoot)
        let personFailure = MellowError.personAnalysisUnavailable(reason: "stub")
        let failing = TestSupport.makeModel(
            root: failingRoot, analyzer: StubFaceAnalyzer(result: .success([face])),
            personAnalyzer: StubPersonAnalyzer(result: .failure(personFailure)),
            importer: FakeImporter(staged: [.success(StagedPhoto(url: failingStaged, displayName: nil))]))
        try await importOne(failing, failingStaged)
        XCTAssertEqual(failing.bodySkinStatus, .personAnalysisUnavailable(personFailure))
        XCTAssertTrue(failing.canAdjustBodySkin(.brightness), "인물 분석이 실패해도 얼굴 둘레 대체 영역으로 렌더하므로 켠다")
        XCTAssertEqual(UserMessage.bodySkinStatus(failing.bodySkinStatus), "인물 영역 분석 실패 → 얼굴 둘레로 대신 적용해요")
        failing.beginSliderEdit()
        failing.edit(.bodySkin(.brightness, 0.4))
        failing.endSliderEdit()
        try await waitUntil { !failing.isRendering }
        XCTAssertNil(failing.presentedError, "인물 분석이 실패한 사진도 대체 영역으로 몸 피부를 렌더한다")
        let facelessRoot = root.appendingPathComponent("faceless")
        try FileManager.default.createDirectory(at: facelessRoot, withIntermediateDirectories: true)
        let facelessStaged = try TestSupport.solidPNG(in: facelessRoot)
        let faceless = TestSupport.makeModel(
            root: facelessRoot,
            importer: FakeImporter(staged: [.success(StagedPhoto(url: facelessStaged, displayName: nil))]))
        try await importOne(faceless, facelessStaged)
        XCTAssertEqual(faceless.bodySkinStatus, .noFace)
        XCTAssertFalse(faceless.canAdjustBodySkin(.brightness), "얼굴이 없으면 끈다")
        faceless.applyPreset(PresetValues(bodySkin: BodySkinAdjustments(brightness: 0.4)))
        XCTAssertTrue(faceless.canAdjustBodySkin(.brightness), "프리셋으로 들어온 값은 0으로 되돌릴 수 있다")
        XCTAssertFalse(faceless.canAdjustBodySkin(.tone), "0인 항목은 계속 끈다")
        try await waitUntil { !faceless.isRendering }
        XCTAssertNil(faceless.presentedError, "얼굴이 없으면 몸 피부만 건너뛰고 오류를 띄우지 않는다")
        faceless.beginSliderEdit()
        faceless.edit(.bodySkin(.brightness, 0))
        XCTAssertTrue(faceless.canAdjustBodySkin(.brightness), "드래그 중에는 0에 닿아도 끄지 않는다")
        faceless.endSliderEdit()
        XCTAssertFalse(faceless.canAdjustBodySkin(.brightness), "드래그가 끝나고 0이면 끈다")
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
        model.setBeautyTarget(.face(1))
        XCTAssertEqual(model.faceAvailability, .noLandmarks)
        XCTAssertTrue(UserMessage.noLandmarksHint.contains("메이크업"))
        for tool in ["피부 보정", "얼룩 고르기", "붉은기", "번들거림", "잡티·변형"] {
            XCTAssertTrue(UserMessage.noLandmarksHint.contains(tool), "특징점 없이 쓸 수 있는 도구를 알린다: \(tool)")
        }
        XCTAssertTrue(UserMessage.noLandmarksHint.contains("주름 밝히기"), "특징점이 있어야 하는 주름 슬라이더를 알린다")
        model.setBeautyTarget(.face(0))
        XCTAssertEqual(model.faceAvailability, .ready)
        model.setBeautyTarget(.gender(.male))
        XCTAssertEqual(model.faceAvailability, .ready, "그룹·전체는 모든 얼굴 기준")
        XCTAssertEqual(model.currentRecipe, EditRecipe(), "대상 전환은 레시피를 바꾸지 않는다")

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

    func testSplitCompareIsAModeBesideTheFullToggleAndResetsOnSelect() async throws {
        let staged = try TestSupport.solidPNG(in: root)
        let model = TestSupport.makeModel(
            root: root, importer: FakeImporter(staged: [.success(StagedPhoto(url: staged, displayName: nil))]))
        try await importOne(model, staged)
        XCTAssertEqual(model.compareMode, .off)
        XCTAssertFalse(model.blocksCanvasTouch)
        model.isComparing = true
        XCTAssertEqual(model.compareMode, .full, "기존 토글은 전체 모드")
        XCTAssertTrue(model.displayImage === model.original)
        model.toggleSplitCompare()
        XCTAssertEqual(model.compareMode, .split, "분할을 켜면 전체는 꺼진다")
        XCTAssertFalse(model.isComparing)
        XCTAssertTrue(model.displayImage === model.preview, "분할 모드의 바탕은 보정본")
        XCTAssertTrue(model.blocksCanvasTouch)
        XCTAssertTrue(model.splitCompareOriginal === model.original, "같은 기하로 그린 원본을 겹친다")
        XCTAssertEqual(model.compareSplit, AppModel.Policy.compareSplitDefault)
        model.setCompareSplit(1.4)
        XCTAssertEqual(model.compareSplit, 1)
        model.setCompareSplit(-0.2)
        XCTAssertEqual(model.compareSplit, 0)
        model.setCompareSplit(0.3)
        model.selectTool(.retouch)
        model.touch(from: NormalizedPoint(x: 0.5, y: 0.5), to: NormalizedPoint(x: 0.5, y: 0.5))
        XCTAssertNil(model.cloneSource, "비교 중에는 캔버스 탭을 무시한다")
        model.isComparing.toggle()
        XCTAssertEqual(model.compareMode, .full, "분할 중에 전체 토글을 켜면 전체로")
        model.toggleSplitCompare()
        model.toggleSplitCompare()
        XCTAssertEqual(model.compareMode, .off, "분할을 두 번 누르면 꺼진다")
        XCTAssertEqual(model.compareSplit, 0.3, accuracy: 1e-9, "분할선 위치는 기억한다")
        model.toggleSplitCompare()
        let id = try XCTUnwrap(model.session.selectedPhotoID)
        model.select(id)
        XCTAssertEqual(model.compareMode, .off, "사진을 고르면 비교가 꺼진다")
        XCTAssertEqual(UserMessage.compareBadge(.split), "원본 | 보정본")
        XCTAssertEqual(UserMessage.compareBadge(.full), "원본")
        XCTAssertEqual(UserMessage.compareBadge(.off), "보정본")
    }

    func testSplitCompareShowsTheOriginalOnlyWhenItsGeometryMatchesThePreview() async throws {
        let staged = try TestSupport.solidPNG(in: root)
        let model = TestSupport.makeModel(
            root: root, importer: FakeImporter(staged: [.success(StagedPhoto(url: staged, displayName: nil))]))
        try await importOne(model, staged)
        try await waitUntil { !model.isRendering }
        let gate = OriginalRenderGate()
        let pipeline = model.pipeline
        model.renderOriginal = { id, recipe in
            try await gate.pass()
            return try await pipeline.preview(id, recipe: recipe)
        }
        model.toggleSplitCompare()
        XCTAssertNotNil(model.splitCompareOriginal, "같은 기하로 그린 원본을 겹친다")
        let unflipped = model.preview
        model.edit(.flipHorizontal(true))
        try await waitUntil { model.preview !== unflipped && gate.calls == 1 }
        let stale = try XCTUnwrap(model.original)
        let preview = try XCTUnwrap(model.preview)
        XCTAssertEqual(stale.width * preview.height, preview.width * stale.height, "뒤집기는 비율이 같다")
        XCTAssertNil(model.splitCompareOriginal, "뒤집기 전 원본은 다시 그려질 때까지 겹치지 않는다")
        gate.open()
        try await waitUntil { model.splitCompareOriginal != nil }
        XCTAssertTrue(model.original !== stale, "다시 그린 원본을 겹친다")
        gate.fails = true
        let flipped = model.preview
        model.edit(.quarterTurns(1))
        try await waitUntil { model.preview !== flipped && gate.calls == 2 }
        XCTAssertNil(model.splitCompareOriginal, "원본을 다시 그리지 못하면 겹치지 않는다")
        model.edit(.exposure(0.2))
        try await waitUntil { gate.calls == 3 && !model.isRendering }
        XCTAssertNil(model.splitCompareOriginal, "다시 시도도 실패하면 계속 숨긴다")
        gate.fails = false
        model.edit(.exposure(0.3))
        try await waitUntil { model.splitCompareOriginal != nil }
        XCTAssertNil(model.presentedError, "원본 실패는 알림을 띄우지 않는다")
    }

    func testLastRenderFailureClearsWhenTheSelectedPhotoChanges() async throws {
        let first = try TestSupport.solidPNG(in: root, name: "A")
        let second = try TestSupport.solidPNG(in: root, name: "B")
        let importer = FakeImporter(staged: [
            .success(StagedPhoto(url: first, displayName: "A")), .success(StagedPhoto(url: second, displayName: "B")),
        ])
        let model = TestSupport.makeModel(root: root, importer: importer)
        await model.importFromFiles([first, second])
        try await waitUntil { model.isReady }
        model.lastRenderFailure = UserMessage.text(for: MellowError.renderFailed)
        XCTAssertTrue(model.diagnosticLines.contains { $0.hasPrefix(UserMessage.diagnosticLabel(.failure)) })
        let other = try XCTUnwrap(model.session.photos.first { $0.id != model.session.selectedPhotoID }).id
        model.select(other)
        XCTAssertNil(model.lastRenderFailure, "다른 사진을 고르면 이전 사진의 렌더 오류를 지운다")
        XCTAssertFalse(model.diagnosticLines.contains { $0.hasPrefix(UserMessage.diagnosticLabel(.failure)) })
    }

    func testDiagnosticLinesListBuildPhotoAnalysisAndNonDefaultRecipeKeys() async throws {
        let staged = try TestSupport.solidPNG(in: root)
        let face = TestSupport.landmarkedFace(in: NormalizedRect(x: 0.2, y: 0.2, width: 0.6, height: 0.6))
        let model = TestSupport.makeModel(
            root: root, analyzer: StubFaceAnalyzer(result: .success([face])),
            importer: FakeImporter(staged: [.success(StagedPhoto(url: staged, displayName: nil))]))
        try await importOne(model, staged)
        model.edit(.effect(.grain, 1))
        model.edit(.skinRefinement(.darkCircles, 0.5))
        try await waitUntil { !model.isRendering }
        let lines = model.diagnosticLines
        XCTAssertTrue(lines.contains { $0.hasPrefix(UserMessage.diagnosticLabel(.build)) })
        XCTAssertNotEqual(DeviceModel.identifier, DeviceModel.unknown, "기기 모델을 읽는다")
        XCTAssertTrue(
            lines.contains {
                $0.hasPrefix(UserMessage.diagnosticLabel(.device)) && $0.contains(DeviceModel.identifier)
            },
            "기기 줄에 모델 식별자가 있다")
        XCTAssertTrue(lines.contains { $0.contains("faces=1") })
        XCTAssertTrue(lines.contains { $0.contains("preview=") })
        XCTAssertTrue(lines.contains("effects.grain=1.00"))
        XCTAssertTrue(lines.contains("portrait.skin.darkCircles=0.50"))
        XCTAssertFalse(lines.contains { $0.hasPrefix("color.") }, "기본값인 키는 없다")
        XCTAssertEqual(RecipeSummary.nonDefaultLines(EditRecipe()), [])
        var recipe = EditRecipe()
        recipe.portrait.skin.autoBlemish = true
        recipe.makeup.lip = MakeupTint(colorID: "lip-rose", intensity: 0.4)
        XCTAssertEqual(
            Set(RecipeSummary.nonDefaultLines(recipe)),
            ["portrait.skin.autoBlemish=true", "makeup.lip.colorID=lip-rose", "makeup.lip.intensity=0.40"])
    }

    func testDiagnosticRecipeSummaryCollapsesLocalEditsIntoOneCountLine() {
        var recipe = EditRecipe()
        recipe.color.exposure = 0.5
        let spot = RetouchSpot(x: 0.4, y: 0.4, sourceX: 0.5, sourceY: 0.5, radius: 0.02)
        let stroke = WarpStroke(x: 0.3, y: 0.3, dx: 0.01, dy: 0.0, radius: 0.05)
        recipe.operations = [.spot(spot), .spot(spot), .warp(stroke)]
        let lines = RecipeSummary.nonDefaultLines(recipe)
        XCTAssertEqual(lines, ["color.exposure=0.50", "operations=3"], "수동 편집은 점·획마다 줄을 만들지 않고 개수 한 줄이다")
    }

    private func twoFaces() -> [FaceGeometry] {
        [
            TestSupport.landmarkedFace(in: NormalizedRect(x: 0.05, y: 0.3, width: 0.35, height: 0.4)),
            TestSupport.landmarkedFace(in: NormalizedRect(x: 0.55, y: 0.3, width: 0.35, height: 0.4)),
        ]
    }

    /// 복제 샘플과 점 하나를 찍어 사진을 잠근다.
    private func lockWithRetouch(_ model: AppModel) async throws {
        let tool = model.tool
        model.tool = .retouch
        try await waitUntil { !model.isRendering }
        model.touch(from: NormalizedPoint(x: 0.5, y: 0.1), to: NormalizedPoint(x: 0.5, y: 0.1))
        model.touch(from: NormalizedPoint(x: 0.52, y: 0.1), to: NormalizedPoint(x: 0.52, y: 0.1))
        try await waitUntil { !model.isRendering }
        model.tool = tool
        XCTAssertTrue(model.isGeometryLocked)
    }

    func testPersonChipsReflectEstimatesManualGenderAndOverrides() async throws {
        let staged = try TestSupport.solidPNG(in: root)
        let faces = twoFaces()
        let model = TestSupport.makeModel(
            root: root, analyzer: StubFaceAnalyzer(result: .success(faces)),
            genderEstimator: StubGenderEstimator(
                result: .success([GenderEstimate(gender: .female, confidence: 0.9), nil])),
            importer: FakeImporter(staged: [.success(StagedPhoto(url: staged, displayName: nil))]))
        try await importOne(model, staged)
        XCTAssertEqual(model.selectedInfo?.genders, [.female, nil])
        var chips = model.personChips
        XCTAssertEqual(chips.map(\.faceIndex), [0, 1])
        XCTAssertEqual(chips.map(\.target), [.face(0), .face(1)])
        XCTAssertEqual(chips[0].gender, .female)
        XCTAssertEqual(chips[0].source, .estimated)
        XCTAssertEqual(chips[1].source, .none)
        XCTAssertEqual(chips.map(\.overriddenCount), [0, 0])
        XCTAssertEqual(model.effectiveGender(forFace: 0), .female)
        XCTAssertEqual(model.genderSource(forFace: 1), .none)
        model.setBeautyTarget(.gender(.female))
        model.edit(.skinSmoothing(0.4))
        model.setBeautyTarget(.face(0))
        XCTAssertEqual(model.scopedValues.portrait.skin.smoothing, 0.4, "기록이 없어도 추정 성별의 그룹 값을 보인다")
        model.setBeautyTarget(.face(1))
        model.setGender(.male)
        chips = model.personChips
        XCTAssertEqual(chips[1].gender, .male)
        XCTAssertEqual(chips[1].source, .manual)
        XCTAssertNotNil(chips[1].personID)
        XCTAssertEqual(model.session.selected?.document.undoStack.count, 2)
        model.setBeautyTarget(.face(0))
        model.setGender(.male)
        XCTAssertEqual(model.personChips[0].source, .manual, "추정 위에 수동 지정")
        XCTAssertEqual(model.effectiveGender(forFace: 0), .male)
        model.setBeautyTarget(.gender(.male))
        model.beginSliderEdit()
        model.edit(.skinSmoothing(0.6))
        model.endSliderEdit()
        XCTAssertEqual(model.scopedValues.portrait.skin.smoothing, 0.6)
        XCTAssertEqual(model.overriddenKeys, [.skinSmoothing])
        model.setBeautyTarget(.face(1))
        XCTAssertEqual(model.scopedValues.portrait.skin.smoothing, 0.6, "남성 그룹 값을 상속한다")
        XCTAssertEqual(model.overriddenKeys, [], "상속 중이라 덮어쓴 키가 없다")
        model.edit(.faceShape(.width, -0.3))
        XCTAssertEqual(model.overriddenKeys, [.faceShape(.width)])
        XCTAssertEqual(model.personChips[1].overriddenCount, 1)
        model.setBeautyTarget(.all)
        XCTAssertEqual(model.scopedValues.portrait.skin.smoothing, 0, "전체 층은 그룹 값을 모른다")
        XCTAssertEqual(model.overriddenKeys, [])
        try await waitUntil { !model.isRendering }
        XCTAssertNil(model.presentedError)
    }

    func testGenderAndResetAreRoutedToTheCurrentTargetAndUndoOneStep() async throws {
        let staged = try TestSupport.solidPNG(in: root)
        let model = TestSupport.makeModel(
            root: root, analyzer: StubFaceAnalyzer(result: .success(twoFaces())),
            importer: FakeImporter(staged: [.success(StagedPhoto(url: staged, displayName: nil))]))
        try await importOne(model, staged)
        model.setBeautyTarget(.all)
        model.setGender(.female)
        XCTAssertTrue(model.currentRecipe.people.individuals.isEmpty, "전체·그룹 대상에서는 성별 지정이 없다")
        XCTAssertFalse(model.canUndo)
        model.setBeautyTarget(.gender(.female))
        model.edit(.skinSmoothing(0.5))
        model.edit(.feature(.eyeBrighten, 0.4))
        XCTAssertEqual(model.overriddenKeys, [.skinSmoothing, .feature(.eyeBrighten)])
        model.resetOverrides([.skinSmoothing])
        XCTAssertEqual(model.overriddenKeys, [.feature(.eyeBrighten)])
        XCTAssertEqual(model.session.selected?.document.undoStack.count, 3)
        model.resetOverrides()
        XCTAssertEqual(model.overriddenKeys, [])
        XCTAssertNil(model.currentRecipe.people.groups[.female])
        model.undo()
        XCTAssertEqual(model.overriddenKeys, [.feature(.eyeBrighten)])
        model.setBeautyTarget(.face(0))
        model.resetOverrides()
        XCTAssertEqual(model.session.selected?.document.undoStack.count, 3, "기록이 없는 얼굴의 초기화는 아무것도 안 한다")
        model.edit(.faceShape(.width, -0.2))
        try await lockWithRetouch(model)
        model.setGender(.male)
        XCTAssertEqual(model.statusMessage, UserMessage.geometryLocked, "잠긴 사진의 성별 변경은 안내만")
        XCTAssertNil(model.personChips[0].gender)
    }

    func testCanvasTapSelectsTheFaceAndLegacyPeopleAreBoundOnPrepare() async throws {
        let staged = try TestSupport.solidPNG(in: root)
        let big = TestSupport.landmarkedFace(in: NormalizedRect(x: 0.1, y: 0.1, width: 0.6, height: 0.7))
        let small = TestSupport.landmarkedFace(in: NormalizedRect(x: 0.4, y: 0.3, width: 0.2, height: 0.25))
        let store = MemorySessionStore()
        let model = TestSupport.makeModel(
            root: root, analyzer: StubFaceAnalyzer(result: .success([big, small])),
            importer: FakeImporter(staged: [.success(StagedPhoto(url: staged, displayName: nil))]), store: store)
        try await importOne(model, staged)
        XCTAssertTrue(EditorTool.beauty.usesCanvasTouch)
        XCTAssertTrue(EditorTool.makeup.usesCanvasTouch)
        model.selectTool(.beauty)
        model.touch(from: NormalizedPoint(x: 0.5, y: 0.4), to: NormalizedPoint(x: 0.5, y: 0.4))
        XCTAssertEqual(model.beautyTarget, .face(1), "겹친 영역은 작은 상자(앞사람)")
        model.touch(from: NormalizedPoint(x: 0.15, y: 0.15), to: NormalizedPoint(x: 0.15, y: 0.15))
        XCTAssertEqual(model.beautyTarget, .face(0))
        model.touch(from: NormalizedPoint(x: 0.95, y: 0.95), to: NormalizedPoint(x: 0.95, y: 0.95))
        XCTAssertEqual(model.beautyTarget, .all, "얼굴 밖은 전체")
        model.selectTool(.makeup)
        model.touch(from: NormalizedPoint(x: 0.5, y: 0.4), to: NormalizedPoint(x: 0.5, y: 0.4))
        XCTAssertEqual(model.beautyTarget, .face(1))
        XCTAssertFalse(model.canUndo, "대상 선택은 편집이 아니다")
        model.selectTool(.adjust)
        model.touch(from: NormalizedPoint(x: 0.15, y: 0.15), to: NormalizedPoint(x: 0.15, y: 0.15))
        XCTAssertEqual(model.beautyTarget, .face(1), "다른 도구에서는 바뀌지 않는다")

        var legacy = EditRecipe()
        legacy.people.individuals = [
            PersonRecord(id: .legacy(index: 1), legacyIndex: 1, layer: PortraitLayer(skinSmoothing: 0.4))
        ]
        let id = model.session.photos[0].id
        let filename = model.session.photos[0].filename
        store.saved = SessionSnapshot(
            photos: [PhotoEntry(id: id, filename: filename, displayName: "옛", document: EditDocument(recipe: legacy))],
            selectedPhotoID: id, presets: [])
        let reopened = TestSupport.makeModel(
            root: root, analyzer: StubFaceAnalyzer(result: .success([big, small])), store: store)
        await reopened.restore()
        try await waitUntil { reopened.isReady && reopened.preview != nil }
        let bound = try XCTUnwrap(reopened.currentRecipe.people.individuals.first)
        XCTAssertEqual(bound.anchor, PersonAnchor(faceBox: small.boundingBox), "준비 뒤 legacy 기록에 anchor가 채워진다")
        XCTAssertNil(bound.legacyIndex)
        XCTAssertFalse(reopened.canUndo, "연결은 체크포인트가 아니다")
        XCTAssertEqual(reopened.personChips[1].personID, bound.id)
        XCTAssertEqual(reopened.personChips[1].overriddenCount, 1)
    }

    func testUnmatchedPersonCanBeReboundOrRemovedAndLookAppliesToAFace() async throws {
        let staged = try TestSupport.solidPNG(in: root)
        let model = TestSupport.makeModel(
            root: root, analyzer: StubFaceAnalyzer(result: .success(twoFaces())),
            importer: FakeImporter(staged: [.success(StagedPhoto(url: staged, displayName: nil))]))
        try await importOne(model, staged)
        model.session.edit(model.session.photos[0].id) { document in
            // 사진의 어느 얼굴과도 짝이 되지 않는 상자(중심 0.5·0.97, 폭 0.03)에 기록을 만든다.
            let stray = NormalizedRect(x: 0.485, y: 0.955, width: 0.03, height: 0.03)
            return document.set(.skinSmoothing(0.8), forFace: 0, of: [stray])
        }
        let stray = try XCTUnwrap(model.currentRecipe.people.individuals.first)
        var chips = model.personChips
        XCTAssertEqual(chips.count, 3)
        XCTAssertTrue(chips[2].isUnmatched)
        XCTAssertEqual(chips[2].personID, stray.id)
        XCTAssertEqual(chips[2].target, .person(stray.id))
        XCTAssertEqual(model.unpairedFaceIndices, [0, 1])
        model.setBeautyTarget(.person(stray.id))
        XCTAssertEqual(model.scopedValues.portrait.skin.smoothing, 0.8)
        XCTAssertEqual(model.faceAvailability, .ready, "짝이 없는 사람은 얼굴이 없지만 분석 실패가 아니다")
        model.rebindPerson(stray.id, toFace: 0)
        chips = model.personChips
        XCTAssertEqual(chips.count, 2)
        XCTAssertEqual(chips[0].personID, stray.id)
        XCTAssertEqual(model.unpairedFaceIndices, [1])
        XCTAssertEqual(model.beautyTarget, .face(0), "연결한 얼굴이 대상이 된다")
        XCTAssertEqual(model.session.selected?.document.undoStack.count, 2)
        model.removePerson(stray.id)
        XCTAssertTrue(model.currentRecipe.people.individuals.isEmpty)
        XCTAssertEqual(model.beautyTarget, .all, "지운 사람이 대상이었으면 전체로")
        model.setBeautyTarget(.face(1))
        model.applyMakeupLook(id: "daily")
        XCTAssertEqual(model.currentRecipe.people.individuals.count, 1, "기록이 없던 얼굴에 룩을 적용하면 기록이 생긴다")
        XCTAssertEqual(model.scopedValues.makeup.lookID, "daily")
        XCTAssertEqual(model.currentRecipe.makeup, MakeupAdjustments(), "전체 층은 그대로")
        model.undo()
        XCTAssertTrue(model.currentRecipe.people.individuals.isEmpty, "실행 취소 한 번에 기록이 사라진다")
    }

    func testLockedPhotoRefusesEditsThatMoveFaceShapeOntoAnotherFace() async throws {
        let staged = try TestSupport.solidPNG(in: root)
        let faces = twoFaces()
        let model = TestSupport.makeModel(
            root: root, analyzer: StubFaceAnalyzer(result: .success(faces)),
            importer: FakeImporter(staged: [.success(StagedPhoto(url: staged, displayName: nil))]))
        try await importOne(model, staged)
        let left = faces[0].boundingBox
        // owner가 왼쪽 얼굴을 갖고, shaped는 같은 얼굴에 조금 덜 가까워 짝이 없다.
        let owner = PersonRecord(anchor: PersonAnchor(faceBox: left), layer: PortraitLayer(skinSmoothing: 0.5))
        let shaped = PersonRecord(
            anchor: PersonAnchor(x: left.midX + 0.05, y: left.midY, width: left.width),
            layer: PortraitLayer(face: [.width: -0.2]))
        model.session.edit(model.session.photos[0].id) { document in
            document = EditDocument(recipe: EditRecipe(people: PeopleAdjustments(individuals: [owner, shaped])))
            return nil
        }
        XCTAssertEqual(model.personChips.map(\.personID), [owner.id, nil, shaped.id])
        try await lockWithRetouch(model)
        let locked = model.currentRecipe
        model.statusMessage = ""
        model.removePerson(owner.id)
        XCTAssertEqual(model.statusMessage, UserMessage.geometryLocked, "지우면 shaped가 왼쪽 얼굴에 붙어 얼굴형이 옮겨 간다")
        XCTAssertEqual(model.currentRecipe, locked)
        model.setBeautyTarget(.face(0))
        model.statusMessage = ""
        model.resetOverrides()
        XCTAssertEqual(model.statusMessage, UserMessage.geometryLocked, "층을 비워 기록이 지워지는 재설정도 같다")
        XCTAssertEqual(model.currentRecipe, locked)
        model.edit(.skinSmoothing(0.7))
        XCTAssertEqual(model.currentRecipe.people.person(owner.id)?.layer.skinSmoothing, 0.7, "짝이 그대로인 편집은 된다")
        model.undo()
        model.undo()
        XCTAssertFalse(model.isGeometryLocked, "실행 취소는 검사하지 않는다")
        model.removePerson(owner.id)
        XCTAssertNil(model.currentRecipe.people.person(owner.id), "잠기지 않은 사진은 지울 수 있다")
    }

    func testOneTouchRoutesToTheCurrentTargetAndRemembersStrength() async throws {
        let staged = try TestSupport.solidPNG(in: root)
        let model = TestSupport.makeModel(
            root: root, analyzer: StubFaceAnalyzer(result: .success(twoFaces())),
            importer: FakeImporter(staged: [.success(StagedPhoto(url: staged, displayName: nil))]))
        try await importOne(model, staged)
        XCTAssertFalse(model.showsDetailAdjustments, "세부 조정은 접혀서 시작")
        XCTAssertNil(model.oneTouchStrength)
        model.applyOneTouch()
        XCTAssertEqual(model.oneTouchStrength, EditingPolicy.oneTouchDefaultStrength)
        XCTAssertEqual(model.currentRecipe.people.groups[.female]?.oneTouch, EditingPolicy.oneTouchDefaultStrength)
        XCTAssertEqual(
            model.currentRecipe.bodySkin.brightness,
            OneTouchBundle.Table.bodyBrightness * EditingPolicy.oneTouchDefaultStrength, accuracy: 1e-12)
        XCTAssertEqual(model.session.selected?.document.undoStack.count, 1, "세 층 + 몸 피부가 한 단계")
        XCTAssertTrue(model.isOneTouchTagged(.skinRefinement(.darkCircles)))
        XCTAssertFalse(model.isOneTouchTagged(.faceShape(.width)), "얼굴형은 묶음 밖")
        model.setBeautyTarget(.face(0))
        XCTAssertNil(model.oneTouchStrength, "개인 층에는 표시가 없다(그룹 값 상속)")
        XCTAssertFalse(model.isOneTouchTagged(.skinRefinement(.darkCircles)), "상속 중인 표시는 꼬리표가 아니다")
        model.setGender(.female)
        model.beginSliderEdit()
        model.applyOneTouch(strength: 0.3)
        model.applyOneTouch(strength: 1)
        model.endSliderEdit()
        XCTAssertEqual(model.oneTouchStrength, 1)
        let person = try XCTUnwrap(model.currentRecipe.people.individuals.first)
        XCTAssertEqual(person.layer, OneTouchBundle.layer(for: .female, strength: 1), "사람 대상은 그 사람의 성별 표")
        XCTAssertEqual(model.session.selected?.document.undoStack.count, 3, "원터치 1 + 성별 지정 1 + 드래그 1")
        XCTAssertEqual(
            model.currentRecipe.bodySkin.brightness,
            OneTouchBundle.Table.bodyBrightness * EditingPolicy.oneTouchDefaultStrength, accuracy: 1e-12,
            "사람 대상은 몸 피부를 쓰지 않는다")
        model.setBeautyTarget(.all)
        XCTAssertEqual(model.oneTouchStrength, EditingPolicy.oneTouchDefaultStrength, "전체 층 표시는 그대로")
        model.edit(.skinRefinement(.darkCircles, 0.1))
        XCTAssertNil(model.oneTouchStrength, "묶인 키를 손으로 바꾸면 표시가 사라진다")
        XCTAssertFalse(model.isOneTouchTagged(.skinRefinement(.darkCircles)))
        XCTAssertEqual(
            model.currentRecipe.people.groups[.male]?.oneTouch, EditingPolicy.oneTouchDefaultStrength, "그룹 표시는 남는다")
        model.applyOneTouch()
        XCTAssertEqual(model.oneTouchStrength, EditingPolicy.oneTouchDefaultStrength, "표시가 없으면 기본 강도로 다시 적용")
        model.setBeautyTarget(.gender(.male))
        XCTAssertEqual(model.oneTouchStrength, EditingPolicy.oneTouchDefaultStrength)
        model.applyOneTouch(strength: 0)
        XCTAssertNil(model.currentRecipe.people.groups[.male], "강도 0은 그룹의 묶인 키를 지운다")
        XCTAssertNil(model.oneTouchStrength)
        model.setBeautyTarget(.all)
        try await lockWithRetouch(model)
        model.applyOneTouch(strength: 1)
        XCTAssertEqual(model.oneTouchStrength, 1, "잠긴 사진에서도 원터치는 된다")
        XCTAssertEqual(model.currentRecipe.portrait.face, FaceShapeAdjustments())
        try await waitUntil { !model.isRendering }
        XCTAssertNil(model.presentedError)
        model.showsDetailAdjustments = true
        model.select(model.session.photos[0].id)
        XCTAssertTrue(model.showsDetailAdjustments, "접기 상태는 사진과 무관")
    }

    func testOneTouchButtonEndsAnOpenDragAndStrengthIsClampedForTheSlider() async throws {
        let staged = try TestSupport.solidPNG(in: root)
        let model = TestSupport.makeModel(
            root: root, analyzer: StubFaceAnalyzer(result: .success(twoFaces())),
            importer: FakeImporter(staged: [.success(StagedPhoto(url: staged, displayName: nil))]))
        try await importOne(model, staged)
        model.beginSliderEdit()
        model.edit(.skinSmoothing(0.2))
        model.applyOneTouch()
        XCTAssertFalse(model.isSliderEditActive, "버튼은 열린 드래그를 먼저 끝낸다")
        XCTAssertEqual(model.session.selected?.document.undoStack.count, 2, "드래그 1 + 원터치 1")
        XCTAssertTrue(model.isOneTouchTagged(.brightness), "몸 피부 밝기는 전체 층 표시에 묶인다")
        XCTAssertFalse(model.isOneTouchTagged(.tone))
        model.setBeautyTarget(.gender(.female))
        XCTAssertTrue(model.isOneTouchTagged(.brightness), "몸 피부는 사진 단위라 대상과 무관")
        var corrupted = model.currentRecipe
        corrupted.portrait.oneTouch = 3
        corrupted.people.groups[.female]?.oneTouch = -1
        model.session.edit(model.session.photos[0].id) { document in
            document = EditDocument(recipe: corrupted)
            return nil
        }
        XCTAssertEqual(model.oneTouchStrength, 0, "손상 파일 값도 0…1로 잘라 슬라이더에 넘긴다")
        model.setBeautyTarget(.all)
        XCTAssertEqual(model.oneTouchStrength, OneTouchBundle.maximumStrength)
        XCTAssertTrue(UserMessage.oneTouchHintAll.contains("립"), "전체 안내는 그룹 층이 메이크업도 가린다고 말한다")
        XCTAssertTrue(UserMessage.oneTouchHintGroup.contains("몸 피부"), "그룹 원터치는 몸 피부를 쓰지 않는다")
        XCTAssertTrue(UserMessage.oneTouchHintPerson.contains("몸 피부"), "사람 원터치는 몸 피부를 쓰지 않는다")
    }

    func testAutoEnhanceIncludesOneTouchOnlyWhenFacesExist() async throws {
        XCTAssertTrue(AppModel.Policy.autoIncludesOneTouch)
        let staged = try TestSupport.solidPNG(in: root)
        let model = TestSupport.makeModel(
            root: root, analyzer: StubFaceAnalyzer(result: .success(twoFaces())),
            importer: FakeImporter(staged: [.success(StagedPhoto(url: staged, displayName: nil))]))
        try await importOne(model, staged)
        await model.autoEnhance()
        try await waitUntil { !model.isRendering }
        XCTAssertEqual(model.oneTouchStrength, EditingPolicy.oneTouchDefaultStrength, "자동이 원터치를 포함한다")
        XCTAssertEqual(model.currentRecipe.people.groups[.female]?.oneTouch, EditingPolicy.oneTouchDefaultStrength)
        XCTAssertEqual(model.session.selected?.document.undoStack.count, 1)
        XCTAssertEqual(model.statusMessage, UserMessage.autoEnhanced)
        let otherRoot = try TestSupport.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: otherRoot) }
        let faceless = try TestSupport.solidPNG(in: otherRoot, name: "faceless")
        let plain = TestSupport.makeModel(
            root: otherRoot, importer: FakeImporter(staged: [.success(StagedPhoto(url: faceless, displayName: nil))]))
        try await importOne(plain, faceless)
        await plain.autoEnhance()
        try await waitUntil { !plain.isRendering }
        XCTAssertNil(plain.oneTouchStrength, "얼굴이 없으면 색감만")
        XCTAssertTrue(plain.currentRecipe.people.groups.isEmpty)
        XCTAssertEqual(plain.currentRecipe.portrait, PortraitAdjustments())
        XCTAssertNotEqual(plain.currentRecipe, EditRecipe(), "색감·디테일은 바뀐다")
        XCTAssertNil(plain.presentedError)
    }

    func testScopedPanelValuesShowInheritedAndOverriddenKeysPerTarget() async throws {
        let staged = try TestSupport.solidPNG(in: root)
        let faces = twoFaces()
        let model = TestSupport.makeModel(
            root: root, analyzer: StubFaceAnalyzer(result: .success(faces)),
            importer: FakeImporter(staged: [.success(StagedPhoto(url: staged, displayName: nil))]))
        try await importOne(model, staged)
        model.edit(.skinSmoothing(0.2))
        model.setBeautyTarget(.face(0))
        model.setGender(.female)
        model.setBeautyTarget(.gender(.female))
        model.applyMakeupLook(id: "daily")
        XCTAssertEqual(model.scopedValues.makeup.lookID, "daily")
        XCTAssertEqual(model.overriddenKeys, PortraitKey.makeup)
        model.setBeautyTarget(.face(0))
        XCTAssertEqual(model.scopedValues.makeup.lookID, "daily", "여성 그룹의 룩을 상속")
        XCTAssertEqual(model.scopedValues.portrait.skin.smoothing, 0.2, "전체 층의 피부를 상속")
        XCTAssertEqual(model.overriddenKeys, [])
        model.edit(.makeupIntensity(.lip, 0.9))
        XCTAssertEqual(model.overriddenKeys, [.makeupPart(.lip)])
        XCTAssertNil(model.scopedValues.makeup.lookID, "부위를 바꾸면 그 층의 룩 선택이 풀린다")
        model.resetOverrides([.makeupPart(.lip)])
        XCTAssertEqual(model.scopedValues.makeup.lookID, "daily")
        XCTAssertEqual(UserMessage.scopeHint(for: .face(0)), UserMessage.scopeHintPerson)
        XCTAssertEqual(UserMessage.scopeHint(for: .gender(.male)), UserMessage.scopeHintGroup)
        XCTAssertNil(UserMessage.scopeHint(for: .all))
    }

    /// 리뷰 Important 1·Minor 5: 뷰티·메이크업 캔버스는 탭만 대상 고르기이고, 이동(드래그)은 무시하며, 렌더 중에도 받는다.
    func testTargetTapIgnoresDragsAndIsNotBlockedByRendering() async throws {
        let staged = try TestSupport.solidPNG(in: root)
        let model = TestSupport.makeModel(
            root: root, analyzer: StubFaceAnalyzer(result: .success(twoFaces())),
            importer: FakeImporter(staged: [.success(StagedPhoto(url: staged, displayName: nil))]))
        try await importOne(model, staged)
        try await waitUntil { !model.isRendering }
        XCTAssertTrue(EditorTool.beauty.selectsTargetByTap)
        XCTAssertTrue(EditorTool.makeup.selectsTargetByTap)
        XCTAssertFalse(EditorTool.retouch.selectsTargetByTap)
        XCTAssertFalse(EditorTool.warp.selectsTargetByTap)
        model.selectTool(.beauty)
        let left = NormalizedPoint(x: 0.2, y: 0.5)
        let right = NormalizedPoint(x: 0.7, y: 0.5)
        model.touch(from: left, to: left)
        XCTAssertEqual(model.beautyTarget, .face(0))
        model.touch(from: left, to: right)
        XCTAssertEqual(model.beautyTarget, .face(0), "오른쪽 얼굴까지 끈 이동은 탭이 아니다")
        model.touch(from: left, to: NormalizedPoint(x: 0.95, y: 0.95))
        XCTAssertEqual(model.beautyTarget, .face(0), "얼굴 밖에서 끝난 이동도 대상을 전체로 바꾸지 않는다")
        let jitter = AppModel.Policy.targetTapTolerance / 2
        model.touch(from: right, to: NormalizedPoint(x: right.x + jitter, y: right.y))
        XCTAssertEqual(model.beautyTarget, .face(1), "허용 오차 안의 흔들림은 탭이다")
        model.isRendering = true
        model.touch(from: left, to: left)
        XCTAssertEqual(model.beautyTarget, .face(0), "대상 고르기는 편집이 아니라 렌더 중에도 받는다")
        model.selectTool(.retouch)
        model.touch(from: left, to: left)
        XCTAssertNil(model.cloneSource, "잡티 탭은 렌더 중에 여전히 막는다")
        model.isRendering = false
        XCTAssertFalse(model.canUndo)
    }

    /// 리뷰 Minor 3: 기억한 대상이 없어진 사람이나 범위 밖 얼굴이면 전체로 읽는다.
    func testStaleTargetFallsBackToAll() async throws {
        let staged = try TestSupport.solidPNG(in: root)
        let model = TestSupport.makeModel(
            root: root, analyzer: StubFaceAnalyzer(result: .success(twoFaces())),
            importer: FakeImporter(staged: [.success(StagedPhoto(url: staged, displayName: nil))]))
        try await importOne(model, staged)
        model.setBeautyTarget(.face(5))
        XCTAssertEqual(model.beautyTarget, .all, "범위 밖 얼굴")
        model.setBeautyTarget(.person(PersonID()))
        XCTAssertEqual(model.beautyTarget, .all, "없는 사람")
        model.session.edit(model.session.photos[0].id) { document in
            let stray = NormalizedRect(x: 0.485, y: 0.955, width: 0.03, height: 0.03)
            return document.set(.skinSmoothing(0.8), forFace: 0, of: [stray])
        }
        let stray = try XCTUnwrap(model.currentRecipe.people.individuals.first)
        model.setBeautyTarget(.person(stray.id))
        XCTAssertEqual(model.beautyTarget, .person(stray.id))
        model.undo()
        XCTAssertTrue(model.currentRecipe.people.individuals.isEmpty)
        XCTAssertEqual(model.beautyTarget, .all, "실행 취소로 사라진 사람이 대상이면 전체")
        model.edit(.skinSmoothing(0.3))
        XCTAssertEqual(model.currentRecipe.portrait.skin.smoothing, 0.3, "편집이 조용히 버려지지 않고 전체 층에 간다")
    }

    /// 리뷰 Minor 4: 성별 지우기·바꾸기, 사진을 오가도 대상 기억, 기록 없는 얼굴의 원터치 드래그 한 단계,
    /// 자동·원터치 실행 취소, 기록이 있는 얼굴로의 연결 무시.
    func testGenderChangesTargetMemoryOneTouchDragUndoAndRebindGuard() async throws {
        let first = try TestSupport.solidPNG(in: root, name: "first")
        let second = try TestSupport.solidPNG(in: root, name: "second")
        let model = TestSupport.makeModel(
            root: root, analyzer: StubFaceAnalyzer(result: .success(twoFaces())),
            importer: FakeImporter(staged: [
                .success(StagedPhoto(url: first, displayName: nil)),
                .success(StagedPhoto(url: second, displayName: nil)),
            ]))
        await model.importFromFiles([first, second])
        try await waitUntil { model.isReady && model.preview != nil && model.session.photos.count == 2 }
        let firstID = model.session.photos[0].id
        let secondID = model.session.photos[1].id
        if model.session.selectedPhotoID != firstID {
            model.select(firstID)
            try await waitUntil { model.isReady && model.session.selectedPhotoID == firstID }
        }
        let pristine = model.currentRecipe
        XCTAssertEqual(pristine, EditRecipe())

        // 성별: 남성 → 여성 → 미지정.
        model.setBeautyTarget(.face(0))
        model.setGender(.male)
        XCTAssertEqual(model.personChips[0].gender, .male)
        model.setGender(.female)
        XCTAssertEqual(model.personChips[0].gender, .female)
        XCTAssertEqual(model.personChips[0].source, .manual)
        model.setGender(nil)
        XCTAssertNil(model.personChips[0].gender)
        XCTAssertEqual(model.personChips[0].source, .none)
        XCTAssertEqual(model.session.selected?.document.undoStack.count, 3)
        model.undo()
        model.undo()
        model.undo()
        XCTAssertEqual(model.currentRecipe, pristine)

        // 대상 기억: 다른 사진은 전체, 돌아오면 그대로.
        model.setBeautyTarget(.face(1))
        model.select(secondID)
        try await waitUntil { model.isReady && model.session.selectedPhotoID == secondID && !model.faces.isEmpty }
        XCTAssertEqual(model.beautyTarget, .all)
        model.select(firstID)
        try await waitUntil { model.isReady && model.session.selectedPhotoID == firstID && !model.faces.isEmpty }
        XCTAssertEqual(model.beautyTarget, .face(1), "사진마다 대상을 기억한다")

        // 기록 없는 얼굴의 원터치 드래그는 기록을 만들며 한 단계다.
        XCTAssertTrue(model.currentRecipe.people.individuals.isEmpty)
        model.beginSliderEdit()
        model.applyOneTouch(strength: 0.3)
        model.applyOneTouch(strength: 0.5)
        model.endSliderEdit()
        XCTAssertEqual(model.currentRecipe.people.individuals.count, 1)
        XCTAssertEqual(model.oneTouchStrength, 0.5)
        XCTAssertEqual(model.session.selected?.document.undoStack.count, 1, "연속 변경 한 단계")
        model.undo()
        XCTAssertEqual(model.currentRecipe, pristine, "실행 취소 한 번에 기록까지 사라진다")

        // 원터치 버튼(전체)과 자동은 실행 취소 한 번에 기본 레시피로.
        model.setBeautyTarget(.all)
        model.applyOneTouch()
        XCTAssertNotEqual(model.currentRecipe, pristine)
        model.undo()
        XCTAssertEqual(model.currentRecipe, pristine)
        try await waitUntil { !model.isRendering }
        await model.autoEnhance()
        XCTAssertNotNil(model.currentRecipe.people.groups[.male]?.oneTouch)
        model.undo()
        XCTAssertEqual(model.currentRecipe, pristine)

        // 기록이 있는 얼굴로는 연결하지 않는다.
        model.setBeautyTarget(.face(0))
        model.setGender(.female)
        model.session.edit(firstID) { document in
            let stray = NormalizedRect(x: 0.485, y: 0.955, width: 0.03, height: 0.03)
            return document.set(.skinSmoothing(0.8), forFace: 0, of: [stray])
        }
        let stray = try XCTUnwrap(model.personChips.first(where: \.isUnmatched)?.personID)
        let before = model.currentRecipe
        let steps = model.session.selected?.document.undoStack.count
        model.rebindPerson(stray, toFace: 0)
        XCTAssertEqual(model.currentRecipe, before, "이미 기록과 짝인 얼굴")
        XCTAssertEqual(model.session.selected?.document.undoStack.count, steps)
        XCTAssertEqual(model.beautyTarget, .face(0))
        try await waitUntil { !model.isRendering }
        XCTAssertNil(model.presentedError)
    }
}

/// 비교 화면 원본 다시 그리기를 붙잡아 두는 문. open() 전까지 기다리고, fails면 바로 실패한다.
@MainActor
private final class OriginalRenderGate {
    var fails = false
    private(set) var calls = 0
    private var isOpen = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func pass() async throws {
        calls += 1
        if fails {
            throw MellowError.renderFailed
        }
        guard !isOpen else { return }
        await withCheckedContinuation { waiters.append($0) }
    }

    func open() {
        isOpen = true
        for waiter in waiters {
            waiter.resume()
        }
        waiters.removeAll()
    }
}
