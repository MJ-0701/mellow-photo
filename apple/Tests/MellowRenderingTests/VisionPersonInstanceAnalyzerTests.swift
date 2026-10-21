import CoreImage
import MellowShared
import XCTest

@testable import MellowRendering

final class VisionPersonInstanceAnalyzerTests: XCTestCase {
    typealias Support = RenderingTestSupport

    /// 사람 픽셀로 보는 마스크 값.
    private let personValue: Float = 0.5

    /// 마스크 픽셀 하나의 값(0…1).
    private func value(_ mask: CIImage, at point: CGPoint) throws -> Float {
        let pixel = CGRect(origin: point, size: CGSize(width: 1, height: 1))
        return try Support.renderer.readPixels(mask.cropped(to: pixel))[0]
    }

    func testDemoPortraitHasOneInstanceOrNone() throws {
        let url = try XCTUnwrap(
            Bundle.module.url(forResource: "demo-portrait", withExtension: "png", subdirectory: "Fixtures"))
        let image = try ImageLoader().load(url: url, maxDimension: 1200)
        let masks = try VisionPersonInstanceAnalyzer().instanceMasks(image)
        XCTAssertLessThanOrEqual(masks.count, 1, "한 사람 사진")
        guard let mask = masks.first else { throw XCTSkip("instance mask unavailable on this machine") }
        XCTAssertEqual(mask.extent.origin, .zero, "Vision 원래 해상도이고 원점은 0이다")
        let center = CGPoint(x: (mask.extent.midX).rounded(.down), y: (mask.extent.midY).rounded(.down))
        XCTAssertGreaterThanOrEqual(try value(mask, at: center), personValue, "가운데 얼굴은 그 사람이다")
    }

    func testEmptySceneHasNoInstances() throws {
        let blank = Support.solid(CIColor(red: 0.5, green: 0.6, blue: 0.7), size: 512)
        XCTAssertEqual(try VisionPersonInstanceAnalyzer().instanceMasks(blank).count, 0)
    }
}
