import CoreImage
import MellowShared
import XCTest

@testable import MellowRendering

final class BodySkinStageTests: XCTestCase {
    typealias Support = RenderingTestSupport

    private let extent = SyntheticFace.extent
    /// 밝기 1에서 기대하는 최소 빨강 증가와 톤 ±1에서 기대하는 최소 R−B 변화(바이트).
    private static let liftMinimum = 6
    private static let toneMinimum = 10
    /// 피부 다각형 비트맵이 눈·입술을 넓혀 뺀 고리 안의 얼굴 피부. 눈 아래끝(y 286)에서 14px, 입술 위끝(y 160)에서 7px.
    /// 입술 고리는 y 172 아래라 (256, 175)에서 고리 안 (256, 167)로 옮겼다.
    private static let underEyeRing = CGPoint(x: 200, y: 272)
    private static let lipRing = CGPoint(x: 256, y: 167)

    private func output(
        _ synthetic: SyntheticFace, _ values: BodySkinAdjustments, faces: [FaceGeometry]? = nil,
        personMask: CIImage? = SyntheticFace.bodyPersonMask, targetFace: Int? = nil
    ) throws -> CIImage {
        var recipe = EditRecipe()
        recipe.bodySkin = values
        recipe.portrait.targetFace = targetFace
        let analysis = PhotoAnalysis(faces: faces ?? [synthetic.face], personMask: personMask)
        let context = RenderContext(extent: extent, recipe: recipe, analysis: analysis, tuning: RenderTuning())
        return try BodySkinStage().apply(synthetic.image, in: context)
    }

    private func gap(_ pixel: [UInt8]) -> Int { Int(pixel[0]) - Int(pixel[2]) }

    func testZeroValuesNoPersonOrNoFaceReturnInputBytes() throws {
        let synthetic = try SyntheticFace.makeWithBody()
        let input = try Support.bytes(synthetic.image)
        let full = BodySkinAdjustments(brightness: 1, tone: 1, smoothing: 1)
        XCTAssertTrue(try Support.bytes(output(synthetic, BodySkinAdjustments())) == input, "값 0")
        XCTAssertTrue(try Support.bytes(output(synthetic, full, personMask: nil)) == input, "인물 마스크 없음")
        XCTAssertTrue(try Support.bytes(output(synthetic, full, faces: [])) == input, "얼굴 없음(기준색 없음)")
        XCTAssertEqual(BodySkinStage().name, "bodySkin")
    }

    func testBrightnessLiftsVisibleSkinAndLeavesShirtBackgroundAndEyes() throws {
        let synthetic = try SyntheticFace.makeWithBody()
        let before = try Support.grid(synthetic.image)
        let after = try Support.grid(output(synthetic, BodySkinAdjustments(brightness: 1)))
        for point in [SyntheticFace.bodySkinPoint, SyntheticFace.cheek, SyntheticFace.forehead] {
            XCTAssertGreaterThanOrEqual(Int(after.red(point)), Int(before.red(point)) + Self.liftMinimum, "피부 \(point)")
        }
        let untouched = [
            SyntheticFace.shirtPoint, SyntheticFace.backgroundBesideBody, SyntheticFace.backgroundAboveHead,
            SyntheticFace.backgroundInsideContour, SyntheticFace.leftEye, SyntheticFace.mouth, SyntheticFace.outside,
            SyntheticFace.leftBrowCenter,
        ]
        for point in untouched {
            XCTAssertEqual(after.rgba(point), before.rgba(point), "피부가 아닌 \(point)")
        }
        let half = try Support.grid(output(synthetic, BodySkinAdjustments(brightness: 0.5)))
        XCTAssertGreaterThan(half.red(SyntheticFace.bodySkinPoint), before.red(SyntheticFace.bodySkinPoint))
        XCTAssertLessThan(half.red(SyntheticFace.bodySkinPoint), after.red(SyntheticFace.bodySkinPoint))
    }

    func testToneWarmsOrCoolsSkinOnly() throws {
        let synthetic = try SyntheticFace.makeWithBody()
        let before = try Support.grid(synthetic.image)
        let warm = try Support.grid(output(synthetic, BodySkinAdjustments(tone: 1)))
        let cool = try Support.grid(output(synthetic, BodySkinAdjustments(tone: -1)))
        for point in [SyntheticFace.bodySkinPoint, SyntheticFace.cheek] {
            let original = gap(before.rgba(point))
            XCTAssertGreaterThanOrEqual(gap(warm.rgba(point)), original + Self.toneMinimum, "따뜻하게 \(point)")
            XCTAssertLessThanOrEqual(gap(cool.rgba(point)), original - Self.toneMinimum, "차갑게 \(point)")
        }
        for point in [SyntheticFace.shirtPoint, SyntheticFace.leftEye, SyntheticFace.outside] {
            XCTAssertEqual(warm.rgba(point), before.rgba(point), "\(point)")
            XCTAssertEqual(cool.rgba(point), before.rgba(point), "\(point)")
        }
    }

    func testSmoothingSkipsTheFaceAndSmoothsBodySkin() throws {
        let synthetic = try SyntheticFace.makeWithBody()
        let image = synthetic.image
        let result = try output(synthetic, BodySkinAdjustments(smoothing: 1))
        let radii = BodySkinStage.bodyRadii(shortSide: extent.width, tuning: RenderTuning())
        let before = try Support.bandVariances(
            image, in: SyntheticFace.bodyPatch, fineRadius: radii.fine, midRadius: radii.mid)
        let after = try Support.bandVariances(
            result, in: SyntheticFace.bodyPatch, fineRadius: radii.fine, midRadius: radii.mid)
        XCTAssertLessThan(after.mid, before.mid * 0.6, "몸 얼룩 대역이 준다")
        XCTAssertEqual(after.fine / before.fine, 1, accuracy: 0.1, "몸 모공 대역은 ±10% 안")
        let beforeGrid = try Support.grid(image)
        let afterGrid = try Support.grid(result)
        let patch = SyntheticFace.skinPatch
        for y in stride(from: Int(patch.minY), to: Int(patch.maxY), by: 10) {
            for x in stride(from: Int(patch.minX), to: Int(patch.maxX), by: 10) {
                let point = CGPoint(x: x, y: y)
                XCTAssertEqual(afterGrid.rgba(point), beforeGrid.rgba(point), "얼굴 피부 \(point)는 얼굴 슬라이더 몫")
            }
        }
        for point in [Self.underEyeRing, Self.lipRing] {
            XCTAssertEqual(afterGrid.rgba(point), beforeGrid.rgba(point), "눈가·입가 얼굴 피부 \(point)")
        }
        for point in [SyntheticFace.shirtPoint, SyntheticFace.backgroundBesideBody, SyntheticFace.leftEye] {
            XCTAssertEqual(afterGrid.rgba(point), beforeGrid.rgba(point), "\(point)")
        }
    }

    func testOutOfRangeValuesRenderClamped() throws {
        let synthetic = try SyntheticFace.makeWithBody()
        XCTAssertTrue(
            try Support.bytes(output(synthetic, BodySkinAdjustments(brightness: 3, tone: -5, smoothing: 2)))
                == Support.bytes(output(synthetic, BodySkinAdjustments(brightness: 1, tone: -1, smoothing: 1))))
        XCTAssertTrue(
            try Support.bytes(output(synthetic, BodySkinAdjustments(brightness: -1))) == Support.bytes(synthetic.image),
            "밝기 음수는 0")
        XCTAssertEqual(
            BodySkinStage.clamped(BodySkinAdjustments(brightness: 2, tone: 3, smoothing: -1)),
            BodySkinAdjustments(brightness: 1, tone: 1))
    }

    func testBodySkinIgnoresTargetFaceAndUsesTheLargestFace() throws {
        let synthetic = try SyntheticFace.makeWithBody()
        let small = synthetic.face.transformed(scale: 0.3, offset: NormalizedPoint(x: 0.65, y: 0.6))
        let bright = BodySkinAdjustments(brightness: 1)
        let plain = try Support.bytes(output(synthetic, bright))
        XCTAssertTrue(try Support.bytes(output(synthetic, bright, targetFace: 7)) == plain, "범위 밖 대상 얼굴도 동작")
        XCTAssertTrue(
            try Support.bytes(output(synthetic, bright, faces: [small, synthetic.face])) == plain, "기준은 가장 큰 얼굴")
        XCTAssertEqual(BodySkinStage.referenceFace([small, synthetic.face])?.boundingBox, synthetic.face.boundingBox)
        XCTAssertNil(BodySkinStage.referenceFace([]))
    }

    func testBodySkinMasksAddTwoEntriesPerPhoto() throws {
        let synthetic = try SyntheticFace.makeWithBody()
        var recipe = EditRecipe()
        recipe.bodySkin = BodySkinAdjustments(brightness: 0.5, smoothing: 0.5)
        let analysis = PhotoAnalysis(faces: [synthetic.face], personMask: SyntheticFace.bodyPersonMask)
        let context = RenderContext(extent: extent, recipe: recipe, analysis: analysis, tuning: RenderTuning())
        let first = try Support.bytes(BodySkinStage().apply(synthetic.image, in: context))
        let second = try Support.bytes(BodySkinStage().apply(synthetic.image, in: context))
        XCTAssertEqual(analysis.regionMasks.count, 2, "보호 영역 비트맵 하나 + 얼굴 다각형 비트맵 하나")
        XCTAssertTrue(first == second)
        let small = synthetic.face.transformed(scale: 0.3, offset: NormalizedPoint(x: 0.65, y: 0.6))
        let twoFaces = PhotoAnalysis(faces: [synthetic.face, small], personMask: SyntheticFace.bodyPersonMask)
        _ = try BodySkinStage().apply(
            synthetic.image,
            in: RenderContext(extent: extent, recipe: recipe, analysis: twoFaces, tuning: RenderTuning()))
        XCTAssertEqual(twoFaces.regionMasks.count, 2, "얼굴 수와 관계없이 사진마다 둘")
    }
}
