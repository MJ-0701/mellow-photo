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

    /// 룩 이름은 메이크업 부위를 덮어쓴 가장 위 층의 것이다.
    /// 부위를 안 건드린 층은 아래 층의 룩을 상속하고, 부위만 바꾼 층은 룩 이름을 지운다.
    func testLookIDComesFromTheTopLayerThatOverridesMakeup() {
        var recipe = EditRecipe()
        recipe.makeup.lookID = "daily"
        recipe.makeup.lip = MakeupTint(colorID: "lip-rose", intensity: 0.5)
        recipe.people.groups[.female] = PortraitLayer(skinSmoothing: 0.4)
        XCTAssertEqual(
            PortraitResolver.resolve(recipe, person: nil, gender: .female).makeup.lookID, "daily",
            "메이크업을 안 건드린 그룹은 전체의 룩을 상속")
        recipe.people.groups[.female] = PortraitLayer(makeup: [.lip: MakeupTint(colorID: nil, intensity: 0.9)])
        XCTAssertNil(
            PortraitResolver.resolve(recipe, person: nil, gender: .female).makeup.lookID,
            "부위만 바꾼 그룹은 룩 이름을 지운다")
        recipe.people.groups[.female] = PortraitLayer(
            makeup: [.lip: MakeupTint(colorID: "lip-coral", intensity: 0.4)], makeupLookID: "party")
        XCTAssertEqual(PortraitResolver.resolve(recipe, person: nil, gender: .female).makeup.lookID, "party")
    }

    func testScopeAllowsSideChestOnlyInFemaleGroupAndPeople() {
        let scopes: [PortraitScope] = [.all, .gender(.male), .gender(.female), .person(PersonID())]
        XCTAssertFalse(PortraitScope.all.allows(.bodyShape(.sideChest)))
        XCTAssertFalse(PortraitScope.gender(.male).allows(.bodyShape(.sideChest)))
        XCTAssertTrue(PortraitScope.gender(.female).allows(.bodyShape(.sideChest)))
        XCTAssertTrue(PortraitScope.person(PersonID()).allows(.bodyShape(.sideChest)))
        for scope in scopes {
            XCTAssertTrue(scope.allows(.bodyShape(.waist)), "\(scope)")
            XCTAssertTrue(scope.allows(.faceShape(.doubleChin)), "\(scope)")
        }
    }

    func testBodyResolvesAllGroupPersonByKey() {
        var recipe = EditRecipe()
        recipe.body.waist = -0.2
        recipe.body.arms = -0.1
        recipe.people.groups[.female] = PortraitLayer(body: [.waist: -0.5])
        let record = PersonRecord(
            anchor: PersonAnchor(x: 0.5, y: 0.5, width: 0.2), layer: PortraitLayer(body: [.arms: -0.8]))
        recipe.people.individuals = [record]
        let female = PortraitResolver.resolve(recipe, person: record, gender: .female).body
        XCTAssertEqual(female.waist, -0.5, "그룹 층이 전체 층을 덮는다")
        XCTAssertEqual(female.arms, -0.8, "개인 층이 전체 층을 덮는다")
        let undetermined = PortraitResolver.resolve(recipe, person: record, gender: nil).body
        XCTAssertEqual(undetermined.waist, -0.2, "성별 미지정은 그룹 층을 건너뛴다")
        XCTAssertEqual(undetermined.arms, -0.8)
        XCTAssertEqual(PortraitResolver.resolve(recipe, scope: .all, estimate: nil).body, recipe.body)
    }

    func testSideChestIgnoredInAllLayerAndMaleGroup() {
        var recipe = EditRecipe()
        recipe.body.sideChest = 0.9
        recipe.people.groups[.male] = PortraitLayer(body: [.sideChest: 0.7])
        recipe.people.groups[.female] = PortraitLayer(body: [.sideChest: 0.4])
        let man = PersonRecord(
            anchor: PersonAnchor(x: 0.5, y: 0.5, width: 0.2), gender: .male,
            layer: PortraitLayer(body: [.sideChest: 0.6]))
        recipe.people.individuals = [man]
        XCTAssertEqual(PortraitResolver.resolve(recipe, person: nil, gender: .male).body.sideChest, 0)
        XCTAssertEqual(PortraitResolver.resolve(recipe, person: nil, gender: .female).body.sideChest, 0.4)
        XCTAssertEqual(PortraitResolver.resolve(recipe, person: nil, gender: nil).body.sideChest, 0)
        XCTAssertEqual(PortraitResolver.resolve(recipe, person: man, gender: .male).body.sideChest, 0.6, "개인 층은 늘 허용")
        XCTAssertEqual(PortraitResolver.resolve(recipe, scope: .all, estimate: nil).body.sideChest, 0)
        XCTAssertEqual(PortraitResolver.allLayerBody(recipe).sideChest, 0)
        XCTAssertEqual(recipe.body.sideChest, 0.9, "전체 층 값은 지우지 않고 무시만 한다")
        XCTAssertEqual(recipe.people.groups[.male]?.body[.sideChest], 0.7, "남성 그룹 값도 보존한다")
    }

    func testDependsOnBodySeesLayers() {
        var recipe = EditRecipe()
        XCTAssertFalse(recipe.dependsOnBody)
        recipe.people.individuals = [
            PersonRecord(anchor: PersonAnchor(x: 0.5, y: 0.5, width: 0.2), layer: PortraitLayer(body: [.waist: -0.3]))
        ]
        XCTAssertTrue(recipe.dependsOnBody, "개인 층 체형도 몸이 필요하다")
        recipe = EditRecipe()
        recipe.people.groups[.female] = PortraitLayer(body: [.arms: -0.2])
        XCTAssertTrue(recipe.dependsOnBody, "그룹 층 체형도 몸이 필요하다")
        recipe = EditRecipe()
        recipe.body.sideChest = 0.5
        XCTAssertFalse(recipe.dependsOnBody, "전체 층 부유방은 렌더가 무시한다")
    }
}
