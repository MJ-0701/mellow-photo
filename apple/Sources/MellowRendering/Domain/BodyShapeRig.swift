import CoreImage
import MellowShared

/// 체형 슬라이더 7개를 이동 원소로 바꾼다(스펙 5). 좌표·길이는 extent 픽셀, 몸통 축과 어깨 폭은 BodySkeleton이 정한다.
/// 값은 여기서 AdjustmentRange로 자른다. 프리셋·일괄 적용 값은 편집 규칙의 클램프를 거치지 않기 때문이다.
/// 유한하지 않은 값은 0으로 본다. 음수는 가늘게·좁게·짧게, 양수는 넓게·길게다. 다리 길게만 0…1이고 띠 하나를 만든다.
/// push 이동 = 값 × min(항목 최대, bodyShapeMaxShift) × 어깨 폭. 반지름은 이동 / shapeDisplacementLimit 이상이라
/// DisplacementWarp가 얼굴 원소와 같은 상한을 써도 체형 이동이 몰래 줄지 않는다.
/// 필요한 관절이 없는 항목(또는 높이·팔다리 한쪽)만 건너뛴다.
enum BodyShapeRig {
    /// 팔다리 선분 하나. 양 끝 관절, 반폭(어깨 폭 비율), 이동 비율.
    private struct Limb {
        let start: BodyJoint
        let end: BodyJoint
        let halfWidth: CGFloat
        let shiftRatio: CGFloat
    }

    /// 원소를 만들 때 함께 쓰는 사람과 이동 상한.
    private struct Builder {
        let skeleton: BodySkeleton
        let limit: CGFloat
        /// 사람 마스크에서 찾은 몸통 옆선. 마스크가 없으면 nil이다.
        let outline: BodyOutline?
        let extent: CGRect

        var width: CGFloat { skeleton.torsoWidth }

        /// center를 direction(단위 벡터) × shift만큼 민다. 반지름은 base × 어깨 폭과 |shift| / limit 중 큰 값이다.
        func push(_ center: CGPoint, _ direction: CGVector, shift: CGFloat, radius base: CGFloat) -> ShapePrimitive {
            let radius = max(base * width, abs(shift) / limit)
            let vector = CGVector(dx: direction.dx * shift, dy: direction.dy * shift)
            return .push(center: center, vector: vector, radius: radius)
        }

        /// center에서 본 point 쪽 가로축 방향(바깥). 가로축 성분이 0이면 nil.
        func outward(_ point: CGPoint, from center: CGPoint) -> CGVector? {
            let side = skeleton.side(of: point, from: center)
            guard side != 0 else { return nil }
            return CGVector(dx: skeleton.across.dx * side, dy: skeleton.across.dy * side)
        }

        /// level 높이 옆선 원소의 중심(스펙 5.8).
        /// outline이 nil이면 관절선 점 그대로다(마스크 없는 렌더는 이전과 같은 원소).
        /// outline이 있으면 그 쪽 옆선 점이고 없으면 nil이다(팔이 붙음).
        func sideCenter(_ jointPoint: CGPoint, level: CGFloat, middle: CGPoint) -> CGPoint? {
            guard let outline else { return jointPoint }
            let side = skeleton.side(of: jointPoint, from: middle)
            guard side != 0, let point = outline.points[OutlineKey(level: Double(level), side: Int(side))] else {
                return nil
            }
            let x = extent.minX + CGFloat(point.x) * extent.width
            let y = extent.minY + CGFloat(point.y) * extent.height
            return CGPoint(x: x, y: y)
        }
    }

    /// 허리 높이. 어깨에서 엉덩이까지의 비율(스펙 55%).
    private static let waistLevel: CGFloat = 0.55
    /// 몸 전체의 가슴 높이. 어깨에서 엉덩이까지의 비율.
    private static let chestLevel: CGFloat = 0.3
    /// 부유방 높이(겨드랑이 아래 옆선). 어깨에서 엉덩이까지의 비율.
    private static let sideChestLevel: CGFloat = 0.27
    /// 부유방 push 기본 반지름. 어깨 폭 비율.
    private static let sideChestRadius: CGFloat = 0.14
    /// 사진 준비 때 몸통 옆선을 찾는 높이(부유방, 몸 전체의 가슴).
    static let outlineLevels: [Double] = [Double(sideChestLevel), Double(chestLevel)]
    /// 엉덩이 관절에서 골반 바깥 윤곽까지. 어깨 폭 비율. Vision 엉덩이 점은 윤곽보다 안쪽이다.
    private static let hipOutlineOffset: CGFloat = 0.12
    /// 허벅지 반폭. 어깨 폭 비율(허벅지 폭은 어깨 폭의 40% 안팎).
    private static let thighHalfWidth: CGFloat = 0.2
    /// 위팔·아래팔 반폭. 어깨 폭 비율.
    /// 팔 보호 캡슐 반지름도 이 값에서 정한다.
    static let upperArmHalfWidth: CGFloat = 0.12
    static let forearmHalfWidth: CGFloat = 0.09
    /// 위팔·허벅지는 항목 이동 그대로, 아래팔은 75%(아래팔이 가늘어 같은 이동이면 더 많이 줄어든다).
    private static let fullShift: CGFloat = 1
    private static let forearmShiftRatio: CGFloat = 0.75
    /// push 기본 반지름. 어깨 폭 비율. 몸통·팔다리는 기본 이동(≤ 0.06)의 3배 이상이다.
    private static let torsoRadius: CGFloat = 0.3
    private static let armRadius: CGFloat = 0.2
    private static let thighRadius: CGFloat = 0.3
    private static let shoulderRadius: CGFloat = 0.3
    /// 목 push 반지름. 어깨 폭 비율. 목 관절에서 0.2W 위에서 0이 되어 턱 끝(0.25~0.3W 위)과 입에 닿지 않는다.
    /// 승모근 점과의 간격(약 0.2W)과 같아 smoothstep 대칭(s(t) + s(1 − t) = 1)으로 그 사이 어깨선이 고르게 움직인다.
    /// 목 기본 이동(0.03)의 6.7배라 이동 / shapeDisplacementLimit(0.12)보다 크다.
    private static let neckRadius: CGFloat = 0.2
    /// 승모근 비탈 점. 목 관절에서 각 어깨 관절 쪽으로 간 비율. 어깨 관절까지 0.3W 남아 어깨 끝은 움직이지 않는다.
    private static let trapeziusLevel: CGFloat = 0.4
    /// 엉덩이가 발목보다 이만큼(어깨 폭 비율) 위에 있어야 다리 띠를 만든다. 누운 사람·거꾸로 된 사진은 건너뛴다.
    private static let minimumLegSpan: CGFloat = 0.5
    /// 이보다 짧은 팔다리 선분(픽셀)은 방향을 정할 수 없어 건너뛴다.
    private static let minimumSegmentLength: CGFloat = 1

    private static let armLimbs = [
        Limb(start: .leftShoulder, end: .leftElbow, halfWidth: upperArmHalfWidth, shiftRatio: fullShift),
        Limb(start: .leftElbow, end: .leftWrist, halfWidth: forearmHalfWidth, shiftRatio: forearmShiftRatio),
        Limb(start: .rightShoulder, end: .rightElbow, halfWidth: upperArmHalfWidth, shiftRatio: fullShift),
        Limb(start: .rightElbow, end: .rightWrist, halfWidth: forearmHalfWidth, shiftRatio: forearmShiftRatio),
    ]
    private static let thighLimbs = [
        Limb(start: .leftHip, end: .leftKnee, halfWidth: thighHalfWidth, shiftRatio: fullShift),
        Limb(start: .rightHip, end: .rightKnee, halfWidth: thighHalfWidth, shiftRatio: fullShift),
    ]

    /// 몸통 묶음(팔 보호를 받는 항목). 나머지 항목은 팔다리 묶음이다.
    private static let torsoKeys: Set<BodyShapeKey> = [.waist, .overall, .sideChest]

    /// 몸통·팔다리 묶음을 이은 원소. 다리 띠를 포함한다.
    static func primitives(
        body: BodyGeometry, adjustments: BodyShapeAdjustments, extent: CGRect, tuning: RenderTuning,
        outline: BodyOutline? = nil
    ) -> [ShapePrimitive] {
        let parts = groups(
            body: body, adjustments: adjustments, extent: extent, tuning: tuning, includesLegBand: true,
            outline: outline)
        return parts.torso + parts.limbs
    }

    /// 항목을 몸통(허리·몸 전체·부유방)과 팔다리(팔·허벅지·어깨·목·다리 띠)로 나눠 만든다(스펙 5.5).
    /// guards는 몸통 묶음이 받는 팔 캡슐이다. 관절이 없는 선분은 빠진다.
    /// includesLegBand가 false면 다리 길게를 건너뛴다(가장 큰 몸만 띠를 만든다).
    /// outline은 그 몸의 사람 마스크에서 찾은 몸통 옆선이다(BodyTarget.outline).
    /// 부유방·몸 전체 가슴 원소만 쓰고 nil이면 관절선 점을 쓴다.
    static func groups(
        body: BodyGeometry, adjustments: BodyShapeAdjustments, extent: CGRect, tuning: RenderTuning,
        includesLegBand: Bool, outline: BodyOutline? = nil
    ) -> (torso: [ShapePrimitive], limbs: [ShapePrimitive], guards: [ShapeGuard]) {
        guard adjustments.hasEffect, let skeleton = BodySkeleton(body: body, extent: extent, tuning: tuning) else {
            return ([], [], [])
        }
        let rig = Builder(
            skeleton: skeleton, limit: CGFloat(tuning.shapeDisplacementLimit), outline: outline, extent: extent)
        var torso: [ShapePrimitive] = []
        var limbs: [ShapePrimitive] = []
        for key in BodyShapeKey.allCases where includesLegBand || key != .legLength {
            let raw = adjustments[key]
            let value = AdjustmentRange.clamped(raw.isFinite ? raw : 0, to: AdjustmentRange.bodyShape(key))
            guard value != 0 else { continue }
            let made = primitives(for: key, value: CGFloat(value), rig: rig, tuning: tuning)
            if torsoKeys.contains(key) {
                torso += made
            } else {
                limbs += made
            }
        }
        return (torso, limbs, armGuards(skeleton, tuning: tuning))
    }

    /// 어깨–팔꿈치·팔꿈치–손목 캡슐. 반지름은 어깨 폭 × 반폭 × armGuardScale, feather는 어깨 폭 × armGuardFeather다.
    private static func armGuards(_ skeleton: BodySkeleton, tuning: RenderTuning) -> [ShapeGuard] {
        let width = skeleton.torsoWidth
        let scale = CGFloat(tuning.armGuardScale)
        let feather = width * CGFloat(tuning.armGuardFeather)
        return armLimbs.compactMap { limb in
            guard let start = skeleton.point(limb.start), let end = skeleton.point(limb.end) else { return nil }
            return .capsule(start: start, end: end, radius: width * limb.halfWidth * scale, feather: feather)
        }
    }

    private static func primitives(
        for key: BodyShapeKey, value: CGFloat, rig: Builder, tuning: RenderTuning
    ) -> [ShapePrimitive] {
        let maximum = CGFloat(min(tuning.bodyItemMaxShift(key), tuning.bodyShapeMaxShift))
        let shift = value * maximum * rig.width
        switch key {
        case .legLength: return legLength(rig.skeleton, stretch: value * CGFloat(tuning.bodyItemMaxShift(key)))
        case .waist: return waist(rig, shift: shift)
        case .overall: return overall(rig, shift: shift)
        case .arms: return limbs(rig, armLimbs, shift: shift, radius: armRadius)
        case .thighs: return limbs(rig, thighLimbs, shift: shift, radius: thighRadius)
        case .shoulders: return shoulders(rig, shift: shift)
        case .neck: return neck(rig, shift: shift)
        case .sideChest: return sideChest(rig, shift: shift)
        }
    }

    /// 두 엉덩이 중점에서 보이는 발목 평균까지 가로 띠를 아래로 늘린다. 엉덩이가 발목보다 충분히 위에 있어야 한다.
    private static func legLength(_ skeleton: BodySkeleton, stretch: CGFloat) -> [ShapePrimitive] {
        let ankles = [BodyJoint.leftAnkle, .rightAnkle].compactMap(skeleton.point)
        guard let hip = skeleton.hipCenter, !ankles.isEmpty else { return [] }
        let ankleY = ankles.map(\.y).reduce(0, +) / CGFloat(ankles.count)
        guard hip.y - ankleY >= minimumLegSpan * skeleton.torsoWidth else { return [] }
        return [.band(yStart: hip.y, yEnd: ankleY, stretch: stretch)]
    }

    /// 같은 쪽 어깨~엉덩이 55% 점을 가로축 안쪽(음수)이나 바깥으로 민다. 두 엉덩이가 있어야 한다.
    private static func waist(_ rig: Builder, shift: CGFloat) -> [ShapePrimitive] {
        guard let hipCenter = rig.skeleton.hipCenter else { return [] }
        let middle = BodySkeleton.lerp(rig.skeleton.shoulderCenter, hipCenter, waistLevel)
        return torsoSides(rig, level: waistLevel).compactMap { point in
            guard let direction = rig.outward(point, from: middle) else { return nil }
            return rig.push(point, direction, shift: shift, radius: torsoRadius)
        }
    }

    /// 27% 높이(겨드랑이 아래) 몸통 옆선 점을 가로축 안쪽으로 민다(스펙 5.8). 부유방은 0…1이다.
    /// 옆선 점은 몸통 옆선(rig.sideCenter)이고 마스크가 없으면 같은 쪽 어깨~엉덩이 27% 점이다.
    /// 두 엉덩이가 있어야 한다.
    private static func sideChest(_ rig: Builder, shift: CGFloat) -> [ShapePrimitive] {
        guard let hipCenter = rig.skeleton.hipCenter else { return [] }
        let middle = BodySkeleton.lerp(rig.skeleton.shoulderCenter, hipCenter, sideChestLevel)
        return torsoSides(rig, level: sideChestLevel).compactMap { point in
            guard let direction = rig.outward(point, from: middle),
                let center = rig.sideCenter(point, level: sideChestLevel, middle: middle)
            else { return nil }
            return rig.push(center, direction, shift: -shift, radius: sideChestRadius)
        }
    }

    /// 가슴·골반 바깥·허벅지 바깥 세 높이의 양옆을 민다. 두 엉덩이가 있어야 하고 허벅지 높이는 그쪽 무릎이 있어야 한다.
    /// 가슴 점은 부유방처럼 몸통 옆선(rig.sideCenter)이다. 골반·허벅지는 관절에서 정한다.
    private static func overall(_ rig: Builder, shift: CGFloat) -> [ShapePrimitive] {
        guard let hipCenter = rig.skeleton.hipCenter else { return [] }
        let chestMiddle = BodySkeleton.lerp(rig.skeleton.shoulderCenter, hipCenter, chestLevel)
        var result: [ShapePrimitive] = torsoSides(rig, level: chestLevel).compactMap { point in
            guard let direction = rig.outward(point, from: chestMiddle),
                let center = rig.sideCenter(point, level: chestLevel, middle: chestMiddle)
            else { return nil }
            return rig.push(center, direction, shift: shift, radius: torsoRadius)
        }
        for (hipJoint, kneeJoint) in [(BodyJoint.leftHip, BodyJoint.leftKnee), (.rightHip, .rightKnee)] {
            guard let hip = rig.skeleton.point(hipJoint), let direction = rig.outward(hip, from: hipCenter) else {
                continue
            }
            let hipOutline = offset(hip, direction, hipOutlineOffset * rig.width)
            result.append(rig.push(hipOutline, direction, shift: shift, radius: torsoRadius))
            guard let knee = rig.skeleton.point(kneeJoint) else { continue }
            let thighOutline = offset(BodySkeleton.midpoint(hip, knee), direction, thighHalfWidth * rig.width)
            result.append(rig.push(thighOutline, direction, shift: shift, radius: torsoRadius))
        }
        return result
    }

    /// 선분 가운데에서 수직으로 반폭만큼 떨어진 양옆 두 점을 선분 쪽(음수)이나 바깥으로 민다.
    private static func limbs(_ rig: Builder, _ limbs: [Limb], shift: CGFloat, radius: CGFloat) -> [ShapePrimitive] {
        limbs.flatMap { limb -> [ShapePrimitive] in
            guard let start = rig.skeleton.point(limb.start), let end = rig.skeleton.point(limb.end) else { return [] }
            let length = hypot(end.x - start.x, end.y - start.y)
            guard length >= minimumSegmentLength else { return [] }
            let normal = CGVector(dx: -(end.y - start.y) / length, dy: (end.x - start.x) / length)
            let middle = BodySkeleton.midpoint(start, end)
            return [CGFloat(1), -1].map { sign in
                let direction = CGVector(dx: normal.dx * sign, dy: normal.dy * sign)
                let center = offset(middle, direction, limb.halfWidth * rig.width)
                return rig.push(center, direction, shift: shift * limb.shiftRatio, radius: radius)
            }
        }
    }

    /// 각 어깨 관절을 가로축 바깥(양수)이나 안쪽으로 민다.
    private static func shoulders(_ rig: Builder, shift: CGFloat) -> [ShapePrimitive] {
        [BodyJoint.leftShoulder, .rightShoulder].compactMap { joint in
            guard let shoulder = rig.skeleton.point(joint),
                let direction = rig.outward(shoulder, from: rig.skeleton.shoulderCenter)
            else { return nil }
            return rig.push(shoulder, direction, shift: shift, radius: shoulderRadius)
        }
    }

    /// 목 관절(목 아래끝)과 양쪽 승모근 비탈 점을 몸통 아래쪽(양수)이나 위쪽으로 민다.
    /// 어깨선이 내려가 목이 길어지고 얼굴·머리는 그대로다. 턱 아래 0.2W에서 0이 된다.
    private static func neck(_ rig: Builder, shift: CGFloat) -> [ShapePrimitive] {
        guard let neck = rig.skeleton.point(.neck) else { return [] }
        let down = CGVector(dx: -rig.skeleton.up.dx, dy: -rig.skeleton.up.dy)
        let slopes = [BodyJoint.leftShoulder, .rightShoulder].compactMap(rig.skeleton.point).map { shoulder in
            BodySkeleton.lerp(neck, shoulder, trapeziusLevel)
        }
        return ([neck] + slopes).map { center in
            rig.push(center, down, shift: shift, radius: neckRadius)
        }
    }

    /// 같은 쪽 어깨와 엉덩이 사이 level 높이의 점. 엉덩이가 없는 쪽은 빠진다.
    private static func torsoSides(_ rig: Builder, level: CGFloat) -> [CGPoint] {
        [(BodyJoint.leftShoulder, BodyJoint.leftHip), (.rightShoulder, .rightHip)].compactMap { shoulder, hip in
            guard let top = rig.skeleton.point(shoulder), let bottom = rig.skeleton.point(hip) else { return nil }
            return BodySkeleton.lerp(top, bottom, level)
        }
    }

    private static func offset(_ point: CGPoint, _ direction: CGVector, _ distance: CGFloat) -> CGPoint {
        CGPoint(x: point.x + direction.dx * distance, y: point.y + direction.dy * distance)
    }
}
