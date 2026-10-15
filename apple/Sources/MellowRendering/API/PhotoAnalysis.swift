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
    /// 다각형 마스크 비트맵 캐시. 묶음을 복사해도 같은 캐시를 나눠 쓴다. 키에 다각형 점이 들어 있어 얼굴이 바뀌어도 낡은 값을 쓰지 않는다.
    let regionMasks = RegionMaskCache()

    public init(faces: [FaceGeometry] = [], faceAnalysisFailure: MellowError? = nil, blemishes: [BlemishSpot] = []) {
        self.faces = faces
        self.faceAnalysisFailure = faceAnalysisFailure
        self.blemishes = blemishes
    }
}
