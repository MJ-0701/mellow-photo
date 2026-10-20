import CoreGraphics
import MellowEditing
import MellowShared

extension AppModel {
    /// 선택 사진에 편집을 적용한다.
    /// 거절되지 않았으면 true.
    /// checksPairing이면 잠긴 사진에서 얼굴마다 해석한 얼굴형 값이 바뀌는 편집을 거절한다.
    /// 기록을 지우거나 옮기면 전역 짝짓기가 다른 기록을 다른 얼굴에 붙일 수 있어서다.
    /// 실행 취소·다시 실행·초기화는 저장된 상태로 돌아가는 것이라 검사하지 않는다.
    @discardableResult
    private func mutateSelected(
        checksPairing: Bool = true, _ body: (inout EditDocument) -> EditDocument.Rejection?
    ) -> Bool {
        guard let id = session.selectedPhotoID, isReady, !isBusy else { return false }
        let rejection = session.edit(id) { document in
            guard checksPairing, document.isGeometryLocked else { return body(&document) }
            var proposal = document
            if let rejection = body(&proposal) {
                return rejection
            }
            guard resolvedFaceShapes(of: proposal.recipe) == resolvedFaceShapes(of: document.recipe) else {
                return .geometryLocked
            }
            document = proposal
            return nil
        }
        switch rejection {
        case .geometryLocked:
            statusMessage = UserMessage.geometryLocked
            return false
        case .unknownPerson:
            // 대상 사람이 사라졌으면 조용히 끝낸다.
            return false
        case nil:
            break
        }
        if let error = session.lastPersistenceError {
            present(error)
        }
        if !isCropDragging {
            scheduleRender()
        }
        return true
    }

    /// 드래그하는 동안은 세션 파일을 쓰지 않고 끝날 때 한 번 저장한다.
    func beginSliderEdit() {
        guard let id = session.selectedPhotoID else { return }
        session.beginDeferredPersistence()
        session.edit(id) { document in
            document.beginContinuousChange()
            return nil
        }
    }

    func endSliderEdit() {
        if let id = session.selectedPhotoID {
            session.endContinuousChange(id)
        }
        session.endDeferredPersistence()
        if let error = session.lastPersistenceError {
            present(error)
        }
    }

    /// 드래그 도중 들어온 한 번짜리 편집은 진행 중인 연속 변경을 먼저 끝내 자기 체크포인트를 갖게 한다.
    /// 드래그 중이 아니면 아무것도 하지 않는다(세션을 한 번 더 쓰지 않는다).
    func endSliderEditIfActive() {
        guard session.isPersistenceDeferred else { return }
        endSliderEdit()
    }

    /// 얼굴 의존 변경은 현재 뷰티 대상의 층에 쓴다.
    /// 찾은 얼굴을 처음 만지면 기록이 만들어진다.
    func edit(_ change: EditChange) {
        let target = beautyTarget
        guard change.portraitKey != nil || isGenderChange(change) else {
            mutateSelected { $0.set(change) }
            return
        }
        switch target {
        case .face(let index):
            let boxes = faces.map(\.boundingBox)
            mutateSelected { $0.set(change, forFace: index, of: boxes) }
        default:
            guard let scope = scope(for: target) else { return }
            mutateSelected { $0.set(change, in: scope) }
        }
    }

    private func isGenderChange(_ change: EditChange) -> Bool {
        if case .gender = change {
            return true
        }
        return false
    }

    /// 대상 전환은 화면 상태라 레시피를 바꾸지 않는다.
    func setBeautyTarget(_ target: BeautyTarget) {
        guard let id = session.selectedPhotoID else { return }
        endSliderEditIfActive()
        beautyTargets[id] = target
    }

    func applyPreset(_ values: PresetValues) {
        endSliderEditIfActive()
        mutateSelected { document in
            document.apply(values)
            return nil
        }
    }

    /// 레시피가 실제로 바뀌었으면 true. 이미 같은 값이거나 편집할 수 없는 상태면 false.
    @discardableResult
    func applyAutoSuggestion(_ suggestion: AutoEnhanceSuggestion) -> Bool {
        endSliderEditIfActive()
        var applied = false
        mutateSelected { document in
            applied = document.applyAuto(suggestion)
            return nil
        }
        return applied
    }

    /// 카탈로그의 룩을 현재 대상 층에 체크포인트 한 번으로 적용한다.
    /// nil은 메이크업을 모두 지운다(없음).
    /// 모르는 id는 무시한다.
    /// 기록이 없는 얼굴이면 기록을 만들며 적용한다.
    func applyMakeupLook(id: String?) {
        let look = makeupCatalog.look(id: id)
        guard id == nil || look != nil else { return }
        endSliderEditIfActive()
        if case .face(let index) = beautyTarget {
            let boxes = faces.map(\.boundingBox)
            mutateSelected { document in
                document.applyMakeupLook(look, forFace: index, of: boxes)
                return nil
            }
            return
        }
        let scope = scope(for: beautyTarget) ?? .all
        mutateSelected { document in
            document.applyMakeupLook(look, in: scope)
            return nil
        }
    }

    /// 현재 대상(얼굴 또는 찾지 못한 사람)의 성별을 지정한다.
    /// nil은 미지정이다.
    /// 전체·그룹 대상에서는 아무것도 하지 않는다.
    /// 기록이 없는 얼굴은 기록을 만들며 지정한다.
    /// 잠긴 사진에서는 거절하고 안내한다.
    func setGender(_ gender: Gender?) {
        switch beautyTarget {
        case .face, .person:
            endSliderEditIfActive()
            edit(.gender(gender))
        case .all, .gender:
            return
        }
    }

    /// 현재 대상 층에서 keys를 상속으로 되돌린다(nil이면 층 전체).
    /// 전체 대상은 그 키를 기본값으로 둔다.
    /// 기록이 없는 얼굴은 아무것도 하지 않는다.
    func resetOverrides(_ keys: Set<PortraitKey>? = nil) {
        guard let scope = scope(for: beautyTarget) else { return }
        endSliderEditIfActive()
        mutateSelected { $0.resetOverrides(keys, in: scope) }
    }

    /// 찾지 못한 기록을 기록이 없는 얼굴에 연결하고 그 얼굴을 대상으로 한다(체크포인트 한 번).
    /// 이미 기록과 짝인 얼굴에는 연결하지 않는다.
    func rebindPerson(_ id: PersonID, toFace index: Int) {
        guard unpairedFaceIndices.contains(index), let anchor = anchor(forFace: index) else { return }
        endSliderEditIfActive()
        guard mutateSelected({ $0.rebindPerson(id, to: anchor) }) else { return }
        setBeautyTarget(.face(index))
    }

    /// 사람 기록을 지운다(체크포인트 한 번).
    /// 지운 사람이 지금 대상(그 사람 칩이나 그 사람과 짝인 얼굴)이면 대상을 전체로 되돌린다.
    func removePerson(_ id: PersonID) {
        let isTarget: Bool
        switch beautyTarget {
        case .person(let target): isTarget = target == id
        case .face(let index): isTarget = peopleByFace[index]?.id == id
        case .all, .gender: isTarget = false
        }
        endSliderEditIfActive()
        guard mutateSelected({ $0.removePerson(id) }), isTarget else { return }
        setBeautyTarget(.all)
    }

    /// 전체 사진에 적용을 누를 수 있는지. 사진이 둘 이상이고 복사할 항목이 하나라도 있어야 한다.
    var canApplyToAll: Bool { session.photos.count >= 2 && !syncCategories.isEmpty }

    func setSyncCategory(_ category: SyncCategory, enabled: Bool) {
        if enabled {
            syncCategories.insert(category)
        } else {
            syncCategories.remove(category)
        }
    }

    func applyToAll() {
        guard let id = session.selectedPhotoID, !isBusy, !syncCategories.isEmpty else { return }
        session.applyToAll(from: id, categories: syncCategories)
        statusMessage = UserMessage.appliedToAll(
            categoryCount: syncCategories.count, total: SyncCategory.allCases.count)
    }

    /// 되돌린 자르기가 고른 비율과 맞는다는 보장이 없으므로 비율 선택을 비운다.
    func undo() {
        cropAspect = nil
        mutateSelected(checksPairing: false) { document in
            document.undo()
            return nil
        }
    }

    func redo() {
        cropAspect = nil
        mutateSelected(checksPairing: false) { document in
            document.redo()
            return nil
        }
    }

    func reset() {
        cloneSource = nil
        isChoosingCloneSource = true
        mutateSelected(checksPairing: false) { document in
            document.reset()
            return nil
        }
    }

    /// 프리셋은 사람을 고르지 않는다.
    /// 개인 층은 사진마다 사람이 달라 저장하지 않는다.
    func savePreset(named name: String) {
        // 프리셋은 전체 층과 성별 그룹 층만 담는다(PresetValues(of:)가 개인 층을 버린다).
        session.addPreset(named: name, values: PresetValues(of: currentRecipe))
    }

    func resetCloneSource() {
        cloneSource = nil
        isChoosingCloneSource = true
        statusMessage = UserMessage.chooseCloneSource
    }

    /// 캔버스 탭·드래그. 좌표는 캔버스(출력) 정규화, 원점 왼쪽 아래. 저장은 원본 좌표로 한다.
    func touch(from: NormalizedPoint, to: NormalizedPoint) {
        guard isReady, !isBusy, !blocksCanvasTouch, !isRendering, !canvasShowsUncropped else { return }
        let transform = outputTransform
        // 변환을 모르는데 기하가 있으면 캔버스 좌표를 원본 좌표로 오인하게 되므로 거절한다.
        guard transform != nil || currentRecipe.geometry.isIdentity else { return }
        let fromOriginal = transform?.toOriginal(from) ?? from
        let toOriginal = transform?.toOriginal(to) ?? to
        switch tool {
        case .retouch:
            if isChoosingCloneSource || cloneSource == nil {
                cloneSource = toOriginal
                isChoosingCloneSource = false
                statusMessage = UserMessage.chooseCloneTarget
                return
            }
            guard let source = cloneSource else { return }
            let spot = RetouchSpot(
                x: toOriginal.x, y: toOriginal.y, sourceX: source.x, sourceY: source.y, radius: brushRadius)
            mutateSelected { document in
                document.appendLocalEdit(.spot(spot))
                return nil
            }
        case .warp:
            let dx = max(-Policy.warpMaxDelta, min(Policy.warpMaxDelta, toOriginal.x - fromOriginal.x))
            let dy = max(-Policy.warpMaxDelta, min(Policy.warpMaxDelta, toOriginal.y - fromOriginal.y))
            guard abs(dx) + abs(dy) > Policy.warpMinimumDelta else { return }
            let stroke = WarpStroke(
                x: fromOriginal.x, y: fromOriginal.y, dx: dx, dy: dy,
                radius: brushRadius * Policy.warpRadiusMultiplier)
            mutateSelected { document in
                document.appendLocalEdit(.warp(stroke))
                return nil
            }
        case .beauty, .makeup:
            // 탭한 점이 든 얼굴 상자 중 가장 작은 것(겹치면 앞사람)이 대상이고 얼굴 밖이면 전체다.
            // 대상 선택은 화면 상태라 레시피를 바꾸지 않는다.
            let point = CGPoint(x: toOriginal.x, y: toOriginal.y)
            let boxes = faces.map(\.boundingBox)
            let hit = boxes.indices
                .filter { boxes[$0].cgRect.contains(point) }
                .min { boxes[$0].width * boxes[$0].height < boxes[$1].width * boxes[$1].height }
            setBeautyTarget(hit.map(BeautyTarget.face) ?? .all)
        case .look, .crop, .adjust, .body, .background:
            return
        }
    }
}
