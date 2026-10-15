enum EditorTool: CaseIterable, Identifiable {
    case look
    case crop
    case adjust
    case beauty
    case retouch
    case warp

    var id: Self { self }

    /// 화면에 보이는 도구 이름. 문구는 UserMessage에 둔다.
    var title: String {
        switch self {
        case .look: return UserMessage.toolLook
        case .crop: return UserMessage.toolCrop
        case .adjust: return UserMessage.toolAdjust
        case .beauty: return UserMessage.toolBeauty
        case .retouch: return UserMessage.toolRetouch
        case .warp: return UserMessage.toolWarp
        }
    }

    var symbol: String {
        switch self {
        case .look: return "camera.filters"
        case .crop: return "crop.rotate"
        case .adjust: return "slider.horizontal.3"
        case .beauty: return "face.smiling"
        case .retouch: return "bandage"
        case .warp: return "arrow.up.left.and.arrow.down.right"
        }
    }

    var usesCanvasTouch: Bool { self == .retouch || self == .warp }
}
