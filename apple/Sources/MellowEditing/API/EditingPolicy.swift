import MellowShared

/// 편집 규칙의 상수. 값 범위는 MellowShared의 AdjustmentRange를 같은 이름으로 내보낸다.
public enum EditingPolicy {
    /// 사진 한 장당 보관하는 실행 취소 단계 수.
    public static let historyLimit = 40
    /// 피부·눈입·배경·메이크업 강도.
    public static let unitRange = AdjustmentRange.unit
    /// 얼굴형·체형의 가운데 0인 양방향 범위.
    public static let bipolarRange = AdjustmentRange.bipolar
    /// 메이크업 색을 처음 고를 때 그 부위 강도가 0이면 두는 값. 색 칩을 눌렀는데 아무것도 안 바뀌는 일을 막는다.
    public static let makeupDefaultIntensity = 0.5

    /// 미소만 한 방향이다.
    public static func faceShapeRange(_ key: FaceShapeKey) -> ClosedRange<Double> {
        AdjustmentRange.faceShape(key)
    }

    /// 다리 길게만 한 방향이다.
    public static func bodyShapeRange(_ key: BodyShapeKey) -> ClosedRange<Double> {
        AdjustmentRange.bodyShape(key)
    }

    /// NaN은 범위의 아래 끝이 된다.
    public static func clamped(_ value: Double, to range: ClosedRange<Double>) -> Double {
        AdjustmentRange.clamped(value, to: range)
    }
}
