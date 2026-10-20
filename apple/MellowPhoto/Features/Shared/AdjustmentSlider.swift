import MellowEditing
import SwiftUI

struct AdjustmentSlider: View {
    @Environment(AppModel.self) private var model
    let title: String
    let value: Double
    let range: ClosedRange<Double>
    var snapsToZero = false
    /// 현재 대상 층이 이 값을 덮어썼는지.
    /// 제목 앞에 점을 보인다.
    var isOverridden = false
    /// 덮어쓴 값을 상속으로 되돌린다.
    /// 덮어썼을 때만 컨텍스트 메뉴(Mac은 제목 옆 단추)로 보인다.
    var onReset: (() -> Void)? = nil
    let change: (Double) -> EditChange

    var body: some View {
        VStack(spacing: 5) {
            HStack(spacing: 4) {
                if isOverridden {
                    OverrideDot()
                }
                Text(title)
                #if os(macOS)
                    if isOverridden, let onReset {
                        Button(action: onReset) {
                            Image(systemName: "xmark.circle")
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                        .help(UserMessage.overrideReset)
                        .accessibilityLabel(UserMessage.overrideReset)
                    }
                #endif
                Spacer()
                Text(value, format: .number.precision(.fractionLength(2))).monospacedDigit().foregroundStyle(.secondary)
            }
            .font(.caption)
            .overrideResetMenu(isOverridden: isOverridden, onReset: onReset)
            Slider(value: Binding(get: { value }, set: { model.edit(change(snapped($0))) }), in: range) { editing in
                if editing {
                    model.beginSliderEdit()
                } else {
                    model.endSliderEdit()
                }
            }
            .accessibilityLabel(title)
        }
    }

    /// 양방향 슬라이더는 0 근처에서 0으로 붙는다.
    private func snapped(_ newValue: Double) -> Double {
        snapsToZero && abs(newValue) < Theme.bipolarSnapWidth ? 0 : newValue
    }
}

/// 덮어쓴 값 표시 점(강조색).
struct OverrideDot: View {
    var body: some View {
        Circle().fill(Theme.accent).frame(width: Theme.overrideDotSize, height: Theme.overrideDotSize)
            .accessibilityHidden(true)
    }
}

extension View {
    /// 덮어썼고 되돌릴 수 있을 때만 "재설정" 컨텍스트 메뉴 항목을 보인다.
    /// 메뉴는 늘 붙여 둔다.
    /// 덮어쓰기 상태가 바뀌어도 뷰 정체성이 그대로여서 드래그가 끊기지 않는다.
    /// 슬라이더 막대가 아니라 제목 줄에 붙여 길게 누르기가 드래그와 겹치지 않게 한다.
    func overrideResetMenu(isOverridden: Bool, onReset: (() -> Void)?) -> some View {
        contextMenu {
            if isOverridden, let onReset {
                Button(UserMessage.overrideReset, action: onReset)
            }
        }
    }
}
