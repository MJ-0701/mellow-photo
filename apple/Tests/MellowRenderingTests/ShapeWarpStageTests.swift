import CoreImage
import MellowShared
import XCTest

@testable import MellowRendering

final class ShapeWarpStageTests: XCTestCase {
    typealias Support = RenderingTestSupport

    private let extent = SyntheticFace.extent
    private let tuning = RenderTuning()

    /// 윤곽 17점 중 index번째 점의 픽셀 위치. 1과 15는 눈~입 높이의 왼쪽·오른쪽 윤곽이다.
    private func contourPoint(_ index: Int, of face: FaceGeometry) throws -> CGPoint {
        let point = try XCTUnwrap(face.landmarks[.faceContour]?[index])
        return CGPoint(x: point.x * extent.width, y: point.y * extent.height)
    }

    private func context(
        _ face: FaceShapeAdjustments, faces: [FaceGeometry], targetFace: Int? = nil
    ) -> RenderContext {
        var recipe = EditRecipe()
        recipe.portrait.face = face
        recipe.portrait.targetFace = targetFace
        return RenderContext(extent: extent, recipe: recipe, faces: faces, tuning: tuning)
    }

    private func bodyContext(
        _ body: BodyShapeAdjustments, bodies: [BodyGeometry], face: FaceShapeAdjustments = FaceShapeAdjustments(),
        faces: [FaceGeometry] = []
    ) -> RenderContext {
        var recipe = EditRecipe()
        recipe.body = body
        recipe.portrait.face = face
        return RenderContext(
            extent: extent, recipe: recipe, analysis: PhotoAnalysis(faces: faces, bodies: bodies), tuning: tuning)
    }

    func testNoFaceEditReturnsInputUnchanged() throws {
        let synthetic = SyntheticFace.make()
        let output = try ShapeWarpStage().apply(
            synthetic.image, in: context(FaceShapeAdjustments(), faces: [synthetic.face]))
        XCTAssertEqual(try Support.bytes(output), try Support.bytes(synthetic.image))
    }

    func testFaceWithoutLandmarksIsUntouched() throws {
        let boxOnly = SyntheticFace.make(landmarks: false)
        let output = try ShapeWarpStage().apply(
            boxOnly.image, in: context(FaceShapeAdjustments(width: -1), faces: [boxOnly.face]))
        XCTAssertEqual(try Support.bytes(output), try Support.bytes(boxOnly.image), "윤곽점이 없으면 원소가 없다")
    }

    func testNarrowWidthMovesContourMarkersTowardCenter() throws {
        let face = SyntheticFace.make().face
        let left = try contourPoint(1, of: face)
        let right = try contourPoint(15, of: face)
        let input = Support.markers([left, right], extent: extent)
        let before = try Support.grid(input)
        let after = try Support.grid(
            ShapeWarpStage().apply(input, in: context(FaceShapeAdjustments(width: -1), faces: [face])))
        let rig = FaceShapeRig.primitives(
            face: face, adjustments: FaceShapeAdjustments(width: -1), extent: extent, tuning: tuning)
        let expectedLeft = Support.expectedPosition(of: left, primitives: rig, limit: tuning.shapeDisplacementLimit)
        let originalLeft = try XCTUnwrap(Support.markerCentroid(before, near: left))
        let originalRight = try XCTUnwrap(Support.markerCentroid(before, near: right))
        let movedLeft = try XCTUnwrap(Support.markerCentroid(after, near: expectedLeft))
        let mirroredExpectation = CGPoint(x: 2 * SyntheticFace.box.midX - expectedLeft.x, y: right.y)
        let movedRight = try XCTUnwrap(Support.markerCentroid(after, near: mirroredExpectation))
        XCTAssertGreaterThan(movedLeft.x - originalLeft.x, 4, "왼쪽 윤곽이 중심 쪽(+x)으로")
        XCTAssertLessThan(movedRight.x - originalRight.x, -4, "오른쪽 윤곽이 중심 쪽(−x)으로")
        XCTAssertEqual(movedLeft.x - originalLeft.x, expectedLeft.x - left.x, accuracy: 0.75, "rig가 예측한 만큼")
        XCTAssertEqual(movedLeft.y, originalLeft.y, accuracy: 0.75, "가로로만")
    }

    func testOutOfRangeFaceValuesRenderLikeClampedValues() throws {
        let synthetic = SyntheticFace.make()
        func render(_ face: FaceShapeAdjustments) throws -> [UInt8] {
            try Support.bytes(ShapeWarpStage().apply(synthetic.image, in: context(face, faces: [synthetic.face])))
        }
        XCTAssertEqual(try render(FaceShapeAdjustments(width: -3)), try render(FaceShapeAdjustments(width: -1)))
        XCTAssertEqual(
            try render(FaceShapeAdjustments(eyeSize: 4, chinLength: -9)),
            try render(FaceShapeAdjustments(eyeSize: 1, chinLength: -1)))
        XCTAssertEqual(
            try render(FaceShapeAdjustments(smile: -0.5)), try Support.bytes(synthetic.image), "범위 밖 미소는 0")
    }

    func testTargetFaceWarpsOnlyThatFace() throws {
        let base = SyntheticFace.make().face
        let leftFace = base.transformed(scale: 0.5, offset: NormalizedPoint(x: 0, y: 0.25))
        let rightFace = base.transformed(scale: 0.5, offset: NormalizedPoint(x: 0.5, y: 0.25))
        let leftMarker = try contourPoint(1, of: leftFace)
        let rightMarker = try contourPoint(1, of: rightFace)
        let input = Support.markers([leftMarker, rightMarker], extent: extent)
        let before = try Support.grid(input)
        let renderContext = context(FaceShapeAdjustments(width: -1), faces: [leftFace, rightFace], targetFace: 0)
        let after = try Support.grid(ShapeWarpStage().apply(input, in: renderContext))
        let originalLeft = try XCTUnwrap(Support.markerCentroid(before, near: leftMarker))
        let originalRight = try XCTUnwrap(Support.markerCentroid(before, near: rightMarker))
        let movedLeft = try XCTUnwrap(Support.markerCentroid(after, near: leftMarker))
        let stayed = try XCTUnwrap(Support.markerCentroid(after, near: rightMarker))
        XCTAssertGreaterThan(movedLeft.x - originalLeft.x, 2, "고른 얼굴은 좁아진다")
        XCTAssertEqual(stayed.x, originalRight.x, accuracy: 0.25, "다른 얼굴은 그대로")
        XCTAssertEqual(stayed.y, originalRight.y, accuracy: 0.25)
    }

    func testLegacyFaceSlimRecipeStillNarrows() throws {
        let json = Data(#"{"schemaVersion":2,"portrait":{"faceSlim":0.3}}"#.utf8)
        let recipe = try JSONDecoder().decode(EditRecipe.self, from: json)
        XCTAssertEqual(recipe.portrait.face.width, -0.3)
        let face = SyntheticFace.make().face
        let left = try contourPoint(1, of: face)
        let input = Support.markers([left], extent: extent)
        let renderContext = RenderContext(extent: extent, recipe: recipe, faces: [face], tuning: tuning)
        let original = try XCTUnwrap(Support.markerCentroid(Support.grid(input), near: left))
        let moved = try XCTUnwrap(
            Support.markerCentroid(Support.grid(ShapeWarpStage().apply(input, in: renderContext)), near: left))
        XCTAssertGreaterThan(moved.x - original.x, 1.5, "B0 얼굴 미세 조정 0.3이 계속 얼굴을 좁힌다")
    }

    func testLegLengthMovesMarkerBelowHipsDownAndKeepsRowsAboveHips() throws {
        let body = Support.standingBody(in: Support.standingBox)
        let knee = CGPoint(x: 200, y: 120)
        let chest = CGPoint(x: 256, y: 400)
        let input = Support.markers([knee, chest], extent: extent)
        let renderContext = bodyContext(BodyShapeAdjustments(legLength: 1), bodies: [body])
        let primitives = ShapeWarpStage().bodyPrimitives(in: renderContext)
        let expected = Support.expectedPosition(of: knee, primitives: primitives, limit: tuning.shapeDisplacementLimit)
        let before = try Support.grid(input)
        let after = try Support.grid(ShapeWarpStage().apply(input, in: renderContext))
        let original = try XCTUnwrap(Support.markerCentroid(before, near: knee))
        let moved = try XCTUnwrap(Support.markerCentroid(after, near: expected))
        XCTAssertLessThan(moved.y - original.y, -4, "띠 안 무릎 표식이 아래로")
        XCTAssertEqual(moved.y - original.y, expected.y - knee.y, accuracy: 0.75, "rig가 예측한 만큼")
        XCTAssertEqual(moved.x, original.x, accuracy: 0.25, "세로로만")
        // 엉덩이 256 + 띠 이동 18.4 + 여백 2 위쪽 행은 패치 밖이라 입력 바이트 그대로다.
        var changedAbove = 0
        for y in 280..<SyntheticFace.size {
            for x in 0..<SyntheticFace.size where after.rgba(CGPoint(x: x, y: y)) != before.rgba(CGPoint(x: x, y: y)) {
                changedAbove += 1
            }
        }
        XCTAssertEqual(changedAbove, 0, "엉덩이 위(가슴 표식 포함)는 그대로")
    }

    func testOnlyLargestBodyIsReshaped() throws {
        let large = Support.standingBody(in: NormalizedRect(x: 0, y: 0, width: 0.5, height: 1))
        let small = Support.standingBody(in: NormalizedRect(x: 0.6, y: 0.3, width: 0.3, height: 0.5))
        func waistSide(of body: BodyGeometry) throws -> CGPoint {
            let primitives = BodyShapeRig.primitives(
                body: body, adjustments: BodyShapeAdjustments(waist: -1), extent: extent, tuning: tuning)
            let centers = primitives.compactMap { primitive -> CGPoint? in
                guard case .push(let center, _, _) = primitive else { return nil }
                return center
            }
            return try XCTUnwrap(centers.first, "허리 원소는 push다")
        }
        let largeSide = try waistSide(of: large)
        let smallSide = try waistSide(of: small)
        let input = Support.markers([largeSide, smallSide], extent: extent)
        let before = try Support.grid(input)
        let renderContext = bodyContext(BodyShapeAdjustments(waist: -1), bodies: [large, small])
        let after = try Support.grid(ShapeWarpStage().apply(input, in: renderContext))
        let movedLarge = try XCTUnwrap(Support.markerCentroid(after, near: largeSide))
        let originalLarge = try XCTUnwrap(Support.markerCentroid(before, near: largeSide))
        let stayed = try XCTUnwrap(Support.markerCentroid(after, near: smallSide))
        let originalSmall = try XCTUnwrap(Support.markerCentroid(before, near: smallSide))
        XCTAssertGreaterThan(abs(movedLarge.x - originalLarge.x), 3, "가장 큰 사람의 허리는 바뀐다")
        XCTAssertEqual(stayed.x, originalSmall.x, accuracy: 0.25, "다른 사람은 그대로")
        XCTAssertEqual(stayed.y, originalSmall.y, accuracy: 0.25)
    }

    func testFaceAndBodyEditsWarpInOneSampling() throws {
        let face = SyntheticFace.make().face
        let body = Support.standingBody(in: Support.standingBox)
        let contour = try contourPoint(1, of: face)
        let shoulder = CGPoint(x: (0.1 + 0.8 * 0.75) * 512, y: 0.8 * 512)
        let renderContext = bodyContext(
            BodyShapeAdjustments(shoulders: 1), bodies: [body], face: FaceShapeAdjustments(width: -1), faces: [face])
        let stage = ShapeWarpStage()
        let primitives = stage.facePrimitives(in: renderContext) + stage.bodyPrimitives(in: renderContext)
        let input = Support.markers([contour, shoulder], extent: extent)
        let before = try Support.grid(input)
        let after = try Support.grid(stage.apply(input, in: renderContext))
        for marker in [contour, shoulder] {
            let expected = Support.expectedPosition(
                of: marker, primitives: primitives, limit: tuning.shapeDisplacementLimit)
            let original = try XCTUnwrap(Support.markerCentroid(before, near: marker))
            let moved = try XCTUnwrap(Support.markerCentroid(after, near: expected))
            XCTAssertGreaterThan(hypot(expected.x - marker.x, expected.y - marker.y), 2, "둘 다 실제로 움직인다")
            XCTAssertEqual(moved.x - original.x, expected.x - marker.x, accuracy: 0.75, "얼굴·체형 합친 예측만큼")
            XCTAssertEqual(moved.y - original.y, expected.y - marker.y, accuracy: 0.75)
        }
    }

    func testOutOfRangeBodyValuesRenderLikeClampedValues() throws {
        let body = Support.standingBody(in: Support.standingBox)
        let image = Support.markers([CGPoint(x: 200, y: 120), CGPoint(x: 150, y: 330)], extent: extent)
        func render(_ adjustments: BodyShapeAdjustments, bodies: [BodyGeometry]) throws -> [UInt8] {
            try Support.bytes(ShapeWarpStage().apply(image, in: bodyContext(adjustments, bodies: bodies)))
        }
        XCTAssertEqual(
            try render(BodyShapeAdjustments(legLength: 3, waist: -4), bodies: [body]),
            try render(BodyShapeAdjustments(legLength: 1, waist: -1), bodies: [body]))
        XCTAssertEqual(
            try render(BodyShapeAdjustments(legLength: -2), bodies: [body]), try Support.bytes(image), "음수 다리 길게는 0")
        XCTAssertEqual(
            try render(BodyShapeAdjustments(legLength: 1, waist: -1), bodies: []), try Support.bytes(image),
            "관절이 없으면 체형만 빠지고 오류가 없다")
    }
}
