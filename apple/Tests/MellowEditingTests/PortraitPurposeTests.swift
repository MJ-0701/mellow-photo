import MellowShared
import XCTest

@testable import MellowEditing

final class PortraitPurposeTests: XCTestCase {
    private let face = NormalizedRect(x: 0.2, y: 0.3, width: 0.4, height: 0.5)

    func testSkinPurposeChangesOnlySkinAndUndoesAsOneAction() {
        var document = EditDocument()
        document.set(.exposure(0.3))
        document.set(.feature(.eyeBrighten, 0.4))
        document.set(.faceShape(.jaw, 0.2))
        document.set(.autoBlemish(true))
        let before = document
        let result = document.applyPortraitPurpose(
            .skin, strength: OneTouchBundle.defaultStrength, faces: [face],
            targets: [PortraitPurposeFace(index: 0, gender: .female, availableKeys: PortraitPurpose.skin.keys)])
        XCTAssertGreaterThan(result.changedCount, 0)
        let person = document.recipe.people.individuals.first
        let resolved = PortraitResolver.resolve(document.recipe, person: person, gender: .female)
        XCTAssertEqual(
            resolved.portrait.skin.smoothing, OneTouchBundle.Table.female.smoothing * OneTouchBundle.defaultStrength)
        XCTAssertEqual(document.recipe.color, before.recipe.color)
        XCTAssertEqual(document.recipe.detail, before.recipe.detail)
        XCTAssertEqual(document.recipe.background, before.recipe.background)
        XCTAssertEqual(document.recipe.bodySkin, before.recipe.bodySkin)
        XCTAssertEqual(document.recipe.makeup, before.recipe.makeup)
        XCTAssertEqual(resolved.portrait.face, before.recipe.portrait.face)
        XCTAssertEqual(resolved.portrait.features, before.recipe.portrait.features)
        XCTAssertTrue(resolved.portrait.skin.autoBlemish)
        XCTAssertNil(person?.layer.oneTouch)
        XCTAssertEqual(document.undoStack.count, before.undoStack.count + 1)
        document.undo()
        XCTAssertEqual(document.recipe, before.recipe)
        document.redo()
        XCTAssertEqual(document.recipe.people.individuals.first?.layer, person?.layer)
    }

    func testUnavailableZeroAndSameValueNeverCreateRecordsOrHistory() {
        var document = EditDocument()
        let before = document
        for strength in [0.0, OneTouchBundle.defaultStrength] {
            let result = document.applyPortraitPurpose(
                .skin, strength: strength, faces: [face],
                targets: [PortraitPurposeFace(index: 0, gender: nil, availableKeys: [])])
            XCTAssertEqual(result.changedCount, 0)
            XCTAssertEqual(document, before)
        }
    }
    func testExplicitZeroPartialAndGroupValuesArePreservedUnlessSelectedKeysAreReplaced() {
        var document = EditDocument()
        document.set(.skinRefinement(.spots, 0.3), in: .gender(.female))
        document.set(.skinSmoothing(0), forFace: 0, of: [face])
        document.set(.feature(.lipVitality, 0.7), forFace: 0, of: [face])
        document.set(.autoBlemish(true), forFace: 0, of: [face])
        let before = document
        let targets = [PortraitPurposeFace(index: 0, gender: .female, availableKeys: PortraitPurpose.skin.keys)]
        let result = document.applyPortraitPurpose(.skin, strength: 1, faces: [face], targets: targets)
        let person = document.recipe.people.individuals[0]
        XCTAssertEqual(person.layer.skinSmoothing, 0)
        XCTAssertNil(person.layer.skinRefinement[.spots], "그룹의 명시값을 개인값으로 덮지 않는다")
        XCTAssertTrue(result.items.contains { $0.key == .skinSmoothing && $0.reason == .keptExisting })
        XCTAssertEqual(person.layer.features[.lipVitality], 0.7)
        XCTAssertEqual(person.layer.autoBlemish, true)
        let count = document.undoStack.count
        _ = document.applyPortraitPurpose(.skin, strength: 1, faces: [face], targets: targets, replacingExisting: true)
        XCTAssertEqual(document.recipe.people.individuals[0].layer.skinSmoothing, OneTouchBundle.Table.female.smoothing)
        XCTAssertEqual(document.recipe.people.groups, before.recipe.people.groups)
        XCTAssertEqual(
            document.recipe.people.individuals[0].layer.features, before.recipe.people.individuals[0].layer.features)
        XCTAssertEqual(document.recipe.people.individuals[0].layer.autoBlemish, true)
        XCTAssertEqual(document.undoStack.count, count + 1)
        let same = document
        XCTAssertEqual(
            document.applyPortraitPurpose(
                .skin, strength: 1, faces: [face], targets: targets,
                replacingExisting: true
            ).changedCount, 0)
        XCTAssertEqual(document, same)
    }

    func testShapesApplyOnlyTheOptedInKeyAndKeepLocalEditLock() {
        for purpose in [PortraitPurpose.underChin, .sideChest] {
            var document = EditDocument()
            let target = PortraitPurposeFace(index: 0, gender: .female, availableKeys: purpose.keys)
            XCTAssertEqual(
                document.applyPortraitPurpose(purpose, strength: 1, faces: [face], targets: [target]).changedCount, 1)
            let layer = document.recipe.people.individuals[0].layer
            XCTAssertEqual(layer.overriddenKeys, purpose.keys)
            document.undo()
            XCTAssertTrue(document.recipe.isDefault)
            document.appendLocalEdit(.warp(WarpStroke(x: 0.5, y: 0.5, dx: 0.01, dy: 0, radius: 0.1)))
            let locked = document
            let rejected = document.applyPortraitPurpose(purpose, strength: 1, faces: [face], targets: [target])
            XCTAssertEqual(rejected.changedCount, 0)
            XCTAssertTrue(rejected.items.allSatisfy { $0.reason == .geometryLocked })
            XCTAssertEqual(document, locked)
        }
    }

    func testPurposeAndLegacyOneTouchKeepExplicitPersonalPriorityWithoutPretendingMarkerIsResolvedStrength() {
        var document = EditDocument()
        let target = PortraitPurposeFace(index: 0, gender: .female, availableKeys: PortraitPurpose.skin.keys)
        _ = document.applyPortraitPurpose(
            .skin, strength: OneTouchBundle.defaultStrength, faces: [face], targets: [target])
        let personal = document.recipe.people.individuals[0]
        for strength in [1.0, 0.0] {
            document.applyOneTouch(strength: strength)
            XCTAssertEqual(document.recipe.people.individuals[0], personal)
            let resolved = PortraitResolver.resolve(document.recipe, person: personal, gender: .female)
            XCTAssertEqual(
                resolved.portrait.skin.smoothing,
                OneTouchBundle.Table.female.smoothing * OneTouchBundle.defaultStrength)
            XCTAssertNotEqual(resolved.portrait.skin.smoothing, OneTouchBundle.Table.female.smoothing * strength)
        }
        let before = document
        let targets = [target, target]
        let result = document.applyPortraitPurpose(
            .skin, strength: 1, faces: [face], targets: targets, replacingExisting: true)
        XCTAssertEqual(result.items.count, PortraitPurpose.skin.keys.count, "같은 인물을 두 번 집계하지 않는다")
        for item in result.items {
            XCTAssertEqual(item.gender, .female)
            if item.reason == .changed {
                XCTAssertNotEqual(item.resolvedBefore, item.resolvedAfter)
            } else {
                XCTAssertEqual(item.resolvedBefore, item.resolvedAfter)
            }
        }
        XCTAssertEqual(document.undoStack.count, before.undoStack.count + 1)
    }

}
