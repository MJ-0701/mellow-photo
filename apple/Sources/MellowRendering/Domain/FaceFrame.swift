import CoreImage
import MellowShared

/// 얼굴 좌표계. 원점 = 얼굴 상자 중심, x축 = 두 눈을 잇는 방향, y축 = x축을 반시계로 90° 돌린 방향(입 → 눈).
/// 길이는 extent 픽셀이다. x축은 눈동자 → 눈 영역 중심 → roll(반시계 양수) → 가로 순으로 정하고,
/// y축이 입에서 눈 쪽을 향하도록 두 축을 함께 뒤집을 수 있다. 그래서 Vision의 점 순서·좌우 이름이나
/// 사진 기울기와 관계없이 같은 얼굴 좌표를 얻는다.
struct FaceFrame {
    /// 눈 하나의 중심과 폭(얼굴 x축 방향, 픽셀).
    struct Eye: Equatable {
        let center: CGPoint
        let width: CGFloat
    }

    private struct EyePair {
        let first: CGPoint
        let second: CGPoint
    }

    /// 윤곽 다각형이 되려면 필요한 점 수.
    private static let minimumContourPoints = 3
    /// 두 눈 사이가 얼굴 폭의 이 비율보다 짧으면 눈으로 방향을 정하지 않는다.
    private static let minimumEyeSpan: CGFloat = 0.05
    /// 눈 영역 점이 없을 때의 눈 폭. 얼굴 폭 비율.
    private static let fallbackEyeWidth: CGFloat = 0.2
    /// 눈 폭을 재려면 필요한 눈 영역 점 수.
    private static let minimumEyeRegionPoints = 2
    /// 특징점이 없을 때 눈·입 중심 높이. 상자 중심 기준, 상자 높이 비율(FaceRegions 대체 위치 0.63·0.27).
    private static let fallbackEyeLevel: CGFloat = 0.13
    private static let fallbackMouthLevel: CGFloat = -0.23

    let origin: CGPoint
    let xAxis: CGVector
    let yAxis: CGVector
    let faceWidth: CGFloat
    /// 윤곽점(픽셀). Vision 순서 그대로다. 원소는 순서가 아니라 얼굴 좌표로 고른다.
    let contour: [CGPoint]
    /// 두 눈 중심의 얼굴 좌표 v.
    let eyeLevel: CGFloat
    /// 바깥 입술 중심의 얼굴 좌표 v.
    let mouthLevel: CGFloat
    let eyes: [Eye]
    private let landmarks: [FaceLandmark: [CGPoint]]

    /// 윤곽점이 3개보다 적거나 얼굴 폭이 0이면 nil.
    init?(face: FaceGeometry, extent: CGRect) {
        var landmarks: [FaceLandmark: [CGPoint]] = [:]
        for (landmark, points) in face.landmarks {
            landmarks[landmark] = points.map {
                CGPoint(x: extent.minX + $0.x * extent.width, y: extent.minY + $0.y * extent.height)
            }
        }
        let contour = landmarks[.faceContour] ?? []
        let width = CGFloat(face.boundingBox.width) * extent.width
        guard contour.count >= Self.minimumContourPoints, width > 0 else { return nil }
        let box = FaceRegions.pixelRect(face.boundingBox, in: extent)
        let origin = CGPoint(x: box.midX, y: box.midY)
        let pair = Self.eyePair(landmarks)
        var xAxis = CGVector(dx: 1, dy: 0)
        if let pair, Self.length(Self.offset(pair.second, from: pair.first)) > width * Self.minimumEyeSpan {
            xAxis = Self.unit(Self.offset(pair.second, from: pair.first))
        } else if let roll = face.roll {
            xAxis = CGVector(dx: CGFloat(cos(roll)), dy: CGFloat(sin(roll)))
        }
        var yAxis = CGVector(dx: -xAxis.dy, dy: xAxis.dx)
        let eyeCenter = pair.map { Self.midpoint($0.first, $0.second) }
        let lips = landmarks[.outerLips] ?? []
        let mouthCenter = Self.centroid(lips.isEmpty ? contour : lips)
        if Self.dot(yAxis, Self.offset(eyeCenter ?? origin, from: mouthCenter)) < 0 {
            xAxis = CGVector(dx: -xAxis.dx, dy: -xAxis.dy)
            yAxis = CGVector(dx: -yAxis.dx, dy: -yAxis.dy)
        }
        let boxHeight = CGFloat(face.boundingBox.height) * extent.height
        self.origin = origin
        self.xAxis = xAxis
        self.yAxis = yAxis
        self.faceWidth = width
        self.contour = contour
        self.landmarks = landmarks
        if let eyeCenter {
            eyeLevel = Self.dot(Self.offset(eyeCenter, from: origin), yAxis)
        } else {
            eyeLevel = boxHeight * Self.fallbackEyeLevel
        }
        if lips.isEmpty {
            mouthLevel = boxHeight * Self.fallbackMouthLevel
        } else {
            mouthLevel = Self.dot(Self.offset(Self.centroid(lips), from: origin), yAxis)
        }
        let regions = [FaceLandmark.leftEye, .rightEye].compactMap { landmarks[$0] }
            .filter { $0.count >= Self.minimumEyeRegionPoints }
        let centers = pair.map { [$0.first, $0.second] } ?? []
        eyes = centers.map { center in
            let nearest = regions.min {
                Self.length(Self.offset(Self.centroid($0), from: center))
                    < Self.length(Self.offset(Self.centroid($1), from: center))
            }
            let measured = nearest.map { Self.span($0, along: xAxis) } ?? 0
            return Eye(center: center, width: measured > 0 ? measured : width * Self.fallbackEyeWidth)
        }
    }

    /// 이미지 픽셀 점을 얼굴 좌표(u, v)로.
    func local(_ point: CGPoint) -> CGPoint {
        let offset = Self.offset(point, from: origin)
        return CGPoint(x: Self.dot(offset, xAxis), y: Self.dot(offset, yAxis))
    }

    /// 얼굴 좌표 점을 이미지 픽셀로.
    func imagePoint(u: CGFloat, v: CGFloat) -> CGPoint {
        CGPoint(x: origin.x + xAxis.dx * u + yAxis.dx * v, y: origin.y + xAxis.dy * u + yAxis.dy * v)
    }

    /// 얼굴 좌표 벡터를 이미지 벡터로.
    func vector(u: CGFloat, v: CGFloat) -> CGVector {
        CGVector(dx: xAxis.dx * u + yAxis.dx * v, dy: xAxis.dy * u + yAxis.dy * v)
    }

    /// 특징점(픽셀). 없으면 빈 배열.
    func points(_ landmark: FaceLandmark) -> [CGPoint] {
        landmarks[landmark] ?? []
    }

    static func centroid(_ points: [CGPoint]) -> CGPoint {
        let count = CGFloat(max(1, points.count))
        let sum = points.reduce(CGPoint.zero) { CGPoint(x: $0.x + $1.x, y: $0.y + $1.y) }
        return CGPoint(x: sum.x / count, y: sum.y / count)
    }

    /// 눈동자 둘, 없으면 눈 영역 중심 둘.
    private static func eyePair(_ landmarks: [FaceLandmark: [CGPoint]]) -> EyePair? {
        if let left = landmarks[.leftPupil]?.first, let right = landmarks[.rightPupil]?.first {
            return EyePair(first: left, second: right)
        }
        guard let left = landmarks[.leftEye], let right = landmarks[.rightEye], !left.isEmpty, !right.isEmpty
        else { return nil }
        return EyePair(first: centroid(left), second: centroid(right))
    }

    private static func midpoint(_ a: CGPoint, _ b: CGPoint) -> CGPoint {
        CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2)
    }

    private static func offset(_ point: CGPoint, from origin: CGPoint) -> CGVector {
        CGVector(dx: point.x - origin.x, dy: point.y - origin.y)
    }

    private static func dot(_ a: CGVector, _ b: CGVector) -> CGFloat {
        a.dx * b.dx + a.dy * b.dy
    }

    private static func length(_ vector: CGVector) -> CGFloat {
        hypot(vector.dx, vector.dy)
    }

    private static func unit(_ vector: CGVector) -> CGVector {
        let size = length(vector)
        return CGVector(dx: vector.dx / size, dy: vector.dy / size)
    }

    /// 점들을 axis에 투영한 길이(최대 − 최소).
    private static func span(_ points: [CGPoint], along axis: CGVector) -> CGFloat {
        let projections = points.map { $0.x * axis.dx + $0.y * axis.dy }
        return (projections.max() ?? 0) - (projections.min() ?? 0)
    }
}
