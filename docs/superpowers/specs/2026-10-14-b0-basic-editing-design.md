# B0 기본 편집 세트 설계

작성일 2026-10-14. 기준 커밋 `7c3c3e5`(하위 프로젝트 A 머지 직후). 설계 Claude Fable 5.1, 구현 Claude Opus 5.5.

## 1. 배경과 목표

A(구조 리팩토링)가 끝난 뒤 실사용자 피드백은 "기능이 하나도 없다"였다. 현재 앱은 색감 슬라이더 4개, 분위기 프리셋 3개, 피부 정돈, 얼굴 미세 조정, 수동 잡티·변형뿐이다. SNOW·메이투·스냅시드 같은 일반 사용자 기준의 "기본 편집"이 빠져 있다.

B0의 목표는 비전문가가 **사진 한 장을 열어 30초 안에 필터를 고르고, 자동 보정을 누르고, 자르고, 저장**할 수 있게 하는 것이다. 느낌은 SNOW식 원탭이다. 필터 칩과 자동 보정 버튼이 전면에, 세부 슬라이더는 조정 패널 뒤에 둔다.

사용 형태: 정식 출시가 아니라 **TestFlight 내부 테스터 두 명**이 쓴다. 저장소 변수 `IOS_AUTO_SUBMIT`·`IOS_AUTO_RELEASE`는 이미 `false`다.

### 결정 기록

| 질문 | 결정 |
|---|---|
| 느낌 | SNOW·메이투식 원탭. 필터 칩 + 자동 보정 버튼이 기본 화면, 슬라이더는 조정 패널. |
| 자동 보정 | "인물 전체 예쁘게": 노출·하이라이트·그림자·따뜻함·채도 자동 + 얼굴이 있으면 피부 정돈 0.3, 얼굴 미세 조정 0.15. 플래그가 아니라 슬라이더 값을 써 넣는다. |
| 자르기 | 비율 프리셋(원본·1:1·4:5·3:4·9:16) + 자유 드래그 + 90° 회전 + 좌우 반전 + 수평 슬라이더 ±15°. |
| 필터와 프리셋 | 분리 유지. 필터(룩)는 사진별, 분위기 프리셋은 슬라이더 값. |
| 필터 정의 | Apple 필터 이름이 아니라 파라미터 데이터(`shared/looks/`). Android·Windows가 같은 JSON을 읽는다. LUT 전환 경로는 `look.id` 계약으로 열어 둔다. |
| 기하 적용 위치 | 파이프라인 맨 마지막. 얼굴·수동 편집 좌표는 원본 기준 유지. |

## 2. 레시피 확장 (schemaVersion 2 유지)

`EditRecipe`에 세 하위 구조를 추가한다. 모두 기본값이 있어 A에서 저장한 파일과 출시본 v1 마이그레이션 결과가 그대로 읽힌다. `schemaVersion`은 2를 유지한다(추가 전용 변경).

```json
{
  "schemaVersion": 2,
  "color":    { "exposure": 0, "contrast": 1, "saturation": 1, "warmth": 0 },
  "portrait": { "skinSmoothing": 0, "faceSlim": 0, "targetFace": null },
  "detail":   { "highlights": 0, "shadows": 0, "sharpness": 0, "vignette": 0 },
  "look":     { "id": null, "intensity": 1.0 },
  "geometry": { "flipHorizontal": false, "quarterTurns": 0, "straightenDegrees": 0, "crop": null },
  "operations": []
}
```

| 필드 | 범위 | 의미 |
|---|---|---|
| `detail.highlights` | −1…1 | 음수면 밝은 영역을 눌러 디테일 복원, 양수면 밝힘 |
| `detail.shadows` | −1…1 | 양수면 어두운 영역을 밝힘 |
| `detail.sharpness` | 0…1 | 휘도 선명도 |
| `detail.vignette` | 0…1 | 가장자리 어둡게 |
| `look.id` | 룩 카탈로그 id 또는 null | 필터. 모르는 id는 디코드 성공·렌더 시 무시(항등) |
| `look.intensity` | 0…1 | 원본과 룩 결과의 혼합 비율 |
| `geometry.flipHorizontal` | bool | 좌우 반전 |
| `geometry.quarterTurns` | 0…3 | 시계 방향 90° 회전 횟수 |
| `geometry.straightenDegrees` | −15…15 | 수평 보정 각도(양수 = 시계 방향) |
| `geometry.crop` | 정규화 사각형 또는 null | 반전·회전·수평 보정이 끝난 이미지 기준. null이면 전체 |

`EditRecipe.isDefault`·`hasEdits`는 새 필드를 포함한다. `allValuesFinite`도 새 수치를 검사한다. `PresetValues`에 `detail`을 추가한다(`look`·`geometry`는 넣지 않는다). `detail`이 없는 구 프리셋은 기본값으로 디코드된다.

스키마: `shared/recipe-schema/edit-recipe.v2.schema.json`에 세 속성을 추가하고, `RecipeSchemaTests`가 `detail`·`look`·`geometry`·`geometry.crop` 키까지 대조한다. `session-file.v2.schema.json`의 preset `values`에 `detail`을 추가한다.

## 3. 룩 데이터

`shared/looks/looks.v1.json`이 룩 10종을 정의한다. 앱 번들에 같은 파일을 복사하고(`apple/MellowPhoto/Resources/looks.v1.json`), MellowShared 테스트가 두 파일이 바이트 동일한지 확인한다.

```json
{
  "schemaVersion": 1,
  "looks": [
    {
      "id": "clear",
      "name": "맑음",
      "toneCurve": [[0, 0], [0.25, 0.23], [0.5, 0.52], [0.75, 0.78], [1, 1]],
      "saturation": 1.05,
      "contrast": 1.03,
      "warmth": -0.05,
      "tint": 0,
      "vignette": 0,
      "fade": 0
    }
  ]
}
```

| 룩 id | 이름 | 성격 |
|---|---|---|
| `clear` | 맑음 | 약간 차갑고 선명 |
| `film` | 필름 | 콘트라스트 S자 커브, 페이드 약간, 따뜻함 |
| `cozy` | 포근 | 따뜻함 +, 채도 약간 ↓ |
| `calm` | 차분 | 차가움, 대비 ↓ |
| `mono` | 모노 | 채도 0, 커브로 대비 |
| `sepia` | 세피아 | 채도 0.2 + 따뜻한 틴트 |
| `vintage` | 빈티지 | 페이드 강, 비네팅, 채도 ↓ |
| `vivid` | 선명 | 채도·대비 ↑ |
| `pastel` | 파스텔 | 밝기 ↑, 대비 ↓, 채도 ↓ |
| `night` | 밤 | 어둡고 차가움, 비네팅 |

룩 필드: `toneCurve`(휘도 점 5개, x 오름차순, 0…1), `saturation`(0…2), `contrast`(0.5…1.5), `warmth`(−1…1, 색감 단계와 같은 켈빈 환산), `tint`(−1…1), `vignette`(0…1), `fade`(0…1, 블랙 리프트 = 커브 시작점을 `fade * 0.15`만큼 올림). 정확한 수치는 구현 단계에서 데모 인물 사진으로 보며 정하되, 각 룩은 "강도 1에서 원본과 눈에 띄게 다르고 피부가 깨지지 않는" 것을 기준으로 한다.

MellowShared에 `Look`(Codable)과 `LookCatalog`(`init(data:)`, `look(id:)`, `all`)을 둔다. 카탈로그 로딩은 앱이 번들에서 한 번 하고 `AppModel`이 보관한다. 모르는 id는 `look(id:)`가 nil을 돌려주고 렌더는 항등이다.

## 4. 파이프라인

`RenderPipeline.standard`를 7단계로 확장한다. 이름은 `"skin"`, `"faceReshape"`, `"localEdit"`, `"color"`, `"detail"`, `"look"`, `"geometry"`.

- **DetailStage**: `CIHighlightShadowAdjust`(highlightAmount = 1 + highlights, shadowAmount = shadows), `CISharpenLuminance`(sharpness × `RenderTuning.sharpnessMax`), `CIVignette`(intensity = vignette × `RenderTuning.vignetteMax`, radius는 짧은 변 비례). 값이 전부 0이면 항등.
- **LookStage**: 룩 파라미터를 `CIToneCurve` → `CIColorControls`(saturation·contrast) → `CITemperatureAndTint`(warmth·tint) → `CIVignette`로 조립한 뒤, `CIMix`(또는 `CIDissolveTransition`)로 원본과 `intensity` 비율로 섞는다. id가 없거나 모르면 항등. `RenderContext`에 `lookCatalog`를 추가한다.
- **GeometryStage**: 순서는 좌우 반전 → 90° 회전 → 수평 보정 → 자르기. 수평 보정은 중심 기준 회전 뒤 빈 모서리가 생기지 않는 최소 배율로 확대하고 원래 크기로 자른다(배율 = `cos|θ| + sin|θ| × max(w/h, h/w)`). 자르기는 그 결과 이미지 기준 정규화 사각형을 픽셀로 바꿔 자른다. 결과 extent는 원점 0으로 평행 이동한다.

`RenderPipeline.render`는 마지막에 `context.extent`로 자르던 것을 **기하 단계가 돌려준 extent**로 바꾼다. 기하 단계 이전 단계는 지금처럼 원본 extent를 유지한다. 모든 새 상수는 `RenderTuning`에 둔다.

`PhotoPipeline.preview`·`renderOriginal`은 바뀐 extent를 그대로 돌려준다. `PreparedPhoto.pixelSize`는 원본 크기 그대로이고, 내보내기 파일은 자른 크기다. 썸네일은 자르기 전 이미지다.

### 좌표 변환

MellowShared에 순수 수학 `GeometryTransform`을 둔다.

```swift
public struct GeometryTransform: Sendable {
    public init(geometry: GeometryAdjustments, sourceAspect: Double)   // 원본 가로/세로
    public var outputAspect: Double
    public func toOriginal(_ point: NormalizedPoint) -> NormalizedPoint   // 출력(자른 화면) 좌표 → 원본 좌표
    public func toOutput(_ point: NormalizedPoint) -> NormalizedPoint?    // 원본 좌표 → 출력 좌표, 자른 영역 밖이면 nil
}
```

반전·회전·수평 보정·자르기를 전부 포함하며, 원점은 왼쪽 아래다. 캔버스는 자르기 도구 밖에서 자른 결과를 보여주므로 잡티·변형 탭은 `toOriginal`로 원본 좌표를 얻어 레시피에 기록한다. 복제 샘플 마커는 `toOutput`으로 그린다. 자르기 도구 안에서는 캔버스가 자르기 전(반전·회전·수평 보정만 적용된) 이미지를 보여주며 탭 도구는 비활성이다.

## 5. 자동 보정

MellowRendering에 `AutoEnhancer`를 둔다. 입력은 미리보기 `CIImage`와 얼굴 유무, 출력은 `AutoEnhanceSuggestion { color, detail, portrait }`.

- 휘도 히스토그램(`CIAreaHistogram`, 64구간)에서 평균 휘도 L̄, 1·99 백분위 L₁·L₉₉를 구한다.
- 노출: `exposure = clamp(log2(target / L̄), −1, 1)`, target = `RenderTuning.autoTargetLuminance`(0.45).
- 하이라이트: L₉₉가 0.97 이상이면 `highlights = −min(1, (L₉₉ − 0.9) × 5)`, 아니면 0. 그림자: L₁이 0.03 이하면 `shadows = min(1, (0.1 − L₁) × 5)`, 아니면 0.
- 따뜻함: `CIAreaAverage`의 평균 RGB에서 그레이 월드 편차 `(r − b) / (r + b)`를 −1…1로 스케일한 값의 음수 × `RenderTuning.autoWarmthGain`(0.5)로 중성화(클램프 −0.3…0.3).
- 채도: `saturation = 1.08`. 대비: `1.04`.
- 얼굴이 하나 이상이면 `portrait.skinSmoothing = 0.3`, `faceSlim = 0.15`, `targetFace`는 유지(nil).
- 모든 값은 UI 범위로 클램프한다. 입력이 단색처럼 분산이 없으면 노출만 조정한다.

적용은 `EditDocument.applyAuto(_ suggestion:)`: 체크포인트 한 번, `color`·`detail`·`portrait` 값을 덮어쓰되 잠긴 사진의 `faceSlim`·`targetFace`는 보존한다(프리셋과 같은 규칙). `look`·`geometry`·`operations`는 건드리지 않는다. `AppModel.autoEnhance()`가 파이프라인에서 제안을 받아 적용하고 렌더를 예약한다. 상태 문구는 "자동 보정을 적용했어요. ⌘Z로 되돌릴 수 있어요." 자동 보정 버튼은 토글이 아니라 "적용" 동작이며, 되돌리기는 실행 취소다.

## 6. 화면

`EditorTool`을 `look, auto(버튼, 도구 아님), crop, adjust, portrait, retouch, warp`로 재구성한다. `auto`는 `EditorTool` 케이스가 아니라 도구 줄의 버튼이다. 기존 `.color`는 `.adjust`로 이름을 바꾼다.

- **도구 줄**(compact 하단, regular 인스펙터 상단): 가로 스크롤 아이콘+라벨 버튼. 순서 필터 · 자동 · 자르기 · 조정 · 인물 · 잡티 · 변형. 세그먼트 피커 폐기.
- **필터 패널**: 룩 썸네일 칩(선택 사진 썸네일에 룩을 입힌 작은 이미지, `AppModel`이 사진별·룩별 캐시, 원본 칩이 맨 앞) + 강도 슬라이더(룩이 선택된 때만). 칩 탭 = `edit(.look(id))`, 같은 칩 다시 탭 = 해제.
- **자르기 패널**: 캔버스가 자르기 전 이미지를 보여주고 그 위에 `CropOverlay`(모서리·변 손잡이 8개, 드래그로 사각형 이동·크기 변경, 비율 고정 시 비율 유지). 비율 칩(원본·1:1·4:5·3:4·9:16), 90° 회전 버튼, 좌우 반전 버튼, 수평 슬라이더(−15…15). 조작마다 레시피에 반영하되 손잡이 드래그는 `beginSliderEdit`/`endSliderEdit`처럼 연속 변경으로 묶어 체크포인트 한 번. "초기화"는 geometry만 기본값으로.
- **조정 패널**: 분위기 프리셋 줄(기존) + 노출·대비·채도·따뜻함 + 하이라이트·그림자·선명도·비네팅. 프리셋 저장은 `detail`을 포함한다.
- 인물·잡티·변형 패널은 그대로.
- `EditChange`에 `highlights, shadows, sharpness, vignette, lookID(String?), lookIntensity, flipHorizontal(Bool), quarterTurns(Int), straightenDegrees, crop(NormalizedRect?)`를 추가한다. 잠금 규칙은 기존대로 `faceSlim`·`targetFace`만 해당한다.
- 캔버스 표시 모드: `AppModel.canvasShowsUncropped`는 `tool == .crop`일 때 true. 이때 `PhotoPipeline.preview`는 기하 단계에서 자르기만 건너뛴 결과를 돌려준다(`RenderContext.skipsCrop`).

## 7. 오류 처리

새 오류 케이스는 없다. 룩 카탈로그를 번들에서 읽지 못하면 `AppModel.live()`가 `present`로 알리고 필터 패널은 비어 있다(앱은 계속 동작). 모르는 `look.id`는 조용히 항등. 자동 보정 분석 실패(`CIAreaHistogram` 결과 없음)는 `MellowError.renderFailed`로 알리고 레시피를 바꾸지 않는다.

## 8. 테스트

| 층 | 내용 |
|---|---|
| Shared | `detail`·`look`·`geometry` 기본값 디코드와 라운드트립; `isDefault`가 새 필드 반영; 스키마 테스트 확장; `GeometryTransform` 왕복(반전·회전·수평·자르기 조합 8케이스, 오차 1e-9)과 자른 영역 밖 nil; 룩 카탈로그 디코드, id 10개, 번들 사본과 `shared/` 바이트 동일. |
| Rendering | 디테일: highlights −1이 밝은 그라데이션의 최대 휘도를 낮춘다, shadows +1이 최소 휘도를 올린다, vignette 1이 모서리 픽셀을 중앙보다 어둡게 한다, sharpness가 바이트를 바꾼다, 전부 0이면 항등. 룩: 강도 0 = 항등, 강도 1 ≠ 항등, 10종 전부 렌더 성공, 모르는 id = 항등. 기하: 128×80에 1:1 자르기 → 80×80, 90° 회전 → 80×128, 반전은 왼쪽 열과 오른쪽 열 교환, 수평 5°에서 결과 extent가 원본과 같고 모서리 픽셀이 투명하지 않음, `skipsCrop`이면 자르기만 생략. 파이프라인 이름 7개 순서. 자동 보정: 어두운 단색 → exposure > 0, 밝은 단색 → exposure < 0, 얼굴 있으면 portrait 값, 없으면 0. |
| Library | `detail` 없는 구 프리셋 디코드; `applyAuto`가 잠긴 사진의 faceSlim 보존. |
| Editing | `applyAuto`가 체크포인트 1회; `look`·`geometry` 변경이 잠금과 무관. |
| App | `autoEnhance()`가 undo 1단계·렌더 예약; 자르기 도구 진입 시 미리보기가 자르기 전; 잡티 탭이 `toOriginal`을 거쳐 원본 좌표로 기록; 룩 썸네일 캐시가 사진·룩별로 1회 렌더. |
| 실기동 | Mac: 필터 선택→강도→자동 보정→자르기 1:1→수평→저장(파일 크기 확인). iPhone·iPad 시뮬레이터 화면 캡처. |

## 9. 범위 밖과 선행 작업

범위 밖: LUT(.cube) 룩, 텍스트·스티커, 사용자 필터 제작, 필터 자동 추천, Android·Windows 코드.

B0 첫 Task는 A에서 parked된 3건 정리다: 백그라운드 진입 시 열린 드래그 저장 창 flush, `select`의 세션 2회 저장 제거, `docs/APPLE.md`의 "핀치 확대 없음" 문구와 테스트 수 갱신.

B0 완료 후 절차(스펙 밖, 기록용): GitHub `production` 환경에 `apple-v*` 태그 규칙 추가 → main 푸시 → `scripts/release.sh apple 0.3.0` → 태그 푸시 → TestFlight 내부 테스터 그룹에 두 명.

## 10. 위험

| 위험 | 대응 |
|---|---|
| 자르기 후 캔버스 탭 좌표 어긋남 | `GeometryTransform` 왕복 테스트 + 자르기 도구 안에서는 탭 도구 비활성. |
| 룩 10종 수치가 데모 사진에서만 좋아 보임 | 구현 Task에서 인물·풍경·실내 세 장으로 확인하고 수치 조정 근거를 보고서에 남김. |
| `CIHighlightShadowAdjust`가 큰 이미지에서 느림 | 미리보기는 1600px 이하라 허용. 내보내기만 느려지며 진행률로 표시. |
| 자동 보정이 과도한 결과 | 모든 값 클램프 + 한 번의 실행 취소. 보수적 게인(`RenderTuning`)에서 시작. |
| 룩 썸네일 10장 렌더로 필터 패널 진입이 느림 | 220px 썸네일에 룩만 적용(전체 파이프라인 아님), 사진별 캐시, 백그라운드 액터에서 순차 렌더. |
