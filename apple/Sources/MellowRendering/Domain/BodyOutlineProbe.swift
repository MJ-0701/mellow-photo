import CoreImage
import MellowShared

/// 사람 마스크에서 몸통 옆선 점을 찾는다(스펙 5.8).
/// Vision 어깨 관절은 팔이 붙는 자리라 어깨~엉덩이 관절선 점이 팔 보호 캡슐 안에 들어간다.
/// 그래서 부유방·몸 전체 가슴 원소는 실제 몸통 경계에 둔다.
/// 높이마다 몸 가운데 점 C = lerp(어깨 중점, 엉덩이 중점, level)에서 몸통 가로축으로 양쪽을 걷는다.
/// 마스크 값이 personMinimum 미만인 첫 표본을 만나면 그 직전 표본이 옆선이다.
/// 그 전에 같은 쪽 위팔 선분(어깨–팔꿈치, 팔꿈치가 없으면 어깨 관절)에서 팔 캡슐 반지름 + feather 안인 표본에 닿으면 팔이 붙은 것이라 점이 없다.
/// feather까지 보는 것은 찾은 점이 보호가 이동을 줄이는 가장자리 띠 안에 들지 않게 하려는 것이다.
/// 끝까지 배경을 못 만나거나 C가 배경이어도 점이 없다.
enum BodyOutlineProbe {
    /// 한 걸음. 어깨 폭 비율.
    private static let outlineProbeStep: CGFloat = 0.01
    /// 가장 멀리 걷는 거리. 어깨 폭 비율.
    private static let outlineProbeReach: CGFloat = 0.8
    /// 이 값 미만인 마스크 표본을 배경으로 본다. 경계 중간값이다.
    private static let personMinimum: Double = 0.5
    /// 몸통 가로축의 두 쪽.
    private static let sides = [-1, 1]

    /// 두 엉덩이가 없으면 빈 옆선이다.
    /// 팔 판정 거리는 렌더의 팔 보호와 같은 반지름(어깨 폭 × upperArmHalfWidth × armGuardScale)에 feather(어깨 폭 × armGuardFeather)를 더한 값이다.
    static func probe(
        skeleton: BodySkeleton, mask: MaskSampler, extent: CGRect, levels: [Double], tuning: RenderTuning
    ) -> BodyOutline {
        guard let hipCenter = skeleton.hipCenter, extent.width > 0, extent.height > 0 else {
            return BodyOutline(points: [:])
        }
        let width = skeleton.torsoWidth
        let guardRadius = width * BodyShapeRig.upperArmHalfWidth * CGFloat(tuning.armGuardScale)
        let armRadius = guardRadius + width * CGFloat(tuning.armGuardFeather)
        var points: [OutlineKey: NormalizedPoint] = [:]
        for level in levels {
            let center = BodySkeleton.lerp(skeleton.shoulderCenter, hipCenter, CGFloat(level))
            for side in sides {
                let sign = CGFloat(side)
                let direction = CGVector(dx: skeleton.across.dx * sign, dy: skeleton.across.dy * sign)
                let walk = Walk(
                    center: center, direction: direction, step: width * outlineProbeStep,
                    arm: upperArm(skeleton, side: sign), armRadius: armRadius)
                guard let edge = walk.edge(mask: mask, extent: extent) else { continue }
                points[OutlineKey(level: level, side: side)] = normalized(edge, in: extent)
            }
        }
        return BodyOutline(points: points)
    }

    /// 한 높이·한 쪽의 걷기.
    private struct Walk {
        let center: CGPoint
        let direction: CGVector
        let step: CGFloat
        /// 같은 쪽 위팔 선분. 팔꿈치가 없으면 두 끝이 어깨 관절이다.
        let arm: (start: CGPoint, end: CGPoint)?
        let armRadius: CGFloat

        /// 걸음 수. 0번째 표본이 C다.
        private static let steps = Int(
            (BodyOutlineProbe.outlineProbeReach / BodyOutlineProbe.outlineProbeStep).rounded())

        func edge(mask: MaskSampler, extent: CGRect) -> CGPoint? {
            var previous: CGPoint?
            for index in 0...Self.steps {
                let distance = step * CGFloat(index)
                let point = CGPoint(x: center.x + direction.dx * distance, y: center.y + direction.dy * distance)
                if mask.value(at: BodyOutlineProbe.normalized(point, in: extent)) < BodyOutlineProbe.personMinimum {
                    return previous
                }
                if let arm, BodyOutlineProbe.segmentDistance(point, arm.start, arm.end) <= armRadius {
                    return nil
                }
                previous = point
            }
            return nil
        }
    }

    /// 몸통 가로축에서 side 쪽에 있는 어깨와 그 팔꿈치.
    private static func upperArm(_ skeleton: BodySkeleton, side: CGFloat) -> (start: CGPoint, end: CGPoint)? {
        let arms = [(BodyJoint.leftShoulder, BodyJoint.leftElbow), (.rightShoulder, .rightElbow)]
        for (shoulderJoint, elbowJoint) in arms {
            guard let shoulder = skeleton.point(shoulderJoint),
                skeleton.side(of: shoulder, from: skeleton.shoulderCenter) == side
            else { continue }
            return (shoulder, skeleton.point(elbowJoint) ?? shoulder)
        }
        return nil
    }

    /// 점에서 선분 start–end까지 거리. 두 끝이 같으면 점까지 거리다.
    private static func segmentDistance(_ point: CGPoint, _ start: CGPoint, _ end: CGPoint) -> CGFloat {
        let dx = end.x - start.x
        let dy = end.y - start.y
        let squared = dx * dx + dy * dy
        guard squared > 0 else { return hypot(point.x - start.x, point.y - start.y) }
        let along = ((point.x - start.x) * dx + (point.y - start.y) * dy) / squared
        let t = min(max(along, 0), 1)
        return hypot(point.x - (start.x + dx * t), point.y - (start.y + dy * t))
    }

    private static func normalized(_ point: CGPoint, in extent: CGRect) -> NormalizedPoint {
        NormalizedPoint(
            x: Double((point.x - extent.minX) / extent.width), y: Double((point.y - extent.minY) / extent.height))
    }
}
