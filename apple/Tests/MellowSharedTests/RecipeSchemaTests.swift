import XCTest

@testable import MellowShared

/// JSON Schema 검증기 없이, 스키마가 선언한 속성과 실제 인코드 키가 같은지 확인한다.
final class RecipeSchemaTests: XCTestCase {
    private func schema(named name: String) throws -> [String: Any] {
        // apple/Tests/MellowSharedTests/이 파일 → 네 단계 위가 저장소 루트.
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("shared/recipe-schema/\(name).json")
        return try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
    }

    func testRecipeSchemaPropertiesMatchEncodedKeys() throws {
        let schema = try schema(named: "edit-recipe.v2.schema")
        let properties = try XCTUnwrap(schema["properties"] as? [String: Any])
        var recipe = EditRecipe()
        recipe.operations = [.spot(RetouchSpot(x: 0, y: 0, sourceX: 0, sourceY: 0, radius: 0.1))]
        let encoded = try XCTUnwrap(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(recipe)) as? [String: Any])
        XCTAssertEqual(Set(properties.keys), Set(encoded.keys))
        let schemaColor = try XCTUnwrap((properties["color"] as? [String: Any])?["properties"] as? [String: Any])
        let encodedColor = try XCTUnwrap(encoded["color"] as? [String: Any])
        XCTAssertEqual(Set(schemaColor.keys), Set(encodedColor.keys))
        XCTAssertEqual(schema["$id"] as? String, "https://mellow.photo/schema/edit-recipe.v2.json")
    }
}
