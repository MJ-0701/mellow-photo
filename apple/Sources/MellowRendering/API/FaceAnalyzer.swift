import CoreImage
import MellowShared

public protocol FaceAnalyzer: Sendable {
    /// 왼쪽부터 정렬된 얼굴. 분석 자체가 불가능하면 MellowError.faceAnalysisUnavailable.
    func analyze(_ image: CIImage) throws -> [FaceGeometry]
}
