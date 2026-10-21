import CoreImage
import MellowShared

/// 피부 보정의 CIKL 색 커널을 감싸는 유일한 자리. WarpKernel처럼 Metal로 바꿀 때 이 타입만 바꾼다.
final class SkinKernels: @unchecked Sendable {
    static let shared = SkinKernels()

    private let chroma: CIColorKernel?
    private let bands: CIColorKernel?
    private let fold: CIColorKernel?
    private let tone: CIColorKernel?
    private let blush: CIColorKernel?
    private let healing: CIColorKernel?
    private let spotCorrection: CIColorKernel?
    private let spotBlend: CIColorKernel?

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
        // 휘도 계수는 BT.601이다.
        // 주변은 피부 마스크 가중 평균(분자 ÷ 분모)이라 눈·눈썹·입술·머리카락이 섞이지 않는다.
        // 분모 하한 0.001은 둘레가 전부 보호 영역일 때 0으로 나누지 않게 한다.
        // 피부 가중치 합이 minimumCoverage보다 작으면 주변 휘도를 0으로 두어 gap이 0, 배율이 1이 된다.
        // 세 채널에 같은 배율을 곱해 그늘의 색조·채도를 지킨다(같은 값을 더하면 회색 쪽으로 간다).
        fold = CIColorKernel(
            source: """
                kernel vec4 foldLift(__sample image, __sample low, __sample wideNumerator, __sample wideDenominator,
                                     float amount, float maxGain, float lumaFloor, float minimumCoverage) {
                    vec3 luma = vec3(0.299, 0.587, 0.114);
                    float lowLuma = dot(low.rgb, luma);
                    float coverage = max(wideDenominator.r, 0.001);
                    float surroundLuma = dot(wideNumerator.rgb / coverage, luma) * step(minimumCoverage, wideDenominator.r);
                    float gap = max(surroundLuma - lowLuma, 0.0);
                    float gain = min(1.0 + amount * gap / max(lowLuma, lumaFloor), maxGain);
                    return vec4(image.rgb * gain, image.a);
                }
                """)
        // luma는 BT.709 선형 휘도 계수다. 분모 하한 0.001은 마스크 밖(가중치 0)에서 0으로 나누지 않게 한다.
        // 작은 반사광은 대부분 중간 대역에 있어 번들거림 가중치만큼 중간 대역도 줄인다. 모공 대역은 그대로다.
        tone = CIColorKernel(
            source: """
                kernel vec4 toneMix(__sample image, __sample fineBlur, __sample midBlur, __sample wideNumerator,
                                    __sample wideDenominator, __sample reference, float keep, float even,
                                    float shine, float shineOffset, float shineRamp) {
                    vec3 luma = vec3(0.2126, 0.7152, 0.0722);
                    vec3 wide = wideNumerator.rgb / max(wideDenominator.r, 0.001);
                    float gloss = clamp((dot(image.rgb, luma) - dot(reference.rgb, luma) - shineOffset) / shineRamp,
                                        0.0, 1.0);
                    float pull = max(even, shine * gloss);
                    vec3 low = mix(midBlur.rgb, wide, pull);
                    vec3 mid = (fineBlur.rgb - midBlur.rgb) * (1.0 - shine * gloss);
                    vec3 fine = image.rgb - fineBlur.rgb;
                    return vec4(low + mid * keep + fine, image.a);
                }
                """)
        // Y·Cb·Cr 계수와 역변환 계수는 BT.601(sRGB 감마 값 기준)이다.
        blush = CIColorKernel(
            source: """
                kernel vec4 skinRedness(__sample pixel, __sample reference, float clear, float flush,
                                        float referenceOffset) {
                    vec3 yv = vec3(0.299, 0.587, 0.114);
                    vec3 cbv = vec3(-0.168736, -0.331264, 0.5);
                    vec3 crv = vec3(0.5, -0.418688, -0.081312);
                    float y = dot(pixel.rgb, yv);
                    float cb = dot(pixel.rgb, cbv);
                    float cr = dot(pixel.rgb, crv);
                    float excess = max(cr - (dot(reference.rgb, crv) - referenceOffset), 0.0);
                    cr = cr - excess * clear + flush;
                    vec3 rgb = vec3(y + 1.402 * cr, y - 0.344136 * cb - 0.714136 * cr, y + 1.772 * cb);
                    return vec4(clamp(rgb, 0.0, 1.0), pixel.a);
                }
                """)
        // 채널별 배율 = 고리 평균 ÷ 원본 저주파.
        // 분모 하한 0.001은 고리 가중치가 0인 곳(extent 밖)에서 0으로 나누지 않게 한다.
        healing = CIColorKernel(
            source: """
                kernel vec4 healTone(__sample source, __sample sourceLow, __sample ringNumerator,
                                     __sample ringDenominator, float floorValue, float maxGain) {
                    vec3 ring = ringNumerator.rgb / max(ringDenominator.r, 0.001);
                    vec3 gain = clamp(ring / max(sourceLow.rgb, vec3(floorValue)), vec3(1.0 / maxGain), vec3(maxGain));
                    return vec4(source.rgb * gain, source.a);
                }
                """)
        // luma는 BT.709 선형 휘도 계수다.
        // dark = 닫힘(점) − 닫힘(모공), bright = 열림(모공) − 열림(점)이라 모공 크기 명암은 빠진다.
        // 상대 깊이 = 휘도 차이 ÷ max(닫힘(모공) 휘도, floorLuma).
        // 가중치는 start…end에서 0 → 1로 오르고 capStart…capEnd에서 1 → 0으로 내린다(깊은 구조는 점이 아니다).
        spotCorrection = CIColorKernel(
            source: """
                kernel vec4 spotCorrection(__sample darkFill, __sample darkPore, __sample brightCut,
                                           __sample brightPore, float start, float end, float capStart,
                                           float capEnd, float floorLuma, float brightAmount) {
                    vec3 luma = vec3(0.2126, 0.7152, 0.0722);
                    vec3 dark = max(darkFill.rgb - darkPore.rgb, vec3(0.0));
                    vec3 bright = max(brightPore.rgb - brightCut.rgb, vec3(0.0));
                    float base = max(dot(darkPore.rgb, luma), floorLuma);
                    float depth = dot(dark, luma) / base;
                    float height = dot(bright, luma) / base;
                    float wd = smoothstep(start, end, depth) * (1.0 - smoothstep(capStart, capEnd, depth));
                    float wb = smoothstep(start, end, height) * (1.0 - smoothstep(capStart, capEnd, height));
                    return vec4(dark * wd - bright * wb * brightAmount, 1.0);
                }
                """)
        spotBlend = CIColorKernel(
            source: """
                kernel vec4 spotApply(__sample image, __sample correction, __sample mask, float amount) {
                    return vec4(image.rgb + correction.rgb * mask.r * amount, image.a);
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

    /// 주름 밝히기의 주변 피부 가중치 합 하한.
    /// 띠 둘레 피부 가중치 합(넓은 흐림의 분모)이 2%보다 작으면 기준이 없다고 보고 밝히지 않는다.
    static let foldMinimumCoverage = 0.02

    /// 주변 피부 평균(wideNumerator ÷ wideDenominator)이 국소 저주파(low)보다 밝은 휘도(BT.601) 비율만큼 세 채널에 같은 배율을 곱한다.
    /// 배율 = min(1 + amount × 휘도 차이 ÷ max(국소 휘도, lumaFloor), maxGain). 둘레가 어두우면 배율 1이다.
    /// 피부 가중치 합이 foldMinimumCoverage보다 작으면 배율 1이다.
    /// lumaFloor가 0 이하이거나 maxGain이 1보다 작으면(어둡게 만드는 상한) 렌더 실패다.
    func foldLift(
        image: CIImage, low: CIImage, wideNumerator: CIImage, wideDenominator: CIImage, amount: Double,
        maxGain: Double, lumaFloor: Double, extent: CGRect
    ) throws -> CIImage {
        guard let fold, lumaFloor > 0, maxGain >= 1 else { throw MellowError.renderFailed }
        let arguments: [Any] = [
            image, low, wideNumerator, wideDenominator, amount, maxGain, lumaFloor, Self.foldMinimumCoverage,
        ]
        guard let lifted = fold.apply(extent: extent, arguments: arguments) else { throw MellowError.renderFailed }
        return lifted
    }

    /// low = mix(midBlur, 마스크 가중 넓은 평균, max(even, shine × 번들거림 가중치)). mid는 (1 − shine × 가중치)배다.
    /// 번들거림 가중치는 선형 휘도(BT.709)가 reference보다 shineOffset 이상 밝은 곳에서 shineRamp에 걸쳐 0 → 1.
    /// shine이 0이면 mid는 bandMix와 같고 fine(모공)은 언제나 그대로다.
    func toneMix(
        image: CIImage, fineBlur: CIImage, midBlur: CIImage, wideNumerator: CIImage, wideDenominator: CIImage,
        reference: CIImage, keep: Double, even: Double, shine: Double, shineOffset: Double, shineRamp: Double,
        extent: CGRect
    ) throws -> CIImage {
        guard let tone, shineRamp > 0 else { throw MellowError.renderFailed }
        let arguments: [Any] = [
            image, fineBlur, midBlur, wideNumerator, wideDenominator, reference, keep, even, shine, shineOffset,
            shineRamp,
        ]
        guard let mixed = tone.apply(extent: extent, arguments: arguments) else { throw MellowError.renderFailed }
        return mixed
    }

    /// encoded는 sRGB 감마 이미지, reference는 볼 기준 평균(감마, 무한 확장).
    /// 기준 Cr(볼 평균 − referenceOffset)을 넘는 만큼 × clear를 빼고 flush를 더한다.
    func redness(
        encoded: CIImage, reference: CIImage, clear: Double, flush: Double, referenceOffset: Double, extent: CGRect
    ) throws -> CIImage {
        guard let blush else { throw MellowError.renderFailed }
        let arguments: [Any] = [encoded, reference, clear, flush, referenceOffset]
        guard let shifted = blush.apply(extent: extent, arguments: arguments) else { throw MellowError.renderFailed }
        return shifted
    }

    /// 원본 패치 S × (고리 평균 ÷ S 저주파), 채널별, 배율 1/maxGain…maxGain.
    /// 원본의 고주파(질감)는 비율로 옮겨지고 저주파(밝기·색)는 대상 둘레 고리 평균이 된다.
    /// lumaFloor가 0 이하이거나 maxGain이 1보다 작으면 렌더 실패다.
    func heal(
        source: CIImage, sourceLow: CIImage, ringNumerator: CIImage, ringDenominator: CIImage, lumaFloor: Double,
        maxGain: Double, extent: CGRect
    ) throws -> CIImage {
        guard let healing, lumaFloor > 0, maxGain >= 1 else { throw MellowError.renderFailed }
        let arguments: [Any] = [source, sourceLow, ringNumerator, ringDenominator, lumaFloor, maxGain]
        guard let healed = healing.apply(extent: extent, arguments: arguments) else { throw MellowError.renderFailed }
        return healed
    }

    /// 점 지우기 보정 지도(스펙 G5 4.3).
    /// 어두운 점은 더하고 밝은 점은 brightAmount배로 빼는 선형 RGB 차이다(음수 가능).
    /// brightAmount 0이면 어두운 점만 채운다.
    /// start < end, capStart < capEnd, lumaFloor > 0이 아니면 렌더 실패다.
    func spot(
        darkFill: CIImage, darkPore: CIImage, brightCut: CIImage, brightPore: CIImage, start: Double, end: Double,
        capStart: Double, capEnd: Double, lumaFloor: Double, brightAmount: Double, extent: CGRect
    ) throws -> CIImage {
        guard let spotCorrection, start < end, capStart < capEnd, lumaFloor > 0 else { throw MellowError.renderFailed }
        let images: [Any] = [darkFill, darkPore, brightCut, brightPore]
        let limits: [Any] = [start, end, capStart, capEnd, lumaFloor, brightAmount]
        guard let correction = spotCorrection.apply(extent: extent, arguments: images + limits) else {
            throw MellowError.renderFailed
        }
        return correction
    }

    /// image.rgb + correction.rgb × mask.r × amount.
    /// 알파는 image 그대로다.
    func spotApply(image: CIImage, correction: CIImage, mask: CIImage, amount: Double, extent: CGRect) throws
        -> CIImage
    {
        guard let spotBlend else { throw MellowError.renderFailed }
        let arguments: [Any] = [image, correction, mask, amount]
        guard let applied = spotBlend.apply(extent: extent, arguments: arguments) else {
            throw MellowError.renderFailed
        }
        return applied
    }
}
