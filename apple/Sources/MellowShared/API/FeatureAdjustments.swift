import Foundation

/// 눈·입 디테일 슬라이더 이름. 레시피 JSON 키와 같다.
public enum FeatureKey: String, CaseIterable, Codable, Sendable {
    case eyeBrighten
    case teethWhiten
    case lipVitality
}

/// 눈 또렷하게·치아 미백·입술 생기 0…1. 렌더는 D 단계.
public struct FeatureAdjustments: Codable, Equatable, Sendable {
    public var eyeBrighten: Double
    public var teethWhiten: Double
    public var lipVitality: Double

    public init(eyeBrighten: Double = 0, teethWhiten: Double = 0, lipVitality: Double = 0) {
        self.eyeBrighten = eyeBrighten
        self.teethWhiten = teethWhiten
        self.lipVitality = lipVitality
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        eyeBrighten = try container.decodeIfPresent(Double.self, forKey: .eyeBrighten) ?? 0
        teethWhiten = try container.decodeIfPresent(Double.self, forKey: .teethWhiten) ?? 0
        lipVitality = try container.decodeIfPresent(Double.self, forKey: .lipVitality) ?? 0
    }

    public subscript(key: FeatureKey) -> Double {
        get {
            switch key {
            case .eyeBrighten: return eyeBrighten
            case .teethWhiten: return teethWhiten
            case .lipVitality: return lipVitality
            }
        }
        set {
            switch key {
            case .eyeBrighten: eyeBrighten = newValue
            case .teethWhiten: teethWhiten = newValue
            case .lipVitality: lipVitality = newValue
            }
        }
    }

    public var numericValues: [Double] { FeatureKey.allCases.map { self[$0] } }
    public var hasEffect: Bool { numericValues.contains { $0 != 0 } }
}
