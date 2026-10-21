import CoreImage
import MellowShared

/// 이중턱 값으로 턱밑 그늘을 밝힌다(스펙 5.7). 모양 워프 앞이라 원본 좌표의 턱밑 띠를 쓴다.
/// doubleChin이 0보다 크고 FaceShapeRig가 이중턱 원소를 만드는 얼굴(doubleChinApplies)만 처리하고 없으면 입력을 그대로 돌려준다.
/// 워프가 접어 올리지 않는 얼굴(옆얼굴·턱 윤곽점 부족)은 그늘도 밝히지 않는다.
/// 마스크는 턱밑 띠(FaceRegions+Chin.swift) × 볼 기준 피부색 가중치라 수염처럼 피부색이 아닌 픽셀은 밝히지 않는다.
/// 감마 BT.601 휘도 L' = L + 값 × chinShadeMaxGain × max(0, R − L)이고 증가는 chinShadeMaxLift에서 자른다.
/// R은 띠 둘레 피부(피부색 가중치 × (1 − 띠))의 넓은 가중 평균 휘도라 그늘을 둘레 피부 밝기 쪽으로 올린다.
/// 색은 휘도 비율로 올려 색조를 지키고 결과는 입력보다 어둡지 않다. 띠 경계 안만 계산해 원본 위에 합성한다.
struct ChinShadeStage: RenderStage {
    let name = "chinShade"

    /// 띠 위끝·아래끝. 아래턱 윤곽에서 얼굴 좌표 아래로 간 거리, 얼굴 폭 비율.
    static let bandTop: CGFloat = 0.03
    static let bandBottom: CGFloat = 0.20
    /// 띠 가로 끝. 입꼬리 x 바깥으로 간 거리, 얼굴 폭 비율.
    static let bandSideMargin: CGFloat = 0.08
    /// 띠 가장자리 흐림 반지름. 얼굴 폭 비율.
    static let bandFeather: CGFloat = 0.03
    /// 둘레 피부 기준 휘도의 흐림 반지름. 얼굴 폭 비율.
    static let referenceRadius: CGFloat = 0.15
    /// 둘레 피부 가중치 합이 이보다 작으면 기준이 없다고 보고 밝히지 않는다.
    private static let minimumCoverage = 0.02
    /// 기준 휘도 흐림이 닿는 거리. 반지름 배수.
    private static let blurReach: CGFloat = 3

    func apply(_ image: CIImage, in context: RenderContext) throws -> CIImage {
        var result = image
        for target in context.faceTargets {
            let raw = target.portrait.face.doubleChin
            let value = AdjustmentRange.clamped(raw.isFinite ? raw : 0, to: AdjustmentRange.faceShape(.doubleChin))
            guard value > 0,
                FaceShapeRig.doubleChinApplies(face: target.face, extent: context.extent, tuning: context.tuning)
            else { continue }
            result = try lift(result, face: target.face, value: value, context: context)
        }
        return result
    }

    private func lift(_ image: CIImage, face: FaceGeometry, value: Double, context: RenderContext) throws -> CIImage {
        let extent = context.extent
        let tuning = context.tuning
        guard
            let band = FaceRegions.chinBandRegion(
                face: face, extent: extent, tuning: tuning, cache: context.regionMasks)
        else { return image }
        let width = FaceRegions.faceWidth(face, extent: extent)
        let radius = max(CGFloat(tuning.skinBlurMinimumRadius), width * Self.referenceRadius)
        let reach = radius * Self.blurReach
        let area = band.bounds.insetBy(dx: -reach, dy: -reach).intersection(extent).integral
        let encoded = image.applyingFilter("CILinearToSRGBToneCurve")
        guard
            let skin = try FaceRegions.chinSkinWeight(
                face: face, encoded: encoded, area: area, extent: extent, tuning: tuning)
        else { return image }
        let black = CIImage(color: .black).cropped(to: extent)
        let skinWeight = skin.composited(over: black).cropped(to: extent)
        let shade = band.image
            .applyingFilter("CIMultiplyCompositing", parameters: [kCIInputBackgroundImageKey: skinWeight])
            .cropped(to: extent)
        let outsideBand = band.image.applyingFilter("CIColorInvert").cropped(to: extent)
        let surround =
            skinWeight
            .applyingFilter("CIMultiplyCompositing", parameters: [kCIInputBackgroundImageKey: outsideBand])
            .cropped(to: extent)
        let wide = FrequencySeparation.maskedMean(encoded, mask: surround, radius: Double(radius))
        let lifted = try ChinShadeKernel.shared.lift(
            encoded: encoded, numerator: wide.numerator, denominator: wide.denominator,
            amount: value * tuning.chinShadeMaxGain, maxLift: tuning.chinShadeMaxLift,
            minimumCoverage: Self.minimumCoverage, extent: band.bounds)
        // 감마 왕복의 반올림이 입력보다 낮아지지 않게 선형에서 입력과의 최댓값을 둔다.
        let brighter = lifted.applyingFilter("CISRGBToneCurveToLinear")
            .applyingFilter("CIMaximumCompositing", parameters: [kCIInputBackgroundImageKey: image])
            .cropped(to: band.bounds)
        return MaskBuilder.blend(brighter, over: image, mask: shade).cropped(to: extent)
    }
}

/// 턱밑 그늘 밝히기 CIKL 색 커널을 감싸는 자리.
private final class ChinShadeKernel: @unchecked Sendable {
    static let shared = ChinShadeKernel()

    private let kernel: CIColorKernel?

    /// 휘도 계수는 BT.601(sRGB 감마 값 기준)이다.
    /// 둘레는 피부 가중 평균(분자 ÷ 분모)이고 분모 하한 0.001은 0으로 나누지 않게 한다.
    /// 가중치 합이 minimumCoverage보다 작으면 둘레 휘도를 0으로 두어 밝히지 않는다.
    /// 세 채널에 같은 배율을 곱해 색조를 지키고 1에서 자르되 입력보다 낮아지지 않는다.
    private init() {
        kernel = CIColorKernel(
            source: """
                kernel vec4 chinLift(__sample pixel, __sample numerator, __sample denominator, float amount,
                                     float maxLift, float minimumCoverage) {
                    vec3 luma = vec3(0.299, 0.587, 0.114);
                    float l = dot(pixel.rgb, luma);
                    float coverage = denominator.r;
                    float surround = dot(numerator.rgb / max(coverage, 0.001), luma) * step(minimumCoverage, coverage);
                    float lift = min(amount * max(surround - l, 0.0), maxLift);
                    float ratio = (l + lift) / max(l, 0.001);
                    return vec4(max(pixel.rgb, min(pixel.rgb * ratio, vec3(1.0))), pixel.a);
                }
                """)
    }

    func lift(
        encoded: CIImage, numerator: CIImage, denominator: CIImage, amount: Double, maxLift: Double,
        minimumCoverage: Double, extent: CGRect
    ) throws -> CIImage {
        guard let kernel else { throw MellowError.renderFailed }
        let arguments: [Any] = [encoded, numerator, denominator, amount, maxLift, minimumCoverage]
        guard let output = kernel.apply(extent: extent, arguments: arguments) else { throw MellowError.renderFailed }
        return output
    }
}
