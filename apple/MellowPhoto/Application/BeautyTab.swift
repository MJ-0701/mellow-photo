/// 뷰티 도구의 하위 탭. 눈·입 탭은 D 단계에서 추가한다.
enum BeautyTab: CaseIterable, Identifiable {
    case skin
    case face

    var id: Self { self }

    var title: String {
        switch self {
        case .skin: return UserMessage.beautyTabSkin
        case .face: return UserMessage.beautyTabFace
        }
    }
}
