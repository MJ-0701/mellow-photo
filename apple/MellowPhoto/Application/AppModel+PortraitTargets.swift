import MellowEditing
import MellowShared

extension AppModel {
    /// 저장된 개인 기록 수가 아니라 현재 사진에서 실제로 연결된 얼굴만 센다.
    func portraitFaceCount(for target: BeautyTarget) -> Int {
        switch target {
        case .all: return faces.count
        case .gender(let gender): return faces.indices.filter { effectiveGender(forFace: $0) == gender }.count
        case .face(let index): return faces.indices.contains(index) ? 1 : 0
        case .person(let id): return peopleByFace.values.filter { $0.id == id }.count
        }
    }

    func isEmptyGenderGroup(_ target: BeautyTarget) -> Bool {
        if case .gender = target { return portraitFaceCount(for: target) == 0 }
        return false
    }

    var hasEmptyPortraitGroup: Bool { isEmptyGenderGroup(beautyTarget) }

    /// 0명인 그룹에 있던 값을 명시적으로 중립으로 되돌리는 조작만 허용한다.
    func permitsNeutralResetInEmptyGroup(_ change: EditChange) -> Bool {
        guard let key = change.portraitKey, overriddenKeys.contains(key) else { return false }
        switch change {
        case .skinSmoothing(let value), .skinRefinement(_, let value), .faceShape(_, let value), .feature(_, let value),
            .bodyShape(_, let value):
            return value == 0
        case .autoBlemish(let value): return !value
        default: return false
        }
    }

    @discardableResult
    func rejectEmptyPortraitGroup(_ target: BeautyTarget) -> Bool {
        guard isEmptyGenderGroup(target) else { return false }
        cancelQuickRetouch()
        endSliderEditIfActive()
        statusMessage = UserMessage.emptyPortraitGroup
        return true
    }
}
