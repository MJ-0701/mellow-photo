import CoreImage
import MellowShared

/// 글로우(흐린 빛 스크린) → 그레인(회색 잡음 오버레이). 룩 뒤 마지막 단계라 기하 뒤 현재 extent를 쓴다. 분석이 필요 없다.
/// 값은 AdjustmentRange.unit으로 직접 자른다. 그레인은 CIRandomGenerator가 위치마다 고정값이라 결정적이다.
struct EffectStage: RenderStage {
    let name = "effect"

    /// 오버레이의 중립 회색. 이 값의 층은 항등이다.
    private static let neutralGray = 0.5
    /// 알갱이 한 변의 하한(픽셀).
    private static let minimumGrainSize: CGFloat = 1

    func apply(_ image: CIImage, in context: RenderContext) throws -> CIImage {
        let values = Self.clamped(context.recipe.effects)
        guard values.hasEffect else { return image }
        let extent = image.extent
        let shortSide = min(extent.width, extent.height)
        var result = image
        if values.glow > 0 {
            result = Self.glowed(result, amount: values.glow, shortSide: shortSide, tuning: context.tuning)
        }
        if values.grain > 0 {
            result = try Self.grained(result, amount: values.grain, shortSide: shortSide, tuning: context.tuning)
        }
        return result.cropped(to: extent)
    }

    static func clamped(_ effects: EffectAdjustments) -> EffectAdjustments {
        var copy = effects
        for key in EffectKey.allCases {
            copy[key] = AdjustmentRange.clamped(effects[key], to: AdjustmentRange.unit)
        }
        return copy
    }

    static func glowRadius(shortSide: CGFloat, tuning: RenderTuning) -> Double {
        Double(shortSide) * tuning.glowRadiusFraction
    }

    static func grainSize(shortSide: CGFloat, tuning: RenderTuning) -> CGFloat {
        max(minimumGrainSize, shortSide * CGFloat(tuning.grainSizeFraction))
    }

    /// 밝은 영역이 번지는 글로우. 흐린 이미지를 제곱해 밝은 곳에 몰린 빛 층을 만들고 세기만큼 스크린으로 얹는다.
    /// CIBloom은 고르게 밝은 영역을 더 밝히지 않아(어두운 이웃만 밝힌다) 쓰지 않는다. 가장자리는 늘려 흐린다.
    /// 흐린 사본은 0…1로 자른다. 빛 층이 1을 넘으면 스크린 1 − (1 − a)(1 − b)가 1을 넘는 원본을 어둡게(음수까지) 하고,
    /// 광색역 음수 성분은 제곱하면 빛이 되기 때문이다. 자르면 빛 층은 glowMaxIntensity 이하라 출력이 원본보다 어두워지지 않는다.
    static func glowed(_ image: CIImage, amount: Double, shortSide: CGFloat, tuning: RenderTuning) -> CIImage {
        let blurred = FrequencySeparation.blurred(image, radius: glowRadius(shortSide: shortSide, tuning: tuning))
            .applyingFilter(
                "CIColorClamp",
                parameters: [
                    "inputMinComponents": CIVector(x: 0, y: 0, z: 0, w: 0),
                    "inputMaxComponents": CIVector(x: 1, y: 1, z: 1, w: 1),
                ])
        let highlights = blurred.applyingFilter(
            "CIMultiplyCompositing", parameters: [kCIInputBackgroundImageKey: blurred])
        let strength = CGFloat(amount * tuning.glowMaxIntensity)
        let light = highlights.applyingFilter(
            "CIColorMatrix",
            parameters: [
                "inputRVector": CIVector(x: strength, y: 0, z: 0, w: 0),
                "inputGVector": CIVector(x: 0, y: strength, z: 0, w: 0),
                "inputBVector": CIVector(x: 0, y: 0, z: strength, w: 0),
            ])
        return light.applyingFilter("CIScreenBlendMode", parameters: [kCIInputBackgroundImageKey: image])
            .cropped(to: image.extent)
    }

    /// 회색 잡음 층을 sRGB 감마 공간에서 오버레이로 얹고 선형으로 되돌린다.
    static func grained(_ image: CIImage, amount: Double, shortSide: CGFloat, tuning: RenderTuning) throws -> CIImage {
        let layer = try grainLayer(
            extent: image.extent, amplitude: amount * tuning.grainMaxAmplitude,
            grainSize: grainSize(shortSide: shortSide, tuning: tuning))
        let base = image.applyingFilter("CILinearToSRGBToneCurve")
        return layer.applyingFilter("CIOverlayBlendMode", parameters: [kCIInputBackgroundImageKey: base])
            .applyingFilter("CISRGBToneCurveToLinear").cropped(to: image.extent)
    }

    /// 0.5 ± amplitude/2의 회색 잡음. CIRandomGenerator의 알파(0…1 균등)를 회색으로 쓰고 grainSize 배로 키운다.
    /// 잡음은 무한 extent라 원점이 0이 아닌 extent도 가장자리까지 채운다.
    static func grainLayer(extent: CGRect, amplitude: Double, grainSize: CGFloat) throws -> CIImage {
        guard let random = CIFilter(name: "CIRandomGenerator")?.outputImage else { throw MellowError.renderFailed }
        let gain = CGFloat(amplitude)
        let bias = CGFloat(neutralGray - amplitude / 2)
        let noise = random.applyingFilter(
            "CIColorMatrix",
            parameters: [
                "inputRVector": CIVector(x: 0, y: 0, z: 0, w: gain),
                "inputGVector": CIVector(x: 0, y: 0, z: 0, w: gain),
                "inputBVector": CIVector(x: 0, y: 0, z: 0, w: gain),
                "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 0),
                "inputBiasVector": CIVector(x: bias, y: bias, z: bias, w: 1),
            ])
        return noise.transformed(by: CGAffineTransform(scaleX: grainSize, y: grainSize)).cropped(to: extent)
    }
}
