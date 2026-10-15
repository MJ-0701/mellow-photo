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

    func testBodyPrimitivesAreEmptyUntilBodyStage() {
        var recipe = EditRecipe()
        recipe.body.legLength = 1
        let renderContext = RenderContext(extent: extent, recipe: recipe, faces: [], tuning: tuning)
        XCTAssertTrue(ShapeWarpStage().bodyPrimitives(in: renderContext).isEmpty, "체형 원소는 E 단계에서 채운다")
    }
}
