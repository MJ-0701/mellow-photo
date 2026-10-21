# 인물 보정 I2 렌더(사람별 체형·보호 워프·이중턱·부유방) 구현 계획

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 렌더가 사진의 모든 몸에 그 사람에게 해석한 체형을 걸고, 모양 워프가 배경·옆 사람·팔을 끌지 않으며, 이중턱(워프 + 턱밑 그늘)과 부유방 원소가 생긴다.

**Architecture:** 사진 준비 때 Vision 사람 인스턴스 마스크를 받고 몸–얼굴, 몸–인스턴스, 얼굴–인스턴스 짝을 한 번 정해 `PhotoAnalysis`에 둔다. `RenderContext`가 몸마다 `BodyTarget`을 만들고, `ShapeWarpStage`가 사람·항목별 `ShapeGroup`을 모아 `DisplacementWarp`가 그룹마다 보호 가중치를 곱한 이동량 지도를 더해 한 번만 샘플링한다. 새 단계 `chinShade`가 `shapeWarp` 바로 앞에서 턱밑 그늘을 밝힌다.

**Tech Stack:** Swift 5.9 tools / Swift 5 언어 모드, Core Image(CIKL 색 커널), Vision(`VNGeneratePersonInstanceMaskRequest`, iOS 17·macOS 14), XCTest.

**Spec:** `docs/superpowers/specs/2026-10-21-beauty-i-chin-body-design.md` (에이전트 참조 5절). 선행: I1 계획 전부.

## 사람이 확인할 것

- **순서.** Task 1 인스턴스 분석·짝 → 2 몸 대상과 사람별 체형 → 3 보호 워프 → 4 이중턱·부유방 원소 → 5 턱밑 그늘 단계·문서. Task마다 Opus 구현 → 리뷰.
- **외부 효과가 있는 단계.** 없음.
- **스펙이 정하지 않아 이 계획이 정한 것.**

| 결정 | 이유 | 바꾸면 비용 |
|---|---|---|
| 몸·얼굴과 인스턴스의 짝은 사진 준비 때 CPU로 한 번 정하고 저장하지 않는다 | 렌더마다 마스크를 표본하면 미리보기가 느려진다. 분석 결과와 수명이 같다 | 작음 |
| 보호 가중치의 흐림은 마스크를 extent로 늘린 뒤 그룹 영향 경계 + 3σ로 잘라 extent 해상도에서 한다(스펙 5.4의 "원래 해상도에서 흐림"을 바꿈) | Vision 마스크는 가로·세로 배율이 달라 저해상도에서 등방 흐림을 하면 σ가 축마다 달라진다. 잘라서 흐리므로 비용은 영향 경계 크기에 비례한다 | 작음 |
| 모든 그룹의 사람 마스크가 nil이면 지금처럼 원소를 한 지도에 모아 그린다 | 그룹별 합은 부동소수 더하기 순서가 달라 바이트가 달라질 수 있다. 마스크 없는 기존 테스트가 그대로 통과해야 한다 | 작음 |
| 기존 `testOnlyLargestBodyIsReshaped`는 "전체 층 체형은 모든 몸, 다리 띠는 가장 큰 몸만"으로 바꾼다 | 스펙 결정(전체 층 = 모든 사람)이다 | 작음 |

- **위험.** CI 가상 머신에서 인스턴스 요청이 결과를 주지 않을 수 있다. 실패는 빈 배열로 조용히 대체하고, 인스턴스가 꼭 필요한 테스트는 합성 마스크로 만든다(Vision 필요 테스트는 I3 수용 테스트뿐).
- **사용자 조치.** 없음.

---

## 에이전트 참조

## Global Constraints

I1 계획의 Global Constraints를 그대로 따른다. 이 계획에서 더하는 것:

- MellowRendering은 `CoreImage`·`Foundation`·`ImageIO`·`UniformTypeIdentifiers`·`MellowShared`·`Vision`만 import한다.
- 단계 이름 순서는 Task 5 이후 `skin, bodySkin, feature, makeup, background, chinShade, shapeWarp, localEdit, geometry, color, detail, look, effect`다. Task 5 전까지는 기존 순서다.
- 새 `RenderTuning` 상수는 기존 체형 상수 절 바로 아래에 둔다. 값은 `shapeBackgroundGain` 4, `shapeBackgroundSigmaRatio` 1.5, `shapeBackgroundSigmaMinimum` 0.002, `armGuardScale` 1.0, `armGuardFeather` 0.03, `bodyFaceNeckDrop` 0.25, `bodyFaceMatchTolerance` 1.0, `instanceMatchMinimum` 0.5, `chinShadeMaxGain` 0.5, `chinShadeMaxLift` 12.0 / 255.0다(`faceDoubleChinMaxShift`·`bodySideChestMaxShift`는 I1).
- 원소 배치 비율은 각 rig의 `private static let`이다. 이중턱은 `doubleChinOffset` 0.10, `doubleChinRadius` 0.10, `doubleChinLowerOffset` 0.22, `doubleChinLowerRadius` 0.16, `doubleChinLowerShare` 0.5, `doubleChinMinimumPoints` 3. 부유방은 `sideChestLevel` 0.27, `sideChestRadius` 0.14. 턱밑 그늘 마스크는 `ChinShadeStage`의 `bandTop` 0.03, `bandBottom` 0.20, `bandSideMargin` 0.08, `bandFeather` 0.03, `referenceRadius` 0.15(모두 얼굴 폭 비율).
- 새 테스트 도우미는 `apple/Tests/MellowRenderingTests/ShapeTestSupport.swift`에 둔다. `RenderingTestSupport.swift`는 읽기만 한다(다른 세션이 고칠 수 있음).
- CIKL 커널 소스는 `DisplacementWarp`(이동량·가중치)와 `ChinShadeStage`(밝히기) 안에만 둔다.

## Review Focus

1. 인물 마스크·인스턴스가 없는 사진(합성 테스트, 분석 실패)은 이 계획 전과 같은 바이트로 렌더된다(다리 띠·얼굴형·체형 모두).
2. 몸이 여럿인데 얼굴이 하나뿐이면 짝이 된 몸만 개인 값을 받고 나머지는 전체 층 값을 받는다. 다른 사람의 개인 값은 어느 몸에도 붙지 않는다.
3. 팔이 몸통에 붙은 자세에서 허리·부유방을 켜도 팔 픽셀이 움직이지 않는다. 팔이 떨어진 자세에서는 몸통 윤곽이 움직인다(보호가 효과를 지우지 않음).
4. 넓히기(+) 방향 체형도 보호가 켜진 상태에서 목표 이동을 거의 다 낸다(배경 띠가 실루엣 바로 바깥을 막지 않음).
5. 이중턱은 턱선·입술을 움직이지 않고, 턱밑 그늘 단계는 수염처럼 피부색이 아닌 픽셀을 밝히지 않으며 어둡게 만들지 않는다.

---

### Task 1: 사람 인스턴스 분석과 짝

**Files:**
- Create: `apple/Sources/MellowRendering/API/PersonInstanceAnalyzer.swift`
- Create: `apple/Sources/MellowRendering/Infrastructure/VisionPersonInstanceAnalyzer.swift`
- Create: `apple/Sources/MellowRendering/Domain/BodyFaceMatcher.swift`
- Create: `apple/Sources/MellowRendering/Domain/InstanceAssignment.swift`
- Modify: `apple/Sources/MellowRendering/API/PhotoAnalysis.swift`
- Modify: `apple/Sources/MellowRendering/API/PhotoPipeline.swift`
- Modify: `apple/Sources/MellowRendering/API/RenderTuning.swift` (짝짓기 상수 3개)
- Modify: `apple/MellowPhoto/Application/Ports.swift` 또는 파이프라인을 조립하는 앱 파일(`VisionPersonInstanceAnalyzer()`를 넘김)
- Test: `apple/Tests/MellowRenderingTests/BodyFaceMatcherTests.swift`, `apple/Tests/MellowRenderingTests/VisionPersonInstanceAnalyzerTests.swift`, `apple/Tests/MellowRenderingTests/PhotoPipelineTests.swift`

**Interfaces:**
- Produces:
  - `public protocol PersonInstanceAnalyzer: Sendable { func instanceMasks(_ image: CIImage) throws -> [CIImage] }`. 결과는 사람마다 0…1 회색 마스크이고 Vision 원래 해상도(원점 0)다. 사람이 없으면 빈 배열이다.
  - `public struct VisionPersonInstanceAnalyzer: PersonInstanceAnalyzer`(`public init()`). `VNGeneratePersonInstanceMaskRequest`의 `allInstances`마다 `generateMask(forInstances: [index])` 버퍼를 `CIImage(cvPixelBuffer:options: [.colorSpace: NSNull()])`로 돌려준다.
  - `enum BodyFaceMatcher { static func match(bodies: [BodyGeometry], faces: [FaceGeometry], extent: CGRect, tuning: RenderTuning) -> [Int: Int] }`(몸 인덱스 → 얼굴 인덱스). 기준점·기대점·허용 거리·탐욕 순서는 스펙 5.2.
  - `enum InstanceAssignment { static func owner(of points: [CGPoint], in masks: [CIImage], extent: CGRect, renderer: Renderer, tuning: RenderTuning) -> Int? }`. 점은 extent 픽셀이고 마스크는 `BackgroundStage.personMask(_:extent:feather: 0)`과 같은 배치로 표본한다. 평균이 `instanceMatchMinimum` 이상인 마스크 중 평균이 가장 큰 것의 인덱스다. 점이 없으면 nil이다.
  - `PhotoAnalysis`에 `personInstances: [CIImage]`(기본 `[]`), `bodyFaceMatches: [Int: Int]`, `bodyInstances: [Int: Int]`(몸 → 인스턴스), `faceInstances: [Int: Int]`(얼굴 → 인스턴스)를 더한다. init 인자는 모두 기본값이 있다.
  - `PhotoPipeline.init`에 `instanceAnalyzer: (any PersonInstanceAnalyzer)? = nil`을 `bodyAnalyzer:` 바로 뒤에 더한다.
  - `PreparedPhoto.bodyFaceMatches: [Int: Int]`. `PreparedPhoto.hasBody`는 쓸 수 있는 몸(`BodySkeleton`이 만들어지는 몸)이 하나라도 있으면 true다.
  - `RenderTuning.bodyFaceNeckDrop` 0.25, `bodyFaceMatchTolerance` 1.0, `instanceMatchMinimum` 0.5.

- [ ] **Step 1: 실패하는 테스트를 쓴다**

`BodyFaceMatcherTests`:
- `testNeckBelowFaceMatches`: 얼굴 상자 (0.4, 0.6, 0.2, 0.2)와 목 관절이 (0.5, 0.55)인 몸은 짝 `[0: 0]`.
- `testFarBodyDoesNotMatch`: 목이 얼굴 기대점에서 얼굴 폭의 1.2배 떨어진 몸은 짝이 없다.
- `testGreedyOneToOneIsDeterministic`: 몸 둘·얼굴 둘이 교차로 가까운 배치에서 거리 합이 아니라 거리 오름차순 탐욕 결과가 나오고, 입력 순서를 바꿔도 같은 (몸, 얼굴) 쌍이 나온다.
- `testShoulderCenterWhenNeckMissing`: 목이 없고 두 어깨가 있으면 어깨 중점으로 짝짓는다. 목·어깨가 모두 없는 몸은 짝이 없다.

`VisionPersonInstanceAnalyzerTests`:
- `testDemoPortraitHasOneInstanceOrNone`: `demo-portrait.png`에서 결과 수가 0 또는 1이다. 1이면 마스크 중심 근처 값이 0.5 이상이다. 0이면 `XCTSkip("instance mask unavailable on this machine")`.
- `testEmptySceneHasNoInstances`: 단색 이미지는 빈 배열이다.

`PhotoPipelineTests`:
- `testPrepareStoresBodyFaceMatchesAndInstances`: 스텁 얼굴 분석기(얼굴 1개), 스텁 몸 분석기(몸 2개, 하나는 그 얼굴 아래), 스텁 인스턴스 분석기(두 몸을 각각 덮는 사각 마스크 2개)로 준비하면 `PreparedPhoto.bodyFaceMatches`에 짝이 하나 있고, 분석의 `bodyInstances`가 두 몸을 서로 다른 인스턴스에 둔다.
- `testInstanceFailureIsSilent`: 던지는 스텁 인스턴스 분석기여도 준비가 성공하고 `personInstances`가 비었다.

- [ ] **Step 2: 실패를 확인한다**

Run: `cd apple && swift test --filter "BodyFaceMatcherTests|VisionPersonInstanceAnalyzerTests|PhotoPipelineTests"`
Expected: 컴파일 오류.

- [ ] **Step 3: 분석기·짝짓기·준비를 구현한다**

`prepare`는 인물 마스크 뒤, 몸 분석 뒤에 인스턴스를 받는다. 몸 인스턴스의 표본점은 그 몸의 목·두 어깨·두 엉덩이 중 신뢰도를 넘은 것, 얼굴 인스턴스의 표본점은 얼굴 상자 중심 하나다. 인스턴스 분석기가 nil이거나 던지면 빈 배열이다. `InstanceAssignment`의 표본은 `renderer`로 마스크를 extent에 배치한 이미지의 1×1 영역을 읽는다(픽셀 수가 몇 개뿐이라 CPU 비용이 작다). 앱의 파이프라인 조립 코드에서 `VisionPersonInstanceAnalyzer()`를 넘긴다. `modules.md`의 Rendering 포트 문단에 새 포트를 적는 것은 Task 5에서 한다.

- [ ] **Step 4: 통과를 확인한다**

Run: `cd apple && swift test --filter MellowRenderingTests`
Expected: 모두 통과(인스턴스 없는 기계에서는 Vision 테스트 하나가 건너뜀).

- [ ] **Step 5: 커밋**

```bash
git add apple/Sources/MellowRendering apple/MellowPhoto/Application apple/Tests/MellowRenderingTests/BodyFaceMatcherTests.swift apple/Tests/MellowRenderingTests/VisionPersonInstanceAnalyzerTests.swift apple/Tests/MellowRenderingTests/PhotoPipelineTests.swift
git commit -m "feat(rendering): 사람 인스턴스 마스크와 얼굴–몸 짝을 사진 준비 때 정함"
```

### Task 2: 몸 대상과 사람별 체형

**Files:**
- Modify: `apple/Sources/MellowRendering/API/RenderStage.swift` (`FaceTarget.body`, `BodyTarget`, `RenderContext.bodyTargets`)
- Modify: `apple/Sources/MellowRendering/Domain/ShapeWarpStage.swift`
- Test: `apple/Tests/MellowRenderingTests/ShapeWarpStageTests.swift`, `apple/Tests/MellowRenderingTests/RenderPipelineTests.swift` 중 대상 테스트가 있는 곳(새 테스트는 `ShapeWarpStageTests`)

**Interfaces:**
- Consumes: Task 1의 `PhotoAnalysis.bodyFaceMatches`·`bodyInstances`·`faceInstances`·`personInstances`, I1의 `PortraitResolver.Resolved.body`·`allLayerBody`.
- Produces:
  - `FaceTarget.body: BodyShapeAdjustments`(init 인자 `body:`를 `makeup:` 뒤에 더하고 기본값 `BodyShapeAdjustments()`).
  - `public struct BodyTarget: Sendable { public let index: Int; public let body: BodyGeometry; public let faceIndex: Int?; public let adjustments: BodyShapeAdjustments }`. 각 속성은 코드에서 한 줄씩이다.
  - `RenderContext.bodyTargets: [BodyTarget]`(모든 몸, `analysis.bodies` 순서).
  - `RenderContext.personMask(forBody index: Int) -> (own: CIImage?, others: [CIImage])`와 `personMask(forFace index: Int) -> (own: CIImage?, others: [CIImage])`. 인스턴스가 있으면 own은 그 인스턴스, others는 나머지 인스턴스다. 없으면 own은 `personMask`(전체), others는 빈 배열이다. 둘 다 Vision 원래 해상도 마스크를 그대로 돌려주고 extent 배치는 소비자가 한다.

- [ ] **Step 1: 실패하는 테스트를 쓴다**

`ShapeWarpStageTests`에 더한다(합성 몸은 `BodyGeometry.standingBody`, 얼굴은 `SyntheticFace`의 기하를 이동해 쓴다).
- `testAllLayerBodyReshapesEveryBody`: 몸 둘, 전체 층 `waist = -1`. 두 몸의 허리 표식이 모두 안쪽으로 움직인다. 기존 `testOnlyLargestBodyIsReshaped`는 지우고 이 테스트와 다음 테스트로 대신한다.
- `testLegBandOnlyForLargestBody`: 몸 둘, 전체 층 `legLength = 1`. 원소 목록에 띠가 하나이고 시작 행이 가장 큰 몸의 엉덩이 높이다.
- `testPersonLayerBodyAppliesOnlyToMatchedBody`: 얼굴 하나가 몸 A와 짝(`bodyFaceMatches [0: 0]`). 그 얼굴 기록 층 `body: [.waist: -1]`, 전체 층 체형 0. 몸 A의 허리만 움직이고 몸 B는 같은 바이트다.
- `testFemaleGroupSideChestReachesOnlyFemaleBody`: 얼굴 둘, 수동 성별 남·여 기록, 각각 몸과 짝. 여성 그룹 `body: [.sideChest: 1]`. `bodyTargets`에서 여성 몸의 `adjustments.sideChest == 1`, 남성 몸 0, 짝 없는 셋째 몸 0.
- `testUnmatchedBodyGetsAllLayerWithoutSideChest`: 짝 없는 몸의 `adjustments`가 `PortraitResolver.allLayerBody(recipe)`와 같다.

- [ ] **Step 2: 실패를 확인한다**

Run: `cd apple && swift test --filter ShapeWarpStageTests`
Expected: 컴파일 오류(`bodyTargets` 없음).

- [ ] **Step 3: 대상과 단계를 구현한다**

`makeTargets`에서 `FaceTarget`에 `resolved.body`를 넣는다. `bodyTargets`는 `analysis.bodies.indices`마다 짝 얼굴이 있으면 그 `FaceTarget.body`, 없으면 `allLayerBody(recipe)`다. `ShapeWarpStage.bodyPrimitives`는 모든 `bodyTargets`에서 원소를 만들되 다리 띠는 `index == 0`(가장 큰 몸)일 때만 만든다. 다른 몸의 `legLength`는 원소를 만들기 전에 0으로 둔다. 이 Task에서는 보호 없이 기존 `DisplacementWarp.apply(_:to:extent:limit:)` 하나로 그린다(보호는 Task 3).

- [ ] **Step 4: 통과를 확인한다**

Run: `cd apple && swift test --filter MellowRenderingTests`
Expected: 모두 통과.

- [ ] **Step 5: 커밋**

```bash
git add apple/Sources/MellowRendering apple/Tests/MellowRenderingTests/ShapeWarpStageTests.swift
git commit -m "feat(rendering): 모든 몸에 그 사람의 층으로 해석한 체형을 걸고 다리 띠는 가장 큰 몸만"
```

### Task 3: 보호 워프

**Files:**
- Create: `apple/Sources/MellowRendering/Domain/ShapeGroup.swift`
- Modify: `apple/Sources/MellowRendering/Domain/DisplacementWarp.swift`
- Modify: `apple/Sources/MellowRendering/Domain/ShapeWarpStage.swift`
- Modify: `apple/Sources/MellowRendering/Domain/BodyShapeRig.swift` (항목을 몸통·팔다리로 나눠 돌려주는 함수)
- Modify: `apple/Sources/MellowRendering/API/RenderTuning.swift` (보호 상수 5개)
- Create: `apple/Tests/MellowRenderingTests/ShapeTestSupport.swift`
- Test: `apple/Tests/MellowRenderingTests/DisplacementWarpTests.swift`, `apple/Tests/MellowRenderingTests/ShapeWarpStageTests.swift`

**Interfaces:**
- Consumes: Task 2의 `bodyTargets`·`personMask(forBody:)`·`personMask(forFace:)`.
- Produces:
  - `enum ShapeGuard: Equatable, Sendable { case capsule(start: CGPoint, end: CGPoint, radius: CGFloat, feather: CGFloat) }`.
  - `struct ShapeGroup: Sendable { var primitives: [ShapePrimitive]; var ownMask: CIImage?; var otherMasks: [CIImage]; var guards: [ShapeGuard] }`(마스크는 Vision 원래 해상도). 정의의 세미콜론은 설명용이다.
  - `DisplacementWarp.apply(groups: [ShapeGroup], to image: CIImage, extent: CGRect, limit: Double) throws -> CIImage`.
  - `DisplacementWarp.field(groups: [ShapeGroup], extent: CGRect, limit: Double) throws -> CIImage?`(internal, 테스트·수용 테스트가 읽음). 원소가 없으면 nil이다.
  - `BodyShapeRig.groups(body: BodyGeometry, adjustments: BodyShapeAdjustments, extent: CGRect, tuning: RenderTuning, includesLegBand: Bool) -> (torso: [ShapePrimitive], limbs: [ShapePrimitive], guards: [ShapeGuard])`. 몸통은 `waist`·`overall`·`sideChest`, 팔다리는 `arms`·`thighs`·`shoulders`·`neck`·`legLength`(띠)다. 기존 `primitives(body:adjustments:extent:tuning:)`는 두 목록을 이은 결과로 남긴다.
  - `RenderTuning`: `shapeBackgroundGain` 4, `shapeBackgroundSigmaRatio` 1.5, `shapeBackgroundSigmaMinimum` 0.002, `armGuardScale` 1.0, `armGuardFeather` 0.03.
  - 테스트 도우미 `ShapeTestSupport.fieldVectors(_ field: CIImage, at points: [CGPoint]) throws -> [CGVector]`(float 지도에서 점마다 (dx, dy)를 읽음).

- [ ] **Step 1: 실패하는 테스트를 쓴다**

`DisplacementWarpTests`에 더한다. 사람 마스크는 `RenderingTestSupport.personMask(size:person:)`(사각 사람)를 쓴다.
- `testGroupsWithoutMasksMatchTheSingleFieldPath`: 마스크 없는 그룹 둘로 렌더한 결과가 두 원소 목록을 이은 기존 `apply(_:to:extent:limit:)` 결과와 같은 바이트다.
- `testBackgroundBeyondTheBandDoesNotMove`: 사람 사각형 오른쪽 변에 안쪽 push(이동 v = 12px, 반지름 80px). 사각형에서 4v + 4px 밖 점의 지도 이동은 0.25px 이하이고, 사각형 안쪽 변에서 v/2 안쪽 점의 이동은 보호 없는 지도와 2% 안에서 같다.
- `testWideningKeepsMostOfTheShift`: 같은 변에 바깥 push(v = 12px). 변에서 v만큼 바깥 점의 이동이 보호 없는 지도의 90% 이상이다.
- `testOtherPersonIsNotMoved`: 사람 A 사각형과 맞닿은 사람 B 사각형(다른 마스크). A의 변에 안쪽 push. B 안쪽 2px 너머의 이동이 0.25px 이하다.
- `testCapsuleGuardZeroesTorsoShiftOnTheArm`: 캡슐(반지름 20px, feather 6px) 안 점의 이동이 0.01px 이하이고 반지름 + feather 밖 점은 보호 없는 지도와 같다.

`ShapeWarpStageTests`에 더한다.
- `testArmTouchingTorsoKeepsArmPixels`: `standingBody`의 팔꿈치·손목을 몸통 옆선에 붙인 몸, 사람 마스크 있음, `waist = -1`. 팔 캡슐 반지름 안 표식의 이동이 1px 이하다.
- `testArmAwayStillSlimsTheWaist`: 팔을 몸통에서 어깨 폭의 0.2만큼 띄운 몸. 허리 윤곽 표식이 보호 없는 렌더 이동의 80% 이상 움직인다.
- 기존 `ShapeWarpStageTests`·`DisplacementWarpTests`·`BodyShapeRigTests`는 바뀌지 않고 통과해야 한다(마스크가 없으므로).

- [ ] **Step 2: 실패를 확인한다**

Run: `cd apple && swift test --filter "DisplacementWarpTests|ShapeWarpStageTests"`
Expected: 컴파일 오류.

- [ ] **Step 3: 그룹 지도와 보호를 구현한다**

- 모든 그룹의 `ownMask`가 nil이면 원소를 이어 기존 경로로 그린다.
- 그 밖에는 그룹마다 `displacementField`로 지도를 그리고 가중치를 곱한 뒤 그룹 지도를 더한다. 띠는 지금처럼 샘플링 커널이 더한다.
- 가중치는 스펙 5.4다. own 마스크는 `BackgroundStage.personMask(_:extent:feather: 0)`로 늘리고 그룹 영향 경계 + 3σ로 잘라 `CIGaussianBlur`(σ)를 건다. σ = max(그룹 최대 이동 × `shapeBackgroundSigmaRatio`, 짧은 변 × `shapeBackgroundSigmaMinimum`)이다.
- others는 같은 배치로 늘린 뒤 `CIMaximumCompositing`으로 합친다(흐리지 않음).
- 캡슐은 그룹당 최대 4개다. 가중치 커널은 vec4(start.xy, end.xy) 4개와 vec2(radius, feather) 4개를 받고, 없는 캡슐은 radius 0으로 넘긴다.
- 가중치·곱·합 커널은 `DisplacementWarp` 안 CIColorKernel이다. 알파는 늘 1이다(기존 지도 커널과 같은 이유).
- `ShapeWarpStage`는 얼굴 대상마다 얼굴형 그룹(`personMask(forFace:)`, 보호 없음)을 만든다. 몸 대상마다 몸통 그룹(`personMask(forBody:)`, 그 몸의 팔 캡슐)과 팔다리 그룹(같은 마스크, 캡슐 없음)을 만든다.
- 캡슐은 어깨–팔꿈치(반지름 = 어깨 폭 × `upperArmHalfWidth` × `armGuardScale`)와 팔꿈치–손목(`forearmHalfWidth` × `armGuardScale`)이다. feather는 어깨 폭 × `armGuardFeather`다. `upperArmHalfWidth`·`forearmHalfWidth`는 `BodyShapeRig`의 기존 상수를 internal로 열어 쓴다.

- [ ] **Step 4: 통과를 확인한다**

Run: `cd apple && swift test --filter MellowRenderingTests`
Expected: 모두 통과.

- [ ] **Step 5: 커밋**

```bash
git add apple/Sources/MellowRendering apple/Tests/MellowRenderingTests/ShapeTestSupport.swift apple/Tests/MellowRenderingTests/DisplacementWarpTests.swift apple/Tests/MellowRenderingTests/ShapeWarpStageTests.swift
git commit -m "feat(rendering): 모양 워프가 배경·옆 사람·팔을 끌지 않게 그룹별 보호 가중치를 곱함"
```

### Task 4: 이중턱·부유방 원소

**Files:**
- Modify: `apple/Sources/MellowRendering/Domain/FaceShapeRig.swift`
- Modify: `apple/Sources/MellowRendering/Domain/BodyShapeRig.swift`
- Test: `apple/Tests/MellowRenderingTests/FaceShapeRigTests.swift`, `apple/Tests/MellowRenderingTests/BodyShapeRigTests.swift`

**Interfaces:**
- Consumes: I1의 `FaceShapeKey.doubleChin`·`BodyShapeKey.sideChest`·`RenderTuning.faceDoubleChinMaxShift`·`bodySideChestMaxShift`, Task 3의 몸통 그룹 분류.
- Produces: `FaceShapeRig.primitives`가 `.doubleChin`에서 위쪽 push 원소들을, `BodyShapeRig`가 `.sideChest`에서 몸통 그룹 원소 둘(양쪽)을 만든다. I1 Task 1의 임시 빈 case를 지운다.

- [ ] **Step 1: 실패하는 테스트를 쓴다**

`FaceShapeRigTests`(얼굴은 이 파일이 이미 쓰는 합성·데모 특징점 얼굴):
- `testDoubleChinLiftsUnderTheChinWithoutMovingTheJaw`: `doubleChin = 1`. 턱 끝 아래 얼굴 폭 × 0.10 점의 이동이 위쪽이고 크기가 얼굴 폭 × 0.035의 ±10% 안이다. 모든 윤곽점의 |이동| ≤ 얼굴 폭 × 0.0035. 바깥 입술 점의 |이동| == 0. 턱 끝 아래 얼굴 폭 × 0.40 점의 |이동| == 0.
- `testDoubleChinFoldsWithoutFlipping`: `RenderingTestSupport.minimumJacobian`이 턱 아래 사각형에서 0.5보다 크다(접힘 없음, 압축은 50%까지).
- `testDoubleChinNeedsThreeLowerContourPoints`: 입 높이 아래 윤곽점이 둘뿐인 얼굴은 원소가 없다.
- `testDoubleChinFollowsYawAttenuation`: yaw 0.8인 얼굴의 최대 이동이 정면의 `yawAttenuation(0.8)`배다.
- `testDoubleChinIsUnitRange`: 값 −1은 원소가 없고 값 2는 값 1과 같은 원소다.

`BodyShapeRigTests`:
- `testSideChestPushesBothTorsoSidesInward`: `sideChest = 1`. 원소 둘이 각 쪽 어깨~엉덩이 27% 점에 있고 이동이 몸통 가로축 안쪽, 크기가 어깨 폭 × 0.03, 반지름이 어깨 폭 × 0.14 이상이다.
- `testSideChestNeedsHips`: 엉덩이가 없으면 원소가 없다.
- `testSideChestIsTorsoGroup`: `groups(...)`의 `torso`에 들어가고 `limbs`에는 없다.

- [ ] **Step 2: 실패를 확인한다**

Run: `cd apple && swift test --filter "FaceShapeRigTests|BodyShapeRigTests"`
Expected: 새 테스트 실패(원소 없음).

- [ ] **Step 3: 원소를 구현한다**

이중턱 배치는 스펙 5.6과 Global Constraints의 비율 상수다. 윗줄 점마다 이동 = shift / c다. c는 가운데 점의 위쪽 중심에서 본 윗줄 모든 중심의 감쇠 합이다. 그래서 턱 끝 아래 최대 이동이 shift가 된다. 아랫줄은 턱 끝 아래 가운데 하나이고 이동은 shift × `doubleChinLowerShare`다. 좌우 끝 점은 얼굴 좌표 x로 입꼬리 사이에서 고른다. 입술 점이 둘 미만이면 아래 윤곽 전체를 쓴다. 부유방은 스펙 5.8이다.

- [ ] **Step 4: 통과를 확인한다**

Run: `cd apple && swift test --filter MellowRenderingTests`
Expected: 모두 통과.

- [ ] **Step 5: 커밋**

```bash
git add apple/Sources/MellowRendering/Domain/FaceShapeRig.swift apple/Sources/MellowRendering/Domain/BodyShapeRig.swift apple/Tests/MellowRenderingTests/FaceShapeRigTests.swift apple/Tests/MellowRenderingTests/BodyShapeRigTests.swift
git commit -m "feat(rendering): 이중턱(턱밑 접어 올리기)·부유방(겨드랑이 아래 옆선) 이동 원소 추가"
```

### Task 5: 턱밑 그늘 단계와 문서

**Files:**
- Create: `apple/Sources/MellowRendering/Domain/ChinShadeStage.swift`
- Create: `apple/Sources/MellowRendering/Domain/FaceRegions+Chin.swift`
- Modify: `apple/Sources/MellowRendering/API/RenderPipeline.swift`
- Modify: `apple/Sources/MellowRendering/API/RenderTuning.swift` (`chinShadeMaxGain`, `chinShadeMaxLift`)
- Modify: `docs/architecture/modules.md` (Rendering 캔버스: 공개 API, 포트, 단계 순서, 보호 워프·이중턱·부유방·짝짓기 규칙, 테스트 목록)
- Test: `apple/Tests/MellowRenderingTests/ChinShadeStageTests.swift`, `apple/Tests/MellowRenderingTests/RenderPipelineTests.swift`

**Interfaces:**
- Consumes: `FaceTarget.portrait.face.doubleChin`, `FaceRegions.cheekAverages`·기존 Cb·Cr 거리 가중 함수, `RenderContext.regionMasks`.
- Produces: `struct ChinShadeStage: RenderStage`(이름 `"chinShade"`), `FaceRegions.chinBandMask(face: FaceGeometry, extent: CGRect, tuning: RenderTuning, cache: RegionMaskCache?) -> CIImage?`(특징점이 부족하면 nil).

- [ ] **Step 1: 실패하는 테스트를 쓴다**

`ChinShadeStageTests`(얼굴은 `SyntheticFace.make()`의 기하, 이미지는 그 얼굴 아래 턱밑 띠 위치에 휘도 40/255 낮은 띠를 칠한 피부색 단색):
- `testZeroDoubleChinReturnsInputUnchanged`: 모든 대상의 `doubleChin` 0이면 같은 바이트다.
- `testLiftsTheShadowBandUnderTheChin`: `doubleChin = 1`. 띠 안 평균 휘도가 오르고 오른 양이 `chinShadeMaxLift`(12/255) 이하이며 띠와 주변의 휘도 차가 줄었다.
- `testNeverDarkens`: 띠보다 밝은 픽셀도 있는 이미지에서 어떤 픽셀도 어두워지지 않는다.
- `testOutsideTheBandIsUntouched`: 턱선 위(입·볼)와 띠 아래 얼굴 폭 × 0.25 너머가 같은 바이트다.
- `testNonSkinColorIsNotLifted`: 띠 안에 회갈색이 아닌 짙은 회색(수염 흉내, Cb·Cr이 볼과 먼 색) 영역을 칠하면 그 영역의 휘도 증가가 1/255 이하다.
- `testOnlyTheTargetFace`: 얼굴 둘 중 개인 층으로 하나만 `doubleChin = 1`이면 다른 얼굴의 턱밑은 같은 바이트다.

`RenderPipelineTests`의 단계 이름 배열 기대값을 `skin, bodySkin, feature, makeup, background, chinShade, shapeWarp, localEdit, geometry, color, detail, look, effect`로 바꾼다.

- [ ] **Step 2: 실패를 확인한다**

Run: `cd apple && swift test --filter "ChinShadeStageTests|RenderPipelineTests"`
Expected: 컴파일 오류.

- [ ] **Step 3: 단계를 구현한다**

마스크는 스펙 5.7이다. 띠 다각형은 아래턱 윤곽을 얼굴 좌표 아래로 `bandTop`·`bandBottom`만큼 옮긴 두 선으로 닫고 좌우를 입꼬리 x ± `bandSideMargin`에서 자른다. 기존 다각형 비트맵과 feather 경로(`featheredPolygonMask`)를 쓰고 캐시 키는 다각형이다. 피부색 가중치는 `skinMask`가 쓰는 볼 기준 Cb·Cr 거리 함수와 같은 것을 부른다. 밝히기 커널은 감마 BT.601 휘도로 L' = L + 값 × `chinShadeMaxGain` × max(0, R − L)을 계산하고 증가를 `chinShadeMaxLift`에서 자른다. 색은 휘도 비율로 올려 색조를 유지한다. R은 마스크 가중 평균을 반지름 얼굴 폭 × `referenceRadius`로 흐린 값이다(가중 흐림 / 마스크 흐림). 결과는 마스크 경계 안에서만 계산해 `CIBlendWithMask`로 얹는다. `RenderPipeline.standard`의 `BackgroundStage()`와 `ShapeWarpStage()` 사이에 `ChinShadeStage()`를 넣는다. `modules.md`를 고친다.

- [ ] **Step 4: 통과를 확인한다**

Run: `cd apple && swift test`
Expected: 모두 통과.

Run: `bash scripts/verify-modules.sh`
Expected: 오류 없음.

- [ ] **Step 5: 커밋**

```bash
git add apple/Sources/MellowRendering apple/Tests/MellowRenderingTests/ChinShadeStageTests.swift apple/Tests/MellowRenderingTests/RenderPipelineTests.swift docs/architecture/modules.md
git commit -m "feat(rendering): 이중턱 값으로 턱밑 그늘을 밝히는 chinShade 단계 추가"
```
