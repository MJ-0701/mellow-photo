import MellowShared

public enum EditingPolicy {
    /// 사진 한 장당 보관하는 실행 취소 단계 수.
    public static let historyLimit = 40
    /// 피부·눈입·배경·메이크업 강도.
    public static let unitRange: ClosedRange<Double> = 0...1
    /// 얼굴형·체형의 가운데 0인 양방향 범위.
    public static let bipolarRange: ClosedRange<Double> = -1...1

    /// 미소만 한 방향이다.
    public static func faceShapeRange(_ key: FaceShapeKey) -> ClosedRange<Double> {
        key == .smile ? unitRange : bipolarRange
    }

    /// NaN은 범위의 아래 끝이 된다.
    public static func clamped(_ value: Double, to range: ClosedRange<Double>) -> Double {
        min(range.upperBound, max(range.lowerBound, value))
    }
}
