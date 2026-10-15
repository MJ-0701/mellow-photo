# 인물 보정 C 얼굴 리셰이프 구현 계획

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 얼굴 폭 하나뿐이던 얼굴 탭을 얼굴 폭·턱선·광대·눈 크기·눈 간격·코 폭·입 크기·미소·이마·턱 길이 10개 슬라이더로 넓히고, 모든 얼굴형 변형을 이동량 지도 하나로 합쳐 한 번만 다시 그린다.

**Architecture:** MellowRendering/Domain에 이동 원소 `ShapePrimitive`(push·scale·band)와 원소를 RG float 이동량 지도로 더해 일반 커널 한 번으로 샘플링하는 `DisplacementWarp`를 둔다. `FaceFrame`이 눈동자 기준 얼굴 좌표계를 만들고 `FaceShapeRig`가 슬라이더 값을 원소 목록으로 바꾼다(값은 rig가 직접 범위로 자른다). `ShapeWarpStage`(이름 `shapeWarp`)가 `FaceReshapeStage`를 대체하고 체형 원소 자리(`bodyPrimitives`)를 빈 배열로 남긴다. 값 범위 정의는 MellowShared `AdjustmentRange`로 옮기고 `EditingPolicy`는 그대로 내보낸다. 앱은 뷰티 › 얼굴 탭에 슬라이더 10개를 둔다.

**Tech Stack:** Swift 5.9 tools / Swift 5 언어 모드, SwiftUI + Observation, Core Image(CIKL `CIColorKernel` 3개로 이동량 지도, CIKL `CIKernel` 1개로 샘플링), Vision(기존 얼굴 특징점), XCTest, XcodeGen 2.46.0.

**Spec:** `docs/superpowers/specs/2026-10-15-beauty-b-to-f-design.md` (C에 해당하는 절: 1.3, 1.5, 3, 7, 8, 9). B 실행 기록 `.superpowers/sdd/2026-10-15-beauty-b-skin/progress.md`의 C 이월 항목(ShapeWarpStage가 얼굴 키를 직접 클램프)을 포함한다.

## 사람이 확인할 것

- **순서.** Task 1 이동량 지도 → 2 얼굴 좌표계·공용 값 범위 → 3 얼굴형 원소 10종 → 4 얼굴 단계 교체(옛 얼굴 폭 변형 삭제) → 5 얼굴 탭 슬라이더 10개·시나리오 → 6 문서·전체 검증. 6개 Task, Task마다 Opus 구현 → 리뷰 → 수정, 끝에 전체 리뷰.
- **외부 효과가 있는 단계.** 없음. 푸시·태그·TestFlight는 F를 마친 뒤(스펙 "외부 효과가 있는 단계").
- **스펙이 정하지 않아 이 계획이 정한 것.**

| 결정 | 이유 | 바꾸면 비용 |
|---|---|---|
| 이동량 지도는 원소마다 작은 Core Image 커널을 이어 붙여 만들고(스펙의 그라데이션 + 덧셈 합성 대신), 샘플링은 일반 커널 하나 | 음수 이동량이 색 변환·알파 나눗셈에 깨지지 않고, 감쇠 모양이 기존 수동 변형과 같음. 빌드 경고(지원 중단 API) 4개가 늘어남 | 작음 |
| 원소 하나의 이동은 반지름의 25%까지(확대·축소 배율 0.25, 띠 늘림 25%) | 원소 하나로는 이미지가 접히지 않음. 슬라이더 10개를 모두 끝까지 올려도 접히지 않는지 테스트로 확인 | 작음 |
| 값 범위 정의를 공용 모듈로 옮기고 편집 규칙은 같은 이름으로 그대로 내보냄 | 렌더 모듈은 편집 모듈을 쓸 수 없고(모듈 규칙), 프리셋·일괄 적용 값은 편집 규칙을 거치지 않아 렌더가 직접 잘라야 함(B 리뷰 이월) | 작음 |
| 얼굴 방향은 눈동자로 정하고 입이 아래가 되게 맞춤. 눈 점이 없을 때만 Vision 기울기 값을 씀 | Vision 점 순서·좌우 이름과 사진 기울기에 영향받지 않음 | 작음 |
| 윤곽점은 순서가 아니라 높이로 고름(폭: 눈~입, 턱선: 입 아래, 광대: 각 쪽 맨 위 점, 턱 길이: 맨 아래 점). 같은 쪽 점들은 이동을 나눠 가짐 | 실제 윤곽이 눈 높이까지 안 올라올 수 있음. 점 개수와 관계없이 세기가 같음 | 작음 |
| 항목별 최대 이동(얼굴 폭 기준): 얼굴 폭 6%(실효 약 3.4%), 턱선 7%, 광대 4%, 눈 간격·코 폭 2%, 미소 2.5%, 이마·턱 길이 5%, 눈 크기 중심 1.22배, 입 크기 1.18배 | 메이투·Evoto의 "자연스러운 최대" 수준 어림. 실사진 피드백으로 `RenderTuning` 한 곳에서 조정 | 작음 |
| 특징점이 빠진 항목만 건너뜀. 윤곽점이 없는 얼굴은 모든 항목을 건너뜀 | 코 점이 없어도 얼굴 폭은 동작(스펙: 윤곽점 없으면 원소 없음) | 작음 |
| 옆얼굴 약화는 20°(0.35rad)에서 끊김 없이 시작해 옆얼굴(90°)에서 0 | 스펙의 cos 비율을 연속이 되도록 기준값으로 나눔 | 작음 |
| B0 "얼굴 미세 조정" 값은 얼굴 폭으로 계속 얼굴을 좁힘. 다만 특징점 없이 상자만 있는 얼굴은 이제 바뀌지 않음 | 스펙 규칙. Vision은 거의 항상 윤곽점을 줌 | 작음 |
| 체형 자리는 빈 함수 하나만 둠. 다리 길게용 띠 원소는 정의·테스트만 | E에서 채움. E의 API를 미리 만들지 않음 | 작음 |

- **범위 밖.** 체형 원소와 관절 분석(E), 눈·치아·입술 색 보정(D), 옆얼굴 전용 변형, 자동 보정의 얼굴형 값(스펙: 얼굴형은 사용자 선택).
- **위험.** 얼굴 가까운 문틀·벽 같은 직선이 살짝 휠 수 있다. 여러 슬라이더를 동시에 끝까지 올린 결과의 접힘 검사는 합성 얼굴로만 한다. 눈 점이 없는 얼굴에서 쓰는 Vision 기울기 값의 부호는 실사진으로 확인하지 않았다. 보정 품질은 자동 테스트로 판정할 수 없다.
- **사용자 조치.** 이 계획 안에는 없다. 실제 인물 사진으로 얼굴형 결과를 보는 것은 F 뒤 1.2.0 TestFlight에서 한다(스펙 사용자 조치).

---

## 에이전트 참조

## Global Constraints

- 작업 위치: worktree `/Users/mj/IdeaProjects/mellow-photo/.claude/worktrees/b0-basic-editing`, 브랜치 `beauty-b-to-f`(시작 HEAD `0114300`, B 구현·리뷰 완료). 부모 저장소로 `cd`하지 않는다. 모든 Swift·xcodebuild 명령 전에 `export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`.
- 모듈 의존성 표(`docs/architecture/modules.md`)와 `scripts/verify-modules.sh`는 바뀌지 않는다. MellowRendering의 import는 `CoreImage`·`Foundation`·`MellowShared`·`Vision`만 쓴다. MellowShared는 Foundation·CoreGraphics만. MellowRendering은 MellowEditing을 import할 수 없다(값 범위는 MellowShared `AdjustmentRange`).
- 새 보정은 MellowRendering 단계와 MellowShared 레시피 확장으로만 넣는다. 파이프라인 단계 이름 순서는 Task 4부터 `skin, shapeWarp, localEdit, geometry, color, detail, look`(Task 1~3 동안은 기존 `skin, faceReshape, …` 그대로).
- 레시피 `schemaVersion`은 2 유지, 키 추가만 한다(C는 레시피 키를 바꾸지 않는다). 옛 키 `portrait.skinSmoothing`·`portrait.faceSlim`은 읽기만 한다. v1 세션(평탄 배열 `undoHistory`)은 계속 읽힌다. 번들 ID `com.mj.mellowphoto`는 그대로.
- 값 범위: `face.*` −1…1, `smile` 0…1. 정의는 `AdjustmentRange` 한 곳, `EditingPolicy.unitRange`·`bipolarRange`·`faceShapeRange(_:)`·`clamped(_:to:)`는 같은 이름·시그니처로 그것을 내보낸다.
- 좌표는 정규화·원점 왼쪽 아래. 이동 원소와 이동량 지도는 extent 기준 픽셀이고 결과는 `out(p) = in(p − D(p))`.
- `RenderTuning` 새 상수 시작값: shapeDisplacementLimit 0.25, faceShapeYawThreshold 0.35, faceWidthMaxShift 0.06, faceJawMaxShift 0.07, faceCheekboneMaxShift 0.04, faceEyeSizeMaxScale 0.18, faceEyeDistanceMaxShift 0.02, faceNoseWidthMaxShift 0.02, faceMouthSizeMaxScale 0.15, faceSmileMaxShift 0.025, faceForeheadMaxShift 0.05, faceChinLengthMaxShift 0.05. 지우는 상수: faceSlimShiftFraction, faceSlimRadiusFraction, faceSlimAnchorX, faceSlimAnchorY.
- 한 줄 한 문장, 세미콜론 금지(CIKL 소스 문자열 안은 예외), 매직 넘버는 명명 상수(`RenderTuning`·`Theme`·`AppModel.Policy`·`EditingPolicy`, 기하 비율은 기존 `FallbackFeature`처럼 타입 안 `private static let`).
- 한국어 사용자 문구는 앱 타깃(`UserMessage`·뷰)에만. 모듈은 `MellowError`만 던진다.
- `cd apple && swift format lint --strict --recursive Sources Tests MellowPhoto MellowPhotoTests` 출력 없음(긴 줄은 줄바꿈으로 고친다). 허용된 빌드 경고: 기존 `CIWarpKernel` 지원 중단(`WarpKernel`), 기존 `CIColorKernel(source:)` 지원 중단(`SkinKernels`), 새 `CIColorKernel(source:)`·`CIKernel(source:)` 지원 중단(`DisplacementWarp`), 시뮬레이터 `usesCPUOnly`.
- `./scripts/verify-modules.sh` 통과. 전체 검증은 `./scripts/test-apple.sh`.
- 패키지 테스트: `cd apple && swift test`. Mac 앱 테스트: `xcodebuild -project apple/MellowPhoto.xcodeproj -scheme MellowPhoto -derivedDataPath apple/build -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO test 2>&1 | grep -E "Executed|TEST (SUCCEEDED|FAILED)|error:"`. 이 계획은 앱 파일을 더하거나 지우지 않으므로 `xcodegen generate`가 필요 없다(필요해지면 `apple/MellowPhoto.xcodeproj`도 커밋).
- iOS 시뮬레이터 테스트는 Task 6의 `./scripts/test-apple.sh` 전체 실행에서만 돌린다. Xcode를 열거나 앱을 직접 띄우거나 조작하지 않는다.
- 커밋: 한국어 Conventional Commits, 마지막 줄 `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`. `git add`는 Task에 나열한 경로만.
- 각 Task 끝에 패키지 테스트(앱을 건드렸으면 Mac 앱 테스트도)와 lint가 통과해야 다음으로 간다. 기준 테스트 수(시작 시점): 패키지 175(Shared 37 · Rendering 84 · Library 30 · Export 4 · Editing 20), 앱 iPhone 50 · iPad 50 · Mac 51.

## Review Focus

스펙이 암시하지만 스펙의 테스트 목록이 직접 다루지 않는 입력. 각 줄의 테스트를 소유 Task에 넣었다.

1. **손으로 고친 프리셋 파일이나 일괄 적용으로 범위 밖 얼굴형 값(width −3, smile −0.5)이 들어온다.** 렌더는 −1·0과 같아야 한다(프리셋·일괄 값은 편집 규칙의 클램프를 거치지 않는다). → Task 4 `testOutOfRangeFaceValuesRenderLikeClampedValues` (rig 수준은 Task 3 `testValuesOutsideRangeAreClamped`).
2. **실제 Vision 특징점(점 개수·순서·좌우 이름이 합성 얼굴과 다름).** 열 항목 모두 원소가 생기고 얼굴 폭 −1은 중심선 쪽을 향해야 한다. → Task 3 `testDemoPortraitLandmarksDriveEveryKey`.
3. **슬라이더 10개를 모두 끝까지 올린다.** 겹친 원소의 합으로 이미지가 접히거나 찢어지지 않아야 한다. → Task 3 `testExtremeCombinationsNeverFold`.
4. **고개를 돌린 얼굴(Vision yaw ±π/4, ±π/2).** 약해지되 0.35rad에서 끊기지 않고, 옆얼굴에서는 아무것도 바꾸지 않아야 한다. → Task 3 `testYawAttenuatesContinuouslyAndVanishesAtProfile`.
5. **얼굴이 사진 가장자리에 붙어 원소가 이미지 밖에 걸친다.** 크기는 그대로이고 가장자리에 투명·검은 띠가 없어야 한다. → Task 1 `testPushNearEdgeKeepsExtentAndOpaqueEdges`.

## 인터페이스 요약 (모든 Task가 공유하는 이름)

```swift
// MellowShared (Task 2)
public enum AdjustmentRange { static unit, bipolar; static faceShape(_ key: FaceShapeKey) -> ClosedRange<Double>; static clamped(_:to:) -> Double }

// MellowEditing (Task 2) — 이름·시그니처 그대로, 값은 AdjustmentRange에서
public enum EditingPolicy { historyLimit, unitRange, bipolarRange, faceShapeRange(_:), clamped(_:to:) }

// MellowRendering (internal)
enum ShapePrimitive: Equatable, Sendable {                         // Task 1
    case push(center: CGPoint, vector: CGVector, radius: CGFloat)
    case scale(center: CGPoint, factor: CGFloat, radius: CGFloat)
    case band(yStart: CGFloat, yEnd: CGFloat, stretch: CGFloat)
    static func falloff(distance: CGFloat, radius: CGFloat) -> CGFloat
    func limited(to limit: Double) -> ShapePrimitive
    var isIdentity: Bool
    var maxDisplacement: CGFloat
    func displacement(at point: CGPoint) -> CGVector
}
final class DisplacementWarp {                                     // Task 1
    static let shared
    func apply(_ primitives: [ShapePrimitive], to image: CIImage, extent: CGRect, limit: Double) throws -> CIImage
    func displacementField(_ primitives: [ShapePrimitive], extent: CGRect) throws -> CIImage
    static func displacement(at point: CGPoint, of primitives: [ShapePrimitive], limit: Double) -> CGVector
}
struct FaceFrame {                                                  // Task 2
    struct Eye { center: CGPoint; width: CGFloat }
    init?(face: FaceGeometry, extent: CGRect)
    origin, xAxis, yAxis, faceWidth, contour, eyeLevel, mouthLevel, eyes
    func local(_ point: CGPoint) -> CGPoint
    func imagePoint(u: CGFloat, v: CGFloat) -> CGPoint
    func vector(u: CGFloat, v: CGFloat) -> CGVector
    func points(_ landmark: FaceLandmark) -> [CGPoint]
    static func centroid(_ points: [CGPoint]) -> CGPoint
}
enum FaceShapeRig {                                                 // Task 3
    static func primitives(face: FaceGeometry, adjustments: FaceShapeAdjustments, extent: CGRect, tuning: RenderTuning) -> [ShapePrimitive]
    static func yawAttenuation(_ yaw: Double?, tuning: RenderTuning) -> Double
}
struct ShapeWarpStage: RenderStage {                                // Task 4, name "shapeWarp"
    func facePrimitives(in context: RenderContext) -> [ShapePrimitive]
    func bodyPrimitives(in context: RenderContext) -> [ShapePrimitive]   // E가 채움, C에서는 []
}
RenderTuning: + shapeDisplacementLimit (Task 1), faceShapeYawThreshold·face…MaxShift/MaxScale 10개·faceShapeMaxShift(_:) (Task 3), − faceSlim… 4개 (Task 4)
삭제: FaceReshapeStage (Task 4)

// 테스트 지원 (apple/Tests/MellowRenderingTests/RenderingTestSupport.swift)
RenderingTestSupport.markers(_:extent:), markerCentroid(_:near:window:), expectedPosition(of:primitives:limit:)   // Task 1
SyntheticFace.pivot, FaceGeometry.rotated(by:about:), FaceGeometry.removing(_:)                                    // Task 2
RenderingTestSupport.minimumJacobian(of:limit:in:)                                                                 // Task 3
FaceGeometry.transformed(scale:offset:)                                                                            // Task 4

// 앱 (Task 5)
UserMessage.faceShapeTitle(_ key: FaceShapeKey) -> String   // UserMessage.faceWidth 삭제
BeautyPanel 얼굴 탭: FaceShapeKey.allCases 순서 슬라이더 10개
TestSupport.landmarkedFace(in: NormalizedRect) -> FaceGeometry   (apple/MellowPhotoTests/TestSupport.swift)
```

---

### Task 1: DisplacementWarp — 이동 원소를 한 번에 샘플링하는 이동량 지도

**Files:**
- Create: `apple/Sources/MellowRendering/Domain/ShapePrimitive.swift`
- Create: `apple/Sources/MellowRendering/Domain/DisplacementWarp.swift`
- Modify: `apple/Sources/MellowRendering/API/RenderTuning.swift` (`shapeDisplacementLimit`)
- Modify: `apple/Tests/MellowRenderingTests/RenderingTestSupport.swift` (점 표식·무게 중심·예상 위치)
- Test: `apple/Tests/MellowRenderingTests/DisplacementWarpTests.swift`

**Interfaces:**
- Consumes: `MellowError.warpUnavailable`·`renderFailed`, `RenderTuning`, 테스트 지원 `PixelGrid`·`hardEllipse`·`gradient`·`grid`·`bytes`.
- Produces: `enum ShapePrimitive`(`push(center:vector:radius:)`, `scale(center:factor:radius:)`, `band(yStart:yEnd:stretch:)`, `static falloff(distance:radius:)`, `limited(to:)`, `isIdentity`, `maxDisplacement`, `displacement(at:)`), `final class DisplacementWarp`(`shared`, `apply(_:to:extent:limit:) throws -> CIImage`, `displacementField(_:extent:) throws -> CIImage`, `static displacement(at:of:limit:) -> CGVector`), `RenderTuning.shapeDisplacementLimit`(0.25). 테스트 지원: `RenderingTestSupport.markers(_:extent:)`, `markerCentroid(_:near:window:)`, `expectedPosition(of:primitives:limit:)`, 상수 `markerRadius`·`markerThreshold`·`pixelCenterOffset`·`fixedPointIterations`.

방식 근거:
- **래스터 방식.** 스펙 1.5는 `CIRadialGradient`·`CIConstantColor`·`CIAdditionCompositing`을 적었지만 그 경로는 음수 이동량을 색으로 다룬다. `CIColor`는 sRGB로 해석돼 작업 색공간(선형)으로 비선형 변환되고, 그라데이션 알파는 사전곱 나눗셈을 거친다. 대신 0(검정, 알파 1)에서 시작해 원소마다 CIKL 색 커널 하나(`pushField`·`scaleField`·`bandField`)로 `field.rg`에 그 원소의 이동량을 더한다. 출력 알파는 늘 1이라 사전곱이 값을 바꾸지 않는다. 지도는 화면에 그리지 않으므로 출력 색 변환도 없다. 색 커널은 Core Image가 한 프로그램으로 합친다. 감쇠는 `WarpKernel`과 같은 smoothstep `t = clamp(1 − d/r)`, `w = t²(3 − 2t)`.
- **샘플링 커널.** `CIWarpKernel`은 `destCoord()`와 균일 인자만 받고 이미지를 읽지 못해 지도를 쓸 수 없다. 그래서 일반 `CIKernel` 하나가 `sample(field)`로 이동량을 읽고 `sample(image, samplerTransform(image, destCoord() − d))`로 한 번만 샘플링한다. 입력은 `clampedToExtent()`라 가장자리에 투명 띠가 없다. ROI는 원소 최대 이동의 합 + 2px.
- **원소 정의.** push: `D = vector × w`. scale: `D = (p − c) × factor × w`(양수면 확대, 중심 선형 배율 1/(1 − factor)). band: `span = yEnd − yStart`, `t = clamp((y − yStart)/span)`, `D = (0, stretch × span × t)` — 띠 안은 늘어나고 yEnd 너머는 `stretch × span`만큼 통째로 밀린다(E 다리 길게용, C에서는 정의·테스트만). `y − D_y(y)`의 기울기가 `1 − stretch`라 |stretch| < 1이면 단조·연속.
- **원소별 상한.** push는 |vector| ≤ radius × limit, scale은 |factor| ≤ limit(최대 이동 ≤ radius × limit), band는 |stretch| ≤ limit. limit 0.25에서 원소 하나의 야코비안은 0.625 이상이라 접히지 않는다. 지도는 작업 형식(기본 RGBAh) float이라 48MP 얼굴(이동 200px 안팎)에서도 오차 0.125px 이하다.

- [ ] **Step 1: 테스트 지원 코드**

`RenderingTestSupport.swift`의 `enum RenderingTestSupport` 안, `hardEllipse` 아래에 추가:

```swift
    /// 변형 테스트의 점 표식 반지름(픽셀).
    static let markerRadius: CGFloat = 3
    /// 이 빨강 값보다 어두운 픽셀을 표식으로 본다. 바탕(0.9 회색)은 sRGB 바이트로 약 230이다.
    static let markerThreshold: UInt8 = 200
    /// 픽셀 (x, y)의 중심은 (x + 0.5, y + 0.5)다.
    static let pixelCenterOffset = 0.5
    /// expectedPosition의 고정점 반복 횟수. 이동량 기울기가 0.5 아래라 30번이면 충분히 수렴한다.
    static let fixedPointIterations = 30

    /// 밝은 회색(0.9) 바탕에 반지름 markerRadius인 검은 점들. 점은 hardEllipse로 픽셀 크기에서 그린다.
    static func markers(_ centers: [CGPoint], extent: CGRect) -> CIImage {
        var image = CIImage(color: CIColor(red: 0.9, green: 0.9, blue: 0.9)).cropped(to: extent)
        let dot = CIImage(color: .black)
        let radii = CGSize(width: markerRadius, height: markerRadius)
        for center in centers {
            let mask = hardEllipse(center: center, radii: radii, extent: extent)
            image = dot.applyingFilter(
                "CIBlendWithMask", parameters: [kCIInputBackgroundImageKey: image, kCIInputMaskImageKey: mask]
            ).cropped(to: extent)
        }
        return image
    }

    /// point 둘레 ±window 픽셀 안 어두운 픽셀의 가중 중심(가중치 = markerThreshold − 빨강). 없으면 nil.
    static func markerCentroid(_ grid: PixelGrid, near point: CGPoint, window: Int = 16) -> CGPoint? {
        var total: Double = 0
        var sumX: Double = 0
        var sumY: Double = 0
        let centerX = Int(point.x)
        let centerY = Int(point.y)
        for y in max(0, centerY - window)...min(grid.height - 1, centerY + window) {
            for x in max(0, centerX - window)...min(grid.width - 1, centerX + window) {
                let weight = Double(markerThreshold) - Double(grid.red(CGPoint(x: x, y: y)))
                guard weight > 0 else { continue }
                total += weight
                sumX += weight * (Double(x) + pixelCenterOffset)
                sumY += weight * (Double(y) + pixelCenterOffset)
            }
        }
        guard total > 0 else { return nil }
        return CGPoint(x: sumX / total, y: sumY / total)
    }

    /// out(p) = in(p − D(p))에서 입력의 marker가 나타나는 출력 위치. p = marker + D(p)를 고정점 반복으로 푼다.
    static func expectedPosition(of marker: CGPoint, primitives: [ShapePrimitive], limit: Double) -> CGPoint {
        var position = marker
        for _ in 0..<fixedPointIterations {
            let shift = DisplacementWarp.displacement(at: position, of: primitives, limit: limit)
            position = CGPoint(x: marker.x + shift.dx, y: marker.y + shift.dy)
        }
        return position
    }
```

- [ ] **Step 2: 실패하는 테스트 작성**

`apple/Tests/MellowRenderingTests/DisplacementWarpTests.swift`:

```swift
import CoreImage
import MellowShared
import XCTest

@testable import MellowRendering

final class DisplacementWarpTests: XCTestCase {
    typealias Support = RenderingTestSupport

    /// 점의 무게 중심이 예상 위치에서 벗어나도 되는 거리(픽셀). 쌍선형 샘플링과 점 가장자리 안티에일리어싱 몫.
    private static let tolerance: CGFloat = 0.75
    private let extent = CGRect(x: 0, y: 0, width: 128, height: 128)
    private let center = CGPoint(x: 64, y: 64)
    private let limit = RenderTuning().shapeDisplacementLimit

    private func warp(_ image: CIImage, _ primitives: [ShapePrimitive]) throws -> CIImage {
        try DisplacementWarp.shared.apply(primitives, to: image, extent: image.extent, limit: limit)
    }

    /// 점 하나를 그린 이미지를 변형하고 옮겨진 점의 무게 중심을 돌려준다.
    private func moved(_ marker: CGPoint, by primitives: [ShapePrimitive]) throws -> CGPoint {
        let output = try warp(Support.markers([marker], extent: extent), primitives)
        let expected = Support.expectedPosition(of: marker, primitives: primitives, limit: limit)
        return try XCTUnwrap(Support.markerCentroid(Support.grid(output), near: expected))
    }

    private func assertNear(
        _ actual: CGPoint, _ expected: CGPoint, file: StaticString = #filePath, line: UInt = #line
    ) {
        XCTAssertEqual(actual.x, expected.x, accuracy: Self.tolerance, file: file, line: line)
        XCTAssertEqual(actual.y, expected.y, accuracy: Self.tolerance, file: file, line: line)
    }

    func testNoPrimitivesReturnsInputBytes() throws {
        let input = Support.gradient()
        XCTAssertEqual(try Support.bytes(warp(input, [])), try Support.bytes(input))
        let idle = ShapePrimitive.push(center: CGPoint(x: 64, y: 40), vector: CGVector(dx: 0, dy: 0), radius: 20)
        XCTAssertEqual(try Support.bytes(warp(input, [idle])), try Support.bytes(input), "이동량 0인 원소만 있으면 그대로")
    }

    func testPushMovesMarkerAlongVector() throws {
        let push = ShapePrimitive.push(center: center, vector: CGVector(dx: 6, dy: 3), radius: 40)
        let result = try moved(center, by: [push])
        assertNear(result, Support.expectedPosition(of: center, primitives: [push], limit: limit))
        XCTAssertGreaterThan(result.x - center.x, 5, "벡터 방향(+x)으로 5px 넘게 움직인다")
        XCTAssertGreaterThan(result.y - center.y, 2, "벡터 방향(+y)으로 움직인다")
    }

    func testNegativePushMovesMarkerBack() throws {
        let push = ShapePrimitive.push(center: center, vector: CGVector(dx: -6, dy: -3), radius: 40)
        let result = try moved(center, by: [push])
        assertNear(result, Support.expectedPosition(of: center, primitives: [push], limit: limit))
        XCTAssertLessThan(result.x - center.x, -5, "음수 이동량이 지도에서 잘리지 않는다")
    }

    func testTwoPushesAddTheirShifts() throws {
        let right = ShapePrimitive.push(center: center, vector: CGVector(dx: 5, dy: 0), radius: 40)
        let up = ShapePrimitive.push(center: center, vector: CGVector(dx: 0, dy: 4), radius: 40)
        let rightOnly = try moved(center, by: [right])
        let upOnly = try moved(center, by: [up])
        let both = try moved(center, by: [right, up])
        let summedX = (rightOnly.x - center.x) + (upOnly.x - center.x)
        let summedY = (rightOnly.y - center.y) + (upOnly.y - center.y)
        XCTAssertEqual(both.x - center.x, summedX, accuracy: 1, "두 원소의 이동은 각각의 합과 비슷하다")
        XCTAssertEqual(both.y - center.y, summedY, accuracy: 1)
    }

    func testScaleMagnifiesAroundCenter() throws {
        let scale = ShapePrimitive.scale(center: center, factor: 0.2, radius: 40)
        let left = CGPoint(x: center.x - 12, y: center.y)
        let right = CGPoint(x: center.x + 12, y: center.y)
        let grid = try Support.grid(warp(Support.markers([left, right], extent: extent), [scale]))
        let expectedLeft = Support.expectedPosition(of: left, primitives: [scale], limit: limit)
        let expectedRight = Support.expectedPosition(of: right, primitives: [scale], limit: limit)
        let movedLeft = try XCTUnwrap(Support.markerCentroid(grid, near: expectedLeft, window: 8))
        let movedRight = try XCTUnwrap(Support.markerCentroid(grid, near: expectedRight, window: 8))
        assertNear(movedLeft, expectedLeft)
        assertNear(movedRight, expectedRight)
        XCTAssertGreaterThan(movedRight.x - movedLeft.x, 26, "두 점 사이 24px가 넓어진다")
    }

    func testDisplacementIsLimitedPerPrimitive() throws {
        let push = ShapePrimitive.push(center: center, vector: CGVector(dx: 100, dy: 0), radius: 40)
        XCTAssertEqual(push.limited(to: limit), .push(center: center, vector: CGVector(dx: 10, dy: 0), radius: 40))
        XCTAssertEqual(
            ShapePrimitive.scale(center: center, factor: 3, radius: 40).limited(to: limit),
            .scale(center: center, factor: 0.25, radius: 40))
        XCTAssertEqual(
            ShapePrimitive.band(yStart: 96, yEnd: 32, stretch: -2).limited(to: limit),
            .band(yStart: 96, yEnd: 32, stretch: -0.25))
        let result = try moved(center, by: [push])
        assertNear(result, Support.expectedPosition(of: center, primitives: [push], limit: limit))
        XCTAssertLessThan(result.x - center.x, 10.5, "반지름 × 0.25를 넘지 않는다")
    }

    func testBandMappingIsMonotoneAndContinuous() {
        let band = ShapePrimitive.band(yStart: 96, yEnd: 32, stretch: 0.08)
        let step: CGFloat = 0.5
        var previousSource = -CGFloat.infinity
        var previousShift = band.displacement(at: CGPoint(x: 0, y: 0)).dy
        for index in 0...256 {
            let y = CGFloat(index) * step
            let shift = band.displacement(at: CGPoint(x: 0, y: y)).dy
            let source = y - shift
            XCTAssertGreaterThan(source, previousSource, "출력 y가 커지면 읽는 입력 y도 커진다(접힘 없음) y=\(y)")
            XCTAssertLessThanOrEqual(abs(shift - previousShift), step * 0.08 + 1e-9, "끊김 없음 y=\(y)")
            previousSource = source
            previousShift = shift
        }
        XCTAssertEqual(band.displacement(at: CGPoint(x: 0, y: 10)).dy, -5.12, accuracy: 1e-9, "띠 아래 내용은 5.12px 내려온다")
        XCTAssertEqual(band.displacement(at: CGPoint(x: 0, y: 10)).dx, 0)
        XCTAssertEqual(band.displacement(at: CGPoint(x: 0, y: 110)).dy, 0, "띠 위는 그대로")
    }

    func testBandMovesMarkerBeyondBand() throws {
        let band = ShapePrimitive.band(yStart: 96, yEnd: 32, stretch: 0.08)
        let below = CGPoint(x: 64, y: 20)
        let above = CGPoint(x: 64, y: 110)
        let input = Support.markers([below, above], extent: extent)
        let before = try Support.grid(input)
        let after = try Support.grid(warp(input, [band]))
        let movedBelow = try XCTUnwrap(Support.markerCentroid(after, near: CGPoint(x: 64, y: 15), window: 8))
        let originalBelow = try XCTUnwrap(Support.markerCentroid(before, near: below, window: 8))
        let movedAbove = try XCTUnwrap(Support.markerCentroid(after, near: above, window: 8))
        let originalAbove = try XCTUnwrap(Support.markerCentroid(before, near: above, window: 8))
        XCTAssertEqual(movedBelow.y, originalBelow.y - 5.12, accuracy: Self.tolerance)
        XCTAssertEqual(movedBelow.x, originalBelow.x, accuracy: 0.25)
        XCTAssertEqual(movedAbove.y, originalAbove.y, accuracy: 0.25)
    }

    func testPushNearEdgeKeepsExtentAndOpaqueEdges() throws {
        let input = Support.gradient()
        let push = ShapePrimitive.push(center: CGPoint(x: 2, y: 40), vector: CGVector(dx: 8, dy: 0), radius: 32)
        let output = try warp(input, [push])
        XCTAssertEqual(output.extent, input.extent)
        let after = try Support.grid(output)
        let before = try Support.grid(input)
        XCTAssertEqual(after.rgba(CGPoint(x: 0, y: 40))[3], 255, "가장자리는 바깥 픽셀을 늘려 채워 불투명")
        XCTAssertNotEqual(after.rgba(CGPoint(x: 6, y: 40)), before.rgba(CGPoint(x: 6, y: 40)), "가장자리 근처가 움직인다")
        XCTAssertEqual(after.rgba(CGPoint(x: 100, y: 40)), before.rgba(CGPoint(x: 100, y: 40)), "반지름 밖은 그대로")
    }
}
```

- [ ] **Step 3: 실패 확인**

Run: `cd apple && swift test --filter DisplacementWarpTests` → 컴파일 실패(`cannot find 'DisplacementWarp' in scope`, `cannot find type 'ShapePrimitive'`).

- [ ] **Step 4: 구현**

`RenderTuning.swift`: `warpDisplacementLimit` 줄 아래에 추가:

```swift
    /// 얼굴형·체형 원소 하나가 옮기는 최대 거리. push는 반지름 비율, scale은 배율, band는 늘림 비율.
    /// smoothstep 감쇠의 최대 기울기가 1.5 / 반지름이라 0.25면 원소 하나의 야코비안이 0.625 이상으로 접히지 않는다.
    public var shapeDisplacementLimit: Double = 0.25
```

`apple/Sources/MellowRendering/Domain/ShapePrimitive.swift`:

```swift
import CoreImage

/// 이동량 지도에 더하는 원소. 좌표·길이는 extent 기준 픽셀이고 원점은 왼쪽 아래다.
/// 결과는 out(p) = in(p − D(p))라서 내용은 원소의 이동 방향으로 움직인다.
enum ShapePrimitive: Equatable, Sendable {
    /// center에서 radius 안을 smoothstep 감쇠로 vector만큼 민다.
    case push(center: CGPoint, vector: CGVector, radius: CGFloat)
    /// center 기준 반경 방향으로 확대(factor > 0)하거나 축소(< 0)한다. 중심의 선형 배율은 1 / (1 − factor).
    case scale(center: CGPoint, factor: CGFloat, radius: CGFloat)
    /// yStart에서 yEnd까지의 가로 띠를 yEnd 쪽으로 늘린다. yEnd 너머는 stretch × (yEnd − yStart)만큼 통째로 밀린다.
    case band(yStart: CGFloat, yEnd: CGFloat, stretch: CGFloat)

    /// smoothstep 감쇠. t = clamp(1 − d / r), w = t²(3 − 2t). WarpKernel과 같은 모양이다.
    static func falloff(distance: CGFloat, radius: CGFloat) -> CGFloat {
        guard radius > 0 else { return 0 }
        let t = min(1, max(0, 1 - distance / radius))
        return t * t * (3 - 2 * t)
    }

    /// 원소 하나의 최대 이동을 제한한다. push는 |vector| ≤ radius × limit, scale은 |factor| ≤ limit, band는 |stretch| ≤ limit.
    func limited(to limit: Double) -> ShapePrimitive {
        let cap = CGFloat(limit)
        switch self {
        case .push(let center, let vector, let radius):
            let length = hypot(vector.dx, vector.dy)
            let maximum = max(0, radius) * cap
            guard length > maximum, length > 0 else { return self }
            let limitedVector = CGVector(dx: vector.dx * maximum / length, dy: vector.dy * maximum / length)
            return .push(center: center, vector: limitedVector, radius: radius)
        case .scale(let center, let factor, let radius):
            return .scale(center: center, factor: min(cap, max(-cap, factor)), radius: radius)
        case .band(let yStart, let yEnd, let stretch):
            return .band(yStart: yStart, yEnd: yEnd, stretch: min(cap, max(-cap, stretch)))
        }
    }

    /// 아무것도 옮기지 않는 원소. 렌더에서 뺀다.
    var isIdentity: Bool {
        switch self {
        case .push(_, let vector, let radius):
            return radius <= 0 || (vector.dx == 0 && vector.dy == 0)
        case .scale(_, let factor, let radius):
            return radius <= 0 || factor == 0
        case .band(let yStart, let yEnd, let stretch):
            return stretch == 0 || yStart == yEnd
        }
    }

    /// 이 원소가 옮길 수 있는 최대 거리(픽셀). 샘플링 ROI 여백에 쓴다.
    var maxDisplacement: CGFloat {
        switch self {
        case .push(_, let vector, _):
            return hypot(vector.dx, vector.dy)
        case .scale(_, let factor, let radius):
            return abs(factor) * radius
        case .band(let yStart, let yEnd, let stretch):
            return abs(stretch * (yEnd - yStart))
        }
    }

    /// DisplacementWarp 커널과 같은 식의 CPU 참조 구현. 테스트와 접힘 검사에 쓴다.
    func displacement(at point: CGPoint) -> CGVector {
        switch self {
        case .push(let center, let vector, let radius):
            let w = Self.falloff(distance: hypot(point.x - center.x, point.y - center.y), radius: radius)
            return CGVector(dx: vector.dx * w, dy: vector.dy * w)
        case .scale(let center, let factor, let radius):
            let offset = CGVector(dx: point.x - center.x, dy: point.y - center.y)
            let w = Self.falloff(distance: hypot(offset.dx, offset.dy), radius: radius)
            return CGVector(dx: offset.dx * factor * w, dy: offset.dy * factor * w)
        case .band(let yStart, let yEnd, let stretch):
            let span = yEnd - yStart
            guard span != 0 else { return .zero }
            let t = min(1, max(0, (point.y - yStart) / span))
            return CGVector(dx: 0, dy: stretch * span * t)
        }
    }
}
```

`apple/Sources/MellowRendering/Domain/DisplacementWarp.swift`:

```swift
import CoreImage
import MellowShared

/// 얼굴형·체형 이동 원소를 이동량 지도 하나로 더해 한 번만 샘플링한다.
/// 지도는 R = dx, G = dy(픽셀)인 작업 형식 float 이미지이고 결과는 out(p) = in(p − D(p))다.
/// 지도 색 커널 3개와 샘플링 일반 커널 1개를 감싸는 유일한 자리. Metal로 바꿀 때 이 타입만 바꾼다.
/// CIWarpKernel은 균일 인자만 받고 이미지를 읽을 수 없어 지도를 샘플링하려면 일반 커널이 필요하다.
final class DisplacementWarp: @unchecked Sendable {
    static let shared = DisplacementWarp()

    /// ROI를 최대 이동보다 이만큼(픽셀) 더 넓혀 쌍선형 샘플링이 잘리지 않게 한다.
    private static let roiPadding: CGFloat = 2
    /// 샘플링 커널에서 입력 이미지 인자의 순서. ROI 콜백이 인덱스로 구분한다.
    private static let imageArgumentIndex: Int32 = 0

    private let pushField: CIColorKernel?
    private let scaleField: CIColorKernel?
    private let bandField: CIColorKernel?
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
        bandField = CIColorKernel(
            source: """
                kernel vec4 bandField(__sample field, float yStart, float span, float stretch) {
                    float t = clamp((destCoord().y - yStart) / span, 0.0, 1.0);
                    return vec4(field.r, field.g + stretch * span * t, 0.0, 1.0);
                }
                """)
        sampler = CIKernel(
            source: """
                kernel vec4 displacedSample(sampler image, sampler field) {
                    vec2 d = sample(field, samplerCoord(field)).rg;
                    return sample(image, samplerTransform(image, destCoord() - d));
                }
                """)
    }

    /// 원소마다 limit를 적용한 뒤 한 번 샘플링한다. 남는 원소가 없으면 입력을 그대로 돌려준다.
    func apply(_ primitives: [ShapePrimitive], to image: CIImage, extent: CGRect, limit: Double) throws -> CIImage {
        let effective = primitives.map { $0.limited(to: limit) }.filter { !$0.isIdentity }
        guard !effective.isEmpty else { return image }
        guard let sampler else { throw MellowError.warpUnavailable }
        let field = try displacementField(effective, extent: extent)
        let margin = effective.reduce(Self.roiPadding) { $0 + $1.maxDisplacement }
        let arguments: [Any] = [image.clampedToExtent(), field]
        let warped = sampler.apply(
            extent: extent,
            roiCallback: { index, rect in
                index == Self.imageArgumentIndex ? rect.insetBy(dx: -margin, dy: -margin) : rect
            },
            arguments: arguments)
        guard let warped else { throw MellowError.renderFailed }
        return warped.cropped(to: extent)
    }

    /// 원소들의 이동량 합. 0에서 시작해 원소마다 색 커널 하나를 이어 붙인다.
    func displacementField(_ primitives: [ShapePrimitive], extent: CGRect) throws -> CIImage {
        var field = CIImage(color: CIColor(red: 0, green: 0, blue: 0, alpha: 1)).cropped(to: extent)
        for primitive in primitives {
            field = try accumulate(primitive, onto: field, extent: extent)
        }
        return field
    }

    /// CPU 참조. 원소마다 limit를 적용한 이동량의 합.
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
        case .band(let yStart, let yEnd, let stretch):
            kernel = bandField
            arguments = [field, yStart, yEnd - yStart, stretch]
        }
        guard let kernel else { throw MellowError.warpUnavailable }
        guard let output = kernel.apply(extent: extent, arguments: arguments) else { throw MellowError.renderFailed }
        return output
    }
}
```

예외 경로(커널 언어가 색 커널의 `destCoord()`를 거부해 세 `CIColorKernel(source:)`가 nil이면 테스트가 `warpUnavailable`로 실패한다): 세 지도 커널을 `CIKernel(source:)`로 바꾸고 소스에서 `__sample field` → `sampler field`, `field.rg`·`field.r`·`field.g` → `sample(field, samplerCoord(field)).rg`·`.r`·`.g`로 바꾼 뒤 `apply(extent:roiCallback: { _, rect in rect }, arguments:)`로 부른다. 이 경우 커밋 메시지 본문에 한 줄 적는다.

- [ ] **Step 5: 통과 확인**

Run: `cd apple && swift test --filter DisplacementWarpTests` → 9개 PASS. 이어서 `cd apple && swift test` → `Executed 184 tests, with 0 failures`(Shared 37 · Rendering 93 · Library 30 · Export 4 · Editing 20). lint 출력 없음. `./scripts/verify-modules.sh` 통과.

- [ ] **Step 6: 커밋**

```bash
git add apple/Sources/MellowRendering/Domain/ShapePrimitive.swift apple/Sources/MellowRendering/Domain/DisplacementWarp.swift apple/Sources/MellowRendering/API/RenderTuning.swift apple/Tests/MellowRenderingTests/RenderingTestSupport.swift apple/Tests/MellowRenderingTests/DisplacementWarpTests.swift
git commit -m "feat(rendering): 이동 원소를 한 번에 샘플링하는 이동량 지도 추가

push·scale·band 원소를 색 커널로 RG float 지도에 더하고 일반 커널 하나로
out(p) = in(p − D(p))를 샘플링한다. 원소마다 반지름 × 0.25로 이동을 제한한다.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 2: 공용 값 범위와 얼굴 좌표계 — AdjustmentRange, FaceFrame

**Files:**
- Create: `apple/Sources/MellowShared/API/AdjustmentRange.swift`
- Modify: `apple/Sources/MellowEditing/API/EditingPolicy.swift` (전체 교체, 이름·시그니처 유지)
- Create: `apple/Sources/MellowRendering/Domain/FaceFrame.swift`
- Modify: `apple/Tests/MellowRenderingTests/RenderingTestSupport.swift` (`SyntheticFace.pivot`, `FaceGeometry.rotated(by:about:)`·`removing(_:)`)
- Test: `apple/Tests/MellowRenderingTests/FaceFrameTests.swift`, `apple/Tests/MellowEditingTests/EditDocumentTests.swift`

**Interfaces:**
- Consumes: `FaceGeometry`, `FaceLandmark`, `FaceShapeKey`, `FaceRegions.pixelRect(_:in:)`.
- Produces: `public enum AdjustmentRange`(`unit`, `bipolar`, `faceShape(_:)`, `clamped(_:to:)`). `EditingPolicy`는 같은 이름으로 내보낸다. `struct FaceFrame`(internal) — `struct Eye { center: CGPoint; width: CGFloat }`, `init?(face:extent:)`, `origin`, `xAxis`, `yAxis`, `faceWidth`, `contour: [CGPoint]`, `eyeLevel`, `mouthLevel`(얼굴 좌표 v), `eyes: [Eye]`, `local(_:) -> CGPoint`(u, v), `imagePoint(u:v:)`, `vector(u:v:)`, `points(_:) -> [CGPoint]`, `static centroid(_:)`. 테스트 지원: `SyntheticFace.pivot`, `FaceGeometry.rotated(by:about:)`, `FaceGeometry.removing(_:)`.

좌표계 근거: 원점은 스펙대로 얼굴 상자 중심. x축은 두 눈동자(없으면 두 눈 영역 중심)를 잇는 방향이라 기울어진 얼굴의 roll이 저절로 반영된다. 두 눈이 없거나 얼굴 폭의 5%보다 가까우면 `FaceGeometry.roll`(반시계 양수로 해석, 실사진 미검증)을, 그것도 없으면 가로를 쓴다. y축은 x축을 반시계 90° 돌린 방향이고, 눈 중심이 입(바깥 입술 중심, 없으면 윤곽 중심) 쪽보다 아래로 나오면 두 축을 함께 뒤집는다. 그래서 Vision의 `leftEye`·`rightEye` 이름이 화면 기준인지 사람 기준인지와 무관하다. 눈·입 높이는 특징점이 없으면 `FaceRegions`의 대체 부위 위치(눈 중심 상자 높이 0.63, 입 0.27)를 상자 중심 기준으로 옮긴 값(+0.13, −0.23)을 쓴다.

- [ ] **Step 1: 테스트 지원 코드**

`RenderingTestSupport.swift`의 `struct SyntheticFace` 안, `static var extent` 아래에 추가:

```swift
    /// 얼굴 상자 중심(256, 200)의 정규화 좌표. 회전 테스트의 회전 중심.
    static var pivot: NormalizedPoint {
        NormalizedPoint(x: Double(box.midX) / Double(size), y: Double(box.midY) / Double(size))
    }
```

파일 맨 아래에 추가:

```swift
extension FaceGeometry {
    /// 특징점을 pivot 둘레로 angle만큼 반시계로 돌리고 roll을 angle로 둔다. 상자는 그대로다. 정사각형 extent에서만 쓴다.
    func rotated(by angle: Double, about pivot: NormalizedPoint) -> FaceGeometry {
        let cosine = cos(angle)
        let sine = sin(angle)
        var turned: [FaceLandmark: [NormalizedPoint]] = [:]
        for (landmark, points) in landmarks {
            turned[landmark] = points.map { point in
                let dx = point.x - pivot.x
                let dy = point.y - pivot.y
                return NormalizedPoint(x: pivot.x + dx * cosine - dy * sine, y: pivot.y + dx * sine + dy * cosine)
            }
        }
        return FaceGeometry(boundingBox: boundingBox, landmarks: turned, roll: angle, yaw: yaw)
    }

    /// 주어진 특징점을 뺀다.
    func removing(_ removed: [FaceLandmark]) -> FaceGeometry {
        var copy = self
        for landmark in removed {
            copy.landmarks[landmark] = nil
        }
        return copy
    }
}
```

- [ ] **Step 2: 실패하는 테스트 작성**

`EditDocumentTests.swift`의 `testNewChangesClampToPolicyRanges` 아래에 추가:

```swift
    func testEditingPolicyForwardsSharedRanges() {
        XCTAssertEqual(EditingPolicy.unitRange, AdjustmentRange.unit)
        XCTAssertEqual(EditingPolicy.bipolarRange, AdjustmentRange.bipolar)
        for key in FaceShapeKey.allCases {
            XCTAssertEqual(EditingPolicy.faceShapeRange(key), AdjustmentRange.faceShape(key), "\(key)")
        }
        XCTAssertEqual(AdjustmentRange.faceShape(.smile), 0...1)
        XCTAssertEqual(AdjustmentRange.clamped(.nan, to: AdjustmentRange.bipolar), -1, "NaN은 아래 끝")
        XCTAssertEqual(EditingPolicy.clamped(4, to: AdjustmentRange.unit), 1)
    }
```

`apple/Tests/MellowRenderingTests/FaceFrameTests.swift`:

```swift
import CoreImage
import MellowShared
import XCTest

@testable import MellowRendering

final class FaceFrameTests: XCTestCase {
    private let extent = SyntheticFace.extent
    private let thirtyDegrees = Double.pi / 6

    private func frame(_ face: FaceGeometry) throws -> FaceFrame {
        try XCTUnwrap(FaceFrame(face: face, extent: extent))
    }

    private func assertAxis(_ axis: CGVector, angle: Double, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(axis.dx, CGFloat(cos(angle)), accuracy: 1e-6, file: file, line: line)
        XCTAssertEqual(axis.dy, CGFloat(sin(angle)), accuracy: 1e-6, file: file, line: line)
    }

    func testNoContourHasNoFrame() {
        XCTAssertNil(FaceFrame(face: SyntheticFace.make(landmarks: false).face, extent: extent))
        XCTAssertNil(FaceFrame(face: SyntheticFace.make().face.removing([.faceContour]), extent: extent))
    }

    func testUprightSyntheticFaceUsesPupilAxis() throws {
        let upright = try frame(SyntheticFace.make().face)
        XCTAssertEqual(upright.origin.x, 256, accuracy: 1e-6)
        XCTAssertEqual(upright.origin.y, 200, accuracy: 1e-6)
        assertAxis(upright.xAxis, angle: 0)
        assertAxis(upright.yAxis, angle: Double.pi / 2)
        XCTAssertEqual(upright.faceWidth, 280, accuracy: 1e-6)
        XCTAssertEqual(upright.eyeLevel, 100, accuracy: 1e-6)
        XCTAssertEqual(upright.mouthLevel, -60, accuracy: 1e-6)
        XCTAssertEqual(upright.contour.count, 17)
        XCTAssertEqual(upright.eyes.count, 2)
        for eye in upright.eyes {
            XCTAssertEqual(eye.width, 56, accuracy: 1e-6, "눈 영역의 x축 방향 폭")
        }
        let local = upright.local(CGPoint(x: 312, y: 300))
        XCTAssertEqual(local.x, 56, accuracy: 1e-6)
        XCTAssertEqual(local.y, 100, accuracy: 1e-6)
        let back = upright.imagePoint(u: local.x, v: local.y)
        XCTAssertEqual(back.x, 312, accuracy: 1e-6)
        XCTAssertEqual(back.y, 300, accuracy: 1e-6)
    }

    func testRotatedFaceRotatesAxesAndKeepsLevels() throws {
        let tilted = try frame(SyntheticFace.make().face.rotated(by: thirtyDegrees, about: SyntheticFace.pivot))
        assertAxis(tilted.xAxis, angle: thirtyDegrees)
        assertAxis(tilted.yAxis, angle: thirtyDegrees + Double.pi / 2)
        XCTAssertEqual(tilted.eyeLevel, 100, accuracy: 1e-6)
        XCTAssertEqual(tilted.mouthLevel, -60, accuracy: 1e-6)
        let shift = tilted.vector(u: 10, v: 0)
        XCTAssertEqual(shift.dx, CGFloat(10 * cos(thirtyDegrees)), accuracy: 1e-6)
        XCTAssertEqual(shift.dy, CGFloat(10 * sin(thirtyDegrees)), accuracy: 1e-6)
    }

    func testUpsideDownFaceFlipsAxesSoUpPointsToEyes() throws {
        let flipped = try frame(SyntheticFace.make().face.rotated(by: Double.pi, about: SyntheticFace.pivot))
        assertAxis(flipped.xAxis, angle: Double.pi)
        assertAxis(flipped.yAxis, angle: -Double.pi / 2)
        XCTAssertEqual(flipped.eyeLevel, 100, accuracy: 1e-6)
        XCTAssertEqual(flipped.mouthLevel, -60, accuracy: 1e-6)
    }

    func testFallsBackToEyeCentersThenRoll() throws {
        let tilted = SyntheticFace.make().face.rotated(by: thirtyDegrees, about: SyntheticFace.pivot)
        let eyesOnly = try frame(tilted.removing([.leftPupil, .rightPupil]))
        assertAxis(eyesOnly.xAxis, angle: thirtyDegrees)
        XCTAssertEqual(eyesOnly.eyeLevel, 100, accuracy: 1e-6)
        let rollOnly = try frame(tilted.removing([.leftPupil, .rightPupil, .leftEye, .rightEye]))
        assertAxis(rollOnly.xAxis, angle: thirtyDegrees)
        XCTAssertTrue(rollOnly.eyes.isEmpty)
        XCTAssertEqual(rollOnly.eyeLevel, 300 * 0.13, accuracy: 1e-6, "눈이 없으면 상자 높이 비율")
        let nothing = try frame(SyntheticFace.make().face.removing([.leftPupil, .rightPupil, .leftEye, .rightEye]))
        assertAxis(nothing.xAxis, angle: 0)
    }

    func testCoincidentPupilsFallBackToRollWithoutNaN() throws {
        var face = SyntheticFace.make().face
        let middle = NormalizedPoint(x: 0.5, y: 300.0 / 512)
        face.landmarks[.leftPupil] = [middle]
        face.landmarks[.rightPupil] = [middle]
        face.roll = thirtyDegrees
        let degenerate = try frame(face)
        assertAxis(degenerate.xAxis, angle: thirtyDegrees)
        XCTAssertTrue(degenerate.eyeLevel.isFinite)
        XCTAssertTrue(degenerate.mouthLevel.isFinite)
    }

    func testEyesUseRegionWidthOrFallback() throws {
        var narrow = SyntheticFace.make().face
        for landmark in [FaceLandmark.leftEye, .rightEye] {
            let points = narrow.landmarks[landmark] ?? []
            let centerX = points.map(\.x).reduce(0, +) / Double(points.count)
            let centerY = points.map(\.y).reduce(0, +) / Double(points.count)
            narrow.landmarks[landmark] = points.map {
                NormalizedPoint(x: centerX + ($0.x - centerX) / 2, y: centerY + ($0.y - centerY) / 2)
            }
        }
        for eye in try frame(narrow).eyes {
            XCTAssertEqual(eye.width, 28, accuracy: 1e-6, "눈 영역을 절반으로 줄이면 폭도 절반")
        }
        let fallback = try frame(narrow.removing([.leftEye, .rightEye]))
        XCTAssertEqual(fallback.eyes.count, 2, "눈동자만 있어도 눈은 둘")
        for eye in fallback.eyes {
            XCTAssertEqual(eye.width, 280 * 0.2, accuracy: 1e-6, "눈 영역이 없으면 얼굴 폭의 20%")
        }
    }
}
```

- [ ] **Step 3: 실패 확인**

Run: `cd apple && swift test --filter 'FaceFrameTests|EditDocumentTests'` → 컴파일 실패(`cannot find 'FaceFrame' in scope`, `cannot find 'AdjustmentRange' in scope`).

- [ ] **Step 4: 구현**

`apple/Sources/MellowShared/API/AdjustmentRange.swift`:

```swift
import Foundation

/// 레시피 값 범위의 유일한 정의. 편집 규칙(EditingPolicy)과 렌더 단계가 함께 쓴다.
/// MellowRendering은 MellowEditing을 import할 수 없고, 프리셋·일괄 적용 값은 편집 규칙의 클램프를 거치지 않으므로
/// 렌더 단계도 이 범위로 직접 자른다.
public enum AdjustmentRange {
    /// 피부·눈입·배경·메이크업 강도, 미소·다리 길게.
    public static let unit: ClosedRange<Double> = 0...1
    /// 얼굴형·체형의 가운데 0인 양방향 범위.
    public static let bipolar: ClosedRange<Double> = -1...1

    /// 미소만 한 방향이다.
    public static func faceShape(_ key: FaceShapeKey) -> ClosedRange<Double> {
        key == .smile ? unit : bipolar
    }

    /// NaN은 범위의 아래 끝이 된다.
    public static func clamped(_ value: Double, to range: ClosedRange<Double>) -> Double {
        min(range.upperBound, max(range.lowerBound, value))
    }
}
```

`apple/Sources/MellowEditing/API/EditingPolicy.swift` 전체:

```swift
import MellowShared

/// 편집 규칙의 상수. 값 범위는 MellowShared의 AdjustmentRange를 같은 이름으로 내보낸다.
public enum EditingPolicy {
    /// 사진 한 장당 보관하는 실행 취소 단계 수.
    public static let historyLimit = 40
    /// 피부·눈입·배경·메이크업 강도.
    public static let unitRange = AdjustmentRange.unit
    /// 얼굴형·체형의 가운데 0인 양방향 범위.
    public static let bipolarRange = AdjustmentRange.bipolar

    /// 미소만 한 방향이다.
    public static func faceShapeRange(_ key: FaceShapeKey) -> ClosedRange<Double> {
        AdjustmentRange.faceShape(key)
    }

    /// NaN은 범위의 아래 끝이 된다.
    public static func clamped(_ value: Double, to range: ClosedRange<Double>) -> Double {
        AdjustmentRange.clamped(value, to: range)
    }
}
```

`apple/Sources/MellowRendering/Domain/FaceFrame.swift`:

```swift
import CoreImage
import MellowShared

/// 얼굴 좌표계. 원점 = 얼굴 상자 중심, x축 = 두 눈을 잇는 방향, y축 = x축을 반시계로 90° 돌린 방향(입 → 눈).
/// 길이는 extent 픽셀이다. x축은 눈동자 → 눈 영역 중심 → roll(반시계 양수) → 가로 순으로 정하고,
/// y축이 입에서 눈 쪽을 향하도록 두 축을 함께 뒤집을 수 있다. 그래서 Vision의 점 순서·좌우 이름이나
/// 사진 기울기와 관계없이 같은 얼굴 좌표를 얻는다.
struct FaceFrame {
    /// 눈 하나의 중심과 폭(얼굴 x축 방향, 픽셀).
    struct Eye: Equatable {
        let center: CGPoint
        let width: CGFloat
    }

    private struct EyePair {
        let first: CGPoint
        let second: CGPoint
    }

    /// 윤곽 다각형이 되려면 필요한 점 수.
    private static let minimumContourPoints = 3
    /// 두 눈 사이가 얼굴 폭의 이 비율보다 짧으면 눈으로 방향을 정하지 않는다.
    private static let minimumEyeSpan: CGFloat = 0.05
    /// 눈 영역 점이 없을 때의 눈 폭. 얼굴 폭 비율.
    private static let fallbackEyeWidth: CGFloat = 0.2
    /// 눈 폭을 재려면 필요한 눈 영역 점 수.
    private static let minimumEyeRegionPoints = 2
    /// 특징점이 없을 때 눈·입 중심 높이. 상자 중심 기준, 상자 높이 비율(FaceRegions 대체 위치 0.63·0.27).
    private static let fallbackEyeLevel: CGFloat = 0.13
    private static let fallbackMouthLevel: CGFloat = -0.23

    let origin: CGPoint
    let xAxis: CGVector
    let yAxis: CGVector
    let faceWidth: CGFloat
    /// 윤곽점(픽셀). Vision 순서 그대로다. 원소는 순서가 아니라 얼굴 좌표로 고른다.
    let contour: [CGPoint]
    /// 두 눈 중심의 얼굴 좌표 v.
    let eyeLevel: CGFloat
    /// 바깥 입술 중심의 얼굴 좌표 v.
    let mouthLevel: CGFloat
    let eyes: [Eye]
    private let landmarks: [FaceLandmark: [CGPoint]]

    /// 윤곽점이 3개보다 적거나 얼굴 폭이 0이면 nil.
    init?(face: FaceGeometry, extent: CGRect) {
        var landmarks: [FaceLandmark: [CGPoint]] = [:]
        for (landmark, points) in face.landmarks {
            landmarks[landmark] = points.map {
                CGPoint(x: extent.minX + $0.x * extent.width, y: extent.minY + $0.y * extent.height)
            }
        }
        let contour = landmarks[.faceContour] ?? []
        let width = CGFloat(face.boundingBox.width) * extent.width
        guard contour.count >= Self.minimumContourPoints, width > 0 else { return nil }
        let box = FaceRegions.pixelRect(face.boundingBox, in: extent)
        let origin = CGPoint(x: box.midX, y: box.midY)
        let pair = Self.eyePair(landmarks)
        var xAxis = CGVector(dx: 1, dy: 0)
        if let pair, Self.length(Self.offset(pair.second, from: pair.first)) > width * Self.minimumEyeSpan {
            xAxis = Self.unit(Self.offset(pair.second, from: pair.first))
        } else if let roll = face.roll {
            xAxis = CGVector(dx: CGFloat(cos(roll)), dy: CGFloat(sin(roll)))
        }
        var yAxis = CGVector(dx: -xAxis.dy, dy: xAxis.dx)
        let eyeCenter = pair.map { Self.midpoint($0.first, $0.second) }
        let lips = landmarks[.outerLips] ?? []
        let mouthCenter = Self.centroid(lips.isEmpty ? contour : lips)
        if Self.dot(yAxis, Self.offset(eyeCenter ?? origin, from: mouthCenter)) < 0 {
            xAxis = CGVector(dx: -xAxis.dx, dy: -xAxis.dy)
            yAxis = CGVector(dx: -yAxis.dx, dy: -yAxis.dy)
        }
        let boxHeight = CGFloat(face.boundingBox.height) * extent.height
        self.origin = origin
        self.xAxis = xAxis
        self.yAxis = yAxis
        self.faceWidth = width
        self.contour = contour
        self.landmarks = landmarks
        if let eyeCenter {
            eyeLevel = Self.dot(Self.offset(eyeCenter, from: origin), yAxis)
        } else {
            eyeLevel = boxHeight * Self.fallbackEyeLevel
        }
        if lips.isEmpty {
            mouthLevel = boxHeight * Self.fallbackMouthLevel
        } else {
            mouthLevel = Self.dot(Self.offset(Self.centroid(lips), from: origin), yAxis)
        }
        let regions = [FaceLandmark.leftEye, .rightEye].compactMap { landmarks[$0] }
            .filter { $0.count >= Self.minimumEyeRegionPoints }
        let centers = pair.map { [$0.first, $0.second] } ?? []
        eyes = centers.map { center in
            let nearest = regions.min {
                Self.length(Self.offset(Self.centroid($0), from: center))
                    < Self.length(Self.offset(Self.centroid($1), from: center))
            }
            let measured = nearest.map { Self.span($0, along: xAxis) } ?? 0
            return Eye(center: center, width: measured > 0 ? measured : width * Self.fallbackEyeWidth)
        }
    }

    /// 이미지 픽셀 점을 얼굴 좌표(u, v)로.
    func local(_ point: CGPoint) -> CGPoint {
        let offset = Self.offset(point, from: origin)
        return CGPoint(x: Self.dot(offset, xAxis), y: Self.dot(offset, yAxis))
    }

    /// 얼굴 좌표 점을 이미지 픽셀로.
    func imagePoint(u: CGFloat, v: CGFloat) -> CGPoint {
        CGPoint(x: origin.x + xAxis.dx * u + yAxis.dx * v, y: origin.y + xAxis.dy * u + yAxis.dy * v)
    }

    /// 얼굴 좌표 벡터를 이미지 벡터로.
    func vector(u: CGFloat, v: CGFloat) -> CGVector {
        CGVector(dx: xAxis.dx * u + yAxis.dx * v, dy: xAxis.dy * u + yAxis.dy * v)
    }

    /// 특징점(픽셀). 없으면 빈 배열.
    func points(_ landmark: FaceLandmark) -> [CGPoint] {
        landmarks[landmark] ?? []
    }

    static func centroid(_ points: [CGPoint]) -> CGPoint {
        let count = CGFloat(max(1, points.count))
        let sum = points.reduce(CGPoint.zero) { CGPoint(x: $0.x + $1.x, y: $0.y + $1.y) }
        return CGPoint(x: sum.x / count, y: sum.y / count)
    }

    /// 눈동자 둘, 없으면 눈 영역 중심 둘.
    private static func eyePair(_ landmarks: [FaceLandmark: [CGPoint]]) -> EyePair? {
        if let left = landmarks[.leftPupil]?.first, let right = landmarks[.rightPupil]?.first {
            return EyePair(first: left, second: right)
        }
        guard let left = landmarks[.leftEye], let right = landmarks[.rightEye], !left.isEmpty, !right.isEmpty
        else { return nil }
        return EyePair(first: centroid(left), second: centroid(right))
    }

    private static func midpoint(_ a: CGPoint, _ b: CGPoint) -> CGPoint {
        CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2)
    }

    private static func offset(_ point: CGPoint, from origin: CGPoint) -> CGVector {
        CGVector(dx: point.x - origin.x, dy: point.y - origin.y)
    }

    private static func dot(_ a: CGVector, _ b: CGVector) -> CGFloat {
        a.dx * b.dx + a.dy * b.dy
    }

    private static func length(_ vector: CGVector) -> CGFloat {
        hypot(vector.dx, vector.dy)
    }

    private static func unit(_ vector: CGVector) -> CGVector {
        let size = length(vector)
        return CGVector(dx: vector.dx / size, dy: vector.dy / size)
    }

    /// 점들을 axis에 투영한 길이(최대 − 최소).
    private static func span(_ points: [CGPoint], along axis: CGVector) -> CGFloat {
        let projections = points.map { $0.x * axis.dx + $0.y * axis.dy }
        return (projections.max() ?? 0) - (projections.min() ?? 0)
    }
}
```

- [ ] **Step 5: 통과 확인**

Run: `cd apple && swift test` → `Executed 192 tests, with 0 failures`(Shared 37 · Rendering 100 · Library 30 · Export 4 · Editing 21). 기존 `testNewChangesClampToPolicyRanges`·잠금 테스트가 그대로 통과해야 한다. lint 출력 없음. `./scripts/verify-modules.sh` 통과. Mac 앱 테스트 → `Executed 51 tests, with 0 failures`(`EditingPolicy` 공개 API가 그대로인지 확인).

- [ ] **Step 6: 커밋**

```bash
git add apple/Sources/MellowShared/API/AdjustmentRange.swift apple/Sources/MellowEditing/API/EditingPolicy.swift apple/Sources/MellowRendering/Domain/FaceFrame.swift apple/Tests/MellowRenderingTests/RenderingTestSupport.swift apple/Tests/MellowRenderingTests/FaceFrameTests.swift apple/Tests/MellowEditingTests/EditDocumentTests.swift
git commit -m "feat(rendering): 눈동자 기준 얼굴 좌표계와 공용 값 범위 추가

값 범위 정의를 MellowShared AdjustmentRange로 옮겨 렌더 단계도 직접 자를 수
있게 하고, EditingPolicy는 같은 이름으로 내보낸다. FaceFrame은 눈동자·눈 중심·
roll 순으로 x축을 정하고 입에서 눈 쪽을 위로 맞춘다.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 3: FaceShapeRig — 얼굴형 10개 항목을 이동 원소로

**Files:**
- Create: `apple/Sources/MellowRendering/Domain/FaceShapeRig.swift`
- Modify: `apple/Sources/MellowRendering/API/RenderTuning.swift` (`import MellowShared`, yaw 기준, 항목별 최대 이동 10개, `faceShapeMaxShift(_:)`)
- Modify: `apple/Tests/MellowRenderingTests/RenderingTestSupport.swift` (`minimumJacobian(of:limit:in:)`)
- Test: `apple/Tests/MellowRenderingTests/FaceShapeRigTests.swift`

**Interfaces:**
- Consumes: `FaceFrame`(Task 2), `AdjustmentRange.clamped`·`faceShape`(Task 2), `ShapePrimitive`·`DisplacementWarp.displacement(at:of:limit:)`(Task 1), `FaceShapeAdjustments` subscript, `VisionFaceAnalyzer`, `ImageLoader`.
- Produces: `enum FaceShapeRig` — `static func primitives(face: FaceGeometry, adjustments: FaceShapeAdjustments, extent: CGRect, tuning: RenderTuning) -> [ShapePrimitive]`(스펙 시그니처에 `tuning` 추가), `static func yawAttenuation(_ yaw: Double?, tuning: RenderTuning) -> Double`. `RenderTuning.faceShapeYawThreshold`(0.35), `faceWidthMaxShift`(0.06), `faceJawMaxShift`(0.07), `faceCheekboneMaxShift`(0.04), `faceEyeSizeMaxScale`(0.18), `faceEyeDistanceMaxShift`(0.02), `faceNoseWidthMaxShift`(0.02), `faceMouthSizeMaxScale`(0.15), `faceSmileMaxShift`(0.025), `faceForeheadMaxShift`(0.05), `faceChinLengthMaxShift`(0.05), `func faceShapeMaxShift(_ key: FaceShapeKey) -> Double`. 테스트 지원: `RenderingTestSupport.minimumJacobian(of:limit:in:)`.

항목별 원소(스펙 3 표를 얼굴 좌표 u·v로 구체화, W = 얼굴 폭 픽셀, s = 값 × 항목 최대 × W × yaw 약화, f = 값 × 항목 최대 배율 × yaw 약화):

| 항목 | 원소 | 반지름 |
|---|---|---|
| width | mouthLevel ≤ v ≤ eyeLevel인 윤곽점, 쪽(u 부호)마다 점 k개에 push(u: 쪽 × s / k) | 0.22W |
| jaw | v < mouthLevel이고 \|u\| ≥ 0.1W인 윤곽점, 쪽마다 push(u: 쪽 × s / k, v: −0.5 × s / k) | 0.22W |
| cheekbone | 쪽마다 v가 가장 큰 윤곽점 하나에 push(u: 쪽 × s) | 0.2W |
| eyeSize | 눈마다 scale(f) | 눈 폭 × 1.2 |
| eyeDistance | 눈마다 push(u: 눈 쪽 × s) | 눈 폭 × 1.3 |
| noseWidth | nose의 u 최소·최대 점(코 날개)에 push(u: (날개 u − 중심 u) 부호 × s). 중심 = noseCrest(없으면 nose) 평균 u | 0.1W |
| mouthSize | 바깥 입술 중심에 scale(f) | 입 폭 × 0.75 |
| smile | 바깥 입술 u 최소·최대 점(입꼬리)에 push(u: 쪽 × 0.4s, v: s) | 입 폭 × 0.35 |
| forehead | 눈썹 위끝(없으면 eyeLevel + 0.12W)에서 0.3W 위, 눈썹 평균 u에 push(v: s) | 0.35W |
| chinLength | v가 가장 작은 윤곽점(턱 끝)에 push(v: −s) | 0.25W |

부호: width·jaw·cheekbone·noseWidth 음수 = 좁게(중심 쪽), eyeSize·mouthSize 양수 = 크게, eyeDistance 양수 = 넓게, smile 양수 = 위·바깥, forehead 양수 = 이마가 위로(넓게), chinLength 양수 = 턱이 아래로(길게). 같은 쪽 점 수 k로 나눠 겹친 합이 s를 넘지 않는다(합성 얼굴에서 width −1의 실효 최대 ≈ 0.034W). 합성 얼굴(W = 280)에서 모든 원소가 `shapeDisplacementLimit` 안이라 테스트 수치가 정확히 맞는다. 합성 얼굴로 열 항목 ±1 조합의 야코비안을 미리 계산하면 최솟값이 약 0.39다(테스트 기준 0.2). 특징점이 없는 항목은 빈 배열, 윤곽점이 없으면 전부 빈 배열.

- [ ] **Step 1: 테스트 지원 코드**

`RenderingTestSupport` enum 안, `expectedPosition` 아래에 추가:

```swift
    /// minimumJacobian의 격자 간격과 중앙 차분 간격(픽셀).
    static let jacobianGridStep: CGFloat = 4
    static let jacobianDelta: CGFloat = 0.5

    /// out(p) = in(p − D(p))에서 읽는 위치 p − D(p)의 야코비안 행렬식 최솟값. 0 이하면 이미지가 접힌다.
    static func minimumJacobian(of primitives: [ShapePrimitive], limit: Double, in rect: CGRect) -> CGFloat {
        func source(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            let shift = DisplacementWarp.displacement(at: CGPoint(x: x, y: y), of: primitives, limit: limit)
            return CGPoint(x: x - shift.dx, y: y - shift.dy)
        }
        let h = jacobianDelta
        var worst = CGFloat.infinity
        for y in stride(from: rect.minY, through: rect.maxY, by: jacobianGridStep) {
            for x in stride(from: rect.minX, through: rect.maxX, by: jacobianGridStep) {
                let right = source(x + h, y)
                let left = source(x - h, y)
                let up = source(x, y + h)
                let down = source(x, y - h)
                let a = (right.x - left.x) / (2 * h)
                let b = (up.x - down.x) / (2 * h)
                let c = (right.y - left.y) / (2 * h)
                let d = (up.y - down.y) / (2 * h)
                worst = min(worst, a * d - b * c)
            }
        }
        return worst
    }
```

- [ ] **Step 2: 실패하는 테스트 작성**

`apple/Tests/MellowRenderingTests/FaceShapeRigTests.swift`:

```swift
import CoreImage
import MellowShared
import XCTest

@testable import MellowRendering

final class FaceShapeRigTests: XCTestCase {
    typealias Support = RenderingTestSupport

    private struct Push {
        let center: CGPoint
        let vector: CGVector
        let radius: CGFloat
    }

    private struct Scale {
        let center: CGPoint
        let factor: CGFloat
        let radius: CGFloat
    }

    private let extent = SyntheticFace.extent
    private let tuning = RenderTuning()
    /// 합성 얼굴의 얼굴 폭(상자 가로)과 중심선(픽셀).
    private let faceWidth: CGFloat = 280
    private let midline: CGFloat = 256

    private func primitives(
        _ adjustments: FaceShapeAdjustments, face: FaceGeometry = SyntheticFace.make().face
    ) -> [ShapePrimitive] {
        FaceShapeRig.primitives(face: face, adjustments: adjustments, extent: extent, tuning: tuning)
    }

    /// 열 항목 모두 0.6(미소 포함).
    private var allKeys: FaceShapeAdjustments {
        var adjustments = FaceShapeAdjustments()
        for key in FaceShapeKey.allCases {
            adjustments[key] = 0.6
        }
        return adjustments
    }

    private func pushes(_ list: [ShapePrimitive]) -> [Push] {
        list.compactMap { primitive in
            guard case .push(let center, let vector, let radius) = primitive else { return nil }
            return Push(center: center, vector: vector, radius: radius)
        }
    }

    private func scales(_ list: [ShapePrimitive]) -> [Scale] {
        list.compactMap { primitive in
            guard case .scale(let center, let factor, let radius) = primitive else { return nil }
            return Scale(center: center, factor: factor, radius: radius)
        }
    }

    private func mirrored(_ primitive: ShapePrimitive) -> ShapePrimitive {
        switch primitive {
        case .push(let center, let vector, let radius):
            return .push(
                center: CGPoint(x: 2 * midline - center.x, y: center.y), vector: CGVector(dx: -vector.dx, dy: vector.dy),
                radius: radius)
        case .scale(let center, let factor, let radius):
            return .scale(center: CGPoint(x: 2 * midline - center.x, y: center.y), factor: factor, radius: radius)
        case .band:
            return primitive
        }
    }

    /// 상자 중심(256, 200) 둘레로 angle만큼 반시계로 돌린다.
    private func rotated(_ primitive: ShapePrimitive, by angle: Double) -> ShapePrimitive {
        let pivot = CGPoint(x: SyntheticFace.box.midX, y: SyntheticFace.box.midY)
        let cosine = CGFloat(cos(angle))
        let sine = CGFloat(sin(angle))
        func turn(_ vector: CGVector) -> CGVector {
            CGVector(dx: vector.dx * cosine - vector.dy * sine, dy: vector.dx * sine + vector.dy * cosine)
        }
        func move(_ point: CGPoint) -> CGPoint {
            let turned = turn(CGVector(dx: point.x - pivot.x, dy: point.y - pivot.y))
            return CGPoint(x: pivot.x + turned.dx, y: pivot.y + turned.dy)
        }
        switch primitive {
        case .push(let center, let vector, let radius):
            return .push(center: move(center), vector: turn(vector), radius: radius)
        case .scale(let center, let factor, let radius):
            return .scale(center: move(center), factor: factor, radius: radius)
        case .band:
            return primitive
        }
    }

    private func approximatelyEqual(_ a: ShapePrimitive, _ b: ShapePrimitive) -> Bool {
        let tolerance: CGFloat = 1e-6
        switch (a, b) {
        case (.push(let c1, let v1, let r1), .push(let c2, let v2, let r2)):
            return hypot(c1.x - c2.x, c1.y - c2.y) < tolerance && hypot(v1.dx - v2.dx, v1.dy - v2.dy) < tolerance
                && abs(r1 - r2) < tolerance
        case (.scale(let c1, let f1, let r1), .scale(let c2, let f2, let r2)):
            return hypot(c1.x - c2.x, c1.y - c2.y) < tolerance && abs(f1 - f2) < tolerance && abs(r1 - r2) < tolerance
        default:
            return false
        }
    }

    func testZeroValuesProduceNoPrimitives() {
        XCTAssertTrue(primitives(FaceShapeAdjustments()).isEmpty)
    }

    func testNoContourProducesNoPrimitives() {
        XCTAssertTrue(primitives(allKeys, face: SyntheticFace.make(landmarks: false).face).isEmpty)
        XCTAssertTrue(primitives(allKeys, face: SyntheticFace.make().face.removing([.faceContour])).isEmpty)
    }

    func testNarrowWidthPushesLeftContourRightAndRightContourLeft() {
        let list = pushes(primitives(FaceShapeAdjustments(width: -1)))
        XCTAssertEqual(list.count, 6, "눈~입 높이 윤곽점 한쪽 3개씩")
        let left = list.filter { $0.center.x < midline }
        let right = list.filter { $0.center.x > midline }
        XCTAssertEqual(left.count, 3)
        XCTAssertEqual(right.count, 3)
        for push in left {
            XCTAssertGreaterThan(push.vector.dx, 0, "왼쪽 윤곽은 +x")
            XCTAssertEqual(push.vector.dy, 0, accuracy: 1e-9)
        }
        for push in right {
            XCTAssertLessThan(push.vector.dx, 0, "오른쪽 윤곽은 −x")
        }
        let leftTotal = left.map(\.vector.dx).reduce(0, +)
        XCTAssertEqual(leftTotal, faceWidth * CGFloat(tuning.faceWidthMaxShift), accuracy: 1e-6, "한쪽 합 = 얼굴 폭 × 최대")
    }

    func testJawPushesInwardAndUpExcludingChinCenter() {
        let list = pushes(primitives(FaceShapeAdjustments(jaw: -1)))
        XCTAssertEqual(list.count, 10, "입 아래 윤곽점 한쪽 5개씩, 턱 끝 가까운 점 제외")
        for push in list {
            XCTAssertLessThan(push.center.y, SyntheticFace.mouth.y, "입 아래")
            XCTAssertGreaterThanOrEqual(abs(push.center.x - midline), faceWidth * 0.1)
            XCTAssertGreaterThan(push.vector.dy, 0, "V라인은 위로")
            XCTAssertEqual(push.vector.dx > 0, push.center.x < midline, "안쪽으로")
        }
    }

    func testCheekboneForeheadAndChinDirections() {
        let cheek = pushes(primitives(FaceShapeAdjustments(cheekbone: -1)))
        XCTAssertEqual(cheek.count, 2)
        let cheekShift = faceWidth * CGFloat(tuning.faceCheekboneMaxShift)
        for push in cheek {
            XCTAssertEqual(push.center.y, 240, accuracy: 1e-6, "각 쪽 가장 높은 윤곽점")
            XCTAssertEqual(push.vector.dx, push.center.x < midline ? cheekShift : -cheekShift, accuracy: 1e-6)
        }
        let forehead = pushes(primitives(FaceShapeAdjustments(forehead: 1)))
        XCTAssertEqual(forehead.count, 1)
        XCTAssertEqual(forehead[0].center.x, midline, accuracy: 1e-6)
        XCTAssertGreaterThan(forehead[0].center.y, SyntheticFace.leftBrow.maxY, "눈썹 위")
        XCTAssertEqual(
            forehead[0].vector.dy, faceWidth * CGFloat(tuning.faceForeheadMaxShift), accuracy: 1e-6, "이마가 위로")
        let chin = pushes(primitives(FaceShapeAdjustments(chinLength: 1)))
        XCTAssertEqual(chin.count, 1)
        XCTAssertEqual(chin[0].center.y, 50, accuracy: 1e-6, "턱 끝")
        XCTAssertEqual(
            chin[0].vector.dy, -faceWidth * CGFloat(tuning.faceChinLengthMaxShift), accuracy: 1e-6, "턱이 아래로")
    }

    func testEyeNoseAndMouthKeys() {
        let eyes = scales(primitives(FaceShapeAdjustments(eyeSize: 1)))
        let eyeXs = eyes.map(\.center.x).sorted()
        XCTAssertEqual(eyeXs, [SyntheticFace.leftEye.x, SyntheticFace.rightEye.x], "각 눈동자 중심")
        for eye in eyes {
            XCTAssertEqual(eye.factor, CGFloat(tuning.faceEyeSizeMaxScale), accuracy: 1e-9, "양수면 확대")
            XCTAssertEqual(eye.radius, 56 * 1.2, accuracy: 1e-6, "반지름 = 눈 폭 × 1.2")
        }
        let apart = pushes(primitives(FaceShapeAdjustments(eyeDistance: 1)))
        XCTAssertEqual(apart.count, 2)
        for push in apart {
            XCTAssertEqual(push.vector.dx < 0, push.center.x < midline, "중심선에서 멀어진다")
        }
        let nose = pushes(primitives(FaceShapeAdjustments(noseWidth: -1)))
        XCTAssertEqual(nose.map(\.center.x).sorted(), [236, 276], "코 날개 두 점")
        for push in nose {
            XCTAssertEqual(push.vector.dx > 0, push.center.x < midline, "코 날개가 가운데로")
            XCTAssertEqual(abs(push.vector.dx), faceWidth * CGFloat(tuning.faceNoseWidthMaxShift), accuracy: 1e-6)
        }
        let mouth = scales(primitives(FaceShapeAdjustments(mouthSize: 1)))
        XCTAssertEqual(mouth.count, 1)
        XCTAssertEqual(mouth[0].center.x, SyntheticFace.mouth.x, accuracy: 1e-6)
        XCTAssertEqual(mouth[0].center.y, SyntheticFace.mouth.y, accuracy: 1e-6)
        XCTAssertGreaterThan(mouth[0].factor, 0)
        let smile = pushes(primitives(FaceShapeAdjustments(smile: 1)))
        XCTAssertEqual(smile.count, 2)
        for push in smile {
            XCTAssertGreaterThan(push.vector.dy, 0, "입꼬리가 위로")
            XCTAssertEqual(push.vector.dx < 0, push.center.x < midline, "입꼬리가 바깥으로")
        }
    }

    func testAllKeysAreMirrorSymmetric() {
        let list = primitives(allKeys)
        XCTAssertGreaterThan(list.count, 20)
        for primitive in list {
            let mirror = mirrored(primitive)
            XCTAssertTrue(list.contains { approximatelyEqual($0, mirror) }, "\(primitive)의 거울 원소가 없다")
        }
    }

    func testRollRotatesPrimitives() {
        let angle = Double.pi / 6
        let tiltedFace = SyntheticFace.make().face.rotated(by: angle, about: SyntheticFace.pivot)
        let upright = primitives(allKeys)
        let tilted = primitives(allKeys, face: tiltedFace)
        XCTAssertEqual(tilted.count, upright.count)
        for (expected, actual) in zip(upright.map { rotated($0, by: angle) }, tilted) {
            XCTAssertTrue(approximatelyEqual(expected, actual), "\(actual) ≠ \(expected)")
        }
        for push in pushes(primitives(FaceShapeAdjustments(width: -1), face: tiltedFace)) {
            let vectorAngle = atan2(Double(push.vector.dy), Double(push.vector.dx))
            XCTAssertEqual(sin(vectorAngle - angle), 0, accuracy: 1e-6, "얼굴 폭 벡터도 30° 기운다")
        }
    }

    func testValuesOutsideRangeAreClamped() {
        XCTAssertEqual(primitives(FaceShapeAdjustments(width: -3)), primitives(FaceShapeAdjustments(width: -1)))
        XCTAssertEqual(primitives(FaceShapeAdjustments(eyeSize: 7)), primitives(FaceShapeAdjustments(eyeSize: 1)))
        XCTAssertTrue(primitives(FaceShapeAdjustments(smile: -0.5)).isEmpty, "미소는 0…1")
    }

    func testYawAttenuatesContinuouslyAndVanishesAtProfile() {
        var face = SyntheticFace.make().face
        let straight = primitives(FaceShapeAdjustments(width: -1), face: face)
        face.yaw = tuning.faceShapeYawThreshold
        XCTAssertEqual(primitives(FaceShapeAdjustments(width: -1), face: face), straight, "기준값에서는 약화 없음")
        face.yaw = -0.6
        let turned = pushes(primitives(FaceShapeAdjustments(width: -1), face: face))
        let ratio = CGFloat(cos(0.6) / cos(tuning.faceShapeYawThreshold))
        XCTAssertEqual(turned[0].vector.dx, pushes(straight)[0].vector.dx * ratio, accuracy: 1e-9)
        face.yaw = Double.pi / 4
        XCTAssertFalse(primitives(allKeys, face: face).isEmpty, "Vision의 45° 얼굴은 약하게 남는다")
        face.yaw = Double.pi / 2
        XCTAssertTrue(primitives(allKeys, face: face).isEmpty, "옆얼굴은 원소 없음")
    }

    func testMissingFeatureLandmarksSkipOnlyThatKey() {
        let noNose = SyntheticFace.make().face.removing([.nose])
        XCTAssertTrue(primitives(FaceShapeAdjustments(noseWidth: -1), face: noNose).isEmpty)
        XCTAssertEqual(primitives(FaceShapeAdjustments(width: -1), face: noNose).count, 6)
        let noLips = SyntheticFace.make().face.removing([.outerLips])
        XCTAssertTrue(primitives(FaceShapeAdjustments(mouthSize: 1, smile: 1), face: noLips).isEmpty)
        XCTAssertFalse(primitives(FaceShapeAdjustments(width: -1), face: noLips).isEmpty)
        let noEyes = SyntheticFace.make().face.removing([.leftPupil, .rightPupil, .leftEye, .rightEye])
        XCTAssertTrue(primitives(FaceShapeAdjustments(eyeSize: 1, eyeDistance: 1), face: noEyes).isEmpty)
        XCTAssertEqual(primitives(FaceShapeAdjustments(forehead: 1), face: noEyes).count, 1, "눈썹으로 이마 위치를 잡는다")
    }

    func testExtremeCombinationsNeverFold() {
        let combinations: [[Double]] = [
            [1, 1, 1, 1, 1, 1, 1, 1, 1, 1],
            [-1, -1, -1, -1, -1, -1, -1, 1, -1, -1],
            [1, -1, 1, -1, -1, 1, -1, 1, 1, -1],
        ]
        let region = CGRect(x: 50, y: 20, width: 412, height: 470)
        for values in combinations {
            var adjustments = FaceShapeAdjustments()
            for (key, value) in zip(FaceShapeKey.allCases, values) {
                adjustments[key] = value
            }
            let worst = Support.minimumJacobian(
                of: primitives(adjustments), limit: tuning.shapeDisplacementLimit, in: region)
            XCTAssertGreaterThan(worst, 0.2, "\(values)에서 이미지가 접힌다")
        }
    }

    func testDemoPortraitLandmarksDriveEveryKey() throws {
        let url = try XCTUnwrap(
            Bundle.module.url(forResource: "demo-portrait", withExtension: "png", subdirectory: "Fixtures"))
        let image = try ImageLoader().load(url: url, maxDimension: 1200)
        let face = try XCTUnwrap(try VisionFaceAnalyzer().analyze(image).first)
        for key in FaceShapeKey.allCases {
            var adjustments = FaceShapeAdjustments()
            adjustments[key] = 1
            let list = FaceShapeRig.primitives(face: face, adjustments: adjustments, extent: image.extent, tuning: tuning)
            XCTAssertFalse(list.isEmpty, "\(key): 실제 특징점으로 원소가 생긴다")
        }
        let frame = try XCTUnwrap(FaceFrame(face: face, extent: image.extent))
        XCTAssertGreaterThan(frame.yAxis.dy, 0, "똑바로 선 사진의 얼굴 위쪽은 이미지 위쪽")
        let narrow = FaceShapeRig.primitives(
            face: face, adjustments: FaceShapeAdjustments(width: -1), extent: image.extent, tuning: tuning)
        for case .push(let center, let vector, _) in narrow {
            let side = frame.local(center).x
            let along = vector.dx * frame.xAxis.dx + vector.dy * frame.xAxis.dy
            XCTAssertLessThan(side * along, 0, "얼굴 폭 −1은 중심선 쪽")
        }
    }
}
```

- [ ] **Step 3: 실패 확인**

Run: `cd apple && swift test --filter FaceShapeRigTests` → 컴파일 실패(`cannot find 'FaceShapeRig' in scope`, `value of type 'RenderTuning' has no member 'faceWidthMaxShift'`).

- [ ] **Step 4: 구현**

`RenderTuning.swift`: 맨 위 `import Foundation` 아래에 `import MellowShared`를 넣고, `shapeDisplacementLimit` 아래에 추가:

```swift
    /// |yaw|가 이보다 크면 얼굴형 이동을 cos(|yaw|) / cos(이 값)으로 줄인다(스펙 0.35rad ≈ 20°). 이 값에서 1이라 끊기지 않는다.
    public var faceShapeYawThreshold: Double = 0.35
    /// 얼굴 폭 ±1에서 한쪽 윤곽을 미는 양. 얼굴 폭 비율. 같은 쪽 점 수로 나눠 겹치므로 실효 최대는 약 0.034
    /// (140mm 얼굴에서 약 5mm)이고 B0 얼굴 미세 조정(0.035)과 비슷하다.
    public var faceWidthMaxShift: Double = 0.06
    /// 턱선. 입 아래 윤곽점 몫으로 나눠 실효 최대 약 0.029, 위로 드는 양은 안쪽의 절반.
    public var faceJawMaxShift: Double = 0.07
    /// 광대. 각 쪽 윤곽 맨 위 점 하나를 민다.
    public var faceCheekboneMaxShift: Double = 0.04
    /// 눈 크기. scale 배율이라 눈 중심 선형 배율은 1 / (1 − 0.18) ≈ 1.22(큰 눈 보정의 흔한 1.2~1.3배).
    public var faceEyeSizeMaxScale: Double = 0.18
    /// 눈 간격. 눈 하나가 얼굴 폭의 2%(약 3mm) 움직인다.
    public var faceEyeDistanceMaxShift: Double = 0.02
    /// 코 폭. 코 날개 하나가 얼굴 폭의 2% 움직인다. 코 폭은 얼굴 폭의 25% 안팎이라 −1이면 약 16% 좁아진다.
    public var faceNoseWidthMaxShift: Double = 0.02
    /// 입 크기. scale 배율, 입 중심 선형 배율 약 1.18.
    public var faceMouthSizeMaxScale: Double = 0.15
    /// 미소. 입꼬리가 위로 얼굴 폭의 2.5%, 바깥으로 그 40%.
    public var faceSmileMaxShift: Double = 0.025
    /// 이마. 이마 가운데를 위·아래로 얼굴 폭의 5%(약 7mm).
    public var faceForeheadMaxShift: Double = 0.05
    /// 턱 길이. 턱 끝을 아래·위로 얼굴 폭의 5%.
    public var faceChinLengthMaxShift: Double = 0.05

    /// 얼굴형 항목별 최대 이동. eyeSize·mouthSize는 scale 배율, 나머지는 얼굴 폭 비율.
    public func faceShapeMaxShift(_ key: FaceShapeKey) -> Double {
        switch key {
        case .width: return faceWidthMaxShift
        case .jaw: return faceJawMaxShift
        case .cheekbone: return faceCheekboneMaxShift
        case .eyeSize: return faceEyeSizeMaxScale
        case .eyeDistance: return faceEyeDistanceMaxShift
        case .noseWidth: return faceNoseWidthMaxShift
        case .mouthSize: return faceMouthSizeMaxScale
        case .smile: return faceSmileMaxShift
        case .forehead: return faceForeheadMaxShift
        case .chinLength: return faceChinLengthMaxShift
        }
    }
```

`apple/Sources/MellowRendering/Domain/FaceShapeRig.swift`:

```swift
import CoreImage
import MellowShared

/// 얼굴형 슬라이더 10개를 이동 원소로 바꾼다. 좌표·길이는 extent 픽셀, 원소 위치는 FaceFrame 얼굴 좌표로 고른다.
/// 값은 여기서 AdjustmentRange로 자른다. 프리셋·일괄 적용 값은 편집 규칙의 클램프를 거치지 않기 때문이다.
/// push 항목의 이동 = 값 × 항목 최대 × 얼굴 폭 × yaw 약화, scale 항목의 배율 = 값 × 항목 최대 배율 × yaw 약화.
enum FaceShapeRig {
    /// 얼굴 중심선 한쪽의 윤곽점.
    private struct ContourSide {
        /// 왼쪽 −1, 오른쪽 +1(얼굴 x축 기준).
        let side: CGFloat
        let points: [CGPoint]
    }

    /// 바깥 입술의 중심, 입꼬리 두 점, 얼굴 x축 방향 폭.
    private struct Mouth {
        let center: CGPoint
        let corners: [CGPoint]
        let width: CGFloat
    }

    /// width·jaw 윤곽 push 반지름. 얼굴 폭 비율.
    private static let contourRadius: CGFloat = 0.22
    /// cheekbone push 반지름. 얼굴 폭 비율.
    private static let cheekboneRadius: CGFloat = 0.2
    /// jaw가 위로 드는 양. 안쪽 이동 대비.
    private static let jawLiftRatio: CGFloat = 0.5
    /// 턱 끝 가까운 윤곽점은 jaw에서 뺀다(턱 길이는 chinLength 몫). 얼굴 폭 비율.
    private static let jawCenterExclusion: CGFloat = 0.1
    /// eyeSize scale 반지름. 눈 폭 대비(스펙 1.2).
    private static let eyeScaleRadius: CGFloat = 1.2
    /// eyeDistance push 반지름. 눈 폭 대비. 눈 전체와 눈꺼풀을 함께 옮긴다.
    private static let eyeShiftRadius: CGFloat = 1.3
    /// noseWidth push 반지름. 얼굴 폭 비율. 코 날개 둘이 가운데서 서로 상쇄되는 크기.
    private static let noseWingRadius: CGFloat = 0.1
    /// mouthSize scale 반지름. 입 폭 대비. 입꼬리(입 폭의 절반)를 넉넉히 덮는다.
    private static let mouthScaleRadius: CGFloat = 0.75
    /// smile push 반지름. 입 폭 대비.
    private static let mouthCornerRadius: CGFloat = 0.35
    /// 입꼬리가 바깥으로 가는 양. 위쪽 이동 대비.
    private static let smileOutwardRatio: CGFloat = 0.4
    /// forehead push 중심을 눈썹 위끝에서 올리는 거리와 반지름. 얼굴 폭 비율. 눈썹은 감쇠 끝자락(5% 안팎)만 받는다.
    private static let foreheadOffset: CGFloat = 0.3
    private static let foreheadRadius: CGFloat = 0.35
    /// 눈썹 점이 없을 때 눈 높이 위로 눈썹 위끝을 어림하는 거리. 얼굴 폭 비율.
    private static let fallbackBrowRise: CGFloat = 0.12
    /// chinLength push 반지름. 얼굴 폭 비율. 입(턱 끝에서 얼굴 폭의 약 30% 위)에는 닿지 않는다.
    private static let chinRadius: CGFloat = 0.25
    /// 좌우 끝점을 고르려면 필요한 점 수.
    private static let minimumFeaturePoints = 2
    /// 이보다 작은 yaw 약화는 원소를 만들지 않는다(옆얼굴).
    private static let negligibleAttenuation = 1e-3

    static func primitives(
        face: FaceGeometry, adjustments: FaceShapeAdjustments, extent: CGRect, tuning: RenderTuning
    ) -> [ShapePrimitive] {
        guard adjustments.hasEffect, let frame = FaceFrame(face: face, extent: extent) else { return [] }
        let attenuation = yawAttenuation(face.yaw, tuning: tuning)
        guard attenuation > negligibleAttenuation else { return [] }
        var result: [ShapePrimitive] = []
        for key in FaceShapeKey.allCases {
            let value = AdjustmentRange.clamped(adjustments[key], to: AdjustmentRange.faceShape(key))
            guard value != 0 else { continue }
            let amount = CGFloat(value * tuning.faceShapeMaxShift(key) * attenuation)
            result += primitives(for: key, amount: amount, frame: frame)
        }
        return result
    }

    /// |yaw| ≤ 기준이면 1, 넘으면 cos(|yaw|) / cos(기준). 옆얼굴(π/2)에서 0으로 이어진다.
    static func yawAttenuation(_ yaw: Double?, tuning: RenderTuning) -> Double {
        guard let yaw, abs(yaw) > tuning.faceShapeYawThreshold else { return 1 }
        return max(0, cos(min(abs(yaw), Double.pi / 2)) / cos(tuning.faceShapeYawThreshold))
    }

    private static func primitives(for key: FaceShapeKey, amount: CGFloat, frame: FaceFrame) -> [ShapePrimitive] {
        let shift = amount * frame.faceWidth
        switch key {
        case .width: return width(frame, shift: shift)
        case .jaw: return jaw(frame, shift: shift)
        case .cheekbone: return cheekbone(frame, shift: shift)
        case .eyeSize: return eyeSize(frame, factor: amount)
        case .eyeDistance: return eyeDistance(frame, shift: shift)
        case .noseWidth: return noseWidth(frame, shift: shift)
        case .mouthSize: return mouthSize(frame, factor: amount)
        case .smile: return smile(frame, shift: shift)
        case .forehead: return forehead(frame, shift: shift)
        case .chinLength: return chinLength(frame, shift: shift)
        }
    }

    /// 눈~입 높이 윤곽점을 중심선 쪽(음수)이나 바깥(양수)으로 민다. 한쪽 합이 shift가 되게 점 수로 나눈다.
    private static func width(_ frame: FaceFrame, shift: CGFloat) -> [ShapePrimitive] {
        let radius = contourRadius * frame.faceWidth
        let sides = contourSides(frame) { frame.mouthLevel <= $0.y && $0.y <= frame.eyeLevel }
        return sides.flatMap { group in
            group.points.map { point in
                let share = group.side * shift / CGFloat(group.points.count)
                return ShapePrimitive.push(center: point, vector: frame.vector(u: share, v: 0), radius: radius)
            }
        }
    }

    /// 입 아래 윤곽점을 안쪽·위(음수, V라인)나 바깥·아래로 민다. 턱 끝 가까운 점은 뺀다.
    private static func jaw(_ frame: FaceFrame, shift: CGFloat) -> [ShapePrimitive] {
        let radius = contourRadius * frame.faceWidth
        let exclusion = jawCenterExclusion * frame.faceWidth
        let sides = contourSides(frame) { $0.y < frame.mouthLevel && abs($0.x) >= exclusion }
        return sides.flatMap { group in
            group.points.map { point in
                let count = CGFloat(group.points.count)
                let vector = frame.vector(u: group.side * shift / count, v: -shift * jawLiftRatio / count)
                return ShapePrimitive.push(center: point, vector: vector, radius: radius)
            }
        }
    }

    /// 각 쪽에서 가장 높은 윤곽점(Vision 윤곽의 위끝, 관자놀이~광대)을 안쪽(음수)이나 바깥으로 민다.
    private static func cheekbone(_ frame: FaceFrame, shift: CGFloat) -> [ShapePrimitive] {
        let radius = cheekboneRadius * frame.faceWidth
        return contourSides(frame) { _ in true }.compactMap { group in
            guard let top = group.points.max(by: { frame.local($0).y < frame.local($1).y }) else { return nil }
            return .push(center: top, vector: frame.vector(u: group.side * shift, v: 0), radius: radius)
        }
    }

    /// 각 눈 중심을 반지름 = 눈 폭 × 1.2로 확대(양수)하거나 축소한다.
    private static func eyeSize(_ frame: FaceFrame, factor: CGFloat) -> [ShapePrimitive] {
        frame.eyes.map { .scale(center: $0.center, factor: factor, radius: $0.width * eyeScaleRadius) }
    }

    /// 각 눈을 중심선에서 멀어지게(양수) 하거나 가깝게 민다.
    private static func eyeDistance(_ frame: FaceFrame, shift: CGFloat) -> [ShapePrimitive] {
        frame.eyes.compactMap { eye in
            let side = side(of: frame.local(eye.center).x)
            guard side != 0 else { return nil }
            return .push(
                center: eye.center, vector: frame.vector(u: side * shift, v: 0), radius: eye.width * eyeShiftRadius)
        }
    }

    /// nose 영역의 좌우 끝점(코 날개)을 noseCrest(없으면 nose) 중심 쪽(음수)이나 바깥으로 민다.
    private static func noseWidth(_ frame: FaceFrame, shift: CGFloat) -> [ShapePrimitive] {
        let nose = frame.points(.nose)
        guard nose.count >= minimumFeaturePoints,
            let leftWing = nose.min(by: { frame.local($0).x < frame.local($1).x }),
            let rightWing = nose.max(by: { frame.local($0).x < frame.local($1).x })
        else { return [] }
        let crest = frame.points(.noseCrest)
        let middle = frame.local(FaceFrame.centroid(crest.isEmpty ? nose : crest)).x
        let radius = noseWingRadius * frame.faceWidth
        return [leftWing, rightWing].compactMap { wing in
            let side = side(of: frame.local(wing).x - middle)
            guard side != 0 else { return nil }
            return .push(center: wing, vector: frame.vector(u: side * shift, v: 0), radius: radius)
        }
    }

    /// 바깥 입술 중심을 확대(양수)하거나 축소한다.
    private static func mouthSize(_ frame: FaceFrame, factor: CGFloat) -> [ShapePrimitive] {
        guard let mouth = mouth(frame) else { return [] }
        return [.scale(center: mouth.center, factor: factor, radius: mouth.width * mouthScaleRadius)]
    }

    /// 입꼬리 두 점을 위·바깥으로 민다. 미소는 0…1이다.
    private static func smile(_ frame: FaceFrame, shift: CGFloat) -> [ShapePrimitive] {
        guard let mouth = mouth(frame) else { return [] }
        let middle = frame.local(mouth.center).x
        let radius = mouth.width * mouthCornerRadius
        return mouth.corners.compactMap { corner in
            let side = side(of: frame.local(corner).x - middle)
            guard side != 0 else { return nil }
            let vector = frame.vector(u: side * smileOutwardRatio * shift, v: shift)
            return .push(center: corner, vector: vector, radius: radius)
        }
    }

    /// 눈썹 위끝에서 얼굴 폭 × 0.3 위를 중심으로 이마를 위(양수, 이마가 넓어짐)나 아래로 민다.
    private static func forehead(_ frame: FaceFrame, shift: CGFloat) -> [ShapePrimitive] {
        let brows = (frame.points(.leftEyebrow) + frame.points(.rightEyebrow)).map(frame.local)
        let browTop = brows.map(\.y).max() ?? frame.eyeLevel + fallbackBrowRise * frame.faceWidth
        let browMiddle = brows.isEmpty ? 0 : brows.map(\.x).reduce(0, +) / CGFloat(brows.count)
        let center = frame.imagePoint(u: browMiddle, v: browTop + foreheadOffset * frame.faceWidth)
        return [.push(center: center, vector: frame.vector(u: 0, v: shift), radius: foreheadRadius * frame.faceWidth)]
    }

    /// 가장 낮은 윤곽점(턱 끝)을 아래(양수, 턱이 길어짐)나 위로 민다.
    private static func chinLength(_ frame: FaceFrame, shift: CGFloat) -> [ShapePrimitive] {
        guard let chin = frame.contour.min(by: { frame.local($0).y < frame.local($1).y }) else { return [] }
        return [.push(center: chin, vector: frame.vector(u: 0, v: -shift), radius: chinRadius * frame.faceWidth)]
    }

    /// 중심선 왼쪽·오른쪽 윤곽점 중 얼굴 좌표 조건에 맞는 점. 중심선 위의 점은 빠진다.
    private static func contourSides(_ frame: FaceFrame, where include: (CGPoint) -> Bool) -> [ContourSide] {
        [CGFloat(-1), 1].map { side in
            ContourSide(
                side: side,
                points: frame.contour.filter { point in
                    let local = frame.local(point)
                    return local.x * side > 0 && include(local)
                })
        }
    }

    private static func mouth(_ frame: FaceFrame) -> Mouth? {
        let lips = frame.points(.outerLips)
        guard lips.count >= minimumFeaturePoints,
            let left = lips.min(by: { frame.local($0).x < frame.local($1).x }),
            let right = lips.max(by: { frame.local($0).x < frame.local($1).x })
        else { return nil }
        let width = frame.local(right).x - frame.local(left).x
        guard width > 0 else { return nil }
        return Mouth(center: FaceFrame.centroid(lips), corners: [left, right], width: width)
    }

    /// 얼굴 좌표 u의 부호. 0이면 0.
    private static func side(of u: CGFloat) -> CGFloat {
        if u > 0 {
            return 1
        }
        if u < 0 {
            return -1
        }
        return 0
    }
}
```

- [ ] **Step 5: 통과 확인**

Run: `cd apple && swift test --filter FaceShapeRigTests` → 13개 PASS. `testExtremeCombinationsNeverFold`가 실패하면 상수를 바꾸지 말고 최솟값과 조합을 보고한다(설계 계산 0.39). 이어서 `cd apple && swift test` → `Executed 205 tests, with 0 failures`(Shared 37 · Rendering 113 · Library 30 · Export 4 · Editing 21). lint 출력 없음.

- [ ] **Step 6: 커밋**

```bash
git add apple/Sources/MellowRendering/Domain/FaceShapeRig.swift apple/Sources/MellowRendering/API/RenderTuning.swift apple/Tests/MellowRenderingTests/RenderingTestSupport.swift apple/Tests/MellowRenderingTests/FaceShapeRigTests.swift
git commit -m "feat(rendering): 얼굴형 10개 항목을 이동 원소로 바꾸는 FaceShapeRig 추가

얼굴 좌표에서 윤곽점·눈·코·입·눈썹을 높이와 좌우로 골라 push·scale 원소를
만든다. 값은 rig가 직접 범위로 자르고, 고개를 돌린 얼굴은 cos 비율로 약하게 한다.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 4: ShapeWarpStage — 얼굴 단계 교체와 옛 얼굴 폭 변형 삭제

**Files:**
- Create: `apple/Sources/MellowRendering/Domain/ShapeWarpStage.swift`
- Delete: `apple/Sources/MellowRendering/Domain/FaceReshapeStage.swift` (`git rm`)
- Modify: `apple/Sources/MellowRendering/API/RenderPipeline.swift` (`standard` 단계 목록)
- Modify: `apple/Sources/MellowRendering/API/RenderTuning.swift` (`faceSlim…` 네 줄 삭제)
- Modify: `apple/Tests/MellowRenderingTests/RenderingTestSupport.swift` (`FaceGeometry.transformed(scale:offset:)`)
- Test: `apple/Tests/MellowRenderingTests/ShapeWarpStageTests.swift`, `apple/Tests/MellowRenderingTests/RenderPipelineTests.swift`

**Interfaces:**
- Consumes: `FaceShapeRig.primitives(face:adjustments:extent:tuning:)`(Task 3), `DisplacementWarp.shared.apply(_:to:extent:limit:)`(Task 1), `RenderContext.targetFaces`, `RenderTuning.shapeDisplacementLimit`, 테스트 지원 `markers`·`markerCentroid`·`expectedPosition`(Task 1).
- Produces: `struct ShapeWarpStage: RenderStage`(이름 `"shapeWarp"`), `func facePrimitives(in:) -> [ShapePrimitive]`, `func bodyPrimitives(in:) -> [ShapePrimitive]`(C에서는 늘 빈 배열, E가 `BodyShapeRig`로 채움). `RenderPipeline.standard` = `skin, shapeWarp, localEdit, geometry, color, detail, look`. 삭제: `FaceReshapeStage`, `RenderTuning.faceSlimShiftFraction`·`faceSlimRadiusFraction`·`faceSlimAnchorX`·`faceSlimAnchorY`. 테스트 지원: `FaceGeometry.transformed(scale:offset:)`.

B0 호환: `portrait.faceSlim`은 B부터 `face.width = −faceSlim`으로 읽힌다(디코드 테스트는 이미 있음). 이 Task는 그 값이 새 단계에서도 얼굴을 좁히는지 렌더로 확인한다. 특징점 없이 상자만 있는 얼굴은 스펙대로 바뀌지 않는다(B0의 상자 기반 변형과 다른 점, VALIDATION에 기록).

- [ ] **Step 1: 테스트 지원 코드**

`RenderingTestSupport.swift` 맨 아래 `extension FaceGeometry` 안에 추가:

```swift
    /// 상자와 특징점을 정규화 좌표에서 scale배 한 뒤 offset만큼 옮긴다. 한 사진에 얼굴 여럿을 놓을 때 쓴다.
    func transformed(scale: Double, offset: NormalizedPoint) -> FaceGeometry {
        func move(_ point: NormalizedPoint) -> NormalizedPoint {
            NormalizedPoint(x: point.x * scale + offset.x, y: point.y * scale + offset.y)
        }
        let box = NormalizedRect(
            x: boundingBox.x * scale + offset.x, y: boundingBox.y * scale + offset.y,
            width: boundingBox.width * scale, height: boundingBox.height * scale)
        return FaceGeometry(boundingBox: box, landmarks: landmarks.mapValues { $0.map(move) }, roll: roll, yaw: yaw)
    }
```

- [ ] **Step 2: 실패하는 테스트 작성**

`apple/Tests/MellowRenderingTests/ShapeWarpStageTests.swift`:

```swift
import CoreImage
import MellowShared
import XCTest

@testable import MellowRendering

final class ShapeWarpStageTests: XCTestCase {
    typealias Support = RenderingTestSupport

    private let extent = SyntheticFace.extent
    private let tuning = RenderTuning()

    /// 윤곽 17점 중 index번째 점의 픽셀 위치. 1과 15는 눈~입 높이의 왼쪽·오른쪽 윤곽이다.
    private func contourPoint(_ index: Int, of face: FaceGeometry) throws -> CGPoint {
        let point = try XCTUnwrap(face.landmarks[.faceContour]?[index])
        return CGPoint(x: point.x * extent.width, y: point.y * extent.height)
    }

    private func context(
        _ face: FaceShapeAdjustments, faces: [FaceGeometry], targetFace: Int? = nil
    ) -> RenderContext {
        var recipe = EditRecipe()
        recipe.portrait.face = face
        recipe.portrait.targetFace = targetFace
        return RenderContext(extent: extent, recipe: recipe, faces: faces, tuning: tuning)
    }

    func testNoFaceEditReturnsInputUnchanged() throws {
        let synthetic = SyntheticFace.make()
        let output = try ShapeWarpStage().apply(
            synthetic.image, in: context(FaceShapeAdjustments(), faces: [synthetic.face]))
        XCTAssertEqual(try Support.bytes(output), try Support.bytes(synthetic.image))
    }

    func testFaceWithoutLandmarksIsUntouched() throws {
        let boxOnly = SyntheticFace.make(landmarks: false)
        let output = try ShapeWarpStage().apply(
            boxOnly.image, in: context(FaceShapeAdjustments(width: -1), faces: [boxOnly.face]))
        XCTAssertEqual(try Support.bytes(output), try Support.bytes(boxOnly.image), "윤곽점이 없으면 원소가 없다")
    }

    func testNarrowWidthMovesContourMarkersTowardCenter() throws {
        let face = SyntheticFace.make().face
        let left = try contourPoint(1, of: face)
        let right = try contourPoint(15, of: face)
        let input = Support.markers([left, right], extent: extent)
        let before = try Support.grid(input)
        let after = try Support.grid(
            ShapeWarpStage().apply(input, in: context(FaceShapeAdjustments(width: -1), faces: [face])))
        let rig = FaceShapeRig.primitives(
            face: face, adjustments: FaceShapeAdjustments(width: -1), extent: extent, tuning: tuning)
        let expectedLeft = Support.expectedPosition(of: left, primitives: rig, limit: tuning.shapeDisplacementLimit)
        let originalLeft = try XCTUnwrap(Support.markerCentroid(before, near: left))
        let originalRight = try XCTUnwrap(Support.markerCentroid(before, near: right))
        let movedLeft = try XCTUnwrap(Support.markerCentroid(after, near: expectedLeft))
        let mirroredExpectation = CGPoint(x: 2 * SyntheticFace.box.midX - expectedLeft.x, y: right.y)
        let movedRight = try XCTUnwrap(Support.markerCentroid(after, near: mirroredExpectation))
        XCTAssertGreaterThan(movedLeft.x - originalLeft.x, 4, "왼쪽 윤곽이 중심 쪽(+x)으로")
        XCTAssertLessThan(movedRight.x - originalRight.x, -4, "오른쪽 윤곽이 중심 쪽(−x)으로")
        XCTAssertEqual(movedLeft.x - originalLeft.x, expectedLeft.x - left.x, accuracy: 0.75, "rig가 예측한 만큼")
        XCTAssertEqual(movedLeft.y, originalLeft.y, accuracy: 0.75, "가로로만")
    }

    func testOutOfRangeFaceValuesRenderLikeClampedValues() throws {
        let synthetic = SyntheticFace.make()
        func render(_ face: FaceShapeAdjustments) throws -> [UInt8] {
            try Support.bytes(ShapeWarpStage().apply(synthetic.image, in: context(face, faces: [synthetic.face])))
        }
        XCTAssertEqual(try render(FaceShapeAdjustments(width: -3)), try render(FaceShapeAdjustments(width: -1)))
        XCTAssertEqual(
            try render(FaceShapeAdjustments(eyeSize: 4, chinLength: -9)),
            try render(FaceShapeAdjustments(eyeSize: 1, chinLength: -1)))
        XCTAssertEqual(
            try render(FaceShapeAdjustments(smile: -0.5)), try Support.bytes(synthetic.image), "범위 밖 미소는 0")
    }

    func testTargetFaceWarpsOnlyThatFace() throws {
        let base = SyntheticFace.make().face
        let leftFace = base.transformed(scale: 0.5, offset: NormalizedPoint(x: 0, y: 0.25))
        let rightFace = base.transformed(scale: 0.5, offset: NormalizedPoint(x: 0.5, y: 0.25))
        let leftMarker = try contourPoint(1, of: leftFace)
        let rightMarker = try contourPoint(1, of: rightFace)
        let input = Support.markers([leftMarker, rightMarker], extent: extent)
        let before = try Support.grid(input)
        let renderContext = context(FaceShapeAdjustments(width: -1), faces: [leftFace, rightFace], targetFace: 0)
        let after = try Support.grid(ShapeWarpStage().apply(input, in: renderContext))
        let originalLeft = try XCTUnwrap(Support.markerCentroid(before, near: leftMarker))
        let originalRight = try XCTUnwrap(Support.markerCentroid(before, near: rightMarker))
        let movedLeft = try XCTUnwrap(Support.markerCentroid(after, near: leftMarker))
        let stayed = try XCTUnwrap(Support.markerCentroid(after, near: rightMarker))
        XCTAssertGreaterThan(movedLeft.x - originalLeft.x, 2, "고른 얼굴은 좁아진다")
        XCTAssertEqual(stayed.x, originalRight.x, accuracy: 0.25, "다른 얼굴은 그대로")
        XCTAssertEqual(stayed.y, originalRight.y, accuracy: 0.25)
    }

    func testLegacyFaceSlimRecipeStillNarrows() throws {
        let json = Data(#"{"schemaVersion":2,"portrait":{"faceSlim":0.3}}"#.utf8)
        let recipe = try JSONDecoder().decode(EditRecipe.self, from: json)
        XCTAssertEqual(recipe.portrait.face.width, -0.3)
        let face = SyntheticFace.make().face
        let left = try contourPoint(1, of: face)
        let input = Support.markers([left], extent: extent)
        let renderContext = RenderContext(extent: extent, recipe: recipe, faces: [face], tuning: tuning)
        let original = try XCTUnwrap(Support.markerCentroid(Support.grid(input), near: left))
        let moved = try XCTUnwrap(
            Support.markerCentroid(Support.grid(ShapeWarpStage().apply(input, in: renderContext)), near: left))
        XCTAssertGreaterThan(moved.x - original.x, 1.5, "B0 얼굴 미세 조정 0.3이 계속 얼굴을 좁힌다")
    }

    func testBodyPrimitivesAreEmptyUntilBodyStage() {
        var recipe = EditRecipe()
        recipe.body.legLength = 1
        let renderContext = RenderContext(extent: extent, recipe: recipe, faces: [], tuning: tuning)
        XCTAssertTrue(ShapeWarpStage().bodyPrimitives(in: renderContext).isEmpty, "체형 원소는 E 단계에서 채운다")
    }
}
```

`RenderPipelineTests.swift`: `testFaceWidthWorksInBothDirections` 전체를 다음으로 바꾼다(상자만 있는 얼굴은 이제 바뀌지 않으므로 특징점이 있는 합성 얼굴을 쓴다).

```swift
    func testFaceWidthWorksInBothDirections() throws {
        let synthetic = SyntheticFace.make()
        var narrow = EditRecipe()
        narrow.portrait.face.width = -1
        var wide = EditRecipe()
        wide.portrait.face.width = 1
        let narrowBytes = try Support.bytes(Support.render(synthetic.image, recipe: narrow, faces: [synthetic.face]))
        let wideBytes = try Support.bytes(Support.render(synthetic.image, recipe: wide, faces: [synthetic.face]))
        XCTAssertNotEqual(narrowBytes, try Support.bytes(synthetic.image))
        XCTAssertNotEqual(wideBytes, try Support.bytes(synthetic.image))
        XCTAssertNotEqual(narrowBytes, wideBytes)
    }
```

`testStageOrderMatters` 전체를 다음으로 바꾼다(얼굴 변형 영역이 수동 잡티의 복제 원본에 걸리도록 합성 얼굴을 쓴다).

```swift
    func testStageOrderMatters() throws {
        let synthetic = SyntheticFace.make()
        let input = synthetic.image
        var recipe = EditRecipe()
        recipe.color.exposure = 0.8
        // 노출·잡티 복제는 둘 다 선형이라 서로 교환된다. 순서 차이는 얼굴형 변형과 수동 잡티 사이에서 드러난다.
        // 잡티 복제 원본(x 0.15 둘레)이 왼쪽 윤곽 변형 영역에 걸친다.
        recipe.portrait.face.width = -1
        recipe.operations = [.spot(RetouchSpot(x: 0.5, y: 0.5, sourceX: 0.15, sourceY: 0.5, radius: 0.2))]
        let context = RenderContext(
            extent: input.extent, recipe: recipe, faces: [synthetic.face], tuning: RenderTuning())
        let standard = try RenderPipeline.standard.render(input, context: context)
        let reversed = try RenderPipeline(stages: RenderPipeline.standard.stages.reversed()).render(
            input, context: context)
        XCTAssertEqual(
            RenderPipeline.standard.stages.map(\.name),
            ["skin", "shapeWarp", "localEdit", "geometry", "color", "detail", "look"])
        XCTAssertNotEqual(try Support.bytes(standard), try Support.bytes(reversed))
    }
```

- [ ] **Step 3: 실패 확인**

Run: `cd apple && swift test --filter 'ShapeWarpStageTests|RenderPipelineTests'` → 컴파일 실패(`cannot find 'ShapeWarpStage' in scope`).

- [ ] **Step 4: 구현**

`apple/Sources/MellowRendering/Domain/ShapeWarpStage.swift`:

```swift
import CoreImage
import MellowShared

/// 얼굴형(C)과 체형(E) 이동 원소를 모아 이동량 지도로 한 번만 변형한다. FaceReshapeStage를 대체한다.
/// 얼굴은 대상 얼굴 모두, 값 범위는 FaceShapeRig가 직접 자른다. 원소가 없으면 입력을 그대로 돌려준다.
struct ShapeWarpStage: RenderStage {
    let name = "shapeWarp"

    func apply(_ image: CIImage, in context: RenderContext) throws -> CIImage {
        let primitives = facePrimitives(in: context) + bodyPrimitives(in: context)
        return try DisplacementWarp.shared.apply(
            primitives, to: image, extent: context.extent, limit: context.tuning.shapeDisplacementLimit)
    }

    func facePrimitives(in context: RenderContext) -> [ShapePrimitive] {
        let adjustments = context.recipe.portrait.face
        guard adjustments.hasEffect else { return [] }
        return context.targetFaces.flatMap { face in
            FaceShapeRig.primitives(face: face, adjustments: adjustments, extent: context.extent, tuning: context.tuning)
        }
    }

    /// 체형 원소 자리. E 단계가 BodyShapeRig 원소로 채운다. 그때까지 빈 배열이다.
    func bodyPrimitives(in context: RenderContext) -> [ShapePrimitive] {
        []
    }
}
```

`RenderPipeline.swift`의 `standard`:

```swift
    public static let standard = RenderPipeline(stages: [
        SkinStage(), ShapeWarpStage(), LocalEditStage(), GeometryStage(), ColorStage(), DetailStage(), LookStage(),
    ])
```

`RenderTuning.swift`에서 다음 네 줄(과 그 앞뒤 빈 줄 하나)을 지운다:

```swift
    public var faceSlimShiftFraction: Double = 0.035
    public var faceSlimRadiusFraction: Double = 0.34
    public var faceSlimAnchorX: Double = 0.12
    public var faceSlimAnchorY: Double = 0.36
```

`git rm apple/Sources/MellowRendering/Domain/FaceReshapeStage.swift`.

- [ ] **Step 5: 통과 확인**

Run: `cd apple && swift test` → `Executed 212 tests, with 0 failures`(Shared 37 · Rendering 120 · Library 30 · Export 4 · Editing 21). `testPortraitStagesChangeOnlyWhenFacesExist`·`testTargetFaceLimitsPortraitStagesToOneFace`·`PhotoPipelineTests`는 고치지 않고 통과해야 한다. `grep -rn "FaceReshape\|faceReshape\|faceSlimShift\|faceSlimRadius\|faceSlimAnchor" apple/Sources apple/Tests` → 결과 없음. lint 출력 없음. Mac 앱 테스트 → `Executed 51 tests, with 0 failures`(B 시나리오는 상자만 있는 스텁 얼굴이라 얼굴 폭은 미리보기를 바꾸지 않지만 피부 보정이 바꾸므로 통과한다. Task 5에서 특징점 스텁으로 바꾼다).

- [ ] **Step 6: 커밋**

```bash
git add apple/Sources/MellowRendering apple/Tests/MellowRenderingTests
git commit -m "feat(rendering): 얼굴 단계를 이동량 지도 기반 shapeWarp로 교체

대상 얼굴 모두의 얼굴형 원소를 모아 DisplacementWarp로 한 번만 샘플링하고,
체형 원소 자리는 빈 배열로 남긴다. 옛 FaceReshapeStage와 faceSlim 상수를 지운다.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 5: 앱 — 얼굴 탭 슬라이더 10개와 C 시나리오

**Files:**
- Modify: `apple/MellowPhoto/Features/Editor/BeautyPanel.swift` (`faceControls`)
- Modify: `apple/MellowPhoto/Application/UserMessage.swift` (`faceShapeTitle(_:)`, `faceWidth` 삭제, `faceHint` 문구)
- Modify: `apple/MellowPhotoTests/TestSupport.swift` (`landmarkedFace(in:)`)
- Test: `apple/MellowPhotoTests/AppModelTests.swift`, `apple/MellowPhotoTests/EditorScenarioTests.swift`

**Interfaces:**
- Consumes: `EditChange.faceShape(_:_:)`, `EditingPolicy.faceShapeRange(_:)`(Task 2), `AdjustmentSlider(title:value:range:snapsToZero:change:)`, `AppModel.isGeometryLocked`·`beautyTab`, `ShapeWarpStage`(Task 4, 미리보기 경유).
- Produces: `UserMessage.faceShapeTitle(_ key: FaceShapeKey) -> String`(얼굴 폭·턱선·광대·눈 크기·눈 간격·코 폭·입 크기·미소·이마·턱 길이). `UserMessage.faceWidth` 삭제. `TestSupport.landmarkedFace(in: NormalizedRect) -> FaceGeometry`. 앱 파일 추가·삭제 없음(xcodegen 불필요).

- [ ] **Step 1: 실패하는 테스트 작성**

`TestSupport.swift`의 `enum TestSupport` 안, `sharedLookCatalog` 아래에 추가:

```swift
    /// box 안에 비율로 놓은 가짜 특징점 얼굴. 윤곽은 Vision처럼 한쪽 관자놀이에서 턱을 지나 반대쪽까지 17점이다.
    static func landmarkedFace(in box: NormalizedRect) -> FaceGeometry {
        func point(_ x: Double, _ y: Double) -> NormalizedPoint {
            NormalizedPoint(x: box.minX + box.width * x, y: box.minY + box.height * y)
        }
        func ellipse(_ centerX: Double, _ centerY: Double, _ radiusX: Double, _ radiusY: Double) -> [NormalizedPoint] {
            (0..<12).map { step in
                let angle = 2 * Double.pi * Double(step) / 12
                return point(centerX + radiusX * cos(angle), centerY + radiusY * sin(angle))
            }
        }
        let contour = (0...16).map { step -> NormalizedPoint in
            let angle = Double.pi + Double.pi * Double(step) / 16
            return point(0.5 + 0.5 * cos(angle), 0.6 + 0.6 * sin(angle))
        }
        return FaceGeometry(
            boundingBox: box,
            landmarks: [
                .faceContour: contour,
                .leftEye: ellipse(0.3, 0.63, 0.1, 0.04), .rightEye: ellipse(0.7, 0.63, 0.1, 0.04),
                .leftPupil: [point(0.3, 0.63)], .rightPupil: [point(0.7, 0.63)],
                .leftEyebrow: ellipse(0.3, 0.75, 0.12, 0.02), .rightEyebrow: ellipse(0.7, 0.75, 0.12, 0.02),
                .nose: [point(0.42, 0.4), point(0.58, 0.4), point(0.5, 0.55)],
                .noseCrest: [point(0.5, 0.55), point(0.5, 0.45)],
                .outerLips: ellipse(0.5, 0.27, 0.17, 0.06), .innerLips: ellipse(0.5, 0.27, 0.13, 0.02),
            ])
    }
```

`AppModelTests.swift` 맨 아래(`testBeautyTabSurvivesToolSwitch` 뒤)에 추가:

```swift
    func testFaceTabEditsEveryShapeKeyOneUndoStepEach() async throws {
        let staged = try TestSupport.solidPNG(in: root)
        let model = TestSupport.makeModel(
            root: root, importer: FakeImporter(staged: [.success(StagedPhoto(url: staged, displayName: nil))]))
        try await importOne(model, staged)
        model.selectTool(.beauty)
        model.beautyTab = .face
        for key in FaceShapeKey.allCases {
            model.beginSliderEdit()
            model.edit(.faceShape(key, 0.3))
            model.edit(.faceShape(key, 0.4))
            model.endSliderEdit()
        }
        for key in FaceShapeKey.allCases {
            XCTAssertEqual(model.currentRecipe.portrait.face[key], 0.4, accuracy: 1e-9, "\(key)")
        }
        XCTAssertEqual(model.session.selected?.document.undoStack.count, FaceShapeKey.allCases.count)
        let titles = FaceShapeKey.allCases.map(UserMessage.faceShapeTitle)
        XCTAssertEqual(Set(titles).count, FaceShapeKey.allCases.count, "슬라이더 이름이 겹치지 않는다")
        XCTAssertEqual(titles.first, "얼굴 폭")
        model.undo()
        XCTAssertEqual(model.currentRecipe.portrait.face.chinLength, 0, "실행 취소 한 번에 마지막 슬라이더만")
        XCTAssertEqual(model.currentRecipe.portrait.face.forehead, 0.4, accuracy: 1e-9)
    }

    func testGeometryLockRejectsEveryFaceShapeKey() async throws {
        let staged = try TestSupport.solidPNG(in: root)
        let model = TestSupport.makeModel(
            root: root, importer: FakeImporter(staged: [.success(StagedPhoto(url: staged, displayName: nil))]))
        try await importOne(model, staged)
        model.tool = .retouch
        model.touch(from: NormalizedPoint(x: 0.3, y: 0.3), to: NormalizedPoint(x: 0.3, y: 0.3))
        model.touch(from: NormalizedPoint(x: 0.5, y: 0.5), to: NormalizedPoint(x: 0.5, y: 0.5))
        XCTAssertEqual(model.currentRecipe.operations.count, 1)
        try await waitUntil { !model.isRendering }
        XCTAssertTrue(model.isGeometryLocked)
        for key in FaceShapeKey.allCases {
            model.edit(.faceShape(key, 0.5))
            XCTAssertEqual(model.currentRecipe.portrait.face[key], 0, "\(key)는 잠겨 있다")
        }
        XCTAssertEqual(model.statusMessage, UserMessage.geometryLocked)
    }
```

`EditorScenarioTests.swift`: `demoFace`와 `testBeautySkinAndFaceWidthThenExportSucceeds`를 다음으로 바꾼다(스펙 8 시나리오의 C 단계).

```swift
    /// 공용 픽스처의 얼굴 위치를 어림한 스텁 얼굴. 얼굴형이 동작하도록 상자 비율로 놓은 가짜 특징점을 단다.
    private static let demoFace = TestSupport.landmarkedFace(
        in: NormalizedRect(x: 0.33, y: 0.36, width: 0.38, height: 0.4))

    private func previewBytes(_ model: AppModel) -> [UInt8] {
        model.preview.map { Array($0.dataProvider!.data! as Data) } ?? []
    }

    func testBeautySkinThenFaceShapeThenExportSucceeds() async throws {
        let model = TestSupport.makeModel(
            root: root, analyzer: StubFaceAnalyzer(result: .success([Self.demoFace])),
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

        let recipe = model.currentRecipe
        XCTAssertEqual(recipe.portrait.skin, SkinAdjustments(smoothing: 0.5, autoBlemish: true))
        XCTAssertEqual(recipe.portrait.face, FaceShapeAdjustments(width: -0.5, eyeSize: 0.3, smile: 0.4))
        let size = try await exportedPixelSize(model)
        XCTAssertEqual(size.width, size.height, "정사각형 원본이 그대로 저장된다")
    }
```

- [ ] **Step 2: 실패 확인**

Run: `xcodebuild -project apple/MellowPhoto.xcodeproj -scheme MellowPhoto -derivedDataPath apple/build -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO build-for-testing 2>&1 | grep -c "error:"` → 0보다 큼(`faceShapeTitle` 없음).

- [ ] **Step 3: 구현**

`UserMessage.swift`: `static let faceWidth = "얼굴 폭"` 줄을 지우고, `faceHint`를 다음으로 바꾼다:

```swift
    static let faceHint = "가운데가 원래 모양이에요. 얼굴 형태를 먼저 조정한 뒤 잡티를 보정해 주세요."
```

함수 묶음(`faceOrdinal` 아래)에 추가:

```swift
    /// 뷰티 › 얼굴 탭 슬라이더 이름. 화면 순서는 FaceShapeKey.allCases.
    static func faceShapeTitle(_ key: FaceShapeKey) -> String {
        switch key {
        case .width: return "얼굴 폭"
        case .jaw: return "턱선"
        case .cheekbone: return "광대"
        case .eyeSize: return "눈 크기"
        case .eyeDistance: return "눈 간격"
        case .noseWidth: return "코 폭"
        case .mouthSize: return "입 크기"
        case .smile: return "미소"
        case .forehead: return "이마"
        case .chinLength: return "턱 길이"
        }
    }
```

`BeautyPanel.swift`의 `faceControls` 전체:

```swift
    /// 얼굴형 슬라이더 10개. 미소만 0…1, 나머지는 가운데 0인 양방향이고 0 근처에서 0에 붙는다.
    @ViewBuilder
    private func faceControls(_ face: FaceShapeAdjustments) -> some View {
        ForEach(FaceShapeKey.allCases, id: \.self) { key in
            let range = EditingPolicy.faceShapeRange(key)
            AdjustmentSlider(
                title: UserMessage.faceShapeTitle(key), value: face[key], range: range,
                snapsToZero: range.lowerBound < 0
            ) { .faceShape(key, $0) }
            .disabled(model.isGeometryLocked)
        }
        Text(model.isGeometryLocked ? UserMessage.geometryLocked : UserMessage.faceHint)
            .font(.caption).foregroundStyle(.secondary)
    }
```

- [ ] **Step 4: 통과 확인**

Run: Mac 앱 테스트 → `Executed 53 tests, with 0 failures`. `cd apple && swift test` → `Executed 212 tests, with 0 failures`. lint 출력 없음. `./scripts/verify-modules.sh` 통과. `grep -rn "UserMessage.faceWidth" apple` → 결과 없음. iOS 시뮬레이터 테스트는 돌리지 않는다(Task 6).

- [ ] **Step 5: 커밋**

```bash
git add apple/MellowPhoto/Features/Editor/BeautyPanel.swift apple/MellowPhoto/Application/UserMessage.swift apple/MellowPhotoTests/TestSupport.swift apple/MellowPhotoTests/AppModelTests.swift apple/MellowPhotoTests/EditorScenarioTests.swift
git commit -m "feat(app): 뷰티 얼굴 탭에 얼굴형 슬라이더 10개 추가

얼굴 폭·턱선·광대·눈 크기·눈 간격·코 폭·입 크기·미소·이마·턱 길이를 둔다.
미소만 한 방향이고 나머지는 0 근처에서 붙는다. 수동 편집이 있으면 모두 잠긴다.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 6: 문서·검증 기록

**Files:**
- Modify: `README.md`, `docs/APPLE.md`, `docs/architecture/modules.md`, `VALIDATION.md`

**Interfaces:**
- Consumes: Task 1~5 결과와 `./scripts/test-apple.sh`·`./scripts/build-apple.sh` 출력.
- Produces: 문서. 이후 Task 없음.

- [ ] **Step 1: 최종 검증 실행**

Run: `./scripts/test-apple.sh; echo "exit=$?"` → `exit=0`, 패키지 `Executed 212 tests, with 0 failures`, 앱 iPhone `Executed 52 tests`·iPad `Executed 52 tests`·Mac `Executed 53 tests`(모두 0 failures). 이어서 `./scripts/build-apple.sh ios-device; echo "exit=$?"`와 `./scripts/build-apple.sh mac; echo "exit=$?"` → 둘 다 `exit=0`. 빌드 로그의 경고가 Global Constraints의 허용 목록(이번에 `DisplacementWarp.swift`의 커널 언어 지원 중단 경고가 늘어남)뿐인지 본다. 실제 숫자·종료 코드·커밋 해시(`git rev-parse --short HEAD`)를 적어 두고 아래 문서에 그대로 쓴다. 기대와 다르면 실제 값을 쓰고, 실패면 통과로 쓰지 않는다.

- [ ] **Step 2: README·APPLE.md·modules.md**

`README.md`:
- "첫 보정" 5번의 "뷰티 값(피부 보정·자동 잡티·얼굴 폭)"을 "뷰티 값(피부 보정·자동 잡티·얼굴형 10개)"으로.
- 6번을 "**뷰티**에서 감지된 얼굴을 고르고 *피부* 탭의 피부 보정·자동 잡티, *얼굴* 탭의 얼굴 폭·턱선·광대·눈 크기·눈 간격·코 폭·입 크기·미소·이마·턱 길이를 씁니다. 미소만 0에서 시작하고 나머지는 가운데가 원래 모양(왼쪽은 줄이고 오른쪽은 키움)입니다. 얼굴 번호는 화면 왼쪽부터입니다."로.
- 41행의 "얼굴 폭과 얼굴 선택은 잠깁니다"를 "얼굴형 슬라이더와 얼굴 선택은 잠깁니다"로.
- "구현된 범위"의 "얼굴 양옆의 약한 국소 변형, 수동 드래그 변형"을 "얼굴 윤곽점·눈·코·입 위치로 만든 얼굴형 보정 10종(모든 얼굴형 변형을 이동량 지도 하나로 합쳐 한 번만 다시 그림), 수동 드래그 변형"으로.
- 한계 문단 첫 문장 뒤에 "얼굴형 보정도 학습 모델 없이 Vision 특징점으로 동작하며, 고개를 20° 넘게 돌린 얼굴은 약하게, 옆얼굴과 윤곽점을 찾지 못한 얼굴은 바꾸지 않습니다. 얼굴 가까운 직선 배경이 살짝 휠 수 있습니다."를 넣는다.
- 로드맵 "C 얼굴 리셰이프" 줄을 "**C 얼굴 리셰이프**: 얼굴형 슬라이더 10개와 이동량 지도 (`portrait.face`) — 구현됨, 실제 인물 사진 확인은 사용자 조치로 남음"으로.

`docs/APPLE.md`:
- 자동 줄의 "얼굴 폭·체형·메이크업은 건드리지 않습니다"를 "얼굴형·체형·메이크업은 건드리지 않습니다"로.
- 뷰티 줄의 "얼굴 탭은 가운데 0인 *얼굴 폭*. 수동 잡티·변형이 있으면 얼굴 폭과 얼굴 선택이 잠깁니다."를 "얼굴 탭은 *얼굴 폭·턱선·광대·눈 크기·눈 간격·코 폭·입 크기·미소·이마·턱 길이* 10개이고 미소를 뺀 9개는 가운데 0인 양방향(0 근처에서 붙음)입니다. 얼굴형 변형은 모두 한 번에 다시 그립니다. 고개를 많이 돌린 얼굴은 약하게 적용됩니다. 수동 잡티·변형이 있으면 얼굴형 슬라이더와 얼굴 선택이 잠깁니다."로.
- "검증 상태" 문단을 Step 1의 실제 결과(브랜치 `beauty-b-to-f`, 커밋, 종료 코드, 패키지 212개(MellowShared 37 · MellowRendering 120 · MellowLibrary 30 · MellowExport 4 · MellowEditing 21), 앱 iPhone 52 · iPad 52 · Mac 53 예상)로 바꾼다. B 절의 bash 3.2 이력 문장은 지운다(VALIDATION B 절에 남아 있음).
- 기기 확인 항목에 "얼굴형 10종의 실제 사진 결과(과한 값, 기울어진 얼굴, 배경 직선 휨)"를 더한다.

`docs/architecture/modules.md`:
- MellowShared 공개 API에 `AdjustmentRange`를 더하고 규칙에 "값 범위(unit 0…1·bipolar −1…1·얼굴형은 미소만 unit)는 `AdjustmentRange` 한 곳"을 더한다.
- MellowEditing 규칙의 "값 범위는 `EditingPolicy`(unitRange·bipolarRange·faceShapeRange)"를 "값 범위는 `EditingPolicy`(unitRange·bipolarRange·faceShapeRange, 값은 MellowShared `AdjustmentRange`를 그대로 내보냄)"로.
- MellowRendering 규칙의 단계 순서를 `skin` → `shapeWarp` → `localEdit` → `geometry` → `color` → `detail` → `look`으로 바꾸고 다음을 더한다: "얼굴형·체형 변형은 `ShapeWarpStage` 하나가 이동 원소(`ShapePrimitive` push·scale·band)를 모아 `DisplacementWarp`로 한 번만 샘플링(out(p) = in(p − D(p)), 원소마다 반지름 × `shapeDisplacementLimit`), 이동량 지도 CIKL 커널은 `DisplacementWarp` 한 곳, 얼굴형 원소는 `FaceShapeRig`가 `FaceFrame`(눈동자 기준 얼굴 좌표)에서 만들고 값을 `AdjustmentRange`로 직접 자름, |yaw| > `faceShapeYawThreshold`면 cos 비율로 약화, 윤곽점이 없으면 원소 없음, 체형 원소 자리 `bodyPrimitives`는 E까지 빈 배열". 테스트 칸에 "이동량 지도(점 표식 이동·원소 합·띠 단조성), 얼굴 좌표계(기울기·뒤집힘·대체 경로), 얼굴형 원소 방향·대칭·회전·클램프·접힘 검사·데모 사진 특징점, 얼굴 단계 렌더"를 더한다.
- 앱 타깃 `Application/` 설명의 `BeautyTab`(피부·얼굴)은 그대로 둔다.

- [ ] **Step 3: VALIDATION.md**

`## 인물 보정 B 피부 (2026-10-15)` 절 뒤, `## TestFlight 전용 배포 경로` 앞에 `## 인물 보정 C 얼굴 리셰이프 (2026-10-15)` 절을 쓴다. 사람 확인 영역만 있고, 실행한 것만 통과로 쓴다.
- 첫 문단: 브랜치·커밋·환경(B 절과 같은 형식), "이 절의 검증은 모두 자동 테스트와 빌드이며, 앱 화면을 직접 보거나 조작한 검증은 없습니다."
- `### 자동 검증`: `./scripts/test-apple.sh` 종료 코드, 패키지 테스트 수(모듈별), 앱 테스트 수(iPhone·iPad·Mac), `build-apple.sh ios-device`·`mac` 종료 코드, 빌드 경고(기존 `WarpKernel`·`SkinKernels`에 더해 `DisplacementWarp`의 Core Image 커널 언어 지원 중단 경고).
- `### 자동 테스트가 확인하는 것`: 이동량 지도(원소가 없으면 같은 바이트, push가 점을 정확한 위치로 옮김, 음수 방향, 두 원소의 이동이 합과 같음, scale 확대, 원소별 상한, 띠의 단조·연속과 띠 아래 이동, 가장자리 불투명), 얼굴 좌표계(30° 기울기·뒤집힌 얼굴·눈동자 없을 때 대체), 얼굴형 원소(얼굴 폭 −1은 왼쪽 +x·오른쪽 −x, 턱선·광대·이마·턱 길이·눈·코·입 방향, 열 항목 좌우 대칭, 30° 기울면 원소도 30° 회전, 범위 밖 값 클램프, yaw 약화와 옆얼굴, 특징점이 빠진 항목만 건너뜀, ±1 조합 세 가지에서 접힘 없음(야코비안 최솟값 > 0.2), 데모 사진의 실제 특징점으로 열 항목 모두 원소 생성), 얼굴 단계 렌더(윤곽 표식이 중심 쪽으로 이동, 범위 밖 값이 잘린 값과 같은 결과, 고른 얼굴만 변형, B0 `faceSlim` 0.3 레시피가 계속 좁힘), 앱(얼굴 탭 10개 슬라이더 실행 취소 단위, 잠금 시 10개 모두 거부), 시나리오(데모 사진 → 피부 0.5 + 자동 잡티 → 얼굴 폭 −0.5·눈 크기 0.3·미소 0.4로 미리보기가 다시 바뀜 → 정사각형 저장). "합성 얼굴과 데모 사진 한 장으로 돌며, 실제 인물 사진에서 보기 좋은지는 판단하지 않습니다."
- `### 스펙과 다르게 한 것`: 이동량 지도를 그라데이션 덧셈 대신 CIKL 색 커널로 만듦(음수 값 보존), 값 범위 정의를 `AdjustmentRange`로 옮김(렌더 모듈이 편집 모듈을 쓸 수 없음), 광대는 "눈 높이 윤곽점" 대신 각 쪽 맨 위 윤곽점, 같은 쪽 윤곽점은 이동을 나눠 가짐, `FaceShapeRig.primitives`에 `tuning` 인자 추가, scale·band의 원소별 상한은 배율·늘림 비율로 정의, yaw 약화는 cos(|yaw|)/cos(0.35)로 0.35에서 연속. Task 1의 예외 경로(색 커널을 일반 커널로 바꿈)를 썼다면 그것도 적는다.
- `### 미검증 (사용자 확인 필요)`: 실제 인물 사진에서 얼굴형 10종의 느낌과 최대값이 과하거나 약한지, 여러 슬라이더를 함께 끝까지 올린 실제 사진, 기울어진 얼굴·고개를 돌린 얼굴, 눈 점이 없는 얼굴에서 쓰는 Vision roll 부호, 상자만 있는 얼굴에서 B0 세션의 얼굴 미세 조정이 더는 적용되지 않는 점, 얼굴 가까운 직선 배경 휨, 여러 얼굴 사진, 48MP 원본 저장 속도와 메모리, 얼굴 탭 화면(슬라이더 10개 배치, 0 근처 붙음, 잠금 안내, 좁은 화면 스크롤), 실기기. "이전 절(B, B0, 구조 리팩토링 A)의 미검증 항목은 그대로 승계합니다."

- [ ] **Step 4: 커밋**

```bash
git add README.md docs/APPLE.md docs/architecture/modules.md VALIDATION.md
git commit -m "docs: 얼굴 리셰이프 사용법·모듈 캔버스·C 검증 기록 갱신

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

## 자체 검토 결과

- **스펙 대조:** §1.1 모듈 배치 → `ShapePrimitive`·`DisplacementWarp`(Task 1), `FaceShapeRig`(Task 3), `ShapeWarpStage`(Task 4)는 모두 Rendering/Domain, 새 import 없음, `verify-modules.sh` 불변. §1.3 순서 → Task 4가 `faceReshape`를 `shapeWarp`로 바꾸고 `testStageOrderMatters` 배열 갱신(나머지 단계 feature·makeup·background는 D·F). §1.5 이동량 지도 → Task 1(push·scale·band, RG float 지도, 일반 커널 한 번, 원소별 상한, 테스트 3종: 0개 같은 바이트·push 방향·두 원소 합). 수동 변형(`LocalEditStage.applyWarp`) 불변. §3 → Task 2(얼굴 좌표계: 상자 중심·눈동자 x축·roll), Task 3(10개 항목 표, 항목별 상한 `RenderTuning`, |yaw| > 0.35 cos 약화, 윤곽점 없으면 빈 배열), Task 4(대상 얼굴 모두 + 체형 자리, 원소 없으면 입력 그대로), Task 5(UI: 슬라이더 10개, 미소만 0…1, 나머지 0 근처 스냅). §3 테스트 → width −1 방향(Task 3 `testNarrowWidth…`), 좌우 대칭(`testAllKeysAreMirrorSymmetric`), roll 30°(`testRollRotatesPrimitives`), 값 0 빈 배열(`testZeroValuesProduceNoPrimitives`), 렌더 표식 이동(Task 4 `testNarrowWidthMovesContourMarkersTowardCenter`), faceSlim 이행(Task 4 `testLegacyFaceSlimRecipeStillNarrows`, 디코드는 B 테스트). §7 → `UserMessage` 슬라이더 이름(Task 5), `Theme.bipolarSnapWidth`는 B에서 있음. §8 → 각 Task 테스트, `RenderPipelineTests` 순서 배열(Task 4), `AppModelTests`(Task 5), 시나리오 C 단계(Task 5), 전체 검증·VALIDATION(Task 6). §9 → 이 파일 이름과 주요 Task가 표와 같다. B 이월(ShapeWarpStage가 모든 얼굴 키를 직접 클램프) → Task 3 rig 클램프 + Task 4 렌더 테스트.
- **스펙과 다르게 정한 점:** 지도 래스터를 CIKL 색 커널로(스펙은 그라데이션·덧셈 합성), 값 범위 정의를 `AdjustmentRange`로 이동(스펙은 `EditingPolicy` 한 곳이라 했지만 렌더 모듈이 쓸 수 없음), 광대는 각 쪽 맨 위 윤곽점, `primitives`에 `tuning` 인자, scale·band 상한 정의, yaw 약화를 기준값에서 연속이 되게 정규화.
- **타입 일관성:** `ShapePrimitive` 케이스·`limited(to:)`·`displacement(at:)`, `DisplacementWarp.apply(_:to:extent:limit:)`·`displacement(at:of:limit:)`를 Task 1·3·4와 테스트 지원에서 같게 썼다. `FaceFrame`의 `local`·`vector(u:v:)`·`imagePoint(u:v:)`·`points(_:)`·`centroid(_:)`·`eyes`·`eyeLevel`·`mouthLevel`은 Task 2에서 정의하고 Task 3이 쓴다. `RenderTuning.faceShapeMaxShift(_:)`와 상수 이름은 Task 3·테스트에서 같다. `AdjustmentRange.faceShape`·`clamped`는 Task 2에서 정의하고 Task 3이 쓴다. 테스트 지원 `markers`·`markerCentroid`·`expectedPosition`(Task 1), `pivot`·`rotated`·`removing`(Task 2), `minimumJacobian`(Task 3), `transformed`(Task 4)는 앞 Task에서 정의된다. 테스트 수: 175 → 184 → 192 → 205 → 212, 앱 Mac 51 → 53.
- **Review Focus 매핑:** 1→Task 4(+Task 3), 2→Task 3, 3→Task 3, 4→Task 3, 5→Task 1. 모두 테스트 코드가 있다.
- **플레이스홀더 점검:** "TBD/TODO/나중에" 없음. `bodyPrimitives`의 빈 배열은 스펙이 정한 E 이음매다. Task 6 문서 수치는 실제 실행 결과로 쓴다.
