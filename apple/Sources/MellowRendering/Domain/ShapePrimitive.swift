import CoreImage

/// 이동량 지도에 더하는 원소. 좌표·길이는 extent 기준 픽셀이고 원점은 왼쪽 아래다.
/// 결과는 out(p) = in(p − D(p))라서 내용은 원소의 이동 방향으로 움직인다.
enum ShapePrimitive: Equatable, Sendable {
    /// center에서 radius 안을 smoothstep 감쇠로 vector만큼 민다.
    case push(center: CGPoint, vector: CGVector, radius: CGFloat)
    /// center 기준 반경 방향으로 확대(factor > 0)하거나 축소(< 0)한다. 중심의 선형 배율은 1 / (1 − factor).
    case scale(center: CGPoint, factor: CGFloat, radius: CGFloat)
    /// yStart에서 yEnd까지의 가로 띠를 yEnd 쪽으로 늘린다. 띠 안 이동은 stretch × span × t²(3 − 2t)라
    /// 양 끝(골반·발목)에서 기울기가 0이고 가운데 국소 늘림이 최대 1.5 × stretch다.
    /// yEnd 너머는 stretch × (yEnd − yStart)만큼 통째로 밀린다. 지도에 그리지 않고 DisplacementWarp 샘플링 커널이 같은 식으로 더한다.
    case band(yStart: CGFloat, yEnd: CGFloat, stretch: CGFloat)

    /// smoothstep 감쇠. t = clamp(1 − d / r), w = t²(3 − 2t). WarpKernel과 같은 모양이다.
    static func falloff(distance: CGFloat, radius: CGFloat) -> CGFloat {
        guard radius > 0 else { return 0 }
        let t = min(1, max(0, 1 - distance / radius))
        return t * t * (3 - 2 * t)
    }

    /// 원소 하나의 최대 이동을 제한한다. push는 |vector| ≤ radius × limit, scale은 |factor| ≤ limit, band는 |stretch| ≤ limit.
    func limited(to limit: Double) -> ShapePrimitive {
        let cap = CGFloat(limit)
        switch self {
        case .push(let center, let vector, let radius):
            let length = hypot(vector.dx, vector.dy)
            let maximum = max(0, radius) * cap
            guard length > maximum, length > 0 else { return self }
            let limitedVector = CGVector(dx: vector.dx * maximum / length, dy: vector.dy * maximum / length)
            return .push(center: center, vector: limitedVector, radius: radius)
        case .scale(let center, let factor, let radius):
            return .scale(center: center, factor: min(cap, max(-cap, factor)), radius: radius)
        case .band(let yStart, let yEnd, let stretch):
            return .band(yStart: yStart, yEnd: yEnd, stretch: min(cap, max(-cap, stretch)))
        }
    }

    /// 다리 길게 띠인지. 띠는 이동량 지도가 아니라 샘플링 커널이 계산한다.
    var isBand: Bool {
        switch self {
        case .band:
            return true
        case .push, .scale:
            return false
        }
    }

    /// 아무것도 옮기지 않는 원소. 렌더에서 뺀다.
    var isIdentity: Bool {
        switch self {
        case .push(_, let vector, let radius):
            return radius <= 0 || (vector.dx == 0 && vector.dy == 0)
        case .scale(_, let factor, let radius):
            return radius <= 0 || factor == 0
        case .band(let yStart, let yEnd, let stretch):
            return stretch == 0 || yStart == yEnd
        }
    }

    /// 이 원소가 옮길 수 있는 최대 거리(픽셀). 샘플링 ROI 여백에 쓴다.
    var maxDisplacement: CGFloat {
        switch self {
        case .push(_, let vector, _):
            return hypot(vector.dx, vector.dy)
        case .scale(_, let factor, let radius):
            return abs(factor) * radius
        case .band(let yStart, let yEnd, let stretch):
            return abs(stretch * (yEnd - yStart))
        }
    }

    /// DisplacementWarp 커널과 같은 식의 CPU 참조 구현. 테스트와 접힘 검사에 쓴다.
    func displacement(at point: CGPoint) -> CGVector {
        switch self {
        case .push(let center, let vector, let radius):
            let w = Self.falloff(distance: hypot(point.x - center.x, point.y - center.y), radius: radius)
            return CGVector(dx: vector.dx * w, dy: vector.dy * w)
        case .scale(let center, let factor, let radius):
            let offset = CGVector(dx: point.x - center.x, dy: point.y - center.y)
            let w = Self.falloff(distance: hypot(offset.dx, offset.dy), radius: radius)
            return CGVector(dx: offset.dx * factor * w, dy: offset.dy * factor * w)
        case .band(let yStart, let yEnd, let stretch):
            let span = yEnd - yStart
            guard span != 0 else { return .zero }
            let t = min(1, max(0, (point.y - yStart) / span))
            return CGVector(dx: 0, dy: stretch * span * t * t * (3 - 2 * t))
        }
    }
}
