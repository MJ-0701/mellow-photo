import CoreImage
import MellowShared
import XCTest

@testable import MellowRendering

final class GeometryStageTests: XCTestCase {
    typealias Support = RenderingTestSupport

    private func render(
        _ geometry: GeometryAdjustments, skipsCrop: Bool = false, input: CIImage = RenderingTestSupport.gradient()
    ) throws -> CIImage {
        var recipe = EditRecipe()
        recipe.geometry = geometry
        let context = RenderContext(
            extent: input.extent, recipe: recipe, faces: [], tuning: RenderTuning(), skipsCrop: skipsCrop)
        return try RenderPipeline.standard.render(input, context: context)
    }

    func testIdentityKeepsExtentAndBytes() throws {
        let input = Support.gradient()
        let result = try render(GeometryAdjustments(), input: input)
        XCTAssertEqual(result.extent, input.extent)
        XCTAssertEqual(try Support.bytes(result), try Support.bytes(input))
    }

    func testSquareCropOf128By80Is80By80AtOrigin() throws {
        let side = 80.0 / 128.0
        let crop = NormalizedRect(x: (1 - side) / 2, y: 0, width: side, height: 1)
        let result = try render(GeometryAdjustments(crop: crop))
        XCTAssertEqual(result.extent, CGRect(x: 0, y: 0, width: 80, height: 80))
    }

    func testQuarterTurnSwapsWidthAndHeight() throws {
        let result = try render(GeometryAdjustments(quarterTurns: 1))
        XCTAssertEqual(result.extent, CGRect(x: 0, y: 0, width: 80, height: 128))
        let threeTurns = try render(GeometryAdjustments(quarterTurns: 3))
        XCTAssertEqual(threeTurns.extent, CGRect(x: 0, y: 0, width: 80, height: 128))
        XCTAssertNotEqual(try Support.bytes(result), try Support.bytes(threeTurns), "1회와 3회 회전은 다른 방향")
    }

    func testFlipSwapsLeftAndRightColumns() throws {
        let input = Support.gradient()
        let original = try Support.bytes(input)
        let flipped = try Support.bytes(render(GeometryAdjustments(flipHorizontal: true), input: input))
        // 첫 행의 첫 픽셀 R과 마지막 픽셀 R이 서로 바뀐다.
        let lastPixel = (128 - 1) * 4
        XCTAssertEqual(Int(flipped[0]), Int(original[lastPixel]), accuracy: 2)
        XCTAssertEqual(Int(flipped[lastPixel]), Int(original[0]), accuracy: 2)
    }

    func testStraightenKeepsExtentAndLeavesNoTransparentCorner() throws {
        let gray = Support.solid(CIColor(red: 0.5, green: 0.5, blue: 0.5), size: 128)
        let result = try render(GeometryAdjustments(straightenDegrees: 5), input: gray)
        XCTAssertEqual(result.extent, gray.extent)
        let bytes = try Support.bytes(result)
        for cornerIndex in [0, (128 - 1) * 4, (128 * 127) * 4, (128 * 128 - 1) * 4] {
            XCTAssertEqual(bytes[cornerIndex + 3], 255, "모서리 알파가 불투명해야 한다")
        }
    }

    func testSkipsCropLeavesOnlyCropOut() throws {
        let crop = NormalizedRect(x: 0.25, y: 0.25, width: 0.5, height: 0.5)
        let geometry = GeometryAdjustments(flipHorizontal: true, quarterTurns: 1, crop: crop)
        let cropped = try render(geometry)
        let uncropped = try render(geometry, skipsCrop: true)
        XCTAssertEqual(uncropped.extent, CGRect(x: 0, y: 0, width: 80, height: 128))
        XCTAssertEqual(cropped.extent, CGRect(x: 0, y: 0, width: 40, height: 64))
    }

    func testGeometryOutputAspectMatchesTransform() throws {
        let crop = NormalizedRect(x: 0.1, y: 0.2, width: 0.6, height: 0.5)
        let geometry = GeometryAdjustments(quarterTurns: 1, straightenDegrees: 10, crop: crop)
        let result = try render(geometry)
        let transform = GeometryTransform(geometry: geometry, sourceAspect: 128.0 / 80.0)
        XCTAssertEqual(Double(result.extent.width / result.extent.height), transform.outputAspect, accuracy: 0.02)
    }
}
