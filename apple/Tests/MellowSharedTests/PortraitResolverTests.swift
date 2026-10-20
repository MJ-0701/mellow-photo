import XCTest

@testable import MellowShared

final class PortraitResolverTests: XCTestCase {
    private let id = PersonID()

    private func sample() -> EditRecipe {
        var recipe = EditRecipe()
        recipe.portrait.skin.smoothing = 0.2
        recipe.portrait.skin.autoBlemish = true
        recipe.makeup.lip = MakeupTint(colorID: "lip-coral", intensity: 0.3)
        recipe.people.groups[.female] = PortraitLayer(
            skinSmoothing: 0.5, features: [.eyeBrighten: 0.4],
            makeup: [.lip: MakeupTint(colorID: "lip-rose", intensity: 0.6)])
        recipe.people.groups[.male] = PortraitLayer(skinSmoothing: 0.1)
        recipe.people.individuals = [
            PersonRecord(
                id: id, anchor: PersonAnchor(x: 0.3, y: 0.5, width: 0.2), gender: .female,
                layer: PortraitLayer(
                    skinSmoothing: 0.9, face: [.width: -0.3], makeup: [.lip: MakeupTint(colorID: nil, intensity: 0)]))
        ]
        return recipe
    }

    func testLayersOverlayKeyByKeyAndUndeterminedGenderSkipsGroups() {
        let recipe = sample()
        let person = recipe.people.person(id)
        let resolved = PortraitResolver.resolve(recipe, person: person, gender: .female)
        XCTAssertEqual(resolved.portrait.skin.smoothing, 0.9, "개인이 그룹·전체를 이긴다")
        XCTAssertTrue(resolved.portrait.skin.autoBlemish, "아무 층도 덮지 않은 키는 전체 값")
        XCTAssertEqual(resolved.portrait.features.eyeBrighten, 0.4, "개인이 덮지 않은 키는 그룹 값")
        XCTAssertEqual(resolved.portrait.face.width, -0.3)
        XCTAssertNil(resolved.makeup.lip.colorID, "개인 층의 색 없음이 그룹의 색을 이긴다")
        XCTAssertEqual(resolved.makeup.lip.intensity, 0)
        let groupOnly = PortraitResolver.resolve(recipe, person: nil, gender: .female)
        XCTAssertEqual(groupOnly.portrait.skin.smoothing, 0.5)
        XCTAssertEqual(groupOnly.makeup.lip, MakeupTint(colorID: "lip-rose", intensity: 0.6))
        let undetermined = PortraitResolver.resolve(recipe, person: nil, gender: nil)
        XCTAssertEqual(undetermined.portrait, recipe.portrait)
        XCTAssertEqual(undetermined.makeup, recipe.makeup)
        let male = PortraitResolver.resolve(recipe, person: nil, gender: .male)
        XCTAssertEqual(male.portrait.skin.smoothing, 0.1)
        XCTAssertEqual(male.portrait.features.eyeBrighten, 0, "다른 그룹의 키는 받지 않는다")
        var noGroups = recipe
        noGroups.people.groups = [:]
        XCTAssertEqual(PortraitResolver.resolve(noGroups, person: nil, gender: .female).portrait, recipe.portrait)
    }

    func testScopeResolutionEffectiveGenderAndOverriddenKeys() {
        let recipe = sample()
        let person = recipe.people.person(id)
        XCTAssertEqual(
            PortraitResolver.effectiveGender(person: person, estimate: .male), .female, "수동 지정이 추정을 이긴다")
        let unassigned = PersonRecord(anchor: PersonAnchor(x: 0.5, y: 0.5, width: 0.1))
        XCTAssertEqual(PortraitResolver.effectiveGender(person: unassigned, estimate: .male), .male)
        XCTAssertNil(PortraitResolver.effectiveGender(person: nil, estimate: nil))
        XCTAssertEqual(PortraitResolver.resolve(recipe, scope: .all, estimate: .female).portrait, recipe.portrait)
        XCTAssertEqual(
            PortraitResolver.resolve(recipe, scope: .gender(.female), estimate: nil).portrait.skin.smoothing, 0.5)
        let scoped = PortraitResolver.resolve(recipe, scope: .person(id), estimate: .male)
        XCTAssertEqual(scoped.portrait.skin.smoothing, 0.9)
        XCTAssertEqual(scoped.portrait.features.eyeBrighten, 0.4, "기록의 수동 성별(여성)로 그룹을 고른다")
        XCTAssertEqual(
            PortraitResolver.resolve(recipe, scope: .person(PersonID()), estimate: nil).portrait, recipe.portrait,
            "모르는 사람은 전체 값")
        XCTAssertEqual(PortraitResolver.overriddenKeys(recipe, scope: .all), [])
        XCTAssertEqual(PortraitResolver.overriddenKeys(recipe, scope: .gender(.male)), [.skinSmoothing])
        XCTAssertEqual(
            PortraitResolver.overriddenKeys(recipe, scope: .person(id)),
            [.skinSmoothing, .faceShape(.width), .makeupPart(.lip)])
        XCTAssertEqual(PortraitResolver.overriddenKeys(recipe, scope: .person(PersonID())), [])
        XCTAssertNil(PortraitResolver.layer(recipe, scope: .all))
        XCTAssertEqual(PortraitResolver.layer(recipe, scope: .gender(.male)), PortraitLayer(skinSmoothing: 0.1))
        var withoutMale = recipe
        withoutMale.people.groups[.male] = nil
        XCTAssertEqual(PortraitResolver.layer(withoutMale, scope: .gender(.male)), PortraitLayer(), "없는 그룹은 빈 층")
    }
}
