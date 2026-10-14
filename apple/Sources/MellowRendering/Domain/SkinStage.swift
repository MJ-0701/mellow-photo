import CoreImage
import MellowShared

/// 얼굴 타원 마스크 안을 노이즈 제거·블러로 고르게 한다. 눈·입은 보호한다.
struct SkinStage: RenderStage {
    let name = "skin"

    func apply(_ image: CIImage, in context: RenderContext) throws -> CIImage {
        let strength = context.recipe.portrait.skinSmoothing
        guard strength > 0, !context.targetFaces.isEmpty else { return image }
        let extent = context.extent
        let tuning = context.tuning
        var mask = CIImage(color: .black).cropped(to: extent)
        for face in context.targetFaces {
            let faceRect = context.pixelRect(face.boundingBox)
            let inset = faceRect.insetBy(
                dx: faceRect.width * tuning.skinFaceInsetX, dy: faceRect.height * tuning.skinFaceInsetY)
            var local = MaskBuilder.ellipse(
                inset, extent: extent, strength: min(tuning.skinMaskMaxStrength, strength * tuning.skinMaskMaxStrength))
            for feature in protectedFeatures(of: face) {
                let featureRect = context.pixelRect(feature).insetBy(
                    dx: -faceRect.width * tuning.skinFeatureInset, dy: -faceRect.height * tuning.skinFeatureInset)
                local = MaskBuilder.blend(
                    CIImage(color: .black), over: local, mask: MaskBuilder.ellipse(featureRect, extent: extent))
            }
            mask = local.applyingFilter("CIMaximumCompositing", parameters: [kCIInputBackgroundImageKey: mask])
        }
        let blurRadius = max(tuning.skinBlurMinimumRadius, context.shortSide * tuning.skinBlurRadiusFraction)
        let smooth = image.clampedToExtent()
            .applyingFilter(
                "CINoiseReduction",
                parameters: ["inputNoiseLevel": tuning.skinNoiseLevel, "inputSharpness": tuning.skinNoiseSharpness]
            )
            .applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: blurRadius])
        return MaskBuilder.blend(smooth, over: image, mask: mask).cropped(to: extent)
    }

    /// 랜드마크가 없으면 얼굴 상자 비율로 어림한 위치를 보호한다.
    private func protectedFeatures(of face: FaceGeometry) -> [NormalizedRect] {
        let box = face.boundingBox
        let leftEye = face.bounds(of: .leftEye) ?? FallbackFeature.place(FallbackFeature.leftEye, in: box)
        let rightEye = face.bounds(of: .rightEye) ?? FallbackFeature.place(FallbackFeature.rightEye, in: box)
        let mouth = face.bounds(of: .outerLips) ?? FallbackFeature.place(FallbackFeature.mouth, in: box)
        return [leftEye, rightEye, mouth]
    }

    /// 랜드마크 대신 쓰는 부위 위치. 얼굴 상자 안의 비율이다.
    private enum FallbackFeature {
        static let leftEye = NormalizedRect(x: 0.15, y: 0.56, width: 0.28, height: 0.14)
        static let rightEye = NormalizedRect(x: 0.57, y: 0.56, width: 0.28, height: 0.14)
        static let mouth = NormalizedRect(x: 0.25, y: 0.18, width: 0.5, height: 0.18)

        static func place(_ ratio: NormalizedRect, in box: NormalizedRect) -> NormalizedRect {
            NormalizedRect(
                x: box.minX + box.width * ratio.x, y: box.minY + box.height * ratio.y, width: box.width * ratio.width,
                height: box.height * ratio.height)
        }
    }
}
