import CoreImage
import MellowShared
import Vision

public struct VisionFaceAnalyzer: FaceAnalyzer {
    public init() {}

    public func analyze(_ image: CIImage) throws -> [FaceGeometry] {
        let request = VNDetectFaceLandmarksRequest()
        #if targetEnvironment(simulator)
            // 시뮬레이터는 실기기의 모든 추론 백엔드를 쓰지 못한다.
            request.usesCPUOnly = true
        #endif
        do {
            try VNImageRequestHandler(ciImage: image, options: [:]).perform([request])
        } catch {
            throw MellowError.faceAnalysisUnavailable(reason: error.localizedDescription)
        }
        let faces = (request.results ?? []).map(Self.geometry(from:))
        return Self.orderedLeftToRight(faces)
    }

    public static func orderedLeftToRight(_ faces: [FaceGeometry]) -> [FaceGeometry] {
        faces.sorted { $0.boundingBox.minX < $1.boundingBox.minX }
    }

    private static func geometry(from observation: VNFaceObservation) -> FaceGeometry {
        let box = observation.boundingBox
        var landmarks: [FaceLandmark: [MellowShared.NormalizedPoint]] = [:]
        if let all = observation.landmarks {
            let regions: [(FaceLandmark, VNFaceLandmarkRegion2D?)] = [
                (.faceContour, all.faceContour), (.leftEye, all.leftEye), (.rightEye, all.rightEye),
                (.leftEyebrow, all.leftEyebrow), (.rightEyebrow, all.rightEyebrow), (.nose, all.nose),
                (.noseCrest, all.noseCrest), (.medianLine, all.medianLine), (.outerLips, all.outerLips),
                (.innerLips, all.innerLips), (.leftPupil, all.leftPupil), (.rightPupil, all.rightPupil),
            ]
            for (landmark, region) in regions {
                guard let region, region.pointCount > 0 else { continue }
                // normalizedPoints는 얼굴 상자 기준. 이미지 좌표로 옮긴다.
                landmarks[landmark] = region.normalizedPoints.map { point in
                    MellowShared.NormalizedPoint(
                        x: box.minX + Double(point.x) * box.width,
                        y: box.minY + Double(point.y) * box.height)
                }
            }
        }
        return FaceGeometry(
            boundingBox: MellowShared.NormalizedRect(cgRect: box),
            landmarks: landmarks,
            roll: observation.roll.map(\.doubleValue),
            yaw: observation.yaw.map(\.doubleValue))
    }
}
