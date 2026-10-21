import Foundation

/// 사진 한 장의 보정 레시피. shared/recipe-schema/edit-recipe.v2.schema.json과 같은 형식.
public struct EditRecipe: Codable, Equatable, Sendable {
    public static let currentSchemaVersion = 2

    public var color = ColorAdjustments()
    public var portrait = PortraitAdjustments()
    public var detail = DetailAdjustments()
    public var look = LookSelection()
    public var geometry = GeometryAdjustments()
    public var background = BackgroundAdjustments()
    public var bodySkin = BodySkinAdjustments()
    public var body = BodyShapeAdjustments()
    public var makeup = MakeupAdjustments()
    public var effects = EffectAdjustments()
    /// 성별 그룹 층과 개인 기록.
    /// portrait·makeup이 전체 층이다.
    public var people = PeopleAdjustments()
    public var operations: [LocalEdit] = []

    public init(
        color: ColorAdjustments = .init(), portrait: PortraitAdjustments = .init(), detail: DetailAdjustments = .init(),
        look: LookSelection = .init(), geometry: GeometryAdjustments = .init(),
        background: BackgroundAdjustments = .init(), bodySkin: BodySkinAdjustments = .init(),
        body: BodyShapeAdjustments = .init(), makeup: MakeupAdjustments = .init(), effects: EffectAdjustments = .init(),
        people: PeopleAdjustments = .init(), operations: [LocalEdit] = []
    ) {
        self.color = color
        self.portrait = portrait
        self.detail = detail
        self.look = look
        self.geometry = geometry
        self.background = background
        self.bodySkin = bodySkin
        self.body = body
        self.makeup = makeup
        self.effects = effects
        self.people = people
        self.operations = operations
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case color
        case portrait
        case detail
        case look
        case geometry
        case background
        case bodySkin
        case body
        case makeup
        case effects
        case people
        case operations
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        color = try container.decodeIfPresent(ColorAdjustments.self, forKey: .color) ?? .init()
        portrait = try container.decodeIfPresent(PortraitAdjustments.self, forKey: .portrait) ?? .init()
        detail = try container.decodeIfPresent(DetailAdjustments.self, forKey: .detail) ?? .init()
        look = try container.decodeIfPresent(LookSelection.self, forKey: .look) ?? .init()
        geometry = try container.decodeIfPresent(GeometryAdjustments.self, forKey: .geometry) ?? .init()
        background = try container.decodeIfPresent(BackgroundAdjustments.self, forKey: .background) ?? .init()
        bodySkin = try container.decodeIfPresent(BodySkinAdjustments.self, forKey: .bodySkin) ?? .init()
        body = try container.decodeIfPresent(BodyShapeAdjustments.self, forKey: .body) ?? .init()
        makeup = try container.decodeIfPresent(MakeupAdjustments.self, forKey: .makeup) ?? .init()
        effects = try container.decodeIfPresent(EffectAdjustments.self, forKey: .effects) ?? .init()
        people = try container.decodeIfPresent(PeopleAdjustments.self, forKey: .people) ?? .init()
        operations = try container.decodeIfPresent([LocalEdit].self, forKey: .operations) ?? []
        // B0~G의 targetFace는 people이 없을 때만 개인 층으로 옮긴다.
        let legacyTarget = try container.decodeIfPresent(LegacyPortraitProbe.self, forKey: .portrait)?.targetFace
        if let legacyTarget, people.individuals.isEmpty {
            migrateLegacyTargetFace(legacyTarget)
        }
    }

    /// portrait 컨테이너의 옛 targetFace만 읽는다.
    private struct LegacyPortraitProbe: Decodable {
        var targetFace: Int?
    }

    /// B0~G의 portrait.targetFace("이 값을 i번 얼굴에만")를 H의 모양으로 옮긴다.
    /// 전체 층 값 전부를 i번 사람의 개인 층(legacyIndex)으로 옮기고 전체 층은 비운다.
    /// 렌더 결과는 같다.
    /// id는 인덱스에서 결정적이라 같은 파일을 두 번 읽어도 같다.
    /// 옮길 값이 없으면 기록을 만들지 않는다.
    /// 음수·거대한 인덱스(손상 파일)는 범위의 마지막 값으로 모은다.
    /// 어느 얼굴과도 짝이 되지 않아 옛 결과(빈 대상)와 같다.
    /// 사람 기록이 이미 있으면 아무것도 하지 않는다(디코더와 같은 조건, 기존 기록을 덮어쓰지 않는다).
    public mutating func migrateLegacyTargetFace(_ index: Int) {
        guard people.individuals.isEmpty else { return }
        let layer = PortraitLayer.difference(portrait: portrait, makeup: makeup)
        portrait = PortraitAdjustments()
        makeup = MakeupAdjustments()
        guard !layer.isEmpty else { return }
        let safe = PersonID.legacyIndexRange.contains(index) ? index : PersonID.legacyIndexRange.upperBound
        people.individuals = [PersonRecord(id: .legacy(index: safe), legacyIndex: safe, layer: layer)]
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(Self.currentSchemaVersion, forKey: .schemaVersion)
        try container.encode(color, forKey: .color)
        try container.encode(portrait, forKey: .portrait)
        try container.encode(detail, forKey: .detail)
        try container.encode(look, forKey: .look)
        try container.encode(geometry, forKey: .geometry)
        try container.encode(background, forKey: .background)
        try container.encode(bodySkin, forKey: .bodySkin)
        try container.encode(body, forKey: .body)
        try container.encode(makeup, forKey: .makeup)
        try container.encode(effects, forKey: .effects)
        try container.encode(people, forKey: .people)
        try container.encode(operations, forKey: .operations)
    }

    public var spots: [RetouchSpot] {
        operations.compactMap { edit in
            if case .spot(let spot) = edit { return spot }
            return nil
        }
    }

    public var warps: [WarpStroke] {
        operations.compactMap { edit in
            if case .warp(let stroke) = edit { return stroke }
            return nil
        }
    }

    public var hasLocalEdits: Bool { !operations.isEmpty }
    /// 피부·얼굴형·눈·입·메이크업 중 하나라도 렌더를 바꾸면 얼굴 분석이 필요하다.
    /// 성별 그룹·개인 층의 값도 같다.
    public var dependsOnFaces: Bool { portrait.dependsOnFaces || makeup.hasEffect || people.hasEffect }
    /// 배경 흐림과 몸 피부는 인물 마스크가 필요하다.
    public var dependsOnPerson: Bool { background.hasEffect || bodySkin.hasEffect }
    /// 체형은 관절점이 필요하다.
    /// 어느 층이든 렌더에 쓰이는 체형 값이 있는지.
    /// 전체 층의 허용되지 않는 키(부유방)는 렌더가 무시하므로 세지 않는다.
    /// 타입 검사 시간을 줄이려 한 줄에 한 묶음씩 따진다.
    public var dependsOnBody: Bool {
        let allLayer = PortraitResolver.allLayerBody(self).hasEffect
        let groups = people.groups.values.contains { $0.body.values.contains { $0 != 0 } }
        let individuals = people.individuals.contains { $0.layer.body.values.contains { $0 != 0 } }
        return allLayer || groups || individuals
    }
    public var isDefault: Bool { self == EditRecipe() }

    /// 렌더 전 검증용. 비유한수가 하나라도 있으면 false.
    public var allValuesFinite: Bool {
        let scalars = [color.exposure, color.contrast, color.saturation, color.warmth, look.intensity]
        // 타입 검사 시간을 줄이려 묶음마다 따로 붙인다.
        var groups: [Double] = portrait.numericValues
        groups += detail.numericValues
        groups += geometry.numericValues
        groups += background.numericValues
        groups += bodySkin.numericValues
        groups += body.numericValues
        groups += makeup.numericValues
        groups += effects.numericValues
        groups += people.numericValues
        let locals = operations.flatMap(\.numericValues)
        return (scalars + groups + locals).allSatisfy(\.isFinite)
    }
}
