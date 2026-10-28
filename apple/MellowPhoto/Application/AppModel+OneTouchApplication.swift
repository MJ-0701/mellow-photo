import Foundation
import MellowEditing
import MellowShared

extension AppModel {
    /// 요청값과 저장 표시를 분리한다. 무효 적용 뒤에도 화면 입력을 저장 강도로 되돌릴 필요는 없다.
    struct OneTouchPlan {
        let result: OneTouchApplicationResult
        fileprivate let photoID: PhotoID
        fileprivate let selectedTarget: BeautyTarget
        fileprivate let context: UUID
        fileprivate let analysis: UUID
        fileprivate let base: EditDocument
        fileprivate let proposed: EditDocument
    }

    func planOneTouchApplication(
        strength: Double, replacingPersonal: Bool, target: BeautyTarget? = nil
    ) -> OneTouchPlan? {
        guard let entry = session.selected, let info = selectedInfo, isReady, !isWorkStopped,
            !isImporting, !isExporting, !isRestoring, quickRetouchRunID == nil
        else { return nil }
        let requestedTarget = target ?? beautyTarget
        let indices: [Int]
        let scope: OneTouchApplicationScope
        switch requestedTarget {
        case .all:
            indices = Array(faces.indices)
            scope = .all
        case .gender(let gender):
            indices = faces.indices.filter { effectiveGender(forFace: $0) == gender }
            scope = .gender(gender)
        case .face(let index):
            indices = faces.indices.contains(index) ? [index] : []
            scope = .face(index)
        case .person(let id):
            indices = peopleByFace.filter { $0.value.id == id }.keys.sorted()
            scope = .person(id)
        }
        let targets = indices.map {
            PortraitPurposeFace(
                index: $0, gender: effectiveGender(forFace: $0), availableKeys: info.oneTouchKeys[$0] ?? [])
        }
        var proposed = entry.document
        let result = proposed.applyOneTouchReporting(
            strength: strength, in: scope, faces: faces.map(\.boundingBox), targets: targets,
            replacingPersonal: replacingPersonal, bodySkinAvailable: info.oneTouchBodySkinAvailable)
        return OneTouchPlan(
            result: result, photoID: entry.id, selectedTarget: beautyTarget, context: portraitPurposeContext,
            analysis: info.generation, base: entry.document, proposed: proposed)
    }

    @discardableResult
    func applyOneTouchApplication(_ plan: OneTouchPlan) -> Bool {
        guard let entry = session.selected, let info = selectedInfo, isReady, !isWorkStopped,
            !isImporting, !isExporting, !isRestoring, quickRetouchRunID == nil,
            entry.id == plan.photoID, beautyTarget == plan.selectedTarget,
            portraitPurposeContext == plan.context, info.generation == plan.analysis,
            entry.document == plan.base, !session.isPersistenceDeferred,
            plan.result.hasChanges, plan.proposed.recipe != plan.base.recipe
        else { return false }
        // 기존 목적 적용과 동일한 사진/분석/렌더 요청 수명을 공유한다.
        portraitPurposeApplication = PortraitPurposeApplication(
            photoID: plan.photoID, recipe: plan.proposed.recipe, result: nil,
            oneTouchResult: plan.result, phase: .rendering)
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

    @discardableResult
    func applyOneTouchApplication(
        strength: Double, replacingPersonal: Bool, target: BeautyTarget? = nil
    ) -> Bool {
        endSliderEditIfActive()
        guard
            let plan = planOneTouchApplication(strength: strength, replacingPersonal: replacingPersonal, target: target)
        else {
            return false
        }
        return applyOneTouchApplication(plan)
    }
}
