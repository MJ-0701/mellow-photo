import CoreImage
import MellowShared

/// 얼굴형 슬라이더 10개를 이동 원소로 바꾼다. 좌표·길이는 extent 픽셀, 원소 위치는 FaceFrame 얼굴 좌표로 고른다.
/// 값은 여기서 AdjustmentRange로 자른다. 프리셋·일괄 적용 값은 편집 규칙의 클램프를 거치지 않기 때문이다.
/// push 항목의 이동 = 값 × 항목 최대 × 얼굴 폭 × yaw 약화, scale 항목의 배율 = 값 × 항목 최대 배율 × yaw 약화.
enum FaceShapeRig {
    /// 얼굴 중심선 한쪽의 윤곽점.
    private struct ContourSide {
        /// 왼쪽 −1, 오른쪽 +1(얼굴 x축 기준).
        let side: CGFloat
        let points: [CGPoint]
    }

    /// 바깥 입술의 중심, 입꼬리 두 점, 얼굴 x축 방향 폭.
    private struct Mouth {
        let center: CGPoint
        let corners: [CGPoint]
        let width: CGFloat
    }

    /// width·jaw 윤곽 push 반지름. 얼굴 폭 비율.
    private static let contourRadius: CGFloat = 0.22
    /// cheekbone push 반지름. 얼굴 폭 비율.
    private static let cheekboneRadius: CGFloat = 0.2
    /// jaw가 위로 드는 양. 안쪽 이동 대비.
    private static let jawLiftRatio: CGFloat = 0.5
    /// 턱 끝 가까운 윤곽점은 jaw에서 뺀다(턱 길이는 chinLength 몫). 얼굴 폭 비율.
    private static let jawCenterExclusion: CGFloat = 0.1
    /// eyeSize scale 반지름. 눈 폭 대비(스펙 1.2).
    private static let eyeScaleRadius: CGFloat = 1.2
    /// eyeDistance push 반지름. 눈 폭 대비. 눈 전체와 눈꺼풀을 함께 옮긴다.
    private static let eyeShiftRadius: CGFloat = 1.3
    /// noseWidth push 반지름. 얼굴 폭 비율. 코 날개 둘이 가운데서 서로 상쇄되는 크기.
    private static let noseWingRadius: CGFloat = 0.1
    /// mouthSize scale 반지름. 입 폭 대비. 입꼬리(입 폭의 절반)를 넉넉히 덮는다.
    private static let mouthScaleRadius: CGFloat = 0.75
    /// smile push 반지름. 입 폭 대비.
    private static let mouthCornerRadius: CGFloat = 0.35
    /// 입꼬리가 바깥으로 가는 양. 위쪽 이동 대비.
    private static let smileOutwardRatio: CGFloat = 0.4
    /// forehead push 중심을 눈썹 위끝에서 올리는 거리와 반지름. 얼굴 폭 비율. 눈썹은 감쇠 끝자락(5% 안팎)만 받는다.
    private static let foreheadOffset: CGFloat = 0.3
    private static let foreheadRadius: CGFloat = 0.35
    /// 눈썹 점이 없을 때 눈 높이 위로 눈썹 위끝을 어림하는 거리. 얼굴 폭 비율.
    private static let fallbackBrowRise: CGFloat = 0.12
    /// chinLength push 반지름. 얼굴 폭 비율. 입(턱 끝에서 얼굴 폭의 약 30% 위)에는 닿지 않는다.
    private static let chinRadius: CGFloat = 0.25
    /// 좌우 끝점을 고르려면 필요한 점 수.
    private static let minimumFeaturePoints = 2
    /// 두 눈 중심이 얼굴 폭의 이 비율보다 가까우면 눈 원소를 만들지 않는다.
    /// 두 눈동자가 한 점이면 FaceFrame이 같은 중심의 눈 둘을 주므로 한 점에 scale·push가 두 번 걸린다.
    /// FaceFrame이 눈으로 방향을 정하는 기준(5%)과 같다.
    private static let minimumEyeSeparation: CGFloat = 0.05
    /// 눈 원소를 만들려면 필요한 눈 수.
    private static let eyeCount = 2
    /// 이보다 작은 yaw 약화는 원소를 만들지 않는다(옆얼굴).
    private static let negligibleAttenuation = 1e-3

    static func primitives(
        face: FaceGeometry, adjustments: FaceShapeAdjustments, extent: CGRect, tuning: RenderTuning
    ) -> [ShapePrimitive] {
        guard adjustments.hasEffect, let frame = FaceFrame(face: face, extent: extent) else { return [] }
        let attenuation = yawAttenuation(face.yaw, tuning: tuning)
        guard attenuation > negligibleAttenuation else { return [] }
        var result: [ShapePrimitive] = []
        for key in FaceShapeKey.allCases {
            let value = AdjustmentRange.clamped(adjustments[key], to: AdjustmentRange.faceShape(key))
            guard value != 0 else { continue }
            let amount = CGFloat(value * tuning.faceShapeMaxShift(key) * attenuation)
            result += primitives(for: key, amount: amount, frame: frame)
        }
        return result
    }

    /// |yaw| ≤ 기준이면 1, 넘으면 cos(|yaw|) / cos(기준). 옆얼굴(π/2)에서 0으로 이어진다.
    static func yawAttenuation(_ yaw: Double?, tuning: RenderTuning) -> Double {
        guard let yaw, abs(yaw) > tuning.faceShapeYawThreshold else { return 1 }
        return max(0, cos(min(abs(yaw), Double.pi / 2)) / cos(tuning.faceShapeYawThreshold))
    }

    private static func primitives(for key: FaceShapeKey, amount: CGFloat, frame: FaceFrame) -> [ShapePrimitive] {
        let shift = amount * frame.faceWidth
        switch key {
        case .width: return width(frame, shift: shift)
        case .jaw: return jaw(frame, shift: shift)
        case .cheekbone: return cheekbone(frame, shift: shift)
        case .eyeSize: return eyeSize(frame, factor: amount)
        case .eyeDistance: return eyeDistance(frame, shift: shift)
        case .noseWidth: return noseWidth(frame, shift: shift)
        case .mouthSize: return mouthSize(frame, factor: amount)
        case .smile: return smile(frame, shift: shift)
        case .forehead: return forehead(frame, shift: shift)
        case .chinLength: return chinLength(frame, shift: shift)
        }
    }

    /// 눈~입 높이 윤곽점을 중심선 쪽(음수)이나 바깥(양수)으로 민다. 한쪽 합이 shift가 되게 점 수로 나눈다.
    private static func width(_ frame: FaceFrame, shift: CGFloat) -> [ShapePrimitive] {
        let radius = contourRadius * frame.faceWidth
        let sides = contourSides(frame) { frame.mouthLevel <= $0.y && $0.y <= frame.eyeLevel }
        return sides.flatMap { group in
            group.points.map { point in
                let share = group.side * shift / CGFloat(group.points.count)
                return ShapePrimitive.push(center: point, vector: frame.vector(u: share, v: 0), radius: radius)
            }
        }
    }

    /// 입 아래 윤곽점을 안쪽·위(음수, V라인)나 바깥·아래로 민다. 턱 끝 가까운 점은 뺀다.
    private static func jaw(_ frame: FaceFrame, shift: CGFloat) -> [ShapePrimitive] {
        let radius = contourRadius * frame.faceWidth
        let exclusion = jawCenterExclusion * frame.faceWidth
        let sides = contourSides(frame) { $0.y < frame.mouthLevel && abs($0.x) >= exclusion }
        return sides.flatMap { group in
            group.points.map { point in
                let count = CGFloat(group.points.count)
                let vector = frame.vector(u: group.side * shift / count, v: -shift * jawLiftRatio / count)
                return ShapePrimitive.push(center: point, vector: vector, radius: radius)
            }
        }
    }

    /// 각 쪽에서 가장 높은 윤곽점(Vision 윤곽의 위끝, 관자놀이~광대)을 안쪽(음수)이나 바깥으로 민다.
    private static func cheekbone(_ frame: FaceFrame, shift: CGFloat) -> [ShapePrimitive] {
        let radius = cheekboneRadius * frame.faceWidth
        return contourSides(frame) { _ in true }.compactMap { group in
            guard let top = group.points.max(by: { frame.local($0).y < frame.local($1).y }) else { return nil }
            return .push(center: top, vector: frame.vector(u: group.side * shift, v: 0), radius: radius)
        }
    }

    /// 각 눈 중심을 반지름 = 눈 폭 × 1.2로 확대(양수)하거나 축소한다.
    private static func eyeSize(_ frame: FaceFrame, factor: CGFloat) -> [ShapePrimitive] {
        separatedEyes(frame).map { .scale(center: $0.center, factor: factor, radius: $0.width * eyeScaleRadius) }
    }

    /// 각 눈을 중심선에서 멀어지게(양수) 하거나 가깝게 민다.
    private static func eyeDistance(_ frame: FaceFrame, shift: CGFloat) -> [ShapePrimitive] {
        separatedEyes(frame).compactMap { eye in
            let side = side(of: frame.local(eye.center).x)
            guard side != 0 else { return nil }
            return .push(
                center: eye.center, vector: frame.vector(u: side * shift, v: 0), radius: eye.width * eyeShiftRadius)
        }
    }

    /// nose 영역의 좌우 끝점(코 날개)을 noseCrest(없으면 nose) 중심 쪽(음수)이나 바깥으로 민다.
    private static func noseWidth(_ frame: FaceFrame, shift: CGFloat) -> [ShapePrimitive] {
        let nose = frame.points(.nose)
        guard nose.count >= minimumFeaturePoints,
            let leftWing = nose.min(by: { frame.local($0).x < frame.local($1).x }),
            let rightWing = nose.max(by: { frame.local($0).x < frame.local($1).x })
        else { return [] }
        let crest = frame.points(.noseCrest)
        let middle = frame.local(FaceFrame.centroid(crest.isEmpty ? nose : crest)).x
        let radius = noseWingRadius * frame.faceWidth
        return [leftWing, rightWing].compactMap { wing in
            let side = side(of: frame.local(wing).x - middle)
            guard side != 0 else { return nil }
            return .push(center: wing, vector: frame.vector(u: side * shift, v: 0), radius: radius)
        }
    }

    /// 바깥 입술 중심을 확대(양수)하거나 축소한다.
    private static func mouthSize(_ frame: FaceFrame, factor: CGFloat) -> [ShapePrimitive] {
        guard let mouth = mouth(frame) else { return [] }
        return [.scale(center: mouth.center, factor: factor, radius: mouth.width * mouthScaleRadius)]
    }

    /// 입꼬리 두 점을 위·바깥으로 민다. 미소는 0…1이다.
    private static func smile(_ frame: FaceFrame, shift: CGFloat) -> [ShapePrimitive] {
        guard let mouth = mouth(frame) else { return [] }
        let middle = frame.local(mouth.center).x
        let radius = mouth.width * mouthCornerRadius
        return mouth.corners.compactMap { corner in
            let side = side(of: frame.local(corner).x - middle)
            guard side != 0 else { return nil }
            let vector = frame.vector(u: side * smileOutwardRatio * shift, v: shift)
            return .push(center: corner, vector: vector, radius: radius)
        }
    }

    /// 눈썹 위끝에서 얼굴 폭 × 0.3 위를 중심으로 이마를 위(양수, 이마가 넓어짐)나 아래로 민다.
    private static func forehead(_ frame: FaceFrame, shift: CGFloat) -> [ShapePrimitive] {
        let brows = (frame.points(.leftEyebrow) + frame.points(.rightEyebrow)).map(frame.local)
        let browTop = brows.map(\.y).max() ?? frame.eyeLevel + fallbackBrowRise * frame.faceWidth
        let browMiddle = brows.isEmpty ? 0 : brows.map(\.x).reduce(0, +) / CGFloat(brows.count)
        let center = frame.imagePoint(u: browMiddle, v: browTop + foreheadOffset * frame.faceWidth)
        return [.push(center: center, vector: frame.vector(u: 0, v: shift), radius: foreheadRadius * frame.faceWidth)]
    }

    /// 가장 낮은 윤곽점(턱 끝)을 아래(양수, 턱이 길어짐)나 위로 민다.
    private static func chinLength(_ frame: FaceFrame, shift: CGFloat) -> [ShapePrimitive] {
        guard let chin = frame.contour.min(by: { frame.local($0).y < frame.local($1).y }) else { return [] }
        return [.push(center: chin, vector: frame.vector(u: 0, v: -shift), radius: chinRadius * frame.faceWidth)]
    }

    /// 중심선 왼쪽·오른쪽 윤곽점 중 얼굴 좌표 조건에 맞는 점. 중심선 위의 점은 빠진다.
    private static func contourSides(_ frame: FaceFrame, where include: (CGPoint) -> Bool) -> [ContourSide] {
        [CGFloat(-1), 1].map { side in
            ContourSide(
                side: side,
                points: frame.contour.filter { point in
                    let local = frame.local(point)
                    return local.x * side > 0 && include(local)
                })
        }
    }

    /// 서로 떨어진 두 눈. 눈이 둘이 아니거나 두 중심이 너무 가까우면 빈 배열.
    private static func separatedEyes(_ frame: FaceFrame) -> [FaceFrame.Eye] {
        let eyes = frame.eyes
        guard eyes.count == eyeCount else { return [] }
        let gap = hypot(eyes[1].center.x - eyes[0].center.x, eyes[1].center.y - eyes[0].center.y)
        return gap > minimumEyeSeparation * frame.faceWidth ? eyes : []
    }

    private static func mouth(_ frame: FaceFrame) -> Mouth? {
        let lips = frame.points(.outerLips)
        guard lips.count >= minimumFeaturePoints,
            let left = lips.min(by: { frame.local($0).x < frame.local($1).x }),
            let right = lips.max(by: { frame.local($0).x < frame.local($1).x })
        else { return nil }
        let width = frame.local(right).x - frame.local(left).x
        guard width > 0 else { return nil }
        return Mouth(center: FaceFrame.centroid(lips), corners: [left, right], width: width)
    }

    /// 얼굴 좌표 u의 부호. 0이면 0.
    private static func side(of u: CGFloat) -> CGFloat {
        if u > 0 {
            return 1
        }
        if u < 0 {
            return -1
        }
        return 0
    }
}
