import MellowShared

/// 몸통 옆선 점 하나의 자리.
/// level은 어깨 중점에서 엉덩이 중점까지의 비율이고 side는 몸통 가로축 기준 −1·+1이다.
/// +1은 BodySkeleton.across 쪽(똑바로 선 사람에서 화면 오른쪽)이다.
public struct OutlineKey: Hashable, Sendable {
    public let level: Double
    public let side: Int

    public init(level: Double, side: Int) {
        self.level = level
        self.side = side
    }
}

/// 사진 준비 때 그 몸의 사람 마스크에서 찾은 몸통 옆선 점(스펙 5.8).
/// 점은 이미지 정규화 좌표라 미리보기와 원본 해상도 렌더가 같은 자리를 쓴다.
/// 열쇠가 없는 높이·쪽은 팔이 몸통에 붙었거나 배경을 만나지 못한 것이다.
/// 영속화하지 않는다.
public struct BodyOutline: Equatable, Sendable {
    public let points: [OutlineKey: NormalizedPoint]

    public init(points: [OutlineKey: NormalizedPoint]) {
        self.points = points
    }

    /// 부유방 높이(어깨~엉덩이 27%)에 옆선 점이 한쪽이라도 있는지.
    /// 없으면 렌더가 부유방 원소를 만들지 않는다(팔이 붙음).
    /// 앱 안내가 렌더와 같은 높이를 묻는다.
    public var hasSideChestPoint: Bool {
        points.keys.contains { $0.level == BodyShapeRig.sideChestOutlineLevel }
    }
}
