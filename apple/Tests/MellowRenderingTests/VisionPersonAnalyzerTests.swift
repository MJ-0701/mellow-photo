import CoreImage
import MellowShared
import XCTest

@testable import MellowRendering

final class VisionPersonAnalyzerTests: XCTestCase {
    typealias Support = RenderingTestSupport

    /// 마스크 픽셀 하나의 값(0…1).
    private func value(_ mask: CIImage, at point: CGPoint) throws -> Float {
        let pixel = CGRect(origin: point, size: CGSize(width: 1, height: 1))
        return try Support.renderer.readPixels(mask.cropped(to: pixel))[0]
    }

    func testDemoPortraitMaskCoversFaceAndNotTopCorner() throws {
        let url = try XCTUnwrap(
            Bundle.module.url(forResource: "demo-portrait", withExtension: "png", subdirectory: "Fixtures"))
        let image = try ImageLoader().load(url: url, maxDimension: 1200)
        let face = try XCTUnwrap(try VisionFaceAnalyzer().analyze(image).first)
        let mask = try XCTUnwrap(try VisionPersonAnalyzer().personMask(image), "인물 사진에는 마스크가 있다")
        XCTAssertEqual(mask.extent.origin, .zero)
        let faceCenter = CGPoint(
            x: (face.boundingBox.midX * mask.extent.width).rounded(.down),
            y: (face.boundingBox.midY * mask.extent.height).rounded(.down))
        XCTAssertGreaterThan(try value(mask, at: faceCenter), 0.8, "얼굴 가운데는 사람")
        XCTAssertLessThan(try value(mask, at: CGPoint(x: 0, y: mask.extent.height - 1)), 0.2, "왼쪽 위 구석은 배경")
    }

    func testBlankImageHasNoPerson() throws {
        let blank = Support.solid(CIColor(red: 0.5, green: 0.6, blue: 0.7), size: 512)
        XCTAssertNil(try VisionPersonAnalyzer().personMask(blank))
    }
}
