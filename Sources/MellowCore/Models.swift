import Foundation
import CoreGraphics

public struct Adjustments: Codable, Equatable, Sendable {
    public var exposure: Double = 0
    public var contrast: Double = 1
    public var saturation: Double = 1
    public var warmth: Double = 0
    public var skin: Double = 0
    public var faceSlim: Double = 0
    public init() {}
}

// Coordinates are normalized to the oriented image, with origin at bottom left.
public struct RetouchSpot: Codable, Equatable, Sendable {
    public var x: Double
    public var y: Double
    public var sourceX: Double
    public var sourceY: Double
    public var radius: Double
    public init(x: Double, y: Double, sourceX: Double, sourceY: Double, radius: Double) {
        self.x = x; self.y = y; self.sourceX = sourceX; self.sourceY = sourceY; self.radius = radius
    }
}
public struct WarpStroke: Codable, Equatable, Sendable {
    public var x: Double
    public var y: Double
    public var dx: Double
    public var dy: Double
    public var radius: Double
    public init(x: Double, y: Double, dx: Double, dy: Double, radius: Double) {
        self.x = x; self.y = y; self.dx = dx; self.dy = dy; self.radius = radius
    }
}
public enum LocalEdit: Codable, Equatable, Sendable {
    case spot(RetouchSpot)
    case warp(WarpStroke)
}
public struct EditRecipe: Codable, Equatable, Sendable {
    public var adjustments = Adjustments()
    public var operations: [LocalEdit] = []
    public var spots: [RetouchSpot] { operations.compactMap { if case .spot(let s) = $0 { return s }; return nil } }
    public var warps: [WarpStroke] { operations.compactMap { if case .warp(let s) = $0 { return s }; return nil } }
    public var selectedFace: Int? = nil
    public init() {}
}
public struct FaceRegion: Sendable {
    public let rect: CGRect
    public let leftEye: CGRect?
    public let rightEye: CGRect?
    public let mouth: CGRect?
    public init(rect: CGRect, leftEye: CGRect? = nil, rightEye: CGRect? = nil, mouth: CGRect? = nil) {
        self.rect = rect; self.leftEye = leftEye; self.rightEye = rightEye; self.mouth = mouth
    }
}
public struct SavedPreset: Codable, Identifiable, Equatable {
    public var id: UUID
    public var name: String
    public var adjustments: Adjustments
    public init(name: String, adjustments: Adjustments) { self.id = UUID(); self.name = name; self.adjustments = adjustments }
}
