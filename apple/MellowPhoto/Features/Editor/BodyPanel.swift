import MellowEditing
import MellowShared
import SwiftUI

/// 체형 도구.
/// 선택한 대상의 관절점으로 다리·허리·몸 전체·팔·허벅지·어깨·목·부유방을 바꾼다.
/// 얼굴이 있으면 맨 위에 뷰티 패널과 같은 대상 칩을 두고, 대상 층까지 겹친 값을 보인다.
/// 부유방은 그 키를 둘 수 있는 대상(여성 그룹·사람)에서만 보이고 다른 대상에서는 안내를 보인다.
/// 대상 몸의 팔이 부유방 높이에서 몸통에 붙어 옆선 점이 없으면 부유방 슬라이더 아래에 안내를 보인다.
/// 현재 대상 층이 덮어쓴 항목은 점과 재설정 메뉴를 단다(전체 대상에는 없다).
/// 관절을 찾지 못했거나 대상 사람의 몸이 없거나 체형 분석이 실패하면 안내를 보이고 슬라이더는 끈다.
/// 프리셋 등으로 들어온 0이 아닌 값은 되돌릴 수 있게 켠다.
/// 수동 잡티·변형이 있으면 얼굴형처럼 대상과 무관하게 잠긴다.
struct BodyPanel: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let availability = model.bodyAvailability
        let shape = model.scopedValues.body
        let overridden = model.overriddenKeys
        // 얼굴이 없는 사진에는 고를 사람이 없다(메이크업 패널과 같다).
        if !model.faces.isEmpty {
            TargetChips()
        }
        switch availability {
        case .ready:
            EmptyView()
        case .noBody:
            Label(UserMessage.noBodyDetected, systemImage: "figure.stand")
            Text(UserMessage.noBodyHint).font(.caption).foregroundStyle(.secondary)
        case .noBodyForTarget:
            Label(UserMessage.noBodyForTarget, systemImage: "figure.stand")
        case .unavailable(let failure):
            Label(UserMessage.bodyAnalysisUnavailableTitle, systemImage: "exclamationmark.triangle")
            Text(UserMessage.text(for: failure)).font(.caption).foregroundStyle(.secondary)
        }
        ForEach(BodyShapeKey.allCases.filter(model.showsBodyShape), id: \.self) { key in
            let range = EditingPolicy.bodyShapeRange(key)
            AdjustmentSlider(
                title: UserMessage.bodyShapeTitle(key), value: shape[key], range: range,
                snapsToZero: range.lowerBound < 0, isOverridden: overridden.contains(.bodyShape(key)),
                onReset: reset(key)
            ) { .bodyShape(key, $0) }
            .disabled(!model.canAdjustBodyShape(key))
            if key == .sideChest, model.showsSideChestArmTouching {
                Text(UserMessage.sideChestArmTouching).font(.caption).foregroundStyle(.secondary)
            }
        }
        if !model.showsBodyShape(.sideChest) {
            Text(UserMessage.sideChestScopeHint).font(.caption).foregroundStyle(.secondary)
        }
        if model.showsLegLengthLargestOnly {
            Text(UserMessage.legLengthLargestOnly).font(.caption).foregroundStyle(.secondary)
        }
        Text(model.isGeometryLocked ? UserMessage.geometryLocked : UserMessage.bodyHint)
            .font(.caption).foregroundStyle(.secondary)
    }

    /// 현재 대상 층에서 그 체형 키만 상속으로 되돌린다.
    private func reset(_ key: BodyShapeKey) -> () -> Void {
        { model.resetOverrides([.bodyShape(key)]) }
    }
}
