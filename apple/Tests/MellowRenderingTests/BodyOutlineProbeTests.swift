import CoreImage
import MellowShared
import XCTest

@testable import MellowRendering

/// 몸통 옆선 테스트의 합성 마스크. 좌표는 512 정사각형 extent 픽셀이고 마스크는 그 절반 크기라 배치가 2배로 늘린다.
/// 사각형 변은 모두 마스크 정수 픽셀 위에 있다.
enum OutlineTestSupport {
    /// 마스크 원래 크기(픽셀).
    static let maskSize = CGSize(width: 256, height: 256)
    /// extent 픽셀 → 마스크 픽셀 비율.
    static let maskScale: CGFloat = 0.5
    /// 몸통 사각형. standingBody의 27% 높이 관절선 점(x 168)보다 바깥이고 위팔 캡슐에서 충분히 떨어져 있다.
    static let torso = CGRect(x: 184, y: 200, width: 144, height: 240)
    /// 몸통에서 16px 떨어진 두 팔 사각형(화면 왼쪽, 오른쪽). 위팔·아래팔 관절을 모두 덮는다.
    static let detachedArms = [
        CGRect(x: 96, y: 220, width: 72, height: 204), CGRect(x: 344, y: 220, width: 72, height: 204),
    ]
    /// 화면 왼쪽 팔이 몸통 변까지 붙은 사각형.
    static let attachedLeftArm = CGRect(x: 96, y: 220, width: 88, height: 204)
    /// 두 변이 위팔 캡슐의 feather 띠(반지름 24.6px ~ 반지름 + feather 30.7px) 안에 드는 몸통.
    /// 27%·30% 높이에서 변의 위팔 선 거리는 약 26–28px다.
    static let torsoInGuardFeather = CGRect(x: 168, y: 200, width: 176, height: 240)

    /// rects(extent 픽셀)를 사람 1로 칠한 회색 마스크. 원점 0이다.
    /// Vision 마스크처럼 비트맵이라 늘리면 Core Image가 이웃 픽셀을 보간한다(절차 이미지는 늘려도 변이 날카롭다).
    static func mask(people rects: [CGRect]) throws -> CIImage {
        let drawn = try RenderingTestSupport.renderer.makeCGImage(procedural(people: rects))
        return CIImage(cgImage: drawn, options: [.colorSpace: NSNull()])
    }

    private static func procedural(people rects: [CGRect]) -> CIImage {
        let bounds = CGRect(origin: .zero, size: maskSize)
        var image = CIImage(color: .black).cropped(to: bounds)
        for rect in rects {
            let scaled = CGRect(
                x: rect.minX * maskScale, y: rect.minY * maskScale, width: rect.width * maskScale,
                height: rect.height * maskScale)
            image = CIImage(color: .white).cropped(to: scaled).composited(over: image)
        }
        return image.cropped(to: bounds)
    }

    /// 몸통과 떨어진 두 팔.
    static func detachedMask() throws -> CIImage {
        try mask(people: [torso] + detachedArms)
    }

    static func sampler(_ mask: CIImage) throws -> MaskSampler {
        try XCTUnwrap(MaskSampler(mask: mask, renderer: RenderingTestSupport.renderer))
    }
}

final class BodyOutlineProbeTests: XCTestCase {
    typealias Support = RenderingTestSupport

    private let extent = CGRect(x: 0, y: 0, width: 512, height: 512)
    private let tuning = RenderTuning()
    private let levels = [0.27, 0.3]

    private func probe(_ mask: CIImage, body: BodyGeometry? = nil) throws -> BodyOutline {
        let geometry = body ?? Support.standingBody(in: Support.standingBox)
        let skeleton = try XCTUnwrap(BodySkeleton(body: geometry, extent: extent, tuning: tuning))
        return BodyOutlineProbe.probe(
            skeleton: skeleton, mask: try OutlineTestSupport.sampler(mask), extent: extent, levels: levels,
            tuning: tuning)
    }

    private func pixel(_ point: NormalizedPoint) -> CGPoint {
        CGPoint(x: extent.minX + point.x * extent.width, y: extent.minY + point.y * extent.height)
    }

    // MARK: MaskSampler

    func testSamplerStretchesTheMaskOverTheImageOnEachAxis() throws {
        // Vision처럼 사진과 비율이 다른 64×48 마스크. 왼쪽 절반과 아래 절반 중 한쪽만 사람이다.
        let size = CGSize(width: 64, height: 48)
        let left = try OutlineTestSupport.sampler(
            Support.personMask(size: size, person: CGRect(x: 0, y: 0, width: 32, height: 48)))
        XCTAssertEqual(left.width, 64)
        XCTAssertEqual(left.height, 48)
        XCTAssertEqual(left.value(at: NormalizedPoint(x: 0.25, y: 0.5)), 1, accuracy: 1e-9)
        XCTAssertEqual(left.value(at: NormalizedPoint(x: 0.75, y: 0.5)), 0, accuracy: 1e-9)
        XCTAssertEqual(left.value(at: NormalizedPoint(x: 0.5, y: 0.5)), 0.5, accuracy: 1e-9, "경계는 쌍선형 보간의 가운데")
        let bottom = try OutlineTestSupport.sampler(
            Support.personMask(size: size, person: CGRect(x: 0, y: 0, width: 64, height: 24)))
        XCTAssertEqual(bottom.value(at: NormalizedPoint(x: 0.5, y: 0.25)), 1, accuracy: 1e-9, "Core Image처럼 y는 아래가 0")
        XCTAssertEqual(bottom.value(at: NormalizedPoint(x: 0.5, y: 0.75)), 0, accuracy: 1e-9)
        XCTAssertEqual(bottom.value(at: NormalizedPoint(x: 0.5, y: -0.5)), 1, accuracy: 1e-9, "밖은 가장자리 값")
        XCTAssertEqual(bottom.value(at: NormalizedPoint(x: 0.5, y: 1.5)), 0, accuracy: 1e-9)
    }

    func testSamplerMatchesTheBackgroundStagePlacement() throws {
        let mask = try OutlineTestSupport.detachedMask()
        let sampler = try OutlineTestSupport.sampler(mask)
        let placed = BackgroundStage.personMask(mask, extent: extent, feather: 0)
        let points = [
            CGPoint(x: 184.5, y: 300.5), CGPoint(x: 183.5, y: 300.5), CGPoint(x: 170.5, y: 421.5),
            CGPoint(x: 250.5, y: 199.5), CGPoint(x: 167.5, y: 230.5),
        ]
        for point in points {
            let pixel = CGRect(x: point.x.rounded(.down), y: point.y.rounded(.down), width: 1, height: 1)
            let expected = Double(try XCTUnwrap(Support.renderer.readPixels(placed.cropped(to: pixel)).first))
            let normalized = NormalizedPoint(x: point.x / extent.width, y: point.y / extent.height)
            XCTAssertEqual(sampler.value(at: normalized), expected, accuracy: 0.01, "\(point)")
        }
    }

    // MARK: BodyOutlineProbe

    func testFindsTorsoEdgesWithinOneStepWhenArmsAreAway() throws {
        let outline = try probe(OutlineTestSupport.detachedMask())
        let step = 0.01 * 204.8
        let torso = OutlineTestSupport.torso
        XCTAssertEqual(outline.points.count, 4, "두 높이 × 두 쪽")
        for level in levels {
            for side in [-1, 1] {
                let point = pixel(
                    try XCTUnwrap(outline.points[OutlineKey(level: level, side: side)], "\(level) \(side)"))
                let edge = side < 0 ? torso.minX : torso.maxX
                let inward = side < 0 ? point.x - edge : edge - point.x
                XCTAssertGreaterThanOrEqual(inward, 0, "옆선 점은 몸통 안 \(level) \(side)")
                XCTAssertLessThan(inward, step, "몸통 변에서 한 걸음 안 \(level) \(side)")
                XCTAssertEqual(point.y, 409.6 + (256 - 409.6) * level, accuracy: 1e-6, "몸 가운데 높이에서 가로로 걷는다")
            }
        }
    }

    func testArmTouchingTheTorsoRemovesThatSide() throws {
        let mask = try OutlineTestSupport.mask(
            people: [OutlineTestSupport.torso, OutlineTestSupport.attachedLeftArm, OutlineTestSupport.detachedArms[1]])
        let outline = try probe(mask)
        for level in levels {
            XCTAssertNil(outline.points[OutlineKey(level: level, side: -1)], "팔이 붙은 쪽은 점이 없다 \(level)")
            XCTAssertNotNil(outline.points[OutlineKey(level: level, side: 1)], "떨어진 쪽은 그대로 \(level)")
        }
    }

    func testTorsoEdgeInsideTheGuardFeatherCountsAsTouching() throws {
        let mask = try OutlineTestSupport.mask(people: [OutlineTestSupport.torsoInGuardFeather])
        XCTAssertTrue(try probe(mask).points.isEmpty, "보호가 이동을 줄이는 feather 띠 안의 옆선은 팔에 붙은 것으로 본다")
        var wide = tuning
        wide.armGuardFeather = 0
        let skeleton = try XCTUnwrap(
            BodySkeleton(body: Support.standingBody(in: Support.standingBox), extent: extent, tuning: wide))
        let withoutFeather = BodyOutlineProbe.probe(
            skeleton: skeleton, mask: try OutlineTestSupport.sampler(mask), extent: extent, levels: levels,
            tuning: wide)
        XCTAssertEqual(withoutFeather.points.count, 4, "feather를 빼면 같은 변을 찾는다(마스크·걷기는 그대로)")
    }

    func testAllPersonMaskHasNoPoints() throws {
        let everywhere = try OutlineTestSupport.mask(people: [CGRect(x: 0, y: 0, width: 512, height: 512)])
        XCTAssertTrue(try probe(everywhere).points.isEmpty)
        // 팔꿈치가 없어도 어깨 관절만으로 팔을 본다. 그래도 끝까지 배경이 없으면 점이 없다.
        let noElbows = Support.standingBody(in: Support.standingBox, omitting: [.leftElbow, .rightElbow])
        XCTAssertTrue(try probe(everywhere, body: noElbows).points.isEmpty)
    }

    func testBodyWithoutHipsHasNoPoints() throws {
        let upperBody = Support.standingBody(in: Support.standingBox, omitting: [.leftHip])
        XCTAssertTrue(try probe(try OutlineTestSupport.detachedMask(), body: upperBody).points.isEmpty)
    }

    func testCenterOutsideTheMaskHasNoPoints() throws {
        let armsOnly = try OutlineTestSupport.mask(people: OutlineTestSupport.detachedArms)
        XCTAssertTrue(try probe(armsOnly).points.isEmpty, "몸 가운데가 배경이면 옆선을 정할 수 없다")
    }
}
