import CoreImage
import MellowShared

/// 사람별 인스턴스 마스크 포트.
/// 기본 구현은 Infrastructure의 VisionPersonInstanceAnalyzer다.
public protocol PersonInstanceAnalyzer: Sendable {
    /// 사람마다 0…1 회색 마스크(그 사람 1·나머지 0).
    /// Vision 원래 해상도이고 extent 원점은 (0, 0)이다.
    /// 쓰는 쪽이 BackgroundStage.personMask와 같은 배치로 extent에 늘린다.
    /// 사람이 없으면 빈 배열이다.
    func instanceMasks(_ image: CIImage) throws -> [CIImage]
}
