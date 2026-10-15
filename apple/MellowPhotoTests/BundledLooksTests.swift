import MellowShared
import XCTest

@testable import Mellow_Photo

final class BundledLooksTests: XCTestCase {
    func testBundledLooksAreIdenticalToSharedFile() throws {
        let bundled = try XCTUnwrap(Bundle.main.url(forResource: "looks.v1", withExtension: "json"))
        let shared = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("shared/looks/looks.v1.json")
        XCTAssertEqual(try Data(contentsOf: bundled), try Data(contentsOf: shared))
        XCTAssertEqual(try LookCatalog(data: Data(contentsOf: bundled)).all.count, 10)
    }
}
