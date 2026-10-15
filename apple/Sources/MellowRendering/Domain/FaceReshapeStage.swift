import CoreImage
import MellowShared

/// A 범위에서는 얼굴 양옆을 안쪽으로 미는 faceSlim만 담는다. C에서 부위별로 확장된다.
struct FaceReshapeStage: RenderStage {
    let name = "faceReshape"

    func apply(_ image: CIImage, in context: RenderContext) throws -> CIImage {
        let amount = -context.recipe.portrait.face.width
        guard amount > 0, !context.targetFaces.isEmpty else { return image }
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
        let shift = min(1, amount) * box.width * tuning.faceSlimShiftFraction
        let radius = box.width * context.extent.width / context.shortSide * tuning.faceSlimRadiusFraction
        let y = box.minY + box.height * tuning.faceSlimAnchorY
        return [
            WarpStroke(x: box.minX + box.width * tuning.faceSlimAnchorX, y: y, dx: shift, dy: 0, radius: radius),
            WarpStroke(x: box.maxX - box.width * tuning.faceSlimAnchorX, y: y, dx: -shift, dy: 0, radius: radius),
        ]
    }
}
