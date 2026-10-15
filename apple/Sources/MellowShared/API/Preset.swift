import Foundation

public struct PresetValues: Codable, Equatable, Sendable {
    public var color: ColorAdjustments
    public var portrait: PortraitAdjustments
    public var detail: DetailAdjustments
    public var background: BackgroundAdjustments
    public var body: BodyShapeAdjustments
    public var makeup: MakeupAdjustments

    public init(
        color: ColorAdjustments = .init(), portrait: PortraitAdjustments = .init(), detail: DetailAdjustments = .init(),
        background: BackgroundAdjustments = .init(), body: BodyShapeAdjustments = .init(),
        makeup: MakeupAdjustments = .init()
    ) {
        self.color = color
        self.portrait = portrait
        self.detail = detail
        self.background = background
        self.body = body
        self.makeup = makeup
    }

    /// 레시피의 슬라이더 그룹. 룩·기하·수동 편집은 담지 않는다. 대상 얼굴은 호출자가 정한다.
    public init(of recipe: EditRecipe) {
        self.init(
            color: recipe.color, portrait: recipe.portrait, detail: recipe.detail, background: recipe.background,
            body: recipe.body, makeup: recipe.makeup)
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        color = try container.decodeIfPresent(ColorAdjustments.self, forKey: .color) ?? .init()
        portrait = try container.decodeIfPresent(PortraitAdjustments.self, forKey: .portrait) ?? .init()
        detail = try container.decodeIfPresent(DetailAdjustments.self, forKey: .detail) ?? .init()
        background = try container.decodeIfPresent(BackgroundAdjustments.self, forKey: .background) ?? .init()
        body = try container.decodeIfPresent(BodyShapeAdjustments.self, forKey: .body) ?? .init()
        makeup = try container.decodeIfPresent(MakeupAdjustments.self, forKey: .makeup) ?? .init()
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
