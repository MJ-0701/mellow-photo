import MellowShared

public enum EditChange: Equatable, Sendable {
    case exposure(Double)
    case contrast(Double)
    case saturation(Double)
    case warmth(Double)
    case skinSmoothing(Double)
    case autoBlemish(Bool)
    case skinRefinement(SkinRefinementKey, Double)
    case faceShape(FaceShapeKey, Double)
    case targetFace(Int?)
    case feature(FeatureKey, Double)
    case backgroundBlur(Double)
    case bodySkin(BodySkinKey, Double)
    case bodyShape(BodyShapeKey, Double)
    case makeupColor(MakeupPart, String?)
    case makeupIntensity(MakeupPart, Double)
    case highlights(Double)
    case shadows(Double)
    case sharpness(Double)
    case vignette(Double)
    case effect(EffectKey, Double)
    case lookID(String?)
    case lookIntensity(Double)
    case flipHorizontal(Bool)
    case quarterTurns(Int)
    case straightenDegrees(Double)
    case crop(NormalizedRect?)
    /// 사람의 수동 성별 지정.
    /// 개인 scope에서만 뜻이 있다.
    case gender(Gender?)

    /// 수동 편집이 있는 동안 바꿀 수 없는 변경. 자르기·회전은 원본 좌표를 바꾸지 않으므로 잠기지 않는다.
    /// 성별이 바뀌면 그룹의 얼굴형 값이 다른 얼굴에 걸려 수동 편집 좌표가 어긋난다.
    public var affectsGeometry: Bool {
        switch self {
        case .faceShape, .bodyShape, .targetFace, .gender:
            return true
        default:
            return false
        }
    }
}

extension EditChange {
    /// 층이 덮어쓸 수 있는 키.
    /// 얼굴 의존 변경만 값이 있고 나머지는 scope를 무시한다.
    public var portraitKey: PortraitKey? {
        switch self {
        case .skinSmoothing: return .skinSmoothing
        case .autoBlemish: return .autoBlemish
        case .skinRefinement(let key, _): return .skinRefinement(key)
        case .faceShape(let key, _): return .faceShape(key)
        case .feature(let key, _): return .feature(key)
        case .makeupColor(let part, _), .makeupIntensity(let part, _): return .makeupPart(part)
        default: return nil
        }
    }
}
