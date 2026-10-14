import MellowEditing
import MellowShared
import XCTest

@testable import MellowLibrary

/// JSON Schema 검증기 없이, session-file.v2 스키마가 선언한 속성과 실제 인코드 키가 같은지 확인한다.
/// 값 범위와 required 목록은 검사하지 않는다.
final class SessionSchemaTests: XCTestCase {
    private func schema() throws -> [String: Any] {
        // apple/Tests/MellowLibraryTests/이 파일 → 네 단계 위가 저장소 루트.
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("shared/recipe-schema/session-file.v2.schema.json")
        return try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
    }

    private func properties(_ object: Any?) throws -> [String: Any] {
        try XCTUnwrap((object as? [String: Any])?["properties"] as? [String: Any])
    }

    private func encodedSampleSession() throws -> [String: Any] {
        var edited = EditRecipe()
        edited.color.exposure = 0.4
        let earlier = EditRecipe()
        var undone = EditRecipe()
        undone.color.exposure = 0.6
        let id = PhotoID()
        let photo = PhotoEntry(
            id: id, filename: "\(id.rawValue.uuidString).heic", displayName: "사진 1",
            document: EditDocument(recipe: edited, undoStack: [earlier], redoStack: [undone]))
        let snapshot = SessionSnapshot(photos: [photo], selectedPhotoID: id, presets: [BuiltInPresets.cozy])
        let data = try SessionFile.encode(SessionFileMapper.file(from: snapshot))
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    func testSessionSchemaPropertiesMatchEncodedKeys() throws {
        let schema = try schema()
        XCTAssertEqual(schema["$id"] as? String, "https://mellow.photo/schema/session-file.v2.schema.json")
        let top = try properties(schema)
        let encoded = try encodedSampleSession()
        XCTAssertEqual(Set(top.keys), Set(encoded.keys))

        let photoItem = try properties((top["photos"] as? [String: Any])?["items"])
        let photos = try XCTUnwrap(encoded["photos"] as? [[String: Any]])
        XCTAssertEqual(photos.count, 1)
        XCTAssertEqual(Set(photoItem.keys), Set(try XCTUnwrap(photos.first).keys))

        let presetItem = try properties((top["presets"] as? [String: Any])?["items"])
        let presets = try XCTUnwrap(encoded["presets"] as? [[String: Any]])
        let preset = try XCTUnwrap(presets.first)
        XCTAssertEqual(Set(presetItem.keys), Set(preset.keys))

        let valuesSchema = try properties(presetItem["values"])
        let values = try XCTUnwrap(preset["values"] as? [String: Any])
        XCTAssertEqual(Set(valuesSchema.keys), Set(values.keys))
    }
}
