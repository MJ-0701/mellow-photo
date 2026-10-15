/// 뷰티 도구의 하위 탭.
enum BeautyTab: CaseIterable, Identifiable {
    case skin
    case face
    case features

    var id: Self { self }

    var title: String {
        switch self {
        case .skin: return UserMessage.beautyTabSkin
        case .face: return UserMessage.beautyTabFace
        case .features: return UserMessage.beautyTabFeatures
        }
    }
}
