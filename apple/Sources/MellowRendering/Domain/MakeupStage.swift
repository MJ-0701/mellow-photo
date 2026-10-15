import CoreImage
import MellowShared

/// 메이크업. 대상 얼굴마다 FaceRegions 마스크 안에서만 색을 얹고 마스크 밖 픽셀은 그대로 둔다(스펙 6).
/// 섞기는 Core Image 기본 섞기 모드를 작업 색공간에서 하고, 강도 = 부위 강도 × 부위 최대 불투명도(RenderTuning)로 원본과 섞는다.
/// 강도는 AdjustmentRange.unit으로 직접 자른다. 프리셋·일괄 적용 값은 편집 규칙의 클램프를 거치지 않는다.
/// 색은 카탈로그의 그 부위 팔레트에서만 찾고, 없거나 모르는 색이면 그 부위만 건너뛴다(오류 아님).
struct MakeupStage: RenderStage {
    let name = "makeup"

    static let softLight = "CISoftLightBlendMode"
    static let multiply = "CIMultiplyBlendMode"
    static let screen = "CIScreenBlendMode"

    func apply(_ image: CIImage, in context: RenderContext) throws -> CIImage {
        let makeup = Self.clamped(context.recipe.makeup)
        guard makeup.hasEffect, !context.targetFaces.isEmpty else { return image }
        var result = image
        for face in context.targetFaces {
            result = paintLips(result, face: face, tint: makeup.lip, context: context)
        }
        return result.cropped(to: context.extent)
    }

    /// 강도를 0…1로 자른다. 유한하지 않은 값은 RenderPipeline이 먼저 거절한다.
    static func clamped(_ makeup: MakeupAdjustments) -> MakeupAdjustments {
        var copy = makeup
        for part in MakeupPart.allCases {
            copy.setIntensity(AdjustmentRange.clamped(makeup.intensity(of: part), to: AdjustmentRange.unit), of: part)
        }
        return copy
    }

    /// 카탈로그의 부위 팔레트 색으로 만든 단색 이미지. 강도 0, 고르지 않음, 모르는 색(다른 부위 색 포함)이면 nil이다.
    static func colorImage(_ tint: MakeupTint, part: MakeupPart, context: RenderContext) -> CIImage? {
        guard tint.intensity > 0, let color = context.makeupCatalog.color(id: tint.colorID, for: part) else {
            return nil
        }
        return solid(color.rgb)
    }

    /// sRGB 감마 값 rgb(성분이 모자라면 0)의 무한 크기 단색 이미지. Core Image가 작업 색공간으로 바꾼다.
    static func solid(_ rgb: [Double]) -> CIImage {
        func component(_ index: Int) -> Double { rgb.indices.contains(index) ? rgb[index] : 0 }
        return CIImage(color: CIColor(red: component(0), green: component(1), blue: component(2)))
    }

    /// color를 image 위에 섞기 모드 mode로 얹은 결과를 bounds 안에서만 만든다.
    static func blended(_ image: CIImage, with color: CIImage, mode: String, in bounds: CGRect) -> CIImage {
        color.cropped(to: bounds).applyingFilter(mode, parameters: [kCIInputBackgroundImageKey: image])
            .cropped(to: bounds)
    }

    /// foreground를 마스크 × amount 비율로 image 위에 섞는다. 마스크가 정확히 0인 곳(bounds 밖 포함)은 image 바이트 그대로다.
    static func mixed(
        _ foreground: CIImage, over image: CIImage, mask: FaceRegions.RegionMask, amount: Double, extent: CGRect
    ) -> CIImage {
        let scaled = mask.image.applyingFilter(
            "CIColorMatrix",
            parameters: [
                "inputRVector": CIVector(x: amount, y: 0, z: 0, w: 0),
                "inputGVector": CIVector(x: 0, y: amount, z: 0, w: 0),
                "inputBVector": CIVector(x: 0, y: 0, z: amount, w: 0),
            ])
        return MaskBuilder.blend(foreground.cropped(to: mask.bounds), over: image, mask: scaled).cropped(to: extent)
    }

    /// 입술(바깥 − 안쪽)에 고른 색을 소프트 라이트로 얹는다. 소프트 라이트는 입술 명암(질감)을 남긴다.
    private func paintLips(_ image: CIImage, face: FaceGeometry, tint: MakeupTint, context: RenderContext) -> CIImage {
        guard let color = Self.colorImage(tint, part: .lip, context: context),
            let lips = FaceRegions.lipMask(
                face: face, extent: context.extent, tuning: context.tuning, cache: context.regionMasks)
        else { return image }
        let lit = Self.blended(image, with: color, mode: Self.softLight, in: lips.bounds)
        let amount = tint.intensity * context.tuning.makeupLipMaxOpacity
        return Self.mixed(lit, over: image, mask: lips, amount: amount, extent: context.extent)
    }
}
