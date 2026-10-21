import CoreImage
import MellowShared
import XCTest

@testable import MellowRendering

final class DisplacementWarpTests: XCTestCase {
    typealias Support = RenderingTestSupport

    /// 점의 무게 중심이 예상 위치에서 벗어나도 되는 거리(픽셀). 쌍선형 샘플링과 점 가장자리 안티에일리어싱 몫.
    private static let tolerance: CGFloat = 0.75
    private let extent = CGRect(x: 0, y: 0, width: 128, height: 128)
    private let center = CGPoint(x: 64, y: 64)
    private let limit = RenderTuning().shapeDisplacementLimit

    private func warp(_ image: CIImage, _ primitives: [ShapePrimitive]) throws -> CIImage {
        try DisplacementWarp.shared.apply(primitives, to: image, extent: image.extent, limit: limit)
    }

    /// 점 하나를 그린 이미지를 변형하고 옮겨진 점의 무게 중심을 돌려준다.
    private func moved(_ marker: CGPoint, by primitives: [ShapePrimitive]) throws -> CGPoint {
        let output = try warp(Support.markers([marker], extent: extent), primitives)
        let expected = Support.expectedPosition(of: marker, primitives: primitives, limit: limit)
        return try XCTUnwrap(Support.markerCentroid(Support.grid(output), near: expected))
    }

    private func assertNear(
        _ actual: CGPoint, _ expected: CGPoint, file: StaticString = #filePath, line: UInt = #line
    ) {
        XCTAssertEqual(actual.x, expected.x, accuracy: Self.tolerance, file: file, line: line)
        XCTAssertEqual(actual.y, expected.y, accuracy: Self.tolerance, file: file, line: line)
    }

    func testNoPrimitivesReturnsInputBytes() throws {
        let input = Support.gradient()
        XCTAssertEqual(try Support.bytes(warp(input, [])), try Support.bytes(input))
        let idle = ShapePrimitive.push(center: CGPoint(x: 64, y: 40), vector: CGVector(dx: 0, dy: 0), radius: 20)
        XCTAssertEqual(try Support.bytes(warp(input, [idle])), try Support.bytes(input), "이동량 0인 원소만 있으면 그대로")
    }

    func testPushMovesMarkerAlongVector() throws {
        let push = ShapePrimitive.push(center: center, vector: CGVector(dx: 6, dy: 3), radius: 40)
        let result = try moved(center, by: [push])
        assertNear(result, Support.expectedPosition(of: center, primitives: [push], limit: limit))
        XCTAssertGreaterThan(result.x - center.x, 5, "벡터 방향(+x)으로 5px 넘게 움직인다")
        XCTAssertGreaterThan(result.y - center.y, 2, "벡터 방향(+y)으로 움직인다")
    }

    func testNegativePushMovesMarkerBack() throws {
        let push = ShapePrimitive.push(center: center, vector: CGVector(dx: -6, dy: -3), radius: 40)
        let result = try moved(center, by: [push])
        assertNear(result, Support.expectedPosition(of: center, primitives: [push], limit: limit))
        XCTAssertLessThan(result.x - center.x, -5, "음수 이동량이 지도에서 잘리지 않는다")
    }

    func testTwoPushesAddTheirShifts() throws {
        let right = ShapePrimitive.push(center: center, vector: CGVector(dx: 5, dy: 0), radius: 40)
        let up = ShapePrimitive.push(center: center, vector: CGVector(dx: 0, dy: 4), radius: 40)
        let rightOnly = try moved(center, by: [right])
        let upOnly = try moved(center, by: [up])
        let both = try moved(center, by: [right, up])
        let summedX = (rightOnly.x - center.x) + (upOnly.x - center.x)
        let summedY = (rightOnly.y - center.y) + (upOnly.y - center.y)
        XCTAssertEqual(both.x - center.x, summedX, accuracy: 1, "두 원소의 이동은 각각의 합과 비슷하다")
        XCTAssertEqual(both.y - center.y, summedY, accuracy: 1)
    }

    func testScaleMagnifiesAroundCenter() throws {
        let scale = ShapePrimitive.scale(center: center, factor: 0.2, radius: 40)
        let left = CGPoint(x: center.x - 12, y: center.y)
        let right = CGPoint(x: center.x + 12, y: center.y)
        let grid = try Support.grid(warp(Support.markers([left, right], extent: extent), [scale]))
        let expectedLeft = Support.expectedPosition(of: left, primitives: [scale], limit: limit)
        let expectedRight = Support.expectedPosition(of: right, primitives: [scale], limit: limit)
        let movedLeft = try XCTUnwrap(Support.markerCentroid(grid, near: expectedLeft, window: 8))
        let movedRight = try XCTUnwrap(Support.markerCentroid(grid, near: expectedRight, window: 8))
        assertNear(movedLeft, expectedLeft)
        assertNear(movedRight, expectedRight)
        XCTAssertGreaterThan(movedRight.x - movedLeft.x, 26, "두 점 사이 24px가 넓어진다")
    }

    func testDisplacementIsLimitedPerPrimitive() throws {
        let push = ShapePrimitive.push(center: center, vector: CGVector(dx: 100, dy: 0), radius: 40)
        XCTAssertEqual(push.limited(to: limit), .push(center: center, vector: CGVector(dx: 10, dy: 0), radius: 40))
        XCTAssertEqual(
            ShapePrimitive.scale(center: center, factor: 3, radius: 40).limited(to: limit),
            .scale(center: center, factor: 0.25, radius: 40))
        XCTAssertEqual(
            ShapePrimitive.band(yStart: 96, yEnd: 32, stretch: -2).limited(to: limit),
            .band(yStart: 96, yEnd: 32, stretch: -0.25))
        let result = try moved(center, by: [push])
        assertNear(result, Support.expectedPosition(of: center, primitives: [push], limit: limit))
        XCTAssertLessThan(result.x - center.x, 10.5, "반지름 × 0.25를 넘지 않는다")
    }

    func testBandMappingIsMonotoneAndContinuous() {
        let band = ShapePrimitive.band(yStart: 96, yEnd: 32, stretch: 0.08)
        let step: CGFloat = 0.5
        // smoothstep의 최대 기울기는 1.5라 한 걸음 변화는 step × 0.08 × 1.5 이하다.
        let maximumStepChange = step * 0.08 * 1.5 + 1e-9
        var previousSource = -CGFloat.infinity
        var previousShift = band.displacement(at: CGPoint(x: 0, y: 0)).dy
        for index in 0...256 {
            let y = CGFloat(index) * step
            let shift = band.displacement(at: CGPoint(x: 0, y: y)).dy
            let source = y - shift
            XCTAssertGreaterThan(source, previousSource, "출력 y가 커지면 읽는 입력 y도 커진다(접힘 없음) y=\(y)")
            XCTAssertLessThanOrEqual(abs(shift - previousShift), maximumStepChange, "끊김 없음 y=\(y)")
            previousSource = source
            previousShift = shift
        }
        XCTAssertEqual(band.displacement(at: CGPoint(x: 0, y: 10)).dy, -5.12, accuracy: 1e-9, "띠 아래 내용은 5.12px 내려온다")
        XCTAssertEqual(band.displacement(at: CGPoint(x: 0, y: 10)).dx, 0)
        XCTAssertEqual(band.displacement(at: CGPoint(x: 0, y: 64)).dy, -2.56, accuracy: 1e-9, "띠 가운데는 전체 이동의 절반")
        XCTAssertEqual(band.displacement(at: CGPoint(x: 0, y: 110)).dy, 0, "띠 위는 그대로")
    }

    func testBandEdgesHaveZeroSlope() {
        let band = ShapePrimitive.band(yStart: 96, yEnd: 32, stretch: 0.08)
        let h: CGFloat = 0.01
        func slope(at y: CGFloat) -> CGFloat {
            let above = band.displacement(at: CGPoint(x: 0, y: y + h)).dy
            let below = band.displacement(at: CGPoint(x: 0, y: y - h)).dy
            return (above - below) / (2 * h)
        }
        XCTAssertEqual(slope(at: 96), 0, accuracy: 1e-3, "골반(띠 시작)에서 꺾이지 않는다")
        XCTAssertEqual(slope(at: 32), 0, accuracy: 1e-3, "발목(띠 끝)에서 꺾이지 않는다")
        XCTAssertEqual(slope(at: 64), 0.12, accuracy: 1e-3, "가운데 기울기는 1.5 × stretch")
    }

    func testBandMovesMarkerBeyondBand() throws {
        let band = ShapePrimitive.band(yStart: 96, yEnd: 32, stretch: 0.08)
        let below = CGPoint(x: 64, y: 20)
        let above = CGPoint(x: 64, y: 110)
        let input = Support.markers([below, above], extent: extent)
        let before = try Support.grid(input)
        let after = try Support.grid(warp(input, [band]))
        let movedBelow = try XCTUnwrap(Support.markerCentroid(after, near: CGPoint(x: 64, y: 15), window: 8))
        let originalBelow = try XCTUnwrap(Support.markerCentroid(before, near: below, window: 8))
        let movedAbove = try XCTUnwrap(Support.markerCentroid(after, near: above, window: 8))
        let originalAbove = try XCTUnwrap(Support.markerCentroid(before, near: above, window: 8))
        XCTAssertEqual(movedBelow.y, originalBelow.y - 5.12, accuracy: Self.tolerance)
        XCTAssertEqual(movedBelow.x, originalBelow.x, accuracy: 0.25)
        XCTAssertEqual(movedAbove.y, originalAbove.y, accuracy: 0.25)
    }

    func testPushNearEdgeKeepsExtentAndOpaqueEdges() throws {
        let input = Support.gradient()
        let push = ShapePrimitive.push(center: CGPoint(x: 2, y: 40), vector: CGVector(dx: 8, dy: 0), radius: 32)
        let output = try warp(input, [push])
        XCTAssertEqual(output.extent, input.extent)
        let after = try Support.grid(output)
        let before = try Support.grid(input)
        XCTAssertEqual(after.rgba(CGPoint(x: 0, y: 40))[3], 255, "가장자리는 바깥 픽셀을 늘려 채워 불투명")
        XCTAssertNotEqual(after.rgba(CGPoint(x: 6, y: 40)), before.rgba(CGPoint(x: 6, y: 40)), "가장자리 근처가 움직인다")
        XCTAssertEqual(after.rgba(CGPoint(x: 100, y: 40)), before.rgba(CGPoint(x: 100, y: 40)), "반지름 밖은 그대로")
    }

    func testInfluenceBoundsCoverEachPrimitiveInsideExtent() {
        // 반지름 20 + 최대 이동 6 + ROI 여백 2 = 28.
        let push = ShapePrimitive.push(center: center, vector: CGVector(dx: 6, dy: 0), radius: 20)
        XCTAssertEqual(
            DisplacementWarp.influenceBounds([push], extent: extent), CGRect(x: 36, y: 36, width: 56, height: 56))
        // 반지름 10 + 이동 0.1 × 10 + 2 = 13, 왼쪽 아래 모서리에서 잘린다.
        let corner = ShapePrimitive.scale(center: CGPoint(x: 2, y: 2), factor: 0.1, radius: 10)
        XCTAssertEqual(
            DisplacementWarp.influenceBounds([corner], extent: extent), CGRect(x: 0, y: 0, width: 15, height: 15))
        XCTAssertEqual(
            DisplacementWarp.influenceBounds([push, corner], extent: extent), CGRect(x: 0, y: 0, width: 92, height: 92))
        // 띠는 시작 행 96 + 이동 5.12 + 여백 2 = 103.12 아래만 움직인다. 위쪽 행은 패치에서 빠진다.
        let band = ShapePrimitive.band(yStart: 96, yEnd: 32, stretch: 0.08)
        XCTAssertEqual(
            DisplacementWarp.influenceBounds([band], extent: extent), CGRect(x: 0, y: 0, width: 128, height: 104))
        // 위로 늘리는 띠는 32 − 7.12 = 24.88 위만.
        let rising = ShapePrimitive.band(yStart: 32, yEnd: 96, stretch: 0.08)
        XCTAssertEqual(
            DisplacementWarp.influenceBounds([rising], extent: extent), CGRect(x: 0, y: 24, width: 128, height: 104))
    }

    /// 두 얼굴의 원소 경계 안만 변형한 결과가 전체 extent 변형과 같고, 경계 밖은 입력 바이트 그대로다.
    func testPatchWarpMatchesFullExtentWarp() throws {
        let faceExtent = SyntheticFace.extent
        let base = SyntheticFace.make().face
        let faces = [
            base.transformed(scale: 0.5, offset: NormalizedPoint(x: 0, y: 0.25)),
            base.transformed(scale: 0.5, offset: NormalizedPoint(x: 0.5, y: 0.25)),
        ]
        let adjustments = FaceShapeAdjustments(width: -1, eyeSize: 1, chinLength: 1)
        let primitives = faces.flatMap {
            FaceShapeRig.primitives(face: $0, adjustments: adjustments, extent: faceExtent, tuning: RenderTuning())
        }
        let patch = DisplacementWarp.influenceBounds(primitives.map { $0.limited(to: limit) }, extent: faceExtent)
        XCTAssertFalse(patch.isEmpty)
        XCTAssertLessThan(patch.width * patch.height, faceExtent.width * faceExtent.height, "경계가 extent보다 작아야 의미가 있다")
        // 사진처럼 비트맵에서 읽은 입력을 쓴다. 절차 생성 입력은 중간 버퍼 정밀도에 따라 1 LSB씩 달라져 통과 여부를 가릴 수 없다.
        let texture = Support.skinTexture(size: SyntheticFace.size)
        let translucent = texture.applyingFilter(
            "CIColorMatrix", parameters: ["inputAVector": CIVector(x: 0, y: 0, z: 0, w: 0.5)])
        let inputs = try [texture, translucent].map { CIImage(cgImage: try Support.renderer.makeCGImage($0)) }
        for input in inputs {
            let patched = try Support.grid(
                DisplacementWarp.shared.apply(primitives, to: input, extent: faceExtent, limit: limit))
            let full = try Support.grid(
                DisplacementWarp.shared.apply(
                    primitives, to: input, extent: faceExtent, limit: limit, region: faceExtent))
            let original = try Support.grid(input)
            var worstInside = 0
            var worstOutside = 0
            var changedInside = 0
            var changedOutside = 0
            for y in 0..<SyntheticFace.size {
                for x in 0..<SyntheticFace.size {
                    let point = CGPoint(x: x, y: y)
                    let pixel = patched.rgba(point)
                    let difference = zip(pixel, full.rgba(point)).map { abs(Int($0) - Int($1)) }.max() ?? 0
                    let changed = pixel == original.rgba(point) ? 0 : 1
                    if patch.contains(CGPoint(x: Double(x) + 0.5, y: Double(y) + 0.5)) {
                        worstInside = max(worstInside, difference)
                        changedInside += changed
                    } else {
                        worstOutside = max(worstOutside, difference)
                        changedOutside += changed
                    }
                }
            }
            XCTAssertLessThanOrEqual(worstInside, 1, "경계 안은 전체 변형과 ±1 LSB 안")
            XCTAssertGreaterThan(changedInside, 0, "경계 안은 실제로 변형된다")
            XCTAssertEqual(changedOutside, 0, "경계 밖은 입력 바이트 그대로")
            XCTAssertLessThanOrEqual(worstOutside, 1, "경계 밖도 전체 변형과 ±1 LSB 안")
        }
    }

    func testBandIsNotDrawnIntoFieldAndRowsAboveKeepInputBytes() throws {
        let band = ShapePrimitive.band(yStart: 96, yEnd: 32, stretch: 0.08)
        let push = ShapePrimitive.push(center: CGPoint(x: 100, y: 110), vector: CGVector(dx: 3, dy: 0), radius: 10)
        XCTAssertTrue(DisplacementWarp.fieldBounds([band], extent: extent).isNull, "띠만 있으면 지도를 그리지 않는다")
        XCTAssertEqual(
            DisplacementWarp.fieldBounds([band, push], extent: extent),
            DisplacementWarp.influenceBounds([push], extent: extent), "지도는 push 경계만")
        // 사진처럼 비트맵에서 읽은 입력. 패치 밖 바이트 동일성은 비트맵 입력에서만 판정할 수 있다(C Task 4).
        let input = CIImage(cgImage: try Support.renderer.makeCGImage(Support.skinTexture(size: 128)))
        let before = try Support.grid(input)
        let after = try Support.grid(warp(input, [band]))
        var changedAbove = 0
        var changedBelow = 0
        for y in 0..<128 {
            for x in 0..<128 {
                let point = CGPoint(x: x, y: y)
                guard after.rgba(point) != before.rgba(point) else { continue }
                if y >= 104 {
                    changedAbove += 1
                } else {
                    changedBelow += 1
                }
            }
        }
        XCTAssertEqual(changedAbove, 0, "띠 시작 위쪽 행(패치 밖)은 입력 바이트 그대로")
        XCTAssertGreaterThan(changedBelow, 0, "띠 안과 너머는 움직인다")
    }

    /// 띠 이동이 512px를 넘어도 반정밀도 지도의 0.5px 계단이 생기지 않는다(띠는 샘플링 커널이 float로 계산한다).
    func testLargeBandShiftKeepsSubpixelAccuracy() throws {
        let tall = CGRect(x: 0, y: 0, width: 32, height: 4096)
        // 2600 × 0.24625 = 640.25. 반정밀도는 512~1024에서 0.5 간격이라 지도에 담으면 640으로 반올림된다.
        let band = ShapePrimitive.band(yStart: 100, yEnd: 2700, stretch: 0.24625)
        let marker = CGPoint(x: 16, y: 3000)
        let input = Support.markers([marker], extent: tall)
        let output = try DisplacementWarp.shared.apply([band], to: input, extent: tall, limit: limit)
        // 가장자리를 늘려 채운 뒤 옮겨야 기준 이미지 extent가 tall 그대로라 격자 좌표가 출력과 같다.
        let reference = input.clampedToExtent().transformed(by: CGAffineTransform(translationX: 0, y: 640.25))
            .cropped(to: tall)
        let expected = CGPoint(x: 16, y: 3640.25)
        let moved = try XCTUnwrap(Support.markerCentroid(Support.grid(output), near: expected, window: 8))
        let translated = try XCTUnwrap(Support.markerCentroid(Support.grid(reference), near: expected, window: 8))
        XCTAssertEqual(moved.y, translated.y, accuracy: 0.1, "띠 너머는 640.25px 평행 이동과 같다")
        XCTAssertEqual(moved.x, translated.x, accuracy: 0.05)
    }

    func testOnlyOneBandIsAccepted() {
        let first = ShapePrimitive.band(yStart: 96, yEnd: 32, stretch: 0.05)
        let second = ShapePrimitive.band(yStart: 120, yEnd: 60, stretch: 0.05)
        XCTAssertThrowsError(try warp(Support.gradient(), [first, second])) { error in
            XCTAssertEqual(error as? MellowError, .renderFailed, "샘플링 커널은 띠 하나만 받는다")
        }
    }

    func testBandAndPushMoveMarkerTogether() throws {
        let band = ShapePrimitive.band(yStart: 96, yEnd: 32, stretch: 0.08)
        let push = ShapePrimitive.push(center: CGPoint(x: 64, y: 20), vector: CGVector(dx: 6, dy: 0), radius: 40)
        let marker = CGPoint(x: 64, y: 20)
        let result = try moved(marker, by: [band, push])
        assertNear(result, Support.expectedPosition(of: marker, primitives: [band, push], limit: limit))
        XCTAssertGreaterThan(result.x - marker.x, 4, "push 몫")
        XCTAssertLessThan(result.y - marker.y, -4, "띠 몫")
    }

    // MARK: - 보호 워프(묶음)

    /// 보호 테스트의 extent와 사람 사각형. 사각형 오른쪽 변은 x = 140이다.
    private static let guardExtent = CGRect(x: 0, y: 0, width: 256, height: 256)
    private static let personRect = CGRect(x: 40, y: 32, width: 100, height: 192)
    /// 변에 둔 push의 이동(v)과 반지름(픽셀).
    private static let edgeShift: CGFloat = 12
    private static let edgeRadius: CGFloat = 80

    private func personMask(_ rect: CGRect) -> CIImage {
        Support.personMask(size: Self.guardExtent.size, person: rect)
    }

    /// 사각형 오른쪽 변 가운데에서 가로로 미는 원소. direction −1이면 안쪽(가늘게), +1이면 바깥(넓게).
    private func edgePush(_ direction: CGFloat, edge: CGFloat = personRect.maxX) -> ShapePrimitive {
        .push(
            center: CGPoint(x: edge, y: Self.personRect.midY),
            vector: CGVector(dx: direction * Self.edgeShift, dy: 0), radius: Self.edgeRadius)
    }

    private func groupField(_ groups: [ShapeGroup]) throws -> CIImage {
        try XCTUnwrap(
            DisplacementWarp.shared.field(
                groups: groups, extent: Self.guardExtent, limit: limit, tuning: RenderTuning()))
    }

    func testGroupsWithoutMasksMatchTheSingleFieldPath() throws {
        let input = CIImage(cgImage: try Support.renderer.makeCGImage(Support.skinTexture(size: 128)))
        let first = [
            ShapePrimitive.push(center: CGPoint(x: 40, y: 64), vector: CGVector(dx: 5, dy: 1), radius: 30),
            ShapePrimitive.scale(center: CGPoint(x: 70, y: 80), factor: 0.1, radius: 20),
        ]
        let second = [
            ShapePrimitive.push(center: CGPoint(x: 60, y: 60), vector: CGVector(dx: -4, dy: 2), radius: 40),
            ShapePrimitive.band(yStart: 50, yEnd: 10, stretch: 0.05),
        ]
        let groups = [ShapeGroup(primitives: first), ShapeGroup(primitives: second)]
        let grouped = try DisplacementWarp.shared.apply(
            groups: groups, to: input, extent: input.extent, limit: limit, tuning: RenderTuning())
        let single = try DisplacementWarp.shared.apply(first + second, to: input, extent: input.extent, limit: limit)
        XCTAssertEqual(try Support.bytes(grouped), try Support.bytes(single), "마스크가 없으면 보호 없이 한 지도로 그린다")
    }

    func testBackgroundBeyondTheBandDoesNotMove() throws {
        let push = edgePush(-1)
        let bare = try groupField([ShapeGroup(primitives: [push])])
        let guarded = try groupField([ShapeGroup(primitives: [push], ownMask: personMask(Self.personRect))])
        let y = Self.personRect.midY
        let outside = CGPoint(x: Self.personRect.maxX + 4 * Self.edgeShift + 4, y: y)
        let inside = CGPoint(x: Self.personRect.maxX - Self.edgeShift / 2, y: y)
        XCTAssertGreaterThan(try ShapeTestSupport.shift(bare, at: outside), 1, "보호가 없으면 배경도 움직인다")
        XCTAssertLessThanOrEqual(try ShapeTestSupport.shift(guarded, at: outside), 0.25, "띠 너머 배경은 움직이지 않는다")
        let expected = try ShapeTestSupport.shift(bare, at: inside)
        XCTAssertEqual(
            try ShapeTestSupport.shift(guarded, at: inside), expected, accuracy: expected * 0.02, "사람 안쪽은 그대로 민다")
    }

    func testWideningKeepsMostOfTheShift() throws {
        let push = edgePush(1)
        let bare = try groupField([ShapeGroup(primitives: [push])])
        let guarded = try groupField([ShapeGroup(primitives: [push], ownMask: personMask(Self.personRect))])
        let beyond = CGPoint(x: Self.personRect.maxX + Self.edgeShift, y: Self.personRect.midY)
        let expected = try ShapeTestSupport.shift(bare, at: beyond)
        XCTAssertGreaterThan(expected, Self.edgeShift / 2)
        XCTAssertGreaterThanOrEqual(
            try ShapeTestSupport.shift(guarded, at: beyond), expected * 0.9, "실루엣 바로 바깥도 넓히기를 막지 않는다")
    }

    func testOtherPersonIsNotMoved() throws {
        let first = CGRect(x: 40, y: 32, width: 88, height: 192)
        let second = CGRect(x: first.maxX, y: 32, width: 88, height: 192)
        let push = edgePush(-1, edge: first.maxX)
        let guarded = try groupField([
            ShapeGroup(primitives: [push], ownMask: personMask(first), otherMasks: [personMask(second)])
        ])
        let bare = try groupField([ShapeGroup(primitives: [push])])
        let y = first.midY
        XCTAssertGreaterThan(try ShapeTestSupport.shift(bare, at: CGPoint(x: second.minX + 4, y: y)), 1)
        for x in stride(from: second.minX + 2, through: second.maxX - 1, by: 4) {
            for dy in [CGFloat(-40), 0, 40] {
                let point = CGPoint(x: x, y: y + dy)
                XCTAssertLessThanOrEqual(
                    try ShapeTestSupport.shift(guarded, at: point), 0.25, "옆 사람 안쪽은 움직이지 않는다 \(point)")
            }
        }
    }

    func testCapsuleGuardZeroesTorsoShiftOnTheArm() throws {
        let everyone = personMask(Self.guardExtent)
        let push = ShapePrimitive.push(center: CGPoint(x: 128, y: 128), vector: CGVector(dx: -12, dy: 0), radius: 90)
        let start = CGPoint(x: 120, y: 180)
        let end = CGPoint(x: 140, y: 90)
        let capsule = ShapeGuard.capsule(start: start, end: end, radius: 20, feather: 6)
        let bare = try groupField([ShapeGroup(primitives: [push])])
        let guarded = try groupField([ShapeGroup(primitives: [push], ownMask: everyone, guards: [capsule])])
        let middle = ShapeTestSupport.lerp(start, end, 0.5)
        // 선분에 수직인 단위 벡터. 선분 방향 (20, −90)을 반시계로 돌렸다.
        let length = hypot(end.x - start.x, end.y - start.y)
        let normal = CGVector(dx: (start.y - end.y) / length, dy: (end.x - start.x) / length)
        for along in [CGFloat(0.1), 0.5, 0.9] {
            for across in [CGFloat(-18), 0, 18] {
                let point = ShapeTestSupport.offset(ShapeTestSupport.lerp(start, end, along), normal, across)
                XCTAssertGreaterThan(try ShapeTestSupport.shift(bare, at: point), 1)
                XCTAssertLessThanOrEqual(try ShapeTestSupport.shift(guarded, at: point), 0.01, "캡슐 안은 막는다 \(point)")
            }
        }
        for across in [CGFloat(-28), 28, -40, 40] {
            let point = ShapeTestSupport.offset(middle, normal, across)
            let expected = try XCTUnwrap(ShapeTestSupport.fieldVectors(bare, at: [point]).first)
            let actual = try XCTUnwrap(ShapeTestSupport.fieldVectors(guarded, at: [point]).first)
            XCTAssertEqual(actual.dx, expected.dx, accuracy: 0.01, "반지름 + feather 밖은 그대로 \(point)")
            XCTAssertEqual(actual.dy, expected.dy, accuracy: 0.01)
        }
    }
}
