import CoreImage
import MellowShared

/// 모공보다 크고 얼굴 폭 2.4%보다 작은 어두운·밝은 점을 닫힘·열림 차이로 채운다(스펙 G5 4절).
/// 모공 크기 명암은 차이에서 빠져 남고, 상대 깊이가 cap보다 깊은 구조(콧구멍·눈꼬리)는 건드리지 않는다.
/// 강도는 깊이 시작 문턱을 움직이고(1에서 spotDepthStart, 0에서 spotDepthStartWeak) 문턱을 넘은 점은 완전히 채운다.
enum SpotRemoval {
    private static let dilate = "CIMorphologyMaximum"
    private static let erode = "CIMorphologyMinimum"

    /// 강도의 깊이 문턱(시작·끝)과 채움 비율.
    static func thresholds(strength: Double, tuning: RenderTuning) -> (start: Double, end: Double, fill: Double) {
        let amount = min(1, max(0, strength))
        let span: Double = tuning.spotDepthStart - tuning.spotDepthStartWeak
        let start: Double = tuning.spotDepthStartWeak + span * amount
        let fill: Double = min(1, amount / tuning.spotFullFillStrength)
        return (start, start + tuning.spotDepthRamp, fill)
    }

    /// 한 얼굴의 점 지우기.
    /// 얼굴 마스크 영역(maskBounds) 밖은 image 그대로다.
    /// skinMask는 SkinStage가 만든 세기 1 피부 마스크다.
    static func apply(
        _ image: CIImage, face: FaceGeometry, skinMask: CIImage, faceWidth: CGFloat, amount: Double,
        tuning: RenderTuning, extent: CGRect, cache: RegionMaskCache?
    ) throws -> CIImage {
        guard amount > 0 else { return image }
        let bounds = FaceRegions.maskBounds(face: face, extent: extent, tuning: tuning).intersection(extent)
        guard !bounds.isEmpty else { return image }
        let width = Double(faceWidth)
        // 형태 필터는 반지름을 정수로 내림하고 1픽셀 아래는 아무것도 하지 않는다.
        // 올림해야 모공 크기 명암이 닫힘(모공)에 들어가 차이에서 빠진다.
        let minimum = tuning.spotMorphologyMinimumRadius
        let spot: Double = max(minimum, (width * tuning.spotRadiusFraction).rounded(.up))
        let pore: Double = max(minimum, (width * tuning.spotPoreRadiusFraction).rounded(.up))
        // 형태 필터 입력은 가장자리 여유를 둔 유한 영역이다.
        // 무한 extent를 넣으면 영역 밖이 늘어난 픽셀이 된다.
        let padding = CGFloat(spot * tuning.spotMorphologyPaddingInSpots)
        let source = image.clampedToExtent().cropped(to: bounds.insetBy(dx: -padding, dy: -padding))
        func morphology(_ first: String, _ second: String, _ radius: Double) -> CIImage {
            source.applyingFilter(first, parameters: [kCIInputRadiusKey: radius])
                .applyingFilter(second, parameters: [kCIInputRadiusKey: radius]).cropped(to: bounds)
        }
        let limits = thresholds(strength: amount, tuning: tuning)
        let correction = try SkinKernels.shared.spot(
            darkFill: morphology(dilate, erode, spot), darkPore: morphology(dilate, erode, pore),
            brightCut: morphology(erode, dilate, spot), brightPore: morphology(erode, dilate, pore),
            start: limits.start, end: limits.end, capStart: tuning.spotDepthCapStart, capEnd: tuning.spotDepthCapEnd,
            lumaFloor: tuning.spotLumaFloor, extent: bounds)
        // 보정 지도를 중간 결과로 굳혀 뒤의 흐림·합성이 형태 필터 그래프를 다시 펼치지 않게 한다.
        let baked = correction.insertingIntermediate()
        let blurRadius: Double = pore * tuning.spotCorrectionBlurInPores
        let smoothed = baked.clampedToExtent()
            .applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: blurRadius])
        let mask = FaceRegions.spotMask(face: face, skinMask: skinMask, extent: extent, tuning: tuning, cache: cache)
        // 커널에는 bounds로 자른 이미지를 넘긴다.
        // 자르지 않은 이미지를 커널과 바탕(composited over)에 함께 쓰면 Core Image가 바탕까지 bounds 가장자리를 늘린 픽셀로 그린다.
        let fixed = try SkinKernels.shared.spotApply(
            image: image.cropped(to: bounds), correction: smoothed, mask: mask, amount: limits.fill, extent: bounds)
        return fixed.composited(over: image).cropped(to: extent)
    }
}
