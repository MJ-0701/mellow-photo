# 인물 보정 G1 피부 정밀 구현 계획

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 뷰티 › 피부 탭에 다크서클·팔자주름·마리오네트 주름·미간 주름·피부 얼룩 고르기·붉은기(맑게 ↔ 혈색)·번들거림 슬라이더 7개를 더한다. 모두 기존 `skin` 단계 안에서 피부 마스크와 특징점 띠로 동작하고 모공 질감은 남긴다.

**Architecture:** MellowShared `SkinAdjustments`에 키 7개(`SkinRefinementKey`)를 더한다(schemaVersion 2, 기본값 0). MellowRendering은 주름 띠 마스크를 `FaceRegions+Folds.swift`(얼굴 좌표 타원 × 피부 다각형 비트맵, 새 캐시 항목 없음)에, CIKL 색 커널 3개(`foldLift`·`toneMix`·`redness`)를 `SkinKernels`에, 적용 도우미를 `SkinRefinement`에 두고 `SkinStage`가 대상 얼굴마다 "주름 밝히기 → 대역 합성(피부 보정·얼룩 고르기·번들거림) → 붉은기" 순서로 부른다. 파이프라인 단계 이름 순서는 바뀌지 않는다. 앱은 뷰티 › 피부 탭에 슬라이더 6개를 더한다.

**Tech Stack:** Swift 5.9 tools / Swift 5 언어 모드, SwiftUI + Observation, Core Image(CIGaussianBlur·CIAreaAverage·CIMix·CIMultiplyCompositing·CIBlendWithMask·CIColorMatrix·CILinearToSRGBToneCurve, CIKL `CIColorKernel`), XCTest, XcodeGen 2.46.0.

**Spec:** `docs/superpowers/specs/2026-10-20-beauty-g-evoto-design.md` (G1에 해당하는 절: 1.1, 1.2, 1.5, 1.6의 주름 밝히기·대역 합성·붉은기, 1.9, 1.10, 2, 4)

## 사람이 확인할 것

- **순서.** Task 1~2 레시피·편집 규칙 → 3 주름 띠 마스크 → 4 주름 밝히기 → 5 얼룩 고르기·번들거림 → 6 붉은기 → 7 통합(항등·클램프·특징점 없음·대상 얼굴·캐시) → 8 앱 화면·시나리오. 8개 Task, Task마다 Opus 구현 → 리뷰 → 수정, 끝에 전체 리뷰.
- **외부 효과가 있는 단계.** 없음. 푸시·태그·TestFlight는 G 범위 밖(스펙 "외부 효과가 있는 단계").
- **스펙이 정하지 않아 이 계획이 정한 것.**

| 결정 | 이유 | 바꾸면 비용 |
|---|---|---|
| 팔자 띠 중심을 코 날개 → 입꼬리 선분에서 얼굴 바깥쪽으로 얼굴 폭 2% 민다 | 주름은 선분보다 바깥에 있고, 선분 위에 두면 입술 보호 영역(얼굴 폭 5%)에 걸려 띠가 비는 구간이 생김 | 작음 |
| 마리오네트 띠는 입꼬리에서 턱 쪽(얼굴 −v)으로 바깥쪽 15° 기운 고정 방향으로 얼굴 폭 12% 내려 긋고, 같은 2% 바깥 밀기를 쓴다. 코 특징점이 없어도 만든다 | 입꼬리 아래에는 Vision 특징점이 없어 방향을 특징점으로 정할 수 없음. 팔자 선분 방향을 이어 쓰면 코가 없을 때 마리오네트까지 빠짐 | 작음 |
| 눈썹 안쪽 끝은 두 눈 가운데 선에 가장 가까운 점들(얼굴 폭 1% 안)의 평균 | Vision 눈썹 점은 위아래 두 줄이라 한 점만 고르면 높이가 치우침 | 작음 |
| 붉은기 −의 기준 Cr은 볼 두 곳 평균 | 피부 마스크의 피부색 기준과 같은 곳. 볼 상자가 없으면(얼굴이 사진 밖에 걸침) 붉은기·번들거림만 건너뜀 | 작음 |
| 번들거림 가중치는 선형 휘도가 볼 기준보다 0.12 이상 밝은 곳에서 시작 | 피부 질감 잡음(±10%)은 걸리지 않고 반사광(+0.25 이상)은 걸림 | 작음 |
| 주름 밝히기 뒤에 대역 합성, 그 뒤 붉은기 | 밝힌 결과 위에 얼룩을 고르고, 색 이동은 마지막 | 작음 |
| 얼룩 고르기·번들거림이 0이면 기존 `bandMix` 경로 그대로 | 피부 보정만 쓰는 사진의 바이트가 G 전후 같아야 함(회귀) | 작음 |
| (Task 4 구현 중 변경) 주름 국소 저주파 반지름을 얼굴 폭 4% → 1.5% | 4%는 좁은 주름 그림자를 거의 지워 밝힘이 생기지 않았음. 판정 문턱은 그대로 | 작음 |

- **범위 밖(다른 계획).** 몸 피부·톤(G2), 효과·동기화·분할 비교·VALIDATION(G3).
- **위험.** 주름 띠 위치는 특징점 어림이라 돌아간 얼굴에서 어긋날 수 있다(올리는 양을 "주변보다 어두운 만큼"으로 제한해 밝은 얼룩은 생기지 않음). 하얗게 날아간 반사광은 피부색 가중치 밖이라 번들거림이 덜 눌린다. 마리오네트 띠는 입술·배경이 둘레 평균에 섞여 밝힘 여유가 가장 작다(합성 얼굴 +16, 문턱 +12). 보정 품질은 자동 테스트로 판정할 수 없다.
- **사용자 조치.** 이 계획은 자동 검증만 한다. 실제 인물 사진 확인은 G3 뒤 사용자 조치(스펙).

---

## 에이전트 참조

## Global Constraints

- 작업 위치: worktree `/Users/mj/IdeaProjects/mellow-photo/.claude/worktrees/beauty-g`, 브랜치 `beauty-g-evoto`(main `5be4ced`에서 분기). 부모 저장소로 `cd`하지 않는다. 다른 세션이 부모 저장소에서 사진 가져오기 버그를 고치는 중이므로 `PhotoPickerButton.swift`·`project.yml`·`scripts/test-apple.sh`·UI 테스트 타깃은 이 계획에서 건드리지 않고 그 변경이 있다고 가정하지도 않는다. 모든 Swift·xcodebuild 명령 전에 `export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`.
- 모듈 의존성 표(`docs/architecture/modules.md`)와 `scripts/verify-modules.sh`는 바뀌지 않는다. MellowShared는 Foundation·CoreGraphics만, MellowEditing은 MellowShared만, MellowRendering은 `CoreImage`·`Foundation`·`MellowShared`·`Vision`만 import한다. 렌더는 `AdjustmentRange`로 직접 자른다.
- 새 보정은 MellowRendering 단계와 MellowShared 레시피 확장으로만 넣는다. 이 계획은 파이프라인 단계 이름 순서를 바꾸지 않는다(`skin, feature, makeup, background, shapeWarp, localEdit, geometry, color, detail, look`).
- 레시피 `schemaVersion`은 2 유지, 키 추가만. 새 키는 기본값 0이고 없으면 0으로 읽는다. v1 세션은 계속 읽힌다.
- 값 범위: `skin.redness`만 `AdjustmentRange.bipolar`, 나머지 정밀 6종은 `AdjustmentRange.unit`. `AdjustmentRange.skinRefinement(_:)` 한 곳.
- 마스크는 `FaceRegions`(확장 파일 포함)에서만 만든다. 피부 CIKL 색 커널은 `SkinKernels` 한 곳.
- `RenderTuning` 새 상수 시작값: foldLowBandFraction 0.015(구현 중 0.04에서 변경), foldSurroundFraction 0.12, foldLiftMax 0.9, foldLiftMaxGain 1.6, foldLumaFloor 0.01 (Task 4, 배율 상한·분모 하한은 구현 중 추가) · toneBandFraction 0.12, toneEveningMax 0.8, shineLumaOffset 0.12, shineLumaRamp 0.1, shineReductionMax 0.85 (Task 5) · rednessClearMax 0.7, rednessFlushMax 0.03 (Task 6). 위치 비율은 `FaceRegions+Folds.swift`의 `private enum FoldShape`.
- CI는 Xcode 26.3이다(로컬 27). `CGFloat`와 `Double`을 섞는 삼각함수·`hypot`·`atan2` 호출은 인자 타입을 맞춘다(`CGFloat(cos(Double(angle)))`처럼 명시 변환). 같은 타입 둘(`atan2(cgFloat, cgFloat)`)은 그대로 된다.
- 한 줄 한 문장, 세미콜론 금지, 매직 넘버는 명명 상수(`RenderTuning`·`Theme`·`AppModel.Policy`·`EditingPolicy`, 기하 비율은 `FoldShape` 또는 타입 안 `private static let`). CIKL 소스 안 표준 계수(BT.601·BT.709)는 주석으로 이름을 단다.
- 한국어 사용자 문구는 앱 타깃(`UserMessage`·뷰)에만. 모듈은 `MellowError`만 던진다(새 case 없음).
- `cd apple && swift format lint --strict --recursive Sources Tests MellowPhoto MellowPhotoTests` 출력 없음(한도 120자). 허용된 빌드 경고: 기존 `CIWarpKernel`·`CIColorKernel(source:)`·`CIKernel(source:)` 지원 중단(`WarpKernel`, `SkinKernels`, `FeatureKernels`, `DisplacementWarp`), 시뮬레이터 `usesCPUOnly`. `SkinKernels`의 커널 3개는 같은 종류의 경고 3곳을 더한다(허용).
- `./scripts/verify-modules.sh` 통과. 전체 검증은 `./scripts/test-apple.sh`.
- 패키지 테스트: `cd apple && swift test`(모듈마다 `Executed N tests`가 따로 찍힌다). Mac 앱 테스트: `xcodebuild -project apple/MellowPhoto.xcodeproj -scheme MellowPhoto -derivedDataPath apple/build -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO test 2>&1 | grep -E "Executed|TEST (SUCCEEDED|FAILED)|error:"`. 이 계획은 앱 파일을 더하거나 지우지 않으므로 `xcodegen generate`가 필요 없다.
- iOS 시뮬레이터 테스트는 이 계획에서 돌리지 않는다(G3 마지막 Task에서 한 번). 시뮬레이터를 끄거나 지우지 않는다. Xcode를 열거나 앱을 띄우지 않는다.
- 푸시·태그·`scripts/release.sh` 실행 금지.
- 커밋: 한국어 Conventional Commits, 마지막 줄 `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`. `git add`는 Task에 나열한 경로만.
- 각 Task 끝에 패키지 테스트(앱을 건드렸으면 Mac 앱 테스트도)와 lint가 통과해야 다음으로 간다. 기준 테스트 수(계획 작성 때 `func test` 수로 셈, 시작 전에 `swift test`로 다시 확인): 패키지 331(Shared 43 · Rendering 225 · Library 30 · Export 4 · Editing 29), 앱 Mac 71(iPhone·iPad 70). 목표: 패키지 354(Shared 45 · Rendering 244 · Library 30 · Export 4 · Editing 31), 앱 Mac 72.
- 표본 점이 틀려 테스트가 실패하면 마스크 격자를 표본 점 둘레 ±20px로 출력해 타원 안의 다른 점으로 표본을 옮긴다. 판정 문턱(128·+12 등)을 낮추지 않는다.

## Review Focus

스펙이 암시하지만 스펙의 테스트 표가 직접 다루지 않는 입력. 각 줄의 테스트를 소유 Task에 넣었다.

1. **G 이전에 저장한 세션·프리셋(`skin`에 `smoothing`·`autoBlemish`만 있음)을 연다.** 정밀 7종이 0으로 읽히고 렌더 바이트가 같아야 한다. → Task 1 `testSkinRefinementKeysRoundTripAndDefaultToIdentity`, Task 5 `testSmoothingOnlyUsesTheLegacyBandMixPath`.
2. **다크서클을 넣은 뒤 자동 보정을 누른다.** 자동 보정이 다크서클·붉은기를 0으로 지우면 안 된다. → Task 2 `testApplyAutoKeepsSkinRefinements`.
3. **상자만 있는 얼굴(특징점 없음).** 주름 4종은 조용히 빠지고 얼룩 고르기·붉은기·번들거림은 대체 타원 마스크로 동작해야 한다. → Task 7 `testBoxOnlyFaceSkipsFoldsButStillEvensTone`.
4. **코·눈썹·입술·한쪽 눈 특징점이 없는 얼굴.** 그 띠만 빠지고 나머지 띠는 남아야 한다(코가 없어도 마리오네트는 남고, 입술이 없으면 팔자·마리오네트 둘 다 빠진다). → Task 3 `testFoldMasksNeedTheirLandmarks`, Task 4 `testMissingLandmarksSkipOnlyThatFold`.
5. **단체 사진에서 대상 얼굴 하나.** 다른 얼굴은 한 픽셀도 바뀌지 않아야 한다. → Task 7 `testTargetFaceRefinesOnlyThatFace`.
6. **손으로 고친 프리셋의 범위 밖 값(3, −5).** 자른 값과 같은 바이트여야 한다. → Task 7 `testZeroRefinementsAreIdentityAndOutOfRangeValuesRenderClamped`.

## 인터페이스 요약 (모든 Task가 공유하는 이름)

```swift
// MellowShared (Task 1)
public enum SkinRefinementKey: String, CaseIterable, Codable, Sendable { darkCircles, nasolabial, marionette, glabella, toneEvening, redness, shine }
public struct SkinAdjustments {
    smoothing, autoBlemish, darkCircles, nasolabial, marionette, glabella, toneEvening, redness, shine
    init(smoothing:autoBlemish:darkCircles:nasolabial:marionette:glabella:toneEvening:redness:shine:)  // 모두 기본값
    subscript(SkinRefinementKey) -> Double; refinementValues: [Double]; hasRefinement; hasEffect; numericValues
}
AdjustmentRange.skinRefinement(_ key: SkinRefinementKey) -> ClosedRange<Double>   // redness만 bipolar

// MellowEditing (Task 2)
EditChange.skinRefinement(SkinRefinementKey, Double)        // affectsGeometry false
EditingPolicy.skinRefinementRange(_:)
EditDocument.applyAuto: skin.smoothing·autoBlemish만 덮어씀

// MellowRendering (Task 3~7)
RenderTuning: + Global Constraints의 상수 12개
FaceRegions.Oval.tilt: CGFloat = 0                            // softMask가 angle + tilt로 그림
FaceRegions.eyeMidline(_:) (private → internal)
FaceRegions.darkCircleMask / nasolabialMask / marionetteMask / glabellaMask(face:extent:tuning:cache:) -> RegionMask?
FaceRegions.cheekAverages(of:face:extent:) -> (left: CIImage, right: CIImage)?
MaskBuilder.scaled(_:by:)
SkinKernels.foldLift(image:low:surround:amount:maxGain:lumaFloor:extent:), toneMix(image:fineBlur:midBlur:wideNumerator:wideDenominator:reference:keep:even:shine:shineOffset:shineRamp:extent:), redness(encoded:reference:clear:flush:extent:)
FrequencySeparation.refined(_:bounds:faceWidth:mask:reference:smoothing:toneEvening:shine:tuning:), maskedMean(_:mask:radius:)
enum SkinRefinement { liftFold(_:region:faceWidth:amount:tuning:extent:), adjustRedness(_:mask:bounds:reference:value:tuning:extent:) }
SkinStage.clamped(_:), folds(for:skin:context:), cheekReference(of:face:extent:)

// 테스트 지원 (Task 3)
SyntheticFace.underLeftEye, underRightEye, rolledUnderLeftEye, rolledUnderRightEye, leftNasolabial, rightNasolabial,
    leftMarionette, rightMarionette, glabella

// 앱 (Task 8)
UserMessage.skinRefinementTitle(_:), skinRefinementHint
BeautyPanel.skinControls: 슬라이더 7개 추가
```

---

### Task 1: 레시피 — SkinRefinementKey, SkinAdjustments 확장, 스키마

**Files:**
- Modify: `apple/Sources/MellowShared/API/SkinAdjustments.swift` (전체 교체)
- Modify: `apple/Sources/MellowShared/API/AdjustmentRange.swift` (`skinRefinement(_:)` 추가)
- Modify: `shared/recipe-schema/edit-recipe.v2.schema.json` (`portrait.skin` 키 6개), `shared/recipe-schema/README.md`
- Test: `apple/Tests/MellowSharedTests/EditRecipeCodingTests.swift`, `apple/Tests/MellowSharedTests/RecipeSchemaTests.swift`

**Interfaces:**
- Consumes: `AdjustmentRange.unit`·`bipolar`, `PortraitAdjustments.numericValues`(기존, `skin.numericValues`를 합침).
- Produces: 인터페이스 요약의 MellowShared 항목. 기존 호출 `SkinAdjustments(smoothing:autoBlemish:)`·`SkinAdjustments(smoothing:)`는 그대로 컴파일된다.

설계 근거: 스펙 1.2. 정밀 값은 `portrait.skin` 안에 두어 `dependsOnFaces`·`PresetValues`·일괄 적용이 자동으로 포함한다. 인코드는 합성 `Codable`이라 9개 키를 모두 쓰고, 디코드는 `decodeIfPresent`로 없는 키를 0으로 읽는다.

- [ ] **Step 1: 실패하는 테스트 작성**

`EditRecipeCodingTests.swift`의 `testShapeKeysAddressEveryValue` 뒤에 추가:

```swift
    func testSkinRefinementKeysRoundTripAndDefaultToIdentity() throws {
        let legacy = #"{"schemaVersion":2,"portrait":{"skin":{"smoothing":0.4,"autoBlemish":true}}}"#
        let decoded = try JSONDecoder().decode(EditRecipe.self, from: Data(legacy.utf8))
        XCTAssertEqual(decoded.portrait.skin, SkinAdjustments(smoothing: 0.4, autoBlemish: true), "G 이전 파일은 정밀 값이 0")
        XCTAssertEqual(decoded.portrait.skin.refinementValues, Array(repeating: 0, count: 7))
        XCTAssertFalse(decoded.portrait.skin.hasRefinement)
        var recipe = EditRecipe()
        for (offset, key) in SkinRefinementKey.allCases.enumerated() {
            recipe.portrait.skin[key] = Double(offset + 1) / 10
        }
        XCTAssertEqual(recipe.portrait.skin.refinementValues, (1...7).map { Double($0) / 10 })
        XCTAssertEqual(recipe.portrait.skin.darkCircles, 0.1)
        XCTAssertEqual(recipe.portrait.skin.marionette, 0.3)
        XCTAssertEqual(recipe.portrait.skin.shine, 0.7)
        XCTAssertEqual(recipe.portrait.skin.numericValues, [0] + (1...7).map { Double($0) / 10 })
        XCTAssertTrue(recipe.portrait.skin.hasEffect)
        XCTAssertTrue(recipe.dependsOnFaces, "정밀 값만 있어도 얼굴이 필요하다")
        XCTAssertFalse(recipe.dependsOnPerson)
        XCTAssertFalse(recipe.isDefault)
        let data = try JSONEncoder().encode(recipe)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let skin = try XCTUnwrap((json["portrait"] as? [String: Any])?["skin"] as? [String: Any])
        XCTAssertEqual(
            Set(skin.keys), Set(["smoothing", "autoBlemish"] + SkinRefinementKey.allCases.map(\.rawValue)))
        XCTAssertEqual(try JSONDecoder().decode(EditRecipe.self, from: data), recipe)
        XCTAssertEqual(AdjustmentRange.skinRefinement(.redness), AdjustmentRange.bipolar)
        for key in SkinRefinementKey.allCases where key != .redness {
            XCTAssertEqual(AdjustmentRange.skinRefinement(key), AdjustmentRange.unit, "\(key)")
        }
    }

    func testSkinRefinementScalarsAreCheckedForFinitenessAndCarriedByPresets() throws {
        let paths: [WritableKeyPath<EditRecipe, Double>] = [
            \.portrait.skin.darkCircles, \.portrait.skin.nasolabial, \.portrait.skin.marionette,
            \.portrait.skin.glabella, \.portrait.skin.toneEvening, \.portrait.skin.redness, \.portrait.skin.shine,
        ]
        for path in paths {
            var recipe = EditRecipe()
            recipe[keyPath: path] = .nan
            XCTAssertFalse(recipe.allValuesFinite, "\(path)")
        }
        var recipe = EditRecipe()
        recipe.portrait.skin.redness = -0.4
        let values = PresetValues(of: recipe)
        XCTAssertEqual(values.portrait.skin.redness, -0.4)
        XCTAssertEqual(try JSONDecoder().decode(PresetValues.self, from: JSONEncoder().encode(values)), values)
    }
```

`RecipeSchemaTests.swift`의 `encodedSampleRecipe()`에서 `recipe.portrait.skin = SkinAdjustments(smoothing: 0.3, autoBlemish: true)` 줄을 다음으로 바꾼다:

```swift
        recipe.portrait.skin = SkinAdjustments(smoothing: 0.3, autoBlemish: true, darkCircles: 0.2, redness: -0.1)
```

- [ ] **Step 2: 실패 확인**

Run: `cd apple && swift test --filter EditRecipeCodingTests`
Expected: 컴파일 실패 (`cannot find 'SkinRefinementKey' in scope`).

- [ ] **Step 3: 구현**

`apple/Sources/MellowShared/API/SkinAdjustments.swift` 전체:

```swift
import Foundation

/// 피부 정밀 슬라이더 이름. 레시피 JSON 키와 같다. redness만 가운데 0인 양방향이다.
public enum SkinRefinementKey: String, CaseIterable, Codable, Sendable {
    case darkCircles
    case nasolabial
    case marionette
    case glabella
    case toneEvening
    case redness
    case shine
}

/// 피부 보정 강도 0…1, 자동 잡티 스위치, 피부 정밀 7종(G). redness만 −1…1이고 나머지는 0…1이다.
public struct SkinAdjustments: Codable, Equatable, Sendable {
    public var smoothing: Double
    public var autoBlemish: Bool
    public var darkCircles: Double
    public var nasolabial: Double
    public var marionette: Double
    public var glabella: Double
    public var toneEvening: Double
    public var redness: Double
    public var shine: Double

    public init(
        smoothing: Double = 0, autoBlemish: Bool = false, darkCircles: Double = 0, nasolabial: Double = 0,
        marionette: Double = 0, glabella: Double = 0, toneEvening: Double = 0, redness: Double = 0, shine: Double = 0
    ) {
        self.smoothing = smoothing
        self.autoBlemish = autoBlemish
        self.darkCircles = darkCircles
        self.nasolabial = nasolabial
        self.marionette = marionette
        self.glabella = glabella
        self.toneEvening = toneEvening
        self.redness = redness
        self.shine = shine
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        smoothing = try container.decodeIfPresent(Double.self, forKey: .smoothing) ?? 0
        autoBlemish = try container.decodeIfPresent(Bool.self, forKey: .autoBlemish) ?? false
        darkCircles = try container.decodeIfPresent(Double.self, forKey: .darkCircles) ?? 0
        nasolabial = try container.decodeIfPresent(Double.self, forKey: .nasolabial) ?? 0
        marionette = try container.decodeIfPresent(Double.self, forKey: .marionette) ?? 0
        glabella = try container.decodeIfPresent(Double.self, forKey: .glabella) ?? 0
        toneEvening = try container.decodeIfPresent(Double.self, forKey: .toneEvening) ?? 0
        redness = try container.decodeIfPresent(Double.self, forKey: .redness) ?? 0
        shine = try container.decodeIfPresent(Double.self, forKey: .shine) ?? 0
    }

    public subscript(key: SkinRefinementKey) -> Double {
        get {
            switch key {
            case .darkCircles: return darkCircles
            case .nasolabial: return nasolabial
            case .marionette: return marionette
            case .glabella: return glabella
            case .toneEvening: return toneEvening
            case .redness: return redness
            case .shine: return shine
            }
        }
        set {
            switch key {
            case .darkCircles: darkCircles = newValue
            case .nasolabial: nasolabial = newValue
            case .marionette: marionette = newValue
            case .glabella: glabella = newValue
            case .toneEvening: toneEvening = newValue
            case .redness: redness = newValue
            case .shine: shine = newValue
            }
        }
    }

    /// SkinRefinementKey.allCases 순서의 정밀 값.
    public var refinementValues: [Double] { SkinRefinementKey.allCases.map { self[$0] } }
    /// 정밀 값 중 0이 아닌 것이 있는지.
    public var hasRefinement: Bool { refinementValues.contains { $0 != 0 } }
    /// 렌더 결과를 바꾸는 값이 있는지.
    public var hasEffect: Bool { smoothing != 0 || autoBlemish || hasRefinement }
    public var numericValues: [Double] { [smoothing] + refinementValues }
}
```

`AdjustmentRange.swift`의 `bodyShape(_:)` 아래에 추가:

```swift
    /// 붉은기(맑게 ↔ 혈색)만 양방향이다.
    public static func skinRefinement(_ key: SkinRefinementKey) -> ClosedRange<Double> {
        key == .redness ? bipolar : unit
    }
```

`shared/recipe-schema/edit-recipe.v2.schema.json`의 `portrait.skin.properties`를 다음으로 바꾼다:

```json
          "properties": {
            "smoothing": { "type": "number", "default": 0, "minimum": 0, "maximum": 1 },
            "autoBlemish": { "type": "boolean", "default": false },
            "darkCircles": { "type": "number", "default": 0, "minimum": 0, "maximum": 1 },
            "nasolabial": { "type": "number", "default": 0, "minimum": 0, "maximum": 1, "description": "팔자주름(코 날개 → 입꼬리)." },
            "marionette": { "type": "number", "default": 0, "minimum": 0, "maximum": 1, "description": "마리오네트 주름(입꼬리 → 턱 쪽)." },
            "glabella": { "type": "number", "default": 0, "minimum": 0, "maximum": 1, "description": "미간 주름." },
            "toneEvening": { "type": "number", "default": 0, "minimum": 0, "maximum": 1, "description": "피부 얼룩 고르기(저주파를 피부 평균 쪽으로)." },
            "redness": { "type": "number", "default": 0, "minimum": -1, "maximum": 1, "description": "음수는 맑게(붉은 반점 줄임), 양수는 혈색." },
            "shine": { "type": "number", "default": 0, "minimum": 0, "maximum": 1, "description": "번들거림(밝은 반사 영역을 피부 평균 쪽으로)." }
          }
```

`shared/recipe-schema/README.md`:
1. "v2 형식 요점"의 `portrait`는 … 줄을 다음으로 바꾼다: `- \`portrait\`는 \`skin\`(피부 보정 \`smoothing\` 0~1, 자동 잡티 \`autoBlemish\`, G의 피부 정밀 \`darkCircles\`·\`nasolabial\`·\`marionette\`·\`glabella\`·\`toneEvening\`·\`shine\` 0~1과 \`redness\` −1~1), \`face\`(얼굴형 10개, 가운데 0인 양방향, \`smile\`만 0~1), \`features\`(눈 또렷하게·치아 미백·입술 생기 0~1)로 나뉩니다.`
2. 범위 표의 `portrait.skin.smoothing` 줄 아래에 `| \`portrait.skin.{darkCircles,nasolabial,marionette,glabella,toneEvening,shine}\` | 0 … 1 | 0 … 1 |`과 `| \`portrait.skin.redness\` | −1 … 1 | −1 … 1 |`을 더한다.
3. "키를 추가할 때의 규칙 (B~F)" 제목을 "키를 추가할 때의 규칙 (B~G)"로 바꾸고 첫 문단 끝에 문장을 더한다: `G 단계는 \`portrait.skin\`에 피부 정밀 7개, 최상위 \`bodySkin\`·\`effects\`를 같은 규칙으로 더했습니다(기본값 0, schemaVersion 2 유지).`

- [ ] **Step 4: 통과 확인**

Run: `cd apple && swift test` → `Executed 45 tests`(Shared) · `225`(Rendering) · `30`(Library) · `4`(Export) · `29`(Editing), 모두 `with 0 failures`. `swift format lint` 출력 없음. `./scripts/verify-modules.sh` 통과.

- [ ] **Step 5: 커밋**

```bash
git add apple/Sources/MellowShared/API/SkinAdjustments.swift apple/Sources/MellowShared/API/AdjustmentRange.swift shared/recipe-schema/edit-recipe.v2.schema.json shared/recipe-schema/README.md apple/Tests/MellowSharedTests/EditRecipeCodingTests.swift apple/Tests/MellowSharedTests/RecipeSchemaTests.swift
git commit -m "feat(shared): 피부 정밀 7종 레시피 키 추가

portrait.skin에 darkCircles·nasolabial·marionette·glabella·toneEvening·redness·shine을
기본값 0으로 더한다(schemaVersion 2 유지). 붉은기만 가운데 0 양방향이다.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 2: 편집 규칙 — skinRefinement 변경, 자동 보정이 정밀 값을 보존

**Files:**
- Modify: `apple/Sources/MellowEditing/API/EditChange.swift`, `EditingPolicy.swift`, `EditDocument.swift`
- Test: `apple/Tests/MellowEditingTests/EditDocumentTests.swift`

**Interfaces:**
- Consumes: `SkinRefinementKey`, `SkinAdjustments.subscript`, `AdjustmentRange.skinRefinement(_:)`.
- Produces: `EditChange.skinRefinement(SkinRefinementKey, Double)`(`affectsGeometry == false`), `EditingPolicy.skinRefinementRange(_:)`. `applyAuto`는 `portrait.skin.smoothing`·`autoBlemish`만 바꾼다.

설계 근거: 스펙 1.2. 정밀 보정은 색만 바꾸므로 수동 편집 잠금 대상이 아니다. 기존 `applyAuto`는 `updated.portrait.skin = suggestion.portrait.skin`으로 그룹 전체를 덮어써 정밀 값을 0으로 지우므로 두 필드만 쓰도록 고친다(스펙 결정 표).

- [ ] **Step 1: 실패하는 테스트 작성**

`EditDocumentTests.swift`의 `testApplyMakeupLookIsOneUndoStepAndPartEditsDetachLook` 뒤에 추가:

```swift
    func testSkinRefinementChangesClampAreNotLockedAndUndoOneStepEach() {
        var document = EditDocument()
        document.appendLocalEdit(.spot(RetouchSpot(x: 0.5, y: 0.5, sourceX: 0.4, sourceY: 0.4, radius: 0.02)))
        let steps = document.undoStack.count
        XCTAssertFalse(EditChange.skinRefinement(.redness, 0.5).affectsGeometry)
        XCTAssertNil(document.set(.skinRefinement(.darkCircles, 1.7)), "색만 바꾸므로 수동 편집이 있어도 잠기지 않는다")
        XCTAssertEqual(document.recipe.portrait.skin.darkCircles, 1)
        XCTAssertNil(document.set(.skinRefinement(.redness, -3)))
        XCTAssertEqual(document.recipe.portrait.skin.redness, -1, "붉은기만 양방향")
        document.set(.skinRefinement(.shine, -0.2))
        XCTAssertEqual(document.recipe.portrait.skin.shine, 0, "한 방향 항목의 음수는 0")
        XCTAssertEqual(document.undoStack.count, steps + 2, "값이 실제로 바뀐 변경마다 한 단계")
        XCTAssertEqual(EditingPolicy.skinRefinementRange(.redness), EditingPolicy.bipolarRange)
        XCTAssertEqual(EditingPolicy.skinRefinementRange(.toneEvening), EditingPolicy.unitRange)
        document.undo()
        XCTAssertEqual(document.recipe.portrait.skin.redness, 0)
        XCTAssertEqual(document.recipe.portrait.skin.darkCircles, 1)
    }

    func testApplyAutoKeepsSkinRefinements() {
        var document = EditDocument()
        document.set(.skinRefinement(.darkCircles, 0.6))
        document.set(.skinRefinement(.redness, -0.3))
        let suggestion = AutoEnhanceSuggestion(
            color: ColorAdjustments(exposure: 0.2), detail: DetailAdjustments(),
            portrait: PortraitAdjustments(skin: SkinAdjustments(smoothing: 0.3, autoBlemish: true)))
        XCTAssertTrue(document.applyAuto(suggestion))
        XCTAssertEqual(
            document.recipe.portrait.skin,
            SkinAdjustments(smoothing: 0.3, autoBlemish: true, darkCircles: 0.6, redness: -0.3),
            "자동 보정은 피부 보정·자동 잡티만 쓰고 정밀 값은 지우지 않는다")
        XCTAssertFalse(document.applyAuto(suggestion), "같은 값이면 아무것도 하지 않는다")
        var other = EditDocument()
        other.applyFromBatch(PresetValues(of: document.recipe))
        XCTAssertEqual(other.recipe.portrait.skin.darkCircles, 0.6, "일괄 적용은 정밀 값을 나른다")
    }
```

- [ ] **Step 2: 실패 확인**

Run: `cd apple && swift test --filter EditDocumentTests` → 컴파일 실패(`type 'EditChange' has no member 'skinRefinement'`).

- [ ] **Step 3: 구현**

`EditChange.swift`: `case autoBlemish(Bool)` 아래에 `case skinRefinement(SkinRefinementKey, Double)`. `affectsGeometry`는 그대로(false).

`EditingPolicy.swift`: `bodyShapeRange(_:)` 아래에 추가:

```swift
    /// 붉은기만 양방향이다.
    public static func skinRefinementRange(_ key: SkinRefinementKey) -> ClosedRange<Double> {
        AdjustmentRange.skinRefinement(key)
    }
```

`EditDocument.swift`:
1. `set`의 `case .autoBlemish(let flag): …` 아래에 추가:

```swift
        case .skinRefinement(let key, let value):
            updated.portrait.skin[key] = EditingPolicy.clamped(value, to: EditingPolicy.skinRefinementRange(key))
```

2. `applyAuto`의 `updated.portrait.skin = suggestion.portrait.skin` 한 줄을 두 줄로 바꾼다:

```swift
        updated.portrait.skin.smoothing = suggestion.portrait.skin.smoothing
        updated.portrait.skin.autoBlemish = suggestion.portrait.skin.autoBlemish
```

같은 함수의 doc 주석 "색·디테일·피부·눈 또렷하게만 바꾸고"를 "색·디테일·피부 보정·자동 잡티·눈 또렷하게만 바꾸고"로, 건드리지 않는 목록에 "피부 정밀"을 더한다.

- [ ] **Step 4: 통과 확인**

Run: `cd apple && swift test` → Editing `Executed 31 tests`, 나머지 Task 1과 같음, 모두 0 failures. lint 출력 없음.

- [ ] **Step 5: 커밋**

```bash
git add apple/Sources/MellowEditing/API/EditChange.swift apple/Sources/MellowEditing/API/EditingPolicy.swift apple/Sources/MellowEditing/API/EditDocument.swift apple/Tests/MellowEditingTests/EditDocumentTests.swift
git commit -m "feat(editing): 피부 정밀 편집 변경과 자동 보정의 정밀 값 보존

skinRefinement 변경은 키별 범위로 자르고 잠기지 않는다. applyAuto는
피부 보정·자동 잡티만 덮어써 다크서클·붉은기 값을 지우지 않는다.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 3: 주름 띠 마스크 — FaceRegions+Folds, Oval.tilt

**Files:**
- Create: `apple/Sources/MellowRendering/Domain/FaceRegions+Folds.swift`
- Modify: `apple/Sources/MellowRendering/Domain/FaceRegions+Makeup.swift` (`Oval.tilt`, `softMask` 각도, `eyeMidline` internal)
- Modify: `apple/Tests/MellowRenderingTests/RenderingTestSupport.swift` (`SyntheticFace` 표본 점)
- Test: `apple/Tests/MellowRenderingTests/FoldRegionsTests.swift`(새 파일)

**Interfaces:**
- Consumes: `FaceFrame`(`eyes`·`local`·`imagePoint`·`faceWidth`), `FaceRegions.eyePolygons`·`landmarkPolygon`·`softMask`·`Oval`, `FaceRegions.eyeMidline`.
- Produces: `FaceRegions.darkCircleMask`·`nasolabialMask`·`marionetteMask`·`glabellaMask(face:extent:tuning:cache:) -> RegionMask?`, `Oval.tilt`.

설계 근거: 스펙 1.5. 타원 × 피부 다각형 비트맵(`softMask`)이라 눈·입 안은 0이고 기울어진 얼굴을 따라가며 캐시 항목을 늘리지 않는다. 표본 점은 합성 얼굴의 얼굴 좌표(원점 (256, 200), x축 가로, 얼굴 폭 280)에서 계산했다: 왼눈 중심 (200, 300)·폭 56·높이 28 → 다크서클 중심 v = 86 − 28 × 0.6 = 69.2(y 269.2), 반지름 (33.6, 22.4). 왼쪽 팔자 선분은 코 날개 (236, 190) → 입꼬리 (208, 140), 길이 57.3, 바깥쪽 2%(5.6px) 민 중심 ≈ (217, 168), 띠 위 표본 (220, 173)은 입술 보호 영역(경계에서 14px)과 21px 떨어져 있다. 왼쪽 마리오네트는 입꼬리 (208, 140)에서 아래로 바깥 15° 기운 방향 (−0.257, −0.966)으로 16.8px 내려간 점을 바깥으로 5.6px 민 중심 ≈ (198, 125), 반지름 (19.6, 8.4), 표본 (196, 124)은 입술 보호 영역 경계와 20px 떨어져 있다. 미간은 눈썹 안쪽 끝 (232, 338)·(280, 338)의 중점 (256, 338), 반지름 (26.8, 19.6).

- [ ] **Step 1: 표본 점과 실패하는 테스트 작성**

`RenderingTestSupport.swift`의 메이크업 표본 점 extension(`static let chinTip …` 뒤) 아래에 extension을 추가:

```swift
/// 주름 띠 표본 점. 얼굴 좌표(원점 (256, 200), 얼굴 폭 280)에서 계산한 위치다. 계산은 G1 계획 Task 3 참고.
extension SyntheticFace {
    /// 다크서클 타원 안(중심 y 269.2, 세로 반지름 22.4). 눈 보호 영역(아래끝 286 − 14)보다 10px 아래.
    static let underLeftEye = CGPoint(x: 200, y: 262)
    static let underRightEye = CGPoint(x: 312, y: 262)
    /// 얼굴을 중심 둘레로 30° 돌렸을 때의 under*Eye 자리.
    static let rolledUnderLeftEye = CGPoint(x: 176.5, y: 225.7)
    static let rolledUnderRightEye = CGPoint(x: 273.5, y: 281.7)
    /// 코 날개 → 입꼬리 띠 위(코 쪽 40% 지점을 바깥으로 민 자리).
    static let leftNasolabial = CGPoint(x: 220, y: 173)
    static let rightNasolabial = CGPoint(x: 292, y: 173)
    /// 입꼬리에서 턱 쪽으로 내려간 마리오네트 타원 안.
    static let leftMarionette = CGPoint(x: 196, y: 124)
    static let rightMarionette = CGPoint(x: 316, y: 124)
    /// 두 눈썹 안쪽 끝 사이.
    static let glabella = CGPoint(x: 256, y: 338)
}
```

`apple/Tests/MellowRenderingTests/FoldRegionsTests.swift`:

```swift
import CoreImage
import MellowShared
import XCTest

@testable import MellowRendering

final class FoldRegionsTests: XCTestCase {
    typealias Support = RenderingTestSupport

    private let extent = SyntheticFace.extent
    private let tuning = RenderTuning()

    func testDarkCircleMaskSitsUnderBothEyesAndLeavesEyesAndCheeks() throws {
        let face = SyntheticFace.make().face
        let mask = try XCTUnwrap(FaceRegions.darkCircleMask(face: face, extent: extent, tuning: tuning))
        XCTAssertEqual(mask.image.extent, extent)
        let pixels = try Support.grid(mask.image)
        XCTAssertGreaterThan(pixels.red(SyntheticFace.underLeftEye), 128)
        XCTAssertGreaterThan(pixels.red(SyntheticFace.underRightEye), 128)
        XCTAssertEqual(
            Double(pixels.red(SyntheticFace.underLeftEye)), Double(pixels.red(SyntheticFace.underRightEye)),
            accuracy: 2, "좌우 대칭")
        let outside = [
            SyntheticFace.leftEye, SyntheticFace.scleraPoint, SyntheticFace.cheek, SyntheticFace.forehead,
            SyntheticFace.mouth, SyntheticFace.outside,
        ]
        for point in outside {
            XCTAssertEqual(pixels.red(point), 0, "다크서클 밖 \(point)")
        }
        XCTAssertFalse(mask.bounds.contains(SyntheticFace.mouth), "입은 계산 영역 밖")
    }

    func testNasolabialMaskRunsFromNoseWingToMouthCornerOnBothSides() throws {
        let face = SyntheticFace.make().face
        let mask = try XCTUnwrap(FaceRegions.nasolabialMask(face: face, extent: extent, tuning: tuning))
        let pixels = try Support.grid(mask.image)
        XCTAssertGreaterThan(pixels.red(SyntheticFace.leftNasolabial), 128)
        XCTAssertGreaterThan(pixels.red(SyntheticFace.rightNasolabial), 128)
        XCTAssertEqual(
            Double(pixels.red(SyntheticFace.leftNasolabial)), Double(pixels.red(SyntheticFace.rightNasolabial)),
            accuracy: 2, "좌우 대칭")
        let outside = [
            SyntheticFace.mouth, SyntheticFace.lipPoint, SyntheticFace.philtrum, SyntheticFace.cheek,
            SyntheticFace.leftEye, SyntheticFace.leftMarionette, SyntheticFace.chinTip, SyntheticFace.outside,
        ]
        for point in outside {
            XCTAssertEqual(pixels.red(point), 0, "팔자 띠 밖 \(point)")
        }
    }

    func testMarionetteMaskDropsFromTheMouthCornersTowardTheChin() throws {
        let face = SyntheticFace.make().face
        let mask = try XCTUnwrap(FaceRegions.marionetteMask(face: face, extent: extent, tuning: tuning))
        let pixels = try Support.grid(mask.image)
        XCTAssertGreaterThan(pixels.red(SyntheticFace.leftMarionette), 128)
        XCTAssertGreaterThan(pixels.red(SyntheticFace.rightMarionette), 128)
        XCTAssertEqual(
            Double(pixels.red(SyntheticFace.leftMarionette)), Double(pixels.red(SyntheticFace.rightMarionette)),
            accuracy: 2, "좌우 대칭")
        let outside = [
            SyntheticFace.mouth, SyntheticFace.lipPoint, SyntheticFace.leftNasolabial, SyntheticFace.cheek,
            SyntheticFace.chinTip, SyntheticFace.outside,
        ]
        for point in outside {
            XCTAssertEqual(pixels.red(point), 0, "마리오네트 띠 밖 \(point)")
        }
        XCTAssertNotNil(
            FaceRegions.marionetteMask(face: face.removing([.nose]), extent: extent, tuning: tuning),
            "방향이 고정이라 코가 없어도 만든다")
    }

    func testGlabellaMaskSitsBetweenTheBrows() throws {
        let face = SyntheticFace.make().face
        let mask = try XCTUnwrap(FaceRegions.glabellaMask(face: face, extent: extent, tuning: tuning))
        let pixels = try Support.grid(mask.image)
        XCTAssertGreaterThan(pixels.red(SyntheticFace.glabella), 128)
        let outside = [
            SyntheticFace.leftBrowCenter, SyntheticFace.forehead, SyntheticFace.leftEye, SyntheticFace.bridge,
            SyntheticFace.cheek,
        ]
        for point in outside {
            XCTAssertEqual(pixels.red(point), 0, "미간 밖 \(point)")
        }
    }

    func testFoldMasksFollowARolledFace() throws {
        let rolled = SyntheticFace.make().face.rotated(by: .pi / 6, about: SyntheticFace.pivot)
        let pixels = try Support.grid(
            XCTUnwrap(FaceRegions.darkCircleMask(face: rolled, extent: extent, tuning: tuning)).image)
        XCTAssertGreaterThan(pixels.red(SyntheticFace.rolledUnderLeftEye), 128)
        XCTAssertGreaterThan(pixels.red(SyntheticFace.rolledUnderRightEye), 128)
        XCTAssertEqual(
            Double(pixels.red(SyntheticFace.rolledUnderLeftEye)), Double(pixels.red(SyntheticFace.rolledUnderRightEye)),
            accuracy: 2, "돌려도 좌우 대칭")
        XCTAssertNotNil(FaceRegions.nasolabialMask(face: rolled, extent: extent, tuning: tuning))
        XCTAssertNotNil(FaceRegions.marionetteMask(face: rolled, extent: extent, tuning: tuning))
        XCTAssertNotNil(FaceRegions.glabellaMask(face: rolled, extent: extent, tuning: tuning))
    }

    func testFoldMasksNeedTheirLandmarks() throws {
        let boxOnly = SyntheticFace.make(landmarks: false).face
        XCTAssertNil(FaceRegions.darkCircleMask(face: boxOnly, extent: extent, tuning: tuning))
        XCTAssertNil(FaceRegions.nasolabialMask(face: boxOnly, extent: extent, tuning: tuning))
        XCTAssertNil(FaceRegions.marionetteMask(face: boxOnly, extent: extent, tuning: tuning))
        XCTAssertNil(FaceRegions.glabellaMask(face: boxOnly, extent: extent, tuning: tuning))
        let face = SyntheticFace.make().face
        XCTAssertNil(FaceRegions.nasolabialMask(face: face.removing([.nose]), extent: extent, tuning: tuning))
        XCTAssertNil(FaceRegions.nasolabialMask(face: face.removing([.outerLips]), extent: extent, tuning: tuning))
        XCTAssertNil(FaceRegions.marionetteMask(face: face.removing([.outerLips]), extent: extent, tuning: tuning))
        XCTAssertNil(FaceRegions.glabellaMask(face: face.removing([.leftEyebrow]), extent: extent, tuning: tuning))
        let noPupils = face.removing([.leftPupil, .rightPupil])
        XCTAssertNotNil(FaceRegions.darkCircleMask(face: noPupils, extent: extent, tuning: tuning), "동공이 없어도 눈 중심으로")
        let oneEye = try XCTUnwrap(
            FaceRegions.darkCircleMask(face: face.removing([.leftEye]), extent: extent, tuning: tuning))
        let pixels = try Support.grid(oneEye.image)
        XCTAssertGreaterThan(pixels.red(SyntheticFace.underRightEye), 128, "남은 눈 아래는 그대로")
        XCTAssertEqual(pixels.red(SyntheticFace.underLeftEye), 0, "다각형이 없는 눈은 띠를 만들지 않는다")
    }
}
```

- [ ] **Step 2: 실패 확인**

Run: `cd apple && swift test --filter FoldRegionsTests` → 컴파일 실패(`type 'FaceRegions' has no member 'darkCircleMask'`).

- [ ] **Step 3: 구현**

`FaceRegions+Makeup.swift`:
1. `struct Oval { let center: CGPoint; let radii: CGSize }`를 다음으로 바꾼다(한 줄 한 문장으로 풀어 쓴다):

```swift
    /// 얼굴 x축 방향으로 돌려 그리는 타원 하나(픽셀). tilt는 얼굴 x축 기준 추가 회전(라디안, 반시계)이다.
    struct Oval {
        let center: CGPoint
        let radii: CGSize
        var tilt: CGFloat = 0
    }
```

2. `softMask`의 `MaskBuilder.ellipse(center: oval.center, radii: oval.radii, angle: angle, extent: extent)`를 `angle: angle + oval.tilt`로 바꾼다.
3. `private static func eyeMidline(_ frame: FaceFrame) -> CGFloat`를 `static func eyeMidline(_ frame: FaceFrame) -> CGFloat`로 바꾼다(internal).

`apple/Sources/MellowRendering/Domain/FaceRegions+Folds.swift`:

```swift
import CoreImage
import MellowShared

/// 주름 띠 위치 비율. 특징점에 주름선이 없어 코 날개·입꼬리·눈썹 안쪽 끝으로 어림한 값이다.
/// 길이는 얼굴 폭·눈 폭·눈 높이 기준, 각도는 얼굴 x축 기준이다.
private enum FoldShape {
    /// 다크서클 중심을 눈 아래끝에서 내리는 양. 눈 높이 배수.
    static let darkCircleDrop: CGFloat = 0.6
    /// 다크서클 타원 반지름. 눈 폭·눈 높이 배수.
    static let darkCircleRadiusU: CGFloat = 0.6
    static let darkCircleRadiusV: CGFloat = 0.8
    /// 눈 다각형을 그 눈의 것으로 보는 중심 거리 상한. 눈 폭 배수.
    static let eyeMatchDistance: CGFloat = 1
    /// 팔자 띠의 반 길이(코 날개 → 입꼬리 선분 길이 배수)와 반 폭(얼굴 폭 비율).
    static let nasolabialHalfLength: CGFloat = 0.55
    static let nasolabialHalfWidth: CGFloat = 0.035
    /// 띠를 선분에서 얼굴 바깥쪽으로 미는 양. 얼굴 폭 비율. 주름은 선분보다 바깥에 있다. 마리오네트도 같은 값을 쓴다.
    static let nasolabialOutset: CGFloat = 0.02
    /// 마리오네트 띠 길이(입꼬리에서 턱 쪽으로)와 타원 반지름. 얼굴 폭 비율.
    static let marionetteLength: CGFloat = 0.12
    static let marionetteRadiusU: CGFloat = 0.07
    static let marionetteRadiusV: CGFloat = 0.03
    /// 마리오네트 띠 방향. 얼굴 −v(턱 쪽)에서 바깥쪽으로 기운 각도(라디안, 약 15°). 입꼬리 아래에는 특징점이 없어 고정한다.
    static let marionetteTiltFromVertical: CGFloat = 0.26
    /// 미간 타원. 안쪽 눈썹 끝 간격의 절반에 더하는 여유와 세로 반지름. 얼굴 폭 비율.
    static let glabellaMargin: CGFloat = 0.01
    static let glabellaRadiusV: CGFloat = 0.07
    /// 눈썹 안쪽 끝으로 치는 점의 허용 오차. 얼굴 폭 비율.
    static let browEndTolerance: CGFloat = 0.01
}

extension FaceRegions {
    /// 눈 아래 다크서클 띠. 두 눈 중심이 있어야 하고, 눈 다각형이 없는 눈은 뺀다. 눈 안은 피부 비트맵의 보호 영역이 0으로 만든다.
    static func darkCircleMask(
        face: FaceGeometry, extent: CGRect, tuning: RenderTuning, cache: RegionMaskCache? = nil
    ) -> RegionMask? {
        guard let frame = FaceFrame(face: face, extent: extent), frame.eyes.count == 2 else { return nil }
        let polygons = eyePolygons(face: face, extent: extent).map { $0.map(frame.local) }
        var ovals: [Oval] = []
        for eye in frame.eyes {
            let center = frame.local(eye.center)
            let nearest = polygons.min {
                abs(FaceFrame.centroid($0).x - center.x) < abs(FaceFrame.centroid($1).x - center.x)
            }
            guard let polygon = nearest,
                abs(FaceFrame.centroid(polygon).x - center.x) < eye.width * FoldShape.eyeMatchDistance,
                let top = polygon.map(\.y).max(), let bottom = polygon.map(\.y).min(), top > bottom
            else { continue }
            let height = top - bottom
            let oval = Oval(
                center: frame.imagePoint(u: center.x, v: bottom - height * FoldShape.darkCircleDrop),
                radii: CGSize(
                    width: eye.width * FoldShape.darkCircleRadiusU, height: height * FoldShape.darkCircleRadiusV))
            ovals.append(oval)
        }
        return softMask(ovals, face: face, frame: frame, extent: extent, tuning: tuning, cache: cache)
    }

    /// 팔자 띠(코 날개 → 입꼬리). 코와 바깥 입술이 있어야 한다.
    static func nasolabialMask(
        face: FaceGeometry, extent: CGRect, tuning: RenderTuning, cache: RegionMaskCache? = nil
    ) -> RegionMask? {
        guard let frame = FaceFrame(face: face, extent: extent),
            let nose = landmarkPolygon(face, .nose, extent)?.map(frame.local),
            let lips = landmarkPolygon(face, .outerLips, extent)?.map(frame.local)
        else { return nil }
        let width = frame.faceWidth
        let midline = eyeMidline(frame)
        var ovals: [Oval] = []
        for side in [CGFloat(-1), 1] {
            guard let wing = nose.max(by: { ($0.x - midline) * side < ($1.x - midline) * side }),
                let corner = lips.max(by: { ($0.x - midline) * side < ($1.x - midline) * side })
            else { continue }
            let dx = corner.x - wing.x
            let dy = corner.y - wing.y
            let length = hypot(dx, dy)
            guard length > 0 else { continue }
            let direction = CGPoint(x: dx / length, y: dy / length)
            let middle = CGPoint(x: (wing.x + corner.x) / 2, y: (wing.y + corner.y) / 2)
            ovals.append(
                bandOval(
                    frame: frame, center: middle, direction: direction, side: side,
                    radii: CGSize(
                        width: length * FoldShape.nasolabialHalfLength, height: width * FoldShape.nasolabialHalfWidth)))
        }
        return softMask(ovals, face: face, frame: frame, extent: extent, tuning: tuning, cache: cache)
    }

    /// 마리오네트 띠(입꼬리 → 턱 쪽). 바깥 입술만 있으면 된다. 방향은 얼굴 −v에서 바깥쪽으로 marionetteTiltFromVertical 기운 고정값이다.
    static func marionetteMask(
        face: FaceGeometry, extent: CGRect, tuning: RenderTuning, cache: RegionMaskCache? = nil
    ) -> RegionMask? {
        guard let frame = FaceFrame(face: face, extent: extent),
            let lips = landmarkPolygon(face, .outerLips, extent)?.map(frame.local)
        else { return nil }
        let width = frame.faceWidth
        let midline = eyeMidline(frame)
        let along = CGFloat(sin(Double(FoldShape.marionetteTiltFromVertical)))
        let down = CGFloat(cos(Double(FoldShape.marionetteTiltFromVertical)))
        var ovals: [Oval] = []
        for side in [CGFloat(-1), 1] {
            guard let corner = lips.max(by: { ($0.x - midline) * side < ($1.x - midline) * side }) else { continue }
            let direction = CGPoint(x: side * along, y: -down)
            let half = width * FoldShape.marionetteLength / 2
            let middle = CGPoint(x: corner.x + direction.x * half, y: corner.y + direction.y * half)
            ovals.append(
                bandOval(
                    frame: frame, center: middle, direction: direction, side: side,
                    radii: CGSize(width: width * FoldShape.marionetteRadiusU, height: width * FoldShape.marionetteRadiusV)))
        }
        return softMask(ovals, face: face, frame: frame, extent: extent, tuning: tuning, cache: cache)
    }

    /// 얼굴 좌표의 중심·방향으로 놓는 띠 타원. 중심을 방향에 수직인 바깥쪽(side)으로 얼굴 폭 × nasolabialOutset 민다.
    private static func bandOval(frame: FaceFrame, center: CGPoint, direction: CGPoint, side: CGFloat, radii: CGSize)
        -> Oval
    {
        var normal = CGPoint(x: -direction.y, y: direction.x)
        if normal.x * side < 0 {
            normal = CGPoint(x: -normal.x, y: -normal.y)
        }
        let outset = frame.faceWidth * FoldShape.nasolabialOutset
        let shifted = CGPoint(x: center.x + normal.x * outset, y: center.y + normal.y * outset)
        return Oval(
            center: frame.imagePoint(u: shifted.x, v: shifted.y), radii: radii, tilt: atan2(direction.y, direction.x))
    }

    /// 두 눈썹 안쪽 끝 사이의 미간. 눈썹이 둘 다 있어야 한다.
    static func glabellaMask(
        face: FaceGeometry, extent: CGRect, tuning: RenderTuning, cache: RegionMaskCache? = nil
    ) -> RegionMask? {
        guard let frame = FaceFrame(face: face, extent: extent) else { return nil }
        let brows = [FaceLandmark.leftEyebrow, .rightEyebrow].compactMap {
            landmarkPolygon(face, $0, extent)?.map(frame.local)
        }
        guard brows.count == 2 else { return nil }
        let width = frame.faceWidth
        let midline = eyeMidline(frame)
        let ends = brows.map { innerEnd(of: $0, midline: midline, tolerance: width * FoldShape.browEndTolerance) }
        let gap = abs(ends[0].x - ends[1].x)
        let center = CGPoint(x: (ends[0].x + ends[1].x) / 2, y: (ends[0].y + ends[1].y) / 2)
        let oval = Oval(
            center: frame.imagePoint(u: center.x, v: center.y),
            radii: CGSize(width: gap / 2 + width * FoldShape.glabellaMargin, height: width * FoldShape.glabellaRadiusV))
        return softMask([oval], face: face, frame: frame, extent: extent, tuning: tuning, cache: cache)
    }

    /// 눈썹 점 중 두 눈 가운데 선에 가장 가까운 점들(tolerance 안)의 평균. 위아래 두 줄인 눈썹은 가운데 높이가 된다.
    private static func innerEnd(of brow: [CGPoint], midline: CGFloat, tolerance: CGFloat) -> CGPoint {
        let nearest = brow.map { abs($0.x - midline) }.min() ?? 0
        return FaceFrame.centroid(brow.filter { abs($0.x - midline) <= nearest + tolerance })
    }
}
```

- [ ] **Step 4: 통과 확인**

Run: `cd apple && swift test` → Rendering `Executed 231 tests`, 0 failures(기존 메이크업 마스크 테스트도 그대로 통과해야 한다). lint 출력 없음.

- [ ] **Step 5: 커밋**

```bash
git add apple/Sources/MellowRendering/Domain/FaceRegions+Folds.swift apple/Sources/MellowRendering/Domain/FaceRegions+Makeup.swift apple/Tests/MellowRenderingTests/RenderingTestSupport.swift apple/Tests/MellowRenderingTests/FoldRegionsTests.swift
git commit -m "feat(rendering): 다크서클·팔자·마리오네트·미간 주름 띠 마스크

얼굴 좌표 타원 × 피부 다각형 비트맵으로 눈 아래·코 날개→입꼬리·입꼬리→턱 쪽·
눈썹 사이 띠를 만든다. 타원에 추가 회전을 더해 기운 띠를 그린다.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 4: 주름 밝히기 — foldLift 커널, SkinRefinement, SkinStage 구조

**Files:**
- Modify: `apple/Sources/MellowRendering/API/RenderTuning.swift` (상수 3개)
- Modify: `apple/Sources/MellowRendering/Domain/SkinKernels.swift` (`foldLift`)
- Create: `apple/Sources/MellowRendering/Domain/SkinRefinement.swift`
- Modify: `apple/Sources/MellowRendering/Domain/SkinStage.swift` (`apply` 재구성, `clamped`, `folds`)
- Test: `apple/Tests/MellowRenderingTests/SkinStageTests.swift`

**Interfaces:**
- Consumes: Task 3 마스크, `FrequencySeparation.blurred`, `MaskBuilder.blend`, `AdjustmentRange`.
- Produces: `SkinKernels.foldLift(image:low:surround:amount:extent:)`, `SkinRefinement.liftFold(_:region:faceWidth:amount:tuning:extent:)`, `SkinStage.clamped(_:)`, `SkinStage.folds(for:skin:context:)`. 기존 `healSpots`는 그대로.

설계 근거: 스펙 1.6 주름 밝히기. `rgb' = rgb + max(surround − low, 0) × amount`라 어두운 만큼만 올리고 모공 대역은 더하는 항에 없다. 띠가 어긋나 보통 피부에 걸려도 `surround − low ≈ 0`이라 밝은 얼룩이 생기지 않는다.

- [ ] **Step 1: 실패하는 테스트 작성**

`SkinStageTests.swift`의 private 도우미(`ellipse` 아래)에 추가:

```swift
    /// center 둘레 타원 안 픽셀을 factor배 어둡게 한다(그늘·주름 흉내).
    private func darkened(_ image: CIImage, at center: CGPoint, radii: CGSize, factor: Double) -> CIImage {
        let dim = image.applyingFilter(
            "CIColorMatrix",
            parameters: [
                "inputRVector": CIVector(x: factor, y: 0, z: 0, w: 0),
                "inputGVector": CIVector(x: 0, y: factor, z: 0, w: 0),
                "inputBVector": CIVector(x: 0, y: 0, z: factor, w: 0),
            ])
        let mask = Support.hardEllipse(center: center, radii: radii, extent: SyntheticFace.extent)
        return dim.applyingFilter(
            "CIBlendWithMask", parameters: [kCIInputBackgroundImageKey: image, kCIInputMaskImageKey: mask]
        ).cropped(to: SyntheticFace.extent)
    }

    /// 주름 띠 테스트의 그늘 밝기 배율(선형).
    private static let shadowFactor = 0.6
    /// 밝힌 뒤 기대하는 최소 빨강 증가(바이트).
    private static let liftMinimum = 12
```

`testSkinRenderReusesCachedMaskAcrossRenders` 뒤에 추가:

```swift
    func testDarkCirclesLiftOnlyTheShadowUnderTheEyes() throws {
        let base = SyntheticFace.make()
        let radii = CGSize(width: 30, height: 10)
        var image = darkened(base.image, at: SyntheticFace.underLeftEye, radii: radii, factor: Self.shadowFactor)
        image = darkened(image, at: SyntheticFace.underRightEye, radii: radii, factor: Self.shadowFactor)
        let synthetic = SyntheticFace(image: image, face: base.face)
        let before = try Support.grid(image)
        let after = try Support.grid(render(synthetic, skin: SkinAdjustments(darkCircles: 1)))
        for point in [SyntheticFace.underLeftEye, SyntheticFace.underRightEye] {
            XCTAssertGreaterThanOrEqual(
                Int(after.red(point)), Int(before.red(point)) + Self.liftMinimum, "\(point) 그늘이 밝아진다")
        }
        let outside = [
            SyntheticFace.leftEye, SyntheticFace.scleraPoint, SyntheticFace.cheek, SyntheticFace.mouth,
            SyntheticFace.forehead, SyntheticFace.backgroundInsideContour, SyntheticFace.outside,
        ]
        for point in outside {
            XCTAssertEqual(after.rgba(point), before.rgba(point), "다크서클 띠 밖 \(point)")
        }
        let half = try Support.grid(render(synthetic, skin: SkinAdjustments(darkCircles: 0.5)))
        XCTAssertGreaterThan(half.red(SyntheticFace.underLeftEye), before.red(SyntheticFace.underLeftEye))
        XCTAssertLessThan(half.red(SyntheticFace.underLeftEye), after.red(SyntheticFace.underLeftEye), "0.5는 사이")
    }

    func testNasolabialAndMarionetteLiftTheirOwnFoldOnly() throws {
        let base = SyntheticFace.make()
        let radii = CGSize(width: 7, height: 7)
        var image = base.image
        for center in [SyntheticFace.leftNasolabial, SyntheticFace.leftMarionette] {
            image = darkened(image, at: center, radii: radii, factor: Self.shadowFactor)
        }
        let synthetic = SyntheticFace(image: image, face: base.face)
        let before = try Support.grid(image)
        let nasolabial = try Support.grid(render(synthetic, skin: SkinAdjustments(nasolabial: 1)))
        XCTAssertGreaterThanOrEqual(
            Int(nasolabial.red(SyntheticFace.leftNasolabial)),
            Int(before.red(SyntheticFace.leftNasolabial)) + Self.liftMinimum, "팔자주름이 밝아진다")
        XCTAssertEqual(
            nasolabial.rgba(SyntheticFace.leftMarionette), before.rgba(SyntheticFace.leftMarionette),
            "팔자 슬라이더는 마리오네트 띠를 건드리지 않는다")
        let marionette = try Support.grid(render(synthetic, skin: SkinAdjustments(marionette: 1)))
        XCTAssertGreaterThanOrEqual(
            Int(marionette.red(SyntheticFace.leftMarionette)),
            Int(before.red(SyntheticFace.leftMarionette)) + Self.liftMinimum, "마리오네트 주름이 밝아진다")
        XCTAssertEqual(
            marionette.rgba(SyntheticFace.leftNasolabial), before.rgba(SyntheticFace.leftNasolabial),
            "마리오네트 슬라이더는 팔자 띠를 건드리지 않는다")
        let outside = [
            SyntheticFace.mouth, SyntheticFace.lipPoint, SyntheticFace.philtrum, SyntheticFace.leftEye,
            SyntheticFace.forehead, SyntheticFace.chinTip, SyntheticFace.outside,
        ]
        for point in outside {
            XCTAssertEqual(nasolabial.rgba(point), before.rgba(point), "팔자 띠 밖 \(point)")
            XCTAssertEqual(marionette.rgba(point), before.rgba(point), "마리오네트 띠 밖 \(point)")
        }
    }

    func testGlabellaLiftsBetweenTheBrowsOnly() throws {
        let base = SyntheticFace.make()
        let image = darkened(
            base.image, at: SyntheticFace.glabella, radii: CGSize(width: 8, height: 8), factor: Self.shadowFactor)
        let synthetic = SyntheticFace(image: image, face: base.face)
        let before = try Support.grid(image)
        let after = try Support.grid(render(synthetic, skin: SkinAdjustments(glabella: 1)))
        XCTAssertGreaterThanOrEqual(
            Int(after.red(SyntheticFace.glabella)), Int(before.red(SyntheticFace.glabella)) + Self.liftMinimum)
        let outside = [
            SyntheticFace.leftBrowCenter, SyntheticFace.leftEye, SyntheticFace.forehead, SyntheticFace.bridge,
            SyntheticFace.cheek, SyntheticFace.mouth,
        ]
        for point in outside {
            XCTAssertEqual(after.rgba(point), before.rgba(point), "미간 밖 \(point)")
        }
    }

    func testMissingLandmarksSkipOnlyThatFold() throws {
        let base = SyntheticFace.make()
        let image = darkened(
            base.image, at: SyntheticFace.glabella, radii: CGSize(width: 8, height: 8), factor: Self.shadowFactor)
        let shaded = darkened(
            image, at: SyntheticFace.leftMarionette, radii: CGSize(width: 7, height: 7), factor: Self.shadowFactor)
        let noNose = SyntheticFace(image: shaded, face: base.face.removing([.nose]))
        let three = SkinAdjustments(nasolabial: 1, marionette: 1, glabella: 1)
        let before = try Support.grid(shaded)
        let after = try Support.grid(render(noNose, skin: three))
        XCTAssertGreaterThanOrEqual(
            Int(after.red(SyntheticFace.glabella)), Int(before.red(SyntheticFace.glabella)) + Self.liftMinimum,
            "코가 없어도 미간은 밝힌다")
        XCTAssertGreaterThanOrEqual(
            Int(after.red(SyntheticFace.leftMarionette)), Int(before.red(SyntheticFace.leftMarionette)) + Self.liftMinimum,
            "코가 없어도 마리오네트는 밝힌다(방향 고정)")
        XCTAssertEqual(after.rgba(SyntheticFace.leftNasolabial), before.rgba(SyntheticFace.leftNasolabial), "팔자만 건너뛴다")
        let boxOnly = SyntheticFace.make(landmarks: false)
        let folds = SkinAdjustments(darkCircles: 1, nasolabial: 1, marionette: 1, glabella: 1)
        XCTAssertTrue(try Support.bytes(render(boxOnly, skin: folds)) == Support.bytes(boxOnly.image), "특징점 없으면 그대로")
    }
```

- [ ] **Step 2: 실패 확인**

Run: `cd apple && swift test --filter SkinStageTests` → 컴파일 실패(`SkinAdjustments`에 `darkCircles:` 인자는 있으나 `SkinStage`가 아직 쓰지 않아 실행 시 `XCTAssertGreaterThanOrEqual` 실패). 실패 메시지에 "그늘이 밝아진다"가 보여야 한다.

- [ ] **Step 3: 구현**

`RenderTuning.swift`의 `blemishSourceOffset` 아래에 추가:

```swift
    /// 주름 밝히기가 보는 국소 저주파 반지름. 얼굴 폭 비율. 가장 좁은 띠(마리오네트 3%)의 절반이고 모공 대역(0.6%)보다 넓다.
    public var foldLowBandFraction: Double = 0.015
    /// 주름 둘레 피부 평균을 재는 반지름. 얼굴 폭 비율. 띠 폭(3.5~8%)보다 넓어야 주름 자신이 평균에 덜 들어간다.
    public var foldSurroundFraction: Double = 0.12
    /// 주름 밝히기 1에서 "주변 평균 − 국소 저주파"의 양수 차이를 더하는 비율. 100%면 평평해 보인다.
    public var foldLiftMax: Double = 0.9
```

`SkinKernels.swift`: 프로퍼티 `private let fold: CIColorKernel?`를 더하고 `init`에 커널을 만든다:

```swift
        fold = CIColorKernel(
            source: """
                kernel vec4 foldLift(__sample image, __sample low, __sample surround, float amount) {
                    vec3 gap = max(surround.rgb - low.rgb, vec3(0.0));
                    return vec4(image.rgb + gap * amount, image.a);
                }
                """)
```

메서드 추가:

```swift
    /// 주변 평균(surround)이 국소 저주파(low)보다 밝은 만큼만 amount 비율로 더한다. 모공 대역은 더하는 항에 없어 그대로다.
    func foldLift(image: CIImage, low: CIImage, surround: CIImage, amount: Double, extent: CGRect) throws -> CIImage {
        guard let fold else { throw MellowError.renderFailed }
        let arguments: [Any] = [image, low, surround, amount]
        guard let lifted = fold.apply(extent: extent, arguments: arguments) else { throw MellowError.renderFailed }
        return lifted
    }
```

`apple/Sources/MellowRendering/Domain/SkinRefinement.swift`:

```swift
import CoreImage
import MellowShared

/// 피부 정밀 중 영역 하나에 거는 보정(주름 밝히기·붉은기). SkinStage가 대상 얼굴마다 부른다.
enum SkinRefinement {
    /// 어두운 주름 띠를 둘레 피부 밝기 쪽으로 올린다. region.bounds 안에서만 계산하고 마스크 밖은 입력 바이트 그대로다.
    static func liftFold(
        _ image: CIImage, region: FaceRegions.RegionMask, faceWidth: CGFloat, amount: Double, tuning: RenderTuning,
        extent: CGRect
    ) throws -> CIImage {
        guard amount > 0 else { return image }
        let lowRadius = max(tuning.skinBlurMinimumRadius, Double(faceWidth) * tuning.foldLowBandFraction)
        let surroundRadius = max(tuning.skinBlurMinimumRadius, Double(faceWidth) * tuning.foldSurroundFraction)
        let lifted = try SkinKernels.shared.foldLift(
            image: image, low: FrequencySeparation.blurred(image, radius: lowRadius),
            surround: FrequencySeparation.blurred(image, radius: surroundRadius), amount: amount * tuning.foldLiftMax,
            extent: region.bounds)
        return MaskBuilder.blend(lifted, over: image, mask: region.image).cropped(to: extent)
    }
}
```

`SkinStage.swift`의 `apply` 전체를 다음으로 바꾸고 `clamped`·`refine`·`folds`를 더한다(`healSpots` 이하는 그대로):

```swift
    func apply(_ image: CIImage, in context: RenderContext) throws -> CIImage {
        let skin = Self.clamped(context.recipe.portrait.skin)
        guard skin.hasEffect, !context.targetFaces.isEmpty else { return image }
        let extent = context.extent
        var result = image
        if skin.autoBlemish {
            for heal in Self.healSpots(in: context) {
                result = LocalEditStage.applySpot(heal, to: result, context: context)
            }
        }
        guard skin.smoothing > 0 || skin.hasRefinement else { return result.cropped(to: extent) }
        for face in context.targetFaces {
            result = try refine(result, face: face, skin: skin, context: context)
        }
        return result.cropped(to: extent)
    }

    /// 피부 보정 0…1, 정밀 값은 키별 범위로 자른다. 프리셋·일괄 값은 편집 규칙을 거치지 않는다. 유한하지 않은 값은 RenderPipeline이 먼저 거절한다.
    static func clamped(_ skin: SkinAdjustments) -> SkinAdjustments {
        var copy = skin
        copy.smoothing = AdjustmentRange.clamped(skin.smoothing, to: AdjustmentRange.unit)
        for key in SkinRefinementKey.allCases {
            copy[key] = AdjustmentRange.clamped(skin[key], to: AdjustmentRange.skinRefinement(key))
        }
        return copy
    }

    /// 얼굴 하나: 주름 밝히기 4종 → 피부 마스크 안 대역 합성. 마스크 계산 영역이 비면(얼굴이 사진 밖) 건너뛴다.
    private func refine(_ image: CIImage, face: FaceGeometry, skin: SkinAdjustments, context: RenderContext) throws
        -> CIImage
    {
        let extent = context.extent
        let tuning = context.tuning
        // 이미지 밖까지 계산하면 가장자리에 알파 0·RGB가 있는 픽셀이 남는다.
        let bounds = FaceRegions.maskBounds(face: face, extent: extent, tuning: tuning).intersection(image.extent)
        guard !bounds.isEmpty else { return image }
        let faceWidth = FaceRegions.faceWidth(face, extent: extent)
        var result = image
        for fold in Self.folds(for: face, skin: skin, context: context) {
            result = try SkinRefinement.liftFold(
                result, region: fold.region, faceWidth: faceWidth, amount: fold.amount, tuning: tuning, extent: extent)
        }
        guard skin.smoothing > 0 else { return result }
        let mask = try FaceRegions.skinMask(
            face: face, image: result, extent: extent, tuning: tuning, strength: tuning.skinMaskMaxStrength,
            cache: context.regionMasks)
        let smooth = try FrequencySeparation.smoothed(
            result, bounds: bounds, faceWidth: faceWidth, smoothing: skin.smoothing, tuning: tuning)
        return MaskBuilder.blend(smooth, over: result, mask: mask).cropped(to: extent)
    }

    /// 값이 0이 아니고 마스크를 만들 수 있는 주름 띠. 순서는 다크서클 → 팔자 → 마리오네트 → 미간. 특징점이 없는 띠는 빠진다.
    static func folds(for face: FaceGeometry, skin: SkinAdjustments, context: RenderContext)
        -> [(amount: Double, region: FaceRegions.RegionMask)]
    {
        let extent = context.extent
        let tuning = context.tuning
        let cache = context.regionMasks
        let candidates: [(Double, () -> FaceRegions.RegionMask?)] = [
            (skin.darkCircles, { FaceRegions.darkCircleMask(face: face, extent: extent, tuning: tuning, cache: cache) }),
            (skin.nasolabial, { FaceRegions.nasolabialMask(face: face, extent: extent, tuning: tuning, cache: cache) }),
            (skin.marionette, { FaceRegions.marionetteMask(face: face, extent: extent, tuning: tuning, cache: cache) }),
            (skin.glabella, { FaceRegions.glabellaMask(face: face, extent: extent, tuning: tuning, cache: cache) }),
        ]
        return candidates.compactMap { amount, make in
            guard amount > 0, let region = make() else { return nil }
            return (amount, region)
        }
    }
```

- [ ] **Step 4: 통과 확인**

Run: `cd apple && swift test` → Rendering `Executed 235 tests`, 0 failures(기존 피부 테스트 9개 포함). lint 출력 없음. 빌드 경고는 `SkinKernels.swift`의 `CIColorKernel(source:)` 지원 중단이 2 → 3곳으로 늘어난 것뿐이어야 한다.

- [ ] **Step 5: 커밋**

```bash
git add apple/Sources/MellowRendering/API/RenderTuning.swift apple/Sources/MellowRendering/Domain/SkinKernels.swift apple/Sources/MellowRendering/Domain/SkinRefinement.swift apple/Sources/MellowRendering/Domain/SkinStage.swift apple/Tests/MellowRenderingTests/SkinStageTests.swift
git commit -m "feat(rendering): 다크서클·팔자·마리오네트·미간 주름 밝히기

주름 띠 안에서 둘레 피부 평균이 국소 저주파보다 밝은 만큼만 더해 어두운 주름을
올리고 모공 대역은 그대로 둔다. skin 단계가 대상 얼굴마다 띠 4종을 먼저 처리한다.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 5: 얼룩 고르기·번들거림 — toneMix 커널, 마스크 가중 평균, refined

**Files:**
- Modify: `apple/Sources/MellowRendering/API/RenderTuning.swift` (상수 5개)
- Modify: `apple/Sources/MellowRendering/Domain/SkinKernels.swift` (`toneMix`)
- Modify: `apple/Sources/MellowRendering/Domain/FrequencySeparation.swift` (`refined`, `maskedMean`)
- Modify: `apple/Sources/MellowRendering/Domain/FaceRegions.swift` (`cheekAverages`, `skinMask`가 이를 씀)
- Modify: `apple/Sources/MellowRendering/Domain/MaskBuilder.swift` (`scaled`)
- Modify: `apple/Sources/MellowRendering/Domain/SkinStage.swift` (`refine`의 합성 부분, `cheekReference`)
- Test: `apple/Tests/MellowRenderingTests/SkinStageTests.swift`

**Interfaces:**
- Consumes: Task 4의 구조, `FaceRegions.cheekRects`, `SkinKernels.bandMix`(유지).
- Produces: `SkinKernels.toneMix(...)`, `FrequencySeparation.refined(...)`·`maskedMean(_:mask:radius:)`, `FaceRegions.cheekAverages(of:face:extent:)`, `MaskBuilder.scaled(_:by:)`, `SkinStage.cheekReference(of:face:extent:) -> CIImage?`.

설계 근거: 스펙 1.6 대역 합성. `low = mix(midBlur, wide, max(even, shine × w))`이고 `wide`는 세기 1 피부 마스크로 가중한 넓은 평균이라 마스크 경계에서 머리카락·배경 색이 섞이지 않는다. 번들거림 가중치 `w`는 선형 휘도가 볼 기준보다 `shineLumaOffset` 이상 밝을 때 시작한다. 얼룩 고르기·번들거림이 모두 0이면 기존 `bandMix` 경로를 그대로 타 피부 보정만 쓰는 사진의 바이트가 바뀌지 않는다.

- [ ] **Step 1: 실패하는 테스트 작성**

`SkinStageTests.swift`에 추가(`testMissingLandmarksSkipOnlyThatFold` 뒤):

```swift
    /// 번들거림 테스트의 반사광 색. 피부색 가중치(σ 0.04) 안에 들면서 선형 휘도가 피부(0.44)보다 0.28 밝다.
    private static let glossColor = CIColor(red: 0.98, green: 0.84, blue: 0.74)
    /// 번들거림을 눌렀을 때 기대하는 최소 빨강 감소(바이트).
    private static let mattifyMinimum = 15

    func testToneEveningFlattensBlotchesAndKeepsPores() throws {
        let synthetic = SyntheticFace.make()
        let output = try render(synthetic, skin: SkinAdjustments(toneEvening: 1))
        let radii = FrequencySeparation.radii(
            faceWidth: FaceRegions.faceWidth(synthetic.face, extent: synthetic.image.extent), tuning: RenderTuning())
        let patch = SyntheticFace.skinPatch
        let before = try Support.bandVariances(synthetic.image, in: patch, fineRadius: radii.fine, midRadius: radii.mid)
        let after = try Support.bandVariances(output, in: patch, fineRadius: radii.fine, midRadius: radii.mid)
        XCTAssertEqual(after.fine / before.fine, 1, accuracy: 0.1, "모공 대역은 ±10% 안")
        XCTAssertEqual(after.mid / before.mid, 1, accuracy: 0.25, "중간 대역은 피부 보정 0이라 거의 그대로")
        let lowBefore = Support.variance(
            try Support.luma(FrequencySeparation.blurred(synthetic.image, radius: radii.mid).cropped(to: patch)))
        let lowAfter = Support.variance(
            try Support.luma(FrequencySeparation.blurred(output, radius: radii.mid).cropped(to: patch)))
        XCTAssertLessThan(lowAfter, lowBefore * 0.5, "저주파 얼룩이 준다")
        let beforeGrid = try Support.grid(synthetic.image)
        let afterGrid = try Support.grid(output)
        for point in [SyntheticFace.leftEye, SyntheticFace.mouth, SyntheticFace.backgroundInsideContour, SyntheticFace.outside]
        {
            XCTAssertEqual(afterGrid.rgba(point), beforeGrid.rgba(point), "피부 마스크 밖 \(point)")
        }
    }

    func testShineMattifiesOnlyBrightSkinSpots() throws {
        let base = SyntheticFace.make()
        let gloss = Support.hardEllipse(
            center: SyntheticFace.forehead, radii: CGSize(width: 12, height: 12), extent: SyntheticFace.extent)
        let image = CIImage(color: Self.glossColor).applyingFilter(
            "CIBlendWithMask", parameters: [kCIInputBackgroundImageKey: base.image, kCIInputMaskImageKey: gloss]
        ).cropped(to: SyntheticFace.extent)
        let synthetic = SyntheticFace(image: image, face: base.face)
        let before = try Support.grid(image)
        let after = try Support.grid(render(synthetic, skin: SkinAdjustments(shine: 1)))
        XCTAssertLessThanOrEqual(
            Int(after.red(SyntheticFace.forehead)), Int(before.red(SyntheticFace.forehead)) - Self.mattifyMinimum,
            "반사광이 눌린다")
        for point in [SyntheticFace.cheek, CGPoint(x: 180, y: 220)] {
            let expected = before.rgba(point)
            let actual = after.rgba(point)
            for channel in 0..<3 {
                XCTAssertEqual(Int(actual[channel]), Int(expected[channel]), accuracy: 1, "보통 피부 \(point)는 거의 그대로")
            }
        }
        for point in [SyntheticFace.leftEye, SyntheticFace.mouth, SyntheticFace.outside] {
            XCTAssertEqual(after.rgba(point), before.rgba(point), "피부 마스크 밖 \(point)")
        }
    }

    func testSmoothingOnlyUsesTheLegacyBandMixPath() throws {
        let synthetic = SyntheticFace.make()
        let extent = synthetic.image.extent
        let tuning = RenderTuning()
        let faceWidth = FaceRegions.faceWidth(synthetic.face, extent: extent)
        let bounds = FaceRegions.maskBounds(face: synthetic.face, extent: extent, tuning: tuning)
        let mask = try FaceRegions.skinMask(face: synthetic.face, image: synthetic.image, extent: extent, tuning: tuning)
        let reference = try XCTUnwrap(SkinStage.cheekReference(of: synthetic.image, face: synthetic.face, extent: extent))
        let legacy = try FrequencySeparation.smoothed(
            synthetic.image, bounds: bounds, faceWidth: faceWidth, smoothing: 0.7, tuning: tuning)
        let refined = try FrequencySeparation.refined(
            synthetic.image, bounds: bounds, faceWidth: faceWidth, mask: mask, reference: reference, smoothing: 0.7,
            toneEvening: 0, shine: 0, tuning: tuning)
        XCTAssertTrue(try Support.bytes(refined) == Support.bytes(legacy), "얼룩·번들거림 0이면 기존 경로와 같은 바이트")
        let combined = try render(synthetic, skin: SkinAdjustments(smoothing: 0.7, toneEvening: 0.5))
        XCTAssertFalse(try Support.bytes(combined) == Support.bytes(render(synthetic, skin: SkinAdjustments(smoothing: 0.7))))
    }
```

- [ ] **Step 2: 실패 확인**

Run: `cd apple && swift test --filter SkinStageTests` → 컴파일 실패(`FrequencySeparation`에 `refined` 없음).

- [ ] **Step 3: 구현**

`RenderTuning.swift`의 `foldLiftMax` 아래에 추가:

```swift
    /// 얼룩 고르기·번들거림이 당기는 넓은 피부 평균의 반지름. 얼굴 폭 비율. 볼 그림자 같은 큰 명암은 남는다.
    public var toneBandFraction: Double = 0.12
    /// 얼룩 고르기 1에서 저주파를 넓은 평균 쪽으로 당기는 비율.
    public var toneEveningMax: Double = 0.8
    /// 선형 휘도가 볼 기준보다 이만큼 밝으면 번들거림으로 보기 시작한다. 피부 질감 잡음(±10%)은 걸리지 않는다.
    public var shineLumaOffset: Double = 0.12
    /// 시작점에서 이만큼 더 밝으면 번들거림 가중치 1.
    public var shineLumaRamp: Double = 0.1
    /// 번들거림 1에서 반사광의 저주파를 넓은 평균 쪽으로 당기는 비율.
    public var shineReductionMax: Double = 0.85
```

`MaskBuilder.swift`의 `blend` 위에 추가:

```swift
    /// 회색 마스크에 factor를 곱한다. 1이면 그대로다.
    static func scaled(_ mask: CIImage, by factor: Double) -> CIImage {
        guard factor != 1 else { return mask }
        return mask.applyingFilter(
            "CIColorMatrix",
            parameters: [
                "inputRVector": CIVector(x: factor, y: 0, z: 0, w: 0),
                "inputGVector": CIVector(x: 0, y: factor, z: 0, w: 0),
                "inputBVector": CIVector(x: 0, y: 0, z: factor, w: 0),
            ])
    }
```

`FaceRegions.swift`: `skinMask`의 볼 평균 계산을 새 함수로 뺀다.

```swift
    /// 볼 두 곳의 평균색(무한 확장 이미지). 넘긴 이미지의 색공간 그대로다(감마 이미지면 감마 평균, 선형이면 선형 평균).
    /// 볼 상자가 하나뿐이면 둘 다 그 상자이고, 하나도 없으면(얼굴이 사진 밖에 걸침) nil.
    static func cheekAverages(of image: CIImage, face: FaceGeometry, extent: CGRect)
        -> (left: CIImage, right: CIImage)?
    {
        let cheeks = cheekRects(face: face, extent: extent)
        guard let left = cheeks.first, let right = cheeks.last else { return nil }
        return (average(image, in: left), average(image, in: right))
    }
```

`skinMask` 안의

```swift
        let cheeks = cheekRects(face: face, extent: extent)
        if let left = cheeks.first, let right = cheeks.last {
            let encoded = image.applyingFilter("CILinearToSRGBToneCurve")
            let weight = try SkinKernels.shared.chromaWeight(
                of: encoded, left: average(encoded, in: left), right: average(encoded, in: right),
                sigma: tuning.skinChromaSigma, extent: extent)
```

를 다음으로 바꾼다:

```swift
        let encoded = image.applyingFilter("CILinearToSRGBToneCurve")
        if let cheeks = cheekAverages(of: encoded, face: face, extent: extent) {
            let weight = try SkinKernels.shared.chromaWeight(
                of: encoded, left: cheeks.left, right: cheeks.right, sigma: tuning.skinChromaSigma, extent: extent)
```

`SkinKernels.swift`: 프로퍼티 `private let tone: CIColorKernel?`와 커널:

```swift
        tone = CIColorKernel(
            source: """
                kernel vec4 toneMix(__sample image, __sample fineBlur, __sample midBlur, __sample wideNumerator,
                                    __sample wideDenominator, __sample reference, float keep, float even,
                                    float shine, float shineOffset, float shineRamp) {
                    vec3 luma = vec3(0.2126, 0.7152, 0.0722);
                    vec3 wide = wideNumerator.rgb / max(wideDenominator.r, 0.001);
                    float gloss = clamp((dot(image.rgb, luma) - dot(reference.rgb, luma) - shineOffset) / shineRamp,
                                        0.0, 1.0);
                    float pull = max(even, shine * gloss);
                    vec3 low = mix(midBlur.rgb, wide, pull);
                    vec3 mid = fineBlur.rgb - midBlur.rgb;
                    vec3 fine = image.rgb - fineBlur.rgb;
                    return vec4(low + mid * keep + fine, image.a);
                }
                """)
```

(`luma`는 BT.709 선형 휘도 계수, 분모 하한 0.001은 마스크 밖 0 나눗셈 방지다. 주석으로 적는다.)

```swift
    /// low = mix(midBlur, 마스크 가중 넓은 평균, max(even, shine × 번들거림 가중치)). 나머지는 bandMix와 같다.
    /// 번들거림 가중치는 선형 휘도(BT.709)가 reference보다 shineOffset 이상 밝은 곳에서 shineRamp에 걸쳐 0 → 1.
    func toneMix(
        image: CIImage, fineBlur: CIImage, midBlur: CIImage, wideNumerator: CIImage, wideDenominator: CIImage,
        reference: CIImage, keep: Double, even: Double, shine: Double, shineOffset: Double, shineRamp: Double,
        extent: CGRect
    ) throws -> CIImage {
        guard let tone, shineRamp > 0 else { throw MellowError.renderFailed }
        let arguments: [Any] = [
            image, fineBlur, midBlur, wideNumerator, wideDenominator, reference, keep, even, shine, shineOffset,
            shineRamp,
        ]
        guard let mixed = tone.apply(extent: extent, arguments: arguments) else { throw MellowError.renderFailed }
        return mixed
    }
```

`FrequencySeparation.swift`의 `smoothed` 아래에 추가:

```swift
    /// 얼룩 고르기·번들거림이 들어간 대역 합성. mask는 세기 1 피부 마스크(넓은 평균의 가중치), reference는 볼 평균(선형, 무한 확장).
    /// toneEvening·shine이 모두 0이면 smoothed와 같은 경로·같은 바이트다.
    static func refined(
        _ image: CIImage, bounds: CGRect, faceWidth: CGFloat, mask: CIImage, reference: CIImage, smoothing: Double,
        toneEvening: Double, shine: Double, tuning: RenderTuning
    ) throws -> CIImage {
        let even = min(1, max(0, toneEvening)) * tuning.toneEveningMax
        let gloss = min(1, max(0, shine)) * tuning.shineReductionMax
        guard even > 0 || gloss > 0 else {
            return try smoothed(image, bounds: bounds, faceWidth: faceWidth, smoothing: smoothing, tuning: tuning)
        }
        guard !bounds.isEmpty else { return image }
        let bandRadii = Self.radii(faceWidth: faceWidth, tuning: tuning)
        let wideRadius = max(bandRadii.mid, Double(faceWidth) * tuning.toneBandFraction)
        let wide = maskedMean(image, mask: mask, radius: wideRadius)
        return try SkinKernels.shared.toneMix(
            image: image, fineBlur: blurred(image, radius: bandRadii.fine), midBlur: blurred(image, radius: bandRadii.mid),
            wideNumerator: wide.numerator, wideDenominator: wide.denominator, reference: reference,
            keep: 1 - min(1, max(0, smoothing)) * tuning.midReductionMax, even: even, shine: gloss,
            shineOffset: tuning.shineLumaOffset, shineRamp: tuning.shineLumaRamp, extent: bounds)
    }

    /// 마스크 가중 평균의 분자 blur(image × mask)와 분모 blur(mask). 나눗셈은 커널이 한다. 경계 밖 색이 평균에 섞이지 않는다.
    static func maskedMean(_ image: CIImage, mask: CIImage, radius: Double) -> (numerator: CIImage, denominator: CIImage) {
        let weighted = image.applyingFilter("CIMultiplyCompositing", parameters: [kCIInputBackgroundImageKey: mask])
        return (blurred(weighted, radius: radius), blurred(mask, radius: radius))
    }
```

`SkinStage.swift`: `refine`의 `guard skin.smoothing > 0 else { return result }` 이하를 다음으로 바꾼다.

```swift
        guard skin.smoothing > 0 || skin.toneEvening > 0 || skin.shine > 0 else { return result }
        let unitMask = try FaceRegions.skinMask(
            face: face, image: result, extent: extent, tuning: tuning, strength: 1, cache: context.regionMasks)
        let blendMask = MaskBuilder.scaled(unitMask, by: tuning.skinMaskMaxStrength)
        // 볼 상자가 없으면 번들거림의 기준이 없어 번들거림만 건너뛴다.
        let reference = Self.cheekReference(of: result, face: face, extent: extent)
        let smooth = try FrequencySeparation.refined(
            result, bounds: bounds, faceWidth: faceWidth, mask: unitMask, reference: reference ?? Self.noReference,
            smoothing: skin.smoothing, toneEvening: skin.toneEvening, shine: reference == nil ? 0 : skin.shine,
            tuning: tuning)
        return MaskBuilder.blend(smooth, over: result, mask: blendMask).cropped(to: extent)
```

`SkinStage`에 추가:

```swift
    /// 기준이 없을 때 커널에 넘기는 자리 채움(쓰이지 않는다).
    private static let noReference = CIImage(color: .black)

    /// 볼 두 곳 평균을 반씩 섞은 기준색(무한 확장). 넘긴 이미지의 색공간을 따른다. 볼 상자가 없으면 nil.
    static func cheekReference(of image: CIImage, face: FaceGeometry, extent: CGRect) -> CIImage? {
        guard let cheeks = FaceRegions.cheekAverages(of: image, face: face, extent: extent) else { return nil }
        return cheeks.left.applyingFilter(
            "CIMix", parameters: [kCIInputBackgroundImageKey: cheeks.right, "inputAmount": Self.referenceMix])
    }

    /// 두 볼을 같은 비중으로 섞는다.
    private static let referenceMix = 0.5
```

`refine`의 doc 주석을 "주름 밝히기 3종 → 피부 마스크 안 대역 합성(피부 보정·얼룩 고르기·번들거림)"으로 고친다.

- [ ] **Step 4: 통과 확인**

Run: `cd apple && swift test` → Rendering `Executed 238 tests`, 0 failures. `testSmoothingCutsMidBandAndKeepsPores`·`testSkinRenderReusesCachedMaskAcrossRenders`가 그대로 통과해야 한다(마스크는 strength 1로 한 번 만들고 곱하므로 캐시 항목 수 1 유지). lint 출력 없음.

- [ ] **Step 5: 커밋**

```bash
git add apple/Sources/MellowRendering/API/RenderTuning.swift apple/Sources/MellowRendering/Domain/SkinKernels.swift apple/Sources/MellowRendering/Domain/FrequencySeparation.swift apple/Sources/MellowRendering/Domain/FaceRegions.swift apple/Sources/MellowRendering/Domain/MaskBuilder.swift apple/Sources/MellowRendering/Domain/SkinStage.swift apple/Tests/MellowRenderingTests/SkinStageTests.swift
git commit -m "feat(rendering): 피부 얼룩 고르기와 번들거림

대역 합성의 저주파를 피부 마스크 가중 넓은 평균 쪽으로 당긴다. 번들거림은 볼 기준보다
밝은 반사 영역에만 같은 식을 건다. 둘 다 0이면 기존 경로라 피부 보정 결과는 그대로다.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 6: 붉은기 — redness 커널, 맑게 ↔ 혈색

**Files:**
- Modify: `apple/Sources/MellowRendering/API/RenderTuning.swift` (상수 2개)
- Modify: `apple/Sources/MellowRendering/Domain/SkinKernels.swift` (`redness`)
- Modify: `apple/Sources/MellowRendering/Domain/SkinRefinement.swift` (`adjustRedness`)
- Modify: `apple/Sources/MellowRendering/Domain/SkinStage.swift` (`refine` 끝)
- Test: `apple/Tests/MellowRenderingTests/SkinStageTests.swift`

**Interfaces:**
- Consumes: Task 5의 `unitMask`·`blendMask`·`cheekReference`.
- Produces: `SkinKernels.redness(encoded:reference:clear:flush:extent:)`, `SkinRefinement.adjustRedness(_:mask:bounds:reference:value:tuning:extent:)`.

설계 근거: 스펙 1.6 붉은기. 감마 BT.601 YCbCr에서 Cr만 옮긴다. −는 볼 기준 Cr을 넘는 만큼만 줄여 반점을 고르고 보통 피부는 두지 않으며, +는 균일하게 더한다. 색 계산은 `FeatureKernels.shifted`처럼 감마로 바꿔 하고 선형으로 되돌린다.

- [ ] **Step 1: 실패하는 테스트 작성**

`SkinStageTests.swift`에 추가:

```swift
    /// 붉은기 테스트의 반점 색. 피부보다 감마 Cr이 0.037 높고 피부색 가중치 안이다.
    private static let blotchColor = CIColor(red: 0.84, green: 0.58, blue: 0.52)
    /// 오른볼 위 반점 자리. 잡티·특징·분산 측정 패치에서 떨어져 있다.
    private static let blotchPoint = CGPoint(x: 320, y: 210)

    func testRednessClearsOnlyRedderThanCheeksAndFlushAddsEvenly() throws {
        let base = SyntheticFace.make()
        let blotch = Support.hardEllipse(
            center: Self.blotchPoint, radii: CGSize(width: 10, height: 10), extent: SyntheticFace.extent)
        let image = CIImage(color: Self.blotchColor).applyingFilter(
            "CIBlendWithMask", parameters: [kCIInputBackgroundImageKey: base.image, kCIInputMaskImageKey: blotch]
        ).cropped(to: SyntheticFace.extent)
        let synthetic = SyntheticFace(image: image, face: base.face)
        func gap(_ pixel: [UInt8]) -> Int { Int(pixel[0]) - Int(pixel[1]) }
        let before = try Support.grid(image)
        let clear = try Support.grid(render(synthetic, skin: SkinAdjustments(redness: -1)))
        XCTAssertLessThanOrEqual(gap(clear.rgba(Self.blotchPoint)), gap(before.rgba(Self.blotchPoint)) - 10, "반점의 붉은기가 준다")
        for channel in 0..<3 {
            XCTAssertEqual(
                Int(clear.rgba(SyntheticFace.cheek)[channel]), Int(before.rgba(SyntheticFace.cheek)[channel]), accuracy: 2,
                "기준보다 붉지 않은 피부는 거의 그대로")
        }
        let flush = try Support.grid(render(synthetic, skin: SkinAdjustments(redness: 1)))
        for point in [SyntheticFace.cheek, Self.blotchPoint, SyntheticFace.forehead] {
            XCTAssertGreaterThanOrEqual(gap(flush.rgba(point)), gap(before.rgba(point)) + 5, "혈색은 피부 전체에 고르게 \(point)")
        }
        for point in [SyntheticFace.leftEye, SyntheticFace.mouth, SyntheticFace.backgroundInsideContour, SyntheticFace.outside]
        {
            XCTAssertEqual(clear.rgba(point), before.rgba(point), "피부 마스크 밖 \(point)")
            XCTAssertEqual(flush.rgba(point), before.rgba(point), "피부 마스크 밖 \(point)")
        }
    }
```

- [ ] **Step 2: 실패 확인**

Run: `cd apple && swift test --filter SkinStageTests/testRednessClearsOnlyRedderThanCheeksAndFlushAddsEvenly` → 실행 실패("반점의 붉은기가 준다").

- [ ] **Step 3: 구현**

`RenderTuning.swift`의 `shineReductionMax` 아래:

```swift
    /// 붉은기 −1에서 볼 기준 Cr을 넘는 붉은 양을 줄이는 비율.
    public var rednessClearMax: Double = 0.7
    /// 붉은기 +1에서 감마 Cr에 고르게 더하는 값. 입술 생기(0.02)보다 조금 크다.
    public var rednessFlushMax: Double = 0.03
```

`SkinKernels.swift`: 프로퍼티 `private let blush: CIColorKernel?`와 커널(계수는 BT.601, 감마 값 기준 — 주석):

```swift
        blush = CIColorKernel(
            source: """
                kernel vec4 skinRedness(__sample pixel, __sample reference, float clear, float flush) {
                    vec3 yv = vec3(0.299, 0.587, 0.114);
                    vec3 cbv = vec3(-0.168736, -0.331264, 0.5);
                    vec3 crv = vec3(0.5, -0.418688, -0.081312);
                    float y = dot(pixel.rgb, yv);
                    float cb = dot(pixel.rgb, cbv);
                    float cr = dot(pixel.rgb, crv);
                    float excess = max(cr - dot(reference.rgb, crv), 0.0);
                    cr = cr - excess * clear + flush;
                    vec3 rgb = vec3(y + 1.402 * cr, y - 0.344136 * cb - 0.714136 * cr, y + 1.772 * cb);
                    return vec4(clamp(rgb, 0.0, 1.0), pixel.a);
                }
                """)
```

```swift
    /// encoded는 sRGB 감마 이미지, reference는 볼 기준 평균(감마, 무한 확장). 기준 Cr을 넘는 만큼 × clear를 빼고 flush를 더한다.
    func redness(encoded: CIImage, reference: CIImage, clear: Double, flush: Double, extent: CGRect) throws -> CIImage {
        guard let blush else { throw MellowError.renderFailed }
        let arguments: [Any] = [encoded, reference, clear, flush]
        guard let shifted = blush.apply(extent: extent, arguments: arguments) else { throw MellowError.renderFailed }
        return shifted
    }
```

`SkinRefinement.swift`에 추가:

```swift
    /// 붉은기. value < 0은 기준(reference, 감마)보다 붉은 만큼만 줄이고(맑게), value > 0은 Cr을 고르게 더한다(혈색).
    /// 감마로 바꿔 계산하고 선형으로 되돌린다. mask 밖은 입력 바이트 그대로다.
    static func adjustRedness(
        _ image: CIImage, mask: CIImage, bounds: CGRect, reference: CIImage, value: Double, tuning: RenderTuning,
        extent: CGRect
    ) throws -> CIImage {
        guard value != 0, !bounds.isEmpty else { return image }
        let encoded = image.applyingFilter("CILinearToSRGBToneCurve")
        let clear = value < 0 ? -value * tuning.rednessClearMax : 0
        let flush = value > 0 ? value * tuning.rednessFlushMax : 0
        let shifted = try SkinKernels.shared.redness(
            encoded: encoded, reference: reference, clear: clear, flush: flush, extent: bounds
        ).applyingFilter("CISRGBToneCurveToLinear")
        return MaskBuilder.blend(shifted, over: image, mask: mask).cropped(to: extent)
    }
```

`SkinStage.refine`: `guard skin.smoothing > 0 || skin.toneEvening > 0 || skin.shine > 0 else { return result }`를 `guard skin.smoothing > 0 || skin.toneEvening > 0 || skin.shine > 0 || skin.redness != 0 else { return result }`로 바꾸고, 대역 합성 블록을 `if skin.smoothing > 0 || skin.toneEvening > 0 || skin.shine > 0 { … result = MaskBuilder.blend(...) }`로 감싼 뒤 마지막에 붙인다:

```swift
        if skin.redness != 0,
            let encodedReference = Self.cheekReference(
                of: result.applyingFilter("CILinearToSRGBToneCurve"), face: face, extent: extent)
        {
            result = try SkinRefinement.adjustRedness(
                result, mask: blendMask, bounds: bounds, reference: encodedReference, value: skin.redness,
                tuning: tuning, extent: extent)
        }
        return result
```

doc 주석에 "→ 붉은기"를 더한다. 볼 상자가 없으면 붉은기는 건너뛴다(기준이 없음).

- [ ] **Step 4: 통과 확인**

Run: `cd apple && swift test` → Rendering `Executed 239 tests`, 0 failures. lint 출력 없음.

- [ ] **Step 5: 커밋**

```bash
git add apple/Sources/MellowRendering/API/RenderTuning.swift apple/Sources/MellowRendering/Domain/SkinKernels.swift apple/Sources/MellowRendering/Domain/SkinRefinement.swift apple/Sources/MellowRendering/Domain/SkinStage.swift apple/Tests/MellowRenderingTests/SkinStageTests.swift
git commit -m "feat(rendering): 붉은기 맑게·혈색

피부 마스크 안에서 볼 기준 Cr을 넘는 붉은 양만 줄이거나(맑게) Cr을 고르게 더한다(혈색).
감마 BT.601 YCbCr에서 Cr만 옮긴다.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 7: 통합 — 항등·클램프·특징점 없음·대상 얼굴·캐시

**Files:**
- Test: `apple/Tests/MellowRenderingTests/SkinStageTests.swift`

**Interfaces:** 새 타입 없음. 앞 Task의 동작을 묶어 확인한다. 테스트가 실패하면 소유 Task(4~6)의 코드를 고친다.

- [ ] **Step 1: 테스트 작성**

```swift
    func testZeroRefinementsAreIdentityAndOutOfRangeValuesRenderClamped() throws {
        let synthetic = SyntheticFace.make()
        let input = try Support.bytes(synthetic.image)
        XCTAssertTrue(try Support.bytes(render(synthetic, skin: SkinAdjustments())) == input)
        XCTAssertTrue(try Support.bytes(render(synthetic, skin: SkinAdjustments(shine: -1))) == input, "음수는 0")
        XCTAssertTrue(
            try Support.bytes(
                render(synthetic, skin: SkinAdjustments(darkCircles: 3, marionette: 2, toneEvening: 2, redness: -5)))
                == Support.bytes(
                    render(synthetic, skin: SkinAdjustments(darkCircles: 1, marionette: 1, toneEvening: 1, redness: -1))))
        XCTAssertEqual(
            SkinStage.clamped(SkinAdjustments(smoothing: 4, marionette: -2, redness: 2, glabella: -1)),
            SkinAdjustments(smoothing: 1, redness: 1))
    }

    func testBoxOnlyFaceSkipsFoldsButStillEvensTone() throws {
        let boxOnly = SyntheticFace.make(landmarks: false)
        let input = try Support.bytes(boxOnly.image)
        let folds = SkinAdjustments(darkCircles: 1, nasolabial: 1, marionette: 1, glabella: 1)
        XCTAssertTrue(try Support.bytes(render(boxOnly, skin: folds)) == input, "주름 띠는 특징점이 없으면 빠진다")
        let before = try Support.grid(boxOnly.image)
        let evened = try Support.grid(render(boxOnly, skin: SkinAdjustments(toneEvening: 1, redness: 1)))
        XCTAssertNotEqual(evened.rgba(SyntheticFace.cheek), before.rgba(SyntheticFace.cheek), "대체 타원 마스크로 동작")
        XCTAssertEqual(evened.rgba(SyntheticFace.outside), before.rgba(SyntheticFace.outside))
    }

    /// 반 크기 합성 얼굴 둘을 좌우에 놓는다. 비트맵으로 굳혀 마스크 밖 바이트를 그대로 비교한다.
    func testTargetFaceRefinesOnlyThatFace() throws {
        let synthetic = SyntheticFace.make()
        let side = CGFloat(SyntheticFace.size)
        let half = CGAffineTransform(scaleX: 0.5, y: 0.5)
        let left = synthetic.image.transformed(by: half.concatenating(CGAffineTransform(translationX: 0, y: side / 4)))
        let right = synthetic.image.transformed(
            by: half.concatenating(CGAffineTransform(translationX: side / 2, y: side / 4)))
        let composed = left.composited(over: right).composited(over: CIImage(color: .gray))
            .cropped(to: SyntheticFace.extent)
        let image = CIImage(cgImage: try Support.renderer.makeCGImage(composed))
        let faces = [
            synthetic.face.transformed(scale: 0.5, offset: NormalizedPoint(x: 0, y: 0.25)),
            synthetic.face.transformed(scale: 0.5, offset: NormalizedPoint(x: 0.5, y: 0.25)),
        ]
        var recipe = EditRecipe()
        recipe.portrait.skin = SkinAdjustments(
            darkCircles: 1, nasolabial: 1, marionette: 1, glabella: 1, toneEvening: 1, redness: 1, shine: 1)
        recipe.portrait.targetFace = 0
        let context = RenderContext(extent: image.extent, recipe: recipe, faces: faces, tuning: RenderTuning())
        let before = try Support.grid(image)
        let after = try Support.grid(SkinStage().apply(image, in: context))
        var leftChanged = 0
        var rightChanged = 0
        for y in 0..<SyntheticFace.size {
            for x in 0..<SyntheticFace.size {
                let point = CGPoint(x: x, y: y)
                guard after.rgba(point) != before.rgba(point) else { continue }
                if x < SyntheticFace.size / 2 {
                    leftChanged += 1
                } else {
                    rightChanged += 1
                }
            }
        }
        XCTAssertGreaterThan(leftChanged, 0, "고른 얼굴은 보정된다")
        XCTAssertEqual(rightChanged, 0, "다른 얼굴은 한 픽셀도 바뀌지 않는다")
    }

    func testRefinementsReuseTheSkinRasterAndAddNoCacheEntries() throws {
        let synthetic = SyntheticFace.make()
        var recipe = EditRecipe()
        recipe.portrait.skin = SkinAdjustments(
            smoothing: 0.5, darkCircles: 1, nasolabial: 1, marionette: 1, glabella: 1, toneEvening: 1, redness: -1,
            shine: 1)
        let analysis = PhotoAnalysis(faces: [synthetic.face])
        let context = RenderContext(
            extent: synthetic.image.extent, recipe: recipe, analysis: analysis, tuning: RenderTuning())
        let first = try Support.bytes(SkinStage().apply(synthetic.image, in: context))
        let second = try Support.bytes(SkinStage().apply(synthetic.image, in: context))
        XCTAssertEqual(analysis.regionMasks.count, 1, "주름 띠·대역 합성·붉은기 모두 피부 다각형 비트맵 하나를 쓴다")
        XCTAssertTrue(first == second, "같은 입력은 같은 바이트")
    }
```

- [ ] **Step 2: 통과 확인**

Run: `cd apple && swift test` → Rendering `Executed 244 tests`, 0 failures. 실패하면 소유 Task의 구현을 고치고 그 Task의 테스트도 함께 통과시킨다. lint 출력 없음. `./scripts/verify-modules.sh` 통과.

- [ ] **Step 3: 커밋**

```bash
git add apple/Tests/MellowRenderingTests/SkinStageTests.swift
git commit -m "test(rendering): 피부 정밀 항등·클램프·특징점 없음·대상 얼굴·캐시

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 8: 앱 — 뷰티 피부 탭 슬라이더 6개, 문구, 시나리오

**Files:**
- Modify: `apple/MellowPhoto/Application/UserMessage.swift`
- Modify: `apple/MellowPhoto/Features/Editor/BeautyPanel.swift`
- Test: `apple/MellowPhotoTests/AppModelTests.swift`, `apple/MellowPhotoTests/EditorScenarioTests.swift`

**Interfaces:**
- Consumes: `EditChange.skinRefinement`, `EditingPolicy.skinRefinementRange`, `AdjustmentSlider(snapsToZero:)`.
- Produces: `UserMessage.skinRefinementTitle(_:)`, `UserMessage.skinRefinementHint`. 새 파일 없음(`xcodegen` 불필요).

설계 근거: 스펙 1.9. 피부 탭 안에 두어 얼굴 선택·특징점 없음 안내를 그대로 쓴다. 붉은기만 가운데 0 스냅.

- [ ] **Step 1: 실패하는 테스트 작성**

`AppModelTests.swift`의 `testBeautyToolEditsSkinOneUndoStepEach` 뒤에 추가:

```swift
    func testSkinTabEditsEveryRefinementKeyOneUndoStepEach() async throws {
        let staged = try TestSupport.solidPNG(in: root)
        let face = TestSupport.landmarkedFace(in: NormalizedRect(x: 0.2, y: 0.2, width: 0.6, height: 0.6))
        let model = TestSupport.makeModel(
            root: root, analyzer: StubFaceAnalyzer(result: .success([face])),
            importer: FakeImporter(staged: [.success(StagedPhoto(url: staged, displayName: nil))]))
        try await importOne(model, staged)
        model.selectTool(.beauty)
        model.beautyTab = .skin
        for (offset, key) in SkinRefinementKey.allCases.enumerated() {
            model.beginSliderEdit()
            model.edit(.skinRefinement(key, 0.3))
            model.edit(.skinRefinement(key, key == .redness ? -0.5 : 0.6))
            model.endSliderEdit()
            XCTAssertEqual(model.session.selected?.document.undoStack.count, offset + 1, "\(key) 드래그 한 번이 한 단계")
        }
        XCTAssertEqual(
            model.currentRecipe.portrait.skin,
            SkinAdjustments(
                darkCircles: 0.6, nasolabial: 0.6, marionette: 0.6, glabella: 0.6, toneEvening: 0.6, redness: -0.5,
                shine: 0.6))
        try await waitUntil { !model.isRendering }
        XCTAssertNil(model.presentedError)
        model.undo()
        XCTAssertEqual(model.currentRecipe.portrait.skin.shine, 0)
        XCTAssertEqual(
            SkinRefinementKey.allCases.map(UserMessage.skinRefinementTitle),
            ["다크서클", "팔자주름", "마리오네트 주름", "미간 주름", "피부 얼룩 고르기", "붉은기", "번들거림"])
    }
```

`EditorScenarioTests.swift`의 `testBeautySkinFaceFeaturesBackgroundBodyThenMakeupThenExportSucceeds`에서 `let skinned = previewBytes(model)` 뒤에 추가하고, 그다음 얼굴 단계의 `self.previewBytes(model) != skinned`를 `!= refined`로 바꾼다:

```swift
        for (key, value) in [(SkinRefinementKey.darkCircles, 0.6), (.toneEvening, 0.5)] {
            model.beginSliderEdit()
            model.edit(.skinRefinement(key, value))
            model.endSliderEdit()
        }
        // 피부 정밀만 바꿔도 미리보기가 바뀌어야 한다.
        try await waitUntil { !model.isRendering && self.previewBytes(model) != skinned }
        let refined = previewBytes(model)
```

마지막 레시피 검증의 `XCTAssertEqual(recipe.portrait.skin, SkinAdjustments(smoothing: 0.5, autoBlemish: true))`를 `SkinAdjustments(smoothing: 0.5, autoBlemish: true, darkCircles: 0.6, toneEvening: 0.5)`로 바꾼다.

- [ ] **Step 2: 실패 확인**

Run: Mac 앱 테스트 명령 → 컴파일 실패(`UserMessage`에 `skinRefinementTitle` 없음).

- [ ] **Step 3: 구현**

`UserMessage.swift`: `skinHint` 아래에 추가하고 `skinHint` 문구는 그대로 둔다.

```swift
    static let skinRefinementHint =
        "다크서클·팔자주름·마리오네트 주름·미간 주름은 특징점으로 어림한 띠 안에서 어두운 만큼만 밝힙니다. 붉은기는 왼쪽이 맑게, 오른쪽이 혈색이에요."
```

`featureTitle(_:)` 아래에 추가:

```swift
    /// 뷰티 › 피부 탭의 정밀 슬라이더 이름. 화면 순서는 SkinRefinementKey.allCases.
    static func skinRefinementTitle(_ key: SkinRefinementKey) -> String {
        switch key {
        case .darkCircles: return "다크서클"
        case .nasolabial: return "팔자주름"
        case .marionette: return "마리오네트 주름"
        case .glabella: return "미간 주름"
        case .toneEvening: return "피부 얼룩 고르기"
        case .redness: return "붉은기"
        case .shine: return "번들거림"
        }
    }
```

`BeautyPanel.swift`의 `skinControls`를 다음으로 바꾼다:

```swift
    /// 피부 보정·자동 잡티 아래에 정밀 7개. 붉은기만 가운데 0인 양방향이고 0 근처에서 0에 붙는다.
    @ViewBuilder
    private func skinControls(_ skin: SkinAdjustments) -> some View {
        AdjustmentSlider(title: UserMessage.skinSmoothing, value: skin.smoothing, range: EditingPolicy.unitRange) {
            .skinSmoothing($0)
        }
        Toggle(
            UserMessage.autoBlemish,
            isOn: Binding(get: { skin.autoBlemish }, set: { model.edit(.autoBlemish($0)) })
        )
        .font(.caption)
        Text(UserMessage.skinHint).font(.caption).foregroundStyle(.secondary)
        Divider().opacity(0.4)
        ForEach(SkinRefinementKey.allCases, id: \.self) { key in
            let range = EditingPolicy.skinRefinementRange(key)
            AdjustmentSlider(
                title: UserMessage.skinRefinementTitle(key), value: skin[key], range: range,
                snapsToZero: range.lowerBound < 0
            ) { .skinRefinement(key, $0) }
        }
        Text(UserMessage.skinRefinementHint).font(.caption).foregroundStyle(.secondary)
    }
```

- [ ] **Step 4: 통과 확인**

Run: `cd apple && swift test` → 패키지 354(Shared 45 · Rendering 244 · Library 30 · Export 4 · Editing 31), 0 failures. Mac 앱 테스트 → `Executed 72 tests, with 0 failures`, `TEST SUCCEEDED`. lint 출력 없음. `./scripts/verify-modules.sh` 통과. `cd apple && xcodegen generate --quiet && git diff --exit-code --stat MellowPhoto.xcodeproj` → 출력 없음(파일 추가 없음).

- [ ] **Step 5: 커밋**

```bash
git add apple/MellowPhoto/Application/UserMessage.swift apple/MellowPhoto/Features/Editor/BeautyPanel.swift apple/MellowPhotoTests/AppModelTests.swift apple/MellowPhotoTests/EditorScenarioTests.swift
git commit -m "feat(app): 뷰티 피부 탭에 피부 정밀 슬라이더 7개

다크서클·팔자주름·마리오네트 주름·미간 주름·피부 얼룩 고르기·붉은기(가운데 0)·번들거림.
시나리오 테스트에 피부 정밀 단계를 더한다.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

## 자체 검토 결과

- **스펙 대조:** §1.1 → `SkinRefinementKey`(Shared, Task 1), `FaceRegions+Folds`(Task 3), `SkinKernels` 커널 3개(Task 4·5·6), `SkinRefinement`(Task 4·6), `FrequencySeparation.refined`·`maskedMean`(Task 5), 새 import 없음·`verify-modules.sh` 불변. §1.2 → `portrait.skin` 키 7개·범위·`hasEffect`·`numericValues`·스키마·README(Task 1), `EditChange.skinRefinement`·`applyAuto`(Task 2). §1.3 → 단계 순서 불변(이 계획은 순서 배열을 건드리지 않음). §1.5 → 네 마스크(마리오네트는 고정 방향)·`Oval.tilt`·`eyeMidline`(Task 3). §1.6 → 주름 밝히기(Task 4), 대역 합성 식·마스크 가중 평균·기존 경로 유지(Task 5), 붉은기(Task 6), 상수 10개(Task 4·5·6). §1.9 → 피부 탭 슬라이더·스냅·문구(Task 8). §1.10 → 프리셋이 정밀 값을 나름(Task 1 테스트), `applyAuto`(Task 2). §2 → 항등·클램프(Task 7), 마스크 밖 불변(Task 4·5·6), 특징점 없음(Task 3·4·7), 대상 얼굴(Task 7), 회귀·캐시(Task 5·7), 앱·시나리오(Task 8). §4 → 이 계획의 Task 목록이 표와 같다.
- **타입 일관성:** `SkinAdjustments.subscript`·`refinementValues`·`hasRefinement`, `AdjustmentRange.skinRefinement`, `EditingPolicy.skinRefinementRange`, `FaceRegions.darkCircleMask`·`nasolabialMask`·`marionetteMask`·`glabellaMask`·`cheekAverages`·`eyeMidline`, `Oval.tilt`, `MaskBuilder.scaled`, `SkinKernels.foldLift`·`toneMix`·`redness`, `FrequencySeparation.refined`·`maskedMean`, `SkinRefinement.liftFold`·`adjustRedness`, `SkinStage.clamped`·`folds`·`cheekReference`, `SyntheticFace` 표본 점 9개, `UserMessage.skinRefinementTitle`·`skinRefinementHint`를 정의한 Task와 쓰는 Task에서 같게 썼다. 테스트 수: 패키지 331 → 333 → 335 → 341 → 345 → 348 → 349 → 354 → 354, 앱 Mac 71 → 72.
- **Review Focus 매핑:** 1→Task 1·5, 2→Task 2, 3→Task 7, 4→Task 3·4, 5→Task 7, 6→Task 7. 모두 테스트 코드가 있다.
- **플레이스홀더 점검:** "TBD/TODO/나중에" 없음. 표본 점 좌표는 계산 근거를 Task 3에 적었고 실패 시 조치는 Global Constraints에 있다.
