# 인물 보정 G3 효과·작업 흐름 구현 계획

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 조정 패널에 그레인·글로우를, "전체 사진에 적용"에 무엇을 복사할지 고르는 동기화 항목 메뉴를, 동작 줄에 기존 "원본 비교" 토글 옆 분할 비교(드래그 분할선)를 더하고, G 전체의 문서·검증 기록을 마친다.

**Architecture:** MellowShared에 최상위 레시피 그룹 `effects`(그레인·글로우)를 더하고 MellowRendering은 `look` 뒤 마지막 단계 `effect`(`CIBloom` → 회색 잡음 오버레이)를 둔다. 선택 동기화는 MellowEditing의 `SyncCategory`와 `EditDocument.applyFromBatch(_:categories:)`가 규칙을 갖고, MellowLibrary `ProjectSession.applyToAll(from:categories:)`가 넘기며, 앱은 세션 상태 `syncCategories`와 톱니 메뉴를 둔다. 비교는 `AppModel.CompareMode { off, full, split }`로 묶되 기존 `isComparing`(전체 토글)은 계산 속성으로 남겨 호출부·테스트가 바뀌지 않고, 분할은 캔버스 위에 원본을 왼쪽만 보이게 얹고 분할선을 드래그한다.

**Tech Stack:** Swift 5.9 tools / Swift 5 언어 모드, SwiftUI + Observation, Core Image(CIBloom·CIRandomGenerator·CIColorMatrix·CIOverlayBlendMode·CILinearToSRGBToneCurve), XCTest, XcodeGen 2.46.0.

**Spec:** `docs/superpowers/specs/2026-10-20-beauty-g-evoto-design.md` (G3에 해당하는 절: 1.1, 1.2, 1.3, 1.6의 효과, 1.7, 1.8, 1.9, 1.10, 2, 3, 4). 선행: G1·G2 계획 전부 머지.

## 사람이 확인할 것

- **순서.** Task 1~2 레시피·편집 규칙 → 3 효과 단계 → 4 조정 패널 효과 → 5 선택 동기화 규칙(편집·라이브러리) → 6 동기화 메뉴 → 7 분할 비교 → 8 문서·VALIDATION·전체 검증. 8개 Task, Task마다 Opus 구현 → 리뷰 → 수정, 끝에 전체 리뷰.
- **외부 효과가 있는 단계.** 없음. Task 8은 문서와 검증 기록만 커밋한다. 푸시·태그·TestFlight·릴리스 노트는 G 범위 밖이다.
- **스펙이 정하지 않아 이 계획이 정한 것.**

| 결정 | 이유 | 바꾸면 비용 |
|---|---|---|
| 그레인 층은 `0.5 ± 진폭/2`의 회색 잡음이고 sRGB 감마 공간에서 오버레이 | 회색 0.5 오버레이는 항등이라 강도 0이 정확히 항등이고, 감마에서 얹어야 어두운 곳과 밝은 곳의 알갱이가 비슷하게 보임 | 작음 |
| 글로우는 `CIBloom` 하나, 반지름은 짧은 변 비례 | 기본 필터만으로 되고 미리보기·저장본이 같아 보임 | 작음 |
| 동기화 선택이 비면 "전체 사진에 적용" 버튼을 끄고 적용도 하지 않음 | 아무것도 복사하지 않는 적용은 실행 취소 단계만 남김 | 작음 |
| 동기화 메뉴 항목 이름: 색감·디테일, 효과, 피부, 얼굴형, 눈·입, 메이크업, 배경, 체형, 피부톤 | 도구·탭 이름과 같은 말을 씀 | 작음 |
| 분할선은 캔버스 좌표계(`coordinateSpace`)로 드래그 위치를 받아 0…1로 자르고, 분할을 끄고 켜도 마지막 위치를 기억(사진을 바꾸면 모드만 꺼짐) | 손잡이 자체 좌표로 받으면 손을 뗐다 다시 잡을 때 튐 | 작음 |
| 전체 토글과 분할은 모드 하나라 한쪽을 켜면 다른 쪽이 꺼짐 | 두 겹을 동시에 보일 이유가 없음 | 작음 |
| 세션 상태인 동기화 선택은 파일에 저장하지 않음(앱을 다시 열면 전부) | 스펙 결정. 세션 스키마 불변 | 작음 |

- **범위 밖.** 동기화 선택 영속화, 그레인 색 잡음·크기 슬라이더, 1.3.0 릴리스 노트·배포.
- **위험.** 그레인은 미리보기(1600px)와 저장본(원본)에서 알갱이 크기를 비례시키지만 확대해 보면 모양이 다르다. 분할선 손잡이가 iPhone에서 자르기 손잡이·브러시 제스처와 겹치지 않도록 비교 중에는 다른 제스처를 막는다. 보정 품질과 손잡이 조작감은 자동 테스트로 판정할 수 없다.
- **사용자 조치.** Task 8이 끝나면 실제 사진으로 G 전체(피부 정밀 6종·피부톤 3종·효과 2종·동기화 메뉴·분할 비교)를 확인하고 VALIDATION의 미검증 항목을 보며 피드백.

---

## 에이전트 참조

## Global Constraints

G1 계획의 Global Constraints를 그대로 따른다(worktree `.claude/worktrees/beauty-g`, 브랜치 `beauty-g-evoto`, `DEVELOPER_DIR`, 모듈 표 불변, lint, 커밋 서명, `PhotoPickerButton.swift`·`project.yml`·`scripts/test-apple.sh`·UI 테스트 타깃은 건드리지 않음). 이 계획에서 다른 것:

- 파이프라인 단계 이름 순서는 Task 3부터 `skin, bodySkin, feature, makeup, background, shapeWarp, localEdit, geometry, color, detail, look, effect`(스펙 1.3).
- 레시피: 최상위 `effects` 추가(키 추가만, schemaVersion 2). `effects.*`는 `AdjustmentRange.unit`. `dependsOn*`에는 넣지 않는다(분석 불필요).
- `RenderTuning` 새 상수 시작값(Task 3): grainMaxAmplitude 0.12, grainSizeFraction 0.0012, glowRadiusFraction 0.02, glowMaxIntensity 0.6. 앱 상수(Task 7): `AppModel.Policy.compareSplitDefault` 0.5, `compareSplitRange` 0...1, `Theme.compareDividerWidth` 2, `compareHandleSize` 28, `Theme.canvasCoordinateSpace` "canvas".
- 새 CIKL 커널 없음. 새 빌드 경고 없음.
- 앱 파일을 더하는 Task는 6(`SyncMenu.swift`)과 7(`CompareDivider.swift`)이며 그 두 Task만 `cd apple && xcodegen generate --quiet`를 돌리고 `apple/MellowPhoto.xcodeproj`를 함께 커밋한다(`project.yml`은 `MellowPhoto/` 폴더 전체를 소스로 잡으므로 고치지 않는다). 새 테스트 파일 `CompareDividerTests.swift`도 같은 규칙(테스트 타깃은 `MellowPhotoTests/` 폴더 전체).
- iOS 시뮬레이터 테스트는 Task 8의 `MELLOW_IOS_TESTS=1 ./scripts/test-apple.sh` 한 번에서만 돌린다. 직접 부팅하지 않은 시뮬레이터를 끄지 않는다. Xcode를 열거나 앱을 띄우지 않는다.
- 기존 `isComparing` 토글 동작과 그것을 쓰는 테스트는 바꾸지 않는다(스펙 1.8).
- 기준 테스트 수(G2 끝): 패키지 367(Shared 47 · Rendering 253 · Library 30 · Export 4 · Editing 33), 앱 Mac 74. 목표: 패키지 377(Shared 49 · Rendering 257 · Library 31 · Export 4 · Editing 36), 앱 Mac 78.

## Review Focus

1. **그레인을 켠 채 같은 사진을 두 번 렌더하고, 미리보기와 저장본을 만든다.** 두 렌더의 바이트가 같아야 하고(결정적), 저장이 성공해야 한다. → Task 3 `testGrainIsDeterministicAndKeepsMeanBrightness`, Task 8 시나리오.
2. **자르기·회전한 사진에 그레인을 건다.** 기하 뒤 extent(원점이 0이 아닐 수 있음)에 맞춰야 하고 가장자리가 비거나 투명해지지 않아야 한다. → Task 3 `testEffectsFollowTheCurrentExtentAfterGeometry`.
3. **동기화 항목을 색감만 켜고 적용한다.** 다른 사진의 피부·얼굴형·대상 얼굴이 그대로여야 한다(얼굴 의존 항목이 없으면 대상 얼굴 유지). → Task 5 `testBatchCopiesOnlyChosenCategoriesAndKeepsTargetFaceWithoutFaceCategories`, Task 6 `testApplyToAllCopiesOnlyChosenCategories`.
4. **잠긴 사진에 얼굴형만 동기화한다.** 아무것도 바뀌지 않아야 한다(잠금 규칙 유지). → Task 5 같은 테스트.
5. **분할 비교 중에 잡티 도구로 캔버스를 누르거나, 전체 토글을 켠다.** 탭은 무시되고 모드는 전체로 바뀌며 사진을 바꾸면 꺼진다. 기존 전체 토글만 쓰는 흐름은 바뀌지 않는다. → Task 7 `testSplitCompareIsAModeBesideTheFullToggleAndResetsOnSelect`.
6. **G 이전 세션·프리셋.** `effects`가 없어도 기본값으로 읽힌다. → Task 1 `testEffectsRoundTripDefaultsAndNeedNoAnalysis`.

## 인터페이스 요약 (모든 Task가 공유하는 이름)

```swift
// MellowShared (Task 1)
public enum EffectKey: String, CaseIterable, Codable, Sendable { grain, glow }
public struct EffectAdjustments { grain, glow; init(grain:glow:); subscript(EffectKey); numericValues; hasEffect }
EditRecipe.effects, init(…makeup:effects:operations:); PresetValues.effects, init(…makeup:effects:)

// MellowEditing (Task 2·5)
EditChange.effect(EffectKey, Double)                                   // affectsGeometry false
public enum SyncCategory: String, CaseIterable, Codable, Sendable, Identifiable {
    color, effects, skin, faceShape, features, makeup, background, body, bodySkin
    static all: Set<SyncCategory>; var dependsOnFaces: Bool }
EditDocument.applyFromBatch(_:categories: = SyncCategory.all)

// MellowLibrary (Task 5)
ProjectSession.applyToAll(from:categories: = SyncCategory.all)

// MellowRendering (Task 3)
RenderTuning: + grainMaxAmplitude, grainSizeFraction, glowRadiusFraction, glowMaxIntensity
struct EffectStage: RenderStage { name "effect"; static clamped(_:), glowRadius(shortSide:tuning:), grainSize(shortSide:tuning:),
    glowed(_:amount:shortSide:tuning:), grained(_:amount:shortSide:tuning:), grainLayer(extent:amplitude:grainSize:) }
RenderPipeline.standard: LookStage() 뒤에 EffectStage()

// 앱 (Task 4·6·7)
UserMessage.effectTitle(_:), effectsHint, syncMenuLabel, syncCategoryTitle(_:), appliedToAll(categoryCount:total:),
    splitCompare, splitCompareDone, compareBadge(_:), compareDividerLabel
AppModel.syncCategories, setSyncCategory(_:enabled:), canApplyToAll
AppModel.CompareMode { off, full, split }, compareMode, isComparing(계산, get/set), compareSplit, blocksCanvasTouch,
    toggleSplitCompare(), setCompareSplit(_:), Policy.compareSplitDefault, Policy.compareSplitRange
struct SyncMenu: View; struct CompareDivider: View { static fraction(forX:width:) }
Theme.compareDividerWidth, compareHandleSize, canvasCoordinateSpace
```

---

### Task 1: 레시피 — EffectAdjustments, EditRecipe.effects, PresetValues, 스키마

**Files:**
- Create: `apple/Sources/MellowShared/API/EffectAdjustments.swift`
- Modify: `apple/Sources/MellowShared/API/EditRecipe.swift`, `Preset.swift`
- Modify: `shared/recipe-schema/edit-recipe.v2.schema.json`, `session-file.v2.schema.json`, `README.md`
- Test: `apple/Tests/MellowSharedTests/EditRecipeCodingTests.swift`, `RecipeSchemaTests.swift`

- [ ] **Step 1: 실패하는 테스트 작성**

`EditRecipeCodingTests.swift`에 추가:

```swift
    func testEffectsRoundTripDefaultsAndNeedNoAnalysis() throws {
        let legacy = #"{"schemaVersion":2,"look":{"id":"film"}}"#
        let decoded = try JSONDecoder().decode(EditRecipe.self, from: Data(legacy.utf8))
        XCTAssertEqual(decoded.effects, EffectAdjustments(), "G3 이전 파일은 효과가 0")
        var recipe = EditRecipe()
        recipe.effects = EffectAdjustments(grain: 0.3, glow: 0.6)
        XCTAssertEqual(recipe.effects.numericValues, [0.3, 0.6])
        XCTAssertEqual(recipe.effects[.glow], 0.6)
        XCTAssertTrue(recipe.effects.hasEffect)
        XCTAssertFalse(recipe.dependsOnFaces)
        XCTAssertFalse(recipe.dependsOnPerson)
        XCTAssertFalse(recipe.dependsOnBody)
        XCTAssertFalse(recipe.isDefault)
        let data = try JSONEncoder().encode(recipe)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(Set(try XCTUnwrap(json["effects"] as? [String: Any]).keys), Set(EffectKey.allCases.map(\.rawValue)))
        XCTAssertEqual(try JSONDecoder().decode(EditRecipe.self, from: data), recipe)
    }

    func testEffectScalarsAreCheckedForFinitenessAndCarriedByPresets() throws {
        for path in [\EditRecipe.effects.grain, \EditRecipe.effects.glow] {
            var recipe = EditRecipe()
            recipe[keyPath: path] = .nan
            XCTAssertFalse(recipe.allValuesFinite, "\(path)")
        }
        var recipe = EditRecipe()
        recipe.effects.grain = 0.2
        let values = PresetValues(of: recipe)
        XCTAssertEqual(values.effects.grain, 0.2)
        XCTAssertEqual(try JSONDecoder().decode(PresetValues.self, from: JSONEncoder().encode(values)), values)
        let legacy = try JSONDecoder().decode(PresetValues.self, from: Data(#"{"color":{},"portrait":{}}"#.utf8))
        XCTAssertEqual(legacy.effects, EffectAdjustments())
    }
```

`RecipeSchemaTests.swift`: `encodedSampleRecipe()`에 `recipe.effects.grain = 0.1`, 키 배열에 `"effects"` 추가.

- [ ] **Step 2: 실패 확인**

Run: `cd apple && swift test --filter EditRecipeCodingTests` → 컴파일 실패(`EffectAdjustments` 없음).

- [ ] **Step 3: 구현**

`apple/Sources/MellowShared/API/EffectAdjustments.swift`:

```swift
import Foundation

/// 효과 슬라이더 이름. 레시피 JSON 키와 같다.
public enum EffectKey: String, CaseIterable, Codable, Sendable {
    case grain
    case glow
}

/// 그레인·글로우 0…1. 렌더는 룩 뒤 마지막 단계(effect)이고 분석이 필요 없다.
public struct EffectAdjustments: Codable, Equatable, Sendable {
    public var grain: Double
    public var glow: Double

    public init(grain: Double = 0, glow: Double = 0) {
        self.grain = grain
        self.glow = glow
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        grain = try container.decodeIfPresent(Double.self, forKey: .grain) ?? 0
        glow = try container.decodeIfPresent(Double.self, forKey: .glow) ?? 0
    }

    public subscript(key: EffectKey) -> Double {
        get {
            switch key {
            case .grain: return grain
            case .glow: return glow
            }
        }
        set {
            switch key {
            case .grain: grain = newValue
            case .glow: glow = newValue
            }
        }
    }

    /// EffectKey.allCases 순서.
    public var numericValues: [Double] { EffectKey.allCases.map { self[$0] } }
    public var hasEffect: Bool { numericValues.contains { $0 != 0 } }
}
```

`EditRecipe.swift`: `public var makeup = MakeupAdjustments()` 아래에 `public var effects = EffectAdjustments()`, init 인자 `makeup: MakeupAdjustments = .init(), effects: EffectAdjustments = .init(), operations: …`, `CodingKeys`에 `case effects`(makeup 다음), decode `?? .init()`, encode, `allValuesFinite`의 groups에 `+ effects.numericValues`.

`Preset.swift`: `PresetValues.effects`(makeup 다음), init 인자 `effects: EffectAdjustments = .init()`, `init(of:)`에 `effects: recipe.effects`, decode `?? .init()`.

`edit-recipe.v2.schema.json`의 `"makeup"` 항목 뒤:

```json
    "effects": {
      "type": "object", "additionalProperties": false,
      "description": "룩 뒤 마지막 단계. 분석이 필요 없다.",
      "properties": {
        "grain": { "type": "number", "default": 0, "minimum": 0, "maximum": 1 },
        "glow": { "type": "number", "default": 0, "minimum": 0, "maximum": 1 }
      }
    },
```

`session-file.v2.schema.json` 프리셋 `values.properties`에 `"effects": { "$ref": "edit-recipe.v2.schema.json#/properties/effects" }`. `README.md`: 요점에 "최상위 `effects`(그레인·글로우 0~1, 룩 뒤 마지막 단계)", 범위 표에 `| \`effects.*\` | 0 … 1 | 0 … 1 |`, 프리셋 `values` 줄에 `effects`, Apple 구현 파일 목록에 `EffectAdjustments.swift`.

- [ ] **Step 4: 통과 확인**

Run: `cd apple && swift test` → Shared `Executed 49 tests`, Library 30(세션 스키마 대조 통과), 0 failures. lint 출력 없음.

- [ ] **Step 5: 커밋**

```bash
git add apple/Sources/MellowShared/API/EffectAdjustments.swift apple/Sources/MellowShared/API/EditRecipe.swift apple/Sources/MellowShared/API/Preset.swift shared/recipe-schema/edit-recipe.v2.schema.json shared/recipe-schema/session-file.v2.schema.json shared/recipe-schema/README.md apple/Tests/MellowSharedTests/EditRecipeCodingTests.swift apple/Tests/MellowSharedTests/RecipeSchemaTests.swift
git commit -m "feat(shared): 효과 레시피 그룹 effects(그레인·글로우) 추가

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 2: 편집 규칙 — effect 변경

**Files:**
- Modify: `apple/Sources/MellowEditing/API/EditChange.swift`, `EditDocument.swift`
- Test: `apple/Tests/MellowEditingTests/EditDocumentTests.swift`

- [ ] **Step 1: 실패하는 테스트 작성**

```swift
    func testEffectChangesClampAreNotLockedAndAreCopiedButNotByAuto() {
        var document = EditDocument()
        document.appendLocalEdit(.spot(RetouchSpot(x: 0.5, y: 0.5, sourceX: 0.4, sourceY: 0.4, radius: 0.02)))
        XCTAssertFalse(EditChange.effect(.grain, 0.5).affectsGeometry)
        XCTAssertNil(document.set(.effect(.grain, 2)))
        XCTAssertEqual(document.recipe.effects.grain, 1)
        document.set(.effect(.glow, -1))
        XCTAssertEqual(document.recipe.effects.glow, 0)
        let suggestion = AutoEnhanceSuggestion(
            color: ColorAdjustments(exposure: 0.1), detail: DetailAdjustments(), portrait: PortraitAdjustments())
        document.applyAuto(suggestion)
        XCTAssertEqual(document.recipe.effects.grain, 1, "자동 보정은 효과를 건드리지 않는다")
        var other = EditDocument()
        other.apply(PresetValues(of: document.recipe))
        XCTAssertEqual(other.recipe.effects.grain, 1, "프리셋이 효과를 나른다")
        var third = EditDocument()
        third.applyFromBatch(PresetValues(effects: EffectAdjustments(glow: 0.4)))
        XCTAssertEqual(third.recipe.effects.glow, 0.4, "일괄 적용도 나른다")
    }
```

- [ ] **Step 2: 실패 확인** → 컴파일 실패(`EditChange.effect` 없음).

- [ ] **Step 3: 구현**

`EditChange.swift`: `case vignette(Double)` 아래에 `case effect(EffectKey, Double)`. `EditDocument.set`: `case .effect(let key, let value): updated.effects[key] = EditingPolicy.clamped(value, to: EditingPolicy.unitRange)`. `merged`의 `updated.makeup = values.makeup` 아래에 `updated.effects = values.effects`.

- [ ] **Step 4: 통과 확인** → Editing `Executed 34 tests`, 0 failures. lint 출력 없음.

- [ ] **Step 5: 커밋**

```bash
git add apple/Sources/MellowEditing/API/EditChange.swift apple/Sources/MellowEditing/API/EditDocument.swift apple/Tests/MellowEditingTests/EditDocumentTests.swift
git commit -m "feat(editing): 효과 편집 변경과 프리셋·일괄 복사

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 3: EffectStage — 글로우·그레인, 파이프라인 마지막 단계

**Files:**
- Create: `apple/Sources/MellowRendering/Domain/EffectStage.swift`
- Modify: `apple/Sources/MellowRendering/API/RenderTuning.swift`, `RenderPipeline.swift`
- Modify: `apple/Tests/MellowRenderingTests/RenderPipelineTests.swift` (순서 배열)
- Test: `apple/Tests/MellowRenderingTests/EffectStageTests.swift`(새 파일)

설계 근거: 스펙 1.6 효과. 기하 뒤라 현재 이미지 extent를 쓴다. `CIRandomGenerator`는 위치마다 값이 고정이라 같은 입력이면 같은 결과다.

- [ ] **Step 1: 실패하는 테스트 작성**

```swift
import CoreImage
import MellowShared
import XCTest

@testable import MellowRendering

final class EffectStageTests: XCTestCase {
    typealias Support = RenderingTestSupport

    private func output(_ image: CIImage, _ effects: EffectAdjustments) throws -> CIImage {
        var recipe = EditRecipe()
        recipe.effects = effects
        let context = RenderContext(extent: image.extent, recipe: recipe, faces: [], tuning: RenderTuning())
        return try EffectStage().apply(image, in: context)
    }

    /// 선형 평균 휘도(바이트 환산 전 0…1).
    private func meanLuma(_ image: CIImage) throws -> Double {
        let values = try Support.luma(image)
        return values.reduce(0, +) / Double(values.count)
    }

    func testZeroEffectsReturnInputBytesAndOutOfRangeValuesClamp() throws {
        let input = Support.skinTexture(size: 256)
        XCTAssertTrue(try Support.bytes(output(input, EffectAdjustments())) == Support.bytes(input))
        XCTAssertTrue(try Support.bytes(output(input, EffectAdjustments(grain: -1, glow: -2))) == Support.bytes(input), "음수는 0")
        XCTAssertTrue(
            try Support.bytes(output(input, EffectAdjustments(grain: 3, glow: 5)))
                == Support.bytes(output(input, EffectAdjustments(grain: 1, glow: 1))))
        XCTAssertEqual(EffectStage.clamped(EffectAdjustments(grain: 2, glow: -1)), EffectAdjustments(grain: 1))
        XCTAssertEqual(EffectStage().name, "effect")
    }

    func testGrainIsDeterministicAndKeepsMeanBrightness() throws {
        let input = Support.solid(CIColor(red: 0.5, green: 0.5, blue: 0.5), size: 256)
        let first = try output(input, EffectAdjustments(grain: 1))
        let second = try output(input, EffectAdjustments(grain: 1))
        XCTAssertTrue(try Support.bytes(first) == Support.bytes(second), "같은 입력은 같은 바이트")
        XCTAssertFalse(try Support.bytes(first) == Support.bytes(input), "그레인이 보인다")
        XCTAssertEqual(try meanLuma(first), try meanLuma(input), accuracy: 0.01, "평균 밝기는 거의 그대로")
        let flatVariance = Support.variance(try Support.luma(input))
        let grainVariance = Support.variance(try Support.luma(first))
        XCTAssertGreaterThan(grainVariance, flatVariance + 1e-5, "단색에 잡음이 생긴다")
        let half = Support.variance(try Support.luma(output(input, EffectAdjustments(grain: 0.5))))
        XCTAssertLessThan(half, grainVariance, "강도 0.5는 더 약하다")
        XCTAssertEqual(EffectStage.grainSize(shortSide: 1200, tuning: RenderTuning()), 1.44, accuracy: 1e-9)
        XCTAssertEqual(EffectStage.grainSize(shortSide: 100, tuning: RenderTuning()), 1, "알갱이는 1px 아래로 내려가지 않는다")
    }

    func testGlowBrightensHighlightsMoreThanShadows() throws {
        let input = Support.gradient()
        let before = try Support.grid(input)
        let after = try Support.grid(output(input, EffectAdjustments(glow: 1)))
        let dark = CGPoint(x: 8, y: 40)
        let bright = CGPoint(x: 120, y: 40)
        let brightGain = Int(after.red(bright)) - Int(before.red(bright))
        let darkGain = Int(after.red(dark)) - Int(before.red(dark))
        XCTAssertGreaterThanOrEqual(brightGain, 8, "밝은 쪽이 환해진다")
        XCTAssertGreaterThan(brightGain, darkGain, "어두운 쪽보다 더")
        XCTAssertEqual(EffectStage.glowRadius(shortSide: 1200, tuning: RenderTuning()), 24, accuracy: 1e-9)
    }

    func testEffectsFollowTheCurrentExtentAfterGeometry() throws {
        let input = Support.skinTexture(size: 256).cropped(to: CGRect(x: 64, y: 32, width: 128, height: 96))
        let result = try output(input, EffectAdjustments(grain: 1, glow: 1))
        XCTAssertEqual(result.extent, input.extent, "기하 뒤 extent(원점 0 아님)를 그대로 둔다")
        let grid = try Support.grid(result)
        for point in [CGPoint(x: 0, y: 0), CGPoint(x: 127, y: 95), CGPoint(x: 0, y: 95), CGPoint(x: 127, y: 0)] {
            XCTAssertEqual(grid.rgba(point)[3], 255, "가장자리가 투명해지지 않는다 \(point)")
        }
    }
}
```

`RenderPipelineTests.testStageOrderMatters` 배열 끝에 `"effect"`를 더한다.

- [ ] **Step 2: 실패 확인** → 컴파일 실패(`EffectStage` 없음).

- [ ] **Step 3: 구현**

`RenderTuning.swift`의 `lookTintRange` 아래:

```swift
    /// 그레인 1에서 오버레이 층의 잡음 진폭(sRGB 감마 값, 전체 폭). 0.5 ± 0.06.
    public var grainMaxAmplitude: Double = 0.12
    /// 알갱이 한 변. 짧은 변 비율(1200px에서 1.44px). 1px 아래로는 내려가지 않는다.
    public var grainSizeFraction: Double = 0.0012
    /// 글로우 반지름. 짧은 변 비율(1200px에서 24px).
    public var glowRadiusFraction: Double = 0.02
    /// 글로우 1에서 CIBloom 세기.
    public var glowMaxIntensity: Double = 0.6
```

`apple/Sources/MellowRendering/Domain/EffectStage.swift`:

```swift
import CoreImage
import MellowShared

/// 글로우(CIBloom) → 그레인(회색 잡음 오버레이). 룩 뒤 마지막 단계라 기하 뒤 현재 extent를 쓴다. 분석이 필요 없다.
/// 값은 AdjustmentRange.unit으로 직접 자른다. 그레인은 CIRandomGenerator가 위치마다 고정값이라 결정적이다.
struct EffectStage: RenderStage {
    let name = "effect"

    /// 오버레이의 중립 회색. 이 값의 층은 항등이다.
    private static let neutralGray = 0.5
    /// 알갱이 한 변의 하한(픽셀).
    private static let minimumGrainSize: CGFloat = 1

    func apply(_ image: CIImage, in context: RenderContext) throws -> CIImage {
        let values = Self.clamped(context.recipe.effects)
        guard values.hasEffect else { return image }
        let extent = image.extent
        let shortSide = min(extent.width, extent.height)
        var result = image
        if values.glow > 0 {
            result = Self.glowed(result, amount: values.glow, shortSide: shortSide, tuning: context.tuning)
        }
        if values.grain > 0 {
            result = Self.grained(result, amount: values.grain, shortSide: shortSide, tuning: context.tuning)
        }
        return result.cropped(to: extent)
    }

    static func clamped(_ effects: EffectAdjustments) -> EffectAdjustments {
        var copy = effects
        for key in EffectKey.allCases {
            copy[key] = AdjustmentRange.clamped(effects[key], to: AdjustmentRange.unit)
        }
        return copy
    }

    static func glowRadius(shortSide: CGFloat, tuning: RenderTuning) -> Double {
        Double(shortSide) * tuning.glowRadiusFraction
    }

    static func grainSize(shortSide: CGFloat, tuning: RenderTuning) -> CGFloat {
        max(minimumGrainSize, shortSide * CGFloat(tuning.grainSizeFraction))
    }

    /// 밝은 영역이 번지는 글로우. 가장자리는 늘려 어두워지지 않게 한다.
    static func glowed(_ image: CIImage, amount: Double, shortSide: CGFloat, tuning: RenderTuning) -> CIImage {
        image.clampedToExtent()
            .applyingFilter(
                "CIBloom",
                parameters: [
                    kCIInputRadiusKey: glowRadius(shortSide: shortSide, tuning: tuning),
                    kCIInputIntensityKey: amount * tuning.glowMaxIntensity,
                ]
            )
            .cropped(to: image.extent)
    }

    /// 회색 잡음 층을 sRGB 감마 공간에서 오버레이로 얹고 선형으로 되돌린다.
    static func grained(_ image: CIImage, amount: Double, shortSide: CGFloat, tuning: RenderTuning) -> CIImage {
        let layer = grainLayer(
            extent: image.extent, amplitude: amount * tuning.grainMaxAmplitude,
            grainSize: grainSize(shortSide: shortSide, tuning: tuning))
        let base = image.applyingFilter("CILinearToSRGBToneCurve")
        return layer.applyingFilter("CIOverlayBlendMode", parameters: [kCIInputBackgroundImageKey: base])
            .applyingFilter("CISRGBToneCurveToLinear").cropped(to: image.extent)
    }

    /// 0.5 ± amplitude/2의 회색 잡음. CIRandomGenerator의 알파(0…1 균등)를 회색으로 쓰고 grainSize 배로 키운다.
    static func grainLayer(extent: CGRect, amplitude: Double, grainSize: CGFloat) -> CIImage {
        let bias = neutralGray - amplitude / 2
        let noise = CIFilter(name: "CIRandomGenerator")!.outputImage!.applyingFilter(
            "CIColorMatrix",
            parameters: [
                "inputRVector": CIVector(x: 0, y: 0, z: 0, w: amplitude),
                "inputGVector": CIVector(x: 0, y: 0, z: 0, w: amplitude),
                "inputBVector": CIVector(x: 0, y: 0, z: 0, w: amplitude),
                "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 0),
                "inputBiasVector": CIVector(x: bias, y: bias, z: bias, w: 1),
            ])
        return noise.transformed(by: CGAffineTransform(scaleX: grainSize, y: grainSize)).cropped(to: extent)
    }
}
```

`RenderPipeline.swift`: `standard` 배열 끝 `LookStage(),` 뒤에 `EffectStage(),`. doc 주석에 "효과(글로우·그레인)는 룩 뒤 마지막"을 더한다.

- [ ] **Step 4: 통과 확인** → Rendering `Executed 257 tests`, 0 failures. lint 출력 없음. `./scripts/verify-modules.sh` 통과.

- [ ] **Step 5: 커밋**

```bash
git add apple/Sources/MellowRendering/Domain/EffectStage.swift apple/Sources/MellowRendering/API/RenderTuning.swift apple/Sources/MellowRendering/API/RenderPipeline.swift apple/Tests/MellowRenderingTests/RenderPipelineTests.swift apple/Tests/MellowRenderingTests/EffectStageTests.swift
git commit -m "feat(rendering): 효과 단계 — 글로우와 그레인

룩 뒤 마지막 단계 effect. 글로우는 CIBloom, 그레인은 짧은 변에 비례한 회색 잡음을
sRGB 감마 공간에서 오버레이한다. 같은 입력은 같은 바이트다.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 4: 앱 — 조정 패널 효과 슬라이더

**Files:**
- Modify: `apple/MellowPhoto/Application/UserMessage.swift`, `apple/MellowPhoto/Features/Editor/AdjustPanel.swift`
- Test: `apple/MellowPhotoTests/AppModelTests.swift`

- [ ] **Step 1: 실패하는 테스트 작성**

```swift
    func testAdjustToolEditsEffectsOneUndoStepEach() async throws {
        let staged = try TestSupport.solidPNG(in: root)
        let model = TestSupport.makeModel(
            root: root, importer: FakeImporter(staged: [.success(StagedPhoto(url: staged, displayName: nil))]))
        try await importOne(model, staged)
        model.selectTool(.adjust)
        for (offset, key) in EffectKey.allCases.enumerated() {
            model.beginSliderEdit()
            model.edit(.effect(key, 0.2))
            model.edit(.effect(key, 0.6))
            model.endSliderEdit()
            XCTAssertEqual(model.session.selected?.document.undoStack.count, offset + 1, "\(key)")
        }
        XCTAssertEqual(model.currentRecipe.effects, EffectAdjustments(grain: 0.6, glow: 0.6))
        try await waitUntil { !model.isRendering }
        XCTAssertNil(model.presentedError)
        XCTAssertEqual(EffectKey.allCases.map(UserMessage.effectTitle), ["그레인", "글로우"])
        model.undo()
        XCTAssertEqual(model.currentRecipe.effects, EffectAdjustments(grain: 0.6))
    }
```

- [ ] **Step 2: 실패 확인** → Mac 앱 테스트 컴파일 실패(`UserMessage.effectTitle` 없음).

- [ ] **Step 3: 구현**

`UserMessage.swift`:

```swift
    static let effectsHint = "그레인과 글로우는 필터와 선명도 뒤에 사진 전체에 얹어요."

    /// 조정 패널 효과 슬라이더 이름. 화면 순서는 EffectKey.allCases.
    static func effectTitle(_ key: EffectKey) -> String {
        switch key {
        case .grain: return "그레인"
        case .glow: return "글로우"
        }
    }
```

`AdjustPanel.swift`: 비네팅 슬라이더 아래에 추가(`import MellowEditing` 필요):

```swift
        Divider().opacity(0.4)
        ForEach(EffectKey.allCases, id: \.self) { key in
            AdjustmentSlider(title: UserMessage.effectTitle(key), value: recipe.effects[key], range: EditingPolicy.unitRange) {
                .effect(key, $0)
            }
        }
        Text(UserMessage.effectsHint).font(.caption).foregroundStyle(.secondary)
```

- [ ] **Step 4: 통과 확인** → Mac 앱 테스트 `Executed 75 tests, with 0 failures`. lint 출력 없음.

- [ ] **Step 5: 커밋**

```bash
git add apple/MellowPhoto/Application/UserMessage.swift apple/MellowPhoto/Features/Editor/AdjustPanel.swift apple/MellowPhotoTests/AppModelTests.swift
git commit -m "feat(app): 조정 패널에 그레인·글로우 슬라이더

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 5: 선택 동기화 규칙 — SyncCategory, applyFromBatch(categories:), applyToAll(categories:)

**Files:**
- Create: `apple/Sources/MellowEditing/API/SyncCategory.swift`
- Modify: `apple/Sources/MellowEditing/API/EditDocument.swift` (`applyFromBatch`, `apply`, `merged`)
- Modify: `apple/Sources/MellowLibrary/API/ProjectSession.swift` (`applyToAll(from:categories:)`)
- Test: `apple/Tests/MellowEditingTests/EditDocumentTests.swift`, `apple/Tests/MellowLibraryTests/ProjectSessionTests.swift`

설계 근거: 스펙 1.7. 전부 고르면 기존 동작과 같아야 한다(기존 일괄·프리셋 테스트 불변).

- [ ] **Step 1: 실패하는 테스트 작성**

`EditDocumentTests.swift`:

```swift
    func testBatchCopiesOnlyChosenCategoriesAndKeepsTargetFaceWithoutFaceCategories() {
        var values = PresetValues(color: ColorAdjustments(exposure: 0.3), detail: DetailAdjustments(vignette: 0.2))
        values.portrait.skin.smoothing = 0.6
        values.portrait.face.width = -0.5
        values.makeup.lip = MakeupTint(colorID: "lip-coral", intensity: 0.5)
        values.bodySkin.brightness = 0.4
        values.effects.grain = 0.3
        var document = EditDocument()
        document.set(.targetFace(1))
        document.set(.feature(.teethWhiten, 0.7))
        document.applyFromBatch(values, categories: [.color, .effects])
        XCTAssertEqual(document.recipe.color.exposure, 0.3)
        XCTAssertEqual(document.recipe.detail.vignette, 0.2, "색감 항목은 디테일을 포함한다")
        XCTAssertEqual(document.recipe.effects.grain, 0.3)
        XCTAssertEqual(document.recipe.portrait.skin.smoothing, 0, "고르지 않은 피부는 그대로")
        XCTAssertEqual(document.recipe.portrait.features.teethWhiten, 0.7)
        XCTAssertNil(document.recipe.makeup.lip.colorID)
        XCTAssertEqual(document.recipe.bodySkin.brightness, 0)
        XCTAssertEqual(document.recipe.portrait.targetFace, 1, "얼굴 의존 항목이 없으면 대상 얼굴을 유지한다")
        document.applyFromBatch(values, categories: [.skin])
        XCTAssertEqual(document.recipe.portrait.skin.smoothing, 0.6)
        XCTAssertNil(document.recipe.portrait.targetFace, "얼굴 의존 항목을 복사하면 대상 얼굴을 전체로")
        var locked = EditDocument()
        locked.set(.faceShape(.width, -0.2))
        locked.appendLocalEdit(.spot(RetouchSpot(x: 0.5, y: 0.4, sourceX: 0.4, sourceY: 0.4, radius: 0.02)))
        let before = locked.recipe
        locked.applyFromBatch(values, categories: [.faceShape, .body])
        XCTAssertEqual(locked.recipe, before, "잠긴 사진의 얼굴형·체형은 복사하지 않는다")
        let steps = locked.undoStack.count
        locked.applyFromBatch(values, categories: [])
        XCTAssertEqual(locked.undoStack.count, steps, "빈 선택은 아무것도 하지 않는다")
        XCTAssertEqual(SyncCategory.allCases.count, 9)
        XCTAssertEqual(SyncCategory.allCases.filter(\.dependsOnFaces), [.skin, .faceShape, .features, .makeup])
        XCTAssertEqual(SyncCategory.all, Set(SyncCategory.allCases))
    }
```

`ProjectSessionTests.swift`:

```swift
    func testApplyToAllWithCategoriesCopiesOnlyThose() throws {
        let session = ProjectSession(store: MemorySessionStore(), maxPhotos: 40)
        let source = entry("A")
        let other = entry("B")
        try session.add(source)
        try session.add(other)
        session.edit(source.id) { $0.set(.exposure(0.3)) }
        session.edit(source.id) { $0.set(.skinSmoothing(0.5)) }
        session.edit(other.id) { $0.set(.targetFace(0)) }
        session.applyToAll(from: source.id, categories: [.color])
        XCTAssertEqual(session.photos[1].document.recipe.color.exposure, 0.3)
        XCTAssertEqual(session.photos[1].document.recipe.portrait.skin.smoothing, 0, "피부는 고르지 않았다")
        XCTAssertEqual(session.photos[1].document.recipe.portrait.targetFace, 0, "얼굴 항목이 없으면 대상 얼굴 유지")
        session.applyToAll(from: source.id)
        XCTAssertEqual(session.photos[1].document.recipe.portrait.skin.smoothing, 0.5, "기본은 전부")
        XCTAssertNil(session.photos[1].document.recipe.portrait.targetFace)
    }
```

- [ ] **Step 2: 실패 확인** → 컴파일 실패(`SyncCategory` 없음).

- [ ] **Step 3: 구현**

`apple/Sources/MellowEditing/API/SyncCategory.swift`:

```swift
import MellowShared

/// "전체 사진에 적용"이 복사할 수 있는 항목. 레시피 그룹과의 대응과 잠금·대상 얼굴 규칙은 EditDocument.applyFromBatch에 있다.
public enum SyncCategory: String, CaseIterable, Codable, Sendable, Identifiable {
    /// 색감 + 디테일.
    case color
    case effects
    /// 피부 보정·자동 잡티·피부 정밀.
    case skin
    /// 얼굴형. 잠긴 사진에서는 복사하지 않는다.
    case faceShape
    case features
    case makeup
    case background
    /// 체형. 잠긴 사진에서는 복사하지 않는다.
    case body
    case bodySkin

    public var id: Self { self }
    public static let all = Set(allCases)

    /// 얼굴에 의존하는 항목. 하나라도 복사하면 잠기지 않은 사진의 대상 얼굴을 전체로 되돌린다.
    public var dependsOnFaces: Bool {
        switch self {
        case .skin, .faceShape, .features, .makeup: return true
        case .color, .effects, .background, .body, .bodySkin: return false
        }
    }
}
```

`EditDocument.swift`: `apply`·`applyFromBatch`·`merged`를 다음으로 바꾼다.

```swift
    /// 사용자가 고른 프리셋. 프리셋은 얼굴을 고르지 않으므로 대상 얼굴은 늘 사진의 값을 유지한다. 잠긴 사진은 얼굴형·체형도 유지한다.
    public mutating func apply(_ values: PresetValues) {
        checkpoint()
        recipe = merged(values, targetFace: recipe.portrait.targetFace, categories: SyncCategory.all)
    }

    /// 다른 사진의 설정을 일괄 복사. 고른 항목만 덮어쓴다(기본은 전부). 빈 선택은 아무것도 하지 않는다.
    /// 잠기지 않은 사진은 얼굴 의존 항목을 복사할 때만 대상 얼굴을 전체로 되돌린다.
    public mutating func applyFromBatch(_ values: PresetValues, categories: Set<SyncCategory> = SyncCategory.all) {
        guard !categories.isEmpty else { return }
        let resetsTarget = !isGeometryLocked && categories.contains { $0.dependsOnFaces }
        checkpoint()
        recipe = merged(values, targetFace: resetsTarget ? nil : recipe.portrait.targetFace, categories: categories)
    }

    /// 고른 그룹을 프리셋 값으로 바꾼다. 룩·기하·수동 편집은 그대로 두고, 잠긴 사진은 얼굴형·체형을 건너뛴다.
    private func merged(_ values: PresetValues, targetFace: Int?, categories: Set<SyncCategory>) -> EditRecipe {
        var updated = recipe
        if categories.contains(.color) {
            updated.color = values.color
            updated.detail = values.detail
        }
        if categories.contains(.effects) {
            updated.effects = values.effects
        }
        if categories.contains(.skin) {
            updated.portrait.skin = values.portrait.skin
        }
        if categories.contains(.faceShape), !isGeometryLocked {
            updated.portrait.face = values.portrait.face
        }
        if categories.contains(.features) {
            updated.portrait.features = values.portrait.features
        }
        if categories.contains(.makeup) {
            updated.makeup = values.makeup
        }
        if categories.contains(.background) {
            updated.background = values.background
        }
        if categories.contains(.body), !isGeometryLocked {
            updated.body = values.body
        }
        if categories.contains(.bodySkin) {
            updated.bodySkin = values.bodySkin
        }
        updated.portrait.targetFace = targetFace
        return updated
    }
```

`ProjectSession.swift`: `applyToAll(from id: PhotoID)`를 `applyToAll(from id: PhotoID, categories: Set<SyncCategory> = SyncCategory.all)`로 바꾸고 `applyFromBatch(values, categories: categories)`를 부른다. doc 주석 "고른 항목만 복사한다(기본은 전부)".

- [ ] **Step 4: 통과 확인** → Editing `Executed 35 tests`, Library `31`, 0 failures(기존 `testBatchApplyKeepsLockedShapeAndCopiesTheRest`·`testPresetPreservesFaceShapeWhenLocked`·`testApplyToAllCopiesValuesWithBatchRules` 불변 통과). lint 출력 없음. `./scripts/verify-modules.sh` 통과.

- [ ] **Step 5: 커밋**

```bash
git add apple/Sources/MellowEditing/API/SyncCategory.swift apple/Sources/MellowEditing/API/EditDocument.swift apple/Sources/MellowLibrary/API/ProjectSession.swift apple/Tests/MellowEditingTests/EditDocumentTests.swift apple/Tests/MellowLibraryTests/ProjectSessionTests.swift
git commit -m "feat(editing): 선택 동기화 — 일괄 적용이 고른 항목만 복사

SyncCategory 9종. 잠긴 사진 보존 규칙은 그대로이고 얼굴 의존 항목을 복사할 때만
대상 얼굴을 전체로 되돌린다. 기본은 전부라 기존 동작과 같다.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 6: 앱 — 동기화 항목 메뉴

**Files:**
- Create: `apple/MellowPhoto/Features/Editor/SyncMenu.swift`
- Modify: `apple/MellowPhoto/Application/AppModel.swift`, `AppModel+Editing.swift`, `UserMessage.swift`, `apple/MellowPhoto/Features/Editor/EditorScene.swift`, `apple/MellowPhoto.xcodeproj`
- Test: `apple/MellowPhotoTests/AppModelTests.swift`

- [ ] **Step 1: 실패하는 테스트 작성**

```swift
    func testApplyToAllCopiesOnlyChosenCategories() async throws {
        let first = try TestSupport.solidPNG(in: root, name: "A")
        let second = try TestSupport.solidPNG(in: root, name: "B")
        let model = TestSupport.makeModel(root: root, importer: FakeImporter(passesThroughFileURLs: true))
        await model.importFromFiles([first, second])
        try await waitUntil { model.isReady && model.preview != nil }
        XCTAssertEqual(model.session.photos.count, 2)
        XCTAssertEqual(model.syncCategories, SyncCategory.all, "기본은 전부")
        XCTAssertTrue(model.canApplyToAll)
        model.edit(.exposure(0.3))
        model.edit(.skinSmoothing(0.4))
        model.setSyncCategory(.skin, enabled: false)
        model.applyToAll()
        let other = model.session.photos[1].document.recipe
        XCTAssertEqual(other.color.exposure, 0.3)
        XCTAssertEqual(other.portrait.skin.smoothing, 0, "끈 항목은 복사하지 않는다")
        XCTAssertEqual(model.statusMessage, UserMessage.appliedToAll(categoryCount: 8, total: 9))
        for category in SyncCategory.allCases {
            model.setSyncCategory(category, enabled: false)
        }
        XCTAssertFalse(model.canApplyToAll, "아무것도 고르지 않으면 끈다")
        model.edit(.exposure(0.5))
        model.applyToAll()
        XCTAssertEqual(model.session.photos[1].document.recipe.color.exposure, 0.3, "빈 선택은 적용하지 않는다")
        model.setSyncCategory(.color, enabled: true)
        XCTAssertEqual(model.syncCategories, [.color])
        XCTAssertEqual(
            SyncCategory.allCases.map(UserMessage.syncCategoryTitle),
            ["색감·디테일", "효과", "피부", "얼굴형", "눈·입", "메이크업", "배경", "체형", "피부톤"])
    }
```

- [ ] **Step 2: 실패 확인** → 컴파일 실패(`syncCategories` 없음).

- [ ] **Step 3: 구현**

`AppModel.swift`: `var isComparing = false` 근처에 `/// 전체 사진에 적용이 복사할 항목. 세션 상태라 파일에 저장하지 않는다. var syncCategories: Set<SyncCategory> = SyncCategory.all`. `canRemoveSelected` 같은 자리에:

```swift
    /// 전체 사진에 적용을 누를 수 있는지. 사진이 둘 이상이고 복사할 항목이 하나라도 있어야 한다.
    var canApplyToAll: Bool { session.photos.count >= 2 && !syncCategories.isEmpty }

    func setSyncCategory(_ category: SyncCategory, enabled: Bool) {
        if enabled {
            syncCategories.insert(category)
        } else {
            syncCategories.remove(category)
        }
    }
```

`AppModel+Editing.swift`의 `applyToAll()`:

```swift
    func applyToAll() {
        guard let id = session.selectedPhotoID, !isBusy, !syncCategories.isEmpty else { return }
        session.applyToAll(from: id, categories: syncCategories)
        statusMessage = UserMessage.appliedToAll(categoryCount: syncCategories.count, total: SyncCategory.allCases.count)
    }
```

`UserMessage.swift`: 기존 `static let appliedToAll` 아래에:

```swift
    static let syncMenuLabel = "동기화 항목"

    /// 전부 골랐으면 기존 문구, 아니면 고른 개수를 알린다.
    static func appliedToAll(categoryCount: Int, total: Int) -> String {
        categoryCount == total ? appliedToAll : "전체 사진에 고른 \(categoryCount)개 항목을 적용했어요."
    }

    /// 동기화 메뉴 항목 이름. 화면 순서는 SyncCategory.allCases.
    static func syncCategoryTitle(_ category: SyncCategory) -> String {
        switch category {
        case .color: return "색감·디테일"
        case .effects: return "효과"
        case .skin: return "피부"
        case .faceShape: return "얼굴형"
        case .features: return "눈·입"
        case .makeup: return "메이크업"
        case .background: return "배경"
        case .body: return "체형"
        case .bodySkin: return "피부톤"
        }
    }
```

`apple/MellowPhoto/Features/Editor/SyncMenu.swift`:

```swift
import MellowEditing
import SwiftUI

/// "전체 사진에 적용"이 복사할 항목을 고르는 톱니 메뉴. 항목마다 켜고 끄는 토글이다.
struct SyncMenu: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Menu {
            ForEach(SyncCategory.allCases) { category in
                Toggle(
                    UserMessage.syncCategoryTitle(category),
                    isOn: Binding(
                        get: { model.syncCategories.contains(category) },
                        set: { model.setSyncCategory(category, enabled: $0) }))
            }
        } label: {
            Image(systemName: "gearshape")
        }
        .menuStyle(.button)
        .accessibilityLabel(UserMessage.syncMenuLabel)
    }
}
```

`EditorScene.swift`: compact의 `Button("전체 사진에 적용") { model.applyToAll() }.disabled(model.session.photos.count < 2)`를 `Button("전체 사진에 적용") { model.applyToAll() }.disabled(!model.canApplyToAll)`로 바꾸고 바로 뒤에 `SyncMenu()`를 둔다. regular의 전체 적용 버튼은 `HStack { Button {…}.buttonStyle(.bordered).disabled(!model.canApplyToAll); SyncMenu() }`로 감싼다.

`cd apple && xcodegen generate --quiet && git status --short MellowPhoto.xcodeproj` → `M MellowPhoto.xcodeproj/project.pbxproj`.

- [ ] **Step 4: 통과 확인** → Mac 앱 테스트 `Executed 76 tests, with 0 failures`. lint 출력 없음. `cd apple && xcodegen generate --quiet && git diff --exit-code --stat MellowPhoto.xcodeproj` → 커밋 뒤 출력 없음.

- [ ] **Step 5: 커밋**

```bash
git add apple/MellowPhoto/Features/Editor/SyncMenu.swift apple/MellowPhoto/Application/AppModel.swift apple/MellowPhoto/Application/AppModel+Editing.swift apple/MellowPhoto/Application/UserMessage.swift apple/MellowPhoto/Features/Editor/EditorScene.swift apple/MellowPhoto.xcodeproj apple/MellowPhotoTests/AppModelTests.swift
git commit -m "feat(app): 전체 사진에 적용의 동기화 항목 메뉴

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 7: 앱 — 분할 전후 비교(기존 전체 토글은 그대로)

**Files:**
- Create: `apple/MellowPhoto/Features/Editor/CompareDivider.swift`
- Modify: `apple/MellowPhoto/Application/AppModel.swift`, `AppModel+Editing.swift`(`touch` 가드), `UserMessage.swift`, `apple/MellowPhoto/Features/Shared/Theme.swift`, `apple/MellowPhoto/Features/Editor/PhotoCanvasView.swift`, `ActionBar.swift`, `apple/MellowPhoto.xcodeproj`
- Test: `apple/MellowPhotoTests/AppModelTests.swift`, `apple/MellowPhotoTests/CompareDividerTests.swift`(새 파일)

설계 근거: 스펙 1.8. `isComparing`을 계산 속성(get/set)으로 바꿔 기존 토글 버튼·`displayImage`·테스트가 그대로 동작한다. 분할은 모드 하나를 더하는 것이고, 두 모드는 상호 배타다.

- [ ] **Step 1: 실패하는 테스트 작성**

`AppModelTests.swift`:

```swift
    func testSplitCompareIsAModeBesideTheFullToggleAndResetsOnSelect() async throws {
        let staged = try TestSupport.solidPNG(in: root)
        let model = TestSupport.makeModel(
            root: root, importer: FakeImporter(staged: [.success(StagedPhoto(url: staged, displayName: nil))]))
        try await importOne(model, staged)
        XCTAssertEqual(model.compareMode, .off)
        XCTAssertFalse(model.blocksCanvasTouch)
        model.isComparing = true
        XCTAssertEqual(model.compareMode, .full, "기존 토글은 전체 모드")
        XCTAssertTrue(model.displayImage === model.original)
        model.toggleSplitCompare()
        XCTAssertEqual(model.compareMode, .split, "분할을 켜면 전체는 꺼진다")
        XCTAssertFalse(model.isComparing)
        XCTAssertTrue(model.displayImage === model.preview, "분할 모드의 바탕은 보정본")
        XCTAssertTrue(model.blocksCanvasTouch)
        XCTAssertEqual(model.compareSplit, AppModel.Policy.compareSplitDefault)
        model.setCompareSplit(1.4)
        XCTAssertEqual(model.compareSplit, 1)
        model.setCompareSplit(-0.2)
        XCTAssertEqual(model.compareSplit, 0)
        model.setCompareSplit(0.3)
        model.selectTool(.retouch)
        model.touch(from: NormalizedPoint(x: 0.5, y: 0.5), to: NormalizedPoint(x: 0.5, y: 0.5))
        XCTAssertNil(model.cloneSource, "비교 중에는 캔버스 탭을 무시한다")
        model.isComparing.toggle()
        XCTAssertEqual(model.compareMode, .full, "분할 중에 전체 토글을 켜면 전체로")
        model.toggleSplitCompare()
        model.toggleSplitCompare()
        XCTAssertEqual(model.compareMode, .off, "분할을 두 번 누르면 꺼진다")
        XCTAssertEqual(model.compareSplit, 0.3, accuracy: 1e-9, "분할선 위치는 기억한다")
        model.toggleSplitCompare()
        let id = try XCTUnwrap(model.session.selectedPhotoID)
        model.select(id)
        XCTAssertEqual(model.compareMode, .off, "사진을 고르면 비교가 꺼진다")
        XCTAssertEqual(UserMessage.compareBadge(.split), "원본 | 보정본")
        XCTAssertEqual(UserMessage.compareBadge(.full), "원본")
        XCTAssertEqual(UserMessage.compareBadge(.off), "보정본")
    }
```

`apple/MellowPhotoTests/CompareDividerTests.swift`:

```swift
import XCTest

@testable import Mellow_Photo

/// 분할선 드래그 계산만 확인한다. 화면 표시는 사람이 본다.
@MainActor
final class CompareDividerTests: XCTestCase {
    func testFractionClampsToCanvasAndDefaultsWhenWidthIsZero() {
        XCTAssertEqual(CompareDivider.fraction(forX: 150, width: 300), 0.5, accuracy: 1e-9)
        XCTAssertEqual(CompareDivider.fraction(forX: -20, width: 300), 0)
        XCTAssertEqual(CompareDivider.fraction(forX: 400, width: 300), 1)
        XCTAssertEqual(CompareDivider.fraction(forX: 10, width: 0), AppModel.Policy.compareSplitDefault)
    }
}
```

- [ ] **Step 2: 실패 확인** → 컴파일 실패(`compareMode` 없음).

- [ ] **Step 3: 구현**

`AppModel.swift`:
1. `Policy`에 `/// 분할 비교의 처음 분할선 위치와 범위(원본이 보이는 왼쪽 폭 비율). static let compareSplitDefault = 0.5`, `static let compareSplitRange = 0.0...1.0`.
2. 중첩 타입에 `/// 전후 비교 모드. full은 기존 전체 토글, split은 분할선. enum CompareMode: Equatable { case off, full, split }`.
3. `var isComparing = false`를 다음으로 바꾼다:

```swift
    var compareMode: CompareMode = .off
    /// 원본이 보이는 왼쪽 폭 비율. 분할을 끄고 켜도 유지한다.
    var compareSplit = Policy.compareSplitDefault
    /// 기존 전체 토글. 분할 중에 true로 두면 전체로 바뀐다.
    var isComparing: Bool {
        get { compareMode == .full }
        set { compareMode = newValue ? .full : .off }
    }
    /// 비교 중에는 캔버스 탭·브러시·자르기 틀을 막는다(두 모드 모두).
    var blocksCanvasTouch: Bool { compareMode != .off }

    func toggleSplitCompare() {
        compareMode = compareMode == .split ? .off : .split
    }

    func setCompareSplit(_ fraction: Double) {
        compareSplit = min(Policy.compareSplitRange.upperBound, max(Policy.compareSplitRange.lowerBound, fraction))
    }
```

4. `select(_:)`의 `isComparing = false`를 `compareMode = .off`로.
5. `AppModel+Editing.swift` `touch`의 `!isComparing`을 `!blocksCanvasTouch`로.

`UserMessage.swift`:

```swift
    static let splitCompare = "분할"
    static let splitCompareDone = "분할 끝"
    static let compareDividerLabel = "원본과 보정본의 경계"

    /// 캔버스 왼쪽 위 배지.
    static func compareBadge(_ mode: AppModel.CompareMode) -> String {
        switch mode {
        case .off: return "보정본"
        case .full: return "원본"
        case .split: return "원본 | 보정본"
        }
    }
```

`Theme.swift`: `static let compareDividerWidth: CGFloat = 2`, `/// 분할선 손잡이 지름. static let compareHandleSize: CGFloat = 28`, `/// 캔버스 이미지 좌표계 이름. 분할선 드래그 위치를 이 좌표로 받는다. static let canvasCoordinateSpace = "canvas"`.

`apple/MellowPhoto/Features/Editor/CompareDivider.swift`:

```swift
import SwiftUI

/// 분할 비교의 세로 분할선과 손잡이. 드래그 위치는 캔버스 좌표(Theme.canvasCoordinateSpace)로 받아 0…1로 자른다.
struct CompareDivider: View {
    @Environment(AppModel.self) private var model
    let size: CGSize

    /// 캔버스 x 위치를 분할 비율로. 폭이 0이면 기본 위치.
    static func fraction(forX x: CGFloat, width: CGFloat) -> Double {
        guard width > 0 else { return AppModel.Policy.compareSplitDefault }
        return min(1, max(0, Double(x / width)))
    }

    var body: some View {
        ZStack {
            Rectangle().fill(.white).frame(width: Theme.compareDividerWidth, height: size.height)
            Circle().fill(.white)
                .frame(width: Theme.compareHandleSize, height: Theme.compareHandleSize)
                .overlay(Image(systemName: "arrow.left.and.right").font(.caption2.weight(.bold)).foregroundStyle(.black))
                .shadow(radius: 2)
        }
        .position(x: size.width * model.compareSplit, y: size.height / 2)
        .gesture(
            DragGesture(minimumDistance: 0, coordinateSpace: .named(Theme.canvasCoordinateSpace))
                .onChanged { value in
                    model.setCompareSplit(Self.fraction(forX: value.location.x, width: size.width))
                })
        .accessibilityLabel(UserMessage.compareDividerLabel)
    }
}
```

`PhotoCanvasView.swift`:
1. `Image(cgImage: image)…frame(width:height:)` 뒤 overlay 체인에 `.overlay { splitOverlay(in: size) }`를 `cropOverlay` 앞에 더하고, `.frame(minWidth:…)` 앞에 `.coordinateSpace(name: Theme.canvasCoordinateSpace)`를 둔다.
2. `cloneSourceMarker`·`cropOverlay`·`touchLayer`의 `!model.isComparing`을 `!model.blocksCanvasTouch`로.
3. 접근성 라벨 `model.isComparing ? "원본 사진" : "보정 미리보기"`는 `model.compareMode == .full ? "원본 사진" : "보정 미리보기"`로.
4. 왼쪽 위 배지 `Text(model.isComparing ? "원본" : "보정본")`을 `Text(UserMessage.compareBadge(model.compareMode))`로.
5. 함수 추가:

```swift
    /// 분할 모드: 원본을 왼쪽 compareSplit 비율만 보이게 얹고 경계에 분할선을 둔다.
    @ViewBuilder
    private func splitOverlay(in size: CGSize) -> some View {
        if model.compareMode == .split, let original = model.original {
            Image(cgImage: original).resizable().interpolation(.high)
                .frame(width: size.width, height: size.height)
                .mask(alignment: .leading) { Rectangle().frame(width: size.width * model.compareSplit) }
                .allowsHitTesting(false)
            CompareDivider(size: size)
        }
    }
```

`ActionBar.swift`: 기존 "원본 비교" 버튼 앞에 추가(기존 버튼은 그대로):

```swift
            Button {
                model.toggleSplitCompare()
            } label: {
                Text(model.compareMode == .split ? UserMessage.splitCompareDone : UserMessage.splitCompare)
                    .font(.caption.weight(.medium))
                    .frame(minWidth: 44, minHeight: 40)
            }
```

`cd apple && xcodegen generate --quiet`.

- [ ] **Step 4: 통과 확인** → Mac 앱 테스트 `Executed 78 tests, with 0 failures`(기존 `isComparing`을 쓰는 테스트 포함). lint 출력 없음. xcodeproj 차이 없음.

- [ ] **Step 5: 커밋**

```bash
git add apple/MellowPhoto/Features/Editor/CompareDivider.swift apple/MellowPhoto/Application/AppModel.swift apple/MellowPhoto/Application/AppModel+Editing.swift apple/MellowPhoto/Application/UserMessage.swift apple/MellowPhoto/Features/Shared/Theme.swift apple/MellowPhoto/Features/Editor/PhotoCanvasView.swift apple/MellowPhoto/Features/Editor/ActionBar.swift apple/MellowPhoto.xcodeproj apple/MellowPhotoTests/AppModelTests.swift apple/MellowPhotoTests/CompareDividerTests.swift
git commit -m "feat(app): 분할 전후 비교를 기존 원본 비교 토글 옆에 추가

비교 모드(없음·전체·분할) 하나로 묶되 기존 토글 동작은 그대로다. 분할은 원본을 왼쪽만
보이게 얹고 분할선을 드래그한다. 비교 중 캔버스 탭은 두 모드 모두 막는다.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 8: 문서·스펙·검증 기록, 시나리오, 전체 검증

**Files:**
- Modify: `docs/architecture/modules.md`, `docs/superpowers/specs/2026-10-20-beauty-g-evoto-design.md`, `VALIDATION.md`
- Test: `apple/MellowPhotoTests/EditorScenarioTests.swift`

- [ ] **Step 1: 시나리오 확장**

`EditorScenarioTests.swift`: `demoPortraitCopy()`에 `named name: String = "demo-portrait"` 인자를 더해 `root.appendingPathComponent("\(name).png")`로 쓴다. B~F 시나리오의 `let toned = previewBytes(model)`(G2) 뒤에 추가하고, 그다음 얼굴 단계의 비교 기준을 `grained`로 바꾼다:

```swift
        model.selectTool(.adjust)
        model.beginSliderEdit()
        model.edit(.effect(.grain, 0.5))
        model.endSliderEdit()
        // 그레인만 바꿔도 미리보기가 바뀌어야 한다.
        try await waitUntil { !model.isRendering && self.previewBytes(model) != toned }
        let grained = previewBytes(model)
        model.isComparing = true
        XCTAssertTrue(model.displayImage === model.original, "전체 토글은 원본을 보인다")
        model.toggleSplitCompare()
        XCTAssertEqual(model.compareMode, .split)
        model.toggleSplitCompare()
        XCTAssertEqual(model.compareMode, .off)
```

마지막 저장 앞에 선택 동기화를 더한다(두 번째 사진은 색감만 받아야 한다):

```swift
        await model.importFromFiles([try demoPortraitCopy(named: "demo-second")])
        try await waitUntil { model.session.photos.count == 2 && !model.isImporting }
        let firstID = model.session.photos[0].id
        model.select(firstID)
        try await waitUntil { model.isReady && model.preview != nil }
        for category in SyncCategory.allCases where category != .color {
            model.setSyncCategory(category, enabled: false)
        }
        model.applyToAll()
        let second = model.session.photos[1].document.recipe
        XCTAssertEqual(second.color, recipe.color, "색감만 복사")
        XCTAssertEqual(second.portrait.skin, SkinAdjustments(), "피부는 복사하지 않음")
        XCTAssertEqual(second.effects, EffectAdjustments(), "효과도 복사하지 않음")
```

(`let recipe = model.currentRecipe`는 그 앞에서 첫 사진을 읽은 값이다. 두 번째 사진을 가져온 뒤 첫 사진을 다시 고르고 `exportedPixelSize`로 저장한다.) 마지막 레시피 검증에 `XCTAssertEqual(recipe.effects, EffectAdjustments(grain: 0.5))`를 더한다.

Run: Mac 앱 테스트 → `Executed 78 tests, with 0 failures`.

- [ ] **Step 2: 문서**

`docs/architecture/modules.md`:
- MellowShared 공개 API에 `SkinRefinementKey`, `BodySkinAdjustments`, `BodySkinKey`, `EffectAdjustments`, `EffectKey` 추가. 규칙에 "G 레시피 키(`portrait.skin` 정밀 6종, `bodySkin`, `effects`)는 기본값 0, `AdjustmentRange.skinRefinement`·`bodySkin`(붉은기·톤만 bipolar)" 추가.
- MellowEditing 공개 API에 `SyncCategory` 추가. 규칙에 "일괄 적용은 `applyFromBatch(_:categories:)`가 고른 항목만 복사(기본 전부), 얼굴 의존 항목을 복사할 때만 잠기지 않은 사진의 대상 얼굴을 전체로, 빈 선택은 아무것도 안 함, `applyAuto`는 피부 보정·자동 잡티만" 추가.
- MellowLibrary 규칙에 `applyToAll(from:categories:)`.
- MellowRendering 규칙: 단계 순서를 `skin → bodySkin → feature → makeup → background → shapeWarp → localEdit → geometry → color → detail → look → effect`로, `skin` 단계 설명에 "주름 밝히기(다크서클·팔자·미간, `FaceRegions+Folds` 띠) → 대역 합성(피부 보정·얼룩 고르기·번들거림, 마스크 가중 넓은 평균) → 붉은기", `bodySkin` 단계(인물 마스크 × 가장 큰 얼굴 볼 기준 피부색 − 눈·입, 얼굴·인물 마스크 없으면 건너뜀), `effect` 단계(CIBloom → 회색 잡음 오버레이, 현재 extent), 캐시 상한 "얼굴당 18(9 × 2)·최소 32", `SkinKernels` 커널 5개를 적는다. 테스트 목록에 G 항목 요약.
- 앱 타깃: `BeautyTab`(피부·얼굴·눈·입·피부톤), `SyncMenu`·`CompareDivider`, `AppModel.CompareMode`.

스펙 `2026-10-20-beauty-g-evoto-design.md`: 구현 중 스펙과 달라진 것이 있으면 결정 표에 "(G 구현 중 변경)" 행을 더하고 해당 에이전트 참조 절을 고친다. 없으면 바꾸지 않는다.

- [ ] **Step 3: 전체 검증과 VALIDATION**

Run: `export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer && MELLOW_IOS_TESTS=1 ./scripts/test-apple.sh` → 종료 코드 0(모듈 검사, lint, xcodegen 차이 없음, 패키지 377, iPhone·iPad·Mac 앱 테스트 모두 `TEST SUCCEEDED`). 실패하면 고치고 다시 돌린다. 실행 전 `xcrun simctl list devices booted`로 켜져 있던 시뮬레이터를 적어 두고 실행 뒤 상태가 같은지 확인한다(끄지 않는다).

몸 피부 매끄럽게의 저장 시간 측정: `shared/fixtures/demo-portrait.png`를 긴 변 8000px로 키운 임시 PNG(`sips -Z 8000`으로 만들어 스크래치 폴더에 둠, 저장소에 넣지 않음)에 `bodySkin.smoothing = 1`과 0으로 `PhotoPipeline.renderOriginal` + `makeCGImage` 시간을 각각 3회 재서 중앙값을 적는다(임시 XCTest 또는 스크립트, 커밋하지 않음).

`VALIDATION.md` 끝에 `## 인물 보정 G 피부 정밀·몸 피부·효과·작업 흐름 (2026-10-20)` 절을 F 절과 같은 소제목으로 쓴다: 날짜·커밋·환경 / 자동 검증(명령, 종료 코드, 테스트 수 모듈별, 시뮬레이터 상태) / 자동 테스트가 확인하는 것(스펙 §2 표를 실제 테스트 이름으로) / 구현 중 측정(위 저장 시간, 그레인 평균 밝기 차) / 스펙과 다르게 한 것(없으면 "없음") / 미검증(사용자 확인 필요): 실제 사진의 6종 피부 정밀 품질, 주름 띠 위치(돌린 얼굴), 하얗게 날아간 반사광의 번들거림, 몸 피부가 옷·배경·다른 사람에게 번지는지, 얼굴과 몸의 조명 차, 그레인의 미리보기·저장본 모양 차, 분할선 손잡이 조작감(iPhone), 동기화 메뉴 글자 폭, 실기기. 마지막에 "배포(릴리스 노트·태그·TestFlight)는 G 범위가 아니며 실행하지 않았다"를 적는다. 수행하지 않은 검증을 통과로 쓰지 않는다.

- [ ] **Step 4: 커밋**

```bash
git add docs/architecture/modules.md docs/superpowers/specs/2026-10-20-beauty-g-evoto-design.md VALIDATION.md apple/MellowPhotoTests/EditorScenarioTests.swift
git commit -m "docs: 인물 보정 G 모듈 지도·스펙 반영·검증 기록

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

## 자체 검토 결과

- **스펙 대조:** §1.1 → `EffectKey`·`EffectAdjustments`(Task 1), `SyncCategory`(Task 5), `EffectStage`(Task 3), `SyncMenu`·`CompareDivider`·`AppModel` 상태(Task 6·7), 새 import 없음. §1.2 → `effects` 그룹·두 스키마·README(Task 1), `EditChange.effect`(Task 2). §1.3 → `effect`를 `look` 뒤(Task 3, 순서 배열 갱신). §1.6 효과 → CIBloom·회색 잡음 오버레이·감마 공간·짧은 변 비례·상수 4개(Task 3). §1.7 → `SyncCategory` 9종·`dependsOnFaces`·`applyFromBatch(categories:)`·빈 집합·잠금·대상 얼굴·`applyToAll(categories:)`·앱 상태·메뉴·문구(Task 5·6). §1.8 → `CompareMode`·계산 속성 `isComparing`·`compareSplit`·`toggleSplitCompare`·`setCompareSplit`·`blocksCanvasTouch`·`select` 초기화·캔버스 마스크·분할선·배지·버튼·`Theme` 상수(Task 7). §1.9 → 조정 패널 효과(Task 4), 메뉴·버튼(Task 6·7). §1.10 → 프리셋·일괄·자동 보정(Task 2). §2 → 항등·클램프·결정성·extent(Task 3), 편집·라이브러리(Task 5), 앱 비교·동기화·효과(Task 4·6·7), 시나리오(Task 8). §3 → VALIDATION G 절(Task 8). §4 → Task 목록이 표와 같다.
- **타입 일관성:** `EffectAdjustments.subscript`·`hasEffect`, `EditChange.effect`, `EffectStage.clamped`·`glowRadius`·`grainSize`·`glowed`·`grained`·`grainLayer`, `SyncCategory.all`·`dependsOnFaces`, `EditDocument.applyFromBatch(_:categories:)`, `ProjectSession.applyToAll(from:categories:)`, `AppModel.syncCategories`·`setSyncCategory`·`canApplyToAll`·`CompareMode`·`compareMode`·`compareSplit`·`blocksCanvasTouch`·`toggleSplitCompare`·`setCompareSplit`·`Policy.compareSplitDefault`·`compareSplitRange`, `CompareDivider.fraction(forX:width:)`, `Theme.compareDividerWidth`·`compareHandleSize`·`canvasCoordinateSpace`, `UserMessage.effectTitle`·`syncCategoryTitle`·`appliedToAll(categoryCount:total:)`·`splitCompare`·`splitCompareDone`·`compareBadge`·`compareDividerLabel`을 정의한 Task와 쓰는 Task에서 같게 썼다. 테스트 수: 패키지 367 → 369 → 370 → 374 → 374 → 377 → 377 → 377 → 377, 앱 Mac 74 → 75(T4) → 76(T6) → 78(T7).
- **Review Focus 매핑:** 1→Task 3·8, 2→Task 3, 3→Task 5·6, 4→Task 5, 5→Task 7, 6→Task 1. 모두 테스트 코드가 있다.
- **플레이스홀더 점검:** "TBD/TODO/나중에" 없음. VALIDATION 수치는 실제 실행 결과로 쓴다고 명시했다.
