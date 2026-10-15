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
}
