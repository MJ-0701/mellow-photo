# 인물 보정 F 메이크업 구현 계획

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 새 메이크업 도구에 룩 5종(데일리·쿨톤·웜피치·로지·스모키)과 립 6색·블러셔 4색·아이섀도 4색·눈썹·쉐딩/하이라이터를 더하고, 데이터 파일 하나(`shared/makeup/makeup.v1.json`)로 팔레트와 룩을 정의한 뒤, 문서·검증 기록·1.2.0 변경사항까지 마쳐 1.2.0 배포를 준비한다.

**Architecture:** `MakeupCatalog`(MellowShared)가 데이터 파일을 읽고 형식을 검사한다. `EditDocument.applyMakeupLook(_:)`이 룩 값을 체크포인트 한 번으로 써 넣고, 부위를 바꾸면 룩 이름이 풀린다. 렌더는 `feature`와 `background` 사이의 새 `MakeupStage`가 대상 얼굴마다 `FaceRegions` 마스크(입술은 기존 `lipMask`, 새 마스크는 `FaceRegions+Makeup.swift`) 안에서만 Core Image 기본 섞기 모드로 색을 얹는다. 블러셔·쉐딩·하이라이터는 얼굴 좌표계(`FaceFrame`)의 기운 타원 × 피부 다각형 비트맵이라 기울어진 얼굴을 따라가고 캐시 항목을 늘리지 않는다. 다각형 비트맵 캐시 상한은 얼굴 수에 비례한다.

**Tech Stack:** Swift 5.9 tools / Swift 5 언어 모드, SwiftUI + Observation, Core Image(`CISoftLightBlendMode`·`CIMultiplyBlendMode`·`CIScreenBlendMode`·`CIBlendWithMask`·`CIRadialGradient`, 새 커널 언어 커널 없음), Vision(기존), XCTest, XcodeGen 2.46.0.

**Spec:** `docs/superpowers/specs/2026-10-15-beauty-b-to-f-design.md` (F에 해당하는 절: 1.1~1.3, 6, 7, 8, 9, "외부 효과가 있는 단계"). 이월 항목은 `.superpowers/sdd/2026-10-15-beauty-d-features/progress.md`("Carry-forward (F)": 캐시 상한, `lipMask` 재사용, `makeupCatalog` 기본값), `.superpowers/sdd/2026-10-15-beauty-c-face/progress.md`(특징점 없는 얼굴 안내), `.superpowers/sdd/2026-10-15-beauty-e-body/progress.md`(상반신 다리 길게)에서 가져왔다.

## 사람이 확인할 것

- **순서.** Task 1 데이터·카탈로그 → 2 편집 규칙 → 3 메이크업 단계·립 → 4 블러셔·아이섀도 → 5 눈썹·쉐딩 → 6 캐시·여러 얼굴 → 7 앱 정리 → 8 메이크업 도구 → 9 문서·검증·1.2.0 변경사항. 9개 Task, Task마다 Opus 구현 → 리뷰 → 수정, 끝에 전체 리뷰.
- **외부 효과가 있는 단계.** 이 계획 안에는 없다. Task 9는 `fastlane/release_notes/1.2.0.json`을 커밋만 한다. 머지 뒤 `scripts/release.sh apple 1.2.0` → `git push origin main apple-v1.2.0`은 컨트롤러가 사용자 확인 뒤 실행하며, 태그 푸시가 TestFlight 업로드와 외부 베타 심사 제출을 일으킨다.
- **스펙이 정하지 않아 이 계획이 정한 것.**

| 결정 | 이유 | 바꾸면 비용 |
|---|---|---|
| 데이터 파일의 `colors`는 부위별 객체(`lip`·`blush`·`eyeshadow`), 읽을 때 rgb 3개·0…1, id 중복, 룩이 자기 부위 팔레트 색만 쓰는지 검사하고 틀리면 파일 전체를 거부 | 다른 플랫폼도 같은 파일을 읽는다. 틀린 파일이 조용히 엉뚱한 색을 내지 않고 "메이크업 목록을 읽지 못함" 안내로 드러난다 | **중간** (파일 형식은 플랫폼 공통 계약) |
| 색 섞기는 Core Image 기본 섞기 모드를 작업 색공간에서: 립·블러셔 소프트 라이트, 아이섀도·눈썹·쉐딩 곱하기, 하이라이터 스크린 | 스펙의 모드 그대로이고 새 커널 언어 커널(지원 중단 경고)을 더하지 않는다. 감마 공간 계산보다 조금 진하게 보일 수 있어 강도 상한은 `RenderTuning` 한 곳에서 조정 | 작음 |
| 블러셔·쉐딩·하이라이터는 얼굴 좌표 타원 × 기존 피부 다각형 비트맵 | 기울어진 얼굴을 따라가고, 눈·눈썹·입술(넓힌 보호 영역)과 얼굴 밖에는 색이 닿지 않으며, 피부 보정과 같은 비트맵을 써 캐시가 늘지 않는다 | 작음 |
| 쉐딩은 광대 아래·턱선·코 옆(각 2곳), 하이라이터는 콧대·이마 가운데·턱 끝, 강도 슬라이더 하나로 함께 | 스펙 6의 위치 그대로, 화면은 부위당 슬라이더 하나 | 작음 |
| 아이섀도는 윗눈꺼풀 선부터 눈썹 아래끝까지 거리의 75%, 눈썹이 없으면 눈 높이만큼 | 눈썹에 닿지 않고 쌍꺼풀 위까지 덮는 흔한 범위 | 작음 |
| 눈썹은 가로 1.15배·세로 1.6배 넓힌 영역을 원래 눈썹 평균색으로 곱함 | 스펙 "조금 넓혀 기존 눈썹 색으로". 가는 눈썹이 위아래로 채워진다 | 작음 |
| 색을 처음 고를 때 강도가 0이면 0.5로 둠(편집 규칙) | 색 칩을 눌렀는데 아무것도 안 바뀌는 일을 막는다. 실행 취소 한 단계 | 작음 |
| 룩 칩 "없음"은 메이크업을 모두 지움. 룩 칩은 이름만(썸네일 없음) | 메이크업 썸네일은 얼굴 크기 렌더가 5번 더 필요하다 | 작음 |
| 룩 적용은 `EditDocument.applyMakeupLook(룩)` 한 경로. 스펙 1.2의 `EditChange.makeupLook(String?)`은 만들지 않음 | 편집 규칙은 카탈로그를 모른다. id만 받는 변경은 부위 값을 채우지 못해 lookID가 실제 값과 어긋난다. 스펙 문구는 Task 9에서 고친다 | 작음 |
| 다각형 비트맵 캐시 상한을 얼굴 수에 비례(얼굴당 16, 최소 32) | 메이크업이 얼굴당 비트맵 3개(아이섀도·눈썹 둘)를 더해 얼굴 셋이면 미리보기·저장을 오갈 때마다 비우고 다시 그린다(D 이월). 늘어나는 메모리는 비트맵 하나 최대 256KB | 작음 |
| 시작 팔레트와 룩 수치(예: 데일리 = MLBB 립 0.5·피치 블러셔 0.35·브라운 섀도 0.3·눈썹 0.3·쉐딩 0.2) | 자연스러운 쪽 어림. 실사진 피드백으로 데이터 파일 한 곳에서 조정 | 작음 |
| 앱 정리: 특징점 없는 얼굴은 뷰티·메이크업에 안내 문구, 배경·체형 슬라이더는 값이 0이 아니면 켜 둠(프리셋 값을 0으로 되돌릴 수 있게), 상반신 사진의 다리 길게는 지금 안내 그대로 | 이전 단계 이월. 다리 길게까지 끄려면 사진 정보에 새 판정 필드가 필요해 이번엔 안내로 둔다 | 작음 |

- **확인한 기존 동작(새 작업 없음).** 프리셋·일괄 적용이 메이크업을 나르는 것과 자동 보정이 메이크업을 건드리지 않는 것은 B에서 구현·테스트됐다(`EditDocumentTests`). 스펙 9의 "자동 보정 확장"(피부 0.3·자동 잡티·눈 또렷하게 0.2)도 B·D에서 끝났다.
- **범위 밖.** 아이라이너·속눈썹(스펙), 메이크업 룩 썸네일, 피부톤에 맞춘 색 추천, 부위 위치 손으로 옮기기, 감마 공간 섞기 커널, 다리 길게 슬라이더 끄기, 실사진 품질 판정.
- **위험.** 소프트 라이트는 아주 어둡거나 밝은 입술에서 색 변화가 약하다. 특징점이 틀리면 엉뚱한 곳에 색이 얹힌다. 블러셔·쉐딩·하이라이터는 피부색 판별 없이 다각형만 쓰므로 머리카락이 이마·볼을 덮으면 머리카락에도 얹힌다. 안경테·앞머리가 눈썹을 가리면 눈썹 평균색이 틀린다. 보정 품질은 자동 테스트로 판정할 수 없다.
- **사용자 조치.** 1.2.0 TestFlight 빌드에서 실제 인물 사진으로 메이크업 5룩과 부위별 색 확인, Task 9가 쓴 1.2.0 변경사항 문구 검토, 배포 실행 승인.

---

## 에이전트 참조

## Global Constraints

- 작업 위치: worktree `/Users/mj/IdeaProjects/mellow-photo/.claude/worktrees/b0-basic-editing`, 브랜치 `beauty-b-to-f`(시작 HEAD `d9f32d4` 뒤 이 계획 커밋, B~E 구현 완료). 부모 저장소로 `cd`하지 않는다. 모든 Swift·xcodebuild 명령 전에 `export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`.
- 모듈 의존성 표(`docs/architecture/modules.md`)와 `scripts/verify-modules.sh`는 바뀌지 않는다. MellowShared는 Foundation·CoreGraphics만, MellowEditing은 MellowShared만, MellowRendering은 `CoreImage`·`Foundation`·`MellowShared`·`Vision`만 import한다. MellowRendering은 MellowEditing을 import할 수 없다(값 범위는 MellowShared `AdjustmentRange`).
- 새 보정은 MellowRendering 단계와 MellowShared 레시피 확장으로만 넣는다. 파이프라인 단계 이름 순서는 Task 3부터 `skin, feature, makeup, background, shapeWarp, localEdit, geometry, color, detail, look`(스펙 1.3)이다.
- 레시피 `schemaVersion`은 2 유지, F는 레시피 키를 바꾸지 않는다(`makeup`은 B에서 이미 있다). v1 세션은 계속 읽힌다. 번들 ID `com.mj.mellowphoto`는 그대로.
- 값 범위: `makeup.*.intensity` 0…1(`AdjustmentRange.unit` = `EditingPolicy.unitRange`). 렌더도 이 범위로 직접 자른다(프리셋·일괄 값은 편집 규칙을 거치지 않는다). 유한하지 않은 값은 `RenderPipeline`이 먼저 거절한다(`allValuesFinite`에 이미 포함).
- 마스크는 `FaceRegions`(같은 타입의 확장 파일 포함)에서만 만든다(스펙 1.1, D 이월). 입술 색은 기존 `FaceRegions.lipMask`를 다시 쓴다.
- `RenderTuning` 새 상수 시작값: Task 3 — makeupLipMaxOpacity 0.85. Task 4 — makeupBlushMaxOpacity 0.6, makeupEyeshadowMaxOpacity 0.45, makeupEyeshadowFeather 0.008. Task 5 — makeupBrowMaxOpacity 0.5, makeupBrowFeather 0.006, makeupShadeMaxOpacity 0.4, makeupHighlightMaxOpacity 0.3, makeupShadeRGB [0.72, 0.6, 0.52], makeupHighlightRGB [1, 0.97, 0.92]. 위치 비율은 `FaceRegions+Makeup.swift`의 `private enum MakeupShape`(기존 `FaceShapeRig`처럼 타입 안 상수).
- 한 줄 한 문장, 세미콜론 금지, 매직 넘버는 명명 상수(`RenderTuning`·`Theme`·`AppModel.Policy`·`EditingPolicy`, 기하 비율은 타입 안 `private static let` 또는 `MakeupShape`).
- 한국어 사용자 문구는 앱 타깃(`UserMessage`·뷰)에만. 모듈은 `MellowError`만 던진다(F는 새 오류 case를 더하지 않는다. 카탈로그 디코드 오류는 `DecodingError`이고 앱이 `nil`로 받아 안내 문구로 바꾼다).
- `cd apple && swift format lint --strict --recursive Sources Tests MellowPhoto MellowPhotoTests` 출력 없음(긴 줄은 줄바꿈으로 고친다, 한도 120자). 허용된 빌드 경고: 기존 `CIWarpKernel` 지원 중단(`WarpKernel`), 기존 `CIColorKernel(source:)` 지원 중단(`SkinKernels`, `DisplacementWarp`, `FeatureKernels`), 기존 `CIKernel(source:)` 지원 중단(`DisplacementWarp`), 시뮬레이터 `usesCPUOnly`(`VisionFaceAnalyzer`). F는 새 경고를 더하지 않는다.
- `./scripts/verify-modules.sh` 통과. 전체 검증은 `./scripts/test-apple.sh`.
- 패키지 테스트: `cd apple && swift test`(모듈마다 `Executed N tests`가 따로 찍힌다). Mac 앱 테스트: `xcodebuild -project apple/MellowPhoto.xcodeproj -scheme MellowPhoto -derivedDataPath apple/build -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO test 2>&1 | grep -E "Executed|TEST (SUCCEEDED|FAILED)|error:"`. 앱 파일을 더하는 Task는 Task 1(리소스 `makeup.v1.json`)과 Task 8(`MakeupPanel.swift`)이며 그 두 Task만 `cd apple && xcodegen generate --quiet`를 돌리고 `apple/MellowPhoto.xcodeproj`를 함께 커밋한다.
- iOS 시뮬레이터 테스트는 Task 9의 `MELLOW_IOS_TESTS=1 ./scripts/test-apple.sh` 한 번에서만 돌린다(로컬 `test-apple.sh`는 이 변수가 없으면 iOS 시뮬레이터를 건너뛴다). 직접 부팅하지 않은 시뮬레이터를 끄지 않는다(`xcrun simctl shutdown`·`erase` 금지, 다른 프로젝트가 같은 기기를 쓰고 있을 수 있다). Xcode를 열거나 앱을 직접 띄우거나 조작하지 않는다.
- 푸시·태그·`scripts/release.sh` 실행 금지(머지 뒤 컨트롤러 몫).
- 커밋: 한국어 Conventional Commits, 마지막 줄 `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`. `git add`는 Task에 나열한 경로만.
- 각 Task 끝에 패키지 테스트(앱을 건드렸으면 Mac 앱 테스트도)와 lint가 통과해야 다음으로 간다. 기준 테스트 수(시작 시점, 계획 작성 때 `func test` 수로 셈): 패키지 298(Shared 40 · Rendering 197 · Library 30 · Export 4 · Editing 27), 앱 iPhone 60 · iPad 60 · Mac 61. 목표: 패키지 322(Shared 43 · Rendering 216 · Library 30 · Export 4 · Editing 29), 앱 iPhone 65 · iPad 65 · Mac 66.

## Review Focus

스펙이 암시하지만 스펙의 테스트 목록이 직접 다루지 않는 입력. 각 줄의 테스트를 소유 Task에 넣었다.

1. **손으로 고친 프리셋·일괄 적용으로 모르는 색 id, 다른 부위의 색 id(립에 `blush-peach`), 범위 밖 강도(3, −0.5)가 들어오거나 카탈로그가 비어 있다.** 렌더는 그 부위만 건너뛰거나 잘린 값과 같아야 하고 오류를 던지지 않아야 한다. → Task 3 `testUnknownWrongPartOrMissingCatalogColorAndLandmarklessFaceSkipLip`, `testOutOfRangeIntensityRendersLikeClampedValues`, `testPreviewAndOriginalPaintMakeupOnlyWithPipelineCatalog`.
2. **특징점이 없는 얼굴(Vision이 상자만 준 얼굴), 눈썹·코·눈 일부가 없는 얼굴.** 그 부위만 조용히 빠지고, 앱은 슬라이더가 아무것도 안 하는 이유를 알려야 한다. → Task 4 `testMakeupMasksNeedLandmarks`, Task 5 `testBrowAndContourNeedLandmarks`, Task 7 `testFaceAvailabilityReportsMissingLandmarksForTargetFaces`.
3. **기울어진 얼굴(roll 30°).** 블러셔·아이섀도가 얼굴을 따라 돌아야 하고 돌리기 전 자리는 비어야 한다. → Task 4 `testBlushAndEyeshadowFollowARolledFace`.
4. **단체 사진.** 대상 얼굴만 바뀌어야 하고, 얼굴 셋에 메이크업을 모두 켜고 미리보기·저장 크기를 오가도 마스크 캐시가 비워지지 않아야 한다. → Task 6 `testTargetFacePaintsOnlyThatFace`, `testThreeFacesWithFullMakeupKeepEveryMaskAcrossTwoResolutions`.
5. **번들 카탈로그가 없거나 깨졌거나 공용 파일과 어긋났다.** 앱은 안내 문구를 띄우고 나머지 도구는 동작해야 하며 깨진 파일은 받아들이지 않아야 한다. → Task 1 `testRejectsUnknownSchemaPartBadRGBForeignColorAndRange`, `testBundledMakeupIsIdenticalToSharedFile`, Task 8 `testMakeupWorksWithLocalEditsAndFallsBackWithoutCatalog`.

## 인터페이스 요약 (모든 Task가 공유하는 이름)

```swift
// MellowShared (Task 1·2)
public struct MakeupColor: Codable, Equatable, Sendable, Identifiable { id; name; rgb: [Double]; red; green; blue }
public struct MakeupLook: Codable, Equatable, Sendable, Identifiable {
    id; name; lip: MakeupTint; blush: MakeupTint; eyeshadow: MakeupTint; brow: MakeupStrength; contour: MakeupStrength
    init(id:name:lip:blush:eyeshadow:brow:contour:)   // 부위 기본값 .init()
    var adjustments: MakeupAdjustments                // lookID = id
}
public struct MakeupCatalog: Equatable, Sendable {
    static currentSchemaVersion = 1; static builtInLookIDs; static builtInColorIDs: [MakeupPart: [String]]; static empty
    let looks: [MakeupLook]; init(looks:palettes:); init(data:) throws
    func look(id: String?) -> MakeupLook?; func colors(for: MakeupPart) -> [MakeupColor]
    func color(id: String?) -> MakeupColor?; func color(id: String?, for: MakeupPart) -> MakeupColor?; var isEmpty: Bool
}
MakeupAdjustments.colorID(of:), setColorID(_:of:), setIntensity(_:of:)          // Task 2

// MellowEditing (Task 2)
EditChange.makeupColor(MakeupPart, String?), .makeupIntensity(MakeupPart, Double)   // affectsGeometry false
EditingPolicy.makeupDefaultIntensity                                                // 0.5
EditDocument.applyMakeupLook(_ look: MakeupLook?)                                   // nil = 모두 지움

// MellowRendering 공개 API (Task 3)
RenderContext.makeupCatalog: MakeupCatalog                 // 두 init 모두 makeupCatalog: = .empty (lookCatalog 다음)
PhotoPipeline.init(analyzer:personAnalyzer:bodyAnalyzer:tuning:lookCatalog:makeupCatalog:)   // 기본 .empty
RenderTuning.makeupLipMaxOpacity (T3), makeupBlushMaxOpacity, makeupEyeshadowMaxOpacity, makeupEyeshadowFeather (T4),
    makeupBrowMaxOpacity, makeupBrowFeather, makeupShadeMaxOpacity, makeupHighlightMaxOpacity, makeupShadeRGB,
    makeupHighlightRGB (T5)

// MellowRendering internal
struct MakeupStage: RenderStage { name "makeup"; static clamped(_:), colorImage(_:part:context:), solid(_:), mixed(...), blended(...) }  // T3
MaskBuilder.ellipse(center:radii:angle:extent:strength:)                           // T4
FaceRegions.skinPolygonRaster(face:extent:tuning:cache:)                           // T4 (skinMask가 같은 비트맵)
FaceRegions.featheredPolygonMask(…, feather:)  // T4: private → internal, feather 인자 추가
FaceRegions.Oval, blushMask(face:extent:tuning:cache:), eyeshadowMask(…), lidPolygon(eye:brows:frame:), softMask(…)   // T4
FaceRegions.BrowRegion { mask; sample }, browRegions(…), ContourRegions { shade; highlight }, contourRegions(…)        // T5
RegionMaskCache.minimumEntries, entriesPerFacePerResolution, resolutions, capacity(forFaces:), maximumEntries(인스턴스), init(maximumEntries:)   // T6

// 테스트 지원 (apple/Tests/MellowRenderingTests)
RenderingTestSupport.sharedMakeupCatalog()                                          // T3
SyntheticFace.leftBlush, rightBlush, rolledLeftBlush, rolledRightBlush, rolledLidSkin (T4), leftBrowCenter, aboveLeftBrow,
    leftHollow, rightHollow, leftJaw, bridge, foreheadCenter, chinTip (T5)

// 앱 (Task 7·8)
AppModel.FaceAvailability { ready, noLandmarks, noFace, unavailable(MellowError) }, faceAvailability,
    canAdjustBackgroundBlur, canAdjustBodyShape(_:)                                 // T7
EditorTool.makeup, MakeupPanel, AppModel.makeupCatalog, makeupPart, applyMakeupLook(id:),
    AppModel.bundledMakeupCatalog(in:), Policy.bundledMakeupCatalogName/Extension   // T8
UserMessage.noLandmarksHint (T7), toolMakeup, makeupNoLook, makeupPartsLabel, makeupIntensity, makeupHint,
    makeupCatalogUnavailable, makeupPartTitle(_:) (T8)
Theme.makeupChipSize, makeupChipPadding, makeupSwatchSize                          // T8
TestSupport.sharedMakeupCatalog(), makeModel(…, makeupCatalog: MakeupCatalog? = nil, …)   // T8
```

---

### Task 1: 메이크업 데이터와 카탈로그 — makeup.v1.json, MakeupCatalog, 번들 사본

**Files:**
- Create: `shared/makeup/makeup.v1.json`, `shared/makeup/README.md`
- Create: `apple/MellowPhoto/Resources/makeup.v1.json` (위 파일과 바이트 동일)
- Create: `apple/Sources/MellowShared/API/MakeupCatalog.swift`
- Modify: `apple/MellowPhoto.xcodeproj` (`xcodegen generate` 결과)
- Test: `apple/Tests/MellowSharedTests/MakeupCatalogTests.swift`(새 파일), `apple/MellowPhotoTests/BundledLooksTests.swift`

**Interfaces:**
- Consumes: `MakeupPart`(`hasColor`), `MakeupTint`, `MakeupStrength`, `MakeupAdjustments(lookID:lip:blush:eyeshadow:brow:contour:)`, `AdjustmentRange.unit` (모두 B에서 있음).
- Produces: `public struct MakeupColor`(`id`, `name`, `rgb`, `red`·`green`·`blue` = 성분이 없으면 0), `public struct MakeupLook`(`init(id:name:lip:blush:eyeshadow:brow:contour:)`, `adjustments`), `public struct MakeupCatalog`(`currentSchemaVersion`, `builtInLookIDs`, `builtInColorIDs`, `empty`, `looks`, `init(looks:palettes:)`, `init(data:) throws`, `look(id:)`, `colors(for:)`, `color(id:)`, `color(id:for:)`, `isEmpty`).

설계 근거: `LookCatalog`와 같은 패턴(스펙 6). 다른 플랫폼이 같은 파일을 읽으므로 형식 위반은 디코드 단계에서 `DecodingError.dataCorrupted`로 거부한다. 앱은 디코드 실패를 "메이크업 목록을 읽지 못함"으로 알린다(Task 8). 렌더가 쓰는 `color(id:for:)`는 그 부위 팔레트만 찾는다. 손으로 고친 프리셋이 립에 블러셔 색을 넣으면 립을 건너뛴다(Task 3).

- [ ] **Step 1: 데이터 파일**

`shared/makeup/makeup.v1.json`:

```json
{
  "schemaVersion": 1,
  "colors": {
    "lip": [
      { "id": "lip-nude",  "name": "누드", "rgb": [0.80, 0.55, 0.49] },
      { "id": "lip-coral", "name": "코랄", "rgb": [0.96, 0.45, 0.38] },
      { "id": "lip-rose",  "name": "로즈", "rgb": [0.82, 0.38, 0.47] },
      { "id": "lip-red",   "name": "레드", "rgb": [0.80, 0.10, 0.16] },
      { "id": "lip-berry", "name": "베리", "rgb": [0.60, 0.13, 0.30] },
      { "id": "lip-mlbb",  "name": "MLBB", "rgb": [0.72, 0.42, 0.42] }
    ],
    "blush": [
      { "id": "blush-peach", "name": "피치", "rgb": [0.98, 0.70, 0.58] },
      { "id": "blush-pink",  "name": "핑크", "rgb": [0.97, 0.62, 0.70] },
      { "id": "blush-coral", "name": "코랄", "rgb": [0.97, 0.55, 0.45] },
      { "id": "blush-rose",  "name": "로즈", "rgb": [0.86, 0.52, 0.58] }
    ],
    "eyeshadow": [
      { "id": "shadow-brown", "name": "브라운", "rgb": [0.55, 0.38, 0.28] },
      { "id": "shadow-peach", "name": "피치",   "rgb": [0.90, 0.62, 0.50] },
      { "id": "shadow-pink",  "name": "핑크",   "rgb": [0.85, 0.55, 0.62] },
      { "id": "shadow-smoky", "name": "스모키", "rgb": [0.30, 0.27, 0.28] }
    ]
  },
  "looks": [
    { "id": "daily",      "name": "데일리", "lip": { "colorID": "lip-mlbb",  "intensity": 0.5 },  "blush": { "colorID": "blush-peach", "intensity": 0.35 }, "eyeshadow": { "colorID": "shadow-brown", "intensity": 0.3 },  "brow": { "intensity": 0.3 },  "contour": { "intensity": 0.2 } },
    { "id": "cool",       "name": "쿨톤",   "lip": { "colorID": "lip-rose",  "intensity": 0.55 }, "blush": { "colorID": "blush-pink",  "intensity": 0.4 },  "eyeshadow": { "colorID": "shadow-pink",  "intensity": 0.35 }, "brow": { "intensity": 0.3 },  "contour": { "intensity": 0.25 } },
    { "id": "warm-peach", "name": "웜피치", "lip": { "colorID": "lip-coral", "intensity": 0.55 }, "blush": { "colorID": "blush-peach", "intensity": 0.45 }, "eyeshadow": { "colorID": "shadow-peach", "intensity": 0.4 },  "brow": { "intensity": 0.3 },  "contour": { "intensity": 0.2 } },
    { "id": "rosy",       "name": "로지",   "lip": { "colorID": "lip-rose",  "intensity": 0.6 },  "blush": { "colorID": "blush-rose",  "intensity": 0.5 },  "eyeshadow": { "colorID": "shadow-pink",  "intensity": 0.3 },  "brow": { "intensity": 0.25 }, "contour": { "intensity": 0.15 } },
    { "id": "smoky",      "name": "스모키", "lip": { "colorID": "lip-berry", "intensity": 0.6 },  "blush": { "colorID": "blush-rose",  "intensity": 0.3 },  "eyeshadow": { "colorID": "shadow-smoky", "intensity": 0.6 },  "brow": { "intensity": 0.5 },  "contour": { "intensity": 0.4 } }
  ]
}
```

번들 사본: `mkdir -p shared/makeup && cp shared/makeup/makeup.v1.json apple/MellowPhoto/Resources/makeup.v1.json` (파일을 먼저 쓴 뒤 복사).

`shared/makeup/README.md`:

````markdown
# 메이크업 카탈로그

메이크업 팔레트와 룩은 이 폴더의 데이터로 정의합니다. Apple·Android·Windows 구현은 모두 `makeup.v1.json`을 그대로 읽습니다. 색이나 룩을 플랫폼 코드 안에 따로 적지 않습니다.

레시피는 `makeup.lookID`와 부위별 `colorID`로 이 파일을 가리킵니다(`shared/recipe-schema/README.md`의 `makeup` 항목). id는 고정이며, 지우거나 바꾸면 기존 레시피의 색이 빠집니다. 이름과 수치는 실제 사진으로 보며 조정할 수 있습니다.

Apple 기준 구현은 `apple/Sources/MellowShared/API/MakeupCatalog.swift`(`MakeupColor`, `MakeupLook`, `MakeupCatalog`)입니다.

## 파일 형식

```json
{ "schemaVersion": 1,
  "colors": { "lip": [ { "id": "lip-coral", "name": "코랄", "rgb": [0.96, 0.45, 0.38] }, … ], "blush": [ … ], "eyeshadow": [ … ] },
  "looks": [ { "id": "daily", "name": "데일리", "lip": { "colorID": "lip-mlbb", "intensity": 0.5 }, …, "brow": { "intensity": 0.3 }, "contour": { "intensity": 0.2 } } ] }
```

- `schemaVersion`: 지금은 `1`입니다. 읽는 쪽은 모르는 버전을 거부합니다(`MakeupCatalog.currentSchemaVersion`).
- `colors`: 색을 고르는 세 부위(`lip` 6색, `blush` 4색, `eyeshadow` 4색)의 팔레트. 배열 순서가 화면 순서입니다. 눈썹·쉐딩은 색이 없습니다.
- `looks`: 화면 순서대로 둔 룩 5개(`daily`, `cool`, `warm-peach`, `rosy`, `smoky`, `MakeupCatalog.builtInLookIDs`).

| 필드 | 범위 | 의미 |
|---|---|---|
| 색 `id` | 문자열, 파일 전체에서 유일 | 레시피가 저장하는 식별자. 바꾸지 않습니다. |
| 색 `name` | 문자열 | 화면에 보여 줄 이름(한국어). |
| 색 `rgb` | 숫자 3개, 각 0 … 1 | sRGB 감마 값. |
| 룩 `id`·`name` | 문자열 | 룩 식별자와 이름. |
| 룩 `lip`·`blush`·`eyeshadow` | `{ colorID, intensity }` | `colorID`는 그 부위 팔레트의 색(다른 부위 색은 거부), `intensity` 0 … 1. |
| 룩 `brow`·`contour` | `{ intensity }` | 0 … 1. |

읽는 쪽은 형식이 틀린 파일(모르는 부위, rgb 개수·범위, 중복 id, 다른 부위 색을 쓰는 룩, 범위 밖 강도) 전체를 거부하고 메이크업 없이 동작합니다.

## 룩 적용 규칙

룩을 고르면 룩의 부위 값 다섯 개를 레시피 `makeup`에 그대로 써 넣고 `lookID`를 기록합니다(실행 취소 한 단계). 이후 부위 하나라도 값을 바꾸면 `lookID`를 비웁니다. 룩 "없음"은 메이크업을 모두 지웁니다. 색을 처음 고를 때 그 부위 강도가 0이면 0.5로 둡니다.

## 렌더

메이크업은 렌더 파이프라인의 `feature`(눈·치아·입술 생기) 다음, `background` 앞 단계입니다. 얼굴 특징점에서 만든 영역 안에서만 바꾸고, 강도 = 부위 강도 × 부위 최대 불투명도(Apple `RenderTuning`)로 원본과 섞습니다. 섞기는 작업 색공간(선형 sRGB)에서 합니다.

| 부위 | 영역 | 섞기 | 최대 불투명도 |
|---|---|---|---|
| 립 | 바깥 입술 − 안쪽 입술 | 소프트 라이트(고른 색) | 0.85 |
| 블러셔 | 두 눈 아래·코 옆 볼 타원 × 얼굴 피부 영역 | 소프트 라이트(고른 색) | 0.6 |
| 아이섀도 | 윗눈꺼풀부터 눈썹 아래까지 거리의 75% 띠 − 눈 | 곱하기(고른 색) | 0.45 |
| 눈썹 | 눈썹을 가로 1.15배·세로 1.6배 넓힌 영역 | 곱하기(원래 눈썹 평균색) | 0.5 |
| 쉐딩 | 광대 아래·턱선·코 옆 타원 × 얼굴 피부 영역 | 곱하기(회갈색 `[0.72, 0.6, 0.52]`) | 0.4 |
| 하이라이터 | 콧대·이마 가운데·턱 끝 타원 × 얼굴 피부 영역 | 스크린(`[1, 0.97, 0.92]`) | 0.3 |

순서는 쉐딩·하이라이터 → 블러셔 → 아이섀도 → 눈썹 → 립입니다. 위치 비율은 Apple `apple/Sources/MellowRendering/Domain/FaceRegions+Makeup.swift`의 `MakeupShape`에 있습니다.

## 앱 번들 사본

Apple 앱은 `apple/MellowPhoto/Resources/makeup.v1.json` 사본을 번들에 넣어 읽습니다. 이 파일을 고치면 사본도 같은 커밋에서 복사합니다.

```bash
cp shared/makeup/makeup.v1.json apple/MellowPhoto/Resources/makeup.v1.json
```

두 테스트가 지킵니다.

- `apple/Tests/MellowSharedTests/MakeupCatalogTests.swift`: 이 파일을 읽어 룩·색 id 순서, 값 범위, 룩이 자기 부위 색만 쓰는지, 형식 위반 거부를 확인합니다.
- `apple/MellowPhotoTests/BundledLooksTests.swift`: 앱 번들 사본이 이 파일과 바이트 단위로 같은지 확인합니다.
````

- [ ] **Step 2: 실패하는 테스트 작성**

`apple/Tests/MellowSharedTests/MakeupCatalogTests.swift`:

```swift
import XCTest

@testable import MellowShared

final class MakeupCatalogTests: XCTestCase {
    private func sharedMakeupData() throws -> Data {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("shared/makeup/makeup.v1.json")
        return try Data(contentsOf: url)
    }

    func testSharedCatalogHasFiveLooksAndFixedPalettes() throws {
        let catalog = try MakeupCatalog(data: sharedMakeupData())
        XCTAssertEqual(catalog.looks.map(\.id), MakeupCatalog.builtInLookIDs)
        XCTAssertEqual(MakeupCatalog.builtInLookIDs, ["daily", "cool", "warm-peach", "rosy", "smoky"])
        XCTAssertEqual(catalog.looks.map(\.name), ["데일리", "쿨톤", "웜피치", "로지", "스모키"])
        for part in MakeupPart.allCases {
            XCTAssertEqual(catalog.colors(for: part).map(\.id), MakeupCatalog.builtInColorIDs[part] ?? [], "\(part)")
        }
        XCTAssertEqual(catalog.colors(for: .lip).count, 6)
        XCTAssertEqual(catalog.colors(for: .blush).count, 4)
        XCTAssertEqual(catalog.colors(for: .eyeshadow).count, 4)
        XCTAssertTrue(catalog.colors(for: .brow).isEmpty, "눈썹·쉐딩은 색이 없다")
        XCTAssertEqual(catalog.look(id: "daily")?.name, "데일리")
        XCTAssertNil(catalog.look(id: "nope"))
        XCTAssertNil(catalog.look(id: nil))
        XCTAssertEqual(catalog.color(id: "lip-coral")?.name, "코랄")
        XCTAssertNil(catalog.color(id: "lip-coral", for: .blush), "다른 부위 팔레트에서는 찾지 않는다")
        XCTAssertFalse(catalog.isEmpty)
    }

    func testEveryColorAndLookIsInRangeAndLooksUseTheirOwnPalette() throws {
        let catalog = try MakeupCatalog(data: sharedMakeupData())
        for part in MakeupPart.allCases {
            for color in catalog.colors(for: part) {
                XCTAssertEqual(color.rgb.count, 3, color.id)
                XCTAssertTrue(color.rgb.allSatisfy { (0...1).contains($0) }, color.id)
                XCTAssertEqual([color.red, color.green, color.blue], color.rgb, color.id)
            }
        }
        for look in catalog.looks {
            let adjustments = look.adjustments
            XCTAssertEqual(adjustments.lookID, look.id)
            for part in MakeupPart.allCases {
                XCTAssertTrue((0...1).contains(adjustments.intensity(of: part)), "\(look.id) \(part)")
            }
            XCTAssertNotNil(catalog.color(id: look.lip.colorID, for: .lip), look.id)
            XCTAssertNotNil(catalog.color(id: look.blush.colorID, for: .blush), look.id)
            XCTAssertNotNil(catalog.color(id: look.eyeshadow.colorID, for: .eyeshadow), look.id)
        }
        let daily = try XCTUnwrap(catalog.look(id: "daily"))
        XCTAssertEqual(
            daily.adjustments,
            MakeupAdjustments(
                lookID: "daily", lip: MakeupTint(colorID: "lip-mlbb", intensity: 0.5),
                blush: MakeupTint(colorID: "blush-peach", intensity: 0.35),
                eyeshadow: MakeupTint(colorID: "shadow-brown", intensity: 0.3), brow: MakeupStrength(intensity: 0.3),
                contour: MakeupStrength(intensity: 0.2)))
        XCTAssertEqual(MakeupColor(id: "x", name: "x", rgb: [0.5]).blue, 0, "성분이 모자라면 0")
    }

    func testRejectsUnknownSchemaPartBadRGBForeignColorAndRange() throws {
        let rejected = [
            #"{"schemaVersion":2,"colors":{},"looks":[]}"#,
            #"{"schemaVersion":1,"colors":{"brow":[]},"looks":[]}"#,
            #"{"schemaVersion":1,"colors":{"lip":[{"id":"a","name":"a","rgb":[1.2,0,0]}]},"looks":[]}"#,
            #"{"schemaVersion":1,"colors":{"lip":[{"id":"a","name":"a","rgb":[0.5,0.5]}]},"looks":[]}"#,
            #"{"schemaVersion":1,"colors":{"lip":[{"id":"a","name":"a","rgb":[0,0,0]}],"#
                + #""blush":[{"id":"a","name":"a","rgb":[0,0,0]}]},"looks":[]}"#,
            #"{"schemaVersion":1,"colors":{"lip":[{"id":"a","name":"a","rgb":[0,0,0]}],"#
                + #""blush":[{"id":"b","name":"b","rgb":[0,0,0]}]},"looks":[{"id":"x","name":"x","#
                + #""lip":{"colorID":"b","intensity":0.5},"blush":{"intensity":0},"eyeshadow":{"intensity":0},"#
                + #""brow":{"intensity":0},"contour":{"intensity":0}}]}"#,
            #"{"schemaVersion":1,"colors":{},"looks":[{"id":"x","name":"x","lip":{"intensity":0},"#
                + #""blush":{"intensity":0},"eyeshadow":{"intensity":0},"brow":{"intensity":1.5},"#
                + #""contour":{"intensity":0}}]}"#,
        ]
        for json in rejected {
            XCTAssertThrowsError(try MakeupCatalog(data: Data(json.utf8)), json)
        }
        let minimal = try MakeupCatalog(data: Data(#"{"schemaVersion":1,"colors":{},"looks":[]}"#.utf8))
        XCTAssertTrue(minimal.isEmpty)
        XCTAssertTrue(MakeupCatalog.empty.isEmpty)
        XCTAssertEqual(minimal, MakeupCatalog.empty)
    }
}
```

`apple/MellowPhotoTests/BundledLooksTests.swift`의 `testBundledLooksAreIdenticalToSharedFile` 아래에 추가:

```swift
    func testBundledMakeupIsIdenticalToSharedFile() throws {
        let bundled = try XCTUnwrap(Bundle.main.url(forResource: "makeup.v1", withExtension: "json"))
        let shared = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("shared/makeup/makeup.v1.json")
        XCTAssertEqual(try Data(contentsOf: bundled), try Data(contentsOf: shared))
        XCTAssertEqual(try MakeupCatalog(data: Data(contentsOf: bundled)).looks.count, 5)
    }
```

- [ ] **Step 3: 실패 확인**

Run: `cd apple && swift test --filter MakeupCatalogTests` → 컴파일 실패(`cannot find 'MakeupCatalog' in scope`).

- [ ] **Step 4: 구현**

`apple/Sources/MellowShared/API/MakeupCatalog.swift`:

```swift
import Foundation

/// 메이크업 팔레트의 색 하나. rgb는 sRGB 감마 값 0…1이다(shared/makeup/makeup.v1.json).
public struct MakeupColor: Codable, Equatable, Sendable, Identifiable {
    public var id: String
    public var name: String
    public var rgb: [Double]

    public init(id: String, name: String, rgb: [Double]) {
        self.id = id
        self.name = name
        self.rgb = rgb
    }

    public var red: Double { component(0) }
    public var green: Double { component(1) }
    public var blue: Double { component(2) }

    /// 성분이 모자라면 0. 파일에서 읽은 카탈로그는 3개인지 이미 검사했다.
    private func component(_ index: Int) -> Double {
        rgb.indices.contains(index) ? rgb[index] : 0
    }
}

/// 메이크업 룩 하나. 고르면 부위 값을 레시피에 채운다(스펙 6).
public struct MakeupLook: Codable, Equatable, Sendable, Identifiable {
    public var id: String
    public var name: String
    public var lip: MakeupTint
    public var blush: MakeupTint
    public var eyeshadow: MakeupTint
    public var brow: MakeupStrength
    public var contour: MakeupStrength

    public init(
        id: String, name: String, lip: MakeupTint = .init(), blush: MakeupTint = .init(),
        eyeshadow: MakeupTint = .init(), brow: MakeupStrength = .init(), contour: MakeupStrength = .init()
    ) {
        self.id = id
        self.name = name
        self.lip = lip
        self.blush = blush
        self.eyeshadow = eyeshadow
        self.brow = brow
        self.contour = contour
    }

    /// 이 룩을 고른 레시피의 메이크업 값. lookID는 이 룩의 id다.
    public var adjustments: MakeupAdjustments {
        MakeupAdjustments(lookID: id, lip: lip, blush: blush, eyeshadow: eyeshadow, brow: brow, contour: contour)
    }
}

/// shared/makeup/makeup.v1.json의 팔레트와 룩. LookCatalog와 같은 방식으로 모든 플랫폼이 같은 파일을 읽는다.
public struct MakeupCatalog: Equatable, Sendable {
    public static let currentSchemaVersion = 1
    public static let builtInLookIDs = ["daily", "cool", "warm-peach", "rosy", "smoky"]
    public static let builtInColorIDs: [MakeupPart: [String]] = [
        .lip: ["lip-nude", "lip-coral", "lip-rose", "lip-red", "lip-berry", "lip-mlbb"],
        .blush: ["blush-peach", "blush-pink", "blush-coral", "blush-rose"],
        .eyeshadow: ["shadow-brown", "shadow-peach", "shadow-pink", "shadow-smoky"],
    ]
    public static let empty = MakeupCatalog(looks: [], palettes: [:])
    /// rgb 성분 수.
    private static let rgbComponents = 3

    private struct File: Decodable {
        var schemaVersion: Int
        var colors: [String: [MakeupColor]]
        var looks: [MakeupLook]
    }

    /// 화면 순서의 룩.
    public let looks: [MakeupLook]
    private let palettes: [MakeupPart: [MakeupColor]]

    public init(looks: [MakeupLook], palettes: [MakeupPart: [MakeupColor]]) {
        self.looks = looks
        self.palettes = palettes
    }

    /// 형식이 틀리면 DecodingError를 던진다. 모르는 schemaVersion·부위, rgb가 3개가 아니거나 0…1 밖, 색·룩 id 중복,
    /// 룩이 그 부위 팔레트에 없는 색을 가리키거나 강도가 0…1 밖이면 파일 전체를 거부한다.
    public init(data: Data) throws {
        let file = try JSONDecoder().decode(File.self, from: data)
        guard file.schemaVersion == Self.currentSchemaVersion else {
            throw Self.corrupted("unsupported makeup schemaVersion \(file.schemaVersion)")
        }
        var palettes: [MakeupPart: [MakeupColor]] = [:]
        for (key, colors) in file.colors {
            guard let part = MakeupPart(rawValue: key), part.hasColor else {
                throw Self.corrupted("unknown makeup color part \(key)")
            }
            for color in colors where !Self.isValid(color) {
                throw Self.corrupted("invalid rgb for \(color.id)")
            }
            palettes[part] = colors
        }
        let colorIDs = palettes.values.flatMap { $0.map(\.id) }
        let lookIDs = file.looks.map(\.id)
        guard Set(colorIDs).count == colorIDs.count, Set(lookIDs).count == lookIDs.count else {
            throw Self.corrupted("duplicate makeup id")
        }
        self.init(looks: file.looks, palettes: palettes)
        for look in looks {
            try validate(look)
        }
    }

    public func look(id: String?) -> MakeupLook? {
        guard let id else { return nil }
        return looks.first { $0.id == id }
    }

    /// 화면 순서의 팔레트. 눈썹·쉐딩은 빈 배열이다.
    public func colors(for part: MakeupPart) -> [MakeupColor] {
        palettes[part] ?? []
    }

    /// 어느 부위든 id가 같은 색.
    public func color(id: String?) -> MakeupColor? {
        MakeupPart.allCases.lazy.compactMap { self.color(id: id, for: $0) }.first
    }

    /// part 팔레트 안의 색. 다른 부위의 색 id는 nil이라 렌더가 그 부위를 건너뛴다.
    public func color(id: String?, for part: MakeupPart) -> MakeupColor? {
        guard let id else { return nil }
        return colors(for: part).first { $0.id == id }
    }

    /// 룩도 색도 없으면 true. 앱이 "메이크업 목록을 읽지 못함" 안내를 보일 때 쓴다.
    public var isEmpty: Bool { looks.isEmpty && palettes.values.allSatisfy(\.isEmpty) }

    private static func isValid(_ color: MakeupColor) -> Bool {
        color.rgb.count == rgbComponents && color.rgb.allSatisfy { AdjustmentRange.unit.contains($0) }
    }

    /// 룩의 강도는 0…1이고 색은 그 부위 팔레트에 있어야 한다.
    private func validate(_ look: MakeupLook) throws {
        let tints: [(MakeupPart, MakeupTint)] = [(.lip, look.lip), (.blush, look.blush), (.eyeshadow, look.eyeshadow)]
        for (part, tint) in tints {
            if let id = tint.colorID, color(id: id, for: part) == nil {
                throw Self.corrupted("\(look.id) \(part.rawValue) color \(id) not in palette")
            }
        }
        let intensities = tints.map { $0.1.intensity } + [look.brow.intensity, look.contour.intensity]
        guard intensities.allSatisfy({ AdjustmentRange.unit.contains($0) }) else {
            throw Self.corrupted("\(look.id) intensity out of range")
        }
    }

    private static func corrupted(_ description: String) -> DecodingError {
        DecodingError.dataCorrupted(DecodingError.Context(codingPath: [], debugDescription: description))
    }
}
```

새 리소스를 프로젝트에 넣는다: `cd apple && xcodegen generate --quiet && git status --short MellowPhoto.xcodeproj` → `M MellowPhoto.xcodeproj/project.pbxproj`.

- [ ] **Step 5: 통과 확인**

Run: `cmp shared/makeup/makeup.v1.json apple/MellowPhoto/Resources/makeup.v1.json && echo same` → `same`. `cd apple && swift test` → 모듈별 `Executed 43 tests`(Shared) · `197`(Rendering) · `30`(Library) · `4`(Export) · `27`(Editing), 모두 `with 0 failures`(합 301). lint 출력 없음. `./scripts/verify-modules.sh` 통과. Mac 앱 테스트 → `Executed 62 tests, with 0 failures`. `cd apple && xcodegen generate --quiet && git diff --exit-code --stat MellowPhoto.xcodeproj` → 이 Task 커밋 뒤에는 출력 없음.

- [ ] **Step 6: 커밋**

```bash
git add shared/makeup/makeup.v1.json shared/makeup/README.md apple/MellowPhoto/Resources/makeup.v1.json apple/Sources/MellowShared/API/MakeupCatalog.swift apple/MellowPhoto.xcodeproj apple/Tests/MellowSharedTests/MakeupCatalogTests.swift apple/MellowPhotoTests/BundledLooksTests.swift
git commit -m "feat(shared): 메이크업 팔레트·룩 데이터 파일과 MakeupCatalog

립 6색·블러셔 4색·아이섀도 4색과 룩 5종을 shared/makeup/makeup.v1.json에 두고
앱 번들에 같은 사본을 넣는다. 형식이 틀린 파일은 읽을 때 거부한다.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 2: 편집 규칙 — 메이크업 변경, 룩 적용, 룩 이름 풀기

**Files:**
- Modify: `apple/Sources/MellowShared/API/MakeupAdjustments.swift` (`colorID(of:)`, `setColorID(_:of:)`, `setIntensity(_:of:)`)
- Modify: `apple/Sources/MellowEditing/API/EditChange.swift` (`makeupColor`, `makeupIntensity`)
- Modify: `apple/Sources/MellowEditing/API/EditingPolicy.swift` (`makeupDefaultIntensity`)
- Modify: `apple/Sources/MellowEditing/API/EditDocument.swift` (`set`의 switch, `applyMakeupLook`, `editedMakeup`)
- Test: `apple/Tests/MellowEditingTests/EditDocumentTests.swift`

**Interfaces:**
- Consumes: `MakeupLook.adjustments`(Task 1), `MakeupPart.hasColor`, `MakeupAdjustments.intensity(of:)`.
- Produces: `MakeupAdjustments.colorID(of:) -> String?`(brow·contour는 nil), `setColorID(_:of:)`(brow·contour는 무시), `setIntensity(_:of:)`. `EditChange.makeupColor(MakeupPart, String?)`, `EditChange.makeupIntensity(MakeupPart, Double)`(둘 다 `affectsGeometry == false`). `EditingPolicy.makeupDefaultIntensity`(0.5). `EditDocument.applyMakeupLook(_ look: MakeupLook?)`.

설계 근거: 스펙 6 "룩 적용: 부위 값을 써 넣고 lookID 기록, 체크포인트 1회, 이후 부위 변경은 lookID를 nil로". 값이 실제로 바뀔 때만 lookID를 푼다(같은 값으로 슬라이더를 놓아도 룩이 풀리지 않게). 메이크업은 색만 바꾸므로 수동 편집 잠금 대상이 아니다(스펙 결정 "수동 잡티·변형 편집이 있으면 얼굴형·체형 슬라이더도 잠김"에 메이크업은 없다). 스펙 1.2의 `EditChange.makeupLook(String?)`은 만들지 않는다(편집 규칙은 카탈로그를 모른다, Task 9에서 스펙 문구 수정). 앱 타깃에는 `EditChange`를 전부 나열하는 switch가 없다(E 계획 때 확인) — 앱은 바꾸지 않는다.

- [ ] **Step 1: 실패하는 테스트 작성**

`EditDocumentTests.swift`의 `testBodyShapeIsLockedByLocalEditsLikeFaceShape` 뒤에 추가:

```swift
    func testMakeupChangesClampDetachLookAndAreNotLocked() {
        var document = EditDocument()
        document.appendLocalEdit(.spot(RetouchSpot(x: 0.5, y: 0.5, sourceX: 0.4, sourceY: 0.4, radius: 0.02)))
        XCTAssertFalse(EditChange.makeupIntensity(.lip, 0.5).affectsGeometry)
        XCTAssertFalse(EditChange.makeupColor(.lip, "lip-coral").affectsGeometry)
        XCTAssertNil(document.set(.makeupColor(.lip, "lip-coral")), "메이크업은 수동 편집이 있어도 잠기지 않는다")
        XCTAssertEqual(
            document.recipe.makeup.lip, MakeupTint(colorID: "lip-coral", intensity: EditingPolicy.makeupDefaultIntensity),
            "색을 처음 고르면 기본 강도")
        XCTAssertEqual(EditingPolicy.makeupDefaultIntensity, 0.5)
        XCTAssertNil(document.set(.makeupIntensity(.lip, 1.7)))
        XCTAssertEqual(document.recipe.makeup.lip.intensity, 1)
        XCTAssertNil(document.set(.makeupIntensity(.brow, -0.3)))
        XCTAssertEqual(document.recipe.makeup.brow.intensity, 0)
        document.set(.makeupColor(.lip, "lip-red"))
        XCTAssertEqual(document.recipe.makeup.lip, MakeupTint(colorID: "lip-red", intensity: 1), "강도가 있으면 색만 바꾼다")
        let steps = document.undoStack.count
        document.set(.makeupColor(.brow, "lip-red"))
        XCTAssertEqual(document.undoStack.count, steps, "눈썹은 색이 없어 무시한다")
        XCTAssertNil(document.recipe.makeup.colorID(of: .brow))
        document.set(.makeupColor(.lip, nil))
        XCTAssertEqual(document.recipe.makeup.lip, MakeupTint(colorID: nil, intensity: 1), "색을 빼도 강도는 남는다")
    }

    func testApplyMakeupLookIsOneUndoStepAndPartEditsDetachLook() {
        let look = MakeupLook(
            id: "daily", name: "데일리", lip: MakeupTint(colorID: "lip-mlbb", intensity: 0.5),
            blush: MakeupTint(colorID: "blush-peach", intensity: 0.35),
            eyeshadow: MakeupTint(colorID: "shadow-brown", intensity: 0.3), brow: MakeupStrength(intensity: 0.3),
            contour: MakeupStrength(intensity: 0.2))
        var document = EditDocument()
        document.appendLocalEdit(.warp(WarpStroke(x: 0.5, y: 0.5, dx: 0.01, dy: 0, radius: 0.1)))
        document.set(.makeupIntensity(.brow, 0.9))
        let before = document.undoStack.count
        document.applyMakeupLook(look)
        XCTAssertEqual(document.recipe.makeup, look.adjustments, "잠긴 사진에도 룩을 적용한다")
        XCTAssertEqual(document.recipe.makeup.lookID, "daily")
        XCTAssertEqual(document.undoStack.count, before + 1, "룩 적용은 체크포인트 한 번")
        document.applyMakeupLook(look)
        XCTAssertEqual(document.undoStack.count, before + 1, "같은 룩을 다시 골라도 단계가 늘지 않는다")
        document.set(.makeupIntensity(.blush, 0.35))
        XCTAssertEqual(document.recipe.makeup.lookID, "daily", "값이 그대로면 룩을 유지한다")
        document.set(.makeupIntensity(.blush, 0.6))
        XCTAssertNil(document.recipe.makeup.lookID, "부위를 바꾸면 룩 이름을 지운다")
        XCTAssertEqual(document.recipe.makeup.lip, look.lip, "나머지 부위는 룩 값 그대로")
        document.undo()
        XCTAssertEqual(document.recipe.makeup, look.adjustments)
        document.undo()
        XCTAssertEqual(document.recipe.makeup.brow.intensity, 0.9, "실행 취소 한 번에 룩 적용 전으로")
        XCTAssertNil(document.recipe.makeup.lookID)
        document.redo()
        document.applyMakeupLook(nil)
        XCTAssertEqual(document.recipe.makeup, MakeupAdjustments(), "없음은 메이크업을 모두 지운다")
    }
```

- [ ] **Step 2: 실패 확인**

Run: `cd apple && swift test --filter EditDocumentTests` → 컴파일 실패(`type 'EditChange' has no member 'makeupColor'`, `value of type 'EditDocument' has no member 'applyMakeupLook'`).

- [ ] **Step 3: 구현**

`MakeupAdjustments.swift`의 `intensity(of:)` 아래에 추가:

```swift
    /// 색을 고르는 부위의 색 id. brow·contour는 늘 nil이다.
    public func colorID(of part: MakeupPart) -> String? {
        switch part {
        case .lip: return lip.colorID
        case .blush: return blush.colorID
        case .eyeshadow: return eyeshadow.colorID
        case .brow, .contour: return nil
        }
    }

    /// brow·contour는 색이 없어 무시한다.
    public mutating func setColorID(_ id: String?, of part: MakeupPart) {
        switch part {
        case .lip: lip.colorID = id
        case .blush: blush.colorID = id
        case .eyeshadow: eyeshadow.colorID = id
        case .brow, .contour: break
        }
    }

    public mutating func setIntensity(_ value: Double, of part: MakeupPart) {
        switch part {
        case .lip: lip.intensity = value
        case .blush: blush.intensity = value
        case .eyeshadow: eyeshadow.intensity = value
        case .brow: brow.intensity = value
        case .contour: contour.intensity = value
        }
    }
```

같은 파일 `MakeupAdjustments`의 doc 주석 `/// 메이크업 레시피. lookID는 마지막으로 적용한 룩이다. 렌더와 룩 규칙은 F 단계.`를 `/// 메이크업 레시피. lookID는 마지막으로 적용한 룩이고 부위 값을 바꾸면 비운다(EditDocument).`로 바꾼다.

`EditChange.swift`: `case bodyShape(BodyShapeKey, Double)` 아래에 추가(`affectsGeometry`는 그대로라 false):

```swift
    case makeupColor(MakeupPart, String?)
    case makeupIntensity(MakeupPart, Double)
```

`EditingPolicy.swift`: `bipolarRange` 아래에 추가:

```swift
    /// 메이크업 색을 처음 고를 때 그 부위 강도가 0이면 두는 값. 색 칩을 눌렀는데 아무것도 안 바뀌는 일을 막는다.
    public static let makeupDefaultIntensity = 0.5
```

`EditDocument.swift`:
1. `set` switch의 `case .bodyShape(let key, let value): …` 아래에 추가:

```swift
        case .makeupColor(let part, let id):
            updated.makeup = Self.editedMakeup(updated.makeup) { makeup in
                guard part.hasColor else { return }
                makeup.setColorID(id, of: part)
                if id != nil, makeup.intensity(of: part) == 0 {
                    makeup.setIntensity(EditingPolicy.makeupDefaultIntensity, of: part)
                }
            }
        case .makeupIntensity(let part, let value):
            updated.makeup = Self.editedMakeup(updated.makeup) { makeup in
                makeup.setIntensity(EditingPolicy.clamped(value, to: EditingPolicy.unitRange), of: part)
            }
```

2. `applyAuto` 아래에 추가:

```swift
    /// 룩의 부위 값 다섯 개를 메이크업에 써 넣고 lookID를 기록한다(스펙 6). nil이면 메이크업을 모두 지운다(룩 "없음").
    /// 체크포인트 한 번이다. 색만 바꾸므로 수동 편집이 있어도 잠기지 않는다. 이미 같은 값이면 아무것도 하지 않는다.
    public mutating func applyMakeupLook(_ look: MakeupLook?) {
        let makeup = look?.adjustments ?? MakeupAdjustments()
        guard makeup != recipe.makeup else { return }
        checkpoint()
        recipe.makeup = makeup
    }
```

3. `merged(_:targetFace:)` 아래에 추가:

```swift
    /// 부위 값이 실제로 바뀌었으면 룩 이름을 지운다(스펙 6). 같은 값이면 룩을 유지한다.
    private static func editedMakeup(
        _ previous: MakeupAdjustments, _ change: (inout MakeupAdjustments) -> Void
    ) -> MakeupAdjustments {
        var makeup = previous
        change(&makeup)
        if makeup != previous {
            makeup.lookID = nil
        }
        return makeup
    }
```

4. `applyAuto`의 doc 주석은 이미 "메이크업은 건드리지 않는다"를 말한다. 바꾸지 않는다.

- [ ] **Step 4: 통과 확인**

Run: `cd apple && swift test` → 모듈별 `Executed 43 · 197 · 30 · 4 · 29 tests`, 모두 `with 0 failures`(합 303). lint 출력 없음. `./scripts/verify-modules.sh` 통과. Mac 앱 테스트 → `Executed 62 tests, with 0 failures`.

- [ ] **Step 5: 커밋**

```bash
git add apple/Sources/MellowShared/API/MakeupAdjustments.swift apple/Sources/MellowEditing/API/EditChange.swift apple/Sources/MellowEditing/API/EditingPolicy.swift apple/Sources/MellowEditing/API/EditDocument.swift apple/Tests/MellowEditingTests/EditDocumentTests.swift
git commit -m "feat(editing): 메이크업 색·강도 변경과 룩 적용 규칙

룩은 부위 값을 체크포인트 한 번으로 써 넣고, 부위 값을 바꾸면 룩 이름을 지운다.
색을 처음 고르면 강도 0.5를 두고, 메이크업은 수동 편집이 있어도 잠기지 않는다.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 3: 메이크업 단계와 립 — MakeupStage, 파이프라인 연결, 카탈로그 전달

**Files:**
- Create: `apple/Sources/MellowRendering/Domain/MakeupStage.swift`
- Modify: `apple/Sources/MellowRendering/API/RenderStage.swift` (`RenderContext.makeupCatalog`, 두 init)
- Modify: `apple/Sources/MellowRendering/API/RenderPipeline.swift` (`standard`에 `MakeupStage()`)
- Modify: `apple/Sources/MellowRendering/API/PhotoPipeline.swift` (`makeupCatalog` 보관·전달, `init`)
- Modify: `apple/Sources/MellowRendering/API/RenderTuning.swift` (`makeupLipMaxOpacity`)
- Modify: `apple/Tests/MellowRenderingTests/RenderingTestSupport.swift` (`sharedMakeupCatalog()`)
- Modify: `apple/Tests/MellowRenderingTests/RenderPipelineTests.swift` (`testStageOrderMatters` 이름 배열)
- Test: `apple/Tests/MellowRenderingTests/MakeupStageTests.swift`(새 파일), `apple/Tests/MellowRenderingTests/PhotoPipelineTests.swift`

**Interfaces:**
- Consumes: `MakeupCatalog.color(id:for:)`(Task 1), `MakeupAdjustments.setIntensity(_:of:)`(Task 2), `FaceRegions.lipMask(face:extent:tuning:cache:)`(D), `MaskBuilder.blend(_:over:mask:)`, `RenderContext.targetFaces`·`regionMasks`.
- Produces: `RenderContext.makeupCatalog`(두 init 모두 `makeupCatalog: MakeupCatalog = .empty`, `lookCatalog` 다음 자리). `PhotoPipeline.init(analyzer:personAnalyzer:bodyAnalyzer:tuning:lookCatalog:makeupCatalog:)`(기본 `.empty`). `RenderTuning.makeupLipMaxOpacity`(0.85). internal `struct MakeupStage: RenderStage`(`name == "makeup"`, `static func clamped(_:)`, `static func colorImage(_:part:context:) -> CIImage?`, `static func solid(_ rgb: [Double]) -> CIImage`, `static func mixed(_:over:mask:amount:extent:)`, `static func blended(_:with:mode:in:)`, 섞기 모드 이름 상수 `softLight`·`multiply`·`screen`). 테스트 지원 `RenderingTestSupport.sharedMakeupCatalog()`.

설계 근거: 스펙 1.3 순서 `skin → feature → makeup → background → …`. 입술 생기(feature) 뒤에 립을 얹어 입술 생기가 립 색까지 진하게 하지 않는다. 섞기는 Core Image 기본 모드를 작업 색공간에서 한다(새 커널 언어 경고 없음). 강도 0·얼굴 없음·색 없음·모르는 색은 입력 그대로(오류 아님, D·E와 같은 원칙). 카탈로그는 D 이월대로 `RenderContext`에 기본값 있는 필드로 넣는다.

- [ ] **Step 1: 테스트 지원 코드**

`RenderingTestSupport.swift`의 `sharedLookCatalog()` 아래에 추가:

```swift
    static func sharedMakeupCatalog() throws -> MakeupCatalog {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("shared/makeup/makeup.v1.json")
        return try MakeupCatalog(data: Data(contentsOf: url))
    }
```

- [ ] **Step 2: 실패하는 테스트 작성**

`apple/Tests/MellowRenderingTests/MakeupStageTests.swift`:

```swift
import CoreImage
import MellowShared
import XCTest

@testable import MellowRendering

final class MakeupStageTests: XCTestCase {
    typealias Support = RenderingTestSupport

    private let extent = SyntheticFace.extent

    private func output(
        _ synthetic: SyntheticFace, _ makeup: MakeupAdjustments, faces: [FaceGeometry]? = nil,
        catalog: MakeupCatalog? = nil
    ) throws -> CIImage {
        var recipe = EditRecipe()
        recipe.makeup = makeup
        let resolved = try catalog ?? Support.sharedMakeupCatalog()
        let context = RenderContext(
            extent: extent, recipe: recipe, faces: faces ?? [synthetic.face], tuning: RenderTuning(),
            makeupCatalog: resolved)
        return try MakeupStage().apply(synthetic.image, in: context)
    }

    /// R+G+B 바이트 합.
    private func brightness(_ pixel: [UInt8]) -> Int {
        pixel.prefix(3).reduce(0) { $0 + Int($1) }
    }

    func testZeroIntensityOrNoFacesReturnInputBytes() throws {
        let synthetic = SyntheticFace.makeFeatures()
        let input = try Support.bytes(synthetic.image)
        let named = MakeupAdjustments(lookID: "daily", lip: MakeupTint(colorID: "lip-red", intensity: 0))
        XCTAssertEqual(try Support.bytes(output(synthetic, named)), input, "강도 0이면 입력과 같은 바이트")
        let red = MakeupAdjustments(lip: MakeupTint(colorID: "lip-red", intensity: 1))
        XCTAssertEqual(try Support.bytes(output(synthetic, red, faces: [])), input, "얼굴이 없으면 그대로")
    }

    func testLipColorChangesOnlyTheLipRing() throws {
        let synthetic = SyntheticFace.makeFeatures()
        let before = try Support.grid(synthetic.image)
        let red = try Support.grid(output(synthetic, MakeupAdjustments(lip: MakeupTint(colorID: "lip-red", intensity: 1))))
        XCTAssertNotEqual(red.rgba(SyntheticFace.lipPoint), before.rgba(SyntheticFace.lipPoint), "입술 색이 바뀐다")
        let outside = [
            SyntheticFace.mouth, SyntheticFace.philtrum, SyntheticFace.scleraPoint, SyntheticFace.cheek,
            SyntheticFace.outside,
        ]
        for point in outside {
            XCTAssertEqual(red.rgba(point), before.rgba(point), "입술 마스크 밖 \(point)")
        }
        let coral = try Support.grid(
            output(synthetic, MakeupAdjustments(lip: MakeupTint(colorID: "lip-coral", intensity: 1))))
        XCTAssertNotEqual(coral.rgba(SyntheticFace.lipPoint), red.rgba(SyntheticFace.lipPoint), "색마다 결과가 다르다")
    }

    func testUnknownWrongPartOrMissingCatalogColorAndLandmarklessFaceSkipLip() throws {
        let synthetic = SyntheticFace.makeFeatures()
        let input = try Support.bytes(synthetic.image)
        for id in ["blush-peach", "nope", nil] as [String?] {
            let makeup = MakeupAdjustments(lip: MakeupTint(colorID: id, intensity: 1))
            XCTAssertEqual(try Support.bytes(output(synthetic, makeup)), input, "\(String(describing: id))는 건너뛴다")
        }
        let red = MakeupAdjustments(lip: MakeupTint(colorID: "lip-red", intensity: 1))
        XCTAssertEqual(try Support.bytes(output(synthetic, red, catalog: .empty)), input, "카탈로그가 없으면 립을 건너뛴다")
        let boxOnly = SyntheticFace.make(landmarks: false)
        XCTAssertEqual(try Support.bytes(output(boxOnly, red)), try Support.bytes(boxOnly.image), "특징점 없는 얼굴은 그대로")
    }

    func testOutOfRangeIntensityRendersLikeClampedValues() throws {
        let synthetic = SyntheticFace.makeFeatures()
        func rendered(_ intensity: Double) throws -> [UInt8] {
            try Support.bytes(output(synthetic, MakeupAdjustments(lip: MakeupTint(colorID: "lip-red", intensity: intensity))))
        }
        XCTAssertEqual(try rendered(3), try rendered(1))
        XCTAssertEqual(try rendered(-0.5), try Support.bytes(synthetic.image), "음수는 0")
    }
}
```

`PhotoPipelineTests.swift`의 `testBodyAnalysisFailureSkipsOnlyBodyWarp` 뒤에 추가:

```swift
    func testPreviewAndOriginalPaintMakeupOnlyWithPipelineCatalog() async throws {
        let synthetic = SyntheticFace.makeFeatures()
        let url = try Support.writePNG(synthetic.image, name: "face")
        func bytes(_ image: CGImage) -> [UInt8] { Array(image.dataProvider!.data! as Data) }
        var recipe = EditRecipe()
        recipe.makeup.lip = MakeupTint(colorID: "lip-red", intensity: 1)
        let id = PhotoID()
        let painted = PhotoPipeline(
            analyzer: StubFaceAnalyzer(result: .success([synthetic.face])), tuning: RenderTuning(),
            makeupCatalog: try Support.sharedMakeupCatalog())
        _ = try await painted.prepare(id, at: url)
        let plain = try await painted.preview(id, recipe: EditRecipe())
        let lipped = try await painted.preview(id, recipe: recipe)
        XCTAssertNotEqual(bytes(lipped), bytes(plain), "미리보기에 립이 들어간다")
        let plainOriginal = try await painted.renderOriginal(id, at: url, recipe: EditRecipe(), maxDimension: nil)
        let lippedOriginal = try await painted.renderOriginal(id, at: url, recipe: recipe, maxDimension: nil)
        XCTAssertNotEqual(try Support.bytes(lippedOriginal), try Support.bytes(plainOriginal), "저장에도 립이 들어간다")
        let bare = PhotoPipeline(analyzer: StubFaceAnalyzer(result: .success([synthetic.face])), tuning: RenderTuning())
        _ = try await bare.prepare(id, at: url)
        let skipped = try await bare.preview(id, recipe: recipe)
        XCTAssertEqual(bytes(skipped), bytes(plain), "카탈로그가 없으면 립만 건너뛰고 오류를 던지지 않는다")
    }
```

`RenderPipelineTests.testStageOrderMatters`의 이름 배열을 다음으로 바꾼다:

```swift
            ["skin", "feature", "makeup", "background", "shapeWarp", "localEdit", "geometry", "color", "detail", "look"])
```

- [ ] **Step 3: 실패 확인**

Run: `cd apple && swift test --filter 'MakeupStageTests|PhotoPipelineTests|RenderPipelineTests'` → 컴파일 실패(`cannot find 'MakeupStage' in scope`, `extra argument 'makeupCatalog' in call`).

- [ ] **Step 4: 구현**

`RenderTuning.swift`: `backgroundMaskFeather` 아래에 추가:

```swift
    /// 립 1에서 소프트 라이트 결과를 섞는 비율. 소프트 라이트는 입술 명암을 남겨 1에 가까워도 질감이 유지된다.
    public var makeupLipMaxOpacity: Double = 0.85
```

`RenderStage.swift`:
1. `public let lookCatalog: LookCatalog` 아래에 추가:

```swift
    /// 메이크업 팔레트. 비어 있으면 색을 고르는 부위(립·블러셔·아이섀도)만 빠진다.
    public let makeupCatalog: MakeupCatalog
```

2. 첫 init의 인자 목록과 본문:

```swift
    public init(
        extent: CGRect, recipe: EditRecipe, analysis: PhotoAnalysis, tuning: RenderTuning,
        lookCatalog: LookCatalog = .empty, makeupCatalog: MakeupCatalog = .empty, skipsCrop: Bool = false
    ) {
        self.extent = extent
        self.recipe = recipe
        self.analysis = analysis
        self.tuning = tuning
        self.lookCatalog = lookCatalog
        self.makeupCatalog = makeupCatalog
        self.skipsCrop = skipsCrop
```

(그 아래 `let faces = …`부터는 그대로.)

3. 둘째 init 전체:

```swift
    /// 얼굴·잡티만 있는 분석으로 만든다. 단계 테스트가 쓰는 형태다.
    /// 새 분석 결과는 이 인자 목록에 더하지 않고 PhotoAnalysis에만 더한다.
    public init(
        extent: CGRect, recipe: EditRecipe, faces: [FaceGeometry], tuning: RenderTuning,
        lookCatalog: LookCatalog = .empty, makeupCatalog: MakeupCatalog = .empty, skipsCrop: Bool = false,
        blemishes: [BlemishSpot] = []
    ) {
        self.init(
            extent: extent, recipe: recipe, analysis: PhotoAnalysis(faces: faces, blemishes: blemishes),
            tuning: tuning, lookCatalog: lookCatalog, makeupCatalog: makeupCatalog, skipsCrop: skipsCrop)
    }
```

`PhotoPipeline.swift`:
1. `private let lookCatalog: LookCatalog` 아래에 `private let makeupCatalog: MakeupCatalog`.
2. init:

```swift
    /// personAnalyzer·bodyAnalyzer가 nil이면 그 분석을 하지 않는다(사람 없음과 같다). 앱은 Vision 구현을 넘긴다.
    /// makeupCatalog가 비어 있으면 색을 고르는 메이크업 부위만 빠진다.
    public init(
        analyzer: any FaceAnalyzer, personAnalyzer: (any PersonAnalyzer)? = nil,
        bodyAnalyzer: (any BodyAnalyzer)? = nil, tuning: RenderTuning, lookCatalog: LookCatalog = .empty,
        makeupCatalog: MakeupCatalog = .empty
    ) {
        self.analyzer = analyzer
        self.personAnalyzer = personAnalyzer
        self.bodyAnalyzer = bodyAnalyzer
        self.tuning = tuning
        self.lookCatalog = lookCatalog
        self.makeupCatalog = makeupCatalog
        cache = PreviewCache(capacity: tuning.previewCacheCapacity)
    }
```

3. `preview(_:recipe:showsUncropped:)`의 컨텍스트:

```swift
        let context = RenderContext(
            extent: image.extent, recipe: recipe, analysis: entry.analysis, tuning: tuning, lookCatalog: lookCatalog,
            makeupCatalog: makeupCatalog, skipsCrop: showsUncropped)
```

4. `render(url:recipe:analysis:maxDimension:)`의 컨텍스트:

```swift
        let context = RenderContext(
            extent: image.extent, recipe: recipe, analysis: analysis, tuning: tuning, lookCatalog: lookCatalog,
            makeupCatalog: makeupCatalog)
```

`RenderPipeline.swift`의 `standard`와 그 위 주석:

```swift
    /// 자동 보정이 기반이 되고 수동 편집이 그 위에, 기하가 출력 화면을 정하고, 색감은 마지막에.
    /// 좌표·마스크 기반 단계(피부·눈입·메이크업·배경·얼굴형·수동 편집)는 기하 앞이라 원본 좌표를 쓰고, 비네팅·선명도는 기하 뒤라 잘린 화면을 따른다.
    public static let standard = RenderPipeline(stages: [
        SkinStage(), FeatureStage(), MakeupStage(), BackgroundStage(), ShapeWarpStage(), LocalEditStage(),
        GeometryStage(), ColorStage(), DetailStage(), LookStage(),
    ])
```

`apple/Sources/MellowRendering/Domain/MakeupStage.swift`:

```swift
import CoreImage
import MellowShared

/// 메이크업. 대상 얼굴마다 FaceRegions 마스크 안에서만 색을 얹고 마스크 밖 픽셀은 그대로 둔다(스펙 6).
/// 섞기는 Core Image 기본 섞기 모드를 작업 색공간에서 하고, 강도 = 부위 강도 × 부위 최대 불투명도(RenderTuning)로 원본과 섞는다.
/// 강도는 AdjustmentRange.unit으로 직접 자른다. 프리셋·일괄 적용 값은 편집 규칙의 클램프를 거치지 않는다.
/// 색은 카탈로그의 그 부위 팔레트에서만 찾고, 없거나 모르는 색이면 그 부위만 건너뛴다(오류 아님).
struct MakeupStage: RenderStage {
    let name = "makeup"

    static let softLight = "CISoftLightBlendMode"
    static let multiply = "CIMultiplyBlendMode"
    static let screen = "CIScreenBlendMode"

    func apply(_ image: CIImage, in context: RenderContext) throws -> CIImage {
        let makeup = Self.clamped(context.recipe.makeup)
        guard makeup.hasEffect, !context.targetFaces.isEmpty else { return image }
        var result = image
        for face in context.targetFaces {
            result = paintLips(result, face: face, tint: makeup.lip, context: context)
        }
        return result.cropped(to: context.extent)
    }

    /// 강도를 0…1로 자른다. 유한하지 않은 값은 RenderPipeline이 먼저 거절한다.
    static func clamped(_ makeup: MakeupAdjustments) -> MakeupAdjustments {
        var copy = makeup
        for part in MakeupPart.allCases {
            copy.setIntensity(AdjustmentRange.clamped(makeup.intensity(of: part), to: AdjustmentRange.unit), of: part)
        }
        return copy
    }

    /// 카탈로그의 부위 팔레트 색으로 만든 단색 이미지. 강도 0, 고르지 않음, 모르는 색(다른 부위 색 포함)이면 nil이다.
    static func colorImage(_ tint: MakeupTint, part: MakeupPart, context: RenderContext) -> CIImage? {
        guard tint.intensity > 0, let color = context.makeupCatalog.color(id: tint.colorID, for: part) else {
            return nil
        }
        return solid(color.rgb)
    }

    /// sRGB 감마 값 rgb(성분이 모자라면 0)의 무한 크기 단색 이미지. Core Image가 작업 색공간으로 바꾼다.
    static func solid(_ rgb: [Double]) -> CIImage {
        func component(_ index: Int) -> Double { rgb.indices.contains(index) ? rgb[index] : 0 }
        return CIImage(color: CIColor(red: component(0), green: component(1), blue: component(2)))
    }

    /// color를 image 위에 섞기 모드 mode로 얹은 결과를 bounds 안에서만 만든다.
    static func blended(_ image: CIImage, with color: CIImage, mode: String, in bounds: CGRect) -> CIImage {
        color.cropped(to: bounds).applyingFilter(mode, parameters: [kCIInputBackgroundImageKey: image])
            .cropped(to: bounds)
    }

    /// foreground를 마스크 × amount 비율로 image 위에 섞는다. 마스크가 정확히 0인 곳(bounds 밖 포함)은 image 바이트 그대로다.
    static func mixed(
        _ foreground: CIImage, over image: CIImage, mask: FaceRegions.RegionMask, amount: Double, extent: CGRect
    ) -> CIImage {
        let scaled = mask.image.applyingFilter(
            "CIColorMatrix",
            parameters: [
                "inputRVector": CIVector(x: amount, y: 0, z: 0, w: 0),
                "inputGVector": CIVector(x: 0, y: amount, z: 0, w: 0),
                "inputBVector": CIVector(x: 0, y: 0, z: amount, w: 0),
            ])
        return MaskBuilder.blend(foreground.cropped(to: mask.bounds), over: image, mask: scaled).cropped(to: extent)
    }

    /// 입술(바깥 − 안쪽)에 고른 색을 소프트 라이트로 얹는다. 소프트 라이트는 입술 명암(질감)을 남긴다.
    private func paintLips(_ image: CIImage, face: FaceGeometry, tint: MakeupTint, context: RenderContext) -> CIImage {
        guard let color = Self.colorImage(tint, part: .lip, context: context),
            let lips = FaceRegions.lipMask(
                face: face, extent: context.extent, tuning: context.tuning, cache: context.regionMasks)
        else { return image }
        let lit = Self.blended(image, with: color, mode: Self.softLight, in: lips.bounds)
        let amount = tint.intensity * context.tuning.makeupLipMaxOpacity
        return Self.mixed(lit, over: image, mask: lips, amount: amount, extent: context.extent)
    }
}
```

- [ ] **Step 5: 통과 확인**

Run: `cd apple && swift test` → 모듈별 `Executed 43 · 202 · 30 · 4 · 29 tests`, 모두 `with 0 failures`(합 308). 기존 렌더 테스트(메이크업 값이 없는 레시피)는 바이트가 바뀌지 않아야 한다(바뀌면 `apply`의 이른 반환을 확인). lint 출력 없음. `./scripts/verify-modules.sh` 통과. Mac 앱 테스트 → `Executed 62 tests, with 0 failures`(앱은 아직 카탈로그를 넘기지 않아 메이크업이 빠진다, Task 8).

- [ ] **Step 6: 커밋**

```bash
git add apple/Sources/MellowRendering/Domain/MakeupStage.swift apple/Sources/MellowRendering/API/RenderStage.swift apple/Sources/MellowRendering/API/RenderPipeline.swift apple/Sources/MellowRendering/API/PhotoPipeline.swift apple/Sources/MellowRendering/API/RenderTuning.swift apple/Tests/MellowRenderingTests/RenderingTestSupport.swift apple/Tests/MellowRenderingTests/RenderPipelineTests.swift apple/Tests/MellowRenderingTests/MakeupStageTests.swift apple/Tests/MellowRenderingTests/PhotoPipelineTests.swift
git commit -m "feat(rendering): 메이크업 단계와 립 색, 렌더 컨텍스트에 메이크업 카탈로그

눈·입 보정 다음, 배경 흐림 앞에 메이크업 단계를 두고 입술 마스크 안에만
고른 립 색을 소프트 라이트로 얹는다. 색이 없거나 모르면 립만 건너뛴다.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 4: 블러셔와 아이섀도 — 기운 타원 마스크, 눈꺼풀 띠 마스크

**Files:**
- Create: `apple/Sources/MellowRendering/Domain/FaceRegions+Makeup.swift`
- Modify: `apple/Sources/MellowRendering/Domain/FaceRegions.swift` (`skinPolygonRaster` 추출, `featheredPolygonMask`·`featherRadius`·`boundingRect`·`boundsPaddingInFeathers` 공개 범위, `feather` 인자)
- Modify: `apple/Sources/MellowRendering/Domain/MaskBuilder.swift` (돌린 타원)
- Modify: `apple/Sources/MellowRendering/Domain/MakeupStage.swift` (`paintBlush`, `shadeEyelids`)
- Modify: `apple/Sources/MellowRendering/API/RenderTuning.swift`
- Modify: `apple/Tests/MellowRenderingTests/RenderingTestSupport.swift` (메이크업 표본 점)
- Test: `apple/Tests/MellowRenderingTests/MakeupRegionsTests.swift`(새 파일), `apple/Tests/MellowRenderingTests/MakeupStageTests.swift`

**Interfaces:**
- Consumes: `FaceFrame`(`init?(face:extent:)`, `origin`, `xAxis`, `faceWidth`, `eyeLevel`, `mouthLevel`, `eyes`, `local(_:)`, `imagePoint(u:v:)`, `static centroid(_:)`), `FaceRegions.skinPolygon`·`protectedPolygons`·`polygonMask`·`eyePolygons`·`landmarkPolygon`, `MakeupStage.colorImage`·`blended`·`mixed`(Task 3).
- Produces: `MaskBuilder.ellipse(center:radii:angle:extent:strength:)`. `FaceRegions.skinPolygonRaster(face:extent:tuning:cache:)`. `FaceRegions.featheredPolygonMask(fill:cut:face:extent:tuning:cache:feather:)`(internal, `feather: CGFloat? = nil` = 기존 눈·입 흐림). `FaceRegions.Oval`(`center`, `radii`), `blushMask(face:extent:tuning:cache:) -> RegionMask?`, `eyeshadowMask(face:extent:tuning:cache:) -> RegionMask?`, `lidPolygon(eye:brows:frame:) -> [CGPoint]?`, `softMask(_:face:frame:extent:tuning:cache:) -> RegionMask?`. `RenderTuning.makeupBlushMaxOpacity`(0.6), `makeupEyeshadowMaxOpacity`(0.45), `makeupEyeshadowFeather`(0.008). 테스트 지원 `SyntheticFace.leftBlush`·`rightBlush`·`rolledLeftBlush`·`rolledRightBlush`·`rolledLidSkin`.

설계 근거:
- **얼굴 좌표.** 모든 위치를 `FaceFrame`(원점 = 얼굴 상자 중심, x축 = 두 눈동자 방향, y축 = 입 → 눈)에서 정해 기울어진 얼굴을 따라간다. 윤곽점이 없으면 `FaceFrame`이 nil이라 메이크업 부위가 빠진다(특징점 없는 얼굴은 건너뜀, D와 같은 원칙).
- **블러셔.** 눈마다 중심 u = 눈동자 u × 1.15, v = 입 높이 + (눈 높이 − 입 높이) × 0.45, 반지름 (얼굴 폭 × 0.13, × 0.085), 얼굴 x축으로 돌린 `MaskBuilder` 타원(가운데 65%까지 1, 가장자리에서 0 — 넓은 경계). 피부 다각형 비트맵(윤곽 + 이마 − 넓힌 눈·눈썹·입술)을 곱해 눈·입·얼굴 밖에는 닿지 않는다. 피부 보정과 같은 비트맵 키라 캐시가 늘지 않는다. 합성 얼굴(얼굴 폭 280, 중심 (256, 200), 눈동자 u ±56, 눈 높이 100, 입 높이 −60)에서 중심은 (191.6, 212)·(320.4, 212)다.
- **아이섀도.** 눈마다 윗눈꺼풀 선(눈 다각형 중 중심보다 위인 점, 얼굴 x 순서)과 그 선을 위로 올리고 양옆으로 10% 넓힌 선으로 닫은 띠. 올리는 양은 가장 가까운 눈썹 아래끝까지 거리의 75%, 눈썹이 없거나 눈보다 아래면 눈 높이. 눈 다각형을 빼고 얼굴 폭 × 0.008로 흐린다. 합성 얼굴 왼눈은 윗선 y 314, 눈썹 아래 332라 띠 윗선 y 327.5이고 `lidSkin`(200, 324)이 띠 안이다.
- **섞기.** 블러셔는 소프트 라이트, 아이섀도는 곱하기(스펙 6).

- [ ] **Step 1: 테스트 지원 코드**

`RenderingTestSupport.swift`의 `extension SyntheticFace { … }`(흰자·홍채·치아) 블록 뒤에 추가:

```swift
/// 메이크업 영역 표본 점. 얼굴 좌표(원점 (256, 200), 얼굴 폭 280, 눈 높이 100, 입 높이 −60)에서 계산한 위치다.
extension SyntheticFace {
    /// 블러셔 중심. u = 눈동자 u ±56 × 1.15, v = −60 + 160 × 0.45 = 12.
    static let leftBlush = CGPoint(x: 191.6, y: 212)
    static let rightBlush = CGPoint(x: 320.4, y: 212)
    /// 얼굴을 중심 둘레로 30° 돌렸을 때의 블러셔 중심과 lidSkin 자리.
    static let rolledLeftBlush = CGPoint(x: 194.2, y: 178.2)
    static let rolledRightBlush = CGPoint(x: 305.8, y: 242.6)
    static let rolledLidSkin = CGPoint(x: 145.5, y: 279.4)
}
```

- [ ] **Step 2: 실패하는 테스트 작성**

`apple/Tests/MellowRenderingTests/MakeupRegionsTests.swift`:

```swift
import CoreImage
import MellowShared
import XCTest

@testable import MellowRendering

final class MakeupRegionsTests: XCTestCase {
    typealias Support = RenderingTestSupport

    private let extent = SyntheticFace.extent
    private let tuning = RenderTuning()

    func testBlushMaskSitsOnBothCheeksInsideTheFace() throws {
        let face = SyntheticFace.make().face
        let mask = try XCTUnwrap(FaceRegions.blushMask(face: face, extent: extent, tuning: tuning))
        XCTAssertEqual(mask.image.extent, extent)
        let pixels = try Support.grid(mask.image)
        XCTAssertGreaterThan(pixels.red(SyntheticFace.leftBlush), 200)
        XCTAssertGreaterThan(pixels.red(SyntheticFace.rightBlush), 200)
        XCTAssertEqual(
            Double(pixels.red(SyntheticFace.leftBlush)), Double(pixels.red(SyntheticFace.rightBlush)), accuracy: 2,
            "좌우 대칭")
        XCTAssertGreaterThan(pixels.red(SyntheticFace.cheek), 128, "볼 표본 점도 덮는다")
        let outside = [
            SyntheticFace.leftEye, SyntheticFace.mouth, SyntheticFace.lipPoint, SyntheticFace.forehead,
            SyntheticFace.outside,
        ]
        for point in outside {
            XCTAssertEqual(pixels.red(point), 0, "블러셔 밖 \(point)")
        }
        XCTAssertFalse(mask.bounds.contains(SyntheticFace.leftEye), "눈은 계산 영역 밖")
    }

    func testEyeshadowMaskCoversTheLidAndLeavesEyesAndCheeks() throws {
        let face = SyntheticFace.makeFeatures().face
        let mask = try XCTUnwrap(FaceRegions.eyeshadowMask(face: face, extent: extent, tuning: tuning))
        let pixels = try Support.grid(mask.image)
        XCTAssertGreaterThan(pixels.red(SyntheticFace.lidSkin), 128, "눈과 눈썹 사이 눈꺼풀")
        let outside = [
            SyntheticFace.leftEye, SyntheticFace.scleraPoint, SyntheticFace.cheek, SyntheticFace.forehead,
            SyntheticFace.mouth,
        ]
        for point in outside {
            XCTAssertEqual(pixels.red(point), 0, "아이섀도 밖 \(point)")
        }
    }

    func testBlushAndEyeshadowFollowARolledFace() throws {
        let rolled = SyntheticFace.makeFeatures().face.rotated(by: .pi / 6, about: SyntheticFace.pivot)
        let blush = try Support.grid(XCTUnwrap(FaceRegions.blushMask(face: rolled, extent: extent, tuning: tuning)).image)
        XCTAssertGreaterThan(blush.red(SyntheticFace.rolledLeftBlush), 200)
        XCTAssertGreaterThan(blush.red(SyntheticFace.rolledRightBlush), 200)
        let lids = try Support.grid(
            XCTUnwrap(FaceRegions.eyeshadowMask(face: rolled, extent: extent, tuning: tuning)).image)
        XCTAssertGreaterThan(lids.red(SyntheticFace.rolledLidSkin), 128)
        XCTAssertEqual(lids.red(SyntheticFace.lidSkin), 0, "돌리기 전 눈꺼풀 자리는 비어 있다")
    }

    func testMakeupMasksNeedLandmarks() {
        let boxOnly = SyntheticFace.make(landmarks: false).face
        XCTAssertNil(FaceRegions.blushMask(face: boxOnly, extent: extent, tuning: tuning))
        XCTAssertNil(FaceRegions.eyeshadowMask(face: boxOnly, extent: extent, tuning: tuning))
        let browless = SyntheticFace.makeFeatures().face.removing([.leftEyebrow, .rightEyebrow])
        XCTAssertNotNil(
            FaceRegions.eyeshadowMask(face: browless, extent: extent, tuning: tuning), "눈썹이 없으면 눈 높이만큼 올린다")
        let eyeless = SyntheticFace.makeFeatures().face.removing([.leftEye, .rightEye, .leftPupil, .rightPupil])
        XCTAssertNil(FaceRegions.blushMask(face: eyeless, extent: extent, tuning: tuning), "두 눈이 없으면 볼 위치를 정하지 않는다")
        XCTAssertNil(FaceRegions.eyeshadowMask(face: eyeless, extent: extent, tuning: tuning))
    }
}
```

`MakeupStageTests.swift` 맨 아래(`testOutOfRangeIntensityRendersLikeClampedValues` 뒤)에 추가:

```swift
    func testBlushTintsCheeksOnly() throws {
        let synthetic = SyntheticFace.makeFeatures()
        let before = try Support.grid(synthetic.image)
        let after = try Support.grid(
            output(synthetic, MakeupAdjustments(blush: MakeupTint(colorID: "blush-pink", intensity: 1))))
        XCTAssertNotEqual(after.rgba(SyntheticFace.cheek), before.rgba(SyntheticFace.cheek), "볼 색이 바뀐다")
        let outside = [
            SyntheticFace.outside, SyntheticFace.mouth, SyntheticFace.lipPoint, SyntheticFace.scleraPoint,
            SyntheticFace.forehead,
        ]
        for point in outside {
            XCTAssertEqual(after.rgba(point), before.rgba(point), "블러셔 밖 \(point)")
        }
    }

    func testEyeshadowDarkensTheLidOnly() throws {
        let synthetic = SyntheticFace.makeFeatures()
        let before = try Support.grid(synthetic.image)
        let after = try Support.grid(
            output(synthetic, MakeupAdjustments(eyeshadow: MakeupTint(colorID: "shadow-smoky", intensity: 1))))
        XCTAssertLessThanOrEqual(
            brightness(after.rgba(SyntheticFace.lidSkin)), brightness(before.rgba(SyntheticFace.lidSkin)) - 15,
            "눈꺼풀이 어두워진다")
        for point in [SyntheticFace.scleraPoint, SyntheticFace.leftEye, SyntheticFace.cheek, SyntheticFace.lipPoint] {
            XCTAssertEqual(after.rgba(point), before.rgba(point), "아이섀도 밖 \(point)")
        }
    }
```

- [ ] **Step 3: 실패 확인**

Run: `cd apple && swift test --filter 'MakeupRegionsTests|MakeupStageTests'` → 컴파일 실패(`type 'FaceRegions' has no member 'blushMask'`).

- [ ] **Step 4: 구현**

`RenderTuning.swift`: `makeupLipMaxOpacity` 아래에 추가:

```swift
    /// 블러셔 1에서 소프트 라이트 결과를 섞는 비율.
    public var makeupBlushMaxOpacity: Double = 0.6
    /// 아이섀도 1에서 곱하기 결과를 섞는 비율. 곱하기는 진하게 어두워져 립보다 낮게 둔다.
    public var makeupEyeshadowMaxOpacity: Double = 0.45
    /// 아이섀도 띠를 흐리는 반지름. 얼굴 폭 비율. 300px 얼굴에서 2.4px라 눈 안쪽까지 번지지 않는다.
    public var makeupEyeshadowFeather: Double = 0.008
```

`MaskBuilder.swift`: `ellipse(_:extent:strength:)`를 다음 세 함수로 바꾼다(기존 함수의 결과는 바이트 그대로):

```swift
    /// 중심 0.65까지 strength, 가장자리 1.0에서 0으로 떨어지는 타원.
    /// 단위 원을 확대하면 Core Image가 같은 그라데이션을 한 번 그려 크기가 다른 타원끼리 재사용하므로
    /// 큰 타원이 뭉개진다. 그래서 가로 반지름 픽셀 크기로 그리고 세로만 늘린다.
    static func ellipse(_ rect: CGRect, extent: CGRect, strength: Double = 1) -> CIImage {
        unbounded(rect, strength: strength).cropped(to: extent)
    }

    /// center 둘레로 angle(라디안, 반시계)만큼 돌린 타원. radii.width가 돌린 x축 방향 반지름이고 경계 모양은 ellipse와 같다.
    static func ellipse(center: CGPoint, radii: CGSize, angle: CGFloat, extent: CGRect, strength: Double = 1) -> CIImage {
        let rect = CGRect(
            x: center.x - radii.width, y: center.y - radii.height, width: radii.width * 2, height: radii.height * 2)
        let turn = CGAffineTransform(translationX: center.x, y: center.y).rotated(by: angle)
            .translatedBy(x: -center.x, y: -center.y)
        return unbounded(rect, strength: strength).transformed(by: turn).cropped(to: extent)
    }

    /// 자르지 않은 타원. 반지름 밖은 검정(0)이다.
    private static func unbounded(_ rect: CGRect, strength: Double) -> CIImage {
        let radiusX = max(1, rect.width / 2)
        let radiusY = max(1, rect.height / 2)
        let gradient = CIFilter(
            name: "CIRadialGradient",
            parameters: [
                "inputCenter": CIVector(x: rect.midX, y: rect.midY),
                "inputRadius0": solidRadius * radiusX,
                "inputRadius1": fadeRadius * radiusX,
                "inputColor0": CIColor(red: strength, green: strength, blue: strength),
                "inputColor1": CIColor.black,
            ])!.outputImage!
        let stretch = CGAffineTransform(translationX: rect.midX, y: rect.midY)
            .scaledBy(x: 1, y: radiusY / radiusX)
            .translatedBy(x: -rect.midX, y: -rect.midY)
        return gradient.transformed(by: stretch)
    }
```

`FaceRegions.swift`:
1. `private static let boundsPaddingInFeathers: CGFloat = 4` → `static let boundsPaddingInFeathers: CGFloat = 4`.
2. `skinMask`의 첫 줄들을 바꾼다(`let cutWidth = …`와 `var mask = polygonMask(…)` 네 줄을 지우고 한 줄로):

```swift
        var mask = skinPolygonRaster(face: face, extent: extent, tuning: tuning, cache: cache)
```

3. `maskBounds` 위에 추가:

```swift
    /// 피부 다각형(윤곽 + 이마 호)에서 넓힌 눈·눈썹·입술을 뺀 비트맵(흐리기 전). skinMask와 메이크업 마스크가 같은 캐시 항목을 쓴다.
    static func skinPolygonRaster(face: FaceGeometry, extent: CGRect, tuning: RenderTuning, cache: RegionMaskCache?)
        -> CIImage
    {
        let cutWidth = faceWidth(face, extent: extent) * CGFloat(tuning.skinFeatureFeather) * 2
        return polygonMask(
            fill: [skinPolygon(face: face, extent: extent, tuning: tuning)],
            cut: protectedPolygons(face: face, extent: extent), cutWidth: cutWidth, extent: extent, tuning: tuning,
            cache: cache)
    }
```

4. `featheredPolygonMask`를 다음으로 바꾼다(`private` 제거, `feather` 인자):

```swift
    /// 다각형 마스크를 feather(기본은 얼굴 폭 × featureMaskFeather)로 흐리고 경계 상자 + 흐림 4배 여백 밖을 0으로 자른다.
    /// cut은 넓히지 않는다(featureCutWidth).
    static func featheredPolygonMask(
        fill: [[CGPoint]], cut: [[CGPoint]], face: FaceGeometry, extent: CGRect, tuning: RenderTuning,
        cache: RegionMaskCache?, feather: CGFloat? = nil
    ) -> RegionMask? {
        let feather =
            feather
            ?? max(
                CGFloat(tuning.skinBlurMinimumRadius),
                faceWidth(face, extent: extent) * CGFloat(tuning.featureMaskFeather))
        let padding = feather * boundsPaddingInFeathers
        let bounds = boundingRect(fill.flatMap { $0 }).insetBy(dx: -padding, dy: -padding).intersection(extent).integral
        guard !bounds.isEmpty else { return nil }
        let raster = polygonMask(
            fill: fill, cut: cut, cutWidth: featureCutWidth, extent: extent, tuning: tuning, cache: cache)
        let black = CIImage(color: .black).cropped(to: extent)
        let image = raster.clampedToExtent()
            .applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: feather])
            .cropped(to: bounds).composited(over: black)
        return RegionMask(image: image, bounds: bounds)
    }
```

5. `private static func featherRadius(…)` → `static func featherRadius(…)`, `private static func boundingRect(…)` → `static func boundingRect(…)`.

`apple/Sources/MellowRendering/Domain/FaceRegions+Makeup.swift`:

```swift
import CoreImage
import MellowShared

/// 메이크업 영역 위치 비율. 길이는 얼굴 폭, 높이는 얼굴 좌표(FaceFrame)의 입 높이·눈 높이 기준이다.
private enum MakeupShape {
    /// 블러셔 중심의 가로 위치. 눈동자 u의 배수(눈보다 조금 바깥).
    static let blushOutward: CGFloat = 1.15
    /// 블러셔 중심 높이. 입 높이 → 눈 높이 사이의 비율(코 옆 볼).
    static let blushHeight: CGFloat = 0.45
    /// 블러셔 타원 반지름(얼굴 x축·y축 방향). 얼굴 폭 비율.
    static let blushRadiusU: CGFloat = 0.13
    static let blushRadiusV: CGFloat = 0.085
    /// 아이섀도 띠를 올리는 양. 윗눈꺼풀에서 눈썹 아래끝까지 거리의 비율.
    static let eyeshadowRise: CGFloat = 0.75
    /// 눈썹이 없을 때 올리는 양. 눈 높이의 배수.
    static let eyeshadowRiseWithoutBrow: CGFloat = 1
    /// 띠 윗선을 양옆으로 넓히는 비율. 눈 폭 대비.
    static let eyeshadowSpread: CGFloat = 0.1
    /// 다각형이 되려면 필요한 윗눈꺼풀 점 수.
    static let minimumLidPoints = 2
}

extension FaceRegions {
    /// 얼굴 x축 방향으로 돌려 그리는 타원 하나(픽셀).
    struct Oval {
        let center: CGPoint
        let radii: CGSize
    }

    /// 볼 블러셔 영역. 두 눈 아래·코 옆의 기운 타원 × 피부 다각형. 윤곽점이나 두 눈이 없으면 nil.
    static func blushMask(face: FaceGeometry, extent: CGRect, tuning: RenderTuning, cache: RegionMaskCache? = nil)
        -> RegionMask?
    {
        guard let frame = FaceFrame(face: face, extent: extent), frame.eyes.count == 2 else { return nil }
        let width = frame.faceWidth
        let level = frame.mouthLevel + (frame.eyeLevel - frame.mouthLevel) * MakeupShape.blushHeight
        let radii = CGSize(width: width * MakeupShape.blushRadiusU, height: width * MakeupShape.blushRadiusV)
        let ovals = frame.eyes.map { eye in
            Oval(center: frame.imagePoint(u: frame.local(eye.center).x * MakeupShape.blushOutward, v: level), radii: radii)
        }
        return softMask(ovals, face: face, frame: frame, extent: extent, tuning: tuning, cache: cache)
    }

    /// 아이섀도 영역. 눈마다 윗눈꺼풀 띠(lidPolygon)에서 눈 다각형을 빼고 얼굴 폭 × makeupEyeshadowFeather로 흐린다.
    /// 윤곽점이나 눈 다각형이 없으면 nil.
    static func eyeshadowMask(face: FaceGeometry, extent: CGRect, tuning: RenderTuning, cache: RegionMaskCache? = nil)
        -> RegionMask?
    {
        guard let frame = FaceFrame(face: face, extent: extent) else { return nil }
        let eyes = eyePolygons(face: face, extent: extent)
        let brows = [FaceLandmark.leftEyebrow, .rightEyebrow].compactMap { landmarkPolygon(face, $0, extent) }
        let lids = eyes.compactMap { lidPolygon(eye: $0, brows: brows, frame: frame) }
        guard !lids.isEmpty else { return nil }
        let feather = max(
            CGFloat(tuning.skinBlurMinimumRadius), frame.faceWidth * CGFloat(tuning.makeupEyeshadowFeather))
        return featheredPolygonMask(
            fill: lids, cut: eyes, face: face, extent: extent, tuning: tuning, cache: cache, feather: feather)
    }

    /// 윗눈꺼풀 선(눈 다각형 중 중심보다 위인 점, 얼굴 x 순서)과 그 선을 올리고 양옆으로 넓힌 선으로 닫은 다각형(픽셀).
    /// 올리는 양은 가로로 가장 가까운 눈썹의 아래끝까지 거리 × eyeshadowRise, 눈썹이 없거나 눈보다 아래면 눈 높이 × eyeshadowRiseWithoutBrow.
    static func lidPolygon(eye: [CGPoint], brows: [[CGPoint]], frame: FaceFrame) -> [CGPoint]? {
        let local = eye.map(frame.local)
        let center = FaceFrame.centroid(local)
        let upper = local.filter { $0.y >= center.y }.sorted { $0.x < $1.x }
        guard upper.count >= MakeupShape.minimumLidPoints, let top = local.map(\.y).max(),
            let bottom = local.map(\.y).min()
        else { return nil }
        let nearest = brows.map { $0.map(frame.local) }
            .min { abs(FaceFrame.centroid($0).x - center.x) < abs(FaceFrame.centroid($1).x - center.x) }
        let browBottom = nearest.flatMap { $0.map(\.y).min() }
        var rise = (top - bottom) * MakeupShape.eyeshadowRiseWithoutBrow
        if let browBottom, browBottom > top {
            rise = (browBottom - top) * MakeupShape.eyeshadowRise
        }
        let spread = 1 + MakeupShape.eyeshadowSpread
        let lifted = upper.reversed().map { point in
            CGPoint(x: center.x + (point.x - center.x) * spread, y: point.y + rise)
        }
        return (upper + lifted).map { frame.imagePoint(u: $0.x, v: $0.y) }
    }

    /// 얼굴 x축으로 돌린 타원들의 최대 × 피부 다각형 비트맵을 피부 마스크와 같은 반지름으로 흐린다.
    /// 타원 경계 상자 + 흐림 4배 여백 밖은 정확히 0이다. 타원이 없으면 nil.
    static func softMask(
        _ ovals: [Oval], face: FaceGeometry, frame: FaceFrame, extent: CGRect, tuning: RenderTuning,
        cache: RegionMaskCache?
    ) -> RegionMask? {
        let feather = featherRadius(face, extent, tuning)
        let padding = feather * boundsPaddingInFeathers
        let reach = ovals.map { oval -> CGRect in
            let side = max(oval.radii.width, oval.radii.height)
            return CGRect(x: oval.center.x - side, y: oval.center.y - side, width: side * 2, height: side * 2)
        }
        .reduce(CGRect.null) { $0.union($1) }
        let bounds = reach.insetBy(dx: -padding, dy: -padding).intersection(extent).integral
        guard !ovals.isEmpty, !bounds.isEmpty else { return nil }
        let angle = atan2(frame.xAxis.dy, frame.xAxis.dx)
        let black = CIImage(color: .black).cropped(to: extent)
        var shapes = black
        for oval in ovals {
            shapes = MaskBuilder.ellipse(center: oval.center, radii: oval.radii, angle: angle, extent: extent)
                .applyingFilter("CIMaximumCompositing", parameters: [kCIInputBackgroundImageKey: shapes])
        }
        let skin = skinPolygonRaster(face: face, extent: extent, tuning: tuning, cache: cache)
        let image = shapes.applyingFilter("CIMultiplyCompositing", parameters: [kCIInputBackgroundImageKey: skin])
            .clampedToExtent()
            .applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: feather])
            .cropped(to: bounds).composited(over: black)
        return RegionMask(image: image, bounds: bounds)
    }
}
```

`MakeupStage.swift`:
1. `apply`의 얼굴 반복을 다음으로 바꾼다:

```swift
        for face in context.targetFaces {
            result = paintBlush(result, face: face, tint: makeup.blush, context: context)
            result = shadeEyelids(result, face: face, tint: makeup.eyeshadow, context: context)
            result = paintLips(result, face: face, tint: makeup.lip, context: context)
        }
```

2. `paintLips` 위에 추가:

```swift
    /// 볼에 고른 색을 소프트 라이트로 얹는다.
    private func paintBlush(_ image: CIImage, face: FaceGeometry, tint: MakeupTint, context: RenderContext) -> CIImage {
        guard let color = Self.colorImage(tint, part: .blush, context: context),
            let cheeks = FaceRegions.blushMask(
                face: face, extent: context.extent, tuning: context.tuning, cache: context.regionMasks)
        else { return image }
        let lit = Self.blended(image, with: color, mode: Self.softLight, in: cheeks.bounds)
        let amount = tint.intensity * context.tuning.makeupBlushMaxOpacity
        return Self.mixed(lit, over: image, mask: cheeks, amount: amount, extent: context.extent)
    }

    /// 눈꺼풀에 고른 색을 곱한다.
    private func shadeEyelids(_ image: CIImage, face: FaceGeometry, tint: MakeupTint, context: RenderContext)
        -> CIImage
    {
        guard let color = Self.colorImage(tint, part: .eyeshadow, context: context),
            let lids = FaceRegions.eyeshadowMask(
                face: face, extent: context.extent, tuning: context.tuning, cache: context.regionMasks)
        else { return image }
        let shaded = Self.blended(image, with: color, mode: Self.multiply, in: lids.bounds)
        let amount = tint.intensity * context.tuning.makeupEyeshadowMaxOpacity
        return Self.mixed(shaded, over: image, mask: lids, amount: amount, extent: context.extent)
    }
```

- [ ] **Step 5: 통과 확인**

Run: `cd apple && swift test` → 모듈별 `Executed 43 · 208 · 30 · 4 · 29 tests`, 모두 `with 0 failures`(합 314). 피부 보정·눈·입 기존 테스트가 그대로 통과해야 한다(`skinPolygonRaster` 추출과 `featheredPolygonMask` 기본 흐림은 결과가 같다). 표본 점 단언이 1~2 차이로 실패하면 표본 점 좌표를 계산 근거대로 다시 확인하고, 고친 근거를 커밋 본문에 적는다(임계값을 느슨하게 바꾸지 않는다). lint 출력 없음. `./scripts/verify-modules.sh` 통과. Mac 앱 테스트 → `Executed 62 tests, with 0 failures`.

- [ ] **Step 6: 커밋**

```bash
git add apple/Sources/MellowRendering/Domain/FaceRegions+Makeup.swift apple/Sources/MellowRendering/Domain/FaceRegions.swift apple/Sources/MellowRendering/Domain/MaskBuilder.swift apple/Sources/MellowRendering/Domain/MakeupStage.swift apple/Sources/MellowRendering/API/RenderTuning.swift apple/Tests/MellowRenderingTests/RenderingTestSupport.swift apple/Tests/MellowRenderingTests/MakeupRegionsTests.swift apple/Tests/MellowRenderingTests/MakeupStageTests.swift
git commit -m "feat(rendering): 블러셔·아이섀도 영역과 메이크업 단계 연결

블러셔는 얼굴 좌표의 기운 볼 타원 × 피부 다각형, 아이섀도는 윗눈꺼풀에서 눈썹 쪽으로
올린 띠에서 눈을 뺀 영역이다. 기울어진 얼굴을 따라가고 특징점이 없으면 건너뛴다.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 5: 눈썹과 쉐딩·하이라이터 — 넓힌 눈썹, 얼굴 윤곽 타원

**Files:**
- Modify: `apple/Sources/MellowRendering/Domain/FaceRegions+Makeup.swift` (`BrowRegion`, `browRegions`, `ContourRegions`, `contourRegions`, `MakeupShape` 상수)
- Modify: `apple/Sources/MellowRendering/Domain/MakeupStage.swift` (`darkenBrows`, `sculpt`)
- Modify: `apple/Sources/MellowRendering/API/RenderTuning.swift`
- Modify: `apple/Tests/MellowRenderingTests/RenderingTestSupport.swift` (표본 점)
- Test: `apple/Tests/MellowRenderingTests/MakeupRegionsTests.swift`, `apple/Tests/MellowRenderingTests/MakeupStageTests.swift`

**Interfaces:**
- Consumes: Task 4의 `Oval`, `softMask`, `featheredPolygonMask(…feather:)`, `boundingRect`, `FaceFrame`, `MakeupStage.solid`·`blended`·`mixed`.
- Produces: `FaceRegions.BrowRegion`(`mask: RegionMask`, `sample: CGRect`), `browRegions(face:extent:tuning:cache:) -> [BrowRegion]`, `FaceRegions.ContourRegions`(`shade: RegionMask?`, `highlight: RegionMask?`), `contourRegions(face:extent:tuning:cache:) -> ContourRegions?`. `RenderTuning.makeupBrowMaxOpacity`(0.5), `makeupBrowFeather`(0.006), `makeupShadeMaxOpacity`(0.4), `makeupHighlightMaxOpacity`(0.3), `makeupShadeRGB`([0.72, 0.6, 0.52]), `makeupHighlightRGB`([1, 0.97, 0.92]). 테스트 지원 `SyntheticFace.leftBrowCenter`·`aboveLeftBrow`·`leftHollow`·`rightHollow`·`leftJaw`·`bridge`·`foreheadCenter`·`chinTip`.

설계 근거:
- **눈썹.** 눈썹 다각형을 얼굴 좌표에서 중심 둘레로 가로 1.15배·세로 1.6배 넓히고 얼굴 폭 × 0.006으로 흐린다(눈썹마다 캐시 항목 하나). 색은 원래 눈썹 경계 상자의 평균(`CIAreaAverage`)이고 곱하기로 섞는다(스펙 6 "기존 눈썹 색으로 multiply"). 합성 얼굴 왼눈썹은 (168, 332, 64, 12)라 넓힌 위끝이 y 347.6이다.
- **쉐딩(곱하기 회갈색).** 광대 아래: u ±얼굴 폭 × 0.34, v = 입 + (눈 − 입) × 0.2, 반지름 (0.11, 0.04)W. 턱선: 입보다 아래 윤곽점 중 그쪽(u 부호)에서 입과 턱 끝 가운데 높이에 가장 가까운 점, 반지름 (0.09, 0.05)W. 코 옆: 코 다각형의 가장 왼쪽·오른쪽 u, v = (눈 + 코 아래끝) / 2, 반지름 (0.02W, (눈 − 코 아래끝) / 2).
- **하이라이터(스크린).** 콧대: 코 좌우 가운데 u, 같은 v, 반지름 (0.025W, 위 세로 반지름 × 0.8). 이마 가운데: u 0, v = 눈 + 0.22W, 반지름 (0.12, 0.06)W. 턱 끝: 가장 낮은 윤곽점 u, v = 그 점 + 0.06W, 반지름 (0.06, 0.035)W.
- 모든 타원은 `softMask`(피부 다각형 비트맵을 곱함)라 눈·눈썹·입술의 넓힌 보호 영역과 얼굴 밖에는 닿지 않는다. 코가 없으면 코 옆·콧대만 빠진다. 합성 얼굴 표본: 광대 아래 (161, 172)·(351, 172), 왼턱 안쪽 (145, 110)(윤곽점 (134.4, 105.6) 안쪽), 콧대 (256, 245), 이마 (256, 368), 턱 끝 (256, 67).
- **순서.** 쉐딩·하이라이터(바탕) → 블러셔 → 아이섀도 → 눈썹 → 립.

- [ ] **Step 1: 테스트 지원 코드**

`RenderingTestSupport.swift`의 메이크업 표본 점 확장(Task 4)에 추가:

```swift
    /// 왼눈썹 가운데와, 세로로 1.6배 넓힌 눈썹 안이지만 원래 눈썹(위끝 344) 바깥인 피부.
    static let leftBrowCenter = CGPoint(x: 200, y: 338)
    static let aboveLeftBrow = CGPoint(x: 200, y: 345)
    /// 광대 아래 쉐딩 중심(u ±95.2, v = −60 + 160 × 0.2).
    static let leftHollow = CGPoint(x: 161, y: 172)
    static let rightHollow = CGPoint(x: 351, y: 172)
    /// 왼쪽 턱선 쉐딩 타원(윤곽점 (134.4, 105.6) 중심) 안쪽의 얼굴 피부.
    static let leftJaw = CGPoint(x: 145, y: 110)
    /// 콧대·이마 가운데·턱 끝 하이라이터 안.
    static let bridge = CGPoint(x: 256, y: 245)
    static let foreheadCenter = CGPoint(x: 256, y: 368)
    static let chinTip = CGPoint(x: 256, y: 67)
```

- [ ] **Step 2: 실패하는 테스트 작성**

`MakeupRegionsTests.swift` 맨 아래에 추가:

```swift
    func testBrowRegionsWidenEachBrowAndSampleTheOriginalBrow() throws {
        let face = SyntheticFace.make().face
        let brows = FaceRegions.browRegions(face: face, extent: extent, tuning: tuning)
        XCTAssertEqual(brows.count, 2)
        XCTAssertEqual(brows[0].sample, SyntheticFace.leftBrow, "왼눈썹 상자를 그대로 잰다")
        let pixels = try Support.grid(brows[0].mask.image)
        XCTAssertGreaterThan(pixels.red(SyntheticFace.leftBrowCenter), 200)
        XCTAssertGreaterThan(pixels.red(SyntheticFace.aboveLeftBrow), 128, "위아래로 넓혀 눈썹 바로 위 피부도 덮는다")
        for point in [SyntheticFace.leftEye, CGPoint(x: 312, y: 338), SyntheticFace.cheek] {
            XCTAssertEqual(pixels.red(point), 0, "왼눈썹 밖 \(point)")
        }
    }

    func testContourShadesHollowsAndJawAndHighlightsBridgeForeheadAndChin() throws {
        let face = SyntheticFace.make().face
        let regions = try XCTUnwrap(FaceRegions.contourRegions(face: face, extent: extent, tuning: tuning))
        let shade = try Support.grid(XCTUnwrap(regions.shade).image)
        let highlight = try Support.grid(XCTUnwrap(regions.highlight).image)
        for point in [SyntheticFace.leftHollow, SyntheticFace.rightHollow, SyntheticFace.leftJaw] {
            XCTAssertGreaterThan(shade.red(point), 128, "쉐딩 \(point)")
        }
        for point in [SyntheticFace.bridge, SyntheticFace.foreheadCenter, SyntheticFace.chinTip] {
            XCTAssertGreaterThan(highlight.red(point), 128, "하이라이터 \(point)")
        }
        for point in [SyntheticFace.leftEye, SyntheticFace.lipPoint, SyntheticFace.outside] {
            XCTAssertEqual(shade.red(point), 0, "쉐딩 밖 \(point)")
            XCTAssertEqual(highlight.red(point), 0, "하이라이터 밖 \(point)")
        }
    }

    func testBrowAndContourNeedLandmarks() {
        let boxOnly = SyntheticFace.make(landmarks: false).face
        XCTAssertTrue(FaceRegions.browRegions(face: boxOnly, extent: extent, tuning: tuning).isEmpty)
        XCTAssertNil(FaceRegions.contourRegions(face: boxOnly, extent: extent, tuning: tuning))
        let noseless = SyntheticFace.make().face.removing([.nose])
        let regions = FaceRegions.contourRegions(face: noseless, extent: extent, tuning: tuning)
        XCTAssertNotNil(regions?.shade, "코가 없으면 코 옆만 빠진다")
        XCTAssertNotNil(regions?.highlight, "콧대만 빠지고 이마·턱 끝은 남는다")
        let oneBrow = SyntheticFace.make().face.removing([.leftEyebrow])
        XCTAssertEqual(FaceRegions.browRegions(face: oneBrow, extent: extent, tuning: tuning).count, 1)
    }
```

`MakeupStageTests.swift` 맨 아래에 추가:

```swift
    func testBrowDarkensBrowsOnly() throws {
        let synthetic = SyntheticFace.makeFeatures()
        let before = try Support.grid(synthetic.image)
        let after = try Support.grid(output(synthetic, MakeupAdjustments(brow: MakeupStrength(intensity: 1))))
        XCTAssertLessThanOrEqual(
            brightness(after.rgba(SyntheticFace.leftBrowCenter)),
            brightness(before.rgba(SyntheticFace.leftBrowCenter)) - 10, "눈썹이 진해진다")
        XCTAssertLessThan(
            brightness(after.rgba(SyntheticFace.aboveLeftBrow)), brightness(before.rgba(SyntheticFace.aboveLeftBrow)),
            "눈썹 바로 위가 눈썹 색으로 채워진다")
        for point in [SyntheticFace.cheek, SyntheticFace.scleraPoint, SyntheticFace.lipPoint, SyntheticFace.mouth] {
            XCTAssertEqual(after.rgba(point), before.rgba(point), "눈썹 밖 \(point)")
        }
    }

    func testContourDarkensHollowsAndBrightensForehead() throws {
        let synthetic = SyntheticFace.makeFeatures()
        let before = try Support.grid(synthetic.image)
        let after = try Support.grid(output(synthetic, MakeupAdjustments(contour: MakeupStrength(intensity: 1))))
        XCTAssertLessThanOrEqual(
            brightness(after.rgba(SyntheticFace.leftHollow)), brightness(before.rgba(SyntheticFace.leftHollow)) - 6,
            "광대 아래가 어두워진다")
        XCTAssertGreaterThanOrEqual(
            brightness(after.rgba(SyntheticFace.foreheadCenter)),
            brightness(before.rgba(SyntheticFace.foreheadCenter)) + 6, "이마 가운데가 밝아진다")
        for point in [SyntheticFace.outside, SyntheticFace.scleraPoint, SyntheticFace.lipPoint] {
            XCTAssertEqual(after.rgba(point), before.rgba(point), "쉐딩·하이라이터 밖 \(point)")
        }
    }
```

- [ ] **Step 3: 실패 확인**

Run: `cd apple && swift test --filter 'MakeupRegionsTests|MakeupStageTests'` → 컴파일 실패(`type 'FaceRegions' has no member 'browRegions'`).

- [ ] **Step 4: 구현**

`RenderTuning.swift`: `makeupEyeshadowFeather` 아래에 추가:

```swift
    /// 눈썹 1에서 원래 눈썹 평균색으로 곱한 결과를 섞는 비율.
    public var makeupBrowMaxOpacity: Double = 0.5
    /// 넓힌 눈썹을 흐리는 반지름. 얼굴 폭 비율.
    public var makeupBrowFeather: Double = 0.006
    /// 쉐딩 1에서 회갈색 곱하기 결과를 섞는 비율.
    public var makeupShadeMaxOpacity: Double = 0.4
    /// 하이라이터 1에서 스크린 결과를 섞는 비율.
    public var makeupHighlightMaxOpacity: Double = 0.3
    /// 쉐딩 색(sRGB 감마 값). 스펙 6의 회갈색.
    public var makeupShadeRGB: [Double] = [0.72, 0.6, 0.52]
    /// 하이라이터 색(sRGB 감마 값). 따뜻한 흰색.
    public var makeupHighlightRGB: [Double] = [1, 0.97, 0.92]
```

`FaceRegions+Makeup.swift`:
1. `MakeupShape`의 `minimumLidPoints` 아래에 추가:

```swift
    /// 눈썹을 넓히는 배율(얼굴 x축·y축). 가는 눈썹이 위아래로 채워진다.
    static let browSpreadU: CGFloat = 1.15
    static let browSpreadV: CGFloat = 1.6
    /// 광대 아래 쉐딩. 가로 위치(얼굴 폭 비율), 높이(입 → 눈 비율), 반지름(얼굴 폭 비율).
    static let hollowOffset: CGFloat = 0.34
    static let hollowHeight: CGFloat = 0.2
    static let hollowRadiusU: CGFloat = 0.11
    static let hollowRadiusV: CGFloat = 0.04
    /// 턱선 쉐딩 반지름. 얼굴 폭 비율.
    static let jawRadiusU: CGFloat = 0.09
    static let jawRadiusV: CGFloat = 0.05
    /// 코 옆 쉐딩의 가로 반지름. 얼굴 폭 비율.
    static let noseSideRadiusU: CGFloat = 0.02
    /// 콧대 하이라이터의 가로 반지름(얼굴 폭 비율)과 세로 길이(코 옆 쉐딩 세로 반지름 대비).
    static let bridgeRadiusU: CGFloat = 0.025
    static let bridgeLengthFraction: CGFloat = 0.8
    /// 이마 가운데 하이라이터. 눈 높이 위 거리와 반지름. 얼굴 폭 비율.
    static let foreheadRise: CGFloat = 0.22
    static let foreheadRadiusU: CGFloat = 0.12
    static let foreheadRadiusV: CGFloat = 0.06
    /// 턱 끝 하이라이터. 가장 낮은 윤곽점 위 거리와 반지름. 얼굴 폭 비율.
    static let chinRise: CGFloat = 0.06
    static let chinRadiusU: CGFloat = 0.06
    static let chinRadiusV: CGFloat = 0.035
```

2. `extension FaceRegions` 안, `softMask` 위에 추가:

```swift
    /// 눈썹 하나의 넓힌 마스크와 원래 눈썹 색을 잴 사각형(픽셀).
    struct BrowRegion {
        let mask: RegionMask
        let sample: CGRect
    }

    /// 쉐딩(어둡게)·하이라이터(밝게) 영역. 각각 타원이 하나도 없거나 계산 영역이 비면 nil.
    struct ContourRegions {
        let shade: RegionMask?
        let highlight: RegionMask?
    }

    /// 눈썹마다 다각형을 얼굴 좌표에서 browSpreadU·browSpreadV배 넓혀 얼굴 폭 × makeupBrowFeather로 흐린다.
    /// 윤곽점이 없으면 빈 배열, 눈썹 특징점이 없는 쪽은 뺀다.
    static func browRegions(face: FaceGeometry, extent: CGRect, tuning: RenderTuning, cache: RegionMaskCache? = nil)
        -> [BrowRegion]
    {
        guard let frame = FaceFrame(face: face, extent: extent) else { return [] }
        let feather = max(CGFloat(tuning.skinBlurMinimumRadius), frame.faceWidth * CGFloat(tuning.makeupBrowFeather))
        return [FaceLandmark.leftEyebrow, .rightEyebrow].compactMap { landmark in
            guard let brow = landmarkPolygon(face, landmark, extent) else { return nil }
            let local = brow.map(frame.local)
            let center = FaceFrame.centroid(local)
            let widened = local.map { point in
                frame.imagePoint(
                    u: center.x + (point.x - center.x) * MakeupShape.browSpreadU,
                    v: center.y + (point.y - center.y) * MakeupShape.browSpreadV)
            }
            guard
                let mask = featheredPolygonMask(
                    fill: [widened], cut: [], face: face, extent: extent, tuning: tuning, cache: cache,
                    feather: feather)
            else { return nil }
            return BrowRegion(mask: mask, sample: boundingRect(brow).intersection(extent).integral)
        }
    }

    /// 쉐딩: 광대 아래·턱선·코 옆(각 2곳). 하이라이터: 콧대·이마 가운데·턱 끝(스펙 6). 윤곽점이 없으면 nil.
    static func contourRegions(
        face: FaceGeometry, extent: CGRect, tuning: RenderTuning, cache: RegionMaskCache? = nil
    ) -> ContourRegions? {
        guard let frame = FaceFrame(face: face, extent: extent) else { return nil }
        let width = frame.faceWidth
        let eye = frame.eyeLevel
        let mouth = frame.mouthLevel
        let contour = frame.contour.map(frame.local)
        guard let chin = contour.min(by: { $0.y < $1.y }) else { return nil }
        func oval(_ u: CGFloat, _ v: CGFloat, _ radiusU: CGFloat, _ radiusV: CGFloat) -> Oval {
            Oval(center: frame.imagePoint(u: u, v: v), radii: CGSize(width: radiusU, height: radiusV))
        }
        var shade: [Oval] = []
        var highlight: [Oval] = []
        let jawTarget = (mouth + chin.y) / 2
        for side in [CGFloat(-1), 1] {
            shade.append(
                oval(
                    side * width * MakeupShape.hollowOffset, mouth + (eye - mouth) * MakeupShape.hollowHeight,
                    width * MakeupShape.hollowRadiusU, width * MakeupShape.hollowRadiusV))
            let jaw = contour.filter { $0.y < mouth && $0.x * side > 0 }
                .min { abs($0.y - jawTarget) < abs($1.y - jawTarget) }
            if let jaw {
                shade.append(oval(jaw.x, jaw.y, width * MakeupShape.jawRadiusU, width * MakeupShape.jawRadiusV))
            }
        }
        if let nose = landmarkPolygon(face, .nose, extent)?.map(frame.local), let left = nose.map(\.x).min(),
            let right = nose.map(\.x).max(), let bottom = nose.map(\.y).min(), eye > bottom
        {
            let middle = (eye + bottom) / 2
            let half = (eye - bottom) / 2
            for u in [left, right] {
                shade.append(oval(u, middle, width * MakeupShape.noseSideRadiusU, half))
            }
            highlight.append(
                oval((left + right) / 2, middle, width * MakeupShape.bridgeRadiusU, half * MakeupShape.bridgeLengthFraction))
        }
        highlight.append(
            oval(0, eye + width * MakeupShape.foreheadRise, width * MakeupShape.foreheadRadiusU, width * MakeupShape.foreheadRadiusV))
        highlight.append(
            oval(chin.x, chin.y + width * MakeupShape.chinRise, width * MakeupShape.chinRadiusU, width * MakeupShape.chinRadiusV))
        return ContourRegions(
            shade: softMask(shade, face: face, frame: frame, extent: extent, tuning: tuning, cache: cache),
            highlight: softMask(highlight, face: face, frame: frame, extent: extent, tuning: tuning, cache: cache))
    }
```

(120자를 넘는 줄은 lint가 알려 주는 대로 인자마다 줄을 나눈다.)

`MakeupStage.swift`:
1. `apply`의 얼굴 반복을 다음으로 바꾼다:

```swift
        for face in context.targetFaces {
            result = sculpt(result, face: face, strength: makeup.contour, context: context)
            result = paintBlush(result, face: face, tint: makeup.blush, context: context)
            result = shadeEyelids(result, face: face, tint: makeup.eyeshadow, context: context)
            result = darkenBrows(result, face: face, strength: makeup.brow, context: context)
            result = paintLips(result, face: face, tint: makeup.lip, context: context)
        }
```

2. `paintBlush` 위에 추가:

```swift
    /// 쉐딩 영역은 회갈색을 곱하고 하이라이터 영역은 따뜻한 흰색을 스크린으로 얹는다. 강도 하나로 함께 움직인다.
    private func sculpt(_ image: CIImage, face: FaceGeometry, strength: MakeupStrength, context: RenderContext)
        -> CIImage
    {
        let tuning = context.tuning
        guard strength.intensity > 0,
            let regions = FaceRegions.contourRegions(
                face: face, extent: context.extent, tuning: tuning, cache: context.regionMasks)
        else { return image }
        var result = image
        if let shade = regions.shade {
            let darkened = Self.blended(
                result, with: Self.solid(tuning.makeupShadeRGB), mode: Self.multiply, in: shade.bounds)
            result = Self.mixed(
                darkened, over: result, mask: shade, amount: strength.intensity * tuning.makeupShadeMaxOpacity,
                extent: context.extent)
        }
        if let highlight = regions.highlight {
            let brightened = Self.blended(
                result, with: Self.solid(tuning.makeupHighlightRGB), mode: Self.screen, in: highlight.bounds)
            result = Self.mixed(
                brightened, over: result, mask: highlight,
                amount: strength.intensity * tuning.makeupHighlightMaxOpacity, extent: context.extent)
        }
        return result
    }

    /// 넓힌 눈썹을 원래 눈썹 상자의 평균색으로 곱해 진하게 하고 비어 있던 눈썹 가장자리를 채운다.
    private func darkenBrows(_ image: CIImage, face: FaceGeometry, strength: MakeupStrength, context: RenderContext)
        -> CIImage
    {
        guard strength.intensity > 0 else { return image }
        var result = image
        let brows = FaceRegions.browRegions(
            face: face, extent: context.extent, tuning: context.tuning, cache: context.regionMasks)
        for brow in brows where !brow.sample.isEmpty {
            let tone = image.applyingFilter(
                "CIAreaAverage", parameters: [kCIInputExtentKey: CIVector(cgRect: brow.sample)]
            ).clampedToExtent()
            let darkened = Self.blended(result, with: tone, mode: Self.multiply, in: brow.mask.bounds)
            result = Self.mixed(
                darkened, over: result, mask: brow.mask, amount: strength.intensity * context.tuning.makeupBrowMaxOpacity,
                extent: context.extent)
        }
        return result
    }
```

- [ ] **Step 5: 통과 확인**

Run: `cd apple && swift test` → 모듈별 `Executed 43 · 213 · 30 · 4 · 29 tests`, 모두 `with 0 failures`(합 319). 표본 점 단언이 실패하면 Task 4 Step 5와 같은 원칙(계산 근거 재확인, 임계값 완화 금지, 근거를 커밋 본문에). lint 출력 없음. `./scripts/verify-modules.sh` 통과. Mac 앱 테스트 → `Executed 62 tests, with 0 failures`.

- [ ] **Step 6: 커밋**

```bash
git add apple/Sources/MellowRendering/Domain/FaceRegions+Makeup.swift apple/Sources/MellowRendering/Domain/MakeupStage.swift apple/Sources/MellowRendering/API/RenderTuning.swift apple/Tests/MellowRenderingTests/RenderingTestSupport.swift apple/Tests/MellowRenderingTests/MakeupRegionsTests.swift apple/Tests/MellowRenderingTests/MakeupStageTests.swift
git commit -m "feat(rendering): 눈썹 진하게와 쉐딩·하이라이터

눈썹은 넓힌 영역을 원래 눈썹 평균색으로 곱하고, 쉐딩은 광대 아래·턱선·코 옆을
회갈색으로 곱하며 하이라이터는 콧대·이마·턱 끝을 스크린으로 밝힌다.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 6: 마스크 캐시 용량과 여러 얼굴 — 얼굴 수 비례 상한, 대상 얼굴

**Files:**
- Modify: `apple/Sources/MellowRendering/Domain/RegionMaskCache.swift`
- Modify: `apple/Sources/MellowRendering/API/PhotoAnalysis.swift` (`regionMasks` 생성)
- Modify: `apple/Tests/MellowRenderingTests/FaceRegionsTests.swift` (`testRegionMaskCacheEmptiesWhenFull`의 상한 참조)
- Test: `apple/Tests/MellowRenderingTests/RegionMaskCacheTests.swift`(새 파일), `apple/Tests/MellowRenderingTests/MakeupStageTests.swift`

**Interfaces:**
- Consumes: Task 3~5의 메이크업 마스크(캐시 항목: 피부 다각형 비트맵 공유, 아이섀도 1, 눈썹 2), D의 피부·눈·입술·치아 항목, `RenderingTestSupport.sharedMakeupCatalog()`, `FaceGeometry.transformed(scale:offset:)`.
- Produces: `RegionMaskCache.minimumEntries`(32), `entriesPerFacePerResolution`(8), `resolutions`(2), `static func capacity(forFaces:) -> Int`, 인스턴스 `maximumEntries`, `init(maximumEntries: Int = minimumEntries)`. `PhotoAnalysis.regionMasks`는 `capacity(forFaces: faces.count)` 상한으로 만든다.

설계 근거(D 이월 a): 얼굴 하나가 한 해상도에서 쓰는 다각형 비트맵은 피부·눈·입술·치아·아이섀도·왼눈썹·오른눈썹 7개다(블러셔·쉐딩·하이라이터는 피부 비트맵을, 립은 입술 생기와 같은 입술 비트맵을 쓴다). 미리보기·원본 두 해상도면 얼굴당 14개라 상한 32에서는 얼굴 셋부터 저장할 때마다 비우고 다시 그린다. 얼굴당 16(여유 하나 포함 8 × 2)으로 비례시키고 최소 32를 유지한다. 비트맵은 긴 변 최대 512 회색이라 하나 최대 256KB이고, 미리보기 캐시에서 밀려난 사진의 비트맵은 기존대로 놓는다. 대상 얼굴만 바뀌는 것은 `RenderContext.targetFaces`로 이미 보장되며 메이크업에 대해 테스트로 고정한다.

- [ ] **Step 1: 실패하는 테스트 작성**

`apple/Tests/MellowRenderingTests/RegionMaskCacheTests.swift`:

```swift
import CoreImage
import MellowShared
import XCTest

@testable import MellowRendering

final class RegionMaskCacheTests: XCTestCase {
    typealias Support = RenderingTestSupport

    func testCapacityGrowsWithFaceCount() {
        XCTAssertEqual(RegionMaskCache.capacity(forFaces: 0), RegionMaskCache.minimumEntries)
        XCTAssertEqual(RegionMaskCache.capacity(forFaces: 2), 32)
        XCTAssertEqual(RegionMaskCache.capacity(forFaces: 3), 48)
        let face = SyntheticFace.make().face
        XCTAssertEqual(PhotoAnalysis(faces: [face, face, face]).regionMasks.maximumEntries, 48)
        XCTAssertEqual(PhotoAnalysis().regionMasks.maximumEntries, 32)
    }

    /// 세 얼굴에 피부·눈·입·메이크업을 모두 켜고 큰 크기·작은 크기(미리보기·원본 대신)로 번갈아 렌더한다.
    /// 상한이 32로 고정이면 두 번째 크기에서 캐시를 비워 매번 다시 그린다(D 이월).
    func testThreeFacesWithFullMakeupKeepEveryMaskAcrossTwoResolutions() throws {
        let synthetic = SyntheticFace.makeFeatures()
        let third = 1.0 / 3
        let faces = [0, third, 2 * third].map {
            synthetic.face.transformed(scale: third, offset: NormalizedPoint(x: $0, y: third))
        }
        let analysis = PhotoAnalysis(faces: faces)
        let catalog = try Support.sharedMakeupCatalog()
        var recipe = EditRecipe()
        recipe.portrait.skin.smoothing = 0.5
        recipe.portrait.features = FeatureAdjustments(eyeBrighten: 0.5, teethWhiten: 0.5, lipVitality: 0.5)
        recipe.makeup = try XCTUnwrap(catalog.look(id: "smoky")).adjustments
        let large = synthetic.image
        let small = synthetic.image.transformed(by: CGAffineTransform(scaleX: 0.5, y: 0.5))
        func render(_ image: CIImage) throws -> [UInt8] {
            let context = RenderContext(
                extent: image.extent, recipe: recipe, analysis: analysis, tuning: RenderTuning(),
                makeupCatalog: catalog)
            return try Support.bytes(RenderPipeline.standard.render(image, context: context))
        }
        let firstLarge = try render(large)
        _ = try render(small)
        let filled = analysis.regionMasks.count
        XCTAssertGreaterThan(filled, RegionMaskCache.minimumEntries, "얼굴 셋 × 두 크기는 옛 상한 32를 넘는다")
        XCTAssertEqual(try render(large), firstLarge, "캐시에서 꺼낸 마스크로도 같은 결과")
        _ = try render(small)
        XCTAssertEqual(analysis.regionMasks.count, filled, "다시 렌더해도 비우지 않고 같은 비트맵을 쓴다")
    }
}
```

`MakeupStageTests.swift` 맨 아래에 추가:

```swift
    /// 반 크기 합성 얼굴 둘을 좌우에 놓는다(FeatureStageTests와 같은 배치). 비트맵으로 굳혀 바이트를 그대로 비교한다.
    func testTargetFacePaintsOnlyThatFace() throws {
        let synthetic = SyntheticFace.makeFeatures()
        let half = CGAffineTransform(scaleX: 0.5, y: 0.5)
        let side = CGFloat(SyntheticFace.size)
        let left = synthetic.image.transformed(by: half.concatenating(CGAffineTransform(translationX: 0, y: side / 4)))
        let right = synthetic.image.transformed(
            by: half.concatenating(CGAffineTransform(translationX: side / 2, y: side / 4)))
        let composed = left.composited(over: right).composited(over: CIImage(color: .gray)).cropped(to: extent)
        let image = CIImage(cgImage: try Support.renderer.makeCGImage(composed))
        let faces = [
            synthetic.face.transformed(scale: 0.5, offset: NormalizedPoint(x: 0, y: 0.25)),
            synthetic.face.transformed(scale: 0.5, offset: NormalizedPoint(x: 0.5, y: 0.25)),
        ]
        let catalog = try Support.sharedMakeupCatalog()
        var recipe = EditRecipe()
        recipe.makeup = try XCTUnwrap(catalog.look(id: "smoky")).adjustments
        recipe.portrait.targetFace = 0
        let context = RenderContext(
            extent: extent, recipe: recipe, faces: faces, tuning: RenderTuning(), makeupCatalog: catalog)
        let before = try Support.grid(image)
        let after = try Support.grid(MakeupStage().apply(image, in: context))
        var leftChanged = 0
        var rightChanged = 0
        for y in 0..<SyntheticFace.size {
            for x in 0..<SyntheticFace.size {
                let point = CGPoint(x: x, y: y)
                guard after.rgba(point) != before.rgba(point) else { continue }
                if x < SyntheticFace.size / 2 {
                    leftChanged += 1
                } else {
                    rightChanged += 1
                }
            }
        }
        XCTAssertGreaterThan(leftChanged, 0, "고른 얼굴은 메이크업이 들어간다")
        XCTAssertEqual(rightChanged, 0, "다른 얼굴은 한 픽셀도 바뀌지 않는다")
    }
```

`FaceRegionsTests.testRegionMaskCacheEmptiesWhenFull`의 `for index in 0...RegionMaskCache.maximumEntries {`를 `for index in 0...cache.maximumEntries {`로 바꾼다.

- [ ] **Step 2: 실패 확인**

Run: `cd apple && swift test --filter 'RegionMaskCacheTests|MakeupStageTests|FaceRegionsTests'` → 컴파일 실패(`type 'RegionMaskCache' has no member 'capacity'`, `value of type 'RegionMaskCache' has no member 'maximumEntries'`).

- [ ] **Step 3: 구현**

`RegionMaskCache.swift`의 클래스 앞부분(`static let maximumEntries = 32`와 그 주석, `private let lock` 위까지)을 다음으로 바꾸고, `mask(for:make:)` 안의 `Self.maximumEntries`를 `maximumEntries`로 바꾼다:

```swift
final class RegionMaskCache: @unchecked Sendable {
    /// 얼굴 하나가 한 해상도에서 쓰는 다각형 비트맵 수의 상한. 피부·눈·입술·치아·아이섀도·왼눈썹·오른눈썹 7개에 여유 1.
    /// 블러셔·쉐딩·하이라이터는 피부 비트맵을, 립은 입술 비트맵을 함께 쓴다.
    static let entriesPerFacePerResolution = 8
    /// 미리보기와 원본 두 해상도.
    static let resolutions = 2
    /// 얼굴이 적어도 이만큼은 담는다(D의 고정 상한).
    static let minimumEntries = 32

    /// 얼굴 수에 맞춘 상한. 비트맵 하나는 긴 변 512 이하 회색이라 최대 256KB다.
    static func capacity(forFaces count: Int) -> Int {
        max(minimumEntries, count * entriesPerFacePerResolution * resolutions)
    }

    /// 항목 수 상한. 넘으면 모두 비운다.
    let maximumEntries: Int

    init(maximumEntries: Int = minimumEntries) {
        self.maximumEntries = maximumEntries
    }
```

`PhotoAnalysis.swift`:
1. `let regionMasks = RegionMaskCache()`와 그 주석을 다음으로 바꾼다:

```swift
    /// 다각형 마스크 비트맵 캐시. 묶음을 복사해도 같은 캐시를 나눠 쓴다. 키에 다각형 점이 들어 있어 얼굴이 바뀌어도 낡은 값을 쓰지 않는다.
    /// 상한은 준비 때 찾은 얼굴 수에 비례한다(RegionMaskCache.capacity(forFaces:)).
    let regionMasks: RegionMaskCache
```

2. init 본문 끝(`self.bodyAnalysisFailure = bodyAnalysisFailure` 아래)에 추가:

```swift
        regionMasks = RegionMaskCache(maximumEntries: RegionMaskCache.capacity(forFaces: faces.count))
```

- [ ] **Step 4: 통과 확인**

Run: `cd apple && swift test` → 모듈별 `Executed 43 · 216 · 30 · 4 · 29 tests`, 모두 `with 0 failures`(합 322). lint 출력 없음. `./scripts/verify-modules.sh` 통과. Mac 앱 테스트 → `Executed 62 tests, with 0 failures`.

- [ ] **Step 5: 커밋**

```bash
git add apple/Sources/MellowRendering/Domain/RegionMaskCache.swift apple/Sources/MellowRendering/API/PhotoAnalysis.swift apple/Tests/MellowRenderingTests/FaceRegionsTests.swift apple/Tests/MellowRenderingTests/RegionMaskCacheTests.swift apple/Tests/MellowRenderingTests/MakeupStageTests.swift
git commit -m "perf(rendering): 마스크 캐시 상한을 얼굴 수에 비례, 대상 얼굴 메이크업 고정

메이크업이 얼굴당 비트맵을 더해 단체 사진에서 미리보기와 저장을 오갈 때마다
캐시를 비우던 것을 얼굴당 16개(최소 32개) 상한으로 막는다.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 7: 앱 정리 — 특징점 없는 얼굴 안내, 배경·체형 슬라이더 되돌리기

**Files:**
- Modify: `apple/MellowPhoto/Application/AppModel.swift` (`FaceAvailability`, `faceAvailability`, `canAdjustBackgroundBlur`, `canAdjustBodyShape(_:)`)
- Modify: `apple/MellowPhoto/Application/UserMessage.swift` (`noLandmarksHint`)
- Modify: `apple/MellowPhoto/Features/Editor/BeautyPanel.swift`
- Modify: `apple/MellowPhoto/Features/Editor/BackgroundPanel.swift`
- Modify: `apple/MellowPhoto/Features/Editor/BodyPanel.swift`
- Test: `apple/MellowPhotoTests/AppModelTests.swift`

**Interfaces:**
- Consumes: `AppModel.selectedInfo`·`faces`·`currentRecipe`·`backgroundAvailability`·`bodyAvailability`·`isGeometryLocked`(기존), `TestSupport.landmarkedFace(in:)`, `StubFaceAnalyzer(result:)`.
- Produces: `enum AppModel.FaceAvailability: Equatable { case ready, noLandmarks, noFace, unavailable(MellowError) }`, `AppModel.faceAvailability`, `AppModel.canAdjustBackgroundBlur: Bool`, `AppModel.canAdjustBodyShape(_ key: BodyShapeKey) -> Bool`. `UserMessage.noLandmarksHint`.

설계 근거(이월 f):
- **특징점 없는 얼굴(C 이월).** Vision이 상자만 준 얼굴은 피부 보정(대체 타원)만 동작하고 얼굴형·눈·입·메이크업 슬라이더는 아무것도 안 한다. 대상 얼굴(모든 얼굴이면 전부)에 특징점이 하나도 없으면 `noLandmarks`로 안내를 보인다. 슬라이더는 끄지 않는다(피부 보정은 동작하고 프리셋 값 확인이 가능해야 한다). 메이크업 도구(Task 8)도 같은 상태를 쓴다.
- **배경·체형 슬라이더(D·E 이월).** 사람·관절이 없으면 슬라이더를 꺼서 프리셋으로 들어온 값을 0으로 되돌릴 수 없었다. 값이 0이 아니면 켜 둔다(효과는 없지만 되돌릴 수 있다). 체형은 잠금이 먼저다.
- **상반신 사진의 다리 길게(E 이월).** 지금 안내 문구("다리 길게는 골반과 발목이 보여야 바뀌어요")를 유지하고 바꾸지 않는다. 끄려면 `PreparedPhoto`에 새 판정이 필요하다(범위 밖).

- [ ] **Step 1: 실패하는 테스트 작성**

`AppModelTests.swift` 맨 아래(마지막 테스트 뒤)에 추가:

```swift
    func testFaceAvailabilityReportsMissingLandmarksForTargetFaces() async throws {
        let staged = try TestSupport.solidPNG(in: root)
        let landmarked = TestSupport.landmarkedFace(in: NormalizedRect(x: 0.05, y: 0.3, width: 0.35, height: 0.4))
        let boxOnly = FaceGeometry(boundingBox: NormalizedRect(x: 0.55, y: 0.3, width: 0.35, height: 0.4))
        let model = TestSupport.makeModel(
            root: root, analyzer: StubFaceAnalyzer(result: .success([landmarked, boxOnly])),
            importer: FakeImporter(staged: [.success(StagedPhoto(url: staged, displayName: nil))]))
        try await importOne(model, staged)
        XCTAssertEqual(model.faceAvailability, .ready, "특징점이 있는 얼굴이 대상에 있으면 준비됨")
        model.edit(.targetFace(1))
        XCTAssertEqual(model.faceAvailability, .noLandmarks)
        XCTAssertTrue(UserMessage.noLandmarksHint.contains("메이크업"))
        model.edit(.targetFace(0))
        XCTAssertEqual(model.faceAvailability, .ready)

        let otherRoot = try TestSupport.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: otherRoot) }
        let otherStaged = try TestSupport.solidPNG(in: otherRoot)
        let empty = TestSupport.makeModel(
            root: otherRoot, importer: FakeImporter(staged: [.success(StagedPhoto(url: otherStaged, displayName: nil))]))
        try await importOne(empty, otherStaged)
        XCTAssertEqual(empty.faceAvailability, .noFace)
    }

    func testBackgroundAndBodySlidersStayUsableToResetPresetValues() async throws {
        let staged = try TestSupport.solidPNG(in: root)
        let model = TestSupport.makeModel(
            root: root, importer: FakeImporter(staged: [.success(StagedPhoto(url: staged, displayName: nil))]))
        try await importOne(model, staged)
        XCTAssertEqual(model.backgroundAvailability, .noPerson)
        XCTAssertEqual(model.bodyAvailability, .noBody)
        XCTAssertFalse(model.canAdjustBackgroundBlur)
        XCTAssertFalse(model.canAdjustBodyShape(.waist))
        model.applyPreset(
            PresetValues(background: BackgroundAdjustments(blur: 0.4), body: BodyShapeAdjustments(waist: -0.3)))
        XCTAssertTrue(model.canAdjustBackgroundBlur, "프리셋으로 들어온 흐림은 0으로 되돌릴 수 있다")
        XCTAssertTrue(model.canAdjustBodyShape(.waist))
        XCTAssertFalse(model.canAdjustBodyShape(.arms), "0인 항목은 효과가 없어 계속 끈다")
        model.edit(.backgroundBlur(0))
        model.edit(.bodyShape(.waist, 0))
        XCTAssertFalse(model.canAdjustBackgroundBlur)
        XCTAssertFalse(model.canAdjustBodyShape(.waist))
        try await waitUntil { !model.isRendering }
        XCTAssertNil(model.presentedError)
    }
```

- [ ] **Step 2: 실패 확인**

Run: `xcodebuild -project apple/MellowPhoto.xcodeproj -scheme MellowPhoto -derivedDataPath apple/build -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO build-for-testing 2>&1 | grep -c "error:"` → 0보다 큼(`faceAvailability`·`canAdjustBackgroundBlur`·`noLandmarksHint` 없음).

- [ ] **Step 3: 구현**

`UserMessage.swift`: `noFaceHint` 아래에 추가:

```swift
    static let noLandmarksHint = "얼굴 특징점을 찾지 못해 얼굴형·눈·입·메이크업은 바뀌지 않아요. 피부 보정과 잡티·변형 도구는 쓸 수 있어요."
```

`AppModel.swift`:
1. `BodyAvailability` 아래에 추가:

```swift
    /// 뷰티·메이크업 도구가 보여줄 얼굴 상태. 분석 실패가 얼굴 없음보다 먼저다.
    enum FaceAvailability: Equatable {
        case ready
        /// 대상 얼굴에 특징점이 하나도 없다. 피부 보정만 동작한다.
        case noLandmarks
        case noFace
        case unavailable(MellowError)
    }
```

2. `bodyAvailability` 아래에 추가:

```swift
    /// 선택 사진의 뷰티·메이크업 얼굴 상태. 대상 얼굴(모든 얼굴이면 전부)에 특징점이 없으면 noLandmarks다.
    var faceAvailability: FaceAvailability {
        if let failure = selectedInfo?.faceAnalysisFailure {
            return .unavailable(failure)
        }
        guard !faces.isEmpty else { return .noFace }
        let targets =
            currentRecipe.portrait.targetFace.map { index in faces.indices.contains(index) ? [faces[index]] : [] }
            ?? faces
        let lacksLandmarks = !targets.isEmpty && targets.allSatisfy { $0.landmarks.isEmpty }
        return lacksLandmarks ? .noLandmarks : .ready
    }
    /// 배경 흐림 슬라이더를 움직일 수 있는지. 사람이 없어도 프리셋으로 들어온 값은 0으로 되돌릴 수 있게 켠다.
    var canAdjustBackgroundBlur: Bool {
        backgroundAvailability == .ready || currentRecipe.background.blur != 0
    }
    /// 체형 슬라이더를 움직일 수 있는지. 잠금이 먼저이고, 관절이 없어도 0이 아닌 값은 되돌릴 수 있게 켠다.
    func canAdjustBodyShape(_ key: BodyShapeKey) -> Bool {
        !isGeometryLocked && (bodyAvailability == .ready || currentRecipe.body[key] != 0)
    }
```

`BeautyPanel.swift`의 `body` 전체를 다음으로 바꾼다(아래 `skinControls`·`faceControls`·`featureControls`는 그대로):

```swift
    var body: some View {
        @Bindable var model = model
        let recipe = model.currentRecipe
        let availability = model.faceAvailability
        switch availability {
        case .unavailable(let failure):
            Label(UserMessage.faceAnalysisUnavailableTitle, systemImage: "exclamationmark.triangle")
            Text(UserMessage.text(for: failure)).font(.caption).foregroundStyle(.secondary)
        case .noFace:
            Label(UserMessage.noFaceDetected, systemImage: "person.crop.rectangle.badge.questionmark")
            Text(UserMessage.noFaceHint).font(.caption).foregroundStyle(.secondary)
        case .ready, .noLandmarks:
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
            if availability == .noLandmarks {
                Text(UserMessage.noLandmarksHint).font(.caption).foregroundStyle(.secondary)
            }
            Picker(UserMessage.beautyTabsLabel, selection: $model.beautyTab) {
                ForEach(BeautyTab.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            switch model.beautyTab {
            case .skin: skinControls(recipe.portrait.skin)
            case .face: faceControls(recipe.portrait.face)
            case .features: featureControls(recipe.portrait.features)
            }
        }
    }
```

`BackgroundPanel.swift`: `.disabled(availability != .ready)`를 `.disabled(!model.canAdjustBackgroundBlur)`로 바꾸고, 구조체 doc 주석의 둘째 줄을 `/// 사람을 찾지 못했거나 인물 분석이 실패하면 안내를 보이고 슬라이더는 끈다. 프리셋으로 들어온 값이 있으면 0으로 되돌릴 수 있게 켠다.`로 바꾼다.

`BodyPanel.swift`: `.disabled(availability != .ready || model.isGeometryLocked)`를 `.disabled(!model.canAdjustBodyShape(key))`로 바꾸고, doc 주석 둘째 줄을 `/// 관절을 찾지 못했거나 체형 분석이 실패하면 안내를 보이고 슬라이더는 끈다. 프리셋으로 들어온 0이 아닌 값은 되돌릴 수 있게 켠다.`로 바꾼다.

- [ ] **Step 4: 통과 확인**

Run: Mac 앱 테스트 → `Executed 64 tests, with 0 failures`. `cd apple && swift test` → 합 322, 모두 `with 0 failures`. lint 출력 없음. `./scripts/verify-modules.sh` 통과. iOS 시뮬레이터 테스트는 돌리지 않는다(Task 9).

- [ ] **Step 5: 커밋**

```bash
git add apple/MellowPhoto/Application/AppModel.swift apple/MellowPhoto/Application/UserMessage.swift apple/MellowPhoto/Features/Editor/BeautyPanel.swift apple/MellowPhoto/Features/Editor/BackgroundPanel.swift apple/MellowPhoto/Features/Editor/BodyPanel.swift apple/MellowPhotoTests/AppModelTests.swift
git commit -m "fix(app): 특징점 없는 얼굴 안내, 프리셋 배경·체형 값을 되돌릴 수 있게

상자만 찾은 얼굴은 얼굴형·눈·입·메이크업이 바뀌지 않는다는 안내를 보인다.
사람·관절이 없어도 0이 아닌 배경 흐림·체형 값은 슬라이더로 0까지 되돌릴 수 있다.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 8: 앱 — 메이크업 도구, 카탈로그 로드, 룩 적용, F 시나리오

**Files:**
- Create: `apple/MellowPhoto/Features/Editor/MakeupPanel.swift`
- Modify: `apple/MellowPhoto/Application/EditorTool.swift`
- Modify: `apple/MellowPhoto/Application/AppModel.swift` (`makeupCatalog`, `makeupPart`, `init`, `Policy`)
- Modify: `apple/MellowPhoto/Application/AppModel+Editing.swift` (`applyMakeupLook(id:)`, `touch` switch)
- Modify: `apple/MellowPhoto/Application/UserMessage.swift`
- Modify: `apple/MellowPhoto/Features/Shared/Theme.swift`
- Modify: `apple/MellowPhoto/Features/Editor/ToolStrip.swift`
- Modify: `apple/MellowPhoto/Features/Editor/EditorScene.swift` (`toolPanel`)
- Modify: `apple/MellowPhoto/Platform/AppModel+Live.swift`
- Modify: `apple/MellowPhoto.xcodeproj` (`xcodegen generate` 결과)
- Modify: `apple/MellowPhotoTests/TestSupport.swift` (`sharedMakeupCatalog()`, `makeModel` 인자)
- Test: `apple/MellowPhotoTests/AppModelTests.swift`, `apple/MellowPhotoTests/EditorScenarioTests.swift`

**Interfaces:**
- Consumes: `MakeupCatalog`·`MakeupLook`·`MakeupColor`(Task 1), `EditChange.makeupColor`·`makeupIntensity`·`EditDocument.applyMakeupLook`·`MakeupAdjustments.colorID(of:)`(Task 2), `PhotoPipeline.init(…makeupCatalog:)`(Task 3), `AppModel.faceAvailability`(Task 7), `AdjustmentSlider(title:value:range:change:)`, `Theme.accent`.
- Produces: `EditorTool.makeup`(제목 "메이크업", 기호 `paintbrush.pointed`, 도구 줄 뷰티 다음). `struct MakeupPanel: View`. `AppModel.makeupCatalog: MakeupCatalog`(init 인자 `makeupCatalog: MakeupCatalog = .empty`, `lookCatalog` 다음), `AppModel.makeupPart: MakeupPart`(기본 `.lip`), `AppModel.applyMakeupLook(id: String?)`, `static func AppModel.bundledMakeupCatalog(in: Bundle = .main) -> MakeupCatalog?`, `Policy.bundledMakeupCatalogName`("makeup.v1")·`bundledMakeupCatalogExtension`("json"). `UserMessage.toolMakeup`, `makeupNoLook`, `makeupPartsLabel`, `makeupIntensity`, `makeupHint`, `makeupCatalogUnavailable`, `makeupPartTitle(_:)`. `Theme.makeupChipSize`, `makeupChipPadding`, `makeupSwatchSize`. 테스트 지원 `TestSupport.sharedMakeupCatalog()`, `TestSupport.makeModel(root:maxPhotos:analyzer:personAnalyzer:bodyAnalyzer:makeupCatalog:importer:store:)`(`makeupCatalog: MakeupCatalog? = nil` = 공용 파일).

설계 근거(스펙 7): 도구 줄 `필터 · 자동 · 자르기 · 조정 · 뷰티 · 메이크업 · 체형 · 배경 · 잡티 · 변형`. 패널은 위에서부터 얼굴 상태 안내(Task 7의 `faceAvailability`), 카탈로그를 읽지 못했으면 안내, 룩 칩(없음 + 5개, 이름 칩), 부위 탭(립·블러셔·아이섀도·눈썹·쉐딩), 색이 있는 부위는 색 칩, 강도 슬라이더, 도움말. 메이크업은 색만 바꾸므로 수동 편집이 있어도 끄지 않는다. 카탈로그는 룩 카탈로그와 같은 방식으로 번들에서 읽고, 파일이 없거나 깨졌으면(디코드 오류) 빈 카탈로그와 안내 문구로 바꾼다(스펙 6·7). 두 카탈로그가 모두 없으면 알림 하나에 함께 적는다. 룩 칩을 누르면 같은 룩이어도 다시 적용(편집 규칙이 같은 값이면 단계를 만들지 않는다), "없음"은 모두 지운다. 색 칩을 다시 누르면 색을 뺀다.

- [ ] **Step 1: 테스트 지원 코드**

`TestSupport.swift`의 `sharedLookCatalog()` 아래에 추가:

```swift
    /// 저장소의 공용 메이크업 카탈로그. 앱 번들과 같은 파일이다.
    static func sharedMakeupCatalog() throws -> MakeupCatalog {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("shared/makeup/makeup.v1.json")
        return try MakeupCatalog(data: Data(contentsOf: url))
    }
```

`makeModel` 전체:

```swift
    /// makeupCatalog가 nil이면 공용 파일을 읽는다. 카탈로그가 없는 경우는 .empty를 넘긴다.
    @MainActor
    static func makeModel(
        root: URL, maxPhotos: Int = 40, analyzer: StubFaceAnalyzer = StubFaceAnalyzer(),
        personAnalyzer: StubPersonAnalyzer = StubPersonAnalyzer(), bodyAnalyzer: StubBodyAnalyzer = StubBodyAnalyzer(),
        makeupCatalog: MakeupCatalog? = nil, importer: FakeImporter = FakeImporter(),
        store: MemorySessionStore = MemorySessionStore()
    ) -> AppModel {
        let copies = WorkingCopyStore(directory: root.appendingPathComponent("Library"))
        try? copies.prepareDirectory()
        let catalog = (try? sharedLookCatalog()) ?? .empty
        let makeup = makeupCatalog ?? (try? sharedMakeupCatalog()) ?? .empty
        return AppModel(
            session: ProjectSession(store: store, maxPhotos: maxPhotos),
            pipeline: PhotoPipeline(
                analyzer: analyzer, personAnalyzer: personAnalyzer, bodyAnalyzer: bodyAnalyzer, tuning: RenderTuning(),
                lookCatalog: catalog, makeupCatalog: makeup),
            copies: copies,
            importer: importer,
            exporter: Exporter(renderer: Renderer()),
            lookCatalog: catalog,
            makeupCatalog: makeup,
            renderDebounce: .milliseconds(10))
    }
```

- [ ] **Step 2: 실패하는 테스트 작성**

`AppModelTests.swift`:
1. 기존 `testBodyToolEditsEveryKeyOneUndoStepEachWhenBodyFound`의 `XCTAssertEqual(EditorTool.allCases, [.look, .crop, .adjust, .beauty, .body, .background, .retouch, .warp])`를 다음으로 바꾼다:

```swift
        XCTAssertEqual(
            EditorTool.allCases, [.look, .crop, .adjust, .beauty, .makeup, .body, .background, .retouch, .warp])
```

2. 맨 아래에 추가:

```swift
    func testMakeupToolAppliesLookOnceAndPartEditsDetachLook() async throws {
        let staged = try TestSupport.solidPNG(in: root)
        let face = TestSupport.landmarkedFace(in: NormalizedRect(x: 0.2, y: 0.2, width: 0.6, height: 0.6))
        let model = TestSupport.makeModel(
            root: root, analyzer: StubFaceAnalyzer(result: .success([face])),
            importer: FakeImporter(staged: [.success(StagedPhoto(url: staged, displayName: nil))]))
        try await importOne(model, staged)
        model.selectTool(.makeup)
        XCTAssertEqual(EditorTool.makeup.title, "메이크업")
        XCTAssertEqual(model.makeupCatalog.looks.map(\.name), ["데일리", "쿨톤", "웜피치", "로지", "스모키"])
        XCTAssertEqual(
            MakeupPart.allCases.map(UserMessage.makeupPartTitle), ["립", "블러셔", "아이섀도", "눈썹", "쉐딩"])
        let daily = try XCTUnwrap(model.makeupCatalog.look(id: "daily"))
        model.applyMakeupLook(id: "daily")
        XCTAssertEqual(model.currentRecipe.makeup, daily.adjustments)
        model.applyMakeupLook(id: "nope")
        XCTAssertEqual(model.currentRecipe.makeup, daily.adjustments, "모르는 룩은 무시한다")
        model.makeupPart = .blush
        model.beginSliderEdit()
        model.edit(.makeupIntensity(.blush, 0.6))
        model.edit(.makeupIntensity(.blush, 0.8))
        model.endSliderEdit()
        XCTAssertEqual(model.currentRecipe.makeup.blush.intensity, 0.8, accuracy: 1e-9)
        XCTAssertNil(model.currentRecipe.makeup.lookID, "부위를 바꾸면 룩 이름이 풀린다")
        try await waitUntil { !model.isRendering }
        XCTAssertNil(model.presentedError)
        model.undo()
        XCTAssertEqual(model.currentRecipe.makeup, daily.adjustments, "드래그 한 번이 실행 취소 한 단계")
        model.undo()
        XCTAssertEqual(model.currentRecipe.makeup, MakeupAdjustments(), "룩 적용도 실행 취소 한 번")
        model.redo()
        model.applyMakeupLook(id: nil)
        XCTAssertEqual(model.currentRecipe.makeup, MakeupAdjustments(), "없음은 메이크업을 모두 지운다")
    }

    func testMakeupWorksWithLocalEditsAndFallsBackWithoutCatalog() async throws {
        let staged = try TestSupport.solidPNG(in: root)
        let model = TestSupport.makeModel(
            root: root, importer: FakeImporter(staged: [.success(StagedPhoto(url: staged, displayName: nil))]))
        try await importOne(model, staged)
        model.tool = .retouch
        model.touch(from: NormalizedPoint(x: 0.3, y: 0.3), to: NormalizedPoint(x: 0.3, y: 0.3))
        model.touch(from: NormalizedPoint(x: 0.5, y: 0.5), to: NormalizedPoint(x: 0.5, y: 0.5))
        try await waitUntil { !model.isRendering }
        XCTAssertTrue(model.isGeometryLocked)
        model.selectTool(.makeup)
        model.edit(.makeupColor(.lip, "lip-coral"))
        XCTAssertEqual(model.currentRecipe.makeup.lip.colorID, "lip-coral", "메이크업은 수동 편집이 있어도 잠기지 않는다")
        XCTAssertNotEqual(model.statusMessage, UserMessage.geometryLocked)
        model.applyMakeupLook(id: "smoky")
        XCTAssertEqual(model.currentRecipe.makeup.lookID, "smoky")

        let otherRoot = try TestSupport.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: otherRoot) }
        let otherStaged = try TestSupport.solidPNG(in: otherRoot)
        let bare = TestSupport.makeModel(
            root: otherRoot, makeupCatalog: .empty,
            importer: FakeImporter(staged: [.success(StagedPhoto(url: otherStaged, displayName: nil))]))
        try await importOne(bare, otherStaged)
        bare.applyMakeupLook(id: "daily")
        XCTAssertEqual(bare.currentRecipe.makeup, MakeupAdjustments(), "카탈로그가 없으면 룩을 고를 수 없다")
        XCTAssertTrue(bare.makeupCatalog.isEmpty)
        XCTAssertTrue(UserMessage.makeupCatalogUnavailable.contains("메이크업"))
        XCTAssertNil(
            AppModel.bundledMakeupCatalog(in: Bundle(for: AppModelTests.self)), "파일이 없는 번들은 nil(안내 문구로 바뀐다)")
        XCTAssertEqual(AppModel.bundledMakeupCatalog()?.looks.count, 5, "앱 번들에서는 읽힌다")
    }
```

`EditorScenarioTests.swift`:
1. `testBeautySkinFaceFeaturesBackgroundThenBodyThenExportSucceeds`의 이름을 `testBeautySkinFaceFeaturesBackgroundBodyThenMakeupThenExportSucceeds`로 바꾼다.
2. 그 안의 `try await waitUntil { !model.isRendering && self.previewBytes(model) != blurred }` 줄 바로 아래(빈 줄과 `let recipe = model.currentRecipe` 앞)에 추가:

```swift
        let bodied = previewBytes(model)

        model.selectTool(.makeup)
        model.applyMakeupLook(id: "daily")
        // 메이크업 룩만 골라도 미리보기가 바뀌어야 한다.
        try await waitUntil { !model.isRendering && self.previewBytes(model) != bodied }
```

3. `XCTAssertEqual(recipe.body, BodyShapeAdjustments(legLength: 0.5))` 아래에 추가:

```swift
        XCTAssertEqual(recipe.makeup, try XCTUnwrap(model.makeupCatalog.look(id: "daily")).adjustments)
```

4. 마지막 단언 문구 `"다리를 늘려도 정사각형 원본 크기 그대로 저장된다"`를 `"다리를 늘리고 메이크업을 해도 정사각형 원본 크기 그대로 저장된다"`로 바꾼다.

- [ ] **Step 3: 실패 확인**

Run: `xcodebuild -project apple/MellowPhoto.xcodeproj -scheme MellowPhoto -derivedDataPath apple/build -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO build-for-testing 2>&1 | grep -c "error:"` → 0보다 큼(`EditorTool`에 `makeup` 없음, `makeupCatalog` 없음, `applyMakeupLook` 없음).

- [ ] **Step 4: 구현**

`UserMessage.swift`: `bodyAnalysisUnavailableTitle` 아래에 추가:

```swift
    static let toolMakeup = "메이크업"
    static let makeupNoLook = "없음"
    static let makeupPartsLabel = "메이크업 부위"
    static let makeupIntensity = "강도"
    static let makeupHint = "룩을 고른 뒤 부위마다 색과 강도를 바꿀 수 있어요. 부위를 바꾸면 룩 선택은 풀려요."
    static let makeupCatalogUnavailable = "메이크업 목록을 읽지 못해 룩과 색을 쓸 수 없습니다."
```

함수 묶음(`bodyShapeTitle` 아래)에 추가:

```swift
    /// 메이크업 부위 탭 이름. 화면 순서는 MakeupPart.allCases.
    static func makeupPartTitle(_ part: MakeupPart) -> String {
        switch part {
        case .lip: return "립"
        case .blush: return "블러셔"
        case .eyeshadow: return "아이섀도"
        case .brow: return "눈썹"
        case .contour: return "쉐딩"
        }
    }
```

`Theme.swift`: `lookChipSize` 아래에 추가:

```swift
    /// 메이크업 룩 이름 칩의 최소 크기와 좌우 여백.
    static let makeupChipSize = CGSize(width: 56, height: 30)
    static let makeupChipPadding: CGFloat = 10
    /// 메이크업 색 칩 지름.
    static let makeupSwatchSize: CGFloat = 28
```

`EditorTool.swift`: `case beauty` 아래에 `case makeup`을 더하고, `title`의 `case .beauty` 아래에 `case .makeup: return UserMessage.toolMakeup`, `symbol`의 `case .beauty` 아래에 `case .makeup: return "paintbrush.pointed"`를 더한다.

`AppModel.swift`:
1. `Policy`의 `bundledLookCatalogExtension` 아래에 추가:

```swift
        /// 앱 번들에 든 메이크업 카탈로그 파일. shared/makeup/makeup.v1.json과 같은 내용이다.
        static let bundledMakeupCatalogName = "makeup.v1"
        static let bundledMakeupCatalogExtension = "json"
```

2. `let lookCatalog: LookCatalog` 아래에 `let makeupCatalog: MakeupCatalog`.
3. `var beautyTab: BeautyTab = .skin` 아래에 추가:

```swift
    /// 메이크업 도구에서 마지막으로 본 부위. 도구를 바꿔도 유지한다.
    var makeupPart: MakeupPart = .lip
```

4. init:

```swift
    init(
        session: ProjectSession, pipeline: PhotoPipeline, copies: WorkingCopyStore, importer: any PhotoImporter,
        exporter: Exporter, lookCatalog: LookCatalog = .empty, makeupCatalog: MakeupCatalog = .empty,
        renderDebounce: Duration = Policy.renderDebounce
    ) {
        self.session = session
        self.pipeline = pipeline
        self.copies = copies
        self.importer = importer
        self.exporter = exporter
        self.lookCatalog = lookCatalog
        self.makeupCatalog = makeupCatalog
        renderScheduler = RenderScheduler(debounce: renderDebounce)
    }
```

`AppModel+Editing.swift`:
1. `applyAutoSuggestion` 아래에 추가:

```swift
    /// 카탈로그의 룩을 체크포인트 한 번으로 적용한다. nil은 메이크업을 모두 지운다(없음). 모르는 id는 무시한다.
    func applyMakeupLook(id: String?) {
        let look = makeupCatalog.look(id: id)
        guard id == nil || look != nil else { return }
        endSliderEditIfActive()
        mutateSelected { document in
            document.applyMakeupLook(look)
            return nil
        }
    }
```

2. `touch` switch 마지막 case:

```swift
        case .look, .crop, .adjust, .beauty, .makeup, .body, .background:
            return
```

`ToolStrip.swift`의 도구 목록:

```swift
                ForEach([EditorTool.crop, .adjust, .beauty, .makeup, .body, .background, .retouch, .warp]) {
                    toolButton($0)
                }
```

`EditorScene.swift`의 `toolPanel` switch에 `case .beauty: BeautyPanel()` 아래 한 줄:

```swift
        case .makeup: MakeupPanel()
```

`AppModel+Live.swift`:
1. `live()`의 `let bundledCatalog = bundledLookCatalog()`부터 `if bundledCatalog == nil { … }` 블록 끝까지를 다음으로 바꾼다:

```swift
        let lookCatalog = bundledLookCatalog()
        let makeupCatalog = bundledMakeupCatalog()
        let model = AppModel(
            session: session,
            pipeline: PhotoPipeline(
                analyzer: VisionFaceAnalyzer(), personAnalyzer: VisionPersonAnalyzer(),
                bodyAnalyzer: VisionBodyAnalyzer(), tuning: RenderTuning.forCurrentDevice(),
                lookCatalog: lookCatalog ?? .empty, makeupCatalog: makeupCatalog ?? .empty),
            copies: copies,
            importer: SystemPhotoImporter(),
            exporter: Exporter(renderer: Renderer()),
            lookCatalog: lookCatalog ?? .empty,
            makeupCatalog: makeupCatalog ?? .empty)
        // 두 목록을 모두 읽지 못하면 알림 하나에 함께 적는다. 알림은 마지막 것 하나만 보인다.
        let unavailable = [
            lookCatalog == nil ? UserMessage.lookCatalogUnavailable : nil,
            makeupCatalog == nil ? UserMessage.makeupCatalogUnavailable : nil,
        ].compactMap { $0 }
        if !unavailable.isEmpty {
            model.present(message: unavailable.joined(separator: "\n"))
        }
```

2. `bundledLookCatalog()` 아래에 추가:

```swift
    /// 번들 메이크업 카탈로그. 파일이 없거나 형식이 틀리면(DecodingError 포함) nil이고, 호출자가 빈 카탈로그와 안내 문구로 바꾼다.
    static func bundledMakeupCatalog(in bundle: Bundle = .main) -> MakeupCatalog? {
        guard
            let url = bundle.url(
                forResource: Policy.bundledMakeupCatalogName, withExtension: Policy.bundledMakeupCatalogExtension)
        else { return nil }
        do {
            return try MakeupCatalog(data: Data(contentsOf: url))
        } catch {
            return nil
        }
    }
```

`apple/MellowPhoto/Features/Editor/MakeupPanel.swift`:

```swift
import MellowEditing
import MellowShared
import SwiftUI

/// 메이크업 도구. 룩 칩(없음 + 5개)이 위, 부위 탭이 아래, 부위마다 색 칩과 강도 슬라이더(스펙 7).
/// 색만 바꾸므로 수동 편집이 있어도 끄지 않는다. 얼굴이 없거나 특징점이 없으면 안내를 보인다.
struct MakeupPanel: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        let makeup = model.currentRecipe.makeup
        let catalog = model.makeupCatalog
        let part = model.makeupPart
        switch model.faceAvailability {
        case .ready:
            EmptyView()
        case .noLandmarks:
            Text(UserMessage.noLandmarksHint).font(.caption).foregroundStyle(.secondary)
        case .noFace:
            Label(UserMessage.noFaceDetected, systemImage: "person.crop.rectangle.badge.questionmark")
        case .unavailable(let failure):
            Label(UserMessage.faceAnalysisUnavailableTitle, systemImage: "exclamationmark.triangle")
            Text(UserMessage.text(for: failure)).font(.caption).foregroundStyle(.secondary)
        }
        if catalog.isEmpty {
            Text(UserMessage.makeupCatalogUnavailable).font(.caption).foregroundStyle(.secondary)
        }
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                lookChip(id: nil, name: UserMessage.makeupNoLook, selected: makeup == MakeupAdjustments())
                ForEach(catalog.looks) { look in
                    lookChip(id: look.id, name: look.name, selected: makeup.lookID == look.id)
                }
            }
            .padding(.vertical, 4)
        }
        .scrollIndicators(.hidden)
        Picker(UserMessage.makeupPartsLabel, selection: $model.makeupPart) {
            ForEach(MakeupPart.allCases, id: \.self) { Text(UserMessage.makeupPartTitle($0)).tag($0) }
        }
        .pickerStyle(.segmented)
        if part.hasColor {
            ScrollView(.horizontal) {
                HStack(spacing: 10) {
                    ForEach(catalog.colors(for: part)) { color in
                        swatch(color, part: part, selected: makeup.colorID(of: part) == color.id)
                    }
                }
                .padding(.vertical, 4)
            }
            .scrollIndicators(.hidden)
        }
        AdjustmentSlider(
            title: UserMessage.makeupIntensity, value: makeup.intensity(of: part), range: EditingPolicy.unitRange
        ) { .makeupIntensity(part, $0) }
        Text(UserMessage.makeupHint).font(.caption).foregroundStyle(.secondary)
    }

    private func lookChip(id: String?, name: String, selected: Bool) -> some View {
        Button {
            model.applyMakeupLook(id: id)
        } label: {
            Text(name).font(.caption)
                .padding(.horizontal, Theme.makeupChipPadding)
                .frame(minWidth: Theme.makeupChipSize.width, minHeight: Theme.makeupChipSize.height)
                .background(selected ? Theme.accent.opacity(0.2) : Color.secondary.opacity(0.15), in: Capsule())
                .overlay(Capsule().stroke(selected ? Theme.accent : .clear, lineWidth: 2))
                .foregroundStyle(selected ? Theme.accent : .primary)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(name)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    /// 같은 색 칩을 다시 누르면 색을 뺀다.
    private func swatch(_ color: MakeupColor, part: MakeupPart, selected: Bool) -> some View {
        Button {
            model.edit(.makeupColor(part, selected ? nil : color.id))
        } label: {
            VStack(spacing: 4) {
                Circle().fill(Color(red: color.red, green: color.green, blue: color.blue))
                    .frame(width: Theme.makeupSwatchSize, height: Theme.makeupSwatchSize)
                    .overlay(Circle().stroke(selected ? Theme.accent : .clear, lineWidth: 2))
                Text(color.name).font(.caption2).foregroundStyle(selected ? Theme.accent : .secondary)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(color.name)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
```

새 앱 파일을 프로젝트에 넣는다: `cd apple && xcodegen generate --quiet && git status --short MellowPhoto.xcodeproj` → `M MellowPhoto.xcodeproj/project.pbxproj`.

- [ ] **Step 5: 통과 확인**

Run: Mac 앱 테스트 → `Executed 66 tests, with 0 failures`. `cd apple && swift test` → 합 322, 모두 `with 0 failures`. lint 출력 없음. `./scripts/verify-modules.sh` 통과. `cd apple && xcodegen generate --quiet && git diff --exit-code --stat MellowPhoto.xcodeproj` → 이 Task 커밋 뒤에는 출력 없음. iOS 시뮬레이터 테스트는 돌리지 않는다(Task 9).

- [ ] **Step 6: 커밋**

```bash
git add apple/MellowPhoto/Features/Editor/MakeupPanel.swift apple/MellowPhoto/Application/EditorTool.swift apple/MellowPhoto/Application/AppModel.swift apple/MellowPhoto/Application/AppModel+Editing.swift apple/MellowPhoto/Application/UserMessage.swift apple/MellowPhoto/Features/Shared/Theme.swift apple/MellowPhoto/Features/Editor/ToolStrip.swift apple/MellowPhoto/Features/Editor/EditorScene.swift apple/MellowPhoto/Platform/AppModel+Live.swift apple/MellowPhoto.xcodeproj apple/MellowPhotoTests/TestSupport.swift apple/MellowPhotoTests/AppModelTests.swift apple/MellowPhotoTests/EditorScenarioTests.swift
git commit -m "feat(app): 메이크업 도구와 룩 5종, 번들 메이크업 카탈로그 연결

도구 줄 뷰티 다음에 메이크업 도구를 두고 룩 칩·부위 탭·색 칩·강도 슬라이더를 단다.
번들 카탈로그를 읽지 못하면 안내 문구를 띄우고 나머지 도구는 그대로 동작한다.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 9: 문서·스펙·검증 기록, 1.2.0 변경사항, 전체 검증

**Files:**
- Create: `fastlane/release_notes/1.2.0.json`
- Modify: `README.md`, `docs/APPLE.md`, `docs/architecture/modules.md`, `VALIDATION.md`, `docs/superpowers/specs/2026-10-15-beauty-b-to-f-design.md`

**Interfaces:**
- Consumes: Task 1~8 결과와 `MELLOW_IOS_TESTS=1 ./scripts/test-apple.sh`·`./scripts/build-apple.sh` 출력.
- Produces: 문서와 1.2.0 변경사항. 이후 Task 없음(배포는 머지 뒤 컨트롤러).

- [ ] **Step 1: 최종 검증 실행**

실행 전 `xcrun simctl list devices booted`로 이미 켜진 시뮬레이터를 적어 둔다. Run: `MELLOW_IOS_TESTS=1 ./scripts/test-apple.sh; echo "exit=$?"` → `exit=0`, 패키지 모듈별 `Executed 43 · 216 · 30 · 4 · 29 tests`(합 322), 앱 iPhone `Executed 65 tests`·iPad `Executed 65 tests`·Mac `Executed 66 tests`(모두 0 failures). 실행 뒤에도 시뮬레이터를 끄지 않는다(스크립트가 부팅한 기기도 끄지 않는다. 다른 프로젝트가 같은 기기를 쓸 수 있다). SpringBoard 크래시 창이 떠도 테스트 결과로만 판정하고 기록한다. 이어서 `./scripts/build-apple.sh ios-device; echo "exit=$?"`와 `./scripts/build-apple.sh mac; echo "exit=$?"` → 둘 다 `exit=0`. 빌드 로그의 경고가 Global Constraints 허용 목록뿐인지 본다. 실제 숫자·종료 코드·커밋 해시(`git rev-parse --short HEAD`)를 적어 두고 아래 문서에 그대로 쓴다. 기대와 다르면 실제 값을 쓰고, 실패면 통과로 쓰지 않는다.

- [ ] **Step 2: 1.2.0 변경사항**

`fastlane/release_notes/1.2.0.json`:

```json
{
  "ko": "인물 보정 기능을 추가했습니다.\n- 뷰티: 모공 질감을 살린 피부 보정과 자동 잡티, 얼굴형 10가지(얼굴 폭·턱선·광대·눈 크기·눈 간격·코 폭·입 크기·미소·이마·턱 길이), 눈 또렷하게·치아 미백·입술 생기\n- 메이크업: 립 6색·블러셔 4색·아이섀도 4색·눈썹·쉐딩, 룩 5종(데일리·쿨톤·웜피치·로지·스모키)\n- 체형: 다리 길게·허리·몸 전체·팔·허벅지·어깨·목(사진에서 가장 큰 한 사람)\n- 배경: 사람은 그대로 두고 배경만 흐리기\n- 자동 보정이 얼굴이 있으면 피부 보정·자동 잡티·눈 또렷하게를 함께 켭니다\n과하거나 어색한 보정이 있으면 어떤 사진에서 어느 항목이었는지 알려주세요."
}
```

Run: `ruby -rjson -e 'n = JSON.parse(File.read("fastlane/release_notes/1.2.0.json")); abort("keys") unless n.keys == ["ko"]; abort("blank") if n["ko"].strip.empty?; abort("long") if n["ko"].length > 4000; puts n["ko"].length'` → 4000 이하 숫자 한 줄. `/usr/bin/ruby fastlane/test/release_notes_test.rb` → `0 failures, 0 errors`.

- [ ] **Step 3: README·APPLE.md·modules.md**

`README.md`:
- "첫 보정" 3번의 "얼굴형·체형은 건드리지 않습니다."를 "얼굴형·체형·메이크업은 건드리지 않습니다."로.
- 5번의 "뷰티·체형·배경 값(피부 보정·자동 잡티·얼굴형 10개·눈·입 3개·체형 7개·배경 흐림)"을 "뷰티·메이크업·체형·배경 값(피부 보정·자동 잡티·얼굴형 10개·눈·입 3개·메이크업 부위 색·강도·체형 7개·배경 흐림)"으로.
- 6번(뷰티) 뒤에 새 항목 "**메이크업**에서 데일리·쿨톤·웜피치·로지·스모키 룩을 고르거나, 립(6색)·블러셔(4색)·아이섀도(4색)·눈썹·쉐딩 탭에서 색과 강도를 고릅니다. 룩을 고른 뒤 부위를 바꾸면 룩 선택이 풀리고, *없음*은 메이크업을 모두 지웁니다. 쉐딩은 광대 아래·턱선·코 옆을 어둡게, 콧대·이마·턱 끝을 밝게 합니다. 수동 잡티·변형이 있어도 쓸 수 있습니다."를 넣고 이후 번호를 하나씩 민다.
- 도구 줄 문장을 "필터 · 자동 · 자르기 · 조정 · 뷰티 · 메이크업 · 체형 · 배경 · 잡티 · 변형 순서입니다."로.
- "구현된 범위"의 눈·입 줄 아래에 "- 입술·볼·눈꺼풀·눈썹·얼굴 윤곽 영역에서만 색을 얹는 메이크업(립·블러셔·아이섀도·눈썹·쉐딩/하이라이터, `shared/makeup/makeup.v1.json`의 팔레트와 룩 5종)"을 더한다.
- 한계 문단의 "Evoto와 동일한 보정 품질은 구현하지 않았습니다." 앞에 "메이크업도 학습 모델 없이 Vision 특징점으로 동작하며, 특징점을 찾지 못한 얼굴은 바꾸지 않고(안내 문구가 보입니다) 머리카락이 볼·이마를 덮으면 블러셔·하이라이터가 머리카락에도 얹힐 수 있습니다. "를 넣는다.
- 검증 문단의 커널 언어 API 설명은 그대로 둔다(F는 새 커널을 더하지 않았다).
- 로드맵 "F 메이크업" 줄을 "**F 메이크업**: 메이크업 룩 5종과 부위별 색·강도 (`makeup`) — 구현됨, 실제 인물 사진 확인은 사용자 조치로 남음"으로.

`docs/APPLE.md`:
- 도구 줄 문장을 "**필터 · 자동 · 자르기 · 조정 · 뷰티 · 메이크업 · 체형 · 배경 · 잡티 · 변형**"으로.
- 뷰티 줄 끝에 "대상 얼굴에 특징점이 없으면 얼굴형·눈·입이 바뀌지 않는다는 안내가 보입니다."를 더한다.
- 뷰티 줄 아래(체형 줄 위)에 "- 메이크업: 룩 칩(*없음*·데일리·쿨톤·웜피치·로지·스모키) 아래 *립·블러셔·아이섀도·눈썹·쉐딩* 탭. 립·블러셔·아이섀도는 색 칩(같은 칩을 다시 누르면 색을 뺌, 처음 고르면 강도 0.5)과 *강도*, 눈썹·쉐딩은 *강도*만. 룩을 고르면 다섯 부위 값을 한 번에 채우고(실행 취소 한 번), 부위를 바꾸면 룩 선택이 풀립니다. 색만 바꾸므로 수동 잡티·변형이 있어도 잠기지 않습니다. 메이크업 목록 파일을 읽지 못하면 안내를 보입니다." 줄을 넣는다.
- 체형·배경 줄의 "안내를 보이고 슬라이더를 끕니다."를 "안내를 보이고 슬라이더를 끕니다(프리셋으로 들어온 0이 아닌 값은 되돌릴 수 있게 켭니다)."로.
- "검증 상태" 문단을 Step 1의 실제 결과(브랜치 `beauty-b-to-f`, 커밋, 종료 코드, 패키지 322개(MellowShared 43 · MellowRendering 216 · MellowLibrary 30 · MellowExport 4 · MellowEditing 29), 앱 iPhone 65 · iPad 65 · Mac 66 예상)로 바꾼다.
- 기기 확인 항목에 "메이크업 5룩과 부위별 색의 실제 인물 사진 결과(어두운·밝은 입술, 앞머리·안경, 기울어진 얼굴, 여러 사람, 특징점을 못 찾은 얼굴 안내)"를 더한다.

`docs/architecture/modules.md`:
- MellowShared 공개 API에 `MakeupCatalog`, `MakeupLook`, `MakeupColor`를 더한다. 규칙에 "메이크업 팔레트·룩은 `shared/makeup/makeup.v1.json`을 `MakeupCatalog`로 읽고 형식 위반(모르는 부위, rgb 개수·범위, 중복 id, 다른 부위 색을 쓰는 룩, 범위 밖 강도)은 파일 전체를 거부, 렌더용 색은 `color(id:for:)`가 그 부위 팔레트에서만 찾음"을 더한다. 테스트 칸에 "메이크업 카탈로그"를 더한다.
- MellowEditing 규칙에 "메이크업 룩은 `applyMakeupLook`이 체크포인트 한 번으로 부위 값을 채우고 부위 값이 바뀌면 `lookID`를 비움, 색을 처음 고를 때 강도 0이면 `makeupDefaultIntensity`, 메이크업은 수동 편집 잠금 대상 아님"을 더한다.
- MellowRendering 규칙의 단계 순서를 `skin` → `feature` → `makeup` → `background` → `shapeWarp` → `localEdit` → `geometry` → `color` → `detail` → `look`으로 바꾸고, "메이크업은 `RenderContext.makeupCatalog`(기본 빈 카탈로그)의 그 부위 팔레트 색만 쓰고 없으면 그 부위만 건너뜀(오류 아님), 마스크는 `FaceRegions`(확장 `FaceRegions+Makeup.swift`) 한 곳에서 만들고 립은 입술 생기와 같은 `lipMask`, 블러셔·쉐딩·하이라이터는 `FaceFrame` 좌표의 기운 타원 × 피부 다각형 비트맵(피부 보정과 같은 캐시 항목), 섞기는 Core Image 기본 섞기 모드(소프트 라이트·곱하기·스크린), 다각형 비트맵 캐시 상한은 얼굴 수 비례(`RegionMaskCache.capacity(forFaces:)`, 얼굴당 16·최소 32)"를 더한다. `PhotoPipeline` 문단의 `init(analyzer:personAnalyzer:bodyAnalyzer:tuning:lookCatalog:)`를 `init(analyzer:personAnalyzer:bodyAnalyzer:tuning:lookCatalog:makeupCatalog:)`로 바꾼다. 테스트 칸에 "메이크업(강도 0·모르는 색·다른 부위 색·빈 카탈로그·범위 밖 강도, 부위별 마스크 밖 같은 바이트, 블러셔·아이섀도·눈썹·쉐딩·하이라이터 위치, 기울어진 얼굴, 특징점 누락, 대상 얼굴만, 얼굴 셋 두 해상도 캐시 유지)"를 더한다.
- 앱 `Application/` 설명의 `EditorTool`을 `look, crop, adjust, beauty, makeup, body, background, retouch, warp`로 바꾸고, `AppModel` 생성자 문단에 `makeupCatalog`(번들 `makeup.v1.json`, 읽지 못하면 빈 카탈로그와 안내)를 더한다.

- [ ] **Step 4: 스펙 갱신 (CLAUDE.md 규칙 3)**

`docs/superpowers/specs/2026-10-15-beauty-b-to-f-design.md`:
- 결정 표의 마지막 "(E 구현 중 변경) …" 줄 아래에 두 줄을 더한다:
  - "| (F 구현 중 정함) 메이크업 섞기는 Core Image 기본 섞기 모드를 작업 색공간에서, 블러셔·쉐딩·하이라이터는 얼굴 좌표 타원 × 피부 다각형 비트맵 | 새 커널 언어 경고가 없고 기울어진 얼굴을 따라가며 캐시 항목이 늘지 않음. 감마 공간보다 조금 진할 수 있어 강도 상한은 `RenderTuning`에서 조정 | 작음 |"
  - "| (F 구현 중 변경) 다각형 비트맵 캐시 상한을 32 고정에서 얼굴 수 비례(얼굴당 16, 최소 32)로 | 메이크업 비트맵이 더해져 얼굴 셋부터 미리보기·저장을 오갈 때마다 비우고 다시 그렸음 | 작음 |"
- 1.2의 `EditChange` 목록에서 "`makeupLook(String?)`, "를 지우고 그 항목 끝에 "룩 적용은 `EditChange`가 아니라 `EditDocument.applyMakeupLook(MakeupLook?)`(스펙 6) 한 경로. (F 구현 중 변경: 처음 문구는 `makeupLook(String?)` 케이스 — 편집 규칙은 카탈로그를 몰라 id만으로 부위 값을 채울 수 없음.)"을 붙인다.
- 1.4의 "`RegionMaskCache`(다각형·extent 키, 32개 상한)"를 "`RegionMaskCache`(다각형·extent 키, 얼굴 수 비례 상한 — 얼굴당 16·최소 32)"로 바꾸고 문단 끝에 "(F 구현 중 변경: 처음 문구는 32개 상한.)"을 붙인다.
- 6의 데이터 항목 끝에 "`colors`는 부위별 객체(`lip`·`blush`·`eyeshadow`)이고 읽을 때 형식 위반(모르는 부위, rgb 개수·범위, 중복 id, 다른 부위 색을 쓰는 룩, 범위 밖 강도)은 파일 전체를 거부한다(F 구현 중 정함)."를, 룩 적용 항목 끝에 "룩 \"없음\"은 메이크업을 모두 지운다. 색을 처음 고를 때 강도가 0이면 0.5로 둔다(F 구현 중 정함)."를, `MakeupStage` 항목 끝에 "섞기는 작업 색공간. 위치: 블러셔 = 눈동자 u × 1.15·입~눈 45% 높이 타원, 아이섀도 = 윗눈꺼풀~눈썹 아래 75% 띠, 눈썹 = 가로 1.15·세로 1.6배, 쉐딩 = 광대 아래·턱선·코 옆, 하이라이터 = 콧대·이마 가운데·턱 끝, 모두 특징점이 없으면 건너뜀(F 구현 중 정함)."를 더한다.

- [ ] **Step 5: VALIDATION.md**

`## 인물 보정 E 체형 (2026-10-15)` 절 뒤, `## TestFlight 전용 배포 경로` 앞에 `## 인물 보정 F 메이크업 (2026-10-15)` 절을 쓴다. 사람 확인 영역만 있고, 실행한 것만 통과로 쓴다.
- 첫 문단: 브랜치·커밋·환경(E 절과 같은 형식), "이 절의 검증은 모두 자동 테스트와 빌드이며, 앱 화면을 직접 보거나 조작한 검증은 없습니다."
- `### 자동 검증`: `MELLOW_IOS_TESTS=1 ./scripts/test-apple.sh` 종료 코드, 패키지 테스트 수(모듈별), 앱 테스트 수(iPhone·iPad·Mac), `build-apple.sh ios-device`·`mac` 종료 코드, 빌드 경고(허용 목록, F가 더한 경고 없음), 1.2.0 변경사항 파일 검사(길이·`release_notes_test.rb` 결과), 실행 중 SpringBoard 크래시가 있었으면 그 사실.
- `### 자동 테스트가 확인하는 것`: 카탈로그(룩·색 id 순서, 값 범위, 룩이 자기 부위 색만, 형식 위반 거부, 번들 사본 바이트 동일), 편집(클램프, 색 처음 고를 때 0.5, 눈썹 색 무시, 룩 적용 한 단계·같은 룩 재적용 무단계, 부위 변경 시 룩 이름 풀림, 없음, 수동 편집이 있어도 잠기지 않음), 렌더(강도 0·얼굴 없음 같은 바이트, 립·블러셔·아이섀도·눈썹·쉐딩/하이라이터가 각 마스크 밖 바이트를 바꾸지 않음, 모르는 색·다른 부위 색·빈 카탈로그·특징점 없는 얼굴은 건너뜀, 범위 밖 강도, 미리보기·저장 모두 파이프라인 카탈로그 사용, 단계 순서), 마스크(블러셔 좌우 대칭·눈·입·얼굴 밖 0, 아이섀도 눈꺼풀 덮고 눈 0, 30° 기울인 얼굴을 따라감, 눈썹 넓힘·원래 상자 표본, 쉐딩·하이라이터 위치, 특징점·눈·눈썹·코 누락), 캐시(얼굴 수 비례 상한, 얼굴 셋 × 두 크기에서 비우지 않음), 대상 얼굴만, 앱(메이크업 도구 순서·실행 취소 단위·모르는 룩 무시·없음, 수동 편집과 함께, 카탈로그 없는 번들의 nil과 안내, 특징점 없는 얼굴 안내, 배경·체형 프리셋 값 되돌리기), 시나리오(데모 사진 → 피부 → 얼굴형 → 눈 → 배경 → 다리 길게 → 메이크업 데일리로 미리보기가 다시 바뀜 → 정사각형 저장, 스텁 분석기). "합성 얼굴과 스텁으로 돌며, 실제 사람에게 메이크업이 자연스러운지는 판단하지 않습니다."
- `### 스펙과 다르게 한 것`: `EditChange.makeupLook` 대신 `applyMakeupLook` 한 경로, 데이터 파일 형식 검증, 섞기 작업 색공간, 블러셔·쉐딩·하이라이터의 얼굴 좌표 타원 × 피부 다각형, 캐시 상한 얼굴 수 비례, 색 처음 고를 때 0.5, 없음 = 모두 지움, 룩 칩 썸네일 없음, 특징점 없는 얼굴 안내와 배경·체형 슬라이더 되돌리기(이월 정리), 상반신 다리 길게는 안내 유지.
- `### 미검증 (사용자 확인 필요)`: 실제 인물 사진의 메이크업 5룩과 14색 느낌·최대 강도, 어두운·밝은 입술의 립 색 변화, 앞머리·안경·머리카락이 볼을 덮은 사진, 기울어진·옆으로 돌린 얼굴, 단체 사진, 메이크업 도구 화면(룩 칩·5개 부위 탭·색 칩이 iPhone 폭에 들어가는지), 48MP 원본 저장 속도와 메모리(메이크업 포함), iPhone·iPad 실기기. "이전 절(E, D, C, B, B0, 구조 리팩토링 A)의 미검증 항목은 그대로 승계합니다."
- `### 1.2.0 TestFlight에서 확인할 것 (B~F 통합)`: 실제 인물·전신 사진으로 피부 보정·자동 잡티, 얼굴형 10종, 눈·치아·입술, 배경 흐림 경계, 체형 7종, 메이크업 5룩을 보고 과하거나 약한 항목을 적기(수치는 `RenderTuning`과 `shared/makeup/makeup.v1.json` 한 곳에서 조정), 시뮬레이터·구형 기기의 분석 실패 안내, 1.2.0 변경사항 문구. "배포(`scripts/release.sh apple 1.2.0`, 태그 푸시)는 머지 뒤 별도로 실행하며 이 절을 쓸 때는 실행하지 않았습니다."

- [ ] **Step 6: 커밋**

```bash
git add fastlane/release_notes/1.2.0.json README.md docs/APPLE.md docs/architecture/modules.md VALIDATION.md docs/superpowers/specs/2026-10-15-beauty-b-to-f-design.md
git commit -m "docs: 메이크업 사용법·모듈 캔버스·스펙·F 검증 기록과 1.2.0 변경사항

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

## 자체 검토 결과

- **스펙 대조:** §1.1 → `MakeupCatalog`·`MakeupLook`·`MakeupColor`(Shared/API, Task 1), `MakeupStage`(Domain, Task 3), 새 import 없음·`verify-modules.sh` 불변. §1.2 → `EditChange.makeupColor`·`makeupIntensity`(Task 2), `makeupLook(String?)`은 `applyMakeupLook`으로 대체(결정 표, 스펙 문구는 Task 9), `affectsGeometry`는 메이크업에서 false(Task 2 테스트), 범위는 `AdjustmentRange.unit` 한 곳, `dependsOnFaces`·`allValuesFinite`·`PresetValues`의 메이크업은 B에서 끝남(확인한 기존 동작). §1.3 → `makeup`을 `feature`와 `background` 사이(Task 3, 순서 배열 갱신). §1.4 → `RenderContext.makeupCatalog` 기본값(Task 3), 캐시 상한 변경(Task 6, 스펙 문구는 Task 9). §6 → 데이터 파일·README·번들 사본(Task 1), 팔레트 14색·룩 5개(Task 1), `MakeupCatalog(data:)`·`empty`·`look(id:)`·`color(id:)`(Task 1), 디코드 오류 → 앱 안내(Task 8), 룩 적용 규칙(Task 2), 립 소프트 라이트(Task 3), 블러셔 소프트 라이트·아이섀도 곱하기(Task 4), 눈썹 곱하기·쉐딩 곱하기·하이라이터 스크린(Task 5), 테스트 4종(카탈로그 디코드·번들 동일: Task 1, 강도 0 같은 바이트: Task 3 `testZeroIntensityOrNoFacesReturnInputBytes`, 립 색이 입술 마스크 안에서만: Task 3 `testLipColorChangesOnlyTheLipRing`, 룩 적용 후 부위 값 일치·실행 취소 1회: Task 2 `testApplyMakeupLookIsOneUndoStepAndPartEditsDetachLook`·Task 8 `testMakeupToolAppliesLookOnceAndPartEditsDetachLook`). §7 → `EditorTool.makeup`(Task 8), `AppModel` 카탈로그 로드·`applyMakeupLook`(Task 8), 자동 보정은 B·D에서 끝남, `UserMessage` 도구 이름·부위 탭 이름·"메이크업 목록을 읽지 못함"(Task 8), `Theme` 메이크업 칩 크기(Task 8). §8 → 각 Task 테스트, 순서 배열(Task 3), `AppModelTests`(새 도구 전환·룩 적용 실행 취소: Task 8, 분석 실패 안내: Task 7 `faceAvailability`), 시나리오의 메이크업 데일리(Task 8), 전체 검증·VALIDATION F 절(Task 9). §9 → 파일 이름과 주요 Task(메이크업 데이터·카탈로그, MakeupStage, 룩 적용 규칙, 메이크업 도구, 문서·VALIDATION·1.2.0 노트)가 표와 같다. "외부 효과가 있는 단계" → 계획 안에서는 실행하지 않고 Task 9가 1.2.0 노트만 커밋.
- **이월:** (a) 캐시 → Task 6, (b) `lipMask` 재사용·새 마스크는 `FaceRegions`만 → Task 3·4·5, (c) `makeupCatalog` 기본값 → Task 3, (d) 메이크업 편집 변경·룩 적용·잠기지 않음 → Task 2, (e) 프리셋·일괄 → B에서 구현됨(확인), (f) 특징점 없는 얼굴 안내·배경 슬라이더 되돌리기·다리 길게 → Task 7(다리 길게는 안내 유지로 결정), (g) 문서·`MELLOW_IOS_TESTS=1` 한 번·시뮬레이터 끄지 않음 → Task 9.
- **타입 일관성:** `MakeupCatalog(looks:palettes:)`·`init(data:)`·`look(id:)`·`colors(for:)`·`color(id:)`·`color(id:for:)`·`isEmpty`, `MakeupLook.adjustments`, `MakeupColor.red/green/blue`, `MakeupAdjustments.colorID(of:)`·`setColorID(_:of:)`·`setIntensity(_:of:)`, `EditChange.makeupColor`·`makeupIntensity`, `EditingPolicy.makeupDefaultIntensity`, `EditDocument.applyMakeupLook(_:)`, `RenderContext(…makeupCatalog:…)`, `PhotoPipeline.init(…makeupCatalog:)`, `MakeupStage.colorImage`·`solid`·`blended`·`mixed`·`softLight`·`multiply`·`screen`, `MaskBuilder.ellipse(center:radii:angle:extent:strength:)`, `FaceRegions.skinPolygonRaster`·`featheredPolygonMask(…feather:)`·`Oval`·`blushMask`·`eyeshadowMask`·`lidPolygon`·`softMask`·`BrowRegion`·`browRegions`·`ContourRegions`·`contourRegions`, `RegionMaskCache.capacity(forFaces:)`·`minimumEntries`·`maximumEntries`, `AppModel.FaceAvailability`·`faceAvailability`·`canAdjustBackgroundBlur`·`canAdjustBodyShape(_:)`·`makeupCatalog`·`makeupPart`·`applyMakeupLook(id:)`·`bundledMakeupCatalog(in:)`, `TestSupport.makeModel(…makeupCatalog:…)`를 정의한 Task와 쓰는 Task에서 같게 썼다. 테스트 수: 패키지 298 → 301 → 303 → 308 → 314 → 319 → 322 → 322 → 322, 앱 Mac 61 → 62 → … → 64(Task 7) → 66(Task 8), iPhone·iPad 60 → 61 → 63 → 65.
- **Review Focus 매핑:** 1→Task 3, 2→Task 4·5·7, 3→Task 4, 4→Task 6, 5→Task 1·8. 모두 테스트 코드가 있다.
- **플레이스홀더 점검:** "TBD/TODO/나중에" 없음. Task 4·5의 표본 점 실패 시 조치와 Task 9 문서 수치는 실제 실행 결과로 쓴다고 명시했다.
