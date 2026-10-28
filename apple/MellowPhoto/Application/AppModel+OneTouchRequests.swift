import Foundation
import MellowEditing
import MellowShared

extension AppModel {
    struct OneTouchInputKey: Hashable {
        let photoID: PhotoID
        let target: BeautyTarget
        let analysis: UUID
    }
    struct OneTouchRequestDrag {
        let id: UUID
        let key: OneTouchInputKey
        let context: UUID
        let document: EditDocument
    }
    struct OneTouchAttempt {
        let key: OneTouchInputKey
        let context: UUID
        let recipe: EditRecipe
        let result: OneTouchApplicationResult?
        let accepted: Bool
        let proposedChanges: Bool
        let replacingPersonal: Bool
        let clearingInheritance: Bool
    }
    struct OneTouchFeedback {
        enum Phase { case rendering, visible, noChange, unavailable, cancelled, renderFailed, saveFailed }
        let phase: Phase
        let result: OneTouchApplicationResult?
        let replacingPersonal: Bool
        let clearingInheritance: Bool
    }

    private func oneTouchInputKey(for target: BeautyTarget) -> OneTouchInputKey? {
        guard let id = session.selectedPhotoID, let info = selectedInfo else { return nil }
        return OneTouchInputKey(photoID: id, target: target, analysis: info.generation)
    }

    func requestedOneTouchStrength(for target: BeautyTarget) -> Double {
        guard let key = oneTouchInputKey(for: target) else { return OneTouchBundle.defaultStrength }
        return oneTouchRequests[key] ?? oneTouchStrength(for: target) ?? OneTouchBundle.defaultStrength
    }

    func setRequestedOneTouchStrength(
        _ strength: Double, for target: BeautyTarget, expectedContext: UUID? = nil, dragID: UUID? = nil
    ) {
        guard strength.isFinite, let key = oneTouchInputKey(for: target),
            expectedContext == nil || expectedContext == portraitPurposeContext
        else { return }
        if let dragID, oneTouchRequestDrag?.id != dragID { return }
        if let drag = oneTouchRequestDrag {
            guard drag.key == key, drag.context == portraitPurposeContext,
                session.selected?.document == drag.document
            else { return }
        }
        oneTouchRequests = oneTouchRequests.filter { $0.key.photoID != key.photoID || $0.key.analysis == key.analysis }
        oneTouchRequestGeneration = UUID()
        oneTouchRequests[key] = OneTouchBundle.clampedStrength(strength)
        clearOneTouchAttempt()
    }

    /// 드래그는 요청값만 고른다. 진행 중인 다른 편집도 여기서 저장하지 않는다.
    @discardableResult
    func beginOneTouchRequestEditing(for target: BeautyTarget, expectedContext: UUID? = nil) -> UUID? {
        guard expectedContext == nil || expectedContext == portraitPurposeContext else { return nil }
        guard let key = oneTouchInputKey(for: target), let document = session.selected?.document,
            !isEmptyGenderGroup(target)
        else { return nil }
        clearOneTouchAttempt()
        let id = UUID()
        oneTouchRequestDrag = OneTouchRequestDrag(id: id, key: key, context: portraitPurposeContext, document: document)
        return id
    }

    func cancelOneTouchRequestEditing(_ id: UUID?) {
        if oneTouchRequestDrag?.id == id { oneTouchRequestDrag = nil }
    }

    /// 종료도 입력 정리만 한다. 기본/개인 교체 버튼이 별도 한 트랜잭션을 만든다.
    func endOneTouchRequestEditing(for _: BeautyTarget, id: UUID) {
        guard oneTouchRequestDrag?.id == id else { return }
        oneTouchRequestDrag = nil
    }

    func clearOneTouchAttempt() {
        pendingOneTouchDecision = nil
        let hadAttempt = oneTouchAttempt != nil
        oneTouchAttempt = nil
        if hadAttempt || portraitPurposeApplication?.oneTouchResult != nil { portraitPurposeApplication = nil }
    }

    /// 새 시도는 이전 성공 표시를 제거한다. 기본 0의 상속 복귀는 별도 legacy 경로다.
    @discardableResult
    func submitOneTouchRequest(for target: BeautyTarget, replacingPersonal: Bool = false) -> Bool {
        endSliderEditIfActive()
        oneTouchRequestDrag = nil
        clearOneTouchAttempt()
        guard oneTouchInputKey(for: target) != nil, isReady, !isWorkStopped,
            !isImporting, !isExporting, !isRestoring, quickRetouchRunID == nil
        else { return false }
        let strength = requestedOneTouchStrength(for: target)
        if strength == 0, !replacingPersonal { return clearOneTouchInheritance(for: target) }
        let plan = planOneTouchApplication(strength: strength, replacingPersonal: replacingPersonal, target: target)
        return submitPreparedOneTouchPlan(plan, for: target, replacingPersonal: replacingPersonal)
    }

    /// 선택할 때 이미 고정한 계획만 쓴다. 확인 시 현재 사진으로 새 계획을 만들지 않는다.
    @discardableResult
    func submitPreparedOneTouchPlan(
        _ plan: OneTouchPlan?, for target: BeautyTarget, replacingPersonal: Bool
    ) -> Bool {
        clearOneTouchAttempt()
        guard let key = oneTouchInputKey(for: target) else { return false }
        let accepted = plan.map { applyOneTouchApplication($0) } ?? false
        oneTouchAttempt = OneTouchAttempt(
            key: key, context: portraitPurposeContext, recipe: currentRecipe,
            result: plan?.result, accepted: accepted, proposedChanges: plan?.result.hasChanges == true,
            replacingPersonal: replacingPersonal, clearingInheritance: false)
        return accepted
    }

    /// 빈 그룹도 저장된 키만 명시적으로 지운다. 새로운 neutral override를 만들지 않는다.
    @discardableResult
    func clearOneTouchInheritance(for target: BeautyTarget) -> Bool {
        endSliderEditIfActive()
        clearOneTouchAttempt()
        guard let key = oneTouchInputKey(for: target), let entry = session.selected, isReady, !isWorkStopped,
            !isImporting, !isExporting, !isRestoring, quickRetouchRunID == nil
        else { return false }
        var proposal = entry.document
        let rejection: EditDocument.Rejection?
        if case .face(let index) = target {
            rejection = proposal.applyOneTouch(strength: 0, forFace: index, of: faces.map(\.boundingBox))
        } else if let scope = scope(for: target) {
            rejection = proposal.applyOneTouch(strength: 0, in: scope)
        } else {
            return false
        }
        let changes = rejection == nil && proposal.recipe != entry.document.recipe
        var accepted = false
        if changes {
            portraitPurposeApplication = PortraitPurposeApplication(
                photoID: entry.id, recipe: proposal.recipe,
                result: nil, phase: .rendering)
            accepted = mutateSelected { document in
                document = proposal
                return nil
            }
            if session.lastPersistenceError != nil { portraitPurposeApplication?.phase = .saveFailed }
        }
        oneTouchRequests[key] = 0
        oneTouchAttempt = OneTouchAttempt(
            key: key, context: portraitPurposeContext, recipe: currentRecipe,
            result: nil, accepted: accepted, proposedChanges: changes, replacingPersonal: false,
            clearingInheritance: true)
        return accepted
    }

    func oneTouchFeedback(for target: BeautyTarget) -> OneTouchFeedback? {
        guard let attempt = oneTouchAttempt, attempt.key == oneTouchInputKey(for: target),
            attempt.context == portraitPurposeContext, attempt.recipe == currentRecipe
        else { return nil }
        let phase: OneTouchFeedback.Phase
        if !attempt.accepted {
            if attempt.proposedChanges {
                phase = .cancelled
            } else if !attempt.clearingInheritance && (attempt.result == nil || attempt.result?.items.isEmpty == true) {
                phase = .unavailable
            } else {
                phase = .noChange
            }
        } else if let receipt = portraitPurposeApplication, receipt.photoID == attempt.key.photoID,
            receipt.recipe == attempt.recipe, receipt.oneTouchResult == attempt.result
        {
            switch receipt.phase {
            case .rendering: phase = .rendering
            case .visible: phase = .visible
            case .cancelled: phase = .cancelled
            case .renderFailed: phase = .renderFailed
            case .saveFailed: phase = .saveFailed
            }
        } else {
            phase = .cancelled
        }
        return OneTouchFeedback(
            phase: phase, result: attempt.result,
            replacingPersonal: attempt.replacingPersonal, clearingInheritance: attempt.clearingInheritance)
    }

    func oneTouchPreparedFaceCount(for target: BeautyTarget) -> Int {
        guard
            let result = planOneTouchApplication(
                strength: OneTouchBundle.defaultStrength,
                replacingPersonal: true, target: target)?.result
        else { return 0 }
        return Set(result.items.filter(\.renderReady).map(\.faceIndex)).count
    }
    func hasStoredOneTouchValues(for target: BeautyTarget) -> Bool {
        let layer: PortraitLayer?
        if case .face(let index) = target {
            layer = peopleByFace[index]?.layer
        } else if let scope = scope(for: target) {
            layer = PortraitResolver.layer(currentRecipe, scope: scope)
        } else {
            layer = nil
        }
        return layer.map { !$0.overriddenKeys.isDisjoint(with: OneTouchBundle.keys) || $0.oneTouch != nil } ?? false
    }

}
