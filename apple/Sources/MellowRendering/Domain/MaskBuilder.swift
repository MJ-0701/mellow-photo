import CoreImage

enum MaskBuilder {
    /// 이 비율까지는 strength를 그대로 유지한다.
    private static let solidRadius = 0.65
    /// 이 비율에서 0이 된다. 타원의 가장자리.
    private static let fadeRadius = 1.0

    /// 중심 0.65까지 strength, 가장자리 1.0에서 0으로 떨어지는 타원.
    /// 단위 원을 확대하면 Core Image가 같은 그라데이션을 한 번 그려 크기가 다른 타원끼리 재사용하므로
    /// 큰 타원이 뭉개진다. 그래서 가로 반지름 픽셀 크기로 그리고 세로만 늘린다.
    static func ellipse(_ rect: CGRect, extent: CGRect, strength: Double = 1) -> CIImage {
        unbounded(rect, strength: strength).cropped(to: extent)
    }

    /// center 둘레로 angle(라디안, 반시계)만큼 돌린 타원. radii.width가 돌린 x축 방향 반지름이고 경계 모양은 ellipse와 같다.
    static func ellipse(center: CGPoint, radii: CGSize, angle: CGFloat, extent: CGRect, strength: Double = 1)
        -> CIImage
    {
        let rect = CGRect(
            x: center.x - radii.width, y: center.y - radii.height, width: radii.width * 2, height: radii.height * 2)
        let turn = CGAffineTransform(translationX: center.x, y: center.y).rotated(by: angle)
            .translatedBy(x: -center.x, y: -center.y)
        return unbounded(rect, strength: strength).transformed(by: turn).cropped(to: extent)
    }

    /// 자르지 않은 타원. 반지름 밖은 검정(0)이다.
    private static func unbounded(_ rect: CGRect, strength: Double) -> CIImage {
        let radiusX = max(1, rect.width / 2)
        let radiusY = max(1, rect.height / 2)
        let gradient = CIFilter(
            name: "CIRadialGradient",
            parameters: [
                "inputCenter": CIVector(x: rect.midX, y: rect.midY),
                "inputRadius0": solidRadius * radiusX,
                "inputRadius1": fadeRadius * radiusX,
                "inputColor0": CIColor(red: strength, green: strength, blue: strength),
                "inputColor1": CIColor.black,
            ])!.outputImage!
        let stretch = CGAffineTransform(translationX: rect.midX, y: rect.midY)
            .scaledBy(x: 1, y: radiusY / radiusX)
            .translatedBy(x: -rect.midX, y: -rect.midY)
        return gradient.transformed(by: stretch)
    }

    static func blend(_ foreground: CIImage, over background: CIImage, mask: CIImage) -> CIImage {
        foreground.applyingFilter(
            "CIBlendWithMask", parameters: [kCIInputBackgroundImageKey: background, kCIInputMaskImageKey: mask])
    }
}
