import MellowEditing
import SwiftUI

/// 배경 도구. 사람은 그대로 두고 인물 영역 밖을 흐린다.
/// 사람을 찾지 못했거나 인물 분석이 실패하면 안내를 보이고 슬라이더는 끈다. 프리셋으로 들어온 값이 있으면 0으로 되돌릴 수 있게 켠다.
struct BackgroundPanel: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let availability = model.backgroundAvailability
        switch availability {
        case .ready:
            EmptyView()
        case .noPerson:
            Label(UserMessage.noPersonDetected, systemImage: "person.crop.rectangle.badge.questionmark")
            Text(UserMessage.noPersonHint).font(.caption).foregroundStyle(.secondary)
        case .unavailable(let failure):
            Label(UserMessage.personAnalysisUnavailableTitle, systemImage: "exclamationmark.triangle")
            Text(UserMessage.text(for: failure)).font(.caption).foregroundStyle(.secondary)
        }
        AdjustmentSlider(
            title: UserMessage.backgroundBlur, value: model.currentRecipe.background.blur,
            range: EditingPolicy.unitRange
        ) { .backgroundBlur($0) }
        .disabled(!model.canAdjustBackgroundBlur)
        Text(UserMessage.backgroundHint).font(.caption).foregroundStyle(.secondary)
    }
}
