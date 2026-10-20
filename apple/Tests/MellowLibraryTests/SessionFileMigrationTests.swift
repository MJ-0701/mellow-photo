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
        XCTAssertEqual(first.document.recipe.portrait.skin.smoothing, 0.3)
        XCTAssertEqual(first.document.recipe.portrait.face.width, -0.2)
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
        XCTAssertEqual(snapshot.presets[0].values.portrait.skin.smoothing, 0.3)
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

    func testB0SessionWithLegacyPortraitKeysMigratesUndoHistory() throws {
        let json = """
            {"schemaVersion":2,"photos":[{"id":"22222222-2222-2222-2222-222222222222",\
            "filename":"22222222-2222-2222-2222-222222222222.heic","displayName":"사진 1",\
            "recipe":{"schemaVersion":2,"portrait":{"skinSmoothing":0.4,"faceSlim":0.25,"targetFace":0}},\
            "undo":[{"schemaVersion":2,"portrait":{"skinSmoothing":0.1}}],"redo":[]}],\
            "presets":[{"id":"33333333-3333-3333-3333-333333333333","name":"옛",\
            "values":{"color":{},"portrait":{"faceSlim":0.3}}}]}
            """
        let snapshot = SessionFileMapper.snapshot(from: try SessionFile.decode(Data(json.utf8)))
        let document = snapshot.photos[0].document
        XCTAssertEqual(document.recipe.portrait.skin.smoothing, 0.4)
        XCTAssertEqual(document.recipe.portrait.face.width, -0.25)
        XCTAssertEqual(document.recipe.portrait.targetFace, 0)
        XCTAssertEqual(document.undoStack[0].portrait.skin.smoothing, 0.1)
        XCTAssertEqual(snapshot.presets[0].values.portrait.face.width, -0.3)
        let rewritten = try SessionFile.encode(SessionFileMapper.file(from: snapshot))
        let text = try XCTUnwrap(String(data: rewritten, encoding: .utf8))
        XCTAssertFalse(text.contains("skinSmoothing"), "다시 저장하면 옛 키를 쓰지 않는다")
        XCTAssertFalse(text.contains("faceSlim"))
    }

    func testPresetPeopleGroupsPersistAndIndividualsAreDropped() throws {
        var values = PresetValues(color: ColorAdjustments(exposure: 0.2))
        values.people.groups[.male] = PortraitLayer(skinSmoothing: 0.2)
        let preset = Preset(name: "남녀", values: values)
        let snapshot = SessionSnapshot(photos: [], selectedPhotoID: nil, presets: [preset])
        let data = try SessionFile.encode(SessionFileMapper.file(from: snapshot))
        let restored = SessionFileMapper.snapshot(from: try SessionFile.decode(data))
        XCTAssertEqual(restored.presets[0].values.people.groups[.male], PortraitLayer(skinSmoothing: 0.2))
        let json = """
            {"schemaVersion":2,"photos":[],"presets":[{"id":"33333333-3333-3333-3333-333333333333","name":"옛",\
            "values":{"color":{},"portrait":{},"people":{"groups":{"female":{"face":{"jaw":0.1}}},\
            "individuals":[{"id":"44444444-4444-4444-4444-444444444444","anchor":{"x":0.5,"y":0.5,"width":0.2},\
            "layer":{"skin":{"smoothing":1}}}]}}}]}
            """
        let decoded = SessionFileMapper.snapshot(from: try SessionFile.decode(Data(json.utf8)))
        XCTAssertEqual(decoded.presets[0].values.people.groups[.female], PortraitLayer(face: [.jaw: 0.1]))
        XCTAssertTrue(decoded.presets[0].values.people.individuals.isEmpty)
    }
}
