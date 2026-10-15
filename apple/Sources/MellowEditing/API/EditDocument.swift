import MellowShared

/// 사진 한 장의 편집 상태. 체크포인트·잠금·보존 규칙은 전부 여기에만 있다.
public struct EditDocument: Equatable, Sendable {
    public enum Rejection: Equatable, Sendable {
        case geometryLocked
    }

    public private(set) var recipe: EditRecipe
    public private(set) var undoStack: [EditRecipe]
    public private(set) var redoStack: [EditRecipe]
    private var isContinuousChange = false

    public init(recipe: EditRecipe = EditRecipe(), undoStack: [EditRecipe] = [], redoStack: [EditRecipe] = []) {
        self.recipe = recipe
        self.undoStack = undoStack
        self.redoStack = redoStack
    }

    /// 연속 변경 중인지는 편집 상태가 아니므로 비교에서 뺀다.
    public static func == (lhs: EditDocument, rhs: EditDocument) -> Bool {
        lhs.recipe == rhs.recipe && lhs.undoStack == rhs.undoStack && lhs.redoStack == rhs.redoStack
    }

    public var canUndo: Bool { !undoStack.isEmpty }
    public var canRedo: Bool { !redoStack.isEmpty }
    public var hasEdits: Bool { !recipe.isDefault }
    /// 수동 편집 좌표가 어긋나지 않도록 얼굴 형태와 대상 얼굴을 고정한다.
    public var isGeometryLocked: Bool { recipe.hasLocalEdits }

    public mutating func beginContinuousChange() {
        checkpoint()
        isContinuousChange = true
    }

    public mutating func endContinuousChange() {
        isContinuousChange = false
    }

    @discardableResult
    public mutating func set(_ change: EditChange) -> Rejection? {
        if change.affectsGeometry, isGeometryLocked {
            return .geometryLocked
        }
        var updated = recipe
        switch change {
        case .exposure(let value): updated.color.exposure = value
        case .contrast(let value): updated.color.contrast = value
        case .saturation(let value): updated.color.saturation = value
        case .warmth(let value): updated.color.warmth = value
        case .skinSmoothing(let value):
            updated.portrait.skin.smoothing = EditingPolicy.clamped(value, to: EditingPolicy.unitRange)
        case .autoBlemish(let flag): updated.portrait.skin.autoBlemish = flag
        case .faceShape(let key, let value):
            updated.portrait.face[key] = EditingPolicy.clamped(value, to: EditingPolicy.faceShapeRange(key))
        case .targetFace(let index): updated.portrait.targetFace = index
        case .feature(let key, let value):
            updated.portrait.features[key] = EditingPolicy.clamped(value, to: EditingPolicy.unitRange)
        case .backgroundBlur(let value):
            updated.background.blur = EditingPolicy.clamped(value, to: EditingPolicy.unitRange)
        case .highlights(let value): updated.detail.highlights = value
        case .shadows(let value): updated.detail.shadows = value
        case .sharpness(let value): updated.detail.sharpness = value
        case .vignette(let value): updated.detail.vignette = value
        case .lookID(let id): updated.look.id = id
        case .lookIntensity(let value): updated.look.intensity = value
        // 회전·반전은 자르기 영역을 이미지와 함께 옮긴다.
        case .flipHorizontal(let flag):
            if flag != updated.geometry.flipHorizontal {
                updated.geometry = updated.geometry.flippedHorizontally()
            }
        case .quarterTurns(let turns):
            let steps = ((turns - updated.geometry.normalizedQuarterTurns) % 4 + 4) % 4
            for _ in 0..<steps {
                updated.geometry = updated.geometry.turnedClockwise()
            }
        case .straightenDegrees(let degrees):
            let limit = GeometryAdjustments.maxStraightenDegrees
            updated.geometry.straightenDegrees = max(-limit, min(limit, degrees))
        case .crop(let rect): updated.geometry.crop = rect
        }
        // 값이 그대로면 실행 취소 단계를 만들지 않는다.
        guard updated != recipe else { return nil }
        checkpointUnlessContinuous()
        recipe = updated
        return nil
    }

    /// 사용자가 고른 프리셋. 프리셋은 얼굴을 고르지 않으므로 대상 얼굴은 늘 사진의 값을 유지한다.
    /// 잠긴 사진은 얼굴형·체형도 유지한다.
    public mutating func apply(_ values: PresetValues) {
        checkpoint()
        recipe = merged(values, targetFace: recipe.portrait.targetFace)
    }

    /// 다른 사진의 설정을 일괄 복사. 잠기지 않은 사진은 대상 얼굴을 전체로 되돌린다.
    public mutating func applyFromBatch(_ values: PresetValues) {
        checkpoint()
        recipe = merged(values, targetFace: isGeometryLocked ? recipe.portrait.targetFace : nil)
    }

    /// 자동 보정 제안을 한 번의 체크포인트로 적용한다. 색·디테일·피부·눈 또렷하게만 바꾸고
    /// 치아 미백·입술 생기·대상 얼굴·얼굴형·체형·배경·메이크업·룩·기하·수동 편집은 건드리지 않는다.
    /// 이미 같은 값이면 아무것도 하지 않아 연타해도 실행 취소 한 번에 되돌아간다. 적용했으면 true.
    @discardableResult
    public mutating func applyAuto(_ suggestion: AutoEnhanceSuggestion) -> Bool {
        var updated = recipe
        updated.color = suggestion.color
        updated.detail = suggestion.detail
        updated.portrait.skin = suggestion.portrait.skin
        updated.portrait.features.eyeBrighten = suggestion.portrait.features.eyeBrighten
        guard updated != recipe else { return false }
        checkpoint()
        recipe = updated
        return true
    }

    /// 슬라이더 그룹을 프리셋 값으로 바꾼다. 룩·기하·수동 편집은 그대로 둔다.
    private func merged(_ values: PresetValues, targetFace: Int?) -> EditRecipe {
        var updated = recipe
        updated.color = values.color
        updated.detail = values.detail
        updated.portrait = values.portrait
        updated.portrait.targetFace = targetFace
        updated.background = values.background
        updated.body = values.body
        updated.makeup = values.makeup
        if isGeometryLocked {
            updated.portrait.face = recipe.portrait.face
            updated.body = recipe.body
        }
        return updated
    }

    public mutating func appendLocalEdit(_ edit: LocalEdit) {
        checkpoint()
        recipe.operations.append(edit)
    }

    /// 실행 취소·다시 실행·초기화는 진행 중이던 연속 변경을 끝낸다. 이후 편집은 다시 체크포인트한다.
    public mutating func undo() {
        isContinuousChange = false
        guard let previous = undoStack.popLast() else { return }
        redoStack.append(recipe)
        recipe = previous
    }

    public mutating func redo() {
        isContinuousChange = false
        guard let next = redoStack.popLast() else { return }
        undoStack.append(recipe)
        recipe = next
    }

    public mutating func reset() {
        isContinuousChange = false
        checkpoint()
        recipe = EditRecipe()
    }

    private mutating func checkpointUnlessContinuous() {
        if !isContinuousChange {
            checkpoint()
        }
    }

    private mutating func checkpoint() {
        if undoStack.last != recipe {
            undoStack.append(recipe)
        }
        if undoStack.count > EditingPolicy.historyLimit {
            undoStack.removeFirst(undoStack.count - EditingPolicy.historyLimit)
        }
        redoStack.removeAll()
    }
}
