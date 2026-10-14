import CoreImage
import MellowShared

/// 사용자의 잡티·변형을 기록 순서대로 재생한다.
struct LocalEditStage: RenderStage {
    let name = "localEdit"

    func apply(_ image: CIImage, in context: RenderContext) throws -> CIImage {
        var result = image
        for operation in context.recipe.operations {
            switch operation {
            case .warp(let stroke):
                result = try Self.applyWarp(stroke, to: result, context: context)
            case .spot(let spot):
                result = Self.applySpot(spot, to: result, context: context)
            }
        }
        return result
    }

    static func applyWarp(_ stroke: WarpStroke, to image: CIImage, context: RenderContext) throws -> CIImage {
        guard stroke.radius > 0 else { return image }
        let tuning = context.tuning
        let radius = max(1, min(tuning.warpMaxRadiusFraction, stroke.radius) * context.shortSide)
        return try WarpKernel.shared.apply(
            to: image,
            extent: context.extent,
            center: context.pixelPoint(x: stroke.x, y: stroke.y),
            delta: CGVector(dx: stroke.dx * context.extent.width, dy: stroke.dy * context.extent.height),
            radius: radius,
            displacementLimit: tuning.warpDisplacementLimit)
    }

    static func applySpot(_ spot: RetouchSpot, to image: CIImage, context: RenderContext) -> CIImage {
        guard spot.radius > 0 else { return image }
        let extent = context.extent
        let radius = min(context.tuning.spotMaxRadiusFraction, spot.radius) * context.shortSide
        let center = context.pixelPoint(x: spot.x, y: spot.y)
        let offset = CGAffineTransform(
            translationX: (spot.x - spot.sourceX) * extent.width, y: (spot.y - spot.sourceY) * extent.height)
        let source = image.clampedToExtent().transformed(by: offset)
        let mask = MaskBuilder.ellipse(
            CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2), extent: extent)
        return MaskBuilder.blend(source, over: image, mask: mask).cropped(to: extent)
    }
}
