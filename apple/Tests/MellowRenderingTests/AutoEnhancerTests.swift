import CoreImage
import MellowShared
import XCTest

@testable import MellowRendering

final class AutoEnhancerTests: XCTestCase {
    typealias Support = RenderingTestSupport
    private let enhancer = AutoEnhancer(tuning: RenderTuning(), renderer: RenderingTestSupport.renderer)

    func testDarkImageGetsPositiveExposureAndBrightImageNegative() throws {
        let dark = Support.solid(CIColor(red: 0.12, green: 0.12, blue: 0.12), size: 64)
        let bright = Support.solid(CIColor(red: 0.9, green: 0.9, blue: 0.9), size: 64)
        XCTAssertGreaterThan(try enhancer.suggestion(for: dark, hasFaces: false).color.exposure, 0)
        XCTAssertLessThan(try enhancer.suggestion(for: bright, hasFaces: false).color.exposure, 0)
    }

    func testSolidImageOnlyAdjustsExposure() throws {
        let gray = Support.solid(CIColor(red: 0.3, green: 0.3, blue: 0.3), size: 64)
        let suggestion = try enhancer.suggestion(for: gray, hasFaces: false)
        XCTAssertEqual(suggestion.detail, DetailAdjustments())
        XCTAssertEqual(suggestion.color.warmth, 0)
        XCTAssertEqual(suggestion.color.saturation, 1)
        XCTAssertEqual(suggestion.color.contrast, 1)
    }

    func testGradientGetsHighlightAndShadowRecoveryWithinRanges() throws {
        let suggestion = try enhancer.suggestion(for: Support.gradient(), hasFaces: false)
        XCTAssertTrue((-1...0).contains(suggestion.detail.highlights))
        XCTAssertTrue((0...1).contains(suggestion.detail.shadows))
        XCTAssertEqual(suggestion.color.saturation, RenderTuning().autoSaturation)
        XCTAssertEqual(suggestion.color.contrast, RenderTuning().autoContrast)
        XCTAssertTrue((-1...1).contains(suggestion.color.exposure))
    }

    func testWarmCastIsNeutralizedTowardCool() throws {
        // 단색은 노출만 조정하므로(스펙 5절) 분산이 있는 따뜻한 그라데이션으로 캐스트를 만든다.
        let warm = CIFilter(
            name: "CILinearGradient",
            parameters: [
                "inputPoint0": CIVector(x: 0, y: 0),
                "inputPoint1": CIVector(x: 64, y: 0),
                "inputColor0": CIColor(red: 0.5, green: 0.35, blue: 0.2),
                "inputColor1": CIColor(red: 0.9, green: 0.7, blue: 0.5),
            ])!
            .outputImage!.cropped(to: CGRect(x: 0, y: 0, width: 64, height: 64))
        let suggestion = try enhancer.suggestion(for: warm, hasFaces: false)
        XCTAssertLessThan(suggestion.color.warmth, 0, "붉은 캐스트는 차갑게 보정")
        XCTAssertGreaterThanOrEqual(suggestion.color.warmth, -RenderTuning().autoWarmthLimit)
    }

    func testFacesAddPortraitValues() throws {
        let image = Support.gradient()
        XCTAssertEqual(try enhancer.suggestion(for: image, hasFaces: false).portrait, PortraitAdjustments())
        let withFaces = try enhancer.suggestion(for: image, hasFaces: true).portrait
        XCTAssertEqual(withFaces.skinSmoothing, RenderTuning().autoSkinSmoothing)
        XCTAssertEqual(withFaces.faceSlim, RenderTuning().autoFaceSlim)
        XCTAssertNil(withFaces.targetFace)
    }

    func testSuggestionDoesNotDependOnCurrentRecipe() throws {
        let image = Support.gradient()
        let first = try enhancer.suggestion(for: image, hasFaces: true)
        let second = try enhancer.suggestion(for: image, hasFaces: true)
        XCTAssertEqual(first, second)
    }
}
