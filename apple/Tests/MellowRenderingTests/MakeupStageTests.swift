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

    func testBlushTintsCheeksOnly() throws {
        let synthetic = SyntheticFace.makeFeatures()
        let before = try Support.grid(synthetic.image)
        let after = try Support.grid(
            output(synthetic, MakeupAdjustments(blush: MakeupTint(colorID: "blush-pink", intensity: 1))))
        XCTAssertNotEqual(after.rgba(SyntheticFace.cheek), before.rgba(SyntheticFace.cheek), "볼 색이 바뀐다")
        let outside = [
            SyntheticFace.outside, SyntheticFace.mouth, SyntheticFace.lipPoint, SyntheticFace.scleraPoint,
            SyntheticFace.forehead,
        ]
        for point in outside {
            XCTAssertEqual(after.rgba(point), before.rgba(point), "블러셔 밖 \(point)")
        }
    }

    func testEyeshadowDarkensTheLidOnly() throws {
        let synthetic = SyntheticFace.makeFeatures()
        let before = try Support.grid(synthetic.image)
        let after = try Support.grid(
            output(synthetic, MakeupAdjustments(eyeshadow: MakeupTint(colorID: "shadow-smoky", intensity: 1))))
        XCTAssertLessThanOrEqual(
            brightness(after.rgba(SyntheticFace.lidSkin)), brightness(before.rgba(SyntheticFace.lidSkin)) - 15,
            "눈꺼풀이 어두워진다")
        for point in [SyntheticFace.scleraPoint, SyntheticFace.leftEye, SyntheticFace.cheek, SyntheticFace.lipPoint] {
            XCTAssertEqual(after.rgba(point), before.rgba(point), "아이섀도 밖 \(point)")
        }
    }

    /// 색상각(도, 0…360). 무채색이면 0.
    private func hue(_ pixel: [UInt8]) -> Double {
        let red = Double(pixel[0])
        let green = Double(pixel[1])
        let blue = Double(pixel[2])
        let top = max(red, green, blue)
        let range = top - min(red, green, blue)
        guard range > 0 else { return 0 }
        let sector: Double
        if top == red {
            sector = (green - blue) / range
        } else if top == green {
            sector = (blue - red) / range + 2
        } else {
            sector = (red - green) / range + 4
        }
        let degrees = sector * 60
        return degrees < 0 ? degrees + 360 : degrees
    }

    /// 두 색상각 사이의 원 위 거리(도).
    private func hueDistance(_ first: Double, _ second: Double) -> Double {
        let gap = abs(first - second).truncatingRemainder(dividingBy: 360)
        return min(gap, 360 - gap)
    }

    /// 밝은 색은 감마 공간에서 섞어야 소프트 라이트가 중간 밝기 채널을 어둡게 하지 않는다.
    /// 선형 공간에서 섞으면 누드(G 0.55)가 선형 0.26 < 0.5라 입술 G(0.28)를 크게 낮춘다.
    func testLightLipColorBlendsInGammaSpace() throws {
        let synthetic = SyntheticFace.makeFeatures()
        let before = try Support.grid(synthetic.image).rgba(SyntheticFace.lipPoint)
        let nude = MakeupAdjustments(lip: MakeupTint(colorID: "lip-nude", intensity: 1))
        let after = try Support.grid(output(synthetic, nude)).rgba(SyntheticFace.lipPoint)
        XCTAssertNotEqual(after, before, "입술 색이 바뀐다")
        XCTAssertGreaterThanOrEqual(Int(after[1]), Int(before[1]) - 2, "밝은 누드가 입술 G를 낮추지 않는다")
        let color = try XCTUnwrap(Support.sharedMakeupCatalog().color(id: "lip-nude", for: .lip))
        let target = hue(color.rgb.map { UInt8(($0 * 255).rounded()) })
        XCTAssertLessThan(hueDistance(hue(after), target), hueDistance(hue(before), target), "색상이 고른 색 쪽으로 간다")
        let zero = MakeupAdjustments(lip: MakeupTint(colorID: "lip-nude", intensity: 0))
        XCTAssertEqual(try Support.bytes(output(synthetic, zero)), try Support.bytes(synthetic.image), "강도 0은 그대로")
    }

    /// 강도 0.5의 결과는 채널마다 입력과 강도 1 결과 사이에 있다(바뀐 채널은 양 끝과 다르다).
    func testHalfIntensityLiesBetweenInputAndFull() throws {
        let synthetic = SyntheticFace.makeFeatures()
        let input = try Support.grid(synthetic.image)
        let cases: [(MakeupPart, String, CGPoint)] = [
            (.lip, "lip-red", SyntheticFace.lipPoint), (.blush, "blush-pink", SyntheticFace.leftBlush),
        ]
        for (part, colorID, point) in cases {
            func rendered(_ intensity: Double) throws -> [UInt8] {
                var makeup = MakeupAdjustments()
                makeup.setColorID(colorID, of: part)
                makeup.setIntensity(intensity, of: part)
                return try Support.grid(output(synthetic, makeup)).rgba(point)
            }
            let full = try rendered(1)
            let half = try rendered(0.5)
            let original = input.rgba(point)
            var changed = 0
            for channel in 0..<3 where abs(Int(full[channel]) - Int(original[channel])) >= 2 {
                changed += 1
                let low = min(full[channel], original[channel])
                let high = max(full[channel], original[channel])
                XCTAssertGreaterThan(half[channel], low, "\(part) 채널 \(channel)")
                XCTAssertLessThan(half[channel], high, "\(part) 채널 \(channel)")
            }
            XCTAssertGreaterThan(changed, 0, "\(part) 강도 1이 색을 바꾼다")
        }
    }

    /// 반 크기 합성 얼굴 둘을 좌우에 놓는다. targetFace 0은 왼쪽 얼굴만, 범위 밖 인덱스는 아무 얼굴도 칠하지 않는다.
    func testTargetFacePaintsOnlyThatFace() throws {
        let synthetic = SyntheticFace.makeFeatures()
        let half = CGAffineTransform(scaleX: 0.5, y: 0.5)
        let side = CGFloat(SyntheticFace.size)
        let left = synthetic.image.transformed(by: half.concatenating(CGAffineTransform(translationX: 0, y: side / 4)))
        let right = synthetic.image.transformed(
            by: half.concatenating(CGAffineTransform(translationX: side / 2, y: side / 4)))
        let composed = left.composited(over: right).composited(over: CIImage(color: .gray)).cropped(to: extent)
        let image = CIImage(cgImage: try Support.renderer.makeCGImage(composed))
        let faces = [
            synthetic.face.transformed(scale: 0.5, offset: NormalizedPoint(x: 0, y: 0.25)),
            synthetic.face.transformed(scale: 0.5, offset: NormalizedPoint(x: 0.5, y: 0.25)),
        ]
        let catalog = try Support.sharedMakeupCatalog()
        func rendered(targetFace: Int) throws -> CIImage {
            var recipe = EditRecipe()
            recipe.makeup = MakeupAdjustments(
                lip: MakeupTint(colorID: "lip-red", intensity: 1),
                blush: MakeupTint(colorID: "blush-pink", intensity: 1),
                eyeshadow: MakeupTint(colorID: "shadow-smoky", intensity: 1))
            recipe.portrait.targetFace = targetFace
            let context = RenderContext(
                extent: extent, recipe: recipe, faces: faces, tuning: RenderTuning(), makeupCatalog: catalog)
            return try MakeupStage().apply(image, in: context)
        }
        let before = try Support.grid(image)
        let after = try Support.grid(rendered(targetFace: 0))
        var leftChanged = 0
        var rightChanged = 0
        for y in 0..<SyntheticFace.size {
            for x in 0..<SyntheticFace.size {
                let point = CGPoint(x: x, y: y)
                guard after.rgba(point) != before.rgba(point) else { continue }
                if x < SyntheticFace.size / 2 {
                    leftChanged += 1
                } else {
                    rightChanged += 1
                }
            }
        }
        XCTAssertGreaterThan(leftChanged, 0, "고른 얼굴에 메이크업이 들어간다")
        XCTAssertEqual(rightChanged, 0, "다른 얼굴은 한 픽셀도 바뀌지 않는다")
        XCTAssertEqual(try Support.bytes(rendered(targetFace: 7)), try Support.bytes(image), "범위 밖 얼굴은 그대로")
    }
}
