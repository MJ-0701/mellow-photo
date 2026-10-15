import CoreImage
import MellowShared
import XCTest

@testable import MellowRendering

final class DetailStageTests: XCTestCase {
    typealias Support = RenderingTestSupport

    /// 한 줄(y=0)의 RGBA 바이트에서 R 채널의 최대·최소.
    /// CGImage 데이터 버퍼는 높이보다 긴 0 패딩을 가질 수 있어 첫 줄만 읽는다.
    private func redRange(_ image: CIImage) throws -> (min: UInt8, max: UInt8) {
        let bytes = try Support.bytes(image)
        let rowLength = Int(image.extent.width) * 4
        let reds = stride(from: 0, to: rowLength, by: 4).map { bytes[$0] }
        return (reds.min()!, reds.max()!)
    }

    func testDefaultDetailIsIdentity() throws {
        let input = Support.gradient()
        XCTAssertEqual(try Support.bytes(Support.render(input, recipe: EditRecipe())), try Support.bytes(input))
    }

    func testNegativeHighlightsLowerTheBrightestPixels() throws {
        let input = Support.gradient()
        var recipe = EditRecipe()
        recipe.detail.highlights = -1
        let result = try Support.render(input, recipe: recipe)
        XCTAssertEqual(result.extent, input.extent)
        XCTAssertLessThan(try redRange(result).max, try redRange(input).max)
    }

    func testPositiveShadowsRaiseTheDarkestPixels() throws {
        let input = Support.gradient()
        var recipe = EditRecipe()
        recipe.detail.shadows = 1
        XCTAssertGreaterThan(try redRange(Support.render(input, recipe: recipe)).min, try redRange(input).min)
    }

    func testVignetteDarkensCornersMoreThanCenter() throws {
        let gray = Support.solid(CIColor(red: 0.6, green: 0.6, blue: 0.6), size: 128)
        var recipe = EditRecipe()
        recipe.detail.vignette = 1
        let bytes = try Support.bytes(Support.render(gray, recipe: recipe))
        let corner = bytes[0]
        let centerIndex = (64 * 128 + 64) * 4
        XCTAssertLessThan(corner, bytes[centerIndex])
    }

    func testSharpnessChangesBytesOnGradient() throws {
        let input = Support.gradient()
        var recipe = EditRecipe()
        recipe.detail.sharpness = 1
        XCTAssertNotEqual(try Support.bytes(Support.render(input, recipe: recipe)), try Support.bytes(input))
    }
}
