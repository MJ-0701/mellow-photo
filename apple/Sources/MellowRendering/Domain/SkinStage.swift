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

    /// 대상 잡티의 복제 원. 원본이 눈·눈썹·입술·코에 걸리는 잡티는 건너뛴다.
    /// 제외 판정은 얼굴마다 한 번 만든다. 넓힘은 그 얼굴 잡티 중 가장 큰 복제 반지름이다(작은 잡티에는 보수적).
    static func healSpots(in context: RenderContext) -> [RetouchSpot] {
        let blemishes = context.targetBlemishes
        var exclusions: [Int: (CGPoint) -> Bool] = [:]
        for (faceIndex, members) in Dictionary(grouping: blemishes, by: \.faceIndex) {
            guard context.faces.indices.contains(faceIndex) else { continue }
            let largest = members.map { healRadius(of: $0, in: context) }.max() ?? 0
            let polygons = FaceRegions.blemishExclusionPolygons(face: context.faces[faceIndex], extent: context.extent)
            exclusions[faceIndex] = FaceRegions.containment(polygons: polygons, dilation: largest)
        }
        return blemishes.compactMap { healSpot(for: $0, in: context, excluded: exclusions[$0.faceIndex]) }
    }

    /// 잡티를 덮는 복제 원. 원본은 얼굴 가운데 쪽 옆 피부이고, 그쪽이 제외 영역이면 반대쪽이다.
    /// 양쪽 다 제외 영역이면 nil. 수동 잡티와 같은 패치 복구를 쓴다.
    static func healSpot(
        for blemish: BlemishSpot, in context: RenderContext, excluded: ((CGPoint) -> Bool)? = nil
    ) -> RetouchSpot? {
        let tuning = context.tuning
        let radius = blemish.radius * tuning.blemishHealRadiusScale
        let faces = context.faces
        let knownFace = faces.indices.contains(blemish.faceIndex)
        let faceCenterX = knownFace ? faces[blemish.faceIndex].boundingBox.midX : blemish.x
        let towardCenter: Double = faceCenterX >= blemish.x ? 1 : -1
        let shift = radius * Double(context.shortSide) * tuning.blemishSourceOffset / Double(context.extent.width)
        for direction in [towardCenter, -towardCenter] {
            let sourceX = blemish.x + direction * shift
            if let excluded, excluded(context.pixelPoint(x: sourceX, y: blemish.y)) {
                continue
            }
            return RetouchSpot(x: blemish.x, y: blemish.y, sourceX: sourceX, sourceY: blemish.y, radius: radius)
        }
        return nil
    }

    /// 복제 원의 픽셀 반지름.
    private static func healRadius(of blemish: BlemishSpot, in context: RenderContext) -> CGFloat {
        CGFloat(blemish.radius * context.tuning.blemishHealRadiusScale) * context.shortSide
    }
}
