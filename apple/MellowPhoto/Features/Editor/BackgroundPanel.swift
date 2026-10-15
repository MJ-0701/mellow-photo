import MellowEditing
import SwiftUI

/// 배경 도구. 사람은 그대로 두고 인물 영역 밖을 흐린다.
/// 사람을 찾지 못했거나 인물 분석이 실패하면 안내를 보이고 슬라이더는 값이 보이게 끈다(프리셋으로 들어온 값을 확인할 수 있다).
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
        .disabled(availability != .ready)
        Text(UserMessage.backgroundHint).font(.caption).foregroundStyle(.secondary)
    }
}
