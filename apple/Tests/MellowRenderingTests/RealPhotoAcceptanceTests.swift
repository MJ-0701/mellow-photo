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
        /// 피부 톤(몸) ±1에서 피부 마스크 가중 |ΔR − ΔB|(8비트) 상한.
        /// 얼굴 전체가 주황·푸른빛으로 뜨지 않게 한다(스펙 G4 1.4).
        static let bodyToneMaximumRedMinusBlue = 30.0
        static let outsideFaceChangedFraction = 0.002
        /// "얼굴 밖"을 재기 전에 얼굴 다각형을 넓히는 폭.
        /// 얼굴 폭 비율(스펙 G4 1.4).
        static let outsideFaceDilationFraction: CGFloat = 0.05
        static let browChangedFraction = 0.05
    }

    /// VALIDATION 실측 표에 옮길 측정 출력 줄(`acceptance <항목> <지표>=<값>`).
    /// 단언에 쓰는 값을 그대로 적는다.
    @discardableResult
    private func record(_ item: String, _ metric: String, _ value: Double) -> Double {
        print("acceptance \(item) \(metric)=\(String(format: "%.4f", value))")
        return value
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
            record("smoothing", "changed", DisplayScale.changedFraction(before.grid, after, in: try faceRect)),
            Visibility.smoothingChangedFraction)
        var recipe = EditRecipe()
        recipe.portrait.skin.smoothing = 1
        XCTAssertGreaterThanOrEqual(
            record("smoothing", "fineRatio", try skinFineVarianceRatio(recipe)), Naturalness.fineVarianceRatioMinimum,
            "모공 대역은 남는다")
    }

    func testToneEveningEvensSkinButKeepsPores() throws {
        let before = try base()
        let after = try grid { $0.portrait.skin.toneEvening = 1 }
        let skin = try skinWeight()
        XCTAssertGreaterThanOrEqual(
            record("toneEvening", "changed", DisplayScale.changedFraction(before.grid, after, in: try faceRect)),
            Visibility.toneEveningChangedFraction)
        let delta = DisplayScale.lumaDelta(before.grid, after, weight: skin)
        XCTAssertGreaterThanOrEqual(
            record("toneEvening", "meanAbsLuma", delta.meanAbsolute), Visibility.toneEveningMeanAbsolute)
        XCTAssertLessThanOrEqual(
            record("toneEvening", "meanLuma", delta.mean), Naturalness.toneEveningMaximumMeanLift, "고르게 할 뿐 밝히지 않는다")
        var recipe = EditRecipe()
        recipe.portrait.skin.toneEvening = 1
        XCTAssertGreaterThanOrEqual(
            record("toneEvening", "fineRatio", try skinFineVarianceRatio(recipe)),
            Naturalness.fineVarianceRatioMinimum, "모공 대역은 남는다")
    }

    // MARK: 주름

    /// 자연 사진에서의 상한 + 합성 그늘 회복률.
    /// 하한은 호출자가 더한다.
    private func assertFoldIsNaturalAndRecoversShadow(
        _ key: SkinRefinementKey, file: StaticString = #filePath, line: UInt = #line
    )
        throws
    {
        let portrait = try self.portrait()
        let region = try XCTUnwrap(portrait.foldBandMask(key), "\(key) 띠", file: file, line: line)
        let weight = try portrait.mask(region)
        let before = try base().grid
        let natural = try grid({ $0.portrait.skin[key] = 1 }, stage: SkinStage())
        let lift = DisplayScale.lumaDelta(before, natural, weight: weight)
        XCTAssertLessThanOrEqual(
            record("\(key)", "bandMeanLuma", lift.mean), Naturalness.foldMaximumMeanLift, "\(key) 밝은 얼룩 없음",
            file: file, line: line)
        let chroma = DisplayScale.chromaDelta(before, natural, weight: weight)
        XCTAssertLessThanOrEqual(
            record("\(key)", "bandChroma", max(chroma.cb, chroma.cr)), Naturalness.foldMaximumChroma,
            "\(key) 색 기 없음", file: file, line: line)
        var recipe = EditRecipe()
        recipe.portrait.skin[key] = 1
        let naturalOutput = try SkinStage().apply(portrait.image, in: portrait.context(recipe))
        // 띠 마스크 가중이라 사각형 안에 걸친 눈·속눈썹은 비에 들어가지 않는다(스펙 G4 1.4 "띠 영역").
        let fineRatio = try Support.fineVarianceRatio(
            before: portrait.image, after: naturalOutput, weight: region.image, in: region.bounds.integral,
            fineRadius: fineRadius())
        XCTAssertGreaterThanOrEqual(
            record("\(key)", "fineRatio", fineRatio), Naturalness.fineVarianceRatioMinimum, "\(key) 질감 유지",
            file: file, line: line)
        let shadowed = try portrait.baked(
            SyntheticDefect.shadowed(portrait.image, mask: region.image, depth: Visibility.shadowDepth))
        let defective = try DisplayScale.grid(shadowed)
        let repaired = try grid({ $0.portrait.skin[key] = 1 }, stage: SkinStage(), input: shadowed)
        let recovery = DisplayScale.recovery(
            original: DisplayScale.luma(before, weight: weight),
            defective: DisplayScale.luma(defective, weight: weight),
            repaired: DisplayScale.luma(repaired, weight: weight))
        XCTAssertGreaterThanOrEqual(
            record("\(key)", "recovery", recovery), Visibility.foldRecovery, "\(key) 합성 그늘 회복", file: file,
            line: line)
    }

    func testDarkCirclesLiftUnderTheEyesVisiblyAndNaturally() throws {
        let before = try base().grid
        let after = try grid({ $0.portrait.skin.darkCircles = 1 }, stage: SkinStage())
        XCTAssertGreaterThanOrEqual(
            record("darkCircles", "changed", DisplayScale.changedFraction(before, after, in: try faceRect)),
            Visibility.darkCirclesChangedFraction)
        let weight = try self.portrait().mask(self.portrait().foldBandMask(.darkCircles))
        XCTAssertGreaterThanOrEqual(
            DisplayScale.lumaDelta(before, after, weight: weight).mean, Visibility.darkCirclesMeanLift, "눈 아래가 밝아진다")
        try assertFoldIsNaturalAndRecoversShadow(.darkCircles)
    }

    func testNasolabialLiftsTheFoldVisiblyAndNaturally() throws {
        let before = try base().grid
        let after = try grid({ $0.portrait.skin.nasolabial = 1 }, stage: SkinStage())
        XCTAssertGreaterThanOrEqual(
            record("nasolabial", "changed", DisplayScale.changedFraction(before, after, in: try faceRect)),
            Visibility.nasolabialChangedFraction)
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
        XCTAssertGreaterThan(record("rednessClear", "plantedCr", excess), Visibility.minimumPlantedBlotchCr, "반점이 심어졌다")
        XCTAssertGreaterThanOrEqual(
            record("rednessClear", "removal", 1 - remaining / excess), Visibility.rednessClearRemoval, "붉은 반점을 맑게")
        let flushed = try grid({ $0.portrait.skin.redness = 1 }, stage: SkinStage())
        XCTAssertGreaterThanOrEqual(
            record(
                "rednessFlush", "meanRed",
                DisplayScale.channelDelta(original, flushed, channel: 0, weight: try skinWeight())),
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
        XCTAssertGreaterThan(
            record("shine", "plantedLuma", defective - original), Visibility.minimumPlantedHighlightLift, "반사광이 심어졌다")
        XCTAssertGreaterThanOrEqual(
            record(
                "shine", "reduction",
                DisplayScale.recovery(original: original, defective: defective, repaired: repaired)),
            Visibility.shineReduction,
            "반사광을 누른다")
    }

    // MARK: 몸 피부

    func testBodySkinBrightnessToneAndSmoothingAreVisible() throws {
        let portrait = try self.portrait()
        // 인물 마스크가 없으면 몸 피부 단계는 얼굴 둘레 대체 영역을 쓰고 `bodySkinArea()`도 같은 영역을 잰다.
        // 그래서 건너뛰지 않고 어느 영역이었는지만 출력 줄로 남긴다.
        record("bodySkin", "personMask", portrait.analysis.personMask == nil ? 0 : 1)
        let before = try base().grid
        let bright = try grid { $0.bodySkin.brightness = 1 }
        XCTAssertGreaterThanOrEqual(
            record("bodyBrightness", "changed", DisplayScale.changedFraction(before, bright, in: nil)),
            Visibility.bodyBrightnessChangedFraction)
        // 상한은 몸 피부 영역(인물 마스크 또는 대체 영역 × 몸 피부색 가중치)의 평균 ΔY다(스펙 G4 1.4 "피부 영역").
        let bodySkin = try DisplayScale.grid(portrait.bodySkinArea())
        XCTAssertLessThanOrEqual(
            record("bodyBrightness", "meanLuma", DisplayScale.lumaDelta(before, bright, weight: bodySkin).mean),
            Naturalness.bodyBrightnessMaximumMeanLift,
            "과하게 밝히지 않음")
        let skin = try skinWeight()
        let warm = try grid { $0.bodySkin.tone = 1 }
        let redMinusBlue =
            DisplayScale.channelDelta(before, warm, channel: 0, weight: skin)
            - DisplayScale.channelDelta(before, warm, channel: 2, weight: skin)
        XCTAssertGreaterThanOrEqual(
            record("bodyTone", "redMinusBlue", redMinusBlue), Visibility.bodyToneRedMinusBlue, "따뜻한 톤이 보인다")
        XCTAssertLessThanOrEqual(abs(redMinusBlue), Naturalness.bodyToneMaximumRedMinusBlue, "따뜻한 톤이 주황빛으로 뜨지 않음")
        let cool = try grid { $0.bodySkin.tone = -1 }
        let coolRedMinusBlue =
            DisplayScale.channelDelta(before, cool, channel: 0, weight: skin)
            - DisplayScale.channelDelta(before, cool, channel: 2, weight: skin)
        XCTAssertLessThanOrEqual(
            abs(record("bodyTone", "coolRedMinusBlue", coolRedMinusBlue)), Naturalness.bodyToneMaximumRedMinusBlue,
            "차가운 톤이 푸른빛으로 뜨지 않음")
        let smooth = try grid { $0.bodySkin.smoothing = 1 }
        XCTAssertGreaterThanOrEqual(
            record("bodySmoothing", "changed", DisplayScale.changedFraction(before, smooth, in: nil)),
            Visibility.bodySmoothingChangedFraction)
    }

    // MARK: 효과

    func testGrainIsVisibleAtPhoneScale() throws {
        let portrait = try self.portrait()
        let before = try base().grid
        let after = try grid { $0.effects.grain = 1 }
        XCTAssertGreaterThanOrEqual(
            record("grain", "lumaStdDev", DisplayScale.lumaDeltaStandardDeviation(before, after, in: nil)),
            Visibility.grainStandardDeviation)
        let cell =
            EffectStage.grainSize(shortSide: portrait.extent.width, tuning: portrait.tuning)
            * DisplayScale.phoneWidth / portrait.extent.width
        XCTAssertGreaterThanOrEqual(
            record("grain", "cellPixels", Double(cell)), Visibility.grainMinimumCell, "알갱이가 화면에서 뭉개지지 않는 크기")
    }

    func testGlowIsVisibleAtPhoneScale() throws {
        let before = try base().grid
        let after = try grid { $0.effects.glow = 1 }
        XCTAssertGreaterThanOrEqual(
            record("glow", "changed", DisplayScale.changedFraction(before, after, in: nil)),
            Visibility.glowChangedFraction)
    }

    // MARK: 눈·입·블러셔 (원터치가 쓰는 항목)

    func testEyeAndLipFeaturesAreVisible() throws {
        let portrait = try self.portrait()
        let before = try base().grid
        let eyes = try portrait.mask(
            FaceRegions.eyeMask(face: portrait.face, extent: portrait.extent, tuning: portrait.tuning))
        let brightened = try grid({ $0.portrait.features.eyeBrighten = 1 }, stage: FeatureStage())
        XCTAssertGreaterThanOrEqual(
            record("eyeBrighten", "meanAbsLuma", DisplayScale.lumaDelta(before, brightened, weight: eyes).meanAbsolute),
            Visibility.eyeMeanAbsolute)
        let lips = try portrait.mask(
            FaceRegions.lipMask(face: portrait.face, extent: portrait.extent, tuning: portrait.tuning))
        let vivid = try grid({ $0.portrait.features.lipVitality = 1 }, stage: FeatureStage())
        XCTAssertGreaterThanOrEqual(
            record("lipVitality", "meanAbsCr", DisplayScale.chromaDelta(before, vivid, weight: lips).cr),
            Visibility.lipChromaCr,
            "입술 혈색이 보인다")
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
            record(
                "blush", "meanAbsLuma",
                DisplayScale.lumaDelta(try base().grid, try DisplayScale.grid(output), weight: blush).meanAbsolute),
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
        XCTAssertLessThanOrEqual(
            record(
                "outsideFace", "changed",
                portrait.outsideFaceChangedFraction(
                    before: before, after: after, dilationFraction: Naturalness.outsideFaceDilationFraction)),
            Naturalness.outsideFaceChangedFraction,
            "얼굴 다각형 밖은 그대로")
    }

    // MARK: 원터치

    /// 원터치 하한(스펙 G4 1.2 원터치 행, G5 1.2에서 재조정).
    /// 화면 배율 얼굴 상자 changedFraction.
    /// 실측이 옛 문턱을 넘는 항목은 옛 문턱을 유지하고 미달 항목만 G5 새 문턱으로 내린다(VALIDATION G5-1).
    enum OneTouchVisibility {
        static let femaleDefaultChangedFraction = 0.05
        /// 남성·공통 기본 0.6도 같은 하한(스펙 G4 1.2, G4-2 구현 중 추가).
        /// 남성은 G5 표 인하 뒤 실측 0.047이라 G5 새 문턱 0.03으로 내렸다(스펙 G5 1.2).
        static let maleDefaultChangedFraction = 0.03
        static let commonDefaultChangedFraction = 0.05
        static let femaleMaximumChangedFraction = 0.10
        static let maleMaximumChangedFraction = 0.06
        static let femaleMaleDifferenceFraction = 0.02
        static let coupleMinimumChangedFraction = 0.03
    }

    /// 원터치 상한·밝기 하한(스펙 G4 1.4 원터치 행, G5 1.2에서 재조정).
    enum OneTouchNaturalness {
        /// 기본 0.6 얼굴 피부 평균 ΔY(/255).
        /// Evoto 원클릭 +1.9, 75분위 +3.0(스펙 G5 1.2).
        static let skinMeanLiftRange = 0.5...3.0
        /// 강도 1 얼굴 피부 평균 ΔY 상한.
        static let maximumSkinMeanLift = 4.0
        static let defaultFineVarianceRatio = 0.9
        static let maximumFineVarianceRatio = 0.85
        static let defaultMidVarianceRatio = 0.80
        static let maximumMidVarianceRatio = 0.70
        static let defaultLowVarianceRatio = 0.85
        static let maximumLowVarianceRatio = 0.80
        /// 중간 대역 바깥 경계·넓은 대역 바깥 경계(얼굴 폭 비율).
        /// 하네스 Calibration과 같다.
        static let midOuterFraction = 0.03
        static let lowOuterFraction = 0.12
        /// 강도 1 띠 가중 평균 ΔY 상한(Evoto 전용 도구 × 1.3).
        static let darkCircleBandMaximumLift = 10.5
        static let nasolabialBandMaximumLift = 6.7
        static let defaultChromaDeviationRatio = 0.80
        static let maximumChromaDeviationRatio = 0.70
        /// 몸 피부(얼굴 다각형 밖) 평균 ΔY 상한.
        /// Evoto +0.3(스펙 G5 1.1).
        static let defaultBodyMeanLift = 1.5
        static let maximumBodyMeanLift = 2.5
        static let percentileAbsoluteLuma = 60.0
        static let percentile = 0.99
        static let skinChroma = 0.015
        static let maleLipChroma = 0.01
        static let femaleLipChroma = 0.03
        static let browChangedFraction = 0.05
        static let outsideFaceChangedFraction = 0.002
    }

    /// 자동 잡티 복구 원반 잔차(스펙 G5 1.2 "자동 잡티 복구").
    enum HealBounds {
        /// 심는 어두운 원의 반지름(얼굴 폭 비율)과 선형 휘도 배율.
        static let plantedRadiusFraction: CGFloat = 0.012
        static let plantedFactor = 0.80
        /// 복구 원 안 평균 Y와 고리 평균 Y의 차 상한(8비트).
        static let discResidual = 3.0
        /// 잡티 반지름 → 복구 원 반지름 배수가 blemishHealRadiusScale이다.
        /// 원반 평균은 복구 원의 0.65배(MaskBuilder 타원이 완전히 덮는 범위) 안에서 잰다.
        static let discFraction: CGFloat = 0.65
        /// 고리는 복구 원 반지름의 1~1.5배다.
        static let ringOuterFraction: CGFloat = 1.5
    }

    /// 전체 대상 원터치와 같은 층(전체 층 공통 표, 그룹 층 성별 표)에 faces[i]를 genders[i]로 지정한 레시피.
    /// 하한(보임)과 남녀 비교는 몸 피부 없이 얼굴만 잰다(보수적).
    /// 상한(자연)은 withBodySkin으로 전체 대상 원터치가 실제로 내는 결과를 잰다(스펙 G4 1.4 "위 항목들의 합").
    /// 미지정(nil)은 기록을 만들지 않는다.
    private static func oneTouchRecipe(
        strength: Double, faces: [FaceGeometry], genders: [Gender?], withBodySkin: Bool = false
    ) -> EditRecipe {
        var recipe = EditRecipe()
        if withBodySkin {
            recipe.bodySkin = OneTouchBundle.bodySkin(strength: strength)
        }
        OneTouchBundle.layer(for: nil, strength: strength).applied(to: &recipe.portrait, makeup: &recipe.makeup)
        for group in Gender.allCases {
            recipe.people.groups[group] = OneTouchBundle.layer(for: group, strength: strength)
        }
        recipe.people.individuals = zip(faces, genders).compactMap { face, gender in
            gender.map { PersonRecord(anchor: PersonAnchor(faceBox: face.boundingBox), gender: $0) }
        }
        return recipe
    }

    /// 데모 사진에 원터치를 건 전체 파이프라인 결과(메이크업 팔레트 포함).
    private func oneTouchRender(_ recipe: EditRecipe) throws -> (grid: PixelGrid, output: CIImage) {
        let portrait = try self.portrait()
        let context = RenderContext(
            extent: portrait.extent, recipe: recipe, analysis: portrait.analysis, tuning: portrait.tuning,
            makeupCatalog: try Support.sharedMakeupCatalog())
        let output = try RenderPipeline.standard.render(portrait.image, context: context)
        return (try DisplayScale.grid(output), output)
    }

    private func oneTouchRender(strength: Double, gender: Gender?, withBodySkin: Bool = false) throws -> (
        grid: PixelGrid, output: CIImage
    ) {
        let portrait = try self.portrait()
        return try oneTouchRender(
            Self.oneTouchRecipe(
                strength: strength, faces: [portrait.face], genders: [gender], withBodySkin: withBodySkin))
    }

    private func label(_ gender: Gender?, _ strength: Double) -> String {
        "oneTouch-\(gender?.rawValue ?? "common")-\(strength)"
    }

    func testOneTouchIsVisibleForEachGenderAndDiffersBetweenThem() throws {
        let portrait = try self.portrait()
        let before = try base().grid
        let rect = try faceRect
        let femaleDefault = try oneTouchRender(strength: OneTouchBundle.defaultStrength, gender: .female).grid
        XCTAssertGreaterThanOrEqual(
            record(
                label(.female, OneTouchBundle.defaultStrength), "changed",
                DisplayScale.changedFraction(before, femaleDefault, in: rect)),
            OneTouchVisibility.femaleDefaultChangedFraction)
        let defaults: [(gender: Gender?, minimum: Double)] = [
            (.male, OneTouchVisibility.maleDefaultChangedFraction),
            (nil, OneTouchVisibility.commonDefaultChangedFraction),
        ]
        for item in defaults {
            let result = try oneTouchRender(strength: OneTouchBundle.defaultStrength, gender: item.gender).grid
            XCTAssertGreaterThanOrEqual(
                record(
                    label(item.gender, OneTouchBundle.defaultStrength), "changed",
                    DisplayScale.changedFraction(before, result, in: rect)),
                item.minimum, "\(label(item.gender, OneTouchBundle.defaultStrength)) 기본 강도도 보인다")
        }
        let female = try oneTouchRender(strength: OneTouchBundle.maximumStrength, gender: .female).grid
        XCTAssertGreaterThanOrEqual(
            record(label(.female, 1), "changed", DisplayScale.changedFraction(before, female, in: rect)),
            OneTouchVisibility.femaleMaximumChangedFraction)
        let male = try oneTouchRender(strength: OneTouchBundle.maximumStrength, gender: .male).grid
        XCTAssertGreaterThanOrEqual(
            record(label(.male, 1), "changed", DisplayScale.changedFraction(before, male, in: rect)),
            OneTouchVisibility.maleMaximumChangedFraction)
        XCTAssertGreaterThanOrEqual(
            record("oneTouch-femaleVsMale-1", "changed", DisplayScale.changedFraction(female, male, in: rect)),
            OneTouchVisibility.femaleMaleDifferenceFraction, "남녀 결과가 다르다")
        let unassigned = try oneTouchRender(strength: OneTouchBundle.maximumStrength, gender: nil).grid
        var commonOnly = Self.oneTouchRecipe(
            strength: OneTouchBundle.maximumStrength, faces: [portrait.face], genders: [nil])
        commonOnly.people.groups = [:]
        let common = try oneTouchRender(commonOnly).grid
        XCTAssertEqual(DisplayScale.changedFraction(unassigned, common, in: nil), 0, "미지정은 공통 표만 받는다")
        let lips = try portrait.mask(
            FaceRegions.lipMask(face: portrait.face, extent: portrait.extent, tuning: portrait.tuning))
        let maleLips = DisplayScale.chromaDelta(before, male, weight: lips)
        XCTAssertLessThanOrEqual(
            record(label(.male, 1), "lipChroma", max(maleLips.cb, maleLips.cr)), OneTouchNaturalness.maleLipChroma,
            "남성은 립 없음")
    }

    func testOneTouchStaysNaturalAtDefaultAndMaximum() throws {
        let portrait = try self.portrait()
        let before = try base().grid
        let rect = try faceRect
        let skin = try skinWeight()
        let blush = try portrait.mask(
            FaceRegions.blushMask(face: portrait.face, extent: portrait.extent, tuning: portrait.tuning))
        let skinWithoutBlush = try subtract(skin, blush)
        let brows = try portrait.browMask()
        XCTAssertGreaterThan(DisplayScale.maskedPixelCount(brows), 0, "눈썹 마스크가 비어 있지 않다")
        let lips = try portrait.mask(
            FaceRegions.lipMask(face: portrait.face, extent: portrait.extent, tuning: portrait.tuning))
        let bodySkinArea = try DisplayScale.grid(portrait.bodySkinArea())
        let skinBounds = FaceRegions.maskBounds(face: portrait.face, extent: portrait.extent, tuning: portrait.tuning)
        let cases: [(gender: Gender?, strength: Double, fineRatio: Double)] = [
            (.female, OneTouchBundle.defaultStrength, OneTouchNaturalness.defaultFineVarianceRatio),
            (.male, OneTouchBundle.defaultStrength, OneTouchNaturalness.defaultFineVarianceRatio),
            (nil, OneTouchBundle.defaultStrength, OneTouchNaturalness.defaultFineVarianceRatio),
            (.female, OneTouchBundle.maximumStrength, OneTouchNaturalness.maximumFineVarianceRatio),
            (.male, OneTouchBundle.maximumStrength, OneTouchNaturalness.maximumFineVarianceRatio),
            (nil, OneTouchBundle.maximumStrength, OneTouchNaturalness.maximumFineVarianceRatio),
        ]
        for item in cases {
            let result = try oneTouchRender(strength: item.strength, gender: item.gender, withBodySkin: true)
            let name = label(item.gender, item.strength)
            let isDefault = item.strength == OneTouchBundle.defaultStrength
            let lift = record(name, "skinMeanLuma", DisplayScale.lumaDelta(before, result.grid, weight: skin).mean)
            if isDefault {
                XCTAssertTrue(OneTouchNaturalness.skinMeanLiftRange.contains(lift), "\(name) 피부 평균 ΔY \(lift)")
            } else {
                XCTAssertLessThanOrEqual(lift, OneTouchNaturalness.maximumSkinMeanLift, "\(name) 밝기 상한")
            }
            try assertBandsAndChromaStayNatural(name: name, isDefault: isDefault, output: result.output)
            let crRatio = DisplayScale.chromaStandardDeviationRatio(before, result.grid, weight: skin)
            XCTAssertGreaterThanOrEqual(
                record(name, "crSigmaRatio", crRatio),
                isDefault
                    ? OneTouchNaturalness.defaultChromaDeviationRatio : OneTouchNaturalness.maximumChromaDeviationRatio,
                "\(name) 붉은기 분산")
            if !isDefault {
                try assertFoldBandsStayBelowEvoto(name: name, before: before, after: result.grid)
            }
            let fineRatio = try Support.fineVarianceRatio(
                before: portrait.image, after: result.output, weight: portrait.skinMask(), in: skinBounds,
                fineRadius: fineRadius())
            XCTAssertGreaterThanOrEqual(record(name, "fineRatio", fineRatio), item.fineRatio, "\(name) 질감")
            XCTAssertLessThanOrEqual(
                record(
                    name, "p99AbsLuma",
                    DisplayScale.percentileAbsoluteLumaDelta(
                        before, result.grid, in: rect, percentile: OneTouchNaturalness.percentile)),
                OneTouchNaturalness.percentileAbsoluteLuma, "\(name) 국소 폭주 없음")
            let chroma = DisplayScale.chromaDelta(
                before, result.grid, weight: item.gender == .female ? skinWithoutBlush : skin)
            XCTAssertLessThanOrEqual(
                record(name, "skinChroma", max(chroma.cb, chroma.cr)), OneTouchNaturalness.skinChroma, "\(name) 색 기 없음")
            XCTAssertLessThanOrEqual(
                record(name, "browChanged", DisplayScale.changedFraction(before, result.grid, weight: brows)),
                OneTouchNaturalness.browChangedFraction, "\(name) 눈썹")
            XCTAssertLessThanOrEqual(
                record(
                    name, "outsideFace",
                    portrait.outsideFaceChangedFraction(
                        before: before, after: result.grid, dilationFraction: Naturalness.outsideFaceDilationFraction,
                        excluding: bodySkinArea)),
                OneTouchNaturalness.outsideFaceChangedFraction, "\(name) 얼굴·몸 피부 밖")
            // 얼굴 항목(피부·눈입·메이크업)은 몸 피부 없이 렌더해 넓힌 얼굴 다각형 밖 전체를 뺌 없이 잰다.
            let faceOnly = try oneTouchRender(strength: item.strength, gender: item.gender).grid
            XCTAssertLessThanOrEqual(
                record(
                    name, "outsideFaceFaceOnly",
                    portrait.outsideFaceChangedFraction(
                        before: before, after: faceOnly, dilationFraction: Naturalness.outsideFaceDilationFraction)),
                OneTouchNaturalness.outsideFaceChangedFraction, "\(name) 얼굴 항목은 얼굴 밖을 바꾸지 않는다")
            let lipChroma = DisplayScale.chromaDelta(before, result.grid, weight: lips)
            XCTAssertLessThanOrEqual(
                record(name, "lipChroma", max(lipChroma.cb, lipChroma.cr)),
                item.gender == .female ? OneTouchNaturalness.femaleLipChroma : OneTouchNaturalness.maleLipChroma,
                "\(name) 입술")
        }
    }

    /// 피부 안쪽 중간·넓은 대역 분산 비(스펙 G5 1.2).
    /// Evoto는 두 대역을 거의 그대로 둔다.
    private func assertBandsAndChromaStayNatural(name: String, isDefault: Bool, output: CIImage) throws {
        let portrait = try self.portrait()
        let interior = try portrait.interiorSkinMask()
        let bounds = FaceRegions.maskBounds(face: portrait.face, extent: portrait.extent, tuning: portrait.tuning)
        let faceWidth = Double(portrait.faceWidth)
        let midOuter = faceWidth * OneTouchNaturalness.midOuterFraction
        let lowOuter = faceWidth * OneTouchNaturalness.lowOuterFraction
        let midRatio = try Support.bandVarianceRatio(
            before: portrait.image, after: output, weight: interior, in: bounds, innerRadius: fineRadius(),
            outerRadius: midOuter)
        XCTAssertGreaterThanOrEqual(
            record(name, "midRatio", midRatio),
            isDefault ? OneTouchNaturalness.defaultMidVarianceRatio : OneTouchNaturalness.maximumMidVarianceRatio,
            "\(name) 중간 대역")
        let lowRatio = try Support.bandVarianceRatio(
            before: portrait.image, after: output, weight: interior, in: bounds, innerRadius: midOuter,
            outerRadius: lowOuter)
        XCTAssertGreaterThanOrEqual(
            record(name, "lowRatio", lowRatio),
            isDefault ? OneTouchNaturalness.defaultLowVarianceRatio : OneTouchNaturalness.maximumLowVarianceRatio,
            "\(name) 넓은 대역")
    }

    /// 강도 1 다크서클·팔자 띠 평균 ΔY ≤ Evoto 전용 도구 × 1.3(스펙 G5 판정 5).
    private func assertFoldBandsStayBelowEvoto(name: String, before: PixelGrid, after: PixelGrid) throws {
        let portrait = try self.portrait()
        let darkCircle = try portrait.mask(portrait.foldBandMask(.darkCircles))
        XCTAssertLessThanOrEqual(
            record(name, "darkCircleBand", DisplayScale.lumaDelta(before, after, weight: darkCircle).mean),
            OneTouchNaturalness.darkCircleBandMaximumLift, "\(name) 다크서클 ≤ Evoto × 1.3")
        let nasolabial = try portrait.mask(portrait.foldBandMask(.nasolabial))
        XCTAssertLessThanOrEqual(
            record(name, "nasolabialBand", DisplayScale.lumaDelta(before, after, weight: nasolabial).mean),
            OneTouchNaturalness.nasolabialBandMaximumLift, "\(name) 팔자 ≤ Evoto × 1.3")
    }

    /// 전체 대상 원터치의 몸 피부(얼굴 다각형 밖) 평균 ΔY(스펙 G5 1.1 몸 피부 행).
    func testOneTouchKeepsBodyLiftWithinEvotoBounds() throws {
        let portrait = try self.portrait()
        let before = try base().grid
        let body = try DisplayScale.grid(portrait.bodyOnlySkinArea())
        XCTAssertGreaterThan(DisplayScale.maskedPixelCount(body), 0, "몸 피부 영역이 비어 있지 않다")
        let cases: [(strength: Double, maximum: Double)] = [
            (OneTouchBundle.defaultStrength, OneTouchNaturalness.defaultBodyMeanLift),
            (OneTouchBundle.maximumStrength, OneTouchNaturalness.maximumBodyMeanLift),
        ]
        for item in cases {
            let result = try oneTouchRender(strength: item.strength, gender: nil, withBodySkin: true)
            let name = label(nil, item.strength)
            XCTAssertLessThanOrEqual(
                record(name, "bodyMeanLuma", DisplayScale.lumaDelta(before, result.grid, weight: body).mean),
                item.maximum, "\(name) 몸 피부 밝기")
        }
    }

    /// 자동 잡티 복구가 데모 사진의 경사면에서 원반을 남기지 않는다(스펙 G5 1.2 "자동 잡티 복구").
    func testAutoBlemishHealLeavesNoDiscOnTheDemoCheek() throws {
        let portrait = try self.portrait()
        let extent = portrait.extent
        let cheek = try XCTUnwrap(FaceRegions.cheekRects(face: portrait.face, extent: extent).first)
        // 볼 상자 아래 턱 쪽(상자 높이만큼 아래)의 경사면.
        let center = CGPoint(x: cheek.midX, y: cheek.minY - cheek.height)
        let radius = portrait.faceWidth * HealBounds.plantedRadiusFraction
        let spotted = try portrait.baked(
            SyntheticDefect.spotted(
                portrait.image, centers: [center], radius: radius, factor: HealBounds.plantedFactor, extent: extent))
        let shortSide = min(extent.width, extent.height)
        let blemish = BlemishSpot(
            x: Double((center.x - extent.minX) / extent.width), y: Double((center.y - extent.minY) / extent.height),
            radius: Double(radius / shortSide), faceIndex: 0)
        var recipe = EditRecipe()
        recipe.portrait.skin.autoBlemish = true
        let analysis = PhotoAnalysis(
            faces: portrait.analysis.faces, blemishes: [blemish], personMask: nil, bodies: [])
        let context = RenderContext(extent: extent, recipe: recipe, analysis: analysis, tuning: portrait.tuning)
        let healed = try DisplayScale.grid(SkinStage().apply(spotted, in: context))
        // 복구 원은 잡티 반지름 × blemishHealRadiusScale이다.
        let healRadius = radius * CGFloat(portrait.tuning.blemishHealRadiusScale)
        let discRadius = healRadius * HealBounds.discFraction
        let disc = try DisplayScale.grid(
            Support.hardEllipse(center: center, radii: CGSize(width: discRadius, height: discRadius), extent: extent))
        let ring = try DisplayScale.grid(
            portrait.annulus(center: center, inner: healRadius, outer: healRadius * HealBounds.ringOuterFraction))
        let residual = abs(DisplayScale.luma(healed, weight: disc) - DisplayScale.luma(healed, weight: ring))
        XCTAssertLessThanOrEqual(record("heal", "discResidual", residual), HealBounds.discResidual, "원반 잔차 없음")
        let defective = try DisplayScale.grid(spotted)
        let defectDisc = DisplayScale.luma(defective, weight: disc)
        let defectResidual = abs(defectDisc - DisplayScale.luma(defective, weight: ring))
        record("heal", "plantedResidual", defectResidual)
        XCTAssertGreaterThan(defectResidual, HealBounds.discResidual, "심은 원이 복구 전에는 보인다")
    }

    /// 변형은 묶음 밖이다(스펙 G4 1.4 마지막 행).
    /// 얼굴마다 해석한 얼굴형이 0이고 체형이 기본이며 변형 단계가 아무것도 바꾸지 않는다.
    func testOneTouchNeverReshapesTheFaceOrBody() throws {
        let portrait = try self.portrait()
        for gender in [Gender?.none, .female, .male] {
            let recipe = Self.oneTouchRecipe(
                strength: OneTouchBundle.maximumStrength, faces: [portrait.face], genders: [gender])
            let context = portrait.context(recipe)
            XCTAssertEqual(
                context.faceTargets.map(\.portrait.face), [FaceShapeAdjustments()], "\(String(describing: gender))")
            XCTAssertEqual(recipe.body, BodyShapeAdjustments())
            let warped = try DisplayScale.grid(portrait.render(recipe, stage: ShapeWarpStage()))
            XCTAssertEqual(DisplayScale.changedFraction(try base().grid, warped, in: nil), 0, "변형 단계는 그대로")
        }
    }

    /// 커플 생성 사진: 라벨대로 성별을 지정하고 전체 원터치를 건다.
    /// 두 얼굴이 다 바뀌되 여성이 더 많이 바뀌고 남성 입술 색은 그대로다.
    func testOneTouchOnTheCouplePhotoTreatsMaleAndFemaleDifferently() throws {
        let people = try RealPeople.couple.get()
        XCTAssertEqual(people.faces.count, people.labels.count, "Vision 얼굴 수가 라벨과 같아야 한다(PeopleFixturesTests)")
        let catalog = try Support.sharedMakeupCatalog()
        let analysis = PhotoAnalysis(faces: people.faces)
        func render(_ recipe: EditRecipe) throws -> PixelGrid {
            let context = RenderContext(
                extent: people.extent, recipe: recipe, analysis: analysis, tuning: people.tuning,
                makeupCatalog: catalog)
            return try DisplayScale.grid(RenderPipeline.standard.render(people.image, context: context))
        }
        let before = try render(EditRecipe())
        let after = try render(
            Self.oneTouchRecipe(strength: OneTouchBundle.maximumStrength, faces: people.faces, genders: people.labels))
        var changed: [Gender: Double] = [:]
        for (face, gender) in zip(people.faces, people.labels) {
            let rect = DisplayScale.rect(face.boundingBox, in: before)
            let fraction = record(
                "oneTouch-couple-\(gender.rawValue)", "changed", DisplayScale.changedFraction(before, after, in: rect))
            changed[gender] = fraction
            XCTAssertGreaterThanOrEqual(fraction, OneTouchVisibility.coupleMinimumChangedFraction, "\(gender) 얼굴이 바뀐다")
        }
        XCTAssertGreaterThan(changed[.female] ?? 0, changed[.male] ?? 0, "여성 표가 더 많이 바꾼다")
        let maleIndex = try XCTUnwrap(people.labels.firstIndex(of: .male))
        let maleLips = try XCTUnwrap(
            FaceRegions.lipMask(face: people.faces[maleIndex], extent: people.extent, tuning: people.tuning))
        let chroma = DisplayScale.chromaDelta(
            before, after, weight: try DisplayScale.grid(maleLips.image.cropped(to: people.extent)))
        XCTAssertLessThanOrEqual(
            record("oneTouch-couple-male", "lipChroma", max(chroma.cb, chroma.cr)), OneTouchNaturalness.maleLipChroma,
            "남성 입술 색은 그대로")
        let unassigned = try render(
            Self.oneTouchRecipe(
                strength: OneTouchBundle.maximumStrength, faces: people.faces, genders: people.labels.map { _ in nil }))
        for (index, face) in people.faces.enumerated() {
            let rect = DisplayScale.rect(face.boundingBox, in: before)
            XCTAssertGreaterThanOrEqual(
                record(
                    "oneTouch-couple-unassigned-\(index)", "changed",
                    DisplayScale.changedFraction(before, unassigned, in: rect)),
                OneTouchVisibility.coupleMinimumChangedFraction, "미지정도 공통 표로 바뀐다")
        }
    }

    /// 두 마스크의 차(a − b, 0 아래는 0).
    /// PixelGrid는 읽기 전용이라 같은 크기의 비트맵을 색 관리 없이 다시 만든다.
    private func subtract(_ a: PixelGrid, _ b: PixelGrid) throws -> PixelGrid {
        var bytes = [UInt8](repeating: 0, count: a.width * a.height * Self.bytesPerPixel)
        for y in 0..<a.height {
            for x in 0..<a.width {
                let point = CGPoint(x: x, y: y)
                let value = UInt8(max(0, Int(a.red(point)) - Int(b.red(point))))
                let offset = ((a.height - 1 - y) * a.width + x) * Self.bytesPerPixel
                bytes[offset] = value
                bytes[offset + 1] = value
                bytes[offset + 2] = value
            }
        }
        let provider = try XCTUnwrap(CGDataProvider(data: Data(bytes) as CFData))
        let image = try XCTUnwrap(
            CGImage(
                width: a.width, height: a.height, bitsPerComponent: Self.bitsPerComponent,
                bitsPerPixel: Self.bitsPerComponent * Self.bytesPerPixel, bytesPerRow: a.width * Self.bytesPerPixel,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue), provider: provider,
                decode: nil, shouldInterpolate: false, intent: .defaultIntent))
        return PixelGrid(image)
    }

    private static let bitsPerComponent = 8
    private static let bytesPerPixel = 4
}
