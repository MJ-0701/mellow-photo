# 인물 보정 I1 레시피·규칙(이중턱·부유방 키, 체형 층) 구현 계획

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 레시피에 `doubleChin`·`sideChest` 키가 생기고, 체형이 전체 → 성별 그룹 → 개인 층으로 겹치며, 부유방은 여성 그룹·개인 층에만 놓이고, 잠금·동기화·프리셋이 체형 층을 얼굴형과 같은 규칙으로 다룬다.

**Architecture:** MellowShared의 `PortraitLayer`에 `body` 사전을, `PortraitKey`에 `.bodyShape`를 더하고 허용 층 규칙을 `PortraitScope.allows` 한 곳에 둔다. `PortraitResolver`가 체형도 겹쳐 `Resolved.body`로 내고, MellowEditing은 `EditChange.bodyShape`의 `portraitKey`로 기존 층 편집 경로를 그대로 탄다. 렌더는 이 계획에서 바뀌지 않는다(`recipe.body`를 가장 큰 사람에게 거는 지금 동작 유지, 사람별 렌더는 I2).

**Tech Stack:** Swift 5.9 tools / Swift 5 언어 모드, XCTest.

**Spec:** `docs/superpowers/specs/2026-10-21-beauty-i-chin-body-design.md` (에이전트 참조 3·4절).

## 사람이 확인할 것

- **순서.** Task 1 새 키 → 2 체형 층·허용 층·해석 → 3 편집·잠금·동기화 → 4 스키마·문서. Task마다 Opus 구현 → 리뷰.
- **외부 효과가 있는 단계.** 없음(커밋만, 푸시 없음).
- **스펙이 정하지 않아 이 계획이 정한 것.**

| 결정 | 이유 | 바꾸면 비용 |
|---|---|---|
| 허용되지 않는 층(전체·남성 그룹)에 `sideChest`를 보내면 편집은 아무것도 바꾸지 않고 `Rejection.scopeNotAllowed`를 돌려준다. 잠긴 사진이면 `geometryLocked`가 먼저다 | 화면은 그 슬라이더를 숨기므로 이 경로는 프로그램 오류다. 잠금이 먼저인 것은 기존 거절 순서와 같다 | 작음 |
| 전체 층의 `recipe.body.sideChest`는 파일·프리셋에서 읽어 그대로 보존하되 해석에서 0으로 본다 | 파일을 고치지 않아도 렌더가 규칙을 지킨다. 값을 지우면 왕복 동일성이 깨진다 | 작음 |
| I1이 끝난 시점의 렌더는 사람별 체형을 아직 모른다. 개인·그룹 층의 체형 값은 I2 전까지 렌더에 반영되지 않는다 | 묶음을 작게 나눠 리뷰한다. I1만 따로 배포하지 않는다 | 작음 |

- **위험.** `PortraitKey`에 case가 늘어 `switch`가 있는 곳이 모두 컴파일 오류가 난다. 앱 타깃(`UserMessage`, 재설정 메뉴 등)도 고쳐야 Mac 빌드가 된다. Task 3의 마지막 단계에서 Mac 앱을 빌드해 확인한다.
- **사용자 조치.** 없음.

---

## 에이전트 참조

## Global Constraints

- 작업 위치는 worktree `/Users/mj/IdeaProjects/mellow-photo/.claude/worktrees/beauty-body`이고 브랜치는 `beauty-body`다. 브랜치를 바꾸거나 `git stash`를 쓰지 않는다.
- 모든 Swift 명령 앞에 `export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`.
- 패키지 테스트는 `cd apple && swift test`이고 걸리는 시간이 길면 `--filter`로 좁혀 돌린다. Task 끝에는 전체를 한 번 돌린다.
- 로컬 iOS 시뮬레이터 실행 금지. `MELLOW_IOS_TESTS`를 켜지 않는다. Mac 앱 빌드·테스트는 `./scripts/test-apple.sh`가 하는 Mac 대상만 쓴다.
- 한 줄에 한 문장, 세미콜론 금지, 매직 넘버는 명명 상수. 주석·문서는 한국어.
- 한국어 사용자 문구는 앱 타깃(`UserMessage`)에만. 모듈은 `MellowError`만 던진다.
- `docs/architecture/modules.md`의 의존성 표를 지킨다(`scripts/verify-modules.sh`).
- Xcode 26.3 타입 검사 시간 초과를 피한다. CGFloat·Double을 한 식에 섞지 말고, 긴 배열 `+` 사슬은 `var values: [Double] = …` 뒤 `values += …`로 한 줄에 한 묶음씩 붙인다.
- 커밋은 한국어 Conventional Commits이고 끝에 `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`. `git add`는 바꾼 파일 경로만.
- 건드리지 않는 파일: `OneTouchBundle.swift`, `SkinStage.swift`, `BodySkinStage.swift`, `RenderTuning.swift`의 피부 상수 절, `RealPhotoAcceptanceTests.swift`.
- `swift format lint --strict`가 통과해야 한다(`cd apple && swift format lint --strict --recursive Sources Tests MellowPhoto MellowPhotoTests MellowPhotoUITests`).

## Review Focus

1. 옛 세션 파일(새 키가 없는 레시피·층)은 이전과 같은 값으로 읽히고 다시 쓰면 같은 JSON이 나와야 한다. 빈 `body` 층 사전은 인코드에서 빠진다.
2. 프리셋이나 손상 파일이 전체 층·남성 그룹 층에 `sideChest`를 담고 와도 해석 결과의 `sideChest`는 0이다(편집 거절과 별개).
3. 잠긴 사진에서 그룹·개인 층의 체형 키 변경·재설정·사람 삭제·다시 연결은 모두 거절된다(얼굴형과 같은 조건).
4. 동기화로 체형을 복사하면 받는 사진의 개인 층 체형 키만 지워지고 다른 개인 키(피부 등)는 남는다.
5. 원터치 적용·해제는 어느 층의 체형 키도 바꾸지 않는다.

---

### Task 1: 이중턱·부유방 키

**Files:**
- Modify: `apple/Sources/MellowShared/API/FaceShapeAdjustments.swift`
- Modify: `apple/Sources/MellowShared/API/BodyShapeAdjustments.swift`
- Modify: `apple/Sources/MellowShared/API/AdjustmentRange.swift`
- Modify: `apple/Sources/MellowRendering/API/RenderTuning.swift` (체형 절에 두 상수만, Task 1에서는 기존 `faceShapeMaxShift`·`bodyItemMaxShift`의 switch를 채우는 데 필요)
- Modify: `apple/MellowPhoto/Application/UserMessage.swift` (`faceShapeTitle`·`bodyShapeTitle` switch)
- Test: `apple/Tests/MellowSharedTests/EditRecipeCodingTests.swift`

**Interfaces:**
- Produces: `FaceShapeKey.doubleChin`(마지막 case), `FaceShapeAdjustments.doubleChin: Double`, `BodyShapeKey.sideChest`(마지막 case), `BodyShapeAdjustments.sideChest: Double`, `AdjustmentRange.faceShape(.doubleChin) == AdjustmentRange.unit`, `AdjustmentRange.bodyShape(.sideChest) == AdjustmentRange.unit`, `RenderTuning.faceDoubleChinMaxShift: Double = 0.035`, `RenderTuning.bodySideChestMaxShift: Double = 0.03`.

- [ ] **Step 1: 실패하는 테스트를 쓴다**

`EditRecipeCodingTests`에 다음을 더한다.
- `testDoubleChinAndSideChestDecodeAsZeroWhenMissing`: 두 키가 없는 기존 v2 JSON 픽스처 문자열을 디코드하면 `recipe.portrait.face.doubleChin == 0`, `recipe.body.sideChest == 0`.
- `testDoubleChinAndSideChestRoundTrip`: `doubleChin = 0.4`, `sideChest = 0.7`인 레시피를 인코드·디코드하면 같다.
- `testNewShapeKeysAreUnitRange`: `AdjustmentRange.faceShape(.doubleChin) == 0...1`, `AdjustmentRange.bodyShape(.sideChest) == 0...1`, `FaceShapeKey.allCases.last == .doubleChin`, `BodyShapeKey.allCases.last == .sideChest`.

- [ ] **Step 2: 실패를 확인한다**

Run: `cd apple && swift test --filter EditRecipeCodingTests`
Expected: 컴파일 오류(`doubleChin`·`sideChest` 없음).

- [ ] **Step 3: 키와 범위를 더한다**

두 구조체에 저장 속성·`init` 기본값 0·`decodeIfPresent ?? 0`·subscript case를 더한다. `AdjustmentRange.faceShape(_:)`는 `.smile`·`.doubleChin`에 unit, `bodyShape(_:)`는 `.legLength`·`.sideChest`에 unit이다. `RenderTuning`의 `faceShapeMaxShift(.doubleChin)`은 `faceDoubleChinMaxShift`, `bodyItemMaxShift(.sideChest)`는 `bodySideChestMaxShift`를 돌려준다. 두 상수는 기존 체형 상수 바로 아래에 둔다. `BodyShapeRig.primitives(for:)`의 switch에는 `.sideChest`에서 빈 배열을 돌려주는 임시 case를 두고 주석에 "I2 Task 4에서 채움"을 적는다. `FaceShapeRig.primitives(for:)`의 `.doubleChin`도 같다. `UserMessage.faceShapeTitle(.doubleChin)`은 "이중턱", `bodyShapeTitle(.sideChest)`는 "부유방"이다.

- [ ] **Step 4: 통과를 확인한다**

Run: `cd apple && swift test --filter "EditRecipeCodingTests|FaceShapeRigTests|BodyShapeRigTests"`
Expected: 모두 통과.

- [ ] **Step 5: 커밋**

```bash
git add apple/Sources/MellowShared/API/FaceShapeAdjustments.swift apple/Sources/MellowShared/API/BodyShapeAdjustments.swift apple/Sources/MellowShared/API/AdjustmentRange.swift apple/Sources/MellowRendering/API/RenderTuning.swift apple/Sources/MellowRendering/Domain/FaceShapeRig.swift apple/Sources/MellowRendering/Domain/BodyShapeRig.swift apple/MellowPhoto/Application/UserMessage.swift apple/Tests/MellowSharedTests/EditRecipeCodingTests.swift
git commit -m "feat(shared): 이중턱·부유방 레시피 키 추가"
```

### Task 2: 체형 층·허용 층·해석

**Files:**
- Modify: `apple/Sources/MellowShared/API/PeopleAdjustments.swift`
- Modify: `apple/Sources/MellowShared/API/PortraitResolver.swift`
- Modify: `apple/Sources/MellowShared/API/EditRecipe.swift` (`dependsOnBody`)
- Modify: `apple/Sources/MellowRendering/API/RenderStage.swift` (`applied(to:makeup:body:)` 호출 맞춤만, 값은 아직 안 씀)
- Test: `apple/Tests/MellowSharedTests/PortraitLayerTests.swift`, `apple/Tests/MellowSharedTests/PortraitResolverTests.swift`

**Interfaces:**
- Consumes: Task 1의 키.
- Produces:
  - `PortraitKey.bodyShape(BodyShapeKey)`, `PortraitKey.bodyShapes: Set<PortraitKey>`, `PortraitKey.isShape: Bool`(`.faceShape`·`.bodyShape`), `PortraitKey.all`에 체형 포함.
  - `PortraitLayer.body: [BodyShapeKey: Double]`(init 인자 `body:` 기본 `[:]`, JSON 키 `body`).
  - `PortraitLayer.applied(to portrait: inout PortraitAdjustments, makeup target: inout MakeupAdjustments, body: inout BodyShapeAdjustments)`. 기존 두 인자 이름은 그대로다.
  - `PortraitScope.allows(_ key: PortraitKey) -> Bool` (스펙 3.3 코드 그대로).
  - `PortraitResolver.Resolved.body: BodyShapeAdjustments`(init 인자 `body:` 기본 `BodyShapeAdjustments()`).
  - `PortraitResolver.allLayerBody(_ recipe: EditRecipe) -> BodyShapeAdjustments`.

- [ ] **Step 1: 실패하는 테스트를 쓴다**

`PortraitLayerTests`:
- `testBodyLayerRoundTripsAndOmitsWhenEmpty`: `PortraitLayer(body: [.waist: -0.5])` 인코드 JSON에 `"body":{"waist":-0.5}`가 있고 디코드하면 같다. `PortraitLayer()`의 JSON에는 `body` 키가 없다.
- `testBodyKeysCountAsOverriddenAndEffect`: `body: [.arms: 0]`은 `overriddenKeys == [.bodyShape(.arms)]`이고 `hasEffect == false`다. `body: [.arms: 0.2]`는 `hasEffect == true`이고 `numericValues`에 0.2가 있다. `remove([.bodyShape(.arms)])` 뒤 `body`가 비고 `isEmpty == true`다.
- `testIsShapeCoversFaceAndBody`: `.faceShape(.jaw).isShape`, `.bodyShape(.waist).isShape`는 true, `.skinSmoothing.isShape`는 false. `PortraitKey.all.isSuperset(of: PortraitKey.bodyShapes)`.

`PortraitResolverTests`:
- `testScopeAllowsSideChestOnlyInFemaleGroupAndPeople`: `.all`·`.gender(.male)`는 `.bodyShape(.sideChest)`에 false, `.gender(.female)`·`.person(PersonID())`는 true. 다른 키(`.bodyShape(.waist)`, `.faceShape(.doubleChin)`)는 네 scope 모두 true.
- `testBodyResolvesAllGroupPersonByKey`: 전체 `body.waist = -0.2`·`arms = -0.1`, 여성 그룹 `body: [.waist: -0.5]`, 개인(성별 미지정 기록) `body: [.arms: -0.8]`. `resolve(recipe, person: record, gender: .female).body`는 waist −0.5·arms −0.8. `gender: nil`이면 waist −0.2·arms −0.8.
- `testSideChestIgnoredInAllLayerAndMaleGroup`: 전체 `body.sideChest = 0.9`, 남성 그룹 `body: [.sideChest: 0.7]`, 여성 그룹 `body: [.sideChest: 0.4]`. 남성 해석 0, 여성 해석 0.4, `gender: nil` 해석 0, 개인 층 `[.sideChest: 0.6]`인 남성 기록 해석 0.6. `allLayerBody(recipe).sideChest == 0`이고 `recipe.body.sideChest`는 0.9 그대로다.
- `testDependsOnBodySeesLayers`: 전체 체형 0이고 개인 층 `body: [.waist: -0.3]`이면 `dependsOnBody == true`. 전체 층 `sideChest`만 0.5면 `dependsOnBody == false`.

- [ ] **Step 2: 실패를 확인한다**

Run: `cd apple && swift test --filter "PortraitLayerTests|PortraitResolverTests"`
Expected: 컴파일 오류.

- [ ] **Step 3: 층·허용 층·해석을 구현한다**

`PortraitLayer`의 Codable은 `decodeNumbers`·`encodeNumbers`를 `BodyShapeKey`로 재사용한다. `numericValues`는 `values += body.values` 한 줄을 더한다. `difference`는 바꾸지 않는다. `PortraitScope.allows`는 `PortraitResolver.swift`의 `PortraitScope` 옆 extension에 둔다. `resolve(_:person:gender:)`는 `allLayerBody(recipe)`에서 시작하고 그룹 층은 `PortraitScope.gender(gender).allows`가 false인 키를 건너뛰며 개인 층은 전부 덮는다. 체형 덮어쓰기는 `applied(to:makeup:body:)` 안에서 하되 그룹 층의 허용 필터는 해석 함수에서 층 사본의 `body`를 걸러 넘기는 방식으로 한다(층 타입은 자기가 어느 scope인지 모른다). `resolve(_:scope:estimate:)`의 `.all` 경우는 `Resolved(portrait:makeup:body: allLayerBody(recipe))`다. `dependsOnBody`는 스펙 3.5 식이다. `RenderStage.makeTargets`는 `resolve` 결과를 그대로 쓰므로 바꿀 것이 없고, 호출부 컴파일만 맞춘다.

- [ ] **Step 4: 통과를 확인한다**

Run: `cd apple && swift test --filter "MellowSharedTests"`
Expected: 모두 통과.

- [ ] **Step 5: 커밋**

```bash
git add apple/Sources/MellowShared/API/PeopleAdjustments.swift apple/Sources/MellowShared/API/PortraitResolver.swift apple/Sources/MellowShared/API/EditRecipe.swift apple/Sources/MellowRendering/API/RenderStage.swift apple/Tests/MellowSharedTests/PortraitLayerTests.swift apple/Tests/MellowSharedTests/PortraitResolverTests.swift
git commit -m "feat(shared): 체형을 성별 그룹·개인 층으로 겹치고 부유방 허용 층 규칙 추가"
```

### Task 3: 편집·잠금·동기화

**Files:**
- Modify: `apple/Sources/MellowEditing/API/EditChange.swift`
- Modify: `apple/Sources/MellowEditing/API/EditDocument.swift`
- Modify: `apple/Sources/MellowEditing/API/SyncCategory.swift`
- Modify: `apple/MellowPhoto/Application/AppModel+Editing.swift` (`Rejection` switch, 잠금 사본 검사)
- Modify: `apple/MellowPhoto/Application/AppModel.swift` (`resolvedFaceShapes` → `resolvedShapes`)
- Modify: 그 밖에 `PortraitKey` switch가 있는 앱 파일(컴파일 오류가 가리키는 곳)
- Test: `apple/Tests/MellowEditingTests/EditDocumentTests.swift`

**Interfaces:**
- Consumes: Task 2의 `PortraitKey.bodyShape`, `PortraitScope.allows`, `PortraitLayer.body`, `PortraitResolver.Resolved.body`.
- Produces:
  - `EditChange.bodyShape(key, _).portraitKey == .bodyShape(key)`.
  - `EditDocument.Rejection.scopeNotAllowed`.
  - `SyncCategory.body.dependsOnFaces == true`, `SyncCategory.body.portraitKeys == PortraitKey.bodyShapes`.
  - 앱: `AppModel.resolvedShapes(of: EditRecipe) -> [ResolvedShape]`, `struct ResolvedShape: Equatable { let face: FaceShapeAdjustments; let body: BodyShapeAdjustments }`(AppModel 안 중첩 타입). 이 정의의 세미콜론은 설명용이고 코드에서는 줄을 나눈다.

- [ ] **Step 1: 실패하는 테스트를 쓴다**

`EditDocumentTests`에 더한다.
- `testBodyShapeGoesToTheTargetLayer`: `set(.bodyShape(.waist, -0.4), in: .gender(.female))` 뒤 `recipe.people.groups[.female]?.body[.waist] == -0.4`이고 `recipe.body.waist == 0`. `set(.bodyShape(.arms, -0.3), forFace: 0, of: [box])`는 새 기록 층 `body[.arms] == -0.3`.
- `testBodyShapeInLayersIsClamped`: 그룹 층에 `waist` 5를 보내면 1, 개인 층에 `sideChest` −1을 보내면 0.
- `testSideChestRejectedOutsideFemaleGroupAndPeople`: `set(.bodyShape(.sideChest, 0.5), in: .all)`과 `in: .gender(.male)`은 `.scopeNotAllowed`를 돌려주고 레시피·실행 취소 스택이 그대로다. `in: .gender(.female)`과 남성 수동 성별 기록의 `.person(id)`은 성공한다.
- `testLockedPhotoRejectsLayerBodyEdits`: 수동 편집(`appendLocalEdit`)이 있는 사진에서 그룹 층 체형 변경은 `.geometryLocked`, 개인 층에 체형 키가 있는 기록의 `removePerson`·`rebindPerson`은 `.geometryLocked`, 그 층의 `resetOverrides([.bodyShape(.waist)], in: .person(id))`는 `.geometryLocked`. 잠긴 사진에서 `set(.bodyShape(.sideChest, 0.5), in: .all)`은 `.geometryLocked`다(잠금이 먼저).
- `testResetAllLayerBodyKey`: 전체 층 `body.waist = -0.5`에서 `resetOverrides([.bodyShape(.waist)], in: .all)` 뒤 0. 잠긴 사진에서는 0이 아닌 값을 되돌릴 때 `.geometryLocked`.
- `testSyncBodyCopiesGroupsAndClearsIndividualBodyKeysOnly`: 원본 프리셋 값의 전체 `body.waist = -0.3`, 여성 그룹 `body: [.sideChest: 0.5]`. 받는 사진의 개인 기록 층이 `body: [.waist: -0.9]`, `skinSmoothing: 0.4`. `applyFromBatch(values, categories: [.body])` 뒤 받는 사진의 전체 `waist` −0.3, 여성 그룹 `sideChest` 0.5, 개인 층 `body` 비고 `skinSmoothing` 0.4 유지.
- `testOneTouchLeavesBodyLayersAlone`: 그룹·개인 층에 체형 값이 있을 때 `applyOneTouch(strength: 0.6, in: .all)`과 `applyOneTouch(strength: 0, in: .all)` 뒤 모든 층의 `body`가 그대로다.

- [ ] **Step 2: 실패를 확인한다**

Run: `cd apple && swift test --filter EditDocumentTests`
Expected: 새 테스트 실패(체형이 전체 층으로만 감, `scopeNotAllowed` 없음).

- [ ] **Step 3: 편집 규칙을 넓힌다**

- `EditChange.portraitKey`에 `.bodyShape(let key, _): return .bodyShape(key)`를 더한다.
- `set(_:in:)`은 잠금 검사 뒤, `apply` 전에 `change.portraitKey`가 있고 `!scope.allows(key)`면 `.scopeNotAllowed`를 돌려준다.
- `write(_:key:into:beneath:)`에 `.bodyShape(let shape, let value): layer.body[shape] = EditingPolicy.clamped(value, to: EditingPolicy.bodyShapeRange(shape))`.
- `resetOverrides`의 전체 층 판정은 `.faceShape`와 같은 방식으로 `.bodyShape(let shape)`일 때 `recipe.body[shape] != 0`을 본다. 층 판정은 `isFaceShape`를 `isShape`로 바꾼다.
- `carriesFaceShape`를 `carriesShape`로 이름을 바꾸고 `isShape`로 판정한다. 주석의 "얼굴형"을 "얼굴형·체형"으로 고친다.
- `resetAllLayer`·`copy`의 switch에 `.bodyShape` case를 더한다(`recipe.body[shape] = 0`, `target.body[shape] = source.body[shape]`).
- `SyncCategory.body`를 `dependsOnFaces` true 쪽으로 옮기고 `portraitKeys`에 `PortraitKey.bodyShapes`를 준다. `merged`는 이미 `portraitKeys`로 그룹 복사·개인 지우기를 하므로 다른 변경이 없다.
- 앱: `mutateSelected`의 `Rejection` switch에 `.scopeNotAllowed`를 더해 조용히 끝낸다(화면이 숨기므로). `resolvedFaceShapes`를 `resolvedShapes`로 바꾸고 `ResolvedShape(face:body:)`를 비교한다.

- [ ] **Step 4: 통과와 Mac 빌드를 확인한다**

Run: `cd apple && swift test`
Expected: 전부 통과.

Run: `cd apple && xcodebuild -project MellowPhoto.xcodeproj -scheme MellowPhoto -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO build 2>&1 | grep -E "error:|BUILD (SUCCEEDED|FAILED)"`
Expected: `BUILD SUCCEEDED`.

- [ ] **Step 5: 커밋**

```bash
git add apple/Sources/MellowEditing apple/MellowPhoto/Application apple/Tests/MellowEditingTests/EditDocumentTests.swift
git commit -m "feat(editing): 체형을 대상 층에 쓰고 잠금·동기화를 얼굴형과 같은 규칙으로 넓힘"
```

### Task 4: 스키마·문서

**Files:**
- Modify: `shared/recipe-schema/edit-recipe.v2.schema.json`
- Modify: `shared/recipe-schema/README.md`
- Modify: `docs/architecture/modules.md` (MellowShared·MellowEditing 캔버스의 공개 API·규칙)
- Test: `apple/Tests/MellowSharedTests/RecipeSchemaTests.swift`

**Interfaces:**
- Consumes: Task 1~3의 키와 규칙.

- [ ] **Step 1: 실패하는 테스트를 쓴다**

`RecipeSchemaTests`의 키 대조 테스트가 `FaceShapeKey.allCases`·`BodyShapeKey.allCases`와 층 객체의 `body`를 스키마와 대조하도록 기대값을 넓힌다(기존 대조 함수가 allCases를 읽으면 스키마만 고치면 된다). 층 객체(`people.groups.*`, `people.individuals[].layer`)에 `body` 속성이 있어야 한다는 단언을 더한다.

- [ ] **Step 2: 실패를 확인한다**

Run: `cd apple && swift test --filter RecipeSchemaTests`
Expected: 스키마에 `doubleChin`·`sideChest`·층 `body`가 없어 실패.

- [ ] **Step 3: 스키마와 문서를 고친다**

스키마의 얼굴형 객체에 `doubleChin`(0…1), 체형 객체에 `sideChest`(0…1), 층 객체에 `body`(체형 객체와 같은 키, 모두 선택)를 더한다. README에 다음을 적는다. 체형이 층을 가진다. 전체 층 체형은 사진의 모든 사람에게 걸린다(I2부터). `sideChest`는 여성 그룹·개인 층에서만 렌더에 쓰이고 전체·남성 그룹 값은 보존하되 무시한다. `modules.md`의 Shared·Editing 캔버스에 공개 API(`PortraitScope.allows`, `Rejection.scopeNotAllowed`)와 규칙 문장을 더한다.

- [ ] **Step 4: 통과를 확인한다**

Run: `cd apple && swift test --filter "RecipeSchemaTests|MellowLibraryTests"`
Expected: 모두 통과.

Run: `bash scripts/verify-modules.sh`
Expected: 오류 없음.

- [ ] **Step 5: 커밋**

```bash
git add shared/recipe-schema docs/architecture/modules.md apple/Tests/MellowSharedTests/RecipeSchemaTests.swift
git commit -m "docs: 레시피 스키마와 모듈 지도에 체형 층·이중턱·부유방 반영"
```
