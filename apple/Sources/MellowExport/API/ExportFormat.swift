import UniformTypeIdentifiers

public enum ExportFormat: String, CaseIterable, Codable, Sendable {
    case jpeg
    case png

    public var fileExtension: String {
        switch self {
        case .jpeg: return "jpg"
        case .png: return "png"
        }
    }

    var typeIdentifier: String {
        switch self {
        case .jpeg: return UTType.jpeg.identifier
        case .png: return UTType.png.identifier
        }
    }
}

public struct ExportOptions: Equatable, Sendable {
    /// 원본 해상도를 끄면 긴 변을 이 값으로 제한한다. 오래된 iPhone을 위한 보수적 기본값.
    public static let defaultMaxDimension = 4096
    public static let defaultQuality = 0.94

    public var format: ExportFormat
    public var fullResolution: Bool
    public var quality: Double

    public init(
        format: ExportFormat = .jpeg, fullResolution: Bool = false, quality: Double = ExportOptions.defaultQuality
    ) {
        self.format = format
        self.fullResolution = fullResolution
        self.quality = quality
    }

    public var maxDimension: Int? {
        fullResolution ? nil : Self.defaultMaxDimension
    }
}
