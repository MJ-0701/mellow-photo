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
            for heal in Self.healSpots(in: context) {
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

    /// 대상 잡티의 복제 원. 쓸 만한 원본이 없는 잡티는 건너뛴다.
    /// 원본 조건은 얼굴마다 한 번 만든다. 제외 영역 넓힘은 그 얼굴 잡티 중 가장 큰 복제 반지름이다(작은 잡티에는 보수적).
    /// 얼굴 인덱스가 범위 밖인 잡티는 피부 다각형이 없어 건너뛴다.
    static func healSpots(in context: RenderContext) -> [RetouchSpot] {
        let blemishes = context.targetBlemishes
        var rules: [Int: SourceRules] = [:]
        for (faceIndex, members) in Dictionary(grouping: blemishes, by: \.faceIndex) {
            guard context.faces.indices.contains(faceIndex) else { continue }
            rules[faceIndex] = SourceRules(face: context.faces[faceIndex], members: members, in: context)
        }
        return blemishes.indices.compactMap { index in
            let blemish = blemishes[index]
            guard let faceRules = rules[blemish.faceIndex] else { return nil }
            let others = blemishes.indices.filter { $0 != index && blemishes[$0].faceIndex == blemish.faceIndex }
                .map { blemishes[$0] }
            return healSpot(for: blemish, in: context, rules: faceRules, others: others)
        }
    }

    /// 잡티를 덮는 복제 원. 원본은 얼굴 가운데 쪽 옆 피부이고, 그쪽이 조건에 맞지 않으면 반대쪽이다.
    /// 양쪽 다 맞지 않으면 nil. 수동 잡티와 같은 패치 복구를 쓴다.
    private static func healSpot(
        for blemish: BlemishSpot, in context: RenderContext, rules: SourceRules, others: [BlemishSpot]
    ) -> RetouchSpot? {
        let tuning = context.tuning
        let radius = blemish.radius * tuning.blemishHealRadiusScale
        let faceCenterX = context.faces[blemish.faceIndex].boundingBox.midX
        let towardCenter: Double = faceCenterX >= blemish.x ? 1 : -1
        let shift = radius * Double(context.shortSide) * tuning.blemishSourceOffset / Double(context.extent.width)
        let sourceRadius = healRadius(of: blemish, in: context)
        for direction in [towardCenter, -towardCenter] {
            let sourceX = blemish.x + direction * shift
            let source = context.pixelPoint(x: sourceX, y: blemish.y)
            guard rules.accepts(source, radius: sourceRadius, others: others, in: context) else { continue }
            return RetouchSpot(x: blemish.x, y: blemish.y, sourceX: sourceX, sourceY: blemish.y, radius: radius)
        }
        return nil
    }

    /// 복제 원의 픽셀 반지름.
    private static func healRadius(of blemish: BlemishSpot, in context: RenderContext) -> CGFloat {
        CGFloat(blemish.radius * context.tuning.blemishHealRadiusScale) * context.shortSide
    }

    /// 한 얼굴의 복제 원본 조건. 경로는 얼굴마다 한 번 만든다.
    private struct SourceRules {
        /// 눈·눈썹·입술·코를 그 얼굴 잡티 중 가장 큰 복제 반지름만큼 넓힌 영역.
        let excluded: (CGPoint) -> Bool
        /// 피부 다각형(윤곽 + 이마 호). 머리카락·배경을 피부에 옮기지 않게 한다.
        let insideSkin: (CGPoint) -> Bool

        init(face: FaceGeometry, members: [BlemishSpot], in context: RenderContext) {
            let largest = members.map { SkinStage.healRadius(of: $0, in: context) }.max() ?? 0
            let exclusions = FaceRegions.blemishExclusionPolygons(face: face, extent: context.extent)
            excluded = FaceRegions.containment(polygons: exclusions, dilation: largest)
            let skin = FaceRegions.skinPolygon(face: face, extent: context.extent, tuning: context.tuning)
            insideSkin = FaceRegions.containment(polygons: [skin], dilation: 0)
        }

        /// 원본 원 중심이 피부 안·제외 영역 밖이고, 다른 잡티와 (원본 반지름 + 그 잡티 반지름) 이상 떨어졌는지.
        /// 다른 잡티는 아직 지우기 전일 수 있어 원본으로 쓰면 잡티를 옮겨 붙인다.
        func accepts(_ source: CGPoint, radius: CGFloat, others: [BlemishSpot], in context: RenderContext) -> Bool {
            guard insideSkin(source), !excluded(source) else { return false }
            return others.allSatisfy { other in
                let center = context.pixelPoint(x: other.x, y: other.y)
                let reach = radius + CGFloat(other.radius) * context.shortSide
                return hypot(source.x - center.x, source.y - center.y) >= reach
            }
        }
    }
}
