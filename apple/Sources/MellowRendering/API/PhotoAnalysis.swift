import CoreImage
import MellowShared

/// 사진 준비 때 한 번 계산한 분석 결과 묶음. 렌더 단계는 RenderContext.analysis로 읽는다.
/// 새 분석 결과(E 관절점 등)는 여기 필드로만 더하고 RenderContext·PhotoPipeline의 인자 목록은 늘리지 않는다.
public struct PhotoAnalysis: Sendable {
    /// 왼쪽부터 정렬된 얼굴.
    public var faces: [FaceGeometry]
    /// 얼굴 분석이 실패했으면 그 이유. 얼굴이 없는 것과 구분한다.
    public var faceAnalysisFailure: MellowError?
    /// 자동 잡티. 얼굴이 있을 때만 찾는다. 영속화하지 않는다.
    public var blemishes: [BlemishSpot]
    /// 회색조 인물 마스크(사람 1·배경 0). PersonAnalyzer가 준 크기 그대로이고 렌더 단계가 extent로 키운다. 사람이 없으면 nil.
    public var personMask: CIImage?
    /// 인물 분석이 실패했으면 그 이유. 사람이 없는 것과 구분한다.
    public var personAnalysisFailure: MellowError?
    /// 관절점. 상자 넓이가 큰 사람이 앞이고 체형은 첫 사람만 바꾼다. 사람이 없으면 빈 배열.
    public var bodies: [BodyGeometry]
    /// 체형 분석이 실패했으면 그 이유. 사람이 없는 것과 구분한다.
    public var bodyAnalysisFailure: MellowError?
    /// 얼굴별 성별 추정.
    /// faces와 같은 길이이거나 빈 배열이다.
    /// 임계값을 통과한 추정만 들어 있다.
    /// 영속화하지 않는다.
    public var genderEstimates: [GenderEstimate?]
    /// 사람별 인스턴스 마스크(0…1).
    /// PersonInstanceAnalyzer가 준 크기 그대로이고 렌더 단계가 extent로 늘린다.
    /// 사람이 없거나 분석이 실패했으면 빈 배열이다.
    /// 영속화하지 않는다.
    public var personInstances: [CIImage]
    /// 몸 인덱스 → 얼굴 인덱스(BodyFaceMatcher).
    /// 짝이 없는 몸은 키가 없다.
    public var bodyFaceMatches: [Int: Int]
    /// 몸 인덱스 → personInstances 인덱스(InstanceAssignment).
    /// 인스턴스를 고르지 못한 몸은 키가 없다.
    public var bodyInstances: [Int: Int]
    /// 얼굴 인덱스 → personInstances 인덱스.
    /// 인스턴스를 고르지 못한 얼굴은 키가 없다.
    public var faceInstances: [Int: Int]
    /// 다각형 마스크 비트맵 캐시. 묶음을 복사해도 같은 캐시를 나눠 쓴다. 키에 다각형 점이 들어 있어 얼굴이 바뀌어도 낡은 값을 쓰지 않는다.
    /// 상한은 준비 때 찾은 얼굴 수에 비례한다(RegionMaskCache.capacity(forFaces:)).
    let regionMasks: RegionMaskCache

    public init(
        faces: [FaceGeometry] = [], faceAnalysisFailure: MellowError? = nil, blemishes: [BlemishSpot] = [],
        personMask: CIImage? = nil, personAnalysisFailure: MellowError? = nil, bodies: [BodyGeometry] = [],
        bodyAnalysisFailure: MellowError? = nil, genderEstimates: [GenderEstimate?] = [],
        personInstances: [CIImage] = [], bodyFaceMatches: [Int: Int] = [:], bodyInstances: [Int: Int] = [:],
        faceInstances: [Int: Int] = [:]
    ) {
        self.faces = faces
        self.faceAnalysisFailure = faceAnalysisFailure
        self.blemishes = blemishes
        self.personMask = personMask
        self.personAnalysisFailure = personAnalysisFailure
        self.bodies = bodies
        self.bodyAnalysisFailure = bodyAnalysisFailure
        self.genderEstimates = genderEstimates
        self.personInstances = personInstances
        self.bodyFaceMatches = bodyFaceMatches
        self.bodyInstances = bodyInstances
        self.faceInstances = faceInstances
        regionMasks = RegionMaskCache(maximumEntries: RegionMaskCache.capacity(forFaces: faces.count))
    }
}
