import Foundation

public struct RenderTuning: Sendable {
    /// 미리보기 긴 변. 8GB 이상 1600, 미만 1200.
    public var previewMaxDimension: Int = 1600
    public var previewCacheCapacity: Int = 3
    public var thumbnailMaxDimension: Int = 220

    public var skinMaskMaxStrength: Double = 0.85
    public var skinFaceInsetX: Double = 0.08
    public var skinFaceInsetY: Double = 0.03
    public var skinFeatureInset: Double = 0.045
    public var skinNoiseLevel: Double = 0.06
    public var skinNoiseSharpness: Double = 0.3
    public var skinBlurRadiusFraction: Double = 0.0015
    public var skinBlurMinimumRadius: Double = 0.5
    /// 눈썹 위로 이마를 덮는 높이. 얼굴 상자 높이 비율. Vision 상자 위끝은 눈썹 근처라 20%면 이마 중간이고, 머리카락은 피부색 가중치가 뺀다.
    public var skinForeheadExtension: Double = 0.2
    /// 눈·눈썹·입술 보호 영역을 넓히는 폭. 얼굴 폭 비율. 마스크 흐림의 3σ(4.5%)보다 넓어야 눈 안쪽이 정확히 0이 된다.
    public var skinFeatureFeather: Double = 0.05
    /// 볼 평균과의 Cb·Cr 거리 기준(sRGB 감마 값). 이 안은 가중치 1, 두 배에서 0. 한 얼굴 안 피부 편차는 0.02 안팎이고 무채색 머리카락·배경은 0.06 이상 떨어진다.
    public var skinChromaSigma: Double = 0.04
    /// 피부 마스크를 마지막에 흐리는 반지름. 얼굴 폭 비율.
    public var skinMaskFeather: Double = 0.015
    /// 다각형 마스크를 그리는 비트맵의 긴 변. 마스크는 흐리므로 512면 48MP에서도 계단이 보이지 않는다.
    public var regionMaskMaxDimension: Int = 512

    public var faceSlimShiftFraction: Double = 0.035
    public var faceSlimRadiusFraction: Double = 0.34
    public var faceSlimAnchorX: Double = 0.12
    public var faceSlimAnchorY: Double = 0.36

    public var warpMaxRadiusFraction: Double = 0.5
    public var warpDisplacementLimit: Double = 0.25
    public var spotMaxRadiusFraction: Double = 0.3
    public var warmthKelvinRange: Double = 2000
    public var neutralKelvin: Double = 6500

    /// highlights −1에서 CIHighlightShadowAdjust의 highlightAmount가 1 − 이 값까지 내려간다.
    public var highlightReductionRange: Double = 0.7
    /// highlights +1에서 밝은 구간 톤 커브를 이만큼 올린다.
    public var highlightLiftAmount: Double = 0.12
    public var sharpnessMax: Double = 1.5
    public var vignetteRadius: Double = 1.5
    /// 룩 tint ±1이 CITemperatureAndTint 목표 중립 y ±이 값이 된다.
    public var lookTintRange: Double = 60

    /// 자동 보정이 노출로 맞추는 평균 휘도(sRGB 감마 값).
    public var autoTargetLuminance: Double = 0.45
    public var autoWarmthGain: Double = 0.5
    public var autoWarmthLimit: Double = 0.3
    public var autoHighlightThreshold: Double = 0.97
    public var autoShadowThreshold: Double = 0.03
    public var autoSaturation: Double = 1.08
    public var autoContrast: Double = 1.04
    public var autoSkinSmoothing: Double = 0.3
    /// 상·하위 백분위 차이가 이보다 작으면 단색으로 보고 노출만 조정한다.
    public var autoFlatRange: Double = 0.05
    public var autoExposureLimit: Double = 1
    public var autoHistogramBins: Int = 64
    /// 어두운 끝·밝은 끝으로 보는 히스토그램 백분위.
    public var autoLowPercentile: Double = 0.01
    public var autoHighPercentile: Double = 0.99
    /// highlights = −(L₉₉ − 이 값) × autoRecoveryGain.
    public var autoHighlightRampStart: Double = 0.9
    /// shadows = (이 값 − L₁) × autoRecoveryGain.
    public var autoShadowRampEnd: Double = 0.1
    public var autoRecoveryGain: Double = 5
    /// 검은 이미지에서 log2가 발산하지 않게 하는 평균 휘도 하한.
    public var autoMinimumLuminance: Double = 0.001

    public init() {}

    public static func forCurrentDevice(physicalMemory: UInt64 = ProcessInfo.processInfo.physicalMemory) -> RenderTuning
    {
        var tuning = RenderTuning()
        let gigabyte: UInt64 = 1 << 30
        tuning.previewMaxDimension = physicalMemory >= 8 * gigabyte ? 1600 : 1200
        return tuning
    }
}
