import SwiftUI

enum Theme {
    static let accent = Color(red: 0.78, green: 0.88, blue: 0.69)
    static let panel = Color(red: 0.11, green: 0.12, blue: 0.12)
    static let canvas = Color(red: 0.075, green: 0.083, blue: 0.083)
    static let sidebarWidth: CGFloat = 174
    static let inspectorWidth: CGFloat = 292
    static let compactControlsHeight: CGFloat = 200
    static let thumbnailCompact = CGSize(width: 52, height: 60)
    static let thumbnailRegular = CGSize(width: 130, height: 152)
    /// 캔버스 배율. 1은 화면에 맞춤.
    static let zoomRange = 1.0...4.0
    static let zoomStep = 0.5
    static let toolButtonSize = CGSize(width: 64, height: 56)
    /// Mac 도구 줄 아래 스크롤 막대 자리. 막대가 버튼 글자를 가리지 않게 한다.
    static let toolStripScrollerInset: CGFloat = 12
    static let lookChipSize = CGSize(width: 64, height: 76)
    static let cropHandleSize: CGFloat = 22
    /// 자르기 사각형의 최소 변. 정규화 단위.
    static let cropMinimumSide = 0.1
    /// 복제 샘플 고리의 최소 지름. 브러시가 아주 작아도 보이게 한다.
    static let brushMarkerMinimumDiameter: CGFloat = 12

    static func clampedZoom(_ value: Double) -> Double {
        min(zoomRange.upperBound, max(zoomRange.lowerBound, value))
    }
}

extension Image {
    init(cgImage: CGImage) {
        self.init(decorative: cgImage, scale: 1, orientation: .up)
    }
}
