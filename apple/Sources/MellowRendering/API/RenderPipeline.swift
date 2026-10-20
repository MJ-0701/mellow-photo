import CoreImage
import MellowShared

public struct RenderPipeline: Sendable {
    public let stages: [any RenderStage]

    public init(stages: [any RenderStage]) {
        self.stages = stages
    }

    /// 자동 보정이 기반이 되고 수동 편집이 그 위에, 기하가 출력 화면을 정하고, 색감은 마지막에.
    /// 좌표·마스크 기반 단계(피부·몸 피부·눈입·메이크업·배경·얼굴형·수동 편집)는 기하 앞이라 원본 좌표를 쓰고, 비네팅·선명도는 기하 뒤라 잘린 화면을 따른다.
    public static let standard = RenderPipeline(stages: [
        SkinStage(), BodySkinStage(), FeatureStage(), MakeupStage(), BackgroundStage(), ShapeWarpStage(),
        LocalEditStage(), GeometryStage(), ColorStage(), DetailStage(), LookStage(),
    ])

    public func render(_ image: CIImage, context: RenderContext) throws -> CIImage {
        guard !context.extent.isEmpty, !context.extent.isInfinite else { throw MellowError.invalidImageSize }
        guard context.recipe.allValuesFinite else { throw MellowError.invalidRecipeValues }
        var result = image
        for stage in stages {
            result = try stage.apply(result, in: context)
        }
        // 각 단계가 자기 extent로 자른다. 기하 단계가 extent를 바꾸므로 원본 extent로 다시 자르지 않는다.
        return result
    }
}
