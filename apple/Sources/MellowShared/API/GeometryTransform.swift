import Foundation

/// 출력(자른 화면) 정규화 좌표와 원본 정규화 좌표를 오간다. 순수 수학이라 모든 플랫폼이 같은 식을 쓴다.
/// 순서: 반전 → 시계 방향 90° 회전 → 수평 보정(중심 회전 + 확대) → 자르기.
public struct GeometryTransform: Sendable {
    public let geometry: GeometryAdjustments
    public let sourceAspect: Double
    /// 반전·회전 뒤의 가로/세로.
    public let turnedAspect: Double
    public let outputAspect: Double

    public init(geometry: GeometryAdjustments, sourceAspect: Double) {
        self.geometry = geometry
        self.sourceAspect = sourceAspect
        let turns = geometry.normalizedQuarterTurns
        turnedAspect = turns % 2 == 0 ? sourceAspect : 1 / sourceAspect
        if let crop = geometry.crop {
            outputAspect = turnedAspect * crop.width / crop.height
        } else {
            outputAspect = turnedAspect
        }
    }

    /// 빈 모서리가 생기지 않는 최소 확대 배율.
    public static func straightenScale(degrees: Double, aspect: Double) -> Double {
        let radians = abs(degrees) * .pi / 180
        return cos(radians) + sin(radians) * max(aspect, 1 / aspect)
    }

    public func toOriginal(_ point: NormalizedPoint) -> NormalizedPoint {
        var current = point
        if let crop = geometry.crop {
            current = NormalizedPoint(x: crop.x + current.x * crop.width, y: crop.y + current.y * crop.height)
        }
        current = unstraighten(current)
        for _ in 0..<geometry.normalizedQuarterTurns {
            current = Self.turnCounterclockwise(current)
        }
        if geometry.flipHorizontal {
            current = NormalizedPoint(x: 1 - current.x, y: current.y)
        }
        return current
    }

    /// 원본 좌표가 자른 영역 밖이면 nil.
    public func toOutput(_ point: NormalizedPoint) -> NormalizedPoint? {
        var current = point
        if geometry.flipHorizontal {
            current = NormalizedPoint(x: 1 - current.x, y: current.y)
        }
        for _ in 0..<geometry.normalizedQuarterTurns {
            current = Self.turnClockwise(current)
        }
        current = straighten(current)
        if let crop = geometry.crop {
            current = NormalizedPoint(x: (current.x - crop.x) / crop.width, y: (current.y - crop.y) / crop.height)
        }
        let range = -1e-9...(1 + 1e-9)
        guard range.contains(current.x), range.contains(current.y) else { return nil }
        return current
    }

    /// 시계 방향 90°: (x, y) → (y, 1 − x).
    private static func turnClockwise(_ point: NormalizedPoint) -> NormalizedPoint {
        NormalizedPoint(x: point.y, y: 1 - point.x)
    }

    private static func turnCounterclockwise(_ point: NormalizedPoint) -> NormalizedPoint {
        NormalizedPoint(x: 1 - point.y, y: point.x)
    }

    /// 수평 보정: 이미지를 시계 방향 θ만큼 돌리고 s배 확대. 가로세로비를 반영한 중심 좌표에서 계산한다.
    private func straighten(_ point: NormalizedPoint) -> NormalizedPoint {
        guard geometry.straightenDegrees != 0 else { return point }
        let radians = -geometry.straightenDegrees * .pi / 180
        let scale = Self.straightenScale(degrees: geometry.straightenDegrees, aspect: turnedAspect)
        let u = (point.x - 0.5) * turnedAspect
        let v = point.y - 0.5
        let ru = (u * cos(radians) - v * sin(radians)) * scale
        let rv = (u * sin(radians) + v * cos(radians)) * scale
        return NormalizedPoint(x: ru / turnedAspect + 0.5, y: rv + 0.5)
    }

    private func unstraighten(_ point: NormalizedPoint) -> NormalizedPoint {
        guard geometry.straightenDegrees != 0 else { return point }
        let radians = geometry.straightenDegrees * .pi / 180
        let scale = Self.straightenScale(degrees: geometry.straightenDegrees, aspect: turnedAspect)
        let u = (point.x - 0.5) * turnedAspect / scale
        let v = (point.y - 0.5) / scale
        let ru = u * cos(radians) - v * sin(radians)
        let rv = u * sin(radians) + v * cos(radians)
        return NormalizedPoint(x: ru / turnedAspect + 0.5, y: rv + 0.5)
    }
}
