import Foundation

/// 사진 한 장의 보정 레시피. shared/recipe-schema/edit-recipe.v2.schema.json과 같은 형식.
public struct EditRecipe: Codable, Equatable, Sendable {
    public static let currentSchemaVersion = 2

    public var color = ColorAdjustments()
    public var portrait = PortraitAdjustments()
    public var detail = DetailAdjustments()
    public var look = LookSelection()
    public var geometry = GeometryAdjustments()
    public var operations: [LocalEdit] = []

    public init(
        color: ColorAdjustments = .init(), portrait: PortraitAdjustments = .init(), detail: DetailAdjustments = .init(),
        look: LookSelection = .init(), geometry: GeometryAdjustments = .init(), operations: [LocalEdit] = []
    ) {
        self.color = color
        self.portrait = portrait
        self.detail = detail
        self.look = look
        self.geometry = geometry
        self.operations = operations
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case color
        case portrait
        case detail
        case look
        case geometry
        case operations
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        color = try container.decodeIfPresent(ColorAdjustments.self, forKey: .color) ?? .init()
        portrait = try container.decodeIfPresent(PortraitAdjustments.self, forKey: .portrait) ?? .init()
        detail = try container.decodeIfPresent(DetailAdjustments.self, forKey: .detail) ?? .init()
        look = try container.decodeIfPresent(LookSelection.self, forKey: .look) ?? .init()
        geometry = try container.decodeIfPresent(GeometryAdjustments.self, forKey: .geometry) ?? .init()
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
    public var dependsOnFaces: Bool { portrait.dependsOnFaces }
    public var isDefault: Bool { self == EditRecipe() }

    /// 렌더 전 검증용. 비유한수가 하나라도 있으면 false.
    public var allValuesFinite: Bool {
        let scalars = [
            color.exposure, color.contrast, color.saturation, color.warmth, portrait.skinSmoothing, portrait.faceSlim,
            look.intensity,
        ]
        let locals = operations.flatMap(\.numericValues)
        return (scalars + detail.numericValues + geometry.numericValues + locals).allSatisfy(\.isFinite)
    }
}
