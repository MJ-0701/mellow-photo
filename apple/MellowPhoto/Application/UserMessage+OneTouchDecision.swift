import MellowEditing
import MellowShared

extension UserMessage {
    static let oneTouchDecisionTitle = "사진에 저장된 개인 조정이 있어요"
    static let oneTouchDecisionKeep = "기존 조정 유지"
    static let oneTouchDecisionExpired = "이전 선택은 더 이상 사용할 수 없어요. 원터치를 다시 눌러 적용 범위를 확인해 주세요."

    static func oneTouchDecisionTarget(_ target: AppModel.BeautyTarget) -> String {
        switch target {
        case .all: return "이 사진의 모든 얼굴"
        case .gender(let gender): return gender == .female ? "여성 그룹" : "남성 그룹"
        case .face, .person: return "선택한 사람"
        }
    }

    static func oneTouchDecisionChanges(_ result: OneTouchApplicationResult) -> String {
        let people = Set(result.renderReadyChangedKeys.map(\.faceIndex)).count
        if people == 0 {
            return result.bodySkinChanged ? "얼굴 변경 없음 · 몸 피부 밝기만 변경" : "얼굴·몸 피부 밝기 변경 없음"
        }
        let face = "얼굴 \(people)명 · \(result.changedCount)개 항목 변경"
        return result.bodySkinChanged ? face + " · 몸 피부 밝기도 변경" : face + " · 몸 피부 밝기 유지"
    }
}
