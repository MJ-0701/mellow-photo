import MellowShared

/// 사진 한 장의 편집 상태. 체크포인트·잠금·보존 규칙은 전부 여기에만 있다.
public struct EditDocument: Equatable, Sendable {
    public enum Rejection: Equatable, Sendable {
        case geometryLocked
        /// 개인 scope의 기록이 없거나 성별을 개인이 아닌 scope에 보냈다.
        case unknownPerson
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

    /// 얼굴 의존 변경(portraitKey가 있는 것과 .gender)만 scope를 본다.
    /// 나머지는 scope와 무관하게 전체에 쓴다.
    /// 개인 scope의 기록이 없거나 .gender를 개인이 아닌 scope에 보내면 .unknownPerson이고 아무것도 하지 않는다.
    @discardableResult
    public mutating func set(_ change: EditChange, in scope: PortraitScope = .all) -> Rejection? {
        if change.affectsGeometry, isGeometryLocked {
            return .geometryLocked
        }
        var updated = recipe
        if let rejection = Self.apply(change, scope: scope, to: &updated) {
            return rejection
        }
        return commit(updated)
    }

    /// anchor에 해당하는 기록이 있으면 그 기록에, 없으면 새 기록을 만들어 같은 변경을 쓴다(한 체크포인트).
    /// 찾은 얼굴을 처음 만질 때의 경로다.
    @discardableResult
    public mutating func set(_ change: EditChange, forPersonAt anchor: PersonAnchor) -> Rejection? {
        if change.affectsGeometry, isGeometryLocked {
            return .geometryLocked
        }
        var updated = recipe
        let id = updated.people.personID(at: anchor) ?? Self.appendPerson(at: anchor, to: &updated)
        if let rejection = Self.apply(change, scope: .person(id), to: &updated) {
            return rejection
        }
        return commit(updated)
    }

    /// 그 층에서 keys를 지워 상속으로 되돌린다.
    /// nil이면 층 전체이고 개인은 성별 지정을 유지한다.
    /// .all은 그 키를 기본값으로 둔다.
    /// 잠긴 사진에서 실제로 바뀌는 얼굴형 키가 들어 있으면 거절한다.
    @discardableResult
    public mutating func resetOverrides(_ keys: Set<PortraitKey>? = nil, in scope: PortraitScope) -> Rejection? {
        let targets = keys ?? PortraitKey.all
        var updated = recipe
        if scope == .all {
            let changesShape = targets.contains { key in
                guard case .faceShape(let shape) = key else { return false }
                return recipe.portrait.face[shape] != 0
            }
            guard !(isGeometryLocked && changesShape) else { return .geometryLocked }
            Self.resetAllLayer(targets, in: &updated)
            return commit(updated)
        }
        guard var layer = PortraitResolver.layer(updated, scope: scope) else { return .unknownPerson }
        let removing = targets.intersection(layer.overriddenKeys)
        guard !(isGeometryLocked && removing.contains(where: \.isFaceShape)) else { return .geometryLocked }
        layer.remove(targets)
        if keys == nil {
            layer.makeupLookID = nil
        }
        Self.store(layer, in: &updated, scope: scope)
        return commit(updated)
    }

    /// 찾지 못한 사람을 다른 얼굴에 연결한다(체크포인트 한 번).
    /// 얼굴형 키가 있고 잠겼으면 거절한다.
    @discardableResult
    public mutating func rebindPerson(_ id: PersonID, to anchor: PersonAnchor) -> Rejection? {
        guard let index = recipe.people.individuals.firstIndex(where: { $0.id == id }) else { return .unknownPerson }
        if isGeometryLocked, recipe.people.individuals[index].layer.overriddenKeys.contains(where: \.isFaceShape) {
            return .geometryLocked
        }
        var updated = recipe
        updated.people.individuals[index].anchor = anchor
        updated.people.individuals[index].legacyIndex = nil
        return commit(updated)
    }

    /// 사람 기록을 지운다(체크포인트 한 번).
    /// 얼굴형 키가 있고 잠겼으면 거절한다.
    @discardableResult
    public mutating func removePerson(_ id: PersonID) -> Rejection? {
        guard let index = recipe.people.individuals.firstIndex(where: { $0.id == id }) else { return .unknownPerson }
        if isGeometryLocked, recipe.people.individuals[index].layer.overriddenKeys.contains(where: \.isFaceShape) {
            return .geometryLocked
        }
        var updated = recipe
        updated.people.individuals.remove(at: index)
        return commit(updated)
    }

    /// legacyIndex만 있는 기록에 faces[legacyIndex]의 anchor를 채운다.
    /// 사진을 준비한 뒤 부르는 연결이라 체크포인트를 만들지 않는다.
    /// 바뀐 것이 있으면 true.
    public mutating func bindLegacyPeople(faces: [NormalizedRect]) -> Bool {
        var changed = false
        for index in recipe.people.individuals.indices where recipe.people.individuals[index].anchor == nil {
            guard let legacy = recipe.people.individuals[index].legacyIndex, faces.indices.contains(legacy) else {
                continue
            }
            recipe.people.individuals[index].anchor = PersonAnchor(faceBox: faces[legacy])
            recipe.people.individuals[index].legacyIndex = nil
            changed = true
        }
        return changed
    }

    /// 사용자가 고른 프리셋. 프리셋은 얼굴을 고르지 않으므로 대상 얼굴은 늘 사진의 값을 유지한다.
    /// 전체 층과 성별 그룹 층을 통째로 바꾸고 개인 층·성별 지정은 그대로 둔다.
    /// 잠긴 사진은 전체 층과 그룹 층의 얼굴형·체형을 유지한다. 바뀌는 값이 없으면 실행 취소 단계를 만들지 않는다.
    public mutating func apply(_ values: PresetValues) {
        let updated = merged(
            values, targetFace: recipe.portrait.targetFace, categories: SyncCategory.all, clearsIndividuals: false)
        guard updated != recipe else { return }
        checkpoint()
        recipe = updated
    }

    /// 다른 사진의 설정을 일괄 복사. 고른 항목만 전체·그룹 층에 덮어쓴다(기본은 전부). 빈 선택은 아무것도 하지 않는다.
    /// 복사한 얼굴 의존 항목은 받는 사진의 개인 층에서 그 키를 지운다. 성별 지정·anchor는 그대로다.
    /// 잠기지 않은 사진은 얼굴 의존 항목을 복사할 때만 대상 얼굴을 전체로 되돌린다.
    /// 바뀌는 값이 없으면(잠긴 사진에 얼굴형만 복사하는 경우 등) 실행 취소 단계를 만들지 않는다.
    public mutating func applyFromBatch(_ values: PresetValues, categories: Set<SyncCategory> = SyncCategory.all) {
        guard !categories.isEmpty else { return }
        let resetsTarget = !isGeometryLocked && categories.contains { $0.dependsOnFaces }
        let updated = merged(
            values, targetFace: resetsTarget ? nil : recipe.portrait.targetFace, categories: categories,
            clearsIndividuals: true)
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

    /// 룩의 부위 값 다섯 개를 scope 층의 메이크업에 써 넣고 lookID를 기록한다(스펙 6).
    /// 전체 층에서 nil이면 메이크업을 모두 지운다(룩 "없음").
    /// 그룹·개인 층에서 nil은 다섯 부위를 0으로 덮어쓴다(상속으로 돌리는 것은 재설정).
    /// 체크포인트 한 번이다. 색만 바꾸므로 수동 편집이 있어도 잠기지 않는다. 이미 같은 값이면 아무것도 하지 않는다.
    /// 모르는 사람이면 아무것도 하지 않는다.
    public mutating func applyMakeupLook(_ look: MakeupLook?, in scope: PortraitScope = .all) {
        let adjustments = look?.adjustments ?? MakeupAdjustments()
        var updated = recipe
        if scope == .all {
            updated.makeup = adjustments
        } else {
            guard var layer = PortraitResolver.layer(recipe, scope: scope) else { return }
            for part in MakeupPart.allCases {
                layer.makeup[part] = Self.inherited(part, from: adjustments)
            }
            layer.makeupLookID = look?.id
            Self.store(layer, in: &updated, scope: scope)
        }
        updated.people.prune()
        guard updated != recipe else { return }
        checkpoint()
        recipe = updated
    }

    /// 고른 그룹을 프리셋 값으로 바꾼다. 룩·기하·수동 편집은 그대로 두고, 잠긴 사진은 얼굴형·체형을 건너뛴다.
    /// 얼굴 의존 항목은 그룹 층의 그 키도 바꾸고, clearsIndividuals면 개인 층에서 그 키를 지운다.
    /// 잠긴 사진에서 건너뛴 얼굴형은 개인 층에서도 지우지 않는다.
    private func merged(
        _ values: PresetValues, targetFace: Int?, categories: Set<SyncCategory>, clearsIndividuals: Bool
    ) -> EditRecipe {
        var updated = recipe
        var applied = categories
        if isGeometryLocked {
            applied.remove(.faceShape)
            applied.remove(.body)
        }
        if applied.contains(.color) {
            updated.color = values.color
            updated.detail = values.detail
        }
        if applied.contains(.effects) {
            updated.effects = values.effects
        }
        if applied.contains(.skin) {
            updated.portrait.skin = values.portrait.skin
        }
        if applied.contains(.faceShape) {
            updated.portrait.face = values.portrait.face
        }
        if applied.contains(.features) {
            updated.portrait.features = values.portrait.features
        }
        if applied.contains(.makeup) {
            updated.makeup = values.makeup
        }
        if applied.contains(.background) {
            updated.background = values.background
        }
        if applied.contains(.body) {
            updated.body = values.body
        }
        if applied.contains(.bodySkin) {
            updated.bodySkin = values.bodySkin
        }
        for keys in applied.compactMap(\.portraitKeys) {
            for gender in Gender.allCases {
                var group = updated.people.groups[gender] ?? PortraitLayer()
                Self.copy(keys, from: values.people.groups[gender] ?? PortraitLayer(), into: &group)
                updated.people.groups[gender] = group
            }
            if clearsIndividuals {
                for index in updated.people.individuals.indices {
                    updated.people.individuals[index].layer.remove(keys)
                }
            }
        }
        updated.people.prune()
        updated.portrait.targetFace = targetFace
        return updated
    }

    /// target의 keys를 source의 값으로 바꾼다(source에 없는 키는 지움).
    /// 메이크업 전부를 옮기면 룩 이름도 옮긴다.
    private static func copy(_ keys: Set<PortraitKey>, from source: PortraitLayer, into target: inout PortraitLayer) {
        target.remove(keys)
        for key in keys.intersection(source.overriddenKeys) {
            switch key {
            case .skinSmoothing: target.skinSmoothing = source.skinSmoothing
            case .autoBlemish: target.autoBlemish = source.autoBlemish
            case .skinRefinement(let refinement): target.skinRefinement[refinement] = source.skinRefinement[refinement]
            case .faceShape(let shape): target.face[shape] = source.face[shape]
            case .feature(let feature): target.features[feature] = source.features[feature]
            case .makeupPart(let part): target.makeup[part] = source.makeup[part]
            }
        }
        if keys.isSuperset(of: PortraitKey.makeup) {
            target.makeupLookID = source.makeupLookID
        }
    }

    /// 빈 기록과 빈 그룹 층을 지운 뒤 값이 그대로면 체크포인트 없이 끝낸다.
    private mutating func commit(_ proposed: EditRecipe) -> Rejection? {
        var updated = proposed
        updated.people.prune()
        // 값이 그대로면 실행 취소 단계를 만들지 않는다.
        guard updated != recipe else { return nil }
        checkpointUnlessContinuous()
        recipe = updated
        return nil
    }

    private static func appendPerson(at anchor: PersonAnchor, to recipe: inout EditRecipe) -> PersonID {
        let record = PersonRecord(anchor: anchor)
        recipe.people.individuals.append(record)
        return record.id
    }

    /// 변경을 제안 레시피에 쓴다.
    /// 잠금은 호출자가 먼저 본다.
    private static func apply(_ change: EditChange, scope: PortraitScope, to updated: inout EditRecipe) -> Rejection? {
        if case .gender(let gender) = change {
            guard case .person(let id) = scope,
                let index = updated.people.individuals.firstIndex(where: { $0.id == id })
            else { return .unknownPerson }
            updated.people.individuals[index].gender = gender
            return nil
        }
        guard scope != .all, let key = change.portraitKey else {
            updated = applyingToAllLayer(change, to: updated)
            return nil
        }
        guard var layer = PortraitResolver.layer(updated, scope: scope) else { return .unknownPerson }
        write(change, key: key, into: &layer, beneath: beneath(updated, scope: scope))
        store(layer, in: &updated, scope: scope)
        return nil
    }

    /// 전체 층과 사진 단위 값에 변경을 쓴다.
    private static func applyingToAllLayer(_ change: EditChange, to recipe: EditRecipe) -> EditRecipe {
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
        // 성별은 개인 층에만 쓴다(apply가 먼저 처리한다).
        case .gender: break
        }
        return updated
    }

    /// 그 층 아래를 겹친 값.
    /// 메이크업 색을 처음 고를 때의 기본 강도 기준이다.
    /// 개인은 기록의 수동 성별로 그룹을 고른다(편집 규칙은 자동 추정을 모른다).
    private static func beneath(_ recipe: EditRecipe, scope: PortraitScope) -> PortraitResolver.Resolved {
        switch scope {
        case .all, .gender:
            return PortraitResolver.resolve(recipe, person: nil, gender: nil)
        case .person(let id):
            return PortraitResolver.resolve(recipe, person: nil, gender: recipe.people.person(id)?.gender)
        }
    }

    /// 층에 키 하나를 쓴다.
    /// 전체 층과 같은 클램프·룩 해제 규칙이다.
    private static func write(
        _ change: EditChange, key: PortraitKey, into layer: inout PortraitLayer, beneath: PortraitResolver.Resolved
    ) {
        switch change {
        case .skinSmoothing(let value):
            layer.skinSmoothing = EditingPolicy.clamped(value, to: EditingPolicy.unitRange)
        case .autoBlemish(let flag):
            layer.autoBlemish = flag
        case .skinRefinement(let refinement, let value):
            layer.skinRefinement[refinement] = EditingPolicy.clamped(
                value, to: EditingPolicy.skinRefinementRange(refinement))
        case .faceShape(let shape, let value):
            layer.face[shape] = EditingPolicy.clamped(value, to: EditingPolicy.faceShapeRange(shape))
        case .feature(let feature, let value):
            layer.features[feature] = EditingPolicy.clamped(value, to: EditingPolicy.unitRange)
        case .makeupColor(let part, let id):
            guard part.hasColor else { return }
            var tint = layer.makeup[part] ?? inherited(part, from: beneath.makeup)
            tint.colorID = id
            if id != nil, tint.intensity == 0 {
                tint.intensity = EditingPolicy.makeupDefaultIntensity
            }
            replaceMakeup(part, with: tint, in: &layer)
        case .makeupIntensity(let part, let value):
            var tint = layer.makeup[part] ?? inherited(part, from: beneath.makeup)
            tint.intensity = EditingPolicy.clamped(value, to: EditingPolicy.unitRange)
            replaceMakeup(part, with: tint, in: &layer)
        default:
            return
        }
    }

    /// 아래 층의 부위 값을 층의 부위 값 모양으로 바꾼다.
    private static func inherited(_ part: MakeupPart, from makeup: MakeupAdjustments) -> MakeupTint {
        MakeupTint(colorID: part.hasColor ? makeup.colorID(of: part) : nil, intensity: makeup.intensity(of: part))
    }

    /// 부위 값이 실제로 바뀌면 그 층의 룩 이름을 지운다(전체 층과 같은 규칙).
    private static func replaceMakeup(_ part: MakeupPart, with tint: MakeupTint, in layer: inout PortraitLayer) {
        if layer.makeup[part] != tint {
            layer.makeupLookID = nil
        }
        layer.makeup[part] = tint
    }

    /// 층을 제자리에 둔다.
    /// 빈 그룹 층은 키를 지운다.
    private static func store(_ layer: PortraitLayer, in recipe: inout EditRecipe, scope: PortraitScope) {
        switch scope {
        case .all:
            return
        case .gender(let gender):
            recipe.people.groups[gender] = layer.isEmpty ? nil : layer
        case .person(let id):
            if let index = recipe.people.individuals.firstIndex(where: { $0.id == id }) {
                recipe.people.individuals[index].layer = layer
            }
        }
    }

    /// 전체 층의 키를 기본값으로 둔다.
    /// 메이크업 다섯 부위를 모두 지우면 룩 이름도 지운다.
    private static func resetAllLayer(_ keys: Set<PortraitKey>, in recipe: inout EditRecipe) {
        for key in keys {
            switch key {
            case .skinSmoothing: recipe.portrait.skin.smoothing = 0
            case .autoBlemish: recipe.portrait.skin.autoBlemish = false
            case .skinRefinement(let refinement): recipe.portrait.skin[refinement] = 0
            case .faceShape(let shape): recipe.portrait.face[shape] = 0
            case .feature(let feature): recipe.portrait.features[feature] = 0
            case .makeupPart(let part):
                if part.hasColor {
                    recipe.makeup.setColorID(nil, of: part)
                }
                recipe.makeup.setIntensity(0, of: part)
            }
        }
        if keys.isSuperset(of: PortraitKey.makeup) {
            recipe.makeup.lookID = nil
        }
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
