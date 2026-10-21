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

    /// 턱 위 그늘 선(폭 얼굴 폭 1%, 길이 10%)은 잡티가 아니다(스펙 G5 5.2).
    /// 옆의 원은 잡힌다.
    func testElongatedShadowLineIsNotABlemish() throws {
        let base = SyntheticFace.make()
        let faceWidth = SyntheticFace.box.width
        // 입 보호 영역(입 아래 끝 y 120 − 넓힘)보다 아래, 피부 아래 끝(y 50)보다 충분히 위다.
        let lineCenter = CGPoint(x: 256, y: 90)
        let lineRadii = CGSize(width: faceWidth * 0.05, height: faceWidth * 0.005)
        let disc = SyntheticFace.cheek
        let discRadii = CGSize(width: SyntheticFace.blemishRadius, height: SyntheticFace.blemishRadius)
        let painted = SyntheticFace.painted(
            SyntheticFace.painted(base.image, center: lineCenter, radii: lineRadii), center: disc, radii: discRadii)
        let image = CIImage(cgImage: try Support.renderer.makeCGImage(painted))
        let spots = try detector().detect(image: image, faces: [base.face])
        let centers = spots.map(pixelCenter)
        XCTAssertTrue(centers.contains { hypot($0.x - disc.x, $0.y - disc.y) < faceWidth * 0.02 }, "원은 잡힌다")
        XCTAssertFalse(
            centers.contains { hypot($0.x - lineCenter.x, $0.y - lineCenter.y) < faceWidth * 0.06 }, "선은 거절")
    }

    /// 피부 다각형 가장자리(마스크 < 0.9)의 원은 잡지 않는다(스펙 G5 5.2).
    /// 합성 얼굴은 윤곽이 피부 타원보다 넓어 양옆 가장자리가 배경이므로 윤곽과 피부가 만나는 턱 끝을 쓴다.
    func testSpotOnTheSkinEdgeIsRejected() throws {
        let base = SyntheticFace.make()
        let extent = base.image.extent
        let faceWidth = SyntheticFace.box.width
        let polygon = FaceRegions.skinPolygon(face: base.face, extent: extent, tuning: RenderTuning())
        // 윤곽 가장 아래 점에서 안쪽으로 얼굴 폭 1%만 들어간 자리.
        let lowest = try XCTUnwrap(polygon.min { $0.y < $1.y })
        let edge = CGPoint(x: lowest.x, y: lowest.y + faceWidth * 0.01)
        let painted = SyntheticFace.painted(base.image, center: edge, radii: CGSize(width: 3, height: 3))
        let image = CIImage(cgImage: try Support.renderer.makeCGImage(painted))
        let spots = try detector().detect(image: image, faces: [base.face])
        XCTAssertTrue(spots.isEmpty, "가장자리 원은 거절 \(spots.map(pixelCenter))")
    }
}
