import CoreImage

/// 이동량 지도에서 그 자리를 움직이지 않게 막는 모양. 좌표·길이는 extent 픽셀이다.
enum ShapeGuard: Equatable, Sendable {
    /// start–end 선분에서 radius 안은 막고(가중치 0) radius + feather 밖은 그대로 둔다(가중치 1).
    /// 그 사이는 smoothstep으로 잇는다.
    case capsule(start: CGPoint, end: CGPoint, radius: CGFloat, feather: CGFloat)
}

/// 같은 보호를 받는 이동 원소 묶음(스펙 5.4).
/// 사람 마스크는 분석기가 준 해상도 그대로이고 extent 배치는 DisplacementWarp가 한다.
/// ownMask가 nil이면 배경·이웃·팔 보호를 모두 끈다.
struct ShapeGroup: Sendable {
    var primitives: [ShapePrimitive]
    /// 이 원소들이 속한 사람의 마스크.
    /// 밖(배경)으로 갈수록 이동을 줄인다.
    var ownMask: CIImage?
    /// 다른 사람들의 마스크.
    /// 그 안은 움직이지 않는다.
    var otherMasks: [CIImage]
    /// 이 묶음의 이동을 막는 자리(몸통 묶음의 팔).
    var guards: [ShapeGuard]

    init(
        primitives: [ShapePrimitive], ownMask: CIImage? = nil, otherMasks: [CIImage] = [],
        guards: [ShapeGuard] = []
    ) {
        self.primitives = primitives
        self.ownMask = ownMask
        self.otherMasks = otherMasks
        self.guards = guards
    }
}
