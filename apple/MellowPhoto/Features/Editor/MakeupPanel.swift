import MellowEditing
import MellowShared
import SwiftUI

/// 메이크업 도구. 룩 칩(없음 + 5개)이 위, 부위 탭이 아래, 부위마다 색 칩과 강도 슬라이더(스펙 7).
/// 색만 바꾸므로 수동 편집이 있어도 끄지 않는다. 얼굴이 없거나 특징점이 없으면 안내를 보인다.
/// 얼굴 분석이 실패하면 없음 칩만 남기고 끈다(canAdjustMakeup).
/// 얼굴이 있으면 맨 위에 대상 칩을 두고, 대상 층까지 겹친 값을 보인다.
struct MakeupPanel: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        let makeup = model.scopedValues.makeup
        let catalog = model.makeupCatalog
        let part = model.makeupPart
        let overridden = model.overriddenKeys
        switch model.faceAvailability {
        case .ready:
            EmptyView()
        case .noLandmarks:
            Text(UserMessage.noLandmarksHint).font(.caption).foregroundStyle(.secondary)
        case .noFace:
            Label(UserMessage.noFaceDetected, systemImage: "person.crop.rectangle.badge.questionmark")
        case .unavailable(let failure):
            Label(UserMessage.faceAnalysisUnavailableTitle, systemImage: "exclamationmark.triangle")
            Text(UserMessage.text(for: failure)).font(.caption).foregroundStyle(.secondary)
        }
        // 얼굴이 없거나 분석이 실패한 사진에는 고를 사람이 없다.
        if !model.faces.isEmpty {
            TargetChips()
        }
        if catalog.isEmpty {
            Text(UserMessage.makeupCatalogUnavailable).font(.caption).foregroundStyle(.secondary)
        }
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                lookChip(id: nil, name: UserMessage.makeupNoLook, selected: isNoLook(makeup, overridden: overridden))
                ForEach(catalog.looks) { look in
                    lookChip(id: look.id, name: look.name, selected: makeup.lookID == look.id)
                        .disabled(!model.canAdjustMakeup)
                }
            }
            .padding(.vertical, 4)
        }
        .scrollIndicators(.hidden)
        Picker(UserMessage.makeupPartsLabel, selection: $model.makeupPart) {
            ForEach(MakeupPart.allCases, id: \.self) { Text(UserMessage.makeupPartTitle($0)).tag($0) }
        }
        .pickerStyle(.segmented)
        if part.hasColor {
            ScrollView(.horizontal) {
                HStack(spacing: 10) {
                    ForEach(catalog.colors(for: part)) { color in
                        swatch(color, part: part, selected: makeup.colorID(of: part) == color.id)
                    }
                }
                .padding(.vertical, 4)
            }
            .scrollIndicators(.hidden)
            .disabled(!model.canAdjustMakeup)
        }
        AdjustmentSlider(
            title: UserMessage.makeupIntensity, value: makeup.intensity(of: part), range: EditingPolicy.unitRange,
            isOverridden: overridden.contains(.makeupPart(part)),
            onReset: { model.resetOverrides([.makeupPart(part)]) }
        ) { .makeupIntensity(part, $0) }
        .disabled(!model.canAdjustMakeup)
        Text(UserMessage.makeupHint).font(.caption).foregroundStyle(.secondary)
    }

    /// "없음" 칩 선택 조건.
    /// 전체는 메이크업이 기본값일 때다.
    /// 그룹·사람은 그 층이 모든 부위를 덮어써 빈 메이크업으로 만들었을 때다(상속으로 비어 보이는 것과 구분).
    private func isNoLook(_ makeup: MakeupAdjustments, overridden: Set<PortraitKey>) -> Bool {
        if model.beautyTarget == .all {
            return makeup == MakeupAdjustments()
        }
        return overridden.isSuperset(of: PortraitKey.makeup) && !makeup.hasEffect
    }

    private func lookChip(id: String?, name: String, selected: Bool) -> some View {
        Button {
            model.applyMakeupLook(id: id)
        } label: {
            Text(name).font(.caption)
                .padding(.horizontal, Theme.makeupChipPadding)
                .frame(minWidth: Theme.makeupChipSize.width, minHeight: Theme.makeupChipSize.height)
                .background(
                    selected
                        ? Theme.accent.opacity(Theme.accentFillOpacity)
                        : Color.secondary.opacity(Theme.chipFillOpacity),
                    in: Capsule()
                )
                .overlay(Capsule().stroke(selected ? Theme.accent : .clear, lineWidth: Theme.chipStrokeWidth))
                .foregroundStyle(selected ? Theme.accent : .primary)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(name)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    /// 같은 색 칩을 다시 누르면 색을 뺀다.
    private func swatch(_ color: MakeupColor, part: MakeupPart, selected: Bool) -> some View {
        Button {
            model.edit(.makeupColor(part, selected ? nil : color.id))
        } label: {
            VStack(spacing: 4) {
                Circle().fill(Color(red: color.red, green: color.green, blue: color.blue))
                    .frame(width: Theme.makeupSwatchSize, height: Theme.makeupSwatchSize)
                    .overlay(Circle().stroke(selected ? Theme.accent : .clear, lineWidth: Theme.chipStrokeWidth))
                Text(color.name).font(.caption2).foregroundStyle(selected ? Theme.accent : .secondary)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(color.name)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
