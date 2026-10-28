import SwiftUI

/// 선택 전에는 사진을 바꾸지 않는다. 각 단추는 고정된 요청 하나만 확인한다.
struct OneTouchDecisionSheet: View {
    @Environment(AppModel.self) private var model
    let decision: AppModel.OneTouchDecision
    let keep: () -> Void
    let replace: () -> Void
    let cancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            #if DEBUG
                if model.isOneTouchUIFixture {
                    Text("합성 원터치 검사").font(.caption2)
                        .accessibilityIdentifier("oneTouch.choice.fixture")
                        .accessibilityValue(model.oneTouchFixtureSnapshot)
                }
            #endif
            Text(UserMessage.oneTouchDecisionTitle).font(.headline)
                .accessibilityIdentifier("oneTouch.choice.title")
            Text(
                UserMessage.oneTouchDecisionTarget(decision.target) + " · 요청 강도 "
                    + OneTouchRow.strengthText(for: decision.strength)
            )
            .font(.subheadline)
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text(UserMessage.oneTouchProtected(decision.keepResult) ?? "")
                    Text("이번 원터치는 아직 적용 전이에요. 적용 방식을 골라주세요.")
                    VStack(alignment: .leading, spacing: 6) {
                        Text(UserMessage.oneTouchDecisionKeep).font(.subheadline.bold())
                        Text(UserMessage.oneTouchDecisionChanges(decision.keepResult))
                            .accessibilityIdentifier("oneTouch.choice.keepSummary")
                        Text("개인 조정은 그대로 두고 나머지 원터치 설정을 적용해요.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        Text(UserMessage.oneTouchReplacePersonal).font(.subheadline.bold())
                        Text(UserMessage.oneTouchDecisionChanges(decision.replaceResult))
                            .accessibilityIdentifier("oneTouch.choice.replaceSummary")
                        Text("이 대상에서 적용 가능한 피부·눈·입·메이크업 값만 바꿔요. 사진 전체의 밝기·색감, 배경, 얼굴형·체형은 유지해요.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                .font(.callout)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
            }
            .accessibilityIdentifier("oneTouch.choice.scroll")
            VStack(spacing: 10) {
                Button(UserMessage.oneTouchDecisionKeep, action: keep)
                    .buttonStyle(.bordered)
                    .accessibilityIdentifier("oneTouch.choice.keep")
                Button(UserMessage.oneTouchReplacePersonal, action: replace)
                    .buttonStyle(.borderedProminent).tint(Theme.accent).foregroundStyle(Theme.canvas)
                    .accessibilityIdentifier("oneTouch.choice.replace")
                Button("취소", role: .cancel, action: cancel)
                    .accessibilityIdentifier("oneTouch.choice.cancel")
            }
            .frame(maxWidth: .infinity)
        }
        .padding(20)
        .frame(minWidth: 260, idealWidth: 400, maxWidth: 440, minHeight: 400)
        #if os(iOS)
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        #endif
    }
}
