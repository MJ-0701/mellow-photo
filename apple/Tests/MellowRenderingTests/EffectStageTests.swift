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

    /// 8비트 sRGB 출력의 RGB 평균(알파 제외).
    private func meanByte(_ image: CIImage) throws -> Double {
        let bytes = try Support.bytes(image)
        let colors = bytes.enumerated().filter { $0.offset % 4 != 3 }.map { Double($0.element) }
        return colors.reduce(0, +) / Double(colors.count)
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
        XCTAssertEqual(try meanByte(first), try meanByte(input), accuracy: 1, "평균 밝기는 8비트 ±1 안")
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

    func testGlowNeverDarkensValuesAboveOne() throws {
        let input = Support.gradient().applyingFilter("CIExposureAdjust", parameters: [kCIInputEVKey: 1.5])
        let before = try Support.grid(input)
        let after = try Support.grid(output(input, EffectAdjustments(glow: 1)))
        for x in stride(from: 0, to: 128, by: 8) {
            let point = CGPoint(x: x, y: 40)
            XCTAssertGreaterThanOrEqual(after.red(point), before.red(point), "1을 넘는 밝은 영역이 어두워지지 않는다 \(point)")
        }
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

    /// 키운 잡음은 가장 가까운 화소로 뽑아 알갱이 안이 한 값이다. 선형 보간이면 알갱이 경계가 번진다.
    func testGrainLayerKeepsHardSquareGrains() throws {
        let side = 64
        let grain = 4
        let layer = try EffectStage.grainLayer(
            extent: CGRect(x: 0, y: 0, width: side, height: side), amplitude: 1, grainSize: CGFloat(grain))
        let grid = try Support.grid(layer)
        var cellValues = Set<UInt8>()
        var softPixels = 0
        for cellY in stride(from: 0, to: side, by: grain) {
            for cellX in stride(from: 0, to: side, by: grain) {
                let corner = grid.red(CGPoint(x: cellX, y: cellY))
                cellValues.insert(corner)
                for y in cellY..<(cellY + grain) {
                    for x in cellX..<(cellX + grain) where grid.red(CGPoint(x: x, y: y)) != corner {
                        softPixels += 1
                    }
                }
            }
        }
        XCTAssertEqual(softPixels, 0, "알갱이 안은 한 값")
        XCTAssertGreaterThan(cellValues.count, 1, "알갱이마다 값이 다르다")
    }
}
