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

    /// 시계 방향으로 90° 더 돌린다. 자르기 영역도 이미지와 함께 돌려 같은 픽셀이 보이게 한다.
    /// 정규화 좌표(원점 왼쪽 아래)에서 시계 방향 90°는 GeometryTransform과 같이 (x, y) → (y, 1 − x)다.
    /// 사각형의 x 범위 [x, x + w]는 새 y 범위 [1 − x − w, 1 − x]로, y 범위 [y, y + h]는 새 x 범위로 간다.
    /// 그래서 (x, y, w, h) → (y, 1 − x − w, h, w). 수평 보정은 중심 회전이라 90° 회전과 순서를 바꿔도 같다.
    public func turnedClockwise() -> GeometryAdjustments {
        var turned = self
        turned.quarterTurns = (normalizedQuarterTurns + 1) % 4
        if let crop {
            turned.crop = NormalizedRect(x: crop.y, y: 1 - crop.x - crop.width, width: crop.height, height: crop.width)
        }
        return turned
    }

    /// 화면에 보이는 그대로 좌우 반전한다. 자르기 영역과 수평 보정도 함께 거울에 비춰 같은 픽셀이 보이게 한다.
    /// 출력 공간에서 화면 거울은 Mx ∘ S ∘ T^k ∘ F다(F 반전, T 시계 방향 90°, S 수평 보정, Mx는 x → 1 − x).
    /// Mx ∘ S(θ) = S(−θ) ∘ Mx라 수평 보정 각도의 부호를 바꾼다.
    /// Mx ∘ T = T ∘ My이고 My = T² ∘ Mx라서 홀수 k에서는 Mx ∘ T^k = T^(k+2) ∘ Mx, 짝수 k에서는 T^k ∘ Mx다.
    /// 원본 쪽 Mx는 F를 켜고 끄는 것이므로, 반전을 뒤집고 홀수 회전이면 반 바퀴를 더한다.
    /// 자르기 사각형은 회전 뒤 프레임에서 늘 x → 1 − x − w로 비친다.
    public func flippedHorizontally() -> GeometryAdjustments {
        var flipped = self
        flipped.flipHorizontal.toggle()
        if normalizedQuarterTurns % 2 == 1 {
            flipped.quarterTurns = (normalizedQuarterTurns + 2) % 4
        }
        // −0이 저장되지 않도록 0은 그대로 둔다.
        if straightenDegrees != 0 {
            flipped.straightenDegrees = -straightenDegrees
        }
        if let crop {
            flipped.crop = NormalizedRect(x: 1 - crop.x - crop.width, y: crop.y, width: crop.width, height: crop.height)
        }
        return flipped
    }

    public var numericValues: [Double] {
        var values = [straightenDegrees]
        if let crop {
            values += [crop.x, crop.y, crop.width, crop.height]
        }
        return values
    }
}
