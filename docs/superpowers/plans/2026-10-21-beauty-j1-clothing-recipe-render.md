# 인물 보정 J1 옷 주름 레시피·렌더 구현 계획

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 레시피에 `clothing`(강도·브러시 획)이 생기고, 렌더 단계 `clothing`이 입은 옷의 중간 대역 휘도 그늘을 줄이며, 실사진 수용 테스트가 보이는 하한·자연스러움 상한·옷 밖 불변·피부 불변을 잰다.

**Architecture:**
- `ClothingAdjustments`는 `BodySkinAdjustments`처럼 최상위 묶음이다.
- `ClothingStage`는 `bodySkin` 바로 뒤에서 돈다. 계산은 세 단계다.
  - 감마 공간 휘도에서 중간 대역(가우스 − guided)을 구한다.
  - 미세 질감 게이트를 곱한다.
  - 옷 마스크를 곱한 ΔY를 세 채널에 더한다.
- `ClothingMask`의 구성은 다음과 같다.
  - 색에 기대는 부분(피부·머리카락)은 매번 Core Image 그래프로 계산한다.
  - 사람 코어·머리 타원·획 비트맵만 만들어 쓰고, 획 비트맵은 `RegionMaskCache`에 둔다.

**Tech Stack:** Swift 5 언어 모드, Core Image(CIColorKernel·CIBoxBlur·CIGaussianBlur·CIMorphologyMaximum·CIAreaAverage), Vision(기존 분석), XCTest.

**Spec:** `docs/superpowers/specs/2026-10-21-beauty-j-clothing-wrinkles-design.md`. J1에 해당하는 절은 1~7절과 9절(앱 테스트 제외), 10절이다.

## 사람이 확인할 것

- **시작 조건.** beauty-g5와 beauty-body가 main에 병합된 뒤 시작한다. beauty-body는 2026-10-22에 병합됐다(`8157172`). 이 브랜치는 그 위로 이미 올렸다. beauty-g5 병합 뒤 한 번 더 `git rebase main` 한다.
- **순서.** Task는 아래 6개다. Task마다 Opus가 구현하고, 리뷰한 뒤 고친다. 끝에 전체 리뷰를 한다.
  1. 레시피
  2. 편집 규칙
  3. 대역 줄이기 커널
  4. 자동 옷 마스크와 단계 연결
  5. 브러시 획 마스크
  6. 실사진 수용 테스트와 CI
- **외부 효과가 있는 단계.** Task 6 끝의 푸시와 `gh workflow run apple-checks.yml --ref beauty-j-cloth`다. Actions 시간을 쓴다. main 병합은 하지 않는다.
- **사용자 승인이 필요한 것.** Task 6이 잰 수용 임계값이다. 임시 상수로 넣고 main 병합 전에 사용자가 승인한다(스펙 결정 표).
- **스펙이 정하지 않아 이 계획이 정한 것.**

| 결정 | 이유 | 바꾸면 비용 |
|---|---|---|
| 임시 임계값은 Task 6에서 잰 세 사진 중 가장 나쁜 값에 여유를 둔다. 하한류는 ×0.85, 상한류는 ×1.15다. 스펙 목표보다 느슨해지면 멈추고 보고한다 | 측정 잡음(Vision 버전)에 흔들리지 않게 하면서 스펙 목표를 넘지 않는다 | 작음 |
| 머리카락 측지 재구성은 128px에서 24회 반복한다. 렌더 시간을 Task 6에서 `record`로 남긴다 | 스펙 7절 상수 그대로다. 느리면 반복을 줄이는 대신 해상도를 낮춘다 | 작음 |

---

## 에이전트 참조

## Global Constraints

- 모든 Swift·xcodebuild 명령 전에 `export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`를 실행한다.
- 작업 위치는 worktree `/Users/mj/IdeaProjects/mellow-photo/.claude/worktrees/beauty-j-cloth`(브랜치 `beauty-j-cloth`)다. 부모 저장소로 `cd`하지 않는다.
- 모듈 의존성 표는 바꾸지 않는다(`./scripts/verify-modules.sh` 통과). MellowShared는 Foundation·CoreGraphics만 import한다. MellowRendering은 SwiftUI·UIKit·AppKit을 import하지 않는다.
- 한 줄에 한 문장을 쓰고 세미콜론은 쓰지 않는다. 매직 넘버는 `RenderTuning`·`EditingPolicy` 명명 상수로 둔다. 한국어 사용자 문구는 앱 타깃에만 둔다(J1은 앱 문구가 없음). 모듈은 `MellowError`만 던진다.
- CI는 Xcode 26.3이다. 섞인 `+` 사슬은 3항 이하로 나누고, CGFloat·Double을 한 식에 섞지 않는다(명시 변환).
- 커밋은 한국어 Conventional Commits다. 끝에 `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`를 붙인다. `git add`는 바꾼 경로만 한다.
- 로컬 iOS 시뮬레이터 실행은 금지다. `MELLOW_IOS_TESTS`를 켜지 않는다.
- 패키지 테스트는 `cd apple && swift test --filter <이름>`이다. 전체는 `./scripts/test-apple.sh`다.
- 줄 번호는 `8accbf6` 기준이다. beauty-g5 병합 뒤 다시 찾는다. `8157172`의 단계 이름 배열은 `skin, bodySkin, feature, makeup, background, chinShade, shapeWarp, localEdit, geometry, color, detail, look, effect`다. J1 뒤에는 `bodySkin` 다음에 `clothing`이 들어간다.
- 기준 테스트 수는 시작 전에 실측해 여기 적는다. 증분은 Shared +4, Editing +5, Rendering +12다.

## Review Focus

1. **얼굴이 하나도 없고 사람 마스크만 있는 사진**(뒷모습)에서 강도 1이어도 바이트가 같아야 한다(획 없음). Task 4 `testNoFaceLeavesImageUnchanged`.
2. **확장 범위 입력**(선형 1.5 같은 HDR 하이라이트)이 옷 밖에서 잘리지 않아야 한다. Task 3 `testExtendedRangeOutsideMaskIsPreserved`.
3. **아주 작은 이미지**(룩 썸네일 64px)에서 σs 바닥 0.8px, guided 반경 ≥1로 유한한 출력이 나와야 한다. Task 3 `testTinyImageStaysFinite`.
4. **해상도가 달라도 같은 정도로 펴져야 한다**(미리보기 대 원본). 절반 해상도의 중간 대역 비가 원 해상도와 ±0.1 안이어야 한다. Task 3 `testRelativeScaleMatchesAcrossResolutions`.
5. **점 하나짜리 획**(탭)은 지름 2r 원으로 칠해져야 한다. **사진 가장자리 밖 좌표**의 획은 잘려 그려지고 오류가 나지 않아야 한다. Task 5 `testSinglePointStrokePaintsDisc`, `testStrokeOutsideExtentIsClipped`.

---

### Task 1: 레시피 `clothing`

**Files:**
- Create: `apple/Sources/MellowShared/API/ClothingAdjustments.swift`
- Modify: `apple/Sources/MellowShared/API/EditRecipe.swift`(속성, init, CodingKeys, decode, encode, `dependsOnPerson`, `allValuesFinite`)
- Modify: `apple/Sources/MellowShared/API/AdjustmentRange.swift`
- Modify: `apple/Sources/MellowShared/API/Preset.swift`(`PresetValues`, :8·18·39·48·61·77)
- Modify: `shared/recipe-schema/edit-recipe.v2.schema.json`(최상위 `clothing`), `shared/recipe-schema/README.md`(:24 최상위 목록, :56 프리셋, :79 범위 표)
- Modify: `shared/recipe-schema/session-file.v2.schema.json`(프리셋 values에 `clothing` ref, :42 옆)
- Test: `apple/Tests/MellowSharedTests/EditRecipeCodingTests.swift`, `apple/Tests/MellowSharedTests/RecipeSchemaTests.swift`, `apple/Tests/MellowLibraryTests/SessionFileMigrationTests.swift`

**Interfaces:**
- Produces:
  - `public enum ClothingKey: String, CaseIterable, Codable, Sendable { case wrinkles }`
  - `public struct ClothingStroke: Codable, Equatable, Sendable { points: [NormalizedPoint], radius: Double, erase: Bool }`. 멤버와이즈 public init이다.
  - `public struct ClothingAdjustments: Codable, Equatable, Sendable`
    - `wrinkles: Double`, `strokes: [ClothingStroke]`
    - `init(wrinkles: Double = 0, strokes: [ClothingStroke] = [])`
    - `subscript(key: ClothingKey) -> Double`
    - `hasEffect`, `hasPaint`, `numericValues`
  - `EditRecipe.clothing: ClothingAdjustments`
  - `AdjustmentRange.clothing(_ key: ClothingKey) -> ClosedRange<Double>`(= `unit`)
  - `PresetValues.clothing: ClothingAdjustments`. 획은 늘 비어 있다.

- [ ] **Step 1: 실패하는 테스트를 쓴다**

`EditRecipeCodingTests`에 더한다:

```swift
func testClothingRoundTripsAndDefaultsWhenMissing() throws {
    var recipe = EditRecipe()
    recipe.clothing = ClothingAdjustments(
        wrinkles: 0.6,
        strokes: [ClothingStroke(points: [NormalizedPoint(x: 0.2, y: 0.3), NormalizedPoint(x: 0.4, y: 0.35)], radius: 0.03, erase: false)])
    let data = try JSONEncoder().encode(recipe)
    XCTAssertEqual(try JSONDecoder().decode(EditRecipe.self, from: data).clothing, recipe.clothing)
    let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    let clothing = try XCTUnwrap(json["clothing"] as? [String: Any])
    XCTAssertEqual(Set(clothing.keys), ["wrinkles", "strokes"])
    let legacy = try JSONDecoder().decode(EditRecipe.self, from: Data(#"{"schemaVersion":2}"#.utf8))
    XCTAssertEqual(legacy.clothing, ClothingAdjustments(), "J 이전 파일은 옷 주름 0, 획 없음")
}

func testClothingDependsOnPersonOnlyWithStrength() {
    var recipe = EditRecipe()
    recipe.clothing.strokes = [ClothingStroke(points: [NormalizedPoint(x: 0.5, y: 0.5)], radius: 0.02, erase: false)]
    XCTAssertFalse(recipe.dependsOnPerson, "획만 있고 강도 0이면 효과 없음")
    recipe.clothing.wrinkles = 0.5
    XCTAssertTrue(recipe.dependsOnPerson)
    XCTAssertTrue(recipe.clothing.hasPaint)
    XCTAssertEqual(AdjustmentRange.clothing(.wrinkles), AdjustmentRange.unit)
}

func testPresetCarriesClothingStrengthButNotStrokes() {
    var recipe = EditRecipe()
    recipe.clothing = ClothingAdjustments(wrinkles: 0.4, strokes: [ClothingStroke(points: [NormalizedPoint(x: 0.1, y: 0.1)], radius: 0.02, erase: true)])
    let values = PresetValues(of: recipe)
    XCTAssertEqual(values.clothing, ClothingAdjustments(wrinkles: 0.4))
}
```

`testEveryNewScalarIsCheckedForFiniteness`의 `paths`에 `\.clothing.wrinkles`를 더한다. 다음 테스트도 더한다:

```swift
func testClothingStrokeValuesAreCheckedForFiniteness() {
    var recipe = EditRecipe()
    recipe.clothing.strokes = [ClothingStroke(points: [NormalizedPoint(x: .nan, y: 0.5)], radius: 0.02, erase: false)]
    XCTAssertFalse(recipe.allValuesFinite)
    recipe.clothing.strokes = [ClothingStroke(points: [NormalizedPoint(x: 0.5, y: 0.5)], radius: .infinity, erase: false)]
    XCTAssertFalse(recipe.allValuesFinite)
}
```

`RecipeSchemaTests.swift:71`의 절 목록에 `"clothing"`을 `"body"` 다음에 넣는다. `SessionFileMigrationTests`의 v1 디코딩 테스트에 `XCTAssertEqual(recipe.clothing, ClothingAdjustments())`를 더한다.

- [ ] **Step 2: 실패를 확인한다**

`cd apple && swift test --filter "EditRecipeCodingTests|RecipeSchemaTests|SessionFileMigrationTests"`를 돌린다. 기대값은 컴파일 오류(`ClothingAdjustments` 없음)다.

- [ ] **Step 3: 구현한다**

- `ClothingAdjustments.swift`
  - 디코딩은 `decodeIfPresent ?? 0`, `?? []`다.
  - `numericValues`는 `[wrinkles]` 뒤에 획마다 `radius`와 점의 x·y를 붙인 것이다.
- `EditRecipe`
  - `dependsOnPerson`에 `|| clothing.hasEffect`를 더한다.
  - `allValuesFinite`는 `groups += clothing.numericValues`로 따로 붙인다.
- `PresetValues(of:)`는 `ClothingAdjustments(wrinkles: recipe.clothing.wrinkles)`다.
- 스키마 `clothing` 절은 스펙 4절 JSON 그대로다.
- README에 적을 내용:
  - 최상위 목록에 `clothing`(옷 주름 0~1과 브러시 획)을 더한다.
  - 프리셋 줄에 `clothing`(강도만)을 더한다.
  - 범위 표에 `clothing.wrinkles 0 … 1`을 더한다.
  - 획 규칙 한 문단: 원본 정규화 좌표이고, 칠한 획이 있으면 그곳에만 적용하고, 지우기는 늘 뺀다. 동기화·프리셋은 획을 나르지 않는다.

- [ ] **Step 4: 통과를 확인한다**

같은 명령을 다시 돌린다. 기대값은 PASS다.

- [ ] **Step 5: 커밋한다**

```bash
git add apple/Sources/MellowShared shared/recipe-schema apple/Tests/MellowSharedTests apple/Tests/MellowLibraryTests
git commit -m "feat(shared): 옷 주름 레시피 묶음과 스키마 추가"
```

### Task 2: 편집 규칙

**Files:**
- Modify: `apple/Sources/MellowEditing/API/EditChange.swift`(`case clothing(ClothingKey, Double)`, `affectsGeometry`는 false)
- Modify: `apple/Sources/MellowEditing/API/EditingPolicy.swift`
- Modify: `apple/Sources/MellowEditing/API/EditDocument.swift`(:566 apply, :395 동기화 `.body`, :719 근처에 획 편집)
- Modify: `apple/Sources/MellowEditing/API/SyncCategory.swift`(주석만: `.body`가 옷 주름 강도도 나른다)
- Test: `apple/Tests/MellowEditingTests/EditDocumentTests.swift`

**Interfaces:**
- Consumes: Task 1 타입.
- Produces:
  - `EditingPolicy.clothingRange(_ key: ClothingKey) -> ClosedRange<Double>`
  - `EditingPolicy.clothingStrokeMaxPoints = 256`, `EditingPolicy.clothingMaxStrokes = 64`
  - `@discardableResult EditDocument.appendClothingStroke(_ stroke: ClothingStroke) -> Bool`. 상한을 넘거나 점이 0개면 false를 돌려주고 바꾸지 않는다. 반지름은 `EditingPolicy.clothingStrokeRadiusRange`(0.008…0.2)로 자르고 점 좌표는 0…1로 자른다. 성공하면 체크포인트 하나다.
  - `EditDocument.clearClothingStrokes()`. 획이 없으면 체크포인트하지 않는다.

- [ ] **Step 1: 실패하는 테스트를 쓴다**

```swift
func testClothingStrengthIsClamped() {
    var document = EditDocument()
    document.apply(.clothing(.wrinkles, 1.7))
    XCTAssertEqual(document.recipe.clothing.wrinkles, 1)
}

func testClothingStrokeIsOneUndoStep() {
    var document = EditDocument()
    let stroke = ClothingStroke(points: [NormalizedPoint(x: 0.2, y: 0.2), NormalizedPoint(x: 1.3, y: 0.4)], radius: 0.5, erase: false)
    XCTAssertTrue(document.appendClothingStroke(stroke))
    XCTAssertEqual(document.recipe.clothing.strokes.first?.points.last, NormalizedPoint(x: 1, y: 0.4))
    XCTAssertEqual(document.recipe.clothing.strokes.first?.radius, 0.2)
    document.undo()
    XCTAssertTrue(document.recipe.clothing.strokes.isEmpty)
}

func testClothingStrokeLimitsAreRefused() {
    var document = EditDocument()
    XCTAssertFalse(document.appendClothingStroke(ClothingStroke(points: [], radius: 0.02, erase: false)))
    let many = (0..<(EditingPolicy.clothingStrokeMaxPoints + 1)).map { NormalizedPoint(x: Double($0) / 1000, y: 0.5) }
    XCTAssertFalse(document.appendClothingStroke(ClothingStroke(points: many, radius: 0.02, erase: false)))
    let dot = ClothingStroke(points: [NormalizedPoint(x: 0.5, y: 0.5)], radius: 0.02, erase: false)
    for _ in 0..<EditingPolicy.clothingMaxStrokes { XCTAssertTrue(document.appendClothingStroke(dot)) }
    XCTAssertFalse(document.appendClothingStroke(dot))
}

func testClearClothingStrokes() {
    var document = EditDocument()
    document.appendClothingStroke(ClothingStroke(points: [NormalizedPoint(x: 0.5, y: 0.5)], radius: 0.02, erase: true))
    document.clearClothingStrokes()
    XCTAssertTrue(document.recipe.clothing.strokes.isEmpty)
    document.undo()
    XCTAssertEqual(document.recipe.clothing.strokes.count, 1)
}

func testSyncBodyCopiesClothingStrengthKeepsStrokesAndDoesNotLock() {
    // 받는 사진에 획 하나, 보내는 값 wrinkles 0.7
    // 기존 동기화 테스트의 도우미로 [.body]를 적용한다
    // 기대: wrinkles 0.7, 받는 사진의 획 그대로
    // 획이 있어도 .faceShape·.bodyShape 변경이 거절되지 않음(isGeometryLocked == false)
}
```

마지막 테스트 본문은 `EditDocumentTests`의 기존 동기화 도우미(`merged`/`applyFromBatch`를 부르는 것)를 써서 위 네 단정을 그대로 넣는다.

- [ ] **Step 2: 실패를 확인한다**

`cd apple && swift test --filter EditDocumentTests`를 돌린다. 기대값은 컴파일 오류다.

- [ ] **Step 3: 구현한다**

- apply 분기는 `updated.clothing[key] = EditingPolicy.clamped(value, to: EditingPolicy.clothingRange(key))`다.
- 동기화 `if applied.contains(.body)` 안에 `updated.clothing.wrinkles = values.clothing.wrinkles`를 더한다.
- 획 편집은 `recipe.operations`를 쓰지 않으므로 `hasLocalEdits` 잠금에 들지 않는다.

- [ ] **Step 4: 통과를 확인한다**

같은 명령을 다시 돌린다. 기대값은 PASS다.

- [ ] **Step 5: 커밋한다**

```bash
git add apple/Sources/MellowEditing apple/Tests/MellowEditingTests
git commit -m "feat(editing): 옷 주름 강도와 브러시 획 편집 규칙 추가"
```

### Task 3: 대역 줄이기 커널 `ClothingKernels`

**Files:**
- Create: `apple/Sources/MellowRendering/Domain/ClothingKernels.swift`
- Modify: `apple/Sources/MellowRendering/API/RenderTuning.swift`("옷" 절에 스펙 7절 상수 전부, 기존 절 뒤에, 문서 주석 한 줄씩)
- Test: `apple/Tests/MellowRenderingTests/ClothingStageTests.swift`(새 파일)

**Interfaces:**
- Produces:
  - `struct ClothingKernels`. `static let shared`이고, 커널 생성 실패는 nil 속성으로 들고 있다가 호출 때 `MellowError.renderFailed`를 던진다. `SkinKernels`와 같은 형태다.
  - `static func flattened(_ image: CIImage, weight: CIImage, strength: Double, extent: CGRect, tuning: RenderTuning) throws -> CIImage`
    - 입력은 선형이다.
    - 안에서 sRGB 인코딩을 하고 Y, Ys, guided base, 질감 게이트를 거쳐 ΔY를 더한다.
    - 그 뒤 선형으로 되돌린다.
    - `weight`는 0…1 회색 마스크(옷 마스크)이고 `strength`는 `wrinkles`다.
  - `static func midBandSigmas(shortSide: CGFloat, tuning: RenderTuning) -> (fine: CGFloat, coarse: CGFloat)`. 테스트와 수용 측정이 같은 σ를 쓴다.

guided 필터 정의는 스펙 5절 2항(상자 평균 네 번 + 색 커널)이다. `CIBoxBlur` 반지름은 `max(1, round(r))`이다. 경계는 `clampedToExtent()` 뒤 `cropped(to:)`로 처리한다.

- [ ] **Step 1: 실패하는 테스트를 쓴다**

합성 천 도우미를 `ClothingStageTests` 안에 둔다. 512×512 회색 0.55(sRGB) 바탕이다. 여기에 진폭 0.08, 주기 짧은 변 × 0.02인 사인파 접힘을 대각선으로 더한다. 1px 체커 결(진폭 0.02)도 더한다. 선형으로 디코드해 준다.

```swift
func testFlattenReducesFoldsAndKeepsWeave() throws {
    let (fabric, extent) = Self.fabric(size: 512)
    let out = try ClothingKernels.flattened(fabric, weight: Self.white(extent), strength: 1, extent: extent, tuning: RenderTuning())
    let s = ClothingKernels.midBandSigmas(shortSide: 512, tuning: RenderTuning())
    XCTAssertLessThan(try Self.midBandRMS(out, s) / Self.midBandRMS(fabric, s), 0.8, "접힘 진폭이 줄어든다")
    XCTAssertGreaterThan(try Self.fineRMS(out, s) / Self.fineRMS(fabric, s), 0.9, "1px 결은 남는다")
}

func testZeroWeightIsIdentityAndZeroStrengthIsIdentity() throws { /* 두 경우 모두 바이트 동일 */ }

func testShadowsLiftMoreThanHighlightsDrop() throws {
    // 접힘 골(어두운 곳)의 평균 ΔY > 접힘 마루의 평균 |ΔY|
}

func testExtendedRangeOutsideMaskIsPreserved() throws {
    // 왼쪽 절반 선형 1.5, 오른쪽 천. weight는 오른쪽만 1.
    // 왼쪽 픽셀(RGBAf로 렌더)이 1.5 ± 1e-3
}

func testTinyImageStaysFinite() throws {
    // 64×64 천, strength 1 → 모든 픽셀 유한, 0 이상
}

func testRelativeScaleMatchesAcrossResolutions() throws {
    // 1024 천과 그것을 512로 줄인 천: 중간 대역 비 차이 ≤ 0.1
}
```

`midBandRMS`는 `Gauss(σs) − Gauss(σL)`의 RMS다. `fineRMS`는 `Y − Gauss(σs)`의 RMS다. 둘 다 sRGB 휘도에서 잰다. `RenderingTestSupport.luma`와 `bandVariances` 형태를 재사용하고, 맞지 않으면 이 파일에 private 도우미로 둔다.

- [ ] **Step 2: 실패를 확인한다**

`cd apple && swift test --filter ClothingStageTests`를 돌린다. 기대값은 컴파일 오류다.

- [ ] **Step 3: 구현한다**

`ClothingKernels.flattened`와 커널 두 개를 만든다.
- `guidedCoefficients(mean, meanSquare, epsilon) -> (a, b)`
- `flatten(rgb, Y, Ys, meanA, meanB, fineEnergy, weight, strength, shadowGain, highlightGain, textureLow, textureHigh)`

`bp = Ys − (meanA·Ys + meanB)`이고 ΔY는 스펙 5절 5항이다. 출력은 자르지 않는다.

- [ ] **Step 4: 통과를 확인한다**

같은 명령을 다시 돌린다. 기대값은 6개 PASS다.

- [ ] **Step 5: 커밋한다**

```bash
git add apple/Sources/MellowRendering apple/Tests/MellowRenderingTests/ClothingStageTests.swift
git commit -m "feat(rendering): 옷 주름 중간 대역 줄이기 커널 추가"
```

### Task 4: 자동 옷 마스크와 `ClothingStage`

**Files:**
- Create: `apple/Sources/MellowRendering/Domain/ClothingMask.swift`, `apple/Sources/MellowRendering/Domain/ClothingStage.swift`
- Modify: `apple/Sources/MellowRendering/API/RenderPipeline.swift`(`BodySkinStage()` 바로 뒤에 `ClothingStage()`, 문서 주석의 단계 목록)
- Modify: `apple/Sources/MellowRendering/Domain/BodySkinStage.swift`. `product`·`inverted`가 private이면 internal로 바꿔 함께 쓴다(동작 불변).
- Test: `ClothingStageTests.swift`, `apple/Tests/MellowRenderingTests/RenderPipelineTests.swift`(단계 이름 배열에 `"clothing"`을 `"bodySkin"` 다음에)

**Interfaces:**
- Consumes:
  - Task 3 `ClothingKernels.flattened`
  - `FaceRegions.cheekAverages`, `FaceRegions.wholeFaceMask`
  - `BackgroundStage.personMask`
  - `context.personMask`, `context.faces`
  - `context.analysis.personInstances: [CIImage]`, `context.analysis.faceInstances: [Int: Int]`(얼굴 인덱스 → 인스턴스 인덱스, `8157172`에 있음). `RenderContext.analysis`는 public이다
- Produces:
  - `enum ClothingMask`
  - `static func make(encoded: CIImage, context: RenderContext) throws -> CIImage?`
    - 0…1 회색, extent는 `context.extent`다.
    - 얼굴도 칠한 획도 없으면 nil이다.
    - Task 5가 획을 더한다.
  - `struct ClothingStage: RenderStage`, `name = "clothing"`
    - `wrinkles`를 `AdjustmentRange.clothing`으로 자른다.
    - 0이면 입력 그대로다.
    - 마스크가 nil이면 입력 그대로다.
    - 나머지는 `ClothingKernels.flattened`를 부른다.

마스크 식은 스펙 6절이다(사람 코어 P, 얼굴 있는 인스턴스, 피부 K, 머리 H, 머리카락 R, 자동 영역 A). 색 거리 커널은 `ClothingMaskKernels`(같은 파일 private)에 둔다. 넣을 커널은 다음 두 가지다.
- 피부: 볼 평균 Cb·Cr·Y, 공간 감쇠 중심·반경
- 머리카락 색

머리카락 측지 재구성:
1. 128px로 줄인다.
2. 다음을 `clothingHairGrowSteps`번 반복한다.
   - `seed = min(CIMorphologyMaximum(seed, radius 1), hairColor > 0.35)`
3. 늘려서 색 가중과 곱한다.

- [ ] **Step 1: 실패하는 테스트를 쓴다**

`SyntheticFace.makeWithBody()`(얼굴 + 몸)와 `RenderingTestSupport.personMask`로 합성 사진을 만든다. 몸통 사각형 안에 Task 3의 천 무늬를 칠하고, 얼굴은 볼 색으로 칠한다.

```swift
func testStageNameAndZeroIsIdentity() throws { /* name == "clothing", wrinkles 0 → 바이트 동일 */ }

func testStageFlattensTorsoButNotOutsidePersonOrFace() throws {
    // wrinkles 1
    // 몸통 사각형 중간 대역 비 < 0.85
    // 사람 마스크 밖 최대 |ΔRGB| ≤ 1(8비트)
    // 얼굴 상자 안 평균 |ΔY| ≤ 0.5(8비트)
}

func testSkinColouredArmIsProtected() throws {
    // 몸통 옆에 볼과 같은 색의 팔 사각형(접힘 무늬 포함)
    // 팔 안 평균 |ΔY| ≤ 0.5
}

func testNoFaceLeavesImageUnchanged() throws {
    // 사람 마스크 있음, faces 빈 배열, wrinkles 1, 획 없음 → 바이트 동일
}

func testDeterministic() throws { /* 두 번 렌더 바이트 동일 */ }
```

`RenderPipelineTests`의 기대 배열에 `"clothing"`을 넣는다.

- [ ] **Step 2: 실패를 확인한다**

`cd apple && swift test --filter "ClothingStageTests|RenderPipelineTests"`를 돌린다. 기대값은 FAIL이다.

- [ ] **Step 3: 구현한다**

`ClothingMask.make`와 `ClothingStage`를 만들고 파이프라인에 넣는다.

- [ ] **Step 4: 통과를 확인한다**

같은 명령을 다시 돌린다. 이어서 `cd apple && swift test`로 전체 패키지 회귀가 없는지 본다.

- [ ] **Step 5: 커밋한다**

```bash
git add apple/Sources/MellowRendering apple/Tests/MellowRenderingTests
git commit -m "feat(rendering): 자동 옷 마스크와 옷 주름 렌더 단계 추가"
```

### Task 5: 브러시 획 마스크

**Files:**
- Modify: `apple/Sources/MellowRendering/Domain/ClothingMask.swift`
- Modify: `apple/Sources/MellowRendering/Domain/RegionMaskCache.swift`(사진당 2개를 상한·주석에 반영. `RegionMaskKey`에 획용 생성자를 더하고, 키 값은 extent·크기·획 숫자다)
- Test: `ClothingStageTests.swift`, `apple/Tests/MellowRenderingTests/RegionMaskCacheTests.swift`(있으면 상한 단정 갱신)

**Interfaces:**
- Consumes: Task 4 `ClothingMask.make`
- Produces:
  - `static func strokeRaster(_ strokes: [ClothingStroke], erase: Bool, extent: CGRect, maxDimension: Int, cache: RegionMaskCache?) -> CIImage?`
    - `CGContext` 회색 비트맵에 둥근 끝·둥근 이음 선을 그린다. 선 폭은 2r × 짧은 변이다.
    - 점 하나면 원을 그린다.
    - 가장자리는 r × `clothingStrokeFeather`로 흐린다.
    - 해당하는 획이 없으면 nil이다.
  - `make`의 획 규칙(스펙 6절 "획"): `hasPaint`면 `Paint × (1−K) × (1−H) × (1−R)`, 아니면 A다. 끝에 `× (1 − Erase)`를 곱한다.
  - 칠한 획이 있으면 얼굴이 없어도 nil이 아니다.

- [ ] **Step 1: 실패하는 테스트를 쓴다**

```swift
func testPaintRestrictsEffectToStroke() throws {
    // 자동 영역이 몸통 전체인 합성 사진에 몸통 왼쪽 절반만 칠한 획 → 오른쪽 절반 바이트 동일, 왼쪽 중간 대역 비 < 0.85
}

func testPaintWorksOutsidePersonAndWithoutFaces() throws {
    // faces 빈 배열, 사람 마스크 없음, 배경의 천 무늬 위 칠한 획 → 획 안 중간 대역 비 < 0.85, 획 밖 바이트 동일
}

func testEraseRemovesAutomaticArea() throws {
    // 획 없음 + 몸통 위 지우기 획 하나 → 지우기 획 안(가장자리 흐림 폭 제외) 최대 |ΔRGB| ≤ 1
}

func testSinglePointStrokePaintsDisc() throws {
    // 점 하나 (0.5,0.5) r 0.05 → strokeRaster 중심 > 0.9, 중심에서 r×1.5 밖 < 0.05
}

func testStrokeOutsideExtentIsClipped() throws {
    // 점 (-0.2, 0.5)→(0.1, 0.5) → 오류 없이 왼쪽 가장자리에만 값
}

func testStrokeRasterIsCached() throws {
    // 같은 획으로 두 번 make → cache.count 증가는 첫 번째에만
}
```

- [ ] **Step 2: 실패를 확인한다**

`cd apple && swift test --filter ClothingStageTests`를 돌린다. 기대값은 FAIL이다.

- [ ] **Step 3: 구현한다**

`strokeRaster`를 만들고 `make`에 연결한다. 캐시 상한 계산을 고친다.

- [ ] **Step 4: 통과를 확인한다**

같은 명령을 돌리고 `swift test`로 전체를 확인한다.

- [ ] **Step 5: 커밋한다**

```bash
git add apple/Sources/MellowRendering apple/Tests/MellowRenderingTests
git commit -m "feat(rendering): 옷 주름 칠하기·지우기 획 마스크 추가"
```

### Task 6: 실사진 수용 테스트와 CI

**Files:**
- Create: `apple/Tests/MellowRenderingTests/ClothingAcceptanceTests.swift`
- Modify: `VALIDATION.md`. "J1 옷 주름" 절을 두고 측정값·임시 임계값·사용자 승인 대기를 적는다. 사람 확인 영역만 쓴다.
- 건드리지 않음: `RealPhotoAcceptanceTests.swift`, `RenderingTestSupport.swift`(도우미가 필요하면 새 파일 안 private)

**Interfaces:**
- Consumes:
  - `PeopleFixtures.url`, `ImageLoader`
  - `PhotoPipeline(analyzer: VisionFaceAnalyzer(), personAnalyzer: VisionPersonAnalyzer(), bodyAnalyzer: VisionBodyAnalyzer(), instanceAnalyzer: VisionPersonInstanceAnalyzer(), tuning:)`의 `prepare`·`preparedAnalysis`(`ShapeTestSupport.swift`의 `RealBodyPhoto.prepared`와 같은 방식)
  - `DisplayScale`
  - `ClothingMask.make`, `ClothingKernels.midBandSigmas`
- Produces:
  - `enum Visibility`(파일 안, `clothingMidBandRatio`, `clothingMeanAbsLuma`)
  - `enum Naturalness`(`clothingFineRatio`, `clothingMidBandFloor`, `clothingP99Luma`, `clothingMeanLift`, `clothingOutsideMax` = 1, `clothingSkinMean` = 0.5, `clothingSkinP99` = 3, `clothingHeadMean` = 0.5)
  - `record(item, metric, value)` 출력 형식은 `RealPhotoAcceptanceTests`와 같다(`acceptance <item> <metric>=<v>`).

사진 셋은 `group-01.jpg`, `couple-01.jpg`, `demo-portrait.png`다.
- `ClothingPhoto` 클래스를 이 파일에 둔다. `RealBodyPhoto.prepared`처럼 사진마다 한 번 준비해 잠금 캐시에 둔다. 들고 있는 것은 image, analysis(얼굴·사람 마스크·인스턴스·`faceInstances`)다. `group-01.jpg`·`couple-01.jpg`는 `Fixtures/people`, `demo-portrait.png`는 `Fixtures`에서 읽는다.
- 측정 영역 C는 `ClothingMask.make` > 0.5(강도 1, 획 없음)인 곳이다. C가 짧은 변² × 0.02보다 작으면 그 사진은 `XCTSkip`한다. 셋 다 건너뛰면 실패다.

- [ ] **Step 1: 측정만 하는 테스트를 쓴다**

임계값 자리는 스펙 9절 목표값이다.

```swift
func testClothingWrinklesAreVisibleButNatural() throws
// 사진마다:
//   mid ≤ Visibility.clothingMidBandRatio(0.80), meanAbs ≥ Visibility.clothingMeanAbsLuma(2.0)
//   fine ≥ Naturalness.clothingFineRatio(0.80), mid ≥ Naturalness.clothingMidBandFloor(0.45)
//   p99 ≤ Naturalness.clothingP99Luma(30), meanSigned ≤ Naturalness.clothingMeanLift(6.4)
func testOutsidePersonIsUnchanged() throws      // 사람 마스크 < 0.05(3px 침식) 최대 |ΔRGB| ≤ 1
func testSkinIsUnchanged() throws               // FaceRegions.skinMask와 몸 피부 영역 평균 ≤ 0.5, p99 ≤ 3
func testHairAndHeadAreUnchanged() throws       // 머리 타원 H > 0.6 평균 ≤ 0.5
func testBrushOnWallAndEraseOnSweater() throws  // group-01: 벽 위 칠한 획 밖 불변, 파란 스웨터 위 지우기 획 안 최대 ≤ 1
func testRenderTimeIsRecorded() throws          // group-01 미리보기 해상도에서 강도 0과 1 렌더 시간 비를 record만 한다
```

모든 값을 `record`한다. 브러시 테스트의 스웨터 위치는 group-01에서 가운데 사람 얼굴 상자 아래 1.5 얼굴 높이 지점이다(라벨 순서로 가운데 얼굴).

- [ ] **Step 2: 돌려서 잰다**

`cd apple && swift test --filter ClothingAcceptanceTests 2>&1 | grep acceptance`를 돌린다.
- 기대값은 PASS다. 스펙 목표 안이어야 한다.
- 목표를 못 넘으면 Task 3~4의 상수를 바꾸지 말고 멈춘다. 측정값을 보고한다(사용자 판단).

- [ ] **Step 3: 임시 임계값을 넣는다**

측정한 가장 나쁜 값에 계획 결정 표의 여유를 준다. 하한류는 ×0.85, 상한류는 ×1.15다. 스펙 목표보다 느슨해지면 목표값을 쓴다. 각 상수 위에 "임시, 사용자 승인 대기(J1 측정값 …)" 주석을 단다.

- [ ] **Step 4: VALIDATION에 적는다**

`VALIDATION.md`에 "J1 옷 주름" 절을 쓴다. 담을 것은 다음과 같다.
- 사진별 측정값 표
- 임시 임계값
- 렌더 시간 비
- 범위 밖 항목(무늬 옷·깊은 구김·머리카락과 같은 색 옷)
- "사용자 승인 대기"
- 수행하지 않은 기기 확인은 "미수행"으로 적는다.

- [ ] **Step 5: 전체 검증을 한다**

`export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer && ./scripts/test-apple.sh`를 돌린다. 로컬은 iOS 테스트를 건너뛴다. 기대값은 lint·모듈·xcodegen 검사 통과, `swift test` 전부 PASS, Mac 앱 테스트 `TEST SUCCEEDED`다.

- [ ] **Step 6: 커밋한다**

```bash
git add apple/Tests/MellowRenderingTests/ClothingAcceptanceTests.swift VALIDATION.md
git commit -m "test(rendering): 옷 주름 실사진 수용 테스트와 검증 기록 추가"
```

- [ ] **Step 7: 푸시하고 CI를 확인한다**

```bash
git push -u origin beauty-j-cloth
gh workflow run apple-checks.yml --ref beauty-j-cloth
gh run list --workflow apple-checks.yml --branch beauty-j-cloth --limit 1
```

기대값은 마지막 run의 conclusion이 `success`인 것이다. 실패하면 로그(`gh run view <id> --log-failed`)로 고치고 다시 돌린다. CI 결과를 VALIDATION에 한 줄로 적고 커밋·푸시한다.
