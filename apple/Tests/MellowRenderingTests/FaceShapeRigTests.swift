import CoreImage
import MellowShared
import XCTest

@testable import MellowRendering

final class FaceShapeRigTests: XCTestCase {
    typealias Support = RenderingTestSupport

    private struct Push {
        let center: CGPoint
        let vector: CGVector
        let radius: CGFloat
    }

    private struct Scale {
        let center: CGPoint
        let factor: CGFloat
        let radius: CGFloat
    }

    private let extent = SyntheticFace.extent
    private let tuning = RenderTuning()
    /// 합성 얼굴의 얼굴 폭(상자 가로)과 중심선(픽셀).
    private let faceWidth: CGFloat = 280
    private let midline: CGFloat = 256

    private func primitives(
        _ adjustments: FaceShapeAdjustments, face: FaceGeometry = SyntheticFace.make().face
    ) -> [ShapePrimitive] {
        FaceShapeRig.primitives(face: face, adjustments: adjustments, extent: extent, tuning: tuning)
    }

    /// 열 항목 모두 0.6(미소 포함).
    private var allKeys: FaceShapeAdjustments {
        var adjustments = FaceShapeAdjustments()
        for key in FaceShapeKey.allCases {
            adjustments[key] = 0.6
        }
        return adjustments
    }

    private func pushes(_ list: [ShapePrimitive]) -> [Push] {
        list.compactMap { primitive in
            guard case .push(let center, let vector, let radius) = primitive else { return nil }
            return Push(center: center, vector: vector, radius: radius)
        }
    }

    private func scales(_ list: [ShapePrimitive]) -> [Scale] {
        list.compactMap { primitive in
            guard case .scale(let center, let factor, let radius) = primitive else { return nil }
            return Scale(center: center, factor: factor, radius: radius)
        }
    }

    private func mirrored(_ primitive: ShapePrimitive) -> ShapePrimitive {
        switch primitive {
        case .push(let center, let vector, let radius):
            return .push(
                center: CGPoint(x: 2 * midline - center.x, y: center.y),
                vector: CGVector(dx: -vector.dx, dy: vector.dy), radius: radius)
        case .scale(let center, let factor, let radius):
            return .scale(center: CGPoint(x: 2 * midline - center.x, y: center.y), factor: factor, radius: radius)
        case .band:
            return primitive
        }
    }

    /// 상자 중심(256, 200) 둘레로 angle만큼 반시계로 돌린다.
    private func rotated(_ primitive: ShapePrimitive, by angle: Double) -> ShapePrimitive {
        let pivot = CGPoint(x: SyntheticFace.box.midX, y: SyntheticFace.box.midY)
        let cosine = CGFloat(cos(angle))
        let sine = CGFloat(sin(angle))
        func turn(_ vector: CGVector) -> CGVector {
            CGVector(dx: vector.dx * cosine - vector.dy * sine, dy: vector.dx * sine + vector.dy * cosine)
        }
        func move(_ point: CGPoint) -> CGPoint {
            let turned = turn(CGVector(dx: point.x - pivot.x, dy: point.y - pivot.y))
            return CGPoint(x: pivot.x + turned.dx, y: pivot.y + turned.dy)
        }
        switch primitive {
        case .push(let center, let vector, let radius):
            return .push(center: move(center), vector: turn(vector), radius: radius)
        case .scale(let center, let factor, let radius):
            return .scale(center: move(center), factor: factor, radius: radius)
        case .band:
            return primitive
        }
    }

    private func approximatelyEqual(_ a: ShapePrimitive, _ b: ShapePrimitive) -> Bool {
        let tolerance: CGFloat = 1e-6
        switch (a, b) {
        case (.push(let c1, let v1, let r1), .push(let c2, let v2, let r2)):
            return hypot(c1.x - c2.x, c1.y - c2.y) < tolerance && hypot(v1.dx - v2.dx, v1.dy - v2.dy) < tolerance
                && abs(r1 - r2) < tolerance
        case (.scale(let c1, let f1, let r1), .scale(let c2, let f2, let r2)):
            return hypot(c1.x - c2.x, c1.y - c2.y) < tolerance && abs(f1 - f2) < tolerance && abs(r1 - r2) < tolerance
        default:
            return false
        }
    }

    func testZeroValuesProduceNoPrimitives() {
        XCTAssertTrue(primitives(FaceShapeAdjustments()).isEmpty)
    }

    func testNoContourProducesNoPrimitives() {
        XCTAssertTrue(primitives(allKeys, face: SyntheticFace.make(landmarks: false).face).isEmpty)
        XCTAssertTrue(primitives(allKeys, face: SyntheticFace.make().face.removing([.faceContour])).isEmpty)
    }

    func testNarrowWidthPushesLeftContourRightAndRightContourLeft() {
        let list = pushes(primitives(FaceShapeAdjustments(width: -1)))
        XCTAssertEqual(list.count, 6, "눈~입 높이 윤곽점 한쪽 3개씩")
        let left = list.filter { $0.center.x < midline }
        let right = list.filter { $0.center.x > midline }
        XCTAssertEqual(left.count, 3)
        XCTAssertEqual(right.count, 3)
        for push in left {
            XCTAssertGreaterThan(push.vector.dx, 0, "왼쪽 윤곽은 +x")
            XCTAssertEqual(push.vector.dy, 0, accuracy: 1e-9)
        }
        for push in right {
            XCTAssertLessThan(push.vector.dx, 0, "오른쪽 윤곽은 −x")
        }
        let leftTotal = left.map(\.vector.dx).reduce(0, +)
        XCTAssertEqual(leftTotal, faceWidth * CGFloat(tuning.faceWidthMaxShift), accuracy: 1e-6, "한쪽 합 = 얼굴 폭 × 최대")
    }

    func testJawPushesInwardAndUpExcludingChinCenter() {
        let list = pushes(primitives(FaceShapeAdjustments(jaw: -1)))
        XCTAssertEqual(list.count, 10, "입 아래 윤곽점 한쪽 5개씩, 턱 끝 가까운 점 제외")
        for push in list {
            XCTAssertLessThan(push.center.y, SyntheticFace.mouth.y, "입 아래")
            XCTAssertGreaterThanOrEqual(abs(push.center.x - midline), faceWidth * 0.1)
            XCTAssertGreaterThan(push.vector.dy, 0, "V라인은 위로")
            XCTAssertEqual(push.vector.dx > 0, push.center.x < midline, "안쪽으로")
        }
    }

    func testCheekboneForeheadAndChinDirections() {
        let cheek = pushes(primitives(FaceShapeAdjustments(cheekbone: -1)))
        XCTAssertEqual(cheek.count, 2)
        let cheekShift = faceWidth * CGFloat(tuning.faceCheekboneMaxShift)
        for push in cheek {
            XCTAssertEqual(push.center.y, 240, accuracy: 1e-6, "각 쪽 가장 높은 윤곽점")
            XCTAssertEqual(push.vector.dx, push.center.x < midline ? cheekShift : -cheekShift, accuracy: 1e-6)
        }
        let forehead = pushes(primitives(FaceShapeAdjustments(forehead: 1)))
        XCTAssertEqual(forehead.count, 1)
        XCTAssertEqual(forehead[0].center.x, midline, accuracy: 1e-6)
        XCTAssertGreaterThan(forehead[0].center.y, SyntheticFace.leftBrow.maxY, "눈썹 위")
        XCTAssertEqual(
            forehead[0].vector.dy, faceWidth * CGFloat(tuning.faceForeheadMaxShift), accuracy: 1e-6, "이마가 위로")
        let chin = pushes(primitives(FaceShapeAdjustments(chinLength: 1)))
        XCTAssertEqual(chin.count, 1)
        XCTAssertEqual(chin[0].center.y, 50, accuracy: 1e-6, "턱 끝")
        XCTAssertEqual(
            chin[0].vector.dy, -faceWidth * CGFloat(tuning.faceChinLengthMaxShift), accuracy: 1e-6, "턱이 아래로")
    }

    func testEyeNoseAndMouthKeys() {
        let eyes = scales(primitives(FaceShapeAdjustments(eyeSize: 1)))
        let eyeXs = eyes.map(\.center.x).sorted()
        XCTAssertEqual(eyeXs, [SyntheticFace.leftEye.x, SyntheticFace.rightEye.x], "각 눈동자 중심")
        for eye in eyes {
            XCTAssertEqual(eye.factor, CGFloat(tuning.faceEyeSizeMaxScale), accuracy: 1e-9, "양수면 확대")
            XCTAssertEqual(eye.radius, 56 * 1.2, accuracy: 1e-6, "반지름 = 눈 폭 × 1.2")
        }
        let apart = pushes(primitives(FaceShapeAdjustments(eyeDistance: 1)))
        XCTAssertEqual(apart.count, 2)
        for push in apart {
            XCTAssertEqual(push.vector.dx < 0, push.center.x < midline, "중심선에서 멀어진다")
        }
        let nose = pushes(primitives(FaceShapeAdjustments(noseWidth: -1)))
        XCTAssertEqual(nose.map(\.center.x).sorted(), [236, 276], "코 날개 두 점")
        for push in nose {
            XCTAssertEqual(push.vector.dx > 0, push.center.x < midline, "코 날개가 가운데로")
            XCTAssertEqual(abs(push.vector.dx), faceWidth * CGFloat(tuning.faceNoseWidthMaxShift), accuracy: 1e-6)
        }
        let mouth = scales(primitives(FaceShapeAdjustments(mouthSize: 1)))
        XCTAssertEqual(mouth.count, 1)
        XCTAssertEqual(mouth[0].center.x, SyntheticFace.mouth.x, accuracy: 1e-6)
        XCTAssertEqual(mouth[0].center.y, SyntheticFace.mouth.y, accuracy: 1e-6)
        XCTAssertGreaterThan(mouth[0].factor, 0)
        let smile = pushes(primitives(FaceShapeAdjustments(smile: 1)))
        XCTAssertEqual(smile.count, 2)
        for push in smile {
            XCTAssertGreaterThan(push.vector.dy, 0, "입꼬리가 위로")
            XCTAssertEqual(push.vector.dx < 0, push.center.x < midline, "입꼬리가 바깥으로")
        }
    }

    func testAllKeysAreMirrorSymmetric() {
        let list = primitives(allKeys)
        XCTAssertGreaterThan(list.count, 20)
        for primitive in list {
            let mirror = mirrored(primitive)
            XCTAssertTrue(list.contains { approximatelyEqual($0, mirror) }, "\(primitive)의 거울 원소가 없다")
        }
    }

    func testRollRotatesPrimitives() {
        let angle = Double.pi / 6
        let tiltedFace = SyntheticFace.make().face.rotated(by: angle, about: SyntheticFace.pivot)
        let upright = primitives(allKeys)
        let tilted = primitives(allKeys, face: tiltedFace)
        XCTAssertEqual(tilted.count, upright.count)
        for (expected, actual) in zip(upright.map { rotated($0, by: angle) }, tilted) {
            XCTAssertTrue(approximatelyEqual(expected, actual), "\(actual) ≠ \(expected)")
        }
        for push in pushes(primitives(FaceShapeAdjustments(width: -1), face: tiltedFace)) {
            let vectorAngle = atan2(Double(push.vector.dy), Double(push.vector.dx))
            XCTAssertEqual(sin(vectorAngle - angle), 0, accuracy: 1e-6, "얼굴 폭 벡터도 30° 기운다")
        }
    }

    func testValuesOutsideRangeAreClamped() {
        XCTAssertEqual(primitives(FaceShapeAdjustments(width: -3)), primitives(FaceShapeAdjustments(width: -1)))
        XCTAssertEqual(primitives(FaceShapeAdjustments(eyeSize: 7)), primitives(FaceShapeAdjustments(eyeSize: 1)))
        XCTAssertTrue(primitives(FaceShapeAdjustments(smile: -0.5)).isEmpty, "미소는 0…1")
    }

    func testYawAttenuatesContinuouslyAndVanishesAtProfile() {
        var face = SyntheticFace.make().face
        let straight = primitives(FaceShapeAdjustments(width: -1), face: face)
        face.yaw = tuning.faceShapeYawThreshold
        XCTAssertEqual(primitives(FaceShapeAdjustments(width: -1), face: face), straight, "기준값에서는 약화 없음")
        face.yaw = -0.6
        let turned = pushes(primitives(FaceShapeAdjustments(width: -1), face: face))
        let ratio = CGFloat(cos(0.6) / cos(tuning.faceShapeYawThreshold))
        XCTAssertEqual(turned[0].vector.dx, pushes(straight)[0].vector.dx * ratio, accuracy: 1e-9)
        face.yaw = Double.pi / 4
        XCTAssertFalse(primitives(allKeys, face: face).isEmpty, "Vision의 45° 얼굴은 약하게 남는다")
        face.yaw = Double.pi / 2
        XCTAssertTrue(primitives(allKeys, face: face).isEmpty, "옆얼굴은 원소 없음")
    }

    func testMissingFeatureLandmarksSkipOnlyThatKey() {
        let noNose = SyntheticFace.make().face.removing([.nose])
        XCTAssertTrue(primitives(FaceShapeAdjustments(noseWidth: -1), face: noNose).isEmpty)
        XCTAssertEqual(primitives(FaceShapeAdjustments(width: -1), face: noNose).count, 6)
        let noLips = SyntheticFace.make().face.removing([.outerLips])
        XCTAssertTrue(primitives(FaceShapeAdjustments(mouthSize: 1, smile: 1), face: noLips).isEmpty)
        XCTAssertFalse(primitives(FaceShapeAdjustments(width: -1), face: noLips).isEmpty)
        let noEyes = SyntheticFace.make().face.removing([.leftPupil, .rightPupil, .leftEye, .rightEye])
        XCTAssertTrue(primitives(FaceShapeAdjustments(eyeSize: 1, eyeDistance: 1), face: noEyes).isEmpty)
        XCTAssertEqual(primitives(FaceShapeAdjustments(forehead: 1), face: noEyes).count, 1, "눈썹으로 이마 위치를 잡는다")
    }

    func testExtremeCombinationsNeverFold() {
        let combinations: [[Double]] = [
            [1, 1, 1, 1, 1, 1, 1, 1, 1, 1],
            [-1, -1, -1, -1, -1, -1, -1, 1, -1, -1],
            [1, -1, 1, -1, -1, 1, -1, 1, 1, -1],
        ]
        let region = CGRect(x: 50, y: 20, width: 412, height: 470)
        for values in combinations {
            var adjustments = FaceShapeAdjustments()
            for (key, value) in zip(FaceShapeKey.allCases, values) {
                adjustments[key] = value
            }
            let worst = Support.minimumJacobian(
                of: primitives(adjustments), limit: tuning.shapeDisplacementLimit, in: region)
            XCTAssertGreaterThan(worst, 0.2, "\(values)에서 이미지가 접힌다")
        }
    }

    func testDemoPortraitLandmarksDriveEveryKey() throws {
        let url = try XCTUnwrap(
            Bundle.module.url(forResource: "demo-portrait", withExtension: "png", subdirectory: "Fixtures"))
        let image = try ImageLoader().load(url: url, maxDimension: 1200)
        let face = try XCTUnwrap(try VisionFaceAnalyzer().analyze(image).first)
        for key in FaceShapeKey.allCases {
            var adjustments = FaceShapeAdjustments()
            adjustments[key] = 1
            let list = FaceShapeRig.primitives(
                face: face, adjustments: adjustments, extent: image.extent, tuning: tuning)
            XCTAssertFalse(list.isEmpty, "\(key): 실제 특징점으로 원소가 생긴다")
        }
        let frame = try XCTUnwrap(FaceFrame(face: face, extent: image.extent))
        XCTAssertGreaterThan(frame.yAxis.dy, 0, "똑바로 선 사진의 얼굴 위쪽은 이미지 위쪽")
        let narrow = FaceShapeRig.primitives(
            face: face, adjustments: FaceShapeAdjustments(width: -1), extent: image.extent, tuning: tuning)
        for case .push(let center, let vector, _) in narrow {
            let side = frame.local(center).x
            let along = vector.dx * frame.xAxis.dx + vector.dy * frame.xAxis.dy
            XCTAssertLessThan(side * along, 0, "얼굴 폭 −1은 중심선 쪽")
        }
    }

    func testOutOfRangeValuesMatchClampedValues() {
        XCTAssertEqual(
            primitives(FaceShapeAdjustments(width: 5, smile: -1)), primitives(FaceShapeAdjustments(width: 1)),
            "프리셋·일괄 적용 값도 rig가 자른다")
        var wild = FaceShapeAdjustments()
        var clamped = FaceShapeAdjustments()
        for key in FaceShapeKey.allCases {
            wild[key] = -4
            clamped[key] = key == .smile ? 0 : -1
        }
        XCTAssertEqual(primitives(wild), primitives(clamped))
    }

    func testCoincidentPupilsSkipEyePrimitives() {
        var together = SyntheticFace.make().face
        together.landmarks[.rightPupil] = together.landmarks[.leftPupil]
        var nearly = SyntheticFace.make().face
        nearly.landmarks[.rightPupil] = [NormalizedPoint(x: 202.0 / 512, y: 300.0 / 512)]
        for face in [together, nearly] {
            XCTAssertTrue(
                primitives(FaceShapeAdjustments(eyeSize: 1, eyeDistance: 1), face: face).isEmpty,
                "한 점에 눈 원소를 두 번 걸지 않는다")
            XCTAssertEqual(primitives(FaceShapeAdjustments(width: -1), face: face).count, 6, "다른 항목은 그대로")
        }
    }

    /// 손으로 계산한 기대값. 원점은 상자 중심(256, 200)이다.
    /// 이마: 눈썹 위끝 y 344(v 144)에서 0.3 × 280 = 84 위인 (256, 428), 이동 0.05 × 280 = 14, 반지름 0.35 × 280 = 98.
    /// 반지름 절반 거리에서 smoothstep 감쇠는 0.5라 이동이 7이다.
    /// 얼굴 폭: 왼쪽 첫 윤곽점 (84, 240)에 0.06 × 280 / 3 = 5.6, 반지름 0.22 × 280 = 61.6.
    /// 턱 끝: (256, 50)에 아래로 14, 반지름 0.25 × 280 = 70.
    func testHandComputedDisplacements() throws {
        let forehead = pushes(primitives(FaceShapeAdjustments(forehead: 1)))
        XCTAssertEqual(forehead.count, 1)
        let top = try XCTUnwrap(forehead.first)
        XCTAssertEqual(top.center.x, 256, accuracy: 1e-9)
        XCTAssertEqual(top.center.y, 428, accuracy: 1e-9)
        XCTAssertEqual(top.radius, 98, accuracy: 1e-9)
        let list = primitives(FaceShapeAdjustments(forehead: 1))
        let limit = tuning.shapeDisplacementLimit
        let samples: [(point: CGPoint, dy: CGFloat)] = [
            (CGPoint(x: 256, y: 428), 14), (CGPoint(x: 256, y: 477), 7), (CGPoint(x: 305, y: 428), 7),
            (CGPoint(x: 256, y: 330), 0),
        ]
        for sample in samples {
            let shift = DisplacementWarp.displacement(at: sample.point, of: list, limit: limit)
            XCTAssertEqual(shift.dx, 0, accuracy: 1e-9)
            XCTAssertEqual(shift.dy, sample.dy, accuracy: 1e-9, "\(sample.point)")
        }
        let width = pushes(primitives(FaceShapeAdjustments(width: -1)))
        let temple = try XCTUnwrap(width.first { hypot($0.center.x - 84, $0.center.y - 240) < 1e-6 })
        XCTAssertEqual(temple.vector.dx, 5.6, accuracy: 1e-9)
        XCTAssertEqual(temple.vector.dy, 0, accuracy: 1e-9)
        XCTAssertEqual(temple.radius, 61.6, accuracy: 1e-9)
        let chin = try XCTUnwrap(pushes(primitives(FaceShapeAdjustments(chinLength: 1))).first)
        XCTAssertEqual(chin.center.x, 256, accuracy: 1e-9)
        XCTAssertEqual(chin.center.y, 50, accuracy: 1e-9)
        XCTAssertEqual(chin.vector.dy, -14, accuracy: 1e-9)
        XCTAssertEqual(chin.radius, 70, accuracy: 1e-9)
    }
}
