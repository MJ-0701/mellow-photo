import XCTest

@testable import MellowShared

/// JSON Schema 검증기 없이, 스키마가 선언한 속성과 실제 인코드 키가 같은지 확인한다.
/// 값 범위와 required 목록은 검사하지 않는다.
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

    private func propertyKeys(_ object: Any?) throws -> Set<String> {
        let properties = try XCTUnwrap((object as? [String: Any])?["properties"] as? [String: Any])
        return Set(properties.keys)
    }

    private func encodedSampleRecipe() throws -> [String: Any] {
        var recipe = EditRecipe()
        recipe.portrait.targetFace = 1
        recipe.operations = [
            .spot(RetouchSpot(x: 0.5, y: 0.4, sourceX: 0.45, sourceY: 0.4, radius: 0.02)),
            .warp(WarpStroke(x: 0.5, y: 0.4, dx: 0.01, dy: 0, radius: 0.08)),
        ]
        return try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(recipe)) as? [String: Any])
    }

    func testRecipeSchemaPropertiesMatchEncodedKeys() throws {
        let schema = try schema(named: "edit-recipe.v2.schema")
        let properties = try XCTUnwrap(schema["properties"] as? [String: Any])
        let encoded = try encodedSampleRecipe()
        XCTAssertEqual(Set(properties.keys), Set(encoded.keys))
        let encodedColor = try XCTUnwrap(encoded["color"] as? [String: Any])
        XCTAssertEqual(try propertyKeys(properties["color"]), Set(encodedColor.keys))
        let encodedPortrait = try XCTUnwrap(encoded["portrait"] as? [String: Any])
        XCTAssertEqual(try propertyKeys(properties["portrait"]), Set(encodedPortrait.keys))
        try assertOperationsMatchBranches(properties: properties, encoded: encoded)
        XCTAssertEqual(schema["$id"] as? String, "https://mellow.photo/schema/edit-recipe.v2.schema.json")
    }

    /// 각 수동 편집 항목의 키가 type.const가 같은 oneOf 분기의 properties와 같은지 본다.
    private func assertOperationsMatchBranches(properties: [String: Any], encoded: [String: Any]) throws {
        let items = try XCTUnwrap((properties["operations"] as? [String: Any])?["items"] as? [String: Any])
        let branches = try XCTUnwrap(items["oneOf"] as? [[String: Any]])
        var branchKeys: [String: Set<String>] = [:]
        for branch in branches {
            let branchProperties = try XCTUnwrap(branch["properties"] as? [String: Any])
            let type = try XCTUnwrap((branchProperties["type"] as? [String: Any])?["const"] as? String)
            branchKeys[type] = Set(branchProperties.keys)
        }
        let operations = try XCTUnwrap(encoded["operations"] as? [[String: Any]])
        XCTAssertEqual(operations.count, 2)
        for operation in operations {
            let type = try XCTUnwrap(operation["type"] as? String)
            XCTAssertEqual(branchKeys[type], Set(operation.keys), "\(type) 항목의 키가 스키마 분기와 다르다")
        }
        XCTAssertEqual(Set(operations.compactMap { $0["type"] as? String }), Set(branchKeys.keys))
    }
}
