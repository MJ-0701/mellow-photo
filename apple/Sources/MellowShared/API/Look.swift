import Foundation

/// 필터 한 개의 파라미터. shared/looks/looks.v1.json과 같은 형식이며 모든 플랫폼이 같은 파일을 읽는다.
public struct Look: Codable, Equatable, Sendable, Identifiable {
    public var id: String
    public var name: String
    /// 휘도 입력→출력 점 5개. x 오름차순, 0…1.
    public var toneCurve: [[Double]]
    public var saturation: Double
    public var contrast: Double
    public var warmth: Double
    public var tint: Double
    public var vignette: Double
    /// 블랙 리프트. 커브 시작점을 fade × fadeLift만큼 올린다.
    public var fade: Double

    public static let fadeLift = 0.15

    public init(
        id: String, name: String, toneCurve: [[Double]], saturation: Double = 1, contrast: Double = 1,
        warmth: Double = 0, tint: Double = 0, vignette: Double = 0, fade: Double = 0
    ) {
        self.id = id
        self.name = name
        self.toneCurve = toneCurve
        self.saturation = saturation
        self.contrast = contrast
        self.warmth = warmth
        self.tint = tint
        self.vignette = vignette
        self.fade = fade
    }
}

public struct LookCatalog: Equatable, Sendable {
    public static let currentSchemaVersion = 1
    public static let builtInIDs = [
        "clear", "film", "cozy", "calm", "mono", "sepia", "vintage", "vivid", "pastel", "night",
    ]
    public static let empty = LookCatalog(looks: [])

    private struct File: Decodable {
        var schemaVersion: Int
        var looks: [Look]
    }

    public let all: [Look]
    private let byID: [String: Look]

    public init(looks: [Look]) {
        all = looks
        byID = Dictionary(looks.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    }

    public init(data: Data) throws {
        let file = try JSONDecoder().decode(File.self, from: data)
        guard file.schemaVersion == Self.currentSchemaVersion else {
            throw DecodingError.dataCorrupted(
                DecodingError.Context(
                    codingPath: [], debugDescription: "unsupported looks schemaVersion \(file.schemaVersion)"))
        }
        self.init(looks: file.looks)
    }

    public func look(id: String?) -> Look? {
        guard let id else { return nil }
        return byID[id]
    }
}
