import CoreImage
import MellowShared

/// 눈·치아 영역을 고르는 밝기·채도 규칙. 값은 sRGB 감마 기준이다.
struct ToneRule: Equatable {
    /// 이 휘도에서 가중치가 오르기 시작해 lumaMin + lumaRamp에서 1이 된다.
    var lumaMin: Double
    var lumaRamp: Double
    /// 지표가 limit 아래면 1, limit + limitRamp 위면 0이다.
    var limit: Double
    var limitRamp: Double
    /// true면 지표가 Cr(붉은기), false면 Cb·Cr 거리(채도).
    var rednessOnly: Bool

    /// 흰자: 밝고 무채색.
    static func sclera(_ tuning: RenderTuning) -> ToneRule {
        ToneRule(
            lumaMin: tuning.scleraLumaMin, lumaRamp: tuning.scleraLumaRamp, limit: tuning.scleraChromaMax,
            limitRamp: tuning.scleraChromaRamp, rednessOnly: false)
    }

    /// 치아: 밝고 붉지 않음. 누런 기는 남기고 입술·잇몸·혀를 뺀다.
    static func teeth(_ tuning: RenderTuning) -> ToneRule {
        ToneRule(
            lumaMin: tuning.teethLumaMin, lumaRamp: tuning.teethLumaRamp, limit: tuning.teethRednessMax,
            limitRamp: tuning.teethRednessRamp, rednessOnly: true)
    }
}

/// 감마 YCbCr에서의 색 이동. 기본값은 항등이다.
struct ToneShift: Equatable {
    /// 흰색 쪽으로 섞는 비율.
    var lift: Double = 0
    /// 음의 Cb(노란기)를 0 쪽으로 옮기는 비율.
    var yellowRemoval: Double = 0
    /// Cb·Cr 배율.
    var saturation: Double = 1
    /// Cr에 더하는 값.
    var redness: Double = 0
}

/// 눈·입 보정의 CIKL 색 커널을 감싸는 유일한 자리. SkinKernels처럼 Metal로 바꿀 때 이 타입만 바꾼다.
final class FeatureKernels: @unchecked Sendable {
    static let shared = FeatureKernels()

    private let toneWeight: CIColorKernel?
    private let toneShift: CIColorKernel?

    /// 휘도는 BT.601, Cb·Cr은 SkinKernels와 같은 BT.601 계수다(sRGB 감마 값 기준).
    private init() {
        toneWeight = CIColorKernel(
            source: """
                kernel vec4 toneWeight(__sample pixel, float lumaMin, float lumaRamp, float limit, float limitRamp,
                                       float rednessOnly) {
                    float luma = dot(pixel.rgb, vec3(0.299, 0.587, 0.114));
                    vec2 chroma = vec2(dot(pixel.rgb, vec3(-0.168736, -0.331264, 0.5)),
                                       dot(pixel.rgb, vec3(0.5, -0.418688, -0.081312)));
                    float metric = mix(length(chroma), chroma.y, rednessOnly);
                    float bright = clamp((luma - lumaMin) / lumaRamp, 0.0, 1.0);
                    float plain = clamp((limit - metric) / limitRamp, 0.0, 1.0);
                    float w = bright * plain;
                    return vec4(w, w, w, 1.0);
                }
                """)
        toneShift = CIColorKernel(
            source: """
                kernel vec4 toneShift(__sample pixel, float lift, float yellowRemoval, float saturation,
                                      float redness) {
                    vec3 rgb = pixel.rgb;
                    float y = dot(rgb, vec3(0.299, 0.587, 0.114));
                    float cb = dot(rgb, vec3(-0.168736, -0.331264, 0.5));
                    float cr = dot(rgb, vec3(0.5, -0.418688, -0.081312));
                    cb = (cb - min(cb, 0.0) * yellowRemoval) * saturation;
                    cr = cr * saturation + redness;
                    vec3 shifted = vec3(y + 1.402 * cr, y - 0.344136 * cb - 0.714136 * cr, y + 1.772 * cb);
                    return vec4(clamp(mix(shifted, vec3(1.0), lift), 0.0, 1.0), pixel.a);
                }
                """)
    }

    /// image는 작업 색공간(선형) 이미지. 감마로 바꿔 규칙을 적용한 회색 가중치(0…1)를 extent 안에서 돌려준다.
    func weight(of image: CIImage, rule: ToneRule, extent: CGRect) throws -> CIImage {
        guard let toneWeight, rule.lumaRamp > 0, rule.limitRamp > 0 else { throw MellowError.renderFailed }
        let encoded = image.applyingFilter("CILinearToSRGBToneCurve")
        let arguments: [Any] = [
            encoded, rule.lumaMin, rule.lumaRamp, rule.limit, rule.limitRamp, rule.rednessOnly ? 1.0 : 0.0,
        ]
        guard let weight = toneWeight.apply(extent: extent, arguments: arguments) else {
            throw MellowError.renderFailed
        }
        return weight
    }

    /// image는 작업 색공간(선형) 이미지. 감마로 바꿔 색을 옮기고 선형으로 되돌린다. extent 안만 계산한다.
    func shifted(_ image: CIImage, by shift: ToneShift, extent: CGRect) throws -> CIImage {
        guard let toneShift else { throw MellowError.renderFailed }
        let encoded = image.applyingFilter("CILinearToSRGBToneCurve")
        let arguments: [Any] = [encoded, shift.lift, shift.yellowRemoval, shift.saturation, shift.redness]
        guard let output = toneShift.apply(extent: extent, arguments: arguments) else { throw MellowError.renderFailed }
        return output.applyingFilter("CISRGBToneCurveToLinear")
    }
}
