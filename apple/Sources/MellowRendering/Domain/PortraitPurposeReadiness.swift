import CoreImage
import MellowShared

/// 적용 가능성과 결함 발견을 구분한다. 준비된 입력/기존 렌더 primitive만 확인하며 결함은 판정하지 않는다.
enum PortraitPurposeReadiness {
    static func keys(
        image: CIImage, analysis: PhotoAnalysis, tuning: RenderTuning, renderer: Renderer
    ) -> [Int: Set<PortraitKey>] {
        let extent = image.extent
        var result: [Int: Set<PortraitKey>] = [:]
        for (index, face) in analysis.faces.enumerated() {
            var keys: Set<PortraitKey> = []
            // 상자만 있는 분석의 추정 눈입 위치를 실제 준비된 특징점으로 표시하지 않는다.
            let hasFeatures = [FaceLandmark.faceContour, .leftEye, .rightEye, .outerLips].allSatisfy {
                !(face.landmarks[$0] ?? []).isEmpty
            }
            if hasFeatures,
                let skin = try? FaceRegions.skinMask(
                    face: face, image: image, extent: extent, tuning: tuning, cache: analysis.regionMasks),
                positive(skin, extent: extent, renderer: renderer)
            {
                keys = [
                    .skinSmoothing, .skinRefinement(.spots), .skinRefinement(.toneEvening),
                    .skinRefinement(.chromaEvening),
                ]
                if FaceRegions.cheekAverages(of: image, face: face, extent: extent) != nil {
                    keys.formUnion([.skinRefinement(.redness), .skinRefinement(.shine)])
                }
                let folds: [(SkinRefinementKey, FaceRegions.RegionMask?)] = [
                    (.darkCircles, FaceRegions.darkCircleMask(face: face, extent: extent, tuning: tuning)),
                    (.nasolabial, FaceRegions.nasolabialMask(face: face, extent: extent, tuning: tuning)),
                    (.marionette, FaceRegions.marionetteMask(face: face, extent: extent, tuning: tuning)),
                    (.glabella, FaceRegions.glabellaMask(face: face, extent: extent, tuning: tuning)),
                ]
                for (key, region) in folds {
                    if let region,
                        positive(
                            region.image.applyingFilter(
                                "CIMultiplyCompositing", parameters: [kCIInputBackgroundImageKey: skin]),
                            extent: extent, renderer: renderer)
                    {
                        keys.insert(.skinRefinement(key))
                    }
                }
                if FaceShapeRig.doubleChinApplies(face: face, extent: extent, tuning: tuning),
                    let band = FaceRegions.chinBandRegion(
                        face: face, extent: extent, tuning: tuning, cache: analysis.regionMasks),
                    positive(band.image, extent: extent, renderer: renderer)
                {
                    keys.insert(.faceShape(.doubleChin))
                }
            }
            let bodies = analysis.bodyFaceMatches.filter { $0.value == index }.map(\.key)
            if bodies.count == 1, let bodyIndex = bodies.first, analysis.bodies.indices.contains(bodyIndex),
                let outline = analysis.bodyOutlines[bodyIndex], outline.hasSideChestPoint,
                !BodyShapeRig.primitives(
                    body: analysis.bodies[bodyIndex], adjustments: BodyShapeAdjustments(sideChest: 1),
                    extent: extent, tuning: tuning, outline: outline
                ).isEmpty
            {
                keys.insert(.bodyShape(.sideChest))
            }
            result[index] = keys
        }
        return result
    }

    /// 원 입력의 마스크 최대값만 읽는다. 새 품질 임계값이나 축소 사진의 대체 마스크를 쓰지 않는다.
    private static func positive(_ image: CIImage, extent: CGRect, renderer: Renderer) -> Bool {
        let maximum = image.cropped(to: extent).applyingFilter(
            "CIAreaMaximum", parameters: [kCIInputExtentKey: CIVector(cgRect: extent)])
        guard let pixels = try? renderer.readPixels(maximum), let red = pixels.first else { return false }
        return red.isFinite && red > 0
    }
}
