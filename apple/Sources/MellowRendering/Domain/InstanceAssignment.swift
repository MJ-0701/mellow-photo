import CoreImage
import MellowShared

/// 몸·얼굴의 표본점이 어느 사람 인스턴스에 드는지 정한다(스펙 5.3).
/// 마스크는 BackgroundStage.personMask와 같은 배치(흐림 없음)로 extent에 늘려 표본한다.
enum InstanceAssignment {
    /// 몸의 표본점이 되는 관절.
    /// 몸통 가운데를 고르게 덮어 팔이 다른 사람에게 걸쳐도 몸통이 이긴다.
    static let bodySampleJoints: [BodyJoint] = [.neck, .leftShoulder, .rightShoulder, .leftHip, .rightHip]

    /// 점은 extent 픽셀이다.
    /// 점마다 그 픽셀 하나를 읽어 평균을 낸다.
    /// 평균이 instanceMatchMinimum 이상인 마스크 중 평균이 가장 큰 것의 인덱스다(같으면 앞 인덱스).
    /// 점이나 마스크가 없거나 표본을 읽지 못하면 nil이다.
    static func owner(
        of points: [CGPoint], in masks: [CIImage], extent: CGRect, renderer: Renderer, tuning: RenderTuning
    ) -> Int? {
        let pixels = points.compactMap { pixelRect(containing: $0, in: extent) }
        guard !pixels.isEmpty, !masks.isEmpty else { return nil }
        var best: (index: Int, mean: Double)?
        for (index, mask) in masks.enumerated() {
            guard !mask.extent.isEmpty, !mask.extent.isInfinite else { continue }
            let placed = BackgroundStage.personMask(mask, extent: extent, feather: 0)
            guard let mean = mean(of: placed, at: pixels, renderer: renderer) else { continue }
            guard mean >= tuning.instanceMatchMinimum else { continue }
            if let current = best, current.mean >= mean {
                continue
            }
            best = (index, mean)
        }
        return best?.index
    }

    /// 몸의 표본점(extent 픽셀).
    /// bodySampleJoints 중 신뢰도가 bodyJointMinConfidence 이상인 것이다.
    static func samplePoints(of body: BodyGeometry, extent: CGRect, tuning: RenderTuning) -> [CGPoint] {
        bodySampleJoints.compactMap { joint in
            guard let point = body.point(joint, minimumConfidence: tuning.bodyJointMinConfidence),
                point.x.isFinite, point.y.isFinite
            else { return nil }
            return CGPoint(x: extent.minX + point.x * extent.width, y: extent.minY + point.y * extent.height)
        }
    }

    /// 얼굴의 표본점은 얼굴 상자 중심 하나다.
    static func samplePoints(of face: FaceGeometry, extent: CGRect) -> [CGPoint] {
        let box = face.boundingBox
        guard box.midX.isFinite, box.midY.isFinite else { return [] }
        return [CGPoint(x: extent.minX + box.midX * extent.width, y: extent.minY + box.midY * extent.height)]
    }

    /// 점이 든 1×1 픽셀. extent 밖의 점은 가장 가까운 가장자리 픽셀로 옮긴다.
    private static func pixelRect(containing point: CGPoint, in extent: CGRect) -> CGRect? {
        let bounds = extent.integral
        guard point.x.isFinite, point.y.isFinite, bounds.width >= 1, bounds.height >= 1 else { return nil }
        let x = min(max(point.x.rounded(.down), bounds.minX), bounds.maxX - 1)
        let y = min(max(point.y.rounded(.down), bounds.minY), bounds.maxY - 1)
        return CGRect(x: x, y: y, width: 1, height: 1)
    }

    /// 픽셀 몇 개의 마스크 평균(빨강 채널).
    /// 픽셀마다 1×1 영역만 렌더해 CPU 비용이 작다.
    private static func mean(of mask: CIImage, at pixels: [CGRect], renderer: Renderer) -> Double? {
        var total: Double = 0
        for pixel in pixels {
            guard let value = try? renderer.readPixels(mask.cropped(to: pixel)).first else { return nil }
            total += Double(value)
        }
        return total / Double(pixels.count)
    }
}
