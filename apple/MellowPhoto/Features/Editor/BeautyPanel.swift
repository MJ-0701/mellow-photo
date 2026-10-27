import MellowEditing
import MellowShared
import SwiftUI

/// 뷰티 도구(G4 스펙 4절).
/// 위에서 아래로 대상 칩 → 원터치 버튼 + 강도 → 안내 → 세부 조정(접기, 기본 접힘) → 특징점 없음 안내.
/// 세부 조정은 탭마다 대상 층까지 겹친 값을 슬라이더로 보여준다.
/// 현재 대상 층이 덮어쓴 항목은 점과 재설정 메뉴를 단다(전체 대상에는 없다).
/// 원터치가 쓴 항목은 제목 옆에 "원터치" 꼬리표를 단다.
struct BeautyPanel: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        let recipe = model.currentRecipe
        let portrait = model.scopedValues.portrait
        let availability = model.faceAvailability
        switch availability {
        case .unavailable(let failure):
            Label(UserMessage.faceAnalysisUnavailableTitle, systemImage: "exclamationmark.triangle")
            Text(UserMessage.text(for: failure)).font(.caption).foregroundStyle(.secondary)
        case .noFace:
            Label(UserMessage.noFaceDetected, systemImage: "person.crop.rectangle.badge.questionmark")
            Text(UserMessage.noFaceHint).font(.caption).foregroundStyle(.secondary)
        case .ready, .noLandmarks:
            // iPhone 조절 영역(200pt)에 칩·원터치 줄·"세부 조정" 머리가 스크롤 없이 보이게 간격을 좁힌다.
            VStack(alignment: .leading, spacing: Theme.beautyPanelSpacing) {
                // 성별 안내는 원터치 줄이, 대상 안내는 세부 조정이 한다.
                TargetChips(showsHints: false)
                OneTouchRow()
                DisclosureGroup(UserMessage.detailAdjustments, isExpanded: $model.showsDetailAdjustments) {
                    VStack(alignment: .leading, spacing: 16) {
                        // 점 표시를 설명하는 안내라 세부 슬라이더 위에 둔다.
                        if let hint = UserMessage.scopeHint(for: model.beautyTarget) {
                            Text(hint).font(.caption2).foregroundStyle(.secondary)
                        }
                        Picker(UserMessage.beautyTabsLabel, selection: $model.beautyTab) {
                            ForEach(BeautyTab.allCases) { Text($0.title).tag($0) }
                        }
                        .pickerStyle(.segmented)
                        switch model.beautyTab {
                        case .skin: skinControls(portrait.skin).disabled(model.hasEmptyPortraitGroup)
                        case .face: faceControls(portrait.face).disabled(model.hasEmptyPortraitGroup)
                        case .features: featureControls(portrait.features).disabled(model.hasEmptyPortraitGroup)
                        case .skinTone: skinToneControls(recipe.bodySkin)
                        }
                    }
                    .padding(.top, 8)
                }
                // 세부 조정 머리가 첫 화면에 남도록 그 아래에 둔다.
                if availability == .noLandmarks {
                    Text(UserMessage.noLandmarksHint).font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }

    /// 피부 보정·자동 잡티 아래에 정밀 키 전부(SkinRefinementKey.allCases 순서).
    /// 붉은기만 가운데 0인 양방향이고 0 근처에서 0에 붙는다.
    @ViewBuilder
    private func skinControls(_ skin: SkinAdjustments) -> some View {
        let overridden = model.overriddenKeys
        AdjustmentSlider(
            title: UserMessage.skinSmoothing, value: skin.smoothing, range: EditingPolicy.unitRange,
            isOverridden: overridden.contains(.skinSmoothing), onReset: reset(.skinSmoothing),
            tag: tag(.skinSmoothing)
        ) { .skinSmoothing($0) }
        .id(RetouchDestination.skin)
        Toggle(isOn: Binding(get: { skin.autoBlemish }, set: { model.edit(.autoBlemish($0)) })) {
            HStack(spacing: 4) {
                if overridden.contains(.autoBlemish) {
                    OverrideDot()
                }
                Text(UserMessage.autoBlemish)
                if let tag = tag(.autoBlemish) {
                    TagLabel(text: tag)
                }
            }
        }
        .font(.caption)
        .overrideResetMenu(isOverridden: overridden.contains(.autoBlemish), onReset: reset(.autoBlemish))
        .overrideAccessibility(isOverridden: overridden.contains(.autoBlemish), onReset: reset(.autoBlemish))
        Text(UserMessage.skinHint).font(.caption).foregroundStyle(.secondary)
        Divider().opacity(0.4)
        ForEach(SkinRefinementKey.allCases, id: \.self) { key in
            let range = EditingPolicy.skinRefinementRange(key)
            AdjustmentSlider(
                title: UserMessage.skinRefinementTitle(key), value: skin[key], range: range,
                snapsToZero: range.lowerBound < 0, isOverridden: overridden.contains(.skinRefinement(key)),
                onReset: reset(.skinRefinement(key)), tag: tag(.skinRefinement(key))
            ) { .skinRefinement(key, $0) }
            .id(RetouchDestination.skinRefinement(key))
        }
        Text(UserMessage.skinRefinementHint).font(.caption).foregroundStyle(.secondary)
    }

    /// 얼굴형 슬라이더 10개. 미소만 0…1, 나머지는 가운데 0인 양방향이고 0 근처에서 0에 붙는다.
    @ViewBuilder
    private func faceControls(_ face: FaceShapeAdjustments) -> some View {
        let overridden = model.overriddenKeys
        ForEach(FaceShapeKey.allCases, id: \.self) { key in
            let range = EditingPolicy.faceShapeRange(key)
            AdjustmentSlider(
                title: UserMessage.faceShapeTitle(key), value: face[key], range: range,
                snapsToZero: range.lowerBound < 0, isOverridden: overridden.contains(.faceShape(key)),
                onReset: reset(.faceShape(key))
            ) { .faceShape(key, $0) }
            .id(RetouchDestination.faceShape(key))
            .disabled(model.isGeometryLocked)
        }
        Text(model.isGeometryLocked ? UserMessage.geometryLocked : UserMessage.faceHint)
            .font(.caption).foregroundStyle(.secondary)
    }

    /// 눈 또렷하게·치아 미백·입술 생기 0…1. 색만 바꾸므로 수동 편집이 있어도 잠기지 않는다.
    @ViewBuilder
    private func featureControls(_ features: FeatureAdjustments) -> some View {
        let overridden = model.overriddenKeys
        ForEach(FeatureKey.allCases, id: \.self) { key in
            AdjustmentSlider(
                title: UserMessage.featureTitle(key), value: features[key], range: EditingPolicy.unitRange,
                isOverridden: overridden.contains(.feature(key)), onReset: reset(.feature(key)),
                tag: tag(.feature(key))
            ) { .feature(key, $0) }
            .id(RetouchDestination.feature(key))
        }
        Text(UserMessage.featureHint).font(.caption).foregroundStyle(.secondary)
    }

    /// 보이는 피부 전체의 밝기·톤·매끄럽게.
    /// 맨 위에 사람 영역·기준 얼굴 상태 줄을 보인다.
    /// 슬라이더는 사람 영역이 있거나 얼굴 둘레 대체 영역을 쓸 때 켠다.
    @ViewBuilder
    private func skinToneControls(_ bodySkin: BodySkinAdjustments) -> some View {
        Text(UserMessage.bodySkinStatus(model.bodySkinStatus)).font(.caption).foregroundStyle(.secondary)
        ForEach(BodySkinKey.allCases, id: \.self) { key in
            let range = EditingPolicy.bodySkinRange(key)
            AdjustmentSlider(
                title: UserMessage.bodySkinTitle(key), value: bodySkin[key], range: range,
                snapsToZero: range.lowerBound < 0,
                tag: model.isOneTouchTagged(key) ? UserMessage.oneTouchTag : nil
            ) { .bodySkin(key, $0) }
            .id(RetouchDestination.bodySkin(key))
            .disabled(!model.canAdjustBodySkin(key))
        }
        Text(UserMessage.bodySkinHint).font(.caption).foregroundStyle(.secondary)
    }

    /// 원터치가 쓴 묶인 키이고 현재 대상 층에 표시가 있으면 "원터치".
    private func tag(_ key: PortraitKey) -> String? {
        model.isOneTouchTagged(key) ? UserMessage.oneTouchTag : nil
    }

    /// 현재 대상 층에서 그 키만 상속으로 되돌린다.
    private func reset(_ key: PortraitKey) -> () -> Void {
        { model.resetOverrides([key]) }
    }
}
