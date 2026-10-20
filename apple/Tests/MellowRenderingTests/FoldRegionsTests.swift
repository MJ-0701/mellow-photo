import CoreImage
import MellowShared
import XCTest

@testable import MellowRendering

final class FoldRegionsTests: XCTestCase {
    typealias Support = RenderingTestSupport

    private let extent = SyntheticFace.extent
    private let tuning = RenderTuning()

    func testDarkCircleMaskSitsUnderBothEyesAndLeavesEyesAndCheeks() throws {
        let face = SyntheticFace.make().face
        let mask = try XCTUnwrap(FaceRegions.darkCircleMask(face: face, extent: extent, tuning: tuning))
        XCTAssertEqual(mask.image.extent, extent)
        let pixels = try Support.grid(mask.image)
        XCTAssertGreaterThan(pixels.red(SyntheticFace.underLeftEye), 128)
        XCTAssertGreaterThan(pixels.red(SyntheticFace.underRightEye), 128)
        XCTAssertEqual(
            Double(pixels.red(SyntheticFace.underLeftEye)), Double(pixels.red(SyntheticFace.underRightEye)),
            accuracy: 2, "좌우 대칭")
        let outside = [
            SyntheticFace.leftEye, SyntheticFace.scleraPoint, SyntheticFace.cheek, SyntheticFace.forehead,
            SyntheticFace.mouth, SyntheticFace.outside,
        ]
        for point in outside {
            XCTAssertEqual(pixels.red(point), 0, "다크서클 밖 \(point)")
        }
        XCTAssertFalse(mask.bounds.contains(SyntheticFace.mouth), "입은 계산 영역 밖")
    }

    func testNasolabialMaskRunsFromNoseWingToMouthCornerOnBothSides() throws {
        let face = SyntheticFace.make().face
        let mask = try XCTUnwrap(FaceRegions.nasolabialMask(face: face, extent: extent, tuning: tuning))
        let pixels = try Support.grid(mask.image)
        XCTAssertGreaterThan(pixels.red(SyntheticFace.leftNasolabial), 128)
        XCTAssertGreaterThan(pixels.red(SyntheticFace.rightNasolabial), 128)
        XCTAssertEqual(
            Double(pixels.red(SyntheticFace.leftNasolabial)), Double(pixels.red(SyntheticFace.rightNasolabial)),
            accuracy: 2, "좌우 대칭")
        let outside = [
            SyntheticFace.mouth, SyntheticFace.lipPoint, SyntheticFace.philtrum, SyntheticFace.cheek,
            SyntheticFace.leftEye, SyntheticFace.leftMarionette, SyntheticFace.chinTip, SyntheticFace.outside,
        ]
        for point in outside {
            XCTAssertEqual(pixels.red(point), 0, "팔자 띠 밖 \(point)")
        }
    }

    func testMarionetteMaskDropsFromTheMouthCornersTowardTheChin() throws {
        let face = SyntheticFace.make().face
        let mask = try XCTUnwrap(FaceRegions.marionetteMask(face: face, extent: extent, tuning: tuning))
        let pixels = try Support.grid(mask.image)
        XCTAssertGreaterThan(pixels.red(SyntheticFace.leftMarionette), 128)
        XCTAssertGreaterThan(pixels.red(SyntheticFace.rightMarionette), 128)
        XCTAssertEqual(
            Double(pixels.red(SyntheticFace.leftMarionette)), Double(pixels.red(SyntheticFace.rightMarionette)),
            accuracy: 2, "좌우 대칭")
        let outside = [
            SyntheticFace.mouth, SyntheticFace.lipPoint, SyntheticFace.leftNasolabial, SyntheticFace.cheek,
            SyntheticFace.chinTip, SyntheticFace.outside,
        ]
        for point in outside {
            XCTAssertEqual(pixels.red(point), 0, "마리오네트 띠 밖 \(point)")
        }
        XCTAssertNotNil(
            FaceRegions.marionetteMask(face: face.removing([.nose]), extent: extent, tuning: tuning),
            "방향이 고정이라 코가 없어도 만든다")
    }

    func testGlabellaMaskSitsBetweenTheBrows() throws {
        let face = SyntheticFace.make().face
        let mask = try XCTUnwrap(FaceRegions.glabellaMask(face: face, extent: extent, tuning: tuning))
        let pixels = try Support.grid(mask.image)
        XCTAssertGreaterThan(pixels.red(SyntheticFace.glabella), 128)
        let outside = [
            SyntheticFace.leftBrowCenter, SyntheticFace.forehead, SyntheticFace.leftEye, SyntheticFace.bridge,
            SyntheticFace.cheek,
        ]
        for point in outside {
            XCTAssertEqual(pixels.red(point), 0, "미간 밖 \(point)")
        }
    }

    func testFoldMasksFollowARolledFace() throws {
        let rolled = SyntheticFace.make().face.rotated(by: .pi / 6, about: SyntheticFace.pivot)
        let pixels = try Support.grid(
            XCTUnwrap(FaceRegions.darkCircleMask(face: rolled, extent: extent, tuning: tuning)).image)
        XCTAssertGreaterThan(pixels.red(SyntheticFace.rolledUnderLeftEye), 128)
        XCTAssertGreaterThan(pixels.red(SyntheticFace.rolledUnderRightEye), 128)
        XCTAssertEqual(
            Double(pixels.red(SyntheticFace.rolledUnderLeftEye)), Double(pixels.red(SyntheticFace.rolledUnderRightEye)),
            accuracy: 2, "돌려도 좌우 대칭")
        XCTAssertNotNil(FaceRegions.nasolabialMask(face: rolled, extent: extent, tuning: tuning))
        XCTAssertNotNil(FaceRegions.marionetteMask(face: rolled, extent: extent, tuning: tuning))
        XCTAssertNotNil(FaceRegions.glabellaMask(face: rolled, extent: extent, tuning: tuning))
    }

    func testFoldMasksNeedTheirLandmarks() throws {
        let boxOnly = SyntheticFace.make(landmarks: false).face
        XCTAssertNil(FaceRegions.darkCircleMask(face: boxOnly, extent: extent, tuning: tuning))
        XCTAssertNil(FaceRegions.nasolabialMask(face: boxOnly, extent: extent, tuning: tuning))
        XCTAssertNil(FaceRegions.marionetteMask(face: boxOnly, extent: extent, tuning: tuning))
        XCTAssertNil(FaceRegions.glabellaMask(face: boxOnly, extent: extent, tuning: tuning))
        let face = SyntheticFace.make().face
        XCTAssertNil(FaceRegions.nasolabialMask(face: face.removing([.nose]), extent: extent, tuning: tuning))
        XCTAssertNil(FaceRegions.nasolabialMask(face: face.removing([.outerLips]), extent: extent, tuning: tuning))
        XCTAssertNil(FaceRegions.marionetteMask(face: face.removing([.outerLips]), extent: extent, tuning: tuning))
        XCTAssertNil(FaceRegions.glabellaMask(face: face.removing([.leftEyebrow]), extent: extent, tuning: tuning))
        let noPupils = face.removing([.leftPupil, .rightPupil])
        XCTAssertNotNil(FaceRegions.darkCircleMask(face: noPupils, extent: extent, tuning: tuning), "동공이 없어도 눈 중심으로")
        let oneEye = try XCTUnwrap(
            FaceRegions.darkCircleMask(face: face.removing([.leftEye]), extent: extent, tuning: tuning))
        let pixels = try Support.grid(oneEye.image)
        XCTAssertGreaterThan(pixels.red(SyntheticFace.underRightEye), 128, "남은 눈 아래는 그대로")
        XCTAssertEqual(pixels.red(SyntheticFace.underLeftEye), 0, "다각형이 없는 눈은 띠를 만들지 않는다")
    }
}
