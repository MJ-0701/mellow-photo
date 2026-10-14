import CoreGraphics
import Foundation

/// 방향 보정된 이미지 기준 정규화 좌표. 원점은 왼쪽 아래.
public struct NormalizedPoint: Codable, Hashable, Sendable {
    public var x: Double
    public var y: Double

    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }
}

public struct NormalizedRect: Codable, Equatable, Sendable {
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }

    public init(cgRect: CGRect) {
        self.init(x: cgRect.minX, y: cgRect.minY, width: cgRect.width, height: cgRect.height)
    }

    public var cgRect: CGRect { CGRect(x: x, y: y, width: width, height: height) }
    public var minX: Double { x }
    public var minY: Double { y }
    public var maxX: Double { x + width }
    public var maxY: Double { y + height }
    public var midX: Double { x + width / 2 }
    public var midY: Double { y + height / 2 }
}

public struct PhotoID: Hashable, Codable, Sendable {
    public let rawValue: UUID

    public init() {
        rawValue = UUID()
    }

    public init(rawValue: UUID) {
        self.rawValue = rawValue
    }

    public init(from decoder: Decoder) throws {
        rawValue = try decoder.singleValueContainer().decode(UUID.self)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}
