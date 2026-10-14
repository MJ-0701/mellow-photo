import MellowShared
import XCTest

@testable import MellowLibrary

final class JSONSessionStoreTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    func testMissingFileLoadsAsNil() throws {
        let store = JSONSessionStore(fileURL: root.appendingPathComponent("session.json"))
        XCTAssertNil(try store.load())
    }

    func testSaveThenLoadRoundTrips() throws {
        let store = JSONSessionStore(fileURL: root.appendingPathComponent("session.json"))
        let entry = PhotoEntry(id: PhotoID(), filename: "a.heic", displayName: "A")
        let snapshot = SessionSnapshot(photos: [entry], selectedPhotoID: entry.id, presets: [])
        try store.save(snapshot)
        XCTAssertEqual(try store.load(), snapshot)
    }

    func testMalformedFileIsPreservedAsRecoveryCopyBeforeAnythingIsWritten() throws {
        let fileURL = root.appendingPathComponent("session.json")
        let malformed = Data("{ interrupted session".utf8)
        try malformed.write(to: fileURL)
        let store = JSONSessionStore(fileURL: fileURL)
        XCTAssertThrowsError(try store.load()) { error in
            XCTAssertEqual(error as? MellowError, .sessionUnreadable)
        }
        let recovery = try XCTUnwrap(store.recoveryFileURL)
        XCTAssertEqual(try Data(contentsOf: recovery), malformed)
        XCTAssertEqual(try Data(contentsOf: fileURL), malformed, "복구 사본을 만든 뒤에도 원본은 아직 그대로다")
        try store.save(SessionSnapshot())
        XCTAssertEqual(try Data(contentsOf: recovery), malformed)
        XCTAssertNotNil(try store.load())
    }

    func testSaveFailureIsReportedAsSessionWriteFailed() throws {
        let fileURL = root.appendingPathComponent("session.json")
        try FileManager.default.createDirectory(at: fileURL, withIntermediateDirectories: false)
        let store = JSONSessionStore(fileURL: fileURL)
        XCTAssertThrowsError(try store.save(SessionSnapshot())) { error in
            guard case .sessionWriteFailed = error as? MellowError else {
                return XCTFail("예상과 다른 오류: \(error)")
            }
        }
    }
}
