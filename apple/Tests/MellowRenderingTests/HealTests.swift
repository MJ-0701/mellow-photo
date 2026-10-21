import CoreImage
import MellowShared
import XCTest

@testable import MellowRendering

/// 색 맞춤 복구(스펙 G5 5.1).
/// 원본 패치의 질감만 옮기고 밝기·색은 대상 둘레 고리에 맞춘다.
final class HealTests: XCTestCase {
    typealias Support = RenderingTestSupport

    enum Bounds {
        /// 복구 원 안 평균 Y와 고리 평균 Y의 차 상한(8비트).
        static let residual = 1.0
        /// 복구 원 안 fine 분산 ÷ 원본 패치 fine 분산 하한.
        static let textureRatio = 0.8
        static let size = 512
        static let radius: CGFloat = 24
        /// 왼쪽 0.4 → 오른쪽 0.6 선형 휘도 경사(선형 공간).
        static let gradientLow = 0.4
        static let gradientHigh = 0.6
        /// 원본을 대상에서 왼쪽으로 떨어뜨리는 거리(복구 반지름 배수).
        static let sourceOffset: CGFloat = 2.5
        /// 원반 평균을 재는 안쪽 반지름(복구 반지름 배수). MaskBuilder 타원이 완전히 덮는 범위다.
        static let discFraction: CGFloat = 0.65
        /// 고리 평균을 재는 바깥 반지름(복구 반지름 배수).
        static let ringOuterFraction: CGFloat = 1.5
        /// 질감을 재는 정사각형 반 변(복구 반지름 배수).
        static let patchHalfFraction: CGFloat = 0.6
        static let fineRadius = 1.5
        static let midRadius = 6.0
        /// 배율 상한을 재는 어두운 원본 정사각형 한 변과 감마 밝기(선형 약 0.03, healLumaFloor보다 크다).
        static let darkSide: CGFloat = 80
        static let darkLevel = 0.2
        /// 배율 상한 비교의 상대 허용 오차(원본 저주파가 둘레 밝은 피부를 조금 섞는다).
        static let gainTolerance = 0.1
        /// 배율 상한이 실제로 걸렸음을 보이는 여유. 고리 밝기가 상한 결과보다 이만큼 더 밝아야 한다.
        static let clampMargin = 1.2
        /// 중심에서 밝기를 재는 정사각형 반 변(픽셀).
        static let probeHalf: CGFloat = 3
    }

    /// 피부 질감 위에 수평 휘도 경사를 곱한 입력.
    private func gradientSkin() throws -> CIImage {
        let texture = Support.skinTexture(size: Bounds.size)
        let low = CIColor(red: Bounds.gradientLow, green: Bounds.gradientLow, blue: Bounds.gradientLow)
        let high = CIColor(red: Bounds.gradientHigh, green: Bounds.gradientHigh, blue: Bounds.gradientHigh)
        let ramp = CIFilter(
            name: "CILinearGradient",
            parameters: [
                "inputPoint0": CIVector(x: 0, y: 0), "inputPoint1": CIVector(x: CGFloat(Bounds.size), y: 0),
                "inputColor0": low, "inputColor1": high,
            ])!.outputImage!.cropped(to: texture.extent)
        let shaded = texture.applyingFilter("CIMultiplyCompositing", parameters: [kCIInputBackgroundImageKey: ramp])
        return CIImage(cgImage: try Support.renderer.makeCGImage(shaded.cropped(to: texture.extent)))
    }

    private func context(_ image: CIImage) -> RenderContext {
        RenderContext(extent: image.extent, recipe: EditRecipe(), analysis: PhotoAnalysis(), tuning: RenderTuning())
    }

    private func spot(center: CGPoint, source: CGPoint, extent: CGRect) -> RetouchSpot {
        RetouchSpot(
            x: Double(center.x / extent.width), y: Double(center.y / extent.height),
            sourceX: Double(source.x / extent.width), sourceY: Double(source.y / extent.height),
            radius: Double(Bounds.radius / min(extent.width, extent.height)))
    }

    /// 화면 바이트의 BT.601 휘도 평균. inner ≤ 거리 < outer인 픽셀만 본다.
    private func ringLuma(_ grid: PixelGrid, center: CGPoint, inner: CGFloat, outer: CGFloat) -> Double {
        var sum = 0.0
        var count = 0.0
        for y in 0..<grid.height {
            for x in 0..<grid.width {
                let distance = hypot(CGFloat(x) - center.x, CGFloat(y) - center.y)
                guard distance >= inner, distance < outer else { continue }
                let rgba = grid.rgba(CGPoint(x: x, y: y))
                let red = 0.299 * Double(rgba[0])
                let green = 0.587 * Double(rgba[1])
                let blue = 0.114 * Double(rgba[2])
                sum += red + green + blue
                count += 1
            }
        }
        return sum / max(count, 1)
    }

    /// 중심 둘레 작은 정사각형의 선형 휘도 평균.
    private func linearLuma(_ image: CIImage, at center: CGPoint) throws -> Double {
        let half = Bounds.probeHalf
        let probe = CGRect(x: center.x - half, y: center.y - half, width: half * 2, height: half * 2)
        let values = try Support.luma(image.cropped(to: probe))
        return values.reduce(0, +) / Double(max(values.count, 1))
    }

    func testHealMatchesPatchToneToSurroundingRingOnAGradient() throws {
        let image = try gradientSkin()
        let center = CGPoint(x: 256, y: 256)
        let radius = Bounds.radius
        // 원본은 왼쪽으로 2.5r(60px) 떨어진 더 어두운 피부다.
        let source = CGPoint(x: center.x - radius * Bounds.sourceOffset, y: center.y)
        let retouch = spot(center: center, source: source, extent: image.extent)
        let healed = try Support.grid(LocalEditStage.applySpot(retouch, to: image, context: context(image)))
        let inside = ringLuma(healed, center: center, inner: 0, outer: radius * Bounds.discFraction)
        let ring = ringLuma(healed, center: center, inner: radius, outer: radius * Bounds.ringOuterFraction)
        XCTAssertLessThanOrEqual(abs(inside - ring), Bounds.residual, "복구 원 안 밝기가 둘레 고리와 같다(원반 없음)")
        let before = try Support.grid(image)
        let beforeInside = ringLuma(before, center: center, inner: 0, outer: radius * Bounds.discFraction)
        XCTAssertNotEqual(beforeInside, inside, "복구가 실제로 픽셀을 바꿨다")
    }

    func testHealKeepsSourceTextureAndNeverExceedsGainLimit() throws {
        let image = try gradientSkin()
        let extent = image.extent
        let center = CGPoint(x: 256, y: 256)
        let radius = Bounds.radius
        let sourceCenter = CGPoint(x: center.x - radius * Bounds.sourceOffset, y: center.y)
        let healed = LocalEditStage.applySpot(
            spot(center: center, source: sourceCenter, extent: extent), to: image, context: context(image))
        let half = radius * Bounds.patchHalfFraction
        let patch = CGRect(x: center.x - half, y: center.y - half, width: half * 2, height: half * 2)
        let sourcePatch = CGRect(x: sourceCenter.x - half, y: sourceCenter.y - half, width: half * 2, height: half * 2)
        let healedFine = try Support.bandVariances(
            healed, in: patch, fineRadius: Bounds.fineRadius, midRadius: Bounds.midRadius
        ).fine
        let sourceFine = try Support.bandVariances(
            image, in: sourcePatch, fineRadius: Bounds.fineRadius, midRadius: Bounds.midRadius
        ).fine
        XCTAssertGreaterThanOrEqual(healedFine / sourceFine, Bounds.textureRatio, "원본 질감이 옮겨진다")
        // 배율 상한: 둘레보다 훨씬 어두운 원본은 maxGain배까지만 밝아진다.
        let level = Bounds.darkLevel
        let darkSquare = CIImage(color: CIColor(red: level, green: level, blue: level))
            .cropped(to: CGRect(x: 0, y: 0, width: Bounds.darkSide, height: Bounds.darkSide))
        let darkGraph = darkSquare.composited(over: image).cropped(to: extent)
        let dark = CIImage(cgImage: try Support.renderer.makeCGImage(darkGraph))
        let darkCenter = CGPoint(x: Bounds.darkSide / 2, y: Bounds.darkSide / 2)
        let fromDark = LocalEditStage.applySpot(
            spot(center: center, source: darkCenter, extent: extent), to: dark, context: context(dark))
        let sourceLuma = try linearLuma(dark, at: darkCenter)
        let healedLuma = try linearLuma(fromDark, at: center)
        let ringLinear = try linearLuma(dark, at: CGPoint(x: center.x + radius * Bounds.ringOuterFraction, y: center.y))
        let maxGain = RenderTuning().healMaxGain
        let limit = sourceLuma * maxGain
        XCTAssertGreaterThan(ringLinear, limit * Bounds.clampMargin, "둘레가 상한보다 밝아 배율 상한이 걸리는 입력이다")
        XCTAssertEqual(healedLuma, limit, accuracy: limit * Bounds.gainTolerance, "어두운 원본은 배율 상한까지만 밝아진다")
    }
}
