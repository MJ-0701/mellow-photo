import CoreImage
import MellowShared

/// 렌더할 얼굴 하나와 그 얼굴에 해석한 값(전체 → 성별 그룹 → 개인).
/// 네 얼굴 단계(피부·특징·메이크업·얼굴형)가 이 목록을 돈다.
public struct FaceTarget: Sendable {
    /// analysis.faces 안 인덱스.
    public let index: Int
    public let face: FaceGeometry
    /// 짝이 된 사람 기록.
    /// 없으면 nil이다.
    public let personID: PersonID?
    /// 유효 성별(수동 지정 ?? 추정).
    /// 없으면 그룹 층을 받지 않는다.
    public let gender: Gender?
    public let portrait: PortraitAdjustments
    public let makeup: MakeupAdjustments
    /// 이 얼굴의 사람에게 해석한 체형.
    /// 짝이 된 몸(BodyTarget)이 이 값을 쓴다.
    public let body: BodyShapeAdjustments
    /// 이 얼굴의 자동 잡티.
    public let blemishes: [BlemishSpot]

    public init(
        index: Int, face: FaceGeometry, personID: PersonID?, gender: Gender?, portrait: PortraitAdjustments,
        makeup: MakeupAdjustments, body: BodyShapeAdjustments = BodyShapeAdjustments(), blemishes: [BlemishSpot]
    ) {
        self.index = index
        self.face = face
        self.personID = personID
        self.gender = gender
        self.portrait = portrait
        self.makeup = makeup
        self.body = body
        self.blemishes = blemishes
    }
}

/// 체형을 바꿀 몸 하나와 그 몸에 해석한 체형.
/// 모든 몸이 대상이다.
public struct BodyTarget: Sendable {
    /// analysis.bodies 안 인덱스.
    /// 0이 가장 큰 사람이다.
    public let index: Int
    public let body: BodyGeometry
    /// 짝이 된 얼굴의 analysis.faces 안 인덱스.
    /// 없으면 nil이다.
    public let faceIndex: Int?
    /// 짝 얼굴이 있으면 그 FaceTarget.body, 없으면 PortraitResolver.allLayerBody다.
    public let adjustments: BodyShapeAdjustments
}

public struct RenderContext: Sendable {
    public let extent: CGRect
    public let recipe: EditRecipe
    /// 사진 준비 때 계산한 분석 결과. 단계는 faces·blemishes 같은 접근자로 읽는다.
    public let analysis: PhotoAnalysis
    /// 얼굴마다 해석한 값.
    /// 짝이 없는 사람 기록은 어느 얼굴에도 들어가지 않는다.
    public let faceTargets: [FaceTarget]
    /// 몸마다 해석한 체형(analysis.bodies 순서).
    /// 다른 사람의 개인 값은 어느 몸에도 붙지 않는다.
    public let bodyTargets: [BodyTarget]
    public let tuning: RenderTuning
    public let lookCatalog: LookCatalog
    /// 메이크업 팔레트. 비어 있으면 색을 고르는 부위(립·블러셔·아이섀도)만 빠진다.
    public let makeupCatalog: MakeupCatalog
    /// 자르기 도구 화면용. 기하 단계가 자르기만 건너뛴다.
    public let skipsCrop: Bool

    public init(
        extent: CGRect, recipe: EditRecipe, analysis: PhotoAnalysis, tuning: RenderTuning,
        lookCatalog: LookCatalog = .empty, makeupCatalog: MakeupCatalog = .empty, skipsCrop: Bool = false
    ) {
        self.extent = extent
        self.recipe = recipe
        self.analysis = analysis
        self.tuning = tuning
        self.lookCatalog = lookCatalog
        self.makeupCatalog = makeupCatalog
        self.skipsCrop = skipsCrop
        let faceTargets = Self.makeTargets(recipe: recipe, analysis: analysis)
        self.faceTargets = faceTargets
        bodyTargets = Self.makeBodyTargets(recipe: recipe, analysis: analysis, faceTargets: faceTargets)
    }

    /// 사람 기록을 얼굴에 짝짓고 얼굴마다 층을 겹친다.
    /// 짝짓기는 편집·앱과 같은 PeopleAdjustments.peopleByFace(전역 PersonMatcher.match)다.
    /// 성별은 기록의 수동 지정이 먼저이고 준비 때 받아들인 추정이 그다음이다.
    static func makeTargets(recipe: EditRecipe, analysis: PhotoAnalysis) -> [FaceTarget] {
        let faces = analysis.faces
        let personByFace = recipe.people.peopleByFace(faces.map(\.boundingBox))
        return faces.indices.map { index in
            let person = personByFace[index]
            let estimate = analysis.genderEstimates.indices.contains(index) ? analysis.genderEstimates[index] : nil
            let gender = PortraitResolver.effectiveGender(person: person, estimate: estimate?.gender)
            let resolved = PortraitResolver.resolve(recipe, person: person, gender: gender)
            return FaceTarget(
                index: index, face: faces[index], personID: person?.id, gender: gender, portrait: resolved.portrait,
                makeup: resolved.makeup, body: resolved.body,
                blemishes: analysis.blemishes.filter { $0.faceIndex == index })
        }
    }

    /// 몸마다 짝 얼굴의 체형, 짝이 없으면 전체 층 체형(부유방 0)을 건다.
    /// 짝은 준비 때 정한 analysis.bodyFaceMatches다.
    static func makeBodyTargets(recipe: EditRecipe, analysis: PhotoAnalysis, faceTargets: [FaceTarget])
        -> [BodyTarget]
    {
        let unmatched = PortraitResolver.allLayerBody(recipe)
        return analysis.bodies.indices.map { index in
            let faceIndex = analysis.bodyFaceMatches[index].flatMap { faceTargets.indices.contains($0) ? $0 : nil }
            let adjustments = faceIndex.map { faceTargets[$0].body } ?? unmatched
            return BodyTarget(
                index: index, body: analysis.bodies[index], faceIndex: faceIndex, adjustments: adjustments)
        }
    }

    /// 얼굴·잡티만 있는 분석으로 만든다. 단계 테스트가 쓰는 형태다.
    /// 새 분석 결과는 이 인자 목록에 더하지 않고 PhotoAnalysis에만 더한다.
    public init(
        extent: CGRect, recipe: EditRecipe, faces: [FaceGeometry], tuning: RenderTuning,
        lookCatalog: LookCatalog = .empty, makeupCatalog: MakeupCatalog = .empty, skipsCrop: Bool = false,
        blemishes: [BlemishSpot] = []
    ) {
        self.init(
            extent: extent, recipe: recipe, analysis: PhotoAnalysis(faces: faces, blemishes: blemishes),
            tuning: tuning, lookCatalog: lookCatalog, makeupCatalog: makeupCatalog, skipsCrop: skipsCrop)
    }

    /// 왼쪽부터 정렬된 얼굴.
    public var faces: [FaceGeometry] { analysis.faces }
    /// 사진 준비 때 찾은 자동 잡티. 영속화하지 않는다.
    public var blemishes: [BlemishSpot] { analysis.blemishes }
    /// 사진 준비 때 만든 인물 마스크. 사람이 없거나 분석이 실패했으면 nil이고 배경 단계가 건너뛴다.
    public var personMask: CIImage? { analysis.personMask }
    /// 사진 준비 때 찾은 관절점. 상자 넓이가 큰 사람이 앞이다. 없거나 분석이 실패했으면 비어 있고 체형 원소가 빠진다.
    public var bodies: [BodyGeometry] { analysis.bodies }

    /// 그 몸의 사람 마스크와 다른 사람들의 마스크.
    /// 인스턴스가 있으면 own은 그 인스턴스, others는 나머지 인스턴스다.
    /// 없으면 own은 전체 인물 마스크(그것도 없으면 nil), others는 빈 배열이다.
    /// 둘 다 분석기가 준 해상도 그대로이고 extent 배치는 쓰는 쪽이 한다.
    public func personMask(forBody index: Int) -> (own: CIImage?, others: [CIImage]) {
        instanceMasks(owner: analysis.bodyInstances[index])
    }

    /// 그 얼굴의 사람 마스크와 다른 사람들의 마스크.
    /// 규칙은 personMask(forBody:)와 같다.
    public func personMask(forFace index: Int) -> (own: CIImage?, others: [CIImage]) {
        instanceMasks(owner: analysis.faceInstances[index])
    }

    private func instanceMasks(owner: Int?) -> (own: CIImage?, others: [CIImage]) {
        let instances = analysis.personInstances
        guard let owner, instances.indices.contains(owner) else { return (personMask, []) }
        var others = instances
        others.remove(at: owner)
        return (instances[owner], others)
    }

    /// 같은 사진의 다각형 마스크 비트맵 캐시.
    var regionMasks: RegionMaskCache { analysis.regionMasks }

    /// 정규화 사각형을 픽셀 좌표로.
    public func pixelRect(_ rect: NormalizedRect) -> CGRect {
        CGRect(
            x: extent.minX + rect.x * extent.width,
            y: extent.minY + rect.y * extent.height,
            width: rect.width * extent.width,
            height: rect.height * extent.height)
    }

    public func pixelPoint(x: Double, y: Double) -> CGPoint {
        CGPoint(x: extent.minX + x * extent.width, y: extent.minY + y * extent.height)
    }

    public var shortSide: CGFloat { min(extent.width, extent.height) }
}

public protocol RenderStage: Sendable {
    var name: String { get }
    func apply(_ image: CIImage, in context: RenderContext) throws -> CIImage
}
