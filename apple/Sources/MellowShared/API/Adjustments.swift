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

public struct PortraitAdjustments: Codable, Equatable, Sendable {
    public var skinSmoothing: Double = 0
    public var faceSlim: Double = 0
    /// 왼쪽부터 센 얼굴 인덱스. nil이면 모든 얼굴.
    public var targetFace: Int? = nil

    public init(skinSmoothing: Double = 0, faceSlim: Double = 0, targetFace: Int? = nil) {
        self.skinSmoothing = skinSmoothing
        self.faceSlim = faceSlim
        self.targetFace = targetFace
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        skinSmoothing = try container.decodeIfPresent(Double.self, forKey: .skinSmoothing) ?? 0
        faceSlim = try container.decodeIfPresent(Double.self, forKey: .faceSlim) ?? 0
        targetFace = try container.decodeIfPresent(Int.self, forKey: .targetFace)
    }

    public var dependsOnFaces: Bool { skinSmoothing > 0 || faceSlim > 0 }
}
