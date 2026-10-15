import CoreImage
import MellowShared
import XCTest

@testable import MellowRendering

final class BodySkeletonTests: XCTestCase {
    typealias Support = RenderingTestSupport

    private let extent = CGRect(x: 0, y: 0, width: 512, height: 512)

    func testUprightBodyUsesPixelJointsAndTorsoAxes() throws {
        let body = Support.standingBody(in: Support.standingBox)
        let skeleton = try XCTUnwrap(BodySkeleton(body: body, extent: extent, tuning: RenderTuning()))
        XCTAssertEqual(skeleton.torsoWidth, 204.8, accuracy: 1e-6, "두 어깨 사이 거리")
        let hip = try XCTUnwrap(skeleton.point(.leftHip))
        XCTAssertEqual(hip.x, (0.1 + 0.8 * 0.62) * 512, accuracy: 1e-6)
        XCTAssertEqual(hip.y, 0.5 * 512, accuracy: 1e-6)
        XCTAssertEqual(skeleton.up.dx, 0, accuracy: 1e-9)
        XCTAssertEqual(skeleton.up.dy, 1, accuracy: 1e-9)
        XCTAssertEqual(skeleton.across.dx, 1, accuracy: 1e-9)
        XCTAssertEqual(skeleton.across.dy, 0, accuracy: 1e-9)
        XCTAssertEqual(skeleton.side(of: hip, from: skeleton.shoulderCenter), 1, "화면 오른쪽은 +1")
    }

    func testLowConfidenceJointsAreMissingAndShouldersAreRequired() {
        let tuning = RenderTuning()
        let faint = Support.standingBody(in: Support.standingBox, confidence: 0.2)
        XCTAssertNil(BodySkeleton(body: faint, extent: extent, tuning: tuning), "신뢰도 0.3 미만 어깨는 없는 것")
        let oneShoulder = Support.standingBody(in: Support.standingBox, omitting: [.rightShoulder])
        XCTAssertNil(BodySkeleton(body: oneShoulder, extent: extent, tuning: tuning))
        var faintKnee = Support.standingBody(in: Support.standingBox)
        faintKnee.confidence[.leftKnee] = 0.29
        let skeleton = BodySkeleton(body: faintKnee, extent: extent, tuning: tuning)
        XCTAssertNotNil(skeleton)
        XCTAssertNil(skeleton?.point(.leftKnee), "그 관절만 없는 것으로 본다")
        XCTAssertNotNil(skeleton?.point(.rightKnee))
        let sideways = BodyGeometry(
            joints: [
                .leftShoulder: NormalizedPoint(x: 0.5, y: 0.8), .rightShoulder: NormalizedPoint(x: 0.505, y: 0.8),
            ],
            confidence: [.leftShoulder: 1, .rightShoulder: 1])
        XCTAssertNil(BodySkeleton(body: sideways, extent: extent, tuning: tuning), "어깨가 거의 겹치면(옆모습) 축을 정하지 않는다")
    }

    func testTiltedBodyAxesFollowHipsToShoulders() throws {
        let angle = Double.pi / 6
        let pivot = NormalizedPoint(x: 0.5, y: 0.5)
        let body = Support.standingBody(in: Support.standingBox).rotated(by: angle, about: pivot)
        let skeleton = try XCTUnwrap(BodySkeleton(body: body, extent: extent, tuning: RenderTuning()))
        XCTAssertEqual(skeleton.up.dx, -sin(angle), accuracy: 1e-9)
        XCTAssertEqual(skeleton.up.dy, cos(angle), accuracy: 1e-9)
        XCTAssertEqual(skeleton.across.dx, cos(angle), accuracy: 1e-9)
        XCTAssertEqual(skeleton.across.dy, sin(angle), accuracy: 1e-9)
        var noHip = body
        noHip.joints[.leftHip] = nil
        let shouldersOnly = try XCTUnwrap(BodySkeleton(body: noHip, extent: extent, tuning: RenderTuning()))
        XCTAssertNil(shouldersOnly.hipCenter)
        XCTAssertEqual(shouldersOnly.up.dx, -sin(angle), accuracy: 1e-9, "엉덩이가 없으면 어깨선에 수직")
        XCTAssertEqual(shouldersOnly.up.dy, cos(angle), accuracy: 1e-9)
    }
}
