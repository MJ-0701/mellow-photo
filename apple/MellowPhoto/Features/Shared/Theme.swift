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
    /// 메이크업 룩 이름 칩의 최소 크기와 좌우 여백.
    static let makeupChipSize = CGSize(width: 56, height: 30)
    static let makeupChipPadding: CGFloat = 10
    /// 메이크업 색 칩 지름.
    static let makeupSwatchSize: CGFloat = 28
    static let cropHandleSize: CGFloat = 22
    /// 자르기 사각형의 최소 변. 정규화 단위.
    static let cropMinimumSide = 0.1
    /// 복제 샘플 고리의 최소 지름. 브러시가 아주 작아도 보이게 한다.
    static let brushMarkerMinimumDiameter: CGFloat = 12
    /// 가운데 0인 양방향 슬라이더가 0으로 붙는 폭.
    static let bipolarSnapWidth = 0.05
    /// 분할 비교 세로선 두께.
    static let compareDividerWidth: CGFloat = 2
    /// 분할선 손잡이 지름. 그리는 크기다.
    static let compareHandleSize: CGFloat = 28
    /// 분할선을 잡을 수 있는 띠의 폭. 손가락으로 잡기 쉬운 최소 터치 크기다.
    static let compareHandleHitWidth: CGFloat = 44
    /// 캔버스 이미지 좌표계 이름. 분할선 드래그 위치를 이 좌표로 받는다.
    static let canvasCoordinateSpace = "canvas"

    static func clampedZoom(_ value: Double) -> Double {
        min(zoomRange.upperBound, max(zoomRange.lowerBound, value))
    }
}

extension Image {
    init(cgImage: CGImage) {
        self.init(decorative: cgImage, scale: 1, orientation: .up)
    }
}
