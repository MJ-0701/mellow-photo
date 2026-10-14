import SwiftUI

struct PortraitPanel: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let recipe = model.currentRecipe
        if let failure = model.selectedInfo?.faceAnalysisFailure {
            Label("자동 얼굴 분석을 사용할 수 없어요", systemImage: "exclamationmark.triangle")
            Text(UserMessage.text(for: failure)).font(.caption).foregroundStyle(.secondary)
        } else if model.faces.isEmpty {
            Label("감지된 얼굴이 없어요", systemImage: "person.crop.rectangle.badge.questionmark")
            Text("정면에 가까운 사진을 선택하거나 잡티·변형 도구를 직접 사용해 주세요.").font(.caption).foregroundStyle(.secondary)
        } else {
            Picker(
                "얼굴 \(model.faces.count)명",
                selection: Binding(
                    get: { recipe.portrait.targetFace ?? -1 }, set: { model.edit(.targetFace($0 == -1 ? nil : $0)) })
            ) {
                Text("모든 얼굴").tag(-1)
                ForEach(model.faces.indices, id: \.self) { Text("왼쪽부터 \($0 + 1)번째").tag($0) }
            }
            .disabled(model.isGeometryLocked)
            AdjustmentSlider(title: "피부 정돈", value: recipe.portrait.skinSmoothing, range: 0...1) { .skinSmoothing($0) }
            AdjustmentSlider(title: "얼굴 미세 조정", value: recipe.portrait.faceSlim, range: 0...1) { .faceSlim($0) }
                .disabled(model.isGeometryLocked)
            Text(
                model.isGeometryLocked
                    ? UserMessage.geometryLocked : "얼굴 형태를 먼저 조정한 뒤 잡티를 보정해 주세요. 피부 정돈은 부드러운 필터이며 자동 잡티 제거는 아닙니다."
            )
            .font(.caption).foregroundStyle(.secondary)
        }
    }
}
