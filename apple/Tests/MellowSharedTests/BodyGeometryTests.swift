import MellowShared
import XCTest

final class BodyGeometryTests: XCTestCase {
    func testPointDropsLowConfidenceAndMissingJoints() {
        let body = BodyGeometry(
            joints: [
                .neck: NormalizedPoint(x: 0.5, y: 0.8), .leftHip: NormalizedPoint(x: 0.6, y: 0.5),
                .leftKnee: NormalizedPoint(x: 0.6, y: 0.3),
            ],
            confidence: [.neck: 0.9, .leftHip: 0.29])
        XCTAssertEqual(body.point(.neck, minimumConfidence: 0.3), NormalizedPoint(x: 0.5, y: 0.8))
        XCTAssertNil(body.point(.leftHip, minimumConfidence: 0.3), "신뢰도가 낮으면 없는 것")
        XCTAssertNil(body.point(.leftKnee, minimumConfidence: 0.3), "신뢰도가 없으면 없는 것")
        XCTAssertNil(body.point(.rightAnkle, minimumConfidence: 0), "점이 없으면 nil")
    }

    func testBoundingBoxDefaultsToJointExtentAndGivesArea() {
        let body = BodyGeometry(
            joints: [
                .neck: NormalizedPoint(x: 0.5, y: 0.9), .leftAnkle: NormalizedPoint(x: 0.6, y: 0.1),
                .rightAnkle: NormalizedPoint(x: 0.3, y: 0.15),
            ],
            confidence: [:])
        XCTAssertEqual(body.boundingBox.minX, 0.3, accuracy: 1e-12)
        XCTAssertEqual(body.boundingBox.minY, 0.1, accuracy: 1e-12)
        XCTAssertEqual(body.boundingBox.maxX, 0.6, accuracy: 1e-12)
        XCTAssertEqual(body.boundingBox.maxY, 0.9, accuracy: 1e-12)
        XCTAssertEqual(body.area, 0.3 * 0.8, accuracy: 1e-12)
        XCTAssertEqual(BodyGeometry(joints: [:], confidence: [:]).area, 0, "관절이 없으면 넓이 0")
        let given = NormalizedRect(x: 0, y: 0, width: 0.5, height: 0.5)
        XCTAssertEqual(BodyGeometry(joints: [:], confidence: [:], boundingBox: given).boundingBox, given)
    }

    func testBodyShapeRangeIsUnitOnlyForLegLength() {
        for key in BodyShapeKey.allCases {
            let expected = key == .legLength ? AdjustmentRange.unit : AdjustmentRange.bipolar
            XCTAssertEqual(AdjustmentRange.bodyShape(key), expected, "\(key)")
        }
        XCTAssertEqual(BodyJoint.allCases.count, 14, "스펙 5의 관절 14개")
    }
}
