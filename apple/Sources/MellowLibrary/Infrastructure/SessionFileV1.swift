import Foundation
import MellowShared

/// 출시된 iPhone 앱(MobileSession)의 포맷. 타입 구조를 그대로 흉내 내야 Swift가
/// `[UUID: [Recipe]]`를 평탄 배열로 저장한 것까지 올바르게 읽는다. 손으로 파싱하지 않는다.
struct SessionFileV1: Decodable {
    struct Adjustments: Decodable {
        var exposure: Double = 0
        var contrast: Double = 1
        var saturation: Double = 1
        var warmth: Double = 0
        var skin: Double = 0
        var faceSlim: Double = 0
    }

    struct Spot: Decodable {
        var x: Double
        var y: Double
        var sourceX: Double
        var sourceY: Double
        var radius: Double
    }

    struct Warp: Decodable {
        var x: Double
        var y: Double
        var dx: Double
        var dy: Double
        var radius: Double
    }

    /// Swift 합성 Codable의 enum 표현: {"spot":{"_0":{…}}}
    enum Operation: Decodable {
        case spot(Spot)
        case warp(Warp)

        private enum CodingKeys: String, CodingKey {
            case spot
            case warp
        }

        private enum PayloadKeys: String, CodingKey {
            case value = "_0"
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            if container.contains(.spot) {
                let payload = try container.nestedContainer(keyedBy: PayloadKeys.self, forKey: .spot)
                self = .spot(try payload.decode(Spot.self, forKey: .value))
            } else {
                let payload = try container.nestedContainer(keyedBy: PayloadKeys.self, forKey: .warp)
                self = .warp(try payload.decode(Warp.self, forKey: .value))
            }
        }
    }

    struct Recipe: Decodable {
        var adjustments = Adjustments()
        var operations: [Operation] = []
        var selectedFace: Int?
    }

    struct Photo: Decodable {
        var id: UUID
        var filename: String
        var name: String
        var recipe: Recipe
    }

    struct SavedPreset: Decodable {
        var id: UUID
        var name: String
        var adjustments: Adjustments
    }

    var photos: [Photo]
    var selectedID: UUID?
    var presets: [SavedPreset]
    var undoHistory: [UUID: [Recipe]]?
    var redoHistory: [UUID: [Recipe]]?

    func upgraded() -> SessionFile {
        let photos = self.photos.map { photo in
            SessionFile.Photo(
                id: photo.id,
                filename: photo.filename,
                displayName: photo.name,
                recipe: Self.recipe(photo.recipe),
                undo: (undoHistory?[photo.id] ?? []).map(Self.recipe),
                redo: (redoHistory?[photo.id] ?? []).map(Self.recipe))
        }
        let presets = self.presets.map { preset in
            Preset(id: preset.id, name: preset.name, values: Self.values(preset.adjustments))
        }
        let selected = photos.contains { $0.id == selectedID } ? selectedID : photos.first?.id
        return SessionFile(photos: photos, selectedPhotoID: selected, presets: presets)
    }

    private static func values(_ adjustments: Adjustments) -> PresetValues {
        PresetValues(
            color: ColorAdjustments(
                exposure: adjustments.exposure, contrast: adjustments.contrast,
                saturation: adjustments.saturation, warmth: adjustments.warmth),
            portrait: PortraitAdjustments(
                skin: SkinAdjustments(smoothing: adjustments.skin),
                face: FaceShapeAdjustments(legacyFaceSlim: adjustments.faceSlim)))
    }

    private static func recipe(_ recipe: Recipe) -> EditRecipe {
        var converted = values(recipe.adjustments)
        converted.portrait.targetFace = recipe.selectedFace
        let operations = recipe.operations.map { operation -> LocalEdit in
            switch operation {
            case .spot(let spot):
                return .spot(
                    RetouchSpot(x: spot.x, y: spot.y, sourceX: spot.sourceX, sourceY: spot.sourceY, radius: spot.radius)
                )
            case .warp(let warp):
                return .warp(WarpStroke(x: warp.x, y: warp.y, dx: warp.dx, dy: warp.dy, radius: warp.radius))
            }
        }
        return EditRecipe(color: converted.color, portrait: converted.portrait, operations: operations)
    }
}
