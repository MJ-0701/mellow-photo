import CoreImage
import MellowShared
import XCTest

@testable import MellowRendering

final class VisionBodyAnalyzerTests: XCTestCase {
    typealias Support = RenderingTestSupport
    typealias Joint = VisionBodyAnalyzer.LocatedJoint

    func testBlankImageHasNoBody() throws {
        let blank = Support.solid(CIColor(red: 0.5, green: 0.6, blue: 0.7), size: 512)
        XCTAssertEqual(try VisionBodyAnalyzer().analyze(blank), [])
    }

    /// 데모 사진은 얼굴을 가까이 찍은 셀카라 계획 작성 때 측정으로 Vision이 사람을 찾지 않았다(0명).
    /// 실제 전신 인식은 이 테스트가 확인하지 않는다. 오류 없이 돌고 결과가 정렬·정규화돼 있는지만 본다.
    func testCloseUpSelfieAnalyzesWithoutThrowingAndKeepsOrder() throws {
        let url = try XCTUnwrap(
            Bundle.module.url(forResource: "demo-portrait", withExtension: "png", subdirectory: "Fixtures"))
        let image = try ImageLoader().load(url: url, maxDimension: 1600)
        let bodies = try VisionBodyAnalyzer().analyze(image)
        XCTAssertEqual(bodies.map(\.area), bodies.map(\.area).sorted(by: >), "큰 사람이 앞")
        for point in bodies.flatMap({ Array($0.joints.values) }) {
            XCTAssertTrue((0...1).contains(point.x) && (0...1).contains(point.y), "정규화 좌표")
        }
    }

    func testGeometryDropsUnfoundJointsAndBoxesTheRest() throws {
        let body = try XCTUnwrap(
            VisionBodyAnalyzer.geometry(from: [
                .neck: Joint(location: CGPoint(x: 0.5, y: 0.8), confidence: 0.9),
                .leftAnkle: Joint(location: CGPoint(x: 0.6, y: 0.1), confidence: 0.4),
                .rightAnkle: Joint(location: .zero, confidence: 0),
            ]))
        XCTAssertEqual(Set(body.joints.keys), [.neck, .leftAnkle], "신뢰도 0(찾지 못한 관절)은 버린다")
        XCTAssertEqual(body.confidence[.leftAnkle], 0.4)
        XCTAssertEqual(body.boundingBox.minX, 0.5, accuracy: 1e-9)
        XCTAssertEqual(body.boundingBox.minY, 0.1, accuracy: 1e-9)
        XCTAssertEqual(body.boundingBox.maxX, 0.6, accuracy: 1e-9)
        XCTAssertEqual(body.boundingBox.maxY, 0.8, accuracy: 1e-9)
        XCTAssertNil(
            VisionBodyAnalyzer.geometry(from: [.neck: Joint(location: .zero, confidence: 0)]), "남은 관절이 없으면 사람이 아니다")
    }

    func testOrderedLargestFirst() {
        let small = Support.standingBody(in: NormalizedRect(x: 0.7, y: 0.5, width: 0.2, height: 0.3))
        let large = Support.standingBody(in: Support.standingBox)
        XCTAssertEqual(VisionBodyAnalyzer.orderedLargestFirst([small, large]), [large, small])
    }
}
