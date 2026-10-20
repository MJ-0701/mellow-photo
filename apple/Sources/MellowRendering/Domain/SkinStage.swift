import CoreImage
import MellowShared

/// 자동 잡티를 먼저 지우고 얼굴마다 주름 밝히기 4종(다크서클·팔자·마리오네트·미간)을 건다.
/// 이어서 피부 마스크 안 대역 합성으로 얼룩(피부 보정)·넓은 톤 차이(얼룩 고르기)·번들거림을 줄이고 마지막에 붉은기를 조정한다.
/// 모공 질감(가는 대역)은 남긴다.
struct SkinStage: RenderStage {
    let name = "skin"

    func apply(_ image: CIImage, in context: RenderContext) throws -> CIImage {
        let skin = Self.clamped(context.recipe.portrait.skin)
        guard skin.hasEffect, !context.targetFaces.isEmpty else { return image }
        let extent = context.extent
        var result = image
        if skin.autoBlemish {
            for heal in Self.healSpots(in: context) {
                result = LocalEditStage.applySpot(heal, to: result, context: context)
            }
        }
        guard skin.smoothing > 0 || skin.hasRefinement else { return result.cropped(to: extent) }
        for face in context.targetFaces {
            result = try refine(result, face: face, skin: skin, context: context)
        }
        return result.cropped(to: extent)
    }

    /// 피부 보정 0…1, 정밀 값은 키별 범위로 자른다. 프리셋·일괄 값은 편집 규칙을 거치지 않는다. 유한하지 않은 값은 RenderPipeline이 먼저 거절한다.
    static func clamped(_ skin: SkinAdjustments) -> SkinAdjustments {
        var copy = skin
        copy.smoothing = AdjustmentRange.clamped(skin.smoothing, to: AdjustmentRange.unit)
        for key in SkinRefinementKey.allCases {
            copy[key] = AdjustmentRange.clamped(skin[key], to: AdjustmentRange.skinRefinement(key))
        }
        return copy
    }

    /// 얼굴 하나: 주름 밝히기 4종 → 피부 마스크 안 대역 합성(피부 보정·얼룩 고르기·번들거림) → 붉은기. 마스크 계산 영역이 비면(얼굴이 사진 밖) 건너뛴다.
    private func refine(_ image: CIImage, face: FaceGeometry, skin: SkinAdjustments, context: RenderContext) throws
        -> CIImage
    {
        let extent = context.extent
        let tuning = context.tuning
        // 이미지 밖까지 계산하면 가장자리에 알파 0·RGB가 있는 픽셀이 남는다.
        let bounds = FaceRegions.maskBounds(face: face, extent: extent, tuning: tuning).intersection(image.extent)
        guard !bounds.isEmpty else { return image }
        let faceWidth = FaceRegions.faceWidth(face, extent: extent)
        // 피부 마스크는 주름 전 이미지에서 한 번 만든다.
        // 주름 밝히기의 둘레 기준 가중치와 대역 합성·붉은기가 함께 쓴다.
        // 캐시된 비트맵과 볼 평균만 쓰므로 주름만 켜도 비용이 거의 없다.
        let unitMask = try FaceRegions.skinMask(
            face: face, image: image, extent: extent, tuning: tuning, strength: 1, cache: context.regionMasks)
        var result = image
        for fold in Self.folds(for: face, skin: skin, context: context) {
            result = try SkinRefinement.liftFold(
                result, region: fold.region, skinMask: unitMask, faceWidth: faceWidth, amount: fold.amount,
                tuning: tuning, extent: extent)
        }
        let bandMix = skin.smoothing > 0 || skin.toneEvening > 0 || skin.shine > 0
        guard bandMix || skin.redness != 0 else { return result }
        let blendMask = MaskBuilder.scaled(unitMask, by: tuning.skinMaskMaxStrength)
        if bandMix {
            // 볼 상자가 없으면 번들거림의 기준이 없어 번들거림만 건너뛴다.
            // 그때 커널에 넘기는 검은 기준은 자리 채움이라 쓰이지 않는다.
            let reference = Self.cheekReference(of: result, face: face, extent: extent)
            let smooth = try FrequencySeparation.refined(
                result, bounds: bounds, faceWidth: faceWidth, mask: unitMask,
                reference: reference ?? CIImage(color: .black),
                smoothing: skin.smoothing, toneEvening: skin.toneEvening, shine: reference == nil ? 0 : skin.shine,
                tuning: tuning)
            result = MaskBuilder.blend(smooth, over: result, mask: blendMask).cropped(to: extent)
        }
        // 볼 상자가 없으면 붉은기의 기준이 없어 붉은기는 건너뛴다.
        if skin.redness != 0,
            let encodedReference = Self.cheekReference(
                of: result.applyingFilter("CILinearToSRGBToneCurve"), face: face, extent: extent)
        {
            result = try SkinRefinement.adjustRedness(
                result, mask: blendMask, bounds: bounds, reference: encodedReference, value: skin.redness,
                tuning: tuning, extent: extent)
        }
        return result
    }

    /// 볼 두 곳 평균을 반씩 섞은 기준색(무한 확장). 넘긴 이미지의 색공간을 따른다. 볼 상자가 없으면 nil.
    static func cheekReference(of image: CIImage, face: FaceGeometry, extent: CGRect) -> CIImage? {
        guard let cheeks = FaceRegions.cheekAverages(of: image, face: face, extent: extent) else { return nil }
        return cheeks.left.applyingFilter(
            "CIMix", parameters: [kCIInputBackgroundImageKey: cheeks.right, "inputAmount": Self.referenceMix])
    }

    /// 두 볼을 같은 비중으로 섞는다.
    private static let referenceMix = 0.5

    /// 값이 0이 아니고 마스크를 만들 수 있는 주름 띠. 순서는 다크서클 → 팔자 → 마리오네트 → 미간. 특징점이 없는 띠는 빠진다.
    static func folds(for face: FaceGeometry, skin: SkinAdjustments, context: RenderContext)
        -> [(amount: Double, region: FaceRegions.RegionMask)]
    {
        let extent = context.extent
        let tuning = context.tuning
        let cache = context.regionMasks
        let candidates: [(Double, () -> FaceRegions.RegionMask?)] = [
            (
                skin.darkCircles,
                { FaceRegions.darkCircleMask(face: face, extent: extent, tuning: tuning, cache: cache) }
            ),
            (skin.nasolabial, { FaceRegions.nasolabialMask(face: face, extent: extent, tuning: tuning, cache: cache) }),
            (skin.marionette, { FaceRegions.marionetteMask(face: face, extent: extent, tuning: tuning, cache: cache) }),
            (skin.glabella, { FaceRegions.glabellaMask(face: face, extent: extent, tuning: tuning, cache: cache) }),
        ]
        return candidates.compactMap { amount, make in
            guard amount > 0, let region = make() else { return nil }
            return (amount, region)
        }
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
