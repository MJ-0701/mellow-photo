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

    func testBlownAndCrushedRegionsGetHighlightAndShadowRecovery() throws {
        // 128×80 중간 회색 그라데이션 위에 왼쪽 16열을 검정, 오른쪽 16열을 흰색으로 덮는다(각 12.5%).
        // 구간 중심은 1/64 간격이라 0.97 이상은 62번 구간 이상, 0.03 이하는 1번 구간 이하다.
        // 검정은 0번 구간(중심 0.0078), 흰색은 63번 구간(중심 0.9922)에 들어가 L₁·L₉₉가 그 구간 중심이 된다.
        let width = 128
        let height = 80
        let band = 16
        let darkGray = CIColor(red: 0.2, green: 0.2, blue: 0.2)
        let lightGray = CIColor(red: 0.8, green: 0.8, blue: 0.8)
        let middle = gradient(from: darkGray, to: lightGray)
        let black = CIImage(color: CIColor(red: 0, green: 0, blue: 0))
            .cropped(to: CGRect(x: 0, y: 0, width: band, height: height))
        let white = CIImage(color: CIColor(red: 1, green: 1, blue: 1))
            .cropped(to: CGRect(x: width - band, y: 0, width: band, height: height))
        let image = white.composited(over: black.composited(over: middle))
        let suggestion = try enhancer.suggestion(for: image, hasFaces: false)
        XCTAssertLessThan(suggestion.detail.highlights, 0)
        XCTAssertGreaterThanOrEqual(suggestion.detail.highlights, -1)
        XCTAssertGreaterThan(suggestion.detail.shadows, 0)
        XCTAssertLessThanOrEqual(suggestion.detail.shadows, 1)
        XCTAssertEqual(suggestion.color.saturation, RenderTuning().autoSaturation)
        XCTAssertEqual(suggestion.color.contrast, RenderTuning().autoContrast)
        XCTAssertTrue((-1...1).contains(suggestion.color.exposure))
    }

    func testExposureIsClampedToLimit() throws {
        let limit = RenderTuning().autoExposureLimit
        let nearBlack = Support.solid(CIColor(red: 0.02, green: 0.02, blue: 0.02), size: 64)
        let nearWhite = Support.solid(CIColor(red: 0.98, green: 0.98, blue: 0.98), size: 64)
        XCTAssertEqual(try enhancer.suggestion(for: nearBlack, hasFaces: false).color.exposure, limit)
        XCTAssertEqual(try enhancer.suggestion(for: nearWhite, hasFaces: false).color.exposure, -limit)
    }

    func testWarmCastIsNeutralizedTowardCool() throws {
        // 단색은 노출만 조정하므로(스펙 5절) 분산이 있는 따뜻한 그라데이션으로 캐스트를 만든다.
        // 캐스트가 약해 클램프 전 값이 그대로 나온다.
        let start = CIColor(red: 0.6, green: 0.5, blue: 0.45)
        let end = CIColor(red: 0.9, green: 0.8, blue: 0.75)
        let warm = gradient(from: start, to: end)
        let suggestion = try enhancer.suggestion(for: warm, hasFaces: false)
        XCTAssertLessThan(suggestion.color.warmth, 0, "붉은 캐스트는 차갑게 보정")
        XCTAssertGreaterThan(suggestion.color.warmth, -RenderTuning().autoWarmthLimit)
    }

    func testStrongWarmCastIsClampedToWarmthLimit() throws {
        let warm = gradient(from: CIColor(red: 0.6, green: 0.2, blue: 0.05), to: CIColor(red: 1, green: 0.5, blue: 0.1))
        let suggestion = try enhancer.suggestion(for: warm, hasFaces: false)
        XCTAssertEqual(suggestion.color.warmth, -RenderTuning().autoWarmthLimit)
    }

    func testCoolCastIsNeutralizedTowardWarm() throws {
        let start = CIColor(red: 0.1, green: 0.3, blue: 0.5)
        let end = CIColor(red: 0.4, green: 0.6, blue: 0.9)
        let cool = gradient(from: start, to: end)
        let suggestion = try enhancer.suggestion(for: cool, hasFaces: false)
        XCTAssertGreaterThan(suggestion.color.warmth, 0, "푸른 캐스트는 따뜻하게 보정")
        XCTAssertLessThanOrEqual(suggestion.color.warmth, RenderTuning().autoWarmthLimit)
    }

    /// 128×80 가로 그라데이션. 단색과 달리 분산이 있어 노출 외 보정도 받는다.
    private func gradient(from start: CIColor, to end: CIColor) -> CIImage {
        CIFilter(
            name: "CILinearGradient",
            parameters: [
                "inputPoint0": CIVector(x: 0, y: 0),
                "inputPoint1": CIVector(x: 128, y: 0),
                "inputColor0": start,
                "inputColor1": end,
            ])!
            .outputImage!.cropped(to: CGRect(x: 0, y: 0, width: 128, height: 80))
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
