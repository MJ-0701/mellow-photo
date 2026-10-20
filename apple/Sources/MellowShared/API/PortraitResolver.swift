import Foundation

/// 편집·화면이 가리키는 층.
/// 값 타입이라 여기 둔다(Rendering은 Editing을 import할 수 없다).
public enum PortraitScope: Hashable, Sendable {
    case all
    case gender(Gender)
    case person(PersonID)
}

/// 전체 → 성별 그룹 → 개인 순서로 키 단위로 겹친 값을 만든다.
/// 렌더·편집·앱이 같은 함수를 쓴다.
public enum PortraitResolver {
    public struct Resolved: Equatable, Sendable {
        public var portrait: PortraitAdjustments
        public var makeup: MakeupAdjustments

        public init(portrait: PortraitAdjustments, makeup: MakeupAdjustments) {
            self.portrait = portrait
            self.makeup = makeup
        }
    }

    /// 전체 ⊕ groups[gender] ⊕ person?.layer.
    /// gender가 nil이면 그룹 층을 건너뛴다(미지정은 전체 값과 개인 값만 받는다).
    public static func resolve(_ recipe: EditRecipe, person: PersonRecord?, gender: Gender?) -> Resolved {
        var portrait = recipe.portrait
        var makeup = recipe.makeup
        if let gender, let group = recipe.people.groups[gender] {
            group.applied(to: &portrait, makeup: &makeup)
        }
        person?.layer.applied(to: &portrait, makeup: &makeup)
        return Resolved(portrait: portrait, makeup: makeup)
    }

    /// 화면용.
    /// .person은 기록의 수동 성별이 먼저이고 estimate가 그다음이다.
    /// 모르는 사람은 전체 값이다.
    public static func resolve(_ recipe: EditRecipe, scope: PortraitScope, estimate: Gender?) -> Resolved {
        switch scope {
        case .all:
            return Resolved(portrait: recipe.portrait, makeup: recipe.makeup)
        case .gender(let gender):
            return resolve(recipe, person: nil, gender: gender)
        case .person(let id):
            guard let person = recipe.people.person(id) else {
                return Resolved(portrait: recipe.portrait, makeup: recipe.makeup)
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
