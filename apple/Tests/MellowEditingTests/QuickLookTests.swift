import MellowEditing
import MellowShared
import XCTest

final class QuickLookTests: XCTestCase {
    func testLookReplacesOnlyLookAndIsOneUndoStep() {
        var document = EditDocument()
        document.set(.exposure(0.4))
        document.set(.crop(NormalizedRect(x: 0.1, y: 0.2, width: 0.7, height: 0.6)))
        document.set(.faceShape(.width, -0.2))
        document.appendLocalEdit(.warp(WarpStroke(x: 0.5, y: 0.5, dx: 0.01, dy: 0, radius: 0.1)))
        let before = document.recipe
        let steps = document.undoStack.count
        XCTAssertTrue(document.applyLook(LookSelection(id: "night", intensity: 0.6)))
        var expected = before
        expected.look = LookSelection(id: "night", intensity: 0.6)
        XCTAssertEqual(document.recipe, expected)
        XCTAssertEqual(document.undoStack.count, steps + 1)
        XCTAssertFalse(document.applyLook(LookSelection(id: "night", intensity: 0.6)))
        XCTAssertEqual(document.undoStack.count, steps + 1)
        document.undo()
        XCTAssertEqual(document.recipe, before)
        document.redo()
        XCTAssertEqual(document.recipe, expected)
    }
}
