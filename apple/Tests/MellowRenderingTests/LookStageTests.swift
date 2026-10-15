import CoreImage
import MellowShared
import XCTest

@testable import MellowRendering

final class LookStageTests: XCTestCase {
    typealias Support = RenderingTestSupport

    func testIntensityZeroIsIdentityAndOneIsNot() throws {
        let catalog = try Support.sharedLookCatalog()
        let input = Support.gradient()
        var recipe = EditRecipe()
        recipe.look = LookSelection(id: "film", intensity: 0)
        XCTAssertEqual(
            try Support.bytes(Support.render(input, recipe: recipe, catalog: catalog)), try Support.bytes(input))
        recipe.look.intensity = 1
        XCTAssertNotEqual(
            try Support.bytes(Support.render(input, recipe: recipe, catalog: catalog)), try Support.bytes(input))
    }

    func testEveryBuiltInLookRendersAndChangesTheImage() throws {
        let catalog = try Support.sharedLookCatalog()
        let input = Support.gradient()
        let original = try Support.bytes(input)
        for id in LookCatalog.builtInIDs {
            var recipe = EditRecipe()
            recipe.look = LookSelection(id: id, intensity: 1)
            let result = try Support.render(input, recipe: recipe, catalog: catalog)
            XCTAssertEqual(result.extent, input.extent, id)
            XCTAssertNotEqual(try Support.bytes(result), original, "\(id)는 원본과 달라야 한다")
        }
    }

    func testUnknownLookOrEmptyCatalogIsIdentity() throws {
        let input = Support.gradient()
        var recipe = EditRecipe()
        recipe.look = LookSelection(id: "glitter", intensity: 1)
        XCTAssertEqual(
            try Support.bytes(Support.render(input, recipe: recipe, catalog: try Support.sharedLookCatalog())),
            try Support.bytes(input))
        recipe.look.id = "film"
        XCTAssertEqual(
            try Support.bytes(Support.render(input, recipe: recipe, catalog: .empty)), try Support.bytes(input))
    }

    func testHalfIntensityLiesBetweenOriginalAndFullLook() throws {
        let catalog = try Support.sharedLookCatalog()
        let gray = Support.solid(CIColor(red: 0.5, green: 0.5, blue: 0.5), size: 8)
        func red(_ intensity: Double) throws -> Int {
            var recipe = EditRecipe()
            recipe.look = LookSelection(id: "sepia", intensity: intensity)
            return Int(try Support.bytes(Support.render(gray, recipe: recipe, catalog: catalog))[0])
        }
        let zero = try red(0)
        let half = try red(0.5)
        let full = try red(1)
        XCTAssertNotEqual(zero, full)
        XCTAssertNotEqual(half, zero)
        XCTAssertTrue((min(zero, full)...max(zero, full)).contains(half))
    }
}
