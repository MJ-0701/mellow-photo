import CoreImage
import ImageIO
import MellowRendering
import MellowShared
import XCTest

@testable import MellowExport

final class ExporterTests: XCTestCase {
    private let renderer = Renderer()

    private func gradient() -> CIImage {
        CIFilter(
            name: "CILinearGradient",
            parameters: [
                "inputPoint0": CIVector(x: 0, y: 0), "inputPoint1": CIVector(x: 128, y: 0),
                "inputColor0": CIColor(red: 0.1, green: 0.2, blue: 0.3),
                "inputColor1": CIColor(red: 0.9, green: 0.6, blue: 0.4),
            ])!.outputImage!.cropped(to: CGRect(x: 0, y: 0, width: 128, height: 80))
    }

    func testWritesVerifiableSRGB8BitWithoutGPSAndRefusesOverwrite() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let exporter = Exporter(renderer: renderer)
        for format in ExportFormat.allCases {
            let url = directory.appendingPathComponent("photo.\(format.fileExtension)")
            try exporter.write(gradient(), to: url, format: format, quality: 0.94)
            let before = try Data(contentsOf: url)
            XCTAssertThrowsError(try exporter.write(gradient(), to: url, format: format, quality: 0.94)) { error in
                XCTAssertEqual(error as? MellowError, .fileAlreadyExists)
            }
            XCTAssertEqual(try Data(contentsOf: url), before)
            XCTAssertEqual(try ImageLoader().load(url: url).extent.size, CGSize(width: 128, height: 80))
            let source = CGImageSourceCreateWithURL(url as CFURL, nil)!
            let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil)! as NSDictionary
            XCTAssertNil(properties[kCGImagePropertyGPSDictionary])
            let cg = CGImageSourceCreateImageAtIndex(source, 0, nil)!
            XCTAssertEqual(cg.bitsPerComponent, 8)
            XCTAssertEqual(cg.colorSpace?.name, CGColorSpace.sRGB)
        }
        XCTAssertEqual(
            try FileManager.default.contentsOfDirectory(atPath: directory.path).filter { $0.hasPrefix(".mellow-") }
                .count, 0, "임시 파일이 남지 않는다")
    }

    func testWriteIntoMissingFolderFails() {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            .appendingPathComponent("x.jpg")
        let exporter = Exporter(renderer: renderer)
        XCTAssertThrowsError(try exporter.write(gradient(), to: url, format: .jpeg, quality: 0.9)) { error in
            XCTAssertEqual(error as? MellowError, .cannotWriteToFolder)
        }
    }

    func testOptionsResolveMaxDimension() {
        XCTAssertNil(ExportOptions(format: .jpeg, fullResolution: true).maxDimension)
        XCTAssertEqual(
            ExportOptions(format: .jpeg, fullResolution: false).maxDimension, ExportOptions.defaultMaxDimension)
    }
}
