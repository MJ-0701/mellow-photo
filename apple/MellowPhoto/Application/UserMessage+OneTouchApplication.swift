import MellowEditing
import MellowShared

extension UserMessage {
    static let oneTouchRequestStrength = "요청 강도"
    static let oneTouchReplacePersonal = "개인 조정도 이 강도로 적용"
    static let oneTouchRequestHint = "요청값이에요. 개인별 실제 적용값과 다를 수 있어요."
    static let oneTouchNeutralHint = "기본 적용의 0은 이 대상의 원터치 조정을 지워요. 개인 조정도 0으로 적용하면 이 사진에서 적용 가능한 항목을 꺼요. 다른 설정은 유지돼요."

    static func oneTouchKeyTitle(_ key: PortraitKey) -> String {
        switch key {
        case .skinSmoothing: return skinSmoothing
        case .autoBlemish: return autoBlemish
        case .skinRefinement(let key): return skinRefinementTitle(key)
        case .feature(let key): return featureTitle(key)
        case .makeupPart(let part): return makeupPartTitle(part)
        case .faceShape(let key): return faceShapeTitle(key)
        case .bodyShape(let key): return bodyShapeTitle(key)
        }
    }

    static func oneTouchProtected(_ result: OneTouchApplicationResult) -> String? {
        let items = result.items.filter { $0.reason == .protectedPersonal }
        guard !items.isEmpty else { return nil }
        return "\(Set(items.map(\.faceIndex)).count)명의 개인 조정 \(items.count)개 항목을 유지해요."
    }

    static func oneTouchOutcome(_ feedback: AppModel.OneTouchFeedback) -> String {
        switch feedback.phase {
        case .rendering: return "보정값을 저장하고 화면을 갱신하고 있어요."
        case .saveFailed: return "저장하지 못했어요. 화면이 바뀌어도 적용 완료가 아니에요."
        case .renderFailed: return "보정값은 바뀌었지만 화면을 갱신하지 못했어요. 다시 확인해 주세요."
        case .cancelled: return "사진이나 조정 상태가 바뀌어 이번 결과를 확인할 수 없어요."
        case .unavailable: return "현재 대상에 적용할 얼굴이나 준비된 항목이 없어요."
        case .noChange:
            if let result = feedback.result, oneTouchProtected(result) != nil {
                return "개인 조정이 우선해요. 얼굴 보정값은 그대로예요."
            }
            return "현재 값과 같거나 적용 가능한 변경이 없어요."
        case .visible:
            if feedback.clearingInheritance { return "이 대상의 원터치 조정을 지웠어요. 다른 적용 설정은 유지돼요." }
            guard let result = feedback.result else { return "보정 화면을 확인해 주세요." }
            let people = Set(result.renderReadyChangedKeys.map(\.faceIndex)).count
            if people == 0, result.bodySkinChanged {
                return "몸 피부 밝기 값만 적용됐어요. 얼굴 보정 완료를 뜻하지 않아요."
            }
            return "\(people)명의 보정값 \(result.changedCount)개 항목을 적용했어요. 원본과 비교해 확인하세요."
        }
    }
}
