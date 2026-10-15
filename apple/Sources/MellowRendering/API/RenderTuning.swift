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

    public init() {}

    public static func forCurrentDevice(physicalMemory: UInt64 = ProcessInfo.processInfo.physicalMemory) -> RenderTuning
    {
        var tuning = RenderTuning()
        let gigabyte: UInt64 = 1 << 30
        tuning.previewMaxDimension = physicalMemory >= 8 * gigabyte ? 1600 : 1200
        return tuning
    }
}
