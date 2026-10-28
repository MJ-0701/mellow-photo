import MellowShared

public enum OneTouchApplicationScope: Equatable, Sendable {
    case all
    case gender(Gender)
    case person(PersonID)
    case face(Int)
}

/// 렌더 입력 값의 변화 보고다. 화질 개선이나 완료 렌더를 인증하지 않는다.
public struct OneTouchApplicationResult: Equatable, Sendable {
    public enum Value: Equatable, Sendable {
        case number(Double)
        case flag(Bool)
        /// 강도 0의 색 ID는 가시적 차이가 없으므로 nil로 정규화한다.
        case tint(colorID: String?, intensity: Double)
    }
    public enum Reason: Equatable, Sendable { case changed, protectedPersonal, unavailable, unchanged, invalidTargets }
    public struct Item: Equatable, Sendable {
        public let faceIndex: Int
        public let key: PortraitKey
        public let before: Value
        public let after: Value
        public let reason: Reason
        public let renderReady: Bool
        public var resolvedChanged: Bool { before != after }
    }
    public let requestedStrength: Double
    public let items: [Item]
    /// 준비된 사진 단위 몸 피부 값의 변경. 얼굴 적용 건수와 섞지 않는다.
    public let bodySkinChanged: Bool
    public var bodySkinBefore: BodySkinAdjustments = .init()
    public var bodySkinAfter: BodySkinAdjustments = .init()
    public var storedBodySkinChanged: Bool { bodySkinBefore != bodySkinAfter }
    public var resolvedChangedCount: Int { items.filter(\.resolvedChanged).count }
    public var renderReadyChangedKeys: [Item] { items.filter { $0.resolvedChanged && $0.renderReady } }
    public var unavailableForRenderingKeys: [Item] { items.filter { !$0.renderReady } }
    public var changedCount: Int { items.filter { $0.resolvedChanged && $0.renderReady }.count }
    public var hasChanges: Bool { changedCount > 0 || bodySkinChanged }

    static func value(_ key: PortraitKey, in resolved: PortraitResolver.Resolved) -> Value {
        switch key {
        case .skinSmoothing: return .number(resolved.portrait.skin.smoothing)
        case .autoBlemish: return .flag(resolved.portrait.skin.autoBlemish)
        case .skinRefinement(let key): return .number(resolved.portrait.skin[key])
        case .feature(let key): return .number(resolved.portrait.features[key])
        case .makeupPart(let part):
            let intensity = resolved.makeup.intensity(of: part)
            return .tint(colorID: intensity == 0 ? nil : resolved.makeup.colorID(of: part), intensity: intensity)
        default: preconditionFailure("OneTouch 키만 보고한다")
        }
    }
}
