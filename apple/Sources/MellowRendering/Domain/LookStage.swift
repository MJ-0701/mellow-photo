import CoreImage
import MellowShared

/// 룩 파라미터를 Core Image 기본 필터로 조립하고 강도만큼 원본과 섞는다.
struct LookStage: RenderStage {
    let name = "look"

    func apply(_ image: CIImage, in context: RenderContext) throws -> CIImage {
        let selection = context.recipe.look
        guard selection.intensity > 0, let look = context.lookCatalog.look(id: selection.id) else { return image }
        // 기하 단계 뒤에 오므로 원본 extent가 아니라 현재 이미지 extent로 자른다.
        let styled = Self.styled(image, look: look, tuning: context.tuning).cropped(to: image.extent)
        if selection.intensity >= 1 {
            return styled
        }
        return styled.applyingFilter(
            "CIMix", parameters: [kCIInputBackgroundImageKey: image, "inputAmount": selection.intensity]
        ).cropped(to: image.extent)
    }

    /// 강도 1의 룩 결과. 룩 썸네일도 이 함수를 쓴다.
    static func styled(_ image: CIImage, look: Look, tuning: RenderTuning) -> CIImage {
        var result = image
        if let curve = Self.curveParameters(look) {
            result = result.applyingFilter("CIToneCurve", parameters: curve)
        }
        if look.saturation != 1 || look.contrast != 1 {
            result = result.applyingFilter(
                "CIColorControls",
                parameters: [kCIInputSaturationKey: look.saturation, kCIInputContrastKey: look.contrast])
        }
        if look.warmth != 0 || look.tint != 0 {
            let warmth = max(-1, min(1, look.warmth))
            let targetKelvin = tuning.neutralKelvin - warmth * tuning.warmthKelvinRange
            let targetTint = look.tint * tuning.lookTintRange
            result = result.applyingFilter(
                "CITemperatureAndTint",
                parameters: [
                    "inputNeutral": CIVector(x: tuning.neutralKelvin, y: 0),
                    "inputTargetNeutral": CIVector(x: targetKelvin, y: targetTint),
                ])
        }
        if look.vignette > 0 {
            result = result.applyingFilter(
                "CIVignette", parameters: ["inputIntensity": look.vignette, "inputRadius": tuning.vignetteRadius])
        }
        return result
    }

    /// 점 5개짜리 커브. 첫 점은 fade만큼 올린다. 점이 5개가 아니면 커브를 건너뛴다.
    private static func curveParameters(_ look: Look) -> [String: Any]? {
        guard look.toneCurve.count == 5, look.toneCurve.allSatisfy({ $0.count == 2 }) else { return nil }
        var parameters: [String: Any] = [:]
        for (index, point) in look.toneCurve.enumerated() {
            var y = point[1]
            if index == 0 {
                y = min(1, y + look.fade * Look.fadeLift)
            }
            parameters["inputPoint\(index)"] = CIVector(x: point[0], y: y)
        }
        return parameters
    }
}
