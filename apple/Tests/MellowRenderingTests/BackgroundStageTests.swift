import CoreImage
import MellowShared
import XCTest

@testable import MellowRendering

final class BackgroundStageTests: XCTestCase {
    typealias Support = RenderingTestSupport

    /// 가로로 긴 사진(256×192)과 정사각형 마스크(64×64). 마스크를 가로 4배·세로 3배로 키워야 맞는다.
    private let extent = CGRect(x: 0, y: 0, width: 256, height: 192)
    /// 마스크 안 사람 사각형(x 24…40, y 16…48) → 사진에서 x 96…160, y 48…144.
    private let mask = RenderingTestSupport.personMask(
        size: CGSize(width: 64, height: 64), person: CGRect(x: 24, y: 16, width: 16, height: 32))

    /// 4px 폭 세로 줄무늬. 흐리면 바뀌고 그대로면 같은 바이트다.
    private func stripes() -> CIImage {
        CIFilter(name: "CIStripesGenerator", parameters: ["inputWidth": 4, "inputSharpness": 1])!.outputImage!
            .cropped(to: extent)
    }

    private func render(_ image: CIImage, blur: Double, personMask: CIImage?) throws -> CIImage {
        var recipe = EditRecipe()
        recipe.background.blur = blur
        let context = RenderContext(
            extent: extent, recipe: recipe, analysis: PhotoAnalysis(personMask: personMask), tuning: RenderTuning())
        return try BackgroundStage().apply(image, in: context)
    }

    func testNoMaskOrZeroBlurReturnsInputBytes() throws {
        let input = stripes()
        XCTAssertEqual(
            try Support.bytes(render(input, blur: 0.5, personMask: nil)), try Support.bytes(input),
            "사람이 없거나 분석이 실패하면 건너뛴다")
        XCTAssertEqual(try Support.bytes(render(input, blur: 0, personMask: mask)), try Support.bytes(input))
    }

    func testBlurChangesBackgroundAndKeepsPersonCoreBytes() throws {
        let input = stripes()
        let before = try Support.grid(input)
        let after = try Support.grid(render(input, blur: 1, personMask: mask))
        for y in stride(from: 64, to: 128, by: 4) {
            for x in stride(from: 112, to: 144, by: 2) {
                let point = CGPoint(x: x, y: y)
                XCTAssertEqual(after.rgba(point), before.rgba(point), "사람 안쪽 \(point)")
            }
        }
        XCTAssertNotEqual(after.rgba(CGPoint(x: 20, y: 20)), before.rgba(CGPoint(x: 20, y: 20)), "배경은 흐려진다")
    }

    func testMaskStretchesSeparatelyAlongEachAxis() throws {
        let input = stripes()
        let before = try Support.grid(input)
        let after = try Support.grid(render(input, blur: 1, personMask: mask))
        // 세로 배율이 3이 아니라 4였다면 사람은 y 64…192가 되어 아래 판정이 뒤바뀐다.
        for point in [CGPoint(x: 128, y: 56), CGPoint(x: 128, y: 136)] {
            XCTAssertEqual(after.rgba(point), before.rgba(point), "사람 안 \(point)")
        }
        XCTAssertNotEqual(after.rgba(CGPoint(x: 129, y: 168)), before.rgba(CGPoint(x: 129, y: 168)), "사람 위 배경")
    }

    func testBlurKeepsOpaqueUntintedEdges() throws {
        let input = CIImage(color: CIColor(red: 0.6, green: 0.5, blue: 0.4)).cropped(to: extent)
        let before = try Support.grid(input)
        let after = try Support.grid(render(input, blur: 1, personMask: mask))
        for point in [CGPoint(x: 0, y: 0), CGPoint(x: 255, y: 191), CGPoint(x: 0, y: 191), CGPoint(x: 128, y: 0)] {
            let expected = before.rgba(point)
            let actual = after.rgba(point)
            XCTAssertEqual(actual[3], 255, "가장자리가 투명해지지 않는다 \(point)")
            for channel in 0..<3 {
                XCTAssertEqual(Int(actual[channel]), Int(expected[channel]), accuracy: 1, "가장자리가 어두워지지 않는다 \(point)")
            }
        }
    }

    func testOutOfRangeBlurRendersLikeClampedValue() throws {
        let input = stripes()
        XCTAssertEqual(
            try Support.bytes(render(input, blur: 4, personMask: mask)),
            try Support.bytes(render(input, blur: 1, personMask: mask)))
        XCTAssertEqual(try Support.bytes(render(input, blur: -1, personMask: mask)), try Support.bytes(input), "음수는 0")
    }

    /// 세로 사진(600×900)에 Vision처럼 가로 4:3 마스크(64×48). 가로 9.375배·세로 18.75배로 따로 키워야 맞는다.
    /// 마스크 안 사람(x 24…40, y 12…36) → 사진에서 x 225…375, y 225…675.
    /// 한 배율로 키우거나(가로 배율이면 y 112…338, 세로 배율이면 x 450…750) 비율을 지켜 가운데 맞추면(y 338…563)
    /// 아래 사람 안쪽 두 점 중 하나가 배경으로 흐려진다.
    func testPortraitImageStretchesLandscapeMaskOntoPersonArea() throws {
        let portrait = CGRect(x: 0, y: 0, width: 600, height: 900)
        let landscapeMask = RenderingTestSupport.personMask(
            size: CGSize(width: 64, height: 48), person: CGRect(x: 24, y: 12, width: 16, height: 24))
        let input = CIFilter(name: "CIStripesGenerator", parameters: ["inputWidth": 4, "inputSharpness": 1])!
            .outputImage!.cropped(to: portrait)
        var recipe = EditRecipe()
        recipe.background.blur = 1
        let analysis = PhotoAnalysis(personMask: landscapeMask)
        let context = RenderContext(extent: portrait, recipe: recipe, analysis: analysis, tuning: RenderTuning())
        let output = try BackgroundStage().apply(input, in: context)
        XCTAssertEqual(output.extent, portrait, "extent를 그대로 둔다")
        let before = try Support.grid(input)
        let after = try Support.grid(output)
        let personPoints = [
            CGPoint(x: 300, y: 300), CGPoint(x: 300, y: 600), CGPoint(x: 240, y: 450), CGPoint(x: 360, y: 450),
        ]
        for point in personPoints {
            XCTAssertEqual(after.rgba(point), before.rgba(point), "사람 안 \(point)")
        }
        let backgroundPoints = [
            CGPoint(x: 300, y: 800), CGPoint(x: 300, y: 100), CGPoint(x: 100, y: 450), CGPoint(x: 500, y: 450),
        ]
        for point in backgroundPoints {
            XCTAssertNotEqual(after.rgba(point), before.rgba(point), "사람 밖 배경 \(point)")
        }
    }
}
