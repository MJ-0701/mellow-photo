# 인물 보정 J (옷 주름 펴기) 설계

작성 2026-10-21. 선행: [인물 보정 G](2026-10-20-beauty-g-evoto-design.md)(몸 피부 단계), [인물 보정 H](2026-10-21-beauty-h-per-person-design.md). 근거: Evoto `remove-wrinkles-from-clothes` 전후 12쌍 실측과 Python 시제품(아래 에이전트 참조 3절). 기준 코드: **beauty-g5와 beauty-body(인물 보정 I)가 main에 병합된 뒤의 main**. 이 문서를 쓰는 시점의 main은 `8accbf6`이다. 2026-10-22에 beauty-body가 main(`8157172`)에 병합됐고 beauty-g5는 아직이다.

사용자 요구: Evoto의 "옷 주름 제거" 같은 의상 주름 제거. ML 모델 없이 Swift·Core Image·Vision만 쓴다.

## 사람이 확인할 것

### 결정

"사용자 결정"은 2026-10-21 질문 세 개에 대한 답이다. 나머지는 에이전트가 정한 것이고 바꿀 수 있다.

| 결정 | 이유 | 바꾸면 비용 |
|---|---|---|
| 줄이는 것은 **입은 옷의 부드러운 접힘 그늘**뿐이다. 휘도의 중간 대역(짧은 변의 약 0.12%~1.6% 크기)을 줄이고, 천 올·니트 같은 미세 질감과 몸의 큰 음영은 그대로 둔다. 색은 바꾸지 않는다 | Evoto 실측과 같은 성질이다. 바뀐 면적은 1~7%이고 σ 1.5~6px 대역이 0.6~0.8로 줄었으며 미세 질감과 큰 음영은 그대로였다. 그늘을 메우는 쪽이 주였다(바뀐 픽셀의 70~80%가 밝아짐) | 작음 |
| 그늘(어두운 쪽)은 강도 ×1.0, 밝은 접힘선은 ×0.7로 줄인다 | Evoto도 그늘을 올리는 양이 하이라이트를 내리는 양보다 크다. 양쪽을 같게 줄이면 반짝이는 천이 탁해진다 | 작음 (상수) |
| 옷 영역은 자동으로 잡는다. 사람 영역에서 피부를 빼고(얼굴마다 그 사람의 볼 색, 가까운 몸에만), 머리와 머리카락을 빼고(정수리 위 색, 머리에 이어진 곳만), 미세 질감이 센 곳은 약하게 건다 | ML 없이 옷을 직접 찾을 방법이 없어 빼기로 만든다. 시제품에서 사람 밖 변화 0, 피부 변화 평균 0.0001이었다 | 중간 |
| **부분 브러시도 넣는다.** 칠하기와 지우기 두 가지다. 칠한 곳이 하나라도 있으면 자동 영역 대신 칠한 곳에만 걸고, 지운 곳은 늘 뺀다 (사용자 결정) | Evoto의 "특정 부위에 마스크를 씌워 집중 보정"에 해당한다. 자동 영역이 놓친 옷(머리카락과 같은 색인 셔츠)이나 옷걸이 옷·배경 천을 사용자가 직접 고를 수 있다 | 중간 |
| 칠한 곳에서는 사람 영역 제한을 풀되 피부·머리·머리카락·질감 보호는 그대로 둔다 (에이전트 결정) | 걸린 옷과 배경 천을 고를 수 있어야 브러시의 뜻이 산다. 보호까지 풀면 칠이 얼굴에 닿을 때 바로 망가진다 | 작음 |
| 브러시 획은 사진에만 속한다. 프리셋·"전체 사진에 적용"은 강도 값만 나르고 획은 나르지 않는다. 얼굴형·체형 잠금도 걸지 않는다 | 획 좌표는 그 사진의 원본 좌표다. 옷 단계는 체형 변형보다 먼저 돌아 좌표가 어긋나지 않는다 | 작음 |
| 슬라이더 이름은 "옷 주름"(0~1, 기본 0)이고 **체형 패널**에 둔다. 원터치에는 넣지 않는다 (사용자 결정) | 몸·옷 보정끼리 묶는다. 원터치는 얼굴·피부 보정 묶음이라 옷은 사진마다 판단이 다르다 | 작음 |
| **구현은 beauty-g5와 beauty-body가 main에 병합된 뒤 시작한다.** 이 문서와 계획만 지금 쓴다 (사용자 결정) | 레시피·스키마·동기화·문구·파이프라인 순서·수용 테스트 파일이 두 브랜치와 모두 겹친다. 먼저 구현하면 같은 줄을 세 곳에서 고치게 된다 | 작음 |
| 새 렌더 단계 `clothing`을 `bodySkin` 바로 뒤에 둔다. 레시피에는 최상위 `clothing` 묶음을 더한다 | 저장소 규칙("새 효과는 렌더 단계와 레시피 확장으로만")을 따른다. 체형 변형·수동 편집보다 앞이라 원본 좌표를 쓴다 | 큼 (파일 형식) |
| 체형·얼굴형 변형이 걸린 사진에서는 칠한 자리가 화면에 보이는 옷과 조금(변형량만큼) 어긋난다. 그대로 받아들인다 (에이전트 결정) | 화면 좌표를 원본 좌표로 바꿀 때 자르기·회전만 되돌리고 변형은 되돌리지 않는다. 변형은 보통 몇 % 이내이고 옷 마스크는 가장자리가 흐린 넓은 영역이라 티가 작다. 되돌리려면 변형 필드를 렌더 API로 꺼내야 해 일이 커진다 | 중간 (역변형을 넣으면 렌더 API 확장) |
| 얼굴을 찾은 사람만 자동으로 처리한다. 얼굴이 없는 사람(뒷모습, 놓친 얼굴)은 브러시로만 처리한다 (에이전트 결정) | 피부·머리·머리카락 보호가 모두 얼굴에서 나온다. 얼굴 없는 사람에게 자동으로 걸면 맨살과 머리카락이 밋밋해진다. 사람마다 마스크를 나누는 데는 beauty-body의 `personInstances`를 쓴다 | 작음 |
| "옷 주름"은 사진 전체에 하나만 있다. 체형 패널에서 사람·성별 대상을 골라도 이 절은 그대로 보이고 "모든 사람에 적용"이라고 표시한다. 브러시 크기 슬라이더를 이 절에 함께 둔다 (에이전트 결정) | 사람별 강도는 범위 밖이다. 브러시 크기를 바꾸러 잡티 도구로 가야 하면 불편하다 | 작음 |
| 수용 테스트 임계값은 J1이 Swift로 잰 값에 여유를 두어 임시 상수로 넣는다. main 병합 전에 사용자가 승인한다 (에이전트 결정) | J1 작업을 승인 대기로 멈추지 않는다. 병합은 어차피 사용자에게 묻는다 | 작음 |

### 범위

| 묶음 | 들어가는 것 |
|---|---|
| J1 레시피·렌더 | `clothing` 레시피 묶음(강도, 획), 스키마·README, 범위·동기화·프리셋 규칙, `ClothingStage`(자동 옷 마스크 + 중간 대역 줄이기 + 획 마스크), 단위 테스트, 실사진 수용 테스트 |
| J2 화면·검증 | 체형 패널의 "옷 주름" 슬라이더, 칠하기·지우기·획 모두 지우기, 칠한 영역 겹쳐 보기, 획을 모으는 캔버스 제스처, 문구, VALIDATION |

### 범위 밖

- **깊은 구김을 없애는 것.** 고전 기법은 그늘을 옅게 할 뿐 접힌 형태를 지우지 못한다. Evoto도 "깊은 주름"은 사실상 다시 그린다.
- **무늬·체크·프린트 옷.** 무늬도 같은 대역에 있어 질감 보호가 막는다. 효과가 약하거나 없다.
- **옷걸이에 걸린 옷과 배경 천의 자동 처리.** 사람 영역 밖이라 자동으로는 건드리지 않는다. 브러시로 칠하면 된다.
- **배경 커튼·잡동사니 지우기.** Evoto 예시 둘(커튼을 통째로 없앰)은 생성형이다.
- 보풀 제거, 옷 색 바꾸기, 사람별 강도.

### 위험과 대응

- **머리카락과 같은 색인 옷은 덜 펴진다.** 예: 짧은 검은 머리 아래 짙은 셔츠는 목 그늘로 이어져 머리카락으로 잡힌다(저장소 단체 사진의 갈색 셔츠). 대응: 망가뜨리는 대신 빼는 쪽으로 틀리게 했다. 사용자는 브러시로 칠해 넣을 수 있다.
- **피부와 같은 색인 옷(베이지·살구색)은 일부가 빠진다.** 대응: 피부 판정을 그 사람의 볼 색과 밝기로 좁히고 가까운 몸에만 적용해 줄였다. 남는 경우는 브러시로 넣는다.
- **옷의 모양을 만드는 그늘(칼라·주머니·솔기 옆)도 조금 옅어진다.** 대응: 강한 경계는 가장자리 보존 필터가 지키고, 자연스러움 상한(중간 대역 0.45 아래로 내려가지 않음)을 수용 테스트로 건다.
- **Python 시제품의 수치가 Core Image 구현에서 그대로 나오지 않을 수 있다.** 대응: 수용 테스트 임계값은 J1 구현 때 Swift로 다시 재서 정한다. 시제품 수치는 목표일 뿐이다. 임계값은 사용자 승인 사항이다.
- **화면 품질은 자동 테스트로 판정할 수 없다.**

### 사용자 조치

- J1 수용 테스트 임계값(보이는 하한·자연스러움 상한) 승인.
- J2 뒤 실제 사진(셔츠·티셔츠·정장·니트·무늬 옷)으로 자동 결과와 브러시 조작감 확인. iOS 기기 확인은 CI 뒤에 사용자가 한다(로컬 시뮬레이터 실행 금지).

### 돈·시간·외부 효과가 있는 단계

- 각 계획 끝의 `gh workflow run apple-checks.yml --ref beauty-j-cloth`는 GitHub Actions 시간을 쓴다.
- main 병합·태그·TestFlight 업로드는 이 설계 범위가 아니다. 할 때마다 사용자에게 묻는다.

## 에이전트 참조

### 1. 선행 조건과 겹침

- 시작 조건은 beauty-g5와 beauty-body가 main에 병합된 것이다. 시작할 때 `git log main --oneline | head`로 확인한다. 그다음 `beauty-j-cloth` 브랜치(worktree `.claude/worktrees/beauty-j-cloth`)를 main 위로 다시 올린다(`git rebase main`).
- 아래 파일 위치와 줄 번호는 `8accbf6` 기준이다. 두 브랜치가 병합되면 바뀌므로 구현 전에 다시 찾는다. 특히 확인할 것은 다음과 같다.
  - `RenderPipeline.standard`: `8157172`에서 `skin, bodySkin, feature, makeup, background, chinShade, shapeWarp, localEdit, geometry, color, detail, look, effect`다(확인함).
  - `PortraitKey`: `8157172`에 `.bodyShape(BodyShapeKey)`가 있다(확인함).
  - `PhotoAnalysis`: `8157172`에 `personInstances: [CIImage]`와 `faceInstances: [Int: Int]`(얼굴 인덱스 → 인스턴스 인덱스)가 있다(확인함).
  - `RenderTuning`: 두 브랜치 모두 상수를 더한다.
- 옷 단계의 수용 테스트는 새 파일 `ClothingAcceptanceTests.swift`에 둔다. 기존 `RealPhotoAcceptanceTests.swift`는 두 브랜치가 크게 고치므로 건드리지 않는다.

### 2. 모듈 배치 (의존성 표 변경 없음)

| 새 타입·변경 | 모듈·폴더 | 설명 |
|---|---|---|
| `ClothingKey`(`wrinkles`), `ClothingStroke`, `ClothingAdjustments` | MellowShared/API (`ClothingAdjustments.swift`) | 강도와 획 |
| `EditRecipe.clothing`, `dependsOnPerson`, `allValuesFinite`, `PresetValues.clothing`(강도만) | MellowShared/API | 레시피 확장 |
| `AdjustmentRange.clothing(_:)` | MellowShared/API | 0…1 |
| `shared/recipe-schema/edit-recipe.v2.schema.json`, `README.md` | shared | `clothing` 절. schemaVersion은 2 그대로다 |
| `EditChange.clothing(ClothingKey, Double)`, `EditDocument.appendClothingStroke(_:)`, `clearClothingStrokes()`, `SyncCategory.body`가 `clothing.wrinkles`도 나름 | MellowEditing/API | 편집 규칙 |
| `EditingPolicy.clothingRange` | MellowEditing/API | 범위 전달 |
| `ClothingStage`, `ClothingMask`, `ClothingKernels` | MellowRendering/Domain | 렌더 |
| `RenderTuning`의 `clothing…` 상수 | MellowRendering/API | 매직 넘버 |
| `RenderPipeline.standard`에 `ClothingStage()`를 `BodySkinStage()` 바로 뒤에 | MellowRendering/API | 단계 순서 |
| 체형 패널 절, 브러시 모드, 캔버스 획 제스처, 겹쳐 보기, `UserMessage` 문구 | 앱 타깃 | 화면 |

### 3. 측정 근거 (스크래치, 저장소에 넣지 않음)

- Evoto 전후 12쌍은 `https://www.evoto.ai/ko/features/remove-wrinkles-from-clothes` 페이지 이미지다. 저작물이므로 저장소·테스트 고정 사진에 넣지 않는다.
- Evoto 쪽 실측 결과는 다음과 같다(바뀐 곳 = |G4(ΔY)| > 0.015).
  - 바뀐 면적은 1~7%다. 배경 천을 다룬 쌍은 27~70%다.
  - 대역 비(뒤/앞): σ1.5~3은 0.58~0.89, σ3~6은 0.57~0.93, σ6~12는 0.81~0.97, σ12~24는 0.92~1.0이다. 미세(σ<0.7)는 0.82~1.19다.
  - 색차 변화는 |ΔCb|, |ΔCr| < 0.007이다. 밝아진 픽셀은 69~83%다.
- 시제품 v8 설정:
  - σs = 0.0012·짧은 변, σL = 0.016·짧은 변
  - guided 반경 1.5σL, ε 0.02
  - 그늘 ×1.0, 밝은 쪽 ×0.7
  - 질감 게이트 0.025~0.06
- 시제품 v8 결과:
  - Evoto와의 ΔY 상관은 입은 무지 옷 쌍에서 0.3~0.42다.
  - 저장소 고정 사진(group-01, couple-01, demo-portrait, 강도 1)에서 옷 영역 중간 대역 비는 0.62~0.68이다. 미세 질감 비는 0.83~0.94다.
  - 평균 |ΔY|는 0.015~0.020이고 p99 |ΔY|는 0.078~0.098이다.
  - 사람 밖 최대 |ΔY|는 0이다. 피부 평균 |ΔY|는 0.0001, 머리 평균은 0.0001이다.

### 4. 레시피

```swift
/// 옷 슬라이더 이름. 레시피 JSON 키와 같다.
public enum ClothingKey: String, CaseIterable, Codable, Sendable {
    case wrinkles
}

/// 옷 주름 브러시 한 획. 원본 정규화 좌표(원점 왼쪽 아래)의 꺾은선과 반지름(짧은 변 비율).
/// erase면 칠한 곳·자동 영역에서 뺀다.
public struct ClothingStroke: Codable, Equatable, Sendable {
    public var points: [NormalizedPoint]
    public var radius: Double
    public var erase: Bool
}

/// wrinkles 0…1. strokes는 사진에만 속하고 프리셋·동기화가 나르지 않는다.
public struct ClothingAdjustments: Codable, Equatable, Sendable {
    public var wrinkles: Double
    public var strokes: [ClothingStroke]
    public var hasEffect: Bool { wrinkles != 0 }
    public var hasPaint: Bool { strokes.contains { !$0.erase } }
    public var numericValues: [Double]  // wrinkles, 획마다 radius와 점 좌표
}
```

- `NormalizedPoint`는 `MellowShared/API/Geometry.swift`에 이미 있다(Codable, x·y Double).
- 디코딩은 키가 없으면 `wrinkles` 0, `strokes` []다. v1 세션·옛 v2 레시피가 그대로 열린다.
- 획 하나의 점은 최대 `EditingPolicy.clothingStrokeMaxPoints`(256)개다. 넘으면 앱이 균등하게 솎는다. 획 수 상한은 `clothingMaxStrokes`(64)이고 넘으면 가장 오래된 획부터 버리지 않고 추가를 거절한다(상태 문구).
- 반지름은 `brushRadius`(앱 `Policy.brushRadiusRange` 0.008…0.07)를 그대로 쓴다.
- `EditRecipe.dependsOnPerson`은 `… || clothing.hasEffect`가 된다. 획만 있고 강도가 0이면 효과가 없다.
- `allValuesFinite`는 `clothing.numericValues`를 더한다(타입 검사 시간 때문에 묶음마다 `+=`로 붙인다).
- 프리셋 `PresetValues`는 `wrinkles`만 담는다. 동기화 `.body`는 `wrinkles`만 복사하고 받는 사진의 획은 그대로 둔다.
- 스키마 `clothing` 절:

```json
"clothing": {
  "type": "object", "additionalProperties": false,
  "properties": {
    "wrinkles": { "type": "number", "minimum": 0, "maximum": 1, "default": 0 },
    "strokes": { "type": "array", "default": [], "maxItems": 64, "items": {
      "type": "object", "additionalProperties": false, "required": ["points", "radius", "erase"],
      "properties": {
        "points": { "type": "array", "minItems": 1, "maxItems": 256, "items": {
          "type": "object", "additionalProperties": false, "required": ["x", "y"],
          "properties": { "x": { "type": "number", "minimum": 0, "maximum": 1 }, "y": { "type": "number", "minimum": 0, "maximum": 1 } } } },
        "radius": { "type": "number", "exclusiveMinimum": 0, "maximum": 0.2 },
        "erase": { "type": "boolean" } } } }
  }
}
```

### 5. 렌더 단계 `ClothingStage` (name `"clothing"`)

`recipe.clothing.wrinkles == 0`이면 입력을 그대로 돌려준다. 아래 크기는 모두 짧은 변 `S`의 비율이다.

1. **휘도 분리.** BT.601 휘도 Y만 다룬다. 결과는 세 채널에 같은 ΔY를 더해 색차를 지킨다(감마 인코딩 공간에서 계산한다). 단계 입력은 선형이므로 `BodySkinStage`처럼 `CILinearToSRGBToneCurve`로 인코딩해 계산하고 `CISRGBToneCurveToLinear`로 되돌린다.
2. **중간 대역.** `Ys = Gauss(Y, σs)`, `σs = max(clothingFineSigmaMinimum 0.8px, clothingFineSigma 0.0012·S)`. `base = guided(Ys, 가이드 Ys, r = clothingGuidedRadius 1.5 × clothingCoarseSigma 0.016·S, ε = clothingGuidedEpsilon 0.02)`. `bp = Ys − base`.
   - guided 필터는 상자 평균으로 만든다. `mean_I = Box(I,r)`, `var_I = Box(I²,r) − mean_I²`, `a = var_I/(var_I+ε)`, `b = mean_I − a·mean_I`, `q = Box(a,r)·I + Box(b,r)`. 상자는 `CIBoxBlur`, 나머지는 색 커널이다.
   - `CIGuidedFilter`는 업샘플링용이라 같은 크기에서 위 정의와 같은 값을 주는지 확인하기 전에는 쓰지 않는다.
3. **질감 게이트.** `fine = Y − Ys`. `fe = sqrt(Gauss(fine², 3σs))`. `tex = 1 − smoothstep(clothingTextureLow 0.025, clothingTextureHigh 0.06, fe)`.
4. **옷 마스크 M**(아래 6절). 가중치 `w = M × tex × wrinkles`.
5. **적용.** `ΔY = −w × (bp < 0 ? clothingShadowGain 1.0 : clothingHighlightGain 0.7) × bp`. 출력 RGB = 입력 RGB + ΔY이고 자르지 않는다. 확장 범위(1 초과) 픽셀이 마스크 밖에서 잘리면 안 된다. 커널 하나(`ClothingKernels.flatten`)로 한다.
6. 출력 extent는 입력과 같다. `wrinkles`가 0이 아니고 얼굴·사람 마스크·획이 모두 없으면 입력을 그대로 돌려준다.

### 6. 옷 마스크 `ClothingMask`

저해상도(긴 변 `clothingMaskMaxDimension` 512)에서 만들고 늘려 쓴다.

- **색에 기대는 부분(K·R)은 캐시하지 않는다.** 이 단계의 입력(앞 단계의 피부 보정이 반영된 이미지)에서 매번 Core Image 그래프로 계산한다. CPU로 읽어 오지 않는다. 미리보기와 내보내기가 각자 같은 입력에서 같은 식으로 계산하므로 서로 맞는다.
- **획 비트맵만 `RenderContext.regionMasks`에 캐시한다.** 키는 extent, 비트맵 크기, 획 값이다. `RegionMaskCache.capacity`의 주석과 상한 계산에 사진당 2개(칠하기·지우기)를 더한다.
- 시간 예산: 옷 강도 1일 때 미리보기 렌더 시간 증가를 기존 대비 +30% 이내로 잡는다. J1은 `ClothingStageTests`에서 2048px 합성 이미지 렌더 시간을 `record`로 남기기만 하고 실패시키지 않는다. 넘으면 중간 대역과 guided 필터를 절반 해상도에서 계산해 늘린다.
- **사람 코어** `P = smoothstep(clothingPersonLow 0.6, clothingPersonHigh 0.95, Gauss(personMask, 1.5px@512))`. `BackgroundStage.personMask`로 늘린 마스크를 쓴다. 사람 마스크가 없으면 자동 영역은 0이다(획만 동작).
- **얼굴 있는 사람만.** `analysis.personInstances`가 비어 있지 않으면 `analysis.faceInstances`의 값(얼굴이 배정된 인스턴스)만 모아 합집합을 P에 곱한다. 인스턴스가 배정되지 않은 얼굴의 사람은 자동으로 처리하지 않는다. 인스턴스가 없으면(분석 실패·구형 OS) 사람 마스크 전체를 쓰되, 얼굴이 하나도 없으면 자동 영역은 0이다.
- **피부 K** = 얼굴마다 `K_f`를 구해 최댓값을 쓴다.
  - 기준색: `FaceRegions.cheekAverages`의 볼 평균색(Cb·Cr·Y).
  - 색 거리: `d² = ((Cb−Cb_f)/σc)² + ((Cr−Cr_f)/σc)² + (ln((Y+0.02)/(Y_f+0.02))/clothingSkinLumaSigma 0.28)²`. `σc = clothingSkinChromaSigma`는 8비트 기준 4.5다. 시제품 값은 MAD×1.8, 바닥 2.5였다. 볼 평균만 쓰므로 고정값을 쓴다. 구현 때 다시 잰다.
  - 공간 감쇠: `sp = exp(−½((Δx/(2.2·fw))² + (max(Δy_down,0)/(5·fh))²))`. fw·fh는 얼굴 상자 폭·높이, Δy_down은 얼굴 중심 아래쪽 거리다.
  - `K_f = exp(−½d²)·sp`. 합친 K에 `Gauss(2px@512)`를 건 뒤 `smoothstep(0.25, 0.6)`을 적용한다.
- **머리 H** = 얼굴마다 타원을 그린다.
  - 중심은 얼굴 중심에서 위로 0.25fh, 반지름은 (1.25fw, 1.6fh)다.
  - 경계 `1 − smoothstep(0.8, 1.2, e)`, e는 정규화 거리 제곱이다.
  - `FaceRegions.wholeFaceMask`가 이보다 넓으면 그것과 최댓값을 쓴다.
- **머리카락 R** = 얼굴마다 구한다.
  - 기준색: 얼굴 상자 위 띠(폭은 상자 가운데 60%, 높이는 상자 위 0.02~0.35fh)의 평균색을 `CIAreaAverage`로 구한다.
  - 색 거리: Y·Cb·Cr 거리, 시그마 (`clothingHairLumaSigma` 0.08, `clothingHairChromaSigma` 6.0).
  - 공간 감쇠: 옆 1.6fw, 아래 3.5fh다.
  - **머리에 이어진 곳만** 남긴다. 저해상도(긴 변 128)에서 측지 재구성을 `clothingHairGrowSteps` 24회 반복한다.
    - 씨앗은 머리 타원이다.
    - 한 번에 `CIMorphologyMaximum` 반지름 1px로 넓히고, 머리카락 색 마스크(>0.35)와 `CIMinimumCompositing`으로 자른다.
  - 결과 R = 색 가중 × 이어진 영역이다. `Gauss(2px@512)`를 건 뒤 `smoothstep(0.2, 0.5)`을 적용한다.
- **자동 영역** `A = P × (1−K) × (1−H) × (1−R)`.
- **획.**
  - 칠한 획: 반지름 r의 둥근 끝 꺾은선을 `CGContext`로 그린다(`FaceRegions.polygonMask`처럼 회색 비트맵). 가장자리는 r의 30%로 흐린다.
  - `Paint`는 칠한 획의 합집합, `Erase`는 지우기 획의 합집합이다.
  - `hasPaint`면 `region = Paint × (1−K) × (1−H) × (1−R)`이고, 아니면 `region = A`다.
  - `M = region × (1 − Erase)`.
- 마스크 테스트를 위해 `ClothingMask.make(...)`는 internal이고 `@testable import`로 부른다.

### 7. 상수 (`RenderTuning`, "옷" 절)

`clothingFineSigma 0.0012`, `clothingFineSigmaMinimum 0.8`, `clothingCoarseSigma 0.016`, `clothingGuidedRadius 1.5`, `clothingGuidedEpsilon 0.02`, `clothingShadowGain 1.0`, `clothingHighlightGain 0.7`, `clothingTextureLow 0.025`, `clothingTextureHigh 0.06`, `clothingMaskMaxDimension 512`, `clothingPersonLow 0.6`, `clothingPersonHigh 0.95`, `clothingSkinChromaSigma 4.5`, `clothingSkinLumaSigma 0.28`, `clothingSkinSpreadWidth 2.2`, `clothingSkinSpreadHeight 5.0`, `clothingHeadWidth 1.25`, `clothingHeadHeight 1.6`, `clothingHeadLift 0.25`, `clothingHairLumaSigma 0.08`, `clothingHairChromaSigma 6.0`, `clothingHairSpreadWidth 1.6`, `clothingHairSpreadHeight 3.5`, `clothingHairGrowSteps 24`, `clothingHairGrowDimension 128`, `clothingStrokeFeather 0.3`.

각 상수에 한 줄 문서 주석을 단다. 문서 주석에는 무엇을 재는지와 단위를 쓴다(짧은 변 비율, 8비트, 0…1).

### 8. 화면 (J2)

- 체형 패널(`BodyPanel.swift`) 아래에 "옷" 절을 둔다. 순서는 다음과 같다.
  - `ForEach(ClothingKey.allCases)` 슬라이더: 제목 `UserMessage.clothingTitle(key)` = "옷 주름", 범위 `EditingPolicy.clothingRange`.
  - 브러시 줄: "칠하기"·"지우기" 토글(하나만 켜짐, 다시 누르면 꺼짐), "브러시 모두 지우기" 버튼(획이 있을 때만).
  - 브러시 크기 슬라이더: `brushRadius`와 `Policy.brushRadiusRange`를 그대로 쓴다(잡티 도구의 크기와 같은 값).
  - 대상 칩(beauty-body)이 사람·성별을 가리켜도 이 절은 보이고 제목 옆에 `UserMessage.clothingAppliesToAll`("모든 사람에 적용")을 붙인다. 사용 가능 여부는 체형 관절점이 아니라 사람 마스크·얼굴 유무로 정한다(`AppModel.canAdjustClothing`). 둘 다 없어도 브러시는 쓸 수 있다.
  - 안내 문구 `UserMessage.clothingHint`: "칠한 곳이 있으면 그곳에만 적용돼요."
- 브러시 모드는 앱 상태 `AppModel.clothingBrush: ClothingBrushMode?`(`.paint`·`.erase`)다. 체형 도구를 벗어나면 nil이 된다.
- 브러시 모드에서는 캔버스가 드래그 경로를 모은다(`DragGesture.onChanged`의 위치 목록). 끝날 때 `model.paintClothing(path: [NormalizedPoint])`를 부른다.
  - 출력 좌표를 원본 좌표로 바꾸는 것은 `touch(from:to:)`와 같은 `outputTransform.toOriginal`이다. 변환을 모르는데 기하가 있으면 거절한다.
  - 점 수는 256개 이하로 솎는다.
  - 반지름은 `brushRadius`다.
  - `document.appendClothingStroke`(체크포인트 하나, 실행 취소 한 번에 획 하나)를 부른다.
  - 체형 도구의 기존 터치(현재 `return`)는 브러시 모드가 아닐 때 그대로 둔다.
- 브러시 모드이거나 획이 있으면 칠한 곳을 반투명(칠하기 파랑, 지우기 빨강, 불투명도 0.35)으로 캔버스 위에 그린다. 원본 → 출력 변환으로 위치를 맞춘다. 자동 영역 미리보기는 J2 범위 밖이다.
- 문구는 모두 `UserMessage`에 둔다. 새 앱 파일을 만들면 `xcodegen generate` 결과를 함께 커밋한다(`test-apple.sh`가 차이를 검사한다).

### 9. 테스트

단위 테스트:

| 파일 | 내용 |
|---|---|
| `MellowSharedTests/EditRecipeCodingTests.swift` | `clothing` 왕복, 키 없을 때 기본값, 비유한수 검사 목록에 `clothing`, 범위, 프리셋이 획을 버림 |
| `MellowSharedTests/RecipeSchemaTests.swift` | 절 목록에 `clothing`, 스키마 속성 = 인코딩 키 |
| `MellowLibraryTests/SessionFileMigrationTests.swift` | v1 픽스처가 `clothing` 기본값으로 열림(이미 통과해야 함, 단정만 추가) |
| `MellowEditingTests/EditDocumentTests.swift` | `.clothing(.wrinkles, x)` 적용, `appendClothingStroke` 실행 취소 한 번, `clearClothingStrokes`, 획 상한 거절, 동기화 `.body`가 강도만 나름, 획이 있어도 얼굴형·체형 변경이 잠기지 않음 |
| `MellowRenderingTests/ClothingStageTests.swift` | 이름 `"clothing"`, 강도 0이면 동일, 합성 천(무지 바탕 + 사인파 접힘 + 1px 결) 위에서 접힘 진폭이 줄고 결 진폭은 남음, 사람 마스크 밖 불변, 칠한 획 밖 불변, 지운 획 안 불변, 결정적 |
| `MellowRenderingTests/RenderPipelineTests.swift` | 단계 이름 배열에 `"clothing"`(`"bodySkin"` 다음) |
| 앱 `AppModelTests` | 브러시 모드에서 경로 → 획 하나, 기하 변환 적용, 체형 도구 이탈 시 모드 해제 |

실사진 수용 테스트 `MellowRenderingTests/ClothingAcceptanceTests.swift`:

- 사진은 `Fixtures/people/group-01.jpg`, `Fixtures/people/couple-01.jpg`, `Fixtures/demo-portrait.png`다. 실제 Vision 분석을 쓴다. 고정 사진 로더는 `RenderingTestSupport`의 기존 방식을 따른다. `people/`를 읽는 도우미가 없으면 그 파일에 더한다.
- 측정 영역 C는 `ClothingMask.make` > 0.5인 곳(강도 1, 획 없음)이다. 사진마다 C가 짧은 변² 기준 2% 이상이어야 측정한다.
- 보이는 하한:
  - C 안 중간 대역 비(뒤/앞, `Gauss(σs) − Gauss(σL)`의 RMS) ≤ `Visibility.clothingMidBandRatio`. 목표 0.80, 시제품은 0.62~0.68이었다.
  - C 안 평균 |ΔY|(8비트) ≥ `Visibility.clothingMeanAbsLuma`. 목표 2.0, 시제품은 3.8~5.1이었다.
- 자연스러움 상한:
  - 미세 질감 비(`Y − Gauss(σs)`의 RMS 비) ≥ `Naturalness.clothingFineRatio`. 목표 0.80, 시제품은 0.83~0.94였다.
  - 중간 대역 비 ≥ `Naturalness.clothingMidBandFloor`. 목표 0.45로, 다 지워 밋밋하게 만들지 않는다.
  - p99 |ΔY|(8비트) ≤ `Naturalness.clothingP99Luma`. 목표 30, 시제품은 20~25였다.
  - C 안 평균 ΔY(부호 있음) ≤ `Naturalness.clothingMeanLift`. 목표 6.4(8비트)다.
- 옷 밖 불변: 사람 마스크 < 0.05(3px 침식)인 곳의 최대 |ΔRGB| ≤ 1(8비트).
- 피부 불변:
  - `FaceRegions.skinMask`(얼굴마다)와 몸 피부 영역(`BodySkinStage`와 같은 인물 × 볼 색 가중 > 0.6)에서 평균 |ΔY| ≤ 0.5(8비트)여야 한다.
  - p99는 ≤ 3이어야 한다.
- 머리카락 불변: 머리 타원 H > 0.6에서 평균 |ΔY| ≤ 0.5다.
- 브러시:
  - group-01 배경 벽에 칠한 획 하나를 둔다. 그 획 밖은 불변이고 획 안 C는 측정만 한다(벽은 주름이 없어 하한을 걸지 않음).
  - 파란 스웨터를 덮는 지우기 획 안의 최대 |ΔRGB|는 ≤ 1이어야 한다.
- 모든 값은 `record(item, metric, value)`로 출력해 VALIDATION에 옮긴다. 목표값은 J1 구현 때 Swift 측정으로 다시 정한다. 정한 값은 사용자 승인 뒤 상수로 박는다.

### 10. 계획 나누기

- J1 `docs/superpowers/plans/2026-10-21-beauty-j1-clothing-recipe-render.md`: 4~7절, 9절 중 레시피·편집·렌더·수용 테스트.
- J2 `docs/superpowers/plans/2026-10-21-beauty-j2-clothing-brush-ui.md`: 8절, 9절 중 앱 테스트, VALIDATION, `docs/architecture/modules.md` 캔버스 갱신.
- 계획마다 끝은 다음 순서다.
  1. `export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer && ./scripts/test-apple.sh`(로컬은 iOS 시뮬레이터 테스트 없이)
  2. 푸시
  3. `gh workflow run apple-checks.yml --ref beauty-j-cloth`로 CI가 초록인지 확인
- CI는 Xcode 26.3이다. 긴 `+` 사슬은 나누고 CGFloat·Double을 섞지 않는다.
- 커밋은 한국어 Conventional Commits다. 로컬 iOS 시뮬레이터 실행은 금지이고 generic iOS Simulator 빌드만 허용한다.
