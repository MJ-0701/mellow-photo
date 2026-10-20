import CoreImage
import MellowShared
import XCTest

@testable import MellowRendering

final class EffectStageTests: XCTestCase {
    typealias Support = RenderingTestSupport

    private func output(_ image: CIImage, _ effects: EffectAdjustments) throws -> CIImage {
        var recipe = EditRecipe()
        recipe.effects = effects
        let context = RenderContext(extent: image.extent, recipe: recipe, faces: [], tuning: RenderTuning())
        return try EffectStage().apply(image, in: context)
    }

    /// 선형 평균 휘도(바이트 환산 전 0…1).
    private func meanLuma(_ image: CIImage) throws -> Double {
        let values = try Support.luma(image)
        return values.reduce(0, +) / Double(values.count)
    }

    func testZeroEffectsReturnInputBytesAndOutOfRangeValuesClamp() throws {
        let input = Support.skinTexture(size: 256)
        XCTAssertTrue(try Support.bytes(output(input, EffectAdjustments())) == Support.bytes(input))
        XCTAssertTrue(
            try Support.bytes(output(input, EffectAdjustments(grain: -1, glow: -2))) == Support.bytes(input), "음수는 0")
        XCTAssertTrue(
            try Support.bytes(output(input, EffectAdjustments(grain: 3, glow: 5)))
                == Support.bytes(output(input, EffectAdjustments(grain: 1, glow: 1))))
        XCTAssertEqual(EffectStage.clamped(EffectAdjustments(grain: 2, glow: -1)), EffectAdjustments(grain: 1))
        XCTAssertEqual(EffectStage().name, "effect")
    }

    func testGrainIsDeterministicAndKeepsMeanBrightness() throws {
        let input = Support.solid(CIColor(red: 0.5, green: 0.5, blue: 0.5), size: 256)
        let first = try output(input, EffectAdjustments(grain: 1))
        let second = try output(input, EffectAdjustments(grain: 1))
        XCTAssertTrue(try Support.bytes(first) == Support.bytes(second), "같은 입력은 같은 바이트")
        XCTAssertFalse(try Support.bytes(first) == Support.bytes(input), "그레인이 보인다")
        XCTAssertEqual(try meanLuma(first), try meanLuma(input), accuracy: 0.01, "평균 밝기는 거의 그대로")
        let flatVariance = Support.variance(try Support.luma(input))
        let grainVariance = Support.variance(try Support.luma(first))
        XCTAssertGreaterThan(grainVariance, flatVariance + 1e-5, "단색에 잡음이 생긴다")
        let half = Support.variance(try Support.luma(output(input, EffectAdjustments(grain: 0.5))))
        XCTAssertLessThan(half, grainVariance, "강도 0.5는 더 약하다")
        XCTAssertEqual(EffectStage.grainSize(shortSide: 1200, tuning: RenderTuning()), 1.44, accuracy: 1e-9)
        XCTAssertEqual(EffectStage.grainSize(shortSide: 100, tuning: RenderTuning()), 1, "알갱이는 1px 아래로 내려가지 않는다")
    }

    func testGlowBrightensHighlightsMoreThanShadows() throws {
        let input = Support.gradient()
        let before = try Support.grid(input)
        let after = try Support.grid(output(input, EffectAdjustments(glow: 1)))
        let dark = CGPoint(x: 8, y: 40)
        let bright = CGPoint(x: 120, y: 40)
        let brightGain = Int(after.red(bright)) - Int(before.red(bright))
        let darkGain = Int(after.red(dark)) - Int(before.red(dark))
        XCTAssertGreaterThanOrEqual(brightGain, 8, "밝은 쪽이 환해진다")
        XCTAssertGreaterThan(brightGain, darkGain, "어두운 쪽보다 더")
        XCTAssertEqual(EffectStage.glowRadius(shortSide: 1200, tuning: RenderTuning()), 24, accuracy: 1e-9)
    }

    func testEffectsFollowTheCurrentExtentAfterGeometry() throws {
        let input = Support.skinTexture(size: 256).cropped(to: CGRect(x: 64, y: 32, width: 128, height: 96))
        let result = try output(input, EffectAdjustments(grain: 1, glow: 1))
        XCTAssertEqual(result.extent, input.extent, "기하 뒤 extent(원점 0 아님)를 그대로 둔다")
        let grid = try Support.grid(result)
        for point in [CGPoint(x: 0, y: 0), CGPoint(x: 127, y: 95), CGPoint(x: 0, y: 95), CGPoint(x: 127, y: 0)] {
            XCTAssertEqual(grid.rgba(point)[3], 255, "가장자리가 투명해지지 않는다 \(point)")
        }
    }
}
