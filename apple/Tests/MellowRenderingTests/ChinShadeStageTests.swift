import CoreImage
import MellowShared
import XCTest

@testable import MellowRendering

final class ChinShadeStageTests: XCTestCase {
    typealias Support = RenderingTestSupport

    private let extent = SyntheticFace.extent
    private let tuning = RenderTuning()
    /// 합성 얼굴을 반으로 줄여 턱밑 띠와 그 아래가 사진 안에 들도록 올린 얼굴.
    private let face = SyntheticFace.make().face.transformed(scale: 0.5, offset: NormalizedPoint(x: 0.25, y: 0.45))
    /// 피부색(sRGB 감마)과 그보다 휘도가 40/255 낮은 그늘색. 세 채널에 같은 값을 빼 Cb·Cr이 같다.
    private static let skin: [CGFloat] = [0.80, 0.62, 0.52]
    private static let shadeDrop: CGFloat = 40 / 255
    /// 띠 안에 칠하는 수염 흉내 색. 볼과 Cb·Cr이 멀다.
    private static let beard = CIColor(red: 0.3, green: 0.3, blue: 0.3)
    /// 1바이트(sRGB 감마).
    private static let byte: Double = 1

    private var faceWidth: CGFloat { FaceRegions.faceWidth(face, extent: extent) }

    /// 얼굴의 가장 낮은 윤곽점(턱 끝).
    private func chinTip(of face: FaceGeometry) throws -> CGPoint {
        let contour = try XCTUnwrap(FaceRegions.landmarkPolygon(face, .faceContour, extent))
        return try XCTUnwrap(contour.min { $0.y < $1.y })
    }

    private func color(_ components: [CGFloat], minus drop: CGFloat = 0) -> CIColor {
        CIColor(red: components[0] - drop, green: components[1] - drop, blue: components[2] - drop)
    }

    /// 피부색 단색 위에 얼굴마다 턱밑 띠를 그늘색으로 칠하고 extras를 얹은 비트맵 입력.
    /// 비트맵에서 읽어야 마스크 밖 바이트를 입력과 비교할 수 있다.
    private func shadedImage(faces: [FaceGeometry], extras: [(CIColor, CGRect)] = []) throws -> CIImage {
        var image = CIImage(color: color(Self.skin)).cropped(to: extent)
        let shade = CIImage(color: color(Self.skin, minus: Self.shadeDrop))
        for face in faces {
            let polygon = try XCTUnwrap(FaceRegions.chinBandPolygon(face: face, extent: extent))
            let mask = FaceRegions.polygonMask(fill: [polygon], cut: [], cutWidth: 0, extent: extent, tuning: tuning)
            image = MaskBuilder.blend(shade, over: image, mask: mask).cropped(to: extent)
        }
        for (paint, rect) in extras {
            image = CIImage(color: paint).cropped(to: rect).composited(over: image)
        }
        return CIImage(cgImage: try Support.renderer.makeCGImage(image))
    }

    private func context(doubleChin: Double, faces: [FaceGeometry], onlyFace: Int? = nil) -> RenderContext {
        var recipe = EditRecipe()
        if let onlyFace {
            recipe.people.individuals = [
                PersonRecord(
                    anchor: PersonAnchor(faceBox: faces[onlyFace].boundingBox),
                    layer: PortraitLayer(face: [.doubleChin: doubleChin]))
            ]
        } else {
            recipe.portrait.face.doubleChin = doubleChin
        }
        return RenderContext(extent: extent, recipe: recipe, faces: faces, tuning: tuning)
    }

    /// 감마 BT.601 휘도(바이트).
    private func luma(_ grid: PixelGrid, _ point: CGPoint) -> Double {
        let pixel = grid.rgba(point)
        return 0.299 * Double(pixel[0]) + 0.587 * Double(pixel[1]) + 0.114 * Double(pixel[2])
    }

    private func meanLuma(_ grid: PixelGrid, _ points: [CGPoint]) -> Double {
        points.map { luma(grid, $0) }.reduce(0, +) / Double(points.count)
    }

    /// 턱 끝 아래 띠 가운데 높이(윤곽에서 얼굴 폭 × 0.115 아래)의 점들.
    private func bandPoints(below tip: CGPoint) -> [CGPoint] {
        let y = tip.y - faceWidth * 0.115
        return stride(from: CGFloat(-20), through: 20, by: 5).map { CGPoint(x: tip.x + $0, y: y) }
    }

    /// rows 행·columns 열 범위에서 두 격자가 다른 픽셀 수.
    private func changedPixels(
        _ before: PixelGrid, _ after: PixelGrid, rows: ClosedRange<Int>, columns: ClosedRange<Int>
    )
        -> Int
    {
        var changed = 0
        for y in rows {
            for x in columns where before.rgba(CGPoint(x: x, y: y)) != after.rgba(CGPoint(x: x, y: y)) {
                changed += 1
            }
        }
        return changed
    }

    func testZeroDoubleChinReturnsInputUnchanged() throws {
        let input = try shadedImage(faces: [face])
        let output = try ChinShadeStage().apply(input, in: context(doubleChin: 0, faces: [face]))
        XCTAssertEqual(try Support.bytes(output), try Support.bytes(input))
        XCTAssertEqual(ChinShadeStage().name, "chinShade")
    }

    func testLiftsTheShadowBandUnderTheChin() throws {
        let input = try shadedImage(faces: [face])
        let tip = try chinTip(of: face)
        let band = bandPoints(below: tip)
        let surround = band.map { CGPoint(x: $0.x, y: tip.y - faceWidth * 0.32) }
        let before = try Support.grid(input)
        let after = try Support.grid(ChinShadeStage().apply(input, in: context(doubleChin: 1, faces: [face])))
        let lift = meanLuma(after, band) - meanLuma(before, band)
        XCTAssertGreaterThan(lift, 6, "띠 안이 밝아진다")
        XCTAssertLessThanOrEqual(lift, 12 + Self.byte / 2, "증가는 chinShadeMaxLift(12/255)에서 자른다")
        let gapBefore = meanLuma(before, surround) - meanLuma(before, band)
        let gapAfter = meanLuma(after, surround) - meanLuma(after, band)
        XCTAssertGreaterThan(gapBefore, 35)
        XCTAssertLessThan(gapAfter, gapBefore - 6, "띠와 주변의 휘도 차가 준다")
    }

    func testNeverDarkens() throws {
        let tip = try chinTip(of: face)
        let y = tip.y - faceWidth * 0.115
        let bright = CGRect(x: tip.x + 4, y: y - 4, width: 10, height: 8)
        let input = try shadedImage(faces: [face], extras: [(color(Self.skin, minus: -Self.shadeDrop), bright)])
        let before = try Support.grid(input)
        let after = try Support.grid(ChinShadeStage().apply(input, in: context(doubleChin: 1, faces: [face])))
        var darker = 0
        for row in 0..<before.height {
            for column in 0..<before.width {
                let point = CGPoint(x: column, y: row)
                if zip(after.rgba(point), before.rgba(point)).contains(where: { $0 < $1 }) {
                    darker += 1
                }
            }
        }
        XCTAssertEqual(darker, 0, "어떤 픽셀도 어두워지지 않는다")
        XCTAssertGreaterThan(meanLuma(after, bandPoints(below: tip)), meanLuma(before, bandPoints(below: tip)))
    }

    func testOutsideTheBandIsUntouched() throws {
        let input = try shadedImage(faces: [face])
        let tip = try chinTip(of: face)
        let before = try Support.grid(input)
        let after = try Support.grid(ChinShadeStage().apply(input, in: context(doubleChin: 1, faces: [face])))
        let columns = 0...(before.width - 1)
        // 띠 위끝은 윤곽에서 0.03 아래이고 흐림 여백(feather 4배)을 더해도 윤곽 위 얼굴 폭 × 0.16 너머에는 닿지 않는다.
        let aboveJaw = Int((tip.y + faceWidth * 0.16).rounded(.up))...(before.height - 1)
        XCTAssertEqual(changedPixels(before, after, rows: aboveJaw, columns: columns), 0, "턱선 위(입·볼)는 같은 바이트")
        let belowBand = 0...Int((tip.y - faceWidth * (0.20 + 0.25)).rounded(.down))
        XCTAssertEqual(
            changedPixels(before, after, rows: belowBand, columns: columns), 0, "띠 아래 얼굴 폭 × 0.25 너머는 같은 바이트")
        XCTAssertGreaterThan(meanLuma(after, bandPoints(below: tip)), meanLuma(before, bandPoints(below: tip)))
    }

    func testNonSkinColorIsNotLifted() throws {
        let tip = try chinTip(of: face)
        let y = tip.y - faceWidth * 0.115
        let patch = CGRect(x: tip.x - 15, y: y - 6, width: 30, height: 12)
        let input = try shadedImage(faces: [face], extras: [(Self.beard, patch)])
        let before = try Support.grid(input)
        let after = try Support.grid(ChinShadeStage().apply(input, in: context(doubleChin: 1, faces: [face])))
        let inside = stride(from: patch.minX + 3, through: patch.maxX - 3, by: 4).flatMap { x in
            [CGPoint(x: x, y: patch.midY - 3), CGPoint(x: x, y: patch.midY), CGPoint(x: x, y: patch.midY + 3)]
        }
        XCTAssertLessThanOrEqual(meanLuma(after, inside) - meanLuma(before, inside), Self.byte, "수염 색은 밝히지 않는다")
        for point in inside {
            XCTAssertLessThanOrEqual(luma(after, point) - luma(before, point), Self.byte, "\(point)")
        }
        let skinBand = [CGPoint(x: tip.x - 30, y: y), CGPoint(x: tip.x + 30, y: y)]
        XCTAssertGreaterThan(meanLuma(after, skinBand) - meanLuma(before, skinBand), 4, "옆 피부 그늘은 밝아진다")
    }

    func testOnlyTheTargetFace() throws {
        let base = SyntheticFace.make().face
        let faces = [
            base.transformed(scale: 0.4, offset: NormalizedPoint(x: 0.02, y: 0.45)),
            base.transformed(scale: 0.4, offset: NormalizedPoint(x: 0.55, y: 0.45)),
        ]
        let input = try shadedImage(faces: faces)
        let before = try Support.grid(input)
        let after = try Support.grid(
            ChinShadeStage().apply(input, in: context(doubleChin: 1, faces: faces, onlyFace: 0)))
        let otherBox = FaceRegions.pixelRect(faces[1].boundingBox, in: extent)
        let columns = Int(otherBox.minX)...Int(otherBox.maxX)
        XCTAssertEqual(
            changedPixels(before, after, rows: 0...(before.height - 1), columns: columns), 0, "다른 얼굴의 턱밑은 같은 바이트")
        let tip = try chinTip(of: faces[0])
        let width = FaceRegions.faceWidth(faces[0], extent: extent)
        let band = [CGPoint(x: tip.x, y: tip.y - width * 0.115)]
        XCTAssertGreaterThan(meanLuma(after, band) - meanLuma(before, band), 4, "고른 얼굴은 밝아진다")
    }
}
