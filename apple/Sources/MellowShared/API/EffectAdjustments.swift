import Foundation

/// 효과 슬라이더 이름. 레시피 JSON 키와 같다.
public enum EffectKey: String, CaseIterable, Codable, Sendable {
    case grain
    case glow
}

/// 그레인·글로우 0…1. 렌더는 룩 뒤 마지막 단계(effect)이고 분석이 필요 없다.
public struct EffectAdjustments: Codable, Equatable, Sendable {
    public var grain: Double
    public var glow: Double

    public init(grain: Double = 0, glow: Double = 0) {
        self.grain = grain
        self.glow = glow
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        grain = try container.decodeIfPresent(Double.self, forKey: .grain) ?? 0
        glow = try container.decodeIfPresent(Double.self, forKey: .glow) ?? 0
    }

    public subscript(key: EffectKey) -> Double {
        get {
            switch key {
            case .grain: return grain
            case .glow: return glow
            }
        }
        set {
            switch key {
            case .grain: grain = newValue
            case .glow: glow = newValue
            }
        }
    }

    /// EffectKey.allCases 순서.
    public var numericValues: [Double] { EffectKey.allCases.map { self[$0] } }
    public var hasEffect: Bool { numericValues.contains { $0 != 0 } }
}
