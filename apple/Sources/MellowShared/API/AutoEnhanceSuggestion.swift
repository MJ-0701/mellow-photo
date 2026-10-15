import Foundation

/// 자동 보정이 제안하는 슬라이더 값. 적용은 EditDocument가 규칙에 따라 한다.
public struct AutoEnhanceSuggestion: Equatable, Sendable {
    public var color: ColorAdjustments
    public var detail: DetailAdjustments
    public var portrait: PortraitAdjustments

    public init(color: ColorAdjustments, detail: DetailAdjustments, portrait: PortraitAdjustments) {
        self.color = color
        self.detail = detail
        self.portrait = portrait
    }
}
