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
    public var operations: [LocalEdit] = []

    public init(
        color: ColorAdjustments = .init(), portrait: PortraitAdjustments = .init(), detail: DetailAdjustments = .init(),
        look: LookSelection = .init(), geometry: GeometryAdjustments = .init(),
        background: BackgroundAdjustments = .init(), bodySkin: BodySkinAdjustments = .init(),
        body: BodyShapeAdjustments = .init(), makeup: MakeupAdjustments = .init(), operations: [LocalEdit] = []
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
        operations = try container.decodeIfPresent([LocalEdit].self, forKey: .operations) ?? []
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
    public var dependsOnFaces: Bool { portrait.dependsOnFaces || makeup.hasEffect }
    /// 배경 흐림과 몸 피부는 인물 마스크가 필요하다.
    public var dependsOnPerson: Bool { background.hasEffect || bodySkin.hasEffect }
    /// 체형은 관절점이 필요하다.
    public var dependsOnBody: Bool { body.hasEffect }
    public var isDefault: Bool { self == EditRecipe() }

    /// 렌더 전 검증용. 비유한수가 하나라도 있으면 false.
    public var allValuesFinite: Bool {
        let scalars = [color.exposure, color.contrast, color.saturation, color.warmth, look.intensity]
        let groups =
            portrait.numericValues + detail.numericValues + geometry.numericValues + background.numericValues
            + bodySkin.numericValues + body.numericValues + makeup.numericValues
        let locals = operations.flatMap(\.numericValues)
        return (scalars + groups + locals).allSatisfy(\.isFinite)
    }
}
