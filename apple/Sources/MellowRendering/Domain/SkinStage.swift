import CoreImage
import MellowShared

/// 자동 잡티를 지운 뒤 피부 마스크 안에서 주파수 분리로 얼룩만 줄인다. 모공 질감은 남긴다.
struct SkinStage: RenderStage {
    let name = "skin"

    func apply(_ image: CIImage, in context: RenderContext) throws -> CIImage {
        let skin = context.recipe.portrait.skin
        guard skin.hasEffect, !context.targetFaces.isEmpty else { return image }
        let extent = context.extent
        let tuning = context.tuning
        var result = image
        if skin.autoBlemish {
            for blemish in context.targetBlemishes {
                let heal = Self.healSpot(for: blemish, in: context)
                result = LocalEditStage.applySpot(heal, to: result, context: context)
            }
        }
        guard skin.smoothing > 0 else { return result.cropped(to: extent) }
        for face in context.targetFaces {
            // 이미지 밖까지 계산하면 가장자리에 알파 0·RGB가 있는 픽셀이 남는다.
            let bounds = FaceRegions.maskBounds(face: face, extent: extent, tuning: tuning).intersection(result.extent)
            guard !bounds.isEmpty else { continue }
            let mask = try FaceRegions.skinMask(
                face: face, image: result, extent: extent, tuning: tuning, strength: tuning.skinMaskMaxStrength)
            let smooth = try FrequencySeparation.smoothed(
                result, bounds: bounds, faceWidth: FaceRegions.faceWidth(face, extent: extent),
                smoothing: skin.smoothing, tuning: tuning)
            result = MaskBuilder.blend(smooth, over: result, mask: mask).cropped(to: extent)
        }
        return result
    }

    /// 잡티를 덮는 복제 원. 원본은 얼굴 가운데 쪽 옆 피부다. 수동 잡티와 같은 패치 복구를 쓴다.
    static func healSpot(for blemish: BlemishSpot, in context: RenderContext) -> RetouchSpot {
        let tuning = context.tuning
        let radius = blemish.radius * tuning.blemishHealRadiusScale
        let faces = context.faces
        let knownFace = faces.indices.contains(blemish.faceIndex)
        let faceCenterX = knownFace ? faces[blemish.faceIndex].boundingBox.midX : blemish.x
        let direction: Double = faceCenterX >= blemish.x ? 1 : -1
        let shift = radius * Double(context.shortSide) * tuning.blemishSourceOffset / Double(context.extent.width)
        return RetouchSpot(
            x: blemish.x, y: blemish.y, sourceX: blemish.x + direction * shift, sourceY: blemish.y, radius: radius)
    }
}
