import CoreImage
import MellowShared

/// 눈 또렷하게·치아 미백·입술 생기. 대상 얼굴마다 FaceRegions 마스크 안에서만 바꾸고 마스크 밖 픽셀은 그대로 둔다.
/// 색 계산은 FeatureKernels(sRGB 감마 BT.601 YCbCr)가 하고, 마스크 영역(bounds)만 계산한 뒤 원본 위에 합성한다.
/// 값은 AdjustmentRange.unit으로 직접 자른다. 프리셋·일괄 적용 값은 편집 규칙의 클램프를 거치지 않는다.
struct FeatureStage: RenderStage {
    let name = "feature"

    /// 홍채 선명하게 반지름의 하한(픽셀). 이보다 작으면 CISharpenLuminance가 거의 효과가 없다.
    private static let minimumSharpenRadius: CGFloat = 1

    func apply(_ image: CIImage, in context: RenderContext) throws -> CIImage {
        let values = Self.clamped(context.recipe.portrait.features)
        guard values.hasEffect, !context.targetFaces.isEmpty else { return image }
        var result = image
        for face in context.targetFaces {
            result = try brightenEyes(result, face: face, amount: values.eyeBrighten, context: context)
            result = try whitenTeeth(result, face: face, amount: values.teethWhiten, context: context)
            result = try reviveLips(result, face: face, amount: values.lipVitality, context: context)
        }
        return result.cropped(to: context.extent)
    }

    /// 0…1로 자른다. 유한하지 않은 값은 RenderPipeline이 먼저 거절한다.
    static func clamped(_ features: FeatureAdjustments) -> FeatureAdjustments {
        var copy = features
        for key in FeatureKey.allCases {
            copy[key] = AdjustmentRange.clamped(features[key], to: AdjustmentRange.unit)
        }
        return copy
    }

    /// 흰자를 흰색 쪽으로 섞고 눈동자 원 안 휘도를 선명하게 한다.
    private func brightenEyes(_ image: CIImage, face: FaceGeometry, amount: Double, context: RenderContext) throws
        -> CIImage
    {
        let tuning = context.tuning
        let extent = context.extent
        guard amount > 0,
            let eyes = FaceRegions.eyeMask(face: face, extent: extent, tuning: tuning, cache: context.regionMasks)
        else { return image }
        let kernels = FeatureKernels.shared
        let sclera = try kernels.weight(of: image, rule: .sclera(tuning), extent: eyes.bounds)
        let lifted = try kernels.shifted(image, by: ToneShift(lift: tuning.eyeWhiteLift * amount), extent: eyes.bounds)
        let brightened = MaskBuilder.blend(lifted, over: image, mask: Self.product(eyes.image, sclera, extent: extent))
            .cropped(to: extent)
        let largest = FaceRegions.irisCircles(face: face, extent: extent, tuning: tuning).map(\.radius).max()
        guard let largest,
            let iris = FaceRegions.irisMask(face: face, extent: extent, tuning: tuning, cache: context.regionMasks)
        else { return brightened }
        let radius = max(Self.minimumSharpenRadius, largest * CGFloat(tuning.eyeIrisSharpenRadiusFraction))
        let sharpened = brightened.clampedToExtent()
            .applyingFilter(
                "CISharpenLuminance",
                parameters: ["inputSharpness": tuning.eyeIrisSharpen * amount, kCIInputRadiusKey: radius]
            )
            .cropped(to: iris.bounds)
        return MaskBuilder.blend(sharpened, over: brightened, mask: iris.image).cropped(to: extent)
    }

    /// 치아의 노란기를 빼고 흰색 쪽으로 섞는다. 다문 입은 마스크가 없어 건너뛴다.
    private func whitenTeeth(_ image: CIImage, face: FaceGeometry, amount: Double, context: RenderContext) throws
        -> CIImage
    {
        let tuning = context.tuning
        guard amount > 0,
            let teeth = try FaceRegions.teethMask(
                face: face, image: image, extent: context.extent, tuning: tuning, cache: context.regionMasks)
        else { return image }
        let shift = ToneShift(lift: tuning.teethLift * amount, yellowRemoval: tuning.teethYellowRemoval * amount)
        let whitened = try FeatureKernels.shared.shifted(image, by: shift, extent: teeth.bounds)
        return MaskBuilder.blend(whitened, over: image, mask: teeth.image).cropped(to: context.extent)
    }

    /// 입술(바깥 − 안쪽)의 채도를 올리고 붉은기를 조금 더한다.
    private func reviveLips(_ image: CIImage, face: FaceGeometry, amount: Double, context: RenderContext) throws
        -> CIImage
    {
        let tuning = context.tuning
        guard amount > 0,
            let lips = FaceRegions.lipMask(
                face: face, extent: context.extent, tuning: tuning, cache: context.regionMasks)
        else { return image }
        let shift = ToneShift(saturation: 1 + tuning.lipSaturationMax * amount, redness: tuning.lipRednessMax * amount)
        let revived = try FeatureKernels.shared.shifted(image, by: shift, extent: lips.bounds)
        return MaskBuilder.blend(revived, over: image, mask: lips.image).cropped(to: context.extent)
    }

    /// 두 회색 마스크의 곱. b는 bounds 밖이 비어 있을 수 있어 검정 위에 얹는다.
    private static func product(_ a: CIImage, _ b: CIImage, extent: CGRect) -> CIImage {
        let black = CIImage(color: .black).cropped(to: extent)
        let background = b.composited(over: black)
        return a.applyingFilter("CIMultiplyCompositing", parameters: [kCIInputBackgroundImageKey: background])
            .cropped(to: extent)
    }
}
