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

    private func sectionProperties(_ object: Any?) throws -> [String: Any] {
        try XCTUnwrap((object as? [String: Any])?["properties"] as? [String: Any])
    }

    /// deprecated로 표시한 읽기 전용 옛 키는 인코드하지 않으므로 비교에서 뺀다.
    private func activeKeys(_ object: Any?) throws -> Set<String> {
        let properties = try sectionProperties(object)
        return Set(properties.filter { (($0.value as? [String: Any])?["deprecated"] as? Bool) != true }.keys)
    }

    private func encodedSampleRecipe() throws -> [String: Any] {
        var recipe = EditRecipe()
        recipe.portrait.targetFace = 1
        recipe.portrait.skin = SkinAdjustments(smoothing: 0.3, autoBlemish: true, darkCircles: 0.2, redness: -0.1)
        recipe.portrait.face.width = -0.2
        recipe.portrait.features.eyeBrighten = 0.1
        recipe.background.blur = 0.2
        recipe.bodySkin.tone = -0.2
        recipe.body.legLength = 0.3
        recipe.makeup = MakeupAdjustments(
            lookID: "daily", lip: MakeupTint(colorID: "lip-coral", intensity: 0.5),
            blush: MakeupTint(colorID: "blush-peach", intensity: 0.3),
            eyeshadow: MakeupTint(colorID: "shadow-brown", intensity: 0.2), brow: MakeupStrength(intensity: 0.4),
            contour: MakeupStrength(intensity: 0.1))
        recipe.operations = [
            .spot(RetouchSpot(x: 0.5, y: 0.4, sourceX: 0.45, sourceY: 0.4, radius: 0.02)),
            .warp(WarpStroke(x: 0.5, y: 0.4, dx: 0.01, dy: 0, radius: 0.08)),
        ]
        recipe.look = LookSelection(id: "film", intensity: 0.5)
        recipe.geometry.crop = NormalizedRect(x: 0, y: 0, width: 1, height: 1)
        recipe.detail.sharpness = 0.2
        recipe.people.groups[.female] = PortraitLayer(skinSmoothing: 0.5)
        recipe.people.individuals = [
            PersonRecord(
                id: PersonID(), anchor: PersonAnchor(x: 0.3, y: 0.6, width: 0.12), legacyIndex: 0, gender: .female,
                layer: PortraitLayer(face: [.width: -0.3]))
        ]
        recipe.effects.grain = 0.1
        return try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(recipe)) as? [String: Any])
    }

    func testRecipeSchemaPropertiesMatchEncodedKeys() throws {
        let schema = try schema(named: "edit-recipe.v2.schema")
        let properties = try XCTUnwrap(schema["properties"] as? [String: Any])
        let encoded = try encodedSampleRecipe()
        XCTAssertEqual(Set(properties.keys), Set(encoded.keys))
        for key in [
            "color", "portrait", "detail", "look", "geometry", "background", "bodySkin", "body", "makeup", "effects",
            "people",
        ] {
            let encodedSection = try XCTUnwrap(encoded[key] as? [String: Any], "\(key) 누락")
            XCTAssertEqual(try activeKeys(properties[key]), Set(encodedSection.keys), key)
        }
        let portraitProperties = try sectionProperties(properties["portrait"])
        let encodedPortrait = try XCTUnwrap(encoded["portrait"] as? [String: Any])
        for key in ["skin", "face", "features"] {
            let encodedSection = try XCTUnwrap(encodedPortrait[key] as? [String: Any], "portrait.\(key) 누락")
            XCTAssertEqual(try activeKeys(portraitProperties[key]), Set(encodedSection.keys), "portrait.\(key)")
        }
        let makeupProperties = try sectionProperties(properties["makeup"])
        let encodedMakeup = try XCTUnwrap(encoded["makeup"] as? [String: Any])
        for key in ["lip", "blush", "eyeshadow", "brow", "contour"] {
            let encodedSection = try XCTUnwrap(encodedMakeup[key] as? [String: Any], "makeup.\(key) 누락")
            XCTAssertEqual(try activeKeys(makeupProperties[key]), Set(encodedSection.keys), "makeup.\(key)")
        }
        let geometryProperties = try sectionProperties(properties["geometry"])
        let encodedCrop = try XCTUnwrap((encoded["geometry"] as? [String: Any])?["crop"] as? [String: Any])
        XCTAssertEqual(try propertyKeys(geometryProperties["crop"]), Set(encodedCrop.keys))
        try assertOperationsMatchBranches(properties: properties, encoded: encoded)
        XCTAssertEqual(schema["$id"] as? String, "https://mellow.photo/schema/edit-recipe.v2.schema.json")
    }

    func testPeopleSchemaDescribesLayersGroupsAndRecords() throws {
        let schema = try schema(named: "edit-recipe.v2.schema")
        let properties = try XCTUnwrap(schema["properties"] as? [String: Any])
        let people = try sectionProperties(properties["people"])
        XCTAssertEqual(Set(people.keys), ["groups", "individuals"])
        XCTAssertEqual(try propertyKeys(people["groups"]), Set(Gender.allCases.map(\.rawValue)))
        let item = try XCTUnwrap((people["individuals"] as? [String: Any])?["items"])
        XCTAssertEqual(try propertyKeys(item), ["id", "anchor", "legacyIndex", "gender", "layer"])
        let layer = try XCTUnwrap((schema["$defs"] as? [String: Any])?["portraitLayer"])
        let layerProperties = try sectionProperties(layer)
        XCTAssertEqual(Set(layerProperties.keys), ["skin", "face", "features", "makeup"])
        XCTAssertEqual(
            try propertyKeys(layerProperties["skin"]),
            Set(["smoothing", "autoBlemish"] + SkinRefinementKey.allCases.map(\.rawValue)))
        XCTAssertEqual(try propertyKeys(layerProperties["face"]), Set(FaceShapeKey.allCases.map(\.rawValue)))
        XCTAssertEqual(try propertyKeys(layerProperties["features"]), Set(FeatureKey.allCases.map(\.rawValue)))
        XCTAssertEqual(
            try propertyKeys(layerProperties["makeup"]), Set(["lookID"] + MakeupPart.allCases.map(\.rawValue)))
        let encodedPeople = try XCTUnwrap(try encodedSampleRecipe()["people"] as? [String: Any])
        let encodedRecord = try XCTUnwrap((encodedPeople["individuals"] as? [[String: Any]])?.first)
        let encodedLayer = try XCTUnwrap(encodedRecord["layer"] as? [String: Any])
        XCTAssertTrue(Set(encodedLayer.keys).isSubset(of: Set(layerProperties.keys)))
    }

    func testLegacyPortraitKeysStayInSchemaAsDeprecated() throws {
        let properties = try XCTUnwrap(try schema(named: "edit-recipe.v2.schema")["properties"] as? [String: Any])
        let portrait = try sectionProperties(properties["portrait"])
        for key in ["skinSmoothing", "faceSlim"] {
            let entry = try XCTUnwrap(portrait[key] as? [String: Any], key)
            XCTAssertEqual(entry["deprecated"] as? Bool, true, key)
        }
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
