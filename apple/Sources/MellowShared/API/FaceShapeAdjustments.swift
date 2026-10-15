import Foundation

/// 얼굴형 슬라이더 이름. 레시피 JSON 키와 같다.
public enum FaceShapeKey: String, CaseIterable, Codable, Sendable {
    case width
    case jaw
    case cheekbone
    case eyeSize
    case eyeDistance
    case noseWidth
    case mouthSize
    case smile
    case forehead
    case chinLength
}

/// 얼굴형 −1…1(가운데 0). smile만 0…1. width가 음수면 좁게.
public struct FaceShapeAdjustments: Codable, Equatable, Sendable {
    public var width: Double
    public var jaw: Double
    public var cheekbone: Double
    public var eyeSize: Double
    public var eyeDistance: Double
    public var noseWidth: Double
    public var mouthSize: Double
    public var smile: Double
    public var forehead: Double
    public var chinLength: Double

    public init(
        width: Double = 0, jaw: Double = 0, cheekbone: Double = 0, eyeSize: Double = 0, eyeDistance: Double = 0,
        noseWidth: Double = 0, mouthSize: Double = 0, smile: Double = 0, forehead: Double = 0, chinLength: Double = 0
    ) {
        self.width = width
        self.jaw = jaw
        self.cheekbone = cheekbone
        self.eyeSize = eyeSize
        self.eyeDistance = eyeDistance
        self.noseWidth = noseWidth
        self.mouthSize = mouthSize
        self.smile = smile
        self.forehead = forehead
        self.chinLength = chinLength
    }

    /// B0까지의 faceSlim(0…1, 클수록 좁게)을 width로 옮긴다. 0은 −0이 아니라 0이다.
    public init(legacyFaceSlim slim: Double) {
        self.init(width: slim == 0 ? 0 : -slim)
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        width = try container.decodeIfPresent(Double.self, forKey: .width) ?? 0
        jaw = try container.decodeIfPresent(Double.self, forKey: .jaw) ?? 0
        cheekbone = try container.decodeIfPresent(Double.self, forKey: .cheekbone) ?? 0
        eyeSize = try container.decodeIfPresent(Double.self, forKey: .eyeSize) ?? 0
        eyeDistance = try container.decodeIfPresent(Double.self, forKey: .eyeDistance) ?? 0
        noseWidth = try container.decodeIfPresent(Double.self, forKey: .noseWidth) ?? 0
        mouthSize = try container.decodeIfPresent(Double.self, forKey: .mouthSize) ?? 0
        smile = try container.decodeIfPresent(Double.self, forKey: .smile) ?? 0
        forehead = try container.decodeIfPresent(Double.self, forKey: .forehead) ?? 0
        chinLength = try container.decodeIfPresent(Double.self, forKey: .chinLength) ?? 0
    }

    public subscript(key: FaceShapeKey) -> Double {
        get {
            switch key {
            case .width: return width
            case .jaw: return jaw
            case .cheekbone: return cheekbone
            case .eyeSize: return eyeSize
            case .eyeDistance: return eyeDistance
            case .noseWidth: return noseWidth
            case .mouthSize: return mouthSize
            case .smile: return smile
            case .forehead: return forehead
            case .chinLength: return chinLength
            }
        }
        set {
            switch key {
            case .width: width = newValue
            case .jaw: jaw = newValue
            case .cheekbone: cheekbone = newValue
            case .eyeSize: eyeSize = newValue
            case .eyeDistance: eyeDistance = newValue
            case .noseWidth: noseWidth = newValue
            case .mouthSize: mouthSize = newValue
            case .smile: smile = newValue
            case .forehead: forehead = newValue
            case .chinLength: chinLength = newValue
            }
        }
    }

    /// FaceShapeKey.allCases 순서.
    public var numericValues: [Double] { FaceShapeKey.allCases.map { self[$0] } }
    public var hasEffect: Bool { numericValues.contains { $0 != 0 } }
}
