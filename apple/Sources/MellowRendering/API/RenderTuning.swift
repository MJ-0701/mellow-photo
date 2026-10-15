import Foundation

public struct RenderTuning: Sendable {
    /// 미리보기 긴 변. 8GB 이상 1600, 미만 1200.
    public var previewMaxDimension: Int = 1600
    public var previewCacheCapacity: Int = 3
    public var thumbnailMaxDimension: Int = 220

    public var skinMaskMaxStrength: Double = 0.85
    public var skinFaceInsetX: Double = 0.08
    public var skinFaceInsetY: Double = 0.03
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
    /// 모공 대역의 위쪽 경계 반지름. 얼굴 폭 비율. 모공은 얼굴 폭의 0.5% 안팎이다(400px 얼굴에서 2.4px).
    public var fineBandFraction: Double = 0.006
    /// 얼룩·잔주름 대역의 위쪽 경계 반지름. 얼굴 폭 비율. 이보다 큰 명암(광대 그림자 등)은 남긴다.
    public var midBandFraction: Double = 0.04
    /// 피부 보정 1에서 중간 대역을 줄이는 비율. 15%를 남겨 플라스틱 느낌을 피한다.
    public var midReductionMax: Double = 0.85
    /// 잡티를 찾을 때 얼굴 영역을 줄이는 긴 변. readPixels 세 번이 각각 1M float 이하가 된다.
    public var blemishAnalysisMaxDimension: Int = 512
    /// 잡티 반지름의 하한·상한. 얼굴 폭 비율(스펙 0.5%~2%). 여드름 3~5mm는 얼굴 폭 140mm의 1~1.8%다.
    public var blemishMinRadiusFraction: Double = 0.005
    public var blemishMaxRadiusFraction: Double = 0.02
    /// 주변 밝기를 재는 흐림 반지름. 잡티 최대 반지름의 배수.
    public var blemishSurroundScale: Double = 3
    /// 주변보다 이만큼(상대값) 어두워야 잡티 후보. 모공 잡음은 흐린 뒤 ±1% 안팎이다.
    public var blemishLumaDrop: Double = 0.06
    /// 주변보다 Cr이 이만큼 높아야 잡티 후보. 무채색 그림자·얼룩은 0에 가깝다.
    public var blemishRednessMin: Double = 0.012
    /// 피부 마스크(세기 1)가 이 값 이상인 곳만 본다.
    public var blemishMaskThreshold: Double = 0.5
    /// 얼굴당 잡티 수 상한(스펙).
    public var blemishMaxPerFace: Int = 40
    /// 잡티를 덮는 복제 원의 반지름 배수. applySpot 마스크는 반지름 65%까지만 완전히 복사하므로 1/0.65보다 커야 한다.
    public var blemishHealRadiusScale: Double = 1.8
    /// 복제 원본을 복제 반지름의 이 배수만큼 얼굴 가운데 쪽 옆 피부에서 가져온다. 2 이상이면 원이 겹치지 않는다.
    public var blemishSourceOffset: Double = 2.5

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
