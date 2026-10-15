import CoreImage
import MellowShared

/// 피부 보정의 CIKL 색 커널을 감싸는 유일한 자리. WarpKernel처럼 Metal로 바꿀 때 이 타입만 바꾼다.
final class SkinKernels: @unchecked Sendable {
    static let shared = SkinKernels()

    private let chroma: CIColorKernel?

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
}
