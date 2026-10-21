import XCTest

@testable import MellowShared

final class OneTouchBundleTests: XCTestCase {
    /// Evoto 실측에 맞춘 표 상한(스펙 G5 판정 3).
    enum EvotoCeiling {
        /// Evoto는 중간 대역을 거의 그대로 둔다.
        static let smoothing = 0.25
        static let toneEvening = 0.15
        /// 몸 피부 ΔY ≤ +1.5/255.
        static let bodyBrightness = 0.1
    }

    func testTablesScaleLinearlyAndNeverTouchShapeOrLipColour() {
        let female = OneTouchBundle.layer(for: .female, strength: 1)
        XCTAssertEqual(female.skinSmoothing, OneTouchBundle.Table.female.smoothing)
        XCTAssertEqual(female.skinRefinement[.darkCircles], OneTouchBundle.Table.female.darkCircles)
        XCTAssertEqual(female.features[.lipVitality], OneTouchBundle.Table.female.lipVitality)
        XCTAssertEqual(
            female.makeup[.blush],
            MakeupTint(
                colorID: OneTouchBundle.Table.blushColorID, intensity: OneTouchBundle.Table.female.blushIntensity))
        XCTAssertEqual(female.makeup[.lip], MakeupTint(colorID: nil, intensity: 0), "립은 늘 없음으로 덮어쓴다")
        XCTAssertEqual(female.autoBlemish, true)
        XCTAssertEqual(female.oneTouch, 1)
        XCTAssertTrue(female.face.isEmpty, "얼굴형은 묶음 밖")
        XCTAssertNil(female.makeup[.eyeshadow])
        XCTAssertNil(female.makeupLookID)
        let half = OneTouchBundle.layer(for: .female, strength: 0.5)
        XCTAssertEqual(half.skinSmoothing ?? 0, OneTouchBundle.Table.female.smoothing * 0.5, accuracy: 1e-12)
        XCTAssertEqual(half.skinRefinement[.redness] ?? 0, OneTouchBundle.Table.female.redness * 0.5, accuracy: 1e-12)
        XCTAssertEqual(
            half.makeup[.blush]?.intensity ?? 0, OneTouchBundle.Table.female.blushIntensity * 0.5, accuracy: 1e-12)
        XCTAssertEqual(half.oneTouch, 0.5)
        let male = OneTouchBundle.layer(for: .male, strength: 1)
        XCTAssertEqual(male.makeup[.blush], MakeupTint(colorID: nil, intensity: 0), "남성은 블러셔 없음으로 덮어쓴다")
        XCTAssertEqual(male.makeup[.lip], MakeupTint(colorID: nil, intensity: 0))
        XCTAssertEqual(male.features[.lipVitality], 0)
        XCTAssertLessThan(OneTouchBundle.Table.male.smoothing, OneTouchBundle.Table.female.smoothing, "남성은 덜 매끄럽게")
        XCTAssertLessThan(
            OneTouchBundle.Table.male.toneEvening, OneTouchBundle.Table.common.toneEvening, "남성은 얼룩 고르기 최소")
        XCTAssertGreaterThanOrEqual(OneTouchBundle.Table.male.shine, OneTouchBundle.Table.female.shine)
        let common = OneTouchBundle.layer(for: nil, strength: 1)
        XCTAssertEqual(common.skinSmoothing, OneTouchBundle.Table.common.smoothing)
        XCTAssertEqual(common.makeup[.blush], MakeupTint(colorID: nil, intensity: 0))
        XCTAssertEqual(OneTouchBundle.layer(for: .male, strength: 0), PortraitLayer(), "강도 0은 빈 층")
        XCTAssertEqual(OneTouchBundle.layer(for: .male, strength: 3), male, "강도는 상한으로 자른다")
        XCTAssertEqual(OneTouchBundle.clampedStrength(-1), 0)
        XCTAssertEqual(OneTouchBundle.defaultStrength, 0.6, "Evoto 크기의 기본 강도")
        XCTAssertFalse(OneTouchBundle.writesBodyTone, "톤 표 값이 0이면 톤을 쓰지 않는다")
        XCTAssertEqual(
            OneTouchBundle.bodySkin(strength: 0.5).brightness, OneTouchBundle.Table.bodyBrightness * 0.5,
            accuracy: 1e-12)
        XCTAssertEqual(OneTouchBundle.bodySkin(strength: 0), BodySkinAdjustments())
        XCTAssertEqual(
            OneTouchBundle.keys,
            PortraitKey.skin.union(PortraitKey.features).union([.makeupPart(.blush), .makeupPart(.lip)]))
        XCTAssertTrue(Set(female.overriddenKeys).isSubset(of: OneTouchBundle.keys))
        for values in [OneTouchBundle.Table.common, OneTouchBundle.Table.female, OneTouchBundle.Table.male] {
            XCTAssertLessThanOrEqual(values.smoothing, 0.5, "끝까지 올려도 중간 대역을 절반 넘게 줄이지 않는다")
            XCTAssertLessThanOrEqual(values.redness, 0, "혈색은 더하지 않는다")
            XCTAssertLessThanOrEqual(values.smoothing, EvotoCeiling.smoothing, "Evoto는 중간 대역을 거의 그대로 둔다(스펙 G5 판정 3)")
            XCTAssertLessThanOrEqual(values.toneEvening, EvotoCeiling.toneEvening)
        }
        XCTAssertLessThanOrEqual(OneTouchBundle.Table.bodyBrightness, EvotoCeiling.bodyBrightness, "몸 피부 ΔY ≤ +1.5/255")
    }

    func testOneTouchMarkRoundTripsAndIsNotARenderValue() throws {
        var recipe = EditRecipe()
        recipe.portrait.oneTouch = 0.6
        recipe.people.groups[.female] = PortraitLayer(oneTouch: 0.6)
        XCTAssertFalse(recipe.portrait.dependsOnFaces, "표시만으로는 얼굴이 필요 없다")
        XCTAssertFalse(recipe.people.hasEffect)
        XCTAssertFalse(recipe.people.groups[.female]!.isEmpty, "표시가 있는 층은 비어 있지 않다")
        XCTAssertTrue(recipe.people.groups[.female]!.overriddenKeys.isEmpty, "표시는 키가 아니다")
        let data = try JSONEncoder().encode(recipe)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual((json["portrait"] as? [String: Any])?["oneTouch"] as? Double, 0.6)
        let female = try XCTUnwrap(
            ((json["people"] as? [String: Any])?["groups"] as? [String: Any])?["female"] as? [String: Any])
        XCTAssertEqual(Set(female.keys), ["oneTouch"])
        XCTAssertEqual(try JSONDecoder().decode(EditRecipe.self, from: data), recipe)
        let legacy = #"{"schemaVersion":2,"portrait":{"skin":{"smoothing":0.4}}}"#
        XCTAssertNil(try JSONDecoder().decode(EditRecipe.self, from: Data(legacy.utf8)).portrait.oneTouch)
        let plain = try XCTUnwrap(String(data: JSONEncoder().encode(EditRecipe()), encoding: .utf8))
        XCTAssertFalse(plain.contains("oneTouch"), "없으면 쓰지 않는다")
        recipe.portrait.oneTouch = .nan
        XCTAssertFalse(recipe.allValuesFinite)
    }
}
