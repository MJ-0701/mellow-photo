import CoreImage
import Foundation
import ImageIO
import MellowShared

public struct ImageMetadata: Sendable {
    /// 방향 보정 후 픽셀 크기.
    public let pixelSize: CGSize
}

public struct ImageLoader: Sendable {
    public init() {}

    /// maxDimension이 있으면 방향이 적용된 축소본, 없으면 방향을 보정한 원본.
    public func load(url: URL, maxDimension: Int? = nil) throws -> CIImage {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else {
            throw MellowError.cannotOpenPhoto(filename: url.lastPathComponent)
        }
        let image: CIImage
        if let maxDimension {
            let options: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: maxDimension,
                kCGImageSourceShouldCacheImmediately: true,
            ]
            guard maxDimension > 0, let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
            else {
                throw MellowError.cannotCreatePreview
            }
            image = CIImage(cgImage: cg)
        } else {
            let options: [CFString: Any] = [kCGImageSourceShouldCacheImmediately: true]
            guard let cg = CGImageSourceCreateImageAtIndex(source, 0, options as CFDictionary) else {
                throw MellowError.unsupportedOrCorruptPhoto
            }
            let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
            let orientation = (properties?[kCGImagePropertyOrientation] as? NSNumber)?.int32Value ?? 1
            image = CIImage(cgImage: cg).oriented(forExifOrientation: orientation)
        }
        return image.transformed(by: CGAffineTransform(translationX: -image.extent.minX, y: -image.extent.minY))
    }

    public func metadata(url: URL) throws -> ImageMetadata {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else {
            throw MellowError.cannotOpenPhoto(filename: url.lastPathComponent)
        }
        guard let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
            let width = properties[kCGImagePropertyPixelWidth] as? Int,
            let height = properties[kCGImagePropertyPixelHeight] as? Int
        else {
            throw MellowError.unsupportedOrCorruptPhoto
        }
        let orientation = (properties[kCGImagePropertyOrientation] as? Int) ?? 1
        let rotated = orientation >= 5
        return ImageMetadata(pixelSize: CGSize(width: rotated ? height : width, height: rotated ? width : height))
    }
}
