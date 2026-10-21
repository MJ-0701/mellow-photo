# 인물 보정 J2 옷 주름 화면·브러시·검증 구현 계획

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 체형 패널에 "옷 주름" 슬라이더와 칠하기·지우기 브러시가 생긴다. 캔버스는 드래그 경로를 획으로 저장하고 칠한 곳을 겹쳐 보인다. 검증 기록과 모듈 문서가 J를 반영한다.

**Architecture:**
- 브러시 모드는 앱 상태(`AppModel.clothingBrush`)이고 파일에 저장하지 않는다.
- 캔버스는 브러시 모드에서만 경로를 모은다. 경로를 원본 좌표로 바꾸고 솎는 일은 순수 함수 `ClothingPath`가 한다. 그래서 테스트가 화면 없이 돈다.
- 저장은 J1의 `EditDocument.appendClothingStroke`가 한다.

**Tech Stack:** SwiftUI + Observation(앱 타깃), XCTest(`MellowPhotoTests`).

**Spec:** `docs/superpowers/specs/2026-10-21-beauty-j-clothing-wrinkles-design.md`. J2에 해당하는 절은 8절, 9절의 앱 테스트, 10절이다. 선행은 J1 전부다.

## 사람이 확인할 것

- **순서.** Task는 아래 4개다. Task마다 Opus가 구현하고, 리뷰한 뒤 고친다. 끝에 전체 리뷰를 한다.
  1. 앱 상태와 획 저장
  2. 캔버스 경로 제스처와 겹쳐 보기
  3. 체형 패널 절과 문구
  4. 검증 기록·문서와 CI
- **외부 효과가 있는 단계.** Task 4 끝의 푸시와 `gh workflow run apple-checks.yml --ref beauty-j-cloth`다. main 병합·TestFlight는 하지 않고 사용자에게 묻는다.
- **사용자 조치.** CI 뒤 실제 사진(셔츠·티셔츠·정장·니트·무늬 옷)으로 자동 결과와 브러시 조작감을 확인한다. iOS 기기 확인도 사용자가 한다.
- **스펙이 정하지 않아 이 계획이 정한 것.**

| 결정 | 이유 | 바꾸면 비용 |
|---|---|---|
| 경로 점은 원본 정규화 거리로 브러시 반지름의 0.25배보다 가까운 점을 버린 뒤, 256개를 넘으면 균등하게 솎는다. 첫 점과 끝 점은 늘 남긴다 | 손가락 떨림 점을 줄이고 모양을 지킨다. 상한은 J1 `clothingStrokeMaxPoints` | 작음 |
| 획 상한(64)에 닿으면 획을 버리고 상태 줄에 안내한다 | J1 규칙(추가 거절)을 그대로 보인다 | 작음 |
| 브러시 모드에서는 확대한 사진의 한 손가락 이동이 칠하기가 된다. 두 손가락 확대·이동은 그대로다 | 잡티·변형 도구와 같은 동작이다 | 작음 |

---

## 에이전트 참조

## Global Constraints

- J1 계획의 Global Constraints를 그대로 따른다(`DEVELOPER_DIR`, worktree, 한 줄 한 문장, 세미콜론 금지, 명명 상수, CI Xcode 26.3, 한국어 커밋과 서명, 로컬 iOS 시뮬레이터 금지).
- 한국어 문구는 모두 `apple/MellowPhoto/Application/UserMessage.swift`에 둔다. 매직 넘버는 `AppModel.Policy`나 `Theme`에 둔다.
- 새 앱 파일을 만들면 `xcodegen generate`(고정 버전)를 돌린다. 생긴 `MellowPhoto.xcodeproj` 변경을 같은 커밋에 넣는다.
- Mac 앱 테스트 명령은 다음과 같다. 기대값은 `TEST SUCCEEDED`다.

```bash
xcodebuild -project apple/MellowPhoto.xcodeproj -scheme MellowPhoto -derivedDataPath apple/build -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO test 2>&1 | grep -E "Executed|TEST (SUCCEEDED|FAILED)|error:"
```

- iOS는 generic 빌드만 한다: `xcodebuild -project apple/MellowPhoto.xcodeproj -scheme MellowPhoto -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build`.
- 병합 뒤 체형 패널에는 beauty-body의 대상 칩이 있다. 옷 절은 칩 아래, 체형 슬라이더 뒤에 둔다. 칩 코드는 바꾸지 않는다.

## Review Focus

1. **자르기·회전한 사진**에서 칠한 경로가 원본 좌표로 바뀌어야 한다(`outputTransform.toOriginal`). 변환을 모르는데 기하가 있으면 저장하지 않아야 한다. Task 1 `testPaintClothingConvertsCroppedCanvasToOriginal`, `testPaintClothingRefusedWithoutTransform`.
2. **다른 도구로 갔다가 돌아오면** 브러시 모드가 꺼져 있어야 한다. 체형 패널을 다시 열 때 실수로 칠하지 않게 하기 위해서다. Task 1 `testLeavingBodyToolTurnsBrushOff`.
3. **확대 중 두 손가락 제스처가 섞인 드래그**는 획을 남기지 않아야 한다(잡티 도구와 같은 `dragSawPinch` 규칙). Task 2에서 리뷰로 확인한다(제스처는 단위 테스트 밖이다).
4. **렌더 중·분석 중**(`isBusy`, `blocksCanvasTouch`)에는 칠하기를 받지 않아야 한다. Task 1 `testPaintClothingIgnoredWhileBusy`.
5. **얼굴도 사람도 없는 사진**에서도 브러시는 켜지고 슬라이더도 움직여야 한다. 칠한 곳이 있으면 효과가 난다(스펙). Task 1 `testCanAdjustClothingWithoutFaces`.

---

### Task 1: 앱 상태와 획 저장

**Files:**
- Create: `apple/MellowPhoto/Application/ClothingPath.swift`
- Modify: `apple/MellowPhoto/Application/AppModel.swift`(상태, `Policy` 상수, `selectTool`)
- Modify: `apple/MellowPhoto/Application/AppModel+Editing.swift`(`paintClothing`, `clearClothingStrokes`)
- Test: `apple/MellowPhotoTests/AppModelTests.swift`, `apple/MellowPhotoTests/ClothingPathTests.swift`(새 파일)

**Interfaces:**
- Consumes: J1 `ClothingStroke`, `EditDocument.appendClothingStroke(_:) -> Bool`, `clearClothingStrokes()`, `EditingPolicy.clothingStrokeMaxPoints`.
- Produces:
  - `enum ClothingBrushMode: Equatable { case paint, erase }`
  - `AppModel.clothingBrush: ClothingBrushMode?`. `selectTool`이 `.body`가 아닌 도구로 바꾸면 nil이 된다.
  - `AppModel.canAdjustClothing: Bool`
    - `isSliderEditActive || currentRecipe.clothing.wrinkles != 0 || !faces.isEmpty || currentRecipe.clothing.hasPaint`
    - 얼굴이 없어도 칠할 수 있어야 하므로 브러시는 이 값과 무관하게 켠다. 슬라이더는 이 값을 쓴다.
    - 얼굴이 없는데 칠한 곳도 없을 때만 슬라이더를 끈다.
  - `AppModel.paintClothing(path: [NormalizedPoint])`. 캔버스 좌표, 원점은 왼쪽 아래다.
  - `AppModel.clearClothingStrokes()`
  - `AppModel.Policy.clothingPathMinimumSpacing = 0.25`(브러시 반지름 배수)
  - `enum ClothingPath { static func originalPoints(_ canvas: [NormalizedPoint], transform: GeometryTransform?, geometryIsIdentity: Bool) -> [NormalizedPoint]?`
    - 변환이 nil이고 기하가 있으면 nil이다.
    - 아니면 `toOriginal`을 적용한다.
  - `static func thinned(_ points: [NormalizedPoint], minimumSpacing: Double, limit: Int) -> [NormalizedPoint]`
    - 첫 점과 끝 점은 남긴다.

- [ ] **Step 1: 실패하는 테스트를 쓴다**

`ClothingPathTests`:

```swift
func testThinnedDropsClosePointsAndKeepsEnds() {
    let points = (0...100).map { NormalizedPoint(x: Double($0) * 0.001, y: 0.5) }
    let thinned = ClothingPath.thinned(points, minimumSpacing: 0.01, limit: 256)
    XCTAssertEqual(thinned.first, points.first)
    XCTAssertEqual(thinned.last, points.last)
    XCTAssertEqual(thinned.count, 11)
}

func testThinnedRespectsLimit() {
    let points = (0..<1000).map { NormalizedPoint(x: Double($0) / 1000, y: 0.5) }
    XCTAssertEqual(ClothingPath.thinned(points, minimumSpacing: 0, limit: 256).count, 256)
}

func testOriginalPointsRefusedWithoutTransformWhenGeometryExists() {
    XCTAssertNil(ClothingPath.originalPoints([NormalizedPoint(x: 0.5, y: 0.5)], transform: nil, geometryIsIdentity: false))
}
```

`AppModelTests`에는 기존 도우미(사진 가져오기·준비)를 써서 다음을 더한다:

```swift
func testPaintClothingStoresOneStrokeWithBrushRadius() async throws
// 도구 .body, clothingBrush .paint, brushRadius 0.03
// paintClothing([(0.2,0.5),(0.4,0.5)])
// 레시피 획 1개, erase false, radius 0.03, 실행 취소 한 번에 0개
func testEraseModeStoresEraseStroke() async throws
func testPaintClothingConvertsCroppedCanvasToOriginal() async throws
// 왼쪽 절반 crop 뒤 캔버스 (1, 0.5) → 원본 x 0.5 근처
func testPaintClothingRefusedWithoutTransform() async throws
// selectedInfo 크기를 모르는 상태 + 기하 있음 → 획 없음
func testPaintClothingIgnoredWhileBusy() async throws
func testLeavingBodyToolTurnsBrushOff() async throws
func testStrokeLimitShowsStatus() async throws
// 64획 뒤 65번째 → 획 수 64, statusMessage == UserMessage.clothingStrokeLimit
func testCanAdjustClothingWithoutFaces() async throws
// 얼굴 없는 사진에서 슬라이더는 꺼짐, 칠한 뒤에는 켜짐, 브러시 모드는 켤 수 있음
```

- [ ] **Step 2: 실패를 확인한다**

Mac 앱 테스트 명령에 `-only-testing:MellowPhotoTests/ClothingPathTests -only-testing:MellowPhotoTests/AppModelTests`를 붙여 돌린다. 기대값은 컴파일 오류다.

- [ ] **Step 3: 구현한다**

- `paintClothing`의 조건은 `touch(from:to:)`와 같다(`isReady`, `!isBusy`, `!blocksCanvasTouch`, `!canvasShowsUncropped`, `!isRendering`).
- `clothingBrush`가 nil이면 아무것도 하지 않는다.
- 경로는 원본 좌표로 바꾸고 솎는다(간격 = `brushRadius × Policy.clothingPathMinimumSpacing`). 그다음 `mutateSelected`로 `appendClothingStroke`를 부른다.
- false를 받으면 `statusMessage = UserMessage.clothingStrokeLimit`이다.
- `UserMessage`에 `clothingStrokeLimit`("브러시 획이 너무 많아요. 모두 지운 뒤 다시 칠해 주세요.")을 더한다.

- [ ] **Step 4: 통과를 확인한다**

같은 명령을 다시 돌린다. 기대값은 PASS다.

- [ ] **Step 5: 커밋한다**

`xcodegen generate`를 돌린 뒤 커밋한다.

```bash
git add apple/MellowPhoto apple/MellowPhotoTests apple/MellowPhoto.xcodeproj
git commit -m "feat(app): 옷 주름 브러시 상태와 획 저장 추가"
```

### Task 2: 캔버스 경로 제스처와 겹쳐 보기

**Files:**
- Modify: `apple/MellowPhoto/Features/Editor/PhotoCanvasView.swift`(`touchLayer`, 새 `clothingOverlay(in:)`)
- Modify: `apple/MellowPhoto/Application/AppModel.swift`(`canvasTakesClothingPaint`)
- Modify: `apple/MellowPhoto/Application/Theme.swift`(색·불투명도 상수)
- Test: `apple/MellowPhotoTests/ClothingPathTests.swift`(겹쳐 보기 좌표 변환)

**Interfaces:**
- Consumes: Task 1 `paintClothing(path:)`, `clothingBrush`, `ClothingPath`.
- Produces:
  - `AppModel.canvasTakesClothingPaint: Bool`(`tool == .body && clothingBrush != nil && !blocksCanvasTouch`)
  - `ClothingPath.canvasPoints(_ original: [NormalizedPoint], transform: GeometryTransform?) -> [NormalizedPoint]`. 겹쳐 보기용이고 `toOutput`이 nil인 점은 뺀다.
  - `Theme.clothingPaintColor`(파랑, `Theme.accent`와 다르면 `.blue`), `Theme.clothingEraseColor`(`.red`), `Theme.clothingOverlayOpacity = 0.35`

- [ ] **Step 1: 실패하는 테스트를 쓴다**

```swift
func testCanvasPointsRoundTripThroughCrop() {
    // crop 왼쪽 절반 변환
    // originalPoints(canvasPoints(x))가 x와 1e-9 안
    // 잘려 나간 원본 점(x 0.9)은 canvasPoints에서 빠짐
}
```

- [ ] **Step 2: 실패를 확인한다**

Mac 앱 테스트에 `-only-testing:MellowPhotoTests/ClothingPathTests`를 붙여 돌린다. 기대값은 FAIL이다.

- [ ] **Step 3: 구현한다**

`touchLayer` 맨 앞에 분기를 둔다.
- 조건은 `model.canvasTakesClothingPaint`이다.
- `DragGesture(minimumDistance: 0)`을 쓴다.
  - `onChanged`는 위치를 `@State clothingPath`에 정규화해 더하고, 첫 이벤트에서 `dragSawPinch`를 기록한다.
  - `onEnded`는 pinch가 없었을 때만 `model.paintClothing(path:)`를 부르고 경로를 비운다.

`clothingOverlay(in:)`에 그리는 것은 다음과 같다.
- 모드가 켜져 있거나 획이 있을 때, 레시피 획마다 `Path`를 그린다(`addLines`, 둥근 끝·이음, 선 폭은 `radius × 2 × min(size) × outputToOriginalScale`).
- 획 색은 칠하기 파랑, 지우기 빨강이고 불투명도는 0.35다.
- 진행 중인 `clothingPath`도 같은 색으로 그린다.
- `.allowsHitTesting(false)`다.
- 비교 분할 모드(`compareMode == .split`)에서는 그리지 않는다.

- [ ] **Step 4: 통과를 확인하고 빌드한다**

Mac 앱 테스트와 iOS generic 빌드를 돌린다. 기대값은 PASS와 `BUILD SUCCEEDED`다.

- [ ] **Step 5: 커밋한다**

```bash
git add apple/MellowPhoto apple/MellowPhotoTests
git commit -m "feat(app): 옷 주름 브러시 경로 제스처와 칠한 영역 표시 추가"
```

### Task 3: 체형 패널 절과 문구

**Files:**
- Create: `apple/MellowPhoto/Features/Editor/ClothingSection.swift`
- Modify: `apple/MellowPhoto/Features/Editor/BodyPanel.swift`(체형 슬라이더와 안내 뒤에 `ClothingSection()`)
- Modify: `apple/MellowPhoto/Application/UserMessage.swift`
- Test: `apple/MellowPhotoTests/AppModelTests.swift`(문구 매핑 한 개), 화면은 리뷰로 확인한다

**Interfaces:**
- Consumes:
  - Task 1 상태·함수
  - `AdjustmentSlider(title:value:range:snapsToZero:change:)`
  - `EditingPolicy.clothingRange`
  - `.clothing(key, $0)`(J1 `EditChange`)
  - `AppModel.Policy.brushRadiusRange`
- Produces: `UserMessage` 문구.

| 이름 | 문구 |
|---|---|
| `clothingSectionTitle` | 옷 |
| `clothingTitle(.wrinkles)` | 옷 주름 |
| `clothingAppliesToAll` | 모든 사람에 적용 |
| `clothingPaint` | 칠하기 |
| `clothingErase` | 지우기 |
| `clothingClear` | 브러시 모두 지우기 |
| `clothingBrushSize` | 브러시 크기 |
| `clothingHint` | 칠한 곳이 있으면 그곳에만 적용돼요. 무늬 옷이나 깊은 구김은 덜 펴져요. |
| `clothingStrokeLimit` | (Task 1) |

절의 순서는 다음과 같다.
1. 제목 줄: `clothingSectionTitle`. 대상이 전체가 아니면 옆에 `clothingAppliesToAll` 캡션을 붙인다(병합 코드의 대상 상태 이름을 확인).
2. `ForEach(ClothingKey.allCases)` 슬라이더(`.disabled(!model.canAdjustClothing)`)
3. 칠하기·지우기 토글 두 개. `clothingBrush`를 바꾸고, 같은 것을 다시 누르면 nil이 된다.
4. 브러시 크기 슬라이더(`BrushPanel`과 같은 바인딩·범위·접근성 라벨 `clothingBrushSize`)
5. 획이 있을 때만 "브러시 모두 지우기" 버튼
6. 안내 캡션

- [ ] **Step 1: 실패하는 테스트를 쓴다**

```swift
func testClothingTitles() {
    XCTAssertEqual(UserMessage.clothingTitle(.wrinkles), "옷 주름")
}
```

- [ ] **Step 2: 실패를 확인한다**

기대값은 컴파일 오류다.

- [ ] **Step 3: 구현한다**

`ClothingSection`을 만들고 `BodyPanel`에 넣는다. 그다음 `xcodegen generate`를 돌린다.

- [ ] **Step 4: 통과를 확인하고 빌드한다**

Mac 앱 테스트 전체와 iOS generic 빌드를 돌린다. 기대값은 `TEST SUCCEEDED`, `BUILD SUCCEEDED`다.

- [ ] **Step 5: 커밋한다**

```bash
git add apple/MellowPhoto apple/MellowPhotoTests apple/MellowPhoto.xcodeproj
git commit -m "feat(app): 체형 패널에 옷 주름 슬라이더와 브러시 절 추가"
```

### Task 4: 검증 기록·문서와 CI

**Files:**
- Modify: `VALIDATION.md`(J1 절 아래에 J2를 쓴다. 사람 확인 영역만 쓰고, 수행하지 않은 기기 확인은 "미수행"으로 적는다)
- Modify: `docs/architecture/modules.md`(MellowShared 캔버스의 공개 타입에 `ClothingAdjustments` 계열, MellowRendering 단계 목록에 `clothing`, MellowEditing에 획 편집)
- Modify: `apple/MellowPhotoTests/EditorScenarioTests.swift`(시나리오 하나를 더할지는 아래 Step 1이 정한다)

- [ ] **Step 1: 시나리오 테스트를 쓴다**

```swift
func testClothingScenarioPaintsThenUndoes() async throws
// group-01 준비 → 체형 도구 → 옷 주름 0.8 → 칠하기 모드에서 경로 하나 → 렌더 완료
// → 실행 취소 → 획 0, 강도 0.8 유지
```

기존 시나리오 도우미를 쓴다. 시나리오 테스트가 생성 사진을 앱 테스트 번들에서 읽지 못하면 이 Step을 건너뛴다. 이유를 VALIDATION에 적는다.

- [ ] **Step 2: 문서를 고친다**

VALIDATION J2 절에 적을 것은 다음과 같다.
- 자동 테스트 결과
- CI 결과 자리
- 사용자 확인 항목(실제 사진 다섯 종, 브러시 조작감, 체형 변형과 함께 쓸 때 칠한 자리가 조금 어긋나는 것, iOS 기기)

`modules.md`는 공개 API와 단계 목록만 고친다.

- [ ] **Step 3: 전체 검증을 한다**

`export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer && ./scripts/test-apple.sh`를 돌린다. 기대값은 모든 검사 통과와 `TEST SUCCEEDED`다.

- [ ] **Step 4: 커밋한다**

```bash
git add VALIDATION.md docs/architecture/modules.md apple/MellowPhotoTests
git commit -m "docs: 옷 주름 J2 검증 기록과 모듈 지도 갱신"
```

- [ ] **Step 5: 푸시하고 CI를 확인한다**

```bash
git push origin beauty-j-cloth
gh workflow run apple-checks.yml --ref beauty-j-cloth
gh run list --workflow apple-checks.yml --branch beauty-j-cloth --limit 1
```

기대값은 conclusion이 `success`인 것이다. 결과를 VALIDATION에 한 줄로 적고 커밋·푸시한다. main 병합·TestFlight는 사용자에게 묻는다.
