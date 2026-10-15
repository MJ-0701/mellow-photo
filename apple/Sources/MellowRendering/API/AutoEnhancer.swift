import CoreImage
import Foundation
import MellowShared

/// 휘도 히스토그램과 평균색으로 슬라이더 값을 제안한다. 같은 수식을 다른 플랫폼이 재현할 수 있다.
public struct AutoEnhancer: Sendable {
    private let tuning: RenderTuning
    private let renderer: Renderer

    public init(tuning: RenderTuning, renderer: Renderer) {
        self.tuning = tuning
        self.renderer = renderer
    }

    public func suggestion(for image: CIImage, hasFaces: Bool) throws -> AutoEnhanceSuggestion {
        let bins = try luminanceHistogram(image)
        let mean = bins.enumerated().reduce(0.0) { $0 + center(of: $1.offset, in: bins) * $1.element }
        let low = percentile(bins, tuning.autoLowPercentile)
        let high = percentile(bins, tuning.autoHighPercentile)
        var color = ColorAdjustments()
        var detail = DetailAdjustments()
        let ratio = tuning.autoTargetLuminance / max(mean, tuning.autoMinimumLuminance)
        color.exposure = clamp(log2(ratio), limit: tuning.autoExposureLimit)
        if high - low >= tuning.autoFlatRange {
            if high >= tuning.autoHighlightThreshold {
                detail.highlights = -min(1, (high - tuning.autoHighlightRampStart) * tuning.autoRecoveryGain)
            }
            if low <= tuning.autoShadowThreshold {
                detail.shadows = min(1, (tuning.autoShadowRampEnd - low) * tuning.autoRecoveryGain)
            }
            color.saturation = tuning.autoSaturation
            color.contrast = tuning.autoContrast
            color.warmth = try warmthCorrection(image)
        }
        var portrait = PortraitAdjustments()
        if hasFaces {
            portrait.skin = SkinAdjustments(smoothing: tuning.autoSkinSmoothing, autoBlemish: true)
            portrait.features = FeatureAdjustments(eyeBrighten: tuning.autoEyeBrighten)
        }
        return AutoEnhanceSuggestion(color: color, detail: detail, portrait: portrait)
    }

    /// 정규화된 휘도 히스토그램(합 1). 구간은 sRGB 감마 값이라 임계값이 화면에서 보이는 밝기와 맞는다.
    private func luminanceHistogram(_ image: CIImage) throws -> [Double] {
        let gray = image.applyingFilter("CIColorControls", parameters: [kCIInputSaturationKey: 0])
            .applyingFilter("CILinearToSRGBToneCurve")
        let histogram = gray.applyingFilter(
            "CIAreaHistogram",
            parameters: [
                "inputExtent": CIVector(cgRect: image.extent), "inputCount": tuning.autoHistogramBins, "inputScale": 1,
            ])
        let pixels = try renderer.readPixels(histogram)
        let counts = stride(from: 0, to: pixels.count, by: 4).map { Double(pixels[$0]) }
        let total = counts.reduce(0, +)
        guard total > 0 else { throw MellowError.renderFailed }
        return counts.map { $0 / total }
    }

    private func center(of index: Int, in bins: [Double]) -> Double {
        (Double(index) + 0.5) / Double(bins.count)
    }

    private func percentile(_ bins: [Double], _ fraction: Double) -> Double {
        var cumulative = 0.0
        for (index, weight) in bins.enumerated() {
            cumulative += weight
            if cumulative >= fraction {
                return center(of: index, in: bins)
            }
        }
        return 1
    }

    /// 그레이 월드: 평균 R이 B보다 크면(따뜻한 캐스트) 차갑게, 반대면 따뜻하게.
    private func warmthCorrection(_ image: CIImage) throws -> Double {
        let average = image.applyingFilter("CIAreaAverage", parameters: ["inputExtent": CIVector(cgRect: image.extent)])
        let pixels = try renderer.readPixels(average)
        let red = Double(pixels[0])
        let blue = Double(pixels[2])
        guard red + blue > 0 else { return 0 }
        let cast = (red - blue) / (red + blue)
        return clamp(-cast * tuning.autoWarmthGain, limit: tuning.autoWarmthLimit)
    }

    private func clamp(_ value: Double, limit: Double) -> Double {
        max(-limit, min(limit, value))
    }
}
