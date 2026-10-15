import CoreImage
import MellowShared

/// 얼굴형·체형 이동 원소를 이동량 지도 하나로 더해 한 번만 샘플링한다. 결과는 out(p) = in(p − D(p))다.
/// push·scale은 R = dx, G = dy(픽셀)인 작업 형식 float 지도에 그리고, 다리 길게 띠는 지도에 그리지 않고
/// 샘플링 커널이 균일 인자로 같은 식을 더한다. 띠를 지도에 그리면 사진 가로 전체 크기 중간 버퍼(48MP 약 384MB)가 생기고
/// 512px 넘는 이동이 반정밀도 지도에서 0.5px 계단이 되기 때문이다. 띠는 한 번에 하나만 받는다.
/// 지도 색 커널 2개와 샘플링 일반 커널 1개를 감싸는 유일한 자리. Metal로 바꿀 때 이 타입만 바꾼다.
/// CIWarpKernel은 균일 인자만 받고 이미지를 읽을 수 없어 지도를 샘플링하려면 일반 커널이 필요하다.
final class DisplacementWarp: @unchecked Sendable {
    static let shared = DisplacementWarp()

    /// 샘플링 커널이 식으로 더하는 띠의 최대 개수. 체형 리그는 다리 길게 띠 하나만 만든다.
    static let maximumBands = 1
    /// ROI를 최대 이동보다 이만큼(픽셀) 더 넓혀 쌍선형 샘플링이 잘리지 않게 한다.
    private static let roiPadding: CGFloat = 2
    /// 샘플링 커널에서 입력 이미지 인자의 순서. ROI 콜백이 인덱스로 구분한다.
    private static let imageArgumentIndex: Int32 = 0
    /// 띠가 없을 때 샘플링 커널에 넘기는 (시작, 길이, 늘림). 늘림이 0이라 이동이 없다.
    private static let noBand = CIVector(x: 0, y: 1, z: 0)
    /// 지도에 그릴 원소가 없을 때 넘기는 지도의 크기(픽셀). 이 밖은 투명(이동 0)으로 읽힌다.
    private static let emptyFieldSize = CGSize(width: 1, height: 1)

    private let pushField: CIColorKernel?
    private let scaleField: CIColorKernel?
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
        sampler = CIKernel(
            source: """
                kernel vec4 displacedSample(sampler image, sampler field, vec3 band) {
                    vec2 d = sample(field, samplerCoord(field)).rg;
                    float t = clamp((destCoord().y - band.x) / band.y, 0.0, 1.0);
                    d.y += band.z * band.y * t * t * (3.0 - 2.0 * t);
                    return sample(image, samplerTransform(image, destCoord() - d));
                }
                """)
    }

    /// 원소마다 limit를 적용한 뒤 한 번 샘플링한다. 남는 원소가 없으면 입력을 그대로 돌려준다.
    /// 샘플링은 region(기본은 원소 영향 경계 합집합) 안에서만 하고 밖은 입력 픽셀을 그대로 둔다.
    /// 지도는 push·scale 경계 안에서만 그린다. region은 전체 extent와 비교하는 테스트가 넘긴다.
    func apply(
        _ primitives: [ShapePrimitive], to image: CIImage, extent: CGRect, limit: Double, region: CGRect? = nil
    ) throws -> CIImage {
        let effective = primitives.map { $0.limited(to: limit) }.filter { !$0.isIdentity }
        guard !effective.isEmpty else { return image }
        let bands = effective.filter(\.isBand)
        guard bands.count <= Self.maximumBands else { throw MellowError.renderFailed }
        guard let sampler else { throw MellowError.warpUnavailable }
        let patch = (region ?? Self.influenceBounds(effective, extent: extent)).intersection(extent).integral
        guard !patch.isEmpty else { return image }
        let mapped = effective.filter { !$0.isBand }
        let fieldRect = Self.fieldBounds(mapped, extent: extent).intersection(patch)
        let field =
            fieldRect.isEmpty
            ? Self.emptyField(at: patch.origin) : try displacementField(mapped, extent: fieldRect)
        let margin = effective.reduce(Self.roiPadding) { $0 + $1.maxDisplacement }
        let arguments: [Any] = [image.clampedToExtent(), field, Self.bandVector(bands.first)]
        let warped = sampler.apply(
            extent: patch,
            roiCallback: { index, rect in
                index == Self.imageArgumentIndex ? rect.insetBy(dx: -margin, dy: -margin) : rect
            },
            arguments: arguments)
        guard let warped else { throw MellowError.renderFailed }
        return Self.replacing(patch, of: image, with: warped).cropped(to: extent)
    }

    /// 원소들이 바꿀 수 있는 픽셀을 덮는 사각형을 extent 안 픽셀 경계로 맞춘다. limit를 적용한 원소를 받는다.
    /// push·scale은 중심 둘레 반지름 + 최대 이동 + ROI 여백, 띠는 시작 행 + 여유부터 띠 쪽 먼 가장자리까지 가로 전체다.
    static func influenceBounds(_ primitives: [ShapePrimitive], extent: CGRect) -> CGRect {
        let union = primitives.reduce(CGRect.null) { bounds, primitive in
            bounds.union(influence(of: primitive, extent: extent))
        }
        return union.intersection(extent).integral
    }

    /// 이동량 지도를 그릴 사각형. push·scale 경계의 합집합이고 띠는 넣지 않는다. 띠만 있으면 null.
    static func fieldBounds(_ primitives: [ShapePrimitive], extent: CGRect) -> CGRect {
        influenceBounds(primitives.filter { !$0.isBand }, extent: extent)
    }

    private static func influence(of primitive: ShapePrimitive, extent: CGRect) -> CGRect {
        let reach = primitive.maxDisplacement + roiPadding
        switch primitive {
        case .push(let center, _, let radius), .scale(let center, _, let radius):
            let half = radius + reach
            return CGRect(x: center.x - half, y: center.y - half, width: 2 * half, height: 2 * half)
        case .band(let yStart, let yEnd, _):
            // 시작 행 반대쪽은 이동이 0이라 빼고, 시작 행부터 띠 쪽 먼 가장자리까지만 움직인다.
            let top = yEnd < yStart ? yStart + reach : extent.maxY
            let bottom = yEnd < yStart ? extent.minY : yStart - reach
            return CGRect(x: extent.minX, y: bottom, width: extent.width, height: top - bottom)
        }
    }

    /// region 안은 patch, 밖은 image. 마스크로 고르므로 알파가 있어도 둘이 섞이지 않고 밖은 입력 값 그대로다.
    /// 샘플링 커널은 출력 extent 밖에서도 값을 내므로(투명이 아니다) patch를 잘라 얹는 합성은 쓰지 않는다.
    private static func replacing(_ region: CGRect, of image: CIImage, with patch: CIImage) -> CIImage {
        let mask = CIImage(color: .white).cropped(to: region)
        return patch.applyingFilter(
            "CIBlendWithMask", parameters: [kCIInputBackgroundImageKey: image, kCIInputMaskImageKey: mask])
    }

    /// 띠만 있을 때의 지도. 한 픽셀 이동 0이고 그 밖은 투명이라 샘플링 커널이 이동 0으로 읽는다.
    private static func emptyField(at origin: CGPoint) -> CIImage {
        CIImage(color: CIColor(red: 0, green: 0, blue: 0, alpha: 1))
            .cropped(to: CGRect(origin: origin, size: emptyFieldSize))
    }

    /// 샘플링 커널의 띠 인자 (시작 행, 길이, 늘림).
    private static func bandVector(_ band: ShapePrimitive?) -> CIVector {
        guard case .band(let yStart, let yEnd, let stretch)? = band else { return noBand }
        return CIVector(x: yStart, y: yEnd - yStart, z: stretch)
    }

    /// push·scale 원소들의 이동량 합. 0에서 시작해 원소마다 색 커널 하나를 이어 붙인다. 띠는 건너뛴다.
    func displacementField(_ primitives: [ShapePrimitive], extent: CGRect) throws -> CIImage {
        var field = CIImage(color: CIColor(red: 0, green: 0, blue: 0, alpha: 1)).cropped(to: extent)
        for primitive in primitives where !primitive.isBand {
            field = try accumulate(primitive, onto: field, extent: extent)
        }
        return field
    }

    /// CPU 참조. 원소마다 limit를 적용한 이동량의 합(띠 포함).
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
        case .band:
            return field
        }
        guard let kernel else { throw MellowError.warpUnavailable }
        guard let output = kernel.apply(extent: extent, arguments: arguments) else { throw MellowError.renderFailed }
        return output
    }
}
