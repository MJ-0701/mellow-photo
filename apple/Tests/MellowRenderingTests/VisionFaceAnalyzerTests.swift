import CoreImage
import MellowShared
import XCTest

@testable import MellowRendering

final class VisionFaceAnalyzerTests: XCTestCase {
    func testDemoPortraitYieldsFullLandmarksInImageSpace() throws {
        let url = try XCTUnwrap(
            Bundle.module.url(forResource: "demo-portrait", withExtension: "png", subdirectory: "Fixtures"))
        let image = try ImageLoader().load(url: url, maxDimension: 1200)
        let faces = try VisionFaceAnalyzer().analyze(image)
        let face = try XCTUnwrap(faces.first)
        for landmark in [FaceLandmark.faceContour, .leftEye, .rightEye, .outerLips, .nose] {
            let points = try XCTUnwrap(face.landmarks[landmark], "\(landmark) 누락")
            XCTAssertGreaterThan(points.count, 2)
            for point in points {
                XCTAssertGreaterThanOrEqual(point.x, face.boundingBox.minX - 0.05)
                XCTAssertLessThanOrEqual(point.x, face.boundingBox.maxX + 0.05)
                XCTAssertGreaterThanOrEqual(point.y, face.boundingBox.minY - 0.05)
                XCTAssertLessThanOrEqual(point.y, face.boundingBox.maxY + 0.05)
            }
        }
        let leftEye = try XCTUnwrap(face.bounds(of: .leftEye))
        let mouth = try XCTUnwrap(face.bounds(of: .outerLips))
        XCTAssertGreaterThan(leftEye.midY, mouth.midY, "눈은 입보다 위(원점이 왼쪽 아래)")
    }

    func testFacesAreOrderedLeftToRight() throws {
        let analyzer = VisionFaceAnalyzer()
        let blank = CIImage(color: CIColor(red: 0.5, green: 0.4, blue: 0.3)).cropped(
            to: CGRect(x: 0, y: 0, width: 64, height: 64))
        XCTAssertEqual(try analyzer.analyze(blank).count, 0)
        let faces = [
            FaceGeometry(boundingBox: NormalizedRect(x: 0.6, y: 0, width: 0.2, height: 0.2)),
            FaceGeometry(boundingBox: NormalizedRect(x: 0.1, y: 0, width: 0.2, height: 0.2)),
        ]
        XCTAssertEqual(VisionFaceAnalyzer.orderedLeftToRight(faces).map(\.boundingBox.minX), [0.1, 0.6])
    }
}
