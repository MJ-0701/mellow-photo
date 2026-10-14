enum EditorTool: String, CaseIterable, Identifiable {
    case color = "색감"
    case portrait = "인물"
    case retouch = "잡티"
    case warp = "변형"

    var id: String { rawValue }

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
