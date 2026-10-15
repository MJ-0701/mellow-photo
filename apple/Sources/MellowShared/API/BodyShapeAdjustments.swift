import Foundation

/// 체형 슬라이더 이름. 레시피 JSON 키와 같다.
public enum BodyShapeKey: String, CaseIterable, Codable, Sendable {
    case legLength
    case waist
    case overall
    case arms
    case thighs
    case shoulders
    case neck
}

/// 체형 −1…1(가운데 0). legLength만 0…1. 렌더는 E 단계.
public struct BodyShapeAdjustments: Codable, Equatable, Sendable {
    public var legLength: Double
    public var waist: Double
    public var overall: Double
    public var arms: Double
    public var thighs: Double
    public var shoulders: Double
    public var neck: Double

    public init(
        legLength: Double = 0, waist: Double = 0, overall: Double = 0, arms: Double = 0, thighs: Double = 0,
        shoulders: Double = 0, neck: Double = 0
    ) {
        self.legLength = legLength
        self.waist = waist
        self.overall = overall
        self.arms = arms
        self.thighs = thighs
        self.shoulders = shoulders
        self.neck = neck
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        legLength = try container.decodeIfPresent(Double.self, forKey: .legLength) ?? 0
        waist = try container.decodeIfPresent(Double.self, forKey: .waist) ?? 0
        overall = try container.decodeIfPresent(Double.self, forKey: .overall) ?? 0
        arms = try container.decodeIfPresent(Double.self, forKey: .arms) ?? 0
        thighs = try container.decodeIfPresent(Double.self, forKey: .thighs) ?? 0
        shoulders = try container.decodeIfPresent(Double.self, forKey: .shoulders) ?? 0
        neck = try container.decodeIfPresent(Double.self, forKey: .neck) ?? 0
    }

    public subscript(key: BodyShapeKey) -> Double {
        get {
            switch key {
            case .legLength: return legLength
            case .waist: return waist
            case .overall: return overall
            case .arms: return arms
            case .thighs: return thighs
            case .shoulders: return shoulders
            case .neck: return neck
            }
        }
        set {
            switch key {
            case .legLength: legLength = newValue
            case .waist: waist = newValue
            case .overall: overall = newValue
            case .arms: arms = newValue
            case .thighs: thighs = newValue
            case .shoulders: shoulders = newValue
            case .neck: neck = newValue
            }
        }
    }

    public var numericValues: [Double] { BodyShapeKey.allCases.map { self[$0] } }
    public var hasEffect: Bool { numericValues.contains { $0 != 0 } }
}
