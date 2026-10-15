import CoreImage
import MellowShared

public struct RenderContext: Sendable {
    public let extent: CGRect
    public let recipe: EditRecipe
    public let faces: [FaceGeometry]
    /// recipe.portrait.targetFace를 적용한 결과. 범위 밖 인덱스면 비어 있다.
    public let targetFaces: [FaceGeometry]
    public let tuning: RenderTuning
    public let lookCatalog: LookCatalog
    /// 자르기 도구 화면용. 기하 단계가 자르기만 건너뛴다.
    public let skipsCrop: Bool
    /// 사진 준비 때 찾은 자동 잡티. 영속화하지 않는다.
    public let blemishes: [BlemishSpot]
    /// recipe.portrait.targetFace를 적용한 잡티.
    public let targetBlemishes: [BlemishSpot]

    public init(
        extent: CGRect, recipe: EditRecipe, faces: [FaceGeometry], tuning: RenderTuning,
        lookCatalog: LookCatalog = .empty, skipsCrop: Bool = false, blemishes: [BlemishSpot] = []
    ) {
        self.extent = extent
        self.recipe = recipe
        self.faces = faces
        self.tuning = tuning
        self.lookCatalog = lookCatalog
        self.skipsCrop = skipsCrop
        self.blemishes = blemishes
        if let index = recipe.portrait.targetFace {
            targetFaces = faces.indices.contains(index) ? [faces[index]] : []
            targetBlemishes = blemishes.filter { $0.faceIndex == index }
        } else {
            targetFaces = faces
            targetBlemishes = blemishes
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
