import CoreImage
import MellowShared
import XCTest

@testable import MellowRendering

/// 점 지우기 제외 영역(스펙 G5 4.2).
final class SpotRegionsTests: XCTestCase {
    typealias Support = RenderingTestSupport

    /// 코 다각형 높이 중 콧구멍 띠 안으로 보는 표본 높이 비율.
    private static let nostrilSampleFraction = 0.15
    /// 코 다각형 높이 중 띠 밖(콧대)으로 보는 표본 높이 비율.
    private static let bridgeSampleFraction = 0.8
    /// 제외 비트맵이 칠해졌다고 보는 바이트 하한.
    private static let paintedMinimum: UInt8 = 128
    /// 볼 가운데 표본 점(눈·코·입에서 떨어진 곳).
    private static let cheek = CGPoint(x: 200, y: 200)
    /// 두 눈의 안쪽·바깥쪽 꼬리 넷과 입꼬리 둘(스펙 G5 4.2 (b)·(c)).
    private static let cornerCount = 6

    func testExclusionCoversNostrilBandEyeAndMouthCornersOnly() throws {
        let synthetic = SyntheticFace.make()
        let face = synthetic.face
        let extent = synthetic.image.extent
        let raster = FaceRegions.spotExclusionRaster(face: face, extent: extent, tuning: RenderTuning(), cache: nil)
        let grid = try Support.grid(raster.cropped(to: extent))
        let nose = try XCTUnwrap(face.bounds(of: .nose))
        let nostril = CGPoint(
            x: nose.midX * Double(extent.width),
            y: (nose.minY + nose.height * Self.nostrilSampleFraction) * Double(extent.height))
        let bridge = CGPoint(
            x: nose.midX * Double(extent.width),
            y: (nose.minY + nose.height * Self.bridgeSampleFraction) * Double(extent.height))
        let leftEye = try XCTUnwrap(face.bounds(of: .leftEye))
        let eyeCorner = CGPoint(x: leftEye.minX * Double(extent.width), y: leftEye.midY * Double(extent.height))
        let lips = try XCTUnwrap(face.bounds(of: .outerLips))
        let mouthCorner = CGPoint(x: lips.maxX * Double(extent.width), y: lips.midY * Double(extent.height))
        XCTAssertGreaterThanOrEqual(grid.red(nostril), Self.paintedMinimum, "콧구멍 띠")
        XCTAssertEqual(grid.red(bridge), 0, "코 윗부분은 제외하지 않는다")
        XCTAssertGreaterThanOrEqual(grid.red(eyeCorner), Self.paintedMinimum, "눈꼬리")
        XCTAssertGreaterThanOrEqual(grid.red(mouthCorner), Self.paintedMinimum, "입꼬리")
        XCTAssertEqual(grid.red(Self.cheek), 0, "볼은 제외하지 않는다")
    }

    func testMissingLandmarksDropOnlyThatExclusion() throws {
        let extent = CGRect(x: 0, y: 0, width: SyntheticFace.size, height: SyntheticFace.size)
        let full = FaceRegions.spotExclusionPolygons(
            face: SyntheticFace.make().face, extent: extent, tuning: RenderTuning())
        XCTAssertEqual(full.count, Self.cornerCount + 1, "콧구멍 띠 하나와 꼬리 원 여섯")
        let face = SyntheticFace.make().face.removing([.nose])
        let polygons = FaceRegions.spotExclusionPolygons(face: face, extent: extent, tuning: RenderTuning())
        XCTAssertEqual(polygons.count, Self.cornerCount, "코가 없으면 눈꼬리 넷·입꼬리 둘만")
    }
}
