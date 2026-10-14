import MellowShared
import SwiftUI

struct ColorPanel: View {
    @Environment(AppModel.self) private var model
    @Binding var presetSheet: Bool

    var body: some View {
        let recipe = model.currentRecipe
        ScrollView(.horizontal) {
            HStack {
                ForEach(BuiltInPresets.all + model.session.presets) { preset in
                    Button(preset.name) { model.applyPreset(preset.values) }
                }
                Button {
                    presetSheet = true
                } label: {
                    Label("저장", systemImage: "plus")
                }
            }
            .buttonStyle(.bordered).font(.caption)
        }
        .scrollIndicators(.hidden)
        AdjustmentSlider(title: "노출", value: recipe.color.exposure, range: -1.5...1.5) { .exposure($0) }
        AdjustmentSlider(title: "대비", value: recipe.color.contrast, range: 0.7...1.3) { .contrast($0) }
        AdjustmentSlider(title: "채도", value: recipe.color.saturation, range: 0...1.5) { .saturation($0) }
        AdjustmentSlider(title: "따뜻함", value: recipe.color.warmth, range: -1...1) { .warmth($0) }
    }
}
