import CoreImage
import Darwin
import Foundation
import ImageIO
import MellowRendering
import MellowShared

/// 임시 파일에 쓰고 재해독으로 검증한 뒤 배타적 rename으로 공개한다.
public struct Exporter: Sendable {
    private let renderer: Renderer

    public init(renderer: Renderer) {
        self.renderer = renderer
    }

    public func write(_ image: CIImage, to url: URL, format: ExportFormat, quality: Double) throws {
        let cg = try renderer.makeCGImage(image)
        let temporary = url.deletingLastPathComponent().appendingPathComponent(".mellow-\(UUID().uuidString).tmp")
        defer { try? FileManager.default.removeItem(at: temporary) }
        guard
            let destination = CGImageDestinationCreateWithURL(
                temporary as CFURL, format.typeIdentifier as CFString, 1, nil)
        else {
            throw MellowError.cannotWriteToFolder
        }
        let properties: [CFString: Any] = [
            kCGImageDestinationLossyCompressionQuality: max(0, min(1, quality)),
            kCGImagePropertyOrientation: 1,
        ]
        CGImageDestinationAddImage(destination, cg, properties as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw MellowError.exportVerificationFailed }
        try verify(temporary, width: cg.width, height: cg.height)
        try publishExclusively(temporary, to: url)
    }

    private func verify(_ url: URL, width: Int, height: Int) throws {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
            let decoded = CGImageSourceCreateImageAtIndex(source, 0, nil),
            decoded.width == width, decoded.height == height
        else {
            throw MellowError.exportVerificationFailed
        }
    }

    /// 같은 폴더 안의 배타적 rename은 하드링크 없는 exFAT에서도 원자적이다.
    private func publishExclusively(_ source: URL, to destination: URL) throws {
        let status = source.withUnsafeFileSystemRepresentation { from in
            destination.withUnsafeFileSystemRepresentation { to in
                renameatx_np(AT_FDCWD, from!, AT_FDCWD, to!, UInt32(RENAME_EXCL))
            }
        }
        guard status == 0 else {
            if errno == EEXIST { throw MellowError.fileAlreadyExists }
            throw MellowError.exportFailed(reason: String(cString: strerror(errno)))
        }
    }
}
