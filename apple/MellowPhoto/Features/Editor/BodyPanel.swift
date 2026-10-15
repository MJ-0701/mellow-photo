import MellowEditing
import MellowShared
import SwiftUI

/// 체형 도구. 가장 큰 사람 한 명의 관절점으로 다리·허리·몸 전체·팔·허벅지·어깨·목을 바꾼다.
/// 관절을 찾지 못했거나 체형 분석이 실패하면 안내를 보이고 슬라이더는 값이 보이게 끈다(프리셋으로 들어온 값을 확인할 수 있다).
/// 수동 잡티·변형이 있으면 얼굴형처럼 잠긴다.
struct BodyPanel: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let availability = model.bodyAvailability
        let shape = model.currentRecipe.body
        switch availability {
        case .ready:
            EmptyView()
        case .noBody:
            Label(UserMessage.noBodyDetected, systemImage: "figure.stand")
            Text(UserMessage.noBodyHint).font(.caption).foregroundStyle(.secondary)
        case .unavailable(let failure):
            Label(UserMessage.bodyAnalysisUnavailableTitle, systemImage: "exclamationmark.triangle")
            Text(UserMessage.text(for: failure)).font(.caption).foregroundStyle(.secondary)
        }
        ForEach(BodyShapeKey.allCases, id: \.self) { key in
            let range = EditingPolicy.bodyShapeRange(key)
            AdjustmentSlider(
                title: UserMessage.bodyShapeTitle(key), value: shape[key], range: range,
                snapsToZero: range.lowerBound < 0
            ) { .bodyShape(key, $0) }
            .disabled(availability != .ready || model.isGeometryLocked)
        }
        Text(model.isGeometryLocked ? UserMessage.geometryLocked : UserMessage.bodyHint)
            .font(.caption).foregroundStyle(.secondary)
    }
}
