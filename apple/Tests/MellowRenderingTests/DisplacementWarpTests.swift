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
        var previousSource = -CGFloat.infinity
        var previousShift = band.displacement(at: CGPoint(x: 0, y: 0)).dy
        for index in 0...256 {
            let y = CGFloat(index) * step
            let shift = band.displacement(at: CGPoint(x: 0, y: y)).dy
            let source = y - shift
            XCTAssertGreaterThan(source, previousSource, "출력 y가 커지면 읽는 입력 y도 커진다(접힘 없음) y=\(y)")
            XCTAssertLessThanOrEqual(abs(shift - previousShift), step * 0.08 + 1e-9, "끊김 없음 y=\(y)")
            previousSource = source
            previousShift = shift
        }
        XCTAssertEqual(band.displacement(at: CGPoint(x: 0, y: 10)).dy, -5.12, accuracy: 1e-9, "띠 아래 내용은 5.12px 내려온다")
        XCTAssertEqual(band.displacement(at: CGPoint(x: 0, y: 10)).dx, 0)
        XCTAssertEqual(band.displacement(at: CGPoint(x: 0, y: 110)).dy, 0, "띠 위는 그대로")
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
        let band = ShapePrimitive.band(yStart: 96, yEnd: 32, stretch: 0.08)
        XCTAssertEqual(DisplacementWarp.influenceBounds([band], extent: extent), extent, "띠는 그 너머 전체를 옮긴다")
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
}
