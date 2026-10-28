import XCTest

/// DEBUG 명시 modifier의 합성 임시 세션만 사용한다. 픽셀 변화를 피부 품질 합격으로 쓰지 않는다.
@MainActor
final class OneTouchApplicationUITests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    private func launchFixture() throws -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--quick-retouch-ui-fixture", "--portrait-overrides"]
        app.launch()
        XCTAssertTrue(app.buttons["quick.portrait"].waitForExistence(timeout: 20))
        _ = try waitState(app) { $0["ready"] as? Bool == true }
        return app
    }

    private func state(_ app: XCUIApplication) throws -> [String: Any] {
        let meter = app.staticTexts["oneTouch.fixture"].firstMatch
        XCTAssertTrue(meter.exists)
        let raw = try XCTUnwrap(meter.value as? String)
        let result = try XCTUnwrap(try JSONSerialization.jsonObject(with: Data(raw.utf8)) as? [String: Any])
        XCTAssertEqual(result["fixture"] as? String, "synthetic-one-touch-overrides")
        XCTAssertEqual((result["sourceSHA"] as? String)?.count, 64)
        return result
    }

    @discardableResult
    private func waitState(_ app: XCUIApplication, _ predicate: @escaping ([String: Any]) -> Bool) throws -> [String:
        Any]
    {
        let ready = XCTNSPredicateExpectation(
            predicate: NSPredicate { [self] _, _ in
                guard let value = try? state(app) else { return false }
                return predicate(value)
            }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 20), .completed)
        return try state(app)
    }

    private func capture(_ app: XCUIApplication, name: String) throws {
        let before = try state(app)
        XCTAssertEqual(before["ready"] as? Bool, true)
        let image = XCTAttachment(screenshot: app.screenshot())
        image.name = name
        image.lifetime = .keepAlways
        add(image)
        let after = try state(app)
        XCTAssertEqual(before["recipeSHA"] as? String, after["recipeSHA"] as? String)
        XCTAssertEqual(before["context"] as? String, after["context"] as? String)
        let data = try JSONSerialization.data(withJSONObject: after, options: [.sortedKeys])
        let meter = XCTAttachment(data: data, uniformTypeIdentifier: "public.json")
        meter.name = name + "-state"
        meter.lifetime = .keepAlways
        add(meter)
    }

    private func reveal(_ target: XCUIElement, app: XCUIApplication) throws {
        let panel = app.scrollViews["quick.controlsScroll"]
        var previous = CGRect.zero
        var stationary = 0
        var up = true
        for _ in 0..<30 {
            if target.isHittable { return }
            let before = try state(app)
            let viewport = panel.frame
            let frame = target.exists ? target.frame : .zero
            if frame.height > 0 { up = frame.midY > viewport.midY }
            if abs(frame.minY - previous.minY) < 1 { stationary += 1 } else { stationary = 0 }
            if stationary >= 2 {
                up.toggle()
                stationary = 0
            }
            previous = frame
            let remaining = frame.height > 0 ? abs(frame.midY - viewport.midY) : viewport.height
            let distance = min(viewport.height * 0.3, max(12, remaining))
            let origin = app.coordinate(withNormalizedOffset: .zero)
            let from = origin.withOffset(CGVector(dx: viewport.minX + 2, dy: viewport.midY))
            let to = origin.withOffset(CGVector(dx: viewport.minX + 2, dy: viewport.midY + (up ? -distance : distance)))
            from.press(forDuration: 0.05, thenDragTo: to, withVelocity: .slow, thenHoldForDuration: 0.3)
            let after = try state(app)
            for key in ["recipeSHA", "undo", "saves"] {
                XCTAssertEqual(String(describing: before[key]), String(describing: after[key]), "탐색은 조정을 바꾸지 않는다")
            }
        }
        try capture(app, name: "one-touch-reveal-failed")
        XCTAssertTrue(target.exists)
        XCTAssertTrue(target.isEnabled)
        XCTAssertTrue(target.isHittable)
    }

    func testQuickProtectionExplicitReplacementCompareAndSingleUndo() throws {
        let app = try launchFixture()
        let before = try state(app)
        XCTAssertEqual(try XCTUnwrap(before["resolvedSmoothing"] as? Double), 0.04, accuracy: 1e-12)
        XCTAssertEqual(before["undo"] as? Int, 0)
        app.buttons["quick.portrait"].tap()
        let protected = try waitState(app) { $0["feedbackAll"] as? String == "noChange" }
        XCTAssertEqual(protected["recipeSHA"] as? String, before["recipeSHA"] as? String)
        XCTAssertEqual(protected["saves"] as? Int, before["saves"] as? Int)
        let replace = app.buttons["quick.portrait.replace"]
        try reveal(replace, app: app)
        try capture(app, name: "one-touch-quick-protected")
        replace.tap()
        let after = try waitState(app) { $0["ready"] as? Bool == true && $0["feedbackAll"] as? String == "visible" }
        XCTAssertEqual(after["resolvedSmoothing"] as? Double, 0.2)
        XCTAssertEqual(after["undo"] as? Int, 1)
        XCTAssertEqual(after["saves"] as? Int, (before["saves"] as! Int) + 1)
        try capture(app, name: "one-touch-quick-replaced")
        let compare = app.buttons["quick.compare"]
        try reveal(compare, app: app)
        compare.tap()
        _ = try waitState(app) { $0["compare"] as? String == "split" }
        try capture(app, name: "one-touch-quick-compare")
        compare.tap()
        app.buttons["quick.undo"].tap()
        let undone = try waitState(app) { $0["ready"] as? Bool == true && $0["undo"] as? Int == 0 }
        XCTAssertEqual(undone["recipeSHA"] as? String, before["recipeSHA"] as? String)
        XCTAssertEqual(undone["previewSHA"] as? String, before["previewSHA"] as? String)
        XCTAssertFalse(app.buttons["quick.undo"].isEnabled)
        try capture(app, name: "one-touch-quick-undone")
    }

    func testBeautyUsesSameReportAndEmptyGroupClearKeepsQuickAllSeparate() throws {
        let app = try launchFixture()
        let details = app.buttons["quick.details.portrait"]
        try reveal(details, app: app)
        details.tap()
        let apply = app.buttons["oneTouch.apply"]
        XCTAssertTrue(apply.waitForExistence(timeout: 5))
        try reveal(apply, app: app)
        apply.tap()
        _ = try waitState(app) { $0["feedbackAll"] as? String == "noChange" }
        let replace = app.buttons["oneTouch.apply.replace"]
        try reveal(replace, app: app)
        replace.tap()
        _ = try waitState(app) { $0["ready"] as? Bool == true && $0["feedbackAll"] as? String == "visible" }
        try capture(app, name: "one-touch-beauty-replaced")
        app.buttons["실행 취소"].tap()
        _ = try waitState(app) { $0["ready"] as? Bool == true && $0["undo"] as? Int == 0 }
        let male = app.buttons["남성 그룹 · 0명"]
        try reveal(male, app: app)
        male.tap()
        XCTAssertFalse(app.buttons["oneTouch.apply"].isEnabled)
        let clear = app.buttons["oneTouch.apply.clear"]
        try reveal(clear, app: app)
        clear.tap()
        _ = try waitState(app) { $0["ready"] as? Bool == true && $0["undo"] as? Int == 1 }
        try capture(app, name: "one-touch-empty-group-clear")
        app.buttons["빠른 보정"].tap()
        XCTAssertTrue(app.buttons["quick.portrait"].waitForExistence(timeout: 5))
        try reveal(app.buttons["quick.portrait"], app: app)
        let before = try state(app)
        app.buttons["quick.portrait"].tap()
        let after = try waitState(app) { $0["feedbackAll"] as? String == "noChange" }
        XCTAssertEqual(after["recipeSHA"] as? String, before["recipeSHA"] as? String)
        XCTAssertEqual(after["requestAll"] as? Double, 1)
        XCTAssertEqual(after["requestCurrent"] as? Double, 0)
        try capture(app, name: "one-touch-quick-all-with-empty-beauty-target")
    }

    func testNativeRequestDragToZeroCommitsOnlyAtEndAsOneUndo() throws {
        let app = try launchFixture()
        let slider = app.sliders["quick.portrait.request"]
        try reveal(slider, app: app)
        let before = try state(app)
        let frame = slider.frame
        let origin = app.coordinate(withNormalizedOffset: .zero)
        origin.withOffset(CGVector(dx: frame.maxX - 2, dy: frame.midY)).press(
            forDuration: 0.1,
            thenDragTo: origin.withOffset(CGVector(dx: max(2, frame.minX - 30), dy: frame.midY)),
            withVelocity: .slow, thenHoldForDuration: 0.3)
        let after = try waitState(app) { $0["ready"] as? Bool == true && $0["requestAll"] as? Double == 0 }
        XCTAssertEqual(after["undo"] as? Int, 1)
        XCTAssertEqual(after["saves"] as? Int, (before["saves"] as! Int) + 1)
        XCTAssertEqual(try XCTUnwrap(after["resolvedSmoothing"] as? Double), 0.04, accuracy: 1e-12)
        XCTAssertEqual(after["bodyBrightness"] as? Double, 0)
        try capture(app, name: "one-touch-native-zero-request")
    }
}
