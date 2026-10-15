import Foundation

/// 피부 보정 강도 0…1과 자동 잡티 스위치.
public struct SkinAdjustments: Codable, Equatable, Sendable {
    public var smoothing: Double
    public var autoBlemish: Bool

    public init(smoothing: Double = 0, autoBlemish: Bool = false) {
        self.smoothing = smoothing
        self.autoBlemish = autoBlemish
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        smoothing = try container.decodeIfPresent(Double.self, forKey: .smoothing) ?? 0
        autoBlemish = try container.decodeIfPresent(Bool.self, forKey: .autoBlemish) ?? false
    }

    /// 렌더 결과를 바꾸는 값이 있는지.
    public var hasEffect: Bool { smoothing != 0 || autoBlemish }
    public var numericValues: [Double] { [smoothing] }
}
