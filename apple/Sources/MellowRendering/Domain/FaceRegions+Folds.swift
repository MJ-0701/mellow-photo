import CoreImage
import MellowShared

/// 주름 띠 위치 비율. 특징점에 주름선이 없어 코 날개·입꼬리·눈썹 안쪽 끝으로 어림한 값이다.
/// 길이는 얼굴 폭·눈 폭·눈 높이 기준, 각도는 얼굴 x축 기준이다.
private enum FoldShape {
    /// 다크서클 중심을 눈 아래끝에서 내리는 양. 눈 높이 배수.
    static let darkCircleDrop: CGFloat = 0.6
    /// 다크서클 타원 반지름. 눈 폭·눈 높이 배수.
    static let darkCircleRadiusU: CGFloat = 0.6
    static let darkCircleRadiusV: CGFloat = 0.8
    /// 눈 다각형을 그 눈의 것으로 보는 중심 거리 상한. 눈 폭 배수.
    static let eyeMatchDistance: CGFloat = 1
    /// 팔자 띠의 반 길이(코 날개 → 입꼬리 선분 길이 배수)와 반 폭(얼굴 폭 비율).
    static let nasolabialHalfLength: CGFloat = 0.55
    static let nasolabialHalfWidth: CGFloat = 0.035
    /// 띠를 선분에서 얼굴 바깥쪽으로 미는 양. 얼굴 폭 비율. 주름은 선분보다 바깥에 있다. 마리오네트도 같은 값을 쓴다.
    static let nasolabialOutset: CGFloat = 0.02
    /// 마리오네트 띠 길이(입꼬리에서 턱 쪽으로)와 타원 반지름. 얼굴 폭 비율.
    static let marionetteLength: CGFloat = 0.12
    static let marionetteRadiusU: CGFloat = 0.07
    static let marionetteRadiusV: CGFloat = 0.03
    /// 마리오네트 띠 방향. 얼굴 −v(턱 쪽)에서 바깥쪽으로 기운 각도(라디안, 약 15°). 입꼬리 아래에는 특징점이 없어 고정한다.
    static let marionetteTiltFromVertical: CGFloat = 0.26
    /// 미간 타원. 안쪽 눈썹 끝 간격의 절반에 더하는 여유와 세로 반지름. 얼굴 폭 비율.
    static let glabellaMargin: CGFloat = 0.01
    static let glabellaRadiusV: CGFloat = 0.07
    /// 눈썹 안쪽 끝으로 치는 점의 허용 오차. 얼굴 폭 비율.
    static let browEndTolerance: CGFloat = 0.01
}

extension FaceRegions {
    /// 눈 아래 다크서클 띠. 두 눈 중심이 있어야 하고, 눈 다각형이 없는 눈은 뺀다. 눈 안은 피부 비트맵의 보호 영역이 0으로 만든다.
    static func darkCircleMask(
        face: FaceGeometry, extent: CGRect, tuning: RenderTuning, cache: RegionMaskCache? = nil
    ) -> RegionMask? {
        guard let frame = FaceFrame(face: face, extent: extent), frame.eyes.count == 2 else { return nil }
        let polygons = eyePolygons(face: face, extent: extent).map { $0.map(frame.local) }
        var ovals: [Oval] = []
        for eye in frame.eyes {
            let center = frame.local(eye.center)
            let nearest = polygons.min {
                abs(FaceFrame.centroid($0).x - center.x) < abs(FaceFrame.centroid($1).x - center.x)
            }
            guard let polygon = nearest,
                abs(FaceFrame.centroid(polygon).x - center.x) < eye.width * FoldShape.eyeMatchDistance,
                let top = polygon.map(\.y).max(), let bottom = polygon.map(\.y).min(), top > bottom
            else { continue }
            let height = top - bottom
            let oval = Oval(
                center: frame.imagePoint(u: center.x, v: bottom - height * FoldShape.darkCircleDrop),
                radii: CGSize(
                    width: eye.width * FoldShape.darkCircleRadiusU, height: height * FoldShape.darkCircleRadiusV))
            ovals.append(oval)
        }
        return softMask(ovals, face: face, frame: frame, extent: extent, tuning: tuning, cache: cache)
    }

    /// 팔자 띠(코 날개 → 입꼬리). 코와 바깥 입술이 있어야 한다.
    static func nasolabialMask(
        face: FaceGeometry, extent: CGRect, tuning: RenderTuning, cache: RegionMaskCache? = nil
    ) -> RegionMask? {
        guard let frame = FaceFrame(face: face, extent: extent),
            let nose = landmarkPolygon(face, .nose, extent)?.map(frame.local),
            let lips = landmarkPolygon(face, .outerLips, extent)?.map(frame.local)
        else { return nil }
        let width = frame.faceWidth
        let midline = eyeMidline(frame)
        var ovals: [Oval] = []
        for side in [CGFloat(-1), 1] {
            guard let wing = nose.max(by: { ($0.x - midline) * side < ($1.x - midline) * side }),
                let corner = lips.max(by: { ($0.x - midline) * side < ($1.x - midline) * side })
            else { continue }
            let dx = corner.x - wing.x
            let dy = corner.y - wing.y
            let length = hypot(dx, dy)
            guard length > 0 else { continue }
            let direction = CGPoint(x: dx / length, y: dy / length)
            let middle = CGPoint(x: (wing.x + corner.x) / 2, y: (wing.y + corner.y) / 2)
            ovals.append(
                bandOval(
                    frame: frame, center: middle, direction: direction, side: side,
                    radii: CGSize(
                        width: length * FoldShape.nasolabialHalfLength, height: width * FoldShape.nasolabialHalfWidth)))
        }
        return softMask(ovals, face: face, frame: frame, extent: extent, tuning: tuning, cache: cache)
    }

    /// 마리오네트 띠(입꼬리 → 턱 쪽). 바깥 입술만 있으면 된다. 방향은 얼굴 −v에서 바깥쪽으로 marionetteTiltFromVertical 기운 고정값이다.
    static func marionetteMask(
        face: FaceGeometry, extent: CGRect, tuning: RenderTuning, cache: RegionMaskCache? = nil
    ) -> RegionMask? {
        guard let frame = FaceFrame(face: face, extent: extent),
            let lips = landmarkPolygon(face, .outerLips, extent)?.map(frame.local)
        else { return nil }
        let width = frame.faceWidth
        let midline = eyeMidline(frame)
        let along = CGFloat(sin(Double(FoldShape.marionetteTiltFromVertical)))
        let down = CGFloat(cos(Double(FoldShape.marionetteTiltFromVertical)))
        var ovals: [Oval] = []
        for side in [CGFloat(-1), 1] {
            guard let corner = lips.max(by: { ($0.x - midline) * side < ($1.x - midline) * side }) else { continue }
            let direction = CGPoint(x: side * along, y: -down)
            let half = width * FoldShape.marionetteLength / 2
            let middle = CGPoint(x: corner.x + direction.x * half, y: corner.y + direction.y * half)
            ovals.append(
                bandOval(
                    frame: frame, center: middle, direction: direction, side: side,
                    radii: CGSize(
                        width: width * FoldShape.marionetteRadiusU, height: width * FoldShape.marionetteRadiusV)))
        }
        return softMask(ovals, face: face, frame: frame, extent: extent, tuning: tuning, cache: cache)
    }

    /// 얼굴 좌표의 중심·방향으로 놓는 띠 타원. 중심을 방향에 수직인 바깥쪽(side)으로 얼굴 폭 × nasolabialOutset 민다.
    private static func bandOval(frame: FaceFrame, center: CGPoint, direction: CGPoint, side: CGFloat, radii: CGSize)
        -> Oval
    {
        var normal = CGPoint(x: -direction.y, y: direction.x)
        if normal.x * side < 0 {
            normal = CGPoint(x: -normal.x, y: -normal.y)
        }
        let outset = frame.faceWidth * FoldShape.nasolabialOutset
        let shifted = CGPoint(x: center.x + normal.x * outset, y: center.y + normal.y * outset)
        return Oval(
            center: frame.imagePoint(u: shifted.x, v: shifted.y), radii: radii, tilt: atan2(direction.y, direction.x))
    }

    /// 두 눈썹 안쪽 끝 사이의 미간. 눈썹이 둘 다 있어야 한다.
    static func glabellaMask(
        face: FaceGeometry, extent: CGRect, tuning: RenderTuning, cache: RegionMaskCache? = nil
    ) -> RegionMask? {
        guard let frame = FaceFrame(face: face, extent: extent) else { return nil }
        let brows = [FaceLandmark.leftEyebrow, .rightEyebrow].compactMap {
            landmarkPolygon(face, $0, extent)?.map(frame.local)
        }
        guard brows.count == 2 else { return nil }
        let width = frame.faceWidth
        let midline = eyeMidline(frame)
        let ends = brows.map { innerEnd(of: $0, midline: midline, tolerance: width * FoldShape.browEndTolerance) }
        let gap = abs(ends[0].x - ends[1].x)
        let center = CGPoint(x: (ends[0].x + ends[1].x) / 2, y: (ends[0].y + ends[1].y) / 2)
        let oval = Oval(
            center: frame.imagePoint(u: center.x, v: center.y),
            radii: CGSize(width: gap / 2 + width * FoldShape.glabellaMargin, height: width * FoldShape.glabellaRadiusV))
        return softMask([oval], face: face, frame: frame, extent: extent, tuning: tuning, cache: cache)
    }

    /// 눈썹 점 중 두 눈 가운데 선에 가장 가까운 점들(tolerance 안)의 평균. 위아래 두 줄인 눈썹은 가운데 높이가 된다.
    private static func innerEnd(of brow: [CGPoint], midline: CGFloat, tolerance: CGFloat) -> CGPoint {
        let nearest = brow.map { abs($0.x - midline) }.min() ?? 0
        return FaceFrame.centroid(brow.filter { abs($0.x - midline) <= nearest + tolerance })
    }
}
