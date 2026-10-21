import CoreImage
import MellowShared
import XCTest

@testable import MellowRendering

/// 점 지우기 하위 단계(스펙 G5 4.4).
/// 합성 얼굴을 2배로 키워(얼굴 폭 560px) 피부 질감 위에 단단한 원을 심고 SkinStage로 렌더해 잰다.
/// 512 그대로면 얼굴 폭 0.3%(모공)가 1픽셀보다 작아 형태 필터가 아무 일도 하지 않는다(미리보기 얼굴은 400px 이상).
final class SpotRemovalTests: XCTestCase {
    typealias Support = RenderingTestSupport

    enum Bounds {
        /// 합성 얼굴 확대 배율.
        static let scale: CGFloat = 2
        static let size = CGFloat(SyntheticFace.size) * scale
        static let faceWidth = SyntheticFace.box.width * scale
        static let spotRadiusFraction: CGFloat = 0.01
        /// 모공 크기 점의 반지름(얼굴 폭 비율).
        /// 형태 필터가 반지름을 내림하므로 모공 대역은 반지름 내림(560 × 0.3% = 1.68 → 1픽셀) 이하의 점이다.
        /// 그래서 1픽셀 반지름 점(560px 얼굴의 0.18%)을 심는다(스펙 G5 4.4, G5-2 구현 중 변경).
        static let poreRadiusFraction: CGFloat = 1 / (SyntheticFace.box.width * scale)
        static let darkFactor = 0.85
        static let brightFactor = 1.10
        /// 얕은 점(상대 깊이 3%).
        static let shallowFactor = 0.97
        static let spotRecovery = 0.7
        static let poreRemaining = 0.9
        static let strengthGap = 0.1
        /// 밝은 점 빼기를 끈 기본에서 밝은 점 평균 회복률 상한.
        static let brightLeftRecovery = 0.3
        /// 밝은 점 빼기를 켤 때의 배율.
        static let brightAmountOn = 1.0
        static let weakStrength = 0.3
        /// 채움 비율이 1보다 작은 강도(spotFullFillStrength 아래).
        static let partialFillStrength = 0.15
        /// 콧구멍 띠 안 표본 높이(코 다각형 높이 비율).
        static let nostrilSampleFraction = 0.15
        /// 콧구멍 띠가 바뀌어도 되는 바이트.
        static let nostrilTolerance = 1
        /// 얼굴 마스크 영역 밖 표본까지의 여유(픽셀).
        static let outsideMargin: CGFloat = 2
        /// 회복률을 재는 원(심은 원 반지름 배수).
        static let discScale: CGFloat = 0.65
        /// 512 합성 얼굴 좌표의 심은 점(볼 둘, 미간).
        /// 강도·영역 밖·대상 얼굴 테스트가 쓴다.
        static let spotCenters = [CGPoint(x: 200, y: 200), CGPoint(x: 310, y: 210), CGPoint(x: 256, y: 300)]
        /// 회복률을 재는 볼·이마 격자의 열(x)과 행(y), 512 합성 얼굴 좌표.
        /// 합성 질감의 얼룩(흐림 16px)이 점과 붙으면 한 점의 회복률이 0.46~0.94로 흩어져 격자 평균으로 잰다.
        static let gridColumns: [CGFloat] = [180, 200, 220, 300, 320, 340]
        static let gridRows: [CGFloat] = [200, 225, 380]
        static let poreCenters = [CGPoint(x: 230, y: 240), CGPoint(x: 290, y: 250)]
        /// 사진 네 귀퉁이에서 들어온 거리(픽셀).
        static let cornerInset: CGFloat = 4
    }

    private var extent: CGRect { CGRect(x: 0, y: 0, width: Bounds.size, height: Bounds.size) }
    private let spotRadius = Bounds.faceWidth * Bounds.spotRadiusFraction
    private let poreRadius = Bounds.faceWidth * Bounds.poreRadiusFraction
    private var spotDisc: CGFloat { spotRadius * Bounds.discScale }

    private static func scaled(_ point: CGPoint) -> CGPoint {
        CGPoint(x: point.x * Bounds.scale, y: point.y * Bounds.scale)
    }

    private var spotCenters: [CGPoint] { Bounds.spotCenters.map(Self.scaled) }
    private var gridCenters: [CGPoint] {
        Bounds.gridColumns.flatMap { x in Bounds.gridRows.map { y in Self.scaled(CGPoint(x: x, y: y)) } }
    }
    private var poreCenters: [CGPoint] { Bounds.poreCenters.map(Self.scaled) }

    /// 2배 합성 얼굴(특징점은 정규화 좌표라 그대로다).
    private func base() -> (image: CIImage, face: FaceGeometry) {
        let synthetic = SyntheticFace.make()
        let image = synthetic.image.transformed(by: CGAffineTransform(scaleX: Bounds.scale, y: Bounds.scale))
            .cropped(to: extent)
        return (image, synthetic.face)
    }

    private func planted(_ factor: Double, centers: [CGPoint], radiusFraction: CGFloat) throws -> (
        image: CIImage, face: FaceGeometry
    ) {
        let source = base()
        let spotted = SyntheticDefect.spotted(
            source.image, centers: centers, radius: Bounds.faceWidth * radiusFraction, factor: factor, extent: extent)
        return (CIImage(cgImage: try Support.renderer.makeCGImage(spotted)), source.face)
    }

    private func render(_ image: CIImage, face: FaceGeometry, spots: Double, tuning: RenderTuning = RenderTuning())
        throws -> PixelGrid
    {
        var recipe = EditRecipe()
        recipe.portrait.skin.spots = spots
        let context = RenderContext(
            extent: image.extent, recipe: recipe, analysis: PhotoAnalysis(faces: [face]), tuning: tuning)
        return try Support.grid(SkinStage().apply(image, in: context))
    }

    private func discLuma(_ grid: PixelGrid, at center: CGPoint, radius: CGFloat) -> Double {
        Support.discLuma(grid, at: center, radius: radius)
    }

    /// 같은 레시피로 렌더한 깨끗한 사진과 심은 사진.
    private struct Pair {
        let clean: PixelGrid
        let cleanAfter: PixelGrid
        let before: PixelGrid
        let after: PixelGrid
    }

    /// 심은 결함(원 안 가중 휘도, 깨끗한 사진 대비)이 렌더 뒤에 남은 비율.
    /// 렌더 뒤 결함은 깨끗한 사진을 같은 레시피로 렌더한 결과와 비교한다.
    /// 점 지우기는 합성 질감의 얼룩(흐림 16px)도 조금 채우거나 깎으므로 그 몫을 빼고 심은 결함만 본다.
    /// 회복률은 1 − 이 값이다.
    private func remaining(_ pair: Pair, at center: CGPoint, radius: CGFloat) throws -> Double {
        let planted =
            discLuma(pair.before, at: center, radius: radius) - discLuma(pair.clean, at: center, radius: radius)
        let after = discLuma(pair.after, at: center, radius: radius)
        let left = after - discLuma(pair.cleanAfter, at: center, radius: radius)
        guard abs(planted) > 0 else { return 0 }
        return left / planted
    }

    private func pair(
        _ factor: Double, centers: [CGPoint], radiusFraction: CGFloat, spots: Double,
        tuning: RenderTuning = RenderTuning()
    ) throws -> Pair {
        let cleanImage = CIImage(cgImage: try Support.renderer.makeCGImage(base().image))
        let defective = try planted(factor, centers: centers, radiusFraction: radiusFraction)
        let face = defective.face
        return Pair(
            clean: try Support.grid(cleanImage),
            cleanAfter: try render(cleanImage, face: face, spots: spots, tuning: tuning),
            before: try Support.grid(defective.image),
            after: try render(defective.image, face: face, spots: spots, tuning: tuning))
    }

    /// 격자 점들의 평균 회복률(1 − 남은 비율).
    private func meanRecovery(_ pair: Pair) throws -> Double {
        var total = 0.0
        for center in gridCenters {
            let recovered = try 1 - remaining(pair, at: center, radius: spotDisc)
            total += recovered
        }
        return total / Double(gridCenters.count)
    }

    func testSpotRemovalFillsSpotsLargerThanPoresOnly() throws {
        let fraction = Bounds.spotRadiusFraction
        let dark = try pair(Bounds.darkFactor, centers: gridCenters, radiusFraction: fraction, spots: 1)
        let darkMean = try meanRecovery(dark)
        XCTAssertGreaterThanOrEqual(darkMean, Bounds.spotRecovery, "어두운 점 평균 회복률")
        // 기본은 어두운 점만 채운다(spotBrightAmount 0, 스펙 G5 4.1 G5-2 구현 중 변경).
        let bright = try pair(Bounds.brightFactor, centers: gridCenters, radiusFraction: fraction, spots: 1)
        XCTAssertLessThanOrEqual(try meanRecovery(bright), Bounds.brightLeftRecovery, "기본은 밝은 점을 남긴다")
        // 밝은 점 빼기를 켜면 같은 식으로 채운다(커널 경로 검사).
        var withBright = RenderTuning()
        withBright.spotBrightAmount = Bounds.brightAmountOn
        let brightOn = try pair(
            Bounds.brightFactor, centers: gridCenters, radiusFraction: fraction, spots: 1, tuning: withBright)
        XCTAssertGreaterThanOrEqual(try meanRecovery(brightOn), Bounds.spotRecovery, "밝은 점 빼기를 켜면 채운다")
        let pores = try pair(
            Bounds.darkFactor, centers: poreCenters, radiusFraction: Bounds.poreRadiusFraction, spots: 1)
        for center in poreCenters {
            let left = try remaining(pores, at: center, radius: poreRadius)
            XCTAssertGreaterThanOrEqual(left, Bounds.poreRemaining, "모공 크기 점은 남는다 \(center)")
        }
    }

    func testSpotStrengthMovesTheDepthThreshold() throws {
        let fraction = Bounds.spotRadiusFraction
        let full = try pair(Bounds.shallowFactor, centers: spotCenters, radiusFraction: fraction, spots: 1)
        let weak = try pair(
            Bounds.shallowFactor, centers: spotCenters, radiusFraction: fraction, spots: Bounds.weakStrength)
        let center = spotCenters[0]
        let fullRecovery = try 1 - remaining(full, at: center, radius: spotDisc)
        let weakRecovery = try 1 - remaining(weak, at: center, radius: spotDisc)
        XCTAssertGreaterThanOrEqual(fullRecovery - weakRecovery, Bounds.strengthGap, "강도 1이 얕은 점을 더 채운다")
        let shallow = try planted(Bounds.shallowFactor, centers: spotCenters, radiusFraction: fraction)
        var recipe = EditRecipe()
        recipe.portrait.skin.spots = 0
        let context = RenderContext(
            extent: shallow.image.extent, recipe: recipe, analysis: PhotoAnalysis(faces: [shallow.face]),
            tuning: RenderTuning())
        let zero = try Support.bytes(SkinStage().apply(shallow.image, in: context))
        XCTAssertEqual(try Support.bytes(shallow.image), zero, "강도 0은 바이트 동일")
        let limits = SpotRemoval.thresholds(strength: Bounds.weakStrength, tuning: RenderTuning())
        XCTAssertEqual(limits.fill, 1, accuracy: 1e-12, "0.3부터 문턱을 넘은 점은 완전히 채운다")
        XCTAssertLessThan(SpotRemoval.thresholds(strength: Bounds.partialFillStrength, tuning: RenderTuning()).fill, 1)
    }

    func testDarkOnlySkipsTheBrightPassesAndKeepsTheBytes() throws {
        let bright = try planted(Bounds.brightFactor, centers: gridCenters, radiusFraction: Bounds.spotRadiusFraction)
        let tuning = RenderTuning()
        XCTAssertEqual(tuning.spotBrightAmount, 0, "기본은 어두운 점만")
        let bounds = FaceRegions.maskBounds(face: bright.face, extent: extent, tuning: tuning)
        let width = Double(Bounds.faceWidth)
        let spot = width * tuning.spotRadiusFraction
        let pore = max(tuning.skinBlurMinimumRadius, width * tuning.spotPoreRadiusFraction)
        let limits = SpotRemoval.thresholds(strength: 1, tuning: tuning)
        func correction(includesBright: Bool, tuning: RenderTuning) throws -> [UInt8] {
            try Support.bytes(
                SpotRemoval.correction(
                    bright.image, bounds: bounds, spot: spot, pore: pore, limits: limits, tuning: tuning,
                    includesBright: includesBright))
        }
        let skipped = try correction(includesBright: false, tuning: tuning)
        XCTAssertEqual(skipped, try correction(includesBright: true, tuning: tuning), "밝은 점 형태 필터를 건너뛰어도 같은 바이트")
        var withBright = tuning
        withBright.spotBrightAmount = Bounds.brightAmountOn
        XCTAssertNotEqual(skipped, try correction(includesBright: true, tuning: withBright), "켜면 밝은 점 입력이 쓰인다")
    }

    func testSpotRemovalLeavesPixelsOutsideTheFaceBoundsUntouched() throws {
        let dark = try planted(Bounds.darkFactor, centers: spotCenters, radiusFraction: Bounds.spotRadiusFraction)
        let before = try Support.grid(dark.image)
        let after = try render(dark.image, face: dark.face, spots: 1)
        let bounds = FaceRegions.maskBounds(face: dark.face, extent: extent, tuning: RenderTuning())
        let far = Bounds.size - Bounds.cornerInset
        let near = Bounds.cornerInset
        let corners = [
            CGPoint(x: near, y: near), CGPoint(x: far, y: near), CGPoint(x: near, y: far), CGPoint(x: far, y: far),
        ]
        let beside = CGPoint(x: bounds.maxX + Bounds.outsideMargin, y: bounds.midY)
        for point in corners + [beside] {
            XCTAssertEqual(before.rgba(point), after.rgba(point), "영역 밖 \(point) 바이트 동일")
        }
        var changedOutside = 0
        let side = Int(Bounds.size)
        for y in 0..<side {
            for x in 0..<side {
                let point = CGPoint(x: x, y: y)
                guard !bounds.contains(point), before.rgba(point) != after.rgba(point) else { continue }
                changedOutside += 1
            }
        }
        XCTAssertEqual(changedOutside, 0, "얼굴 마스크 영역 밖은 한 픽셀도 바뀌지 않는다")
        let nose = try XCTUnwrap(dark.face.bounds(of: .nose))
        let nostril = CGPoint(
            x: nose.midX * Double(extent.width),
            y: (nose.minY + nose.height * Bounds.nostrilSampleFraction) * Double(extent.height))
        let delta = abs(Int(before.red(nostril)) - Int(after.red(nostril)))
        XCTAssertLessThanOrEqual(delta, Bounds.nostrilTolerance, "콧구멍 띠는 그대로")
    }

    /// SkinStageTests.testTargetFaceRefinesOnlyThatFace와 같은 두 얼굴 구성에 개인 층 spots = 1.
    /// 2배 사진을 반으로 줄여 놓으므로 얼굴 폭은 280px이다.
    func testSpotRemovalRefinesOnlyTheTargetFace() throws {
        let dark = try planted(Bounds.darkFactor, centers: spotCenters, radiusFraction: Bounds.spotRadiusFraction)
        let side = Bounds.size
        let half = CGAffineTransform(scaleX: 0.5, y: 0.5)
        let left = dark.image.transformed(by: half.concatenating(CGAffineTransform(translationX: 0, y: side / 4)))
        let right = dark.image.transformed(
            by: half.concatenating(CGAffineTransform(translationX: side / 2, y: side / 4)))
        let composed = left.composited(over: right).composited(over: CIImage(color: .gray)).cropped(to: extent)
        let image = CIImage(cgImage: try Support.renderer.makeCGImage(composed))
        let faces = [
            dark.face.transformed(scale: 0.5, offset: NormalizedPoint(x: 0, y: 0.25)),
            dark.face.transformed(scale: 0.5, offset: NormalizedPoint(x: 0.5, y: 0.25)),
        ]
        var recipe = EditRecipe()
        recipe.portrait.skin.spots = 1
        recipe = Support.restricted(recipe, toFace: 0, of: faces)
        let context = RenderContext(extent: image.extent, recipe: recipe, faces: faces, tuning: RenderTuning())
        let before = try Support.grid(image)
        let after = try Support.grid(SkinStage().apply(image, in: context))
        var leftChanged = 0
        var rightChanged = 0
        let pixels = Int(side)
        for y in 0..<pixels {
            for x in 0..<pixels {
                let point = CGPoint(x: x, y: y)
                guard after.rgba(point) != before.rgba(point) else { continue }
                if x < pixels / 2 {
                    leftChanged += 1
                } else {
                    rightChanged += 1
                }
            }
        }
        XCTAssertGreaterThan(leftChanged, 0, "고른 얼굴의 점은 지워진다")
        XCTAssertEqual(rightChanged, 0, "다른 얼굴은 한 픽셀도 바뀌지 않는다")
    }
}
