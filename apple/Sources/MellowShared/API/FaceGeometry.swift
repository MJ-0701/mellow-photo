import Foundation

/// Vision VNFaceLandmarks2D의 영역 이름과 1:1.
public enum FaceLandmark: String, CaseIterable, Codable, Sendable {
    case faceContour
    case leftEye
    case rightEye
    case leftEyebrow
    case rightEyebrow
    case nose
    case noseCrest
    case medianLine
    case outerLips
    case innerLips
    case leftPupil
    case rightPupil
}

/// 영속화하지 않는다. 사진을 준비할 때마다 다시 계산한다.
public struct FaceGeometry: Equatable, Sendable {
    public var boundingBox: NormalizedRect
    /// 이미지 좌표계의 점. 얼굴 상대 좌표가 아니다.
    public var landmarks: [FaceLandmark: [NormalizedPoint]]
    public var roll: Double?
    public var yaw: Double?

    public init(
        boundingBox: NormalizedRect, landmarks: [FaceLandmark: [NormalizedPoint]] = [:], roll: Double? = nil,
        yaw: Double? = nil
    ) {
        self.boundingBox = boundingBox
        self.landmarks = landmarks
        self.roll = roll
        self.yaw = yaw
    }

    public func bounds(of landmark: FaceLandmark) -> NormalizedRect? {
        guard let points = landmarks[landmark], let first = points.first else { return nil }
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
