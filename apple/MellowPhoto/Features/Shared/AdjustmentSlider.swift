import MellowEditing
import SwiftUI

struct AdjustmentSlider: View {
    @Environment(AppModel.self) private var model
    let title: String
    let value: Double
    let range: ClosedRange<Double>
    var snapsToZero = false
    let change: (Double) -> EditChange

    var body: some View {
        VStack(spacing: 5) {
            HStack {
                Text(title)
                Spacer()
                Text(value, format: .number.precision(.fractionLength(2))).monospacedDigit().foregroundStyle(.secondary)
            }
            .font(.caption)
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
