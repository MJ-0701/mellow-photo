import MellowEditing
import MellowShared
import SwiftUI

/// 뷰티 도구.
/// 대상 선택은 탭 위에 두고, 탭마다 대상 층까지 겹친 값을 슬라이더로 보여준다.
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
            BeautyTargetPicker()
            if availability == .noLandmarks {
                Text(UserMessage.noLandmarksHint).font(.caption).foregroundStyle(.secondary)
            }
            Picker(UserMessage.beautyTabsLabel, selection: $model.beautyTab) {
                ForEach(BeautyTab.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            switch model.beautyTab {
            case .skin: skinControls(portrait.skin)
            case .face: faceControls(portrait.face)
            case .features: featureControls(portrait.features)
            case .skinTone: skinToneControls(recipe.bodySkin)
            }
        }
    }

    /// 피부 보정·자동 잡티 아래에 정밀 7개. 붉은기만 가운데 0인 양방향이고 0 근처에서 0에 붙는다.
    @ViewBuilder
    private func skinControls(_ skin: SkinAdjustments) -> some View {
        AdjustmentSlider(title: UserMessage.skinSmoothing, value: skin.smoothing, range: EditingPolicy.unitRange) {
            .skinSmoothing($0)
        }
        Toggle(
            UserMessage.autoBlemish,
            isOn: Binding(get: { skin.autoBlemish }, set: { model.edit(.autoBlemish($0)) })
        )
        .font(.caption)
        Text(UserMessage.skinHint).font(.caption).foregroundStyle(.secondary)
        Divider().opacity(0.4)
        ForEach(SkinRefinementKey.allCases, id: \.self) { key in
            let range = EditingPolicy.skinRefinementRange(key)
            AdjustmentSlider(
                title: UserMessage.skinRefinementTitle(key), value: skin[key], range: range,
                snapsToZero: range.lowerBound < 0
            ) { .skinRefinement(key, $0) }
        }
        Text(UserMessage.skinRefinementHint).font(.caption).foregroundStyle(.secondary)
    }

    /// 얼굴형 슬라이더 10개. 미소만 0…1, 나머지는 가운데 0인 양방향이고 0 근처에서 0에 붙는다.
    @ViewBuilder
    private func faceControls(_ face: FaceShapeAdjustments) -> some View {
        ForEach(FaceShapeKey.allCases, id: \.self) { key in
            let range = EditingPolicy.faceShapeRange(key)
            AdjustmentSlider(
                title: UserMessage.faceShapeTitle(key), value: face[key], range: range,
                snapsToZero: range.lowerBound < 0
            ) { .faceShape(key, $0) }
            .disabled(model.isGeometryLocked)
        }
        Text(model.isGeometryLocked ? UserMessage.geometryLocked : UserMessage.faceHint)
            .font(.caption).foregroundStyle(.secondary)
    }

    /// 눈 또렷하게·치아 미백·입술 생기 0…1. 색만 바꾸므로 수동 편집이 있어도 잠기지 않는다.
    @ViewBuilder
    private func featureControls(_ features: FeatureAdjustments) -> some View {
        ForEach(FeatureKey.allCases, id: \.self) { key in
            AdjustmentSlider(
                title: UserMessage.featureTitle(key), value: features[key], range: EditingPolicy.unitRange
            ) { .feature(key, $0) }
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
                snapsToZero: range.lowerBound < 0
            ) { .bodySkin(key, $0) }
            .disabled(!model.canAdjustBodySkin(key))
        }
        Text(UserMessage.bodySkinHint).font(.caption).foregroundStyle(.secondary)
    }
}

/// 뷰티·메이크업 패널 맨 위 임시 대상 피커(전체 · 성별 그룹 · 사람 n).
/// H3이 대상 칩으로 바꾼다.
/// 대상 전환은 화면 상태라 잠긴 사진에서도 막지 않는다.
struct BeautyTargetPicker: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Picker(
            UserMessage.beautyTargetLabel,
            selection: Binding(get: { model.beautyTarget }, set: { model.setBeautyTarget($0) })
        ) {
            Text(UserMessage.beautyTargetAll).tag(AppModel.BeautyTarget.all)
            ForEach(Gender.allCases, id: \.self) { gender in
                Text(UserMessage.beautyTargetGender(gender)).tag(AppModel.BeautyTarget.gender(gender))
            }
            ForEach(model.faces.indices, id: \.self) { index in
                Text(UserMessage.beautyTargetFace(index + 1)).tag(AppModel.BeautyTarget.face(index))
            }
        }
    }
}
