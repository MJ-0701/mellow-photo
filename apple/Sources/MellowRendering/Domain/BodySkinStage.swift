import CoreImage
import MellowShared

/// 보이는 피부 전체(얼굴 포함)의 밝기·톤과 얼굴 밖 피부의 매끄럽게.
/// 마스크 = 인물 마스크 × 가장 큰 얼굴의 볼 기준 피부색 가중치 × (1 − 모든 얼굴의 눈·눈썹·입).
/// 매끄럽게는 거기서 얼굴 피부 다각형 전체(눈가·입가 포함, 잘라내지 않음)를 뺀다.
/// 얼굴이 없으면 입력 그대로, 인물 마스크가 없으면 얼굴 둘레 대체 영역을 쓴다(오류 아님).
/// 값은 AdjustmentRange로 직접 자른다.
/// 대상 얼굴 선택과 무관하다.
struct BodySkinStage: RenderStage {
    let name = "bodySkin"

    func apply(_ image: CIImage, in context: RenderContext) throws -> CIImage {
        let values = Self.clamped(context.recipe.bodySkin)
        guard values.hasEffect,
            let toneMask = try Self.toneMask(
                image, faces: context.faces, personMask: context.personMask,
                extent: context.extent, tuning: context.tuning, regionMasks: context.regionMasks)
        else { return image }
        let extent = context.extent
        let tuning = context.tuning
        // 밝기 뒤에 매끄럽게 하면 밝기 경계가 번지므로 매끄럽게가 먼저다.
        var result = image
        if values.smoothing > 0 {
            var smoothMask = toneMask
            if let face = FaceRegions.wholeFaceMask(
                faces: context.faces, extent: extent, tuning: tuning, cache: context.regionMasks)
            {
                smoothMask = Self.product(toneMask, Self.inverted(face.image, extent: extent), extent: extent)
            }
            let smooth = try FrequencySeparation.smoothed(
                result, bounds: extent, radii: Self.bodyRadii(shortSide: context.shortSide, tuning: tuning),
                smoothing: values.smoothing, tuning: tuning)
            result = MaskBuilder.blend(smooth, over: result, mask: smoothMask).cropped(to: extent)
        }
        if values.brightness > 0 || values.tone != 0 {
            let shift = ToneShift(
                lift: values.brightness * tuning.bodySkinLiftMax, redness: values.tone * tuning.bodySkinToneMax,
                blueness: -values.tone * tuning.bodySkinToneMax)
            let shifted = try FeatureKernels.shared.shifted(result, by: shift, extent: extent)
            result = MaskBuilder.blend(shifted, over: result, mask: toneMask).cropped(to: extent)
        }
        return result
    }

    /// 실제 단계와 준비 계측이 공유하는 원래 밝기/톤 마스크. 결함이나 개선량은 판정하지 않는다.
    static func toneMask(
        _ image: CIImage, faces: [FaceGeometry], personMask: CIImage?, extent: CGRect,
        tuning: RenderTuning, regionMasks: RegionMaskCache?
    ) throws -> CIImage? {
        guard let reference = Self.referenceFace(faces) else { return nil }
        let encoded = image.applyingFilter("CILinearToSRGBToneCurve")
        // 기준색은 skin 단계 뒤 입력에서 잰다. 마스크를 거는 얼굴 픽셀과 같은 이미지라야 얼굴 피부 가중치가 1에 머문다.
        guard let cheeks = FaceRegions.cheekAverages(of: encoded, face: reference, extent: extent) else { return nil }
        let area: CIImage
        if let person = personMask, !person.extent.isEmpty, !person.extent.isInfinite {
            let feather = max(
                CGFloat(tuning.skinBlurMinimumRadius),
                min(extent.width, extent.height) * CGFloat(tuning.bodySkinMaskFeather))
            area = BackgroundStage.personMask(person, extent: extent, feather: feather)
        } else {
            area = Self.fallbackPersonRegion(face: reference, extent: extent, tuning: tuning)
        }
        let chroma = try SkinKernels.shared.chromaWeight(
            of: encoded, left: cheeks.left, right: cheeks.right, sigma: tuning.bodySkinChromaSigma, extent: extent)
        var toneMask = Self.product(area, chroma, extent: extent)
        if let features = FaceRegions.featureMask(
            faces: faces, extent: extent, tuning: tuning, cache: regionMasks)
        {
            toneMask = Self.product(toneMask, Self.inverted(features.image, extent: extent), extent: extent)
        }
        return toneMask
    }

    /// 밝기·매끄럽게 0…1, 톤 −1…1. 유한하지 않은 값은 RenderPipeline이 먼저 거절한다.
    static func clamped(_ values: BodySkinAdjustments) -> BodySkinAdjustments {
        var copy = values
        for key in BodySkinKey.allCases {
            copy[key] = AdjustmentRange.clamped(values[key], to: AdjustmentRange.bodySkin(key))
        }
        return copy
    }

    /// 인물 마스크가 없을 때의 사람 영역.
    /// 얼굴 상자를 가로 bodySkinFallbackWidthScale배, 상자 위끝에서 아래로 높이 × bodySkinFallbackHeightScale만큼 늘린 직사각형이다.
    /// 짧은 변 × bodySkinFallbackFeather로 흐린 부드러운 사각형이고 옷·배경은 피부색 가중치가 뺀다.
    static func fallbackPersonRegion(face: FaceGeometry, extent: CGRect, tuning: RenderTuning) -> CIImage {
        let box = FaceRegions.pixelRect(face.boundingBox, in: extent)
        let width = box.width * CGFloat(tuning.bodySkinFallbackWidthScale)
        let height = box.height * CGFloat(tuning.bodySkinFallbackHeightScale)
        let region = CGRect(x: box.midX - width / 2, y: box.maxY - height, width: width, height: height)
            .intersection(extent)
        let feather = max(
            CGFloat(tuning.skinBlurMinimumRadius),
            min(extent.width, extent.height) * CGFloat(tuning.bodySkinFallbackFeather))
        let black = CIImage(color: .black).cropped(to: extent)
        return CIImage(color: .white).cropped(to: region).composited(over: black).clampedToExtent()
            .applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: feather]).cropped(to: extent)
    }

    /// 기준색을 재는 얼굴. 상자 폭이 가장 큰 얼굴이고 없으면 nil.
    static func referenceFace(_ faces: [FaceGeometry]) -> FaceGeometry? {
        FaceRegions.widestFace(faces)
    }

    /// 몸 피부 대역 반지름. 얼굴 폭 대신 짧은 변에 비례한다.
    static func bodyRadii(shortSide: CGFloat, tuning: RenderTuning) -> (fine: Double, mid: Double) {
        let fine = max(tuning.skinBlurMinimumRadius, Double(shortSide) * tuning.bodySkinFineBandFraction)
        let mid = max(fine, Double(shortSide) * tuning.bodySkinMidBandFraction)
        return (fine, mid)
    }

    /// 두 회색 마스크의 곱. 둘 다 extent 밖이 비어 있을 수 있어 검정 위에 얹는다.
    private static func product(_ first: CIImage, _ second: CIImage, extent: CGRect) -> CIImage {
        let black = CIImage(color: .black).cropped(to: extent)
        let background = second.composited(over: black)
        return first.composited(over: black)
            .applyingFilter("CIMultiplyCompositing", parameters: [kCIInputBackgroundImageKey: background])
            .cropped(to: extent)
    }

    /// 1 − mask. extent 밖이 비어 있으면(검정) 1이 된다.
    private static func inverted(_ mask: CIImage, extent: CGRect) -> CIImage {
        mask.composited(over: CIImage(color: .black).cropped(to: extent)).applyingFilter("CIColorInvert")
            .cropped(to: extent)
    }
}
