import CoreImage
import MellowShared
import XCTest

@testable import MellowRendering

final class BlemishDetectorTests: XCTestCase {
    typealias Support = RenderingTestSupport

    private let size = CGFloat(SyntheticFace.size)

    private func detector(_ tuning: RenderTuning = RenderTuning()) -> BlemishDetector {
        BlemishDetector(tuning: tuning, renderer: Support.renderer)
    }

    private func pixelCenter(_ spot: BlemishSpot) -> CGPoint {
        CGPoint(x: spot.x * size, y: spot.y * size)
    }

    func testFindsPlantedSpotsAndIgnoresSpotNextToEye() throws {
        let synthetic = SyntheticFace.make(withBlemishes: true)
        let spots = try detector().detect(image: synthetic.image, faces: [synthetic.face])
        XCTAssertEqual(spots.count, SyntheticFace.blemishes.count)
        for planted in SyntheticFace.blemishes {
            XCTAssertTrue(
                spots.contains { hypot(pixelCenter($0).x - planted.x, pixelCenter($0).y - planted.y) < 2 },
                "\(planted) 누락")
        }
        let near = SyntheticFace.blemishNearEye
        XCTAssertFalse(spots.contains { hypot(pixelCenter($0).x - near.x, pixelCenter($0).y - near.y) < 6 })
        for spot in spots {
            XCTAssertEqual(spot.faceIndex, 0)
            XCTAssertEqual(Double(spot.radius * size), Double(SyntheticFace.blemishRadius), accuracy: 1.5)
        }
    }

    func testDownscaledAnalysisMapsSpotsBackToPlantedPositions() throws {
        let synthetic = SyntheticFace.make(withBlemishes: true)
        let analysisScale: CGFloat = 0.5
        // 합성 얼굴의 마스크 영역은 긴 변 388px이라 256이면 배율이 0.66이다. 0.5가 되도록 긴 변의 절반을 쓴다.
        let bounds = FaceRegions.maskBounds(
            face: synthetic.face, extent: synthetic.image.extent, tuning: RenderTuning())
        var tuning = RenderTuning()
        tuning.blemishAnalysisMaxDimension = Int(max(bounds.width, bounds.height) * analysisScale)
        let spots = try detector(tuning).detect(image: synthetic.image, faces: [synthetic.face])
        XCTAssertEqual(spots.count, SyntheticFace.blemishes.count)
        let tolerance = 2 / analysisScale
        for planted in SyntheticFace.blemishes {
            XCTAssertTrue(
                spots.contains { hypot(pixelCenter($0).x - planted.x, pixelCenter($0).y - planted.y) < tolerance },
                "\(planted)가 축소 분석 뒤 제자리로 돌아오지 않는다")
        }
    }

    func testCleanSkinAndNoFacesYieldNothing() throws {
        let clean = SyntheticFace.make()
        XCTAssertEqual(try detector().detect(image: clean.image, faces: [clean.face]), [])
        let spotted = SyntheticFace.make(withBlemishes: true)
        XCTAssertEqual(try detector().detect(image: spotted.image, faces: []), [])
    }

    func testSpotsPerFaceAreCapped() throws {
        XCTAssertEqual(RenderTuning().blemishMaxPerFace, 40)
        var tuning = RenderTuning()
        tuning.blemishMaxPerFace = 3
        let synthetic = SyntheticFace.make(withBlemishes: true)
        XCTAssertEqual(try detector(tuning).detect(image: synthetic.image, faces: [synthetic.face]).count, 3)
    }

    func testDemoPortraitStaysWithinCapAndOutsideEyesAndLips() throws {
        let url = try XCTUnwrap(
            Bundle.module.url(forResource: "demo-portrait", withExtension: "png", subdirectory: "Fixtures"))
        let image = try ImageLoader().load(url: url, maxDimension: RenderTuning().previewMaxDimension)
        let face = try XCTUnwrap(try VisionFaceAnalyzer().analyze(image).first)
        let spots = try detector().detect(image: image, faces: [face])
        XCTAssertLessThanOrEqual(spots.count, RenderTuning().blemishMaxPerFace)
        let protected = FaceRegions.protectedPolygons(face: face, extent: image.extent)
        for spot in spots {
            let point = CGPoint(x: spot.x * image.extent.width, y: spot.y * image.extent.height)
            XCTAssertFalse(FaceRegions.contains(point, polygons: protected, dilation: 0), "눈·눈썹·입술 안의 잡티 \(point)")
        }
    }
}
