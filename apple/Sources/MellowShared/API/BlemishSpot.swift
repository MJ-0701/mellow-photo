import Foundation

/// 사진 준비 때 찾은 자동 잡티. 영속화하지 않고 준비할 때마다 다시 계산한다.
public struct BlemishSpot: Equatable, Sendable {
    /// 정규화 중심. 원점은 왼쪽 아래.
    public var x: Double
    public var y: Double
    /// 짧은 변 대비 반지름. RetouchSpot.radius와 같은 단위.
    public var radius: Double
    /// 왼쪽부터 센 얼굴 인덱스. 대상 얼굴 선택에 쓴다.
    public var faceIndex: Int

    public init(x: Double, y: Double, radius: Double, faceIndex: Int) {
        self.x = x
        self.y = y
        self.radius = radius
        self.faceIndex = faceIndex
    }
}
