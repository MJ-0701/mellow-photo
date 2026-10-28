import CoreImage
import MellowShared

/// 원 준비 입력에서 실제 primitive가 사용 가능한지 확인한다. 결함 검출/품질 수용이 아니다.
/// 단계가 앞서 바꾼 픽셀에 따라 색 가중치는 달라질 수 있으므로 최종 가시 효과를 보증하지 않는다.
enum OneTouchReadiness {
    struct Result {
        var keys: [Int: Set<PortraitKey>]
        var bodySkin: Bool
    }
    static func inspect(
        image: CIImage, analysis: PhotoAnalysis, tuning: RenderTuning,
        renderer: Renderer, makeupCatalog: MakeupCatalog, skinKeys: [Int: Set<PortraitKey>]
    ) -> Result {
        let extent = image.extent
        var result: [Int: Set<PortraitKey>] = [:]
        var automaticRecipe = EditRecipe()
        automaticRecipe.portrait.skin.autoBlemish = true
        let automaticContext = RenderContext(
            extent: extent, recipe: automaticRecipe, analysis: analysis, tuning: tuning)
        for (index, face) in analysis.faces.enumerated() {
            var keys = (skinKeys[index] ?? []).intersection(OneTouchBundle.keys)
            // 상자 fallback을 실제 눈/입 준비로 표시하지 않는다.
            let hasContour = !(face.landmarks[.faceContour] ?? []).isEmpty
            if automaticContext.faceTargets.indices.contains(index),
                !SkinStage.healSpots(for: automaticContext.faceTargets[index], in: automaticContext).isEmpty
            {
                keys.insert(.autoBlemish)
            }
            if hasContour, !(face.landmarks[.leftEye] ?? []).isEmpty,
                !(face.landmarks[.rightEye] ?? []).isEmpty,
                let eyes = FaceRegions.eyeMask(face: face, extent: extent, tuning: tuning, cache: analysis.regionMasks)
            {
                let sclera = try? FeatureKernels.shared.weight(of: image, rule: .sclera(tuning), extent: eyes.bounds)
                let weighted = sclera.map {
                    eyes.image.applyingFilter("CIMultiplyCompositing", parameters: [kCIInputBackgroundImageKey: $0])
                }
                let iris = FaceRegions.irisMask(face: face, extent: extent, tuning: tuning, cache: analysis.regionMasks)
                if positive(weighted, extent: extent, renderer: renderer)
                    || positive(iris?.image, extent: extent, renderer: renderer)
                {
                    keys.insert(.feature(.eyeBrighten))
                }
            }
            if hasContour, !(face.landmarks[.outerLips] ?? []).isEmpty {
                let lips = FaceRegions.lipMask(face: face, extent: extent, tuning: tuning, cache: analysis.regionMasks)
                if positive(lips?.image, extent: extent, renderer: renderer) {
                    keys.insert(.feature(.lipVitality))
                    // 원터치의 lip은 항상 neutral이다. 기존 양의 tint 해제를 위한 실제 입 영역 준비다.
                    keys.insert(.makeupPart(.lip))
                }
                if let teeth = try? FaceRegions.teethMask(
                    face: face, image: image, extent: extent, tuning: tuning, cache: analysis.regionMasks),
                    positive(teeth.image, extent: extent, renderer: renderer)
                {
                    keys.insert(.feature(.teethWhiten))
                }
            }
            if hasContour, !(face.landmarks[.leftEye] ?? []).isEmpty,
                !(face.landmarks[.rightEye] ?? []).isEmpty,
                makeupCatalog.color(id: OneTouchBundle.Table.blushColorID, for: .blush) != nil,
                let blush = FaceRegions.blushMask(
                    face: face, extent: extent, tuning: tuning, cache: analysis.regionMasks),
                positive(blush.image, extent: extent, renderer: renderer)
            {
                keys.insert(.makeupPart(.blush))
            }
            result[index] = keys
        }
        let bodyMask = try? BodySkinStage.toneMask(
            image, faces: analysis.faces, personMask: analysis.personMask,
            extent: extent, tuning: tuning, regionMasks: analysis.regionMasks)
        return Result(keys: result, bodySkin: positive(bodyMask, extent: extent, renderer: renderer))
    }

    private static func positive(_ image: CIImage?, extent: CGRect, renderer: Renderer) -> Bool {
        guard let image else { return false }
        let maximum = image.cropped(to: extent).applyingFilter(
            "CIAreaMaximum", parameters: [kCIInputExtentKey: CIVector(cgRect: extent)])
        guard let value = try? renderer.readPixels(maximum).first else { return false }
        return value.isFinite && value > 0
    }
}
