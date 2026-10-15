import MellowShared
import SwiftUI

/// 분위기 프리셋 + 색감 슬라이더 + 디테일 슬라이더.
struct AdjustPanel: View {
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
        Divider().opacity(0.4)
        AdjustmentSlider(title: "하이라이트", value: recipe.detail.highlights, range: -1...1) { .highlights($0) }
        AdjustmentSlider(title: "그림자", value: recipe.detail.shadows, range: -1...1) { .shadows($0) }
        AdjustmentSlider(title: "선명도", value: recipe.detail.sharpness, range: 0...1) { .sharpness($0) }
        AdjustmentSlider(title: "비네팅", value: recipe.detail.vignette, range: 0...1) { .vignette($0) }
    }
}
