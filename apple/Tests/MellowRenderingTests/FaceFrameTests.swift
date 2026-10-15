import CoreImage
import MellowShared
import XCTest

@testable import MellowRendering

final class FaceFrameTests: XCTestCase {
    private let extent = SyntheticFace.extent
    private let thirtyDegrees = Double.pi / 6

    private func frame(_ face: FaceGeometry) throws -> FaceFrame {
        try XCTUnwrap(FaceFrame(face: face, extent: extent))
    }

    private func assertAxis(_ axis: CGVector, angle: Double, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(axis.dx, CGFloat(cos(angle)), accuracy: 1e-6, file: file, line: line)
        XCTAssertEqual(axis.dy, CGFloat(sin(angle)), accuracy: 1e-6, file: file, line: line)
    }

    func testNoContourHasNoFrame() {
        XCTAssertNil(FaceFrame(face: SyntheticFace.make(landmarks: false).face, extent: extent))
        XCTAssertNil(FaceFrame(face: SyntheticFace.make().face.removing([.faceContour]), extent: extent))
    }

    func testUprightSyntheticFaceUsesPupilAxis() throws {
        let upright = try frame(SyntheticFace.make().face)
        XCTAssertEqual(upright.origin.x, 256, accuracy: 1e-6)
        XCTAssertEqual(upright.origin.y, 200, accuracy: 1e-6)
        assertAxis(upright.xAxis, angle: 0)
        assertAxis(upright.yAxis, angle: Double.pi / 2)
        XCTAssertEqual(upright.faceWidth, 280, accuracy: 1e-6)
        XCTAssertEqual(upright.eyeLevel, 100, accuracy: 1e-6)
        XCTAssertEqual(upright.mouthLevel, -60, accuracy: 1e-6)
        XCTAssertEqual(upright.contour.count, 17)
        XCTAssertEqual(upright.eyes.count, 2)
        for eye in upright.eyes {
            XCTAssertEqual(eye.width, 56, accuracy: 1e-6, "눈 영역의 x축 방향 폭")
        }
        let local = upright.local(CGPoint(x: 312, y: 300))
        XCTAssertEqual(local.x, 56, accuracy: 1e-6)
        XCTAssertEqual(local.y, 100, accuracy: 1e-6)
        let back = upright.imagePoint(u: local.x, v: local.y)
        XCTAssertEqual(back.x, 312, accuracy: 1e-6)
        XCTAssertEqual(back.y, 300, accuracy: 1e-6)
    }

    func testRotatedFaceRotatesAxesAndKeepsLevels() throws {
        let tilted = try frame(SyntheticFace.make().face.rotated(by: thirtyDegrees, about: SyntheticFace.pivot))
        assertAxis(tilted.xAxis, angle: thirtyDegrees)
        assertAxis(tilted.yAxis, angle: thirtyDegrees + Double.pi / 2)
        XCTAssertEqual(tilted.eyeLevel, 100, accuracy: 1e-6)
        XCTAssertEqual(tilted.mouthLevel, -60, accuracy: 1e-6)
        let shift = tilted.vector(u: 10, v: 0)
        XCTAssertEqual(shift.dx, CGFloat(10 * cos(thirtyDegrees)), accuracy: 1e-6)
        XCTAssertEqual(shift.dy, CGFloat(10 * sin(thirtyDegrees)), accuracy: 1e-6)
    }

    func testUpsideDownFaceFlipsAxesSoUpPointsToEyes() throws {
        let flipped = try frame(SyntheticFace.make().face.rotated(by: Double.pi, about: SyntheticFace.pivot))
        assertAxis(flipped.xAxis, angle: Double.pi)
        assertAxis(flipped.yAxis, angle: -Double.pi / 2)
        XCTAssertEqual(flipped.eyeLevel, 100, accuracy: 1e-6)
        XCTAssertEqual(flipped.mouthLevel, -60, accuracy: 1e-6)
    }

    func testFallsBackToEyeCentersThenRoll() throws {
        let tilted = SyntheticFace.make().face.rotated(by: thirtyDegrees, about: SyntheticFace.pivot)
        let eyesOnly = try frame(tilted.removing([.leftPupil, .rightPupil]))
        assertAxis(eyesOnly.xAxis, angle: thirtyDegrees)
        XCTAssertEqual(eyesOnly.eyeLevel, 100, accuracy: 1e-6)
        let rollOnly = try frame(tilted.removing([.leftPupil, .rightPupil, .leftEye, .rightEye]))
        assertAxis(rollOnly.xAxis, angle: thirtyDegrees)
        XCTAssertTrue(rollOnly.eyes.isEmpty)
        XCTAssertEqual(rollOnly.eyeLevel, 300 * 0.13, accuracy: 1e-6, "눈이 없으면 상자 높이 비율")
        let nothing = try frame(SyntheticFace.make().face.removing([.leftPupil, .rightPupil, .leftEye, .rightEye]))
        assertAxis(nothing.xAxis, angle: 0)
    }

    func testCoincidentPupilsFallBackToRollWithoutNaN() throws {
        var face = SyntheticFace.make().face
        let middle = NormalizedPoint(x: 0.5, y: 300.0 / 512)
        face.landmarks[.leftPupil] = [middle]
        face.landmarks[.rightPupil] = [middle]
        face.roll = thirtyDegrees
        let degenerate = try frame(face)
        assertAxis(degenerate.xAxis, angle: thirtyDegrees)
        XCTAssertTrue(degenerate.eyeLevel.isFinite)
        XCTAssertTrue(degenerate.mouthLevel.isFinite)
    }

    func testEyesUseRegionWidthOrFallback() throws {
        var narrow = SyntheticFace.make().face
        for landmark in [FaceLandmark.leftEye, .rightEye] {
            let points = narrow.landmarks[landmark] ?? []
            let centerX = points.map(\.x).reduce(0, +) / Double(points.count)
            let centerY = points.map(\.y).reduce(0, +) / Double(points.count)
            narrow.landmarks[landmark] = points.map {
                NormalizedPoint(x: centerX + ($0.x - centerX) / 2, y: centerY + ($0.y - centerY) / 2)
            }
        }
        for eye in try frame(narrow).eyes {
            XCTAssertEqual(eye.width, 28, accuracy: 1e-6, "눈 영역을 절반으로 줄이면 폭도 절반")
        }
        let fallback = try frame(narrow.removing([.leftEye, .rightEye]))
        XCTAssertEqual(fallback.eyes.count, 2, "눈동자만 있어도 눈은 둘")
        for eye in fallback.eyes {
            XCTAssertEqual(eye.width, 280 * 0.2, accuracy: 1e-6, "눈 영역이 없으면 얼굴 폭의 20%")
        }
    }
}
