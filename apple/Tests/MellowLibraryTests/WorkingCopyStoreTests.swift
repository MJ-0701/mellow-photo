import XCTest

@testable import MellowLibrary

final class WorkingCopyStoreTests: XCTestCase {
    func testLegacyWorkingCopyLocationIsFound() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let store = WorkingCopyStore(directory: root.appendingPathComponent("Library"))
        try store.prepareDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        try Data([1]).write(to: root.appendingPathComponent("old.heic"))
        XCTAssertEqual(store.url(for: "old.heic"), root.appendingPathComponent("old.heic"))
        XCTAssertEqual(store.url(for: "new.heic"), root.appendingPathComponent("Library/new.heic"))
    }
}
