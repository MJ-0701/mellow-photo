# 인물 보정 G5-2 점 지우기 구현 계획

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 레시피 키 `portrait.skin.spots`와 `skin` 단계 안 점 지우기 하위 단계(`SpotRemoval`)를 넣는다. 모공보다 크고 얼굴 폭 2.4%보다 작은 어두운 점을 닫힘 차이로 채우고(밝은 점 빼기는 `spotBrightAmount` 0으로 기본 꺼짐, G5-2 구현 중 변경), 모공 대역과 깊은 구조(콧구멍·눈꼬리·입꼬리)는 건드리지 않으며, 강도는 깊이 문턱을 움직인다. 원터치 표는 `spots` 1.0/1.0/0.4(G5-2 구현 중 변경, 처음 0.75)를 쓰고 자동 잡티를 끈다. 하네스의 시제품을 지우고 제품 단계로 잰다.

**Architecture:** 키는 `SkinRefinementKey.spots`(MellowShared, 키 추가만, schemaVersion 2 유지). 렌더는 `SkinStage.refine`의 첫 하위 단계 `SpotRemoval.apply`(MellowRendering Domain)이고 커널은 `SkinKernels.spot`·`spotApply`, 제외 영역은 `FaceRegions+Spots.swift`. 보정 지도는 유한 영역에서 만들어 `insertingIntermediate()`로 굳힌다(실패 시 대안은 Task 3). 파이프라인 단계 이름·순서는 바뀌지 않는다.

**Tech Stack:** Swift 5.9 tools / Swift 5 언어 모드, Core Image(CIMorphology, CIKL 색 커널), Vision(테스트), XCTest.

**Spec:** `docs/superpowers/specs/2026-10-21-beauty-g5-evoto-calibration-design.md` (1.1, 1.2 심은 점 행, 2절 `spots`·`autoBlemish`, 3절, 4절, 7절). 선행: G5-1 전부 머지(`beauty-g5`).

## 사람이 확인할 것

- **순서.** Task 1 키·표·화면 이름 → 2 제외 영역·캐시 → 3 `SpotRemoval`·커널·단계 → 4 심은 점 수용·원터치 무복제 → 5 하네스 정리·실행. 5개 Task, Task마다 Opus 구현 → 리뷰 → 수정, 끝에 전체 리뷰.
- **외부 효과가 있는 단계.** 없음. Task 5의 하네스 실행은 이 Mac의 로컬 Evoto 이미지가 있을 때만 약 16분이 들고, 없으면 건너뛰고 VALIDATION에 "미실행"으로 적는다.
- **스펙이 정하지 않아 이 계획이 정한 것.**

| 결정 | 이유 | 바꾸면 비용 |
|---|---|---|
| `SkinRefinementKey.spots`는 `allCases` **마지막**에 둔다(`shine` 뒤). 화면 순서도 마지막 | 기존 순서를 흔들지 않고, 점 지우기는 "결함 지우기" 묶음의 끝이 자연스럽다. G5-3의 `chromaEvening`은 `toneEvening` 뒤에 끼운다(스펙 3절 순서) | 작음 |
| 점 마스크의 제외 비트맵은 `polygonMask(fill: exclusions, cut: [])` 하나이고 흐림은 `skinMaskFeather`와 같다 | 캐시 항목 하나, 흐림 반지름 상수 재사용 | 작음 |
| 강도 0.3 미만의 채움 비율 램프(`spotFullFillStrength`)는 커널 밖 Swift에서 곱한다 | 커널 인자 하나를 줄이고 식이 단순하다 | 작음 |
| 하네스 `Legacy` 표 상수는 1.4.0 값을 테스트 파일 안에 적는다(제품 상수 참조 아님) | 비교 기준이 제품 표와 함께 움직이면 안 된다 | 작음 |
| 원터치 "복제 원 없음"은 `SkinStage.healSpots(in:)`이 빈 배열인지로 단언한다(렌더 바이트 비교 아님) | 빠르고 뜻이 정확하다 | 작음 |

- **범위 밖(다른 계획).** 얼룩 색 고르기(G5-3), VALIDATION 최종·문서(G5-3).
- **위험.** (1) 중간 결과 굳히기로 얼굴 밖 픽셀이 바뀌면 Task 3의 대안(`RenderContext.renderer`)으로 간다. (2) 데모 사진의 콧구멍·눈꼬리가 특징점 어림과 어긋나면 제외 원 반지름을 0.03 → 0.04로 올린다(VALIDATION에 적는다). (3) 원본 해상도 렌더 시간. Task 4가 데모 미리보기 원터치 0.6 렌더 시간을 전후로 찍는다.
- **사용자 조치.** 없음.

---

## 에이전트 참조

## Global Constraints

G5-1 계획의 Global Constraints를 그대로 따른다(브랜치 `beauty-g5`·`DEVELOPER_DIR`·건드리지 않는 변형 파일·모듈 표 불변·lint·커밋 서명·`git add` 경로 제한·**로컬 iOS 시뮬레이터 금지**·푸시 금지). 이 계획에서 다른 것:

- 시작 조건: G5-1 머지(`SkinKernels.heal`·새 수용 경계 존재). 기준 테스트 수는 **시작 전에 실측해 이 줄에 적는다**(G5-1 뒤 추정 패키지 462, Mac 99). 이 계획이 더하는 수: **Shared +1, Rendering +9, Mac +0**(Task 1 Shared +1, Task 2 Rendering +2, Task 3 Rendering +4, Task 4 Rendering +3, Task 5 Rendering 0 — `SpotPrototype`은 테스트가 아니라 수가 줄지 않음).
- 레시피 `schemaVersion` 2 유지, 키 추가만(`portrait.skin.spots`, `$defs/portraitLayer.skin.spots`, 기본값 0).
- 파이프라인 단계 이름·순서 불변. `skin` 단계 안 순서: 자동 잡티 복구 → **점 지우기** → 주름 밝히기 → 대역 합성 → 붉은기.
- `RenderTuning` 추가(스펙 4.1): `spotRadiusFraction` 0.012, `spotPoreRadiusFraction` 0.003, `spotCorrectionBlurInPores` 1.0, `spotDepthStart` 0.008, `spotDepthStartWeak` 0.020, `spotDepthRamp` 0.032, `spotDepthCapStart` 0.25, `spotDepthCapEnd` 0.40, `spotLumaFloor` 0.01, `spotFullFillStrength` 0.3, `spotMorphologyPaddingInSpots` 3.0, `spotExclusionRadiusFraction` 0.03, `spotNostrilBandFraction` 0.4, `spotBrightAmount` 0(G5-2 구현 중 추가, 어두운 점만, 반지름은 올림 없이 스펙 처음 정의). 캐시 `RegionMaskCache.entriesPerFacePerResolution` 10 → 11.
- 표 변경(스펙 2절 G5-2 몫): `spots` 1.0/1.0/0.4(G5-2 구현 중 변경, 처음 0.75), `autoBlemish` false(층이 `false`를 덮어씀).
- `SkinKernels` 커널 6 → 8(`spot`·`spotApply`). 마스크는 `FaceRegions`(확장 파일 `FaceRegions+Spots.swift`).
- 테스트 문턱은 스펙 1.2 심은 점 행의 값이고 `SpotBounds` 명명 상수다.

## Review Focus

1. **얼굴 마스크 영역 밖 바이트 불변.** 중간 결과 굳히기가 영역 밖을 늘어난 픽셀로 만들지 않는다. → Task 3 `testSpotRemovalLeavesPixelsOutsideTheFaceBoundsUntouched`.
2. **모공은 남고 점만 사라진다.** 심은 1% 점은 70% 이상 회복, 0.3% 점은 90% 이상 남음. → Task 3 `testSpotRemovalFillsSpotsLargerThanPoresOnly`, Task 4 `testSpotRemovalFillsPlantedSpotsAndKeepsPores`.
3. **콧구멍·눈꼬리·입꼬리는 그대로.** → Task 2 마스크 테스트, Task 4 수용 테스트의 제외 원 평균 |ΔY| ≤ 1/255.
4. **강도가 문턱을 움직인다.** 0.3과 1의 얕은 점 회복률 차이 ≥ 0.1, 0은 바이트 동일. → Task 3 `testSpotStrengthMovesTheDepthThreshold`.
5. **원터치는 복제 원을 만들지 않는다.** `healSpots(in:)`이 빈 배열이고 표의 `autoBlemish`가 false를 덮어쓴다. → Task 1 `OneTouchBundleTests`, Task 4 `testOneTouchMakesNoCloneHeals`.
6. **대상 얼굴만.** 개인 층 `spots`는 그 얼굴만 바꾼다. → Task 3 `testSpotRemovalRefinesOnlyTheTargetFace`.

## 인터페이스 요약 (모든 Task가 공유하는 이름)

```swift
// MellowShared (Task 1)
SkinRefinementKey.spots                                  // allCases 마지막
SkinAdjustments.spots: Double                            // 0…1, 기본 0
OneTouchBundle.Values.spots: Double                      // refinements에 포함
OneTouchBundle.Table.common.spots = 1.0, female.spots = 1.0, male.spots = 0.4
OneTouchBundle.layer(for:strength:)                      // autoBlemish = false

// MellowRendering (Task 2)
FaceRegions.spotExclusionPolygons(face:extent:tuning:) -> [[CGPoint]]
FaceRegions.spotExclusionRaster(face:extent:tuning:cache:) -> CIImage
FaceRegions.spotMask(face:skinMask:extent:tuning:cache:) -> CIImage     // skinMask × (1 − blur(raster))
RegionMaskCache.entriesPerFacePerResolution = 11

// MellowRendering (Task 3)
enum SpotRemoval {
    static func apply(_ image: CIImage, face: FaceGeometry, skinMask: CIImage, faceWidth: CGFloat, amount: Double,
                      tuning: RenderTuning, extent: CGRect, cache: RegionMaskCache?) throws -> CIImage
    static func thresholds(strength: Double, tuning: RenderTuning) -> (start: Double, end: Double, fill: Double)
}
extension SkinKernels {
    func spot(darkFill: CIImage, darkPore: CIImage, brightCut: CIImage, brightPore: CIImage,
              start: Double, end: Double, capStart: Double, capEnd: Double, lumaFloor: Double, extent: CGRect) throws -> CIImage
    func spotApply(image: CIImage, correction: CIImage, mask: CIImage, amount: Double, extent: CGRect) throws -> CIImage
}
SkinStage.refine                                          // 점 지우기를 주름 앞에 호출

// 테스트 지원 (Task 4)
RealPortrait.spotGrid(count: Int, radiusFraction: CGFloat, spacingFraction: CGFloat) throws -> [CGPoint]
RealPortrait.spotExclusionMask() throws -> PixelGrid
RealPhotoAcceptanceTests.SpotBounds

// 하네스 (Task 5)
EvotoCalibrationTests.Legacy                              // 1.4.0 표 상수
EvotoCalibrationTests.candidateFamilies = [legacy]        // SpotPrototype·Variant.spots·cloneHeal 삭제
```

---

### Task 1: 키 `spots`·표·스키마·화면 이름

**Files:**
- Modify: `apple/Sources/MellowShared/API/SkinAdjustments.swift`, `apple/Sources/MellowShared/API/OneTouchBundle.swift`, `shared/recipe-schema/edit-recipe.v2.schema.json`, `shared/recipe-schema/README.md`, `apple/MellowPhoto/Application/UserMessage.swift`
- Test: `apple/Tests/MellowSharedTests/OneTouchBundleTests.swift`, `EditRecipeCodingTests.swift`, `RecipeSchemaTests.swift`, `apple/Tests/MellowEditingTests/EditDocumentTests.swift`

- [ ] **Step 1: 실패하는 테스트 작성**

`OneTouchBundleTests`에 추가:

```swift
    func testOneTouchRemovesSpotsAndTurnsCloneHealOff() {
        let female = OneTouchBundle.layer(for: .female, strength: 1)
        XCTAssertEqual(female.skinRefinement[.spots], OneTouchBundle.Table.female.spots)
        XCTAssertEqual(female.autoBlemish, false, "점 지우기가 있으면 복제 원을 끈다(스펙 G5 판정 4b)")
        XCTAssertTrue(female.overriddenKeys.contains(.autoBlemish), "false를 덮어쓴다(상속 아님)")
        XCTAssertLessThan(OneTouchBundle.Table.male.spots, OneTouchBundle.Table.female.spots, "남성은 점을 더 남긴다")
        XCTAssertEqual(OneTouchBundle.layer(for: .male, strength: 0.5).skinRefinement[.spots] ?? 0, OneTouchBundle.Table.male.spots * 0.5, accuracy: 1e-12)
        XCTAssertTrue(OneTouchBundle.keys.contains(.skinRefinement(.spots)))
    }
```

기존 `testTablesScaleLinearlyAndNeverTouchShapeOrLipColour`의 `XCTAssertEqual(female.autoBlemish, true)`를 `false`로 바꾼다. `EditRecipeCodingTests`의 피부 정밀 왕복 테스트에 `spots: 0.4`를 더하고, 옛 JSON(키 없음)이 0으로 읽히는지 단언한다. `RecipeSchemaTests`는 `additionalProperties: false`라 스키마 수정 없이는 실패한다(키 집합 대조). `EditDocumentTests`에서 "정밀 7종 보존"을 세는 테스트가 있으면 `SkinRefinementKey.allCases.count`로 바꾼다.

- [ ] **Step 2: 실패 확인**

Run: `cd apple && swift test --filter "OneTouchBundleTests|EditRecipeCodingTests|RecipeSchemaTests"` → 컴파일 실패(`.spots` 없음).

- [ ] **Step 3: 구현**

`SkinRefinementKey`에 `case spots` 추가(마지막). `SkinAdjustments`: `public var spots: Double`, init 인자 `spots: Double = 0`(마지막), decode `?? 0`, subscript get/set 분기. 주석 "피부 정밀 8종".

`OneTouchBundle.Values`에 `spots: Double`(init 인자, `refinements`에 `.spots: spots`). `Table`: common 1.0, female 1.0, male 0.4(G5-2 구현 중 변경, 처음 0.75). `layer(for:strength:)`: `layer.autoBlemish = false`. 주석: "점 지우기가 복제 원을 대신한다(스펙 G5 판정 4b). false를 덮어써 1.4.0 세션의 true를 끈다."

스키마: `portrait.skin.spots` `{ "type": "number", "default": 0, "minimum": 0, "maximum": 1, "description": "점 지우기(모공보다 크고 얼굴 폭 2.4%보다 작은 어두운·밝은 점 채움). 강도는 깊이 문턱을 움직인다." }`, `$defs/portraitLayer.skin.spots` 같음(default 없음). README: 규칙 절에 "G5는 `portrait.skin`에 `spots`·`chromaEvening`을 같은 규칙으로 더했습니다(기본값 0, schemaVersion 2 유지)", `portrait` 설명 줄에 `spots` 추가, 원터치 표에 `skin.spots` 1.0/1.0/0.4(G5-2 구현 중 변경, 처음 0.75) 행과 `skin.autoBlemish` false.

`UserMessage.skinRefinementTitle`: `case .spots: return "점 지우기"`. `skinRefinementHint`에 "점 지우기는 모공보다 큰 점만 채워요" 한 구절을 더한다(한 줄 유지).

- [ ] **Step 4: 실행**

Run: `cd apple && swift test --filter "MellowSharedTests|MellowEditingTests"` → 통과. Mac 앱 테스트 통과(`BeautyPanel`이 `allCases`로 슬라이더를 하나 더 그린다. 앱 테스트에 슬라이더 수를 세는 단언이 있으면 `allCases.count`로 바꾼다). lint 출력 없음.

- [ ] **Step 5: 커밋**

```bash
git add apple/Sources/MellowShared/API/SkinAdjustments.swift apple/Sources/MellowShared/API/OneTouchBundle.swift shared/recipe-schema/edit-recipe.v2.schema.json shared/recipe-schema/README.md apple/MellowPhoto/Application/UserMessage.swift apple/Tests/MellowSharedTests/OneTouchBundleTests.swift apple/Tests/MellowSharedTests/EditRecipeCodingTests.swift apple/Tests/MellowSharedTests/RecipeSchemaTests.swift
git commit -m "feat(shared): 피부 정밀 키 spots 추가, 원터치 표가 점 지우기를 쓰고 자동 잡티를 끔

portrait.skin.spots(0…1, 기본 0, schemaVersion 2 유지). 표는 1.0/1.0/0.4(G5-2 구현 중 변경, 처음 0.75)이고 autoBlemish false를 덮어쓴다.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

(`EditDocumentTests.swift`를 고쳤으면 `git add`에 넣는다.)

---

### Task 2: 제외 영역(콧구멍 띠·눈꼬리·입꼬리)과 캐시

**Files:**
- Create: `apple/Sources/MellowRendering/Domain/FaceRegions+Spots.swift`
- Modify: `apple/Sources/MellowRendering/Domain/RegionMaskCache.swift`, `apple/Sources/MellowRendering/API/RenderTuning.swift`
- Create: `apple/Tests/MellowRenderingTests/SpotRegionsTests.swift`
- Test: `apple/Tests/MellowRenderingTests/RegionMaskCacheTests.swift`(캐시 수 단언)

- [ ] **Step 1: 실패하는 테스트 작성**

`SpotRegionsTests.swift`(합성 얼굴 `SyntheticFace.make()`, 얼굴 폭 280, 특징점 좌표는 `SyntheticFace.geometry()`와 `FoldRegionsTests`의 표본 점 방식):

```swift
final class SpotRegionsTests: XCTestCase {
    typealias Support = RenderingTestSupport

    func testExclusionCoversNostrilBandEyeAndMouthCornersOnly() throws {
        let face = SyntheticFace.make()
        let tuning = RenderTuning()
        let extent = face.image.extent
        let raster = FaceRegions.spotExclusionRaster(face: face.geometry, extent: extent, tuning: tuning, cache: nil)
        let grid = try Support.grid(raster.cropped(to: extent))
        // 코 다각형 아래 끝 바로 위(콧구멍 띠 안), 코 다각형 위쪽(띠 밖), 눈꼬리, 입꼬리, 볼 가운데.
        let nose = try XCTUnwrap(face.geometry.bounds(of: .nose))
        let nostril = CGPoint(x: nose.midX * extent.width, y: (nose.minY + nose.height * 0.15) * extent.height)
        let bridge = CGPoint(x: nose.midX * extent.width, y: (nose.minY + nose.height * 0.8) * extent.height)
        let leftEye = try XCTUnwrap(face.geometry.bounds(of: .leftEye))
        let eyeCorner = CGPoint(x: leftEye.minX * extent.width, y: leftEye.midY * extent.height)
        let lips = try XCTUnwrap(face.geometry.bounds(of: .outerLips))
        let mouthCorner = CGPoint(x: lips.maxX * extent.width, y: lips.midY * extent.height)
        let cheek = CGPoint(x: 200, y: 200)
        XCTAssertGreaterThanOrEqual(grid.red(nostril), 128, "콧구멍 띠")
        XCTAssertEqual(grid.red(bridge), 0, "코 윗부분은 제외하지 않는다")
        XCTAssertGreaterThanOrEqual(grid.red(eyeCorner), 128, "눈꼬리")
        XCTAssertGreaterThanOrEqual(grid.red(mouthCorner), 128, "입꼬리")
        XCTAssertEqual(grid.red(cheek), 0, "볼은 제외하지 않는다")
    }

    func testMissingLandmarksDropOnlyThatExclusion() throws {
        let face = SyntheticFace.make().geometry.removing([.nose])
        let polygons = FaceRegions.spotExclusionPolygons(face: face, extent: CGRect(x: 0, y: 0, width: 512, height: 512), tuning: RenderTuning())
        XCTAssertEqual(polygons.count, 4, "코가 없으면 눈꼬리 둘·입꼬리 둘만")
    }
}
```

`RegionMaskCacheTests`의 `entriesPerFacePerResolution` 단언을 11로, `SkinStageTests.testRefinementsUseOneSkinRasterAndOneFoldRaster`가 캐시 항목 수를 세면 점 지우기 켠 경우 +1을 더한다.

- [ ] **Step 2: 실패 확인**

Run: `cd apple && swift test --filter "SpotRegionsTests|RegionMaskCacheTests"` → 컴파일 실패.

- [ ] **Step 3: 구현**

`FaceRegions+Spots.swift`:

```swift
extension FaceRegions {
    /// 점 지우기에서 뺄 영역: 코 다각형 아래 spotNostrilBandFraction 높이(콧구멍), 눈 다각형의 u 최소·최대 점 둘레 원, 바깥 입술의 u 최소·최대 점 둘레 원.
    /// 특징점이 없는 부위는 뺀다.
    static func spotExclusionPolygons(face: FaceGeometry, extent: CGRect, tuning: RenderTuning) -> [[CGPoint]] {
        let width = faceWidth(face, extent: extent)
        let radius = width * CGFloat(tuning.spotExclusionRadiusFraction)
        var polygons: [[CGPoint]] = []
        if let nose = landmarkPolygon(face, .nose, extent) {
            let box = boundingRect(nose)
            let top = box.minY + box.height * CGFloat(tuning.spotNostrilBandFraction)
            let band = CGRect(x: box.minX, y: box.minY, width: box.width, height: top - box.minY)
            polygons.append(rectanglePolygon(band))
        }
        for landmark in [FaceLandmark.leftEye, .rightEye, .outerLips] {
            guard let polygon = landmarkPolygon(face, landmark, extent), let left = polygon.min(by: { $0.x < $1.x }),
                let right = polygon.max(by: { $0.x < $1.x })
            else { continue }
            for corner in [left, right] {
                polygons.append(ellipsePolygon(in: CGRect(x: corner.x - radius, y: corner.y - radius, width: radius * 2, height: radius * 2)))
            }
        }
        return polygons
    }

    static func spotExclusionRaster(face: FaceGeometry, extent: CGRect, tuning: RenderTuning, cache: RegionMaskCache?) -> CIImage {
        polygonMask(fill: spotExclusionPolygons(face: face, extent: extent, tuning: tuning), cut: [], cutWidth: 0, extent: extent, tuning: tuning, cache: cache)
    }

    /// 피부 마스크 × (1 − 흐린 제외 비트맵).
    static func spotMask(face: FaceGeometry, skinMask: CIImage, extent: CGRect, tuning: RenderTuning, cache: RegionMaskCache?) -> CIImage {
        let raster = spotExclusionRaster(face: face, extent: extent, tuning: tuning, cache: cache)
        let black = CIImage(color: .black).cropped(to: extent)
        let keep = raster.composited(over: black).clampedToExtent()
            .applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: featherRadius(face, extent, tuning)])
            .cropped(to: extent).applyingFilter("CIColorInvert")
        return skinMask.applyingFilter("CIMultiplyCompositing", parameters: [kCIInputBackgroundImageKey: keep]).cropped(to: extent)
    }
}
```

`ellipsePolygon`은 지금 `private` → `fileprivate`에서 internal로 올린다(`FaceRegions.swift`). `rectanglePolygon(_:)`은 네 꼭짓점. `polygonMask`가 빈 `fill`을 받으면 검은 비트맵을 돌려주는지 확인하고, 아니면 `spotExclusionRaster`가 빈 목록일 때 `black`을 돌려준다.

`RegionMaskCache.entriesPerFacePerResolution = 11`(주석: G5 점 제외 비트맵). `RenderTuning`에 `spotExclusionRadiusFraction`·`spotNostrilBandFraction`.

- [ ] **Step 4: 실행**

Run: `cd apple && swift test --filter "SpotRegionsTests|RegionMaskCacheTests|SkinStageTests|MakeupStageTests"` → 통과(얼굴 셋 두 해상도 캐시 유지 테스트가 상한 증가에 맞는지 확인).

- [ ] **Step 5: 커밋**

```bash
git add apple/Sources/MellowRendering/Domain/FaceRegions+Spots.swift apple/Sources/MellowRendering/Domain/FaceRegions.swift apple/Sources/MellowRendering/Domain/RegionMaskCache.swift apple/Sources/MellowRendering/API/RenderTuning.swift apple/Tests/MellowRenderingTests/SpotRegionsTests.swift apple/Tests/MellowRenderingTests/RegionMaskCacheTests.swift
git commit -m "feat(rendering): 점 지우기 제외 영역(콧구멍 띠·눈꼬리·입꼬리) 마스크와 캐시 항목 추가

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 3: `SpotRemoval`·커널·`skin` 단계 연결

**Files:**
- Create: `apple/Sources/MellowRendering/Domain/SpotRemoval.swift`
- Modify: `apple/Sources/MellowRendering/Domain/SkinKernels.swift`, `apple/Sources/MellowRendering/Domain/SkinStage.swift`, `apple/Sources/MellowRendering/API/RenderTuning.swift`
- Create: `apple/Tests/MellowRenderingTests/SpotRemovalTests.swift`

- [ ] **Step 1: 실패하는 테스트 작성**

`SpotRemovalTests.swift`(합성 얼굴 + `Support.skinTexture` 질감 위에 심은 원, `SkinStage`로 렌더):

```swift
final class SpotRemovalTests: XCTestCase {
    typealias Support = RenderingTestSupport

    enum Bounds {
        static let faceWidth: CGFloat = 280
        static let spotRadiusFraction: CGFloat = 0.01
        static let poreRadiusFraction: CGFloat = 0.003
        static let darkFactor = 0.85
        static let brightFactor = 1.10
        static let shallowFactor = 0.97
        static let spotRecovery = 0.7
        static let poreRemaining = 0.9
        static let strengthGap = 0.1
        static let spotCenters = [CGPoint(x: 200, y: 200), CGPoint(x: 310, y: 210), CGPoint(x: 256, y: 300)]
        static let poreCenters = [CGPoint(x: 230, y: 240), CGPoint(x: 290, y: 250)]
    }

    private func planted(_ factor: Double, centers: [CGPoint], radiusFraction: CGFloat) throws -> (image: CIImage, face: FaceGeometry) {
        let base = SyntheticFace.make()
        let spotted = SyntheticDefect.spotted(base.image, centers: centers, radius: Bounds.faceWidth * radiusFraction, factor: factor, extent: base.image.extent)
        return (CIImage(cgImage: try Support.renderer.makeCGImage(spotted)), base.geometry)
    }

    private func render(_ image: CIImage, face: FaceGeometry, spots: Double) throws -> PixelGrid {
        var recipe = EditRecipe()
        recipe.portrait.skin.spots = spots
        let context = RenderContext(extent: image.extent, recipe: recipe, analysis: PhotoAnalysis(faces: [face]), tuning: RenderTuning())
        return try Support.grid(SkinStage().apply(image, in: context))
    }

    private func recovery(original: PixelGrid, defective: PixelGrid, repaired: PixelGrid, at center: CGPoint) -> Double {
        DisplayScale.recovery(original: Double(original.red(center)), defective: Double(defective.red(center)), repaired: Double(repaired.red(center)))
    }

    func testSpotRemovalFillsSpotsLargerThanPoresOnly() throws {
        let clean = try Support.grid(SyntheticFace.make().image)
        let dark = try planted(Bounds.darkFactor, centers: Bounds.spotCenters, radiusFraction: Bounds.spotRadiusFraction)
        let darkBefore = try Support.grid(dark.image)
        let darkAfter = try render(dark.image, face: dark.face, spots: 1)
        for center in Bounds.spotCenters {
            XCTAssertGreaterThanOrEqual(recovery(original: clean, defective: darkBefore, repaired: darkAfter, at: center), Bounds.spotRecovery, "어두운 점 \(center)")
        }
        let bright = try planted(Bounds.brightFactor, centers: Bounds.spotCenters, radiusFraction: Bounds.spotRadiusFraction)
        let brightAfter = try render(bright.image, face: bright.face, spots: 1)
        for center in Bounds.spotCenters {
            XCTAssertGreaterThanOrEqual(recovery(original: clean, defective: try Support.grid(bright.image), repaired: brightAfter, at: center), Bounds.spotRecovery, "밝은 점 \(center)")
        }
        let pores = try planted(Bounds.darkFactor, centers: Bounds.poreCenters, radiusFraction: Bounds.poreRadiusFraction)
        let poresBefore = try Support.grid(pores.image)
        let poresAfter = try render(pores.image, face: pores.face, spots: 1)
        for center in Bounds.poreCenters {
            let remaining = 1 - recovery(original: clean, defective: poresBefore, repaired: poresAfter, at: center)
            XCTAssertGreaterThanOrEqual(remaining, Bounds.poreRemaining, "모공 크기 점은 남는다 \(center)")
        }
    }

    func testSpotStrengthMovesTheDepthThreshold() throws {
        let clean = try Support.grid(SyntheticFace.make().image)
        let shallow = try planted(Bounds.shallowFactor, centers: Bounds.spotCenters, radiusFraction: Bounds.spotRadiusFraction)
        let before = try Support.grid(shallow.image)
        let weak = try render(shallow.image, face: shallow.face, spots: 0.3)
        let full = try render(shallow.image, face: shallow.face, spots: 1)
        let center = Bounds.spotCenters[0]
        let gap = recovery(original: clean, defective: before, repaired: full, at: center) - recovery(original: clean, defective: before, repaired: weak, at: center)
        XCTAssertGreaterThanOrEqual(gap, Bounds.strengthGap, "강도 1이 얕은 점을 더 채운다")
        let zero = try render(shallow.image, face: shallow.face, spots: 0)
        XCTAssertEqual(try Support.bytes(shallow.image), zero.bytes, "강도 0은 바이트 동일")
    }

    func testSpotRemovalLeavesPixelsOutsideTheFaceBoundsUntouched() throws {
        let dark = try planted(Bounds.darkFactor, centers: Bounds.spotCenters, radiusFraction: Bounds.spotRadiusFraction)
        let before = try Support.grid(dark.image)
        let after = try render(dark.image, face: dark.face, spots: 1)
        let bounds = FaceRegions.maskBounds(face: dark.face, extent: dark.image.extent, tuning: RenderTuning())
        for point in [CGPoint(x: 4, y: 4), CGPoint(x: 508, y: 4), CGPoint(x: 4, y: 508), CGPoint(x: 508, y: 508), CGPoint(x: Int(bounds.maxX) + 2, y: Int(bounds.midY))] {
            XCTAssertEqual(before.rgba(point), after.rgba(point), "영역 밖 \(point) 바이트 동일")
        }
        let nose = try XCTUnwrap(dark.face.bounds(of: .nose))
        let nostril = CGPoint(x: Int(nose.midX * dark.image.extent.width), y: Int((nose.minY + nose.height * 0.15) * dark.image.extent.height))
        XCTAssertLessThanOrEqual(abs(Int(before.red(nostril)) - Int(after.red(nostril))), 1, "콧구멍 띠는 그대로")
    }

    func testSpotRemovalRefinesOnlyTheTargetFace() throws {
        // SkinStageTests.testTargetFaceRefinesOnlyThatFace와 같은 두 얼굴 구성에 개인 층 spots = 1.
    }
}
```

`PixelGrid.bytes`가 없으면 `Support.bytes(_:)`로 두 이미지를 비교한다.

- [ ] **Step 2: 실패 확인**

Run: `cd apple && swift test --filter SpotRemovalTests` → 컴파일 실패(`SpotRemoval` 없음) 또는 `spots`가 렌더에 영향 없어 회복률 0.

- [ ] **Step 3: 구현**

`RenderTuning`(스펙 4.1의 나머지 상수, 주석에 뜻).

`SkinKernels`에 커널 둘(`spot`은 시제품 `correctionKernel`과 같고 Y는 BT.709 선형, `spotApply`는 `image.rgb + correction.rgb × mask.r × amount`).

`SpotRemoval.swift`:

```swift
/// 모공보다 크고 얼굴 폭 2.4%보다 작은 어두운·밝은 점을 닫힘·열림 차이로 채운다(스펙 G5 4절).
/// 모공 크기 명암은 차이에서 빠져 남고, 상대 깊이가 cap보다 깊은 구조(콧구멍·눈꼬리)는 건드리지 않는다.
/// 강도는 깊이 시작 문턱을 움직이고(1에서 spotDepthStart, 0에서 spotDepthStartWeak) 문턱을 넘은 점은 완전히 채운다.
enum SpotRemoval {
    static func thresholds(strength: Double, tuning: RenderTuning) -> (start: Double, end: Double, fill: Double) {
        let amount = min(1, max(0, strength))
        let start = tuning.spotDepthStartWeak + (tuning.spotDepthStart - tuning.spotDepthStartWeak) * amount
        let fill = min(1, amount / tuning.spotFullFillStrength)
        return (start, start + tuning.spotDepthRamp, fill)
    }

    static func apply(
        _ image: CIImage, face: FaceGeometry, skinMask: CIImage, faceWidth: CGFloat, amount: Double,
        tuning: RenderTuning, extent: CGRect, cache: RegionMaskCache?
    ) throws -> CIImage {
        guard amount > 0 else { return image }
        let bounds = FaceRegions.maskBounds(face: face, extent: extent, tuning: tuning).intersection(extent)
        guard !bounds.isEmpty else { return image }
        let spot = Double(faceWidth) * tuning.spotRadiusFraction
        let pore = max(tuning.skinBlurMinimumRadius, Double(faceWidth) * tuning.spotPoreRadiusFraction)
        // 형태 필터 입력은 가장자리 여유를 둔 유한 영역이다. 무한 extent를 넣으면 영역 밖이 늘어난 픽셀이 된다.
        let padding = CGFloat(spot * tuning.spotMorphologyPaddingInSpots)
        let source = image.clampedToExtent().cropped(to: bounds.insetBy(dx: -padding, dy: -padding))
        func morphology(_ first: String, _ second: String, _ radius: Double) -> CIImage {
            source.applyingFilter(first, parameters: [kCIInputRadiusKey: radius])
                .applyingFilter(second, parameters: [kCIInputRadiusKey: radius]).cropped(to: bounds)
        }
        let maximum = "CIMorphologyMaximum"
        let minimum = "CIMorphologyMinimum"
        let limits = thresholds(strength: amount, tuning: tuning)
        let correction = try SkinKernels.shared.spot(
            darkFill: morphology(maximum, minimum, spot), darkPore: morphology(maximum, minimum, pore),
            brightCut: morphology(minimum, maximum, spot), brightPore: morphology(minimum, maximum, pore),
            start: limits.start, end: limits.end, capStart: tuning.spotDepthCapStart, capEnd: tuning.spotDepthCapEnd,
            lumaFloor: tuning.spotLumaFloor, extent: bounds)
        // 보정 지도를 중간 결과로 굳혀 뒤의 흐림·합성이 형태 필터 그래프를 다시 펼치지 않게 한다.
        let baked = correction.insertingIntermediate()
        let smoothed = baked.clampedToExtent()
            .applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: pore * tuning.spotCorrectionBlurInPores])
        let mask = FaceRegions.spotMask(face: face, skinMask: skinMask, extent: extent, tuning: tuning, cache: cache)
        let fixed = try SkinKernels.shared.spotApply(image: image, correction: smoothed, mask: mask, amount: limits.fill, extent: bounds)
        return fixed.composited(over: image).cropped(to: extent)
    }
}
```

`SkinStage.refine`: `unitMask`를 만든 뒤, 주름 반복 앞에

```swift
        if skin.spots > 0 {
            result = try SpotRemoval.apply(
                result, face: face, skinMask: unitMask, faceWidth: faceWidth, amount: skin.spots, tuning: tuning,
                extent: extent, cache: context.regionMasks)
        }
```

`apply`의 `where skin.smoothing > 0 || skin.hasRefinement`는 `hasRefinement`가 `allCases`라 `spots`를 포함한다. `refine`의 `guard bandMix || skin.redness != 0 else { return result }`는 그대로(점 지우기 결과를 돌려준다).

**(G5-2 구현 중 변경)** `spotApply`에 `image.cropped(to: bounds)`를 넘긴다(스펙 4.3). 자르지 않으면 바탕까지 늘어난 픽셀이 된다. 단위 테스트는 2배 합성 얼굴·깨끗한 사진 렌더 대비 남은 비율·격자 18점 평균 회복률로 잰다(스펙 4.4).

**대안(`testSpotRemovalLeavesPixelsOutsideTheFaceBoundsUntouched`가 실패할 때만):** `RenderContext.init`에 `renderer: Renderer? = nil`(저장 속성 `public let renderer: Renderer?`), `PhotoPipeline`의 `preview`·`render(url:…)`가 `renderer: renderer`를 넘기고, `Renderer`에 `func makeFloatImage(_ image: CIImage) throws -> CIImage`(`createCGImage(format: .RGBAf, colorSpace: extendedLinearSRGB)` → `CIImage(cgImage:options: [.colorSpace: extendedLinearSRGB])`, extent 원점으로 되돌리는 translate)를 더한다. `SpotRemoval.apply`에 `renderer: Renderer?` 인자를 더해 있으면 `insertingIntermediate()` 대신 `makeFloatImage`를 쓴다. 테스트는 `Support.renderer`를 넘긴다. 이 경우 `modules.md`의 `RenderContext` 설명에 한 줄을 더하고 VALIDATION "스펙과 다르게 한 것"에 적는다.

- [ ] **Step 4: 실행·회귀**

Run: `cd apple && swift test --filter "SpotRemovalTests|SkinStageTests|RenderPipelineTests|RealPhotoAcceptanceTests"` → 통과. `RealPhotoAcceptanceTests`의 원터치 상한(얼굴 밖 ≤ 0.002, fine ≥ 0.9)은 표에 `spots`가 들어가므로 이 Task에서 함께 돈다. fine 비가 미달이면 `spotCorrectionBlurInPores`를 1.0 → 1.5로 올린다.

- [ ] **Step 5: 커밋**

```bash
git add apple/Sources/MellowRendering/Domain/SpotRemoval.swift apple/Sources/MellowRendering/Domain/SkinKernels.swift apple/Sources/MellowRendering/Domain/SkinStage.swift apple/Sources/MellowRendering/API/RenderTuning.swift apple/Tests/MellowRenderingTests/SpotRemovalTests.swift
git commit -m "feat(rendering): 점 지우기 하위 단계 추가 — 닫힘·열림 차이로 모공보다 큰 점만 채움

skin 단계에서 자동 잡티 뒤·주름 앞에 돈다. 상대 깊이 문턱은 강도가 움직이고 25~40%보다 깊은 구조는 건드리지 않는다.
보정 지도는 유한 영역에서 만들어 중간 결과로 굳힌다.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 4: 실사진 수용 — 심은 점·원터치 무복제·렌더 시간

**Files:**
- Modify: `apple/Tests/MellowRenderingTests/RenderingTestSupport.swift`, `apple/Tests/MellowRenderingTests/RealPhotoAcceptanceTests.swift`

- [ ] **Step 1: 테스트 작성**

`RealPortrait.spotGrid(count:radiusFraction:spacingFraction:)`: 피부 마스크(세기 1)를 `readPixels`로 읽어 얼굴 상자 안을 `spacingFraction × faceWidth` 간격 격자로 훑으며 마스크 ≥ 0.9이고 제외 마스크(`spotExclusionMask`) = 0이며 서로 `spacingFraction` 이상 떨어진 점을 `count`개 모은다(위에서 아래, 왼쪽에서 오른쪽, 결정적). 부족하면 `MellowError.renderFailed`.

`RealPhotoAcceptanceTests`에 추가:

```swift
    enum SpotBounds {
        static let darkCount = 6
        static let brightCount = 3
        static let darkRadiusFraction: CGFloat = 0.009
        static let brightRadiusFraction: CGFloat = 0.007
        static let darkFactor = 0.85
        static let brightFactor = 1.10
        static let spacingFraction: CGFloat = 0.08
        static let darkRecovery = 0.7
        static let brightRecovery = 0.6
        static let fineRatio = 0.9
        static let poreRatio = 0.9
        static let exclusionMeanAbsolute = 1.0
        static let defaultDarkRecovery = 0.6
        static let maleDefaultDarkRecovery = 0.4
    }

    /// 점 지우기 1이 심은 점을 채우고 모공·제외 영역·얼굴 밖은 남긴다(스펙 G5 1.2).
    func testSpotRemovalFillsPlantedSpotsAndKeepsPores() throws { … }
    /// 원터치 0.6에서 심은 어두운 점 회복: 여성·공통 ≥ 0.6, 남성 ≥ 0.4이고 여성보다 작다.
    func testOneTouchDefaultRemovesPlantedSpotsLessForMen() throws { … }
    /// 원터치 레시피는 복제 원을 하나도 만들지 않는다(자동 잡티 false 덮어쓰기).
    func testOneTouchMakesNoCloneHeals() throws {
        let portrait = try self.portrait()
        let blemish = BlemishSpot(x: 0.5, y: 0.5, radius: 0.01, faceIndex: 0)
        let analysis = PhotoAnalysis(faces: portrait.analysis.faces, blemishes: [blemish], personMask: nil, bodies: [])
        var recipe = Self.oneTouchRecipe(strength: 1, faces: [portrait.face], genders: [.female])
        recipe.portrait.skin.autoBlemish = true   // 1.4.0 세션에 남은 전체 층 값
        for group in Gender.allCases { recipe.people.groups[group] = OneTouchBundle.layer(for: group, strength: 1) }
        let context = RenderContext(extent: portrait.extent, recipe: recipe, analysis: analysis, tuning: portrait.tuning)
        XCTAssertTrue(SkinStage.healSpots(in: context).isEmpty, "그룹 층 false가 전체 층 true를 덮는다")
    }
```

회복률은 원 안 `hardEllipse(0.65r)` 가중 휘도로 `DisplayScale.recovery`. 모공 비: 원 밖 피부 안쪽 가중치로 `Support.bandVarianceRatio(innerRadius: 0, outerRadius: faceWidth × 0.003)` 대신 fine 비(`fineVarianceRatio`, 심은 원 마스크를 뺀 가중치)와 "0.3% 닫힘 어두운 점 평균 비"를 함께 잰다. 0.3% 닫힘 비는 `Support.closingDarkMean(_:weight:in:radius:)`(close(r) − Y의 가중 평균)를 더해 `after / before ≥ 0.9`.

렌더 시간: `testOneTouchDefaultRemovesPlantedSpotsLessForMen` 앞에 `measure` 대신 `CFAbsoluteTimeGetCurrent`로 원터치 0.6 데모 미리보기 렌더 시간을 `record("oneTouch-0.6", "renderSeconds", …)`로 찍는다(단언 없음, VALIDATION용). `spots = 0`인 같은 레시피도 찍어 차이를 적는다.

- [ ] **Step 2: 실행·조정**

Run: `cd apple && swift test --filter RealPhotoAcceptanceTests 2>&1 | tee /tmp/g5-2-acceptance.log | grep -E "acceptance|passed|failed|error"`.

- 회복률 미달 → `spotRadiusFraction` 0.012 → 0.015(모공 비 ≥ 0.9 유지 확인).
- 제외 원 |ΔY| 초과 → `spotExclusionRadiusFraction` 0.03 → 0.04.
- 남성 회복률이 여성 이상 → 표 `male.spots` 0.75 → 0.65.
- 원터치 보임 하한 재확인(G5-1 규칙 그대로).

전체 `swift test` → Rendering 기준 +9(이 계획 합계). Mac 앱 테스트 통과. lint 출력 없음. iOS 시뮬레이터용 빌드 성공.

- [ ] **Step 3: 커밋**

```bash
git add apple/Tests/MellowRenderingTests/RenderingTestSupport.swift apple/Tests/MellowRenderingTests/RealPhotoAcceptanceTests.swift
git commit -m "test(rendering): 데모 사진에 심은 점의 회복률·모공·제외 영역과 원터치 무복제를 단언

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

(상수·표를 고쳤으면 그 파일과 README를 같은 커밋에 넣고 메시지에 적는다.)

---

### Task 5: 하네스 정리·실행

**Files:**
- Modify: `apple/Tests/MellowRenderingTests/EvotoCalibrationTests.swift`

- [ ] **Step 1: 시제품 제거와 `Legacy` 계열**

- `SpotPrototype` enum 삭제. `Variant.spots`·`cloneHeal` 삭제. `EvotoPhoto.render`에서 시제품 호출 삭제.
- `Candidate` → `Legacy`: 1.4.0 표 값 상수(`smoothing` 0.35/0.45/0.25, `toneEvening` 0.25/0.35/0.15, `darkCircles` 0.55/0.6/0.5, `nasolabial` 0.4/0.45/0.35, `spots` 0, `autoBlemish` true, `bodyBrightness` 0.15). `Variant`에 `autoBlemish: Bool`을 더하고 `layer(_:strength:)`가 그 값을 쓴다(현재 표 계열은 `OneTouchBundle.layer`와 같아야 하므로 `testLocalLayerMatchesTheBundle`이 `autoBlemish false`를 확인한다).
- `candidateFamilies = [candidate("legacy", table: Legacy.values(for:), bodyBrightness: Legacy.bodyBrightness, autoBlemish: true)]`.
- 파일 머리 주석의 "시제품" 문구를 지우고 "legacy 계열은 1.4.0 표"를 적는다.

- [ ] **Step 2: 컴파일·단위 확인**

Run: `cd apple && swift test --filter EvotoCalibrationTests` → `testLocalLayerMatchesTheBundle` 통과, 측정 테스트는 `MELLOW_EVOTO_DIR` 없음으로 건너뜀(XCTSkip).

- [ ] **Step 3: 하네스 실행(이미지가 있을 때만)**

Phase A가 쓴 Evoto 이미지 폴더가 이 Mac에 있으면(코디네이터가 경로를 알려 준다. 없으면 이 Step을 건너뛰고 VALIDATION에 "미실행"):

```bash
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
cd apple && MELLOW_EVOTO_DIR=<evimg> MELLOW_EVOTO_OUT=/private/tmp/claude-501/-Users-mj-IdeaProjects-mellow-photo/<session>/scratchpad/g5/phaseb MELLOW_EVOTO_CANDIDATES=1 swift test --filter EvotoCalibrationTests/testMeasureOneTouchAgainstEvotoPairs
```

→ 약 16분. `metrics.md`의 묶음별 중앙값에서 `app`·`female`·`male`(G5 표)과 `legacy`·`evoto` 줄을 읽고 스펙 1.1 경계와 대조해 결과를 **스크래치패드 `g5/phaseb/summary.md`**에 적는다(VALIDATION은 G5-3이 쓴다). 경계 미달 항목은 상수 조정 규칙(Task 4)으로 한 번 고치고 다시 잰다. `zoom.png`에서 `blemish-removal_…_app.zoom.png`에 원반이 없는지, `wrinkle-remover-for-face_…_app.zoom.png`에서 콧구멍이 밝아지지 않는지 눈으로 본다(Read 도구).

- [ ] **Step 4: 커밋**

```bash
git add apple/Tests/MellowRenderingTests/EvotoCalibrationTests.swift
git commit -m "test(rendering): Evoto 하네스에서 점 지우기 시제품을 지우고 1.4.0 표를 legacy 계열로 잼

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

## 자체 검토 결과

- **스펙 대조:** 3절 키·스키마·화면 이름 → Task 1. 2절 `spots`·`autoBlemish` → Task 1. 4.2 마스크·캐시 → Task 2. 4.1 상수·4.3 식·굳히기·대안·4.4 단위 테스트 → Task 3. 1.2 심은 점 행·무복제 행 → Task 4. 7절 하네스 → Task 5. 9절 "G5-2 5 Task"와 같다.
- **타입 일관성:** `SkinRefinementKey.spots`, `OneTouchBundle.Values.spots`, `FaceRegions.spotExclusionPolygons`·`spotExclusionRaster`·`spotMask`, `SpotRemoval.apply`·`thresholds`, `SkinKernels.spot`·`spotApply`, `RealPortrait.spotGrid`·`spotExclusionMask`, `Support.closingDarkMean`, `EvotoCalibrationTests.Legacy`를 정의한 Task와 쓰는 Task에서 같게 썼다.
- **Review Focus 매핑:** 1·2·4·6 → Task 3, 2·3 → Task 4(+Task 2), 5 → Task 1·4.
- **플레이스홀더 점검:** 상수는 스펙 4.1 값이고 조정 규칙을 적었다. Task 5 Step 3의 `<evimg>`·`<session>`은 코디네이터가 주는 로컬 경로다(저장소 밖). "TBD/TODO" 없음.
