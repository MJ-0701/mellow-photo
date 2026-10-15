import CoreImage
import MellowShared
import XCTest

@testable import MellowRendering

final class FeatureStageTests: XCTestCase {
    typealias Support = RenderingTestSupport

    private let extent = SyntheticFace.extent

    private func output(_ synthetic: SyntheticFace, _ features: FeatureAdjustments, face: FaceGeometry? = nil) throws
        -> CIImage
    {
        var recipe = EditRecipe()
        recipe.portrait.features = features
        let context = RenderContext(
            extent: extent, recipe: recipe, faces: [face ?? synthetic.face], tuning: RenderTuning())
        return try FeatureStage().apply(synthetic.image, in: context)
    }

    private func render(_ synthetic: SyntheticFace, _ features: FeatureAdjustments, face: FaceGeometry? = nil) throws
        -> PixelGrid
    {
        try Support.grid(output(synthetic, features, face: face))
    }

    func testZeroFeaturesOrNoFacesReturnInputBytes() throws {
        let synthetic = SyntheticFace.makeFeatures()
        XCTAssertEqual(
            try Support.bytes(output(synthetic, FeatureAdjustments())), try Support.bytes(synthetic.image))
        var recipe = EditRecipe()
        recipe.portrait.features = FeatureAdjustments(eyeBrighten: 1, teethWhiten: 1, lipVitality: 1)
        let noFaces = RenderContext(extent: extent, recipe: recipe, faces: [], tuning: RenderTuning())
        XCTAssertEqual(
            try Support.bytes(FeatureStage().apply(synthetic.image, in: noFaces)), try Support.bytes(synthetic.image))
    }

    func testEyeBrightenLiftsScleraSharpensIrisAndLeavesSkin() throws {
        let synthetic = SyntheticFace.makeFeatures()
        let before = try Support.grid(synthetic.image)
        let image = try output(synthetic, FeatureAdjustments(eyeBrighten: 1))
        let after = try Support.grid(image)
        XCTAssertGreaterThanOrEqual(
            Int(after.red(SyntheticFace.scleraPoint)), Int(before.red(SyntheticFace.scleraPoint)) + 5, "흰자가 밝아진다")
        for point in [SyntheticFace.lidSkin, SyntheticFace.mouth, SyntheticFace.lipPoint, SyntheticFace.cheek] {
            XCTAssertEqual(after.rgba(point), before.rgba(point), "눈 마스크 밖 \(point)")
        }
        let iris = CGRect(x: SyntheticFace.leftEye.x - 9, y: SyntheticFace.leftEye.y - 9, width: 18, height: 18)
        let sharpened = Support.variance(try Support.luma(image.cropped(to: iris)))
        let original = Support.variance(try Support.luma(synthetic.image.cropped(to: iris)))
        XCTAssertGreaterThan(sharpened, original * 1.2, "홍채 고리 경계가 선명해진다")
    }

    func testTeethWhitenBrightensAndNeutralizesTeethOnly() throws {
        let synthetic = SyntheticFace.makeFeatures()
        let before = try Support.grid(synthetic.image)
        let after = try render(synthetic, FeatureAdjustments(teethWhiten: 1))
        let teethBefore = before.rgba(SyntheticFace.mouth)
        let teethAfter = after.rgba(SyntheticFace.mouth)
        XCTAssertGreaterThanOrEqual(Int(teethAfter[2]), Int(teethBefore[2]) + 15, "노란기가 빠져 파랑이 오른다")
        XCTAssertGreaterThanOrEqual(Int(teethAfter[1]), Int(teethBefore[1]), "어두워지지 않는다")
        for point in [SyntheticFace.lipPoint, SyntheticFace.philtrum, SyntheticFace.scleraPoint] {
            XCTAssertEqual(after.rgba(point), before.rgba(point), "치아 마스크 밖 \(point)")
        }
    }

    func testClosedMouthTeethWhitenChangesNothing() throws {
        let closed = SyntheticFace.makeFeatures(mouthOpen: false)
        XCTAssertEqual(
            try Support.bytes(output(closed, FeatureAdjustments(teethWhiten: 1))), try Support.bytes(closed.image),
            "다문 입은 치아 미백이 아무것도 바꾸지 않는다")
    }

    func testLipVitalitySaturatesLipRingOnly() throws {
        let synthetic = SyntheticFace.makeFeatures()
        let before = try Support.grid(synthetic.image)
        let after = try render(synthetic, FeatureAdjustments(lipVitality: 1))
        let lipBefore = before.rgba(SyntheticFace.lipPoint)
        let lipAfter = after.rgba(SyntheticFace.lipPoint)
        XCTAssertGreaterThanOrEqual(
            Int(lipAfter[0]) - Int(lipAfter[1]), Int(lipBefore[0]) - Int(lipBefore[1]) + 10, "입술 채도가 오른다")
        for point in [SyntheticFace.mouth, SyntheticFace.philtrum, SyntheticFace.scleraPoint] {
            XCTAssertEqual(after.rgba(point), before.rgba(point), "입술 마스크 밖 \(point)")
        }
    }

    func testOutOfRangeFeatureValuesRenderLikeClampedValues() throws {
        let synthetic = SyntheticFace.makeFeatures()
        func rendered(_ features: FeatureAdjustments) throws -> [UInt8] {
            try Support.bytes(output(synthetic, features))
        }
        XCTAssertEqual(
            try rendered(FeatureAdjustments(eyeBrighten: 3, teethWhiten: 9)),
            try rendered(FeatureAdjustments(eyeBrighten: 1, teethWhiten: 1)))
        XCTAssertEqual(try rendered(FeatureAdjustments(lipVitality: -0.5)), try Support.bytes(synthetic.image), "음수는 0")
    }

    func testMissingLandmarksSkipOnlyTheirFeature() throws {
        let boxOnly = SyntheticFace.make(landmarks: false)
        let all = FeatureAdjustments(eyeBrighten: 1, teethWhiten: 1, lipVitality: 1)
        XCTAssertEqual(try Support.bytes(output(boxOnly, all)), try Support.bytes(boxOnly.image), "특징점 없는 얼굴은 그대로")
        let synthetic = SyntheticFace.makeFeatures()
        let before = try Support.grid(synthetic.image)
        let noInner = try render(
            synthetic, FeatureAdjustments(teethWhiten: 1), face: synthetic.face.removing([.innerLips]))
        XCTAssertEqual(noInner.rgba(SyntheticFace.mouth), before.rgba(SyntheticFace.mouth), "안쪽 입술이 없으면 치아만 건너뛴다")
        let noPupils = try render(
            synthetic, FeatureAdjustments(eyeBrighten: 1), face: synthetic.face.removing([.leftPupil, .rightPupil]))
        XCTAssertGreaterThan(
            noPupils.red(SyntheticFace.scleraPoint), before.red(SyntheticFace.scleraPoint), "동공이 없어도 흰자는 보정한다")
    }
}
