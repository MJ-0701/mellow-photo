import CoreImage
import Foundation
import MellowShared

@testable import MellowRendering

enum RenderingTestSupport {
    static let renderer = Renderer()

    static func gradient() -> CIImage {
        let filter = CIFilter(
            name: "CILinearGradient",
            parameters: [
                "inputPoint0": CIVector(x: 0, y: 0),
                "inputPoint1": CIVector(x: 128, y: 0),
                "inputColor0": CIColor(red: 0.1, green: 0.2, blue: 0.3),
                "inputColor1": CIColor(red: 0.9, green: 0.6, blue: 0.4),
            ])!
        return filter.outputImage!.cropped(to: CGRect(x: 0, y: 0, width: 128, height: 80))
    }

    static func solid(_ color: CIColor, size: Int = 256) -> CIImage {
        CIImage(color: color).cropped(to: CGRect(x: 0, y: 0, width: size, height: size))
    }

    static func bytes(_ image: CIImage) throws -> [UInt8] {
        let cg = try renderer.makeCGImage(image)
        return Array(cg.dataProvider!.data! as Data)
    }

    static func render(_ image: CIImage, recipe: EditRecipe, faces: [FaceGeometry] = []) throws -> CIImage {
        let context = RenderContext(extent: image.extent, recipe: recipe, faces: faces, tuning: RenderTuning())
        return try RenderPipeline.standard.render(image, context: context)
    }

    static func sharedLookCatalog() throws -> LookCatalog {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("shared/looks/looks.v1.json")
        return try LookCatalog(data: Data(contentsOf: url))
    }

    static func render(_ image: CIImage, recipe: EditRecipe, faces: [FaceGeometry] = [], catalog: LookCatalog) throws
        -> CIImage
    {
        let context = RenderContext(
            extent: image.extent, recipe: recipe, faces: faces, tuning: RenderTuning(), lookCatalog: catalog)
        return try RenderPipeline.standard.render(image, context: context)
    }

    static func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    static func grid(_ image: CIImage) throws -> PixelGrid {
        PixelGrid(try renderer.makeCGImage(image))
    }

    /// 가장자리 폭이 반지름의 2%인 거의 단단한 타원 마스크.
    /// 단위 원을 확대하면 Core Image가 같은 그라데이션을 작은 배율로 한 번 그려 재사용해 큰 타원 가장자리가 흐려진다.
    /// 그래서 가로 반지름 크기로 그리고 세로만 늘린다.
    static func hardEllipse(center: CGPoint, radii: CGSize, extent: CGRect) -> CIImage {
        let gradient = CIFilter(
            name: "CIRadialGradient",
            parameters: [
                "inputCenter": CIVector(x: 0, y: 0), "inputRadius0": 0.98 * radii.width, "inputRadius1": radii.width,
                "inputColor0": CIColor.white, "inputColor1": CIColor.black,
            ])!.outputImage!
        let transform = CGAffineTransform(
            a: 1, b: 0, c: 0, d: radii.height / radii.width, tx: center.x, ty: center.y)
        return gradient.transformed(by: transform).cropped(to: extent)
    }

    /// 피부색 바탕에 모공(픽셀 단위 잡음 ±4%)과 얼룩(흐린 잡음으로 섞은 밝고 어두운 피부)을 넣는다.
    /// CIRandomGenerator는 늘 같은 무늬라 테스트가 결정적이다.
    static func skinTexture(size: Int) -> CIImage {
        let extent = CGRect(x: 0, y: 0, width: size, height: size)
        // CIColorMatrix는 알파로 나눈(비사전곱) 값을 쓴다. 무작위 알파로 나눈 빨강은 1을 크게 넘으므로
        // 나눗셈에 영향받지 않는 알파 채널(0…1 균등)을 회색으로 쓴다.
        let gray = CIFilter(name: "CIRandomGenerator")!.outputImage!.applyingFilter(
            "CIColorMatrix",
            parameters: [
                "inputRVector": CIVector(x: 0, y: 0, z: 0, w: 1), "inputGVector": CIVector(x: 0, y: 0, z: 0, w: 1),
                "inputBVector": CIVector(x: 0, y: 0, z: 0, w: 1), "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 0),
                "inputBiasVector": CIVector(x: 0, y: 0, z: 0, w: 1),
            ])
        let blotch = gray.applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: 8])
            .applyingFilter(
                "CIColorMatrix",
                parameters: [
                    "inputRVector": CIVector(x: 30, y: 0, z: 0, w: 0),
                    "inputGVector": CIVector(x: 0, y: 30, z: 0, w: 0),
                    "inputBVector": CIVector(x: 0, y: 0, z: 30, w: 0),
                    "inputBiasVector": CIVector(x: -14.5, y: -14.5, z: -14.5, w: 0),
                ]
            )
            .applyingFilter(
                "CIColorClamp",
                parameters: [
                    "inputMinComponents": CIVector(x: 0, y: 0, z: 0, w: 0),
                    "inputMaxComponents": CIVector(x: 1, y: 1, z: 1, w: 1),
                ])
        let light = CIImage(color: CIColor(red: 0.84, green: 0.66, blue: 0.56))
        let dark = CIImage(color: CIColor(red: 0.74, green: 0.56, blue: 0.46))
        let base = light.applyingFilter(
            "CIBlendWithMask", parameters: [kCIInputBackgroundImageKey: dark, kCIInputMaskImageKey: blotch])
        let bright = base.applyingFilter(
            "CIColorMatrix",
            parameters: [
                "inputRVector": CIVector(x: 1.04, y: 0, z: 0, w: 0),
                "inputGVector": CIVector(x: 0, y: 1.04, z: 0, w: 0),
                "inputBVector": CIVector(x: 0, y: 0, z: 1.04, w: 0),
            ])
        let dim = base.applyingFilter(
            "CIColorMatrix",
            parameters: [
                "inputRVector": CIVector(x: 0.96, y: 0, z: 0, w: 0),
                "inputGVector": CIVector(x: 0, y: 0.96, z: 0, w: 0),
                "inputBVector": CIVector(x: 0, y: 0, z: 0.96, w: 0),
            ])
        return bright.applyingFilter(
            "CIBlendWithMask", parameters: [kCIInputBackgroundImageKey: dim, kCIInputMaskImageKey: gray]
        ).cropped(to: extent)
    }
}

/// CGImage 바이트를 Core Image 좌표(원점 왼쪽 아래)로 읽는다. 행 끝 여백(bytesPerRow)을 고려한다.
struct PixelGrid {
    let width: Int
    let height: Int
    let bytesPerRow: Int
    let data: [UInt8]

    init(_ image: CGImage) {
        width = image.width
        height = image.height
        bytesPerRow = image.bytesPerRow
        data = Array(image.dataProvider!.data! as Data)
    }

    /// CGImage는 맨 위 행부터 저장한다.
    func rgba(_ point: CGPoint) -> [UInt8] {
        let x = Int(point.x)
        let y = Int(point.y)
        let offset = (height - 1 - y) * bytesPerRow + x * 4
        return Array(data[offset..<(offset + 4)])
    }

    func red(_ point: CGPoint) -> UInt8 { rgba(point)[0] }
}

/// 512×512 합성 얼굴. 좌표는 Core Image 픽셀이고 원점은 왼쪽 아래다.
/// 윤곽(가로 반지름 172)은 피부 타원(140)보다 넓어 윤곽 안에 파란 배경이 들어간다.
struct SyntheticFace {
    static let size = 512
    static let skinCenter = CGPoint(x: 256, y: 240)
    static let skinRadii = CGSize(width: 140, height: 190)
    static let contourRadii = CGSize(width: 172, height: 190)
    static let leftEye = CGPoint(x: 200, y: 300)
    static let rightEye = CGPoint(x: 312, y: 300)
    static let eyeRadii = CGSize(width: 28, height: 14)
    static let leftBrow = CGRect(x: 168, y: 332, width: 64, height: 12)
    static let rightBrow = CGRect(x: 280, y: 332, width: 64, height: 12)
    static let mouth = CGPoint(x: 256, y: 140)
    static let mouthRadii = CGSize(width: 48, height: 20)
    static let innerMouthRadii = CGSize(width: 40, height: 8)
    static let nose = [CGPoint(x: 236, y: 190), CGPoint(x: 276, y: 190), CGPoint(x: 256, y: 250)]
    static let box = CGRect(x: 116, y: 50, width: 280, height: 300)
    /// 피부 위 잡티 다섯 개의 중심.
    static let blemishes = [
        CGPoint(x: 176, y: 224), CGPoint(x: 336, y: 224), CGPoint(x: 216, y: 372), CGPoint(x: 300, y: 376),
        CGPoint(x: 256, y: 84),
    ]
    /// 눈 바로 아래(보호 영역 안)의 잡티. 검출되면 안 된다.
    static let blemishNearEye = CGPoint(x: 200, y: 278)
    static let blemishRadius: CGFloat = 3.5
    static let cheek = CGPoint(x: 180, y: 200)
    static let forehead = CGPoint(x: 256, y: 380)
    static let backgroundInsideContour = CGPoint(x: 96, y: 240)
    static let outside = CGPoint(x: 20, y: 20)
    /// 잡티·특징에서 떨어진 볼 안쪽 정사각형. 대역 분산을 잰다.
    static let skinPatch = CGRect(x: 150, y: 190, width: 60, height: 60)

    let image: CIImage
    let face: FaceGeometry

    static var extent: CGRect { CGRect(x: 0, y: 0, width: size, height: size) }

    static func make(withBlemishes: Bool = false, landmarks: Bool = true) -> SyntheticFace {
        let backgroundColor = CIColor(red: 0.2, green: 0.35, blue: 0.75)
        var image = CIImage(color: backgroundColor).cropped(to: extent)
        let skinMask = RenderingTestSupport.hardEllipse(center: skinCenter, radii: skinRadii, extent: extent)
        image = RenderingTestSupport.skinTexture(size: size).applyingFilter(
            "CIBlendWithMask", parameters: [kCIInputBackgroundImageKey: image, kCIInputMaskImageKey: skinMask])
        let eyeColor = CIImage(color: CIColor(red: 0.12, green: 0.09, blue: 0.08))
        for eye in [leftEye, rightEye] {
            image = paint(eyeColor, center: eye, radii: eyeRadii, over: image)
        }
        let browColor = CIImage(color: CIColor(red: 0.25, green: 0.18, blue: 0.14))
        for brow in [leftBrow, rightBrow] {
            image = browColor.cropped(to: brow).composited(over: image)
        }
        let lipColor = CIImage(color: CIColor(red: 0.72, green: 0.28, blue: 0.32))
        image = paint(lipColor, center: mouth, radii: mouthRadii, over: image)
        if withBlemishes {
            // 피부보다 휘도 40% 낮고 Cr이 0.026 높다. 피부색 가중치(σ 0.04) 안이라 마스크에 남는다.
            let spotColor = CIImage(color: CIColor(red: 0.56, green: 0.32, blue: 0.27))
            let radii = CGSize(width: blemishRadius, height: blemishRadius)
            for center in blemishes + [blemishNearEye] {
                image = paint(spotColor, center: center, radii: radii, over: image)
            }
        }
        let face = landmarks ? geometry() : FaceGeometry(boundingBox: normalized(box))
        return SyntheticFace(image: image.cropped(to: extent), face: face)
    }

    private static func paint(_ color: CIImage, center: CGPoint, radii: CGSize, over image: CIImage) -> CIImage {
        let mask = RenderingTestSupport.hardEllipse(center: center, radii: radii, extent: extent)
        return color.applyingFilter(
            "CIBlendWithMask", parameters: [kCIInputBackgroundImageKey: image, kCIInputMaskImageKey: mask]
        ).cropped(to: extent)
    }

    private static func normalized(_ point: CGPoint) -> NormalizedPoint {
        NormalizedPoint(x: Double(point.x) / Double(size), y: Double(point.y) / Double(size))
    }

    private static func normalized(_ rect: CGRect) -> NormalizedRect {
        NormalizedRect(
            x: Double(rect.minX) / Double(size), y: Double(rect.minY) / Double(size),
            width: Double(rect.width) / Double(size), height: Double(rect.height) / Double(size))
    }

    private static func ellipse(_ center: CGPoint, _ radii: CGSize) -> [NormalizedPoint] {
        (0..<12).map { step in
            let angle = 2 * Double.pi * Double(step) / 12
            return normalized(
                CGPoint(
                    x: center.x + radii.width * CGFloat(cos(angle)), y: center.y + radii.height * CGFloat(sin(angle))))
        }
    }

    private static func corners(_ rect: CGRect) -> [NormalizedPoint] {
        [
            CGPoint(x: rect.minX, y: rect.minY), CGPoint(x: rect.maxX, y: rect.minY),
            CGPoint(x: rect.maxX, y: rect.maxY), CGPoint(x: rect.minX, y: rect.maxY),
        ].map(normalized)
    }

    /// Vision처럼 윤곽은 한쪽 관자놀이에서 턱을 지나 반대쪽까지 17점이다.
    private static func geometry() -> FaceGeometry {
        let contour = (0...16).map { step -> NormalizedPoint in
            let angle = Double.pi + Double.pi * Double(step) / 16
            return normalized(
                CGPoint(
                    x: skinCenter.x + contourRadii.width * CGFloat(cos(angle)),
                    y: skinCenter.y + contourRadii.height * CGFloat(sin(angle))))
        }
        return FaceGeometry(
            boundingBox: normalized(box),
            landmarks: [
                .faceContour: contour, .leftEye: ellipse(leftEye, eyeRadii), .rightEye: ellipse(rightEye, eyeRadii),
                .leftEyebrow: corners(leftBrow), .rightEyebrow: corners(rightBrow),
                .outerLips: ellipse(mouth, mouthRadii), .innerLips: ellipse(mouth, innerMouthRadii),
                .nose: nose.map(normalized), .leftPupil: [normalized(leftEye)], .rightPupil: [normalized(rightEye)],
            ])
    }
}
