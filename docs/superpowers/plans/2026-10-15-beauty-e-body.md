# 인물 보정 E 체형 구현 계획

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 새 체형 도구에 다리 길게·허리·몸 전체·팔·허벅지·어깨·목 슬라이더 7개를 더하고, 사진 준비 때 찾은 가장 큰 사람의 관절점으로 얼굴형 변형과 같은 한 번의 변형에 체형 이동을 합친다.

**Architecture:** 관절점은 `BodyAnalyzer` 포트(`VisionBodyAnalyzer` = `VNDetectHumanBodyPoseRequest`)로 사진 준비 때 한 번 찾아 `PhotoAnalysis.bodies`에 두고, 실패는 `PreparedPhoto.bodyAnalysisFailure`로 남긴다. `BodySkeleton`이 관절을 픽셀 좌표·몸통 축·어깨 폭으로 바꾸고 `BodyShapeRig`가 슬라이더를 이동 원소(push 여러 개 + 다리 띠 하나)로 바꾼다. `ShapeWarpStage.bodyPrimitives`가 그 원소를 얼굴 원소와 합쳐 `DisplacementWarp`로 한 번만 샘플링한다. 다리 띠는 이동량 지도에 그리지 않고 샘플링 커널이 식으로 더하며 양 끝을 smoothstep으로 부드럽게 한다.

**Tech Stack:** Swift 5.9 tools / Swift 5 언어 모드, SwiftUI + Observation, Core Image(CIKL `CIColorKernel` 2개 + `CIKernel` 1개, `CIBlendWithMask`), Vision(`VNDetectFaceLandmarksRequest`·`VNGeneratePersonSegmentationRequest` 기존, `VNDetectHumanBodyPoseRequest` 새로), XCTest, XcodeGen 2.46.0.

**Spec:** `docs/superpowers/specs/2026-10-15-beauty-b-to-f-design.md` (E에 해당하는 절: 1.1~1.5, 5, 7, 8, 9). C 실행 기록 `.superpowers/sdd/2026-10-15-beauty-c-face/progress.md`의 E 이월 항목(`bodies` 필드, band 영향 범위 제한, band 가장자리 smoothstep, 512px 넘는 이동의 정밀도, push 반지름 ≥ 이동 × 4)과 D 실행 기록 `.superpowers/sdd/2026-10-15-beauty-d-features/progress.md`의 분석 실패 처리 방식(인물 분석과 같음)을 포함한다.

## 사람이 확인할 것

- **순서.** Task 1 관절점 타입·체형 편집 변경 → 2 체형 분석 → 3 다리 띠 계산 방식 → 4 체형 이동 원소 → 5 변형 단계 연결 → 6 체형 도구 → 7 문서·전체 검증. 7개 Task, Task마다 Opus 구현 → 리뷰 → 수정, 끝에 전체 리뷰.
- **외부 효과가 있는 단계.** 없음. 푸시·태그·TestFlight는 F를 마친 뒤(스펙 "외부 효과가 있는 단계").
- **스펙이 정하지 않아 이 계획이 정한 것.**

| 결정 | 이유 | 바꾸면 비용 |
|---|---|---|
| 다리 길게 띠는 이동량 지도에 그리지 않고 다시 그리는 단계에서 식으로 계산 | 48MP에서 다리를 바꿀 때마다 사진 크기 이동량 지도(약 384MB)가 생기지 않는다. 600px 넘게 밀려도 반 픽셀 계단이 없다. 스펙 1.5 문구를 고친다 | 작음 |
| 띠 양 끝(골반·발목)을 부드럽게 시작·끝냄 | 골반에서 늘림이 갑자기 시작해 꺾여 보이지 않는다. 대신 무릎 근처가 평균의 1.5배로 가장 많이 늘어난다 | 작음 |
| 이동량 지도 정밀도(16비트)는 유지 | 띠를 뺀 체형 이동 하나는 어깨 폭의 6% 이하라 48MP에서도 512px 미만, 위치 오차 0.25px 이하. 32비트로 바꾸면 지도 메모리가 두 배 | 작음 |
| 시작 강도(어깨 폭 40cm 기준, 값 ±1): 허리 한쪽 2.4cm(허리 −17%), 몸 전체 가슴·골반·허벅지 각 1.4cm, 팔 위팔 0.8cm(−17%), 허벅지 1.4cm(−17%), 어깨 한쪽 1.6cm(±8%), 목 1.2cm, 다리 골반~발목 8% | 얼굴형과 비슷한 "자연스러운 최대" 어림이고 스펙 상한(몸 폭 6%) 안. 실사진 피드백으로 `RenderTuning` 한 곳에서 조정 | 작음 |
| 방향: 왼쪽(음수)은 가늘게·좁게·짧게, 오른쪽은 넓게·길게. 스펙의 "전체 날씬"은 화면 이름을 "몸 전체"로 | 얼굴 폭과 같은 방향. "날씬" 이름은 오른쪽이 뚱뚱해지는 것과 어긋난다 | 작음 |
| 가장 큰 사람의 두 어깨가 보이면 체형 슬라이더를 켜고, 그 밖의 관절이 없는 항목은 조용히 건너뜀 | 모든 이동량이 어깨 폭 기준이다. 상반신 사진에서도 어깨·팔·목은 동작 | 작음 |
| 체형 분석 실패는 가져오기 경고 없이 체형 도구 안에서만 알리고, 미리보기·저장은 체형만 빼고 진행 | 인물 분석(D)과 같은 처리. 시뮬레이터에서 가져올 때마다 알림이 뜨지 않게 | 작음 |
| 수동 편집 잠금 안내 문구를 얼굴형·체형 공통으로 바꿈 | 체형 슬라이더도 같은 이유로 잠긴다 | 작음 |
| 체형 도구는 도구 줄의 뷰티 다음, 배경 앞 | F가 메이크업을 뷰티와 체형 사이에 넣어 스펙 7의 순서가 된다 | 작음 |

- **범위 밖.** 여러 사람의 체형 동시 보정(스펙: 가장 큰 한 명), 몸 영역 마스크로 배경 휨 막기, 옆모습·누운 자세 전용 처리, 자동 보정의 체형 값(스펙 7), 다시 준비한 사진의 분석 결과를 안내에 반영(D 이월, F 앱 정리 때).
- **위험.** 다리 띠는 사진 가로 전체를 늘려 다리 높이의 배경·다른 사람도 함께 늘어난다. 팔이 몸통에 붙어 있으면 허리·팔 이동이 서로 밀어 윤곽이 울 수 있다. 옷·자세 때문에 관절이 틀리면 엉뚱한 곳이 휜다. 공용 데모 사진(얼굴 가까운 셀카)에서 Vision이 사람을 0명 찾아(Mac 측정) 실제 전신 인식은 자동 테스트로 확인하지 못한다. iOS 시뮬레이터에서 체형 분석이 실패할 수 있다(안내만 뜨고 다른 보정은 동작). 보정 품질은 자동 테스트로 판정할 수 없다.
- **사용자 조치.** 이 계획 안에는 없다. 실제 전신 사진으로 체형 결과를 보는 것은 F 뒤 1.2.0 TestFlight에서 한다(스펙 사용자 조치).

---

## 에이전트 참조

## Global Constraints

- 작업 위치: worktree `/Users/mj/IdeaProjects/mellow-photo/.claude/worktrees/b0-basic-editing`, 브랜치 `beauty-b-to-f`(시작 HEAD `d5fb355`, B·C·D 구현 완료). 부모 저장소로 `cd`하지 않는다. 모든 Swift·xcodebuild 명령 전에 `export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`.
- 모듈 의존성 표(`docs/architecture/modules.md`)와 `scripts/verify-modules.sh`는 바뀌지 않는다. MellowRendering의 import는 `CoreImage`·`Foundation`·`MellowShared`·`Vision`만 쓴다. MellowShared는 Foundation·CoreGraphics만. MellowRendering은 MellowEditing을 import할 수 없다(값 범위는 MellowShared `AdjustmentRange`).
- 새 보정은 MellowRendering 단계와 MellowShared 레시피 확장으로만 넣는다. 파이프라인 단계 이름 순서는 모든 Task에서 `skin, feature, background, shapeWarp, localEdit, geometry, color, detail, look` 그대로다(체형 원소는 `shapeWarp` 안에 합친다).
- 레시피 `schemaVersion`은 2 유지, E는 레시피 키를 바꾸지 않는다(`body`는 B에서 이미 있다). v1 세션은 계속 읽힌다. 번들 ID `com.mj.mellowphoto`는 그대로.
- 값 범위: `body.legLength` 0…1, 나머지 `body.*` −1…1(`AdjustmentRange.bodyShape(_:)` = `EditingPolicy.bodyShapeRange(_:)`). 렌더도 이 범위로 직접 자르고 유한하지 않은 값은 0으로 본다(프리셋·일괄 값은 편집 규칙을 거치지 않는다).
- 좌표는 정규화·원점 왼쪽 아래. 관절 이름의 left·right는 Vision처럼 찍힌 사람 기준(정면 사진에서 `leftShoulder`는 화면 오른쪽)이고, 렌더는 좌우를 이름이 아니라 위치로 정한다.
- `RenderTuning` 새 상수 시작값: Task 2 — bodyJointMinConfidence 0.3(스펙). Task 4 — bodyShapeMaxShift 0.06(스펙), bodyWaistMaxShift 0.06, bodyOverallMaxShift 0.035, bodyArmMaxShift 0.02, bodyThighMaxShift 0.035, bodyShoulderMaxShift 0.04, bodyNeckMaxShift 0.03, legLengthMaxStretch 0.08(스펙).
- 체형 push 원소의 반지름은 `|이동| / shapeDisplacementLimit` 이상이어야 한다(얼굴과 같은 상한 0.25가 체형 이동을 몰래 줄이지 않게, C 이월).
- 한 줄 한 문장, 세미콜론 금지(CIKL 소스 문자열 안은 예외), 매직 넘버는 명명 상수(`RenderTuning`·`Theme`·`AppModel.Policy`·`EditingPolicy`, 기하 비율·판정 문턱은 기존 `FaceShapeRig`처럼 타입 안 `private static let`).
- 한국어 사용자 문구는 앱 타깃(`UserMessage`·뷰)에만. 모듈은 `MellowError`만 던진다. 새 case `MellowError.bodyAnalysisUnavailable(reason: String)`(Task 2)의 문구는 같은 Task에서 `UserMessage.text(for:)`에 더한다.
- `cd apple && swift format lint --strict --recursive Sources Tests MellowPhoto MellowPhotoTests` 출력 없음(긴 줄은 줄바꿈으로 고친다, 한도 120자). 허용된 빌드 경고: 기존 `CIWarpKernel` 지원 중단(`WarpKernel`), 기존 `CIColorKernel(source:)` 지원 중단(`SkinKernels`, `DisplacementWarp`, `FeatureKernels`), 기존 `CIKernel(source:)` 지원 중단(`DisplacementWarp`), 시뮬레이터 `usesCPUOnly`(`VisionFaceAnalyzer`). E는 새 경고를 더하지 않는다(`VisionBodyAnalyzer`에 `usesCPUOnly`를 넣지 않는다).
- `./scripts/verify-modules.sh` 통과. 전체 검증은 `./scripts/test-apple.sh`.
- 패키지 테스트: `cd apple && swift test`(모듈마다 `Executed N tests`가 따로 찍힌다). Mac 앱 테스트: `xcodebuild -project apple/MellowPhoto.xcodeproj -scheme MellowPhoto -derivedDataPath apple/build -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO test 2>&1 | grep -E "Executed|TEST (SUCCEEDED|FAILED)|error:"`. 앱 파일을 더하는 Task는 Task 6(`BodyPanel.swift`) 하나이며 그 Task만 `cd apple && xcodegen generate`를 돌리고 `apple/MellowPhoto.xcodeproj`를 함께 커밋한다.
- iOS 시뮬레이터 테스트는 Task 7의 `MELLOW_IOS_TESTS=1 ./scripts/test-apple.sh` 한 번에서만 돌린다(로컬 `test-apple.sh`는 이 변수가 없으면 iOS 시뮬레이터를 건너뛴다). 직접 부팅하지 않은 시뮬레이터를 끄지 않는다(`xcrun simctl shutdown`·`erase` 금지, 다른 프로젝트가 같은 기기를 쓰고 있을 수 있다). Xcode를 열거나 앱을 직접 띄우거나 조작하지 않는다.
- 커밋: 한국어 Conventional Commits, 마지막 줄 `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`. `git add`는 Task에 나열한 경로만.
- 각 Task 끝에 패키지 테스트(앱을 건드렸으면 Mac 앱 테스트도)와 lint가 통과해야 다음으로 간다. 기준 테스트 수(시작 시점, 계획 작성 때 `swift test`로 셈): 패키지 258(Shared 37 · Rendering 163 · Library 30 · Export 4 · Editing 24), 앱 iPhone 55 · iPad 55 · Mac 56. (D 기록의 "257"은 Editing을 23으로 센 값이다. 실제는 24.)

## Review Focus

스펙이 암시하지만 스펙의 테스트 목록이 직접 다루지 않는 입력. 각 줄의 테스트를 소유 Task에 넣었다.

1. **체형 분석이 실패했거나(시뮬레이터·구형 기기), 준비 전이거나, 관절이 없는 사진에 체형 값이 있다(프리셋·일괄 적용으로도 들어온다).** 미리보기·저장 모두 오류 없이 체형만 빠져야 하고 앱은 오류 창을 띄우지 않아야 한다. → Task 5 `testBodyAnalysisFailureSkipsOnlyBodyWarp`, `testOutOfRangeBodyValuesRenderLikeClampedValues`(관절 없음), Task 6 `testBodyToolReportsNoBodyAndAnalysisFailureWithoutBlockingRender`.
2. **손으로 고친 프리셋 파일·일괄 적용으로 범위 밖·유한하지 않은 체형 값(legLength 3·−2, waist −4, NaN)이 들어온다.** 렌더는 잘린 값과 같아야 하고 NaN은 0이어야 한다. → Task 4 `testZeroNaNAndOutOfRangeValues`, Task 5 `testOutOfRangeBodyValuesRenderLikeClampedValues`.
3. **기울어진 사람, 거꾸로 된 사진, 누운 사람.** 허리·목 이동은 몸통 축을 따라야 하고, 엉덩이가 발목보다 충분히 위에 있지 않으면 다리 띠는 건너뛰어야 한다. → Task 2 `testTiltedBodyAxesFollowHipsToShoulders`, Task 4 `testTiltedBodyPushesFollowTorsoAxis`, `testLegLengthMakesOneBandFromHipsToAnkles`.
4. **여러 사람이 찍힌 사진.** 가장 큰 사람만 바뀌고 다른 사람은 그대로여야 한다(다리 띠가 가로로 걸치는 것은 위험에 적음). → Task 2 `testOrderedLargestFirst`, Task 5 `testOnlyLargestBodyIsReshaped`.
5. **큰 사진(48MP)에서 다리 길게.** 띠 시작 위쪽 행은 원본 바이트 그대로, 이동량 지도는 push 경계만, 512px 넘는 이동도 서브픽셀로 정확해야 한다. → Task 3 `testBandIsNotDrawnIntoFieldAndRowsAboveKeepInputBytes`, `testLargeBandShiftKeepsSubpixelAccuracy`, Task 5 `testLegLengthMovesMarkerBelowHipsDownAndKeepsRowsAboveHips`.

## 인터페이스 요약 (모든 Task가 공유하는 이름)

```swift
// MellowShared (Task 1·2)
public enum BodyJoint: String, CaseIterable, Codable, Sendable   // 14개: neck, left/rightShoulder, …Elbow, …Wrist, …Hip, …Knee, …Ankle, root
public struct BodyGeometry: Equatable, Sendable {
    var joints: [BodyJoint: NormalizedPoint]; var confidence: [BodyJoint: Double]; var boundingBox: NormalizedRect
    init(joints:confidence:boundingBox:)            // boundingBox 기본 nil = 관절을 감싸는 상자
    func point(_:minimumConfidence:) -> NormalizedPoint?
    var area: Double
}
AdjustmentRange.bodyShape(_ key: BodyShapeKey) -> ClosedRange<Double>      // Task 1
MellowError.bodyAnalysisUnavailable(reason: String)                         // Task 2

// MellowEditing (Task 1)
EditChange.bodyShape(BodyShapeKey, Double)        // affectsGeometry true
EditingPolicy.bodyShapeRange(_:)

// MellowRendering 공개 API (Task 2)
public protocol BodyAnalyzer: Sendable { func analyze(_ image: CIImage) throws -> [BodyGeometry] }
public struct VisionBodyAnalyzer: BodyAnalyzer {  // Infrastructure
    init(); static func orderedLargestFirst(_:) -> [BodyGeometry]
    struct LocatedJoint { location: CGPoint; confidence: Double }          // internal
    static func geometry(from: [BodyJoint: LocatedJoint]) -> BodyGeometry?  // internal
}
PhotoAnalysis.bodies: [BodyGeometry], .bodyAnalysisFailure: MellowError?, init(…, bodies:, bodyAnalysisFailure:)  // 기본값
RenderContext.bodies: [BodyGeometry]
PhotoPipeline.init(analyzer:personAnalyzer:bodyAnalyzer:tuning:lookCatalog:)   // bodyAnalyzer: (any BodyAnalyzer)? = nil
PreparedPhoto.hasBody: Bool, .bodyAnalysisFailure: MellowError?            // init 기본값 false·nil
RenderTuning.bodyJointMinConfidence                                        // Task 2
RenderTuning.bodyShapeMaxShift, bodyWaistMaxShift, bodyOverallMaxShift, bodyArmMaxShift, bodyThighMaxShift,
    bodyShoulderMaxShift, bodyNeckMaxShift, legLengthMaxStretch, bodyItemMaxShift(_:)   // Task 4

// MellowRendering internal
struct BodySkeleton { joints; torsoWidth; shoulderCenter; hipCenter: CGPoint?; up; across
    init?(body:extent:tuning:); point(_:); side(of:from:); static midpoint(_:_:), lerp(_:_:_:) }   // Task 2
ShapePrimitive.isBand                                                     // Task 3
DisplacementWarp.maximumBands, fieldBounds(_:extent:)                      // Task 3
enum BodyShapeRig { static func primitives(body:adjustments:extent:tuning:) -> [ShapePrimitive] }   // Task 4
ShapeWarpStage.bodyPrimitives(in:)                                         // Task 5에서 채움

// 테스트 지원 (apple/Tests/MellowRenderingTests)
RenderingTestSupport.standingBox, standingBody(in:confidence:omitting:), BodyGeometry.rotated(by:about:)   // Task 2
StubBodyAnalyzer (PhotoPipelineTests.swift)                                // Task 2

// 앱 (Task 6)
EditorTool.body, BodyPanel, AppModel.BodyAvailability, AppModel.bodyAvailability, PhotoInfo.hasBody, .bodyAnalysisFailure
UserMessage.toolBody, bodyHint, noBodyDetected, noBodyHint, bodyAnalysisUnavailableTitle, bodyShapeTitle(_:)
StubBodyAnalyzer, TestSupport.standingBody(in:), TestSupport.makeModel(…, bodyAnalyzer:, …)
```

---

### Task 1: 관절점 타입과 체형 편집 변경 — BodyGeometry, EditChange.bodyShape, 잠금

**Files:**
- Create: `apple/Sources/MellowShared/API/BodyGeometry.swift`
- Modify: `apple/Sources/MellowShared/API/AdjustmentRange.swift` (`bodyShape(_:)`)
- Modify: `apple/Sources/MellowEditing/API/EditingPolicy.swift` (`bodyShapeRange(_:)`)
- Modify: `apple/Sources/MellowEditing/API/EditChange.swift` (`bodyShape`, `affectsGeometry`)
- Modify: `apple/Sources/MellowEditing/API/EditDocument.swift` (`set`의 switch, `isGeometryLocked` 주석)
- Test: `apple/Tests/MellowSharedTests/BodyGeometryTests.swift`(새 파일), `apple/Tests/MellowEditingTests/EditDocumentTests.swift`

**Interfaces:**
- Consumes: `NormalizedPoint`, `NormalizedRect`, `BodyShapeKey`, `BodyShapeAdjustments` 첨자, `AdjustmentRange.unit`·`bipolar`·`clamped(_:to:)`, `EditDocument.merged`(B에서 이미 잠긴 사진의 `body`를 보존).
- Produces: `public enum BodyJoint`(14개, `CaseIterable`). `public struct BodyGeometry`(`joints`, `confidence`, `boundingBox`, `init(joints:confidence:boundingBox: NormalizedRect? = nil)`, `point(_:minimumConfidence:)`, `area`). `AdjustmentRange.bodyShape(_:)`, `EditingPolicy.bodyShapeRange(_:)`. `EditChange.bodyShape(BodyShapeKey, Double)`(`affectsGeometry == true`, 범위로 자름).

확인한 기존 동작(C 이월 g): `EditDocument.merged`가 잠긴 사진의 `portrait.face`와 `body`를 이미 보존하고 `EditDocumentTests`(“잠긴 사진은 체형도 유지한다”)가 고정한다. 이 Task는 그 부분을 바꾸지 않는다.

- [ ] **Step 1: 실패하는 테스트 작성**

`apple/Tests/MellowSharedTests/BodyGeometryTests.swift`:

```swift
import MellowShared
import XCTest

final class BodyGeometryTests: XCTestCase {
    func testPointDropsLowConfidenceAndMissingJoints() {
        let body = BodyGeometry(
            joints: [
                .neck: NormalizedPoint(x: 0.5, y: 0.8), .leftHip: NormalizedPoint(x: 0.6, y: 0.5),
                .leftKnee: NormalizedPoint(x: 0.6, y: 0.3),
            ],
            confidence: [.neck: 0.9, .leftHip: 0.29])
        XCTAssertEqual(body.point(.neck, minimumConfidence: 0.3), NormalizedPoint(x: 0.5, y: 0.8))
        XCTAssertNil(body.point(.leftHip, minimumConfidence: 0.3), "신뢰도가 낮으면 없는 것")
        XCTAssertNil(body.point(.leftKnee, minimumConfidence: 0.3), "신뢰도가 없으면 없는 것")
        XCTAssertNil(body.point(.rightAnkle, minimumConfidence: 0), "점이 없으면 nil")
    }

    func testBoundingBoxDefaultsToJointExtentAndGivesArea() {
        let body = BodyGeometry(
            joints: [
                .neck: NormalizedPoint(x: 0.5, y: 0.9), .leftAnkle: NormalizedPoint(x: 0.6, y: 0.1),
                .rightAnkle: NormalizedPoint(x: 0.3, y: 0.15),
            ],
            confidence: [:])
        XCTAssertEqual(body.boundingBox.minX, 0.3, accuracy: 1e-12)
        XCTAssertEqual(body.boundingBox.minY, 0.1, accuracy: 1e-12)
        XCTAssertEqual(body.boundingBox.maxX, 0.6, accuracy: 1e-12)
        XCTAssertEqual(body.boundingBox.maxY, 0.9, accuracy: 1e-12)
        XCTAssertEqual(body.area, 0.3 * 0.8, accuracy: 1e-12)
        XCTAssertEqual(BodyGeometry(joints: [:], confidence: [:]).area, 0, "관절이 없으면 넓이 0")
        let given = NormalizedRect(x: 0, y: 0, width: 0.5, height: 0.5)
        XCTAssertEqual(BodyGeometry(joints: [:], confidence: [:], boundingBox: given).boundingBox, given)
    }

    func testBodyShapeRangeIsUnitOnlyForLegLength() {
        for key in BodyShapeKey.allCases {
            let expected = key == .legLength ? AdjustmentRange.unit : AdjustmentRange.bipolar
            XCTAssertEqual(AdjustmentRange.bodyShape(key), expected, "\(key)")
        }
        XCTAssertEqual(BodyJoint.allCases.count, 14, "스펙 5의 관절 14개")
    }
}
```

`EditDocumentTests.swift`의 `testFeatureAndBackgroundChangesClampAndStayUnlocked` 뒤에 추가:

```swift
    func testBodyShapeChangesClampAndAreOneUndoStepEach() {
        var document = EditDocument()
        XCTAssertNil(document.set(.bodyShape(.waist, -1.7)))
        XCTAssertNil(document.set(.bodyShape(.legLength, -0.4)), "다리 길게는 0 아래로 가지 않는다")
        XCTAssertNil(document.set(.bodyShape(.legLength, 2)))
        XCTAssertNil(document.set(.bodyShape(.neck, 0.3)))
        XCTAssertEqual(document.recipe.body, BodyShapeAdjustments(legLength: 1, waist: -1, neck: 0.3))
        XCTAssertEqual(EditingPolicy.bodyShapeRange(.legLength), EditingPolicy.unitRange)
        XCTAssertEqual(EditingPolicy.bodyShapeRange(.arms), EditingPolicy.bipolarRange)
        document.undo()
        XCTAssertEqual(document.recipe.body.neck, 0, "변경마다 실행 취소 한 단계")
        XCTAssertEqual(document.recipe.body.legLength, 1)
    }

    func testBodyShapeIsLockedByLocalEditsLikeFaceShape() {
        var document = EditDocument()
        document.appendLocalEdit(.warp(WarpStroke(x: 0.5, y: 0.5, dx: 0.01, dy: 0, radius: 0.1)))
        XCTAssertTrue(EditChange.bodyShape(.waist, -0.5).affectsGeometry)
        for key in BodyShapeKey.allCases {
            XCTAssertEqual(document.set(.bodyShape(key, 0.5)), .geometryLocked, "\(key)는 잠긴다")
        }
        XCTAssertEqual(document.recipe.body, BodyShapeAdjustments())
        XCTAssertEqual(document.undoStack.count, 1, "거절된 변경은 실행 취소 단계를 만들지 않는다")
    }
```

- [ ] **Step 2: 실패 확인**

Run: `cd apple && swift test --filter 'BodyGeometryTests|EditDocumentTests'` → 컴파일 실패(`cannot find 'BodyGeometry' in scope`, `type 'EditChange' has no member 'bodyShape'`).

- [ ] **Step 3: 구현**

`apple/Sources/MellowShared/API/BodyGeometry.swift`:

```swift
import Foundation

/// Vision VNHumanBodyPoseObservation.JointName 중 체형 보정이 쓰는 14개(스펙 5). left·right는 찍힌 사람 기준이다.
public enum BodyJoint: String, CaseIterable, Codable, Sendable {
    case neck
    case leftShoulder
    case rightShoulder
    case leftElbow
    case rightElbow
    case leftWrist
    case rightWrist
    case leftHip
    case rightHip
    case leftKnee
    case rightKnee
    case leftAnkle
    case rightAnkle
    case root
}

/// 사람 한 명의 관절점. 영속화하지 않는다. 사진을 준비할 때마다 다시 계산한다.
/// 좌표는 이미지 기준 정규화(원점 왼쪽 아래). 정면 사진에서 leftShoulder는 화면 오른쪽에 있다.
/// 렌더는 좌우를 이름이 아니라 위치로 정한다.
public struct BodyGeometry: Equatable, Sendable {
    public var joints: [BodyJoint: NormalizedPoint]
    /// 관절별 신뢰도 0…1. 값이 없는 관절은 신뢰도가 없는 것으로 본다.
    public var confidence: [BodyJoint: Double]
    /// 관절을 감싸는 상자. 여러 사람 중 가장 큰 사람을 고르는 데 쓴다.
    public var boundingBox: NormalizedRect

    /// boundingBox가 nil이면 joints를 감싸는 상자로 정한다. 관절이 없으면 크기 0인 상자다.
    public init(
        joints: [BodyJoint: NormalizedPoint], confidence: [BodyJoint: Double], boundingBox: NormalizedRect? = nil
    ) {
        self.joints = joints
        self.confidence = confidence
        self.boundingBox = boundingBox ?? Self.enclosing(Array(joints.values))
    }

    /// 신뢰도가 minimumConfidence 이상인 관절. 신뢰도가 낮거나 없으면 nil(스펙 5: 없는 것으로 본다).
    public func point(_ joint: BodyJoint, minimumConfidence: Double) -> NormalizedPoint? {
        guard let point = joints[joint], let value = confidence[joint], value >= minimumConfidence else { return nil }
        return point
    }

    /// 상자 넓이. 여러 사람 중 가장 큰 사람을 앞에 둘 때 쓴다.
    public var area: Double { boundingBox.width * boundingBox.height }

    private static func enclosing(_ points: [NormalizedPoint]) -> NormalizedRect {
        guard let first = points.first else { return NormalizedRect(x: 0, y: 0, width: 0, height: 0) }
        var minX = first.x
        var maxX = first.x
        var minY = first.y
        var maxY = first.y
        for point in points.dropFirst() {
            minX = min(minX, point.x)
            maxX = max(maxX, point.x)
            minY = min(minY, point.y)
            maxY = max(maxY, point.y)
        }
        return NormalizedRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }
}
```

`AdjustmentRange.swift`: `faceShape(_:)` 아래에 추가:

```swift
    /// 다리 길게만 한 방향이다.
    public static func bodyShape(_ key: BodyShapeKey) -> ClosedRange<Double> {
        key == .legLength ? unit : bipolar
    }
```

`EditingPolicy.swift`: `faceShapeRange(_:)` 아래에 추가:

```swift
    /// 다리 길게만 한 방향이다.
    public static func bodyShapeRange(_ key: BodyShapeKey) -> ClosedRange<Double> {
        AdjustmentRange.bodyShape(key)
    }
```

`EditChange.swift`: `case backgroundBlur(Double)` 아래에 `case bodyShape(BodyShapeKey, Double)`을 더하고 `affectsGeometry`를 다음으로 바꾼다:

```swift
    /// 수동 편집이 있는 동안 바꿀 수 없는 변경. 자르기·회전은 원본 좌표를 바꾸지 않으므로 잠기지 않는다.
    public var affectsGeometry: Bool {
        switch self {
        case .faceShape, .bodyShape, .targetFace:
            return true
        default:
            return false
        }
    }
```

`EditDocument.swift`:
1. `isGeometryLocked`의 주석을 `/// 수동 편집 좌표가 어긋나지 않도록 얼굴형·체형과 대상 얼굴을 고정한다.`로 바꾼다.
2. `set` switch의 `case .backgroundBlur(let value): …` 아래에 추가:

```swift
        case .bodyShape(let key, let value):
            updated.body[key] = EditingPolicy.clamped(value, to: EditingPolicy.bodyShapeRange(key))
```

앱 타깃에는 `EditChange`를 전부 나열하는 switch가 없다(계획 작성 때 `grep -rn "switch change" apple/MellowPhoto` 결과 없음). 그래서 앱 코드는 바꾸지 않는다.

- [ ] **Step 4: 통과 확인**

Run: `cd apple && swift test` → 모듈별 `Executed 40 tests`(Shared) · `163`(Rendering) · `30`(Library) · `4`(Export) · `26`(Editing), 모두 `with 0 failures`(합 263). lint 출력 없음. `./scripts/verify-modules.sh` 통과. Mac 앱 테스트 → `Executed 56 tests, with 0 failures`.

- [ ] **Step 5: 커밋**

```bash
git add apple/Sources/MellowShared/API/BodyGeometry.swift apple/Sources/MellowShared/API/AdjustmentRange.swift apple/Sources/MellowEditing/API/EditingPolicy.swift apple/Sources/MellowEditing/API/EditChange.swift apple/Sources/MellowEditing/API/EditDocument.swift apple/Tests/MellowSharedTests/BodyGeometryTests.swift apple/Tests/MellowEditingTests/EditDocumentTests.swift
git commit -m "feat(editing): 관절점 타입과 체형 편집 변경, 수동 편집 시 체형 잠금

BodyGeometry·BodyJoint를 MellowShared에 두고 신뢰도가 낮은 관절은 없는 것으로 본다.
bodyShape 변경은 다리 길게 0…1, 나머지 −1…1로 자르고 수동 편집이 있으면 잠긴다.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 2: 체형 분석 — BodyAnalyzer 포트, VisionBodyAnalyzer, BodySkeleton, 준비 단계 분석

**Files:**
- Modify: `apple/Sources/MellowShared/API/MellowError.swift` (`bodyAnalysisUnavailable`)
- Create: `apple/Sources/MellowRendering/API/BodyAnalyzer.swift`
- Create: `apple/Sources/MellowRendering/Infrastructure/VisionBodyAnalyzer.swift`
- Create: `apple/Sources/MellowRendering/Domain/BodySkeleton.swift`
- Modify: `apple/Sources/MellowRendering/API/PhotoAnalysis.swift` (`bodies`·`bodyAnalysisFailure`)
- Modify: `apple/Sources/MellowRendering/API/RenderStage.swift` (`bodies` 접근자)
- Modify: `apple/Sources/MellowRendering/API/RenderTuning.swift` (`bodyJointMinConfidence`)
- Modify: `apple/Sources/MellowRendering/API/PhotoPipeline.swift` (`PreparedPhoto` 필드, `init`, `prepare`, 체형 분석)
- Modify: `apple/MellowPhoto/Application/UserMessage.swift` (새 오류 문구)
- Modify: `apple/Tests/MellowRenderingTests/RenderingTestSupport.swift` (`standingBox`, `standingBody`, `BodyGeometry.rotated`)
- Test: `apple/Tests/MellowRenderingTests/VisionBodyAnalyzerTests.swift`, `BodySkeletonTests.swift`(새 파일 둘), `PhotoPipelineTests.swift`

**Interfaces:**
- Consumes: `BodyGeometry`·`BodyJoint`·`point(_:minimumConfidence:)`(Task 1), `PhotoAnalysis`·`PhotoPipeline.preparedAnalysis(_:)`(D), `ImageLoader`, `RenderingTestSupport.solid`·`personMask(size:person:)`.
- Produces: `MellowError.bodyAnalysisUnavailable(reason: String)`. `public protocol BodyAnalyzer: Sendable { func analyze(_ image: CIImage) throws -> [BodyGeometry] }`. `public struct VisionBodyAnalyzer: BodyAnalyzer`(`init()`, `public static func orderedLargestFirst(_:)`, internal `struct LocatedJoint`, internal `static func geometry(from:) -> BodyGeometry?`). `PhotoAnalysis.bodies`·`bodyAnalysisFailure`(init 인자 기본 `[]`·`nil`). `RenderContext.bodies`. `RenderTuning.bodyJointMinConfidence`(0.3). `PhotoPipeline.init(analyzer:personAnalyzer:bodyAnalyzer:tuning:lookCatalog:)`. `PreparedPhoto.hasBody`·`bodyAnalysisFailure`(init 인자 기본 `false`·`nil`). internal `struct BodySkeleton`(`joints`, `torsoWidth`, `shoulderCenter`, `hipCenter`, `up`, `across`, `init?(body:extent:tuning:)`, `point(_:)`, `side(of:from:)`, `static midpoint(_:_:)`, `static lerp(_:_:_:)`). 테스트 지원: `RenderingTestSupport.standingBox`, `standingBody(in:confidence:omitting:)`, `BodyGeometry.rotated(by:about:)`, `StubBodyAnalyzer`(PhotoPipelineTests.swift 위).

설계 근거:
- **Vision 요청.** `VNDetectHumanBodyPoseRequest`(이 Mac의 지원 리비전은 1뿐), `recognizedPoints(.all)`에서 14개 관절만 옮긴다. 위치는 Vision 정규화(원점 왼쪽 아래)라 그대로 쓴다. 신뢰도 0인 점은 Vision이 찾지 못한 관절이라 버린다. 사람 순서는 관절 상자 넓이 내림차순(스펙 1.4 "면적이 가장 큰 사람을 앞에"). 측정(Mac, 계획 작성 때): 1600px 미리보기 첫 호출 0.08~0.13초(모델 적재), 이후 약 0.005초. 공용 데모 사진(얼굴 가까운 셀카)과 단색 이미지는 0명이고 `VNDetectHumanRectanglesRequest`도 데모 사진에서 0명이다. 그래서 실제 사람을 찾는 경로는 자동 테스트가 확인하지 못하고(VALIDATION 미검증), 이름 대응·신뢰도·정렬은 순수 함수 테스트로 확인한다. `usesCPUOnly`는 넣지 않는다(인물 분석과 같은 이유).
- **어깨 기준(BodySkeleton).** 모든 체형 이동량이 어깨 폭 기준이라 두 어깨가 없거나 어깨 폭이 짧은 변의 2%보다 짧으면(옆모습·아주 작은 사람) 쓸 사람이 없다고 본다. `PreparedPhoto.hasBody`도 같은 판정(가장 큰 사람에 대해)이라 앱 안내와 렌더가 어긋나지 않는다. 몸통 세로축은 엉덩이 중점 → 어깨 중점(어깨 폭의 25%보다 멀 때), 아니면 어깨선에 수직인 위쪽이다. 가로축은 세로축을 시계 방향으로 90° 돌린 방향이다.
- **실패 처리(스펙 1.4).** 체형 분석 실패는 사진 준비를 막지 않고 `PreparedPhoto.bodyAnalysisFailure`로 남긴다. 얼굴·잡티·인물 분석과 서로 영향이 없다. `bodyAnalyzer`가 nil이면 분석하지 않는다(사람 없음과 같음). 앱 조립은 Task 6에서 `VisionBodyAnalyzer()`를 넘긴다.

- [ ] **Step 1: 테스트 지원 코드**

`RenderingTestSupport.swift`의 `enum RenderingTestSupport` 안, `personMask(size:person:)` 아래에 추가:

```swift
    /// 체형 테스트의 기본 사람 자리. 512 정사각형에서 어깨 폭 204.8px, 엉덩이 y 256, 발목 y 25.6.
    static let standingBox = NormalizedRect(x: 0.1, y: 0, width: 0.8, height: 1)

    /// 정면으로 선 사람의 관절점(box 비율). Vision처럼 찍힌 사람 기준 이름이라 leftShoulder가 화면 오른쪽이다.
    /// 모든 관절의 신뢰도는 confidence이고 omitting의 관절은 뺀다.
    static func standingBody(
        in box: NormalizedRect, confidence: Double = 1, omitting: Set<BodyJoint> = []
    ) -> BodyGeometry {
        let layout: [BodyJoint: (x: Double, y: Double)] = [
            .neck: (0.5, 0.82), .rightShoulder: (0.25, 0.8), .leftShoulder: (0.75, 0.8),
            .rightElbow: (0.18, 0.62), .leftElbow: (0.82, 0.62), .rightWrist: (0.15, 0.45), .leftWrist: (0.85, 0.45),
            .rightHip: (0.38, 0.5), .leftHip: (0.62, 0.5), .rightKnee: (0.39, 0.27), .leftKnee: (0.61, 0.27),
            .rightAnkle: (0.4, 0.05), .leftAnkle: (0.6, 0.05), .root: (0.5, 0.5),
        ]
        var joints: [BodyJoint: NormalizedPoint] = [:]
        var confidences: [BodyJoint: Double] = [:]
        for (joint, spot) in layout where !omitting.contains(joint) {
            joints[joint] = NormalizedPoint(x: box.minX + box.width * spot.x, y: box.minY + box.height * spot.y)
            confidences[joint] = confidence
        }
        return BodyGeometry(joints: joints, confidence: confidences)
    }
```

같은 파일 맨 아래(`extension FaceGeometry` 뒤)에 추가:

```swift
extension BodyGeometry {
    /// pivot 둘레로 반시계 angle(라디안) 돌린 관절점. 정사각형 extent에서만 픽셀 회전과 같다. 상자는 그대로 둔다.
    func rotated(by angle: Double, about pivot: NormalizedPoint) -> BodyGeometry {
        var copy = self
        for (joint, point) in joints {
            let x = point.x - pivot.x
            let y = point.y - pivot.y
            copy.joints[joint] = NormalizedPoint(
                x: pivot.x + x * cos(angle) - y * sin(angle), y: pivot.y + x * sin(angle) + y * cos(angle))
        }
        return copy
    }
}
```

`PhotoPipelineTests.swift`의 `struct StubPersonAnalyzer` 아래에 추가:

```swift
struct StubBodyAnalyzer: BodyAnalyzer {
    var result: Result<[BodyGeometry], MellowError>
    func analyze(_ image: CIImage) throws -> [BodyGeometry] { try result.get() }
}
```

- [ ] **Step 2: 실패하는 테스트 작성**

`apple/Tests/MellowRenderingTests/VisionBodyAnalyzerTests.swift`:

```swift
import CoreImage
import MellowShared
import XCTest

@testable import MellowRendering

final class VisionBodyAnalyzerTests: XCTestCase {
    typealias Support = RenderingTestSupport
    typealias Joint = VisionBodyAnalyzer.LocatedJoint

    func testBlankImageHasNoBody() throws {
        let blank = Support.solid(CIColor(red: 0.5, green: 0.6, blue: 0.7), size: 512)
        XCTAssertEqual(try VisionBodyAnalyzer().analyze(blank), [])
    }

    /// 데모 사진은 얼굴을 가까이 찍은 셀카라 계획 작성 때 측정으로 Vision이 사람을 찾지 않았다(0명).
    /// 실제 전신 인식은 이 테스트가 확인하지 않는다. 오류 없이 돌고 결과가 정렬·정규화돼 있는지만 본다.
    func testCloseUpSelfieAnalyzesWithoutThrowingAndKeepsOrder() throws {
        let url = try XCTUnwrap(
            Bundle.module.url(forResource: "demo-portrait", withExtension: "png", subdirectory: "Fixtures"))
        let image = try ImageLoader().load(url: url, maxDimension: 1600)
        let bodies = try VisionBodyAnalyzer().analyze(image)
        XCTAssertEqual(bodies.map(\.area), bodies.map(\.area).sorted(by: >), "큰 사람이 앞")
        for point in bodies.flatMap({ Array($0.joints.values) }) {
            XCTAssertTrue((0...1).contains(point.x) && (0...1).contains(point.y), "정규화 좌표")
        }
    }

    func testGeometryDropsUnfoundJointsAndBoxesTheRest() throws {
        let body = try XCTUnwrap(
            VisionBodyAnalyzer.geometry(from: [
                .neck: Joint(location: CGPoint(x: 0.5, y: 0.8), confidence: 0.9),
                .leftAnkle: Joint(location: CGPoint(x: 0.6, y: 0.1), confidence: 0.4),
                .rightAnkle: Joint(location: .zero, confidence: 0),
            ]))
        XCTAssertEqual(Set(body.joints.keys), [.neck, .leftAnkle], "신뢰도 0(찾지 못한 관절)은 버린다")
        XCTAssertEqual(body.confidence[.leftAnkle], 0.4)
        XCTAssertEqual(body.boundingBox.minX, 0.5, accuracy: 1e-9)
        XCTAssertEqual(body.boundingBox.minY, 0.1, accuracy: 1e-9)
        XCTAssertEqual(body.boundingBox.maxX, 0.6, accuracy: 1e-9)
        XCTAssertEqual(body.boundingBox.maxY, 0.8, accuracy: 1e-9)
        XCTAssertNil(VisionBodyAnalyzer.geometry(from: [.neck: Joint(location: .zero, confidence: 0)]), "남은 관절이 없으면 사람이 아니다")
    }

    func testOrderedLargestFirst() {
        let small = Support.standingBody(in: NormalizedRect(x: 0.7, y: 0.5, width: 0.2, height: 0.3))
        let large = Support.standingBody(in: Support.standingBox)
        XCTAssertEqual(VisionBodyAnalyzer.orderedLargestFirst([small, large]), [large, small])
    }
}
```

`apple/Tests/MellowRenderingTests/BodySkeletonTests.swift`:

```swift
import CoreImage
import MellowShared
import XCTest

@testable import MellowRendering

final class BodySkeletonTests: XCTestCase {
    typealias Support = RenderingTestSupport

    private let extent = CGRect(x: 0, y: 0, width: 512, height: 512)

    func testUprightBodyUsesPixelJointsAndTorsoAxes() throws {
        let body = Support.standingBody(in: Support.standingBox)
        let skeleton = try XCTUnwrap(BodySkeleton(body: body, extent: extent, tuning: RenderTuning()))
        XCTAssertEqual(skeleton.torsoWidth, 204.8, accuracy: 1e-6, "두 어깨 사이 거리")
        let hip = try XCTUnwrap(skeleton.point(.leftHip))
        XCTAssertEqual(hip.x, (0.1 + 0.8 * 0.62) * 512, accuracy: 1e-6)
        XCTAssertEqual(hip.y, 0.5 * 512, accuracy: 1e-6)
        XCTAssertEqual(skeleton.up.dx, 0, accuracy: 1e-9)
        XCTAssertEqual(skeleton.up.dy, 1, accuracy: 1e-9)
        XCTAssertEqual(skeleton.across.dx, 1, accuracy: 1e-9)
        XCTAssertEqual(skeleton.across.dy, 0, accuracy: 1e-9)
        XCTAssertEqual(skeleton.side(of: hip, from: skeleton.shoulderCenter), 1, "화면 오른쪽은 +1")
    }

    func testLowConfidenceJointsAreMissingAndShouldersAreRequired() {
        let tuning = RenderTuning()
        let faint = Support.standingBody(in: Support.standingBox, confidence: 0.2)
        XCTAssertNil(BodySkeleton(body: faint, extent: extent, tuning: tuning), "신뢰도 0.3 미만 어깨는 없는 것")
        let oneShoulder = Support.standingBody(in: Support.standingBox, omitting: [.rightShoulder])
        XCTAssertNil(BodySkeleton(body: oneShoulder, extent: extent, tuning: tuning))
        var faintKnee = Support.standingBody(in: Support.standingBox)
        faintKnee.confidence[.leftKnee] = 0.29
        let skeleton = BodySkeleton(body: faintKnee, extent: extent, tuning: tuning)
        XCTAssertNotNil(skeleton)
        XCTAssertNil(skeleton?.point(.leftKnee), "그 관절만 없는 것으로 본다")
        XCTAssertNotNil(skeleton?.point(.rightKnee))
        let sideways = BodyGeometry(
            joints: [.leftShoulder: NormalizedPoint(x: 0.5, y: 0.8), .rightShoulder: NormalizedPoint(x: 0.505, y: 0.8)],
            confidence: [.leftShoulder: 1, .rightShoulder: 1])
        XCTAssertNil(BodySkeleton(body: sideways, extent: extent, tuning: tuning), "어깨가 거의 겹치면(옆모습) 축을 정하지 않는다")
    }

    func testTiltedBodyAxesFollowHipsToShoulders() throws {
        let angle = Double.pi / 6
        let pivot = NormalizedPoint(x: 0.5, y: 0.5)
        let body = Support.standingBody(in: Support.standingBox).rotated(by: angle, about: pivot)
        let skeleton = try XCTUnwrap(BodySkeleton(body: body, extent: extent, tuning: RenderTuning()))
        XCTAssertEqual(skeleton.up.dx, -sin(angle), accuracy: 1e-9)
        XCTAssertEqual(skeleton.up.dy, cos(angle), accuracy: 1e-9)
        XCTAssertEqual(skeleton.across.dx, cos(angle), accuracy: 1e-9)
        XCTAssertEqual(skeleton.across.dy, sin(angle), accuracy: 1e-9)
        var noHip = body
        noHip.joints[.leftHip] = nil
        let shouldersOnly = try XCTUnwrap(BodySkeleton(body: noHip, extent: extent, tuning: RenderTuning()))
        XCTAssertNil(shouldersOnly.hipCenter)
        XCTAssertEqual(shouldersOnly.up.dx, -sin(angle), accuracy: 1e-9, "엉덩이가 없으면 어깨선에 수직")
        XCTAssertEqual(shouldersOnly.up.dy, cos(angle), accuracy: 1e-9)
    }
}
```

`PhotoPipelineTests.swift`의 `testWithoutPersonAnalyzerThereIsNoPerson` 뒤에 추가:

```swift
    func testPrepareStoresBodiesAndReportsUsableBody() async throws {
        let url = try writeSolidPNG()
        let large = Support.standingBody(in: Support.standingBox)
        let small = Support.standingBody(in: NormalizedRect(x: 0.7, y: 0.5, width: 0.2, height: 0.3))
        let pipeline = PhotoPipeline(
            analyzer: StubFaceAnalyzer(result: .success([])),
            bodyAnalyzer: StubBodyAnalyzer(result: .success([large, small])), tuning: RenderTuning())
        let id = PhotoID()
        let prepared = try await pipeline.prepare(id, at: url)
        XCTAssertTrue(prepared.hasBody)
        XCTAssertNil(prepared.bodyAnalysisFailure)
        let analysis = await pipeline.preparedAnalysis(id)
        XCTAssertEqual(analysis?.bodies, [large, small], "분석기가 준 순서 그대로 보관한다")
    }

    func testBodyWithoutBothShouldersIsNotUsable() async throws {
        let url = try writeSolidPNG()
        let body = Support.standingBody(in: Support.standingBox, omitting: [.leftShoulder])
        let pipeline = PhotoPipeline(
            analyzer: StubFaceAnalyzer(result: .success([])),
            bodyAnalyzer: StubBodyAnalyzer(result: .success([body])), tuning: RenderTuning())
        let id = PhotoID()
        let prepared = try await pipeline.prepare(id, at: url)
        XCTAssertFalse(prepared.hasBody, "체형 이동량의 기준인 어깨 폭이 없다")
        let analysis = await pipeline.preparedAnalysis(id)
        XCTAssertEqual(analysis?.bodies.count, 1, "관절은 그대로 보관한다")
    }

    func testBodyAnalysisFailureIsReportedNotThrown() async throws {
        let url = try writeSolidPNG()
        let face = FaceGeometry(boundingBox: NormalizedRect(x: 0.2, y: 0.2, width: 0.6, height: 0.6))
        let mask = Support.personMask(
            size: CGSize(width: 64, height: 48), person: CGRect(x: 16, y: 8, width: 32, height: 32))
        let pipeline = PhotoPipeline(
            analyzer: StubFaceAnalyzer(result: .success([face])),
            personAnalyzer: StubPersonAnalyzer(result: .success(mask)),
            bodyAnalyzer: StubBodyAnalyzer(result: .failure(.bodyAnalysisUnavailable(reason: "test"))),
            tuning: RenderTuning())
        let prepared = try await pipeline.prepare(PhotoID(), at: url)
        XCTAssertFalse(prepared.hasBody)
        XCTAssertEqual(prepared.bodyAnalysisFailure, .bodyAnalysisUnavailable(reason: "test"))
        XCTAssertEqual(prepared.faces, [face], "체형 분석 실패가 얼굴 분석에 영향을 주지 않는다")
        XCTAssertTrue(prepared.hasPerson, "인물 분석에도 영향을 주지 않는다")
    }

    func testWithoutBodyAnalyzerThereIsNoBody() async throws {
        let url = try writeSolidPNG()
        let pipeline = PhotoPipeline(analyzer: StubFaceAnalyzer(result: .success([])), tuning: RenderTuning())
        let id = PhotoID()
        let prepared = try await pipeline.prepare(id, at: url)
        XCTAssertFalse(prepared.hasBody)
        XCTAssertNil(prepared.bodyAnalysisFailure)
        let analysis = await pipeline.preparedAnalysis(id)
        XCTAssertEqual(analysis?.bodies, [])
    }
```

- [ ] **Step 3: 실패 확인**

Run: `cd apple && swift test --filter 'VisionBodyAnalyzerTests|BodySkeletonTests|PhotoPipelineTests'` → 컴파일 실패(`cannot find type 'BodyAnalyzer' in scope`, `cannot find 'BodySkeleton' in scope`).

- [ ] **Step 4: 구현**

`MellowError.swift`: `case personAnalysisUnavailable(reason: String)` 아래에 `case bodyAnalysisUnavailable(reason: String)`.

`UserMessage.swift`의 `text(for:)` switch에서 `case .personAnalysisUnavailable` 블록 아래에 추가:

```swift
        case .bodyAnalysisUnavailable(let reason):
            return "몸의 관절을 분석할 수 없어 체형 보정을 쓸 수 없습니다. 다른 보정은 사용할 수 있어요. (\(reason))"
```

`RenderTuning.swift`: `backgroundMaskFeather` 아래에 추가:

```swift
    /// 관절 신뢰도가 이보다 낮으면 없는 것으로 본다(스펙 5).
    public var bodyJointMinConfidence: Double = 0.3
```

`apple/Sources/MellowRendering/API/BodyAnalyzer.swift`:

```swift
import CoreImage
import MellowShared

/// 관절점 포트. 기본 구현은 Infrastructure의 VisionBodyAnalyzer다.
public protocol BodyAnalyzer: Sendable {
    /// 찾은 사람들의 관절점. 관절 상자 넓이가 큰 사람이 앞이다. 사람이 없으면 빈 배열.
    /// 분석 자체가 불가능하면 MellowError.bodyAnalysisUnavailable.
    func analyze(_ image: CIImage) throws -> [BodyGeometry]
}
```

`apple/Sources/MellowRendering/Infrastructure/VisionBodyAnalyzer.swift`:

```swift
import CoreImage
import MellowShared
import Vision

/// VNDetectHumanBodyPoseRequest로 사람마다 관절 14개를 찾는다. 좌표는 Vision 정규화(원점 왼쪽 아래) 그대로다.
public struct VisionBodyAnalyzer: BodyAnalyzer {
    /// Vision이 찾은 관절 하나의 위치(정규화)와 신뢰도.
    struct LocatedJoint {
        let location: CGPoint
        let confidence: Double
    }

    /// BodyJoint와 Vision 관절 이름의 대응. 눈·귀·코는 쓰지 않는다.
    private static let jointNames: [(BodyJoint, VNHumanBodyPoseObservation.JointName)] = [
        (.neck, .neck), (.leftShoulder, .leftShoulder), (.rightShoulder, .rightShoulder),
        (.leftElbow, .leftElbow), (.rightElbow, .rightElbow), (.leftWrist, .leftWrist), (.rightWrist, .rightWrist),
        (.leftHip, .leftHip), (.rightHip, .rightHip), (.leftKnee, .leftKnee), (.rightKnee, .rightKnee),
        (.leftAnkle, .leftAnkle), (.rightAnkle, .rightAnkle), (.root, .root),
    ]

    public init() {}

    public func analyze(_ image: CIImage) throws -> [BodyGeometry] {
        let request = VNDetectHumanBodyPoseRequest()
        do {
            try VNImageRequestHandler(ciImage: image, options: [:]).perform([request])
        } catch {
            throw MellowError.bodyAnalysisUnavailable(reason: error.localizedDescription)
        }
        let bodies = (request.results ?? []).compactMap { observation -> BodyGeometry? in
            guard let points = try? observation.recognizedPoints(.all) else { return nil }
            var located: [BodyJoint: LocatedJoint] = [:]
            for (joint, name) in Self.jointNames {
                guard let point = points[name] else { continue }
                located[joint] = LocatedJoint(location: point.location, confidence: Double(point.confidence))
            }
            return Self.geometry(from: located)
        }
        return Self.orderedLargestFirst(bodies)
    }

    /// 신뢰도 0 이하인 점(Vision이 찾지 못한 관절)은 버린다. 남은 점이 없으면 nil. 상자는 남은 점을 감싼다.
    static func geometry(from located: [BodyJoint: LocatedJoint]) -> BodyGeometry? {
        var joints: [BodyJoint: MellowShared.NormalizedPoint] = [:]
        var confidence: [BodyJoint: Double] = [:]
        for (joint, point) in located where point.confidence > 0 {
            joints[joint] = MellowShared.NormalizedPoint(x: Double(point.location.x), y: Double(point.location.y))
            confidence[joint] = point.confidence
        }
        guard !joints.isEmpty else { return nil }
        return BodyGeometry(joints: joints, confidence: confidence)
    }

    /// 관절 상자 넓이가 큰 사람부터. 체형은 첫 사람만 바꾼다(스펙 5).
    public static func orderedLargestFirst(_ bodies: [BodyGeometry]) -> [BodyGeometry] {
        bodies.sorted { $0.area > $1.area }
    }
}
```

`apple/Sources/MellowRendering/Domain/BodySkeleton.swift`:

```swift
import CoreImage
import MellowShared

/// 사람 한 명의 관절을 extent 픽셀 좌표로 옮기고 몸통 좌표축과 어깨 폭을 정한다.
/// 신뢰도가 bodyJointMinConfidence보다 낮은 관절은 없는 것으로 본다.
/// 모든 체형 항목의 이동량이 어깨 폭 기준이라 두 어깨가 없거나 거의 겹치면(옆모습) nil이다.
struct BodySkeleton {
    /// 어깨 폭이 extent 짧은 변의 이 비율보다 작으면 몸통 방향을 정할 수 없다고 본다(옆모습·아주 작은 사람).
    private static let minimumTorsoFraction: CGFloat = 0.02
    /// 엉덩이 중점이 어깨 중점에서 어깨 폭의 이 비율보다 가까우면 세로축을 엉덩이로 정하지 않는다.
    private static let minimumTorsoHeight: CGFloat = 0.25
    /// 중점의 보간 비율.
    private static let halfway: CGFloat = 0.5

    /// 신뢰도를 넘은 관절의 픽셀 위치.
    let joints: [BodyJoint: CGPoint]
    /// 두 어깨 사이 거리(픽셀). 체형 이동량의 기준 길이다.
    let torsoWidth: CGFloat
    /// 두 어깨 중점.
    let shoulderCenter: CGPoint
    /// 두 엉덩이 중점. 엉덩이가 하나라도 없으면 nil.
    let hipCenter: CGPoint?
    /// 몸통 세로축(엉덩이 → 어깨) 단위 벡터. 엉덩이가 없으면 어깨선에 수직인 위쪽이다.
    let up: CGVector
    /// 몸통 가로축 단위 벡터. up을 시계 방향으로 90° 돌린 방향(똑바로 선 사람에서 화면 오른쪽)이다.
    let across: CGVector

    init?(body: BodyGeometry, extent: CGRect, tuning: RenderTuning) {
        var joints: [BodyJoint: CGPoint] = [:]
        for joint in BodyJoint.allCases {
            guard let point = body.point(joint, minimumConfidence: tuning.bodyJointMinConfidence),
                point.x.isFinite, point.y.isFinite
            else { continue }
            joints[joint] = CGPoint(x: extent.minX + point.x * extent.width, y: extent.minY + point.y * extent.height)
        }
        guard let left = joints[.leftShoulder], let right = joints[.rightShoulder] else { return nil }
        let width = hypot(right.x - left.x, right.y - left.y)
        guard width >= Self.minimumTorsoFraction * min(extent.width, extent.height) else { return nil }
        let shoulderCenter = Self.midpoint(left, right)
        var hipCenter: CGPoint?
        if let leftHip = joints[.leftHip], let rightHip = joints[.rightHip] {
            hipCenter = Self.midpoint(leftHip, rightHip)
        }
        let up: CGVector
        if let hip = hipCenter,
            hypot(shoulderCenter.x - hip.x, shoulderCenter.y - hip.y) > Self.minimumTorsoHeight * width
        {
            up = Self.unit(CGVector(dx: shoulderCenter.x - hip.x, dy: shoulderCenter.y - hip.y))
        } else {
            let first = left.x <= right.x ? left : right
            let second = left.x <= right.x ? right : left
            let line = Self.unit(CGVector(dx: second.x - first.x, dy: second.y - first.y))
            up = CGVector(dx: -line.dy, dy: line.dx)
        }
        self.joints = joints
        torsoWidth = width
        self.shoulderCenter = shoulderCenter
        self.hipCenter = hipCenter
        self.up = up
        across = CGVector(dx: up.dy, dy: -up.dx)
    }

    func point(_ joint: BodyJoint) -> CGPoint? {
        joints[joint]
    }

    /// point가 center의 가로축 쪽(오른쪽)이면 +1, 반대쪽이면 −1, 가로축 성분이 0이면 0.
    func side(of point: CGPoint, from center: CGPoint) -> CGFloat {
        let along = (point.x - center.x) * across.dx + (point.y - center.y) * across.dy
        if along > 0 {
            return 1
        }
        if along < 0 {
            return -1
        }
        return 0
    }

    static func midpoint(_ first: CGPoint, _ second: CGPoint) -> CGPoint {
        lerp(first, second, halfway)
    }

    /// first에서 second 쪽으로 t만큼 간 점.
    static func lerp(_ first: CGPoint, _ second: CGPoint, _ t: CGFloat) -> CGPoint {
        CGPoint(x: first.x + (second.x - first.x) * t, y: first.y + (second.y - first.y) * t)
    }

    private static func unit(_ vector: CGVector) -> CGVector {
        let length = hypot(vector.dx, vector.dy)
        guard length > 0 else { return CGVector(dx: 0, dy: 1) }
        return CGVector(dx: vector.dx / length, dy: vector.dy / length)
    }
}
```

`PhotoAnalysis.swift`: `personAnalysisFailure` 아래에 필드 둘을 더하고 init을 바꾼다:

```swift
    /// 관절점. 상자 넓이가 큰 사람이 앞이고 체형은 첫 사람만 바꾼다. 사람이 없으면 빈 배열.
    public var bodies: [BodyGeometry]
    /// 체형 분석이 실패했으면 그 이유. 사람이 없는 것과 구분한다.
    public var bodyAnalysisFailure: MellowError?
```

```swift
    public init(
        faces: [FaceGeometry] = [], faceAnalysisFailure: MellowError? = nil, blemishes: [BlemishSpot] = [],
        personMask: CIImage? = nil, personAnalysisFailure: MellowError? = nil, bodies: [BodyGeometry] = [],
        bodyAnalysisFailure: MellowError? = nil
    ) {
        self.faces = faces
        self.faceAnalysisFailure = faceAnalysisFailure
        self.blemishes = blemishes
        self.personMask = personMask
        self.personAnalysisFailure = personAnalysisFailure
        self.bodies = bodies
        self.bodyAnalysisFailure = bodyAnalysisFailure
    }
```

`RenderStage.swift`: `public var personMask` 아래에 추가:

```swift
    /// 사진 준비 때 찾은 관절점. 상자 넓이가 큰 사람이 앞이다. 없거나 분석이 실패했으면 비어 있고 체형 원소가 빠진다.
    public var bodies: [BodyGeometry] { analysis.bodies }
```

`PhotoPipeline.swift`:

1. `PreparedPhoto`에 필드 둘을 더하고 init을 바꾼다:

```swift
    /// 가장 큰 사람의 두 어깨가 보이면 true. 체형 도구의 "전신 없음" 안내에 쓴다.
    public let hasBody: Bool
    /// 체형 분석이 실패했으면 그 이유. 사람이 없는 것과 구분한다.
    public let bodyAnalysisFailure: MellowError?

    public init(
        pixelSize: CGSize, thumbnail: CGImage, faces: [FaceGeometry], faceAnalysisFailure: MellowError?,
        hasPerson: Bool = false, personAnalysisFailure: MellowError? = nil, hasBody: Bool = false,
        bodyAnalysisFailure: MellowError? = nil
    ) {
        self.pixelSize = pixelSize
        self.thumbnail = thumbnail
        self.faces = faces
        self.faceAnalysisFailure = faceAnalysisFailure
        self.hasPerson = hasPerson
        self.personAnalysisFailure = personAnalysisFailure
        self.hasBody = hasBody
        self.bodyAnalysisFailure = bodyAnalysisFailure
    }
```

2. `private let personAnalyzer` 아래에 `private let bodyAnalyzer: (any BodyAnalyzer)?`를 더하고 init을 바꾼다:

```swift
    /// personAnalyzer·bodyAnalyzer가 nil이면 그 분석을 하지 않는다(사람 없음과 같다). 앱은 Vision 구현을 넘긴다.
    public init(
        analyzer: any FaceAnalyzer, personAnalyzer: (any PersonAnalyzer)? = nil,
        bodyAnalyzer: (any BodyAnalyzer)? = nil, tuning: RenderTuning, lookCatalog: LookCatalog = .empty
    ) {
        self.analyzer = analyzer
        self.personAnalyzer = personAnalyzer
        self.bodyAnalyzer = bodyAnalyzer
        self.tuning = tuning
        self.lookCatalog = lookCatalog
        cache = PreviewCache(capacity: tuning.previewCacheCapacity)
    }
```

3. `prepare`에서 `let person = analyzePerson(in: preview)`부터 `return PreparedPhoto(…)`까지를 다음으로 바꾼다:

```swift
        let person = analyzePerson(in: preview)
        let body = analyzeBodies(in: preview)
        let analysis = PhotoAnalysis(
            faces: faces, faceAnalysisFailure: failure, blemishes: detectBlemishes(in: preview, faces: faces),
            personMask: person.mask, personAnalysisFailure: person.failure, bodies: body.bodies,
            bodyAnalysisFailure: body.failure)
        let thumbnail = try renderer.makeCGImage(Self.scaled(preview, maxDimension: tuning.thumbnailMaxDimension))
        entries[id] = Entry(analysis: analysis, thumbnail: CIImage(cgImage: thumbnail))
        cache.insert(preview, for: id)
        releaseMasksOfEvictedPreviews()
        // 렌더(BodyShapeRig)와 같은 판정이라 앱 안내와 실제 동작이 어긋나지 않는다.
        let usable = body.bodies.first.flatMap { BodySkeleton(body: $0, extent: preview.extent, tuning: tuning) }
        return PreparedPhoto(
            pixelSize: metadata.pixelSize, thumbnail: thumbnail, faces: faces, faceAnalysisFailure: failure,
            hasPerson: person.mask != nil, personAnalysisFailure: person.failure, hasBody: usable != nil,
            bodyAnalysisFailure: body.failure)
```

4. `analyzePerson` 아래에 추가:

```swift
    /// 체형 분석이 실패해도 사진 준비는 막지 않는다. 체형 원소만 빠진다(스펙 1.4).
    private func analyzeBodies(in image: CIImage) -> (bodies: [BodyGeometry], failure: MellowError?) {
        guard let bodyAnalyzer else { return ([], nil) }
        do {
            return (try bodyAnalyzer.analyze(image), nil)
        } catch let error as MellowError {
            return ([], error)
        } catch {
            return ([], .bodyAnalysisUnavailable(reason: error.localizedDescription))
        }
    }
```

`renderOriginal`은 바꾸지 않는다. 체형 값만 있는 레시피는 분석 실패·준비 전이어도 오류 없이 체형만 빠진다(스펙 1.4, Task 5가 테스트로 고정).

- [ ] **Step 5: 통과 확인**

Run: `cd apple && swift test` → 모듈별 `Executed 40 · 174 · 30 · 4 · 26 tests`, 모두 `with 0 failures`(합 274). lint 출력 없음. `./scripts/verify-modules.sh` 통과(새 import 없음). Mac 앱 테스트 → `Executed 56 tests, with 0 failures`.

- [ ] **Step 6: 커밋**

```bash
git add apple/Sources/MellowShared/API/MellowError.swift apple/Sources/MellowRendering apple/Tests/MellowRenderingTests apple/MellowPhoto/Application/UserMessage.swift
git commit -m "feat(rendering): 관절점 포트와 Vision 구현, 사진 준비 때 체형 분석

VNDetectHumanBodyPoseRequest로 관절 14개를 찾아 큰 사람부터 PhotoAnalysis.bodies에 둔다.
BodySkeleton이 신뢰도 낮은 관절을 빼고 어깨 폭과 몸통 축을 정한다.
실패는 PreparedPhoto.bodyAnalysisFailure로 남기고 사진 준비는 계속한다.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 3: 다리 띠 계산 방식 — 샘플링 커널에서 계산, smoothstep 가장자리, 띠 패치 제한

**Files:**
- Modify: `apple/Sources/MellowRendering/Domain/ShapePrimitive.swift` (band 문서·`displacement`, `isBand`)
- Modify: `apple/Sources/MellowRendering/Domain/DisplacementWarp.swift` (전체 교체)
- Test: `apple/Tests/MellowRenderingTests/DisplacementWarpTests.swift`

**Interfaces:**
- Consumes: 기존 `ShapePrimitive`(`limited(to:)`, `isIdentity`, `maxDisplacement`, `displacement(at:)`), `DisplacementWarp.apply(_:to:extent:limit:region:)`·`influenceBounds(_:extent:)`·`displacementField(_:extent:)`·`displacement(at:of:limit:)`, `RenderingTestSupport.markers`·`markerCentroid`·`expectedPosition`·`skinTexture`.
- Produces: `ShapePrimitive.isBand: Bool`. band의 CPU 참조 이동이 smoothstep 모양(양 끝 기울기 0, 너머 이동은 그대로 stretch × span). `DisplacementWarp.maximumBands`(1), `DisplacementWarp.fieldBounds(_:extent:) -> CGRect`(push·scale 경계만, 띠만 있으면 null). `influenceBounds`의 band 몫이 "시작 행부터 띠 쪽 먼 가장자리까지"로 바뀜. `apply`는 띠가 둘 이상이면 `MellowError.renderFailed`. 시그니처는 그대로라 `ShapeWarpStage`는 바꾸지 않는다.

설계 근거(C 이월 c·d·e):
- **띠를 지도 밖에서 계산(c).** 지금은 band가 영향 경계를 extent 전체로 넓혀 다리 길게를 건드리면 사진 크기 RGBAh 지도(48MP 약 384MB)가 다시 생긴다. 띠 이동은 y만의 함수라 샘플링 커널에 균일 인자 `(yStart, span, stretch)`로 넘겨 그 자리에서 더한다. 지도는 push·scale 경계 합집합만 그리고, 지도 밖은 투명(이동 0)으로 읽힌다. 패치(샘플링·합성 영역)는 push·scale 경계와 "띠 시작 행 + 여유부터 띠 쪽 먼 가장자리까지 가로 전체"의 합집합이다. 띠 시작 반대쪽 행은 이동이 0이라 패치 밖이고 입력 바이트 그대로다. 띠는 체형 리그가 다리 길게 하나만 만들므로 커널은 띠 하나만 받는다.
- **smoothstep(d).** 띠 안 이동을 `stretch × span × t`에서 `stretch × span × t²(3 − 2t)`로 바꾼다. 양 끝(골반·발목)에서 기울기가 0이라 늘림이 꺾이지 않고(C1), 너머 이동(stretch × span)은 그대로다. 국소 늘림은 가운데에서 최대 1.5 × stretch다. 띠 매핑 y → y − D(y)의 기울기는 1 − stretch × S′(t) ≥ 1 − 1.5 × |stretch|이고 stretch는 limit(0.25)로 잘리므로 늘 0.625 이상이라 접히지 않는다.
- **정밀도(e).** 띠 이동은 커널 안 float32로 계산해 반정밀도 계단이 없다(512~1024px에서 0.5px 간격이던 문제). push·scale은 지도(작업 형식 RGBAh)에 그대로 둔다. 체형 push 하나의 최대 이동은 어깨 폭 × 0.06이고 48MP 긴 변(8064px)을 어깨 폭으로 잡아도 484px < 512px라 위치 오차는 0.25px 이하다. RGBAf 지도는 메모리가 두 배라 쓰지 않는다.

- [ ] **Step 1: 실패하는 테스트 작성**

`DisplacementWarpTests.swift`:

1. `testBandMappingIsMonotoneAndContinuous` 전체를 다음으로 바꾼다:

```swift
    func testBandMappingIsMonotoneAndContinuous() {
        let band = ShapePrimitive.band(yStart: 96, yEnd: 32, stretch: 0.08)
        let step: CGFloat = 0.5
        // smoothstep의 최대 기울기는 1.5라 한 걸음 변화는 step × 0.08 × 1.5 이하다.
        let maximumStepChange = step * 0.08 * 1.5 + 1e-9
        var previousSource = -CGFloat.infinity
        var previousShift = band.displacement(at: CGPoint(x: 0, y: 0)).dy
        for index in 0...256 {
            let y = CGFloat(index) * step
            let shift = band.displacement(at: CGPoint(x: 0, y: y)).dy
            let source = y - shift
            XCTAssertGreaterThan(source, previousSource, "출력 y가 커지면 읽는 입력 y도 커진다(접힘 없음) y=\(y)")
            XCTAssertLessThanOrEqual(abs(shift - previousShift), maximumStepChange, "끊김 없음 y=\(y)")
            previousSource = source
            previousShift = shift
        }
        XCTAssertEqual(band.displacement(at: CGPoint(x: 0, y: 10)).dy, -5.12, accuracy: 1e-9, "띠 아래 내용은 5.12px 내려온다")
        XCTAssertEqual(band.displacement(at: CGPoint(x: 0, y: 10)).dx, 0)
        XCTAssertEqual(band.displacement(at: CGPoint(x: 0, y: 64)).dy, -2.56, accuracy: 1e-9, "띠 가운데는 전체 이동의 절반")
        XCTAssertEqual(band.displacement(at: CGPoint(x: 0, y: 110)).dy, 0, "띠 위는 그대로")
    }
```

2. 그 바로 뒤에 추가:

```swift
    func testBandEdgesHaveZeroSlope() {
        let band = ShapePrimitive.band(yStart: 96, yEnd: 32, stretch: 0.08)
        let h: CGFloat = 0.01
        func slope(at y: CGFloat) -> CGFloat {
            let above = band.displacement(at: CGPoint(x: 0, y: y + h)).dy
            let below = band.displacement(at: CGPoint(x: 0, y: y - h)).dy
            return (above - below) / (2 * h)
        }
        XCTAssertEqual(slope(at: 96), 0, accuracy: 1e-3, "골반(띠 시작)에서 꺾이지 않는다")
        XCTAssertEqual(slope(at: 32), 0, accuracy: 1e-3, "발목(띠 끝)에서 꺾이지 않는다")
        XCTAssertEqual(slope(at: 64), 0.12, accuracy: 1e-3, "가운데 기울기는 1.5 × stretch")
    }
```

3. `testInfluenceBoundsCoverEachPrimitiveInsideExtent`의 마지막 두 줄(`let band = …`와 `"띠는 그 너머 전체를 옮긴다"` 단언)을 다음으로 바꾼다:

```swift
        // 띠는 시작 행 96 + 이동 5.12 + 여백 2 = 103.12 아래만 움직인다. 위쪽 행은 패치에서 빠진다.
        let band = ShapePrimitive.band(yStart: 96, yEnd: 32, stretch: 0.08)
        XCTAssertEqual(
            DisplacementWarp.influenceBounds([band], extent: extent), CGRect(x: 0, y: 0, width: 128, height: 104))
        // 위로 늘리는 띠는 32 − 7.12 = 24.88 위만.
        let rising = ShapePrimitive.band(yStart: 32, yEnd: 96, stretch: 0.08)
        XCTAssertEqual(
            DisplacementWarp.influenceBounds([rising], extent: extent), CGRect(x: 0, y: 24, width: 128, height: 104))
```

4. 파일 맨 아래(`testPatchWarpMatchesFullExtentWarp` 뒤)에 추가:

```swift
    func testBandIsNotDrawnIntoFieldAndRowsAboveKeepInputBytes() throws {
        let band = ShapePrimitive.band(yStart: 96, yEnd: 32, stretch: 0.08)
        let push = ShapePrimitive.push(center: CGPoint(x: 100, y: 110), vector: CGVector(dx: 3, dy: 0), radius: 10)
        XCTAssertTrue(DisplacementWarp.fieldBounds([band], extent: extent).isNull, "띠만 있으면 지도를 그리지 않는다")
        XCTAssertEqual(
            DisplacementWarp.fieldBounds([band, push], extent: extent),
            DisplacementWarp.influenceBounds([push], extent: extent), "지도는 push 경계만")
        // 사진처럼 비트맵에서 읽은 입력. 패치 밖 바이트 동일성은 비트맵 입력에서만 판정할 수 있다(C Task 4).
        let input = CIImage(cgImage: try Support.renderer.makeCGImage(Support.skinTexture(size: 128)))
        let before = try Support.grid(input)
        let after = try Support.grid(warp(input, [band]))
        var changedAbove = 0
        var changedBelow = 0
        for y in 0..<128 {
            for x in 0..<128 {
                let point = CGPoint(x: x, y: y)
                guard after.rgba(point) != before.rgba(point) else { continue }
                if y >= 104 {
                    changedAbove += 1
                } else {
                    changedBelow += 1
                }
            }
        }
        XCTAssertEqual(changedAbove, 0, "띠 시작 위쪽 행(패치 밖)은 입력 바이트 그대로")
        XCTAssertGreaterThan(changedBelow, 0, "띠 안과 너머는 움직인다")
    }

    /// 띠 이동이 512px를 넘어도 반정밀도 지도의 0.5px 계단이 생기지 않는다(띠는 샘플링 커널이 float로 계산한다).
    func testLargeBandShiftKeepsSubpixelAccuracy() throws {
        let tall = CGRect(x: 0, y: 0, width: 32, height: 4096)
        // 2600 × 0.24625 = 640.25. 반정밀도는 512~1024에서 0.5 간격이라 지도에 담으면 640으로 반올림된다.
        let band = ShapePrimitive.band(yStart: 100, yEnd: 2700, stretch: 0.24625)
        let marker = CGPoint(x: 16, y: 3000)
        let input = Support.markers([marker], extent: tall)
        let output = try DisplacementWarp.shared.apply([band], to: input, extent: tall, limit: limit)
        let reference = input.transformed(by: CGAffineTransform(translationX: 0, y: 640.25)).cropped(to: tall)
        let expected = CGPoint(x: 16, y: 3640.25)
        let moved = try XCTUnwrap(Support.markerCentroid(Support.grid(output), near: expected, window: 8))
        let translated = try XCTUnwrap(Support.markerCentroid(Support.grid(reference), near: expected, window: 8))
        XCTAssertEqual(moved.y, translated.y, accuracy: 0.1, "띠 너머는 640.25px 평행 이동과 같다")
        XCTAssertEqual(moved.x, translated.x, accuracy: 0.05)
    }

    func testOnlyOneBandIsAccepted() {
        let first = ShapePrimitive.band(yStart: 96, yEnd: 32, stretch: 0.05)
        let second = ShapePrimitive.band(yStart: 120, yEnd: 60, stretch: 0.05)
        XCTAssertThrowsError(try warp(Support.gradient(), [first, second])) { error in
            XCTAssertEqual(error as? MellowError, .renderFailed, "샘플링 커널은 띠 하나만 받는다")
        }
    }

    func testBandAndPushMoveMarkerTogether() throws {
        let band = ShapePrimitive.band(yStart: 96, yEnd: 32, stretch: 0.08)
        let push = ShapePrimitive.push(center: CGPoint(x: 64, y: 20), vector: CGVector(dx: 6, dy: 0), radius: 40)
        let marker = CGPoint(x: 64, y: 20)
        let result = try moved(marker, by: [band, push])
        assertNear(result, Support.expectedPosition(of: marker, primitives: [band, push], limit: limit))
        XCTAssertGreaterThan(result.x - marker.x, 4, "push 몫")
        XCTAssertLessThan(result.y - marker.y, -4, "띠 몫")
    }
```

- [ ] **Step 2: 실패 확인**

Run: `cd apple && swift test --filter DisplacementWarpTests` → 컴파일 실패(`type 'DisplacementWarp' has no member 'fieldBounds'`).

- [ ] **Step 3: 구현**

`ShapePrimitive.swift`:

1. `case band(…)`의 문서 주석을 다음으로 바꾼다:

```swift
    /// yStart에서 yEnd까지의 가로 띠를 yEnd 쪽으로 늘린다. 띠 안 이동은 stretch × span × t²(3 − 2t)라
    /// 양 끝(골반·발목)에서 기울기가 0이고 가운데 국소 늘림이 최대 1.5 × stretch다.
    /// yEnd 너머는 stretch × (yEnd − yStart)만큼 통째로 밀린다. 지도에 그리지 않고 DisplacementWarp 샘플링 커널이 같은 식으로 더한다.
```

2. `displacement(at:)`의 band case를 다음으로 바꾼다:

```swift
        case .band(let yStart, let yEnd, let stretch):
            let span = yEnd - yStart
            guard span != 0 else { return .zero }
            let t = min(1, max(0, (point.y - yStart) / span))
            return CGVector(dx: 0, dy: stretch * span * t * t * (3 - 2 * t))
```

3. `isIdentity` 위에 추가:

```swift
    /// 다리 길게 띠인지. 띠는 이동량 지도가 아니라 샘플링 커널이 계산한다.
    var isBand: Bool {
        switch self {
        case .band:
            return true
        case .push, .scale:
            return false
        }
    }
```

`apple/Sources/MellowRendering/Domain/DisplacementWarp.swift` 전체:

```swift
import CoreImage
import MellowShared

/// 얼굴형·체형 이동 원소를 이동량 지도 하나로 더해 한 번만 샘플링한다. 결과는 out(p) = in(p − D(p))다.
/// push·scale은 R = dx, G = dy(픽셀)인 작업 형식 float 지도에 그리고, 다리 길게 띠는 지도에 그리지 않고
/// 샘플링 커널이 균일 인자로 같은 식을 더한다. 띠를 지도에 그리면 사진 가로 전체 크기 중간 버퍼(48MP 약 384MB)가 생기고
/// 512px 넘는 이동이 반정밀도 지도에서 0.5px 계단이 되기 때문이다. 띠는 한 번에 하나만 받는다.
/// 지도 색 커널 2개와 샘플링 일반 커널 1개를 감싸는 유일한 자리. Metal로 바꿀 때 이 타입만 바꾼다.
/// CIWarpKernel은 균일 인자만 받고 이미지를 읽을 수 없어 지도를 샘플링하려면 일반 커널이 필요하다.
final class DisplacementWarp: @unchecked Sendable {
    static let shared = DisplacementWarp()

    /// 샘플링 커널이 식으로 더하는 띠의 최대 개수. 체형 리그는 다리 길게 띠 하나만 만든다.
    static let maximumBands = 1
    /// ROI를 최대 이동보다 이만큼(픽셀) 더 넓혀 쌍선형 샘플링이 잘리지 않게 한다.
    private static let roiPadding: CGFloat = 2
    /// 샘플링 커널에서 입력 이미지 인자의 순서. ROI 콜백이 인덱스로 구분한다.
    private static let imageArgumentIndex: Int32 = 0
    /// 띠가 없을 때 샘플링 커널에 넘기는 (시작, 길이, 늘림). 늘림이 0이라 이동이 없다.
    private static let noBand = CIVector(x: 0, y: 1, z: 0)
    /// 지도에 그릴 원소가 없을 때 넘기는 지도의 크기(픽셀). 이 밖은 투명(이동 0)으로 읽힌다.
    private static let emptyFieldSize = CGSize(width: 1, height: 1)

    private let pushField: CIColorKernel?
    private let scaleField: CIColorKernel?
    private let sampler: CIKernel?

    /// 지도 커널은 알파를 늘 1로 둔다. 사전곱 나눗셈이 이동량을 바꾸지 않게 한다.
    private init() {
        pushField = CIColorKernel(
            source: """
                kernel vec4 pushField(__sample field, vec2 center, vec2 vector, float radius) {
                    float t = clamp(1.0 - distance(destCoord(), center) / radius, 0.0, 1.0);
                    float w = t * t * (3.0 - 2.0 * t);
                    return vec4(field.rg + vector * w, 0.0, 1.0);
                }
                """)
        scaleField = CIColorKernel(
            source: """
                kernel vec4 scaleField(__sample field, vec2 center, float factor, float radius) {
                    vec2 offset = destCoord() - center;
                    float t = clamp(1.0 - length(offset) / radius, 0.0, 1.0);
                    float w = t * t * (3.0 - 2.0 * t);
                    return vec4(field.rg + offset * (factor * w), 0.0, 1.0);
                }
                """)
        sampler = CIKernel(
            source: """
                kernel vec4 displacedSample(sampler image, sampler field, vec3 band) {
                    vec2 d = sample(field, samplerCoord(field)).rg;
                    float t = clamp((destCoord().y - band.x) / band.y, 0.0, 1.0);
                    d.y += band.z * band.y * t * t * (3.0 - 2.0 * t);
                    return sample(image, samplerTransform(image, destCoord() - d));
                }
                """)
    }

    /// 원소마다 limit를 적용한 뒤 한 번 샘플링한다. 남는 원소가 없으면 입력을 그대로 돌려준다.
    /// 샘플링은 region(기본은 원소 영향 경계 합집합) 안에서만 하고 밖은 입력 픽셀을 그대로 둔다.
    /// 지도는 push·scale 경계 안에서만 그린다. region은 전체 extent와 비교하는 테스트가 넘긴다.
    func apply(
        _ primitives: [ShapePrimitive], to image: CIImage, extent: CGRect, limit: Double, region: CGRect? = nil
    ) throws -> CIImage {
        let effective = primitives.map { $0.limited(to: limit) }.filter { !$0.isIdentity }
        guard !effective.isEmpty else { return image }
        let bands = effective.filter(\.isBand)
        guard bands.count <= Self.maximumBands else { throw MellowError.renderFailed }
        guard let sampler else { throw MellowError.warpUnavailable }
        let patch = (region ?? Self.influenceBounds(effective, extent: extent)).intersection(extent).integral
        guard !patch.isEmpty else { return image }
        let mapped = effective.filter { !$0.isBand }
        let fieldRect = Self.fieldBounds(mapped, extent: extent).intersection(patch)
        let field =
            fieldRect.isEmpty
            ? Self.emptyField(at: patch.origin) : try displacementField(mapped, extent: fieldRect)
        let margin = effective.reduce(Self.roiPadding) { $0 + $1.maxDisplacement }
        let arguments: [Any] = [image.clampedToExtent(), field, Self.bandVector(bands.first)]
        let warped = sampler.apply(
            extent: patch,
            roiCallback: { index, rect in
                index == Self.imageArgumentIndex ? rect.insetBy(dx: -margin, dy: -margin) : rect
            },
            arguments: arguments)
        guard let warped else { throw MellowError.renderFailed }
        return Self.replacing(patch, of: image, with: warped).cropped(to: extent)
    }

    /// 원소들이 바꿀 수 있는 픽셀을 덮는 사각형을 extent 안 픽셀 경계로 맞춘다. limit를 적용한 원소를 받는다.
    /// push·scale은 중심 둘레 반지름 + 최대 이동 + ROI 여백, 띠는 시작 행 + 여유부터 띠 쪽 먼 가장자리까지 가로 전체다.
    static func influenceBounds(_ primitives: [ShapePrimitive], extent: CGRect) -> CGRect {
        let union = primitives.reduce(CGRect.null) { bounds, primitive in
            bounds.union(influence(of: primitive, extent: extent))
        }
        return union.intersection(extent).integral
    }

    /// 이동량 지도를 그릴 사각형. push·scale 경계의 합집합이고 띠는 넣지 않는다. 띠만 있으면 null.
    static func fieldBounds(_ primitives: [ShapePrimitive], extent: CGRect) -> CGRect {
        influenceBounds(primitives.filter { !$0.isBand }, extent: extent)
    }

    private static func influence(of primitive: ShapePrimitive, extent: CGRect) -> CGRect {
        let reach = primitive.maxDisplacement + roiPadding
        switch primitive {
        case .push(let center, _, let radius), .scale(let center, _, let radius):
            let half = radius + reach
            return CGRect(x: center.x - half, y: center.y - half, width: 2 * half, height: 2 * half)
        case .band(let yStart, let yEnd, _):
            // 시작 행 반대쪽은 이동이 0이라 빼고, 시작 행부터 띠 쪽 먼 가장자리까지만 움직인다.
            let top = yEnd < yStart ? yStart + reach : extent.maxY
            let bottom = yEnd < yStart ? extent.minY : yStart - reach
            return CGRect(x: extent.minX, y: bottom, width: extent.width, height: top - bottom)
        }
    }

    /// region 안은 patch, 밖은 image. 마스크로 고르므로 알파가 있어도 둘이 섞이지 않고 밖은 입력 값 그대로다.
    /// 샘플링 커널은 출력 extent 밖에서도 값을 내므로(투명이 아니다) patch를 잘라 얹는 합성은 쓰지 않는다.
    private static func replacing(_ region: CGRect, of image: CIImage, with patch: CIImage) -> CIImage {
        let mask = CIImage(color: .white).cropped(to: region)
        return patch.applyingFilter(
            "CIBlendWithMask", parameters: [kCIInputBackgroundImageKey: image, kCIInputMaskImageKey: mask])
    }

    /// 띠만 있을 때의 지도. 한 픽셀 이동 0이고 그 밖은 투명이라 샘플링 커널이 이동 0으로 읽는다.
    private static func emptyField(at origin: CGPoint) -> CIImage {
        CIImage(color: CIColor(red: 0, green: 0, blue: 0, alpha: 1)).cropped(to: CGRect(origin: origin, size: emptyFieldSize))
    }

    /// 샘플링 커널의 띠 인자 (시작 행, 길이, 늘림).
    private static func bandVector(_ band: ShapePrimitive?) -> CIVector {
        guard case .band(let yStart, let yEnd, let stretch)? = band else { return noBand }
        return CIVector(x: yStart, y: yEnd - yStart, z: stretch)
    }

    /// push·scale 원소들의 이동량 합. 0에서 시작해 원소마다 색 커널 하나를 이어 붙인다. 띠는 건너뛴다.
    func displacementField(_ primitives: [ShapePrimitive], extent: CGRect) throws -> CIImage {
        var field = CIImage(color: CIColor(red: 0, green: 0, blue: 0, alpha: 1)).cropped(to: extent)
        for primitive in primitives where !primitive.isBand {
            field = try accumulate(primitive, onto: field, extent: extent)
        }
        return field
    }

    /// CPU 참조. 원소마다 limit를 적용한 이동량의 합(띠 포함).
    static func displacement(at point: CGPoint, of primitives: [ShapePrimitive], limit: Double) -> CGVector {
        primitives.reduce(CGVector.zero) { sum, primitive in
            let shift = primitive.limited(to: limit).displacement(at: point)
            return CGVector(dx: sum.dx + shift.dx, dy: sum.dy + shift.dy)
        }
    }

    private func accumulate(_ primitive: ShapePrimitive, onto field: CIImage, extent: CGRect) throws -> CIImage {
        let kernel: CIColorKernel?
        let arguments: [Any]
        switch primitive {
        case .push(let center, let vector, let radius):
            kernel = pushField
            arguments = [field, CIVector(x: center.x, y: center.y), CIVector(x: vector.dx, y: vector.dy), radius]
        case .scale(let center, let factor, let radius):
            kernel = scaleField
            arguments = [field, CIVector(x: center.x, y: center.y), factor, radius]
        case .band:
            return field
        }
        guard let kernel else { throw MellowError.warpUnavailable }
        guard let output = kernel.apply(extent: extent, arguments: arguments) else { throw MellowError.renderFailed }
        return output
    }
}
```

`emptyField`의 한 줄이 120자를 넘으면 `.cropped(to:)`를 다음 줄로 내린다. `bandField` 커널이 없어져 커널 언어 지원 중단 경고가 하나 줄어든다(허용 목록은 그대로).

- [ ] **Step 4: 통과 확인**

Run: `cd apple && swift test` → 모듈별 `Executed 40 · 179 · 30 · 4 · 26 tests`, 모두 `with 0 failures`(합 279). 기존 `testBandMovesMarkerBeyondBand`(띠 너머 −5.12px, 위쪽 그대로)와 `testPatchWarpMatchesFullExtentWarp`는 바꾸지 않고 통과해야 한다. lint 출력 없음.

- [ ] **Step 5: 커밋**

```bash
git add apple/Sources/MellowRendering/Domain/ShapePrimitive.swift apple/Sources/MellowRendering/Domain/DisplacementWarp.swift apple/Tests/MellowRenderingTests/DisplacementWarpTests.swift
git commit -m "feat(rendering): 다리 띠를 샘플링 커널에서 계산하고 양 끝을 부드럽게

띠는 이동량 지도에 그리지 않아 큰 사진에서 사진 크기 지도가 생기지 않고, 512px 넘는
이동도 반정밀도 계단이 없다. 패치는 띠 시작 행부터 먼 가장자리까지로 줄인다.
띠 안 이동은 smoothstep이라 골반·발목에서 꺾이지 않는다.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 4: 체형 이동 원소 — BodyShapeRig와 RenderTuning 체형 상수

**Files:**
- Create: `apple/Sources/MellowRendering/Domain/BodyShapeRig.swift`
- Modify: `apple/Sources/MellowRendering/API/RenderTuning.swift` (체형 상수, `bodyItemMaxShift(_:)`)
- Test: `apple/Tests/MellowRenderingTests/BodyShapeRigTests.swift`(새 파일)

**Interfaces:**
- Consumes: `BodySkeleton`(`init?(body:extent:tuning:)`, `point`, `torsoWidth`, `shoulderCenter`, `hipCenter`, `up`, `across`, `side(of:from:)`, `midpoint`, `lerp`)·`RenderingTestSupport.standingBox`·`standingBody`·`BodyGeometry.rotated`(Task 2), `ShapePrimitive`·`limited(to:)`·`isBand`(Task 3), `AdjustmentRange.bodyShape`(Task 1), `RenderingTestSupport.minimumJacobian`.
- Produces: `enum BodyShapeRig { static func primitives(body:adjustments:extent:tuning:) -> [ShapePrimitive] }`. `RenderTuning.bodyShapeMaxShift`·`bodyWaistMaxShift`·`bodyOverallMaxShift`·`bodyArmMaxShift`·`bodyThighMaxShift`·`bodyShoulderMaxShift`·`bodyNeckMaxShift`·`legLengthMaxStretch`, `RenderTuning.bodyItemMaxShift(_ key: BodyShapeKey) -> Double`.

설계 근거(스펙 5 표):

| 항목 | 원소(음수 기준) | 필요한 관절 | 개수 |
|---|---|---|---|
| legLength | `.band(엉덩이 중점 y, 보이는 발목 평균 y, 값 × 0.08)` | 두 엉덩이, 발목 하나 이상, 엉덩이가 발목보다 어깨 폭 × 0.5 이상 위 | 1 |
| waist | 같은 쪽 어깨~엉덩이 55% 점을 가로축 안쪽으로 | 두 엉덩이 | 2 |
| overall | 가슴(어깨~엉덩이 30%)·골반 바깥(엉덩이 + 0.12W)·허벅지 바깥(엉덩이~무릎 중점 + 0.2W)을 안쪽으로 | 두 엉덩이(+ 그쪽 무릎) | 6 |
| arms | 위팔·아래팔 중점에서 선분에 수직으로 반폭(0.12W·0.09W)만큼 떨어진 두 점을 선분 쪽으로(아래팔 이동은 75%) | 그 선분 양 끝 | 8 |
| thighs | 엉덩이~무릎 중점 양옆(0.2W)을 선분 쪽으로 | 같은 쪽 엉덩이·무릎 | 4 |
| shoulders | 각 어깨 관절을 가로축으로 바깥(+)·안쪽(−) | 두 어깨 | 2 |
| neck | 목 관절에서 위로 0.2W 점을 세로축으로 위(+)·아래(−) | 목 | 1 |

W는 어깨 폭(BodySkeleton.torsoWidth). push 이동 = 값 × min(항목 최대, `bodyShapeMaxShift`) × W. 반지름 = max(기본 반지름 × W, |이동| / `shapeDisplacementLimit`)이라 기본값(반지름 0.2~0.3W, 이동 ≤ 0.06W)에서도, 튜닝을 키워도 DisplacementWarp의 상한에 걸리지 않는다(C 이월 f). 좌우·안팎은 이름이 아니라 가로축 성분의 부호로 정한다. 띠는 사진 행 기준이라 몸이 기울어도 세로로만 늘린다. 시작값 근거(어깨 폭 40cm 기준)는 사람 확인 표와 `RenderTuning` 주석에 있다.

- [ ] **Step 1: 실패하는 테스트 작성**

`apple/Tests/MellowRenderingTests/BodyShapeRigTests.swift`:

```swift
import CoreImage
import MellowShared
import XCTest

@testable import MellowRendering

final class BodyShapeRigTests: XCTestCase {
    typealias Support = RenderingTestSupport
    typealias Push = (center: CGPoint, vector: CGVector, radius: CGFloat)

    private let extent = CGRect(x: 0, y: 0, width: 512, height: 512)
    private let tuning = RenderTuning()
    /// standingBox 사람의 어깨 폭(픽셀)과 몸 가운데 x.
    private let torsoWidth: CGFloat = 204.8
    private let midline: CGFloat = 256

    private func primitives(
        _ adjustments: BodyShapeAdjustments, body: BodyGeometry? = nil, tuning: RenderTuning? = nil
    ) -> [ShapePrimitive] {
        BodyShapeRig.primitives(
            body: body ?? Support.standingBody(in: Support.standingBox), adjustments: adjustments, extent: extent,
            tuning: tuning ?? self.tuning)
    }

    /// push 원소만 꺼낸다. push가 아닌 원소가 있으면 실패로 남긴다.
    private func pushes(_ primitives: [ShapePrimitive], file: StaticString = #filePath, line: UInt = #line) -> [Push] {
        primitives.compactMap { primitive in
            guard case .push(let center, let vector, let radius) = primitive else {
                XCTFail("push가 아니다: \(primitive)", file: file, line: line)
                return nil
            }
            return (center, vector, radius)
        }
    }

    private func distance(_ first: CGPoint, _ second: CGPoint) -> CGFloat {
        hypot(first.x - second.x, first.y - second.y)
    }

    func testWaistNegativePushesBothSidesTowardMidline() {
        let narrow = pushes(primitives(BodyShapeAdjustments(waist: -1)))
        XCTAssertEqual(narrow.count, 2)
        for push in narrow {
            let towardMidline: CGFloat = push.center.x < midline ? 1 : -1
            XCTAssertEqual(push.vector.dx, towardMidline * 0.06 * torsoWidth, accuracy: 1e-6, "어깨 폭 × 0.06만큼 중심선 쪽")
            XCTAssertEqual(push.vector.dy, 0, accuracy: 1e-9, "똑바로 선 사람은 가로로만")
            XCTAssertEqual(push.center.y, (0.8 + (0.5 - 0.8) * 0.55) * 512, accuracy: 1e-6, "어깨~엉덩이 55% 높이")
        }
        let rightSide = narrow.map(\.center.x).max() ?? 0
        XCTAssertEqual(rightSide, (0.1 + 0.8 * (0.75 + (0.62 - 0.75) * 0.55)) * 512, accuracy: 1e-6)
        let wide = pushes(primitives(BodyShapeAdjustments(waist: 1)))
        XCTAssertEqual(wide.count, 2)
        for (inward, outward) in zip(narrow, wide) {
            XCTAssertEqual(inward.vector.dx, -outward.vector.dx, accuracy: 1e-9, "+1은 반대 방향")
        }
    }

    func testOverallPushesThreeHeightsOnEachSideTowardMidline() {
        let result = pushes(primitives(BodyShapeAdjustments(overall: -1)))
        XCTAssertEqual(result.count, 6, "가슴·골반·허벅지 × 양옆")
        for push in result {
            let towardMidline: CGFloat = push.center.x < midline ? 1 : -1
            XCTAssertEqual(push.vector.dx, towardMidline * 0.035 * torsoWidth, accuracy: 1e-6)
            XCTAssertEqual(push.vector.dy, 0, accuracy: 1e-9)
        }
        let heights = Set(result.map { ($0.center.y * 10).rounded() / 10 })
        XCTAssertEqual(heights.count, 3, "높이 세 곳")
    }

    func testArmsAndThighsPushTowardTheirSegments() throws {
        let body = Support.standingBody(in: Support.standingBox)
        let skeleton = try XCTUnwrap(BodySkeleton(body: body, extent: extent, tuning: tuning))
        let cases: [(BodyShapeAdjustments, [(BodyJoint, BodyJoint)])] = [
            (
                BodyShapeAdjustments(arms: -1),
                [
                    (.leftShoulder, .leftElbow), (.leftElbow, .leftWrist), (.rightShoulder, .rightElbow),
                    (.rightElbow, .rightWrist),
                ]
            ),
            (BodyShapeAdjustments(thighs: -1), [(.leftHip, .leftKnee), (.rightHip, .rightKnee)]),
        ]
        for (adjustments, segments) in cases {
            let middles = try segments.map { start, end in
                BodySkeleton.midpoint(try XCTUnwrap(skeleton.point(start)), try XCTUnwrap(skeleton.point(end)))
            }
            let result = pushes(primitives(adjustments, body: body))
            XCTAssertEqual(result.count, segments.count * 2, "선분마다 양옆 두 점")
            for push in result {
                let nearest = try XCTUnwrap(middles.min { distance($0, push.center) < distance($1, push.center) })
                let toward = CGVector(dx: nearest.x - push.center.x, dy: nearest.y - push.center.y)
                XCTAssertGreaterThan(push.vector.dx * toward.dx + push.vector.dy * toward.dy, 0, "선분 쪽으로 민다")
            }
        }
    }

    func testShouldersMoveOutwardAndNeckMovesUp() throws {
        let wider = pushes(primitives(BodyShapeAdjustments(shoulders: 1)))
        XCTAssertEqual(wider.count, 2)
        for push in wider {
            let outward: CGFloat = push.center.x > midline ? 1 : -1
            XCTAssertEqual(push.vector.dx, outward * 0.04 * torsoWidth, accuracy: 1e-6, "양수는 바깥으로")
            XCTAssertEqual(push.center.y, 0.8 * 512, accuracy: 1e-6, "어깨 관절 자리")
        }
        let narrower = pushes(primitives(BodyShapeAdjustments(shoulders: -1)))
        for (out, inward) in zip(wider, narrower) {
            XCTAssertEqual(out.vector.dx, -inward.vector.dx, accuracy: 1e-9)
        }
        let longer = try XCTUnwrap(pushes(primitives(BodyShapeAdjustments(neck: 1))).first)
        XCTAssertEqual(longer.vector.dy, 0.03 * torsoWidth, accuracy: 1e-6, "목은 위로")
        XCTAssertEqual(longer.vector.dx, 0, accuracy: 1e-9)
        XCTAssertEqual(longer.center.y, 0.82 * 512 + 0.2 * torsoWidth, accuracy: 1e-6, "목 관절 위 목~턱 사이")
        let shorter = try XCTUnwrap(pushes(primitives(BodyShapeAdjustments(neck: -1))).first)
        XCTAssertLessThan(shorter.vector.dy, 0, "음수는 아래로")
    }

    func testLegLengthMakesOneBandFromHipsToAnkles() throws {
        let result = primitives(BodyShapeAdjustments(legLength: 0.5))
        XCTAssertEqual(result.count, 1)
        guard case .band(let start, let end, let stretch) = try XCTUnwrap(result.first) else {
            return XCTFail("띠가 아니다")
        }
        XCTAssertEqual(start, 256, accuracy: 1e-6, "두 엉덩이 중점 높이")
        XCTAssertEqual(end, 25.6, accuracy: 1e-6, "발목 높이")
        XCTAssertEqual(stretch, 0.04, accuracy: 1e-9, "값 × 0.08")
        let oneAnkle = Support.standingBody(in: Support.standingBox, omitting: [.leftAnkle])
        XCTAssertEqual(primitives(BodyShapeAdjustments(legLength: 1), body: oneAnkle).count, 1, "발목 하나로도 만든다")
        let pivot = NormalizedPoint(x: 0.5, y: 0.5)
        let upsideDown = Support.standingBody(in: Support.standingBox).rotated(by: .pi, about: pivot)
        XCTAssertTrue(primitives(BodyShapeAdjustments(legLength: 1), body: upsideDown).isEmpty, "엉덩이가 발목보다 아래면 건너뛴다")
        let lying = Support.standingBody(in: Support.standingBox).rotated(by: .pi / 2, about: pivot)
        XCTAssertTrue(primitives(BodyShapeAdjustments(legLength: 1), body: lying).isEmpty, "누운 사람은 건너뛴다")
    }

    func testMissingOrLowConfidenceJointsSkipOnlyTheirItems() {
        let all = BodyShapeAdjustments(legLength: 1, waist: -1, overall: -1, arms: -1, thighs: -1, shoulders: 1, neck: 1)
        let full = Support.standingBody(in: Support.standingBox)
        XCTAssertEqual(primitives(all, body: full).count, 1 + 2 + 6 + 8 + 4 + 2 + 1)
        let upperBody = Support.standingBody(
            in: Support.standingBox,
            omitting: [.leftHip, .rightHip, .leftKnee, .rightKnee, .leftAnkle, .rightAnkle, .root])
        XCTAssertEqual(primitives(all, body: upperBody).count, 8 + 2 + 1, "엉덩이가 없으면 팔·어깨·목만 남는다")
        for key in [BodyShapeKey.legLength, .waist, .overall, .thighs] {
            var single = BodyShapeAdjustments()
            single[key] = key == .legLength ? 1 : -1
            XCTAssertTrue(primitives(single, body: upperBody).isEmpty, "\(key)")
        }
        var faintKnee = full
        faintKnee.confidence[.leftKnee] = 0.29
        XCTAssertEqual(primitives(BodyShapeAdjustments(thighs: -1), body: faintKnee).count, 2, "신뢰도 낮은 무릎 쪽 허벅지만 빠진다")
        XCTAssertEqual(primitives(BodyShapeAdjustments(overall: -1), body: faintKnee).count, 5, "그쪽 허벅지 높이만 빠진다")
        let noElbows = Support.standingBody(in: Support.standingBox, omitting: [.leftElbow, .rightElbow])
        XCTAssertTrue(primitives(BodyShapeAdjustments(arms: -1), body: noElbows).isEmpty)
        let noNeck = Support.standingBody(in: Support.standingBox, omitting: [.neck])
        XCTAssertTrue(primitives(BodyShapeAdjustments(neck: 1), body: noNeck).isEmpty)
        let oneShoulder = Support.standingBody(in: Support.standingBox, omitting: [.leftShoulder])
        XCTAssertTrue(primitives(all, body: oneShoulder).isEmpty, "어깨 폭이 없으면 모든 항목을 건너뛴다")
    }

    func testZeroNaNAndOutOfRangeValues() {
        XCTAssertTrue(primitives(BodyShapeAdjustments()).isEmpty)
        XCTAssertTrue(primitives(BodyShapeAdjustments(waist: .nan, neck: .infinity)).isEmpty, "유한하지 않은 값은 0")
        XCTAssertEqual(
            primitives(BodyShapeAdjustments(waist: -3, arms: 7)), primitives(BodyShapeAdjustments(waist: -1, arms: 1)))
        XCTAssertTrue(primitives(BodyShapeAdjustments(legLength: -0.5)).isEmpty, "다리 길게는 0 아래가 없다")
        XCTAssertEqual(primitives(BodyShapeAdjustments(legLength: 4)), primitives(BodyShapeAdjustments(legLength: 1)))
    }

    func testBodyPushesAreNeverCappedByDisplacementLimit() {
        let limit = tuning.shapeDisplacementLimit
        for sign in [-1.0, 1.0] {
            let extreme = BodyShapeAdjustments(
                legLength: 1, waist: sign, overall: sign, arms: sign, thighs: sign, shoulders: sign, neck: sign)
            for primitive in primitives(extreme) {
                XCTAssertEqual(primitive.limited(to: limit), primitive, "얼굴과 같은 상한이 체형 이동을 줄이지 않는다: \(primitive)")
            }
        }
        var strong = RenderTuning()
        strong.bodyShapeMaxShift = 0.2
        strong.bodyWaistMaxShift = 0.2
        for push in pushes(primitives(BodyShapeAdjustments(waist: -1), tuning: strong)) {
            let primitive = ShapePrimitive.push(center: push.center, vector: push.vector, radius: push.radius)
            XCTAssertEqual(primitive.limited(to: limit), primitive, "튜닝을 키우면 반지름도 따라 커진다")
            XCTAssertEqual(abs(push.vector.dx), 0.2 * torsoWidth, accuracy: 1e-6)
        }
        var capped = RenderTuning()
        capped.bodyWaistMaxShift = 0.5
        let shifts = pushes(primitives(BodyShapeAdjustments(waist: -1), tuning: capped)).map { abs($0.vector.dx) }
        XCTAssertEqual(shifts.max() ?? 0, 0.06 * torsoWidth, accuracy: 1e-6, "항목 최대는 bodyShapeMaxShift(0.06)를 넘지 않는다")
    }

    func testTiltedBodyPushesFollowTorsoAxis() throws {
        let angle = Double.pi / 6
        let body = Support.standingBody(in: Support.standingBox).rotated(
            by: angle, about: NormalizedPoint(x: 0.5, y: 0.5))
        let waist = pushes(primitives(BodyShapeAdjustments(waist: -1), body: body))
        XCTAssertEqual(waist.count, 2)
        for push in waist {
            let length = hypot(push.vector.dx, push.vector.dy)
            XCTAssertEqual(length, 0.06 * torsoWidth, accuracy: 1e-6)
            let alongAcross = push.vector.dx * cos(angle) + push.vector.dy * sin(angle)
            XCTAssertEqual(abs(alongAcross), length, accuracy: 1e-6, "몸통 가로축(cos 30°, sin 30°)과 평행")
        }
        let neck = try XCTUnwrap(pushes(primitives(BodyShapeAdjustments(neck: 1), body: body)).first)
        XCTAssertEqual(neck.vector.dx, -sin(angle) * 0.03 * torsoWidth, accuracy: 1e-6, "목은 몸통 위쪽으로")
        XCTAssertEqual(neck.vector.dy, cos(angle) * 0.03 * torsoWidth, accuracy: 1e-6)
    }

    func testCombinedEditsDoNotFold() {
        let limit = tuning.shapeDisplacementLimit
        var worst = CGFloat.infinity
        for sign in [-1.0, 1.0] {
            for key in BodyShapeKey.allCases where key != .legLength {
                var single = BodyShapeAdjustments()
                single[key] = sign
                worst = min(worst, Support.minimumJacobian(of: primitives(single), limit: limit, in: extent))
            }
            let all = BodyShapeAdjustments(
                legLength: 1, waist: sign, overall: sign, arms: sign, thighs: sign, shoulders: sign, neck: sign)
            worst = min(worst, Support.minimumJacobian(of: primitives(all), limit: limit, in: extent))
        }
        XCTAssertGreaterThan(worst, 0.2, "겹치는 체형 원소가 이미지를 접지 않는다(최소 야코비안 \(worst))")
    }
}
```

- [ ] **Step 2: 실패 확인**

Run: `cd apple && swift test --filter BodyShapeRigTests` → 컴파일 실패(`cannot find 'BodyShapeRig' in scope`, `value of type 'RenderTuning' has no member 'bodyShapeMaxShift'`).

- [ ] **Step 3: 구현**

`RenderTuning.swift`: `bodyJointMinConfidence` 아래에 추가:

```swift
    /// 체형 push 항목 하나의 이동 상한. 어깨 폭 비율(스펙 0.06, "몸 폭의 6% 이내"). 항목별 최대가 이보다 크면 이 값으로 자른다.
    public var bodyShapeMaxShift: Double = 0.06
    /// 허리 ±1에서 한쪽 옆구리를 미는 양. 어깨 폭 40cm면 2.4cm라 허리 폭(약 28cm)이 −1에서 약 17% 줄어든다.
    public var bodyWaistMaxShift: Double = 0.06
    /// 몸 전체. 가슴·골반·허벅지 바깥 세 곳을 각각 어깨 폭의 3.5%(약 1.4cm).
    public var bodyOverallMaxShift: Double = 0.035
    /// 팔. 위팔 양옆을 각각 어깨 폭의 2%(약 0.8cm, 위팔 폭 약 9.6cm의 17%). 아래팔은 그 75%.
    public var bodyArmMaxShift: Double = 0.02
    /// 허벅지. 양옆을 각각 어깨 폭의 3.5%(약 1.4cm, 허벅지 폭 약 16cm의 17%).
    public var bodyThighMaxShift: Double = 0.035
    /// 어깨. 각 어깨 관절을 어깨 폭의 4%(약 1.6cm)라 어깨 폭이 ±8% 바뀐다.
    public var bodyShoulderMaxShift: Double = 0.04
    /// 목. 목~턱 사이 위쪽을 어깨 폭의 3%(약 1.2cm) 올리거나 내린다.
    public var bodyNeckMaxShift: Double = 0.03
    /// 다리 길게 1의 띠 늘림 비율(스펙 0.08). 골반~발목이 8% 길어지고 발 아래는 그만큼 사진 밖으로 밀린다.
    public var legLengthMaxStretch: Double = 0.08

    /// 체형 항목별 최대. legLength는 띠 늘림 비율, 나머지는 어깨 폭 비율의 push 이동이다.
    public func bodyItemMaxShift(_ key: BodyShapeKey) -> Double {
        switch key {
        case .legLength: return legLengthMaxStretch
        case .waist: return bodyWaistMaxShift
        case .overall: return bodyOverallMaxShift
        case .arms: return bodyArmMaxShift
        case .thighs: return bodyThighMaxShift
        case .shoulders: return bodyShoulderMaxShift
        case .neck: return bodyNeckMaxShift
        }
    }
```

`apple/Sources/MellowRendering/Domain/BodyShapeRig.swift`:

```swift
import CoreImage
import MellowShared

/// 체형 슬라이더 7개를 이동 원소로 바꾼다(스펙 5). 좌표·길이는 extent 픽셀, 몸통 축과 어깨 폭은 BodySkeleton이 정한다.
/// 값은 여기서 AdjustmentRange로 자른다. 프리셋·일괄 적용 값은 편집 규칙의 클램프를 거치지 않기 때문이다.
/// 유한하지 않은 값은 0으로 본다. 음수는 가늘게·좁게·짧게, 양수는 넓게·길게다. 다리 길게만 0…1이고 띠 하나를 만든다.
/// push 이동 = 값 × min(항목 최대, bodyShapeMaxShift) × 어깨 폭. 반지름은 이동 / shapeDisplacementLimit 이상이라
/// DisplacementWarp가 얼굴 원소와 같은 상한을 써도 체형 이동이 몰래 줄지 않는다.
/// 필요한 관절이 없는 항목(또는 높이·팔다리 한쪽)만 건너뛴다.
enum BodyShapeRig {
    /// 팔다리 선분 하나. 양 끝 관절, 반폭(어깨 폭 비율), 이동 비율.
    private struct Limb {
        let start: BodyJoint
        let end: BodyJoint
        let halfWidth: CGFloat
        let shiftRatio: CGFloat
    }

    /// 원소를 만들 때 함께 쓰는 사람과 이동 상한.
    private struct Builder {
        let skeleton: BodySkeleton
        let limit: CGFloat

        var width: CGFloat { skeleton.torsoWidth }

        /// center를 direction(단위 벡터) × shift만큼 민다. 반지름은 base × 어깨 폭과 |shift| / limit 중 큰 값이다.
        func push(_ center: CGPoint, _ direction: CGVector, shift: CGFloat, radius base: CGFloat) -> ShapePrimitive {
            let radius = max(base * width, abs(shift) / limit)
            let vector = CGVector(dx: direction.dx * shift, dy: direction.dy * shift)
            return .push(center: center, vector: vector, radius: radius)
        }

        /// center에서 본 point 쪽 가로축 방향(바깥). 가로축 성분이 0이면 nil.
        func outward(_ point: CGPoint, from center: CGPoint) -> CGVector? {
            let side = skeleton.side(of: point, from: center)
            guard side != 0 else { return nil }
            return CGVector(dx: skeleton.across.dx * side, dy: skeleton.across.dy * side)
        }
    }

    /// 허리 높이. 어깨에서 엉덩이까지의 비율(스펙 55%).
    private static let waistLevel: CGFloat = 0.55
    /// 몸 전체의 가슴 높이. 어깨에서 엉덩이까지의 비율.
    private static let chestLevel: CGFloat = 0.3
    /// 엉덩이 관절에서 골반 바깥 윤곽까지. 어깨 폭 비율. Vision 엉덩이 점은 윤곽보다 안쪽이다.
    private static let hipOutlineOffset: CGFloat = 0.12
    /// 허벅지 반폭. 어깨 폭 비율(허벅지 폭은 어깨 폭의 40% 안팎).
    private static let thighHalfWidth: CGFloat = 0.2
    /// 위팔·아래팔 반폭. 어깨 폭 비율.
    private static let upperArmHalfWidth: CGFloat = 0.12
    private static let forearmHalfWidth: CGFloat = 0.09
    /// 위팔·허벅지는 항목 이동 그대로, 아래팔은 75%(아래팔이 가늘어 같은 이동이면 더 많이 줄어든다).
    private static let fullShift: CGFloat = 1
    private static let forearmShiftRatio: CGFloat = 0.75
    /// push 기본 반지름. 어깨 폭 비율. 모두 기본 이동(≤ 0.06)의 4배 이상이다.
    private static let torsoRadius: CGFloat = 0.3
    private static let armRadius: CGFloat = 0.2
    private static let thighRadius: CGFloat = 0.3
    private static let shoulderRadius: CGFloat = 0.3
    private static let neckRadius: CGFloat = 0.3
    /// 목 push 중심. 목 관절(목 아래끝)에서 몸통 위쪽으로 어깨 폭 비율. 목~턱 사이 위쪽이다.
    private static let neckRise: CGFloat = 0.2
    /// 엉덩이가 발목보다 이만큼(어깨 폭 비율) 위에 있어야 다리 띠를 만든다. 누운 사람·거꾸로 된 사진은 건너뛴다.
    private static let minimumLegSpan: CGFloat = 0.5
    /// 이보다 짧은 팔다리 선분(픽셀)은 방향을 정할 수 없어 건너뛴다.
    private static let minimumSegmentLength: CGFloat = 1

    private static let armLimbs = [
        Limb(start: .leftShoulder, end: .leftElbow, halfWidth: upperArmHalfWidth, shiftRatio: fullShift),
        Limb(start: .leftElbow, end: .leftWrist, halfWidth: forearmHalfWidth, shiftRatio: forearmShiftRatio),
        Limb(start: .rightShoulder, end: .rightElbow, halfWidth: upperArmHalfWidth, shiftRatio: fullShift),
        Limb(start: .rightElbow, end: .rightWrist, halfWidth: forearmHalfWidth, shiftRatio: forearmShiftRatio),
    ]
    private static let thighLimbs = [
        Limb(start: .leftHip, end: .leftKnee, halfWidth: thighHalfWidth, shiftRatio: fullShift),
        Limb(start: .rightHip, end: .rightKnee, halfWidth: thighHalfWidth, shiftRatio: fullShift),
    ]

    static func primitives(
        body: BodyGeometry, adjustments: BodyShapeAdjustments, extent: CGRect, tuning: RenderTuning
    ) -> [ShapePrimitive] {
        guard adjustments.hasEffect, let skeleton = BodySkeleton(body: body, extent: extent, tuning: tuning) else {
            return []
        }
        let rig = Builder(skeleton: skeleton, limit: CGFloat(tuning.shapeDisplacementLimit))
        var result: [ShapePrimitive] = []
        for key in BodyShapeKey.allCases {
            let raw = adjustments[key]
            let value = AdjustmentRange.clamped(raw.isFinite ? raw : 0, to: AdjustmentRange.bodyShape(key))
            guard value != 0 else { continue }
            result += primitives(for: key, value: CGFloat(value), rig: rig, tuning: tuning)
        }
        return result
    }

    private static func primitives(
        for key: BodyShapeKey, value: CGFloat, rig: Builder, tuning: RenderTuning
    ) -> [ShapePrimitive] {
        let maximum = CGFloat(min(tuning.bodyItemMaxShift(key), tuning.bodyShapeMaxShift))
        let shift = value * maximum * rig.width
        switch key {
        case .legLength: return legLength(rig.skeleton, stretch: value * CGFloat(tuning.bodyItemMaxShift(key)))
        case .waist: return waist(rig, shift: shift)
        case .overall: return overall(rig, shift: shift)
        case .arms: return limbs(rig, armLimbs, shift: shift, radius: armRadius)
        case .thighs: return limbs(rig, thighLimbs, shift: shift, radius: thighRadius)
        case .shoulders: return shoulders(rig, shift: shift)
        case .neck: return neck(rig, shift: shift)
        }
    }

    /// 두 엉덩이 중점에서 보이는 발목 평균까지 가로 띠를 아래로 늘린다. 엉덩이가 발목보다 충분히 위에 있어야 한다.
    private static func legLength(_ skeleton: BodySkeleton, stretch: CGFloat) -> [ShapePrimitive] {
        let ankles = [BodyJoint.leftAnkle, .rightAnkle].compactMap(skeleton.point)
        guard let hip = skeleton.hipCenter, !ankles.isEmpty else { return [] }
        let ankleY = ankles.map(\.y).reduce(0, +) / CGFloat(ankles.count)
        guard hip.y - ankleY >= minimumLegSpan * skeleton.torsoWidth else { return [] }
        return [.band(yStart: hip.y, yEnd: ankleY, stretch: stretch)]
    }

    /// 같은 쪽 어깨~엉덩이 55% 점을 가로축 안쪽(음수)이나 바깥으로 민다. 두 엉덩이가 있어야 한다.
    private static func waist(_ rig: Builder, shift: CGFloat) -> [ShapePrimitive] {
        guard let hipCenter = rig.skeleton.hipCenter else { return [] }
        let middle = BodySkeleton.lerp(rig.skeleton.shoulderCenter, hipCenter, waistLevel)
        return torsoSides(rig, level: waistLevel).compactMap { point in
            guard let direction = rig.outward(point, from: middle) else { return nil }
            return rig.push(point, direction, shift: shift, radius: torsoRadius)
        }
    }

    /// 가슴·골반 바깥·허벅지 바깥 세 높이의 양옆을 민다. 두 엉덩이가 있어야 하고 허벅지 높이는 그쪽 무릎이 있어야 한다.
    private static func overall(_ rig: Builder, shift: CGFloat) -> [ShapePrimitive] {
        guard let hipCenter = rig.skeleton.hipCenter else { return [] }
        let chestMiddle = BodySkeleton.lerp(rig.skeleton.shoulderCenter, hipCenter, chestLevel)
        var result: [ShapePrimitive] = torsoSides(rig, level: chestLevel).compactMap { point in
            guard let direction = rig.outward(point, from: chestMiddle) else { return nil }
            return rig.push(point, direction, shift: shift, radius: torsoRadius)
        }
        for (hipJoint, kneeJoint) in [(BodyJoint.leftHip, BodyJoint.leftKnee), (.rightHip, .rightKnee)] {
            guard let hip = rig.skeleton.point(hipJoint), let direction = rig.outward(hip, from: hipCenter) else {
                continue
            }
            let hipOutline = offset(hip, direction, hipOutlineOffset * rig.width)
            result.append(rig.push(hipOutline, direction, shift: shift, radius: torsoRadius))
            guard let knee = rig.skeleton.point(kneeJoint) else { continue }
            let thighOutline = offset(BodySkeleton.midpoint(hip, knee), direction, thighHalfWidth * rig.width)
            result.append(rig.push(thighOutline, direction, shift: shift, radius: torsoRadius))
        }
        return result
    }

    /// 선분 가운데에서 수직으로 반폭만큼 떨어진 양옆 두 점을 선분 쪽(음수)이나 바깥으로 민다.
    private static func limbs(_ rig: Builder, _ limbs: [Limb], shift: CGFloat, radius: CGFloat) -> [ShapePrimitive] {
        limbs.flatMap { limb -> [ShapePrimitive] in
            guard let start = rig.skeleton.point(limb.start), let end = rig.skeleton.point(limb.end) else { return [] }
            let length = hypot(end.x - start.x, end.y - start.y)
            guard length >= minimumSegmentLength else { return [] }
            let normal = CGVector(dx: -(end.y - start.y) / length, dy: (end.x - start.x) / length)
            let middle = BodySkeleton.midpoint(start, end)
            return [CGFloat(1), -1].map { sign in
                let direction = CGVector(dx: normal.dx * sign, dy: normal.dy * sign)
                let center = offset(middle, direction, limb.halfWidth * rig.width)
                return rig.push(center, direction, shift: shift * limb.shiftRatio, radius: radius)
            }
        }
    }

    /// 각 어깨 관절을 가로축 바깥(양수)이나 안쪽으로 민다.
    private static func shoulders(_ rig: Builder, shift: CGFloat) -> [ShapePrimitive] {
        [BodyJoint.leftShoulder, .rightShoulder].compactMap { joint in
            guard let shoulder = rig.skeleton.point(joint),
                let direction = rig.outward(shoulder, from: rig.skeleton.shoulderCenter)
            else { return nil }
            return rig.push(shoulder, direction, shift: shift, radius: shoulderRadius)
        }
    }

    /// 목 관절에서 위로 어깨 폭 × 0.2 점(목~턱 사이 위쪽)을 몸통 위쪽(양수, 목이 길어짐)이나 아래로 민다.
    private static func neck(_ rig: Builder, shift: CGFloat) -> [ShapePrimitive] {
        guard let neck = rig.skeleton.point(.neck) else { return [] }
        let center = offset(neck, rig.skeleton.up, neckRise * rig.width)
        return [rig.push(center, rig.skeleton.up, shift: shift, radius: neckRadius)]
    }

    /// 같은 쪽 어깨와 엉덩이 사이 level 높이의 점. 엉덩이가 없는 쪽은 빠진다.
    private static func torsoSides(_ rig: Builder, level: CGFloat) -> [CGPoint] {
        [(BodyJoint.leftShoulder, BodyJoint.leftHip), (.rightShoulder, .rightHip)].compactMap { shoulder, hip in
            guard let top = rig.skeleton.point(shoulder), let bottom = rig.skeleton.point(hip) else { return nil }
            return BodySkeleton.lerp(top, bottom, level)
        }
    }

    private static func offset(_ point: CGPoint, _ direction: CGVector, _ distance: CGFloat) -> CGPoint {
        CGPoint(x: point.x + direction.dx * distance, y: point.y + direction.dy * distance)
    }
}
```

`testCombinedEditsDoNotFold`가 0.2 이하로 실패하면 반지름이 아니라 해당 항목 최대(`RenderTuning`)를 낮추고, 그 주석과 사람 확인 표의 시작 강도를 같은 커밋에서 고친다(CLAUDE.md 규칙 3). 측정한 최소 야코비안을 보고에 적는다.

- [ ] **Step 4: 통과 확인**

Run: `cd apple && swift test` → 모듈별 `Executed 40 · 189 · 30 · 4 · 26 tests`, 모두 `with 0 failures`(합 289). lint 출력 없음.

- [ ] **Step 5: 커밋**

```bash
git add apple/Sources/MellowRendering/Domain/BodyShapeRig.swift apple/Sources/MellowRendering/API/RenderTuning.swift apple/Tests/MellowRenderingTests/BodyShapeRigTests.swift
git commit -m "feat(rendering): 체형 슬라이더 7개를 이동 원소로 바꾸는 BodyShapeRig

어깨 폭 기준으로 허리·몸 전체·팔·허벅지·어깨·목 push와 다리 길게 띠를 만든다.
필요한 관절이 없는 항목만 건너뛰고, push 반지름을 이동 / 상한 이상으로 둬 몰래 줄지 않는다.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 5: 변형 단계 연결 — ShapeWarpStage.bodyPrimitives, 체형 분석 실패 시 건너뛰기

**Files:**
- Modify: `apple/Sources/MellowRendering/Domain/ShapeWarpStage.swift`
- Test: `apple/Tests/MellowRenderingTests/ShapeWarpStageTests.swift`, `apple/Tests/MellowRenderingTests/PhotoPipelineTests.swift`

**Interfaces:**
- Consumes: `RenderContext.bodies`·`PhotoAnalysis(…bodies:…)`·`StubBodyAnalyzer`·`standingBody`(Task 2), `DisplacementWarp`(Task 3), `BodyShapeRig.primitives(body:adjustments:extent:tuning:)`(Task 4), `PhotoPipelineTests.writeStripesPNG()`(D).
- Produces: `ShapeWarpStage.bodyPrimitives(in:)`이 `context.bodies.first`의 체형 원소를 돌려준다. 단계 이름·순서는 그대로.

설계 근거: 체형은 가장 큰 사람 한 명(스펙 5, `bodies.first`). 관절이 없거나 체형 분석이 실패했거나 준비 전이면 `bodies`가 비어 체형 원소만 빠지고 얼굴 원소는 그대로 한 번에 샘플링된다(스펙 1.4: 해당 단계만 건너뜀, 오류 아님). `PhotoPipeline.renderOriginal`은 얼굴 의존 레시피만 거절하므로 체형 값은 저장을 막지 않는다.

- [ ] **Step 1: 실패하는 테스트 작성**

`ShapeWarpStageTests.swift`:

1. `context(_:faces:targetFace:)` 아래에 도우미를 더한다:

```swift
    private func bodyContext(
        _ body: BodyShapeAdjustments, bodies: [BodyGeometry], face: FaceShapeAdjustments = FaceShapeAdjustments(),
        faces: [FaceGeometry] = []
    ) -> RenderContext {
        var recipe = EditRecipe()
        recipe.body = body
        recipe.portrait.face = face
        return RenderContext(
            extent: extent, recipe: recipe, analysis: PhotoAnalysis(faces: faces, bodies: bodies), tuning: tuning)
    }
```

2. `testBodyPrimitivesAreEmptyUntilBodyStage`를 지우고 그 자리에 다음 네 테스트를 넣는다:

```swift
    func testLegLengthMovesMarkerBelowHipsDownAndKeepsRowsAboveHips() throws {
        let body = Support.standingBody(in: Support.standingBox)
        let knee = CGPoint(x: 200, y: 120)
        let chest = CGPoint(x: 256, y: 400)
        let input = Support.markers([knee, chest], extent: extent)
        let renderContext = bodyContext(BodyShapeAdjustments(legLength: 1), bodies: [body])
        let primitives = ShapeWarpStage().bodyPrimitives(in: renderContext)
        let expected = Support.expectedPosition(of: knee, primitives: primitives, limit: tuning.shapeDisplacementLimit)
        let before = try Support.grid(input)
        let after = try Support.grid(ShapeWarpStage().apply(input, in: renderContext))
        let original = try XCTUnwrap(Support.markerCentroid(before, near: knee))
        let moved = try XCTUnwrap(Support.markerCentroid(after, near: expected))
        XCTAssertLessThan(moved.y - original.y, -4, "띠 안 무릎 표식이 아래로")
        XCTAssertEqual(moved.y - original.y, expected.y - knee.y, accuracy: 0.75, "rig가 예측한 만큼")
        XCTAssertEqual(moved.x, original.x, accuracy: 0.25, "세로로만")
        // 엉덩이 256 + 띠 이동 18.4 + 여백 2 위쪽 행은 패치 밖이라 입력 바이트 그대로다.
        var changedAbove = 0
        for y in 280..<SyntheticFace.size {
            for x in 0..<SyntheticFace.size where after.rgba(CGPoint(x: x, y: y)) != before.rgba(CGPoint(x: x, y: y)) {
                changedAbove += 1
            }
        }
        XCTAssertEqual(changedAbove, 0, "엉덩이 위(가슴 표식 포함)는 그대로")
    }

    func testOnlyLargestBodyIsReshaped() throws {
        let large = Support.standingBody(in: NormalizedRect(x: 0, y: 0, width: 0.5, height: 1))
        let small = Support.standingBody(in: NormalizedRect(x: 0.6, y: 0.3, width: 0.3, height: 0.5))
        func waistSide(of body: BodyGeometry) throws -> CGPoint {
            let primitives = BodyShapeRig.primitives(
                body: body, adjustments: BodyShapeAdjustments(waist: -1), extent: extent, tuning: tuning)
            let centers = primitives.compactMap { primitive -> CGPoint? in
                guard case .push(let center, _, _) = primitive else { return nil }
                return center
            }
            return try XCTUnwrap(centers.first, "허리 원소는 push다")
        }
        let largeSide = try waistSide(of: large)
        let smallSide = try waistSide(of: small)
        let input = Support.markers([largeSide, smallSide], extent: extent)
        let before = try Support.grid(input)
        let renderContext = bodyContext(BodyShapeAdjustments(waist: -1), bodies: [large, small])
        let after = try Support.grid(ShapeWarpStage().apply(input, in: renderContext))
        let movedLarge = try XCTUnwrap(Support.markerCentroid(after, near: largeSide))
        let originalLarge = try XCTUnwrap(Support.markerCentroid(before, near: largeSide))
        let stayed = try XCTUnwrap(Support.markerCentroid(after, near: smallSide))
        let originalSmall = try XCTUnwrap(Support.markerCentroid(before, near: smallSide))
        XCTAssertGreaterThan(abs(movedLarge.x - originalLarge.x), 3, "가장 큰 사람의 허리는 바뀐다")
        XCTAssertEqual(stayed.x, originalSmall.x, accuracy: 0.25, "다른 사람은 그대로")
        XCTAssertEqual(stayed.y, originalSmall.y, accuracy: 0.25)
    }

    func testFaceAndBodyEditsWarpInOneSampling() throws {
        let face = SyntheticFace.make().face
        let body = Support.standingBody(in: Support.standingBox)
        let contour = try contourPoint(1, of: face)
        let shoulder = CGPoint(x: (0.1 + 0.8 * 0.75) * 512, y: 0.8 * 512)
        let renderContext = bodyContext(
            BodyShapeAdjustments(shoulders: 1), bodies: [body], face: FaceShapeAdjustments(width: -1), faces: [face])
        let stage = ShapeWarpStage()
        let primitives = stage.facePrimitives(in: renderContext) + stage.bodyPrimitives(in: renderContext)
        let input = Support.markers([contour, shoulder], extent: extent)
        let before = try Support.grid(input)
        let after = try Support.grid(stage.apply(input, in: renderContext))
        for marker in [contour, shoulder] {
            let expected = Support.expectedPosition(
                of: marker, primitives: primitives, limit: tuning.shapeDisplacementLimit)
            let original = try XCTUnwrap(Support.markerCentroid(before, near: marker))
            let moved = try XCTUnwrap(Support.markerCentroid(after, near: expected))
            XCTAssertGreaterThan(hypot(expected.x - marker.x, expected.y - marker.y), 2, "둘 다 실제로 움직인다")
            XCTAssertEqual(moved.x - original.x, expected.x - marker.x, accuracy: 0.75, "얼굴·체형 합친 예측만큼")
            XCTAssertEqual(moved.y - original.y, expected.y - marker.y, accuracy: 0.75)
        }
    }

    func testOutOfRangeBodyValuesRenderLikeClampedValues() throws {
        let body = Support.standingBody(in: Support.standingBox)
        let image = Support.markers([CGPoint(x: 200, y: 120), CGPoint(x: 150, y: 330)], extent: extent)
        func render(_ adjustments: BodyShapeAdjustments, bodies: [BodyGeometry]) throws -> [UInt8] {
            try Support.bytes(ShapeWarpStage().apply(image, in: bodyContext(adjustments, bodies: bodies)))
        }
        XCTAssertEqual(
            try render(BodyShapeAdjustments(legLength: 3, waist: -4), bodies: [body]),
            try render(BodyShapeAdjustments(legLength: 1, waist: -1), bodies: [body]))
        XCTAssertEqual(
            try render(BodyShapeAdjustments(legLength: -2), bodies: [body]), try Support.bytes(image), "음수 다리 길게는 0")
        XCTAssertEqual(
            try render(BodyShapeAdjustments(legLength: 1, waist: -1), bodies: []), try Support.bytes(image),
            "관절이 없으면 체형만 빠지고 오류가 없다")
    }
```

`PhotoPipelineTests.swift` 맨 아래에 추가:

```swift
    func testBodyAnalysisFailureSkipsOnlyBodyWarp() async throws {
        let url = try writeStripesPNG()
        var colorOnly = EditRecipe()
        colorOnly.color.exposure = 0.2
        var shaped = colorOnly
        shaped.body = BodyShapeAdjustments(legLength: 1, waist: -1)

        let working = PhotoPipeline(
            analyzer: StubFaceAnalyzer(result: .success([])),
            bodyAnalyzer: StubBodyAnalyzer(result: .success([Support.standingBody(in: Support.standingBox)])),
            tuning: RenderTuning())
        let workingID = PhotoID()
        _ = try await working.prepare(workingID, at: url)
        let reshaped = try await working.preview(workingID, recipe: shaped)
        let plain = try await working.preview(workingID, recipe: colorOnly)
        XCTAssertNotEqual(
            Array(reshaped.dataProvider!.data! as Data), Array(plain.dataProvider!.data! as Data), "관절이 있으면 허리가 바뀐다")

        let failing = PhotoPipeline(
            analyzer: StubFaceAnalyzer(result: .success([])),
            bodyAnalyzer: StubBodyAnalyzer(result: .failure(.bodyAnalysisUnavailable(reason: "test"))),
            tuning: RenderTuning())
        let id = PhotoID()
        _ = try await failing.prepare(id, at: url)
        let previewShaped = try await failing.preview(id, recipe: shaped)
        let previewColor = try await failing.preview(id, recipe: colorOnly)
        XCTAssertEqual(
            Array(previewShaped.dataProvider!.data! as Data), Array(previewColor.dataProvider!.data! as Data),
            "미리보기는 체형만 빼고 그린다")
        let original = try await failing.renderOriginal(id, at: url, recipe: shaped, maxDimension: nil)
        let originalColor = try await failing.renderOriginal(id, at: url, recipe: colorOnly, maxDimension: nil)
        XCTAssertEqual(try Support.bytes(original), try Support.bytes(originalColor), "저장도 오류 없이 체형만 건너뛴다")
        let unprepared = try await failing.renderOriginal(PhotoID(), at: url, recipe: shaped, maxDimension: nil)
        XCTAssertEqual(unprepared.extent.size, CGSize(width: 256, height: 192), "준비 전 사진도 체형 때문에 저장을 막지 않는다")
    }
```

- [ ] **Step 2: 실패 확인**

Run: `cd apple && swift test --filter 'ShapeWarpStageTests|PhotoPipelineTests'` → 새 테스트 실패(`bodyPrimitives`가 빈 배열이라 표식이 움직이지 않고, `testBodyAnalysisFailureSkipsOnlyBodyWarp`의 "관절이 있으면 허리가 바뀐다"가 실패).

- [ ] **Step 3: 구현**

`ShapeWarpStage.swift`의 타입 문서 주석 두 줄과 `bodyPrimitives`를 다음으로 바꾼다:

```swift
/// 얼굴형(C)과 체형(E) 이동 원소를 모아 이동량 지도로 한 번만 변형한다. B0의 상자 기반 얼굴 폭 변형을 대체한다.
/// 얼굴은 대상 얼굴 모두, 체형은 가장 큰 사람(bodies.first) 한 명이다. 값 범위는 각 rig가 직접 자른다.
/// 원소가 없으면 입력을 그대로 돌려준다. 관절이 없거나 체형 분석이 실패했으면 체형 원소만 빠진다(오류 아님).
```

```swift
    /// 가장 큰 사람 한 명의 체형 원소. 관절이 없거나 분석이 실패해 bodies가 비었으면 빈 배열이다(스펙 1.4, 5).
    func bodyPrimitives(in context: RenderContext) -> [ShapePrimitive] {
        let adjustments = context.recipe.body
        guard adjustments.hasEffect, let body = context.bodies.first else { return [] }
        return BodyShapeRig.primitives(
            body: body, adjustments: adjustments, extent: context.extent, tuning: context.tuning)
    }
```

- [ ] **Step 4: 통과 확인**

Run: `cd apple && swift test` → 모듈별 `Executed 40 · 193 · 30 · 4 · 26 tests`, 모두 `with 0 failures`(합 293). `RenderPipelineTests.testStageOrderMatters`의 이름 배열은 바뀌지 않는다. lint 출력 없음.

- [ ] **Step 5: 커밋**

```bash
git add apple/Sources/MellowRendering/Domain/ShapeWarpStage.swift apple/Tests/MellowRenderingTests/ShapeWarpStageTests.swift apple/Tests/MellowRenderingTests/PhotoPipelineTests.swift
git commit -m "feat(rendering): 얼굴형 변형에 가장 큰 사람의 체형 원소를 합쳐 한 번에 변형

ShapeWarpStage.bodyPrimitives가 bodies.first로 BodyShapeRig 원소를 만든다.
관절이 없거나 체형 분석이 실패하면 체형만 빠지고 미리보기·저장은 계속한다.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 6: 앱 — 체형 도구, 전신 없음·분석 실패 안내, 잠금, Vision 체형 분석 연결, E 시나리오

**Files:**
- Create: `apple/MellowPhoto/Features/Editor/BodyPanel.swift`
- Modify: `apple/MellowPhoto/Application/EditorTool.swift`
- Modify: `apple/MellowPhoto/Application/AppModel.swift` (`PhotoInfo`, `BodyAvailability`, `bodyAvailability`, `remember`)
- Modify: `apple/MellowPhoto/Application/AppModel+Editing.swift` (`touch` switch)
- Modify: `apple/MellowPhoto/Application/UserMessage.swift`
- Modify: `apple/MellowPhoto/Features/Editor/ToolStrip.swift`
- Modify: `apple/MellowPhoto/Features/Editor/EditorScene.swift` (`toolPanel`)
- Modify: `apple/MellowPhoto/Platform/AppModel+Live.swift`
- Modify: `apple/MellowPhoto.xcodeproj` (`xcodegen generate` 결과)
- Modify: `apple/MellowPhotoTests/TestSupport.swift` (`StubBodyAnalyzer`, `standingBody(in:)`, `makeModel` 인자)
- Test: `apple/MellowPhotoTests/AppModelTests.swift`, `apple/MellowPhotoTests/EditorScenarioTests.swift`

**Interfaces:**
- Consumes: `BodyAnalyzer`·`VisionBodyAnalyzer`·`PreparedPhoto.hasBody`·`bodyAnalysisFailure`·`PhotoPipeline.init(…bodyAnalyzer:…)`·`MellowError.bodyAnalysisUnavailable`(Task 2), `ShapeWarpStage` 체형 원소(Task 5, 미리보기 경유), `EditChange.bodyShape`·`EditingPolicy.bodyShapeRange`(Task 1), `BodyShapeKey.allCases`, `AdjustmentSlider(title:value:range:snapsToZero:change:)`, `Theme.bipolarSnapWidth`.
- Produces: `EditorTool.body`(제목 "체형", 기호 `figure.stand`, 도구 줄 뷰티 다음). `struct BodyPanel: View`. `AppModel.PhotoInfo.hasBody: Bool`(기본 false), `.bodyAnalysisFailure: MellowError?`. `enum AppModel.BodyAvailability: Equatable { case ready, noBody, unavailable(MellowError) }`, `AppModel.bodyAvailability`. `UserMessage.toolBody`, `bodyHint`, `noBodyDetected`, `noBodyHint`(스펙 문구 "전신이 보이는 사진에서 동작합니다."), `bodyAnalysisUnavailableTitle`, `bodyShapeTitle(_:)`, 바뀐 `geometryLocked`. 테스트 지원: `StubBodyAnalyzer`(`result: Result<[BodyGeometry], MellowError> = .success([])`), `TestSupport.standingBody(in:)`, `TestSupport.makeModel(root:maxPhotos:analyzer:personAnalyzer:bodyAnalyzer:importer:store:)`.

설계 근거: 도구 줄은 `필터 · 자동 · 자르기 · 조정 · 뷰티 · 체형 · 배경 · 잡티 · 변형`(F가 메이크업을 뷰티와 체형 사이에 넣어 스펙 7 순서가 된다). 관절이 없거나 분석이 실패하면 안내를 위에 보이고 슬라이더는 값이 보이게 끈다(프리셋·일괄로 들어온 값 확인, 배경 도구와 같은 방식). 수동 잡티·변형이 있으면 슬라이더를 끄고 잠금 문구를 보인다(얼굴형과 같은 규칙). 잠금 문구는 얼굴형·체형 공통으로 바꾼다(`mutateSelected`가 거절 때 띄우는 문구 하나). 체형 분석 실패는 가져오기 경고에 넣지 않는다(`ImportPhotos`는 그대로). 분석 실패가 전신 없음보다 먼저다.

- [ ] **Step 1: 테스트 지원 코드**

`TestSupport.swift`의 `struct StubPersonAnalyzer` 아래에 추가:

```swift
struct StubBodyAnalyzer: BodyAnalyzer {
    var result: Result<[BodyGeometry], MellowError> = .success([])
    func analyze(_ image: CIImage) throws -> [BodyGeometry] { try result.get() }
}
```

`enum TestSupport` 안, `personMask(_:)` 아래에 추가:

```swift
    /// 정면으로 선 사람의 관절점(box 비율, 신뢰도 1). 패키지 테스트의 RenderingTestSupport.standingBody와 같은 배치다.
    static func standingBody(in box: NormalizedRect) -> BodyGeometry {
        let layout: [BodyJoint: (x: Double, y: Double)] = [
            .neck: (0.5, 0.82), .rightShoulder: (0.25, 0.8), .leftShoulder: (0.75, 0.8),
            .rightElbow: (0.18, 0.62), .leftElbow: (0.82, 0.62), .rightWrist: (0.15, 0.45), .leftWrist: (0.85, 0.45),
            .rightHip: (0.38, 0.5), .leftHip: (0.62, 0.5), .rightKnee: (0.39, 0.27), .leftKnee: (0.61, 0.27),
            .rightAnkle: (0.4, 0.05), .leftAnkle: (0.6, 0.05), .root: (0.5, 0.5),
        ]
        var joints: [BodyJoint: NormalizedPoint] = [:]
        for (joint, spot) in layout {
            joints[joint] = NormalizedPoint(x: box.minX + box.width * spot.x, y: box.minY + box.height * spot.y)
        }
        return BodyGeometry(joints: joints, confidence: joints.mapValues { _ in 1 })
    }
```

`makeModel` 전체:

```swift
    @MainActor
    static func makeModel(
        root: URL, maxPhotos: Int = 40, analyzer: StubFaceAnalyzer = StubFaceAnalyzer(),
        personAnalyzer: StubPersonAnalyzer = StubPersonAnalyzer(), bodyAnalyzer: StubBodyAnalyzer = StubBodyAnalyzer(),
        importer: FakeImporter = FakeImporter(), store: MemorySessionStore = MemorySessionStore()
    ) -> AppModel {
        let copies = WorkingCopyStore(directory: root.appendingPathComponent("Library"))
        try? copies.prepareDirectory()
        let catalog = (try? sharedLookCatalog()) ?? .empty
        return AppModel(
            session: ProjectSession(store: store, maxPhotos: maxPhotos),
            pipeline: PhotoPipeline(
                analyzer: analyzer, personAnalyzer: personAnalyzer, bodyAnalyzer: bodyAnalyzer, tuning: RenderTuning(),
                lookCatalog: catalog),
            copies: copies,
            importer: importer,
            exporter: Exporter(renderer: Renderer()),
            lookCatalog: catalog,
            renderDebounce: .milliseconds(10))
    }
```

- [ ] **Step 2: 실패하는 테스트 작성**

`AppModelTests.swift` 맨 아래(`testBackgroundToolReportsNoPersonAndAnalysisFailureWithoutBlockingRender` 뒤)에 추가:

```swift
    func testBodyToolEditsEveryKeyOneUndoStepEachWhenBodyFound() async throws {
        let staged = try TestSupport.solidPNG(in: root)
        let body = TestSupport.standingBody(in: NormalizedRect(x: 0.1, y: 0, width: 0.8, height: 1))
        let model = TestSupport.makeModel(
            root: root, bodyAnalyzer: StubBodyAnalyzer(result: .success([body])),
            importer: FakeImporter(staged: [.success(StagedPhoto(url: staged, displayName: nil))]))
        try await importOne(model, staged)
        XCTAssertEqual(EditorTool.allCases, [.look, .crop, .adjust, .beauty, .body, .background, .retouch, .warp])
        model.selectTool(.body)
        XCTAssertEqual(EditorTool.body.title, "체형")
        XCTAssertEqual(model.bodyAvailability, .ready)
        for key in BodyShapeKey.allCases {
            model.beginSliderEdit()
            model.edit(.bodyShape(key, 0.2))
            model.edit(.bodyShape(key, 0.4))
            model.endSliderEdit()
        }
        for key in BodyShapeKey.allCases {
            XCTAssertEqual(model.currentRecipe.body[key], 0.4, accuracy: 1e-9, "\(key)")
        }
        XCTAssertEqual(
            BodyShapeKey.allCases.map(UserMessage.bodyShapeTitle), ["다리 길게", "허리", "몸 전체", "팔", "허벅지", "어깨", "목"])
        try await waitUntil { !model.isRendering }
        XCTAssertNil(model.presentedError)
        model.undo()
        XCTAssertEqual(model.currentRecipe.body.neck, 0, "드래그 한 번이 실행 취소 한 단계")
        XCTAssertEqual(model.currentRecipe.body.shoulders, 0.4, accuracy: 1e-9)
    }

    func testBodyToolReportsNoBodyAndAnalysisFailureWithoutBlockingRender() async throws {
        let staged = try TestSupport.solidPNG(in: root)
        let empty = TestSupport.makeModel(
            root: root, importer: FakeImporter(staged: [.success(StagedPhoto(url: staged, displayName: nil))]))
        try await importOne(empty, staged)
        XCTAssertEqual(empty.bodyAvailability, .noBody)
        XCTAssertEqual(UserMessage.noBodyHint, "전신이 보이는 사진에서 동작합니다.")

        let otherRoot = try TestSupport.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: otherRoot) }
        let otherStaged = try TestSupport.solidPNG(in: otherRoot)
        let failure = MellowError.bodyAnalysisUnavailable(reason: "test")
        let failing = TestSupport.makeModel(
            root: otherRoot, bodyAnalyzer: StubBodyAnalyzer(result: .failure(failure)),
            importer: FakeImporter(staged: [.success(StagedPhoto(url: otherStaged, displayName: nil))]))
        try await importOne(failing, otherStaged)
        XCTAssertNil(failing.presentedError, "체형 분석 실패는 가져오기 경고로 띄우지 않는다")
        XCTAssertEqual(failing.bodyAvailability, .unavailable(failure))
        failing.edit(.bodyShape(.legLength, 0.5))
        try await waitUntil { !failing.isRendering }
        XCTAssertEqual(failing.currentRecipe.body.legLength, 0.5, "값은 저장된다")
        XCTAssertNil(failing.presentedError, "렌더는 체형만 건너뛰고 오류를 띄우지 않는다")
    }

    func testGeometryLockRejectsEveryBodyShapeKey() async throws {
        let staged = try TestSupport.solidPNG(in: root)
        let body = TestSupport.standingBody(in: NormalizedRect(x: 0.1, y: 0, width: 0.8, height: 1))
        let model = TestSupport.makeModel(
            root: root, bodyAnalyzer: StubBodyAnalyzer(result: .success([body])),
            importer: FakeImporter(staged: [.success(StagedPhoto(url: staged, displayName: nil))]))
        try await importOne(model, staged)
        model.tool = .retouch
        model.touch(from: NormalizedPoint(x: 0.3, y: 0.3), to: NormalizedPoint(x: 0.3, y: 0.3))
        model.touch(from: NormalizedPoint(x: 0.5, y: 0.5), to: NormalizedPoint(x: 0.5, y: 0.5))
        XCTAssertEqual(model.currentRecipe.operations.count, 1)
        try await waitUntil { !model.isRendering }
        XCTAssertTrue(model.isGeometryLocked)
        model.selectTool(.body)
        for key in BodyShapeKey.allCases {
            model.edit(.bodyShape(key, 0.5))
            XCTAssertEqual(model.currentRecipe.body[key], 0, "\(key)는 잠겨 있다")
        }
        XCTAssertEqual(model.statusMessage, UserMessage.geometryLocked)
        XCTAssertTrue(UserMessage.geometryLocked.contains("체형"), "잠금 문구가 체형도 말한다")
    }
```

`EditorScenarioTests.swift`: `demoPersonMask` 아래에 스텁 사람을 더하고, `testBeautySkinFaceFeaturesThenBackgroundThenExportSucceeds` 전체를 다음으로 바꾼다(스펙 8 시나리오의 E 단계).

```swift
    /// 공용 픽스처에는 전신이 없다(Vision은 0명을 찾는다). 다리 띠가 사진 아래쪽에 걸리도록 놓은 스텁 사람이다.
    private static let demoBody = TestSupport.standingBody(in: NormalizedRect(x: 0.15, y: 0, width: 0.7, height: 0.9))
```

```swift
    func testBeautySkinFaceFeaturesBackgroundThenBodyThenExportSucceeds() async throws {
        let model = TestSupport.makeModel(
            root: root, analyzer: StubFaceAnalyzer(result: .success([Self.demoFace])),
            personAnalyzer: StubPersonAnalyzer(result: .success(Self.demoPersonMask)),
            bodyAnalyzer: StubBodyAnalyzer(result: .success([Self.demoBody])),
            importer: FakeImporter(passesThroughFileURLs: true))
        await model.importFromFiles([try demoPortraitCopy()])
        try await waitUntil { model.isReady && model.preview != nil }
        let plain = previewBytes(model)

        model.selectTool(.beauty)
        model.beginSliderEdit()
        model.edit(.skinSmoothing(0.5))
        model.endSliderEdit()
        model.edit(.autoBlemish(true))
        try await waitUntil { !model.isRendering && self.previewBytes(model) != plain }
        let skinned = previewBytes(model)

        model.beautyTab = .face
        let faceEdits: [(FaceShapeKey, Double)] = [(.width, -0.5), (.eyeSize, 0.3), (.smile, 0.4)]
        for (key, value) in faceEdits {
            model.beginSliderEdit()
            model.edit(.faceShape(key, value))
            model.endSliderEdit()
        }
        // 얼굴형만 바꿔도 미리보기가 바뀌어야 한다(바뀌지 않으면 시간 초과로 실패).
        try await waitUntil { !model.isRendering && self.previewBytes(model) != skinned }

        model.beautyTab = .features
        model.beginSliderEdit()
        model.edit(.feature(.eyeBrighten, 0.5))
        model.endSliderEdit()
        try await waitUntil { !model.isRendering }
        let featured = previewBytes(model)

        model.selectTool(.background)
        XCTAssertEqual(model.backgroundAvailability, .ready)
        model.beginSliderEdit()
        model.edit(.backgroundBlur(0.5))
        model.endSliderEdit()
        // 배경 흐림만 바꿔도 미리보기가 바뀌어야 한다.
        try await waitUntil { !model.isRendering && self.previewBytes(model) != featured }
        let blurred = previewBytes(model)

        model.selectTool(.body)
        XCTAssertEqual(model.bodyAvailability, .ready)
        model.beginSliderEdit()
        model.edit(.bodyShape(.legLength, 0.5))
        model.endSliderEdit()
        // 다리 길게만 바꿔도 미리보기가 바뀌어야 한다.
        try await waitUntil { !model.isRendering && self.previewBytes(model) != blurred }

        let recipe = model.currentRecipe
        XCTAssertEqual(recipe.portrait.skin, SkinAdjustments(smoothing: 0.5, autoBlemish: true))
        XCTAssertEqual(recipe.portrait.face, FaceShapeAdjustments(width: -0.5, eyeSize: 0.3, smile: 0.4))
        XCTAssertEqual(recipe.portrait.features, FeatureAdjustments(eyeBrighten: 0.5))
        XCTAssertEqual(recipe.background.blur, 0.5, accuracy: 1e-9)
        XCTAssertEqual(recipe.body, BodyShapeAdjustments(legLength: 0.5))
        let size = try await exportedPixelSize(model)
        XCTAssertEqual(size.width, size.height, "다리를 늘려도 정사각형 원본 크기 그대로 저장된다")
    }
```

- [ ] **Step 3: 실패 확인**

Run: `xcodebuild -project apple/MellowPhoto.xcodeproj -scheme MellowPhoto -derivedDataPath apple/build -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO build-for-testing 2>&1 | grep -c "error:"` → 0보다 큼(`EditorTool`에 `body` 없음, `bodyAvailability` 없음, `bodyShapeTitle` 없음).

- [ ] **Step 4: 구현**

`UserMessage.swift`:
1. `geometryLocked`를 다음으로 바꾼다:

```swift
    static let geometryLocked = "수동 보정 위치를 유지하려고 얼굴형·체형 조정을 잠갔어요. 실행 취소 또는 초기화하면 다시 조정할 수 있어요."
```

2. `static let personAnalysisUnavailableTitle = …` 아래에 추가:

```swift
    static let toolBody = "체형"
    static let bodyHint = "다리 길게는 왼쪽 끝, 나머지는 가운데가 원래 모양이에요(왼쪽은 가늘게·좁게, 오른쪽은 넓게·길게). 다리 길게는 골반과 발목이 보여야 바뀌어요."
    static let noBodyDetected = "몸의 관절을 찾지 못했어요"
    static let noBodyHint = "전신이 보이는 사진에서 동작합니다."
    static let bodyAnalysisUnavailableTitle = "체형 분석을 사용할 수 없어요"
```

3. 함수 묶음(`featureTitle` 아래)에 추가:

```swift
    /// 체형 도구 슬라이더 이름. 화면 순서는 BodyShapeKey.allCases. 스펙의 "전체 날씬"은 양방향이라 "몸 전체"로 부른다.
    static func bodyShapeTitle(_ key: BodyShapeKey) -> String {
        switch key {
        case .legLength: return "다리 길게"
        case .waist: return "허리"
        case .overall: return "몸 전체"
        case .arms: return "팔"
        case .thighs: return "허벅지"
        case .shoulders: return "어깨"
        case .neck: return "목"
        }
    }
```

`EditorTool.swift`: `case beauty` 아래에 `case body`를 더하고, `title`의 `case .beauty` 아래에 `case .body: return UserMessage.toolBody`, `symbol`의 `case .beauty` 아래에 `case .body: return "figure.stand"`를 더한다.

`AppModel.swift`:
1. `PhotoInfo`의 `personAnalysisFailure` 아래에 추가:

```swift
        /// 가장 큰 사람의 두 어깨가 보이는지. 체형 도구 안내에 쓴다.
        var hasBody = false
        /// 체형 분석이 실패했으면 그 이유. 사람이 없는 것과 구분한다.
        var bodyAnalysisFailure: MellowError?
```

2. `BackgroundAvailability` 아래에 추가:

```swift
    /// 체형 도구가 보여줄 상태. 분석 실패가 전신 없음보다 먼저다.
    enum BodyAvailability: Equatable {
        case ready
        case noBody
        case unavailable(MellowError)
    }
```

3. `backgroundAvailability` 아래에 추가:

```swift
    /// 선택 사진의 체형 도구 상태.
    var bodyAvailability: BodyAvailability {
        if let failure = selectedInfo?.bodyAnalysisFailure {
            return .unavailable(failure)
        }
        return selectedInfo?.hasBody == true ? .ready : .noBody
    }
```

4. `remember(_:_:)`:

```swift
    func remember(_ id: PhotoID, _ prepared: PreparedPhoto) {
        thumbnails[id] = prepared.thumbnail
        photoInfo[id] = PhotoInfo(
            pixelSize: prepared.pixelSize, faces: prepared.faces, faceAnalysisFailure: prepared.faceAnalysisFailure,
            hasPerson: prepared.hasPerson, personAnalysisFailure: prepared.personAnalysisFailure,
            hasBody: prepared.hasBody, bodyAnalysisFailure: prepared.bodyAnalysisFailure)
    }
```

`AppModel+Editing.swift`의 `touch` switch 마지막 case:

```swift
        case .look, .crop, .adjust, .beauty, .body, .background:
            return
```

`ToolStrip.swift`의 도구 목록:

```swift
                ForEach([EditorTool.crop, .adjust, .beauty, .body, .background, .retouch, .warp]) { toolButton($0) }
```

`EditorScene.swift`의 `toolPanel` switch에 `case .beauty: BeautyPanel()` 아래 한 줄:

```swift
        case .body: BodyPanel()
```

`apple/MellowPhoto/Features/Editor/BodyPanel.swift`:

```swift
import MellowEditing
import MellowShared
import SwiftUI

/// 체형 도구. 가장 큰 사람 한 명의 관절점으로 다리·허리·몸 전체·팔·허벅지·어깨·목을 바꾼다.
/// 관절을 찾지 못했거나 체형 분석이 실패하면 안내를 보이고 슬라이더는 값이 보이게 끈다(프리셋으로 들어온 값을 확인할 수 있다).
/// 수동 잡티·변형이 있으면 얼굴형처럼 잠긴다.
struct BodyPanel: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let availability = model.bodyAvailability
        let shape = model.currentRecipe.body
        switch availability {
        case .ready:
            EmptyView()
        case .noBody:
            Label(UserMessage.noBodyDetected, systemImage: "figure.stand")
            Text(UserMessage.noBodyHint).font(.caption).foregroundStyle(.secondary)
        case .unavailable(let failure):
            Label(UserMessage.bodyAnalysisUnavailableTitle, systemImage: "exclamationmark.triangle")
            Text(UserMessage.text(for: failure)).font(.caption).foregroundStyle(.secondary)
        }
        ForEach(BodyShapeKey.allCases, id: \.self) { key in
            let range = EditingPolicy.bodyShapeRange(key)
            AdjustmentSlider(
                title: UserMessage.bodyShapeTitle(key), value: shape[key], range: range,
                snapsToZero: range.lowerBound < 0
            ) { .bodyShape(key, $0) }
            .disabled(availability != .ready || model.isGeometryLocked)
        }
        Text(model.isGeometryLocked ? UserMessage.geometryLocked : UserMessage.bodyHint)
            .font(.caption).foregroundStyle(.secondary)
    }
}
```

`AppModel+Live.swift`의 파이프라인 조립:

```swift
            pipeline: PhotoPipeline(
                analyzer: VisionFaceAnalyzer(), personAnalyzer: VisionPersonAnalyzer(),
                bodyAnalyzer: VisionBodyAnalyzer(), tuning: RenderTuning.forCurrentDevice(), lookCatalog: lookCatalog),
```

새 앱 파일을 프로젝트에 넣는다: `cd apple && xcodegen generate --quiet && git status --short MellowPhoto.xcodeproj` → `M MellowPhoto.xcodeproj/project.pbxproj`.

- [ ] **Step 5: 통과 확인**

Run: Mac 앱 테스트 → `Executed 59 tests, with 0 failures`. `cd apple && swift test` → 모듈별 `Executed 40 · 193 · 30 · 4 · 26 tests`, 모두 `with 0 failures`. lint 출력 없음(`bodyHint` 줄이 120자를 넘으면 문자열을 `+`로 나누지 말고 문장을 줄인다). `./scripts/verify-modules.sh` 통과. `cd apple && xcodegen generate --quiet && git diff --exit-code --stat MellowPhoto.xcodeproj` → 이 Task 커밋 뒤에는 출력 없음. iOS 시뮬레이터 테스트는 돌리지 않는다(Task 7).

- [ ] **Step 6: 커밋**

```bash
git add apple/MellowPhoto/Features/Editor/BodyPanel.swift apple/MellowPhoto/Application/EditorTool.swift apple/MellowPhoto/Application/AppModel.swift apple/MellowPhoto/Application/AppModel+Editing.swift apple/MellowPhoto/Application/UserMessage.swift apple/MellowPhoto/Features/Editor/ToolStrip.swift apple/MellowPhoto/Features/Editor/EditorScene.swift apple/MellowPhoto/Platform/AppModel+Live.swift apple/MellowPhoto.xcodeproj apple/MellowPhotoTests/TestSupport.swift apple/MellowPhotoTests/AppModelTests.swift apple/MellowPhotoTests/EditorScenarioTests.swift
git commit -m "feat(app): 체형 도구와 전신 없음 안내, Vision 체형 분석 연결

도구 줄 뷰티 다음에 체형 도구를 두고 슬라이더 7개를 단다. 관절이 없거나 분석이
실패하면 안내를 보이고 슬라이더를 끄며, 수동 편집이 있으면 잠근다.
실기기 조립은 VisionBodyAnalyzer를 넘긴다.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 7: 문서·스펙·검증 기록과 전체 검증

**Files:**
- Modify: `README.md`, `docs/APPLE.md`, `docs/architecture/modules.md`, `VALIDATION.md`, `docs/superpowers/specs/2026-10-15-beauty-b-to-f-design.md`

**Interfaces:**
- Consumes: Task 1~6 결과와 `MELLOW_IOS_TESTS=1 ./scripts/test-apple.sh`·`./scripts/build-apple.sh` 출력.
- Produces: 문서. 이후 Task 없음.

- [ ] **Step 1: 최종 검증 실행**

실행 전 `xcrun simctl list devices booted`로 이미 켜진 시뮬레이터를 적어 둔다. Run: `MELLOW_IOS_TESTS=1 ./scripts/test-apple.sh; echo "exit=$?"` → `exit=0`, 패키지 모듈별 `Executed 40 · 193 · 30 · 4 · 26 tests`(합 293), 앱 iPhone `Executed 58 tests`·iPad `Executed 58 tests`·Mac `Executed 59 tests`(모두 0 failures). 실행 뒤에도 시뮬레이터를 끄지 않는다(스크립트가 부팅한 기기도 끄지 않는다. 다른 프로젝트가 같은 기기를 쓸 수 있다). SpringBoard 크래시 창이 떠도 테스트 결과로만 판정하고 기록한다. 이어서 `./scripts/build-apple.sh ios-device; echo "exit=$?"`와 `./scripts/build-apple.sh mac; echo "exit=$?"` → 둘 다 `exit=0`. 빌드 로그의 경고가 Global Constraints 허용 목록뿐인지 본다. 실제 숫자·종료 코드·커밋 해시(`git rev-parse --short HEAD`)를 적어 두고 아래 문서에 그대로 쓴다. 기대와 다르면 실제 값을 쓰고, 실패면 통과로 쓰지 않는다.

- [ ] **Step 2: README·APPLE.md·modules.md**

`README.md`:
- "첫 보정" 5번의 "뷰티·배경 값(피부 보정·자동 잡티·얼굴형 10개·눈·입 3개·배경 흐림)"을 "뷰티·체형·배경 값(피부 보정·자동 잡티·얼굴형 10개·눈·입 3개·체형 7개·배경 흐림)"으로.
- 6번(뷰티) 뒤에 새 항목 "**체형**에서 다리 길게·허리·몸 전체·팔·허벅지·어깨·목을 씁니다. 다리 길게만 0에서 시작하고 나머지는 가운데가 원래 모양(왼쪽은 가늘게·좁게, 오른쪽은 넓게·길게)입니다. 사진에서 가장 큰 사람 한 명만 바뀌고, 관절을 찾지 못한 사진은 \"전신이 보이는 사진에서 동작합니다\" 안내만 보입니다. 다리 길게는 골반 아래를 세로로 늘려 사진 아래쪽이 조금 잘립니다."를 넣고 이후 번호를 하나씩 민다.
- 도구 줄 문장을 "필터 · 자동 · 자르기 · 조정 · 뷰티 · 체형 · 배경 · 잡티 · 변형 순서입니다."로.
- 잠금 문단의 "얼굴형 슬라이더와 얼굴 선택은 잠깁니다"를 "얼굴형·체형 슬라이더와 얼굴 선택은 잠깁니다"로, "얼굴 형태는 유지합니다"를 "얼굴형·체형은 유지합니다"로.
- "구현된 범위"에 "- Vision 관절점으로 가장 큰 사람 한 명의 다리·허리·몸 전체·팔·허벅지·어깨·목을 바꾸는 체형 보정(얼굴형과 같은 이동량 지도 한 번에 합침)"을 더한다.
- 한계 문단의 "Evoto와 동일한 보정 품질, 자동 전신 체형 인식은 구현하지 않았습니다."를 "체형 보정도 학습 모델 없이 Vision 관절점으로 동작하며, 다리 길게는 다리 높이의 배경·다른 사람도 함께 늘이고, 팔이 몸에 붙은 사진이나 옷에 가려 관절이 틀린 사진은 윤곽이 휠 수 있습니다. Evoto와 동일한 보정 품질은 구현하지 않았습니다."로.
- 로드맵 "E 체형" 줄을 "**E 체형**: 체형 슬라이더 7개 (`body`) — 구현됨, 실제 전신 사진 확인은 사용자 조치로 남음"으로.

`docs/APPLE.md`:
- 도구 줄 문장을 "**필터 · 자동 · 자르기 · 조정 · 뷰티 · 체형 · 배경 · 잡티 · 변형**"으로.
- 뷰티 줄의 "수동 잡티·변형이 있으면 얼굴형 슬라이더와 얼굴 선택이 잠깁니다."는 그대로 두고, 그 아래(배경 줄 위)에 "- 체형: *다리 길게*(0…1)·*허리·몸 전체·팔·허벅지·어깨·목*(가운데 0인 양방향, 0 근처에서 붙음). 사진을 준비할 때 찾은 관절점으로 가장 큰 사람 한 명만 바꾸고 얼굴형과 함께 한 번에 다시 그립니다. 두 어깨를 찾지 못했거나 체형 분석이 실패하면 안내를 보이고 슬라이더를 끕니다. 수동 잡티·변형이 있으면 잠깁니다." 줄을 넣는다.
- "검증 상태" 문단을 Step 1의 실제 결과(브랜치 `beauty-b-to-f`, 커밋, 종료 코드, 패키지 293개(MellowShared 40 · MellowRendering 193 · MellowLibrary 30 · MellowExport 4 · MellowEditing 26), 앱 iPhone 58 · iPad 58 · Mac 59 예상)로 바꾼다.
- 기기 확인 항목에 "체형 7종의 실제 전신 사진 결과(과한 값, 팔이 몸에 붙은 자세, 여러 사람, 다리 높이 배경 직선 휨, 다리 길게의 아래쪽 잘림)와 시뮬레이터·구형 기기의 체형 분석 실패 안내"를 더한다.

`docs/architecture/modules.md`:
- MellowShared 규칙에 "관절점(`BodyGeometry`·`BodyJoint` 14개, 신뢰도 포함)은 영속화하지 않음, 체형 범위는 `AdjustmentRange.bodyShape`(다리 길게만 unit)"를 더한다.
- MellowEditing 규칙의 "수동 편집 시 얼굴형(`faceShape`)·대상 잠금(E에서 체형 추가)"을 "수동 편집 시 얼굴형(`faceShape`)·체형(`bodyShape`)·대상 잠금"으로, 값 범위 괄호에 `bodyShapeRange`를 더한다.
- MellowRendering 공개 API에 `BodyAnalyzer`, `VisionBodyAnalyzer`를 더한다. 포트 칸에 "`BodyAnalyzer` (`analyze(CIImage) throws -> [BodyGeometry]`, 관절 상자 넓이가 큰 사람부터). 기본 구현 `VisionBodyAnalyzer`(`VNDetectHumanBodyPoseRequest`, 신뢰도 0인 관절은 버림)도 `Infrastructure/`의 `public`"을 더한다.
- MellowRendering 규칙에서 "체형 원소 자리 `bodyPrimitives`는 E까지 빈 배열"을 지우고 다음을 더한다: "체형 분석은 사진 준비 때 `PhotoAnalysis.bodies`에 두고 실패는 `PreparedPhoto.bodyAnalysisFailure`이며 렌더는 체형 원소만 건너뜀(오류 아님), `BodySkeleton`이 신뢰도 `bodyJointMinConfidence` 미만 관절을 빼고 어깨 폭·몸통 축을 정하며 두 어깨가 없으면 체형 없음(`PreparedPhoto.hasBody`도 같은 판정), 체형 원소는 `BodyShapeRig`가 가장 큰 사람(`bodies.first`)에서 만들고 값을 `AdjustmentRange`로 직접 자름(유한하지 않은 값은 0), push 이동은 어깨 폭 × min(항목 최대, `bodyShapeMaxShift`)이고 반지름은 이동 / `shapeDisplacementLimit` 이상, 다리 길게 띠는 이동량 지도에 그리지 않고 샘플링 커널이 smoothstep 식으로 더함(띠 하나만, 패치는 띠 시작 행부터 먼 가장자리까지)". 이동량 지도 문구의 "색 커널로 이동량을 그리고"를 "push·scale은 색 커널로 이동량 지도에 그리고"로 바꾼다. 테스트 칸에 "관절점(신뢰도·상자·Vision 이름 대응·큰 사람 순서), 몸통 축(기울기·엉덩이 없음), 체형 원소(방향·관절 누락·범위 밖·NaN·상한에 안 걸림·기울기·접힘), 다리 띠(smoothstep 가장자리·지도 밖 계산·패치 위 같은 바이트·640px 이동 정밀도), 체형 렌더(무릎 표식 이동·가장 큰 사람만·얼굴과 한 번에·분석 실패 시 건너뜀)"를 더한다.
- `PhotoPipeline` 문단의 `init(analyzer:personAnalyzer:tuning:lookCatalog:)`를 `init(analyzer:personAnalyzer:bodyAnalyzer:tuning:lookCatalog:)`(분석기 기본 nil = 분석 안 함)로 바꾼다.
- 앱 `Application/` 설명의 `EditorTool`을 `look, crop, adjust, beauty, body, background, retouch, warp`로 바꾸고, `AppModel+Live` 줄에 `VisionBodyAnalyzer`를 더한다. `AppModel` 생성자 문단의 "`PhotoPipeline`(안에 `FaceAnalyzer`·`PersonAnalyzer`)"를 "`PhotoPipeline`(안에 `FaceAnalyzer`·`PersonAnalyzer`·`BodyAnalyzer`)"로.

- [ ] **Step 3: 스펙 갱신 (CLAUDE.md 규칙 3)**

`docs/superpowers/specs/2026-10-15-beauty-b-to-f-design.md`:
- 결정 표의 "(D 구현 중 변경) …" 줄 아래에 줄 하나를 더한다: "| (E 구현 중 변경) 다리 길게 띠는 이동량 지도에 그리지 않고 다시 그리는 커널이 식으로 계산하고, 띠 양 끝(골반·발목)을 부드럽게 시작·끝냄 | 큰 사진에서 다리를 바꿀 때 사진 크기 이동량 지도가 생기지 않고 큰 이동도 반 픽셀 계단이 없음. 골반에서 늘림이 꺾이지 않는 대신 무릎 근처가 가장 많이 늘어남 | 작음 |".
- 1.5의 원소 설명 `.band(yStart, yEnd, stretch)(가로 띠 세로 늘림, 다리 길게 전용)` 뒤에 "띠 안 이동은 stretch × span × smoothstep(t)"를 더하고, 둘째 항목의 "원소 종류마다 CIKL `CIColorKernel(source:)` 하나(`pushField`·`scaleField`·`bandField`)가"를 "push·scale마다 CIKL `CIColorKernel(source:)` 하나(`pushField`·`scaleField`)가"로, "(… band는 extent 전체)"를 "(… band는 지도에 넣지 않고 샘플링 커널이 같은 식으로 더하며 띠는 하나만, 패치는 띠 시작 행부터 먼 가장자리까지)"로 바꾸고 끝에 "(E 구현 중 변경: 처음 문구는 bandField 색 커널과 band 영향 = extent 전체.)"를 붙인다.
- 5의 `BodyShapeRig` 줄 뒤에 "항목별 최대는 `RenderTuning`(허리 0.06·몸 전체 0.035·팔 0.02·허벅지 0.035·어깨 0.04·목 0.03, 모두 `bodyShapeMaxShift` 이하), push 반지름 ≥ 이동 / `shapeDisplacementLimit`, 음수는 가늘게·좁게·짧게. 화면 이름은 overall을 \"몸 전체\"로 부름. 두 어깨가 없으면 체형 없음(안내 대상). (E 구현 중 정함)"을 더한다.

- [ ] **Step 4: VALIDATION.md**

`## 인물 보정 D 눈·치아·입술·배경 (2026-10-15)` 절 뒤, `## TestFlight 전용 배포 경로` 앞에 `## 인물 보정 E 체형 (2026-10-15)` 절을 쓴다. 사람 확인 영역만 있고, 실행한 것만 통과로 쓴다.
- 첫 문단: 브랜치·커밋·환경(D 절과 같은 형식), "이 절의 검증은 모두 자동 테스트와 빌드이며, 앱 화면을 직접 보거나 조작한 검증은 없습니다."
- `### 자동 검증`: `MELLOW_IOS_TESTS=1 ./scripts/test-apple.sh` 종료 코드, 패키지 테스트 수(모듈별), 앱 테스트 수(iPhone·iPad·Mac), `build-apple.sh ios-device`·`mac` 종료 코드, 빌드 경고(허용 목록, `bandField` 커널이 없어져 커널 언어 경고 하나 감소), 실행 중 SpringBoard 크래시가 있었으면 그 사실.
- `### 자동 테스트가 확인하는 것`: 관절점(신뢰도 낮은 관절 제외, 상자·넓이, Vision 이름 대응·신뢰도 0 제외, 큰 사람 순서, 단색·데모 사진 오류 없음), 몸통 축(똑바로 선 사람·30° 기울기·엉덩이 없음·옆모습 제외), 체형 분석(보관·두 어깨 판정·실패가 얼굴·인물 분석을 막지 않음), 다리 띠(단조·연속, 양 끝 기울기 0, 지도에 그리지 않음, 띠 시작 위 같은 바이트, 640.25px 이동이 평행 이동과 0.1px 안, 띠 둘 거절, push와 함께), 체형 원소(7항목 방향·크기, 관절 누락·낮은 신뢰도, 0·NaN·범위 밖, 상한에 걸리지 않음, 기울어진 몸, 거꾸로·누운 사람 다리 건너뜀, 겹친 원소 최소 야코비안(측정값)), 체형 렌더(무릎 표식 아래로·엉덩이 위 같은 바이트, 가장 큰 사람만, 얼굴과 한 번에, 범위 밖 값, 체형 분석 실패 시 미리보기·저장 모두 체형만 빠짐), 편집(클램프·실행 취소·수동 편집 잠금), 앱(체형 도구 실행 취소 단위, 상태 세 가지, 분석 실패 시 오류 창 없음, 잠금), 시나리오(데모 사진 → 피부 → 얼굴형 → 눈 → 배경 → 다리 길게 0.5로 미리보기가 다시 바뀜 → 정사각형 저장, 스텁 분석기). "합성 관절과 스텁으로 돌며, 실제 사람에서 Vision이 관절을 찾는지와 결과가 보기 좋은지는 판단하지 않습니다."
- `### 구현 중 측정 (이번 절을 쓰면서 다시 재지 않음)`: 계획 작성 때 잰 값(Vision 체형 분석 Mac 첫 호출 0.08~0.13초·이후 약 0.005초, 데모 셀카·단색 이미지 0명, `VNDetectHumanRectanglesRequest`도 데모 셀카 0명)과 구현 중 실제로 잰 값(최소 야코비안 등).
- `### 스펙과 다르게 한 것`: 다리 띠를 지도 밖에서 계산·smoothstep·패치 제한(스펙 1.5 갱신), 항목별 최대를 상한 0.06 아래로 따로 둠, push 반지름 하한, 두 어깨가 없으면 체형 없음, "전체 날씬" 화면 이름을 "몸 전체"로, 거꾸로·누운 사람의 다리 띠 건너뜀, 체형 분석 실패를 가져오기 경고에 넣지 않음, 잠금 문구를 얼굴형·체형 공통으로.
- `### 미검증 (사용자 확인 필요)`: 실제 전신 사진에서 Vision 관절 인식(자동 테스트에 전신 사진이 없음), 체형 7종의 느낌과 최대값, 팔이 몸에 붙은 자세·앉은 자세·옆모습, 여러 사람 사진에서 다리 띠가 다른 사람을 늘이는 정도, 다리 높이 배경 직선 휨과 아래쪽 잘림, iPhone·iPad 실기기와 시뮬레이터에서의 체형 분석 동작·시간, 48MP 원본 저장 속도와 메모리(다리 길게 포함), 체형 도구 화면(슬라이더 7개 배치, 안내 문구, 꺼진 슬라이더), 실기기. "이전 절(D, C, B, B0, 구조 리팩토링 A)의 미검증 항목은 그대로 승계합니다."

- [ ] **Step 5: 커밋**

```bash
git add README.md docs/APPLE.md docs/architecture/modules.md VALIDATION.md docs/superpowers/specs/2026-10-15-beauty-b-to-f-design.md
git commit -m "docs: 체형 사용법·모듈 캔버스·스펙·E 검증 기록 갱신

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

## 자체 검토 결과

- **스펙 대조:** §1.1 → `BodyGeometry`·`BodyJoint`(Shared/API, Task 1), `BodyAnalyzer`(Rendering/API, Task 2), `VisionBodyAnalyzer`(Rendering/Infrastructure, Task 2), `BodyShapeRig`(Domain, Task 4), `DisplacementWarp`(Task 3). 새 import 없음, `verify-modules.sh` 불변. §1.2 → `EditChange.bodyShape`(Task 1), `affectsGeometry`에 `bodyShape`(Task 1), 범위 한 곳(`AdjustmentRange.bodyShape`·`EditingPolicy.bodyShapeRange`), 프리셋·일괄 적용의 잠긴 체형 보존은 B에서 구현·테스트됨. `dependsOnBody`(B)는 렌더가 체형 실패 때 오류를 던지지 않으므로 판정에 쓰지 않는다. §1.3 → 순서 불변, 체형 원소는 `shapeWarp` 안. §1.4 → 관절점(4번째 분석) 미리보기에서 계산·큰 사람 앞(Task 2), 실패는 `PreparedPhoto.bodyAnalysisFailure`(Task 2), 렌더는 해당 원소만 건너뜀(Task 5), 앱 안내(Task 6), `PhotoAnalysis.bodies`·`RenderContext.bodies`(Task 2), `PhotoPipeline.init`의 `bodyAnalyzer`와 앱 Vision 주입(Task 2·6). §1.5 → band 처리 변경(Task 3, 스펙 문구는 Task 7). §5 → 관절 14개·신뢰도 0.3(Task 1·2), 상한 0.06(Task 4), 표 7항목(Task 4 설계 근거 표), 관절 없으면 그 항목만(Task 4), `bodies.first`만(Task 5), 슬라이더 7개·전신 안내(Task 6), 테스트 4종(waist −1 중심선: Task 4 `testWaistNegativePushesBothSidesTowardMidline`, 관절 누락: `testMissingOrLowConfidenceJointsSkipOnlyTheirItems`, band 단조·연속: Task 3 `testBandMappingIsMonotoneAndContinuous`·`testBandEdgesHaveZeroSlope`, 스텁 관절 렌더 띠 아래 표식 아래로: Task 5 `testLegLengthMovesMarkerBelowHipsDownAndKeepsRowsAboveHips`). §7 → `EditorTool.body`(Task 6, `makeup`은 F), 분석 실패 안내(Task 6), `UserMessage` 도구 이름·전신 없음 문구(Task 6), 양방향 스냅은 기존 `Theme.bipolarSnapWidth`. 자동 보정은 체형을 건드리지 않음(`applyAuto` 불변). §8 → 각 Task 테스트, 순서 배열 불변, `AppModelTests`(Task 6), 시나리오의 다리 0.5(Task 6), 전체 검증·VALIDATION E 절(Task 7). §9 → 파일 이름과 주요 Task(Body 분석, BodyShapeRig, ShapeWarpStage 통합, 체형 도구)가 표와 같다.
- **C·D 이월:** (a) 잠금 → Task 1, (b) `bodies`·`bodyPrimitives` → Task 2·5, (c) band 패치 제한 → Task 3(지도 밖 계산 + 패치는 시작 행부터), (d) smoothstep → Task 3, (e) 정밀도 → Task 3(띠는 float 커널 계산, push는 RGBAh로 충분함을 근거로 적음, 640.25px 테스트), (f) 반지름 ≥ 이동 × 4 → Task 4(반지름 하한 + 테스트), (g) 프리셋·일괄 → B에서 구현됨을 Task 1에 적음, (h) 전신 없음·실패 안내 → Task 2·5·6.
- **타입 일관성:** `BodyGeometry(joints:confidence:boundingBox:)`·`point(_:minimumConfidence:)`·`area`, `BodySkeleton`(`torsoWidth`·`shoulderCenter`·`hipCenter`·`up`·`across`·`point`·`side(of:from:)`·`midpoint`·`lerp`), `VisionBodyAnalyzer.LocatedJoint`·`geometry(from:)`·`orderedLargestFirst`, `PhotoAnalysis(…bodies:bodyAnalysisFailure:)`, `PreparedPhoto.hasBody`·`bodyAnalysisFailure`, `PhotoPipeline.init(analyzer:personAnalyzer:bodyAnalyzer:tuning:lookCatalog:)`, `ShapePrimitive.isBand`, `DisplacementWarp.fieldBounds`·`maximumBands`, `BodyShapeRig.primitives(body:adjustments:extent:tuning:)`, `RenderTuning.bodyItemMaxShift(_:)`, `StubBodyAnalyzer(result:)`(패키지·앱 각각), `standingBody`(패키지 `(in:confidence:omitting:)`, 앱 `(in:)`)를 정의한 Task와 쓰는 Task에서 같게 썼다. 테스트 수: 패키지 258 → 263 → 274 → 279 → 289 → 293, 앱 Mac 56 → 59, iPhone·iPad 55 → 58.
- **Review Focus 매핑:** 1→Task 5(+Task 6), 2→Task 4·5, 3→Task 2·4, 4→Task 2·5, 5→Task 3·5. 모두 테스트 코드가 있다.
- **플레이스홀더 점검:** "TBD/TODO/나중에" 없음. Task 4의 접힘 테스트 실패 시 조치와 Task 7 문서 수치는 실제 실행 결과로 쓴다고 명시했다.
