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
}
