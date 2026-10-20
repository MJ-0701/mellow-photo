import MellowShared

/// "전체 사진에 적용"이 복사할 수 있는 항목. 레시피 그룹과의 대응과 잠금·개인 층 규칙은 EditDocument.applyFromBatch에 있다.
public enum SyncCategory: String, CaseIterable, Codable, Sendable, Identifiable {
    /// 색감 + 디테일.
    case color
    case effects
    /// 피부 보정·자동 잡티·피부 정밀.
    case skin
    /// 얼굴형. 잠긴 사진에서는 복사하지 않는다.
    case faceShape
    case features
    case makeup
    case background
    /// 체형. 잠긴 사진에서는 복사하지 않는다.
    case body
    case bodySkin

    public var id: Self { self }
    public static let all = Set(allCases)

    /// 얼굴에 의존하는 항목. 복사하면 받는 사진의 개인 층에서 그 항목의 키를 지운다.
    public var dependsOnFaces: Bool {
        switch self {
        case .skin, .faceShape, .features, .makeup: return true
        case .color, .effects, .background, .body, .bodySkin: return false
        }
    }

    /// 이 항목이 층에서 다루는 키.
    /// 얼굴 의존 항목만 값이 있다.
    public var portraitKeys: Set<PortraitKey>? {
        switch self {
        case .skin: return PortraitKey.skin
        case .faceShape: return PortraitKey.faceShape
        case .features: return PortraitKey.features
        case .makeup: return PortraitKey.makeup
        case .color, .effects, .background, .body, .bodySkin: return nil
        }
    }
}
