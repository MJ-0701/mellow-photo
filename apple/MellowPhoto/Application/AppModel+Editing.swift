import MellowEditing
import MellowShared

extension AppModel {
    private func mutateSelected(_ body: (inout EditDocument) -> EditDocument.Rejection?) {
        guard let id = session.selectedPhotoID, isReady, !isBusy else { return }
        if session.edit(id, body) == .geometryLocked {
            statusMessage = UserMessage.geometryLocked
            return
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
    private func endSliderEditIfActive() {
        guard session.isPersistenceDeferred else { return }
        endSliderEdit()
    }

    func edit(_ change: EditChange) {
        mutateSelected { $0.set(change) }
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

    func applyToAll() {
        guard let id = session.selectedPhotoID, !isBusy else { return }
        session.applyToAll(from: id)
        statusMessage = UserMessage.appliedToAll
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

    /// 프리셋은 얼굴을 고르지 않는다. 대상 얼굴 번호는 사진마다 의미가 달라 저장하지 않는다.
    func savePreset(named name: String) {
        var portrait = currentRecipe.portrait
        portrait.targetFace = nil
        session.addPreset(
            named: name,
            values: PresetValues(color: currentRecipe.color, portrait: portrait, detail: currentRecipe.detail))
    }

    func resetCloneSource() {
        cloneSource = nil
        isChoosingCloneSource = true
        statusMessage = UserMessage.chooseCloneSource
    }

    /// 캔버스 탭·드래그. 좌표는 캔버스(출력) 정규화, 원점 왼쪽 아래. 저장은 원본 좌표로 한다.
    func touch(from: NormalizedPoint, to: NormalizedPoint) {
        guard isReady, !isBusy, !isComparing, !isRendering, !canvasShowsUncropped else { return }
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
        case .look, .crop, .adjust, .portrait:
            return
        }
    }
}
