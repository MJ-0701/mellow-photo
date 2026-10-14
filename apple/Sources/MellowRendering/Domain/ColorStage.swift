import CoreImage
import MellowShared

struct ColorStage: RenderStage {
    let name = "color"

    func apply(_ image: CIImage, in context: RenderContext) throws -> CIImage {
        let color = context.recipe.color
        let tuning = context.tuning
        var result = image
        if color.exposure != 0 {
            result = result.applyingFilter("CIExposureAdjust", parameters: [kCIInputEVKey: color.exposure])
        }
        if color.contrast != 1 || color.saturation != 1 {
            result = result.applyingFilter(
                "CIColorControls",
                parameters: [kCIInputContrastKey: color.contrast, kCIInputSaturationKey: color.saturation])
        }
        if color.warmth != 0 {
            let clamped = max(-1, min(1, color.warmth))
            result = result.applyingFilter(
                "CITemperatureAndTint",
                parameters: [
                    "inputNeutral": CIVector(x: tuning.neutralKelvin, y: 0),
                    "inputTargetNeutral": CIVector(x: tuning.neutralKelvin - clamped * tuning.warmthKelvinRange, y: 0),
                ])
        }
        return result
    }
}
