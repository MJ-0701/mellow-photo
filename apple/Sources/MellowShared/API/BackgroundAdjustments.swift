import Foundation

/// 배경 흐림 0…1. 렌더는 D 단계(인물 마스크).
public struct BackgroundAdjustments: Codable, Equatable, Sendable {
    public var blur: Double

    public init(blur: Double = 0) {
        self.blur = blur
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        blur = try container.decodeIfPresent(Double.self, forKey: .blur) ?? 0
    }

    public var numericValues: [Double] { [blur] }
    public var hasEffect: Bool { blur != 0 }
}
