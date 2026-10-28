import Foundation
import MellowEditing
import MellowShared

extension AppModel {
    struct PortraitPurposePlan {
        let purpose: PortraitPurpose
        let result: PortraitPurposeResult
        fileprivate let photoID: PhotoID
        fileprivate let target: BeautyTarget
        fileprivate let context: UUID
        fileprivate let analysis: UUID
        fileprivate let base: EditDocument
        fileprivate let proposed: EditDocument
    }

    struct PortraitPurposeApplication {
        enum Phase { case rendering, visible, cancelled, renderFailed, saveFailed }
        let photoID: PhotoID
        let recipe: EditRecipe
        let result: PortraitPurposeResult
        var phase: Phase
        var renderRequest: UUID?
    }

    func invalidatePortraitPurposeApplication() {
        if portraitPurposeApplication?.phase == .rendering || portraitPurposeApplication?.phase == .visible {
            portraitPurposeApplication?.phase = .cancelled
        }
    }

    /// 저장된 조정을 바꾸기 전 동일 입력으로 적용/건너뛸 키를 계산한다.
    func planPortraitPurpose(
        _ purpose: PortraitPurpose, strength: Double, replacingExisting: Bool
    ) -> PortraitPurposePlan? {
        guard let entry = session.selected, let info = selectedInfo, isReady, !isWorkStopped,
            !isImporting, !isExporting, !isRestoring, quickRetouchRunID == nil
        else { return nil }
        let indices: [Int]
        switch beautyTarget {
        case .all: indices = Array(faces.indices)
        case .gender(let gender): indices = faces.indices.filter { effectiveGender(forFace: $0) == gender }
        case .face(let index): indices = faces.indices.contains(index) ? [index] : []
        case .person(let id): indices = peopleByFace.filter { $0.value.id == id }.keys.sorted()
        }
        // 옆선은 대상을 직접 고른 개인에만 쓴다. 성별을 추정/지정하거나 이웃에게 대신 적용하지 않는다.
        let explicitlyChosen: Bool
        switch beautyTarget {
        case .face, .person: explicitlyChosen = true
        default: explicitlyChosen = false
        }
        let targets = indices.map { index in
            PortraitPurposeFace(
                index: index, gender: effectiveGender(forFace: index),
                availableKeys: purpose == .sideChest && !explicitlyChosen ? [] : info.portraitPurposeKeys[index] ?? [])
        }
        var proposal = entry.document
        let result = proposal.applyPortraitPurpose(
            purpose, strength: strength, faces: faces.map(\.boundingBox), targets: targets,
            replacingExisting: replacingExisting)
        return PortraitPurposePlan(
            purpose: purpose, result: result, photoID: entry.id, target: beautyTarget,
            context: portraitPurposeContext, analysis: info.generation, base: entry.document, proposed: proposal)
    }

    @discardableResult
    func applyPortraitPurpose(_ plan: PortraitPurposePlan) -> Bool {
        guard let entry = session.selected, let info = selectedInfo, isReady, !isWorkStopped,
            !isImporting, !isExporting, !isRestoring, quickRetouchRunID == nil,
            entry.id == plan.photoID, beautyTarget == plan.target, portraitPurposeContext == plan.context,
            info.generation == plan.analysis, entry.document == plan.base,
            !session.isPersistenceDeferred
        else { return false }
        guard plan.result.changedCount > 0, plan.proposed.recipe != plan.base.recipe else {
            statusMessage = "바뀌는 항목이 없어요. 유지한 조정과 적용 가능한 부위를 확인해 주세요."
            return false
        }
        portraitPurposeApplication = PortraitPurposeApplication(
            photoID: plan.photoID, recipe: plan.proposed.recipe, result: plan.result, phase: .rendering)
        guard
            mutateSelected({ document in
                document = plan.proposed
                return nil
            })
        else {
            portraitPurposeApplication?.phase = .cancelled
            return false
        }
        if session.lastPersistenceError != nil { portraitPurposeApplication?.phase = .saveFailed }
        return true
    }

    /// 버튼 조작은 진행 중 드래그를 먼저 저장해 별도의 Undo 단계로 보존한다.
    @discardableResult
    func applyPortraitPurpose(_ purpose: PortraitPurpose, strength: Double, replacingExisting: Bool) -> Bool {
        endSliderEditIfActive()
        guard let plan = planPortraitPurpose(purpose, strength: strength, replacingExisting: replacingExisting) else {
            return false
        }
        return applyPortraitPurpose(plan)
    }
}
