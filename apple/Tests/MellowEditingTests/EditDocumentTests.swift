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

    func testLocalEditLocksFaceShapeAndGender() {
        var document = EditDocument()
        document.set(.faceShape(.width, -0.2))
        document.set(.gender(.female), forFace: 0, of: twoFaces)
        document.appendLocalEdit(.spot(RetouchSpot(x: 0.5, y: 0.4, sourceX: 0.4, sourceY: 0.4, radius: 0.02)))
        XCTAssertTrue(document.isGeometryLocked)
        XCTAssertEqual(document.set(.faceShape(.width, -0.9)), .geometryLocked)
        XCTAssertEqual(document.set(.faceShape(.jaw, 0.3)), .geometryLocked)
        XCTAssertEqual(
            document.set(.gender(nil), in: .person(document.recipe.people.individuals[0].id)), .geometryLocked)
        XCTAssertEqual(document.recipe.portrait.face, FaceShapeAdjustments(width: -0.2))
        XCTAssertEqual(document.recipe.people.individuals[0].gender, .female)
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

    func testSkinRefinementChangesClampAreNotLockedAndUndoOneStepEach() {
        var document = EditDocument()
        document.appendLocalEdit(.spot(RetouchSpot(x: 0.5, y: 0.5, sourceX: 0.4, sourceY: 0.4, radius: 0.02)))
        let steps = document.undoStack.count
        XCTAssertFalse(EditChange.skinRefinement(.redness, 0.5).affectsGeometry)
        XCTAssertNil(document.set(.skinRefinement(.darkCircles, 1.7)), "색만 바꾸므로 수동 편집이 있어도 잠기지 않는다")
        XCTAssertEqual(document.recipe.portrait.skin.darkCircles, 1)
        XCTAssertNil(document.set(.skinRefinement(.redness, -3)))
        XCTAssertEqual(document.recipe.portrait.skin.redness, -1, "붉은기만 양방향")
        document.set(.skinRefinement(.shine, -0.2))
        XCTAssertEqual(document.recipe.portrait.skin.shine, 0, "한 방향 항목의 음수는 0")
        XCTAssertEqual(document.undoStack.count, steps + 2, "값이 실제로 바뀐 변경마다 한 단계")
        XCTAssertEqual(EditingPolicy.skinRefinementRange(.redness), EditingPolicy.bipolarRange)
        XCTAssertEqual(EditingPolicy.skinRefinementRange(.toneEvening), EditingPolicy.unitRange)
        document.undo()
        XCTAssertEqual(document.recipe.portrait.skin.redness, 0)
        XCTAssertEqual(document.recipe.portrait.skin.darkCircles, 1)
    }

    func testApplyAutoKeepsSkinRefinements() {
        var document = EditDocument()
        document.set(.skinRefinement(.darkCircles, 0.6))
        document.set(.skinRefinement(.redness, -0.3))
        let suggestion = AutoEnhanceSuggestion(
            color: ColorAdjustments(exposure: 0.2), detail: DetailAdjustments(),
            portrait: PortraitAdjustments(skin: SkinAdjustments(smoothing: 0.3, autoBlemish: true)))
        XCTAssertTrue(document.applyAuto(suggestion))
        XCTAssertEqual(
            document.recipe.portrait.skin,
            SkinAdjustments(smoothing: 0.3, autoBlemish: true, darkCircles: 0.6, redness: -0.3),
            "자동 보정은 피부 보정·자동 잡티만 쓰고 정밀 값은 지우지 않는다")
        XCTAssertFalse(document.applyAuto(suggestion), "같은 값이면 아무것도 하지 않는다")
        var other = EditDocument()
        other.applyFromBatch(PresetValues(of: document.recipe))
        XCTAssertEqual(other.recipe.portrait.skin.darkCircles, 0.6, "일괄 적용은 정밀 값을 나른다")
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
        document.set(.gender(.male), forFace: 0, of: twoFaces)
        document.apply(
            PresetValues(
                portrait: PortraitAdjustments(face: FaceShapeAdjustments(width: -0.7)),
                background: BackgroundAdjustments(blur: 0.4), body: BodyShapeAdjustments(waist: -0.3),
                makeup: MakeupAdjustments(brow: MakeupStrength(intensity: 0.5))))
        XCTAssertEqual(document.recipe.portrait.face.width, -0.7)
        XCTAssertEqual(document.recipe.people.individuals[0].gender, .male, "프리셋은 사람을 고르지 않으므로 사진의 성별 지정을 유지한다")
        XCTAssertEqual(document.recipe.background.blur, 0.4)
        XCTAssertEqual(document.recipe.body.waist, -0.3)
        XCTAssertEqual(document.recipe.makeup.brow.intensity, 0.5)
    }

    func testBatchApplyKeepsLockedShapeAndCopiesTheRest() {
        var locked = EditDocument()
        locked.set(.faceShape(.width, -0.2))
        locked.appendLocalEdit(.spot(RetouchSpot(x: 0.5, y: 0.4, sourceX: 0.4, sourceY: 0.4, radius: 0.02)))
        var unlocked = EditDocument()
        let values = PresetValues(
            color: ColorAdjustments(exposure: 0.3),
            portrait: PortraitAdjustments(
                skin: SkinAdjustments(smoothing: 0.6), face: FaceShapeAdjustments(width: -0.9)),
            body: BodyShapeAdjustments(legLength: 0.4),
            makeup: MakeupAdjustments(lip: MakeupTint(colorID: "lip-coral", intensity: 0.5)))
        locked.applyFromBatch(values)
        unlocked.applyFromBatch(values)
        XCTAssertEqual(locked.recipe.portrait.face.width, -0.2)
        XCTAssertEqual(locked.recipe.body, BodyShapeAdjustments(), "잠긴 사진은 체형도 유지한다")
        XCTAssertEqual(locked.recipe.portrait.skin.smoothing, 0.6, "피부는 잠금과 무관하게 복사한다")
        XCTAssertEqual(locked.recipe.makeup.lip.colorID, "lip-coral")
        XCTAssertEqual(locked.recipe.color.exposure, 0.3)
        XCTAssertEqual(unlocked.recipe.portrait.face.width, -0.9)
        XCTAssertEqual(unlocked.recipe.body.legLength, 0.4)
        XCTAssertTrue(locked.canUndo)
        XCTAssertTrue(unlocked.canUndo)
    }

    func testBatchCopiesOnlyChosenCategoriesAndKeepsIndividualsWithoutFaceCategories() {
        var values = PresetValues(color: ColorAdjustments(exposure: 0.3), detail: DetailAdjustments(vignette: 0.2))
        values.portrait.skin.smoothing = 0.6
        values.portrait.face.width = -0.5
        values.makeup.lip = MakeupTint(colorID: "lip-coral", intensity: 0.5)
        values.bodySkin.brightness = 0.4
        values.effects.grain = 0.3
        var document = EditDocument()
        document.set(.skinSmoothing(0.9), forFace: 0, of: twoFaces)
        document.set(.feature(.teethWhiten, 0.7))
        document.applyFromBatch(values, categories: [.color, .effects])
        XCTAssertEqual(document.recipe.color.exposure, 0.3)
        XCTAssertEqual(document.recipe.detail.vignette, 0.2, "색감 항목은 디테일을 포함한다")
        XCTAssertEqual(document.recipe.effects.grain, 0.3)
        XCTAssertEqual(document.recipe.portrait.skin.smoothing, 0, "고르지 않은 피부는 그대로")
        XCTAssertEqual(document.recipe.portrait.features.teethWhiten, 0.7)
        XCTAssertNil(document.recipe.makeup.lip.colorID)
        XCTAssertEqual(document.recipe.bodySkin.brightness, 0)
        XCTAssertEqual(document.recipe.people.individuals[0].layer.skinSmoothing, 0.9, "얼굴 의존 항목이 없으면 개인 층을 유지한다")
        document.applyFromBatch(values, categories: [.skin])
        XCTAssertEqual(document.recipe.portrait.skin.smoothing, 0.6)
        XCTAssertTrue(document.recipe.people.individuals.isEmpty, "피부를 복사하면 개인 피부 키를 지운다")
        var locked = EditDocument()
        locked.set(.faceShape(.width, -0.2))
        locked.appendLocalEdit(.spot(RetouchSpot(x: 0.5, y: 0.4, sourceX: 0.4, sourceY: 0.4, radius: 0.02)))
        let before = locked.recipe
        locked.applyFromBatch(values, categories: [.faceShape, .body])
        XCTAssertEqual(locked.recipe, before, "잠긴 사진의 얼굴형·체형은 복사하지 않는다")
        let steps = locked.undoStack.count
        locked.applyFromBatch(values, categories: [])
        XCTAssertEqual(locked.undoStack.count, steps, "빈 선택은 아무것도 하지 않는다")
        XCTAssertEqual(SyncCategory.allCases.count, 9)
        XCTAssertEqual(SyncCategory.allCases.filter(\.dependsOnFaces), [.skin, .faceShape, .features, .makeup])
        XCTAssertEqual(SyncCategory.all, Set(SyncCategory.allCases))
    }

    func testApplyAutoIsOneUndoStepAndLeavesShapeAlone() {
        var recipe = EditRecipe()
        recipe.body.waist = -0.3
        recipe.makeup.lip = MakeupTint(colorID: "lip-rose", intensity: 0.4)
        var document = EditDocument(recipe: recipe)
        document.set(.faceShape(.width, -0.2))
        document.set(.skinSmoothing(0.9), forFace: 0, of: twoFaces)
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
        XCTAssertEqual(document.recipe.people.individuals[0].layer.skinSmoothing, 0.9, "자동 보정은 전체 층에만 쓴다")
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

    func testBodySkinChangesClampAreNotLockedAndAreCopiedByPresetsAndBatch() {
        var document = EditDocument()
        document.appendLocalEdit(.warp(WarpStroke(x: 0.5, y: 0.5, dx: 0.01, dy: 0, radius: 0.1)))
        XCTAssertFalse(EditChange.bodySkin(.tone, 0.5).affectsGeometry)
        XCTAssertNil(document.set(.bodySkin(.brightness, 1.5)), "색만 바꾸므로 잠기지 않는다")
        XCTAssertEqual(document.recipe.bodySkin.brightness, 1)
        XCTAssertNil(document.set(.bodySkin(.tone, -4)))
        XCTAssertEqual(document.recipe.bodySkin.tone, -1, "톤만 양방향")
        document.set(.bodySkin(.smoothing, -0.5))
        XCTAssertEqual(document.recipe.bodySkin.smoothing, 0)
        XCTAssertEqual(EditingPolicy.bodySkinRange(.tone), EditingPolicy.bipolarRange)
        XCTAssertEqual(EditingPolicy.bodySkinRange(.smoothing), EditingPolicy.unitRange)
        var other = EditDocument()
        other.apply(PresetValues(of: document.recipe))
        XCTAssertEqual(other.recipe.bodySkin, BodySkinAdjustments(brightness: 1, tone: -1), "프리셋이 몸 피부를 나른다")
        var third = EditDocument()
        third.applyFromBatch(PresetValues(bodySkin: BodySkinAdjustments(smoothing: 0.4)))
        XCTAssertEqual(third.recipe.bodySkin.smoothing, 0.4, "일괄 적용도 나른다")
    }

    func testApplyAutoKeepsBodySkin() {
        var document = EditDocument()
        document.set(.bodySkin(.brightness, 0.5))
        let suggestion = AutoEnhanceSuggestion(
            color: ColorAdjustments(exposure: 0.1), detail: DetailAdjustments(), portrait: PortraitAdjustments())
        XCTAssertTrue(document.applyAuto(suggestion))
        XCTAssertEqual(document.recipe.bodySkin.brightness, 0.5, "자동 보정은 몸 피부를 건드리지 않는다")
    }

    func testEffectChangesClampAreNotLockedAndAreCopiedButNotByAuto() {
        var document = EditDocument()
        document.appendLocalEdit(.spot(RetouchSpot(x: 0.5, y: 0.5, sourceX: 0.4, sourceY: 0.4, radius: 0.02)))
        XCTAssertFalse(EditChange.effect(.grain, 0.5).affectsGeometry)
        XCTAssertNil(document.set(.effect(.grain, 2)))
        XCTAssertEqual(document.recipe.effects.grain, 1)
        document.set(.effect(.glow, -1))
        XCTAssertEqual(document.recipe.effects.glow, 0)
        let suggestion = AutoEnhanceSuggestion(
            color: ColorAdjustments(exposure: 0.1), detail: DetailAdjustments(), portrait: PortraitAdjustments())
        document.applyAuto(suggestion)
        XCTAssertEqual(document.recipe.effects.grain, 1, "자동 보정은 효과를 건드리지 않는다")
        var other = EditDocument()
        other.apply(PresetValues(of: document.recipe))
        XCTAssertEqual(other.recipe.effects.grain, 1, "프리셋이 효과를 나른다")
        var third = EditDocument()
        third.applyFromBatch(PresetValues(effects: EffectAdjustments(glow: 0.4)))
        XCTAssertEqual(third.recipe.effects.glow, 0.4, "일괄 적용도 나른다")
    }

    func testNoOpBatchAndRepeatedPresetAddNoUndoStep() {
        var locked = EditDocument()
        locked.set(.faceShape(.width, -0.2))
        locked.appendLocalEdit(.spot(RetouchSpot(x: 0.5, y: 0.4, sourceX: 0.4, sourceY: 0.4, radius: 0.02)))
        let lockedSteps = locked.undoStack.count
        let faceOnly = PresetValues(portrait: PortraitAdjustments(face: FaceShapeAdjustments(width: -0.9)))
        locked.applyFromBatch(faceOnly, categories: [.faceShape])
        XCTAssertEqual(locked.undoStack.count, lockedSteps, "잠긴 사진에 얼굴형만 복사하면 단계를 만들지 않는다")
        var document = EditDocument()
        let values = PresetValues(color: ColorAdjustments(exposure: 0.3))
        document.apply(values)
        let presetSteps = document.undoStack.count
        document.apply(values)
        XCTAssertEqual(document.undoStack.count, presetSteps, "같은 프리셋을 다시 고르면 단계를 만들지 않는다")
        document.undo()
        document.apply(PresetValues())
        XCTAssertTrue(document.canRedo, "바뀐 것이 없는 프리셋은 다시 실행 기록도 지우지 않는다")
    }

    /// 모든 그룹을 기본값이 아닌 값으로 채운 프리셋.
    private func filledPresetValues() -> PresetValues {
        var values = PresetValues(
            color: ColorAdjustments(exposure: 0.3, contrast: 1.2, saturation: 0.8, warmth: 0.1),
            detail: DetailAdjustments(highlights: -0.2, shadows: 0.3, sharpness: 0.4, vignette: 0.5),
            background: BackgroundAdjustments(blur: 0.4))
        values.portrait.skin.smoothing = 0.6
        values.portrait.skin.autoBlemish = true
        for key in SkinRefinementKey.allCases {
            values.portrait.skin[key] = 0.3
        }
        for key in FaceShapeKey.allCases {
            values.portrait.face[key] = -0.3
        }
        for key in FeatureKey.allCases {
            values.portrait.features[key] = 0.5
        }
        for part in MakeupPart.allCases {
            values.makeup.setIntensity(0.4, of: part)
            if part.hasColor {
                values.makeup.setColorID("\(part.rawValue)-test", of: part)
            }
        }
        values.makeup.lookID = "look-test"
        for key in BodySkinKey.allCases {
            values.bodySkin[key] = 0.2
        }
        for key in BodyShapeKey.allCases {
            values.body[key] = -0.2
        }
        for key in EffectKey.allCases {
            values.effects[key] = 0.3
        }
        values.people.groups[.male] = PortraitLayer(skinSmoothing: 0.4, face: [.jaw: -0.2])
        values.people.groups[.female] = PortraitLayer(
            features: [.eyeBrighten: 0.3], makeup: [.lip: MakeupTint(colorID: "lip-test", intensity: 0.5)])
        return values
    }

    func testBatchWithAllCategoriesCopiesEveryPresetGroup() {
        let values = filledPresetValues()
        let defaults = PresetValues()
        for (filled, empty) in zip(Mirror(reflecting: values).children, Mirror(reflecting: defaults).children) {
            XCTAssertNotEqual(
                String(describing: filled.value), String(describing: empty.value), "\(filled.label ?? "") 그룹을 채운다")
        }
        let portraits = zip(
            Mirror(reflecting: values.portrait).children, Mirror(reflecting: defaults.portrait).children)
        for (filled, empty) in portraits {
            XCTAssertNotEqual(
                String(describing: filled.value), String(describing: empty.value), "\(filled.label ?? "") 묶음을 채운다")
        }
        var document = EditDocument()
        document.set(.skinSmoothing(0.9), forFace: 0, of: twoFaces)
        document.applyFromBatch(values, categories: SyncCategory.all)
        XCTAssertTrue(document.recipe.people.individuals.isEmpty, "전부 복사하면 개인 층의 얼굴 키가 모두 빠진다")
        XCTAssertEqual(PresetValues(of: document.recipe), values, "전부를 고르면 프리셋의 모든 그룹을 복사한다")
    }

    /// 두 사람 사진의 얼굴 상자(왼쪽 중심 x 0.3, 오른쪽 0.7).
    private let twoFaces = [
        NormalizedRect(x: 0.2, y: 0.35, width: 0.2, height: 0.3),
        NormalizedRect(x: 0.6, y: 0.35, width: 0.2, height: 0.3),
    ]
    private var faceAnchor: PersonAnchor { PersonAnchor(faceBox: twoFaces[0]) }

    func testScopedSetWritesOnlyThatLayerAndClamps() {
        var document = EditDocument()
        document.set(.skinSmoothing(0.2))
        XCTAssertNil(document.set(.skinSmoothing(1.7), in: .gender(.female)))
        XCTAssertEqual(document.recipe.people.groups[.female], PortraitLayer(skinSmoothing: 1), "층 값도 같은 범위로 자른다")
        XCTAssertEqual(document.recipe.portrait.skin.smoothing, 0.2, "전체 층은 그대로")
        XCTAssertNil(document.set(.skinRefinement(.redness, -3), in: .gender(.female)))
        XCTAssertEqual(document.recipe.people.groups[.female]?.skinRefinement[.redness], -1)
        XCTAssertNil(document.set(.faceShape(.width, -0.4), in: .gender(.male)))
        XCTAssertNil(document.set(.feature(.eyeBrighten, 0.5), in: .gender(.male)))
        XCTAssertNil(document.set(.autoBlemish(true), in: .gender(.male)))
        XCTAssertEqual(
            document.recipe.people.groups[.male],
            PortraitLayer(autoBlemish: true, face: [.width: -0.4], features: [.eyeBrighten: 0.5]))
        XCTAssertNil(document.set(.exposure(0.3), in: .gender(.male)), "얼굴 의존이 아닌 변경은 scope를 무시한다")
        XCTAssertEqual(document.recipe.color.exposure, 0.3)
        XCTAssertEqual(document.set(.skinSmoothing(0.5), in: .person(PersonID())), .unknownPerson)
        XCTAssertNil(document.set(.makeupColor(.lip, "lip-rose"), in: .gender(.female)))
        XCTAssertEqual(
            document.recipe.people.groups[.female]?.makeup[.lip],
            MakeupTint(colorID: "lip-rose", intensity: EditingPolicy.makeupDefaultIntensity),
            "층에서 색을 처음 고르면 기본 강도")
        document.set(.makeupIntensity(.lip, 0.8), in: .gender(.female))
        XCTAssertEqual(document.recipe.people.groups[.female]?.makeup[.lip]?.intensity, 0.8)
        XCTAssertNil(document.set(.makeupIntensity(.brow, 2), in: .gender(.female)))
        XCTAssertEqual(document.recipe.people.groups[.female]?.makeup[.brow], MakeupTint(colorID: nil, intensity: 1))
        XCTAssertEqual(document.recipe.makeup, MakeupAdjustments(), "전체 층 메이크업은 그대로")
        let steps = document.undoStack.count
        document.set(.skinSmoothing(1), in: .gender(.female))
        XCTAssertEqual(document.undoStack.count, steps, "같은 값은 체크포인트를 만들지 않는다")
        document.beginContinuousChange()
        document.set(.skinSmoothing(0.3), in: .gender(.female))
        document.set(.skinSmoothing(0.4), in: .gender(.female))
        document.endContinuousChange()
        XCTAssertEqual(document.undoStack.count, steps + 1, "드래그는 한 단계")
        document.undo()
        XCTAssertEqual(document.recipe.people.groups[.female]?.skinSmoothing, 1)
    }

    func testFirstTouchOfAFaceCreatesTheRecordAndEmptyRecordsArePruned() {
        var document = EditDocument()
        XCTAssertNil(document.set(.skinSmoothing(0.6), forFace: 0, of: twoFaces))
        XCTAssertEqual(document.recipe.people.individuals.count, 1)
        let id = document.recipe.people.individuals[0].id
        XCTAssertEqual(document.recipe.people.individuals[0].anchor, faceAnchor)
        XCTAssertEqual(document.recipe.people.individuals[0].layer, PortraitLayer(skinSmoothing: 0.6))
        XCTAssertEqual(document.undoStack.count, 1, "기록 생성과 값 쓰기는 한 단계")
        let reanalyzed = [NormalizedRect(x: 0.215, y: 0.35, width: 0.19, height: 0.3), twoFaces[1]]
        XCTAssertNil(document.set(.faceShape(.jaw, 0.2), forFace: 0, of: reanalyzed))
        XCTAssertEqual(document.recipe.people.individuals.count, 1, "조금 움직인 얼굴 상자도 같은 사람")
        XCTAssertEqual(document.recipe.people.individuals[0].id, id)
        XCTAssertEqual(document.recipe.people.person(id)?.layer.face[.jaw], 0.2)
        XCTAssertNil(document.set(.skinSmoothing(0.6), forFace: 0, of: twoFaces))
        XCTAssertEqual(document.undoStack.count, 2, "같은 값은 단계를 만들지 않는다")
        XCTAssertNil(document.resetOverrides(in: .person(id)))
        XCTAssertTrue(document.recipe.people.individuals.isEmpty, "층이 비고 성별도 없는 기록은 지운다")
        document.undo()
        XCTAssertEqual(document.recipe.people.person(id)?.layer.face[.jaw], 0.2)
        XCTAssertNil(document.set(.gender(.female), forFace: 1, of: twoFaces))
        XCTAssertEqual(document.recipe.people.individuals.count, 2)
        let second = document.recipe.people.individuals[1]
        XCTAssertEqual(second.gender, .female)
        XCTAssertTrue(second.layer.isEmpty)
        XCTAssertNil(document.set(.gender(nil), in: .person(second.id)))
        XCTAssertEqual(document.recipe.people.individuals.count, 1, "성별을 풀어 비면 기록도 사라진다")
        XCTAssertTrue(document.hasEdits)
    }

    func testGenderAssignmentIsLockedByLocalEditsAndNeedsAPerson() {
        var document = EditDocument()
        document.set(.gender(.male), forFace: 0, of: twoFaces)
        let id = document.recipe.people.individuals[0].id
        XCTAssertEqual(document.set(.gender(.female), in: .all), .unknownPerson, "성별은 개인에게만")
        XCTAssertEqual(document.set(.gender(.female), in: .gender(.female)), .unknownPerson)
        document.appendLocalEdit(.spot(RetouchSpot(x: 0.5, y: 0.4, sourceX: 0.4, sourceY: 0.4, radius: 0.02)))
        XCTAssertTrue(document.isGeometryLocked)
        XCTAssertEqual(document.set(.gender(.female), in: .person(id)), .geometryLocked)
        XCTAssertEqual(document.recipe.people.person(id)?.gender, .male)
        XCTAssertEqual(document.set(.faceShape(.width, -0.3), in: .person(id)), .geometryLocked)
        XCTAssertEqual(document.set(.faceShape(.width, -0.3), in: .gender(.male)), .geometryLocked)
        XCTAssertNil(document.set(.skinSmoothing(0.4), in: .person(id)), "피부는 잠금과 무관")
        XCTAssertNil(document.set(.feature(.teethWhiten, 0.4), in: .gender(.male)))
        document.undo()
        document.undo()
        document.undo()
        XCTAssertFalse(document.isGeometryLocked)
        XCTAssertNil(document.set(.gender(.female), in: .person(id)))
        XCTAssertEqual(document.recipe.people.person(id)?.gender, .female)
        XCTAssertTrue(EditChange.gender(nil).affectsGeometry)
        XCTAssertEqual(EditChange.makeupColor(.lip, nil).portraitKey, .makeupPart(.lip))
        XCTAssertNil(EditChange.exposure(0).portraitKey)
    }

    func testResetOverridesRestoresInheritanceAndRespectsLock() {
        var document = EditDocument()
        document.set(.skinSmoothing(0.2))
        document.set(.faceShape(.width, -0.5))
        document.set(.skinSmoothing(0.9), in: .gender(.female))
        document.set(.faceShape(.width, 0.3), in: .gender(.female))
        document.set(.makeupColor(.lip, "lip-rose"), in: .gender(.female))
        XCTAssertNil(document.resetOverrides([.skinSmoothing], in: .gender(.female)))
        XCTAssertEqual(
            document.recipe.people.groups[.female]?.overriddenKeys, [.faceShape(.width), .makeupPart(.lip)],
            "지운 키는 상속으로 돌아간다")
        XCTAssertNil(document.resetOverrides(in: .gender(.female)))
        XCTAssertNil(document.recipe.people.groups[.female], "빈 그룹 층은 키를 지운다")
        XCTAssertEqual(document.recipe.portrait.face.width, -0.5, "전체 층은 그대로")
        XCTAssertNil(document.resetOverrides([.faceShape(.width)], in: .all))
        XCTAssertEqual(document.recipe.portrait.face.width, 0, "전체 층의 재설정은 기본값")
        XCTAssertEqual(document.recipe.portrait.skin.smoothing, 0.2)
        document.set(.faceShape(.jaw, 0.4), in: .gender(.male))
        document.set(.skinSmoothing(0.7), in: .gender(.male))
        document.appendLocalEdit(.warp(WarpStroke(x: 0.5, y: 0.5, dx: 0.01, dy: 0, radius: 0.1)))
        XCTAssertEqual(document.resetOverrides(in: .gender(.male)), .geometryLocked, "얼굴형 키가 든 층 전체 초기화는 거절")
        XCTAssertNil(document.resetOverrides([.skinSmoothing], in: .gender(.male)), "얼굴형이 아닌 키만이면 허용")
        XCTAssertEqual(document.recipe.people.groups[.male], PortraitLayer(face: [.jaw: 0.4]))
        XCTAssertEqual(document.resetOverrides(in: .person(PersonID())), .unknownPerson)
    }

    func testRebindRemoveBindLegacyAndScopedLookAreOneUndoStep() throws {
        var document = EditDocument()
        document.set(.skinSmoothing(0.6), forFace: 0, of: twoFaces)
        let id = document.recipe.people.individuals[0].id
        let elsewhere = PersonAnchor(x: 0.8, y: 0.5, width: 0.2)
        XCTAssertNil(document.rebindPerson(id, to: elsewhere))
        XCTAssertEqual(document.recipe.people.person(id)?.anchor, elsewhere)
        XCTAssertEqual(document.undoStack.count, 2)
        XCTAssertEqual(document.rebindPerson(PersonID(), to: elsewhere), .unknownPerson)
        XCTAssertNil(document.removePerson(id))
        XCTAssertTrue(document.recipe.people.individuals.isEmpty)
        document.undo()
        XCTAssertEqual(document.recipe.people.person(id)?.anchor, elsewhere)
        var legacy = EditDocument(
            recipe: EditRecipe(
                people: PeopleAdjustments(individuals: [
                    PersonRecord(id: .legacy(index: 1), legacyIndex: 1, layer: PortraitLayer(skinSmoothing: 0.3)),
                    PersonRecord(id: .legacy(index: 5), legacyIndex: 5, layer: PortraitLayer(skinSmoothing: 0.4)),
                ])))
        let faces = [
            NormalizedRect(x: 0.1, y: 0.3, width: 0.2, height: 0.3),
            NormalizedRect(x: 0.6, y: 0.3, width: 0.2, height: 0.3),
        ]
        XCTAssertTrue(legacy.bindLegacyPeople(faces: faces))
        XCTAssertEqual(legacy.recipe.people.individuals[0].anchor, PersonAnchor(faceBox: faces[1]))
        XCTAssertNil(legacy.recipe.people.individuals[0].legacyIndex)
        XCTAssertEqual(legacy.recipe.people.individuals[1].legacyIndex, 5, "범위 밖 인덱스는 그대로 남는다")
        XCTAssertFalse(legacy.canUndo, "연결은 체크포인트가 아니다")
        XCTAssertFalse(legacy.bindLegacyPeople(faces: faces), "두 번째는 바뀐 것이 없다")
        let look = MakeupLook(
            id: "daily", name: "데일리", lip: MakeupTint(colorID: "lip-coral", intensity: 0.5),
            blush: MakeupTint(colorID: "blush-peach", intensity: 0.3),
            eyeshadow: MakeupTint(colorID: "shadow-brown", intensity: 0.2), brow: MakeupStrength(intensity: 0.4),
            contour: MakeupStrength(intensity: 0.1))
        var looked = EditDocument()
        looked.applyMakeupLook(look, in: .gender(.female))
        XCTAssertEqual(looked.undoStack.count, 1)
        XCTAssertEqual(looked.recipe.people.groups[.female]?.makeupLookID, "daily")
        XCTAssertEqual(
            looked.recipe.people.groups[.female]?.makeup[.lip], MakeupTint(colorID: "lip-coral", intensity: 0.5))
        XCTAssertEqual(looked.recipe.people.groups[.female]?.makeup[.contour], MakeupTint(colorID: nil, intensity: 0.1))
        XCTAssertEqual(looked.recipe.makeup, MakeupAdjustments(), "전체 층은 그대로")
        looked.set(.makeupIntensity(.lip, 0.9), in: .gender(.female))
        XCTAssertNil(looked.recipe.people.groups[.female]?.makeupLookID, "부위를 바꾸면 룩 이름을 지운다")
        looked.applyMakeupLook(nil, in: .gender(.female))
        XCTAssertEqual(looked.recipe.people.groups[.female]?.makeup.count, 5, "층의 룩 없음은 다섯 부위를 0으로 덮어쓴다")
        XCTAssertTrue(looked.recipe.people.groups[.female]!.makeup.values.allSatisfy { $0.intensity == 0 })
    }

    func testPresetKeepsIndividualsAndGenderButReplacesGroups() {
        var document = EditDocument()
        document.set(.skinSmoothing(0.8), in: .gender(.female))
        document.set(.gender(.female), forFace: 0, of: twoFaces)
        document.set(.faceShape(.width, -0.3), forFace: 0, of: twoFaces)
        let id = document.recipe.people.individuals[0].id
        var values = PresetValues(color: ColorAdjustments(exposure: 0.2))
        values.people.groups[.male] = PortraitLayer(skinSmoothing: 0.1)
        document.apply(values)
        XCTAssertEqual(document.recipe.people.groups, [.male: PortraitLayer(skinSmoothing: 0.1)], "그룹 층은 통째로 바뀐다")
        XCTAssertEqual(document.recipe.people.person(id)?.gender, .female)
        XCTAssertEqual(document.recipe.people.person(id)?.layer, PortraitLayer(face: [.width: -0.3]), "개인 층은 그대로")
        var locked = EditDocument()
        locked.set(.faceShape(.jaw, 0.2), in: .gender(.female))
        locked.appendLocalEdit(.spot(RetouchSpot(x: 0.5, y: 0.4, sourceX: 0.4, sourceY: 0.4, radius: 0.02)))
        var shaping = PresetValues()
        shaping.people.groups[.female] = PortraitLayer(skinSmoothing: 0.5, face: [.jaw: 0.9])
        locked.apply(shaping)
        XCTAssertEqual(
            locked.recipe.people.groups[.female], PortraitLayer(skinSmoothing: 0.5, face: [.jaw: 0.2]),
            "잠긴 사진은 그룹의 얼굴형도 보존하고 나머지는 받는다")
        XCTAssertNil(SyncCategory.color.portraitKeys)
        XCTAssertEqual(SyncCategory.skin.portraitKeys, PortraitKey.skin)
        XCTAssertEqual(SyncCategory.makeup.portraitKeys, PortraitKey.makeup)
    }

    func testBatchSyncCopiesGroupsAndClearsIndividualKeysOfSyncedCategories() {
        var document = EditDocument()
        document.set(.skinSmoothing(0.9), in: .gender(.male))
        document.set(.gender(.female), forFace: 0, of: twoFaces)
        document.set(.skinSmoothing(0.7), forFace: 0, of: twoFaces)
        document.set(.faceShape(.width, -0.3), forFace: 0, of: twoFaces)
        document.set(.makeupColor(.lip, "lip-rose"), forFace: 0, of: twoFaces)
        let id = document.recipe.people.individuals[0].id
        var values = PresetValues(color: ColorAdjustments(exposure: 0.3))
        values.portrait.skin.smoothing = 0.4
        values.people.groups[.female] = PortraitLayer(skinSmoothing: 0.5, face: [.jaw: 0.2])
        document.applyFromBatch(values, categories: [.color])
        XCTAssertEqual(document.recipe.color.exposure, 0.3)
        XCTAssertEqual(document.recipe.people.groups[.male], PortraitLayer(skinSmoothing: 0.9), "색감만이면 그룹도 그대로")
        XCTAssertEqual(
            document.recipe.people.person(id)?.layer.overriddenKeys,
            [.skinSmoothing, .faceShape(.width), .makeupPart(.lip)])
        document.applyFromBatch(values, categories: [.skin])
        XCTAssertEqual(document.recipe.portrait.skin.smoothing, 0.4)
        XCTAssertNil(document.recipe.people.groups[.male], "원본에 없는 그룹의 피부 키는 지운다")
        XCTAssertEqual(
            document.recipe.people.groups[.female], PortraitLayer(skinSmoothing: 0.5), "그룹의 피부 키만 복사하고 얼굴형은 아직 아님")
        let person = document.recipe.people.person(id)
        XCTAssertEqual(person?.layer.overriddenKeys, [.faceShape(.width), .makeupPart(.lip)], "개인 층의 피부 키만 빠진다")
        XCTAssertEqual(person?.gender, .female, "성별 지정은 남는다")
        XCTAssertEqual(person?.anchor, faceAnchor)
        var locked = document
        locked.appendLocalEdit(.spot(RetouchSpot(x: 0.5, y: 0.4, sourceX: 0.4, sourceY: 0.4, radius: 0.02)))
        locked.applyFromBatch(values, categories: [.faceShape, .makeup])
        XCTAssertEqual(
            locked.recipe.people.person(id)?.layer.overriddenKeys, [.faceShape(.width)],
            "잠긴 사진은 얼굴형을 건너뛰어 개인 얼굴형 키도 남는다")
        XCTAssertNil(locked.recipe.people.groups[.female]?.face[.jaw])
        document.applyFromBatch(values, categories: [.faceShape, .makeup])
        XCTAssertEqual(document.recipe.people.groups[.female], PortraitLayer(skinSmoothing: 0.5, face: [.jaw: 0.2]))
        XCTAssertEqual(document.recipe.people.person(id)?.layer, PortraitLayer(), "얼굴형·메이크업 키까지 빠져 층이 빈다")
        XCTAssertEqual(document.recipe.people.person(id)?.gender, .female, "성별이 있어 기록은 남는다")
        let steps = document.undoStack.count
        document.applyFromBatch(values, categories: [.faceShape, .makeup])
        XCTAssertEqual(document.undoStack.count, steps, "바뀐 것이 없는 동기화는 단계를 만들지 않는다")
    }

    func testFaceEditsFollowTheRenderPairingForOverlappingFaces() {
        // A(중심 0.50)·B(0.60)와 얼굴 0.48·0.54(폭 모두 0.2).
        // 얼굴 1에 가장 가까운 기록은 A지만 렌더 짝짓기는 B를 얼굴 1에 둔다.
        let recordA = PersonRecord(anchor: PersonAnchor(x: 0.5, y: 0.5, width: 0.2), gender: .male)
        let recordB = PersonRecord(
            anchor: PersonAnchor(x: 0.6, y: 0.5, width: 0.2), layer: PortraitLayer(skinSmoothing: 0.2))
        var document = EditDocument(
            recipe: EditRecipe(people: PeopleAdjustments(individuals: [recordA, recordB])))
        let overlapping = [
            NormalizedRect(x: 0.38, y: 0.35, width: 0.2, height: 0.3),
            NormalizedRect(x: 0.44, y: 0.35, width: 0.2, height: 0.3),
        ]
        XCTAssertNil(document.set(.skinSmoothing(0.8), forFace: 1, of: overlapping))
        XCTAssertEqual(document.recipe.people.person(recordB.id)?.layer.skinSmoothing, 0.8, "얼굴 1의 사람은 B")
        XCTAssertTrue(document.recipe.people.person(recordA.id)?.layer.isEmpty == true, "A는 그대로")
        XCTAssertEqual(document.recipe.people.individuals.count, 2)
        XCTAssertNil(document.set(.gender(.female), forFace: 0, of: overlapping))
        XCTAssertEqual(document.recipe.people.person(recordA.id)?.gender, .female)
        let third = overlapping + [NormalizedRect(x: 0.8, y: 0.35, width: 0.1, height: 0.15)]
        XCTAssertNil(document.set(.skinSmoothing(0.4), forFace: 2, of: third))
        XCTAssertEqual(document.recipe.people.individuals.count, 3, "짝이 없는 얼굴은 새 기록")
        XCTAssertEqual(document.recipe.people.personID(forFace: 2, of: third), document.recipe.people.individuals[2].id)
        XCTAssertEqual(document.set(.skinSmoothing(0.4), forFace: 3, of: third), .unknownPerson, "범위 밖 얼굴")
    }
}
