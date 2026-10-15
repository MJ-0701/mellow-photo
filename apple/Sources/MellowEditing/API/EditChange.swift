import MellowShared

public enum EditChange: Equatable, Sendable {
    case exposure(Double)
    case contrast(Double)
    case saturation(Double)
    case warmth(Double)
    case skinSmoothing(Double)
    case autoBlemish(Bool)
    case faceShape(FaceShapeKey, Double)
    case targetFace(Int?)
    case feature(FeatureKey, Double)
    case backgroundBlur(Double)
    case bodyShape(BodyShapeKey, Double)
    case makeupColor(MakeupPart, String?)
    case makeupIntensity(MakeupPart, Double)
    case highlights(Double)
    case shadows(Double)
    case sharpness(Double)
    case vignette(Double)
    case lookID(String?)
    case lookIntensity(Double)
    case flipHorizontal(Bool)
    case quarterTurns(Int)
    case straightenDegrees(Double)
    case crop(NormalizedRect?)

    /// 수동 편집이 있는 동안 바꿀 수 없는 변경. 자르기·회전은 원본 좌표를 바꾸지 않으므로 잠기지 않는다.
    public var affectsGeometry: Bool {
        switch self {
        case .faceShape, .bodyShape, .targetFace:
            return true
        default:
            return false
        }
    }
}
