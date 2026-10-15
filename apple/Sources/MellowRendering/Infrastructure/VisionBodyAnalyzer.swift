import CoreImage
import MellowShared
import Vision

/// VNDetectHumanBodyPoseRequest로 사람마다 관절 14개를 찾는다. 좌표는 Vision 정규화(원점 왼쪽 아래) 그대로다.
public struct VisionBodyAnalyzer: BodyAnalyzer {
    /// Vision이 찾은 관절 하나의 위치(정규화)와 신뢰도.
    struct LocatedJoint {
        let location: CGPoint
        let confidence: Double
    }

    /// BodyJoint와 Vision 관절 이름의 대응. 눈·귀·코는 쓰지 않는다.
    private static let jointNames: [(BodyJoint, VNHumanBodyPoseObservation.JointName)] = [
        (.neck, .neck), (.leftShoulder, .leftShoulder), (.rightShoulder, .rightShoulder),
        (.leftElbow, .leftElbow), (.rightElbow, .rightElbow), (.leftWrist, .leftWrist), (.rightWrist, .rightWrist),
        (.leftHip, .leftHip), (.rightHip, .rightHip), (.leftKnee, .leftKnee), (.rightKnee, .rightKnee),
        (.leftAnkle, .leftAnkle), (.rightAnkle, .rightAnkle), (.root, .root),
    ]

    public init() {}

    public func analyze(_ image: CIImage) throws -> [BodyGeometry] {
        let request = VNDetectHumanBodyPoseRequest()
        do {
            try VNImageRequestHandler(ciImage: image, options: [:]).perform([request])
        } catch {
            throw MellowError.bodyAnalysisUnavailable(reason: error.localizedDescription)
        }
        let bodies = (request.results ?? []).compactMap { observation -> BodyGeometry? in
            guard let points = try? observation.recognizedPoints(.all) else { return nil }
            var located: [BodyJoint: LocatedJoint] = [:]
            for (joint, name) in Self.jointNames {
                guard let point = points[name] else { continue }
                located[joint] = LocatedJoint(location: point.location, confidence: Double(point.confidence))
            }
            return Self.geometry(from: located)
        }
        return Self.orderedLargestFirst(bodies)
    }

    /// 신뢰도 0 이하인 점(Vision이 찾지 못한 관절)은 버린다. 남은 점이 없으면 nil. 상자는 남은 점을 감싼다.
    static func geometry(from located: [BodyJoint: LocatedJoint]) -> BodyGeometry? {
        var joints: [BodyJoint: MellowShared.NormalizedPoint] = [:]
        var confidence: [BodyJoint: Double] = [:]
        for (joint, point) in located where point.confidence > 0 {
            joints[joint] = MellowShared.NormalizedPoint(x: Double(point.location.x), y: Double(point.location.y))
            confidence[joint] = point.confidence
        }
        guard !joints.isEmpty else { return nil }
        return BodyGeometry(joints: joints, confidence: confidence)
    }

    /// 관절 상자 넓이가 큰 사람부터. 체형은 첫 사람만 바꾼다(스펙 5).
    public static func orderedLargestFirst(_ bodies: [BodyGeometry]) -> [BodyGeometry] {
        bodies.sorted { $0.area > $1.area }
    }
}
