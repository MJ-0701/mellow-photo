import MellowEditing
import MellowLibrary
import MellowRendering
import MellowShared
import XCTest

@testable import Mellow_Photo

@MainActor
final class OneTouchPrimaryActionTests: XCTestCase {
    func testPrimaryTapWithProtectedPersonalValuesWaitsWithoutApplyingBodyBrightness() async throws {
        let model = try AppModel.oneTouchDebugFixture()
        let root = model.copies.directory.deletingLastPathComponent()
        defer {
            model.stopWork()
            try? FileManager.default.removeItem(at: root)
        }
        await model.restore()
        try await waitUntil { model.isReady && !model.isRendering }
        model.edit(.bodySkin(.brightness, 0))
        try await waitUntil { !model.isRendering }
        model.setRequestedOneTouchStrength(1, for: .all)
        let before = model.session.selected!.document
        let saves = model.oneTouchFixtureSaveCount!()
        let context = model.portraitPurposeContext
        XCTAssertFalse(model.beginOneTouchPrimaryAction(for: .all), "선택 전에는 얼굴이나 몸부터 적용하지 않는다")
        XCTAssertEqual(model.session.selected!.document, before)
        XCTAssertEqual(model.oneTouchFixtureSaveCount!(), saves)
        XCTAssertEqual(model.portraitPurposeContext, context)
        XCTAssertFalse(model.isRendering)
    }
    func testAutomaticDecisionInvalidationExplainsRetryWithoutAConfirmCallback() async throws {
        let (model, root) = try await seededModel()
        defer {
            model.stopWork()
            try? FileManager.default.removeItem(at: root)
        }
        XCTAssertFalse(model.beginOneTouchPrimaryAction(for: .all))
        let first = try XCTUnwrap(model.oneTouchDecision(for: .all))
        let before = model.session.selected!.document
        let saves = model.oneTouchFixtureSaveCount!()
        model.statusMessage = ""
        model.setRequestedOneTouchStrength(0.8, for: .all)
        XCTAssertNil(model.pendingOneTouchDecision)
        XCTAssertEqual(model.statusMessage, UserMessage.oneTouchDecisionExpired)
        XCTAssertFalse(model.beginOneTouchPrimaryAction(for: .all))
        let second = try XCTUnwrap(model.oneTouchDecision(for: .all))
        model.statusMessage = ""
        model.scheduleRender()
        XCTAssertNil(model.pendingOneTouchDecision)
        XCTAssertEqual(model.statusMessage, UserMessage.oneTouchDecisionExpired)
        XCTAssertEqual(model.session.selected!.document, before)
        XCTAssertEqual(model.oneTouchFixtureSaveCount!(), saves)
        XCTAssertFalse(model.beginOneTouchPrimaryAction(for: .all))
        let current = try XCTUnwrap(model.oneTouchDecision(for: .all))
        model.dismissOneTouchDecision(id: first.id)
        model.dismissOneTouchDecision(id: second.id)
        XCTAssertEqual(model.pendingOneTouchDecision?.id, current.id)
        model.statusMessage = ""
        model.dismissOneTouchDecision(id: current.id)
        XCTAssertNil(model.pendingOneTouchDecision)
        XCTAssertEqual(model.statusMessage, "")
    }
    private func seededModel() async throws -> (AppModel, URL) {
        let model = try AppModel.oneTouchDebugFixture()
        await model.restore()
        try await waitUntil { model.isReady && !model.isRendering }
        return (model, model.copies.directory.deletingLastPathComponent())
    }

    func testReplacementChoiceUsesSnapshotAndPreservesSettingsWithOneUndoRedoAndReload() async throws {
        let (model, root) = try await seededModel()
        defer {
            model.stopWork()
            try? FileManager.default.removeItem(at: root)
        }
        model.edit(.exposure(0.25))
        model.edit(.backgroundBlur(0.35))
        model.edit(.bodySkin(.brightness, 0))
        try await waitUntil { !model.isRendering }
        model.setRequestedOneTouchStrength(1, for: .all)
        let before = model.session.selected!.document
        let saves = model.oneTouchFixtureSaveCount!()
        XCTAssertFalse(model.beginOneTouchPrimaryAction(for: .all))
        let decision = try XCTUnwrap(model.oneTouchDecision(for: .all))
        XCTAssertTrue(decision.keepResult.items.contains { $0.reason == .protectedPersonal })
        XCTAssertEqual(decision.keepResult.changedCount, 0)
        XCTAssertTrue(decision.keepResult.bodySkinChanged)
        XCTAssertFalse(decision.replaceResult.bodySkinChanged)
        XCTAssertTrue(model.resolveOneTouchDecision(id: decision.id, choice: .replacePersonal))
        try await waitUntil { !model.isRendering }
        let after = model.session.selected!.document
        XCTAssertEqual(after.recipe.color, before.recipe.color)
        XCTAssertEqual(after.recipe.background, before.recipe.background)
        XCTAssertEqual(after.recipe.portrait, before.recipe.portrait)
        XCTAssertEqual(after.recipe.bodySkin, before.recipe.bodySkin)
        XCTAssertEqual(after.recipe.people.groups, before.recipe.people.groups)
        XCTAssertEqual(after.recipe.body, before.recipe.body)
        XCTAssertEqual(model.peopleByFace[0]?.layer.skinSmoothing, 0.2)
        XCTAssertEqual(model.oneTouchFixtureSaveCount!(), saves + 1)
        XCTAssertEqual(after.undoStack.count, before.undoStack.count + 1)
        XCTAssertEqual(model.oneTouchFeedback(for: .all)?.phase, .visible)
        XCTAssertFalse(model.resolveOneTouchDecision(id: decision.id, choice: .replacePersonal))
        XCTAssertEqual(model.session.selected!.document, after)
        XCTAssertEqual(model.oneTouchFixtureSaveCount!(), saves + 1)
        let persisted = try XCTUnwrap(JSONSessionStore(fileURL: root.appendingPathComponent("session.json")).load())
        XCTAssertEqual(persisted.photos.first { $0.id == model.session.selectedPhotoID }?.document, after)
        model.undo()
        XCTAssertEqual(model.currentRecipe, before.recipe)
        model.redo()
        XCTAssertEqual(model.currentRecipe, after.recipe)
    }

    func testKeepAndCancelDoNotSilentlyReplacePersonalValues() async throws {
        let (model, root) = try await seededModel()
        defer {
            model.stopWork()
            try? FileManager.default.removeItem(at: root)
        }
        model.edit(.bodySkin(.brightness, 0))
        try await waitUntil { !model.isRendering }
        model.setRequestedOneTouchStrength(1, for: .all)
        let before = model.session.selected!.document
        let saves = model.oneTouchFixtureSaveCount!()
        XCTAssertFalse(model.beginOneTouchPrimaryAction(for: .all))
        let cancelled = try XCTUnwrap(model.oneTouchDecision(for: .all))
        model.dismissOneTouchDecision(id: cancelled.id)
        XCTAssertNil(model.oneTouchDecision(for: .all))
        XCTAssertFalse(model.resolveOneTouchDecision(id: cancelled.id, choice: .replacePersonal))
        XCTAssertEqual(model.session.selected!.document, before)
        XCTAssertEqual(model.oneTouchFixtureSaveCount!(), saves)
        XCTAssertFalse(model.beginOneTouchPrimaryAction(for: .all))
        let keep = try XCTUnwrap(model.oneTouchDecision(for: .all))
        XCTAssertTrue(model.resolveOneTouchDecision(id: keep.id, choice: .keepAdjustments))
        try await waitUntil { !model.isRendering }
        XCTAssertEqual(model.currentRecipe.people.individuals, before.recipe.people.individuals)
        XCTAssertEqual(model.currentRecipe.bodySkin.brightness, 0.08)
        XCTAssertEqual(model.oneTouchFeedback(for: .all)?.result?.changedCount, 0)
        XCTAssertEqual(model.session.selected!.document.undoStack.count, before.undoStack.count + 1)
        XCTAssertEqual(model.oneTouchFixtureSaveCount!(), saves + 1)
    }

    func testDraftABAAndOldDecisionCallbacksCannotConsumeANewerRequest() async throws {
        let (model, root) = try await seededModel()
        defer {
            model.stopWork()
            try? FileManager.default.removeItem(at: root)
        }
        let before = model.session.selected!.document
        let saves = model.oneTouchFixtureSaveCount!()
        model.beginOneTouchPrimaryAction(for: .all)
        let old = try XCTUnwrap(model.oneTouchDecision(for: .all))
        model.setRequestedOneTouchStrength(0.3, for: .all)
        model.setRequestedOneTouchStrength(1, for: .all)
        XCTAssertFalse(model.resolveOneTouchDecision(id: old.id, choice: .replacePersonal))
        XCTAssertEqual(model.session.selected!.document, before)
        model.beginOneTouchPrimaryAction(for: .all)
        let latest = try XCTUnwrap(model.oneTouchDecision(for: .all))
        model.dismissOneTouchDecision(id: old.id)
        XCTAssertEqual(model.oneTouchDecision(for: .all)?.id, latest.id)
        XCTAssertFalse(model.resolveOneTouchDecision(id: old.id, choice: .keepAdjustments))
        XCTAssertEqual(model.oneTouchDecision(for: .all)?.id, latest.id)
        XCTAssertEqual(model.oneTouchFixtureSaveCount!(), saves)
        XCTAssertTrue(model.resolveOneTouchDecision(id: latest.id, choice: .replacePersonal))
    }

    func testPrimaryDoesNotFlushAnotherDeferredEditAndQuickPortraitUsesSameEntry() async throws {
        let (model, root) = try await seededModel()
        defer {
            model.stopWork()
            try? FileManager.default.removeItem(at: root)
        }
        model.beginSliderEdit()
        model.edit(.exposure(0.2))
        let deferred = model.session.selected!.document
        let saves = model.oneTouchFixtureSaveCount!()
        XCTAssertTrue(model.session.isPersistenceDeferred)
        XCTAssertFalse(model.beginOneTouchPrimaryAction(for: .all))
        XCTAssertEqual(model.session.selected!.document, deferred)
        XCTAssertEqual(model.oneTouchFixtureSaveCount!(), saves)
        XCTAssertTrue(model.session.isPersistenceDeferred)
        XCTAssertNil(model.pendingOneTouchDecision)
        model.endSliderEdit()
        try await waitUntil { !model.isRendering }
        let before = model.session.selected!.document
        await model.applyQuickAction(.portrait)
        XCTAssertNotNil(model.oneTouchDecision(for: .all))
        XCTAssertEqual(model.session.selected!.document, before)
    }

    func testPhotoTargetAnalysisRecipeAndStopInvalidateAnOpenChoice() async throws {
        for scenario in ["photoABA", "targetABA", "analysis", "editUndo", "stopResume"] {
            let (model, root) = try await seededModel()
            defer {
                model.stopWork()
                try? FileManager.default.removeItem(at: root)
            }
            model.beginOneTouchPrimaryAction(for: .all)
            let decision = try XCTUnwrap(model.oneTouchDecision(for: .all))
            switch scenario {
            case "photoABA":
                let first = model.session.selectedPhotoID!
                let other = model.session.photos.first { $0.id != first }!.id
                model.select(other)
                try await waitUntil { model.isReady && !model.isRendering }
                model.select(first)
            case "targetABA":
                model.setBeautyTarget(.gender(.female))
                model.setBeautyTarget(.all)
            case "analysis":
                let id = model.session.selectedPhotoID!
                let info = model.selectedInfo!
                model.remember(
                    id,
                    PreparedPhoto(
                        pixelSize: info.pixelSize, thumbnail: model.thumbnails[id]!, faces: info.faces,
                        faceAnalysisFailure: nil, portraitPurposeKeys: info.portraitPurposeKeys,
                        oneTouchKeys: info.oneTouchKeys, oneTouchBodySkinAvailable: info.oneTouchBodySkinAvailable),
                    bindsLegacyPeople: false)
            case "editUndo":
                model.edit(.exposure(0.2))
                model.undo()
            default:
                model.stopWork()
                model.resumeWork()
            }
            try await waitUntil { model.isReady && !model.isRendering }
            let beforeConfirmation = model.session.selected!.document
            let saves = model.oneTouchFixtureSaveCount!()
            XCTAssertNil(model.oneTouchDecision(for: .all), scenario)
            XCTAssertFalse(model.resolveOneTouchDecision(id: decision.id, choice: .replacePersonal), scenario)
            XCTAssertEqual(model.session.selected!.document, beforeConfirmation, scenario)
            XCTAssertEqual(model.oneTouchFixtureSaveCount!(), saves, scenario)
            XCTAssertNil(model.oneTouchFeedback(for: .all), scenario)
        }
    }

    func testGenderChoiceAndQuickAllKeepTheirActionTargetsSeparate() async throws {
        let (model, root) = try await seededModel()
        defer {
            model.stopWork()
            try? FileManager.default.removeItem(at: root)
        }
        model.setBeautyTarget(.gender(.female))
        model.setRequestedOneTouchStrength(0.8, for: .gender(.female))
        model.beginOneTouchPrimaryAction(for: .gender(.female))
        let female = try XCTUnwrap(model.oneTouchDecision(for: .gender(.female)))
        XCTAssertEqual(female.strength, 0.8)
        XCTAssertEqual(female.target, .gender(.female))
        XCTAssertEqual(UserMessage.oneTouchDecisionTarget(female.target), "여성 그룹")
        model.dismissOneTouchDecision(id: female.id)
        model.setBeautyTarget(.gender(.male))
        model.setRequestedOneTouchStrength(0.3, for: .gender(.male))
        model.setRequestedOneTouchStrength(1, for: .all)
        model.beginOneTouchPrimaryAction(for: .all)
        let all = try XCTUnwrap(model.oneTouchDecision(for: .all))
        XCTAssertEqual(all.target, .all)
        XCTAssertEqual(all.strength, 1)
        XCTAssertEqual(UserMessage.oneTouchDecisionTarget(all.target), "이 사진의 모든 얼굴")
        XCTAssertNil(model.oneTouchDecision(for: .gender(.male)))
        XCTAssertTrue(model.resolveOneTouchDecision(id: all.id, choice: .replacePersonal))
        XCTAssertEqual(model.beautyTarget, .gender(.male))
        XCTAssertEqual(model.requestedOneTouchStrength(for: .gender(.male)), 0.3)
        XCTAssertEqual(model.peopleByFace[0]?.layer.skinSmoothing, 0.2)
    }

    func testPrimaryZeroAndDirectFaceRetainLegacySemanticsWithoutChoice() async throws {
        let (model, root) = try await seededModel()
        defer {
            model.stopWork()
            try? FileManager.default.removeItem(at: root)
        }
        let before = model.currentRecipe
        model.setRequestedOneTouchStrength(0, for: .all)
        XCTAssertTrue(model.beginOneTouchPrimaryAction(for: .all))
        XCTAssertNil(model.pendingOneTouchDecision)
        XCTAssertEqual(model.currentRecipe.people.individuals, before.people.individuals)
        XCTAssertEqual(model.currentRecipe.bodySkin.brightness, 0)
        model.undo()
        try await waitUntil { !model.isRendering }
        model.setBeautyTarget(.face(0))
        model.setRequestedOneTouchStrength(1, for: .face(0))
        XCTAssertTrue(model.beginOneTouchPrimaryAction(for: .face(0)))
        XCTAssertNil(model.pendingOneTouchDecision)
        XCTAssertEqual(model.peopleByFace[0]?.layer.skinSmoothing, 0.2)
        XCTAssertEqual(model.currentRecipe.portrait, before.portrait)
        XCTAssertEqual(model.currentRecipe.bodySkin, before.bodySkin)
    }

    func testPartialPersonalProtectionStillRequiresChoiceBeforeAnyGlobalChange() async throws {
        let root = try TestSupport.temporaryDirectory()
        let faces = [
            TestSupport.landmarkedFace(in: NormalizedRect(x: 0.1, y: 0.2, width: 0.3, height: 0.6)),
            TestSupport.landmarkedFace(in: NormalizedRect(x: 0.6, y: 0.2, width: 0.3, height: 0.6)),
        ]
        let store = MemorySessionStore()
        let model = TestSupport.makeModel(
            root: root, analyzer: StubFaceAnalyzer(result: .success(faces)),
            importer: FakeImporter(passesThroughFileURLs: true), store: store)
        defer {
            model.stopWork()
            try? FileManager.default.removeItem(at: root)
        }
        await model.importFromFiles([try TestSupport.solidPNG(in: root)])
        try await waitUntil { model.isReady && !model.isRendering }
        model.applyOneTouch(strength: 0.2, target: .face(0))
        try await waitUntil { !model.isRendering }
        model.setRequestedOneTouchStrength(1, for: .all)
        let before = model.session.selected!.document
        let saves = store.saveCount
        XCTAssertFalse(model.beginOneTouchPrimaryAction(for: .all))
        let choice = try XCTUnwrap(model.oneTouchDecision(for: .all))
        XCTAssertTrue(choice.keepResult.items.contains { $0.reason == .protectedPersonal })
        XCTAssertGreaterThan(choice.keepResult.changedCount, 0, "일부 인물의 값은 변경 가능해도 먼저 고른다")
        XCTAssertEqual(model.session.selected!.document, before)
        XCTAssertEqual(store.saveCount, saves)
        XCTAssertTrue(model.resolveOneTouchDecision(id: choice.id, choice: .keepAdjustments))
        XCTAssertEqual(model.currentRecipe.people.individuals, before.recipe.people.individuals)
        XCTAssertEqual(store.saveCount, saves + 1)
        XCTAssertEqual(model.session.selected!.document.undoStack.count, before.undoStack.count + 1)
    }

    func testNoOpChoiceAndRepeatedPrimaryDoNotReusePreviousSuccess() async throws {
        let (model, root) = try await seededModel()
        defer {
            model.stopWork()
            try? FileManager.default.removeItem(at: root)
        }
        let before = model.session.selected!.document
        let saves = model.oneTouchFixtureSaveCount!()
        model.beginOneTouchPrimaryAction(for: .all)
        let keep = try XCTUnwrap(model.oneTouchDecision(for: .all))
        XCTAssertFalse(model.resolveOneTouchDecision(id: keep.id, choice: .keepAdjustments))
        XCTAssertEqual(model.oneTouchFeedback(for: .all)?.phase, .noChange)
        XCTAssertEqual(model.session.selected!.document, before)
        XCTAssertEqual(model.oneTouchFixtureSaveCount!(), saves)
        model.beginOneTouchPrimaryAction(for: .all)
        let replace = try XCTUnwrap(model.oneTouchDecision(for: .all))
        XCTAssertTrue(model.resolveOneTouchDecision(id: replace.id, choice: .replacePersonal))
        try await waitUntil { !model.isRendering }
        XCTAssertEqual(model.oneTouchFeedback(for: .all)?.phase, .visible)
        let after = model.session.selected!.document
        let saved = model.oneTouchFixtureSaveCount!()
        XCTAssertFalse(model.beginOneTouchPrimaryAction(for: .all))
        if let again = model.oneTouchDecision(for: .all) {
            XCTAssertNil(model.oneTouchFeedback(for: .all), "선택 대기는 이전 성공 표시를 재사용하지 않는다")
            XCTAssertFalse(model.resolveOneTouchDecision(id: again.id, choice: .replacePersonal))
        }
        XCTAssertEqual(model.oneTouchFeedback(for: .all)?.phase, .noChange)
        XCTAssertEqual(model.session.selected!.document, after)
        XCTAssertEqual(model.oneTouchFixtureSaveCount!(), saved)
    }

    func testChoiceReportsPersistenceAndRenderFailuresAsFailures() async throws {
        for failure in ["save", "render"] {
            let root = try TestSupport.temporaryDirectory()
            let face = TestSupport.landmarkedFace(in: NormalizedRect(x: 0.2, y: 0.2, width: 0.6, height: 0.6))
            let store = MemorySessionStore()
            let model = TestSupport.makeModel(
                root: root, analyzer: StubFaceAnalyzer(result: .success([face])),
                importer: FakeImporter(passesThroughFileURLs: true), store: store)
            defer {
                model.stopWork()
                try? FileManager.default.removeItem(at: root)
            }
            await model.importFromFiles([try TestSupport.solidPNG(in: root)])
            try await waitUntil { model.isReady && !model.isRendering }
            model.applyOneTouch(strength: 1, target: .all)
            model.applyOneTouch(strength: 0.2, target: .face(0))
            try await waitUntil { !model.isRendering }
            model.setRequestedOneTouchStrength(1, for: .all)
            model.beginOneTouchPrimaryAction(for: .all)
            let decision = try XCTUnwrap(model.oneTouchDecision(for: .all))
            let before = model.session.selected!.document
            if failure == "save" {
                store.saveFailure = .cannotWriteToFolder
            } else {
                let entry = model.session.selected!
                await model.pipeline.evict(entry.id)
                try FileManager.default.removeItem(at: model.copies.url(for: entry.filename))
            }
            XCTAssertTrue(model.resolveOneTouchDecision(id: decision.id, choice: .replacePersonal))
            try await waitUntil { !model.isRendering }
            XCTAssertEqual(model.oneTouchFeedback(for: .all)?.phase, failure == "save" ? .saveFailed : .renderFailed)
            XCTAssertEqual(model.session.selected!.document.undoStack.count, before.undoStack.count + 1)
        }
    }

}
