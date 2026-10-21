import CoreImage
import MellowShared
import XCTest

@testable import MellowRendering

/// 모양 워프·보호 테스트 도우미. RenderingTestSupport는 다른 세션이 고칠 수 있어 여기에 둔다.
enum ShapeTestSupport {
    /// 이동량 지도를 색 관리 없이 float로 읽는 문맥. 작업 색공간은 Renderer와 같다.
    /// Renderer.readPixels는 선형 sRGB로 바꿔 읽어 음수 이동이 잘릴 수 있다.
    private static let fieldContext = CIContext(options: [
        .workingColorSpace: CGColorSpace(name: CGColorSpace.extendedLinearSRGB)!
    ])
    /// 픽셀 하나의 RGBAf 바이트 수.
    private static let pixelBytes = 4 * MemoryLayout<Float>.size

    /// float 지도에서 점마다 (dx, dy)를 읽는다. 점이 든 픽셀(중심 = 내림 + 0.5)의 값이다.
    static func fieldVectors(_ field: CIImage, at points: [CGPoint]) throws -> [CGVector] {
        points.map { point in
            var pixel = [Float](repeating: 0, count: 4)
            let bounds = CGRect(x: point.x.rounded(.down), y: point.y.rounded(.down), width: 1, height: 1)
            pixel.withUnsafeMutableBytes { buffer in
                fieldContext.render(
                    field, toBitmap: buffer.baseAddress!, rowBytes: pixelBytes, bounds: bounds, format: .RGBAf,
                    colorSpace: nil)
            }
            return CGVector(dx: CGFloat(pixel[0]), dy: CGFloat(pixel[1]))
        }
    }

    /// 지도의 한 점 이동 크기.
    static func shift(_ field: CIImage, at point: CGPoint) throws -> CGFloat {
        let vector = try XCTUnwrap(fieldVectors(field, at: [point]).first)
        return hypot(vector.dx, vector.dy)
    }

    /// standingBody에서 팔꿈치·손목만 옮긴 몸. 나머지 관절은 standingBody 그대로다.
    /// 점은 extent 픽셀이고 extent로 나눠 정규화한다.
    static func body(
        _ base: BodyGeometry, moving joints: [BodyJoint: CGPoint], extent: CGRect
    ) -> BodyGeometry {
        var moved = base.joints
        var confidence = base.confidence
        for (joint, point) in joints {
            moved[joint] = NormalizedPoint(
                x: Double((point.x - extent.minX) / extent.width), y: Double((point.y - extent.minY) / extent.height))
            confidence[joint] = 1
        }
        return BodyGeometry(joints: moved, confidence: confidence)
    }

    /// a에서 b로 t만큼 간 점.
    static func lerp(_ a: CGPoint, _ b: CGPoint, _ t: CGFloat) -> CGPoint {
        CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t)
    }

    /// point를 direction(단위 벡터) 쪽으로 distance만큼 옮긴다.
    static func offset(_ point: CGPoint, _ direction: CGVector, _ distance: CGFloat) -> CGPoint {
        CGPoint(x: point.x + direction.dx * distance, y: point.y + direction.dy * distance)
    }
}

/// float 이미지(이동량 지도·마스크)의 사각형 영역을 한 번에 읽은 값.
/// 좌표는 Core Image 픽셀(원점 왼쪽 아래)이고 색 관리 없이 읽어 음수 이동과 선형 마스크 값을 그대로 둔다.
/// 영역 밖이나 이미지가 없는 곳은 0이다.
struct FloatPatch {
    /// 읽은 영역(정수 픽셀 경계).
    let rect: CGRect
    private let width: Int
    private let height: Int
    private let values: [Float]
    /// 픽셀 하나의 채널 수(RGBA).
    private static let channels = 4

    /// image가 nil이면 모두 0인 영역이다.
    init(_ image: CIImage?, in rect: CGRect) {
        let bounds = rect.integral
        let columns = Int(bounds.width)
        let rows = Int(bounds.height)
        var buffer = [Float](repeating: 0, count: columns * rows * Self.channels)
        if let image, columns > 0, rows > 0 {
            let rowBytes = columns * Self.channels * MemoryLayout<Float>.size
            buffer.withUnsafeMutableBytes { bytes in
                ShapeTestSupport.floatContext.render(
                    image, toBitmap: bytes.baseAddress!, rowBytes: rowBytes, bounds: bounds, format: .RGBAf,
                    colorSpace: nil)
            }
        }
        self.rect = bounds
        width = columns
        height = rows
        values = buffer
    }

    /// 점이 든 픽셀(중심 = 내림 + 0.5)의 채널 값. 비트맵은 맨 위 행부터 저장한다.
    private func channel(_ index: Int, at point: CGPoint) -> CGFloat {
        let column = Int((point.x - rect.minX).rounded(.down))
        let row = Int((point.y - rect.minY).rounded(.down))
        guard column >= 0, column < width, row >= 0, row < height else { return 0 }
        let offset = ((height - 1 - row) * width + column) * Self.channels
        return CGFloat(values[offset + index])
    }

    /// 지도의 (dx, dy).
    func vector(at point: CGPoint) -> CGVector {
        CGVector(dx: channel(0, at: point), dy: channel(1, at: point))
    }

    /// 마스크의 빨강 채널(회색 마스크 값).
    func red(at point: CGPoint) -> CGFloat {
        channel(0, at: point)
    }

    /// 영역 안 모든 픽셀 중심.
    var pixelCenters: [CGPoint] {
        var result: [CGPoint] = []
        result.reserveCapacity(width * height)
        for row in 0..<height {
            for column in 0..<width {
                result.append(CGPoint(x: rect.minX + CGFloat(column) + 0.5, y: rect.minY + CGFloat(row) + 0.5))
            }
        }
        return result
    }
}

extension ShapeTestSupport {
    /// FloatPatch가 쓰는 문맥. fieldVectors와 같은 작업 색공간이다.
    static let floatContext = CIContext(options: [
        .workingColorSpace: CGColorSpace(name: CGColorSpace.extendedLinearSRGB)!
    ])

    /// 점에서 선분 a–b까지 거리.
    static func distance(from point: CGPoint, toSegment a: CGPoint, _ b: CGPoint) -> CGFloat {
        let ab = CGVector(dx: b.x - a.x, dy: b.y - a.y)
        let span = ab.dx * ab.dx + ab.dy * ab.dy
        let along = span > 0 ? ((point.x - a.x) * ab.dx + (point.y - a.y) * ab.dy) / span : 0
        let t = min(max(along, 0), 1)
        return hypot(point.x - (a.x + ab.dx * t), point.y - (a.y + ab.dy * t))
    }

    /// 1차원 제곱 거리 변환(Felzenszwalb). 입력은 칸마다 0(씨앗) 또는 무한대다.
    private static func squaredDistance1D(_ input: [Double]) -> [Double] {
        let count = input.count
        var output = [Double](repeating: .infinity, count: count)
        var vertices = [Int](repeating: 0, count: count)
        var bounds = [Double](repeating: 0, count: count + 1)
        var hull = -1
        for index in 0..<count where input[index].isFinite {
            if hull < 0 {
                hull = 0
                vertices[0] = index
                bounds[0] = -.infinity
                bounds[1] = .infinity
                continue
            }
            var crossing = 0.0
            repeat {
                let previous = vertices[hull]
                let rise = (input[index] + Double(index * index)) - (input[previous] + Double(previous * previous))
                crossing = rise / Double(2 * (index - previous))
                guard crossing <= bounds[hull] else { break }
                hull -= 1
            } while hull >= 0
            hull += 1
            vertices[hull] = index
            bounds[hull] = hull == 0 ? -.infinity : crossing
            bounds[hull + 1] = .infinity
        }
        guard hull >= 0 else { return output }
        var segment = 0
        for index in 0..<count {
            while bounds[segment + 1] < Double(index) {
                segment += 1
            }
            let vertex = vertices[segment]
            let gap = Double(index - vertex)
            output[index] = gap * gap + input[vertex]
        }
        return output
    }

    /// 씨앗 픽셀(inside가 true)까지의 유클리드 거리(픽셀). 행 우선, 원점 왼쪽 아래 행부터다.
    static func distanceToNearest(_ inside: [Bool], width: Int, height: Int) -> [Double] {
        var squared = [Double](repeating: .infinity, count: width * height)
        for row in 0..<height {
            let line = (0..<width).map { inside[row * width + $0] ? 0.0 : Double.infinity }
            let transformed = squaredDistance1D(line)
            for column in 0..<width {
                squared[row * width + column] = transformed[column]
            }
        }
        for column in 0..<width {
            let line = (0..<height).map { squared[$0 * width + column] }
            let transformed = squaredDistance1D(line)
            for row in 0..<height {
                squared[row * width + column] = transformed[row]
            }
        }
        return squared.map { $0.squareRoot() }
    }
}

/// 생성 체형 사진(Fixtures/body)을 앱과 같은 PhotoPipeline(실제 Vision 분석기 넷)으로 준비한 것.
/// 렌더와 같은 분석·같은 묶음(ShapeWarpStage.groups)·같은 지도(DisplacementWarp.field)로 잰다.
/// 사진마다 한 번만 준비해 나눠 쓴다.
final class RealBodyPhoto: @unchecked Sendable {
    let file: String
    let tuning = RenderTuning()
    let pipeline: PhotoPipeline
    /// 파이프라인 안 사진 ID.
    let id: PhotoID
    /// 파이프라인이 쓰는 미리보기와 같은 크기로 읽은 사진.
    let image: CIImage
    let analysis: PhotoAnalysis

    private static let lock = NSLock()
    nonisolated(unsafe) private static var cache: [String: RealBodyPhoto] = [:]

    private init(file: String, pipeline: PhotoPipeline, id: PhotoID, image: CIImage, analysis: PhotoAnalysis) {
        self.file = file
        self.pipeline = pipeline
        self.id = id
        self.image = image
        self.analysis = analysis
    }

    static func url(_ file: String) throws -> URL {
        try XCTUnwrap(Bundle.module.url(forResource: file, withExtension: nil, subdirectory: "Fixtures/body"))
    }

    /// 준비가 실패하면 그 테스트만 오류로 실패한다.
    static func prepared(_ file: String) async throws -> RealBodyPhoto {
        if let cached = lock.withLock({ cache[file] }) {
            return cached
        }
        let tuning = RenderTuning()
        let pipeline = PhotoPipeline(
            analyzer: VisionFaceAnalyzer(), personAnalyzer: VisionPersonAnalyzer(), bodyAnalyzer: VisionBodyAnalyzer(),
            instanceAnalyzer: VisionPersonInstanceAnalyzer(), tuning: tuning)
        let id = PhotoID()
        let location = try url(file)
        _ = try await pipeline.prepare(id, at: location)
        let stored = await pipeline.preparedAnalysis(id)
        let analysis = try XCTUnwrap(stored)
        let image = try ImageLoader().load(url: location, maxDimension: tuning.previewMaxDimension)
        let photo = RealBodyPhoto(file: file, pipeline: pipeline, id: id, image: image, analysis: analysis)
        lock.withLock { cache[file] = photo }
        return photo
    }

    var extent: CGRect { image.extent }
    /// 미리보기 px → 폰 px.
    var phoneScale: CGFloat { DisplayScale.phoneWidth / extent.width }

    func context(_ recipe: EditRecipe) -> RenderContext {
        RenderContext(extent: extent, recipe: recipe, analysis: analysis, tuning: tuning)
    }

    /// 렌더가 그리는 묶음 그대로.
    func groups(_ recipe: EditRecipe) -> [ShapeGroup] {
        ShapeWarpStage().groups(in: context(recipe))
    }

    /// 렌더가 샘플링하는 이동량 지도(보호 가중치 포함). 원소가 없으면 nil.
    func field(_ recipe: EditRecipe) throws -> CIImage? {
        try DisplacementWarp.shared.field(
            groups: groups(recipe), extent: extent, limit: tuning.shapeDisplacementLimit, tuning: tuning)
    }

    /// 지도 전체를 읽은 값.
    func fieldPatch(_ recipe: EditRecipe) throws -> FloatPatch {
        FloatPatch(try field(recipe), in: extent)
    }

    /// 묶음 원소의 limit 뒤 최대 이동(미리보기 px). 배경 보호 띠 폭의 기준이다.
    func largestShift(_ recipe: EditRecipe) -> CGFloat {
        let limit = tuning.shapeDisplacementLimit
        return groups(recipe).flatMap(\.primitives).map { $0.limited(to: limit).maxDisplacement }.max() ?? 0
    }

    /// 앱 미리보기와 같은 경로(PhotoPipeline.preview).
    func preview(_ recipe: EditRecipe) async throws -> CGImage {
        try await pipeline.preview(id, recipe: recipe)
    }

    /// 다른 입력(격자 합성)을 같은 분석으로 전체 파이프라인에 넘긴다.
    func render(_ recipe: EditRecipe, input: CIImage) throws -> CGImage {
        let output = try RenderPipeline.standard.render(input, context: context(recipe))
        return try RenderingTestSupport.renderer.makeCGImage(output)
    }

    func skeleton(_ body: Int) throws -> BodySkeleton {
        try XCTUnwrap(
            BodySkeleton(body: analysis.bodies[body], extent: extent, tuning: tuning), "\(file) 몸 \(body)의 두 어깨")
    }

    /// 사람 마스크를 extent에 늘린 것(흐림 없음).
    func placed(_ mask: CIImage) -> CIImage {
        BackgroundStage.personMask(mask, extent: extent, feather: 0)
    }

    /// 전체 인물 마스크를 extent로 읽은 값.
    func personMaskPatch() throws -> FloatPatch {
        FloatPatch(placed(try XCTUnwrap(analysis.personMask, "\(file) 인물 마스크")), in: extent)
    }

    /// 얼굴과 짝인 몸.
    func body(matching face: Int) throws -> Int {
        try XCTUnwrap(analysis.bodyFaceMatches.first { $0.value == face }?.key, "\(file) 얼굴 \(face)와 짝인 몸")
    }
}

extension ShapeTestSupport {
    /// 감마 BT.601 휘도(8비트).
    private static func luma(_ pixel: [UInt8]) -> Double {
        0.299 * Double(pixel[0]) + 0.587 * Double(pixel[1]) + 0.114 * Double(pixel[2])
    }

    /// weights(같은 해상도의 회색 마스크) 가중 평균 ΔY(8비트). 가중치 합이 0이면 0이다.
    static func weightedLumaDelta(_ before: PixelGrid, _ after: PixelGrid, weights: FloatPatch) -> Double {
        var total = 0.0
        var sum = 0.0
        for row in 0..<before.height {
            for column in 0..<before.width {
                let point = CGPoint(x: column, y: row)
                let weight = Double(weights.red(at: CGPoint(x: Double(column) + 0.5, y: Double(row) + 0.5)))
                guard weight > 0 else { continue }
                total += weight
                sum += weight * (luma(after.rgba(point)) - luma(before.rgba(point)))
            }
        }
        return total > 0 ? sum / total : 0
    }

    /// 폰 배율 격자에서 include(그 픽셀 중심의 미리보기 좌표)가 참인 픽셀 중 바뀐(세 채널 중 최대 |Δ| ≥ 4) 비율.
    /// 포함 픽셀이 없으면 0이다.
    static func changedFraction(
        _ before: PixelGrid, _ after: PixelGrid, phoneScale: CGFloat, include: (CGPoint) -> Bool
    ) -> Double {
        var total = 0
        var changed = 0
        for row in 0..<before.height {
            for column in 0..<before.width {
                let preview = CGPoint(x: (CGFloat(column) + 0.5) / phoneScale, y: (CGFloat(row) + 0.5) / phoneScale)
                guard include(preview) else { continue }
                total += 1
                let point = CGPoint(x: column, y: row)
                let a = before.rgba(point)
                let b = after.rgba(point)
                if (0..<3).contains(where: { abs(Int(a[$0]) - Int(b[$0])) >= DisplayScale.defaultMinimumDelta }) {
                    changed += 1
                }
            }
        }
        return total > 0 ? Double(changed) / Double(total) : 0
    }
}
