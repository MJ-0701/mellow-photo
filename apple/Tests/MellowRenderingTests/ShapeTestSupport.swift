import CoreImage
import MellowShared
import XCTest

@testable import MellowRendering

/// 모양 워프·보호 테스트 도우미. RenderingTestSupport는 다른 세션이 고칠 수 있어 여기에 둔다.
enum ShapeTestSupport {
    /// 이동량 지도를 색 관리 없이 float로 읽는 문맥. 작업 색공간은 Renderer와 같다.
    /// Renderer.readPixels는 선형 sRGB로 바꿔 읽어 음수 이동이 잘릴 수 있다.
    private static let fieldContext = CIContext(options: [
        .workingColorSpace: CGColorSpace(name: CGColorSpace.extendedLinearSRGB)!
    ])
    /// 픽셀 하나의 RGBAf 바이트 수.
    private static let pixelBytes = 4 * MemoryLayout<Float>.size

    /// float 지도에서 점마다 (dx, dy)를 읽는다. 점이 든 픽셀(중심 = 내림 + 0.5)의 값이다.
    static func fieldVectors(_ field: CIImage, at points: [CGPoint]) throws -> [CGVector] {
        points.map { point in
            var pixel = [Float](repeating: 0, count: 4)
            let bounds = CGRect(x: point.x.rounded(.down), y: point.y.rounded(.down), width: 1, height: 1)
            pixel.withUnsafeMutableBytes { buffer in
                fieldContext.render(
                    field, toBitmap: buffer.baseAddress!, rowBytes: pixelBytes, bounds: bounds, format: .RGBAf,
                    colorSpace: nil)
            }
            return CGVector(dx: CGFloat(pixel[0]), dy: CGFloat(pixel[1]))
        }
    }

    /// 지도의 한 점 이동 크기.
    static func shift(_ field: CIImage, at point: CGPoint) throws -> CGFloat {
        let vector = try XCTUnwrap(fieldVectors(field, at: [point]).first)
        return hypot(vector.dx, vector.dy)
    }

    /// standingBody에서 팔꿈치·손목만 옮긴 몸. 나머지 관절은 standingBody 그대로다.
    /// 점은 extent 픽셀이고 extent로 나눠 정규화한다.
    static func body(
        _ base: BodyGeometry, moving joints: [BodyJoint: CGPoint], extent: CGRect
    ) -> BodyGeometry {
        var moved = base.joints
        var confidence = base.confidence
        for (joint, point) in joints {
            moved[joint] = NormalizedPoint(
                x: Double((point.x - extent.minX) / extent.width), y: Double((point.y - extent.minY) / extent.height))
            confidence[joint] = 1
        }
        return BodyGeometry(joints: moved, confidence: confidence)
    }

    /// a에서 b로 t만큼 간 점.
    static func lerp(_ a: CGPoint, _ b: CGPoint, _ t: CGFloat) -> CGPoint {
        CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t)
    }

    /// point를 direction(단위 벡터) 쪽으로 distance만큼 옮긴다.
    static func offset(_ point: CGPoint, _ direction: CGVector, _ distance: CGFloat) -> CGPoint {
        CGPoint(x: point.x + direction.dx * distance, y: point.y + direction.dy * distance)
    }
}
