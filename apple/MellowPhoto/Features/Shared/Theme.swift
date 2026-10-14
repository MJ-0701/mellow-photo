import SwiftUI

enum Theme {
    static let accent = Color(red: 0.78, green: 0.88, blue: 0.69)
    static let panel = Color(red: 0.11, green: 0.12, blue: 0.12)
    static let canvas = Color(red: 0.075, green: 0.083, blue: 0.083)
    static let sidebarWidth: CGFloat = 174
    static let inspectorWidth: CGFloat = 292
    static let compactControlsHeight: CGFloat = 182
    static let thumbnailCompact = CGSize(width: 52, height: 60)
    static let thumbnailRegular = CGSize(width: 130, height: 152)
    /// 캔버스 배율. 1은 화면에 맞춤.
    static let zoomRange = 1.0...4.0
    static let zoomStep = 0.5

    static func clampedZoom(_ value: Double) -> Double {
        min(zoomRange.upperBound, max(zoomRange.lowerBound, value))
    }
}

extension Image {
    init(cgImage: CGImage) {
        self.init(decorative: cgImage, scale: 1, orientation: .up)
    }
}
