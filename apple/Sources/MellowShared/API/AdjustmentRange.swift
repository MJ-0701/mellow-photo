import Foundation

/// 레시피 값 범위의 유일한 정의. 편집 규칙(EditingPolicy)과 렌더 단계가 함께 쓴다.
/// MellowRendering은 MellowEditing을 import할 수 없고, 프리셋·일괄 적용 값은 편집 규칙의 클램프를 거치지 않으므로
/// 렌더 단계도 이 범위로 직접 자른다.
public enum AdjustmentRange {
    /// 피부·눈입·배경·메이크업 강도, 미소·이중턱·다리 길게·부유방.
    public static let unit: ClosedRange<Double> = 0...1
    /// 얼굴형·체형의 가운데 0인 양방향 범위.
    public static let bipolar: ClosedRange<Double> = -1...1

    /// 미소·이중턱만 한 방향이다.
    public static func faceShape(_ key: FaceShapeKey) -> ClosedRange<Double> {
        switch key {
        case .smile, .doubleChin: return unit
        default: return bipolar
        }
    }

    /// 다리 길게·부유방만 한 방향이다.
    public static func bodyShape(_ key: BodyShapeKey) -> ClosedRange<Double> {
        switch key {
        case .legLength, .sideChest: return unit
        default: return bipolar
        }
    }

    /// 붉은기(맑게 ↔ 혈색)만 양방향이다.
    public static func skinRefinement(_ key: SkinRefinementKey) -> ClosedRange<Double> {
        key == .redness ? bipolar : unit
    }

    /// 피부 톤(따뜻 ↔ 차가움)만 양방향이다.
    public static func bodySkin(_ key: BodySkinKey) -> ClosedRange<Double> {
        key == .tone ? bipolar : unit
    }

    /// NaN은 범위의 아래 끝이 된다.
    public static func clamped(_ value: Double, to range: ClosedRange<Double>) -> Double {
        min(range.upperBound, max(range.lowerBound, value))
    }
}
