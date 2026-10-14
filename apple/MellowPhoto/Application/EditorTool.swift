enum EditorTool: CaseIterable, Identifiable {
    case color
    case portrait
    case retouch
    case warp

    var id: Self { self }

    /// 화면에 보이는 도구 이름. 문구는 UserMessage에 둔다.
    var title: String {
        switch self {
        case .color: return UserMessage.toolColor
        case .portrait: return UserMessage.toolPortrait
        case .retouch: return UserMessage.toolRetouch
        case .warp: return UserMessage.toolWarp
        }
    }

    var symbol: String {
        switch self {
        case .color: return "slider.horizontal.3"
        case .portrait: return "face.smiling"
        case .retouch: return "bandage"
        case .warp: return "arrow.up.left.and.arrow.down.right"
        }
    }

    var usesCanvasTouch: Bool { self == .retouch || self == .warp }
}
