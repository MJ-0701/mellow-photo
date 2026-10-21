import CoreImage
import MellowShared

/// 사용자의 잡티·변형을 기록 순서대로 재생한다.
struct LocalEditStage: RenderStage {
    let name = "localEdit"

    func apply(_ image: CIImage, in context: RenderContext) throws -> CIImage {
        var result = image
        for operation in context.recipe.operations {
            switch operation {
            case .warp(let stroke):
                result = try Self.applyWarp(stroke, to: result, context: context)
            case .spot(let spot):
                result = Self.applySpot(spot, to: result, context: context)
            }
        }
        return result
    }

    static func applyWarp(_ stroke: WarpStroke, to image: CIImage, context: RenderContext) throws -> CIImage {
        guard stroke.radius > 0 else { return image }
        let tuning = context.tuning
        let radius = max(1, min(tuning.warpMaxRadiusFraction, stroke.radius) * context.shortSide)
        return try WarpKernel.shared.apply(
            to: image,
            extent: context.extent,
            center: context.pixelPoint(x: stroke.x, y: stroke.y),
            delta: CGVector(dx: stroke.dx * context.extent.width, dy: stroke.dy * context.extent.height),
            radius: radius,
            displacementLimit: tuning.warpDisplacementLimit)
    }

    /// 색 맞춤 복구(스펙 G5 5.1). 원본 패치의 질감(고주파)만 옮기고 밝기·색(저주파)은 대상 둘레 고리 평균에 맞춘다.
    /// 수동 잡티와 자동 잡티가 같은 함수를 쓴다. 커널이 실패하면 입력 그대로다.
    static func applySpot(_ spot: RetouchSpot, to image: CIImage, context: RenderContext) -> CIImage {
        guard spot.radius > 0 else { return image }
        let extent = context.extent
        let tuning = context.tuning
        let radius = min(tuning.spotMaxRadiusFraction, spot.radius) * context.shortSide
        let center = context.pixelPoint(x: spot.x, y: spot.y)
        let offset = CGAffineTransform(
            translationX: (spot.x - spot.sourceX) * extent.width, y: (spot.y - spot.sourceY) * extent.height)
        let source = image.clampedToExtent().transformed(by: offset)
        let patch = CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)
        let mask = MaskBuilder.ellipse(patch, extent: extent)
        // 대상 둘레 고리(패치 자신을 뺀 피부)의 평균이 복구 패치의 밝기·색이 된다.
        let innerRadius = radius * tuning.healRingInnerScale
        let inner = CGRect(
            x: center.x - innerRadius, y: center.y - innerRadius, width: innerRadius * 2, height: innerRadius * 2)
        let ring = MaskBuilder.ellipse(inner, extent: extent).applyingFilter("CIColorInvert").cropped(to: extent)
        let ringMean = FrequencySeparation.maskedMean(image, mask: ring, radius: radius * tuning.healRingRadiusScale)
        let sourceLow = FrequencySeparation.blurred(source, radius: radius * tuning.healLowBandScale)
        let area = patch.intersection(extent)
        guard !area.isEmpty,
            let healed = try? SkinKernels.shared.heal(
                source: source, sourceLow: sourceLow, ringNumerator: ringMean.numerator,
                ringDenominator: ringMean.denominator, lumaFloor: tuning.healLumaFloor, maxGain: tuning.healMaxGain,
                extent: area)
        else { return image }
        return MaskBuilder.blend(healed, over: image, mask: mask).cropped(to: extent)
    }
}
