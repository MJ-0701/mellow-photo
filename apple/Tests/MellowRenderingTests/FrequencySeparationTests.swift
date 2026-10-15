import CoreImage
import MellowShared
import XCTest

@testable import MellowRendering

final class FrequencySeparationTests: XCTestCase {
    typealias Support = RenderingTestSupport

    /// 합성 얼굴과 같은 얼굴 폭. 미리보기 1600px 사진의 작은 얼굴 정도다.
    private let faceWidth: CGFloat = 280
    private let patch = CGRect(x: 156, y: 156, width: 200, height: 200)

    func testRadiiScaleWithFaceWidthAndHaveFloor() {
        let tuning = RenderTuning()
        let radii = FrequencySeparation.radii(faceWidth: faceWidth, tuning: tuning)
        XCTAssertEqual(radii.fine, Double(faceWidth) * tuning.fineBandFraction, accuracy: 1e-9)
        XCTAssertEqual(radii.mid, Double(faceWidth) * tuning.midBandFraction, accuracy: 1e-9)
        let tiny = FrequencySeparation.radii(faceWidth: 10, tuning: tuning)
        XCTAssertEqual(tiny.fine, tuning.skinBlurMinimumRadius)
        XCTAssertGreaterThanOrEqual(tiny.mid, tiny.fine)
    }

    func testZeroSmoothingReturnsInput() throws {
        let image = Support.skinTexture(size: 64)
        let output = try FrequencySeparation.smoothed(
            image, bounds: image.extent, faceWidth: faceWidth, smoothing: 0, tuning: RenderTuning())
        XCTAssertEqual(try Support.bytes(output), try Support.bytes(image))
    }

    func testSmoothingCutsMidBandAndKeepsFineBand() throws {
        let tuning = RenderTuning()
        let image = Support.skinTexture(size: SyntheticFace.size)
        let radii = FrequencySeparation.radii(faceWidth: faceWidth, tuning: tuning)
        let output = try FrequencySeparation.smoothed(
            image, bounds: image.extent, faceWidth: faceWidth, smoothing: 1, tuning: tuning)
        XCTAssertEqual(output.extent, image.extent)
        let before = try Support.bandVariances(image, in: patch, fineRadius: radii.fine, midRadius: radii.mid)
        let after = try Support.bandVariances(output, in: patch, fineRadius: radii.fine, midRadius: radii.mid)
        XCTAssertLessThan(after.mid, before.mid * 0.5, "중간 대역(얼룩) 분산이 절반 아래로 준다")
        XCTAssertEqual(after.fine / before.fine, 1, accuracy: 0.1, "모공 대역 분산은 ±10% 안")
    }
}
