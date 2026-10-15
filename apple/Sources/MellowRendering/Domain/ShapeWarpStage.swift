import CoreImage
import MellowShared

/// 얼굴형(C)과 체형(E) 이동 원소를 모아 이동량 지도로 한 번만 변형한다. B0의 상자 기반 얼굴 폭 변형을 대체한다.
/// 얼굴은 대상 얼굴 모두, 체형은 가장 큰 사람(bodies.first) 한 명이다. 값 범위는 각 rig가 직접 자른다.
/// 원소가 없으면 입력을 그대로 돌려준다. 관절이 없거나 체형 분석이 실패했으면 체형 원소만 빠진다(오류 아님).
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

    /// 가장 큰 사람 한 명의 체형 원소. 관절이 없거나 분석이 실패해 bodies가 비었으면 빈 배열이다(스펙 1.4, 5).
    func bodyPrimitives(in context: RenderContext) -> [ShapePrimitive] {
        let adjustments = context.recipe.body
        guard adjustments.hasEffect, let body = context.bodies.first else { return [] }
        return BodyShapeRig.primitives(
            body: body, adjustments: adjustments, extent: context.extent, tuning: context.tuning)
    }
}
