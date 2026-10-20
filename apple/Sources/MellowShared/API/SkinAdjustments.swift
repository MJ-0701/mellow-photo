import Foundation

/// 피부 정밀 슬라이더 이름. 레시피 JSON 키와 같다. redness만 가운데 0인 양방향이다.
public enum SkinRefinementKey: String, CaseIterable, Codable, Sendable {
    case darkCircles
    case nasolabial
    case marionette
    case glabella
    case toneEvening
    case redness
    case shine
}

/// 피부 보정 강도 0…1, 자동 잡티 스위치, 피부 정밀 7종(G). redness만 −1…1이고 나머지는 0…1이다.
public struct SkinAdjustments: Codable, Equatable, Sendable {
    public var smoothing: Double
    public var autoBlemish: Bool
    public var darkCircles: Double
    public var nasolabial: Double
    public var marionette: Double
    public var glabella: Double
    public var toneEvening: Double
    public var redness: Double
    public var shine: Double

    public init(
        smoothing: Double = 0, autoBlemish: Bool = false, darkCircles: Double = 0, nasolabial: Double = 0,
        marionette: Double = 0, glabella: Double = 0, toneEvening: Double = 0, redness: Double = 0, shine: Double = 0
    ) {
        self.smoothing = smoothing
        self.autoBlemish = autoBlemish
        self.darkCircles = darkCircles
        self.nasolabial = nasolabial
        self.marionette = marionette
        self.glabella = glabella
        self.toneEvening = toneEvening
        self.redness = redness
        self.shine = shine
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        smoothing = try container.decodeIfPresent(Double.self, forKey: .smoothing) ?? 0
        autoBlemish = try container.decodeIfPresent(Bool.self, forKey: .autoBlemish) ?? false
        darkCircles = try container.decodeIfPresent(Double.self, forKey: .darkCircles) ?? 0
        nasolabial = try container.decodeIfPresent(Double.self, forKey: .nasolabial) ?? 0
        marionette = try container.decodeIfPresent(Double.self, forKey: .marionette) ?? 0
        glabella = try container.decodeIfPresent(Double.self, forKey: .glabella) ?? 0
        toneEvening = try container.decodeIfPresent(Double.self, forKey: .toneEvening) ?? 0
        redness = try container.decodeIfPresent(Double.self, forKey: .redness) ?? 0
        shine = try container.decodeIfPresent(Double.self, forKey: .shine) ?? 0
    }

    public subscript(key: SkinRefinementKey) -> Double {
        get {
            switch key {
            case .darkCircles: return darkCircles
            case .nasolabial: return nasolabial
            case .marionette: return marionette
            case .glabella: return glabella
            case .toneEvening: return toneEvening
            case .redness: return redness
            case .shine: return shine
            }
        }
        set {
            switch key {
            case .darkCircles: darkCircles = newValue
            case .nasolabial: nasolabial = newValue
            case .marionette: marionette = newValue
            case .glabella: glabella = newValue
            case .toneEvening: toneEvening = newValue
            case .redness: redness = newValue
            case .shine: shine = newValue
            }
        }
    }

    /// SkinRefinementKey.allCases 순서의 정밀 값.
    public var refinementValues: [Double] { SkinRefinementKey.allCases.map { self[$0] } }
    /// 정밀 값 중 0이 아닌 것이 있는지.
    public var hasRefinement: Bool { refinementValues.contains { $0 != 0 } }
    /// 렌더 결과를 바꾸는 값이 있는지.
    public var hasEffect: Bool { smoothing != 0 || autoBlemish || hasRefinement }
    public var numericValues: [Double] { [smoothing] + refinementValues }
}
