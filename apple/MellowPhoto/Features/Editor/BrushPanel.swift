import SwiftUI

struct BrushPanel: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        Text(instruction).font(.subheadline)
        if model.tool == .retouch {
            Button("샘플 위치 다시 고르기") { model.resetCloneSource() }.buttonStyle(.bordered)
            #if os(macOS)
                Text("⌥ Option + 클릭으로도 샘플 위치를 바꿀 수 있습니다.").font(.caption2).foregroundStyle(.secondary)
            #endif
        }
        HStack {
            Text("브러시 크기").font(.caption)
            Slider(value: $model.brushRadius, in: AppModel.Policy.brushRadiusRange).accessibilityLabel("브러시 크기")
        }
        Text(
            model.tool == .retouch
                ? "자동 탐지가 아닌 수동 복제 브러시입니다. 가까운 피부를 샘플로 선택하면 더 자연스러워요." : "배경도 함께 움직일 수 있어요. 조금씩 조정하고 원본과 비교해 주세요."
        )
        .font(.caption).foregroundStyle(.secondary)
        Text("잡티 보정 \(model.currentRecipe.spots.count)회 · 부분 변형 \(model.currentRecipe.warps.count)회")
            .font(.caption2)
            .foregroundStyle(.secondary)
    }

    private var instruction: String {
        if model.tool == .retouch {
            return model.isChoosingCloneSource ? UserMessage.chooseCloneSource : UserMessage.chooseCloneTarget
        }
        return "조정할 부분을 원하는 방향으로 살짝 밀어주세요."
    }
}
