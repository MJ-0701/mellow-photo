import MellowShared

/// 기존 피부 묶음과 형태 도구를 목적별로 명시 적용한다. 렌더 강도는 바꾸지 않는다.
public enum PortraitPurpose: Equatable, Sendable {
    case skin
    case underChin
    case sideChest

    /// 자동 잡티(false 포함), 눈입, 메이크업, 몸 피부는 피부 전용 적용에서 제외한다.
    public var keys: Set<PortraitKey> {
        switch self {
        case .skin: return PortraitKey.skin.subtracting([.autoBlemish])
        case .underChin: return [.faceShape(.doubleChin)]
        case .sideChest: return [.bodyShape(.sideChest)]
        }
    }
}

public struct PortraitPurposeFace: Equatable, Sendable {
    public let index: Int
    public let gender: Gender?
    /// 실제 렌더 준비가 확인한 키만 전달한다. 얼굴 개수로 준비 상태를 추정하지 않는다.
    public let availableKeys: Set<PortraitKey>

    public init(index: Int, gender: Gender?, availableKeys: Set<PortraitKey>) {
        self.index = index
        self.gender = gender
        self.availableKeys = availableKeys
    }
}

public struct PortraitPurposeResult: Equatable, Sendable {
    public enum Reason: Equatable, Sendable {
        case changed
        case keptExisting
        case unavailable
        case unchanged
        case geometryLocked
        case pairingChanged
    }
    public struct Item: Equatable, Sendable {
        public let faceIndex: Int
        public let key: PortraitKey
        public let reason: Reason
        public let resolvedBefore: Double
        public let resolvedAfter: Double
        public let gender: Gender?
    }
    public let items: [Item]
    public var changedCount: Int { items.filter { $0.reason == .changed }.count }
}

extension EditDocument {
    /// 강도 0은 적용하지 않는다. 해제/되돌리기는 기존 Undo로 처리해 개인값을 되살리거나 지우지 않는다.
    /// 후보를 따로 만들어 실제 변경이 있는 경우에만 한 단계로 전달한다.
    public mutating func applyPortraitPurpose(
        _ purpose: PortraitPurpose, strength: Double, faces: [NormalizedRect],
        targets: [PortraitPurposeFace], replacingExisting: Bool = false
    ) -> PortraitPurposeResult {
        guard strength.isFinite, strength > 0 else { return PortraitPurposeResult(items: []) }
        let before = self
        let originalPeople = recipe.people.peopleByFace(faces)
        var proposal = self
        var items: [PortraitPurposeResult.Item] = []
        proposal.beginContinuousChange()
        var visited: Set<Int> = []
        for target in targets.sorted(by: { $0.index < $1.index }) where faces.indices.contains(target.index) {
            guard visited.insert(target.index).inserted else { continue }
            let person = originalPeople[target.index]
            let gender = PortraitResolver.effectiveGender(person: person, estimate: target.gender)
            let resolved = PortraitResolver.resolve(before.recipe, person: person, gender: gender)
            let explicit = (person?.layer.overriddenKeys ?? [])
                .union(gender.flatMap { before.recipe.people.groups[$0]?.overriddenKeys } ?? [])
            for change in purpose.changes(gender: gender, strength: strength) {
                guard let key = change.portraitKey else { continue }
                let previousValue = purpose.value(key, in: resolved)
                var proposedValue = previousValue
                let reason: PortraitPurposeResult.Reason
                if !target.availableKeys.contains(key) {
                    reason = .unavailable
                } else if key.isShape && before.isGeometryLocked {
                    reason = .geometryLocked
                } else if !replacingExisting && (explicit.contains(key) || purpose.value(key, in: resolved) != 0) {
                    reason = .keptExisting
                } else {
                    var check = proposal
                    if check.set(change, forFace: target.index, of: faces) != nil {
                        reason = .unavailable
                    } else {
                        let updatedPerson = check.recipe.people.peopleByFace(faces)[target.index]
                        let updated = PortraitResolver.resolve(check.recipe, person: updatedPerson, gender: gender)
                        if purpose.value(key, in: resolved) == purpose.value(key, in: updated) {
                            reason = .unchanged
                        } else {
                            reason = .changed
                            proposedValue = purpose.value(key, in: updated)
                            proposal = check
                        }
                    }
                }
                items.append(
                    .init(
                        faceIndex: target.index, key: key, reason: reason,
                        resolvedBefore: previousValue, resolvedAfter: proposedValue, gender: gender))
            }
        }
        proposal.endContinuousChange()
        let result = PortraitPurposeResult(items: items)
        guard result.changedCount > 0 else { return result }
        // 새 개인 기록 때문에 기존 다른 사람의 연결이 바뀌면 전부 거절한다.
        let afterPeople = proposal.recipe.people.peopleByFace(faces)
        for (index, person) in originalPeople where afterPeople[index]?.id != person.id {
            return PortraitPurposeResult(
                items: items.map {
                    .init(
                        faceIndex: $0.faceIndex, key: $0.key, reason: .pairingChanged,
                        resolvedBefore: $0.resolvedBefore, resolvedAfter: $0.resolvedBefore, gender: $0.gender)
                })
        }
        self = proposal
        return result
    }
}

private extension PortraitPurpose {
    func changes(gender: Gender?, strength: Double) -> [EditChange] {
        let scale = OneTouchBundle.clampedStrength(strength)
        switch self {
        case .skin:
            let layer = OneTouchBundle.layer(for: gender, strength: scale)
            return [.skinSmoothing(layer.skinSmoothing ?? 0)]
                + SkinRefinementKey.allCases.map {
                    .skinRefinement($0, layer.skinRefinement[$0] ?? 0)
                }
        case .underChin: return [.faceShape(.doubleChin, scale)]
        case .sideChest: return [.bodyShape(.sideChest, scale)]
        }
    }

    func value(_ key: PortraitKey, in resolved: PortraitResolver.Resolved) -> Double {
        switch key {
        case .skinSmoothing: return resolved.portrait.skin.smoothing
        case .skinRefinement(let key): return resolved.portrait.skin[key]
        case .faceShape(let key): return resolved.portrait.face[key]
        case .bodyShape(let key): return resolved.body[key]
        default: return 0
        }
    }
}
