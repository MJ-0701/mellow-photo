import CoreImage
import MellowShared

extension FaceRegions {
    /// 콧구멍 띠의 볼록 껍질을 만들려면 필요한 코 점 수.
    private static let minimumHullPoints = 3

    /// 점 지우기(스펙 G5 4.2)에서 뺄 영역.
    /// 코 다각형 아래 spotNostrilBandFraction 높이(콧구멍), 두 눈과 바깥 입술의 u 최소·최대 점 둘레 원이다.
    /// u·v는 얼굴 좌표(FaceFrame)이고, 얼굴 좌표가 없으면 이미지 x·y다.
    /// 특징점이 없는 부위는 뺀다(빈 목록 가능).
    static func spotExclusionPolygons(face: FaceGeometry, extent: CGRect, tuning: RenderTuning) -> [[CGPoint]] {
        let frame = FaceFrame(face: face, extent: extent)
        let toLocal: (CGPoint) -> CGPoint = { point in frame?.local(point) ?? point }
        let toImage: (CGPoint) -> CGPoint = { point in frame?.imagePoint(u: point.x, v: point.y) ?? point }
        let radius = faceWidth(face, extent: extent) * CGFloat(tuning.spotExclusionRadiusFraction)
        var polygons: [[CGPoint]] = []
        if let nose = landmarkPolygon(face, .nose, extent)?.map(toLocal) {
            polygons.append(nostrilBand(nose, fraction: CGFloat(tuning.spotNostrilBandFraction)).map(toImage))
        }
        for landmark in [FaceLandmark.leftEye, .rightEye, .outerLips] {
            guard let polygon = landmarkPolygon(face, landmark, extent)?.map(toLocal),
                let left = polygon.min(by: { $0.x < $1.x }), let right = polygon.max(by: { $0.x < $1.x })
            else { continue }
            for corner in [toImage(left), toImage(right)] {
                let diameter = radius * 2
                let circle = CGRect(x: corner.x - radius, y: corner.y - radius, width: diameter, height: diameter)
                polygons.append(ellipsePolygon(in: circle))
            }
        }
        return polygons
    }

    /// 점 지우기 제외 비트맵(흐리기 전).
    /// 캐시 항목 하나다.
    static func spotExclusionRaster(face: FaceGeometry, extent: CGRect, tuning: RenderTuning, cache: RegionMaskCache?)
        -> CIImage
    {
        polygonMask(
            fill: spotExclusionPolygons(face: face, extent: extent, tuning: tuning), cut: [], cutWidth: 0,
            extent: extent, tuning: tuning, cache: cache)
    }

    /// 점 지우기 마스크 = 피부 마스크 × (1 − 흐린 제외 비트맵).
    static func spotMask(
        face: FaceGeometry, skinMask: CIImage, extent: CGRect, tuning: RenderTuning, cache: RegionMaskCache?
    ) -> CIImage {
        let raster = spotExclusionRaster(face: face, extent: extent, tuning: tuning, cache: cache)
        let keep = raster.clampedToExtent()
            .applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: featherRadius(face, extent, tuning)])
            .cropped(to: extent).applyingFilter("CIColorInvert")
        return skinMask.applyingFilter("CIMultiplyCompositing", parameters: [kCIInputBackgroundImageKey: keep])
            .cropped(to: extent)
    }

    /// 코 다각형(얼굴 좌표) 중 v가 아래 fraction 높이 안인 점들의 볼록 껍질.
    /// 점이 셋보다 적으면 코 상자 아래 fraction 높이 사각형이다.
    private static func nostrilBand(_ nose: [CGPoint], fraction: CGFloat) -> [CGPoint] {
        let box = boundingRect(nose)
        let top = box.minY + box.height * fraction
        let lower = nose.filter { $0.y <= top }
        if lower.count >= minimumHullPoints {
            let hull = convexHull(lower)
            if hull.count >= minimumHullPoints {
                return hull
            }
        }
        return [
            CGPoint(x: box.minX, y: box.minY), CGPoint(x: box.maxX, y: box.minY), CGPoint(x: box.maxX, y: top),
            CGPoint(x: box.minX, y: top),
        ]
    }

    /// 단조 사슬 볼록 껍질(반시계 방향).
    /// 한 줄에 놓인 점은 뺀다.
    static func convexHull(_ points: [CGPoint]) -> [CGPoint] {
        let sorted = points.sorted { $0.x == $1.x ? $0.y < $1.y : $0.x < $1.x }
        guard sorted.count >= minimumHullPoints else { return sorted }
        func cross(_ origin: CGPoint, _ a: CGPoint, _ b: CGPoint) -> CGFloat {
            let first: CGFloat = (a.x - origin.x) * (b.y - origin.y)
            let second: CGFloat = (a.y - origin.y) * (b.x - origin.x)
            return first - second
        }
        var lower: [CGPoint] = []
        for point in sorted {
            while lower.count >= 2, cross(lower[lower.count - 2], lower[lower.count - 1], point) <= 0 {
                lower.removeLast()
            }
            lower.append(point)
        }
        var upper: [CGPoint] = []
        for point in sorted.reversed() {
            while upper.count >= 2, cross(upper[upper.count - 2], upper[upper.count - 1], point) <= 0 {
                upper.removeLast()
            }
            upper.append(point)
        }
        return Array(lower.dropLast()) + Array(upper.dropLast())
    }
}
