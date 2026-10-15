import XCTest

@testable import MellowShared

final class GeometryTransformTests: XCTestCase {
    private let tolerance = 1e-9

    private func assertEqual(_ a: NormalizedPoint, _ b: NormalizedPoint, _ message: String = "") {
        XCTAssertEqual(a.x, b.x, accuracy: tolerance, message)
        XCTAssertEqual(a.y, b.y, accuracy: tolerance, message)
    }

    func testIdentityMapsPointsToThemselves() throws {
        let transform = GeometryTransform(geometry: GeometryAdjustments(), sourceAspect: 1.5)
        let point = NormalizedPoint(x: 0.3, y: 0.8)
        assertEqual(transform.toOriginal(point), point)
        assertEqual(try XCTUnwrap(transform.toOutput(point)), point)
        XCTAssertEqual(transform.outputAspect, 1.5, accuracy: tolerance)
    }

    func testFlipMirrorsX() {
        let transform = GeometryTransform(geometry: GeometryAdjustments(flipHorizontal: true), sourceAspect: 1)
        assertEqual(transform.toOriginal(NormalizedPoint(x: 0.2, y: 0.7)), NormalizedPoint(x: 0.8, y: 0.7))
    }

    func testOneClockwiseTurnMapsTopLeftToTopRight() throws {
        let transform = GeometryTransform(geometry: GeometryAdjustments(quarterTurns: 1), sourceAspect: 2)
        // 원본의 왼쪽 위 (0,1)은 시계 방향으로 돌리면 오른쪽 위 (1,1).
        assertEqual(try XCTUnwrap(transform.toOutput(NormalizedPoint(x: 0, y: 1))), NormalizedPoint(x: 1, y: 1))
        assertEqual(transform.toOriginal(NormalizedPoint(x: 1, y: 1)), NormalizedPoint(x: 0, y: 1))
        XCTAssertEqual(transform.outputAspect, 0.5, accuracy: tolerance)
    }

    func testStraightenKeepsCenterAndAspectAndScalesCorners() throws {
        let geometry = GeometryAdjustments(straightenDegrees: 10)
        let transform = GeometryTransform(geometry: geometry, sourceAspect: 1.5)
        let center = NormalizedPoint(x: 0.5, y: 0.5)
        assertEqual(transform.toOriginal(center), center)
        XCTAssertEqual(transform.outputAspect, 1.5, accuracy: tolerance)
        // 출력 모서리는 원본 안쪽에서 온다 (빈 모서리가 없다는 뜻).
        // 배율이 최소값이라 가로가 긴 이미지의 왼쪽 아래 모서리는 원본 아래 변에 정확히 닿는다.
        let corner = transform.toOriginal(NormalizedPoint(x: 0, y: 0))
        XCTAssertGreaterThan(corner.x, 0)
        XCTAssertEqual(corner.y, 0, accuracy: tolerance)
        let expectedScale = cos(10 * .pi / 180) + sin(10 * .pi / 180) * 1.5
        XCTAssertEqual(GeometryTransform.straightenScale(degrees: 10, aspect: 1.5), expectedScale, accuracy: tolerance)
    }

    func testCropRemapsAndRejectsPointsOutside() throws {
        let crop = NormalizedRect(x: 0.25, y: 0.5, width: 0.5, height: 0.5)
        let transform = GeometryTransform(geometry: GeometryAdjustments(crop: crop), sourceAspect: 1)
        assertEqual(transform.toOriginal(NormalizedPoint(x: 0, y: 0)), NormalizedPoint(x: 0.25, y: 0.5))
        assertEqual(transform.toOriginal(NormalizedPoint(x: 1, y: 1)), NormalizedPoint(x: 0.75, y: 1))
        XCTAssertNil(transform.toOutput(NormalizedPoint(x: 0.1, y: 0.1)))
        assertEqual(
            try XCTUnwrap(transform.toOutput(NormalizedPoint(x: 0.5, y: 0.75))), NormalizedPoint(x: 0.5, y: 0.5))
        XCTAssertEqual(transform.outputAspect, 1, accuracy: tolerance)
    }

    func testRoundTripAcrossCombinations() throws {
        let crops: [NormalizedRect?] = [nil, NormalizedRect(x: 0.1, y: 0.2, width: 0.6, height: 0.5)]
        let samples = [
            NormalizedPoint(x: 0.5, y: 0.5), NormalizedPoint(x: 0.37, y: 0.61), NormalizedPoint(x: 0.5, y: 0.52),
        ]
        for flip in [false, true] {
            for turns in 0...3 {
                for degrees in [0.0, -7.5, 12] {
                    for crop in crops {
                        let geometry = GeometryAdjustments(
                            flipHorizontal: flip, quarterTurns: turns, straightenDegrees: degrees, crop: crop)
                        let transform = GeometryTransform(geometry: geometry, sourceAspect: 4.0 / 3.0)
                        for point in samples {
                            let original = transform.toOriginal(point)
                            let back = try XCTUnwrap(transform.toOutput(original), "\(geometry) \(point)")
                            assertEqual(back, point, "\(geometry)")
                        }
                    }
                }
            }
        }
    }
}
