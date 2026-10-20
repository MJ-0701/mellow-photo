# 인물 보정 G2 몸 피부·톤 구현 계획

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 뷰티에 "피부톤" 탭을 더해 피부 밝기·피부 톤(따뜻 ↔ 차가움)·바디 피부 매끄럽게 슬라이더 3개가 얼굴·팔·목처럼 보이는 피부 전체에 걸리고 옷·배경·눈·입은 그대로 두게 한다.

**Architecture:** MellowShared에 최상위 레시피 그룹 `bodySkin`(`BodySkinAdjustments`, schemaVersion 2, 기본값 0)을 더하고 `dependsOnPerson`에 포함한다. MellowRendering은 `skin` 바로 뒤에 새 단계 `bodySkin`(`BodySkinStage`)을 둔다. 마스크는 인물 마스크(배경 단계와 같은 확대·흐림) × 가장 큰 얼굴의 볼 기준 피부색 가중치 × (1 − 모든 얼굴의 눈·입 비트맵)이고, 매끄럽게는 거기서 얼굴 피부 다각형을 뺀다. 밝기·톤은 기존 눈·입 커널(`ToneShift`)에 Cb 가산을 더해 쓴다. 얼굴이나 인물 마스크가 없으면 조용히 건너뛴다. 앱은 뷰티 › 피부톤 탭이고 사람 없음 안내는 배경 도구와 같은 규칙이다.

**Tech Stack:** Swift 5.9 tools / Swift 5 언어 모드, SwiftUI + Observation, Core Image(CIGaussianBlur·CIMultiplyCompositing·CIMaximumCompositing·CIColorInvert·CIBlendWithMask, 기존 CIKL 커널 재사용), XCTest, XcodeGen 2.46.0.

**Spec:** `docs/superpowers/specs/2026-10-20-beauty-g-evoto-design.md` (G2에 해당하는 절: 1.1, 1.2, 1.3, 1.4, 1.6의 몸 피부, 1.9, 1.10, 2, 4). 선행: G1 계획 전부 머지.

## 사람이 확인할 것

- **순서.** Task 1 레시피 → 2 편집 규칙 → 3 렌더 기반(인물 마스크 분리·`ToneShift` Cb·몸 반지름·눈입 비트맵·캐시 상한) → 4 `BodySkinStage`·파이프라인 연결 → 5 앱 피부톤 탭·시나리오. 5개 Task, Task마다 Opus 구현 → 리뷰 → 수정, 끝에 전체 리뷰.
- **외부 효과가 있는 단계.** 없음.
- **스펙이 정하지 않아 이 계획이 정한 것.**

| 결정 | 이유 | 바꾸면 비용 |
|---|---|---|
| 눈·입 제외 비트맵은 모든 얼굴의 눈 다각형과 바깥 입술을 한 비트맵에 그림(사진당 해상도마다 캐시 항목 1개) | 얼굴마다 그리면 얼굴 수만큼 항목이 늘고 합성도 그만큼 늘어남 | 작음 |
| 몸 매끄럽게의 대역 반지름은 짧은 변 비례(모공 0.2%·얼룩 1.2%)이고 계산 영역은 사진 전체 | 몸에는 "얼굴 폭"이 없고 인물 마스크의 실제 범위를 픽셀을 읽지 않고는 모름 | 작음 |
| 적용 순서는 매끄럽게 → 밝기·톤 | 밝힌 뒤 흐리면 밝기 경계가 번짐 | 작음 |
| 기준 얼굴은 상자 폭이 가장 큰 얼굴 하나(대상 얼굴 선택과 무관) | 몸 피부는 얼굴별 보정이 아니고, 기준색은 하나여야 함 | 작음 |
| 피부톤 탭의 사람 없음 안내·슬라이더 켜짐 규칙은 배경 도구와 같은 `backgroundAvailability`를 그대로 씀 | 같은 인물 마스크에 기대므로 판정이 같음 | 작음 |

- **범위 밖.** 얼굴 없는 사진의 몸 피부(스펙 범위 밖 — 사용자가 고정 피부색 대체를 거부, 나중 후보는 관절점 근처 피부색 표본), 효과·동기화·분할 비교(G3). 뒷모습 사진에서는 피부톤 탭이 얼굴 없음 안내만 보인다.
- **위험.** 얼굴과 몸의 조명이 다르거나 피부색이 다른 사람이 함께 있으면 피부 판별이 흔들린다(가중치 거리 기준 0.05, 강도 상한 보수적). 사진 전체 흐림이라 48MP 저장이 느려질 수 있다(G3 VALIDATION에서 측정). 밝기는 흰색 쪽 섞기라 채도가 조금 준다.
- **사용자 조치.** 자동 검증만 한다. 실제 사진 확인은 G3 뒤.

---

## 에이전트 참조

## Global Constraints

G1 계획의 Global Constraints를 그대로 따른다(worktree `.claude/worktrees/beauty-g`, 브랜치 `beauty-g-evoto`, `DEVELOPER_DIR`, 모듈 표 불변, lint, 커밋 서명, 다른 세션이 고치는 `PhotoPickerButton.swift`·`project.yml`·`scripts/test-apple.sh`·UI 테스트 타깃은 건드리지 않음). 이 계획에서 다른 것:

- 파이프라인 단계 이름 순서는 Task 4부터 `skin, bodySkin, feature, makeup, background, shapeWarp, localEdit, geometry, color, detail, look`이다(스펙 1.3).
- 레시피: 최상위 `bodySkin` 추가(키 추가만, schemaVersion 2). `bodySkin.tone`만 `AdjustmentRange.bipolar`, `brightness`·`smoothing`은 `unit`. `EditRecipe.dependsOnPerson`에 포함하고 `dependsOnFaces`에는 넣지 않는다(스펙 결정 표).
- `RenderTuning` 새 상수 시작값(Task 4): bodySkinChromaSigma 0.05, bodySkinMaskFeather 0.004, bodySkinLiftMax 0.2, bodySkinToneMax 0.025, bodySkinFineBandFraction 0.002, bodySkinMidBandFraction 0.012. `RegionMaskCache.entriesPerFacePerResolution`은 8 → 9(Task 3).
- 새 CIKL 커널 없음(기존 `chromaWeight`·`toneShift` 재사용). `FeatureKernels`의 toneShift 커널에 인자 하나(`blueness`)가 늘어나지만 경고 수는 같다.
- 이 계획은 앱 파일을 더하거나 지우지 않으므로 `xcodegen generate`가 필요 없다.
- 기준 테스트 수(G1 끝): 패키지 354(Shared 45 · Rendering 244 · Library 30 · Export 4 · Editing 31), 앱 Mac 72. 목표: 패키지 367(Shared 47 · Rendering 253 · Library 30 · Export 4 · Editing 33), 앱 Mac 74.

## Review Focus

1. **얼굴은 있지만 사람 마스크가 없는 사진(인물 분석 실패·작은 사람)에 피부 밝기를 넣는다.** 렌더는 건너뛰고 오류를 내지 않아야 하며, 저장도 성공해야 한다(`dependsOnPerson`이라 배경 흐림과 같은 규칙). → Task 4 `testZeroValuesNoPersonOrNoFaceReturnInputBytes`, Task 5 `testSkinToneSlidersFollowPersonAvailabilityAndPresetValues`.
2. **사람 마스크는 있지만 얼굴이 없는 사진(뒷모습).** 기준색이 없어 건너뛰고 패널은 얼굴 없음 안내를 보인다. → Task 4 같은 테스트, Task 5의 `BeautyPanel` 분기(기존 `faceAvailability`).
3. **대상 얼굴을 범위 밖 번호로 둔 프리셋.** 몸 피부는 대상 얼굴과 무관하게 가장 큰 얼굴을 기준으로 동작해야 한다. → Task 4 `testBodySkinIgnoresTargetFaceAndUsesTheLargestFace`.
4. **흰 옷·회색 배경이 인물 마스크 안에 있다.** 피부색 가중치가 0이라 한 바이트도 바뀌지 않아야 한다. → Task 4 `testBrightnessLiftsVisibleSkinAndLeavesShirtBackgroundAndEyes`.
5. **얼굴 피부 보정과 몸 매끄럽게를 함께 켠다.** 얼굴은 두 번 매끄럽게 되지 않아야 한다(얼굴 피부 다각형 제외). → Task 4 `testSmoothingSkipsTheFaceAndSmoothsBodySkin`.
6. **G 이전 프리셋·세션을 연다.** `bodySkin`이 없어도 기본값으로 읽혀야 한다. → Task 1 `testBodySkinRoundTripsDefaultsAndDependsOnPerson`.

## 인터페이스 요약 (모든 Task가 공유하는 이름)

```swift
// MellowShared (Task 1)
public enum BodySkinKey: String, CaseIterable, Codable, Sendable { brightness, tone, smoothing }
public struct BodySkinAdjustments { brightness, tone, smoothing; init(brightness:tone:smoothing:); subscript(BodySkinKey); numericValues; hasEffect }
AdjustmentRange.bodySkin(_:)                       // tone만 bipolar
EditRecipe.bodySkin, init(…background:bodySkin:body:makeup:operations:), dependsOnPerson 포함
PresetValues.bodySkin, init(…background:bodySkin:body:makeup:)

// MellowEditing (Task 2)
EditChange.bodySkin(BodySkinKey, Double)           // affectsGeometry false
EditingPolicy.bodySkinRange(_:)

// MellowRendering (Task 3·4)
BackgroundStage.personMask(_:extent:feather:) -> CIImage       // 사람 1·배경 0, backgroundMask는 이것의 반전
ToneShift.blueness: Double = 0                                  // 감마 Cb 가산, 커널 인자 추가
FrequencySeparation.smoothed(_:bounds:radii:smoothing:tuning:)  // 반지름을 직접 받는 오버로드
FaceRegions.featureMask(faces:extent:tuning:cache:) -> RegionMask?      // 모든 얼굴의 눈 + 바깥 입술 한 비트맵
FaceRegions.skinPolygonUnion(faces:extent:tuning:cache:) -> CIImage     // 얼굴마다 skinPolygonRaster의 최대
RegionMaskCache.entriesPerFacePerResolution = 9
RenderTuning: + bodySkin 상수 6개
struct BodySkinStage: RenderStage { name "bodySkin"; static clamped(_:), referenceFace(_:), bodyRadii(shortSide:tuning:) }
RenderPipeline.standard: SkinStage() 뒤에 BodySkinStage()

// 테스트 지원 (Task 4)
SyntheticFace.makeWithBody(), bodySkinRect, leftShirtRect, bodyPatch, bodySkinPoint, shirtPoint, backgroundBesideBody,
    backgroundAboveHead, bodyPersonMask

// 앱 (Task 5)
BeautyTab.skinTone
AppModel.canAdjustBodySkin(_:)
UserMessage.beautyTabSkinTone, bodySkinTitle(_:), bodySkinHint, bodySkinNoPersonHint
```

---

### Task 1: 레시피 — BodySkinAdjustments, EditRecipe.bodySkin, PresetValues, 스키마

**Files:**
- Create: `apple/Sources/MellowShared/API/BodySkinAdjustments.swift`
- Modify: `apple/Sources/MellowShared/API/AdjustmentRange.swift`, `EditRecipe.swift`, `Preset.swift`
- Modify: `shared/recipe-schema/edit-recipe.v2.schema.json`, `session-file.v2.schema.json`, `README.md`
- Test: `apple/Tests/MellowSharedTests/EditRecipeCodingTests.swift`, `RecipeSchemaTests.swift`

**Interfaces:**
- Produces: 인터페이스 요약의 MellowShared 항목. 기존 `EditRecipe(...)`·`PresetValues(...)` 호출은 새 인자에 기본값이 있어 그대로 컴파일된다.

설계 근거: 스펙 1.2. 몸 피부는 얼굴별 값이 아니라 최상위 그룹이고, 인물 마스크가 필요해 `dependsOnPerson`에 들어간다.

- [ ] **Step 1: 실패하는 테스트 작성**

`EditRecipeCodingTests.swift`에 추가:

```swift
    func testBodySkinRoundTripsDefaultsAndDependsOnPerson() throws {
        let legacy = #"{"schemaVersion":2,"background":{"blur":0.2}}"#
        let decoded = try JSONDecoder().decode(EditRecipe.self, from: Data(legacy.utf8))
        XCTAssertEqual(decoded.bodySkin, BodySkinAdjustments(), "G2 이전 파일은 몸 피부가 0")
        var recipe = EditRecipe()
        recipe.bodySkin = BodySkinAdjustments(brightness: 0.3, tone: -0.2, smoothing: 0.5)
        XCTAssertEqual(recipe.bodySkin.numericValues, [0.3, -0.2, 0.5])
        XCTAssertEqual(recipe.bodySkin[.tone], -0.2)
        XCTAssertTrue(recipe.bodySkin.hasEffect)
        XCTAssertTrue(recipe.dependsOnPerson, "몸 피부는 인물 마스크가 필요하다")
        XCTAssertFalse(recipe.dependsOnFaces, "얼굴 분석이 실패한 사진의 저장을 막지 않는다")
        XCTAssertFalse(recipe.isDefault)
        let data = try JSONEncoder().encode(recipe)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let bodySkin = try XCTUnwrap(json["bodySkin"] as? [String: Any])
        XCTAssertEqual(Set(bodySkin.keys), Set(BodySkinKey.allCases.map(\.rawValue)))
        XCTAssertEqual(try JSONDecoder().decode(EditRecipe.self, from: data), recipe)
        XCTAssertEqual(AdjustmentRange.bodySkin(.tone), AdjustmentRange.bipolar)
        XCTAssertEqual(AdjustmentRange.bodySkin(.brightness), AdjustmentRange.unit)
        XCTAssertEqual(AdjustmentRange.bodySkin(.smoothing), AdjustmentRange.unit)
    }

    func testBodySkinScalarsAreCheckedForFinitenessAndCarriedByPresets() throws {
        for path in [\EditRecipe.bodySkin.brightness, \EditRecipe.bodySkin.tone, \EditRecipe.bodySkin.smoothing] {
            var recipe = EditRecipe()
            recipe[keyPath: path] = .nan
            XCTAssertFalse(recipe.allValuesFinite, "\(path)")
        }
        var recipe = EditRecipe()
        recipe.bodySkin.tone = 0.4
        let values = PresetValues(of: recipe)
        XCTAssertEqual(values.bodySkin.tone, 0.4)
        XCTAssertEqual(try JSONDecoder().decode(PresetValues.self, from: JSONEncoder().encode(values)), values)
        let legacy = try JSONDecoder().decode(PresetValues.self, from: Data(#"{"color":{},"portrait":{}}"#.utf8))
        XCTAssertEqual(legacy.bodySkin, BodySkinAdjustments())
    }
```

`RecipeSchemaTests.swift`: `encodedSampleRecipe()`에 `recipe.bodySkin.tone = -0.2`를 더하고, `testRecipeSchemaPropertiesMatchEncodedKeys`의 키 배열 `["color", "portrait", "detail", "look", "geometry", "background", "body", "makeup"]`에 `"bodySkin"`을 더한다.

- [ ] **Step 2: 실패 확인**

Run: `cd apple && swift test --filter EditRecipeCodingTests` → 컴파일 실패(`BodySkinAdjustments` 없음).

- [ ] **Step 3: 구현**

`apple/Sources/MellowShared/API/BodySkinAdjustments.swift`:

```swift
import Foundation

/// 몸 피부 슬라이더 이름. 레시피 JSON 키와 같다. tone만 가운데 0인 양방향이다.
public enum BodySkinKey: String, CaseIterable, Codable, Sendable {
    case brightness
    case tone
    case smoothing
}

/// 보이는 피부 전체(얼굴 포함)에 거는 밝기 0…1, 톤 −1…1(따뜻 ↔ 차가움), 매끄럽게 0…1. 렌더는 bodySkin 단계(인물 마스크 × 피부색).
public struct BodySkinAdjustments: Codable, Equatable, Sendable {
    public var brightness: Double
    public var tone: Double
    public var smoothing: Double

    public init(brightness: Double = 0, tone: Double = 0, smoothing: Double = 0) {
        self.brightness = brightness
        self.tone = tone
        self.smoothing = smoothing
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        brightness = try container.decodeIfPresent(Double.self, forKey: .brightness) ?? 0
        tone = try container.decodeIfPresent(Double.self, forKey: .tone) ?? 0
        smoothing = try container.decodeIfPresent(Double.self, forKey: .smoothing) ?? 0
    }

    public subscript(key: BodySkinKey) -> Double {
        get {
            switch key {
            case .brightness: return brightness
            case .tone: return tone
            case .smoothing: return smoothing
            }
        }
        set {
            switch key {
            case .brightness: brightness = newValue
            case .tone: tone = newValue
            case .smoothing: smoothing = newValue
            }
        }
    }

    /// BodySkinKey.allCases 순서.
    public var numericValues: [Double] { BodySkinKey.allCases.map { self[$0] } }
    public var hasEffect: Bool { numericValues.contains { $0 != 0 } }
}
```

`AdjustmentRange.swift`에 추가:

```swift
    /// 피부 톤(따뜻 ↔ 차가움)만 양방향이다.
    public static func bodySkin(_ key: BodySkinKey) -> ClosedRange<Double> {
        key == .tone ? bipolar : unit
    }
```

`EditRecipe.swift`: `public var background = BackgroundAdjustments()` 아래에 `public var bodySkin = BodySkinAdjustments()`. init 인자 `background: BackgroundAdjustments = .init(), bodySkin: BodySkinAdjustments = .init(), body: …`와 대입. `CodingKeys`에 `case bodySkin`(background 다음). `init(from:)`에 `bodySkin = try container.decodeIfPresent(BodySkinAdjustments.self, forKey: .bodySkin) ?? .init()`. `encode`에 `try container.encode(bodySkin, forKey: .bodySkin)`. `dependsOnPerson`을 `background.hasEffect || bodySkin.hasEffect`로, doc 주석 "배경 흐림과 몸 피부는 인물 마스크가 필요하다". `allValuesFinite`의 `groups`에 `+ bodySkin.numericValues`.

`Preset.swift`: `PresetValues`에 `public var bodySkin: BodySkinAdjustments`(background 다음), init 인자 `bodySkin: BodySkinAdjustments = .init()`, `init(of:)`에 `bodySkin: recipe.bodySkin`, `init(from:)`에 `decodeIfPresent … ?? .init()`.

`edit-recipe.v2.schema.json`: `"background"` 항목 뒤에 추가:

```json
    "bodySkin": {
      "type": "object", "additionalProperties": false,
      "description": "보이는 피부 전체(인물 마스크 × 피부색). tone만 가운데 0인 양방향.",
      "properties": {
        "brightness": { "type": "number", "default": 0, "minimum": 0, "maximum": 1 },
        "tone": { "type": "number", "default": 0, "minimum": -1, "maximum": 1, "description": "양수는 따뜻하게, 음수는 차갑게." },
        "smoothing": { "type": "number", "default": 0, "minimum": 0, "maximum": 1, "description": "얼굴 피부 영역을 뺀 몸 피부만." }
      }
    },
```

`session-file.v2.schema.json`의 프리셋 `values.properties`에 `"bodySkin": { "$ref": "edit-recipe.v2.schema.json#/properties/bodySkin" },`(background 다음).

`README.md`: 요점의 "최상위 `background`(배경 흐림), `body`…" 줄에 "`bodySkin`(몸 피부 밝기·톤·매끄럽게, `tone`만 −1~1)"을 더하고, 범위 표에 `| \`bodySkin.{brightness,smoothing}\` | 0 … 1 | 0 … 1 |`·`| \`bodySkin.tone\` | −1 … 1 | −1 … 1 |`, 프리셋 `values` 줄에 `bodySkin`을 더한다. 표의 Apple 구현 파일 목록에 `BodySkinAdjustments.swift`를 더한다.

- [ ] **Step 4: 통과 확인**

Run: `cd apple && swift test` → Shared `Executed 47 tests`, Library 30(`SessionSchemaTests`가 프리셋 키 집합을 대조하므로 세션 스키마를 고치지 않으면 실패한다), 나머지 그대로, 모두 0 failures. lint 출력 없음.

- [ ] **Step 5: 커밋**

```bash
git add apple/Sources/MellowShared/API/BodySkinAdjustments.swift apple/Sources/MellowShared/API/AdjustmentRange.swift apple/Sources/MellowShared/API/EditRecipe.swift apple/Sources/MellowShared/API/Preset.swift shared/recipe-schema/edit-recipe.v2.schema.json shared/recipe-schema/session-file.v2.schema.json shared/recipe-schema/README.md apple/Tests/MellowSharedTests/EditRecipeCodingTests.swift apple/Tests/MellowSharedTests/RecipeSchemaTests.swift
git commit -m "feat(shared): 몸 피부 레시피 그룹 bodySkin 추가

밝기·톤·매끄럽게를 기본값 0으로 더한다(schemaVersion 2 유지). 인물 마스크 의존에
포함하고 얼굴 의존에는 넣지 않는다. 프리셋도 나른다.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 2: 편집 규칙 — bodySkin 변경, 일괄·프리셋 복사

**Files:**
- Modify: `apple/Sources/MellowEditing/API/EditChange.swift`, `EditingPolicy.swift`, `EditDocument.swift`
- Test: `apple/Tests/MellowEditingTests/EditDocumentTests.swift`

**Interfaces:**
- Produces: `EditChange.bodySkin(BodySkinKey, Double)`(`affectsGeometry == false`), `EditingPolicy.bodySkinRange(_:)`. `merged`가 `bodySkin`을 복사한다.

- [ ] **Step 1: 실패하는 테스트 작성**

```swift
    func testBodySkinChangesClampAreNotLockedAndAreCopiedByPresetsAndBatch() {
        var document = EditDocument()
        document.appendLocalEdit(.warp(WarpStroke(x: 0.5, y: 0.5, dx: 0.01, dy: 0, radius: 0.1)))
        XCTAssertFalse(EditChange.bodySkin(.tone, 0.5).affectsGeometry)
        XCTAssertNil(document.set(.bodySkin(.brightness, 1.5)), "색만 바꾸므로 잠기지 않는다")
        XCTAssertEqual(document.recipe.bodySkin.brightness, 1)
        XCTAssertNil(document.set(.bodySkin(.tone, -4)))
        XCTAssertEqual(document.recipe.bodySkin.tone, -1, "톤만 양방향")
        document.set(.bodySkin(.smoothing, -0.5))
        XCTAssertEqual(document.recipe.bodySkin.smoothing, 0)
        XCTAssertEqual(EditingPolicy.bodySkinRange(.tone), EditingPolicy.bipolarRange)
        XCTAssertEqual(EditingPolicy.bodySkinRange(.smoothing), EditingPolicy.unitRange)
        var other = EditDocument()
        other.apply(PresetValues(of: document.recipe))
        XCTAssertEqual(other.recipe.bodySkin, BodySkinAdjustments(brightness: 1, tone: -1), "프리셋이 몸 피부를 나른다")
        var third = EditDocument()
        third.applyFromBatch(PresetValues(bodySkin: BodySkinAdjustments(smoothing: 0.4)))
        XCTAssertEqual(third.recipe.bodySkin.smoothing, 0.4, "일괄 적용도 나른다")
    }

    func testApplyAutoKeepsBodySkin() {
        var document = EditDocument()
        document.set(.bodySkin(.brightness, 0.5))
        let suggestion = AutoEnhanceSuggestion(
            color: ColorAdjustments(exposure: 0.1), detail: DetailAdjustments(), portrait: PortraitAdjustments())
        XCTAssertTrue(document.applyAuto(suggestion))
        XCTAssertEqual(document.recipe.bodySkin.brightness, 0.5, "자동 보정은 몸 피부를 건드리지 않는다")
    }
```

- [ ] **Step 2: 실패 확인**

Run: `cd apple && swift test --filter EditDocumentTests` → 컴파일 실패(`EditChange.bodySkin` 없음).

- [ ] **Step 3: 구현**

`EditChange.swift`: `case backgroundBlur(Double)` 아래에 `case bodySkin(BodySkinKey, Double)`.
`EditingPolicy.swift`: `public static func bodySkinRange(_ key: BodySkinKey) -> ClosedRange<Double> { AdjustmentRange.bodySkin(key) }`(doc "피부 톤만 양방향이다").
`EditDocument.swift`: `set`에 `case .bodySkin(let key, let value): updated.bodySkin[key] = EditingPolicy.clamped(value, to: EditingPolicy.bodySkinRange(key))`. `merged`의 `updated.background = values.background` 아래에 `updated.bodySkin = values.bodySkin`. `applyAuto`의 doc 주석 "건드리지 않는" 목록에 "몸 피부"를 더한다.

- [ ] **Step 4: 통과 확인**

Run: `cd apple && swift test` → Editing `Executed 33 tests`, 0 failures. lint 출력 없음.

- [ ] **Step 5: 커밋**

```bash
git add apple/Sources/MellowEditing/API/EditChange.swift apple/Sources/MellowEditing/API/EditingPolicy.swift apple/Sources/MellowEditing/API/EditDocument.swift apple/Tests/MellowEditingTests/EditDocumentTests.swift
git commit -m "feat(editing): 몸 피부 편집 변경과 프리셋·일괄 복사

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 3: 렌더 기반 — 인물 마스크 분리, ToneShift Cb, 몸 반지름 오버로드, 눈·입 비트맵, 캐시 상한

**Files:**
- Modify: `apple/Sources/MellowRendering/Domain/BackgroundStage.swift`, `FeatureKernels.swift`, `FrequencySeparation.swift`, `FaceRegions.swift`, `RegionMaskCache.swift`
- Test: `apple/Tests/MellowRenderingTests/FeatureStageTests.swift`, `FeatureRegionsTests.swift`, `RegionMaskCacheTests.swift`

**Interfaces:**
- Produces: `BackgroundStage.personMask(_:extent:feather:)`, `ToneShift.blueness`, `FrequencySeparation.smoothed(_:bounds:radii:smoothing:tuning:)`, `FaceRegions.featureMask(faces:…)`, `FaceRegions.skinPolygonUnion(faces:…)`, `RegionMaskCache.entriesPerFacePerResolution = 9`.

설계 근거: 스펙 1.6 몸 피부. 배경 단계의 확대·흐림을 반전 없이 돌려받아 같은 마스크를 쓰고, 기존 `toneShift` 커널에 Cb 가산을 더해 새 커널 없이 톤을 바꾼다. `blueness` 기본 0이라 기존 호출 결과는 바뀌지 않는다.

- [ ] **Step 1: 실패하는 테스트 작성**

`FeatureStageTests.swift`에 추가:

```swift
    func testToneShiftBluenessMovesOnlyChromaAndDefaultsToIdentity() throws {
        let skin = Support.solid(CIColor(red: 0.84, green: 0.66, blue: 0.56), size: 8)
        let before = try Support.grid(skin)
        let cooler = try Support.grid(FeatureKernels.shared.shifted(skin, by: ToneShift(blueness: 0.05), extent: skin.extent))
        let point = CGPoint(x: 4, y: 4)
        XCTAssertGreaterThanOrEqual(Int(cooler.rgba(point)[2]), Int(before.rgba(point)[2]) + 10, "Cb를 더하면 파랑이 오른다")
        XCTAssertEqual(Int(cooler.rgba(point)[0]), Int(before.rgba(point)[0]), accuracy: 1, "빨강은 그대로")
        let same = try Support.grid(FeatureKernels.shared.shifted(skin, by: ToneShift(), extent: skin.extent))
        for channel in 0..<3 {
            XCTAssertEqual(Int(same.rgba(point)[channel]), Int(before.rgba(point)[channel]), accuracy: 1, "기본값은 항등")
        }
    }
```

`FeatureRegionsTests.swift`에 추가:

```swift
    func testFeatureMaskCoversEyesAndLipsOfEveryFaceInOneRaster() throws {
        let synthetic = SyntheticFace.makeFeatures()
        let second = synthetic.face.transformed(scale: 0.5, offset: NormalizedPoint(x: 0.5, y: 0.5))
        let cache = RegionMaskCache()
        let mask = try XCTUnwrap(
            FaceRegions.featureMask(faces: [synthetic.face, second], extent: extent, tuning: tuning, cache: cache))
        let pixels = try Support.grid(mask.image)
        XCTAssertGreaterThan(pixels.red(SyntheticFace.scleraPoint), 200)
        XCTAssertGreaterThan(pixels.red(SyntheticFace.lipPoint), 200)
        XCTAssertGreaterThan(pixels.red(SyntheticFace.mouth), 200, "안쪽 입술(치아)도 덮는다")
        XCTAssertGreaterThan(pixels.red(CGPoint(x: 256 + 200 / 2, y: 256 + 300 / 2)), 200, "두 번째 얼굴의 왼눈")
        XCTAssertEqual(pixels.red(SyntheticFace.cheek), 0)
        XCTAssertEqual(pixels.red(SyntheticFace.forehead), 0)
        XCTAssertEqual(cache.count, 1, "얼굴 수와 관계없이 비트맵 하나")
        XCTAssertNil(FaceRegions.featureMask(faces: [], extent: extent, tuning: tuning, cache: cache))
        XCTAssertNil(
            FaceRegions.featureMask(
                faces: [SyntheticFace.make(landmarks: false).face], extent: extent, tuning: tuning, cache: cache),
            "특징점이 없으면 뺄 것이 없다")
    }

    func testSkinPolygonUnionCoversEveryFaceAndSharesTheSkinRaster() throws {
        let synthetic = SyntheticFace.make()
        let second = synthetic.face.transformed(scale: 0.5, offset: NormalizedPoint(x: 0.5, y: 0.5))
        let cache = RegionMaskCache()
        _ = FaceRegions.skinPolygonRaster(face: synthetic.face, extent: extent, tuning: tuning, cache: cache)
        let union = FaceRegions.skinPolygonUnion(faces: [synthetic.face, second], extent: extent, tuning: tuning, cache: cache)
        let pixels = try Support.grid(union)
        XCTAssertGreaterThan(pixels.red(SyntheticFace.cheek), 200)
        XCTAssertGreaterThan(pixels.red(CGPoint(x: 256 + 180 / 2, y: 256 + 200 / 2)), 200, "두 번째 얼굴의 볼")
        XCTAssertEqual(pixels.red(SyntheticFace.outside), 0)
        XCTAssertEqual(pixels.red(CGPoint(x: 256, y: 24)), 0, "턱 아래 몸은 얼굴 피부가 아니다")
        XCTAssertEqual(cache.count, 2, "얼굴마다 피부 비트맵 하나를 skinMask와 함께 쓴다")
    }
```

`RegionMaskCacheTests.swift`의 `testCapacityGrowsWithFaceCount`에서 `capacity(forFaces: 2)` 기대값 32 → 36, `capacity(forFaces: 3)`·`maximumEntries` 48 → 54로 바꾸고, 주석에 "얼굴당 해상도마다 9(G2: 몸 피부의 눈·입 비트맵)"를 적는다.

`BackgroundStageTests.swift`는 바꾸지 않는다(기존 5개가 그대로 통과해야 한다).

- [ ] **Step 2: 실패 확인**

Run: `cd apple && swift test --filter "FeatureStageTests|FeatureRegionsTests|RegionMaskCacheTests"` → 컴파일 실패(`ToneShift`에 `blueness` 없음).

- [ ] **Step 3: 구현**

`BackgroundStage.swift`: `backgroundMask`를 둘로 나눈다.

```swift
    /// 사람 1·배경 0인 extent 크기 마스크. 인물 마스크를 extent에 맞게 가로·세로 따로 키우고(마스크 비율은 사진과 다를 수 있다) feather로 흐린다.
    static func personMask(_ person: CIImage, extent: CGRect, feather: CGFloat) -> CIImage {
        let source = person.extent
        let placement = CGAffineTransform(translationX: extent.minX, y: extent.minY)
            .scaledBy(x: extent.width / source.width, y: extent.height / source.height)
            .translatedBy(x: -source.minX, y: -source.minY)
        return person.transformed(by: placement).clampedToExtent()
            .applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: feather])
            .cropped(to: extent)
    }

    /// 배경 1·사람 0. personMask의 반전.
    static func backgroundMask(_ person: CIImage, extent: CGRect, feather: CGFloat) -> CIImage {
        personMask(person, extent: extent, feather: feather).applyingFilter("CIColorInvert").cropped(to: extent)
    }
```

`FeatureKernels.swift`: `ToneShift`에 `/// Cb에 더하는 값(양수면 차갑게). var blueness: Double = 0`. 커널 시그니처를 `toneShift(__sample pixel, float lift, float yellowRemoval, float saturation, float redness, float blueness)`로, `cb = (cb - min(cb, 0.0) * yellowRemoval) * saturation + blueness;`로, `shifted`의 인자 배열 끝에 `shift.blueness`를 더한다.

`FrequencySeparation.swift`: 기존 `smoothed(_:bounds:faceWidth:smoothing:tuning:)` 본문을 새 오버로드에 맡긴다.

```swift
    static func smoothed(
        _ image: CIImage, bounds: CGRect, faceWidth: CGFloat, smoothing: Double, tuning: RenderTuning
    ) throws -> CIImage {
        try smoothed(image, bounds: bounds, radii: radii(faceWidth: faceWidth, tuning: tuning), smoothing: smoothing, tuning: tuning)
    }

    /// 반지름을 직접 받는 형태. 몸 피부처럼 얼굴 폭이 없는 영역이 쓴다.
    static func smoothed(
        _ image: CIImage, bounds: CGRect, radii: (fine: Double, mid: Double), smoothing: Double, tuning: RenderTuning
    ) throws -> CIImage {
        let amount = min(1, max(0, smoothing))
        guard amount > 0, !bounds.isEmpty else { return image }
        return try SkinKernels.shared.bandMix(
            image: image, fineBlur: blurred(image, radius: radii.fine), midBlur: blurred(image, radius: radii.mid),
            keep: 1 - amount * tuning.midReductionMax, extent: bounds)
    }
```

`FaceRegions.swift`에 추가(`lipMask` 아래):

```swift
    /// 모든 얼굴의 눈 다각형과 바깥 입술을 한 비트맵에 그려 featureMaskFeather(가장 넓은 얼굴 기준)로 흐린 마스크.
    /// 몸 피부가 눈·입(치아 포함)을 빼는 데 쓴다. 다각형이 하나도 없으면 nil. 얼굴 수와 관계없이 캐시 항목 하나다.
    static func featureMask(faces: [FaceGeometry], extent: CGRect, tuning: RenderTuning, cache: RegionMaskCache? = nil)
        -> RegionMask?
    {
        var fill: [[CGPoint]] = []
        for face in faces {
            fill += eyePolygons(face: face, extent: extent)
            if let lips = landmarkPolygon(face, .outerLips, extent) {
                fill.append(lips)
            }
        }
        guard !fill.isEmpty, let widest = faces.max(by: { $0.boundingBox.width < $1.boundingBox.width }) else {
            return nil
        }
        return featheredPolygonMask(fill: fill, cut: [], face: widest, extent: extent, tuning: tuning, cache: cache)
    }

    /// 얼굴마다 피부 다각형 비트맵(skinMask와 같은 캐시 항목)을 최대로 합친 extent 크기 마스크. 얼굴이 없으면 검정.
    static func skinPolygonUnion(faces: [FaceGeometry], extent: CGRect, tuning: RenderTuning, cache: RegionMaskCache? = nil)
        -> CIImage
    {
        var union = CIImage(color: .black).cropped(to: extent)
        for face in faces {
            union = skinPolygonRaster(face: face, extent: extent, tuning: tuning, cache: cache)
                .applyingFilter("CIMaximumCompositing", parameters: [kCIInputBackgroundImageKey: union])
        }
        return union.cropped(to: extent)
    }
```

`RegionMaskCache.swift`: `entriesPerFacePerResolution`을 9로, 주석을 "피부·눈·입술·치아·아이섀도·왼눈썹·오른눈썹·눈입(몸 피부) 8개에 여유 1"로.

- [ ] **Step 4: 통과 확인**

Run: `cd apple && swift test` → Rendering `Executed 247 tests`, 0 failures(`BackgroundStageTests` 5개 불변 통과). lint 출력 없음.

- [ ] **Step 5: 커밋**

```bash
git add apple/Sources/MellowRendering/Domain/BackgroundStage.swift apple/Sources/MellowRendering/Domain/FeatureKernels.swift apple/Sources/MellowRendering/Domain/FrequencySeparation.swift apple/Sources/MellowRendering/Domain/FaceRegions.swift apple/Sources/MellowRendering/Domain/RegionMaskCache.swift apple/Tests/MellowRenderingTests/FeatureStageTests.swift apple/Tests/MellowRenderingTests/FeatureRegionsTests.swift apple/Tests/MellowRenderingTests/RegionMaskCacheTests.swift
git commit -m "refactor(rendering): 몸 피부 단계가 쓸 인물 마스크·Cb 이동·눈입 비트맵

배경 마스크의 확대·흐림을 반전 없이 돌려주는 personMask로 나누고, ToneShift에 Cb 가산을,
FrequencySeparation에 반지름을 직접 받는 오버로드를 더한다. 캐시 상한은 얼굴당 9.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 4: BodySkinStage — 마스크, 밝기·톤, 매끄럽게, 파이프라인 연결

**Files:**
- Create: `apple/Sources/MellowRendering/Domain/BodySkinStage.swift`
- Modify: `apple/Sources/MellowRendering/API/RenderTuning.swift` (상수 6개), `apple/Sources/MellowRendering/API/RenderPipeline.swift`
- Modify: `apple/Tests/MellowRenderingTests/RenderingTestSupport.swift` (`makeWithBody`), `RenderPipelineTests.swift` (순서 배열)
- Test: `apple/Tests/MellowRenderingTests/BodySkinStageTests.swift`(새 파일)

**Interfaces:**
- Consumes: Task 3 전부, `SkinKernels.chromaWeight`, `FeatureKernels.shifted`, `MaskBuilder.blend`, `FaceRegions.cheekAverages`(G1).
- Produces: `BodySkinStage`(name `"bodySkin"`), `static clamped(_:)`, `static referenceFace(_:) -> FaceGeometry?`, `static bodyRadii(shortSide:tuning:)`.

설계 근거: 스펙 1.6 몸 피부. 합성 얼굴 아래에 피부 질감 사각형(몸)과 회색 사각형(옷)을 두고 64×64 스텁 인물 마스크(사진 x 96…416, y 0…376)로 덮는다. 회색은 피부색 가중치가 정확히 0(Cb·Cr 거리 0.127 > 2σ)이라 바이트가 바뀌지 않는다.

- [ ] **Step 1: 합성 몸과 실패하는 테스트 작성**

`RenderingTestSupport.swift`의 주름 표본 점 extension 아래에 추가:

```swift
/// 합성 얼굴 아래에 몸 피부와 옷을 둔 사진. 몸 피부 단계 테스트용.
extension SyntheticFace {
    /// 턱(y 50) 아래 몸 피부. 피부 질감을 그대로 쓴다.
    static let bodySkinRect = CGRect(x: 156, y: 0, width: 200, height: 48)
    /// 몸 왼쪽 회색 옷. 피부색 가중치가 0이다.
    static let leftShirtRect = CGRect(x: 100, y: 0, width: 56, height: 48)
    static let shirtColor = CIColor(red: 0.5, green: 0.5, blue: 0.5)
    /// 몸 피부 안 분산 측정 패치.
    static let bodyPatch = CGRect(x: 226, y: 4, width: 60, height: 40)
    static let bodySkinPoint = CGPoint(x: 256, y: 24)
    static let shirtPoint = CGPoint(x: 128, y: 24)
    /// 인물 마스크 밖 배경(왼쪽 x < 96, 머리 위 y > 376).
    static let backgroundBesideBody = CGPoint(x: 40, y: 24)
    static let backgroundAboveHead = CGPoint(x: 256, y: 450)
    /// 64×64 스텁 인물 마스크. 사람 사각형 x 12…52, y 0…47 → 사진 x 96…416, y 0…376(얼굴·몸·옷을 덮는다).
    static let bodyPersonMask = RenderingTestSupport.personMask(
        size: CGSize(width: 64, height: 64), person: CGRect(x: 12, y: 0, width: 40, height: 47))

    static func makeWithBody() -> SyntheticFace {
        let base = make()
        var image = RenderingTestSupport.skinTexture(size: size).cropped(to: bodySkinRect).composited(over: base.image)
        image = CIImage(color: shirtColor).cropped(to: leftShirtRect).composited(over: image)
        return SyntheticFace(image: image.cropped(to: extent), face: base.face)
    }
}
```

`apple/Tests/MellowRenderingTests/BodySkinStageTests.swift`:

```swift
import CoreImage
import MellowShared
import XCTest

@testable import MellowRendering

final class BodySkinStageTests: XCTestCase {
    typealias Support = RenderingTestSupport

    private let extent = SyntheticFace.extent
    /// 밝기 1에서 기대하는 최소 빨강 증가와 톤 ±1에서 기대하는 최소 R−B 변화(바이트).
    private static let liftMinimum = 6
    private static let toneMinimum = 10

    private func output(
        _ synthetic: SyntheticFace, _ values: BodySkinAdjustments, faces: [FaceGeometry]? = nil,
        personMask: CIImage? = SyntheticFace.bodyPersonMask, targetFace: Int? = nil
    ) throws -> CIImage {
        var recipe = EditRecipe()
        recipe.bodySkin = values
        recipe.portrait.targetFace = targetFace
        let analysis = PhotoAnalysis(faces: faces ?? [synthetic.face], personMask: personMask)
        let context = RenderContext(extent: extent, recipe: recipe, analysis: analysis, tuning: RenderTuning())
        return try BodySkinStage().apply(synthetic.image, in: context)
    }

    private func gap(_ pixel: [UInt8]) -> Int { Int(pixel[0]) - Int(pixel[2]) }

    func testZeroValuesNoPersonOrNoFaceReturnInputBytes() throws {
        let synthetic = SyntheticFace.makeWithBody()
        let input = try Support.bytes(synthetic.image)
        let full = BodySkinAdjustments(brightness: 1, tone: 1, smoothing: 1)
        XCTAssertTrue(try Support.bytes(output(synthetic, BodySkinAdjustments())) == input, "값 0")
        XCTAssertTrue(try Support.bytes(output(synthetic, full, personMask: nil)) == input, "인물 마스크 없음")
        XCTAssertTrue(try Support.bytes(output(synthetic, full, faces: [])) == input, "얼굴 없음(기준색 없음)")
        XCTAssertEqual(BodySkinStage().name, "bodySkin")
    }

    func testBrightnessLiftsVisibleSkinAndLeavesShirtBackgroundAndEyes() throws {
        let synthetic = SyntheticFace.makeWithBody()
        let before = try Support.grid(synthetic.image)
        let after = try Support.grid(output(synthetic, BodySkinAdjustments(brightness: 1)))
        for point in [SyntheticFace.bodySkinPoint, SyntheticFace.cheek, SyntheticFace.forehead] {
            XCTAssertGreaterThanOrEqual(Int(after.red(point)), Int(before.red(point)) + Self.liftMinimum, "피부 \(point)")
        }
        let untouched = [
            SyntheticFace.shirtPoint, SyntheticFace.backgroundBesideBody, SyntheticFace.backgroundAboveHead,
            SyntheticFace.backgroundInsideContour, SyntheticFace.leftEye, SyntheticFace.mouth, SyntheticFace.outside,
        ]
        for point in untouched {
            XCTAssertEqual(after.rgba(point), before.rgba(point), "피부가 아닌 \(point)")
        }
        let half = try Support.grid(output(synthetic, BodySkinAdjustments(brightness: 0.5)))
        XCTAssertGreaterThan(half.red(SyntheticFace.bodySkinPoint), before.red(SyntheticFace.bodySkinPoint))
        XCTAssertLessThan(half.red(SyntheticFace.bodySkinPoint), after.red(SyntheticFace.bodySkinPoint))
    }

    func testToneWarmsOrCoolsSkinOnly() throws {
        let synthetic = SyntheticFace.makeWithBody()
        let before = try Support.grid(synthetic.image)
        let warm = try Support.grid(output(synthetic, BodySkinAdjustments(tone: 1)))
        let cool = try Support.grid(output(synthetic, BodySkinAdjustments(tone: -1)))
        for point in [SyntheticFace.bodySkinPoint, SyntheticFace.cheek] {
            XCTAssertGreaterThanOrEqual(gap(warm.rgba(point)), gap(before.rgba(point)) + Self.toneMinimum, "따뜻하게 \(point)")
            XCTAssertLessThanOrEqual(gap(cool.rgba(point)), gap(before.rgba(point)) - Self.toneMinimum, "차갑게 \(point)")
        }
        for point in [SyntheticFace.shirtPoint, SyntheticFace.leftEye, SyntheticFace.outside] {
            XCTAssertEqual(warm.rgba(point), before.rgba(point), "\(point)")
            XCTAssertEqual(cool.rgba(point), before.rgba(point), "\(point)")
        }
    }

    func testSmoothingSkipsTheFaceAndSmoothsBodySkin() throws {
        let synthetic = SyntheticFace.makeWithBody()
        let image = synthetic.image
        let result = try output(synthetic, BodySkinAdjustments(smoothing: 1))
        let radii = BodySkinStage.bodyRadii(shortSide: extent.width, tuning: RenderTuning())
        let before = try Support.bandVariances(image, in: SyntheticFace.bodyPatch, fineRadius: radii.fine, midRadius: radii.mid)
        let after = try Support.bandVariances(result, in: SyntheticFace.bodyPatch, fineRadius: radii.fine, midRadius: radii.mid)
        XCTAssertLessThan(after.mid, before.mid * 0.6, "몸 얼룩 대역이 준다")
        XCTAssertEqual(after.fine / before.fine, 1, accuracy: 0.1, "몸 모공 대역은 ±10% 안")
        let beforeGrid = try Support.grid(image)
        let afterGrid = try Support.grid(result)
        let patch = SyntheticFace.skinPatch
        for y in stride(from: Int(patch.minY), to: Int(patch.maxY), by: 10) {
            for x in stride(from: Int(patch.minX), to: Int(patch.maxX), by: 10) {
                let point = CGPoint(x: x, y: y)
                XCTAssertEqual(afterGrid.rgba(point), beforeGrid.rgba(point), "얼굴 피부 \(point)는 얼굴 슬라이더 몫")
            }
        }
        for point in [SyntheticFace.shirtPoint, SyntheticFace.backgroundBesideBody, SyntheticFace.leftEye] {
            XCTAssertEqual(afterGrid.rgba(point), beforeGrid.rgba(point), "\(point)")
        }
    }

    func testOutOfRangeValuesRenderClamped() throws {
        let synthetic = SyntheticFace.makeWithBody()
        XCTAssertTrue(
            try Support.bytes(output(synthetic, BodySkinAdjustments(brightness: 3, tone: -5, smoothing: 2)))
                == Support.bytes(output(synthetic, BodySkinAdjustments(brightness: 1, tone: -1, smoothing: 1))))
        XCTAssertTrue(
            try Support.bytes(output(synthetic, BodySkinAdjustments(brightness: -1))) == Support.bytes(synthetic.image),
            "밝기 음수는 0")
        XCTAssertEqual(
            BodySkinStage.clamped(BodySkinAdjustments(brightness: 2, tone: 3, smoothing: -1)),
            BodySkinAdjustments(brightness: 1, tone: 1))
    }

    func testBodySkinIgnoresTargetFaceAndUsesTheLargestFace() throws {
        let synthetic = SyntheticFace.makeWithBody()
        let small = synthetic.face.transformed(scale: 0.3, offset: NormalizedPoint(x: 0.65, y: 0.6))
        let bright = BodySkinAdjustments(brightness: 1)
        let plain = try Support.bytes(output(synthetic, bright))
        XCTAssertTrue(try Support.bytes(output(synthetic, bright, targetFace: 7)) == plain, "범위 밖 대상 얼굴도 동작")
        XCTAssertTrue(try Support.bytes(output(synthetic, bright, faces: [small, synthetic.face])) == plain, "기준은 가장 큰 얼굴")
        XCTAssertEqual(BodySkinStage.referenceFace([small, synthetic.face])?.boundingBox, synthetic.face.boundingBox)
        XCTAssertNil(BodySkinStage.referenceFace([]))
    }

    func testBodySkinMasksShareFaceRastersAndAddOneEntry() throws {
        let synthetic = SyntheticFace.makeWithBody()
        var recipe = EditRecipe()
        recipe.bodySkin = BodySkinAdjustments(brightness: 0.5, smoothing: 0.5)
        let analysis = PhotoAnalysis(faces: [synthetic.face], personMask: SyntheticFace.bodyPersonMask)
        let context = RenderContext(extent: extent, recipe: recipe, analysis: analysis, tuning: RenderTuning())
        let first = try Support.bytes(BodySkinStage().apply(synthetic.image, in: context))
        let second = try Support.bytes(BodySkinStage().apply(synthetic.image, in: context))
        XCTAssertEqual(analysis.regionMasks.count, 2, "눈·입 비트맵 하나 + 피부 다각형(skinMask와 공유) 하나")
        XCTAssertTrue(first == second)
    }
}
```

`RenderPipelineTests.swift`의 `testStageOrderMatters` 배열을 `["skin", "bodySkin", "feature", "makeup", "background", "shapeWarp", "localEdit", "geometry", "color", "detail", "look"]`로 바꾼다.

- [ ] **Step 2: 실패 확인**

Run: `cd apple && swift test --filter "BodySkinStageTests|RenderPipelineTests"` → 컴파일 실패(`BodySkinStage` 없음).

- [ ] **Step 3: 구현**

`RenderTuning.swift`의 `backgroundMaskFeather` 아래:

```swift
    /// 몸 피부의 피부색 거리 기준. 얼굴(skinChromaSigma 0.04)보다 넓다. 몸은 얼굴과 조명이 달라 색이 더 흩어진다.
    public var bodySkinChromaSigma: Double = 0.05
    /// 몸 피부가 쓰는 인물 마스크 흐림. 짧은 변 비율. 배경 흐림(0.006)보다 조금 좁게 둬 옷깃으로 덜 번진다.
    public var bodySkinMaskFeather: Double = 0.004
    /// 피부 밝기 1에서 흰색 쪽으로 섞는 비율(sRGB 감마 값). Evoto 전후 측정(+0.066)에 가깝다.
    public var bodySkinLiftMax: Double = 0.2
    /// 피부 톤 ±1에서 감마 Cr에 더하고 Cb에서 빼는 값(따뜻). 음수는 반대.
    public var bodySkinToneMax: Double = 0.025
    /// 몸 모공 대역의 위쪽 경계 반지름. 짧은 변 비율(1200px에서 2.4px).
    public var bodySkinFineBandFraction: Double = 0.002
    /// 몸 얼룩 대역의 위쪽 경계 반지름. 짧은 변 비율(1200px에서 14px).
    public var bodySkinMidBandFraction: Double = 0.012
```

`apple/Sources/MellowRendering/Domain/BodySkinStage.swift`:

```swift
import CoreImage
import MellowShared

/// 보이는 피부 전체(얼굴 포함)의 밝기·톤과 얼굴 밖 피부의 매끄럽게. 마스크 = 인물 마스크 × 가장 큰 얼굴의 볼 기준 피부색 가중치
/// × (1 − 모든 얼굴의 눈·입). 매끄럽게는 거기서 얼굴 피부 다각형을 뺀다. 인물 마스크나 얼굴이 없으면 입력 그대로(오류 아님).
/// 값은 AdjustmentRange로 직접 자른다. 대상 얼굴 선택과 무관하다.
struct BodySkinStage: RenderStage {
    let name = "bodySkin"

    func apply(_ image: CIImage, in context: RenderContext) throws -> CIImage {
        let values = Self.clamped(context.recipe.bodySkin)
        guard values.hasEffect, let person = context.personMask, !person.extent.isEmpty, !person.extent.isInfinite,
            let reference = Self.referenceFace(context.faces)
        else { return image }
        let extent = context.extent
        let tuning = context.tuning
        let encoded = image.applyingFilter("CILinearToSRGBToneCurve")
        guard let cheeks = FaceRegions.cheekAverages(of: encoded, face: reference, extent: extent) else { return image }
        let feather = max(
            CGFloat(tuning.skinBlurMinimumRadius), context.shortSide * CGFloat(tuning.bodySkinMaskFeather))
        let area = BackgroundStage.personMask(person, extent: extent, feather: feather)
        let chroma = try SkinKernels.shared.chromaWeight(
            of: encoded, left: cheeks.left, right: cheeks.right, sigma: tuning.bodySkinChromaSigma, extent: extent)
        var toneMask = Self.product(area, chroma, extent: extent)
        if let features = FaceRegions.featureMask(
            faces: context.faces, extent: extent, tuning: tuning, cache: context.regionMasks)
        {
            toneMask = Self.product(toneMask, Self.inverted(features.image, extent: extent), extent: extent)
        }
        var result = image
        if values.smoothing > 0 {
            let faceSkin = FaceRegions.skinPolygonUnion(
                faces: context.faces, extent: extent, tuning: tuning, cache: context.regionMasks)
            let smoothMask = Self.product(toneMask, Self.inverted(faceSkin, extent: extent), extent: extent)
            let smooth = try FrequencySeparation.smoothed(
                result, bounds: extent, radii: Self.bodyRadii(shortSide: context.shortSide, tuning: tuning),
                smoothing: values.smoothing, tuning: tuning)
            result = MaskBuilder.blend(smooth, over: result, mask: smoothMask).cropped(to: extent)
        }
        if values.brightness > 0 || values.tone != 0 {
            let shift = ToneShift(
                lift: values.brightness * tuning.bodySkinLiftMax, blueness: -values.tone * tuning.bodySkinToneMax,
                redness: values.tone * tuning.bodySkinToneMax)
            let shifted = try FeatureKernels.shared.shifted(result, by: shift, extent: extent)
            result = MaskBuilder.blend(shifted, over: result, mask: toneMask).cropped(to: extent)
        }
        return result
    }

    /// 밝기·매끄럽게 0…1, 톤 −1…1. 유한하지 않은 값은 RenderPipeline이 먼저 거절한다.
    static func clamped(_ values: BodySkinAdjustments) -> BodySkinAdjustments {
        var copy = values
        for key in BodySkinKey.allCases {
            copy[key] = AdjustmentRange.clamped(values[key], to: AdjustmentRange.bodySkin(key))
        }
        return copy
    }

    /// 기준색을 재는 얼굴. 상자 폭이 가장 큰 얼굴이고 없으면 nil.
    static func referenceFace(_ faces: [FaceGeometry]) -> FaceGeometry? {
        faces.max { $0.boundingBox.width < $1.boundingBox.width }
    }

    /// 몸 피부 대역 반지름. 얼굴 폭 대신 짧은 변에 비례한다.
    static func bodyRadii(shortSide: CGFloat, tuning: RenderTuning) -> (fine: Double, mid: Double) {
        let fine = max(tuning.skinBlurMinimumRadius, Double(shortSide) * tuning.bodySkinFineBandFraction)
        let mid = max(fine, Double(shortSide) * tuning.bodySkinMidBandFraction)
        return (fine, mid)
    }

    /// 두 회색 마스크의 곱. 둘 다 extent 밖이 비어 있을 수 있어 검정 위에 얹는다.
    private static func product(_ a: CIImage, _ b: CIImage, extent: CGRect) -> CIImage {
        let black = CIImage(color: .black).cropped(to: extent)
        let background = b.composited(over: black)
        return a.composited(over: black)
            .applyingFilter("CIMultiplyCompositing", parameters: [kCIInputBackgroundImageKey: background])
            .cropped(to: extent)
    }

    /// 1 − mask. extent 밖이 비어 있으면(검정) 1이 된다.
    private static func inverted(_ mask: CIImage, extent: CGRect) -> CIImage {
        mask.composited(over: CIImage(color: .black).cropped(to: extent)).applyingFilter("CIColorInvert")
            .cropped(to: extent)
    }
}
```

`ToneShift`의 memberwise init은 선언 순서(`lift, yellowRemoval, saturation, redness, blueness`)를 따르므로 위 호출은 인자 이름을 그 순서대로 쓴다(`lift:blueness:redness:` 순서가 틀리면 컴파일 오류 — `lift:` 다음 `redness:` 다음 `blueness:` 순서로 고친다).

`RenderPipeline.swift`: `standard`의 `SkinStage(), FeatureStage(), …`를 `SkinStage(), BodySkinStage(), FeatureStage(), …`로, doc 주석의 단계 목록에 몸 피부를 더한다.

- [ ] **Step 4: 통과 확인**

Run: `cd apple && swift test` → Rendering `Executed 253 tests`, 0 failures. 기존 `PhotoPipelineTests`·`RenderPipelineTests.testIdentityRecipeLeavesBytesUntouched`가 그대로 통과(값 0이면 항등). lint 출력 없음. `./scripts/verify-modules.sh` 통과.

- [ ] **Step 5: 커밋**

```bash
git add apple/Sources/MellowRendering/Domain/BodySkinStage.swift apple/Sources/MellowRendering/API/RenderTuning.swift apple/Sources/MellowRendering/API/RenderPipeline.swift apple/Tests/MellowRenderingTests/RenderingTestSupport.swift apple/Tests/MellowRenderingTests/RenderPipelineTests.swift apple/Tests/MellowRenderingTests/BodySkinStageTests.swift
git commit -m "feat(rendering): 몸 피부 단계 — 보이는 피부 전체의 밝기·톤·매끄럽게

skin 뒤 새 단계 bodySkin. 인물 마스크 × 가장 큰 얼굴의 볼 기준 피부색 가중치 − 눈·입 안에서
밝기·톤을 바꾸고, 얼굴 피부 다각형을 뺀 몸 피부만 주파수 분리로 매끄럽게 한다.
인물 마스크나 얼굴이 없으면 건너뛴다.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 5: 앱 — 뷰티 피부톤 탭, 사람 없음 규칙, 문구, 시나리오

**Files:**
- Modify: `apple/MellowPhoto/Application/BeautyTab.swift`, `AppModel.swift`, `UserMessage.swift`
- Modify: `apple/MellowPhoto/Features/Editor/BeautyPanel.swift`
- Test: `apple/MellowPhotoTests/AppModelTests.swift`, `apple/MellowPhotoTests/EditorScenarioTests.swift`

**Interfaces:**
- Produces: `BeautyTab.skinTone`, `AppModel.canAdjustBodySkin(_:)`, `UserMessage.beautyTabSkinTone`·`bodySkinTitle(_:)`·`bodySkinHint`·`bodySkinNoPersonHint`.

설계 근거: 스펙 1.9. 얼굴 없음·분석 실패는 `BeautyPanel`의 기존 분기가 먼저 막고, 사람 없음은 `backgroundAvailability`로 안내한다. 슬라이더 켜짐 규칙은 배경 흐림과 같다(드래그 중·ready·값이 0이 아니면 켬).

- [ ] **Step 1: 실패하는 테스트 작성**

`AppModelTests.swift`에 추가:

```swift
    func testSkinToneTabEditsEveryKeyOneUndoStepEachWhenPersonFound() async throws {
        let staged = try TestSupport.solidPNG(in: root)
        let face = TestSupport.landmarkedFace(in: NormalizedRect(x: 0.2, y: 0.3, width: 0.6, height: 0.6))
        let mask = TestSupport.personMask(NormalizedRect(x: 0.1, y: 0, width: 0.8, height: 0.95))
        let model = TestSupport.makeModel(
            root: root, analyzer: StubFaceAnalyzer(result: .success([face])),
            personAnalyzer: StubPersonAnalyzer(result: .success(mask)),
            importer: FakeImporter(staged: [.success(StagedPhoto(url: staged, displayName: nil))]))
        try await importOne(model, staged)
        model.selectTool(.beauty)
        model.beautyTab = .skinTone
        XCTAssertEqual(BeautyTab.allCases.count, 4)
        XCTAssertEqual(BeautyTab.skinTone.title, "피부톤")
        XCTAssertEqual(model.backgroundAvailability, .ready)
        for key in BodySkinKey.allCases {
            XCTAssertTrue(model.canAdjustBodySkin(key), "\(key)")
        }
        for (offset, key) in BodySkinKey.allCases.enumerated() {
            model.beginSliderEdit()
            model.edit(.bodySkin(key, 0.2))
            model.edit(.bodySkin(key, key == .tone ? -0.4 : 0.7))
            model.endSliderEdit()
            XCTAssertEqual(model.session.selected?.document.undoStack.count, offset + 1, "\(key) 드래그 한 번이 한 단계")
        }
        XCTAssertEqual(model.currentRecipe.bodySkin, BodySkinAdjustments(brightness: 0.7, tone: -0.4, smoothing: 0.7))
        try await waitUntil { !model.isRendering }
        XCTAssertNil(model.presentedError)
        XCTAssertEqual(BodySkinKey.allCases.map(UserMessage.bodySkinTitle), ["피부 밝기", "피부 톤", "바디 피부 매끄럽게"])
        model.selectTool(.adjust)
        model.selectTool(.beauty)
        XCTAssertEqual(model.beautyTab, .skinTone, "탭은 도구를 바꿔도 유지")
    }

    func testSkinToneSlidersFollowPersonAvailabilityAndPresetValues() async throws {
        let staged = try TestSupport.solidPNG(in: root)
        let face = FaceGeometry(boundingBox: NormalizedRect(x: 0.2, y: 0.2, width: 0.6, height: 0.6))
        let model = TestSupport.makeModel(
            root: root, analyzer: StubFaceAnalyzer(result: .success([face])),
            importer: FakeImporter(staged: [.success(StagedPhoto(url: staged, displayName: nil))]))
        try await importOne(model, staged)
        XCTAssertEqual(model.backgroundAvailability, .noPerson)
        XCTAssertFalse(model.canAdjustBodySkin(.brightness), "사람이 없으면 끈다")
        model.applyPreset(PresetValues(bodySkin: BodySkinAdjustments(brightness: 0.4)))
        XCTAssertTrue(model.canAdjustBodySkin(.brightness), "프리셋으로 들어온 값은 0으로 되돌릴 수 있다")
        XCTAssertFalse(model.canAdjustBodySkin(.tone), "0인 항목은 계속 끈다")
        try await waitUntil { !model.isRendering }
        XCTAssertNil(model.presentedError, "사람이 없으면 몸 피부만 건너뛰고 오류를 띄우지 않는다")
        model.beginSliderEdit()
        model.edit(.bodySkin(.brightness, 0))
        XCTAssertTrue(model.canAdjustBodySkin(.brightness), "드래그 중에는 0에 닿아도 끄지 않는다")
        model.endSliderEdit()
        XCTAssertFalse(model.canAdjustBodySkin(.brightness))
    }
```

`EditorScenarioTests.swift`의 B~F 시나리오에서 `let refined = previewBytes(model)`(G1) 뒤에 추가하고, 그다음 얼굴 단계의 비교 기준을 `toned`로 바꾼다:

```swift
        model.beautyTab = .skinTone
        XCTAssertTrue(model.canAdjustBodySkin(.brightness))
        model.beginSliderEdit()
        model.edit(.bodySkin(.brightness, 0.6))
        model.endSliderEdit()
        // 몸 피부 밝기만 바꿔도 미리보기가 바뀌어야 한다(스텁 인물 마스크가 얼굴을 덮는다).
        try await waitUntil { !model.isRendering && self.previewBytes(model) != refined }
        let toned = previewBytes(model)
```

마지막 레시피 검증에 `XCTAssertEqual(recipe.bodySkin, BodySkinAdjustments(brightness: 0.6))`를 더한다.

- [ ] **Step 2: 실패 확인**

Run: Mac 앱 테스트 명령 → 컴파일 실패(`BeautyTab`에 `skinTone` 없음).

- [ ] **Step 3: 구현**

`BeautyTab.swift`: `case features` 아래에 `case skinTone`, `title`에 `case .skinTone: return UserMessage.beautyTabSkinTone`.

`UserMessage.swift`: `beautyTabFeatures` 아래에

```swift
    static let beautyTabSkinTone = "피부톤"
    static let bodySkinHint = "얼굴·목·팔처럼 보이는 피부 전체에 적용돼요. 기준 피부색은 가장 큰 얼굴의 볼에서 읽고, 옷과 배경은 그대로 둬요. 피부 톤은 가운데가 원래 색이에요."
    static let bodySkinNoPersonHint = "피부 밝기·톤·바디 매끄럽게는 사람 영역을 찾은 사진에서 동작해요."
```

`featureTitle(_:)` 아래에:

```swift
    /// 뷰티 › 피부톤 탭 슬라이더 이름. 화면 순서는 BodySkinKey.allCases.
    static func bodySkinTitle(_ key: BodySkinKey) -> String {
        switch key {
        case .brightness: return "피부 밝기"
        case .tone: return "피부 톤"
        case .smoothing: return "바디 피부 매끄럽게"
        }
    }
```

`AppModel.swift`의 `canAdjustBackgroundBlur` 아래에:

```swift
    /// 피부톤 슬라이더를 움직일 수 있는지. 배경 흐림과 같은 인물 마스크 규칙이다(드래그 중·사람 있음·0이 아닌 값).
    func canAdjustBodySkin(_ key: BodySkinKey) -> Bool {
        isSliderEditActive || backgroundAvailability == .ready || currentRecipe.bodySkin[key] != 0
    }
```

`BeautyPanel.swift`: `switch model.beautyTab`에 `case .skinTone: skinToneControls(recipe.bodySkin)`를 더하고 함수를 추가한다.

```swift
    /// 보이는 피부 전체의 밝기·톤·매끄럽게. 사람이 없으면 안내를 보이고 슬라이더는 배경 흐림과 같은 규칙으로 끈다.
    @ViewBuilder
    private func skinToneControls(_ bodySkin: BodySkinAdjustments) -> some View {
        switch model.backgroundAvailability {
        case .ready:
            EmptyView()
        case .noPerson:
            Label(UserMessage.noPersonDetected, systemImage: "person.crop.rectangle.badge.questionmark")
            Text(UserMessage.bodySkinNoPersonHint).font(.caption).foregroundStyle(.secondary)
        case .unavailable(let failure):
            Label(UserMessage.personAnalysisUnavailableTitle, systemImage: "exclamationmark.triangle")
            Text(UserMessage.text(for: failure)).font(.caption).foregroundStyle(.secondary)
        }
        ForEach(BodySkinKey.allCases, id: \.self) { key in
            let range = EditingPolicy.bodySkinRange(key)
            AdjustmentSlider(
                title: UserMessage.bodySkinTitle(key), value: bodySkin[key], range: range,
                snapsToZero: range.lowerBound < 0
            ) { .bodySkin(key, $0) }
            .disabled(!model.canAdjustBodySkin(key))
        }
        Text(UserMessage.bodySkinHint).font(.caption).foregroundStyle(.secondary)
    }
```

- [ ] **Step 4: 통과 확인**

Run: `cd apple && swift test` → 패키지 367(Shared 47 · Rendering 253 · Library 30 · Export 4 · Editing 33), 0 failures. Mac 앱 테스트 → `Executed 74 tests, with 0 failures`. lint 출력 없음. `./scripts/verify-modules.sh` 통과. `cd apple && xcodegen generate --quiet && git diff --exit-code --stat MellowPhoto.xcodeproj` → 출력 없음.

- [ ] **Step 5: 커밋**

```bash
git add apple/MellowPhoto/Application/BeautyTab.swift apple/MellowPhoto/Application/AppModel.swift apple/MellowPhoto/Application/UserMessage.swift apple/MellowPhoto/Features/Editor/BeautyPanel.swift apple/MellowPhotoTests/AppModelTests.swift apple/MellowPhotoTests/EditorScenarioTests.swift
git commit -m "feat(app): 뷰티 피부톤 탭 — 피부 밝기·톤·바디 피부 매끄럽게

사람 영역을 찾지 못하면 안내를 보이고 배경 흐림과 같은 규칙으로 슬라이더를 끈다.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

## 자체 검토 결과

- **스펙 대조:** §1.1 → `BodySkinKey`·`BodySkinAdjustments`(Task 1), `EditChange.bodySkin`(Task 2), `BodySkinStage`(Task 4), `ToneShift.blueness`(Task 3), `BeautyTab.skinTone`(Task 5), 새 import 없음. §1.2 → `bodySkin` 그룹·범위·`dependsOnPerson`·`PresetValues`·두 스키마·README(Task 1). §1.3 → `bodySkin`을 `skin` 뒤(Task 4, 순서 배열 갱신). §1.4 → 기준 얼굴 = 가장 넓은 얼굴(Task 4). §1.6 몸 피부 → 마스크 식·`personMask` 분리·`featureMask`·`skinPolygonUnion`·반지름 오버로드·적용 순서·상수 6개(Task 3·4), 캐시 상한 9(Task 3). §1.9 → 피부톤 탭·안내·켜짐 규칙·문구(Task 5). §1.10 → 프리셋·일괄·자동 보정(Task 2). §2 → 항등(Task 4), 마스크 밖 불변(옷·배경·눈, Task 4), 클램프(Task 4), 얼굴 없음·사람 없음 건너뜀(Task 4·5), 대상 얼굴 무관(Task 4), 얼굴 피부 제외(Task 4), 회귀(배경 테스트 불변, Task 3), 앱·시나리오(Task 5). §4 → Task 목록이 표와 같다.
- **타입 일관성:** `BodySkinAdjustments.subscript`·`numericValues`·`hasEffect`, `AdjustmentRange.bodySkin`, `EditingPolicy.bodySkinRange`, `BackgroundStage.personMask`, `ToneShift.blueness`(memberwise 순서 `lift, yellowRemoval, saturation, redness, blueness`), `FrequencySeparation.smoothed(radii:)`, `FaceRegions.featureMask`·`skinPolygonUnion`, `BodySkinStage.clamped`·`referenceFace`·`bodyRadii`, `SyntheticFace.makeWithBody`와 표본 점, `AppModel.canAdjustBodySkin`, `UserMessage.bodySkinTitle` 등을 정의한 Task와 쓰는 Task에서 같게 썼다. 테스트 수: 패키지 354 → 356 → 358 → 361 → 367 → 367, 앱 Mac 72 → 74.
- **Review Focus 매핑:** 1→Task 4·5, 2→Task 4·5, 3→Task 4, 4→Task 4, 5→Task 4, 6→Task 1. 모두 테스트 코드가 있다.
- **플레이스홀더 점검:** "TBD/TODO/나중에" 없음. `ToneShift` 인자 순서 주의를 Task 4에 적었다.
