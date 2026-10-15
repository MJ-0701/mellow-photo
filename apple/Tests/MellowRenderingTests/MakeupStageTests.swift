import CoreImage
import MellowShared
import XCTest

@testable import MellowRendering

final class MakeupStageTests: XCTestCase {
    typealias Support = RenderingTestSupport

    private let extent = SyntheticFace.extent

    private func output(
        _ synthetic: SyntheticFace, _ makeup: MakeupAdjustments, faces: [FaceGeometry]? = nil,
        catalog: MakeupCatalog? = nil
    ) throws -> CIImage {
        var recipe = EditRecipe()
        recipe.makeup = makeup
        let resolved = try catalog ?? Support.sharedMakeupCatalog()
        let context = RenderContext(
            extent: extent, recipe: recipe, faces: faces ?? [synthetic.face], tuning: RenderTuning(),
            makeupCatalog: resolved)
        return try MakeupStage().apply(synthetic.image, in: context)
    }

    /// R+G+B 바이트 합.
    private func brightness(_ pixel: [UInt8]) -> Int {
        pixel.prefix(3).reduce(0) { $0 + Int($1) }
    }

    func testZeroIntensityOrNoFacesReturnInputBytes() throws {
        let synthetic = SyntheticFace.makeFeatures()
        let input = try Support.bytes(synthetic.image)
        let named = MakeupAdjustments(lookID: "daily", lip: MakeupTint(colorID: "lip-red", intensity: 0))
        XCTAssertEqual(try Support.bytes(output(synthetic, named)), input, "강도 0이면 입력과 같은 바이트")
        let red = MakeupAdjustments(lip: MakeupTint(colorID: "lip-red", intensity: 1))
        XCTAssertEqual(try Support.bytes(output(synthetic, red, faces: [])), input, "얼굴이 없으면 그대로")
    }

    func testLipColorChangesOnlyTheLipRing() throws {
        let synthetic = SyntheticFace.makeFeatures()
        let before = try Support.grid(synthetic.image)
        let red = try Support.grid(
            output(synthetic, MakeupAdjustments(lip: MakeupTint(colorID: "lip-red", intensity: 1))))
        XCTAssertNotEqual(red.rgba(SyntheticFace.lipPoint), before.rgba(SyntheticFace.lipPoint), "입술 색이 바뀐다")
        let outside = [
            SyntheticFace.mouth, SyntheticFace.philtrum, SyntheticFace.scleraPoint, SyntheticFace.cheek,
            SyntheticFace.outside,
        ]
        for point in outside {
            XCTAssertEqual(red.rgba(point), before.rgba(point), "입술 마스크 밖 \(point)")
        }
        let coral = try Support.grid(
            output(synthetic, MakeupAdjustments(lip: MakeupTint(colorID: "lip-coral", intensity: 1))))
        XCTAssertNotEqual(coral.rgba(SyntheticFace.lipPoint), red.rgba(SyntheticFace.lipPoint), "색마다 결과가 다르다")
    }

    func testUnknownWrongPartOrMissingCatalogColorAndLandmarklessFaceSkipLip() throws {
        let synthetic = SyntheticFace.makeFeatures()
        let input = try Support.bytes(synthetic.image)
        for id in ["blush-peach", "nope", nil] as [String?] {
            let makeup = MakeupAdjustments(lip: MakeupTint(colorID: id, intensity: 1))
            XCTAssertEqual(try Support.bytes(output(synthetic, makeup)), input, "\(String(describing: id))는 건너뛴다")
        }
        let red = MakeupAdjustments(lip: MakeupTint(colorID: "lip-red", intensity: 1))
        XCTAssertEqual(try Support.bytes(output(synthetic, red, catalog: .empty)), input, "카탈로그가 없으면 립을 건너뛴다")
        let boxOnly = SyntheticFace.make(landmarks: false)
        XCTAssertEqual(try Support.bytes(output(boxOnly, red)), try Support.bytes(boxOnly.image), "특징점 없는 얼굴은 그대로")
    }

    func testOutOfRangeIntensityRendersLikeClampedValues() throws {
        let synthetic = SyntheticFace.makeFeatures()
        func rendered(_ intensity: Double) throws -> [UInt8] {
            try Support.bytes(
                output(synthetic, MakeupAdjustments(lip: MakeupTint(colorID: "lip-red", intensity: intensity))))
        }
        XCTAssertEqual(try rendered(3), try rendered(1))
        XCTAssertEqual(try rendered(-0.5), try Support.bytes(synthetic.image), "음수는 0")
    }
}
