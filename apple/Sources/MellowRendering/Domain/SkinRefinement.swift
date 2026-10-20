import CoreImage
import MellowShared

/// 피부 정밀 중 영역 하나에 거는 보정(주름 밝히기·붉은기). SkinStage가 대상 얼굴마다 부른다.
enum SkinRefinement {
    /// 어두운 주름 띠를 둘레 피부 밝기 쪽으로 올린다. region.bounds 안에서만 계산하고 마스크 밖은 입력 바이트 그대로다.
    static func liftFold(
        _ image: CIImage, region: FaceRegions.RegionMask, faceWidth: CGFloat, amount: Double, tuning: RenderTuning,
        extent: CGRect
    ) throws -> CIImage {
        guard amount > 0 else { return image }
        let lowRadius = max(tuning.skinBlurMinimumRadius, Double(faceWidth) * tuning.foldLowBandFraction)
        let surroundRadius = max(tuning.skinBlurMinimumRadius, Double(faceWidth) * tuning.foldSurroundFraction)
        let lifted = try SkinKernels.shared.foldLift(
            image: image, low: FrequencySeparation.blurred(image, radius: lowRadius),
            surround: FrequencySeparation.blurred(image, radius: surroundRadius), amount: amount * tuning.foldLiftMax,
            extent: region.bounds)
        return MaskBuilder.blend(lifted, over: image, mask: region.image).cropped(to: extent)
    }
}
