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

    /// 반 크기 합성 얼굴 둘을 좌우에 놓는다. 왼쪽 사람의 개인 층은 왼쪽 얼굴만, 짝이 없는 기록은 아무 얼굴도 칠하지 않는다.
    /// 다섯 부위(립·블러셔·아이섀도·눈썹·쉐딩)를 모두 강도 1로 켠다.
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
                eyeshadow: MakeupTint(colorID: "shadow-smoky", intensity: 1), brow: MakeupStrength(intensity: 1),
                contour: MakeupStrength(intensity: 1))
            recipe = Support.restricted(recipe, toFace: targetFace, of: faces)
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

    func testBrowDarkensBrowsOnly() throws {
        let synthetic = SyntheticFace.makeFeatures()
        let before = try Support.grid(synthetic.image)
        let after = try Support.grid(output(synthetic, MakeupAdjustments(brow: MakeupStrength(intensity: 1))))
        XCTAssertLessThanOrEqual(
            brightness(after.rgba(SyntheticFace.leftBrowCenter)),
            brightness(before.rgba(SyntheticFace.leftBrowCenter)) - 10, "눈썹이 진해진다")
        XCTAssertLessThan(
            brightness(after.rgba(SyntheticFace.aboveLeftBrow)), brightness(before.rgba(SyntheticFace.aboveLeftBrow)),
            "눈썹 바로 위가 눈썹 색으로 채워진다")
        for point in [SyntheticFace.cheek, SyntheticFace.scleraPoint, SyntheticFace.lipPoint, SyntheticFace.mouth] {
            XCTAssertEqual(after.rgba(point), before.rgba(point), "눈썹 밖 \(point)")
        }
    }

    func testContourDarkensHollowsAndBrightensForehead() throws {
        let synthetic = SyntheticFace.makeFeatures()
        let before = try Support.grid(synthetic.image)
        let after = try Support.grid(output(synthetic, MakeupAdjustments(contour: MakeupStrength(intensity: 1))))
        XCTAssertLessThanOrEqual(
            brightness(after.rgba(SyntheticFace.leftHollow)), brightness(before.rgba(SyntheticFace.leftHollow)) - 6,
            "광대 아래가 어두워진다")
        XCTAssertGreaterThanOrEqual(
            brightness(after.rgba(SyntheticFace.foreheadCenter)),
            brightness(before.rgba(SyntheticFace.foreheadCenter)) + 6, "이마 가운데가 밝아진다")
        for point in [SyntheticFace.outside, SyntheticFace.scleraPoint, SyntheticFace.lipPoint] {
            XCTAssertEqual(after.rgba(point), before.rgba(point), "쉐딩·하이라이터 밖 \(point)")
        }
    }

    /// 눈썹·쉐딩 강도 0은 그 단계를 건너뛴다. 모르는 립 색으로 단계 반복까지는 들어가게 한다.
    func testZeroBrowAndContourIntensityReturnInputBytes() throws {
        let synthetic = SyntheticFace.makeFeatures()
        let makeup = MakeupAdjustments(
            lip: MakeupTint(colorID: "nope", intensity: 1), brow: MakeupStrength(intensity: 0),
            contour: MakeupStrength(intensity: 0))
        XCTAssertEqual(try Support.bytes(output(synthetic, makeup)), try Support.bytes(synthetic.image))
    }

    /// BT.601 휘도(바이트).
    private func luma(_ pixel: [UInt8]) -> Double {
        0.299 * Double(pixel[0]) + 0.587 * Double(pixel[1]) + 0.114 * Double(pixel[2])
    }

    /// 고른 중간 톤 피부에서 쉐딩은 휘도를 낮추고 하이라이터는 높이며 색상각은 거의 그대로다(감마 공간 섞기).
    /// 측정값: 광대 아래 휘도 156 → 138, 이마 156 → 190, 색상각 변화는 둘 다 0.3° 아래.
    func testContourMovesMidToneSkinLuminanceWithoutHueShift() throws {
        let minimumLumaChange = 10.0
        let maximumHueShift = 2.0
        let skin = CIColor(red: 0.76, green: 0.57, blue: 0.45)
        let synthetic = SyntheticFace(
            image: Support.solid(skin, size: SyntheticFace.size), face: SyntheticFace.make().face)
        let before = try Support.grid(synthetic.image)
        let after = try Support.grid(output(synthetic, MakeupAdjustments(contour: MakeupStrength(intensity: 1))))
        let hollowBefore = before.rgba(SyntheticFace.leftHollow)
        let hollowAfter = after.rgba(SyntheticFace.leftHollow)
        XCTAssertLessThanOrEqual(luma(hollowAfter), luma(hollowBefore) - minimumLumaChange, "쉐딩은 어둡게")
        XCTAssertLessThanOrEqual(hueDistance(hue(hollowAfter), hue(hollowBefore)), maximumHueShift, "쉐딩 색상각")
        let foreheadBefore = before.rgba(SyntheticFace.foreheadCenter)
        let foreheadAfter = after.rgba(SyntheticFace.foreheadCenter)
        XCTAssertGreaterThanOrEqual(luma(foreheadAfter), luma(foreheadBefore) + minimumLumaChange, "하이라이터는 밝게")
        XCTAssertLessThanOrEqual(
            hueDistance(hue(foreheadAfter), hue(foreheadBefore)), maximumHueShift, "하이라이터 색상각")
    }

    func testGenderGroupPaintsOnlyFacesOfThatGender() throws {
        let pair = try SyntheticFace.pair(SyntheticFace.makeFeatures(), renderer: Support.renderer)
        let catalog = try Support.sharedMakeupCatalog()
        func rendered(genders: [Gender?]) throws -> CIImage {
            var recipe = EditRecipe()
            recipe.people.groups[.female] = PortraitLayer(makeup: [.lip: MakeupTint(colorID: "lip-red", intensity: 1)])
            recipe.people.individuals = zip(pair.faces, genders).compactMap { face, gender in
                gender.map { PersonRecord(anchor: PersonAnchor(faceBox: face.boundingBox), gender: $0) }
            }
            let context = RenderContext(
                extent: pair.image.extent, recipe: recipe, faces: pair.faces, tuning: RenderTuning(),
                makeupCatalog: catalog)
            return try MakeupStage().apply(pair.image, in: context)
        }
        let before = try Support.grid(pair.image)
        let rightOnly = Support.changedPixelsByHalf(before, try Support.grid(rendered(genders: [nil, .female])))
        XCTAssertEqual(rightOnly.left, 0, "미지정인 사람은 그룹 값을 받지 않는다")
        XCTAssertGreaterThan(rightOnly.right, 0)
        let both = Support.changedPixelsByHalf(before, try Support.grid(rendered(genders: [.female, .female])))
        XCTAssertGreaterThan(both.left, 0)
        XCTAssertGreaterThan(both.right, 0)
        let male = Support.changedPixelsByHalf(before, try Support.grid(rendered(genders: [.male, nil])))
        XCTAssertEqual(male.left + male.right, 0, "다른 그룹은 받지 않는다")
    }
}
