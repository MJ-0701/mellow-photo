import Foundation

/// 성별 그룹.
/// 레시피 JSON 키와 같다.
/// 지정하지 않은 사람은 nil이다.
public enum Gender: String, CaseIterable, Codable, Sendable {
    case male
    case female
}

/// 레시피 안 사람 기록의 키.
/// 편집이 사람을 가리킬 때 쓴다.
public struct PersonID: Hashable, Codable, Sendable {
    /// 옛 targetFace에서 이행한 기록의 id 접두사.
    /// 뒤 12자리가 얼굴 인덱스다.
    private static let legacyPrefix = "B0000000-0000-0000-0000-"
    /// 접두사 뒤 인덱스 자리 수.
    private static let legacyDigits = 12
    /// 12자리에 들어가는 인덱스 범위.
    /// 밖의 인덱스(음수·손상 파일)는 upperBound로 모은다.
    public static let legacyIndexRange = 0...999_999_999_999

    public let rawValue: UUID

    public init() {
        rawValue = UUID()
    }

    public init(rawValue: UUID) {
        self.rawValue = rawValue
    }

    /// 옛 targetFace 이행용 결정적 id.
    /// 같은 파일을 두 번 읽어도 같다.
    /// 범위 밖 인덱스는 어느 얼굴과도 짝이 되지 않는 마지막 값으로 모은다(크래시하지 않는다).
    public static func legacy(index: Int) -> PersonID {
        let safe = legacyIndexRange.contains(index) ? index : legacyIndexRange.upperBound
        let digits = String(safe)
        let suffix = String(repeating: "0", count: legacyDigits - digits.count) + digits
        guard let uuid = UUID(uuidString: legacyPrefix + suffix) else {
            preconditionFailure("legacy person index out of range: \(index)")
        }
        return PersonID(rawValue: uuid)
    }

    public init(from decoder: Decoder) throws {
        rawValue = try decoder.singleValueContainer().decode(UUID.self)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

/// 사람을 다시 찾는 열쇠.
/// 정규화 얼굴 상자의 중심과 폭이다(원점 왼쪽 아래, 원본 기준).
public struct PersonAnchor: Codable, Equatable, Sendable {
    public var x: Double
    public var y: Double
    public var width: Double

    public init(x: Double, y: Double, width: Double) {
        self.x = x
        self.y = y
        self.width = width
    }

    public init(faceBox: NormalizedRect) {
        self.init(x: faceBox.midX, y: faceBox.midY, width: faceBox.width)
    }
}

/// 층이 덮어쓸 수 있는 키.
/// 편집·화면·동기화가 같은 이름을 쓴다.
public enum PortraitKey: Hashable, Sendable {
    case skinSmoothing
    case autoBlemish
    case skinRefinement(SkinRefinementKey)
    case faceShape(FaceShapeKey)
    case feature(FeatureKey)
    case makeupPart(MakeupPart)

    public var isFaceShape: Bool {
        if case .faceShape = self {
            return true
        }
        return false
    }

    /// 피부 보정·자동 잡티·정밀 7종.
    public static let skin: Set<PortraitKey> = {
        var keys: [PortraitKey] = [.skinSmoothing, .autoBlemish]
        keys += SkinRefinementKey.allCases.map(PortraitKey.skinRefinement)
        return Set(keys)
    }()
    public static let faceShape = Set(FaceShapeKey.allCases.map(PortraitKey.faceShape))
    public static let features = Set(FeatureKey.allCases.map(PortraitKey.feature))
    public static let makeup = Set(MakeupPart.allCases.map(PortraitKey.makeupPart))
    public static let all = skin.union(faceShape).union(features).union(makeup)
}

/// 성긴 층.
/// 있는 키만 아래 층을 덮어쓰고 없는 키는 상속한다.
/// 메이크업은 부위 단위다.
/// JSON은 전체 층과 같은 중첩(skin·face·features·makeup)이되 모든 잎이 선택이다.
public struct PortraitLayer: Codable, Equatable, Sendable {
    public var skinSmoothing: Double?
    public var autoBlemish: Bool?
    public var skinRefinement: [SkinRefinementKey: Double]
    public var face: [FaceShapeKey: Double]
    public var features: [FeatureKey: Double]
    /// 색 없는 부위는 colorID가 nil이다.
    public var makeup: [MakeupPart: MakeupTint]
    /// 이 층에서 마지막으로 적용한 룩.
    /// 부위를 바꾸면 지운다(전체 층과 같은 규칙).
    public var makeupLookID: String?
    /// 원터치 표시.
    /// 이 층의 묶인 항목이 OneTouchBundle 표 × 이 강도와 같다는 뜻이다.
    /// 렌더는 읽지 않고 키(overriddenKeys)도 아니다.
    public var oneTouch: Double?

    public init(
        skinSmoothing: Double? = nil, autoBlemish: Bool? = nil, skinRefinement: [SkinRefinementKey: Double] = [:],
        face: [FaceShapeKey: Double] = [:], features: [FeatureKey: Double] = [:],
        makeup: [MakeupPart: MakeupTint] = [:], makeupLookID: String? = nil, oneTouch: Double? = nil
    ) {
        self.skinSmoothing = skinSmoothing
        self.autoBlemish = autoBlemish
        self.skinRefinement = skinRefinement
        self.face = face
        self.features = features
        self.makeup = makeup
        self.makeupLookID = makeupLookID
        self.oneTouch = oneTouch
    }

    public var isEmpty: Bool { overriddenKeys.isEmpty && makeupLookID == nil && oneTouch == nil }

    /// 이 층이 덮어쓰는 키.
    /// 0으로 덮어쓴 키도 들어간다(상속을 끊음).
    public var overriddenKeys: Set<PortraitKey> {
        var keys = Set<PortraitKey>()
        if skinSmoothing != nil {
            keys.insert(.skinSmoothing)
        }
        if autoBlemish != nil {
            keys.insert(.autoBlemish)
        }
        keys.formUnion(skinRefinement.keys.map(PortraitKey.skinRefinement))
        keys.formUnion(face.keys.map(PortraitKey.faceShape))
        keys.formUnion(features.keys.map(PortraitKey.feature))
        keys.formUnion(makeup.keys.map(PortraitKey.makeupPart))
        return keys
    }

    /// 기본값과 다른 값이 하나라도 있는지.
    /// 0으로 덮어쓴 키는 렌더를 바꾸지 않는다.
    public var hasEffect: Bool {
        if let skinSmoothing, skinSmoothing != 0 {
            return true
        }
        if autoBlemish == true {
            return true
        }
        if skinRefinement.values.contains(where: { $0 != 0 }) {
            return true
        }
        if face.values.contains(where: { $0 != 0 }) {
            return true
        }
        if features.values.contains(where: { $0 != 0 }) {
            return true
        }
        return makeup.values.contains { $0.intensity != 0 }
    }

    /// 이 층의 모든 숫자(유한성 검사용).
    /// 원터치 표시도 넣는다.
    /// 타입 검사 시간을 줄이려 한 줄에 한 묶음씩 붙인다(Xcode 26.3이 긴 섞인 사슬을 포기함).
    public var numericValues: [Double] {
        let smoothing: Double = skinSmoothing ?? 0
        let marker: Double = oneTouch ?? 0
        var values: [Double] = [smoothing, marker]
        values += skinRefinement.values
        values += face.values
        values += features.values
        values += makeup.values.map(\.intensity)
        return values
    }

    /// 이 층의 키로 아래 층 값을 덮어쓴다.
    public func applied(to portrait: inout PortraitAdjustments, makeup target: inout MakeupAdjustments) {
        if let skinSmoothing {
            portrait.skin.smoothing = skinSmoothing
        }
        if let autoBlemish {
            portrait.skin.autoBlemish = autoBlemish
        }
        for (key, value) in skinRefinement {
            portrait.skin[key] = value
        }
        for (key, value) in face {
            portrait.face[key] = value
        }
        for (key, value) in features {
            portrait.features[key] = value
        }
        for (part, tint) in makeup {
            if part.hasColor {
                target.setColorID(tint.colorID, of: part)
            }
            target.setIntensity(tint.intensity, of: part)
        }
        // 룩 이름은 메이크업 부위를 덮어쓴 가장 위 층의 것이다.
        // 부위만 바꾼 층은 아래 층의 룩 이름을 지운다(겹친 값이 그 룩과 다르다).
        if makeupLookID != nil || !makeup.isEmpty {
            target.lookID = makeupLookID
        }
    }

    /// 키를 지워 상속으로 되돌린다.
    /// 메이크업 키가 모두 빠지면 룩 이름도 지운다.
    public mutating func remove(_ keys: Set<PortraitKey>) {
        for key in keys {
            switch key {
            case .skinSmoothing: skinSmoothing = nil
            case .autoBlemish: autoBlemish = nil
            case .skinRefinement(let refinement): skinRefinement[refinement] = nil
            case .faceShape(let shape): face[shape] = nil
            case .feature(let feature): features[feature] = nil
            case .makeupPart(let part): makeup[part] = nil
            }
        }
        if makeup.isEmpty {
            makeupLookID = nil
        }
    }

    /// 전체 층 값 중 기본값과 다른 것만 담은 층.
    /// 옛 targetFace 이행(H2)에 쓴다.
    public static func difference(portrait: PortraitAdjustments, makeup: MakeupAdjustments) -> PortraitLayer {
        var layer = PortraitLayer()
        if portrait.skin.smoothing != 0 {
            layer.skinSmoothing = portrait.skin.smoothing
        }
        if portrait.skin.autoBlemish {
            layer.autoBlemish = true
        }
        for key in SkinRefinementKey.allCases where portrait.skin[key] != 0 {
            layer.skinRefinement[key] = portrait.skin[key]
        }
        for key in FaceShapeKey.allCases where portrait.face[key] != 0 {
            layer.face[key] = portrait.face[key]
        }
        for key in FeatureKey.allCases where portrait.features[key] != 0 {
            layer.features[key] = portrait.features[key]
        }
        for part in MakeupPart.allCases {
            let colorID = part.hasColor ? makeup.colorID(of: part) : nil
            let tint = MakeupTint(colorID: colorID, intensity: makeup.intensity(of: part))
            if tint != MakeupTint() {
                layer.makeup[part] = tint
            }
        }
        layer.makeupLookID = layer.makeup.isEmpty ? nil : makeup.lookID
        return layer
    }

    // MARK: Codable

    // enum rawValue를 JSON 키로 쓴다.
    // Swift 기본 [Enum: T] 인코딩은 배열이라 쓰지 않는다.

    private enum CodingKeys: String, CodingKey {
        case oneTouch
        case skin
        case face
        case features
        case makeup
    }

    private struct RawKey: CodingKey {
        let stringValue: String
        var intValue: Int? { nil }

        init(stringValue: String) {
            self.stringValue = stringValue
        }

        init?(intValue: Int) {
            nil
        }

        init(_ raw: String) {
            stringValue = raw
        }
    }

    private static let smoothingKey = RawKey("smoothing")
    private static let autoBlemishKey = RawKey("autoBlemish")
    private static let lookIDKey = RawKey("lookID")

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        oneTouch = try container.decodeIfPresent(Double.self, forKey: .oneTouch)
        skinRefinement = [:]
        makeup = [:]
        if container.contains(.skin) {
            let skin = try container.nestedContainer(keyedBy: RawKey.self, forKey: .skin)
            skinSmoothing = try skin.decodeIfPresent(Double.self, forKey: Self.smoothingKey)
            autoBlemish = try skin.decodeIfPresent(Bool.self, forKey: Self.autoBlemishKey)
            for key in SkinRefinementKey.allCases {
                skinRefinement[key] = try skin.decodeIfPresent(Double.self, forKey: RawKey(key.rawValue))
            }
        }
        face = try Self.decodeNumbers(FaceShapeKey.self, in: container, forKey: .face)
        features = try Self.decodeNumbers(FeatureKey.self, in: container, forKey: .features)
        if container.contains(.makeup) {
            let parts = try container.nestedContainer(keyedBy: RawKey.self, forKey: .makeup)
            makeupLookID = try parts.decodeIfPresent(String.self, forKey: Self.lookIDKey)
            for part in MakeupPart.allCases {
                makeup[part] = try parts.decodeIfPresent(MakeupTint.self, forKey: RawKey(part.rawValue))
            }
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(oneTouch, forKey: .oneTouch)
        if skinSmoothing != nil || autoBlemish != nil || !skinRefinement.isEmpty {
            var skin = container.nestedContainer(keyedBy: RawKey.self, forKey: .skin)
            try skin.encodeIfPresent(skinSmoothing, forKey: Self.smoothingKey)
            try skin.encodeIfPresent(autoBlemish, forKey: Self.autoBlemishKey)
            for key in SkinRefinementKey.allCases {
                try skin.encodeIfPresent(skinRefinement[key], forKey: RawKey(key.rawValue))
            }
        }
        try Self.encodeNumbers(face, in: &container, forKey: .face)
        try Self.encodeNumbers(features, in: &container, forKey: .features)
        if makeupLookID != nil || !makeup.isEmpty {
            var parts = container.nestedContainer(keyedBy: RawKey.self, forKey: .makeup)
            try parts.encodeIfPresent(makeupLookID, forKey: Self.lookIDKey)
            for part in MakeupPart.allCases {
                try parts.encodeIfPresent(makeup[part], forKey: RawKey(part.rawValue))
            }
        }
    }

    private static func decodeNumbers<Key: RawRepresentable & CaseIterable & Hashable>(
        _: Key.Type, in container: KeyedDecodingContainer<CodingKeys>, forKey key: CodingKeys
    ) throws -> [Key: Double] where Key.RawValue == String {
        guard container.contains(key) else { return [:] }
        let nested = try container.nestedContainer(keyedBy: RawKey.self, forKey: key)
        var values: [Key: Double] = [:]
        for item in Key.allCases {
            values[item] = try nested.decodeIfPresent(Double.self, forKey: RawKey(item.rawValue))
        }
        return values
    }

    private static func encodeNumbers<Key: RawRepresentable & CaseIterable & Hashable>(
        _ values: [Key: Double], in container: inout KeyedEncodingContainer<CodingKeys>, forKey key: CodingKeys
    ) throws where Key.RawValue == String {
        guard !values.isEmpty else { return }
        var nested = container.nestedContainer(keyedBy: RawKey.self, forKey: key)
        for item in Key.allCases {
            try nested.encodeIfPresent(values[item], forKey: RawKey(item.rawValue))
        }
    }
}

/// 사진 안 한 사람.
/// anchor로 다시 찾고 layer가 그 사람만의 값이다.
/// gender는 수동 지정만 담는다(자동 추정은 분석 결과).
public struct PersonRecord: Codable, Equatable, Identifiable, Sendable {
    public var id: PersonID
    public var anchor: PersonAnchor?
    /// 옛 targetFace에서 온 기록만 가진다.
    /// anchor가 채워지면 지운다.
    public var legacyIndex: Int?
    public var gender: Gender?
    public var layer: PortraitLayer

    public init(
        id: PersonID = PersonID(), anchor: PersonAnchor? = nil, legacyIndex: Int? = nil, gender: Gender? = nil,
        layer: PortraitLayer = PortraitLayer()
    ) {
        self.id = id
        self.anchor = anchor
        self.legacyIndex = legacyIndex
        self.gender = gender
        self.layer = layer
    }

    /// 성별도 층도 없는 기록.
    /// 편집 규칙이 변경 뒤 지운다.
    public var isEmpty: Bool { gender == nil && layer.isEmpty }

    private enum CodingKeys: String, CodingKey {
        case id
        case anchor
        case legacyIndex
        case gender
        case layer
    }

    /// 관대하게 읽는다.
    /// layer가 없으면 빈 층이고 모르는 gender 문자열은 미지정이다.
    /// id·anchor·legacyIndex가 잘못되면 실패하고 PeopleAdjustments가 이 기록만 버린다.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(PersonID.self, forKey: .id)
        anchor = try container.decodeIfPresent(PersonAnchor.self, forKey: .anchor)
        legacyIndex = try container.decodeIfPresent(Int.self, forKey: .legacyIndex)
        gender = try? container.decodeIfPresent(Gender.self, forKey: .gender)
        layer = try container.decodeIfPresent(PortraitLayer.self, forKey: .layer) ?? PortraitLayer()
    }
}

/// 성별 그룹 층 둘과 개인 기록.
/// 전체 층은 EditRecipe.portrait·makeup이다.
public struct PeopleAdjustments: Codable, Equatable, Sendable {
    public var groups: [Gender: PortraitLayer]
    public var individuals: [PersonRecord]

    public init(groups: [Gender: PortraitLayer] = [:], individuals: [PersonRecord] = []) {
        self.groups = groups
        self.individuals = individuals
    }

    /// 어느 층이든 렌더를 바꾸는 값이 있는지.
    /// 성별 지정만 있는 기록은 false다.
    public var hasEffect: Bool {
        groups.values.contains(where: \.hasEffect) || individuals.contains { $0.layer.hasEffect }
    }

    /// 모든 층의 숫자(유한성 검사용).
    public var numericValues: [Double] {
        groups.values.flatMap(\.numericValues) + individuals.flatMap(\.layer.numericValues)
    }

    public func person(_ id: PersonID) -> PersonRecord? {
        individuals.first { $0.id == id }
    }

    /// 찾은 얼굴 인덱스 → 그 얼굴과 짝이 된 기록.
    /// PersonMatcher.match의 전역 1:1 결과다.
    /// 렌더(RenderContext.makeTargets)·편집·앱이 모두 이 함수로 얼굴의 사람을 정한다.
    /// 짝이 없는 얼굴은 키가 없다.
    public func peopleByFace(_ faces: [NormalizedRect]) -> [Int: PersonRecord] {
        var result: [Int: PersonRecord] = [:]
        for match in PersonMatcher.match(individuals, faces: faces) {
            result[match.faceIndex] = person(match.person)
        }
        return result
    }

    /// faces[index]와 짝이 된 기록의 id.
    /// anchor 하나에 가장 가까운 기록을 따로 찾으면 겹친 얼굴에서 렌더와 다른 사람을 고를 수 있어 늘 전역 짝짓기를 쓴다.
    public func personID(forFace index: Int, of faces: [NormalizedRect]) -> PersonID? {
        peopleByFace(faces)[index]?.id
    }

    /// 빈 기록과 빈 그룹 층을 지운다.
    /// 빈 그룹 층은 인코드에서 빠지므로 남겨 두면 저장 전후 ==와 isDefault가 어긋난다.
    /// 같은 id의 기록은 앞의 것만 남긴다(손상 파일에서 두 얼굴이 한 층을 나누지 않게).
    public mutating func prune() {
        individuals = Self.uniqued(individuals.filter { !$0.isEmpty })
        groups = groups.filter { !$0.value.isEmpty }
    }

    /// 같은 id가 다시 나오면 버린다.
    private static func uniqued(_ records: [PersonRecord]) -> [PersonRecord] {
        var seen = Set<PersonID>()
        return records.filter { seen.insert($0.id).inserted }
    }

    // MARK: Codable

    // groups는 Gender rawValue를 JSON 키로 쓴다.
    // 비어 있는 그룹 층과 빈 individuals는 쓰지 않는다.

    private enum CodingKeys: String, CodingKey {
        case groups
        case individuals
    }

    private struct GenderKey: CodingKey {
        let stringValue: String
        var intValue: Int? { nil }

        init(stringValue: String) {
            self.stringValue = stringValue
        }

        init?(intValue: Int) {
            nil
        }
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        groups = [:]
        if container.contains(.groups) {
            let nested = try container.nestedContainer(keyedBy: GenderKey.self, forKey: .groups)
            for gender in Gender.allCases {
                groups[gender] = try nested.decodeIfPresent(
                    PortraitLayer.self, forKey: GenderKey(stringValue: gender.rawValue))
            }
        }
        let lossy = try container.decodeIfPresent([LossyRecord].self, forKey: .individuals) ?? []
        // 같은 id가 둘 이상이면 앞의 것만 남긴다.
        individuals = Self.uniqued(lossy.compactMap(\.record))
    }

    /// 잘못된 기록 하나 때문에 세션 전체를 못 여는 일이 없게 그 기록만 버린다.
    private struct LossyRecord: Decodable {
        let record: PersonRecord?

        init(from decoder: Decoder) throws {
            record = try? PersonRecord(from: decoder)
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        let present = groups.filter { !$0.value.isEmpty }
        if !present.isEmpty {
            var nested = container.nestedContainer(keyedBy: GenderKey.self, forKey: .groups)
            for gender in Gender.allCases {
                try nested.encodeIfPresent(present[gender], forKey: GenderKey(stringValue: gender.rawValue))
            }
        }
        if !individuals.isEmpty {
            try container.encode(individuals, forKey: .individuals)
        }
    }
}
