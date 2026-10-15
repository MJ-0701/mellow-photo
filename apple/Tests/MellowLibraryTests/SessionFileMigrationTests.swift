import MellowEditing
import MellowShared
import XCTest

@testable import MellowLibrary

final class SessionFileMigrationTests: XCTestCase {
    private func fixture(_ name: String) throws -> Data {
        let url = try XCTUnwrap(Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures"))
        return try Data(contentsOf: url)
    }

    func testV1SessionDecodesToV2Snapshot() throws {
        let file = try SessionFile.decode(fixture("session-v1"))
        let snapshot = SessionFileMapper.snapshot(from: file)
        XCTAssertEqual(snapshot.photos.count, 2)
        let first = snapshot.photos[0]
        XCTAssertEqual(first.id.rawValue.uuidString, "11111111-1111-1111-1111-111111111111")
        XCTAssertEqual(first.filename, "11111111-1111-1111-1111-111111111111.heic")
        XCTAssertEqual(first.displayName, "사진 1")
        XCTAssertEqual(first.document.recipe.color.exposure, 0.4)
        XCTAssertEqual(first.document.recipe.portrait.skinSmoothing, 0.3)
        XCTAssertEqual(first.document.recipe.portrait.faceSlim, 0.2)
        XCTAssertEqual(first.document.recipe.portrait.targetFace, 1)
        XCTAssertEqual(
            first.document.recipe.operations,
            [
                .spot(RetouchSpot(x: 0.5, y: 0.4, sourceX: 0.45, sourceY: 0.4, radius: 0.02)),
                .warp(WarpStroke(x: 0.5, y: 0.4, dx: 0.01, dy: 0, radius: 0.08)),
            ])
        XCTAssertEqual(snapshot.photos[1].document.recipe.color.warmth, -0.1)
        XCTAssertEqual(snapshot.selectedPhotoID, first.id)
        XCTAssertEqual(snapshot.presets.count, 1)
        XCTAssertEqual(snapshot.presets[0].name, "포근한")
        XCTAssertEqual(snapshot.presets[0].values.portrait.skinSmoothing, 0.3)
        XCTAssertEqual(snapshot.presets[0].values.color.warmth, 0.25)
    }

    func testV1UndoHistoryFlatArrayDecodes() throws {
        let file = try SessionFile.decode(fixture("session-v1"))
        let snapshot = SessionFileMapper.snapshot(from: file)
        let first = snapshot.photos[0].document
        XCTAssertEqual(first.undoStack.count, 2)
        XCTAssertEqual(first.undoStack[1].color.exposure, 0.1)
        XCTAssertEqual(first.redoStack.count, 1)
        XCTAssertEqual(first.redoStack[0].color.exposure, 0.6)
        XCTAssertTrue(snapshot.photos[1].document.undoStack.isEmpty)
    }

    func testV1DanglingSelectionFallsBackToFirstPhoto() throws {
        var json = try XCTUnwrap(String(data: fixture("session-v1"), encoding: .utf8))
        json = json.replacingOccurrences(
            of: "\"selectedID\" : \"11111111-1111-1111-1111-111111111111\"",
            with: "\"selectedID\" : \"99999999-9999-9999-9999-999999999999\"")
        let snapshot = SessionFileMapper.snapshot(from: try SessionFile.decode(Data(json.utf8)))
        XCTAssertEqual(snapshot.selectedPhotoID, snapshot.photos[0].id)
    }

    func testV2RoundTripIsLossless() throws {
        var document = EditDocument()
        document.set(.exposure(0.3))
        document.appendLocalEdit(.warp(WarpStroke(x: 0.5, y: 0.5, dx: 0.01, dy: 0, radius: 0.1)))
        let entry = PhotoEntry(id: PhotoID(), filename: "a.heic", displayName: "A", document: document)
        let preset = Preset(name: "P", values: PresetValues(color: ColorAdjustments(exposure: 0.2)))
        let snapshot = SessionSnapshot(photos: [entry], selectedPhotoID: entry.id, presets: [preset])
        let data = try SessionFile.encode(SessionFileMapper.file(from: snapshot))
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(json["schemaVersion"] as? Int, 2)
        let restored = SessionFileMapper.snapshot(from: try SessionFile.decode(data))
        XCTAssertEqual(restored, snapshot)
    }

    func testV1DecodeNeverProducesSchemaVersion1OnEncode() throws {
        let file = try SessionFile.decode(fixture("session-v1"))
        let data = try SessionFile.encode(file)
        XCTAssertTrue(try XCTUnwrap(String(data: data, encoding: .utf8)).contains("\"schemaVersion\":2"))
    }

    func testPresetWithoutDetailDecodes() throws {
        let json = """
            {"schemaVersion":2,"photos":[],"presets":[{"id":"33333333-3333-3333-3333-333333333333","name":"옛","values":{"color":{"exposure":0.1},"portrait":{}}}]}
            """
        let snapshot = SessionFileMapper.snapshot(from: try SessionFile.decode(Data(json.utf8)))
        XCTAssertEqual(snapshot.presets[0].values.detail, DetailAdjustments())
    }
}
