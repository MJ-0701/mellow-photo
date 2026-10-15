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

    func testLocalEditLocksFaceShapeAndTargetFace() {
        var document = EditDocument()
        document.set(.faceShape(.width, -0.2))
        document.set(.targetFace(1))
        document.appendLocalEdit(.spot(RetouchSpot(x: 0.5, y: 0.4, sourceX: 0.4, sourceY: 0.4, radius: 0.02)))
        XCTAssertTrue(document.isGeometryLocked)
        XCTAssertEqual(document.set(.faceShape(.width, -0.9)), .geometryLocked)
        XCTAssertEqual(document.set(.faceShape(.jaw, 0.3)), .geometryLocked)
        XCTAssertEqual(document.set(.targetFace(nil)), .geometryLocked)
        XCTAssertEqual(document.recipe.portrait.face, FaceShapeAdjustments(width: -0.2))
        XCTAssertEqual(document.recipe.portrait.targetFace, 1)
        XCTAssertNil(document.set(.skinSmoothing(0.5)))
        // 피부 보정, 수동 편집 순으로 되돌린다.
        document.undo()
        document.undo()
        XCTAssertFalse(document.isGeometryLocked)
    }

    func testAutoBlemishIsNotLockedAndUndoesInOneStep() {
        var document = EditDocument()
        document.appendLocalEdit(.warp(WarpStroke(x: 0.5, y: 0.5, dx: 0.01, dy: 0, radius: 0.1)))
        XCTAssertNil(document.set(.autoBlemish(true)))
        XCTAssertTrue(document.recipe.portrait.skin.autoBlemish)
        let count = document.undoStack.count
        XCTAssertNil(document.set(.autoBlemish(true)))
        XCTAssertEqual(document.undoStack.count, count, "같은 값은 단계를 만들지 않는다")
        document.undo()
        XCTAssertFalse(document.recipe.portrait.skin.autoBlemish)
    }

    func testNewChangesClampToPolicyRanges() {
        var document = EditDocument()
        document.set(.skinSmoothing(1.5))
        XCTAssertEqual(document.recipe.portrait.skin.smoothing, EditingPolicy.unitRange.upperBound)
        document.set(.faceShape(.width, -3))
        XCTAssertEqual(document.recipe.portrait.face.width, EditingPolicy.bipolarRange.lowerBound)
        document.set(.faceShape(.smile, -0.5))
        XCTAssertEqual(document.recipe.portrait.face.smile, 0, "미소는 한 방향만")
        document.set(.faceShape(.eyeSize, 0.4))
        XCTAssertEqual(document.recipe.portrait.face.eyeSize, 0.4)
        XCTAssertEqual(EditingPolicy.faceShapeRange(.smile), 0...1)
        XCTAssertEqual(EditingPolicy.faceShapeRange(.jaw), -1...1)
    }

    func testEditingPolicyForwardsSharedRanges() {
        XCTAssertEqual(EditingPolicy.unitRange, AdjustmentRange.unit)
        XCTAssertEqual(EditingPolicy.bipolarRange, AdjustmentRange.bipolar)
        for key in FaceShapeKey.allCases {
            XCTAssertEqual(EditingPolicy.faceShapeRange(key), AdjustmentRange.faceShape(key), "\(key)")
        }
        XCTAssertEqual(AdjustmentRange.faceShape(.smile), 0...1)
        XCTAssertEqual(AdjustmentRange.clamped(.nan, to: AdjustmentRange.bipolar), -1, "NaN은 아래 끝")
        XCTAssertEqual(EditingPolicy.clamped(4, to: AdjustmentRange.unit), 1)
    }

    func testFeatureAndBackgroundChangesClampAndStayUnlocked() {
        var document = EditDocument()
        document.appendLocalEdit(.spot(RetouchSpot(x: 0.5, y: 0.4, sourceX: 0.4, sourceY: 0.4, radius: 0.02)))
        XCTAssertNil(document.set(.feature(.eyeBrighten, 0.4)), "색만 바꾸므로 수동 편집이 있어도 잠기지 않는다")
        XCTAssertNil(document.set(.feature(.teethWhiten, 1.7)))
        XCTAssertNil(document.set(.feature(.lipVitality, -0.2)))
        XCTAssertNil(document.set(.backgroundBlur(2)))
        XCTAssertEqual(
            document.recipe.portrait.features, FeatureAdjustments(eyeBrighten: 0.4, teethWhiten: 1, lipVitality: 0))
        XCTAssertEqual(document.recipe.background.blur, 1)
        XCTAssertFalse(EditChange.feature(.eyeBrighten, 0.5).affectsGeometry)
        XCTAssertFalse(EditChange.backgroundBlur(0.5).affectsGeometry)
        document.undo()
        XCTAssertEqual(document.recipe.background.blur, 0, "변경마다 실행 취소 한 단계")
        XCTAssertEqual(document.recipe.portrait.features.teethWhiten, 1)
    }

    func testBodyShapeChangesClampAndAreOneUndoStepEach() {
        var document = EditDocument()
        XCTAssertNil(document.set(.bodyShape(.waist, -1.7)))
        XCTAssertNil(document.set(.bodyShape(.legLength, -0.4)), "다리 길게는 0 아래로 가지 않는다")
        XCTAssertNil(document.set(.bodyShape(.legLength, 2)))
        XCTAssertNil(document.set(.bodyShape(.neck, 0.3)))
        XCTAssertEqual(document.recipe.body, BodyShapeAdjustments(legLength: 1, waist: -1, neck: 0.3))
        XCTAssertEqual(EditingPolicy.bodyShapeRange(.legLength), EditingPolicy.unitRange)
        XCTAssertEqual(EditingPolicy.bodyShapeRange(.arms), EditingPolicy.bipolarRange)
        document.undo()
        XCTAssertEqual(document.recipe.body.neck, 0, "변경마다 실행 취소 한 단계")
        XCTAssertEqual(document.recipe.body.legLength, 1)
    }

    func testBodyShapeIsLockedByLocalEditsLikeFaceShape() {
        var document = EditDocument()
        document.appendLocalEdit(.warp(WarpStroke(x: 0.5, y: 0.5, dx: 0.01, dy: 0, radius: 0.1)))
        XCTAssertTrue(EditChange.bodyShape(.waist, -0.5).affectsGeometry)
        for key in BodyShapeKey.allCases {
            XCTAssertEqual(document.set(.bodyShape(key, 0.5)), .geometryLocked, "\(key)는 잠긴다")
        }
        XCTAssertEqual(document.recipe.body, BodyShapeAdjustments())
        XCTAssertEqual(document.undoStack.count, 1, "거절된 변경은 실행 취소 단계를 만들지 않는다")
    }

    func testMakeupChangesClampDetachLookAndAreNotLocked() {
        var document = EditDocument()
        document.appendLocalEdit(.spot(RetouchSpot(x: 0.5, y: 0.5, sourceX: 0.4, sourceY: 0.4, radius: 0.02)))
        XCTAssertFalse(EditChange.makeupIntensity(.lip, 0.5).affectsGeometry)
        XCTAssertFalse(EditChange.makeupColor(.lip, "lip-coral").affectsGeometry)
        XCTAssertNil(document.set(.makeupColor(.lip, "lip-coral")), "메이크업은 수동 편집이 있어도 잠기지 않는다")
        XCTAssertEqual(
            document.recipe.makeup.lip,
            MakeupTint(colorID: "lip-coral", intensity: EditingPolicy.makeupDefaultIntensity),
            "색을 처음 고르면 기본 강도")
        XCTAssertEqual(EditingPolicy.makeupDefaultIntensity, 0.5)
        XCTAssertNil(document.set(.makeupIntensity(.lip, 1.7)))
        XCTAssertEqual(document.recipe.makeup.lip.intensity, 1)
        XCTAssertNil(document.set(.makeupIntensity(.brow, -0.3)))
        XCTAssertEqual(document.recipe.makeup.brow.intensity, 0)
        document.set(.makeupColor(.lip, "lip-red"))
        XCTAssertEqual(document.recipe.makeup.lip, MakeupTint(colorID: "lip-red", intensity: 1), "강도가 있으면 색만 바꾼다")
        let steps = document.undoStack.count
        document.set(.makeupColor(.brow, "lip-red"))
        XCTAssertEqual(document.undoStack.count, steps, "눈썹은 색이 없어 무시한다")
        XCTAssertNil(document.recipe.makeup.colorID(of: .brow))
        document.set(.makeupColor(.lip, nil))
        XCTAssertEqual(document.recipe.makeup.lip, MakeupTint(colorID: nil, intensity: 1), "색을 빼도 강도는 남는다")
    }

    func testApplyMakeupLookIsOneUndoStepAndPartEditsDetachLook() {
        let look = MakeupLook(
            id: "daily", name: "데일리", lip: MakeupTint(colorID: "lip-mlbb", intensity: 0.5),
            blush: MakeupTint(colorID: "blush-peach", intensity: 0.35),
            eyeshadow: MakeupTint(colorID: "shadow-brown", intensity: 0.3), brow: MakeupStrength(intensity: 0.3),
            contour: MakeupStrength(intensity: 0.2))
        var document = EditDocument()
        document.appendLocalEdit(.warp(WarpStroke(x: 0.5, y: 0.5, dx: 0.01, dy: 0, radius: 0.1)))
        document.set(.makeupIntensity(.brow, 0.9))
        let before = document.undoStack.count
        document.applyMakeupLook(look)
        XCTAssertEqual(document.recipe.makeup, look.adjustments, "잠긴 사진에도 룩을 적용한다")
        XCTAssertEqual(document.recipe.makeup.lookID, "daily")
        XCTAssertEqual(document.undoStack.count, before + 1, "룩 적용은 체크포인트 한 번")
        document.applyMakeupLook(look)
        XCTAssertEqual(document.undoStack.count, before + 1, "같은 룩을 다시 골라도 단계가 늘지 않는다")
        document.set(.makeupIntensity(.blush, 0.35))
        XCTAssertEqual(document.recipe.makeup.lookID, "daily", "값이 그대로면 룩을 유지한다")
        document.set(.makeupIntensity(.blush, 0.6))
        XCTAssertNil(document.recipe.makeup.lookID, "부위를 바꾸면 룩 이름을 지운다")
        XCTAssertEqual(document.recipe.makeup.lip, look.lip, "나머지 부위는 룩 값 그대로")
        document.undo()
        XCTAssertEqual(document.recipe.makeup, look.adjustments)
        document.undo()
        XCTAssertEqual(document.recipe.makeup.brow.intensity, 0.9, "실행 취소 한 번에 룩 적용 전으로")
        XCTAssertNil(document.recipe.makeup.lookID)
        document.redo()
        document.applyMakeupLook(nil)
        XCTAssertEqual(document.recipe.makeup, MakeupAdjustments(), "없음은 메이크업을 모두 지운다")
    }

    func testPresetAndBatchCarryFeaturesAndBackground() {
        let values = PresetValues(
            portrait: PortraitAdjustments(features: FeatureAdjustments(eyeBrighten: 0.3, lipVitality: 0.2)),
            background: BackgroundAdjustments(blur: 0.5))
        var preset = EditDocument()
        preset.apply(values)
        var locked = EditDocument()
        locked.appendLocalEdit(.warp(WarpStroke(x: 0.5, y: 0.5, dx: 0.01, dy: 0, radius: 0.1)))
        locked.applyFromBatch(values)
        for document in [preset, locked] {
            XCTAssertEqual(document.recipe.portrait.features, FeatureAdjustments(eyeBrighten: 0.3, lipVitality: 0.2))
            XCTAssertEqual(document.recipe.background.blur, 0.5, "잠긴 사진도 색 보정은 복사한다")
        }
    }

    func testPresetPreservesFaceShapeWhenLocked() {
        var document = EditDocument()
        document.set(.faceShape(.width, -0.2))
        document.appendLocalEdit(.warp(WarpStroke(x: 0.5, y: 0.5, dx: 0.01, dy: 0, radius: 0.1)))
        let preset = PresetValues(
            color: ColorAdjustments(exposure: 0.5),
            portrait: PortraitAdjustments(face: FaceShapeAdjustments(width: -0.7)))
        document.apply(preset)
        XCTAssertEqual(document.recipe.color.exposure, 0.5)
        XCTAssertEqual(document.recipe.portrait.face.width, -0.2)
        XCTAssertEqual(document.recipe.operations.count, 1)
    }

    func testPresetReplacesEverythingWhenUnlocked() {
        var document = EditDocument()
        document.set(.targetFace(2))
        document.apply(
            PresetValues(
                portrait: PortraitAdjustments(targetFace: 5, face: FaceShapeAdjustments(width: -0.7)),
                background: BackgroundAdjustments(blur: 0.4), body: BodyShapeAdjustments(waist: -0.3),
                makeup: MakeupAdjustments(brow: MakeupStrength(intensity: 0.5))))
        XCTAssertEqual(document.recipe.portrait.face.width, -0.7)
        XCTAssertEqual(document.recipe.portrait.targetFace, 2, "프리셋은 얼굴을 고르지 않으므로 사진의 대상 얼굴을 유지한다")
        XCTAssertEqual(document.recipe.background.blur, 0.4)
        XCTAssertEqual(document.recipe.body.waist, -0.3)
        XCTAssertEqual(document.recipe.makeup.brow.intensity, 0.5)
    }

    func testBatchApplyKeepsLockedShapeAndCopiesTheRest() {
        var locked = EditDocument()
        locked.set(.faceShape(.width, -0.2))
        locked.set(.targetFace(1))
        locked.appendLocalEdit(.spot(RetouchSpot(x: 0.5, y: 0.4, sourceX: 0.4, sourceY: 0.4, radius: 0.02)))
        var unlocked = EditDocument()
        unlocked.set(.targetFace(0))
        let values = PresetValues(
            color: ColorAdjustments(exposure: 0.3),
            portrait: PortraitAdjustments(
                targetFace: 3, skin: SkinAdjustments(smoothing: 0.6), face: FaceShapeAdjustments(width: -0.9)),
            body: BodyShapeAdjustments(legLength: 0.4),
            makeup: MakeupAdjustments(lip: MakeupTint(colorID: "lip-coral", intensity: 0.5)))
        locked.applyFromBatch(values)
        unlocked.applyFromBatch(values)
        XCTAssertEqual(locked.recipe.portrait.face.width, -0.2)
        XCTAssertEqual(locked.recipe.body, BodyShapeAdjustments(), "잠긴 사진은 체형도 유지한다")
        XCTAssertEqual(locked.recipe.portrait.targetFace, 1)
        XCTAssertEqual(locked.recipe.portrait.skin.smoothing, 0.6, "피부는 잠금과 무관하게 복사한다")
        XCTAssertEqual(locked.recipe.makeup.lip.colorID, "lip-coral")
        XCTAssertEqual(locked.recipe.color.exposure, 0.3)
        XCTAssertEqual(unlocked.recipe.portrait.face.width, -0.9)
        XCTAssertEqual(unlocked.recipe.body.legLength, 0.4)
        XCTAssertNil(unlocked.recipe.portrait.targetFace)
        XCTAssertTrue(locked.canUndo)
        XCTAssertTrue(unlocked.canUndo)
    }

    func testApplyAutoIsOneUndoStepAndLeavesShapeAlone() {
        var recipe = EditRecipe()
        recipe.body.waist = -0.3
        recipe.makeup.lip = MakeupTint(colorID: "lip-rose", intensity: 0.4)
        var document = EditDocument(recipe: recipe)
        document.set(.faceShape(.width, -0.2))
        document.set(.targetFace(1))
        document.set(.lookID("film"))
        let before = document.undoStack.count
        let suggestion = AutoEnhanceSuggestion(
            color: ColorAdjustments(exposure: 0.3, saturation: 1.08), detail: DetailAdjustments(highlights: -0.2),
            portrait: PortraitAdjustments(skin: SkinAdjustments(smoothing: 0.3, autoBlemish: true)))
        document.applyAuto(suggestion)
        XCTAssertEqual(document.undoStack.count, before + 1)
        XCTAssertEqual(document.recipe.color.exposure, 0.3)
        XCTAssertEqual(document.recipe.detail.highlights, -0.2)
        XCTAssertEqual(document.recipe.portrait.skin, SkinAdjustments(smoothing: 0.3, autoBlemish: true))
        XCTAssertEqual(document.recipe.portrait.face.width, -0.2, "자동 보정은 얼굴형을 건드리지 않는다")
        XCTAssertEqual(document.recipe.portrait.targetFace, 1)
        XCTAssertEqual(document.recipe.body.waist, -0.3)
        XCTAssertEqual(document.recipe.makeup.lip.colorID, "lip-rose")
        XCTAssertEqual(document.recipe.look.id, "film", "자동 보정은 룩을 건드리지 않는다")
        document.undo()
        XCTAssertEqual(document.recipe.color.exposure, 0)
    }

    func testApplyAutoKeepsTeethLipsAndBackgroundAndSetsOnlyEyeBrighten() {
        var document = EditDocument()
        document.set(.feature(.teethWhiten, 0.6))
        document.set(.feature(.lipVitality, 0.4))
        document.set(.backgroundBlur(0.5))
        let before = document.undoStack.count
        let suggestion = AutoEnhanceSuggestion(
            color: ColorAdjustments(), detail: DetailAdjustments(),
            portrait: PortraitAdjustments(features: FeatureAdjustments(eyeBrighten: 0.2)))
        XCTAssertTrue(document.applyAuto(suggestion))
        XCTAssertEqual(
            document.recipe.portrait.features, FeatureAdjustments(eyeBrighten: 0.2, teethWhiten: 0.6, lipVitality: 0.4),
            "자동 보정은 치아 미백·입술 생기를 지우지 않는다")
        XCTAssertEqual(document.recipe.background.blur, 0.5, "자동 보정은 배경을 건드리지 않는다")
        XCTAssertEqual(document.undoStack.count, before + 1)
        document.undo()
        XCTAssertEqual(
            document.recipe.portrait.features, FeatureAdjustments(eyeBrighten: 0, teethWhiten: 0.6, lipVitality: 0.4))
    }

    func testApplyAutoKeepsBodyShapeAndBackgroundBlur() {
        var document = EditDocument()
        document.set(.bodyShape(.legLength, 0.4))
        document.set(.bodyShape(.waist, -0.3))
        document.set(.backgroundBlur(0.5))
        let body = document.recipe.body
        let before = document.undoStack.count
        let suggestion = AutoEnhanceSuggestion(
            color: ColorAdjustments(exposure: 0.2), detail: DetailAdjustments(),
            portrait: PortraitAdjustments(skin: SkinAdjustments(smoothing: 0.3)))
        XCTAssertTrue(document.applyAuto(suggestion))
        XCTAssertEqual(document.recipe.body, body, "자동 보정은 체형을 건드리지 않는다")
        XCTAssertEqual(document.recipe.background.blur, 0.5, "자동 보정은 배경을 건드리지 않는다")
        XCTAssertEqual(document.undoStack.count, before + 1, "자동 보정은 실행 취소 한 단계")
        document.undo()
        XCTAssertEqual(document.recipe.color.exposure, 0)
        XCTAssertEqual(document.recipe.body, body)
        XCTAssertEqual(document.recipe.background.blur, 0.5)
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

    func testQuarterTurnsMoveCropWithImage() {
        var document = EditDocument()
        let crop = NormalizedRect(x: 0.1, y: 0.2, width: 0.5, height: 0.3)
        document.set(.crop(crop))
        document.set(.quarterTurns(1))
        XCTAssertEqual(document.recipe.geometry.quarterTurns, 1)
        XCTAssertEqual(document.recipe.geometry.crop?.width ?? 0, 0.3, accuracy: 1e-9)
        XCTAssertEqual(document.recipe.geometry.crop?.y ?? 0, 0.4, accuracy: 1e-9)
        document.set(.quarterTurns(0))
        XCTAssertEqual(document.recipe.geometry.quarterTurns, 0)
        XCTAssertEqual(document.recipe.geometry.crop?.x ?? 0, crop.x, accuracy: 1e-9, "남은 세 번을 돌아 제자리")
        XCTAssertEqual(document.recipe.geometry.crop?.width ?? 0, crop.width, accuracy: 1e-9)
        XCTAssertEqual(document.undoStack.count, 3)
    }

    func testFlipMovesCropOnlyWhenFlagChanges() {
        var document = EditDocument()
        document.set(.crop(NormalizedRect(x: 0, y: 0, width: 0.5, height: 1)))
        document.set(.straightenDegrees(4))
        document.set(.flipHorizontal(true))
        XCTAssertTrue(document.recipe.geometry.flipHorizontal)
        XCTAssertEqual(document.recipe.geometry.crop?.x ?? 0, 0.5, accuracy: 1e-9)
        XCTAssertEqual(document.recipe.geometry.straightenDegrees, -4)
        let steps = document.undoStack.count
        document.set(.flipHorizontal(true))
        XCTAssertEqual(document.recipe.geometry.crop?.x ?? 0, 0.5, accuracy: 1e-9, "같은 값이면 다시 옮기지 않는다")
        XCTAssertEqual(document.undoStack.count, steps)
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

    func testApplyAutoWithSameValuesIsNoOp() {
        var document = EditDocument()
        let first = AutoEnhanceSuggestion(
            color: ColorAdjustments(exposure: 0.3), detail: DetailAdjustments(shadows: 0.2),
            portrait: PortraitAdjustments(skin: SkinAdjustments(smoothing: 0.3)))
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
