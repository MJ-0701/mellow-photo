# 인물 보정 B~F (피부·얼굴·디테일·체형·메이크업) 설계

작성 2026-10-15. 선행: [구조 리팩토링 A](2026-10-14-apple-modulith-restructure-design.md), [기본 편집 B0](2026-10-14-b0-basic-editing-design.md).

## 사람이 확인할 것

### 결정

| 결정 | 이유 | 바꾸면 비용 |
|---|---|---|
| Apple 기본 기능(Vision·Core Image)만 쓰고 모델을 번들하지 않음 | 앱이 가볍고 모델 변환·라이선스 작업이 없음. 영역 계산은 한 모듈에 모아 나중에 분할 모델로 교체 가능 | 중간 |
| 다섯 단계를 B → C → D → E → F 순서로 만들고 끝난 뒤 1.2.0으로 한 번 배포 | 사용자 결정 | 작음 |
| 색을 바꾸는 얼굴 보정은 원본 좌표에서 먼저, 얼굴·체형 변형은 그 뒤 한 번만 | 화면이 덜 깨지고 영역 계산이 단순해짐 | **큼** |
| 얼굴 10개·체형 7개 슬라이더를 이동량 지도 하나로 합쳐 한 번만 다시 그림 | 여러 번 변형하면 화질이 떨어짐 | **큼** |
| (C 구현 중 변경) 이동량 지도를 그라데이션 덧셈 대신 Core Image 커널 언어 색 커널로 그리고, 이동 원소가 닿는 영역의 합집합 안에서만 계산한 뒤 원본 위에 합성 | 그라데이션 덧셈은 음수 이동량을 보존하지 못함. 영역 제한으로 Mac 8000×6000·얼굴 1개 최대 메모리 875 → 832 MB. 커널 언어는 지원 중단 경고가 늘어남(기존 피부 커널과 같은 처지) | 작음 |
| (D 구현 중 변경) 사진 준비 때의 분석(얼굴·잡티·인물 마스크)을 `RenderContext` 개별 필드 대신 `PhotoAnalysis` 묶음 하나로 넘기고, 다각형 마스크 비트맵은 묶음 안 사진별 캐시(`RegionMaskCache`)가 한 번만 그림 | B 최종 리뷰 이월 사항. 분석이 늘 때마다(E 관절점) 생성자 인자가 늘지 않고, 같은 사진의 눈·입·피부 마스크를 렌더마다 다시 그리지 않음. 옛 생성자를 남겨 기존 호출부·테스트는 그대로 | 작음 |
| (E 구현 중 변경) 다리 길게 띠는 이동량 지도에 그리지 않고 다시 그리는 커널이 식으로 계산하고, 띠 양 끝(골반·발목)을 부드럽게 시작·끝냄. 다시 그리는 범위는 골반 행부터 사진 먼 가장자리까지 | 큰 사진에서 다리를 바꿀 때 사진 크기 이동량 지도가 생기지 않고 큰 이동도 반 픽셀 계단이 없음. 골반에서 늘림이 꺾이지 않는 대신 무릎 근처가 가장 많이 늘어남 | 작음 |
| (E 구현 중 변경) 체형 이동 상한을 하나(몸 폭의 6%)가 아니라 항목마다 따로 둠(허리 6%·몸 전체 3.5%·팔 2%·허벅지 3.5%·어깨 4%·목 3%, 모두 6% 이하) | 팔·목처럼 가는 부위에 6%를 그대로 주면 과함. 수치는 한 곳에서 조정 | 작음 |
| (E 구현 중 변경) 목 보정은 목 관절 바로 위 좁은 범위만 밀고 턱·입은 움직이지 않음 | 처음 범위는 턱 끝과 입술까지 닿아 목 대신 얼굴 아래쪽이 변형됨(리뷰 지적). 고개를 숙였거나 목이 짧은 사람은 턱 아래가 조금 움직일 수 있음 | 작음 |
| (E 구현 중 변경) 두 어깨가 모두 보여야 체형으로 인정(아니면 "전신 없음" 안내). 다리 길게는 두 엉덩이와 발목 하나 이상이 보일 때만 동작하고 거꾸로·누운 사람은 건너뜀 | 어깨 폭이 모든 체형 이동의 기준 길이라 하나만 보이면 크기를 정할 수 없음. 상반신 사진에서 다리 길게 슬라이더는 켜져 있지만 효과가 없음 | 작음 |
| (E 구현 중 변경) 화면 이름 "전체 날씬"을 "몸 전체"로 부름 | 가운데 0인 양방향 슬라이더라 "날씬"만 가리키는 이름이 맞지 않음 | 작음 |
| 얼굴 보정은 찾은 얼굴 모두(기존 대상 얼굴 선택 유지), 체형은 가장 큰 사람 한 명 | 단체 사진에서 체형 변형이 서로 간섭함 | 작음 |
| 얼굴형·체형 슬라이더는 가운데 0인 양방향(미소·다리 길게만 한 방향) | Evoto·메이투와 같은 조작감 | 작음 |
| 수동 잡티·변형 편집이 있으면 얼굴형·체형 슬라이더도 잠김 | 수동 편집 좌표가 변형 뒤에서 어긋남(기존 얼굴 미세 조정과 같은 규칙) | 작음 |
| 메이크업 룩은 부분별 값을 채워 넣는 방식 | 자동 보정과 같은 방식, 고른 뒤 부분별로 손볼 수 있음 | 작음 |
| 자동 보정에 피부 보정 0.3·자동 잡티·눈 또렷하게 0.2 추가, 얼굴형·체형·메이크업은 건드리지 않음 | "인물 전체 예쁘게"를 유지하되 모양 변형은 사용자 선택으로 | 작음 |
| 도구 줄: 필터·자동·자르기·조정·뷰티(피부/얼굴/눈·입)·메이크업·체형·배경·잡티·변형 | 13개를 10개로 묶음, "인물"은 "뷰티"로 대체 | 작음 |

### 범위

| 단계 | 들어가는 것 |
|---|---|
| B 피부 | 질감 유지 피부 보정(기존 "피부 정돈" 슬라이더를 대체), 자동 잡티 스위치 |
| C 얼굴 | 얼굴 폭·턱선·광대·눈 크기·눈 간격·코 폭·입 크기·미소·이마·턱 길이 (기존 "얼굴 미세 조정"은 얼굴 폭으로 흡수) |
| D 디테일 | 눈 또렷하게, 치아 미백, 입술 생기, 배경 흐림 |
| E 체형 | 다리 길게, 허리, 몸 전체(처음 이름 "전체 날씬"), 팔, 허벅지, 어깨, 목 |
| F 메이크업 | 립(6색)·블러셔(4색)·아이섀도(4색)·눈썹 진하게·쉐딩/하이라이터, 메이크업 룩 5종(데일리·쿨톤·웜피치·로지·스모키) |

### 범위 밖

피부톤 균일·미백, 다크서클·팔자주름, 번들거림 제거, 배경 색·교체·제거, 아이라이너·속눈썹, 동영상, 얼굴 분할 모델 번들. 사용자가 고르지 않았거나 모델이 필요함.

### 위험과 대응

- **피부 영역 경계:** 머리카락이 얼굴을 덮거나 조명이 강하면 피부색 판별이 흔들림. 피부 영역은 부드럽게 경계 처리하고 강도 상한을 둠. 부족하면 영역 계산만 분할 모델로 교체.
- **체형 변형의 배경 휨:** 문틀·벽 모서리 같은 직선이 휠 수 있음. 강도를 보수적으로(몸 폭의 6% 이내) 잡고 VALIDATION에 기록.
- **다리 길게:** 발 아래가 아래로 밀려 사진 아래쪽이 최대 8% 잘릴 수 있음.
- **분석 시간:** 사진 준비 때 얼굴·인물 영역·관절점·잡티를 모두 계산함. 미리보기 해상도에서만 계산하고 실패해도 다른 보정은 계속 동작.
- **화면 확인:** 보정 품질은 자동 테스트로 판정할 수 없음. 실제 사진으로 보는 것은 사용자 조치.

### 사용자 조치

- 1.2.0 TestFlight 빌드에서 실제 인물 사진으로 피부·얼굴·체형·메이크업 결과 확인.
- 강도가 과하거나 약한 항목 피드백(수치는 `RenderTuning`·데이터 파일 한 곳에서 조정).

### 외부 효과가 있는 단계

다섯 단계 구현·머지 후 `scripts/release.sh apple 1.2.0` → `git push origin main apple-v1.2.0`. 태그 푸시는 TestFlight 업로드와 외부 그룹 베타 심사 제출을 일으킴.

## 에이전트 참조

### 1. 공통 구조

#### 1.1 모듈 배치 (`docs/architecture/modules.md` 규칙 준수)

| 새 타입 | 모듈·폴더 | 설명 |
|---|---|---|
| `SkinAdjustments`, `FaceShapeAdjustments`, `FeatureAdjustments`, `BackgroundAdjustments`, `BodyShapeAdjustments`, `MakeupAdjustments`, `MakeupPart` | MellowShared/API | 레시피 값 |
| `BodyGeometry`, `BodyJoint` | MellowShared/API | 관절점(정규화, 원점 왼쪽 아래). 영속화 안 함 |
| `BlemishSpot` | MellowShared/API | 자동 잡티 위치(정규화 중심·반지름). 영속화 안 함 |
| `MakeupCatalog`, `MakeupLook`, `MakeupColor` | MellowShared/API | `shared/makeup/makeup.v1.json`을 읽음 |
| `PersonAnalyzer`, `BodyAnalyzer` 프로토콜 | MellowRendering/API | `FaceAnalyzer`와 같은 포트 |
| `VisionPersonAnalyzer`, `VisionBodyAnalyzer` | MellowRendering/Infrastructure | `VNGeneratePersonSegmentationRequest`, `VNDetectHumanBodyPoseRequest` |
| `BlemishDetector` | MellowRendering/Domain | 미리보기에서 잡티 목록 계산 |
| `FaceRegions` | MellowRendering/Domain | 윤곽점에서 피부·눈·입술·치아·볼·눈두덩 마스크를 만드는 유일한 곳(분할 모델 교체 지점) |
| `FrequencySeparation` | MellowRendering/Domain | 세 층 분리·합성 |
| `ShapeRig` (`FaceShapeRig`, `BodyShapeRig`) | MellowRendering/Domain | 슬라이더 → 이동 원소 목록 |
| `DisplacementWarp` | MellowRendering/Domain | 이동 원소 → 이동량 지도 → 한 번 샘플링 (`WarpKernel` 옆, CIKL 일반 커널) |
| 단계 `FeatureStage`, `MakeupStage`, `BackgroundStage`, `ShapeWarpStage` | MellowRendering/Domain | `SkinStage`는 다시 씀, `FaceReshapeStage`는 `ShapeWarpStage`로 대체 |

새 프레임워크 import 없음(Vision·CoreImage는 Rendering에 이미 허용). `verify-modules.sh` 변경 없음.

#### 1.2 레시피 확장 (schemaVersion 2 유지, 키 추가만)

```json
"portrait": {
  "targetFace": null,
  "skin":   { "smoothing": 0, "autoBlemish": false },
  "face":   { "width": 0, "jaw": 0, "cheekbone": 0, "eyeSize": 0, "eyeDistance": 0,
              "noseWidth": 0, "mouthSize": 0, "smile": 0, "forehead": 0, "chinLength": 0 },
  "features": { "eyeBrighten": 0, "teethWhiten": 0, "lipVitality": 0 }
},
"background": { "blur": 0 },
"body": { "legLength": 0, "waist": 0, "overall": 0, "arms": 0, "thighs": 0, "shoulders": 0, "neck": 0 },
"makeup": {
  "lookID": null,
  "lip":       { "colorID": null, "intensity": 0 },
  "blush":     { "colorID": null, "intensity": 0 },
  "eyeshadow": { "colorID": null, "intensity": 0 },
  "brow":      { "intensity": 0 },
  "contour":   { "intensity": 0 }
}
```

- 범위: `skin.smoothing`·`features.*`·`background.blur`·`makeup.*.intensity` 0…1, `face.*`·`body.*` −1…1(`smile`·`legLength`는 0…1). 범위는 `EditingPolicy`의 명명 상수 한 곳.
- 이전 키 호환: `portrait.skinSmoothing`이 있고 `portrait.skin`이 없으면 `skin.smoothing = skinSmoothing`. `portrait.faceSlim`이 있고 `portrait.face`가 없으면 `face.width = -faceSlim`. 인코드는 새 키만. v1 세션 읽기 테스트 유지.
- `PortraitAdjustments.dependsOnFaces`는 skin·face·features·makeup 중 하나라도 0이 아니면 true. `EditRecipe`에 `dependsOnPerson`(background.blur > 0), `dependsOnBody`(body 중 0이 아닌 값) 추가.
- `allValuesFinite`에 새 스칼라 전부 포함.
- `shared/recipe-schema/edit-recipe.v2.schema.json`·README 갱신, `PresetValues`에 새 그룹 포함(프리셋 저장·일괄 적용이 새 값을 나름).
- `EditChange`에 항목별 케이스 추가(`skinSmoothing`, `autoBlemish(Bool)`, `faceShape(FaceShapeKey, Double)`, `feature(FeatureKey, Double)`, `backgroundBlur`, `bodyShape(BodyShapeKey, Double)`, `makeupLook(String?)`, `makeupColor(MakeupPart, String?)`, `makeupIntensity(MakeupPart, Double)`). `affectsGeometry`는 `faceShape`·`bodyShape`·`targetFace`가 true. 기존 `faceSlim` 케이스는 제거하고 호출부를 `faceShape(.width, …)`로 옮김.

#### 1.3 파이프라인 순서

```
skin → feature → makeup → background → shapeWarp → localEdit → geometry → color → detail → look
```

- 좌표·마스크를 쓰는 단계(skin~shapeWarp, localEdit)는 모두 geometry 앞, 원본 좌표.
- `RenderPipelineTests.testStageOrderMatters` 이름 배열을 단계마다 갱신.

#### 1.4 분석 (사진 준비 때 1회, 미리보기 해상도)

`PhotoPipeline.prepare`가 얼굴에 이어 순서대로 계산해 `Entry`에 둠:
1. 얼굴(기존).
2. 잡티 목록(얼굴이 있을 때) — `BlemishDetector`.
3. 인물 마스크 — `PersonAnalyzer.personMask(_:) throws -> CIImage?`(회색조, 사람 1·배경 0, 미리보기 이미지로 계산). 받은 크기 그대로(원점 (0, 0)) 보관하고 렌더 시 extent로 가로·세로를 따로 확대. `VisionPersonAnalyzer`(`.balanced` 품질)의 결과는 입력 비율과 무관하게 512×384 고정이라 축마다 배율이 다르다. 마스크 픽셀 중 128/255 이상이 1% 미만이면 "사람 없음"으로 nil. (D 구현 중 변경: 처음 문구는 "미리보기 크기" 마스크를 원본 extent로 확대.)
4. 관절점 — `BodyAnalyzer.analyze(_:) throws -> [BodyGeometry]`, 면적이 가장 큰 사람을 앞에.

각 분석은 독립적으로 실패할 수 있고 실패는 `PreparedPhoto`에 `personAnalysisFailure`·`bodyAnalysisFailure`로 남김(얼굴과 같은 방식). 레시피가 그 분석에 의존하는데 실패했으면 렌더는 해당 단계만 건너뜀(오류를 던지지 않음), 앱은 패널에 안내 문구를 표시. 분석 결과는 `PhotoAnalysis`(MellowRendering/API, `faces`·`faceAnalysisFailure`·`blemishes`·`personMask`·`personAnalysisFailure`, E에서 `bodies` 추가) 하나로 묶어 `RenderContext.analysis`로 넘기고, `RenderContext.faces`·`blemishes`·`personMask`는 묶음을 읽는 계산 속성이다. 새 분석은 이 묶음에만 더하고 `RenderContext`·`PhotoPipeline`의 인자 목록은 늘리지 않는다. 다각형 마스크 비트맵은 묶음의 `RegionMaskCache`(다각형·extent 키, 32개 상한)가 사진마다 한 번만 그리며, 미리보기 캐시에서 밀려난 사진의 비트맵은 놓는다. 옛 생성자 `RenderContext(extent:recipe:faces:…blemishes:)`는 묶음을 만들어 넘기는 형태로 남긴다. `makeupCatalog: MakeupCatalog`는 F에서 `RenderContext`에 추가(기본값 있음). (D 구현 중 변경: 처음 문구는 `RenderContext`에 `blemishes`·`personMask`·`bodies` 개별 필드 추가.)

`PhotoPipeline.init`에 `personAnalyzer`, `bodyAnalyzer` 인자 추가(테스트는 스텁). 앱 `AppModel+Live.swift`가 Vision 구현을 주입.

#### 1.5 이동량 지도 (`DisplacementWarp`)

- 이동 원소 `ShapePrimitive`: `.push(center, vector, radius)`(반지름 안에서 smoothstep 감쇠로 vector만큼 이동), `.scale(center, factor, radius)`(반경 방향 확대·축소), `.band(yStart, yEnd, stretch)`(가로 띠 세로 늘림, 다리 길게 전용). 띠 안 이동은 stretch × span × smoothstep(t).
- 모든 원소를 더한 이동량 `D(p)`를 RG float 이미지로 만들고(push·scale마다 CIKL `CIColorKernel(source:)` 하나(`pushField`·`scaleField`)가 앞 지도에 자기 이동량을 더함, 음수 보존, 작업 색공간 float), 일반 커널(`CIKernel(source:)`) 하나로 `out(p) = in(p − D(p))`를 샘플링. 원소별 이동 길이는 `radius × RenderTuning.shapeDisplacementLimit`로 제한. 지도와 샘플링은 `DisplacementWarp.influenceBounds`(limit 적용 원소의 영향 경계 합집합 ∩ extent, band는 지도에 넣지 않고 샘플링 커널이 같은 식으로 더하며 띠는 하나만, 패치는 띠 시작 행부터 먼 가장자리까지) 안에서만 하고 `CIBlendWithMask`로 원본 위에 합성. (C 구현 중 변경: 처음 문구는 `CIRadialGradient`·`CIConstantColor`·`CIAdditionCompositing` 덧셈과 전체 extent 지도였음.) (E 구현 중 변경: 처음 문구는 bandField 색 커널과 band 영향 = extent 전체.)
- 기존 수동 변형(`LocalEditStage.applyWarp`)은 그대로 둠.
- 테스트: 원소 0개면 입력과 같은 바이트, push 하나가 지정 방향으로 픽셀을 옮김, 두 원소 합이 각각의 이동 합과 근사.

### 2. B 피부

- **`FaceRegions.skinMask(face:image:extent:)`:** `faceContour` 점 + 눈썹 위로 얼굴 상자 높이 × `skinForeheadExtension`만큼 연장한 호로 다각형을 만든다. 눈·눈썹·바깥 입술 다각형을 `skinFeatureFeather`만큼 넓혀 뺀다. 볼 두 곳(눈 아래, 코 옆)에서 YCbCr 평균·분산을 재고 Cb·Cr 거리가 `skinChromaSigma` 이내인 픽셀만 남기는 가중치를 곱한다. 마지막에 얼굴 폭 × `skinMaskFeather`로 흐린다. 윤곽점이 없으면 기존 타원 마스크로 폴백.
- **`FrequencySeparation`:** 반지름 `r1 = 얼굴폭 × fineBandFraction`, `r2 = 얼굴폭 × midBandFraction`. `low = blur(r2)`, `mid = blur(r1) − low`, `fine = img − blur(r1)`. 결과 `low + mid × (1 − smoothing × midReductionMax) + fine`. 피부 마스크 안에서만 합성.
- **`BlemishDetector.detect(image:faces:) -> [BlemishSpot]`:** 피부 마스크 안 휘도에 DoG(잡티 크기 = 얼굴폭 × 0.5%~2%)를 적용, 주변보다 `blemishLumaDrop` 이상 어둡고 Cr이 `blemishRednessMin` 이상 높은 연결 영역을 잡티로. 얼굴당 최대 40개, 눈·입 다각형과 겹치면 제외. 픽셀 읽기는 `Renderer.readPixels`로 얼굴 영역을 최대 512px로 줄여서.
- **적용:** `skin.autoBlemish`가 켜져 있으면 `SkinStage`가 각 잡티를 `LocalEditStage.applySpot`과 같은 패치 복구로 지운 뒤 주파수 분리를 함.
- **UI:** 뷰티 › 피부: "피부 보정" 슬라이더, "자동 잡티" 스위치.
- **테스트:** 합성 얼굴(피부색 타원 + 가짜 윤곽점)에서 눈 영역 픽셀 불변, 모공 대역(fine) 분산이 ±10% 안, 중간 대역 분산 감소, 합성 어두운 점 5개 검출·눈 안 점 무시, 이전 `skinSmoothing` 키 디코드.

### 3. C 얼굴 리셰이프

- **`FaceShapeRig.primitives(face:adjustments:extent:) -> [ShapePrimitive]`:** 얼굴 좌표계(중심 = 얼굴 상자 중심, x축 = 두 눈동자를 잇는 방향, roll 반영)에서 계산하고 이미지 좌표로 돌림. 이동량 상한 = 얼굴폭 × `faceShapeMaxShift`(항목별 RenderTuning). |yaw| > 0.35rad면 `cos` 비율로 약화, 윤곽점 없으면 빈 배열.

| 항목 | 원소 |
|---|---|
| width | 윤곽점 중 눈~입 높이 점들을 얼굴 중심선 쪽으로 push |
| jaw | 입 아래 윤곽점을 안쪽·위로 push (V라인) |
| cheekbone | 눈 높이 윤곽점을 안쪽으로 push |
| eyeSize | 각 눈동자 중심 scale(반지름 = 눈 폭 × 1.2) |
| eyeDistance | 각 눈 중심을 중심선에서 멀어지거나 가까워지게 push |
| noseWidth | 코 날개 점(nose 영역 좌우 끝)을 noseCrest 쪽으로 push |
| mouthSize | 입술 중심 scale |
| smile | 입꼬리 두 점을 위·바깥으로 push |
| forehead | 눈썹 위 이마 영역을 위·아래로 push |
| chinLength | 턱 끝 점 아래 영역을 아래·위로 push |

- **`ShapeWarpStage`:** 대상 얼굴 모두의 얼굴 원소 + (E) 체형 원소를 모아 `DisplacementWarp` 한 번. 원소가 없으면 입력 그대로.
- **UI:** 뷰티 › 얼굴: 슬라이더 10개. 미소만 0…1, 나머지 9개는 가운데 0인 양방향(0 근처 스냅).
- **테스트:** width −1이면 왼쪽 윤곽점 원소 벡터가 +x, 오른쪽이 −x; 좌우 대칭; roll 30°면 벡터도 30° 회전; 값 0이면 빈 배열; 렌더에서 윤곽 근처 표식 픽셀이 중심 쪽으로 이동; `faceSlim` 키 마이그레이션.

### 4. D 눈·치아·입술·배경

- **색 계산(D 구현 중 정함):** 흰자·치아 판별과 색 이동은 `FeatureKernels`의 CIKL 색 커널에서 sRGB 감마 값으로 바꾼 뒤 BT.601 YCbCr(휘도 BT.601, Cb·Cr은 `SkinKernels`와 같은 계수)로 계산하고 다시 선형으로 되돌린다. 눈 높이는 눈 다각형 경계 상자의 짧은 변, "얼굴 면적"은 얼굴 상자 넓이, 노란기 제거는 음의 Cb를 0 쪽으로 옮기는 것이다. 특징점이 없는 얼굴은 해당 보정만 건너뛴다.
- **눈 또렷하게(`FeatureStage`):** `FaceRegions.eyeMask`(눈 다각형). 마스크 안에서 휘도 상위·채도 낮은 픽셀(흰자)을 `eyeWhiteLift × 값`만큼 밝게, 눈동자 원(동공 중심, 반지름 = 눈 높이 × 0.5) 안을 `CISharpenLuminance`로 `eyeIrisSharpen × 값`.
- **치아 미백:** `FaceRegions.teethMask` = 안쪽 입술 다각형 × (휘도 > `teethLumaMin`) × (Cr < `teethRednessMax`). 다각형 면적이 얼굴 면적의 `mouthOpenMinArea`보다 작으면 생략. 마스크 안 노란기(Cb 쪽 이동) 제거 + 밝기 `teethLift × 값`.
- **입술 생기:** 바깥−안쪽 입술 다각형, 채도 +`lipSaturationMax × 값`, 붉은기 소폭.
- **배경 흐림(`BackgroundStage`):** `personMask`를 extent로 가로·세로 따로 확대·`backgroundMaskFeather`로 부드럽게 한 뒤 반전해 `CIMaskedVariableBlur`(반지름 = 짧은 변 × `backgroundBlurMaxFraction` × 값), 같은 반전 마스크로 원본 위에 합성해 사람 안쪽은 원본 바이트로 둔다. 마스크가 없으면(사람 없음·인물 분석 실패·준비 전) 입력 그대로.
- **UI:** 뷰티 › 눈·입: 슬라이더 3개. 배경 도구: 흐림 슬라이더 + 사람 없음 안내.
- **테스트:** 마스크 밖 픽셀 불변(눈·치아·입술 각각), 붉은 입술 픽셀은 치아 마스크에서 제외, 입 다문 얼굴은 치아 무변화, 스텁 인물 마스크에서 사람 영역 불변·배경만 변화.

### 5. E 체형

- **`BodyGeometry`:** `joints: [BodyJoint: NormalizedPoint]`, `confidence: [BodyJoint: Double]`, `boundingBox`. 관절: neck, leftShoulder, rightShoulder, leftElbow, rightElbow, leftWrist, rightWrist, leftHip, rightHip, leftKnee, rightKnee, leftAnkle, rightAnkle, root. 신뢰도 < `bodyJointMinConfidence`(0.3)인 관절은 없는 것으로.
- **`BodyShapeRig.primitives(body:adjustments:extent:)`:** 상한 = 몸통 폭(어깨 사이) × `bodyShapeMaxShift`(0.06).
- 항목별 최대는 `RenderTuning`(허리 0.06·몸 전체 0.035·팔 0.02·허벅지 0.035·어깨 0.04·목 0.03, 모두 `bodyShapeMaxShift` 이하), push 이동 = 어깨 폭 × 값 × min(항목 최대, `bodyShapeMaxShift`), push 반지름 ≥ 이동 / `shapeDisplacementLimit`, 음수는 가늘게·좁게·짧게. 화면 이름은 overall을 "몸 전체"로 부름. 두 어깨가 없으면 체형 없음(안내 대상). 다리 띠는 두 엉덩이와 발목 하나 이상이 있고 엉덩이 중점이 발목 평균보다 어깨 폭 × 0.5 이상 위일 때만. 목 push는 중심이 목 관절 위 어깨 폭 × 0.1, 반지름 어깨 폭 × 0.15라 관절 위 0.25W에서 0(턱 끝 0.28W 이동 0px). (E 구현 중 정함, 목 범위는 E 리뷰 후 변경: 처음 구현은 중심 0.2W·반지름 0.3W.)

| 항목 | 원소 |
|---|---|
| legLength | `.band(골반 y, 발목 y, stretch = 값 × 0.08)` — 띠 아래는 아래로 밀리고 이미지 경계에서 잘림 |
| waist | 어깨~골반 55% 높이, 몸통 양옆을 중심선 쪽 push |
| overall | 몸통·골반·허벅지 높이 3곳의 양옆을 중심선 쪽 push |
| arms | 어깨-팔꿈치, 팔꿈치-손목 선분 중점의 양옆을 선분 쪽 push |
| thighs | 골반-무릎 선분 중점의 양옆을 선분 쪽 push |
| shoulders | 양 어깨 관절을 바깥(+)·안쪽(−) push |
| neck | 목 관절과 턱 사이를 위(+)·아래(−)로 push, 턱 아래에서 끝남 |

- 필요한 관절이 없으면 그 항목만 건너뜀. 체형은 `bodies.first`(가장 큰 사람)만.
- **UI:** 체형 도구: 슬라이더 7개, 관절이 없으면 "전신이 보이는 사진에서 동작합니다" 표시.
- **테스트:** waist −1이면 양옆 원소가 중심선을 향함, 관절 누락 시 해당 항목 빈 배열, band 매핑이 단조·연속, 스텁 관절로 렌더 시 띠 아래 표식 픽셀이 아래로 이동.

### 6. F 메이크업

- **데이터 `shared/makeup/makeup.v1.json`** (앱 번들 사본 `apple/MellowPhoto/Resources/makeup.v1.json`, 두 파일 바이트 동일, README 포함):
  - `colors`: 부위별 팔레트 — lip 6(`lip-nude`, `lip-coral`, `lip-rose`, `lip-red`, `lip-berry`, `lip-mlbb`), blush 4(`blush-peach`, `blush-pink`, `blush-coral`, `blush-rose`), eyeshadow 4(`shadow-brown`, `shadow-peach`, `shadow-pink`, `shadow-smoky`). 각 `{ id, name(한국어), rgb: [r,g,b] 0…1 }`.
  - `looks` 5개: `daily`, `cool`, `warm-peach`, `rosy`, `smoky`. 각 `{ id, name, lip: {colorID, intensity}, blush: {…}, eyeshadow: {…}, brow: {intensity}, contour: {intensity} }`.
- **`MakeupCatalog(data:)`**: `LookCatalog`와 같은 패턴(`empty`, `look(id:)`, `color(id:)`), 디코드 오류는 앱에서 `UserMessage`로 매핑.
- **룩 적용:** `EditDocument.applyMakeupLook(_:)`이 룩의 부위 값을 `makeup`에 써 넣고 `lookID` 기록, 체크포인트 1회. 이후 부위 변경은 `lookID`를 nil로.
- **`MakeupStage`** (마스크는 `FaceRegions`):
  - lip: 바깥−안쪽 입술, 색을 `CISoftLightBlendMode` + 강도 혼합(입술 질감 유지).
  - blush: 볼 타원(눈 아래·코 옆·윤곽 안쪽), 넓은 경계, soft light.
  - eyeshadow: 눈 위 눈꺼풀~눈썹 사이 다각형에서 눈을 뺀 영역, multiply.
  - brow: 눈썹 다각형을 조금 넓혀 기존 눈썹 색으로 multiply.
  - contour: 광대 아래·턱선·코 옆 어둡게(multiply 회갈색), 콧대·이마 중앙·턱 끝 밝게(screen).
- **UI:** 메이크업 도구: 룩 칩 5개(+없음) 위, 부위 탭(립·블러셔·아이섀도·눈썹·쉐딩) 아래, 부위마다 색 칩 + 강도 슬라이더.
- **테스트:** 카탈로그 디코드·번들 사본 동일, 강도 0이면 입력과 같은 바이트, 립 색이 입술 마스크 안에서만 색상 변화, 룩 적용 후 부위 값 일치·실행 취소 1회.

### 7. 앱

- `EditorTool`: `look, auto(동작), crop, adjust, beauty, makeup, body, background, retouch, warp`. `portrait` 제거, 기존 인물 패널 내용은 `BeautyPanel`(하위 탭 피부/얼굴/눈·입)로 이동.
- `AppModel`: 분석 실패 안내(`personAnalysisFailure`, `bodyAnalysisFailure`), 메이크업 카탈로그 로드(룩 카탈로그와 같은 방식), `applyMakeupLook`.
- 자동 보정(`AutoEnhancer`): 얼굴이 있으면 `skin.smoothing 0.3`, `skin.autoBlemish true`, `features.eyeBrighten 0.2`. 기존 faceSlim 0.15는 제거(얼굴형은 사용자 선택).
- `UserMessage`: 도구 이름(뷰티·메이크업·체형·배경), 하위 탭 이름, 안내 문구(사람 없음, 전신 없음, 메이크업 목록을 읽지 못함).
- `Theme`: 양방향 슬라이더 스냅 폭, 메이크업 칩 크기.

### 8. 테스트·검증

- 단계마다 해당 모듈 테스트 + `RenderPipelineTests` 순서 배열 + 앱 `AppModelTests`(새 도구 전환, 분석 실패 안내, 룩 적용 실행 취소).
- 시나리오 테스트 `EditorScenarioTests`에 "피부 0.5 + 자동 잡티 → 얼굴 폭 −0.5 → 눈 또렷 0.5 → 배경 흐림 0.5 → 다리 0.5 → 메이크업 데일리 → 내보내기 성공" 추가(스텁 분석기).
- `./scripts/test-apple.sh` 전체 통과, lint, verify-modules, xcodegen diff.
- `VALIDATION.md`에 B~F 절: 자동 검증 수, 미검증(실사진 품질, 48MP 속도, 실기기, 직선 배경 휨).

### 9. 계획 분할

계획 문서 다섯 개, B → C → D → E → F 순서로 실행. 각 계획 첫 Task는 이전 단계 머지 상태에서 시작. 공통 기반(1.2 레시피 골격, 1.4 분석 포트, 1.5 이동량 지도)은 B 계획(레시피·분석 골격)과 C 계획(이동량 지도)에 넣음.

| 계획 | 파일 | 주요 Task |
|---|---|---|
| B | `docs/superpowers/plans/2026-10-15-beauty-b-skin.md` | 레시피 골격·마이그레이션, 분석 확장 골격, FaceRegions 피부 마스크, 주파수 분리, BlemishDetector, SkinStage 재작성, 뷰티 도구·피부 패널 |
| C | `docs/superpowers/plans/2026-10-15-beauty-c-face.md` | DisplacementWarp, FaceShapeRig, ShapeWarpStage(FaceReshapeStage 대체), 얼굴 패널 |
| D | `docs/superpowers/plans/2026-10-15-beauty-d-features.md` | Person 분석, FeatureStage, BackgroundStage, 눈·입 패널, 배경 도구 |
| E | `docs/superpowers/plans/2026-10-15-beauty-e-body.md` | Body 분석, BodyShapeRig, ShapeWarpStage 통합, 체형 도구 |
| F | `docs/superpowers/plans/2026-10-15-beauty-f-makeup.md` | 메이크업 데이터·카탈로그, MakeupStage, 룩 적용 규칙, 메이크업 도구, 자동 보정 확장, 문서·VALIDATION·1.2.0 노트 |
