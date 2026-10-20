# 인물 보정 G4-1 주름 재설계·보이는 강도 구현 계획

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 실사진(실제 Vision, `demo-portrait.png`)에서 폰 화면 배율로 잰 "보이는 강도" 하한과 "자연스러움" 상한을 테스트로 고정한 뒤, 그 테스트가 통과하도록 주름 띠 위치·주름 밝히기 기준·그레인·붉은기·번들거림·몸 피부 톤 상수를 고친다. 사람 영역이 없어도 얼굴이 있으면 몸 피부가 동작하게 하고 피부톤 탭에 조건 상태 줄을, 정보 시트에 진단 절을 더한다.

**Architecture:** 측정은 테스트 지원 `DisplayScale`(가로 1170px Lanczos 축소 뒤 `PixelGrid`)과 `RealPortrait`(데모 사진 + 실제 Vision 분석 한 번 캐시)로 한다. 렌더 변경은 `FaceRegions+Folds.swift`(띠 기하와 주름용 피부 비트맵), `SkinKernels.foldLift`(피부 마스크 가중 넓은 평균을 기준으로), `SkinStage.refine`(피부 마스크를 먼저 만들어 주름에 넘김), `BodySkinStage`(대체 영역), `RenderTuning` 상수에 한정된다. 파이프라인 단계 순서·레시피·모듈 표는 바뀌지 않는다.

**Tech Stack:** Swift 5.9 tools / Swift 5 언어 모드, Core Image(CILanczosScaleTransform·CIGaussianBlur·CIMultiplyCompositing·CIKL), Vision(테스트에서 실제 분석), SwiftUI + Observation(상태 줄·진단), XCTest, XcodeGen 2.46.0.

**Spec:** `docs/superpowers/specs/2026-10-21-beauty-g4-one-touch-design.md` (1절 보이는 강도·상한, 2절 주름·몸 피부 조건, 6절 진단, 7.1·7.2, 8). 선행: 없음(main `74fb2df`).

## 사람이 확인할 것

- **순서.** Task 1 측정 도우미와 수용 테스트(하한·상한, 지금 코드에서 주름·그레인·붉은기·번들거림·몸 피부 톤이 빨강) → 2 주름 띠 → 3 밝히기 기준 → 4 상수·몸 피부 대체 영역·피부톤 상태 줄 → 5 진단 절 → 6 문서·VALIDATION. 6개 Task, Task마다 Opus 구현 → 리뷰 → 수정, 끝에 전체 리뷰.
- **외부 효과가 있는 단계.** 없음. 푸시·태그·TestFlight·CI 복구는 하지 않는다(사용자 조치).
- **스펙이 정하지 않아 이 계획이 정한 것.**

| 결정 | 이유 | 바꾸면 비용 |
|---|---|---|
| 실사진 분석(`RealPortrait`)은 테스트 프로세스에서 한 번만 하고 `static let shared`로 나눠 쓴다 | Vision 세 가지 분석이 사진당 1초 안팎이라 테스트마다 하면 느리다 | 작음 |
| 합성 결함을 심은 이미지는 `Renderer.makeCGImage`로 굳힌 비트맵이다 | 그래프 입력이면 단계가 같은 그래프를 두 번 계산하고 "마스크 밖 바이트 동일" 비교가 흔들린다(`SyntheticFace.makeWithBody`와 같은 이유) | 작음 |
| 질감(fine 대역 분산 비)은 화면 배율이 아니라 **원본 배율**에서 잰다 | 축소가 모공 대역을 먼저 지워 비가 뜻을 잃는다. 하한(보임)은 화면 배율, 상한(질감)은 원본 배율 | 작음 |
| 주름용 피부 비트맵은 메이크업·피부 보정 비트맵과 별개 캐시 항목이다(얼굴당 해상도마다 9 → 10) | 보호 영역 넓힘 폭이 달라 같은 비트맵을 쓸 수 없다 | 작음 |
| 몸 피부 대체 영역은 직사각형을 흐린 부드러운 사각형이고 `MaskBuilder.ellipse`는 쓰지 않는다 | 어깨·팔은 타원 밖으로 벗어난다 | 작음 |
| 피부톤 탭 상태 줄은 `AppModel.bodySkinStatus` 다섯 가지 중 하나이고 `canAdjustBodySkin`이 `.ready`·`.fallback`에서 켜진다(기존 "프리셋 값이 0이 아니면 켬" 규칙 유지) | 조건을 숨기지 않는다 | 작음 |
| 진단 줄의 키 경로는 영어 식별자(`effects.grain=1.00`), 라벨만 한국어 | 모듈 값 이름을 그대로 보이는 것이 디버깅에 맞다 | 작음 |

- **범위 밖(다른 계획).** 원터치(G4-2·G4-3), 사람별·성별(H), 생성 사진(H3 Task 1).
- **위험.** 문턱이 데모 사진 한 장 기준이다. Task 1에서 빨강인 테스트가 Task 2~4 뒤에도 빨강이면 스펙 1.2·1.4의 조정 후보 상수를 올리거나 내린다. 문턱을 바꾸는 것은 사용자 승인 뒤(스펙 규칙).
- **사용자 조치.** Task 6 뒤 CI 요금 한도 해제, (질문 4에 따라) 1.3.1 TestFlight, 기기에서 그레인·다크서클·팔자·피부 밝기 스크린샷과 그레인 1 저장본 확인, 피부톤 상태 줄·진단 절 스크린샷.

---

## 에이전트 참조

## Global Constraints

- 작업 위치: main `74fb2df`에서 분기한 브랜치 `beauty-g4`(worktree를 쓰면 `/Users/mj/IdeaProjects/mellow-photo/.claude/worktrees/beauty-g4`). `PhotoPickerButton.swift`·`project.yml`·`scripts/test-apple.sh`·UI 테스트 타깃은 건드리지 않는다. 모든 Swift·xcodebuild 명령 전에 `export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`.
- 시작 조건: `git log --oneline -1`이 `74fb2df` 또는 그 뒤 main. 작업 트리에 미추적 `apple/Tests/MellowRenderingTests/ZZMeasureGTests.swift`(임시 측정 파일)가 있으면 지운다(커밋하지 않는다).
- 모듈 의존성 표(`docs/architecture/modules.md`)와 `scripts/verify-modules.sh`는 바뀌지 않는다. MellowRendering은 `CoreImage`·`Foundation`·`MellowShared`·`Vision`·`ImageIO`·`UniformTypeIdentifiers`만 import한다. 레시피 키·스키마는 바뀌지 않는다.
- 파이프라인 단계 이름 순서 불변. 새 단계 없음. 마스크는 `FaceRegions`(확장 파일 포함) 한 곳, 피부 CIKL 커널은 `SkinKernels` 한 곳.
- `RenderTuning` 변경(스펙 1.3): `grainMaxAmplitude` 0.30, `grainSizeFraction` 0.0025, `rednessFlushMax` 0.06, `rednessClearMax` 1.0, `rednessReferenceOffset` 0.01(신설), `shineLumaOffset` 0.08, `shineLumaRamp` 0.08, `bodySkinToneMax` 0.05, `foldSurroundFraction` 0.18, `foldFeatureFeather` 0.012(신설), `bodySkinFallbackWidthScale` 3·`bodySkinFallbackHeightScale` 4·`bodySkinFallbackFeather` 0.05(신설). `FoldShape` 변경은 Task 2. 캐시 `entriesPerFacePerResolution` 9 → 10.
- 한 줄 한 문장, 세미콜론 금지, 매직 넘버는 명명 상수(`RenderTuning`·`Theme`·`AppModel.Policy`·`EditingPolicy`, 기하 비율은 `FoldShape`, 테스트 문턱은 `Visibility`·`Naturalness`). CIKL 안 표준 계수(BT.601·BT.709)는 주석으로 이름을 단다.
- 한국어 사용자 문구는 앱 타깃(`UserMessage`·뷰)에만. 모듈은 `MellowError`만 던진다(새 case 없음).
- CI는 Xcode 26.3이다(로컬 27). `CGFloat`와 `Double`을 섞는 삼각함수·`hypot`·`atan2`는 인자 타입을 명시 변환한다.
- `cd apple && swift format lint --strict --recursive Sources Tests MellowPhoto MellowPhotoTests MellowPhotoUITests` 출력 없음(한도 120자). 허용된 빌드 경고: 기존 `CIColorKernel(source:)`·`CIWarpKernel`·`CIKernel(source:)` 지원 중단, 시뮬레이터 `usesCPUOnly`.
- `./scripts/verify-modules.sh` 통과. 패키지 테스트: `cd apple && swift test`(모듈마다 `Executed N tests`). Mac 앱 테스트: `xcodebuild -project apple/MellowPhoto.xcodeproj -scheme MellowPhoto -derivedDataPath apple/build -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO test 2>&1 | grep -E "Executed|TEST (SUCCEEDED|FAILED)|error:"`.
- **iOS 시뮬레이터 테스트는 로컬에서 돌리지 않는다.** `MELLOW_IOS_TESTS`를 켜지 않는다. `./scripts/test-apple.sh`는 로컬에서 iOS를 건너뛴다(그대로 쓴다). iOS 검증은 CI(사용자가 요금 한도를 푼 뒤)다. Xcode를 열거나 앱·시뮬레이터를 띄우지 않는다.
- 푸시·태그·`scripts/release.sh` 실행 금지.
- 커밋: 한국어 Conventional Commits, 마지막 줄 `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`. `git add`는 Task에 나열한 경로만. `git add -A`·`git commit -a` 금지.
- 기준 테스트 수(VALIDATION G 최종 리뷰 기준, **시작 전에 `swift test`와 Mac 앱 테스트로 실측해 이 줄에 적는다**): 패키지 384(Shared 49 · Rendering 262 · Library 32 · Export 4 · Editing 37), 앱 Mac 79. 이 계획이 더하는 수: **Rendering +14, 앱 Mac +2**(Task 1 Rendering +13, Task 4 Rendering +1·Mac +1, Task 5 Mac +1). 아래 "Executed N tests"는 명목치이므로 실측 기준값에 같은 증분을 더해 읽는다.
- 실사진 테스트는 macOS Vision이 돌려주는 특징점에 기댄다. Vision 버전이 바뀌어 얼굴 수가 1이 아니면 `RealPortrait` 생성이 실패하고 모든 수용 테스트가 실패한다 — 그때는 VALIDATION에 적고 사용자에게 알린다(문턱을 손대지 않는다).
- 문턱을 못 넘으면 스펙 1.2·1.4의 "조정 후보" 상수를 고친다. 문턱 수치 자체를 바꾸는 것은 사용자 승인이 있을 때만이고 VALIDATION에 적는다.

## Review Focus

1. **데모 사진에서 주름 4종을 1로 올린다(결함 없음).** 띠 안 색차 변화 ≤ 0.01, 어느 띠도 평균 ΔY +0.08을 넘지 않아야 한다(밝은 얼룩 없음). → Task 1 `testDarkCirclesLiftUnderTheEyesVisiblyAndNaturally` 등의 상한 단언.
2. **눈 보호 영역 넓힘을 1.2%로 줄여도 눈 안은 0이어야 한다.** → Task 2 `FoldRegionsTests`의 "밖" 점(`leftEye`·`scleraPoint`).
3. **띠 둘레가 전부 보호 영역이라 가중 평균 분모가 0에 가깝다.** 배율은 1(밝히지 않음)이어야 한다. → Task 3 `testFoldLiftWithEmptySurroundLeavesTheBandUnchanged`.
4. **사람 영역이 없는 사진에 얼굴만 있다.** 피부 밝기가 얼굴 둘레 피부에 걸리고 옷·배경은 그대로, 상태 줄은 "대체". → Task 4 `testBodySkinFallsBackToTheFaceNeighbourhoodWithoutAPersonMask`, `testSkinToneStatusLineReflectsPersonAndFaceConditions`.
5. **그레인 1을 폰 배율로 축소한다.** 휘도 차이 표준편차 ≥ 5/255이고 평균 밝기는 ±1 안. → Task 1 `testGrainIsVisibleAtPhoneScale`, 기존 `testGrainIsDeterministicAndKeepsMeanBrightness`.
6. **얼룩 고르기 1과 피부 보정 1에서 모공이 남는다.** fine 분산 비 ≥ 0.85. → Task 1 `testSkinSmoothingChangesTheFaceButKeepsPores`, `testToneEveningEvensSkinButKeepsPores`.

## 인터페이스 요약 (모든 Task가 공유하는 이름)

```swift
// 테스트 지원 (Task 1, apple/Tests/MellowRenderingTests/RenderingTestSupport.swift)
enum DisplayScale {
    static let phoneWidth: CGFloat = 1170
    static func grid(_ image: CGImage) throws -> PixelGrid
    static func grid(_ image: CIImage) throws -> PixelGrid
    static func rect(_ normalized: NormalizedRect, in grid: PixelGrid) -> CGRect
    static func changedFraction(_ before: PixelGrid, _ after: PixelGrid, in rect: CGRect?, minimumDelta: Int) -> Double
    static func lumaDelta(_ before: PixelGrid, _ after: PixelGrid, weight: PixelGrid?) -> (mean: Double, meanAbsolute: Double)   // 8비트 단위
    static func chromaDelta(_ before: PixelGrid, _ after: PixelGrid, weight: PixelGrid?) -> (cb: Double, cr: Double)            // 0…1
    static func channelDelta(_ before: PixelGrid, _ after: PixelGrid, channel: Int, weight: PixelGrid?) -> Double              // 8비트 평균 Δ
    static func lumaDeltaStandardDeviation(_ before: PixelGrid, _ after: PixelGrid, in rect: CGRect?) -> Double
    static func percentileAbsoluteLumaDelta(_ before: PixelGrid, _ after: PixelGrid, in rect: CGRect, percentile: Double) -> Double
    static func luma(_ grid: PixelGrid, weight: PixelGrid) -> Double                                                             // 가중 평균 Y(8비트)
    static func recovery(original: Double, defective: Double, repaired: Double) -> Double
}
final class RealPortrait { static let shared: RealPortrait; image: CIImage; extent: CGRect; analysis: PhotoAnalysis; face: FaceGeometry; faceWidth: CGFloat; tuning: RenderTuning
    func context(_ recipe: EditRecipe, image: CIImage? = nil) -> RenderContext
    func render(_ recipe: EditRecipe, stage: (any RenderStage)? = nil, input: CIImage? = nil) throws -> CGImage
    func baked(_ image: CIImage) throws -> CIImage
    func mask(_ region: FaceRegions.RegionMask?) throws -> PixelGrid        // 화면 배율 회색 격자
    func skinMask(strength: Double = 1) throws -> CIImage }
enum SyntheticDefect { static func shadowed(_:mask:depth:) -> CIImage; static func reddened(_:center:radius:extent:) -> CIImage; static func highlighted(_:center:radius:lift:extent:) -> CIImage }
RenderingTestSupport.fineVarianceRatio(before:after:in:fineRadius:midRadius:) -> Double

// MellowRendering (Task 2)
FaceRegions.foldSkinRaster(face:extent:tuning:cache:) -> CIImage
FaceRegions.softMask(_:face:frame:extent:tuning:cache:raster:)        // raster 기본값 = skinPolygonRaster
FoldShape.darkCircleDropFraction, darkCircleRadiusVFraction, nasolabialOverrun, nasolabialOutset(0.045), nasolabialHalfWidth(0.03), marionetteLength(0.14), marionetteRadiusU(0.08), marionetteOutset(0.03)
RegionMaskCache.entriesPerFacePerResolution = 10

// MellowRendering (Task 3)
SkinKernels.foldLift(image:low:wideNumerator:wideDenominator:amount:maxGain:lumaFloor:extent:)
SkinRefinement.liftFold(_:region:skinMask:faceWidth:amount:tuning:extent:)
RenderTuning.foldSurroundFraction = 0.18, foldFeatureFeather = 0.012

// MellowRendering (Task 4)
SkinKernels.redness(encoded:reference:clear:flush:referenceOffset:extent:)
BodySkinStage.fallbackPersonRegion(face:extent:tuning:) -> CIImage
RenderTuning: 위 Global Constraints의 상수
// 앱 (Task 4)
AppModel.BodySkinStatus { ready, fallback, noFace, faceAnalysisUnavailable(MellowError), personAnalysisUnavailable(MellowError) }
AppModel.bodySkinStatus, canAdjustBodySkin(_:)  (ready·fallback에서 켬)
UserMessage.bodySkinStatus(_:) 
// 앱 (Task 5)
AppModel.diagnosticLines: [String], lastRenderFailure: String?
RecipeSummary.nonDefaultLines(_ recipe: EditRecipe) -> [String]      // apple/MellowPhoto/Application/AppModel+Diagnostics.swift
UserMessage.diagnosticsTitle, copyDiagnostics, diagnosticLabel(_:)
```

---

### Task 1: 측정 도우미와 실사진 수용 테스트 (하한·상한)

**Files:**
- Modify: `apple/Tests/MellowRenderingTests/RenderingTestSupport.swift`
- Create: `apple/Tests/MellowRenderingTests/RealPhotoAcceptanceTests.swift`

**Interfaces:**
- Consumes: `ImageLoader`, `VisionFaceAnalyzer`, `VisionPersonAnalyzer`, `VisionBodyAnalyzer`, `PhotoAnalysis`, `RenderContext`, `RenderPipeline.standard`, 각 단계, `FaceRegions`의 마스크 함수, `FaceFrame`, `PixelGrid`.
- Produces: 인터페이스 요약의 Task 1 항목.

설계 근거: 스펙 1.1·1.2·1.4. 이 Task는 코드를 고치지 않고 **지금 코드의 실패를 테스트로 드러낸다**. 끝에 어떤 테스트가 빨강인지 적는다(Task 2~4가 초록으로 만든다).

- [ ] **Step 1: 테스트 지원 작성**

`RenderingTestSupport.swift` 끝에 추가:

```swift
/// 폰 화면 배율 측정. 비교할 이미지를 가로 1170px(iPhone 390pt × 3)로 맞춘 뒤 8비트로 읽는다(스펙 G4 1.1).
enum DisplayScale {
    static let phoneWidth: CGFloat = 1170
    /// 세 채널 중 최대 |Δ|가 이 값 이상이면 "바뀐 픽셀"이다.
    static let defaultMinimumDelta = 4
    /// BT.601 휘도 계수.
    private static let lumaWeights = (r: 0.299, g: 0.587, b: 0.114)
    /// BT.601 Cb·Cr 계수(0…1 값 기준).
    private static let cbWeights = (r: -0.168736, g: -0.331264, b: 0.5)
    private static let crWeights = (r: 0.5, g: -0.418688, b: -0.081312)

    static func grid(_ image: CGImage) throws -> PixelGrid {
        let source = CIImage(cgImage: image)
        let scale = phoneWidth / source.extent.width
        let height = (source.extent.height * scale).rounded(.down)
        let scaled = source.applyingFilter(
            "CILanczosScaleTransform", parameters: [kCIInputScaleKey: scale, kCIInputAspectRatioKey: 1]
        ).cropped(to: CGRect(x: 0, y: 0, width: phoneWidth, height: height))
        return PixelGrid(try RenderingTestSupport.renderer.makeCGImage(scaled))
    }

    static func grid(_ image: CIImage) throws -> PixelGrid {
        try grid(RenderingTestSupport.renderer.makeCGImage(image))
    }

    /// 정규화 사각형(원점 왼쪽 아래)을 격자 픽셀 사각형으로.
    static func rect(_ normalized: NormalizedRect, in grid: PixelGrid) -> CGRect {
        CGRect(
            x: normalized.x * Double(grid.width), y: normalized.y * Double(grid.height),
            width: normalized.width * Double(grid.width), height: normalized.height * Double(grid.height)
        ).intersection(CGRect(x: 0, y: 0, width: grid.width, height: grid.height)).integral
    }

    private static func points(_ grid: PixelGrid, in rect: CGRect?) -> [CGPoint] {
        let area = rect ?? CGRect(x: 0, y: 0, width: grid.width, height: grid.height)
        var result: [CGPoint] = []
        for y in Int(area.minY)..<Int(area.maxY) {
            for x in Int(area.minX)..<Int(area.maxX) {
                result.append(CGPoint(x: x, y: y))
            }
        }
        return result
    }

    private static func luma(_ rgba: [UInt8]) -> Double {
        lumaWeights.r * Double(rgba[0]) + lumaWeights.g * Double(rgba[1]) + lumaWeights.b * Double(rgba[2])
    }

    private static func chroma(_ rgba: [UInt8]) -> (cb: Double, cr: Double) {
        let r = Double(rgba[0]) / 255
        let g = Double(rgba[1]) / 255
        let b = Double(rgba[2]) / 255
        return (cbWeights.r * r + cbWeights.g * g + cbWeights.b * b, crWeights.r * r + crWeights.g * g + crWeights.b * b)
    }

    private static func weight(_ mask: PixelGrid?, _ point: CGPoint) -> Double {
        mask.map { Double($0.red(point)) / 255 } ?? 1
    }

    static func changedFraction(
        _ before: PixelGrid, _ after: PixelGrid, in rect: CGRect?, minimumDelta: Int = defaultMinimumDelta
    ) -> Double {
        let all = points(before, in: rect)
        guard !all.isEmpty else { return 0 }
        let changed = all.filter { point in
            let a = before.rgba(point)
            let b = after.rgba(point)
            return (0..<3).contains { abs(Int(a[$0]) - Int(b[$0])) >= minimumDelta }
        }
        return Double(changed.count) / Double(all.count)
    }

    /// 가중 평균 ΔY와 평균 |ΔY|(8비트). weight가 nil이면 전체 평균.
    static func lumaDelta(_ before: PixelGrid, _ after: PixelGrid, weight: PixelGrid?) -> (mean: Double, meanAbsolute: Double) {
        var total = 0.0
        var sum = 0.0
        var absolute = 0.0
        for point in points(before, in: nil) {
            let w = weight(weight, point)
            guard w > 0 else { continue }
            let delta = luma(after.rgba(point)) - luma(before.rgba(point))
            total += w
            sum += w * delta
            absolute += w * abs(delta)
        }
        guard total > 0 else { return (0, 0) }
        return (sum / total, absolute / total)
    }

    /// 가중 평균 |ΔCb|·|ΔCr|(0…1).
    static func chromaDelta(_ before: PixelGrid, _ after: PixelGrid, weight: PixelGrid?) -> (cb: Double, cr: Double) {
        var total = 0.0
        var cb = 0.0
        var cr = 0.0
        for point in points(before, in: nil) {
            let w = weight(weight, point)
            guard w > 0 else { continue }
            let a = chroma(before.rgba(point))
            let b = chroma(after.rgba(point))
            total += w
            cb += w * abs(b.cb - a.cb)
            cr += w * abs(b.cr - a.cr)
        }
        guard total > 0 else { return (0, 0) }
        return (cb / total, cr / total)
    }

    /// 가중 평균 채널 Δ(8비트, 부호 있음). channel 0 = R, 2 = B.
    static func channelDelta(_ before: PixelGrid, _ after: PixelGrid, channel: Int, weight: PixelGrid?) -> Double {
        var total = 0.0
        var sum = 0.0
        for point in points(before, in: nil) {
            let w = weight(weight, point)
            guard w > 0 else { continue }
            total += w
            sum += w * (Double(after.rgba(point)[channel]) - Double(before.rgba(point)[channel]))
        }
        return total > 0 ? sum / total : 0
    }

    static func lumaDeltaStandardDeviation(_ before: PixelGrid, _ after: PixelGrid, in rect: CGRect?) -> Double {
        let deltas = points(before, in: rect).map { luma(after.rgba($0)) - luma(before.rgba($0)) }
        return RenderingTestSupport.variance(deltas).squareRoot()
    }

    static func percentileAbsoluteLumaDelta(
        _ before: PixelGrid, _ after: PixelGrid, in rect: CGRect, percentile: Double
    ) -> Double {
        let deltas = points(before, in: rect).map { abs(luma(after.rgba($0)) - luma(before.rgba($0))) }.sorted()
        guard !deltas.isEmpty else { return 0 }
        let index = min(deltas.count - 1, Int(Double(deltas.count - 1) * percentile))
        return deltas[index]
    }

    /// 가중 평균 Y(8비트).
    static func luma(_ grid: PixelGrid, weight: PixelGrid) -> Double {
        var total = 0.0
        var sum = 0.0
        for point in points(grid, in: nil) {
            let w = weight(weight, point)
            guard w > 0 else { continue }
            total += w
            sum += w * luma(grid.rgba(point))
        }
        return total > 0 ? sum / total : 0
    }

    /// (복구 − 결함) ÷ (원본 − 결함). 1이면 완전 복구, 0이면 그대로.
    static func recovery(original: Double, defective: Double, repaired: Double) -> Double {
        let drop = original - defective
        guard abs(drop) > 1e-6 else { return 0 }
        return (repaired - defective) / drop
    }
}

/// 실사진 위에 심는 결함. 모두 실제 특징점 마스크·좌표를 쓴다(스펙 G4 1.1).
enum SyntheticDefect {
    /// image × (1 − depth × mask). 선형 공간 곱이다.
    static func shadowed(_ image: CIImage, mask: CIImage, depth: Double) -> CIImage {
        let factor = 1 - depth
        let dimmed = image.applyingFilter(
            "CIColorMatrix",
            parameters: [
                "inputRVector": CIVector(x: factor, y: 0, z: 0, w: 0),
                "inputGVector": CIVector(x: 0, y: factor, z: 0, w: 0),
                "inputBVector": CIVector(x: 0, y: 0, z: factor, w: 0),
            ])
        return MaskBuilder.blend(dimmed, over: image, mask: mask).cropped(to: image.extent)
    }

    /// 붉은 반점. 감마 공간에서 R × 1.12, G·B × 0.95(Cr 약 +0.05)인 단단한 원.
    static func reddened(_ image: CIImage, center: CGPoint, radius: CGFloat, extent: CGRect) -> CIImage {
        let encoded = image.applyingFilter("CILinearToSRGBToneCurve")
        let red = encoded.applyingFilter(
            "CIColorMatrix",
            parameters: [
                "inputRVector": CIVector(x: 1.12, y: 0, z: 0, w: 0),
                "inputGVector": CIVector(x: 0, y: 0.95, z: 0, w: 0),
                "inputBVector": CIVector(x: 0, y: 0, z: 0.95, w: 0),
            ])
        let mask = RenderingTestSupport.hardEllipse(
            center: center, radii: CGSize(width: radius, height: radius), extent: extent)
        return MaskBuilder.blend(red, over: encoded, mask: mask).applyingFilter("CISRGBToneCurveToLinear")
            .cropped(to: extent)
    }

    /// 반사광. 선형 휘도를 가우시안 봉우리(중심에서 lift)만큼 더한다.
    static func highlighted(_ image: CIImage, center: CGPoint, radius: CGFloat, lift: Double, extent: CGRect) -> CIImage {
        let blob = RenderingTestSupport.hardEllipse(
            center: center, radii: CGSize(width: radius, height: radius), extent: extent
        ).applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: radius / 2])
        let light = blob.applyingFilter(
            "CIColorMatrix",
            parameters: [
                "inputRVector": CIVector(x: lift, y: 0, z: 0, w: 0),
                "inputGVector": CIVector(x: lift, y: 0, z: 0, w: 0),
                "inputBVector": CIVector(x: lift, y: 0, z: 0, w: 0),
                "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 0),
            ])
        return light.applyingFilter("CIAdditionCompositing", parameters: [kCIInputBackgroundImageKey: image])
            .cropped(to: extent)
    }
}

/// 실제 Vision으로 분석한 데모 사진. 한 번만 준비해 모든 실사진 수용 테스트가 나눠 쓴다.
final class RealPortrait: @unchecked Sendable {
    static let shared: RealPortrait = {
        do {
            return try RealPortrait()
        } catch {
            fatalError("데모 사진 준비 실패: \(error)")
        }
    }()

    let image: CIImage
    let extent: CGRect
    let analysis: PhotoAnalysis
    let face: FaceGeometry
    let faceWidth: CGFloat
    let tuning = RenderTuning()

    private init() throws {
        guard
            let url = Bundle.module.url(forResource: "demo-portrait", withExtension: "png", subdirectory: "Fixtures")
        else { throw MellowError.cannotOpenPhoto(filename: "demo-portrait.png") }
        image = try ImageLoader().load(url: url, maxDimension: tuning.previewMaxDimension)
        extent = image.extent
        let faces = try VisionFaceAnalyzer().analyze(image)
        guard faces.count == 1 else { throw MellowError.faceAnalysisUnavailable(reason: "faces \(faces.count)") }
        let mask = try VisionPersonAnalyzer().personMask(image)
        let bodies = try VisionBodyAnalyzer().analyze(image)
        analysis = PhotoAnalysis(faces: faces, personMask: mask, bodies: bodies)
        face = faces[0]
        faceWidth = FaceRegions.faceWidth(face, extent: image.extent)
    }

    func context(_ recipe: EditRecipe, image input: CIImage? = nil) -> RenderContext {
        RenderContext(extent: (input ?? image).extent, recipe: recipe, analysis: analysis, tuning: tuning)
    }

    /// stage가 nil이면 전체 파이프라인.
    func render(_ recipe: EditRecipe, stage: (any RenderStage)? = nil, input: CIImage? = nil) throws -> CGImage {
        let source = input ?? image
        let context = self.context(recipe, image: source)
        let output = try stage.map { try $0.apply(source, in: context) } ?? RenderPipeline.standard.render(source, context: context)
        return try RenderingTestSupport.renderer.makeCGImage(output)
    }

    /// 그래프를 비트맵으로 굳힌다. 결함을 심은 입력은 굳혀서 넘긴다.
    func baked(_ graph: CIImage) throws -> CIImage {
        CIImage(cgImage: try RenderingTestSupport.renderer.makeCGImage(graph.cropped(to: extent)))
    }

    /// 영역 마스크를 화면 배율 격자로. nil이면 실패.
    func mask(_ region: FaceRegions.RegionMask?) throws -> PixelGrid {
        guard let region else { throw MellowError.renderFailed }
        return try DisplayScale.grid(region.image.cropped(to: extent))
    }

    func skinMask(strength: Double = 1) throws -> CIImage {
        try FaceRegions.skinMask(face: face, image: image, extent: extent, tuning: tuning, strength: strength)
    }
}

extension RenderingTestSupport {
    /// rect 안 fine 대역 분산의 후/전 비. 1이면 질감 그대로, 작으면 뭉갬. 원본 배율에서 잰다.
    static func fineVarianceRatio(before: CIImage, after: CIImage, in rect: CGRect, fineRadius: Double, midRadius: Double)
        throws -> Double
    {
        let first = try bandVariances(before, in: rect, fineRadius: fineRadius, midRadius: midRadius).fine
        let second = try bandVariances(after, in: rect, fineRadius: fineRadius, midRadius: midRadius).fine
        return first > 0 ? second / first : 1
    }
}
```

- [ ] **Step 2: 수용 테스트 작성**

`apple/Tests/MellowRenderingTests/RealPhotoAcceptanceTests.swift`:

```swift
import CoreImage
import MellowShared
import XCTest

@testable import MellowRendering

/// 실사진(실제 Vision) + 폰 화면 배율에서 "보이는 강도" 하한과 "자연스러움" 상한(스펙 G4 1.2·1.4).
/// 문턱을 못 넘으면 렌더 상수를 고친다. 문턱을 바꾸는 것은 사용자 승인 뒤 VALIDATION에 적는다.
final class RealPhotoAcceptanceTests: XCTestCase {
    typealias Support = RenderingTestSupport

    /// 하한(보여야 함). 화면 배율 8비트.
    enum Visibility {
        static let smoothingChangedFraction = 0.04
        static let darkCirclesChangedFraction = 0.010
        static let darkCirclesMeanLift = 3.0
        static let nasolabialChangedFraction = 0.005
        static let foldRecovery = 0.5
        static let toneEveningChangedFraction = 0.04
        static let toneEveningMeanAbsolute = 3.0
        static let rednessClearRemoval = 0.5
        static let rednessFlushRedLift = 5.0
        static let shineReduction = 0.4
        static let bodyBrightnessChangedFraction = 0.15
        static let bodyToneRedMinusBlue = 6.0
        static let bodySmoothingChangedFraction = 0.10
        static let grainStandardDeviation = 5.0
        static let grainMinimumCell = 2.5
        static let glowChangedFraction = 0.40
        static let eyeMeanAbsolute = 3.0
        static let lipMeanAbsolute = 4.0
        static let blushMeanAbsolute = 3.0
        /// 합성 그늘 깊이·반점·반사광 크기.
        static let shadowDepth = 0.25
        static let blotchRadiusFraction: CGFloat = 0.04
        static let highlightRadiusFraction: CGFloat = 0.06
        static let highlightLift = 0.3
        static let highlightHeightFraction: CGFloat = 0.25
    }

    /// 상한(자연스러워야 함).
    enum Naturalness {
        static let foldMaximumMeanLift = 0.08 * 255
        static let foldMaximumChroma = 0.01
        static let fineVarianceRatioMinimum = 0.85
        static let toneEveningMaximumMeanLift = 0.03 * 255
        static let bodyBrightnessMaximumMeanLift = 0.10 * 255
        static let outsideFaceChangedFraction = 0.002
        static let browChangedFraction = 0.05
    }

    private var portrait: RealPortrait { .shared }
    private static var baseline: (image: CGImage, grid: PixelGrid)?

    private func base() throws -> (image: CGImage, grid: PixelGrid) {
        if let baseline = Self.baseline {
            return baseline
        }
        let image = try portrait.render(EditRecipe())
        let baseline = (image, try DisplayScale.grid(image))
        Self.baseline = baseline
        return baseline
    }

    private func grid(_ change: (inout EditRecipe) -> Void, stage: (any RenderStage)? = nil, input: CIImage? = nil) throws
        -> PixelGrid
    {
        var recipe = EditRecipe()
        change(&recipe)
        return try DisplayScale.grid(portrait.render(recipe, stage: stage, input: input))
    }

    private var faceRect: CGRect {
        get throws { DisplayScale.rect(portrait.face.boundingBox, in: try base().grid) }
    }

    private func skinWeight() throws -> PixelGrid {
        try DisplayScale.grid(portrait.skinMask().cropped(to: portrait.extent))
    }

    private var bandRadii: (fine: Double, mid: Double) {
        FrequencySeparation.radii(faceWidth: portrait.faceWidth, tuning: portrait.tuning)
    }

    private func nativeFaceRect() -> CGRect {
        FaceRegions.pixelRect(portrait.face.boundingBox, in: portrait.extent).integral
    }

    // MARK: 피부

    func testSkinSmoothingChangesTheFaceButKeepsPores() throws {
        let before = try base()
        let after = try grid { $0.portrait.skin.smoothing = 1 }
        XCTAssertGreaterThanOrEqual(
            DisplayScale.changedFraction(before.grid, after, in: try faceRect), Visibility.smoothingChangedFraction)
        var recipe = EditRecipe()
        recipe.portrait.skin.smoothing = 1
        let output = try SkinStage().apply(portrait.image, in: portrait.context(recipe))
        let ratio = try Support.fineVarianceRatio(
            before: portrait.image, after: output, in: nativeFaceRect(), fineRadius: bandRadii.fine,
            midRadius: bandRadii.mid)
        XCTAssertGreaterThanOrEqual(ratio, Naturalness.fineVarianceRatioMinimum, "모공 대역은 남는다")
    }

    func testToneEveningEvensSkinButKeepsPores() throws {
        let before = try base()
        let after = try grid { $0.portrait.skin.toneEvening = 1 }
        let skin = try skinWeight()
        XCTAssertGreaterThanOrEqual(
            DisplayScale.changedFraction(before.grid, after, in: try faceRect), Visibility.toneEveningChangedFraction)
        let delta = DisplayScale.lumaDelta(before.grid, after, weight: skin)
        XCTAssertGreaterThanOrEqual(delta.meanAbsolute, Visibility.toneEveningMeanAbsolute)
        XCTAssertLessThanOrEqual(delta.mean, Naturalness.toneEveningMaximumMeanLift, "고르게 할 뿐 밝히지 않는다")
        var recipe = EditRecipe()
        recipe.portrait.skin.toneEvening = 1
        let output = try SkinStage().apply(portrait.image, in: portrait.context(recipe))
        XCTAssertGreaterThanOrEqual(
            try Support.fineVarianceRatio(
                before: portrait.image, after: output, in: nativeFaceRect(), fineRadius: bandRadii.fine,
                midRadius: bandRadii.mid),
            Naturalness.fineVarianceRatioMinimum)
    }

    // MARK: 주름

    private func foldMask(_ key: SkinRefinementKey) -> FaceRegions.RegionMask? {
        let extent = portrait.extent
        let tuning = portrait.tuning
        let face = portrait.face
        switch key {
        case .darkCircles: return FaceRegions.darkCircleMask(face: face, extent: extent, tuning: tuning)
        case .nasolabial: return FaceRegions.nasolabialMask(face: face, extent: extent, tuning: tuning)
        case .marionette: return FaceRegions.marionetteMask(face: face, extent: extent, tuning: tuning)
        case .glabella: return FaceRegions.glabellaMask(face: face, extent: extent, tuning: tuning)
        default: return nil
        }
    }

    /// 자연 사진에서의 상한 + 합성 그늘 회복률. 하한은 호출자가 더한다.
    private func assertFoldIsNaturalAndRecoversShadow(_ key: SkinRefinementKey, file: StaticString = #filePath, line: UInt = #line)
        throws
    {
        let region = try XCTUnwrap(foldMask(key), "\(key) 띠", file: file, line: line)
        let weight = try portrait.mask(region)
        let before = try base().grid
        let natural = try grid({ $0.portrait.skin[key] = 1 }, stage: SkinStage())
        let lift = DisplayScale.lumaDelta(before, natural, weight: weight)
        XCTAssertLessThanOrEqual(lift.mean, Naturalness.foldMaximumMeanLift, "\(key) 밝은 얼룩 없음", file: file, line: line)
        let chroma = DisplayScale.chromaDelta(before, natural, weight: weight)
        XCTAssertLessThanOrEqual(max(chroma.cb, chroma.cr), Naturalness.foldMaximumChroma, "\(key) 색 기 없음", file: file, line: line)
        var recipe = EditRecipe()
        recipe.portrait.skin[key] = 1
        let naturalOutput = try SkinStage().apply(portrait.image, in: portrait.context(recipe))
        XCTAssertGreaterThanOrEqual(
            try Support.fineVarianceRatio(
                before: portrait.image, after: naturalOutput, in: region.bounds.integral, fineRadius: bandRadii.fine,
                midRadius: bandRadii.mid),
            Naturalness.fineVarianceRatioMinimum, "\(key) 질감 유지", file: file, line: line)
        let shadowed = try portrait.baked(
            SyntheticDefect.shadowed(portrait.image, mask: region.image, depth: Visibility.shadowDepth))
        let defective = try DisplayScale.grid(shadowed)
        let repaired = try grid({ $0.portrait.skin[key] = 1 }, stage: SkinStage(), input: shadowed)
        let recovery = DisplayScale.recovery(
            original: DisplayScale.luma(before, weight: weight), defective: DisplayScale.luma(defective, weight: weight),
            repaired: DisplayScale.luma(repaired, weight: weight))
        XCTAssertGreaterThanOrEqual(recovery, Visibility.foldRecovery, "\(key) 합성 그늘 회복", file: file, line: line)
    }

    func testDarkCirclesLiftUnderTheEyesVisiblyAndNaturally() throws {
        let before = try base().grid
        let after = try grid({ $0.portrait.skin.darkCircles = 1 }, stage: SkinStage())
        XCTAssertGreaterThanOrEqual(
            DisplayScale.changedFraction(before, after, in: try faceRect), Visibility.darkCirclesChangedFraction)
        let weight = try portrait.mask(foldMask(.darkCircles))
        XCTAssertGreaterThanOrEqual(
            DisplayScale.lumaDelta(before, after, weight: weight).mean, Visibility.darkCirclesMeanLift, "눈 아래가 밝아진다")
        try assertFoldIsNaturalAndRecoversShadow(.darkCircles)
    }

    func testNasolabialLiftsTheFoldVisiblyAndNaturally() throws {
        let before = try base().grid
        let after = try grid({ $0.portrait.skin.nasolabial = 1 }, stage: SkinStage())
        XCTAssertGreaterThanOrEqual(
            DisplayScale.changedFraction(before, after, in: try faceRect), Visibility.nasolabialChangedFraction)
        try assertFoldIsNaturalAndRecoversShadow(.nasolabial)
    }

    func testMarionetteRecoversASyntheticShadow() throws {
        try assertFoldIsNaturalAndRecoversShadow(.marionette)
    }

    func testGlabellaRecoversASyntheticShadow() throws {
        try assertFoldIsNaturalAndRecoversShadow(.glabella)
    }

    // MARK: 붉은기·번들거림

    func testRednessClearsASyntheticBlotchAndFlushIsVisible() throws {
        let cheek = try XCTUnwrap(FaceRegions.cheekRects(face: portrait.face, extent: portrait.extent).first)
        let center = CGPoint(x: cheek.midX, y: cheek.midY)
        let radius = portrait.faceWidth * Visibility.blotchRadiusFraction
        let blotchy = try portrait.baked(
            SyntheticDefect.reddened(portrait.image, center: center, radius: radius, extent: portrait.extent))
        let disc = try DisplayScale.grid(
            Support.hardEllipse(center: center, radii: CGSize(width: radius, height: radius), extent: portrait.extent))
        let original = try base().grid
        let defective = try DisplayScale.grid(blotchy)
        let repaired = try grid({ $0.portrait.skin.redness = -1 }, stage: SkinStage(), input: blotchy)
        let excess = DisplayScale.chromaDelta(original, defective, weight: disc).cr
        let remaining = DisplayScale.chromaDelta(original, repaired, weight: disc).cr
        XCTAssertGreaterThan(excess, 0.02, "반점이 심어졌다")
        XCTAssertGreaterThanOrEqual(1 - remaining / excess, Visibility.rednessClearRemoval, "붉은 반점을 맑게")
        let flushed = try grid({ $0.portrait.skin.redness = 1 }, stage: SkinStage())
        XCTAssertGreaterThanOrEqual(
            DisplayScale.channelDelta(original, flushed, channel: 0, weight: try skinWeight()), Visibility.rednessFlushRedLift,
            "혈색이 보인다")
    }

    func testShineFlattensASyntheticHighlight() throws {
        let frame = try XCTUnwrap(FaceFrame(face: portrait.face, extent: portrait.extent))
        let center = frame.imagePoint(u: 0, v: frame.eyeLevel + portrait.faceWidth * Visibility.highlightHeightFraction)
        let radius = portrait.faceWidth * Visibility.highlightRadiusFraction
        let shiny = try portrait.baked(
            SyntheticDefect.highlighted(
                portrait.image, center: center, radius: radius, lift: Visibility.highlightLift, extent: portrait.extent))
        let disc = try DisplayScale.grid(
            Support.hardEllipse(center: center, radii: CGSize(width: radius, height: radius), extent: portrait.extent))
        let original = DisplayScale.luma(try base().grid, weight: disc)
        let defective = DisplayScale.luma(try DisplayScale.grid(shiny), weight: disc)
        let repaired = DisplayScale.luma(try grid({ $0.portrait.skin.shine = 1 }, stage: SkinStage(), input: shiny), weight: disc)
        XCTAssertGreaterThan(defective - original, 10, "반사광이 심어졌다")
        XCTAssertGreaterThanOrEqual(
            DisplayScale.recovery(original: original, defective: defective, repaired: repaired), Visibility.shineReduction,
            "반사광을 누른다")
    }

    // MARK: 몸 피부

    func testBodySkinBrightnessToneAndSmoothingAreVisible() throws {
        try XCTSkipIf(portrait.analysis.personMask == nil, "데모 사진에서 인물 마스크를 찾지 못함")
        let before = try base().grid
        let bright = try grid { $0.bodySkin.brightness = 1 }
        XCTAssertGreaterThanOrEqual(
            DisplayScale.changedFraction(before, bright, in: nil), Visibility.bodyBrightnessChangedFraction)
        let skin = try skinWeight()
        XCTAssertLessThanOrEqual(
            DisplayScale.lumaDelta(before, bright, weight: skin).mean, Naturalness.bodyBrightnessMaximumMeanLift, "과하게 밝히지 않음")
        let warm = try grid { $0.bodySkin.tone = 1 }
        let redMinusBlue =
            DisplayScale.channelDelta(before, warm, channel: 0, weight: skin)
            - DisplayScale.channelDelta(before, warm, channel: 2, weight: skin)
        XCTAssertGreaterThanOrEqual(redMinusBlue, Visibility.bodyToneRedMinusBlue, "따뜻한 톤이 보인다")
        let smooth = try grid { $0.bodySkin.smoothing = 1 }
        XCTAssertGreaterThanOrEqual(
            DisplayScale.changedFraction(before, smooth, in: nil), Visibility.bodySmoothingChangedFraction)
    }

    // MARK: 효과

    func testGrainIsVisibleAtPhoneScale() throws {
        let before = try base().grid
        let after = try grid { $0.effects.grain = 1 }
        XCTAssertGreaterThanOrEqual(
            DisplayScale.lumaDeltaStandardDeviation(before, after, in: nil), Visibility.grainStandardDeviation)
        let cell = EffectStage.grainSize(shortSide: portrait.extent.width, tuning: portrait.tuning)
            * DisplayScale.phoneWidth / portrait.extent.width
        XCTAssertGreaterThanOrEqual(cell, Visibility.grainMinimumCell, "알갱이가 화면에서 뭉개지지 않는 크기")
    }

    func testGlowIsVisibleAtPhoneScale() throws {
        let before = try base().grid
        let after = try grid { $0.effects.glow = 1 }
        XCTAssertGreaterThanOrEqual(DisplayScale.changedFraction(before, after, in: nil), Visibility.glowChangedFraction)
    }

    // MARK: 눈·입·블러셔 (원터치가 쓰는 항목)

    func testEyeAndLipFeaturesAreVisible() throws {
        let before = try base().grid
        let eyes = try portrait.mask(FaceRegions.eyeMask(face: portrait.face, extent: portrait.extent, tuning: portrait.tuning))
        let brightened = try grid({ $0.portrait.features.eyeBrighten = 1 }, stage: FeatureStage())
        XCTAssertGreaterThanOrEqual(
            DisplayScale.lumaDelta(before, brightened, weight: eyes).meanAbsolute, Visibility.eyeMeanAbsolute)
        let lips = try portrait.mask(FaceRegions.lipMask(face: portrait.face, extent: portrait.extent, tuning: portrait.tuning))
        let vivid = try grid({ $0.portrait.features.lipVitality = 1 }, stage: FeatureStage())
        XCTAssertGreaterThanOrEqual(DisplayScale.lumaDelta(before, vivid, weight: lips).meanAbsolute, Visibility.lipMeanAbsolute)
        let teeth = try FaceRegions.teethMask(
            face: portrait.face, image: portrait.image, extent: portrait.extent, tuning: portrait.tuning)
        try XCTSkipIf(teeth == nil, "다문 입이라 치아 미백은 데모 사진에서 재지 않는다")
    }

    func testBlushIsVisible() throws {
        let catalog = try Support.sharedMakeupCatalog()
        var recipe = EditRecipe()
        recipe.makeup.blush = MakeupTint(colorID: "blush-peach", intensity: 1)
        let context = RenderContext(
            extent: portrait.extent, recipe: recipe, analysis: portrait.analysis, tuning: portrait.tuning,
            makeupCatalog: catalog)
        let output = try MakeupStage().apply(portrait.image, in: context)
        let blush = try portrait.mask(FaceRegions.blushMask(face: portrait.face, extent: portrait.extent, tuning: portrait.tuning))
        XCTAssertGreaterThanOrEqual(
            DisplayScale.lumaDelta(try base().grid, try DisplayScale.grid(output), weight: blush).meanAbsolute,
            Visibility.blushMeanAbsolute)
    }

    // MARK: 밖은 그대로

    func testFaceItemsLeaveHairAndBackgroundUntouched() throws {
        let before = try base().grid
        var recipe = EditRecipe()
        recipe.portrait.skin = SkinAdjustments(
            smoothing: 1, darkCircles: 1, nasolabial: 1, marionette: 1, glabella: 1, toneEvening: 1, redness: -1, shine: 1)
        let after = try DisplayScale.grid(portrait.render(recipe, stage: SkinStage()))
        let polygon = FaceRegions.skinPolygon(face: portrait.face, extent: portrait.extent, tuning: portrait.tuning)
        let dilation = portrait.faceWidth * 0.05
        let inside = FaceRegions.containment(polygons: [polygon], dilation: dilation)
        let scale = portrait.extent.width / DisplayScale.phoneWidth
        var outsideChanged = 0
        var outsideTotal = 0
        for y in 0..<before.height {
            for x in 0..<before.width {
                let point = CGPoint(x: x, y: y)
                guard !inside(CGPoint(x: CGFloat(x) * scale, y: CGFloat(y) * scale)) else { continue }
                outsideTotal += 1
                let a = before.rgba(point)
                let b = after.rgba(point)
                if (0..<3).contains(where: { abs(Int(a[$0]) - Int(b[$0])) >= DisplayScale.defaultMinimumDelta }) {
                    outsideChanged += 1
                }
            }
        }
        XCTAssertLessThanOrEqual(
            Double(outsideChanged) / Double(max(outsideTotal, 1)), Naturalness.outsideFaceChangedFraction, "얼굴 다각형 밖은 그대로")
    }
}
```

- [ ] **Step 3: 실행해 빨강·초록을 기록**

Run: `cd apple && swift test --filter RealPhotoAcceptanceTests 2>&1 | grep -E "passed|failed|error|XCTAssert" | head -60`

기대(지금 코드): 통과 — `testSkinSmoothingChangesTheFaceButKeepsPores`, `testToneEveningEvensSkinButKeepsPores`, `testGlowIsVisibleAtPhoneScale`, `testFaceItemsLeaveHairAndBackgroundUntouched`, `testBlushIsVisible`(미측정이라 결과를 적는다), `testEyeAndLipFeaturesAreVisible`(같음), `testBodySkinBrightnessToneAndSmoothingAreVisible`의 밝기·매끄럽게. 실패 — 주름 4종(하한·회복), `testGrainIsVisibleAtPhoneScale`, `testRednessClearsASyntheticBlotchAndFlushIsVisible`, `testShineFlattensASyntheticHighlight`, 몸 피부 톤 단언. 실제 결과가 기대와 다르면(예: 눈·입·블러셔가 미달) 그 사실을 Task 6 VALIDATION의 실측 표에 적고 Task 4에서 스펙 1.2의 조정 후보 상수를 올린다. **이 Task에서는 테스트 코드를 초록으로 만들지 않는다.** 단 컴파일 오류·측정 도우미의 버그는 고친다(예: Lanczos 결과 크기가 1170이 아니면 `cropped`를 맞춘다).

lint: `cd apple && swift format lint --strict --recursive Tests` 출력 없음.

- [ ] **Step 4: 커밋**

```bash
git add apple/Tests/MellowRenderingTests/RenderingTestSupport.swift apple/Tests/MellowRenderingTests/RealPhotoAcceptanceTests.swift
git commit -m "test(rendering): 실사진·폰 화면 배율의 보이는 강도 하한과 자연스러움 상한 수용 테스트

실제 Vision으로 분석한 데모 사진을 가로 1170px로 맞춰 바뀐 비율·가중 휘도·색차·질감 비를 잰다.
합성 그늘·반점·반사광의 회복률도 포함. 지금 코드에서 주름 4종·그레인·붉은기·번들거림·몸 피부 톤이 빨강이다(의도).

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 2: 주름 띠 — 얼굴 폭 기준 기하와 주름용 피부 비트맵

**Files:**
- Modify: `apple/Sources/MellowRendering/Domain/FaceRegions+Folds.swift`, `FaceRegions+Makeup.swift`(`softMask`의 `raster` 인자), `FaceRegions.swift`(`foldSkinRaster`), `RegionMaskCache.swift`(상한 10)
- Modify: `apple/Sources/MellowRendering/API/RenderTuning.swift`(`foldFeatureFeather`)
- Test: `apple/Tests/MellowRenderingTests/FoldRegionsTests.swift`, `RenderingTestSupport.swift`(표본 점), `RegionMaskCacheTests.swift`, `SkinStageTests.swift`(캐시 수), `BodySkinStageTests.swift`(캐시 수 단언이 있으면)

**Interfaces:**
- Consumes: `FaceFrame`, `polygonMask`, `protectedPolygons`, `skinPolygon`.
- Produces: 인터페이스 요약의 Task 2 항목.

설계 근거: 스펙 2.1. 보호 영역 넓힘 5%가 띠를 잘랐고 띠 크기가 눈 높이·짧은 선분에 매여 있었다.

- [ ] **Step 1: 테스트 갱신(실패하게)**

`RenderingTestSupport.swift`의 주름 표본 점 확장을 고친다:

```swift
/// 주름 띠 표본 점(G4). 얼굴 좌표(원점 (256, 200), 얼굴 폭 280). 계산은 G4-1 계획 Task 2 참고.
extension SyntheticFace {
    /// 다크서클 타원 안(중심 v = 눈 아래끝 286 − 280 × 0.055 = 270.6, 세로 반지름 280 × 0.045 = 12.6).
    static let underLeftEye = CGPoint(x: 200, y: 262)
    static let underRightEye = CGPoint(x: 312, y: 262)
    static let rolledUnderLeftEye = CGPoint(x: 176.5, y: 225.7)
    static let rolledUnderRightEye = CGPoint(x: 273.5, y: 281.7)
    /// 팔자 띠 중심. 코 날개 (236, 190) → 입꼬리 (208, 140)를 25% 연장한 끝 (201, 127.5)의 중점 (218.5, 158.75)을 바깥으로 12.6 민 자리.
    static let leftNasolabial = CGPoint(x: 206, y: 162)
    static let rightNasolabial = CGPoint(x: 306, y: 162)
    /// 연장된 팔자 띠 끝(약 (188, 130))에서 3 흐림 이상 떨어진 턱 쪽 피부. 팔자 띠 밖이어야 한다.
    static let belowLeftNasolabial = CGPoint(x: 186, y: 100)
    /// 마리오네트 타원 안(입꼬리에서 15° 바깥으로 19.6 내려간 중점을 바깥으로 8.4 민 자리 (194.8, 123.3)).
    static let leftMarionette = CGPoint(x: 196, y: 120)
    static let rightMarionette = CGPoint(x: 316, y: 120)
    static let glabella = CGPoint(x: 256, y: 338)
}
```

(`rolledUnderLeftEye`·`rolledUnderRightEye`는 새 중심(270.6)으로 다시 계산한다: 중심 (200, 270.6)·(312, 270.6)을 (256, 200) 둘레로 30° 돌린 점은 (146.2, 233.1)·(243.2, 289.1)이고 띠 안이면 그대로 쓴다. 격자를 찍어 값이 128을 넘는 점으로 확정한다.)

`FoldRegionsTests.testNasolabialMaskRunsFromNoseWingToMouthCornerOnBothSides`의 `outside` 배열에서 `SyntheticFace.leftMarionette`를 빼고 `SyntheticFace.belowLeftNasolabial`을 넣는다. 같은 테스트 끝에 추가:

```swift
        let corner = CGPoint(x: 204, y: 136)
        XCTAssertGreaterThan(pixels.red(corner), 64, "띠가 입꼬리 옆까지 이어진다(보호 영역 넓힘 1.2%)")
```

`testDarkCircleMaskSitsUnderBothEyesAndLeavesEyesAndCheeks` 끝에 추가:

```swift
        let lowerBand = CGPoint(x: 200, y: 280)
        XCTAssertGreaterThan(pixels.red(lowerBand), 128, "눈 아래끝(286)에서 6px 아래도 띠 안이다")
```

`RegionMaskCacheTests.testCapacityGrowsWithFaceCount`: 36 → 40, 54 → 60, 주석 "얼굴당 해상도마다 10(G4: 주름용 피부 비트맵)". `SkinStageTests.testRefinementsReuseTheSkinRasterAndAddNoCacheEntries`: 단언을 `XCTAssertEqual(analysis.regionMasks.count, 2, "피부 다각형 비트맵 하나와 주름용 비트맵 하나")`로, 이름을 `testRefinementsUseOneSkinRasterAndOneFoldRaster`로. `RegionMaskCacheTests.testThreeFacesWithFullMakeupKeepEveryMaskAcrossTwoResolutions`가 항목 수를 세면 얼굴당 +1을 반영한다.

- [ ] **Step 2: 실패 확인**

Run: `cd apple && swift test --filter "FoldRegionsTests|RegionMaskCacheTests|SkinStageTests/testRefinements"` → `belowLeftNasolabial`·`corner`·`lowerBand`·캐시 수 단언 실패.

- [ ] **Step 3: 구현**

`RenderTuning.swift`(`foldSurroundFraction` 옆):

```swift
    /// 주름용 피부 비트맵이 눈·눈썹·입술 보호 영역을 넓히는 폭. 얼굴 폭 비율. 피부 보정용(skinFeatureFeather 5%)보다 좁아
    /// 띠가 눈 아래·입꼬리 옆까지 닿고, 마스크 흐림(skinMaskFeather 1.5%)과 비슷해 눈·입 안은 0에 머문다.
    public var foldFeatureFeather: Double = 0.012
```

`FaceRegions.swift`(`skinPolygonRaster` 아래):

```swift
    /// 주름 띠용 피부 비트맵. skinPolygonRaster와 같되 보호 영역 넓힘이 foldFeatureFeather다. 캐시 항목이 따로 든다.
    static func foldSkinRaster(face: FaceGeometry, extent: CGRect, tuning: RenderTuning, cache: RegionMaskCache?)
        -> CIImage
    {
        let cutWidth = faceWidth(face, extent: extent) * CGFloat(tuning.foldFeatureFeather) * 2
        return polygonMask(
            fill: [skinPolygon(face: face, extent: extent, tuning: tuning)],
            cut: protectedPolygons(face: face, extent: extent), cutWidth: cutWidth, extent: extent, tuning: tuning,
            cache: cache)
    }
```

`FaceRegions+Makeup.swift`의 `softMask`에 `raster: CIImage? = nil` 인자를 더하고 `let skin = raster ?? skinPolygonRaster(...)`로 바꾼다. `RegionMaskCache.entriesPerFacePerResolution = 10`(주석 "G4: 주름용 피부 비트맵").

`FaceRegions+Folds.swift`의 `FoldShape`:

```swift
private enum FoldShape {
    /// 다크서클 중심을 눈 다각형 아래끝에서 내리는 양. 얼굴 폭 비율(눈 높이는 뜬 정도에 따라 달라 쓰지 않는다).
    static let darkCircleDropFraction: CGFloat = 0.055
    /// 다크서클 타원 가로 반지름(눈 폭 배수)과 세로 반지름(얼굴 폭 비율).
    static let darkCircleRadiusU: CGFloat = 0.65
    static let darkCircleRadiusVFraction: CGFloat = 0.045
    static let eyeMatchDistance: CGFloat = 1
    /// 팔자 선분을 입꼬리 너머로 연장하는 비율(입꼬리 − 코 날개 길이 기준). 주름은 입꼬리 아래까지 이어진다.
    static let nasolabialOverrun: CGFloat = 0.25
    static let nasolabialHalfLength: CGFloat = 0.55
    static let nasolabialHalfWidth: CGFloat = 0.03
    /// 팔자 띠를 선분에서 얼굴 바깥쪽으로 미는 양. 얼굴 폭 비율. 주름은 선분보다 바깥에 있다.
    static let nasolabialOutset: CGFloat = 0.045
    static let marionetteLength: CGFloat = 0.14
    static let marionetteRadiusU: CGFloat = 0.08
    static let marionetteRadiusV: CGFloat = 0.03
    static let marionetteOutset: CGFloat = 0.03
    static let marionetteTiltFromVertical: CGFloat = 0.26
    static let glabellaMargin: CGFloat = 0.01
    static let glabellaRadiusV: CGFloat = 0.07
    static let browEndTolerance: CGFloat = 0.01
}
```

`darkCircleMask`: 타원을 다음으로.

```swift
            let width = frame.faceWidth
            let oval = Oval(
                center: frame.imagePoint(u: center.x, v: bottom - width * FoldShape.darkCircleDropFraction),
                radii: CGSize(
                    width: eye.width * FoldShape.darkCircleRadiusU, height: width * FoldShape.darkCircleRadiusVFraction))
```

`nasolabialMask`: `corner`를 구한 뒤 연장 끝을 쓴다.

```swift
            let end = CGPoint(
                x: corner.x + (corner.x - wing.x) * FoldShape.nasolabialOverrun,
                y: corner.y + (corner.y - wing.y) * FoldShape.nasolabialOverrun)
            let dx = end.x - wing.x
            let dy = end.y - wing.y
            let length = hypot(dx, dy)
            guard length > 0 else { continue }
            let direction = CGPoint(x: dx / length, y: dy / length)
            let middle = CGPoint(x: (wing.x + end.x) / 2, y: (wing.y + end.y) / 2)
            ovals.append(
                bandOval(
                    frame: frame, center: middle, direction: direction, side: side, outset: FoldShape.nasolabialOutset,
                    radii: CGSize(
                        width: length * FoldShape.nasolabialHalfLength, height: width * FoldShape.nasolabialHalfWidth)))
```

`marionetteMask`: `bandOval(..., outset: FoldShape.marionetteOutset, ...)`. `bandOval`에 `outset: CGFloat` 인자를 더하고 `frame.faceWidth * outset`으로 민다. 네 마스크 모두 `softMask(..., raster: foldSkinRaster(face: face, extent: extent, tuning: tuning, cache: cache))`를 넘긴다.

- [ ] **Step 4: 통과 확인**

Run: `cd apple && swift test --filter "FoldRegionsTests|RegionMaskCacheTests|SkinStageTests|MakeupStageTests|BodySkinStageTests"` → 모두 통과(표본 점이 어긋나면 격자를 ±20px 찍어 타원 안의 점으로 옮기고 문턱은 낮추지 않는다). `swift test --filter RealPhotoAcceptanceTests` → 주름 자연 하한은 아직 실패해도 된다(기준이 Task 3). lint 출력 없음. `./scripts/verify-modules.sh` 통과.

- [ ] **Step 5: 커밋**

```bash
git add apple/Sources/MellowRendering/Domain/FaceRegions+Folds.swift apple/Sources/MellowRendering/Domain/FaceRegions+Makeup.swift apple/Sources/MellowRendering/Domain/FaceRegions.swift apple/Sources/MellowRendering/Domain/RegionMaskCache.swift apple/Sources/MellowRendering/API/RenderTuning.swift apple/Tests/MellowRenderingTests/FoldRegionsTests.swift apple/Tests/MellowRenderingTests/RenderingTestSupport.swift apple/Tests/MellowRenderingTests/RegionMaskCacheTests.swift apple/Tests/MellowRenderingTests/SkinStageTests.swift
git commit -m "fix(rendering): 주름 띠를 얼굴 폭 기준으로 다시 놓고 주름용 피부 비트맵의 보호 영역 넓힘을 1.2%로

눈·입 보호 영역 넓힘 5%가 다크서클·팔자 띠를 조각만 남겼다. 팔자는 입꼬리 너머 25% 연장, 바깥 밀기 4.5%.
캐시 항목 얼굴당 해상도마다 9 → 10.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 3: 밝히기 기준 — 피부 마스크 × (1 − 띠) 가중 넓은 평균

**Files:**
- Modify: `apple/Sources/MellowRendering/Domain/SkinKernels.swift`, `SkinRefinement.swift`, `SkinStage.swift`
- Modify: `apple/Sources/MellowRendering/API/RenderTuning.swift`(`foldSurroundFraction` 0.18)
- Test: `apple/Tests/MellowRenderingTests/SkinStageTests.swift`

**Interfaces:**
- Consumes: `FrequencySeparation.maskedMean`, `FaceRegions.skinMask`.
- Produces: `SkinKernels.foldLift(image:low:wideNumerator:wideDenominator:amount:maxGain:lumaFloor:extent:)`, `SkinRefinement.liftFold(_:region:skinMask:faceWidth:amount:tuning:extent:)`.

설계 근거: 스펙 2.2. 측정된 gap(0.025 · 0.002 · −0.058)은 가중치 없는 흐림에 눈·눈썹·입술이 섞인 값이다.

- [ ] **Step 1: 실패하는 테스트 작성**

`SkinStageTests.swift` 끝에 추가:

```swift
    /// 띠 둘레에 피부가 전혀 없으면(피부 마스크 0) 기준이 없어 배율 1이어야 한다. 폭주·검정 번짐 없음.
    func testFoldLiftWithEmptySurroundLeavesTheBandUnchanged() throws {
        let synthetic = SyntheticFace.make()
        let region = try XCTUnwrap(
            FaceRegions.darkCircleMask(face: synthetic.face, extent: synthetic.image.extent, tuning: RenderTuning()))
        let black = CIImage(color: .black).cropped(to: synthetic.image.extent)
        let output = try SkinRefinement.liftFold(
            synthetic.image, region: region, skinMask: black, faceWidth: 280, amount: 1, tuning: RenderTuning(),
            extent: synthetic.image.extent)
        XCTAssertEqual(try Support.bytes(output), try Support.bytes(synthetic.image), "피부 기준이 없으면 바꾸지 않는다")
    }

    /// 둘레에 어두운 눈·눈썹이 있어도 기준은 피부만 본다: 눈 아래 그늘을 심으면 밝아져야 한다(실사진 실패의 재현).
    func testFoldLiftIgnoresDarkFeaturesInTheSurround() throws {
        let synthetic = SyntheticFace.make()
        let center = SyntheticFace.underLeftEye
        let shadowed = darkened(synthetic.image, at: center, radii: CGSize(width: 40, height: 14), factor: Self.shadowFactor)
        let before = try Support.grid(shadowed)
        let after = try Support.grid(
            render(SyntheticFace(image: shadowed, face: synthetic.face), skin: SkinAdjustments(darkCircles: 1)))
        XCTAssertGreaterThanOrEqual(
            Int(after.red(center)), Int(before.red(center)) + Self.liftMinimum, "눈 옆 그늘도 피부 기준으로 밝힌다")
        XCTAssertEqual(after.rgba(SyntheticFace.leftEye), before.rgba(SyntheticFace.leftEye), "눈 안은 그대로")
    }
```

- [ ] **Step 2: 실패 확인**

Run: `cd apple && swift test --filter SkinStageTests` → 컴파일 실패(`skinMask:` 인자 없음).

- [ ] **Step 3: 구현**

`SkinKernels.swift`의 `fold` 커널:

```swift
        // 휘도 계수는 BT.601이다. 주변은 피부 마스크 가중 평균(분자 ÷ 분모)이라 눈·눈썹·입술·머리카락이 섞이지 않는다.
        // 분모 하한 0.001은 둘레가 전부 보호 영역일 때 0으로 나누지 않게 하고, 그때 주변 휘도가 0이라 gap이 0이 된다.
        // 세 채널에 같은 배율을 곱해 그늘의 색조·채도를 지킨다.
        fold = CIColorKernel(
            source: """
                kernel vec4 foldLift(__sample image, __sample low, __sample wideNumerator, __sample wideDenominator,
                                     float amount, float maxGain, float lumaFloor) {
                    vec3 luma = vec3(0.299, 0.587, 0.114);
                    float lowLuma = dot(low.rgb, luma);
                    float coverage = max(wideDenominator.r, 0.001);
                    float surroundLuma = dot(wideNumerator.rgb / coverage, luma) * step(0.02, wideDenominator.r);
                    float gap = max(surroundLuma - lowLuma, 0.0);
                    float gain = min(1.0 + amount * gap / max(lowLuma, lumaFloor), maxGain);
                    return vec4(image.rgb * gain, image.a);
                }
                """)
```

(`step(0.02, den)`: 피부 가중치 합이 2% 미만이면 주변 휘도를 0으로 두어 밝히지 않는다. 상수 0.02는 `SkinKernels.foldMinimumCoverage`로 두고 커널 인자로 넘긴다 — 매직 넘버 금지. 인자 목록에 `float minimumCoverage`를 더한다.)

`foldLift` 메서드 시그니처: `foldLift(image:low:wideNumerator:wideDenominator:amount:maxGain:lumaFloor:extent:)`, 인자 배열에 `Self.foldMinimumCoverage`를 더한다.

`SkinRefinement.liftFold`:

```swift
    /// 어두운 주름 띠를 둘레 "피부" 밝기 쪽으로 올린다. 기준은 skinMask × (1 − 띠)로 가중한 넓은 평균이라
    /// 눈·눈썹·입술·머리카락과 띠 자신이 섞이지 않는다. region.bounds 안에서만 계산하고 마스크 밖은 입력 바이트 그대로다.
    static func liftFold(
        _ image: CIImage, region: FaceRegions.RegionMask, skinMask: CIImage, faceWidth: CGFloat, amount: Double,
        tuning: RenderTuning, extent: CGRect
    ) throws -> CIImage {
        guard amount > 0 else { return image }
        let lowRadius = max(tuning.skinBlurMinimumRadius, Double(faceWidth) * tuning.foldLowBandFraction)
        let surroundRadius = max(tuning.skinBlurMinimumRadius, Double(faceWidth) * tuning.foldSurroundFraction)
        let black = CIImage(color: .black).cropped(to: extent)
        let outsideBand = region.image.composited(over: black).applyingFilter("CIColorInvert").cropped(to: extent)
        let weight = skinMask.composited(over: black)
            .applyingFilter("CIMultiplyCompositing", parameters: [kCIInputBackgroundImageKey: outsideBand])
            .cropped(to: extent)
        let wide = FrequencySeparation.maskedMean(image, mask: weight, radius: surroundRadius)
        let lifted = try SkinKernels.shared.foldLift(
            image: image, low: FrequencySeparation.blurred(image, radius: lowRadius), wideNumerator: wide.numerator,
            wideDenominator: wide.denominator, amount: amount * tuning.foldLiftMax, maxGain: tuning.foldLiftMaxGain,
            lumaFloor: tuning.foldLumaFloor, extent: region.bounds)
        return MaskBuilder.blend(lifted, over: image, mask: region.image).cropped(to: extent)
    }
```

`SkinStage.refine`: `unitMask`를 `for fold in ...` 앞으로 올리고(`bandMix || redness` guard보다 먼저 만들되, 주름·대역·붉은기 모두 0이면 이미 호출되지 않는다) 주름 호출에 `skinMask: unitMask`를 넘긴다. `unitMask`는 `result`(주름 전 이미지)에서 한 번 만든다. `RenderTuning.foldSurroundFraction = 0.18`(주석 갱신: "피부 가중 평균이라 넓혀도 눈·입이 섞이지 않고 띠 자신의 비중이 준다").

- [ ] **Step 4: 통과 확인**

Run: `cd apple && swift test --filter "SkinStageTests|RealPhotoAcceptanceTests"` → SkinStageTests 전부 통과(기존 주름 테스트 포함, Rendering 명목 277 중 이 두 파일). `RealPhotoAcceptanceTests`의 주름 4종 네 테스트가 통과해야 한다. 미달이면 `foldLiftMax`(0.9 → 최대 1.0)·`foldSurroundFraction`(0.18 → 0.22)·`FoldShape` 크기 순으로 올리고, 상한(평균 ΔY ≤ 20/255, 색차 ≤ 0.01, 질감 ≥ 0.85)이 깨지면 되돌린다. 조정한 값을 Task 6에 적는다. lint 출력 없음.

- [ ] **Step 5: 커밋**

```bash
git add apple/Sources/MellowRendering/Domain/SkinKernels.swift apple/Sources/MellowRendering/Domain/SkinRefinement.swift apple/Sources/MellowRendering/Domain/SkinStage.swift apple/Sources/MellowRendering/API/RenderTuning.swift apple/Tests/MellowRenderingTests/SkinStageTests.swift
git commit -m "fix(rendering): 주름 밝히기 기준을 피부 마스크 × (1 − 띠) 가중 넓은 평균으로

가중치 없는 흐림은 눈·눈썹·입술을 섞어 주변이 그늘보다 어둡게 나왔다(실사진 측정 gap ≈ 0). 반지름 0.12 → 0.18.
피부 가중치 합이 2% 미만이면 밝히지 않는다.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 4: 상수 재조정, 몸 피부 대체 영역, 피부톤 상태 줄

**Files:**
- Modify: `apple/Sources/MellowRendering/API/RenderTuning.swift`, `apple/Sources/MellowRendering/Domain/SkinKernels.swift`(붉은기 기준 여유), `SkinRefinement.swift`, `BodySkinStage.swift`
- Modify: `apple/MellowPhoto/Application/AppModel.swift`, `UserMessage.swift`, `apple/MellowPhoto/Features/Editor/BeautyPanel.swift`
- Test: `apple/Tests/MellowRenderingTests/EffectStageTests.swift`, `BodySkinStageTests.swift`, `SkinStageTests.swift`, `apple/MellowPhotoTests/AppModelTests.swift`

**Interfaces:**
- Consumes: `BackgroundStage.personMask`, `FaceRegions.widestFace`, `AppModel.faceAvailability`·`backgroundAvailability`.
- Produces: 인터페이스 요약의 Task 4 항목.

설계 근거: 스펙 1.3·2.3·2.4.

- [ ] **Step 1: 실패하는 테스트 작성**

`EffectStageTests.swift` 48행 `grainSize(shortSide: 1200)` 기대값을 `3.0`으로. `BodySkinStageTests.testZeroValuesNoPersonOrNoFaceReturnInputBytes`의 "인물 마스크 없음" 단언을 지우고(이제 얼굴이 있으면 동작) 끝에 추가:

```swift
    /// 인물 마스크가 없어도 얼굴이 있으면 얼굴 상자를 가로 3배·아래로 4배 늘린 영역을 사람 대신 쓴다(스펙 G4 2.4).
    func testBodySkinFallsBackToTheFaceNeighbourhoodWithoutAPersonMask() throws {
        let synthetic = try SyntheticFace.makeWithBody()
        let before = try Support.grid(synthetic.image)
        let after = try Support.grid(output(synthetic, BodySkinAdjustments(brightness: 1), personMask: nil))
        for point in [SyntheticFace.bodySkinPoint, SyntheticFace.cheek] {
            XCTAssertGreaterThanOrEqual(Int(after.red(point)), Int(before.red(point)) + Self.liftMinimum, "대체 영역 안 피부 \(point)")
        }
        for point in [
            SyntheticFace.shirtPoint, SyntheticFace.backgroundBesideBody, SyntheticFace.backgroundAboveHead,
            SyntheticFace.leftEye, SyntheticFace.outside,
        ] {
            XCTAssertEqual(after.rgba(point), before.rgba(point), "피부색이 아니거나 영역 밖 \(point)")
        }
        let region = BodySkinStage.fallbackPersonRegion(face: synthetic.face, extent: extent, tuning: RenderTuning())
        let grid = try Support.grid(region)
        XCTAssertGreaterThan(grid.red(SyntheticFace.bodySkinPoint), 200, "얼굴 아래는 영역 안")
        XCTAssertEqual(grid.red(SyntheticFace.backgroundAboveHead), 0, "얼굴 위는 영역 밖")
    }
```

`BodySkinStageTests.testToneWarmsOrCoolsSkinOnly`의 `toneMinimum`이 새 상수(0.05)에서도 뜻이 맞는지 확인하고 그대로 둔다(10바이트 이상이면 통과). `SkinStageTests.testRednessClearsOnlyRedderThanCheeksAndFlushAddsEvenly`는 상수가 커져도 방향 단언이라 그대로 통과해야 한다(실패하면 기대값의 부호·여유만 확인).

`AppModelTests.testSkinToneSlidersFollowPersonAvailabilityAndPresetValues`를 다음으로 바꾼다:

```swift
    func testSkinToneStatusLineReflectsPersonAndFaceConditions() async throws {
        let staged = try TestSupport.solidPNG(in: root)
        let face = FaceGeometry(boundingBox: NormalizedRect(x: 0.2, y: 0.2, width: 0.6, height: 0.6))
        let model = TestSupport.makeModel(
            root: root, analyzer: StubFaceAnalyzer(result: .success([face])),
            importer: FakeImporter(staged: [.success(StagedPhoto(url: staged, displayName: nil))]))
        try await importOne(model, staged)
        XCTAssertEqual(model.backgroundAvailability, .noPerson)
        XCTAssertEqual(model.bodySkinStatus, .fallback, "사람 영역이 없어도 얼굴이 있으면 대체 영역")
        XCTAssertTrue(model.canAdjustBodySkin(.brightness), "대체 영역에서도 켠다")
        XCTAssertEqual(UserMessage.bodySkinStatus(.fallback), "사람 영역 없음 → 얼굴 둘레로 대신 적용해요")
        XCTAssertEqual(UserMessage.bodySkinStatus(.ready), "사람 영역 ✓ · 기준 얼굴 ✓")
        XCTAssertEqual(UserMessage.bodySkinStatus(.noFace), "기준 얼굴이 없어 피부 밝기·톤·매끄럽게가 적용되지 않아요")
        model.beginSliderEdit()
        model.edit(.bodySkin(.brightness, 0.4))
        model.endSliderEdit()
        try await waitUntil { !model.isRendering }
        XCTAssertNil(model.presentedError)
        let faceless = TestSupport.makeModel(
            root: root, importer: FakeImporter(staged: [.success(StagedPhoto(url: try TestSupport.solidPNG(in: root, name: "b"), displayName: nil))]))
        await faceless.importFromFiles([try TestSupport.solidPNG(in: root, name: "c")])
        try await waitUntil { faceless.isReady && faceless.preview != nil }
        XCTAssertEqual(faceless.bodySkinStatus, .noFace)
        XCTAssertFalse(faceless.canAdjustBodySkin(.brightness), "얼굴이 없으면 끈다")
        faceless.applyPreset(PresetValues(bodySkin: BodySkinAdjustments(brightness: 0.4)))
        XCTAssertTrue(faceless.canAdjustBodySkin(.brightness), "프리셋으로 들어온 값은 0으로 되돌릴 수 있다")
        XCTAssertFalse(faceless.canAdjustBodySkin(.tone), "0인 항목은 계속 끈다")
    }
```

(`FakeImporter`가 스테이징 목록으로 동작하면 두 번째 모델의 가져오기 호출 형태를 기존 테스트와 같게 맞춘다 — `importOne(faceless, staged2)`.)

- [ ] **Step 2: 실패 확인**

Run: `cd apple && swift test --filter "EffectStageTests|BodySkinStageTests"` → `grainSize`·대체 영역 실패. Mac 앱 테스트 → 컴파일 실패(`bodySkinStatus` 없음).

- [ ] **Step 3: 구현**

`RenderTuning.swift`: Global Constraints의 값으로 바꾸고 주석을 갱신한다(그레인: "폰 화면에서 보이는 크기·진폭. 1.3.0의 0.12·0.0012는 축소에 평균돼 보이지 않았다"). 새 상수:

```swift
    /// 붉은기 −의 기준을 볼 평균 Cr보다 이만큼 낮게 잡는다(감마 Cr). 고르게 붉은 피부도 −1에서 맑아진다.
    public var rednessReferenceOffset: Double = 0.01
    /// 인물 마스크가 없을 때 몸 피부가 쓰는 대체 영역: 가장 큰 얼굴 상자의 가로 배수와 상자 위끝에서 아래로의 높이 배수.
    public var bodySkinFallbackWidthScale: Double = 3
    public var bodySkinFallbackHeightScale: Double = 4
    /// 대체 영역 가장자리 흐림. 짧은 변 비율.
    public var bodySkinFallbackFeather: Double = 0.05
```

`SkinKernels.redness(encoded:reference:clear:flush:referenceOffset:extent:)`: 커널 `skinRedness`에 `float referenceOffset`을 더해 `float excess = max(cr - (dot(reference.rgb, crv) - referenceOffset), 0.0)`. `SkinRefinement.adjustRedness`가 `tuning.rednessReferenceOffset`을 넘긴다.

`BodySkinStage`:

```swift
    func apply(_ image: CIImage, in context: RenderContext) throws -> CIImage {
        let values = Self.clamped(context.recipe.bodySkin)
        guard values.hasEffect, let reference = Self.referenceFace(context.faces) else { return image }
        let extent = context.extent
        let tuning = context.tuning
        let encoded = image.applyingFilter("CILinearToSRGBToneCurve")
        guard let cheeks = FaceRegions.cheekAverages(of: encoded, face: reference, extent: extent) else { return image }
        let area: CIImage
        if let person = context.personMask, !person.extent.isEmpty, !person.extent.isInfinite {
            let feather = max(
                CGFloat(tuning.skinBlurMinimumRadius), context.shortSide * CGFloat(tuning.bodySkinMaskFeather))
            area = BackgroundStage.personMask(person, extent: extent, feather: feather)
        } else {
            area = Self.fallbackPersonRegion(face: reference, extent: extent, tuning: tuning)
        }
        …(이하 기존과 같음, `area` 사용)
    }

    /// 인물 마스크가 없을 때의 사람 영역. 얼굴 상자를 가로 bodySkinFallbackWidthScale배, 상자 위끝에서 아래로
    /// 높이 × bodySkinFallbackHeightScale만큼 늘린 직사각형을 흐린 부드러운 사각형이다. 옷·배경은 피부색 가중치가 뺀다.
    static func fallbackPersonRegion(face: FaceGeometry, extent: CGRect, tuning: RenderTuning) -> CIImage {
        let box = FaceRegions.pixelRect(face.boundingBox, in: extent)
        let width = box.width * CGFloat(tuning.bodySkinFallbackWidthScale)
        let height = box.height * CGFloat(tuning.bodySkinFallbackHeightScale)
        let region = CGRect(x: box.midX - width / 2, y: box.maxY - height, width: width, height: height)
            .intersection(extent)
        let feather = max(CGFloat(tuning.skinBlurMinimumRadius), min(extent.width, extent.height) * CGFloat(tuning.bodySkinFallbackFeather))
        let black = CIImage(color: .black).cropped(to: extent)
        return CIImage(color: .white).cropped(to: region).composited(over: black).clampedToExtent()
            .applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: feather]).cropped(to: extent)
    }
```

(파일 머리 주석 "인물 마스크나 얼굴이 없으면 입력 그대로"를 "얼굴이 없으면 입력 그대로, 인물 마스크가 없으면 얼굴 둘레 대체 영역"으로 고친다.)

앱 `AppModel.swift`:

```swift
    /// 피부톤 탭이 보여줄 몸 피부 조건. 얼굴 분석 실패 → 인물 분석 실패 → 얼굴 없음 → 대체 → 준비 순서로 판정한다.
    enum BodySkinStatus: Equatable {
        case ready
        /// 사람 영역이 없어 얼굴 둘레 대체 영역을 쓴다.
        case fallback
        case noFace
        case faceAnalysisUnavailable(MellowError)
        case personAnalysisUnavailable(MellowError)
    }

    var bodySkinStatus: BodySkinStatus {
        if let failure = selectedInfo?.faceAnalysisFailure {
            return .faceAnalysisUnavailable(failure)
        }
        guard !faces.isEmpty else { return .noFace }
        if let failure = selectedInfo?.personAnalysisFailure {
            return .personAnalysisUnavailable(failure)
        }
        return selectedInfo?.hasPerson == true ? .ready : .fallback
    }

    func canAdjustBodySkin(_ key: BodySkinKey) -> Bool {
        let active = bodySkinStatus == .ready || bodySkinStatus == .fallback
        return isSliderEditActive || active || currentRecipe.bodySkin[key] != 0
    }
```

`UserMessage.bodySkinStatus(_:)`: `.ready` "사람 영역 ✓ · 기준 얼굴 ✓", `.fallback` "사람 영역 없음 → 얼굴 둘레로 대신 적용해요", `.noFace` "기준 얼굴이 없어 피부 밝기·톤·매끄럽게가 적용되지 않아요", `.faceAnalysisUnavailable` `faceAnalysisUnavailableTitle`, `.personAnalysisUnavailable` "인물 영역 분석 실패 → 얼굴 둘레로 대신 적용해요". `BeautyPanel.skinToneControls`: 기존 `backgroundAvailability` 분기를 `Text(UserMessage.bodySkinStatus(model.bodySkinStatus)).font(.caption).foregroundStyle(.secondary)` 한 줄로 바꾼다(`bodySkinNoPersonHint`·`noPersonDetected` 라벨은 피부톤 탭에서 더 쓰지 않으면 지운다 — 배경 패널이 쓰면 남긴다).

- [ ] **Step 4: 통과 확인**

Run: `cd apple && swift test` → Rendering 명목 277(+1), 나머지 불변, `RealPhotoAcceptanceTests` 전부 통과(그레인·붉은기·번들거림·몸 피부 톤 포함). 미달 항목은 스펙 1.2의 조정 후보를 올리되 1.4 상한을 함께 확인한다. Mac 앱 테스트 → `Executed 80 tests`(기존 1개 교체 + 0, 이름만 바뀜 → 79; 아래 Task 5에서 +1) — 실측값으로 적는다. lint 출력 없음.

- [ ] **Step 5: 커밋**

```bash
git add apple/Sources/MellowRendering/API/RenderTuning.swift apple/Sources/MellowRendering/Domain/SkinKernels.swift apple/Sources/MellowRendering/Domain/SkinRefinement.swift apple/Sources/MellowRendering/Domain/BodySkinStage.swift apple/MellowPhoto/Application/AppModel.swift apple/MellowPhoto/Application/UserMessage.swift apple/MellowPhoto/Features/Editor/BeautyPanel.swift apple/Tests/MellowRenderingTests/EffectStageTests.swift apple/Tests/MellowRenderingTests/BodySkinStageTests.swift apple/Tests/MellowRenderingTests/SkinStageTests.swift apple/MellowPhotoTests/AppModelTests.swift
git commit -m "fix(rendering): 폰 화면에서 보이도록 그레인·붉은기·번들거림·몸 피부 톤 상수를 올리고 몸 피부 대체 영역 추가

그레인 알갱이 0.0025·진폭 0.30, 붉은기 + 0.06·− 1.0(기준 여유 0.01), 번들거림 시작 0.08, 몸 톤 0.05.
인물 마스크가 없어도 얼굴이 있으면 얼굴 둘레 영역에 몸 피부를 건다. 피부톤 탭에 조건 상태 줄.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 5: 진단 절 (앱 정보 시트)

**Files:**
- Create: `apple/MellowPhoto/Application/AppModel+Diagnostics.swift`
- Modify: `apple/MellowPhoto/Application/AppModel.swift`(`lastRenderFailure` 기록), `UserMessage.swift`, `apple/MellowPhoto/Features/Info/InfoSheet.swift`, `apple/MellowPhoto.xcodeproj`
- Test: `apple/MellowPhotoTests/AppModelTests.swift`

설계 근거: 스펙 6절. 파이프라인은 바꾸지 않는다.

- [ ] **Step 1: 실패하는 테스트 작성**

`AppModelTests.swift` 끝에 추가:

```swift
    func testDiagnosticLinesListBuildPhotoAnalysisAndNonDefaultRecipeKeys() async throws {
        let staged = try TestSupport.solidPNG(in: root)
        let face = TestSupport.landmarkedFace(in: NormalizedRect(x: 0.2, y: 0.2, width: 0.6, height: 0.6))
        let model = TestSupport.makeModel(
            root: root, analyzer: StubFaceAnalyzer(result: .success([face])),
            importer: FakeImporter(staged: [.success(StagedPhoto(url: staged, displayName: nil))]))
        try await importOne(model, staged)
        model.edit(.effect(.grain, 1))
        model.edit(.skinRefinement(.darkCircles, 0.5))
        try await waitUntil { !model.isRendering }
        let lines = model.diagnosticLines
        XCTAssertTrue(lines.contains { $0.hasPrefix(UserMessage.diagnosticLabel(.build)) })
        XCTAssertTrue(lines.contains { $0.contains("faces=1") })
        XCTAssertTrue(lines.contains { $0.contains("preview=") })
        XCTAssertTrue(lines.contains("effects.grain=1.00"))
        XCTAssertTrue(lines.contains("portrait.skin.darkCircles=0.50"))
        XCTAssertFalse(lines.contains { $0.hasPrefix("color.") }, "기본값인 키는 없다")
        XCTAssertEqual(RecipeSummary.nonDefaultLines(EditRecipe()), [])
        var recipe = EditRecipe()
        recipe.portrait.skin.autoBlemish = true
        recipe.makeup.lip = MakeupTint(colorID: "lip-rose", intensity: 0.4)
        XCTAssertEqual(
            Set(RecipeSummary.nonDefaultLines(recipe)),
            ["portrait.skin.autoBlemish=true", "makeup.lip.colorID=lip-rose", "makeup.lip.intensity=0.40"])
    }
```

- [ ] **Step 2: 실패 확인**

Run: Mac 앱 테스트 → 컴파일 실패(`diagnosticLines` 없음).

- [ ] **Step 3: 구현**

`AppModel+Diagnostics.swift`:

```swift
import Foundation
import MellowShared

/// 레시피를 JSON으로 펼쳐 기본 레시피와 다른 잎만 "경로=값"으로 적는다. 키 경로는 영어 식별자(모듈 값 이름 그대로).
enum RecipeSummary {
    static func nonDefaultLines(_ recipe: EditRecipe) -> [String] {
        let current = leaves(of: recipe)
        let defaults = leaves(of: EditRecipe())
        return current.filter { defaults[$0.key] != $0.value }.map { "\($0.key)=\($0.value)" }.sorted()
    }

    private static func leaves(of recipe: EditRecipe) -> [String: String] {
        guard let data = try? JSONEncoder().encode(recipe),
            let object = try? JSONSerialization.jsonObject(with: data)
        else { return [:] }
        var result: [String: String] = [:]
        flatten(object, path: "", into: &result)
        result["schemaVersion"] = nil
        return result
    }

    private static func flatten(_ value: Any, path: String, into result: inout [String: String]) {
        switch value {
        case let dictionary as [String: Any]:
            for (key, child) in dictionary {
                flatten(child, path: path.isEmpty ? key : "\(path).\(key)", into: &result)
            }
        case let array as [Any]:
            for (index, child) in array.enumerated() {
                flatten(child, path: "\(path)[\(index)]", into: &result)
            }
        case let number as NSNumber:
            result[path] = CFGetTypeID(number) == CFBooleanGetTypeID() ? (number.boolValue ? "true" : "false")
                : String(format: "%.2f", number.doubleValue)
        case let string as String:
            result[path] = string
        default:
            result[path] = "null"
        }
    }
}

extension AppModel {
    enum DiagnosticItem {
        case build, device, photo, preview, analysis, failure
    }

    /// 정보 시트 "진단". 스크린샷 한 장으로 전제 조건(얼굴·사람·관절)과 적용 중인 값을 볼 수 있다.
    var diagnosticLines: [String] {
        let bundle = Bundle.main
        let version = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        let build = bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
        var lines = [
            "\(UserMessage.diagnosticLabel(.build)) \(version) (\(build))",
            "\(UserMessage.diagnosticLabel(.device)) \(ProcessInfo.processInfo.operatingSystemVersionString)",
        ]
        if let info = selectedInfo {
            lines.append("\(UserMessage.diagnosticLabel(.photo)) \(Int(info.pixelSize.width))×\(Int(info.pixelSize.height))")
            lines.append(
                "\(UserMessage.diagnosticLabel(.analysis)) faces=\(info.faces.count) person=\(info.hasPerson) body=\(info.hasBody)")
        }
        if let preview {
            lines.append("\(UserMessage.diagnosticLabel(.preview)) preview=\(preview.width)×\(preview.height)")
        }
        lines += RecipeSummary.nonDefaultLines(currentRecipe)
        if let lastRenderFailure {
            lines.append("\(UserMessage.diagnosticLabel(.failure)) \(lastRenderFailure)")
        }
        return lines
    }
}
```

`AppModel.swift`: `var lastRenderFailure: String?`를 두고 `scheduleRender` 완료의 `.failure(let error)`에서 `lastRenderFailure = UserMessage.text(for: error)`, `.success`에서 nil. `UserMessage`: `diagnosticsTitle` "진단", `copyDiagnostics` "복사", `diagnosticLabel(_:)`(`.build` "앱", `.device` "기기", `.photo` "사진", `.preview` "미리보기", `.analysis` "분석", `.failure` "마지막 오류"). `InfoSheet`: `@Environment(AppModel.self)`를 받아 `Section(UserMessage.diagnosticsTitle)`에 줄마다 `Text(line).font(.caption.monospaced())`와 `Button(UserMessage.copyDiagnostics)`(`#if os(macOS)` `NSPasteboard.general.clearContents(); NSPasteboard.general.setString(text, forType: .string)` / `#else` `UIPasteboard.general.string = text`). `cd apple && xcodegen generate --quiet`.

- [ ] **Step 4: 통과 확인**

Run: Mac 앱 테스트 → `Executed 80 tests, with 0 failures`(실측 기준 +1). `cd apple && swift test` 불변. lint 출력 없음. `cd apple && xcodegen generate --quiet && git diff --exit-code --stat MellowPhoto.xcodeproj` → 출력 없음(생성 결과를 커밋에 포함).

- [ ] **Step 5: 커밋**

```bash
git add apple/MellowPhoto/Application/AppModel+Diagnostics.swift apple/MellowPhoto/Application/AppModel.swift apple/MellowPhoto/Application/UserMessage.swift apple/MellowPhoto/Features/Info/InfoSheet.swift apple/MellowPhoto.xcodeproj apple/MellowPhotoTests/AppModelTests.swift
git commit -m "feat(app): 정보 시트에 진단 절(앱·기기·사진·분석·기본값 아닌 레시피 키·마지막 오류)

기기 확인 때 스크린샷 한 장으로 전제 조건과 적용 값을 본다. 렌더 경로는 바꾸지 않는다.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 6: 문서·VALIDATION·전체 검증

**Files:**
- Modify: `docs/architecture/modules.md`, `docs/superpowers/specs/2026-10-21-beauty-g4-one-touch-design.md`, `docs/superpowers/specs/2026-10-20-beauty-g-evoto-design.md`, `VALIDATION.md`

- [ ] **Step 1: 전체 검증**

Run: `export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer && ./scripts/test-apple.sh` → 종료 코드 0(로컬은 iOS 시뮬레이터를 건너뛴다. `MELLOW_IOS_TESTS`를 켜지 않는다). 모듈 검사, lint, xcodegen 차이 없음, 패키지, Mac 앱 테스트.

실측값 수집: `cd apple && swift test --filter RealPhotoAcceptanceTests 2>&1 | tee /tmp/g4-1-acceptance.log`. 각 테스트에 `print("acceptance <항목> <지표>=<값>")` 줄을 더해 두었다면 그 값을, 아니면 단언 메시지의 값을 VALIDATION 표에 옮긴다(측정 출력 줄을 더하는 것은 허용 — 커밋 전 lint 통과).

- [ ] **Step 2: 문서**

- `docs/architecture/modules.md` MellowRendering 규칙: 주름 밝히기 설명을 "피부 마스크 × (1 − 띠) 가중 넓은 평균 기준, 주름용 피부 비트맵(보호 영역 넓힘 1.2%)은 캐시 항목 따로(얼굴당 해상도마다 10)", 몸 피부에 "인물 마스크가 없으면 얼굴 둘레 대체 영역", 그레인 상수 변경, 테스트 목록에 "실사진 수용(폰 화면 배율 하한·자연스러움 상한, 합성 결함 회복)" 추가. 앱 타깃 표에 `AppModel.BodySkinStatus`·진단 절.
- G4 스펙: 구현 중 상수를 바꿨으면 결정 표에 "(G4-1 구현 중 변경)" 행을 더하고 1.3절 표를 고친다. 바꾼 것이 없으면 그대로.
- G 스펙: 1.5 표(주름 띠)와 1.6 상수 표에 "G4-1에서 변경, 새 값은 G4 스펙 2.1·1.3" 한 줄.

- [ ] **Step 3: VALIDATION**

`VALIDATION.md` 끝에 `## 인물 보정 G4-1 주름 재설계·보이는 강도 (2026-10-XX)`:
- 날짜·커밋·환경. "iOS 시뮬레이터·실기기 검증은 하지 않았다(CI 요금 한도, 사용자 조치)".
- 자동 검증: 명령·종료 코드·테스트 수(모듈별).
- **실측 표**: 스펙 1.2·1.4의 모든 행에 대해 문턱과 측정값. 문턱을 못 넘어 상수를 바꾼 항목은 이전 값 → 새 값.
- 자동 테스트가 확인하는 것(테스트 이름).
- 스펙과 다르게 한 것(없으면 "없음").
- 미검증: 실기기 화면에서 그레인·주름·몸 피부, 저장본 그레인, 커플·단체 사진(H3 Task 1 뒤 2차 측정), CI iOS 테스트, 피부톤 상태 줄·진단 절의 iPhone 폭.
- "배포(릴리스 노트·태그·TestFlight)는 하지 않았다."

- [ ] **Step 4: 커밋**

```bash
git add docs/architecture/modules.md docs/superpowers/specs/2026-10-21-beauty-g4-one-touch-design.md docs/superpowers/specs/2026-10-20-beauty-g-evoto-design.md VALIDATION.md
git commit -m "docs: G4-1 모듈 지도·스펙 반영·실사진 수용 실측 검증 기록

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

## 자체 검토 결과

- **스펙 대조:** §1.1 측정 방법 → Task 1 `DisplayScale`·`SyntheticDefect`·`RealPortrait`. §1.2 하한·§1.4 상한 → Task 1 테스트(원터치 행은 G4-2). §1.3 상수 → Task 2(`foldFeatureFeather`), Task 3(`foldSurroundFraction`), Task 4(나머지). §2.1 띠 → Task 2. §2.2 밝히기 → Task 3. §2.3 붉은기·번들거림 → Task 4. §2.4 몸 피부 조건·상태 줄 → Task 4. §6 진단 → Task 5. §7.2 VALIDATION → Task 6. §8 "G4-1 6 Task"와 같다.
- **타입 일관성:** `DisplayScale.grid`·`rect`·`changedFraction`·`lumaDelta`·`chromaDelta`·`channelDelta`·`lumaDeltaStandardDeviation`·`percentileAbsoluteLumaDelta`·`luma(_:weight:)`·`recovery`, `RealPortrait.shared`·`render(_:stage:input:)`·`baked`·`mask`·`skinMask`, `SyntheticDefect` 셋, `fineVarianceRatio`, `FaceRegions.foldSkinRaster`·`softMask(raster:)`, `FoldShape` 새 이름, `SkinKernels.foldLift(…wideNumerator:wideDenominator:…)`·`redness(…referenceOffset:…)`, `SkinRefinement.liftFold(…skinMask:…)`, `BodySkinStage.fallbackPersonRegion`, `AppModel.BodySkinStatus`·`bodySkinStatus`·`diagnosticLines`·`lastRenderFailure`, `RecipeSummary.nonDefaultLines`, `UserMessage.bodySkinStatus`·`diagnosticsTitle`·`copyDiagnostics`·`diagnosticLabel`을 정의한 Task와 쓰는 Task에서 같게 썼다. 테스트 수: 패키지 384 → 397(T1, Rendering +13) → 397 → 397 → 398(T4) → 398, 앱 Mac 79 → 79 → 80(T5).
- **Review Focus 매핑:** 1→Task 1, 2→Task 2, 3→Task 3, 4→Task 4, 5→Task 1·기존, 6→Task 1. 모두 테스트 코드가 있다.
- **플레이스홀더 점검:** Task 2의 `rolled*` 표본 점은 "격자를 찍어 확정"이라 적었고 계산값을 함께 두었다. VALIDATION의 실측값은 실행 결과로 채운다. 그 밖에 "TBD/TODO/나중에" 없음.
