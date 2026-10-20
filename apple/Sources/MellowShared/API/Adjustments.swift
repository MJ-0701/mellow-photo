import Foundation

public struct ColorAdjustments: Codable, Equatable, Sendable {
    public var exposure: Double = 0
    public var contrast: Double = 1
    public var saturation: Double = 1
    public var warmth: Double = 0

    public init(exposure: Double = 0, contrast: Double = 1, saturation: Double = 1, warmth: Double = 0) {
        self.exposure = exposure
        self.contrast = contrast
        self.saturation = saturation
        self.warmth = warmth
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        exposure = try container.decodeIfPresent(Double.self, forKey: .exposure) ?? 0
        contrast = try container.decodeIfPresent(Double.self, forKey: .contrast) ?? 1
        saturation = try container.decodeIfPresent(Double.self, forKey: .saturation) ?? 1
        warmth = try container.decodeIfPresent(Double.self, forKey: .warmth) ?? 0
    }

    public var isDefault: Bool { self == ColorAdjustments() }
}

/// 얼굴에 의존하는 보정. 옛 키 skinSmoothing·faceSlim은 읽기만 하고 쓰지 않는다.
/// 옛 키 targetFace는 EditRecipe가 읽어 개인 층으로 옮긴다.
public struct PortraitAdjustments: Codable, Equatable, Sendable {
    public var skin: SkinAdjustments
    public var face: FaceShapeAdjustments
    public var features: FeatureAdjustments

    public init(
        skin: SkinAdjustments = .init(), face: FaceShapeAdjustments = .init(), features: FeatureAdjustments = .init()
    ) {
        self.skin = skin
        self.face = face
        self.features = features
    }

    private enum CodingKeys: String, CodingKey {
        case skin
        case face
        case features
        case skinSmoothing
        case faceSlim
    }

    /// 새 키가 있으면 새 키, 없으면 B0까지의 옛 키를 옮긴다.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let skin = try container.decodeIfPresent(SkinAdjustments.self, forKey: .skin) {
            self.skin = skin
        } else {
            let legacy = try container.decodeIfPresent(Double.self, forKey: .skinSmoothing) ?? 0
            skin = SkinAdjustments(smoothing: legacy)
        }
        if let face = try container.decodeIfPresent(FaceShapeAdjustments.self, forKey: .face) {
            self.face = face
        } else {
            let legacy = try container.decodeIfPresent(Double.self, forKey: .faceSlim) ?? 0
            face = FaceShapeAdjustments(legacyFaceSlim: legacy)
        }
        features = try container.decodeIfPresent(FeatureAdjustments.self, forKey: .features) ?? .init()
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(skin, forKey: .skin)
        try container.encode(face, forKey: .face)
        try container.encode(features, forKey: .features)
    }

    public var dependsOnFaces: Bool { skin.hasEffect || face.hasEffect || features.hasEffect }
    public var numericValues: [Double] { skin.numericValues + face.numericValues + features.numericValues }
}
