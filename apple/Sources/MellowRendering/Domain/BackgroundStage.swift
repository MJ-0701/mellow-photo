import CoreImage
import MellowShared

/// 인물 마스크 밖을 흐린다. 마스크를 extent로 키우고 짧은 변 × backgroundMaskFeather로 부드럽게 한 뒤 반전해
/// CIMaskedVariableBlur의 반지름 지도로 쓰고, 같은 마스크로 원본 위에 합성해 사람 영역(반전 마스크 0)은 원본 바이트로 둔다.
/// 마스크가 없으면(사람 없음·인물 분석 실패·준비 전) 입력을 그대로 돌려준다(스펙 1.4: 해당 단계만 건너뜀).
struct BackgroundStage: RenderStage {
    let name = "background"

    func apply(_ image: CIImage, in context: RenderContext) throws -> CIImage {
        let amount = AdjustmentRange.clamped(context.recipe.background.blur, to: AdjustmentRange.unit)
        guard amount > 0, let person = context.personMask, !person.extent.isEmpty, !person.extent.isInfinite else {
            return image
        }
        let extent = context.extent
        let tuning = context.tuning
        let feather = max(
            CGFloat(tuning.skinBlurMinimumRadius), context.shortSide * CGFloat(tuning.backgroundMaskFeather))
        let background = Self.backgroundMask(person, extent: extent, feather: feather)
        let radius = Double(context.shortSide) * tuning.backgroundBlurMaxFraction * amount
        let blurred = image.clampedToExtent()
            .applyingFilter("CIMaskedVariableBlur", parameters: ["inputMask": background, kCIInputRadiusKey: radius])
            .cropped(to: extent)
        return MaskBuilder.blend(blurred, over: image, mask: background).cropped(to: extent)
    }

    /// 배경 1·사람 0인 extent 크기 마스크. 인물 마스크(사람 1)를 extent에 맞게 가로·세로 따로 키운다(마스크 비율은 사진과 다를 수 있다).
    static func backgroundMask(_ person: CIImage, extent: CGRect, feather: CGFloat) -> CIImage {
        let source = person.extent
        let placement = CGAffineTransform(translationX: extent.minX, y: extent.minY)
            .scaledBy(x: extent.width / source.width, y: extent.height / source.height)
            .translatedBy(x: -source.minX, y: -source.minY)
        return person.transformed(by: placement).clampedToExtent()
            .applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: feather])
            .applyingFilter("CIColorInvert")
            .cropped(to: extent)
    }
}
