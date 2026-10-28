import Foundation
import MellowShared
import XCTest

@testable import MellowEditing

final class OneTouchApplicationTests: XCTestCase {
    private let faces = [NormalizedRect(x: 0.15, y: 0.2, width: 0.25, height: 0.4)]
    private var target: PortraitPurposeFace {
        PortraitPurposeFace(index: 0, gender: .female, availableKeys: OneTouchBundle.keys)
    }

    func testFullyProtectedDefaultDoesNotStoreAnUnrealizedStrengthOrUndo() {
        var document = EditDocument()
        document.applyOneTouch(strength: 0.2, forFace: 0, of: faces)
        document.set(.gender(.female), forFace: 0, of: faces)
        let before = document
        let result = document.applyOneTouchReporting(strength: 1, faces: faces, targets: [target])
        XCTAssertEqual(result.changedCount, 0)
        XCTAssertEqual(result.items.filter { $0.reason == .protectedPersonal }.count, OneTouchBundle.keys.count)
        XCTAssertEqual(document, before)
    }

    func testExplicitReplacementOnlyChangesSelectedPersonalBundleAndOneUndo() {
        var document = EditDocument()
        document.applyOneTouch(strength: 0.6)
        document.set(.exposure(0.8))
        document.set(.skinSmoothing(0.04), forFace: 0, of: faces)
        document.set(.faceShape(.jaw, 0.3), forFace: 0, of: faces)
        let before = document
        let result = document.applyOneTouchReporting(
            strength: 1, faces: faces, targets: [target], replacingPersonal: true)
        XCTAssertGreaterThan(result.changedCount, 0)
        let person = document.recipe.people.peopleByFace(faces)[0]!
        XCTAssertEqual(person.layer.skinSmoothing, OneTouchBundle.Table.female.smoothing)
        XCTAssertEqual(person.layer.face[.jaw], 0.3)
        XCTAssertEqual(document.recipe.portrait, before.recipe.portrait)
        XCTAssertEqual(document.recipe.people.groups, before.recipe.people.groups)
        XCTAssertEqual(document.recipe.color, before.recipe.color)
        XCTAssertEqual(document.recipe.bodySkin, before.recipe.bodySkin)
        XCTAssertEqual(document.undoStack.count, before.undoStack.count + 1)
        let applied = document
        document.undo()
        XCTAssertEqual(document.recipe, before.recipe)
        document.redo()
        XCTAssertEqual(document.recipe, applied.recipe)
        _ = document.applyOneTouchReporting(strength: 1, faces: faces, targets: [target], replacingPersonal: true)
        XCTAssertEqual(document, applied)
    }

    func testExplicitZeroBlocksInheritanceAndLegacyZeroStillRemoves() {
        var document = EditDocument()
        document.applyOneTouch(strength: 1)
        let result = document.applyOneTouchReporting(
            strength: 0, faces: faces, targets: [target], replacingPersonal: true)
        XCTAssertGreaterThan(result.changedCount, 0)
        let person = document.recipe.people.peopleByFace(faces)[0]
        XCTAssertEqual(person?.layer.skinSmoothing, 0)
        XCTAssertEqual(person?.layer.autoBlemish, false)
        XCTAssertEqual(person?.layer.oneTouch, 0)
        XCTAssertEqual(document.recipe.portrait.skin.smoothing, OneTouchBundle.Table.common.smoothing)
        let neutral = document
        _ = document.applyOneTouchReporting(strength: 0, faces: faces, targets: [target], replacingPersonal: true)
        XCTAssertEqual(document, neutral)
        document.undo()
        XCTAssertTrue(document.recipe.people.individuals.isEmpty)
        document.redo()
        XCTAssertEqual(document.recipe, neutral.recipe)
        document.applyOneTouch(strength: 0, forFace: 0, of: faces)
        XCTAssertNil(document.recipe.people.peopleByFace(faces)[0]?.layer.skinSmoothing)
    }
    func testUnavailableDefaultStoredValuesAreReportedOnlyWhenSomeReadyChangeCommits() {
        var document = EditDocument()
        let partial = PortraitPurposeFace(index: 0, gender: .female, availableKeys: [.skinSmoothing])
        let result = document.applyOneTouchReporting(strength: 1, faces: faces, targets: [partial])
        XCTAssertEqual(result.changedCount, 1)
        XCTAssertGreaterThan(result.resolvedChangedCount, 1)
        XCTAssertTrue(
            result.items.contains { $0.key == .feature(.eyeBrighten) && $0.resolvedChanged && !$0.renderReady })
        XCTAssertEqual(document.recipe.portrait.features.eyeBrighten, OneTouchBundle.Table.common.eyeBrighten)
        let before = document
        let unavailable = PortraitPurposeFace(index: 0, gender: .female, availableKeys: [])
        let noEffect = document.applyOneTouchReporting(strength: 0.5, faces: faces, targets: [unavailable])
        XCTAssertFalse(noEffect.hasChanges)
        XCTAssertEqual(noEffect.resolvedChangedCount, 0)
        XCTAssertEqual(document, before)
    }

    func testExplicitSubsetPreservesOthersAndDuplicateOrMissingTargetsAreNoOp() throws {
        let two = faces + [NormalizedRect(x: 0.65, y: 0.2, width: 0.2, height: 0.35)]
        var document = EditDocument()
        document.set(.skinSmoothing(0.1), forFace: 0, of: two)
        document.set(.skinSmoothing(0.7), forFace: 1, of: two)
        let before = document
        let partial = PortraitPurposeFace(index: 0, gender: .female, availableKeys: [.skinSmoothing])
        let result = document.applyOneTouchReporting(
            strength: 1, faces: two, targets: [partial], replacingPersonal: true)
        XCTAssertEqual(result.changedCount, 1)
        XCTAssertEqual(document.recipe.people.peopleByFace(two)[1], before.recipe.people.peopleByFace(two)[1])
        XCTAssertNil(document.recipe.people.peopleByFace(two)[0]?.layer.features[.eyeBrighten])
        XCTAssertNil(document.recipe.people.peopleByFace(two)[0]?.layer.oneTouch)
        let applied = document
        for targets in [
            [partial, partial], [], [PortraitPurposeFace(index: 8, gender: nil, availableKeys: OneTouchBundle.keys)],
        ] {
            let rejected = document.applyOneTouchReporting(
                strength: 0, faces: two, targets: targets, replacingPersonal: true)
            XCTAssertFalse(rejected.hasChanges)
            XCTAssertEqual(document, applied)
        }
        let restored = try JSONDecoder().decode(EditRecipe.self, from: JSONEncoder().encode(document.recipe))
        XCTAssertEqual(restored, document.recipe)
    }

    func testNeutralColorMetadataAndInheritedZeroDoNotCreateRecords() {
        var document = EditDocument()
        document.set(.makeupColor(.blush, "blush-peach"))
        document.set(.makeupIntensity(.blush, 0))
        let before = document
        let result = document.applyOneTouchReporting(
            strength: 0, faces: faces, targets: [target], replacingPersonal: true)
        XCTAssertFalse(result.hasChanges)
        XCTAssertEqual(document, before)
    }

    func testMixedUnrecordedAlreadyEqualFaceDoesNotRejectOtherPersonsReplacement() {
        let two = faces + [NormalizedRect(x: 0.65, y: 0.2, width: 0.2, height: 0.35)]
        var document = EditDocument()
        document.applyOneTouch(strength: 1)
        document.applyOneTouch(strength: 0.2, forFace: 1, of: two)
        let before = document
        let targets = two.indices.map {
            PortraitPurposeFace(index: $0, gender: nil, availableKeys: OneTouchBundle.keys)
        }
        let result = document.applyOneTouchReporting(strength: 1, faces: two, targets: targets, replacingPersonal: true)
        XCTAssertGreaterThan(result.changedCount, 0)
        XCTAssertNil(document.recipe.people.peopleByFace(two)[0], "이미 같은 상속값에는 새 기록을 만들지 않는다")
        XCTAssertEqual(
            document.recipe.people.peopleByFace(two)[1]?.layer.skinSmoothing, OneTouchBundle.Table.common.smoothing)
        XCTAssertEqual(document.undoStack.count, before.undoStack.count + 1)
        document.undo()
        XCTAssertEqual(document.recipe, before.recipe)
    }

}
