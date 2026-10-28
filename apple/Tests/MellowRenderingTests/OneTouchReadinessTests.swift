import CoreImage
import MellowShared
import XCTest

@testable import MellowRendering

final class OneTouchReadinessTests: XCTestCase {
    private func inspect(_ image: CIImage, faces: [FaceGeometry], catalog: MakeupCatalog = .empty)
        -> OneTouchReadiness.Result
    {
        let analysis = PhotoAnalysis(faces: faces)
        let tuning = RenderTuning()
        let renderer = RenderingTestSupport.renderer
        let skin = PortraitPurposeReadiness.keys(image: image, analysis: analysis, tuning: tuning, renderer: renderer)
        return OneTouchReadiness.inspect(
            image: image, analysis: analysis, tuning: tuning,
            renderer: renderer, makeupCatalog: catalog, skinKeys: skin)
    }

    func testBoxOnlyNeverClaimsPortraitReadinessAndBodyUsesActualExistingFallback() {
        let image = RenderingTestSupport.solid(CIColor(red: 0.6, green: 0.4, blue: 0.3))
        let face = FaceGeometry(boundingBox: NormalizedRect(x: 0.2, y: 0.2, width: 0.6, height: 0.6))
        let result = inspect(image, faces: [face])
        XCTAssertEqual(result.keys[0], [])
        XCTAssertTrue(result.bodySkin, "기존 몸 피부 단계의 양의 fallback 마스크는 얼굴 보정 준비와 별개다")
    }

    func testActualMasksClosedMouthAndCatalogAreDistinguished() throws {
        let synthetic = SyntheticFace.makeFeatures(mouthOpen: false)
        let withoutCatalog = inspect(synthetic.image, faces: [synthetic.face])
        XCTAssertTrue(withoutCatalog.keys[0]!.contains(.skinSmoothing))
        XCTAssertTrue(withoutCatalog.keys[0]!.contains(.feature(.eyeBrighten)))
        XCTAssertTrue(withoutCatalog.keys[0]!.contains(.feature(.lipVitality)))
        XCTAssertFalse(withoutCatalog.keys[0]!.contains(.feature(.teethWhiten)))
        XCTAssertFalse(withoutCatalog.keys[0]!.contains(.makeupPart(.blush)))
        XCTAssertFalse(withoutCatalog.keys[0]!.contains(.autoBlemish), "수정 가능한 복제 원이 없는 것을 피부 마스크로 대신하지 않는다")
        let withCatalog = inspect(
            synthetic.image, faces: [synthetic.face], catalog: try RenderingTestSupport.sharedMakeupCatalog())
        XCTAssertTrue(withCatalog.keys[0]!.contains(.makeupPart(.blush)))
        XCTAssertTrue(withCatalog.bodySkin)
    }
}
