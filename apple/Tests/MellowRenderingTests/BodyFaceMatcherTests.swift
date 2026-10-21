import CoreImage
import MellowShared
import XCTest

@testable import MellowRendering

final class BodyFaceMatcherTests: XCTestCase {
    /// 정사각형이라 정규화 거리와 픽셀 거리의 비율이 가로세로 같다.
    private let extent = CGRect(x: 0, y: 0, width: 1000, height: 1000)
    private let tuning = RenderTuning()
    /// 얼굴 상자 한 변(정규화). 2의 거듭제곱 분수라 상자 가운데가 정확히 기대점이다.
    private let faceSide = 0.25

    /// 아래 가운데에서 상자 높이 × bodyFaceNeckDrop 아래가 expected인 얼굴.
    private func face(expectingNeckAt expected: NormalizedPoint) -> FaceGeometry {
        let bottom = expected.y + faceSide * tuning.bodyFaceNeckDrop
        let box = NormalizedRect(x: expected.x - faceSide / 2, y: bottom, width: faceSide, height: faceSide)
        return FaceGeometry(boundingBox: box)
    }

    /// 주어진 관절만 신뢰도 1로 가진 몸.
    private func body(_ joints: [BodyJoint: NormalizedPoint]) -> BodyGeometry {
        BodyGeometry(joints: joints, confidence: joints.mapValues { _ in 1 })
    }

    private func neckBody(x: Double, y: Double) -> BodyGeometry {
        body([.neck: NormalizedPoint(x: x, y: y)])
    }

    func testNeckBelowFaceMatches() {
        let face = FaceGeometry(boundingBox: NormalizedRect(x: 0.4, y: 0.6, width: 0.2, height: 0.2))
        let matches = BodyFaceMatcher.match(
            bodies: [neckBody(x: 0.5, y: 0.55)], faces: [face], extent: extent, tuning: tuning)
        XCTAssertEqual(matches, [0: 0])
    }

    func testFarBodyDoesNotMatch() {
        let expected = NormalizedPoint(x: 0.5, y: 0.55)
        let far = 1.2 * faceSide
        let matches = BodyFaceMatcher.match(
            bodies: [neckBody(x: expected.x + far, y: expected.y)], faces: [face(expectingNeckAt: expected)],
            extent: extent, tuning: tuning)
        XCTAssertEqual(matches, [:], "얼굴 폭의 1.2배는 허용 거리 1.0배 밖이다")
        let near = 0.9 * faceSide
        let close = BodyFaceMatcher.match(
            bodies: [neckBody(x: expected.x + near, y: expected.y)], faces: [face(expectingNeckAt: expected)],
            extent: extent, tuning: tuning)
        XCTAssertEqual(close, [0: 0], "0.9배는 허용 거리 안이다")
    }

    func testGreedyOneToOneIsDeterministic() {
        // 몸 0–얼굴 1이 0.04로 가장 가까워 먼저 짝이 되고, 남은 몸 1–얼굴 0(0.15)이 그다음이다.
        // 거리 합이 가장 작은 짝(몸 0–얼굴 0 0.06 + 몸 1–얼굴 1 0.05)과 다르다.
        let faces = [
            face(expectingNeckAt: NormalizedPoint(x: 0.3, y: 0.55)),
            face(expectingNeckAt: NormalizedPoint(x: 0.4, y: 0.55)),
        ]
        let bodies = [neckBody(x: 0.36, y: 0.55), neckBody(x: 0.45, y: 0.55)]
        let matches = BodyFaceMatcher.match(bodies: bodies, faces: faces, extent: extent, tuning: tuning)
        XCTAssertEqual(matches, [0: 1, 1: 0], "거리 오름차순 탐욕")
        let expectedPairs = pairs(matches, bodies: bodies, faces: faces)
        let reversedBodies = Array(bodies.reversed())
        let reversedFaces = Array(faces.reversed())
        let reordered = BodyFaceMatcher.match(
            bodies: reversedBodies, faces: reversedFaces, extent: extent, tuning: tuning)
        XCTAssertEqual(pairs(reordered, bodies: reversedBodies, faces: reversedFaces), expectedPairs, "입력 순서와 무관")
        XCTAssertEqual(
            BodyFaceMatcher.match(bodies: bodies, faces: faces, extent: extent, tuning: tuning), matches, "다시 해도 같다")
    }

    func testEqualDistancesBreakTiesByBodyThenFaceIndex() {
        let faces = [face(expectingNeckAt: NormalizedPoint(x: 0.5, y: 0.55))]
        let bodies = [neckBody(x: 0.375, y: 0.55), neckBody(x: 0.625, y: 0.55)]
        let matches = BodyFaceMatcher.match(bodies: bodies, faces: faces, extent: extent, tuning: tuning)
        XCTAssertEqual(matches, [0: 0], "같은 거리면 몸 인덱스가 작은 쪽")
    }

    func testShoulderCenterWhenNeckMissing() {
        let face = face(expectingNeckAt: NormalizedPoint(x: 0.5, y: 0.55))
        let shoulders = body([
            .leftShoulder: NormalizedPoint(x: 0.6, y: 0.55), .rightShoulder: NormalizedPoint(x: 0.4, y: 0.55),
        ])
        XCTAssertEqual(
            BodyFaceMatcher.match(bodies: [shoulders], faces: [face], extent: extent, tuning: tuning), [0: 0],
            "두 어깨 중점이 목 자리다")
        let hipsOnly = body([.leftHip: NormalizedPoint(x: 0.55, y: 0.3), .rightHip: NormalizedPoint(x: 0.45, y: 0.3)])
        let oneShoulder = body([.leftShoulder: NormalizedPoint(x: 0.5, y: 0.55)])
        XCTAssertEqual(
            BodyFaceMatcher.match(bodies: [hipsOnly, oneShoulder], faces: [face], extent: extent, tuning: tuning), [:],
            "목도 두 어깨도 없으면 짝이 없다")
    }

    func testLowConfidenceNeckIsIgnored() {
        let face = face(expectingNeckAt: NormalizedPoint(x: 0.5, y: 0.55))
        let weak = BodyGeometry(
            joints: [.neck: NormalizedPoint(x: 0.5, y: 0.55)], confidence: [.neck: tuning.bodyJointMinConfidence / 2])
        XCTAssertEqual(BodyFaceMatcher.match(bodies: [weak], faces: [face], extent: extent, tuning: tuning), [:])
    }

    /// 인덱스 짝을 (목 x, 얼굴 상자 x) 짝으로 바꾼다. 입력 순서를 바꾼 결과와 비교한다.
    private func pairs(_ matches: [Int: Int], bodies: [BodyGeometry], faces: [FaceGeometry]) -> [String] {
        matches.map { bodyIndex, faceIndex in
            let neck = bodies[bodyIndex].joints[.neck]?.x ?? -1
            return "\(neck)|\(faces[faceIndex].boundingBox.x)"
        }.sorted()
    }
}
