import XCTest

@testable import MellowShared

final class MakeupCatalogTests: XCTestCase {
    private func sharedMakeupData() throws -> Data {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("shared/makeup/makeup.v1.json")
        return try Data(contentsOf: url)
    }

    func testSharedCatalogHasFiveLooksAndFixedPalettes() throws {
        let catalog = try MakeupCatalog(data: sharedMakeupData())
        XCTAssertEqual(catalog.looks.map(\.id), MakeupCatalog.builtInLookIDs)
        XCTAssertEqual(MakeupCatalog.builtInLookIDs, ["daily", "cool", "warm-peach", "rosy", "smoky"])
        XCTAssertEqual(catalog.looks.map(\.name), ["데일리", "쿨톤", "웜피치", "로지", "스모키"])
        for part in MakeupPart.allCases {
            XCTAssertEqual(catalog.colors(for: part).map(\.id), MakeupCatalog.builtInColorIDs[part] ?? [], "\(part)")
        }
        XCTAssertEqual(catalog.colors(for: .lip).count, 6)
        XCTAssertEqual(catalog.colors(for: .blush).count, 4)
        XCTAssertEqual(catalog.colors(for: .eyeshadow).count, 4)
        XCTAssertTrue(catalog.colors(for: .brow).isEmpty, "눈썹·쉐딩은 색이 없다")
        XCTAssertEqual(catalog.look(id: "daily")?.name, "데일리")
        XCTAssertNil(catalog.look(id: "nope"))
        XCTAssertNil(catalog.look(id: nil))
        XCTAssertEqual(catalog.color(id: "lip-coral")?.name, "코랄")
        XCTAssertNil(catalog.color(id: "lip-coral", for: .blush), "다른 부위 팔레트에서는 찾지 않는다")
        XCTAssertFalse(catalog.isEmpty)
    }

    func testEveryColorAndLookIsInRangeAndLooksUseTheirOwnPalette() throws {
        let catalog = try MakeupCatalog(data: sharedMakeupData())
        for part in MakeupPart.allCases {
            for color in catalog.colors(for: part) {
                XCTAssertEqual(color.rgb.count, 3, color.id)
                XCTAssertTrue(color.rgb.allSatisfy { (0...1).contains($0) }, color.id)
                XCTAssertEqual([color.red, color.green, color.blue], color.rgb, color.id)
            }
        }
        for look in catalog.looks {
            let adjustments = look.adjustments
            XCTAssertEqual(adjustments.lookID, look.id)
            for part in MakeupPart.allCases {
                XCTAssertTrue((0...1).contains(adjustments.intensity(of: part)), "\(look.id) \(part)")
            }
            XCTAssertNotNil(catalog.color(id: look.lip.colorID, for: .lip), look.id)
            XCTAssertNotNil(catalog.color(id: look.blush.colorID, for: .blush), look.id)
            XCTAssertNotNil(catalog.color(id: look.eyeshadow.colorID, for: .eyeshadow), look.id)
        }
        let daily = try XCTUnwrap(catalog.look(id: "daily"))
        XCTAssertEqual(
            daily.adjustments,
            MakeupAdjustments(
                lookID: "daily", lip: MakeupTint(colorID: "lip-mlbb", intensity: 0.5),
                blush: MakeupTint(colorID: "blush-peach", intensity: 0.35),
                eyeshadow: MakeupTint(colorID: "shadow-brown", intensity: 0.3), brow: MakeupStrength(intensity: 0.3),
                contour: MakeupStrength(intensity: 0.2)))
        XCTAssertEqual(MakeupColor(id: "x", name: "x", rgb: [0.5]).blue, 0, "성분이 모자라면 0")
    }

    func testRejectsUnknownSchemaPartBadRGBForeignColorAndRange() throws {
        let rejected = [
            #"{"schemaVersion":2,"colors":{},"looks":[]}"#,
            #"{"schemaVersion":1,"colors":{"brow":[]},"looks":[]}"#,
            #"{"schemaVersion":1,"colors":{"lip":[{"id":"a","name":"a","rgb":[1.2,0,0]}]},"looks":[]}"#,
            #"{"schemaVersion":1,"colors":{"lip":[{"id":"a","name":"a","rgb":[0.5,0.5]}]},"looks":[]}"#,
            #"{"schemaVersion":1,"colors":{"lip":[{"id":"a","name":"a","rgb":[0,0,0]}],"#
                + #""blush":[{"id":"a","name":"a","rgb":[0,0,0]}]},"looks":[]}"#,
            #"{"schemaVersion":1,"colors":{"lip":[{"id":"a","name":"a","rgb":[0,0,0]}],"#
                + #""blush":[{"id":"b","name":"b","rgb":[0,0,0]}]},"looks":[{"id":"x","name":"x","#
                + #""lip":{"colorID":"b","intensity":0.5},"blush":{"intensity":0},"eyeshadow":{"intensity":0},"#
                + #""brow":{"intensity":0},"contour":{"intensity":0}}]}"#,
            #"{"schemaVersion":1,"colors":{},"looks":[{"id":"x","name":"x","lip":{"intensity":0},"#
                + #""blush":{"intensity":0},"eyeshadow":{"intensity":0},"brow":{"intensity":1.5},"#
                + #""contour":{"intensity":0}}]}"#,
        ]
        for json in rejected {
            XCTAssertThrowsError(try MakeupCatalog(data: Data(json.utf8)), json)
        }
        let minimal = try MakeupCatalog(data: Data(#"{"schemaVersion":1,"colors":{},"looks":[]}"#.utf8))
        XCTAssertTrue(minimal.isEmpty)
        XCTAssertTrue(MakeupCatalog.empty.isEmpty)
        XCTAssertEqual(minimal, MakeupCatalog.empty)
    }
}
