import XCTest

/// + 메뉴의 두 가져오기 항목이 실제로 시스템 피커를 띄우는지 본다.
/// 메뉴 항목 안에서 표시를 시작하면 메뉴가 닫히며 피커도 사라지는데, 이는 단위 테스트로 잡히지 않는다.
@MainActor
final class ImportMenuUITests: XCTestCase {
    private enum Label {
        static let importButton = "사진 가져오기"
        static let photosItem = "사진 앱에서 고르기"
        static let filesItem = "파일에서 고르기"
    }

    /// 시스템 피커가 붙이는 접근성 식별자. 기기 언어와 무관하다.
    private enum SystemPicker {
        static let photosCancel = "Cancel"
        static let filesBrowser = "Browse View (Picker)"
    }

    private enum Timeout {
        static let launch: TimeInterval = 15
        static let menu: TimeInterval = 5
        static let picker: TimeInterval = 10
    }

    override func setUp() {
        continueAfterFailure = false
    }

    func testPhotosItemPresentsPhotoPicker() {
        assertEveryImportButton(opens: Label.photosItem) { app in
            app.buttons[SystemPicker.photosCancel]
        }
    }

    func testFilesItemPresentsFileBrowser() {
        assertEveryImportButton(opens: Label.filesItem) { app in
            app.otherElements[SystemPicker.filesBrowser]
        }
    }

    /// 툴바의 +와 빈 화면의 큰 버튼은 같은 컴포넌트지만 표시 위치가 달라 각각 확인한다.
    private func assertEveryImportButton(
        opens item: String, picker: (XCUIApplication) -> XCUIElement,
        file: StaticString = #filePath, line: UInt = #line
    ) {
        let app = XCUIApplication()
        app.launch()
        let buttonCount = enabledImportButtons(in: app).count
        XCTAssertGreaterThan(buttonCount, 0, "가져오기 버튼이 없습니다", file: file, line: line)
        for index in 0..<buttonCount {
            if index > 0 {
                app.terminate()
                app.launch()
            }
            let button = enabledImportButtons(in: app).element(boundBy: index)
            button.tap()
            let entry = app.buttons[item]
            XCTAssertTrue(entry.waitForExistence(timeout: Timeout.menu), "\(index)번 버튼 메뉴", file: file, line: line)
            entry.tap()
            XCTAssertTrue(
                picker(app).waitForExistence(timeout: Timeout.picker), "\(index)번 버튼에서 \(item) 피커가 뜨지 않음",
                file: file, line: line)
        }
    }

    /// 복원 중에는 버튼이 꺼져 있으므로 켜질 때까지 기다린다.
    private func enabledImportButtons(in app: XCUIApplication) -> XCUIElementQuery {
        let buttons = app.buttons.matching(identifier: Label.importButton)
        let enabled = expectation(for: NSPredicate(format: "isEnabled == true"), evaluatedWith: buttons.firstMatch)
        wait(for: [enabled], timeout: Timeout.launch)
        return buttons
    }
}
