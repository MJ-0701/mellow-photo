import XCTest

@testable import MellowShared

final class LookCatalogTests: XCTestCase {
    private func sharedLooksData() throws -> Data {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("shared/looks/looks.v1.json")
        return try Data(contentsOf: url)
    }

    func testSharedCatalogHasTenLooksInFixedOrder() throws {
        let catalog = try LookCatalog(data: sharedLooksData())
        XCTAssertEqual(catalog.all.map(\.id), LookCatalog.builtInIDs)
        XCTAssertEqual(
            LookCatalog.builtInIDs,
            ["clear", "film", "cozy", "calm", "mono", "sepia", "vintage", "vivid", "pastel", "night"])
        XCTAssertEqual(catalog.look(id: "film")?.name, "필름")
        XCTAssertNil(catalog.look(id: "nope"))
    }

    func testEveryLookHasValidToneCurveAndRanges() throws {
        for look in try LookCatalog(data: sharedLooksData()).all {
            XCTAssertEqual(look.toneCurve.count, 5, look.id)
            XCTAssertEqual(look.toneCurve.first?[0], 0, look.id)
            XCTAssertEqual(look.toneCurve.last?[0], 1, look.id)
            let xs = look.toneCurve.map { $0[0] }
            XCTAssertEqual(xs, xs.sorted(), "\(look.id) 톤 커브 x는 오름차순")
            XCTAssertTrue((0...2).contains(look.saturation), look.id)
            XCTAssertTrue((0.5...1.5).contains(look.contrast), look.id)
            XCTAssertTrue((-1...1).contains(look.warmth), look.id)
            XCTAssertTrue((0...1).contains(look.vignette), look.id)
            XCTAssertTrue((0...1).contains(look.fade), look.id)
        }
    }

    func testEmptyCatalogAndUnknownSchemaVersion() {
        XCTAssertTrue(LookCatalog.empty.all.isEmpty)
        XCTAssertThrowsError(try LookCatalog(data: Data(#"{"schemaVersion":9,"looks":[]}"#.utf8)))
    }
}
