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
        var onlyLeft = all
        onlyLeft.portrait.targetFace = 0
        var outOfRange = all
        outOfRange.portrait.targetFace = 7
        XCTAssertNotEqual(
            try Support.bytes(Support.render(input, recipe: all, faces: [left, right])),
            try Support.bytes(Support.render(input, recipe: onlyLeft, faces: [left, right])))
        XCTAssertEqual(
            try Support.bytes(Support.render(input, recipe: outOfRange, faces: [left, right])),
            try Support.bytes(input), "범위 밖 인덱스는 아무 얼굴도 고치지 않는다")
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
            ["skin", "feature", "background", "shapeWarp", "localEdit", "geometry", "color", "detail", "look"])
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
        recipe.portrait.targetFace = 1
        let extent = CGRect(x: 0, y: 0, width: 64, height: 64)
        let legacy = RenderContext(
            extent: extent, recipe: recipe, faces: [left, right], tuning: RenderTuning(), blemishes: spots)
        let bundled = RenderContext(
            extent: extent, recipe: recipe, analysis: PhotoAnalysis(faces: [left, right], blemishes: spots),
            tuning: RenderTuning())
        XCTAssertEqual(legacy.faces, bundled.faces)
        XCTAssertEqual(legacy.blemishes, bundled.blemishes)
        XCTAssertEqual(legacy.targetFaces, [right])
        XCTAssertEqual(bundled.targetFaces, [right])
        XCTAssertEqual(bundled.targetBlemishes, [spots[1]])
    }
}
