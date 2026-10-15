import MellowEditing
import MellowShared
import SwiftUI

/// 뷰티 도구. 얼굴 선택은 탭 위에 두고, 탭마다 슬라이더를 보여준다.
struct BeautyPanel: View {
    @Environment(AppModel.self) private var model

    /// 얼굴 선택 피커에서 "모든 얼굴"을 뜻하는 태그.
    private static let allFacesTag = -1

    var body: some View {
        @Bindable var model = model
        let recipe = model.currentRecipe
        if let failure = model.selectedInfo?.faceAnalysisFailure {
            Label(UserMessage.faceAnalysisUnavailableTitle, systemImage: "exclamationmark.triangle")
            Text(UserMessage.text(for: failure)).font(.caption).foregroundStyle(.secondary)
        } else if model.faces.isEmpty {
            Label(UserMessage.noFaceDetected, systemImage: "person.crop.rectangle.badge.questionmark")
            Text(UserMessage.noFaceHint).font(.caption).foregroundStyle(.secondary)
        } else {
            Picker(
                UserMessage.faceCount(model.faces.count),
                selection: Binding(
                    get: { recipe.portrait.targetFace ?? Self.allFacesTag },
                    set: { model.edit(.targetFace($0 == Self.allFacesTag ? nil : $0)) })
            ) {
                Text(UserMessage.allFaces).tag(Self.allFacesTag)
                ForEach(model.faces.indices, id: \.self) { Text(UserMessage.faceOrdinal($0 + 1)).tag($0) }
            }
            .disabled(model.isGeometryLocked)
            Picker(UserMessage.beautyTabsLabel, selection: $model.beautyTab) {
                ForEach(BeautyTab.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            switch model.beautyTab {
            case .skin: skinControls(recipe.portrait.skin)
            case .face: faceControls(recipe.portrait.face)
            }
        }
    }

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
}
