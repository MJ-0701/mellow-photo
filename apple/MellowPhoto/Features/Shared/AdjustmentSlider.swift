import MellowEditing
import SwiftUI

struct AdjustmentSlider: View {
    @Environment(AppModel.self) private var model
    let title: String
    let value: Double
    let range: ClosedRange<Double>
    let change: (Double) -> EditChange

    var body: some View {
        VStack(spacing: 5) {
            HStack {
                Text(title)
                Spacer()
                Text(value, format: .number.precision(.fractionLength(2))).monospacedDigit().foregroundStyle(.secondary)
            }
            .font(.caption)
            Slider(value: Binding(get: { value }, set: { model.edit(change($0)) }), in: range) { editing in
                if editing {
                    model.beginSliderEdit()
                } else {
                    model.endSliderEdit()
                }
            }
            .accessibilityLabel(title)
        }
    }
}
