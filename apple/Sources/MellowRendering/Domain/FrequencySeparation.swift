import CoreImage
import MellowShared

/// 피부를 낮은·중간·모공 세 대역으로 나눠 중간 대역(얼룩·잔주름)만 줄인다. 모공 대역은 그대로 둔다.
enum FrequencySeparation {
    /// 얼굴 폭에 비례한 두 반지름. fine은 모공 대역의 위쪽, mid는 중간 대역의 위쪽 경계.
    static func radii(faceWidth: CGFloat, tuning: RenderTuning) -> (fine: Double, mid: Double) {
        let fine = max(tuning.skinBlurMinimumRadius, Double(faceWidth) * tuning.fineBandFraction)
        let mid = max(fine, Double(faceWidth) * tuning.midBandFraction)
        return (fine, mid)
    }

    /// 가장자리를 늘려 흐린다. extent는 무한이다.
    static func blurred(_ image: CIImage, radius: Double) -> CIImage {
        image.clampedToExtent().applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: radius])
    }

    /// low + mid × (1 − smoothing × midReductionMax) + fine. bounds 밖은 계산하지 않는다(투명).
    static func smoothed(
        _ image: CIImage, bounds: CGRect, faceWidth: CGFloat, smoothing: Double, tuning: RenderTuning
    ) throws -> CIImage {
        let amount = min(1, max(0, smoothing))
        guard amount > 0, !bounds.isEmpty else { return image }
        // 지역 상수 이름을 radii로 하면 같은 이름의 정적 메서드를 가려 컴파일되지 않는다.
        let bandRadii = Self.radii(faceWidth: faceWidth, tuning: tuning)
        return try SkinKernels.shared.bandMix(
            image: image, fineBlur: blurred(image, radius: bandRadii.fine),
            midBlur: blurred(image, radius: bandRadii.mid), keep: 1 - amount * tuning.midReductionMax, extent: bounds)
    }

    /// 얼룩 고르기·번들거림이 들어간 대역 합성. mask는 세기 1 피부 마스크(넓은 평균의 가중치), reference는 볼 평균(선형, 무한 확장).
    /// toneEvening·shine이 모두 0이면 smoothed와 같은 경로·같은 바이트다.
    static func refined(
        _ image: CIImage, bounds: CGRect, faceWidth: CGFloat, mask: CIImage, reference: CIImage, smoothing: Double,
        toneEvening: Double, shine: Double, tuning: RenderTuning
    ) throws -> CIImage {
        let even = min(1, max(0, toneEvening)) * tuning.toneEveningMax
        let gloss = min(1, max(0, shine)) * tuning.shineReductionMax
        guard even > 0 || gloss > 0 else {
            return try smoothed(image, bounds: bounds, faceWidth: faceWidth, smoothing: smoothing, tuning: tuning)
        }
        guard !bounds.isEmpty else { return image }
        let bandRadii = Self.radii(faceWidth: faceWidth, tuning: tuning)
        let wideRadius = max(bandRadii.mid, Double(faceWidth) * tuning.toneBandFraction)
        let wide = maskedMean(image, mask: mask, radius: wideRadius)
        return try SkinKernels.shared.toneMix(
            image: image, fineBlur: blurred(image, radius: bandRadii.fine),
            midBlur: blurred(image, radius: bandRadii.mid),
            wideNumerator: wide.numerator, wideDenominator: wide.denominator, reference: reference,
            keep: 1 - min(1, max(0, smoothing)) * tuning.midReductionMax, even: even, shine: gloss,
            shineOffset: tuning.shineLumaOffset, shineRamp: tuning.shineLumaRamp, extent: bounds)
    }

    /// 마스크 가중 평균의 분자 blur(image × mask)와 분모 blur(mask). 나눗셈은 커널이 한다. 경계 밖 색이 평균에 섞이지 않는다.
    static func maskedMean(_ image: CIImage, mask: CIImage, radius: Double)
        -> (numerator: CIImage, denominator: CIImage)
    {
        let weighted = image.applyingFilter("CIMultiplyCompositing", parameters: [kCIInputBackgroundImageKey: mask])
        return (blurred(weighted, radius: radius), blurred(mask, radius: radius))
    }
}
