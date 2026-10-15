import CoreImage
import MellowShared

/// 인물 영역 포트. 기본 구현은 Infrastructure의 VisionPersonAnalyzer다.
public protocol PersonAnalyzer: Sendable {
    /// 입력 이미지 전체를 덮는 회색조 마스크(사람 1·배경 0). extent 원점은 (0, 0)이고 가로세로 비율은 입력과 다를 수 있다.
    /// 사람이 없으면 nil. 분석 자체가 불가능하면 MellowError.personAnalysisUnavailable.
    func personMask(_ image: CIImage) throws -> CIImage?
}
