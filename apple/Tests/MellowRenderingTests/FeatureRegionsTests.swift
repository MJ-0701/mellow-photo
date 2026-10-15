import CoreImage
import MellowShared
import XCTest

@testable import MellowRendering

final class FeatureRegionsTests: XCTestCase {
    typealias Support = RenderingTestSupport

    private let extent = SyntheticFace.extent
    private let tuning = RenderTuning()

    /// 왼눈 위끝(314) 바로 위 눈꺼풀.
    private static let upperLid = CGPoint(x: 200, y: 316)
    /// 가중치 표본 단색 이미지의 한 변(픽셀).
    private static let weightSampleSize = 8
    /// 흰자 휘도 시작점(0.45)보다 어두운 회색.
    private static let darkGray = CIColor(red: 0.3, green: 0.3, blue: 0.3)
    /// 흰자만큼 밝지만 채도가 높은 피부.
    private static let brightSkin = CIColor(red: 0.95, green: 0.72, blue: 0.6)

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

    func testIrisMaskCoversIrisOnly() throws {
        let face = SyntheticFace.makeFeatures().face
        let mask = try XCTUnwrap(FaceRegions.irisMask(face: face, extent: extent, tuning: tuning))
        let pixels = try Support.grid(mask.image)
        XCTAssertGreaterThan(pixels.red(SyntheticFace.leftEye), 250, "눈동자 가운데")
        XCTAssertGreaterThan(pixels.red(SyntheticFace.rightEye), 250)
        XCTAssertEqual(pixels.red(SyntheticFace.scleraPoint), 0, "눈 안이지만 눈동자 밖(흰자)")
        XCTAssertEqual(pixels.red(Self.upperLid), 0, "위 눈꺼풀")
        XCTAssertEqual(pixels.red(SyntheticFace.lidSkin), 0)
    }

    func testScleraWeightKeepsBrightPlainPixelsOnly() throws {
        let rule = ToneRule.sclera(tuning)
        func weight(_ color: CIColor) throws -> Float {
            let image = Support.solid(color, size: Self.weightSampleSize)
            let weighted = try FeatureKernels.shared.weight(of: image, rule: rule, extent: image.extent)
            return try Support.renderer.readPixels(weighted)[0]
        }
        XCTAssertGreaterThan(try weight(SyntheticFace.scleraColor), 0.9, "밝고 무채색인 흰자")
        XCTAssertLessThan(try weight(Self.darkGray), 0.1, "어두운 회색")
        XCTAssertLessThan(try weight(Self.brightSkin), 0.1, "밝지만 색이 있는 피부")
        XCTAssertLessThan(try weight(SyntheticFace.irisRingColors[1]), 0.1, "홍채")
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
