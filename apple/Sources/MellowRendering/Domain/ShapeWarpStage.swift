import CoreImage
import MellowShared

/// 얼굴형(C)과 체형(E) 이동 원소를 모아 이동량 지도로 한 번만 변형한다. B0의 상자 기반 얼굴 폭 변형을 대체한다.
/// 얼굴은 대상 얼굴 모두, 체형은 모든 몸(bodyTargets)이고 몸마다 그 사람의 해석 값을 쓴다.
/// 다리 길게 띠는 가장 큰 몸 하나만 만든다(DisplacementWarp.maximumBands 1). 값 범위는 각 rig가 직접 자른다.
/// 원소가 없으면 입력을 그대로 돌려준다. 관절이 없거나 체형 분석이 실패했으면 체형 원소만 빠진다(오류 아님).
struct ShapeWarpStage: RenderStage {
    let name = "shapeWarp"

    func apply(_ image: CIImage, in context: RenderContext) throws -> CIImage {
        let primitives = facePrimitives(in: context) + bodyPrimitives(in: context)
        return try DisplacementWarp.shared.apply(
            primitives, to: image, extent: context.extent, limit: context.tuning.shapeDisplacementLimit)
    }

    /// 얼굴마다 그 얼굴에 해석한 얼굴형 값으로 원소를 만든다.
    func facePrimitives(in context: RenderContext) -> [ShapePrimitive] {
        context.faceTargets.flatMap { target -> [ShapePrimitive] in
            let adjustments = target.portrait.face
            guard adjustments.hasEffect else { return [] }
            return FaceShapeRig.primitives(
                face: target.face, adjustments: adjustments, extent: context.extent, tuning: context.tuning)
        }
    }

    /// 몸마다 그 몸에 해석한 체형 값으로 원소를 만든다.
    /// 관절이 없거나 분석이 실패해 bodies가 비었으면 빈 배열이다(스펙 1.4, 5).
    /// 가장 크지 않은 몸은 다리 길게를 0으로 두고 만든다.
    func bodyPrimitives(in context: RenderContext) -> [ShapePrimitive] {
        context.bodyTargets.flatMap { target -> [ShapePrimitive] in
            var adjustments = target.adjustments
            if target.index != Self.bandBodyIndex {
                adjustments.legLength = 0
            }
            guard adjustments.hasEffect else { return [] }
            return BodyShapeRig.primitives(
                body: target.body, adjustments: adjustments, extent: context.extent, tuning: context.tuning)
        }
    }

    /// 다리 띠를 만드는 몸. 분석이 넓이 순으로 정렬해 0이 가장 큰 몸이다.
    private static let bandBodyIndex = 0
}
