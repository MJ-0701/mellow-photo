import MellowShared

/// 사진 한 장의 편집 상태.
/// 체크포인트·잠금·보존 규칙은 전부 여기에만 있다.
public struct EditDocument: Equatable, Sendable {
    public enum Rejection: Equatable, Sendable {
        case geometryLocked
        /// 개인 scope의 기록이 없거나 성별을 개인이 아닌 scope에 보냈다.
        case unknownPerson
        /// 그 층에 둘 수 없는 키다(PortraitScope.allows).
        /// 전체 층·남성 그룹의 부유방이다.
        case scopeNotAllowed
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
    /// 수동 편집 좌표가 어긋나지 않도록 얼굴형·체형과 성별 지정을 고정한다.
    public var isGeometryLocked: Bool { recipe.hasLocalEdits }

    public mutating func beginContinuousChange() {
        checkpoint()
        isContinuousChange = true
    }

    public mutating func endContinuousChange() {
        isContinuousChange = false
    }

    /// 얼굴 의존 변경·체형(portraitKey가 있는 것)과 .gender만 scope를 본다.
    /// 나머지는 scope와 무관하게 전체에 쓴다.
    /// 개인 scope의 기록이 없거나 .gender를 개인이 아닌 scope에 보내면 .unknownPerson이고 아무것도 하지 않는다.
    /// 그 층에 둘 수 없는 키(PortraitScope.allows)는 .scopeNotAllowed이고 아무것도 하지 않는다.
    /// 잠금 검사가 먼저다.
    @discardableResult
    public mutating func set(_ change: EditChange, in scope: PortraitScope = .all) -> Rejection? {
        if change.affectsGeometry, isGeometryLocked {
            return .geometryLocked
        }
        if let key = change.portraitKey, !scope.allows(key) {
            return .scopeNotAllowed
        }
        var updated = recipe
        if let rejection = Self.apply(change, scope: scope, to: &updated) {
            return rejection
        }
        return commit(updated)
    }

    /// faces[index]와 짝이 된 기록이 있으면 그 기록에, 없으면 그 얼굴의 anchor로 새 기록을 만들어 같은 변경을 쓴다(한 체크포인트).
    /// 찾은 얼굴을 처음 만질 때의 경로다.
    /// 짝은 렌더와 같은 전역 짝짓기(PeopleAdjustments.personID(forFace:of:))로 정한다.
    /// 그래서 겹친 얼굴에서도 화면에서 고른 얼굴과 값이 바뀌는 얼굴이 같다.
    /// index가 범위 밖이면 .unknownPerson이다.
    @discardableResult
    public mutating func set(_ change: EditChange, forFace index: Int, of faces: [NormalizedRect]) -> Rejection? {
        if change.affectsGeometry, isGeometryLocked {
            return .geometryLocked
        }
        guard faces.indices.contains(index) else { return .unknownPerson }
        var updated = recipe
        let id =
            updated.people.personID(forFace: index, of: faces)
            ?? Self.appendPerson(at: PersonAnchor(faceBox: faces[index]), to: &updated)
        if let rejection = Self.apply(change, scope: .person(id), to: &updated) {
            return rejection
        }
        return commit(updated)
    }

    /// 그 층에서 keys를 지워 상속으로 되돌린다.
    /// nil이면 층 전체이고 개인은 성별 지정을 유지한다.
    /// .all은 그 키를 기본값으로 둔다.
    /// 잠긴 사진에서 실제로 바뀌는 얼굴형·체형 키가 들어 있으면 거절한다.
    @discardableResult
    public mutating func resetOverrides(_ keys: Set<PortraitKey>? = nil, in scope: PortraitScope) -> Rejection? {
        let targets = keys ?? PortraitKey.all
        var updated = recipe
        if scope == .all {
            let changesShape = targets.contains { key in
                switch key {
                case .faceShape(let shape): return recipe.portrait.face[shape] != 0
                case .bodyShape(let shape): return recipe.body[shape] != 0
                default: return false
                }
            }
            guard !(isGeometryLocked && changesShape) else { return .geometryLocked }
            Self.resetAllLayer(targets, in: &updated)
            return commit(updated)
        }
        guard var layer = PortraitResolver.layer(updated, scope: scope) else { return .unknownPerson }
        let removing = targets.intersection(layer.overriddenKeys)
        guard !(isGeometryLocked && removing.contains(where: \.isShape)) else { return .geometryLocked }
        layer.remove(targets)
        if keys == nil {
            layer.makeupLookID = nil
            layer.oneTouch = nil
        }
        Self.store(layer, in: &updated, scope: scope)
        return commit(updated)
    }

    /// 찾지 못한 사람을 다른 얼굴에 연결한다(체크포인트 한 번).
    /// 잠긴 사진에서 그 사람에게 걸린 얼굴형·체형 키가 있으면 거절한다(carriesShape).
    @discardableResult
    public mutating func rebindPerson(_ id: PersonID, to anchor: PersonAnchor) -> Rejection? {
        guard let index = recipe.people.individuals.firstIndex(where: { $0.id == id }) else { return .unknownPerson }
        if isGeometryLocked, carriesShape(recipe.people.individuals[index]) {
            return .geometryLocked
        }
        var updated = recipe
        updated.people.individuals[index].anchor = anchor
        updated.people.individuals[index].legacyIndex = nil
        return commit(updated)
    }

    /// 사람 기록을 지운다(체크포인트 한 번).
    /// 잠긴 사진에서 그 사람에게 걸린 얼굴형·체형 키가 있으면 거절한다(carriesShape).
    @discardableResult
    public mutating func removePerson(_ id: PersonID) -> Rejection? {
        guard let index = recipe.people.individuals.firstIndex(where: { $0.id == id }) else { return .unknownPerson }
        if isGeometryLocked, carriesShape(recipe.people.individuals[index]) {
            return .geometryLocked
        }
        var updated = recipe
        updated.people.individuals.remove(at: index)
        return commit(updated)
    }

    /// 기록 층이나 기록의 수동 성별 그룹 층에 얼굴형·체형 키가 있는지.
    /// 그 기록을 옮기거나 지우면 그 얼굴형·체형 값이 사람 사이를 옮겨 가 수동 편집 좌표가 어긋난다.
    /// 편집 규칙은 자동 추정을 모르므로 그룹은 수동 성별로만 고른다.
    private func carriesShape(_ record: PersonRecord) -> Bool {
        let group = record.gender.flatMap { recipe.people.groups[$0] } ?? PortraitLayer()
        return record.layer.overriddenKeys.union(group.overriddenKeys).contains(where: \.isShape)
    }

    /// 대상 층에 원터치 표 × 강도를 쓴다(스펙 G4 3.3).
    /// 체크포인트 하나이고 연속 변경 중이면 만들지 않는다.
    /// .all은 전체 층에 공통 표, 남성·여성 그룹 층에 각 성별 표, 몸 피부 밝기에 몸 피부 표를 쓴다.
    /// 몸 피부 톤은 표 값이 0인 동안 쓰지 않는다.
    /// 그룹 층의 묶음 밖 키와 개인 층은 그대로 둔다.
    /// .gender는 그 그룹 층만, .person은 그 기록 층에 기록의 수동 성별 표(없으면 공통)를 쓴다.
    /// 강도 0은 묶인 키를 지우고(전체 층은 기본값, 그 외 상속) 표시도 지운다.
    /// 얼굴형·체형 키를 쓰지 않으므로 잠긴 사진에서도 허용한다.
    /// 모르는 사람이면 .unknownPerson이다.
    @discardableResult
    public mutating func applyOneTouch(strength: Double, in scope: PortraitScope = .all) -> Rejection? {
        let clamped = OneTouchBundle.clampedStrength(strength)
        var updated = recipe
        switch scope {
        case .all:
            Self.writeOneTouch(strength: clamped, intoAllLayerOf: &updated)
            for gender in Gender.allCases {
                var group = updated.people.groups[gender] ?? PortraitLayer()
                Self.writeOneTouch(gender: gender, strength: clamped, into: &group)
                updated.people.groups[gender] = group.isEmpty ? nil : group
            }
            let body = OneTouchBundle.bodySkin(strength: clamped)
            updated.bodySkin.brightness = body.brightness
            if OneTouchBundle.writesBodyTone {
                updated.bodySkin.tone = body.tone
            }
        case .gender(let gender):
            var group = updated.people.groups[gender] ?? PortraitLayer()
            Self.writeOneTouch(gender: gender, strength: clamped, into: &group)
            updated.people.groups[gender] = group.isEmpty ? nil : group
        case .person(let id):
            guard let index = updated.people.individuals.firstIndex(where: { $0.id == id }) else {
                return .unknownPerson
            }
            Self.writeOneTouch(
                gender: updated.people.individuals[index].gender, strength: clamped,
                into: &updated.people.individuals[index].layer)
        }
        return commit(updated, clearsStaleMarks: false)
    }

    /// faces[index]와 짝이 된 사람에게 원터치를 쓴다.
    /// 기록이 없으면 그 얼굴 anchor로 만든다(체크포인트 하나).
    /// 짝짓기는 set(_:forFace:of:)·렌더와 같은 PeopleAdjustments.personID(forFace:of:)다.
    /// index가 범위 밖이면 .unknownPerson이다.
    @discardableResult
    public mutating func applyOneTouch(strength: Double, forFace index: Int, of faces: [NormalizedRect]) -> Rejection? {
        guard faces.indices.contains(index) else { return .unknownPerson }
        var updated = recipe
        let id =
            updated.people.personID(forFace: index, of: faces)
            ?? Self.appendPerson(at: PersonAnchor(faceBox: faces[index]), to: &updated)
        guard let recordIndex = updated.people.individuals.firstIndex(where: { $0.id == id }) else {
            return .unknownPerson
        }
        Self.writeOneTouch(
            gender: updated.people.individuals[recordIndex].gender, strength: OneTouchBundle.clampedStrength(strength),
            into: &updated.people.individuals[recordIndex].layer)
        return commit(updated, clearsStaleMarks: false)
    }

    /// 층의 묶인 키를 표 × 강도로 바꾸고 표시를 둔다.
    /// 강도 0은 묶인 키를 지우고 표시도 지운다.
    /// 메이크업 부위가 실제로 바뀌면 룩 이름을 지운다(전체 층과 같은 규칙).
    private static func writeOneTouch(gender: Gender?, strength: Double, into layer: inout PortraitLayer) {
        let previousMakeup = layer.makeup
        layer.remove(OneTouchBundle.keys)
        if strength > 0 {
            copy(OneTouchBundle.keys, from: OneTouchBundle.layer(for: gender, strength: strength), into: &layer)
            layer.oneTouch = strength
        } else {
            layer.oneTouch = nil
        }
        if layer.makeup != previousMakeup {
            layer.makeupLookID = nil
        }
    }

    /// 전체 층에 공통 표 × 강도를 쓴다.
    /// 강도 0은 묶인 키를 기본값으로 두고 표시를 지운다.
    /// 메이크업 색·강도가 그대로면 룩 이름을 지키고 바뀌면 지운다.
    /// 표 층은 늘 메이크업 부위를 담아 applied가 룩 이름을 지우므로 앞의 이름을 따로 들고 있다.
    private static func writeOneTouch(strength: Double, intoAllLayerOf recipe: inout EditRecipe) {
        let previous = recipe.makeup
        resetAllLayer(OneTouchBundle.keys, in: &recipe)
        if strength > 0 {
            OneTouchBundle.layer(for: nil, strength: strength).applied(to: &recipe.portrait, makeup: &recipe.makeup)
            recipe.portrait.oneTouch = strength
        } else {
            recipe.portrait.oneTouch = nil
        }
        var tints = recipe.makeup
        tints.lookID = previous.lookID
        recipe.makeup.lookID = tints == previous ? previous.lookID : nil
    }

    /// legacyIndex만 있는 기록 중 지금 짝짓기에서 faces[legacyIndex]와 짝이 된 기록에 그 anchor를 채운다.
    /// 짝을 잃은 기록은 그대로 둔다(거리 0 anchor로 다른 기록의 얼굴을 빼앗지 않게).
    /// 짝이 된 기록만 채우므로 짝짓기 결과는 그대로다.
    /// 사진을 준비한 뒤 부르는 연결이라 체크포인트를 만들지 않는다.
    /// 바뀐 것이 있으면 true.
    public mutating func bindLegacyPeople(faces: [NormalizedRect]) -> Bool {
        let paired = recipe.people.peopleByFace(faces).mapValues(\.id)
        var changed = false
        for index in recipe.people.individuals.indices where recipe.people.individuals[index].anchor == nil {
            let record = recipe.people.individuals[index]
            guard let legacy = record.legacyIndex, paired[legacy] == record.id else { continue }
            recipe.people.individuals[index].anchor = PersonAnchor(faceBox: faces[legacy])
            recipe.people.individuals[index].legacyIndex = nil
            changed = true
        }
        return changed
    }

    /// 사용자가 고른 프리셋.
    /// 프리셋은 사람을 고르지 않는다.
    /// 전체 층과 성별 그룹 층을 통째로 바꾸고 개인 층·성별 지정은 그대로 둔다.
    /// 잠긴 사진은 전체 층과 그룹 층의 얼굴형·체형을 유지한다.
    /// 바뀌는 값이 없으면 실행 취소 단계를 만들지 않는다.
    public mutating func apply(_ values: PresetValues) {
        let updated = merged(values, categories: SyncCategory.all, clearsIndividuals: false)
        guard updated != recipe else { return }
        checkpoint()
        recipe = updated
    }

    /// 다른 사진의 설정을 일괄 복사.
    /// 고른 항목만 전체·그룹 층에 덮어쓴다(기본은 전부).
    /// 빈 선택은 아무것도 하지 않는다.
    /// 복사한 얼굴 의존 항목은 받는 사진의 개인 층에서 그 키를 지운다.
    /// 성별 지정·anchor는 그대로다.
    /// 바뀌는 값이 없으면(잠긴 사진에 얼굴형만 복사하는 경우 등) 실행 취소 단계를 만들지 않는다.
    public mutating func applyFromBatch(_ values: PresetValues, categories: Set<SyncCategory> = SyncCategory.all) {
        guard !categories.isEmpty else { return }
        let updated = merged(values, categories: categories, clearsIndividuals: true)
        guard updated != recipe else { return }
        checkpoint()
        recipe = updated
    }

    /// 자동 보정 제안을 한 번의 체크포인트로 적용한다.
    /// oneTouchStrength가 nil이면 색·디테일·피부 보정·자동 잡티·눈 또렷하게만 바꾸고
    /// 피부 정밀·치아 미백·입술 생기·성별 그룹·개인 층·얼굴형·체형·배경·몸 피부·메이크업·효과·룩·기하·수동 편집은 건드리지 않는다.
    /// 피부 보정 값이 실제로 바뀌면 전체 층의 원터치 표시를 지운다.
    /// oneTouchStrength가 있으면 색·디테일과 전체 대상 원터치(applyOneTouch(strength:in: .all))를 같은 체크포인트에서 쓰고 제안의 인물 값은 쓰지 않는다.
    /// 얼굴이 있는지는 호출자가 보고 강도를 넘긴다.
    /// 이미 같은 값이면 아무것도 하지 않아 연타해도 실행 취소 한 번에 되돌아간다.
    /// 적용했으면 true.
    @discardableResult
    public mutating func applyAuto(_ suggestion: AutoEnhanceSuggestion, oneTouchStrength: Double? = nil) -> Bool {
        var updated = recipe
        updated.color = suggestion.color
        updated.detail = suggestion.detail
        if let oneTouchStrength {
            var document = EditDocument(recipe: updated)
            document.applyOneTouch(strength: oneTouchStrength, in: .all)
            updated = document.recipe
        } else {
            updated.portrait.skin.smoothing = suggestion.portrait.skin.smoothing
            updated.portrait.skin.autoBlemish = suggestion.portrait.skin.autoBlemish
            updated.portrait.features.eyeBrighten = suggestion.portrait.features.eyeBrighten
            Self.clearStaleOneTouchMarks(previous: recipe, in: &updated)
        }
        guard updated != recipe else { return false }
        checkpoint()
        recipe = updated
        return true
    }

    /// 카탈로그에서 확인한 기존 룩·강도를 한 단계로 적용한다.
    /// 다른 조정·개인 층·수동 편집을 유지하고 같은 값이면 이력을 늘리지 않는다.
    @discardableResult
    public mutating func applyLook(_ selection: LookSelection) -> Bool {
        var updated = recipe
        updated.look = selection
        guard updated != recipe else { return false }
        _ = commit(updated)
        return true
    }

    /// 룩의 부위 값 다섯 개를 scope 층의 메이크업에 써 넣고 lookID를 기록한다(스펙 6).
    /// 전체 층에서 nil이면 메이크업을 모두 지운다(룩 "없음").
    /// 그룹·개인 층에서 nil은 다섯 부위를 0으로 덮어쓴다(상속으로 돌리는 것은 재설정).
    /// 체크포인트 한 번이다.
    /// 색만 바꾸므로 수동 편집이 있어도 잠기지 않는다.
    /// 이미 같은 값이면 아무것도 하지 않는다.
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
        Self.clearStaleOneTouchMarks(previous: recipe, in: &updated)
        updated.people.prune()
        guard updated != recipe else { return }
        checkpoint()
        recipe = updated
    }

    /// faces[index]와 짝이 된 사람에게 룩을 적용한다.
    /// 기록이 없으면 그 얼굴 anchor로 만들며 적용한다(체크포인트 한 번).
    /// 짝짓기는 set(_:forFace:of:)·렌더와 같은 PeopleAdjustments.personID(forFace:of:)다.
    /// 층 규칙은 applyMakeupLook(_:in: .person)과 같다.
    /// index가 범위 밖이거나 이미 같은 값이면 아무것도 하지 않는다.
    public mutating func applyMakeupLook(_ look: MakeupLook?, forFace index: Int, of faces: [NormalizedRect]) {
        guard faces.indices.contains(index) else { return }
        var proposal = EditDocument(recipe: recipe)
        let id =
            proposal.recipe.people.personID(forFace: index, of: faces)
            ?? Self.appendPerson(at: PersonAnchor(faceBox: faces[index]), to: &proposal.recipe)
        proposal.applyMakeupLook(look, in: .person(id))
        let updated = proposal.recipe
        guard updated != recipe else { return }
        checkpoint()
        recipe = updated
    }

    /// 고른 그룹을 프리셋 값으로 바꾼다.
    /// 룩·기하·수동 편집은 그대로 두고, 잠긴 사진은 얼굴형·체형을 건너뛴다.
    /// 얼굴 의존 항목은 그룹 층의 그 키도 바꾸고, clearsIndividuals면 개인 층에서 그 키를 지운다.
    /// 잠긴 사진에서 건너뛴 얼굴형·체형은 개인 층에서도 지우지 않는다.
    private func merged(
        _ values: PresetValues, categories: Set<SyncCategory>, clearsIndividuals: Bool
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
        carryOneTouchMarks(from: values, applied: applied, into: &updated)
        updated.people.prune()
        return updated
    }

    /// 프리셋·동기화의 원터치 표시 규칙(스펙 G4 3.3).
    /// 묶인 키가 바뀐 개인 층의 표시는 지운다.
    /// 피부·눈입·메이크업·몸 피부를 모두 복사하면 전체 층·그룹 층 표시를 원본 것으로 둔다.
    /// 하나라도 빠졌으면 표시가 거짓이 되므로 전체 층·그룹 층 표시를 지운다.
    /// 넷 다 복사하지 않으면 묶인 값이 그대로라 표시도 그대로다.
    private func carryOneTouchMarks(
        from values: PresetValues, applied: Set<SyncCategory>, into updated: inout EditRecipe
    ) {
        Self.clearStaleOneTouchMarks(previous: recipe, in: &updated)
        guard !applied.isDisjoint(with: SyncCategory.oneTouchCategories) else { return }
        let copiesMarks = applied.isSuperset(of: SyncCategory.oneTouchCategories)
        updated.portrait.oneTouch = copiesMarks ? values.portrait.oneTouch : nil
        for gender in Gender.allCases {
            guard var group = updated.people.groups[gender] else { continue }
            group.oneTouch = copiesMarks ? values.people.groups[gender]?.oneTouch : nil
            updated.people.groups[gender] = group
        }
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
            case .bodyShape(let shape): target.body[shape] = source.body[shape]
            }
        }
        if keys.isSuperset(of: PortraitKey.makeup) {
            target.makeupLookID = source.makeupLookID
        }
    }

    /// 묶인 키가 바뀐 층의 원터치 표시와 빈 기록·빈 그룹 층을 지운 뒤 값이 그대로면 체크포인트 없이 끝낸다.
    /// 원터치를 쓰는 경로만 clearsStaleMarks를 끈다(방금 둔 표시를 지키려고).
    private mutating func commit(_ proposed: EditRecipe, clearsStaleMarks: Bool = true) -> Rejection? {
        var updated = proposed
        if clearsStaleMarks {
            Self.clearStaleOneTouchMarks(previous: recipe, in: &updated)
        }
        updated.people.prune()
        // 값이 그대로면 실행 취소 단계를 만들지 않는다.
        guard updated != recipe else { return nil }
        checkpointUnlessContinuous()
        recipe = updated
        return nil
    }

    /// 이전 레시피와 비교해 묶인 키가 실제로 바뀐 층의 원터치 표시를 지운다(메이크업 lookID와 같은 규칙).
    /// 같은 값이면 표시를 남긴다.
    /// 전체 층 표시는 몸 피부 밝기도 본다.
    private static func clearStaleOneTouchMarks(previous: EditRecipe, in updated: inout EditRecipe) {
        if updated.portrait.oneTouch != nil,
            bundledValues(previous.portrait, previous.makeup) != bundledValues(updated.portrait, updated.makeup)
                || bundledBody(previous.bodySkin) != bundledBody(updated.bodySkin)
        {
            updated.portrait.oneTouch = nil
        }
        for gender in Gender.allCases {
            guard var group = updated.people.groups[gender], group.oneTouch != nil else { continue }
            if bundled(previous.people.groups[gender] ?? PortraitLayer()) != bundled(group) {
                group.oneTouch = nil
                updated.people.groups[gender] = group.isEmpty ? nil : group
            }
        }
        for index in updated.people.individuals.indices where updated.people.individuals[index].layer.oneTouch != nil {
            let before = previous.people.person(updated.people.individuals[index].id)?.layer ?? PortraitLayer()
            if bundled(before) != bundled(updated.people.individuals[index].layer) {
                updated.people.individuals[index].layer.oneTouch = nil
            }
        }
    }

    /// 층에서 묶인 키만 남긴 사본이다(표시·룩 이름 제외).
    /// 성긴 층을 그대로 비교하므로 0으로 덮어씀과 상속이 구분된다.
    private static func bundled(_ layer: PortraitLayer) -> PortraitLayer {
        var copy = layer
        copy.remove(PortraitKey.all.subtracting(OneTouchBundle.keys))
        copy.oneTouch = nil
        copy.makeupLookID = nil
        return copy
    }

    /// 전체 층 표시에 묶인 몸 피부 값.
    /// 밝기는 늘 묶이고 톤은 원터치가 쓸 때만 묶인다.
    private static func bundledBody(_ body: BodySkinAdjustments) -> [Double] {
        OneTouchBundle.writesBodyTone ? [body.brightness, body.tone] : [body.brightness]
    }

    /// 전체 층의 묶인 값.
    /// 전체 층은 빽빽한 값이라 기본값과 같은 키는 없음과 같게 본다.
    private static func bundledValues(_ portrait: PortraitAdjustments, _ makeup: MakeupAdjustments) -> PortraitLayer {
        bundled(PortraitLayer.difference(portrait: portrait, makeup: makeup))
    }

    /// 짝이 없는 얼굴의 새 기록.
    /// 그 얼굴과 거리 0이라 다음 짝짓기에서 그 얼굴과 짝이 된다.
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
            // 원터치 표시는 그 사람의 성별 표와 같다는 뜻이라 성별이 바뀌면 거짓이 된다.
            if updated.people.individuals[index].gender != gender {
                updated.people.individuals[index].layer.oneTouch = nil
            }
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
        case .bodyShape(let shape, let value):
            layer.body[shape] = EditingPolicy.clamped(value, to: EditingPolicy.bodyShapeRange(shape))
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
            case .bodyShape(let shape): recipe.body[shape] = 0
            }
        }
        if keys.isSuperset(of: PortraitKey.makeup) {
            recipe.makeup.lookID = nil
        }
    }

    /// 부위 값이 실제로 바뀌었으면 룩 이름을 지운다(스펙 6).
    /// 같은 값이면 룩을 유지한다.
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

    /// 실행 취소·다시 실행·초기화는 진행 중이던 연속 변경을 끝낸다.
    /// 이후 편집은 다시 체크포인트한다.
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

extension EditDocument {
    /// 새 계획 경로. positive 기본 적용은 개인값을 보호하며 실제 준비된 키만 쓴다.
    /// 명시 교체의 0은 개인 neutral 값이다. 기존 applyOneTouch(0)의 상속 복귀와 별개다.
    @discardableResult
    public mutating func applyOneTouchReporting(
        strength: Double, in scope: OneTouchApplicationScope = .all, faces: [NormalizedRect],
        targets: [PortraitPurposeFace], replacingPersonal: Bool = false, bodySkinAvailable: Bool = false
    ) -> OneTouchApplicationResult {
        let scale = OneTouchBundle.clampedStrength(strength)
        let before = recipe
        let oldPeople = before.people.peopleByFace(faces)
        let valid =
            strength.isFinite && !targets.isEmpty
            && Set(targets.map(\.index)).count == targets.count
            && targets.allSatisfy { faces.indices.contains($0.index) }
            && !faces.indices.contains { index in faces[..<index].contains(faces[index]) }
        guard valid, replacingPersonal || scale > 0 else {
            return OneTouchApplicationResult(requestedStrength: scale, items: [], bodySkinChanged: false)
        }
        // scope와 대상의 불일치를 추측으로 보완하지 않는다.
        let scoped = targets.filter { target in
            switch scope {
            case .all: return true
            case .gender(let gender):
                return PortraitResolver.effectiveGender(person: oldPeople[target.index], estimate: target.gender)
                    == gender
            case .person(let id): return oldPeople[target.index]?.id == id
            case .face(let index): return target.index == index
            }
        }
        let completeScope: Bool
        if !replacingPersonal, scope == .all {
            completeScope = Set(scoped.map(\.index)) == Set(faces.indices)
        } else {
            completeScope = true
        }
        guard scoped.count == targets.count, completeScope else {
            return OneTouchApplicationResult(requestedStrength: scale, items: [], bodySkinChanged: false)
        }
        var updated = before
        var createdPeople: [Int: PersonID] = [:]
        if replacingPersonal {
            for target in scoped {
                let person = oldPeople[target.index]
                let gender = PortraitResolver.effectiveGender(person: person, estimate: target.gender)
                let resolved = PortraitResolver.resolve(before, person: person, gender: gender)
                let source = Self.oneTouchNeutralOrTable(gender: gender, strength: scale)
                var desiredPortrait = resolved.portrait
                var desiredMakeup = resolved.makeup
                source.applied(to: &desiredPortrait, makeup: &desiredMakeup)
                let desired = PortraitResolver.Resolved(
                    portrait: desiredPortrait, makeup: desiredMakeup, body: resolved.body)
                let keys = target.availableKeys.intersection(OneTouchBundle.keys).filter {
                    OneTouchApplicationResult.value($0, in: resolved)
                        != OneTouchApplicationResult.value($0, in: desired)
                }
                guard !keys.isEmpty else { continue }
                let id = person?.id ?? Self.appendPerson(at: PersonAnchor(faceBox: faces[target.index]), to: &updated)
                if person == nil { createdPeople[target.index] = id }
                guard let index = updated.people.individuals.firstIndex(where: { $0.id == id }) else { continue }
                let writeKeys = target.availableKeys.intersection(OneTouchBundle.keys).filter { key in
                    if case .makeupPart = key {
                        return OneTouchApplicationResult.value(key, in: resolved)
                            != OneTouchApplicationResult.value(key, in: desired)
                    }
                    return true
                }
                Self.copy(Set(writeKeys), from: source, into: &updated.people.individuals[index].layer)
                if keys.contains(where: {
                    if case .makeupPart = $0 { return true }
                    return false
                }) {
                    updated.people.individuals[index].layer.makeupLookID = nil
                }
                // 부분 적용을 전체 묶음 강도로 표시하지 않는다.
                updated.people.individuals[index].layer.oneTouch =
                    target.availableKeys.isSuperset(of: OneTouchBundle.keys) ? scale : nil
            }
        } else {
            // 기본 동작은 기존 proposal 그대로다. 미준비 키의 저장과 현재 렌더 준비를 보고에서 구분한다.
            var legacy = self
            switch scope {
            case .all: _ = legacy.applyOneTouch(strength: scale)
            case .gender(let gender): _ = legacy.applyOneTouch(strength: scale, in: .gender(gender))
            case .person(let id): _ = legacy.applyOneTouch(strength: scale, in: .person(id))
            case .face(let index): _ = legacy.applyOneTouch(strength: scale, forFace: index, of: faces)
            }
            updated = legacy.recipe
        }
        let newPeople = updated.people.peopleByFace(faces)
        let pairingValid =
            oldPeople.allSatisfy { newPeople[$0.key]?.id == $0.value.id }
            && scoped.allSatisfy { target in
                guard let new = newPeople[target.index] else {
                    return oldPeople[target.index] == nil && createdPeople[target.index] == nil
                }
                if let created = createdPeople[target.index] { return new.id == created }
                return oldPeople[target.index]?.id == new.id
            }
        let items = scoped.flatMap { target in
            OneTouchBundle.keys.sorted { String(describing: $0) < String(describing: $1) }.map { key in
                let person = oldPeople[target.index]
                let gender = PortraitResolver.effectiveGender(person: person, estimate: target.gender)
                let previous = OneTouchApplicationResult.value(
                    key, in: PortraitResolver.resolve(before, person: person, gender: gender))
                let next =
                    pairingValid
                    ? OneTouchApplicationResult.value(
                        key, in: PortraitResolver.resolve(updated, person: newPeople[target.index], gender: gender))
                    : previous
                let reason: OneTouchApplicationResult.Reason
                if !pairingValid {
                    reason = .invalidTargets
                } else if !target.availableKeys.contains(key) {
                    reason = .unavailable
                } else if !replacingPersonal && previous == next && person?.layer.overriddenKeys.contains(key) == true {
                    reason = .protectedPersonal
                } else {
                    reason = previous == next ? .unchanged : .changed
                }
                return OneTouchApplicationResult.Item(
                    faceIndex: target.index, key: key, before: previous, after: next, reason: reason,
                    renderReady: target.availableKeys.contains(key))
            }
        }
        var result = OneTouchApplicationResult(
            requestedStrength: scale, items: items,
            bodySkinChanged: pairingValid && bodySkinAvailable && before.bodySkin != updated.bodySkin)
        result.bodySkinBefore = before.bodySkin
        result.bodySkinAfter = updated.bodySkin
        guard pairingValid, result.hasChanges else {
            var noOp = OneTouchApplicationResult(
                requestedStrength: scale,
                items: items.map {
                    .init(
                        faceIndex: $0.faceIndex, key: $0.key, before: $0.before, after: $0.before,
                        reason: $0.reason, renderReady: $0.renderReady)
                }, bodySkinChanged: false)
            noOp.bodySkinBefore = before.bodySkin
            noOp.bodySkinAfter = before.bodySkin
            return noOp
        }
        _ = commit(updated, clearsStaleMarks: false)
        return result
    }

    private static func oneTouchNeutralOrTable(gender: Gender?, strength: Double) -> PortraitLayer {
        guard strength == 0 else { return OneTouchBundle.layer(for: gender, strength: strength) }
        var neutral = OneTouchBundle.layer(for: gender, strength: 1)
        neutral.skinSmoothing = 0
        neutral.autoBlemish = false
        for key in SkinRefinementKey.allCases { neutral.skinRefinement[key] = 0 }
        for key in FeatureKey.allCases { neutral.features[key] = 0 }
        neutral.makeup[.blush] = MakeupTint(colorID: nil, intensity: 0)
        neutral.makeup[.lip] = MakeupTint(colorID: nil, intensity: 0)
        neutral.oneTouch = 0
        return neutral
    }
}
