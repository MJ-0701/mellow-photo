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
    /// 수동 편집 좌표가 어긋나지 않도록 얼굴형·체형과 대상 얼굴을 고정한다.
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
        case .skinRefinement(let key, let value):
            updated.portrait.skin[key] = EditingPolicy.clamped(value, to: EditingPolicy.skinRefinementRange(key))
        case .faceShape(let key, let value):
            updated.portrait.face[key] = EditingPolicy.clamped(value, to: EditingPolicy.faceShapeRange(key))
        case .targetFace(let index): updated.portrait.targetFace = index
        case .feature(let key, let value):
            updated.portrait.features[key] = EditingPolicy.clamped(value, to: EditingPolicy.unitRange)
        case .backgroundBlur(let value):
            updated.background.blur = EditingPolicy.clamped(value, to: EditingPolicy.unitRange)
        case .bodySkin(let key, let value):
            updated.bodySkin[key] = EditingPolicy.clamped(value, to: EditingPolicy.bodySkinRange(key))
        case .bodyShape(let key, let value):
            updated.body[key] = EditingPolicy.clamped(value, to: EditingPolicy.bodyShapeRange(key))
        case .makeupColor(let part, let id):
            updated.makeup = Self.editedMakeup(updated.makeup) { makeup in
                guard part.hasColor else { return }
                makeup.setColorID(id, of: part)
                if id != nil, makeup.intensity(of: part) == 0 {
                    makeup.setIntensity(EditingPolicy.makeupDefaultIntensity, of: part)
                }
            }
        case .makeupIntensity(let part, let value):
            updated.makeup = Self.editedMakeup(updated.makeup) { makeup in
                makeup.setIntensity(EditingPolicy.clamped(value, to: EditingPolicy.unitRange), of: part)
            }
        case .highlights(let value): updated.detail.highlights = value
        case .shadows(let value): updated.detail.shadows = value
        case .sharpness(let value): updated.detail.sharpness = value
        case .vignette(let value): updated.detail.vignette = value
        case .effect(let key, let value):
            updated.effects[key] = EditingPolicy.clamped(value, to: EditingPolicy.unitRange)
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
    /// 잠긴 사진은 얼굴형·체형도 유지한다. 바뀌는 값이 없으면 실행 취소 단계를 만들지 않는다.
    public mutating func apply(_ values: PresetValues) {
        let updated = merged(values, targetFace: recipe.portrait.targetFace, categories: SyncCategory.all)
        guard updated != recipe else { return }
        checkpoint()
        recipe = updated
    }

    /// 다른 사진의 설정을 일괄 복사. 고른 항목만 덮어쓴다(기본은 전부). 빈 선택은 아무것도 하지 않는다.
    /// 잠기지 않은 사진은 얼굴 의존 항목을 복사할 때만 대상 얼굴을 전체로 되돌린다.
    /// 바뀌는 값이 없으면(잠긴 사진에 얼굴형만 복사하는 경우 등) 실행 취소 단계를 만들지 않는다.
    public mutating func applyFromBatch(_ values: PresetValues, categories: Set<SyncCategory> = SyncCategory.all) {
        guard !categories.isEmpty else { return }
        let resetsTarget = !isGeometryLocked && categories.contains { $0.dependsOnFaces }
        let updated = merged(
            values, targetFace: resetsTarget ? nil : recipe.portrait.targetFace, categories: categories)
        guard updated != recipe else { return }
        checkpoint()
        recipe = updated
    }

    /// 자동 보정 제안을 한 번의 체크포인트로 적용한다. 색·디테일·피부 보정·자동 잡티·눈 또렷하게만 바꾸고
    /// 피부 정밀·치아 미백·입술 생기·대상 얼굴·얼굴형·체형·배경·몸 피부·메이크업·효과·룩·기하·수동 편집은 건드리지 않는다.
    /// 이미 같은 값이면 아무것도 하지 않아 연타해도 실행 취소 한 번에 되돌아간다. 적용했으면 true.
    @discardableResult
    public mutating func applyAuto(_ suggestion: AutoEnhanceSuggestion) -> Bool {
        var updated = recipe
        updated.color = suggestion.color
        updated.detail = suggestion.detail
        updated.portrait.skin.smoothing = suggestion.portrait.skin.smoothing
        updated.portrait.skin.autoBlemish = suggestion.portrait.skin.autoBlemish
        updated.portrait.features.eyeBrighten = suggestion.portrait.features.eyeBrighten
        guard updated != recipe else { return false }
        checkpoint()
        recipe = updated
        return true
    }

    /// 룩의 부위 값 다섯 개를 메이크업에 써 넣고 lookID를 기록한다(스펙 6). nil이면 메이크업을 모두 지운다(룩 "없음").
    /// 체크포인트 한 번이다. 색만 바꾸므로 수동 편집이 있어도 잠기지 않는다. 이미 같은 값이면 아무것도 하지 않는다.
    public mutating func applyMakeupLook(_ look: MakeupLook?) {
        let makeup = look?.adjustments ?? MakeupAdjustments()
        guard makeup != recipe.makeup else { return }
        checkpoint()
        recipe.makeup = makeup
    }

    /// 고른 그룹을 프리셋 값으로 바꾼다. 룩·기하·수동 편집은 그대로 두고, 잠긴 사진은 얼굴형·체형을 건너뛴다.
    private func merged(_ values: PresetValues, targetFace: Int?, categories: Set<SyncCategory>) -> EditRecipe {
        var updated = recipe
        if categories.contains(.color) {
            updated.color = values.color
            updated.detail = values.detail
        }
        if categories.contains(.effects) {
            updated.effects = values.effects
        }
        if categories.contains(.skin) {
            updated.portrait.skin = values.portrait.skin
        }
        if categories.contains(.faceShape), !isGeometryLocked {
            updated.portrait.face = values.portrait.face
        }
        if categories.contains(.features) {
            updated.portrait.features = values.portrait.features
        }
        if categories.contains(.makeup) {
            updated.makeup = values.makeup
        }
        if categories.contains(.background) {
            updated.background = values.background
        }
        if categories.contains(.body), !isGeometryLocked {
            updated.body = values.body
        }
        if categories.contains(.bodySkin) {
            updated.bodySkin = values.bodySkin
        }
        updated.portrait.targetFace = targetFace
        return updated
    }

    /// 부위 값이 실제로 바뀌었으면 룩 이름을 지운다(스펙 6). 같은 값이면 룩을 유지한다.
    private static func editedMakeup(
        _ previous: MakeupAdjustments, _ change: (inout MakeupAdjustments) -> Void
    ) -> MakeupAdjustments {
        var makeup = previous
        change(&makeup)
        if makeup != previous {
            makeup.lookID = nil
        }
        return makeup
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
