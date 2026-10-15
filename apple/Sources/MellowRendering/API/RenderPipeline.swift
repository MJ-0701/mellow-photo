import CoreImage
import MellowShared

public struct RenderPipeline: Sendable {
    public let stages: [any RenderStage]

    public init(stages: [any RenderStage]) {
        self.stages = stages
    }

    /// 자동 보정이 기반이 되고 수동 편집이 그 위에, 색감은 마지막에.
    public static let standard = RenderPipeline(stages: [
        SkinStage(), FaceReshapeStage(), LocalEditStage(), ColorStage(), DetailStage(),
    ])

    public func render(_ image: CIImage, context: RenderContext) throws -> CIImage {
        guard !context.extent.isEmpty, !context.extent.isInfinite else { throw MellowError.invalidImageSize }
        guard context.recipe.allValuesFinite else { throw MellowError.invalidRecipeValues }
        var result = image
        for stage in stages {
            result = try stage.apply(result, in: context)
        }
        return result.cropped(to: context.extent)
    }
}
