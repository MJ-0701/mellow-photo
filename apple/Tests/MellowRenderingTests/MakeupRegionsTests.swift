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
}
