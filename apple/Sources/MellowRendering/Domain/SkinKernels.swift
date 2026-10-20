import CoreImage
import MellowShared

/// 피부 보정의 CIKL 색 커널을 감싸는 유일한 자리. WarpKernel처럼 Metal로 바꿀 때 이 타입만 바꾼다.
final class SkinKernels: @unchecked Sendable {
    static let shared = SkinKernels()

    private let chroma: CIColorKernel?
    private let bands: CIColorKernel?
    private let fold: CIColorKernel?

    /// Cb·Cr 계수는 BT.601(sRGB 감마 값 기준)이다. 거리 t = d²/σ², 가중치 = clamp((4 − t)/3)이라 d ≤ σ면 1, d = 2σ면 0.
    private init() {
        chroma = CIColorKernel(
            source: """
                kernel vec4 skinChromaWeight(__sample pixel, __sample left, __sample right, float invSigmaSquared) {
                    vec3 cb = vec3(-0.168736, -0.331264, 0.5);
                    vec3 cr = vec3(0.5, -0.418688, -0.081312);
                    vec3 reference = (left.rgb + right.rgb) * 0.5;
                    vec2 d = vec2(dot(pixel.rgb - reference, cb), dot(pixel.rgb - reference, cr));
                    float t = dot(d, d) * invSigmaSquared;
                    float w = clamp((4.0 - t) / 3.0, 0.0, 1.0);
                    return vec4(w, w, w, 1.0);
                }
                """)
        bands = CIColorKernel(
            source: """
                kernel vec4 bandMix(__sample image, __sample fineBlur, __sample midBlur, float keep) {
                    vec3 mid = fineBlur.rgb - midBlur.rgb;
                    vec3 fine = image.rgb - fineBlur.rgb;
                    return vec4(midBlur.rgb + mid * keep + fine, image.a);
                }
                """)
        fold = CIColorKernel(
            source: """
                kernel vec4 foldLift(__sample image, __sample low, __sample surround, float amount) {
                    vec3 gap = max(surround.rgb - low.rgb, vec3(0.0));
                    return vec4(image.rgb + gap * amount, image.a);
                }
                """)
    }

    /// encoded는 sRGB 감마 값 이미지, left·right는 볼 평균을 무한 확장한 이미지. 결과는 회색 가중치.
    func chromaWeight(of encoded: CIImage, left: CIImage, right: CIImage, sigma: Double, extent: CGRect) throws
        -> CIImage
    {
        guard let chroma, sigma > 0 else { throw MellowError.renderFailed }
        let arguments: [Any] = [encoded, left, right, 1 / (sigma * sigma)]
        guard let weight = chroma.apply(extent: extent, arguments: arguments) else { throw MellowError.renderFailed }
        return weight
    }

    /// low + mid × keep + fine. low = blur(r2), mid = blur(r1) − blur(r2), fine = 원본 − blur(r1).
    func bandMix(image: CIImage, fineBlur: CIImage, midBlur: CIImage, keep: Double, extent: CGRect) throws -> CIImage {
        guard let bands else { throw MellowError.renderFailed }
        let arguments: [Any] = [image, fineBlur, midBlur, keep]
        guard let mixed = bands.apply(extent: extent, arguments: arguments) else { throw MellowError.renderFailed }
        return mixed
    }

    /// 주변 평균(surround)이 국소 저주파(low)보다 밝은 만큼만 amount 비율로 더한다. 모공 대역은 더하는 항에 없어 그대로다.
    func foldLift(image: CIImage, low: CIImage, surround: CIImage, amount: Double, extent: CGRect) throws -> CIImage {
        guard let fold else { throw MellowError.renderFailed }
        let arguments: [Any] = [image, low, surround, amount]
        guard let lifted = fold.apply(extent: extent, arguments: arguments) else { throw MellowError.renderFailed }
        return lifted
    }
}
