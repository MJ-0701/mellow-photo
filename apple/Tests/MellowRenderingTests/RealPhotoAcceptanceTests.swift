import CoreImage
import MellowShared
import XCTest

@testable import MellowRendering

/// 실사진(실제 Vision) + 폰 화면 배율에서 "보이는 강도" 하한과 "자연스러움" 상한(스펙 G4 1.2·1.4).
/// 문턱을 못 넘으면 렌더 상수를 고친다.
/// 문턱을 바꾸는 것은 사용자 승인 뒤 VALIDATION에 적는다.
final class RealPhotoAcceptanceTests: XCTestCase {
    typealias Support = RenderingTestSupport

    /// 하한(보여야 함).
    /// 화면 배율 8비트.
    enum Visibility {
        static let smoothingChangedFraction = 0.04
        static let darkCirclesChangedFraction = 0.010
        static let darkCirclesMeanLift = 3.0
        static let nasolabialChangedFraction = 0.005
        static let foldRecovery = 0.5
        static let toneEveningChangedFraction = 0.04
        static let toneEveningMeanAbsolute = 3.0
        static let rednessClearRemoval = 0.5
        static let rednessFlushRedLift = 5.0
        static let shineReduction = 0.4
        static let bodyBrightnessChangedFraction = 0.15
        static let bodyToneRedMinusBlue = 6.0
        static let bodySmoothingChangedFraction = 0.10
        static let grainStandardDeviation = 5.0
        static let grainMinimumCell = 2.5
        static let glowChangedFraction = 0.40
        static let eyeMeanAbsolute = 3.0
        /// 입술 생기는 Cb·Cr만 바꾸고 휘도를 지키므로 휘도가 아니라 입술 마스크 가중 |ΔCr|(0…1)로 잰다(스펙 G4 1.2).
        static let lipChromaCr = 0.02
        static let blushMeanAbsolute = 3.0
        /// 합성 그늘 깊이·반점·반사광 크기.
        static let shadowDepth = 0.25
        /// 심은 반점이 실제로 붉어졌는지 보는 반점 안 |ΔCr| 하한(0…1).
        /// 심는 양은 약 0.05다.
        static let minimumPlantedBlotchCr = 0.02
        /// 심은 반사광이 실제로 밝아졌는지 보는 반사광 안 평균 ΔY 하한(8비트).
        static let minimumPlantedHighlightLift = 10.0
        static let blotchRadiusFraction: CGFloat = 0.04
        static let highlightRadiusFraction: CGFloat = 0.06
        static let highlightLift = 0.3
        static let highlightHeightFraction: CGFloat = 0.25
    }

    /// 상한(자연스러워야 함).
    enum Naturalness {
        static let foldMaximumMeanLift = 0.08 * 255
        static let foldMaximumChroma = 0.01
        static let fineVarianceRatioMinimum = 0.85
        static let toneEveningMaximumMeanLift = 0.03 * 255
        static let bodyBrightnessMaximumMeanLift = 0.10 * 255
        static let outsideFaceChangedFraction = 0.002
        /// "얼굴 밖"을 재기 전에 얼굴 다각형을 넓히는 폭.
        /// 얼굴 폭 비율(스펙 G4 1.4).
        static let outsideFaceDilationFraction: CGFloat = 0.05
        static let browChangedFraction = 0.05
    }

    /// 준비가 실패하면 이 테스트만 오류로 실패한다(묶음 전체가 멈추지 않는다).
    private func portrait() throws -> RealPortrait {
        try RealPortrait.shared.get()
    }
    private static var baseline: (image: CGImage, grid: PixelGrid)?

    private func base() throws -> (image: CGImage, grid: PixelGrid) {
        if let baseline = Self.baseline {
            return baseline
        }
        let image = try self.portrait().render(EditRecipe())
        let baseline = (image, try DisplayScale.grid(image))
        Self.baseline = baseline
        return baseline
    }

    private func grid(_ change: (inout EditRecipe) -> Void, stage: (any RenderStage)? = nil, input: CIImage? = nil)
        throws
        -> PixelGrid
    {
        var recipe = EditRecipe()
        change(&recipe)
        return try DisplayScale.grid(self.portrait().render(recipe, stage: stage, input: input))
    }

    private var faceRect: CGRect {
        get throws { DisplayScale.rect(try self.portrait().face.boundingBox, in: try base().grid) }
    }

    private func skinWeight() throws -> PixelGrid {
        let portrait = try self.portrait()
        return try DisplayScale.grid(portrait.skinMask().cropped(to: portrait.extent))
    }

    private func fineRadius() throws -> Double {
        let portrait = try self.portrait()
        return FrequencySeparation.radii(faceWidth: portrait.faceWidth, tuning: portrait.tuning).fine
    }

    /// 피부 마스크 가중 fine 분산 비(스펙 G4 1.4 "피부 마스크 안").
    /// 피부 마스크가 0이 아닐 수 있는 영역에서 잰다.
    private func skinFineVarianceRatio(_ recipe: EditRecipe) throws -> Double {
        let portrait = try self.portrait()
        let output = try SkinStage().apply(portrait.image, in: portrait.context(recipe))
        let rect = FaceRegions.maskBounds(face: portrait.face, extent: portrait.extent, tuning: portrait.tuning)
        return try Support.fineVarianceRatio(
            before: portrait.image, after: output, weight: portrait.skinMask(), in: rect, fineRadius: fineRadius())
    }

    // MARK: 피부

    func testSkinSmoothingChangesTheFaceButKeepsPores() throws {
        let before = try base()
        let after = try grid { $0.portrait.skin.smoothing = 1 }
        XCTAssertGreaterThanOrEqual(
            DisplayScale.changedFraction(before.grid, after, in: try faceRect), Visibility.smoothingChangedFraction)
        var recipe = EditRecipe()
        recipe.portrait.skin.smoothing = 1
        XCTAssertGreaterThanOrEqual(
            try skinFineVarianceRatio(recipe), Naturalness.fineVarianceRatioMinimum, "모공 대역은 남는다")
    }

    func testToneEveningEvensSkinButKeepsPores() throws {
        let before = try base()
        let after = try grid { $0.portrait.skin.toneEvening = 1 }
        let skin = try skinWeight()
        XCTAssertGreaterThanOrEqual(
            DisplayScale.changedFraction(before.grid, after, in: try faceRect), Visibility.toneEveningChangedFraction)
        let delta = DisplayScale.lumaDelta(before.grid, after, weight: skin)
        XCTAssertGreaterThanOrEqual(delta.meanAbsolute, Visibility.toneEveningMeanAbsolute)
        XCTAssertLessThanOrEqual(delta.mean, Naturalness.toneEveningMaximumMeanLift, "고르게 할 뿐 밝히지 않는다")
        var recipe = EditRecipe()
        recipe.portrait.skin.toneEvening = 1
        XCTAssertGreaterThanOrEqual(
            try skinFineVarianceRatio(recipe), Naturalness.fineVarianceRatioMinimum, "모공 대역은 남는다")
    }

    // MARK: 주름

    private func foldMask(_ key: SkinRefinementKey) throws -> FaceRegions.RegionMask? {
        let portrait = try self.portrait()
        let extent = portrait.extent
        let tuning = portrait.tuning
        let face = portrait.face
        switch key {
        case .darkCircles: return FaceRegions.darkCircleMask(face: face, extent: extent, tuning: tuning)
        case .nasolabial: return FaceRegions.nasolabialMask(face: face, extent: extent, tuning: tuning)
        case .marionette: return FaceRegions.marionetteMask(face: face, extent: extent, tuning: tuning)
        case .glabella: return FaceRegions.glabellaMask(face: face, extent: extent, tuning: tuning)
        default: return nil
        }
    }

    /// 자연 사진에서의 상한 + 합성 그늘 회복률.
    /// 하한은 호출자가 더한다.
    private func assertFoldIsNaturalAndRecoversShadow(
        _ key: SkinRefinementKey, file: StaticString = #filePath, line: UInt = #line
    )
        throws
    {
        let portrait = try self.portrait()
        let region = try XCTUnwrap(foldMask(key), "\(key) 띠", file: file, line: line)
        let weight = try portrait.mask(region)
        let before = try base().grid
        let natural = try grid({ $0.portrait.skin[key] = 1 }, stage: SkinStage())
        let lift = DisplayScale.lumaDelta(before, natural, weight: weight)
        XCTAssertLessThanOrEqual(lift.mean, Naturalness.foldMaximumMeanLift, "\(key) 밝은 얼룩 없음", file: file, line: line)
        let chroma = DisplayScale.chromaDelta(before, natural, weight: weight)
        XCTAssertLessThanOrEqual(
            max(chroma.cb, chroma.cr), Naturalness.foldMaximumChroma, "\(key) 색 기 없음", file: file, line: line)
        var recipe = EditRecipe()
        recipe.portrait.skin[key] = 1
        let naturalOutput = try SkinStage().apply(portrait.image, in: portrait.context(recipe))
        // 띠 마스크 가중이라 사각형 안에 걸친 눈·속눈썹은 비에 들어가지 않는다(스펙 G4 1.4 "띠 영역").
        XCTAssertGreaterThanOrEqual(
            try Support.fineVarianceRatio(
                before: portrait.image, after: naturalOutput, weight: region.image, in: region.bounds.integral,
                fineRadius: fineRadius()),
            Naturalness.fineVarianceRatioMinimum, "\(key) 질감 유지", file: file, line: line)
        let shadowed = try portrait.baked(
            SyntheticDefect.shadowed(portrait.image, mask: region.image, depth: Visibility.shadowDepth))
        let defective = try DisplayScale.grid(shadowed)
        let repaired = try grid({ $0.portrait.skin[key] = 1 }, stage: SkinStage(), input: shadowed)
        let recovery = DisplayScale.recovery(
            original: DisplayScale.luma(before, weight: weight),
            defective: DisplayScale.luma(defective, weight: weight),
            repaired: DisplayScale.luma(repaired, weight: weight))
        XCTAssertGreaterThanOrEqual(recovery, Visibility.foldRecovery, "\(key) 합성 그늘 회복", file: file, line: line)
    }

    func testDarkCirclesLiftUnderTheEyesVisiblyAndNaturally() throws {
        let before = try base().grid
        let after = try grid({ $0.portrait.skin.darkCircles = 1 }, stage: SkinStage())
        XCTAssertGreaterThanOrEqual(
            DisplayScale.changedFraction(before, after, in: try faceRect), Visibility.darkCirclesChangedFraction)
        let weight = try self.portrait().mask(foldMask(.darkCircles))
        XCTAssertGreaterThanOrEqual(
            DisplayScale.lumaDelta(before, after, weight: weight).mean, Visibility.darkCirclesMeanLift, "눈 아래가 밝아진다")
        try assertFoldIsNaturalAndRecoversShadow(.darkCircles)
    }

    func testNasolabialLiftsTheFoldVisiblyAndNaturally() throws {
        let before = try base().grid
        let after = try grid({ $0.portrait.skin.nasolabial = 1 }, stage: SkinStage())
        XCTAssertGreaterThanOrEqual(
            DisplayScale.changedFraction(before, after, in: try faceRect), Visibility.nasolabialChangedFraction)
        try assertFoldIsNaturalAndRecoversShadow(.nasolabial)
    }

    func testMarionetteRecoversASyntheticShadow() throws {
        try assertFoldIsNaturalAndRecoversShadow(.marionette)
    }

    func testGlabellaRecoversASyntheticShadow() throws {
        try assertFoldIsNaturalAndRecoversShadow(.glabella)
    }

    // MARK: 붉은기·번들거림

    func testRednessClearsASyntheticBlotchAndFlushIsVisible() throws {
        let portrait = try self.portrait()
        let cheek = try XCTUnwrap(FaceRegions.cheekRects(face: portrait.face, extent: portrait.extent).first)
        let center = CGPoint(x: cheek.midX, y: cheek.midY)
        let radius = portrait.faceWidth * Visibility.blotchRadiusFraction
        let blotchy = try portrait.baked(
            SyntheticDefect.reddened(portrait.image, center: center, radius: radius, extent: portrait.extent))
        let disc = try DisplayScale.grid(
            Support.hardEllipse(center: center, radii: CGSize(width: radius, height: radius), extent: portrait.extent))
        let original = try base().grid
        let defective = try DisplayScale.grid(blotchy)
        let repaired = try grid({ $0.portrait.skin.redness = -1 }, stage: SkinStage(), input: blotchy)
        let excess = DisplayScale.chromaDelta(original, defective, weight: disc).cr
        let remaining = DisplayScale.chromaDelta(original, repaired, weight: disc).cr
        XCTAssertGreaterThan(excess, Visibility.minimumPlantedBlotchCr, "반점이 심어졌다")
        XCTAssertGreaterThanOrEqual(1 - remaining / excess, Visibility.rednessClearRemoval, "붉은 반점을 맑게")
        let flushed = try grid({ $0.portrait.skin.redness = 1 }, stage: SkinStage())
        XCTAssertGreaterThanOrEqual(
            DisplayScale.channelDelta(original, flushed, channel: 0, weight: try skinWeight()),
            Visibility.rednessFlushRedLift,
            "혈색이 보인다")
    }

    func testShineFlattensASyntheticHighlight() throws {
        let portrait = try self.portrait()
        let frame = try XCTUnwrap(FaceFrame(face: portrait.face, extent: portrait.extent))
        let center = frame.imagePoint(u: 0, v: frame.eyeLevel + portrait.faceWidth * Visibility.highlightHeightFraction)
        let radius = portrait.faceWidth * Visibility.highlightRadiusFraction
        let shiny = try portrait.baked(
            SyntheticDefect.highlighted(
                portrait.image, center: center, radius: radius, lift: Visibility.highlightLift, extent: portrait.extent)
        )
        let disc = try DisplayScale.grid(
            Support.hardEllipse(center: center, radii: CGSize(width: radius, height: radius), extent: portrait.extent))
        let original = DisplayScale.luma(try base().grid, weight: disc)
        let defective = DisplayScale.luma(try DisplayScale.grid(shiny), weight: disc)
        let repaired = DisplayScale.luma(
            try grid({ $0.portrait.skin.shine = 1 }, stage: SkinStage(), input: shiny), weight: disc)
        XCTAssertGreaterThan(defective - original, Visibility.minimumPlantedHighlightLift, "반사광이 심어졌다")
        XCTAssertGreaterThanOrEqual(
            DisplayScale.recovery(original: original, defective: defective, repaired: repaired),
            Visibility.shineReduction,
            "반사광을 누른다")
    }

    // MARK: 몸 피부

    func testBodySkinBrightnessToneAndSmoothingAreVisible() throws {
        let portrait = try self.portrait()
        try XCTSkipIf(portrait.analysis.personMask == nil, "데모 사진에서 인물 마스크를 찾지 못함")
        let before = try base().grid
        let bright = try grid { $0.bodySkin.brightness = 1 }
        XCTAssertGreaterThanOrEqual(
            DisplayScale.changedFraction(before, bright, in: nil), Visibility.bodyBrightnessChangedFraction)
        // 상한은 몸 피부 영역(인물 마스크 또는 대체 영역 × 몸 피부색 가중치)의 평균 ΔY다(스펙 G4 1.4 "피부 영역").
        let bodySkin = try DisplayScale.grid(portrait.bodySkinArea())
        XCTAssertLessThanOrEqual(
            DisplayScale.lumaDelta(before, bright, weight: bodySkin).mean, Naturalness.bodyBrightnessMaximumMeanLift,
            "과하게 밝히지 않음")
        let skin = try skinWeight()
        let warm = try grid { $0.bodySkin.tone = 1 }
        let redMinusBlue =
            DisplayScale.channelDelta(before, warm, channel: 0, weight: skin)
            - DisplayScale.channelDelta(before, warm, channel: 2, weight: skin)
        XCTAssertGreaterThanOrEqual(redMinusBlue, Visibility.bodyToneRedMinusBlue, "따뜻한 톤이 보인다")
        let smooth = try grid { $0.bodySkin.smoothing = 1 }
        XCTAssertGreaterThanOrEqual(
            DisplayScale.changedFraction(before, smooth, in: nil), Visibility.bodySmoothingChangedFraction)
    }

    // MARK: 효과

    func testGrainIsVisibleAtPhoneScale() throws {
        let portrait = try self.portrait()
        let before = try base().grid
        let after = try grid { $0.effects.grain = 1 }
        XCTAssertGreaterThanOrEqual(
            DisplayScale.lumaDeltaStandardDeviation(before, after, in: nil), Visibility.grainStandardDeviation)
        let cell =
            EffectStage.grainSize(shortSide: portrait.extent.width, tuning: portrait.tuning)
            * DisplayScale.phoneWidth / portrait.extent.width
        XCTAssertGreaterThanOrEqual(cell, Visibility.grainMinimumCell, "알갱이가 화면에서 뭉개지지 않는 크기")
    }

    func testGlowIsVisibleAtPhoneScale() throws {
        let before = try base().grid
        let after = try grid { $0.effects.glow = 1 }
        XCTAssertGreaterThanOrEqual(
            DisplayScale.changedFraction(before, after, in: nil), Visibility.glowChangedFraction)
    }

    // MARK: 눈·입·블러셔 (원터치가 쓰는 항목)

    func testEyeAndLipFeaturesAreVisible() throws {
        let portrait = try self.portrait()
        let before = try base().grid
        let eyes = try portrait.mask(
            FaceRegions.eyeMask(face: portrait.face, extent: portrait.extent, tuning: portrait.tuning))
        let brightened = try grid({ $0.portrait.features.eyeBrighten = 1 }, stage: FeatureStage())
        XCTAssertGreaterThanOrEqual(
            DisplayScale.lumaDelta(before, brightened, weight: eyes).meanAbsolute, Visibility.eyeMeanAbsolute)
        let lips = try portrait.mask(
            FaceRegions.lipMask(face: portrait.face, extent: portrait.extent, tuning: portrait.tuning))
        let vivid = try grid({ $0.portrait.features.lipVitality = 1 }, stage: FeatureStage())
        XCTAssertGreaterThanOrEqual(
            DisplayScale.chromaDelta(before, vivid, weight: lips).cr, Visibility.lipChromaCr, "입술 혈색이 보인다")
        let teeth = try FaceRegions.teethMask(
            face: portrait.face, image: portrait.image, extent: portrait.extent, tuning: portrait.tuning)
        try XCTSkipIf(teeth == nil, "다문 입이라 치아 미백은 데모 사진에서 재지 않는다")
    }

    func testBlushIsVisible() throws {
        let portrait = try self.portrait()
        let catalog = try Support.sharedMakeupCatalog()
        var recipe = EditRecipe()
        recipe.makeup.blush = MakeupTint(colorID: "blush-peach", intensity: 1)
        let context = RenderContext(
            extent: portrait.extent, recipe: recipe, analysis: portrait.analysis, tuning: portrait.tuning,
            makeupCatalog: catalog)
        let output = try MakeupStage().apply(portrait.image, in: context)
        let blush = try portrait.mask(
            FaceRegions.blushMask(face: portrait.face, extent: portrait.extent, tuning: portrait.tuning))
        XCTAssertGreaterThanOrEqual(
            DisplayScale.lumaDelta(try base().grid, try DisplayScale.grid(output), weight: blush).meanAbsolute,
            Visibility.blushMeanAbsolute)
    }

    // MARK: 밖은 그대로

    func testFaceItemsLeaveHairAndBackgroundUntouched() throws {
        let portrait = try self.portrait()
        let before = try base().grid
        var recipe = EditRecipe()
        recipe.portrait.skin = SkinAdjustments(
            smoothing: 1, darkCircles: 1, nasolabial: 1, marionette: 1, glabella: 1, toneEvening: 1, redness: -1,
            shine: 1)
        let after = try DisplayScale.grid(portrait.render(recipe, stage: SkinStage()))
        let polygon = FaceRegions.skinPolygon(face: portrait.face, extent: portrait.extent, tuning: portrait.tuning)
        let dilation = portrait.faceWidth * Naturalness.outsideFaceDilationFraction
        let inside = FaceRegions.containment(polygons: [polygon], dilation: dilation)
        let scale = portrait.extent.width / DisplayScale.phoneWidth
        var outsideChanged = 0
        var outsideTotal = 0
        for y in 0..<before.height {
            for x in 0..<before.width {
                let point = CGPoint(x: x, y: y)
                guard !inside(CGPoint(x: CGFloat(x) * scale, y: CGFloat(y) * scale)) else { continue }
                outsideTotal += 1
                let a = before.rgba(point)
                let b = after.rgba(point)
                if (0..<3).contains(where: { abs(Int(a[$0]) - Int(b[$0])) >= DisplayScale.defaultMinimumDelta }) {
                    outsideChanged += 1
                }
            }
        }
        XCTAssertLessThanOrEqual(
            Double(outsideChanged) / Double(max(outsideTotal, 1)), Naturalness.outsideFaceChangedFraction,
            "얼굴 다각형 밖은 그대로")
    }
}
