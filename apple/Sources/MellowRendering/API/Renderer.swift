import CoreImage
import MellowShared

/// CIContext 소유자. 출력은 8bit sRGB.
public final class Renderer: @unchecked Sendable {
    private let context: CIContext
    private let outputColorSpace = CGColorSpace(name: CGColorSpace.sRGB)!

    public init() {
        context = CIContext(options: [
            .workingColorSpace: CGColorSpace(name: CGColorSpace.extendedLinearSRGB)!,
            .outputColorSpace: CGColorSpace(name: CGColorSpace.sRGB)!,
        ])
    }

    public func makeCGImage(_ image: CIImage) throws -> CGImage {
        guard let cg = context.createCGImage(image, from: image.extent, format: .RGBA8, colorSpace: outputColorSpace)
        else {
            throw MellowError.renderFailed
        }
        return cg
    }

    /// RGBAf로 읽는다. 행 우선, 맨 위 행부터(Core Image 좌표의 가장 큰 y가 첫 행). 히스토그램·평균·잡티 분석처럼 긴 변 512px 이하 이미지에만 쓴다.
    public func readPixels(_ image: CIImage) throws -> [Float] {
        guard !image.extent.isInfinite else { throw MellowError.renderFailed }
        let width = Int(image.extent.width.rounded())
        let height = Int(image.extent.height.rounded())
        guard width > 0, height > 0 else { throw MellowError.renderFailed }
        var pixels = [Float](repeating: 0, count: width * height * 4)
        let rowBytes = width * 4 * MemoryLayout<Float>.size
        let colorSpace = CGColorSpace(name: CGColorSpace.linearSRGB)
        pixels.withUnsafeMutableBytes { buffer in
            context.render(
                image, toBitmap: buffer.baseAddress!, rowBytes: rowBytes, bounds: image.extent, format: .RGBAf,
                colorSpace: colorSpace)
        }
        return pixels
    }

    /// 회색 마스크를 색 관리 없이 8비트 한 채널(빨강)로 읽는다.
    /// 행 우선, 맨 위 행부터다.
    /// 분석기 원래 해상도 마스크를 사진 준비 때 한 번 읽는 데 쓴다(MaskSampler).
    func readMaskBytes(_ image: CIImage) throws -> (bytes: [UInt8], width: Int, height: Int) {
        guard !image.extent.isInfinite else { throw MellowError.renderFailed }
        let bounds = image.extent.integral
        let width = Int(bounds.width)
        let height = Int(bounds.height)
        guard width > 0, height > 0 else { throw MellowError.renderFailed }
        var bytes = [UInt8](repeating: 0, count: width * height)
        bytes.withUnsafeMutableBytes { buffer in
            context.render(
                image, toBitmap: buffer.baseAddress!, rowBytes: width, bounds: bounds, format: .R8, colorSpace: nil)
        }
        return (bytes, width, height)
    }
}
