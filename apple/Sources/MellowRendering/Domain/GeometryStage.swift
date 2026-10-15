import CoreImage
import MellowShared

/// 반전 → 시계 방향 90° 회전 → 수평 보정(중심 회전 + 확대) → 자르기. 결과 extent는 원점 0.
/// 좌표 기반 단계(피부·얼굴 변형·수동 편집) 뒤, 색·디테일·룩 앞에 둔다. 비네팅이 잘린 화면을 따른다.
struct GeometryStage: RenderStage {
    let name = "geometry"

    func apply(_ image: CIImage, in context: RenderContext) throws -> CIImage {
        let geometry = context.recipe.geometry
        guard !geometry.isIdentity else { return image }
        var result = image
        var extent = image.extent
        if geometry.flipHorizontal {
            let flip = CGAffineTransform(a: -1, b: 0, c: 0, d: 1, tx: extent.minX + extent.maxX, ty: 0)
            result = result.transformed(by: flip).cropped(to: extent)
        }
        for _ in 0..<geometry.normalizedQuarterTurns {
            // (x, y) → (y − minY, maxX − x): 시계 방향 90°.
            let turn = CGAffineTransform(a: 0, b: -1, c: 1, d: 0, tx: -extent.minY, ty: extent.maxX)
            result = result.transformed(by: turn)
            extent = CGRect(x: 0, y: 0, width: extent.height, height: extent.width)
            result = Self.moveToOrigin(result).cropped(to: extent)
        }
        if geometry.straightenDegrees != 0 {
            let radians = -geometry.straightenDegrees * .pi / 180
            let scale = GeometryTransform.straightenScale(
                degrees: geometry.straightenDegrees, aspect: extent.width / extent.height)
            let center = CGPoint(x: extent.midX, y: extent.midY)
            let transform = CGAffineTransform(translationX: center.x, y: center.y)
                .rotated(by: radians)
                .scaledBy(x: scale, y: scale)
                .translatedBy(x: -center.x, y: -center.y)
            result = result.transformed(by: transform).cropped(to: extent)
        }
        if let crop = geometry.crop, !context.skipsCrop {
            // 변마다 가장 가까운 픽셀로 맞춘다. integral처럼 바깥으로 넓히면 부동소수 오차로 한 픽셀이 늘어난다.
            let minX = (extent.minX + crop.minX * extent.width).rounded()
            let maxX = (extent.minX + crop.maxX * extent.width).rounded()
            let minY = (extent.minY + crop.minY * extent.height).rounded()
            let maxY = (extent.minY + crop.maxY * extent.height).rounded()
            let pixelRect = CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY).intersection(extent)
            guard !pixelRect.isEmpty else { throw MellowError.invalidRecipeValues }
            result = result.cropped(to: pixelRect)
        }
        // 반전만, 수평 보정만 한 경우에도 원점 0 계약을 지킨다.
        return Self.moveToOrigin(result)
    }

    private static func moveToOrigin(_ image: CIImage) -> CIImage {
        image.transformed(by: CGAffineTransform(translationX: -image.extent.minX, y: -image.extent.minY))
    }
}
