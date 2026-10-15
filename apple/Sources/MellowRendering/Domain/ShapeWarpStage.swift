import CoreImage
import MellowShared

/// 얼굴형(C)과 체형(E) 이동 원소를 모아 이동량 지도로 한 번만 변형한다. B0의 상자 기반 얼굴 폭 변형을 대체한다.
/// 얼굴은 대상 얼굴 모두, 값 범위는 FaceShapeRig가 직접 자른다. 원소가 없으면 입력을 그대로 돌려준다.
struct ShapeWarpStage: RenderStage {
    let name = "shapeWarp"

    func apply(_ image: CIImage, in context: RenderContext) throws -> CIImage {
        let primitives = facePrimitives(in: context) + bodyPrimitives(in: context)
        return try DisplacementWarp.shared.apply(
            primitives, to: image, extent: context.extent, limit: context.tuning.shapeDisplacementLimit)
    }

    func facePrimitives(in context: RenderContext) -> [ShapePrimitive] {
        let adjustments = context.recipe.portrait.face
        guard adjustments.hasEffect else { return [] }
        return context.targetFaces.flatMap { face in
            FaceShapeRig.primitives(
                face: face, adjustments: adjustments, extent: context.extent, tuning: context.tuning)
        }
    }

    /// 체형 원소 자리. E 단계가 BodyShapeRig 원소로 채운다. 그때까지 빈 배열이다.
    func bodyPrimitives(in context: RenderContext) -> [ShapePrimitive] {
        []
    }
}
