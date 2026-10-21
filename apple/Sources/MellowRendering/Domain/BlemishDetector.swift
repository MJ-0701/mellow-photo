import CoreImage
import Foundation
import MellowShared

/// 미리보기에서 자동 잡티를 찾는다. 피부 마스크 안에서 주변보다 어둡고 붉은 작은 점이다(DoG).
/// 얼굴 영역만 긴 변 blemishAnalysisMaxDimension으로 줄여 픽셀을 읽는다.
struct BlemishDetector {
    let tuning: RenderTuning
    let renderer: Renderer

    /// BT.601 휘도·Cr 계수. sRGB 감마 값에 쓴다.
    private static let lumaWeights: [Double] = [0.299, 0.587, 0.114]
    private static let redChromaWeights: [Double] = [0.5, -0.418688, -0.081312]

    private struct Candidate {
        var center: CGPoint
        var radius: CGFloat
        var score: Double
    }

    /// 얼굴 순서대로, 얼굴마다 점수(어두운 정도의 합)가 높은 순서로 최대 blemishMaxPerFace개.
    func detect(image: CIImage, faces: [FaceGeometry]) throws -> [BlemishSpot] {
        var spots: [BlemishSpot] = []
        for (index, face) in faces.enumerated() {
            spots += try detect(image: image, face: face, faceIndex: index)
        }
        return spots
    }

    private func detect(image: CIImage, face: FaceGeometry, faceIndex: Int) throws -> [BlemishSpot] {
        let extent = image.extent
        // 얼굴 상자가 아니라 피부 마스크 영역을 본다. 마스크의 이마 호는 상자 위로 올라간다.
        let faceRect = FaceRegions.maskBounds(face: face, extent: extent, tuning: tuning)
        guard !faceRect.isEmpty else { return [] }
        let scale = min(1, CGFloat(tuning.blemishAnalysisMaxDimension) / max(faceRect.width, faceRect.height))
        let width = Int((faceRect.width * scale).rounded(.down))
        let height = Int((faceRect.height * scale).rounded(.down))
        guard width > 0, height > 0 else { return [] }
        let small = CGRect(x: 0, y: 0, width: width, height: height)
        let toSmall = CGAffineTransform(
            a: scale, b: 0, c: 0, d: scale, tx: -faceRect.minX * scale, ty: -faceRect.minY * scale)
        let faceWidth = FaceRegions.faceWidth(face, extent: extent)
        let smallFaceWidth = Double(faceWidth * scale)
        let encoded = image.applyingFilter("CILinearToSRGBToneCurve").transformed(by: toSmall)
        let centerRadius = max(tuning.skinBlurMinimumRadius, smallFaceWidth * tuning.blemishMinRadiusFraction)
        let surroundRadius = smallFaceWidth * tuning.blemishMaxRadiusFraction * tuning.blemishSurroundScale
        let center = try renderer.readPixels(
            FrequencySeparation.blurred(encoded, radius: centerRadius).cropped(to: small))
        let surround = try renderer.readPixels(
            FrequencySeparation.blurred(encoded, radius: surroundRadius).cropped(to: small))
        let maskImage = try FaceRegions.skinMask(face: face, image: image, extent: extent, tuning: tuning)
        let mask = try renderer.readPixels(maskImage.transformed(by: toSmall).cropped(to: small))
        // 중심 검사는 볼 색 가중치 없는 피부 다각형 마스크로 한다(스펙 G5 5.2, G5-1 검토 뒤 변경).
        // 색 가중 마스크는 붉은 잡티 자신의 중심 값을 낮춰 둥근 염증 여드름까지 거절한다.
        let geometry = FaceRegions.skinPolygonRaster(face: face, extent: extent, tuning: tuning, cache: nil)
            .clampedToExtent()
            .applyingFilter(
                "CIGaussianBlur", parameters: [kCIInputRadiusKey: FaceRegions.featherRadius(face, extent, tuning)]
            )
            .cropped(to: extent)
        let geometryMask = try renderer.readPixels(geometry.transformed(by: toSmall).cropped(to: small))
        var candidate = [Bool](repeating: false, count: width * height)
        var drop = [Double](repeating: 0, count: width * height)
        for index in candidate.indices {
            let offset = index * 4
            let surroundLuma = Self.weighted(surround, offset, Self.lumaWeights)
            guard Double(mask[offset]) >= tuning.blemishMaskThreshold, surroundLuma > 0 else { continue }
            let relativeDrop = (surroundLuma - Self.weighted(center, offset, Self.lumaWeights)) / surroundLuma
            let centerRed = Self.weighted(center, offset, Self.redChromaWeights)
            let redness = centerRed - Self.weighted(surround, offset, Self.redChromaWeights)
            if relativeDrop >= tuning.blemishLumaDrop && redness >= tuning.blemishRednessMin {
                candidate[index] = true
                drop[index] = relativeDrop
            }
        }
        let excluded = FaceRegions.containment(
            polygons: FaceRegions.blemishExclusionPolygons(face: face, extent: extent),
            dilation: faceWidth * CGFloat(tuning.skinFeatureFeather))
        let minRadius = faceWidth * CGFloat(tuning.blemishMinRadiusFraction)
        let maxRadius = faceWidth * CGFloat(tuning.blemishMaxRadiusFraction)
        var found: [Candidate] = []
        for members in Self.components(of: candidate, width: width, height: height) {
            guard Self.isCompact(members: members, width: width, tuning: tuning) else { continue }
            var sumX = 0.0
            var sumY = 0.0
            var score = 0.0
            for index in members {
                sumX += Double(index % width) + 0.5
                // readPixels는 맨 위 행부터다. Core Image y는 아래에서 센다.
                sumY += Double(height - 1 - index / width) + 0.5
                score += drop[index]
            }
            let count = Double(members.count)
            // 중심 픽셀의 피부 다각형 마스크. readPixels는 맨 위 행부터라 행을 뒤집는다.
            let centerX = Int(sumX / count)
            let centerRow = height - 1 - Int(sumY / count)
            guard centerX >= 0, centerX < width, centerRow >= 0, centerRow < height else { continue }
            let centerOffset = (centerRow * width + centerX) * 4
            guard Double(geometryMask[centerOffset]) >= tuning.blemishCenterMaskMinimum else { continue }
            let radius = CGFloat((count / Double.pi).squareRoot()) / scale
            guard radius >= minRadius, radius <= maxRadius else { continue }
            let point = CGPoint(
                x: faceRect.minX + CGFloat(sumX / count) / scale, y: faceRect.minY + CGFloat(sumY / count) / scale)
            guard !excluded(point) else { continue }
            found.append(Candidate(center: point, radius: radius, score: score))
        }
        let shortSide = min(extent.width, extent.height)
        return found.sorted { $0.score > $1.score }.prefix(tuning.blemishMaxPerFace).map { candidate in
            BlemishSpot(
                x: Double((candidate.center.x - extent.minX) / extent.width),
                y: Double((candidate.center.y - extent.minY) / extent.height),
                radius: Double(candidate.radius / shortSide), faceIndex: faceIndex)
        }
    }

    /// 상자 종횡비 ≤ blemishMaxAspect이고 채움 비 ≥ blemishMinFill이면 원에 가깝다.
    /// members는 components의 픽셀 인덱스(행 우선)다.
    static func isCompact(members: [Int], width: Int, tuning: RenderTuning) -> Bool {
        guard let first = members.first, width > 0 else { return false }
        var minX = first % width
        var maxX = minX
        var minY = first / width
        var maxY = minY
        for index in members {
            minX = min(minX, index % width)
            maxX = max(maxX, index % width)
            minY = min(minY, index / width)
            maxY = max(maxY, index / width)
        }
        let boxWidth = Double(maxX - minX + 1)
        let boxHeight = Double(maxY - minY + 1)
        let aspect = max(boxWidth, boxHeight) / min(boxWidth, boxHeight)
        let fill = Double(members.count) / (boxWidth * boxHeight)
        return aspect <= tuning.blemishMaxAspect && fill >= tuning.blemishMinFill
    }

    private static func weighted(_ pixels: [Float], _ offset: Int, _ weights: [Double]) -> Double {
        Double(pixels[offset]) * weights[0] + Double(pixels[offset + 1]) * weights[1]
            + Double(pixels[offset + 2]) * weights[2]
    }

    /// 4방향 연결 영역. 각 영역은 픽셀 인덱스 목록(행 우선, 맨 위 행부터).
    static func components(of candidate: [Bool], width: Int, height: Int) -> [[Int]] {
        var visited = [Bool](repeating: false, count: candidate.count)
        var result: [[Int]] = []
        for start in candidate.indices where candidate[start] && !visited[start] {
            var stack = [start]
            visited[start] = true
            var members: [Int] = []
            while let index = stack.popLast() {
                members.append(index)
                let x = index % width
                let y = index / width
                let neighbors = [(x - 1, y), (x + 1, y), (x, y - 1), (x, y + 1)]
                for (nx, ny) in neighbors where nx >= 0 && nx < width && ny >= 0 && ny < height {
                    let neighbor = ny * width + nx
                    if candidate[neighbor] && !visited[neighbor] {
                        visited[neighbor] = true
                        stack.append(neighbor)
                    }
                }
            }
            result.append(members)
        }
        return result
    }
}
