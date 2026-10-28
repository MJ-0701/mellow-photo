import MellowEditing
import MellowLibrary
import MellowRendering
import MellowShared
import XCTest

@testable import Mellow_Photo

@MainActor
final class OneTouchApplicationActionTests: XCTestCase {
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

    func testProtectedPlanAndExplicitReplacementReportActualValuesAndOneTransaction() async throws {
        let (model, root, store) = try await makeModel()
        defer {
            model.stopWork()
            try? FileManager.default.removeItem(at: root)
        }
        model.setBeautyTarget(.face(0))
        model.applyOneTouch(strength: 0.2)
        model.setBeautyTarget(.all)
        try await waitUntil { !model.isRendering }
        let before = model.session.selected!.document
        let saves = store.saveCount
        let protected = try XCTUnwrap(model.planOneTouchApplication(strength: 1, replacingPersonal: false))
        XCTAssertEqual(protected.result.changedCount, 0)
        XCTAssertTrue(protected.result.items.contains { $0.reason == .protectedPersonal })
        // 사진 단위 밝기의 준비/변화는 얼굴 변경과 별도로 보고한다.
        if protected.result.bodySkinChanged {
            XCTAssertTrue(model.applyOneTouchApplication(protected))
            XCTAssertEqual(model.currentRecipe.people.individuals, before.recipe.people.individuals)
            model.undo()
            try await waitUntil { !model.isRendering }
        } else {
            XCTAssertFalse(model.applyOneTouchApplication(protected))
            XCTAssertEqual(store.saveCount, saves)
        }
        let replace = try XCTUnwrap(model.planOneTouchApplication(strength: 1, replacingPersonal: true))
        XCTAssertGreaterThan(replace.result.changedCount, 0)
        let replacementBase = model.session.selected!.document
        let replacementSaves = store.saveCount
        XCTAssertTrue(model.applyOneTouchApplication(replace))
        XCTAssertEqual(store.saveCount, replacementSaves + 1)
        XCTAssertEqual(model.currentRecipe.portrait, replacementBase.recipe.portrait)
        XCTAssertEqual(model.currentRecipe.people.groups, replacementBase.recipe.people.groups)
        XCTAssertEqual(model.currentRecipe.bodySkin, replacementBase.recipe.bodySkin)
        XCTAssertEqual(model.session.selected!.document.undoStack.count, replacementBase.undoStack.count + 1)
        try await waitUntil { !model.isRendering }
        XCTAssertEqual(model.portraitPurposeApplication?.phase, .visible)
        XCTAssertEqual(model.portraitPurposeApplication?.oneTouchResult, replace.result)
        let applied = model.currentRecipe
        let noOpSaves = store.saveCount
        XCTAssertFalse(model.applyOneTouchApplication(strength: 1, replacingPersonal: true))
        XCTAssertEqual(store.saveCount, noOpSaves)
        model.undo()
        XCTAssertEqual(model.currentRecipe, replacementBase.recipe)
        XCTAssertEqual(model.portraitPurposeApplication?.phase, .cancelled)
        model.redo()
        XCTAssertEqual(model.currentRecipe, applied)
        let restored = ProjectSession(store: store, maxPhotos: 40)
        try restored.restore()
        XCTAssertEqual(restored.selected?.document.recipe, applied)
    }

    func testStaleAnalysisSelectionAndEditPlansNeverSaveOrCreateReceipt() async throws {
        let (model, root, store) = try await makeModel()
        defer {
            model.stopWork()
            try? FileManager.default.removeItem(at: root)
        }
        let stale = try XCTUnwrap(model.planOneTouchApplication(strength: 1, replacingPersonal: true))
        model.setBeautyTarget(.gender(.female))
        model.setBeautyTarget(.all)
        let saves = store.saveCount
        let before = model.session.selected!.document
        XCTAssertFalse(model.applyOneTouchApplication(stale))
        XCTAssertEqual(store.saveCount, saves)
        XCTAssertEqual(model.session.selected!.document, before)
        XCTAssertNil(model.portraitPurposeApplication)
        let ready = try XCTUnwrap(model.planOneTouchApplication(strength: 1, replacingPersonal: true))
        let id = model.session.selectedPhotoID!
        let info = model.selectedInfo!
        model.remember(
            id,
            PreparedPhoto(
                pixelSize: info.pixelSize, thumbnail: model.thumbnails[id]!,
                faces: info.faces, faceAnalysisFailure: nil), bindsLegacyPeople: false)
        XCTAssertFalse(model.applyOneTouchApplication(ready))
        let unavailable = try XCTUnwrap(model.planOneTouchApplication(strength: 1, replacingPersonal: true))
        XCTAssertFalse(unavailable.result.hasChanges)
        XCTAssertFalse(model.applyOneTouchApplication(unavailable))
        XCTAssertEqual(store.saveCount, saves)
        XCTAssertEqual(model.session.selected!.document, before)
    }

    func testDragUndoAndReanalysisInvalidateReceiptWithoutUndoingCommittedValues() async throws {
        let (model, root, _) = try await makeModel()
        defer {
            model.stopWork()
            try? FileManager.default.removeItem(at: root)
        }
        model.selectTool(.adjust)
        model.beginSliderEdit()
        model.edit(.exposure(0.3))
        XCTAssertTrue(model.applyOneTouchApplication(strength: 1, replacingPersonal: true))
        XCTAssertFalse(model.session.isPersistenceDeferred)
        try await waitUntil { !model.isRendering }
        XCTAssertEqual(model.portraitPurposeApplication?.phase, .visible)
        let applied = model.currentRecipe
        let id = model.session.selectedPhotoID!
        let info = model.selectedInfo!
        model.remember(
            id,
            PreparedPhoto(
                pixelSize: info.pixelSize, thumbnail: model.thumbnails[id]!,
                faces: info.faces, faceAnalysisFailure: nil), bindsLegacyPeople: false)
        XCTAssertEqual(model.portraitPurposeApplication?.phase, .cancelled)
        XCTAssertEqual(model.currentRecipe, applied)
        model.undo()
        XCTAssertEqual(model.currentRecipe.color.exposure, 0.3)
        XCTAssertTrue(model.currentRecipe.people.individuals.isEmpty)
        model.undo()
        XCTAssertTrue(model.currentRecipe.isDefault)
    }

    func testNeutralNoOpAndEmptyGroupDoNotPersist() async throws {
        let (model, root, store) = try await makeModel()
        defer {
            model.stopWork()
            try? FileManager.default.removeItem(at: root)
        }
        let before = model.session.selected!.document
        let saves = store.saveCount
        XCTAssertFalse(model.applyOneTouchApplication(strength: 0, replacingPersonal: true))
        model.setBeautyTarget(.gender(.female))
        XCTAssertFalse(model.applyOneTouchApplication(strength: 1, replacingPersonal: true))
        XCTAssertEqual(model.session.selected!.document, before)
        XCTAssertEqual(store.saveCount, saves)
        XCTAssertNil(model.portraitPurposeApplication)
    }

    func testSaveFailureAndRenderFailureCannotBecomeVisibleSuccess() async throws {
        let (model, root, store) = try await makeModel()
        defer {
            model.stopWork()
            try? FileManager.default.removeItem(at: root)
        }
        store.saveFailure = .cannotWriteToFolder
        XCTAssertTrue(model.applyOneTouchApplication(strength: 1, replacingPersonal: true))
        let recipe = model.currentRecipe
        let undoCount = model.session.selected!.document.undoStack.count
        try await waitUntil { !model.isRendering }
        XCTAssertEqual(model.portraitPurposeApplication?.phase, .saveFailed)
        XCTAssertEqual(model.currentRecipe, recipe)
        XCTAssertEqual(model.session.selected!.document.undoStack.count, undoCount)
        store.saveFailure = nil
        model.undo()
        try await waitUntil { !model.isRendering }
        let entry = model.session.selected!
        await model.pipeline.evict(entry.id)
        try FileManager.default.removeItem(at: model.copies.url(for: entry.filename))
        XCTAssertTrue(model.applyOneTouchApplication(strength: 1, replacingPersonal: true))
        let failed = model.currentRecipe
        let failedUndo = model.session.selected!.document.undoStack.count
        try await waitUntil { !model.isRendering }
        XCTAssertEqual(model.portraitPurposeApplication?.phase, .renderFailed)
        XCTAssertEqual(model.currentRecipe, failed)
        XCTAssertEqual(model.session.selected!.document.undoStack.count, failedUndo)
    }

}
