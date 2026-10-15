import CoreImage
import MellowShared

/// 하이라이트·그림자·선명도·비네팅. 값이 전부 기본이면 항등.
struct DetailStage: RenderStage {
    let name = "detail"

    /// CIToneCurve 다섯 점의 x 위치(항등 커브의 고정 앵커). 조정값이 아니라 커브 정의라 튜닝 상수로 두지 않는다.
    private static let toneCurveAnchors: [Double] = [0, 0.25, 0.5, 0.75, 1]
    /// 하이라이트 올리기에서 y를 들어 올리는 앵커(0.75 지점)의 인덱스.
    private static let liftedAnchorIndex = 3

    func apply(_ image: CIImage, in context: RenderContext) throws -> CIImage {
        let detail = context.recipe.detail
        guard !detail.isDefault else { return image }
        let tuning = context.tuning
        var result = image
        if detail.highlights < 0 || detail.shadows != 0 {
            let highlightAmount = 1 + min(0, detail.highlights) * tuning.highlightReductionRange
            result = result.applyingFilter(
                "CIHighlightShadowAdjust",
                parameters: [
                    "inputHighlightAmount": highlightAmount,
                    "inputShadowAmount": detail.shadows,
                    "inputRadius": 0,
                ])
        }
        if detail.highlights > 0 {
            let lift = detail.highlights * tuning.highlightLiftAmount
            result = result.applyingFilter("CIToneCurve", parameters: Self.liftedToneCurve(lift: lift))
        }
        if detail.sharpness > 0 {
            result = result.applyingFilter(
                "CISharpenLuminance", parameters: ["inputSharpness": detail.sharpness * tuning.sharpnessMax])
        }
        if detail.vignette > 0 {
            result = result.applyingFilter(
                "CIVignette", parameters: ["inputIntensity": detail.vignette, "inputRadius": tuning.vignetteRadius])
        }
        return result.cropped(to: context.extent)
    }

    /// 항등 톤 커브에서 0.75 앵커만 `lift`만큼(최대 1) 올린 CIToneCurve 파라미터.
    private static func liftedToneCurve(lift: Double) -> [String: Any] {
        var parameters: [String: Any] = [:]
        for (index, x) in toneCurveAnchors.enumerated() {
            let y = index == liftedAnchorIndex ? min(1, x + lift) : x
            parameters["inputPoint\(index)"] = CIVector(x: x, y: y)
        }
        return parameters
    }
}
