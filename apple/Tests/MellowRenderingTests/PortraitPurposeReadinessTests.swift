import CoreImage
import MellowShared
import XCTest

@testable import MellowRendering

final class PortraitPurposeReadinessTests: XCTestCase {
    func testFaceBoxAloneAndUnmatchedBodyNeverAdvertisePurposeReadiness() {
        let image = RenderingTestSupport.solid(CIColor(red: 0.6, green: 0.4, blue: 0.3))
        let face = FaceGeometry(boundingBox: NormalizedRect(x: 0.2, y: 0.2, width: 0.6, height: 0.6))
        let analysis = PhotoAnalysis(faces: [face])
        let keys = PortraitPurposeReadiness.keys(
            image: image, analysis: analysis, tuning: RenderTuning(), renderer: RenderingTestSupport.renderer)
        XCTAssertEqual(keys[0], [])
    }
    func testSideChestRequiresOneMatchedBodyAndPreparedOutline() {
        let image = RenderingTestSupport.solid(CIColor(red: 0.6, green: 0.4, blue: 0.3), size: 512)
        let face = FaceGeometry(boundingBox: NormalizedRect(x: 0.35, y: 0.8, width: 0.3, height: 0.18))
        let body = RenderingTestSupport.standingBody(in: NormalizedRect(x: 0.1, y: 0.1, width: 0.8, height: 0.8))
        let outline = BodyOutline(points: [
            OutlineKey(level: BodyShapeRig.sideChestOutlineLevel, side: -1): NormalizedPoint(x: 0.3, y: 0.69),
            OutlineKey(level: BodyShapeRig.sideChestOutlineLevel, side: 1): NormalizedPoint(x: 0.71, y: 0.69),
        ])
        func keys(_ analysis: PhotoAnalysis) -> Set<PortraitKey> {
            PortraitPurposeReadiness.keys(
                image: image, analysis: analysis, tuning: RenderTuning(),
                renderer: RenderingTestSupport.renderer)[0] ?? []
        }
        let positive = PhotoAnalysis(faces: [face], bodies: [body], bodyFaceMatches: [0: 0], bodyOutlines: [0: outline])
        XCTAssertTrue(keys(positive).contains(.bodyShape(.sideChest)), "기존 primitive가 실제로 만들어지는 준비 상태만 허용한다")
        var missing = positive
        missing.bodyFaceMatches = [:]
        XCTAssertFalse(keys(missing).contains(.bodyShape(.sideChest)))
        missing = positive
        missing.bodyOutlines = [:]
        XCTAssertFalse(keys(missing).contains(.bodyShape(.sideChest)))
        missing = positive
        missing.bodies.append(body)
        missing.bodyFaceMatches[1] = 0
        missing.bodyOutlines[1] = outline
        XCTAssertFalse(keys(missing).contains(.bodyShape(.sideChest)), "한 얼굴에 두 몸이 연결되면 추측하지 않는다")
    }

}
