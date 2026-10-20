import MellowEditing
import MellowShared

extension AppModel {
    private func mutateSelected(_ body: (inout EditDocument) -> EditDocument.Rejection?) {
        guard let id = session.selectedPhotoID, isReady, !isBusy else { return }
        switch session.edit(id, body) {
        case .geometryLocked:
            statusMessage = UserMessage.geometryLocked
            return
        case .unknownPerson:
            // 대상 사람이 사라졌으면 조용히 끝낸다.
            return
        case nil:
            break
        }
        if let error = session.lastPersistenceError {
            present(error)
        }
        if !isCropDragging {
            scheduleRender()
        }
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

    /// 카탈로그의 룩을 체크포인트 한 번으로 적용한다. nil은 메이크업을 모두 지운다(없음). 모르는 id는 무시한다.
    func applyMakeupLook(id: String?) {
        let look = makeupCatalog.look(id: id)
        guard id == nil || look != nil else { return }
        endSliderEditIfActive()
        // 기록이 없는 얼굴에는 아직 룩을 걸 층이 없다(H3이 기록을 만들며 적용한다).
        guard let scope = scope(for: beautyTarget) else {
            statusMessage = UserMessage.pickASliderFirst
            return
        }
        mutateSelected { document in
            document.applyMakeupLook(look, in: scope)
            return nil
        }
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
        mutateSelected { document in
            document.undo()
            return nil
        }
    }

    func redo() {
        cropAspect = nil
        mutateSelected { document in
            document.redo()
            return nil
        }
    }

    func reset() {
        cloneSource = nil
        isChoosingCloneSource = true
        mutateSelected { document in
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
        case .look, .crop, .adjust, .beauty, .makeup, .body, .background:
            return
        }
    }
}
