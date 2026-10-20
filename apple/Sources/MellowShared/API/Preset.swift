import Foundation

public struct PresetValues: Codable, Equatable, Sendable {
    public var color: ColorAdjustments
    public var portrait: PortraitAdjustments
    public var detail: DetailAdjustments
    public var background: BackgroundAdjustments
    public var bodySkin: BodySkinAdjustments
    public var body: BodyShapeAdjustments
    public var makeup: MakeupAdjustments
    public var effects: EffectAdjustments
    /// 성별 그룹 층만 담는다.
    /// 개인 기록은 사진 사이에서 같은 사람을 알아볼 수 없어 나르지 않는다.
    public var people: PeopleAdjustments

    public init(
        color: ColorAdjustments = .init(), portrait: PortraitAdjustments = .init(), detail: DetailAdjustments = .init(),
        background: BackgroundAdjustments = .init(), bodySkin: BodySkinAdjustments = .init(),
        body: BodyShapeAdjustments = .init(), makeup: MakeupAdjustments = .init(),
        effects: EffectAdjustments = .init(), people: PeopleAdjustments = .init()
    ) {
        self.color = color
        self.portrait = portrait
        self.detail = detail
        self.background = background
        self.bodySkin = bodySkin
        self.body = body
        self.makeup = makeup
        self.effects = effects
        self.people = PeopleAdjustments(groups: people.groups)
    }

    /// 레시피의 슬라이더 그룹. 룩·기하·수동 편집은 담지 않는다.
    /// 사람별 값은 성별 그룹 층만 담는다.
    public init(of recipe: EditRecipe) {
        self.init(
            color: recipe.color, portrait: recipe.portrait, detail: recipe.detail, background: recipe.background,
            bodySkin: recipe.bodySkin, body: recipe.body, makeup: recipe.makeup, effects: recipe.effects,
            people: PeopleAdjustments(groups: recipe.people.groups))
    }

    private enum CodingKeys: String, CodingKey {
        case color
        case portrait
        case detail
        case background
        case bodySkin
        case body
        case makeup
        case effects
        case people
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        color = try container.decodeIfPresent(ColorAdjustments.self, forKey: .color) ?? .init()
        portrait = try container.decodeIfPresent(PortraitAdjustments.self, forKey: .portrait) ?? .init()
        detail = try container.decodeIfPresent(DetailAdjustments.self, forKey: .detail) ?? .init()
        background = try container.decodeIfPresent(BackgroundAdjustments.self, forKey: .background) ?? .init()
        bodySkin = try container.decodeIfPresent(BodySkinAdjustments.self, forKey: .bodySkin) ?? .init()
        body = try container.decodeIfPresent(BodyShapeAdjustments.self, forKey: .body) ?? .init()
        makeup = try container.decodeIfPresent(MakeupAdjustments.self, forKey: .makeup) ?? .init()
        effects = try container.decodeIfPresent(EffectAdjustments.self, forKey: .effects) ?? .init()
        let decodedPeople = try container.decodeIfPresent(PeopleAdjustments.self, forKey: .people) ?? .init()
        // 파일에 개인 층이 와도 버린다.
        people = PeopleAdjustments(groups: decodedPeople.groups)
    }

    /// 사람별 값은 groups만 쓴다.
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(color, forKey: .color)
        try container.encode(portrait, forKey: .portrait)
        try container.encode(detail, forKey: .detail)
        try container.encode(background, forKey: .background)
        try container.encode(bodySkin, forKey: .bodySkin)
        try container.encode(body, forKey: .body)
        try container.encode(makeup, forKey: .makeup)
        try container.encode(effects, forKey: .effects)
        try container.encode(PeopleAdjustments(groups: people.groups), forKey: .people)
    }
}

public struct Preset: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID
    public var name: String
    public var values: PresetValues

    public init(id: UUID = UUID(), name: String, values: PresetValues) {
        self.id = id
        self.name = name
        self.values = values
    }
}

/// iPhone 출시본 값. Mac 앱이 쓰던 다른 값은 폐기했다.
public enum BuiltInPresets: Sendable {
    public static let natural = Preset(
        id: UUID(uuidString: "A0000000-0000-0000-0000-000000000001")!,
        name: "내추럴",
        values: PresetValues(
            color: ColorAdjustments(exposure: 0.1),
            portrait: PortraitAdjustments(skin: SkinAdjustments(smoothing: 0.2))))
    public static let cozy = Preset(
        id: UUID(uuidString: "A0000000-0000-0000-0000-000000000002")!,
        name: "포근한",
        values: PresetValues(
            color: ColorAdjustments(exposure: 0.15, saturation: 0.92, warmth: 0.25),
            portrait: PortraitAdjustments(skin: SkinAdjustments(smoothing: 0.3))))
    public static let clean = Preset(
        id: UUID(uuidString: "A0000000-0000-0000-0000-000000000003")!,
        name: "클린",
        values: PresetValues(color: ColorAdjustments(exposure: 0.2, contrast: 1.05, warmth: -0.1)))
    public static let all: [Preset] = [natural, cozy, clean]
}
