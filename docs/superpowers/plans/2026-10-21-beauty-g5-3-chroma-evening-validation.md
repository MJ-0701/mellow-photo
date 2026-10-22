# 인물 보정 G5-3 얼룩 색 고르기·하네스 실측·검증 구현 계획

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 레시피 키 `portrait.skin.chromaEvening`과 휘도를 지키는 얼룩 색 고르기(얼굴 폭 2.5% 흐림의 Cb·Cr을 12% 피부 평균 쪽으로)를 대역 합성 커널에 더한다. 원터치 표에 0.5/0.5/0.35를 넣고 심은 보라 얼룩으로 단언한다. Evoto 하네스를 돌려 결과 표를 VALIDATION에 옮기고 G5 전체의 문서(모듈 지도·G4 스펙 3.2·README)를 마무리한다.

**Architecture:** 키는 `SkinRefinementKey.chromaEvening`(`toneEvening` 뒤). 렌더는 `FrequencySeparation.refined`의 `toneMix` 커널 확장(입력 `blotchBlur` 하나, 인자 `evenChroma` 하나)이라 새 단계·마스크·캐시가 없다. 화면 값(sRGB 감마)에서 BT.601 역변환의 Cb·Cr 열만 써 화면 Y를 보존하고 선형 RGB로 되돌린다.

**Tech Stack:** Swift 5.9 tools / Swift 5 언어 모드, Core Image(CIKL 색 커널), Vision(테스트), XCTest.

**Spec:** `docs/superpowers/specs/2026-10-21-beauty-g5-evoto-calibration-design.md` (1.1, 1.2 얼룩 색 고르기 행, 2절 `chromaEvening`, 3절, 6절, 7절, 8절). 선행: G5-2 전부 머지.

## 사람이 확인할 것

- **순서.** Task 1 키·표·화면 이름 → 2 커널·대역 합성 → 3 심은 얼룩 수용 → 4 하네스 실행·VALIDATION·문서. 4개 Task, Task마다 Opus 구현 → 리뷰 → 수정, 끝에 전체 리뷰.
- **외부 효과가 있는 단계.** Task 4의 하네스 실행(이 Mac 로컬 이미지, 약 16분). 푸시·태그·버전 올림 없음(코디네이터 몫).
- **스펙이 정하지 않아 이 계획이 정한 것.**

| 결정 | 이유 | 바꾸면 비용 |
|---|---|---|
| 얼룩 색 고르기의 흐림 반지름 상수 이름은 `chromaBlotchFraction`(0.025, G5-3 구현 중 0.06에서 변경), 최대 배율은 `chromaEveningMax`(1.0) | 스펙 6절 | 작음 |
| `chromaEvening`만 0이 아니고 `toneEvening`·`shine`이 0이면 `toneMix` 경로로 가되 `even`·`shine`은 0이다(`smoothed` 경로가 아님) | 커널 하나로 네 값을 다룬다. "셋 다 0이면 `smoothed`와 같은 바이트" 규칙은 유지된다 | 작음 |
| 하네스 실측에서 `chromaEvening`이 Cr 표준편차 비 하한(0.6에서 ≥ 0.80)을 깨면 표 값을 0.5 → 0.3으로 내리고, 그래도 깨면 표 값 0으로 두고 키는 남긴다 | 스펙 판정 7의 되돌리기 규칙 | 작음 |
| VALIDATION의 하네스 표는 묶음 네 개(retouch·spots·dark-circles·wrinkles)의 중앙값만 옮기고 쌍별 표는 스크래치패드에 둔다 | VALIDATION은 사람이 읽는 영역이다 | 작음 |

- **범위 밖.** 다른 플랫폼 구현, 버전 올림·배포(코디네이터), 2세대 점 지우기.
- **위험.** 자연 홍조가 있는 데모 사진에서 색 고르기가 볼 붉은기를 눌러 `crSigmaRatio` 하한에 걸릴 수 있다. 대응: 위 결정의 표 값 인하 규칙.
- **사용자 조치.** VALIDATION의 하네스 표를 보고 1.4.1 배포 여부를 정한다(코디네이터에게 알림). 기기 확인 항목은 스펙 "사용자 조치".

---

## 에이전트 참조

## Global Constraints

G5-1 계획의 Global Constraints를 그대로 따른다(브랜치·`DEVELOPER_DIR`·건드리지 않는 변형 파일·모듈 표 불변·lint·커밋 서명·`git add` 경로 제한·**로컬 iOS 시뮬레이터 금지**·푸시 금지). 이 계획에서 다른 것:

- 시작 조건: G5-2 머지(`SkinRefinementKey.spots`·`SpotRemoval` 존재). 기준 테스트 수는 **시작 전에 실측해 이 줄에 적는다**(G5-2 뒤 추정 패키지 472, Mac 99). 이 계획이 더하는 수: **Shared +1, Rendering +3**(Task 1 Shared +1, Task 2 Rendering +2, Task 3 Rendering +1).
- 레시피 키 추가만(`portrait.skin.chromaEvening`, `$defs/portraitLayer.skin.chromaEvening`, 기본값 0, schemaVersion 2 유지). `SkinRefinementKey` 순서: `darkCircles, nasolabial, marionette, glabella, toneEvening, chromaEvening, redness, shine, spots`.
- `RenderTuning` 추가: `chromaBlotchFraction` 0.025(G5-3 구현 중 변경, 처음 0.06), `chromaEveningMax` 1.0. 커널의 색 이동은 감마 값에서 재고 뺀다(스펙 6절, G5-3 구현 중 변경).
- 표 변경(스펙 2절 G5-3 몫): `chromaEvening` 0.5/0.5/0.35.
- `SkinKernels` `toneMix` 인자 추가(커널 수는 8 그대로). `FrequencySeparation.refined` 시그니처에 `chromaEvening: Double` 추가.
- 하네스 실행은 `MELLOW_EVOTO_DIR`이 있을 때만이고 이미지·출력은 저장소 밖.

## Review Focus

1. **휘도 보존.** 심은 보라 얼룩에 `chromaEvening = 1`을 걸면 Cb·Cr은 절반 이상 줄고 같은 픽셀의 Y는 바이트 1 이내. → Task 2 `testChromaEveningPullsBlotchChromaAndKeepsLuma`.
2. **0이면 같은 바이트.** `chromaEvening = 0`은 G5-2 `ee1aa28`에서 고정한 독립 `toneMix` 커널과 피부·얼룩·번들거림 조합별로 같은 바이트(대역 합성 경로 불변). → Task 2 `testZeroChromaEveningKeepsTheToneMixBytes`.
3. **데모 사진 자연 홍조.** 원터치 0.6에서 Cr 표준편차 비 ≥ 0.80. → Task 3(기존 `testOneTouchStaysNaturalAtDefaultAndMaximum`의 `crSigmaRatio`).
4. **하네스 표.** 1.4.0 표(legacy) / G5 표 / Evoto 세 줄이 스펙 1.1 경계와 나란히 있고, 미달 항목이 "미달"로 적혀 있다. → Task 4 VALIDATION.
5. **문서 정합.** `modules.md`·G4 스펙 3.2·README 표의 값이 `OneTouchBundle.Table`과 같다. → Task 4.

## 인터페이스 요약 (모든 Task가 공유하는 이름)

```swift
// MellowShared (Task 1)
SkinRefinementKey.chromaEvening                          // toneEvening 뒤
SkinAdjustments.chromaEvening: Double
OneTouchBundle.Values.chromaEvening: Double
OneTouchBundle.Table.common.chromaEvening = 0.5, female = 0.5, male = 0.35

// MellowRendering (Task 2)
RenderTuning.chromaBlotchFraction = 0.025, chromaEveningMax = 1.0
FrequencySeparation.refined(_:bounds:faceWidth:mask:reference:smoothing:toneEvening:chromaEvening:shine:tuning:) throws -> CIImage
SkinKernels.toneMix(image:fineBlur:midBlur:blotchBlur:wideNumerator:wideDenominator:reference:keep:even:evenChroma:shine:shineOffset:shineRamp:extent:) throws -> CIImage

// 테스트 지원 (Task 3)
SyntheticDefect.tinted(_ image: CIImage, center: CGPoint, radius: CGFloat, cb: Double, cr: Double, extent: CGRect) -> CIImage
RealPhotoAcceptanceTests.ChromaBounds
```

---

### Task 1: 키 `chromaEvening`·표·스키마·화면 이름

**Files:**
- Modify: `apple/Sources/MellowShared/API/SkinAdjustments.swift`, `apple/Sources/MellowShared/API/OneTouchBundle.swift`, `shared/recipe-schema/edit-recipe.v2.schema.json`, `shared/recipe-schema/README.md`, `apple/MellowPhoto/Application/UserMessage.swift`
- Test: `apple/Tests/MellowSharedTests/OneTouchBundleTests.swift`, `EditRecipeCodingTests.swift`, `RecipeSchemaTests.swift`

- [ ] **Step 1: 실패하는 테스트 작성**

`OneTouchBundleTests`에 추가:

```swift
    func testOneTouchEvensBlotchChromaMoreForWomenThanMen() {
        XCTAssertEqual(OneTouchBundle.layer(for: .female, strength: 1).skinRefinement[.chromaEvening], OneTouchBundle.Table.female.chromaEvening)
        XCTAssertLessThan(OneTouchBundle.Table.male.chromaEvening, OneTouchBundle.Table.female.chromaEvening)
        XCTAssertEqual(SkinRefinementKey.allCases, [.darkCircles, .nasolabial, .marionette, .glabella, .toneEvening, .chromaEvening, .redness, .shine, .spots], "화면 순서")
        XCTAssertTrue(OneTouchBundle.keys.contains(.skinRefinement(.chromaEvening)))
    }
```

`EditRecipeCodingTests` 왕복에 `chromaEvening: 0.3`, 옛 JSON은 0. `RecipeSchemaTests`는 스키마 키 대조로 실패한다.

- [ ] **Step 2: 실패 확인**

Run: `cd apple && swift test --filter "OneTouchBundleTests|EditRecipeCodingTests|RecipeSchemaTests"` → 컴파일 실패.

- [ ] **Step 3: 구현**

G5-2 Task 1과 같은 방식으로 `case chromaEvening`(`toneEvening` 뒤), `SkinAdjustments.chromaEvening`(init 인자는 `toneEvening` 뒤, decode `?? 0`, subscript), `OneTouchBundle.Values.chromaEvening`(`refinements`에 포함), `Table` 0.5/0.5/0.35, 스키마 두 곳(`description`: "얼룩 색 고르기. 얼굴 폭 2.5% 흐림의 Cb·Cr이 12% 피부 평균에서 벗어난 만큼을 되돌리고 휘도는 그대로 둔다."), README(`portrait` 설명 줄·원터치 표·규칙 절 G5 문장은 G5-2가 썼으니 값만), `UserMessage.skinRefinementTitle` `case .chromaEvening: return "얼룩 색 고르기"`.

- [ ] **Step 4: 실행·커밋**

Run: `cd apple && swift test --filter "MellowSharedTests|MellowEditingTests"` → 통과. Mac 앱 테스트 통과. lint 출력 없음.

```bash
git add apple/Sources/MellowShared/API/SkinAdjustments.swift apple/Sources/MellowShared/API/OneTouchBundle.swift shared/recipe-schema/edit-recipe.v2.schema.json shared/recipe-schema/README.md apple/MellowPhoto/Application/UserMessage.swift apple/Tests/MellowSharedTests/OneTouchBundleTests.swift apple/Tests/MellowSharedTests/EditRecipeCodingTests.swift apple/Tests/MellowSharedTests/RecipeSchemaTests.swift
git commit -m "feat(shared): 피부 정밀 키 chromaEvening 추가, 원터치 표 0.5/0.5/0.35

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 2: `toneMix` 확장과 대역 합성

**Files:**
- Modify: `apple/Sources/MellowRendering/Domain/SkinKernels.swift`, `apple/Sources/MellowRendering/Domain/FrequencySeparation.swift`, `apple/Sources/MellowRendering/Domain/SkinStage.swift`, `apple/Sources/MellowRendering/API/RenderTuning.swift`
- Modify: `apple/Tests/MellowRenderingTests/RenderingTestSupport.swift`(`SyntheticDefect.tinted`)
- Test: `apple/Tests/MellowRenderingTests/SkinStageTests.swift`

- [ ] **Step 1: 실패하는 테스트 작성**

`SyntheticDefect.tinted(_:center:radius:cb:cr:extent:)`: 감마 공간에서 `CIColorMatrix`로 Cb·Cr 이동에 해당하는 RGB 편향(`ΔR = 1.402·cr`, `ΔG = −0.344136·cb − 0.714136·cr`, `ΔB = 1.772·cb`, BT.601 역변환)을 더한 사본을 `hardEllipse` 마스크로 섞고 선형으로 되돌린다. Y(BT.601 감마)는 변하지 않는다.

`SkinStageTests`에 추가(합성 얼굴, 볼에 반지름 얼굴 폭 6% 보라 얼룩 cb +0.04, cr +0.03):

```swift
    func testChromaEveningPullsBlotchChromaAndKeepsLuma() throws {
        let base = SyntheticFace.make()
        let extent = base.image.extent
        let center = CGPoint(x: 200, y: 220)
        let radius: CGFloat = 280 * 0.06
        let blotchy = CIImage(cgImage: try Support.renderer.makeCGImage(
            SyntheticDefect.tinted(base.image, center: center, radius: radius, cb: 0.04, cr: 0.03, extent: extent)))
        let before = try Support.grid(blotchy)
        let after = try Support.grid(render(base, image: blotchy, skin: SkinAdjustments(chromaEvening: 1)))
        let clean = try Support.grid(base.image)
        let disc = try Support.grid(Support.hardEllipse(center: center, radii: CGSize(width: radius * 0.65, height: radius * 0.65), extent: extent))
        let planted = DisplayScale.chromaDelta(clean, before, weight: disc)
        let remaining = DisplayScale.chromaDelta(clean, after, weight: disc)
        XCTAssertGreaterThanOrEqual(1 - remaining.cb / planted.cb, 0.5, "Cb 절반 이상")
        XCTAssertGreaterThanOrEqual(1 - remaining.cr / planted.cr, 0.5, "Cr 절반 이상")
        XCTAssertLessThanOrEqual(DisplayScale.lumaDelta(before, after, weight: disc).meanAbsolute, 1.0, "휘도는 그대로")
    }

    func testZeroChromaEveningKeepsTheToneMixBytes() throws {
        let base = SyntheticFace.make()
        let withEven = try Support.bytes(render(base, skin: SkinAdjustments(toneEvening: 0.5)))
        let withZeroChroma = try Support.bytes(render(base, skin: SkinAdjustments(toneEvening: 0.5, chromaEvening: 0)))
        XCTAssertEqual(withEven, withZeroChroma)
    }
```

(`render(_:image:skin:)`는 이 파일의 기존 도우미 형태를 따른다. `DisplayScale`은 화면 배율 격자용이지만 `PixelGrid` 입력이면 그대로 쓸 수 있다. 격자가 같은 크기면 된다.)

- [ ] **Step 2: 실패 확인**

Run: `cd apple && swift test --filter SkinStageTests/testChromaEvening` → 첫 테스트 실패(변화 없음), 둘째는 통과(아직 경로 없음).

- [ ] **Step 3: 구현**

`RenderTuning`:

```swift
    /// 얼룩 색 고르기가 보는 얼룩 크기 흐림 반지름. 얼굴 폭 비율. 볼의 보라·붉은 얼룩은 5~10%다(스펙 G5 6절).
    public var chromaBlotchFraction: Double = 0.025
    /// 얼룩 색 고르기 1에서 Cb·Cr 편차를 되돌리는 비율.
    public var chromaEveningMax: Double = 1.0
```

`toneMix` 커널에 `__sample blotchBlur`와 `float evenChroma` 인자, 본문 끝에:

```
    // cbv·crv는 BT.601 Cb·Cr 계수, invCb·invCr는 Y 성분이 0인 역변환 열이다.
    // encodeSRGB·decodeSRGB는 SkinKernels의 sRGB 변환 함수를 쓴다.
    vec3 cbv = vec3(-0.168736, -0.331264, 0.5);
    vec3 crv = vec3(0.5, -0.418688, -0.081312);
    vec3 invCb = vec3(0.0, -0.344136, 1.772);
    vec3 invCr = vec3(1.402, -0.714136, 0.0);
    vec3 mixed = low + mid * keep + fine;
    vec3 blotch = encodeSRGB(blotchBlur.rgb) - encodeSRGB(wide);
    vec3 shift = evenChroma * (dot(blotch, cbv) * invCb + dot(blotch, crv) * invCr);
    vec3 evened = decodeSRGB(encodeSRGB(mixed) - shift) - mixed;
    return vec4(mixed + evened * step(0.000001, evenChroma), image.a);
```

`FrequencySeparation.refined`에 `chromaEvening: Double` 인자: `let chroma = min(1, max(0, chromaEvening)) * tuning.chromaEveningMax`, guard를 `even > 0 || gloss > 0 || chroma > 0`로, `blotchBlur = blurred(image, radius: max(bandRadii.fine, Double(faceWidth) * tuning.chromaBlotchFraction))`를 커널에 넘긴다(G5-3 구현 중 변경: 하한 mid → fine, 색 이동은 감마 값에서, 스펙 6절). `SkinStage.refine`: `bandMix = skin.smoothing > 0 || skin.toneEvening > 0 || skin.chromaEvening > 0 || skin.shine > 0`, 호출에 `chromaEvening: skin.chromaEvening`.

`modules.md`의 "대역 합성(피부 보정·얼룩 고르기·번들거림을 한 번에 …)" 문장에 "얼룩 색 고르기(얼굴 폭 2.5% 흐림의 Cb·Cr을 12% 평균 쪽으로, Y 유지)"를 더하고 "세 값이 모두 0이면" → "네 값이 모두 0이면"(Task 4에서 함께 커밋해도 된다).

- [ ] **Step 4: 실행·커밋**

Run: `cd apple && swift test --filter "SkinStageTests|FrequencySeparationTests|RealPhotoAcceptanceTests"` → 통과. `testSmoothingOnlyUsesTheLegacyBandMixPath`·`testToneEveningFlattensBlotchesAndKeepsPores`가 같은 바이트·같은 결과를 지킨다.

```bash
git add apple/Sources/MellowRendering/Domain/SkinKernels.swift apple/Sources/MellowRendering/Domain/FrequencySeparation.swift apple/Sources/MellowRendering/Domain/SkinStage.swift apple/Sources/MellowRendering/API/RenderTuning.swift apple/Tests/MellowRenderingTests/RenderingTestSupport.swift apple/Tests/MellowRenderingTests/SkinStageTests.swift
git commit -m "feat(rendering): 얼룩 색 고르기 — 얼굴 폭 2.5% 흐림의 Cb·Cr을 피부 평균 쪽으로 당기고 휘도는 지킴

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 3: 실사진 수용 — 심은 보라 얼룩

**Files:**
- Modify: `apple/Tests/MellowRenderingTests/RealPhotoAcceptanceTests.swift`

- [ ] **Step 1: 테스트 작성**

```swift
    enum ChromaBounds {
        static let radiusFraction: CGFloat = 0.06
        static let plantedCb = 0.04
        static let plantedCr = 0.03
        static let removal = 0.5
        static let lumaMeanAbsolute = 1.5
        static let fineRatio = 0.9
        static let midLumaRatio = 0.95
    }

    /// 얼룩 색 고르기 1이 볼의 보라 얼룩 색을 절반 이상 되돌리고 휘도 입체감은 둔다(스펙 G5 1.2).
    func testChromaEveningClearsAPlantedPurpleBlotchAndKeepsLumaRelief() throws {
        let portrait = try self.portrait()
        let cheek = try XCTUnwrap(FaceRegions.cheekRects(face: portrait.face, extent: portrait.extent).first)
        let center = CGPoint(x: cheek.midX, y: cheek.midY)
        let radius = portrait.faceWidth * ChromaBounds.radiusFraction
        let blotchy = try portrait.baked(SyntheticDefect.tinted(portrait.image, center: center, radius: radius, cb: ChromaBounds.plantedCb, cr: ChromaBounds.plantedCr, extent: portrait.extent))
        let disc = try DisplayScale.grid(Support.hardEllipse(center: center, radii: CGSize(width: radius * 0.65, height: radius * 0.65), extent: portrait.extent))
        let original = try base().grid
        let defective = try DisplayScale.grid(blotchy)
        let repaired = try grid({ $0.portrait.skin.chromaEvening = 1 }, stage: SkinStage(), input: blotchy)
        let planted = DisplayScale.chromaDelta(original, defective, weight: disc)
        let remaining = DisplayScale.chromaDelta(original, repaired, weight: disc)
        XCTAssertGreaterThanOrEqual(record("chromaEvening", "cbRemoval", 1 - remaining.cb / planted.cb), ChromaBounds.removal)
        XCTAssertGreaterThanOrEqual(record("chromaEvening", "crRemoval", 1 - remaining.cr / planted.cr), ChromaBounds.removal)
        XCTAssertLessThanOrEqual(record("chromaEvening", "lumaMeanAbs", DisplayScale.lumaDelta(defective, repaired, weight: disc).meanAbsolute), ChromaBounds.lumaMeanAbsolute)
        var recipe = EditRecipe()
        recipe.portrait.skin.chromaEvening = 1
        XCTAssertGreaterThanOrEqual(record("chromaEvening", "fineRatio", try skinFineVarianceRatio(recipe)), ChromaBounds.fineRatio)
        let interior = try portrait.interiorSkinMask()
        let output = try SkinStage().apply(portrait.image, in: portrait.context(recipe))
        let skinBounds = FaceRegions.maskBounds(face: portrait.face, extent: portrait.extent, tuning: portrait.tuning)
        XCTAssertGreaterThanOrEqual(
            record("chromaEvening", "midLumaRatio", try Support.bandVarianceRatio(before: portrait.image, after: output, weight: interior, in: skinBounds, innerRadius: fineRadius(), outerRadius: Double(portrait.faceWidth) * OneTouchNaturalness.midOuterFraction)),
            ChromaBounds.midLumaRatio, "휘도 입체감은 둔다")
    }
```

- [ ] **Step 2: 실행·조정**

Run: `cd apple && swift test --filter RealPhotoAcceptanceTests 2>&1 | tee /tmp/g5-3-acceptance.log | grep -E "acceptance|passed|failed|error"` → 통과. 원터치 `crSigmaRatio`가 0.6에서 0.80 미만이면 표 `chromaEvening`을 0.5 → 0.3으로(세 성별 비례), 그래도 미달이면 0.

전체 `swift test` → 이 계획 합계 Shared +1, Rendering +3. Mac 앱 테스트 통과. lint 출력 없음. iOS 시뮬레이터용 빌드 성공.

- [ ] **Step 3: 커밋**

```bash
git add apple/Tests/MellowRenderingTests/RealPhotoAcceptanceTests.swift
git commit -m "test(rendering): 데모 볼에 심은 보라 얼룩의 색 제거율과 휘도 보존을 단언

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 4: 하네스 실행·VALIDATION·문서

**Files:**
- Modify: `VALIDATION.md`, `docs/architecture/modules.md`, `docs/superpowers/specs/2026-10-21-beauty-g4-one-touch-design.md`(3.2 표 값만), `shared/recipe-schema/README.md`(값 대조), `docs/superpowers/specs/2026-10-21-beauty-g5-evoto-calibration-design.md`("구현 중 변경" 행)

- [ ] **Step 1: 하네스 실행(이미지가 있을 때만)**

G5-2 Task 5 Step 3과 같은 명령으로 전체 계열(`app`·`female`·`male`·`legacy`)을 잰다(약 16분). 출력 `metrics.md`의 묶음별 중앙값 네 표(retouch·spots·dark-circles·wrinkles)에서 `evoto`·`legacy-0.6`·`legacy-1.0`·`app-0.6`·`app-1.0`·`male-0.6`·`male-1.0` 줄을 스펙 1.1 경계와 대조한다. 미달 항목은 G5-1·G5-2·이 계획의 조정 규칙을 한 번씩 적용해 다시 재고, 그래도 미달이면 "미달"로 적는다. `zoom.png`를 Read 도구로 본다: `blemish-removal_…_app.zoom.png`(원반 없음·주근깨 지워짐), `ai-skin-retouching_…_app.zoom.png`(손등 원반 없음, 하얗게 뜨지 않음), `frequency-separation_…_app.zoom.png`(보라 얼룩 줄었는지), `wrinkle-remover-for-face_…_app.zoom.png`(콧구멍 그대로).

이미지가 없으면 이 Step을 건너뛰고 VALIDATION에 "하네스 미실행(이미지 없음)"으로 적는다.

- [ ] **Step 2: VALIDATION**

`VALIDATION.md` 끝에 `## 인물 보정 G5 Evoto 보정 재조정 (2026-10-XX)` (G5-1 초안 절은 이 절로 흡수하고 지운다):

- 머리: 브랜치·커밋 범위, 환경, "모두 자동 테스트, 화면 조작 없음, iOS 시뮬레이터·실기기 없음, 배포 없음".
- 자동 검증: `./scripts/test-apple.sh` 종료 코드, 패키지·Mac 테스트 수(모듈별), 늘어난 수의 내역, iOS 시뮬레이터용 빌드.
- 원터치 실측(데모·커플, 화면 배율): 하한 표(옛 문턱 / 적용 문턱 / 실측), 상한 표(새 행 전부), 심은 결함 표(점 회복·모공·제외 영역·원반 잔차·보라 얼룩).
- Evoto 하네스 실측 표: 차원 × {Evoto, 1.4.0 표 0.6, 1.4.0 표 1.0, G5 0.6, G5 1.0, G5 남성 0.6} 와 경계, 판정(합격/미달). 쌍 수와 묶음 이름. 미달 항목의 이유와 대응.
- 렌더 시간: 데모 미리보기 원터치 0.6, `spots` 0과 1의 차이(G5-2 Task 4 기록).
- 내린 보임 문턱과 이유(있으면), 바뀐 상수·표 값 전체(1.4.0 → G5).
- 스펙과 다르게 한 것(각 계획의 조정 규칙으로 바꾼 값, 대안 굳히기를 썼는지).
- 미검증: 실기기(스펙 "사용자 조치" 항목), CI(Xcode 26.3), 다른 피부톤·조명, 2세대 점 지우기.
- CI 상태: 컨트롤러가 확인한다고만 적는다(통과를 주장하지 않음).

- [ ] **Step 3: 문서 정합**

- `docs/architecture/modules.md`: MellowShared 규칙 "피부 정밀 7종" → 9종(`chromaEvening`·`spots`), 묶인 키 "피부 9종" → 11종, 원터치 표 설명에 "자동 잡티 false 덮어쓰기·점 지우기·얼룩 색 고르기". MellowRendering 규칙: `skin` 단계 순서에 "점 지우기(`SpotRemoval`, 닫힘·열림 차이, 제외 비트맵)" 추가, `SkinKernels` "커널 5개" → 8개(`chroma`·`bands`·`fold`·`tone`·`blush`·`heal`·`spot`·`spotApply`), 잡티 복구 "패치 복구" → "색 맞춤 복구(원본 질감 × 대상 고리 비율)", 잡티 검출 거절 조건, 캐시 "얼굴당 20(해상도마다 10 × 2)" → 22(11 × 2), 대역 합성 문장(Task 2). 테스트 목록에 G5 항목 한 줄. 대안 굳히기를 썼으면 `RenderContext.renderer`.
- G4 스펙 3.2 표를 G5 2절 값으로 고치고 표 머리에 "(G5에서 변경: 값은 G5 스펙 2절이 기준)"을 적는다. 결정 표의 "(G5에서 변경)" 행은 설계 단계에서 이미 넣었다.
- README 원터치 표와 `OneTouchBundle.Table`이 같은지 눈으로 대조한다.
- G5 스펙 결정 표에 구현 중 바뀐 값이 있으면 "(G5-n 구현 중 변경)" 행을 더한다(결정 먼저, 코드 다음 규칙).

- [ ] **Step 4: 최종 검증·커밋**

Run: `./scripts/test-apple.sh` → 종료 코드 0(로컬은 iOS 생략). `cd apple && swift test 2>&1 | grep -E "Executed"`로 모듈별 수를 VALIDATION에 옮긴다.

```bash
git add VALIDATION.md docs/architecture/modules.md docs/superpowers/specs/2026-10-21-beauty-g4-one-touch-design.md docs/superpowers/specs/2026-10-21-beauty-g5-evoto-calibration-design.md shared/recipe-schema/README.md
git commit -m "docs: G5 검증 기록(Evoto 하네스 실측·수용 실측)과 모듈 지도·표 문서 갱신

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

(표·상수를 고쳤으면 그 소스 파일도 같은 커밋에 넣고 메시지에 적는다.)

---

## 자체 검토 결과

- **스펙 대조:** 3절 키·순서·화면 이름·2절 `chromaEvening` → Task 1. 6절 커널·대역 합성 → Task 2. 1.2 얼룩 색 고르기 행 → Task 3. 7절 하네스 실행·8절 VALIDATION·3절 `modules.md` → Task 4. 9절 "G5-3 4 Task"와 같다.
- **타입 일관성:** `SkinRefinementKey.chromaEvening`, `RenderTuning.chromaBlotchFraction`·`chromaEveningMax`, `FrequencySeparation.refined(chromaEvening:)`, `SkinKernels.toneMix(blotchBlur:evenChroma:)`, `SyntheticDefect.tinted`, `RealPortrait.interiorSkinMask`(G5-1), `Support.bandVarianceRatio`(G5-1)를 정의한 Task와 쓰는 Task에서 같게 썼다.
- **Review Focus 매핑:** 1·2 → Task 2, 3 → Task 3, 4·5 → Task 4.
- **플레이스홀더 점검:** 표 값·상수는 스펙 값이고 조정 규칙을 적었다. 하네스 경로는 저장소 밖 로컬 경로다. "TBD/TODO" 없음.
