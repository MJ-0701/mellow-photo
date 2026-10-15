import CoreImage
import MellowShared

public struct RenderContext: Sendable {
    public let extent: CGRect
    public let recipe: EditRecipe
    /// 사진 준비 때 계산한 분석 결과. 단계는 faces·blemishes 같은 접근자로 읽는다.
    public let analysis: PhotoAnalysis
    /// recipe.portrait.targetFace를 적용한 결과. 범위 밖 인덱스면 비어 있다.
    public let targetFaces: [FaceGeometry]
    public let tuning: RenderTuning
    public let lookCatalog: LookCatalog
    /// 자르기 도구 화면용. 기하 단계가 자르기만 건너뛴다.
    public let skipsCrop: Bool
    /// recipe.portrait.targetFace를 적용한 잡티.
    public let targetBlemishes: [BlemishSpot]

    public init(
        extent: CGRect, recipe: EditRecipe, analysis: PhotoAnalysis, tuning: RenderTuning,
        lookCatalog: LookCatalog = .empty, skipsCrop: Bool = false
    ) {
        self.extent = extent
        self.recipe = recipe
        self.analysis = analysis
        self.tuning = tuning
        self.lookCatalog = lookCatalog
        self.skipsCrop = skipsCrop
        let faces = analysis.faces
        let blemishes = analysis.blemishes
        if let index = recipe.portrait.targetFace {
            targetFaces = faces.indices.contains(index) ? [faces[index]] : []
            targetBlemishes = blemishes.filter { $0.faceIndex == index }
        } else {
            targetFaces = faces
            targetBlemishes = blemishes
        }
    }

    /// 얼굴·잡티만 있는 분석으로 만든다. 단계 테스트가 쓰는 형태다.
    /// 새 분석 결과는 이 인자 목록에 더하지 않고 PhotoAnalysis에만 더한다.
    public init(
        extent: CGRect, recipe: EditRecipe, faces: [FaceGeometry], tuning: RenderTuning,
        lookCatalog: LookCatalog = .empty, skipsCrop: Bool = false, blemishes: [BlemishSpot] = []
    ) {
        self.init(
            extent: extent, recipe: recipe, analysis: PhotoAnalysis(faces: faces, blemishes: blemishes),
            tuning: tuning, lookCatalog: lookCatalog, skipsCrop: skipsCrop)
    }

    /// 왼쪽부터 정렬된 얼굴.
    public var faces: [FaceGeometry] { analysis.faces }
    /// 사진 준비 때 찾은 자동 잡티. 영속화하지 않는다.
    public var blemishes: [BlemishSpot] { analysis.blemishes }
    /// 사진 준비 때 만든 인물 마스크. 사람이 없거나 분석이 실패했으면 nil이고 배경 단계가 건너뛴다.
    public var personMask: CIImage? { analysis.personMask }
    /// 같은 사진의 다각형 마스크 비트맵 캐시.
    var regionMasks: RegionMaskCache { analysis.regionMasks }

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
