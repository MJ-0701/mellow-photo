import SwiftUI

/// 분할 비교의 세로 분할선과 손잡이. 드래그 위치는 캔버스 좌표(Theme.canvasCoordinateSpace)로 받아 0…1로 자른다.
struct CompareDivider: View {
    @Environment(AppModel.self) private var model
    /// 화면에 그린 이미지 크기(확대 배율 포함). 분할선은 이 좌표계에 놓인다.
    let size: CGSize

    /// 캔버스 x 위치를 분할 비율로. 폭이 0이면 기본 위치.
    static func fraction(forX x: CGFloat, width: CGFloat) -> Double {
        guard width > 0 else { return AppModel.Policy.compareSplitDefault }
        let range = AppModel.Policy.compareSplitRange
        return min(range.upperBound, max(range.lowerBound, Double(x / width)))
    }

    var body: some View {
        ZStack {
            Rectangle().fill(.white).frame(width: Theme.compareDividerWidth, height: size.height)
            Circle().fill(.white)
                .frame(width: Theme.compareHandleSize, height: Theme.compareHandleSize)
                .overlay(
                    Image(systemName: "arrow.left.and.right").font(.caption2.weight(.bold)).foregroundStyle(.black)
                )
                .shadow(radius: 2)
        }
        .frame(width: Theme.compareHandleSize, height: size.height)
        .contentShape(Rectangle())
        .position(x: size.width * model.compareSplit, y: size.height / 2)
        .gesture(
            DragGesture(minimumDistance: 0, coordinateSpace: .named(Theme.canvasCoordinateSpace))
                .onChanged { value in
                    model.setCompareSplit(Self.fraction(forX: value.location.x, width: size.width))
                }
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(UserMessage.compareDividerLabel)
        .accessibilityValue(model.compareSplit.formatted(.percent.precision(.fractionLength(0))))
        .accessibilityAdjustableAction { direction in
            let step = AppModel.Policy.compareSplitAccessibilityStep
            switch direction {
            case .increment: model.setCompareSplit(model.compareSplit + step)
            case .decrement: model.setCompareSplit(model.compareSplit - step)
            @unknown default: break
            }
        }
    }
}
