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
        scheduleRender()
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
            session.edit(id) { document in
                document.endContinuousChange()
                return nil
            }
        }
        session.endDeferredPersistence()
        if let error = session.lastPersistenceError {
            present(error)
        }
    }

    func edit(_ change: EditChange) {
        mutateSelected { $0.set(change) }
    }

    func applyPreset(_ values: PresetValues) {
        mutateSelected { document in
            document.apply(values)
            return nil
        }
    }

    func applyToAll() {
        guard let id = session.selectedPhotoID, !isBusy else { return }
        session.applyToAll(from: id)
        statusMessage = UserMessage.appliedToAll
    }

    func undo() {
        mutateSelected { document in
            document.undo()
            return nil
        }
    }

    func redo() {
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
        session.addPreset(named: name, values: PresetValues(color: currentRecipe.color, portrait: portrait))
    }

    func resetCloneSource() {
        cloneSource = nil
        isChoosingCloneSource = true
        statusMessage = UserMessage.chooseCloneSource
    }

    /// 캔버스 탭·드래그. 좌표는 정규화, 원점 왼쪽 아래.
    func touch(from: NormalizedPoint, to: NormalizedPoint) {
        guard isReady, !isBusy, !isComparing, !isRendering else { return }
        switch tool {
        case .retouch:
            if isChoosingCloneSource || cloneSource == nil {
                cloneSource = to
                isChoosingCloneSource = false
                statusMessage = UserMessage.chooseCloneTarget
                return
            }
            guard let source = cloneSource else { return }
            let spot = RetouchSpot(x: to.x, y: to.y, sourceX: source.x, sourceY: source.y, radius: brushRadius)
            mutateSelected { document in
                document.appendLocalEdit(.spot(spot))
                return nil
            }
        case .warp:
            let dx = max(-Policy.warpMaxDelta, min(Policy.warpMaxDelta, to.x - from.x))
            let dy = max(-Policy.warpMaxDelta, min(Policy.warpMaxDelta, to.y - from.y))
            guard abs(dx) + abs(dy) > Policy.warpMinimumDelta else { return }
            let stroke = WarpStroke(
                x: from.x, y: from.y, dx: dx, dy: dy, radius: brushRadius * Policy.warpRadiusMultiplier)
            mutateSelected { document in
                document.appendLocalEdit(.warp(stroke))
                return nil
            }
        case .color, .portrait:
            return
        }
    }
}
