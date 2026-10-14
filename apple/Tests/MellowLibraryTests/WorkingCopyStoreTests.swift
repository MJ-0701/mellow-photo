import MellowShared
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

    func testAdoptAlwaysMovesIntoCurrentDirectory() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let store = WorkingCopyStore(directory: root.appendingPathComponent("Library"))
        try store.prepareDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let id = PhotoID()
        let filename = "\(id.rawValue.uuidString).heic"
        try Data([1]).write(to: root.appendingPathComponent(filename))
        let temporary = root.appendingPathComponent("incoming.heic")
        try Data([2]).write(to: temporary)
        XCTAssertEqual(try store.adopt(temporaryFile: temporary, as: id), filename)
        XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent("Library/\(filename)")), Data([2]))
        XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent(filename)), Data([1]), "옛 위치는 건드리지 않는다")
    }
}
