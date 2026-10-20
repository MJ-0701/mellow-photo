import CoreImage
import Foundation
import ImageIO
import MellowShared
import XCTest

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

    static func sharedMakeupCatalog() throws -> MakeupCatalog {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("shared/makeup/makeup.v1.json")
        return try MakeupCatalog(data: Data(contentsOf: url))
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

    static func writePNG(_ image: CIImage, name: String = "image") throws -> URL {
        let url = try temporaryDirectory().appendingPathComponent("\(name).png")
        let cg = try renderer.makeCGImage(image)
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil) else {
            throw MellowError.cannotWriteToFolder
        }
        CGImageDestinationAddImage(destination, cg, nil)
        guard CGImageDestinationFinalize(destination) else { throw MellowError.cannotWriteToFolder }
        return url
    }

    static func grid(_ image: CIImage) throws -> PixelGrid {
        PixelGrid(try renderer.makeCGImage(image))
    }

    /// 두 격자가 다른 픽셀 수를 왼쪽 절반·오른쪽 절반으로 나눠 센다.
    /// 격자 크기는 같아야 한다.
    static func changedPixelsByHalf(_ before: PixelGrid, _ after: PixelGrid) -> (left: Int, right: Int) {
        var left = 0
        var right = 0
        for y in 0..<before.height {
            for x in 0..<before.width {
                let point = CGPoint(x: x, y: y)
                guard after.rgba(point) != before.rgba(point) else { continue }
                if x < before.width / 2 {
                    left += 1
                } else {
                    right += 1
                }
            }
        }
        return (left, right)
    }

    /// rect 안 휘도(선형 sRGB)의 대역별 분산. fine = 원본 − blur(r1), mid = blur(r1) − blur(r2).
    static func bandVariances(_ image: CIImage, in rect: CGRect, fineRadius: Double, midRadius: Double) throws
        -> (fine: Double, mid: Double)
    {
        let original = try luma(image.cropped(to: rect))
        let fineBlur = try luma(FrequencySeparation.blurred(image, radius: fineRadius).cropped(to: rect))
        let midBlur = try luma(FrequencySeparation.blurred(image, radius: midRadius).cropped(to: rect))
        let fine = zip(original, fineBlur).map { $0 - $1 }
        let mid = zip(fineBlur, midBlur).map { $0 - $1 }
        return (variance(fine), variance(mid))
    }

    static func luma(_ image: CIImage) throws -> [Double] {
        let pixels = try renderer.readPixels(image)
        return stride(from: 0, to: pixels.count, by: 4).map { index in
            0.2126 * Double(pixels[index]) + 0.7152 * Double(pixels[index + 1]) + 0.0722 * Double(pixels[index + 2])
        }
    }

    static func variance(_ values: [Double]) -> Double {
        guard !values.isEmpty else { return 0 }
        let mean = values.reduce(0, +) / Double(values.count)
        return values.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / Double(values.count)
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

    /// 검은 바탕에 흰 사각형 사람이 있는 인물 마스크. size는 마스크 크기, person은 마스크 안 사람 사각형(픽셀).
    static func personMask(size: CGSize, person: CGRect) -> CIImage {
        let extent = CGRect(origin: .zero, size: size)
        return CIImage(color: .white).cropped(to: person).composited(over: CIImage(color: .black)).cropped(to: extent)
    }

    /// 체형 테스트의 기본 사람 자리. 512 정사각형에서 어깨 폭 204.8px, 엉덩이 y 256, 발목 y 25.6.
    static let standingBox = NormalizedRect(x: 0.1, y: 0, width: 0.8, height: 1)

    /// 정면으로 선 사람의 관절점(box 비율). Vision처럼 찍힌 사람 기준 이름이라 leftShoulder가 화면 오른쪽이다.
    /// 모든 관절의 신뢰도는 confidence이고 omitting의 관절은 뺀다.
    static func standingBody(
        in box: NormalizedRect, confidence: Double = 1, omitting: Set<BodyJoint> = []
    ) -> BodyGeometry {
        let layout: [BodyJoint: (x: Double, y: Double)] = [
            .neck: (0.5, 0.82), .rightShoulder: (0.25, 0.8), .leftShoulder: (0.75, 0.8),
            .rightElbow: (0.18, 0.62), .leftElbow: (0.82, 0.62), .rightWrist: (0.15, 0.45), .leftWrist: (0.85, 0.45),
            .rightHip: (0.38, 0.5), .leftHip: (0.62, 0.5), .rightKnee: (0.39, 0.27), .leftKnee: (0.61, 0.27),
            .rightAnkle: (0.4, 0.05), .leftAnkle: (0.6, 0.05), .root: (0.5, 0.5),
        ]
        var joints: [BodyJoint: NormalizedPoint] = [:]
        var confidences: [BodyJoint: Double] = [:]
        for (joint, spot) in layout where !omitting.contains(joint) {
            joints[joint] = NormalizedPoint(x: box.minX + box.width * spot.x, y: box.minY + box.height * spot.y)
            confidences[joint] = confidence
        }
        return BodyGeometry(joints: joints, confidence: confidences)
    }

    /// 변형 테스트의 점 표식 반지름(픽셀).
    static let markerRadius: CGFloat = 3
    /// 이 빨강 값보다 어두운 픽셀을 표식으로 본다. 바탕(0.9 회색)은 sRGB 바이트로 약 230이다.
    static let markerThreshold: UInt8 = 200
    /// 픽셀 (x, y)의 중심은 (x + 0.5, y + 0.5)다.
    static let pixelCenterOffset = 0.5
    /// expectedPosition의 고정점 반복 횟수. 이동량 기울기가 0.5 아래라 30번이면 충분히 수렴한다.
    static let fixedPointIterations = 30

    /// 밝은 회색(0.9) 바탕에 반지름 markerRadius인 검은 점들. 점은 hardEllipse로 픽셀 크기에서 그린다.
    static func markers(_ centers: [CGPoint], extent: CGRect) -> CIImage {
        var image = CIImage(color: CIColor(red: 0.9, green: 0.9, blue: 0.9)).cropped(to: extent)
        let dot = CIImage(color: .black)
        let radii = CGSize(width: markerRadius, height: markerRadius)
        for center in centers {
            let mask = hardEllipse(center: center, radii: radii, extent: extent)
            image = dot.applyingFilter(
                "CIBlendWithMask", parameters: [kCIInputBackgroundImageKey: image, kCIInputMaskImageKey: mask]
            ).cropped(to: extent)
        }
        return image
    }

    /// point 둘레 ±window 픽셀 안 어두운 픽셀의 가중 중심(가중치 = markerThreshold − 빨강). 없으면 nil.
    static func markerCentroid(_ grid: PixelGrid, near point: CGPoint, window: Int = 16) -> CGPoint? {
        var total: Double = 0
        var sumX: Double = 0
        var sumY: Double = 0
        let centerX = Int(point.x)
        let centerY = Int(point.y)
        for y in max(0, centerY - window)...min(grid.height - 1, centerY + window) {
            for x in max(0, centerX - window)...min(grid.width - 1, centerX + window) {
                let weight = Double(markerThreshold) - Double(grid.red(CGPoint(x: x, y: y)))
                guard weight > 0 else { continue }
                total += weight
                sumX += weight * (Double(x) + pixelCenterOffset)
                sumY += weight * (Double(y) + pixelCenterOffset)
            }
        }
        guard total > 0 else { return nil }
        return CGPoint(x: sumX / total, y: sumY / total)
    }

    /// out(p) = in(p − D(p))에서 입력의 marker가 나타나는 출력 위치. p = marker + D(p)를 고정점 반복으로 푼다.
    static func expectedPosition(of marker: CGPoint, primitives: [ShapePrimitive], limit: Double) -> CGPoint {
        var position = marker
        for _ in 0..<fixedPointIterations {
            let shift = DisplacementWarp.displacement(at: position, of: primitives, limit: limit)
            position = CGPoint(x: marker.x + shift.dx, y: marker.y + shift.dy)
        }
        return position
    }

    /// minimumJacobian의 격자 간격과 중앙 차분 간격(픽셀).
    static let jacobianGridStep: CGFloat = 4
    static let jacobianDelta: CGFloat = 0.5

    /// out(p) = in(p − D(p))에서 읽는 위치 p − D(p)의 야코비안 행렬식 최솟값. 0 이하면 이미지가 접힌다.
    static func minimumJacobian(of primitives: [ShapePrimitive], limit: Double, in rect: CGRect) -> CGFloat {
        func source(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            let shift = DisplacementWarp.displacement(at: CGPoint(x: x, y: y), of: primitives, limit: limit)
            return CGPoint(x: x - shift.dx, y: y - shift.dy)
        }
        let h = jacobianDelta
        var worst = CGFloat.infinity
        for y in stride(from: rect.minY, through: rect.maxY, by: jacobianGridStep) {
            for x in stride(from: rect.minX, through: rect.maxX, by: jacobianGridStep) {
                let right = source(x + h, y)
                let left = source(x - h, y)
                let up = source(x, y + h)
                let down = source(x, y - h)
                let a = (right.x - left.x) / (2 * h)
                let b = (up.x - down.x) / (2 * h)
                let c = (right.y - left.y) / (2 * h)
                let d = (up.y - down.y) / (2 * h)
                worst = min(worst, a * d - b * c)
            }
        }
        return worst
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
/// 보정 없는 렌더는 Core Image가 읽은 CGImage를 그대로 돌려줘 ARGB일 수 있으므로 채널을 RGBA 순서로 맞춘다.
struct PixelGrid {
    let width: Int
    let height: Int
    let bytesPerRow: Int
    let data: [UInt8]
    /// 메모리 안 바이트 위치. R, G, B, A 순서.
    let channelOffsets: [Int]

    init(_ image: CGImage) {
        width = image.width
        height = image.height
        bytesPerRow = image.bytesPerRow
        data = Array(image.dataProvider!.data! as Data)
        let alphaFirst = [.premultipliedFirst, .first, .noneSkipFirst].contains(image.alphaInfo)
        let littleEndian = image.bitmapInfo.intersection(.byteOrderMask) == .byteOrder32Little
        switch (alphaFirst, littleEndian) {
        case (true, false):
            channelOffsets = [1, 2, 3, 0]
        case (true, true):
            channelOffsets = [2, 1, 0, 3]
        case (false, true):
            channelOffsets = [3, 2, 1, 0]
        case (false, false):
            channelOffsets = [0, 1, 2, 3]
        }
    }

    /// CGImage는 맨 위 행부터 저장한다.
    func rgba(_ point: CGPoint) -> [UInt8] {
        let x = Int(point.x)
        let y = Int(point.y)
        let offset = (height - 1 - y) * bytesPerRow + x * 4
        return channelOffsets.map { data[offset + $0] }
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

    /// 얼굴 상자 중심(256, 200)의 정규화 좌표. 회전 테스트의 회전 중심.
    static var pivot: NormalizedPoint {
        NormalizedPoint(x: Double(box.midX) / Double(size), y: Double(box.midY) / Double(size))
    }

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

/// 흰자·홍채·치아까지 그린 합성 얼굴. 눈 다각형·동공·입술 특징점은 make()와 같다.
extension SyntheticFace {
    static let scleraColor = CIColor(red: 0.78, green: 0.74, blue: 0.72)
    static let teethColor = CIColor(red: 0.86, green: 0.80, blue: 0.66)
    /// 홍채 바깥 고리·안쪽 고리·동공의 반지름(픽셀). 눈 높이 28px × 0.5 = 14px 원 안에 든다.
    static let irisRingRadii: [CGFloat] = [12, 7, 3]
    static let irisRingColors = [
        CIColor(red: 0.30, green: 0.20, blue: 0.12), CIColor(red: 0.50, green: 0.36, blue: 0.22),
        CIColor(red: 0.04, green: 0.03, blue: 0.03),
    ]
    /// 다문 입의 안쪽 입술 타원. 높이 1px이라 넓이가 얼굴 상자의 0.14%다.
    static let closedInnerMouthRadii = CGSize(width: 40, height: 1)
    /// 흰자 위 표본 점(왼눈 중심에서 20px 바깥). 홍채 고리 밖이고 눈 다각형 안이다.
    static let scleraPoint = CGPoint(x: 180, y: 300)
    /// 입술 고리(바깥 20px·안쪽 8px 반지름 사이) 위 표본 점.
    static let lipPoint = CGPoint(x: 256, y: 152)
    /// 왼눈 위끝(314)과 눈썹 아래끝(332) 사이 피부.
    static let lidSkin = CGPoint(x: 200, y: 324)
    /// 입술 위끝(160)과 코 아래(190) 사이 피부.
    static let philtrum = CGPoint(x: 256, y: 172)

    /// mouthOpen이 false면 치아를 그리지 않고 안쪽 입술을 closedInnerMouthRadii 타원으로 둔다(다문 입).
    static func makeFeatures(mouthOpen: Bool = true) -> SyntheticFace {
        let base = make()
        var image = base.image
        for eye in [leftEye, rightEye] {
            image = paint(CIImage(color: scleraColor), center: eye, radii: eyeRadii, over: image)
            for (radius, color) in zip(irisRingRadii, irisRingColors) {
                let radii = CGSize(width: radius, height: radius)
                image = paint(CIImage(color: color), center: eye, radii: radii, over: image)
            }
        }
        var face = base.face
        if mouthOpen {
            image = paint(CIImage(color: teethColor), center: mouth, radii: innerMouthRadii, over: image)
        } else {
            face.landmarks[.innerLips] = innerLips(radii: closedInnerMouthRadii)
        }
        return SyntheticFace(image: image, face: face)
    }

    /// 입 중심의 12점 타원 안쪽 입술 특징점(정규화).
    static func innerLips(radii: CGSize) -> [NormalizedPoint] {
        ellipse(mouth, radii)
    }
}

/// 메이크업 영역 표본 점. 얼굴 좌표(원점 (256, 200), 얼굴 폭 280, 눈 높이 100, 입 높이 −60)에서 계산한 위치다.
extension SyntheticFace {
    /// 블러셔 중심. u = 눈동자 u ±56 × 1.15, v = −60 + 160 × 0.45 = 12.
    static let leftBlush = CGPoint(x: 191.6, y: 212)
    static let rightBlush = CGPoint(x: 320.4, y: 212)
    /// 얼굴을 중심 둘레로 30° 돌렸을 때의 블러셔 중심과 lidSkin 자리.
    static let rolledLeftBlush = CGPoint(x: 194.2, y: 178.2)
    static let rolledRightBlush = CGPoint(x: 305.8, y: 242.6)
    static let rolledLidSkin = CGPoint(x: 145.5, y: 279.4)
    /// 왼눈썹 가운데와, 세로로 1.6배 넓힌 눈썹 안이지만 원래 눈썹(위끝 344) 바깥인 피부.
    static let leftBrowCenter = CGPoint(x: 200, y: 338)
    static let aboveLeftBrow = CGPoint(x: 200, y: 345)
    /// 광대 아래 쉐딩 중심(u ±95.2, v = −60 + 160 × 0.2).
    static let leftHollow = CGPoint(x: 161, y: 172)
    static let rightHollow = CGPoint(x: 351, y: 172)
    /// 왼쪽 턱선 쉐딩 타원(윤곽점 (134.4, 105.6) 중심) 안쪽의 얼굴 피부.
    static let leftJaw = CGPoint(x: 145, y: 110)
    /// 콧대·이마 가운데·턱 끝 하이라이터 안.
    static let bridge = CGPoint(x: 256, y: 245)
    static let foreheadCenter = CGPoint(x: 256, y: 368)
    static let chinTip = CGPoint(x: 256, y: 67)
}

/// 주름 띠 표본 점(G4).
/// 얼굴 좌표(원점 (256, 200), 얼굴 폭 280).
/// 계산은 G4-1 계획 Task 2 참고.
extension SyntheticFace {
    /// 다크서클 타원 안(중심 v = 눈 아래끝 286 − 280 × 0.055 = 270.6, 세로 반지름 280 × 0.045 = 12.6).
    static let underLeftEye = CGPoint(x: 200, y: 262)
    static let underRightEye = CGPoint(x: 312, y: 262)
    /// 얼굴을 중심 둘레로 30° 돌렸을 때의 under*Eye 자리.
    static let rolledUnderLeftEye = CGPoint(x: 176.5, y: 225.7)
    static let rolledUnderRightEye = CGPoint(x: 273.5, y: 281.7)
    /// 팔자 띠 안.
    /// 띠 중심은 코 날개 (236, 190) → 입꼬리 (208, 140)를 25% 연장한 끝 (201, 127.5)의 중점 (218.5, 158.75)을
    /// 바깥으로 12.6 민 자리(약 (207.5, 165)다).
    /// 격자를 찍어 띠 값 239·마리오네트 띠 0이고 피부 질감 얼룩이 작은 자리로 옮겼다.
    /// 오른쪽은 픽셀 거울상(x → 511 − x)이다.
    static let leftNasolabial = CGPoint(x: 202, y: 156)
    static let rightNasolabial = CGPoint(x: 309, y: 156)
    /// 연장된 팔자 띠 끝(약 (188, 130))에서 3 흐림 이상 떨어진 턱 쪽 피부.
    /// 팔자 띠 밖이어야 한다.
    static let belowLeftNasolabial = CGPoint(x: 186, y: 100)
    /// 마리오네트 타원 안(입꼬리에서 15° 바깥으로 19.6 내려간 중점을 바깥으로 8.4 민 자리 (194.8, 123.3)).
    /// 오른쪽은 픽셀 거울상(x → 511 − x)이다.
    static let leftMarionette = CGPoint(x: 196, y: 120)
    static let rightMarionette = CGPoint(x: 315, y: 120)
    /// 두 눈썹 안쪽 끝 사이.
    static let glabella = CGPoint(x: 256, y: 338)
}

/// 합성 얼굴 아래에 몸 피부와 옷을 둔 사진. 몸 피부 단계 테스트용.
extension SyntheticFace {
    /// 턱(y 50) 아래 몸 피부. 피부 질감을 그대로 쓴다.
    static let bodySkinRect = CGRect(x: 156, y: 0, width: 200, height: 48)
    /// 몸 왼쪽 회색 옷. 피부색 가중치가 0이다.
    static let leftShirtRect = CGRect(x: 100, y: 0, width: 56, height: 48)
    static let shirtColor = CIColor(red: 0.5, green: 0.5, blue: 0.5)
    /// 몸 피부 안 분산 측정 패치.
    static let bodyPatch = CGRect(x: 226, y: 4, width: 60, height: 40)
    static let bodySkinPoint = CGPoint(x: 256, y: 24)
    static let shirtPoint = CGPoint(x: 128, y: 24)
    /// 인물 마스크 밖 배경(왼쪽 x < 96, 머리 위 y > 416).
    static let backgroundBesideBody = CGPoint(x: 40, y: 24)
    static let backgroundAboveHead = CGPoint(x: 256, y: 450)
    /// 64×64 스텁 인물 마스크. 사람 사각형 x 12…52, y 0…52 → 사진 x 96…416, y 0…416(얼굴·이마(y 380)·몸·옷을 덮는다).
    static let bodyPersonMask = RenderingTestSupport.personMask(
        size: CGSize(width: 64, height: 64), person: CGRect(x: 12, y: 0, width: 40, height: 52))

    /// 비트맵으로 굳힌다. 마스크가 0인 곳(옷·얼굴 피부)의 바이트를 그대로 비교하려면 입력이 그래프가 아닌 비트맵이어야 한다.
    static func makeWithBody() throws -> SyntheticFace {
        let base = make()
        var image = RenderingTestSupport.skinTexture(size: size).cropped(to: bodySkinRect).composited(over: base.image)
        image = CIImage(color: shirtColor).cropped(to: leftShirtRect).composited(over: image)
        let baked = CIImage(cgImage: try RenderingTestSupport.renderer.makeCGImage(image.cropped(to: extent)))
        return SyntheticFace(image: baked, face: base.face)
    }
}

extension SyntheticFace {
    /// 반 크기 합성 얼굴 둘을 좌우에 놓고 비트맵으로 굳힌다.
    /// faces[0]이 왼쪽(x 0…0.5), faces[1]이 오른쪽이다.
    static func pair(_ synthetic: SyntheticFace, renderer: Renderer) throws -> (image: CIImage, faces: [FaceGeometry]) {
        let half = CGAffineTransform(scaleX: 0.5, y: 0.5)
        let side = CGFloat(size)
        let left = synthetic.image.transformed(by: half.concatenating(CGAffineTransform(translationX: 0, y: side / 4)))
        let right = synthetic.image.transformed(
            by: half.concatenating(CGAffineTransform(translationX: side / 2, y: side / 4)))
        let composed = left.composited(over: right).composited(over: CIImage(color: .gray)).cropped(to: extent)
        let image = CIImage(cgImage: try renderer.makeCGImage(composed))
        let faces = [
            synthetic.face.transformed(scale: 0.5, offset: NormalizedPoint(x: 0, y: 0.25)),
            synthetic.face.transformed(scale: 0.5, offset: NormalizedPoint(x: 0.5, y: 0.25)),
        ]
        return (image, faces)
    }
}

extension FaceGeometry {
    /// 특징점을 pivot 둘레로 angle만큼 반시계로 돌리고 roll을 angle로 둔다. 상자는 그대로다. 정사각형 extent에서만 쓴다.
    func rotated(by angle: Double, about pivot: NormalizedPoint) -> FaceGeometry {
        let cosine = cos(angle)
        let sine = sin(angle)
        var turned: [FaceLandmark: [NormalizedPoint]] = [:]
        for (landmark, points) in landmarks {
            turned[landmark] = points.map { point in
                let dx = point.x - pivot.x
                let dy = point.y - pivot.y
                return NormalizedPoint(x: pivot.x + dx * cosine - dy * sine, y: pivot.y + dx * sine + dy * cosine)
            }
        }
        return FaceGeometry(boundingBox: boundingBox, landmarks: turned, roll: angle, yaw: yaw)
    }

    /// 주어진 특징점을 뺀다.
    func removing(_ removed: [FaceLandmark]) -> FaceGeometry {
        var copy = self
        for landmark in removed {
            copy.landmarks[landmark] = nil
        }
        return copy
    }

    /// 상자와 특징점을 정규화 좌표에서 scale배 한 뒤 offset만큼 옮긴다. 한 사진에 얼굴 여럿을 놓을 때 쓴다.
    func transformed(scale: Double, offset: NormalizedPoint) -> FaceGeometry {
        func move(_ point: NormalizedPoint) -> NormalizedPoint {
            NormalizedPoint(x: point.x * scale + offset.x, y: point.y * scale + offset.y)
        }
        let box = NormalizedRect(
            x: boundingBox.x * scale + offset.x, y: boundingBox.y * scale + offset.y,
            width: boundingBox.width * scale, height: boundingBox.height * scale)
        return FaceGeometry(boundingBox: box, landmarks: landmarks.mapValues { $0.map(move) }, roll: roll, yaw: yaw)
    }
}

extension BodyGeometry {
    /// pivot 둘레로 반시계 angle(라디안) 돌린 관절점. 정사각형 extent에서만 픽셀 회전과 같다. 상자는 그대로 둔다.
    func rotated(by angle: Double, about pivot: NormalizedPoint) -> BodyGeometry {
        var copy = self
        for (joint, point) in joints {
            let x = point.x - pivot.x
            let y = point.y - pivot.y
            copy.joints[joint] = NormalizedPoint(
                x: pivot.x + x * cos(angle) - y * sin(angle), y: pivot.y + x * sin(angle) + y * cos(angle))
        }
        return copy
    }
}

/// 폰 화면 배율 측정.
/// 비교할 이미지를 가로 1170px(iPhone 390pt × 3)로 맞춘 뒤 8비트로 읽는다(스펙 G4 1.1).
enum DisplayScale {
    static let phoneWidth: CGFloat = 1170
    /// 세 채널 중 최대 |Δ|가 이 값 이상이면 "바뀐 픽셀"이다.
    static let defaultMinimumDelta = 4
    /// BT.601 휘도 계수.
    private static let lumaWeights = (r: 0.299, g: 0.587, b: 0.114)
    /// BT.601 Cb·Cr 계수(0…1 값 기준).
    private static let cbWeights = (r: -0.168736, g: -0.331264, b: 0.5)
    private static let crWeights = (r: 0.5, g: -0.418688, b: -0.081312)

    static func grid(_ image: CGImage) throws -> PixelGrid {
        let source = CIImage(cgImage: image)
        let scale = phoneWidth / source.extent.width
        let height = (source.extent.height * scale).rounded(.down)
        let scaled = source.applyingFilter(
            "CILanczosScaleTransform", parameters: [kCIInputScaleKey: scale, kCIInputAspectRatioKey: 1]
        ).cropped(to: CGRect(x: 0, y: 0, width: phoneWidth, height: height))
        return PixelGrid(try RenderingTestSupport.renderer.makeCGImage(scaled))
    }

    static func grid(_ image: CIImage) throws -> PixelGrid {
        try grid(RenderingTestSupport.renderer.makeCGImage(image))
    }

    /// 정규화 사각형(원점 왼쪽 아래)을 격자 픽셀 사각형으로.
    static func rect(_ normalized: NormalizedRect, in grid: PixelGrid) -> CGRect {
        CGRect(
            x: normalized.x * Double(grid.width), y: normalized.y * Double(grid.height),
            width: normalized.width * Double(grid.width), height: normalized.height * Double(grid.height)
        ).intersection(CGRect(x: 0, y: 0, width: grid.width, height: grid.height)).integral
    }

    private static func points(_ grid: PixelGrid, in rect: CGRect?) -> [CGPoint] {
        let area = rect ?? CGRect(x: 0, y: 0, width: grid.width, height: grid.height)
        var result: [CGPoint] = []
        for y in Int(area.minY)..<Int(area.maxY) {
            for x in Int(area.minX)..<Int(area.maxX) {
                result.append(CGPoint(x: x, y: y))
            }
        }
        return result
    }

    private static func luma(_ rgba: [UInt8]) -> Double {
        lumaWeights.r * Double(rgba[0]) + lumaWeights.g * Double(rgba[1]) + lumaWeights.b * Double(rgba[2])
    }

    private static func chroma(_ rgba: [UInt8]) -> (cb: Double, cr: Double) {
        let r = Double(rgba[0]) / 255
        let g = Double(rgba[1]) / 255
        let b = Double(rgba[2]) / 255
        return (
            cbWeights.r * r + cbWeights.g * g + cbWeights.b * b, crWeights.r * r + crWeights.g * g + crWeights.b * b
        )
    }

    private static func weightValue(_ mask: PixelGrid?, _ point: CGPoint) -> Double {
        mask.map { Double($0.red(point)) / 255 } ?? 1
    }

    static func changedFraction(
        _ before: PixelGrid, _ after: PixelGrid, in rect: CGRect?, minimumDelta: Int = defaultMinimumDelta
    ) -> Double {
        let all = points(before, in: rect)
        guard !all.isEmpty else { return 0 }
        let changed = all.filter { point in
            let a = before.rgba(point)
            let b = after.rgba(point)
            return (0..<3).contains { abs(Int(a[$0]) - Int(b[$0])) >= minimumDelta }
        }
        return Double(changed.count) / Double(all.count)
    }

    /// 가중 평균 ΔY와 평균 |ΔY|(8비트).
    /// weight가 nil이면 전체 평균.
    static func lumaDelta(_ before: PixelGrid, _ after: PixelGrid, weight: PixelGrid?) -> (
        mean: Double, meanAbsolute: Double
    ) {
        var total = 0.0
        var sum = 0.0
        var absolute = 0.0
        for point in points(before, in: nil) {
            let w = weightValue(weight, point)
            guard w > 0 else { continue }
            let delta = luma(after.rgba(point)) - luma(before.rgba(point))
            total += w
            sum += w * delta
            absolute += w * abs(delta)
        }
        guard total > 0 else { return (0, 0) }
        return (sum / total, absolute / total)
    }

    /// 가중 평균 |ΔCb|·|ΔCr|(0…1).
    static func chromaDelta(_ before: PixelGrid, _ after: PixelGrid, weight: PixelGrid?) -> (cb: Double, cr: Double) {
        var total = 0.0
        var cb = 0.0
        var cr = 0.0
        for point in points(before, in: nil) {
            let w = weightValue(weight, point)
            guard w > 0 else { continue }
            let a = chroma(before.rgba(point))
            let b = chroma(after.rgba(point))
            total += w
            cb += w * abs(b.cb - a.cb)
            cr += w * abs(b.cr - a.cr)
        }
        guard total > 0 else { return (0, 0) }
        return (cb / total, cr / total)
    }

    /// 가중 평균 채널 Δ(8비트, 부호 있음).
    /// channel 0 = R, 2 = B.
    static func channelDelta(_ before: PixelGrid, _ after: PixelGrid, channel: Int, weight: PixelGrid?) -> Double {
        var total = 0.0
        var sum = 0.0
        for point in points(before, in: nil) {
            let w = weightValue(weight, point)
            guard w > 0 else { continue }
            total += w
            sum += w * (Double(after.rgba(point)[channel]) - Double(before.rgba(point)[channel]))
        }
        return total > 0 ? sum / total : 0
    }

    static func lumaDeltaStandardDeviation(_ before: PixelGrid, _ after: PixelGrid, in rect: CGRect?) -> Double {
        let deltas = points(before, in: rect).map { luma(after.rgba($0)) - luma(before.rgba($0)) }
        return RenderingTestSupport.variance(deltas).squareRoot()
    }

    static func percentileAbsoluteLumaDelta(
        _ before: PixelGrid, _ after: PixelGrid, in rect: CGRect, percentile: Double
    ) -> Double {
        let deltas = points(before, in: rect).map { abs(luma(after.rgba($0)) - luma(before.rgba($0))) }.sorted()
        guard !deltas.isEmpty else { return 0 }
        let index = min(deltas.count - 1, Int(Double(deltas.count - 1) * percentile))
        return deltas[index]
    }

    /// 가중 평균 Y(8비트).
    static func luma(_ grid: PixelGrid, weight: PixelGrid) -> Double {
        var total = 0.0
        var sum = 0.0
        for point in points(grid, in: nil) {
            let w = weightValue(weight, point)
            guard w > 0 else { continue }
            total += w
            sum += w * luma(grid.rgba(point))
        }
        return total > 0 ? sum / total : 0
    }

    /// (복구 − 결함) ÷ (원본 − 결함).
    /// 1이면 완전 복구, 0이면 그대로.
    static func recovery(original: Double, defective: Double, repaired: Double) -> Double {
        let drop = original - defective
        guard abs(drop) > 1e-6 else { return 0 }
        return (repaired - defective) / drop
    }
}

/// 실사진 위에 심는 결함.
/// 모두 실제 특징점 마스크·좌표를 쓴다(스펙 G4 1.1).
enum SyntheticDefect {
    /// image × (1 − depth × mask).
    /// 선형 공간 곱이다.
    static func shadowed(_ image: CIImage, mask: CIImage, depth: Double) -> CIImage {
        let factor = 1 - depth
        let dimmed = image.applyingFilter(
            "CIColorMatrix",
            parameters: [
                "inputRVector": CIVector(x: factor, y: 0, z: 0, w: 0),
                "inputGVector": CIVector(x: 0, y: factor, z: 0, w: 0),
                "inputBVector": CIVector(x: 0, y: 0, z: factor, w: 0),
            ])
        return MaskBuilder.blend(dimmed, over: image, mask: mask).cropped(to: image.extent)
    }

    /// 붉은 반점.
    /// 감마 공간에서 R × 1.12, G·B × 0.95(Cr 약 +0.05)인 단단한 원.
    static func reddened(_ image: CIImage, center: CGPoint, radius: CGFloat, extent: CGRect) -> CIImage {
        let encoded = image.applyingFilter("CILinearToSRGBToneCurve")
        let red = encoded.applyingFilter(
            "CIColorMatrix",
            parameters: [
                "inputRVector": CIVector(x: 1.12, y: 0, z: 0, w: 0),
                "inputGVector": CIVector(x: 0, y: 0.95, z: 0, w: 0),
                "inputBVector": CIVector(x: 0, y: 0, z: 0.95, w: 0),
            ])
        let mask = RenderingTestSupport.hardEllipse(
            center: center, radii: CGSize(width: radius, height: radius), extent: extent)
        return MaskBuilder.blend(red, over: encoded, mask: mask).applyingFilter("CISRGBToneCurveToLinear")
            .cropped(to: extent)
    }

    /// 반사광.
    /// 선형 휘도를 가우시안 봉우리(중심에서 약 lift)만큼 더한다.
    /// lift를 더한 사본을 봉우리 마스크로 섞어 image + lift × 봉우리가 된다.
    /// 알파 0인 빛 층을 더하는 방식은 사전곱에서 빛이 0이 되어 쓰지 않는다.
    static func highlighted(_ image: CIImage, center: CGPoint, radius: CGFloat, lift: Double, extent: CGRect) -> CIImage
    {
        let blob = RenderingTestSupport.hardEllipse(
            center: center, radii: CGSize(width: radius, height: radius), extent: extent
        ).applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: radius / 2]).cropped(to: extent)
        let lifted = image.applyingFilter(
            "CIColorMatrix", parameters: ["inputBiasVector": CIVector(x: lift, y: lift, z: lift, w: 0)])
        return MaskBuilder.blend(lifted, over: image, mask: blob).cropped(to: extent)
    }
}

/// 실제 Vision으로 분석한 데모 사진.
/// 한 번만 준비해 모든 실사진 수용 테스트가 나눠 쓴다.
final class RealPortrait: @unchecked Sendable {
    /// 준비 결과.
    /// 실패(예: Vision 버전이 바뀌어 얼굴 수가 1이 아님)는 테스트마다 get()에서 오류로 나온다.
    /// fatalError로 두면 테스트 묶음 전체가 멈춰 다른 렌더링 테스트 결과까지 잃는다.
    static let shared = Result { try RealPortrait() }

    let image: CIImage
    let extent: CGRect
    let analysis: PhotoAnalysis
    let face: FaceGeometry
    let faceWidth: CGFloat
    let tuning = RenderTuning()

    private init() throws {
        guard
            let url = Bundle.module.url(forResource: "demo-portrait", withExtension: "png", subdirectory: "Fixtures")
        else { throw MellowError.cannotOpenPhoto(filename: "demo-portrait.png") }
        image = try ImageLoader().load(url: url, maxDimension: tuning.previewMaxDimension)
        extent = image.extent
        let faces = try VisionFaceAnalyzer().analyze(image)
        guard faces.count == 1 else { throw MellowError.faceAnalysisUnavailable(reason: "faces \(faces.count)") }
        let mask = try VisionPersonAnalyzer().personMask(image)
        let bodies = try VisionBodyAnalyzer().analyze(image)
        analysis = PhotoAnalysis(faces: faces, personMask: mask, bodies: bodies)
        face = faces[0]
        faceWidth = FaceRegions.faceWidth(face, extent: image.extent)
    }

    func context(_ recipe: EditRecipe, image input: CIImage? = nil) -> RenderContext {
        RenderContext(extent: (input ?? image).extent, recipe: recipe, analysis: analysis, tuning: tuning)
    }

    /// stage가 nil이면 전체 파이프라인.
    func render(_ recipe: EditRecipe, stage: (any RenderStage)? = nil, input: CIImage? = nil) throws -> CGImage {
        let source = input ?? image
        let context = self.context(recipe, image: source)
        let output =
            try stage.map { try $0.apply(source, in: context) }
            ?? RenderPipeline.standard.render(source, context: context)
        return try RenderingTestSupport.renderer.makeCGImage(output)
    }

    /// 그래프를 비트맵으로 굳힌다.
    /// 결함을 심은 입력은 굳혀서 넘긴다.
    func baked(_ graph: CIImage) throws -> CIImage {
        CIImage(cgImage: try RenderingTestSupport.renderer.makeCGImage(graph.cropped(to: extent)))
    }

    /// 영역 마스크를 화면 배율 격자로.
    /// nil이면 실패.
    func mask(_ region: FaceRegions.RegionMask?) throws -> PixelGrid {
        guard let region else { throw MellowError.renderFailed }
        return try DisplayScale.grid(region.image.cropped(to: extent))
    }

    func skinMask(strength: Double = 1) throws -> CIImage {
        try FaceRegions.skinMask(face: face, image: image, extent: extent, tuning: tuning, strength: strength)
    }

    /// 몸 피부 단계가 밝기·톤을 거는 영역(눈·입 제외 전).
    /// 인물 마스크(없으면 얼굴 둘레 대체 영역) × 볼 기준 몸 피부색 가중치다.
    func bodySkinArea() throws -> CIImage {
        let encoded = image.applyingFilter("CILinearToSRGBToneCurve")
        guard let cheeks = FaceRegions.cheekAverages(of: encoded, face: face, extent: extent) else {
            throw MellowError.renderFailed
        }
        let area: CIImage
        if let person = analysis.personMask {
            let shortSide = min(extent.width, extent.height)
            let feather = max(CGFloat(tuning.skinBlurMinimumRadius), shortSide * CGFloat(tuning.bodySkinMaskFeather))
            area = BackgroundStage.personMask(person, extent: extent, feather: feather)
        } else {
            area = BodySkinStage.fallbackPersonRegion(face: face, extent: extent, tuning: tuning)
        }
        let chroma = try SkinKernels.shared.chromaWeight(
            of: encoded, left: cheeks.left, right: cheeks.right, sigma: tuning.bodySkinChromaSigma, extent: extent)
        let black = CIImage(color: .black).cropped(to: extent)
        return area.composited(over: black)
            .applyingFilter("CIMultiplyCompositing", parameters: [kCIInputBackgroundImageKey: chroma])
            .cropped(to: extent)
    }
}

extension RenderingTestSupport {
    /// rect 안 fine 대역(원본 − blur(fineRadius)) 휘도 분산의 후/전 비를 weight(회색 마스크) 가중으로 잰다.
    /// 1이면 질감 그대로이고 작으면 뭉갠 것이다.
    /// 원본 배율에서 잰다.
    /// 마스크가 0인 눈·눈썹·입술·배경은 비에 들어가지 않는다(스펙 G4 1.4 "피부 마스크 안"·"띠 영역").
    static func fineVarianceRatio(before: CIImage, after: CIImage, weight: CIImage, in rect: CGRect, fineRadius: Double)
        throws -> Double
    {
        let weights = try luma(weight.cropped(to: rect))
        let first = try weightedFineVariance(before, weights: weights, in: rect, fineRadius: fineRadius)
        let second = try weightedFineVariance(after, weights: weights, in: rect, fineRadius: fineRadius)
        return first > 0 ? second / first : 1
    }

    private static func weightedFineVariance(_ image: CIImage, weights: [Double], in rect: CGRect, fineRadius: Double)
        throws -> Double
    {
        let original = try luma(image.cropped(to: rect))
        let blurred = try luma(FrequencySeparation.blurred(image, radius: fineRadius).cropped(to: rect))
        let fine = zip(original, blurred).map { $0 - $1 }
        let total = weights.reduce(0, +)
        // 마스크가 비었거나 크기가 어긋나면 비가 1로 조용히 통과하지 않게 실패한다.
        guard total > 0, fine.count == weights.count else { throw MellowError.renderFailed }
        let mean = zip(fine, weights).reduce(0) { $0 + $1.0 * $1.1 } / total
        return zip(fine, weights).reduce(0) { $0 + $1.1 * ($1.0 - mean) * ($1.0 - mean) } / total
    }
}

/// 생성 사진 세트의 정답 라벨(shared/fixtures/people/labels.json).
/// people은 왼쪽부터다.
struct PeopleLabels: Decodable {
    struct Person: Decodable {
        var gender: String
        var ageBand: String
        var glasses: Bool
        var pose: String
        var occlusion: String
        var ambiguous: Bool
    }

    struct Photo: Decodable {
        var file: String
        var people: [Person]
    }

    var version: Int
    var photos: [Photo]
}

/// 테스트 타깃에 복사한 생성 사진(couple-01·group-01)과 라벨.
enum PeopleFixtures {
    static func url(_ name: String) throws -> URL {
        try XCTUnwrap(Bundle.module.url(forResource: name, withExtension: nil, subdirectory: "Fixtures/people"))
    }

    static func labels() throws -> PeopleLabels {
        try JSONDecoder().decode(PeopleLabels.self, from: Data(contentsOf: url("labels.json")))
    }

    /// 저장소 원본 폴더.
    /// apple/Tests/MellowRenderingTests/RenderingTestSupport.swift에서 네 단계 위가 저장소 루트다.
    static var sharedFolder: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("shared/fixtures/people")
    }
}

extension RenderingTestSupport {
    /// 전체 층 값을 faces[index]에 anchor로 묶인 개인 층으로 옮긴다.
    /// 옛 targetFace 이행과 같은 규칙이다.
    /// 범위 밖 index는 legacyIndex로 남아 짝이 없다.
    static func restricted(_ recipe: EditRecipe, toFace index: Int, of faces: [FaceGeometry]) -> EditRecipe {
        var moved = recipe
        moved.migrateLegacyTargetFace(index)
        if faces.indices.contains(index), !moved.people.individuals.isEmpty {
            moved.people.individuals[0].anchor = PersonAnchor(faceBox: faces[index].boundingBox)
            moved.people.individuals[0].legacyIndex = nil
        }
        return moved
    }
}
