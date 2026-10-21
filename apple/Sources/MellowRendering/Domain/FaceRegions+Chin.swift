import CoreImage
import MellowShared

extension FaceRegions {
    /// 턱밑 띠 다각형이 되려면 필요한 입 높이 아래 윤곽점 수.
    private static let chinMinimumContourPoints = 2
    /// 입꼬리 좌우를 고르려면 필요한 바깥 입술 점 수.
    private static let chinMinimumLipPoints = 2

    /// 턱밑 그늘 띠(스펙 5.7). 아래턱 윤곽(얼굴 좌표 y < 입 높이)을 얼굴 좌표 아래로 얼굴 폭 × bandTop·bandBottom만큼 옮긴 두 선으로 닫는다.
    /// 가로는 입꼬리 x ± 얼굴 폭 × bandSideMargin에서 자르고 입술 점이 둘 미만이면 아래 윤곽 전체를 쓴다.
    /// 점은 extent 픽셀이다. 특징점이 부족하면 nil이다.
    static func chinBandPolygon(face: FaceGeometry, extent: CGRect) -> [CGPoint]? {
        guard let frame = FaceFrame(face: face, extent: extent) else { return nil }
        let width = frame.faceWidth
        let jaw = frame.contour.map(frame.local).filter { $0.y < frame.mouthLevel }.sorted { $0.x < $1.x }
        guard jaw.count >= chinMinimumContourPoints, let first = jaw.first, let last = jaw.last else { return nil }
        var left = first.x
        var right = last.x
        let lips = (face.landmarks[.outerLips] ?? []).map { point in
            frame.local(CGPoint(x: extent.minX + point.x * extent.width, y: extent.minY + point.y * extent.height))
        }
        if lips.count >= chinMinimumLipPoints, let leftCorner = lips.map(\.x).min(),
            let rightCorner = lips.map(\.x).max()
        {
            let margin = width * ChinShadeStage.bandSideMargin
            left = max(left, leftCorner - margin)
            right = min(right, rightCorner + margin)
        }
        guard right > left else { return nil }
        let line = clipped(jaw, from: left, to: right)
        guard line.count >= chinMinimumContourPoints else { return nil }
        let top = line.map { CGPoint(x: $0.x, y: $0.y - width * ChinShadeStage.bandTop) }
        let bottom = line.reversed().map { CGPoint(x: $0.x, y: $0.y - width * ChinShadeStage.bandBottom) }
        return (top + bottom).map { frame.imagePoint(u: $0.x, v: $0.y) }
    }

    /// 턱밑 띠를 얼굴 폭 × bandFeather로 흐린 마스크. 캐시 키는 다각형이다. 특징점이 부족하면 nil이다.
    static func chinBandMask(face: FaceGeometry, extent: CGRect, tuning: RenderTuning, cache: RegionMaskCache?)
        -> CIImage?
    {
        chinBandRegion(face: face, extent: extent, tuning: tuning, cache: cache)?.image
    }

    /// chinBandMask와 그 마스크가 0이 아닐 수 있는 영역.
    static func chinBandRegion(face: FaceGeometry, extent: CGRect, tuning: RenderTuning, cache: RegionMaskCache?)
        -> RegionMask?
    {
        guard let polygon = chinBandPolygon(face: face, extent: extent) else { return nil }
        let feather = max(
            CGFloat(tuning.skinBlurMinimumRadius), faceWidth(face, extent: extent) * ChinShadeStage.bandFeather)
        return featheredPolygonMask(
            fill: [polygon], cut: [], face: face, extent: extent, tuning: tuning, cache: cache, feather: feather)
    }

    /// 볼 기준 피부색 가중치(skinMask와 같은 Cb·Cr 거리). encoded는 sRGB 감마 이미지이고 area 안만 계산한다.
    /// 볼이 사진 밖이면 nil이다.
    static func chinSkinWeight(
        face: FaceGeometry, encoded: CIImage, area: CGRect, extent: CGRect, tuning: RenderTuning
    ) throws -> CIImage? {
        guard let cheeks = cheekAverages(of: encoded, face: face, extent: extent) else { return nil }
        return try SkinKernels.shared.chromaWeight(
            of: encoded, left: cheeks.left, right: cheeks.right, sigma: tuning.skinChromaSigma, extent: area)
    }

    /// x 순으로 정렬한 꺾은선을 left…right로 자른다. 끝은 선분 위 보간점이다.
    private static func clipped(_ line: [CGPoint], from left: CGFloat, to right: CGFloat) -> [CGPoint] {
        var result: [CGPoint] = []
        for (start, end) in zip(line, line.dropFirst()) {
            if left <= start.x, start.x <= right {
                result.append(start)
            }
            for edge in [left, right] where start.x < edge && edge < end.x {
                let t = (edge - start.x) / (end.x - start.x)
                result.append(CGPoint(x: edge, y: start.y + (end.y - start.y) * t))
            }
        }
        if let last = line.last, left <= last.x, last.x <= right {
            result.append(last)
        }
        return result
    }
}
