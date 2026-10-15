import CoreImage
import MellowShared

/// 얼굴형·체형 이동 원소를 이동량 지도 하나로 더해 한 번만 샘플링한다.
/// 지도는 R = dx, G = dy(픽셀)인 작업 형식 float 이미지이고 결과는 out(p) = in(p − D(p))다.
/// 지도 색 커널 3개와 샘플링 일반 커널 1개를 감싸는 유일한 자리. Metal로 바꿀 때 이 타입만 바꾼다.
/// CIWarpKernel은 균일 인자만 받고 이미지를 읽을 수 없어 지도를 샘플링하려면 일반 커널이 필요하다.
final class DisplacementWarp: @unchecked Sendable {
    static let shared = DisplacementWarp()

    /// ROI를 최대 이동보다 이만큼(픽셀) 더 넓혀 쌍선형 샘플링이 잘리지 않게 한다.
    private static let roiPadding: CGFloat = 2
    /// 샘플링 커널에서 입력 이미지 인자의 순서. ROI 콜백이 인덱스로 구분한다.
    private static let imageArgumentIndex: Int32 = 0

    private let pushField: CIColorKernel?
    private let scaleField: CIColorKernel?
    private let bandField: CIColorKernel?
    private let sampler: CIKernel?

    /// 지도 커널은 알파를 늘 1로 둔다. 사전곱 나눗셈이 이동량을 바꾸지 않게 한다.
    private init() {
        pushField = CIColorKernel(
            source: """
                kernel vec4 pushField(__sample field, vec2 center, vec2 vector, float radius) {
                    float t = clamp(1.0 - distance(destCoord(), center) / radius, 0.0, 1.0);
                    float w = t * t * (3.0 - 2.0 * t);
                    return vec4(field.rg + vector * w, 0.0, 1.0);
                }
                """)
        scaleField = CIColorKernel(
            source: """
                kernel vec4 scaleField(__sample field, vec2 center, float factor, float radius) {
                    vec2 offset = destCoord() - center;
                    float t = clamp(1.0 - length(offset) / radius, 0.0, 1.0);
                    float w = t * t * (3.0 - 2.0 * t);
                    return vec4(field.rg + offset * (factor * w), 0.0, 1.0);
                }
                """)
        bandField = CIColorKernel(
            source: """
                kernel vec4 bandField(__sample field, float yStart, float span, float stretch) {
                    float t = clamp((destCoord().y - yStart) / span, 0.0, 1.0);
                    return vec4(field.r, field.g + stretch * span * t, 0.0, 1.0);
                }
                """)
        sampler = CIKernel(
            source: """
                kernel vec4 displacedSample(sampler image, sampler field) {
                    vec2 d = sample(field, samplerCoord(field)).rg;
                    return sample(image, samplerTransform(image, destCoord() - d));
                }
                """)
    }

    /// 원소마다 limit를 적용한 뒤 한 번 샘플링한다. 남는 원소가 없으면 입력을 그대로 돌려준다.
    func apply(_ primitives: [ShapePrimitive], to image: CIImage, extent: CGRect, limit: Double) throws -> CIImage {
        let effective = primitives.map { $0.limited(to: limit) }.filter { !$0.isIdentity }
        guard !effective.isEmpty else { return image }
        guard let sampler else { throw MellowError.warpUnavailable }
        let field = try displacementField(effective, extent: extent)
        let margin = effective.reduce(Self.roiPadding) { $0 + $1.maxDisplacement }
        let arguments: [Any] = [image.clampedToExtent(), field]
        let warped = sampler.apply(
            extent: extent,
            roiCallback: { index, rect in
                index == Self.imageArgumentIndex ? rect.insetBy(dx: -margin, dy: -margin) : rect
            },
            arguments: arguments)
        guard let warped else { throw MellowError.renderFailed }
        return warped.cropped(to: extent)
    }

    /// 원소들의 이동량 합. 0에서 시작해 원소마다 색 커널 하나를 이어 붙인다.
    func displacementField(_ primitives: [ShapePrimitive], extent: CGRect) throws -> CIImage {
        var field = CIImage(color: CIColor(red: 0, green: 0, blue: 0, alpha: 1)).cropped(to: extent)
        for primitive in primitives {
            field = try accumulate(primitive, onto: field, extent: extent)
        }
        return field
    }

    /// CPU 참조. 원소마다 limit를 적용한 이동량의 합.
    static func displacement(at point: CGPoint, of primitives: [ShapePrimitive], limit: Double) -> CGVector {
        primitives.reduce(CGVector.zero) { sum, primitive in
            let shift = primitive.limited(to: limit).displacement(at: point)
            return CGVector(dx: sum.dx + shift.dx, dy: sum.dy + shift.dy)
        }
    }

    private func accumulate(_ primitive: ShapePrimitive, onto field: CIImage, extent: CGRect) throws -> CIImage {
        let kernel: CIColorKernel?
        let arguments: [Any]
        switch primitive {
        case .push(let center, let vector, let radius):
            kernel = pushField
            arguments = [field, CIVector(x: center.x, y: center.y), CIVector(x: vector.dx, y: vector.dy), radius]
        case .scale(let center, let factor, let radius):
            kernel = scaleField
            arguments = [field, CIVector(x: center.x, y: center.y), factor, radius]
        case .band(let yStart, let yEnd, let stretch):
            kernel = bandField
            arguments = [field, yStart, yEnd - yStart, stretch]
        }
        guard let kernel else { throw MellowError.warpUnavailable }
        guard let output = kernel.apply(extent: extent, arguments: arguments) else { throw MellowError.renderFailed }
        return output
    }
}
