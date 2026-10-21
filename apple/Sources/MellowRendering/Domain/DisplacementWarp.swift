import CoreImage
import MellowShared

/// 얼굴형·체형 이동 원소를 이동량 지도 하나로 더해 한 번만 샘플링한다. 결과는 out(p) = in(p − D(p))다.
/// push·scale은 R = dx, G = dy(픽셀)인 작업 형식 float 지도에 그리고, 다리 길게 띠는 지도에 그리지 않고
/// 샘플링 커널이 균일 인자로 같은 식을 더한다. 띠를 지도에 그리면 사진 가로 전체 크기 중간 버퍼(48MP 약 384MB)가 생기고
/// 512px 넘는 이동이 반정밀도 지도에서 0.5px 계단이 되기 때문이다. 띠는 한 번에 하나만 받는다.
/// 보호 워프(스펙 5.4)는 묶음(ShapeGroup)마다 지도를 그려 보호 가중치를 곱하고 더한 뒤 한 번만 샘플링한다.
/// 지도 색 커널 4개(push·scale·보호 가중치·합)와 샘플링 일반 커널 1개를 감싸는 유일한 자리. Metal로 바꿀 때 이 타입만 바꾼다.
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
    /// 보호 가중치 커널이 받는 묶음당 팔 캡슐 수.
    static let maximumGuards = 4
    /// 캡슐이 없는 자리에 넘기는 선분과 (반지름, feather). 반지름 0이라 막지 않는다.
    private static let absentSegment = CIVector(x: 0, y: 0, z: 0, w: 0)
    private static let absentSize = CIVector(x: 0, y: 0)

    private let pushField: CIColorKernel?
    private let scaleField: CIColorKernel?
    private let protectedField: CIColorKernel?
    private let sumField: CIColorKernel?
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
        // 배경 가중치 clamp(gain × own) × (1 − others)에 팔 보호 Π(1 − c_i)를 곱한다.
        // c_i는 캡슐 반지름 안 1, 반지름 + feather 밖 0인 smoothstep이고 반지름 0은 캡슐이 없다는 뜻이다.
        protectedField = CIColorKernel(
            source: """
                float capsuleCover(vec2 p, vec4 segment, vec2 size) {
                    vec2 ab = segment.zw - segment.xy;
                    float span = dot(ab, ab);
                    float h = span > 0.0 ? clamp(dot(p - segment.xy, ab) / span, 0.0, 1.0) : 0.0;
                    float d = distance(p, segment.xy + ab * h);
                    float cover = 1.0 - smoothstep(size.x, size.x + max(size.y, 0.0001), d);
                    return size.x > 0.0 ? cover : 0.0;
                }
                kernel vec4 protectedField(
                    __sample field, __sample own, __sample others, float gain,
                    vec4 s0, vec2 r0, vec4 s1, vec2 r1, vec4 s2, vec2 r2, vec4 s3, vec2 r3
                ) {
                    vec2 p = destCoord();
                    float arm = (1.0 - capsuleCover(p, s0, r0)) * (1.0 - capsuleCover(p, s1, r1));
                    arm *= (1.0 - capsuleCover(p, s2, r2)) * (1.0 - capsuleCover(p, s3, r3));
                    float background = clamp(gain * own.r, 0.0, 1.0) * (1.0 - clamp(others.r, 0.0, 1.0));
                    return vec4(field.rg * (background * arm), 0.0, 1.0);
                }
                """)
        sumField = CIColorKernel(
            source: """
                kernel vec4 sumField(__sample first, __sample second) {
                    return vec4(first.rg + second.rg, 0.0, 1.0);
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
        let patch = (region ?? Self.influenceBounds(effective, extent: extent)).intersection(extent).integral
        guard !patch.isEmpty else { return image }
        let mapped = effective.filter { !$0.isBand }
        let fieldRect = Self.fieldBounds(mapped, extent: extent).intersection(patch)
        let field =
            fieldRect.isEmpty
            ? Self.emptyField(at: patch.origin) : try displacementField(mapped, extent: fieldRect)
        return try sample(image, field: field, effective: effective, patch: patch, extent: extent)
    }

    /// 묶음마다 보호 가중치를 곱한 지도를 더해 한 번 샘플링한다(스펙 5.4).
    /// 모든 묶음의 ownMask가 nil이면 원소를 이어 apply(_:to:extent:limit:)로 그린다(보호 없음, 같은 바이트).
    /// 다리 띠는 지도에 그리지 않고 샘플링 커널이 더하므로 보호를 받지 않는다.
    func apply(
        groups: [ShapeGroup], to image: CIImage, extent: CGRect, limit: Double, tuning: RenderTuning
    ) throws -> CIImage {
        guard Self.isProtected(groups) else {
            return try apply(groups.flatMap(\.primitives), to: image, extent: extent, limit: limit)
        }
        let limited = groups.map { Self.limited($0, to: limit) }
        let effective = limited.flatMap(\.primitives)
        guard !effective.isEmpty else { return image }
        guard effective.filter(\.isBand).count <= Self.maximumBands else { throw MellowError.renderFailed }
        let patch = Self.influenceBounds(effective, extent: extent)
        guard !patch.isEmpty else { return image }
        let field =
            try protectedSum(limited, extent: extent, tuning: tuning) ?? Self.emptyField(at: patch.origin)
        return try sample(image, field: field, effective: effective, patch: patch, extent: extent)
    }

    /// apply(groups:)가 샘플링하는 이동량 지도(띠 제외). 그릴 push·scale 원소가 없으면 nil이다.
    /// 테스트와 수용 테스트가 이동량을 직접 읽는다.
    func field(
        groups: [ShapeGroup], extent: CGRect, limit: Double, tuning: RenderTuning
    ) throws -> CIImage? {
        let limited = groups.map { Self.limited($0, to: limit) }
        guard Self.isProtected(groups) else {
            let mapped = limited.flatMap(\.primitives).filter { !$0.isBand }
            let rect = Self.fieldBounds(mapped, extent: extent)
            guard !rect.isNull, !rect.isEmpty else { return nil }
            return try displacementField(mapped, extent: rect)
        }
        return try protectedSum(limited, extent: extent, tuning: tuning)
    }

    /// 하나라도 사람 마스크가 있으면 보호 경로로 그린다.
    private static func isProtected(_ groups: [ShapeGroup]) -> Bool {
        groups.contains { $0.ownMask != nil }
    }

    /// 원소마다 limit를 적용하고 아무것도 옮기지 않는 원소를 뺀 묶음.
    private static func limited(_ group: ShapeGroup, to limit: Double) -> ShapeGroup {
        var result = group
        result.primitives = group.primitives.map { $0.limited(to: limit) }.filter { !$0.isIdentity }
        return result
    }

    /// 묶음 지도에 보호 가중치를 곱해 더한다. 그릴 원소가 없으면 nil이다.
    private func protectedSum(_ groups: [ShapeGroup], extent: CGRect, tuning: RenderTuning) throws -> CIImage? {
        var total: CIImage?
        for group in groups {
            guard let weighted = try protectedField(group, extent: extent, tuning: tuning) else { continue }
            guard let previous = total else {
                total = weighted
                continue
            }
            guard let sumField else { throw MellowError.warpUnavailable }
            let rect = previous.extent.union(weighted.extent)
            guard let sum = sumField.apply(extent: rect, arguments: [previous, weighted]) else {
                throw MellowError.renderFailed
            }
            total = sum
        }
        return total
    }

    /// 묶음 하나의 지도에 배경·이웃·팔 보호 가중치를 곱한다. ownMask가 nil이면 가중치 1이다.
    /// σ = max(묶음 최대 이동 × shapeBackgroundSigmaRatio, 짧은 변 × shapeBackgroundSigmaMinimum)이고 extent 픽셀이다.
    /// 사람 마스크는 분석기 해상도 근처에서 흐린 뒤 extent로 늘린다(nativeBlurred).
    /// 다른 사람 마스크는 같은 배치로 늘려 흐리지 않고 최댓값으로 합친다.
    private func protectedField(_ group: ShapeGroup, extent: CGRect, tuning: RenderTuning) throws -> CIImage? {
        let mapped = group.primitives.filter { !$0.isBand }
        let rect = Self.fieldBounds(mapped, extent: extent)
        guard !rect.isNull, !rect.isEmpty else { return nil }
        let field = try displacementField(mapped, extent: rect)
        guard let own = group.ownMask else { return field }
        guard group.guards.count <= Self.maximumGuards else { throw MellowError.renderFailed }
        guard let protectedField else { throw MellowError.warpUnavailable }
        let largest = mapped.map(\.maxDisplacement).max() ?? 0
        let shortSide = min(extent.width, extent.height)
        let shiftSigma = largest * CGFloat(tuning.shapeBackgroundSigmaRatio)
        let sigma = max(shiftSigma, shortSide * CGFloat(tuning.shapeBackgroundSigmaMinimum))
        let blurred = Self.nativeBlurred(own, sigma: sigma, extent: extent)
        let ownWeight = BackgroundStage.personMask(blurred, extent: extent, feather: 0).cropped(to: rect)
        var arguments: [Any] = [field, ownWeight, Self.combinedOthers(group.otherMasks, extent: extent)]
        arguments.append(tuning.shapeBackgroundGain)
        for index in 0..<Self.maximumGuards {
            arguments += Self.guardArguments(group.guards.indices.contains(index) ? group.guards[index] : nil)
        }
        guard let output = protectedField.apply(extent: rect, arguments: arguments) else {
            throw MellowError.renderFailed
        }
        return output
    }

    /// 사람 마스크를 분석기 해상도 근처에서 흐린다. sigma는 extent 픽셀이고 마스크 픽셀로 바꿔 쓴다.
    /// 48MP 내보내기에서 늘린 마스크를 큰 σ로 흐리는 비용을 마스크 크기 비용으로 줄인다.
    /// 분석기 마스크는 사진과 가로세로 비가 다를 수 있다(Vision 인물 마스크 512×384를 세로 사진에 쓰면 두 축 배율이 1.8배 차이).
    /// CIGaussianBlur는 등방성이라 먼저 두 축 배율을 큰 쪽(sharedScale)에 맞춰 덜 촘촘한 축만 늘린 뒤 sigma × sharedScale로 흐린다.
    /// 그래서 extent에서 두 축 모두 정확히 sigma다. 늘리는 축은 마스크 해상도를 넘지 않는 만큼만 커진다.
    /// 결과는 그 크기 그대로라 BackgroundStage.personMask가 extent로 늘린다.
    private static func nativeBlurred(_ mask: CIImage, sigma: CGFloat, extent: CGRect) -> CIImage {
        let source = mask.extent
        let scaleX = source.width / extent.width
        let scaleY = source.height / extent.height
        let sharedScale = max(scaleX, scaleY)
        let uniform = mask.transformed(by: CGAffineTransform(scaleX: sharedScale / scaleX, y: sharedScale / scaleY))
        return uniform.clampedToExtent()
            .applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: sigma * sharedScale])
            .cropped(to: uniform.extent)
    }

    /// 다른 사람 마스크들을 extent에 늘려 최댓값으로 합친다. 없으면 검정(이웃 없음)이다.
    private static func combinedOthers(_ masks: [CIImage], extent: CGRect) -> CIImage {
        let black = CIImage(color: CIColor(red: 0, green: 0, blue: 0, alpha: 1)).cropped(to: extent)
        return masks.reduce(black) { combined, mask in
            BackgroundStage.personMask(mask, extent: extent, feather: 0)
                .applyingFilter("CIMaximumCompositing", parameters: [kCIInputBackgroundImageKey: combined])
                .cropped(to: extent)
        }
    }

    /// 캡슐 하나의 커널 인자 (선분, (반지름, feather)). 없으면 반지름 0이다.
    private static func guardArguments(_ shapeGuard: ShapeGuard?) -> [Any] {
        guard case .capsule(let start, let end, let radius, let feather)? = shapeGuard else {
            return [absentSegment, absentSize]
        }
        return [CIVector(x: start.x, y: start.y, z: end.x, w: end.y), CIVector(x: radius, y: feather)]
    }

    /// 지도와 띠로 patch 안만 샘플링하고 밖은 입력 픽셀을 그대로 둔다.
    private func sample(
        _ image: CIImage, field: CIImage, effective: [ShapePrimitive], patch: CGRect, extent: CGRect
    ) throws -> CIImage {
        guard let sampler else { throw MellowError.warpUnavailable }
        let bands = effective.filter(\.isBand)
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
