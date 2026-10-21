import CoreImage
import MellowShared

/// 사진 준비 때 몸과 얼굴을 짝짓는다(스펙 5.2).
/// 몸의 기준점은 목 관절이고 없으면 두 어깨 중점이다.
/// 얼굴의 기대점은 얼굴 상자 아래 가운데에서 상자 높이 × bodyFaceNeckDrop만큼 아래다.
/// 거리는 extent 픽셀로 재서 사진 비율이 결과를 바꾸지 않는다.
enum BodyFaceMatcher {
    /// 짝 후보 하나.
    private struct Candidate {
        let body: Int
        let face: Int
        let distance: CGFloat
    }

    /// 중점의 보간 비율.
    private static let halfway: CGFloat = 0.5

    /// 몸 인덱스 → 얼굴 인덱스.
    /// 거리를 얼굴 폭으로 나눈 값이 bodyFaceMatchTolerance 이하인 쌍만 후보다.
    /// 거리 오름차순 탐욕 1:1이고 같은 거리는 (몸 인덱스, 얼굴 인덱스) 순이라 결정적이다.
    static func match(bodies: [BodyGeometry], faces: [FaceGeometry], extent: CGRect, tuning: RenderTuning)
        -> [Int: Int]
    {
        let tolerance = CGFloat(tuning.bodyFaceMatchTolerance)
        var candidates: [Candidate] = []
        for (bodyIndex, body) in bodies.enumerated() {
            guard let anchor = anchor(of: body, extent: extent, tuning: tuning) else { continue }
            for (faceIndex, face) in faces.enumerated() {
                let width = CGFloat(face.boundingBox.width) * extent.width
                guard width > 0 else { continue }
                let expected = expectedNeck(of: face, extent: extent, tuning: tuning)
                let distance = hypot(anchor.x - expected.x, anchor.y - expected.y)
                guard distance.isFinite, distance / width <= tolerance else { continue }
                candidates.append(Candidate(body: bodyIndex, face: faceIndex, distance: distance))
            }
        }
        candidates.sort { first, second in
            if first.distance != second.distance {
                return first.distance < second.distance
            }
            if first.body != second.body {
                return first.body < second.body
            }
            return first.face < second.face
        }
        var matches: [Int: Int] = [:]
        var usedFaces = Set<Int>()
        for candidate in candidates where matches[candidate.body] == nil && !usedFaces.contains(candidate.face) {
            matches[candidate.body] = candidate.face
            usedFaces.insert(candidate.face)
        }
        return matches
    }

    /// 목 관절, 없으면 두 어깨 중점(extent 픽셀).
    /// 신뢰도가 bodyJointMinConfidence보다 낮은 관절은 없는 것으로 본다.
    static func anchor(of body: BodyGeometry, extent: CGRect, tuning: RenderTuning) -> CGPoint? {
        let minimum = tuning.bodyJointMinConfidence
        if let neck = body.point(.neck, minimumConfidence: minimum) {
            return pixel(neck, in: extent)
        }
        guard let left = body.point(.leftShoulder, minimumConfidence: minimum),
            let right = body.point(.rightShoulder, minimumConfidence: minimum)
        else { return nil }
        return BodySkeleton.lerp(pixel(left, in: extent), pixel(right, in: extent), halfway)
    }

    /// 얼굴 상자 아래 가운데에서 상자 높이 × bodyFaceNeckDrop 아래(extent 픽셀).
    static func expectedNeck(of face: FaceGeometry, extent: CGRect, tuning: RenderTuning) -> CGPoint {
        let box = face.boundingBox
        let drop = box.height * tuning.bodyFaceNeckDrop
        return pixel(NormalizedPoint(x: box.midX, y: box.minY - drop), in: extent)
    }

    private static func pixel(_ point: NormalizedPoint, in extent: CGRect) -> CGPoint {
        CGPoint(x: extent.minX + point.x * extent.width, y: extent.minY + point.y * extent.height)
    }
}
