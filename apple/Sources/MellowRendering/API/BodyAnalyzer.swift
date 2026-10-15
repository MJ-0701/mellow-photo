import CoreImage
import MellowShared

/// 관절점 포트. 기본 구현은 Infrastructure의 VisionBodyAnalyzer다.
public protocol BodyAnalyzer: Sendable {
    /// 찾은 사람들의 관절점. 관절 상자 넓이가 큰 사람이 앞이다. 사람이 없으면 빈 배열.
    /// 분석 자체가 불가능하면 MellowError.bodyAnalysisUnavailable.
    func analyze(_ image: CIImage) throws -> [BodyGeometry]
}
