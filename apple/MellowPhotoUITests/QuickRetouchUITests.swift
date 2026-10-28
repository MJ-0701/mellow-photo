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
        let panel = app.scrollViews["quick.controlsScroll"]
        var up = upward
        var previous = CGRect.zero
        var stationary = 0
        capture(app, "quick-reveal-start-" + element.identifier)
        for step in 0..<24 {
            if element.isHittable { return }
            let viewport = panel.frame
            let target = element.exists ? element.frame : .zero
            let oldDirection = up
            if target.height > 0 { up = target.midY > viewport.midY }
            if step > 0, abs(target.minY - previous.minY) < 1 { stationary += 1 } else { stationary = 0 }
            if stationary >= 2 {
                up.toggle()
                stationary = 0
            }
            if up != oldDirection { capture(app, "quick-reveal-reverse-" + element.identifier) }
            print(
                "quick-reveal step=\(step) target=\(target) viewport=\(viewport) exists=\(element.exists) enabled=\(element.isEnabled) hittable=\(element.isHittable) up=\(up)"
            )
            previous = target
            let remaining = target.height > 0 ? abs(target.midY - viewport.midY) : viewport.height
            let distance = min(viewport.height * 0.3, max(12, remaining))
            // 슬라이더를 잡지 않는 왼쪽 여백. 끝에서 잠깐 멈춰 관성으로 목표를 지나치지 않는다.
            let x = viewport.minX + 2
            let startY = viewport.midY
            let endY = startY + (up ? -distance : distance)
            let origin = app.coordinate(withNormalizedOffset: .zero)
            origin.withOffset(CGVector(dx: x, dy: startY)).press(
                forDuration: 0.05, thenDragTo: origin.withOffset(CGVector(dx: x, dy: endY)),
                withVelocity: .slow, thenHoldForDuration: 0.3)
        }
        capture(app, "quick-reveal-failure-" + element.identifier)
        print("quick-reveal-failure AX=" + app.debugDescription)
        XCTAssertTrue(element.exists)
        XCTAssertTrue(element.isEnabled)
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
