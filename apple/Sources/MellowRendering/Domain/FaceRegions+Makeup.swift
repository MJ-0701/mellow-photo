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
    /// 눈썹을 넓히는 배율(얼굴 x축·y축). 가는 눈썹이 위아래로 채워진다.
    static let browSpreadU: CGFloat = 1.15
    static let browSpreadV: CGFloat = 1.6
    /// 광대 아래 쉐딩. 가로 위치(얼굴 폭 비율), 높이(입 → 눈 비율), 반지름(얼굴 폭 비율).
    static let hollowOffset: CGFloat = 0.34
    static let hollowHeight: CGFloat = 0.2
    static let hollowRadiusU: CGFloat = 0.11
    static let hollowRadiusV: CGFloat = 0.04
    /// 턱선 쉐딩 반지름. 얼굴 폭 비율.
    static let jawRadiusU: CGFloat = 0.09
    static let jawRadiusV: CGFloat = 0.05
    /// 코 옆 쉐딩의 가로 반지름. 얼굴 폭 비율.
    static let noseSideRadiusU: CGFloat = 0.02
    /// 콧대 하이라이터의 가로 반지름(얼굴 폭 비율)과 세로 길이(코 옆 쉐딩 세로 반지름 대비).
    static let bridgeRadiusU: CGFloat = 0.025
    static let bridgeLengthFraction: CGFloat = 0.8
    /// 이마 가운데 하이라이터. 눈 높이 위 거리와 반지름. 얼굴 폭 비율.
    static let foreheadRise: CGFloat = 0.22
    static let foreheadRadiusU: CGFloat = 0.12
    static let foreheadRadiusV: CGFloat = 0.06
    /// 턱 끝 하이라이터. 가장 낮은 윤곽점 위 거리와 반지름. 얼굴 폭 비율.
    static let chinRise: CGFloat = 0.06
    static let chinRadiusU: CGFloat = 0.06
    static let chinRadiusV: CGFloat = 0.035
}

extension FaceRegions {
    /// 얼굴 x축 방향으로 돌려 그리는 타원 하나(픽셀). tilt는 얼굴 x축 기준 추가 회전(라디안, 반시계)이다.
    struct Oval {
        let center: CGPoint
        let radii: CGSize
        var tilt: CGFloat = 0
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
    /// 눈썹은 두 눈 가운데 선(eyeMidline)에서 그 눈과 같은 쪽인 것만 고른다. 눈썹 하나가 없을 때 반대쪽 눈썹을 쓰지 않는다.
    static func lidPolygon(eye: [CGPoint], brows: [[CGPoint]], frame: FaceFrame) -> [CGPoint]? {
        let local = eye.map(frame.local)
        let center = FaceFrame.centroid(local)
        let upper = local.filter { $0.y >= center.y }.sorted { $0.x < $1.x }
        guard upper.count >= MakeupShape.minimumLidPoints, let top = local.map(\.y).max(),
            let bottom = local.map(\.y).min()
        else { return nil }
        let midline = eyeMidline(frame)
        let nearest = brows.map { $0.map(frame.local) }
            .filter { (FaceFrame.centroid($0).x - midline) * (center.x - midline) > 0 }
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

    /// 두 눈 가운데의 얼굴 좌표 u. 두 눈 위치를 모르면 얼굴 상자 중심(0)이다.
    static func eyeMidline(_ frame: FaceFrame) -> CGFloat {
        guard let first = frame.eyes.first, let last = frame.eyes.last, frame.eyes.count > 1 else { return 0 }
        return (frame.local(first.center).x + frame.local(last.center).x) / 2
    }

    /// 눈썹 하나의 넓힌 마스크와 원래 눈썹 색을 잴 사각형(픽셀).
    struct BrowRegion {
        let mask: RegionMask
        let sample: CGRect
    }

    /// 쉐딩(어둡게)·하이라이터(밝게) 영역. 각각 타원이 하나도 없거나 계산 영역이 비면 nil.
    struct ContourRegions {
        let shade: RegionMask?
        let highlight: RegionMask?
    }

    /// 눈썹마다 다각형을 얼굴 좌표에서 browSpreadU·browSpreadV배 넓혀 얼굴 폭 × makeupBrowFeather로 흐린다.
    /// 윤곽점이 없으면 빈 배열, 눈썹 특징점이 없는 쪽은 뺀다. 넓힌 다각형은 눈썹마다 캐시 항목 하나다.
    static func browRegions(face: FaceGeometry, extent: CGRect, tuning: RenderTuning, cache: RegionMaskCache? = nil)
        -> [BrowRegion]
    {
        guard let frame = FaceFrame(face: face, extent: extent) else { return [] }
        let feather = max(CGFloat(tuning.skinBlurMinimumRadius), frame.faceWidth * CGFloat(tuning.makeupBrowFeather))
        return [FaceLandmark.leftEyebrow, .rightEyebrow].compactMap { landmark in
            guard let brow = landmarkPolygon(face, landmark, extent) else { return nil }
            let local = brow.map(frame.local)
            let center = FaceFrame.centroid(local)
            let widened = local.map { point in
                frame.imagePoint(
                    u: center.x + (point.x - center.x) * MakeupShape.browSpreadU,
                    v: center.y + (point.y - center.y) * MakeupShape.browSpreadV)
            }
            guard
                let mask = featheredPolygonMask(
                    fill: [widened], cut: [], face: face, extent: extent, tuning: tuning, cache: cache,
                    feather: feather)
            else { return nil }
            return BrowRegion(mask: mask, sample: boundingRect(brow).intersection(extent).integral)
        }
    }

    /// 쉐딩: 광대 아래·턱선·코 옆(각 2곳). 하이라이터: 콧대·이마 가운데·턱 끝(스펙 6). 윤곽점이 없으면 nil.
    /// 코가 없으면 코 옆 쉐딩과 콧대 하이라이터만 뺀다. 피부 비트맵은 skinMask와 같은 캐시 항목이다.
    static func contourRegions(
        face: FaceGeometry, extent: CGRect, tuning: RenderTuning, cache: RegionMaskCache? = nil
    ) -> ContourRegions? {
        guard let frame = FaceFrame(face: face, extent: extent) else { return nil }
        let width = frame.faceWidth
        let eye = frame.eyeLevel
        let mouth = frame.mouthLevel
        let contour = frame.contour.map(frame.local)
        guard let chin = contour.min(by: { $0.y < $1.y }) else { return nil }
        func oval(_ u: CGFloat, _ v: CGFloat, _ radiusU: CGFloat, _ radiusV: CGFloat) -> Oval {
            Oval(center: frame.imagePoint(u: u, v: v), radii: CGSize(width: radiusU, height: radiusV))
        }
        var shade: [Oval] = []
        var highlight: [Oval] = []
        let jawTarget = (mouth + chin.y) / 2
        for side in [CGFloat(-1), 1] {
            shade.append(
                oval(
                    side * width * MakeupShape.hollowOffset, mouth + (eye - mouth) * MakeupShape.hollowHeight,
                    width * MakeupShape.hollowRadiusU, width * MakeupShape.hollowRadiusV))
            let jaw = contour.filter { $0.y < mouth && $0.x * side > 0 }
                .min { abs($0.y - jawTarget) < abs($1.y - jawTarget) }
            if let jaw {
                shade.append(oval(jaw.x, jaw.y, width * MakeupShape.jawRadiusU, width * MakeupShape.jawRadiusV))
            }
        }
        if let nose = landmarkPolygon(face, .nose, extent)?.map(frame.local), let left = nose.map(\.x).min(),
            let right = nose.map(\.x).max(), let bottom = nose.map(\.y).min(), eye > bottom
        {
            let middle = (eye + bottom) / 2
            let half = (eye - bottom) / 2
            for u in [left, right] {
                shade.append(oval(u, middle, width * MakeupShape.noseSideRadiusU, half))
            }
            highlight.append(
                oval(
                    (left + right) / 2, middle, width * MakeupShape.bridgeRadiusU,
                    half * MakeupShape.bridgeLengthFraction))
        }
        highlight.append(
            oval(
                0, eye + width * MakeupShape.foreheadRise, width * MakeupShape.foreheadRadiusU,
                width * MakeupShape.foreheadRadiusV))
        highlight.append(
            oval(
                chin.x, chin.y + width * MakeupShape.chinRise, width * MakeupShape.chinRadiusU,
                width * MakeupShape.chinRadiusV))
        return ContourRegions(
            shade: softMask(shade, face: face, frame: frame, extent: extent, tuning: tuning, cache: cache),
            highlight: softMask(highlight, face: face, frame: frame, extent: extent, tuning: tuning, cache: cache))
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
            let turn = angle + oval.tilt
            shapes = MaskBuilder.ellipse(center: oval.center, radii: oval.radii, angle: turn, extent: extent)
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
