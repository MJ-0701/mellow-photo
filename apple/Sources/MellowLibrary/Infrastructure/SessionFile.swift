import Foundation
import MellowShared

/// 디스크 포맷 v2. 런타임 타입과 분리되어 있어 런타임이 바뀌어도 파일 호환을 따로 관리한다.
struct SessionFile: Codable, Equatable {
    static let currentSchemaVersion = 2

    struct Photo: Codable, Equatable {
        var id: UUID
        var filename: String
        var displayName: String
        var recipe: EditRecipe
        var undo: [EditRecipe]
        var redo: [EditRecipe]
    }

    var schemaVersion: Int = currentSchemaVersion
    var photos: [Photo]
    var selectedPhotoID: UUID?
    var presets: [Preset]

    private struct VersionProbe: Decodable {
        var schemaVersion: Int?
    }

    /// v1(출시본 iPhone 포맷)과 v2를 자동 판별한다.
    static func decode(_ data: Data) throws -> SessionFile {
        let decoder = JSONDecoder()
        let version = try decoder.decode(VersionProbe.self, from: data).schemaVersion ?? 1
        switch version {
        case 1:
            return try decoder.decode(SessionFileV1.self, from: data).upgraded()
        case currentSchemaVersion:
            return try decoder.decode(SessionFile.self, from: data)
        default:
            throw MellowError.sessionUnreadable
        }
    }

    static func encode(_ file: SessionFile) throws -> Data {
        var copy = file
        copy.schemaVersion = currentSchemaVersion
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(copy)
    }
}
