import Foundation
import MellowShared

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
    /// 주름 밝히기가 보는 국소 저주파 반지름. 얼굴 폭 비율.
    /// 가장 좁은 띠 반지름(마리오네트 3%)의 절반이라 주름 그늘을 잡고, 모공 대역(fineBandFraction 0.6%)보다 커서 모공은 뺀다.
    public var foldLowBandFraction: Double = 0.015
    /// 주름 둘레 피부 평균을 재는 반지름. 얼굴 폭 비율. 띠 폭(3.5~8%)보다 넓어야 주름 자신이 평균에 덜 들어간다.
    public var foldSurroundFraction: Double = 0.12
    /// 주름 밝히기 1에서 국소 휘도에 대한 휘도 차이("주변 평균 − 국소 저주파"의 양수 부분)를 배율에 반영하는 비율.
    /// 배율 = 1 + foldLiftMax × 휘도 차이 ÷ 국소 휘도라 1이면 그늘이 주변 평균까지 올라 평평해 보인다.
    public var foldLiftMax: Double = 0.9
    /// 주름 밝히기 배율(1 + 휘도 차이 ÷ 국소 휘도)의 상한.
    /// 선형 휘도를 40% 잃은 그늘을 foldLiftMax 0.9로 올리는 배율(1 + 0.9 × 0.4 / 0.6)이 1.6이다.
    /// 이보다 깊은 그늘은 덜 올리고, 국소 휘도가 아주 낮은 눈가·속눈썹 옆에서 배율이 튀지 않는다.
    public var foldLiftMaxGain: Double = 1.6
    /// 주름 밝히기 배율의 분모(국소 휘도) 하한. 선형 0.01(감마 약 0.1)보다 어두운 곳에서 0으로 나누지 않는다.
    public var foldLumaFloor: Double = 0.01
    /// 얼룩 고르기·번들거림이 당기는 넓은 피부 평균의 반지름. 얼굴 폭 비율. 볼 그림자 같은 큰 명암은 남는다.
    public var toneBandFraction: Double = 0.12
    /// 얼룩 고르기 1에서 저주파를 넓은 평균 쪽으로 당기는 비율.
    public var toneEveningMax: Double = 0.8
    /// 선형 휘도가 볼 기준보다 이만큼 밝으면 번들거림으로 보기 시작한다. 피부 질감 잡음(±10%)은 걸리지 않는다.
    public var shineLumaOffset: Double = 0.12
    /// 시작점에서 이만큼 더 밝으면 번들거림 가중치 1.
    public var shineLumaRamp: Double = 0.1
    /// 번들거림 1에서 반사광의 저주파를 넓은 평균 쪽으로 당기고 중간 대역을 줄이는 비율. 모공 대역은 그대로다.
    public var shineReductionMax: Double = 0.85
    /// 붉은기 −1에서 볼 기준 Cr을 넘는 붉은 양을 줄이는 비율.
    public var rednessClearMax: Double = 0.7
    /// 붉은기 +1에서 감마 Cr에 고르게 더하는 값. 입술 생기(0.02)보다 조금 크다.
    public var rednessFlushMax: Double = 0.03

    public var warpMaxRadiusFraction: Double = 0.5
    public var warpDisplacementLimit: Double = 0.25
    /// 얼굴형·체형 원소 하나가 옮기는 최대 거리. push는 반지름 비율, scale은 배율, band는 늘림 비율.
    /// smoothstep 감쇠의 최대 기울기가 1.5 / 반지름이라 0.25면 원소 하나의 야코비안이 0.625 이상으로 접히지 않는다.
    public var shapeDisplacementLimit: Double = 0.25
    /// |yaw|가 이보다 크면 얼굴형 이동을 cos(|yaw|) / cos(이 값)으로 줄인다(스펙 0.35rad ≈ 20°). 이 값에서 1이라 끊기지 않는다.
    public var faceShapeYawThreshold: Double = 0.35
    /// 얼굴 폭 ±1에서 한쪽 윤곽을 미는 양. 얼굴 폭 비율. 같은 쪽 점 수로 나눠 겹치므로 실효 최대는 약 0.034
    /// (140mm 얼굴에서 약 5mm)이고 B0 얼굴 미세 조정(0.035)과 비슷하다.
    public var faceWidthMaxShift: Double = 0.06
    /// 턱선. 입 아래 윤곽점 몫으로 나눠 실효 최대 약 0.029, 위로 드는 양은 안쪽의 절반.
    public var faceJawMaxShift: Double = 0.07
    /// 광대. 각 쪽 윤곽 맨 위 점 하나를 민다.
    public var faceCheekboneMaxShift: Double = 0.04
    /// 눈 크기. scale 배율이라 눈 중심 선형 배율은 1 / (1 − 0.18) ≈ 1.22(큰 눈 보정의 흔한 1.2~1.3배).
    public var faceEyeSizeMaxScale: Double = 0.18
    /// 눈 간격. 눈 하나가 얼굴 폭의 2%(약 3mm) 움직인다.
    public var faceEyeDistanceMaxShift: Double = 0.02
    /// 코 폭. 코 날개 하나가 얼굴 폭의 2% 움직인다. 코 폭은 얼굴 폭의 25% 안팎이라 −1이면 약 16% 좁아진다.
    public var faceNoseWidthMaxShift: Double = 0.02
    /// 입 크기. scale 배율, 입 중심 선형 배율 약 1.18.
    public var faceMouthSizeMaxScale: Double = 0.15
    /// 미소. 입꼬리가 위로 얼굴 폭의 2.5%, 바깥으로 그 40%.
    public var faceSmileMaxShift: Double = 0.025
    /// 이마. 이마 가운데를 위·아래로 얼굴 폭의 5%(약 7mm).
    public var faceForeheadMaxShift: Double = 0.05
    /// 턱 길이. 턱 끝을 아래·위로 얼굴 폭의 5%.
    public var faceChinLengthMaxShift: Double = 0.05

    /// 얼굴형 항목별 최대 이동. eyeSize·mouthSize는 scale 배율, 나머지는 얼굴 폭 비율.
    public func faceShapeMaxShift(_ key: FaceShapeKey) -> Double {
        switch key {
        case .width: return faceWidthMaxShift
        case .jaw: return faceJawMaxShift
        case .cheekbone: return faceCheekboneMaxShift
        case .eyeSize: return faceEyeSizeMaxScale
        case .eyeDistance: return faceEyeDistanceMaxShift
        case .noseWidth: return faceNoseWidthMaxShift
        case .mouthSize: return faceMouthSizeMaxScale
        case .smile: return faceSmileMaxShift
        case .forehead: return faceForeheadMaxShift
        case .chinLength: return faceChinLengthMaxShift
        }
    }

    /// 눈·입술·치아 다각형 마스크를 흐리는 반지름. 얼굴 폭 비율. 300px 얼굴에서 1.2px라 눈꺼풀·피부로 거의 번지지 않는다.
    public var featureMaskFeather: Double = 0.004
    /// 흰자로 보는 밝기(sRGB 감마 BT.601 휘도)의 시작점과 1이 되는 폭. 홍채·속눈썹(0.2 안팎)은 빠지고 흰자(0.6~0.8)는 들어간다.
    public var scleraLumaMin: Double = 0.45
    public var scleraLumaRamp: Double = 0.15
    /// 흰자로 보는 채도(감마 Cb·Cr 거리) 상한과 0이 되는 폭. 흰자는 0.03 안팎, 눈꼬리 피부는 0.12 이상이다.
    public var scleraChromaMax: Double = 0.08
    public var scleraChromaRamp: Double = 0.04
    /// 눈동자 반지름. 눈 높이(눈 다각형 경계 상자의 짧은 변) 비율(스펙 0.5).
    public var irisRadiusFraction: Double = 0.5
    /// 안쪽 입술 넓이가 얼굴 상자 넓이의 이 비율보다 작으면 다문 입으로 보고 치아 미백을 건너뛴다.
    /// 다문 입의 안쪽 입술은 0.3% 안팎, 치아가 보이는 입은 1% 이상이다.
    public var mouthOpenMinArea: Double = 0.004
    /// 치아로 보는 밝기 시작점과 폭. 입안 그늘(0.1 안팎)은 빠진다.
    public var teethLumaMin: Double = 0.35
    public var teethLumaRamp: Double = 0.15
    /// 치아로 보는 붉은기(감마 Cr) 상한과 0이 되는 폭. 누런 치아는 0.04 안팎, 잇몸·혀·입술은 0.15 이상이다.
    public var teethRednessMax: Double = 0.08
    public var teethRednessRamp: Double = 0.04
    /// 눈 또렷하게 1에서 흰자를 흰색 쪽으로 섞는 비율(sRGB 감마 값). sRGB 199 회색 흰자가 약 210이 된다.
    public var eyeWhiteLift: Double = 0.2
    /// 눈 또렷하게 1에서 홍채의 CISharpenLuminance 선명도. 필터 기본값 0.4의 두 배.
    public var eyeIrisSharpen: Double = 0.8
    /// 홍채 선명하게의 반지름. 눈동자 반지름 비율. 미리보기 눈동자 15px에서 1.5px, 원본에서는 비례해 커진다.
    public var eyeIrisSharpenRadiusFraction: Double = 0.1
    /// 치아 미백 1에서 노란기(음의 감마 Cb)를 0 쪽으로 옮기는 비율.
    public var teethYellowRemoval: Double = 0.7
    /// 치아 미백 1에서 흰색 쪽으로 섞는 비율.
    public var teethLift: Double = 0.12
    /// 입술 생기 1에서 Cb·Cr 배율에 더하는 값(1.3배).
    public var lipSaturationMax: Double = 0.3
    /// 입술 생기 1에서 감마 Cr에 더하는 붉은기.
    public var lipRednessMax: Double = 0.02
    /// 배경 흐림 1의 반지름. 짧은 변 비율. 미리보기(짧은 변 1200)에서 24px, 1200만 화소 원본(짧은 변 3024)에서 60px.
    public var backgroundBlurMaxFraction: Double = 0.02
    /// 인물 마스크를 키운 뒤 흐리는 반지름. 짧은 변 비율. 512×384 마스크 한 칸(1600px 미리보기에서 약 3px)의 두 배를 넘겨 계단을 덮는다.
    public var backgroundMaskFeather: Double = 0.006
    /// 립 1에서 소프트 라이트 결과를 섞는 비율. 소프트 라이트는 입술 명암을 남겨 1에 가까워도 질감이 유지된다.
    public var makeupLipMaxOpacity: Double = 0.85
    /// 블러셔 1에서 소프트 라이트 결과를 섞는 비율.
    public var makeupBlushMaxOpacity: Double = 0.6
    /// 아이섀도 1에서 곱하기 결과를 섞는 비율. 곱하기는 진하게 어두워져 립보다 낮게 둔다.
    public var makeupEyeshadowMaxOpacity: Double = 0.45
    /// 아이섀도 띠를 흐리는 반지름. 얼굴 폭 비율. 300px 얼굴에서 2.4px라 눈 안쪽까지 번지지 않는다.
    public var makeupEyeshadowFeather: Double = 0.008
    /// 눈썹 1에서 원래 눈썹 평균색으로 곱한 결과를 섞는 비율.
    public var makeupBrowMaxOpacity: Double = 0.5
    /// 넓힌 눈썹을 흐리는 반지름. 얼굴 폭 비율.
    public var makeupBrowFeather: Double = 0.006
    /// 쉐딩 1에서 회갈색 곱하기 결과를 섞는 비율.
    public var makeupShadeMaxOpacity: Double = 0.4
    /// 하이라이터 1에서 스크린 결과를 섞는 비율.
    public var makeupHighlightMaxOpacity: Double = 0.3
    /// 쉐딩 색(sRGB 감마 값). 스펙 6의 회갈색.
    public var makeupShadeRGB: [Double] = [0.72, 0.6, 0.52]
    /// 하이라이터 색(sRGB 감마 값). 따뜻한 흰색.
    public var makeupHighlightRGB: [Double] = [1, 0.97, 0.92]
    /// 관절 신뢰도가 이보다 낮으면 없는 것으로 본다(스펙 5).
    public var bodyJointMinConfidence: Double = 0.3
    /// 체형 push 항목 하나의 이동 상한. 어깨 폭 비율(스펙 0.06, "몸 폭의 6% 이내"). 항목별 최대가 이보다 크면 이 값으로 자른다.
    public var bodyShapeMaxShift: Double = 0.06
    /// 허리 ±1에서 한쪽 옆구리를 미는 양. 어깨 폭 40cm면 2.4cm라 허리 폭(약 28cm)이 −1에서 약 17% 줄어든다.
    public var bodyWaistMaxShift: Double = 0.06
    /// 몸 전체. 가슴·골반·허벅지 바깥 세 곳을 각각 어깨 폭의 3.5%(약 1.4cm).
    public var bodyOverallMaxShift: Double = 0.035
    /// 팔. 위팔 양옆을 각각 어깨 폭의 2%(약 0.8cm, 위팔 폭 약 9.6cm의 17%). 아래팔은 그 75%.
    public var bodyArmMaxShift: Double = 0.02
    /// 허벅지. 양옆을 각각 어깨 폭의 3.5%(약 1.4cm, 허벅지 폭 약 16cm의 17%).
    public var bodyThighMaxShift: Double = 0.035
    /// 어깨. 각 어깨 관절을 어깨 폭의 4%(약 1.6cm)라 어깨 폭이 ±8% 바뀐다.
    public var bodyShoulderMaxShift: Double = 0.04
    /// 목. 목 관절과 턱 사이를 어깨 폭의 3%(약 1.2cm) 올리거나 내린다. 턱·입은 움직이지 않는다.
    public var bodyNeckMaxShift: Double = 0.03
    /// 다리 길게 1의 띠 늘림 비율(스펙 0.08). 골반~발목이 8% 길어지고 발 아래는 그만큼 사진 밖으로 밀린다.
    public var legLengthMaxStretch: Double = 0.08

    /// 체형 항목별 최대. legLength는 띠 늘림 비율, 나머지는 어깨 폭 비율의 push 이동이다.
    public func bodyItemMaxShift(_ key: BodyShapeKey) -> Double {
        switch key {
        case .legLength: return legLengthMaxStretch
        case .waist: return bodyWaistMaxShift
        case .overall: return bodyOverallMaxShift
        case .arms: return bodyArmMaxShift
        case .thighs: return bodyThighMaxShift
        case .shoulders: return bodyShoulderMaxShift
        case .neck: return bodyNeckMaxShift
        }
    }

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
    /// 얼굴이 있을 때 자동 보정이 제안하는 눈 또렷하게(스펙 7).
    public var autoEyeBrighten: Double = 0.2
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
