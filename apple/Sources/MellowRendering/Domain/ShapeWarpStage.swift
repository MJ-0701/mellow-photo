import CoreImage
import MellowShared

/// 얼굴형(C)과 체형(E) 이동 원소를 모아 이동량 지도로 한 번만 변형한다. B0의 상자 기반 얼굴 폭 변형을 대체한다.
/// 얼굴은 대상 얼굴 모두, 체형은 모든 몸(bodyTargets)이고 몸마다 그 사람의 해석 값을 쓴다.
/// 원소는 보호 묶음(ShapeGroup)으로 나눈다(스펙 5.5).
/// 얼굴마다 얼굴형 묶음(그 얼굴의 사람 마스크, 팔 보호 없음) 하나다.
/// 몸마다 몸통 묶음(그 몸의 팔 캡슐 보호)과 팔다리 묶음(팔 보호 없음)이고 둘 다 그 몸의 사람 마스크를 받는다.
/// 다리 길게 띠는 가장 큰 몸 하나만 만든다(DisplacementWarp.maximumBands 1). 값 범위는 각 rig가 직접 자른다.
/// 원소가 없으면 입력을 그대로 돌려준다. 관절이 없거나 체형 분석이 실패했으면 체형 원소만 빠진다(오류 아님).
/// 인물 마스크가 없으면 보호가 꺼져 이 계획 전과 같은 바이트로 그린다.
struct ShapeWarpStage: RenderStage {
    let name = "shapeWarp"

    func apply(_ image: CIImage, in context: RenderContext) throws -> CIImage {
        try DisplacementWarp.shared.apply(
            groups: groups(in: context), to: image, extent: context.extent,
            limit: context.tuning.shapeDisplacementLimit, tuning: context.tuning)
    }

    /// apply가 그리는 묶음 그대로. 수용 테스트가 같은 묶음의 이동량을 잰다.
    func groups(in context: RenderContext) -> [ShapeGroup] {
        faceGroups(in: context) + bodyGroups(in: context)
    }

    /// 얼굴마다 그 얼굴에 해석한 얼굴형 값으로 원소를 만든다.
    func facePrimitives(in context: RenderContext) -> [ShapePrimitive] {
        faceGroups(in: context).flatMap(\.primitives)
    }

    /// 몸마다 그 몸에 해석한 체형 값으로 원소를 만든다(몸통 묶음 다음 팔다리 묶음).
    /// 관절이 없거나 분석이 실패해 bodies가 비었으면 빈 배열이다(스펙 1.4, 5).
    func bodyPrimitives(in context: RenderContext) -> [ShapePrimitive] {
        bodyGroups(in: context).flatMap(\.primitives)
    }

    private func faceGroups(in context: RenderContext) -> [ShapeGroup] {
        context.faceTargets.compactMap { target -> ShapeGroup? in
            let adjustments = target.portrait.face
            guard adjustments.hasEffect else { return nil }
            let primitives = FaceShapeRig.primitives(
                face: target.face, adjustments: adjustments, extent: context.extent, tuning: context.tuning)
            guard !primitives.isEmpty else { return nil }
            let masks = context.personMask(forFace: target.index)
            return ShapeGroup(primitives: primitives, ownMask: masks.own, otherMasks: masks.others)
        }
    }

    /// 가장 크지 않은 몸은 다리 길게 띠를 만들지 않는다.
    private func bodyGroups(in context: RenderContext) -> [ShapeGroup] {
        context.bodyTargets.flatMap { target -> [ShapeGroup] in
            let parts = BodyShapeRig.groups(
                body: target.body, adjustments: target.adjustments, extent: context.extent, tuning: context.tuning,
                includesLegBand: target.index == Self.bandBodyIndex)
            let masks = context.personMask(forBody: target.index)
            var result: [ShapeGroup] = []
            if !parts.torso.isEmpty {
                result.append(
                    ShapeGroup(
                        primitives: parts.torso, ownMask: masks.own, otherMasks: masks.others, guards: parts.guards))
            }
            if !parts.limbs.isEmpty {
                result.append(ShapeGroup(primitives: parts.limbs, ownMask: masks.own, otherMasks: masks.others))
            }
            return result
        }
    }

    /// 다리 띠를 만드는 몸. 분석이 넓이 순으로 정렬해 0이 가장 큰 몸이다.
    private static let bandBodyIndex = 0
}
