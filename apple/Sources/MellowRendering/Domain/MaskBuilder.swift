import CoreImage

enum MaskBuilder {
    /// 이 비율까지는 strength를 그대로 유지한다.
    private static let solidRadius = 0.65
    /// 이 비율에서 0이 된다. 타원의 가장자리.
    private static let fadeRadius = 1.0

    /// 중심 0.65까지 strength, 가장자리 1.0에서 0으로 떨어지는 타원.
    static func ellipse(_ rect: CGRect, extent: CGRect, strength: Double = 1) -> CIImage {
        let gradient = CIFilter(
            name: "CIRadialGradient",
            parameters: [
                "inputCenter": CIVector(x: 0, y: 0),
                "inputRadius0": solidRadius,
                "inputRadius1": fadeRadius,
                "inputColor0": CIColor(red: strength, green: strength, blue: strength),
                "inputColor1": CIColor.black,
            ])!.outputImage!
        let transform = CGAffineTransform(
            a: max(1, rect.width / 2), b: 0, c: 0, d: max(1, rect.height / 2), tx: rect.midX, ty: rect.midY)
        return gradient.transformed(by: transform).cropped(to: extent)
    }

    static func blend(_ foreground: CIImage, over background: CIImage, mask: CIImage) -> CIImage {
        foreground.applyingFilter(
            "CIBlendWithMask", parameters: [kCIInputBackgroundImageKey: background, kCIInputMaskImageKey: mask])
    }
}
