enum EditorTool: CaseIterable, Identifiable, Hashable {
    case quick
    case region
    case look
    case crop
    case adjust
    case beauty
    case makeup
    case body
    case background
    case retouch
    case warp

    var id: Self { self }

    /// 화면에 보이는 도구 이름. 문구는 UserMessage에 둔다.
    var title: String {
        switch self {
        case .quick: return UserMessage.toolQuick
        case .region: return "부위 선택"
        case .look: return UserMessage.toolLook
        case .crop: return UserMessage.toolCrop
        case .adjust: return UserMessage.toolAdjust
        case .beauty: return UserMessage.toolBeauty
        case .makeup: return UserMessage.toolMakeup
        case .body: return UserMessage.toolBody
        case .background: return UserMessage.toolBackground
        case .retouch: return UserMessage.toolRetouch
        case .warp: return UserMessage.toolWarp
        }
    }

    var symbol: String {
        switch self {
        case .quick: return "wand.and.stars"
        case .region: return "hand.point.up.left"
        case .look: return "camera.filters"
        case .crop: return "crop.rotate"
        case .adjust: return "slider.horizontal.3"
        case .beauty: return "face.smiling"
        case .makeup: return "paintbrush.pointed"
        case .body: return "figure.stand"
        case .background: return "camera.aperture"
        case .retouch: return "bandage"
        case .warp: return "arrow.up.left.and.arrow.down.right"
        }
    }

    /// 캔버스가 탭·드래그를 받는 도구.
    /// 뷰티·메이크업은 얼굴을 탭해 대상을 고른다.
    var usesCanvasTouch: Bool {
        switch self {
        case .region, .retouch, .warp, .beauty, .makeup: return true
        case .quick, .look, .crop, .adjust, .body, .background: return false
        }
    }

    /// 캔버스에서 탭만 받는 도구(대상 고르기).
    /// 드래그는 확대한 사진 이동에 남긴다.
    var selectsTargetByTap: Bool {
        self == .region || self == .beauty || self == .makeup
    }
}
