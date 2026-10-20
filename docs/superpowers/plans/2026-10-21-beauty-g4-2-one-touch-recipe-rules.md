# 인물 보정 G4-2 원터치 레시피·편집 규칙·실사진 수용 구현 계획

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 성별 표(`OneTouchBundle`)와 층별 `oneTouch` 표시 키를 MellowShared에 더하고, `EditDocument.applyOneTouch(strength:in:)`가 대상 층(전체 = 전체 층 + 남성·여성 그룹 층 + 몸 피부, 그룹, 사람)에 표 × 강도를 쓰게 한다. 묶인 키를 손으로 바꾸면 그 층의 표시가 지워지고, 프리셋·동기화·자동이 표시를 다루는 규칙을 넣는다. 실사진(데모 + 커플 생성 사진)에서 원터치의 하한(보임)·상한(자연)을 테스트로 고정한다. 화면은 G4-3.

**Architecture:** 표와 강도 곱은 순수 값 계산이라 MellowShared `OneTouchBundle`에 둔다(다른 플랫폼이 같은 표를 쓴다). 쓰기는 H2의 `set(_:in:)`·`merged`와 같은 `EditDocument` 안이고 렌더는 `oneTouch` 키를 읽지 않는다(레시피가 곧 렌더). 수용 테스트는 G4-1의 `DisplayScale`·`RealPortrait`와 H3 Task 1의 `PeopleFixtures`를 쓴다.

**Tech Stack:** Swift 5.9 tools / Swift 5 언어 모드, Foundation Codable(직접 구현), Core Image·Vision(테스트), XCTest.

**Spec:** `docs/superpowers/specs/2026-10-21-beauty-g4-one-touch-design.md` (1.2·1.4의 원터치 행, 3절 전부, 7.1의 G4-2 행). 선행: G4-1, H3 Task 1(생성 사진), H1, H2 전부 머지.

## 사람이 확인할 것

- **순서.** Task 1 표·표시 키·스키마 → 2 편집 규칙(쓰기·표시 해제·프리셋·동기화·자동) → 3 실사진 원터치 수용(데모·커플). 3개 Task, Task마다 Opus 구현 → 리뷰 → 수정, 끝에 전체 리뷰.
- **외부 효과가 있는 단계.** 없음.
- **스펙이 정하지 않아 이 계획이 정한 것.**

| 결정 | 이유 | 바꾸면 비용 |
|---|---|---|
| 표시 해제는 `EditDocument.commit`에서 이전 레시피와 비교해 "묶인 키가 실제로 바뀐 층"의 표시만 지운다. `applyOneTouch` 자신은 해제를 건너뛰고 표시를 새 강도로 둔다 | 규칙이 한 곳이고, 같은 값을 다시 쓰는 변경은 표시를 남긴다(`lookID`와 같은 느낌) | 작음 |
| 전체 대상에서 그룹 층에 표를 쓸 때 그룹 층의 묶음 밖 키(얼굴형 등)는 보존하고 개인 층은 건드리지 않는다 | H 규칙("개인이 그룹을 이김")과 사용자가 따로 만진 값을 지키려고 | 작음 |
| 강도는 `0…OneTouchBundle.maximumStrength(1)`로 자르고 `applyOneTouch(strength: 0)`은 "묶음 제거"다(전체 층은 기본값·몸 피부 0, 그룹·개인은 묶인 키 상속·표시 nil) | 슬라이더를 0으로 내리면 되돌아가야 한다 | 작음 |
| `applyAuto(_:oneTouchStrength:)`의 `oneTouchStrength`는 선택 인자(nil = 지금 동작)다. 질문 2의 답과 무관하게 규칙은 넣고 호출 여부만 G4-3가 정한다 | 두 선택지를 한 코드로 받친다 | 작음 |
| 커플 사진 수용 테스트는 `couple-01.jpg`의 Vision 얼굴 수가 라벨과 같을 때만 단언하고(H3 `PeopleFixturesTests`가 보증), 다르면 실패로 둔다 | 사진의 쓸모 조건 | 작음 |

- **범위 밖(다른 계획).** 원터치 버튼·강도 슬라이더·세부 조정 접기·자동 버튼 연동(G4-3), 칩 화면(H3 Task 2~3).
- **위험.** 데모·커플 사진 두 장 기준의 표 값이다. 상한에 걸리면 표 값을 내린다(스펙 1.4 규칙). 성별 표의 취향은 사용자 조치.
- **사용자 조치.** 없음(기기 확인은 G4-3 뒤).

---

## 에이전트 참조

## Global Constraints

G4-1 계획의 Global Constraints를 그대로 따른다(브랜치 `beauty-g4`·`DEVELOPER_DIR`·모듈 표 불변·lint·커밋 서명·`git add` 경로 제한·**로컬 iOS 시뮬레이터 금지**). 이 계획에서 다른 것:

- 시작 조건: H2 머지(`PortraitLayer`·`PortraitScope`·`set(_:in:)`·`merged(…clearsIndividuals:)`·`FaceTarget` 존재)와 H3 Task 1 머지(`PeopleFixtures`·`couple-01.jpg`). 기준 테스트 수는 **시작 전에 실측해 이 줄에 적는다**. 이 계획이 더하는 수: **Shared +3, Editing +5, Rendering +4**(Task 1 Shared +3, Task 2 Editing +5, Task 3 Rendering +4). 앱 0.
- 레시피 `schemaVersion` 2 유지, 키 추가만(`portrait.oneTouch`, `$defs/portraitLayer.oneTouch`). 렌더 코드는 바꾸지 않는다(`oneTouch`를 읽지 않음).
- 표 값은 `OneTouchBundle.Table`의 `static let`에만 있다(스펙 3.2). 테스트는 표 상수를 참조하고 숫자를 다시 적지 않는다(값이 바뀌어도 테스트가 따라온다). 단 "남성은 메이크업 없음"·"변형 없음" 같은 구조 단언은 값으로 고정한다.
- MellowRendering 테스트 타깃은 MellowEditing을 import할 수 없다. 수용 테스트의 레시피는 `OneTouchBundle.layer(for:strength:)`와 `PortraitLayer.applied(to:makeup:)`로 직접 만든다.

## Review Focus

1. **원터치를 적용한 뒤 "전체" 칩에서 다크서클 슬라이더를 움직인다.** 전체 층 표시만 지워지고 그룹 표시는 남아야 한다. → Task 2 `testManualChangeOfABundledKeyClearsOnlyThatLayerMark`.
2. **그룹에 얼굴형 값이 있는 상태에서 전체 원터치.** 그룹의 얼굴형 값은 그대로이고 묶인 키만 바뀌어야 한다. → Task 2 `testOneTouchWritesTablesPerLayerAndStrengthScales`.
3. **색감만 동기화.** 받는 사진의 표시는 그대로. 피부만 동기화하면 받는 사진의 전체·그룹 표시가 지워진다. 피부·눈입·메이크업을 모두 동기화하면 원본 표시가 복사된다. → Task 2 `testPresetsCarryMarksAndSyncCopiesThemOnlyWithAllThreeCategories`.
4. **남성으로 지정한 사람에게 원터치 1.** 입술 색차가 바뀌지 않고 블러셔 띠가 그대로여야 한다. → Task 3 `testOneTouchOnTheCouplePhotoTreatsMaleAndFemaleDifferently`.
5. **원터치 1의 질감.** 피부 fine 분산 비 ≥ 0.85, 기본 0.6에서 ≥ 0.9. → Task 3 `testOneTouchStaysNaturalAtDefaultAndMaximum`.
6. **강도 0.** 레시피가 기본으로 돌아간다(표시 포함). → Task 2 `testOneTouchWritesTablesPerLayerAndStrengthScales`.

## 인터페이스 요약 (모든 Task가 공유하는 이름)

```swift
// MellowShared (Task 1)
public enum OneTouchBundle {
    public static let maximumStrength = 1.0
    public static let keys: Set<PortraitKey>                         // skin 9 + features 3 + makeupPart(.blush) + makeupPart(.lip)
    public struct Values: Equatable, Sendable { smoothing, darkCircles, nasolabial, marionette, glabella, toneEvening, redness, shine,
        eyeBrighten, teethWhiten, lipVitality, blushIntensity: Double; blushColorID: String? }
    public enum Table { static let common, female, male: Values; static let blushColorID = "blush-peach"; static let bodyBrightness = 0.2; static let bodyTone = 0.0 }
    public static func values(for gender: Gender?) -> Values
    public static func clampedStrength(_ strength: Double) -> Double
    public static func layer(for gender: Gender?, strength: Double) -> PortraitLayer   // oneTouch = 강도, autoBlemish = 강도 > 0, 블러셔·립 덮어씀, face·features 외 키 없음
    public static func bodySkin(strength: Double) -> BodySkinAdjustments
}
PortraitAdjustments.oneTouch: Double?          // 전체 층 표시
PortraitLayer.oneTouch: Double?                // 그룹·개인 층 표시, isEmpty에 포함, numericValues에 포함

// MellowEditing (Task 2)
EditingPolicy.oneTouchDefaultStrength = 0.6
EditDocument.applyOneTouch(strength:in: PortraitScope = .all) -> Rejection?
EditDocument.applyOneTouch(strength:forPersonAt: PersonAnchor) -> Rejection?
EditDocument.applyAuto(_:oneTouchStrength: Double? = nil) -> Bool
SyncCategory.oneTouchCategories: Set<SyncCategory> = [.skin, .features, .makeup]
// 내부: EditDocument.clearStaleOneTouchMarks(previous:in:), commit(_:clearsStaleMarks:)

// 테스트 지원 (Task 3)
DisplayScale.changedFraction(_:_:weight:minimumDelta:)           // 가중치 > 0.5인 픽셀만 센다
RealPortrait.outsideFaceChangedFraction(before:after:) -> Double   // G4-1 Task 1 테스트의 계산을 옮김
RealPortrait.browMask() throws -> PixelGrid
RealPeople { static func couple() throws -> RealPeople; image, extent, faces, labels: [Gender] }
```

---

### Task 1: 표와 표시 키 — OneTouchBundle, oneTouch, 스키마

**Files:**
- Create: `apple/Sources/MellowShared/API/OneTouchBundle.swift`
- Modify: `apple/Sources/MellowShared/API/Adjustments.swift`(`PortraitAdjustments.oneTouch`), `PeopleAdjustments.swift`(`PortraitLayer.oneTouch`)
- Modify: `shared/recipe-schema/edit-recipe.v2.schema.json`, `shared/recipe-schema/README.md`
- Create: `apple/Tests/MellowSharedTests/OneTouchBundleTests.swift`
- Test: `apple/Tests/MellowSharedTests/EditRecipeCodingTests.swift`, `RecipeSchemaTests.swift`

- [ ] **Step 1: 실패하는 테스트 작성**

`apple/Tests/MellowSharedTests/OneTouchBundleTests.swift`:

```swift
import XCTest

@testable import MellowShared

final class OneTouchBundleTests: XCTestCase {
    func testTablesScaleLinearlyAndNeverTouchShapeOrLipColour() {
        let female = OneTouchBundle.layer(for: .female, strength: 1)
        XCTAssertEqual(female.skinSmoothing, OneTouchBundle.Table.female.smoothing)
        XCTAssertEqual(female.skinRefinement[.darkCircles], OneTouchBundle.Table.female.darkCircles)
        XCTAssertEqual(female.features[.lipVitality], OneTouchBundle.Table.female.lipVitality)
        XCTAssertEqual(
            female.makeup[.blush],
            MakeupTint(colorID: OneTouchBundle.Table.blushColorID, intensity: OneTouchBundle.Table.female.blushIntensity))
        XCTAssertEqual(female.makeup[.lip], MakeupTint(colorID: nil, intensity: 0), "립은 늘 없음으로 덮어쓴다")
        XCTAssertEqual(female.autoBlemish, true)
        XCTAssertEqual(female.oneTouch, 1)
        XCTAssertTrue(female.face.isEmpty, "얼굴형은 묶음 밖")
        XCTAssertNil(female.makeup[.eyeshadow])
        XCTAssertNil(female.makeupLookID)
        let half = OneTouchBundle.layer(for: .female, strength: 0.5)
        XCTAssertEqual(half.skinSmoothing ?? 0, OneTouchBundle.Table.female.smoothing * 0.5, accuracy: 1e-12)
        XCTAssertEqual(half.skinRefinement[.redness] ?? 0, OneTouchBundle.Table.female.redness * 0.5, accuracy: 1e-12)
        XCTAssertEqual(half.makeup[.blush]?.intensity ?? 0, OneTouchBundle.Table.female.blushIntensity * 0.5, accuracy: 1e-12)
        XCTAssertEqual(half.oneTouch, 0.5)
        let male = OneTouchBundle.layer(for: .male, strength: 1)
        XCTAssertEqual(male.makeup[.blush], MakeupTint(colorID: nil, intensity: 0), "남성은 블러셔 없음으로 덮어쓴다")
        XCTAssertEqual(male.makeup[.lip], MakeupTint(colorID: nil, intensity: 0))
        XCTAssertEqual(male.features[.lipVitality], 0)
        XCTAssertLessThan(OneTouchBundle.Table.male.smoothing, OneTouchBundle.Table.female.smoothing, "남성은 덜 매끄럽게")
        XCTAssertLessThan(OneTouchBundle.Table.male.toneEvening, OneTouchBundle.Table.common.toneEvening, "남성은 얼룩 고르기 최소")
        XCTAssertGreaterThanOrEqual(OneTouchBundle.Table.male.shine, OneTouchBundle.Table.female.shine)
        let common = OneTouchBundle.layer(for: nil, strength: 1)
        XCTAssertEqual(common.skinSmoothing, OneTouchBundle.Table.common.smoothing)
        XCTAssertEqual(common.makeup[.blush], MakeupTint(colorID: nil, intensity: 0))
        XCTAssertEqual(OneTouchBundle.layer(for: .male, strength: 0), PortraitLayer(), "강도 0은 빈 층")
        XCTAssertEqual(OneTouchBundle.layer(for: .male, strength: 3), male, "강도는 상한으로 자른다")
        XCTAssertEqual(OneTouchBundle.clampedStrength(-1), 0)
        XCTAssertEqual(OneTouchBundle.bodySkin(strength: 0.5).brightness, OneTouchBundle.Table.bodyBrightness * 0.5, accuracy: 1e-12)
        XCTAssertEqual(OneTouchBundle.bodySkin(strength: 0), BodySkinAdjustments())
        XCTAssertEqual(OneTouchBundle.keys, PortraitKey.skin.union(PortraitKey.features).union([.makeupPart(.blush), .makeupPart(.lip)]))
        XCTAssertTrue(Set(female.overriddenKeys).isSubset(of: OneTouchBundle.keys))
        for values in [OneTouchBundle.Table.common, OneTouchBundle.Table.female, OneTouchBundle.Table.male] {
            XCTAssertLessThanOrEqual(values.smoothing, 0.5, "끝까지 올려도 중간 대역을 절반 넘게 줄이지 않는다")
            XCTAssertLessThanOrEqual(values.redness, 0, "혈색은 더하지 않는다")
        }
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
        let female = try XCTUnwrap(((json["people"] as? [String: Any])?["groups"] as? [String: Any])?["female"] as? [String: Any])
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
```

`RecipeSchemaTests.testPeopleSchemaDescribesLayersGroupsAndRecords`의 `layerProperties.keys` 기대를 `["oneTouch", "skin", "face", "features", "makeup"]`로 바꾸고, `testRecipeSchemaPropertiesMatchEncodedKeys`가 `portrait` 하위 키를 대조한다면 `encodedSampleRecipe()`에 `recipe.portrait.oneTouch = 0.6`을 더한다.

- [ ] **Step 2: 실패 확인**

Run: `cd apple && swift test --filter "OneTouchBundleTests|RecipeSchemaTests"` → 컴파일 실패(`OneTouchBundle` 없음).

- [ ] **Step 3: 구현**

`apple/Sources/MellowShared/API/OneTouchBundle.swift`:

```swift
import Foundation

/// 원터치 인물 보정의 성별 표. 값은 "허용 상한"(강도 1)이고 기본 강도 0.6이 Evoto 전후 측정 크기다(스펙 G4 1.4·3.2).
/// 렌더는 이 표를 모른다. EditDocument.applyOneTouch가 표 × 강도를 레시피 항목 값으로 쓴다.
public enum OneTouchBundle {
    public static let maximumStrength = 1.0

    /// 표 한 줄. 블러셔 색이 nil이면 블러셔 없음(강도 0으로 덮어씀).
    public struct Values: Equatable, Sendable {
        public var smoothing: Double
        public var darkCircles: Double
        public var nasolabial: Double
        public var marionette: Double
        public var glabella: Double
        public var toneEvening: Double
        public var redness: Double
        public var shine: Double
        public var eyeBrighten: Double
        public var teethWhiten: Double
        public var lipVitality: Double
        public var blushIntensity: Double
        public var blushColorID: String?
    }

    /// 강도 1의 표. 매직 넘버는 여기에만 둔다. 남성은 질감을 남기고 색조 메이크업이 없다.
    public enum Table {
        public static let blushColorID = "blush-peach"
        public static let common = Values(
            smoothing: 0.35, darkCircles: 0.55, nasolabial: 0.4, marionette: 0.25, glabella: 0.3, toneEvening: 0.25,
            redness: -0.2, shine: 0.45, eyeBrighten: 0.25, teethWhiten: 0.25, lipVitality: 0, blushIntensity: 0,
            blushColorID: nil)
        public static let female = Values(
            smoothing: 0.45, darkCircles: 0.6, nasolabial: 0.45, marionette: 0.3, glabella: 0.3, toneEvening: 0.35,
            redness: -0.25, shine: 0.4, eyeBrighten: 0.3, teethWhiten: 0.3, lipVitality: 0.2, blushIntensity: 0.15,
            blushColorID: blushColorID)
        public static let male = Values(
            smoothing: 0.25, darkCircles: 0.5, nasolabial: 0.35, marionette: 0.25, glabella: 0.3, toneEvening: 0.15,
            redness: -0.2, shine: 0.5, eyeBrighten: 0.2, teethWhiten: 0.25, lipVitality: 0, blushIntensity: 0,
            blushColorID: nil)
        /// 사진 단위 몸 피부(전체 대상에서만).
        public static let bodyBrightness = 0.2
        public static let bodyTone = 0.0
    }

    /// 묶인 키. 이 키를 손으로 바꾸면 그 층의 oneTouch 표시가 지워진다. 얼굴형·체형은 들지 않는다.
    public static let keys: Set<PortraitKey> = PortraitKey.skin.union(PortraitKey.features)
        .union([.makeupPart(.blush), .makeupPart(.lip)])

    public static func values(for gender: Gender?) -> Values {
        switch gender {
        case .female: return Table.female
        case .male: return Table.male
        case nil: return Table.common
        }
    }

    public static func clampedStrength(_ strength: Double) -> Double {
        AdjustmentRange.clamped(strength, to: 0...maximumStrength)
    }

    /// 표 × 강도. 강도 0은 빈 층(호출자가 "묶음 제거"로 다룬다). 블러셔·립은 늘 덮어써 아래 층의 색조를 막는다.
    public static func layer(for gender: Gender?, strength: Double) -> PortraitLayer {
        let s = clampedStrength(strength)
        guard s > 0 else { return PortraitLayer() }
        let table = values(for: gender)
        var layer = PortraitLayer()
        layer.skinSmoothing = AdjustmentRange.clamped(table.smoothing * s, to: AdjustmentRange.unit)
        layer.autoBlemish = true
        let refinements: [SkinRefinementKey: Double] = [
            .darkCircles: table.darkCircles, .nasolabial: table.nasolabial, .marionette: table.marionette,
            .glabella: table.glabella, .toneEvening: table.toneEvening, .redness: table.redness, .shine: table.shine,
        ]
        for (key, value) in refinements {
            layer.skinRefinement[key] = AdjustmentRange.clamped(value * s, to: AdjustmentRange.skinRefinement(key))
        }
        layer.features[.eyeBrighten] = AdjustmentRange.clamped(table.eyeBrighten * s, to: AdjustmentRange.unit)
        layer.features[.teethWhiten] = AdjustmentRange.clamped(table.teethWhiten * s, to: AdjustmentRange.unit)
        layer.features[.lipVitality] = AdjustmentRange.clamped(table.lipVitality * s, to: AdjustmentRange.unit)
        layer.makeup[.blush] = MakeupTint(
            colorID: table.blushColorID, intensity: AdjustmentRange.clamped(table.blushIntensity * s, to: AdjustmentRange.unit))
        layer.makeup[.lip] = MakeupTint(colorID: nil, intensity: 0)
        layer.oneTouch = s
        return layer
    }

    public static func bodySkin(strength: Double) -> BodySkinAdjustments {
        let s = clampedStrength(strength)
        return BodySkinAdjustments(brightness: Table.bodyBrightness * s, tone: Table.bodyTone * s)
    }
}
```

`PortraitAdjustments`: `public var oneTouch: Double?`(주석 "원터치 표시. 전체 층의 묶인 항목이 OneTouchBundle 표 × 이 강도와 같다는 뜻. 렌더는 읽지 않는다"), init 인자(마지막, 기본 nil), `CodingKeys.oneTouch`, `decodeIfPresent`, `encodeIfPresent`. `numericValues`에 `[oneTouch ?? 0]`을 더한다(유한성 검사). `dependsOnFaces`는 그대로(표시 무관).

`PortraitLayer`: `public var oneTouch: Double?`(init 마지막 인자, 기본 nil), `isEmpty`에 `&& oneTouch == nil`, `numericValues`에 `[oneTouch ?? 0]`, `hasEffect`·`overriddenKeys`는 그대로(표시 무관), `remove(_:)`는 표시를 건드리지 않는다. Codable: `CodingKeys.oneTouch` 최상위 키로 `decodeIfPresent`/`encodeIfPresent`.

스키마: `portrait.properties.oneTouch` `{ "type": ["number","null"], "minimum": 0, "maximum": 1, "default": null, "description": "원터치 표시. 이 층의 묶인 항목이 OneTouchBundle 표 × 강도와 같다. 렌더는 읽지 않는다." }`, `$defs/portraitLayer.properties.oneTouch` 같은 정의. README: v2 요점에 "`oneTouch`는 원터치 표시(G4)"와 표 값(3.2절 표를 그대로 옮김), "키를 추가할 때의 규칙 (B~H)"에 "G4는 `portrait.oneTouch`·층 `oneTouch`를 같은 규칙으로 더했다(기본값 없음 = 표시 없음)".

- [ ] **Step 4: 통과 확인**

Run: `cd apple && swift test --filter MellowSharedTests` → 기준 +3, 0 failures. 기존 `PortraitLayerTests`·`EditRecipeCodingTests`가 `oneTouch` 없이 통과(없으면 쓰지 않음). lint 출력 없음. `./scripts/verify-modules.sh` 통과.

- [ ] **Step 5: 커밋**

```bash
git add apple/Sources/MellowShared/API/OneTouchBundle.swift apple/Sources/MellowShared/API/Adjustments.swift apple/Sources/MellowShared/API/PeopleAdjustments.swift shared/recipe-schema/edit-recipe.v2.schema.json shared/recipe-schema/README.md apple/Tests/MellowSharedTests/OneTouchBundleTests.swift apple/Tests/MellowSharedTests/RecipeSchemaTests.swift
git commit -m "feat(shared): 원터치 성별 표 OneTouchBundle과 층별 oneTouch 표시 키

공통·여성·남성 표(강도 1 = 상한), 강도 선형 곱, 블러셔·립은 덮어씀, 얼굴형·체형은 묶음 밖.
oneTouch는 렌더가 읽지 않는 표시이고 schemaVersion 2 유지.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 2: 편집 규칙 — applyOneTouch, 표시 해제, 프리셋·동기화·자동

**Files:**
- Modify: `apple/Sources/MellowEditing/API/EditDocument.swift`, `EditingPolicy.swift`, `SyncCategory.swift`
- Test: `apple/Tests/MellowEditingTests/EditDocumentTests.swift`

- [ ] **Step 1: 실패하는 테스트 작성**

`EditDocumentTests.swift` 끝에 추가:

```swift
    func testOneTouchWritesTablesPerLayerAndStrengthScales() {
        var document = EditDocument()
        document.set(.faceShape(.jaw, 0.3), in: .gender(.female))
        XCTAssertNil(document.applyOneTouch(strength: 1))
        XCTAssertEqual(document.undoStack.count, 2, "세 층 + 몸 피부가 한 단계")
        var expectedFemale = OneTouchBundle.layer(for: .female, strength: 1)
        expectedFemale.face[.jaw] = 0.3
        XCTAssertEqual(document.recipe.people.groups[.female], expectedFemale, "그룹의 묶음 밖 키는 보존")
        XCTAssertEqual(document.recipe.people.groups[.male], OneTouchBundle.layer(for: .male, strength: 1))
        var portrait = PortraitAdjustments()
        var makeup = MakeupAdjustments()
        OneTouchBundle.layer(for: nil, strength: 1).applied(to: &portrait, makeup: &makeup)
        portrait.oneTouch = 1
        XCTAssertEqual(document.recipe.portrait, portrait, "전체 층은 공통 표")
        XCTAssertEqual(document.recipe.makeup, makeup)
        XCTAssertEqual(document.recipe.bodySkin, OneTouchBundle.bodySkin(strength: 1))
        XCTAssertEqual(document.recipe.body, BodyShapeAdjustments(), "체형은 묶음 밖")
        XCTAssertEqual(document.recipe.portrait.face, FaceShapeAdjustments(), "얼굴형은 묶음 밖")
        XCTAssertNil(document.applyOneTouch(strength: 0.5))
        XCTAssertEqual(
            document.recipe.people.groups[.female]?.skinSmoothing ?? 0, OneTouchBundle.Table.female.smoothing * 0.5, accuracy: 1e-12)
        XCTAssertEqual(document.recipe.people.groups[.female]?.oneTouch, 0.5)
        XCTAssertEqual(document.recipe.portrait.oneTouch, 0.5)
        XCTAssertEqual(document.recipe.bodySkin.brightness, OneTouchBundle.Table.bodyBrightness * 0.5, accuracy: 1e-12)
        let steps = document.undoStack.count
        document.applyOneTouch(strength: 0.5)
        XCTAssertEqual(document.undoStack.count, steps, "같은 강도는 단계를 만들지 않는다")
        document.beginContinuousChange()
        document.applyOneTouch(strength: 0.6)
        document.applyOneTouch(strength: 0.7)
        document.endContinuousChange()
        XCTAssertEqual(document.undoStack.count, steps + 1, "드래그는 한 단계")
        XCTAssertNil(document.applyOneTouch(strength: 0))
        XCTAssertNil(document.recipe.portrait.oneTouch)
        XCTAssertEqual(document.recipe.portrait.skin, SkinAdjustments(), "강도 0은 전체 층 묶인 키를 기본값으로")
        XCTAssertEqual(document.recipe.bodySkin, BodySkinAdjustments())
        XCTAssertEqual(document.recipe.people.groups[.female], PortraitLayer(face: [.jaw: 0.3]), "그룹은 묶인 키만 지우고 얼굴형은 남는다")
        XCTAssertNil(document.recipe.people.groups[.male], "빈 그룹 층은 사라진다")
        document.appendLocalEdit(.spot(RetouchSpot(x: 0.5, y: 0.4, sourceX: 0.4, sourceY: 0.4, radius: 0.02)))
        XCTAssertNil(document.applyOneTouch(strength: 1), "잠긴 사진에서도 허용(얼굴형 키 없음)")
        XCTAssertEqual(document.recipe.people.groups[.female]?.face[.jaw], 0.3)
    }

    func testOneTouchOnGroupAndPersonUsesThatGenderTableOnly() {
        var document = EditDocument()
        XCTAssertNil(document.applyOneTouch(strength: 1, in: .gender(.male)))
        XCTAssertEqual(document.recipe.people.groups[.male], OneTouchBundle.layer(for: .male, strength: 1))
        XCTAssertNil(document.recipe.people.groups[.female], "다른 그룹은 그대로")
        XCTAssertEqual(document.recipe.portrait, PortraitAdjustments(), "전체 층도 그대로")
        XCTAssertEqual(document.recipe.bodySkin, BodySkinAdjustments(), "몸 피부는 전체 대상에서만")
        XCTAssertNil(document.set(.gender(.female), forPersonAt: faceAnchor))
        let id = document.recipe.people.individuals[0].id
        XCTAssertNil(document.applyOneTouch(strength: 1, in: .person(id)))
        XCTAssertEqual(document.recipe.people.person(id)?.layer, OneTouchBundle.layer(for: .female, strength: 1), "사람은 수동 성별 표")
        let other = PersonAnchor(x: 0.7, y: 0.5, width: 0.2)
        XCTAssertNil(document.applyOneTouch(strength: 0.5, forPersonAt: other))
        XCTAssertEqual(document.recipe.people.individuals.count, 2, "기록이 없으면 만든다")
        XCTAssertEqual(document.recipe.people.individuals[1].layer, OneTouchBundle.layer(for: nil, strength: 0.5), "미지정은 공통 표")
        XCTAssertEqual(document.applyOneTouch(strength: 1, in: .person(PersonID())), .unknownPerson)
        XCTAssertNil(document.applyOneTouch(strength: 0, in: .person(id)))
        XCTAssertEqual(document.recipe.people.person(id)?.layer, PortraitLayer(), "강도 0은 상속으로")
        XCTAssertEqual(document.recipe.people.person(id)?.gender, .female, "성별은 남는다")
    }

    func testManualChangeOfABundledKeyClearsOnlyThatLayerMark() {
        var document = EditDocument()
        document.applyOneTouch(strength: 0.6)
        XCTAssertNil(document.set(.skinRefinement(.darkCircles, 0.1)))
        XCTAssertNil(document.recipe.portrait.oneTouch, "전체 층의 표시만 지워진다")
        XCTAssertEqual(document.recipe.people.groups[.female]?.oneTouch, 0.6)
        XCTAssertEqual(document.recipe.people.groups[.male]?.oneTouch, 0.6)
        XCTAssertNil(document.set(.faceShape(.width, -0.2), in: .gender(.female)))
        XCTAssertEqual(document.recipe.people.groups[.female]?.oneTouch, 0.6, "묶음 밖 키는 표시를 지우지 않는다")
        let same = document.recipe.people.groups[.female]!.skinSmoothing!
        XCTAssertNil(document.set(.skinSmoothing(same), in: .gender(.female)))
        XCTAssertEqual(document.recipe.people.groups[.female]?.oneTouch, 0.6, "같은 값은 표시를 남긴다")
        XCTAssertNil(document.set(.makeupIntensity(.blush, 0.5), in: .gender(.female)))
        XCTAssertNil(document.recipe.people.groups[.female]?.oneTouch, "블러셔는 묶인 키")
        XCTAssertNil(document.resetOverrides([.skinSmoothing], in: .gender(.male)))
        XCTAssertNil(document.recipe.people.groups[.male]?.oneTouch)
        document.applyOneTouch(strength: 0.6)
        document.applyMakeupLook(nil, in: .gender(.female))
        XCTAssertNil(document.recipe.people.groups[.female]?.oneTouch, "룩 없음은 블러셔·립을 바꾼다")
        document.applyOneTouch(strength: 0.6)
        let suggestion = AutoEnhanceSuggestion(
            color: ColorAdjustments(exposure: 0.2), detail: DetailAdjustments(),
            portrait: PortraitAdjustments(skin: SkinAdjustments(smoothing: 0.3, autoBlemish: true)))
        XCTAssertTrue(document.applyAuto(suggestion))
        XCTAssertNil(document.recipe.portrait.oneTouch, "자동이 피부 보정을 바꾸면 전체 층 표시가 지워진다")
        XCTAssertEqual(document.recipe.people.groups[.female]?.oneTouch, 0.6)
    }

    func testPresetsCarryMarksAndSyncCopiesThemOnlyWithAllThreeCategories() {
        var source = EditDocument()
        source.applyOneTouch(strength: 0.6)
        let values = PresetValues(of: source.recipe)
        XCTAssertEqual(values.portrait.oneTouch, 0.6)
        XCTAssertEqual(values.people.groups[.female]?.oneTouch, 0.6)
        var preset = EditDocument()
        preset.apply(values)
        XCTAssertEqual(preset.recipe.portrait.oneTouch, 0.6, "프리셋은 표시를 그대로 나른다")
        XCTAssertEqual(preset.recipe.people.groups[.male]?.oneTouch, 0.6)
        var receiver = EditDocument()
        receiver.applyOneTouch(strength: 1)
        receiver.applyFromBatch(values, categories: [.color])
        XCTAssertEqual(receiver.recipe.portrait.oneTouch, 1, "색감만이면 표시 그대로")
        receiver.applyFromBatch(values, categories: [.skin])
        XCTAssertNil(receiver.recipe.portrait.oneTouch, "일부만 복사하면 표시가 거짓이라 지운다")
        XCTAssertNil(receiver.recipe.people.groups[.female]?.oneTouch)
        receiver.applyFromBatch(values, categories: SyncCategory.oneTouchCategories)
        XCTAssertEqual(receiver.recipe.portrait.oneTouch, 0.6, "세 항목을 모두 복사하면 원본 표시")
        XCTAssertEqual(receiver.recipe.people.groups[.female]?.oneTouch, 0.6)
        XCTAssertEqual(SyncCategory.oneTouchCategories, [.skin, .features, .makeup])
        var person = EditDocument()
        person.applyOneTouch(strength: 1, forPersonAt: faceAnchor)
        person.applyFromBatch(values, categories: [.skin])
        XCTAssertNil(person.recipe.people.individuals.first?.layer.oneTouch, "개인 층은 묶인 키가 빠지며 표시도 사라진다")
    }

    func testApplyAutoCanIncludeOneTouchInOneStep() {
        var document = EditDocument()
        let suggestion = AutoEnhanceSuggestion(
            color: ColorAdjustments(exposure: 0.2), detail: DetailAdjustments(shadows: 0.1),
            portrait: PortraitAdjustments(
                skin: SkinAdjustments(smoothing: 0.3, autoBlemish: true), features: FeatureAdjustments(eyeBrighten: 0.2)))
        XCTAssertTrue(document.applyAuto(suggestion, oneTouchStrength: EditingPolicy.oneTouchDefaultStrength))
        XCTAssertEqual(document.undoStack.count, 1)
        XCTAssertEqual(document.recipe.color.exposure, 0.2)
        XCTAssertEqual(document.recipe.portrait.oneTouch, EditingPolicy.oneTouchDefaultStrength)
        XCTAssertEqual(
            document.recipe.portrait.skin.smoothing, OneTouchBundle.Table.common.smoothing * EditingPolicy.oneTouchDefaultStrength,
            accuracy: 1e-12, "제안의 피부 0.3이 아니라 원터치 공통 표")
        XCTAssertEqual(document.recipe.people.groups[.female]?.oneTouch, EditingPolicy.oneTouchDefaultStrength)
        XCTAssertFalse(document.applyAuto(suggestion, oneTouchStrength: EditingPolicy.oneTouchDefaultStrength), "연타는 바뀌지 않는다")
        var plain = EditDocument()
        XCTAssertTrue(plain.applyAuto(suggestion))
        XCTAssertEqual(plain.recipe.portrait.skin.smoothing, 0.3, "강도 없이 부르면 지금 동작")
        XCTAssertNil(plain.recipe.portrait.oneTouch)
        XCTAssertEqual(EditingPolicy.oneTouchDefaultStrength, 0.6)
    }
```

- [ ] **Step 2: 실패 확인**

Run: `cd apple && swift test --filter EditDocumentTests` → 컴파일 실패(`applyOneTouch` 없음).

- [ ] **Step 3: 구현**

`EditingPolicy`: `public static let oneTouchDefaultStrength = 0.6`(주석 "Evoto 전후 측정 크기가 나는 강도(스펙 G4 1.4)"). `SyncCategory`: `public static let oneTouchCategories: Set<SyncCategory> = [.skin, .features, .makeup]`(주석 "셋을 모두 복사할 때만 oneTouch 표시를 복사한다").

`EditDocument`:

```swift
    /// 대상 층에 원터치 표 × 강도를 쓴다(스펙 G4 3.3). 체크포인트 하나(연속 변경 중이면 없음).
    /// .all: 전체 층 ← 공통 표, 남성·여성 그룹 ← 각 표, 몸 피부 ← 표. 그룹의 묶음 밖 키와 개인 층은 그대로.
    /// .gender: 그 그룹만. .person: 기록의 수동 성별 표(없으면 공통). 강도 0은 묶음 제거. 잠금과 무관(얼굴형 키 없음).
    @discardableResult
    public mutating func applyOneTouch(strength: Double, in scope: PortraitScope = .all) -> Rejection? {
        let s = OneTouchBundle.clampedStrength(strength)
        var updated = recipe
        switch scope {
        case .all:
            Self.writeOneTouch(gender: nil, strength: s, intoAllLayerOf: &updated)
            for gender in Gender.allCases {
                var group = updated.people.groups[gender] ?? PortraitLayer()
                Self.writeOneTouch(gender: gender, strength: s, into: &group)
                updated.people.groups[gender] = group.isEmpty ? nil : group
            }
            updated.bodySkin.brightness = OneTouchBundle.bodySkin(strength: s).brightness
            updated.bodySkin.tone = OneTouchBundle.bodySkin(strength: s).tone
        case .gender(let gender):
            var group = updated.people.groups[gender] ?? PortraitLayer()
            Self.writeOneTouch(gender: gender, strength: s, into: &group)
            updated.people.groups[gender] = group.isEmpty ? nil : group
        case .person(let id):
            guard let index = updated.people.individuals.firstIndex(where: { $0.id == id }) else { return .unknownPerson }
            Self.writeOneTouch(
                gender: updated.people.individuals[index].gender, strength: s, into: &updated.people.individuals[index].layer)
        }
        return commit(updated, clearsStaleMarks: false)
    }

    /// anchor의 사람에게. 기록이 없으면 만든다(체크포인트 하나).
    @discardableResult
    public mutating func applyOneTouch(strength: Double, forPersonAt anchor: PersonAnchor) -> Rejection? {
        var updated = recipe
        let id = updated.people.personID(at: anchor) ?? Self.appendPerson(at: anchor, to: &updated)
        guard let index = updated.people.individuals.firstIndex(where: { $0.id == id }) else { return .unknownPerson }
        Self.writeOneTouch(
            gender: updated.people.individuals[index].gender, strength: OneTouchBundle.clampedStrength(strength),
            into: &updated.people.individuals[index].layer)
        return commit(updated, clearsStaleMarks: false)
    }

    /// 층의 묶인 키를 표 × 강도로 바꾸고 표시를 둔다. 강도 0은 묶인 키 제거·표시 nil.
    private static func writeOneTouch(gender: Gender?, strength: Double, into layer: inout PortraitLayer) {
        layer.remove(OneTouchBundle.keys)
        let table = OneTouchBundle.layer(for: gender, strength: strength)
        guard strength > 0 else {
            layer.oneTouch = nil
            return
        }
        copy(OneTouchBundle.keys, from: table, into: &layer)
        layer.makeupLookID = nil
        layer.oneTouch = strength
    }

    /// 전체 층. 강도 0은 묶인 키를 기본값으로.
    private static func writeOneTouch(gender: Gender?, strength: Double, intoAllLayerOf recipe: inout EditRecipe) {
        resetAllLayer(OneTouchBundle.keys, in: &recipe)
        guard strength > 0 else {
            recipe.portrait.oneTouch = nil
            return
        }
        OneTouchBundle.layer(for: gender, strength: strength).applied(to: &recipe.portrait, makeup: &recipe.makeup)
        recipe.makeup.lookID = nil
        recipe.portrait.oneTouch = strength
    }
```

`commit`을 `commit(_ proposed: EditRecipe, clearsStaleMarks: Bool = true)`로 바꾸고, `clearsStaleMarks`면 `Self.clearStaleOneTouchMarks(previous: recipe, in: &updated)`를 `prune()` 앞에 부른다:

```swift
    /// 이전 레시피와 비교해 묶인 키가 실제로 바뀐 층의 oneTouch 표시를 지운다(메이크업 lookID와 같은 규칙).
    private static func clearStaleOneTouchMarks(previous: EditRecipe, in updated: inout EditRecipe) {
        if updated.portrait.oneTouch != nil, bundledValues(previous.portrait, previous.makeup) != bundledValues(updated.portrait, updated.makeup) {
            updated.portrait.oneTouch = nil
        }
        for gender in Gender.allCases {
            guard var group = updated.people.groups[gender], group.oneTouch != nil else { continue }
            if bundled(previous.people.groups[gender] ?? PortraitLayer()) != bundled(group) {
                group.oneTouch = nil
                updated.people.groups[gender] = group.isEmpty ? nil : group
            }
        }
        for index in updated.people.individuals.indices where updated.people.individuals[index].layer.oneTouch != nil {
            let id = updated.people.individuals[index].id
            let before = previous.people.person(id)?.layer ?? PortraitLayer()
            if bundled(before) != bundled(updated.people.individuals[index].layer) {
                updated.people.individuals[index].layer.oneTouch = nil
            }
        }
    }

    /// 층에서 묶인 키만 남긴 사본(표시 제외). 비교용.
    private static func bundled(_ layer: PortraitLayer) -> PortraitLayer {
        var copy = layer
        copy.remove(PortraitKey.all.subtracting(OneTouchBundle.keys))
        copy.oneTouch = nil
        copy.makeupLookID = nil
        return copy
    }

    private static func bundledValues(_ portrait: PortraitAdjustments, _ makeup: MakeupAdjustments) -> PortraitLayer {
        bundled(PortraitLayer.difference(portrait: portrait, makeup: makeup))
    }
```

(`PortraitLayer.difference`는 0 값을 빼고 담으므로 "0으로 바꿈"과 "없음"이 같아 보인다 — 전체 층은 빽빽한 값이라 그것이 맞다. 그룹·개인은 성긴 층 자체를 비교하므로 "0으로 덮어씀"과 "상속"이 구분된다.)

`apply(_:)`·`applyFromBatch`·`applyMakeupLook(_:in:)`·`applyAuto`·`resetOverrides`·`rebindPerson`·`removePerson`이 모두 `commit` 또는 `clearStaleOneTouchMarks`를 거치게 한다(`checkpoint(); recipe = updated` 직접 대입 자리에 `clearStaleOneTouchMarks(previous: recipe, in: &updated)`를 먼저 둔다). `merged(..., clearsIndividuals:)`에 표시 규칙:

```swift
        let copiesOneTouch = applied.isSuperset(of: SyncCategory.oneTouchCategories)
        if applied.contains(where: { SyncCategory.oneTouchCategories.contains($0) }) {
            updated.portrait.oneTouch = copiesOneTouch ? values.portrait.oneTouch : nil
            for gender in Gender.allCases {
                guard var group = updated.people.groups[gender] else { continue }
                group.oneTouch = copiesOneTouch ? values.people.groups[gender]?.oneTouch : nil
                updated.people.groups[gender] = group.isEmpty ? nil : group
            }
        }
```

(프리셋 `apply`는 `SyncCategory.all`이라 표시를 그대로 나른다. 그룹 층을 통째로 바꾸는 `apply`의 `copy`는 이미 `oneTouch`를 포함한 층을 쓰므로 위 블록이 `values`의 표시를 다시 둔다.)

`applyAuto`:

```swift
    @discardableResult
    public mutating func applyAuto(_ suggestion: AutoEnhanceSuggestion, oneTouchStrength: Double? = nil) -> Bool {
        var updated = recipe
        updated.color = suggestion.color
        updated.detail = suggestion.detail
        if let oneTouchStrength {
            var document = EditDocument(recipe: updated)
            document.applyOneTouch(strength: oneTouchStrength, in: .all)
            updated = document.recipe
        } else {
            updated.portrait.skin.smoothing = suggestion.portrait.skin.smoothing
            updated.portrait.skin.autoBlemish = suggestion.portrait.skin.autoBlemish
            updated.portrait.features.eyeBrighten = suggestion.portrait.features.eyeBrighten
            Self.clearStaleOneTouchMarks(previous: recipe, in: &updated)
        }
        guard updated != recipe else { return false }
        checkpoint()
        recipe = updated
        return true
    }
```

- [ ] **Step 4: 통과 확인**

Run: `cd apple && swift test` → Editing 기준 +5, 나머지 불변(H2까지의 모든 테스트 통과). lint 출력 없음. Mac 앱 테스트 → 불변(앱 코드 변경 없음, 호출부 컴파일만 확인).

- [ ] **Step 5: 커밋**

```bash
git add apple/Sources/MellowEditing/API/EditDocument.swift apple/Sources/MellowEditing/API/EditingPolicy.swift apple/Sources/MellowEditing/API/SyncCategory.swift apple/Tests/MellowEditingTests/EditDocumentTests.swift
git commit -m "feat(editing): 원터치 applyOneTouch(전체·그룹·사람)와 oneTouch 표시 해제·프리셋·동기화·자동 규칙

전체 대상은 전체 층 + 남성·여성 그룹 층 + 몸 피부를 한 단계로 쓴다. 묶인 키를 손으로 바꾸면 그 층의 표시만 지운다.
동기화는 피부·눈입·메이크업을 모두 복사할 때만 표시를 복사한다. applyAuto(oneTouchStrength:)는 선택.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 3: 실사진 원터치 수용 — 데모(하한·상한)와 커플(남녀 차이)

**Files:**
- Modify: `apple/Tests/MellowRenderingTests/RenderingTestSupport.swift`(`RealPeople`, `changedFraction(weight:)`, `outsideFaceChangedFraction`, `browMask`)
- Modify: `apple/Tests/MellowRenderingTests/RealPhotoAcceptanceTests.swift`

- [ ] **Step 1: 테스트 지원 추가**

`RenderingTestSupport.swift`:

```swift
extension DisplayScale {
    /// 가중치 > 0.5인 픽셀 중 바뀐 비율.
    static func changedFraction(_ before: PixelGrid, _ after: PixelGrid, weight: PixelGrid, minimumDelta: Int = defaultMinimumDelta) -> Double {
        var total = 0
        var changed = 0
        for y in 0..<before.height {
            for x in 0..<before.width {
                let point = CGPoint(x: x, y: y)
                guard weight.red(point) > 127 else { continue }
                total += 1
                let a = before.rgba(point)
                let b = after.rgba(point)
                if (0..<3).contains(where: { abs(Int(a[$0]) - Int(b[$0])) >= minimumDelta }) {
                    changed += 1
                }
            }
        }
        return total > 0 ? Double(changed) / Double(total) : 0
    }
}

extension RealPortrait {
    /// 얼굴 다각형(이마 호 포함)을 얼굴 폭 5% 넓힌 영역 밖에서 바뀐 비율(화면 배율). G4-1의 머리카락·배경 불변 검사와 같다.
    func outsideFaceChangedFraction(before: PixelGrid, after: PixelGrid) -> Double {
        let polygon = FaceRegions.skinPolygon(face: face, extent: extent, tuning: tuning)
        let inside = FaceRegions.containment(polygons: [polygon], dilation: faceWidth * 0.05)
        let scale = extent.width / DisplayScale.phoneWidth
        var changed = 0
        var total = 0
        for y in 0..<before.height {
            for x in 0..<before.width {
                guard !inside(CGPoint(x: CGFloat(x) * scale, y: CGFloat(y) * scale)) else { continue }
                total += 1
                let point = CGPoint(x: x, y: y)
                let a = before.rgba(point)
                let b = after.rgba(point)
                if (0..<3).contains(where: { abs(Int(a[$0]) - Int(b[$0])) >= DisplayScale.defaultMinimumDelta }) {
                    changed += 1
                }
            }
        }
        return total > 0 ? Double(changed) / Double(total) : 0
    }

    /// 두 눈썹 다각형 마스크(화면 배율).
    func browMask() throws -> PixelGrid {
        let brows = [FaceLandmark.leftEyebrow, .rightEyebrow].compactMap { FaceRegions.landmarkPolygon(face, $0, extent) }
        return try mask(FaceRegions.featheredPolygonMask(fill: brows, cut: [], face: face, extent: extent, tuning: tuning, cache: nil))
    }
}

/// 생성 커플 사진(couple-01.jpg)과 실제 Vision 얼굴, 라벨 성별(왼쪽부터).
final class RealPeople: @unchecked Sendable {
    static let couple: RealPeople = {
        do {
            return try RealPeople(file: "couple-01.jpg")
        } catch {
            fatalError("커플 사진 준비 실패: \(error)")
        }
    }()

    let image: CIImage
    let extent: CGRect
    let faces: [FaceGeometry]
    let labels: [Gender]
    let tuning = RenderTuning()

    private init(file: String) throws {
        image = try ImageLoader().load(url: try PeopleFixtures.url(file), maxDimension: tuning.previewMaxDimension)
        extent = image.extent
        faces = try VisionFaceAnalyzer().analyze(image)
        let photo = try PeopleFixtures.labels().photos.first { $0.file == file }
        labels = (photo?.people ?? []).compactMap { Gender(rawValue: $0.gender) }
    }
}
```

(G4-1 Task 1의 `testFaceItemsLeaveHairAndBackgroundUntouched` 본문을 `portrait.outsideFaceChangedFraction(before:after:)` 호출로 바꾼다.)

- [ ] **Step 2: 수용 테스트 추가**

`RealPhotoAcceptanceTests.swift`에 추가:

```swift
    // MARK: 원터치

    enum OneTouchVisibility {
        static let femaleDefaultChangedFraction = 0.05
        static let femaleMaximumChangedFraction = 0.10
        static let maleMaximumChangedFraction = 0.06
        static let femaleMaleDifferenceFraction = 0.02
        static let coupleMinimumChangedFraction = 0.03
    }

    enum OneTouchNaturalness {
        static let skinMeanLiftRange = (0.005 * 255)...(0.05 * 255)
        static let defaultFineVarianceRatio = 0.9
        static let maximumFineVarianceRatio = 0.85
        static let percentileAbsoluteLuma = 60.0
        static let skinChroma = 0.015
        static let maleLipChroma = 0.01
        static let femaleLipChroma = 0.03
        static let browChangedFraction = 0.05
        static let outsideFaceChangedFraction = 0.002
    }

    /// 원터치 표를 전체 층(공통)과 그룹 층에 쓰고 사진의 얼굴에 gender를 지정한 레시피. 몸 피부는 넣지 않는다(얼굴 비교).
    private func oneTouchRecipe(strength: Double, gender: Gender?, faces: [FaceGeometry]? = nil, genders: [Gender?]? = nil) -> EditRecipe {
        var recipe = EditRecipe()
        OneTouchBundle.layer(for: nil, strength: strength).applied(to: &recipe.portrait, makeup: &recipe.makeup)
        for group in Gender.allCases {
            recipe.people.groups[group] = OneTouchBundle.layer(for: group, strength: strength)
        }
        let targets = faces ?? [portrait.face]
        let assigned = genders ?? [gender]
        recipe.people.individuals = zip(targets, assigned).compactMap { face, gender in
            gender.map { PersonRecord(anchor: PersonAnchor(faceBox: face.boundingBox), gender: $0) }
        }
        return recipe
    }

    private func oneTouchGrid(strength: Double, gender: Gender?) throws -> (grid: PixelGrid, output: CIImage) {
        let catalog = try Support.sharedMakeupCatalog()
        let recipe = oneTouchRecipe(strength: strength, gender: gender)
        let context = RenderContext(
            extent: portrait.extent, recipe: recipe, analysis: portrait.analysis, tuning: portrait.tuning,
            makeupCatalog: catalog)
        let output = try RenderPipeline.standard.render(portrait.image, context: context)
        return (try DisplayScale.grid(output), output)
    }

    func testOneTouchIsVisibleForEachGenderAndDiffersBetweenThem() throws {
        let before = try base().grid
        let rect = try faceRect
        let femaleDefault = try oneTouchGrid(strength: EditingPolicyMirror.defaultStrength, gender: .female).grid
        XCTAssertGreaterThanOrEqual(
            DisplayScale.changedFraction(before, femaleDefault, in: rect), OneTouchVisibility.femaleDefaultChangedFraction)
        let female = try oneTouchGrid(strength: 1, gender: .female).grid
        XCTAssertGreaterThanOrEqual(DisplayScale.changedFraction(before, female, in: rect), OneTouchVisibility.femaleMaximumChangedFraction)
        let male = try oneTouchGrid(strength: 1, gender: .male).grid
        XCTAssertGreaterThanOrEqual(DisplayScale.changedFraction(before, male, in: rect), OneTouchVisibility.maleMaximumChangedFraction)
        XCTAssertGreaterThanOrEqual(
            DisplayScale.changedFraction(female, male, in: rect), OneTouchVisibility.femaleMaleDifferenceFraction, "남녀 결과가 다르다")
        let unassigned = try oneTouchGrid(strength: 1, gender: nil).grid
        let common = try DisplayScale.grid(portrait.render(oneTouchRecipe(strength: 1, gender: nil, genders: [nil]).withoutGroups()))
        XCTAssertEqual(DisplayScale.changedFraction(unassigned, common, in: rect), 0, accuracy: 1e-9, "미지정은 공통 표만")
        let lips = try portrait.mask(FaceRegions.lipMask(face: portrait.face, extent: portrait.extent, tuning: portrait.tuning))
        let maleLips = DisplayScale.chromaDelta(before, male, weight: lips)
        XCTAssertLessThanOrEqual(max(maleLips.cb, maleLips.cr), OneTouchNaturalness.maleLipChroma, "남성은 립 없음")
    }

    func testOneTouchStaysNaturalAtDefaultAndMaximum() throws {
        let before = try base().grid
        let rect = try faceRect
        let skin = try skinWeight()
        let blush = try portrait.mask(FaceRegions.blushMask(face: portrait.face, extent: portrait.extent, tuning: portrait.tuning))
        let brows = try portrait.browMask()
        let lips = try portrait.mask(FaceRegions.lipMask(face: portrait.face, extent: portrait.extent, tuning: portrait.tuning))
        for (gender, strength, ratioMinimum) in [
            (Gender?.some(.female), EditingPolicyMirror.defaultStrength, OneTouchNaturalness.defaultFineVarianceRatio),
            (.some(.male), EditingPolicyMirror.defaultStrength, OneTouchNaturalness.defaultFineVarianceRatio),
            (nil, EditingPolicyMirror.defaultStrength, OneTouchNaturalness.defaultFineVarianceRatio),
            (.some(.female), 1, OneTouchNaturalness.maximumFineVarianceRatio),
            (.some(.male), 1, OneTouchNaturalness.maximumFineVarianceRatio),
        ] {
            let result = try oneTouchGrid(strength: strength, gender: gender)
            let label = "\(String(describing: gender)) \(strength)"
            let lift = DisplayScale.lumaDelta(before, result.grid, weight: skin).mean
            XCTAssertTrue(OneTouchNaturalness.skinMeanLiftRange.contains(lift), "\(label) 피부 평균 ΔY \(lift)")
            XCTAssertGreaterThanOrEqual(
                try Support.fineVarianceRatio(
                    before: portrait.image, after: result.output, in: nativeFaceRect(), fineRadius: bandRadii.fine,
                    midRadius: bandRadii.mid),
                ratioMinimum, "\(label) 질감")
            XCTAssertLessThanOrEqual(
                DisplayScale.percentileAbsoluteLumaDelta(before, result.grid, in: rect, percentile: 0.99),
                OneTouchNaturalness.percentileAbsoluteLuma, "\(label) 국소 폭주 없음")
            let skinWithoutBlush = gender == .female ? try subtract(skin, blush) : skin
            let chroma = DisplayScale.chromaDelta(before, result.grid, weight: skinWithoutBlush)
            XCTAssertLessThanOrEqual(max(chroma.cb, chroma.cr), OneTouchNaturalness.skinChroma, "\(label) 색 기 없음")
            XCTAssertLessThanOrEqual(
                DisplayScale.changedFraction(before, result.grid, weight: brows), OneTouchNaturalness.browChangedFraction, "\(label) 눈썹")
            XCTAssertLessThanOrEqual(
                portrait.outsideFaceChangedFraction(before: before, after: result.grid),
                OneTouchNaturalness.outsideFaceChangedFraction, "\(label) 얼굴 밖")
            let lipChroma = DisplayScale.chromaDelta(before, result.grid, weight: lips)
            XCTAssertLessThanOrEqual(
                max(lipChroma.cb, lipChroma.cr),
                gender == .female ? OneTouchNaturalness.femaleLipChroma : OneTouchNaturalness.maleLipChroma, "\(label) 입술")
        }
    }

    /// 커플 생성 사진: 라벨대로 성별 지정 → 전체 원터치. 두 얼굴 다 바뀌되 여성이 더 많이, 남성 입술은 색이 그대로.
    func testOneTouchOnTheCouplePhotoTreatsMaleAndFemaleDifferently() throws {
        let people = RealPeople.couple
        XCTAssertEqual(people.faces.count, people.labels.count, "Vision 얼굴 수가 라벨과 같아야 한다(PeopleFixturesTests)")
        let catalog = try Support.sharedMakeupCatalog()
        let analysis = PhotoAnalysis(faces: people.faces)
        func render(_ recipe: EditRecipe) throws -> PixelGrid {
            let context = RenderContext(extent: people.extent, recipe: recipe, analysis: analysis, tuning: people.tuning, makeupCatalog: catalog)
            return try DisplayScale.grid(RenderPipeline.standard.render(people.image, context: context))
        }
        let before = try render(EditRecipe())
        let labelled = oneTouchRecipe(strength: 1, gender: nil, faces: people.faces, genders: people.labels)
        let after = try render(labelled)
        var changed: [Gender: Double] = [:]
        for (face, gender) in zip(people.faces, people.labels) {
            let rect = DisplayScale.rect(face.boundingBox, in: before)
            changed[gender] = DisplayScale.changedFraction(before, after, in: rect)
            XCTAssertGreaterThanOrEqual(changed[gender] ?? 0, OneTouchVisibility.coupleMinimumChangedFraction, "\(gender) 얼굴이 바뀐다")
        }
        XCTAssertGreaterThan(changed[.female] ?? 0, changed[.male] ?? 0, "여성 표가 더 많이 바꾼다")
        if let maleIndex = people.labels.firstIndex(of: .male) {
            let face = people.faces[maleIndex]
            let lips = try DisplayScale.grid(
                XCTUnwrap(FaceRegions.lipMask(face: face, extent: people.extent, tuning: people.tuning)).image.cropped(to: people.extent))
            let chroma = DisplayScale.chromaDelta(before, after, weight: lips)
            XCTAssertLessThanOrEqual(max(chroma.cb, chroma.cr), OneTouchNaturalness.maleLipChroma, "남성 입술 색은 그대로")
        }
        let unassigned = try render(oneTouchRecipe(strength: 1, gender: nil, faces: people.faces, genders: people.labels.map { _ in nil }))
        for face in people.faces {
            let rect = DisplayScale.rect(face.boundingBox, in: before)
            XCTAssertGreaterThanOrEqual(DisplayScale.changedFraction(before, unassigned, in: rect), OneTouchVisibility.coupleMinimumChangedFraction, "미지정도 공통 표로 바뀐다")
        }
    }

    /// 두 마스크의 차(a × (1 − b)).
    private func subtract(_ a: PixelGrid, _ b: PixelGrid) throws -> PixelGrid {
        // PixelGrid는 읽기 전용이라 CIImage로 다시 만든다.
        let size = CGSize(width: a.width, height: a.height)
        var bytes = [UInt8](repeating: 0, count: a.width * a.height * 4)
        for y in 0..<a.height {
            for x in 0..<a.width {
                let point = CGPoint(x: x, y: y)
                let value = UInt8(max(0, Int(a.red(point)) - Int(b.red(point))))
                let offset = ((a.height - 1 - y) * a.width + x) * 4
                bytes[offset] = value
                bytes[offset + 1] = value
                bytes[offset + 2] = value
                bytes[offset + 3] = 255
            }
        }
        let data = Data(bytes)
        let image = CIImage(bitmapData: data, bytesPerRow: a.width * 4, size: size, format: .RGBA8, colorSpace: CGColorSpace(name: CGColorSpace.sRGB))
        return PixelGrid(try Support.renderer.makeCGImage(image))
    }
}

/// MellowEditing을 import할 수 없는 테스트 타깃에서 기본 강도를 같은 값으로 둔다. EditDocumentTests가 0.6을 고정한다.
private enum EditingPolicyMirror {
    static let defaultStrength = 0.6
}

extension EditRecipe {
    /// 그룹 층을 뺀 사본(미지정 = 공통 표만인지 확인용).
    fileprivate func withoutGroups() -> EditRecipe {
        var copy = self
        copy.people.groups = [:]
        return copy
    }
}
```

- [ ] **Step 3: 실행·조정**

Run: `cd apple && swift test --filter RealPhotoAcceptanceTests` → 새 네 테스트 포함 전부 통과. 미달·초과 항목은 `OneTouchBundle.Table` 값을 고친다(하한 미달 → 올림, 상한 초과 → 내림, 두 방향을 못 맞추면 그 항목을 표에서 빼고 VALIDATION에 적는다). 문턱(`OneTouchVisibility`·`OneTouchNaturalness`)은 바꾸지 않는다. 바꾼 표 값은 스펙 3.2 표와 README 표에 반영한다(결정 표 "(G4-2 구현 중 변경)").

전체: `cd apple && swift test` → Rendering 기준 +4, 나머지 불변. lint 출력 없음.

- [ ] **Step 4: 커밋**

```bash
git add apple/Tests/MellowRenderingTests/RenderingTestSupport.swift apple/Tests/MellowRenderingTests/RealPhotoAcceptanceTests.swift docs/superpowers/specs/2026-10-21-beauty-g4-one-touch-design.md shared/recipe-schema/README.md
git commit -m "test(rendering): 원터치 실사진 수용 — 데모의 보임·자연 상한과 커플 사진의 남녀 차이

기본 0.6·최대 1에서 피부 평균 ΔY 범위·질감 비·99백분위·색 기·눈썹·얼굴 밖·입술을 재고,
커플 사진에서 라벨대로 지정한 남녀가 다르게 바뀌는지 확인한다.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

(스펙·README에 바뀐 것이 없으면 `git add`에서 뺀다.)

---

## 자체 검토 결과

- **스펙 대조:** §3.1 키·스키마 → Task 1. §3.2 표·강도·상한 → Task 1(`Table`·`maximumStrength`·`layer`). §3.3 편집 규칙(세 층 쓰기, 몸 피부, 표시 해제, 프리셋, 동기화, 자동) → Task 2. §1.2·1.4 원터치 행 → Task 3. §7.1 G4-2 행 → Task 1~3. §8 "G4-2 3 Task"와 같다. 얼굴형·체형 제외(결정 표) → Task 1·2 단언.
- **타입 일관성:** `OneTouchBundle.maximumStrength`·`keys`·`Values`·`Table`·`values(for:)`·`clampedStrength`·`layer(for:strength:)`·`bodySkin(strength:)`, `PortraitAdjustments.oneTouch`, `PortraitLayer.oneTouch`, `EditingPolicy.oneTouchDefaultStrength`, `SyncCategory.oneTouchCategories`, `EditDocument.applyOneTouch(strength:in:)`·`applyOneTouch(strength:forPersonAt:)`·`applyAuto(_:oneTouchStrength:)`·`commit(_:clearsStaleMarks:)`·`clearStaleOneTouchMarks`, `DisplayScale.changedFraction(weight:)`, `RealPortrait.outsideFaceChangedFraction`·`browMask`, `RealPeople.couple`을 정의한 Task와 쓰는 Task에서 같게 썼다. 테스트 수: Shared +3, Editing +5, Rendering +4.
- **Review Focus 매핑:** 1→Task 2, 2→Task 2, 3→Task 2, 4→Task 3, 5→Task 3, 6→Task 2. 모두 테스트 코드가 있다.
- **플레이스홀더 점검:** 표 값은 스펙 3.2의 시작값이고 Task 3이 실측으로 고칠 수 있다고 적었다. "TBD/TODO/나중에" 없음.
