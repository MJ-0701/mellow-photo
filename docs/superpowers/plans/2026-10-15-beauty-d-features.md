# 인물 보정 D 눈·치아·입술·배경 구현 계획

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 뷰티 › 눈·입 탭에 눈 또렷하게·치아 미백·입술 생기 슬라이더를, 새 배경 도구에 배경 흐림 슬라이더를 더하고, 사진 준비 때 인물 영역을 분석해 사람은 그대로 두고 배경만 흐린다.

**Architecture:** 사진 준비 때 계산한 얼굴·잡티·인물 마스크를 `PhotoAnalysis` 하나로 묶어 `RenderContext`에 넘기고, 다각형 마스크 비트맵은 그 묶음이 가진 `RegionMaskCache`가 사진마다 한 번만 그린다. 인물 분석은 `PersonAnalyzer` 포트(`VisionPersonAnalyzer` = `VNGeneratePersonSegmentationRequest`)로 하고 실패는 `PreparedPhoto.personAnalysisFailure`로 남긴다. `FaceRegions`가 눈·눈동자·입술·치아 마스크를 만들고 `FeatureKernels`(CIKL 색 커널 2개)가 감마 YCbCr에서 영역 가중치와 색 이동을 계산한다. 새 단계 `FeatureStage`(`feature`)와 `BackgroundStage`(`background`)를 `skin` 뒤에 둔다. 마스크가 없으면 단계만 건너뛴다.

**Tech Stack:** Swift 5.9 tools / Swift 5 언어 모드, SwiftUI + Observation, Core Image(CIKL `CIColorKernel` 2개, `CIMaskedVariableBlur`, `CISharpenLuminance`), Vision(`VNDetectFaceLandmarksRequest` 기존, `VNGeneratePersonSegmentationRequest` 새로), XCTest, XcodeGen 2.46.0.

**Spec:** `docs/superpowers/specs/2026-10-15-beauty-b-to-f-design.md` (D에 해당하는 절: 1.1~1.4, 4, 7, 8, 9). B 실행 기록 `.superpowers/sdd/2026-10-15-beauty-b-skin/progress.md`의 D 이월 항목(분석 결과 묶음, 마스크 비트맵 캐시, 인물 분석 실패 시 그 단계만 건너뛰기, `FaceRegions` 다각형 함수 공개, 잡티 검출 시점 결정)과 C 실행 기록 `.superpowers/sdd/2026-10-15-beauty-c-face/progress.md`의 검증 방식(Ruling C1)을 포함한다.

## 사람이 확인할 것

- **순서.** Task 1 분석 묶음·마스크 캐시 → 2 인물 분석 → 3 눈·입 영역 마스크 → 4 눈·입 보정 단계 → 5 배경 흐림 단계 → 6 편집 변경·자동 보정 → 7 눈·입 탭 → 8 배경 도구·D 시나리오 → 9 문서·전체 검증. 9개 Task, Task마다 Opus 구현 → 리뷰 → 수정, 끝에 전체 리뷰.
- **외부 효과가 있는 단계.** 없음. 푸시·태그·TestFlight는 F를 마친 뒤(스펙 "외부 효과가 있는 단계").
- **스펙이 정하지 않아 이 계획이 정한 것.**

| 결정 | 이유 | 바꾸면 비용 |
|---|---|---|
| 사진 분석 결과(얼굴·잡티·인물 마스크)를 묶음 하나로 렌더에 넘긴다 | B 리뷰 이월. E의 관절점도 같은 묶음에 더해 렌더 인자 목록이 늘지 않는다 | 작음 |
| 피부·눈·입 다각형 마스크 비트맵을 사진마다 저장해 두고, 미리보기가 캐시에서 밀려난 사진은 버린다 | 슬라이더를 움직일 때마다 다시 그리지 않는다. 메모리는 최근 사진 3장 몫(장당 수 MB 이하)만 | 작음 |
| 인물 분석은 Vision 기본 품질, 사람 픽셀이 1% 미만이면 "사람 없음" | Mac에서 장당 약 0.01초(첫 장 0.08초). 결과 마스크가 512×384 고정이라 경계를 부드럽게 처리한다 | 작음 |
| 인물 분석 실패는 가져오기 경고로 띄우지 않고 배경 도구 안에서만 알린다 | 시뮬레이터처럼 늘 실패하는 환경에서 가져올 때마다 알림이 뜨지 않게 | 작음 |
| 사람이 없거나 인물 분석이 실패하면 미리보기·저장 모두 배경 흐림만 빼고 진행(오류 아님) | 스펙 1.4. 얼굴 보정 분석 실패는 지금처럼 저장을 막는다 | 작음 |
| 자동 잡티 검출은 지금처럼 사진 준비 때 늘 한다 | 장당 약 0.06초이고 스펙 1.4가 분석을 준비 때 한 번으로 정했다. 스위치를 켤 때 지연이 없다 | 작음 |
| 눈·입 보정은 특징점이 있는 얼굴에만 하고 빠진 부위만 건너뛴다 | 얼굴 상자만으로는 흰자·치아 위치를 알 수 없다 | 작음 |
| 입이 열렸는지는 안쪽 입술 넓이가 얼굴 상자의 0.4% 이상인지로 본다 | 다문 입은 0.3% 안팎, 치아가 보이는 입은 1% 이상 | 작음 |
| 시작 강도(최대값 1 기준): 흰자를 흰색 쪽으로 20%, 홍채 선명도 0.8, 치아 노란기 70% 제거 + 흰색 쪽 12%, 입술 채도 +30% + 붉은기 소폭, 배경 흐림 반지름 짧은 변의 2%(미리보기 약 24px, 1200만 화소 원본 약 60px) | 메이투·Evoto의 "자연스러운 최대" 어림. 실사진 피드백으로 `RenderTuning` 한 곳에서 조정 | 작음 |
| 배경 도구는 도구 줄의 뷰티 다음 자리. 사람이 없으면 슬라이더를 끄고 안내를 보인다 | 프리셋으로 들어온 흐림 값도 보이게 한다. E·F가 체형·메이크업을 뷰티와 배경 사이에 넣는다 | 작음 |

- **범위 밖.** 배경 색 바꾸기·교체·제거(스펙 범위 밖), 머리카락 경계 정밀 분할, 메이크업(F), 체형(E). 자동 보정의 치아·입술·배경 값(스펙 7은 눈 또렷하게 0.2만).
- **위험.** 흐린 배경에 사람 가장자리 색이 살짝 번질 수 있다(후광). 머리카락·손가락 경계는 Vision 마스크 품질에 따른다. 노란 조명이나 진한 그림자에서는 흰자·치아 판별이 흔들린다. iOS 시뮬레이터에서 Vision 인물 분석이 실패할 수 있다(실패해도 안내만 뜨고 다른 보정은 동작). 보정 품질은 자동 테스트로 판정할 수 없다.
- **사용자 조치.** 이 계획 안에는 없다. 실제 인물 사진으로 눈·치아·입술·배경 결과를 보는 것은 F 뒤 1.2.0 TestFlight에서 한다(스펙 사용자 조치).

---

## 에이전트 참조

## Global Constraints

- 작업 위치: worktree `/Users/mj/IdeaProjects/mellow-photo/.claude/worktrees/b0-basic-editing`, 브랜치 `beauty-b-to-f`(시작 HEAD `11be2c6`, B·C 구현·리뷰 완료). 부모 저장소로 `cd`하지 않는다. 모든 Swift·xcodebuild 명령 전에 `export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`.
- 모듈 의존성 표(`docs/architecture/modules.md`)와 `scripts/verify-modules.sh`는 바뀌지 않는다. MellowRendering의 import는 `CoreImage`·`Foundation`·`MellowShared`·`Vision`만 쓴다(`CVPixelBuffer` 함수는 `CoreImage`·`Vision`으로 들어온다). MellowShared는 Foundation·CoreGraphics만. MellowRendering은 MellowEditing을 import할 수 없다(값 범위는 MellowShared `AdjustmentRange`).
- 새 보정은 MellowRendering 단계와 MellowShared 레시피 확장으로만 넣는다. 파이프라인 단계 이름 순서: Task 1~3은 `skin, shapeWarp, localEdit, geometry, color, detail, look` 그대로, Task 4에서 `skin, feature, shapeWarp, localEdit, geometry, color, detail, look`, Task 5부터 `skin, feature, background, shapeWarp, localEdit, geometry, color, detail, look`(F가 `feature`와 `background` 사이에 `makeup`을 넣는다).
- 레시피 `schemaVersion`은 2 유지, D는 레시피 키를 바꾸지 않는다(`portrait.features`·`background.blur`는 B에서 이미 있다). v1 세션은 계속 읽힌다. 번들 ID `com.mj.mellowphoto`는 그대로.
- 값 범위: `features.*`·`background.blur` 0…1(`AdjustmentRange.unit` = `EditingPolicy.unitRange`). 렌더 단계도 이 범위로 직접 자른다(프리셋·일괄 값은 편집 규칙을 거치지 않는다).
- 좌표는 정규화·원점 왼쪽 아래. 인물 마스크는 `PersonAnalyzer`가 돌려준 크기 그대로(원점 (0, 0)) 보관하고 렌더할 때 extent로 가로·세로를 따로 키운다.
- `RenderTuning` 새 상수 시작값: Task 3 — featureMaskFeather 0.004, scleraLumaMin 0.45, scleraLumaRamp 0.15, scleraChromaMax 0.08, scleraChromaRamp 0.04, irisRadiusFraction 0.5, mouthOpenMinArea 0.004, teethLumaMin 0.35, teethLumaRamp 0.15, teethRednessMax 0.08, teethRednessRamp 0.04. Task 4 — eyeWhiteLift 0.2, eyeIrisSharpen 0.8, eyeIrisSharpenRadiusFraction 0.1, teethYellowRemoval 0.7, teethLift 0.12, lipSaturationMax 0.3, lipRednessMax 0.02. Task 5 — backgroundBlurMaxFraction 0.02, backgroundMaskFeather 0.006. Task 6 — autoEyeBrighten 0.2.
- 한 줄 한 문장, 세미콜론 금지(CIKL 소스 문자열 안은 예외), 매직 넘버는 명명 상수(`RenderTuning`·`Theme`·`AppModel.Policy`·`EditingPolicy`, 기하 비율·판정 문턱은 기존 `FallbackFeature`처럼 타입 안 `private static let`).
- 한국어 사용자 문구는 앱 타깃(`UserMessage`·뷰)에만. 모듈은 `MellowError`만 던진다. 새 case `MellowError.personAnalysisUnavailable(reason: String)`(Task 2)의 문구는 같은 Task에서 `UserMessage.text(for:)`에 더한다.
- `cd apple && swift format lint --strict --recursive Sources Tests MellowPhoto MellowPhotoTests` 출력 없음(긴 줄은 줄바꿈으로 고친다, 한도 120자). 허용된 빌드 경고: 기존 `CIWarpKernel` 지원 중단(`WarpKernel`), 기존 `CIColorKernel(source:)` 지원 중단(`SkinKernels`, `DisplacementWarp`), 기존 `CIKernel(source:)` 지원 중단(`DisplacementWarp`), 새 `CIColorKernel(source:)` 지원 중단(`FeatureKernels`), 시뮬레이터 `usesCPUOnly`(`VisionFaceAnalyzer`).
- `./scripts/verify-modules.sh` 통과. 전체 검증은 `./scripts/test-apple.sh`.
- 패키지 테스트: `cd apple && swift test`. Mac 앱 테스트: `xcodebuild -project apple/MellowPhoto.xcodeproj -scheme MellowPhoto -derivedDataPath apple/build -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO test 2>&1 | grep -E "Executed|TEST (SUCCEEDED|FAILED)|error:"`. 앱 파일을 더하는 Task는 Task 8(`BackgroundPanel.swift`) 하나이며 그 Task만 `cd apple && xcodegen generate`를 돌리고 `apple/MellowPhoto.xcodeproj`를 함께 커밋한다.
- iOS 시뮬레이터 테스트는 Task 9의 `MELLOW_IOS_TESTS=1 ./scripts/test-apple.sh` 한 번에서만 돌린다(로컬 `test-apple.sh`는 이 변수가 없으면 iOS 시뮬레이터를 건너뛴다). 직접 부팅하지 않은 시뮬레이터를 끄지 않는다(`xcrun simctl shutdown`·`erase` 금지, 다른 프로젝트가 같은 기기를 쓰고 있을 수 있다). Xcode를 열거나 앱을 직접 띄우거나 조작하지 않는다.
- 커밋: 한국어 Conventional Commits, 마지막 줄 `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`. `git add`는 Task에 나열한 경로만.
- 각 Task 끝에 패키지 테스트(앱을 건드렸으면 Mac 앱 테스트도)와 lint가 통과해야 다음으로 간다. 기준 테스트 수(시작 시점): 패키지 220(Shared 37 · Rendering 128 · Library 30 · Export 4 · Editing 21), 앱 iPhone 52 · iPad 52 · Mac 53.

## Review Focus

스펙이 암시하지만 스펙의 테스트 목록이 직접 다루지 않는 입력. 각 줄의 테스트를 소유 Task에 넣었다.

1. **인물 분석이 실패했거나(시뮬레이터·구형 기기) 준비 전인 사진에 배경 흐림 값이 있다(프리셋·일괄 적용으로도 들어온다).** 미리보기·저장 모두 오류 없이 흐림만 빠져야 하고 앱은 오류 창을 띄우지 않아야 한다. → Task 5 `testPersonAnalysisFailureSkipsOnlyBackgroundBlur`, Task 8 `testBackgroundToolReportsNoPersonAndAnalysisFailureWithoutBlockingRender`.
2. **인물 마스크는 미리보기에서 512×384 고정 크기로 나와 사진 비율과 다르고, 저장은 원본 해상도다.** 사람 영역이 어긋나 얼굴이 흐려지면 안 된다. → Task 5 `testMaskStretchesSeparatelyAlongEachAxis`, `testOriginalRenderScalesPreviewMaskToOutputSize`.
3. **배경 흐림이 사진 가장자리에 닿는다.** 가장자리가 어둡거나 투명한 띠가 생기면 안 된다. → Task 5 `testBlurKeepsOpaqueUntintedEdges`.
4. **손으로 고친 프리셋 파일·일괄 적용으로 범위 밖 값(teethWhiten 9, blur 4, lipVitality −0.5)이 들어온다.** 렌더는 1·0과 같아야 한다. → Task 4 `testOutOfRangeFeatureValuesRenderLikeClampedValues`, Task 5 `testOutOfRangeBlurRendersLikeClampedValue`.
5. **특징점이 일부 빠진 얼굴(상자만, 동공 없음, 안쪽 입술 없음).** 빠진 부위만 건너뛰고 나머지는 동작하며 오류가 없어야 한다. → Task 3 `testFaceWithoutLandmarksHasNoFeatureMasks`, `testIrisCirclesUsePupilOrFallBackToEyeCenter`, Task 4 `testMissingLandmarksSkipOnlyTheirFeature`.

## 인터페이스 요약 (모든 Task가 공유하는 이름)

```swift
// MellowShared (Task 2)
MellowError.personAnalysisUnavailable(reason: String)

// MellowRendering 공개 API
public struct PhotoAnalysis: Sendable {                                    // Task 1 (person 필드는 Task 2)
    var faces: [FaceGeometry]; var faceAnalysisFailure: MellowError?; var blemishes: [BlemishSpot]
    var personMask: CIImage?; var personAnalysisFailure: MellowError?      // Task 2
    let regionMasks: RegionMaskCache                                       // internal
    init(faces:faceAnalysisFailure:blemishes:personMask:personAnalysisFailure:)   // 모두 기본값
}
RenderContext.init(extent:recipe:analysis:tuning:lookCatalog:skipsCrop:)   // Task 1, 기존 init(extent:recipe:faces:tuning:lookCatalog:skipsCrop:blemishes:)는 이것을 부름
RenderContext.analysis, .faces, .blemishes (계산 속성), .regionMasks (internal), .personMask (Task 2)
public protocol PersonAnalyzer: Sendable { func personMask(_ image: CIImage) throws -> CIImage? }   // Task 2
public struct VisionPersonAnalyzer: PersonAnalyzer                        // Task 2, Infrastructure
PhotoPipeline.init(analyzer:personAnalyzer:tuning:lookCatalog:)           // Task 2, personAnalyzer: (any PersonAnalyzer)? = nil
PreparedPhoto.hasPerson: Bool, .personAnalysisFailure: MellowError?       // Task 2
PhotoPipeline.preparedAnalysis(_:) -> PhotoAnalysis?                      // Task 1, internal 테스트용

// MellowRendering internal
final class RegionMaskCache { static maximumEntries; count; mask(for:make:); removeAll() }   // Task 1
struct RegionMaskKey: Hashable { init(fill:cut:cutWidth:extent:maxDimension:) }               // Task 1
FaceRegions.polygonMask(fill:cut:cutWidth:extent:tuning:cache:)            // Task 1, cache 기본 nil
FaceRegions.skinMask(face:image:extent:tuning:strength:cache:)             // Task 1, cache 기본 nil
FaceRegions.landmarkPolygon(_:_:_:)                                        // Task 3, private → internal
FaceRegions.RegionMask { image: CIImage; bounds: CGRect }                  // Task 3
FaceRegions.IrisCircle { center: CGPoint; radius: CGFloat }                // Task 3
FaceRegions.eyePolygons(face:extent:), irisCircles(face:extent:tuning:), area(of:), innerMouthAreaFraction(face:extent:)   // Task 3
FaceRegions.eyeMask / irisMask / lipMask(face:extent:tuning:cache:) -> RegionMask?        // Task 3
FaceRegions.teethMask(face:image:extent:tuning:cache:) throws -> RegionMask?               // Task 3
struct ToneRule { lumaMin, lumaRamp, limit, limitRamp, rednessOnly; static sclera(_:), teeth(_:) }   // Task 3
struct ToneShift { lift = 0, yellowRemoval = 0, saturation = 1, redness = 0 }              // Task 4
final class FeatureKernels { static shared; weight(of:rule:extent:) (Task 3); shifted(_:by:extent:) (Task 4) }
struct FeatureStage: RenderStage { name "feature"; static clamped(_:) }                    // Task 4
struct BackgroundStage: RenderStage { name "background"; static backgroundMask(_:extent:feather:) }   // Task 5

// MellowEditing (Task 6)
EditChange.feature(FeatureKey, Double), EditChange.backgroundBlur(Double)    // affectsGeometry false

// 테스트 지원 (apple/Tests/MellowRenderingTests)
RenderingTestSupport.personMask(size:person:)                               // Task 2
StubPersonAnalyzer (PhotoPipelineTests.swift)                               // Task 2
SyntheticFace.makeFeatures(mouthOpen:), innerLips(radii:), scleraPoint, lipPoint, lidSkin, philtrum   // Task 3

// 앱
BeautyTab.features, UserMessage.beautyTabFeatures, featureTitle(_:), featureHint            // Task 7
EditorTool.background, BackgroundPanel, AppModel.BackgroundAvailability, AppModel.backgroundAvailability   // Task 8
AppModel.PhotoInfo.hasPerson, .personAnalysisFailure                                        // Task 8
StubPersonAnalyzer, TestSupport.personMask(_:), TestSupport.makeModel(…, personAnalyzer:, …) (apple/MellowPhotoTests/TestSupport.swift)   // Task 8
```

---

### Task 1: 분석 묶음과 영역 마스크 캐시 — PhotoAnalysis, RegionMaskCache

**Files:**
- Create: `apple/Sources/MellowRendering/API/PhotoAnalysis.swift`
- Create: `apple/Sources/MellowRendering/Domain/RegionMaskCache.swift`
- Modify: `apple/Sources/MellowRendering/API/RenderStage.swift` (`RenderContext` 전체 교체)
- Modify: `apple/Sources/MellowRendering/API/PhotoPipeline.swift` (`PhotoPipeline` 액터 부분 교체, `PreparedPhoto`는 그대로)
- Modify: `apple/Sources/MellowRendering/Domain/FaceRegions.swift` (`polygonMask`·`skinMask`에 `cache` 인자)
- Modify: `apple/Sources/MellowRendering/Domain/SkinStage.swift` (`skinMask` 호출에 캐시 전달)
- Test: `apple/Tests/MellowRenderingTests/FaceRegionsTests.swift`, `SkinStageTests.swift`, `RenderPipelineTests.swift`, `PhotoPipelineTests.swift`

**Interfaces:**
- Consumes: `FaceGeometry`, `BlemishSpot`, `MellowError`, 기존 `FaceRegions.polygonMask` 본문, `PreviewCache.ids`.
- Produces: `public struct PhotoAnalysis`(`faces`, `faceAnalysisFailure`, `blemishes`, internal `regionMasks`, `init(faces:faceAnalysisFailure:blemishes:)` 모두 기본값). `RenderContext.init(extent:recipe:analysis:tuning:lookCatalog:skipsCrop:)`, 기존 `init(extent:recipe:faces:tuning:lookCatalog:skipsCrop:blemishes:)`(새 init을 부름), `RenderContext.analysis`, 계산 속성 `faces`·`blemishes`, internal `regionMasks`. `final class RegionMaskCache`(`static let maximumEntries = 32`, `count`, `mask(for:make:)`, `removeAll()`), `struct RegionMaskKey: Hashable`(`init(fill:cut:cutWidth:extent:maxDimension:)`). `FaceRegions.polygonMask(…, cache: RegionMaskCache? = nil)`, `FaceRegions.skinMask(…, strength:, cache: RegionMaskCache? = nil)`. `PhotoPipeline.preparedAnalysis(_:) -> PhotoAnalysis?`(internal).

설계 근거:
- **묶음(B 이월 a).** 얼굴·잡티(지금)와 인물 마스크(Task 2)·관절점(E)을 `PhotoAnalysis` 하나로 들고 다닌다. 단계 테스트 수십 곳이 쓰는 `RenderContext(extent:recipe:faces:tuning:…blemishes:)`는 그대로 두고 새 init을 부르게 한다. 이 옛 init의 인자 목록에는 앞으로 아무것도 더하지 않는다. `context.faces`·`context.blemishes`는 계산 속성이 되어 호출부가 바뀌지 않는다.
- **마스크 캐시(B 이월 b).** `FaceRegions.polygonMask`는 렌더마다 CGContext 비트맵(긴 변 최대 512px)을 다시 그린다. 키는 다각형 점·넓힘 폭·extent·비트맵 크기라서 얼굴이나 해상도(미리보기·원본)가 바뀌면 저절로 다른 항목이 되고 무효화가 필요 없다. 캐시는 `PhotoAnalysis` 안 참조 타입이라 `Entry`에 든 묶음을 복사해도 같은 캐시를 쓴다. 항목이 32개를 넘으면 모두 비운다. 미리보기 LRU에서 밀려난 사진과 원본 렌더를 마친 사진(미리보기가 캐시에 없을 때)의 캐시는 비운다. 비워도 이미 만든 렌더 그래프는 비트맵을 붙잡고 있어 안전하다. `BlemishDetector`는 캐시 없이 그대로 부른다.

- [ ] **Step 1: 실패하는 테스트 작성**

`FaceRegionsTests.swift` 맨 아래(`testDemoPortraitMaskCoversCheekAndNotPupil` 뒤)에 추가:

```swift
    func testPolygonMaskCacheReusesRasterAndMatchesUncached() throws {
        let synthetic = SyntheticFace.make()
        let extent = synthetic.image.extent
        let tuning = RenderTuning()
        let fill = [FaceRegions.skinPolygon(face: synthetic.face, extent: extent, tuning: tuning)]
        let cut = FaceRegions.protectedPolygons(face: synthetic.face, extent: extent)
        let cache = RegionMaskCache()
        let first = FaceRegions.polygonMask(
            fill: fill, cut: cut, cutWidth: 28, extent: extent, tuning: tuning, cache: cache)
        let second = FaceRegions.polygonMask(
            fill: fill, cut: cut, cutWidth: 28, extent: extent, tuning: tuning, cache: cache)
        XCTAssertEqual(cache.count, 1, "같은 다각형·extent는 한 번만 그린다")
        XCTAssertTrue(first === second, "저장한 이미지를 그대로 돌려준다")
        let uncached = FaceRegions.polygonMask(fill: fill, cut: cut, cutWidth: 28, extent: extent, tuning: tuning)
        XCTAssertEqual(try Support.bytes(first), try Support.bytes(uncached))
        _ = FaceRegions.polygonMask(fill: fill, cut: cut, cutWidth: 14, extent: extent, tuning: tuning, cache: cache)
        XCTAssertEqual(cache.count, 2, "넓힘 폭이 다르면 다른 항목")
    }

    func testRegionMaskCacheEmptiesWhenFull() {
        let cache = RegionMaskCache()
        let extent = CGRect(x: 0, y: 0, width: 8, height: 8)
        for index in 0...RegionMaskCache.maximumEntries {
            let polygon = [CGPoint(x: 0, y: 0), CGPoint(x: CGFloat(index + 1), y: 0), CGPoint(x: 0, y: 4)]
            let key = RegionMaskKey(fill: [polygon], cut: [], cutWidth: 0, extent: extent, maxDimension: 512)
            _ = cache.mask(for: key) { CIImage(color: .white).cropped(to: extent) }
        }
        XCTAssertEqual(cache.count, 1, "상한을 넘으면 모두 비우고 새 항목 하나만 남는다")
    }
```

`SkinStageTests.swift` 맨 아래에 추가:

```swift
    func testSkinRenderReusesCachedMaskAcrossRenders() throws {
        let synthetic = SyntheticFace.make()
        var recipe = EditRecipe()
        recipe.portrait.skin.smoothing = 0.6
        let analysis = PhotoAnalysis(faces: [synthetic.face])
        let context = RenderContext(
            extent: synthetic.image.extent, recipe: recipe, analysis: analysis, tuning: RenderTuning())
        let first = try Support.bytes(SkinStage().apply(synthetic.image, in: context))
        let second = try Support.bytes(SkinStage().apply(synthetic.image, in: context))
        XCTAssertEqual(analysis.regionMasks.count, 1, "얼굴 하나의 피부 다각형은 한 번만 그린다")
        XCTAssertEqual(first, second)
        let fresh = RenderContext(
            extent: synthetic.image.extent, recipe: recipe, faces: [synthetic.face], tuning: RenderTuning())
        XCTAssertEqual(first, try Support.bytes(SkinStage().apply(synthetic.image, in: fresh)), "캐시 여부와 결과가 같다")
    }
```

`RenderPipelineTests.swift`의 `testEmptyExtentIsRejected` 뒤에 추가:

```swift
    func testAnalysisInitMatchesFaceInit() {
        let left = FaceGeometry(boundingBox: NormalizedRect(x: 0.1, y: 0.1, width: 0.3, height: 0.3))
        let right = FaceGeometry(boundingBox: NormalizedRect(x: 0.6, y: 0.1, width: 0.3, height: 0.3))
        let spots = [
            BlemishSpot(x: 0.2, y: 0.2, radius: 0.01, faceIndex: 0),
            BlemishSpot(x: 0.7, y: 0.2, radius: 0.01, faceIndex: 1),
        ]
        var recipe = EditRecipe()
        recipe.portrait.targetFace = 1
        let extent = CGRect(x: 0, y: 0, width: 64, height: 64)
        let legacy = RenderContext(
            extent: extent, recipe: recipe, faces: [left, right], tuning: RenderTuning(), blemishes: spots)
        let bundled = RenderContext(
            extent: extent, recipe: recipe, analysis: PhotoAnalysis(faces: [left, right], blemishes: spots),
            tuning: RenderTuning())
        XCTAssertEqual(legacy.faces, bundled.faces)
        XCTAssertEqual(legacy.blemishes, bundled.blemishes)
        XCTAssertEqual(legacy.targetFaces, [right])
        XCTAssertEqual(bundled.targetFaces, [right])
        XCTAssertEqual(bundled.targetBlemishes, [spots[1]])
    }
```

`PhotoPipelineTests.swift`의 `testLookThumbnailsRequirePreparedPhoto` 뒤에 추가:

```swift
    func testEvictedPreviewReleasesRegionMasks() async throws {
        let synthetic = SyntheticFace.make()
        let url = try Support.writePNG(synthetic.image, name: "face")
        var tuning = RenderTuning()
        tuning.previewCacheCapacity = 1
        let pipeline = PhotoPipeline(analyzer: StubFaceAnalyzer(result: .success([synthetic.face])), tuning: tuning)
        let first = PhotoID()
        _ = try await pipeline.prepare(first, at: url)
        var recipe = EditRecipe()
        recipe.portrait.skin.smoothing = 0.5
        _ = try await pipeline.preview(first, recipe: recipe)
        let prepared = await pipeline.preparedAnalysis(first)
        let analysis = try XCTUnwrap(prepared)
        XCTAssertEqual(analysis.regionMasks.count, 1)
        _ = try await pipeline.prepare(PhotoID(), at: try writeSolidPNG())
        XCTAssertEqual(analysis.regionMasks.count, 0, "미리보기가 캐시에서 밀려나면 마스크 비트맵도 놓는다")
    }
```

- [ ] **Step 2: 실패 확인**

Run: `cd apple && swift test --filter 'FaceRegionsTests|SkinStageTests|RenderPipelineTests|PhotoPipelineTests'` → 컴파일 실패(`cannot find 'RegionMaskCache' in scope`, `cannot find 'PhotoAnalysis' in scope`).

- [ ] **Step 3: 구현**

`apple/Sources/MellowRendering/API/PhotoAnalysis.swift`:

```swift
import CoreImage
import MellowShared

/// 사진 준비 때 한 번 계산한 분석 결과 묶음. 렌더 단계는 RenderContext.analysis로 읽는다.
/// 새 분석 결과(E 관절점 등)는 여기 필드로만 더하고 RenderContext·PhotoPipeline의 인자 목록은 늘리지 않는다.
public struct PhotoAnalysis: Sendable {
    /// 왼쪽부터 정렬된 얼굴.
    public var faces: [FaceGeometry]
    /// 얼굴 분석이 실패했으면 그 이유. 얼굴이 없는 것과 구분한다.
    public var faceAnalysisFailure: MellowError?
    /// 자동 잡티. 얼굴이 있을 때만 찾는다. 영속화하지 않는다.
    public var blemishes: [BlemishSpot]
    /// 다각형 마스크 비트맵 캐시. 묶음을 복사해도 같은 캐시를 나눠 쓴다. 키에 다각형 점이 들어 있어 얼굴이 바뀌어도 낡은 값을 쓰지 않는다.
    let regionMasks = RegionMaskCache()

    public init(faces: [FaceGeometry] = [], faceAnalysisFailure: MellowError? = nil, blemishes: [BlemishSpot] = []) {
        self.faces = faces
        self.faceAnalysisFailure = faceAnalysisFailure
        self.blemishes = blemishes
    }
}
```

`apple/Sources/MellowRendering/Domain/RegionMaskCache.swift`:

```swift
import CoreImage
import Foundation

/// 다각형 마스크 비트맵 캐시. 같은 사진을 다시 렌더할 때 CGContext 래스터를 다시 그리지 않는다.
/// RenderContext가 Sendable이라 잠금으로 보호한다. 같은 키를 동시에 처음 물으면 둘 다 그릴 수 있지만 결과는 같다.
final class RegionMaskCache: @unchecked Sendable {
    /// 항목 수 상한. 얼굴 몇 개 × 영역 4종(피부·눈·입술·치아) × 해상도 2가지(미리보기·원본)를 담는다. 넘으면 모두 비운다.
    static let maximumEntries = 32

    private let lock = NSLock()
    private var masks: [RegionMaskKey: CIImage] = [:]

    var count: Int { lock.withLock { masks.count } }

    func mask(for key: RegionMaskKey, make: () -> CIImage) -> CIImage {
        if let cached = lock.withLock({ masks[key] }) {
            return cached
        }
        let made = make()
        lock.withLock {
            if masks.count >= Self.maximumEntries {
                masks.removeAll()
            }
            masks[key] = made
        }
        return made
    }

    func removeAll() {
        lock.withLock { masks.removeAll() }
    }
}

/// polygonMask 입력 전체. 다각형 점·넓힘 폭·extent·비트맵 크기가 같으면 같은 비트맵이다.
struct RegionMaskKey: Hashable {
    private let values: [Double]

    init(fill: [[CGPoint]], cut: [[CGPoint]], cutWidth: CGFloat, extent: CGRect, maxDimension: Int) {
        var values = [
            Double(extent.minX), Double(extent.minY), Double(extent.width), Double(extent.height), Double(cutWidth),
            Double(maxDimension), Double(fill.count),
        ]
        for polygon in fill + cut {
            values.append(Double(polygon.count))
            for point in polygon {
                values.append(Double(point.x))
                values.append(Double(point.y))
            }
        }
        self.values = values
    }
}
```

`apple/Sources/MellowRendering/API/RenderStage.swift`의 `public struct RenderContext` 전체를 다음으로 바꾼다(`RenderStage` 프로토콜은 그대로):

```swift
public struct RenderContext: Sendable {
    public let extent: CGRect
    public let recipe: EditRecipe
    /// 사진 준비 때 계산한 분석 결과. 단계는 faces·blemishes 같은 접근자로 읽는다.
    public let analysis: PhotoAnalysis
    /// recipe.portrait.targetFace를 적용한 결과. 범위 밖 인덱스면 비어 있다.
    public let targetFaces: [FaceGeometry]
    public let tuning: RenderTuning
    public let lookCatalog: LookCatalog
    /// 자르기 도구 화면용. 기하 단계가 자르기만 건너뛴다.
    public let skipsCrop: Bool
    /// recipe.portrait.targetFace를 적용한 잡티.
    public let targetBlemishes: [BlemishSpot]

    public init(
        extent: CGRect, recipe: EditRecipe, analysis: PhotoAnalysis, tuning: RenderTuning,
        lookCatalog: LookCatalog = .empty, skipsCrop: Bool = false
    ) {
        self.extent = extent
        self.recipe = recipe
        self.analysis = analysis
        self.tuning = tuning
        self.lookCatalog = lookCatalog
        self.skipsCrop = skipsCrop
        let faces = analysis.faces
        let blemishes = analysis.blemishes
        if let index = recipe.portrait.targetFace {
            targetFaces = faces.indices.contains(index) ? [faces[index]] : []
            targetBlemishes = blemishes.filter { $0.faceIndex == index }
        } else {
            targetFaces = faces
            targetBlemishes = blemishes
        }
    }

    /// 얼굴·잡티만 있는 분석으로 만든다. 단계 테스트가 쓰는 형태다.
    /// 새 분석 결과는 이 인자 목록에 더하지 않고 PhotoAnalysis에만 더한다.
    public init(
        extent: CGRect, recipe: EditRecipe, faces: [FaceGeometry], tuning: RenderTuning,
        lookCatalog: LookCatalog = .empty, skipsCrop: Bool = false, blemishes: [BlemishSpot] = []
    ) {
        self.init(
            extent: extent, recipe: recipe, analysis: PhotoAnalysis(faces: faces, blemishes: blemishes),
            tuning: tuning, lookCatalog: lookCatalog, skipsCrop: skipsCrop)
    }

    /// 왼쪽부터 정렬된 얼굴.
    public var faces: [FaceGeometry] { analysis.faces }
    /// 사진 준비 때 찾은 자동 잡티. 영속화하지 않는다.
    public var blemishes: [BlemishSpot] { analysis.blemishes }
    /// 같은 사진의 다각형 마스크 비트맵 캐시.
    var regionMasks: RegionMaskCache { analysis.regionMasks }

    /// 정규화 사각형을 픽셀 좌표로.
    public func pixelRect(_ rect: NormalizedRect) -> CGRect {
        CGRect(
            x: extent.minX + rect.x * extent.width,
            y: extent.minY + rect.y * extent.height,
            width: rect.width * extent.width,
            height: rect.height * extent.height)
    }

    public func pixelPoint(x: Double, y: Double) -> CGPoint {
        CGPoint(x: extent.minX + x * extent.width, y: extent.minY + y * extent.height)
    }

    public var shortSide: CGFloat { min(extent.width, extent.height) }
}
```

`FaceRegions.swift`:
1. `polygonMask`의 선언과 본문을 다음 두 함수로 바꾼다. `rasterize`의 본문은 기존 `polygonMask` 본문(현재 167~204행, `let black = CIImage(color: .black).cropped(to: extent)`부터 마지막 `.composited(over: black).cropped(to: extent)`까지)을 한 글자도 바꾸지 않고 옮긴 것이다.

```swift
    /// fill 다각형을 1, cut 다각형(경계를 cutWidth/2만큼 넓혀)을 0으로 그린 extent 크기 회색 마스크.
    /// 얼굴 영역만 긴 변 regionMaskMaxDimension 비트맵에 그리고 확대한다. cache가 있으면 같은 입력의 비트맵을 다시 그리지 않는다.
    static func polygonMask(
        fill: [[CGPoint]], cut: [[CGPoint]], cutWidth: CGFloat, extent: CGRect, tuning: RenderTuning,
        cache: RegionMaskCache? = nil
    ) -> CIImage {
        guard let cache else {
            return rasterize(fill: fill, cut: cut, cutWidth: cutWidth, extent: extent, tuning: tuning)
        }
        let key = RegionMaskKey(
            fill: fill, cut: cut, cutWidth: cutWidth, extent: extent, maxDimension: tuning.regionMaskMaxDimension)
        return cache.mask(for: key) {
            rasterize(fill: fill, cut: cut, cutWidth: cutWidth, extent: extent, tuning: tuning)
        }
    }

    /// polygonMask의 CGContext 래스터.
    private static func rasterize(
        fill: [[CGPoint]], cut: [[CGPoint]], cutWidth: CGFloat, extent: CGRect, tuning: RenderTuning
    ) -> CIImage {
        // 기존 polygonMask 본문 그대로
    }
```

(위 `// 기존 polygonMask 본문 그대로` 줄은 옮겨 온 본문으로 바꾸고 주석은 남기지 않는다.)

2. `skinMask` 선언에 마지막 인자 `cache: RegionMaskCache? = nil`을 더하고 본문의 `polygonMask(` 호출 끝에 `cache: cache`를 넘긴다:

```swift
    static func skinMask(
        face: FaceGeometry, image: CIImage, extent: CGRect, tuning: RenderTuning, strength: Double = 1,
        cache: RegionMaskCache? = nil
    ) throws -> CIImage {
        let black = CIImage(color: .black).cropped(to: extent)
        let bounds = maskBounds(face: face, extent: extent, tuning: tuning)
        guard !bounds.isEmpty else { return black }
        let cutWidth = faceWidth(face, extent: extent) * CGFloat(tuning.skinFeatureFeather) * 2
        var mask = polygonMask(
            fill: [skinPolygon(face: face, extent: extent, tuning: tuning)],
            cut: protectedPolygons(face: face, extent: extent), cutWidth: cutWidth, extent: extent, tuning: tuning,
            cache: cache)
```

(그 아래 본문은 그대로.)

`SkinStage.swift`의 `FaceRegions.skinMask(` 호출을 다음으로 바꾼다:

```swift
            let mask = try FaceRegions.skinMask(
                face: face, image: result, extent: extent, tuning: tuning, strength: tuning.skinMaskMaxStrength,
                cache: context.regionMasks)
```

`PhotoPipeline.swift`의 `public actor PhotoPipeline { … }` 전체를 다음으로 바꾼다(`PreparedPhoto`는 그대로):

```swift
/// 무거운 이미지 작업을 메인 액터 밖에서 직렬로 수행한다. 미리보기는 캐시에서 렌더한다.
public actor PhotoPipeline {
    /// 준비 전 사진에 얼굴 보정을 저장하려 할 때의 사유 식별자. 사용자 문구는 앱이 정한다.
    public static let unpreparedReason = "photo-not-prepared"

    private struct Entry {
        /// 준비 때 계산한 분석 결과. 다각형 마스크 캐시도 함께 들고 있다.
        var analysis: PhotoAnalysis
        /// 렌더해 둔 작은 비트맵에서 만든다. 미리보기 CIImage를 참조하지 않아 LRU로 밀려난 미리보기를 붙잡지 않는다.
        var thumbnail: CIImage
    }

    private let loader = ImageLoader()
    private let renderer = Renderer()
    private let pipeline = RenderPipeline.standard
    private let analyzer: any FaceAnalyzer
    private let tuning: RenderTuning
    private let lookCatalog: LookCatalog
    /// 미리보기 이미지가 LRU로 밀려나도 일부러 남긴다. renderOriginal이 얼굴 좌표를 써야 한다.
    private var entries: [PhotoID: Entry] = [:]
    private var cache: PreviewCache

    public init(analyzer: any FaceAnalyzer, tuning: RenderTuning, lookCatalog: LookCatalog = .empty) {
        self.analyzer = analyzer
        self.tuning = tuning
        self.lookCatalog = lookCatalog
        cache = PreviewCache(capacity: tuning.previewCacheCapacity)
    }

    /// 테스트용. 캐시에 든 사진 ID.
    var cachedPreviewIDs: [PhotoID] { cache.ids }

    /// 테스트용. 준비 때 찾은 잡티.
    func preparedBlemishes(_ id: PhotoID) -> [BlemishSpot] {
        entries[id]?.analysis.blemishes ?? []
    }

    /// 테스트용. 준비 때 계산한 분석 묶음.
    func preparedAnalysis(_ id: PhotoID) -> PhotoAnalysis? {
        entries[id]?.analysis
    }

    public func prepare(_ id: PhotoID, at url: URL) throws -> PreparedPhoto {
        let metadata = try loader.metadata(url: url)
        let preview = try loader.load(url: url, maxDimension: tuning.previewMaxDimension)
        var faces: [FaceGeometry] = []
        var failure: MellowError?
        do {
            faces = try analyzer.analyze(preview)
        } catch let error as MellowError {
            failure = error
        } catch {
            failure = .faceAnalysisUnavailable(reason: error.localizedDescription)
        }
        let analysis = PhotoAnalysis(
            faces: faces, faceAnalysisFailure: failure, blemishes: detectBlemishes(in: preview, faces: faces))
        let thumbnail = try renderer.makeCGImage(Self.scaled(preview, maxDimension: tuning.thumbnailMaxDimension))
        entries[id] = Entry(analysis: analysis, thumbnail: CIImage(cgImage: thumbnail))
        cache.insert(preview, for: id)
        releaseMasksOfEvictedPreviews()
        return PreparedPhoto(
            pixelSize: metadata.pixelSize, thumbnail: thumbnail, faces: faces, faceAnalysisFailure: failure)
    }

    /// 캐시가 비었으면 cannotCreatePreview. 호출자가 prepare를 다시 한다.
    /// `showsUncropped`이면 자르기만 건너뛴다. 자르기 도구 화면이 전체 이미지 위에 자르기 틀을 그린다.
    public func preview(_ id: PhotoID, recipe: EditRecipe, showsUncropped: Bool = false) throws -> CGImage {
        guard let entry = entries[id], let image = cache.image(for: id) else {
            throw MellowError.cannotCreatePreview
        }
        let context = RenderContext(
            extent: image.extent, recipe: recipe, analysis: entry.analysis, tuning: tuning, lookCatalog: lookCatalog,
            skipsCrop: showsUncropped)
        return try renderer.makeCGImage(pipeline.render(image, context: context))
    }

    /// 카탈로그의 모든 룩을 강도 1로 입힌 썸네일. 룩 단계만 적용한다(전체 파이프라인이 아님).
    public func lookThumbnails(_ id: PhotoID) throws -> [String: CGImage] {
        guard let entry = entries[id] else { throw MellowError.cannotCreatePreview }
        var result: [String: CGImage] = [:]
        for look in lookCatalog.all {
            let styled = LookStage.styled(entry.thumbnail, look: look, tuning: tuning)
            result[look.id] = try renderer.makeCGImage(styled.cropped(to: entry.thumbnail.extent))
        }
        return result
    }

    /// 원본 분석 기준의 제안. 현재 레시피와 무관하다.
    public func autoEnhanceSuggestion(_ id: PhotoID, hasFaces: Bool) throws -> AutoEnhanceSuggestion {
        guard let image = cache.image(for: id) else { throw MellowError.cannotCreatePreview }
        return try AutoEnhancer(tuning: tuning, renderer: renderer).suggestion(for: image, hasFaces: hasFaces)
    }

    public func reprepareIfEvicted(_ id: PhotoID, at url: URL) throws {
        guard cache.image(for: id) == nil else { return }
        _ = try prepare(id, at: url)
    }

    /// 준비 때 얻은 정규화 얼굴 좌표를 원본 해상도에 그대로 쓴다. 얼굴을 다시 분석하지 않는다.
    public func renderOriginal(_ id: PhotoID, at url: URL, recipe: EditRecipe, maxDimension: Int?) throws -> CIImage {
        guard let entry = entries[id] else {
            // 얼굴 정보 없이 얼굴 보정을 저장하면 조용히 빠진다. 색감만이면 그대로 렌더한다.
            if recipe.dependsOnFaces {
                throw MellowError.faceAnalysisUnavailable(reason: Self.unpreparedReason)
            }
            return try render(url: url, recipe: recipe, analysis: PhotoAnalysis(), maxDimension: maxDimension)
        }
        if recipe.dependsOnFaces, entry.analysis.faces.isEmpty, let failure = entry.analysis.faceAnalysisFailure {
            throw failure
        }
        let rendered = try render(url: url, recipe: recipe, analysis: entry.analysis, maxDimension: maxDimension)
        // 원본 해상도 마스크는 다시 쓸 일이 드물다. 이미 만든 렌더 그래프는 비트맵을 붙잡고 있어 비워도 안전하다.
        releaseMasksOfEvictedPreviews()
        return rendered
    }

    private func render(url: URL, recipe: EditRecipe, analysis: PhotoAnalysis, maxDimension: Int?) throws -> CIImage {
        let image = try loader.load(url: url, maxDimension: maxDimension)
        let context = RenderContext(
            extent: image.extent, recipe: recipe, analysis: analysis, tuning: tuning, lookCatalog: lookCatalog)
        return try pipeline.render(image, context: context)
    }

    /// 잡티 분석이 실패해도 사진 준비는 막지 않는다. 자동 잡티만 동작하지 않는다.
    private func detectBlemishes(in image: CIImage, faces: [FaceGeometry]) -> [BlemishSpot] {
        guard !faces.isEmpty else { return [] }
        return (try? BlemishDetector(tuning: tuning, renderer: renderer).detect(image: image, faces: faces)) ?? []
    }

    /// 미리보기 캐시에 없는 사진의 마스크 비트맵을 놓는다. 메모리를 최근 사진 몇 장 몫으로 묶는다.
    private func releaseMasksOfEvictedPreviews() {
        let cached = Set(cache.ids)
        for (id, entry) in entries where !cached.contains(id) {
            entry.analysis.regionMasks.removeAll()
        }
    }

    public func makeCGImage(_ image: CIImage) throws -> CGImage {
        try renderer.makeCGImage(image)
    }

    public func evict(_ id: PhotoID) {
        entries[id] = nil
        cache.remove(id)
    }

    private static func scaled(_ image: CIImage, maxDimension: Int) -> CIImage {
        let longest = max(image.extent.width, image.extent.height)
        guard longest > CGFloat(maxDimension) else { return image }
        let scale = CGFloat(maxDimension) / longest
        return image.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
    }
}
```

- [ ] **Step 4: 통과 확인**

Run: `cd apple && swift test` → `Executed 225 tests, with 0 failures`(Shared 37 · Rendering 133 · Library 30 · Export 4 · Editing 21). 기존 테스트는 고치지 않고 통과해야 한다. lint 출력 없음. `./scripts/verify-modules.sh` 통과. Mac 앱 테스트 → `Executed 53 tests, with 0 failures`(앱은 공개 시그니처만 쓴다).

- [ ] **Step 5: 커밋**

```bash
git add apple/Sources/MellowRendering apple/Tests/MellowRenderingTests
git commit -m "refactor(rendering): 사진 분석 결과를 PhotoAnalysis로 묶고 영역 마스크 비트맵 캐시 추가

얼굴·잡티를 PhotoAnalysis 하나로 RenderContext에 넘기고 옛 init은 그것을 부른다.
다각형 마스크 비트맵을 사진마다 한 번만 그리고 미리보기가 밀려나면 놓는다.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 2: 인물 분석 — PersonAnalyzer 포트, VisionPersonAnalyzer, 준비 단계 분석

**Files:**
- Modify: `apple/Sources/MellowShared/API/MellowError.swift` (`personAnalysisUnavailable`)
- Create: `apple/Sources/MellowRendering/API/PersonAnalyzer.swift`
- Create: `apple/Sources/MellowRendering/Infrastructure/VisionPersonAnalyzer.swift`
- Modify: `apple/Sources/MellowRendering/API/PhotoAnalysis.swift` (`personMask`·`personAnalysisFailure`)
- Modify: `apple/Sources/MellowRendering/API/RenderStage.swift` (`personMask` 접근자)
- Modify: `apple/Sources/MellowRendering/API/PhotoPipeline.swift` (`PreparedPhoto` 필드, `init`, `prepare`, 인물 분석, 잡티 시점 주석)
- Modify: `apple/MellowPhoto/Application/UserMessage.swift` (새 오류 문구)
- Modify: `apple/Tests/MellowRenderingTests/RenderingTestSupport.swift` (`personMask(size:person:)`)
- Test: `apple/Tests/MellowRenderingTests/VisionPersonAnalyzerTests.swift`, `apple/Tests/MellowRenderingTests/PhotoPipelineTests.swift`

**Interfaces:**
- Consumes: `PhotoAnalysis`·`RenderContext.init(…analysis:…)`·`PhotoPipeline.preparedAnalysis(_:)`(Task 1), `ImageLoader`, `VisionFaceAnalyzer`, `Renderer.readPixels`.
- Produces: `MellowError.personAnalysisUnavailable(reason: String)`. `public protocol PersonAnalyzer: Sendable { func personMask(_ image: CIImage) throws -> CIImage? }`. `public struct VisionPersonAnalyzer: PersonAnalyzer`(`init()`, `static let missingResultReason = "no-segmentation-result"`, internal `static func coverage(of: CVPixelBuffer) -> Double`). `PhotoAnalysis.personMask: CIImage?`, `PhotoAnalysis.personAnalysisFailure: MellowError?`, init 인자 `personMask:`·`personAnalysisFailure:`(기본 nil). `RenderContext.personMask: CIImage?`. `PhotoPipeline.init(analyzer:personAnalyzer:tuning:lookCatalog:)`(`personAnalyzer: (any PersonAnalyzer)? = nil`). `PreparedPhoto.hasPerson: Bool`, `PreparedPhoto.personAnalysisFailure: MellowError?`(init 인자 기본값 `false`·`nil`). 테스트 지원: `RenderingTestSupport.personMask(size:person:)`, `StubPersonAnalyzer`(PhotoPipelineTests.swift 위).

설계 근거:
- **Vision 요청.** `VNGeneratePersonSegmentationRequest`, `qualityLevel = .balanced`, `outputPixelFormat = kCVPixelFormatType_OneComponent8`. 측정(Mac, 데모 사진 1254²): 첫 호출 0.08초(모델 적재), 이후 약 0.01초. 결과는 입력 비율과 무관하게 512×384 고정이고 이미지 전체를 덮는다. `.accurate`는 2016×1512에 0.9초라 쓰지 않는다. 시뮬레이터용 `usesCPUOnly`는 넣지 않는다(지원 중단 경고가 늘고, 실패해도 안내만 뜬다).
- **사람 없음.** Vision은 사람이 없어도 0으로 찬 마스크를 준다. 바이트 128 이상 픽셀이 1% 미만이면 nil(측정: 빈 장면 0%, 데모 사진 57.6%). 판정 상수는 이 타입 안 `private static let`이다(앱이 튜닝 없이 조립하는 포트 구현이라 `RenderTuning`을 받지 않는다).
- **마스크 값.** `CIImage(cvPixelBuffer:options: [.colorSpace: NSNull()])`로 0…255를 색 관리 없이 0…1로 읽는다. 측정: 한 채널 버퍼가 회색(R = G = B)으로 펼쳐진다. 색공간을 붙이면 작업 색공간(선형)으로 바뀌어 경계 중간값이 달라진다. 요청 객체는 호출마다 새로 만들므로 버퍼가 재사용되지 않는다.
- **실패 처리(스펙 1.4).** 인물 분석 실패는 사진 준비를 막지 않고 `PreparedPhoto.personAnalysisFailure`로 남긴다. 얼굴 분석·잡티 검출과 서로 영향이 없다. `personAnalyzer`가 nil이면 분석하지 않는다(사람 없음과 같음, 단계 테스트와 기존 호출부용). 앱 조립은 Task 8에서 `VisionPersonAnalyzer()`를 넘긴다.
- **잡티 검출 시점(B 이월 f).** 자동 잡티가 꺼져 있어도 지금처럼 준비 때 찾는다. 사진당 약 0.06초이고, 스펙 1.4가 분석을 준비 때 한 번으로 정했으며, 스위치를 켤 때 첫 미리보기가 늦어지지 않는다. 코드는 바꾸지 않고 주석으로 남긴다.

- [ ] **Step 1: 테스트 지원 코드**

`RenderingTestSupport.swift`의 `enum RenderingTestSupport` 안, `hardEllipse` 아래에 추가:

```swift
    /// 검은 바탕에 흰 사각형 사람이 있는 인물 마스크. size는 마스크 크기, person은 마스크 안 사람 사각형(픽셀).
    static func personMask(size: CGSize, person: CGRect) -> CIImage {
        let extent = CGRect(origin: .zero, size: size)
        return CIImage(color: .white).cropped(to: person).composited(over: CIImage(color: .black)).cropped(to: extent)
    }
```

`PhotoPipelineTests.swift`의 `struct StubFaceAnalyzer` 아래에 추가:

```swift
struct StubPersonAnalyzer: PersonAnalyzer {
    var result: Result<CIImage?, MellowError>
    func personMask(_ image: CIImage) throws -> CIImage? { try result.get() }
}
```

- [ ] **Step 2: 실패하는 테스트 작성**

`apple/Tests/MellowRenderingTests/VisionPersonAnalyzerTests.swift`:

```swift
import CoreImage
import MellowShared
import XCTest

@testable import MellowRendering

final class VisionPersonAnalyzerTests: XCTestCase {
    typealias Support = RenderingTestSupport

    /// 마스크 픽셀 하나의 값(0…1).
    private func value(_ mask: CIImage, at point: CGPoint) throws -> Float {
        let pixel = CGRect(origin: point, size: CGSize(width: 1, height: 1))
        return try Support.renderer.readPixels(mask.cropped(to: pixel))[0]
    }

    func testDemoPortraitMaskCoversFaceAndNotTopCorner() throws {
        let url = try XCTUnwrap(
            Bundle.module.url(forResource: "demo-portrait", withExtension: "png", subdirectory: "Fixtures"))
        let image = try ImageLoader().load(url: url, maxDimension: 1200)
        let face = try XCTUnwrap(try VisionFaceAnalyzer().analyze(image).first)
        let mask = try XCTUnwrap(try VisionPersonAnalyzer().personMask(image), "인물 사진에는 마스크가 있다")
        XCTAssertEqual(mask.extent.origin, .zero)
        let faceCenter = CGPoint(
            x: (face.boundingBox.midX * mask.extent.width).rounded(.down),
            y: (face.boundingBox.midY * mask.extent.height).rounded(.down))
        XCTAssertGreaterThan(try value(mask, at: faceCenter), 0.8, "얼굴 가운데는 사람")
        XCTAssertLessThan(try value(mask, at: CGPoint(x: 0, y: mask.extent.height - 1)), 0.2, "왼쪽 위 구석은 배경")
    }

    func testBlankImageHasNoPerson() throws {
        let blank = Support.solid(CIColor(red: 0.5, green: 0.6, blue: 0.7), size: 512)
        XCTAssertNil(try VisionPersonAnalyzer().personMask(blank))
    }
}
```

`PhotoPipelineTests.swift`의 `testEvictedPreviewReleasesRegionMasks` 뒤에 추가:

```swift
    func testPrepareStoresPersonMaskAndReportsPresence() async throws {
        let url = try writeSolidPNG()
        let mask = Support.personMask(
            size: CGSize(width: 64, height: 48), person: CGRect(x: 16, y: 8, width: 32, height: 32))
        let pipeline = PhotoPipeline(
            analyzer: StubFaceAnalyzer(result: .success([])),
            personAnalyzer: StubPersonAnalyzer(result: .success(mask)), tuning: RenderTuning())
        let id = PhotoID()
        let prepared = try await pipeline.prepare(id, at: url)
        XCTAssertTrue(prepared.hasPerson)
        XCTAssertNil(prepared.personAnalysisFailure)
        let analysis = await pipeline.preparedAnalysis(id)
        XCTAssertEqual(analysis?.personMask?.extent, mask.extent, "마스크는 받은 크기 그대로 보관한다")
    }

    func testPersonAnalysisFailureIsReportedNotThrown() async throws {
        let url = try writeSolidPNG()
        let face = FaceGeometry(boundingBox: NormalizedRect(x: 0.2, y: 0.2, width: 0.6, height: 0.6))
        let pipeline = PhotoPipeline(
            analyzer: StubFaceAnalyzer(result: .success([face])),
            personAnalyzer: StubPersonAnalyzer(result: .failure(.personAnalysisUnavailable(reason: "test"))),
            tuning: RenderTuning())
        let prepared = try await pipeline.prepare(PhotoID(), at: url)
        XCTAssertFalse(prepared.hasPerson)
        XCTAssertEqual(prepared.personAnalysisFailure, .personAnalysisUnavailable(reason: "test"))
        XCTAssertEqual(prepared.faces, [face], "인물 분석 실패가 얼굴 분석에 영향을 주지 않는다")
        XCTAssertNil(prepared.faceAnalysisFailure)
    }

    func testWithoutPersonAnalyzerThereIsNoPerson() async throws {
        let url = try writeSolidPNG()
        let pipeline = PhotoPipeline(analyzer: StubFaceAnalyzer(result: .success([])), tuning: RenderTuning())
        let id = PhotoID()
        let prepared = try await pipeline.prepare(id, at: url)
        XCTAssertFalse(prepared.hasPerson)
        XCTAssertNil(prepared.personAnalysisFailure)
        let analysis = await pipeline.preparedAnalysis(id)
        XCTAssertNil(analysis?.personMask)
    }
```

- [ ] **Step 3: 실패 확인**

Run: `cd apple && swift test --filter 'VisionPersonAnalyzerTests|PhotoPipelineTests'` → 컴파일 실패(`cannot find type 'PersonAnalyzer' in scope`, `type 'MellowError' has no member 'personAnalysisUnavailable'`).

- [ ] **Step 4: 구현**

`MellowError.swift`: `case faceAnalysisUnavailable(reason: String)` 아래에 추가:

```swift
    case personAnalysisUnavailable(reason: String)
```

`UserMessage.swift`의 `text(for:)` switch에서 `case .faceAnalysisUnavailable` 블록 아래에 추가:

```swift
        case .personAnalysisUnavailable(let reason):
            return "인물 영역을 분석할 수 없어 배경 흐림을 쓸 수 없습니다. 다른 보정은 사용할 수 있어요. (\(reason))"
```

`apple/Sources/MellowRendering/API/PersonAnalyzer.swift`:

```swift
import CoreImage
import MellowShared

/// 인물 영역 포트. 기본 구현은 Infrastructure의 VisionPersonAnalyzer다.
public protocol PersonAnalyzer: Sendable {
    /// 입력 이미지 전체를 덮는 회색조 마스크(사람 1·배경 0). extent 원점은 (0, 0)이고 가로세로 비율은 입력과 다를 수 있다.
    /// 사람이 없으면 nil. 분석 자체가 불가능하면 MellowError.personAnalysisUnavailable.
    func personMask(_ image: CIImage) throws -> CIImage?
}
```

`apple/Sources/MellowRendering/Infrastructure/VisionPersonAnalyzer.swift`:

```swift
import CoreImage
import MellowShared
import Vision

/// VNGeneratePersonSegmentationRequest로 인물 마스크를 만든다. 결과는 입력 비율과 무관한 고정 크기(기본 품질 512×384)다.
public struct VisionPersonAnalyzer: PersonAnalyzer {
    /// Vision이 결과를 주지 않았을 때의 사유 식별자. 사용자 문구는 앱이 정한다.
    public static let missingResultReason = "no-segmentation-result"
    /// 이 값(0…255) 이상인 마스크 픽셀을 사람으로 센다. 경계 중간값이다.
    private static let personByteThreshold: UInt8 = 128
    /// 사람 픽셀이 마스크의 이 비율보다 적으면 사람이 없다고 본다. 빈 장면은 0%, 작게 찍힌 전신 인물도 1%는 넘는다.
    private static let minimumCoverage = 0.01

    public init() {}

    public func personMask(_ image: CIImage) throws -> CIImage? {
        let request = VNGeneratePersonSegmentationRequest()
        request.qualityLevel = .balanced
        request.outputPixelFormat = kCVPixelFormatType_OneComponent8
        do {
            try VNImageRequestHandler(ciImage: image, options: [:]).perform([request])
        } catch {
            throw MellowError.personAnalysisUnavailable(reason: error.localizedDescription)
        }
        guard let buffer = request.results?.first?.pixelBuffer else {
            throw MellowError.personAnalysisUnavailable(reason: Self.missingResultReason)
        }
        guard Self.coverage(of: buffer) >= Self.minimumCoverage else { return nil }
        // 0…255를 색 관리 없이 0…1로 읽는다. 색공간을 붙이면 선형으로 바뀌어 경계 중간값이 달라진다.
        return CIImage(cvPixelBuffer: buffer, options: [.colorSpace: NSNull()])
    }

    /// 사람 픽셀(personByteThreshold 이상)의 비율.
    static func coverage(of buffer: CVPixelBuffer) -> Double {
        CVPixelBufferLockBaseAddress(buffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
        let width = CVPixelBufferGetWidth(buffer)
        let height = CVPixelBufferGetHeight(buffer)
        let rowBytes = CVPixelBufferGetBytesPerRow(buffer)
        guard width > 0, height > 0, let base = CVPixelBufferGetBaseAddress(buffer) else { return 0 }
        let bytes = base.assumingMemoryBound(to: UInt8.self)
        var covered = 0
        for row in 0..<height {
            for column in 0..<width where bytes[row * rowBytes + column] >= personByteThreshold {
                covered += 1
            }
        }
        return Double(covered) / Double(width * height)
    }
}
```

`PhotoAnalysis.swift`: `blemishes` 아래에 필드 둘을 더하고 init을 바꾼다:

```swift
    /// 회색조 인물 마스크(사람 1·배경 0). PersonAnalyzer가 준 크기 그대로이고 렌더 단계가 extent로 키운다. 사람이 없으면 nil.
    public var personMask: CIImage?
    /// 인물 분석이 실패했으면 그 이유. 사람이 없는 것과 구분한다.
    public var personAnalysisFailure: MellowError?
```

```swift
    public init(
        faces: [FaceGeometry] = [], faceAnalysisFailure: MellowError? = nil, blemishes: [BlemishSpot] = [],
        personMask: CIImage? = nil, personAnalysisFailure: MellowError? = nil
    ) {
        self.faces = faces
        self.faceAnalysisFailure = faceAnalysisFailure
        self.blemishes = blemishes
        self.personMask = personMask
        self.personAnalysisFailure = personAnalysisFailure
    }
```

`RenderStage.swift`: `public var blemishes` 아래에 추가:

```swift
    /// 사진 준비 때 만든 인물 마스크. 사람이 없거나 분석이 실패했으면 nil이고 배경 단계가 건너뛴다.
    public var personMask: CIImage? { analysis.personMask }
```

`PhotoPipeline.swift`:

1. `PreparedPhoto` 전체:

```swift
public struct PreparedPhoto: Sendable {
    public let pixelSize: CGSize
    public let thumbnail: CGImage
    public let faces: [FaceGeometry]
    /// 분석이 실패했으면 그 이유. 얼굴이 없는 것과 구분한다.
    public let faceAnalysisFailure: MellowError?
    /// 인물 마스크가 있으면 true. 배경 도구의 "사람 없음" 안내에 쓴다.
    public let hasPerson: Bool
    /// 인물 분석이 실패했으면 그 이유. 사람이 없는 것과 구분한다.
    public let personAnalysisFailure: MellowError?

    public init(
        pixelSize: CGSize, thumbnail: CGImage, faces: [FaceGeometry], faceAnalysisFailure: MellowError?,
        hasPerson: Bool = false, personAnalysisFailure: MellowError? = nil
    ) {
        self.pixelSize = pixelSize
        self.thumbnail = thumbnail
        self.faces = faces
        self.faceAnalysisFailure = faceAnalysisFailure
        self.hasPerson = hasPerson
        self.personAnalysisFailure = personAnalysisFailure
    }
}
```

2. `private let analyzer: any FaceAnalyzer` 아래에 `private let personAnalyzer: (any PersonAnalyzer)?`를 더하고 init을 바꾼다:

```swift
    /// personAnalyzer가 nil이면 인물 분석을 하지 않는다(사람 없음과 같다). 앱은 VisionPersonAnalyzer를 넘긴다.
    public init(
        analyzer: any FaceAnalyzer, personAnalyzer: (any PersonAnalyzer)? = nil, tuning: RenderTuning,
        lookCatalog: LookCatalog = .empty
    ) {
        self.analyzer = analyzer
        self.personAnalyzer = personAnalyzer
        self.tuning = tuning
        self.lookCatalog = lookCatalog
        cache = PreviewCache(capacity: tuning.previewCacheCapacity)
    }
```

3. `prepare`에서 `let analysis = PhotoAnalysis(…)`부터 `return PreparedPhoto(…)`까지를 다음으로 바꾼다:

```swift
        let person = analyzePerson(in: preview)
        let analysis = PhotoAnalysis(
            faces: faces, faceAnalysisFailure: failure, blemishes: detectBlemishes(in: preview, faces: faces),
            personMask: person.mask, personAnalysisFailure: person.failure)
        let thumbnail = try renderer.makeCGImage(Self.scaled(preview, maxDimension: tuning.thumbnailMaxDimension))
        entries[id] = Entry(analysis: analysis, thumbnail: CIImage(cgImage: thumbnail))
        cache.insert(preview, for: id)
        releaseMasksOfEvictedPreviews()
        return PreparedPhoto(
            pixelSize: metadata.pixelSize, thumbnail: thumbnail, faces: faces, faceAnalysisFailure: failure,
            hasPerson: person.mask != nil, personAnalysisFailure: person.failure)
```

4. `detectBlemishes`의 문서 주석을 다음으로 바꾸고, 그 아래에 `analyzePerson`을 더한다:

```swift
    /// 잡티 분석이 실패해도 사진 준비는 막지 않는다. 자동 잡티만 동작하지 않는다.
    /// 자동 잡티가 꺼져 있어도 준비 때 찾는다(사진당 약 0.06초). 분석은 준비 때 한 번이고(스펙 1.4) 스위치를 켤 때 지연이 없다.
```

```swift
    /// 인물 분석이 실패해도 사진 준비는 막지 않는다. 배경 흐림 단계만 건너뛴다(스펙 1.4).
    private func analyzePerson(in image: CIImage) -> (mask: CIImage?, failure: MellowError?) {
        guard let personAnalyzer else { return (nil, nil) }
        do {
            return (try personAnalyzer.personMask(image), nil)
        } catch let error as MellowError {
            return (nil, error)
        } catch {
            return (nil, .personAnalysisUnavailable(reason: error.localizedDescription))
        }
    }
```

- [ ] **Step 5: 통과 확인**

Run: `cd apple && swift test` → `Executed 230 tests, with 0 failures`(Shared 37 · Rendering 138 · Library 30 · Export 4 · Editing 21). lint 출력 없음. `./scripts/verify-modules.sh` 통과(새 import 없음). Mac 앱 테스트 → `Executed 53 tests, with 0 failures`.

- [ ] **Step 6: 커밋**

```bash
git add apple/Sources/MellowShared/API/MellowError.swift apple/Sources/MellowRendering apple/Tests/MellowRenderingTests apple/MellowPhoto/Application/UserMessage.swift
git commit -m "feat(rendering): 인물 영역 포트와 Vision 구현, 사진 준비 때 인물 분석

VNGeneratePersonSegmentationRequest로 인물 마스크를 만들어 PhotoAnalysis에 둔다.
실패는 PreparedPhoto.personAnalysisFailure로 남기고 사진 준비는 계속한다.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 3: 눈·입 영역 마스크 — FaceRegions 눈·눈동자·입술·치아, FeatureKernels 가중치

**Files:**
- Create: `apple/Sources/MellowRendering/Domain/FeatureKernels.swift`
- Modify: `apple/Sources/MellowRendering/Domain/FaceRegions.swift` (`landmarkPolygon` 공개, 눈·입 함수 추가)
- Modify: `apple/Sources/MellowRendering/API/RenderTuning.swift` (눈·입 영역 상수)
- Modify: `apple/Tests/MellowRenderingTests/RenderingTestSupport.swift` (`SyntheticFace.makeFeatures`)
- Test: `apple/Tests/MellowRenderingTests/FeatureRegionsTests.swift`

**Interfaces:**
- Consumes: `FaceRegions.polygonMask(…cache:)`·`RegionMaskCache`(Task 1), `MaskBuilder.ellipse`, `FaceRegions.pixelRect`·`faceWidth`·`boundingRect`·`centroid`, `ImageLoader`, `VisionFaceAnalyzer`.
- Produces: `FaceRegions.landmarkPolygon(_:_:_:)`(internal). `FaceRegions.RegionMask { image: CIImage; bounds: CGRect }`, `FaceRegions.IrisCircle { center: CGPoint; radius: CGFloat }`(Equatable). `FaceRegions.eyePolygons(face:extent:) -> [[CGPoint]]`, `irisCircles(face:extent:tuning:) -> [IrisCircle]`, `area(of:) -> CGFloat`, `innerMouthAreaFraction(face:extent:) -> Double?`, `eyeMask(face:extent:tuning:cache:) -> RegionMask?`, `irisMask(face:extent:tuning:cache:) -> RegionMask?`, `lipMask(face:extent:tuning:cache:) -> RegionMask?`, `teethMask(face:image:extent:tuning:cache:) throws -> RegionMask?`(모든 `cache` 기본 nil). `struct ToneRule`(`lumaMin`, `lumaRamp`, `limit`, `limitRamp`, `rednessOnly`, `static sclera(_:)`, `static teeth(_:)`). `final class FeatureKernels`(`shared`, `weight(of:rule:extent:) throws -> CIImage`). `RenderTuning`: featureMaskFeather, scleraLumaMin, scleraLumaRamp, scleraChromaMax, scleraChromaRamp, irisRadiusFraction, mouthOpenMinArea, teethLumaMin, teethLumaRamp, teethRednessMax, teethRednessRamp. 테스트 지원: `SyntheticFace.makeFeatures(mouthOpen:)`, `innerLips(radii:)`, `scleraColor`, `teethColor`, `irisRingRadii`, `irisRingColors`, `scleraPoint`, `lipPoint`, `lidSkin`, `philtrum`, `closedInnerMouthRadii`.

설계 근거:
- **다각형(B 이월 d).** `landmarkPolygon`을 internal로 열고 눈·입술·치아 마스크가 모두 그것으로 다각형을 만든다. 영역 계산은 여전히 `FaceRegions` 한 곳이다(분할 모델 교체 지점).
- **마스크 모양.** 다각형을 `polygonMask`(캐시)로 그리고 얼굴 폭 × `featureMaskFeather`(최소 `skinBlurMinimumRadius`)로 흐린 뒤 다각형 경계 상자 + 흐림 4배 여백(`bounds`) 밖을 정확히 0으로 자른다. 단계는 `bounds` 안만 계산하고 `CIBlendWithMask`로 원본 위에 얹으므로 그 밖 픽셀은 같은 바이트다(B·C에서 확인한 성질).
- **흰자·치아 가중치.** `FeatureKernels.weight`가 감마(sRGB) 값의 BT.601 휘도와 Cb·Cr로 `clamp((휘도 − lumaMin)/lumaRamp) × clamp((limit − 지표)/limitRamp)`를 만든다. 지표는 흰자에서 Cb·Cr 거리(채도), 치아에서 Cr(붉은기)이다. 측정(이 계획의 단색 표본): 흰자 (0.78, 0.74, 0.72) → 1, 홍채 (0.30, 0.20, 0.12) → 0, 피부 (0.84, 0.66, 0.56) → 0. 치아 (0.86, 0.80, 0.66) → 0.975, 입술 (0.72, 0.28, 0.32)·잇몸 (0.80, 0.45, 0.45)·입안 그늘·피부 → 0.
- **눈동자 원.** 중심은 동공(없으면 눈 다각형 꼭짓점 평균), 반지름은 눈 높이 × 0.5(스펙). 눈 높이는 눈 다각형 경계 상자의 짧은 변이다. 기운 눈에서 조금 커지지만 원 마스크에 눈 마스크를 곱해 눈꺼풀로는 넘치지 않는다.
- **입 열림.** 안쪽 입술 다각형 넓이 ÷ 얼굴 상자 넓이(픽셀)가 `mouthOpenMinArea`(0.4%) 미만이면 치아 마스크가 nil(스펙의 "얼굴 면적"은 얼굴 상자 넓이로 계산). 합성 얼굴: 벌린 입 1.14%, 다문 입 0.14%.

- [ ] **Step 1: 테스트 지원 코드**

`RenderingTestSupport.swift`의 `struct SyntheticFace { … }` 바로 아래(같은 파일, private 멤버 `paint`·`ellipse`를 쓰므로 반드시 이 파일)에 추가:

```swift
/// 흰자·홍채·치아까지 그린 합성 얼굴. 눈 다각형·동공·입술 특징점은 make()와 같다.
extension SyntheticFace {
    static let scleraColor = CIColor(red: 0.78, green: 0.74, blue: 0.72)
    static let teethColor = CIColor(red: 0.86, green: 0.80, blue: 0.66)
    /// 홍채 바깥 고리·안쪽 고리·동공의 반지름(픽셀). 눈 높이 28px × 0.5 = 14px 원 안에 든다.
    static let irisRingRadii: [CGFloat] = [12, 7, 3]
    static let irisRingColors = [
        CIColor(red: 0.30, green: 0.20, blue: 0.12), CIColor(red: 0.50, green: 0.36, blue: 0.22),
        CIColor(red: 0.04, green: 0.03, blue: 0.03),
    ]
    /// 다문 입의 안쪽 입술 타원. 높이 1px이라 넓이가 얼굴 상자의 0.14%다.
    static let closedInnerMouthRadii = CGSize(width: 40, height: 1)
    /// 흰자 위 표본 점(왼눈 중심에서 20px 바깥). 홍채 고리 밖이고 눈 다각형 안이다.
    static let scleraPoint = CGPoint(x: 180, y: 300)
    /// 입술 고리(바깥 20px·안쪽 8px 반지름 사이) 위 표본 점.
    static let lipPoint = CGPoint(x: 256, y: 152)
    /// 왼눈 위끝(314)과 눈썹 아래끝(332) 사이 피부.
    static let lidSkin = CGPoint(x: 200, y: 324)
    /// 입술 위끝(160)과 코 아래(190) 사이 피부.
    static let philtrum = CGPoint(x: 256, y: 172)

    /// mouthOpen이 false면 치아를 그리지 않고 안쪽 입술을 closedInnerMouthRadii 타원으로 둔다(다문 입).
    static func makeFeatures(mouthOpen: Bool = true) -> SyntheticFace {
        let base = make()
        var image = base.image
        for eye in [leftEye, rightEye] {
            image = paint(CIImage(color: scleraColor), center: eye, radii: eyeRadii, over: image)
            for (radius, color) in zip(irisRingRadii, irisRingColors) {
                let radii = CGSize(width: radius, height: radius)
                image = paint(CIImage(color: color), center: eye, radii: radii, over: image)
            }
        }
        var face = base.face
        if mouthOpen {
            image = paint(CIImage(color: teethColor), center: mouth, radii: innerMouthRadii, over: image)
        } else {
            face.landmarks[.innerLips] = innerLips(radii: closedInnerMouthRadii)
        }
        return SyntheticFace(image: image, face: face)
    }

    /// 입 중심의 12점 타원 안쪽 입술 특징점(정규화).
    static func innerLips(radii: CGSize) -> [NormalizedPoint] {
        ellipse(mouth, radii)
    }
}
```

- [ ] **Step 2: 실패하는 테스트 작성**

`apple/Tests/MellowRenderingTests/FeatureRegionsTests.swift`:

```swift
import CoreImage
import MellowShared
import XCTest

@testable import MellowRendering

final class FeatureRegionsTests: XCTestCase {
    typealias Support = RenderingTestSupport

    private let extent = SyntheticFace.extent
    private let tuning = RenderTuning()

    func testEyeMaskCoversEyesAndIsZeroOutsideTheirBounds() throws {
        let face = SyntheticFace.makeFeatures().face
        let mask = try XCTUnwrap(FaceRegions.eyeMask(face: face, extent: extent, tuning: tuning))
        XCTAssertEqual(mask.image.extent, extent)
        let pixels = try Support.grid(mask.image)
        XCTAssertGreaterThan(pixels.red(SyntheticFace.scleraPoint), 200)
        XCTAssertGreaterThan(pixels.red(SyntheticFace.rightEye), 200)
        XCTAssertEqual(pixels.red(SyntheticFace.lidSkin), 0)
        XCTAssertEqual(pixels.red(SyntheticFace.mouth), 0)
        XCTAssertFalse(mask.bounds.contains(SyntheticFace.lidSkin), "눈 위 피부는 계산 영역 밖")
    }

    func testIrisCirclesUsePupilOrFallBackToEyeCenter() throws {
        let face = SyntheticFace.makeFeatures().face
        let circles = FaceRegions.irisCircles(face: face, extent: extent, tuning: tuning)
        XCTAssertEqual(circles.count, 2)
        XCTAssertEqual(circles[0].center.x, SyntheticFace.leftEye.x, accuracy: 1e-6)
        XCTAssertEqual(circles[0].center.y, SyntheticFace.leftEye.y, accuracy: 1e-6)
        XCTAssertEqual(circles[0].radius, 14, accuracy: 1e-6, "눈 높이 28px × 0.5")
        var shifted = face
        shifted.landmarks[.leftPupil] = [NormalizedPoint(x: 205.0 / 512, y: 300.0 / 512)]
        let moved = FaceRegions.irisCircles(face: shifted, extent: extent, tuning: tuning)
        XCTAssertEqual(moved[0].center.x, 205, accuracy: 1e-6, "동공이 있으면 동공이 중심")
        let fallback = FaceRegions.irisCircles(
            face: face.removing([.leftPupil, .rightPupil]), extent: extent, tuning: tuning)
        XCTAssertEqual(fallback.count, 2)
        XCTAssertEqual(fallback[1].center.x, SyntheticFace.rightEye.x, accuracy: 1e-6, "동공이 없으면 눈 다각형 가운데")
        XCTAssertEqual(fallback[1].center.y, SyntheticFace.rightEye.y, accuracy: 1e-6)
    }

    func testTeethMaskKeepsTeethAndDropsRedLipInsideThePolygon() throws {
        let synthetic = SyntheticFace.makeFeatures()
        var face = synthetic.face
        // 안쪽 입술 다각형을 입술 고리까지 넓혀도 붉은 입술 픽셀은 치아로 잡히지 않는다.
        face.landmarks[.innerLips] = SyntheticFace.innerLips(radii: CGSize(width: 46, height: 16))
        let mask = try XCTUnwrap(
            try FaceRegions.teethMask(face: face, image: synthetic.image, extent: extent, tuning: tuning))
        let pixels = try Support.grid(mask.image)
        XCTAssertGreaterThan(pixels.red(SyntheticFace.mouth), 200, "치아")
        XCTAssertEqual(pixels.red(SyntheticFace.lipPoint), 0, "다각형 안이어도 붉은 입술은 치아가 아니다")
        XCTAssertEqual(pixels.red(SyntheticFace.philtrum), 0)
    }

    func testClosedMouthHasNoTeethMask() throws {
        let open = SyntheticFace.makeFeatures()
        let closed = SyntheticFace.makeFeatures(mouthOpen: false)
        let openFraction = try XCTUnwrap(FaceRegions.innerMouthAreaFraction(face: open.face, extent: extent))
        let closedFraction = try XCTUnwrap(FaceRegions.innerMouthAreaFraction(face: closed.face, extent: extent))
        XCTAssertGreaterThan(openFraction, tuning.mouthOpenMinArea)
        XCTAssertLessThan(closedFraction, tuning.mouthOpenMinArea)
        XCTAssertNotNil(try FaceRegions.teethMask(face: open.face, image: open.image, extent: extent, tuning: tuning))
        XCTAssertNil(
            try FaceRegions.teethMask(face: closed.face, image: closed.image, extent: extent, tuning: tuning),
            "다문 입은 치아 마스크가 없다")
    }

    func testLipMaskIsTheRingBetweenOuterAndInnerLips() throws {
        let face = SyntheticFace.makeFeatures().face
        let mask = try XCTUnwrap(FaceRegions.lipMask(face: face, extent: extent, tuning: tuning))
        let pixels = try Support.grid(mask.image)
        XCTAssertGreaterThan(pixels.red(SyntheticFace.lipPoint), 200)
        XCTAssertEqual(pixels.red(SyntheticFace.mouth), 0, "안쪽 입술(치아)은 뺀다")
        XCTAssertEqual(pixels.red(SyntheticFace.philtrum), 0)
        let whole = try XCTUnwrap(
            FaceRegions.lipMask(face: face.removing([.innerLips]), extent: extent, tuning: tuning))
        XCTAssertGreaterThan(try Support.grid(whole.image).red(SyntheticFace.mouth), 200, "안쪽 입술이 없으면 바깥 입술 전체")
    }

    func testFaceWithoutLandmarksHasNoFeatureMasks() throws {
        let boxOnly = SyntheticFace.make(landmarks: false)
        XCTAssertNil(FaceRegions.eyeMask(face: boxOnly.face, extent: extent, tuning: tuning))
        XCTAssertNil(FaceRegions.irisMask(face: boxOnly.face, extent: extent, tuning: tuning))
        XCTAssertNil(FaceRegions.lipMask(face: boxOnly.face, extent: extent, tuning: tuning))
        XCTAssertNil(
            try FaceRegions.teethMask(face: boxOnly.face, image: boxOnly.image, extent: extent, tuning: tuning))
        XCTAssertTrue(FaceRegions.irisCircles(face: boxOnly.face, extent: extent, tuning: tuning).isEmpty)
        XCTAssertNil(FaceRegions.innerMouthAreaFraction(face: boxOnly.face, extent: extent))
    }

    func testDemoPortraitFeatureMasksFollowRealLandmarks() throws {
        let url = try XCTUnwrap(
            Bundle.module.url(forResource: "demo-portrait", withExtension: "png", subdirectory: "Fixtures"))
        let image = try ImageLoader().load(url: url, maxDimension: 1200)
        let photo = image.extent
        let face = try XCTUnwrap(try VisionFaceAnalyzer().analyze(image).first)
        let eyes = try XCTUnwrap(FaceRegions.eyeMask(face: face, extent: photo, tuning: tuning))
        let lips = try XCTUnwrap(FaceRegions.lipMask(face: face, extent: photo, tuning: tuning))
        let pupil = try XCTUnwrap(face.landmarks[.leftPupil]?.first)
        let pupilPoint = CGPoint(x: pupil.x * photo.width, y: pupil.y * photo.height)
        XCTAssertGreaterThan(try Support.grid(eyes.image).red(pupilPoint), 128, "실제 동공은 눈 마스크 안")
        XCTAssertEqual(try Support.grid(lips.image).red(pupilPoint), 0, "동공은 입술 마스크 밖")
        let lipBox = FaceRegions.pixelRect(try XCTUnwrap(face.bounds(of: .outerLips)), in: photo)
        let brightest = try Support.renderer.readPixels(
            lips.image.applyingFilter("CIAreaMaximum", parameters: [kCIInputExtentKey: CIVector(cgRect: lipBox)]))
        XCTAssertGreaterThan(brightest[0], 0.9, "실제 입술 고리가 마스크에 들어간다")
        XCTAssertNotNil(FaceRegions.innerMouthAreaFraction(face: face, extent: photo))
    }
}
```

- [ ] **Step 3: 실패 확인**

Run: `cd apple && swift test --filter FeatureRegionsTests` → 컴파일 실패(`type 'FaceRegions' has no member 'eyeMask'`, `value of type 'RenderTuning' has no member 'mouthOpenMinArea'`).

- [ ] **Step 4: 구현**

`RenderTuning.swift`: `faceShapeMaxShift(_:)` 함수 아래, `spotMaxRadiusFraction` 위에 추가:

```swift
    /// 눈·입술·치아 다각형 마스크를 흐리는 반지름. 얼굴 폭 비율. 300px 얼굴에서 1.2px라 눈꺼풀·피부로 거의 번지지 않는다.
    public var featureMaskFeather: Double = 0.004
    /// 흰자로 보는 밝기(sRGB 감마 BT.601 휘도)의 시작점과 1이 되는 폭. 홍채·속눈썹(0.2 안팎)은 빠지고 흰자(0.6~0.8)는 들어간다.
    public var scleraLumaMin: Double = 0.45
    public var scleraLumaRamp: Double = 0.15
    /// 흰자로 보는 채도(감마 Cb·Cr 거리) 상한과 0이 되는 폭. 흰자는 0.03 안팎, 눈꼬리 피부는 0.12 이상이다.
    public var scleraChromaMax: Double = 0.08
    public var scleraChromaRamp: Double = 0.04
    /// 눈동자 반지름. 눈 높이(눈 다각형 경계 상자의 짧은 변) 비율(스펙 0.5).
    public var irisRadiusFraction: Double = 0.5
    /// 안쪽 입술 넓이가 얼굴 상자 넓이의 이 비율보다 작으면 다문 입으로 보고 치아 미백을 건너뛴다.
    /// 다문 입의 안쪽 입술은 0.3% 안팎, 치아가 보이는 입은 1% 이상이다.
    public var mouthOpenMinArea: Double = 0.004
    /// 치아로 보는 밝기 시작점과 폭. 입안 그늘(0.1 안팎)은 빠진다.
    public var teethLumaMin: Double = 0.35
    public var teethLumaRamp: Double = 0.15
    /// 치아로 보는 붉은기(감마 Cr) 상한과 0이 되는 폭. 누런 치아는 0.04 안팎, 잇몸·혀·입술은 0.15 이상이다.
    public var teethRednessMax: Double = 0.08
    public var teethRednessRamp: Double = 0.04
```

`apple/Sources/MellowRendering/Domain/FeatureKernels.swift`:

```swift
import CoreImage
import MellowShared

/// 눈·치아 영역을 고르는 밝기·채도 규칙. 값은 sRGB 감마 기준이다.
struct ToneRule: Equatable {
    /// 이 휘도에서 가중치가 오르기 시작해 lumaMin + lumaRamp에서 1이 된다.
    var lumaMin: Double
    var lumaRamp: Double
    /// 지표가 limit 아래면 1, limit + limitRamp 위면 0이다.
    var limit: Double
    var limitRamp: Double
    /// true면 지표가 Cr(붉은기), false면 Cb·Cr 거리(채도).
    var rednessOnly: Bool

    /// 흰자: 밝고 무채색.
    static func sclera(_ tuning: RenderTuning) -> ToneRule {
        ToneRule(
            lumaMin: tuning.scleraLumaMin, lumaRamp: tuning.scleraLumaRamp, limit: tuning.scleraChromaMax,
            limitRamp: tuning.scleraChromaRamp, rednessOnly: false)
    }

    /// 치아: 밝고 붉지 않음. 누런 기는 남기고 입술·잇몸·혀를 뺀다.
    static func teeth(_ tuning: RenderTuning) -> ToneRule {
        ToneRule(
            lumaMin: tuning.teethLumaMin, lumaRamp: tuning.teethLumaRamp, limit: tuning.teethRednessMax,
            limitRamp: tuning.teethRednessRamp, rednessOnly: true)
    }
}

/// 눈·입 보정의 CIKL 색 커널을 감싸는 유일한 자리. SkinKernels처럼 Metal로 바꿀 때 이 타입만 바꾼다.
final class FeatureKernels: @unchecked Sendable {
    static let shared = FeatureKernels()

    private let toneWeight: CIColorKernel?

    /// 휘도는 BT.601, Cb·Cr은 SkinKernels와 같은 BT.601 계수다(sRGB 감마 값 기준).
    private init() {
        toneWeight = CIColorKernel(
            source: """
                kernel vec4 toneWeight(__sample pixel, float lumaMin, float lumaRamp, float limit, float limitRamp,
                                       float rednessOnly) {
                    float luma = dot(pixel.rgb, vec3(0.299, 0.587, 0.114));
                    vec2 chroma = vec2(dot(pixel.rgb, vec3(-0.168736, -0.331264, 0.5)),
                                       dot(pixel.rgb, vec3(0.5, -0.418688, -0.081312)));
                    float metric = mix(length(chroma), chroma.y, rednessOnly);
                    float bright = clamp((luma - lumaMin) / lumaRamp, 0.0, 1.0);
                    float plain = clamp((limit - metric) / limitRamp, 0.0, 1.0);
                    float w = bright * plain;
                    return vec4(w, w, w, 1.0);
                }
                """)
    }

    /// image는 작업 색공간(선형) 이미지. 감마로 바꿔 규칙을 적용한 회색 가중치(0…1)를 extent 안에서 돌려준다.
    func weight(of image: CIImage, rule: ToneRule, extent: CGRect) throws -> CIImage {
        guard let toneWeight, rule.lumaRamp > 0, rule.limitRamp > 0 else { throw MellowError.renderFailed }
        let encoded = image.applyingFilter("CILinearToSRGBToneCurve")
        let arguments: [Any] = [
            encoded, rule.lumaMin, rule.lumaRamp, rule.limit, rule.limitRamp, rule.rednessOnly ? 1.0 : 0.0,
        ]
        guard let weight = toneWeight.apply(extent: extent, arguments: arguments) else {
            throw MellowError.renderFailed
        }
        return weight
    }
}
```

`FaceRegions.swift`:
1. `private static func landmarkPolygon(` 선언에서 `private`를 지우고 문서 주석 `/// 특징점 다각형(픽셀). 점이 셋보다 적으면 nil.`을 붙인다.
2. `enum FaceRegions {` 바로 아래(상수 선언들 앞)에 두 타입을 추가:

```swift
    /// 눈·입 마스크와 그 마스크가 0이 아닐 수 있는 영역. 영역 밖 마스크는 정확히 0이다.
    struct RegionMask {
        let image: CIImage
        let bounds: CGRect
    }

    /// 눈동자 원(픽셀).
    struct IrisCircle: Equatable {
        let center: CGPoint
        let radius: CGFloat
    }
```

3. `contains(_:polygons:dilation:)` 위에 눈·입 함수들을 추가:

```swift
    /// 두 눈 다각형. 특징점이 없는 눈은 뺀다.
    static func eyePolygons(face: FaceGeometry, extent: CGRect) -> [[CGPoint]] {
        [FaceLandmark.leftEye, .rightEye].compactMap { landmarkPolygon(face, $0, extent) }
    }

    /// 눈마다 동공(없으면 눈 다각형 꼭짓점 평균)을 중심으로, 눈 높이 × irisRadiusFraction을 반지름으로 한 원.
    /// 눈 높이는 눈 다각형 경계 상자의 짧은 변이다. 기운 눈에서 조금 커지지만 눈 마스크를 곱해 쓰므로 넘치지 않는다.
    static func irisCircles(face: FaceGeometry, extent: CGRect, tuning: RenderTuning) -> [IrisCircle] {
        let pairs: [(FaceLandmark, FaceLandmark)] = [(.leftEye, .leftPupil), (.rightEye, .rightPupil)]
        return pairs.compactMap { eye, pupil in
            guard let polygon = landmarkPolygon(face, eye, extent) else { return nil }
            let box = boundingRect(polygon)
            let pupilPoint = face.landmarks[pupil]?.first.map { point in
                CGPoint(x: extent.minX + point.x * extent.width, y: extent.minY + point.y * extent.height)
            }
            let radius = min(box.width, box.height) * CGFloat(tuning.irisRadiusFraction)
            return IrisCircle(center: pupilPoint ?? centroid(polygon), radius: radius)
        }
    }

    /// 다각형 넓이(픽셀²). 점 순서 방향과 무관하다.
    static func area(of polygon: [CGPoint]) -> CGFloat {
        guard polygon.count >= minimumPolygonPoints else { return 0 }
        var twice: CGFloat = 0
        for index in polygon.indices {
            let current = polygon[index]
            let next = polygon[(index + 1) % polygon.count]
            twice += current.x * next.y - next.x * current.y
        }
        return abs(twice) / 2
    }

    /// 안쪽 입술 다각형 넓이 ÷ 얼굴 상자 넓이(픽셀). 안쪽 입술이 없으면 nil.
    static func innerMouthAreaFraction(face: FaceGeometry, extent: CGRect) -> Double? {
        guard let inner = landmarkPolygon(face, .innerLips, extent) else { return nil }
        let box = pixelRect(face.boundingBox, in: extent)
        let faceArea = box.width * box.height
        guard faceArea > 0 else { return nil }
        return Double(area(of: inner) / faceArea)
    }

    /// 두 눈 다각형 마스크. 눈 특징점이 없으면 nil.
    static func eyeMask(face: FaceGeometry, extent: CGRect, tuning: RenderTuning, cache: RegionMaskCache? = nil)
        -> RegionMask?
    {
        let eyes = eyePolygons(face: face, extent: extent)
        guard !eyes.isEmpty else { return nil }
        return featheredPolygonMask(fill: eyes, cut: [], face: face, extent: extent, tuning: tuning, cache: cache)
    }

    /// 눈동자 원(가운데 0.65까지 1, 가장자리에서 0) × 눈 마스크. 눈 특징점이 없으면 nil.
    static func irisMask(face: FaceGeometry, extent: CGRect, tuning: RenderTuning, cache: RegionMaskCache? = nil)
        -> RegionMask?
    {
        let circles = irisCircles(face: face, extent: extent, tuning: tuning)
        guard !circles.isEmpty, let eyes = eyeMask(face: face, extent: extent, tuning: tuning, cache: cache) else {
            return nil
        }
        var discs = CIImage(color: .black).cropped(to: extent)
        for circle in circles {
            let rect = CGRect(
                x: circle.center.x - circle.radius, y: circle.center.y - circle.radius, width: circle.radius * 2,
                height: circle.radius * 2)
            discs = MaskBuilder.ellipse(rect, extent: extent)
                .applyingFilter("CIMaximumCompositing", parameters: [kCIInputBackgroundImageKey: discs])
        }
        let image = discs.applyingFilter("CIMultiplyCompositing", parameters: [kCIInputBackgroundImageKey: eyes.image])
            .cropped(to: extent)
        return RegionMask(image: image, bounds: eyes.bounds)
    }

    /// 입술 = 바깥 입술 − 안쪽 입술. 안쪽 입술이 없으면 바깥 입술 전체, 바깥 입술이 없으면 nil.
    static func lipMask(face: FaceGeometry, extent: CGRect, tuning: RenderTuning, cache: RegionMaskCache? = nil)
        -> RegionMask?
    {
        guard let outer = landmarkPolygon(face, .outerLips, extent) else { return nil }
        let inner = landmarkPolygon(face, .innerLips, extent).map { [$0] } ?? []
        return featheredPolygonMask(fill: [outer], cut: inner, face: face, extent: extent, tuning: tuning, cache: cache)
    }

    /// 치아 = 안쪽 입술 다각형 × 밝기 × 낮은 붉은기(스펙 4). 다문 입(넓이 비율 < mouthOpenMinArea)이거나 안쪽 입술이 없으면 nil.
    static func teethMask(
        face: FaceGeometry, image: CIImage, extent: CGRect, tuning: RenderTuning, cache: RegionMaskCache? = nil
    ) throws -> RegionMask? {
        guard let inner = landmarkPolygon(face, .innerLips, extent),
            let fraction = innerMouthAreaFraction(face: face, extent: extent), fraction >= tuning.mouthOpenMinArea,
            let region = featheredPolygonMask(
                fill: [inner], cut: [], face: face, extent: extent, tuning: tuning, cache: cache)
        else { return nil }
        let weight = try FeatureKernels.shared.weight(of: image, rule: .teeth(tuning), extent: region.bounds)
        let black = CIImage(color: .black).cropped(to: extent)
        let background = weight.composited(over: black)
        let masked = region.image
            .applyingFilter("CIMultiplyCompositing", parameters: [kCIInputBackgroundImageKey: background])
            .cropped(to: extent)
        return RegionMask(image: masked, bounds: region.bounds)
    }
```

4. `private static func featherRadius(` 위에 공통 도우미를 추가:

```swift
    /// 다각형 마스크를 얼굴 폭 × featureMaskFeather로 흐리고 경계 상자 + 흐림 4배 여백 밖을 0으로 자른다.
    /// cut은 넓히지 않는다(선 굵기 0은 CGContext의 가장 가는 선이다).
    private static func featheredPolygonMask(
        fill: [[CGPoint]], cut: [[CGPoint]], face: FaceGeometry, extent: CGRect, tuning: RenderTuning,
        cache: RegionMaskCache?
    ) -> RegionMask? {
        let feather = max(
            CGFloat(tuning.skinBlurMinimumRadius), faceWidth(face, extent: extent) * CGFloat(tuning.featureMaskFeather))
        let padding = feather * boundsPaddingInFeathers
        let bounds = boundingRect(fill.flatMap { $0 }).insetBy(dx: -padding, dy: -padding).intersection(extent).integral
        guard !bounds.isEmpty else { return nil }
        let raster = polygonMask(fill: fill, cut: cut, cutWidth: 0, extent: extent, tuning: tuning, cache: cache)
        let black = CIImage(color: .black).cropped(to: extent)
        let image = raster.clampedToExtent()
            .applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: feather])
            .cropped(to: bounds).composited(over: black)
        return RegionMask(image: image, bounds: bounds)
    }
```

- [ ] **Step 5: 통과 확인**

Run: `cd apple && swift test --filter FeatureRegionsTests` → 7개 PASS. 이어서 `cd apple && swift test` → `Executed 237 tests, with 0 failures`(Shared 37 · Rendering 145 · Library 30 · Export 4 · Editing 21). lint 출력 없음. 빌드 경고에 `FeatureKernels.swift`의 `CIColorKernel(source:)` 지원 중단이 하나 늘어난다(허용).

- [ ] **Step 6: 커밋**

```bash
git add apple/Sources/MellowRendering/Domain/FeatureKernels.swift apple/Sources/MellowRendering/Domain/FaceRegions.swift apple/Sources/MellowRendering/API/RenderTuning.swift apple/Tests/MellowRenderingTests/RenderingTestSupport.swift apple/Tests/MellowRenderingTests/FeatureRegionsTests.swift
git commit -m "feat(rendering): 눈·눈동자·입술·치아 영역 마스크 추가

FaceRegions가 특징점 다각형으로 눈·입술·치아 마스크를 만들고, 흰자·치아는
감마 YCbCr 밝기·채도 가중치를 곱한다. 다문 입은 치아 마스크가 없다.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 4: 눈·입 보정 단계 — FeatureStage

**Files:**
- Create: `apple/Sources/MellowRendering/Domain/FeatureStage.swift`
- Modify: `apple/Sources/MellowRendering/Domain/FeatureKernels.swift` (`ToneShift`, `toneShift` 커널, `shifted(_:by:extent:)`)
- Modify: `apple/Sources/MellowRendering/API/RenderTuning.swift` (보정 강도 상수)
- Modify: `apple/Sources/MellowRendering/API/RenderPipeline.swift` (`standard`에 `FeatureStage`)
- Test: `apple/Tests/MellowRenderingTests/FeatureStageTests.swift`, `apple/Tests/MellowRenderingTests/RenderPipelineTests.swift`

**Interfaces:**
- Consumes: `FaceRegions.eyeMask`·`irisMask`·`irisCircles`·`lipMask`·`teethMask`·`RegionMask`, `ToneRule.sclera`, `FeatureKernels.weight`(Task 3), `RenderContext.regionMasks`(Task 1), `MaskBuilder.blend`, `AdjustmentRange`, 테스트 지원 `SyntheticFace.makeFeatures` 등(Task 3).
- Produces: `struct ToneShift: Equatable`(`lift = 0`, `yellowRemoval = 0`, `saturation = 1`, `redness = 0`), `FeatureKernels.shifted(_:by:extent:) throws -> CIImage`. `struct FeatureStage: RenderStage`(이름 `"feature"`, `static func clamped(_:) -> FeatureAdjustments`). `RenderTuning`: eyeWhiteLift, eyeIrisSharpen, eyeIrisSharpenRadiusFraction, teethYellowRemoval, teethLift, lipSaturationMax, lipRednessMax. `RenderPipeline.standard` = `skin, feature, shapeWarp, localEdit, geometry, color, detail, look`.

설계 근거:
- **색 이동.** `toneShift` 커널이 감마 값에서 Y·Cb·Cr로 나눠 `cb ← (cb − min(cb, 0) × yellowRemoval) × saturation`, `cr ← cr × saturation + redness`로 바꾸고 RGB로 되돌린 뒤 `mix(rgb, 1, lift)`로 흰색 쪽으로 섞고 0…1로 자른다. 스펙의 "노란기(Cb 쪽 이동) 제거"는 음의 Cb(노랑)를 0 쪽으로 옮기는 것으로 해석했다. 모든 이동이 기본값이면 항등이다(측정: 바이트 동일).
- **단계 동작.** 대상 얼굴마다 눈 → 치아 → 입술 순서. 각 효과는 마스크 `bounds` 안에서만 커널·필터를 계산하고 `MaskBuilder.blend`로 원본 위에 얹는다. 흰자 마스크 = 눈 마스크 × 흰자 가중치, 홍채는 `CISharpenLuminance`(선명도 `eyeIrisSharpen × 값`, 반지름 = 큰 눈동자 반지름 × `eyeIrisSharpenRadiusFraction`, 최소 1px)를 눈동자 원 마스크로 얹는다. 치아는 노란기 제거 + 흰색 쪽, 입술은 채도·붉은기. 값은 `AdjustmentRange.unit`으로 자른다.
- **시작 강도 근거(측정, 이 계획의 단색 표본).** 흰자 sRGB (199, 189, 184) → lift 0.2에서 (210, 202, 198). 치아 (219, 204, 168) → 노란기 0.7·lift 0.12에서 (224, 206, 201). 입술 (184, 71, 82)은 채도 1.35·붉은기 0.03에서 (221, 54, 73)으로 과해 시작값을 채도 +0.3·붉은기 0.02로 낮췄다. 홍채 고리 합성 이미지의 휘도 분산은 선명도 0.8·반지름 1.4px에서 2.28배.

- [ ] **Step 1: 실패하는 테스트 작성**

`apple/Tests/MellowRenderingTests/FeatureStageTests.swift`:

```swift
import CoreImage
import MellowShared
import XCTest

@testable import MellowRendering

final class FeatureStageTests: XCTestCase {
    typealias Support = RenderingTestSupport

    private let extent = SyntheticFace.extent

    private func output(_ synthetic: SyntheticFace, _ features: FeatureAdjustments, face: FaceGeometry? = nil) throws
        -> CIImage
    {
        var recipe = EditRecipe()
        recipe.portrait.features = features
        let context = RenderContext(
            extent: extent, recipe: recipe, faces: [face ?? synthetic.face], tuning: RenderTuning())
        return try FeatureStage().apply(synthetic.image, in: context)
    }

    private func render(_ synthetic: SyntheticFace, _ features: FeatureAdjustments, face: FaceGeometry? = nil) throws
        -> PixelGrid
    {
        try Support.grid(output(synthetic, features, face: face))
    }

    func testZeroFeaturesOrNoFacesReturnInputBytes() throws {
        let synthetic = SyntheticFace.makeFeatures()
        XCTAssertEqual(
            try Support.bytes(output(synthetic, FeatureAdjustments())), try Support.bytes(synthetic.image))
        var recipe = EditRecipe()
        recipe.portrait.features = FeatureAdjustments(eyeBrighten: 1, teethWhiten: 1, lipVitality: 1)
        let noFaces = RenderContext(extent: extent, recipe: recipe, faces: [], tuning: RenderTuning())
        XCTAssertEqual(
            try Support.bytes(FeatureStage().apply(synthetic.image, in: noFaces)), try Support.bytes(synthetic.image))
    }

    func testEyeBrightenLiftsScleraSharpensIrisAndLeavesSkin() throws {
        let synthetic = SyntheticFace.makeFeatures()
        let before = try Support.grid(synthetic.image)
        let image = try output(synthetic, FeatureAdjustments(eyeBrighten: 1))
        let after = try Support.grid(image)
        XCTAssertGreaterThanOrEqual(
            Int(after.red(SyntheticFace.scleraPoint)), Int(before.red(SyntheticFace.scleraPoint)) + 5, "흰자가 밝아진다")
        for point in [SyntheticFace.lidSkin, SyntheticFace.mouth, SyntheticFace.lipPoint, SyntheticFace.cheek] {
            XCTAssertEqual(after.rgba(point), before.rgba(point), "눈 마스크 밖 \(point)")
        }
        let iris = CGRect(x: SyntheticFace.leftEye.x - 9, y: SyntheticFace.leftEye.y - 9, width: 18, height: 18)
        let sharpened = Support.variance(try Support.luma(image.cropped(to: iris)))
        let original = Support.variance(try Support.luma(synthetic.image.cropped(to: iris)))
        XCTAssertGreaterThan(sharpened, original * 1.2, "홍채 고리 경계가 선명해진다")
    }

    func testTeethWhitenBrightensAndNeutralizesTeethOnly() throws {
        let synthetic = SyntheticFace.makeFeatures()
        let before = try Support.grid(synthetic.image)
        let after = try render(synthetic, FeatureAdjustments(teethWhiten: 1))
        let teethBefore = before.rgba(SyntheticFace.mouth)
        let teethAfter = after.rgba(SyntheticFace.mouth)
        XCTAssertGreaterThanOrEqual(Int(teethAfter[2]), Int(teethBefore[2]) + 15, "노란기가 빠져 파랑이 오른다")
        XCTAssertGreaterThanOrEqual(Int(teethAfter[1]), Int(teethBefore[1]), "어두워지지 않는다")
        for point in [SyntheticFace.lipPoint, SyntheticFace.philtrum, SyntheticFace.scleraPoint] {
            XCTAssertEqual(after.rgba(point), before.rgba(point), "치아 마스크 밖 \(point)")
        }
    }

    func testClosedMouthTeethWhitenChangesNothing() throws {
        let closed = SyntheticFace.makeFeatures(mouthOpen: false)
        XCTAssertEqual(
            try Support.bytes(output(closed, FeatureAdjustments(teethWhiten: 1))), try Support.bytes(closed.image),
            "다문 입은 치아 미백이 아무것도 바꾸지 않는다")
    }

    func testLipVitalitySaturatesLipRingOnly() throws {
        let synthetic = SyntheticFace.makeFeatures()
        let before = try Support.grid(synthetic.image)
        let after = try render(synthetic, FeatureAdjustments(lipVitality: 1))
        let lipBefore = before.rgba(SyntheticFace.lipPoint)
        let lipAfter = after.rgba(SyntheticFace.lipPoint)
        XCTAssertGreaterThanOrEqual(
            Int(lipAfter[0]) - Int(lipAfter[1]), Int(lipBefore[0]) - Int(lipBefore[1]) + 10, "입술 채도가 오른다")
        for point in [SyntheticFace.mouth, SyntheticFace.philtrum, SyntheticFace.scleraPoint] {
            XCTAssertEqual(after.rgba(point), before.rgba(point), "입술 마스크 밖 \(point)")
        }
    }

    func testOutOfRangeFeatureValuesRenderLikeClampedValues() throws {
        let synthetic = SyntheticFace.makeFeatures()
        func rendered(_ features: FeatureAdjustments) throws -> [UInt8] {
            try Support.bytes(output(synthetic, features))
        }
        XCTAssertEqual(
            try rendered(FeatureAdjustments(eyeBrighten: 3, teethWhiten: 9)),
            try rendered(FeatureAdjustments(eyeBrighten: 1, teethWhiten: 1)))
        XCTAssertEqual(try rendered(FeatureAdjustments(lipVitality: -0.5)), try Support.bytes(synthetic.image), "음수는 0")
    }

    func testMissingLandmarksSkipOnlyTheirFeature() throws {
        let boxOnly = SyntheticFace.make(landmarks: false)
        let all = FeatureAdjustments(eyeBrighten: 1, teethWhiten: 1, lipVitality: 1)
        XCTAssertEqual(try Support.bytes(output(boxOnly, all)), try Support.bytes(boxOnly.image), "특징점 없는 얼굴은 그대로")
        let synthetic = SyntheticFace.makeFeatures()
        let before = try Support.grid(synthetic.image)
        let noInner = try render(
            synthetic, FeatureAdjustments(teethWhiten: 1), face: synthetic.face.removing([.innerLips]))
        XCTAssertEqual(noInner.rgba(SyntheticFace.mouth), before.rgba(SyntheticFace.mouth), "안쪽 입술이 없으면 치아만 건너뛴다")
        let noPupils = try render(
            synthetic, FeatureAdjustments(eyeBrighten: 1), face: synthetic.face.removing([.leftPupil, .rightPupil]))
        XCTAssertGreaterThan(
            noPupils.red(SyntheticFace.scleraPoint), before.red(SyntheticFace.scleraPoint), "동공이 없어도 흰자는 보정한다")
    }
}
```

`RenderPipelineTests.swift`의 `testStageOrderMatters` 안 이름 배열을 다음으로 바꾼다:

```swift
        XCTAssertEqual(
            RenderPipeline.standard.stages.map(\.name),
            ["skin", "feature", "shapeWarp", "localEdit", "geometry", "color", "detail", "look"])
```

- [ ] **Step 2: 실패 확인**

Run: `cd apple && swift test --filter 'FeatureStageTests|RenderPipelineTests'` → 컴파일 실패(`cannot find 'FeatureStage' in scope`).

- [ ] **Step 3: 구현**

`RenderTuning.swift`: Task 3의 `teethRednessRamp` 아래에 추가:

```swift
    /// 눈 또렷하게 1에서 흰자를 흰색 쪽으로 섞는 비율(sRGB 감마 값). sRGB 199 회색 흰자가 약 210이 된다.
    public var eyeWhiteLift: Double = 0.2
    /// 눈 또렷하게 1에서 홍채의 CISharpenLuminance 선명도. 필터 기본값 0.4의 두 배.
    public var eyeIrisSharpen: Double = 0.8
    /// 홍채 선명하게의 반지름. 눈동자 반지름 비율. 미리보기 눈동자 15px에서 1.5px, 원본에서는 비례해 커진다.
    public var eyeIrisSharpenRadiusFraction: Double = 0.1
    /// 치아 미백 1에서 노란기(음의 감마 Cb)를 0 쪽으로 옮기는 비율.
    public var teethYellowRemoval: Double = 0.7
    /// 치아 미백 1에서 흰색 쪽으로 섞는 비율.
    public var teethLift: Double = 0.12
    /// 입술 생기 1에서 Cb·Cr 배율에 더하는 값(1.3배).
    public var lipSaturationMax: Double = 0.3
    /// 입술 생기 1에서 감마 Cr에 더하는 붉은기.
    public var lipRednessMax: Double = 0.02
```

`FeatureKernels.swift`:
1. `struct ToneRule` 아래에 추가:

```swift
/// 감마 YCbCr에서의 색 이동. 기본값은 항등이다.
struct ToneShift: Equatable {
    /// 흰색 쪽으로 섞는 비율.
    var lift: Double = 0
    /// 음의 Cb(노란기)를 0 쪽으로 옮기는 비율.
    var yellowRemoval: Double = 0
    /// Cb·Cr 배율.
    var saturation: Double = 1
    /// Cr에 더하는 값.
    var redness: Double = 0
}
```

2. `private let toneWeight: CIColorKernel?` 아래에 `private let toneShift: CIColorKernel?`를 더하고, `private init()` 안 `toneWeight = …` 뒤에 추가:

```swift
        toneShift = CIColorKernel(
            source: """
                kernel vec4 toneShift(__sample pixel, float lift, float yellowRemoval, float saturation,
                                      float redness) {
                    vec3 rgb = pixel.rgb;
                    float y = dot(rgb, vec3(0.299, 0.587, 0.114));
                    float cb = dot(rgb, vec3(-0.168736, -0.331264, 0.5));
                    float cr = dot(rgb, vec3(0.5, -0.418688, -0.081312));
                    cb = (cb - min(cb, 0.0) * yellowRemoval) * saturation;
                    cr = cr * saturation + redness;
                    vec3 shifted = vec3(y + 1.402 * cr, y - 0.344136 * cb - 0.714136 * cr, y + 1.772 * cb);
                    return vec4(clamp(mix(shifted, vec3(1.0), lift), 0.0, 1.0), pixel.a);
                }
                """)
```

3. `weight(of:rule:extent:)` 아래에 추가:

```swift
    /// image는 작업 색공간(선형) 이미지. 감마로 바꿔 색을 옮기고 선형으로 되돌린다. extent 안만 계산한다.
    func shifted(_ image: CIImage, by shift: ToneShift, extent: CGRect) throws -> CIImage {
        guard let toneShift else { throw MellowError.renderFailed }
        let encoded = image.applyingFilter("CILinearToSRGBToneCurve")
        let arguments: [Any] = [encoded, shift.lift, shift.yellowRemoval, shift.saturation, shift.redness]
        guard let output = toneShift.apply(extent: extent, arguments: arguments) else { throw MellowError.renderFailed }
        return output.applyingFilter("CISRGBToneCurveToLinear")
    }
```

`apple/Sources/MellowRendering/Domain/FeatureStage.swift`:

```swift
import CoreImage
import MellowShared

/// 눈 또렷하게·치아 미백·입술 생기. 대상 얼굴마다 FaceRegions 마스크 안에서만 바꾸고 마스크 밖 픽셀은 그대로 둔다.
/// 색 계산은 FeatureKernels(sRGB 감마 BT.601 YCbCr)가 하고, 마스크 영역(bounds)만 계산한 뒤 원본 위에 합성한다.
/// 값은 AdjustmentRange.unit으로 직접 자른다. 프리셋·일괄 적용 값은 편집 규칙의 클램프를 거치지 않는다.
struct FeatureStage: RenderStage {
    let name = "feature"

    /// 홍채 선명하게 반지름의 하한(픽셀). 이보다 작으면 CISharpenLuminance가 거의 효과가 없다.
    private static let minimumSharpenRadius: CGFloat = 1

    func apply(_ image: CIImage, in context: RenderContext) throws -> CIImage {
        let values = Self.clamped(context.recipe.portrait.features)
        guard values.hasEffect, !context.targetFaces.isEmpty else { return image }
        var result = image
        for face in context.targetFaces {
            result = try brightenEyes(result, face: face, amount: values.eyeBrighten, context: context)
            result = try whitenTeeth(result, face: face, amount: values.teethWhiten, context: context)
            result = try reviveLips(result, face: face, amount: values.lipVitality, context: context)
        }
        return result.cropped(to: context.extent)
    }

    /// 0…1로 자른다. 유한하지 않은 값은 RenderPipeline이 먼저 거절한다.
    static func clamped(_ features: FeatureAdjustments) -> FeatureAdjustments {
        var copy = features
        for key in FeatureKey.allCases {
            copy[key] = AdjustmentRange.clamped(features[key], to: AdjustmentRange.unit)
        }
        return copy
    }

    /// 흰자를 흰색 쪽으로 섞고 눈동자 원 안 휘도를 선명하게 한다.
    private func brightenEyes(_ image: CIImage, face: FaceGeometry, amount: Double, context: RenderContext) throws
        -> CIImage
    {
        let tuning = context.tuning
        let extent = context.extent
        guard amount > 0,
            let eyes = FaceRegions.eyeMask(face: face, extent: extent, tuning: tuning, cache: context.regionMasks)
        else { return image }
        let kernels = FeatureKernels.shared
        let sclera = try kernels.weight(of: image, rule: .sclera(tuning), extent: eyes.bounds)
        let lifted = try kernels.shifted(image, by: ToneShift(lift: tuning.eyeWhiteLift * amount), extent: eyes.bounds)
        let brightened = MaskBuilder.blend(lifted, over: image, mask: Self.product(eyes.image, sclera, extent: extent))
            .cropped(to: extent)
        let largest = FaceRegions.irisCircles(face: face, extent: extent, tuning: tuning).map(\.radius).max()
        guard let largest,
            let iris = FaceRegions.irisMask(face: face, extent: extent, tuning: tuning, cache: context.regionMasks)
        else { return brightened }
        let radius = max(Self.minimumSharpenRadius, largest * CGFloat(tuning.eyeIrisSharpenRadiusFraction))
        let sharpened = brightened.clampedToExtent()
            .applyingFilter(
                "CISharpenLuminance",
                parameters: ["inputSharpness": tuning.eyeIrisSharpen * amount, kCIInputRadiusKey: radius]
            )
            .cropped(to: iris.bounds)
        return MaskBuilder.blend(sharpened, over: brightened, mask: iris.image).cropped(to: extent)
    }

    /// 치아의 노란기를 빼고 흰색 쪽으로 섞는다. 다문 입은 마스크가 없어 건너뛴다.
    private func whitenTeeth(_ image: CIImage, face: FaceGeometry, amount: Double, context: RenderContext) throws
        -> CIImage
    {
        let tuning = context.tuning
        guard amount > 0,
            let teeth = try FaceRegions.teethMask(
                face: face, image: image, extent: context.extent, tuning: tuning, cache: context.regionMasks)
        else { return image }
        let shift = ToneShift(lift: tuning.teethLift * amount, yellowRemoval: tuning.teethYellowRemoval * amount)
        let whitened = try FeatureKernels.shared.shifted(image, by: shift, extent: teeth.bounds)
        return MaskBuilder.blend(whitened, over: image, mask: teeth.image).cropped(to: context.extent)
    }

    /// 입술(바깥 − 안쪽)의 채도를 올리고 붉은기를 조금 더한다.
    private func reviveLips(_ image: CIImage, face: FaceGeometry, amount: Double, context: RenderContext) throws
        -> CIImage
    {
        let tuning = context.tuning
        guard amount > 0,
            let lips = FaceRegions.lipMask(
                face: face, extent: context.extent, tuning: tuning, cache: context.regionMasks)
        else { return image }
        let shift = ToneShift(saturation: 1 + tuning.lipSaturationMax * amount, redness: tuning.lipRednessMax * amount)
        let revived = try FeatureKernels.shared.shifted(image, by: shift, extent: lips.bounds)
        return MaskBuilder.blend(revived, over: image, mask: lips.image).cropped(to: context.extent)
    }

    /// 두 회색 마스크의 곱. b는 bounds 밖이 비어 있을 수 있어 검정 위에 얹는다.
    private static func product(_ a: CIImage, _ b: CIImage, extent: CGRect) -> CIImage {
        let black = CIImage(color: .black).cropped(to: extent)
        let background = b.composited(over: black)
        return a.applyingFilter("CIMultiplyCompositing", parameters: [kCIInputBackgroundImageKey: background])
            .cropped(to: extent)
    }
}
```

`RenderPipeline.swift`의 `standard`:

```swift
    public static let standard = RenderPipeline(stages: [
        SkinStage(), FeatureStage(), ShapeWarpStage(), LocalEditStage(), GeometryStage(), ColorStage(), DetailStage(),
        LookStage(),
    ])
```

- [ ] **Step 4: 통과 확인**

Run: `cd apple && swift test --filter FeatureStageTests` → 7개 PASS. 이어서 `cd apple && swift test` → `Executed 244 tests, with 0 failures`(Shared 37 · Rendering 152 · Library 30 · Export 4 · Editing 21). `testIdentityRecipeLeavesBytesUntouched`·`testPortraitStagesChangeOnlyWhenFacesExist`·`PhotoPipelineTests`는 고치지 않고 통과해야 한다. lint 출력 없음. Mac 앱 테스트 → `Executed 53 tests, with 0 failures`.

- [ ] **Step 5: 커밋**

```bash
git add apple/Sources/MellowRendering apple/Tests/MellowRenderingTests
git commit -m "feat(rendering): 눈 또렷하게·치아 미백·입술 생기 단계 추가

feature 단계가 skin 뒤에서 흰자를 밝히고 홍채를 선명하게, 치아의 노란기를 빼고,
입술 채도를 올린다. 마스크 밖 픽셀은 같은 바이트로 남는다.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 5: 배경 흐림 단계 — BackgroundStage와 분석 실패 시 건너뛰기

**Files:**
- Create: `apple/Sources/MellowRendering/Domain/BackgroundStage.swift`
- Modify: `apple/Sources/MellowRendering/API/RenderTuning.swift` (배경 상수)
- Modify: `apple/Sources/MellowRendering/API/RenderPipeline.swift` (`standard`에 `BackgroundStage`, 주석)
- Test: `apple/Tests/MellowRenderingTests/BackgroundStageTests.swift`, `PhotoPipelineTests.swift`, `RenderPipelineTests.swift`

**Interfaces:**
- Consumes: `RenderContext.personMask`·`PhotoAnalysis(personMask:)`·`PhotoPipeline.init(…personAnalyzer:…)`·`StubPersonAnalyzer`·`RenderingTestSupport.personMask(size:person:)`(Task 2), `MaskBuilder.blend`, `AdjustmentRange`.
- Produces: `struct BackgroundStage: RenderStage`(이름 `"background"`, `static func backgroundMask(_ person: CIImage, extent: CGRect, feather: CGFloat) -> CIImage`). `RenderTuning.backgroundBlurMaxFraction`(0.02), `backgroundMaskFeather`(0.006). `RenderPipeline.standard` = `skin, feature, background, shapeWarp, localEdit, geometry, color, detail, look`.

설계 근거:
- **마스크 크기.** Vision 마스크는 사진 비율과 무관하게 512×384라서 extent에 맞게 가로·세로 배율을 따로 둔다(사진 크기 / 마스크 크기). 미리보기·원본 어느 extent에도 같은 식이다. 키운 뒤 짧은 변 × `backgroundMaskFeather`(1600px 미리보기 짧은 변 1200에서 7.2px, 마스크 한 칸 약 3px의 두 배)로 흐려 계단을 덮고 반전한다(배경 1·사람 0).
- **흐림.** `CIMaskedVariableBlur`(반지름 = 짧은 변 × `backgroundBlurMaxFraction` × 값, 반전 마스크가 반지름 지도)를 `clampedToExtent()` 입력에 적용해 가장자리에 어두운·투명한 띠가 없다. 마지막에 `CIBlendWithMask`(흐린 결과를 원본 위에, 반전 마스크)로 사람 영역(마스크 0)은 원본 바이트 그대로다(측정: 사람 안쪽 다른 픽셀 0개).
- **건너뛰기(스펙 1.4, B 이월 c).** 마스크가 없으면(사람 없음·인물 분석 실패·준비 전 사진) 입력을 그대로 돌려준다. `PhotoPipeline.renderOriginal`은 인물 의존 레시피 때문에 오류를 던지지 않는다(얼굴 의존 레시피의 기존 규칙은 그대로).

- [ ] **Step 1: 실패하는 테스트 작성**

`apple/Tests/MellowRenderingTests/BackgroundStageTests.swift`:

```swift
import CoreImage
import MellowShared
import XCTest

@testable import MellowRendering

final class BackgroundStageTests: XCTestCase {
    typealias Support = RenderingTestSupport

    /// 가로로 긴 사진(256×192)과 정사각형 마스크(64×64). 마스크를 가로 4배·세로 3배로 키워야 맞는다.
    private let extent = CGRect(x: 0, y: 0, width: 256, height: 192)
    /// 마스크 안 사람 사각형(x 24…40, y 16…48) → 사진에서 x 96…160, y 48…144.
    private let mask = RenderingTestSupport.personMask(
        size: CGSize(width: 64, height: 64), person: CGRect(x: 24, y: 16, width: 16, height: 32))

    /// 4px 폭 세로 줄무늬. 흐리면 바뀌고 그대로면 같은 바이트다.
    private func stripes() -> CIImage {
        CIFilter(name: "CIStripesGenerator", parameters: ["inputWidth": 4, "inputSharpness": 1])!.outputImage!
            .cropped(to: extent)
    }

    private func render(_ image: CIImage, blur: Double, personMask: CIImage?) throws -> CIImage {
        var recipe = EditRecipe()
        recipe.background.blur = blur
        let context = RenderContext(
            extent: extent, recipe: recipe, analysis: PhotoAnalysis(personMask: personMask), tuning: RenderTuning())
        return try BackgroundStage().apply(image, in: context)
    }

    func testNoMaskOrZeroBlurReturnsInputBytes() throws {
        let input = stripes()
        XCTAssertEqual(
            try Support.bytes(render(input, blur: 0.5, personMask: nil)), try Support.bytes(input),
            "사람이 없거나 분석이 실패하면 건너뛴다")
        XCTAssertEqual(try Support.bytes(render(input, blur: 0, personMask: mask)), try Support.bytes(input))
    }

    func testBlurChangesBackgroundAndKeepsPersonCoreBytes() throws {
        let input = stripes()
        let before = try Support.grid(input)
        let after = try Support.grid(render(input, blur: 1, personMask: mask))
        for y in stride(from: 64, to: 128, by: 4) {
            for x in stride(from: 112, to: 144, by: 2) {
                let point = CGPoint(x: x, y: y)
                XCTAssertEqual(after.rgba(point), before.rgba(point), "사람 안쪽 \(point)")
            }
        }
        XCTAssertNotEqual(after.rgba(CGPoint(x: 20, y: 20)), before.rgba(CGPoint(x: 20, y: 20)), "배경은 흐려진다")
    }

    func testMaskStretchesSeparatelyAlongEachAxis() throws {
        let input = stripes()
        let before = try Support.grid(input)
        let after = try Support.grid(render(input, blur: 1, personMask: mask))
        // 세로 배율이 3이 아니라 4였다면 사람은 y 64…192가 되어 아래 판정이 뒤바뀐다.
        for point in [CGPoint(x: 128, y: 56), CGPoint(x: 128, y: 136)] {
            XCTAssertEqual(after.rgba(point), before.rgba(point), "사람 안 \(point)")
        }
        XCTAssertNotEqual(after.rgba(CGPoint(x: 129, y: 168)), before.rgba(CGPoint(x: 129, y: 168)), "사람 위 배경")
    }

    func testBlurKeepsOpaqueUntintedEdges() throws {
        let input = CIImage(color: CIColor(red: 0.6, green: 0.5, blue: 0.4)).cropped(to: extent)
        let before = try Support.grid(input)
        let after = try Support.grid(render(input, blur: 1, personMask: mask))
        for point in [CGPoint(x: 0, y: 0), CGPoint(x: 255, y: 191), CGPoint(x: 0, y: 191), CGPoint(x: 128, y: 0)] {
            let expected = before.rgba(point)
            let actual = after.rgba(point)
            XCTAssertEqual(actual[3], 255, "가장자리가 투명해지지 않는다 \(point)")
            for channel in 0..<3 {
                XCTAssertEqual(Int(actual[channel]), Int(expected[channel]), accuracy: 1, "가장자리가 어두워지지 않는다 \(point)")
            }
        }
    }

    func testOutOfRangeBlurRendersLikeClampedValue() throws {
        let input = stripes()
        XCTAssertEqual(
            try Support.bytes(render(input, blur: 4, personMask: mask)),
            try Support.bytes(render(input, blur: 1, personMask: mask)))
        XCTAssertEqual(try Support.bytes(render(input, blur: -1, personMask: mask)), try Support.bytes(input), "음수는 0")
    }
}
```

`PhotoPipelineTests.swift`에서 `writeSolidPNG` 아래에 도우미를 더하고, `testWithoutPersonAnalyzerThereIsNoPerson` 뒤에 테스트 둘을 추가:

```swift
    /// 4px 폭 세로 줄무늬 PNG(256×192). 배경 흐림이 바뀐 것을 바이트로 알 수 있다.
    private func writeStripesPNG() throws -> URL {
        let image = CIFilter(name: "CIStripesGenerator", parameters: ["inputWidth": 4, "inputSharpness": 1])!
            .outputImage!.cropped(to: CGRect(x: 0, y: 0, width: 256, height: 192))
        return try Support.writePNG(image, name: "stripes")
    }
```

```swift
    func testPersonAnalysisFailureSkipsOnlyBackgroundBlur() async throws {
        let url = try writeStripesPNG()
        let id = PhotoID()
        let pipeline = PhotoPipeline(
            analyzer: StubFaceAnalyzer(result: .success([])),
            personAnalyzer: StubPersonAnalyzer(result: .failure(.personAnalysisUnavailable(reason: "test"))),
            tuning: RenderTuning())
        _ = try await pipeline.prepare(id, at: url)
        var colorOnly = EditRecipe()
        colorOnly.color.exposure = 0.2
        var blurred = colorOnly
        blurred.background.blur = 0.6
        let previewBlurred = try await pipeline.preview(id, recipe: blurred)
        let previewColor = try await pipeline.preview(id, recipe: colorOnly)
        XCTAssertEqual(
            Array(previewBlurred.dataProvider!.data! as Data), Array(previewColor.dataProvider!.data! as Data),
            "미리보기는 흐림만 빼고 그린다")
        let original = try await pipeline.renderOriginal(id, at: url, recipe: blurred, maxDimension: nil)
        let originalColor = try await pipeline.renderOriginal(id, at: url, recipe: colorOnly, maxDimension: nil)
        XCTAssertEqual(try Support.bytes(original), try Support.bytes(originalColor), "저장도 오류 없이 흐림만 건너뛴다")
        let unprepared = try await pipeline.renderOriginal(PhotoID(), at: url, recipe: blurred, maxDimension: nil)
        XCTAssertEqual(unprepared.extent.size, CGSize(width: 256, height: 192), "준비 전 사진도 흐림 때문에 저장을 막지 않는다")
    }

    func testOriginalRenderScalesPreviewMaskToOutputSize() async throws {
        let url = try writeStripesPNG()
        let id = PhotoID()
        let mask = Support.personMask(
            size: CGSize(width: 64, height: 64), person: CGRect(x: 24, y: 16, width: 16, height: 32))
        let pipeline = PhotoPipeline(
            analyzer: StubFaceAnalyzer(result: .success([])),
            personAnalyzer: StubPersonAnalyzer(result: .success(mask)), tuning: RenderTuning())
        _ = try await pipeline.prepare(id, at: url)
        var plain = EditRecipe()
        plain.color.exposure = 0.2
        var blurred = plain
        blurred.background.blur = 1
        let sharpImage = try await pipeline.renderOriginal(id, at: url, recipe: plain, maxDimension: 128)
        let softImage = try await pipeline.renderOriginal(id, at: url, recipe: blurred, maxDimension: 128)
        XCTAssertEqual(softImage.extent.size, CGSize(width: 128, height: 96))
        let sharp = try Support.grid(sharpImage)
        let soft = try Support.grid(softImage)
        // 128×96 출력에서 사람은 x 48…80, y 24…72다.
        XCTAssertEqual(soft.rgba(CGPoint(x: 64, y: 48)), sharp.rgba(CGPoint(x: 64, y: 48)), "작은 출력에서도 사람 가운데는 그대로")
        XCTAssertNotEqual(soft.rgba(CGPoint(x: 10, y: 10)), sharp.rgba(CGPoint(x: 10, y: 10)), "배경은 흐려진다")
    }
```

`RenderPipelineTests.swift`의 `testStageOrderMatters` 이름 배열을 다음으로 바꾼다:

```swift
        XCTAssertEqual(
            RenderPipeline.standard.stages.map(\.name),
            ["skin", "feature", "background", "shapeWarp", "localEdit", "geometry", "color", "detail", "look"])
```

- [ ] **Step 2: 실패 확인**

Run: `cd apple && swift test --filter 'BackgroundStageTests|PhotoPipelineTests|RenderPipelineTests'` → 컴파일 실패(`cannot find 'BackgroundStage' in scope`).

- [ ] **Step 3: 구현**

`RenderTuning.swift`: Task 4의 `lipRednessMax` 아래에 추가:

```swift
    /// 배경 흐림 1의 반지름. 짧은 변 비율. 미리보기(짧은 변 1200)에서 24px, 1200만 화소 원본(짧은 변 3024)에서 60px.
    public var backgroundBlurMaxFraction: Double = 0.02
    /// 인물 마스크를 키운 뒤 흐리는 반지름. 짧은 변 비율. 512×384 마스크 한 칸(1600px 미리보기에서 약 3px)의 두 배를 넘겨 계단을 덮는다.
    public var backgroundMaskFeather: Double = 0.006
```

`apple/Sources/MellowRendering/Domain/BackgroundStage.swift`:

```swift
import CoreImage
import MellowShared

/// 인물 마스크 밖을 흐린다. 마스크를 extent로 키우고 짧은 변 × backgroundMaskFeather로 부드럽게 한 뒤 반전해
/// CIMaskedVariableBlur의 반지름 지도로 쓰고, 같은 마스크로 원본 위에 합성해 사람 영역(반전 마스크 0)은 원본 바이트로 둔다.
/// 마스크가 없으면(사람 없음·인물 분석 실패·준비 전) 입력을 그대로 돌려준다(스펙 1.4: 해당 단계만 건너뜀).
struct BackgroundStage: RenderStage {
    let name = "background"

    func apply(_ image: CIImage, in context: RenderContext) throws -> CIImage {
        let amount = AdjustmentRange.clamped(context.recipe.background.blur, to: AdjustmentRange.unit)
        guard amount > 0, let person = context.personMask, !person.extent.isEmpty, !person.extent.isInfinite else {
            return image
        }
        let extent = context.extent
        let tuning = context.tuning
        let feather = max(
            CGFloat(tuning.skinBlurMinimumRadius), context.shortSide * CGFloat(tuning.backgroundMaskFeather))
        let background = Self.backgroundMask(person, extent: extent, feather: feather)
        let radius = Double(context.shortSide) * tuning.backgroundBlurMaxFraction * amount
        let blurred = image.clampedToExtent()
            .applyingFilter("CIMaskedVariableBlur", parameters: ["inputMask": background, kCIInputRadiusKey: radius])
            .cropped(to: extent)
        return MaskBuilder.blend(blurred, over: image, mask: background).cropped(to: extent)
    }

    /// 배경 1·사람 0인 extent 크기 마스크. 인물 마스크(사람 1)를 extent에 맞게 가로·세로 따로 키운다(마스크 비율은 사진과 다를 수 있다).
    static func backgroundMask(_ person: CIImage, extent: CGRect, feather: CGFloat) -> CIImage {
        let source = person.extent
        let placement = CGAffineTransform(translationX: extent.minX, y: extent.minY)
            .scaledBy(x: extent.width / source.width, y: extent.height / source.height)
            .translatedBy(x: -source.minX, y: -source.minY)
        return person.transformed(by: placement).clampedToExtent()
            .applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: feather])
            .applyingFilter("CIColorInvert")
            .cropped(to: extent)
    }
}
```

`RenderPipeline.swift`의 `standard`와 그 위 주석:

```swift
    /// 자동 보정이 기반이 되고 수동 편집이 그 위에, 기하가 출력 화면을 정하고, 색감은 마지막에.
    /// 좌표·마스크 기반 단계(피부·눈입·배경·얼굴형·수동 편집)는 기하 앞이라 원본 좌표를 쓰고, 비네팅·선명도는 기하 뒤라 잘린 화면을 따른다.
    public static let standard = RenderPipeline(stages: [
        SkinStage(), FeatureStage(), BackgroundStage(), ShapeWarpStage(), LocalEditStage(), GeometryStage(),
        ColorStage(), DetailStage(), LookStage(),
    ])
```

- [ ] **Step 4: 통과 확인**

Run: `cd apple && swift test --filter 'BackgroundStageTests|PhotoPipelineTests'` → 모두 PASS. 이어서 `cd apple && swift test` → `Executed 251 tests, with 0 failures`(Shared 37 · Rendering 159 · Library 30 · Export 4 · Editing 21). lint 출력 없음. Mac 앱 테스트 → `Executed 53 tests, with 0 failures`.

- [ ] **Step 5: 커밋**

```bash
git add apple/Sources/MellowRendering apple/Tests/MellowRenderingTests
git commit -m "feat(rendering): 인물 마스크 기반 배경 흐림 단계 추가

background 단계가 인물 마스크를 사진 크기로 키워 반전한 반지름 지도로
CIMaskedVariableBlur를 적용한다. 마스크가 없으면 이 단계만 건너뛴다.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 6: 편집 변경과 자동 보정 — EditChange.feature·backgroundBlur, 눈 또렷하게 0.2

**Files:**
- Modify: `apple/Sources/MellowEditing/API/EditChange.swift`
- Modify: `apple/Sources/MellowEditing/API/EditDocument.swift` (`set`의 switch)
- Modify: `apple/Sources/MellowRendering/API/AutoEnhancer.swift`
- Modify: `apple/Sources/MellowRendering/API/RenderTuning.swift` (`autoEyeBrighten`)
- Test: `apple/Tests/MellowEditingTests/EditDocumentTests.swift`, `apple/Tests/MellowRenderingTests/AutoEnhancerTests.swift`

**Interfaces:**
- Consumes: `FeatureKey`, `FeatureAdjustments` 첨자, `EditingPolicy.unitRange`·`clamped(_:to:)`, `EditDocument.applyAuto`(이미 `portrait.features`를 복사), `PresetValues`(이미 `portrait`·`background`를 담음).
- Produces: `EditChange.feature(FeatureKey, Double)`, `EditChange.backgroundBlur(Double)`(둘 다 `affectsGeometry == false`, 0…1로 자름). `RenderTuning.autoEyeBrighten`(0.2). `AutoEnhancer.suggestion(for:hasFaces:)`가 얼굴이 있으면 `portrait.features.eyeBrighten = autoEyeBrighten`.

확인한 기존 동작: B Task 1·2가 이미 `PresetValues`에 `background`를 넣고 `EditDocument.merged`가 `portrait`(눈·입 포함)과 `background`를 복사한다. `applyAuto`는 `portrait.features`를 복사한다. 그래서 이 Task는 그 동작을 테스트로 고정만 한다. 눈·입·배경은 색만 바꾸므로 수동 편집 잠금 대상이 아니다.

- [ ] **Step 1: 실패하는 테스트 작성**

`EditDocumentTests.swift`의 `testEditingPolicyForwardsSharedRanges` 뒤에 추가:

```swift
    func testFeatureAndBackgroundChangesClampAndStayUnlocked() {
        var document = EditDocument()
        document.appendLocalEdit(.spot(RetouchSpot(x: 0.5, y: 0.4, sourceX: 0.4, sourceY: 0.4, radius: 0.02)))
        XCTAssertNil(document.set(.feature(.eyeBrighten, 0.4)), "색만 바꾸므로 수동 편집이 있어도 잠기지 않는다")
        XCTAssertNil(document.set(.feature(.teethWhiten, 1.7)))
        XCTAssertNil(document.set(.feature(.lipVitality, -0.2)))
        XCTAssertNil(document.set(.backgroundBlur(2)))
        XCTAssertEqual(
            document.recipe.portrait.features, FeatureAdjustments(eyeBrighten: 0.4, teethWhiten: 1, lipVitality: 0))
        XCTAssertEqual(document.recipe.background.blur, 1)
        XCTAssertFalse(EditChange.feature(.eyeBrighten, 0.5).affectsGeometry)
        XCTAssertFalse(EditChange.backgroundBlur(0.5).affectsGeometry)
        document.undo()
        XCTAssertEqual(document.recipe.background.blur, 0, "변경마다 실행 취소 한 단계")
        XCTAssertEqual(document.recipe.portrait.features.teethWhiten, 1)
    }

    func testPresetAndBatchCarryFeaturesAndBackground() {
        let values = PresetValues(
            portrait: PortraitAdjustments(features: FeatureAdjustments(eyeBrighten: 0.3, lipVitality: 0.2)),
            background: BackgroundAdjustments(blur: 0.5))
        var preset = EditDocument()
        preset.apply(values)
        var locked = EditDocument()
        locked.appendLocalEdit(.warp(WarpStroke(x: 0.5, y: 0.5, dx: 0.01, dy: 0, radius: 0.1)))
        locked.applyFromBatch(values)
        for document in [preset, locked] {
            XCTAssertEqual(document.recipe.portrait.features, FeatureAdjustments(eyeBrighten: 0.3, lipVitality: 0.2))
            XCTAssertEqual(document.recipe.background.blur, 0.5, "잠긴 사진도 색 보정은 복사한다")
        }
    }
```

`AutoEnhancerTests.swift`의 `testFacesAddPortraitValues`에서 `XCTAssertNil(withFaces.targetFace)` 위에 추가:

```swift
        XCTAssertEqual(
            withFaces.features, FeatureAdjustments(eyeBrighten: RenderTuning().autoEyeBrighten),
            "얼굴이 있으면 눈 또렷하게만 제안한다(스펙 7)")
```

- [ ] **Step 2: 실패 확인**

Run: `cd apple && swift test --filter 'EditDocumentTests|AutoEnhancerTests'` → 컴파일 실패(`type 'EditChange' has no member 'feature'`, `value of type 'RenderTuning' has no member 'autoEyeBrighten'`).

- [ ] **Step 3: 구현**

`EditChange.swift`: `case targetFace(Int?)` 아래에 추가:

```swift
    case feature(FeatureKey, Double)
    case backgroundBlur(Double)
```

`affectsGeometry`의 문서 주석은 그대로 둔다(새 두 case는 `default`로 false).

`EditDocument.swift`의 `set` switch에서 `case .targetFace(let index): …` 아래에 추가:

```swift
        case .feature(let key, let value):
            updated.portrait.features[key] = EditingPolicy.clamped(value, to: EditingPolicy.unitRange)
        case .backgroundBlur(let value):
            updated.background.blur = EditingPolicy.clamped(value, to: EditingPolicy.unitRange)
```

`RenderTuning.swift`: `public var autoSkinSmoothing: Double = 0.3` 아래에 추가:

```swift
    /// 얼굴이 있을 때 자동 보정이 제안하는 눈 또렷하게(스펙 7).
    public var autoEyeBrighten: Double = 0.2
```

`AutoEnhancer.swift`의 `if hasFaces { … }` 블록:

```swift
        if hasFaces {
            portrait.skin = SkinAdjustments(smoothing: tuning.autoSkinSmoothing, autoBlemish: true)
            portrait.features = FeatureAdjustments(eyeBrighten: tuning.autoEyeBrighten)
        }
```

- [ ] **Step 4: 통과 확인**

Run: `cd apple && swift test` → `Executed 253 tests, with 0 failures`(Shared 37 · Rendering 159 · Library 30 · Export 4 · Editing 23). lint 출력 없음. Mac 앱 테스트 → `Executed 53 tests, with 0 failures`(`testAutoEnhanceWithFaceTurnsOnAutoBlemishAndKeepsFaceWidth`는 피부 값만 단언하므로 그대로 통과한다).

- [ ] **Step 5: 커밋**

```bash
git add apple/Sources/MellowEditing/API/EditChange.swift apple/Sources/MellowEditing/API/EditDocument.swift apple/Sources/MellowRendering/API/AutoEnhancer.swift apple/Sources/MellowRendering/API/RenderTuning.swift apple/Tests/MellowEditingTests/EditDocumentTests.swift apple/Tests/MellowRenderingTests/AutoEnhancerTests.swift
git commit -m "feat(editing): 눈·입·배경 흐림 편집 변경과 자동 보정 눈 또렷하게 추가

feature·backgroundBlur 변경은 0…1로 자르고 수동 편집이 있어도 잠기지 않는다.
자동 보정은 얼굴이 있으면 눈 또렷하게 0.2를 제안한다.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 7: 앱 — 뷰티 눈·입 탭

**Files:**
- Modify: `apple/MellowPhoto/Application/BeautyTab.swift`
- Modify: `apple/MellowPhoto/Features/Editor/BeautyPanel.swift`
- Modify: `apple/MellowPhoto/Application/UserMessage.swift`
- Test: `apple/MellowPhotoTests/AppModelTests.swift`

**Interfaces:**
- Consumes: `EditChange.feature(_:_:)`(Task 6), `EditingPolicy.unitRange`, `FeatureKey.allCases`, `AdjustmentSlider(title:value:range:change:)`, `AppModel.beautyTab`, `RenderTuning.autoEyeBrighten`(Task 6), `FeatureStage`(Task 4, 미리보기 경유).
- Produces: `BeautyTab.features`(제목 "눈·입"). `UserMessage.beautyTabFeatures`, `UserMessage.featureTitle(_ key: FeatureKey) -> String`(눈 또렷하게·치아 미백·입술 생기), `UserMessage.featureHint`. 앱 파일 추가·삭제 없음(xcodegen 불필요).

- [ ] **Step 1: 실패하는 테스트 작성**

`AppModelTests.swift` 맨 아래(`testGeometryLockRejectsEveryFaceShapeKey` 뒤)에 추가:

```swift
    func testFeaturesTabEditsEachKeyAndIsNotLockedByLocalEdits() async throws {
        let staged = try TestSupport.solidPNG(in: root)
        let model = TestSupport.makeModel(
            root: root, importer: FakeImporter(staged: [.success(StagedPhoto(url: staged, displayName: nil))]))
        try await importOne(model, staged)
        XCTAssertEqual(BeautyTab.allCases, [.skin, .face, .features])
        XCTAssertEqual(BeautyTab.features.title, "눈·입")
        model.tool = .retouch
        model.touch(from: NormalizedPoint(x: 0.3, y: 0.3), to: NormalizedPoint(x: 0.3, y: 0.3))
        model.touch(from: NormalizedPoint(x: 0.5, y: 0.5), to: NormalizedPoint(x: 0.5, y: 0.5))
        try await waitUntil { !model.isRendering }
        XCTAssertTrue(model.isGeometryLocked)
        model.selectTool(.beauty)
        model.beautyTab = .features
        for key in FeatureKey.allCases {
            model.beginSliderEdit()
            model.edit(.feature(key, 0.3))
            model.edit(.feature(key, 0.6))
            model.endSliderEdit()
        }
        for key in FeatureKey.allCases {
            XCTAssertEqual(model.currentRecipe.portrait.features[key], 0.6, accuracy: 1e-9, "\(key)는 잠기지 않는다")
        }
        XCTAssertEqual(FeatureKey.allCases.map(UserMessage.featureTitle), ["눈 또렷하게", "치아 미백", "입술 생기"])
        model.undo()
        XCTAssertEqual(model.currentRecipe.portrait.features.lipVitality, 0, "실행 취소 한 번에 마지막 슬라이더만")
        XCTAssertEqual(model.currentRecipe.portrait.features.teethWhiten, 0.6, accuracy: 1e-9)
    }
```

같은 파일 `testAutoEnhanceWithFaceTurnsOnAutoBlemishAndKeepsFaceWidth`의 마지막 단언 뒤에 추가:

```swift
        XCTAssertEqual(
            model.currentRecipe.portrait.features.eyeBrighten, RenderTuning().autoEyeBrighten, "자동 보정은 눈 또렷하게를 켠다")
```

- [ ] **Step 2: 실패 확인**

Run: `xcodebuild -project apple/MellowPhoto.xcodeproj -scheme MellowPhoto -derivedDataPath apple/build -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO build-for-testing 2>&1 | grep -c "error:"` → 0보다 큼(`BeautyTab`에 `features` 없음, `featureTitle` 없음).

- [ ] **Step 3: 구현**

`BeautyTab.swift` 전체:

```swift
/// 뷰티 도구의 하위 탭.
enum BeautyTab: CaseIterable, Identifiable {
    case skin
    case face
    case features

    var id: Self { self }

    var title: String {
        switch self {
        case .skin: return UserMessage.beautyTabSkin
        case .face: return UserMessage.beautyTabFace
        case .features: return UserMessage.beautyTabFeatures
        }
    }
}
```

`UserMessage.swift`: `static let beautyTabFace = "얼굴"` 아래에 `static let beautyTabFeatures = "눈·입"`을, `static let faceHint = …` 아래에 다음을 더한다:

```swift
    static let featureHint = "치아 미백은 치아가 보이는 사진에서만 바뀌어요. 눈·입 보정은 얼굴 특징점을 찾은 얼굴에 적용돼요."
```

함수 묶음(`faceShapeTitle` 아래)에 추가:

```swift
    /// 뷰티 › 눈·입 탭 슬라이더 이름. 화면 순서는 FeatureKey.allCases.
    static func featureTitle(_ key: FeatureKey) -> String {
        switch key {
        case .eyeBrighten: return "눈 또렷하게"
        case .teethWhiten: return "치아 미백"
        case .lipVitality: return "입술 생기"
        }
    }
```

`BeautyPanel.swift`: `body`의 탭 switch를 다음으로 바꾸고,

```swift
            switch model.beautyTab {
            case .skin: skinControls(recipe.portrait.skin)
            case .face: faceControls(recipe.portrait.face)
            case .features: featureControls(recipe.portrait.features)
            }
```

`faceControls` 아래에 추가:

```swift
    /// 눈 또렷하게·치아 미백·입술 생기 0…1. 색만 바꾸므로 수동 편집이 있어도 잠기지 않는다.
    @ViewBuilder
    private func featureControls(_ features: FeatureAdjustments) -> some View {
        ForEach(FeatureKey.allCases, id: \.self) { key in
            AdjustmentSlider(
                title: UserMessage.featureTitle(key), value: features[key], range: EditingPolicy.unitRange
            ) { .feature(key, $0) }
        }
        Text(UserMessage.featureHint).font(.caption).foregroundStyle(.secondary)
    }
```

- [ ] **Step 4: 통과 확인**

Run: Mac 앱 테스트 → `Executed 54 tests, with 0 failures`. `cd apple && swift test` → `Executed 253 tests, with 0 failures`. lint 출력 없음. `./scripts/verify-modules.sh` 통과. iOS 시뮬레이터 테스트는 돌리지 않는다(Task 9).

- [ ] **Step 5: 커밋**

```bash
git add apple/MellowPhoto/Application/BeautyTab.swift apple/MellowPhoto/Features/Editor/BeautyPanel.swift apple/MellowPhoto/Application/UserMessage.swift apple/MellowPhotoTests/AppModelTests.swift
git commit -m "feat(app): 뷰티 눈·입 탭에 슬라이더 3개 추가

눈 또렷하게·치아 미백·입술 생기를 0…1로 둔다. 색만 바꾸므로 수동 편집이 있어도
잠기지 않는다. 자동 보정의 눈 또렷하게 값을 앱 테스트로 확인한다.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 8: 앱 — 배경 도구, 사람 없음·분석 실패 안내, Vision 인물 분석 연결, D 시나리오

**Files:**
- Create: `apple/MellowPhoto/Features/Editor/BackgroundPanel.swift`
- Modify: `apple/MellowPhoto/Application/EditorTool.swift`
- Modify: `apple/MellowPhoto/Application/AppModel.swift` (`PhotoInfo`, `BackgroundAvailability`, `remember`)
- Modify: `apple/MellowPhoto/Application/AppModel+Editing.swift` (`touch` switch)
- Modify: `apple/MellowPhoto/Application/UserMessage.swift`
- Modify: `apple/MellowPhoto/Features/Editor/ToolStrip.swift`
- Modify: `apple/MellowPhoto/Features/Editor/EditorScene.swift` (`toolPanel`)
- Modify: `apple/MellowPhoto/Platform/AppModel+Live.swift`
- Modify: `apple/MellowPhoto.xcodeproj` (`xcodegen generate` 결과)
- Modify: `apple/MellowPhotoTests/TestSupport.swift` (`StubPersonAnalyzer`, `personMask(_:)`, `makeModel` 인자)
- Test: `apple/MellowPhotoTests/AppModelTests.swift`, `apple/MellowPhotoTests/EditorScenarioTests.swift`

**Interfaces:**
- Consumes: `PersonAnalyzer`·`VisionPersonAnalyzer`·`PreparedPhoto.hasPerson`·`personAnalysisFailure`·`PhotoPipeline.init(…personAnalyzer:…)`·`MellowError.personAnalysisUnavailable`(Task 2), `BackgroundStage`(Task 5, 미리보기 경유), `EditChange.backgroundBlur`·`feature`(Task 6), `BeautyTab.features`(Task 7), `TestSupport.landmarkedFace(in:)`.
- Produces: `EditorTool.background`(제목 "배경", 기호 `camera.aperture`). `struct BackgroundPanel: View`. `AppModel.PhotoInfo.hasPerson: Bool`(기본 false), `AppModel.PhotoInfo.personAnalysisFailure: MellowError?`. `enum AppModel.BackgroundAvailability: Equatable { case ready, noPerson, unavailable(MellowError) }`, `AppModel.backgroundAvailability`. `UserMessage.toolBackground`, `backgroundBlur`, `backgroundHint`, `noPersonDetected`, `noPersonHint`, `personAnalysisUnavailableTitle`. 테스트 지원: `StubPersonAnalyzer`(`result: Result<CIImage?, MellowError> = .success(nil)`), `TestSupport.personMaskSide`, `TestSupport.personMask(_ person: NormalizedRect) -> CIImage`, `TestSupport.makeModel(root:maxPhotos:analyzer:personAnalyzer:importer:store:)`.

설계 근거: 도구 줄은 `필터 · 자동 · 자르기 · 조정 · 뷰티 · 배경 · 잡티 · 변형`(E·F가 체형·메이크업을 뷰티와 배경 사이에 넣어 스펙 7의 순서가 된다). 사람이 없거나 분석이 실패하면 안내를 위에 보이고 슬라이더는 값이 보이게 끈다(프리셋·일괄 적용으로 들어온 값 확인). 인물 분석 실패는 가져오기 경고에 넣지 않는다(`ImportPhotos`는 그대로). 분석 실패가 사람 없음보다 먼저다.

- [ ] **Step 1: 테스트 지원 코드**

`TestSupport.swift`의 `struct StubFaceAnalyzer` 아래에 추가:

```swift
struct StubPersonAnalyzer: PersonAnalyzer {
    var result: Result<CIImage?, MellowError> = .success(nil)
    func personMask(_ image: CIImage) throws -> CIImage? { try result.get() }
}
```

`enum TestSupport` 안, `landmarkedFace(in:)` 아래에 추가:

```swift
    /// 스텁 인물 마스크의 한 변(픽셀). Vision 마스크처럼 사진과 크기·비율이 다르다.
    static let personMaskSide = 64.0

    /// 검은 바탕에 흰 사각형 사람이 있는 정사각형 인물 마스크. person은 정규화 사각형(원점 왼쪽 아래).
    static func personMask(_ person: NormalizedRect) -> CIImage {
        let extent = CGRect(x: 0, y: 0, width: personMaskSide, height: personMaskSide)
        let rect = CGRect(
            x: person.x * personMaskSide, y: person.y * personMaskSide, width: person.width * personMaskSide,
            height: person.height * personMaskSide)
        return CIImage(color: .white).cropped(to: rect).composited(over: CIImage(color: .black)).cropped(to: extent)
    }
```

`makeModel` 전체:

```swift
    @MainActor
    static func makeModel(
        root: URL, maxPhotos: Int = 40, analyzer: StubFaceAnalyzer = StubFaceAnalyzer(),
        personAnalyzer: StubPersonAnalyzer = StubPersonAnalyzer(), importer: FakeImporter = FakeImporter(),
        store: MemorySessionStore = MemorySessionStore()
    ) -> AppModel {
        let copies = WorkingCopyStore(directory: root.appendingPathComponent("Library"))
        try? copies.prepareDirectory()
        let catalog = (try? sharedLookCatalog()) ?? .empty
        return AppModel(
            session: ProjectSession(store: store, maxPhotos: maxPhotos),
            pipeline: PhotoPipeline(
                analyzer: analyzer, personAnalyzer: personAnalyzer, tuning: RenderTuning(), lookCatalog: catalog),
            copies: copies,
            importer: importer,
            exporter: Exporter(renderer: Renderer()),
            lookCatalog: catalog,
            renderDebounce: .milliseconds(10))
    }
```

- [ ] **Step 2: 실패하는 테스트 작성**

`AppModelTests.swift` 맨 아래(`testFeaturesTabEditsEachKeyAndIsNotLockedByLocalEdits` 뒤)에 추가:

```swift
    func testBackgroundToolEditsBlurOneUndoStepWhenPersonFound() async throws {
        let staged = try TestSupport.solidPNG(in: root)
        let mask = TestSupport.personMask(NormalizedRect(x: 0.3, y: 0, width: 0.4, height: 0.8))
        let model = TestSupport.makeModel(
            root: root, personAnalyzer: StubPersonAnalyzer(result: .success(mask)),
            importer: FakeImporter(staged: [.success(StagedPhoto(url: staged, displayName: nil))]))
        try await importOne(model, staged)
        model.selectTool(.background)
        XCTAssertEqual(EditorTool.background.title, "배경")
        XCTAssertEqual(model.backgroundAvailability, .ready)
        model.beginSliderEdit()
        model.edit(.backgroundBlur(0.3))
        model.edit(.backgroundBlur(0.5))
        model.endSliderEdit()
        XCTAssertEqual(model.currentRecipe.background.blur, 0.5, accuracy: 1e-9)
        try await waitUntil { !model.isRendering }
        XCTAssertNil(model.presentedError)
        model.undo()
        XCTAssertEqual(model.currentRecipe.background.blur, 0, "드래그 한 번이 실행 취소 한 단계")
    }

    func testBackgroundToolReportsNoPersonAndAnalysisFailureWithoutBlockingRender() async throws {
        let staged = try TestSupport.solidPNG(in: root)
        let empty = TestSupport.makeModel(
            root: root, importer: FakeImporter(staged: [.success(StagedPhoto(url: staged, displayName: nil))]))
        try await importOne(empty, staged)
        XCTAssertEqual(empty.backgroundAvailability, .noPerson)

        let otherRoot = try TestSupport.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: otherRoot) }
        let otherStaged = try TestSupport.solidPNG(in: otherRoot)
        let failure = MellowError.personAnalysisUnavailable(reason: "test")
        let failing = TestSupport.makeModel(
            root: otherRoot, personAnalyzer: StubPersonAnalyzer(result: .failure(failure)),
            importer: FakeImporter(staged: [.success(StagedPhoto(url: otherStaged, displayName: nil))]))
        try await importOne(failing, otherStaged)
        XCTAssertNil(failing.presentedError, "인물 분석 실패는 가져오기 경고로 띄우지 않는다")
        XCTAssertEqual(failing.backgroundAvailability, .unavailable(failure))
        failing.edit(.backgroundBlur(0.5))
        try await waitUntil { !failing.isRendering }
        XCTAssertEqual(failing.currentRecipe.background.blur, 0.5, "값은 저장된다")
        XCTAssertNil(failing.presentedError, "렌더는 흐림만 건너뛰고 오류를 띄우지 않는다")
    }
```

`EditorScenarioTests.swift`: `demoFace` 아래에 스텁 마스크를 더하고, `testBeautySkinThenFaceShapeThenExportSucceeds` 전체를 다음으로 바꾼다(스펙 8 시나리오의 D 단계).

```swift
    /// 공용 픽스처에서 사람이 있는 영역을 어림한 스텁 인물 마스크. 얼굴과 어깨를 덮는다.
    private static let demoPersonMask = TestSupport.personMask(NormalizedRect(x: 0.2, y: 0, width: 0.65, height: 0.85))
```

```swift
    func testBeautySkinFaceFeaturesThenBackgroundThenExportSucceeds() async throws {
        let model = TestSupport.makeModel(
            root: root, analyzer: StubFaceAnalyzer(result: .success([Self.demoFace])),
            personAnalyzer: StubPersonAnalyzer(result: .success(Self.demoPersonMask)),
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

        let recipe = model.currentRecipe
        XCTAssertEqual(recipe.portrait.skin, SkinAdjustments(smoothing: 0.5, autoBlemish: true))
        XCTAssertEqual(recipe.portrait.face, FaceShapeAdjustments(width: -0.5, eyeSize: 0.3, smile: 0.4))
        XCTAssertEqual(recipe.portrait.features, FeatureAdjustments(eyeBrighten: 0.5))
        XCTAssertEqual(recipe.background.blur, 0.5, accuracy: 1e-9)
        let size = try await exportedPixelSize(model)
        XCTAssertEqual(size.width, size.height, "정사각형 원본이 그대로 저장된다")
    }
```

- [ ] **Step 3: 실패 확인**

Run: `xcodebuild -project apple/MellowPhoto.xcodeproj -scheme MellowPhoto -derivedDataPath apple/build -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO build-for-testing 2>&1 | grep -c "error:"` → 0보다 큼(`EditorTool`에 `background` 없음, `backgroundAvailability` 없음).

- [ ] **Step 4: 구현**

`UserMessage.swift`: `static let toolBeauty = "뷰티"` 아래에 추가:

```swift
    static let toolBackground = "배경"
    static let backgroundBlur = "배경 흐림"
    static let backgroundHint = "사람은 그대로 두고 뒤 배경만 흐려요."
    static let noPersonDetected = "사진에서 사람을 찾지 못했어요"
    static let noPersonHint = "배경 흐림은 사람이 보이는 사진에서 동작해요."
    static let personAnalysisUnavailableTitle = "인물 영역 분석을 사용할 수 없어요"
```

`EditorTool.swift` 전체:

```swift
enum EditorTool: CaseIterable, Identifiable {
    case look
    case crop
    case adjust
    case beauty
    case background
    case retouch
    case warp

    var id: Self { self }

    /// 화면에 보이는 도구 이름. 문구는 UserMessage에 둔다.
    var title: String {
        switch self {
        case .look: return UserMessage.toolLook
        case .crop: return UserMessage.toolCrop
        case .adjust: return UserMessage.toolAdjust
        case .beauty: return UserMessage.toolBeauty
        case .background: return UserMessage.toolBackground
        case .retouch: return UserMessage.toolRetouch
        case .warp: return UserMessage.toolWarp
        }
    }

    var symbol: String {
        switch self {
        case .look: return "camera.filters"
        case .crop: return "crop.rotate"
        case .adjust: return "slider.horizontal.3"
        case .beauty: return "face.smiling"
        case .background: return "camera.aperture"
        case .retouch: return "bandage"
        case .warp: return "arrow.up.left.and.arrow.down.right"
        }
    }

    var usesCanvasTouch: Bool { self == .retouch || self == .warp }
}
```

`AppModel.swift`:
1. `struct PhotoInfo`를 다음으로 바꾸고 바로 아래에 `BackgroundAvailability`를 더한다:

```swift
    struct PhotoInfo {
        var pixelSize: CGSize
        var faces: [FaceGeometry]
        var faceAnalysisFailure: MellowError?
        /// 인물 마스크가 있는지. 배경 도구 안내에 쓴다.
        var hasPerson = false
        /// 인물 분석이 실패했으면 그 이유. 사람이 없는 것과 구분한다.
        var personAnalysisFailure: MellowError?
    }

    /// 배경 도구가 보여줄 상태. 분석 실패가 사람 없음보다 먼저다.
    enum BackgroundAvailability: Equatable {
        case ready
        case noPerson
        case unavailable(MellowError)
    }
```

2. `var faces: [FaceGeometry] { … }` 아래에 추가:

```swift
    /// 선택 사진의 배경 도구 상태.
    var backgroundAvailability: BackgroundAvailability {
        if let failure = selectedInfo?.personAnalysisFailure {
            return .unavailable(failure)
        }
        return selectedInfo?.hasPerson == true ? .ready : .noPerson
    }
```

3. `remember(_:_:)`:

```swift
    func remember(_ id: PhotoID, _ prepared: PreparedPhoto) {
        thumbnails[id] = prepared.thumbnail
        photoInfo[id] = PhotoInfo(
            pixelSize: prepared.pixelSize, faces: prepared.faces, faceAnalysisFailure: prepared.faceAnalysisFailure,
            hasPerson: prepared.hasPerson, personAnalysisFailure: prepared.personAnalysisFailure)
    }
```

`AppModel+Editing.swift`의 `touch` switch 마지막 case:

```swift
        case .look, .crop, .adjust, .beauty, .background:
            return
```

`ToolStrip.swift`의 도구 목록:

```swift
                ForEach([EditorTool.crop, .adjust, .beauty, .background, .retouch, .warp]) { toolButton($0) }
```

`EditorScene.swift`의 `toolPanel` switch에 `case .beauty: BeautyPanel()` 아래 한 줄:

```swift
        case .background: BackgroundPanel()
```

`apple/MellowPhoto/Features/Editor/BackgroundPanel.swift`:

```swift
import MellowEditing
import SwiftUI

/// 배경 도구. 사람은 그대로 두고 인물 영역 밖을 흐린다.
/// 사람을 찾지 못했거나 인물 분석이 실패하면 안내를 보이고 슬라이더는 값이 보이게 끈다(프리셋으로 들어온 값을 확인할 수 있다).
struct BackgroundPanel: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let availability = model.backgroundAvailability
        switch availability {
        case .ready:
            EmptyView()
        case .noPerson:
            Label(UserMessage.noPersonDetected, systemImage: "person.crop.rectangle.badge.questionmark")
            Text(UserMessage.noPersonHint).font(.caption).foregroundStyle(.secondary)
        case .unavailable(let failure):
            Label(UserMessage.personAnalysisUnavailableTitle, systemImage: "exclamationmark.triangle")
            Text(UserMessage.text(for: failure)).font(.caption).foregroundStyle(.secondary)
        }
        AdjustmentSlider(
            title: UserMessage.backgroundBlur, value: model.currentRecipe.background.blur,
            range: EditingPolicy.unitRange
        ) { .backgroundBlur($0) }
        .disabled(availability != .ready)
        Text(UserMessage.backgroundHint).font(.caption).foregroundStyle(.secondary)
    }
}
```

`AppModel+Live.swift`의 파이프라인 조립:

```swift
            pipeline: PhotoPipeline(
                analyzer: VisionFaceAnalyzer(), personAnalyzer: VisionPersonAnalyzer(),
                tuning: RenderTuning.forCurrentDevice(), lookCatalog: lookCatalog),
```

새 앱 파일을 프로젝트에 넣는다: `cd apple && xcodegen generate --quiet && git status --short MellowPhoto.xcodeproj` → `M MellowPhoto.xcodeproj/project.pbxproj`.

- [ ] **Step 5: 통과 확인**

Run: Mac 앱 테스트 → `Executed 56 tests, with 0 failures`. `cd apple && swift test` → `Executed 253 tests, with 0 failures`. lint 출력 없음. `./scripts/verify-modules.sh` 통과. `cd apple && xcodegen generate --quiet && git diff --exit-code --stat MellowPhoto.xcodeproj` → 이 Task 커밋 뒤에는 출력 없음. iOS 시뮬레이터 테스트는 돌리지 않는다(Task 9).

- [ ] **Step 6: 커밋**

```bash
git add apple/MellowPhoto/Features/Editor/BackgroundPanel.swift apple/MellowPhoto/Application/EditorTool.swift apple/MellowPhoto/Application/AppModel.swift apple/MellowPhoto/Application/AppModel+Editing.swift apple/MellowPhoto/Application/UserMessage.swift apple/MellowPhoto/Features/Editor/ToolStrip.swift apple/MellowPhoto/Features/Editor/EditorScene.swift apple/MellowPhoto/Platform/AppModel+Live.swift apple/MellowPhoto.xcodeproj apple/MellowPhotoTests/TestSupport.swift apple/MellowPhotoTests/AppModelTests.swift apple/MellowPhotoTests/EditorScenarioTests.swift
git commit -m "feat(app): 배경 도구와 사람 없음 안내, Vision 인물 분석 연결

도구 줄 뷰티 다음에 배경 도구를 두고 배경 흐림 슬라이더를 단다. 사람이 없거나
인물 분석이 실패하면 안내를 보이고 슬라이더를 끈다. 실기기 조립은 VisionPersonAnalyzer를 넘긴다.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 9: 문서·검증 기록

**Files:**
- Modify: `README.md`, `docs/APPLE.md`, `docs/architecture/modules.md`, `VALIDATION.md`

**Interfaces:**
- Consumes: Task 1~8 결과와 `MELLOW_IOS_TESTS=1 ./scripts/test-apple.sh`·`./scripts/build-apple.sh` 출력.
- Produces: 문서. 이후 Task 없음.

- [ ] **Step 1: 최종 검증 실행**

Run: `MELLOW_IOS_TESTS=1 ./scripts/test-apple.sh; echo "exit=$?"` → `exit=0`, 패키지 `Executed 253 tests, with 0 failures`, 앱 iPhone `Executed 55 tests`·iPad `Executed 55 tests`·Mac `Executed 56 tests`(모두 0 failures). 실행 전 `xcrun simctl list devices booted`로 이미 켜진 시뮬레이터를 적어 두고, 실행 뒤에도 그 기기들을 끄지 않는다(스크립트가 부팅한 기기를 끄는 것도 하지 않는다. 다른 프로젝트가 같은 기기를 쓸 수 있다). SpringBoard 크래시 창이 떠도 테스트 결과로만 판정하고 기록한다. 이어서 `./scripts/build-apple.sh ios-device; echo "exit=$?"`와 `./scripts/build-apple.sh mac; echo "exit=$?"` → 둘 다 `exit=0`. 빌드 로그의 경고가 Global Constraints의 허용 목록(이번에 `FeatureKernels.swift`의 커널 언어 지원 중단 경고가 늘어남)뿐인지 본다. 실제 숫자·종료 코드·커밋 해시(`git rev-parse --short HEAD`)를 적어 두고 아래 문서에 그대로 쓴다. 기대와 다르면 실제 값을 쓰고, 실패면 통과로 쓰지 않는다.

- [ ] **Step 2: README·APPLE.md·modules.md**

`README.md`:
- "첫 보정" 3번의 "얼굴이 있으면 피부 보정 0.3과 자동 잡티를 켭니다."를 "얼굴이 있으면 피부 보정 0.3·자동 잡티·눈 또렷하게 0.2를 켭니다."로.
- 5번의 "뷰티 값(피부 보정·자동 잡티·얼굴형 10개)"을 "뷰티·배경 값(피부 보정·자동 잡티·얼굴형 10개·눈·입 3개·배경 흐림)"으로.
- 6번 끝에 "*눈·입* 탭은 눈 또렷하게·치아 미백·입술 생기입니다. 치아 미백은 치아가 보이는 사진에서만 바뀝니다."를 더하고, 그 뒤에 새 항목 "**배경**에서 배경 흐림으로 사람은 그대로 두고 뒤 배경만 흐립니다. 사람을 찾지 못한 사진은 안내만 보입니다."를 넣고 이후 번호를 하나씩 민다.
- 도구 줄 문장을 "필터 · 자동 · 자르기 · 조정 · 뷰티 · 배경 · 잡티 · 변형 순서입니다."로.
- "구현된 범위"에 "- 눈 흰자·홍채, 치아, 입술 영역에서만 색을 바꾸는 눈 또렷하게·치아 미백·입술 생기, Vision 인물 영역으로 사람 밖만 흐리는 배경 흐림"을 더하고, 자동 보정 줄의 "(얼굴이 있으면 피부 보정 0.3·자동 잡티 포함)"을 "(얼굴이 있으면 피부 보정 0.3·자동 잡티·눈 또렷하게 0.2 포함)"으로.
- 한계 문단의 얼굴형 문장 뒤에 "눈·입 보정과 배경 흐림도 학습 모델 없이 Vision 특징점·인물 영역으로 동작하며, 특징점을 찾지 못한 얼굴은 바꾸지 않고 흐린 배경에 사람 가장자리 색이 살짝 번질 수 있습니다. 인물 영역을 찾지 못하면 배경 흐림만 빠지고 나머지는 저장됩니다."를 넣는다.
- 로드맵 "D 눈·치아·입술·배경" 줄을 "**D 눈·치아·입술·배경**: 눈·치아·입술 보정과 배경 흐림 (`portrait.features`, `background`) — 구현됨, 실제 인물 사진 확인은 사용자 조치로 남음"으로.

`docs/APPLE.md`:
- 도구 줄 문장을 "**필터 · 자동 · 자르기 · 조정 · 뷰티 · 배경 · 잡티 · 변형**"으로.
- 자동 줄의 "얼굴이 있으면 피부 보정 0.3과 자동 잡티를 켭니다."를 "얼굴이 있으면 피부 보정 0.3·자동 잡티·눈 또렷하게 0.2를 켭니다."로.
- 뷰티 줄의 "얼굴 선택 아래 *피부*·*얼굴* 탭."을 "얼굴 선택 아래 *피부*·*얼굴*·*눈·입* 탭."으로 바꾸고 끝에 "눈·입 탭은 *눈 또렷하게*(흰자를 밝히고 홍채를 선명하게)·*치아 미백*(입을 벌린 사진에서만)·*입술 생기* 0…1이고 수동 편집이 있어도 잠기지 않습니다."를 더한다. 그 아래에 "- 배경: *배경 흐림* 0…1. 사진을 준비할 때 찾은 인물 영역 밖만 흐립니다. 사람을 찾지 못했거나 인물 분석이 실패하면 안내를 보이고 슬라이더를 끕니다." 줄을 넣는다.
- "검증 상태" 문단을 Step 1의 실제 결과(브랜치 `beauty-b-to-f`, 커밋, 종료 코드, 패키지 253개(MellowShared 37 · MellowRendering 159 · MellowLibrary 30 · MellowExport 4 · MellowEditing 23), 앱 iPhone 55 · iPad 55 · Mac 56 예상)로 바꾼다.
- 기기 확인 항목에 "눈·치아·입술 보정의 실제 사진 결과(노란 조명, 다문 입·웃는 입), 배경 흐림의 인물 경계(머리카락·손가락·여러 사람)와 시뮬레이터·구형 기기의 인물 분석 실패 안내"를 더한다.

`docs/architecture/modules.md`:
- MellowRendering 공개 API에 `PhotoAnalysis`, `PersonAnalyzer`, `VisionPersonAnalyzer`를 더한다. 포트 칸에 "`PersonAnalyzer` (`personMask(CIImage) throws -> CIImage?`, 사람 없으면 nil). 기본 구현 `VisionPersonAnalyzer`(`VNGeneratePersonSegmentationRequest`, 기본 품질, 사람 픽셀 1% 미만이면 nil)도 `Infrastructure/`의 `public`"을 더한다.
- MellowRendering 규칙의 단계 순서를 `skin` → `feature` → `background` → `shapeWarp` → `localEdit` → `geometry` → `color` → `detail` → `look`으로 바꾸고 다음을 더한다: "사진 준비 때의 분석(얼굴·잡티·인물 마스크)은 `PhotoAnalysis` 하나로 `RenderContext.analysis`에 넘기고 새 분석은 이 묶음에만 더함, 다각형 마스크 비트맵은 `PhotoAnalysis`의 `RegionMaskCache`(다각형·extent 키, 32개 상한)가 사진마다 한 번만 그리고 미리보기 캐시에서 밀려난 사진은 놓음, 인물 분석 실패는 `PreparedPhoto.personAnalysisFailure`이고 렌더는 배경 단계만 건너뜀(오류 아님), 눈·눈동자·입술·치아 마스크도 `FaceRegions` 한 곳, 눈·입 CIKL 색 커널은 `FeatureKernels` 한 곳(감마 BT.601 YCbCr 가중치·색 이동), `feature` 단계는 마스크 영역만 계산해 원본 위에 합성(마스크 밖 같은 바이트), 다문 입(안쪽 입술 넓이 < 얼굴 상자 × `mouthOpenMinArea`)은 치아를 건너뜀, `background` 단계는 인물 마스크를 extent로 가로·세로 따로 키워 흐리고 반전한 지도로 `CIMaskedVariableBlur` 후 같은 마스크로 원본 위에 합성". 테스트 칸에 "분석 묶음·마스크 캐시, 인물 분석(데모 사진·빈 사진·스텁 실패), 눈·입술·치아 마스크(붉은 입술 제외·다문 입·특징점 누락·데모 사진), 눈·치아·입술 렌더(마스크 밖 불변·범위 밖 값), 배경 흐림(사람 안쪽 같은 바이트·축별 배율·가장자리·실패 시 건너뜀·원본 해상도)"를 더한다.
- `PhotoPipeline` 문단의 `init(analyzer:tuning:lookCatalog:)`를 `init(analyzer:personAnalyzer:tuning:lookCatalog:)`(인물 분석기 기본 nil = 분석 안 함)로 바꾼다.
- MellowEditing 규칙에 "`EditChange.feature`·`backgroundBlur`는 0…1로 자르고 잠기지 않음"을 더한다.
- 앱 `Application/` 설명의 `EditorTool`을 `look, crop, adjust, beauty, background, retouch, warp`로, `BeautyTab`을 (피부·얼굴·눈·입)으로 바꾸고, `AppModel+Live` 줄에 `VisionPersonAnalyzer`를 더한다. `AppModel` 생성자 문단의 "`PhotoPipeline`(안에 `FaceAnalyzer`)"를 "`PhotoPipeline`(안에 `FaceAnalyzer`·`PersonAnalyzer`)"로.

- [ ] **Step 3: VALIDATION.md**

`## 인물 보정 C 얼굴 리셰이프 (2026-10-15)` 절 뒤, `## TestFlight 전용 배포 경로` 앞에 `## 인물 보정 D 눈·치아·입술·배경 (2026-10-15)` 절을 쓴다. 사람 확인 영역만 있고, 실행한 것만 통과로 쓴다.
- 첫 문단: 브랜치·커밋·환경(C 절과 같은 형식), "이 절의 검증은 모두 자동 테스트와 빌드이며, 앱 화면을 직접 보거나 조작한 검증은 없습니다."
- `### 자동 검증`: `MELLOW_IOS_TESTS=1 ./scripts/test-apple.sh` 종료 코드, 패키지 테스트 수(모듈별), 앱 테스트 수(iPhone·iPad·Mac), `build-apple.sh ios-device`·`mac` 종료 코드, 빌드 경고(기존 목록에 `FeatureKernels`의 커널 언어 지원 중단 경고 추가), 실행 중 SpringBoard 크래시가 있었으면 그 사실.
- `### 자동 테스트가 확인하는 것`: 분석 묶음(옛 init과 같은 대상 얼굴·잡티, 마스크 비트맵 재사용·상한·미리보기 밀려나면 놓음), 인물 분석(데모 사진 얼굴 가운데 사람·왼쪽 위 배경, 빈 사진 사람 없음, 스텁 실패가 사진 준비를 막지 않음), 영역 마스크(눈 마스크 밖 0, 동공·대체 중심과 반지름, 넓힌 다각형 안 붉은 입술 제외, 다문 입 치아 없음, 입술 고리, 특징점 없는 얼굴, 데모 사진 실제 특징점), 눈·입 렌더(흰자 밝아짐·홍채 분산 증가·눈 밖 같은 바이트, 치아 파랑 증가·치아 밖 같은 바이트, 다문 입 무변화, 입술 채도 증가·입술 밖 같은 바이트, 범위 밖 값, 특징점 누락), 배경 흐림(마스크 없거나 0이면 같은 바이트, 사람 안쪽 같은 바이트, 가로·세로 배율, 가장자리 불투명, 범위 밖 값, 인물 분석 실패 시 미리보기·저장 모두 흐림만 빠짐, 원본 해상도 렌더), 편집(눈·입·흐림 클램프·잠기지 않음·프리셋·일괄 복사, 자동 보정 눈 또렷하게 0.2), 앱(눈·입 탭 실행 취소 단위, 배경 도구 상태 세 가지, 인물 분석 실패 시 오류 창 없음), 시나리오(데모 사진 → 피부 0.5 + 자동 잡티 → 얼굴형 3개 → 눈 또렷하게 0.5 → 배경 흐림 0.5로 미리보기가 다시 바뀜 → 정사각형 저장, 스텁 얼굴·인물 마스크). "합성 얼굴과 데모 사진 한 장으로 돌며, 실제 인물 사진에서 보기 좋은지는 판단하지 않습니다."
- `### 구현 중 측정 (이번 절을 쓰면서 다시 재지 않음)`: 계획 작성 때 잰 값(Vision 인물 분석 Mac 첫 호출 0.08초·이후 약 0.01초·결과 512×384 고정, 데모 사진 사람 픽셀 57.6%·빈 사진 0%)과 구현 중 실제로 잰 값이 있으면 그 값.
- `### 스펙과 다르게 한 것`: 분석 결과를 `RenderContext` 개별 필드 대신 `PhotoAnalysis` 묶음으로 넘김(B 리뷰 이월), 인물 마스크는 "미리보기 크기"가 아니라 Vision 고정 크기(512×384)라 축별로 키움, "사람 없음" 판정(1%)을 정함, 입 열림의 "얼굴 면적"을 얼굴 상자 넓이로 계산, 눈 높이를 눈 다각형 경계 상자의 짧은 변으로 계산, "노란기(Cb 쪽 이동) 제거"를 음의 Cb를 0 쪽으로 옮기는 것으로 구현, 준비 전 사진의 배경 흐림도 오류 없이 건너뜀, 인물 분석 실패를 가져오기 경고에 넣지 않음, 눈·입 보정은 특징점이 없는 얼굴을 건너뜀.
- `### 미검증 (사용자 확인 필요)`: 실제 인물 사진에서 눈·치아·입술 보정의 느낌과 최대값, 노란 조명·진한 그림자에서 흰자·치아 판별, 웃는 입·살짝 벌린 입의 치아 판정 경계, 배경 흐림의 머리카락·손가락 경계와 사람 가장자리 색 번짐, 여러 사람 사진, iPhone·iPad 실기기와 시뮬레이터에서의 인물 분석 동작·시간, 48MP 원본 저장 속도와 메모리(배경 흐림 반지름 약 120px), 눈·입 탭·배경 도구 화면(슬라이더 배치, 안내 문구, 꺼진 슬라이더), 실기기. "이전 절(C, B, B0, 구조 리팩토링 A)의 미검증 항목은 그대로 승계합니다."

- [ ] **Step 4: 커밋**

```bash
git add README.md docs/APPLE.md docs/architecture/modules.md VALIDATION.md
git commit -m "docs: 눈·입·배경 사용법·모듈 캔버스·D 검증 기록 갱신

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

## 자체 검토 결과

- **스펙 대조:** §1.1 모듈 배치 → `FeatureAdjustments`·`BackgroundAdjustments`(B에서 있음), `PersonAnalyzer` 프로토콜(Rendering/API, Task 2), `VisionPersonAnalyzer`(Rendering/Infrastructure, Task 2), `FaceRegions` 눈·입술·치아 마스크(Domain, Task 3), `FeatureStage`·`BackgroundStage`(Domain, Task 4·5). 새 import 없음, `verify-modules.sh` 불변. §1.2 → 레시피 키는 B에서 있음, `EditChange.feature(FeatureKey, Double)`·`backgroundBlur`(Task 6), `affectsGeometry` false, `dependsOnPerson`(B에서 있음)은 렌더가 인물 실패 때 오류를 던지지 않으므로 판정에 쓰지 않음, 프리셋·일괄 적용이 새 값을 나름(B에서 구현, Task 6이 테스트로 고정). §1.3 → Task 4·5가 `feature`·`background`를 `skin` 뒤에 넣고 `testStageOrderMatters` 배열 갱신(`makeup`은 F). §1.4 → 인물 마스크(3번째 분석)를 준비 때 미리보기에서 계산(Task 2), 실패는 `PreparedPhoto.personAnalysisFailure`(Task 2), 렌더는 해당 단계만 건너뜀(Task 5 렌더·저장 테스트), 앱 안내(Task 8), `RenderContext.personMask`(Task 2, 묶음 경유), `PhotoPipeline.init`의 `personAnalyzer` 인자와 앱 Vision 주입(Task 2·8). `bodies`·`bodyAnalyzer`·`makeupCatalog`는 E·F. §4 → 눈(흰자 휘도 상위·채도 낮음 × `eyeWhiteLift`, 동공 중심 눈 높이 × 0.5 원 안 `CISharpenLuminance` × `eyeIrisSharpen`), 치아(안쪽 입술 × 휘도 > `teethLumaMin` × Cr < `teethRednessMax`, `mouthOpenMinArea` 미만 생략, 노란기 제거 + `teethLift`), 입술(바깥 − 안쪽, 채도 + `lipSaturationMax`, 붉은기 소폭), 배경(확대·`backgroundMaskFeather`·반전·`CIMaskedVariableBlur` 반지름 = 짧은 변 × `backgroundBlurMaxFraction` × 값, 마스크 없으면 그대로), UI(눈·입 탭 3개 Task 7, 배경 도구 + 사람 없음 Task 8). §4 테스트 → 마스크 밖 불변 눈·치아·입술 각각(Task 4 `testEyeBrighten…`·`testTeethWhiten…`·`testLipVitality…`), 붉은 입술 치아 마스크 제외(Task 3 `testTeethMaskKeepsTeethAndDropsRedLip…`), 다문 입 무변화(Task 4 `testClosedMouthTeethWhitenChangesNothing`, Task 3 `testClosedMouthHasNoTeethMask`), 스텁 인물 마스크 사람 불변·배경 변화(Task 5 `testBlurChangesBackgroundAndKeepsPersonCoreBytes`). §7 → `EditorTool.background`(Task 8, `makeup`·`body`는 F·E), 뷰티 하위 탭 눈·입(Task 7), 분석 실패 안내(Task 8), 자동 보정 `eyeBrighten 0.2`(Task 6), `UserMessage` 도구·탭·안내 문구(Task 7·8). §8 → 각 Task 테스트, 순서 배열(Task 4·5), `AppModelTests`(Task 7·8), 시나리오의 눈 또렷 0.5 → 배경 흐림 0.5(Task 8), 전체 검증·VALIDATION D 절(Task 9). §9 → 파일 이름과 주요 Task(Person 분석, FeatureStage, BackgroundStage, 눈·입 패널, 배경 도구)가 표와 같다.
- **B·C 이월:** (a) 분석 묶음 → Task 1, (b) 마스크 비트맵 캐시 → Task 1, (c) 인물 실패 시 단계만 건너뜀 → Task 5, (d) `landmarkPolygon` 공개와 눈·입술·치아 다각형 → Task 3, (e) 눈·입 탭 → Task 7, (f) 잡티 검출은 준비 때 유지(근거는 사람 확인 영역과 Task 2 주석). C Ruling C1(iOS는 `MELLOW_IOS_TESTS=1`) → Global Constraints와 Task 9.
- **타입 일관성:** `PhotoAnalysis`(Task 1, Task 2가 person 필드 추가)·`RenderContext.init(…analysis:…)`·`regionMasks`·`personMask`, `RegionMaskCache.count`·`maximumEntries`·`mask(for:make:)`·`removeAll()`, `RegionMaskKey(fill:cut:cutWidth:extent:maxDimension:)`, `FaceRegions.RegionMask`·`IrisCircle`·`eyeMask`·`irisMask`·`lipMask`·`teethMask`·`irisCircles`·`innerMouthAreaFraction`, `ToneRule.sclera`·`teeth`, `ToneShift`, `FeatureKernels.weight(of:rule:extent:)`·`shifted(_:by:extent:)`, `StubPersonAnalyzer(result:)`(패키지·앱 각각), `RenderingTestSupport.personMask(size:person:)`, `TestSupport.personMask(_:)`, `SyntheticFace.makeFeatures`·`innerLips(radii:)`·표본 점 이름을 정의한 Task와 쓰는 Task에서 같게 썼다. 테스트 수: 패키지 220 → 225 → 230 → 237 → 244 → 251 → 253, 앱 Mac 53 → 54 → 56, iPhone·iPad 52 → 53 → 55.
- **Review Focus 매핑:** 1→Task 5(+Task 8), 2→Task 5, 3→Task 5, 4→Task 4·5, 5→Task 3·4. 모두 테스트 코드가 있다.
- **플레이스홀더 점검:** "TBD/TODO/나중에" 없음. Task 1의 `rasterize` 본문은 기존 코드를 그대로 옮기라는 지시이며 옮길 범위를 행으로 적었다. Task 9 문서 수치는 실제 실행 결과로 쓴다.
