import XCTest

@testable import MellowShared

/// 회전·반전이 자르기 영역을 이미지와 함께 옮기는지 확인한다.
final class GeometryAdjustmentsTests: XCTestCase {
    private let tolerance = 1e-9
    private let sample = NormalizedRect(x: 0.1, y: 0.2, width: 0.5, height: 0.3)

    private func assertEqual(
        _ a: NormalizedRect?, _ b: NormalizedRect, file: StaticString = #filePath, line: UInt = #line
    ) {
        guard let a else {
            XCTFail("crop이 nil", file: file, line: line)
            return
        }
        XCTAssertEqual(a.x, b.x, accuracy: tolerance, file: file, line: line)
        XCTAssertEqual(a.y, b.y, accuracy: tolerance, file: file, line: line)
        XCTAssertEqual(a.width, b.width, accuracy: tolerance, file: file, line: line)
        XCTAssertEqual(a.height, b.height, accuracy: tolerance, file: file, line: line)
    }

    private func assertEqual(
        _ a: NormalizedPoint, _ b: NormalizedPoint, file: StaticString = #filePath, line: UInt = #line
    ) {
        XCTAssertEqual(a.x, b.x, accuracy: 1e-6, file: file, line: line)
        XCTAssertEqual(a.y, b.y, accuracy: 1e-6, file: file, line: line)
    }

    func testTurnedClockwiseRotatesCropRect() {
        let turned = GeometryAdjustments(crop: sample).turnedClockwise()
        XCTAssertEqual(turned.quarterTurns, 1)
        assertEqual(turned.crop, NormalizedRect(x: 0.2, y: 0.4, width: 0.3, height: 0.5))
    }

    func testFourTurnsRestoreCropAndWrapCount() {
        var geometry = GeometryAdjustments(quarterTurns: 3, crop: sample)
        geometry = geometry.turnedClockwise()
        XCTAssertEqual(geometry.quarterTurns, 0, "3에서 한 번 더 돌면 0")
        for _ in 0..<2 {
            geometry = geometry.turnedClockwise()
        }
        assertEqual(geometry.crop, NormalizedRect(x: 0.5, y: 0.1, width: 0.3, height: 0.5))
        geometry = geometry.turnedClockwise()
        XCTAssertEqual(geometry.quarterTurns, 3)
        assertEqual(geometry.crop, sample)
    }

    func testTurnWithoutCropKeepsCropNil() {
        XCTAssertNil(GeometryAdjustments().turnedClockwise().crop)
    }

    func testFlipWithEvenTurnsMirrorsCropXAndNegatesStraighten() {
        let flipped = GeometryAdjustments(quarterTurns: 2, straightenDegrees: 5, crop: sample).flippedHorizontally()
        XCTAssertTrue(flipped.flipHorizontal)
        XCTAssertEqual(flipped.straightenDegrees, -5)
        assertEqual(flipped.crop, NormalizedRect(x: 0.4, y: 0.2, width: 0.5, height: 0.3))
    }

    func testFlipWithOddTurnsMirrorsCropY() {
        let flipped = GeometryAdjustments(quarterTurns: 1, crop: sample).flippedHorizontally()
        assertEqual(flipped.crop, NormalizedRect(x: 0.1, y: 0.5, width: 0.5, height: 0.3))
    }

    func testFlipTwiceIsIdentityAndKeepsZeroStraightenPositive() {
        let geometry = GeometryAdjustments(quarterTurns: 1, straightenDegrees: 3, crop: sample)
        XCTAssertEqual(geometry.flippedHorizontally().flippedHorizontally(), geometry)
        let unflipped = GeometryAdjustments(flipHorizontal: true).flippedHorizontally()
        XCTAssertEqual(unflipped.straightenDegrees.sign, .plus, "0을 반전해도 −0이 되지 않는다")
    }

    /// 회전 뒤 출력에서 시계 방향으로 옮겨간 점은 회전 전과 같은 원본 픽셀을 본다.
    func testTurnKeepsSameSourcePixelsUnderTransform() {
        let aspect = 1.5
        let geometry = GeometryAdjustments(straightenDegrees: 7, crop: sample)
        let before = GeometryTransform(geometry: geometry, sourceAspect: aspect)
        let after = GeometryTransform(geometry: geometry.turnedClockwise(), sourceAspect: aspect)
        for point in [NormalizedPoint(x: 0.2, y: 0.7), NormalizedPoint(x: 0.9, y: 0.1)] {
            let turned = NormalizedPoint(x: point.y, y: 1 - point.x)
            assertEqual(after.toOriginal(turned), before.toOriginal(point))
        }
    }

    /// 반전 뒤 출력에서 거울 위치의 점은 반전 전과 같은 원본 픽셀을 본다.
    /// 반전은 회전보다 먼저라 홀수 회전에서는 화면의 위아래 거울이 된다.
    func testFlipKeepsSameSourcePixelsMirroredUnderTransform() {
        let aspect = 1.5
        for turns in [0, 1] {
            let geometry = GeometryAdjustments(quarterTurns: turns, straightenDegrees: 7, crop: sample)
            let before = GeometryTransform(geometry: geometry, sourceAspect: aspect)
            let after = GeometryTransform(geometry: geometry.flippedHorizontally(), sourceAspect: aspect)
            for point in [NormalizedPoint(x: 0.2, y: 0.7), NormalizedPoint(x: 0.9, y: 0.1)] {
                let mirrored: NormalizedPoint
                if turns % 2 == 0 {
                    mirrored = NormalizedPoint(x: 1 - point.x, y: point.y)
                } else {
                    mirrored = NormalizedPoint(x: point.x, y: 1 - point.y)
                }
                assertEqual(after.toOriginal(mirrored), before.toOriginal(point))
            }
        }
    }
}
