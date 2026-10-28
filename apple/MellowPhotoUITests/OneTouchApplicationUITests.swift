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
    private func waitState(
        _ app: XCUIApplication, observing target: XCUIElement? = nil,
        _ predicate: @escaping ([String: Any]) -> Bool
    ) throws -> [String:
        Any]
    {
        let ready = XCTNSPredicateExpectation(
            predicate: NSPredicate { [self] _, _ in
                guard let value = try? state(app) else { return false }
                return predicate(value)
            }, object: nil)
        let outcome = XCTWaiter.wait(for: [ready], timeout: 20)
        if outcome != .completed {
            // continueAfterFailure=false 전에 실제 값과 가림/프레임을 먼저 보존한다.
            try observation(app, target: target, name: "one-touch-wait-timeout")
        }
        XCTAssertEqual(outcome, .completed)
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

    /// 계산만 한다. 누락/비정상 좌표는 nil이며 관측/실패 판정은 호출자가 담당한다.
    private func safeViewport(_ app: XCUIApplication) -> CGRect? {
        let controls = app.scrollViews["quick.controlsScroll"]
        let footer = app.buttons["이 설정 복사"]
        guard controls.exists, footer.exists else { return nil }
        let screen = app.frame
        let controlFrame = controls.frame
        let footerFrame = footer.frame
        func valid(_ frame: CGRect) -> Bool {
            [frame.minX, frame.minY, frame.width, frame.height, frame.maxX, frame.maxY].allSatisfy(\.isFinite)
                && frame.width > 0 && frame.height > 0
        }
        guard valid(screen), valid(controlFrame), valid(footerFrame) else { return nil }
        let panel = controlFrame.intersection(screen)
        guard valid(panel), screen.contains(footerFrame), footerFrame.minY >= panel.midY,
            footerFrame.maxX > panel.minX, footerFrame.minX < panel.maxX
        else { return nil }
        let bottom = min(panel.maxY, footerFrame.minY)
        let safe = CGRect(
            x: panel.minX, y: panel.minY, width: panel.width,
            height: bottom - panel.minY
        ).insetBy(dx: 0, dy: 8)
        return valid(safe) ? safe : nil
    }

    private func frameRecord(_ element: XCUIElement?) -> [String: Any] {
        guard let element, element.exists else { return ["exists": false] }
        return [
            "exists": true, "identifier": element.identifier, "frame": NSCoder.string(for: element.frame),
            "hittable": element.isHittable, "enabled": element.isEnabled,
        ]
    }

    private func observation(
        _ app: XCUIApplication, target: XCUIElement? = nil, name: String, extra: [String: Any] = [:]
    ) throws {
        // fixture 출처가 확인되지 않으면 화면을 저장하지 않는다.
        let actual = try state(app)
        let data = try JSONSerialization.data(
            withJSONObject: [
                "state": actual, "target": frameRecord(target),
                "controls": frameRecord(app.scrollViews["quick.controlsScroll"]),
                "footer": frameRecord(app.buttons["이 설정 복사"]),
                "safeViewport": safeViewport(app).map { NSCoder.string(for: $0) } ?? "unavailable", "gesture": extra,
            ], options: [.sortedKeys])
        let metadata = XCTAttachment(data: data, uniformTypeIdentifier: "public.json")
        metadata.name = name + "-geometry-state"
        metadata.lifetime = .keepAlways
        add(metadata)
        let image = XCTAttachment(screenshot: app.screenshot())
        image.name = name + "-panel"
        image.lifetime = .keepAlways
        add(image)
    }

    private func assertUnedited(_ before: [String: Any], _ after: [String: Any]) {
        for key in [
            "recipeSHA", "undo", "saves", "requestAll", "requestCurrent", "target", "photo", "sourceSHA",
            "feedbackAll",
        ] {
            XCTAssertEqual(String(describing: before[key]), String(describing: after[key]), "탐색은 조정을 바꾸지 않는다")
        }
    }

    private func reveal(_ target: XCUIElement, app: XCUIApplication) throws {
        var previous = CGRect.zero
        var stationary = 0
        var up = true
        for step in 0..<30 {
            let before = try state(app)
            guard let viewport = safeViewport(app) else {
                try observation(app, target: target, name: "one-touch-invalid-viewport")
                XCTFail("보정 패널의 실제 표시 영역을 확인할 수 없다")
                return
            }
            let frame = target.exists ? target.frame : .zero
            let confirmation = target.exists ? target.frame : .zero
            // isHittable alone accepts a slider partly covered by the fixed footer.
            if target.isHittable, frame.width > 0, frame.height > 0,
                viewport.contains(frame), viewport.contains(confirmation),
                abs(frame.minY - confirmation.minY) < 0.5
            {
                try observation(app, target: target, name: "one-touch-reveal-visible-\(step)")
                return
            }
            if step == 0 { try observation(app, target: target, name: "one-touch-reveal-before") }
            if frame.height > 0 { up = frame.midY > viewport.midY }
            if abs(frame.minY - previous.minY) < 1 { stationary += 1 } else { stationary = 0 }
            if stationary >= 2 {
                up.toggle()
                stationary = 0
                try observation(app, target: target, name: "one-touch-reveal-reverse-\(step)")
            }
            previous = frame
            let remaining = frame.height > 0 ? abs(frame.midY - viewport.midY) : viewport.height
            let distance = min(60, min(viewport.height * 0.3, max(12, remaining)))
            let start = CGPoint(x: viewport.minX + 2, y: viewport.midY)
            let end = CGPoint(x: start.x, y: start.y + (up ? -distance : distance))
            let origin = app.coordinate(withNormalizedOffset: .zero)
            origin.withOffset(CGVector(dx: start.x, dy: start.y)).press(
                forDuration: 0.1, thenDragTo: origin.withOffset(CGVector(dx: end.x, dy: end.y)),
                withVelocity: .slow, thenHoldForDuration: 0.3)
            let after = try state(app)
            let traceData = try JSONSerialization.data(
                withJSONObject: [
                    "step": step, "before": before, "after": after,
                    "targetBefore": NSCoder.string(for: frame), "targetAfter": frameRecord(target),
                    "safeViewport": NSCoder.string(for: viewport),
                    "from": NSCoder.string(for: start), "to": NSCoder.string(for: end),
                ], options: [.sortedKeys])
            let trace = XCTAttachment(data: traceData, uniformTypeIdentifier: "public.json")
            trace.name = "one-touch-scroll-step-\(step)"
            trace.lifetime = .keepAlways
            add(trace)
            let changed = [
                "recipeSHA", "undo", "saves", "requestAll", "requestCurrent", "target", "photo", "sourceSHA",
                "feedbackAll",
            ]
            .contains { String(describing: before[$0]) != String(describing: after[$0]) }
            if changed {
                try observation(
                    app, target: target, name: "one-touch-scroll-mutated-\(step)",
                    extra: [
                        "from": NSCoder.string(for: start), "to": NSCoder.string(for: end), "before": before,
                    ])
            }
            assertUnedited(before, after)
        }
        try observation(app, target: target, name: "one-touch-reveal-failed")
        XCTAssertTrue(target.exists)
        XCTAssertTrue(target.isEnabled)
        XCTAssertTrue(target.isHittable)
        XCTAssertEqual(safeViewport(app)?.contains(target.frame), true, "조작할 항목 전체가 고정 바 위에 보여야 한다")
    }

    func testQuickProtectionExplicitReplacementCompareAndSingleUndo() throws {
        let app = try launchFixture()
        let before = try state(app)
        XCTAssertEqual(try XCTUnwrap(before["resolvedSmoothing"] as? Double), 0.04, accuracy: 1e-12)
        XCTAssertEqual(before["undo"] as? Int, 0)
        try reveal(app.buttons["quick.portrait"], app: app)
        app.buttons["quick.portrait"].tap()
        let protected = try waitState(app) { $0["feedbackAll"] as? String == "noChange" }
        XCTAssertEqual(protected["recipeSHA"] as? String, before["recipeSHA"] as? String)
        XCTAssertEqual(protected["saves"] as? Int, before["saves"] as? Int)
        let protectedText = app.staticTexts["quick.portrait.result"]
        try reveal(protectedText, app: app)
        XCTAssertEqual(protectedText.label, "개인 조정이 우선해요. 얼굴 보정값은 그대로예요.")
        try capture(app, name: "one-touch-quick-protected-result")
        let replace = app.buttons["quick.portrait.replace"]
        try reveal(replace, app: app)
        XCTAssertEqual(replace.label, "개인 조정도 이 강도로 적용")
        try capture(app, name: "one-touch-quick-protected-cta")
        replace.tap()
        let after = try waitState(app) { $0["ready"] as? Bool == true && $0["feedbackAll"] as? String == "visible" }
        XCTAssertEqual(after["resolvedSmoothing"] as? Double, 0.2)
        XCTAssertEqual(after["undo"] as? Int, 1)
        XCTAssertEqual(after["saves"] as? Int, (before["saves"] as! Int) + 1)
        let completedText = app.staticTexts["quick.portrait.result"]
        try reveal(completedText, app: app)
        XCTAssertTrue(completedText.label.hasPrefix("1명의 보정값 "))
        XCTAssertTrue(completedText.label.contains("개 항목을 적용했어요. 원본과 비교해 확인하세요."))
        try capture(app, name: "one-touch-quick-replaced-result")
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

    func testNativeDraftZeroThenExplicitNeutralUndoAndSeparateDefaultClear() throws {
        let app = try launchFixture()
        let slider = app.sliders["quick.portrait.request"]
        try reveal(slider, app: app)
        let before = try state(app)
        let frame = slider.frame
        guard let viewport = safeViewport(app) else {
            try observation(app, target: slider, name: "one-touch-zero-invalid-viewport")
            XCTFail("조절기와 고정 하단 바의 위치를 확인할 수 없다")
            return
        }
        let start = CGPoint(x: frame.maxX - frame.height / 2, y: frame.midY)
        let end = CGPoint(x: frame.minX + 1, y: frame.midY)
        let gesture: [String: Any] = [
            "from": NSCoder.string(for: start), "to": NSCoder.string(for: end),
            "initialRequest": before["requestAll"]!, "expectedRequest": 0,
        ]
        try observation(app, target: slider, name: "one-touch-zero-drag-before", extra: gesture)
        XCTAssertEqual(before["requestAll"] as? Double, 1)
        XCTAssertTrue(viewport.contains(frame))
        XCTAssertTrue(viewport.contains(start) && viewport.contains(end))
        let origin = app.coordinate(withNormalizedOffset: .zero)
        origin.withOffset(CGVector(dx: start.x, dy: start.y)).press(
            forDuration: 0.1, thenDragTo: origin.withOffset(CGVector(dx: end.x, dy: end.y)),
            withVelocity: .slow, thenHoldForDuration: 0.3)
        try observation(app, target: slider, name: "one-touch-zero-drag-after", extra: gesture)
        let draft = try waitState(app, observing: slider) {
            $0["ready"] as? Bool == true && $0["requestAll"] as? Double == 0
        }
        XCTAssertEqual(draft["recipeSHA"] as? String, before["recipeSHA"] as? String)
        XCTAssertEqual(draft["undo"] as? Int, before["undo"] as? Int)
        XCTAssertEqual(draft["saves"] as? Int, before["saves"] as? Int)
        XCTAssertEqual(draft["bodyBrightness"] as? Double, before["bodyBrightness"] as? Double)
        try capture(app, name: "one-touch-zero-draft-unapplied")
        let replace = app.buttons["quick.portrait.replace"]
        try reveal(replace, app: app)
        replace.tap()
        let neutral = try waitState(app) { $0["ready"] as? Bool == true && $0["feedbackAll"] as? String == "visible" }
        XCTAssertEqual(neutral["resolvedSmoothing"] as? Double, 0)
        XCTAssertEqual(neutral["bodyBrightness"] as? Double, before["bodyBrightness"] as? Double)
        XCTAssertEqual(neutral["undo"] as? Int, 1)
        XCTAssertEqual(neutral["saves"] as? Int, (before["saves"] as! Int) + 1)
        try capture(app, name: "one-touch-explicit-zero-keeps-other-settings")
        let undo = app.buttons["quick.undo"]
        try reveal(undo, app: app)
        undo.tap()
        let undone = try waitState(app) { $0["ready"] as? Bool == true && $0["undo"] as? Int == 0 }
        XCTAssertEqual(undone["recipeSHA"] as? String, before["recipeSHA"] as? String)
        XCTAssertEqual(undone["previewSHA"] as? String, before["previewSHA"] as? String)
        let apply = app.buttons["quick.portrait"]
        try reveal(apply, app: app)
        apply.tap()
        let cleared = try waitState(app) { $0["ready"] as? Bool == true && $0["feedbackAll"] as? String == "visible" }
        XCTAssertEqual(cleared["requestAll"] as? Double, 0)
        XCTAssertEqual(cleared["bodyBrightness"] as? Double, 0)
        XCTAssertEqual(try XCTUnwrap(cleared["resolvedSmoothing"] as? Double), 0.04, accuracy: 1e-12)
        XCTAssertEqual(cleared["undo"] as? Int, 1)
        XCTAssertEqual(cleared["saves"] as? Int, (undone["saves"] as! Int) + 1)
        try capture(app, name: "one-touch-default-zero-clear-is-separate")
    }
}
