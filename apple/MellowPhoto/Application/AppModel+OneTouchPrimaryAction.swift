import Foundation
import MellowEditing
import MellowShared

extension AppModel {
    enum OneTouchDecisionChoice { case keepAdjustments, replacePersonal }

    struct OneTouchDecision: Identifiable {
        let id = UUID()
        let target: BeautyTarget
        let strength: Double
        let keepResult: OneTouchApplicationResult
        let replaceResult: OneTouchApplicationResult
        fileprivate let photoID: PhotoID
        fileprivate let selectedTarget: BeautyTarget
        fileprivate let analysis: UUID
        fileprivate let context: UUID
        fileprivate let requestGeneration: UUID
        fileprivate let document: EditDocument
        fileprivate let keepPlan: OneTouchPlan
        fileprivate let replacePlan: OneTouchPlan
    }

    /// 주 버튼은 충돌을 먼저 보여 준다. 선택 전 기존 submit의 저장/편집 종료를 호출하지 않는다.
    @discardableResult
    func beginOneTouchPrimaryAction(for target: BeautyTarget) -> Bool {
        pendingOneTouchDecision = nil
        clearOneTouchAttempt()
        guard !session.isPersistenceDeferred else {
            statusMessage = "진행 중인 조절을 먼저 끝낸 뒤 원터치를 눌러주세요."
            return false
        }
        guard let entry = session.selected, let info = selectedInfo else { return false }
        let strength = requestedOneTouchStrength(for: target)
        let protectsPersonal: Bool
        switch target {
        case .all, .gender: protectsPersonal = strength > 0
        case .face, .person: protectsPersonal = false
        }
        if protectsPersonal,
            let keep = planOneTouchApplication(strength: strength, replacingPersonal: false, target: target),
            keep.result.items.contains(where: { $0.reason == .protectedPersonal })
        {
            guard let replace = planOneTouchApplication(strength: strength, replacingPersonal: true, target: target)
            else {
                return false
            }
            pendingOneTouchDecision = OneTouchDecision(
                target: target, strength: strength, keepResult: keep.result, replaceResult: replace.result,
                photoID: entry.id, selectedTarget: beautyTarget, analysis: info.generation,
                context: portraitPurposeContext, requestGeneration: oneTouchRequestGeneration,
                document: entry.document, keepPlan: keep, replacePlan: replace)
            return false
        }
        return submitOneTouchRequest(for: target)
    }

    func oneTouchDecision(for target: BeautyTarget) -> OneTouchDecision? {
        guard let decision = pendingOneTouchDecision, decision.target == target, isCurrent(decision) else { return nil }
        return decision
    }

    private func isCurrent(_ decision: OneTouchDecision) -> Bool {
        guard let entry = session.selected, let info = selectedInfo else { return false }
        return isReady && !isWorkStopped && !isImporting && !isExporting && !isRestoring
            && quickRetouchRunID == nil && !session.isPersistenceDeferred
            && entry.id == decision.photoID && beautyTarget == decision.selectedTarget
            && info.generation == decision.analysis && portraitPurposeContext == decision.context
            && oneTouchRequestGeneration == decision.requestGeneration
            && requestedOneTouchStrength(for: decision.target) == decision.strength
            && entry.document == decision.document
    }

    /// 수명 변경이 닫은 선택은 사용자의 취소와 구분해 다시 확인할 방법을 알려준다.
    func invalidatePendingOneTouchDecision() {
        guard pendingOneTouchDecision != nil else { return }
        pendingOneTouchDecision = nil
        statusMessage = UserMessage.oneTouchDecisionExpired
    }

    func dismissOneTouchDecision(id: UUID) {
        guard pendingOneTouchDecision?.id == id else { return }
        pendingOneTouchDecision = nil
    }

    @discardableResult
    func resolveOneTouchDecision(id: UUID, choice: OneTouchDecisionChoice) -> Bool {
        guard let decision = pendingOneTouchDecision, decision.id == id else {
            statusMessage = UserMessage.oneTouchDecisionExpired
            return false
        }
        pendingOneTouchDecision = nil
        guard isCurrent(decision) else {
            clearOneTouchAttempt()
            statusMessage = UserMessage.oneTouchDecisionExpired
            return false
        }
        let replacing = choice == .replacePersonal
        return submitPreparedOneTouchPlan(
            replacing ? decision.replacePlan : decision.keepPlan,
            for: decision.target, replacingPersonal: replacing)
    }
}
