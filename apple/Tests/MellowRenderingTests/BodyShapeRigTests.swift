import CoreImage
import MellowShared
import XCTest

@testable import MellowRendering

final class BodyShapeRigTests: XCTestCase {
    typealias Support = RenderingTestSupport
    typealias Push = (center: CGPoint, vector: CGVector, radius: CGFloat)

    private let extent = CGRect(x: 0, y: 0, width: 512, height: 512)
    private let tuning = RenderTuning()
    /// standingBox 사람의 어깨 폭(픽셀)과 몸 가운데 x.
    private let torsoWidth: CGFloat = 204.8
    private let midline: CGFloat = 256

    private func primitives(
        _ adjustments: BodyShapeAdjustments, body: BodyGeometry? = nil, tuning: RenderTuning? = nil
    ) -> [ShapePrimitive] {
        BodyShapeRig.primitives(
            body: body ?? Support.standingBody(in: Support.standingBox), adjustments: adjustments, extent: extent,
            tuning: tuning ?? self.tuning)
    }

    /// push 원소만 꺼낸다. push가 아닌 원소가 있으면 실패로 남긴다.
    private func pushes(_ primitives: [ShapePrimitive], file: StaticString = #filePath, line: UInt = #line) -> [Push] {
        primitives.compactMap { primitive in
            guard case .push(let center, let vector, let radius) = primitive else {
                XCTFail("push가 아니다: \(primitive)", file: file, line: line)
                return nil
            }
            return (center, vector, radius)
        }
    }

    private func distance(_ first: CGPoint, _ second: CGPoint) -> CGFloat {
        hypot(first.x - second.x, first.y - second.y)
    }

    func testWaistNegativePushesBothSidesTowardMidline() {
        let narrow = pushes(primitives(BodyShapeAdjustments(waist: -1)))
        XCTAssertEqual(narrow.count, 2)
        for push in narrow {
            let towardMidline: CGFloat = push.center.x < midline ? 1 : -1
            XCTAssertEqual(push.vector.dx, towardMidline * 0.06 * torsoWidth, accuracy: 1e-6, "어깨 폭 × 0.06만큼 중심선 쪽")
            XCTAssertEqual(push.vector.dy, 0, accuracy: 1e-9, "똑바로 선 사람은 가로로만")
            XCTAssertEqual(push.center.y, (0.8 + (0.5 - 0.8) * 0.55) * 512, accuracy: 1e-6, "어깨~엉덩이 55% 높이")
        }
        let rightSide = narrow.map(\.center.x).max() ?? 0
        XCTAssertEqual(rightSide, (0.1 + 0.8 * (0.75 + (0.62 - 0.75) * 0.55)) * 512, accuracy: 1e-6)
        let wide = pushes(primitives(BodyShapeAdjustments(waist: 1)))
        XCTAssertEqual(wide.count, 2)
        for (inward, outward) in zip(narrow, wide) {
            XCTAssertEqual(inward.vector.dx, -outward.vector.dx, accuracy: 1e-9, "+1은 반대 방향")
        }
    }

    func testOverallPushesThreeHeightsOnEachSideTowardMidline() {
        let result = pushes(primitives(BodyShapeAdjustments(overall: -1)))
        XCTAssertEqual(result.count, 6, "가슴·골반·허벅지 × 양옆")
        for push in result {
            let towardMidline: CGFloat = push.center.x < midline ? 1 : -1
            XCTAssertEqual(push.vector.dx, towardMidline * 0.035 * torsoWidth, accuracy: 1e-6)
            XCTAssertEqual(push.vector.dy, 0, accuracy: 1e-9)
        }
        let heights = Set(result.map { ($0.center.y * 10).rounded() / 10 })
        XCTAssertEqual(heights.count, 3, "높이 세 곳")
    }

    func testArmsAndThighsPushTowardTheirSegments() throws {
        let body = Support.standingBody(in: Support.standingBox)
        let skeleton = try XCTUnwrap(BodySkeleton(body: body, extent: extent, tuning: tuning))
        let cases: [(BodyShapeAdjustments, [(BodyJoint, BodyJoint)])] = [
            (
                BodyShapeAdjustments(arms: -1),
                [
                    (.leftShoulder, .leftElbow), (.leftElbow, .leftWrist), (.rightShoulder, .rightElbow),
                    (.rightElbow, .rightWrist),
                ]
            ),
            (BodyShapeAdjustments(thighs: -1), [(.leftHip, .leftKnee), (.rightHip, .rightKnee)]),
        ]
        for (adjustments, segments) in cases {
            let middles = try segments.map { start, end in
                BodySkeleton.midpoint(try XCTUnwrap(skeleton.point(start)), try XCTUnwrap(skeleton.point(end)))
            }
            let result = pushes(primitives(adjustments, body: body))
            XCTAssertEqual(result.count, segments.count * 2, "선분마다 양옆 두 점")
            for push in result {
                let nearest = try XCTUnwrap(middles.min { distance($0, push.center) < distance($1, push.center) })
                let toward = CGVector(dx: nearest.x - push.center.x, dy: nearest.y - push.center.y)
                XCTAssertGreaterThan(push.vector.dx * toward.dx + push.vector.dy * toward.dy, 0, "선분 쪽으로 민다")
            }
        }
    }

    func testShouldersMoveOutwardAndNeckLowersShoulderLine() throws {
        let wider = pushes(primitives(BodyShapeAdjustments(shoulders: 1)))
        XCTAssertEqual(wider.count, 2)
        for push in wider {
            let outward: CGFloat = push.center.x > midline ? 1 : -1
            XCTAssertEqual(push.vector.dx, outward * 0.04 * torsoWidth, accuracy: 1e-6, "양수는 바깥으로")
            XCTAssertEqual(push.center.y, 0.8 * 512, accuracy: 1e-6, "어깨 관절 자리")
        }
        let narrower = pushes(primitives(BodyShapeAdjustments(shoulders: -1)))
        for (out, inward) in zip(wider, narrower) {
            XCTAssertEqual(out.vector.dx, -inward.vector.dx, accuracy: 1e-9)
        }
        let longer = pushes(primitives(BodyShapeAdjustments(neck: 1)))
        XCTAssertEqual(longer.count, 3, "목 관절과 양쪽 승모근 점")
        for push in longer {
            XCTAssertEqual(push.vector.dy, -0.03 * torsoWidth, accuracy: 1e-6, "양수는 어깨선을 아래로")
            XCTAssertEqual(push.vector.dx, 0, accuracy: 1e-9)
        }
        let neckJoint = CGPoint(x: midline, y: 0.82 * 512)
        XCTAssertTrue(longer.contains { distance($0.center, neckJoint) < 1e-6 }, "목 관절 자리")
        let slopeY = 0.82 * 512 + (0.8 - 0.82) * 512 * 0.4
        XCTAssertEqual(longer.filter { abs($0.center.y - slopeY) < 1e-6 }.count, 2, "목 관절~어깨 40% 지점 양쪽")
        let shorter = pushes(primitives(BodyShapeAdjustments(neck: -1)))
        for (down, up) in zip(longer, shorter) {
            XCTAssertEqual(down.vector.dy, -up.vector.dy, accuracy: 1e-9, "음수는 위로")
        }
    }

    func testNeckLengthensByLoweringShoulderLineAndLeavesChin() throws {
        /// 턱 끝은 목 관절에서 어깨 폭의 약 0.25~0.3 위다.
        let chinRise: CGFloat = 0.28
        /// 목 관절에서 어깨 쪽으로 이 비율 간 승모근 비탈 점.
        let slopeLevel: CGFloat = 0.2
        let limit = tuning.shapeDisplacementLimit
        let skeleton = try XCTUnwrap(
            BodySkeleton(body: Support.standingBody(in: Support.standingBox), extent: extent, tuning: tuning))
        let neckBase = try XCTUnwrap(skeleton.point(.neck))
        let chin = CGPoint(x: neckBase.x, y: neckBase.y + chinRise * torsoWidth)
        let slopes = try [BodyJoint.leftShoulder, .rightShoulder].map { joint in
            BodySkeleton.lerp(neckBase, try XCTUnwrap(skeleton.point(joint)), slopeLevel)
        }
        let maxShift = CGFloat(tuning.bodyNeckMaxShift) * torsoWidth
        for sign in [CGFloat(-1), 1] {
            let result = primitives(BodyShapeAdjustments(neck: Double(sign)))
            let atChin = DisplacementWarp.displacement(at: chin, of: result, limit: limit)
            let atBase = DisplacementWarp.displacement(at: neckBase, of: result, limit: limit)
            let neckChange = atChin.dy - atBase.dy
            XCTAssertGreaterThan(neckChange * sign, 0.9 * maxShift, "값 방향으로 목이 길어지거나 짧아진다(\(neckChange)px)")
            let chinShift = hypot(atChin.dx, atChin.dy)
            XCTAssertLessThan(chinShift, 0.1 * maxShift, "턱·입은 끌려가지 않는다(턱 이동 \(chinShift)px)")
            XCTAssertEqual(atBase.dx, 0, accuracy: 1e-9, "목 아래끝은 세로로만")
            let slopeShifts = slopes.map { DisplacementWarp.displacement(at: $0, of: result, limit: limit) }
            for shift in slopeShifts {
                XCTAssertLessThan(shift.dy * sign, -0.9 * maxShift, "양쪽 어깨 비탈이 함께 내려가거나 올라간다")
            }
            XCTAssertEqual(slopeShifts[0].dx, -slopeShifts[1].dx, accuracy: 1e-9, "좌우 대칭")
            XCTAssertEqual(slopeShifts[0].dy, slopeShifts[1].dy, accuracy: 1e-9, "좌우 대칭")
        }
    }

    func testLegLengthMakesOneBandFromHipsToAnkles() throws {
        let result = primitives(BodyShapeAdjustments(legLength: 0.5))
        XCTAssertEqual(result.count, 1)
        guard case .band(let start, let end, let stretch) = try XCTUnwrap(result.first) else {
            return XCTFail("띠가 아니다")
        }
        XCTAssertEqual(start, 256, accuracy: 1e-6, "두 엉덩이 중점 높이")
        XCTAssertEqual(end, 25.6, accuracy: 1e-6, "발목 높이")
        XCTAssertEqual(stretch, 0.04, accuracy: 1e-9, "값 × 0.08")
        let oneAnkle = Support.standingBody(in: Support.standingBox, omitting: [.leftAnkle])
        XCTAssertEqual(primitives(BodyShapeAdjustments(legLength: 1), body: oneAnkle).count, 1, "발목 하나로도 만든다")
        let pivot = NormalizedPoint(x: 0.5, y: 0.5)
        let upsideDown = Support.standingBody(in: Support.standingBox).rotated(by: .pi, about: pivot)
        XCTAssertTrue(primitives(BodyShapeAdjustments(legLength: 1), body: upsideDown).isEmpty, "엉덩이가 발목보다 아래면 건너뛴다")
        let lying = Support.standingBody(in: Support.standingBox).rotated(by: .pi / 2, about: pivot)
        XCTAssertTrue(primitives(BodyShapeAdjustments(legLength: 1), body: lying).isEmpty, "누운 사람은 건너뛴다")
    }

    func testMissingOrLowConfidenceJointsSkipOnlyTheirItems() {
        let all = BodyShapeAdjustments(
            legLength: 1, waist: -1, overall: -1, arms: -1, thighs: -1, shoulders: 1, neck: 1)
        let full = Support.standingBody(in: Support.standingBox)
        XCTAssertEqual(primitives(all, body: full).count, 1 + 2 + 6 + 8 + 4 + 2 + 3)
        let upperBody = Support.standingBody(
            in: Support.standingBox,
            omitting: [.leftHip, .rightHip, .leftKnee, .rightKnee, .leftAnkle, .rightAnkle, .root])
        XCTAssertEqual(primitives(all, body: upperBody).count, 8 + 2 + 3, "엉덩이가 없으면 팔·어깨·목만 남는다")
        for key in [BodyShapeKey.legLength, .waist, .overall, .thighs] {
            var single = BodyShapeAdjustments()
            single[key] = key == .legLength ? 1 : -1
            XCTAssertTrue(primitives(single, body: upperBody).isEmpty, "\(key)")
        }
        var faintKnee = full
        faintKnee.confidence[.leftKnee] = 0.29
        XCTAssertEqual(primitives(BodyShapeAdjustments(thighs: -1), body: faintKnee).count, 2, "신뢰도 낮은 무릎 쪽 허벅지만 빠진다")
        XCTAssertEqual(primitives(BodyShapeAdjustments(overall: -1), body: faintKnee).count, 5, "그쪽 허벅지 높이만 빠진다")
        let noElbows = Support.standingBody(in: Support.standingBox, omitting: [.leftElbow, .rightElbow])
        XCTAssertTrue(primitives(BodyShapeAdjustments(arms: -1), body: noElbows).isEmpty)
        let noNeck = Support.standingBody(in: Support.standingBox, omitting: [.neck])
        XCTAssertTrue(primitives(BodyShapeAdjustments(neck: 1), body: noNeck).isEmpty)
        let oneShoulder = Support.standingBody(in: Support.standingBox, omitting: [.leftShoulder])
        XCTAssertTrue(primitives(all, body: oneShoulder).isEmpty, "어깨 폭이 없으면 모든 항목을 건너뛴다")
    }

    func testZeroNaNAndOutOfRangeValues() {
        XCTAssertTrue(primitives(BodyShapeAdjustments()).isEmpty)
        XCTAssertTrue(primitives(BodyShapeAdjustments(waist: .nan, neck: .infinity)).isEmpty, "유한하지 않은 값은 0")
        XCTAssertTrue(
            primitives(BodyShapeAdjustments(legLength: .nan, arms: -.infinity, shoulders: .nan)).isEmpty,
            "NaN을 클램프 아래 끝(−1)으로 보내 최대 음수 효과를 걸지 않는다")
        XCTAssertEqual(
            primitives(BodyShapeAdjustments(waist: .nan, overall: -0.5)),
            primitives(BodyShapeAdjustments(overall: -0.5)),
            "유한하지 않은 항목만 0이고 나머지는 그대로")
        XCTAssertEqual(
            primitives(BodyShapeAdjustments(waist: -3, arms: 7)), primitives(BodyShapeAdjustments(waist: -1, arms: 1)))
        XCTAssertTrue(primitives(BodyShapeAdjustments(legLength: -0.5)).isEmpty, "다리 길게는 0 아래가 없다")
        XCTAssertEqual(primitives(BodyShapeAdjustments(legLength: 4)), primitives(BodyShapeAdjustments(legLength: 1)))
    }

    func testBodyPushesAreNeverCappedByDisplacementLimit() {
        let limit = tuning.shapeDisplacementLimit
        for sign in [-1.0, 1.0] {
            let extreme = BodyShapeAdjustments(
                legLength: 1, waist: sign, overall: sign, arms: sign, thighs: sign, shoulders: sign, neck: sign)
            for primitive in primitives(extreme) {
                XCTAssertEqual(primitive.limited(to: limit), primitive, "얼굴과 같은 상한이 체형 이동을 줄이지 않는다: \(primitive)")
            }
        }
        var strong = RenderTuning()
        strong.bodyShapeMaxShift = 0.2
        strong.bodyWaistMaxShift = 0.2
        for push in pushes(primitives(BodyShapeAdjustments(waist: -1), tuning: strong)) {
            let primitive = ShapePrimitive.push(center: push.center, vector: push.vector, radius: push.radius)
            XCTAssertEqual(primitive.limited(to: limit), primitive, "튜닝을 키우면 반지름도 따라 커진다")
            XCTAssertEqual(abs(push.vector.dx), 0.2 * torsoWidth, accuracy: 1e-6)
        }
        var capped = RenderTuning()
        capped.bodyWaistMaxShift = 0.5
        let shifts = pushes(primitives(BodyShapeAdjustments(waist: -1), tuning: capped)).map { abs($0.vector.dx) }
        XCTAssertEqual(shifts.max() ?? 0, 0.06 * torsoWidth, accuracy: 1e-6, "항목 최대는 bodyShapeMaxShift(0.06)를 넘지 않는다")
    }

    func testTiltedBodyPushesFollowTorsoAxis() throws {
        let angle = Double.pi / 6
        // CGVector 성분과 곱할 때 cos·sin 오버로드가 모호해지지 않도록 CGFloat로 미리 바꾼다(Xcode 26 컴파일러).
        let cosine = CGFloat(cos(angle))
        let sine = CGFloat(sin(angle))
        let body = Support.standingBody(in: Support.standingBox).rotated(
            by: angle, about: NormalizedPoint(x: 0.5, y: 0.5))
        let waist = pushes(primitives(BodyShapeAdjustments(waist: -1), body: body))
        XCTAssertEqual(waist.count, 2)
        for push in waist {
            let length = hypot(push.vector.dx, push.vector.dy)
            XCTAssertEqual(length, 0.06 * torsoWidth, accuracy: 1e-6)
            let alongAcross = push.vector.dx * cosine + push.vector.dy * sine
            XCTAssertEqual(abs(alongAcross), length, accuracy: 1e-6, "몸통 가로축(cos 30°, sin 30°)과 평행")
        }
        let neck = pushes(primitives(BodyShapeAdjustments(neck: 1), body: body))
        XCTAssertEqual(neck.count, 3)
        for push in neck {
            XCTAssertEqual(push.vector.dx, sine * 0.03 * torsoWidth, accuracy: 1e-6, "목은 몸통 아래쪽으로")
            XCTAssertEqual(push.vector.dy, -cosine * 0.03 * torsoWidth, accuracy: 1e-6)
        }
    }

    func testCombinedEditsDoNotFold() {
        let limit = tuning.shapeDisplacementLimit
        let standing = Support.standingBody(in: Support.standingBox)
        let tilted = standing.rotated(by: .pi / 6, about: NormalizedPoint(x: 0.5, y: 0.5))
        var worst = CGFloat.infinity
        for body in [standing, tilted] {
            for sign in [-1.0, 1.0] {
                for key in BodyShapeKey.allCases where key != .legLength {
                    var single = BodyShapeAdjustments()
                    single[key] = sign
                    let singleJacobian = Support.minimumJacobian(
                        of: primitives(single, body: body), limit: limit, in: extent)
                    worst = min(worst, singleJacobian)
                }
                let all = BodyShapeAdjustments(
                    legLength: 1, waist: sign, overall: sign, arms: sign, thighs: sign, shoulders: sign, neck: sign)
                worst = min(worst, Support.minimumJacobian(of: primitives(all, body: body), limit: limit, in: extent))
            }
        }
        XCTAssertGreaterThan(worst, 0.2, "겹치는 체형 원소가 이미지를 접지 않는다(최소 야코비안 \(worst))")
    }

    func testSymmetricBodyGetsMirroredPushes() {
        let all = BodyShapeAdjustments(waist: -1, overall: -1, arms: 1, thighs: -1, shoulders: 1, neck: 1)
        let result = pushes(primitives(all))
        XCTAssertEqual(result.count, 2 + 6 + 8 + 4 + 2 + 3)
        for push in result {
            let mirrored = result.contains { other in
                abs(other.center.x - (2 * midline - push.center.x)) < 1e-6 && abs(other.center.y - push.center.y) < 1e-6
                    && abs(other.vector.dx + push.vector.dx) < 1e-6 && abs(other.vector.dy - push.vector.dy) < 1e-6
                    && abs(other.radius - push.radius) < 1e-6
            }
            XCTAssertTrue(mirrored, "좌우 대칭인 사람은 중심선 반대편에 거울상 원소가 있다: \(push)")
        }
    }

    func testSideChestPushesBothTorsoSidesInward() {
        let result = pushes(primitives(BodyShapeAdjustments(sideChest: 1)))
        XCTAssertEqual(result.count, 2)
        let level: CGFloat = 0.27
        for push in result {
            let left = push.center.x < midline
            let shoulderX: CGFloat = left ? 0.25 : 0.75
            let hipX: CGFloat = left ? 0.38 : 0.62
            let expectedX = (0.1 + 0.8 * (shoulderX + (hipX - shoulderX) * level)) * 512
            XCTAssertEqual(push.center.x, expectedX, accuracy: 1e-6, "어깨~엉덩이 27% 점")
            XCTAssertEqual(push.center.y, (0.8 + (0.5 - 0.8) * level) * 512, accuracy: 1e-6)
            let towardMidline: CGFloat = left ? 1 : -1
            XCTAssertEqual(push.vector.dx, towardMidline * 0.03 * torsoWidth, accuracy: 1e-6, "몸통 가로축 안쪽")
            XCTAssertEqual(push.vector.dy, 0, accuracy: 1e-9)
            XCTAssertGreaterThanOrEqual(push.radius, 0.14 * torsoWidth - 1e-9)
        }
    }

    func testSideChestNeedsHips() {
        let upperBody = Support.standingBody(in: Support.standingBox, omitting: [.leftHip, .rightHip])
        XCTAssertTrue(primitives(BodyShapeAdjustments(sideChest: 1), body: upperBody).isEmpty)
        let oneHip = Support.standingBody(in: Support.standingBox, omitting: [.leftHip])
        XCTAssertTrue(primitives(BodyShapeAdjustments(sideChest: 1), body: oneHip).isEmpty, "두 엉덩이가 있어야 한다")
    }

    func testSideChestIsTorsoGroup() {
        let parts = BodyShapeRig.groups(
            body: Support.standingBody(in: Support.standingBox), adjustments: BodyShapeAdjustments(sideChest: 1),
            extent: extent, tuning: tuning, includesLegBand: true)
        XCTAssertEqual(parts.torso.count, 2)
        XCTAssertTrue(parts.limbs.isEmpty)
        XCTAssertEqual(parts.guards.count, 4, "몸통 묶음은 두 팔의 위팔·아래팔 캡슐을 받는다")
    }

    // MARK: 몸통 옆선(스펙 5.8)

    /// 27%·30% 높이의 양쪽 옆선 점. 관절선 점(x 168·344)보다 바깥이다. sides에 없는 쪽은 뺀다.
    private func outline(sides: Set<Int> = [-1, 1]) -> BodyOutline {
        var points: [OutlineKey: NormalizedPoint] = [:]
        for level in [0.27, 0.3] {
            for side in sides {
                let x = side < 0 ? 0.30 : 0.71
                points[OutlineKey(level: level, side: side)] = NormalizedPoint(x: x, y: 0.72 - level * 0.1)
            }
        }
        return BodyOutline(points: points)
    }

    private func outlined(
        _ adjustments: BodyShapeAdjustments, outline: BodyOutline?, extent: CGRect? = nil
    ) -> [ShapePrimitive] {
        BodyShapeRig.primitives(
            body: Support.standingBody(in: Support.standingBox), adjustments: adjustments,
            extent: extent ?? self.extent, tuning: tuning, outline: outline)
    }

    private func pixel(_ point: NormalizedPoint, in extent: CGRect) -> CGPoint {
        CGPoint(x: extent.minX + point.x * extent.width, y: extent.minY + point.y * extent.height)
    }

    func testSideChestCentersAreTheOutlinePoints() throws {
        let given = outline()
        let joint = pushes(primitives(BodyShapeAdjustments(sideChest: 1)))
        let result = pushes(outlined(BodyShapeAdjustments(sideChest: 1), outline: given))
        XCTAssertEqual(result.count, 2)
        for (push, old) in zip(result, joint) {
            let side = push.center.x < midline ? -1 : 1
            let expected = pixel(try XCTUnwrap(given.points[OutlineKey(level: 0.27, side: side)]), in: extent)
            XCTAssertEqual(push.center.x, expected.x, accuracy: 1e-9, "옆선 점이 원소 중심")
            XCTAssertEqual(push.center.y, expected.y, accuracy: 1e-9)
            XCTAssertEqual(push.vector.dx, old.vector.dx, accuracy: 1e-9, "방향·이동은 관절선 원소와 같다")
            XCTAssertEqual(push.vector.dy, old.vector.dy, accuracy: 1e-9)
            XCTAssertEqual(push.radius, old.radius, accuracy: 1e-9)
        }
    }

    func testSideChestSkipsTheSideWithoutAnOutlinePoint() {
        let result = pushes(outlined(BodyShapeAdjustments(sideChest: 1), outline: outline(sides: [1])))
        XCTAssertEqual(result.count, 1, "팔이 붙은 쪽은 원소가 없다")
        XCTAssertGreaterThan(result.first?.center.x ?? 0, midline, "남은 원소는 +1 쪽(화면 오른쪽)")
        XCTAssertTrue(outlined(BodyShapeAdjustments(sideChest: 1), outline: BodyOutline(points: [:])).isEmpty)
    }

    func testWithoutOutlineSideChestAndOverallKeepTheJointLine() {
        let all = BodyShapeAdjustments(
            legLength: 1, waist: -1, overall: -1, arms: -1, thighs: -1, shoulders: 1, neck: 1, sideChest: 1)
        XCTAssertEqual(outlined(all, outline: nil), primitives(all), "마스크가 없으면 이 Task 전과 같은 원소")
    }

    func testOverallChestUsesTheOutlineAndKeepsHipAndThigh() throws {
        let given = outline(sides: [-1])
        let joint = pushes(primitives(BodyShapeAdjustments(overall: -1)))
        let result = pushes(outlined(BodyShapeAdjustments(overall: -1), outline: given))
        let chestY = (0.8 + (0.5 - 0.8) * 0.3) * 512
        let jointChest = joint.filter { abs($0.center.y - chestY) < 1e-6 }
        XCTAssertEqual(jointChest.count, 2)
        let lower = { (pushes: [Push]) in pushes.filter { abs($0.center.y - chestY) >= 1e-6 } }
        let expected = pixel(try XCTUnwrap(given.points[OutlineKey(level: 0.3, side: -1)]), in: extent)
        let chest = result.filter { abs($0.center.x - expected.x) < 1e-9 && abs($0.center.y - expected.y) < 1e-9 }
        XCTAssertEqual(chest.count, 1, "가슴은 옆선 점 하나(+1 쪽은 점이 없어 빠짐)")
        XCTAssertEqual(result.count, 5)
        let jointLower = lower(joint)
        let resultLower = result.filter {
            abs($0.center.x - expected.x) >= 1e-9 || abs($0.center.y - expected.y) >= 1e-9
        }
        XCTAssertEqual(resultLower.count, jointLower.count, "골반·허벅지는 그대로")
        for (pushed, old) in zip(resultLower, jointLower) {
            XCTAssertEqual(pushed.center, old.center)
            XCTAssertEqual(pushed.vector, old.vector)
            XCTAssertEqual(pushed.radius, old.radius)
        }
        let waist = outlined(BodyShapeAdjustments(waist: -1), outline: given)
        XCTAssertEqual(waist, primitives(BodyShapeAdjustments(waist: -1)), "허리는 옆선을 쓰지 않는다")
    }

    func testOutlinePointsScaleWithTheExtent() throws {
        let given = outline()
        let preview = pushes(outlined(BodyShapeAdjustments(sideChest: 1), outline: given))
        let large = CGRect(x: 0, y: 0, width: 1024, height: 1024)
        let original = pushes(outlined(BodyShapeAdjustments(sideChest: 1), outline: given, extent: large))
        XCTAssertEqual(original.count, preview.count)
        for (big, small) in zip(original, preview) {
            XCTAssertEqual(big.center.x, small.center.x * 2, accuracy: 1e-9, "정규화 좌표라 원본 해상도에서도 같은 자리")
            XCTAssertEqual(big.center.y, small.center.y * 2, accuracy: 1e-9)
        }
    }
}
