# 인물 보정 G (피부 정밀·몸 피부·효과·작업 흐름) 설계

작성 2026-10-20. 선행: [인물 보정 B~F](2026-10-15-beauty-b-to-f-design.md), 근거: [Evoto 기능 역공학 분석](../../research/2026-10-20-evoto-analysis.md). 기준 코드: main 1.2.0(`5be4ced`).

## 사람이 확인할 것

### 결정

| 결정 | 이유 | 바꾸면 비용 |
|---|---|---|
| 얼굴 피부 정밀 7종(다크서클·팔자주름·마리오네트 주름·미간 주름·얼룩 고르기·붉은기·번들거림)은 새 단계가 아니라 기존 `skin` 단계를 넓혀 넣음 | 피부 마스크·대상 얼굴 반복·비트맵 캐시·"얼굴 없으면 건너뜀" 규칙을 그대로 씀. 단계가 늘면 같은 마스크를 두 번 만듦 | 작음 |
| 단계 순서를 `skin → bodySkin → feature → makeup → background → shapeWarp → localEdit → geometry → color → detail → look → effect`로 고정 | 몸 피부는 색을 바꾸므로 B~F 규칙대로 원본 좌표·변형 앞. 그레인·글로우는 최종 출력 질감이라 룩 뒤 | **큼** |
| 마리오네트 주름은 팔자주름과 별도 슬라이더(`portrait.skin.marionette`). 팔자 띠는 코 날개 → 입꼬리, 마리오네트 띠는 입꼬리에서 턱 쪽으로 내려가는 띠 | 사용자 결정. 입꼬리 아래에는 Vision 특징점이 없어 마리오네트 띠의 위치 근거가 더 약하므로 강도를 따로 조절할 수 있어야 함 | 작음 |
| 주름 띠는 얼굴 좌표(`FaceFrame`) 타원 × 피부 다각형 비트맵(메이크업과 같은 `softMask`) | 기울어진 얼굴을 따라가고 눈·입 안에는 닿지 않으며 새 캐시 항목이 없음 | 작음 |
| 주름 밝히기는 휘도로 "넓은 주변 평균 − 국소 저주파"의 양수 차이를 재고, 국소 휘도 대비 그 비율만큼 RGB를 곱해 올림(어두운 만큼만, 색상·채도 유지, 배율 상한 1.6). 모공의 상대 대비는 유지되고 절대 진폭은 배율만큼 커짐. (G1 구현 중 변경: 채널별 차이는 둘레에 배경색이 섞여 파란 기가 생겼고, 같은 양을 RGB에 더하면 주름이 회색으로 바램) | Evoto 전후 측정(밝기만 오르고 고주파 비 0.9~1.0)과 같은 방향. 텍스처를 뭉개지 않음 | 작음 |
| 얼룩 고르기와 번들거림은 기존 대역 합성 커널을 넓혀 "저주파를 마스크 가중 넓은 평균 쪽으로 당김"으로 구현. 번들거림은 피부색 가중치 안의 밝은 픽셀에서 저주파를 당기고 중주파도 함께 줄임. 피부색에서 먼 흰 반사광 중심은 가중치 밖이라 거의 줄지 않음. (G1 구현 중 변경: 작은 반사광은 대부분 중주파에 있어 저주파만 당기면 거의 줄지 않음. 넓은 번들거림은 덜 줄어 실사진 확인 필요) | Evoto의 "주파수 분리 저주파" 관찰과 같음. 마스크 가중 평균이라 피부 경계에서 머리카락·배경 색이 번지지 않음 | 작음 |
| 붉은기는 가운데 0인 양방향: − 쪽은 볼 기준보다 붉은 만큼만 줄이고(맑게), + 쪽은 Cr을 고르게 더함(혈색) | 반점만 줄이려면 기준이 필요하고, 혈색은 균일하게 올리는 것이 자연스러움 | 작음 |
| 몸 피부·톤은 새 단계 `bodySkin`: 인물 마스크 × 가장 큰 얼굴의 볼 기준 피부색 가중치 − 눈·눈썹·입 영역(특징점이 없으면 대체 타원). 밝기·톤은 얼굴 포함 보이는 피부 전체, 매끄럽게는 얼굴 피부 다각형 전체(눈가·입가 포함)를 뺀 나머지. (G2 구현 중 변경: 눈썹도 빼고, 매끄럽게 제외 영역을 잘라내지 않은 얼굴 다각형으로 넓힘. 리뷰에서 눈가·입가 고리가 두 번 매끄럽게 되고 눈썹이 하얗게 들리는 문제가 나옴) | Evoto와 같이 얼굴·팔·배에 함께 걸리고 옷·배경은 피부색 가중치가 뺌. 얼굴은 자기 슬라이더가 있어 두 번 매끄럽게 하지 않음 | 중간 |
| 얼굴이 없으면(얼굴 없음·얼굴 분석 실패 모두) 몸 피부는 조용히 건너뜀(오류 아님). 고정 피부색 사전 분포로 대체하지 않음. 피부톤 탭은 기존 얼굴 없음 안내만 보임 | 사용자 결정(처음 제안으로 되돌림). 고정 기준색 하나는 그 색과 많이 다른 피부를 덜 고치거나 얼룩지게 하고, 허용 범위를 넓히면 옷·나무로 번짐. 얼굴 없는 사진은 드물고 대체 모드는 기준색·안내·패널 분기·테스트를 더함. 나중 후보는 손목·팔 관절점 근처에서 그 사람의 실제 피부색을 재는 방식 | 중간 |
| 몸 피부는 `dependsOnPerson`에만 넣고 `dependsOnFaces`에는 넣지 않음. 얼굴 분석이 실패한 사진에 몸 피부 값이 있어도 저장은 되고(몸 피부만 빠짐) 미리보기와 같음 | `dependsOnFaces`에 넣으면 얼굴 분석 실패 사진의 저장이 `faceAnalysisUnavailable`로 막힘. 배경 흐림과 같은 "해당 단계만 건너뜀" 규칙이 맞고, 패널이 얼굴 없음을 먼저 안내하므로 조용히 빠져도 놀라지 않음 | 작음 |
| 피부 밝기는 0…1 한 방향(흰색 쪽으로 섞음), 피부 톤은 −1…1(따뜻 ↔ 차가움), 바디 매끄럽게 0…1 | Evoto "피부색 변경"은 밝히는 방향만 측정됨. 어둡게는 조정 도구의 노출로 충분 | 작음 |
| 레시피: `portrait.skin`에 키 7개 추가, 최상위 `bodySkin`·`effects` 추가, `schemaVersion` 2 유지, 기본값은 모두 항등 | B~F "키 추가만" 규칙. 옛 세션은 기본값으로 읽혀 결과가 같음 | 중간 (플랫폼 공통 계약) |
| 효과는 룩 뒤 새 단계 `effect`: 글로우(흐린 사본을 제곱해 밝은 곳에 모은 빛을 스크린 합성) → 그레인(짧은 변에 비례한 회색 잡음을 오버레이). 두 슬라이더 0…1 (G3 구현 중 변경: `CIBloom`은 고르게 밝은 영역을 밝히지 않아 하이라이트에 빛이 번지지 않았음) | Core Image 기본 필터만으로 됨. 그레인 크기를 짧은 변에 비례시켜 미리보기와 저장본이 같아 보임 | 작음 |
| 선택 동기화: 동기화 항목 9종(`SyncCategory`)은 MellowEditing에 두고 `applyFromBatch(_:categories:)`가 고른 그룹만 복사. 선택은 앱 세션 상태(파일에 저장하지 않음), 기본은 전부 | "무엇을 복사하나"는 편집 규칙이고 Library가 Editing을 의존하므로 모듈 표 그대로. 저장하지 않으면 세션 스키마가 바뀌지 않음 | 작음 |
| 잠긴 사진 보존 규칙은 그대로이고, 얼굴 의존 항목(피부·얼굴형·눈입·메이크업) 중 하나라도 동기화할 때만 잠기지 않은 사진의 대상 얼굴을 전체로 되돌림 | 색감만 동기화하는데 대상 얼굴이 풀리면 놀람 | 작음 |
| 기존 "원본 비교" 전체 토글은 그대로 두고, 분할 비교(드래그하는 분할선)를 비교 모드 하나로 더함(`없음 · 전체 · 분할`). 분할선은 0…1로 드래그 | 피부 질감·잡티·턱선 같은 작은 변화는 같은 자리에서 번갈아 보는 토글이 더 잘 보이고, 분할은 화면 전체의 색·톤 변화를 나란히 볼 때 맞음(사용자 결정). 비교 중 캔버스 탭 금지 규칙은 두 모드 모두 그대로 | 작음 |
| 자동 보정은 바꾸지 않음. 단 `applyAuto`가 피부 그룹을 통째로 덮어쓰던 것을 `smoothing`·`autoBlemish`만 쓰도록 고침 | 지금 코드 그대로면 자동 보정이 다크서클·붉은기 값을 0으로 지움 | 작음 |
| 화면: 뷰티 › 피부 탭에 7개 슬라이더 추가, 뷰티에 "피부톤" 탭 추가(몸 피부 3개), 조정 패널 끝에 "효과" 2개, 전체 적용 버튼 옆 "동기화 항목" 메뉴, 동작 줄에 기존 "원본 비교" 옆 "분할" 버튼 | 새 도구를 늘리지 않음(도구 줄 9개 유지). 몸 피부도 얼굴이 필요하므로 뷰티 안이 맞음 | 작음 |
| 다각형 비트맵 캐시 상한을 얼굴당 해상도마다 8 → 9 | 몸 피부가 얼굴마다 눈·입 비트맵 하나를 더 씀 | 작음 |

### 범위

| 묶음 | 들어가는 것 | 계획 |
|---|---|---|
| G1 피부 정밀 | 다크서클, 팔자주름, 마리오네트 주름, 미간 주름, 피부 얼룩 고르기, 붉은기(맑게 ↔ 혈색), 번들거림 | `2026-10-20-beauty-g1-skin-refinement.md` |
| G2 몸 피부·톤 | 피부 밝기, 피부 톤(따뜻 ↔ 차가움), 바디 피부 매끄럽게 | `2026-10-20-beauty-g2-body-skin.md` |
| G3 효과·작업 흐름 | 그레인, 글로우, 선택 동기화, 분할 전후 비교, 문서·검증 기록 | `2026-10-20-beauty-g3-effects-workflow.md` |

### 범위 밖

캐치라이트, 헤어(윤기·흰머리·색·잔머리), 이중 턱, 눈 뜨기·표정·시선·문신·안경 반사·배경 확장, 모델 번들, 얼굴 없는 사진의 몸 피부(나중 후보: 손목·팔꿈치 관절점 근처에서 그 사람의 실제 피부색을 표본으로 재어 기준색으로 쓰기. 고정 피부색 사전 분포는 사용자가 거부), 동기화 선택의 영속화(사용자 결정: 매번 전부), 자동 보정 항목 추가, 1.3.0 배포 준비(릴리스 노트·태그).

### 위험과 대응

- **주름 위치는 추정이다.** Vision 특징점에 주름선이 없어 코 날개·입꼬리·눈썹 안쪽 점으로 띠를 그린다. 마리오네트 띠는 입꼬리 아래에 특징점이 전혀 없어 입꼬리에서 고정 각도로 내려 긋는 어림이라 가장 약하다. 얼굴이 많이 돌아가면 띠가 어긋날 수 있다. 대응: 띠는 넓고 부드럽게, 올리는 양은 "주변보다 어두운 만큼"으로 제한해 어긋나도 밝은 얼룩이 생기지 않게 하고, 마리오네트는 슬라이더를 따로 두어 끌 수 있게 한다.
- **몸 피부는 얼굴 기준색에 기댄다.** 얼굴과 몸에 조명이 다르게 떨어지거나 피부색이 다른 사람이 함께 있으면 판별이 흔들린다. 대응: 가중치 거리 기준을 얼굴보다 넓게 두고 강도 상한을 보수적으로 잡는다. 기준은 가장 큰 얼굴 하나다.
- **얼굴이 없으면 몸 피부가 동작하지 않는다(한계).** 뒷모습·팔만 나온 사진에서는 피부톤 탭이 얼굴 없음 안내만 보이고 슬라이더는 보이지 않는다. 얼굴 분석이 실패한 사진에 프리셋으로 몸 피부 값이 들어오면 조용히 빠진다(저장은 됨). 대응: 범위 밖으로 두고 관절점 기반 피부색 표본을 나중 후보로 적어 둔다.
- **몸 피부 매끄럽게는 사진 전체 크기 흐림이다.** 48MP 저장에서 시간이 늘 수 있다. 대응: 반지름을 짧은 변 비례로 작게 두고 VALIDATION에 측정치를 적는다.
- **흰 반사광 중심은 번들거림이 닿지 않는다.** 하얗게 날아간 반사광은 피부색 가중치(볼 기준 색 거리) 밖이라 슬라이더가 거의 줄이지 못한다. 실사진 이마·코에서 확인할 항목이다.
- **번들거림 판별은 밝기만 본다.** 흰 옷깃이 얼굴 마스크 안으로 들어오면 눌릴 수 있다. 대응: 피부 마스크(피부색 가중치) 안에서만 동작한다.
- **그레인은 결정적이어야 한다.** `CIRandomGenerator`는 위치마다 값이 고정이라 같은 입력이면 같은 결과이고, 테스트도 바이트 비교로 확인한다.
- **화면 품질 판정은 자동 테스트로 할 수 없다.** 실제 사진 확인은 사용자 조치다.

### 사용자 조치

- 구현 뒤 실제 인물·단체·상반신 사진으로 7종 피부 정밀과 몸 피부 결과를 보고 과하거나 약한 항목 피드백(수치는 `RenderTuning` 한 곳).
- 몸 피부가 옷·배경에 번지는 사진이 있으면 알려 주기(가중치 거리 기준 조정 후보).
- 분할 비교 손잡이 크기와 동기화 메뉴 글자가 iPhone 폭에 맞는지 확인.

### 외부 효과가 있는 단계

이 단계 안에는 없다. 푸시·태그·TestFlight 업로드·릴리스 노트는 G 범위가 아니며, 세 계획 어디에서도 실행하지 않는다. 머지 뒤 배포 여부는 사용자가 따로 정한다.

## 에이전트 참조

### 1. 공통 구조

#### 1.1 모듈 배치 (`docs/architecture/modules.md` 규칙 준수, 의존성 표 변경 없음)

| 새 타입·변경 | 모듈·폴더 | 설명 |
|---|---|---|
| `SkinRefinementKey`, `SkinAdjustments` 확장 | MellowShared/API | 피부 정밀 7종 값 |
| `BodySkinKey`, `BodySkinAdjustments` | MellowShared/API | 몸 피부 3종 값 |
| `EffectKey`, `EffectAdjustments` | MellowShared/API | 그레인·글로우 |
| `AdjustmentRange.skinRefinement(_:)`, `bodySkin(_:)` | MellowShared/API | 붉은기·톤만 양방향 |
| `EditChange.skinRefinement`·`bodySkin`·`effect`, `EditingPolicy` 범위 함수 | MellowEditing/API | 편집 변경 |
| `SyncCategory`, `EditDocument.applyFromBatch(_:categories:)` | MellowEditing/API | 선택 동기화 규칙 |
| `ProjectSession.applyToAll(from:categories:)` | MellowLibrary/API | 고른 항목만 복사 |
| `FaceRegions+Folds.swift` (`darkCircleMask`·`nasolabialMask`·`marionetteMask`·`glabellaMask`) | MellowRendering/Domain | 주름 띠 마스크. 마스크는 `FaceRegions` 한 곳 규칙 유지 |
| `SkinKernels` 커널 3개 추가(`foldLift`·`toneMix`·`redness`) | MellowRendering/Domain | 피부 CIKL 색 커널은 이 타입 한 곳 |
| `SkinRefinement` | MellowRendering/Domain | 주름 밝히기·붉은기 적용 도우미(`SkinStage`가 부름) |
| `FrequencySeparation.refined(...)`, `maskedMean(...)` | MellowRendering/Domain | 얼룩 고르기·번들거림이 들어간 대역 합성 |
| `BodySkinStage` | MellowRendering/Domain | 새 단계 `bodySkin` |
| `EffectStage` | MellowRendering/Domain | 새 단계 `effect` |
| `ToneShift.blueness` | MellowRendering/Domain (`FeatureKernels`) | Cb 가산(피부 톤) |
| `RenderTuning` 상수 22개 | MellowRendering/API | 1.6 표 |
| `BeautyTab.skinTone`, `SyncMenu`, `CompareDivider`, `AppModel` 상태 | 앱 타깃 | 화면 |

새 프레임워크 import 없음. `verify-modules.sh` 변경 없음. MellowRendering은 MellowEditing을 import하지 않으므로 렌더는 `AdjustmentRange`로 직접 자른다.

#### 1.2 레시피 확장 (schemaVersion 2 유지, 키 추가만, 기본값 = 항등)

```json
"portrait": {
  "skin": { "smoothing": 0, "autoBlemish": false,
            "darkCircles": 0, "nasolabial": 0, "marionette": 0, "glabella": 0, "toneEvening": 0, "redness": 0, "shine": 0 }
},
"bodySkin": { "brightness": 0, "tone": 0, "smoothing": 0 },
"effects":  { "grain": 0, "glow": 0 }
```

- 범위: `skin.redness`·`bodySkin.tone` −1…1(`AdjustmentRange.bipolar`), 나머지 0…1(`AdjustmentRange.unit`). `AdjustmentRange.skinRefinement(_:)`·`bodySkin(_:)`가 키별 범위를 돌려주고 `EditingPolicy`가 같은 이름으로 내보낸다.
- `SkinAdjustments.hasEffect`는 새 값 중 0이 아닌 것이 있으면 true(그래서 `dependsOnFaces`는 자동으로 포함). `numericValues`는 `[smoothing] + SkinRefinementKey.allCases 순서`.
- `EditRecipe.dependsOnPerson = background.hasEffect || bodySkin.hasEffect`. `dependsOnFaces`는 바뀌지 않는다(몸 피부는 포함하지 않음 — 얼굴이 없으면 단계만 건너뛰고 저장은 막지 않는다, 결정 표).
- `allValuesFinite`에 새 스칼라 12개 전부 포함.
- `PresetValues`에 `bodySkin`·`effects` 그룹 추가(없으면 기본값으로 디코드). 프리셋 저장·적용·일괄 적용이 새 값을 나른다.
- `shared/recipe-schema/edit-recipe.v2.schema.json`에 키 추가(`additionalProperties: false`라 필수), `session-file.v2.schema.json`의 프리셋 `values`에 `bodySkin`·`effects` `$ref` 추가, README 요점·범위 표·"키를 추가할 때의 규칙" 절에 G 항목 추가.
- `EditChange` 추가: `skinRefinement(SkinRefinementKey, Double)`, `bodySkin(BodySkinKey, Double)`, `effect(EffectKey, Double)`. 셋 다 `affectsGeometry == false`(색만 바꾸므로 수동 편집 잠금 대상 아님).
- `EditDocument.applyAuto`는 `updated.portrait.skin.smoothing`·`autoBlemish`만 제안값으로 바꾼다(정밀 7종 보존).

#### 1.3 파이프라인 순서

```
skin → bodySkin → feature → makeup → background → shapeWarp → localEdit → geometry → color → detail → look → effect
```

- `bodySkin`은 `skin` 바로 뒤: 색을 바꾸는 피부 보정이라 원본 좌표·변형 앞(B~F 결정). 얼굴 `skin`이 먼저라 볼 기준색은 얼굴 보정 뒤 값을 재지만 피부 보정은 색 평균을 거의 바꾸지 않는다.
- `effect`는 `look` 뒤 마지막: 그레인은 출력 질감이라 선명도·룩 톤 커브 뒤에 얹고, 글로우는 그레인 앞(잡음이 번지지 않게). 기하 뒤이므로 현재 이미지 extent로 자른다(`LookStage`와 같음).
- `RenderPipelineTests.testStageOrderMatters`의 이름 배열을 G2(bodySkin)·G3(effect)에서 갱신.

#### 1.4 분석

새 분석은 없다. 기존 `PhotoAnalysis`(얼굴·잡티·인물 마스크·관절점)를 그대로 쓴다. 몸 피부의 기준 얼굴은 `context.faces` 중 `boundingBox.width`가 가장 큰 얼굴이다(대상 얼굴 선택과 무관, 몸 피부는 얼굴별 보정이 아님). 얼굴이 하나도 없으면(얼굴 없음·얼굴 분석 실패 모두 `faces`가 빔) 몸 피부 단계는 입력을 그대로 돌려준다.

#### 1.5 주름 띠 마스크 (`FaceRegions+Folds.swift`)

모두 `FaceFrame` 얼굴 좌표(u = 눈 방향, v = 입 → 눈)에서 타원을 놓고 `softMask(ovals, face:frame:extent:tuning:cache:)`로 만든다(타원 최대 × 피부 다각형 비트맵, 피부 마스크 흐림 반지름). 비율 상수는 `private enum FoldShape`. `Oval`에 `tilt: CGFloat = 0`(얼굴 x축 기준 추가 회전, 라디안)을 더하고 `softMask`가 `angle + tilt`로 그린다. 윤곽점이 없어(`FaceFrame`이 nil) 띠를 만들 수 없으면 nil이고 그 항목만 건너뛴다.

| 마스크 | 필요한 특징점 | 타원 |
|---|---|---|
| `darkCircleMask` | 두 눈(`frame.eyes.count == 2`), 눈 다각형 | 눈마다 중심 (눈 u, 눈 다각형 아래끝 v − 눈 높이 × `dropFraction` 0.6), 반지름 (눈 폭 × 0.6, 눈 높이 × 0.8). 눈 안은 피부 비트맵의 보호 영역이 0으로 만든다 |
| `nasolabialMask` | 코, 바깥 입술 | 쪽마다 코 날개(코 다각형에서 그 쪽 x 끝 점)와 입꼬리(바깥 입술에서 그 쪽 x 끝 점)를 잇는 선분. 선분 중점을 바깥쪽(얼굴 가운데 반대)으로 얼굴 폭 × 0.02 민 자리를 중심으로, 반지름 (길이 × 0.55, 얼굴 폭 × 0.035), tilt = 선분 각도 |
| `marionetteMask` | 바깥 입술 | 쪽마다 입꼬리에서 얼굴 좌표 −v(턱 쪽)에서 바깥쪽으로 `marionetteTiltFromVertical`(0.26 rad ≈ 15°) 기운 고정 방향으로 얼굴 폭 × 0.12 내려간 선분. 선분 중점을 바깥쪽으로 얼굴 폭 × 0.02 민 자리를 중심으로, 반지름 (얼굴 폭 × 0.07, 얼굴 폭 × 0.03), tilt = 그 방향 각도. 코가 없어도 된다(입꼬리 아래에는 특징점이 없어 방향을 고정한다) |
| `glabellaMask` | 두 눈썹 | 중심 u = 두 눈썹 안쪽 끝(가운데에 가까운 x 끝 점)의 중점, v = 그 두 점 v 평균, 반지름 (안쪽 끝 간격 × 0.5 + 얼굴 폭 × 0.01, 얼굴 폭 × 0.07) |

코 날개 "그 쪽"은 `eyeMidline` 기준으로 u 부호가 같은 쪽이다. 한쪽이라도 점이 없으면 그 쪽 타원만 뺀다.

#### 1.6 알고리즘과 `RenderTuning` 상수

모든 피부 정밀은 `SkinStage.apply` 안에서 대상 얼굴마다 다음 순서로 돈다: 자동 잡티(기존) → 주름 밝히기 4종(다크서클 → 팔자 → 마리오네트 → 미간) → 대역 합성(피부 보정·얼룩 고르기·번들거림 한 번) → 붉은기. 값은 `AdjustmentRange`로 먼저 자른다. 피부 마스크는 `FaceRegions.skinMask(strength: 1)`을 한 번 만들고(`unitMask`), 합성용은 `MaskBuilder.scaled(unitMask, by: tuning.skinMaskMaxStrength)`다.

**주름 밝히기** (`SkinRefinement.liftFold`): 영역 마스크 `m`, `low = blur(image, faceWidth × foldLowBandFraction)`, `surround = blur(image, faceWidth × foldSurroundFraction)`. 커널 `foldLift`: `gap = max(Y(surround) − Y(low), 0)`(BT.601 휘도), `gain = min(1 + amount × gap / max(Y(low), foldLumaFloor), foldLiftMaxGain)`, `rgb' = rgb × gain`, amount = 값 × `foldLiftMax`. 휘도 차이라 둘레의 배경·입술 색이 번지지 않고, 세 채널에 같은 배율을 곱해 그늘의 색조·채도를 지킨다(같은 값을 더하면 밝힌 다크서클이 회색으로 뜸). 둘레가 더 어두우면 배율 1이다. `MaskBuilder.blend(lifted, over: image, mask: m)`을 `m.bounds` 안에서만 계산. (G1 구현 중 변경: 처음 식 `rgb + max(surround − low, 0) × amount`는 채널마다 차이를 재 배경 옆 띠에 파란 기를 더했다.)

| 상수 | 시작값 | 뜻 |
|---|---|---|
| `foldLowBandFraction` | 0.015 | 주름 국소 저주파 반지름(얼굴 폭 비율). 가장 좁은 띠(마리오네트, 얼굴 폭 3%)의 절반이고 모공 대역(0.6%)의 2.5배. (G1 구현 중 변경: 0.04는 좁은 주름 그림자를 거의 지워 밝힘이 생기지 않음) |
| `foldSurroundFraction` | 0.12 | 주변 피부 평균 반지름 |
| `foldLiftMax` | 0.9 | 값 1에서 어두운 휘도 차이의 90%를 올림 |
| `foldLiftMaxGain` | 1.6 | 밝히기 배율 상한. 선형 휘도를 40% 잃은 그늘을 0.9로 올리는 배율(1 + 0.9 × 0.4 / 0.6). 눈가처럼 국소 휘도가 아주 낮은 곳에서 배율이 튀지 않음 |
| `foldLumaFloor` | 0.01 | 배율 분모(국소 선형 휘도)의 하한 |

**대역 합성** (`FrequencySeparation.refined`): 기존 `low + mid × keep + fine`에서 `low`를 바꾼다. `wideNum = blur(image × unitMask, r_tone)`, `wideDen = blur(unitMask, r_tone)`, `wide = wideNum / max(wideDen, ε)`(마스크 가중 평균이라 경계에서 머리카락·배경이 섞이지 않음), `r_tone = faceWidth × toneBandFraction`. 커널 `toneMix`:

```
even' = max(even, shine × w)            // w = 번들거림 가중치
w = clamp((Y(image) − (Y(reference) + shineOffset)) / shineRamp, 0, 1)   // 선형 휘도 BT.709
low  = mix(midBlur, wide, even')
mid  = (fineBlur − midBlur) × (1 − shine × w)
out  = low + mid × keep + (image − fineBlur)
```

`reference`는 볼 두 곳의 선형 평균(`CIAreaAverage` 두 개를 `CIMix` 0.5로 섞은 무한 이미지), `even = toneEvening × toneEveningMax`, `shine = shineValue × shineReductionMax`, `keep = 1 − smoothing × midReductionMax`. 작은 반사광은 대부분 중간 대역에 있어 번들거림 가중치만큼 중간 대역도 줄인다(G1 구현 중 변경: 저주파만 당기면 반지름 12px 반사광이 11바이트만 줄었다). 모공 대역은 그대로다. 세 값이 모두 0이면 기존 `bandMix` 경로(넓은 흐림을 만들지 않음). `smoothing`만 0이 아니면 결과는 지금과 바이트 단위로 같아야 한다(회귀 테스트).

| 상수 | 시작값 | 뜻 |
|---|---|---|
| `toneBandFraction` | 0.12 | 얼룩 고르기 기준 평균 반지름(얼굴 폭 비율) |
| `toneEveningMax` | 0.8 | 값 1에서 저주파를 평균 쪽으로 80% |
| `shineLumaOffset` | 0.12 | 기준 휘도보다 이만큼 밝으면 번들거림 시작(선형 휘도) |
| `shineLumaRamp` | 0.1 | 시작점에서 이만큼 더 밝으면 가중치 1 |
| `shineReductionMax` | 0.85 | 값 1에서 번들거림 저주파를 평균 쪽으로 85% 당기고 중간 대역을 85% 줄임 |

**붉은기** (`SkinRefinement.adjustRedness`): sRGB 감마 값으로 바꿔 커널 `redness`를 적용하고 되돌린다(`FeatureKernels.shifted`와 같은 틀). `cr_ref`는 볼 기준 평균(감마)의 Cr. 값 v < 0: `cr' = cr − max(cr − cr_ref, 0) × |v| × rednessClearMax`. v > 0: `cr' = cr + v × rednessFlushMax`. Y·Cb는 그대로, RGB로 되돌려 0…1로 자른다. 피부 마스크(합성용)로 원본 위에 합성.

| 상수 | 시작값 | 뜻 |
|---|---|---|
| `rednessClearMax` | 0.7 | −1에서 기준보다 붉은 양의 70%를 줄임 |
| `rednessFlushMax` | 0.03 | +1에서 감마 Cr에 더하는 값 |

**몸 피부** (`BodySkinStage`): `personMask`가 없거나 `faces`가 비면 입력 그대로(오류 아님). 기준 얼굴 = 가장 넓은 얼굴. `encoded = image(sRGB 감마)`, `(left, right) = FaceRegions.cheekAverages(of: encoded, face:, extent:)`(볼 상자가 하나도 없으면 건너뜀). `person = BackgroundStage.personMask(personMask, extent:, feather: shortSide × bodySkinMaskFeather)`(배경 마스크를 만들던 확대·흐림을 반전 없이 돌려주는 새 정적 함수, `backgroundMask`는 이것을 반전). `chroma = SkinKernels.chromaWeight(encoded, left, right, sigma: bodySkinChromaSigma, extent)`. 모든 얼굴의 눈·바깥 입술 다각형을 한 비트맵으로 그린 `features = FaceRegions.featheredPolygonMask(fill: eyes + [outerLips], cut: [], ...)`를 반전해 곱한다(사진당 해상도마다 캐시 항목 1개 → `entriesPerFacePerResolution` 9). `toneMask = person × chroma × (1 − features)`. `smoothMask = toneMask × (1 − skinPolygonRaster(모든 얼굴의 최대))`.
- 밝기·톤: `FeatureKernels.shifted(image, by: ToneShift(lift: brightness × bodySkinLiftMax, blueness: −tone × bodySkinToneMax, redness: tone × bodySkinToneMax), extent)`를 `toneMask`로 합성. `ToneShift`에 `blueness`(Cb 가산)를 더하고 커널 인자를 하나 늘린다(기본 0이라 기존 호출 결과 불변).
- 매끄럽게: `FrequencySeparation.smoothed(image, bounds: extent, faceWidth: shortSide × bodySkinBandScale, smoothing:, tuning:)`를 `smoothMask`로 합성. 반지름은 `fine = max(0.5, shortSide × bodySkinFineBandFraction)`, `mid = shortSide × bodySkinMidBandFraction`이 되도록 `faceWidth` 인자 대신 반지름을 직접 받는 오버로드 `smoothed(_:bounds:radii:smoothing:tuning:)`를 추가한다.
- 적용 순서: 매끄럽게 → 밝기·톤(밝기 뒤에 매끄럽게 하면 밝기 경계가 번짐).

| 상수 | 시작값 | 뜻 |
|---|---|---|
| `bodySkinChromaSigma` | 0.05 | 얼굴(0.04)보다 넓은 피부색 거리 기준 |
| `bodySkinMaskFeather` | 0.004 | 인물 마스크 흐림(짧은 변 비율, 배경과 다르게 조금 좁게) |
| `bodySkinLiftMax` | 0.2 | 밝기 1에서 흰색 쪽으로 섞는 비율(감마) |
| `bodySkinToneMax` | 0.025 | 톤 ±1에서 감마 Cr 가산·Cb 감산 |
| `bodySkinFineBandFraction` | 0.002 | 몸 모공 대역 반지름(짧은 변 비율) |
| `bodySkinMidBandFraction` | 0.012 | 몸 얼룩 대역 반지름 |

**효과** (`EffectStage`): 값은 `AdjustmentRange.unit`으로 자른다. `glow > 0`이면 흐림(반지름 shortSide × glowRadiusFraction, 가장자리 늘림) → 자기 자신과 곱해 하이라이트에 빛을 모음 → glow × glowMaxIntensity 배 → 원본 위에 스크린 합성 뒤 현재 extent로 자른다. `grain > 0`이면 `CIRandomGenerator` 출력의 알파 채널(0…1 균등)을 회색으로 만들어(`RenderingTestSupport.skinTexture`와 같은 `CIColorMatrix` 방식) `0.5 + (gray − 0.5) × grain × grainMaxAmplitude`로 옮기고, 픽셀 크기 `max(1, shortSide × grainSizeFraction)`로 확대한 뒤 sRGB 감마 공간에서 `CIOverlayBlendMode`로 얹고 선형으로 되돌린다(`MakeupStage.blended`와 같은 틀). 회색 0.5 오버레이는 항등이라 `grain = 0`이면 바이트가 같다. 짧은 변은 현재 이미지(기하 뒤) 기준.

| 상수 | 시작값 | 뜻 |
|---|---|---|
| `grainMaxAmplitude` | 0.12 | 그레인 1에서 오버레이 층의 ±진폭(감마) |
| `grainSizeFraction` | 0.0012 | 알갱이 한 변(짧은 변 비율, 1200px에서 1.4px) |
| `glowRadiusFraction` | 0.02 | 글로우 반지름(짧은 변 비율) |
| `glowMaxIntensity` | 0.6 | 글로우 1에서 스크린 합성하는 빛의 배율 |

#### 1.7 선택 동기화

```swift
// MellowEditing/API/SyncCategory.swift
public enum SyncCategory: String, CaseIterable, Codable, Sendable, Identifiable {
    case color       // color + detail
    case effects
    case skin        // portrait.skin (정밀 7종 포함)
    case faceShape   // portrait.face (잠금 규칙 적용)
    case features
    case makeup
    case background
    case body        // body (잠금 규칙 적용)
    case bodySkin
    public var id: Self { self }
    public static let all = Set(allCases)
    /// 얼굴 의존 항목. 하나라도 들어 있으면 잠기지 않은 사진의 대상 얼굴을 전체로 되돌린다.
    public var dependsOnFaces: Bool
}
```

- `EditDocument.applyFromBatch(_ values: PresetValues, categories: Set<SyncCategory> = SyncCategory.all)`. 빈 집합이면 아무것도 하지 않는다(체크포인트 없음). `apply(_:)`(프리셋)는 전부 복사로 그대로.
- `merged(values, targetFace:, categories:)`: 고른 그룹만 덮어쓴다. `faceShape`·`body`는 잠긴 사진에서 건너뛴다. 대상 얼굴은 잠겼으면 유지, 아니면 `categories.contains(where: \.dependsOnFaces)`일 때만 nil.
- `ProjectSession.applyToAll(from id:, categories: Set<SyncCategory> = SyncCategory.all)`.
- 앱: `AppModel.syncCategories: Set<SyncCategory>`(기본 전부, 세션 상태), `setSyncCategory(_:enabled:)`, `canApplyToAll = photos.count >= 2 && !syncCategories.isEmpty`. `EditorScene`의 전체 적용 버튼 옆 `SyncMenu`(톱니 아이콘 `Menu`, 항목마다 `Toggle`). 상태 문구는 고른 항목 수를 포함한다.

#### 1.8 분할 전후 비교 (기존 전체 토글은 그대로)

- `AppModel.CompareMode { off, full, split }`와 `compareMode: CompareMode = .off`. 기존 `isComparing`은 `compareMode == .full`을 뜻하는 계산 속성(get/set)으로 남겨 기존 호출부·`ActionBar`의 "원본 비교" 토글·기존 테스트가 바뀌지 않는다. `set`은 true면 `.full`, false면 `.off`.
- `compareSplit: Double`(원본이 보이는 왼쪽 폭 비율, 기본 `Policy.compareSplitDefault` 0.5), `toggleSplitCompare()`(`.split` ↔ `.off`, 켤 때 분할선은 마지막 위치 유지), `setCompareSplit(_:)`(`Policy.compareSplitRange` 0…1로 자름). `select(_:)`가 `compareMode = .off`로 되돌린다(기존 `isComparing = false`와 같은 자리).
- `displayImage`는 `.full`이면 원본, 아니면 `preview ?? original`(기존과 같음). `blocksCanvasTouch { compareMode != .off }`를 두고 `touch(from:to:)`·마커·브러시 층·자르기 틀은 이 값으로 막는다(지금 `isComparing`을 보던 자리).
- `PhotoCanvasView`: `.split`이면 미리보기 위에 원본을 `mask(alignment: .leading)`로 왼쪽 `width × split`만 보이게 얹고, 그 경계에 `CompareDivider`(세로선 + 손잡이, `DragGesture`로 `setCompareSplit(x / width)`)를 둔다. 왼쪽 위 배지는 `.off` "보정본", `.full` "원본", `.split` "원본 | 보정본".
- `CompareDivider.fraction(forX:width:)`는 순수 계산(클램프)이라 테스트한다. `ActionBar`: 기존 "원본 비교"/"보정본" 버튼은 그대로이고, 그 왼쪽에 `UserMessage.splitCompare`("분할") / `splitCompareDone`("분할 끝") 버튼을 더한다. 한쪽을 켜면 다른 쪽은 꺼진다(모드 하나).
- `Theme.compareDividerWidth` 2, `compareHandleSize` 28.

#### 1.9 앱 화면

- 뷰티 › 피부: 기존 "피부 보정"·"자동 잡티" 아래에 `SkinRefinementKey.allCases` 순서로 "다크서클", "팔자주름", "마리오네트 주름", "미간 주름", "피부 얼룩 고르기", "붉은기", "번들거림". 붉은기만 가운데 0 양방향(`snapsToZero`). 안내 문구에 "주름 위치는 특징점으로 어림한 것"을 적는다.
- 뷰티 › 피부톤(`BeautyTab.skinTone`, 네 번째 탭): "피부 밝기"(0…1), "피부 톤"(−1…1, 스냅), "바디 피부 매끄럽게"(0…1). 사람 없음·인물 분석 실패 안내는 `backgroundAvailability`(인물 마스크 기준)로 보이고, `canAdjustBodySkin(_ key:)`는 배경 흐림과 같은 규칙(드래그 중·ready·값이 0이 아니면 켬). 얼굴 없음·얼굴 분석 실패는 `BeautyPanel`의 기존 `faceAvailability` 분기가 먼저 막는다(뒷모습 사진에서는 피부톤 탭이 얼굴 없음 안내만 보인다).
- 조정: 디테일 슬라이더 아래 구분선, "그레인", "글로우".
- 전체 적용 버튼 옆 `SyncMenu`. 동작 줄은 기존 "원본 비교" 토글 버튼을 그대로 두고 그 왼쪽에 "분할" 버튼을 더한다.
- `UserMessage`에 위 문구 전부와 `skinRefinementTitle(_:)`, `bodySkinTitle(_:)`, `effectTitle(_:)`, `syncCategoryTitle(_:)`, `appliedToAll(categoryCount:)`.

#### 1.10 프리셋·일괄 적용·자동 보정

- 프리셋 저장(`PresetValues(of:)`)은 새 세 그룹을 담고 적용은 전부 덮어쓴다(기존 규칙).
- 일괄 적용은 1.7 규칙.
- 자동 보정 제안은 바뀌지 않는다(`AutoEnhancer` 변경 없음). `applyAuto`는 `skin.smoothing`·`autoBlemish`만 쓴다.

### 2. 테스트 전략

| 범주 | 확인 | 위치 |
|---|---|---|
| 레시피 | 새 키 왕복, 없으면 기본값, 옛 파일 디코드 결과 불변, `hasEffect`·`dependsOnFaces`·`dependsOnPerson`, `allValuesFinite`, 스키마 키 집합, 프리셋 그룹 | `MellowSharedTests` |
| 편집 | 범위 클램프, 잠기지 않음, 실행 취소 한 단계, `applyAuto`가 정밀 값 보존, 선택 동기화 그룹별 복사·잠금·대상 얼굴·빈 집합 | `MellowEditingTests` |
| 라이브러리 | `applyToAll(categories:)`가 고른 그룹만 복사 | `MellowLibraryTests` |
| 렌더 항등 | 값 0이면 입력과 같은 바이트(피부 정밀 각각, 몸 피부, 효과) | `SkinStageTests`, `BodySkinStageTests`, `EffectStageTests` |
| 마스크 밖 불변 | 주름 띠 밖(눈·입·이마·배경), 몸 피부의 옷(피부색 아님)·배경(인물 밖)·눈, 효과는 전체(불변 영역 없음) | 같은 파일 + `FoldRegionsTests` |
| 클램프 | 범위 밖 값이 자른 값과 같은 바이트, 음수는 0 | 단계 테스트마다 |
| 특징점 없음 | 상자만 있는 얼굴은 주름 4종 건너뜀(마리오네트는 바깥 입술만 있으면 동작), 얼룩 고르기·붉은기·번들거림은 대체 타원 마스크로 동작, 몸 피부는 얼굴 없으면 건너뜀 | 단계 테스트 |
| 대상 얼굴 | 고른 얼굴만 바뀌고 다른 얼굴은 한 픽셀도 안 바뀜(피부 정밀), 몸 피부는 대상 얼굴과 무관 | `SkinStageTests`, `BodySkinStageTests` |
| 몸 피부 | 인물 마스크 안 피부만, 마스크 밖 같은 바이트, 얼굴 피부 영역은 매끄럽게 제외, 톤 +는 R−B 증가, 얼굴이나 인물 마스크가 없으면 항등 | `BodySkinStageTests` |
| 회귀 | `smoothing`만 있는 레시피의 바이트가 G 전후 같음, 단계 이름 배열, 캐시 항목 수 | `SkinStageTests`, `RenderPipelineTests`, `RegionMaskCacheTests` |
| 효과 | 같은 입력 두 번 렌더가 같은 바이트(결정적), 그레인이 평균 밝기를 ±1 안에서 유지, 글로우가 밝은 영역을 더 올림 | `EffectStageTests` |
| 앱 | 탭·슬라이더가 실행 취소 한 단계, 피부톤 안내·켜짐 규칙, 동기화 메뉴 상태와 적용, 비교 모드(기존 토글 동작 불변·분할 켜고 끄기·분할선 클램프·선택 시 초기화·두 모드 상호 배타), 문구 | `AppModelTests`, `CompareDividerTests` |
| 시나리오 | 데모 사진: 다크서클 → 얼룩 고르기 → 피부 밝기 → 그레인 → 전체 토글 → 분할 비교 → 선택 동기화(색감만) → 저장 성공 | `EditorScenarioTests` |

### 3. VALIDATION.md 항목 (G3 마지막 Task가 씀)

`## 인물 보정 G (2026-10-20)` 절: 자동 검증(명령·종료 코드·테스트 수), 자동 테스트가 확인하는 것(위 표 요약), 구현 중 측정(몸 피부 매끄럽게 48MP 저장 시간), 스펙과 다르게 한 것, 미검증(실사진 7종 품질·몸 피부 번짐·주름 띠 위치(특히 마리오네트)·뒷모습 사진에서 몸 피부가 빠지는 것·분할 비교 손잡이·동기화 메뉴 폭·실기기). 수행하지 않은 검증을 통과로 쓰지 않는다. 배포는 하지 않았다고 적는다.

### 4. 계획 분할

| 계획 | 파일 | 주요 Task |
|---|---|---|
| G1 | `docs/superpowers/plans/2026-10-20-beauty-g1-skin-refinement.md` | 레시피 `skin` 키 7개·스키마, 편집 변경·`applyAuto`, 주름 띠 마스크 4종, 주름 밝히기 커널, 대역 합성 확장(얼룩·번들거림), 붉은기, `SkinStage` 통합·대상 얼굴, 뷰티 피부 탭 |
| G2 | `docs/superpowers/plans/2026-10-20-beauty-g2-body-skin.md` | 레시피 `bodySkin`, 편집 변경, 인물 마스크 분리·`ToneShift.blueness`, `BodySkinStage`, 파이프라인 연결·캐시 상한, 뷰티 피부톤 탭 |
| G3 | `docs/superpowers/plans/2026-10-20-beauty-g3-effects-workflow.md` | 레시피 `effects`, `EffectStage`·연결, 조정 패널 효과, `SyncCategory`·선택 동기화, 분할 비교, 문서·VALIDATION |

세 계획은 G1 → G2 → G3 순서로 같은 브랜치에서 실행한다. 각 계획의 첫 Task는 앞 계획이 머지된 상태에서 시작한다.
