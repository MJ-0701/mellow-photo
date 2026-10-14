import Foundation

public struct RetouchSpot: Codable, Equatable, Sendable {
    public var x: Double
    public var y: Double
    public var sourceX: Double
    public var sourceY: Double
    public var radius: Double

    public init(x: Double, y: Double, sourceX: Double, sourceY: Double, radius: Double) {
        self.x = x
        self.y = y
        self.sourceX = sourceX
        self.sourceY = sourceY
        self.radius = radius
    }
}

public struct WarpStroke: Codable, Equatable, Sendable {
    public var x: Double
    public var y: Double
    public var dx: Double
    public var dy: Double
    public var radius: Double

    public init(x: Double, y: Double, dx: Double, dy: Double, radius: Double) {
        self.x = x
        self.y = y
        self.dx = dx
        self.dy = dy
        self.radius = radius
    }
}

/// 사용자가 기록한 순서대로 재생되는 수동 편집.
public enum LocalEdit: Equatable, Sendable {
    case spot(RetouchSpot)
    case warp(WarpStroke)
}

extension LocalEdit: Codable {
    private enum CodingKeys: String, CodingKey {
        case type
    }

    private enum Kind: String, Codable {
        case spot
        case warp
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(Kind.self, forKey: .type) {
        case .spot:
            self = .spot(try RetouchSpot(from: decoder))
        case .warp:
            self = .warp(try WarpStroke(from: decoder))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .spot(let spot):
            try container.encode(Kind.spot, forKey: .type)
            try spot.encode(to: encoder)
        case .warp(let stroke):
            try container.encode(Kind.warp, forKey: .type)
            try stroke.encode(to: encoder)
        }
    }

    public var numericValues: [Double] {
        switch self {
        case .spot(let spot):
            return [spot.x, spot.y, spot.sourceX, spot.sourceY, spot.radius]
        case .warp(let stroke):
            return [stroke.x, stroke.y, stroke.dx, stroke.dy, stroke.radius]
        }
    }
}
