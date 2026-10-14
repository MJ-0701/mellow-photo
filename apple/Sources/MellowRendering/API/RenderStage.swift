import CoreImage
import MellowShared

public struct RenderContext: Sendable {
    public let extent: CGRect
    public let recipe: EditRecipe
    public let faces: [FaceGeometry]
    /// recipe.portrait.targetFace를 적용한 결과. 범위 밖 인덱스면 비어 있다.
    public let targetFaces: [FaceGeometry]
    public let tuning: RenderTuning

    public init(extent: CGRect, recipe: EditRecipe, faces: [FaceGeometry], tuning: RenderTuning) {
        self.extent = extent
        self.recipe = recipe
        self.faces = faces
        self.tuning = tuning
        if let index = recipe.portrait.targetFace {
            targetFaces = faces.indices.contains(index) ? [faces[index]] : []
        } else {
            targetFaces = faces
        }
    }

    /// 정규화 사각형을 픽셀 좌표로.
    public func pixelRect(_ rect: NormalizedRect) -> CGRect {
        CGRect(
            x: extent.minX + rect.x * extent.width,
            y: extent.minY + rect.y * extent.height,
            width: rect.width * extent.width,
            height: rect.height * extent.height)
    }

    public func pixelPoint(x: Double, y: Double) -> CGPoint {
        CGPoint(x: extent.minX + x * extent.width, y: extent.minY + y * extent.height)
    }

    public var shortSide: CGFloat { min(extent.width, extent.height) }
}

public protocol RenderStage: Sendable {
    var name: String { get }
    func apply(_ image: CIImage, in context: RenderContext) throws -> CIImage
}
