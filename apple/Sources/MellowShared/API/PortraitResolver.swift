import Foundation

/// 편집·화면이 가리키는 층.
/// 값 타입이라 여기 둔다(Rendering은 Editing을 import할 수 없다).
public enum PortraitScope: Hashable, Sendable {
    case all
    case gender(Gender)
    case person(PersonID)
}

extension PortraitScope {
    /// 이 층에 그 키를 둘 수 있는지.
    /// 편집·해석·화면이 같은 답을 쓴다.
    /// 부유방은 여성 그룹과 개인 층에만 둔다.
    public func allows(_ key: PortraitKey) -> Bool {
        guard key == .bodyShape(.sideChest) else { return true }
        switch self {
        case .all, .gender(.male): return false
        case .gender(.female), .person: return true
        }
    }
}

/// 전체 → 성별 그룹 → 개인 순서로 키 단위로 겹친 값을 만든다.
/// 렌더·편집·앱이 같은 함수를 쓴다.
public enum PortraitResolver {
    public struct Resolved: Equatable, Sendable {
        public var portrait: PortraitAdjustments
        public var makeup: MakeupAdjustments
        public var body: BodyShapeAdjustments

        public init(
            portrait: PortraitAdjustments, makeup: MakeupAdjustments,
            body: BodyShapeAdjustments = BodyShapeAdjustments()
        ) {
            self.portrait = portrait
            self.makeup = makeup
            self.body = body
        }
    }

    /// 전체 ⊕ groups[gender] ⊕ person?.layer.
    /// gender가 nil이면 그룹 층을 건너뛴다(미지정은 전체 값과 개인 값만 받는다).
    /// 체형은 허용되지 않는 키(전체 층·남성 그룹의 부유방)를 건너뛴다.
    /// 개인 층은 모두 덮는다.
    public static func resolve(_ recipe: EditRecipe, person: PersonRecord?, gender: Gender?) -> Resolved {
        var portrait = recipe.portrait
        var makeup = recipe.makeup
        var body = allLayerBody(recipe)
        if let gender, let group = recipe.people.groups[gender] {
            let scope = PortraitScope.gender(gender)
            var allowed = group
            allowed.body = group.body.filter { scope.allows(.bodyShape($0.key)) }
            allowed.applied(to: &portrait, makeup: &makeup, body: &body)
        }
        person?.layer.applied(to: &portrait, makeup: &makeup, body: &body)
        return Resolved(portrait: portrait, makeup: makeup, body: body)
    }

    /// 전체 층 체형에서 전체 층이 허용하지 않는 키를 0으로 둔 값.
    /// 짝 없는 몸과 .all 해석이 쓴다.
    /// 레시피의 값은 지우지 않는다.
    public static func allLayerBody(_ recipe: EditRecipe) -> BodyShapeAdjustments {
        var body = recipe.body
        for key in BodyShapeKey.allCases where !PortraitScope.all.allows(.bodyShape(key)) {
            body[key] = 0
        }
        return body
    }

    /// 화면용.
    /// .person은 기록의 수동 성별이 먼저이고 estimate가 그다음이다.
    /// 모르는 사람은 전체 값이다.
    public static func resolve(_ recipe: EditRecipe, scope: PortraitScope, estimate: Gender?) -> Resolved {
        switch scope {
        case .all:
            return Resolved(portrait: recipe.portrait, makeup: recipe.makeup, body: allLayerBody(recipe))
        case .gender(let gender):
            return resolve(recipe, person: nil, gender: gender)
        case .person(let id):
            guard let person = recipe.people.person(id) else {
                return Resolved(portrait: recipe.portrait, makeup: recipe.makeup, body: allLayerBody(recipe))
            }
            return resolve(recipe, person: person, gender: effectiveGender(person: person, estimate: estimate))
        }
    }

    /// 수동 지정이 있으면 그것, 없으면 추정값.
    public static func effectiveGender(person: PersonRecord?, estimate: Gender?) -> Gender? {
        person?.gender ?? estimate
    }

    /// 그 scope의 층.
    /// .all은 nil, 없는 그룹은 빈 층, 모르는 사람은 nil이다.
    public static func layer(_ recipe: EditRecipe, scope: PortraitScope) -> PortraitLayer? {
        switch scope {
        case .all: return nil
        case .gender(let gender): return recipe.people.groups[gender] ?? PortraitLayer()
        case .person(let id): return recipe.people.person(id)?.layer
        }
    }

    /// 그 층에서 덮어쓴 키.
    /// .all은 빈 집합이다.
    public static func overriddenKeys(_ recipe: EditRecipe, scope: PortraitScope) -> Set<PortraitKey> {
        layer(recipe, scope: scope)?.overriddenKeys ?? []
    }
}
