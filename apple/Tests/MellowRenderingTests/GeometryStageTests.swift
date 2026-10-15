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

    // MARK: - 픽셀 내용: GeometryTransform과 같은 규약인지 고정한다.

    private struct Pixels {
        let data: [UInt8]
        let width: Int
        let height: Int
        let bytesPerRow: Int

        init(_ image: CIImage) throws {
            let cg = try RenderingTestSupport.renderer.makeCGImage(image)
            data = Array(cg.dataProvider!.data! as Data)
            width = cg.width
            height = cg.height
            bytesPerRow = cg.bytesPerRow
        }

        /// CGImage 메모리는 위 행부터라 `rowFromTop` 0이 Core Image y-up 좌표의 맨 위다.
        func red(column: Int, rowFromTop: Int) -> Int {
            Int(data[rowFromTop * bytesPerRow + column * 4])
        }

        /// 픽셀 중심의 y-up 정규화 좌표.
        func normalizedCenter(column: Int, rowFromTop: Int) -> NormalizedPoint {
            NormalizedPoint(
                x: (Double(column) + 0.5) / Double(width), y: 1 - (Double(rowFromTop) + 0.5) / Double(height))
        }
    }

    /// 가로 그라데이션은 x에만 의존한다. 원본 첫 행에서 정규화 x의 R 값을 선형 보간한다.
    private static func gradientRed(atNormalizedX x: Double, in source: Pixels) -> Double {
        let position = x * Double(source.width) - 0.5
        let left = max(0, min(source.width - 1, Int(position.rounded(.down))))
        let right = min(source.width - 1, left + 1)
        let fraction = max(0, min(1, position - Double(left)))
        let leftRed = Double(source.red(column: left, rowFromTop: 0))
        let rightRed = Double(source.red(column: right, rowFromTop: 0))
        return leftRed + (rightRed - leftRed) * fraction
    }

    func testClockwiseTurnPutsLeftEdgeAtTop() throws {
        let input = Support.gradient()
        let source = try Pixels(input)
        let geometry = GeometryAdjustments(quarterTurns: 1)
        let output = try Pixels(render(geometry, input: input))
        // GeometryTransform의 시계 방향 90°는 y-up 정규화 좌표에서 (x, y) → (y, 1 − x)다.
        // 원본 왼쪽 끝(x = 0, 어두움)은 y = 1, 즉 출력 맨 위로 간다. 오른쪽 끝(밝음)은 맨 아래로 간다.
        let top = output.red(column: 0, rowFromTop: 0)
        let bottom = output.red(column: 0, rowFromTop: output.height - 1)
        XCTAssertLessThan(top, bottom, "왼쪽(어두운) 끝이 위로 와야 한다")
        let transform = GeometryTransform(geometry: geometry, sourceAspect: 128.0 / 80.0)
        for row in [0, output.height - 1] {
            let original = transform.toOriginal(output.normalizedCenter(column: 0, rowFromTop: row))
            let expected = Self.gradientRed(atNormalizedX: original.x, in: source)
            XCTAssertEqual(Double(output.red(column: 0, rowFromTop: row)), expected, accuracy: 2)
        }
        XCTAssertEqual(top, source.red(column: 0, rowFromTop: 0), accuracy: 2)
        XCTAssertEqual(bottom, source.red(column: source.width - 1, rowFromTop: 0), accuracy: 2)
    }

    func testStraightenSignMatchesTransform() throws {
        let input = Support.gradient()
        let source = try Pixels(input)
        var samples: [Double: Int] = [:]
        for degrees in [10.0, -10.0] {
            let geometry = GeometryAdjustments(straightenDegrees: degrees)
            let output = try Pixels(render(geometry, input: input))
            let transform = GeometryTransform(geometry: geometry, sourceAspect: 128.0 / 80.0)
            for (column, row) in [(0, 0), (0, output.height - 1), (output.width - 1, 0)] {
                let original = transform.toOriginal(output.normalizedCenter(column: column, rowFromTop: row))
                let expected = Self.gradientRed(atNormalizedX: original.x, in: source)
                let actual = output.red(column: column, rowFromTop: row)
                XCTAssertEqual(Double(actual), expected, accuracy: 3, "\(degrees)° (\(column), \(row))")
            }
            samples[degrees] = output.red(column: 0, rowFromTop: 0)
        }
        // +10°(시계 방향)에서 출력 왼쪽 위는 원본 x ≈ 0.07, −10°에서는 x ≈ 0.16을 본다. 왼쪽이 어두우니 +10°가 더 어둡다.
        XCTAssertLessThan(try XCTUnwrap(samples[10]), try XCTUnwrap(samples[-10]))
    }

    func testCropOffsetSamplesRightQuarter() throws {
        let input = Support.gradient()
        let source = try Pixels(input)
        let crop = NormalizedRect(x: 0.75, y: 0, width: 0.25, height: 1)
        let output = try Pixels(render(GeometryAdjustments(crop: crop), input: input))
        XCTAssertEqual(output.width, 32)
        // 출력 첫 열은 원본 x = 96 열이다.
        XCTAssertEqual(output.red(column: 0, rowFromTop: 0), source.red(column: 96, rowFromTop: 0), accuracy: 2)
        XCTAssertGreaterThan(output.red(column: 0, rowFromTop: 0), source.red(column: 0, rowFromTop: 0) + 50)
    }
}
