import Foundation

/// 메이크업 부위. lip·blush·eyeshadow만 색을 고른다.
public enum MakeupPart: String, CaseIterable, Codable, Sendable {
    case lip
    case blush
    case eyeshadow
    case brow
    case contour

    public var hasColor: Bool { self == .lip || self == .blush || self == .eyeshadow }
}

/// 색을 고르는 부위. colorID는 shared/makeup/makeup.v1.json의 색 id이고 nil이면 고르지 않은 상태.
public struct MakeupTint: Codable, Equatable, Sendable {
    public var colorID: String?
    public var intensity: Double

    public init(colorID: String? = nil, intensity: Double = 0) {
        self.colorID = colorID
        self.intensity = intensity
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        colorID = try container.decodeIfPresent(String.self, forKey: .colorID)
        intensity = try container.decodeIfPresent(Double.self, forKey: .intensity) ?? 0
    }
}

/// 색 없이 강도만 있는 부위(눈썹·쉐딩).
public struct MakeupStrength: Codable, Equatable, Sendable {
    public var intensity: Double

    public init(intensity: Double = 0) {
        self.intensity = intensity
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        intensity = try container.decodeIfPresent(Double.self, forKey: .intensity) ?? 0
    }
}

/// 메이크업 레시피. lookID는 마지막으로 적용한 룩이다. 렌더와 룩 규칙은 F 단계.
public struct MakeupAdjustments: Codable, Equatable, Sendable {
    public var lookID: String?
    public var lip: MakeupTint
    public var blush: MakeupTint
    public var eyeshadow: MakeupTint
    public var brow: MakeupStrength
    public var contour: MakeupStrength

    public init(
        lookID: String? = nil, lip: MakeupTint = .init(), blush: MakeupTint = .init(),
        eyeshadow: MakeupTint = .init(), brow: MakeupStrength = .init(), contour: MakeupStrength = .init()
    ) {
        self.lookID = lookID
        self.lip = lip
        self.blush = blush
        self.eyeshadow = eyeshadow
        self.brow = brow
        self.contour = contour
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        lookID = try container.decodeIfPresent(String.self, forKey: .lookID)
        lip = try container.decodeIfPresent(MakeupTint.self, forKey: .lip) ?? .init()
        blush = try container.decodeIfPresent(MakeupTint.self, forKey: .blush) ?? .init()
        eyeshadow = try container.decodeIfPresent(MakeupTint.self, forKey: .eyeshadow) ?? .init()
        brow = try container.decodeIfPresent(MakeupStrength.self, forKey: .brow) ?? .init()
        contour = try container.decodeIfPresent(MakeupStrength.self, forKey: .contour) ?? .init()
    }

    public func intensity(of part: MakeupPart) -> Double {
        switch part {
        case .lip: return lip.intensity
        case .blush: return blush.intensity
        case .eyeshadow: return eyeshadow.intensity
        case .brow: return brow.intensity
        case .contour: return contour.intensity
        }
    }

    /// MakeupPart.allCases 순서의 강도.
    public var numericValues: [Double] { MakeupPart.allCases.map { intensity(of: $0) } }
    /// 룩 이름이나 색만 있고 강도가 모두 0이면 렌더가 바뀌지 않는다.
    public var hasEffect: Bool { numericValues.contains { $0 != 0 } }
}
