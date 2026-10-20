# 인물 보정 H2 규칙·렌더(얼굴별 값·층 편집·targetFace 이행) 구현 계획

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 렌더가 얼굴마다 해석한 값(`FaceTarget`)으로 돌고, 편집이 전체·성별 그룹·개인 층을 가리켜 값을 쓰고 지우며, 프리셋·동기화가 층 규칙을 따르고, 성별 자동 추정 포트가 생긴다(구현은 H4). 마지막 Task에서 옛 `targetFace`를 읽기 이행으로 바꾸고 속성을 없앤다. 앱은 컴파일과 기본 동작이 유지되는 최소 변경(임시 대상 피커)만 받고 화면은 H3이 만든다.

**Architecture:** `RenderContext`가 `PersonMatcher`·`PortraitResolver`로 얼굴마다 `FaceTarget`을 만들고 `skin`·`feature`·`makeup`·`shapeWarp` 네 단계는 그 목록을 돈다(새 단계·마스크·캐시 없음). `EditDocument.set(_:in:)`·`set(_:forPersonAt:)`·`resetOverrides`가 층을 쓰고, `merged`가 G3의 `SyncCategory`를 그대로 써서 전체·그룹 층을 복사하고 얼굴 의존 항목의 개인 키를 지운다. `GenderEstimator`는 `FaceAnalyzer`와 같은 포트이고 `PhotoPipeline`이 기본 nil로 받는다. Task 1~4는 `targetFace`를 건드리지 않아 옛 세션 렌더가 그대로이고, Task 5가 한 번에 이행·제거·앱 최소 변경을 한다.

**Tech Stack:** Swift 5.9 tools / Swift 5 언어 모드, Core Image(기존 단계), SwiftUI + Observation(앱 최소 변경), XCTest.

**Spec:** `docs/superpowers/specs/2026-10-21-beauty-h-per-person-design.md` (H2에 해당하는 절: 1.1, 1.2의 읽기 이행·적용 순서, 1.4, 1.5, 2의 편집·렌더 행, 5). 선행: H1 계획 전부 머지.

## 사람이 확인할 것

### G4 개정 (2026-10-21)

[G4 스펙](../specs/2026-10-21-beauty-g4-one-touch-design.md) 5절에 따라 이 계획의 제약을 고쳤다. 결정은 바뀌지 않았다.

- 기준 코드: main `74fb2df`(1.3.0 (8.1) TestFlight, G 머지됨). 브랜치 `beauty-g4`(worktree를 쓰면 `.claude/worktrees/beauty-g4`). `beauty-g-evoto`·`.claude/worktrees/beauty-g`는 더 쓰지 않는다.
- **iOS 시뮬레이터 테스트는 로컬에서 돌리지 않는다**(SpringBoard 오류 창이 사용자를 방해함). `MELLOW_IOS_TESTS`를 켜지 않는다. `./scripts/test-apple.sh`는 로컬에서 iOS를 건너뛰며 iOS 검증은 CI(사용자가 요금 한도를 푼 뒤)다.
- 실행 순서: G4-1 → H3 Task 1(생성 사진) → H1 → H2 → G4-2 → H3 Task 2·3 → G4-3 → H3 Task 4 → (승인 시) H4.
- G4-2가 뒤에 `EditDocument.commit`에 `clearsStaleMarks` 인자와 `applyOneTouch`를 더하고 `merged`에 `oneTouch` 표시 규칙을 넣는다. H2의 `commit`·`merged`·`copy`·`resetAllLayer`·`appendPerson`은 그 확장이 가능하게 `private static`/`private mutating`으로 두되 이름을 바꾸지 않는다.

- **순서.** Task 1 렌더 얼굴별 값 → 2 성별 추정 포트 → 3 층 편집 규칙 → 4 프리셋·동기화 층 규칙 → 5 `targetFace` 이행·제거와 앱 최소 변경. 5개 Task, Task마다 Opus 구현 → 리뷰 → 수정, 끝에 전체 리뷰.
- **외부 효과가 있는 단계.** 없음.
- **스펙이 정하지 않아 이 계획이 정한 것.**

| 결정 | 이유 | 바꾸면 비용 |
|---|---|---|
| Task 1~4 동안 옛 `targetFace`는 "전체 층을 그 얼굴에만"이라는 지금 뜻을 유지한 채 `people`과 함께 동작한다. Task 5가 한 번에 이행·제거한다 | 어느 커밋에서도 옛 세션의 렌더 결과가 바뀌지 않는다(스펙 1.2 적용 순서) | 작음 |
| 자동 잡티는 사람마다 켜고 끈다. 단계는 켜진 얼굴의 잡티만 지운 뒤 모든 얼굴을 다듬는다(지금 순서 유지) | 잡티 복구가 다른 얼굴의 다듬기 뒤에 오면 복제 원본이 이미 바뀐 픽셀이 된다 | 작음 |
| 층에서 룩 "없음"은 다섯 부위를 0으로 **덮어쓴다**(상속이 아님). 상속으로 돌리는 것은 "재설정" | "이 사람은 메이크업 없이"가 룩 없음의 뜻이고, 전체 층의 룩 없음(모두 지움)과 같은 결과를 그 사람에게 준다 | 작음 |
| 층에 메이크업 색을 처음 고를 때의 기본 강도는 그 층 아래 값(전체 ⊕ 수동 성별 그룹)을 기준으로 한다 | 편집 규칙은 자동 추정을 모른다. 추정 성별로만 그룹이 걸린 사람은 아주 드문 경우에 기본 강도 기준이 다를 수 있고, 다음 드래그가 바로 고친다 | 작음 |
| 잠긴 사진에서 성별 변경은 그룹의 얼굴형 키와 무관하게 늘 거절한다(스펙 결정 표와 같음, H2 구현 중 변경). 사람 삭제·다시 연결은 그 기록 층이나 기록의 수동 성별 그룹 층에 얼굴형 키가 있을 때만 거절한다 | 성별 규칙은 스펙 결정 표를 따른다(조건부로 두면 두 사람 확인 영역이 어긋난다). 삭제·연결은 얼굴형이 안 걸리면 잠긴 사진에서도 찾지 못한 사람을 정리할 수 있게 한다 | 작음 |
| 동기화 때 개인 키 제거는 실제로 복사한 항목에 대해서만 한다. 잠긴 사진에서 건너뛴 얼굴형은 개인 층에서도 지우지 않는다 | 잠금의 뜻(수동 편집 좌표 보존)과 같다 | 작음 |
| 추정 임계값(신뢰도·얼굴 폭·yaw)은 준비 때 한 번 적용하고 통과한 추정만 `PhotoAnalysis`에 둔다 | 렌더·앱이 같은 값을 보고 임계값 로직이 한 곳이다 | 작음 |
| 이행용 `EditRecipe.migrateLegacyTargetFace(_:)`를 public으로 두어 v1 세션 변환(MellowLibrary)과 테스트 지원이 같은 함수를 쓴다 | 이행 규칙이 두 군데 생기지 않는다 | 작음 |
| 앱 최소 변경: `BeautyTarget`(전체·성별·얼굴 n·찾지 못한 사람)과 라우팅만 넣고 화면은 임시 `Picker`(전체 / 사람 n) | 컴파일과 기본 동작을 유지하는 최소치. 칩·성별 메뉴·덮어쓰기 표시는 H3 | 작음 |

- **범위 밖(다른 계획).** 대상 칩·성별 메뉴·재설정 UI·캔버스 탭·생성 사진·VALIDATION(H3), Core ML 추정기(H4).
- **위험.** Task 5는 여러 모듈·테스트를 한 번에 바꾸는 큰 Task다. 리뷰는 "옛 세션 렌더 바이트 동일"(Review Focus 1)을 먼저 본다. 이행 뒤 옛 사진은 "전체"에서 값이 0으로 보이고 "사람 i"에서 값이 보인다(스펙 위험 항목, H3 VALIDATION에 적음).
- **사용자 조치.** 없음(화면 확인은 H3 뒤).

---

## 에이전트 참조

## Global Constraints

H1 계획의 Global Constraints(G4 개정 포함: 브랜치 `beauty-g4`, 로컬 iOS 시뮬레이터 금지)를 그대로 따른다(`DEVELOPER_DIR`·모듈 표 불변·lint·커밋 서명·`git add` 경로 제한). 이 계획에서 다른 것:

- 시작 조건: H1 머지(`PeopleAdjustments`·`PortraitResolver`·`PersonMatcher` 존재). 기준 테스트 수는 **시작 전에 실측해 이 줄에 적는다**(H1 Global Constraints 참고). 이 계획이 더하는 수는 **Rendering +6, Editing +7, Library +1, Shared +2**(Task 1 Rendering +4, Task 2 Rendering +2, Task 3 Editing +5, Task 4 Editing +2·Library +1, Task 5 Shared +2), 앱 Mac 0(테스트 이름 교체만). 아래의 "Executed N tests"는 명목치(H1 끝 명목 387 → 403, Mac 78)이므로 실측 기준값에 같은 증분을 더해 읽는다.
- MellowRendering은 `CoreImage`·`Foundation`·`MellowShared`·`Vision`만 import한다. `GenderEstimator`는 프로토콜만이고 Core ML을 import하지 않는다.
- 파이프라인 단계 이름 순서 불변(`skin, bodySkin, feature, makeup, background, shapeWarp, localEdit, geometry, color, detail, look, effect`). 새 단계 없음. `RegionMaskCache` 상한 불변.
- `RenderTuning` 새 상수(Task 2): `genderMinConfidence` 0.75, `genderMinFaceWidth` 0.05, `genderMaxYaw` 0.6.
- 값 범위 클램프는 층에서도 `EditingPolicy`의 같은 함수. 렌더는 `AdjustmentRange`로 직접 자른다(기존).
- Task 5 전까지 `PortraitAdjustments.targetFace`·`EditChange.targetFace`·`RenderContext.targetFaces`·`targetBlemishes`는 그대로 두고 기존 테스트가 통과해야 한다. Task 5가 넷을 모두 없애고 테스트를 옮긴다.
- 앱 파일을 더하지 않는다(Task 5는 기존 파일만 고침) → `xcodegen generate` 불필요. Mac 앱 테스트는 Task 5에서 돌린다.
- 패키지 테스트: `cd apple && swift test`. Mac 앱 테스트 명령은 H1과 같다.

## Review Focus

1. **G까지 저장한 세션(`targetFace = 1`, 피부 0.5)을 H2 끝에서 연다.** `portrait.skin.smoothing`은 0이고 `people.individuals[0]`이 `legacyIndex 1`·피부 0.5이며, 두 얼굴 사진의 렌더 바이트가 Task 5 전과 같아야 한다. → Task 5 `testLegacyTargetFaceMigratesIntoAPersonRecord`(Shared), `testTargetFaceLimitsPortraitStagesToOneFace`(Rendering, 이행된 레시피로 재작성), `testV1SessionDecodesToV2Snapshot`(Library, 단언 갱신).
2. **개인 층만 바꾼 사진.** 그 얼굴만 바뀌고 다른 얼굴은 한 픽셀도 바뀌지 않아야 한다. → Task 1 `testIndividualLayerSmoothsOnlyThatFace`.
3. **여성 그룹에 립을 넣고 한 사람만 여성으로 지정.** 그 사람만 바뀌고, 둘 다 지정하면 둘 다 바뀌어야 한다. → Task 1 `testGenderGroupPaintsOnlyFacesOfThatGender`.
4. **잠긴 사진에서 성별을 바꾸려 한다.** 그룹의 얼굴형 키와 무관하게 거절되어야 한다(스펙 결정 표, H2 구현 중 변경). 같은 사진에서 피부·눈입 같은 얼굴형이 아닌 키는 어느 층에서든 허용. → Task 3 `testGenderAssignmentIsLockedByLocalEditsAndNeedsAPerson`.
5. **색감만 동기화.** 받는 사진의 개인 층·성별이 그대로여야 하고, 피부를 동기화하면 개인 층의 피부 키만 빠지고 얼굴형 키·성별은 남아야 한다. → Task 4 `testBatchSyncCopiesGroupsAndClearsIndividualKeysOfSyncedCategories`.
6. **추정기가 얼굴 수와 다른 길이를 돌려주거나 던진다.** 준비는 성공하고 추정은 모두 nil이어야 한다. → Task 2 `testGenderEstimatesAreThresholdedAndFailuresAreSilent`.

## 인터페이스 요약 (모든 Task가 공유하는 이름)

```swift
// MellowRendering (Task 1)
public struct FaceTarget: Sendable { index: Int; face: FaceGeometry; personID: PersonID?; gender: Gender?;
    portrait: PortraitAdjustments; makeup: MakeupAdjustments; blemishes: [BlemishSpot] }
RenderContext.faceTargets: [FaceTarget]; static makeTargets(recipe:analysis:) -> [FaceTarget]
SkinStage.healSpots(for: FaceTarget, in: RenderContext) -> [RetouchSpot]      // healSpots(in:)는 모든 대상을 평탄화
// 테스트 지원 (Task 1)
SyntheticFace.pair(_:renderer:) throws -> (image: CIImage, faces: [FaceGeometry])
RenderingTestSupport.changedPixelsByHalf(_:_:) -> (left: Int, right: Int)

// MellowRendering (Task 2)
public struct GenderEstimate: Equatable, Sendable { gender: Gender; confidence: Double }
public protocol GenderEstimator: Sendable { func estimate(_ image: CIImage, faces: [FaceGeometry]) throws -> [GenderEstimate?] }
PhotoAnalysis.genderEstimates: [GenderEstimate?]            // faces와 같은 길이이거나 빈 배열
PhotoPipeline.init(analyzer:personAnalyzer:bodyAnalyzer:genderEstimator:tuning:lookCatalog:makeupCatalog:)
PhotoPipeline.acceptedEstimates(_:faces:tuning:) -> [GenderEstimate?]   // 임계값 적용, 길이 불일치면 모두 nil
PreparedPhoto.genders: [Gender?]
RenderTuning.genderMinConfidence, genderMinFaceWidth, genderMaxYaw

// MellowEditing (Task 3)
EditChange.gender(Gender?)                                   // affectsGeometry true
EditChange.portraitKey: PortraitKey?
EditDocument.Rejection.unknownPerson
EditDocument.set(_:in: PortraitScope = .all), set(_:forPersonAt: PersonAnchor), resetOverrides(_:in:),
    rebindPerson(_:to:), removePerson(_:), bindLegacyPeople(faces:) -> Bool, applyMakeupLook(_:in: = .all)

// MellowEditing·MellowLibrary (Task 4)
EditDocument.apply(_:)·applyFromBatch(_:categories:)가 people.groups를 복사하고 얼굴 의존 항목의 개인 키를 지움
SyncCategory.portraitKeys: Set<PortraitKey>?                 // skin·faceShape·features·makeup만 값이 있음

// Task 5
EditRecipe.migrateLegacyTargetFace(_ index: Int)             // public, Library v1 변환과 테스트 지원이 씀
PortraitAdjustments.targetFace 제거, EditChange.targetFace 제거, RenderContext.targetFaces·targetBlemishes 제거
RenderingTestSupport.restricted(_ recipe:, toFace:, of faces:) -> EditRecipe
AppModel.BeautyTarget { all, gender(Gender), face(Int), person(PersonID) }, beautyTargets, beautyTarget, setBeautyTarget(_:)
AppModel.anchor(forFace:) -> PersonAnchor?, scope(for:) -> PortraitScope?
UserMessage.beautyTargetLabel, beautyTargetAll, beautyTargetFace(_:)
```

---

### Task 1: 렌더 — FaceTarget과 네 단계의 얼굴별 값

**Files:**
- Modify: `apple/Sources/MellowRendering/API/RenderStage.swift`
- Modify: `apple/Sources/MellowRendering/Domain/SkinStage.swift`, `FeatureStage.swift`, `MakeupStage.swift`, `ShapeWarpStage.swift`
- Modify: `apple/Tests/MellowRenderingTests/RenderingTestSupport.swift`
- Test: `apple/Tests/MellowRenderingTests/RenderPipelineTests.swift`, `SkinStageTests.swift`, `MakeupStageTests.swift`, `ShapeWarpStageTests.swift`

**Interfaces:**
- Consumes: `PersonMatcher.match`, `PortraitResolver.resolve(_:person:gender:)`, `PeopleAdjustments.person`.
- Produces: 인터페이스 요약의 Task 1 항목. `targetFaces`·`targetBlemishes`는 `faceTargets`에서 계산하는 속성으로 남긴다(Task 5가 지움).

설계 근거: 스펙 1.5. 단계는 이미 얼굴마다 반복하므로 반복 안의 값만 얼굴마다 다르게 준다.

- [ ] **Step 1: 실패하는 테스트 작성**

`RenderingTestSupport.swift`의 `SyntheticFace` 확장 끝에 추가:

```swift
extension SyntheticFace {
    /// 반 크기 합성 얼굴 둘을 좌우에 놓는다. faces[0]이 왼쪽(x 0…0.5), faces[1]이 오른쪽. MakeupStageTests의 대상 얼굴 배치와 같다.
    static func pair(_ synthetic: SyntheticFace, renderer: Renderer) throws -> (image: CIImage, faces: [FaceGeometry]) {
        let half = CGAffineTransform(scaleX: 0.5, y: 0.5)
        let side = CGFloat(size)
        let left = synthetic.image.transformed(by: half.concatenating(CGAffineTransform(translationX: 0, y: side / 4)))
        let right = synthetic.image.transformed(
            by: half.concatenating(CGAffineTransform(translationX: side / 2, y: side / 4)))
        let composed = left.composited(over: right).composited(over: CIImage(color: .gray)).cropped(to: extent)
        let image = CIImage(cgImage: try renderer.makeCGImage(composed))
        let faces = [
            synthetic.face.transformed(scale: 0.5, offset: NormalizedPoint(x: 0, y: 0.25)),
            synthetic.face.transformed(scale: 0.5, offset: NormalizedPoint(x: 0.5, y: 0.25)),
        ]
        return (image, faces)
    }
}
```

`RenderingTestSupport` enum 안에 추가:

```swift
    /// 두 격자가 다른 픽셀 수를 왼쪽 절반·오른쪽 절반으로 나눠 센다. 격자 크기는 같아야 한다.
    static func changedPixelsByHalf(_ before: PixelGrid, _ after: PixelGrid) -> (left: Int, right: Int) {
        var left = 0
        var right = 0
        for y in 0..<before.height {
            for x in 0..<before.width {
                let point = CGPoint(x: x, y: y)
                guard after.rgba(point) != before.rgba(point) else { continue }
                if x < before.width / 2 {
                    left += 1
                } else {
                    right += 1
                }
            }
        }
        return (left, right)
    }
```

(`PixelGrid`에 `width`·`height`가 없으면 추가한다. 있으면 그대로 쓴다.)

`RenderPipelineTests.swift` 끝에 추가:

```swift
    func testFaceTargetsResolvePeopleLayersPerFace() {
        let left = FaceGeometry(boundingBox: NormalizedRect(x: 0.05, y: 0.1, width: 0.35, height: 0.8))
        let right = FaceGeometry(boundingBox: NormalizedRect(x: 0.6, y: 0.1, width: 0.35, height: 0.8))
        let spots = [
            BlemishSpot(x: 0.2, y: 0.2, radius: 0.01, faceIndex: 0),
            BlemishSpot(x: 0.7, y: 0.2, radius: 0.01, faceIndex: 1),
        ]
        var recipe = EditRecipe()
        recipe.portrait.skin.smoothing = 0.2
        recipe.people.groups[.female] = PortraitLayer(skinSmoothing: 0.5, features: [.eyeBrighten: 0.3])
        let id = PersonID()
        recipe.people.individuals = [
            PersonRecord(
                id: id, anchor: PersonAnchor(faceBox: right.boundingBox), gender: .female,
                layer: PortraitLayer(skinSmoothing: 0.9, face: [.jaw: 0.4])),
            PersonRecord(anchor: PersonAnchor(x: 0.5, y: 0.98, width: 0.01), layer: PortraitLayer(skinSmoothing: 1)),
        ]
        let extent = CGRect(x: 0, y: 0, width: 64, height: 64)
        let context = RenderContext(
            extent: extent, recipe: recipe, faces: [left, right], tuning: RenderTuning(), blemishes: spots)
        XCTAssertEqual(context.faceTargets.map(\.index), [0, 1])
        let first = context.faceTargets[0]
        XCTAssertNil(first.personID)
        XCTAssertNil(first.gender)
        XCTAssertEqual(first.portrait.skin.smoothing, 0.2, "짝이 없는 얼굴은 전체 값")
        XCTAssertEqual(first.blemishes, [spots[0]])
        let second = context.faceTargets[1]
        XCTAssertEqual(second.personID, id)
        XCTAssertEqual(second.gender, .female)
        XCTAssertEqual(second.portrait.skin.smoothing, 0.9)
        XCTAssertEqual(second.portrait.features.eyeBrighten, 0.3, "그룹 값은 상속")
        XCTAssertEqual(second.portrait.face.jaw, 0.4)
        XCTAssertEqual(second.blemishes, [spots[1]])
        XCTAssertEqual(context.targetFaces, [left, right])
        XCTAssertEqual(context.targetBlemishes, spots)
        var legacy = recipe
        legacy.portrait.targetFace = 0
        let restricted = RenderContext(extent: extent, recipe: legacy, faces: [left, right], tuning: RenderTuning())
        XCTAssertEqual(restricted.faceTargets.map(\.index), [0], "Task 5 전까지 옛 targetFace는 그 얼굴만 남긴다")
    }
```

`SkinStageTests.swift` 끝에 추가:

```swift
    func testIndividualLayerSmoothsOnlyThatFace() throws {
        let pair = try SyntheticFace.pair(SyntheticFace.make(), renderer: Support.renderer)
        var recipe = EditRecipe()
        recipe.people.individuals = [
            PersonRecord(anchor: PersonAnchor(faceBox: pair.faces[0].boundingBox), layer: PortraitLayer(skinSmoothing: 1))
        ]
        let context = RenderContext(extent: pair.image.extent, recipe: recipe, faces: pair.faces, tuning: RenderTuning())
        let before = try Support.grid(pair.image)
        let after = try Support.grid(SkinStage().apply(pair.image, in: context))
        let changed = Support.changedPixelsByHalf(before, after)
        XCTAssertGreaterThan(changed.left, 0, "개인 층이 있는 왼쪽 얼굴만 바뀐다")
        XCTAssertEqual(changed.right, 0, "다른 얼굴은 한 픽셀도 바뀌지 않는다")
        var unmatched = EditRecipe()
        unmatched.people.individuals = [
            PersonRecord(anchor: PersonAnchor(x: 0.5, y: 0.98, width: 0.02), layer: PortraitLayer(skinSmoothing: 1))
        ]
        let idle = RenderContext(extent: pair.image.extent, recipe: unmatched, faces: pair.faces, tuning: RenderTuning())
        XCTAssertEqual(
            try Support.bytes(SkinStage().apply(pair.image, in: idle)), try Support.bytes(pair.image),
            "짝이 없는 기록은 아무 얼굴도 바꾸지 않는다")
        var perFaceBlemish = EditRecipe()
        perFaceBlemish.people.individuals = [
            PersonRecord(anchor: PersonAnchor(faceBox: pair.faces[1].boundingBox), layer: PortraitLayer(autoBlemish: true))
        ]
        let spots = [
            BlemishSpot(x: 0.2, y: 0.5, radius: 0.004, faceIndex: 0), BlemishSpot(x: 0.7, y: 0.5, radius: 0.004, faceIndex: 1),
        ]
        let healing = RenderContext(
            extent: pair.image.extent, recipe: perFaceBlemish, faces: pair.faces, tuning: RenderTuning(), blemishes: spots)
        XCTAssertEqual(Set(SkinStage.healSpots(in: healing).map(\.x)), [0.7], "자동 잡티가 켜진 사람의 잡티만 지운다")
    }
```

`MakeupStageTests.swift` 끝에 추가:

```swift
    func testGenderGroupPaintsOnlyFacesOfThatGender() throws {
        let pair = try SyntheticFace.pair(SyntheticFace.makeFeatures(), renderer: Support.renderer)
        let catalog = try Support.sharedMakeupCatalog()
        func rendered(genders: [Gender?]) throws -> CIImage {
            var recipe = EditRecipe()
            recipe.people.groups[.female] = PortraitLayer(makeup: [.lip: MakeupTint(colorID: "lip-red", intensity: 1)])
            recipe.people.individuals = zip(pair.faces, genders).compactMap { face, gender in
                gender.map { PersonRecord(anchor: PersonAnchor(faceBox: face.boundingBox), gender: $0) }
            }
            let context = RenderContext(
                extent: pair.image.extent, recipe: recipe, faces: pair.faces, tuning: RenderTuning(),
                makeupCatalog: catalog)
            return try MakeupStage().apply(pair.image, in: context)
        }
        let before = try Support.grid(pair.image)
        let rightOnly = Support.changedPixelsByHalf(before, try Support.grid(rendered(genders: [nil, .female])))
        XCTAssertEqual(rightOnly.left, 0, "미지정인 사람은 그룹 값을 받지 않는다")
        XCTAssertGreaterThan(rightOnly.right, 0)
        let both = Support.changedPixelsByHalf(before, try Support.grid(rendered(genders: [.female, .female])))
        XCTAssertGreaterThan(both.left, 0)
        XCTAssertGreaterThan(both.right, 0)
        let male = Support.changedPixelsByHalf(before, try Support.grid(rendered(genders: [.male, nil])))
        XCTAssertEqual(male.left + male.right, 0, "다른 그룹은 받지 않는다")
    }
```

`ShapeWarpStageTests.swift` 끝에 추가(기존 `context(_:faces:targetFace:)` 도우미를 쓴다):

```swift
    func testIndividualFaceShapeMakesPrimitivesOnlyForThatFace() throws {
        let leftFace = SyntheticFace.make().face.transformed(scale: 0.5, offset: NormalizedPoint(x: 0, y: 0.25))
        let rightFace = SyntheticFace.make().face.transformed(scale: 0.5, offset: NormalizedPoint(x: 0.5, y: 0.25))
        var recipe = EditRecipe()
        recipe.people.individuals = [
            PersonRecord(anchor: PersonAnchor(faceBox: leftFace.boundingBox), layer: PortraitLayer(face: [.width: -1]))
        ]
        let individual = RenderContext(
            extent: SyntheticFace.extent, recipe: recipe, faces: [leftFace, rightFace], tuning: RenderTuning())
        let legacy = context(FaceShapeAdjustments(width: -1), faces: [leftFace, rightFace], targetFace: 0)
        let stage = ShapeWarpStage()
        let fromIndividual = stage.facePrimitives(in: individual)
        XCTAssertGreaterThan(fromIndividual.count, 0)
        XCTAssertEqual(fromIndividual.count, stage.facePrimitives(in: legacy).count, "옛 대상 얼굴과 같은 원소 수")
        let everyone = context(FaceShapeAdjustments(width: -1), faces: [leftFace, rightFace])
        XCTAssertEqual(stage.facePrimitives(in: everyone).count, fromIndividual.count * 2)
    }
```

- [ ] **Step 2: 실패 확인**

Run: `cd apple && swift test --filter "RenderPipelineTests|SkinStageTests|MakeupStageTests|ShapeWarpStageTests"` → 컴파일 실패(`faceTargets` 없음).

- [ ] **Step 3: 구현**

`RenderStage.swift`: `RenderContext` 앞에 `FaceTarget`을 두고 `RenderContext`의 `targetFaces`·`targetBlemishes` 저장 속성과 `init` 안의 분기를 다음으로 바꾼다.

```swift
/// 렌더할 얼굴 하나와 그 얼굴에 해석된 값(전체 → 성별 그룹 → 개인). 네 얼굴 단계가 이 목록을 돈다.
public struct FaceTarget: Sendable {
    /// analysis.faces 안 인덱스.
    public let index: Int
    public let face: FaceGeometry
    /// 짝이 된 사람 기록. 없으면 nil.
    public let personID: PersonID?
    /// 유효 성별(수동 지정 ?? 추정). 없으면 그룹 층을 받지 않는다.
    public let gender: Gender?
    public let portrait: PortraitAdjustments
    public let makeup: MakeupAdjustments
    /// 이 얼굴의 자동 잡티.
    public let blemishes: [BlemishSpot]

    public init(
        index: Int, face: FaceGeometry, personID: PersonID?, gender: Gender?, portrait: PortraitAdjustments,
        makeup: MakeupAdjustments, blemishes: [BlemishSpot]
    ) {
        self.index = index
        self.face = face
        self.personID = personID
        self.gender = gender
        self.portrait = portrait
        self.makeup = makeup
        self.blemishes = blemishes
    }
}
```

`RenderContext` 안:

```swift
    /// 얼굴마다 해석한 값. 짝이 없는 사람 기록은 어느 얼굴에도 들어가지 않는다.
    public let faceTargets: [FaceTarget]
    /// faceTargets의 얼굴. (H2 Task 5에서 제거)
    public var targetFaces: [FaceGeometry] { faceTargets.map(\.face) }
    /// faceTargets의 잡티. (H2 Task 5에서 제거)
    public var targetBlemishes: [BlemishSpot] { faceTargets.flatMap(\.blemishes) }
```

`init`의 `let faces = analysis.faces` 이하를 `faceTargets = Self.makeTargets(recipe: recipe, analysis: analysis)`로 바꾸고 다음을 더한다:

```swift
    /// 사람 기록을 얼굴에 짝짓고 얼굴마다 층을 겹친다. Task 5 전까지 옛 targetFace는 전체 층을 그 얼굴에만 건다.
    static func makeTargets(recipe: EditRecipe, analysis: PhotoAnalysis) -> [FaceTarget] {
        let faces = analysis.faces
        let matches = PersonMatcher.match(recipe.people.individuals, faces: faces.map(\.boundingBox))
        var personByFace: [Int: PersonRecord] = [:]
        for match in matches {
            personByFace[match.faceIndex] = recipe.people.person(match.person)
        }
        return faces.indices.compactMap { index in
            if let legacy = recipe.portrait.targetFace, legacy != index {
                return nil
            }
            let person = personByFace[index]
            let gender = person?.gender
            let resolved = PortraitResolver.resolve(recipe, person: person, gender: gender)
            return FaceTarget(
                index: index, face: faces[index], personID: person?.id, gender: gender, portrait: resolved.portrait,
                makeup: resolved.makeup, blemishes: analysis.blemishes.filter { $0.faceIndex == index })
        }
    }
```

`SkinStage.apply`를 다음으로 바꾸고 `healSpots(in:)`는 `faceTargets`를 평탄화하는 껍데기로, 본문은 `healSpots(for:in:)`으로 옮긴다(`rules`는 그 얼굴 하나, `others`는 그 대상의 다른 잡티):

```swift
    func apply(_ image: CIImage, in context: RenderContext) throws -> CIImage {
        let targets = context.faceTargets.map { ($0, Self.clamped($0.portrait.skin)) }.filter { $0.1.hasEffect }
        guard !targets.isEmpty else { return image }
        let extent = context.extent
        var result = image
        for (target, skin) in targets where skin.autoBlemish {
            for heal in Self.healSpots(for: target, in: context) {
                result = LocalEditStage.applySpot(heal, to: result, context: context)
            }
        }
        for (target, skin) in targets where skin.smoothing > 0 || skin.hasRefinement {
            result = try refine(result, face: target.face, skin: skin, context: context)
        }
        return result.cropped(to: extent)
    }

    /// 모든 대상의 복제 원. 테스트·호환용.
    static func healSpots(in context: RenderContext) -> [RetouchSpot] {
        context.faceTargets.flatMap { healSpots(for: $0, in: context) }
    }

    /// 한 대상의 잡티를 덮는 복제 원. 얼굴 인덱스가 범위 밖이면 빈 배열.
    static func healSpots(for target: FaceTarget, in context: RenderContext) -> [RetouchSpot] {
        guard context.faces.indices.contains(target.index), !target.blemishes.isEmpty else { return [] }
        let rules = SourceRules(face: target.face, members: target.blemishes, in: context)
        return target.blemishes.indices.compactMap { index in
            let blemish = target.blemishes[index]
            let others = target.blemishes.enumerated().filter { $0.offset != index }.map(\.element)
            return healSpot(for: blemish, in: context, rules: rules, others: others)
        }
    }
```

`healSpots(in:)`가 `faceTargets`를 평탄화하므로 Task 5 전까지 옛 `targetFace`도 그대로 동작한다. 그런데 위 `apply`는 `skin.autoBlemish`가 사람마다 다르므로 `healSpots(in:)`를 쓰지 않고 대상별로 부른다. 테스트의 `SkinStage.healSpots(in: healing)` 단언은 `autoBlemish`와 무관하게 모든 대상의 복제 원을 돌려주므로 두 사람 잡티가 다 나온다 — 그래서 테스트 단언은 `healSpots(in:)`가 아니라 렌더 결과가 아닌 `apply`가 쓰는 규칙으로 바꿔야 한다. `healSpots(in:)`를 "자동 잡티가 켜진 대상만" 평탄화하도록 정의한다:

```swift
    /// 자동 잡티가 켜진 대상의 복제 원 전부.
    static func healSpots(in context: RenderContext) -> [RetouchSpot] {
        context.faceTargets.filter { clamped($0.portrait.skin).autoBlemish }.flatMap { healSpots(for: $0, in: context) }
    }
```

기존 `healSpots(in:)`를 쓰던 테스트는 `autoBlemish = true`인 레시피로 부르므로 결과가 같다(실행해서 확인하고 다르면 그 테스트의 레시피에 `autoBlemish = true`를 더한다).

`FeatureStage.apply`:

```swift
    func apply(_ image: CIImage, in context: RenderContext) throws -> CIImage {
        let targets = context.faceTargets.map { ($0.face, Self.clamped($0.portrait.features)) }.filter { $0.1.hasEffect }
        guard !targets.isEmpty else { return image }
        var result = image
        for (face, values) in targets {
            result = try brightenEyes(result, face: face, amount: values.eyeBrighten, context: context)
            result = try whitenTeeth(result, face: face, amount: values.teethWhiten, context: context)
            result = try reviveLips(result, face: face, amount: values.lipVitality, context: context)
        }
        return result.cropped(to: context.extent)
    }
```

`MakeupStage.apply`: 같은 틀로 `($0.face, Self.clamped($0.makeup))`를 돌고 다섯 부위에 그 얼굴의 `makeup`을 넘긴다. `ShapeWarpStage.facePrimitives`:

```swift
    func facePrimitives(in context: RenderContext) -> [ShapePrimitive] {
        context.faceTargets.flatMap { target -> [ShapePrimitive] in
            let adjustments = target.portrait.face
            guard adjustments.hasEffect else { return [] }
            return FaceShapeRig.primitives(
                face: target.face, adjustments: adjustments, extent: context.extent, tuning: context.tuning)
        }
    }
```

- [ ] **Step 4: 통과 확인**

Run: `cd apple && swift test --filter MellowRenderingTests` → `Executed 261 tests, with 0 failures`(기존 `targetFace` 테스트 전부 통과). lint 출력 없음. `./scripts/verify-modules.sh` 통과.

- [ ] **Step 5: 커밋**

```bash
git add apple/Sources/MellowRendering/API/RenderStage.swift apple/Sources/MellowRendering/Domain/SkinStage.swift apple/Sources/MellowRendering/Domain/FeatureStage.swift apple/Sources/MellowRendering/Domain/MakeupStage.swift apple/Sources/MellowRendering/Domain/ShapeWarpStage.swift apple/Tests/MellowRenderingTests/RenderingTestSupport.swift apple/Tests/MellowRenderingTests/RenderPipelineTests.swift apple/Tests/MellowRenderingTests/SkinStageTests.swift apple/Tests/MellowRenderingTests/MakeupStageTests.swift apple/Tests/MellowRenderingTests/ShapeWarpStageTests.swift
git commit -m "feat(rendering): 얼굴마다 전체·성별 그룹·개인 층을 겹친 FaceTarget으로 네 단계 렌더

PersonMatcher로 사람 기록을 얼굴에 짝짓고 PortraitResolver로 값을 겹친다.
자동 잡티도 사람별. 옛 targetFace 제한은 이행 전까지 유지.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 2: 성별 추정 포트 — GenderEstimator, PhotoAnalysis.genderEstimates, 임계값

**Files:**
- Create: `apple/Sources/MellowRendering/API/GenderEstimator.swift`
- Modify: `apple/Sources/MellowRendering/API/PhotoAnalysis.swift`, `PhotoPipeline.swift`, `RenderTuning.swift`, `RenderStage.swift`(`makeTargets`가 추정을 씀)
- Test: `apple/Tests/MellowRenderingTests/PhotoPipelineTests.swift`, `RenderingTestSupport.swift`(스텁)

**Interfaces:**
- Consumes: `FaceGeometry.boundingBox`·`yaw`, `PortraitResolver.effectiveGender`.
- Produces: 인터페이스 요약의 Task 2 항목. 기본 구현 없음(H4).

설계 근거: 스펙 1.5. 추정은 보조 정보라 실패 사유를 `PreparedPhoto`에 두지 않고 조용히 빈 배열이다. 임계값은 준비 때 한 번.

- [ ] **Step 1: 실패하는 테스트 작성**

`RenderingTestSupport.swift` 끝에 추가:

```swift
/// 고정 추정값을 돌려주거나 던지는 추정기.
struct StubGenderEstimator: GenderEstimator {
    var result: Result<[GenderEstimate?], MellowError> = .success([])

    func estimate(_ image: CIImage, faces: [FaceGeometry]) throws -> [GenderEstimate?] {
        try result.get()
    }
}

/// 고정 얼굴 목록을 돌려주는 분석기.
struct FixedFaceAnalyzer: FaceAnalyzer {
    var faces: [FaceGeometry]

    func analyze(_ image: CIImage) throws -> [FaceGeometry] {
        faces
    }
}
```

(같은 이름의 스텁이 이미 있으면 그것을 쓰고 새로 만들지 않는다.)

`PhotoPipelineTests.swift` 끝에 추가:

```swift
    func testGenderEstimatesAreThresholdedAndFailuresAreSilent() async throws {
        let tuning = RenderTuning()
        let big = FaceGeometry(boundingBox: NormalizedRect(x: 0.1, y: 0.2, width: 0.3, height: 0.4), yaw: 0.1)
        let small = FaceGeometry(boundingBox: NormalizedRect(x: 0.5, y: 0.2, width: 0.03, height: 0.04))
        let turned = FaceGeometry(boundingBox: NormalizedRect(x: 0.6, y: 0.2, width: 0.3, height: 0.4), yaw: 0.9)
        let faces = [big, small, turned]
        let estimates: [GenderEstimate?] = [
            GenderEstimate(gender: .female, confidence: 0.9), GenderEstimate(gender: .male, confidence: 0.99),
            GenderEstimate(gender: .male, confidence: 0.95),
        ]
        let accepted = PhotoPipeline.acceptedEstimates(estimates, faces: faces, tuning: tuning)
        XCTAssertEqual(accepted.map { $0?.gender }, [.female, nil, nil], "작은 얼굴·돌아간 얼굴은 버린다")
        let weak: [GenderEstimate?] = [GenderEstimate(gender: .female, confidence: 0.6), nil, nil]
        XCTAssertEqual(PhotoPipeline.acceptedEstimates(weak, faces: faces, tuning: tuning), [nil, nil, nil])
        XCTAssertEqual(
            PhotoPipeline.acceptedEstimates([GenderEstimate(gender: .female, confidence: 1)], faces: faces, tuning: tuning),
            [nil, nil, nil], "길이가 다르면 모두 버린다")
        let url = try Support.writePNG(Support.skinTexture(size: 256), name: "genders")
        let pipeline = PhotoPipeline(
            analyzer: FixedFaceAnalyzer(faces: faces), genderEstimator: StubGenderEstimator(result: .success(estimates)),
            tuning: tuning)
        let id = PhotoID()
        let prepared = try await pipeline.prepare(id, at: url)
        XCTAssertEqual(prepared.genders, [.female, nil, nil])
        XCTAssertEqual(try await pipeline.preparedAnalysis(id)?.genderEstimates.map { $0?.gender }, [.female, nil, nil])
        let failing = PhotoPipeline(
            analyzer: FixedFaceAnalyzer(faces: faces),
            genderEstimator: StubGenderEstimator(result: .failure(.faceAnalysisUnavailable(reason: "stub"))),
            tuning: tuning)
        let silent = try await failing.prepare(PhotoID(), at: url)
        XCTAssertEqual(silent.genders, [nil, nil, nil], "추정 실패는 준비를 막지 않는다")
        XCTAssertNil(silent.faceAnalysisFailure)
        let none = PhotoPipeline(analyzer: FixedFaceAnalyzer(faces: faces), tuning: tuning)
        XCTAssertEqual(try await none.prepare(PhotoID(), at: url).genders, [nil, nil, nil], "추정기가 없으면 모두 미지정")
    }

    func testEstimatedGenderSelectsGroupLayerUnlessManuallyAssigned() {
        let left = FaceGeometry(boundingBox: NormalizedRect(x: 0.05, y: 0.1, width: 0.35, height: 0.8))
        let right = FaceGeometry(boundingBox: NormalizedRect(x: 0.6, y: 0.1, width: 0.35, height: 0.8))
        var recipe = EditRecipe()
        recipe.people.groups[.female] = PortraitLayer(skinSmoothing: 0.5)
        recipe.people.groups[.male] = PortraitLayer(skinSmoothing: 0.1)
        recipe.people.individuals = [PersonRecord(anchor: PersonAnchor(faceBox: right.boundingBox), gender: .male)]
        let analysis = PhotoAnalysis(
            faces: [left, right],
            genderEstimates: [GenderEstimate(gender: .female, confidence: 0.9), GenderEstimate(gender: .female, confidence: 0.9)])
        let context = RenderContext(
            extent: CGRect(x: 0, y: 0, width: 64, height: 64), recipe: recipe, analysis: analysis, tuning: RenderTuning())
        XCTAssertEqual(context.faceTargets[0].gender, .female, "추정만 있는 얼굴은 추정 성별")
        XCTAssertEqual(context.faceTargets[0].portrait.skin.smoothing, 0.5)
        XCTAssertEqual(context.faceTargets[1].gender, .male, "수동 지정이 추정을 이긴다")
        XCTAssertEqual(context.faceTargets[1].portrait.skin.smoothing, 0.1)
    }
```

- [ ] **Step 2: 실패 확인**

Run: `cd apple && swift test --filter PhotoPipelineTests` → 컴파일 실패(`GenderEstimator` 없음).

- [ ] **Step 3: 구현**

`apple/Sources/MellowRendering/API/GenderEstimator.swift`:

```swift
import CoreImage
import MellowShared

/// 얼굴 하나의 성별 추정. 저장하지 않는다. 사용자의 수동 지정이 늘 우선한다.
public struct GenderEstimate: Equatable, Sendable {
    public var gender: Gender
    /// 0…1.
    public var confidence: Double

    public init(gender: Gender, confidence: Double) {
        self.gender = gender
        self.confidence = confidence
    }
}

/// 성별 추정 포트. faces와 같은 순서·길이로 돌려주고 추정하지 못한 얼굴은 nil이다. 기본 구현은 H4(Core ML).
/// 실패는 던져도 되며 PhotoPipeline이 조용히 빈 결과로 바꾼다.
public protocol GenderEstimator: Sendable {
    func estimate(_ image: CIImage, faces: [FaceGeometry]) throws -> [GenderEstimate?]
}
```

`PhotoAnalysis.swift`: `public var genderEstimates: [GenderEstimate?]`(문서 주석 "faces와 같은 길이이거나 빈 배열. 임계값을 통과한 추정만. 영속화하지 않는다.")를 `bodyAnalysisFailure` 다음에 두고 `init`에 `genderEstimates: [GenderEstimate?] = []`를 마지막 인자로 더한다.

`RenderTuning.swift`에 추가(다른 상수와 같은 자리·형식):

```swift
    /// 성별 추정을 받아들이는 최소 신뢰도.
    public var genderMinConfidence = 0.75
    /// 이 폭(이미지 폭 비율) 미만의 얼굴은 추정하지 않는다.
    public var genderMinFaceWidth = 0.05
    /// 이보다 돌아간 얼굴(라디안)은 추정하지 않는다.
    public var genderMaxYaw = 0.6
```

`PhotoPipeline.swift`:
- `private let genderEstimator: (any GenderEstimator)?` 추가. `init`에 `genderEstimator: (any GenderEstimator)? = nil`을 `bodyAnalyzer` 다음에 넣는다(기존 호출은 라벨 순서대로 그대로 컴파일된다).
- `prepare`에서 `let body = analyzeBodies(in: preview)` 뒤에 `let genders = estimateGenders(in: preview, faces: faces)`를 두고 `PhotoAnalysis(..., genderEstimates: genders)`로 넘긴다. `PreparedPhoto(..., genders: genders.map { $0?.gender })`.
- `PreparedPhoto`에 `public let genders: [Gender?]`(init 인자 기본 `[]`, 주석 "임계값을 통과한 추정 성별. 얼굴과 같은 길이이거나 빈 배열").

```swift
    /// 추정 실패는 준비를 막지 않는다. 추정은 보조 정보라 실패 사유도 남기지 않는다.
    private func estimateGenders(in image: CIImage, faces: [FaceGeometry]) -> [GenderEstimate?] {
        guard let genderEstimator, !faces.isEmpty else { return Array(repeating: nil, count: faces.count) }
        let raw = (try? genderEstimator.estimate(image, faces: faces)) ?? []
        return Self.acceptedEstimates(raw, faces: faces, tuning: tuning)
    }

    /// 임계값(신뢰도·얼굴 폭·yaw)을 적용한다. 길이가 얼굴 수와 다르면 모두 nil이다.
    public static func acceptedEstimates(_ estimates: [GenderEstimate?], faces: [FaceGeometry], tuning: RenderTuning)
        -> [GenderEstimate?]
    {
        guard estimates.count == faces.count else { return Array(repeating: nil, count: faces.count) }
        return zip(estimates, faces).map { estimate, face in
            guard let estimate, estimate.confidence >= tuning.genderMinConfidence,
                face.boundingBox.width >= tuning.genderMinFaceWidth, abs(face.yaw ?? 0) <= tuning.genderMaxYaw
            else { return nil }
            return estimate
        }
    }
```

`RenderStage.swift`의 `makeTargets`: `let gender = person?.gender`를 다음으로 바꾼다.

```swift
            let estimate = analysis.genderEstimates.indices.contains(index) ? analysis.genderEstimates[index]?.gender : nil
            let gender = PortraitResolver.effectiveGender(person: person, estimate: estimate)
```

- [ ] **Step 4: 통과 확인**

Run: `cd apple && swift test --filter MellowRenderingTests` → `Executed 263 tests, with 0 failures`. lint 출력 없음. `./scripts/verify-modules.sh` 통과.

- [ ] **Step 5: 커밋**

```bash
git add apple/Sources/MellowRendering/API/GenderEstimator.swift apple/Sources/MellowRendering/API/PhotoAnalysis.swift apple/Sources/MellowRendering/API/PhotoPipeline.swift apple/Sources/MellowRendering/API/RenderTuning.swift apple/Sources/MellowRendering/API/RenderStage.swift apple/Tests/MellowRenderingTests/RenderingTestSupport.swift apple/Tests/MellowRenderingTests/PhotoPipelineTests.swift
git commit -m "feat(rendering): 성별 추정 포트 GenderEstimator와 준비 때 임계값 적용

기본 구현 없음(H4). 신뢰도 0.75·얼굴 폭 5%·yaw 0.6rad 임계값. 실패는 조용히 미지정.
수동 지정이 추정을 이긴다.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 3: 편집 규칙 — 층을 가리키는 set, 재설정, 성별, 연결·삭제, legacy 연결

**Files:**
- Modify: `apple/Sources/MellowEditing/API/EditChange.swift`, `apple/Sources/MellowEditing/API/EditDocument.swift`
- Test: `apple/Tests/MellowEditingTests/EditDocumentTests.swift`

**Interfaces:**
- Consumes: `PortraitScope`, `PortraitResolver.layer`·`resolve`, `PeopleAdjustments.personID(at:)`·`prune`, `PortraitLayer.remove`.
- Produces: 인터페이스 요약의 Task 3 항목.

설계 근거: 스펙 1.4. 얼굴 의존 변경만 scope를 본다. 빈 기록은 변경 뒤 지운다. 성별 변경은 잠금 대상.

- [ ] **Step 1: 실패하는 테스트 작성**

`EditDocumentTests.swift` 끝에 추가:

```swift
    private var faceAnchor: PersonAnchor { PersonAnchor(x: 0.3, y: 0.5, width: 0.2) }

    func testScopedSetWritesOnlyThatLayerAndClamps() {
        var document = EditDocument()
        document.set(.skinSmoothing(0.2))
        XCTAssertNil(document.set(.skinSmoothing(1.7), in: .gender(.female)))
        XCTAssertEqual(document.recipe.people.groups[.female], PortraitLayer(skinSmoothing: 1), "층 값도 같은 범위로 자른다")
        XCTAssertEqual(document.recipe.portrait.skin.smoothing, 0.2, "전체 층은 그대로")
        XCTAssertNil(document.set(.skinRefinement(.redness, -3), in: .gender(.female)))
        XCTAssertEqual(document.recipe.people.groups[.female]?.skinRefinement[.redness], -1)
        XCTAssertNil(document.set(.faceShape(.width, -0.4), in: .gender(.male)))
        XCTAssertNil(document.set(.feature(.eyeBrighten, 0.5), in: .gender(.male)))
        XCTAssertNil(document.set(.autoBlemish(true), in: .gender(.male)))
        XCTAssertEqual(
            document.recipe.people.groups[.male],
            PortraitLayer(autoBlemish: true, face: [.width: -0.4], features: [.eyeBrighten: 0.5]))
        XCTAssertNil(document.set(.exposure(0.3), in: .gender(.male)), "얼굴 의존이 아닌 변경은 scope를 무시한다")
        XCTAssertEqual(document.recipe.color.exposure, 0.3)
        XCTAssertEqual(document.set(.skinSmoothing(0.5), in: .person(PersonID())), .unknownPerson)
        XCTAssertNil(document.set(.makeupColor(.lip, "lip-rose"), in: .gender(.female)))
        XCTAssertEqual(
            document.recipe.people.groups[.female]?.makeup[.lip],
            MakeupTint(colorID: "lip-rose", intensity: EditingPolicy.makeupDefaultIntensity),
            "층에서 색을 처음 고르면 기본 강도")
        document.set(.makeupIntensity(.lip, 0.8), in: .gender(.female))
        XCTAssertEqual(document.recipe.people.groups[.female]?.makeup[.lip]?.intensity, 0.8)
        XCTAssertNil(document.set(.makeupIntensity(.brow, 2), in: .gender(.female)))
        XCTAssertEqual(document.recipe.people.groups[.female]?.makeup[.brow], MakeupTint(colorID: nil, intensity: 1))
        XCTAssertEqual(document.recipe.makeup, MakeupAdjustments(), "전체 층 메이크업은 그대로")
        let steps = document.undoStack.count
        document.set(.skinSmoothing(1), in: .gender(.female))
        XCTAssertEqual(document.undoStack.count, steps, "같은 값은 체크포인트를 만들지 않는다")
        document.beginContinuousChange()
        document.set(.skinSmoothing(0.3), in: .gender(.female))
        document.set(.skinSmoothing(0.4), in: .gender(.female))
        document.endContinuousChange()
        XCTAssertEqual(document.undoStack.count, steps + 1, "드래그는 한 단계")
        document.undo()
        XCTAssertEqual(document.recipe.people.groups[.female]?.skinSmoothing, 1)
    }

    func testFirstTouchOfAFaceCreatesTheRecordAndEmptyRecordsArePruned() {
        var document = EditDocument()
        XCTAssertNil(document.set(.skinSmoothing(0.6), forPersonAt: faceAnchor))
        XCTAssertEqual(document.recipe.people.individuals.count, 1)
        let id = document.recipe.people.individuals[0].id
        XCTAssertEqual(document.recipe.people.individuals[0].anchor, faceAnchor)
        XCTAssertEqual(document.recipe.people.individuals[0].layer, PortraitLayer(skinSmoothing: 0.6))
        XCTAssertEqual(document.undoStack.count, 1, "기록 생성과 값 쓰기는 한 단계")
        XCTAssertNil(document.set(.faceShape(.jaw, 0.2), forPersonAt: PersonAnchor(x: 0.31, y: 0.5, width: 0.19)))
        XCTAssertEqual(document.recipe.people.individuals.count, 1, "가까운 anchor는 같은 사람")
        XCTAssertEqual(document.recipe.people.individuals[0].id, id)
        XCTAssertEqual(document.recipe.people.person(id)?.layer.face[.jaw], 0.2)
        XCTAssertNil(document.set(.skinSmoothing(0.6), forPersonAt: faceAnchor))
        XCTAssertEqual(document.undoStack.count, 2, "같은 값은 단계를 만들지 않는다")
        XCTAssertNil(document.resetOverrides(in: .person(id)))
        XCTAssertTrue(document.recipe.people.individuals.isEmpty, "층이 비고 성별도 없는 기록은 지운다")
        document.undo()
        XCTAssertEqual(document.recipe.people.person(id)?.layer.face[.jaw], 0.2)
        XCTAssertNil(document.set(.gender(.female), forPersonAt: PersonAnchor(x: 0.7, y: 0.5, width: 0.2)))
        XCTAssertEqual(document.recipe.people.individuals.count, 2)
        let second = document.recipe.people.individuals[1]
        XCTAssertEqual(second.gender, .female)
        XCTAssertTrue(second.layer.isEmpty)
        XCTAssertNil(document.set(.gender(nil), in: .person(second.id)))
        XCTAssertEqual(document.recipe.people.individuals.count, 1, "성별을 풀어 비면 기록도 사라진다")
        XCTAssertTrue(document.hasEdits)
    }

    func testGenderAssignmentIsLockedByLocalEditsAndNeedsAPerson() {
        var document = EditDocument()
        document.set(.gender(.male), forPersonAt: faceAnchor)
        let id = document.recipe.people.individuals[0].id
        XCTAssertEqual(document.set(.gender(.female), in: .all), .unknownPerson, "성별은 개인에게만")
        XCTAssertEqual(document.set(.gender(.female), in: .gender(.female)), .unknownPerson)
        document.appendLocalEdit(.spot(RetouchSpot(x: 0.5, y: 0.4, sourceX: 0.4, sourceY: 0.4, radius: 0.02)))
        XCTAssertTrue(document.isGeometryLocked)
        XCTAssertEqual(document.set(.gender(.female), in: .person(id)), .geometryLocked)
        XCTAssertEqual(document.recipe.people.person(id)?.gender, .male)
        XCTAssertEqual(document.set(.faceShape(.width, -0.3), in: .person(id)), .geometryLocked)
        XCTAssertEqual(document.set(.faceShape(.width, -0.3), in: .gender(.male)), .geometryLocked)
        XCTAssertNil(document.set(.skinSmoothing(0.4), in: .person(id)), "피부는 잠금과 무관")
        XCTAssertNil(document.set(.feature(.teethWhiten, 0.4), in: .gender(.male)))
        document.undo()
        document.undo()
        document.undo()
        XCTAssertFalse(document.isGeometryLocked)
        XCTAssertNil(document.set(.gender(.female), in: .person(id)))
        XCTAssertEqual(document.recipe.people.person(id)?.gender, .female)
        XCTAssertTrue(EditChange.gender(nil).affectsGeometry)
        XCTAssertEqual(EditChange.makeupColor(.lip, nil).portraitKey, .makeupPart(.lip))
        XCTAssertNil(EditChange.exposure(0).portraitKey)
    }

    func testResetOverridesRestoresInheritanceAndRespectsLock() {
        var document = EditDocument()
        document.set(.skinSmoothing(0.2))
        document.set(.faceShape(.width, -0.5))
        document.set(.skinSmoothing(0.9), in: .gender(.female))
        document.set(.faceShape(.width, 0.3), in: .gender(.female))
        document.set(.makeupColor(.lip, "lip-rose"), in: .gender(.female))
        XCTAssertNil(document.resetOverrides([.skinSmoothing], in: .gender(.female)))
        XCTAssertEqual(
            document.recipe.people.groups[.female]?.overriddenKeys, [.faceShape(.width), .makeupPart(.lip)],
            "지운 키는 상속으로 돌아간다")
        XCTAssertNil(document.resetOverrides(in: .gender(.female)))
        XCTAssertNil(document.recipe.people.groups[.female], "빈 그룹 층은 키를 지운다")
        XCTAssertEqual(document.recipe.portrait.face.width, -0.5, "전체 층은 그대로")
        XCTAssertNil(document.resetOverrides([.faceShape(.width)], in: .all))
        XCTAssertEqual(document.recipe.portrait.face.width, 0, "전체 층의 재설정은 기본값")
        XCTAssertEqual(document.recipe.portrait.skin.smoothing, 0.2)
        document.set(.faceShape(.jaw, 0.4), in: .gender(.male))
        document.set(.skinSmoothing(0.7), in: .gender(.male))
        document.appendLocalEdit(.warp(WarpStroke(x: 0.5, y: 0.5, dx: 0.01, dy: 0, radius: 0.1)))
        XCTAssertEqual(document.resetOverrides(in: .gender(.male)), .geometryLocked, "얼굴형 키가 든 층 전체 초기화는 거절")
        XCTAssertNil(document.resetOverrides([.skinSmoothing], in: .gender(.male)), "얼굴형이 아닌 키만이면 허용")
        XCTAssertEqual(document.recipe.people.groups[.male], PortraitLayer(face: [.jaw: 0.4]))
        XCTAssertEqual(document.resetOverrides(in: .person(PersonID())), .unknownPerson)
    }

    func testRebindRemoveBindLegacyAndScopedLookAreOneUndoStep() throws {
        var document = EditDocument()
        document.set(.skinSmoothing(0.6), forPersonAt: faceAnchor)
        let id = document.recipe.people.individuals[0].id
        let elsewhere = PersonAnchor(x: 0.8, y: 0.5, width: 0.2)
        XCTAssertNil(document.rebindPerson(id, to: elsewhere))
        XCTAssertEqual(document.recipe.people.person(id)?.anchor, elsewhere)
        XCTAssertEqual(document.undoStack.count, 2)
        XCTAssertEqual(document.rebindPerson(PersonID(), to: elsewhere), .unknownPerson)
        XCTAssertNil(document.removePerson(id))
        XCTAssertTrue(document.recipe.people.individuals.isEmpty)
        document.undo()
        XCTAssertEqual(document.recipe.people.person(id)?.anchor, elsewhere)
        var legacy = EditDocument(
            recipe: EditRecipe(
                people: PeopleAdjustments(individuals: [
                    PersonRecord(id: .legacy(index: 1), legacyIndex: 1, layer: PortraitLayer(skinSmoothing: 0.3)),
                    PersonRecord(id: .legacy(index: 5), legacyIndex: 5, layer: PortraitLayer(skinSmoothing: 0.4)),
                ])))
        let faces = [
            NormalizedRect(x: 0.1, y: 0.3, width: 0.2, height: 0.3), NormalizedRect(x: 0.6, y: 0.3, width: 0.2, height: 0.3),
        ]
        XCTAssertTrue(legacy.bindLegacyPeople(faces: faces))
        XCTAssertEqual(legacy.recipe.people.individuals[0].anchor, PersonAnchor(faceBox: faces[1]))
        XCTAssertNil(legacy.recipe.people.individuals[0].legacyIndex)
        XCTAssertEqual(legacy.recipe.people.individuals[1].legacyIndex, 5, "범위 밖 인덱스는 그대로 남는다")
        XCTAssertFalse(legacy.canUndo, "연결은 체크포인트가 아니다")
        XCTAssertFalse(legacy.bindLegacyPeople(faces: faces), "두 번째는 바뀐 것이 없다")
        let look = MakeupLook(
            id: "daily", name: "데일리", lip: MakeupTint(colorID: "lip-coral", intensity: 0.5),
            blush: MakeupTint(colorID: "blush-peach", intensity: 0.3),
            eyeshadow: MakeupTint(colorID: "shadow-brown", intensity: 0.2), brow: MakeupStrength(intensity: 0.4),
            contour: MakeupStrength(intensity: 0.1))
        var looked = EditDocument()
        looked.applyMakeupLook(look, in: .gender(.female))
        XCTAssertEqual(looked.undoStack.count, 1)
        XCTAssertEqual(looked.recipe.people.groups[.female]?.makeupLookID, "daily")
        XCTAssertEqual(looked.recipe.people.groups[.female]?.makeup[.lip], MakeupTint(colorID: "lip-coral", intensity: 0.5))
        XCTAssertEqual(looked.recipe.people.groups[.female]?.makeup[.contour], MakeupTint(colorID: nil, intensity: 0.1))
        XCTAssertEqual(looked.recipe.makeup, MakeupAdjustments(), "전체 층은 그대로")
        looked.set(.makeupIntensity(.lip, 0.9), in: .gender(.female))
        XCTAssertNil(looked.recipe.people.groups[.female]?.makeupLookID, "부위를 바꾸면 룩 이름을 지운다")
        looked.applyMakeupLook(nil, in: .gender(.female))
        XCTAssertEqual(looked.recipe.people.groups[.female]?.makeup.count, 5, "층의 룩 없음은 다섯 부위를 0으로 덮어쓴다")
        XCTAssertTrue(looked.recipe.people.groups[.female]!.makeup.values.allSatisfy { $0.intensity == 0 })
    }
```

(`MakeupLook`의 생성자 라벨이 다르면 `MakeupCatalogTests`가 쓰는 형태를 따른다.)

- [ ] **Step 2: 실패 확인**

Run: `cd apple && swift test --filter EditDocumentTests` → 컴파일 실패(`set(_:in:)` 없음).

- [ ] **Step 3: 구현**

`EditChange.swift`: `case gender(Gender?)` 추가(주석 "개인 scope에서만 뜻이 있다"). `affectsGeometry`의 case 목록에 `.gender` 추가. 끝에 추가:

```swift
extension EditChange {
    /// 층이 덮어쓸 수 있는 키. 얼굴 의존 변경만 값이 있고 나머지는 scope를 무시한다.
    public var portraitKey: PortraitKey? {
        switch self {
        case .skinSmoothing: return .skinSmoothing
        case .autoBlemish: return .autoBlemish
        case .skinRefinement(let key, _): return .skinRefinement(key)
        case .faceShape(let key, _): return .faceShape(key)
        case .feature(let key, _): return .feature(key)
        case .makeupColor(let part, _), .makeupIntensity(let part, _): return .makeupPart(part)
        default: return nil
        }
    }
}
```

`EditDocument.swift`:
- `Rejection`에 `case unknownPerson`.
- 기존 `set(_:)`의 `switch` 본문을 `private static func applyingToAllLayer(_ change: EditChange, to recipe: EditRecipe) -> EditRecipe`로 옮기고(`.gender`는 `break`), `set`을 다음으로 바꾼다:

```swift
    /// 얼굴 의존 변경(portraitKey가 있는 것과 .gender)만 scope를 본다. 나머지는 scope와 무관하게 전체에 쓴다.
    @discardableResult
    public mutating func set(_ change: EditChange, in scope: PortraitScope = .all) -> Rejection? {
        if change.affectsGeometry, isGeometryLocked {
            return .geometryLocked
        }
        var updated = recipe
        if let rejection = Self.apply(change, scope: scope, to: &updated) {
            return rejection
        }
        return commit(updated)
    }

    /// anchor에 해당하는 기록이 있으면 그 기록에, 없으면 새 기록을 만들어 같은 변경을 쓴다(한 체크포인트).
    @discardableResult
    public mutating func set(_ change: EditChange, forPersonAt anchor: PersonAnchor) -> Rejection? {
        if change.affectsGeometry, isGeometryLocked {
            return .geometryLocked
        }
        var updated = recipe
        let id = updated.people.personID(at: anchor) ?? Self.appendPerson(at: anchor, to: &updated)
        if let rejection = Self.apply(change, scope: .person(id), to: &updated) {
            return rejection
        }
        return commit(updated)
    }

    /// 빈 기록을 지우고, 값이 그대로면 체크포인트 없이 끝낸다.
    private mutating func commit(_ proposed: EditRecipe) -> Rejection? {
        var updated = proposed
        updated.people.prune()
        guard updated != recipe else { return nil }
        checkpointUnlessContinuous()
        recipe = updated
        return nil
    }

    private static func appendPerson(at anchor: PersonAnchor, to recipe: inout EditRecipe) -> PersonID {
        let record = PersonRecord(anchor: anchor)
        recipe.people.individuals.append(record)
        return record.id
    }

    /// 변경을 제안 레시피에 쓴다. 잠금은 호출자가 먼저 본다.
    private static func apply(_ change: EditChange, scope: PortraitScope, to updated: inout EditRecipe) -> Rejection? {
        if case .gender(let gender) = change {
            guard case .person(let id) = scope, let index = updated.people.individuals.firstIndex(where: { $0.id == id })
            else { return .unknownPerson }
            updated.people.individuals[index].gender = gender
            return nil
        }
        guard scope != .all, let key = change.portraitKey else {
            updated = applyingToAllLayer(change, to: updated)
            return nil
        }
        guard var layer = PortraitResolver.layer(updated, scope: scope) else { return .unknownPerson }
        let beneath = beneath(updated, scope: scope)
        write(change, key: key, into: &layer, beneath: beneath)
        store(layer, in: &updated, scope: scope)
        return nil
    }

    /// 그 층 아래를 겹친 값. 메이크업 색을 처음 고를 때의 기본 강도 기준이다. 개인은 기록의 수동 성별로 그룹을 고른다.
    private static func beneath(_ recipe: EditRecipe, scope: PortraitScope) -> PortraitResolver.Resolved {
        switch scope {
        case .all, .gender: return PortraitResolver.resolve(recipe, person: nil, gender: nil)
        case .person(let id): return PortraitResolver.resolve(recipe, person: nil, gender: recipe.people.person(id)?.gender)
        }
    }

    /// 층에 키 하나를 쓴다(전체 층과 같은 클램프·룩 해제 규칙).
    private static func write(
        _ change: EditChange, key: PortraitKey, into layer: inout PortraitLayer, beneath: PortraitResolver.Resolved
    ) {
        switch change {
        case .skinSmoothing(let value):
            layer.skinSmoothing = EditingPolicy.clamped(value, to: EditingPolicy.unitRange)
        case .autoBlemish(let flag):
            layer.autoBlemish = flag
        case .skinRefinement(let refinement, let value):
            layer.skinRefinement[refinement] = EditingPolicy.clamped(value, to: EditingPolicy.skinRefinementRange(refinement))
        case .faceShape(let shape, let value):
            layer.face[shape] = EditingPolicy.clamped(value, to: EditingPolicy.faceShapeRange(shape))
        case .feature(let feature, let value):
            layer.features[feature] = EditingPolicy.clamped(value, to: EditingPolicy.unitRange)
        case .makeupColor(let part, let id):
            guard part.hasColor else { return }
            var tint = layer.makeup[part] ?? inherited(part, from: beneath.makeup)
            tint.colorID = id
            if id != nil, tint.intensity == 0 {
                tint.intensity = EditingPolicy.makeupDefaultIntensity
            }
            replaceMakeup(part, with: tint, in: &layer)
        case .makeupIntensity(let part, let value):
            var tint = layer.makeup[part] ?? inherited(part, from: beneath.makeup)
            tint.intensity = EditingPolicy.clamped(value, to: EditingPolicy.unitRange)
            replaceMakeup(part, with: tint, in: &layer)
        default:
            return
        }
    }

    private static func inherited(_ part: MakeupPart, from makeup: MakeupAdjustments) -> MakeupTint {
        MakeupTint(colorID: part.hasColor ? makeup.colorID(of: part) : nil, intensity: makeup.intensity(of: part))
    }

    /// 부위 값이 실제로 바뀌면 그 층의 룩 이름을 지운다(전체 층과 같은 규칙).
    private static func replaceMakeup(_ part: MakeupPart, with tint: MakeupTint, in layer: inout PortraitLayer) {
        if layer.makeup[part] != tint {
            layer.makeupLookID = nil
        }
        layer.makeup[part] = tint
    }

    /// 층을 제자리에 둔다. 빈 그룹 층은 키를 지운다.
    private static func store(_ layer: PortraitLayer, in recipe: inout EditRecipe, scope: PortraitScope) {
        switch scope {
        case .all:
            return
        case .gender(let gender):
            recipe.people.groups[gender] = layer.isEmpty ? nil : layer
        case .person(let id):
            if let index = recipe.people.individuals.firstIndex(where: { $0.id == id }) {
                recipe.people.individuals[index].layer = layer
            }
        }
    }
```

재설정·연결·삭제·legacy 연결·룩:

```swift
    /// 그 층에서 keys를 지워 상속으로 되돌린다. nil이면 층 전체(개인은 성별 지정 유지). .all은 그 키를 기본값으로 둔다.
    /// 잠긴 사진에서 얼굴형 키가 들어 있으면 거절한다.
    @discardableResult
    public mutating func resetOverrides(_ keys: Set<PortraitKey>? = nil, in scope: PortraitScope) -> Rejection? {
        let targets = keys ?? PortraitKey.all
        var updated = recipe
        if scope == .all {
            guard !(isGeometryLocked && targets.contains(where: \.isFaceShape)) else { return .geometryLocked }
            Self.resetAllLayer(targets, in: &updated)
            return commit(updated)
        }
        guard var layer = PortraitResolver.layer(updated, scope: scope) else { return .unknownPerson }
        let removing = targets.intersection(layer.overriddenKeys)
        guard !(isGeometryLocked && removing.contains(where: \.isFaceShape)) else { return .geometryLocked }
        layer.remove(targets)
        if keys == nil {
            layer.makeupLookID = nil
        }
        Self.store(layer, in: &updated, scope: scope)
        return commit(updated)
    }

    private static func resetAllLayer(_ keys: Set<PortraitKey>, in recipe: inout EditRecipe) {
        for key in keys {
            switch key {
            case .skinSmoothing: recipe.portrait.skin.smoothing = 0
            case .autoBlemish: recipe.portrait.skin.autoBlemish = false
            case .skinRefinement(let refinement): recipe.portrait.skin[refinement] = 0
            case .faceShape(let shape): recipe.portrait.face[shape] = 0
            case .feature(let feature): recipe.portrait.features[feature] = 0
            case .makeupPart(let part):
                if part.hasColor {
                    recipe.makeup.setColorID(nil, of: part)
                }
                recipe.makeup.setIntensity(0, of: part)
            }
        }
        if keys.isSuperset(of: PortraitKey.makeup) {
            recipe.makeup.lookID = nil
        }
    }

    /// 찾지 못한 사람을 다른 얼굴에 연결. 얼굴형 키가 있고 잠겼으면 거절.
    @discardableResult
    public mutating func rebindPerson(_ id: PersonID, to anchor: PersonAnchor) -> Rejection? {
        guard let index = recipe.people.individuals.firstIndex(where: { $0.id == id }) else { return .unknownPerson }
        if isGeometryLocked, recipe.people.individuals[index].layer.overriddenKeys.contains(where: \.isFaceShape) {
            return .geometryLocked
        }
        var updated = recipe
        updated.people.individuals[index].anchor = anchor
        updated.people.individuals[index].legacyIndex = nil
        return commit(updated)
    }

    @discardableResult
    public mutating func removePerson(_ id: PersonID) -> Rejection? {
        guard let index = recipe.people.individuals.firstIndex(where: { $0.id == id }) else { return .unknownPerson }
        if isGeometryLocked, recipe.people.individuals[index].layer.overriddenKeys.contains(where: \.isFaceShape) {
            return .geometryLocked
        }
        var updated = recipe
        updated.people.individuals.remove(at: index)
        return commit(updated)
    }

    /// legacyIndex만 있는 기록에 faces[legacyIndex]의 anchor를 채운다. 체크포인트 없음. 바뀐 것이 있으면 true.
    public mutating func bindLegacyPeople(faces: [NormalizedRect]) -> Bool {
        var changed = false
        for index in recipe.people.individuals.indices where recipe.people.individuals[index].anchor == nil {
            guard let legacy = recipe.people.individuals[index].legacyIndex, faces.indices.contains(legacy) else { continue }
            recipe.people.individuals[index].anchor = PersonAnchor(faceBox: faces[legacy])
            recipe.people.individuals[index].legacyIndex = nil
            changed = true
        }
        return changed
    }
```

`applyMakeupLook(_:)`을 `applyMakeupLook(_ look: MakeupLook?, in scope: PortraitScope = .all)`로 바꾼다. `.all`은 기존 본문. 그 외:

```swift
        guard var layer = PortraitResolver.layer(recipe, scope: scope) else { return }
        let adjustments = look?.adjustments ?? MakeupAdjustments()
        for part in MakeupPart.allCases {
            layer.makeup[part] = Self.inherited(part, from: adjustments)
        }
        layer.makeupLookID = look?.id
        var updated = recipe
        Self.store(layer, in: &updated, scope: scope)
        guard updated != recipe else { return }
        checkpoint()
        recipe = updated
```

`set`의 성별 변경에 대한 잠금은 `affectsGeometry`가 처리한다(스펙 1.4). 계획 결정 표의 "그룹에 얼굴형 키가 있을 때만"은 H3에서 화면 안내에 쓰고, 규칙은 단순하게 `affectsGeometry`로 둔다 — 테스트 `testGenderAssignmentIsLockedByLocalEditsAndNeedsAPerson`이 그 규칙을 고정한다.

- [ ] **Step 4: 통과 확인**

Run: `cd apple && swift test --filter MellowEditingTests` → `Executed 41 tests, with 0 failures`. 기존 테스트(`testLocalEditLocksFaceShapeAndTargetFace` 등) 불변 통과. lint 출력 없음.

- [ ] **Step 5: 커밋**

```bash
git add apple/Sources/MellowEditing/API/EditChange.swift apple/Sources/MellowEditing/API/EditDocument.swift apple/Tests/MellowEditingTests/EditDocumentTests.swift
git commit -m "feat(editing): 전체·성별 그룹·개인 층을 가리키는 편집과 재설정·성별 지정·연결

set(_:in:)·set(_:forPersonAt:)·resetOverrides·rebindPerson·removePerson·bindLegacyPeople.
층 값도 같은 범위로 자르고 빈 기록은 지운다. 성별 변경은 수동 편집 잠금 대상.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 4: 프리셋·동기화의 층 규칙 (G3 `merged` 변경)

**Files:**
- Modify: `apple/Sources/MellowEditing/API/SyncCategory.swift`, `apple/Sources/MellowEditing/API/EditDocument.swift`
- Test: `apple/Tests/MellowEditingTests/EditDocumentTests.swift`, `apple/Tests/MellowLibraryTests/ProjectSessionTests.swift`

**Interfaces:**
- Consumes: G3 `SyncCategory`, `applyFromBatch(_:categories:)`, `merged(_:targetFace:categories:)`.
- Produces: `SyncCategory.portraitKeys`, `merged`의 층 규칙. `ProjectSession.applyToAll(from:categories:)`는 바뀌지 않는다.

설계 근거: 스펙 1.4·결정 표. 프리셋·동기화는 전체 층과 그룹 층만 나르고, 동기화는 실제로 복사한 얼굴 의존 항목의 개인 키를 지운다. 성별·anchor·개인의 다른 키는 그대로. `targetFace` 초기화 규칙은 Task 5까지 그대로 둔다.

- [ ] **Step 1: 실패하는 테스트 작성**

먼저 G3 테스트 `testBatchWithAllCategoriesCopiesEveryPresetGroup`(`EditDocumentTests.swift`)을 되돌린다(H1 구현 중 추가). H1은 이 테스트의 Mirror 반복문에 `where filled.label != "people"` 제외와 "H2 Task 4가 … 지운다" 주석을 넣었다. 그 제외와 주석을 지우고 원래 모양(`for (filled, empty) in zip(Mirror(reflecting: values).children, Mirror(reflecting: defaults).children)`)으로 돌린다. `filledPresetValues()`의 `return values` 앞에 그룹 층을 채운다:

```swift
        values.people.groups[.male] = PortraitLayer(skinSmoothing: 0.4, face: [.jaw: -0.2])
        values.people.groups[.female] = PortraitLayer(
            features: [.eyeBrighten: 0.3], makeup: [.lip: MakeupTint(colorID: "lip-test", intensity: 0.5)])
```

이 테스트의 마지막 단언(`PresetValues(of: document.recipe) == values`)은 동기화가 `people.groups`를 복사해야 통과한다(Step 3 전에는 실패).

`EditDocumentTests.swift` 끝에 추가:

```swift
    func testPresetKeepsIndividualsAndGenderButReplacesGroups() {
        var document = EditDocument()
        document.set(.skinSmoothing(0.8), in: .gender(.female))
        document.set(.gender(.female), forPersonAt: faceAnchor)
        document.set(.faceShape(.width, -0.3), forPersonAt: faceAnchor)
        let id = document.recipe.people.individuals[0].id
        var values = PresetValues(color: ColorAdjustments(exposure: 0.2))
        values.people.groups[.male] = PortraitLayer(skinSmoothing: 0.1)
        document.apply(values)
        XCTAssertEqual(document.recipe.people.groups, [.male: PortraitLayer(skinSmoothing: 0.1)], "그룹 층은 통째로 바뀐다")
        XCTAssertEqual(document.recipe.people.person(id)?.gender, .female)
        XCTAssertEqual(document.recipe.people.person(id)?.layer, PortraitLayer(face: [.width: -0.3]), "개인 층은 그대로")
        var locked = EditDocument()
        locked.set(.faceShape(.jaw, 0.2), in: .gender(.female))
        locked.appendLocalEdit(.spot(RetouchSpot(x: 0.5, y: 0.4, sourceX: 0.4, sourceY: 0.4, radius: 0.02)))
        var shaping = PresetValues()
        shaping.people.groups[.female] = PortraitLayer(skinSmoothing: 0.5, face: [.jaw: 0.9])
        locked.apply(shaping)
        XCTAssertEqual(
            locked.recipe.people.groups[.female], PortraitLayer(skinSmoothing: 0.5, face: [.jaw: 0.2]),
            "잠긴 사진은 그룹의 얼굴형도 보존하고 나머지는 받는다")
        XCTAssertNil(SyncCategory.color.portraitKeys)
        XCTAssertEqual(SyncCategory.skin.portraitKeys, PortraitKey.skin)
        XCTAssertEqual(SyncCategory.makeup.portraitKeys, PortraitKey.makeup)
    }

    func testBatchSyncCopiesGroupsAndClearsIndividualKeysOfSyncedCategories() {
        var document = EditDocument()
        document.set(.skinSmoothing(0.9), in: .gender(.male))
        document.set(.gender(.female), forPersonAt: faceAnchor)
        document.set(.skinSmoothing(0.7), forPersonAt: faceAnchor)
        document.set(.faceShape(.width, -0.3), forPersonAt: faceAnchor)
        document.set(.makeupColor(.lip, "lip-rose"), forPersonAt: faceAnchor)
        let id = document.recipe.people.individuals[0].id
        var values = PresetValues(color: ColorAdjustments(exposure: 0.3))
        values.portrait.skin.smoothing = 0.4
        values.people.groups[.female] = PortraitLayer(skinSmoothing: 0.5, face: [.jaw: 0.2])
        document.applyFromBatch(values, categories: [.color])
        XCTAssertEqual(document.recipe.color.exposure, 0.3)
        XCTAssertEqual(document.recipe.people.groups[.male], PortraitLayer(skinSmoothing: 0.9), "색감만이면 그룹도 그대로")
        XCTAssertEqual(document.recipe.people.person(id)?.layer.overriddenKeys, [.skinSmoothing, .faceShape(.width), .makeupPart(.lip)])
        document.applyFromBatch(values, categories: [.skin])
        XCTAssertEqual(document.recipe.portrait.skin.smoothing, 0.4)
        XCTAssertNil(document.recipe.people.groups[.male], "원본에 없는 그룹의 피부 키는 지운다")
        XCTAssertEqual(document.recipe.people.groups[.female], PortraitLayer(skinSmoothing: 0.5), "그룹의 피부 키만 복사하고 얼굴형은 아직 아님")
        let person = document.recipe.people.person(id)
        XCTAssertEqual(person?.layer.overriddenKeys, [.faceShape(.width), .makeupPart(.lip)], "개인 층의 피부 키만 빠진다")
        XCTAssertEqual(person?.gender, .female, "성별 지정은 남는다")
        XCTAssertEqual(person?.anchor, faceAnchor)
        var locked = document
        locked.appendLocalEdit(.spot(RetouchSpot(x: 0.5, y: 0.4, sourceX: 0.4, sourceY: 0.4, radius: 0.02)))
        locked.applyFromBatch(values, categories: [.faceShape, .makeup])
        XCTAssertEqual(locked.recipe.people.person(id)?.layer.overriddenKeys, [.faceShape(.width)], "잠긴 사진은 얼굴형을 건너뛰어 개인 얼굴형 키도 남는다")
        XCTAssertNil(locked.recipe.people.groups[.female]?.face[.jaw])
        document.applyFromBatch(values, categories: [.faceShape, .makeup])
        XCTAssertEqual(document.recipe.people.groups[.female], PortraitLayer(skinSmoothing: 0.5, face: [.jaw: 0.2]))
        XCTAssertTrue(document.recipe.people.individuals.isEmpty, "층이 비고 성별만 남은 기록은 남고, 그렇지 않으면 지운다")
            || document.recipe.people.person(id)?.layer.isEmpty == true
        XCTAssertEqual(document.recipe.people.person(id)?.gender, .female)
    }
```

마지막 두 단언은 하나로 줄인다: 성별이 있으므로 기록은 남고 층만 비어야 한다.

```swift
        XCTAssertEqual(document.recipe.people.person(id)?.layer, PortraitLayer(), "얼굴형·메이크업 키까지 빠져 층이 빈다")
        XCTAssertEqual(document.recipe.people.person(id)?.gender, .female, "성별이 있어 기록은 남는다")
```

(위 코드 블록에서 `XCTAssertTrue(... || ...)` 두 줄은 쓰지 않고 이 두 줄을 쓴다.)

`ProjectSessionTests.swift` 끝에 추가:

```swift
    func testApplyToAllCarriesGroupLayersNotIndividuals() throws {
        let session = ProjectSession(store: MemorySessionStore(), maxPhotos: 40)
        let source = entry("A")
        let other = entry("B")
        try session.add(source)
        try session.add(other)
        let anchor = PersonAnchor(x: 0.3, y: 0.5, width: 0.2)
        session.edit(source.id) { $0.set(.skinSmoothing(0.6), in: .gender(.female)) }
        session.edit(source.id) { $0.set(.skinSmoothing(0.9), forPersonAt: anchor) }
        session.edit(other.id) { $0.set(.gender(.male), forPersonAt: anchor) }
        session.edit(other.id) { $0.set(.skinSmoothing(0.2), forPersonAt: anchor) }
        session.applyToAll(from: source.id, categories: [.skin])
        let received = session.photos[1].document.recipe
        XCTAssertEqual(received.people.groups[.female], PortraitLayer(skinSmoothing: 0.6), "그룹 층은 복사")
        XCTAssertEqual(received.people.individuals.count, 1)
        XCTAssertEqual(received.people.individuals[0].gender, .male, "받는 사진의 성별 지정은 남는다")
        XCTAssertTrue(received.people.individuals[0].layer.isEmpty, "받는 사진의 개인 피부 키는 빠진다")
        XCTAssertEqual(session.photos[0].document.recipe.people.individuals[0].layer.skinSmoothing, 0.9, "원본의 개인 층은 복사되지 않고 그대로")
    }
```

- [ ] **Step 2: 실패 확인**

Run: `cd apple && swift test --filter "EditDocumentTests|ProjectSessionTests"` → 컴파일 실패(`portraitKeys` 없음).

- [ ] **Step 3: 구현**

`SyncCategory.swift`에 추가:

```swift
    /// 이 항목이 층에서 다루는 키. 얼굴 의존 항목만 값이 있다.
    public var portraitKeys: Set<PortraitKey>? {
        switch self {
        case .skin: return PortraitKey.skin
        case .faceShape: return PortraitKey.faceShape
        case .features: return PortraitKey.features
        case .makeup: return PortraitKey.makeup
        case .color, .effects, .background, .body, .bodySkin: return nil
        }
    }
```

`EditDocument.swift`: G3 Task 5의 `apply`·`applyFromBatch`·`merged`를 다음으로 바꾼다(`targetFace` 인자는 Task 5가 없앤다).

```swift
    /// 사용자가 고른 프리셋. 전체 층과 그룹 층을 통째로 바꾸고 개인 층·성별은 그대로 둔다. 잠긴 사진은 얼굴형·체형을 보존한다.
    public mutating func apply(_ values: PresetValues) {
        checkpoint()
        recipe = merged(values, targetFace: recipe.portrait.targetFace, categories: SyncCategory.all, clearsIndividuals: false)
    }

    /// 다른 사진의 설정을 일괄 복사. 고른 항목만 전체·그룹 층에 덮어쓰고, 복사한 얼굴 의존 항목은 개인 층에서 그 키를 지운다.
    /// 성별 지정·anchor는 그대로. 빈 선택은 아무것도 하지 않는다.
    public mutating func applyFromBatch(_ values: PresetValues, categories: Set<SyncCategory> = SyncCategory.all) {
        guard !categories.isEmpty else { return }
        let resetsTarget = !isGeometryLocked && categories.contains { $0.dependsOnFaces }
        checkpoint()
        recipe = merged(
            values, targetFace: resetsTarget ? nil : recipe.portrait.targetFace, categories: categories,
            clearsIndividuals: true)
    }

    private func merged(
        _ values: PresetValues, targetFace: Int?, categories: Set<SyncCategory>, clearsIndividuals: Bool
    ) -> EditRecipe {
        var updated = recipe
        var applied = categories
        if isGeometryLocked {
            applied.remove(.faceShape)
            applied.remove(.body)
        }
        if applied.contains(.color) {
            updated.color = values.color
            updated.detail = values.detail
        }
        if applied.contains(.effects) {
            updated.effects = values.effects
        }
        if applied.contains(.skin) {
            updated.portrait.skin = values.portrait.skin
        }
        if applied.contains(.faceShape) {
            updated.portrait.face = values.portrait.face
        }
        if applied.contains(.features) {
            updated.portrait.features = values.portrait.features
        }
        if applied.contains(.makeup) {
            updated.makeup = values.makeup
        }
        if applied.contains(.background) {
            updated.background = values.background
        }
        if applied.contains(.body) {
            updated.body = values.body
        }
        if applied.contains(.bodySkin) {
            updated.bodySkin = values.bodySkin
        }
        for keys in applied.compactMap(\.portraitKeys) {
            for gender in Gender.allCases {
                var group = updated.people.groups[gender] ?? PortraitLayer()
                Self.copy(keys, from: values.people.groups[gender] ?? PortraitLayer(), into: &group)
                updated.people.groups[gender] = group.isEmpty ? nil : group
            }
            if clearsIndividuals {
                for index in updated.people.individuals.indices {
                    updated.people.individuals[index].layer.remove(keys)
                }
            }
        }
        updated.people.prune()
        updated.portrait.targetFace = targetFace
        return updated
    }

    /// target의 keys를 source의 값으로 바꾼다(source에 없는 키는 지움). 메이크업 전부를 옮기면 룩 이름도 옮긴다.
    private static func copy(_ keys: Set<PortraitKey>, from source: PortraitLayer, into target: inout PortraitLayer) {
        target.remove(keys)
        for key in keys.intersection(source.overriddenKeys) {
            switch key {
            case .skinSmoothing: target.skinSmoothing = source.skinSmoothing
            case .autoBlemish: target.autoBlemish = source.autoBlemish
            case .skinRefinement(let refinement): target.skinRefinement[refinement] = source.skinRefinement[refinement]
            case .faceShape(let shape): target.face[shape] = source.face[shape]
            case .feature(let feature): target.features[feature] = source.features[feature]
            case .makeupPart(let part): target.makeup[part] = source.makeup[part]
            }
        }
        if keys.isSuperset(of: PortraitKey.makeup) {
            target.makeupLookID = source.makeupLookID
        }
    }
```

G3의 `merged`가 `faceShape`·`body`를 `!isGeometryLocked` 조건으로 걸던 것을 `applied` 집합에서 빼는 형태로 바꿨을 뿐 결과는 같다. G3 Task 5의 테스트 `testBatchCopiesOnlyChosenCategoriesAndKeepsTargetFaceWithoutFaceCategories`는 그대로 통과해야 한다(개인 층이 없는 문서).

- [ ] **Step 4: 통과 확인**

Run: `cd apple && swift test` → Editing 43, Library 33, 나머지 불변(Shared 58 · Rendering 263 · Export 4), 0 failures. lint 출력 없음.

- [ ] **Step 5: 커밋**

```bash
git add apple/Sources/MellowEditing/API/SyncCategory.swift apple/Sources/MellowEditing/API/EditDocument.swift apple/Tests/MellowEditingTests/EditDocumentTests.swift apple/Tests/MellowLibraryTests/ProjectSessionTests.swift
git commit -m "feat(editing): 프리셋·동기화가 성별 그룹 층을 나르고 동기화한 항목의 개인 키를 지움

개인 층·성별 지정은 복사하지 않는다. 잠긴 사진은 그룹 얼굴형도 보존.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 5: targetFace 읽기 이행·제거와 앱 최소 변경

**Files:**
- Modify: `apple/Sources/MellowShared/API/Adjustments.swift`(`PortraitAdjustments.targetFace` 제거), `EditRecipe.swift`(이행), `apple/Sources/MellowLibrary/Infrastructure/SessionFileV1.swift`
- Modify: `apple/Sources/MellowEditing/API/EditChange.swift`(`targetFace` 제거), `EditDocument.swift`(`merged` 인자 제거)
- Modify: `apple/Sources/MellowRendering/API/RenderStage.swift`(`targetFaces`·`targetBlemishes`·legacy 제한 제거), `apple/Sources/MellowRendering/API/AutoEnhancer.swift`(`targetFace` 참조가 있으면)
- Modify: `shared/recipe-schema/edit-recipe.v2.schema.json`, `shared/recipe-schema/README.md`
- Modify: `apple/MellowPhoto/Application/AppModel.swift`, `AppModel+Editing.swift`, `AppModel+Library.swift`, `UserMessage.swift`, `apple/MellowPhoto/Features/Editor/BeautyPanel.swift`, `MakeupPanel.swift`
- Test: `apple/Tests/MellowSharedTests/EditRecipeCodingTests.swift`, `RecipeSchemaTests.swift`, `apple/Tests/MellowLibraryTests/SessionFileMigrationTests.swift`, `ProjectSessionTests.swift`, `apple/Tests/MellowEditingTests/EditDocumentTests.swift`, `apple/Tests/MellowRenderingTests/RenderingTestSupport.swift`, `RenderPipelineTests.swift`, `SkinStageTests.swift`, `MakeupStageTests.swift`, `ShapeWarpStageTests.swift`, `FeatureStageTests.swift`, `AutoEnhancerTests.swift`, `apple/MellowPhotoTests/AppModelTests.swift`, `EditorScenarioTests.swift`

**Interfaces:**
- Consumes: Task 1~4 전부, `PortraitLayer.difference`, `PersonID.legacy(index:)`.
- Produces: 인터페이스 요약의 Task 5 항목.

설계 근거: 스펙 1.2 읽기 이행·적용 순서, 1.6의 `BeautyTarget`. 이 Task 하나로 "옛 뜻"이 사라지고 모든 모듈이 `people`만 본다.

- [ ] **Step 1: 실패하는 테스트 작성**

`EditRecipeCodingTests.swift`: `testRoundTripPreservesOperationsOrderAndSchemaVersion`의 `recipe.portrait.targetFace = 1`을 `recipe.people.individuals = [PersonRecord(id: .legacy(index: 1), legacyIndex: 1, layer: PortraitLayer(skinSmoothing: 0.3))]`로 바꾸고 `recipe.portrait.skin.smoothing = 0.3` 줄은 지운다. 끝에 추가:

```swift
    func testLegacyTargetFaceMigratesIntoAPersonRecord() throws {
        let legacy = """
            {"schemaVersion":2,"portrait":{"targetFace":1,"skin":{"smoothing":0.5,"autoBlemish":true,"darkCircles":0.2},\
            "face":{"width":-0.3},"features":{"eyeBrighten":0.4}},\
            "makeup":{"lookID":"daily","lip":{"colorID":"lip-coral","intensity":0.5},"brow":{"intensity":0.2}},\
            "color":{"exposure":0.1}}
            """
        let decoded = try JSONDecoder().decode(EditRecipe.self, from: Data(legacy.utf8))
        XCTAssertEqual(decoded.portrait, PortraitAdjustments(), "전체 층은 비운다")
        XCTAssertEqual(decoded.makeup, MakeupAdjustments())
        XCTAssertEqual(decoded.color.exposure, 0.1)
        XCTAssertEqual(decoded.people.individuals.count, 1)
        let record = decoded.people.individuals[0]
        XCTAssertEqual(record.id, .legacy(index: 1))
        XCTAssertEqual(record.legacyIndex, 1)
        XCTAssertNil(record.anchor)
        XCTAssertNil(record.gender)
        XCTAssertEqual(
            record.layer,
            PortraitLayer(
                skinSmoothing: 0.5, autoBlemish: true, skinRefinement: [.darkCircles: 0.2], face: [.width: -0.3],
                features: [.eyeBrighten: 0.4],
                makeup: [.lip: MakeupTint(colorID: "lip-coral", intensity: 0.5), .brow: MakeupTint(intensity: 0.2)],
                makeupLookID: "daily"))
        XCTAssertTrue(decoded.dependsOnFaces)
        XCTAssertEqual(try JSONDecoder().decode(EditRecipe.self, from: Data(legacy.utf8)), decoded, "이행은 결정적이다")
        let reencoded = try XCTUnwrap(String(data: JSONEncoder().encode(decoded), encoding: .utf8))
        XCTAssertFalse(reencoded.contains("targetFace"), "다시 쓰면 옛 키가 없다")
        XCTAssertTrue(reencoded.contains("\"legacyIndex\":1"))
        let bare = #"{"schemaVersion":2,"portrait":{"targetFace":0}}"#
        XCTAssertTrue(try JSONDecoder().decode(EditRecipe.self, from: Data(bare.utf8)).isDefault, "옮길 값이 없으면 기록도 없다")
        let outOfRange = #"{"schemaVersion":2,"portrait":{"targetFace":7,"skin":{"smoothing":0.5}}}"#
        XCTAssertEqual(
            try JSONDecoder().decode(EditRecipe.self, from: Data(outOfRange.utf8)).people.individuals[0].legacyIndex, 7,
            "범위 밖 인덱스도 그대로 옮긴다(짝이 없어 렌더에서 빠짐, 옛 결과와 같음)")
        let both = """
            {"schemaVersion":2,"portrait":{"targetFace":0,"skin":{"smoothing":0.5}},\
            "people":{"individuals":[{"id":"44444444-4444-4444-4444-444444444444","anchor":{"x":0.5,"y":0.5,"width":0.2},\
            "layer":{"skin":{"smoothing":0.1}}}]}}
            """
        let kept = try JSONDecoder().decode(EditRecipe.self, from: Data(both.utf8))
        XCTAssertEqual(kept.portrait.skin.smoothing, 0.5, "people이 이미 있으면 이행하지 않는다")
        XCTAssertEqual(kept.people.individuals.count, 1)
        var manual = EditRecipe()
        manual.portrait.skin.smoothing = 0.3
        manual.migrateLegacyTargetFace(2)
        XCTAssertEqual(manual.people.individuals[0].id, .legacy(index: 2))
        XCTAssertEqual(manual.portrait.skin.smoothing, 0)
    }

    func testPortraitAdjustmentsNoLongerCarryATargetFace() throws {
        let json = try XCTUnwrap(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(PortraitAdjustments(skin: SkinAdjustments(smoothing: 0.2))))
                as? [String: Any])
        XCTAssertEqual(Set(json.keys), ["skin", "face", "features"])
        let schemaURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("shared/recipe-schema/edit-recipe.v2.schema.json")
        let schema = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: schemaURL)) as? [String: Any])
        let portrait = try XCTUnwrap(
            ((schema["properties"] as? [String: Any])?["portrait"] as? [String: Any])?["properties"] as? [String: Any])
        XCTAssertEqual((portrait["targetFace"] as? [String: Any])?["deprecated"] as? Bool, true)
    }
```

`RecipeSchemaTests.swift`: `encodedSampleRecipe()`의 `recipe.portrait.targetFace = 1` 줄 삭제. `testLegacyPortraitKeysStayInSchemaAsDeprecated`의 키 배열을 `["skinSmoothing", "faceSlim", "targetFace"]`로.

`SessionFileMigrationTests.swift`: `testV1SessionDecodesToV2Snapshot`에서 다음 세 줄을

```swift
        XCTAssertEqual(first.document.recipe.portrait.skin.smoothing, 0.3)
        XCTAssertEqual(first.document.recipe.portrait.face.width, -0.2)
        XCTAssertEqual(first.document.recipe.portrait.targetFace, 1)
```

다음으로 바꾼다:

```swift
        XCTAssertEqual(first.document.recipe.portrait, PortraitAdjustments(), "selectedFace가 있던 사진은 전체 층이 빈다")
        let person = try XCTUnwrap(first.document.recipe.people.individuals.first)
        XCTAssertEqual(person.id, .legacy(index: 1))
        XCTAssertEqual(person.legacyIndex, 1)
        XCTAssertEqual(person.layer, PortraitLayer(skinSmoothing: 0.3, face: [.width: -0.2]))
```

`testB0SessionWithLegacyPortraitKeysMigratesUndoHistory`의 세 단언(`smoothing 0.4`, `width -0.25`, `targetFace 0`)을 다음으로:

```swift
        XCTAssertEqual(document.recipe.portrait, PortraitAdjustments())
        XCTAssertEqual(document.recipe.people.individuals[0].layer, PortraitLayer(skinSmoothing: 0.4, face: [.width: -0.25]))
        XCTAssertEqual(document.recipe.people.individuals[0].legacyIndex, 0)
```

그 테스트 끝에 `XCTAssertFalse(text.contains("targetFace"))`를 더한다.

`ProjectSessionTests.swift`: `testApplyToAllCopiesValuesWithBatchRules`에서 `locked.document.set(.targetFace(1))`·`plain.document.set(.targetFace(0))`와 `targetFace` 단언 두 줄을 지운다. G3의 `testApplyToAllWithCategoriesCopiesOnlyThose`에서 `session.edit(other.id) { $0.set(.targetFace(0)) }`를 `session.edit(other.id) { $0.set(.skinSmoothing(0.9), forPersonAt: PersonAnchor(x: 0.3, y: 0.5, width: 0.2)) }`로, `targetFace` 단언 두 개를 `XCTAssertEqual(session.photos[1].document.recipe.people.individuals[0].layer.skinSmoothing, 0.9, "얼굴 항목이 없으면 개인 층 유지")`와 (전부 적용 뒤) `XCTAssertTrue(session.photos[1].document.recipe.people.individuals.isEmpty, "피부를 동기화하면 개인 피부 키가 빠지고 빈 기록은 사라진다")`로 바꾼다.

`EditDocumentTests.swift`: `testLocalEditLocksFaceShapeAndTargetFace`를 `testLocalEditLocksFaceShapeAndGender`로 바꾸고 `set(.targetFace(1))` → `set(.gender(.female), forPersonAt: faceAnchor)`, `set(.targetFace(nil))` 거절 단언 → `set(.gender(nil), in: .person(document.recipe.people.individuals[0].id))`가 `.geometryLocked`, `targetFace == 1` 단언 → 성별이 `.female`로 남음. `testBatchApplyKeepsLockedShapeAndCopiesTheRest`에서 `targetFace` 관련 줄(`set(.targetFace(…))` 둘, `PortraitAdjustments(targetFace: 3, …)`의 `targetFace: 3`, 단언 둘)을 지운다. G3의 `testBatchCopiesOnlyChosenCategoriesAndKeepsTargetFaceWithoutFaceCategories`를 `testBatchCopiesOnlyChosenCategoriesAndKeepsIndividualsWithoutFaceCategories`로: `document.set(.targetFace(1))` → `document.set(.skinSmoothing(0.9), forPersonAt: faceAnchor)`, `targetFace == 1` 단언 → `XCTAssertEqual(document.recipe.people.individuals[0].layer.skinSmoothing, 0.9, "얼굴 의존 항목이 없으면 개인 층을 유지한다")`, `XCTAssertNil(targetFace)` 단언 → `XCTAssertTrue(document.recipe.people.individuals.isEmpty, "피부를 복사하면 개인 피부 키를 지운다")`.

`RenderingTestSupport.swift`에 추가:

```swift
extension RenderingTestSupport {
    /// 전체 층 값을 faces[index]에 anchor로 묶인 개인 층으로 옮긴다(옛 targetFace 이행과 같은 규칙). 범위 밖 index는 legacyIndex로 남아 짝이 없다.
    static func restricted(_ recipe: EditRecipe, toFace index: Int, of faces: [FaceGeometry]) -> EditRecipe {
        var moved = recipe
        moved.migrateLegacyTargetFace(index)
        if faces.indices.contains(index), !moved.people.individuals.isEmpty {
            moved.people.individuals[0].anchor = PersonAnchor(faceBox: faces[index].boundingBox)
            moved.people.individuals[0].legacyIndex = nil
        }
        return moved
    }
}
```

렌더 테스트에서 `recipe.portrait.targetFace = i`를 쓰던 자리를 모두 `Support.restricted(recipe, toFace: i, of: faces)`로 바꾼다: `SkinStageTests.render(..., targetFace:)` 도우미, `MakeupStageTests.testTargetFacePaintsOnlyThatFace`의 `rendered(targetFace:)`, `ShapeWarpStageTests`의 `context(_:faces:targetFace:)`·`bodyContext(...targetFace:)`, `FeatureStageTests`(132행), `RenderPipelineTests.testTargetFaceLimitsPortraitStagesToOneFace`(`onlyLeft`·`outOfRange`를 `restricted`로 만들고 단언은 그대로 — 범위 밖 7은 legacy 기록이 남아 짝이 없으므로 입력과 같은 바이트). `testAnalysisInitMatchesFaceInit`의 `targetFaces`·`targetBlemishes` 단언을 `faceTargets.map(\.face) == [right]`·`faceTargets[0].blemishes == [spots[1]]`로(레시피는 `restricted(recipe, toFace: 1, of: [left, right])`). Task 1의 `testFaceTargetsResolvePeopleLayersPerFace`에서 `targetFaces`·`targetBlemishes`·legacy 단언 세 줄을 지운다. `ShapeWarpStageTests` Task 1 테스트의 `legacy` 변수도 `restricted`로. `AutoEnhancerTests` 108행 `XCTAssertNil(withFaces.targetFace)` 삭제.

`AppModelTests.swift`:
- `testSavedPresetNeverCarriesTargetFace` → `testSavedPresetCarriesGroupLayersNotIndividuals`:

```swift
    func testSavedPresetCarriesGroupLayersNotIndividuals() async throws {
        let staged = try TestSupport.solidPNG(in: root)
        let face = TestSupport.landmarkedFace(in: NormalizedRect(x: 0.2, y: 0.2, width: 0.6, height: 0.6))
        let model = TestSupport.makeModel(
            root: root, analyzer: StubFaceAnalyzer(result: .success([face])),
            importer: FakeImporter(staged: [.success(StagedPhoto(url: staged, displayName: nil))]))
        try await importOne(model, staged)
        model.setBeautyTarget(.gender(.female))
        model.edit(.skinSmoothing(0.5))
        model.setBeautyTarget(.face(0))
        model.edit(.faceShape(.width, -0.4))
        XCTAssertEqual(model.currentRecipe.people.groups[.female], PortraitLayer(skinSmoothing: 0.5))
        XCTAssertEqual(model.currentRecipe.people.individuals.count, 1)
        model.savePreset(named: "남녀")
        let saved = try XCTUnwrap(model.session.presets.last)
        XCTAssertEqual(saved.values.people.groups[.female], PortraitLayer(skinSmoothing: 0.5))
        XCTAssertTrue(saved.values.people.individuals.isEmpty, "프리셋은 사람을 고르지 않는다")
        XCTAssertEqual(saved.values.portrait.face.width, 0, "개인 층 값은 전체 층에 섞이지 않는다")
    }
```

- `testFaceAvailabilityReportsMissingLandmarksForTargetFaces`: `model.edit(.targetFace(1))` → `model.setBeautyTarget(.face(1))`, `model.edit(.targetFace(0))` → `model.setBeautyTarget(.face(0))`. 끝(빈 모델 검사 앞)에 `model.setBeautyTarget(.gender(.male))`, `XCTAssertEqual(model.faceAvailability, .ready, "그룹·전체는 모든 얼굴 기준")` 추가.
- `EditorScenarioTests.swift`에 `targetFace`가 있으면 같은 식으로 바꾼다(`grep -n targetFace apple/MellowPhotoTests`).

- [ ] **Step 2: 실패 확인**

Run: `cd apple && swift test --filter EditRecipeCodingTests` → 컴파일 실패(`migrateLegacyTargetFace` 없음).

- [ ] **Step 3: 구현**

`Adjustments.swift`(`PortraitAdjustments`): `targetFace` 저장 속성·init 인자·`CodingKeys.targetFace`·디코드·인코드 줄을 지운다. 주석 "옛 키 skinSmoothing·faceSlim은 읽기만" 유지. 호출부 `PortraitAdjustments(targetFace: …)`는 없어야 한다(`grep -rn "targetFace" apple/Sources`로 확인).

`EditRecipe.swift`:

```swift
    private struct LegacyPortraitProbe: Decodable {
        var targetFace: Int?
    }
```

`init(from:)`에서 `people` 디코드 뒤:

```swift
        let legacyTarget = try container.decodeIfPresent(LegacyPortraitProbe.self, forKey: .portrait)?.targetFace
        if let legacyTarget, people.individuals.isEmpty {
            migrateLegacyTargetFace(legacyTarget)
        }
```

그리고:

```swift
    /// B0~G의 portrait.targetFace("이 값을 i번 얼굴에만")를 H의 모양으로 옮긴다: 전체 층 값 전부를 i번 사람의 개인 층으로.
    /// 렌더 결과는 같다. id는 인덱스에서 결정적이다. 옮길 값이 없으면 기록을 만들지 않는다.
    public mutating func migrateLegacyTargetFace(_ index: Int) {
        let layer = PortraitLayer.difference(portrait: portrait, makeup: makeup)
        portrait = PortraitAdjustments()
        makeup = MakeupAdjustments()
        guard !layer.isEmpty else { return }
        // 음수·거대한 인덱스(손상 파일)는 범위의 마지막 값으로 모은다. 어느 얼굴과도 짝이 되지 않아 옛 결과(빈 대상)와 같다.
        let safe = PersonID.legacyIndexRange.contains(index) ? index : PersonID.legacyIndexRange.upperBound
        people.individuals = [PersonRecord(id: .legacy(index: safe), legacyIndex: safe, layer: layer)]
    }
```

인덱스 검증은 H1 구현 중 추가했다. `legacyIndex`는 스키마 `minimum: 0`이므로 음수를 그대로 쓰지 않는다. Step 1에 `targetFace: -1`과 `targetFace: 9999999999999`(13자리) 레시피가 크래시 없이 디코드되고 기록의 `legacyIndex`가 `PersonID.legacyIndexRange.upperBound`, `PersonMatcher.match`가 빈 결과인 단언을 더한다.

`SessionFileV1.swift`의 `recipe(_:)`: `converted.portrait.targetFace = recipe.selectedFace` 줄을 지우고, 마지막에 `var result = EditRecipe(color: …, portrait: …, operations: operations)` 뒤 `if let selected = recipe.selectedFace { result.migrateLegacyTargetFace(selected) }`, `return result`.

`EditChange.swift`: `case targetFace(Int?)` 삭제, `affectsGeometry`에서 제거. `EditDocument.swift`: `applyingToAllLayer`의 `.targetFace` 분기 삭제, `merged`의 `targetFace` 인자와 `updated.portrait.targetFace = targetFace` 삭제, `apply`·`applyFromBatch`의 인자 제거(`resetsTarget` 변수 삭제). 주석 "잠기지 않은 사진은 대상 얼굴을 전체로"를 "복사한 얼굴 의존 항목의 개인 키를 지운다"로.

`RenderStage.swift`: `targetFaces`·`targetBlemishes` 계산 속성과 `makeTargets`의 `if let legacy = recipe.portrait.targetFace` 분기 삭제. `SkinStage`·다른 단계에 `targetFaces` 참조가 남지 않게 `grep -rn "targetFaces\|targetBlemishes\|targetFace" apple/Sources`가 비어야 한다(`AutoEnhancer`가 `targetFace: nil`을 넘기면 그 인자를 지운다).

`edit-recipe.v2.schema.json`: `portrait.targetFace`에 `"deprecated": true`를 더하고 description을 "B0~G의 읽기 전용 키. people이 없을 때만 전체 층 값을 그 인덱스 사람의 개인 층(legacyIndex)으로 옮겨 읽는다. 쓰지 않는다."로. `README.md`: v2 요점의 `targetFace` 문장을 같은 내용으로, v1 변환 표의 `recipe.selectedFace` 행을 `people.individuals[0]`(`legacyIndex`, 전체 층 값을 개인 층으로)로, "선택 키를 null로 쓰지 않고 생략" 목록에서 `portrait.targetFace`를 빼고 `people.individuals[].anchor/legacyIndex/gender`를 넣는다.

앱(최소 변경):

`AppModel.swift`:

```swift
    /// 뷰티·메이크업 패널이 편집하는 대상. 화면 상태라 파일에 저장하지 않는다.
    enum BeautyTarget: Hashable {
        case all
        case gender(Gender)
        /// 찾은 얼굴(기록이 있든 없든). 왼쪽부터 센 인덱스.
        case face(Int)
        /// 짝이 없는 사람 기록.
        case person(PersonID)
    }

    /// 사진마다 마지막으로 본 대상. 앱을 다시 열면 전체다.
    var beautyTargets: [PhotoID: BeautyTarget] = [:]
    var beautyTarget: BeautyTarget {
        session.selectedPhotoID.flatMap { beautyTargets[$0] } ?? .all
    }

    func setBeautyTarget(_ target: BeautyTarget) {
        guard let id = session.selectedPhotoID else { return }
        endSliderEditIfActive()
        beautyTargets[id] = target
    }

    /// 찾은 얼굴의 anchor. 범위 밖이면 nil.
    func anchor(forFace index: Int) -> PersonAnchor? {
        faces.indices.contains(index) ? PersonAnchor(faceBox: faces[index].boundingBox) : nil
    }

    /// 대상이 가리키는 층. .face는 기록이 있으면 .person, 없으면 nil(첫 변경이 기록을 만든다).
    func scope(for target: BeautyTarget) -> PortraitScope? {
        switch target {
        case .all: return .all
        case .gender(let gender): return .gender(gender)
        case .person(let id): return .person(id)
        case .face(let index):
            return anchor(forFace: index).flatMap { currentRecipe.people.personID(at: $0) }.map(PortraitScope.person)
        }
    }

    /// 대상이 가리키는 얼굴. 전체·그룹은 모든 얼굴.
    var targetedFaces: [FaceGeometry] {
        switch beautyTarget {
        case .all, .gender: return faces
        case .face(let index): return faces.indices.contains(index) ? [faces[index]] : []
        case .person(let id):
            let matches = PersonMatcher.match(currentRecipe.people.individuals, faces: faces.map(\.boundingBox))
            return matches.first { $0.person == id }.map { [faces[$0.faceIndex]] } ?? []
        }
    }
```

`faceAvailability`의 `targets` 계산을 `let targets = targetedFaces`로. `removeSelectedPhoto`에서 `beautyTargets[entry.id] = nil`.

`AppModel+Editing.swift`의 `edit(_:)`:

```swift
    /// 얼굴 의존 변경은 현재 뷰티 대상의 층에 쓴다. 찾은 얼굴을 처음 만지면 기록이 만들어진다.
    func edit(_ change: EditChange) {
        let target = beautyTarget
        guard change.portraitKey != nil || isGenderChange(change) else {
            mutateSelected { $0.set(change) }
            return
        }
        switch target {
        case .face(let index):
            guard let anchor = anchor(forFace: index) else { return }
            mutateSelected { $0.set(change, forPersonAt: anchor) }
        default:
            guard let scope = scope(for: target) else { return }
            mutateSelected { $0.set(change, in: scope) }
        }
    }

    private func isGenderChange(_ change: EditChange) -> Bool {
        if case .gender = change {
            return true
        }
        return false
    }
```

`mutateSelected`가 `.unknownPerson`을 받으면 `statusMessage`를 바꾸지 않고 조용히 끝낸다(`if let rejection = session.edit(...) { switch rejection { case .geometryLocked: statusMessage = …; return; case .unknownPerson: return } }`). `savePreset`에서 `values.portrait.targetFace = nil` 줄 삭제(`PresetValues(of:)`가 개인 층을 버린다). `applyMakeupLook(id:)`는 `document.applyMakeupLook(look, in: scope(for: beautyTarget) ?? .all)`로 — `.face` 대상에 기록이 없으면 `.all`이 아니라 먼저 기록을 만들어야 하므로 `.face(index)`면 `document.set(.makeupIntensity(.lip, 0), forPersonAt: anchor)`로 기록을 만들지 않고, 간단히 룩은 `scope(for:)`가 nil이면 `session.edit`에서 `set(.gender(nil)…)`를 쓰지 않고 다음 도우미를 쓴다: `EditDocument`에 public `personID(creatingAt anchor:)`를 두지 않기로 했으므로(스펙 1.4), 룩 적용은 `.face` 대상에서 기록이 없으면 **빈 변경으로 기록을 만들지 않고** `.all`에 적용하지 않도록 아무것도 하지 않고 `statusMessage = UserMessage.pickASliderFirst`를 보인다. H3이 칩 UI에서 "이 사람" 룩 적용 전에 성별 지정 또는 슬라이더 변경으로 기록이 생기게 하므로 여기서는 이 최소 규칙만 둔다.

`UserMessage.swift`에 추가: `beautyTargetLabel`("대상"), `beautyTargetAll`("전체"), `beautyTargetGender(_:)`(남성/여성 → "남성 그룹"/"여성 그룹"), `beautyTargetFace(_ number: Int)`("사람 \(number)"), `pickASliderFirst`("이 사람에게 룩을 적용하려면 먼저 슬라이더를 움직이거나 성별을 지정해 주세요."). `faceCount`·`faceOrdinal`·`allFaces`는 쓰는 곳이 없어지면 지운다.

`BeautyPanel.swift`: 기존 `Picker(UserMessage.faceCount…)`를 다음 임시 피커로 바꾼다(H3이 `TargetChips`로 교체):

```swift
            Picker(
                UserMessage.beautyTargetLabel,
                selection: Binding(get: { model.beautyTarget }, set: { model.setBeautyTarget($0) })
            ) {
                Text(UserMessage.beautyTargetAll).tag(AppModel.BeautyTarget.all)
                ForEach(Gender.allCases, id: \.self) { gender in
                    Text(UserMessage.beautyTargetGender(gender)).tag(AppModel.BeautyTarget.gender(gender))
                }
                ForEach(model.faces.indices, id: \.self) { index in
                    Text(UserMessage.beautyTargetFace(index + 1)).tag(AppModel.BeautyTarget.face(index))
                }
            }
```

`.disabled(model.isGeometryLocked)`는 지운다(대상 전환은 화면 상태). 슬라이더가 보이는 값은 `PortraitResolver.resolve(model.currentRecipe, scope: model.scope(for: model.beautyTarget) ?? .all, estimate: nil)`의 값으로(`.face`에 기록이 없으면 `.all`과 같다). `MakeupPanel`에도 같은 피커를 룩 칩 위에 두고 `makeup` 값을 같은 방식으로 해석한다. 선택 사진이 바뀔 때 `select(_:)`는 `beautyTargets`를 건드리지 않는다(사진마다 기억).

- [ ] **Step 4: 통과 확인**

Run: `grep -rn "targetFace" apple/Sources apple/MellowPhoto` → 출력 없음(스키마·README·테스트의 이행 문구만 남음). `cd apple && swift test` → 패키지 403(Shared 60 · Rendering 263 · Library 33 · Export 4 · Editing 43), 0 failures. Mac 앱 테스트 → `Executed 78 tests, with 0 failures`, `TEST SUCCEEDED`. lint 출력 없음. `./scripts/verify-modules.sh` 통과. `cd apple && xcodegen generate --quiet && git diff --exit-code --stat MellowPhoto.xcodeproj` → 출력 없음.

Review Focus 1 확인: Task 5 전 커밋을 임시 worktree(`git worktree add /tmp/h2-before <Task 4 커밋>`)에 받아 `SkinStageTests.testTargetFaceRefinesOnlyThatFace`가 만드는 두 얼굴 이미지에 `targetFace = 0`·피부 0.5 레시피로 렌더한 PNG를 스크래치 폴더에 쓰고, Task 5 뒤 같은 입력(이행된 레시피)의 PNG와 `cmp`로 바이트를 비교한다(임시 XCTest, 커밋하지 않음). 같아야 한다. 임시 worktree는 비교 뒤 `git worktree remove`로 지운다.

- [ ] **Step 5: 커밋**

```bash
git add apple/Sources/MellowShared/API/Adjustments.swift apple/Sources/MellowShared/API/EditRecipe.swift apple/Sources/MellowLibrary/Infrastructure/SessionFileV1.swift apple/Sources/MellowEditing/API/EditChange.swift apple/Sources/MellowEditing/API/EditDocument.swift apple/Sources/MellowRendering/API/RenderStage.swift apple/Sources/MellowRendering/API/AutoEnhancer.swift shared/recipe-schema/edit-recipe.v2.schema.json shared/recipe-schema/README.md apple/MellowPhoto/Application/AppModel.swift apple/MellowPhoto/Application/AppModel+Editing.swift apple/MellowPhoto/Application/AppModel+Library.swift apple/MellowPhoto/Application/UserMessage.swift apple/MellowPhoto/Features/Editor/BeautyPanel.swift apple/MellowPhoto/Features/Editor/MakeupPanel.swift apple/Tests/MellowSharedTests/EditRecipeCodingTests.swift apple/Tests/MellowSharedTests/RecipeSchemaTests.swift apple/Tests/MellowLibraryTests/SessionFileMigrationTests.swift apple/Tests/MellowLibraryTests/ProjectSessionTests.swift apple/Tests/MellowEditingTests/EditDocumentTests.swift apple/Tests/MellowRenderingTests/RenderingTestSupport.swift apple/Tests/MellowRenderingTests/RenderPipelineTests.swift apple/Tests/MellowRenderingTests/SkinStageTests.swift apple/Tests/MellowRenderingTests/MakeupStageTests.swift apple/Tests/MellowRenderingTests/ShapeWarpStageTests.swift apple/Tests/MellowRenderingTests/FeatureStageTests.swift apple/Tests/MellowRenderingTests/AutoEnhancerTests.swift apple/MellowPhotoTests/AppModelTests.swift apple/MellowPhotoTests/EditorScenarioTests.swift
git commit -m "feat!: 옛 targetFace를 개인 층으로 읽기 이행하고 속성을 없앰

옛 \"이 값을 i번 얼굴에만\"은 전체 층을 비우고 i번 사람의 개인 층(legacyIndex)으로 옮긴다.
렌더 결과는 같다. 렌더·편집·앱이 people만 본다. 앱은 임시 대상 피커(전체·성별·사람 n).

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

(`AutoEnhancer.swift`에 바뀐 것이 없으면 `git add` 목록에서 뺀다.)

---

## 자체 검토 결과

- **스펙 대조:** §1.1 → `FaceTarget`·`RenderContext.faceTargets`·네 단계(Task 1), `GenderEstimator`·`GenderEstimate`·`PhotoAnalysis.genderEstimates`·`PreparedPhoto.genders`·`RenderTuning` 3개(Task 2), `EditChange.gender`·`set(_:in:)`·`set(_:forPersonAt:)`·`resetOverrides`·`rebindPerson`·`removePerson`·`bindLegacyPeople`·`applyMakeupLook(_:in:)`(Task 3), 새 import 없음. §1.2 읽기 이행·적용 순서 → Task 5(결정적 id, 옮길 값 없으면 기록 없음, 범위 밖 그대로, `people` 있으면 이행 안 함, H1 더하기만·H2 마지막 Task에서 한 번에). §1.4 → 층 쓰기·클램프·`unknownPerson`·prune·룩 기본 강도 기준·잠금(Task 3), 프리셋·동기화 층 규칙과 G3 `merged` 변경(Task 4). §1.5 → `makeTargets`·단계 반복문·캐시 불변·임계값 준비 때 적용(Task 1·2). §1.6의 `BeautyTarget`·라우팅 → Task 5 최소 변경(칩은 H3). §2 편집·렌더 행 → Task 1~5. §5 → H2 "5 Task, 마지막 Task에서 이행·제거와 앱 최소 변경"과 같다.
- **타입 일관성:** `FaceTarget(index:face:personID:gender:portrait:makeup:blemishes:)`, `RenderContext.makeTargets`, `SkinStage.healSpots(for:in:)`·`healSpots(in:)`, `SyntheticFace.pair`, `RenderingTestSupport.changedPixelsByHalf`·`restricted(_:toFace:of:)`, `StubGenderEstimator`·`FixedFaceAnalyzer`, `PhotoPipeline.acceptedEstimates`, `EditChange.gender`·`portraitKey`, `EditDocument.Rejection.unknownPerson`·`set(_:in:)`·`set(_:forPersonAt:)`·`resetOverrides(_:in:)`·`rebindPerson`·`removePerson`·`bindLegacyPeople`·`applyMakeupLook(_:in:)`, `SyncCategory.portraitKeys`, `EditRecipe.migrateLegacyTargetFace`, `AppModel.BeautyTarget`·`beautyTargets`·`beautyTarget`·`setBeautyTarget`·`anchor(forFace:)`·`scope(for:)`·`targetedFaces`, `UserMessage.beautyTargetLabel`·`beautyTargetAll`·`beautyTargetGender`·`beautyTargetFace`·`pickASliderFirst`를 정의한 Task와 쓰는 Task에서 같게 썼다. 테스트 수: 패키지 387 → 391(T1) → 393(T2) → 398(T3) → 401(T4) → 403(T5), 앱 Mac 78 → 78.
- **Review Focus 매핑:** 1→Task 5(세 모듈 테스트 + 바이트 비교 절차), 2→Task 1, 3→Task 1, 4→Task 3, 5→Task 4, 6→Task 2. 모두 테스트 코드가 있다.
- **플레이스홀더 점검:** "TBD/TODO/나중에" 없음. Task 5의 `.face` 대상 룩 적용은 H3 전까지의 명시적 최소 규칙(안내 문구)으로 적었고, H3 Task 2가 바꾼다.
