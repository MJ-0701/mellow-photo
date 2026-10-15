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
}
