import Foundation

public struct PresetValues: Codable, Equatable, Sendable {
    public var color: ColorAdjustments
    public var portrait: PortraitAdjustments

    public init(color: ColorAdjustments = .init(), portrait: PortraitAdjustments = .init()) {
        self.color = color
        self.portrait = portrait
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
        values: PresetValues(color: ColorAdjustments(exposure: 0.1), portrait: PortraitAdjustments(skinSmoothing: 0.2)))
    public static let cozy = Preset(
        id: UUID(uuidString: "A0000000-0000-0000-0000-000000000002")!,
        name: "포근한",
        values: PresetValues(
            color: ColorAdjustments(exposure: 0.15, saturation: 0.92, warmth: 0.25),
            portrait: PortraitAdjustments(skinSmoothing: 0.3)))
    public static let clean = Preset(
        id: UUID(uuidString: "A0000000-0000-0000-0000-000000000003")!,
        name: "클린",
        values: PresetValues(color: ColorAdjustments(exposure: 0.2, contrast: 1.05, warmth: -0.1)))
    public static let all: [Preset] = [natural, cozy, clean]
}
