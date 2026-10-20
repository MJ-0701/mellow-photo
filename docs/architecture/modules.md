# 모듈 지도와 캔버스

Mellow Photo Apple 코드는 능력 단위 Swift 모듈 다섯 개(`apple/Package.swift`의 MellowKit)와 iPhone·iPad·Mac을 한 번에 빌드하는 SwiftUI 앱 타깃 하나(`apple/MellowPhoto/`)로 이루어집니다. Android(Kotlin)와 Windows(C/C++) 구현도 같은 다섯 모듈 경계를 따릅니다. 설계 근거는 [구조 리팩토링 설계](../superpowers/specs/2026-10-14-apple-modulith-restructure-design.md) 3절입니다.

## 의존성 지도

```
MellowShared ◄── MellowEditing ◄── MellowLibrary
     ▲
     ├──────── MellowRendering ◄── MellowExport
     └──────── (앱 타깃은 다섯 모듈 모두 import)
```

허용 의존성은 다음 표가 전부입니다. 역방향, 수평(예: Rendering→Library), 앱 타깃을 향한 의존은 금지합니다.

| 모듈 | import 허용 | 금지 프레임워크 |
|---|---|---|
| MellowShared | Foundation, CoreGraphics | 그 외 전부 |
| MellowEditing | MellowShared | CoreImage, Vision, SwiftUI, UIKit, AppKit, Photos |
| MellowLibrary | MellowShared, MellowEditing | CoreImage, Vision, SwiftUI, UIKit, AppKit, Photos |
| MellowRendering | MellowShared, CoreImage, Vision, ImageIO, UniformTypeIdentifiers | SwiftUI, UIKit, AppKit, Photos |
| MellowExport | MellowShared, MellowRendering, ImageIO, UniformTypeIdentifiers | SwiftUI, UIKit, AppKit, Photos |
| 앱 타깃 | 전부 | 없음 |

모듈 내부는 폴더 세 개로 나눕니다. `API/`에는 `public` 타입만 두고, `Domain/`과 `Infrastructure/`는 `internal`입니다. 다른 모듈과 앱은 `API/`의 타입만 씁니다. 아래 캔버스의 "공개 API"는 각 모듈 `API/` 폴더의 타입 전부입니다.

## 모듈 캔버스

### MellowShared
| 항목 | 내용 |
|---|---|
| 책임 | 플랫폼 간 계약이 되는 값 타입과 오류 (공유 커널) |
| 공개 API | `EditRecipe`, `ColorAdjustments`, `PortraitAdjustments`, `SkinAdjustments`, `SkinRefinementKey`, `FaceShapeAdjustments`, `FaceShapeKey`, `FeatureAdjustments`, `FeatureKey`, `BackgroundAdjustments`, `BodyShapeAdjustments`, `BodyShapeKey`, `BodySkinAdjustments`, `BodySkinKey`, `EffectAdjustments`, `EffectKey`, `MakeupAdjustments`, `MakeupPart`, `MakeupTint`, `MakeupStrength`, `MakeupCatalog`, `MakeupLook`, `MakeupColor`, `BlemishSpot`, `LocalEdit`, `RetouchSpot`, `WarpStroke`, `NormalizedPoint`, `NormalizedRect`, `PhotoID`, `FaceGeometry`, `FaceLandmark`, `BodyGeometry`, `BodyJoint`, `Preset`, `PresetValues`, `BuiltInPresets`, `DetailAdjustments`, `LookSelection`, `GeometryAdjustments`, `Look`, `LookCatalog`, `GeometryTransform`, `AutoEnhanceSuggestion`, `AdjustmentRange`, `MellowError` |
| 의존 | 없음 (Foundation, CoreGraphics) |
| 포트 | 없음 |
| 규칙 | 레시피는 v2로만 인코드하고 빠진 키는 기본값으로 디코드, 좌표는 방향 보정 이미지 기준 정규화(원점 왼쪽 아래), 내장 프리셋(내추럴·포근한·클린)은 `BuiltInPresets` 한 곳, 룩은 `shared/looks/looks.v1.json` 데이터를 `LookCatalog`로 읽고 모르는 id는 `look(id:)`가 nil, 메이크업 팔레트·룩은 `shared/makeup/makeup.v1.json`을 `MakeupCatalog`로 읽고 형식 위반(모르는 부위, rgb 개수·범위, 중복 id, 다른 부위 색을 쓰는 룩, 범위 밖 강도)은 파일 전체를 거부, 렌더용 색은 `color(id:for:)`가 그 부위 팔레트에서만 찾음, 기하 좌표 변환(출력 ↔ 원본)은 순수 수학 `GeometryTransform`, 90° 회전과 화면 기준 좌우 반전은 `GeometryAdjustments.turnedClockwise()`·`flippedHorizontally()`가 자르기 영역·수평 보정을 이미지와 함께 옮김, B~F 레시피 골격은 B에서 기본값과 함께 정의, 옛 키 `portrait.skinSmoothing`·`faceSlim`은 읽기만 함, `dependsOnFaces`(피부·얼굴형·눈입·메이크업 강도)·`dependsOnPerson`(배경·몸 피부, 지금 읽는 곳이 없어 저장·분석을 막거나 고르지 않음, 인물 분석은 사진 준비 때 늘 돎)·`dependsOnBody`(체형), G 레시피 키(`portrait.skin` 정밀 7종, 최상위 `bodySkin`·`effects`)는 키 추가만이고 기본값 0이며 없으면 0으로 읽음(schemaVersion 2 유지), 범위는 `AdjustmentRange.skinRefinement(_:)`·`bodySkin(_:)`(붉은기·피부 톤만 bipolar)와 `effects`는 unit, 효과는 분석이 필요 없어 `dependsOn*`에 넣지 않음, 잡티(`BlemishSpot`)는 영속화하지 않음, 관절점(`BodyGeometry`·`BodyJoint` 14개, 신뢰도 포함)은 영속화하지 않음, 값 범위(unit 0…1·bipolar −1…1·얼굴형은 미소만 unit)는 `AdjustmentRange` 한 곳, 체형 범위는 `AdjustmentRange.bodyShape`(다리 길게만 unit), 한국어 사용자 문구 없음 |
| 테스트 | `apple/Tests/MellowSharedTests` (레시피 코딩, 얼굴 기하, `edit-recipe.v2` 스키마 키 대조, `GeometryTransform` 왕복, 회전·반전 시 같은 원본 픽셀 유지, 룩 카탈로그, 메이크업 카탈로그. GPU 불필요) |
| 다른 플랫폼 대응 | Kotlin `:shared`, C++ `mellow_shared` |

### MellowEditing
| 항목 | 내용 |
|---|---|
| 책임 | 사진 한 장의 편집 상태와 규칙 |
| 공개 API | `EditDocument`, `EditChange`, `EditingPolicy`, `SyncCategory` |
| 의존 | MellowShared |
| 포트 | 없음 |
| 규칙 | 변경 전 체크포인트, 수동 편집 시 얼굴형(`faceShape`)·체형(`bodyShape`)·대상 잠금, 프리셋·일괄 적용 시 잠긴 얼굴형·체형 보존, 자동 보정은 색·디테일·피부·눈입만 바꿈, 자동 보정(`applyAuto`)은 체크포인트 한 번이고 값이 같으면 아무것도 바꾸지 않음, `applyAuto`는 피부 그룹 중 `smoothing`·`autoBlemish`만 바꾸고 피부 정밀 7종은 보존, `EditChange.skinRefinement`·`bodySkin`·`effect`는 `EditingPolicy` 범위로 자르고 잠기지 않음, 일괄 적용은 `applyFromBatch(_:categories:)`가 고른 동기화 항목(`SyncCategory` 9종, 기본 전부)만 복사하고 얼굴 의존 항목(피부·얼굴형·눈입·메이크업)을 복사할 때만 잠기지 않은 사진의 대상 얼굴을 전체로 되돌리며 빈 선택은 아무것도 하지 않음, 프리셋·일괄 적용은 바뀌는 값이 없으면 체크포인트를 만들지 않음, `quarterTurns`·`flipHorizontal` 변경은 `GeometryAdjustments`의 회전·반전 함수를 거침, 룩·기하 변경은 잠금과 무관, `EditChange.feature`·`backgroundBlur`는 0…1로 자르고 잠기지 않음, 메이크업 룩은 `applyMakeupLook`이 체크포인트 한 번으로 부위 값을 채우고 부위 값이 바뀌면 `lookID`를 비움, 색을 처음 고를 때 강도 0이면 `makeupDefaultIntensity`, 메이크업은 수동 편집 잠금 대상 아님, 값 범위는 `EditingPolicy`(unitRange·bipolarRange·faceShapeRange·bodyShapeRange, 값은 MellowShared `AdjustmentRange`를 그대로 내보냄), 히스토리 40 |
| 테스트 | `apple/Tests/MellowEditingTests` (GPU 불필요) |
| 다른 플랫폼 대응 | Kotlin `:editing`, C++ `mellow_editing` |

규칙은 모두 `EditDocument` 안에만 있습니다. 슬라이더 드래그는 `beginContinuousChange`/`endContinuousChange`로 시작할 때 한 번만 체크포인트하고, 실행 취소·다시 실행·초기화는 진행 중이던 연속 변경을 끝냅니다. 프리셋은 얼굴을 고르지 않으므로 적용해도 사진의 대상 얼굴을 유지합니다(앱은 사용자 프리셋에 대상 얼굴을 저장하지 않습니다). 잠긴 동안의 얼굴 형태·체형·대상 변경은 무시하고 `EditDocument.Rejection`을 돌려줍니다. 잠기지 않은 사진에 일괄 적용하면 얼굴 의존 동기화 항목을 하나라도 복사할 때만 대상 얼굴을 모든 얼굴로 되돌립니다(색감·효과만 동기화하면 대상 얼굴 유지).

### MellowLibrary
| 항목 | 내용 |
|---|---|
| 책임 | 사진 목록과 선택, 작업 사본, 세션 영속화와 복구, 프리셋 보관, 사진 수 정책 |
| 공개 API | `ProjectSession`, `PhotoEntry`, `SessionSnapshot`, `SessionStore`, `JSONSessionStore`, `WorkingCopyStore`, `LibraryPolicy` |
| 의존 | MellowShared, MellowEditing |
| 포트 | `SessionStore` (`load() throws -> SessionSnapshot?`, `save(SessionSnapshot) throws`). 구현은 같은 모듈의 `JSONSessionStore` |
| 규칙 | 세션 파일은 v1(출시본 iPhone)·v2를 읽고 v2로만 씀, 원자적 쓰기, 슬라이더 드래그 동안은 저장을 미루고 끝날 때 한 번 씀(`beginDeferredPersistence`/`endDeferredPersistence`), 읽을 수 없는 파일은 `session-recovery-<uuid>.json`으로 보존한 뒤 새 세션, 사진 제거는 저장 성공 후에만 반영, 사진 수 상한은 물리 메모리 4GB 미만 12장·8GB 미만 24장·그 외 40장, 프리셋 이름 30자, 작업 사본은 `Library/<uuid>.<확장자>`이고 출시본 iPhone의 상위 폴더 사본도 찾음, 전체 적용은 `applyToAll(from:categories:)`(기본 전부)가 고른 동기화 항목만 다른 사진에 복사(선택은 세션 파일에 저장하지 않음, 빈 선택이거나 바뀐 사진이 없으면 저장하지 않음) |
| 테스트 | `apple/Tests/MellowLibraryTests` (v1 픽스처 이행, `session-file.v2` 스키마 키 대조, 손상 세션 보존, 쓰기 실패 시 제거 중단, 사진 수 정책. GPU 불필요) |
| 다른 플랫폼 대응 | Kotlin `:library`, C++ `mellow_library` |

디스크 포맷 `SessionFile`(v2)과 `SessionFileV1`은 `Infrastructure/`의 DTO이며, `SessionFileMapper`가 `SessionSnapshot`과 변환합니다. `ProjectSession`은 DTO를 모릅니다. 형식은 [`shared/recipe-schema/`](../../shared/recipe-schema/README.md)가 기술합니다.

### MellowRendering
| 항목 | 내용 |
|---|---|
| 책임 | 사진 읽기, 얼굴·인물·관절점 분석, 레시피 렌더, 미리보기 캐시 |
| 공개 API | `PhotoPipeline`, `PreparedPhoto`, `RenderPipeline`, `RenderStage`, `RenderContext`, `RenderTuning`, `Renderer`, `FaceAnalyzer`, `PhotoAnalysis`, `PersonAnalyzer`, `VisionPersonAnalyzer`, `BodyAnalyzer`, `VisionBodyAnalyzer`, `ImageLoader`, `ImageMetadata`, `AutoEnhancer` |
| 의존 | MellowShared (CoreImage, Vision, ImageIO) |
| 포트 | `FaceAnalyzer` (`analyze(CIImage) throws -> [FaceGeometry]`). 기본 구현 `VisionFaceAnalyzer`는 `Infrastructure/`에 있으며 앱이 조립할 수 있도록 `public`입니다. `PersonAnalyzer` (`personMask(CIImage) throws -> CIImage?`, 사람 없으면 nil). 기본 구현 `VisionPersonAnalyzer`(`VNGeneratePersonSegmentationRequest`, `.balanced` 품질이라 결과는 512×384 고정, 0…255 중 128 이상인 사람 픽셀이 1% 미만이면 nil)도 `Infrastructure/`의 `public`. `BodyAnalyzer` (`analyze(CIImage) throws -> [BodyGeometry]`, 관절 상자 넓이가 큰 사람부터). 기본 구현 `VisionBodyAnalyzer`(`VNDetectHumanBodyPoseRequest`, 신뢰도 0인 관절은 버림)도 `Infrastructure/`의 `public` |
| 규칙 | 단계 순서 `skin` → `bodySkin` → `feature` → `makeup` → `background` → `shapeWarp` → `localEdit` → `geometry` → `color` → `detail` → `look` → `effect` 고정(기하 단계는 좌표 기반 단계 뒤, 색 보정 앞이라 얼굴·수동 편집 좌표는 원본 기준이고 비네팅·선명도·룩·효과는 자른 프레임 기준), 기하 단계는 반전 → 90° 회전 → 수평 보정(빈 모서리 없는 최소 확대) → 자르기 순서이고 자르기 픽셀 경계는 변마다 가장 가까운 픽셀로 반올림, `RenderContext.skipsCrop`이면 자르기만 건너뜀(자르기 도구 미리보기), `AutoEnhancer`는 sRGB 감마 값의 64구간 휘도 히스토그램(구간 대표값은 중심 (i + 0.5)/64)과 평균색으로 제안, 미리보기 LRU 3장 캐시(미리보기 렌더는 디스크를 읽지 않음), 미리보기 긴 변은 메모리 8GB 이상 1600px·미만 1200px, 원본 렌더는 준비 때의 정규화 얼굴 좌표 재사용, 얼굴 의존 레시피인데 분석이 실패했거나 준비 전이면 `faceAnalysisUnavailable`, 수치 상수는 `RenderTuning`, `CIWarpKernel`은 `WarpKernel` 하나만 감쌈, 얼굴 영역 마스크는 `FaceRegions` 한 곳(윤곽 다각형을 `CGContext` 회색 비트맵으로 그리고 볼 평균과의 Cb·Cr 거리로 가중), 피부 CIKL 색 커널은 `SkinKernels` 한 곳(`chroma`·`bands`·`fold`·`tone`·`blush` 커널 5개), `PhotoPipeline.prepare`가 얼굴 뒤에 `BlemishDetector`로 잡티를 찾아 `RenderContext.blemishes`로 넘김(실패하면 빈 목록), `skin` 단계는 대상 얼굴마다 자동 잡티 패치 복구 → 주름 밝히기(다크서클 → 팔자 → 마리오네트 → 미간, `FaceRegions+Folds.swift`의 얼굴 폭 기준 얼굴 좌표 타원 × 주름용 피부 비트맵 `foldSkinRaster` 띠, 주름용 피부 비트맵은 눈·입 보호 영역을 얼굴 폭 × `foldFeatureFeather`(1.2%)만 넓혀 피부 보정용(5%)과 캐시 항목이 따로, 기준은 피부 마스크 × (1 − 띠) 가중 넓은 평균 휘도(반지름 얼굴 폭 × `foldSurroundFraction`, 가중치 합이 `SkinKernels.foldMinimumCoverage` 미만이면 밝히지 않음), 휘도 비율 배율 상한 `foldLiftMaxGain`, 특징점이 없는 띠만 건너뜀) → 대역 합성(피부 보정·얼룩 고르기·번들거림을 한 번에, 저주파를 마스크 가중 넓은 평균 쪽으로 당기고 번들거림은 중주파도 줄임, 얼룩 고르기·번들거림이 둘 다 0이면 피부 보정만으로 기존 세 대역 경로, 세 값이 모두 0이면 이 단계를 건너뜀) → 붉은기(볼 기준 Cr − `rednessReferenceOffset`보다 붉은 만큼 줄이거나 Cr을 고르게 더함), `bodySkin` 단계는 인물 마스크(없으면 가장 넓은 얼굴 상자를 가로 `bodySkinFallbackWidthScale`배·위끝에서 아래로 높이 `bodySkinFallbackHeightScale`배 늘린 부드러운 대체 영역 `BodySkinStage.fallbackPersonRegion`) × 가장 넓은 얼굴의 볼 기준 피부색 가중치 × (1 − 모든 얼굴의 눈·눈썹·입, 특징점이 없으면 대체 타원)에 밝기·톤을 걸고 매끄럽게는 거기서 잘라내지 않은 얼굴 다각형 전체를 뺀 영역에만 걸며(매끄럽게 → 밝기·톤 순서), 얼굴이 없으면 입력 그대로(오류 아님, `dependsOnFaces`에 넣지 않음), `effect` 단계는 현재(기하 뒤) extent 기준으로 글로우(흐린 사본을 0…1로 자르고 제곱해 스크린 합성, `CIBloom`은 쓰지 않음) → 그레인(`CIRandomGenerator` 회색 잡음을 짧은 변 × `grainSizeFraction`(0.0025) 크기·전체 폭 `grainMaxAmplitude`(0.30)로 가장 가까운 화소 샘플링으로 키워 sRGB 감마 공간에서 오버레이, 위치마다 고정이라 결정적), 얼굴형·체형 변형은 `ShapeWarpStage` 하나가 이동 원소(`ShapePrimitive` push·scale·band)를 모아 `DisplacementWarp`로 한 번만 샘플링(out(p) = in(p − D(p)), 원소마다 반지름 × `shapeDisplacementLimit`), 이동량 지도 CIKL 커널은 `DisplacementWarp` 한 곳(push·scale은 색 커널로 이동량 지도에 그리고 일반 커널로 샘플링, 원소 영향 경계의 합집합 안에서만 그린 뒤 `CIBlendWithMask`로 원본 위에 합성), 얼굴형 원소는 `FaceShapeRig`가 `FaceFrame`(눈동자 기준 얼굴 좌표)에서 만들고 값을 `AdjustmentRange`로 직접 자름(유한하지 않은 값은 0), |yaw| > `faceShapeYawThreshold`면 cos 비율로 약화, 윤곽점이 없으면 원소 없음, 체형 분석은 사진 준비 때 `PhotoAnalysis.bodies`에 두고 실패는 `PreparedPhoto.bodyAnalysisFailure`이며 렌더는 체형 원소만 건너뜀(오류 아님), `BodySkeleton`이 신뢰도 `bodyJointMinConfidence` 미만 관절을 빼고 어깨 폭·몸통 축을 정하며 두 어깨가 없으면 체형 없음(`PreparedPhoto.hasBody`도 같은 판정), 체형 원소는 `BodyShapeRig`가 가장 큰 사람(`bodies.first`)에서 만들고 값을 `AdjustmentRange`로 직접 자름(유한하지 않은 값은 0), push 이동은 어깨 폭 × min(항목 최대, `bodyShapeMaxShift`)이고 반지름은 이동 / `shapeDisplacementLimit` 이상, 다리 길게 띠는 이동량 지도에 그리지 않고 샘플링 커널이 smoothstep 식으로 더함(띠 하나만, 패치는 띠 시작 행부터 먼 가장자리까지), 다리 띠는 두 엉덩이와 발목 하나 이상이 있을 때만 만듦, 사진 준비 때의 분석(얼굴·잡티·인물 마스크)은 `PhotoAnalysis` 하나로 `RenderContext.analysis`에 넘기고 새 분석은 이 묶음에만 더함, 다각형 마스크 비트맵은 `PhotoAnalysis`의 `RegionMaskCache`(다각형·extent 키, 상한은 얼굴 수 비례 `RegionMaskCache.capacity(forFaces:)` = 얼굴당 20(해상도마다 10 × 2)·최소 32)가 사진마다 한 번만 그리고 미리보기 캐시에서 밀려난 사진은 놓음, 인물 분석 실패는 `PreparedPhoto.personAnalysisFailure`이고 렌더는 배경 단계만 건너뜀(오류 아님), 눈·눈동자·입술·치아 마스크도 `FaceRegions` 한 곳, 눈·입 CIKL 색 커널은 `FeatureKernels` 한 곳(감마 BT.601 YCbCr 가중치·색 이동), `feature` 단계는 마스크 영역만 계산해 원본 위에 합성(마스크 밖 같은 바이트), 다문 입(안쪽 입술 넓이 < 얼굴 상자 × `mouthOpenMinArea`)은 치아를 건너뜀, `background` 단계는 인물 마스크를 extent로 가로·세로 따로 키워 흐리고 반전한 지도로 `CIMaskedVariableBlur` 후 같은 마스크로 원본 위에 합성, 메이크업은 `RenderContext.makeupCatalog`(기본 빈 카탈로그)의 그 부위 팔레트 색만 쓰고 없으면 그 부위만 건너뜀(오류 아님), 마스크는 `FaceRegions`(확장 `FaceRegions+Makeup.swift`) 한 곳에서 만들고 립은 입술 생기와 같은 `lipMask`, 블러셔·쉐딩·하이라이터는 `FaceFrame` 좌표의 기운 타원 × 피부 다각형 비트맵(피부 보정과 같은 캐시 항목), 아이섀도는 눈꺼풀 띠 × 흐리지 않은 눈 비트맵의 반전(눈 안 정확히 0, 속눈썹 선에서 끊김), 아이섀도 띠의 눈썹은 그 눈과 같은 쪽만, 눈썹 진하게는 넓힌 눈썹 마스크에 원래 눈썹 상자의 평균색(`CIAreaAverage`)을 곱함, 섞기는 Core Image 기본 섞기 모드(소프트 라이트·곱하기·스크린)를 sRGB 감마 공간에서(바탕과 색 층을 `CILinearToSRGBToneCurve`로 바꿔 섞고 `CISRGBToneCurveToLinear`로 되돌림, 마스크 합성은 선형), 특징점이 없는 부위는 건너뜀 |
| 테스트 | `apple/Tests/MellowRenderingTests` (GPU 회귀, 단계 순서, 캐시 동등성, 데모 인물 랜드마크, 디테일·룩·기하 픽셀 검사, 자동 보정 제안, 합성 얼굴의 피부 마스크·주파수 분리·잡티 검출과 복구, 타원 마스크 윤곽, 이동량 지도(점 표식 이동·원소 합·띠 단조성), 얼굴 좌표계(기울기·뒤집힘·대체 경로), 얼굴형 원소 방향·대칭·회전·클램프·접힘 검사·데모 사진 특징점, 얼굴 단계 렌더, 분석 묶음·마스크 캐시, 인물 분석(데모 사진·빈 사진·스텁 실패), 눈·입술·치아 마스크(붉은 입술 제외·다문 입·특징점 누락·데모 사진), 눈·치아·입술 렌더(마스크 밖 불변·범위 밖 값), 배경 흐림(사람 안쪽 같은 바이트·축별 배율·가장자리·실패 시 건너뜀·원본 해상도), 관절점(신뢰도·상자·Vision 이름 대응·큰 사람 순서), 몸통 축(기울기·엉덩이 없음), 체형 원소(방향·관절 누락·범위 밖·NaN·상한에 안 걸림·기울기·접힘), 다리 띠(smoothstep 가장자리·지도 밖 계산·패치 위 같은 바이트·640px 이동 정밀도), 체형 렌더(무릎 표식 이동·가장 큰 사람만·얼굴과 한 번에·분석 실패 시 건너뜀), 메이크업(강도 0·모르는 색·다른 부위 색·빈 카탈로그·범위 밖 강도, 부위별 마스크 밖 같은 바이트, 블러셔·아이섀도·눈썹·쉐딩·하이라이터 위치, 기울어진 얼굴, 특징점 누락, 대상 얼굴만, 얼굴 셋 두 해상도 캐시 유지), 인물 보정 G(주름 띠 마스크 위치·특징점 누락·기울어진 얼굴, 주름 밝히기·얼룩 고르기·번들거림·붉은기의 항등·마스크 밖 불변·클램프·대상 얼굴·`smoothing`만 있는 레시피 바이트 불변, 몸 피부의 인물 마스크 밖·옷·눈 불변·얼굴 피부 매끄럽게 제외·톤 방향·얼굴이 없으면 항등·인물 마스크가 없으면 얼굴 둘레 대체 영역, 효과의 항등·결정성·평균 밝기 유지·글로우가 밝은 영역을 더 올림·1 넘는 입력을 어둡게 하지 않음·기하 뒤 extent, 단계 이름 배열·캐시 항목 수), 인물 보정 G4-1(주름용 피부 비트맵·주변 피부 가중 기준·몸 피부 대체 영역), 실사진 수용(`RealPhotoAcceptanceTests`, 데모 사진·실제 Vision, 폰 화면 배율 하한·자연스러움 상한, 합성 그늘·반점·반사광 결함 회복). macOS) |
| 다른 플랫폼 대응 | Kotlin `:rendering`, C++ `mellow_rendering` |

`PhotoPipeline`은 `init(analyzer:personAnalyzer:bodyAnalyzer:tuning:lookCatalog:makeupCatalog:)`로 인물·체형 분석기(기본 nil = 분석 안 함)와 룩·메이크업 카탈로그(기본값 `.empty`)를 받고, 미리보기·원본 렌더 모두 같은 메이크업 카탈로그를 `RenderContext`에 넘깁니다. B0에서 더한 메서드는 `preview(_:recipe:showsUncropped:)`(true면 자르기만 건너뛴 미리보기), `autoEnhanceSuggestion(_:hasFaces:)`(캐시된 미리보기를 분석, 현재 레시피와 무관), `lookThumbnails(_:)`(사진 썸네일에 룩 단계만 강도 1로 입힌 `[룩 id: CGImage]`)입니다. `reprepareIfEvicted(_:at:)`는 미리보기 캐시에서 밀려난 사진을 다시 준비해 새 `PreparedPhoto`를 돌려주고(캐시에 있으면 nil), 앱은 그 결과로 사진 정보(얼굴·인물·체형과 그 실패)를 갱신합니다.

얼굴 분석 실패는 오류가 아니라 `PreparedPhoto.faceAnalysisFailure`로 전달합니다. 색감·수동 편집은 계속할 수 있습니다. 오류 사유는 영어 식별자(예: `PhotoPipeline.unpreparedReason` = `photo-not-prepared`)이며 사용자 문구는 앱의 `UserMessage`가 정합니다.

### MellowExport
| 항목 | 내용 |
|---|---|
| 책임 | 렌더 결과를 파일로 안전하게 쓰기, 이름 충돌 정책, 저장 대상 추상화 |
| 공개 API | `Exporter`, `ExportFormat`, `ExportOptions`, `ExportDestination`, `FileNamingPolicy` |
| 의존 | MellowShared, MellowRendering (ImageIO, UniformTypeIdentifiers) |
| 포트 | `ExportDestination` (`publish(fileURL:suggestedName:) async throws`). 구현은 앱 타깃 `Platform/` |
| 규칙 | 임시 파일에 쓰고 재해독으로 검증한 뒤 `renameatx_np(RENAME_EXCL)`로 공개(덮어쓰기 없음), 출력은 8bit sRGB JPEG/PNG·EXIF 방향 1·원본 GPS와 카메라 EXIF 복사 안 함, 원본 해상도를 끄면 긴 변 최대 4096px, 파일 이름은 `<이름>_mellow`에 충돌 시 번호 |
| 테스트 | `apple/Tests/MellowExportTests` (내보내기·충돌·GPS 없음, 이름 정책. macOS) |
| 다른 플랫폼 대응 | Kotlin `:export`, C++ `mellow_export` |

## 앱 타깃

`apple/MellowPhoto/`는 다섯 모듈을 모두 import하는 유일한 곳입니다. 정의는 `apple/project.yml`(XcodeGen)이고 생성된 `apple/MellowPhoto.xcodeproj`를 커밋합니다.

| 폴더 | 역할 |
|---|---|
| `App/` | `MellowPhotoApp`, 창, 명령(⌘Z·⇧⌘Z). 장면 전환 시 내보내기 취소와 작업 중단·재개 |
| `Application/` | `AppModel`(composition root, `@Observable`·`@MainActor`)과 기능별 extension(`+Editing`, `+Library`, `+Export`, `+Geometry`(자르기 비율·회전), `+Looks`(룩 썸네일·자동 보정)), 도구 목록 `EditorTool`(`look, crop, adjust, beauty, makeup, body, background, retouch, warp`), 뷰티 패널 탭 `BeautyTab`(피부·얼굴·눈·입·피부톤), 비교 모드 `AppModel.CompareMode`(`off`·`full`·`split`, 기존 `isComparing`은 `full`을 뜻하는 계산 속성, 분할 모드는 들고 있는 원본의 기하가 미리보기의 기하와 같을 때만 원본을 겹침), 동기화 항목 선택 `AppModel.syncCategories`(세션 상태, 기본 전부), 유스케이스 `ImportPhotos`·`ExportPhotos`, `RenderScheduler`(디바운스와 세대 토큰으로 마지막 요청만 렌더), 포트 `PhotoImporter`(`Ports.swift`), 피부톤 탭 상태 줄 `AppModel.BodySkinStatus`(`bodySkinStatus`·`canAdjustBodySkin`, 사람 영역이 없거나 사람 분석이 실패해도 얼굴이 있으면 대체 영역이라 슬라이더를 켬), 정보 시트 진단 절 `AppModel+Diagnostics`(`diagnosticLines`·`RecipeSummary`·`DeviceModel`, 마지막 렌더 오류 `lastRenderFailure`는 사진을 바꾸면 지움), 모든 한국어 문구 `UserMessage` |
| `Features/` | SwiftUI 화면. `Library`, `Editor`(전체 적용 옆 동기화 항목 메뉴 `SyncMenu`, 분할 비교 분할선 `CompareDivider` 포함), `Export`, `Presets`, `Info`, `Shared`. compact(iPhone 세로)는 세로 스택, regular(iPad·Mac)는 라이브러리·캔버스·인스펙터 3단 |
| `Platform/` | 포트 어댑터와 실기기 조립 |
| `Resources/` | 에셋, `Localizable.xcstrings`, Info.plist(iOS·macOS), `PrivacyInfo.xcprivacy`, Mac 엔타이틀먼트(App Sandbox), `container-migration.plist` |

`AppModel`은 `ProjectSession`(안에 `SessionStore`), `PhotoPipeline`(안에 `FaceAnalyzer`·`PersonAnalyzer`·`BodyAnalyzer`), `WorkingCopyStore`, `PhotoImporter`, `Exporter`, 룩 카탈로그, `makeupCatalog`(실기기 조립은 번들 `makeup.v1.json`, 읽지 못하면 빈 카탈로그와 안내)를 생성자로 받습니다. `ExportDestination`은 내보낼 때마다 넘깁니다. 테스트(`apple/MellowPhotoTests`)는 가짜 어댑터로 같은 생성자를 씁니다.

유스케이스는 두 개뿐입니다.

- `ImportPhotos`: `PhotoImporter`가 임시 폴더에 옮긴 파일을 정책 상한만큼 받아, 사진마다 작업 사본으로 이동 → `PhotoPipeline.prepare` → 세션에 추가 → 저장합니다. 어느 단계에서 실패해도 사본을 지우고 단계 이름과 함께 `ImportReport`에 기록합니다.
- `ExportPhotos`: 사진마다 원본 렌더 → `Exporter`로 임시 파일 작성 → `ExportDestination`에 공개 → 임시 파일 정리. 취소는 `Task` 취소이며 결과는 `ExportReport`입니다.

`Platform/` 어댑터:

| 파일 | 역할 |
|---|---|
| `SystemPhotoImporter` | `PhotoImporter` 구현. PhotosPicker 항목과 파일 선택·드래그 앤 드롭으로 받은 파일을 임시 폴더로 복사 |
| `PhotoLibraryDestination` | iOS·iPadOS `ExportDestination`. 사진 앱에 새 사진으로 추가(addOnly 권한) |
| `FolderDestination` | macOS `ExportDestination`. 사용자가 고른 폴더에 복사, `FileNamingPolicy`로 충돌 회피 |
| `LegacyMacPresets` | 구 Mac 앱의 `presets.json`을 세션 복원 뒤 한 번 흡수하고 `presets.json.imported`로 이름 변경 |
| `AppModel+Live` | 실기기 조립. `Application Support/MellowPhoto/session.json`, `…/Library/` 작업 사본, `VisionFaceAnalyzer`, `VisionPersonAnalyzer`, `VisionBodyAnalyzer`, 번들 룩·메이크업 카탈로그, 기기별 `LibraryPolicy`·`RenderTuning` |

## 검증

`scripts/verify-modules.sh`가 이 문서의 의존성 표와 소스의 import를 대조합니다. 표의 값을 스크립트 안에 그대로 옮겨 두고 `swift package describe --type json`의 타깃 의존성과 비교하며, 각 모듈 소스의 `import` 문에서 금지 프레임워크(Shared는 ImageIO, 모든 모듈은 PhotosUI 포함)를 찾고, 모듈마다 `API/` 폴더가 있는지 확인합니다. 위반하면 종료 코드 1이며 `scripts/test-apple.sh`와 CI의 필수 단계입니다. 이 표를 바꾸면 스크립트의 표도 같은 커밋에서 고칩니다.
