import CoreImage
import ImageIO
import MellowShared
import UniformTypeIdentifiers
import XCTest

@testable import MellowRendering

final class ImageLoaderTests: XCTestCase {
    typealias Support = RenderingTestSupport

    func testOrientationIsAppliedForFullAndThumbnailLoads() throws {
        let directory = try Support.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("rotated.jpg")
        let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.jpeg.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(
            destination, try Support.renderer.makeCGImage(Support.gradient()),
            [kCGImagePropertyOrientation: 6] as CFDictionary)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        let loader = ImageLoader()
        XCTAssertEqual(try loader.load(url: url).extent, CGRect(x: 0, y: 0, width: 80, height: 128))
        XCTAssertEqual(try loader.load(url: url, maxDimension: 64).extent, CGRect(x: 0, y: 0, width: 40, height: 64))
        XCTAssertEqual(try loader.metadata(url: url).pixelSize, CGSize(width: 80, height: 128))
    }

    func testUnreadableFileThrowsTypedError() throws {
        let directory = try Support.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("broken.png")
        try Data([0, 1, 2]).write(to: url)
        XCTAssertThrowsError(try ImageLoader().load(url: url)) { error in
            XCTAssertEqual(error as? MellowError, .unsupportedOrCorruptPhoto)
        }
        XCTAssertThrowsError(try ImageLoader().load(url: directory.appendingPathComponent("missing.png"))) { error in
            XCTAssertEqual(error as? MellowError, .cannotOpenPhoto(filename: "missing.png"))
        }
    }
}
