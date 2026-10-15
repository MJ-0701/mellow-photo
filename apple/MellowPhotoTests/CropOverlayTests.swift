import MellowShared
import XCTest

@testable import Mellow_Photo

/// 손잡이 드래그 계산만 확인한다. 화면 표시는 사람이 본다.
@MainActor
final class CropOverlayTests: XCTestCase {
    private let full = NormalizedRect(x: 0, y: 0, width: 1, height: 1)

    private func assertRect(
        _ rect: NormalizedRect, _ expected: NormalizedRect, file: StaticString = #filePath, line: UInt = #line
    ) {
        XCTAssertEqual(rect.x, expected.x, accuracy: 1e-9, file: file, line: line)
        XCTAssertEqual(rect.y, expected.y, accuracy: 1e-9, file: file, line: line)
        XCTAssertEqual(rect.width, expected.width, accuracy: 1e-9, file: file, line: line)
        XCTAssertEqual(rect.height, expected.height, accuracy: 1e-9, file: file, line: line)
    }

    func testFreeCornerDragMovesOnlyThatCorner() {
        let rect = CropOverlay.resized(full, handle: .topLeft, dx: 0.2, dy: -0.3, lockedRatio: nil)
        assertRect(rect, NormalizedRect(x: 0.2, y: 0, width: 0.8, height: 0.7))
    }

    func testDragStopsAtMinimumSideAndImageBounds() {
        let shrunk = CropOverlay.resized(full, handle: .right, dx: -5, dy: 0, lockedRatio: nil)
        XCTAssertEqual(shrunk.width, Theme.cropMinimumSide, accuracy: 1e-9)
        XCTAssertEqual(shrunk.x, 0, accuracy: 1e-9)
        let start = NormalizedRect(x: 0.2, y: 0.2, width: 0.5, height: 0.5)
        let grown = CropOverlay.resized(start, handle: .bottomRight, dx: 5, dy: -5, lockedRatio: nil)
        assertRect(grown, NormalizedRect(x: 0.2, y: 0, width: 0.8, height: 0.7))
    }

    func testLockedRatioKeepsRatioWhenCornerHitsEdge() {
        let start = NormalizedRect(x: 0.25, y: 0.25, width: 0.5, height: 0.5)
        let rect = CropOverlay.resized(start, handle: .topRight, dx: 0.5, dy: 0, lockedRatio: 1)
        XCTAssertEqual(rect.width / rect.height, 1, accuracy: 1e-9)
        XCTAssertEqual(rect.minY, 0.25, accuracy: 1e-9, "아래 변은 고정")
        XCTAssertEqual(rect.maxY, 1, accuracy: 1e-9)
        XCTAssertEqual(rect.width, 0.75, accuracy: 1e-9)
    }

    func testLockedRatioTopEdgeDragResizesByHeight() {
        let start = NormalizedRect(x: 0.1, y: 0.1, width: 0.4, height: 0.4)
        let rect = CropOverlay.resized(start, handle: .top, dx: 0, dy: 0.2, lockedRatio: 0.5)
        XCTAssertEqual(rect.height, 0.6, accuracy: 1e-9)
        XCTAssertEqual(rect.width, 0.3, accuracy: 1e-9)
        XCTAssertEqual(rect.minY, 0.1, accuracy: 1e-9)
    }

    func testLockedRatioRespectsMinimumSideForWideRatio() {
        let rect = CropOverlay.resized(full, handle: .bottomLeft, dx: 5, dy: 5, lockedRatio: 2)
        XCTAssertEqual(rect.width / rect.height, 2, accuracy: 1e-9)
        XCTAssertGreaterThanOrEqual(rect.height, Theme.cropMinimumSide - 1e-9)
    }

    func testLockedRatioNearTopStaysInsideUnitSquare() {
        let start = NormalizedRect(x: 0.4, y: 0.95, width: 0.2, height: 0.05)
        let rect = CropOverlay.resized(start, handle: .top, dx: 0, dy: 0, lockedRatio: 0.5)
        XCTAssertEqual(rect.width / rect.height, 0.5, accuracy: 1e-9)
        XCTAssertGreaterThanOrEqual(rect.width, Theme.cropMinimumSide - 1e-9)
        XCTAssertGreaterThanOrEqual(rect.minX, 0)
        XCTAssertGreaterThanOrEqual(rect.minY, 0)
        XCTAssertLessThanOrEqual(rect.maxX, 1 + 1e-9)
        XCTAssertLessThanOrEqual(rect.maxY, 1 + 1e-9)
    }
}
