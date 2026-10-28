import MellowEditing
import MellowLibrary
import MellowRendering
import MellowShared
import XCTest

@testable import Mellow_Photo

@MainActor
final class PortraitPurposeActionTests: XCTestCase {
    private func makeModel() async throws -> (AppModel, URL, MemorySessionStore) {
        let root = try TestSupport.temporaryDirectory()
        let file = try TestSupport.solidPNG(in: root)
        let face = TestSupport.landmarkedFace(in: NormalizedRect(x: 0.2, y: 0.2, width: 0.6, height: 0.6))
        let store = MemorySessionStore()
        let model = TestSupport.makeModel(
            root: root, analyzer: StubFaceAnalyzer(result: .success([face])),
            importer: FakeImporter(passesThroughFileURLs: true), store: store)
        await model.importFromFiles([file])
        try await waitUntil { model.isReady && !model.isRendering }
        return (model, root, store)
    }

    func testPurposeUsesActualPreparationAndCommitsOneUndoThenMatchingPreview() async throws {
        let (model, root, store) = try await makeModel()
        defer {
            model.stopWork()
            try? FileManager.default.removeItem(at: root)
        }
        model.edit(.exposure(0.2))
        let before = model.session.selected!.document
        let saves = store.saveCount
        let plan = try XCTUnwrap(model.planPortraitPurpose(.skin, strength: 1, replacingExisting: false))
        XCTAssertGreaterThan(plan.result.changedCount, 0, "실제 준비된 마스크가 없는 테스트는 적용 성공으로 취급하지 않는다")
        XCTAssertTrue(model.applyPortraitPurpose(plan))
        XCTAssertEqual(model.currentRecipe.color, before.recipe.color)
        XCTAssertEqual(model.currentRecipe.makeup, before.recipe.makeup)
        XCTAssertEqual(model.currentRecipe.bodySkin, before.recipe.bodySkin)
        XCTAssertEqual(model.session.selected!.document.undoStack.count, before.undoStack.count + 1)
        XCTAssertEqual(store.saveCount, saves + 1)
        XCTAssertEqual(model.portraitPurposeApplication?.phase, .rendering)
        try await waitUntil { !model.isRendering }
        XCTAssertEqual(model.portraitPurposeApplication?.phase, .visible)
        let applied = model.currentRecipe
        model.undo()
        XCTAssertEqual(model.currentRecipe, before.recipe)
        model.redo()
        XCTAssertEqual(model.currentRecipe, applied)
        let restored = ProjectSession(store: store, maxPhotos: 40)
        try restored.restore()
        XCTAssertEqual(restored.selected?.document.recipe, applied)
    }

    func testStalePlanNoOpAndUnavailableNeverSaveOrCreateMetadata() async throws {
        let (model, root, store) = try await makeModel()
        defer {
            model.stopWork()
            try? FileManager.default.removeItem(at: root)
        }
        let plan = try XCTUnwrap(model.planPortraitPurpose(.skin, strength: 1, replacingExisting: false))
        model.setBeautyTarget(.gender(.female))
        model.setBeautyTarget(.all)
        let before = model.session.selected!.document
        let saves = store.saveCount
        XCTAssertFalse(model.applyPortraitPurpose(plan), "대상 A-B-A 후에도 옛 계획은 적용하지 않는다")
        XCTAssertEqual(model.session.selected!.document, before)
        XCTAssertEqual(store.saveCount, saves)
        XCTAssertFalse(model.applyPortraitPurpose(.skin, strength: 0, replacingExisting: true))
        XCTAssertFalse(model.applyPortraitPurpose(.sideChest, strength: 1, replacingExisting: true))
        XCTAssertEqual(model.session.selected!.document, before)
        XCTAssertEqual(store.saveCount, saves)
        let id = model.session.selectedPhotoID!
        let info = model.selectedInfo!
        model.remember(
            id,
            PreparedPhoto(
                pixelSize: info.pixelSize, thumbnail: model.thumbnails[id]!,
                faces: info.faces, faceAnalysisFailure: nil), bindsLegacyPeople: false)
        XCTAssertFalse(
            model.applyPortraitPurpose(.skin, strength: 1, replacingExisting: true),
            "얼굴 수가 같아도 실제 준비된 키가 없으면 적용하지 않는다")
        XCTAssertEqual(model.session.selected!.document, before)
        XCTAssertEqual(store.saveCount, saves)
    }

    func testPurposeDrainsSliderAndKeepsItsOwnUndoSeparate() async throws {
        let (model, root, _) = try await makeModel()
        defer {
            model.stopWork()
            try? FileManager.default.removeItem(at: root)
        }
        model.selectTool(.adjust)
        model.beginSliderEdit()
        model.edit(.exposure(0.3))
        XCTAssertTrue(model.session.isPersistenceDeferred)
        XCTAssertTrue(model.applyPortraitPurpose(.skin, strength: 1, replacingExisting: false))
        XCTAssertFalse(model.session.isPersistenceDeferred)
        model.undo()
        XCTAssertEqual(model.currentRecipe.color.exposure, 0.3)
        XCTAssertTrue(model.currentRecipe.people.individuals.isEmpty)
        model.undo()
        XCTAssertTrue(model.currentRecipe.isDefault)
    }
    func testAnalysisRefreshAndEditUndoInvalidateOldPlan() async throws {
        let (model, root, store) = try await makeModel()
        defer {
            model.stopWork()
            try? FileManager.default.removeItem(at: root)
        }
        let beforeRefresh = try XCTUnwrap(model.planPortraitPurpose(.skin, strength: 1, replacingExisting: false))
        let id = model.session.selectedPhotoID!
        let info = model.selectedInfo!
        model.remember(
            id,
            PreparedPhoto(
                pixelSize: info.pixelSize, thumbnail: model.thumbnails[id]!, faces: info.faces,
                faceAnalysisFailure: nil, portraitPurposeKeys: info.portraitPurposeKeys), bindsLegacyPeople: false)
        var before = model.session.selected!.document
        var saves = store.saveCount
        XCTAssertFalse(model.applyPortraitPurpose(beforeRefresh))
        XCTAssertEqual(model.session.selected!.document, before)
        XCTAssertEqual(store.saveCount, saves)
        let beforeEdit = try XCTUnwrap(model.planPortraitPurpose(.skin, strength: 1, replacingExisting: false))
        model.edit(.exposure(0.3))
        model.undo()
        before = model.session.selected!.document
        saves = store.saveCount
        XCTAssertFalse(model.applyPortraitPurpose(beforeEdit), "레시피 값이 돌아와도 옛 분석/편집 계획을 재사용하지 않는다")
        XCTAssertEqual(model.session.selected!.document, before)
        XCTAssertEqual(store.saveCount, saves)
    }

    func testPhotoSelectionABACannotApplyAnOldPlan() async throws {
        let (model, root, store) = try await makeModel()
        defer {
            model.stopWork()
            try? FileManager.default.removeItem(at: root)
        }
        let firstID = model.session.selectedPhotoID!
        let plan = try XCTUnwrap(model.planPortraitPurpose(.skin, strength: 1, replacingExisting: false))
        let other = try TestSupport.solidPNG(in: root, name: "second")
        await model.importFromFiles([other])
        try await waitUntil { model.isReady && !model.isRendering }
        model.select(firstID)
        try await waitUntil { model.isReady && !model.isRendering }
        let before = model.session.selected!.document
        let saves = store.saveCount
        XCTAssertFalse(model.applyPortraitPurpose(plan))
        XCTAssertEqual(model.session.selected!.document, before)
        XCTAssertEqual(store.saveCount, saves)
    }

    func testPurposeReceiptDoesNotClaimCurrentEffectAfterUndoOrReselection() async throws {
        let (model, root, _) = try await makeModel()
        defer {
            model.stopWork()
            try? FileManager.default.removeItem(at: root)
        }
        XCTAssertTrue(model.applyPortraitPurpose(.skin, strength: 1, replacingExisting: false))
        try await waitUntil { !model.isRendering }
        XCTAssertEqual(model.portraitPurposeApplication?.phase, .visible)
        model.undo()
        XCTAssertEqual(
            model.portraitPurposeApplication?.phase, .cancelled,
            "실행 취소한 효과를 현재 화면에 완료된 효과라고 남기면 안 된다")
        try await waitUntil { !model.isRendering }
        XCTAssertTrue(model.applyPortraitPurpose(.skin, strength: 1, replacingExisting: false))
        XCTAssertEqual(model.portraitPurposeApplication?.phase, .rendering)
        model.select(model.session.selectedPhotoID!)
        XCTAssertEqual(
            model.portraitPurposeApplication?.phase, .cancelled,
            "다시 선택해도 취소된 예전 요청이 완료 상태로 부활하지 않는다")
        try await waitUntil { model.isReady && !model.isRendering }
        XCTAssertEqual(model.portraitPurposeApplication?.phase, .cancelled)
    }

    func testSaveFailureAndActualRenderFailureAreNotVisibleSuccessOrAutomaticReapplication() async throws {
        let (model, root, store) = try await makeModel()
        defer {
            model.stopWork()
            try? FileManager.default.removeItem(at: root)
        }
        store.saveFailure = .cannotWriteToFolder
        XCTAssertTrue(model.applyPortraitPurpose(.skin, strength: 1, replacingExisting: false))
        let failedSaveRecipe = model.currentRecipe
        let history = model.session.selected!.document.undoStack.count
        try await waitUntil { !model.isRendering }
        XCTAssertEqual(model.portraitPurposeApplication?.phase, .saveFailed)
        XCTAssertEqual(model.currentRecipe, failedSaveRecipe)
        XCTAssertEqual(model.session.selected!.document.undoStack.count, history)
        store.saveFailure = nil
        model.undo()
        try await waitUntil { !model.isRendering }
        let entry = model.session.selected!
        await model.pipeline.evict(entry.id)
        try FileManager.default.removeItem(at: model.copies.url(for: entry.filename))
        XCTAssertTrue(model.applyPortraitPurpose(.skin, strength: 1, replacingExisting: false))
        let failedRenderRecipe = model.currentRecipe
        let failedHistory = model.session.selected!.document.undoStack.count
        try await waitUntil { !model.isRendering }
        XCTAssertEqual(model.portraitPurposeApplication?.phase, .renderFailed)
        XCTAssertNotNil(model.lastRenderFailure)
        XCTAssertEqual(model.currentRecipe, failedRenderRecipe)
        XCTAssertEqual(model.session.selected!.document.undoStack.count, failedHistory)
        model.undo()
        XCTAssertTrue(model.currentRecipe.isDefault)
    }

    func testReanalysisCannotRetainCurrentPurposeReceipt() async throws {
        let (model, root, _) = try await makeModel()
        defer {
            model.stopWork()
            try? FileManager.default.removeItem(at: root)
        }
        XCTAssertTrue(model.applyPortraitPurpose(.skin, strength: 1, replacingExisting: false))
        try await waitUntil { !model.isRendering }
        XCTAssertEqual(model.portraitPurposeApplication?.phase, .visible)
        let id = model.session.selectedPhotoID!
        let info = model.selectedInfo!
        model.remember(
            id,
            PreparedPhoto(
                pixelSize: info.pixelSize, thumbnail: model.thumbnails[id]!, faces: info.faces,
                faceAnalysisFailure: nil, portraitPurposeKeys: [:]), bindsLegacyPeople: false)
        XCTAssertEqual(
            model.portraitPurposeApplication?.phase, .cancelled,
            "분석/준비 상태가 갱신되면 이전 완료 상태는 무효다")
        model.scheduleRender()
        try await waitUntil { !model.isRendering }
        XCTAssertEqual(
            model.portraitPurposeApplication?.phase, .cancelled,
            "새 분석의 렌더 완료가 옛 적용 상태를 부활시키면 안 된다")
    }

    func testPendingPurposeIsCancelledByReanalysisWithoutAnotherEditOrSave() async throws {
        let (model, root, store) = try await makeModel()
        defer {
            model.stopWork()
            try? FileManager.default.removeItem(at: root)
        }
        XCTAssertTrue(model.applyPortraitPurpose(.skin, strength: 1, replacingExisting: false))
        XCTAssertEqual(model.portraitPurposeApplication?.phase, .rendering)
        let id = model.session.selectedPhotoID!
        let info = model.selectedInfo!
        let before = model.session.selected!.document
        let saves = store.saveCount
        model.remember(
            id,
            PreparedPhoto(
                pixelSize: info.pixelSize, thumbnail: model.thumbnails[id]!, faces: info.faces,
                faceAnalysisFailure: nil, portraitPurposeKeys: [:]), bindsLegacyPeople: false)
        XCTAssertEqual(model.portraitPurposeApplication?.phase, .cancelled)
        try await waitUntil { !model.isRendering }
        XCTAssertEqual(model.portraitPurposeApplication?.phase, .cancelled)
        XCTAssertEqual(model.session.selected!.document, before)
        XCTAssertEqual(store.saveCount, saves)
    }

}
