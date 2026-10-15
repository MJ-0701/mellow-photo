import CoreImage
import MellowShared

/// 사람 한 명의 관절을 extent 픽셀 좌표로 옮기고 몸통 좌표축과 어깨 폭을 정한다.
/// 신뢰도가 bodyJointMinConfidence보다 낮은 관절은 없는 것으로 본다.
/// 모든 체형 항목의 이동량이 어깨 폭 기준이라 두 어깨가 없거나 거의 겹치면(옆모습) nil이다.
struct BodySkeleton {
    /// 어깨 폭이 extent 짧은 변의 이 비율보다 작으면 몸통 방향을 정할 수 없다고 본다(옆모습·아주 작은 사람).
    private static let minimumTorsoFraction: CGFloat = 0.02
    /// 엉덩이 중점이 어깨 중점에서 어깨 폭의 이 비율보다 가까우면 세로축을 엉덩이로 정하지 않는다.
    private static let minimumTorsoHeight: CGFloat = 0.25
    /// 중점의 보간 비율.
    private static let halfway: CGFloat = 0.5

    /// 신뢰도를 넘은 관절의 픽셀 위치.
    let joints: [BodyJoint: CGPoint]
    /// 두 어깨 사이 거리(픽셀). 체형 이동량의 기준 길이다.
    let torsoWidth: CGFloat
    /// 두 어깨 중점.
    let shoulderCenter: CGPoint
    /// 두 엉덩이 중점. 엉덩이가 하나라도 없으면 nil.
    let hipCenter: CGPoint?
    /// 몸통 세로축(엉덩이 → 어깨) 단위 벡터. 엉덩이가 없으면 어깨선에 수직인 위쪽이다.
    let up: CGVector
    /// 몸통 가로축 단위 벡터. up을 시계 방향으로 90° 돌린 방향(똑바로 선 사람에서 화면 오른쪽)이다.
    let across: CGVector

    init?(body: BodyGeometry, extent: CGRect, tuning: RenderTuning) {
        var joints: [BodyJoint: CGPoint] = [:]
        for joint in BodyJoint.allCases {
            guard let point = body.point(joint, minimumConfidence: tuning.bodyJointMinConfidence),
                point.x.isFinite, point.y.isFinite
            else { continue }
            joints[joint] = CGPoint(x: extent.minX + point.x * extent.width, y: extent.minY + point.y * extent.height)
        }
        guard let left = joints[.leftShoulder], let right = joints[.rightShoulder] else { return nil }
        let width = hypot(right.x - left.x, right.y - left.y)
        guard width >= Self.minimumTorsoFraction * min(extent.width, extent.height) else { return nil }
        let shoulderCenter = Self.midpoint(left, right)
        var hipCenter: CGPoint?
        if let leftHip = joints[.leftHip], let rightHip = joints[.rightHip] {
            hipCenter = Self.midpoint(leftHip, rightHip)
        }
        let up: CGVector
        if let hip = hipCenter,
            hypot(shoulderCenter.x - hip.x, shoulderCenter.y - hip.y) > Self.minimumTorsoHeight * width
        {
            up = Self.unit(CGVector(dx: shoulderCenter.x - hip.x, dy: shoulderCenter.y - hip.y))
        } else {
            let first = left.x <= right.x ? left : right
            let second = left.x <= right.x ? right : left
            let line = Self.unit(CGVector(dx: second.x - first.x, dy: second.y - first.y))
            up = CGVector(dx: -line.dy, dy: line.dx)
        }
        self.joints = joints
        torsoWidth = width
        self.shoulderCenter = shoulderCenter
        self.hipCenter = hipCenter
        self.up = up
        across = CGVector(dx: up.dy, dy: -up.dx)
    }

    func point(_ joint: BodyJoint) -> CGPoint? {
        joints[joint]
    }

    /// point가 center의 가로축 쪽(오른쪽)이면 +1, 반대쪽이면 −1, 가로축 성분이 0이면 0.
    func side(of point: CGPoint, from center: CGPoint) -> CGFloat {
        let along = (point.x - center.x) * across.dx + (point.y - center.y) * across.dy
        if along > 0 {
            return 1
        }
        if along < 0 {
            return -1
        }
        return 0
    }

    static func midpoint(_ first: CGPoint, _ second: CGPoint) -> CGPoint {
        lerp(first, second, halfway)
    }

    /// first에서 second 쪽으로 t만큼 간 점.
    static func lerp(_ first: CGPoint, _ second: CGPoint, _ t: CGFloat) -> CGPoint {
        CGPoint(x: first.x + (second.x - first.x) * t, y: first.y + (second.y - first.y) * t)
    }

    private static func unit(_ vector: CGVector) -> CGVector {
        let length = hypot(vector.dx, vector.dy)
        guard length > 0 else { return CGVector(dx: 0, dy: 1) }
        return CGVector(dx: vector.dx / length, dy: vector.dy / length)
    }
}
