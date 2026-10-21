import Foundation

/// 원터치 인물 보정의 성별 표.
/// 값은 허용 상한(강도 1)이고 기본 강도 0.6이 Evoto 전후 측정 크기다(스펙 G4 1.4·3.2).
/// 렌더는 이 표를 모른다.
/// EditDocument.applyOneTouch가 표 × 강도를 레시피 항목 값으로 쓴다.
public enum OneTouchBundle {
    /// 강도 슬라이더의 끝.
    /// 표 값 그대로이고 그것이 상한이다.
    public static let maximumStrength = 1.0
    /// 원터치 기본 강도.
    /// Evoto 전후 측정 크기가 나는 강도다(스펙 G4 1.4).
    /// 편집 규칙(EditingPolicy)과 렌더 테스트가 함께 쓴다.
    public static let defaultStrength = 0.6
    /// 몸 피부 톤을 쓰는지.
    /// 표 값이 0인 동안은 쓰지 않아 사용자가 맞춘 톤을 지우지 않는다.
    public static var writesBodyTone: Bool { Table.bodyTone != 0 }

    /// 표 한 줄.
    /// 블러셔 색이 nil이면 블러셔 없음(강도 0으로 덮어씀)이다.
    public struct Values: Equatable, Sendable {
        public var smoothing: Double
        public var darkCircles: Double
        public var nasolabial: Double
        public var marionette: Double
        public var glabella: Double
        public var toneEvening: Double
        public var chromaEvening: Double
        public var redness: Double
        public var shine: Double
        public var spots: Double
        public var eyeBrighten: Double
        public var teethWhiten: Double
        public var lipVitality: Double
        public var blushIntensity: Double
        public var blushColorID: String?

        public init(
            smoothing: Double, darkCircles: Double, nasolabial: Double, marionette: Double, glabella: Double,
            toneEvening: Double, chromaEvening: Double, redness: Double, shine: Double, spots: Double,
            eyeBrighten: Double,
            teethWhiten: Double, lipVitality: Double, blushIntensity: Double, blushColorID: String?
        ) {
            self.smoothing = smoothing
            self.darkCircles = darkCircles
            self.nasolabial = nasolabial
            self.marionette = marionette
            self.glabella = glabella
            self.toneEvening = toneEvening
            self.chromaEvening = chromaEvening
            self.redness = redness
            self.shine = shine
            self.spots = spots
            self.eyeBrighten = eyeBrighten
            self.teethWhiten = teethWhiten
            self.lipVitality = lipVitality
            self.blushIntensity = blushIntensity
            self.blushColorID = blushColorID
        }

        /// 피부 정밀 아홉 값.
        var refinements: [SkinRefinementKey: Double] {
            [
                .darkCircles: darkCircles, .nasolabial: nasolabial, .marionette: marionette, .glabella: glabella,
                .toneEvening: toneEvening, .chromaEvening: chromaEvening, .redness: redness, .shine: shine,
                .spots: spots,
            ]
        }

        /// 눈·입 세 값.
        var features: [FeatureKey: Double] {
            [.eyeBrighten: eyeBrighten, .teethWhiten: teethWhiten, .lipVitality: lipVitality]
        }
    }

    /// 강도 1의 표.
    /// 매직 넘버는 여기에만 둔다.
    /// 남성은 질감을 남기고 색조 메이크업이 없다.
    /// 값은 스펙 G5 2절(Evoto 7쌍 실측)이다.
    /// 매끄럽게·얼룩 고르기·다크서클·팔자는 G4 값에서 내렸다(우리 0.6이 Evoto보다 더 평탄하고 더 밝았다).
    /// 점 지우기는 G5-2에서 더했다(Evoto와의 가장 큰 간극이 점 제거였다).
    /// 남성은 점을 더 남긴다.
    /// 얼룩 색 고르기는 G5-3에서 더했다(볼의 보라·붉은 얼룩이 점 지우기 뒤에 남은 간극이었다).
    /// 다크서클·팔자는 G5-3에서 한 번 더 내렸다(점 지우기·매끄럽게가 띠를 함께 밝혀 강도 1이 Evoto × 1.3을 넘었다).
    /// 여성은 다른 항목이 팔자 띠를 더 밝혀 팔자 값이 가장 낮다.
    public enum Table {
        public static let blushColorID = "blush-peach"
        /// 성별 미지정(공통).
        public static let common = Values(
            smoothing: 0.16, darkCircles: 0.30, nasolabial: 0.12, marionette: 0.25, glabella: 0.3, toneEvening: 0.08,
            chromaEvening: 0.5, redness: -0.2, shine: 0.45, spots: 1.0, eyeBrighten: 0.25, teethWhiten: 0.25,
            lipVitality: 0, blushIntensity: 0, blushColorID: nil)
        public static let female = Values(
            smoothing: 0.20, darkCircles: 0.30, nasolabial: 0.08, marionette: 0.3, glabella: 0.3, toneEvening: 0.10,
            chromaEvening: 0.5, redness: -0.25, shine: 0.4, spots: 1.0, eyeBrighten: 0.3, teethWhiten: 0.3,
            lipVitality: 0.2, blushIntensity: 0.15, blushColorID: blushColorID)
        public static let male = Values(
            smoothing: 0.12, darkCircles: 0.28, nasolabial: 0.14, marionette: 0.25, glabella: 0.3, toneEvening: 0.05,
            chromaEvening: 0.35, redness: -0.2, shine: 0.5, spots: 0.4, eyeBrighten: 0.2, teethWhiten: 0.25,
            lipVitality: 0, blushIntensity: 0, blushColorID: nil)
        /// 사진 단위 몸 피부 밝기.
        /// 전체 대상에서만 쓴다.
        /// Evoto 원클릭의 몸 피부 ΔY(+0.3/255)에 맞춰 G5에서 0.15 → 0.08.
        public static let bodyBrightness = 0.08
        /// 사진 단위 몸 피부 톤.
        /// 전체 대상에서만 쓴다.
        public static let bodyTone = 0.0
    }

    /// 묶인 키.
    /// 이 키를 손으로 바꾸면 그 층의 oneTouch 표시가 지워진다.
    /// 얼굴형·체형은 들지 않는다.
    /// 전체 층 표시에는 몸 피부 밝기도 묶인다(EditDocument가 따로 본다).
    public static let keys: Set<PortraitKey> = PortraitKey.skin.union(PortraitKey.features)
        .union([.makeupPart(.blush), .makeupPart(.lip)])

    /// 성별의 표.
    /// nil은 공통 표다.
    public static func values(for gender: Gender?) -> Values {
        switch gender {
        case .female: return Table.female
        case .male: return Table.male
        case nil: return Table.common
        }
    }

    /// 강도를 0…maximumStrength로 자른다.
    public static func clampedStrength(_ strength: Double) -> Double {
        AdjustmentRange.clamped(strength, to: 0...maximumStrength)
    }

    /// 표 × 강도의 층.
    /// 강도 0은 빈 층이다(호출자가 묶음 제거로 다룬다).
    /// 블러셔·립은 늘 덮어써 아래 층의 색조를 막는다.
    /// 얼굴형 키와 룩 이름은 쓰지 않는다.
    public static func layer(for gender: Gender?, strength: Double) -> PortraitLayer {
        let scale = clampedStrength(strength)
        guard scale > 0 else { return PortraitLayer() }
        let table = values(for: gender)
        var layer = PortraitLayer()
        layer.skinSmoothing = AdjustmentRange.clamped(table.smoothing * scale, to: AdjustmentRange.unit)
        // 점 지우기가 복제 원을 대신한다(스펙 G5 판정 4b).
        // false를 덮어써 1.4.0 세션의 true를 끈다.
        layer.autoBlemish = false
        for (key, value) in table.refinements {
            layer.skinRefinement[key] = AdjustmentRange.clamped(value * scale, to: AdjustmentRange.skinRefinement(key))
        }
        for (key, value) in table.features {
            layer.features[key] = AdjustmentRange.clamped(value * scale, to: AdjustmentRange.unit)
        }
        layer.makeup[.blush] = MakeupTint(
            colorID: table.blushColorID,
            intensity: AdjustmentRange.clamped(table.blushIntensity * scale, to: AdjustmentRange.unit))
        layer.makeup[.lip] = MakeupTint(colorID: nil, intensity: 0)
        layer.oneTouch = scale
        return layer
    }

    /// 표 × 강도의 몸 피부.
    /// 매끄럽게는 묶음 밖이라 0이다.
    public static func bodySkin(strength: Double) -> BodySkinAdjustments {
        let scale = clampedStrength(strength)
        return BodySkinAdjustments(
            brightness: AdjustmentRange.clamped(
                Table.bodyBrightness * scale, to: AdjustmentRange.bodySkin(.brightness)),
            tone: AdjustmentRange.clamped(Table.bodyTone * scale, to: AdjustmentRange.bodySkin(.tone)))
    }
}
