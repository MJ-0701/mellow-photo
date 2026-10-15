import CoreImage
import MellowShared
import XCTest

@testable import MellowRendering

final class FeatureRegionsTests: XCTestCase {
    typealias Support = RenderingTestSupport

    private let extent = SyntheticFace.extent
    private let tuning = RenderTuning()

    func testEyeMaskCoversEyesAndIsZeroOutsideTheirBounds() throws {
        let face = SyntheticFace.makeFeatures().face
        let mask = try XCTUnwrap(FaceRegions.eyeMask(face: face, extent: extent, tuning: tuning))
        XCTAssertEqual(mask.image.extent, extent)
        let pixels = try Support.grid(mask.image)
        XCTAssertGreaterThan(pixels.red(SyntheticFace.scleraPoint), 200)
        XCTAssertGreaterThan(pixels.red(SyntheticFace.rightEye), 200)
        XCTAssertEqual(pixels.red(SyntheticFace.lidSkin), 0)
        XCTAssertEqual(pixels.red(SyntheticFace.mouth), 0)
        XCTAssertFalse(mask.bounds.contains(SyntheticFace.lidSkin), "눈 위 피부는 계산 영역 밖")
    }

    func testIrisCirclesUsePupilOrFallBackToEyeCenter() throws {
        let face = SyntheticFace.makeFeatures().face
        let circles = FaceRegions.irisCircles(face: face, extent: extent, tuning: tuning)
        XCTAssertEqual(circles.count, 2)
        XCTAssertEqual(circles[0].center.x, SyntheticFace.leftEye.x, accuracy: 1e-6)
        XCTAssertEqual(circles[0].center.y, SyntheticFace.leftEye.y, accuracy: 1e-6)
        XCTAssertEqual(circles[0].radius, 14, accuracy: 1e-6, "눈 높이 28px × 0.5")
        var shifted = face
        shifted.landmarks[.leftPupil] = [NormalizedPoint(x: 205.0 / 512, y: 300.0 / 512)]
        let moved = FaceRegions.irisCircles(face: shifted, extent: extent, tuning: tuning)
        XCTAssertEqual(moved[0].center.x, 205, accuracy: 1e-6, "동공이 있으면 동공이 중심")
        let fallback = FaceRegions.irisCircles(
            face: face.removing([.leftPupil, .rightPupil]), extent: extent, tuning: tuning)
        XCTAssertEqual(fallback.count, 2)
        XCTAssertEqual(fallback[1].center.x, SyntheticFace.rightEye.x, accuracy: 1e-6, "동공이 없으면 눈 다각형 가운데")
        XCTAssertEqual(fallback[1].center.y, SyntheticFace.rightEye.y, accuracy: 1e-6)
    }

    func testTeethMaskKeepsTeethAndDropsRedLipInsideThePolygon() throws {
        let synthetic = SyntheticFace.makeFeatures()
        var face = synthetic.face
        // 안쪽 입술 다각형을 입술 고리까지 넓혀도 붉은 입술 픽셀은 치아로 잡히지 않는다.
        face.landmarks[.innerLips] = SyntheticFace.innerLips(radii: CGSize(width: 46, height: 16))
        let mask = try XCTUnwrap(
            try FaceRegions.teethMask(face: face, image: synthetic.image, extent: extent, tuning: tuning))
        let pixels = try Support.grid(mask.image)
        XCTAssertGreaterThan(pixels.red(SyntheticFace.mouth), 200, "치아")
        XCTAssertEqual(pixels.red(SyntheticFace.lipPoint), 0, "다각형 안이어도 붉은 입술은 치아가 아니다")
        XCTAssertEqual(pixels.red(SyntheticFace.philtrum), 0)
    }

    func testClosedMouthHasNoTeethMask() throws {
        let open = SyntheticFace.makeFeatures()
        let closed = SyntheticFace.makeFeatures(mouthOpen: false)
        let openFraction = try XCTUnwrap(FaceRegions.innerMouthAreaFraction(face: open.face, extent: extent))
        let closedFraction = try XCTUnwrap(FaceRegions.innerMouthAreaFraction(face: closed.face, extent: extent))
        XCTAssertGreaterThan(openFraction, tuning.mouthOpenMinArea)
        XCTAssertLessThan(closedFraction, tuning.mouthOpenMinArea)
        XCTAssertNotNil(try FaceRegions.teethMask(face: open.face, image: open.image, extent: extent, tuning: tuning))
        XCTAssertNil(
            try FaceRegions.teethMask(face: closed.face, image: closed.image, extent: extent, tuning: tuning),
            "다문 입은 치아 마스크가 없다")
    }

    func testLipMaskIsTheRingBetweenOuterAndInnerLips() throws {
        let face = SyntheticFace.makeFeatures().face
        let mask = try XCTUnwrap(FaceRegions.lipMask(face: face, extent: extent, tuning: tuning))
        let pixels = try Support.grid(mask.image)
        XCTAssertGreaterThan(pixels.red(SyntheticFace.lipPoint), 200)
        XCTAssertEqual(pixels.red(SyntheticFace.mouth), 0, "안쪽 입술(치아)은 뺀다")
        XCTAssertEqual(pixels.red(SyntheticFace.philtrum), 0)
        let whole = try XCTUnwrap(
            FaceRegions.lipMask(face: face.removing([.innerLips]), extent: extent, tuning: tuning))
        XCTAssertGreaterThan(try Support.grid(whole.image).red(SyntheticFace.mouth), 200, "안쪽 입술이 없으면 바깥 입술 전체")
    }

    func testFaceWithoutLandmarksHasNoFeatureMasks() throws {
        let boxOnly = SyntheticFace.make(landmarks: false)
        XCTAssertNil(FaceRegions.eyeMask(face: boxOnly.face, extent: extent, tuning: tuning))
        XCTAssertNil(FaceRegions.irisMask(face: boxOnly.face, extent: extent, tuning: tuning))
        XCTAssertNil(FaceRegions.lipMask(face: boxOnly.face, extent: extent, tuning: tuning))
        XCTAssertNil(
            try FaceRegions.teethMask(face: boxOnly.face, image: boxOnly.image, extent: extent, tuning: tuning))
        XCTAssertTrue(FaceRegions.irisCircles(face: boxOnly.face, extent: extent, tuning: tuning).isEmpty)
        XCTAssertNil(FaceRegions.innerMouthAreaFraction(face: boxOnly.face, extent: extent))
    }

    func testDemoPortraitFeatureMasksFollowRealLandmarks() throws {
        let url = try XCTUnwrap(
            Bundle.module.url(forResource: "demo-portrait", withExtension: "png", subdirectory: "Fixtures"))
        let image = try ImageLoader().load(url: url, maxDimension: 1200)
        let photo = image.extent
        let face = try XCTUnwrap(try VisionFaceAnalyzer().analyze(image).first)
        let eyes = try XCTUnwrap(FaceRegions.eyeMask(face: face, extent: photo, tuning: tuning))
        let lips = try XCTUnwrap(FaceRegions.lipMask(face: face, extent: photo, tuning: tuning))
        let pupil = try XCTUnwrap(face.landmarks[.leftPupil]?.first)
        let pupilPoint = CGPoint(x: pupil.x * photo.width, y: pupil.y * photo.height)
        XCTAssertGreaterThan(try Support.grid(eyes.image).red(pupilPoint), 128, "실제 동공은 눈 마스크 안")
        XCTAssertEqual(try Support.grid(lips.image).red(pupilPoint), 0, "동공은 입술 마스크 밖")
        let lipBox = FaceRegions.pixelRect(try XCTUnwrap(face.bounds(of: .outerLips)), in: photo)
        let brightest = try Support.renderer.readPixels(
            lips.image.applyingFilter("CIAreaMaximum", parameters: [kCIInputExtentKey: CIVector(cgRect: lipBox)]))
        XCTAssertGreaterThan(brightest[0], 0.9, "실제 입술 고리가 마스크에 들어간다")
        XCTAssertNotNil(FaceRegions.innerMouthAreaFraction(face: face, extent: photo))
    }
}
