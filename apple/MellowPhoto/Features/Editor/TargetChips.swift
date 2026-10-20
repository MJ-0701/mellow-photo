import MellowShared
import SwiftUI

/// 뷰티·메이크업 패널 맨 위의 대상 칩: 전체 · 남성 그룹 · 여성 그룹 · 사람 1…n · 찾지 못한 사람.
/// 칩 줄만 가로로 스크롤한다.
/// 사람 칩에는 성별 메뉴(길게 누르기·오른쪽 클릭)가 있고, 선택된 사람 칩은 아래 상태 줄에 메뉴 단추를 따로 둔다.
/// 대상 전환은 화면 상태라 잠긴 사진에서도 막지 않는다.
struct TargetChips: View {
    @Environment(AppModel.self) private var model
    /// 선택된 사람의 성별이 미지정일 때 성별 지정 안내를 보일지.
    /// 뷰티 패널은 원터치 줄이 같은 안내를 하므로 끈다.
    var showsGenderHint = true

    var body: some View {
        let target = model.beautyTarget
        let chips = model.personChips
        VStack(alignment: .leading, spacing: 6) {
            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    chip(title: UserMessage.targetAll, symbol: "person.3", target: .all)
                    ForEach(Gender.allCases, id: \.self) { gender in
                        chip(
                            title: UserMessage.groupTitle(gender), symbol: Self.groupSymbol(gender),
                            target: .gender(gender))
                    }
                    ForEach(chips) { person in
                        chip(
                            title: Self.title(for: person), symbol: Self.symbolName(for: person),
                            target: person.target, dot: person.overriddenCount > 0,
                            accessibility: Self.accessibilityLabel(for: person)
                        )
                        .contextMenu { PersonGenderMenu(chip: person) }
                    }
                }
                .padding(.vertical, 4)
            }
            .scrollIndicators(.hidden)
            .accessibilityElement(children: .contain)
            .accessibilityLabel(UserMessage.targetLabel)
            if let selected = chips.first(where: { $0.target == target }) {
                HStack {
                    Text(Self.statusLine(for: selected)).font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Menu {
                        PersonGenderMenu(chip: selected)
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .frame(minWidth: Theme.iconButtonHitSize, minHeight: Theme.iconButtonHitSize)
                            .contentShape(Rectangle())
                    }
                    .menuStyle(.button)
                    .buttonStyle(.borderless)
                    .menuIndicator(.hidden)
                    .fixedSize()
                    .accessibilityLabel(UserMessage.personMenu)
                }
                if showsGenderHint, selected.gender == nil {
                    Text(UserMessage.assignGenderHint).font(.caption2).foregroundStyle(.secondary)
                }
            }
            if let hint = UserMessage.scopeHint(for: target) {
                Text(hint).font(.caption2).foregroundStyle(.secondary)
            }
        }
    }

    private func chip(
        title: String, symbol: String, target: AppModel.BeautyTarget, dot: Bool = false, accessibility: String? = nil
    ) -> some View {
        let selected = model.beautyTarget == target
        return Button {
            model.setBeautyTarget(target)
        } label: {
            HStack(spacing: 4) {
                Image(systemName: symbol)
                Text(title).lineLimit(1)
                if dot {
                    OverrideDot()
                }
            }
            .font(.caption)
            .padding(.horizontal, Theme.targetChipPadding)
            .frame(minHeight: Theme.targetChipHeight)
            .background(
                selected ? Theme.accent.opacity(Theme.accentFillOpacity) : Color.secondary.opacity(0.15),
                in: Capsule()
            )
            .overlay(Capsule().stroke(selected ? Theme.accent : .clear, lineWidth: 2))
            .foregroundStyle(selected ? Theme.accent : .primary)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibility ?? title)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    /// 찾은 얼굴은 왼쪽부터 센 번호, 찾지 못한 기록은 안내 문구.
    static func title(for chip: AppModel.PersonChip) -> String {
        chip.faceIndex.map { String($0 + 1) } ?? UserMessage.personUnmatched
    }

    /// 찾지 못한 기록은 경고, 그 외는 성별 출처(지정은 채움, 추정은 테두리, 미지정은 물음표).
    static func symbolName(for chip: AppModel.PersonChip) -> String {
        if chip.isUnmatched {
            return "person.crop.circle.badge.exclamationmark"
        }
        switch chip.source {
        case .manual: return "person.crop.circle.fill"
        case .estimated: return "person.crop.circle"
        case .none: return "person.crop.circle.badge.questionmark"
        }
    }

    /// "사람 n, 성별, 출처, 바꾼 항목 k개". 미지정은 출처가 없고 바꾼 항목이 없으면 그 부분을 뺀다.
    static func accessibilityLabel(for chip: AppModel.PersonChip) -> String {
        let person: String = chip.faceIndex.map { UserMessage.personOrdinal($0 + 1) } ?? UserMessage.personUnmatched
        var parts: [String] = [person]
        parts.append(UserMessage.genderTitle(chip.gender))
        switch chip.source {
        case .manual: parts.append(UserMessage.genderManual)
        case .estimated: parts.append(UserMessage.genderEstimated)
        case .none: break
        }
        if chip.overriddenCount > 0 {
            parts.append(UserMessage.overriddenCount(chip.overriddenCount))
        }
        return parts.joined(separator: ", ")
    }

    /// 선택된 사람 칩 아래 상태 줄.
    /// 접근성 문구와 같다.
    static func statusLine(for chip: AppModel.PersonChip) -> String {
        accessibilityLabel(for: chip)
    }

    /// 치마 모양 기호는 iOS 18·macOS 15부터라 그 전에는 남녀가 같은 기호이고 글자로 구분한다.
    private static func groupSymbol(_ gender: Gender) -> String {
        guard gender == .female else { return "figure.stand" }
        if #available(iOS 18, macOS 15, *) {
            return "figure.stand.dress"
        }
        return "figure.stand"
    }
}

/// 사람 칩의 메뉴: 성별(남성·여성·미지정, 추정이면 표시), 이 대상 초기화, 찾지 못한 기록은 연결·삭제.
/// 항목을 고르면 그 사람을 대상으로 삼은 뒤 바꾼다.
struct PersonGenderMenu: View {
    @Environment(AppModel.self) private var model
    let chip: AppModel.PersonChip

    var body: some View {
        Section(UserMessage.genderLabel) {
            ForEach(Gender.allCases, id: \.self) { gender in
                let estimated = chip.gender == gender && chip.source == .estimated
                Button {
                    model.setBeautyTarget(chip.target)
                    model.setGender(gender)
                } label: {
                    checkLabel(
                        UserMessage.genderMenuTitle(gender, estimated: estimated), checked: chip.gender == gender)
                }
            }
            Button {
                model.setBeautyTarget(chip.target)
                model.setGender(nil)
            } label: {
                checkLabel(UserMessage.genderUnset, checked: chip.gender == nil)
            }
        }
        Button(UserMessage.resetScope) {
            model.setBeautyTarget(chip.target)
            model.resetOverrides()
        }
        .disabled(chip.overriddenCount == 0)
        if chip.isUnmatched, let id = chip.personID {
            let faces = model.unpairedFaceIndices
            if !faces.isEmpty {
                Menu(UserMessage.rebindPerson) {
                    ForEach(faces, id: \.self) { index in
                        Button(UserMessage.rebindToFace(index + 1)) { model.rebindPerson(id, toFace: index) }
                    }
                }
            }
            Button(UserMessage.removePerson, role: .destructive) { model.removePerson(id) }
        }
    }

    @ViewBuilder
    private func checkLabel(_ title: String, checked: Bool) -> some View {
        if checked {
            Label(title, systemImage: "checkmark")
        } else {
            Text(title)
        }
    }
}
