import Foundation

/// 필터(룩) 선택. id가 nil이면 없음. intensity는 원본과 룩 결과의 혼합 비율.
public struct LookSelection: Codable, Equatable, Sendable {
    public var id: String?
    public var intensity: Double

    public init(id: String? = nil, intensity: Double = 1) {
        self.id = id
        self.intensity = intensity
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(String.self, forKey: .id)
        intensity = try container.decodeIfPresent(Double.self, forKey: .intensity) ?? 1
    }

    public var isDefault: Bool { self == LookSelection() }
}
