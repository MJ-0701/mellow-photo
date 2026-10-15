import CoreImage
import MellowShared
import XCTest

@testable import MellowRendering

final class MakeupRegionsTests: XCTestCase {
    typealias Support = RenderingTestSupport

    private let extent = SyntheticFace.extent
    private let tuning = RenderTuning()

    func testBlushMaskSitsOnBothCheeksInsideTheFace() throws {
        let face = SyntheticFace.make().face
        let mask = try XCTUnwrap(FaceRegions.blushMask(face: face, extent: extent, tuning: tuning))
        XCTAssertEqual(mask.image.extent, extent)
        let pixels = try Support.grid(mask.image)
        XCTAssertGreaterThan(pixels.red(SyntheticFace.leftBlush), 200)
        XCTAssertGreaterThan(pixels.red(SyntheticFace.rightBlush), 200)
        XCTAssertEqual(
            Double(pixels.red(SyntheticFace.leftBlush)), Double(pixels.red(SyntheticFace.rightBlush)), accuracy: 2,
            "좌우 대칭")
        XCTAssertGreaterThan(pixels.red(SyntheticFace.cheek), 128, "볼 표본 점도 덮는다")
        let outside = [
            SyntheticFace.leftEye, SyntheticFace.mouth, SyntheticFace.lipPoint, SyntheticFace.forehead,
            SyntheticFace.outside,
        ]
        for point in outside {
            XCTAssertEqual(pixels.red(point), 0, "블러셔 밖 \(point)")
        }
        XCTAssertFalse(mask.bounds.contains(SyntheticFace.leftEye), "눈은 계산 영역 밖")
    }

    func testEyeshadowMaskCoversTheLidAndLeavesEyesAndCheeks() throws {
        let face = SyntheticFace.makeFeatures().face
        let mask = try XCTUnwrap(FaceRegions.eyeshadowMask(face: face, extent: extent, tuning: tuning))
        let pixels = try Support.grid(mask.image)
        XCTAssertGreaterThan(pixels.red(SyntheticFace.lidSkin), 128, "눈과 눈썹 사이 눈꺼풀")
        let outside = [
            SyntheticFace.leftEye, SyntheticFace.scleraPoint, SyntheticFace.cheek, SyntheticFace.forehead,
            SyntheticFace.mouth,
        ]
        for point in outside {
            XCTAssertEqual(pixels.red(point), 0, "아이섀도 밖 \(point)")
        }
    }

    func testBlushAndEyeshadowFollowARolledFace() throws {
        let rolled = SyntheticFace.makeFeatures().face.rotated(by: .pi / 6, about: SyntheticFace.pivot)
        let blush = try Support.grid(
            XCTUnwrap(FaceRegions.blushMask(face: rolled, extent: extent, tuning: tuning)).image)
        XCTAssertGreaterThan(blush.red(SyntheticFace.rolledLeftBlush), 200)
        XCTAssertGreaterThan(blush.red(SyntheticFace.rolledRightBlush), 200)
        let lids = try Support.grid(
            XCTUnwrap(FaceRegions.eyeshadowMask(face: rolled, extent: extent, tuning: tuning)).image)
        XCTAssertGreaterThan(lids.red(SyntheticFace.rolledLidSkin), 128)
        XCTAssertEqual(lids.red(SyntheticFace.lidSkin), 0, "돌리기 전 눈꺼풀 자리는 비어 있다")
    }

    func testMakeupMasksNeedLandmarks() {
        let boxOnly = SyntheticFace.make(landmarks: false).face
        XCTAssertNil(FaceRegions.blushMask(face: boxOnly, extent: extent, tuning: tuning))
        XCTAssertNil(FaceRegions.eyeshadowMask(face: boxOnly, extent: extent, tuning: tuning))
        let browless = SyntheticFace.makeFeatures().face.removing([.leftEyebrow, .rightEyebrow])
        XCTAssertNotNil(
            FaceRegions.eyeshadowMask(face: browless, extent: extent, tuning: tuning), "눈썹이 없으면 눈 높이만큼 올린다")
        let eyeless = SyntheticFace.makeFeatures().face.removing([.leftEye, .rightEye, .leftPupil, .rightPupil])
        XCTAssertNil(FaceRegions.blushMask(face: eyeless, extent: extent, tuning: tuning), "두 눈이 없으면 볼 위치를 정하지 않는다")
        XCTAssertNil(FaceRegions.eyeshadowMask(face: eyeless, extent: extent, tuning: tuning))
    }

    func testBrowRegionsWidenEachBrowAndSampleTheOriginalBrow() throws {
        let face = SyntheticFace.make().face
        let brows = FaceRegions.browRegions(face: face, extent: extent, tuning: tuning)
        XCTAssertEqual(brows.count, 2)
        XCTAssertEqual(brows[0].sample, SyntheticFace.leftBrow, "왼눈썹 상자를 그대로 잰다")
        let pixels = try Support.grid(brows[0].mask.image)
        XCTAssertGreaterThan(pixels.red(SyntheticFace.leftBrowCenter), 200)
        XCTAssertGreaterThan(pixels.red(SyntheticFace.aboveLeftBrow), 128, "위아래로 넓혀 눈썹 바로 위 피부도 덮는다")
        for point in [SyntheticFace.leftEye, CGPoint(x: 312, y: 338), SyntheticFace.cheek] {
            XCTAssertEqual(pixels.red(point), 0, "왼눈썹 밖 \(point)")
        }
    }

    func testContourShadesHollowsAndJawAndHighlightsBridgeForeheadAndChin() throws {
        let face = SyntheticFace.make().face
        let regions = try XCTUnwrap(FaceRegions.contourRegions(face: face, extent: extent, tuning: tuning))
        let shade = try Support.grid(XCTUnwrap(regions.shade).image)
        let highlight = try Support.grid(XCTUnwrap(regions.highlight).image)
        for point in [SyntheticFace.leftHollow, SyntheticFace.rightHollow, SyntheticFace.leftJaw] {
            XCTAssertGreaterThan(shade.red(point), 128, "쉐딩 \(point)")
        }
        for point in [SyntheticFace.bridge, SyntheticFace.foreheadCenter, SyntheticFace.chinTip] {
            XCTAssertGreaterThan(highlight.red(point), 128, "하이라이터 \(point)")
        }
        for point in [SyntheticFace.leftEye, SyntheticFace.lipPoint, SyntheticFace.outside] {
            XCTAssertEqual(shade.red(point), 0, "쉐딩 밖 \(point)")
            XCTAssertEqual(highlight.red(point), 0, "하이라이터 밖 \(point)")
        }
    }

    func testBrowAndContourNeedLandmarks() {
        let boxOnly = SyntheticFace.make(landmarks: false).face
        XCTAssertTrue(FaceRegions.browRegions(face: boxOnly, extent: extent, tuning: tuning).isEmpty)
        XCTAssertNil(FaceRegions.contourRegions(face: boxOnly, extent: extent, tuning: tuning))
        let noseless = SyntheticFace.make().face.removing([.nose])
        let regions = FaceRegions.contourRegions(face: noseless, extent: extent, tuning: tuning)
        XCTAssertNotNil(regions?.shade, "코가 없으면 코 옆만 빠진다")
        XCTAssertNotNil(regions?.highlight, "콧대만 빠지고 이마·턱 끝은 남는다")
        let oneBrow = SyntheticFace.make().face.removing([.leftEyebrow])
        XCTAssertEqual(FaceRegions.browRegions(face: oneBrow, extent: extent, tuning: tuning).count, 1)
    }

    /// 눈썹 하나가 없을 때 그 눈의 띠는 반대쪽 눈썹이 아니라 눈 높이(28px)만큼 올린다.
    /// 오른눈썹을 48px 올려 두면 잘못 고를 때 왼눈 띠 위끝이 314 + (380 − 314) × 0.75 = 363.5가 된다.
    func testLidPolygonUsesOnlyTheBrowOnTheSameSideOfTheEyes() throws {
        let face = SyntheticFace.make().face
        let frame = try XCTUnwrap(FaceFrame(face: face, extent: extent))
        let leftEye = try XCTUnwrap(FaceRegions.landmarkPolygon(face, .leftEye, extent))
        let rightEye = try XCTUnwrap(FaceRegions.landmarkPolygon(face, .rightEye, extent))
        let leftBrow = try XCTUnwrap(FaceRegions.landmarkPolygon(face, .leftEyebrow, extent))
        let raisedRightBrow = try XCTUnwrap(FaceRegions.landmarkPolygon(face, .rightEyebrow, extent))
            .map { CGPoint(x: $0.x, y: $0.y + 48) }
        func top(_ eye: [CGPoint], _ brows: [[CGPoint]]) throws -> CGFloat {
            let lid = try XCTUnwrap(FaceRegions.lidPolygon(eye: eye, brows: brows, frame: frame))
            return try XCTUnwrap(lid.map(\.y).max())
        }
        XCTAssertEqual(try top(leftEye, [raisedRightBrow]), 342, accuracy: 0.01, "반대쪽 눈썹은 쓰지 않는다")
        XCTAssertEqual(try top(leftEye, [leftBrow, raisedRightBrow]), 327.5, accuracy: 0.01, "같은 쪽 눈썹")
        XCTAssertEqual(try top(rightEye, [raisedRightBrow]), 363.5, accuracy: 0.01, "오른눈은 오른눈썹을 쓴다")
    }

    /// 넓힌 눈썹은 눈썹마다 캐시 항목 하나, 쉐딩·하이라이터는 피부 비트맵 한 항목을 함께 쓴다. 다시 그려도 늘지 않는다.
    func testBrowAndContourMasksReuseCacheEntries() {
        let face = SyntheticFace.make().face
        let cache = RegionMaskCache()
        _ = FaceRegions.browRegions(face: face, extent: extent, tuning: tuning, cache: cache)
        XCTAssertEqual(cache.count, 2)
        _ = FaceRegions.contourRegions(face: face, extent: extent, tuning: tuning, cache: cache)
        XCTAssertEqual(cache.count, 3)
        _ = FaceRegions.browRegions(face: face, extent: extent, tuning: tuning, cache: cache)
        _ = FaceRegions.contourRegions(face: face, extent: extent, tuning: tuning, cache: cache)
        XCTAssertEqual(cache.count, 3, "다시 그려도 늘지 않는다")
    }
}
