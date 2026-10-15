import CoreImage
import MellowShared

/// 얼굴 특징점에서 영역 마스크를 만드는 유일한 곳. 분할 모델로 바꿀 때 이 타입만 바꾼다.
/// 좌표는 extent 기준 픽셀이고 원점은 왼쪽 아래다.
enum FaceRegions {
    /// 이마 호를 그리는 구간 수.
    private static let foreheadArcSegments = 12
    /// 타원 다각형의 점 수.
    private static let ellipseSegments = 24
    /// 마스크 계산 영역의 여백. 흐림 반지름의 배수.
    private static let boundsPaddingInFeathers: CGFloat = 4
    /// 래스터 영역 여백(픽셀). 안티에일리어싱 가장자리를 담는다.
    private static let rasterPadding: CGFloat = 1
    /// 볼 표본 정사각형의 한 변. 눈 폭 대비.
    private static let cheekSampleScale: CGFloat = 0.6
    /// 다각형 하나가 되려면 필요한 점 수.
    private static let minimumPolygonPoints = 3

    /// 특징점이 없을 때 쓰는 부위 위치. 얼굴 상자 안의 비율이다.
    private enum FallbackFeature {
        static let leftEye = NormalizedRect(x: 0.15, y: 0.56, width: 0.28, height: 0.14)
        static let rightEye = NormalizedRect(x: 0.57, y: 0.56, width: 0.28, height: 0.14)
        static let mouth = NormalizedRect(x: 0.25, y: 0.18, width: 0.5, height: 0.18)
        /// 코 끝 높이.
        static let noseBottom = 0.35

        static func place(_ ratio: NormalizedRect, in box: NormalizedRect) -> NormalizedRect {
            NormalizedRect(
                x: box.minX + box.width * ratio.x, y: box.minY + box.height * ratio.y, width: box.width * ratio.width,
                height: box.height * ratio.height)
        }
    }

    static func faceWidth(_ face: FaceGeometry, extent: CGRect) -> CGFloat {
        CGFloat(face.boundingBox.width) * extent.width
    }

    static func pixelRect(_ rect: NormalizedRect, in extent: CGRect) -> CGRect {
        CGRect(
            x: extent.minX + CGFloat(rect.x) * extent.width, y: extent.minY + CGFloat(rect.y) * extent.height,
            width: CGFloat(rect.width) * extent.width, height: CGFloat(rect.height) * extent.height)
    }

    /// 0…strength 피부 가중치. 눈·눈썹·입술은 0, 피부색이 아닌 픽셀(머리카락·배경)은 0에 가깝다.
    /// 윤곽 다각형 + 이마 호 − 넓힌 보호 영역 → × 피부색 가중치 → 흐림 → × strength.
    static func skinMask(
        face: FaceGeometry, image: CIImage, extent: CGRect, tuning: RenderTuning, strength: Double = 1,
        cache: RegionMaskCache? = nil
    ) throws -> CIImage {
        let black = CIImage(color: .black).cropped(to: extent)
        let bounds = maskBounds(face: face, extent: extent, tuning: tuning)
        guard !bounds.isEmpty else { return black }
        let cutWidth = faceWidth(face, extent: extent) * CGFloat(tuning.skinFeatureFeather) * 2
        var mask = polygonMask(
            fill: [skinPolygon(face: face, extent: extent, tuning: tuning)],
            cut: protectedPolygons(face: face, extent: extent), cutWidth: cutWidth, extent: extent, tuning: tuning,
            cache: cache)
        let cheeks = cheekRects(face: face, extent: extent)
        if let left = cheeks.first, let right = cheeks.last {
            let encoded = image.applyingFilter("CILinearToSRGBToneCurve")
            let weight = try SkinKernels.shared.chromaWeight(
                of: encoded, left: average(encoded, in: left), right: average(encoded, in: right),
                sigma: tuning.skinChromaSigma, extent: extent)
            mask = mask.applyingFilter("CIMultiplyCompositing", parameters: [kCIInputBackgroundImageKey: weight])
        }
        var feathered = mask.clampedToExtent()
            .applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: featherRadius(face, extent, tuning)])
        if strength != 1 {
            feathered = feathered.applyingFilter(
                "CIColorMatrix",
                parameters: [
                    "inputRVector": CIVector(x: strength, y: 0, z: 0, w: 0),
                    "inputGVector": CIVector(x: 0, y: strength, z: 0, w: 0),
                    "inputBVector": CIVector(x: 0, y: 0, z: strength, w: 0),
                ])
        }
        return feathered.cropped(to: bounds).composited(over: black)
    }

    /// 마스크가 0이 아닐 수 있는 영역. 이 밖은 계산하지 않아도 된다.
    static func maskBounds(face: FaceGeometry, extent: CGRect, tuning: RenderTuning) -> CGRect {
        let polygon = skinPolygon(face: face, extent: extent, tuning: tuning)
        guard polygon.count >= minimumPolygonPoints else { return .null }
        let padding = featherRadius(face, extent, tuning) * boundsPaddingInFeathers
        return boundingRect(polygon).insetBy(dx: -padding, dy: -padding).intersection(extent).integral
    }

    /// 윤곽점 + 눈썹 위로 올린 이마 호. 윤곽점이 없으면 안쪽으로 줄인 상자 타원.
    static func skinPolygon(face: FaceGeometry, extent: CGRect, tuning: RenderTuning) -> [CGPoint] {
        guard let contour = landmarkPolygon(face, .faceContour, extent), let first = contour.first,
            let last = contour.last
        else { return fallbackSkinEllipse(face, extent, tuning) }
        let span = hypot(last.x - first.x, last.y - first.y)
        guard span > 0 else { return fallbackSkinEllipse(face, extent, tuning) }
        let unit = CGPoint(x: (last.x - first.x) / span, y: (last.y - first.y) / span)
        let mid = CGPoint(x: (first.x + last.x) / 2, y: (first.y + last.y) / 2)
        let upper = upperFeaturePoints(face, extent)
        var normal = CGPoint(x: -unit.y, y: unit.x)
        // 눈썹(없으면 눈, 그것도 없으면 상자 위끝) 쪽을 위로 본다.
        if dot(offset(centroid(upper), from: mid), normal) < 0 {
            normal = CGPoint(x: -normal.x, y: -normal.y)
        }
        let browRise = upper.map { dot(offset($0, from: mid), normal) }.max() ?? 0
        let forehead = CGFloat(face.boundingBox.height) * extent.height * CGFloat(tuning.skinForeheadExtension)
        let rise = max(0, browRise) + forehead
        // θ = 0이 last, θ = π가 first인 반타원. 양 끝점은 윤곽에 이미 있다.
        let arc = (1..<foreheadArcSegments).map { step -> CGPoint in
            let angle = Double.pi * Double(step) / Double(foreheadArcSegments)
            let along = span / 2 * CGFloat(cos(angle))
            let up = rise * CGFloat(sin(angle))
            return CGPoint(x: mid.x + unit.x * along + normal.x * up, y: mid.y + unit.y * along + normal.y * up)
        }
        return contour + arc
    }

    /// 눈·바깥 입술(특징점이 없으면 상자 비율 타원)과 눈썹.
    static func protectedPolygons(face: FaceGeometry, extent: CGRect) -> [[CGPoint]] {
        let box = face.boundingBox
        let required: [(FaceLandmark, NormalizedRect)] = [
            (.leftEye, FallbackFeature.leftEye), (.rightEye, FallbackFeature.rightEye),
            (.outerLips, FallbackFeature.mouth),
        ]
        var polygons = required.map { landmark, fallback in
            landmarkPolygon(face, landmark, extent)
                ?? ellipsePolygon(in: pixelRect(FallbackFeature.place(fallback, in: box), in: extent))
        }
        for landmark in [FaceLandmark.leftEyebrow, .rightEyebrow] {
            if let polygon = landmarkPolygon(face, landmark, extent) {
                polygons.append(polygon)
            }
        }
        return polygons
    }

    /// 자동 잡티에서 뺄 영역. 보호 영역에 코를 더한다(콧구멍은 어둡고 붉어 잡티로 잡힌다).
    static func blemishExclusionPolygons(face: FaceGeometry, extent: CGRect) -> [[CGPoint]] {
        var polygons = protectedPolygons(face: face, extent: extent)
        if let nose = landmarkPolygon(face, .nose, extent) {
            polygons.append(nose)
        }
        return polygons
    }

    /// 눈 아래·코 옆 볼 두 곳. 이미지 밖으로 나간 쪽은 뺀다.
    static func cheekRects(face: FaceGeometry, extent: CGRect) -> [CGRect] {
        let box = face.boundingBox
        let noseBottom = face.bounds(of: .nose)?.minY ?? (box.minY + box.height * FallbackFeature.noseBottom)
        let eyes: [(FaceLandmark, NormalizedRect)] = [
            (.leftEye, FallbackFeature.leftEye), (.rightEye, FallbackFeature.rightEye),
        ]
        return eyes.compactMap { landmark, fallback in
            let eye = face.bounds(of: landmark) ?? FallbackFeature.place(fallback, in: box)
            let center = CGPoint(
                x: extent.minX + CGFloat(eye.midX) * extent.width,
                y: extent.minY + CGFloat((eye.minY + noseBottom) / 2) * extent.height)
            let side = CGFloat(eye.width) * extent.width * cheekSampleScale
            let rect = CGRect(x: center.x - side / 2, y: center.y - side / 2, width: side, height: side)
                .intersection(extent).integral
            return rect.isEmpty ? nil : rect
        }
    }

    /// fill 다각형을 1, cut 다각형(경계를 cutWidth/2만큼 넓혀)을 0으로 그린 extent 크기 회색 마스크.
    /// 얼굴 영역만 긴 변 regionMaskMaxDimension 비트맵에 그리고 확대한다. cache가 있으면 같은 입력의 비트맵을 다시 그리지 않는다.
    static func polygonMask(
        fill: [[CGPoint]], cut: [[CGPoint]], cutWidth: CGFloat, extent: CGRect, tuning: RenderTuning,
        cache: RegionMaskCache? = nil
    ) -> CIImage {
        guard let cache else {
            return rasterize(fill: fill, cut: cut, cutWidth: cutWidth, extent: extent, tuning: tuning)
        }
        let key = RegionMaskKey(
            fill: fill, cut: cut, cutWidth: cutWidth, extent: extent, maxDimension: tuning.regionMaskMaxDimension)
        return cache.mask(for: key) {
            rasterize(fill: fill, cut: cut, cutWidth: cutWidth, extent: extent, tuning: tuning)
        }
    }

    /// polygonMask의 CGContext 래스터.
    private static func rasterize(
        fill: [[CGPoint]], cut: [[CGPoint]], cutWidth: CGFloat, extent: CGRect, tuning: RenderTuning
    ) -> CIImage {
        let black = CIImage(color: .black).cropped(to: extent)
        let filled = fill.filter { $0.count >= minimumPolygonPoints }
        guard !filled.isEmpty else { return black }
        let region = boundingRect(filled.flatMap { $0 }).insetBy(dx: -rasterPadding, dy: -rasterPadding)
            .intersection(extent).integral
        guard !region.isEmpty else { return black }
        let scale = min(1, CGFloat(tuning.regionMaskMaxDimension) / max(region.width, region.height))
        let width = max(1, Int((region.width * scale).rounded(.up)))
        let height = max(1, Int((region.height * scale).rounded(.up)))
        guard
            let context = CGContext(
                data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue)
        else { return black }
        context.setFillColor(gray: 0, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        // CGContext 원점도 왼쪽 아래라 y를 뒤집지 않는다. 점 p는 scale × (p − region.origin)에 그려진다.
        context.scaleBy(x: scale, y: scale)
        context.translateBy(x: -region.minX, y: -region.minY)
        context.setFillColor(gray: 1, alpha: 1)
        for polygon in filled {
            context.addLines(between: polygon)
            context.closePath()
        }
        context.fillPath()
        context.setFillColor(gray: 0, alpha: 1)
        context.setStrokeColor(gray: 0, alpha: 1)
        context.setLineWidth(cutWidth)
        context.setLineJoin(.round)
        for polygon in cut where polygon.count >= minimumPolygonPoints {
            context.addLines(between: polygon)
            context.closePath()
            context.drawPath(using: .fillStroke)
        }
        guard let raster = context.makeImage() else { return black }
        let placement = CGAffineTransform(a: 1 / scale, b: 0, c: 0, d: 1 / scale, tx: region.minX, ty: region.minY)
        return CIImage(cgImage: raster, options: [.colorSpace: NSNull()]).transformed(by: placement)
            .composited(over: black).cropped(to: extent)
    }

    /// 점이 다각형 안이거나 경계에서 dilation 이내인지.
    static func contains(_ point: CGPoint, polygons: [[CGPoint]], dilation: CGFloat) -> Bool {
        containment(polygons: polygons, dilation: dilation)(point)
    }

    /// contains와 같은 판정. 경로를 한 번만 만들어 점 여러 개를 물을 때 쓴다.
    static func containment(polygons: [[CGPoint]], dilation: CGFloat) -> (CGPoint) -> Bool {
        let paths: [CGPath] = polygons.filter { $0.count >= minimumPolygonPoints }.flatMap { polygon -> [CGPath] in
            let path = CGMutablePath()
            path.addLines(between: polygon)
            path.closeSubpath()
            guard dilation > 0 else { return [path] }
            let stroked = path.copy(strokingWithWidth: dilation * 2, lineCap: .round, lineJoin: .round, miterLimit: 1)
            return [path, stroked]
        }
        return { point in paths.contains { $0.contains(point) } }
    }

    private static func featherRadius(_ face: FaceGeometry, _ extent: CGRect, _ tuning: RenderTuning) -> CGFloat {
        max(CGFloat(tuning.skinBlurMinimumRadius), faceWidth(face, extent: extent) * CGFloat(tuning.skinMaskFeather))
    }

    private static func average(_ image: CIImage, in rect: CGRect) -> CIImage {
        image.applyingFilter("CIAreaAverage", parameters: [kCIInputExtentKey: CIVector(cgRect: rect)])
            .clampedToExtent()
    }

    private static func landmarkPolygon(_ face: FaceGeometry, _ landmark: FaceLandmark, _ extent: CGRect)
        -> [CGPoint]?
    {
        guard let points = face.landmarks[landmark], points.count >= minimumPolygonPoints else { return nil }
        return points.map { CGPoint(x: extent.minX + $0.x * extent.width, y: extent.minY + $0.y * extent.height) }
    }

    private static func upperFeaturePoints(_ face: FaceGeometry, _ extent: CGRect) -> [CGPoint] {
        let brows = [FaceLandmark.leftEyebrow, .rightEyebrow].compactMap { landmarkPolygon(face, $0, extent) }
        if !brows.isEmpty {
            return brows.flatMap { $0 }
        }
        let eyes = [FaceLandmark.leftEye, .rightEye].compactMap { landmarkPolygon(face, $0, extent) }
        if !eyes.isEmpty {
            return eyes.flatMap { $0 }
        }
        let box = pixelRect(face.boundingBox, in: extent)
        return [CGPoint(x: box.midX, y: box.maxY)]
    }

    private static func fallbackSkinEllipse(_ face: FaceGeometry, _ extent: CGRect, _ tuning: RenderTuning)
        -> [CGPoint]
    {
        let box = pixelRect(face.boundingBox, in: extent)
        let inset = box.insetBy(
            dx: box.width * CGFloat(tuning.skinFaceInsetX), dy: box.height * CGFloat(tuning.skinFaceInsetY))
        return ellipsePolygon(in: inset)
    }

    private static func ellipsePolygon(in rect: CGRect) -> [CGPoint] {
        (0..<ellipseSegments).map { step in
            let angle = 2 * Double.pi * Double(step) / Double(ellipseSegments)
            return CGPoint(
                x: rect.midX + rect.width / 2 * CGFloat(cos(angle)),
                y: rect.midY + rect.height / 2 * CGFloat(sin(angle)))
        }
    }

    private static func boundingRect(_ points: [CGPoint]) -> CGRect {
        guard let first = points.first else { return .null }
        var rect = CGRect(origin: first, size: .zero)
        for point in points.dropFirst() {
            rect = rect.union(CGRect(origin: point, size: .zero))
        }
        return rect
    }

    private static func centroid(_ points: [CGPoint]) -> CGPoint {
        let count = CGFloat(max(1, points.count))
        let sum = points.reduce(CGPoint.zero) { CGPoint(x: $0.x + $1.x, y: $0.y + $1.y) }
        return CGPoint(x: sum.x / count, y: sum.y / count)
    }

    private static func offset(_ point: CGPoint, from origin: CGPoint) -> CGPoint {
        CGPoint(x: point.x - origin.x, y: point.y - origin.y)
    }

    private static func dot(_ a: CGPoint, _ b: CGPoint) -> CGFloat {
        a.x * b.x + a.y * b.y
    }
}
