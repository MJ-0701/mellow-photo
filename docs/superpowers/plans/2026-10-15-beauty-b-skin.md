# 인물 보정 B 피부 구현 계획

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 기존 "피부 정돈"을 모공 질감을 남기는 주파수 분리 피부 보정과 자동 잡티 제거로 바꾸고, B~F가 쓸 레시피 골격 전체를 한 번에 넣는다.

**Architecture:** MellowShared에 B~F 레시피 값 타입 전부를 기본값과 함께 넣고 `portrait.skinSmoothing`·`faceSlim`을 새 키로 이행한다(schemaVersion 2 유지). MellowRendering에 마스크를 만드는 유일한 곳 `FaceRegions`(윤곽 다각형을 회색 비트맵으로 그려 피부색 가중치와 곱함), 세 대역 `FrequencySeparation`, 사진 준비 때 도는 `BlemishDetector`를 Domain에 두고, `SkinStage`가 잡티를 기존 복제 패치로 지운 뒤 피부 마스크 안에서 중간 대역만 줄인다. 앱은 "인물" 도구를 "뷰티"(피부·얼굴 탭)로 바꾼다. 단계 목록과 이름은 바뀌지 않는다.

**Tech Stack:** Swift 5.9 tools / Swift 5 언어 모드, SwiftUI + Observation, Core Image(CIGaussianBlur·CIAreaAverage·CILinearToSRGBToneCurve·CIMultiplyCompositing·CIBlendWithMask, CIKL `CIColorKernel`), Core Graphics `CGContext`(마스크 다각형), Vision(기존 얼굴 분석), XCTest, XcodeGen 2.46.0.

**Spec:** `docs/superpowers/specs/2026-10-15-beauty-b-to-f-design.md` (B에 해당하는 절: 1.1~1.4, 2, 7, 8, 9)

## 사람이 확인할 것

- **순서.** Task 1~2 레시피·편집 규칙 → 3~6 렌더(피부 마스크·주파수 분리·잡티 찾기·피부 단계) → 7 앱 화면·시나리오 → 8 문서·검증. 8개 Task, Task마다 Opus 구현 → 리뷰 → 수정, 끝에 전체 리뷰.
- **외부 효과가 있는 단계.** 없음. 푸시·태그·TestFlight는 F를 마친 뒤(스펙 "외부 효과가 있는 단계").
- **스펙이 정하지 않아 이 계획이 정한 것.**

| 결정 | 이유 | 바꾸면 비용 |
|---|---|---|
| 피부 마스크 다각형은 얼굴 영역만 긴 변 512px 회색 비트맵에 그려 Core Image로 올림 | Core Image에는 다각형 채우기가 없음. 오목한 입술도 정확하고 새 프레임워크 import가 없음. 마스크는 흐리므로 해상도 손실이 보이지 않음 | 작음 |
| 대역 합성과 피부색 가중치는 CIKL 색 커널 2개(기존 변형 커널과 같은 방식) | 기본 필터로는 음수 차이를 안전하게 더할 수 없음. 빌드 경고(지원 중단 API) 1종이 늘어남 | 작음 |
| 피부색 기준은 볼 두 곳의 평균, 거리 기준은 고정값(분산은 재지 않음) | 렌더 중에 픽셀을 읽지 않아 미리보기가 느려지지 않음 | 작음 |
| "피부 보정" 슬라이더는 얼룩 대역을 줄이는 양, 마스크 세기는 0.85 고정 | 0이면 원본, 1이면 얼룩 대역의 85%를 줄이고 모공은 남김 | 작음 |
| 자동 잡티는 눈·눈썹·입술에 더해 코 영역도 제외 | 콧구멍이 어둡고 붉어 잡티로 잡힘 | 작음 |
| 잡티 분석이 실패하면 잡티 없음으로 처리 | 사진 준비·피부 보정·저장은 계속 동작 | 작음 |
| 체형 편집 케이스는 E에서 추가 | B에는 체형 화면이 없음. 잠금 규칙도 E에서 함께 넣음 | 작음 |
| 뷰티의 눈·입 탭은 D까지 숨김 | 빈 탭을 보이지 않음 | 작음 |
| 얼굴 탭은 "얼굴 폭" 하나, 가운데 0 양방향(기존 얼굴 변형이 넓히기도 하도록 2줄 수정) | C는 렌더러만 바꾸고 슬라이더 9개를 더함 | 작음 |
| 스키마에 옛 키(skinSmoothing·faceSlim)를 읽기 전용으로 남김 | 이전 파일도 스키마 검증을 통과(스키마 README 규칙 2) | 작음 |

- **범위 밖(다음 단계).** 인물·관절 분석 포트와 그 실패 안내(D·E), 눈·입·배경·체형·메이크업 편집 케이스와 화면, 파이프라인 단계 추가. B는 단계 목록을 바꾸지 않는다.
- **위험.** 주근깨가 잡티로 지워질 수 있다(데모 사진에 주근깨가 있음). 머리카락이 얼굴을 덮거나 조명이 강하면 피부 판별이 흔들릴 수 있다. 수치는 모두 `RenderTuning` 한 곳에서 조정한다.
- **사용자 조치.** 이 계획은 자동 검증만 한다. 실제 인물 사진으로 피부 결과를 보는 것은 F 뒤 1.2.0 TestFlight에서 한다(스펙 사용자 조치).

---

## 에이전트 참조

## Global Constraints

- 작업 위치: worktree `/Users/mj/IdeaProjects/mellow-photo/.claude/worktrees/b0-basic-editing`, 브랜치 `beauty-b-to-f`. 부모 저장소로 `cd`하지 않는다. 모든 Swift·xcodebuild 명령 전에 `export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`.
- 모듈 의존성 표(`docs/architecture/modules.md`)와 `scripts/verify-modules.sh`는 바뀌지 않는다. MellowRendering의 import는 `CoreImage`·`Foundation`·`MellowShared`·`Vision`만 쓴다(`CGContext`·`CGPath`는 CoreImage가 들여오는 CoreGraphics). Shared는 Foundation·CoreGraphics만.
- 새 보정은 MellowRendering 단계와 MellowShared 레시피 확장으로만 넣는다. 파이프라인 단계 이름 순서는 그대로 `skin, faceReshape, localEdit, geometry, color, detail, look`.
- 레시피 `schemaVersion`은 2 유지, 키 추가만 한다. 옛 키 `portrait.skinSmoothing`·`portrait.faceSlim`은 읽기만 하고 쓰지 않는다. v1 세션(평탄 배열 `undoHistory`)은 계속 읽힌다. 번들 ID `com.mj.mellowphoto`는 그대로.
- 값 범위(`EditingPolicy`): `skin.smoothing`·`features.*`·`background.blur`·`makeup.*.intensity` 0…1, `face.*`·`body.*` −1…1, `smile`·`legLength` 0…1.
- 좌표는 정규화·원점 왼쪽 아래. 잡티(`BlemishSpot`)는 미리보기에서 계산하고 영속화하지 않으며 반지름 단위는 `RetouchSpot.radius`와 같은 짧은 변 대비.
- `RenderTuning` 새 상수 시작값: skinForeheadExtension 0.2, skinFeatureFeather 0.05, skinChromaSigma 0.04, skinMaskFeather 0.015, regionMaskMaxDimension 512, fineBandFraction 0.006, midBandFraction 0.04, midReductionMax 0.85, blemishAnalysisMaxDimension 512, blemishMinRadiusFraction 0.005, blemishMaxRadiusFraction 0.02, blemishSurroundScale 3, blemishLumaDrop 0.06, blemishRednessMin 0.012, blemishMaskThreshold 0.5, blemishMaxPerFace 40, blemishHealRadiusScale 1.8, blemishSourceOffset 2.5. 지우는 상수: skinFeatureInset, skinNoiseLevel, skinNoiseSharpness, skinBlurRadiusFraction, autoFaceSlim.
- 한 줄 한 문장, 세미콜론 금지, 매직 넘버는 명명 상수(`RenderTuning`·`Theme`·`AppModel.Policy`·`EditingPolicy`, 기하 비율은 기존 `FallbackFeature`처럼 타입 안 `private static let`). CIKL 소스 문자열 안의 표준 계수(BT.601)는 주석으로 이름을 단다.
- 한국어 사용자 문구는 앱 타깃(`UserMessage`·뷰)에만. 모듈은 `MellowError`만 던진다.
- `cd apple && swift format lint --strict --recursive Sources Tests MellowPhoto MellowPhotoTests` 출력 없음(긴 줄은 줄바꿈으로 고친다). 허용된 빌드 경고: 기존 `CIWarpKernel` 지원 중단, 새 `CIColorKernel(source:)` 지원 중단(`SkinKernels`), 시뮬레이터 `usesCPUOnly`.
- `./scripts/verify-modules.sh` 통과. 전체 검증은 `./scripts/test-apple.sh`.
- 패키지 테스트: `cd apple && swift test`. Mac 앱 테스트: `xcodebuild -project apple/MellowPhoto.xcodeproj -scheme MellowPhoto -derivedDataPath apple/build -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO test 2>&1 | grep -E "Executed|TEST (SUCCEEDED|FAILED)|error:"`. 앱 파일을 더하거나 지우면 `cd apple && xcodegen generate`를 하고 `apple/MellowPhoto.xcodeproj`도 커밋한다.
- 커밋: 한국어 Conventional Commits, 마지막 줄 `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`. `git add`는 Task에 나열한 경로만.
- 각 Task 끝에 패키지 테스트(앱을 건드렸으면 Mac 앱 테스트도)와 lint가 통과해야 다음으로 간다. 기준 테스트 수(시작 시점): 패키지 136(Shared 29 · Rendering 56 · Library 29 · Export 4 · Editing 18), 앱 iPhone 46 · iPad 46 · Mac 47.

## Review Focus

스펙이 암시하지만 어느 Task의 스펙 테스트도 직접 다루지 않던 입력. 각 줄의 테스트를 소유 Task에 추가했다.

1. **B0에서 저장한 세션(portrait.skinSmoothing·faceSlim, 실행 취소 기록 포함)을 연다.** 값과 실행 취소 기록이 새 키로 옮겨지고, 다시 저장하면 옛 키가 사라져야 한다. → Task 1 `testB0SessionWithLegacyPortraitKeysMigratesUndoHistory`.
2. **자동 잡티만 켜고(피부 보정 0) 얼굴 분석이 실패한 사진을 저장한다.** 잡티 제거가 조용히 빠지지 않고 저장이 거부돼야 한다. → Task 5 `testRenderOriginalRefusesAutoBlemishOnlyWhenAnalysisFailed`.
3. **수동 잡티가 있는 사진에 "전체 사진에 적용"을 한다.** 그 사진의 얼굴 폭·체형·대상 얼굴은 유지되고 피부·메이크업은 복사돼야 한다. → Task 2 `testBatchApplyKeepsLockedShapeAndCopiesTheRest`.
4. **대상 얼굴을 한 명으로 고르고 자동 잡티를 켠다.** 다른 얼굴의 잡티는 그대로여야 한다. → Task 6 `testAutoBlemishHealsOnlyTargetFace`.
5. **얼굴 폭을 조정한 뒤 자동 보정을 누른다.** 얼굴 폭이 0으로 돌아가지 않아야 한다(B0까지는 자동 보정이 얼굴 형태를 덮어썼다). → Task 2 `testApplyAutoIsOneUndoStepAndLeavesShapeAlone` + Task 7 `testAutoEnhanceWithFaceTurnsOnAutoBlemishAndKeepsFaceWidth`.

## 인터페이스 요약 (모든 Task가 공유하는 이름)

```swift
// MellowShared
public struct SkinAdjustments { smoothing: Double; autoBlemish: Bool; hasEffect; numericValues }
public enum FaceShapeKey: String, CaseIterable { width, jaw, cheekbone, eyeSize, eyeDistance, noseWidth, mouthSize, smile, forehead, chinLength }
public struct FaceShapeAdjustments { 10 Double; init(legacyFaceSlim:); subscript(FaceShapeKey); hasEffect; numericValues }
public enum FeatureKey { eyeBrighten, teethWhiten, lipVitality }
public struct FeatureAdjustments { 3 Double; subscript(FeatureKey); hasEffect; numericValues }
public struct BackgroundAdjustments { blur; hasEffect; numericValues }
public enum BodyShapeKey { legLength, waist, overall, arms, thighs, shoulders, neck }
public struct BodyShapeAdjustments { 7 Double; subscript(BodyShapeKey); hasEffect; numericValues }
public enum MakeupPart { lip, blush, eyeshadow, brow, contour; hasColor }
public struct MakeupTint { colorID: String?; intensity }
public struct MakeupStrength { intensity }
public struct MakeupAdjustments { lookID: String?; lip, blush, eyeshadow: MakeupTint; brow, contour: MakeupStrength; intensity(of:); hasEffect; numericValues }
public struct PortraitAdjustments { targetFace: Int?; skin; face; features; dependsOnFaces; numericValues }
public struct EditRecipe { … + background, body, makeup; dependsOnFaces, dependsOnPerson, dependsOnBody }
public struct PresetValues { color, portrait, detail, background, body, makeup; init(of: EditRecipe) }
public struct BlemishSpot { x, y, radius: Double; faceIndex: Int }

// MellowEditing
public enum EditChange { … skinSmoothing(Double), autoBlemish(Bool), faceShape(FaceShapeKey, Double), targetFace(Int?) …; faceSlim 제거 }
public enum EditingPolicy { historyLimit, unitRange, bipolarRange, faceShapeRange(_:), clamped(_:to:) }

// MellowRendering
RenderTuning: + 위 Global Constraints의 상수
RenderContext: + blemishes: [BlemishSpot], targetBlemishes: [BlemishSpot] (init 마지막 인자 blemishes: = [])
PhotoPipeline: prepare가 얼굴 뒤에 잡티를 찾아 Entry에 둠; preparedBlemishes(_:) (internal, 테스트용)
enum FaceRegions (internal): faceWidth, pixelRect, skinMask(face:image:extent:tuning:strength:) throws, maskBounds, skinPolygon, protectedPolygons, blemishExclusionPolygons, cheekRects, polygonMask, contains(_:polygons:dilation:)
final class SkinKernels (internal): chromaWeight(of:left:right:sigma:extent:) throws, bandMix(image:fineBlur:midBlur:keep:extent:) throws
enum FrequencySeparation (internal): radii(faceWidth:tuning:), blurred(_:radius:), smoothed(_:bounds:faceWidth:smoothing:tuning:) throws
struct BlemishDetector (internal): init(tuning:renderer:), detect(image:faces:) throws -> [BlemishSpot]
SkinStage.healSpot(for:in:) -> RetouchSpot (internal static)

// 앱
EditorTool: look, crop, adjust, beauty, retouch, warp
enum BeautyTab: skin, face
AppModel: + beautyTab
AdjustmentSlider: + snapsToZero
Theme: + bipolarSnapWidth
```

---

### Task 1: 레시피 골격 — B~F 값 타입, 옛 키 이행, 스키마

**Files:**
- Create: `apple/Sources/MellowShared/API/SkinAdjustments.swift`
- Create: `apple/Sources/MellowShared/API/FaceShapeAdjustments.swift`
- Create: `apple/Sources/MellowShared/API/FeatureAdjustments.swift`
- Create: `apple/Sources/MellowShared/API/BackgroundAdjustments.swift`
- Create: `apple/Sources/MellowShared/API/BodyShapeAdjustments.swift`
- Create: `apple/Sources/MellowShared/API/MakeupAdjustments.swift`
- Modify: `apple/Sources/MellowShared/API/Adjustments.swift` (`PortraitAdjustments` 교체)
- Modify: `apple/Sources/MellowShared/API/EditRecipe.swift` (전체 교체)
- Modify: `apple/Sources/MellowShared/API/Preset.swift` (`PresetValues` 확장, 내장 프리셋)
- Modify(호출부 치환): `apple/Sources/MellowEditing/API/EditDocument.swift`, `apple/Sources/MellowLibrary/Infrastructure/SessionFileV1.swift`, `apple/Sources/MellowRendering/Domain/SkinStage.swift`, `apple/Sources/MellowRendering/Domain/FaceReshapeStage.swift`, `apple/Sources/MellowRendering/API/AutoEnhancer.swift`, `apple/MellowPhoto/Platform/LegacyMacPresets.swift`, `apple/MellowPhoto/Features/Editor/PortraitPanel.swift`
- Modify: `shared/recipe-schema/edit-recipe.v2.schema.json`, `shared/recipe-schema/session-file.v2.schema.json`, `shared/recipe-schema/README.md`
- Test: `apple/Tests/MellowSharedTests/EditRecipeCodingTests.swift`, `apple/Tests/MellowSharedTests/RecipeSchemaTests.swift`, `apple/Tests/MellowLibraryTests/SessionFileMigrationTests.swift`
- Test(호출부 치환): `apple/Tests/MellowRenderingTests/RenderPipelineTests.swift`, `PhotoPipelineTests.swift`, `AutoEnhancerTests.swift`, `apple/Tests/MellowLibraryTests/ProjectSessionTests.swift`, `apple/Tests/MellowEditingTests/EditDocumentTests.swift`, `apple/MellowPhotoTests/AppModelTests.swift`, `ExportPhotosTests.swift`, `LegacyMacPresetsTests.swift`

**Interfaces:**
- Consumes: 기존 `EditRecipe`, `PortraitAdjustments`, `PresetValues`, `ColorAdjustments`, `DetailAdjustments`.
- Produces: 인터페이스 요약의 MellowShared 타입 전부(`BlemishSpot` 제외, Task 5). `PortraitAdjustments(targetFace:skin:face:features:)`. `EditRecipe(color:portrait:detail:look:geometry:background:body:makeup:operations:)`. `EditRecipe.dependsOnPerson`, `dependsOnBody`. `PresetValues(color:portrait:detail:background:body:makeup:)`, `PresetValues(of:)`. `FaceShapeAdjustments(legacyFaceSlim:)`. 이 Task에서 `EditChange.faceSlim`은 남아 있고 `face.width = −값`을 쓴다(Task 2에서 제거).

- [ ] **Step 1: 실패하는 테스트 작성**

`apple/Tests/MellowSharedTests/EditRecipeCodingTests.swift`에 추가:

```swift
    func testLegacyPortraitKeysMigrateAndAreNotWritten() throws {
        let json = #"{"schemaVersion":2,"portrait":{"skinSmoothing":0.4,"faceSlim":0.3,"targetFace":1}}"#
        let decoded = try JSONDecoder().decode(EditRecipe.self, from: Data(json.utf8))
        XCTAssertEqual(decoded.portrait.skin, SkinAdjustments(smoothing: 0.4))
        XCTAssertEqual(decoded.portrait.face, FaceShapeAdjustments(width: -0.3))
        XCTAssertEqual(decoded.portrait.targetFace, 1)
        let data = try JSONEncoder().encode(decoded)
        let encoded = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let portrait = try XCTUnwrap(encoded["portrait"] as? [String: Any])
        XCTAssertEqual(Set(portrait.keys), ["targetFace", "skin", "face", "features"])
        XCTAssertEqual(try JSONDecoder().decode(EditRecipe.self, from: data), decoded)
    }

    func testNewPortraitKeysWinOverLegacyKeys() throws {
        let json =
            #"{"schemaVersion":2,"portrait":{"skinSmoothing":0.9,"skin":{"smoothing":0.2},"faceSlim":0.5,"face":{"jaw":0.1}}}"#
        let portrait = try JSONDecoder().decode(EditRecipe.self, from: Data(json.utf8)).portrait
        XCTAssertEqual(portrait.skin.smoothing, 0.2)
        XCTAssertEqual(portrait.face.width, 0)
        XCTAssertEqual(portrait.face.jaw, 0.1)
        XCTAssertEqual(FaceShapeAdjustments(legacyFaceSlim: 0).width.sign, .plus, "faceSlim 0은 −0이 아니라 0으로 옮긴다")
    }

    func testDependencyFlagsFollowEachGroup() {
        let base = EditRecipe()
        XCTAssertFalse(base.dependsOnFaces)
        XCTAssertFalse(base.dependsOnPerson)
        XCTAssertFalse(base.dependsOnBody)
        var recipe = base
        recipe.portrait.skin.autoBlemish = true
        XCTAssertTrue(recipe.dependsOnFaces, "자동 잡티만 켜도 얼굴이 필요하다")
        recipe = base
        recipe.portrait.face.width = -0.1
        XCTAssertTrue(recipe.dependsOnFaces)
        recipe = base
        recipe.portrait.features.teethWhiten = 0.1
        XCTAssertTrue(recipe.dependsOnFaces)
        recipe = base
        recipe.makeup.lip.intensity = 0.3
        XCTAssertTrue(recipe.dependsOnFaces)
        recipe = base
        recipe.makeup.lookID = "daily"
        XCTAssertFalse(recipe.dependsOnFaces, "룩 이름만으로는 렌더가 바뀌지 않는다")
        recipe = base
        recipe.background.blur = 0.5
        XCTAssertTrue(recipe.dependsOnPerson)
        XCTAssertFalse(recipe.dependsOnFaces)
        recipe = base
        recipe.body.waist = -0.2
        XCTAssertTrue(recipe.dependsOnBody)
    }

    func testEveryNewScalarIsCheckedForFiniteness() {
        let paths: [WritableKeyPath<EditRecipe, Double>] = [
            \.portrait.skin.smoothing, \.portrait.face.width, \.portrait.face.jaw, \.portrait.face.cheekbone,
            \.portrait.face.eyeSize, \.portrait.face.eyeDistance, \.portrait.face.noseWidth, \.portrait.face.mouthSize,
            \.portrait.face.smile, \.portrait.face.forehead, \.portrait.face.chinLength,
            \.portrait.features.eyeBrighten, \.portrait.features.teethWhiten, \.portrait.features.lipVitality,
            \.background.blur, \.body.legLength, \.body.waist, \.body.overall, \.body.arms, \.body.thighs,
            \.body.shoulders, \.body.neck, \.makeup.lip.intensity, \.makeup.blush.intensity,
            \.makeup.eyeshadow.intensity, \.makeup.brow.intensity, \.makeup.contour.intensity,
        ]
        for path in paths {
            var recipe = EditRecipe()
            recipe[keyPath: path] = .nan
            XCTAssertFalse(recipe.allValuesFinite, "\(path)")
        }
    }

    func testFullSkeletonRoundTrips() throws {
        var recipe = EditRecipe()
        recipe.portrait.skin = SkinAdjustments(smoothing: 0.5, autoBlemish: true)
        for key in FaceShapeKey.allCases {
            recipe.portrait.face[key] = -0.25
        }
        recipe.portrait.features = FeatureAdjustments(eyeBrighten: 0.2, teethWhiten: 0.3, lipVitality: 0.4)
        recipe.background.blur = 0.6
        for key in BodyShapeKey.allCases {
            recipe.body[key] = 0.1
        }
        recipe.makeup = MakeupAdjustments(
            lookID: "daily", lip: MakeupTint(colorID: "lip-coral", intensity: 0.5),
            blush: MakeupTint(colorID: "blush-peach", intensity: 0.3),
            eyeshadow: MakeupTint(colorID: "shadow-brown", intensity: 0.2), brow: MakeupStrength(intensity: 0.4),
            contour: MakeupStrength(intensity: 0.1))
        let data = try JSONEncoder().encode(recipe)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let portrait = try XCTUnwrap(json["portrait"] as? [String: Any])
        let face = try XCTUnwrap(portrait["face"] as? [String: Any])
        XCTAssertEqual(Set(face.keys), Set(FaceShapeKey.allCases.map(\.rawValue)))
        let body = try XCTUnwrap(json["body"] as? [String: Any])
        XCTAssertEqual(Set(body.keys), Set(BodyShapeKey.allCases.map(\.rawValue)))
        XCTAssertEqual((json["makeup"] as? [String: Any])?["lookID"] as? String, "daily")
        XCTAssertEqual(try JSONDecoder().decode(EditRecipe.self, from: data), recipe)
        XCTAssertFalse(recipe.isDefault)
    }

    func testPresetValuesCarryNewGroups() throws {
        var recipe = EditRecipe()
        recipe.portrait.skin.smoothing = 0.3
        recipe.background.blur = 0.4
        recipe.body.waist = -0.2
        recipe.makeup.brow.intensity = 0.5
        recipe.look.id = "film"
        let values = PresetValues(of: recipe)
        XCTAssertEqual(values.portrait.skin.smoothing, 0.3)
        XCTAssertEqual(values.background.blur, 0.4)
        XCTAssertEqual(values.body.waist, -0.2)
        XCTAssertEqual(values.makeup.brow.intensity, 0.5)
        XCTAssertEqual(try JSONDecoder().decode(PresetValues.self, from: JSONEncoder().encode(values)), values)
        let legacyJSON = #"{"color":{},"portrait":{"skinSmoothing":0.2}}"#
        let legacy = try JSONDecoder().decode(PresetValues.self, from: Data(legacyJSON.utf8))
        XCTAssertEqual(legacy.portrait.skin.smoothing, 0.2)
        XCTAssertEqual(legacy.background, BackgroundAdjustments())
        XCTAssertEqual(legacy.body, BodyShapeAdjustments())
        XCTAssertEqual(legacy.makeup, MakeupAdjustments())
    }

    func testShapeKeysAddressEveryValue() {
        var face = FaceShapeAdjustments()
        for (offset, key) in FaceShapeKey.allCases.enumerated() {
            face[key] = Double(offset + 1) / 10
        }
        XCTAssertEqual(face.numericValues, (1...10).map { Double($0) / 10 })
        XCTAssertEqual(face.width, Double(1) / 10)
        XCTAssertEqual(face.chinLength, Double(10) / 10)
        var body = BodyShapeAdjustments()
        for key in BodyShapeKey.allCases {
            body[key] = 0.5
        }
        XCTAssertEqual(body.numericValues, Array(repeating: 0.5, count: 7))
        var features = FeatureAdjustments()
        for key in FeatureKey.allCases {
            features[key] = 0.2
        }
        XCTAssertEqual(features.numericValues, [0.2, 0.2, 0.2])
        XCTAssertEqual(MakeupPart.allCases.filter(\.hasColor), [.lip, .blush, .eyeshadow])
    }
```

`apple/Tests/MellowSharedTests/RecipeSchemaTests.swift`: `propertyKeys` 아래에 두 도우미를 더하고, `encodedSampleRecipe()`와 `testRecipeSchemaPropertiesMatchEncodedKeys()`를 교체하고, 테스트 하나를 추가한다.

```swift
    private func sectionProperties(_ object: Any?) throws -> [String: Any] {
        try XCTUnwrap((object as? [String: Any])?["properties"] as? [String: Any])
    }

    /// deprecated로 표시한 읽기 전용 옛 키는 인코드하지 않으므로 비교에서 뺀다.
    private func activeKeys(_ object: Any?) throws -> Set<String> {
        let properties = try sectionProperties(object)
        return Set(properties.filter { (($0.value as? [String: Any])?["deprecated"] as? Bool) != true }.keys)
    }

    private func encodedSampleRecipe() throws -> [String: Any] {
        var recipe = EditRecipe()
        recipe.portrait.targetFace = 1
        recipe.portrait.skin = SkinAdjustments(smoothing: 0.3, autoBlemish: true)
        recipe.portrait.face.width = -0.2
        recipe.portrait.features.eyeBrighten = 0.1
        recipe.background.blur = 0.2
        recipe.body.legLength = 0.3
        recipe.makeup = MakeupAdjustments(
            lookID: "daily", lip: MakeupTint(colorID: "lip-coral", intensity: 0.5),
            blush: MakeupTint(colorID: "blush-peach", intensity: 0.3),
            eyeshadow: MakeupTint(colorID: "shadow-brown", intensity: 0.2), brow: MakeupStrength(intensity: 0.4),
            contour: MakeupStrength(intensity: 0.1))
        recipe.operations = [
            .spot(RetouchSpot(x: 0.5, y: 0.4, sourceX: 0.45, sourceY: 0.4, radius: 0.02)),
            .warp(WarpStroke(x: 0.5, y: 0.4, dx: 0.01, dy: 0, radius: 0.08)),
        ]
        recipe.look = LookSelection(id: "film", intensity: 0.5)
        recipe.geometry.crop = NormalizedRect(x: 0, y: 0, width: 1, height: 1)
        recipe.detail.sharpness = 0.2
        return try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(recipe)) as? [String: Any])
    }

    func testRecipeSchemaPropertiesMatchEncodedKeys() throws {
        let schema = try schema(named: "edit-recipe.v2.schema")
        let properties = try XCTUnwrap(schema["properties"] as? [String: Any])
        let encoded = try encodedSampleRecipe()
        XCTAssertEqual(Set(properties.keys), Set(encoded.keys))
        for key in ["color", "portrait", "detail", "look", "geometry", "background", "body", "makeup"] {
            let encodedSection = try XCTUnwrap(encoded[key] as? [String: Any], "\(key) 누락")
            XCTAssertEqual(try activeKeys(properties[key]), Set(encodedSection.keys), key)
        }
        let portraitProperties = try sectionProperties(properties["portrait"])
        let encodedPortrait = try XCTUnwrap(encoded["portrait"] as? [String: Any])
        for key in ["skin", "face", "features"] {
            let encodedSection = try XCTUnwrap(encodedPortrait[key] as? [String: Any], "portrait.\(key) 누락")
            XCTAssertEqual(try activeKeys(portraitProperties[key]), Set(encodedSection.keys), "portrait.\(key)")
        }
        let makeupProperties = try sectionProperties(properties["makeup"])
        let encodedMakeup = try XCTUnwrap(encoded["makeup"] as? [String: Any])
        for key in ["lip", "blush", "eyeshadow", "brow", "contour"] {
            let encodedSection = try XCTUnwrap(encodedMakeup[key] as? [String: Any], "makeup.\(key) 누락")
            XCTAssertEqual(try activeKeys(makeupProperties[key]), Set(encodedSection.keys), "makeup.\(key)")
        }
        let geometryProperties = try sectionProperties(properties["geometry"])
        let encodedCrop = try XCTUnwrap((encoded["geometry"] as? [String: Any])?["crop"] as? [String: Any])
        XCTAssertEqual(try propertyKeys(geometryProperties["crop"]), Set(encodedCrop.keys))
        try assertOperationsMatchBranches(properties: properties, encoded: encoded)
        XCTAssertEqual(schema["$id"] as? String, "https://mellow.photo/schema/edit-recipe.v2.schema.json")
    }

    func testLegacyPortraitKeysStayInSchemaAsDeprecated() throws {
        let properties = try XCTUnwrap(try schema(named: "edit-recipe.v2.schema")["properties"] as? [String: Any])
        let portrait = try sectionProperties(properties["portrait"])
        for key in ["skinSmoothing", "faceSlim"] {
            let entry = try XCTUnwrap(portrait[key] as? [String: Any], key)
            XCTAssertEqual(entry["deprecated"] as? Bool, true, key)
        }
    }
```

`apple/Tests/MellowLibraryTests/SessionFileMigrationTests.swift`에 추가:

```swift
    func testB0SessionWithLegacyPortraitKeysMigratesUndoHistory() throws {
        let json = """
            {"schemaVersion":2,"photos":[{"id":"22222222-2222-2222-2222-222222222222",\
            "filename":"22222222-2222-2222-2222-222222222222.heic","displayName":"사진 1",\
            "recipe":{"schemaVersion":2,"portrait":{"skinSmoothing":0.4,"faceSlim":0.25,"targetFace":0}},\
            "undo":[{"schemaVersion":2,"portrait":{"skinSmoothing":0.1}}],"redo":[]}],\
            "presets":[{"id":"33333333-3333-3333-3333-333333333333","name":"옛",\
            "values":{"color":{},"portrait":{"faceSlim":0.3}}}]}
            """
        let snapshot = SessionFileMapper.snapshot(from: try SessionFile.decode(Data(json.utf8)))
        let document = snapshot.photos[0].document
        XCTAssertEqual(document.recipe.portrait.skin.smoothing, 0.4)
        XCTAssertEqual(document.recipe.portrait.face.width, -0.25)
        XCTAssertEqual(document.recipe.portrait.targetFace, 0)
        XCTAssertEqual(document.undoStack[0].portrait.skin.smoothing, 0.1)
        XCTAssertEqual(snapshot.presets[0].values.portrait.face.width, -0.3)
        let rewritten = try SessionFile.encode(SessionFileMapper.file(from: snapshot))
        let text = try XCTUnwrap(String(data: rewritten, encoding: .utf8))
        XCTAssertFalse(text.contains("skinSmoothing"), "다시 저장하면 옛 키를 쓰지 않는다")
        XCTAssertFalse(text.contains("faceSlim"))
    }
```

- [ ] **Step 2: 실패 확인**

Run: `cd apple && swift test --filter EditRecipeCodingTests`
Expected: 컴파일 실패 (`SkinAdjustments` 없음).

- [ ] **Step 3: 새 값 타입**

`apple/Sources/MellowShared/API/SkinAdjustments.swift`:

```swift
import Foundation

/// 피부 보정 강도 0…1과 자동 잡티 스위치.
public struct SkinAdjustments: Codable, Equatable, Sendable {
    public var smoothing: Double
    public var autoBlemish: Bool

    public init(smoothing: Double = 0, autoBlemish: Bool = false) {
        self.smoothing = smoothing
        self.autoBlemish = autoBlemish
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        smoothing = try container.decodeIfPresent(Double.self, forKey: .smoothing) ?? 0
        autoBlemish = try container.decodeIfPresent(Bool.self, forKey: .autoBlemish) ?? false
    }

    /// 렌더 결과를 바꾸는 값이 있는지.
    public var hasEffect: Bool { smoothing != 0 || autoBlemish }
    public var numericValues: [Double] { [smoothing] }
}
```

`apple/Sources/MellowShared/API/FaceShapeAdjustments.swift`:

```swift
import Foundation

/// 얼굴형 슬라이더 이름. 레시피 JSON 키와 같다.
public enum FaceShapeKey: String, CaseIterable, Codable, Sendable {
    case width
    case jaw
    case cheekbone
    case eyeSize
    case eyeDistance
    case noseWidth
    case mouthSize
    case smile
    case forehead
    case chinLength
}

/// 얼굴형 −1…1(가운데 0). smile만 0…1. width가 음수면 좁게.
public struct FaceShapeAdjustments: Codable, Equatable, Sendable {
    public var width: Double
    public var jaw: Double
    public var cheekbone: Double
    public var eyeSize: Double
    public var eyeDistance: Double
    public var noseWidth: Double
    public var mouthSize: Double
    public var smile: Double
    public var forehead: Double
    public var chinLength: Double

    public init(
        width: Double = 0, jaw: Double = 0, cheekbone: Double = 0, eyeSize: Double = 0, eyeDistance: Double = 0,
        noseWidth: Double = 0, mouthSize: Double = 0, smile: Double = 0, forehead: Double = 0, chinLength: Double = 0
    ) {
        self.width = width
        self.jaw = jaw
        self.cheekbone = cheekbone
        self.eyeSize = eyeSize
        self.eyeDistance = eyeDistance
        self.noseWidth = noseWidth
        self.mouthSize = mouthSize
        self.smile = smile
        self.forehead = forehead
        self.chinLength = chinLength
    }

    /// B0까지의 faceSlim(0…1, 클수록 좁게)을 width로 옮긴다. 0은 −0이 아니라 0이다.
    public init(legacyFaceSlim slim: Double) {
        self.init(width: slim == 0 ? 0 : -slim)
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        width = try container.decodeIfPresent(Double.self, forKey: .width) ?? 0
        jaw = try container.decodeIfPresent(Double.self, forKey: .jaw) ?? 0
        cheekbone = try container.decodeIfPresent(Double.self, forKey: .cheekbone) ?? 0
        eyeSize = try container.decodeIfPresent(Double.self, forKey: .eyeSize) ?? 0
        eyeDistance = try container.decodeIfPresent(Double.self, forKey: .eyeDistance) ?? 0
        noseWidth = try container.decodeIfPresent(Double.self, forKey: .noseWidth) ?? 0
        mouthSize = try container.decodeIfPresent(Double.self, forKey: .mouthSize) ?? 0
        smile = try container.decodeIfPresent(Double.self, forKey: .smile) ?? 0
        forehead = try container.decodeIfPresent(Double.self, forKey: .forehead) ?? 0
        chinLength = try container.decodeIfPresent(Double.self, forKey: .chinLength) ?? 0
    }

    public subscript(key: FaceShapeKey) -> Double {
        get {
            switch key {
            case .width: return width
            case .jaw: return jaw
            case .cheekbone: return cheekbone
            case .eyeSize: return eyeSize
            case .eyeDistance: return eyeDistance
            case .noseWidth: return noseWidth
            case .mouthSize: return mouthSize
            case .smile: return smile
            case .forehead: return forehead
            case .chinLength: return chinLength
            }
        }
        set {
            switch key {
            case .width: width = newValue
            case .jaw: jaw = newValue
            case .cheekbone: cheekbone = newValue
            case .eyeSize: eyeSize = newValue
            case .eyeDistance: eyeDistance = newValue
            case .noseWidth: noseWidth = newValue
            case .mouthSize: mouthSize = newValue
            case .smile: smile = newValue
            case .forehead: forehead = newValue
            case .chinLength: chinLength = newValue
            }
        }
    }

    /// FaceShapeKey.allCases 순서.
    public var numericValues: [Double] { FaceShapeKey.allCases.map { self[$0] } }
    public var hasEffect: Bool { numericValues.contains { $0 != 0 } }
}
```

`apple/Sources/MellowShared/API/FeatureAdjustments.swift`:

```swift
import Foundation

/// 눈·입 디테일 슬라이더 이름. 레시피 JSON 키와 같다.
public enum FeatureKey: String, CaseIterable, Codable, Sendable {
    case eyeBrighten
    case teethWhiten
    case lipVitality
}

/// 눈 또렷하게·치아 미백·입술 생기 0…1. 렌더는 D 단계.
public struct FeatureAdjustments: Codable, Equatable, Sendable {
    public var eyeBrighten: Double
    public var teethWhiten: Double
    public var lipVitality: Double

    public init(eyeBrighten: Double = 0, teethWhiten: Double = 0, lipVitality: Double = 0) {
        self.eyeBrighten = eyeBrighten
        self.teethWhiten = teethWhiten
        self.lipVitality = lipVitality
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        eyeBrighten = try container.decodeIfPresent(Double.self, forKey: .eyeBrighten) ?? 0
        teethWhiten = try container.decodeIfPresent(Double.self, forKey: .teethWhiten) ?? 0
        lipVitality = try container.decodeIfPresent(Double.self, forKey: .lipVitality) ?? 0
    }

    public subscript(key: FeatureKey) -> Double {
        get {
            switch key {
            case .eyeBrighten: return eyeBrighten
            case .teethWhiten: return teethWhiten
            case .lipVitality: return lipVitality
            }
        }
        set {
            switch key {
            case .eyeBrighten: eyeBrighten = newValue
            case .teethWhiten: teethWhiten = newValue
            case .lipVitality: lipVitality = newValue
            }
        }
    }

    public var numericValues: [Double] { FeatureKey.allCases.map { self[$0] } }
    public var hasEffect: Bool { numericValues.contains { $0 != 0 } }
}
```

`apple/Sources/MellowShared/API/BackgroundAdjustments.swift`:

```swift
import Foundation

/// 배경 흐림 0…1. 렌더는 D 단계(인물 마스크).
public struct BackgroundAdjustments: Codable, Equatable, Sendable {
    public var blur: Double

    public init(blur: Double = 0) {
        self.blur = blur
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        blur = try container.decodeIfPresent(Double.self, forKey: .blur) ?? 0
    }

    public var numericValues: [Double] { [blur] }
    public var hasEffect: Bool { blur != 0 }
}
```

`apple/Sources/MellowShared/API/BodyShapeAdjustments.swift`:

```swift
import Foundation

/// 체형 슬라이더 이름. 레시피 JSON 키와 같다.
public enum BodyShapeKey: String, CaseIterable, Codable, Sendable {
    case legLength
    case waist
    case overall
    case arms
    case thighs
    case shoulders
    case neck
}

/// 체형 −1…1(가운데 0). legLength만 0…1. 렌더는 E 단계.
public struct BodyShapeAdjustments: Codable, Equatable, Sendable {
    public var legLength: Double
    public var waist: Double
    public var overall: Double
    public var arms: Double
    public var thighs: Double
    public var shoulders: Double
    public var neck: Double

    public init(
        legLength: Double = 0, waist: Double = 0, overall: Double = 0, arms: Double = 0, thighs: Double = 0,
        shoulders: Double = 0, neck: Double = 0
    ) {
        self.legLength = legLength
        self.waist = waist
        self.overall = overall
        self.arms = arms
        self.thighs = thighs
        self.shoulders = shoulders
        self.neck = neck
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        legLength = try container.decodeIfPresent(Double.self, forKey: .legLength) ?? 0
        waist = try container.decodeIfPresent(Double.self, forKey: .waist) ?? 0
        overall = try container.decodeIfPresent(Double.self, forKey: .overall) ?? 0
        arms = try container.decodeIfPresent(Double.self, forKey: .arms) ?? 0
        thighs = try container.decodeIfPresent(Double.self, forKey: .thighs) ?? 0
        shoulders = try container.decodeIfPresent(Double.self, forKey: .shoulders) ?? 0
        neck = try container.decodeIfPresent(Double.self, forKey: .neck) ?? 0
    }

    public subscript(key: BodyShapeKey) -> Double {
        get {
            switch key {
            case .legLength: return legLength
            case .waist: return waist
            case .overall: return overall
            case .arms: return arms
            case .thighs: return thighs
            case .shoulders: return shoulders
            case .neck: return neck
            }
        }
        set {
            switch key {
            case .legLength: legLength = newValue
            case .waist: waist = newValue
            case .overall: overall = newValue
            case .arms: arms = newValue
            case .thighs: thighs = newValue
            case .shoulders: shoulders = newValue
            case .neck: neck = newValue
            }
        }
    }

    public var numericValues: [Double] { BodyShapeKey.allCases.map { self[$0] } }
    public var hasEffect: Bool { numericValues.contains { $0 != 0 } }
}
```

`apple/Sources/MellowShared/API/MakeupAdjustments.swift`:

```swift
import Foundation

/// 메이크업 부위. lip·blush·eyeshadow만 색을 고른다.
public enum MakeupPart: String, CaseIterable, Codable, Sendable {
    case lip
    case blush
    case eyeshadow
    case brow
    case contour

    public var hasColor: Bool { self == .lip || self == .blush || self == .eyeshadow }
}

/// 색을 고르는 부위. colorID는 shared/makeup/makeup.v1.json의 색 id이고 nil이면 고르지 않은 상태.
public struct MakeupTint: Codable, Equatable, Sendable {
    public var colorID: String?
    public var intensity: Double

    public init(colorID: String? = nil, intensity: Double = 0) {
        self.colorID = colorID
        self.intensity = intensity
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        colorID = try container.decodeIfPresent(String.self, forKey: .colorID)
        intensity = try container.decodeIfPresent(Double.self, forKey: .intensity) ?? 0
    }
}

/// 색 없이 강도만 있는 부위(눈썹·쉐딩).
public struct MakeupStrength: Codable, Equatable, Sendable {
    public var intensity: Double

    public init(intensity: Double = 0) {
        self.intensity = intensity
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        intensity = try container.decodeIfPresent(Double.self, forKey: .intensity) ?? 0
    }
}

/// 메이크업 레시피. lookID는 마지막으로 적용한 룩이다. 렌더와 룩 규칙은 F 단계.
public struct MakeupAdjustments: Codable, Equatable, Sendable {
    public var lookID: String?
    public var lip: MakeupTint
    public var blush: MakeupTint
    public var eyeshadow: MakeupTint
    public var brow: MakeupStrength
    public var contour: MakeupStrength

    public init(
        lookID: String? = nil, lip: MakeupTint = .init(), blush: MakeupTint = .init(),
        eyeshadow: MakeupTint = .init(), brow: MakeupStrength = .init(), contour: MakeupStrength = .init()
    ) {
        self.lookID = lookID
        self.lip = lip
        self.blush = blush
        self.eyeshadow = eyeshadow
        self.brow = brow
        self.contour = contour
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        lookID = try container.decodeIfPresent(String.self, forKey: .lookID)
        lip = try container.decodeIfPresent(MakeupTint.self, forKey: .lip) ?? .init()
        blush = try container.decodeIfPresent(MakeupTint.self, forKey: .blush) ?? .init()
        eyeshadow = try container.decodeIfPresent(MakeupTint.self, forKey: .eyeshadow) ?? .init()
        brow = try container.decodeIfPresent(MakeupStrength.self, forKey: .brow) ?? .init()
        contour = try container.decodeIfPresent(MakeupStrength.self, forKey: .contour) ?? .init()
    }

    public func intensity(of part: MakeupPart) -> Double {
        switch part {
        case .lip: return lip.intensity
        case .blush: return blush.intensity
        case .eyeshadow: return eyeshadow.intensity
        case .brow: return brow.intensity
        case .contour: return contour.intensity
        }
    }

    /// MakeupPart.allCases 순서의 강도.
    public var numericValues: [Double] { MakeupPart.allCases.map { intensity(of: $0) } }
    /// 룩 이름이나 색만 있고 강도가 모두 0이면 렌더가 바뀌지 않는다.
    public var hasEffect: Bool { numericValues.contains { $0 != 0 } }
}
```

- [ ] **Step 4: PortraitAdjustments·EditRecipe·PresetValues**

`apple/Sources/MellowShared/API/Adjustments.swift`의 `PortraitAdjustments` 전체를 다음으로 교체(`ColorAdjustments`는 그대로):

```swift
/// 얼굴에 의존하는 보정. 옛 키 skinSmoothing·faceSlim은 읽기만 하고 쓰지 않는다.
public struct PortraitAdjustments: Codable, Equatable, Sendable {
    /// 왼쪽부터 센 얼굴 인덱스. nil이면 모든 얼굴.
    public var targetFace: Int?
    public var skin: SkinAdjustments
    public var face: FaceShapeAdjustments
    public var features: FeatureAdjustments

    public init(
        targetFace: Int? = nil, skin: SkinAdjustments = .init(), face: FaceShapeAdjustments = .init(),
        features: FeatureAdjustments = .init()
    ) {
        self.targetFace = targetFace
        self.skin = skin
        self.face = face
        self.features = features
    }

    private enum CodingKeys: String, CodingKey {
        case targetFace
        case skin
        case face
        case features
        case skinSmoothing
        case faceSlim
    }

    /// 새 키가 있으면 새 키, 없으면 B0까지의 옛 키를 옮긴다.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        targetFace = try container.decodeIfPresent(Int.self, forKey: .targetFace)
        if let skin = try container.decodeIfPresent(SkinAdjustments.self, forKey: .skin) {
            self.skin = skin
        } else {
            let legacy = try container.decodeIfPresent(Double.self, forKey: .skinSmoothing) ?? 0
            skin = SkinAdjustments(smoothing: legacy)
        }
        if let face = try container.decodeIfPresent(FaceShapeAdjustments.self, forKey: .face) {
            self.face = face
        } else {
            let legacy = try container.decodeIfPresent(Double.self, forKey: .faceSlim) ?? 0
            face = FaceShapeAdjustments(legacyFaceSlim: legacy)
        }
        features = try container.decodeIfPresent(FeatureAdjustments.self, forKey: .features) ?? .init()
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(targetFace, forKey: .targetFace)
        try container.encode(skin, forKey: .skin)
        try container.encode(face, forKey: .face)
        try container.encode(features, forKey: .features)
    }

    public var dependsOnFaces: Bool { skin.hasEffect || face.hasEffect || features.hasEffect }
    public var numericValues: [Double] { skin.numericValues + face.numericValues + features.numericValues }
}
```

`apple/Sources/MellowShared/API/EditRecipe.swift` 전체:

```swift
import Foundation

/// 사진 한 장의 보정 레시피. shared/recipe-schema/edit-recipe.v2.schema.json과 같은 형식.
public struct EditRecipe: Codable, Equatable, Sendable {
    public static let currentSchemaVersion = 2

    public var color = ColorAdjustments()
    public var portrait = PortraitAdjustments()
    public var detail = DetailAdjustments()
    public var look = LookSelection()
    public var geometry = GeometryAdjustments()
    public var background = BackgroundAdjustments()
    public var body = BodyShapeAdjustments()
    public var makeup = MakeupAdjustments()
    public var operations: [LocalEdit] = []

    public init(
        color: ColorAdjustments = .init(), portrait: PortraitAdjustments = .init(), detail: DetailAdjustments = .init(),
        look: LookSelection = .init(), geometry: GeometryAdjustments = .init(),
        background: BackgroundAdjustments = .init(), body: BodyShapeAdjustments = .init(),
        makeup: MakeupAdjustments = .init(), operations: [LocalEdit] = []
    ) {
        self.color = color
        self.portrait = portrait
        self.detail = detail
        self.look = look
        self.geometry = geometry
        self.background = background
        self.body = body
        self.makeup = makeup
        self.operations = operations
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case color
        case portrait
        case detail
        case look
        case geometry
        case background
        case body
        case makeup
        case operations
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        color = try container.decodeIfPresent(ColorAdjustments.self, forKey: .color) ?? .init()
        portrait = try container.decodeIfPresent(PortraitAdjustments.self, forKey: .portrait) ?? .init()
        detail = try container.decodeIfPresent(DetailAdjustments.self, forKey: .detail) ?? .init()
        look = try container.decodeIfPresent(LookSelection.self, forKey: .look) ?? .init()
        geometry = try container.decodeIfPresent(GeometryAdjustments.self, forKey: .geometry) ?? .init()
        background = try container.decodeIfPresent(BackgroundAdjustments.self, forKey: .background) ?? .init()
        body = try container.decodeIfPresent(BodyShapeAdjustments.self, forKey: .body) ?? .init()
        makeup = try container.decodeIfPresent(MakeupAdjustments.self, forKey: .makeup) ?? .init()
        operations = try container.decodeIfPresent([LocalEdit].self, forKey: .operations) ?? []
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(Self.currentSchemaVersion, forKey: .schemaVersion)
        try container.encode(color, forKey: .color)
        try container.encode(portrait, forKey: .portrait)
        try container.encode(detail, forKey: .detail)
        try container.encode(look, forKey: .look)
        try container.encode(geometry, forKey: .geometry)
        try container.encode(background, forKey: .background)
        try container.encode(body, forKey: .body)
        try container.encode(makeup, forKey: .makeup)
        try container.encode(operations, forKey: .operations)
    }

    public var spots: [RetouchSpot] {
        operations.compactMap { edit in
            if case .spot(let spot) = edit { return spot }
            return nil
        }
    }

    public var warps: [WarpStroke] {
        operations.compactMap { edit in
            if case .warp(let stroke) = edit { return stroke }
            return nil
        }
    }

    public var hasLocalEdits: Bool { !operations.isEmpty }
    /// 피부·얼굴형·눈·입·메이크업 중 하나라도 렌더를 바꾸면 얼굴 분석이 필요하다.
    public var dependsOnFaces: Bool { portrait.dependsOnFaces || makeup.hasEffect }
    /// 배경 흐림은 인물 마스크가 필요하다.
    public var dependsOnPerson: Bool { background.hasEffect }
    /// 체형은 관절점이 필요하다.
    public var dependsOnBody: Bool { body.hasEffect }
    public var isDefault: Bool { self == EditRecipe() }

    /// 렌더 전 검증용. 비유한수가 하나라도 있으면 false.
    public var allValuesFinite: Bool {
        let scalars = [color.exposure, color.contrast, color.saturation, color.warmth, look.intensity]
        let groups =
            portrait.numericValues + detail.numericValues + geometry.numericValues + background.numericValues
            + body.numericValues + makeup.numericValues
        let locals = operations.flatMap(\.numericValues)
        return (scalars + groups + locals).allSatisfy(\.isFinite)
    }
}
```

`apple/Sources/MellowShared/API/Preset.swift`의 `PresetValues`를 다음으로 교체하고 내장 프리셋 두 곳을 바꾼다.

```swift
public struct PresetValues: Codable, Equatable, Sendable {
    public var color: ColorAdjustments
    public var portrait: PortraitAdjustments
    public var detail: DetailAdjustments
    public var background: BackgroundAdjustments
    public var body: BodyShapeAdjustments
    public var makeup: MakeupAdjustments

    public init(
        color: ColorAdjustments = .init(), portrait: PortraitAdjustments = .init(), detail: DetailAdjustments = .init(),
        background: BackgroundAdjustments = .init(), body: BodyShapeAdjustments = .init(),
        makeup: MakeupAdjustments = .init()
    ) {
        self.color = color
        self.portrait = portrait
        self.detail = detail
        self.background = background
        self.body = body
        self.makeup = makeup
    }

    /// 레시피의 슬라이더 그룹. 룩·기하·수동 편집은 담지 않는다. 대상 얼굴은 호출자가 정한다.
    public init(of recipe: EditRecipe) {
        self.init(
            color: recipe.color, portrait: recipe.portrait, detail: recipe.detail, background: recipe.background,
            body: recipe.body, makeup: recipe.makeup)
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        color = try container.decodeIfPresent(ColorAdjustments.self, forKey: .color) ?? .init()
        portrait = try container.decodeIfPresent(PortraitAdjustments.self, forKey: .portrait) ?? .init()
        detail = try container.decodeIfPresent(DetailAdjustments.self, forKey: .detail) ?? .init()
        background = try container.decodeIfPresent(BackgroundAdjustments.self, forKey: .background) ?? .init()
        body = try container.decodeIfPresent(BodyShapeAdjustments.self, forKey: .body) ?? .init()
        makeup = try container.decodeIfPresent(MakeupAdjustments.self, forKey: .makeup) ?? .init()
    }
}
```

`BuiltInPresets`: `PortraitAdjustments(skinSmoothing: 0.2)` → `PortraitAdjustments(skin: SkinAdjustments(smoothing: 0.2))`, `PortraitAdjustments(skinSmoothing: 0.3)` → `PortraitAdjustments(skin: SkinAdjustments(smoothing: 0.3))`.

- [ ] **Step 5: 호출부 치환 (동작 변화 없음)**

치환 규칙(값 v는 원래 숫자 그대로):

| 원래 | 바꾼 뒤 |
|---|---|
| `….portrait.skinSmoothing = v` / `XCTAssertEqual(….portrait.skinSmoothing, v)` | `….portrait.skin.smoothing = v` / `XCTAssertEqual(….portrait.skin.smoothing, v)` |
| `….portrait.faceSlim = v` / `XCTAssertEqual(….portrait.faceSlim, v)` | `….portrait.face.width = -v` / `XCTAssertEqual(….portrait.face.width, -v)` |
| `PortraitAdjustments(skinSmoothing: a)` | `PortraitAdjustments(skin: SkinAdjustments(smoothing: a))` |
| `PortraitAdjustments(faceSlim: b)` | `PortraitAdjustments(face: FaceShapeAdjustments(width: -b))` |
| `PortraitAdjustments(faceSlim: b, targetFace: t)` | `PortraitAdjustments(targetFace: t, face: FaceShapeAdjustments(width: -b))` |
| `PortraitAdjustments(skinSmoothing: a, faceSlim: b)` | `PortraitAdjustments(skin: SkinAdjustments(smoothing: a), face: FaceShapeAdjustments(width: -b))` |

이 규칙을 적용할 곳: `RenderPipelineTests.swift` 71·72·80·81·91·109·124행, `EditRecipeCodingTests.swift` 16·52행, `PhotoPipelineTests.swift` 105·112·124·135행, `SessionFileMigrationTests.swift` 22·23·35행, `ProjectSessionTests.swift` 152·155행, `EditDocumentTests.swift` 75·88·91·98·99·111·114·117·205·210·211·223행, `ExportPhotosTests.swift` 86행, `LegacyMacPresetsTests.swift` 20행, `AppModelTests.swift` 65·193행. `EditChange.faceSlim(…)` 호출은 이 Task에서 그대로 둔다.

소스 치환:

- `EditDocument.swift` `set`: `case .skinSmoothing(let value): updated.portrait.skin.smoothing = value`, `case .faceSlim(let value): updated.portrait.face.width = FaceShapeAdjustments(legacyFaceSlim: value).width`. `apply`·`applyFromBatch`·`applyAuto`의 `portrait.faceSlim = recipe.portrait.faceSlim` 세 줄은 `portrait.face = recipe.portrait.face`.
- `SessionFileV1.swift` `values(_:)`의 portrait 인자:

```swift
            portrait: PortraitAdjustments(
                skin: SkinAdjustments(smoothing: adjustments.skin),
                face: FaceShapeAdjustments(legacyFaceSlim: adjustments.faceSlim)))
```

- `SkinStage.swift`: `let strength = context.recipe.portrait.skin.smoothing`.
- `FaceReshapeStage.swift`: `let amount = -context.recipe.portrait.face.width` (나머지 그대로, Task 6에서 양방향으로 바꿈).
- `AutoEnhancer.swift` `if hasFaces` 블록: `portrait.skin.smoothing = tuning.autoSkinSmoothing`, `portrait.face = FaceShapeAdjustments(legacyFaceSlim: tuning.autoFaceSlim)`. `AutoEnhancerTests.swift` 103·104행: `XCTAssertEqual(withFaces.skin.smoothing, RenderTuning().autoSkinSmoothing)`, `XCTAssertEqual(withFaces.face.width, -RenderTuning().autoFaceSlim)`.
- `LegacyMacPresets.swift` `values`: `let portrait = PortraitAdjustments()` 줄을 지우고 portrait 인자를

```swift
                portrait: PortraitAdjustments(
                    skin: SkinAdjustments(smoothing: adjustments.skin ?? 0),
                    face: FaceShapeAdjustments(legacyFaceSlim: adjustments.faceSlim ?? 0)))
```

- `PortraitPanel.swift` 두 슬라이더: `value: recipe.portrait.skin.smoothing`, `value: -recipe.portrait.face.width` (`.skinSmoothing($0)`·`.faceSlim($0)`는 그대로, Task 7에서 패널을 교체).

확인: `grep -rn "portrait.skinSmoothing\|portrait.faceSlim\|skinSmoothing:\|faceSlim:" apple` → 결과 없음.

- [ ] **Step 6: 스키마와 README**

`shared/recipe-schema/edit-recipe.v2.schema.json`의 `portrait`를 다음으로 교체하고, `geometry` 뒤(`operations` 앞)에 `background`·`body`·`makeup`을 넣는다.

```json
    "portrait": {
      "type": "object",
      "additionalProperties": false,
      "properties": {
        "targetFace": { "type": ["integer", "null"], "default": null, "description": "왼쪽부터 센 얼굴 인덱스. null이면 모든 얼굴." },
        "skin": {
          "type": "object", "additionalProperties": false,
          "properties": {
            "smoothing": { "type": "number", "default": 0, "minimum": 0, "maximum": 1 },
            "autoBlemish": { "type": "boolean", "default": false }
          }
        },
        "face": {
          "type": "object", "additionalProperties": false,
          "description": "가운데 0인 양방향. width 음수는 좁게. smile만 0~1.",
          "properties": {
            "width": { "type": "number", "default": 0, "minimum": -1, "maximum": 1 },
            "jaw": { "type": "number", "default": 0, "minimum": -1, "maximum": 1 },
            "cheekbone": { "type": "number", "default": 0, "minimum": -1, "maximum": 1 },
            "eyeSize": { "type": "number", "default": 0, "minimum": -1, "maximum": 1 },
            "eyeDistance": { "type": "number", "default": 0, "minimum": -1, "maximum": 1 },
            "noseWidth": { "type": "number", "default": 0, "minimum": -1, "maximum": 1 },
            "mouthSize": { "type": "number", "default": 0, "minimum": -1, "maximum": 1 },
            "smile": { "type": "number", "default": 0, "minimum": 0, "maximum": 1 },
            "forehead": { "type": "number", "default": 0, "minimum": -1, "maximum": 1 },
            "chinLength": { "type": "number", "default": 0, "minimum": -1, "maximum": 1 }
          }
        },
        "features": {
          "type": "object", "additionalProperties": false,
          "properties": {
            "eyeBrighten": { "type": "number", "default": 0, "minimum": 0, "maximum": 1 },
            "teethWhiten": { "type": "number", "default": 0, "minimum": 0, "maximum": 1 },
            "lipVitality": { "type": "number", "default": 0, "minimum": 0, "maximum": 1 }
          }
        },
        "skinSmoothing": { "type": "number", "minimum": 0, "maximum": 1, "deprecated": true, "description": "B0까지의 읽기 전용 키. skin이 없을 때만 skin.smoothing으로 읽는다. 쓰지 않는다." },
        "faceSlim": { "type": "number", "minimum": 0, "maximum": 1, "deprecated": true, "description": "B0까지의 읽기 전용 키. face가 없을 때만 face.width = −faceSlim으로 읽는다. 쓰지 않는다." }
      }
    },
```

```json
    "background": {
      "type": "object", "additionalProperties": false,
      "properties": { "blur": { "type": "number", "default": 0, "minimum": 0, "maximum": 1 } }
    },
    "body": {
      "type": "object", "additionalProperties": false,
      "description": "가운데 0인 양방향. legLength만 0~1.",
      "properties": {
        "legLength": { "type": "number", "default": 0, "minimum": 0, "maximum": 1 },
        "waist": { "type": "number", "default": 0, "minimum": -1, "maximum": 1 },
        "overall": { "type": "number", "default": 0, "minimum": -1, "maximum": 1 },
        "arms": { "type": "number", "default": 0, "minimum": -1, "maximum": 1 },
        "thighs": { "type": "number", "default": 0, "minimum": -1, "maximum": 1 },
        "shoulders": { "type": "number", "default": 0, "minimum": -1, "maximum": 1 },
        "neck": { "type": "number", "default": 0, "minimum": -1, "maximum": 1 }
      }
    },
    "makeup": {
      "type": "object", "additionalProperties": false,
      "properties": {
        "lookID": { "type": ["string", "null"], "default": null, "description": "shared/makeup/makeup.v1.json의 룩 id. 마지막으로 적용한 룩." },
        "lip": {
          "type": "object", "additionalProperties": false,
          "properties": {
            "colorID": { "type": ["string", "null"], "default": null },
            "intensity": { "type": "number", "default": 0, "minimum": 0, "maximum": 1 }
          }
        },
        "blush": {
          "type": "object", "additionalProperties": false,
          "properties": {
            "colorID": { "type": ["string", "null"], "default": null },
            "intensity": { "type": "number", "default": 0, "minimum": 0, "maximum": 1 }
          }
        },
        "eyeshadow": {
          "type": "object", "additionalProperties": false,
          "properties": {
            "colorID": { "type": ["string", "null"], "default": null },
            "intensity": { "type": "number", "default": 0, "minimum": 0, "maximum": 1 }
          }
        },
        "brow": {
          "type": "object", "additionalProperties": false,
          "properties": { "intensity": { "type": "number", "default": 0, "minimum": 0, "maximum": 1 } }
        },
        "contour": {
          "type": "object", "additionalProperties": false,
          "properties": { "intensity": { "type": "number", "default": 0, "minimum": 0, "maximum": 1 } }
        }
      }
    },
```

`shared/recipe-schema/session-file.v2.schema.json`의 프리셋 `values.properties`에 다음 세 줄을 `detail` 뒤에 추가:

```json
              "background": { "$ref": "edit-recipe.v2.schema.json#/properties/background" },
              "body": { "$ref": "edit-recipe.v2.schema.json#/properties/body" },
              "makeup": { "$ref": "edit-recipe.v2.schema.json#/properties/makeup" }
```

`shared/recipe-schema/README.md`:
- 첫 표의 `edit-recipe.v2` 기준 구현 칸에 `SkinAdjustments.swift`, `FaceShapeAdjustments.swift`, `FeatureAdjustments.swift`, `BackgroundAdjustments.swift`, `BodyShapeAdjustments.swift`, `MakeupAdjustments.swift`를 더한다.
- `RecipeSchemaTests` 설명을 "피부·얼굴형·디테일·배경·체형·메이크업까지 채운 레시피를 인코드해 최상위 키, 각 그룹 키, `portrait.skin/face/features`, `makeup`의 부위 키를 비교합니다. `deprecated: true`인 읽기 전용 옛 키는 비교에서 뺍니다."로 바꾼다.
- "v2 형식 요점"에 다음 네 줄을 추가한다.
  - `portrait`는 `skin`(피부 보정 `smoothing` 0~1, 자동 잡티 `autoBlemish`), `face`(얼굴형 10개, 가운데 0인 양방향, `smile`만 0~1), `features`(눈 또렷하게·치아 미백·입술 생기 0~1)로 나뉩니다.
  - 최상위 `background`(배경 흐림), `body`(체형 7개, `legLength`만 0~1), `makeup`(룩 id와 부위별 색 id·강도)이 있습니다. 렌더는 단계별로 들어오며 값이 기본이면 결과가 바뀌지 않습니다.
  - B0까지 쓰던 `portrait.skinSmoothing`·`portrait.faceSlim`은 읽기만 합니다. `skin`이 없으면 `skin.smoothing = skinSmoothing`, `face`가 없으면 `face.width = −faceSlim`(0은 0)으로 읽고, 쓸 때는 새 키만 씁니다. 스키마에는 `deprecated: true`로 남아 있어 이전 파일도 검증을 통과합니다.
  - 프리셋 `values`는 `color`·`portrait`·`detail`·`background`·`body`·`makeup`을 담습니다. 없는 그룹은 기본값으로 읽습니다.
- "값이 없는 선택 키" 목록에 `makeup.lookID`, `makeup.*.colorID`를 더한다.
- 범위 표의 `portrait.skinSmoothing`·`portrait.faceSlim` 두 행을 다음 행으로 바꾼다: `portrait.skin.smoothing` 0…1 / 0…1, `portrait.face.*` −1…1(smile 0…1) / 같음, `portrait.features.*` 0…1 / 0…1, `background.blur` 0…1 / 0…1, `body.*` −1…1(legLength 0…1) / 같음, `makeup.*.intensity` 0…1 / 0…1. 표 아래 문장의 `PortraitPanel.swift`는 `BeautyPanel.swift`로, "권장 범위는 `EditingPolicy`의 명명 상수"를 덧붙인다.
- v1 → v2 변환 표: `recipe.adjustments.skin` → `recipe.portrait.skin.smoothing`, `recipe.adjustments.faceSlim` → `recipe.portrait.face.width`(부호 반대, 0은 0), `presets[].adjustments` → `presets[].values.{color,portrait}`.
- "키를 추가할 때의 규칙 (B~F)" 첫 문장을 "B 단계에서 B~F의 레시피 골격(`portrait.skin/face/features`, `background`, `body`, `makeup`)을 한 번에 넣었습니다. 이후 단계는 렌더만 채웁니다. 새 키가 더 필요하면 다음을 지킵니다."로 바꾼다.

- [ ] **Step 7: 통과 확인**

Run: `cd apple && swift test` → 145개 PASS(Shared 37 · Rendering 56 · Library 30 · Export 4 · Editing 18). `swift format lint --strict --recursive Sources Tests MellowPhoto MellowPhotoTests` → 출력 없음. Mac 앱 테스트 → `Executed 47 tests, with 0 failures`.

- [ ] **Step 8: 커밋**

```bash
git add apple/Sources apple/Tests apple/MellowPhoto/Platform/LegacyMacPresets.swift apple/MellowPhoto/Features/Editor/PortraitPanel.swift apple/MellowPhotoTests shared/recipe-schema
git commit -m "feat(shared): 인물 보정 B~F 레시피 골격과 옛 피부·얼굴 키 이행 추가

피부·얼굴형·눈입·배경·체형·메이크업 값 타입을 기본값과 함께 넣고
portrait.skinSmoothing·faceSlim은 새 키로 읽기만 한다. schemaVersion은 2를 유지한다.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 2: 편집 규칙 — faceShape·autoBlemish·범위, 프리셋·일괄·자동 보정이 새 그룹을 나름

**Files:**
- Modify: `apple/Sources/MellowEditing/API/EditChange.swift`
- Modify: `apple/Sources/MellowEditing/API/EditingPolicy.swift`
- Modify: `apple/Sources/MellowEditing/API/EditDocument.swift` (`set`, `apply`, `applyFromBatch`, `applyAuto`)
- Modify: `apple/Sources/MellowLibrary/API/ProjectSession.swift` (`applyToAll`)
- Modify: `apple/Sources/MellowRendering/API/AutoEnhancer.swift`, `apple/Sources/MellowRendering/API/RenderTuning.swift` (`autoFaceSlim` 삭제)
- Modify: `apple/MellowPhoto/Application/AppModel+Editing.swift` (`savePreset`), `apple/MellowPhoto/Features/Editor/PortraitPanel.swift`
- Test: `apple/Tests/MellowEditingTests/EditDocumentTests.swift`, `apple/Tests/MellowLibraryTests/ProjectSessionTests.swift`, `apple/Tests/MellowRenderingTests/AutoEnhancerTests.swift`, `apple/MellowPhotoTests/AppModelTests.swift`

**Interfaces:**
- Consumes: Task 1의 타입, `PresetValues(of:)`, `FaceShapeKey`.
- Produces: `EditChange.autoBlemish(Bool)`, `EditChange.faceShape(FaceShapeKey, Double)`(`faceSlim` 제거), `affectsGeometry`는 `faceShape`·`targetFace`. `EditingPolicy.unitRange`(0…1), `bipolarRange`(−1…1), `faceShapeRange(_ key: FaceShapeKey) -> ClosedRange<Double>`, `clamped(_:to:) -> Double`. `apply`·`applyFromBatch`는 background·body·makeup도 적용하고 잠긴 사진은 face·body 유지. `applyAuto`는 color·detail·portrait.skin·portrait.features만 바꾼다. `AutoEnhancer`는 얼굴이 있으면 `skin = SkinAdjustments(smoothing: autoSkinSmoothing, autoBlemish: true)`. E 단계가 `bodyShape(BodyShapeKey, Double)`를 더할 때 `affectsGeometry`에 넣는다.

- [ ] **Step 1: 실패하는 테스트 작성**

`EditDocumentTests.swift`에서 `testLocalEditLocksFaceSlimAndTargetFace`, `testPresetPreservesFaceSlimWhenLocked`, `testPresetReplacesEverythingWhenUnlocked`, `testBatchApplyKeepsLockedGeometryAndResetsTargetOtherwise`, `testApplyAutoIsOneUndoStepAndKeepsLockedGeometry`를 지우고 다음을 넣는다(`testApplyAutoWithSameValuesIsNoOp`는 Task 1 치환 상태 그대로).

```swift
    func testLocalEditLocksFaceShapeAndTargetFace() {
        var document = EditDocument()
        document.set(.faceShape(.width, -0.2))
        document.set(.targetFace(1))
        document.appendLocalEdit(.spot(RetouchSpot(x: 0.5, y: 0.4, sourceX: 0.4, sourceY: 0.4, radius: 0.02)))
        XCTAssertTrue(document.isGeometryLocked)
        XCTAssertEqual(document.set(.faceShape(.width, -0.9)), .geometryLocked)
        XCTAssertEqual(document.set(.faceShape(.jaw, 0.3)), .geometryLocked)
        XCTAssertEqual(document.set(.targetFace(nil)), .geometryLocked)
        XCTAssertEqual(document.recipe.portrait.face, FaceShapeAdjustments(width: -0.2))
        XCTAssertEqual(document.recipe.portrait.targetFace, 1)
        XCTAssertNil(document.set(.skinSmoothing(0.5)))
        // 피부 보정, 수동 편집 순으로 되돌린다.
        document.undo()
        document.undo()
        XCTAssertFalse(document.isGeometryLocked)
    }

    func testAutoBlemishIsNotLockedAndUndoesInOneStep() {
        var document = EditDocument()
        document.appendLocalEdit(.warp(WarpStroke(x: 0.5, y: 0.5, dx: 0.01, dy: 0, radius: 0.1)))
        XCTAssertNil(document.set(.autoBlemish(true)))
        XCTAssertTrue(document.recipe.portrait.skin.autoBlemish)
        let count = document.undoStack.count
        XCTAssertNil(document.set(.autoBlemish(true)))
        XCTAssertEqual(document.undoStack.count, count, "같은 값은 단계를 만들지 않는다")
        document.undo()
        XCTAssertFalse(document.recipe.portrait.skin.autoBlemish)
    }

    func testNewChangesClampToPolicyRanges() {
        var document = EditDocument()
        document.set(.skinSmoothing(1.5))
        XCTAssertEqual(document.recipe.portrait.skin.smoothing, EditingPolicy.unitRange.upperBound)
        document.set(.faceShape(.width, -3))
        XCTAssertEqual(document.recipe.portrait.face.width, EditingPolicy.bipolarRange.lowerBound)
        document.set(.faceShape(.smile, -0.5))
        XCTAssertEqual(document.recipe.portrait.face.smile, 0, "미소는 한 방향만")
        document.set(.faceShape(.eyeSize, 0.4))
        XCTAssertEqual(document.recipe.portrait.face.eyeSize, 0.4)
        XCTAssertEqual(EditingPolicy.faceShapeRange(.smile), 0...1)
        XCTAssertEqual(EditingPolicy.faceShapeRange(.jaw), -1...1)
    }

    func testPresetPreservesFaceShapeWhenLocked() {
        var document = EditDocument()
        document.set(.faceShape(.width, -0.2))
        document.appendLocalEdit(.warp(WarpStroke(x: 0.5, y: 0.5, dx: 0.01, dy: 0, radius: 0.1)))
        let preset = PresetValues(
            color: ColorAdjustments(exposure: 0.5), portrait: PortraitAdjustments(face: FaceShapeAdjustments(width: -0.7)))
        document.apply(preset)
        XCTAssertEqual(document.recipe.color.exposure, 0.5)
        XCTAssertEqual(document.recipe.portrait.face.width, -0.2)
        XCTAssertEqual(document.recipe.operations.count, 1)
    }

    func testPresetReplacesEverythingWhenUnlocked() {
        var document = EditDocument()
        document.set(.targetFace(2))
        document.apply(
            PresetValues(
                portrait: PortraitAdjustments(targetFace: 5, face: FaceShapeAdjustments(width: -0.7)),
                background: BackgroundAdjustments(blur: 0.4), body: BodyShapeAdjustments(waist: -0.3),
                makeup: MakeupAdjustments(brow: MakeupStrength(intensity: 0.5))))
        XCTAssertEqual(document.recipe.portrait.face.width, -0.7)
        XCTAssertEqual(document.recipe.portrait.targetFace, 2, "프리셋은 얼굴을 고르지 않으므로 사진의 대상 얼굴을 유지한다")
        XCTAssertEqual(document.recipe.background.blur, 0.4)
        XCTAssertEqual(document.recipe.body.waist, -0.3)
        XCTAssertEqual(document.recipe.makeup.brow.intensity, 0.5)
    }

    func testBatchApplyKeepsLockedShapeAndCopiesTheRest() {
        var locked = EditDocument()
        locked.set(.faceShape(.width, -0.2))
        locked.set(.targetFace(1))
        locked.appendLocalEdit(.spot(RetouchSpot(x: 0.5, y: 0.4, sourceX: 0.4, sourceY: 0.4, radius: 0.02)))
        var unlocked = EditDocument()
        unlocked.set(.targetFace(0))
        let values = PresetValues(
            color: ColorAdjustments(exposure: 0.3),
            portrait: PortraitAdjustments(
                targetFace: 3, skin: SkinAdjustments(smoothing: 0.6), face: FaceShapeAdjustments(width: -0.9)),
            body: BodyShapeAdjustments(legLength: 0.4),
            makeup: MakeupAdjustments(lip: MakeupTint(colorID: "lip-coral", intensity: 0.5)))
        locked.applyFromBatch(values)
        unlocked.applyFromBatch(values)
        XCTAssertEqual(locked.recipe.portrait.face.width, -0.2)
        XCTAssertEqual(locked.recipe.body, BodyShapeAdjustments(), "잠긴 사진은 체형도 유지한다")
        XCTAssertEqual(locked.recipe.portrait.targetFace, 1)
        XCTAssertEqual(locked.recipe.portrait.skin.smoothing, 0.6, "피부는 잠금과 무관하게 복사한다")
        XCTAssertEqual(locked.recipe.makeup.lip.colorID, "lip-coral")
        XCTAssertEqual(locked.recipe.color.exposure, 0.3)
        XCTAssertEqual(unlocked.recipe.portrait.face.width, -0.9)
        XCTAssertEqual(unlocked.recipe.body.legLength, 0.4)
        XCTAssertNil(unlocked.recipe.portrait.targetFace)
        XCTAssertTrue(locked.canUndo)
        XCTAssertTrue(unlocked.canUndo)
    }

    func testApplyAutoIsOneUndoStepAndLeavesShapeAlone() {
        var recipe = EditRecipe()
        recipe.body.waist = -0.3
        recipe.makeup.lip = MakeupTint(colorID: "lip-rose", intensity: 0.4)
        var document = EditDocument(recipe: recipe)
        document.set(.faceShape(.width, -0.2))
        document.set(.targetFace(1))
        document.set(.lookID("film"))
        let before = document.undoStack.count
        let suggestion = AutoEnhanceSuggestion(
            color: ColorAdjustments(exposure: 0.3, saturation: 1.08), detail: DetailAdjustments(highlights: -0.2),
            portrait: PortraitAdjustments(skin: SkinAdjustments(smoothing: 0.3, autoBlemish: true)))
        document.applyAuto(suggestion)
        XCTAssertEqual(document.undoStack.count, before + 1)
        XCTAssertEqual(document.recipe.color.exposure, 0.3)
        XCTAssertEqual(document.recipe.detail.highlights, -0.2)
        XCTAssertEqual(document.recipe.portrait.skin, SkinAdjustments(smoothing: 0.3, autoBlemish: true))
        XCTAssertEqual(document.recipe.portrait.face.width, -0.2, "자동 보정은 얼굴형을 건드리지 않는다")
        XCTAssertEqual(document.recipe.portrait.targetFace, 1)
        XCTAssertEqual(document.recipe.body.waist, -0.3)
        XCTAssertEqual(document.recipe.makeup.lip.colorID, "lip-rose")
        XCTAssertEqual(document.recipe.look.id, "film", "자동 보정은 룩을 건드리지 않는다")
        document.undo()
        XCTAssertEqual(document.recipe.color.exposure, 0)
    }
```

`ProjectSessionTests.testApplyToAllCopiesValuesWithBatchRules`: `.faceSlim(0.2)` → `.faceShape(.width, -0.2)`, `.faceSlim(0.9)` → `.faceShape(.width, -0.9)`. `session.applyToAll(from: source.id)` 바로 앞에 다음을 넣고, 끝에 단언 두 줄을 더한다.

```swift
        session.edit(source.id) { document in
            var values = PresetValues(of: document.recipe)
            values.background.blur = 0.4
            document.apply(values)
            return nil
        }
```

```swift
        XCTAssertEqual(session.photos[1].document.recipe.background.blur, 0.4, "잠긴 사진도 배경 값은 복사한다")
        XCTAssertEqual(session.photos[2].document.recipe.background.blur, 0.4)
```

`AutoEnhancerTests.testFacesAddPortraitValues`의 두 단언을 다음으로 바꾼다.

```swift
        XCTAssertEqual(withFaces.skin, SkinAdjustments(smoothing: RenderTuning().autoSkinSmoothing, autoBlemish: true))
        XCTAssertEqual(withFaces.face, FaceShapeAdjustments(), "자동 보정은 얼굴형을 제안하지 않는다")
```

`AppModelTests.swift`: 56행 `.faceSlim(0.2)` → `.faceShape(.width, -0.2)`, 64행 `.faceSlim(0.9)` → `.faceShape(.width, -0.9)`, 187행 `.faceSlim(0.4)` → `.faceShape(.width, -0.4)`.

- [ ] **Step 2: 실패 확인**

Run: `cd apple && swift test --filter EditDocumentTests` → 컴파일 실패(`faceShape` 없음).

- [ ] **Step 3: 구현**

`EditingPolicy.swift` 전체:

```swift
import MellowShared

public enum EditingPolicy {
    /// 사진 한 장당 보관하는 실행 취소 단계 수.
    public static let historyLimit = 40
    /// 피부·눈입·배경·메이크업 강도.
    public static let unitRange: ClosedRange<Double> = 0...1
    /// 얼굴형·체형의 가운데 0인 양방향 범위.
    public static let bipolarRange: ClosedRange<Double> = -1...1

    /// 미소만 한 방향이다.
    public static func faceShapeRange(_ key: FaceShapeKey) -> ClosedRange<Double> {
        key == .smile ? unitRange : bipolarRange
    }

    /// NaN은 범위의 아래 끝이 된다.
    public static func clamped(_ value: Double, to range: ClosedRange<Double>) -> Double {
        min(range.upperBound, max(range.lowerBound, value))
    }
}
```

`EditChange.swift`: `case faceSlim(Double)`를 지우고 `case skinSmoothing(Double)` 아래에 두 케이스를 넣고 `affectsGeometry`를 고친다.

```swift
    case skinSmoothing(Double)
    case autoBlemish(Bool)
    case faceShape(FaceShapeKey, Double)
    case targetFace(Int?)
```

```swift
    /// 수동 편집이 있는 동안 바꿀 수 없는 변경. 자르기·회전은 원본 좌표를 바꾸지 않으므로 잠기지 않는다.
    /// E 단계의 체형 변경도 여기에 더한다.
    public var affectsGeometry: Bool {
        switch self {
        case .faceShape, .targetFace:
            return true
        default:
            return false
        }
    }
```

`EditDocument.set`의 두 줄(`skinSmoothing`, `faceSlim`)을 다음 세 줄로:

```swift
        case .skinSmoothing(let value):
            updated.portrait.skin.smoothing = EditingPolicy.clamped(value, to: EditingPolicy.unitRange)
        case .autoBlemish(let flag): updated.portrait.skin.autoBlemish = flag
        case .faceShape(let key, let value):
            updated.portrait.face[key] = EditingPolicy.clamped(value, to: EditingPolicy.faceShapeRange(key))
```

`apply`·`applyFromBatch`·`applyAuto`를 다음으로 교체하고 `merged`를 추가:

```swift
    /// 사용자가 고른 프리셋. 프리셋은 얼굴을 고르지 않으므로 대상 얼굴은 늘 사진의 값을 유지한다.
    /// 잠긴 사진은 얼굴형·체형도 유지한다.
    public mutating func apply(_ values: PresetValues) {
        checkpoint()
        recipe = merged(values, targetFace: recipe.portrait.targetFace)
    }

    /// 다른 사진의 설정을 일괄 복사. 잠기지 않은 사진은 대상 얼굴을 전체로 되돌린다.
    public mutating func applyFromBatch(_ values: PresetValues) {
        checkpoint()
        recipe = merged(values, targetFace: isGeometryLocked ? recipe.portrait.targetFace : nil)
    }

    /// 자동 보정 제안을 한 번의 체크포인트로 적용한다. 색·디테일·피부·눈입만 바꾸고
    /// 대상 얼굴·얼굴형·체형·배경·메이크업·룩·기하·수동 편집은 건드리지 않는다.
    /// 이미 같은 값이면 아무것도 하지 않아 연타해도 실행 취소 한 번에 되돌아간다. 적용했으면 true.
    @discardableResult
    public mutating func applyAuto(_ suggestion: AutoEnhanceSuggestion) -> Bool {
        var updated = recipe
        updated.color = suggestion.color
        updated.detail = suggestion.detail
        updated.portrait.skin = suggestion.portrait.skin
        updated.portrait.features = suggestion.portrait.features
        guard updated != recipe else { return false }
        checkpoint()
        recipe = updated
        return true
    }

    /// 슬라이더 그룹을 프리셋 값으로 바꾼다. 룩·기하·수동 편집은 그대로 둔다.
    private func merged(_ values: PresetValues, targetFace: Int?) -> EditRecipe {
        var updated = recipe
        updated.color = values.color
        updated.detail = values.detail
        updated.portrait = values.portrait
        updated.portrait.targetFace = targetFace
        updated.background = values.background
        updated.body = values.body
        updated.makeup = values.makeup
        if isGeometryLocked {
            updated.portrait.face = recipe.portrait.face
            updated.body = recipe.body
        }
        return updated
    }
```

`ProjectSession.applyToAll`: `let values = PresetValues(color: recipe.color, portrait: recipe.portrait, detail: recipe.detail)` → `let values = PresetValues(of: recipe)`.

`AutoEnhancer.suggestion`의 `if hasFaces` 블록:

```swift
        if hasFaces {
            portrait.skin = SkinAdjustments(smoothing: tuning.autoSkinSmoothing, autoBlemish: true)
        }
```

`RenderTuning.swift`에서 `public var autoFaceSlim: Double = 0.15` 줄을 지운다.

`AppModel+Editing.swift` `savePreset`:

```swift
    /// 프리셋은 얼굴을 고르지 않는다. 대상 얼굴 번호는 사진마다 의미가 달라 저장하지 않는다.
    func savePreset(named name: String) {
        var values = PresetValues(of: currentRecipe)
        values.portrait.targetFace = nil
        session.addPreset(named: name, values: values)
    }
```

`PortraitPanel.swift` 얼굴 슬라이더의 변경 클로저: `{ .faceSlim($0) }` → `{ .faceShape(.width, -$0) }` (Task 7에서 패널 교체).

- [ ] **Step 4: 통과 확인**

Run: `cd apple && swift test` → 147개 PASS(Editing 20). lint 출력 없음. Mac 앱 테스트 → `Executed 47 tests, with 0 failures`. `grep -rn "faceSlim(" apple/Sources apple/Tests apple/MellowPhoto apple/MellowPhotoTests` → 결과 없음.

- [ ] **Step 5: 커밋**

```bash
git add apple/Sources apple/Tests apple/MellowPhoto/Application/AppModel+Editing.swift apple/MellowPhoto/Features/Editor/PortraitPanel.swift apple/MellowPhotoTests/AppModelTests.swift
git commit -m "feat(editing): 얼굴형·자동 잡티 변경과 새 그룹의 프리셋·일괄 적용 규칙 추가

faceSlim 변경을 faceShape(.width)로 바꾸고 범위는 EditingPolicy 한 곳에 둔다.
자동 보정은 피부만 채우고 얼굴형·체형·메이크업은 건드리지 않는다.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 3: FaceRegions — 윤곽 다각형 피부 마스크와 피부색 가중치

**Files:**
- Create: `apple/Sources/MellowRendering/Domain/FaceRegions.swift`
- Create: `apple/Sources/MellowRendering/Domain/SkinKernels.swift`
- Modify: `apple/Sources/MellowRendering/API/RenderTuning.swift` (피부 마스크 상수)
- Modify: `apple/Tests/MellowRenderingTests/RenderingTestSupport.swift` (합성 얼굴, 피부 질감, 픽셀 격자)
- Test: `apple/Tests/MellowRenderingTests/FaceRegionsTests.swift`

**Interfaces:**
- Consumes: `FaceGeometry`, `FaceLandmark`, `NormalizedRect`, `RenderTuning`, `MellowError.renderFailed`.
- Produces: `enum FaceRegions` — `faceWidth(_ face:extent:) -> CGFloat`, `pixelRect(_ rect: NormalizedRect, in extent: CGRect) -> CGRect`, `skinMask(face:image:extent:tuning:strength: Double = 1) throws -> CIImage`(extent 크기, 0…strength), `maskBounds(face:extent:tuning:) -> CGRect`, `skinPolygon(face:extent:tuning:) -> [CGPoint]`, `protectedPolygons(face:extent:) -> [[CGPoint]]`, `blemishExclusionPolygons(face:extent:) -> [[CGPoint]]`, `cheekRects(face:extent:) -> [CGRect]`, `polygonMask(fill:cut:cutWidth:extent:tuning:) -> CIImage`, `contains(_ point: CGPoint, polygons: [[CGPoint]], dilation: CGFloat) -> Bool`. `final class SkinKernels` — `static let shared`, `chromaWeight(of:left:right:sigma:extent:) throws -> CIImage`. `RenderTuning.skinForeheadExtension`(0.2), `skinFeatureFeather`(0.05), `skinChromaSigma`(0.04), `skinMaskFeather`(0.015), `regionMaskMaxDimension`(512). 테스트 지원: `SyntheticFace`, `RenderingTestSupport.skinTexture(size:)`, `hardEllipse(center:radii:extent:)`, `PixelGrid`, `grid(_:)`.

래스터 방식 근거: Core Image에는 임의 다각형을 채우는 필터가 없고, 반평면 그라데이션 조합은 오목한 입술·눈썹을 표현하지 못한다. `CGContext`(8bit 회색, 색 관리 없음)에 얼굴 영역만 긴 변 `regionMaskMaxDimension`으로 그려 `CIImage(cgImage:options: [.colorSpace: NSNull()])`로 올리고 extent 좌표로 확대한다. CoreGraphics는 CoreImage가 들여오므로 import가 늘지 않는다. 마스크는 끝에 얼굴 폭 × `skinMaskFeather`로 흐리므로 512px 래스터의 계단은 보이지 않는다. 피부색 가중치는 볼 두 곳의 `CIAreaAverage`(무한 확장한 1픽셀 이미지)를 CIKL 색 커널에 표본으로 넘겨 렌더 중 픽셀 읽기가 없다.

- [ ] **Step 1: 테스트 지원 코드**

`RenderingTestSupport.swift` 맨 아래(enum 밖)에 추가:

```swift
/// CGImage 바이트를 Core Image 좌표(원점 왼쪽 아래)로 읽는다. 행 끝 여백(bytesPerRow)을 고려한다.
struct PixelGrid {
    let width: Int
    let height: Int
    let bytesPerRow: Int
    let data: [UInt8]

    init(_ image: CGImage) {
        width = image.width
        height = image.height
        bytesPerRow = image.bytesPerRow
        data = Array(image.dataProvider!.data! as Data)
    }

    /// CGImage는 맨 위 행부터 저장한다.
    func rgba(_ point: CGPoint) -> [UInt8] {
        let x = Int(point.x)
        let y = Int(point.y)
        let offset = (height - 1 - y) * bytesPerRow + x * 4
        return Array(data[offset..<(offset + 4)])
    }

    func red(_ point: CGPoint) -> UInt8 { rgba(point)[0] }
}

/// 512×512 합성 얼굴. 좌표는 Core Image 픽셀이고 원점은 왼쪽 아래다.
/// 윤곽(가로 반지름 172)은 피부 타원(140)보다 넓어 윤곽 안에 파란 배경이 들어간다.
struct SyntheticFace {
    static let size = 512
    static let skinCenter = CGPoint(x: 256, y: 240)
    static let skinRadii = CGSize(width: 140, height: 190)
    static let contourRadii = CGSize(width: 172, height: 190)
    static let leftEye = CGPoint(x: 200, y: 300)
    static let rightEye = CGPoint(x: 312, y: 300)
    static let eyeRadii = CGSize(width: 28, height: 14)
    static let leftBrow = CGRect(x: 168, y: 332, width: 64, height: 12)
    static let rightBrow = CGRect(x: 280, y: 332, width: 64, height: 12)
    static let mouth = CGPoint(x: 256, y: 140)
    static let mouthRadii = CGSize(width: 48, height: 20)
    static let innerMouthRadii = CGSize(width: 40, height: 8)
    static let nose = [CGPoint(x: 236, y: 190), CGPoint(x: 276, y: 190), CGPoint(x: 256, y: 250)]
    static let box = CGRect(x: 116, y: 50, width: 280, height: 300)
    /// 피부 위 잡티 다섯 개의 중심.
    static let blemishes = [
        CGPoint(x: 176, y: 224), CGPoint(x: 336, y: 224), CGPoint(x: 216, y: 372), CGPoint(x: 300, y: 376),
        CGPoint(x: 256, y: 84),
    ]
    /// 눈 바로 아래(보호 영역 안)의 잡티. 검출되면 안 된다.
    static let blemishNearEye = CGPoint(x: 200, y: 278)
    static let blemishRadius: CGFloat = 3.5
    static let cheek = CGPoint(x: 180, y: 200)
    static let forehead = CGPoint(x: 256, y: 380)
    static let backgroundInsideContour = CGPoint(x: 96, y: 240)
    static let outside = CGPoint(x: 20, y: 20)
    /// 잡티·특징에서 떨어진 볼 안쪽 정사각형. 대역 분산을 잰다.
    static let skinPatch = CGRect(x: 150, y: 190, width: 60, height: 60)

    let image: CIImage
    let face: FaceGeometry

    static var extent: CGRect { CGRect(x: 0, y: 0, width: size, height: size) }

    static func make(withBlemishes: Bool = false, landmarks: Bool = true) -> SyntheticFace {
        let backgroundColor = CIColor(red: 0.2, green: 0.35, blue: 0.75)
        var image = CIImage(color: backgroundColor).cropped(to: extent)
        let skinMask = RenderingTestSupport.hardEllipse(center: skinCenter, radii: skinRadii, extent: extent)
        image = RenderingTestSupport.skinTexture(size: size).applyingFilter(
            "CIBlendWithMask", parameters: [kCIInputBackgroundImageKey: image, kCIInputMaskImageKey: skinMask])
        let eyeColor = CIImage(color: CIColor(red: 0.12, green: 0.09, blue: 0.08))
        for eye in [leftEye, rightEye] {
            image = paint(eyeColor, center: eye, radii: eyeRadii, over: image)
        }
        let browColor = CIImage(color: CIColor(red: 0.25, green: 0.18, blue: 0.14))
        for brow in [leftBrow, rightBrow] {
            image = browColor.cropped(to: brow).composited(over: image)
        }
        let lipColor = CIImage(color: CIColor(red: 0.72, green: 0.28, blue: 0.32))
        image = paint(lipColor, center: mouth, radii: mouthRadii, over: image)
        if withBlemishes {
            // 피부보다 휘도 40% 낮고 Cr이 0.026 높다. 피부색 가중치(σ 0.04) 안이라 마스크에 남는다.
            let spotColor = CIImage(color: CIColor(red: 0.56, green: 0.32, blue: 0.27))
            let radii = CGSize(width: blemishRadius, height: blemishRadius)
            for center in blemishes + [blemishNearEye] {
                image = paint(spotColor, center: center, radii: radii, over: image)
            }
        }
        let face = landmarks ? geometry() : FaceGeometry(boundingBox: normalized(box))
        return SyntheticFace(image: image.cropped(to: extent), face: face)
    }

    private static func paint(_ color: CIImage, center: CGPoint, radii: CGSize, over image: CIImage) -> CIImage {
        let mask = RenderingTestSupport.hardEllipse(center: center, radii: radii, extent: extent)
        return color.applyingFilter(
            "CIBlendWithMask", parameters: [kCIInputBackgroundImageKey: image, kCIInputMaskImageKey: mask]
        ).cropped(to: extent)
    }

    private static func normalized(_ point: CGPoint) -> NormalizedPoint {
        NormalizedPoint(x: Double(point.x) / Double(size), y: Double(point.y) / Double(size))
    }

    private static func normalized(_ rect: CGRect) -> NormalizedRect {
        NormalizedRect(
            x: Double(rect.minX) / Double(size), y: Double(rect.minY) / Double(size),
            width: Double(rect.width) / Double(size), height: Double(rect.height) / Double(size))
    }

    private static func ellipse(_ center: CGPoint, _ radii: CGSize) -> [NormalizedPoint] {
        (0..<12).map { step in
            let angle = 2 * Double.pi * Double(step) / 12
            return normalized(
                CGPoint(
                    x: center.x + radii.width * CGFloat(cos(angle)), y: center.y + radii.height * CGFloat(sin(angle))))
        }
    }

    private static func corners(_ rect: CGRect) -> [NormalizedPoint] {
        [
            CGPoint(x: rect.minX, y: rect.minY), CGPoint(x: rect.maxX, y: rect.minY),
            CGPoint(x: rect.maxX, y: rect.maxY), CGPoint(x: rect.minX, y: rect.maxY),
        ].map(normalized)
    }

    /// Vision처럼 윤곽은 한쪽 관자놀이에서 턱을 지나 반대쪽까지 17점이다.
    private static func geometry() -> FaceGeometry {
        let contour = (0...16).map { step -> NormalizedPoint in
            let angle = Double.pi + Double.pi * Double(step) / 16
            return normalized(
                CGPoint(
                    x: skinCenter.x + contourRadii.width * CGFloat(cos(angle)),
                    y: skinCenter.y + contourRadii.height * CGFloat(sin(angle))))
        }
        return FaceGeometry(
            boundingBox: normalized(box),
            landmarks: [
                .faceContour: contour, .leftEye: ellipse(leftEye, eyeRadii), .rightEye: ellipse(rightEye, eyeRadii),
                .leftEyebrow: corners(leftBrow), .rightEyebrow: corners(rightBrow),
                .outerLips: ellipse(mouth, mouthRadii), .innerLips: ellipse(mouth, innerMouthRadii),
                .nose: nose.map(normalized), .leftPupil: [normalized(leftEye)], .rightPupil: [normalized(rightEye)],
            ])
    }
}
```

`CIColor(red:green:blue:)`는 sRGB 값이라 출력 바이트는 값 × 255다(잡티 빨강 143, 피부 빨강 181~222). 계획 작성 때 Xcode 27 Core Image로 확인했다.

`enum RenderingTestSupport` 안에 추가:

```swift
    static func grid(_ image: CIImage) throws -> PixelGrid {
        PixelGrid(try renderer.makeCGImage(image))
    }

    /// 가장자리 폭이 반지름의 2%인 거의 단단한 타원 마스크.
    static func hardEllipse(center: CGPoint, radii: CGSize, extent: CGRect) -> CIImage {
        let gradient = CIFilter(
            name: "CIRadialGradient",
            parameters: [
                "inputCenter": CIVector(x: 0, y: 0), "inputRadius0": 0.98, "inputRadius1": 1.0,
                "inputColor0": CIColor.white, "inputColor1": CIColor.black,
            ])!.outputImage!
        let transform = CGAffineTransform(a: radii.width, b: 0, c: 0, d: radii.height, tx: center.x, ty: center.y)
        return gradient.transformed(by: transform).cropped(to: extent)
    }

    /// 피부색 바탕에 모공(픽셀 단위 잡음 ±4%)과 얼룩(흐린 잡음으로 섞은 밝고 어두운 피부)을 넣는다.
    /// CIRandomGenerator는 늘 같은 무늬라 테스트가 결정적이다.
    static func skinTexture(size: Int) -> CIImage {
        let extent = CGRect(x: 0, y: 0, width: size, height: size)
        let gray = CIFilter(name: "CIRandomGenerator")!.outputImage!.applyingFilter(
            "CIColorMatrix",
            parameters: [
                "inputRVector": CIVector(x: 1, y: 0, z: 0, w: 0), "inputGVector": CIVector(x: 1, y: 0, z: 0, w: 0),
                "inputBVector": CIVector(x: 1, y: 0, z: 0, w: 0), "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 0),
                "inputBiasVector": CIVector(x: 0, y: 0, z: 0, w: 1),
            ])
        let blotch = gray.applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: 8])
            .applyingFilter(
                "CIColorMatrix",
                parameters: [
                    "inputRVector": CIVector(x: 30, y: 0, z: 0, w: 0), "inputGVector": CIVector(x: 0, y: 30, z: 0, w: 0),
                    "inputBVector": CIVector(x: 0, y: 0, z: 30, w: 0),
                    "inputBiasVector": CIVector(x: -14.5, y: -14.5, z: -14.5, w: 0),
                ]
            )
            .applyingFilter(
                "CIColorClamp",
                parameters: [
                    "inputMinComponents": CIVector(x: 0, y: 0, z: 0, w: 0),
                    "inputMaxComponents": CIVector(x: 1, y: 1, z: 1, w: 1),
                ])
        let light = CIImage(color: CIColor(red: 0.84, green: 0.66, blue: 0.56))
        let dark = CIImage(color: CIColor(red: 0.74, green: 0.56, blue: 0.46))
        let base = light.applyingFilter(
            "CIBlendWithMask", parameters: [kCIInputBackgroundImageKey: dark, kCIInputMaskImageKey: blotch])
        let bright = base.applyingFilter(
            "CIColorMatrix",
            parameters: [
                "inputRVector": CIVector(x: 1.04, y: 0, z: 0, w: 0), "inputGVector": CIVector(x: 0, y: 1.04, z: 0, w: 0),
                "inputBVector": CIVector(x: 0, y: 0, z: 1.04, w: 0),
            ])
        let dim = base.applyingFilter(
            "CIColorMatrix",
            parameters: [
                "inputRVector": CIVector(x: 0.96, y: 0, z: 0, w: 0), "inputGVector": CIVector(x: 0, y: 0.96, z: 0, w: 0),
                "inputBVector": CIVector(x: 0, y: 0, z: 0.96, w: 0),
            ])
        return bright.applyingFilter(
            "CIBlendWithMask", parameters: [kCIInputBackgroundImageKey: dim, kCIInputMaskImageKey: gray]
        ).cropped(to: extent)
    }
```

긴 줄은 lint에 맞게 줄바꿈한다(값은 그대로).

- [ ] **Step 2: 실패하는 테스트 작성**

`apple/Tests/MellowRenderingTests/FaceRegionsTests.swift`:

```swift
import CoreImage
import MellowShared
import XCTest

@testable import MellowRendering

final class FaceRegionsTests: XCTestCase {
    typealias Support = RenderingTestSupport

    private func maskGrid(_ synthetic: SyntheticFace) throws -> PixelGrid {
        let mask = try FaceRegions.skinMask(
            face: synthetic.face, image: synthetic.image, extent: synthetic.image.extent, tuning: RenderTuning())
        XCTAssertEqual(mask.extent, synthetic.image.extent)
        return try Support.grid(mask)
    }

    func testSkinMaskCoversCheeksAndForehead() throws {
        let grid = try maskGrid(SyntheticFace.make())
        XCTAssertGreaterThan(grid.red(SyntheticFace.cheek), 200)
        XCTAssertGreaterThan(grid.red(SyntheticFace.forehead), 200, "눈썹 위 이마 호까지 덮는다")
    }

    func testSkinMaskExcludesEyesBrowsAndLips() throws {
        let grid = try maskGrid(SyntheticFace.make())
        XCTAssertEqual(grid.red(SyntheticFace.leftEye), 0)
        XCTAssertEqual(grid.red(SyntheticFace.rightEye), 0)
        XCTAssertEqual(grid.red(CGPoint(x: SyntheticFace.leftBrow.midX, y: SyntheticFace.leftBrow.midY)), 0)
        XCTAssertEqual(grid.red(SyntheticFace.mouth), 0)
    }

    func testSkinMaskDropsNonSkinColorInsideContour() throws {
        let grid = try maskGrid(SyntheticFace.make())
        XCTAssertLessThan(grid.red(SyntheticFace.backgroundInsideContour), 8, "윤곽 안이어도 피부색이 아니면 빠진다")
    }

    func testSkinMaskIsZeroOutsideContour() throws {
        let grid = try maskGrid(SyntheticFace.make())
        XCTAssertEqual(grid.red(SyntheticFace.outside), 0)
        XCTAssertEqual(grid.red(CGPoint(x: 256, y: 470)), 0)
    }

    func testWithoutContourFallsBackToInsetEllipse() throws {
        let grid = try maskGrid(SyntheticFace.make(landmarks: false))
        XCTAssertGreaterThan(grid.red(CGPoint(x: 256, y: 200)), 200, "상자 가운데는 피부")
        XCTAssertLessThan(grid.red(CGPoint(x: 124, y: 200)), 20, "피부지만 안쪽으로 줄인 타원 밖")
    }

    func testDemoPortraitMaskCoversCheekAndNotPupil() throws {
        let url = try XCTUnwrap(
            Bundle.module.url(forResource: "demo-portrait", withExtension: "png", subdirectory: "Fixtures"))
        let image = try ImageLoader().load(url: url, maxDimension: 1200)
        let face = try XCTUnwrap(try VisionFaceAnalyzer().analyze(image).first)
        let grid = try Support.grid(
            FaceRegions.skinMask(face: face, image: image, extent: image.extent, tuning: RenderTuning()))
        let pupil = try XCTUnwrap(face.landmarks[.leftPupil]?.first)
        XCTAssertEqual(grid.red(CGPoint(x: pupil.x * image.extent.width, y: pupil.y * image.extent.height)), 0)
        let eye = try XCTUnwrap(face.bounds(of: .leftEye))
        let lips = try XCTUnwrap(face.bounds(of: .outerLips))
        let cheek = CGPoint(x: eye.midX * image.extent.width, y: (eye.minY + lips.maxY) / 2 * image.extent.height)
        XCTAssertGreaterThan(grid.red(cheek), 128, "실제 사진의 눈 아래 볼은 피부 마스크 안")
    }
}
```

- [ ] **Step 3: 실패 확인**

Run: `cd apple && swift test --filter FaceRegionsTests` → 컴파일 실패(`FaceRegions` 없음).

- [ ] **Step 4: 구현**

`RenderTuning.swift`의 `skinBlurMinimumRadius` 아래에 추가:

```swift
    /// 눈썹 위로 이마를 덮는 높이. 얼굴 상자 높이 비율. Vision 상자 위끝은 눈썹 근처라 20%면 이마 중간이고, 머리카락은 피부색 가중치가 뺀다.
    public var skinForeheadExtension: Double = 0.2
    /// 눈·눈썹·입술 보호 영역을 넓히는 폭. 얼굴 폭 비율. 마스크 흐림의 3σ(4.5%)보다 넓어야 눈 안쪽이 정확히 0이 된다.
    public var skinFeatureFeather: Double = 0.05
    /// 볼 평균과의 Cb·Cr 거리 기준(sRGB 감마 값). 이 안은 가중치 1, 두 배에서 0. 한 얼굴 안 피부 편차는 0.02 안팎이고 무채색 머리카락·배경은 0.06 이상 떨어진다.
    public var skinChromaSigma: Double = 0.04
    /// 피부 마스크를 마지막에 흐리는 반지름. 얼굴 폭 비율.
    public var skinMaskFeather: Double = 0.015
    /// 다각형 마스크를 그리는 비트맵의 긴 변. 마스크는 흐리므로 512면 48MP에서도 계단이 보이지 않는다.
    public var regionMaskMaxDimension: Int = 512
```

`apple/Sources/MellowRendering/Domain/SkinKernels.swift`:

```swift
import CoreImage
import MellowShared

/// 피부 보정의 CIKL 색 커널을 감싸는 유일한 자리. WarpKernel처럼 Metal로 바꿀 때 이 타입만 바꾼다.
final class SkinKernels: @unchecked Sendable {
    static let shared = SkinKernels()

    private let chroma: CIColorKernel?

    /// Cb·Cr 계수는 BT.601(sRGB 감마 값 기준)이다. 거리 t = d²/σ², 가중치 = clamp((4 − t)/3)이라 d ≤ σ면 1, d = 2σ면 0.
    private init() {
        chroma = CIColorKernel(
            source: """
                kernel vec4 skinChromaWeight(__sample pixel, __sample left, __sample right, float invSigmaSquared) {
                    vec3 cb = vec3(-0.168736, -0.331264, 0.5);
                    vec3 cr = vec3(0.5, -0.418688, -0.081312);
                    vec3 reference = (left.rgb + right.rgb) * 0.5;
                    vec2 d = vec2(dot(pixel.rgb - reference, cb), dot(pixel.rgb - reference, cr));
                    float t = dot(d, d) * invSigmaSquared;
                    float w = clamp((4.0 - t) / 3.0, 0.0, 1.0);
                    return vec4(w, w, w, 1.0);
                }
                """)
    }

    /// encoded는 sRGB 감마 값 이미지, left·right는 볼 평균을 무한 확장한 이미지. 결과는 회색 가중치.
    func chromaWeight(of encoded: CIImage, left: CIImage, right: CIImage, sigma: Double, extent: CGRect) throws
        -> CIImage
    {
        guard let chroma, sigma > 0 else { throw MellowError.renderFailed }
        let arguments: [Any] = [encoded, left, right, 1 / (sigma * sigma)]
        guard let weight = chroma.apply(extent: extent, arguments: arguments) else { throw MellowError.renderFailed }
        return weight
    }
}
```

`apple/Sources/MellowRendering/Domain/FaceRegions.swift`:

```swift
import CoreImage
import MellowShared

/// 얼굴 특징점에서 영역 마스크를 만드는 유일한 곳. 분할 모델로 바꿀 때 이 타입만 바꾼다.
/// 좌표는 extent 기준 픽셀이고 원점은 왼쪽 아래다.
enum FaceRegions {
    /// 이마 호를 그리는 구간 수.
    private static let foreheadArcSegments = 12
    /// 타원 다각형의 점 수.
    private static let ellipseSegments = 24
    /// 마스크 계산 영역의 여백. 흐림 반지름의 배수.
    private static let boundsPaddingInFeathers: CGFloat = 4
    /// 래스터 영역 여백(픽셀). 안티에일리어싱 가장자리를 담는다.
    private static let rasterPadding: CGFloat = 1
    /// 볼 표본 정사각형의 한 변. 눈 폭 대비.
    private static let cheekSampleScale: CGFloat = 0.6
    /// 다각형 하나가 되려면 필요한 점 수.
    private static let minimumPolygonPoints = 3

    /// 특징점이 없을 때 쓰는 부위 위치. 얼굴 상자 안의 비율이다.
    private enum FallbackFeature {
        static let leftEye = NormalizedRect(x: 0.15, y: 0.56, width: 0.28, height: 0.14)
        static let rightEye = NormalizedRect(x: 0.57, y: 0.56, width: 0.28, height: 0.14)
        static let mouth = NormalizedRect(x: 0.25, y: 0.18, width: 0.5, height: 0.18)
        /// 코 끝 높이.
        static let noseBottom = 0.35

        static func place(_ ratio: NormalizedRect, in box: NormalizedRect) -> NormalizedRect {
            NormalizedRect(
                x: box.minX + box.width * ratio.x, y: box.minY + box.height * ratio.y, width: box.width * ratio.width,
                height: box.height * ratio.height)
        }
    }

    static func faceWidth(_ face: FaceGeometry, extent: CGRect) -> CGFloat {
        CGFloat(face.boundingBox.width) * extent.width
    }

    static func pixelRect(_ rect: NormalizedRect, in extent: CGRect) -> CGRect {
        CGRect(
            x: extent.minX + CGFloat(rect.x) * extent.width, y: extent.minY + CGFloat(rect.y) * extent.height,
            width: CGFloat(rect.width) * extent.width, height: CGFloat(rect.height) * extent.height)
    }

    /// 0…strength 피부 가중치. 눈·눈썹·입술은 0, 피부색이 아닌 픽셀(머리카락·배경)은 0에 가깝다.
    /// 윤곽 다각형 + 이마 호 − 넓힌 보호 영역 → × 피부색 가중치 → 흐림 → × strength.
    static func skinMask(
        face: FaceGeometry, image: CIImage, extent: CGRect, tuning: RenderTuning, strength: Double = 1
    ) throws -> CIImage {
        let black = CIImage(color: .black).cropped(to: extent)
        let bounds = maskBounds(face: face, extent: extent, tuning: tuning)
        guard !bounds.isEmpty else { return black }
        let cutWidth = faceWidth(face, extent: extent) * CGFloat(tuning.skinFeatureFeather) * 2
        var mask = polygonMask(
            fill: [skinPolygon(face: face, extent: extent, tuning: tuning)],
            cut: protectedPolygons(face: face, extent: extent), cutWidth: cutWidth, extent: extent, tuning: tuning)
        let cheeks = cheekRects(face: face, extent: extent)
        if let left = cheeks.first, let right = cheeks.last {
            let encoded = image.applyingFilter("CILinearToSRGBToneCurve")
            let weight = try SkinKernels.shared.chromaWeight(
                of: encoded, left: average(encoded, in: left), right: average(encoded, in: right),
                sigma: tuning.skinChromaSigma, extent: extent)
            mask = mask.applyingFilter("CIMultiplyCompositing", parameters: [kCIInputBackgroundImageKey: weight])
        }
        var feathered = mask.clampedToExtent()
            .applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: featherRadius(face, extent, tuning)])
        if strength != 1 {
            feathered = feathered.applyingFilter(
                "CIColorMatrix",
                parameters: [
                    "inputRVector": CIVector(x: strength, y: 0, z: 0, w: 0),
                    "inputGVector": CIVector(x: 0, y: strength, z: 0, w: 0),
                    "inputBVector": CIVector(x: 0, y: 0, z: strength, w: 0),
                ])
        }
        return feathered.cropped(to: bounds).composited(over: black)
    }

    /// 마스크가 0이 아닐 수 있는 영역. 이 밖은 계산하지 않아도 된다.
    static func maskBounds(face: FaceGeometry, extent: CGRect, tuning: RenderTuning) -> CGRect {
        let polygon = skinPolygon(face: face, extent: extent, tuning: tuning)
        guard polygon.count >= minimumPolygonPoints else { return .null }
        let padding = featherRadius(face, extent, tuning) * boundsPaddingInFeathers
        return boundingRect(polygon).insetBy(dx: -padding, dy: -padding).intersection(extent).integral
    }

    /// 윤곽점 + 눈썹 위로 올린 이마 호. 윤곽점이 없으면 안쪽으로 줄인 상자 타원.
    static func skinPolygon(face: FaceGeometry, extent: CGRect, tuning: RenderTuning) -> [CGPoint] {
        guard let contour = landmarkPolygon(face, .faceContour, extent), let first = contour.first,
            let last = contour.last
        else { return fallbackSkinEllipse(face, extent, tuning) }
        let span = hypot(last.x - first.x, last.y - first.y)
        guard span > 0 else { return fallbackSkinEllipse(face, extent, tuning) }
        let unit = CGPoint(x: (last.x - first.x) / span, y: (last.y - first.y) / span)
        let mid = CGPoint(x: (first.x + last.x) / 2, y: (first.y + last.y) / 2)
        let upper = upperFeaturePoints(face, extent)
        var normal = CGPoint(x: -unit.y, y: unit.x)
        // 눈썹(없으면 눈, 그것도 없으면 상자 위끝) 쪽을 위로 본다.
        if dot(offset(centroid(upper), from: mid), normal) < 0 {
            normal = CGPoint(x: -normal.x, y: -normal.y)
        }
        let browRise = upper.map { dot(offset($0, from: mid), normal) }.max() ?? 0
        let forehead = CGFloat(face.boundingBox.height) * extent.height * CGFloat(tuning.skinForeheadExtension)
        let rise = max(0, browRise) + forehead
        // θ = 0이 last, θ = π가 first인 반타원. 양 끝점은 윤곽에 이미 있다.
        let arc = (1..<foreheadArcSegments).map { step -> CGPoint in
            let angle = Double.pi * Double(step) / Double(foreheadArcSegments)
            let along = span / 2 * CGFloat(cos(angle))
            let up = rise * CGFloat(sin(angle))
            return CGPoint(x: mid.x + unit.x * along + normal.x * up, y: mid.y + unit.y * along + normal.y * up)
        }
        return contour + arc
    }

    /// 눈·바깥 입술(특징점이 없으면 상자 비율 타원)과 눈썹.
    static func protectedPolygons(face: FaceGeometry, extent: CGRect) -> [[CGPoint]] {
        let box = face.boundingBox
        let required: [(FaceLandmark, NormalizedRect)] = [
            (.leftEye, FallbackFeature.leftEye), (.rightEye, FallbackFeature.rightEye),
            (.outerLips, FallbackFeature.mouth),
        ]
        var polygons = required.map { landmark, fallback in
            landmarkPolygon(face, landmark, extent)
                ?? ellipsePolygon(in: pixelRect(FallbackFeature.place(fallback, in: box), in: extent))
        }
        for landmark in [FaceLandmark.leftEyebrow, .rightEyebrow] {
            if let polygon = landmarkPolygon(face, landmark, extent) {
                polygons.append(polygon)
            }
        }
        return polygons
    }

    /// 자동 잡티에서 뺄 영역. 보호 영역에 코를 더한다(콧구멍은 어둡고 붉어 잡티로 잡힌다).
    static func blemishExclusionPolygons(face: FaceGeometry, extent: CGRect) -> [[CGPoint]] {
        var polygons = protectedPolygons(face: face, extent: extent)
        if let nose = landmarkPolygon(face, .nose, extent) {
            polygons.append(nose)
        }
        return polygons
    }

    /// 눈 아래·코 옆 볼 두 곳. 이미지 밖으로 나간 쪽은 뺀다.
    static func cheekRects(face: FaceGeometry, extent: CGRect) -> [CGRect] {
        let box = face.boundingBox
        let noseBottom = face.bounds(of: .nose)?.minY ?? (box.minY + box.height * FallbackFeature.noseBottom)
        let eyes: [(FaceLandmark, NormalizedRect)] = [
            (.leftEye, FallbackFeature.leftEye), (.rightEye, FallbackFeature.rightEye),
        ]
        return eyes.compactMap { landmark, fallback in
            let eye = face.bounds(of: landmark) ?? FallbackFeature.place(fallback, in: box)
            let center = CGPoint(
                x: extent.minX + CGFloat(eye.midX) * extent.width,
                y: extent.minY + CGFloat((eye.minY + noseBottom) / 2) * extent.height)
            let side = CGFloat(eye.width) * extent.width * cheekSampleScale
            let rect = CGRect(x: center.x - side / 2, y: center.y - side / 2, width: side, height: side)
                .intersection(extent).integral
            return rect.isEmpty ? nil : rect
        }
    }

    /// fill 다각형을 1, cut 다각형(경계를 cutWidth/2만큼 넓혀)을 0으로 그린 extent 크기 회색 마스크.
    /// 얼굴 영역만 긴 변 regionMaskMaxDimension 비트맵에 그리고 확대한다.
    static func polygonMask(
        fill: [[CGPoint]], cut: [[CGPoint]], cutWidth: CGFloat, extent: CGRect, tuning: RenderTuning
    ) -> CIImage {
        let black = CIImage(color: .black).cropped(to: extent)
        let filled = fill.filter { $0.count >= minimumPolygonPoints }
        guard !filled.isEmpty else { return black }
        let region = boundingRect(filled.flatMap { $0 }).insetBy(dx: -rasterPadding, dy: -rasterPadding)
            .intersection(extent).integral
        guard !region.isEmpty else { return black }
        let scale = min(1, CGFloat(tuning.regionMaskMaxDimension) / max(region.width, region.height))
        let width = max(1, Int((region.width * scale).rounded(.up)))
        let height = max(1, Int((region.height * scale).rounded(.up)))
        guard
            let context = CGContext(
                data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue)
        else { return black }
        context.setFillColor(gray: 0, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        // CGContext 원점도 왼쪽 아래라 y를 뒤집지 않는다. 점 p는 scale × (p − region.origin)에 그려진다.
        context.scaleBy(x: scale, y: scale)
        context.translateBy(x: -region.minX, y: -region.minY)
        context.setFillColor(gray: 1, alpha: 1)
        for polygon in filled {
            context.addLines(between: polygon)
            context.closePath()
        }
        context.fillPath()
        context.setFillColor(gray: 0, alpha: 1)
        context.setStrokeColor(gray: 0, alpha: 1)
        context.setLineWidth(cutWidth)
        context.setLineJoin(.round)
        for polygon in cut where polygon.count >= minimumPolygonPoints {
            context.addLines(between: polygon)
            context.closePath()
            context.drawPath(using: .fillStroke)
        }
        guard let raster = context.makeImage() else { return black }
        let placement = CGAffineTransform(a: 1 / scale, b: 0, c: 0, d: 1 / scale, tx: region.minX, ty: region.minY)
        return CIImage(cgImage: raster, options: [.colorSpace: NSNull()]).transformed(by: placement)
            .composited(over: black).cropped(to: extent)
    }

    /// 점이 다각형 안이거나 경계에서 dilation 이내인지.
    static func contains(_ point: CGPoint, polygons: [[CGPoint]], dilation: CGFloat) -> Bool {
        polygons.contains { polygon in
            guard polygon.count >= minimumPolygonPoints else { return false }
            let path = CGMutablePath()
            path.addLines(between: polygon)
            path.closeSubpath()
            if path.contains(point) {
                return true
            }
            guard dilation > 0 else { return false }
            let stroked = path.copy(strokingWithWidth: dilation * 2, lineCap: .round, lineJoin: .round, miterLimit: 1)
            return stroked.contains(point)
        }
    }

    private static func featherRadius(_ face: FaceGeometry, _ extent: CGRect, _ tuning: RenderTuning) -> CGFloat {
        max(CGFloat(tuning.skinBlurMinimumRadius), faceWidth(face, extent: extent) * CGFloat(tuning.skinMaskFeather))
    }

    private static func average(_ image: CIImage, in rect: CGRect) -> CIImage {
        image.applyingFilter("CIAreaAverage", parameters: [kCIInputExtentKey: CIVector(cgRect: rect)])
            .clampedToExtent()
    }

    private static func landmarkPolygon(_ face: FaceGeometry, _ landmark: FaceLandmark, _ extent: CGRect)
        -> [CGPoint]?
    {
        guard let points = face.landmarks[landmark], points.count >= minimumPolygonPoints else { return nil }
        return points.map { CGPoint(x: extent.minX + $0.x * extent.width, y: extent.minY + $0.y * extent.height) }
    }

    private static func upperFeaturePoints(_ face: FaceGeometry, _ extent: CGRect) -> [CGPoint] {
        let brows = [FaceLandmark.leftEyebrow, .rightEyebrow].compactMap { landmarkPolygon(face, $0, extent) }
        if !brows.isEmpty {
            return brows.flatMap { $0 }
        }
        let eyes = [FaceLandmark.leftEye, .rightEye].compactMap { landmarkPolygon(face, $0, extent) }
        if !eyes.isEmpty {
            return eyes.flatMap { $0 }
        }
        let box = pixelRect(face.boundingBox, in: extent)
        return [CGPoint(x: box.midX, y: box.maxY)]
    }

    private static func fallbackSkinEllipse(_ face: FaceGeometry, _ extent: CGRect, _ tuning: RenderTuning)
        -> [CGPoint]
    {
        let box = pixelRect(face.boundingBox, in: extent)
        let inset = box.insetBy(
            dx: box.width * CGFloat(tuning.skinFaceInsetX), dy: box.height * CGFloat(tuning.skinFaceInsetY))
        return ellipsePolygon(in: inset)
    }

    private static func ellipsePolygon(in rect: CGRect) -> [CGPoint] {
        (0..<ellipseSegments).map { step in
            let angle = 2 * Double.pi * Double(step) / Double(ellipseSegments)
            return CGPoint(
                x: rect.midX + rect.width / 2 * CGFloat(cos(angle)),
                y: rect.midY + rect.height / 2 * CGFloat(sin(angle)))
        }
    }

    private static func boundingRect(_ points: [CGPoint]) -> CGRect {
        guard let first = points.first else { return .null }
        var rect = CGRect(origin: first, size: .zero)
        for point in points.dropFirst() {
            rect = rect.union(CGRect(origin: point, size: .zero))
        }
        return rect
    }

    private static func centroid(_ points: [CGPoint]) -> CGPoint {
        let count = CGFloat(max(1, points.count))
        let sum = points.reduce(CGPoint.zero) { CGPoint(x: $0.x + $1.x, y: $0.y + $1.y) }
        return CGPoint(x: sum.x / count, y: sum.y / count)
    }

    private static func offset(_ point: CGPoint, from origin: CGPoint) -> CGPoint {
        CGPoint(x: point.x - origin.x, y: point.y - origin.y)
    }

    private static func dot(_ a: CGPoint, _ b: CGPoint) -> CGFloat {
        a.x * b.x + a.y * b.y
    }
}
```

- [ ] **Step 5: 통과 확인**

Run: `cd apple && swift test --filter FaceRegionsTests` → 6 PASS. 전체 `swift test` → 153개 PASS(Rendering 62). lint 출력 없음. `./scripts/verify-modules.sh` → `✓ module dependencies and imports match docs/architecture/modules.md`.

`testWithoutContourFallsBackToInsetEllipse`의 (124, 200)이 20을 넘으면 마스크 흐림이 예상보다 넓은 것이다. 이때 상수를 바꾸지 말고 `skinMaskFeather` 반지름과 해당 점의 거리(14px)를 보고서에 적은 뒤 점을 (118, 200)으로 옮긴다(여전히 피부 타원 안).

- [ ] **Step 6: 커밋**

```bash
git add apple/Sources/MellowRendering apple/Tests/MellowRenderingTests
git commit -m "feat(rendering): 얼굴 윤곽 다각형과 피부색 가중치로 피부 마스크 추가

윤곽점과 이마 호로 다각형을 그리고 눈·눈썹·입술을 넓혀 뺀 뒤 볼 평균과의
Cb·Cr 거리로 머리카락·배경을 걸러낸다. 마스크는 FaceRegions 한 곳에서만 만든다.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 4: FrequencySeparation — 세 대역 분리와 중간 대역 감쇠

**Files:**
- Create: `apple/Sources/MellowRendering/Domain/FrequencySeparation.swift`
- Modify: `apple/Sources/MellowRendering/Domain/SkinKernels.swift` (`bandMix`)
- Modify: `apple/Sources/MellowRendering/API/RenderTuning.swift` (대역 상수)
- Modify: `apple/Tests/MellowRenderingTests/RenderingTestSupport.swift` (`bandVariances`, `luma`, `variance`)
- Test: `apple/Tests/MellowRenderingTests/FrequencySeparationTests.swift`

**Interfaces:**
- Consumes: `SkinKernels.shared`(Task 3), `RenderingTestSupport.skinTexture(size:)`.
- Produces: `FrequencySeparation.radii(faceWidth: CGFloat, tuning:) -> (fine: Double, mid: Double)`, `blurred(_ image: CIImage, radius: Double) -> CIImage`(무한 extent), `smoothed(_ image: CIImage, bounds: CGRect, faceWidth: CGFloat, smoothing: Double, tuning:) throws -> CIImage`(smoothing ≤ 0이면 입력 그대로, 아니면 extent가 bounds). `SkinKernels.bandMix(image:fineBlur:midBlur:keep:extent:) throws -> CIImage`. `RenderTuning.fineBandFraction`(0.006), `midBandFraction`(0.04), `midReductionMax`(0.85). 테스트 지원 `bandVariances(_:in:fineRadius:midRadius:) throws -> (fine: Double, mid: Double)`.

- [ ] **Step 1: 실패하는 테스트 작성**

`RenderingTestSupport` 안에 추가:

```swift
    /// rect 안 휘도(선형 sRGB)의 대역별 분산. fine = 원본 − blur(r1), mid = blur(r1) − blur(r2).
    static func bandVariances(_ image: CIImage, in rect: CGRect, fineRadius: Double, midRadius: Double) throws
        -> (fine: Double, mid: Double)
    {
        let original = try luma(image.cropped(to: rect))
        let fineBlur = try luma(FrequencySeparation.blurred(image, radius: fineRadius).cropped(to: rect))
        let midBlur = try luma(FrequencySeparation.blurred(image, radius: midRadius).cropped(to: rect))
        let fine = zip(original, fineBlur).map { $0 - $1 }
        let mid = zip(fineBlur, midBlur).map { $0 - $1 }
        return (variance(fine), variance(mid))
    }

    static func luma(_ image: CIImage) throws -> [Double] {
        let pixels = try renderer.readPixels(image)
        return stride(from: 0, to: pixels.count, by: 4).map { index in
            0.2126 * Double(pixels[index]) + 0.7152 * Double(pixels[index + 1]) + 0.0722 * Double(pixels[index + 2])
        }
    }

    static func variance(_ values: [Double]) -> Double {
        guard !values.isEmpty else { return 0 }
        let mean = values.reduce(0, +) / Double(values.count)
        return values.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / Double(values.count)
    }
```

`apple/Tests/MellowRenderingTests/FrequencySeparationTests.swift`:

```swift
import CoreImage
import MellowShared
import XCTest

@testable import MellowRendering

final class FrequencySeparationTests: XCTestCase {
    typealias Support = RenderingTestSupport

    /// 합성 얼굴과 같은 얼굴 폭. 미리보기 1600px 사진의 작은 얼굴 정도다.
    private let faceWidth: CGFloat = 280
    private let patch = CGRect(x: 156, y: 156, width: 200, height: 200)

    func testRadiiScaleWithFaceWidthAndHaveFloor() {
        let tuning = RenderTuning()
        let radii = FrequencySeparation.radii(faceWidth: faceWidth, tuning: tuning)
        XCTAssertEqual(radii.fine, Double(faceWidth) * tuning.fineBandFraction, accuracy: 1e-9)
        XCTAssertEqual(radii.mid, Double(faceWidth) * tuning.midBandFraction, accuracy: 1e-9)
        let tiny = FrequencySeparation.radii(faceWidth: 10, tuning: tuning)
        XCTAssertEqual(tiny.fine, tuning.skinBlurMinimumRadius)
        XCTAssertGreaterThanOrEqual(tiny.mid, tiny.fine)
    }

    func testZeroSmoothingReturnsInput() throws {
        let image = Support.skinTexture(size: 64)
        let output = try FrequencySeparation.smoothed(
            image, bounds: image.extent, faceWidth: faceWidth, smoothing: 0, tuning: RenderTuning())
        XCTAssertEqual(try Support.bytes(output), try Support.bytes(image))
    }

    func testSmoothingCutsMidBandAndKeepsFineBand() throws {
        let tuning = RenderTuning()
        let image = Support.skinTexture(size: SyntheticFace.size)
        let radii = FrequencySeparation.radii(faceWidth: faceWidth, tuning: tuning)
        let output = try FrequencySeparation.smoothed(
            image, bounds: image.extent, faceWidth: faceWidth, smoothing: 1, tuning: tuning)
        XCTAssertEqual(output.extent, image.extent)
        let before = try Support.bandVariances(image, in: patch, fineRadius: radii.fine, midRadius: radii.mid)
        let after = try Support.bandVariances(output, in: patch, fineRadius: radii.fine, midRadius: radii.mid)
        XCTAssertLessThan(after.mid, before.mid * 0.5, "중간 대역(얼룩) 분산이 절반 아래로 준다")
        XCTAssertEqual(after.fine / before.fine, 1, accuracy: 0.1, "모공 대역 분산은 ±10% 안")
    }
}
```

- [ ] **Step 2: 실패 확인**

Run: `cd apple && swift test --filter FrequencySeparationTests` → 컴파일 실패.

- [ ] **Step 3: 구현**

`RenderTuning.swift`의 Task 3 상수 아래에 추가:

```swift
    /// 모공 대역의 위쪽 경계 반지름. 얼굴 폭 비율. 모공은 얼굴 폭의 0.5% 안팎이다(400px 얼굴에서 2.4px).
    public var fineBandFraction: Double = 0.006
    /// 얼룩·잔주름 대역의 위쪽 경계 반지름. 얼굴 폭 비율. 이보다 큰 명암(광대 그림자 등)은 남긴다.
    public var midBandFraction: Double = 0.04
    /// 피부 보정 1에서 중간 대역을 줄이는 비율. 15%를 남겨 플라스틱 느낌을 피한다.
    public var midReductionMax: Double = 0.85
```

`SkinKernels.swift`: 프로퍼티 `private let bands: CIColorKernel?`를 추가하고 `init`에서 컴파일한 뒤 메서드를 추가한다.

```swift
        bands = CIColorKernel(
            source: """
                kernel vec4 bandMix(__sample image, __sample fineBlur, __sample midBlur, float keep) {
                    vec3 mid = fineBlur.rgb - midBlur.rgb;
                    vec3 fine = image.rgb - fineBlur.rgb;
                    return vec4(midBlur.rgb + mid * keep + fine, image.a);
                }
                """)
```

```swift
    /// low + mid × keep + fine. low = blur(r2), mid = blur(r1) − blur(r2), fine = 원본 − blur(r1).
    func bandMix(image: CIImage, fineBlur: CIImage, midBlur: CIImage, keep: Double, extent: CGRect) throws -> CIImage {
        guard let bands else { throw MellowError.renderFailed }
        let arguments: [Any] = [image, fineBlur, midBlur, keep]
        guard let mixed = bands.apply(extent: extent, arguments: arguments) else { throw MellowError.renderFailed }
        return mixed
    }
```

`apple/Sources/MellowRendering/Domain/FrequencySeparation.swift`:

```swift
import CoreImage
import MellowShared

/// 피부를 낮은·중간·모공 세 대역으로 나눠 중간 대역(얼룩·잔주름)만 줄인다. 모공 대역은 그대로 둔다.
enum FrequencySeparation {
    /// 얼굴 폭에 비례한 두 반지름. fine은 모공 대역의 위쪽, mid는 중간 대역의 위쪽 경계.
    static func radii(faceWidth: CGFloat, tuning: RenderTuning) -> (fine: Double, mid: Double) {
        let fine = max(tuning.skinBlurMinimumRadius, Double(faceWidth) * tuning.fineBandFraction)
        let mid = max(fine, Double(faceWidth) * tuning.midBandFraction)
        return (fine, mid)
    }

    /// 가장자리를 늘려 흐린다. extent는 무한이다.
    static func blurred(_ image: CIImage, radius: Double) -> CIImage {
        image.clampedToExtent().applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: radius])
    }

    /// low + mid × (1 − smoothing × midReductionMax) + fine. bounds 밖은 계산하지 않는다(투명).
    static func smoothed(
        _ image: CIImage, bounds: CGRect, faceWidth: CGFloat, smoothing: Double, tuning: RenderTuning
    ) throws -> CIImage {
        let amount = min(1, max(0, smoothing))
        guard amount > 0, !bounds.isEmpty else { return image }
        // 지역 상수 이름을 radii로 하면 같은 이름의 정적 메서드를 가려 컴파일되지 않는다.
        let bandRadii = Self.radii(faceWidth: faceWidth, tuning: tuning)
        return try SkinKernels.shared.bandMix(
            image: image, fineBlur: blurred(image, radius: bandRadii.fine),
            midBlur: blurred(image, radius: bandRadii.mid), keep: 1 - amount * tuning.midReductionMax, extent: bounds)
    }
}
```

- [ ] **Step 4: 통과 확인**

Run: `cd apple && swift test --filter FrequencySeparationTests` → 3 PASS. 전체 `swift test` → 156개 PASS(Rendering 65). lint 출력 없음.

`testSmoothingCutsMidBandAndKeepsFineBand`가 모공 대역 ±10%를 넘으면 재분해할 때 r1 근처 주파수가 겹치는 것이다(계획 작성 때 추정치는 약 −4%). 이때 `fineBandFraction`을 바꾸지 말고 측정한 비율을 보고서에 적어 리뷰에서 정한다.

- [ ] **Step 5: 커밋**

```bash
git add apple/Sources/MellowRendering apple/Tests/MellowRenderingTests
git commit -m "feat(rendering): 모공 대역을 남기는 세 대역 주파수 분리 추가

얼굴 폭에 비례한 두 반지름으로 대역을 나누고 중간 대역만 줄인다.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 5: BlemishDetector — 사진 준비 때 자동 잡티 찾기

**Files:**
- Create: `apple/Sources/MellowShared/API/BlemishSpot.swift`
- Create: `apple/Sources/MellowRendering/Domain/BlemishDetector.swift`
- Modify: `apple/Sources/MellowRendering/API/RenderStage.swift` (`RenderContext.blemishes`·`targetBlemishes`)
- Modify: `apple/Sources/MellowRendering/API/PhotoPipeline.swift` (`Entry.blemishes`, `prepare`, `preview`, `renderOriginal`, `preparedBlemishes`)
- Modify: `apple/Sources/MellowRendering/API/RenderTuning.swift` (잡티 상수)
- Modify: `apple/Sources/MellowRendering/API/Renderer.swift` (`readPixels` 주석)
- Modify: `apple/Tests/MellowRenderingTests/RenderingTestSupport.swift` (`writePNG`)
- Test: `apple/Tests/MellowRenderingTests/BlemishDetectorTests.swift`, `apple/Tests/MellowRenderingTests/PhotoPipelineTests.swift`

**Interfaces:**
- Consumes: `FaceRegions.skinMask`·`faceWidth`·`pixelRect`·`blemishExclusionPolygons`·`contains`(Task 3), `FrequencySeparation.blurred`(Task 4), `Renderer.readPixels`, `SyntheticFace`.
- Produces: `public struct BlemishSpot: Equatable, Sendable { x, y, radius: Double; faceIndex: Int }`(Shared). `struct BlemishDetector { init(tuning:renderer:); func detect(image: CIImage, faces: [FaceGeometry]) throws -> [BlemishSpot] }`. `RenderContext.init(…, skipsCrop: Bool = false, blemishes: [BlemishSpot] = [])`, `RenderContext.blemishes`, `targetBlemishes`. `PhotoPipeline.preparedBlemishes(_ id: PhotoID) -> [BlemishSpot]`(internal). `RenderTuning.blemishAnalysisMaxDimension`(512), `blemishMinRadiusFraction`(0.005), `blemishMaxRadiusFraction`(0.02), `blemishSurroundScale`(3), `blemishLumaDrop`(0.06), `blemishRednessMin`(0.012), `blemishMaskThreshold`(0.5), `blemishMaxPerFace`(40). 테스트 지원 `RenderingTestSupport.writePNG(_:name:) throws -> URL`.

- [ ] **Step 1: 실패하는 테스트 작성**

`RenderingTestSupport` 안에 추가(파일 맨 위에 `import ImageIO`):

```swift
    static func writePNG(_ image: CIImage, name: String = "image") throws -> URL {
        let url = try temporaryDirectory().appendingPathComponent("\(name).png")
        let cg = try renderer.makeCGImage(image)
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil) else {
            throw MellowError.cannotWriteToFolder
        }
        CGImageDestinationAddImage(destination, cg, nil)
        guard CGImageDestinationFinalize(destination) else { throw MellowError.cannotWriteToFolder }
        return url
    }
```

`apple/Tests/MellowRenderingTests/BlemishDetectorTests.swift`:

```swift
import CoreImage
import MellowShared
import XCTest

@testable import MellowRendering

final class BlemishDetectorTests: XCTestCase {
    typealias Support = RenderingTestSupport

    private let size = CGFloat(SyntheticFace.size)

    private func detector(_ tuning: RenderTuning = RenderTuning()) -> BlemishDetector {
        BlemishDetector(tuning: tuning, renderer: Support.renderer)
    }

    private func pixelCenter(_ spot: BlemishSpot) -> CGPoint {
        CGPoint(x: spot.x * size, y: spot.y * size)
    }

    func testFindsPlantedSpotsAndIgnoresSpotNextToEye() throws {
        let synthetic = SyntheticFace.make(withBlemishes: true)
        let spots = try detector().detect(image: synthetic.image, faces: [synthetic.face])
        XCTAssertEqual(spots.count, SyntheticFace.blemishes.count)
        for planted in SyntheticFace.blemishes {
            XCTAssertTrue(
                spots.contains { hypot(pixelCenter($0).x - planted.x, pixelCenter($0).y - planted.y) < 2 },
                "\(planted) 누락")
        }
        let near = SyntheticFace.blemishNearEye
        XCTAssertFalse(spots.contains { hypot(pixelCenter($0).x - near.x, pixelCenter($0).y - near.y) < 6 })
        for spot in spots {
            XCTAssertEqual(spot.faceIndex, 0)
            XCTAssertEqual(Double(spot.radius * size), Double(SyntheticFace.blemishRadius), accuracy: 1.5)
        }
    }

    func testCleanSkinAndNoFacesYieldNothing() throws {
        let clean = SyntheticFace.make()
        XCTAssertEqual(try detector().detect(image: clean.image, faces: [clean.face]), [])
        let spotted = SyntheticFace.make(withBlemishes: true)
        XCTAssertEqual(try detector().detect(image: spotted.image, faces: []), [])
    }

    func testSpotsPerFaceAreCapped() throws {
        XCTAssertEqual(RenderTuning().blemishMaxPerFace, 40)
        var tuning = RenderTuning()
        tuning.blemishMaxPerFace = 3
        let synthetic = SyntheticFace.make(withBlemishes: true)
        XCTAssertEqual(try detector(tuning).detect(image: synthetic.image, faces: [synthetic.face]).count, 3)
    }

    func testDemoPortraitStaysWithinCapAndOutsideEyesAndLips() throws {
        let url = try XCTUnwrap(
            Bundle.module.url(forResource: "demo-portrait", withExtension: "png", subdirectory: "Fixtures"))
        let image = try ImageLoader().load(url: url, maxDimension: RenderTuning().previewMaxDimension)
        let face = try XCTUnwrap(try VisionFaceAnalyzer().analyze(image).first)
        let spots = try detector().detect(image: image, faces: [face])
        XCTAssertLessThanOrEqual(spots.count, RenderTuning().blemishMaxPerFace)
        let protected = FaceRegions.protectedPolygons(face: face, extent: image.extent)
        for spot in spots {
            let point = CGPoint(x: spot.x * image.extent.width, y: spot.y * image.extent.height)
            XCTAssertFalse(FaceRegions.contains(point, polygons: protected, dilation: 0), "눈·눈썹·입술 안의 잡티 \(point)")
        }
    }
}
```

`PhotoPipelineTests.swift`에 추가:

```swift
    func testPrepareStoresBlemishesOnlyWhenFacesExist() async throws {
        let synthetic = SyntheticFace.make(withBlemishes: true)
        let url = try Support.writePNG(synthetic.image, name: "face")
        let withFace = PhotoPipeline(
            analyzer: StubFaceAnalyzer(result: .success([synthetic.face])), tuning: RenderTuning())
        let id = PhotoID()
        _ = try await withFace.prepare(id, at: url)
        let spots = await withFace.preparedBlemishes(id)
        XCTAssertEqual(spots.count, SyntheticFace.blemishes.count)
        let noFace = PhotoPipeline(analyzer: StubFaceAnalyzer(result: .success([])), tuning: RenderTuning())
        let other = PhotoID()
        _ = try await noFace.prepare(other, at: url)
        let none = await noFace.preparedBlemishes(other)
        XCTAssertTrue(none.isEmpty)
    }

    func testRenderOriginalRefusesAutoBlemishOnlyWhenAnalysisFailed() async throws {
        let url = try writeSolidPNG()
        let id = PhotoID()
        let pipeline = PhotoPipeline(
            analyzer: StubFaceAnalyzer(result: .failure(.faceAnalysisUnavailable(reason: "test"))),
            tuning: RenderTuning())
        _ = try await pipeline.prepare(id, at: url)
        var recipe = EditRecipe()
        recipe.portrait.skin.autoBlemish = true
        do {
            _ = try await pipeline.renderOriginal(id, at: url, recipe: recipe, maxDimension: nil)
            XCTFail("자동 잡티만 켠 저장도 조용히 빠지면 안 된다")
        } catch {
            XCTAssertEqual(error as? MellowError, .faceAnalysisUnavailable(reason: "test"))
        }
    }
```

- [ ] **Step 2: 실패 확인**

Run: `cd apple && swift test --filter BlemishDetectorTests` → 컴파일 실패(`BlemishDetector` 없음).

- [ ] **Step 3: 구현**

`apple/Sources/MellowShared/API/BlemishSpot.swift`:

```swift
import Foundation

/// 사진 준비 때 찾은 자동 잡티. 영속화하지 않고 준비할 때마다 다시 계산한다.
public struct BlemishSpot: Equatable, Sendable {
    /// 정규화 중심. 원점은 왼쪽 아래.
    public var x: Double
    public var y: Double
    /// 짧은 변 대비 반지름. RetouchSpot.radius와 같은 단위.
    public var radius: Double
    /// 왼쪽부터 센 얼굴 인덱스. 대상 얼굴 선택에 쓴다.
    public var faceIndex: Int

    public init(x: Double, y: Double, radius: Double, faceIndex: Int) {
        self.x = x
        self.y = y
        self.radius = radius
        self.faceIndex = faceIndex
    }
}
```

`RenderTuning.swift`의 Task 4 상수 아래에 추가:

```swift
    /// 잡티를 찾을 때 얼굴 영역을 줄이는 긴 변. readPixels 세 번이 각각 1M float 이하가 된다.
    public var blemishAnalysisMaxDimension: Int = 512
    /// 잡티 반지름의 하한·상한. 얼굴 폭 비율(스펙 0.5%~2%). 여드름 3~5mm는 얼굴 폭 140mm의 1~1.8%다.
    public var blemishMinRadiusFraction: Double = 0.005
    public var blemishMaxRadiusFraction: Double = 0.02
    /// 주변 밝기를 재는 흐림 반지름. 잡티 최대 반지름의 배수.
    public var blemishSurroundScale: Double = 3
    /// 주변보다 이만큼(상대값) 어두워야 잡티 후보. 모공 잡음은 흐린 뒤 ±1% 안팎이다.
    public var blemishLumaDrop: Double = 0.06
    /// 주변보다 Cr이 이만큼 높아야 잡티 후보. 무채색 그림자·얼룩은 0에 가깝다.
    public var blemishRednessMin: Double = 0.012
    /// 피부 마스크(세기 1)가 이 값 이상인 곳만 본다.
    public var blemishMaskThreshold: Double = 0.5
    /// 얼굴당 잡티 수 상한(스펙).
    public var blemishMaxPerFace: Int = 40
```

`Renderer.readPixels` 주석의 마지막 문장을 "히스토그램·평균·잡티 분석처럼 긴 변 512px 이하 이미지에만 쓴다."로 바꾼다.

`apple/Sources/MellowRendering/Domain/BlemishDetector.swift`:

```swift
import CoreImage
import Foundation
import MellowShared

/// 미리보기에서 자동 잡티를 찾는다. 피부 마스크 안에서 주변보다 어둡고 붉은 작은 점이다(DoG).
/// 얼굴 영역만 긴 변 blemishAnalysisMaxDimension으로 줄여 픽셀을 읽는다.
struct BlemishDetector {
    let tuning: RenderTuning
    let renderer: Renderer

    /// BT.601 휘도·Cr 계수. sRGB 감마 값에 쓴다.
    private static let lumaWeights: [Double] = [0.299, 0.587, 0.114]
    private static let redChromaWeights: [Double] = [0.5, -0.418688, -0.081312]

    private struct Candidate {
        var center: CGPoint
        var radius: CGFloat
        var score: Double
    }

    /// 얼굴 순서대로, 얼굴마다 점수(어두운 정도의 합)가 높은 순서로 최대 blemishMaxPerFace개.
    func detect(image: CIImage, faces: [FaceGeometry]) throws -> [BlemishSpot] {
        var spots: [BlemishSpot] = []
        for (index, face) in faces.enumerated() {
            spots += try detect(image: image, face: face, faceIndex: index)
        }
        return spots
    }

    private func detect(image: CIImage, face: FaceGeometry, faceIndex: Int) throws -> [BlemishSpot] {
        let extent = image.extent
        let faceRect = FaceRegions.pixelRect(face.boundingBox, in: extent).intersection(extent).integral
        guard !faceRect.isEmpty else { return [] }
        let scale = min(1, CGFloat(tuning.blemishAnalysisMaxDimension) / max(faceRect.width, faceRect.height))
        let width = Int((faceRect.width * scale).rounded(.down))
        let height = Int((faceRect.height * scale).rounded(.down))
        guard width > 0, height > 0 else { return [] }
        let small = CGRect(x: 0, y: 0, width: width, height: height)
        let toSmall = CGAffineTransform(
            a: scale, b: 0, c: 0, d: scale, tx: -faceRect.minX * scale, ty: -faceRect.minY * scale)
        let faceWidth = FaceRegions.faceWidth(face, extent: extent)
        let smallFaceWidth = Double(faceWidth * scale)
        let encoded = image.applyingFilter("CILinearToSRGBToneCurve").transformed(by: toSmall)
        let centerRadius = max(tuning.skinBlurMinimumRadius, smallFaceWidth * tuning.blemishMinRadiusFraction)
        let surroundRadius = smallFaceWidth * tuning.blemishMaxRadiusFraction * tuning.blemishSurroundScale
        let center = try renderer.readPixels(
            FrequencySeparation.blurred(encoded, radius: centerRadius).cropped(to: small))
        let surround = try renderer.readPixels(
            FrequencySeparation.blurred(encoded, radius: surroundRadius).cropped(to: small))
        let maskImage = try FaceRegions.skinMask(face: face, image: image, extent: extent, tuning: tuning)
        let mask = try renderer.readPixels(maskImage.transformed(by: toSmall).cropped(to: small))
        var candidate = [Bool](repeating: false, count: width * height)
        var drop = [Double](repeating: 0, count: width * height)
        for index in candidate.indices {
            let offset = index * 4
            let surroundLuma = Self.weighted(surround, offset, Self.lumaWeights)
            guard Double(mask[offset]) >= tuning.blemishMaskThreshold, surroundLuma > 0 else { continue }
            let relativeDrop = (surroundLuma - Self.weighted(center, offset, Self.lumaWeights)) / surroundLuma
            let centerRed = Self.weighted(center, offset, Self.redChromaWeights)
            let redness = centerRed - Self.weighted(surround, offset, Self.redChromaWeights)
            if relativeDrop >= tuning.blemishLumaDrop && redness >= tuning.blemishRednessMin {
                candidate[index] = true
                drop[index] = relativeDrop
            }
        }
        let exclusions = FaceRegions.blemishExclusionPolygons(face: face, extent: extent)
        let dilation = faceWidth * CGFloat(tuning.skinFeatureFeather)
        let minRadius = faceWidth * CGFloat(tuning.blemishMinRadiusFraction)
        let maxRadius = faceWidth * CGFloat(tuning.blemishMaxRadiusFraction)
        var found: [Candidate] = []
        for members in Self.components(of: candidate, width: width, height: height) {
            var sumX = 0.0
            var sumY = 0.0
            var score = 0.0
            for index in members {
                sumX += Double(index % width) + 0.5
                // readPixels는 맨 위 행부터다. Core Image y는 아래에서 센다.
                sumY += Double(height - 1 - index / width) + 0.5
                score += drop[index]
            }
            let count = Double(members.count)
            let radius = CGFloat((count / Double.pi).squareRoot()) / scale
            guard radius >= minRadius, radius <= maxRadius else { continue }
            let point = CGPoint(
                x: faceRect.minX + CGFloat(sumX / count) / scale, y: faceRect.minY + CGFloat(sumY / count) / scale)
            guard !FaceRegions.contains(point, polygons: exclusions, dilation: dilation) else { continue }
            found.append(Candidate(center: point, radius: radius, score: score))
        }
        let shortSide = min(extent.width, extent.height)
        return found.sorted { $0.score > $1.score }.prefix(tuning.blemishMaxPerFace).map { candidate in
            BlemishSpot(
                x: Double((candidate.center.x - extent.minX) / extent.width),
                y: Double((candidate.center.y - extent.minY) / extent.height),
                radius: Double(candidate.radius / shortSide), faceIndex: faceIndex)
        }
    }

    private static func weighted(_ pixels: [Float], _ offset: Int, _ weights: [Double]) -> Double {
        Double(pixels[offset]) * weights[0] + Double(pixels[offset + 1]) * weights[1]
            + Double(pixels[offset + 2]) * weights[2]
    }

    /// 4방향 연결 영역. 각 영역은 픽셀 인덱스 목록(행 우선, 맨 위 행부터).
    static func components(of candidate: [Bool], width: Int, height: Int) -> [[Int]] {
        var visited = [Bool](repeating: false, count: candidate.count)
        var result: [[Int]] = []
        for start in candidate.indices where candidate[start] && !visited[start] {
            var stack = [start]
            visited[start] = true
            var members: [Int] = []
            while let index = stack.popLast() {
                members.append(index)
                let x = index % width
                let y = index / width
                let neighbors = [(x - 1, y), (x + 1, y), (x, y - 1), (x, y + 1)]
                for (nx, ny) in neighbors where nx >= 0 && nx < width && ny >= 0 && ny < height {
                    let neighbor = ny * width + nx
                    if candidate[neighbor] && !visited[neighbor] {
                        visited[neighbor] = true
                        stack.append(neighbor)
                    }
                }
            }
            result.append(members)
        }
        return result
    }
}
```

`RenderStage.swift`의 `RenderContext`: 프로퍼티 두 개를 `skipsCrop` 아래에 추가하고 `init`을 교체한다.

```swift
    /// 사진 준비 때 찾은 자동 잡티. 영속화하지 않는다.
    public let blemishes: [BlemishSpot]
    /// recipe.portrait.targetFace를 적용한 잡티.
    public let targetBlemishes: [BlemishSpot]

    public init(
        extent: CGRect, recipe: EditRecipe, faces: [FaceGeometry], tuning: RenderTuning,
        lookCatalog: LookCatalog = .empty, skipsCrop: Bool = false, blemishes: [BlemishSpot] = []
    ) {
        self.extent = extent
        self.recipe = recipe
        self.faces = faces
        self.tuning = tuning
        self.lookCatalog = lookCatalog
        self.skipsCrop = skipsCrop
        self.blemishes = blemishes
        if let index = recipe.portrait.targetFace {
            targetFaces = faces.indices.contains(index) ? [faces[index]] : []
            targetBlemishes = blemishes.filter { $0.faceIndex == index }
        } else {
            targetFaces = faces
            targetBlemishes = blemishes
        }
    }
```

`PhotoPipeline.swift`:
- `Entry`에 `var blemishes: [BlemishSpot]`를 `faceAnalysisFailure` 아래에 추가.
- `cachedPreviewIDs` 아래에 테스트용 접근자:

```swift
    /// 테스트용. 준비 때 찾은 잡티.
    func preparedBlemishes(_ id: PhotoID) -> [BlemishSpot] {
        entries[id]?.blemishes ?? []
    }
```

- `prepare`에서 `let thumbnail = …` 앞에 `let blemishes = detectBlemishes(in: preview, faces: faces)`를 넣고 `Entry(faces: faces, faceAnalysisFailure: failure, blemishes: blemishes, thumbnail: CIImage(cgImage: thumbnail))`로 만든다.
- `preview`의 `RenderContext(…, skipsCrop: showsUncropped, blemishes: entry.blemishes)`.
- `renderOriginal`·`render`: `render(url:recipe:faces:blemishes:maxDimension:)`로 바꾸고 준비 안 된 경로는 `blemishes: []`, 준비된 경로는 `entry.blemishes`를 넘긴다. `render` 안의 `RenderContext`에 `blemishes: blemishes`.
- 새 private 메서드:

```swift
    /// 잡티 분석이 실패해도 사진 준비는 막지 않는다. 자동 잡티만 동작하지 않는다.
    private func detectBlemishes(in image: CIImage, faces: [FaceGeometry]) -> [BlemishSpot] {
        guard !faces.isEmpty else { return [] }
        return (try? BlemishDetector(tuning: tuning, renderer: renderer).detect(image: image, faces: faces)) ?? []
    }
```

- [ ] **Step 4: 통과 확인**

Run: `cd apple && swift test --filter 'BlemishDetectorTests|PhotoPipelineTests'` → PASS. 전체 `swift test` → 162개 PASS(Shared 37 · Rendering 71). lint 출력 없음. `./scripts/verify-modules.sh` 통과.

`testFindsPlantedSpotsAndIgnoresSpotNextToEye`에서 개수가 다르면 먼저 각 후보의 반지름·어두운 정도·Cr 차이를 출력해 원인을 보고서에 적는다. 반지름 상한(5.6px)에 걸리면 `SyntheticFace.blemishRadius`를 3.0으로 줄이고, 임계값은 바꾸지 않는다.

- [ ] **Step 5: 커밋**

```bash
git add apple/Sources/MellowShared/API/BlemishSpot.swift apple/Sources/MellowRendering apple/Tests/MellowRenderingTests
git commit -m "feat(rendering): 사진 준비 때 피부 마스크 안 잡티를 찾는 BlemishDetector 추가

주변보다 어둡고 붉은 작은 연결 영역을 얼굴당 최대 40개 찾고 눈·눈썹·입술·코는 뺀다.
결과는 RenderContext.blemishes로 넘기고 저장하지 않는다.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 6: SkinStage 재작성 — 자동 잡티 복구 후 마스크 안 주파수 분리

**Files:**
- Modify: `apple/Sources/MellowRendering/Domain/SkinStage.swift` (전체 교체)
- Modify: `apple/Sources/MellowRendering/Domain/FaceReshapeStage.swift` (양방향)
- Modify: `apple/Sources/MellowRendering/API/RenderTuning.swift` (복구 상수 추가, 옛 피부 상수 삭제)
- Test: `apple/Tests/MellowRenderingTests/SkinStageTests.swift`, `apple/Tests/MellowRenderingTests/RenderPipelineTests.swift`, `apple/Tests/MellowRenderingTests/PhotoPipelineTests.swift`

**Interfaces:**
- Consumes: `FaceRegions.skinMask`·`maskBounds`·`faceWidth`(Task 3), `FrequencySeparation.smoothed`(Task 4), `RenderContext.targetBlemishes`(Task 5), `LocalEditStage.applySpot`, `MaskBuilder.blend`.
- Produces: `SkinStage`(이름 `"skin"` 그대로), `static func healSpot(for blemish: BlemishSpot, in context: RenderContext) -> RetouchSpot`. `RenderTuning.blemishHealRadiusScale`(1.8), `blemishSourceOffset`(2.5). 삭제: `skinFeatureInset`, `skinNoiseLevel`, `skinNoiseSharpness`, `skinBlurRadiusFraction`. `FaceReshapeStage`는 `face.width` 음수면 좁게, 양수면 넓게(C에서 대체).

- [ ] **Step 1: 실패하는 테스트 작성**

`apple/Tests/MellowRenderingTests/SkinStageTests.swift`:

```swift
import CoreImage
import MellowShared
import XCTest

@testable import MellowRendering

final class SkinStageTests: XCTestCase {
    typealias Support = RenderingTestSupport

    private let size = Double(SyntheticFace.size)

    private func render(
        _ synthetic: SyntheticFace, skin: SkinAdjustments, blemishes: [BlemishSpot] = [], faces: [FaceGeometry]? = nil,
        targetFace: Int? = nil
    ) throws -> CIImage {
        var recipe = EditRecipe()
        recipe.portrait.skin = skin
        recipe.portrait.targetFace = targetFace
        let context = RenderContext(
            extent: synthetic.image.extent, recipe: recipe, faces: faces ?? [synthetic.face], tuning: RenderTuning(),
            blemishes: blemishes)
        return try SkinStage().apply(synthetic.image, in: context)
    }

    private func spot(_ center: CGPoint, face: Int = 0) -> BlemishSpot {
        BlemishSpot(
            x: Double(center.x) / size, y: Double(center.y) / size, radius: Double(SyntheticFace.blemishRadius) / size,
            faceIndex: face)
    }

    func testNoSmoothingAndNoAutoBlemishIsIdentity() throws {
        let synthetic = SyntheticFace.make(withBlemishes: true)
        let output = try render(synthetic, skin: SkinAdjustments())
        XCTAssertEqual(try Support.bytes(output), try Support.bytes(synthetic.image))
    }

    func testSmoothingLeavesEyesAndNonSkinUntouchedAndChangesCheeks() throws {
        let synthetic = SyntheticFace.make()
        let before = try Support.grid(synthetic.image)
        let after = try Support.grid(render(synthetic, skin: SkinAdjustments(smoothing: 1)))
        for point in [
            SyntheticFace.leftEye, SyntheticFace.rightEye, SyntheticFace.mouth, SyntheticFace.backgroundInsideContour,
            SyntheticFace.outside,
        ] {
            XCTAssertEqual(after.rgba(point), before.rgba(point), "\(point)")
        }
        let patch = SyntheticFace.skinPatch
        var changed = 0
        for y in Int(patch.minY)..<Int(patch.maxY) {
            for x in Int(patch.minX)..<Int(patch.maxX) {
                let point = CGPoint(x: x, y: y)
                if after.rgba(point) != before.rgba(point) {
                    changed += 1
                }
            }
        }
        XCTAssertGreaterThan(changed, Int(patch.width * patch.height) / 2, "볼 픽셀 대부분이 바뀐다")
    }

    func testSmoothingCutsMidBandAndKeepsPores() throws {
        let synthetic = SyntheticFace.make()
        let output = try render(synthetic, skin: SkinAdjustments(smoothing: 1))
        let radii = FrequencySeparation.radii(
            faceWidth: FaceRegions.faceWidth(synthetic.face, extent: synthetic.image.extent), tuning: RenderTuning())
        let patch = SyntheticFace.skinPatch
        let before = try Support.bandVariances(synthetic.image, in: patch, fineRadius: radii.fine, midRadius: radii.mid)
        let after = try Support.bandVariances(output, in: patch, fineRadius: radii.fine, midRadius: radii.mid)
        XCTAssertLessThan(after.mid, before.mid * 0.6, "마스크 안 중간 대역이 준다")
        XCTAssertEqual(after.fine / before.fine, 1, accuracy: 0.1, "모공 대역은 ±10% 안")
    }

    func testAutoBlemishHealsPlantedSpots() throws {
        let synthetic = SyntheticFace.make(withBlemishes: true)
        let before = try Support.grid(synthetic.image)
        let planted = SyntheticFace.blemishes.map { spot($0) }
        let after = try Support.grid(render(synthetic, skin: SkinAdjustments(autoBlemish: true), blemishes: planted))
        for center in SyntheticFace.blemishes {
            XCTAssertGreaterThanOrEqual(Int(after.red(center)), Int(before.red(center)) + 20, "\(center)의 잡티가 밝아진다")
        }
    }

    func testAutoBlemishHealsOnlyTargetFace() throws {
        let synthetic = SyntheticFace.make(withBlemishes: true)
        let first = SyntheticFace.blemishes[0]
        let second = SyntheticFace.blemishes[1]
        let blemishes = [spot(first, face: 0), spot(second, face: 1)]
        let before = try Support.grid(synthetic.image)
        let output = try render(
            synthetic, skin: SkinAdjustments(autoBlemish: true), blemishes: blemishes,
            faces: [synthetic.face, synthetic.face], targetFace: 0)
        let after = try Support.grid(output)
        XCTAssertGreaterThanOrEqual(Int(after.red(first)), Int(before.red(first)) + 20)
        XCTAssertEqual(after.rgba(second), before.rgba(second), "대상이 아닌 얼굴의 잡티는 그대로")
    }
}
```

`RenderPipelineTests.swift`:
- `testTargetFaceLimitsPortraitStagesToOneFace`의 `let input = Support.gradient()`를 `let input = Support.skinTexture(size: 256)`으로 바꾼다(그라데이션은 중간 대역이 없어 주파수 분리가 바꾸지 않는다).
- 다음 테스트를 추가:

```swift
    func testFaceWidthWorksInBothDirections() throws {
        let input = Support.gradient()
        let face = FaceGeometry(boundingBox: NormalizedRect(x: 0.15, y: 0.05, width: 0.7, height: 0.9))
        var narrow = EditRecipe()
        narrow.portrait.face.width = -1
        var wide = EditRecipe()
        wide.portrait.face.width = 1
        let narrowBytes = try Support.bytes(Support.render(input, recipe: narrow, faces: [face]))
        let wideBytes = try Support.bytes(Support.render(input, recipe: wide, faces: [face]))
        XCTAssertNotEqual(narrowBytes, try Support.bytes(input))
        XCTAssertNotEqual(wideBytes, try Support.bytes(input))
        XCTAssertNotEqual(narrowBytes, wideBytes)
    }
```

`PhotoPipelineTests.swift`에 추가:

```swift
    func testPreviewHealsDetectedBlemishes() async throws {
        let synthetic = SyntheticFace.make(withBlemishes: true)
        let url = try Support.writePNG(synthetic.image, name: "face")
        let pipeline = PhotoPipeline(
            analyzer: StubFaceAnalyzer(result: .success([synthetic.face])), tuning: RenderTuning())
        let id = PhotoID()
        _ = try await pipeline.prepare(id, at: url)
        let plainImage = try await pipeline.preview(id, recipe: EditRecipe())
        var recipe = EditRecipe()
        recipe.portrait.skin.autoBlemish = true
        let healedImage = try await pipeline.preview(id, recipe: recipe)
        let plain = PixelGrid(plainImage)
        let healed = PixelGrid(healedImage)
        let center = SyntheticFace.blemishes[0]
        XCTAssertGreaterThanOrEqual(Int(healed.red(center)), Int(plain.red(center)) + 20)
    }
```

- [ ] **Step 2: 실패 확인**

Run: `cd apple && swift test --filter 'SkinStageTests|RenderPipelineTests'` → `SkinStageTests`의 eye·band·blemish 테스트와 `testFaceWidthWorksInBothDirections`가 실패(옛 단계는 잡티를 모르고 넓히기를 하지 않음).

- [ ] **Step 3: 구현**

`RenderTuning.swift`: `skinFeatureInset`, `skinNoiseLevel`, `skinNoiseSharpness`, `skinBlurRadiusFraction` 네 줄을 지우고 Task 5 상수 아래에 추가:

```swift
    /// 잡티를 덮는 복제 원의 반지름 배수. applySpot 마스크는 반지름 65%까지만 완전히 복사하므로 1/0.65보다 커야 한다.
    public var blemishHealRadiusScale: Double = 1.8
    /// 복제 원본을 복제 반지름의 이 배수만큼 얼굴 가운데 쪽 옆 피부에서 가져온다. 2 이상이면 원이 겹치지 않는다.
    public var blemishSourceOffset: Double = 2.5
```

`SkinStage.swift` 전체:

```swift
import CoreImage
import MellowShared

/// 자동 잡티를 지운 뒤 피부 마스크 안에서 주파수 분리로 얼룩만 줄인다. 모공 질감은 남긴다.
struct SkinStage: RenderStage {
    let name = "skin"

    func apply(_ image: CIImage, in context: RenderContext) throws -> CIImage {
        let skin = context.recipe.portrait.skin
        guard skin.hasEffect, !context.targetFaces.isEmpty else { return image }
        let extent = context.extent
        let tuning = context.tuning
        var result = image
        if skin.autoBlemish {
            for blemish in context.targetBlemishes {
                let heal = Self.healSpot(for: blemish, in: context)
                result = LocalEditStage.applySpot(heal, to: result, context: context)
            }
        }
        guard skin.smoothing > 0 else { return result.cropped(to: extent) }
        for face in context.targetFaces {
            let bounds = FaceRegions.maskBounds(face: face, extent: extent, tuning: tuning)
            guard !bounds.isEmpty else { continue }
            let mask = try FaceRegions.skinMask(
                face: face, image: result, extent: extent, tuning: tuning, strength: tuning.skinMaskMaxStrength)
            let smooth = try FrequencySeparation.smoothed(
                result, bounds: bounds, faceWidth: FaceRegions.faceWidth(face, extent: extent),
                smoothing: skin.smoothing, tuning: tuning)
            result = MaskBuilder.blend(smooth, over: result, mask: mask).cropped(to: extent)
        }
        return result
    }

    /// 잡티를 덮는 복제 원. 원본은 얼굴 가운데 쪽 옆 피부다. 수동 잡티와 같은 패치 복구를 쓴다.
    static func healSpot(for blemish: BlemishSpot, in context: RenderContext) -> RetouchSpot {
        let tuning = context.tuning
        let radius = blemish.radius * tuning.blemishHealRadiusScale
        let faces = context.faces
        let knownFace = faces.indices.contains(blemish.faceIndex)
        let faceCenterX = knownFace ? faces[blemish.faceIndex].boundingBox.midX : blemish.x
        let direction: Double = faceCenterX >= blemish.x ? 1 : -1
        let shift = radius * Double(context.shortSide) * tuning.blemishSourceOffset / Double(context.extent.width)
        return RetouchSpot(
            x: blemish.x, y: blemish.y, sourceX: blemish.x + direction * shift, sourceY: blemish.y, radius: radius)
    }
}
```

`FaceReshapeStage.swift`: 주석과 두 줄을 바꾼다.

```swift
/// 얼굴 양옆을 미는 얼굴 폭 변형. width 음수면 좁게, 양수면 넓게. C 단계에서 ShapeWarpStage로 대체된다.
```

```swift
        let amount = -context.recipe.portrait.face.width
        guard amount != 0, !context.targetFaces.isEmpty else { return image }
```

`slimStrokes`의 `let shift = min(1, amount) * …` → `let shift = max(-1, min(1, amount)) * box.width * tuning.faceSlimShiftFraction`.

- [ ] **Step 4: 통과 확인**

Run: `cd apple && swift test` → 169개 PASS(Shared 37 · Rendering 78 · Library 30 · Export 4 · Editing 20). `RenderPipelineTests.testStageOrderMatters`의 이름 배열 `["skin", "faceReshape", "localEdit", "geometry", "color", "detail", "look"]`은 바꾸지 않고 통과해야 한다. lint 출력 없음. `grep -rn "skinNoise\|skinFeatureInset\|skinBlurRadiusFraction" apple` → 결과 없음.

- [ ] **Step 5: 커밋**

```bash
git add apple/Sources/MellowRendering apple/Tests/MellowRenderingTests
git commit -m "feat(rendering): 피부 단계를 자동 잡티 복구와 주파수 분리 보정으로 재작성

잡티는 수동 잡티와 같은 패치 복구로 지우고, 피부 마스크 안에서 중간 대역만 줄여
모공 질감을 남긴다. 기존 얼굴 폭 변형은 양방향으로 동작한다.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 7: 앱 — 뷰티 도구(피부·얼굴 탭)와 B 시나리오

**Files:**
- Create: `apple/MellowPhoto/Application/BeautyTab.swift`
- Create: `apple/MellowPhoto/Features/Editor/BeautyPanel.swift`
- Delete: `apple/MellowPhoto/Features/Editor/PortraitPanel.swift`
- Modify: `apple/MellowPhoto/Application/EditorTool.swift`, `apple/MellowPhoto/Application/AppModel.swift` (`beautyTab`), `apple/MellowPhoto/Application/AppModel+Editing.swift` (`touch` 분기), `apple/MellowPhoto/Application/UserMessage.swift`
- Modify: `apple/MellowPhoto/Features/Editor/ToolStrip.swift`, `apple/MellowPhoto/Features/Editor/EditorScene.swift`, `apple/MellowPhoto/Features/Shared/AdjustmentSlider.swift`, `apple/MellowPhoto/Features/Shared/Theme.swift`
- Modify: `apple/MellowPhoto.xcodeproj` (xcodegen 재생성)
- Test: `apple/MellowPhotoTests/AppModelTests.swift`, `apple/MellowPhotoTests/EditorScenarioTests.swift`

**Interfaces:**
- Consumes: `EditChange.skinSmoothing`·`autoBlemish`·`faceShape`, `EditingPolicy.unitRange`·`faceShapeRange`(Task 2), `AppModel.selectTool`·`autoEnhance`.
- Produces: `EditorTool.beauty`(`portrait` 제거, 순서 look·crop·adjust·beauty·retouch·warp), `enum BeautyTab { skin, face }`, `AppModel.beautyTab`, `AdjustmentSlider(title:value:range:snapsToZero:change:)`, `Theme.bipolarSnapWidth`(0.05), `UserMessage.toolBeauty` 등. D가 `BeautyTab.features`(눈·입)를, D·E·F가 `EditorTool.background`·`body`·`makeup`을 더한다.

- [ ] **Step 1: 실패하는 테스트 작성**

`AppModelTests.swift`에 추가:

```swift
    func testBeautyToolEditsSkinOneUndoStepEach() async throws {
        let staged = try TestSupport.solidPNG(in: root)
        let model = TestSupport.makeModel(
            root: root, importer: FakeImporter(staged: [.success(StagedPhoto(url: staged, displayName: nil))]))
        try await importOne(model, staged)
        model.selectTool(.beauty)
        XCTAssertEqual(model.beautyTab, .skin)
        model.beginSliderEdit()
        model.edit(.skinSmoothing(0.4))
        model.edit(.skinSmoothing(0.5))
        model.endSliderEdit()
        model.edit(.autoBlemish(true))
        XCTAssertEqual(model.currentRecipe.portrait.skin, SkinAdjustments(smoothing: 0.5, autoBlemish: true))
        model.undo()
        XCTAssertEqual(model.currentRecipe.portrait.skin, SkinAdjustments(smoothing: 0.5))
        model.undo()
        XCTAssertTrue(model.currentRecipe.isDefault)
    }

    func testAutoEnhanceWithFaceTurnsOnAutoBlemishAndKeepsFaceWidth() async throws {
        let staged = try TestSupport.solidPNG(in: root)
        let face = FaceGeometry(boundingBox: NormalizedRect(x: 0.2, y: 0.2, width: 0.6, height: 0.6))
        let model = TestSupport.makeModel(
            root: root, analyzer: StubFaceAnalyzer(result: .success([face])),
            importer: FakeImporter(staged: [.success(StagedPhoto(url: staged, displayName: nil))]))
        try await importOne(model, staged)
        model.edit(.faceShape(.width, -0.4))
        await model.autoEnhance()
        XCTAssertEqual(
            model.currentRecipe.portrait.skin, SkinAdjustments(smoothing: RenderTuning().autoSkinSmoothing, autoBlemish: true))
        XCTAssertEqual(model.currentRecipe.portrait.face.width, -0.4, "자동 보정은 얼굴형을 건드리지 않는다")
    }

    func testBeautyTabSurvivesToolSwitch() {
        let model = TestSupport.makeModel(root: root)
        model.selectTool(.beauty)
        model.beautyTab = .face
        model.selectTool(.adjust)
        model.selectTool(.beauty)
        XCTAssertEqual(model.beautyTab, .face)
    }
```

`EditorScenarioTests.swift`에 추가:

```swift
    /// 공용 픽스처의 얼굴 위치를 어림한 스텁 얼굴. 특징점이 없어 피부 마스크는 타원으로 폴백한다.
    private static let demoFace = FaceGeometry(boundingBox: NormalizedRect(x: 0.33, y: 0.36, width: 0.38, height: 0.4))

    func testBeautySkinAndFaceWidthThenExportSucceeds() async throws {
        let model = TestSupport.makeModel(
            root: root, analyzer: StubFaceAnalyzer(result: .success([Self.demoFace])),
            importer: FakeImporter(passesThroughFileURLs: true))
        await model.importFromFiles([try demoPortraitCopy()])
        try await waitUntil { model.isReady && model.preview != nil }
        let plain = try XCTUnwrap(model.preview)

        model.selectTool(.beauty)
        model.beginSliderEdit()
        model.edit(.skinSmoothing(0.5))
        model.endSliderEdit()
        model.edit(.autoBlemish(true))
        model.beautyTab = .face
        model.beginSliderEdit()
        model.edit(.faceShape(.width, -0.5))
        model.endSliderEdit()
        try await waitUntil { !model.isRendering }

        let recipe = model.currentRecipe
        XCTAssertEqual(recipe.portrait.skin, SkinAdjustments(smoothing: 0.5, autoBlemish: true))
        XCTAssertEqual(recipe.portrait.face.width, -0.5, accuracy: 1e-9)
        let edited = try XCTUnwrap(model.preview)
        XCTAssertNotEqual(
            Array(edited.dataProvider!.data! as Data), Array(plain.dataProvider!.data! as Data), "미리보기가 바뀌었다")
        let size = try await exportedPixelSize(model)
        XCTAssertEqual(size.width, size.height, "정사각형 원본이 그대로 저장된다")
    }
```

- [ ] **Step 2: 실패 확인**

Run: `cd apple && xcodegen generate && cd .. && xcodebuild -project apple/MellowPhoto.xcodeproj -scheme MellowPhoto -derivedDataPath apple/build -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO build-for-testing 2>&1 | grep -c "error:"` → 0보다 큼(`beauty`·`beautyTab` 없음).

- [ ] **Step 3: 구현**

`apple/MellowPhoto/Application/BeautyTab.swift`:

```swift
/// 뷰티 도구의 하위 탭. 눈·입 탭은 D 단계에서 추가한다.
enum BeautyTab: CaseIterable, Identifiable {
    case skin
    case face

    var id: Self { self }

    var title: String {
        switch self {
        case .skin: return UserMessage.beautyTabSkin
        case .face: return UserMessage.beautyTabFace
        }
    }
}
```

`EditorTool.swift`: `case portrait` → `case beauty`, `title`의 `.portrait: return UserMessage.toolPortrait` → `.beauty: return UserMessage.toolBeauty`, `symbol`의 `.portrait` → `.beauty`(`"face.smiling"` 그대로).

`AppModel.swift`: `var tool: EditorTool = .look` 아래에

```swift
    /// 뷰티 도구에서 마지막으로 본 탭. 도구를 바꿔도 유지한다.
    var beautyTab: BeautyTab = .skin
```

`AppModel+Editing.swift` `touch`의 `case .look, .crop, .adjust, .portrait:` → `case .look, .crop, .adjust, .beauty:`.

`UserMessage.swift`: `static let toolPortrait = "인물"`을 지우고 도구 이름 묶음 아래에 추가:

```swift
    static let toolBeauty = "뷰티"
    static let beautyTabSkin = "피부"
    static let beautyTabFace = "얼굴"
    static let beautyTabsLabel = "뷰티 항목"
    static let skinSmoothing = "피부 보정"
    static let autoBlemish = "자동 잡티"
    static let faceWidth = "얼굴 폭"
    static let skinHint = "피부 보정은 모공 질감을 남기고 얼룩만 고르게 합니다. 자동 잡티는 사진을 준비할 때 찾은 작은 잡티를 지웁니다."
    static let faceHint = "얼굴 형태를 먼저 조정한 뒤 잡티를 보정해 주세요."
    static let faceAnalysisUnavailableTitle = "자동 얼굴 분석을 사용할 수 없어요"
    static let noFaceDetected = "감지된 얼굴이 없어요"
    static let noFaceHint = "정면에 가까운 사진을 선택하거나 잡티·변형 도구를 직접 사용해 주세요."
    static let allFaces = "모든 얼굴"

    static func faceCount(_ count: Int) -> String {
        "얼굴 \(count)명"
    }

    static func faceOrdinal(_ number: Int) -> String {
        "왼쪽부터 \(number)번째"
    }
```

(두 함수는 기존 함수 묶음 안에 둔다.)

`Theme.swift`에 추가:

```swift
    /// 가운데 0인 양방향 슬라이더가 0으로 붙는 폭.
    static let bipolarSnapWidth = 0.05
```

`AdjustmentSlider.swift`: `let range` 아래에 `var snapsToZero = false`를 넣고 Slider 바인딩의 setter를 `set: { model.edit(change(snapped($0))) }`로 바꾸고 메서드를 추가:

```swift
    /// 양방향 슬라이더는 0 근처에서 0으로 붙는다.
    private func snapped(_ newValue: Double) -> Double {
        snapsToZero && abs(newValue) < Theme.bipolarSnapWidth ? 0 : newValue
    }
```

`apple/MellowPhoto/Features/Editor/BeautyPanel.swift`:

```swift
import MellowEditing
import MellowShared
import SwiftUI

/// 뷰티 도구. 얼굴 선택은 탭 위에 두고, 탭마다 슬라이더를 보여준다.
struct BeautyPanel: View {
    @Environment(AppModel.self) private var model

    /// 얼굴 선택 피커에서 "모든 얼굴"을 뜻하는 태그.
    private static let allFacesTag = -1

    var body: some View {
        @Bindable var model = model
        let recipe = model.currentRecipe
        if let failure = model.selectedInfo?.faceAnalysisFailure {
            Label(UserMessage.faceAnalysisUnavailableTitle, systemImage: "exclamationmark.triangle")
            Text(UserMessage.text(for: failure)).font(.caption).foregroundStyle(.secondary)
        } else if model.faces.isEmpty {
            Label(UserMessage.noFaceDetected, systemImage: "person.crop.rectangle.badge.questionmark")
            Text(UserMessage.noFaceHint).font(.caption).foregroundStyle(.secondary)
        } else {
            Picker(
                UserMessage.faceCount(model.faces.count),
                selection: Binding(
                    get: { recipe.portrait.targetFace ?? Self.allFacesTag },
                    set: { model.edit(.targetFace($0 == Self.allFacesTag ? nil : $0)) })
            ) {
                Text(UserMessage.allFaces).tag(Self.allFacesTag)
                ForEach(model.faces.indices, id: \.self) { Text(UserMessage.faceOrdinal($0 + 1)).tag($0) }
            }
            .disabled(model.isGeometryLocked)
            Picker(UserMessage.beautyTabsLabel, selection: $model.beautyTab) {
                ForEach(BeautyTab.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            switch model.beautyTab {
            case .skin: skinControls(recipe.portrait.skin)
            case .face: faceControls(recipe.portrait.face)
            }
        }
    }

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
    }

    @ViewBuilder
    private func faceControls(_ face: FaceShapeAdjustments) -> some View {
        AdjustmentSlider(
            title: UserMessage.faceWidth, value: face.width, range: EditingPolicy.faceShapeRange(.width),
            snapsToZero: true
        ) { .faceShape(.width, $0) }
        .disabled(model.isGeometryLocked)
        Text(model.isGeometryLocked ? UserMessage.geometryLocked : UserMessage.faceHint)
            .font(.caption).foregroundStyle(.secondary)
    }
}
```

`PortraitPanel.swift`를 지운다(`git rm`). `ToolStrip.swift`의 `ForEach([EditorTool.crop, .adjust, .portrait, .retouch, .warp])` → `.beauty`. `EditorScene.swift` `toolPanel`의 `case .portrait: PortraitPanel()` → `case .beauty: BeautyPanel()`.

- [ ] **Step 4: 통과 확인**

Run: `cd apple && xcodegen generate`. Mac 앱 테스트 → `Executed 51 tests, with 0 failures`. iPhone 시뮬레이터 앱 테스트(`./scripts/test-apple.sh`의 iPhone 줄과 같은 명령) → `Executed 50 tests, with 0 failures`. iOS 시뮬레이터 빌드·macOS 빌드에 새 경고 없음(허용 경고 제외). lint 출력 없음. `./scripts/verify-modules.sh` 통과.

- [ ] **Step 5: 커밋**

```bash
git add apple/MellowPhoto apple/MellowPhoto.xcodeproj apple/MellowPhotoTests
git commit -m "feat(app): 인물 도구를 뷰티(피부·얼굴)로 바꾸고 피부 보정·자동 잡티 추가

피부 탭에 피부 보정 슬라이더와 자동 잡티 스위치를, 얼굴 탭에 가운데 0인
얼굴 폭 슬라이더를 둔다. 눈·입 탭은 D 단계에서 연다.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 8: 문서·검증 기록

**Files:**
- Modify: `README.md`, `docs/APPLE.md`, `docs/architecture/modules.md`, `VALIDATION.md`

**Interfaces:**
- Consumes: Task 1~7 결과와 `./scripts/test-apple.sh` 출력.
- Produces: 문서. 이후 Task 없음.

- [ ] **Step 1: README·APPLE.md·modules.md**

`README.md`:
- "첫 보정" 3번의 "얼굴이 있으면 피부 정돈과 얼굴 미세 조정도 약하게 넣습니다"를 "얼굴이 있으면 피부 보정 0.3과 자동 잡티를 켭니다. 얼굴 폭은 건드리지 않습니다"로.
- 5번의 "인물 값(피부 정돈·얼굴 미세 조정)"을 "뷰티 값(피부 보정·자동 잡티·얼굴 폭)"으로.
- 6번을 "**뷰티**에서 감지된 얼굴을 고르고 *피부* 탭의 피부 보정·자동 잡티, *얼굴* 탭의 얼굴 폭(가운데 0, 왼쪽은 좁게·오른쪽은 넓게)을 씁니다. 얼굴 번호는 화면 왼쪽부터입니다."로.
- 도구 줄 문장의 "인물"을 "뷰티"로, 41행의 "얼굴 미세 조정"을 "얼굴 폭"으로.
- "구현된 범위"의 피부 필터 줄을 "얼굴 윤곽점과 피부색으로 만든 피부 영역 안에서 모공 질감을 남기고 얼룩만 줄이는 피부 보정, 사진을 준비할 때 찾은 작은 잡티를 지우는 자동 잡티"로, 자동 보정 줄의 괄호를 "(얼굴이 있으면 피부 보정 0.3·자동 잡티 포함)"으로.
- 한계 문단 첫 두 문장을 "피부 보정과 자동 잡티는 학습 모델 없이 Vision 특징점과 색 규칙으로 동작합니다. 주근깨가 잡티로 지워질 수 있고, 머리카락이 얼굴을 덮거나 조명이 강하면 피부 영역이 흔들릴 수 있습니다. Evoto와 동일한 보정 품질, 자동 전신 체형 인식은 구현하지 않았습니다."로.
- 로드맵 "B 피부" 줄 끝에 " — 완료"를 붙이고 키 표기를 `portrait.skin`으로.

`docs/APPLE.md`:
- 도구 줄 순서의 "인물"을 "뷰티"로.
- 자동 줄을 "얼굴이 있으면 피부 보정 0.3과 자동 잡티를 켭니다. 얼굴 폭·체형·메이크업은 건드리지 않습니다."로.
- 조정 줄의 "인물 값 포함"을 "뷰티 값 포함"으로.
- 새 줄: "- 뷰티: 얼굴 선택 아래 *피부*·*얼굴* 탭. 피부 탭은 *피부 보정*(모공 대역은 남기고 얼룩 대역만 줄임)과 *자동 잡티*(사진을 준비할 때 얼굴당 최대 40개를 찾아 수동 잡티와 같은 방식으로 지움). 얼굴 탭은 가운데 0인 *얼굴 폭*. 수동 잡티·변형이 있으면 얼굴 폭과 얼굴 선택이 잠깁니다."
- 75행 테스트 수를 이번 `./scripts/test-apple.sh` 결과(브랜치 `beauty-b-to-f`, 패키지 169 · 앱 iPhone 50 · iPad 50 · Mac 51 예상)로 바꾼다. 실제 출력과 다르면 실제 값을 쓴다.
- 77행 기기 확인 항목에 "피부 보정·자동 잡티의 실제 사진 결과(주근깨, 머리카락 경계)"를 더한다.

`docs/architecture/modules.md`:
- MellowShared 공개 API에 `SkinAdjustments, FaceShapeAdjustments, FaceShapeKey, FeatureAdjustments, FeatureKey, BackgroundAdjustments, BodyShapeAdjustments, BodyShapeKey, MakeupAdjustments, MakeupPart, MakeupTint, MakeupStrength, BlemishSpot`을 더한다. 규칙에 "B~F 레시피 골격은 B에서 기본값과 함께 정의, 옛 키 `portrait.skinSmoothing`·`faceSlim`은 읽기만 함, `dependsOnFaces`(피부·얼굴형·눈입·메이크업 강도)·`dependsOnPerson`(배경)·`dependsOnBody`(체형), 잡티는 영속화하지 않음"을 더한다.
- MellowEditing 규칙: "수동 편집 시 얼굴 형태·대상 잠금"을 "수동 편집 시 얼굴형(`faceShape`)·대상 잠금(E에서 체형 추가)"으로, "프리셋·일괄 적용 시 잠긴 얼굴형·체형 보존", "자동 보정은 색·디테일·피부·눈입만 바꿈", "값 범위는 `EditingPolicy`(unitRange·bipolarRange·faceShapeRange)"를 더한다.
- MellowRendering 규칙: "얼굴 영역 마스크는 `FaceRegions` 한 곳(윤곽 다각형을 `CGContext` 회색 비트맵으로 그리고 볼 평균과의 Cb·Cr 거리로 가중)", "CIKL 색 커널은 `SkinKernels` 하나만 감쌈", "`PhotoPipeline.prepare`가 얼굴 뒤에 `BlemishDetector`로 잡티를 찾아 `RenderContext.blemishes`로 넘김(실패하면 빈 목록)", "`skin` 단계는 자동 잡티 패치 복구 → 피부 마스크 안 세 대역 주파수 분리"를 더한다. 단계 순서 문장은 그대로.
- 앱 타깃 `Application/` 설명에 `BeautyTab`을 더하고 도구 목록을 `look, crop, adjust, beauty, retouch, warp`로.

- [ ] **Step 2: VALIDATION.md**

`## B0 기본 편집 세트` 절 뒤, `## TestFlight 전용 배포 경로` 앞에 `## 인물 보정 B 피부 (2026-10-15)` 절을 쓴다. 이 절은 사람 확인 영역만 있고, 실제로 실행한 것만 통과로 쓴다.
- 첫 문단: 브랜치·커밋·환경(B0 절과 같은 형식).
- `### 자동 검증`: `./scripts/test-apple.sh` 종료 코드, 패키지 테스트 수(모듈별), 앱 테스트 수(iPhone·iPad·Mac), 빌드 경고(기존 `WarpKernel`과 새 `SkinKernels`의 Core Image 커널 API 지원 중단 경고).
- `### 자동 테스트가 확인하는 것`: 합성 얼굴에서 눈·입·윤곽 안 배경 픽셀 불변, 모공 대역 분산 ±10% 안, 중간 대역 분산 감소, 잡티 5개 검출과 눈 옆 점 무시, 얼굴당 상한, 데모 사진의 실제 특징점으로 볼은 마스크 안·눈동자는 밖, 옛 키 이행(B0 세션 실행 취소 기록 포함), 시나리오 "피부 0.5 + 자동 잡티 → 얼굴 폭 −0.5 → 내보내기".
- `### 미검증 (사용자 확인 필요)`: 실제 인물 사진에서의 피부 보정 느낌(플라스틱 여부, 강도 1), 자동 잡티가 주근깨·점을 지우는지, 머리카락이 얼굴을 덮은 사진의 경계, 강한 조명·역광, 여러 얼굴, 48MP 원본 저장 속도(얼굴마다 큰 흐림 두 번), 뷰티 패널 화면(탭 전환, 스위치, 0 근처 스냅), 실기기. 이전 절의 미검증 항목은 승계한다고 한 줄로 적는다.

- [ ] **Step 3: 최종 검증과 커밋**

Run: `./scripts/test-apple.sh && ./scripts/build-apple.sh ios-device && ./scripts/build-apple.sh mac` → 전부 성공. 결과 수치를 Step 1·2의 문서에 반영한다.

```bash
git add README.md docs/APPLE.md docs/architecture/modules.md VALIDATION.md
git commit -m "docs: 피부 보정 사용법·모듈 캔버스·B 검증 기록 갱신

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

## 자체 검토 결과

- **스펙 대조:** §1.1 모듈 배치 → Task 1(Shared 값 타입·`BlemishSpot` Task 5), Task 3·4·5(`FaceRegions`·`FrequencySeparation`·`BlemishDetector`는 Rendering/Domain). §1.2 레시피 골격·옛 키 이행·`dependsOn*`·`allValuesFinite`·스키마·`PresetValues` → Task 1, `EditChange`(B 범위)·범위 상수 → Task 2. §1.3 순서 → 단계 목록 불변(Task 6 Step 4에서 확인). §1.4 → B 범위인 잡티 분석과 `RenderContext.blemishes`만 Task 5. §2 피부 마스크 → Task 3, 주파수 분리 → Task 4, 잡티 검출 → Task 5, 적용 → Task 6, UI → Task 7, 테스트 5종 → Task 3(눈 영역)·4/6(모공·중간 대역)·5(잡티 5개·눈 안 점)·1(이전 키). §7 → Task 7(도구·문구·Theme), Task 2(자동 보정). §8 → 각 Task와 Task 7 시나리오, Task 8 VALIDATION.
- **스펙과 다르게 정한 점:** `makeup`은 스펙 1.2 JSON대로 최상위라 얼굴 의존 판정은 `EditRecipe.dependsOnFaces`가 메이크업을 더한다(스펙 문장은 `PortraitAdjustments.dependsOnFaces`에 메이크업을 넣음). 피부색 분산은 재지 않고 고정 σ를 쓴다. 잡티 제외 영역에 코를 더했다. `BlemishSpot`에 `faceIndex`를 더했다(대상 얼굴 필터). 스키마는 옛 키를 deprecated로 남겼다.
- **타입 일관성:** `FaceRegions`의 메서드 이름(`skinMask`, `maskBounds`, `faceWidth`, `pixelRect`, `protectedPolygons`, `blemishExclusionPolygons`, `contains`)을 Task 3·5·6에서 같게 썼다. `FrequencySeparation.blurred`는 Task 4에서 정의되고 Task 5(BlemishDetector)·테스트 지원이 쓴다. `RenderContext.init`의 `blemishes:`는 마지막 인자이고 기본값이 있어 기존 호출이 그대로 컴파일된다. `SyntheticFace`·`PixelGrid`·`skinTexture`는 Task 3, `bandVariances`는 Task 4, `writePNG`는 Task 5에서 정의된다. `EditChange.faceSlim`은 Task 1에서 남아 있고 Task 2에서 지운다.
- **Review Focus 매핑:** 1→Task 1, 2→Task 5, 3→Task 2, 4→Task 6, 5→Task 2+7. 모두 테스트 코드가 있다.
- **플레이스홀더 점검:** "TBD/TODO/나중에" 없음. Task 1의 호출부 치환은 규칙 표와 파일·행 목록으로 정확히 지정했다. Task 8의 문서 문장은 실제 테스트 수로 바꿔 쓴다.
