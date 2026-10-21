import CoreImage
import MellowShared
import XCTest

@testable import MellowRendering

/// 이중턱·부유방·체형의 실사진 수용 테스트(스펙 I 1절 "자연스러움 기준"·7.2).
/// 사진은 생성 체형 사진 4장(Fixtures/body)이고 앱과 같은 PhotoPipeline(실제 Vision)으로 준비한다.
/// 이동량은 렌더와 같은 묶음·같은 지도(보호 가중치 포함)를 읽어 재고, 그늘 밝기·배경·남녀 규칙은 렌더 픽셀로 잰다.
/// 폰 px = 미리보기 px × 1170 / 미리보기 폭이다.
/// 기준을 못 맞추면 기준이 아니라 렌더 상수를 스펙 범위 안에서 고친다.
final class ShapeAcceptanceTests: XCTestCase {
    /// 하한(보여야 함). 폰 px.
    enum Visibility {
        static let doubleChinPhoneShift: CGFloat = 3
        static let sideChestPhoneShift: CGFloat = 2
        static let bodyItemPhoneShift: CGFloat = 2
    }

    /// 상한(과하면 안 됨).
    enum Naturalness {
        /// 이중턱 최대 이동. 얼굴 폭 비율.
        static let doubleChinShiftFraction: CGFloat = 0.045
        /// 턱선·턱 끝 윤곽점 이동. 폰 px.
        static let jawPhoneShift: CGFloat = 0.5
        /// 바깥 입술 점 이동. 미리보기 px("입술 이동 0"을 부동소수 오차로 잰다).
        static let lipShift: CGFloat = 0.05
        /// 턱밑 그늘 띠 평균 휘도 증가. 8비트.
        static let chinShadeLift = 12.0
        /// 부유방 이동. 어깨 폭 비율.
        static let sideChestShiftFraction: CGFloat = 0.035
        /// 팔 영역 최대 이동. 몸통 윤곽 이동 대비.
        static let armShare: CGFloat = 0.15
        /// 격자선 위치 이동. 미리보기 px.
        static let lineBend: CGFloat = 0.5
        /// 실루엣 띠 밖 배경과 옆 사람 마스크 안의 바뀐 픽셀 비율(폰 배율, Δ ≥ 4).
        static let changedFraction = 0.002
    }

    /// 측정 자리.
    enum Layout {
        /// 이중턱 띠. 턱 끝 아래 얼굴 좌표 거리, 얼굴 폭 비율.
        static let chinBandTop: CGFloat = 0.05
        static let chinBandBottom: CGFloat = 0.25
        /// 부유방 원소 높이. 어깨~엉덩이 비율이고 렌더 rig 값 그대로다.
        static let sideChestLevel = CGFloat(BodyShapeRig.sideChestOutlineLevel)
        /// 몸 전체 가슴 원소 높이. 어깨~엉덩이 비율이고 렌더 rig 값 그대로다.
        static let chestLevel = CGFloat(BodyShapeRig.chestOutlineLevel)
        /// 사람 마스크 안으로 보는 값.
        static let maskHalf: CGFloat = 0.5
        /// 배경 보호 띠 폭 = 묶음 최대 이동 × bandShiftScale + bandMargin(미리보기 px).
        static let bandShiftScale: CGFloat = 4
        static let bandMargin: CGFloat = 4
        /// 격자 간격과 선 두께(미리보기 px).
        static let gridSpacing = 8
        static let gridLineWidth = 2
        /// 격자선 위치를 재는 창의 시작(선 왼쪽·아래 칸 수). 창 폭은 간격과 같아 선 하나만 든다.
        static let gridWindowLead = 3
        /// 선과 수직 방향으로 재는 줄. 간격 안 이 칸들(교차점 둘레를 피함)에서만 잰다.
        static let gridProbeOffsets = 3...6
    }

    private static let chin = "chin-01.jpg"
    private static let torso = "torso-01.jpg"
    private static let couple = "couple-body-01.jpg"
    private static let lines = "lines-01.jpg"

    /// VALIDATION 실측 표에 옮길 측정 줄(`shape-acceptance <사진> <항목> <지표>=<값>`).
    @discardableResult
    private func record(_ photo: String, _ item: String, _ metric: String, _ value: CGFloat) -> CGFloat {
        print("shape-acceptance \(photo) \(item) \(metric)=\(String(format: "%.4f", Double(value)))")
        return value
    }

    private func photo(_ file: String) async throws -> RealBodyPhoto {
        try await RealBodyPhoto.prepared(file)
    }

    // MARK: 사진 분석

    func testFixturesAreAnalyzable() async throws {
        let chin = try await photo(Self.chin)
        XCTAssertEqual(chin.analysis.faces.count, 1, "chin-01 얼굴 1개")
        let face = try XCTUnwrap(chin.analysis.faces.first)
        let frame = try XCTUnwrap(FaceFrame(face: face, extent: chin.extent))
        let lower = frame.contour.filter { frame.local($0).y < frame.mouthLevel }
        record("chin-01", "analysis", "lowerContourPoints", CGFloat(lower.count))
        XCTAssertGreaterThanOrEqual(lower.count, 3, "chin-01 아래턱 윤곽점 3개 이상")
        XCTAssertTrue(
            FaceShapeRig.doubleChinApplies(face: face, extent: chin.extent, tuning: chin.tuning), "이중턱 원소가 생기는 얼굴")
        for file in [Self.torso, Self.lines] {
            let single = try await photo(file)
            XCTAssertEqual(single.analysis.bodies.count, 1, "\(file) 몸 1개")
            XCTAssertEqual(single.analysis.faces.count, 1, "\(file) 얼굴 1개")
            let skeleton = try single.skeleton(0)
            for joint in [BodyJoint.leftShoulder, .rightShoulder, .leftHip, .rightHip, .leftElbow, .rightElbow] {
                XCTAssertNotNil(skeleton.point(joint), "\(file) \(joint)")
            }
            XCTAssertEqual(single.analysis.bodyFaceMatches, [0: 0], "\(file) 얼굴과 몸이 짝이다")
            record(file, "analysis", "instances", CGFloat(single.analysis.personInstances.count))
        }
        let couple = try await photo(Self.couple)
        XCTAssertEqual(couple.analysis.faces.count, 2, "커플 얼굴 2개")
        XCTAssertEqual(couple.analysis.bodies.count, 2, "커플 몸 2개")
        XCTAssertEqual(couple.analysis.bodyFaceMatches.count, 2, "커플 얼굴–몸 2쌍")
        XCTAssertEqual(Set(couple.analysis.bodyFaceMatches.values), [0, 1])
        record("couple-body-01", "analysis", "instances", CGFloat(couple.analysis.personInstances.count))
        for body in couple.analysis.bodies.indices {
            let skeleton = try couple.skeleton(body)
            for joint in [BodyJoint.leftShoulder, .rightShoulder, .leftHip, .rightHip] {
                XCTAssertNotNil(skeleton.point(joint), "커플 몸 \(body) \(joint)")
            }
        }
    }

    // MARK: 이중턱

    func testDoubleChinIsVisibleAndNatural() async throws {
        let chin = try await photo(Self.chin)
        var recipe = EditRecipe()
        recipe.portrait.face.doubleChin = 1
        let face = try XCTUnwrap(chin.analysis.faces.first)
        let frame = try XCTUnwrap(FaceFrame(face: face, extent: chin.extent))
        let width = frame.faceWidth
        let field = try chin.fieldPatch(recipe)
        let lips = frame.points(.outerLips).map { frame.local($0).x }
        let left = try XCTUnwrap(lips.min())
        let right = try XCTUnwrap(lips.max())
        let tip = try XCTUnwrap(frame.contour.map(frame.local).filter { left <= $0.x && $0.x <= right }.map(\.y).min())
        let top = tip - Layout.chinBandTop * width
        let bottom = tip - Layout.chinBandBottom * width
        var upward: CGFloat = 0
        var largest: CGFloat = 0
        for point in field.pixelCenters {
            let vector = field.vector(at: point)
            largest = max(largest, hypot(vector.dx, vector.dy))
            let local = frame.local(point)
            guard left <= local.x, local.x <= right, bottom <= local.y, local.y <= top else { continue }
            upward = max(upward, vector.dx * frame.yAxis.dx + vector.dy * frame.yAxis.dy)
        }
        record("chin-01", "doubleChin", "faceWidth", width)
        record("chin-01", "doubleChin", "bandMaxUpwardPhone", upward * chin.phoneScale)
        record("chin-01", "doubleChin", "maxShiftOverFaceWidth", largest / width)
        XCTAssertGreaterThanOrEqual(upward * chin.phoneScale, Visibility.doubleChinPhoneShift, "턱밑 띠가 폰에서 보이게 올라간다")
        XCTAssertLessThanOrEqual(largest, width * Naturalness.doubleChinShiftFraction, "최대 이동은 얼굴 폭의 4.5% 이하")
        let jaw = frame.contour.map { field.vector(at: $0) }.map { hypot($0.dx, $0.dy) }.max() ?? 0
        record("chin-01", "doubleChin", "contourMaxPhone", jaw * chin.phoneScale)
        XCTAssertLessThanOrEqual(jaw * chin.phoneScale, Naturalness.jawPhoneShift, "턱선·턱 끝은 움직이지 않는다")
        let lip = frame.points(.outerLips).map { field.vector(at: $0) }.map { hypot($0.dx, $0.dy) }.max() ?? 0
        record("chin-01", "doubleChin", "lipMax", lip)
        XCTAssertLessThanOrEqual(lip, Naturalness.lipShift, "입술은 움직이지 않는다")
        let band = try XCTUnwrap(
            FaceRegions.chinBandMask(face: face, extent: chin.extent, tuning: chin.tuning, cache: nil), "턱밑 띠")
        let weights = FloatPatch(band, in: chin.extent)
        let before = PixelGrid(try await chin.preview(EditRecipe()))
        let after = PixelGrid(try await chin.preview(recipe))
        let lift = ShapeTestSupport.weightedLumaDelta(before, after, weights: weights)
        record("chin-01", "chinShade", "bandMeanLumaLift", CGFloat(lift))
        XCTAssertLessThanOrEqual(lift, Naturalness.chinShadeLift, "턱밑 그늘 밝기 증가는 12/255 이하")
    }

    // MARK: 부유방

    func testSideChestIsVisibleAndNatural() async throws {
        let torso = try await photo(Self.torso)
        let face = try XCTUnwrap(torso.analysis.faces.first)
        var recipe = EditRecipe()
        recipe.people.groups[.female] = PortraitLayer(body: [.sideChest: 1])
        recipe.people.individuals = [PersonRecord(anchor: PersonAnchor(faceBox: face.boundingBox), gender: .female)]
        let body = try torso.body(matching: 0)
        XCTAssertEqual(torso.context(recipe).bodyTargets[body].adjustments.sideChest, 1, "여성으로 지정한 사람의 몸이 부유방을 받는다")
        let found = outlineSides(torso, recipe: recipe, body: body, level: Layout.sideChestLevel, item: "sideChest")
        XCTAssertGreaterThan(found, 0, "torso-01은 부유방 높이에서 적어도 한쪽 옆선이 팔에서 떨어져 있어야 한다")
        let field = try torso.fieldPatch(recipe)
        let skeleton = try torso.skeleton(body)
        let centers = try elementCenters(torso, recipe: recipe, body: body, key: .sideChest)
        XCTAssertEqual(centers.count, found, "옆선 점이 있는 쪽마다 원소가 하나다")
        let shifts = centers.map { field.vector(at: $0) }.map { hypot($0.dx, $0.dy) }
        for (index, shift) in shifts.enumerated() {
            record("torso-01", "sideChest", "center\(index)Phone", shift * torso.phoneScale)
            record("torso-01", "sideChest", "center\(index)OverShoulder", shift / skeleton.torsoWidth)
            XCTAssertGreaterThanOrEqual(shift * torso.phoneScale, Visibility.sideChestPhoneShift, "옆가슴 윤곽이 폰에서 보인다")
            XCTAssertLessThanOrEqual(
                shift, skeleton.torsoWidth * Naturalness.sideChestShiftFraction, "부유방 이동은 어깨 폭의 3.5% 이하")
        }
        let arm = try armMaximum(torso, recipe: recipe, body: body, field: field)
        let reference = try XCTUnwrap(shifts.min())
        record("torso-01", "sideChest", "armMaxOverSide", arm / reference)
        XCTAssertLessThanOrEqual(arm, reference * Naturalness.armShare, "팔 영역 이동은 옆가슴 이동의 15% 이하")
    }

    /// 스펙 7.2 팔 끌림: 허리 −1·부유방 1을 함께 켜도 팔은 몸통 윤곽 이동의 15% 이하이고 두 윤곽은 하한을 넘는다.
    func testTorsoItemsDoNotDragTheArms() async throws {
        let torso = try await photo(Self.torso)
        let face = try XCTUnwrap(torso.analysis.faces.first)
        var recipe = EditRecipe()
        recipe.people.individuals = [
            PersonRecord(
                anchor: PersonAnchor(faceBox: face.boundingBox),
                layer: PortraitLayer(body: [.waist: -1, .sideChest: 1]))
        ]
        let body = try torso.body(matching: 0)
        let found = outlineSides(torso, recipe: recipe, body: body, level: Layout.sideChestLevel, item: "armDrag")
        XCTAssertGreaterThan(found, 0, "부유방 옆선 점이 적어도 한쪽에 있다")
        let field = try torso.fieldPatch(recipe)
        var outline: [CGFloat] = []
        for key in [BodyShapeKey.sideChest, .waist] {
            for (index, center) in try elementCenters(torso, recipe: recipe, body: body, key: key).enumerated() {
                let vector = field.vector(at: center)
                let shift = hypot(vector.dx, vector.dy)
                outline.append(shift)
                record("torso-01", "armDrag", "\(key)Center\(index)Phone", shift * torso.phoneScale)
                XCTAssertGreaterThanOrEqual(shift * torso.phoneScale, Visibility.bodyItemPhoneShift, "\(key) 윤곽이 보인다")
            }
        }
        let arm = try armMaximum(torso, recipe: recipe, body: body, field: field)
        let reference = try XCTUnwrap(outline.max())
        record("torso-01", "armDrag", "armMaxOverOutline", arm / reference)
        XCTAssertLessThanOrEqual(arm, reference * Naturalness.armShare, "팔 영역 이동은 몸통 윤곽 최대 이동의 15% 이하")
    }

    // MARK: 기존 체형

    func testExistingBodyItemsAreVisibleWithProtection() async throws {
        let torso = try await photo(Self.torso)
        let skeleton = try torso.skeleton(0)
        let keys: [BodyShapeKey] = [.waist, .overall, .arms, .thighs, .shoulders, .neck]
        for key in keys {
            if key == .thighs, skeleton.point(.leftKnee) == nil, skeleton.point(.rightKnee) == nil {
                print("shape-acceptance torso-01 thighs skipped=무릎 관절 없음")
                continue
            }
            for value in [-1.0, 1.0] {
                var adjustments = BodyShapeAdjustments()
                adjustments[key] = value
                var recipe = EditRecipe()
                recipe.body = adjustments
                if key == .overall {
                    let chest = outlineSides(
                        torso, recipe: recipe, body: 0, level: Layout.chestLevel, item: "overallChest")
                    XCTAssertGreaterThan(chest, 0, "몸 전체 가슴 옆선 점이 적어도 한쪽에 있다")
                }
                let centers = try elementCenters(torso, recipe: recipe, body: 0, key: key)
                XCTAssertFalse(centers.isEmpty, "\(key) 원소가 있다")
                let field = try torso.fieldPatch(recipe)
                let shifts = centers.map { field.vector(at: $0) }.map { hypot($0.dx, $0.dy) * torso.phoneScale }
                let weakest = shifts.min() ?? 0
                record("torso-01", "\(key)\(value > 0 ? "+1" : "-1")", "minCenterPhone", weakest)
                XCTAssertGreaterThanOrEqual(weakest, Visibility.bodyItemPhoneShift, "\(key) \(value) 원소 중심이 폰에서 보인다")
            }
        }
    }

    // MARK: 배경 직선

    func testBackgroundLinesStayStraight() async throws {
        let torso = try await photo(Self.torso)
        let composite = try gridComposite(torso)
        let baseline = PixelGrid(try torso.render(EditRecipe(), input: composite))
        let width = Int(torso.extent.width)
        let unwarped = PixelGrid(try RenderingTestSupport.renderer.makeCGImage(composite))
        var controlMaximum: CGFloat = 0
        for (name, recipe) in try straightnessRecipes(torso) {
            let zone = try zones(torso, recipe: recipe)
            let after = PixelGrid(try torso.render(recipe, input: composite))
            let outsideBand = zone.excluded.map { !$0 }
            let bend = gridBend(before: baseline, after: after, measurable: outsideBand, width: width)
            record("torso-01", "grid-\(name)", "measuredLines", CGFloat(bend.count))
            record("torso-01", "grid-\(name)", "maxLineShift", bend.maximum)
            XCTAssertGreaterThan(bend.count, 0, "\(name) 띠 밖 격자선을 잰다")
            XCTAssertLessThanOrEqual(bend.maximum, Naturalness.lineBend, "\(name) 띠 밖 격자선이 휘지 않는다")
            // 대조: 같은 묶음을 보호 없이(사람 마스크 nil) 그리면 띠 안 배경 격자선이 휜다. 이 검사가 실패할 수 있음을 보인다.
            let control = PixelGrid(try unprotectedWarp(torso, recipe: recipe, input: composite))
            let inBand = gridBend(before: unwarped, after: control, measurable: zone.band, width: width)
            let outside = gridBend(before: unwarped, after: control, measurable: outsideBand, width: width)
            record("torso-01", "grid-\(name)", "unprotectedBandMaxLineShift", inBand.maximum)
            record("torso-01", "grid-\(name)", "unprotectedOutsideMaxLineShift", outside.maximum)
            controlMaximum = max(controlMaximum, inBand.maximum)
        }
        XCTAssertGreaterThan(controlMaximum, Naturalness.lineBend, "보호를 끄면 띠 안 격자선이 0.5px 넘게 휜다(검사가 실패할 수 있다)")
        let lines = try await photo(Self.lines)
        let before = try DisplayScale.grid(try await lines.preview(EditRecipe()))
        for (name, recipe) in try straightnessRecipes(lines) {
            let excluded = try excludedZone(lines, recipe: recipe)
            let after = try DisplayScale.grid(try await lines.preview(recipe))
            let width = Int(lines.extent.width)
            let fraction = ShapeTestSupport.changedFraction(before, after, phoneScale: lines.phoneScale) { point in
                !excluded[Int(point.y) * width + Int(point.x)]
            }
            record("lines-01", "background-\(name)", "changedFraction", CGFloat(fraction))
            XCTAssertLessThanOrEqual(fraction, Naturalness.changedFraction, "\(name) 실루엣 띠 밖 배경은 그대로다")
        }
    }

    // MARK: 남녀·이웃

    func testGenderRulesOnTheCouple() async throws {
        let couple = try await photo(Self.couple)
        try requireCoupleAnalysis(couple)
        let faces = couple.analysis.faces
        let records = [
            PersonRecord(anchor: PersonAnchor(faceBox: faces[0].boundingBox), gender: .male),
            PersonRecord(anchor: PersonAnchor(faceBox: faces[1].boundingBox), gender: .female),
        ]
        let original = try await couple.preview(EditRecipe())
        let originalBytes = try bytes(original)
        var allLayer = EditRecipe()
        allLayer.people.individuals = records
        allLayer.body.sideChest = 1
        let allLayerBytes = try bytes(try await couple.preview(allLayer))
        XCTAssertEqual(allLayerBytes, originalBytes, "전체 층 부유방은 1바이트도 바꾸지 않는다")
        var maleGroup = EditRecipe()
        maleGroup.people.individuals = records
        maleGroup.people.groups[.male] = PortraitLayer(body: [.sideChest: 1])
        let maleGroupBytes = try bytes(try await couple.preview(maleGroup))
        XCTAssertEqual(maleGroupBytes, originalBytes, "남성 그룹 부유방은 1바이트도 바꾸지 않는다")
        let man = try couple.body(matching: 0)
        let woman = try couple.body(matching: 1)
        var femaleGroup = EditRecipe()
        femaleGroup.people.individuals = records
        femaleGroup.people.groups[.female] = PortraitLayer(body: [.sideChest: 1])
        let femaleField = try couple.fieldPatch(femaleGroup)
        // 이 사진은 위팔이 몸통에 붙어 옆선 점이 없을 수 있다. 점이 있는 쪽만 재고 없는 쪽은 로그에 남긴다(이동은 torso-01이 확인).
        let womanSides = outlineSides(
            couple, recipe: femaleGroup, body: woman, level: Layout.sideChestLevel, item: "femaleGroupSideChest")
        XCTAssertEqual(
            couple.context(femaleGroup).bodyTargets[woman].adjustments.sideChest, 1, "여성 그룹 부유방은 여성 몸이 받는다")
        let womanCenters = try elementCenters(couple, recipe: femaleGroup, body: woman, key: .sideChest)
        XCTAssertEqual(womanCenters.count, womanSides)
        var womanShifts: [CGFloat] = []
        for (index, center) in womanCenters.enumerated() {
            let vector = femaleField.vector(at: center)
            let shift = hypot(vector.dx, vector.dy)
            womanShifts.append(shift)
            record("couple-body-01", "femaleGroupSideChest", "womanCenter\(index)Phone", shift * couple.phoneScale)
            XCTAssertGreaterThanOrEqual(
                shift * couple.phoneScale, Visibility.sideChestPhoneShift, "여성 그룹 부유방은 여성에게 보인다")
        }
        try checkArmRegion(
            couple, recipe: femaleGroup, body: woman, field: femaleField, shifts: womanShifts, item: "woman")
        XCTAssertEqual(couple.context(femaleGroup).bodyTargets[man].adjustments.sideChest, 0, "같은 값이 남성 몸에서 0")
        for point in try torsoSides(couple.skeleton(man), level: Layout.sideChestLevel) {
            let vector = femaleField.vector(at: point)
            XCTAssertEqual(hypot(vector.dx, vector.dy), 0, accuracy: 1e-6, "남성 몸통에는 이동이 없다")
        }
        var maleIndividual = EditRecipe()
        maleIndividual.people.individuals = records
        maleIndividual.people.individuals[0].layer.body[.sideChest] = 1
        XCTAssertEqual(
            couple.context(maleIndividual).bodyTargets[man].adjustments.sideChest, 1, "남성 개인 층 부유방은 그 남성 몸이 받는다")
        let maleField = try couple.fieldPatch(maleIndividual)
        _ = outlineSides(
            couple, recipe: maleIndividual, body: man, level: Layout.sideChestLevel, item: "maleIndividualSideChest")
        let manCenters = try elementCenters(couple, recipe: maleIndividual, body: man, key: .sideChest)
        var manShifts: [CGFloat] = []
        for (index, center) in manCenters.enumerated() {
            let vector = maleField.vector(at: center)
            let shift = hypot(vector.dx, vector.dy)
            manShifts.append(shift)
            record("couple-body-01", "maleIndividualSideChest", "manCenter\(index)Phone", shift * couple.phoneScale)
            XCTAssertGreaterThanOrEqual(
                shift * couple.phoneScale, Visibility.sideChestPhoneShift, "남성 개인 층 부유방은 옆선 점이 있는 쪽을 바꾼다")
        }
        try checkArmRegion(couple, recipe: maleIndividual, body: man, field: maleField, shifts: manShifts, item: "man")
        let maleMask = try instanceMask(couple, body: man)
        let after = try DisplayScale.grid(try await couple.preview(femaleGroup))
        let fraction = ShapeTestSupport.changedFraction(
            try DisplayScale.grid(original), after, phoneScale: couple.phoneScale
        ) { maleMask.red(at: $0) >= Layout.maskHalf }
        record("couple-body-01", "femaleGroupSideChest", "maleInstanceChangedFraction", CGFloat(fraction))
        XCTAssertLessThanOrEqual(fraction, Naturalness.changedFraction, "여성 그룹 부유방은 남성 몸 영역을 바꾸지 않는다")
    }

    func testNeighborIsNotDragged() async throws {
        let couple = try await photo(Self.couple)
        try requireCoupleAnalysis(couple)
        let faces = couple.analysis.faces
        var recipe = EditRecipe()
        recipe.people.individuals = [
            PersonRecord(anchor: PersonAnchor(faceBox: faces[0].boundingBox), gender: .male),
            PersonRecord(
                anchor: PersonAnchor(faceBox: faces[1].boundingBox), gender: .female,
                layer: PortraitLayer(body: [.waist: -1])),
        ]
        let woman = try couple.body(matching: 1)
        let field = try couple.fieldPatch(recipe)
        // 허리 원소가 없으면(엉덩이 관절 없음) 옆 사람 검사가 헛돌므로 먼저 실패한다.
        let waist = try elementCenters(couple, recipe: recipe, body: woman, key: .waist)
        XCTAssertFalse(waist.isEmpty, "여성 허리 원소가 있다")
        for (index, point) in waist.enumerated() {
            let vector = field.vector(at: point)
            let shift = hypot(vector.dx, vector.dy) * couple.phoneScale
            record("couple-body-01", "womanWaist", "center\(index)Phone", shift)
            XCTAssertGreaterThanOrEqual(shift, Visibility.bodyItemPhoneShift, "여성 허리가 보인다")
        }
        let maleMask = try instanceMask(couple, body: try couple.body(matching: 0))
        let before = try DisplayScale.grid(try await couple.preview(EditRecipe()))
        let after = try DisplayScale.grid(try await couple.preview(recipe))
        let fraction = ShapeTestSupport.changedFraction(before, after, phoneScale: couple.phoneScale) {
            maleMask.red(at: $0) >= Layout.maskHalf
        }
        record("couple-body-01", "womanWaist", "maleInstanceChangedFraction", CGFloat(fraction))
        XCTAssertLessThanOrEqual(fraction, Naturalness.changedFraction, "여성 허리가 옆 남성을 끌지 않는다")
    }

    // MARK: 시간 기록

    /// 단언 없이 미리보기 한 장의 렌더 시간을 남긴다(묶음마다 흐림 하나가 더 드는 비용 확인용).
    func testPreviewRenderTimeIsRecorded() async throws {
        var recipe = EditRecipe()
        for key in BodyShapeKey.allCases {
            recipe.body[key] = -1
        }
        recipe.portrait.face.doubleChin = 1
        for file in [Self.torso, Self.couple] {
            let photo = try await photo(file)
            for pass in ["cold", "warm"] {
                let start = Date()
                _ = try await photo.preview(recipe)
                record(file, "previewRender", "\(pass)Seconds", CGFloat(Date().timeIntervalSince(start)))
            }
        }
    }

    /// 단언 없이 원본 해상도(48MP) 한 장의 렌더 시간을 남긴다(내보내기에서 묶음마다 드는 마스크 흐림 비용 확인용).
    /// torso-01 미리보기를 Timing.fullExtent로 늘리고 같은 정규화 분석을 그 extent에 쓴다(내보내기와 같은 방식).
    func testFullResolutionRenderTimeIsRecorded() async throws {
        let torso = try await photo(Self.torso)
        let source = torso.extent
        let stretch = CGAffineTransform(
            scaleX: Timing.fullExtent.width / source.width, y: Timing.fullExtent.height / source.height)
        let input = torso.image.transformed(by: stretch)
        var recipe = EditRecipe()
        recipe.body[.waist] = -1
        recipe.portrait.face.doubleChin = 1
        let full = RenderContext(extent: input.extent, recipe: recipe, analysis: torso.analysis, tuning: torso.tuning)
        let groups = ShapeWarpStage().groups(in: full)
        record(
            "torso-01", "fullResolutionRender", "protectedGroups", CGFloat(groups.filter { $0.ownMask != nil }.count))
        let largest = groups.flatMap(\.primitives).map(\.maxDisplacement).max() ?? 0
        record("torso-01", "fullResolutionRender", "largestShiftPixels", largest)
        for pass in ["fieldCold", "fieldWarm"] {
            let start = Date()
            let field = try XCTUnwrap(
                DisplacementWarp.shared.field(
                    groups: groups, extent: input.extent, limit: torso.tuning.shapeDisplacementLimit,
                    tuning: torso.tuning))
            // 보호 가중치를 곱한 지도만 그린다(값은 8비트로 잘려도 시간만 본다).
            let image = try RenderingTestSupport.renderer.makeCGImage(field)
            XCTAssertNotNil(image.dataProvider?.data)
            record("torso-01", "fullResolutionRender", "\(pass)Seconds", CGFloat(Date().timeIntervalSince(start)))
        }
        let neutral = EditRecipe()
        for (name, edit) in [("neutral", neutral), ("cold", recipe), ("warm", recipe)] {
            let context = RenderContext(
                extent: input.extent, recipe: edit, analysis: torso.analysis, tuning: torso.tuning)
            let start = Date()
            let output = try RenderPipeline.standard.render(input, context: context)
            let image = try RenderingTestSupport.renderer.makeCGImage(output)
            // createCGImage는 픽셀을 늦게 그릴 수 있어 바이트를 읽어 렌더를 끝낸다.
            let rendered = try XCTUnwrap(image.dataProvider?.data) as Data
            XCTAssertFalse(rendered.isEmpty)
            record("torso-01", "fullResolutionRender", "\(name)Seconds", CGFloat(Date().timeIntervalSince(start)))
        }
    }

    /// 원본 해상도 시간 기록의 크기.
    private enum Timing {
        /// 48MP 내보내기 크기(가로 × 세로 픽셀).
        static let fullExtent = CGSize(width: 8000, height: 6000)
    }

    // MARK: 도우미

    private func bytes(_ image: CGImage) throws -> [UInt8] {
        Array(try XCTUnwrap(image.dataProvider?.data) as Data)
    }

    /// 같은 쪽 어깨~엉덩이 level 높이의 두 점(BodyShapeRig.torsoSides와 같은 자리).
    private func torsoSides(_ skeleton: BodySkeleton, level: CGFloat) throws -> [CGPoint] {
        let pairs = [(BodyJoint.leftShoulder, BodyJoint.leftHip), (.rightShoulder, .rightHip)]
        return try pairs.map { shoulder, hip in
            let top = try XCTUnwrap(skeleton.point(shoulder), "\(shoulder)")
            let bottom = try XCTUnwrap(skeleton.point(hip), "\(hip)")
            return BodySkeleton.lerp(top, bottom, level)
        }
    }

    /// 커플 사진 분석이 얼굴 2·몸 2·짝 2가 아니면 남녀·이웃 검사를 건너뛴다.
    /// 분석 실패 자체는 testFixturesAreAnalyzable이 실패로 알린다.
    private func requireCoupleAnalysis(_ couple: RealBodyPhoto) throws {
        let analysis = couple.analysis
        guard analysis.faces.count == 2, analysis.bodies.count == 2, analysis.bodyFaceMatches.count == 2 else {
            let summary = "얼굴 \(analysis.faces.count)·몸 \(analysis.bodies.count)·짝 \(analysis.bodyFaceMatches.count)"
            print("shape-acceptance couple-body-01 rules skipped=\(summary)")
            throw XCTSkip("couple-body-01 분석이 남녀 두 사람이 아니라(\(summary)) 남녀·이웃 규칙을 잴 수 없다")
        }
    }

    /// 그 몸에 렌더가 key 항목으로 만드는 push 원소 중심.
    /// ShapeWarpStage와 같은 BodyShapeRig.groups 호출(그 몸의 해석 값·같은 옆선)이고 렌더 묶음에 같은 원소가 든 것도 확인한다.
    private func elementCenters(_ photo: RealBodyPhoto, recipe: EditRecipe, body: Int, key: BodyShapeKey) throws
        -> [CGPoint]
    {
        let target = photo.context(recipe).bodyTargets[body]
        var only = BodyShapeAdjustments()
        only[key] = target.adjustments[key]
        let parts = BodyShapeRig.groups(
            body: target.body, adjustments: only, extent: photo.extent, tuning: photo.tuning, includesLegBand: false,
            outline: target.outline)
        let centers = (parts.torso + parts.limbs).compactMap(Self.pushCenter)
        let rendered = photo.groups(recipe).flatMap(\.primitives).compactMap(Self.pushCenter)
        for center in centers {
            XCTAssertTrue(rendered.contains(center), "\(key) 원소가 렌더 묶음에 있다")
        }
        return centers
    }

    private static func pushCenter(_ primitive: ShapePrimitive) -> CGPoint? {
        guard case .push(let center, _, _) = primitive else { return nil }
        return center
    }

    /// 그 몸의 level 높이 옆선 점 수(0…2). 점이 없는 쪽(팔이 붙음)을 로그에 남긴다.
    /// 옆선이 없으면(사람 마스크 없음) 관절선 점을 쓰므로 2로 보고 그 사실을 남긴다.
    private func outlineSides(_ photo: RealBodyPhoto, recipe: EditRecipe, body: Int, level: CGFloat, item: String)
        -> Int
    {
        guard let outline = photo.context(recipe).bodyTargets[body].outline else {
            print("shape-acceptance \(photo.file) \(item) outline=없음(관절선 점)")
            return 2
        }
        var found = 0
        for side in [-1, 1] {
            if outline.points[OutlineKey(level: Double(level), side: side)] == nil {
                print("shape-acceptance \(photo.file) \(item) body\(body)Side\(side) skipped=옆선 점 없음(팔이 붙음)")
            } else {
                found += 1
            }
        }
        return found
    }

    /// 팔 영역(팔 캡슐 반지름 안 × 그 사람 마스크 ≥ 0.5)의 최대 |이동|(미리보기 px).
    /// 팔 캡슐은 렌더가 몸통 묶음에 거는 보호 캡슐(BodyShapeRig.groups의 guards) 그대로이고 반지름은 팔 반폭이다(armGuardScale 1).
    private func armMaximum(_ photo: RealBodyPhoto, recipe: EditRecipe, body: Int, field: FloatPatch) throws -> CGFloat
    {
        let target = photo.context(recipe).bodyTargets[body]
        let guards = BodyShapeRig.groups(
            body: target.body, adjustments: target.adjustments, extent: photo.extent, tuning: photo.tuning,
            includesLegBand: false, outline: target.outline
        ).guards
        let capsules = guards.map { shapeGuard -> (CGPoint, CGPoint, CGFloat) in
            guard case .capsule(let start, let end, let radius, _) = shapeGuard else { return (.zero, .zero, 0) }
            return (start, end, radius)
        }
        XCTAssertGreaterThanOrEqual(capsules.count, 2, "두 위팔 캡슐이 있다")
        let own = try XCTUnwrap(photo.context(recipe).personMask(forBody: body).own, "몸 \(body)의 사람 마스크")
        let mask = FloatPatch(photo.placed(own), in: photo.extent)
        var largest: CGFloat = 0
        var counted = 0
        for point in field.pixelCenters {
            guard mask.red(at: point) >= Layout.maskHalf,
                capsules.contains(where: { ShapeTestSupport.distance(from: point, toSegment: $0.0, $0.1) <= $0.2 })
            else { continue }
            counted += 1
            let vector = field.vector(at: point)
            largest = max(largest, hypot(vector.dx, vector.dy))
        }
        XCTAssertGreaterThan(counted, 0, "팔 영역 픽셀이 있다")
        return largest
    }

    /// 팔 영역 최대 이동이 움직인 부유방 이동 중 가장 작은 것의 15% 이하인지(torso-01과 같은 armMaximum).
    /// 움직인 쪽이 없으면 기준이 없어 로그만 남긴다.
    private func checkArmRegion(
        _ photo: RealBodyPhoto, recipe: EditRecipe, body: Int, field: FloatPatch, shifts: [CGFloat], item: String
    ) throws {
        let arm = try armMaximum(photo, recipe: recipe, body: body, field: field)
        guard let reference = shifts.min(), reference > 0 else {
            print("shape-acceptance \(photo.file) \(item)ArmRegion skipped=움직인 부유방 쪽 없음")
            return
        }
        record(photo.file, "\(item)ArmRegion", "armMaxOverSide", arm / reference)
        XCTAssertLessThanOrEqual(arm, reference * Naturalness.armShare, "\(item) 팔 영역 이동은 옆가슴 이동의 15% 이하")
    }

    /// 그 몸의 인스턴스 마스크(extent). 인스턴스가 없는 기계는 이 검사만 건너뛴다.
    private func instanceMask(_ photo: RealBodyPhoto, body: Int) throws -> FloatPatch {
        guard !photo.analysis.personInstances.isEmpty else {
            print("shape-acceptance \(photo.file) instance skipped=personInstances 없음")
            throw XCTSkip("\(photo.file): 사람 인스턴스 마스크가 없는 기계라 옆 사람 영역 검사를 건너뛴다")
        }
        let index = try XCTUnwrap(photo.analysis.bodyInstances[body], "몸 \(body)의 인스턴스")
        return FloatPatch(photo.placed(photo.analysis.personInstances[index]), in: photo.extent)
    }

    /// 직선 검사 레시피 셋: 체형 전 항목 −1, 전 항목 +1, 이중턱 1.
    /// 부유방은 전체 층에서 무시되므로 그 사람의 개인 층에 둔다(줄이기만 있어 두 레시피 모두 1).
    private func straightnessRecipes(_ photo: RealBodyPhoto) throws -> [(String, EditRecipe)] {
        let face = try XCTUnwrap(photo.analysis.faces.first)
        let person = PersonRecord(
            anchor: PersonAnchor(faceBox: face.boundingBox), layer: PortraitLayer(body: [.sideChest: 1]))
        var slim = EditRecipe()
        var wide = EditRecipe()
        for key in BodyShapeKey.allCases where key != .sideChest {
            slim.body[key] = AdjustmentRange.clamped(-1, to: AdjustmentRange.bodyShape(key))
            wide.body[key] = 1
        }
        slim.people.individuals = [person]
        wide.people.individuals = [person]
        var chin = EditRecipe()
        chin.portrait.face.doubleChin = 1
        return [("slim", slim), ("wide", wide), ("doubleChin", chin)]
    }

    /// 실루엣(전체 인물 마스크 ≥ 0.5)에서 (묶음 최대 이동 × 4 + 4px) 안의 픽셀. 행 우선, 원점 왼쪽 아래 행부터다.
    private func excludedZone(_ photo: RealBodyPhoto, recipe: EditRecipe) throws -> [Bool] {
        try zones(photo, recipe: recipe).excluded
    }

    /// excluded는 실루엣과 띠(실루엣에서 띠 폭 안), band는 그중 실루엣 밖(배경 보호 띠)이다.
    private func zones(_ photo: RealBodyPhoto, recipe: EditRecipe) throws -> (excluded: [Bool], band: [Bool]) {
        let mask = try photo.personMaskPatch()
        let width = Int(photo.extent.width)
        let height = Int(photo.extent.height)
        let inside = mask.pixelCenters.map { mask.red(at: $0) >= Layout.maskHalf }
        let distances = ShapeTestSupport.distanceToNearest(inside, width: width, height: height)
        let reach = Double(photo.largestShift(recipe) * Layout.bandShiftScale + Layout.bandMargin)
        record(photo.file, "band", "reachPixels", CGFloat(reach))
        let excluded = distances.map { $0 <= reach }
        let band = zip(excluded, inside).map { $0 && !$1 }
        return (excluded, band)
    }

    /// 렌더와 같은 묶음에서 사람 마스크·이웃·팔 보호를 모두 뺀 워프만 입력에 건다(보호 없는 대조).
    private func unprotectedWarp(_ photo: RealBodyPhoto, recipe: EditRecipe, input: CIImage) throws -> CGImage {
        let bare = photo.groups(recipe).map { ShapeGroup(primitives: $0.primitives) }
        let warped = try DisplacementWarp.shared.apply(
            groups: bare, to: input, extent: photo.extent, limit: photo.tuning.shapeDisplacementLimit,
            tuning: photo.tuning)
        return try RenderingTestSupport.renderer.makeCGImage(warped)
    }

    /// 사람을 흰 바탕 8px 간격 검은 격자 위에 전체 인물 마스크로 얹고 비트맵으로 굳힌다(스펙 7.2).
    private func gridComposite(_ photo: RealBodyPhoto) throws -> CIImage {
        let width = Int(photo.extent.width)
        let height = Int(photo.extent.height)
        var pixels = [UInt8](repeating: 255, count: width * height)
        // CGImage는 맨 위 행부터라 Core Image 좌표 y로 바꿔 선 자리를 정한다.
        for row in 0..<height {
            let y = height - 1 - row
            for column in 0..<width {
                let onLine =
                    column % Layout.gridSpacing < Layout.gridLineWidth || y % Layout.gridSpacing < Layout.gridLineWidth
                if onLine {
                    pixels[row * width + column] = 0
                }
            }
        }
        let provider = try XCTUnwrap(CGDataProvider(data: Data(pixels) as CFData))
        let grid = try XCTUnwrap(
            CGImage(
                width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 8, bytesPerRow: width,
                space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGBitmapInfo(rawValue: 0), provider: provider,
                decode: nil, shouldInterpolate: false, intent: .defaultIntent))
        let background = CIImage(cgImage: grid)
        let person = photo.placed(try XCTUnwrap(photo.analysis.personMask))
        let composite = MaskBuilder.blend(photo.image, over: background, mask: person).cropped(to: photo.extent)
        return CIImage(cgImage: try RenderingTestSupport.renderer.makeCGImage(composite))
    }

    /// 잴 수 있는 픽셀(measurable)만 든 창마다 격자선 위치(검은 픽셀 가중 중심)를 재 가장 큰 차이를 돌려준다.
    /// 세로선은 간격 안 가운데 행들에서, 가로선은 가운데 열들에서 잰다.
    /// 첫 선과 마지막 선도 재고, 사진 가장자리에서는 창을 사진 안으로 자른다.
    private func gridBend(before: PixelGrid, after: PixelGrid, measurable: [Bool], width: Int) -> (
        count: Int, maximum: CGFloat
    ) {
        let height = before.height
        let spacing = Layout.gridSpacing
        var count = 0
        var maximum: CGFloat = 0
        func darkness(_ grid: PixelGrid, _ x: Int, _ y: Int) -> CGFloat {
            CGFloat(255 - Int(grid.rgba(CGPoint(x: x, y: y))[1]))
        }
        for vertical in [true, false] {
            let across = vertical ? width : height
            let along = vertical ? height : width
            for line in stride(from: 0, to: across, by: spacing) {
                let span = max(line - Layout.gridWindowLead, 0)..<min(line - Layout.gridWindowLead + spacing, across)
                for base in stride(from: 0, to: along, by: spacing) {
                    for offset in Layout.gridProbeOffsets {
                        let probe = base + offset
                        guard probe < along else { continue }
                        let window = span.map { vertical ? ($0, probe) : (probe, $0) }
                        guard window.allSatisfy({ measurable[$0.1 * width + $0.0] }) else { continue }
                        let first = window.map { darkness(before, $0.0, $0.1) }
                        let second = window.map { darkness(after, $0.0, $0.1) }
                        let firstTotal = first.reduce(0, +)
                        let secondTotal = second.reduce(0, +)
                        guard firstTotal > 0, secondTotal > 0 else { continue }
                        let positions = span.map { CGFloat($0) }
                        let firstCenter = zip(first, positions).map { $0 * $1 }.reduce(0, +) / firstTotal
                        let secondCenter = zip(second, positions).map { $0 * $1 }.reduce(0, +) / secondTotal
                        count += 1
                        maximum = max(maximum, abs(secondCenter - firstCenter))
                    }
                }
            }
        }
        return (count, maximum)
    }
}
