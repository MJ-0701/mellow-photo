import XCTest

@testable import MellowShared

final class FaceGeometryTests: XCTestCase {
    private let tolerance = 1e-9

    func testBoundsOfLandmarkReturnsEnclosingRectInImageSpace() throws {
        let face = FaceGeometry(
            boundingBox: NormalizedRect(x: 0.2, y: 0.1, width: 0.6, height: 0.8),
            landmarks: [.leftEye: [NormalizedPoint(x: 0.3, y: 0.6), NormalizedPoint(x: 0.4, y: 0.65)]])
        let bounds = try XCTUnwrap(face.bounds(of: .leftEye))
        XCTAssertEqual(bounds.x, 0.3, accuracy: tolerance)
        XCTAssertEqual(bounds.y, 0.6, accuracy: tolerance)
        XCTAssertEqual(bounds.width, 0.1, accuracy: tolerance)
        XCTAssertEqual(bounds.height, 0.05, accuracy: tolerance)
        XCTAssertNil(face.bounds(of: .outerLips), "없는 랜드마크는 nil")
    }

    func testNormalizedRectConvertsToAndFromCGRect() {
        let rect = NormalizedRect(cgRect: CGRect(x: 0.1, y: 0.2, width: 0.3, height: 0.4))
        XCTAssertEqual(rect.cgRect, CGRect(x: 0.1, y: 0.2, width: 0.3, height: 0.4))
        XCTAssertEqual(rect.midX, 0.25, accuracy: tolerance)
    }
}
