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
    /// 이 얼굴의 자동 잡티.
    public let blemishes: [BlemishSpot]

    public init(
        index: Int, face: FaceGeometry, personID: PersonID?, gender: Gender?, portrait: PortraitAdjustments,
        makeup: MakeupAdjustments, blemishes: [BlemishSpot]
    ) {
        self.index = index
        self.face = face
        self.personID = personID
        self.gender = gender
        self.portrait = portrait
        self.makeup = makeup
        self.blemishes = blemishes
    }
}

public struct RenderContext: Sendable {
    public let extent: CGRect
    public let recipe: EditRecipe
    /// 사진 준비 때 계산한 분석 결과. 단계는 faces·blemishes 같은 접근자로 읽는다.
    public let analysis: PhotoAnalysis
    /// 얼굴마다 해석한 값.
    /// 짝이 없는 사람 기록은 어느 얼굴에도 들어가지 않는다.
    public let faceTargets: [FaceTarget]
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
        faceTargets = Self.makeTargets(recipe: recipe, analysis: analysis)
    }

    /// 사람 기록을 얼굴에 짝짓고 얼굴마다 층을 겹친다.
    /// 짝짓기는 편집 쪽과 같은 PersonMatcher.match다.
    /// 성별은 기록의 수동 지정이 먼저이고 준비 때 받아들인 추정이 그다음이다.
    /// H2 Task 5 전까지 옛 targetFace는 전체 층을 그 얼굴에만 건다(범위 밖이면 대상 없음).
    static func makeTargets(recipe: EditRecipe, analysis: PhotoAnalysis) -> [FaceTarget] {
        let faces = analysis.faces
        let matches = PersonMatcher.match(recipe.people.individuals, faces: faces.map(\.boundingBox))
        var personByFace: [Int: PersonRecord] = [:]
        for match in matches {
            personByFace[match.faceIndex] = recipe.people.person(match.person)
        }
        return faces.indices.compactMap { index in
            if let legacy = recipe.portrait.targetFace, legacy != index {
                return nil
            }
            let person = personByFace[index]
            let estimate = analysis.genderEstimates.indices.contains(index) ? analysis.genderEstimates[index] : nil
            let gender = PortraitResolver.effectiveGender(person: person, estimate: estimate?.gender)
            let resolved = PortraitResolver.resolve(recipe, person: person, gender: gender)
            return FaceTarget(
                index: index, face: faces[index], personID: person?.id, gender: gender, portrait: resolved.portrait,
                makeup: resolved.makeup, blemishes: analysis.blemishes.filter { $0.faceIndex == index })
        }
    }

    /// faceTargets의 얼굴.
    /// H2 Task 5에서 지운다.
    public var targetFaces: [FaceGeometry] { faceTargets.map(\.face) }
    /// faceTargets의 잡티.
    /// H2 Task 5에서 지운다.
    public var targetBlemishes: [BlemishSpot] { faceTargets.flatMap(\.blemishes) }

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
