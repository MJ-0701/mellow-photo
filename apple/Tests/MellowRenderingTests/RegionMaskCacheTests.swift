import CoreImage
import MellowShared
import XCTest

@testable import MellowRendering

final class RegionMaskCacheTests: XCTestCase {
    typealias Support = RenderingTestSupport

    /// 얼굴당 해상도마다 9(G2: 몸 피부의 눈·입 비트맵).
    func testCapacityGrowsWithFaceCount() {
        XCTAssertEqual(RegionMaskCache.capacity(forFaces: 0), RegionMaskCache.minimumEntries)
        XCTAssertEqual(RegionMaskCache.capacity(forFaces: 2), 36)
        XCTAssertEqual(RegionMaskCache.capacity(forFaces: 3), 54)
        let face = SyntheticFace.make().face
        XCTAssertEqual(PhotoAnalysis(faces: [face, face, face]).regionMasks.maximumEntries, 54)
        XCTAssertEqual(PhotoAnalysis().regionMasks.maximumEntries, 32)
    }

    /// 세 얼굴에 피부·눈·입·메이크업을 모두 켜고 큰 크기·작은 크기(미리보기·원본 대신)로 번갈아 렌더한다.
    /// 상한이 32로 고정이면 두 번째 크기에서 캐시를 비워 매번 다시 그린다(D 이월).
    func testThreeFacesWithFullMakeupKeepEveryMaskAcrossTwoResolutions() throws {
        let synthetic = SyntheticFace.makeFeatures()
        let third = 1.0 / 3
        let faces = [0, third, 2 * third].map {
            synthetic.face.transformed(scale: third, offset: NormalizedPoint(x: $0, y: third))
        }
        let analysis = PhotoAnalysis(faces: faces)
        let catalog = try Support.sharedMakeupCatalog()
        var recipe = EditRecipe()
        recipe.portrait.skin.smoothing = 0.5
        recipe.portrait.features = FeatureAdjustments(eyeBrighten: 0.5, teethWhiten: 0.5, lipVitality: 0.5)
        recipe.makeup = try XCTUnwrap(catalog.look(id: "smoky")).adjustments
        let large = synthetic.image
        let small = synthetic.image.transformed(by: CGAffineTransform(scaleX: 0.5, y: 0.5))
        func render(_ image: CIImage) throws -> [UInt8] {
            let context = RenderContext(
                extent: image.extent, recipe: recipe, analysis: analysis, tuning: RenderTuning(),
                makeupCatalog: catalog)
            return try Support.bytes(RenderPipeline.standard.render(image, context: context))
        }
        let firstLarge = try render(large)
        _ = try render(small)
        let filled = analysis.regionMasks.count
        XCTAssertGreaterThan(filled, RegionMaskCache.minimumEntries, "얼굴 셋 × 두 크기는 옛 상한 32를 넘는다")
        XCTAssertEqual(try render(large), firstLarge, "캐시에서 꺼낸 마스크로도 같은 결과")
        _ = try render(small)
        XCTAssertEqual(analysis.regionMasks.count, filled, "다시 렌더해도 비우지 않고 같은 비트맵을 쓴다")
    }
}
