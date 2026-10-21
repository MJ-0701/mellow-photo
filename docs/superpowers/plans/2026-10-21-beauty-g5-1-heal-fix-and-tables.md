# 인물 보정 G5-1 색 맞춤 복구·오검출 거절·표 인하 구현 계획

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 1.4.0의 복제 원반 결함을 고치고(원본 질감만 옮기고 밝기·색은 대상 고리에 맞춤), 손·턱 경계 오검출을 거절하고, 원터치 표의 평탄화·밝기·주름 값을 Evoto 실측에 맞춰 내린다. 수용 테스트의 원터치 경계를 스펙 G5 1.2로 다시 정한다.

**Architecture:** 복구 식은 `LocalEditStage.applySpot` 한 함수(수동·자동 공통)이고 커널은 `SkinKernels.heal`이다. 검출 조건은 `BlemishDetector` 안이다. 표는 `OneTouchBundle.Table`뿐이다. 새 측정 도우미는 `RenderingTestSupport`에 둔다. 파이프라인 단계·레시피 키·모듈 표는 바뀌지 않는다.

**Tech Stack:** Swift 5.9 tools / Swift 5 언어 모드, Core Image(CIKL 색 커널), Vision(테스트), XCTest.

**Spec:** `docs/superpowers/specs/2026-10-21-beauty-g5-evoto-calibration-design.md` (1.2, 2절의 G5-1 행, 5절, 7절). 선행: 없음(`beauty-g5` `c7b548b`).

## 사람이 확인할 것

- **순서.** Task 1 색 맞춤 복구 → 2 오검출 거절 → 3 표 인하·README → 4 측정 도우미·수용 테스트 재조정·VALIDATION 초안. 4개 Task, Task마다 Opus 구현 → 리뷰 → 수정, 끝에 전체 리뷰.
- **외부 효과가 있는 단계.** 없음. 푸시·태그·버전 올림 없음.
- **스펙이 정하지 않아 이 계획이 정한 것.**

| 결정 | 이유 | 바꾸면 비용 |
|---|---|---|
| 이 계획에서는 표의 `autoBlemish`를 `true`로 둔다(끄는 것은 G5-2) | 점 지우기 전에 끄면 원터치가 잡티를 아예 안 지운다. 고친 복구가 원반 없이 돈다 | 작음 |
| 복구 고리 평균은 `FrequencySeparation.maskedMean`을 그대로 쓴다(마스크 = 1 − 패치 타원) | 새 흐림 코드 없이 "패치 자신을 뺀 둘레 평균"이 된다 | 작음 |
| 오검출 거절은 검출 쪽(`BlemishDetector`)에만 넣고 복구 쪽 `SourceRules`는 바꾸지 않는다 | 잡히지 않으면 복구도 없다. 복구 쪽 조건은 원본 위치 문제라 별개다 | 작음 |
| 보임 하한은 "실측 뒤 필요한 항목만" 스펙 1.2의 새 문턱으로 내린다. Task 4가 실측값을 먼저 찍고 넘는 항목은 옛 문턱을 유지한다 | 스펙 판정(문턱은 내리지 않는 쪽이 기본) | 작음 |

- **범위 밖(다른 계획).** 점 지우기(G5-2), 얼룩 색 고르기(G5-3), 하네스 실행·VALIDATION 최종(G5-3).
- **위험.** 표를 내리면 데모 사진의 기본 0.6 피부 평균 ΔY가 +0.5/255 아래로 떨어질 수 있다. 대응 규칙: `bodyBrightness`를 0.08 → 0.10까지만 올려 본다(몸 ΔY 상한 +1.5 안). 그래도 미달이면 VALIDATION에 적고 사용자에게 알린다.
- **사용자 조치.** 없음(기기 확인은 1.4.1 뒤).

---

## 에이전트 참조

## Global Constraints

- 작업 위치: 브랜치 `beauty-g5`(worktree `/Users/mj/IdeaProjects/mellow-photo/.claude/worktrees/beauty-g5`), 시작 커밋 `c7b548b` 또는 그 뒤. 모든 Swift·xcodebuild 명령 전에 `export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`.
- **건드리지 않는 파일**: `ShapeWarpStage.swift`·`FaceShapeRig.swift`·`BodyShapeRig.swift`·`DisplacementWarp.swift`·`ShapePrimitive.swift`·`BodySkeleton.swift`와 그 테스트(다른 세션이 작업 중), `PhotoPickerButton.swift`·`project.yml`·`scripts/*`·UI 테스트 타깃.
- 모듈 의존성 표(`docs/architecture/modules.md`)와 `scripts/verify-modules.sh`는 바뀌지 않는다. 파이프라인 단계 이름·순서 불변. 레시피 키·스키마는 이 계획에서 바뀌지 않는다(G5-2·G5-3이 더한다).
- 피부 CIKL 색 커널은 `SkinKernels` 한 곳(`heal` 추가, 6개). 마스크는 `FaceRegions` 한 곳.
- `RenderTuning` 추가(스펙 5절): `healLowBandScale` 0.6, `healRingInnerScale` 1.0, `healRingRadiusScale` 1.5, `healMaxGain` 2.0, `healLumaFloor` 0.01, `blemishCenterMaskMinimum` 0.9, `blemishMaxAspect` 2.0, `blemishMinFill` 0.4. 기존 상수는 바꾸지 않는다.
- 표 변경(스펙 2절, G5-1 몫): `smoothing` 0.16/0.20/0.12, `toneEvening` 0.08/0.10/0.05, `darkCircles` 0.42/0.45/0.38, `nasolabial` 0.32/0.36/0.28, `bodyBrightness` 0.08. 나머지 그대로.
- 한 줄 한 문장, 세미콜론 금지(CIKL 소스 안 제외), 매직 넘버는 명명 상수(`RenderTuning`·`OneTouchBundle.Table`·테스트 `Visibility`·`Naturalness`·`OneTouchVisibility`·`OneTouchNaturalness`). CIKL 안 표준 계수는 주석으로 이름을 단다.
- 한국어 사용자 문구는 앱 타깃에만. 모듈은 `MellowError`만 던진다(새 case 없음).
- CI는 Xcode 26.3(로컬 27). `CGFloat`·`Double` 혼합 연산은 명시 변환. 긴 식은 지역 상수로 나눈다.
- `cd apple && swift format lint --strict --recursive Sources Tests MellowPhoto MellowPhotoTests MellowPhotoUITests` 출력 없음(한도 120자).
- `./scripts/verify-modules.sh` 통과. 패키지 테스트 `cd apple && swift test`. Mac 앱 테스트: `xcodebuild -project apple/MellowPhoto.xcodeproj -scheme MellowPhoto -derivedDataPath apple/build -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO test 2>&1 | grep -E "Executed|TEST (SUCCEEDED|FAILED)|error:"`.
- **iOS 시뮬레이터 테스트는 로컬에서 돌리지 않는다.** `MELLOW_IOS_TESTS`를 켜지 않는다. 시뮬레이터용 빌드만 허용: `xcodebuild -project apple/MellowPhoto.xcodeproj -scheme MellowPhoto -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build 2>&1 | grep -E "BUILD|error:"`.
- 푸시·태그·`scripts/release.sh` 실행 금지. `MELLOW_EVOTO_DIR`로 하네스를 돌리지 않는다(G5-3 몫).
- 커밋: 한국어 Conventional Commits, 마지막 줄 `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`. `git add`는 Task에 나열한 경로만. `git add -A`·`git commit -a` 금지.
- 기준 테스트 수(**시작 전에 `swift test`와 Mac 앱 테스트로 실측해 이 줄에 적는다**. VALIDATION G4 기준 패키지 454(Shared 69 · Rendering 292 · Library 34 · Export 4 · Editing 55) + `c7b548b`의 Rendering +2 = 456 추정, Mac 99). 이 계획이 더하는 수: **Rendering +6**(Task 1 +2, Task 2 +2, Task 4 +2). Shared·Editing·Mac 0.
- 실사진 테스트는 macOS Vision 특징점에 기댄다. 얼굴 수가 1이 아니면 `RealPortrait`가 실패한다 — 그때는 VALIDATION에 적고 사용자에게 알린다.
- 수용 문턱을 못 넘으면 표 값·상수를 고친다. 문턱을 내리는 것은 스펙 1.2의 "새 문턱"까지만이고 VALIDATION에 적는다.

## Review Focus

1. **휘도 경사 위의 수동 잡티.** 복구 원 안 평균 Y가 고리 평균 Y와 1/255 안이어야 한다(옛 복제는 경사 × 2.5r만큼 어긋남). → Task 1 `testHealMatchesPatchToneToSurroundingRingOnAGradient`.
2. **원본 질감 보존.** 복구 원 안 fine 분산이 원본 패치 fine 분산의 0.8배 이상. → Task 1 `testHealKeepsSourceTextureAndNeverExceedsGainLimit`.
3. **턱 경계 그늘 선.** 잡티로 잡히지 않고 옆의 원은 잡힌다. → Task 2 `testElongatedShadowLineIsNotABlemish`.
4. **피부 가장자리 원.** 마스크 0.9 미만 중심은 거절. → Task 2 `testSpotOnTheSkinEdgeIsRejected`.
5. **표를 내린 뒤 데모 원터치.** 기본 0.6 피부 평균 ΔY ∈ [0.5, 3.0]/255, 중간 대역 비 ≥ 0.80, 넓은 대역 비 ≥ 0.85, 강도 1 다크서클 띠 ≤ 10.5, 팔자 ≤ 6.7. → Task 4 `testOneTouchStaysNaturalAtDefaultAndMaximum`.
6. **보임 하한.** 실측이 옛 문턱을 넘는 항목은 옛 문턱 그대로. → Task 4 VALIDATION 초안의 표.

## 인터페이스 요약 (모든 Task가 공유하는 이름)

```swift
// MellowRendering (Task 1)
extension SkinKernels {
    /// 원본 패치 S × (고리 평균 / S 저주파), 채널별, 배율 1/maxGain…maxGain.
    func heal(source: CIImage, sourceLow: CIImage, ringNumerator: CIImage, ringDenominator: CIImage,
              lumaFloor: Double, maxGain: Double, extent: CGRect) throws -> CIImage
}
RenderTuning.healLowBandScale = 0.6, healRingInnerScale = 1.0, healRingRadiusScale = 1.5, healMaxGain = 2.0, healLumaFloor = 0.01
LocalEditStage.applySpot(_:to:context:) -> CIImage      // 시그니처 그대로, 식만 색 맞춤

// MellowRendering (Task 2)
RenderTuning.blemishCenterMaskMinimum = 0.9, blemishMaxAspect = 2.0, blemishMinFill = 0.4
BlemishDetector.isCompact(members: [Int], width: Int, tuning: RenderTuning) -> Bool   // static, 상자 종횡비·채움 비

// MellowShared (Task 3)
OneTouchBundle.Table.common/female/male                 // 값만 변경
OneTouchBundle.Table.bodyBrightness = 0.08

// 테스트 지원 (Task 4)
RenderingTestSupport.bandVarianceRatio(before:after:weight:in:innerRadius:outerRadius:) throws -> Double
DisplayScale.chromaStandardDeviationRatio(_ before: PixelGrid, _ after: PixelGrid, weight: PixelGrid) -> Double
RealPortrait.foldBandMask(_ key: SkinRefinementKey) throws -> PixelGrid      // 기존 private foldMask를 옮김
SyntheticDefect.spotted(_ image: CIImage, centers: [CGPoint], radius: CGFloat, factor: Double, extent: CGRect) -> CIImage
RealPhotoAcceptanceTests.OneTouchVisibility / OneTouchNaturalness            // 값 변경·추가
```

---

### Task 1: 색 맞춤 복구 — `heal` 커널과 `applySpot`

**Files:**
- Modify: `apple/Sources/MellowRendering/Domain/SkinKernels.swift`, `apple/Sources/MellowRendering/Domain/LocalEditStage.swift`, `apple/Sources/MellowRendering/API/RenderTuning.swift`
- Create: `apple/Tests/MellowRenderingTests/HealTests.swift`

- [ ] **Step 1: 실패하는 테스트 작성**

`apple/Tests/MellowRenderingTests/HealTests.swift`:

```swift
import CoreImage
import MellowShared
import XCTest

@testable import MellowRendering

/// 색 맞춤 복구(스펙 G5 5.1). 원본 패치의 질감만 옮기고 밝기·색은 대상 둘레 고리에 맞춘다.
final class HealTests: XCTestCase {
    typealias Support = RenderingTestSupport

    enum Bounds {
        /// 복구 원 안 평균 Y와 고리 평균 Y의 차 상한(8비트).
        static let residual = 1.0
        /// 복구 원 안 fine 분산 ÷ 원본 패치 fine 분산 하한.
        static let textureRatio = 0.8
        static let size = 512
        static let radius: CGFloat = 24
        /// 왼쪽 0.4 → 오른쪽 0.6 선형 휘도 경사(선형 공간).
        static let gradientLow = 0.4
        static let gradientHigh = 0.6
    }

    /// 피부 질감 위에 수평 휘도 경사를 곱한 입력.
    private func gradientSkin() throws -> CIImage {
        let texture = Support.skinTexture(size: Bounds.size)
        let ramp = CIFilter(
            name: "CILinearGradient",
            parameters: [
                "inputPoint0": CIVector(x: 0, y: 0), "inputPoint1": CIVector(x: CGFloat(Bounds.size), y: 0),
                "inputColor0": CIColor(red: Bounds.gradientLow, green: Bounds.gradientLow, blue: Bounds.gradientLow),
                "inputColor1": CIColor(red: Bounds.gradientHigh, green: Bounds.gradientHigh, blue: Bounds.gradientHigh),
            ])!.outputImage!.cropped(to: texture.extent)
        let shaded = texture.applyingFilter("CIMultiplyCompositing", parameters: [kCIInputBackgroundImageKey: ramp])
        return CIImage(cgImage: try Support.renderer.makeCGImage(shaded.cropped(to: texture.extent)))
    }

    private func context(_ image: CIImage) -> RenderContext {
        RenderContext(extent: image.extent, recipe: EditRecipe(), analysis: PhotoAnalysis(), tuning: RenderTuning())
    }

    private func ringLuma(_ grid: PixelGrid, center: CGPoint, inner: CGFloat, outer: CGFloat) -> Double {
        var sum = 0.0
        var count = 0.0
        for y in 0..<grid.height {
            for x in 0..<grid.width {
                let distance = hypot(CGFloat(x) - center.x, CGFloat(grid.height - 1 - y) - center.y)
                guard distance >= inner, distance < outer else { continue }
                let rgba = grid.rgba(CGPoint(x: x, y: y))
                sum += 0.299 * Double(rgba[0]) + 0.587 * Double(rgba[1]) + 0.114 * Double(rgba[2])
                count += 1
            }
        }
        return sum / max(count, 1)
    }

    func testHealMatchesPatchToneToSurroundingRingOnAGradient() throws {
        let image = try gradientSkin()
        let extent = image.extent
        let center = CGPoint(x: 256, y: 256)
        let radius = Bounds.radius
        // 원본은 왼쪽으로 2.5r(60px) 떨어진 더 어두운 피부다.
        let spot = RetouchSpot(
            x: Double(center.x / extent.width), y: Double(center.y / extent.height),
            sourceX: Double((center.x - radius * 2.5) / extent.width), sourceY: Double(center.y / extent.height),
            radius: Double(radius / min(extent.width, extent.height)))
        let healed = try Support.grid(LocalEditStage.applySpot(spot, to: image, context: context(image)))
        let inside = ringLuma(healed, center: center, inner: 0, outer: radius * 0.65)
        let ring = ringLuma(healed, center: center, inner: radius, outer: radius * 1.5)
        XCTAssertLessThanOrEqual(abs(inside - ring), Bounds.residual, "복구 원 안 밝기가 둘레 고리와 같다(원반 없음)")
        let before = try Support.grid(image)
        let beforeInside = ringLuma(before, center: center, inner: 0, outer: radius * 0.65)
        XCTAssertNotEqual(Int(beforeInside), Int(inside), "복구가 실제로 픽셀을 바꿨다")
    }

    func testHealKeepsSourceTextureAndNeverExceedsGainLimit() throws {
        let image = try gradientSkin()
        let extent = image.extent
        let center = CGPoint(x: 256, y: 256)
        let radius = Bounds.radius
        let sourceCenter = CGPoint(x: center.x - radius * 2.5, y: center.y)
        let spot = RetouchSpot(
            x: Double(center.x / extent.width), y: Double(center.y / extent.height),
            sourceX: Double(sourceCenter.x / extent.width), sourceY: Double(center.y / extent.height),
            radius: Double(radius / min(extent.width, extent.height)))
        let healed = LocalEditStage.applySpot(spot, to: image, context: context(image))
        let patch = CGRect(x: center.x - radius * 0.6, y: center.y - radius * 0.6, width: radius * 1.2, height: radius * 1.2)
        let sourcePatch = CGRect(
            x: sourceCenter.x - radius * 0.6, y: sourceCenter.y - radius * 0.6, width: radius * 1.2, height: radius * 1.2)
        let fineRadius = 1.5
        let healedFine = try Support.bandVariances(healed, in: patch, fineRadius: fineRadius, midRadius: 6).fine
        let sourceFine = try Support.bandVariances(image, in: sourcePatch, fineRadius: fineRadius, midRadius: 6).fine
        XCTAssertGreaterThanOrEqual(healedFine / sourceFine, Bounds.textureRatio, "원본 질감이 옮겨진다")
        // 배율 상한: 검은 원본(저주파 0)에서도 maxGain을 넘지 않는다.
        let black = CIImage(color: .black).cropped(to: CGRect(x: 0, y: 0, width: 80, height: 80))
        let dark = CIImage(cgImage: try Support.renderer.makeCGImage(black.composited(over: image).cropped(to: extent)))
        let darkSpot = RetouchSpot(
            x: Double(center.x / extent.width), y: Double(center.y / extent.height), sourceX: Double(40 / extent.width),
            sourceY: Double(40 / extent.height), radius: Double(radius / min(extent.width, extent.height)))
        let fromBlack = try Support.grid(LocalEditStage.applySpot(darkSpot, to: dark, context: context(dark)))
        XCTAssertLessThanOrEqual(Int(fromBlack.red(center)), Int(before(image).red(center)), "검은 원본은 배율 상한에 걸려 밝아지지 않는다")
    }

    private func before(_ image: CIImage) -> PixelGrid {
        try! Support.grid(image)
    }
}
```

- [ ] **Step 2: 실패 확인**

Run: `cd apple && swift test --filter HealTests` → `testHealMatchesPatchToneToSurroundingRingOnAGradient` 실패(잔차 약 (0.2/512) × 60 × 255 ≈ 6/255), 두 번째는 배율 단언 실패.

- [ ] **Step 3: 구현**

`RenderTuning`에 추가(기존 `spotMaxRadiusFraction` 옆):

```swift
    /// 색 맞춤 복구(스펙 G5 5.1)가 원본 패치의 저주파를 재는 흐림 반지름.
    /// 복구 반지름 배수.
    public var healLowBandScale: Double = 0.6
    /// 대상 둘레 고리의 안쪽 반지름.
    /// 복구 반지름 배수.
    public var healRingInnerScale: Double = 1.0
    /// 고리 평균을 재는 흐림 반지름.
    /// 복구 반지름 배수.
    public var healRingRadiusScale: Double = 1.5
    /// 채널별 배율의 상한(하한은 역수).
    public var healMaxGain: Double = 2.0
    /// 배율 분모 하한(선형).
    public var healLumaFloor: Double = 0.01
```

`SkinKernels`에 `heal` 커널(채널별 비율, 분모 하한, 고리 분모 0.001):

```
kernel vec4 healTone(__sample source, __sample sourceLow, __sample ringNumerator, __sample ringDenominator,
                     float floorValue, float maxGain) {
    vec3 ring = ringNumerator.rgb / max(ringDenominator.r, 0.001);
    vec3 gain = clamp(ring / max(sourceLow.rgb, vec3(floorValue)), vec3(1.0 / maxGain), vec3(maxGain));
    return vec4(source.rgb * gain, source.a);
}
```

`LocalEditStage.applySpot`:

```swift
    static func applySpot(_ spot: RetouchSpot, to image: CIImage, context: RenderContext) -> CIImage {
        guard spot.radius > 0 else { return image }
        let extent = context.extent
        let tuning = context.tuning
        let radius = min(tuning.spotMaxRadiusFraction, spot.radius) * context.shortSide
        let center = context.pixelPoint(x: spot.x, y: spot.y)
        let offset = CGAffineTransform(
            translationX: (spot.x - spot.sourceX) * extent.width, y: (spot.y - spot.sourceY) * extent.height)
        let source = image.clampedToExtent().transformed(by: offset)
        let patch = CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)
        let mask = MaskBuilder.ellipse(patch, extent: extent)
        // 대상 둘레 고리(패치 자신을 뺀 피부)의 평균이 복구 패치의 밝기·색이 된다.
        let innerRadius = radius * tuning.healRingInnerScale
        let inner = CGRect(x: center.x - innerRadius, y: center.y - innerRadius, width: innerRadius * 2, height: innerRadius * 2)
        let ring = MaskBuilder.ellipse(inner, extent: extent).applyingFilter("CIColorInvert").cropped(to: extent)
        let ringMean = FrequencySeparation.maskedMean(image, mask: ring, radius: radius * tuning.healRingRadiusScale)
        let sourceLow = FrequencySeparation.blurred(source, radius: radius * tuning.healLowBandScale)
        guard
            let healed = try? SkinKernels.shared.heal(
                source: source, sourceLow: sourceLow, ringNumerator: ringMean.numerator,
                ringDenominator: ringMean.denominator, lumaFloor: tuning.healLumaFloor, maxGain: tuning.healMaxGain,
                extent: patch.intersection(extent))
        else { return image }
        return MaskBuilder.blend(healed, over: image, mask: mask).cropped(to: extent)
    }
```

`ring`의 알파: `CIColorInvert`는 알파를 뒤집지 않으므로 타원 밖(검정, 알파 1)이 흰색이 된다. `MaskBuilder.ellipse`는 `cropped(to: extent)`라 extent 밖은 투명 → 뒤집어도 투명이며 `maskedMean`의 분모가 0이 되는 곳은 커널의 0.001 하한이 막는다.

- [ ] **Step 4: 실행·회귀**

Run: `cd apple && swift test --filter "HealTests|RenderPipelineTests|SkinStageTests"` → 전부 통과. `testAutoBlemishHealsPlantedSpots`(+20 밝아짐)이 통과해야 한다. 미달이면 `healRingRadiusScale`을 1.5 → 2.0으로 올린다(고리가 더 넓어져 잡티 바깥의 밝은 피부가 더 든다).

전체: `cd apple && swift test` → Rendering 기준 +2. lint 출력 없음.

- [ ] **Step 5: 커밋**

```bash
git add apple/Sources/MellowRendering/Domain/SkinKernels.swift apple/Sources/MellowRendering/Domain/LocalEditStage.swift apple/Sources/MellowRendering/API/RenderTuning.swift apple/Tests/MellowRenderingTests/HealTests.swift
git commit -m "fix(rendering): 잡티 복구를 색 맞춤 복구로 바꿔 복제 원반을 없앰

원본 패치의 질감만 옮기고 밝기·색은 대상 둘레 고리 평균에 채널별 비율로 맞춘다.
수동 잡티와 자동 잡티가 같은 함수를 쓴다.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 2: 잡티 오검출 거절 — 피부 가장자리와 길쭉한 영역

**Files:**
- Modify: `apple/Sources/MellowRendering/Domain/BlemishDetector.swift`, `apple/Sources/MellowRendering/API/RenderTuning.swift`
- Test: `apple/Tests/MellowRenderingTests/BlemishDetectorTests.swift`

- [ ] **Step 1: 실패하는 테스트 작성**

`BlemishDetectorTests.swift`에 추가(기존 도우미 `SyntheticFace.make(withBlemishes:)`·`detect` 사용 방식을 따른다):

```swift
    /// 턱 경계의 그늘 선(폭 얼굴 폭 1%, 길이 10%)은 잡티가 아니다. 옆의 원은 잡힌다.
    func testElongatedShadowLineIsNotABlemish() throws {
        let base = SyntheticFace.make()
        let faceWidth: CGFloat = 280
        let lineCenter = CGPoint(x: 256, y: 150)
        let line = Support.hardEllipse(
            center: lineCenter, radii: CGSize(width: faceWidth * 0.05, height: faceWidth * 0.005), extent: base.image.extent)
        let disc = Support.hardEllipse(
            center: CGPoint(x: 200, y: 200), radii: CGSize(width: faceWidth * 0.01, height: faceWidth * 0.01),
            extent: base.image.extent)
        let darkened = SyntheticDefect.shadowed(
            SyntheticDefect.shadowed(base.image, mask: line, depth: 0.2), mask: disc, depth: 0.2)
        let image = CIImage(cgImage: try Support.renderer.makeCGImage(darkened))
        let spots = try BlemishDetector(tuning: RenderTuning(), renderer: Support.renderer).detect(
            image: image, faces: [base.geometry])
        let centers = spots.map { CGPoint(x: $0.x * image.extent.width, y: $0.y * image.extent.height) }
        XCTAssertTrue(centers.contains { hypot($0.x - 200, $0.y - 200) < faceWidth * 0.02 }, "원은 잡힌다")
        XCTAssertFalse(centers.contains { hypot($0.x - lineCenter.x, $0.y - lineCenter.y) < faceWidth * 0.06 }, "선은 거절")
    }

    /// 피부 다각형 가장자리(마스크 < 0.9)의 원은 잡지 않는다.
    func testSpotOnTheSkinEdgeIsRejected() throws {
        let base = SyntheticFace.make()
        let extent = base.image.extent
        let polygon = FaceRegions.skinPolygon(face: base.geometry, extent: extent, tuning: RenderTuning())
        // 윤곽 가장 왼쪽 점에서 안쪽으로 얼굴 폭 1%만 들어간 자리.
        let leftmost = try XCTUnwrap(polygon.min { $0.x < $1.x })
        let edge = CGPoint(x: leftmost.x + 280 * 0.01, y: leftmost.y)
        let disc = Support.hardEllipse(center: edge, radii: CGSize(width: 3, height: 3), extent: extent)
        let image = CIImage(cgImage: try Support.renderer.makeCGImage(SyntheticDefect.shadowed(base.image, mask: disc, depth: 0.2)))
        let spots = try BlemishDetector(tuning: RenderTuning(), renderer: Support.renderer).detect(
            image: image, faces: [base.geometry])
        XCTAssertTrue(spots.isEmpty, "가장자리 원은 거절")
    }
```

합성 얼굴의 피부 질감은 붉은기가 고르므로 `blemishRednessMin` 조건을 통과하려면 `SyntheticDefect.shadowed` 대신 기존 `SyntheticFace.make(withBlemishes:)`의 색(붉고 어두운 원)을 쓰는 도우미가 필요할 수 있다. 그때는 `SyntheticFace`의 `paint` 방식으로 붉은 타원을 그리는 `SyntheticFace.painted(_:center:radii:)`(테스트 지원, internal)를 더해 선과 원 모두 같은 색으로 그린다.

- [ ] **Step 2: 실패 확인**

Run: `cd apple && swift test --filter BlemishDetectorTests` → 두 테스트 실패(선·가장자리 원이 잡힘).

- [ ] **Step 3: 구현**

`RenderTuning`:

```swift
    /// 잡티 중심의 피부 마스크 하한. 피부 다각형 가장자리와 손·턱 경계의 그늘을 거절한다(스펙 G5 5.2).
    public var blemishCenterMaskMinimum: Double = 0.9
    /// 연결 영역 상자의 긴 변 ÷ 짧은 변 상한. 선·주름은 길쭉하다.
    public var blemishMaxAspect: Double = 2.0
    /// 연결 영역의 픽셀 수 ÷ 상자 넓이 하한. 원은 0.785다.
    public var blemishMinFill: Double = 0.4
```

`BlemishDetector.detect(image:face:faceIndex:)`의 영역 루프에서:

```swift
            guard Self.isCompact(members: members, width: width, tuning: tuning) else { continue }
            …
            let centerIndex = min(candidate.count - 1, max(0, Int(sumY / count).clamped… ))  // 중심 픽셀의 mask 값
            guard Double(mask[centerOffset]) >= tuning.blemishCenterMaskMinimum else { continue }
```

중심 픽셀 인덱스: `let cx = Int(sumX / count)`, `let cyTop = height - 1 - Int(sumY / count)`(readPixels는 맨 위 행부터), `centerOffset = (cyTop * width + cx) * 4`, 범위 밖이면 거절.

```swift
    /// 상자 종횡비 ≤ blemishMaxAspect, 채움 비 ≥ blemishMinFill.
    static func isCompact(members: [Int], width: Int, tuning: RenderTuning) -> Bool {
        guard let first = members.first else { return false }
        var minX = first % width
        var maxX = minX
        var minY = first / width
        var maxY = minY
        for index in members {
            minX = min(minX, index % width)
            maxX = max(maxX, index % width)
            minY = min(minY, index / width)
            maxY = max(maxY, index / width)
        }
        let boxWidth = Double(maxX - minX + 1)
        let boxHeight = Double(maxY - minY + 1)
        let aspect = max(boxWidth, boxHeight) / min(boxWidth, boxHeight)
        let fill = Double(members.count) / (boxWidth * boxHeight)
        return aspect <= tuning.blemishMaxAspect && fill >= tuning.blemishMinFill
    }
```

- [ ] **Step 4: 실행·회귀**

Run: `cd apple && swift test --filter "BlemishDetectorTests|SkinStageTests|RealPhotoAcceptanceTests"` → 전부 통과. `testDemoPortraitStaysWithinCapAndOutsideEyesAndLips`는 잡티 수가 줄어도 통과한다(상한만 본다). `testFindsPlantedSpotsAndIgnoresSpotNextToEye`의 심은 원이 채움 비에 걸리면 `blemishMinFill`을 0.35까지 내린다(VALIDATION에 적는다).

- [ ] **Step 5: 커밋**

```bash
git add apple/Sources/MellowRendering/Domain/BlemishDetector.swift apple/Sources/MellowRendering/API/RenderTuning.swift apple/Tests/MellowRenderingTests/BlemishDetectorTests.swift apple/Tests/MellowRenderingTests/RenderingTestSupport.swift
git commit -m "fix(rendering): 피부 가장자리와 길쭉한 그늘을 자동 잡티에서 거절

중심 마스크 0.9 미만, 상자 종횡비 2 초과, 채움 비 0.4 미만인 영역은 잡티가 아니다.
손등·턱 경계의 복제 원반 오검출을 막는다.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

(`RenderingTestSupport.swift`는 도우미를 더했을 때만 `git add`에 넣는다.)

---

### Task 3: 표 인하와 README

**Files:**
- Modify: `apple/Sources/MellowShared/API/OneTouchBundle.swift`, `shared/recipe-schema/README.md`, `docs/superpowers/specs/2026-10-21-beauty-g4-one-touch-design.md`(3.2 표의 값은 G5 스펙이 이미 적었으므로 확인만)
- Test: `apple/Tests/MellowSharedTests/OneTouchBundleTests.swift`

- [ ] **Step 1: 테스트 확인**

`OneTouchBundleTests`는 표 상수를 참조하므로 값이 바뀌어도 통과한다. 구조 단언(남성 < 여성 매끄럽게, 남성 얼룩 고르기 < 공통, 매끄럽게 ≤ 0.5)도 새 값에서 참이다. 새 단언 하나를 더한다(`testTablesScaleLinearlyAndNeverTouchShapeOrLipColour` 끝):

```swift
        for values in [OneTouchBundle.Table.common, OneTouchBundle.Table.female, OneTouchBundle.Table.male] {
            XCTAssertLessThanOrEqual(values.smoothing, 0.25, "Evoto는 중간 대역을 거의 그대로 둔다(스펙 G5 판정 3)")
            XCTAssertLessThanOrEqual(values.toneEvening, 0.15)
        }
        XCTAssertLessThanOrEqual(OneTouchBundle.Table.bodyBrightness, 0.1, "몸 피부 ΔY ≤ +1.5/255")
```

- [ ] **Step 2: 구현**

`OneTouchBundle.Table`:

```swift
        public static let common = Values(
            smoothing: 0.16, darkCircles: 0.42, nasolabial: 0.32, marionette: 0.25, glabella: 0.3, toneEvening: 0.08,
            redness: -0.2, shine: 0.45, eyeBrighten: 0.25, teethWhiten: 0.25, lipVitality: 0, blushIntensity: 0,
            blushColorID: nil)
        public static let female = Values(
            smoothing: 0.20, darkCircles: 0.45, nasolabial: 0.36, marionette: 0.3, glabella: 0.3, toneEvening: 0.10,
            redness: -0.25, shine: 0.4, eyeBrighten: 0.3, teethWhiten: 0.3, lipVitality: 0.2, blushIntensity: 0.15,
            blushColorID: blushColorID)
        public static let male = Values(
            smoothing: 0.12, darkCircles: 0.38, nasolabial: 0.28, marionette: 0.25, glabella: 0.3, toneEvening: 0.05,
            redness: -0.2, shine: 0.5, eyeBrighten: 0.2, teethWhiten: 0.25, lipVitality: 0, blushIntensity: 0,
            blushColorID: nil)
        /// 사진 단위 몸 피부 밝기.
        /// 전체 대상에서만 쓴다.
        /// Evoto 원클릭의 몸 피부 ΔY(+0.3/255)에 맞춰 G5에서 0.15 → 0.08.
        public static let bodyBrightness = 0.08
```

`Table` 주석에 "값은 스펙 G5 2절(Evoto 7쌍 실측)"을 적는다. README의 원터치 표를 같은 값으로 고친다(`autoBlemish`는 아직 true).

- [ ] **Step 3: 실행**

Run: `cd apple && swift test --filter "OneTouchBundleTests|EditDocumentTests"` → 통과. 전체 `swift test` → 테스트 수 불변. `RealPhotoAcceptanceTests`의 원터치 테스트가 옛 하한(`skinMeanLiftRange` 1.275)에 걸려 **실패할 수 있다** — Task 4가 고친다. 이 Task의 커밋은 그 실패를 알고 한다(Task 4와 같은 리뷰 묶음).

- [ ] **Step 4: 커밋**

```bash
git add apple/Sources/MellowShared/API/OneTouchBundle.swift apple/Tests/MellowSharedTests/OneTouchBundleTests.swift shared/recipe-schema/README.md
git commit -m "feat(shared): 원터치 표의 평탄화·밝기·주름 값을 Evoto 실측에 맞춰 내림

매끄럽게 0.16/0.20/0.12, 얼룩 고르기 0.08/0.10/0.05, 다크서클 0.42/0.45/0.38, 팔자 0.32/0.36/0.28, 몸 밝기 0.08.
우리 0.6이 Evoto보다 중간·넓은 대역을 더 평탄하게 하고 더 밝혔다(스펙 G5 판정 3·5).

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 4: 측정 도우미·수용 테스트 재조정·VALIDATION 초안

**Files:**
- Modify: `apple/Tests/MellowRenderingTests/RenderingTestSupport.swift`, `apple/Tests/MellowRenderingTests/RealPhotoAcceptanceTests.swift`, `VALIDATION.md`

- [ ] **Step 1: 측정 도우미**

`RenderingTestSupport` 확장:

```swift
    /// weight 가중 대역(blur(inner) − blur(outer)) 휘도 분산의 후/전 비. 원본 배율.
    static func bandVarianceRatio(
        before: CIImage, after: CIImage, weight: CIImage, in rect: CGRect, innerRadius: Double, outerRadius: Double
    ) throws -> Double {
        let weights = try luma(weight.cropped(to: rect))
        func variance(_ image: CIImage) throws -> Double {
            let inner = try luma(FrequencySeparation.blurred(image, radius: innerRadius).cropped(to: rect))
            let outer = try luma(FrequencySeparation.blurred(image, radius: outerRadius).cropped(to: rect))
            let band = zip(inner, outer).map { $0 - $1 }
            let total = weights.reduce(0, +)
            guard total > 0, band.count == weights.count else { throw MellowError.renderFailed }
            let mean = zip(band, weights).reduce(0) { $0 + $1.0 * $1.1 } / total
            return zip(band, weights).reduce(0) { $0 + $1.1 * ($1.0 - mean) * ($1.0 - mean) } / total
        }
        let first = try variance(before)
        return first > 0 ? try variance(after) / first : 1
    }
```

`DisplayScale`:

```swift
    /// weight 가중 Cr 표준편차의 후/전 비(0…1 Cr).
    static func chromaStandardDeviationRatio(_ before: PixelGrid, _ after: PixelGrid, weight: PixelGrid) -> Double
```

(`chromaDelta`와 같은 순회, `chroma(rgba).cr`의 가중 평균·분산.)

`SyntheticDefect.spotted(_:centers:radius:factor:extent:)`: 중심마다 `hardEllipse` 합집합(`CIMaximumCompositing`) 마스크로 `shadowed(depth: 1 − factor)`(factor < 1은 어둡게, > 1은 `CIColorMatrix` 배율로 밝게).

`RealPortrait.foldBandMask(_:)`: 지금 `RealPhotoAcceptanceTests`의 private `foldMask(_:)`를 옮겨 공개(internal)한다. `RealPortrait.interiorSkinMask()`: `skinMask()`에 `CIColorThreshold`(0.8)를 걸어 피부 안쪽 가중치(하네스 `interiorWeight`와 같음).

- [ ] **Step 2: 수용 테스트 재조정**

`OneTouchVisibility`(처음에는 옛 값 그대로 두고 Step 3의 실측 뒤 필요한 항목만 스펙 1.2 새 값으로):

```swift
    enum OneTouchVisibility {
        static let femaleDefaultChangedFraction = 0.05   // 실측 미달 시 0.04(스펙 G5 1.2)
        static let maleDefaultChangedFraction = 0.05     // 0.03
        static let commonDefaultChangedFraction = 0.05   // 0.03
        static let femaleMaximumChangedFraction = 0.10   // 0.08
        static let maleMaximumChangedFraction = 0.06     // 0.05
        static let femaleMaleDifferenceFraction = 0.02   // 0.015
        static let coupleMinimumChangedFraction = 0.03   // 0.02
    }
```

`OneTouchNaturalness`(스펙 1.2):

```swift
    enum OneTouchNaturalness {
        /// 기본 0.6 얼굴 피부 평균 ΔY(/255). Evoto 원클릭 +1.9, 75분위 +3.0(스펙 G5 1.2).
        static let skinMeanLiftRange = 0.5...3.0
        /// 강도 1 얼굴 피부 평균 ΔY 상한.
        static let maximumSkinMeanLift = 4.0
        static let defaultFineVarianceRatio = 0.9
        static let maximumFineVarianceRatio = 0.85
        static let defaultMidVarianceRatio = 0.80
        static let maximumMidVarianceRatio = 0.70
        static let defaultLowVarianceRatio = 0.85
        static let maximumLowVarianceRatio = 0.80
        /// 중간 대역 바깥 경계·넓은 대역 바깥 경계(얼굴 폭 비율). 하네스 Calibration과 같다.
        static let midOuterFraction = 0.03
        static let lowOuterFraction = 0.12
        static let darkCircleBandMaximumLift = 10.5
        static let nasolabialBandMaximumLift = 6.7
        static let defaultChromaDeviationRatio = 0.80
        static let maximumChromaDeviationRatio = 0.70
        static let percentileAbsoluteLuma = 60.0
        static let percentile = 0.99
        static let skinChroma = 0.015
        static let maleLipChroma = 0.01
        static let femaleLipChroma = 0.03
        static let browChangedFraction = 0.05
        static let outsideFaceChangedFraction = 0.002
    }
```

`testOneTouchStaysNaturalAtDefaultAndMaximum`의 반복 안에 추가:

```swift
            let lift = DisplayScale.lumaDelta(before, result.grid, weight: skin).mean
            if item.strength == OneTouchBundle.defaultStrength {
                XCTAssertTrue(OneTouchNaturalness.skinMeanLiftRange.contains(record(name, "skinMeanLuma", lift)), …)
            } else {
                XCTAssertLessThanOrEqual(record(name, "skinMeanLuma", lift), OneTouchNaturalness.maximumSkinMeanLift, "\(name) 밝기 상한")
            }
            let isDefault = item.strength == OneTouchBundle.defaultStrength
            let interior = try portrait.interiorSkinMask()
            let midRatio = try Support.bandVarianceRatio(
                before: portrait.image, after: result.output, weight: interior, in: skinBounds,
                innerRadius: fineRadius(), outerRadius: Double(portrait.faceWidth) * OneTouchNaturalness.midOuterFraction)
            XCTAssertGreaterThanOrEqual(
                record(name, "midRatio", midRatio),
                isDefault ? OneTouchNaturalness.defaultMidVarianceRatio : OneTouchNaturalness.maximumMidVarianceRatio, "\(name) 중간 대역")
            let lowRatio = try Support.bandVarianceRatio(
                before: portrait.image, after: result.output, weight: interior, in: skinBounds,
                innerRadius: Double(portrait.faceWidth) * OneTouchNaturalness.midOuterFraction,
                outerRadius: Double(portrait.faceWidth) * OneTouchNaturalness.lowOuterFraction)
            XCTAssertGreaterThanOrEqual(
                record(name, "lowRatio", lowRatio),
                isDefault ? OneTouchNaturalness.defaultLowVarianceRatio : OneTouchNaturalness.maximumLowVarianceRatio, "\(name) 넓은 대역")
            let crRatio = DisplayScale.chromaStandardDeviationRatio(before, result.grid, weight: skin)
            XCTAssertGreaterThanOrEqual(
                record(name, "crSigmaRatio", crRatio),
                isDefault ? OneTouchNaturalness.defaultChromaDeviationRatio : OneTouchNaturalness.maximumChromaDeviationRatio, "\(name) 붉은기 분산")
            if !isDefault {
                let darkCircle = try portrait.mask(portrait.foldBandMask(.darkCircles))
                XCTAssertLessThanOrEqual(
                    record(name, "darkCircleBand", DisplayScale.lumaDelta(before, result.grid, weight: darkCircle).mean),
                    OneTouchNaturalness.darkCircleBandMaximumLift, "\(name) 다크서클 ≤ Evoto × 1.3")
                let nasolabial = try portrait.mask(portrait.foldBandMask(.nasolabial))
                XCTAssertLessThanOrEqual(
                    record(name, "nasolabialBand", DisplayScale.lumaDelta(before, result.grid, weight: nasolabial).mean),
                    OneTouchNaturalness.nasolabialBandMaximumLift, "\(name) 팔자 ≤ Evoto × 1.3")
            }
```

새 테스트 둘:

```swift
    /// 자동 잡티 복구가 데모 사진의 경사면에서 원반을 남기지 않는다(스펙 G5 1.2 "자동 잡티 복구").
    func testAutoBlemishHealLeavesNoDiscOnTheDemoCheek() throws {
        let portrait = try self.portrait()
        let cheek = try XCTUnwrap(FaceRegions.cheekRects(face: portrait.face, extent: portrait.extent).first)
        // 볼 상자 아래 턱 쪽(상자 높이만큼 아래)의 경사면.
        let center = CGPoint(x: cheek.midX, y: cheek.minY - cheek.height)
        let radius = portrait.faceWidth * HealBounds.plantedRadiusFraction
        let spotted = try portrait.baked(
            SyntheticDefect.spotted(portrait.image, centers: [center], radius: radius, factor: HealBounds.plantedFactor, extent: portrait.extent))
        let blemish = BlemishSpot(
            x: Double((center.x - portrait.extent.minX) / portrait.extent.width),
            y: Double((center.y - portrait.extent.minY) / portrait.extent.height),
            radius: Double(radius / min(portrait.extent.width, portrait.extent.height)), faceIndex: 0)
        var recipe = EditRecipe()
        recipe.portrait.skin.autoBlemish = true
        let analysis = PhotoAnalysis(faces: portrait.analysis.faces, blemishes: [blemish], personMask: nil, bodies: [])
        let context = RenderContext(extent: portrait.extent, recipe: recipe, analysis: analysis, tuning: portrait.tuning)
        let healed = try DisplayScale.grid(try Support.renderer.makeCGImage(SkinStage().apply(spotted, in: context)))
        let disc = try DisplayScale.grid(Support.hardEllipse(center: center, radii: CGSize(width: radius * 0.65, height: radius * 0.65), extent: portrait.extent))
        let ring = try DisplayScale.grid(try portrait.annulus(center: center, inner: radius, outer: radius * 1.5))
        let residual = abs(DisplayScale.luma(healed, weight: disc) - DisplayScale.luma(healed, weight: ring))
        XCTAssertLessThanOrEqual(record("heal", "discResidual", residual), HealBounds.discResidual, "원반 잔차 없음")
    }
```

`HealBounds`: `plantedRadiusFraction` 0.012, `plantedFactor` 0.80, `discResidual` 3.0. `RealPortrait.annulus(center:inner:outer:)`는 `hardEllipse(outer) − hardEllipse(inner)`(`CISubtractBlendMode` 대신 `CIColorInvert` 곱) 마스크.

두 번째 새 테스트 `testOneTouchKeepsBodyLiftWithinEvotoBounds`: 전체 대상 0.6·1에서 `bodySkinArea` 가중 평균 ΔY ≤ 1.5 / ≤ 2.5(스펙 1.1 몸 피부 행을 데모에서 단언).

- [ ] **Step 3: 실행·조정**

Run: `cd apple && swift test --filter RealPhotoAcceptanceTests 2>&1 | tee /tmp/g5-1-acceptance.log | grep -E "acceptance|passed|failed|error"`.

- `acceptance oneTouch-* changed=…` 줄을 읽어 옛 하한을 넘는 항목은 `OneTouchVisibility` 옛 값 유지, 미달 항목만 스펙 1.2 새 값으로 바꾼다. 새 값도 미달이면 표 값을 올리지 말고(상한 우선) VALIDATION에 적고 사용자에게 알린다.
- `skinMeanLuma`가 0.5 미만이면 `bodyBrightness`를 0.10까지만 올린다(몸 ΔY ≤ 1.5 확인).
- `darkCircleBand`·`nasolabialBand`가 상한을 넘으면 표의 `darkCircles`·`nasolabial`을 0.02씩 내린다.
- 다른 상한에 걸리면 그 항목의 표 값을 내린다(G4 규칙).

전체: `cd apple && swift test` → Rendering 기준 +6. Mac 앱 테스트 통과. lint 출력 없음. iOS 시뮬레이터용 빌드 성공(부팅 없음).

- [ ] **Step 4: VALIDATION 초안**

`VALIDATION.md` 끝에 `## 인물 보정 G5-1 복구 결함·표 인하 (2026-10-XX)` 절: 자동 검증(명령·종료 코드·테스트 수), 원터치 실측 표(하한·상한·새 행 전부, 위 로그의 값), 복구 잔차 실측, 내린 보임 문턱과 이유(있으면), 바뀐 표 값·상수, 스펙과 다르게 한 것, 미검증(실기기·CI·하네스 실측은 G5-3). 수행하지 않은 검증을 통과로 쓰지 않는다.

- [ ] **Step 5: 커밋**

```bash
git add apple/Tests/MellowRenderingTests/RenderingTestSupport.swift apple/Tests/MellowRenderingTests/RealPhotoAcceptanceTests.swift VALIDATION.md
git commit -m "test(rendering): 원터치 수용 경계를 Evoto 실측 기준으로 재조정

기본 0.6 피부 ΔY +0.5~+3.0/255, 강도 1 ≤ +4.0, 중간·넓은 대역 비, 붉은기 분산 비, 다크서클·팔자 띠 상한(Evoto × 1.3),
자동 잡티 복구의 원반 잔차를 데모 사진에서 잰다.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

(표 값을 고쳤으면 `OneTouchBundle.swift`·README를 같은 커밋에 넣고 메시지에 적는다.)

---

## 자체 검토 결과

- **스펙 대조:** 5.1 색 맞춤 복구 → Task 1. 5.2 거절 조건 → Task 2. 2절 G5-1 행(매끄럽게·얼룩 고르기·다크서클·팔자·몸 밝기) → Task 3. 1.2 상한·하한·심은 결함(자동 잡티 복구·수동 복구 경사) → Task 1·4. 7절 도우미 → Task 4. 9절 "G5-1 4 Task"와 같다.
- **타입 일관성:** `SkinKernels.heal`, `RenderTuning.heal*`·`blemish*`, `BlemishDetector.isCompact`, `Support.bandVarianceRatio`, `DisplayScale.chromaStandardDeviationRatio`, `SyntheticDefect.spotted`, `RealPortrait.foldBandMask`·`interiorSkinMask`·`annulus`를 정의한 Task와 쓰는 Task에서 같게 썼다.
- **Review Focus 매핑:** 1·2 → Task 1, 3·4 → Task 2, 5·6 → Task 4.
- **플레이스홀더 점검:** 표 값·상수는 스펙 값이고 조정 규칙을 적었다. "TBD/TODO" 없음.
