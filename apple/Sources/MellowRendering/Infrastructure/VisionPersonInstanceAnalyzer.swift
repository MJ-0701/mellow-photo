import CoreImage
import Foundation
import MellowShared
import Vision

/// VNGeneratePersonInstanceMaskRequest로 사람마다 마스크를 만든다.
/// 결과는 Vision이 준 저해상도 그대로이고 입력 비율과 다를 수 있다.
public struct VisionPersonInstanceAnalyzer: PersonInstanceAnalyzer {
    /// 인스턴스 번호 지도에서 배경(번호 0) 픽셀이 이 비율보다 적으면 사람이 없다고 본다.
    /// Vision은 단색 장면을 화면 전체가 한 사람인 인스턴스로 돌려준다(배경 0%).
    /// 실제 인물 사진은 화면을 꽉 채운 얼굴도 배경이 몇 %는 있다.
    /// 버려도 렌더는 전체 인물 마스크로 대신하므로 결과가 크게 다르지 않다.
    private static let minimumBackgroundCoverage = 0.01
    /// 인스턴스 번호 지도에서 배경의 번호.
    private static let backgroundLabel: UInt8 = 0

    public init() {}

    public func instanceMasks(_ image: CIImage) throws -> [CIImage] {
        let request = VNGeneratePersonInstanceMaskRequest()
        let handler = VNImageRequestHandler(ciImage: image, options: [:])
        do {
            try handler.perform([request])
        } catch {
            throw MellowError.personAnalysisUnavailable(reason: error.localizedDescription)
        }
        // 결과가 없으면 사람이 없는 것이다.
        guard let observation = request.results?.first else { return [] }
        guard Self.backgroundCoverage(of: observation.instanceMask) >= Self.minimumBackgroundCoverage else {
            return []
        }
        // allInstances는 배경(0)을 빼고 사람 번호만 담는다.
        return try observation.allInstances.map { instance in
            do {
                let buffer = try observation.generateMask(forInstances: IndexSet(integer: instance))
                // 0…1을 색 관리 없이 읽는다. 색공간을 붙이면 선형으로 바뀌어 경계 중간값이 달라진다.
                return CIImage(cvPixelBuffer: buffer, options: [.colorSpace: NSNull()])
            } catch {
                throw MellowError.personAnalysisUnavailable(reason: error.localizedDescription)
            }
        }
    }

    /// 인스턴스 번호 지도(한 바이트 번호)에서 배경 픽셀의 비율.
    /// 한 바이트 형식이 아니면 배경이 있다고 보고 1을 돌려준다(결과를 버리지 않는다).
    static func backgroundCoverage(of labels: CVPixelBuffer) -> Double {
        guard CVPixelBufferGetPixelFormatType(labels) == kCVPixelFormatType_OneComponent8 else { return 1 }
        CVPixelBufferLockBaseAddress(labels, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(labels, .readOnly) }
        let width = CVPixelBufferGetWidth(labels)
        let height = CVPixelBufferGetHeight(labels)
        let rowBytes = CVPixelBufferGetBytesPerRow(labels)
        guard width > 0, height > 0, let base = CVPixelBufferGetBaseAddress(labels) else { return 1 }
        let bytes = base.assumingMemoryBound(to: UInt8.self)
        var background = 0
        for row in 0..<height {
            for column in 0..<width where bytes[row * rowBytes + column] == backgroundLabel {
                background += 1
            }
        }
        return Double(background) / Double(width * height)
    }
}
