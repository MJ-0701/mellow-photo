#if ENGINE_STANDALONE
private func expect(_ condition: @autoclosure () throws -> Bool, file: StaticString = #filePath, line: UInt = #line) rethrows { let value = try condition(); precondition(value, "Test failed at \(file):\(line)") }
private func expectThrow<T>(_ operation: () throws -> T) { do { _ = try operation(); preconditionFailure("Expected an error") } catch {} }
#else
import XCTest
private func expect(_ condition: @autoclosure () throws -> Bool, file: StaticString = #filePath, line: UInt = #line) rethrows { XCTAssertTrue(try condition(), file:file,line:line) }
private func expectThrow<T>(_ operation: () throws -> T) { XCTAssertThrowsError(try operation()) }
#endif
import Foundation
import CoreImage
import ImageIO
import UniformTypeIdentifiers
#if !ENGINE_STANDALONE
@testable import MellowCore
#endif

struct EngineTests {
    let engine = ImageEngine()
    func gradient() -> CIImage {
        CIFilter(name:"CILinearGradient",parameters:["inputPoint0":CIVector(x:0,y:0),"inputPoint1":CIVector(x:128,y:0),"inputColor0":CIColor(red:0.1,green:0.2,blue:0.3),"inputColor1":CIColor(red:0.9,green:0.6,blue:0.4)])!.outputImage!.cropped(to:CGRect(x:0,y:0,width:128,height:80))
    }
    func bytes(_ image: CIImage) throws -> [UInt8] {
        let cg = try engine.cgImage(image)
        return Array((cg.dataProvider!.data! as Data))
    }
    func temp() throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at:dir,withIntermediateDirectories:true)
        return dir
    }
    func testIdentityAndColor() throws {
        let input = gradient()
        let unchanged = try engine.render(input,recipe:EditRecipe(),faces:[])
        expect(unchanged.extent == input.extent)
        try expect(try bytes(unchanged) == bytes(input))
        var recipe = EditRecipe(); recipe.adjustments.exposure = 1
        try expect(try bytes(engine.render(input,recipe:recipe,faces:[])) != bytes(input))
    }
    func testWarpAndCloneAreLocalAndEffective() throws {
        let image = gradient()
        let original = try bytes(image)
        for isWarp in [true,false] {
            var recipe = EditRecipe()
            if isWarp { recipe.operations = [.warp(WarpStroke(x:0.5,y:0.5,dx:0.03,dy:0,radius:0.2))] }
            else { recipe.operations = [.spot(RetouchSpot(x:0.5,y:0.5,sourceX:0.2,sourceY:0.5,radius:0.2))] }
            let result = try bytes(engine.render(image,recipe:recipe,faces:[]))
            expect(result != original)
            expect(Array(result.prefix(128*4*10)) == Array(original.prefix(128*4*10)))
        }
    }
    func testLocalEditOrder() throws {
        let input = gradient()
        let spot = LocalEdit.spot(RetouchSpot(x:0.5,y:0.5,sourceX:0.15,sourceY:0.5,radius:0.2))
        let warp = LocalEdit.warp(WarpStroke(x:0.5,y:0.5,dx:0.05,dy:0,radius:0.3))
        var forward = EditRecipe(); forward.operations = [spot,warp]
        var reverse = EditRecipe(); reverse.operations = [warp,spot]
        let forwardImage = try engine.render(input,recipe:forward,faces:[])
        let reverseImage = try engine.render(input,recipe:reverse,faces:[])
        try expect(try bytes(forwardImage) != bytes(reverseImage))
        var one = EditRecipe(); one.operations = [spot]
        var two = EditRecipe(); two.operations = [warp]
        let staged = try engine.render(engine.render(input,recipe:one,faces:[]),recipe:two,faces:[])
        try expect(try bytes(forwardImage) == bytes(staged))
        let persisted = try JSONDecoder().decode(EditRecipe.self,from:JSONEncoder().encode(forward))
        expect(persisted.operations == forward.operations)
    }
    func testExportDimensionsCollisionAndNoGPS() throws {
        let directory = try temp()
        defer { try? FileManager.default.removeItem(at:directory) }
        for format in ExportFormat.allCases {
            let url = directory.appendingPathComponent("photo.\(format.fileExtension)")
            try engine.export(gradient(),to:url,format:format)
            let before = try Data(contentsOf:url)
            expectThrow { try engine.export(gradient(),to:url,format:format) }
            try expect(try before == Data(contentsOf:url))
            let image = try engine.load(url:url)
            expect(image.extent.size == CGSize(width:128,height:80))
            let source = CGImageSourceCreateWithURL(url as CFURL,nil)!
            let props = CGImageSourceCopyPropertiesAtIndex(source,0,nil)! as NSDictionary
            expect(props[kCGImagePropertyGPSDictionary] == nil)
            let cg = CGImageSourceCreateImageAtIndex(source,0,nil)!
            expect(cg.bitsPerComponent == 8)
            expect(cg.colorSpace?.name == CGColorSpace.sRGB)
        }
    }
    func testOrientationAndThumbnail() throws {
        let directory = try temp()
        defer { try? FileManager.default.removeItem(at:directory) }
        let url = directory.appendingPathComponent("rotated.jpg")
        let dest = CGImageDestinationCreateWithURL(url as CFURL,UTType.jpeg.identifier as CFString,1,nil)!
        CGImageDestinationAddImage(dest,try engine.cgImage(gradient()),[kCGImagePropertyOrientation:6] as CFDictionary)
        expect(CGImageDestinationFinalize(dest))
        let full = try engine.load(url:url)
        expect(full.extent == CGRect(x:0,y:0,width:80,height:128))
        let preview = try engine.load(url:url,maxDimension:64)
        expect(preview.extent == CGRect(x:0,y:0,width:40,height:64))
    }
    func testWarmthDirection() throws {
        let gray = CIImage(color:CIColor(red:0.5,green:0.5,blue:0.5)).cropped(to:CGRect(x:0,y:0,width:8,height:8))
        var recipe = EditRecipe(); recipe.adjustments.warmth = 1
        let image = try engine.cgImage(engine.render(gray,recipe:recipe,faces:[]))
        var rgba = [UInt8](repeating:0,count:8*8*4)
        let colorSpace = CGColorSpace(name:CGColorSpace.sRGB)!
        rgba.withUnsafeMutableBytes { buffer in
            let context = CGContext(data:buffer.baseAddress,width:8,height:8,bitsPerComponent:8,bytesPerRow:32,space:colorSpace,bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue)!
            context.draw(image,in:CGRect(x:0,y:0,width:8,height:8))
        }
        expect(rgba[0] > rgba[2])
    }
    func testPortraitFilterPipeline() throws {
        let input = gradient()
        let face = FaceRegion(rect:CGRect(x:0.15,y:0.05,width:0.7,height:0.9))
        var recipe = EditRecipe()
        recipe.adjustments.skin = 0.5
        recipe.adjustments.faceSlim = 0.7
        recipe.adjustments.contrast = 1.05
        recipe.adjustments.saturation = 0.8
        recipe.adjustments.warmth = -0.3
        let result = try engine.render(input,recipe:recipe,faces:[face])
        expect(result.extent == input.extent)
        try expect(try bytes(result) != bytes(input))
        var noFaces = EditRecipe()
        noFaces.adjustments.skin = 1
        noFaces.adjustments.faceSlim = 1
        try expect(try bytes(engine.render(input,recipe:noFaces,faces:[])) == bytes(input))
    }
    func testInvalidRecipeRejected() throws {
        var recipe = EditRecipe(); recipe.adjustments.skin = .nan
        expectThrow { try engine.render(gradient(),recipe:recipe,faces:[]) }
    }
}

#if ENGINE_STANDALONE
@main enum EngineTestRunner {
    static func main() throws {
        let tests = EngineTests()
        try tests.testIdentityAndColor()
        try tests.testWarpAndCloneAreLocalAndEffective()
        try tests.testExportDimensionsCollisionAndNoGPS()
        try tests.testOrientationAndThumbnail()
        try tests.testInvalidRecipeRejected()
        try tests.testWarmthDirection()
        try tests.testLocalEditOrder()
        try tests.testPortraitFilterPipeline()
        print("PASS: 8 engine tests (identity/color, local warp/clone, export/collision/metadata, orientation/thumbnail, invalid input, warmth direction, chronological edits, portrait filters)")
    }
}
#else
final class EngineXCTests: XCTestCase {
    func testEngine() throws {
        let tests = EngineTests()
        try tests.testIdentityAndColor()
        try tests.testWarpAndCloneAreLocalAndEffective()
        try tests.testExportDimensionsCollisionAndNoGPS()
        try tests.testOrientationAndThumbnail()
        try tests.testInvalidRecipeRejected()
        try tests.testWarmthDirection()
        try tests.testLocalEditOrder()
        try tests.testPortraitFilterPipeline()
    }
}
#endif
