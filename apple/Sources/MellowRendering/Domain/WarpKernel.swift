import CoreImage
import MellowShared

/// CIWarpKernel 문자열 소스를 감싸는 유일한 자리. Metal로 바꿀 때 이 타입만 바꾼다.
/// 런타임 Metal 커널은 동적 라이브러리를 지원하는 기기가 필요해 iOS 17 하한보다 좁다.
final class WarpKernel: @unchecked Sendable {
    static let shared = WarpKernel()

    /// ROI를 변위보다 이만큼(픽셀) 더 넓혀 경계 샘플링이 잘리지 않게 한다.
    private static let roiPadding: CGFloat = 2

    private let kernel: CIWarpKernel?

    private init() {
        kernel = CIWarpKernel(
            source: """
                kernel vec2 localWarp(vec2 center, vec2 delta, float radius) {
                    vec2 p = destCoord();
                    float t = clamp(1.0 - distance(p, center) / radius, 0.0, 1.0);
                    float w = t * t * (3.0 - 2.0 * t);
                    return p - delta * w;
                }
                """)
    }

    /// center·delta는 픽셀 좌표. delta 길이는 radius * displacementLimit로 제한한다.
    func apply(
        to image: CIImage, extent: CGRect, center: CGPoint, delta: CGVector, radius: CGFloat, displacementLimit: Double
    ) throws -> CIImage {
        guard let kernel else { throw MellowError.warpUnavailable }
        var dx = delta.dx
        var dy = delta.dy
        let length = hypot(dx, dy)
        let limit = radius * displacementLimit
        if length > limit {
            dx *= limit / length
            dy *= limit / length
        }
        let margin = max(abs(dx), abs(dy)) + Self.roiPadding
        let arguments: [Any] = [CIVector(x: center.x, y: center.y), CIVector(x: dx, y: dy), radius]
        let warped = kernel.apply(
            extent: extent,
            roiCallback: { _, rect in rect.insetBy(dx: -margin, dy: -margin) },
            image: image.clampedToExtent(),
            arguments: arguments)
        guard let warped else { throw MellowError.renderFailed }
        return warped.cropped(to: extent)
    }
}
