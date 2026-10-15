import MellowShared
import XCTest

@testable import MellowEditing

final class EditDocumentTests: XCTestCase {
    func testSetCheckpointsOnceAndUndoRestores() {
        var document = EditDocument()
        XCTAssertNil(document.set(.exposure(0.4)))
        XCTAssertEqual(document.recipe.color.exposure, 0.4)
        XCTAssertTrue(document.canUndo)
        document.undo()
        XCTAssertEqual(document.recipe.color.exposure, 0)
        XCTAssertTrue(document.canRedo)
        document.redo()
        XCTAssertEqual(document.recipe.color.exposure, 0.4)
    }

    func testContinuousChangeCheckpointsOnlyAtBegin() {
        var document = EditDocument()
        document.beginContinuousChange()
        document.set(.exposure(0.1))
        document.set(.exposure(0.2))
        document.set(.exposure(0.3))
        document.endContinuousChange()
        XCTAssertEqual(document.undoStack.count, 1)
        document.undo()
        XCTAssertEqual(document.recipe.color.exposure, 0)
    }

    func testUndoClearsContinuousChange() {
        var document = EditDocument()
        document.beginContinuousChange()
        document.set(.exposure(0.1))
        // 드래그가 끝나기 전에 실행 취소하면 이후 편집은 다시 단계마다 체크포인트한다.
        document.undo()
        document.set(.exposure(0.2))
        document.set(.exposure(0.3))
        XCTAssertEqual(document.undoStack.count, 2)
        document.undo()
        XCTAssertEqual(document.recipe.color.exposure, 0.2)
    }

    func testIdenticalRecipeIsNotCheckpointedTwice() {
        var document = EditDocument()
        document.set(.exposure(0.4))
        document.set(.exposure(0.4))
        XCTAssertEqual(document.undoStack.count, 1)
    }

    func testNewEditClearsRedo() {
        var document = EditDocument()
        document.set(.exposure(0.4))
        document.undo()
        document.set(.contrast(1.1))
        XCTAssertFalse(document.canRedo)
    }

    func testHistoryIsCappedAtPolicyLimit() {
        var document = EditDocument()
        for step in 1...(EditingPolicy.historyLimit + 10) {
            document.set(.exposure(Double(step) / 100))
        }
        XCTAssertEqual(document.undoStack.count, EditingPolicy.historyLimit)
    }

    func testLocalEditLocksFaceSlimAndTargetFace() {
        var document = EditDocument()
        document.set(.faceSlim(0.2))
        document.set(.targetFace(1))
        document.appendLocalEdit(.spot(RetouchSpot(x: 0.5, y: 0.4, sourceX: 0.4, sourceY: 0.4, radius: 0.02)))
        XCTAssertTrue(document.isGeometryLocked)
        XCTAssertEqual(document.set(.faceSlim(0.9)), .geometryLocked)
        XCTAssertEqual(document.set(.targetFace(nil)), .geometryLocked)
        XCTAssertEqual(document.recipe.portrait.faceSlim, 0.2)
        XCTAssertEqual(document.recipe.portrait.targetFace, 1)
        XCTAssertNil(document.set(.skinSmoothing(0.5)))
        // 피부 보정, 수동 편집 순으로 되돌린다.
        document.undo()
        document.undo()
        XCTAssertFalse(document.isGeometryLocked)
    }

    func testPresetPreservesFaceSlimWhenLocked() {
        var document = EditDocument()
        document.set(.faceSlim(0.2))
        document.appendLocalEdit(.warp(WarpStroke(x: 0.5, y: 0.5, dx: 0.01, dy: 0, radius: 0.1)))
        let preset = PresetValues(color: ColorAdjustments(exposure: 0.5), portrait: PortraitAdjustments(faceSlim: 0.7))
        document.apply(preset)
        XCTAssertEqual(document.recipe.color.exposure, 0.5)
        XCTAssertEqual(document.recipe.portrait.faceSlim, 0.2)
        XCTAssertEqual(document.recipe.operations.count, 1)
    }

    func testPresetReplacesEverythingWhenUnlocked() {
        var document = EditDocument()
        document.set(.targetFace(2))
        document.apply(PresetValues(portrait: PortraitAdjustments(faceSlim: 0.7, targetFace: 5)))
        XCTAssertEqual(document.recipe.portrait.faceSlim, 0.7)
        XCTAssertEqual(document.recipe.portrait.targetFace, 2, "프리셋은 얼굴을 고르지 않으므로 사진의 대상 얼굴을 유지한다")
    }

    func testBatchApplyKeepsLockedGeometryAndResetsTargetOtherwise() {
        var locked = EditDocument()
        locked.set(.faceSlim(0.2))
        locked.set(.targetFace(1))
        locked.appendLocalEdit(.spot(RetouchSpot(x: 0.5, y: 0.4, sourceX: 0.4, sourceY: 0.4, radius: 0.02)))
        var unlocked = EditDocument()
        unlocked.set(.targetFace(0))
        let values = PresetValues(
            color: ColorAdjustments(exposure: 0.3), portrait: PortraitAdjustments(faceSlim: 0.9, targetFace: 3))
        locked.applyFromBatch(values)
        unlocked.applyFromBatch(values)
        XCTAssertEqual(locked.recipe.portrait.faceSlim, 0.2)
        XCTAssertEqual(locked.recipe.portrait.targetFace, 1)
        XCTAssertEqual(locked.recipe.color.exposure, 0.3)
        XCTAssertEqual(unlocked.recipe.portrait.faceSlim, 0.9)
        XCTAssertNil(unlocked.recipe.portrait.targetFace)
        XCTAssertTrue(locked.canUndo)
        XCTAssertTrue(unlocked.canUndo)
    }

    func testResetIsUndoable() {
        var document = EditDocument()
        document.set(.exposure(0.4))
        document.appendLocalEdit(.warp(WarpStroke(x: 0.5, y: 0.5, dx: 0.01, dy: 0, radius: 0.1)))
        document.reset()
        XCTAssertTrue(document.recipe.isDefault)
        document.undo()
        XCTAssertEqual(document.recipe.operations.count, 1)
    }

    func testNewChangesAreNotLockedByLocalEdits() {
        var document = EditDocument()
        document.appendLocalEdit(.spot(RetouchSpot(x: 0.5, y: 0.4, sourceX: 0.4, sourceY: 0.4, radius: 0.02)))
        XCTAssertNil(document.set(.highlights(-0.5)))
        XCTAssertNil(document.set(.lookID("film")))
        XCTAssertNil(document.set(.lookIntensity(0.4)))
        XCTAssertNil(document.set(.quarterTurns(1)))
        XCTAssertNil(document.set(.crop(NormalizedRect(x: 0, y: 0, width: 0.5, height: 0.5))))
        XCTAssertEqual(document.recipe.detail.highlights, -0.5)
        XCTAssertEqual(document.recipe.look.id, "film")
        XCTAssertEqual(document.recipe.look.intensity, 0.4)
        XCTAssertEqual(document.recipe.geometry.quarterTurns, 1)
        XCTAssertEqual(document.recipe.geometry.crop?.width, 0.5)
    }

    func testQuarterTurnsWrapAndStraightenClamps() {
        var document = EditDocument()
        document.set(.quarterTurns(5))
        XCTAssertEqual(document.recipe.geometry.quarterTurns, 1)
        document.set(.straightenDegrees(40))
        XCTAssertEqual(document.recipe.geometry.straightenDegrees, GeometryAdjustments.maxStraightenDegrees)
    }

    func testPresetCarriesDetailButNotLookOrGeometry() {
        var document = EditDocument()
        document.set(.lookID("mono"))
        document.set(.quarterTurns(2))
        document.apply(PresetValues(detail: DetailAdjustments(vignette: 0.4)))
        XCTAssertEqual(document.recipe.detail.vignette, 0.4)
        XCTAssertEqual(document.recipe.look.id, "mono")
        XCTAssertEqual(document.recipe.geometry.quarterTurns, 2)
    }

    func testApplyAutoIsOneUndoStepAndKeepsLockedGeometry() {
        var document = EditDocument()
        document.set(.faceSlim(0.2))
        document.set(.targetFace(1))
        document.appendLocalEdit(.warp(WarpStroke(x: 0.5, y: 0.5, dx: 0.01, dy: 0, radius: 0.1)))
        document.set(.lookID("film"))
        let before = document.undoStack.count
        let suggestion = AutoEnhanceSuggestion(
            color: ColorAdjustments(exposure: 0.3, saturation: 1.08),
            detail: DetailAdjustments(highlights: -0.2),
            portrait: PortraitAdjustments(skinSmoothing: 0.3, faceSlim: 0.15))
        document.applyAuto(suggestion)
        XCTAssertEqual(document.undoStack.count, before + 1)
        XCTAssertEqual(document.recipe.color.exposure, 0.3)
        XCTAssertEqual(document.recipe.detail.highlights, -0.2)
        XCTAssertEqual(document.recipe.portrait.skinSmoothing, 0.3)
        XCTAssertEqual(document.recipe.portrait.faceSlim, 0.2, "잠긴 사진은 얼굴 형태 유지")
        XCTAssertEqual(document.recipe.portrait.targetFace, 1)
        XCTAssertEqual(document.recipe.look.id, "film", "자동 보정은 룩을 건드리지 않는다")
        XCTAssertEqual(document.recipe.operations.count, 1)
        document.undo()
        XCTAssertEqual(document.recipe.color.exposure, 0)
    }

    func testApplyAutoWithSameValuesIsNoOp() {
        var document = EditDocument()
        let first = AutoEnhanceSuggestion(
            color: ColorAdjustments(exposure: 0.3), detail: DetailAdjustments(shadows: 0.2),
            portrait: PortraitAdjustments(skinSmoothing: 0.3))
        let second = AutoEnhanceSuggestion(
            color: ColorAdjustments(exposure: 0.5), detail: DetailAdjustments(), portrait: PortraitAdjustments())
        XCTAssertTrue(document.applyAuto(first))
        XCTAssertTrue(document.applyAuto(second))
        document.undo()
        let recipe = document.recipe
        let undoCount = document.undoStack.count
        XCTAssertFalse(document.applyAuto(first), "이미 같은 값이면 적용하지 않는다")
        XCTAssertEqual(document.recipe, recipe)
        XCTAssertEqual(document.undoStack.count, undoCount, "체크포인트를 만들지 않는다")
        XCTAssertEqual(document.redoStack.count, 1, "다시 실행 기록도 지우지 않는다")
        document.undo()
        XCTAssertTrue(document.recipe.isDefault)
    }
}
