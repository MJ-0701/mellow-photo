import Foundation

/// Vision VNHumanBodyPoseObservation.JointName 중 체형 보정이 쓰는 14개(스펙 5). left·right는 찍힌 사람 기준이다.
public enum BodyJoint: String, CaseIterable, Codable, Sendable {
    case neck
    case leftShoulder
    case rightShoulder
    case leftElbow
    case rightElbow
    case leftWrist
    case rightWrist
    case leftHip
    case rightHip
    case leftKnee
    case rightKnee
    case leftAnkle
    case rightAnkle
    case root
}

/// 사람 한 명의 관절점. 영속화하지 않는다. 사진을 준비할 때마다 다시 계산한다.
/// 좌표는 이미지 기준 정규화(원점 왼쪽 아래). 정면 사진에서 leftShoulder는 화면 오른쪽에 있다.
/// 렌더는 좌우를 이름이 아니라 위치로 정한다.
public struct BodyGeometry: Equatable, Sendable {
    public var joints: [BodyJoint: NormalizedPoint]
    /// 관절별 신뢰도 0…1. 값이 없는 관절은 신뢰도가 없는 것으로 본다.
    public var confidence: [BodyJoint: Double]
    /// 관절을 감싸는 상자. 여러 사람 중 가장 큰 사람을 고르는 데 쓴다.
    public var boundingBox: NormalizedRect

    /// boundingBox가 nil이면 joints를 감싸는 상자로 정한다. 관절이 없으면 크기 0인 상자다.
    public init(
        joints: [BodyJoint: NormalizedPoint], confidence: [BodyJoint: Double], boundingBox: NormalizedRect? = nil
    ) {
        self.joints = joints
        self.confidence = confidence
        self.boundingBox = boundingBox ?? Self.enclosing(Array(joints.values))
    }

    /// 신뢰도가 minimumConfidence 이상인 관절. 신뢰도가 낮거나 없으면 nil(스펙 5: 없는 것으로 본다).
    public func point(_ joint: BodyJoint, minimumConfidence: Double) -> NormalizedPoint? {
        guard let point = joints[joint], let value = confidence[joint], value >= minimumConfidence else { return nil }
        return point
    }

    /// 상자 넓이. 여러 사람 중 가장 큰 사람을 앞에 둘 때 쓴다.
    public var area: Double { boundingBox.width * boundingBox.height }

    private static func enclosing(_ points: [NormalizedPoint]) -> NormalizedRect {
        guard let first = points.first else { return NormalizedRect(x: 0, y: 0, width: 0, height: 0) }
        var minX = first.x
        var maxX = first.x
        var minY = first.y
        var maxY = first.y
        for point in points.dropFirst() {
            minX = min(minX, point.x)
            maxX = max(maxX, point.x)
            minY = min(minY, point.y)
            maxY = max(maxY, point.y)
        }
        return NormalizedRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }
}
