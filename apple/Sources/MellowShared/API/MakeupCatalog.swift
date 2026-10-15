import Foundation

/// 메이크업 팔레트의 색 하나. rgb는 sRGB 감마 값 0…1이다(shared/makeup/makeup.v1.json).
public struct MakeupColor: Codable, Equatable, Sendable, Identifiable {
    public var id: String
    public var name: String
    public var rgb: [Double]

    public init(id: String, name: String, rgb: [Double]) {
        self.id = id
        self.name = name
        self.rgb = rgb
    }

    public var red: Double { component(0) }
    public var green: Double { component(1) }
    public var blue: Double { component(2) }

    /// 성분이 모자라면 0. 파일에서 읽은 카탈로그는 3개인지 이미 검사했다.
    private func component(_ index: Int) -> Double {
        rgb.indices.contains(index) ? rgb[index] : 0
    }
}

/// 메이크업 룩 하나. 고르면 부위 값을 레시피에 채운다(스펙 6).
public struct MakeupLook: Codable, Equatable, Sendable, Identifiable {
    public var id: String
    public var name: String
    public var lip: MakeupTint
    public var blush: MakeupTint
    public var eyeshadow: MakeupTint
    public var brow: MakeupStrength
    public var contour: MakeupStrength

    public init(
        id: String, name: String, lip: MakeupTint = .init(), blush: MakeupTint = .init(),
        eyeshadow: MakeupTint = .init(), brow: MakeupStrength = .init(), contour: MakeupStrength = .init()
    ) {
        self.id = id
        self.name = name
        self.lip = lip
        self.blush = blush
        self.eyeshadow = eyeshadow
        self.brow = brow
        self.contour = contour
    }

    /// 이 룩을 고른 레시피의 메이크업 값. lookID는 이 룩의 id다.
    public var adjustments: MakeupAdjustments {
        MakeupAdjustments(lookID: id, lip: lip, blush: blush, eyeshadow: eyeshadow, brow: brow, contour: contour)
    }
}

/// shared/makeup/makeup.v1.json의 팔레트와 룩. LookCatalog와 같은 방식으로 모든 플랫폼이 같은 파일을 읽는다.
public struct MakeupCatalog: Equatable, Sendable {
    public static let currentSchemaVersion = 1
    public static let builtInLookIDs = ["daily", "cool", "warm-peach", "rosy", "smoky"]
    public static let builtInColorIDs: [MakeupPart: [String]] = [
        .lip: ["lip-nude", "lip-coral", "lip-rose", "lip-red", "lip-berry", "lip-mlbb"],
        .blush: ["blush-peach", "blush-pink", "blush-coral", "blush-rose"],
        .eyeshadow: ["shadow-brown", "shadow-peach", "shadow-pink", "shadow-smoky"],
    ]
    public static let empty = MakeupCatalog(looks: [], palettes: [:])
    /// rgb 성분 수.
    private static let rgbComponents = 3

    private struct File: Decodable {
        var schemaVersion: Int
        var colors: [String: [MakeupColor]]
        var looks: [MakeupLook]
    }

    /// 화면 순서의 룩.
    public let looks: [MakeupLook]
    private let palettes: [MakeupPart: [MakeupColor]]

    public init(looks: [MakeupLook], palettes: [MakeupPart: [MakeupColor]]) {
        self.looks = looks
        self.palettes = palettes
    }

    /// 형식이 틀리면 DecodingError를 던진다. 모르는 schemaVersion·부위, rgb가 3개가 아니거나 0…1 밖, 색·룩 id 중복,
    /// 룩이 그 부위 팔레트에 없는 색을 가리키거나 강도가 0…1 밖이면 파일 전체를 거부한다.
    public init(data: Data) throws {
        let file = try JSONDecoder().decode(File.self, from: data)
        guard file.schemaVersion == Self.currentSchemaVersion else {
            throw Self.corrupted("unsupported makeup schemaVersion \(file.schemaVersion)")
        }
        var palettes: [MakeupPart: [MakeupColor]] = [:]
        for (key, colors) in file.colors {
            guard let part = MakeupPart(rawValue: key), part.hasColor else {
                throw Self.corrupted("unknown makeup color part \(key)")
            }
            for color in colors where !Self.isValid(color) {
                throw Self.corrupted("invalid rgb for \(color.id)")
            }
            palettes[part] = colors
        }
        let colorIDs = palettes.values.flatMap { $0.map(\.id) }
        let lookIDs = file.looks.map(\.id)
        guard Set(colorIDs).count == colorIDs.count, Set(lookIDs).count == lookIDs.count else {
            throw Self.corrupted("duplicate makeup id")
        }
        self.init(looks: file.looks, palettes: palettes)
        for look in looks {
            try validate(look)
        }
    }

    public func look(id: String?) -> MakeupLook? {
        guard let id else { return nil }
        return looks.first { $0.id == id }
    }

    /// 화면 순서의 팔레트. 눈썹·쉐딩은 빈 배열이다.
    public func colors(for part: MakeupPart) -> [MakeupColor] {
        palettes[part] ?? []
    }

    /// 어느 부위든 id가 같은 색.
    public func color(id: String?) -> MakeupColor? {
        MakeupPart.allCases.lazy.compactMap { self.color(id: id, for: $0) }.first
    }

    /// part 팔레트 안의 색. 다른 부위의 색 id는 nil이라 렌더가 그 부위를 건너뛴다.
    public func color(id: String?, for part: MakeupPart) -> MakeupColor? {
        guard let id else { return nil }
        return colors(for: part).first { $0.id == id }
    }

    /// 룩도 색도 없으면 true. 앱이 "메이크업 목록을 읽지 못함" 안내를 보일 때 쓴다.
    public var isEmpty: Bool { looks.isEmpty && palettes.values.allSatisfy(\.isEmpty) }

    private static func isValid(_ color: MakeupColor) -> Bool {
        color.rgb.count == rgbComponents && color.rgb.allSatisfy { AdjustmentRange.unit.contains($0) }
    }

    /// 룩의 강도는 0…1이고 색은 그 부위 팔레트에 있어야 한다.
    private func validate(_ look: MakeupLook) throws {
        let tints: [(MakeupPart, MakeupTint)] = [(.lip, look.lip), (.blush, look.blush), (.eyeshadow, look.eyeshadow)]
        for (part, tint) in tints {
            if let id = tint.colorID, color(id: id, for: part) == nil {
                throw Self.corrupted("\(look.id) \(part.rawValue) color \(id) not in palette")
            }
        }
        let intensities = tints.map { $0.1.intensity } + [look.brow.intensity, look.contour.intensity]
        guard intensities.allSatisfy({ AdjustmentRange.unit.contains($0) }) else {
            throw Self.corrupted("\(look.id) intensity out of range")
        }
    }

    private static func corrupted(_ description: String) -> DecodingError {
        DecodingError.dataCorrupted(DecodingError.Context(codingPath: [], debugDescription: description))
    }
}
