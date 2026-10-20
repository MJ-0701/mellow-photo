import CoreImage
import MellowShared

/// 피부 정밀 중 영역 하나에 거는 보정(주름 밝히기·붉은기). SkinStage가 대상 얼굴마다 부른다.
enum SkinRefinement {
    /// 어두운 주름 띠를 둘레 "피부" 밝기 쪽으로 올린다.
    /// 기준은 skinMask × (1 − 띠)로 가중한 넓은 평균이라 눈·눈썹·입술·머리카락과 띠 자신이 섞이지 않는다.
    /// region.bounds 안에서만 계산하고 마스크 밖은 입력 바이트 그대로다.
    static func liftFold(
        _ image: CIImage, region: FaceRegions.RegionMask, skinMask: CIImage, faceWidth: CGFloat, amount: Double,
        tuning: RenderTuning, extent: CGRect
    ) throws -> CIImage {
        guard amount > 0 else { return image }
        let lowRadius = max(tuning.skinBlurMinimumRadius, Double(faceWidth) * tuning.foldLowBandFraction)
        let surroundRadius = max(tuning.skinBlurMinimumRadius, Double(faceWidth) * tuning.foldSurroundFraction)
        let black = CIImage(color: .black).cropped(to: extent)
        let outsideBand = region.image.composited(over: black).applyingFilter("CIColorInvert").cropped(to: extent)
        let weight = skinMask.composited(over: black)
            .applyingFilter("CIMultiplyCompositing", parameters: [kCIInputBackgroundImageKey: outsideBand])
            .cropped(to: extent)
        let wide = FrequencySeparation.maskedMean(image, mask: weight, radius: surroundRadius)
        let lifted = try SkinKernels.shared.foldLift(
            image: image, low: FrequencySeparation.blurred(image, radius: lowRadius), wideNumerator: wide.numerator,
            wideDenominator: wide.denominator, amount: amount * tuning.foldLiftMax, maxGain: tuning.foldLiftMaxGain,
            lumaFloor: tuning.foldLumaFloor, extent: region.bounds)
        return MaskBuilder.blend(lifted, over: image, mask: region.image).cropped(to: extent)
    }

    /// 붉은기. value < 0은 기준(reference, 감마)보다 붉은 만큼만 줄이고(맑게), value > 0은 Cr을 고르게 더한다(혈색).
    /// 감마로 바꿔 계산하고 선형으로 되돌린다. mask 밖은 입력 바이트 그대로다.
    static func adjustRedness(
        _ image: CIImage, mask: CIImage, bounds: CGRect, reference: CIImage, value: Double, tuning: RenderTuning,
        extent: CGRect
    ) throws -> CIImage {
        guard value != 0, !bounds.isEmpty else { return image }
        let encoded = image.applyingFilter("CILinearToSRGBToneCurve")
        let clear = value < 0 ? -value * tuning.rednessClearMax : 0
        let flush = value > 0 ? value * tuning.rednessFlushMax : 0
        let shifted = try SkinKernels.shared.redness(
            encoded: encoded, reference: reference, clear: clear, flush: flush, extent: bounds
        ).applyingFilter("CISRGBToneCurveToLinear")
        return MaskBuilder.blend(shifted, over: image, mask: mask).cropped(to: extent)
    }
}
