import XCTest

@testable import MellowShared

final class EditRecipeCodingTests: XCTestCase {
    func testDefaultRecipeIsDefaultAndNeedsNoFaces() {
        let recipe = EditRecipe()
        XCTAssertTrue(recipe.isDefault)
        XCTAssertFalse(recipe.hasLocalEdits)
        XCTAssertFalse(recipe.dependsOnFaces)
    }

    func testRoundTripPreservesOperationsOrderAndSchemaVersion() throws {
        var recipe = EditRecipe()
        recipe.color.exposure = 0.4
        recipe.portrait.skinSmoothing = 0.3
        recipe.portrait.targetFace = 1
        recipe.operations = [
            .spot(RetouchSpot(x: 0.5, y: 0.4, sourceX: 0.45, sourceY: 0.4, radius: 0.02)),
            .warp(WarpStroke(x: 0.5, y: 0.4, dx: 0.01, dy: 0, radius: 0.08)),
        ]
        let data = try JSONEncoder().encode(recipe)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(json["schemaVersion"] as? Int, 2)
        let operations = try XCTUnwrap(json["operations"] as? [[String: Any]])
        XCTAssertEqual(operations[0]["type"] as? String, "spot")
        XCTAssertEqual(operations[1]["type"] as? String, "warp")
        XCTAssertEqual(operations[0]["sourceX"] as? Double, 0.45)
        let decoded = try JSONDecoder().decode(EditRecipe.self, from: data)
        XCTAssertEqual(decoded, recipe)
        XCTAssertTrue(decoded.dependsOnFaces)
        XCTAssertTrue(decoded.hasLocalEdits)
    }

    func testMissingKeysDecodeToDefaults() throws {
        let json = #"{"schemaVersion":2,"color":{"exposure":0.2}}"#
        let decoded = try JSONDecoder().decode(EditRecipe.self, from: Data(json.utf8))
        XCTAssertEqual(decoded.color.exposure, 0.2)
        XCTAssertEqual(decoded.color.contrast, 1)
        XCTAssertEqual(decoded.portrait, PortraitAdjustments())
        XCTAssertTrue(decoded.operations.isEmpty)
    }

    func testUnknownOperationTypeFailsLoudly() {
        let json = #"{"schemaVersion":2,"operations":[{"type":"glitter","x":0,"y":0}]}"#
        XCTAssertThrowsError(try JSONDecoder().decode(EditRecipe.self, from: Data(json.utf8)))
    }

    func testBuiltInPresetsMatchShippedIPhoneValues() {
        XCTAssertEqual(BuiltInPresets.all.map(\.name), ["내추럴", "포근한", "클린"])
        XCTAssertEqual(BuiltInPresets.cozy.values.color.warmth, 0.25)
        XCTAssertEqual(BuiltInPresets.cozy.values.portrait.skinSmoothing, 0.3)
        XCTAssertEqual(BuiltInPresets.clean.values.color.contrast, 1.05)
    }

    func testRecipeWithoutNewKeysDecodesToDefaults() throws {
        let json = #"{"schemaVersion":2,"color":{"exposure":0.2},"portrait":{},"operations":[]}"#
        let decoded = try JSONDecoder().decode(EditRecipe.self, from: Data(json.utf8))
        XCTAssertEqual(decoded.detail, DetailAdjustments())
        XCTAssertEqual(decoded.look, LookSelection())
        XCTAssertEqual(decoded.geometry, GeometryAdjustments())
        XCTAssertNil(decoded.look.id)
        XCTAssertEqual(decoded.look.intensity, 1)
        var plain = decoded
        plain.color.exposure = 0
        XCTAssertTrue(plain.isDefault)
    }

    func testNewFieldsRoundTripAndAffectDefaultness() throws {
        var recipe = EditRecipe()
        recipe.detail.highlights = -0.4
        recipe.look = LookSelection(id: "film", intensity: 0.7)
        recipe.geometry = GeometryAdjustments(
            flipHorizontal: true, quarterTurns: 1, straightenDegrees: -3,
            crop: NormalizedRect(x: 0.1, y: 0.2, width: 0.5, height: 0.5))
        XCTAssertFalse(recipe.isDefault)
        let data = try JSONEncoder().encode(recipe)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual((json["look"] as? [String: Any])?["id"] as? String, "film")
        XCTAssertEqual((json["geometry"] as? [String: Any])?["quarterTurns"] as? Int, 1)
        let decoded = try JSONDecoder().decode(EditRecipe.self, from: data)
        XCTAssertEqual(decoded, recipe)
    }

    func testNonFiniteGeometryIsNotFinite() {
        var recipe = EditRecipe()
        recipe.geometry.straightenDegrees = .infinity
        XCTAssertFalse(recipe.allValuesFinite)
        recipe.geometry.straightenDegrees = 0
        recipe.detail.vignette = .nan
        XCTAssertFalse(recipe.allValuesFinite)
    }

    func testPresetValuesCarryDetail() throws {
        let values = PresetValues(detail: DetailAdjustments(vignette: 0.3))
        let decoded = try JSONDecoder().decode(PresetValues.self, from: JSONEncoder().encode(values))
        XCTAssertEqual(decoded.detail.vignette, 0.3)
        let legacy = #"{"color":{},"portrait":{}}"#
        XCTAssertEqual(try JSONDecoder().decode(PresetValues.self, from: Data(legacy.utf8)).detail, DetailAdjustments())
    }
}
