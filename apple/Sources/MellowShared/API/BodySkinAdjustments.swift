import Foundation

/// 몸 피부 슬라이더 이름. 레시피 JSON 키와 같다. tone만 가운데 0인 양방향이다.
public enum BodySkinKey: String, CaseIterable, Codable, Sendable {
    case brightness
    case tone
    case smoothing
}

/// 보이는 피부 전체(얼굴 포함)에 거는 밝기 0…1, 톤 −1…1(따뜻 ↔ 차가움), 매끄럽게 0…1. 렌더는 bodySkin 단계(인물 마스크 × 피부색).
public struct BodySkinAdjustments: Codable, Equatable, Sendable {
    public var brightness: Double
    public var tone: Double
    public var smoothing: Double

    public init(brightness: Double = 0, tone: Double = 0, smoothing: Double = 0) {
        self.brightness = brightness
        self.tone = tone
        self.smoothing = smoothing
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        brightness = try container.decodeIfPresent(Double.self, forKey: .brightness) ?? 0
        tone = try container.decodeIfPresent(Double.self, forKey: .tone) ?? 0
        smoothing = try container.decodeIfPresent(Double.self, forKey: .smoothing) ?? 0
    }

    public subscript(key: BodySkinKey) -> Double {
        get {
            switch key {
            case .brightness: return brightness
            case .tone: return tone
            case .smoothing: return smoothing
            }
        }
        set {
            switch key {
            case .brightness: brightness = newValue
            case .tone: tone = newValue
            case .smoothing: smoothing = newValue
            }
        }
    }

    /// BodySkinKey.allCases 순서.
    public var numericValues: [Double] { BodySkinKey.allCases.map { self[$0] } }
    public var hasEffect: Bool { numericValues.contains { $0 != 0 } }
}
