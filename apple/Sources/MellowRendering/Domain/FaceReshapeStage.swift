import CoreImage
import MellowShared

/// 얼굴 양옆을 미는 얼굴 폭 변형. width 음수면 좁게, 양수면 넓게. C 단계에서 ShapeWarpStage로 대체된다.
struct FaceReshapeStage: RenderStage {
    let name = "faceReshape"

    func apply(_ image: CIImage, in context: RenderContext) throws -> CIImage {
        let amount = -context.recipe.portrait.face.width
        guard amount != 0, !context.targetFaces.isEmpty else { return image }
        var result = image
        for face in context.targetFaces {
            for stroke in slimStrokes(for: face, amount: amount, context: context) {
                result = try LocalEditStage.applyWarp(stroke, to: result, context: context)
            }
        }
        return result
    }

    private func slimStrokes(for face: FaceGeometry, amount: Double, context: RenderContext) -> [WarpStroke] {
        let box = face.boundingBox
        let tuning = context.tuning
        let shift = max(-1, min(1, amount)) * box.width * tuning.faceSlimShiftFraction
        let radius = box.width * context.extent.width / context.shortSide * tuning.faceSlimRadiusFraction
        let y = box.minY + box.height * tuning.faceSlimAnchorY
        return [
            WarpStroke(x: box.minX + box.width * tuning.faceSlimAnchorX, y: y, dx: shift, dy: 0, radius: radius),
            WarpStroke(x: box.maxX - box.width * tuning.faceSlimAnchorX, y: y, dx: -shift, dy: 0, radius: radius),
        ]
    }
}
