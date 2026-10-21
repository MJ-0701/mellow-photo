import CoreImage
import MellowShared
import XCTest

@testable import MellowRendering

final class RenderPipelineTests: XCTestCase {
    typealias Support = RenderingTestSupport

    func testIdentityRecipeLeavesBytesUntouched() throws {
        let input = Support.gradient()
        let output = try Support.render(input, recipe: EditRecipe())
        XCTAssertEqual(output.extent, input.extent)
        XCTAssertEqual(try Support.bytes(output), try Support.bytes(input))
    }

    func testExposureChangesBytes() throws {
        var recipe = EditRecipe()
        recipe.color.exposure = 1
        XCTAssertNotEqual(
            try Support.bytes(Support.render(Support.gradient(), recipe: recipe)), try Support.bytes(Support.gradient())
        )
    }

    func testWarpAndCloneAreLocalAndEffective() throws {
        let image = Support.gradient()
        let original = try Support.bytes(image)
        let edits: [LocalEdit] = [
            .warp(WarpStroke(x: 0.5, y: 0.5, dx: 0.03, dy: 0, radius: 0.2)),
            .spot(RetouchSpot(x: 0.5, y: 0.5, sourceX: 0.2, sourceY: 0.5, radius: 0.2)),
        ]
        for edit in edits {
            var recipe = EditRecipe()
            recipe.operations = [edit]
            let result = try Support.bytes(Support.render(image, recipe: recipe))
            XCTAssertNotEqual(result, original)
            XCTAssertEqual(Array(result.prefix(128 * 4 * 10)), Array(original.prefix(128 * 4 * 10)), "아래쪽 10줄은 그대로")
        }
    }

    func testLocalEditsReplayInRecordedOrder() throws {
        let input = Support.gradient()
        let spot = LocalEdit.spot(RetouchSpot(x: 0.5, y: 0.5, sourceX: 0.15, sourceY: 0.5, radius: 0.2))
        let warp = LocalEdit.warp(WarpStroke(x: 0.5, y: 0.5, dx: 0.05, dy: 0, radius: 0.3))
        var forward = EditRecipe()
        forward.operations = [spot, warp]
        var reverse = EditRecipe()
        reverse.operations = [warp, spot]
        let forwardBytes = try Support.bytes(Support.render(input, recipe: forward))
        XCTAssertNotEqual(forwardBytes, try Support.bytes(Support.render(input, recipe: reverse)))
        var onlySpot = EditRecipe()
        onlySpot.operations = [spot]
        var onlyWarp = EditRecipe()
        onlyWarp.operations = [warp]
        let staged = try Support.render(Support.render(input, recipe: onlySpot), recipe: onlyWarp)
        XCTAssertEqual(forwardBytes, try Support.bytes(staged))
    }

    func testWarmthPositiveMakesGrayRedder() throws {
        let gray = Support.solid(CIColor(red: 0.5, green: 0.5, blue: 0.5), size: 8)
        var recipe = EditRecipe()
        recipe.color.warmth = 1
        let bytes = try Support.bytes(Support.render(gray, recipe: recipe))
        XCTAssertGreaterThan(bytes[0], bytes[2])
    }

    func testPortraitStagesChangeOnlyWhenFacesExist() throws {
        let input = Support.gradient()
        let face = FaceGeometry(boundingBox: NormalizedRect(x: 0.15, y: 0.05, width: 0.7, height: 0.9))
        var recipe = EditRecipe()
        recipe.portrait.skin.smoothing = 0.5
        recipe.portrait.face.width = -0.7
        recipe.color.contrast = 1.05
        recipe.color.saturation = 0.8
        recipe.color.warmth = -0.3
        let withFace = try Support.render(input, recipe: recipe, faces: [face])
        XCTAssertEqual(withFace.extent, input.extent)
        XCTAssertNotEqual(try Support.bytes(withFace), try Support.bytes(input))
        var portraitOnly = EditRecipe()
        portraitOnly.portrait.skin.smoothing = 1
        portraitOnly.portrait.face.width = -1
        XCTAssertEqual(
            try Support.bytes(Support.render(input, recipe: portraitOnly, faces: [])), try Support.bytes(input))
    }

    func testTargetFaceLimitsPortraitStagesToOneFace() throws {
        let input = Support.skinTexture(size: 256)
        let left = FaceGeometry(boundingBox: NormalizedRect(x: 0.05, y: 0.1, width: 0.35, height: 0.8))
        let right = FaceGeometry(boundingBox: NormalizedRect(x: 0.6, y: 0.1, width: 0.35, height: 0.8))
        var all = EditRecipe()
        all.portrait.skin.smoothing = 1
        let onlyLeft = Support.restricted(all, toFace: 0, of: [left, right])
        let outOfRange = Support.restricted(all, toFace: 7, of: [left, right])
        XCTAssertNotEqual(
            try Support.bytes(Support.render(input, recipe: all, faces: [left, right])),
            try Support.bytes(Support.render(input, recipe: onlyLeft, faces: [left, right])))
        XCTAssertEqual(
            try Support.bytes(Support.render(input, recipe: outOfRange, faces: [left, right])),
            try Support.bytes(input), "범위 밖 인덱스는 아무 얼굴도 고치지 않는다")
        // 옛 세션은 anchor 없이 legacyIndex로 읽혀 짝짓기의 legacyIndex 폴백으로 그 얼굴에 걸린다.
        let legacyJSON = #"{"schemaVersion":2,"portrait":{"targetFace":1,"skin":{"smoothing":1}}}"#
        let legacy = try JSONDecoder().decode(EditRecipe.self, from: Data(legacyJSON.utf8))
        XCTAssertNil(legacy.people.individuals.first?.anchor)
        XCTAssertEqual(legacy.people.individuals.first?.legacyIndex, 1)
        let legacyBytes = try Support.bytes(Support.render(input, recipe: legacy, faces: [left, right]))
        XCTAssertEqual(
            legacyBytes,
            try Support.bytes(
                Support.render(
                    input, recipe: Support.restricted(all, toFace: 1, of: [left, right]), faces: [left, right])),
            "옛 targetFace 1은 오른쪽 얼굴에만 건 것과 같은 바이트")
        XCTAssertNotEqual(legacyBytes, try Support.bytes(Support.render(input, recipe: all, faces: [left, right])))
    }

    func testFaceWidthWorksInBothDirections() throws {
        let synthetic = SyntheticFace.make()
        var narrow = EditRecipe()
        narrow.portrait.face.width = -1
        var wide = EditRecipe()
        wide.portrait.face.width = 1
        let narrowBytes = try Support.bytes(Support.render(synthetic.image, recipe: narrow, faces: [synthetic.face]))
        let wideBytes = try Support.bytes(Support.render(synthetic.image, recipe: wide, faces: [synthetic.face]))
        XCTAssertNotEqual(narrowBytes, try Support.bytes(synthetic.image))
        XCTAssertNotEqual(wideBytes, try Support.bytes(synthetic.image))
        XCTAssertNotEqual(narrowBytes, wideBytes)
    }

    func testStageOrderMatters() throws {
        let synthetic = SyntheticFace.make()
        let input = synthetic.image
        var recipe = EditRecipe()
        recipe.color.exposure = 0.8
        // 노출·잡티 복제는 둘 다 선형이라 서로 교환된다. 순서 차이는 얼굴형 변형과 수동 잡티 사이에서 드러난다.
        // 잡티 복제 원본(x 0.15 둘레)이 왼쪽 윤곽 변형 영역에 걸친다.
        recipe.portrait.face.width = -1
        recipe.operations = [.spot(RetouchSpot(x: 0.5, y: 0.5, sourceX: 0.15, sourceY: 0.5, radius: 0.2))]
        let context = RenderContext(
            extent: input.extent, recipe: recipe, faces: [synthetic.face], tuning: RenderTuning())
        let standard = try RenderPipeline.standard.render(input, context: context)
        let reversed = try RenderPipeline(stages: RenderPipeline.standard.stages.reversed()).render(
            input, context: context)
        XCTAssertEqual(
            RenderPipeline.standard.stages.map(\.name),
            [
                "skin", "bodySkin", "feature", "makeup", "background", "chinShade", "shapeWarp", "localEdit",
                "geometry", "color", "detail", "look", "effect",
            ])
        XCTAssertNotEqual(try Support.bytes(standard), try Support.bytes(reversed))
    }

    func testNonFiniteRecipeIsRejected() {
        var recipe = EditRecipe()
        recipe.portrait.skin.smoothing = .nan
        XCTAssertThrowsError(try Support.render(Support.gradient(), recipe: recipe)) { error in
            XCTAssertEqual(error as? MellowError, .invalidRecipeValues)
        }
    }

    func testEmptyExtentIsRejected() {
        let empty = CIImage.empty()
        XCTAssertThrowsError(try Support.render(empty, recipe: EditRecipe())) { error in
            XCTAssertEqual(error as? MellowError, .invalidImageSize)
        }
    }

    func testAnalysisInitMatchesFaceInit() {
        let left = FaceGeometry(boundingBox: NormalizedRect(x: 0.1, y: 0.1, width: 0.3, height: 0.3))
        let right = FaceGeometry(boundingBox: NormalizedRect(x: 0.6, y: 0.1, width: 0.3, height: 0.3))
        let spots = [
            BlemishSpot(x: 0.2, y: 0.2, radius: 0.01, faceIndex: 0),
            BlemishSpot(x: 0.7, y: 0.2, radius: 0.01, faceIndex: 1),
        ]
        var recipe = EditRecipe()
        recipe.portrait.skin.smoothing = 0.3
        recipe = Support.restricted(recipe, toFace: 1, of: [left, right])
        let extent = CGRect(x: 0, y: 0, width: 64, height: 64)
        let legacy = RenderContext(
            extent: extent, recipe: recipe, faces: [left, right], tuning: RenderTuning(), blemishes: spots)
        let bundled = RenderContext(
            extent: extent, recipe: recipe, analysis: PhotoAnalysis(faces: [left, right], blemishes: spots),
            tuning: RenderTuning())
        XCTAssertEqual(legacy.faces, bundled.faces)
        XCTAssertEqual(legacy.blemishes, bundled.blemishes)
        XCTAssertEqual(legacy.faceTargets.map(\.face), [left, right])
        XCTAssertEqual(bundled.faceTargets.map(\.face), [left, right])
        XCTAssertEqual(bundled.faceTargets[1].blemishes, [spots[1]])
        XCTAssertEqual(bundled.faceTargets.map(\.portrait.skin.smoothing), [0, 0.3], "옮긴 값은 그 얼굴에만")
        XCTAssertEqual(legacy.faceTargets.map(\.portrait.skin.smoothing), [0, 0.3])
    }

    func testFaceTargetsResolvePeopleLayersPerFace() {
        let left = FaceGeometry(boundingBox: NormalizedRect(x: 0.05, y: 0.1, width: 0.35, height: 0.8))
        let right = FaceGeometry(boundingBox: NormalizedRect(x: 0.6, y: 0.1, width: 0.35, height: 0.8))
        let spots = [
            BlemishSpot(x: 0.2, y: 0.2, radius: 0.01, faceIndex: 0),
            BlemishSpot(x: 0.7, y: 0.2, radius: 0.01, faceIndex: 1),
        ]
        var recipe = EditRecipe()
        recipe.portrait.skin.smoothing = 0.2
        recipe.people.groups[.female] = PortraitLayer(skinSmoothing: 0.5, features: [.eyeBrighten: 0.3])
        let id = PersonID()
        recipe.people.individuals = [
            PersonRecord(
                id: id, anchor: PersonAnchor(faceBox: right.boundingBox), gender: .female,
                layer: PortraitLayer(skinSmoothing: 0.9, face: [.jaw: 0.4])),
            PersonRecord(anchor: PersonAnchor(x: 0.5, y: 0.98, width: 0.01), layer: PortraitLayer(skinSmoothing: 1)),
        ]
        let extent = CGRect(x: 0, y: 0, width: 64, height: 64)
        let context = RenderContext(
            extent: extent, recipe: recipe, faces: [left, right], tuning: RenderTuning(), blemishes: spots)
        XCTAssertEqual(context.faceTargets.map(\.index), [0, 1])
        let first = context.faceTargets[0]
        XCTAssertNil(first.personID)
        XCTAssertNil(first.gender)
        XCTAssertEqual(first.portrait.skin.smoothing, 0.2, "짝이 없는 얼굴은 전체 값")
        XCTAssertEqual(first.blemishes, [spots[0]])
        let second = context.faceTargets[1]
        XCTAssertEqual(second.personID, id)
        XCTAssertEqual(second.gender, .female)
        XCTAssertEqual(second.portrait.skin.smoothing, 0.9)
        XCTAssertEqual(second.portrait.features.eyeBrighten, 0.3, "그룹 값은 상속")
        XCTAssertEqual(second.portrait.face.jaw, 0.4)
        XCTAssertEqual(second.blemishes, [spots[1]])
    }

    func testOverlappingFacesUseTheSameGlobalPairingAsEditing() {
        // A(중심 0.50)·B(0.60)와 얼굴 0.48·0.54(폭 모두 0.2).
        // 얼굴 1에 가장 가까운 기록은 A지만 짝짓기는 B를 얼굴 1에 둔다.
        let faces = [
            FaceGeometry(boundingBox: NormalizedRect(x: 0.38, y: 0.35, width: 0.2, height: 0.3)),
            FaceGeometry(boundingBox: NormalizedRect(x: 0.44, y: 0.35, width: 0.2, height: 0.3)),
        ]
        let recordA = PersonRecord(anchor: PersonAnchor(x: 0.5, y: 0.5, width: 0.2), gender: .male)
        let recordB = PersonRecord(
            anchor: PersonAnchor(x: 0.6, y: 0.5, width: 0.2), layer: PortraitLayer(skinSmoothing: 0.8))
        let recipe = EditRecipe(people: PeopleAdjustments(individuals: [recordA, recordB]))
        let context = RenderContext(
            extent: CGRect(x: 0, y: 0, width: 64, height: 64), recipe: recipe, faces: faces, tuning: RenderTuning())
        XCTAssertEqual(context.faceTargets.map(\.personID), [recordA.id, recordB.id])
        XCTAssertEqual(
            recipe.people.personID(forFace: 1, of: faces.map(\.boundingBox)), recordB.id, "편집이 고르는 사람과 같다")
        XCTAssertEqual(context.faceTargets.map(\.portrait.skin.smoothing), [0, 0.8], "B의 값은 얼굴 1에만")
    }
}
