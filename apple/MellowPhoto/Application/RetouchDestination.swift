import MellowShared

/// 보정값을 바꾸지 않고 기존 도구의 정확한 조절 항목으로 이동한다.
enum RetouchDestination: Hashable, Identifiable {
    case skin
    case bodySkin(BodySkinKey)
    case skinRefinement(SkinRefinementKey)
    case faceShape(FaceShapeKey)
    case feature(FeatureKey)
    case bodyShape(BodyShapeKey)
    case tool(EditorTool)

    static var doubleChin: Self { .faceShape(.doubleChin) }
    static var sideChest: Self { .bodyShape(.sideChest) }
    var id: Self { self }

    var title: String {
        switch self {
        case .skin: return UserMessage.skinSmoothing
        case .bodySkin(let key): return UserMessage.bodySkinTitle(key)
        case .skinRefinement(let key): return UserMessage.skinRefinementTitle(key)
        case .faceShape(let key): return UserMessage.faceShapeTitle(key)
        case .feature(let key): return UserMessage.featureTitle(key)
        case .bodyShape(let key): return UserMessage.bodyShapeTitle(key)
        case .tool(let tool): return tool.title
        }
    }

    static var all: [Self] {
        [.skin] + BodySkinKey.allCases.map(Self.bodySkin) + SkinRefinementKey.allCases.map(Self.skinRefinement)
            + FaceShapeKey.allCases.map(Self.faceShape) + FeatureKey.allCases.map(Self.feature)
            + BodyShapeKey.allCases.map(Self.bodyShape)
            + [EditorTool.look, .adjust, .makeup, .background, .crop, .retouch, .warp].map(Self.tool)
    }
}
