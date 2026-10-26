import XCTest

/// 합성 사진만 든 DEBUG 임시 세션에서 실행한다. 사용자 보관함은 열지 않는다.
@MainActor
final class QuickRetouchUITests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    private func launchFixture() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--quick-retouch-ui-fixture"]
        app.launch()
        XCTAssertTrue(app.buttons["quick.automatic"].waitForExistence(timeout: 20))
        let ready = expectation(
            for: NSPredicate(format: "enabled == true"), evaluatedWith: app.buttons["quick.automatic"])
        wait(for: [ready], timeout: 20)
        return app
    }

    private func reveal(_ element: XCUIElement, in app: XCUIApplication, upward: Bool = true) {
        for _ in 0..<12 {
            if element.isHittable { return }
            let panel = app.scrollViews["quick.controlsScroll"]
            if upward { panel.swipeUp() } else { panel.swipeDown() }
        }
        XCTAssertTrue(element.isHittable)
    }

    private func capture(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testCompactPanelScrollAndAtomicNightUndo() {
        let app = launchFixture()
        capture(app, "quick-compact-top")
        XCTAssertFalse(app.buttons["quick.portrait"].isEnabled)
        let night = app.buttons["quick.night"]
        reveal(night, in: app)
        capture(app, "quick-compact-night")
        night.tap()
        let undo = app.buttons["quick.undo"]
        reveal(undo, in: app, upward: false)
        XCTAssertTrue(undo.isEnabled)
        undo.tap()
        XCTAssertFalse(undo.isEnabled)
        XCTAssertTrue(app.buttons["quick.compare"].isEnabled)
    }

    func testBatchCancelRemainsClickableWhileToolsAreDisabled() {
        let app = launchFixture()
        let batch = app.buttons["quick.batch"]
        reveal(batch, in: app)
        batch.tap()
        let cancel = app.buttons["quick.cancel"]
        XCTAssertTrue(cancel.waitForExistence(timeout: 5))
        XCTAssertTrue(cancel.isEnabled)
        capture(app, "quick-compact-cancel")
        cancel.tap()
        let cancelled = expectation(
            for: NSPredicate(format: "exists == false OR enabled == false"), evaluatedWith: cancel)
        wait(for: [cancelled], timeout: 5)
        XCTAssertTrue(app.staticTexts["quick.summary"].waitForExistence(timeout: 15))
        XCTAssertTrue(app.staticTexts["quick.summary"].label.contains("취소됨"))
    }
}
