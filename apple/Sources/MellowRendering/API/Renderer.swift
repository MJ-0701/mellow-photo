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

    /// RGBAf로 읽는다. 행 우선, 왼쪽 아래 픽셀부터. 히스토그램·평균처럼 작은 이미지에만 쓴다.
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
}
