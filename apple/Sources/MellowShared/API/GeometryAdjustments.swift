import Foundation

/// 반전 → 90° 회전 → 수평 보정 → 자르기 순서로 적용된다. crop은 그 앞 단계가 끝난 이미지 기준.
public struct GeometryAdjustments: Codable, Equatable, Sendable {
    public static let maxStraightenDegrees = 15.0

    public var flipHorizontal: Bool
    /// 시계 방향 90° 회전 횟수 0…3.
    public var quarterTurns: Int
    /// 양수면 시계 방향.
    public var straightenDegrees: Double
    public var crop: NormalizedRect?

    public init(
        flipHorizontal: Bool = false, quarterTurns: Int = 0, straightenDegrees: Double = 0, crop: NormalizedRect? = nil
    ) {
        self.flipHorizontal = flipHorizontal
        self.quarterTurns = quarterTurns
        self.straightenDegrees = straightenDegrees
        self.crop = crop
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        flipHorizontal = try container.decodeIfPresent(Bool.self, forKey: .flipHorizontal) ?? false
        quarterTurns = try container.decodeIfPresent(Int.self, forKey: .quarterTurns) ?? 0
        straightenDegrees = try container.decodeIfPresent(Double.self, forKey: .straightenDegrees) ?? 0
        crop = try container.decodeIfPresent(NormalizedRect.self, forKey: .crop)
    }

    public var isIdentity: Bool { self == GeometryAdjustments() }

    /// 0…3으로 정규화한 회전 횟수.
    public var normalizedQuarterTurns: Int { ((quarterTurns % 4) + 4) % 4 }

    public var numericValues: [Double] {
        var values = [straightenDegrees]
        if let crop {
            values += [crop.x, crop.y, crop.width, crop.height]
        }
        return values
    }
}
