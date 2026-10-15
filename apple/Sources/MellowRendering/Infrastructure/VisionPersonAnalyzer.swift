import CoreImage
import MellowShared
import Vision

/// VNGeneratePersonSegmentationRequest로 인물 마스크를 만든다. 결과는 입력 비율과 무관한 고정 크기(기본 품질 512×384)다.
public struct VisionPersonAnalyzer: PersonAnalyzer {
    /// Vision이 결과를 주지 않았을 때의 사유 식별자. 사용자 문구는 앱이 정한다.
    public static let missingResultReason = "no-segmentation-result"
    /// 이 값(0…255) 이상인 마스크 픽셀을 사람으로 센다. 경계 중간값이다.
    private static let personByteThreshold: UInt8 = 128
    /// 사람 픽셀이 마스크의 이 비율보다 적으면 사람이 없다고 본다. 빈 장면은 0%, 작게 찍힌 전신 인물도 1%는 넘는다.
    private static let minimumCoverage = 0.01

    public init() {}

    public func personMask(_ image: CIImage) throws -> CIImage? {
        let request = VNGeneratePersonSegmentationRequest()
        request.qualityLevel = .balanced
        request.outputPixelFormat = kCVPixelFormatType_OneComponent8
        do {
            try VNImageRequestHandler(ciImage: image, options: [:]).perform([request])
        } catch {
            throw MellowError.personAnalysisUnavailable(reason: error.localizedDescription)
        }
        guard let buffer = request.results?.first?.pixelBuffer else {
            throw MellowError.personAnalysisUnavailable(reason: Self.missingResultReason)
        }
        guard Self.coverage(of: buffer) >= Self.minimumCoverage else { return nil }
        // 0…255를 색 관리 없이 0…1로 읽는다. 색공간을 붙이면 선형으로 바뀌어 경계 중간값이 달라진다.
        return CIImage(cvPixelBuffer: buffer, options: [.colorSpace: NSNull()])
    }

    /// 사람 픽셀(personByteThreshold 이상)의 비율.
    static func coverage(of buffer: CVPixelBuffer) -> Double {
        CVPixelBufferLockBaseAddress(buffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
        let width = CVPixelBufferGetWidth(buffer)
        let height = CVPixelBufferGetHeight(buffer)
        let rowBytes = CVPixelBufferGetBytesPerRow(buffer)
        guard width > 0, height > 0, let base = CVPixelBufferGetBaseAddress(buffer) else { return 0 }
        let bytes = base.assumingMemoryBound(to: UInt8.self)
        var covered = 0
        for row in 0..<height {
            for column in 0..<width where bytes[row * rowBytes + column] >= personByteThreshold {
                covered += 1
            }
        }
        return Double(covered) / Double(width * height)
    }
}
