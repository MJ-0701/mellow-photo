# 인물 보정 I3 화면·검증(체형 대상 칩·생성 사진·수용 테스트) 구현 계획

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 체형 패널이 대상 칩으로 사람·성별 층을 고르고 이중턱·부유방 슬라이더가 규칙대로 보이며, 가상 인물 사진 4장으로 실사진 수용 테스트가 "폰에서 보이는 하한"과 "자연스러움 상한"·배경 직선·팔 끌림·남녀 규칙을 묶는다.

**Architecture:** 앱은 기존 `TargetChips`·`AppModel.scopedValues`·`edit(_:)` 경로를 체형에도 쓴다. 생성 사진은 codex CLI로 만들어 `shared/fixtures/body/`와 테스트 타깃 사본에 둔다. 수용 테스트는 새 파일 `ShapeAcceptanceTests.swift`에서 실제 Vision으로 준비한 분석을 쓰고 이동량은 GPU 지도(`DisplacementWarp.field(groups:extent:limit:)`)로, 픽셀 변화는 렌더 결과로 잰다.

**Tech Stack:** SwiftUI + Observation, XCTest, Vision, codex-cli 0.163.0(`/Users/mj/.local/bin/codex`, 이미지 생성), `sips`, XcodeGen.

**Spec:** `docs/superpowers/specs/2026-10-21-beauty-i-chin-body-design.md` (사람 확인 영역의 "자연스러움 기준", 에이전트 참조 6·7·8절). 선행: I1·I2 전부(Task 1 생성 사진은 먼저 해도 된다).

## 사람이 확인할 것

- **순서.** Task 1 생성 사진(I1과 병행 가능) → 2 체형 패널 → 3 수용 테스트 → 4 문서·VALIDATION·전체 검증. Task마다 Opus 구현 → 리뷰.
- **돈·시간·외부 효과가 있는 단계.** Task 1은 codex CLI 이미지 생성(OpenAI 사용량, 4장, 재생성 포함 최대 8번)이다. 사용자가 2026-10-21에 승인했다. 푸시·CI·TestFlight는 이 계획 밖이고 컨트롤러가 사용자에게 묻고 한다.
- **스펙이 정하지 않아 이 계획이 정한 것.**

| 결정 | 이유 | 바꾸면 비용 |
|---|---|---|
| 생성 사진이 조건(이중턱이 보임, 팔이 몸통에서 떨어짐, 두 사람 어깨가 거의 닿음, 직선 배경)을 못 맞추면 같은 프롬프트를 고쳐 최대 두 번 다시 만든다. 그래도 안 되면 가장 가까운 것을 쓰고 README에 적는다 | 비용 상한을 둔다. 수용 기준 값은 바꾸지 않는다 | 작음 |
| 수용 테스트의 하한·상한 수치는 스펙 표 그대로다. 측정이 기준을 못 맞추면 상수(`RenderTuning`·rig 비율)를 스펙이 허용하는 범위에서 고치고, 기준 자체는 바꾸지 않는다 | "통과하도록 기준을 옮기는 것"을 막는다 | 작음 |
| Vision 인스턴스 마스크가 없는 기계에서는 이웃·남성 영역 검사를 `XCTSkip`으로 건너뛰고 VALIDATION에 건너뜀으로 적는다 | 수행하지 않은 검증을 통과로 쓰지 않는다(저장소 규칙) | 작음 |

- **위험.** 생성 사진에서 Vision 목·어깨 관절이 실사진과 다르게 잡힐 수 있다. 테스트는 관절이 잡히지 않으면 실패로 둔다(건너뛰지 않음). 사진을 다시 만드는 것이 대응이다.
- **사용자 조치.** TestFlight 빌드에서 실제 사진으로 이중턱·부유방·허리의 자연스러움 확인(VALIDATION에 적음).

---

## 에이전트 참조

## Global Constraints

I1·I2 계획의 Global Constraints를 그대로 따른다. 이 계획에서 더하는 것:

- 앱 파일을 새로 만들면 `cd apple && xcodegen generate`를 돌리고 바뀐 `MellowPhoto.xcodeproj`를 함께 커밋한다(`./scripts/test-apple.sh`가 차이를 검사한다).
- 생성 사진은 긴 변 1024px JPEG(`sips -Z 1024 -s format jpeg -s formatOptions 90`), 4장 합계 2 MB 이내다. 테스트 타깃 사본은 `apple/Tests/MellowRenderingTests/Fixtures/body/`이고, 테스트 번들 리소스 규칙은 기존 `Fixtures/people`과 같다(`Package.swift`의 리소스 선언을 확인하고 필요하면 더함).
- Evoto 이미지를 저장소에 넣지 않는다.
- 모든 프롬프트에 "fictional people who do not resemble any real person or celebrity, no text, no watermark, no logos"를 넣는다.
- 사용자 문구 예시는 아래 Task 2 표 그대로 쓴다.

## Review Focus

1. 성별 미지정 사람을 대상으로 고르면 부유방 슬라이더가 보이고(개인 층 허용), 전체·남성 대상에서는 보이지 않으며 안내 문구가 보인다.
2. 대상 사람의 얼굴과 짝인 몸이 없으면 체형 슬라이더가 꺼지되 0이 아닌 값은 0으로 되돌릴 수 있다.
3. 잠긴 사진에서 체형 패널의 모든 슬라이더가 꺼지고 잠금 안내가 보인다(대상과 무관).
4. 수용 테스트가 렌더 경로와 같은 지도·같은 분석을 쓴다(테스트 전용 계산으로 통과하지 않는다).
5. 격자 직선 검사는 실루엣 근처 띠를 빼고 나머지 모든 격자선을 본다(일부 행만 보지 않는다).

---

### Task 1: 생성 사진 4장

**Files:**
- Create: `shared/fixtures/body/chin-01.jpg`, `torso-01.jpg`, `couple-body-01.jpg`, `lines-01.jpg`
- Create: `shared/fixtures/body/labels.json`, `shared/fixtures/body/README.md`
- Create: `apple/Tests/MellowRenderingTests/Fixtures/body/` 아래 같은 4장 사본과 `labels.json`
- Modify: `apple/Package.swift`(리소스 선언이 폴더 단위가 아니면)

- [ ] **Step 1: 스크래치 폴더에서 codex로 사진마다 한 번 만든다**

스크래치는 컨트롤러가 알려 주는 scratchpad 아래 `body-raw/`다. 사진마다 다음 형태로 부른다(플래그는 `codex exec --help`로 확인).

```bash
/Users/mj/.local/bin/codex exec --cd <스크래치>/body-raw "Use the image generation tool to create ONE photorealistic photo and save it to ./chin-01.png. Content: ... They are fictional people who do not resemble any real person or celebrity. No text, no watermark, no logos. Square 1024x1024."
```

| 파일 | Content 문장 |
|---|---|
| `chin-01.png` | a man in his late 30s, front view head and shoulders, slight smile, visible soft double chin under the jawline, plain light grey studio background, collared shirt, face about 35% of image width |
| `torso-01.png` | a woman in her late 20s, front view from head to hips, fitted sleeveless black top, arms relaxed and held slightly away from the torso with a clear gap between arms and waist, plain light studio background, both shoulders and hips visible |
| `couple-body-01.png` | a man and a woman in their 30s standing side by side facing the camera from head to hips, shoulders almost touching, man on the left, both torsos clearly visible in fitted t-shirts, simple indoor background |
| `lines-01.png` | a woman in her 30s, front view from head to hips, arms slightly away from the torso, standing in front of a white tiled wall with a straight vertical door frame on each side and horizontal tile lines, even lighting |

- [ ] **Step 2: 눈으로 확인한다**

각 PNG를 Read로 열어 조건(위 표)을 본다. 조건을 못 맞추면 Content를 고쳐 최대 두 번 더 만든다. 실존 인물처럼 보이거나 글자가 있으면 버린다.

- [ ] **Step 3: Vision이 잡는지 확인한다**

임시 XCTest나 스크립트 없이, Task 3의 테스트가 쓰는 조건을 미리 본다: `chin-01`은 얼굴 1개·윤곽 특징점, `torso-01`·`lines-01`은 몸 1개에 두 어깨·두 엉덩이·팔꿈치, `couple-body-01`은 얼굴 2개·몸 2개. 확인 방법은 `apple/Tests/MellowRenderingTests/VisionBodyAnalyzerTests.swift`와 같은 방식의 테스트를 Task 3 파일에 먼저 써서 돌리는 것이다(Task 3 Step 1의 `testFixturesAreAnalyzable`). 이 단계에서는 사진만 확정한다.

- [ ] **Step 4: JPEG로 바꾸고 라벨·README를 쓴다**

`sips -Z 1024 -s format jpeg -s formatOptions 90 <in>.png --out shared/fixtures/body/<name>.jpg`. `labels.json`은 `people` 폴더와 같은 형식(version 1, photos[].people[] 왼쪽부터 gender·ageBand·glasses·pose·occlusion·ambiguous)이고 사진마다 `notes` 문자열(조건 충족 여부)을 더한다. README는 `shared/fixtures/people/README.md`와 같은 구성(생성 도구·날짜·프롬프트 요지·가상 인물·용도·사용 조건·라벨 형식)이다. 테스트 타깃에 4장과 `labels.json`을 복사한다.

- [ ] **Step 5: 커밋**

```bash
git add shared/fixtures/body apple/Tests/MellowRenderingTests/Fixtures/body apple/Package.swift
git commit -m "test(fixtures): codex로 만든 이중턱·상반신·커플·직선 배경 가상 인물 사진 4장"
```

### Task 2: 체형 패널

**Files:**
- Modify: `apple/MellowPhoto/Features/Editor/BodyPanel.swift`
- Modify: `apple/MellowPhoto/Application/AppModel.swift` (`bodyAvailability`·`canAdjustBodyShape`·`PhotoInfo.bodyFaceMatches`)
- Modify: `apple/MellowPhoto/Application/UserMessage.swift`
- Test: `apple/MellowPhotoTests/AppModelTests.swift`, `apple/MellowPhotoTests/EditorScenarioTests.swift`

**Interfaces:**
- Consumes: I1 `PortraitScope.allows`, `Resolved.body`, I2 `PreparedPhoto.bodyFaceMatches`.
- Produces:
  - `AppModel.PhotoInfo.bodyFaceMatches: [Int: Int]`.
  - `AppModel.bodyAvailability`는 대상이 `.face(i)`·`.person(id)`이고 그 얼굴과 짝인 몸이 없으면 `.noBodyForTarget`(새 case)이다. 전체·그룹은 지금 판정이다.
  - `AppModel.showsBodyShape(_ key: BodyShapeKey) -> Bool`: `.sideChest`는 현재 대상의 scope가 `allows`일 때만 true다. 기록이 없는 얼굴(`.face(i)`, scope nil)은 개인 층이 될 것이므로 true다.
  - `AppModel.canAdjustBodyShape(_ key: BodyShapeKey) -> Bool`: 잠금이면 false. 그 밖에는 드래그 중이거나, 상태가 `.ready`이고 (`legLength`가 아니거나 대상이 다리 띠를 받는 대상)이거나, 현재 값이 0이 아니면 true다. 다리 띠를 받는 대상은 전체·성별 그룹 또는 몸 0과 짝인 얼굴의 사람이다.

| 문구 키 | 문구 |
|---|---|
| `UserMessage.faceShapeTitle(.doubleChin)` | 이중턱 |
| `UserMessage.bodyShapeTitle(.sideChest)` | 부유방 |
| `UserMessage.sideChestScopeHint` | 부유방은 여성 그룹이나 사람을 골라 조정해요 |
| `UserMessage.noBodyForTarget` | 이 사람의 몸을 찾지 못했어요 |
| `UserMessage.legLengthLargestOnly` | 다리 길게는 사진에서 가장 큰 사람에게만 걸려요 |
| `UserMessage.bodyHint` | (고침) 선택한 대상의 관절점으로 몸매를 다듬어요. 배경과 팔은 움직이지 않게 보호해요 |

- [ ] **Step 1: 실패하는 테스트를 쓴다**

`AppModelTests`(기존 스텁 준비 도우미로 얼굴·몸·짝을 넣는다):
- `testSideChestHiddenForAllAndMaleTargets`: 대상 `.all`·`.gender(.male)`에서 `showsBodyShape(.sideChest) == false`, `.gender(.female)`·`.face(0)`에서 true.
- `testBodySliderWritesToTheTargetLayer`: 대상 `.gender(.female)`에서 `edit(.bodyShape(.waist, -0.5))` 뒤 그 그룹 층 값이 −0.5이고 `scopedValues.body.waist == -0.5`, 대상 `.all`의 `scopedValues.body.waist == 0`.
- `testNoBodyForTargetDisablesButAllowsReset`: 얼굴 0이 몸과 짝이 없으면 `.face(0)` 대상에서 `bodyAvailability == .noBodyForTarget`이고 `canAdjustBodyShape(.waist) == false`다. 그 사람 층에 `waist -0.3`이 있으면 true다.
- `testLegLengthOnlyForLargestBodyTarget`: 얼굴 1이 몸 1(가장 큰 몸 아님)과 짝이면 `.face(1)` 대상에서 `canAdjustBodyShape(.legLength) == false`, `.face(0)`(몸 0과 짝)과 `.all`에서 true.
- `testLockedPhotoDisablesBodySliders`: 수동 편집이 있으면 모든 대상에서 `canAdjustBodyShape`가 false다.

`EditorScenarioTests`:
- `testCoupleScenarioSideChestOnlyOnTheWoman`: 커플 준비(스텁 분석, 얼굴 둘·몸 둘·짝), 사람 칩 1에 여성 수동 지정, 대상 `.gender(.female)`, `edit(.bodyShape(.sideChest, 1))`. 렌더 대상(`RenderContext` 생성)에서 여성 몸만 `sideChest == 1`이다.

- [ ] **Step 2: 실패를 확인한다**

Run: `./scripts/test-apple.sh` 대신 Mac 앱 테스트만 돈다.
`cd apple && xcodebuild -project MellowPhoto.xcodeproj -scheme MellowPhoto -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO test -only-testing:MellowPhotoTests/AppModelTests -only-testing:MellowPhotoTests/EditorScenarioTests 2>&1 | grep -E "Executed|error:|TEST (SUCCEEDED|FAILED)"`
Expected: 컴파일 오류 또는 실패.

- [ ] **Step 3: 패널과 모델을 구현한다**

`BodyPanel` 맨 위에 `TargetChips()`(뷰티 패널과 같은 칩, 안내 표시 기본값)를 둔다. 값은 `model.scopedValues.body`이고 슬라이더는 `ForEach(BodyShapeKey.allCases.filter(model.showsBodyShape))`다. 덮어쓴 표시·재설정은 뷰티 패널의 `isOverridden`·`onReset` 인자를 같은 방식으로 단다(`model.overriddenKeys.contains(.bodyShape(key))`, `resetOverrides([.bodyShape(key)])`를 부르는 기존 재설정 경로). 전체·남성 대상이면 슬라이더 목록 아래에 `sideChestScopeHint`를 보인다. 상태 `.noBodyForTarget`이면 `noBodyForTarget` 안내를 보인다. `legLength`가 꺼진 사람 대상이면 `legLengthLargestOnly`를 보인다. `BodyPanel`의 머리 주석 "가장 큰 사람 한 명"을 "선택한 대상"으로 고친다.

- [ ] **Step 4: 통과를 확인한다**

Run: Step 2의 명령.
Expected: `TEST SUCCEEDED`.

- [ ] **Step 5: 커밋**

```bash
git add apple/MellowPhoto apple/MellowPhotoTests
git commit -m "feat(app): 체형 패널에 대상 칩을 두고 부유방은 여성 그룹·사람 대상에서만 보임"
```

### Task 3: 실사진 수용 테스트

**Files:**
- Create: `apple/Tests/MellowRenderingTests/ShapeAcceptanceTests.swift`
- Modify: `apple/Tests/MellowRenderingTests/ShapeTestSupport.swift` (I2 Task 3에서 만든 파일)
- 필요하면 Modify: `RenderTuning` 체형 절·rig 비율 상수(스펙 범위 안, 커밋에 이유)

**Interfaces:**
- Consumes: I2의 `PhotoPipeline`(Vision 얼굴·인물·몸·인스턴스 분석기), `DisplacementWarp.field(groups:extent:limit:)`, `ShapeWarpStage`의 그룹 구성(테스트에서 같은 그룹을 얻도록 `ShapeWarpStage.groups(in: RenderContext) -> [ShapeGroup]`을 internal로 연다), `DisplayScale.phoneWidth`(1170).
- Produces: 없음(테스트).

- [ ] **Step 1: 테스트를 쓴다**

공통: 사진은 `PhotoPipeline(analyzer: VisionFaceAnalyzer(), personAnalyzer: VisionPersonAnalyzer(), bodyAnalyzer: VisionBodyAnalyzer(), instanceAnalyzer: VisionPersonInstanceAnalyzer(), tuning: RenderTuning())`로 준비하고 `preparedAnalysis`로 분석을 얻는다. 폰 px = 미리보기 px × 1170 / 미리보기 폭이다. 측정값은 `record`처럼 테스트 로그에 이름·값을 남긴다(VALIDATION에 옮김).

- `testFixturesAreAnalyzable`: `chin-01` 얼굴 1개·아래턱 윤곽점 3개 이상, `torso-01`·`lines-01` 몸 1개(두 어깨·두 엉덩이·두 팔꿈치), `couple-body-01` 얼굴 2개·몸 2개·`bodyFaceMatches` 2쌍.
- `testDoubleChinIsVisibleAndNatural` (`chin-01`, 전체 층 `doubleChin = 1`): 지도에서 턱 끝 아래 띠(얼굴 좌표 아래 0.05~0.25 얼굴 폭, 입꼬리 사이)의 최대 위쪽 이동 ≥ 3 폰 px이고 ≤ 얼굴 폭 × 0.045. 윤곽점의 최대 |이동| ≤ 0.5 폰 px. 바깥 입술 점 |이동| ≤ 0.05 px. 렌더 픽셀로 턱밑 그늘 띠(`FaceRegions.chinBandMask`)의 평균 휘도 증가 ≤ 12/255.
- `testSideChestIsVisibleAndNatural` (`torso-01`, 여성 그룹 `sideChest = 1`, 얼굴의 사람을 여성으로 지정): 각 쪽 27% 점의 이동 ≥ 2 폰 px이고 ≤ 어깨 폭 × 0.035. 팔 영역(팔 캡슐 반지름 안 × 그 사람 인스턴스 또는 전체 마스크 ≥ 0.5)의 최대 |이동| ≤ 위 이동의 15%.
- `testExistingBodyItemsAreVisibleWithProtection` (`torso-01`): `waist`·`overall`·`arms`·`thighs`·`shoulders`·`neck` 각각 −1과 +1에서 그 항목 원소 중심의 지도 이동 ≥ 2 폰 px(허벅지는 무릎이 없으면 건너뛰고 로그).
- `testBackgroundLinesStayStraight` (`torso-01` 격자 합성과 `lines-01`): 격자 합성은 스펙 7.2다. 체형 전 항목 −1, 전 항목 +1, `doubleChin = 1` 세 레시피마다 실루엣(전체 마스크 ≥ 0.5)에서 (그룹 최대 이동 × 4 + 4px) 밖의 모든 격자선 픽셀 열·행 위치가 0.5px 넘게 움직이지 않는다(격자선 위치는 각 행·열에서 검은 픽셀 중심으로 잼). `lines-01`은 같은 세 레시피에서 실루엣 띠 밖 바뀐 픽셀 비율(Δ ≥ 4) ≤ 0.2%다.
- `testGenderRulesOnTheCouple` (`couple-body-01`, 왼쪽 남성·오른쪽 여성을 수동 지정): 전체 층 `sideChest = 1`과 남성 그룹 `sideChest = 1`은 원본과 같은 바이트. 여성 그룹 `sideChest = 1`은 여성 몸 27% 점 이동 ≥ 2 폰 px이고 남성 인스턴스 마스크(≥ 0.5) 안 바뀐 픽셀 비율 ≤ 0.2%(인스턴스가 없으면 이 부분만 `XCTSkip`). 남성 개인 층 `sideChest = 1`은 남성 몸 27% 점 이동 ≥ 2 폰 px.
- `testNeighborIsNotDragged` (`couple-body-01`): 여성 개인 층 `waist = -1`에서 남성 인스턴스 마스크 안 바뀐 픽셀 비율 ≤ 0.2%(인스턴스가 없으면 `XCTSkip`).
- `testLockedPhotoKeepsBodyRules`는 편집 테스트(I1)에 있으므로 여기서는 하지 않는다.

- [ ] **Step 2: 돌린다**

Run: `cd apple && swift test --filter ShapeAcceptanceTests`
Expected: 처음에는 일부가 기준을 못 맞출 수 있다. 측정값을 로그에서 읽는다.

- [ ] **Step 3: 기준을 못 맞추면 상수를 고친다**

하한을 못 맞추면 그 항목의 최대 이동 상수를 올리되 상한을 넘지 않게 한다. 상한을 넘으면 내린다. 배경·팔·이웃 검사가 실패하면 보호 상수(`shapeBackgroundGain`·`shapeBackgroundSigmaRatio`·`armGuardScale`·`armGuardFeather`)를 고친다. 상수를 고칠 때마다 `swift test --filter "ShapeAcceptanceTests|DisplacementWarpTests|ShapeWarpStageTests|FaceShapeRigTests|BodyShapeRigTests"`를 다시 돌린다. 기준 수치와 테스트 정의는 바꾸지 않는다. 두 번 고쳐도 안 되면 멈추고 측정값과 함께 컨트롤러에 보고한다.

- [ ] **Step 4: 전체를 돌린다**

Run: `cd apple && swift test`
Expected: 모두 통과(인스턴스 없는 기계의 건너뜀은 이름을 적는다).

- [ ] **Step 5: 커밋**

```bash
git add apple/Tests/MellowRenderingTests/ShapeAcceptanceTests.swift apple/Tests/MellowRenderingTests/ShapeTestSupport.swift apple/Sources/MellowRendering
git commit -m "test(rendering): 이중턱·부유방·체형의 폰 하한·자연스러움 상한과 배경 직선·남녀 규칙 수용 테스트"
```

### Task 4: 문서·VALIDATION·전체 검증

**Files:**
- Modify: `VALIDATION.md`
- Modify: `docs/architecture/modules.md` (Rendering 테스트 목록에 수용 테스트, 앱 체형 패널 문장)
- Modify: 앱 변경사항 문서(`git log --oneline -5 -- '*CHANGELOG*' '*changes*'`와 커밋 `2eda292 docs: 1.4.0 변경사항 추가`가 고친 파일을 찾아 같은 곳)

- [ ] **Step 1: 전체 검증을 돌린다**

Run: `export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer && ./scripts/test-apple.sh`
Expected: 모듈 검사·lint·xcodegen 차이 없음·패키지 테스트·Mac 앱 테스트가 모두 통과하고 "iOS 시뮬레이터 앱 테스트 생략"이 찍힌다.

- [ ] **Step 2: VALIDATION을 쓴다**

`VALIDATION.md`에 I 절을 더한다(사람 확인 영역만). 자동 검증(명령, 날짜, 테스트 수, 수용 테스트 측정값 표: 항목·하한·측정·상한), 건너뛴 테스트와 이유, CI 결과 칸(컨트롤러가 CI 뒤에 채움, 지금은 "미실행"), 사용자 기기 확인 항목(실제 커플·상반신 사진에서 이중턱·부유방·허리, 단체 사진 5명 이상에서 옆 사람, 수동 편집이 있는 옛 세션)을 적는다. 수행하지 않은 검증은 통과로 쓰지 않는다.

- [ ] **Step 3: 문서를 고친다**

`modules.md`의 테스트 목록·앱 규칙, 변경사항 문서의 다음 버전 항목("이중턱·부유방 보정 추가, 체형을 사람별·성별로 보정, 몸매 보정이 배경과 팔을 끌지 않음")을 쓴다.

- [ ] **Step 4: 커밋**

```bash
git add VALIDATION.md docs/architecture/modules.md <변경사항 문서>
git commit -m "docs: 인물 보정 I 검증 기록과 변경사항"
```
