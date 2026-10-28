import MellowEditing
import MellowShared
import SwiftUI

/// 요청 강도와 실제 해석 결과를 분리한다. 드래그는 요청값만 바꾸고 종료 때 한 번 적용한다.
struct OneTouchRow: View {
    @Environment(AppModel.self) private var model
    @State private var requestDrag: UUID?
    var fixedTarget: AppModel.BeautyTarget? = nil
    var buttonIdentifier = "oneTouch.apply"

    var body: some View {
        let target = fixedTarget ?? model.beautyTarget
        let strength = model.requestedOneTouchStrength(for: target)
        // 0의 기본 동작은 상속 복귀다. 개인 보호 키 안내는 양의 제안으로 별도 확인한다.
        let proposal = model.planOneTouchApplication(
            strength: strength > 0 ? strength : OneTouchBundle.maximumStrength,
            replacingPersonal: false, target: target)?.result
        let feedback = model.oneTouchFeedback(for: target)
        VStack(alignment: .leading, spacing: 6) {
            #if DEBUG
                if model.isOneTouchUIFixture {
                    Text("합성 원터치 검사").font(.caption2)
                        .accessibilityIdentifier("oneTouch.fixture")
                        .accessibilityValue(model.oneTouchFixtureSnapshot)
                }
            #endif
            HStack(alignment: .bottom, spacing: 12) {
                button(target)
                slider(target, strength: strength, context: model.portraitPurposeContext)
            }
            Text(UserMessage.portraitCount(model.portraitFaceCount(for: target)))
                .font(.caption).foregroundStyle(.secondary)
            if let proposal, let protection = UserMessage.oneTouchProtected(proposal) {
                Text(protection).font(.caption).foregroundStyle(.secondary)
                    .accessibilityIdentifier(buttonIdentifier + ".protected")
            }
            if model.isEmptyGenderGroup(target) {
                Text(UserMessage.emptyPortraitGroup).font(.caption2).foregroundStyle(.secondary)
                if model.hasStoredOneTouchValues(for: target) {
                    Button("이 그룹 원터치 지우기") { model.clearOneTouchInheritance(for: target) }
                        .font(.caption)
                        .accessibilityIdentifier(buttonIdentifier + ".clear")
                }
            } else if offersReplacement(target, strength: strength, proposal: proposal) {
                Button(UserMessage.oneTouchReplacePersonal) {
                    model.submitOneTouchRequest(for: target, replacingPersonal: true)
                }
                .font(.caption).buttonStyle(.bordered)
                .disabled(model.oneTouchPreparedFaceCount(for: target) == 0)
                .accessibilityIdentifier(buttonIdentifier + ".replace")
            }
            if strength == 0 {
                Text(UserMessage.oneTouchNeutralHint).font(.caption2).foregroundStyle(.secondary)
            }
            if let feedback {
                Text(UserMessage.oneTouchOutcome(feedback)).font(.caption)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier(buttonIdentifier + ".result")
            }
            if let report = feedback?.result ?? proposal {
                reportDetails(report, replacing: feedback?.replacingPersonal == true)
            }
            Text(Self.hint(for: target)).font(.caption2).foregroundStyle(.secondary)
            if let person = model.personChips.first(where: { $0.target == target }), person.gender == nil {
                Text(UserMessage.assignGenderForOneTouch).font(.caption2).foregroundStyle(.secondary)
            }
        }
        .onDisappear {
            model.cancelOneTouchRequestEditing(requestDrag)
            requestDrag = nil
        }
    }

    private func offersReplacement(
        _ target: AppModel.BeautyTarget, strength: Double, proposal: OneTouchApplicationResult?
    ) -> Bool {
        guard model.portraitFaceCount(for: target) > 0 else { return false }
        if strength == 0 { return true }
        switch target {
        case .all, .gender: return proposal?.items.contains { $0.reason == .protectedPersonal } == true
        case .face, .person: return false
        }
    }

    private func button(_ target: AppModel.BeautyTarget) -> some View {
        Button {
            model.submitOneTouchRequest(for: target)
        } label: {
            Label(UserMessage.oneTouch, systemImage: Self.buttonSymbol)
                .frame(minWidth: Theme.oneTouchButtonMinWidth)
        }
        .buttonStyle(.borderedProminent).tint(Theme.accent).foregroundStyle(Theme.canvas)
        .fixedSize().accessibilityIdentifier(buttonIdentifier)
        .disabled(model.isEmptyGenderGroup(target))
    }

    private func slider(_ target: AppModel.BeautyTarget, strength: Double, context: UUID) -> some View {
        VStack(spacing: 5) {
            HStack {
                Text(UserMessage.oneTouchRequestStrength)
                Spacer()
                Text(Self.strengthText(for: strength)).monospacedDigit().foregroundStyle(.secondary)
            }
            .font(.caption)
            Slider(
                value: Binding(
                    get: { model.requestedOneTouchStrength(for: target) },
                    set: {
                        model.setRequestedOneTouchStrength(
                            $0, for: target, expectedContext: context, dragID: requestDrag)
                    }),
                in: 0...OneTouchBundle.maximumStrength
            ) { editing in
                if editing {
                    requestDrag = model.beginOneTouchRequestEditing(for: target, expectedContext: context)
                } else if let id = requestDrag {
                    requestDrag = nil
                    model.endOneTouchRequestEditing(for: target, id: id)
                }
            }
            .disabled(model.isEmptyGenderGroup(target))
            .accessibilityLabel("원터치 요청 강도")
            .accessibilityValue(Self.strengthText(for: strength))
            .accessibilityHint("강도를 고른 뒤 원터치 보정으로 적용할 수도 있어요.")
            .accessibilityIdentifier(buttonIdentifier + ".request")
        }
    }

    @ViewBuilder
    private func reportDetails(_ report: OneTouchApplicationResult, replacing: Bool) -> some View {
        let protected = report.items.filter { $0.reason == .protectedPersonal }
        let unavailable = report.unavailableForRenderingKeys
        if !protected.isEmpty || !unavailable.isEmpty {
            DisclosureGroup("적용 범위 보기") {
                Text(UserMessage.oneTouchRequestHint).font(.caption2).foregroundStyle(.secondary)
                if !protected.isEmpty {
                    Text("개인 조정 유지: " + keyNames(protected)).font(.caption2)
                }
                if !unavailable.isEmpty {
                    Text("이 사진에서 보정할 수 없는 항목: " + keyNames(unavailable)).font(.caption2)
                    Text(
                        replacing
                            ? "개인 교체는 이 항목의 기존 값을 유지해요."
                            : "기본 적용은 이 항목의 설정값도 저장할 수 있지만, 이 사진에서 효과를 확인할 수 없어요."
                    )
                    .font(.caption2).foregroundStyle(.secondary)
                }
            }
            .font(.caption).fixedSize(horizontal: false, vertical: true)
        }
    }

    private func keyNames(_ items: [OneTouchApplicationResult.Item]) -> String {
        Set(items.map { UserMessage.oneTouchKeyTitle($0.key) }).sorted().joined(separator: ", ")
    }

    static func strengthText(for strength: Double?) -> String {
        strength.map { String(format: "%.2f", $0) } ?? UserMessage.strengthUnset
    }
    static func hint(for target: AppModel.BeautyTarget) -> String {
        switch target {
        case .all: return UserMessage.oneTouchHintAll
        case .gender: return UserMessage.oneTouchHintGroup
        case .face, .person: return UserMessage.oneTouchHintPerson
        }
    }
    private static var buttonSymbol: String {
        if #available(iOS 18, macOS 15, *) { return "wand.and.sparkles" }
        return "wand.and.stars"
    }
}
