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

    /// 좌우 반전을 켜고 끈다. 자르기 영역과 수평 보정도 함께 거울에 비춰 같은 픽셀이 보이게 한다.
    /// 반전은 회전보다 먼저 적용된다. 원본의 좌우 거울은 짝수 회전 뒤 프레임에서 x → 1 − x,
    /// 홀수 회전 뒤 프레임에서는 y → 1 − y가 된다(R∘H(x, y) = (y, x) = V∘R(x, y)).
    /// 그래서 짝수면 x → 1 − x − w, 홀수면 y → 1 − y − h. 거울에 비친 회전은 방향이 반대라 수평 보정 각도의 부호를 바꾼다.
    public func flippedHorizontally() -> GeometryAdjustments {
        var flipped = self
        flipped.flipHorizontal.toggle()
        // −0이 저장되지 않도록 0은 그대로 둔다.
        if straightenDegrees != 0 {
            flipped.straightenDegrees = -straightenDegrees
        }
        if let crop {
            if normalizedQuarterTurns % 2 == 0 {
                flipped.crop = NormalizedRect(
                    x: 1 - crop.x - crop.width, y: crop.y, width: crop.width, height: crop.height)
            } else {
                flipped.crop = NormalizedRect(
                    x: crop.x, y: 1 - crop.y - crop.height, width: crop.width, height: crop.height)
            }
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
