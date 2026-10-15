import CoreImage
import MellowShared

/// 메이크업 영역 위치 비율. 길이는 얼굴 폭, 높이는 얼굴 좌표(FaceFrame)의 입 높이·눈 높이 기준이다.
private enum MakeupShape {
    /// 블러셔 중심의 가로 위치. 눈동자 u의 배수(눈보다 조금 바깥).
    static let blushOutward: CGFloat = 1.15
    /// 블러셔 중심 높이. 입 높이 → 눈 높이 사이의 비율(코 옆 볼).
    static let blushHeight: CGFloat = 0.45
    /// 블러셔 타원 반지름(얼굴 x축·y축 방향). 얼굴 폭 비율.
    static let blushRadiusU: CGFloat = 0.13
    static let blushRadiusV: CGFloat = 0.085
    /// 아이섀도 띠를 올리는 양. 윗눈꺼풀에서 눈썹 아래끝까지 거리의 비율.
    static let eyeshadowRise: CGFloat = 0.75
    /// 눈썹이 없을 때 올리는 양. 눈 높이의 배수.
    static let eyeshadowRiseWithoutBrow: CGFloat = 1
    /// 띠 윗선을 양옆으로 넓히는 비율. 눈 폭 대비.
    static let eyeshadowSpread: CGFloat = 0.1
    /// 다각형이 되려면 필요한 윗눈꺼풀 점 수.
    static let minimumLidPoints = 2
}

extension FaceRegions {
    /// 얼굴 x축 방향으로 돌려 그리는 타원 하나(픽셀).
    struct Oval {
        let center: CGPoint
        let radii: CGSize
    }

    /// 볼 블러셔 영역. 두 눈 아래·코 옆의 기운 타원 × 피부 다각형. 윤곽점이나 두 눈이 없으면 nil.
    static func blushMask(face: FaceGeometry, extent: CGRect, tuning: RenderTuning, cache: RegionMaskCache? = nil)
        -> RegionMask?
    {
        guard let frame = FaceFrame(face: face, extent: extent), frame.eyes.count == 2 else { return nil }
        let width = frame.faceWidth
        let level = frame.mouthLevel + (frame.eyeLevel - frame.mouthLevel) * MakeupShape.blushHeight
        let radii = CGSize(width: width * MakeupShape.blushRadiusU, height: width * MakeupShape.blushRadiusV)
        let ovals = frame.eyes.map { eye in
            let center = frame.imagePoint(u: frame.local(eye.center).x * MakeupShape.blushOutward, v: level)
            return Oval(center: center, radii: radii)
        }
        return softMask(ovals, face: face, frame: frame, extent: extent, tuning: tuning, cache: cache)
    }

    /// 아이섀도 영역. 눈마다 윗눈꺼풀 띠(lidPolygon)에서 눈 다각형을 빼고 얼굴 폭 × makeupEyeshadowFeather로 흐린다.
    /// 흐림이 눈 안으로 번진 부분은 흐리지 않은 눈 비트맵으로 한 번 더 지워 눈(흰자·홍채)은 정확히 0이다.
    /// 눈 비트맵은 eyeMask와 같은 캐시 항목이다. 윤곽점이나 눈 다각형이 없으면 nil.
    static func eyeshadowMask(face: FaceGeometry, extent: CGRect, tuning: RenderTuning, cache: RegionMaskCache? = nil)
        -> RegionMask?
    {
        guard let frame = FaceFrame(face: face, extent: extent) else { return nil }
        let eyes = eyePolygons(face: face, extent: extent)
        let brows = [FaceLandmark.leftEyebrow, .rightEyebrow].compactMap { landmarkPolygon(face, $0, extent) }
        let lids = eyes.compactMap { lidPolygon(eye: $0, brows: brows, frame: frame) }
        guard !lids.isEmpty else { return nil }
        let feather = max(
            CGFloat(tuning.skinBlurMinimumRadius), frame.faceWidth * CGFloat(tuning.makeupEyeshadowFeather))
        guard
            let band = featheredPolygonMask(
                fill: lids, cut: eyes, face: face, extent: extent, tuning: tuning, cache: cache, feather: feather)
        else { return nil }
        let eyeRaster = polygonMask(
            fill: eyes, cut: [], cutWidth: featureCutWidth, extent: extent, tuning: tuning, cache: cache)
        let image = eyeRaster.applyingFilter("CIColorInvert")
            .applyingFilter("CIMultiplyCompositing", parameters: [kCIInputBackgroundImageKey: band.image])
            .cropped(to: extent)
        return RegionMask(image: image, bounds: band.bounds)
    }

    /// 윗눈꺼풀 선(눈 다각형 중 중심보다 위인 점, 얼굴 x 순서)과 그 선을 올리고 양옆으로 넓힌 선으로 닫은 다각형(픽셀).
    /// 올리는 양은 가로로 가장 가까운 눈썹의 아래끝까지 거리 × eyeshadowRise, 눈썹이 없거나 눈보다 아래면 눈 높이 × eyeshadowRiseWithoutBrow.
    static func lidPolygon(eye: [CGPoint], brows: [[CGPoint]], frame: FaceFrame) -> [CGPoint]? {
        let local = eye.map(frame.local)
        let center = FaceFrame.centroid(local)
        let upper = local.filter { $0.y >= center.y }.sorted { $0.x < $1.x }
        guard upper.count >= MakeupShape.minimumLidPoints, let top = local.map(\.y).max(),
            let bottom = local.map(\.y).min()
        else { return nil }
        let nearest = brows.map { $0.map(frame.local) }
            .min { abs(FaceFrame.centroid($0).x - center.x) < abs(FaceFrame.centroid($1).x - center.x) }
        let browBottom = nearest.flatMap { $0.map(\.y).min() }
        var rise = (top - bottom) * MakeupShape.eyeshadowRiseWithoutBrow
        if let browBottom, browBottom > top {
            rise = (browBottom - top) * MakeupShape.eyeshadowRise
        }
        let spread = 1 + MakeupShape.eyeshadowSpread
        let lifted = upper.reversed().map { point in
            CGPoint(x: center.x + (point.x - center.x) * spread, y: point.y + rise)
        }
        return (upper + lifted).map { frame.imagePoint(u: $0.x, v: $0.y) }
    }

    /// 얼굴 x축으로 돌린 타원들의 최대 × 피부 다각형 비트맵을 피부 마스크와 같은 반지름으로 흐린다.
    /// 타원 경계 상자 + 흐림 4배 여백 밖은 정확히 0이다. 타원이 없으면 nil.
    static func softMask(
        _ ovals: [Oval], face: FaceGeometry, frame: FaceFrame, extent: CGRect, tuning: RenderTuning,
        cache: RegionMaskCache?
    ) -> RegionMask? {
        let feather = featherRadius(face, extent, tuning)
        let padding = feather * boundsPaddingInFeathers
        let reach = ovals.map { oval -> CGRect in
            let side = max(oval.radii.width, oval.radii.height)
            return CGRect(x: oval.center.x - side, y: oval.center.y - side, width: side * 2, height: side * 2)
        }
        .reduce(CGRect.null) { $0.union($1) }
        let bounds = reach.insetBy(dx: -padding, dy: -padding).intersection(extent).integral
        guard !ovals.isEmpty, !bounds.isEmpty else { return nil }
        let angle = atan2(frame.xAxis.dy, frame.xAxis.dx)
        let black = CIImage(color: .black).cropped(to: extent)
        var shapes = black
        for oval in ovals {
            shapes = MaskBuilder.ellipse(center: oval.center, radii: oval.radii, angle: angle, extent: extent)
                .applyingFilter("CIMaximumCompositing", parameters: [kCIInputBackgroundImageKey: shapes])
        }
        let skin = skinPolygonRaster(face: face, extent: extent, tuning: tuning, cache: cache)
        let image = shapes.applyingFilter("CIMultiplyCompositing", parameters: [kCIInputBackgroundImageKey: skin])
            .clampedToExtent()
            .applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: feather])
            .cropped(to: bounds).composited(over: black)
        return RegionMask(image: image, bounds: bounds)
    }
}
