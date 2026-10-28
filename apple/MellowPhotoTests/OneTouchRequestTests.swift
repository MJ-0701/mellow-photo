import CryptoKit
import MellowEditing
import MellowLibrary
import MellowRendering
import MellowShared
import XCTest

@testable import Mellow_Photo

@MainActor
final class OneTouchRequestTests: XCTestCase {
    private func makeModel(photos: Int = 1) async throws -> (AppModel, URL, MemorySessionStore) {
        let root = try TestSupport.temporaryDirectory()
        let face = TestSupport.landmarkedFace(in: NormalizedRect(x: 0.2, y: 0.2, width: 0.6, height: 0.6))
        let store = MemorySessionStore()
        let model = TestSupport.makeModel(
            root: root, analyzer: StubFaceAnalyzer(result: .success([face])),
            importer: FakeImporter(passesThroughFileURLs: true), store: store)
        let files = try (0..<photos).map { _ in try TestSupport.solidPNG(in: root) }
        await model.importFromFiles(files)
        try await waitUntil { model.isReady && !model.isRendering }
        return (model, root, store)
    }

    func testSliderOnlyEditsRequestsAndButtonMakesOneUndo() async throws {
        let (model, root, store) = try await makeModel()
        defer {
            model.stopWork()
            try? FileManager.default.removeItem(at: root)
        }
        let before = model.session.selected!.document
        let saves = store.saveCount
        let context = model.portraitPurposeContext
        let drag = try XCTUnwrap(model.beginOneTouchRequestEditing(for: .all))
        for value in [0.1, 0.2, 0.5, 0.8, 1] {
            model.setRequestedOneTouchStrength(value, for: .all, expectedContext: context, dragID: drag)
            XCTAssertEqual(model.session.selected!.document, before)
            XCTAssertEqual(store.saveCount, saves)
            XCTAssertFalse(model.isRendering)
            XCTAssertEqual(model.portraitPurposeContext, context)
        }
        model.endOneTouchRequestEditing(for: .all, id: drag)
        XCTAssertEqual(store.saveCount, saves)
        XCTAssertEqual(model.session.selected!.document, before)
        XCTAssertNil(model.oneTouchFeedback(for: .all))
        XCTAssertFalse(model.isRendering)
        XCTAssertEqual(model.portraitPurposeContext, context)
        XCTAssertTrue(model.submitOneTouchRequest(for: .all))
        XCTAssertEqual(store.saveCount, saves + 1)
        XCTAssertEqual(model.session.selected!.document.undoStack.count, before.undoStack.count + 1)
        XCTAssertEqual(model.oneTouchFeedback(for: .all)?.phase, .rendering)
        try await waitUntil { !model.isRendering }
        XCTAssertEqual(model.oneTouchFeedback(for: .all)?.phase, .visible)
        XCTAssertEqual(model.requestedOneTouchStrength(for: .all), 1)
        model.undo()
        XCTAssertEqual(model.currentRecipe, before.recipe)
        XCTAssertNil(model.oneTouchFeedback(for: .all))
    }

    func testProtectedRequestStaysAtOneAndExplicitReplacementThenNoOpDoesNotReuseSuccess() async throws {
        let (model, root, store) = try await makeModel()
        defer {
            model.stopWork()
            try? FileManager.default.removeItem(at: root)
        }
        model.applyOneTouch(strength: 1, target: .all)
        model.applyOneTouch(strength: 0.2, target: .face(0))
        try await waitUntil { !model.isRendering }
        model.setRequestedOneTouchStrength(1, for: .all)
        let before = model.session.selected!.document
        let saves = store.saveCount
        XCTAssertFalse(model.submitOneTouchRequest(for: .all))
        XCTAssertEqual(model.requestedOneTouchStrength(for: .all), 1)
        XCTAssertEqual(model.session.selected!.document, before)
        XCTAssertEqual(store.saveCount, saves)
        let protected = try XCTUnwrap(model.oneTouchFeedback(for: .all))
        XCTAssertEqual(protected.phase, .noChange)
        XCTAssertNotNil(UserMessage.oneTouchProtected(try XCTUnwrap(protected.result)))
        XCTAssertTrue(model.submitOneTouchRequest(for: .all, replacingPersonal: true))
        XCTAssertEqual(model.currentRecipe.portrait, before.recipe.portrait)
        XCTAssertEqual(model.currentRecipe.bodySkin, before.recipe.bodySkin)
        try await waitUntil { !model.isRendering }
        XCTAssertEqual(model.oneTouchFeedback(for: .all)?.phase, .visible)
        let after = model.session.selected!.document
        let afterSaves = store.saveCount
        XCTAssertFalse(model.submitOneTouchRequest(for: .all, replacingPersonal: true))
        XCTAssertEqual(model.oneTouchFeedback(for: .all)?.phase, .noChange)
        XCTAssertNil(model.portraitPurposeApplication)
        XCTAssertEqual(model.session.selected!.document, after)
        XCTAssertEqual(store.saveCount, afterSaves)
    }

    func testQuickFixedAllUsesItsOwnRequestAndResultWhileBeautyGenderIsEmpty() async throws {
        let (model, root, _) = try await makeModel()
        defer {
            model.stopWork()
            try? FileManager.default.removeItem(at: root)
        }
        model.setBeautyTarget(.gender(.female))
        XCTAssertEqual(model.portraitFaceCount(for: .gender(.female)), 0)
        model.setRequestedOneTouchStrength(0.8, for: .all)
        model.setRequestedOneTouchStrength(0.3, for: .gender(.female))
        XCTAssertEqual(model.requestedOneTouchStrength(for: .all), 0.8)
        XCTAssertEqual(model.requestedOneTouchStrength(for: .gender(.female)), 0.3)
        XCTAssertTrue(model.submitOneTouchRequest(for: .all))
        XCTAssertEqual(model.beautyTarget, .gender(.female))
        XCTAssertEqual(model.currentRecipe.portrait.skin.smoothing, OneTouchBundle.Table.common.smoothing * 0.8)
        try await waitUntil { !model.isRendering }
        XCTAssertEqual(model.oneTouchFeedback(for: .all)?.phase, .visible)
        XCTAssertNil(model.oneTouchFeedback(for: .gender(.female)))
        let before = model.session.selected!.document
        XCTAssertFalse(model.submitOneTouchRequest(for: .gender(.female)))
        XCTAssertEqual(model.oneTouchFeedback(for: .gender(.female))?.phase, .unavailable)
        XCTAssertNil(model.oneTouchFeedback(for: .all))
        XCTAssertEqual(model.session.selected!.document, before)
    }

    func testPhotoABAOldGestureAndReanalysisCannotApplyOrReuseResults() async throws {
        let (model, root, store) = try await makeModel(photos: 2)
        defer {
            model.stopWork()
            try? FileManager.default.removeItem(at: root)
        }
        let a = model.session.selectedPhotoID!
        let b = model.session.photos.first { $0.id != a }!.id
        model.setRequestedOneTouchStrength(0.8, for: .all)
        XCTAssertTrue(model.submitOneTouchRequest(for: .all))
        try await waitUntil { !model.isRendering }
        let before = model.session.selected!.document
        let oldContext = model.portraitPurposeContext
        let drag = try XCTUnwrap(model.beginOneTouchRequestEditing(for: .all))
        model.setRequestedOneTouchStrength(0.9, for: .all, expectedContext: oldContext, dragID: drag)
        model.select(b)
        try await waitUntil { model.isReady && !model.isRendering }
        let bContext = model.portraitPurposeContext
        let newDrag = try XCTUnwrap(model.beginOneTouchRequestEditing(for: .all))
        model.endOneTouchRequestEditing(for: .all, id: drag)
        XCTAssertEqual(model.oneTouchRequestDrag?.id, newDrag)
        model.setRequestedOneTouchStrength(0.3, for: .all, expectedContext: bContext, dragID: newDrag)
        model.cancelOneTouchRequestEditing(newDrag)
        model.select(a)
        try await waitUntil { model.isReady && !model.isRendering }
        let saves = store.saveCount
        model.endOneTouchRequestEditing(for: .all, id: drag)
        model.setRequestedOneTouchStrength(0.1, for: .all, expectedContext: oldContext, dragID: drag)
        XCTAssertEqual(model.requestedOneTouchStrength(for: .all), 0.9)
        XCTAssertEqual(model.session.selected!.document, before)
        XCTAssertEqual(store.saveCount, saves)
        XCTAssertNil(model.oneTouchFeedback(for: .all))
        let info = model.selectedInfo!
        model.remember(
            a,
            PreparedPhoto(
                pixelSize: info.pixelSize, thumbnail: model.thumbnails[a]!, faces: info.faces,
                faceAnalysisFailure: nil, portraitPurposeKeys: info.portraitPurposeKeys,
                oneTouchKeys: info.oneTouchKeys, oneTouchBodySkinAvailable: info.oneTouchBodySkinAvailable),
            bindsLegacyPeople: false)
        XCTAssertEqual(model.requestedOneTouchStrength(for: .all), model.oneTouchStrength(for: .all))
        XCTAssertNil(model.oneTouchFeedback(for: .all))
    }

    func testEmptyGroupLegacyClearAndExplicitNeutralRemainDifferentAndNoOpSafe() async throws {
        let (model, root, store) = try await makeModel()
        defer {
            model.stopWork()
            try? FileManager.default.removeItem(at: root)
        }
        model.mutateSelected { document in
            document.set(.exposure(0.2))
            return document.applyOneTouch(strength: 0.6, in: .gender(.female))
        }
        try await waitUntil { !model.isRendering }
        model.setBeautyTarget(.gender(.female))
        XCTAssertTrue(model.hasStoredOneTouchValues(for: .gender(.female)))
        let before = model.currentRecipe
        XCTAssertTrue(model.clearOneTouchInheritance(for: .gender(.female)))
        XCTAssertNil(model.currentRecipe.people.groups[.female])
        XCTAssertEqual(model.currentRecipe.color, before.color)
        try await waitUntil { !model.isRendering }
        XCTAssertEqual(model.oneTouchFeedback(for: .gender(.female))?.phase, .visible)
        let saves = store.saveCount
        XCTAssertFalse(model.clearOneTouchInheritance(for: .gender(.female)))
        XCTAssertEqual(store.saveCount, saves)
        XCTAssertEqual(model.oneTouchFeedback(for: .gender(.female))?.phase, .noChange)
        model.undo()
        XCTAssertEqual(model.currentRecipe, before)
        model.setBeautyTarget(.all)
        model.applyOneTouch(strength: 1)
        try await waitUntil { !model.isRendering }
        let global = model.currentRecipe.portrait
        model.setRequestedOneTouchStrength(0, for: .all)
        XCTAssertTrue(model.submitOneTouchRequest(for: .all, replacingPersonal: true))
        XCTAssertEqual(model.currentRecipe.portrait, global)
        XCTAssertEqual(model.peopleByFace[0]?.layer.skinSmoothing, 0)
        try await waitUntil { !model.isRendering }
        XCTAssertFalse(model.oneTouchFeedback(for: .all)!.clearingInheritance)
        XCTAssertTrue(model.clearOneTouchInheritance(for: .face(0)))
        XCTAssertEqual(model.currentRecipe.portrait.skin.smoothing, global.skin.smoothing)
    }

    func testFeedbackIsNotSuccessOnSaveOrRenderFailureAndManualEditInvalidates() async throws {
        let (model, root, store) = try await makeModel()
        defer {
            model.stopWork()
            try? FileManager.default.removeItem(at: root)
        }
        store.saveFailure = .cannotWriteToFolder
        model.setRequestedOneTouchStrength(0.6, for: .all)
        XCTAssertTrue(model.submitOneTouchRequest(for: .all))
        try await waitUntil { !model.isRendering }
        XCTAssertEqual(model.oneTouchFeedback(for: .all)?.phase, .saveFailed)
        store.saveFailure = nil
        model.undo()
        try await waitUntil { !model.isRendering }
        XCTAssertNil(model.oneTouchFeedback(for: .all))
        let entry = model.session.selected!
        await model.pipeline.evict(entry.id)
        try FileManager.default.removeItem(at: model.copies.url(for: entry.filename))
        XCTAssertTrue(model.submitOneTouchRequest(for: .all))
        try await waitUntil { !model.isRendering }
        XCTAssertEqual(model.oneTouchFeedback(for: .all)?.phase, .renderFailed)
        model.edit(.exposure(0.2))
        XCTAssertNil(model.oneTouchFeedback(for: .all))
    }
    #if DEBUG
        func testNativeFixtureIsIsolatedSeededAndReadOnlyMeterMatchesActualModel() async throws {
            let model = try AppModel.oneTouchDebugFixture()
            let root = model.copies.directory.deletingLastPathComponent()
            defer {
                model.stopWork()
                try? FileManager.default.removeItem(at: root)
            }
            await model.restore()
            try await waitUntil { model.isReady && !model.isRendering }
            XCTAssertTrue(model.isOneTouchUIFixture)
            XCTAssertEqual(model.session.photos.count, 2)
            XCTAssertEqual(model.currentRecipe.portrait.oneTouch, 1)
            XCTAssertEqual(model.peopleByFace[0]?.layer.oneTouch, 0.2)
            XCTAssertEqual(model.peopleByFace[0]?.gender, .female)
            XCTAssertEqual(model.currentRecipe.portrait.face, FaceShapeAdjustments())
            XCTAssertFalse(model.canUndo)
            let before = model.session.selected!.document
            let snapshot = try XCTUnwrap(
                try JSONSerialization.jsonObject(with: Data(model.oneTouchFixtureSnapshot.utf8)) as? [String: Any])
            XCTAssertEqual(snapshot["fixture"] as? String, "synthetic-one-touch-overrides")
            XCTAssertEqual(try XCTUnwrap(snapshot["resolvedSmoothing"] as? Double), 0.04, accuracy: 1e-12)
            XCTAssertEqual(snapshot["ready"] as? Bool, true)
            XCTAssertEqual(model.session.selected!.document, before)
            let staged = await model.importer.stage(fileURLs: [root.appendingPathComponent("not-a-photo")])
            XCTAssertTrue(staged.isEmpty)
        }
        func testChoosingNeutralForExplicitReplacementDoesNotClearGlobalBeforeReplacement() async throws {
            let model = try AppModel.oneTouchDebugFixture()
            let root = model.copies.directory.deletingLastPathComponent()
            defer {
                model.stopWork()
                try? FileManager.default.removeItem(at: root)
            }
            await model.restore()
            try await waitUntil { model.isReady && !model.isRendering }
            let before = model.currentRecipe
            let beforeUndo = model.session.selected!.document.undoStack.count
            let drag = try XCTUnwrap(model.beginOneTouchRequestEditing(for: .all))
            model.setRequestedOneTouchStrength(0, for: .all, dragID: drag)
            model.endOneTouchRequestEditing(for: .all, id: drag)
            try await waitUntil { !model.isRendering }
            XCTAssertEqual(model.currentRecipe, before, "교체용 강도 선택만으로 기본 적용/삭제를 선행하지 않는다")
            XCTAssertTrue(model.submitOneTouchRequest(for: .all, replacingPersonal: true))
            try await waitUntil { !model.isRendering }
            XCTAssertEqual(model.currentRecipe.portrait, before.portrait)
            XCTAssertEqual(model.currentRecipe.people.groups, before.people.groups)
            XCTAssertEqual(model.currentRecipe.bodySkin, before.bodySkin)
            XCTAssertEqual(model.session.selected!.document.undoStack.count, beforeUndo + 1)
        }
    #endif

    func testBodyOnlyChangeIsNotReportedAsFaceCompletion() async throws {
        let (model, root, _) = try await makeModel()
        defer {
            model.stopWork()
            try? FileManager.default.removeItem(at: root)
        }
        model.applyOneTouch(strength: 1, target: .all)
        model.applyOneTouch(strength: 0.2, target: .face(0))
        model.edit(.bodySkin(.brightness, 0))
        try await waitUntil { !model.isRendering }
        let individual = model.currentRecipe.people.individuals
        model.setRequestedOneTouchStrength(1, for: .all)
        XCTAssertTrue(model.submitOneTouchRequest(for: .all))
        try await waitUntil { !model.isRendering }
        let feedback = try XCTUnwrap(model.oneTouchFeedback(for: .all))
        XCTAssertEqual(feedback.phase, .visible)
        XCTAssertEqual(feedback.result?.changedCount, 0)
        XCTAssertEqual(feedback.result?.bodySkinChanged, true)
        XCTAssertEqual(model.currentRecipe.people.individuals, individual)
        XCTAssertEqual(UserMessage.oneTouchOutcome(feedback), "몸 피부 밝기 값만 적용됐어요. 얼굴 보정 완료를 뜻하지 않아요.")
    }

    #if DEBUG
        func testNativeMeterRequiredFieldsReflectOwnedSourceAndActualActionScope() async throws {
            let model = try AppModel.oneTouchDebugFixture()
            let root = model.copies.directory.deletingLastPathComponent()
            defer {
                model.stopWork()
                try? FileManager.default.removeItem(at: root)
            }
            await model.restore()
            try await waitUntil { model.isReady && !model.isRendering }
            func meter() throws -> [String: Any] {
                try XCTUnwrap(
                    try JSONSerialization.jsonObject(with: Data(model.oneTouchFixtureSnapshot.utf8)) as? [String: Any])
            }
            let entry = model.session.selected!
            let bytes = try Data(contentsOf: model.copies.url(for: entry.filename))
            let actualSHA = SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
            let first = try meter()
            XCTAssertEqual(first["sourceSHA"] as? String, actualSHA)
            XCTAssertEqual(first["bodyBrightness"] as? Double, model.currentRecipe.bodySkin.brightness)
            XCTAssertEqual(first["requestCurrent"] as? Double, 1)
            let document = model.session.selected!.document
            model.setBeautyTarget(.gender(.male))
            model.setRequestedOneTouchStrength(0.3, for: .gender(.male))
            let second = try meter()
            XCTAssertEqual(second["sourceSHA"] as? String, actualSHA)
            XCTAssertEqual(try XCTUnwrap(second["requestCurrent"] as? Double), 0.3, accuracy: 1e-12)
            XCTAssertEqual(second["requestAll"] as? Double, 1)
            XCTAssertEqual(second["bodyBrightness"] as? Double, document.recipe.bodySkin.brightness)
            XCTAssertEqual(model.session.selected!.document, document)
        }
    #endif

    func testDraftDoesNotDrainAnotherOpenSliderAndApplyKeepsUndoSeparate() async throws {
        let (model, root, store) = try await makeModel()
        defer {
            model.stopWork()
            try? FileManager.default.removeItem(at: root)
        }
        model.selectTool(.adjust)
        model.beginSliderEdit()
        model.edit(.exposure(0.3))
        let before = model.session.selected!.document
        let saves = store.saveCount
        let drag = try XCTUnwrap(model.beginOneTouchRequestEditing(for: .all))
        model.setRequestedOneTouchStrength(0.8, for: .all, dragID: drag)
        model.endOneTouchRequestEditing(for: .all, id: drag)
        XCTAssertTrue(model.session.isPersistenceDeferred)
        XCTAssertEqual(store.saveCount, saves)
        XCTAssertEqual(model.session.selected!.document, before)
        XCTAssertTrue(model.submitOneTouchRequest(for: .all))
        XCTAssertFalse(model.session.isPersistenceDeferred)
        XCTAssertEqual(store.saveCount, saves + 2)
        model.undo()
        XCTAssertEqual(model.currentRecipe.color.exposure, 0.3)
        XCTAssertNil(model.currentRecipe.portrait.oneTouch)
        model.undo()
        XCTAssertTrue(model.currentRecipe.isDefault)
    }

    func testPositiveDraftThenExplicitKeepsGlobalGroupAndBodyValues() async throws {
        let (model, root, store) = try await makeModel()
        defer {
            model.stopWork()
            try? FileManager.default.removeItem(at: root)
        }
        model.applyOneTouch(strength: 0.6, target: .all)
        model.applyOneTouch(strength: 0.2, target: .face(0))
        try await waitUntil { !model.isRendering }
        let before = model.session.selected!.document
        let saves = store.saveCount
        let drag = try XCTUnwrap(model.beginOneTouchRequestEditing(for: .all))
        model.setRequestedOneTouchStrength(1, for: .all, dragID: drag)
        model.endOneTouchRequestEditing(for: .all, id: drag)
        XCTAssertEqual(model.session.selected!.document, before)
        XCTAssertEqual(store.saveCount, saves)
        XCTAssertTrue(model.submitOneTouchRequest(for: .all, replacingPersonal: true))
        XCTAssertEqual(model.currentRecipe.portrait, before.recipe.portrait)
        XCTAssertEqual(model.currentRecipe.people.groups, before.recipe.people.groups)
        XCTAssertEqual(model.currentRecipe.bodySkin, before.recipe.bodySkin)
        XCTAssertEqual(store.saveCount, saves + 1)
        XCTAssertEqual(model.session.selected!.document.undoStack.count, before.undoStack.count + 1)
    }

}
