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
        if let targetFace {
            recipe = Support.restricted(recipe, toFace: targetFace, of: faces)
        }
        return RenderContext(extent: extent, recipe: recipe, faces: faces, tuning: tuning)
    }

    private func bodyContext(
        _ body: BodyShapeAdjustments, bodies: [BodyGeometry], face: FaceShapeAdjustments = FaceShapeAdjustments(),
        faces: [FaceGeometry] = [], targetFace: Int? = nil, bodyAnalysisFailure: MellowError? = nil,
        extent: CGRect? = nil
    ) -> RenderContext {
        var recipe = EditRecipe()
        recipe.body = body
        recipe.portrait.face = face
        if let targetFace {
            recipe = Support.restricted(recipe, toFace: targetFace, of: faces)
        }
        let analysis = PhotoAnalysis(faces: faces, bodies: bodies, bodyAnalysisFailure: bodyAnalysisFailure)
        return RenderContext(extent: extent ?? self.extent, recipe: recipe, analysis: analysis, tuning: tuning)
    }

    /// 허리 −1 원소 중 첫 push의 중심(한쪽 옆구리).
    private func waistSide(of body: BodyGeometry, in extent: CGRect) throws -> CGPoint {
        let primitives = BodyShapeRig.primitives(
            body: body, adjustments: BodyShapeAdjustments(waist: -1), extent: extent, tuning: tuning)
        let centers = primitives.compactMap { primitive -> CGPoint? in
            guard case .push(let center, _, _) = primitive else { return nil }
            return center
        }
        return try XCTUnwrap(centers.first, "허리 원소는 push다")
    }

    /// 표식 하나를 그린 이미지를 context로 변형해 그 표식이 움직인 거리(출력 − 입력 중심)를 잰다.
    private func markerShift(at marker: CGPoint, in renderContext: RenderContext) throws -> CGVector {
        let input = Support.markers([marker], extent: renderContext.extent)
        let stage = ShapeWarpStage()
        let primitives = stage.facePrimitives(in: renderContext) + stage.bodyPrimitives(in: renderContext)
        let expected = Support.expectedPosition(
            of: marker, primitives: primitives, limit: tuning.shapeDisplacementLimit)
        let original = try XCTUnwrap(Support.markerCentroid(Support.grid(input), near: marker))
        let moved = try XCTUnwrap(
            Support.markerCentroid(Support.grid(stage.apply(input, in: renderContext)), near: expected))
        return CGVector(dx: moved.x - original.x, dy: moved.y - original.y)
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

    /// 체형 대상 테스트의 두 사람. 큰 사람이 앞(인덱스 0)이다.
    private var twoBodies: [BodyGeometry] {
        [
            Support.standingBody(in: NormalizedRect(x: 0, y: 0, width: 0.5, height: 1)),
            Support.standingBody(in: NormalizedRect(x: 0.6, y: 0.3, width: 0.3, height: 0.5)),
        ]
    }

    /// 얼굴 상자만 있는 얼굴. 몸과의 짝은 분석의 bodyFaceMatches로 정한다.
    private func boxFace(x: Double) -> FaceGeometry {
        FaceGeometry(boundingBox: NormalizedRect(x: x, y: 0.8, width: 0.1, height: 0.1))
    }

    /// 사람 기록과 몸–얼굴 짝을 가진 문맥.
    private func peopleContext(
        _ recipe: EditRecipe, bodies: [BodyGeometry], faces: [FaceGeometry], matches: [Int: Int]
    ) -> RenderContext {
        let analysis = PhotoAnalysis(faces: faces, bodies: bodies, bodyFaceMatches: matches)
        return RenderContext(extent: extent, recipe: recipe, analysis: analysis, tuning: tuning)
    }

    /// 표식이 rig 예측만큼 움직였는지와 그 가로 이동.
    private func movedX(of marker: CGPoint, before: PixelGrid, after: PixelGrid, primitives: [ShapePrimitive]) throws
        -> CGFloat
    {
        let expected = Support.expectedPosition(
            of: marker, primitives: primitives, limit: tuning.shapeDisplacementLimit)
        let original = try XCTUnwrap(Support.markerCentroid(before, near: marker))
        let moved = try XCTUnwrap(Support.markerCentroid(after, near: expected))
        XCTAssertEqual(moved.x - original.x, expected.x - marker.x, accuracy: 0.75, "rig가 예측한 만큼")
        return moved.x - original.x
    }

    func testAllLayerBodyReshapesEveryBody() throws {
        let bodies = twoBodies
        let largeSide = try waistSide(of: bodies[0], in: extent)
        let smallSide = try waistSide(of: bodies[1], in: extent)
        let input = Support.markers([largeSide, smallSide], extent: extent)
        let renderContext = bodyContext(BodyShapeAdjustments(waist: -1), bodies: bodies)
        let stage = ShapeWarpStage()
        let primitives = stage.bodyPrimitives(in: renderContext)
        let before = try Support.grid(input)
        let after = try Support.grid(stage.apply(input, in: renderContext))
        XCTAssertGreaterThan(
            abs(try movedX(of: largeSide, before: before, after: after, primitives: primitives)), 3, "큰 사람의 허리")
        XCTAssertGreaterThan(
            abs(try movedX(of: smallSide, before: before, after: after, primitives: primitives)), 2, "작은 사람의 허리도")
        XCTAssertEqual(renderContext.bodyTargets.map(\.index), [0, 1], "모든 몸이 분석 순서대로 대상이다")
    }

    func testLegBandOnlyForLargestBody() throws {
        let bodies = twoBodies
        let renderContext = bodyContext(BodyShapeAdjustments(legLength: 1), bodies: bodies)
        let bands = ShapeWarpStage().bodyPrimitives(in: renderContext).filter(\.isBand)
        XCTAssertEqual(bands.count, 1, "띠는 하나뿐이다")
        let largeHip = try XCTUnwrap(BodySkeleton(body: bodies[0], extent: extent, tuning: tuning)?.hipCenter)
        guard case .band(let yStart, _, _) = try XCTUnwrap(bands.first) else { return XCTFail("띠 원소") }
        XCTAssertEqual(yStart, largeHip.y, accuracy: 0.001, "가장 큰 몸의 엉덩이에서 시작한다")
        XCTAssertEqual(renderContext.bodyTargets[1].adjustments.legLength, 1, "해석 값은 그대로이고 원소만 뺀다")
    }

    func testPersonLayerBodyAppliesOnlyToMatchedBody() throws {
        let bodies = twoBodies
        let face = boxFace(x: 0.2)
        var recipe = EditRecipe()
        recipe.people.individuals = [
            PersonRecord(anchor: PersonAnchor(faceBox: face.boundingBox), layer: PortraitLayer(body: [.waist: -1]))
        ]
        let renderContext = peopleContext(recipe, bodies: bodies, faces: [face], matches: [0: 0])
        XCTAssertEqual(renderContext.bodyTargets[0].faceIndex, 0)
        XCTAssertEqual(renderContext.bodyTargets[0].adjustments.waist, -1, "짝 얼굴의 개인 값")
        XCTAssertNil(renderContext.bodyTargets[1].faceIndex)
        XCTAssertEqual(renderContext.bodyTargets[1].adjustments, BodyShapeAdjustments(), "짝 없는 몸은 전체 층 값(0)")
        let largeSide = try waistSide(of: bodies[0], in: extent)
        let smallSide = try waistSide(of: bodies[1], in: extent)
        let input = Support.markers([largeSide, smallSide], extent: extent)
        let stage = ShapeWarpStage()
        let before = try Support.grid(input)
        let after = try Support.grid(stage.apply(input, in: renderContext))
        let shift = try movedX(
            of: largeSide, before: before, after: after, primitives: stage.bodyPrimitives(in: renderContext))
        XCTAssertGreaterThan(abs(shift), 3, "짝이 된 몸의 허리는 바뀐다")
        // 합성 표식은 그래프가 달라지면 가장자리 바이트가 1 어긋날 수 있어 몸 B가 없는 렌더와 비교한다.
        let withoutSmall = peopleContext(recipe, bodies: [bodies[0]], faces: [face], matches: [0: 0])
        XCTAssertEqual(
            try Support.bytes(stage.apply(input, in: renderContext)),
            try Support.bytes(stage.apply(input, in: withoutSmall)), "다른 몸은 같은 바이트다")
        let stayed = try XCTUnwrap(Support.markerCentroid(after, near: smallSide))
        let original = try XCTUnwrap(Support.markerCentroid(before, near: smallSide))
        XCTAssertEqual(stayed.x, original.x, accuracy: 0.25, "다른 몸의 허리는 그대로")
    }

    func testFemaleGroupSideChestReachesOnlyFemaleBody() throws {
        let bodies = twoBodies + [Support.standingBody(in: NormalizedRect(x: 0.55, y: 0, width: 0.2, height: 0.25))]
        let maleFace = boxFace(x: 0.2)
        let femaleFace = boxFace(x: 0.7)
        var recipe = EditRecipe()
        recipe.body = BodyShapeAdjustments(sideChest: 1)
        recipe.people.groups[.female] = PortraitLayer(body: [.sideChest: 1])
        recipe.people.groups[.male] = PortraitLayer(body: [.sideChest: 1])
        recipe.people.individuals = [
            PersonRecord(anchor: PersonAnchor(faceBox: maleFace.boundingBox), gender: .male),
            PersonRecord(anchor: PersonAnchor(faceBox: femaleFace.boundingBox), gender: .female),
        ]
        let renderContext = peopleContext(
            recipe, bodies: bodies, faces: [maleFace, femaleFace], matches: [0: 0, 1: 1])
        let sideChest = renderContext.bodyTargets.map(\.adjustments.sideChest)
        XCTAssertEqual(sideChest, [0, 1, 0], "여성 몸만 받는다(남성 그룹·전체 층의 부유방은 버린다)")
        XCTAssertEqual(renderContext.bodyTargets.map(\.faceIndex), [0, 1, nil])
    }

    func testUnmatchedBodyGetsAllLayerWithoutSideChest() throws {
        var recipe = EditRecipe()
        recipe.body = BodyShapeAdjustments(waist: -0.5, shoulders: 0.4, sideChest: 1)
        let face = boxFace(x: 0.2)
        recipe.people.individuals = [
            PersonRecord(anchor: PersonAnchor(faceBox: face.boundingBox), layer: PortraitLayer(body: [.waist: 1]))
        ]
        let renderContext = peopleContext(recipe, bodies: twoBodies, faces: [face], matches: [:])
        for target in renderContext.bodyTargets {
            XCTAssertNil(target.faceIndex)
            XCTAssertEqual(target.adjustments, PortraitResolver.allLayerBody(recipe), "짝 없는 몸은 전체 층 값")
            XCTAssertEqual(target.adjustments.sideChest, 0)
        }
        XCTAssertEqual(renderContext.faceTargets.first?.body.waist, 1, "얼굴 대상은 그 사람의 해석 값을 든다")
    }

    func testPersonMaskForBodyAndFaceUsesInstances() throws {
        let combined = Support.personMask(
            size: CGSize(width: 64, height: 48), person: CGRect(x: 8, y: 0, width: 48, height: 48))
        let first = Support.personMask(
            size: CGSize(width: 64, height: 48), person: CGRect(x: 32, y: 0, width: 32, height: 48))
        let second = Support.personMask(
            size: CGSize(width: 64, height: 48), person: CGRect(x: 0, y: 0, width: 32, height: 48))
        let analysis = PhotoAnalysis(
            faces: [boxFace(x: 0.2), boxFace(x: 0.7)], personMask: combined, bodies: twoBodies,
            personInstances: [first, second], bodyInstances: [0: 1], faceInstances: [1: 0])
        let renderContext = RenderContext(extent: extent, recipe: EditRecipe(), analysis: analysis, tuning: tuning)
        let body = renderContext.personMask(forBody: 0)
        XCTAssertTrue(body.own === second, "그 몸의 인스턴스")
        XCTAssertEqual(body.others.count, 1)
        XCTAssertTrue(body.others.first === first, "나머지 인스턴스")
        let face = renderContext.personMask(forFace: 1)
        XCTAssertTrue(face.own === first)
        XCTAssertTrue(face.others.first === second)
        let unassigned = renderContext.personMask(forBody: 1)
        XCTAssertTrue(unassigned.own === combined, "인스턴스가 없으면 전체 인물 마스크")
        XCTAssertTrue(unassigned.others.isEmpty)
        XCTAssertTrue(renderContext.personMask(forFace: 0).own === combined)
        let bare = RenderContext(
            extent: extent, recipe: EditRecipe(), analysis: PhotoAnalysis(bodies: twoBodies), tuning: tuning)
        XCTAssertNil(bare.personMask(forBody: 0).own, "인물 마스크도 없으면 nil")
        XCTAssertTrue(bare.personMask(forBody: 0).others.isEmpty)
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

    func testBodyWarpScalesWithExtentLikePreviewAndExport() throws {
        let body = Support.standingBody(in: Support.standingBox)
        let adjustments = BodyShapeAdjustments(waist: -1, shoulders: 1)
        /// 미리보기(1배)와 저장(4배)처럼 같은 사진을 다른 크기로 그린다. 정규화 관절이라 이동도 4배여야 한다.
        let scale: CGFloat = 4
        let small = CGRect(x: 0, y: 0, width: 256, height: 256)
        let large = CGRect(x: 0, y: 0, width: small.width * scale, height: small.height * scale)
        let smallSide = try waistSide(of: body, in: small)
        let largeSide = CGPoint(x: smallSide.x * scale, y: smallSide.y * scale)
        let smallShift = try markerShift(
            at: smallSide, in: bodyContext(adjustments, bodies: [body], extent: small))
        let largeShift = try markerShift(
            at: largeSide, in: bodyContext(adjustments, bodies: [body], extent: large))
        XCTAssertGreaterThan(abs(smallShift.dx), 3, "1배에서도 실제로 움직인다")
        XCTAssertEqual(largeShift.dx, smallShift.dx * scale, accuracy: 1.5, "4배 크기에서는 4배 이동")
        XCTAssertEqual(largeShift.dy, smallShift.dy * scale, accuracy: 1.5)
    }

    func testFailedBodyAnalysisStillWarpsFaceAndLeavesBodyAlone() throws {
        let face = SyntheticFace.make().face
        let body = Support.standingBody(in: Support.standingBox)
        let contour = try contourPoint(1, of: face)
        let side = try waistSide(of: body, in: extent)
        let input = Support.markers([contour, side], extent: extent)
        let faceEdit = FaceShapeAdjustments(width: -1)
        let failure = MellowError.bodyAnalysisUnavailable(reason: "test")
        let stage = ShapeWarpStage()
        for bodyFailure in [failure, nil] {
            let failed = bodyContext(
                BodyShapeAdjustments(waist: -1), bodies: [], face: faceEdit, faces: [face],
                bodyAnalysisFailure: bodyFailure)
            XCTAssertTrue(stage.bodyPrimitives(in: failed).isEmpty, "관절이 없으면 체형 원소가 없다")
            let faceOnly = bodyContext(BodyShapeAdjustments(), bodies: [], face: faceEdit, faces: [face])
            let output = try stage.apply(input, in: failed)
            XCTAssertEqual(
                try Support.bytes(output), try Support.bytes(stage.apply(input, in: faceOnly)),
                "체형 값은 픽셀을 하나도 바꾸지 않는다")
            let shift = try markerShift(at: contour, in: failed)
            XCTAssertGreaterThan(shift.dx, 4, "얼굴 윤곽은 그대로 좁아진다")
        }
    }

    func testBodyWarpIgnoresTargetFace() throws {
        let base = SyntheticFace.make().face
        let leftFace = base.transformed(scale: 0.5, offset: NormalizedPoint(x: 0, y: 0.25))
        let rightFace = base.transformed(scale: 0.5, offset: NormalizedPoint(x: 0.5, y: 0.25))
        let body = Support.standingBody(in: Support.standingBox)
        let side = try waistSide(of: body, in: extent)
        let input = Support.markers([side], extent: extent)
        let adjustments = BodyShapeAdjustments(waist: -1)
        let stage = ShapeWarpStage()
        let untargeted = bodyContext(adjustments, bodies: [body], faces: [leftFace, rightFace])
        for target in [0, 1] {
            let targeted = bodyContext(adjustments, bodies: [body], faces: [leftFace, rightFace], targetFace: target)
            XCTAssertEqual(stage.bodyPrimitives(in: targeted), stage.bodyPrimitives(in: untargeted))
            XCTAssertEqual(
                try Support.bytes(stage.apply(input, in: targeted)),
                try Support.bytes(stage.apply(input, in: untargeted)),
                "고른 얼굴이 있어도 체형은 같게 바뀐다")
            let shift = try markerShift(at: side, in: targeted)
            XCTAssertGreaterThan(abs(shift.dx), 3, "얼굴 \(target)을 골라도 허리가 움직인다")
        }
    }

    func testIndividualFaceShapeMakesPrimitivesOnlyForThatFace() throws {
        let leftFace = SyntheticFace.make().face.transformed(scale: 0.5, offset: NormalizedPoint(x: 0, y: 0.25))
        let rightFace = SyntheticFace.make().face.transformed(scale: 0.5, offset: NormalizedPoint(x: 0.5, y: 0.25))
        var recipe = EditRecipe()
        recipe.people.individuals = [
            PersonRecord(anchor: PersonAnchor(faceBox: leftFace.boundingBox), layer: PortraitLayer(face: [.width: -1]))
        ]
        let individual = RenderContext(
            extent: SyntheticFace.extent, recipe: recipe, faces: [leftFace, rightFace], tuning: RenderTuning())
        let legacy = context(FaceShapeAdjustments(width: -1), faces: [leftFace, rightFace], targetFace: 0)
        let stage = ShapeWarpStage()
        let fromIndividual = stage.facePrimitives(in: individual)
        XCTAssertGreaterThan(fromIndividual.count, 0)
        XCTAssertEqual(fromIndividual, stage.facePrimitives(in: legacy), "이행한 옛 대상 얼굴과 같은 원소")
        let everyone = context(FaceShapeAdjustments(width: -1), faces: [leftFace, rightFace])
        XCTAssertEqual(stage.facePrimitives(in: everyone).count, fromIndividual.count * 2)
    }

    // MARK: - 팔 보호

    /// 팔 보호 테스트의 사람 마스크. 선 사람 전체를 덮는다.
    private var standingPersonMask: CIImage {
        Support.personMask(size: extent.size, person: CGRect(x: 24, y: 0, width: 464, height: 480))
    }

    /// 팔꿈치·손목을 몸통 옆선(같은 쪽 어깨–엉덩이)에서 바깥으로 띄운 몸과 그 표식 자리.
    /// gap은 팔 가장자리와 옆선 사이 거리(어깨 폭 비율)이고 0이면 팔이 옆선에 붙는다.
    /// upperArm은 어깨–팔꿈치 가운데(부유방 높이 근처)다.
    private func armBody(gap: CGFloat) throws -> (
        body: BodyGeometry, arm: [CGPoint], waist: [CGPoint], upperArm: [CGPoint]
    ) {
        let base = Support.standingBody(in: Support.standingBox)
        let skeleton = try XCTUnwrap(BodySkeleton(body: base, extent: extent, tuning: tuning))
        let width = skeleton.torsoWidth
        var moved: [BodyJoint: CGPoint] = [:]
        var arm: [CGPoint] = []
        var waist: [CGPoint] = []
        var upperArm: [CGPoint] = []
        let sides: [(BodyJoint, BodyJoint, BodyJoint, BodyJoint)] = [
            (.rightShoulder, .rightHip, .rightElbow, .rightWrist), (.leftShoulder, .leftHip, .leftElbow, .leftWrist),
        ]
        for (shoulderJoint, hipJoint, elbowJoint, wristJoint) in sides {
            let shoulder = try XCTUnwrap(skeleton.point(shoulderJoint))
            let hip = try XCTUnwrap(skeleton.point(hipJoint))
            let length = hypot(hip.x - shoulder.x, hip.y - shoulder.y)
            var outward = CGVector(dx: (hip.y - shoulder.y) / length, dy: (shoulder.x - hip.x) / length)
            if (shoulder.x - skeleton.shoulderCenter.x) * outward.dx < 0 {
                outward = CGVector(dx: -outward.dx, dy: -outward.dy)
            }
            let waistPoint = ShapeTestSupport.lerp(shoulder, hip, 0.55)
            let elbow = ShapeTestSupport.offset(
                waistPoint, outward, (BodyShapeRig.upperArmHalfWidth + gap) * width)
            let wrist = ShapeTestSupport.offset(hip, outward, (BodyShapeRig.forearmHalfWidth + gap) * width)
            moved[elbowJoint] = elbow
            moved[wristJoint] = wrist
            arm += [elbow, ShapeTestSupport.lerp(elbow, wrist, 0.5)]
            waist.append(waistPoint)
            upperArm.append(ShapeTestSupport.lerp(shoulder, elbow, 0.5))
        }
        return (ShapeTestSupport.body(base, moving: moved, extent: extent), arm, waist, upperArm)
    }

    /// 표식들을 그린 이미지를 변형해 각 표식이 움직인 거리.
    private func measuredShifts(of markers: [CGPoint], in renderContext: RenderContext) throws -> [CGFloat] {
        let input = Support.markers(markers, extent: extent)
        let before = try Support.grid(input)
        let after = try Support.grid(ShapeWarpStage().apply(input, in: renderContext))
        return try markers.map { marker in
            let original = try XCTUnwrap(Support.markerCentroid(before, near: marker))
            let moved = try XCTUnwrap(Support.markerCentroid(after, near: marker, window: 20))
            return hypot(moved.x - original.x, moved.y - original.y)
        }
    }

    private func maskedBodyContext(_ body: BodyGeometry, mask: CIImage?) -> RenderContext {
        var recipe = EditRecipe()
        recipe.body = BodyShapeAdjustments(waist: -1)
        let analysis = PhotoAnalysis(personMask: mask, bodies: [body])
        return RenderContext(extent: extent, recipe: recipe, analysis: analysis, tuning: tuning)
    }

    func testArmTouchingTorsoKeepsArmPixels() throws {
        let layout = try armBody(gap: 0)
        let unguarded = try measuredShifts(of: layout.arm, in: maskedBodyContext(layout.body, mask: nil))
        XCTAssertGreaterThan(unguarded.max() ?? 0, 3, "보호가 없으면 허리 push가 붙은 팔을 끈다")
        let guarded = try measuredShifts(
            of: layout.arm, in: maskedBodyContext(layout.body, mask: standingPersonMask))
        for (marker, shift) in zip(layout.arm, guarded) {
            XCTAssertLessThanOrEqual(shift, 1, "팔 캡슐 안 표식은 움직이지 않는다 \(marker)")
        }
    }

    /// 부유방은 전체 층에 둘 수 없어 몸과 짝이 된 얼굴의 개인 층에 둔다.
    /// outlines는 준비 때 찾은 몸통 옆선이다(기본은 없음 = 관절선 점).
    private func sideChestContext(
        _ body: BodyGeometry, mask: CIImage?, outlines: [Int: BodyOutline] = [:]
    ) -> RenderContext {
        let face = FaceGeometry(boundingBox: NormalizedRect(x: 0.4, y: 0.82, width: 0.2, height: 0.15))
        var recipe = EditRecipe()
        recipe.people.individuals = [
            PersonRecord(anchor: PersonAnchor(faceBox: face.boundingBox), layer: PortraitLayer(body: [.sideChest: 1]))
        ]
        let analysis = PhotoAnalysis(
            faces: [face], personMask: mask, bodies: [body], bodyFaceMatches: [0: 0], bodyOutlines: outlines)
        return RenderContext(extent: extent, recipe: recipe, analysis: analysis, tuning: tuning)
    }

    func testArmTouchingTorsoKeepsArmPixelsUnderSideChest() throws {
        let layout = try armBody(gap: 0)
        let bare = sideChestContext(layout.body, mask: nil)
        XCTAssertEqual(bare.bodyTargets.first?.adjustments.sideChest, 1)
        let unguarded = try measuredShifts(of: layout.upperArm, in: bare)
        XCTAssertGreaterThan(unguarded.max() ?? 0, 2, "보호가 없으면 부유방 push가 붙은 위팔을 끈다")
        let guarded = try measuredShifts(
            of: layout.upperArm, in: sideChestContext(layout.body, mask: standingPersonMask))
        for (marker, shift) in zip(layout.upperArm, guarded) {
            XCTAssertLessThanOrEqual(shift, 1, "팔 캡슐 안 표식은 움직이지 않는다 \(marker)")
        }
    }

    /// 스펙 5.8: 사람 마스크에서 찾은 몸통 옆선의 부유방 원소는 팔 보호에 지워지지 않고 팔은 그대로다.
    func testSideChestOnTheMaskOutlineMovesTheTorsoEdgeButNotTheArm() throws {
        let layout = try armBody(gap: 0.2)
        let mask = try OutlineTestSupport.detachedMask()
        let skeleton = try XCTUnwrap(BodySkeleton(body: layout.body, extent: extent, tuning: tuning))
        let outline = BodyOutlineProbe.probe(
            skeleton: skeleton, mask: try OutlineTestSupport.sampler(mask), extent: extent,
            levels: BodyShapeRig.outlineLevels, tuning: tuning)
        let edges = try [-1, 1].map { side -> CGPoint in
            let point = try XCTUnwrap(outline.points[OutlineKey(level: 0.27, side: side)], "\(side) 쪽 옆선")
            return CGPoint(x: extent.minX + point.x * extent.width, y: extent.minY + point.y * extent.height)
        }
        let outlines = [0: outline]
        let unguarded = try measuredShifts(
            of: edges, in: sideChestContext(layout.body, mask: nil, outlines: outlines))
        let guarded = try measuredShifts(
            of: edges + layout.upperArm, in: sideChestContext(layout.body, mask: mask, outlines: outlines))
        for (expected, shift) in zip(unguarded, guarded.prefix(edges.count)) {
            XCTAssertGreaterThan(expected, 4, "보호가 없으면 옆선이 부유방 이동만큼 움직인다")
            XCTAssertGreaterThanOrEqual(shift, expected * 0.8, "보호를 켜도 몸통 옆선 이동의 80% 이상이 남는다")
        }
        for (marker, shift) in zip(layout.upperArm, guarded.suffix(layout.upperArm.count)) {
            XCTAssertLessThanOrEqual(shift, 1, "위팔 표식은 움직이지 않는다 \(marker)")
        }
    }

    func testArmAwayStillSlimsTheWaist() throws {
        let layout = try armBody(gap: 0.2)
        let unguarded = try measuredShifts(of: layout.waist, in: maskedBodyContext(layout.body, mask: nil))
        let guarded = try measuredShifts(
            of: layout.waist, in: maskedBodyContext(layout.body, mask: standingPersonMask))
        for (expected, shift) in zip(unguarded, guarded) {
            XCTAssertGreaterThan(expected, 5, "허리 윤곽이 실제로 움직인다")
            XCTAssertGreaterThanOrEqual(shift, expected * 0.8, "떨어진 팔의 보호는 허리를 지우지 않는다")
        }
    }

    func testGroupsSplitTorsoAndLimbsWithPersonMasks() throws {
        let face = SyntheticFace.make().face
        let body = Support.standingBody(in: Support.standingBox)
        var recipe = EditRecipe()
        recipe.body = BodyShapeAdjustments(waist: -1, arms: -1)
        recipe.portrait.face = FaceShapeAdjustments(width: -1)
        let mask = standingPersonMask
        let analysis = PhotoAnalysis(faces: [face], personMask: mask, bodies: [body])
        let renderContext = RenderContext(extent: extent, recipe: recipe, analysis: analysis, tuning: tuning)
        let groups = ShapeWarpStage().groups(in: renderContext)
        XCTAssertEqual(groups.count, 3, "얼굴형, 몸통, 팔다리")
        XCTAssertTrue(groups.allSatisfy { $0.ownMask === mask }, "인스턴스가 없으면 모두 전체 인물 마스크")
        XCTAssertEqual(groups.map(\.guards.count), [0, 4, 0], "팔 캡슐은 몸통 묶음만")
        let rig = BodyShapeRig.groups(
            body: body, adjustments: recipe.body, extent: extent, tuning: tuning, includesLegBand: true)
        XCTAssertEqual(groups[1].primitives, rig.torso)
        XCTAssertEqual(groups[2].primitives, rig.limbs)
        XCTAssertEqual(groups[1].guards, rig.guards)
    }

    /// 인물 마스크가 없으면 묶음으로 나눠도 항목 순서로 이은 옛 원소 목록과 같은 바이트다(Review Focus 1).
    func testWithoutPersonMaskRendersLikeKeyOrderedPrimitives() throws {
        let body = Support.standingBody(in: Support.standingBox)
        let all = BodyShapeAdjustments(
            legLength: 1, waist: -1, overall: -1, arms: -1, thighs: -1, shoulders: 1, neck: 1)
        var keyOrdered: [ShapePrimitive] = []
        for key in BodyShapeKey.allCases {
            var single = BodyShapeAdjustments()
            single[key] = all[key]
            keyOrdered += BodyShapeRig.primitives(body: body, adjustments: single, extent: extent, tuning: tuning)
        }
        let input = CIImage(cgImage: try Support.renderer.makeCGImage(Support.skinTexture(size: SyntheticFace.size)))
        let legacy = try DisplacementWarp.shared.apply(
            keyOrdered, to: input, extent: extent, limit: tuning.shapeDisplacementLimit)
        let renderContext = bodyContext(all, bodies: [body])
        XCTAssertTrue(renderContext.personMask(forBody: 0).own == nil)
        XCTAssertEqual(try Support.bytes(ShapeWarpStage().apply(input, in: renderContext)), try Support.bytes(legacy))
    }
}
