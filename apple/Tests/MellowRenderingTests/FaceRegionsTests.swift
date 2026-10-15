import CoreImage
import MellowShared
import XCTest

@testable import MellowRendering

final class FaceRegionsTests: XCTestCase {
    typealias Support = RenderingTestSupport

    private func maskGrid(_ synthetic: SyntheticFace) throws -> PixelGrid {
        let mask = try FaceRegions.skinMask(
            face: synthetic.face, image: synthetic.image, extent: synthetic.image.extent, tuning: RenderTuning())
        XCTAssertEqual(mask.extent, synthetic.image.extent)
        return try Support.grid(mask)
    }

    func testSkinMaskCoversCheeksAndForehead() throws {
        let grid = try maskGrid(SyntheticFace.make())
        XCTAssertGreaterThan(grid.red(SyntheticFace.cheek), 200)
        XCTAssertGreaterThan(grid.red(SyntheticFace.forehead), 200, "눈썹 위 이마 호까지 덮는다")
    }

    func testSkinMaskExcludesEyesBrowsAndLips() throws {
        let grid = try maskGrid(SyntheticFace.make())
        XCTAssertEqual(grid.red(SyntheticFace.leftEye), 0)
        XCTAssertEqual(grid.red(SyntheticFace.rightEye), 0)
        XCTAssertEqual(grid.red(CGPoint(x: SyntheticFace.leftBrow.midX, y: SyntheticFace.leftBrow.midY)), 0)
        XCTAssertEqual(grid.red(SyntheticFace.mouth), 0)
    }

    func testSkinMaskDropsNonSkinColorInsideContour() throws {
        let grid = try maskGrid(SyntheticFace.make())
        XCTAssertLessThan(grid.red(SyntheticFace.backgroundInsideContour), 8, "윤곽 안이어도 피부색이 아니면 빠진다")
    }

    func testSkinMaskIsZeroOutsideContour() throws {
        let grid = try maskGrid(SyntheticFace.make())
        XCTAssertEqual(grid.red(SyntheticFace.outside), 0)
        XCTAssertEqual(grid.red(CGPoint(x: 256, y: 470)), 0)
    }

    func testWithoutContourFallsBackToInsetEllipse() throws {
        let grid = try maskGrid(SyntheticFace.make(landmarks: false))
        XCTAssertGreaterThan(grid.red(CGPoint(x: 256, y: 200)), 200, "상자 가운데는 피부")
        XCTAssertLessThan(grid.red(CGPoint(x: 124, y: 200)), 20, "피부지만 안쪽으로 줄인 타원 밖")
    }

    func testDemoPortraitMaskCoversCheekAndNotPupil() throws {
        let url = try XCTUnwrap(
            Bundle.module.url(forResource: "demo-portrait", withExtension: "png", subdirectory: "Fixtures"))
        let image = try ImageLoader().load(url: url, maxDimension: 1200)
        let face = try XCTUnwrap(try VisionFaceAnalyzer().analyze(image).first)
        let grid = try Support.grid(
            FaceRegions.skinMask(face: face, image: image, extent: image.extent, tuning: RenderTuning()))
        let pupil = try XCTUnwrap(face.landmarks[.leftPupil]?.first)
        XCTAssertEqual(grid.red(CGPoint(x: pupil.x * image.extent.width, y: pupil.y * image.extent.height)), 0)
        let eye = try XCTUnwrap(face.bounds(of: .leftEye))
        let lips = try XCTUnwrap(face.bounds(of: .outerLips))
        let cheek = CGPoint(x: eye.midX * image.extent.width, y: (eye.minY + lips.maxY) / 2 * image.extent.height)
        XCTAssertGreaterThan(grid.red(cheek), 128, "실제 사진의 눈 아래 볼은 피부 마스크 안")
    }

    func testPolygonMaskCacheReusesRasterAndMatchesUncached() throws {
        let synthetic = SyntheticFace.make()
        let extent = synthetic.image.extent
        let tuning = RenderTuning()
        let fill = [FaceRegions.skinPolygon(face: synthetic.face, extent: extent, tuning: tuning)]
        let cut = FaceRegions.protectedPolygons(face: synthetic.face, extent: extent)
        let cache = RegionMaskCache()
        let first = FaceRegions.polygonMask(
            fill: fill, cut: cut, cutWidth: 28, extent: extent, tuning: tuning, cache: cache)
        let second = FaceRegions.polygonMask(
            fill: fill, cut: cut, cutWidth: 28, extent: extent, tuning: tuning, cache: cache)
        XCTAssertEqual(cache.count, 1, "같은 다각형·extent는 한 번만 그린다")
        XCTAssertTrue(first === second, "저장한 이미지를 그대로 돌려준다")
        let uncached = FaceRegions.polygonMask(fill: fill, cut: cut, cutWidth: 28, extent: extent, tuning: tuning)
        XCTAssertEqual(try Support.bytes(first), try Support.bytes(uncached))
        _ = FaceRegions.polygonMask(fill: fill, cut: cut, cutWidth: 14, extent: extent, tuning: tuning, cache: cache)
        XCTAssertEqual(cache.count, 2, "넓힘 폭이 다르면 다른 항목")
    }

    func testRegionMaskCacheEmptiesWhenFull() {
        let cache = RegionMaskCache()
        let extent = CGRect(x: 0, y: 0, width: 8, height: 8)
        for index in 0...RegionMaskCache.maximumEntries {
            let polygon = [CGPoint(x: 0, y: 0), CGPoint(x: CGFloat(index + 1), y: 0), CGPoint(x: 0, y: 4)]
            let key = RegionMaskKey(fill: [polygon], cut: [], cutWidth: 0, extent: extent, maxDimension: 512)
            _ = cache.mask(for: key) { CIImage(color: .white).cropped(to: extent) }
        }
        XCTAssertEqual(cache.count, 1, "상한을 넘으면 모두 비우고 새 항목 하나만 남는다")
    }
}
