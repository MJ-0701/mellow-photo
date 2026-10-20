import XCTest

@testable import Mellow_Photo

/// 분할선 드래그 계산만 확인한다. 화면 표시는 사람이 본다.
@MainActor
final class CompareDividerTests: XCTestCase {
    func testFractionClampsToCanvasAndDefaultsWhenWidthIsZero() {
        XCTAssertEqual(CompareDivider.fraction(forX: 150, width: 300), 0.5, accuracy: 1e-9)
        XCTAssertEqual(CompareDivider.fraction(forX: -20, width: 300), 0)
        XCTAssertEqual(CompareDivider.fraction(forX: 400, width: 300), 1)
        XCTAssertEqual(CompareDivider.fraction(forX: 10, width: 0), AppModel.Policy.compareSplitDefault)
        XCTAssertGreaterThan(Theme.compareHandleHitWidth, Theme.compareHandleSize, "잡는 띠가 그린 손잡이보다 넓다")
    }
}
