public enum EditChange: Equatable, Sendable {
    case exposure(Double)
    case contrast(Double)
    case saturation(Double)
    case warmth(Double)
    case skinSmoothing(Double)
    case faceSlim(Double)
    case targetFace(Int?)

    /// 수동 편집이 있는 동안 바꿀 수 없는 변경.
    public var affectsGeometry: Bool {
        switch self {
        case .faceSlim, .targetFace:
            return true
        default:
            return false
        }
    }
}
