import MellowEditing
import MellowShared
import SwiftUI

/// 뷰티 패널의 원터치 줄: 버튼 + 강도 슬라이더, 그 아래 대상 안내(G4 스펙 4절).
/// 강도는 현재 대상 층의 원터치 표시다.
/// 표시가 없으면 손잡이는 0, 값 자리는 "—"다.
/// 버튼과 슬라이더는 폭과 무관하게 한 줄로 두고 슬라이더가 남는 폭을 쓴다.
/// 폭에 따라 배치를 바꾸면 값 글자가 바뀌는 드래그 중에 슬라이더가 다시 만들어져 드래그가 끊길 수 있다.
struct OneTouchRow: View {
    @Environment(AppModel.self) private var model
    var fixedTarget: AppModel.BeautyTarget? = nil
    var buttonIdentifier = "oneTouch.apply"

    var body: some View {
        let target = fixedTarget ?? model.beautyTarget
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .bottom, spacing: 12) {
                button
                slider
            }
            Text(UserMessage.portraitCount(model.portraitFaceCount(for: target)))
                .font(.caption).foregroundStyle(.secondary)
            if model.isEmptyGenderGroup(target) {
                Text(UserMessage.emptyPortraitGroup).font(.caption2).foregroundStyle(.secondary)
                if (model.oneTouchStrength(for: target) ?? 0) > 0 {
                    Button("이 그룹 원터치 지우기") { model.applyOneTouch(strength: 0, target: target) }
                        .font(.caption)
                }
            }
            Text(Self.hint(for: target)).font(.caption2).foregroundStyle(.secondary)
            if let person = model.personChips.first(where: { $0.target == target }), person.gender == nil {
                Text(UserMessage.assignGenderForOneTouch).font(.caption2).foregroundStyle(.secondary)
            }
        }
    }

    private var button: some View {
        Button {
            model.applyOneTouch(target: fixedTarget)
        } label: {
            Label(UserMessage.oneTouch, systemImage: Self.buttonSymbol)
                .frame(minWidth: Theme.oneTouchButtonMinWidth)
        }
        .buttonStyle(.borderedProminent)
        .tint(Theme.accent)
        .foregroundStyle(Theme.canvas)
        .fixedSize()
        .accessibilityIdentifier(buttonIdentifier)
        .disabled(model.isEmptyGenderGroup(fixedTarget ?? model.beautyTarget))
    }

    private var slider: some View {
        let strength = model.oneTouchStrength(for: fixedTarget ?? model.beautyTarget)
        return VStack(spacing: 5) {
            HStack {
                Text(UserMessage.oneTouchStrength)
                Spacer()
                Text(Self.strengthText(for: strength)).monospacedDigit().foregroundStyle(.secondary)
            }
            .font(.caption)
            Slider(
                value: Binding(get: { strength ?? 0 }, set: { model.applyOneTouch(strength: $0, target: fixedTarget) }),
                in: 0...OneTouchBundle.maximumStrength
            ) { editing in
                if editing {
                    model.beginSliderEdit()
                } else {
                    model.endSliderEdit()
                }
            }
            .disabled(model.isEmptyGenderGroup(fixedTarget ?? model.beautyTarget))
            .accessibilityLabel(UserMessage.oneTouchStrength)
            .accessibilityValue(Self.strengthText(for: strength))
        }
    }

    /// 표시가 없으면 "—", 있으면 소수 둘째 자리.
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

    /// wand.and.sparkles는 iOS 18·macOS 15부터라 그 전에는 비슷한 wand.and.stars를 쓴다.
    private static var buttonSymbol: String {
        if #available(iOS 18, macOS 15, *) {
            return "wand.and.sparkles"
        }
        return "wand.and.stars"
    }
}
