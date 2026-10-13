import Foundation
import CoreImage
import CoreGraphics
import ImageIO
import Vision
import UniformTypeIdentifiers
import Darwin

public enum ExportFormat: String, CaseIterable, Sendable {
    case jpeg, png
    public var fileExtension: String { self == .jpeg ? "jpg" : "png" }
}
public enum ImageEngineError: LocalizedError {
    case message(String)
    public var errorDescription: String? { if case let .message(value) = self { return value }; return nil }
}

public final class ImageEngine: @unchecked Sendable {
    private let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
    private let context: CIContext
    public init() {
        context = CIContext(options: [.workingColorSpace: CGColorSpace(name: CGColorSpace.extendedLinearSRGB)!, .outputColorSpace: CGColorSpace(name: CGColorSpace.sRGB)!])
    }
    public func load(url: URL, maxDimension: Int? = nil) throws -> CIImage {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { throw ImageEngineError.message("사진 파일을 열 수 없습니다: \(url.lastPathComponent)") }
        let image: CIImage
        if let maxDimension {
            guard maxDimension > 0, let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceCreateThumbnailWithTransform: true, kCGImageSourceThumbnailMaxPixelSize: maxDimension, kCGImageSourceShouldCacheImmediately: true] as CFDictionary) else { throw ImageEngineError.message("사진 미리보기를 만들 수 없습니다.") }
            image = CIImage(cgImage: cg)
        } else {
            guard let cg = CGImageSourceCreateImageAtIndex(source, 0, [kCGImageSourceShouldCacheImmediately: true] as CFDictionary) else { throw ImageEngineError.message("지원하지 않거나 손상된 사진입니다.") }
            let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
            let orientation = (props?[kCGImagePropertyOrientation] as? NSNumber)?.int32Value ?? 1
            image = CIImage(cgImage: cg).oriented(forExifOrientation: orientation)
        }
        return image.transformed(by: CGAffineTransform(translationX: -image.extent.minX, y: -image.extent.minY))
    }
    public func detectFaces(in image: CIImage) throws -> [FaceRegion] {
        let request = VNDetectFaceLandmarksRequest()
        #if targetEnvironment(simulator)
        // Simulator inference cannot use every device backend available on a physical iPhone.
        request.usesCPUOnly = true
        #endif
        try VNImageRequestHandler(ciImage: image, options: [:]).perform([request])
        return (request.results ?? []).map { face in
            func bounds(_ region: VNFaceLandmarkRegion2D?) -> CGRect? {
                guard let region, region.pointCount > 0 else { return nil }
                let points = region.normalizedPoints
                let xs = points.map { CGFloat($0.x) }, ys = points.map { CGFloat($0.y) }
                return CGRect(x: face.boundingBox.minX + xs.min()! * face.boundingBox.width, y: face.boundingBox.minY + ys.min()! * face.boundingBox.height, width: (xs.max()! - xs.min()!) * face.boundingBox.width, height: (ys.max()! - ys.min()!) * face.boundingBox.height)
            }
            return FaceRegion(rect: face.boundingBox, leftEye: bounds(face.landmarks?.leftEye), rightEye: bounds(face.landmarks?.rightEye), mouth: bounds(face.landmarks?.outerLips))
        }.sorted { $0.rect.minX < $1.rect.minX }
    }
    private func ellipse(_ rect: CGRect, extent: CGRect, strength: Double = 1) -> CIImage {
        let circle = CIFilter(name: "CIRadialGradient", parameters: ["inputCenter": CIVector(x: 0, y: 0), "inputRadius0": 0.65, "inputRadius1": 1.0, "inputColor0": CIColor(red: strength, green: strength, blue: strength), "inputColor1": CIColor.black])!.outputImage!
        return circle.transformed(by: CGAffineTransform(a: max(1, rect.width / 2), b: 0, c: 0, d: max(1, rect.height / 2), tx: rect.midX, ty: rect.midY)).cropped(to: extent)
    }
    private func pixels(_ rect: CGRect, _ extent: CGRect) -> CGRect { CGRect(x: extent.minX + rect.minX * extent.width, y: extent.minY + rect.minY * extent.height, width: rect.width * extent.width, height: rect.height * extent.height) }
    private func blend(_ foreground: CIImage, over background: CIImage, mask: CIImage) -> CIImage {
        foreground.applyingFilter("CIBlendWithMask", parameters: [kCIInputBackgroundImageKey: background, kCIInputMaskImageKey: mask])
    }
    public func render(_ image: CIImage, recipe: EditRecipe, faces: [FaceRegion]) throws -> CIImage {
        let e = image.extent
        guard !e.isEmpty, !e.isInfinite else { throw ImageEngineError.message("사진 크기가 올바르지 않습니다.") }
        let a = recipe.adjustments
        let values = [a.exposure, a.contrast, a.saturation, a.warmth, a.skin, a.faceSlim] + recipe.spots.flatMap { [$0.x,$0.y,$0.sourceX,$0.sourceY,$0.radius] } + recipe.warps.flatMap { [$0.x,$0.y,$0.dx,$0.dy,$0.radius] }
        guard values.allSatisfy({ $0.isFinite }) else { throw ImageEngineError.message("보정 수치가 올바르지 않습니다.") }
        var result = image
        let chosen: [FaceRegion]
        if let selected = recipe.selectedFace { chosen = faces.indices.contains(selected) ? [faces[selected]] : [] } else { chosen = faces }
        if a.skin > 0, !chosen.isEmpty {
            var mask = CIImage(color: .black).cropped(to:e)
            for face in chosen {
                let r = pixels(face.rect,e)
                var local = ellipse(r.insetBy(dx: r.width*0.08,dy:r.height*0.03),extent:e,strength:min(0.85,a.skin*0.85))
                // Landmark fallback protects approximate feature positions when landmarks are unavailable.
                let features = [face.leftEye ?? CGRect(x:face.rect.minX+face.rect.width*0.15,y:face.rect.minY+face.rect.height*0.56,width:face.rect.width*0.28,height:face.rect.height*0.14),face.rightEye ?? CGRect(x:face.rect.minX+face.rect.width*0.57,y:face.rect.minY+face.rect.height*0.56,width:face.rect.width*0.28,height:face.rect.height*0.14),face.mouth ?? CGRect(x:face.rect.minX+face.rect.width*0.25,y:face.rect.minY+face.rect.height*0.18,width:face.rect.width*0.5,height:face.rect.height*0.18)]
                for feature in features {
                    let fr = pixels(feature,e).insetBy(dx:-r.width*0.045,dy:-r.height*0.045)
                    local = blend(CIImage(color:.black),over:local,mask:ellipse(fr,extent:e))
                }
                mask = local.applyingFilter("CIMaximumCompositing",parameters:[kCIInputBackgroundImageKey:mask])
            }
            let smooth = result.clampedToExtent().applyingFilter("CINoiseReduction",parameters:["inputNoiseLevel":0.06,"inputSharpness":0.3]).applyingFilter("CIGaussianBlur",parameters:[kCIInputRadiusKey:max(0.5,min(e.width,e.height)*0.0015)])
            result = blend(smooth,over:result,mask:mask).cropped(to:e)
        }
        var strokes: [WarpStroke] = []
        if a.faceSlim > 0 {
            for face in chosen {
                let r = face.rect
                let shift = min(1,a.faceSlim)*r.width*0.035
                let radius = r.width * e.width / min(e.width,e.height) * 0.34
                strokes += [WarpStroke(x:r.minX+r.width*0.12,y:r.minY+r.height*0.36,dx:shift,dy:0,radius:radius),WarpStroke(x:r.maxX-r.width*0.12,y:r.minY+r.height*0.36,dx:-shift,dy:0,radius:radius)]
            }
        }
        // Automatic adjustments form the base. Brush edits replay in the user's exact order.
        let operations = strokes.map { LocalEdit.warp($0) } + recipe.operations
        var warpKernel: CIWarpKernel?
        for operation in operations {
            switch operation {
            case .warp(let stroke):
                guard stroke.radius > 0 else { continue }
                if warpKernel == nil {
                    // Supported on iOS 8+ and macOS 10.10+, although deprecated since iOS 12.
                    // Keep this compatibility path: runtime Metal kernels require devices supporting
                    // dynamic libraries, which is narrower than our iOS 16 deployment target.
                    // Initialization/application failures are reported instead of dropping the edit.
                    warpKernel = CIWarpKernel(source: "kernel vec2 localWarp(vec2 center, vec2 delta, float radius) { vec2 p = destCoord(); float t = clamp(1.0 - distance(p, center) / radius, 0.0, 1.0); float w = t*t*(3.0-2.0*t); return p - delta*w; }")
                }
                guard let kernel = warpKernel else { throw ImageEngineError.message("얼굴·체형 보정 기능을 초기화하지 못했습니다.") }
                let radius = max(1,min(0.5,stroke.radius)*min(e.width,e.height))
                var dx = stroke.dx*e.width, dy = stroke.dy*e.height
                let length = hypot(dx,dy), limit = radius*0.25
                if length > limit { dx *= limit/length; dy *= limit/length }
                let margin = max(abs(dx),abs(dy))+2
                guard let warped = kernel.apply(extent:e,roiCallback:{ _, rect in rect.insetBy(dx:-margin,dy:-margin) },image:result.clampedToExtent(),arguments:[CIVector(x:e.minX+stroke.x*e.width,y:e.minY+stroke.y*e.height),CIVector(x:dx,y:dy),radius]) else { throw ImageEngineError.message("얼굴·체형 보정에 실패했습니다.") }
                result = warped.cropped(to:e)
            case .spot(let spot):
                guard spot.radius > 0 else { continue }
                let radius = min(0.3, spot.radius) * min(e.width,e.height)
                let center = CGPoint(x: e.minX + spot.x * e.width, y: e.minY + spot.y * e.height)
                let source = result.clampedToExtent().transformed(by: CGAffineTransform(translationX: (spot.x - spot.sourceX) * e.width, y: (spot.y - spot.sourceY) * e.height))
                result = blend(source, over: result, mask: ellipse(CGRect(x: center.x-radius,y:center.y-radius,width:radius*2,height:radius*2), extent:e)).cropped(to:e)
            }
        }
        if a.exposure != 0 { result = result.applyingFilter("CIExposureAdjust",parameters:[kCIInputEVKey:a.exposure]) }
        if a.contrast != 1 || a.saturation != 1 { result = result.applyingFilter("CIColorControls",parameters:[kCIInputContrastKey:a.contrast,kCIInputSaturationKey:a.saturation]) }
        if a.warmth != 0 { result = result.applyingFilter("CITemperatureAndTint",parameters:["inputNeutral":CIVector(x:6500,y:0),"inputTargetNeutral":CIVector(x:6500-max(-1,min(1,a.warmth))*2000,y:0)]) }
        return result.cropped(to:e)
    }
    public func cgImage(_ image: CIImage) throws -> CGImage {
        guard let cg = context.createCGImage(image,from:image.extent,format:.RGBA8,colorSpace:colorSpace) else { throw ImageEngineError.message("사진을 렌더링할 수 없습니다.") }
        return cg
    }
    public func export(_ image: CIImage, to url: URL, format: ExportFormat, quality: Double = 0.94) throws {
        let cg = try cgImage(image)
        let temp = url.deletingLastPathComponent().appendingPathComponent(".mellow-\(UUID().uuidString).tmp")
        defer { try? FileManager.default.removeItem(at:temp) }
        guard let destination = CGImageDestinationCreateWithURL(temp as CFURL,(format == .jpeg ? UTType.jpeg.identifier : UTType.png.identifier) as CFString,1,nil) else { throw ImageEngineError.message("저장할 폴더를 열 수 없습니다.") }
        CGImageDestinationAddImage(destination,cg,[kCGImageDestinationLossyCompressionQuality:max(0,min(1,quality)),kCGImagePropertyOrientation:1] as CFDictionary)
        guard CGImageDestinationFinalize(destination),let verify = CGImageSourceCreateWithURL(temp as CFURL,nil),let decoded = CGImageSourceCreateImageAtIndex(verify,0,nil),decoded.width == cg.width,decoded.height == cg.height else { throw ImageEngineError.message("저장된 사진을 검증하지 못했습니다.") }
        // Exclusive same-directory rename publishes atomically without hard-link support (e.g. exFAT).
        let status = temp.withUnsafeFileSystemRepresentation { src in url.withUnsafeFileSystemRepresentation { dst in renameatx_np(AT_FDCWD,src!,AT_FDCWD,dst!,UInt32(RENAME_EXCL)) } }
        guard status == 0 else {
            if errno == EEXIST { throw ImageEngineError.message("같은 이름의 파일이 이미 있습니다. 다른 이름을 선택하세요.") }
            throw ImageEngineError.message("사진을 저장하지 못했습니다: \(String(cString:strerror(errno)))")
        }
    }
}
