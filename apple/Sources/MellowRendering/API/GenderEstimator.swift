import CoreImage
import MellowShared

/// 얼굴 하나의 성별 추정.
/// 저장하지 않는다.
/// 사용자의 수동 지정이 늘 우선한다.
public struct GenderEstimate: Equatable, Sendable {
    public var gender: Gender
    /// 0…1.
    public var confidence: Double

    public init(gender: Gender, confidence: Double) {
        self.gender = gender
        self.confidence = confidence
    }
}

/// 성별 추정 포트.
/// faces와 같은 순서·길이로 돌려주고 추정하지 못한 얼굴은 nil이다.
/// 기본 구현은 H4(Core ML)가 더한다.
/// 실패는 던져도 되며 PhotoPipeline이 조용히 미지정으로 바꾼다.
public protocol GenderEstimator: Sendable {
    func estimate(_ image: CIImage, faces: [FaceGeometry]) throws -> [GenderEstimate?]
}
