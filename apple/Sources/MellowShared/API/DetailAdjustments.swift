import Foundation

/// 하이라이트·그림자 −1…1, 선명도·비네팅 0…1.
public struct DetailAdjustments: Codable, Equatable, Sendable {
    public var highlights: Double = 0
    public var shadows: Double = 0
    public var sharpness: Double = 0
    public var vignette: Double = 0

    public init(highlights: Double = 0, shadows: Double = 0, sharpness: Double = 0, vignette: Double = 0) {
        self.highlights = highlights
        self.shadows = shadows
        self.sharpness = sharpness
        self.vignette = vignette
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        highlights = try container.decodeIfPresent(Double.self, forKey: .highlights) ?? 0
        shadows = try container.decodeIfPresent(Double.self, forKey: .shadows) ?? 0
        sharpness = try container.decodeIfPresent(Double.self, forKey: .sharpness) ?? 0
        vignette = try container.decodeIfPresent(Double.self, forKey: .vignette) ?? 0
    }

    public var isDefault: Bool { self == DetailAdjustments() }
    public var numericValues: [Double] { [highlights, shadows, sharpness, vignette] }
}
