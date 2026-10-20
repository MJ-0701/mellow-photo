# 인물 보정 H (사람별·성별 그룹 보정) 설계

작성 2026-10-20. 선행: [인물 보정 B~F](2026-10-15-beauty-b-to-f-design.md), [인물 보정 G](2026-10-20-beauty-g-evoto-design.md). 근거: [Evoto 기능 역공학 분석](../../research/2026-10-20-evoto-analysis.md). 기준 코드: `beauty-g-evoto`에서 G1~G3이 모두 머지된 상태(이 문서를 쓰는 시점에는 G1 진행 중, `dcdf766`).

사용자 요구(원문): "사람이 한명씩 지정이 가능 해야하고 또 남자랑 여자가 각각 지정이 돼서 다 따로따로 보정이 가능해야 한다 함". 지금은 `recipe.portrait` 값 묶음 하나를 `targetFace`로 모든 얼굴 또는 한 얼굴에 거는 구조라, 사람 A와 B가 다른 값을 가질 수 없고 성별 개념이 없다.

## 사람이 확인할 것

### 결정

"사용자 결정"은 사용자가 확정한 것이다. 2026-10-20에 네 가지 질문(자동 추정 모델 미룸, 동기화 때 개인 덮어쓰기 제거, 체형·몸 피부 범위 밖, 생성 사진 저장소 보관)에 모두 권고안대로 답했고, 아래 표에 그대로 반영했다. 남은 선택 항목은 없다.

| 결정 | 이유 | 바꾸면 비용 |
|---|---|---|
| 값은 세 층으로 겹친다: **전체 → 성별 그룹(남성·여성) → 개인**. 위 층이 아래 층을 **키 단위**로 덮어쓰고, 층에는 사용자가 그 층에서 바꾼 키만 저장한다 | Evoto와 같은 조작 모델. 키 단위라 "모두 피부 0.3, B만 0.6"을 해 둔 뒤 전체의 자동 잡티를 켜면 B도 따라온다(묶음 단위면 B의 피부 묶음이 통째로 얼어붙음). 바꾼 키만 저장하니 "상속 중/덮어씀"을 화면에 그대로 보일 수 있다 | **큼** (파일 형식·렌더·편집 규칙 전부) |
| 성별은 **자동 추정이 기본**이고, 추정이 안 되면(신뢰도 낮음·모델 없음·작은 얼굴·옆얼굴·틀린 결과) 사용자가 사람마다 **수동 지정**한다. 수동이 자동보다 우선이고 재분석이 수동을 덮지 않는다. 미지정인 사람은 그룹 값을 받지 않고 전체 값과 개인 값만 받는다. 수동 지정 화면은 H 필수 | 사용자 결정("자동으로 안되면 사용자가 수동으로"). 수동 지정은 레시피에, 자동 추정은 분석 결과에 두므로 분석을 다시 해도 수동 값이 남는 것이 구조로 보장된다 | 작음 |
| **자동 추정 모델은 H1~H3에서 만들지 않고 포트(`GenderEstimator`)만 둔 채 H4로 미룬다.** H1~H3에서는 모든 사람이 미지정으로 시작해 사용자가 지정한다 (사용자 결정) | Vision에는 성별 분류기가 없다. 공개 Core ML 후보는 크기 10~90 MB, 데이터셋 라이선스(연구용 전용인 것이 많음) 확인, 피부톤·나이·옆얼굴 편향 평가, 앱 스토어·개인정보 문구 검토, 그리고 MellowRendering에 CoreML import를 허용하는 모듈 표 변경이 필요하다. 핵심 요구("각각 지정해 따로 보정")는 수동만으로 충족되고 위험이 0이다. 모델은 라벨 있는 생성 사진으로 정확도를 재 본 뒤 넣을지 정하는 편이 안전하다 | 중간 (H4를 하면 모듈 표·스크립트 변경) |
| 사람의 식별 키는 얼굴 인덱스가 아니라 **정규화 얼굴 상자의 중심과 폭(`anchor`)**이다. 다시 분석할 때마다 저장된 anchor와 찾은 얼굴을 거리(얼굴 폭의 50% 이내, 크기 비 2배 이내)로 1:1 짝짓는다. 짝이 없는 사람의 값은 **버리지 않고 렌더에서만 빠지며** 화면에 "사진에서 찾지 못함"으로 보이고 다른 얼굴에 다시 연결하거나 지울 수 있다 | 인덱스는 얼굴 수가 하나만 달라져도 옆 사람에게 값이 붙는다. 좌표는 원본 기준 정규화라 미리보기·원본 해상도·자르기·회전과 무관하고, 같은 사진은 Vision이 거의 같은 상자를 주므로 50% 오차면 충분하다. 얼굴 임베딩은 Vision에 공개 API가 없어 과하다 | **큼** (파일 형식) |
| `portrait.targetFace`는 **쓰지 않고 읽기만** 한다. 옛 레시피의 `targetFace = i`는 읽을 때 "전체 층은 비우고, 지금 값 전부를 i번째 사람의 개인 층으로" 옮긴다(anchor 없이 `legacyIndex`로 두고, 사진을 준비한 뒤 처음 편집할 때 anchor를 채움). `schemaVersion`은 2 유지 | 옛 의미("이 값을 i번 얼굴에만")와 렌더 결과가 같다. 키 추가·읽기 전용 이행은 B~G의 `skinSmoothing`·`faceSlim`과 같은 규칙이라 v3가 필요 없다. v1 세션(`selectedFace`)도 같은 길로 들어온다 | 중간 (플랫폼 공통 계약) |
| "지금 어느 대상을 편집 중인가"(전체·남성·여성·사람 n)는 **앱 세션 상태**이고 파일에 저장하지 않는다. 사진을 바꾸면 그 사진의 마지막 대상을 기억하되 앱을 다시 열면 전체 | 렌더 결과에 영향이 없는 화면 상태다. `targetFace`를 레시피에 두던 것은 렌더를 바꾸는 값이었기 때문이고 H에서는 그 역할이 사라진다 | 작음 |
| 프리셋과 "전체 사진에 적용"(G3 선택 동기화)은 **전체 층과 성별 그룹 층만** 나른다. **개인 층과 성별 지정은 복사하지 않는다.** 얼굴 의존 항목(피부·얼굴형·눈입·메이크업)을 동기화하면 받는 사진의 **그 항목 개인 덮어쓰기를 지운다**(G3의 "대상 얼굴을 전체로 되돌림" 규칙을 승계). 성별 지정은 남긴다 (사용자 결정) | 같은 사람을 사진 사이에서 알아볼 수 없다. 동기화한 항목은 받는 사진에서 원본 사진과 같아 보여야 하는데 개인 덮어쓰기가 남으면 그 사람만 다르다. 성별 그룹 값은 사진이 달라도 뜻이 같으니 나른다 | 작음 |
| **G3는 지금 바꾸지 않는다.** H가 `EditDocument.merged`·`applyFromBatch` 안의 `targetFace` 처리와 테스트 하나를 바꾼다. `SyncCategory` 9종과 `dependsOnFaces`의 의미(얼굴 의존 항목 동기화 시 받는 사진의 개인 선택을 되돌림)는 그대로 쓴다 | 공개 API가 바뀌지 않고 바뀌는 코드는 한 함수 안이다. 지금 G3를 고치면 구현 중인 브랜치를 흔든다 | 작음 |
| H에서 사람별·성별이 되는 것은 **피부(정밀 7종·자동 잡티 포함)·얼굴형·눈입·메이크업**이다. 체형·몸 피부·배경·색감·효과는 사진 단위로 둔다. 사람별 체형은 나중 후보로 기록 (사용자 결정) | 네 가지는 이미 "대상 얼굴마다" 도는 단계라 값만 얼굴마다 다르게 주면 된다. 체형은 사람 한 명(가장 큰 사람)이고 얼굴–관절 짝짓기와 여러 사람 변형 간섭 문제가 따로 있다. 몸 피부는 인물 마스크가 사람을 구분하지 않는다 | 작음 (나중 확장 가능) |
| 렌더는 **얼굴마다 해석한 값**(`FaceTarget`)으로 기존 네 단계가 그대로 돈다. 새 단계·새 마스크·캐시 변경 없음 | 단계는 이미 얼굴마다 반복한다. 얼굴마다 값이 다르면 반복 안의 값만 바뀐다. 다각형 비트맵 캐시 키는 다각형이라 영향 없음 | 작음 |
| 성별 지정 변경과 얼굴형 키의 재설정은 수동 편집 잠금 대상이다 | 성별이 바뀌면 그룹의 얼굴형 값이 다른 얼굴에 걸려 수동 편집 좌표가 어긋난다(기존 `targetFace` 잠금과 같은 이유) | 작음 |
| 자동 보정은 전체 층에만 쓴다 | 지금과 같다. 그룹·개인 층은 사용자가 고른 값이다 | 작음 |
| 화면: 뷰티·메이크업 패널 맨 위 얼굴 피커를 **대상 칩**(전체 · 남성 · 여성 · 사람 1…n)으로 바꾼다. 사람 칩에는 성별 메뉴(남성/여성/미지정, 자동이면 "추정" 배지)가 있고, 전체가 아닌 대상에서는 덮어쓴 슬라이더에 표시와 "재설정"이 붙는다. 뷰티·메이크업 도구에서 캔버스의 얼굴을 탭하면 그 사람이 대상이 된다 | Evoto의 핵심 조작(얼굴 클릭 → 그 사람 값). 상속 중인 값과 덮어쓴 값을 구분해 보여야 "왜 이 값인가"를 알 수 있다 | 작음 |
| 테스트 사진은 **codex CLI로 만든 가상의 커플·단체 사진**이다. 커플 1장 이상(남 1·여 1), 단체 1장 이상(4~6명, 남녀 혼합), 피부톤·나이·안경·옆얼굴·가림을 섞고, 사진마다 왼쪽부터 인원·성별 정답 라벨(JSON)을 둔다. 자동 테스트의 1차 근거는 기존 `SyntheticFace`이고 생성 사진은 시나리오·수동 확인·성별 추정 정확도 측정용 | 사용자 결정("가상의 단체사진과 커플사진을 만들어서 테스트"). 실존 인물을 닮지 않은 가상 인물만 만든다. 생성 사진에서 Vision 얼굴·특징점이 실사진과 다르게 동작할 수 있어 1차 근거로 삼지 않는다 | 작음 |
| 생성 사진은 긴 변 1024px JPEG로 `shared/fixtures/people/`에 두고(합계 5 MB 이내, 출처·사용 조건 README 포함), 테스트 타깃에는 시나리오 테스트가 쓰는 2장만 복사한다 (사용자 결정) | 지금 `demo-portrait.png` 2.4 MB가 두 곳에 있는 것과 같은 방식. 전부 복사하면 저장소가 두 배로 는다 | 작음 |

### 범위

| 묶음 | 들어가는 것 |
|---|---|
| H1 레시피 | `Gender`·`PortraitLayer`·`PersonRecord`·`PeopleAdjustments`, 값 해석(`PortraitResolver`), 사람 짝짓기(`PersonMatcher`), `targetFace` 읽기 이행, 스키마·README·v1 픽스처 테스트 |
| H2 규칙·렌더 | 대상 층을 지정하는 편집(`set(_:in:)`·재설정·성별 지정·연결), 잠금, 프리셋·동기화의 층 규칙, `FaceTarget`, `GenderEstimator` 포트(구현 없음), 네 단계의 얼굴별 값 |
| H3 화면·검증 | 대상 칩, 성별 메뉴, 덮어쓰기 표시·재설정, 캔버스 얼굴 탭, 생성 사진 세트와 라벨, 시나리오 테스트, VALIDATION |
| H4 자동 추정 (선택) | Core ML 성별 추정기, 라벨로 정확도 측정, 모듈 표 CoreML 허용, "추정" 배지 동작 |

### 범위 밖

사람별 체형·몸 피부(나중 후보: 얼굴–관절 짝짓기, iOS 17 `VNGeneratePersonInstanceMaskRequest`로 사람별 인물 마스크), 사진 사이에서 같은 사람 알아보기(얼굴 임베딩), 나이·표정 추정, 개인 층의 프리셋 저장, 편집 대상의 영속화, 성별 외 그룹(어린이 등), 1.3.0 배포 준비.

### 위험과 대응

- **자동 추정은 틀릴 수 있고 민감하다.** 피부톤·나이·옆얼굴에서 정확도가 떨어진다는 보고가 많다. 대응: H1~H3은 수동만, H4는 라벨 있는 생성 사진으로 측정한 뒤 결정. 추정값은 늘 "추정" 배지와 함께 보이고 한 번의 탭으로 고칠 수 있다. 기기 안에서만 계산하고 저장하지 않는다(`PrivacyInfo.xcprivacy` 변경 없음).
- **짝짓기 실패.** Vision 버전이 바뀌어 상자가 크게 움직이거나 얼굴이 가려지면 사람을 못 찾는다. 대응: 값은 보존하고 렌더에서만 빼며 화면에서 다시 연결·삭제할 수 있다. 인덱스가 아니므로 다른 사람에게는 절대 붙지 않는다.
- **옛 세션 이행.** `targetFace`가 있던 사진은 전체 층이 비고 개인 층에 값이 들어간다. 사용자는 "전체" 칩에서 값이 0으로 보이고 "사람 i" 칩에서 값을 보게 된다. 대응: 렌더 결과는 같고 README·VALIDATION에 적는다.
- **층이 셋이라 "왜 이 값인가"가 헷갈릴 수 있다.** 대응: 덮어쓴 키만 표시하고 나머지는 상속값을 그대로 보이며, 대상마다 "이 대상 초기화"가 있다.
- **생성 사진의 한계.** Vision이 생성 얼굴에서 특징점을 다르게 줄 수 있고, 인원 수가 의도와 다를 수 있다. 대응: 만든 사진은 눈으로 인원·성별을 확인한 뒤 라벨을 쓰고, 자동 테스트는 `SyntheticFace`가 1차 근거다. 실사진 확인은 VALIDATION의 사용자 조치로 남는다.
- **화면 품질과 조작감은 자동 테스트로 판정할 수 없다.**

### 사용자 조치

- H3 뒤 실제 커플·단체 사진으로 사람 칩·성별 지정·그룹 값·개인 값·동기화 결과 확인.
- H4를 한다면 후보 모델의 라이선스·배포 조건 최종 확인(법무 판단은 에이전트가 대신할 수 없음).

### 돈·시간·외부 효과가 있는 단계

- 생성 사진 만들기는 codex CLI의 이미지 생성을 쓰므로 OpenAI 사용량(비용)이 든다. 6~10장 규모다.
- 푸시·태그·TestFlight·릴리스 노트는 H 범위가 아니며 어느 계획에서도 실행하지 않는다.

## 에이전트 참조

### 1. 공통 구조

#### 1.1 모듈 배치 (`docs/architecture/modules.md` 규칙 준수, H1~H3은 의존성 표 변경 없음)

| 새 타입·변경 | 모듈·폴더 | 설명 |
|---|---|---|
| `Gender`, `PersonID`, `PersonAnchor`, `PortraitKey`, `PortraitLayer`, `PersonRecord`, `PeopleAdjustments` | MellowShared/API (`PeopleAdjustments.swift`) | 층 값·사람 기록 |
| `PortraitResolver`, `PersonMatcher`, `PersonMatching` | MellowShared/API (`PortraitResolver.swift`, `PersonMatcher.swift`) | 순수 계산. 렌더·편집·앱이 같은 함수를 쓴다 |
| `EditRecipe.people`, `targetFace` 읽기 이행, `PresetValues.people` | MellowShared/API | 레시피 확장 |
| `PortraitScope`, `EditChange.personGender`, `EditDocument.set(_:in:)`·`resetOverrides`·`person(at:)`·`rebindPerson`·`removePerson`·`bindLegacyPeople`·`overriddenKeys` | MellowEditing/API | 층을 지정하는 편집 규칙 |
| `FaceTarget`, `RenderContext.faceTargets`, `PhotoAnalysis.genderEstimates`, `GenderEstimator`·`GenderEstimate`, `PreparedPhoto.genders`, `RenderTuning` 상수 3개 | MellowRendering/API | 얼굴별 값과 추정 포트 |
| `SkinStage`·`FeatureStage`·`MakeupStage`·`ShapeWarpStage` 반복문 | MellowRendering/Domain | `targetFaces` 대신 `faceTargets` |
| `CoreMLGenderEstimator` (H4만) | MellowRendering/Infrastructure | H4에서 모듈 표의 Rendering 행에 CoreML을 더하고 `verify-modules.sh`도 같은 커밋에서 고친다 |
| `TargetChips`, `PersonGenderMenu`, `AdjustmentSlider` 덮어쓰기 표시, `AppModel.portraitScope`, `PhotoInfo.genders`, 캔버스 얼굴 탭 | 앱 타깃 | 화면 |

새 프레임워크 import 없음(H4 제외). `MellowRendering`은 `MellowEditing`을 모르므로 해석·짝짓기는 MellowShared에 둔다.

#### 1.2 레시피 확장 (schemaVersion 2 유지, 키 추가 + `targetFace` 읽기 전용화)

```json
"portrait": { "skin": {…}, "face": {…}, "features": {…} },
"makeup":   { … },
"people": {
  "groups": {
    "male":   { "skin": { "smoothing": 0.2 } },
    "female": { "skin": { "smoothing": 0.5, "darkCircles": 0.3 }, "makeup": { "lookID": "daily", "lip": { "colorID": "lip-rose", "intensity": 0.5 } } }
  },
  "individuals": [
    { "id": "UUID", "anchor": { "x": 0.31, "y": 0.62, "width": 0.12 }, "gender": "female",
      "layer": { "face": { "width": -0.3 }, "features": { "eyeBrighten": 0.4 } } },
    { "id": "UUID", "legacyIndex": 1, "layer": { "skin": { "smoothing": 0.3 }, "face": { "width": -0.2 } } }
  ]
}
```

- `portrait`·`makeup`은 그대로 **전체 층**이다(빽빽한 값, 기본값 = 항등). `portrait.targetFace`는 더 쓰지 않는다(스키마 `deprecated: true`, 읽기 전용).
- **층(`PortraitLayer`)은 성긴 값**이다. 있는 키만 덮어쓰고 없는 키는 아래 층을 상속한다. 모양은 전체 층의 `portrait`·`makeup`과 같은 중첩이되 모든 잎이 선택이다. 메이크업은 **부위 단위**로 덮어쓴다(`lip` 객체가 있으면 색과 강도를 함께 덮어씀, `colorID`가 없거나 null이면 "색 없음"으로 덮어씀). `lookID`는 그 층에서 마지막으로 적용한 룩 이름이고 부위를 바꾸면 지운다(기존 규칙).
- `individuals[]`: `id`(UUID 문자열, 편집이 사람을 가리키는 키), `anchor`(정규화 얼굴 상자 중심 `x`·`y`와 폭 `width`, 원점 왼쪽 아래, 원본 기준), `legacyIndex`(옛 `targetFace`에서 온 기록만, anchor가 채워지면 지움), `gender`(**수동 지정만**, 없으면 미지정), `layer`. anchor와 legacyIndex 중 하나는 있어야 한다.
- 자동 추정 성별은 레시피에 쓰지 않는다. 얼굴과 같이 분석 결과(`PhotoAnalysis`)이고 영속화하지 않는다. 그래서 다시 분석해도 수동 지정이 덮이지 않는다.
- **읽기 이행**: `EditRecipe.init(from:)`가 `portrait` 컨테이너의 `targetFace`를 따로 읽어(`PortraitAdjustments`는 더 이상 이 키를 갖지 않음) 값이 있고 `people.individuals`가 비어 있으면 (1) `portrait.skin/face/features`와 `makeup` 중 기본값과 다른 키 전부를 성긴 층으로 만들고 (2) `individuals = [PersonRecord(id: 새 UUID, legacyIndex: i, layer: 그 층)]`, (3) `portrait`·`makeup`을 기본값으로 둔다. `targetFace`가 범위 밖이었다면(렌더가 빈 대상이던 상태) 그대로 옮긴다(짝이 없는 사람 = 렌더 안 함, 옛 결과와 같음). 옮길 값이 하나도 없으면(모두 기본값) 기록을 만들지 않는다. 실행 취소 기록의 레시피도 같은 디코더를 거치므로 함께 이행된다. 이행으로 만든 기록의 id는 인덱스에서 결정적으로 만든다(`PersonID.legacy(index:)` = `B0000000-0000-0000-0000-` 뒤 12자리 인덱스). 그래서 같은 파일을 두 번 읽어도 같고, 실행 취소 기록의 레시피와 현재 레시피가 내용이 같으면 `==`도 같다(체크포인트 중복이 생기지 않는다).
- **적용 순서**: H1은 `people`을 더하기만 하고(렌더·편집 동작 불변, `targetFace`는 그대로), H2가 렌더·편집이 `people`을 읽게 한 뒤 마지막 Task 하나에서 `targetFace` 읽기 이행·속성 제거·앱 최소 변경을 한 번에 한다(그 사이 어느 커밋에서도 옛 세션의 렌더 결과가 바뀌지 않는다).
- `EditRecipe.dependsOnFaces = portrait.dependsOnFaces || makeup.hasEffect || people.hasEffect`. `people.hasEffect`는 어느 층이든 기본값과 다른 값이 하나라도 있으면 true(성별 지정만 있는 기록은 false).
- `isDefault`는 그대로(`people`이 비면 기본). 빈 기록(성별 없음·층 비움)은 편집 규칙이 변경 뒤 지운다(1.4).
- `allValuesFinite`에 모든 층의 숫자 포함.
- `PresetValues.people`: `groups`만 담는다. `init(of:)`가 `individuals`를 버리고 인코드도 `groups`만 쓴다. 디코드에서 `individuals`가 와도 무시한다.
- `shared/recipe-schema/edit-recipe.v2.schema.json`: `people` 추가(`groups`는 `male`·`female` 키의 층, `individuals`는 위 필드, 층 스키마는 `$defs/portraitLayer` 하나로 두고 `additionalProperties: false`), `portrait.targetFace`에 `deprecated: true`와 이행 설명. `session-file.v2.schema.json`의 프리셋 `values`에 `people`(`groups`만) 추가. README의 v2 요점·v1 변환 표(`selectedFace` → `people.individuals[0].legacyIndex`)·"키를 추가할 때의 규칙"에 H 항목 추가.
- 다른 플랫폼: 같은 키·기본값. 라벨·anchor 좌표계는 기존 규칙(방향 보정 이미지 기준 정규화, 원점 왼쪽 아래).

#### 1.3 MellowShared 타입과 순수 계산

```swift
public enum Gender: String, Codable, CaseIterable, Sendable { case male, female }

public struct PersonID: Hashable, Codable, Sendable { public let rawValue: UUID; init(); init(rawValue:); static func legacy(index: Int) -> PersonID }   // PhotoID와 같은 틀

/// 편집·화면이 가리키는 층. 값 타입이라 MellowShared에 둔다(Editing·Rendering·앱이 함께 씀).
public enum PortraitScope: Hashable, Sendable { case all, gender(Gender), person(PersonID) }

public struct PersonAnchor: Codable, Equatable, Sendable { public var x: Double; public var y: Double; public var width: Double
    public init(faceBox: NormalizedRect)   // 중심과 폭
}

/// 층이 덮어쓸 수 있는 키. 편집·화면이 같은 이름을 쓴다.
public enum PortraitKey: Hashable, Sendable {
    case skinSmoothing, autoBlemish
    case skinRefinement(SkinRefinementKey), faceShape(FaceShapeKey), feature(FeatureKey)
    case makeupPart(MakeupPart)
    public var isFaceShape: Bool
}

public struct PortraitLayer: Codable, Equatable, Sendable {
    public var skinSmoothing: Double?
    public var autoBlemish: Bool?
    public var skinRefinement: [SkinRefinementKey: Double]
    public var face: [FaceShapeKey: Double]
    public var features: [FeatureKey: Double]
    public var makeup: [MakeupPart: MakeupTint]      // 색 없는 부위는 colorID nil
    public var makeupLookID: String?
    public var isEmpty: Bool
    public var hasEffect: Bool                        // 기본값과 다른 값이 하나라도
    public var overriddenKeys: Set<PortraitKey>
    public var numericValues: [Double]
    public func applied(to portrait: inout PortraitAdjustments, makeup: inout MakeupAdjustments)
    public mutating func remove(_ keys: Set<PortraitKey>)
}

public struct PersonRecord: Codable, Equatable, Identifiable, Sendable {
    public var id: PersonID
    public var anchor: PersonAnchor?
    public var legacyIndex: Int?
    public var gender: Gender?        // 수동 지정만
    public var layer: PortraitLayer
    public var isEmpty: Bool          // gender == nil && layer.isEmpty
}

public struct PeopleAdjustments: Codable, Equatable, Sendable {
    public var groups: [Gender: PortraitLayer]
    public var individuals: [PersonRecord]
    public var hasEffect: Bool
    public var numericValues: [Double]
    public func person(_ id: PersonID) -> PersonRecord?
    public func personID(at anchor: PersonAnchor) -> PersonID?      // PersonMatcher.isMatch로 찾음
    public mutating func prune()                                     // isEmpty인 기록 제거
}
```

`PortraitLayer` 인코드는 중첩 객체(`skin`·`face`·`features`·`makeup`)로 하고 비어 있는 그룹 객체는 쓰지 않는다. 딕셔너리는 키 enum의 `rawValue`를 JSON 키로 쓴다(Swift 기본 `[Enum: T]` 인코딩은 배열이 되므로 직접 구현).

```swift
public enum PortraitResolver {
    public struct Resolved: Equatable, Sendable { public var portrait: PortraitAdjustments; public var makeup: MakeupAdjustments }
    /// 전체 ⊕ groups[gender] ⊕ person?.layer. gender가 nil이면 그룹 층을 건너뛴다.
    public static func resolve(_ recipe: EditRecipe, person: PersonRecord?, gender: Gender?) -> Resolved
    /// 수동 지정이 있으면 그것, 없으면 추정값.
    public static func effectiveGender(person: PersonRecord?, estimate: Gender?) -> Gender?
    /// 화면용. scope 층까지 겹친 값. person은 recipe.people에서 찾고 gender는 호출자가 유효 성별을 넘긴다.
    public static func resolve(_ recipe: EditRecipe, scope: PortraitScope, gender: Gender?) -> Resolved
    /// 화면용. 그 층에서 덮어쓴 키. .all은 빈 집합.
    public static func overriddenKeys(_ recipe: EditRecipe, scope: PortraitScope) -> Set<PortraitKey>
}

public enum PersonMatching {
    /// 중심 거리 허용치. 두 폭 중 큰 값에 대한 비율.
    public static let centerTolerance = 0.5
    /// 폭 비(큰 쪽 / 작은 쪽) 상한.
    public static let sizeRatioLimit = 2.0
}

public enum PersonMatcher {
    public struct Match: Equatable, Sendable { public var person: PersonID; public var faceIndex: Int }
    /// 1:1 탐욕 짝짓기. 후보 (사람, 얼굴) 쌍 중 거리 조건과 크기 조건을 만족하는 것을 거리 오름차순으로 고르며 이미 쓴 사람·얼굴은 건너뛴다.
    /// anchor 없는 기록(legacyIndex)은 그 인덱스의 얼굴이 남아 있으면 짝이 된다. 결정적이다(동률은 사람 배열 순서).
    public static func match(_ people: [PersonRecord], faces: [NormalizedRect]) -> [Match]
    /// 두 anchor가 같은 사람인지(거리·크기 조건).
    public static func isMatch(_ a: PersonAnchor, _ b: PersonAnchor) -> Bool
}
```

#### 1.4 편집 규칙 (MellowEditing)

```swift
public enum EditChange {  // 기존 케이스에 더함. targetFace 케이스는 H2 마지막 Task에서 제거
    case gender(Gender?)                     // 개인 scope에서만 뜻이 있다. affectsGeometry true
}

extension EditDocument {
    /// 얼굴 의존 케이스(skinSmoothing·autoBlemish·skinRefinement·faceShape·feature·makeupColor·makeupIntensity·gender)만 scope를 본다.
    /// scope가 .all이면 지금과 같이 전체 층을 쓰고, 그룹·개인이면 그 층의 키를 (같은 클램프로) 쓴다. 나머지 케이스는 scope를 무시한다.
    /// 개인 scope의 기록이 없거나 .gender를 개인이 아닌 scope에 보내면 .unknownPerson을 돌려주고 아무것도 하지 않는다.
    @discardableResult public mutating func set(_ change: EditChange, in scope: PortraitScope = .all) -> Rejection?
    /// anchor에 해당하는 기록이 있으면 그 기록에, 없으면 새 기록을 만들어 같은 변경을 쓴다(한 체크포인트). 찾은 얼굴을 처음 만질 때의 경로.
    @discardableResult public mutating func set(_ change: EditChange, forPersonAt anchor: PersonAnchor) -> Rejection?

    /// 그 층에서 keys를 지워 상속으로 되돌린다. nil이면 층 전체(개인은 성별 지정 유지). .all은 그 키를 기본값으로 둔다. 체크포인트 한 번.
    /// 잠긴 사진에서 얼굴형 키가 들어 있으면 .geometryLocked.
    @discardableResult public mutating func resetOverrides(_ keys: Set<PortraitKey>? = nil, in scope: PortraitScope) -> Rejection?

    /// 찾지 못한 사람을 다른 얼굴에 연결. 체크포인트 한 번. 얼굴형 키가 있고 잠겼으면 거절.
    @discardableResult public mutating func rebindPerson(_ id: PersonID, to anchor: PersonAnchor) -> Rejection?
    @discardableResult public mutating func removePerson(_ id: PersonID) -> Rejection?
    /// legacyIndex만 있는 기록에 faces[legacyIndex]의 anchor를 채운다. 체크포인트 없음. 바뀐 것이 있으면 true.
    public mutating func bindLegacyPeople(faces: [NormalizedRect]) -> Bool
    public mutating func applyMakeupLook(_ look: MakeupLook?, in scope: PortraitScope = .all)
}
```

- `Rejection`에 `unknownPerson` 추가.
- `affectsGeometry`: `.faceShape`, `.bodyShape`, `.gender`(그리고 제거 전까지 `.targetFace`).
- 모든 변경은 적용 뒤 `people.prune()`으로 빈 기록(성별 없음·층 비움)을 지운 다음 "값이 그대로면 체크포인트 없음" 비교를 한다. `anchor`를 받은 기록은 `legacyIndex`를 지운다.
- 층에 메이크업 색을 처음 고를 때의 기본 강도 규칙은 그 층 아래(전체 ⊕ 그룹, 그룹은 기록의 수동 성별 기준)를 겹친 값을 기준으로 한다.
- 그룹·개인 층의 값 변경도 "값이 그대로면 체크포인트 없음" 규칙을 따른다. 연속 변경(`beginContinuousChange`)은 scope와 무관하게 지금과 같다.
- `applyAuto`: 전체 층만(지금과 같음).
- `apply(_ values:)`(프리셋): `color`·`detail`·`background`·`body`·전체 층 `portrait`·`makeup`·`people.groups`를 덮어쓴다. 개인 층·성별 지정은 그대로. 잠긴 사진은 전체 층과 그룹 층의 얼굴형을 보존.
- `applyFromBatch(_:categories:)`(G3 위에): 고른 항목을 전체 층과 그룹 층에서 덮어쓴다. `categories` 중 `dependsOnFaces`인 항목은 **받는 사진의 모든 개인 층에서 그 항목의 키를 지운다**(`skin` → `skinSmoothing`·`autoBlemish`·`skinRefinement(*)`, `faceShape` → `faceShape(*)`, `features` → `feature(*)`, `makeup` → `makeupPart(*)`·`makeupLookID`). 성별 지정·anchor는 그대로. 잠긴 사진은 `faceShape`·`body`를 건너뛴다(G3 그대로). G3의 `merged(values, targetFace:, categories:)`에서 `targetFace` 인자가 사라지고 위 규칙이 들어간다.
- `isGeometryLocked`는 그대로. 잠긴 사진에서 scope 전환은 화면 상태라 막지 않는다.

#### 1.5 렌더 (MellowRendering)

```swift
public struct GenderEstimate: Equatable, Sendable { public var gender: Gender; public var confidence: Double }

/// 얼굴마다 성별을 추정한다. faces와 같은 순서·길이. 추정하지 못한 얼굴은 nil. 기본 구현은 H4.
public protocol GenderEstimator: Sendable {
    func estimate(_ image: CIImage, faces: [FaceGeometry]) throws -> [GenderEstimate?]
}

public struct FaceTarget: Sendable {
    public let index: Int
    public let face: FaceGeometry
    public let personID: PersonID?
    public let gender: Gender?                 // 유효 성별(수동 ?? 추정)
    public let portrait: PortraitAdjustments   // 해석된 빽빽한 값
    public let makeup: MakeupAdjustments
    public let blemishes: [BlemishSpot]        // 이 얼굴의 잡티
}
```

- `PhotoAnalysis.genderEstimates: [GenderEstimate?]`(기본 빈 배열). `PhotoPipeline.init(…, genderEstimator: (any GenderEstimator)? = nil)`. `prepare`가 얼굴 뒤에 추정을 돌리고 실패는 조용히 빈 배열(추정은 보조 정보라 `PreparedPhoto`에 실패 사유를 두지 않는다). 임계값은 준비 때 적용한다: 신뢰도 < `genderMinConfidence`, 얼굴 폭 < `genderMinFaceWidth`, |yaw| > `genderMaxYaw`면 nil. `PreparedPhoto.genders: [Gender?]`로 앱에 넘긴다.
- `RenderContext.init`이 `targetFaces`·`targetBlemishes` 대신 `faceTargets`를 만든다: `matches = PersonMatcher.match(recipe.people.individuals, faces: faces.map(\.boundingBox))` → 얼굴 i마다 `person = 짝이 된 기록`, `gender = PortraitResolver.effectiveGender(person:, estimate: genderEstimates[i]?.gender)`, `resolved = PortraitResolver.resolve(recipe, person:, gender:)`, 잡티는 `faceIndex == i`. 짝이 없는 기록은 어느 얼굴에도 들어가지 않는다. `faces`·`blemishes` 접근자는 유지. `targetFaces`는 제거하고 테스트를 `faceTargets.map(\.face)`로 옮긴다.
- 네 단계: `SkinStage`는 `faceTargets` 중 `clamped(target.portrait.skin).hasEffect`인 것만 돌고 자동 잡티는 그 얼굴의 `target.blemishes`로 `healSpots`를 만든다(`SourceRules` 얼굴별 구성은 그대로). `FeatureStage`·`MakeupStage`는 `target.portrait.features`·`target.makeup`. `ShapeWarpStage.facePrimitives`는 `target.portrait.face`. 각 단계의 "값이 없으면 입력 그대로" 조기 반환은 "어느 대상에도 효과가 없으면"으로 바뀐다.
- `renderOriginal`의 `dependsOnFaces` 검사는 레시피 속성이 바뀌므로 그대로 동작한다.
- 캐시: `RegionMaskCache` 키·상한 불변. `PreviewCache` 불변. 성능: 단계는 이미 얼굴마다 반복하므로 얼굴 6명 단체 사진의 비용은 지금 "모든 얼굴" 선택과 같다. 해석·짝짓기는 얼굴 수에 비례하는 산술이다.

| `RenderTuning` 상수 | 시작값 | 뜻 |
|---|---|---|
| `genderMinConfidence` | 0.75 | 이 미만 추정은 버림 |
| `genderMinFaceWidth` | 0.05 | 정규화 얼굴 상자 폭(이미지 폭 비율)이 이 미만이면 추정 안 함 |
| `genderMaxYaw` | 0.6 | 라디안. 이보다 돌아간 얼굴은 추정 안 함 |

#### 1.6 앱 화면

- `AppModel.BeautyTarget { all, gender(Gender), face(Int), person(PersonID) }` — `.face(i)`는 찾은 얼굴(기록이 있든 없든), `.person(id)`는 짝이 없는 기록. 얼굴 의존 변경은 `.face(i)`면 `set(_:forPersonAt: anchor(i))`, `.person(id)`면 `set(_:in: .person(id))`, 그룹·전체는 `set(_:in:)`으로 보낸다. `beautyTargets: [PhotoID: BeautyTarget]`(세션 상태), `beautyTarget`(선택 사진 기준, 기본 `.all`), `setBeautyTarget(_:)`. 사진을 지우면 항목도 지운다. 파일에 저장하지 않는다.
- `PhotoInfo.genders: [Gender?]`(`PreparedPhoto.genders`). `remember(_:_:)` 뒤 `session.edit`로 `bindLegacyPeople(faces:)`를 한 번 부른다(바뀐 것이 있을 때만 저장이 일어남).
- `personChips: [PersonChip]` — 찾은 얼굴마다 `{ faceIndex, personID?, effectiveGender, source(.manual/.estimated/.none), overriddenCount }`, 왼쪽부터. 뒤에 짝이 없는 기록 `{ personID, gender, overriddenCount, unmatched: true }`.
- `TargetChips`(새 파일 `Features/Editor/TargetChips.swift`): 가로 스크롤 칩 `전체` · `남성` · `여성` · `1`…`n`(성별 아이콘 + 번호, 미지정은 물음표) · 찾지 못한 기록(경고 아이콘). 덮어쓴 키가 있는 칩에는 점. 사람 칩 길게 누르기/`contextMenu`에 `PersonGenderMenu`(남성 · 여성 · 미지정, 추정이면 항목 옆 "추정" 표시)와 "이 대상 초기화", 찾지 못한 기록에는 "이 얼굴에 연결 → 얼굴 n" 하위 메뉴와 "삭제". 뷰티·메이크업 패널의 기존 `Picker`를 이것으로 바꾼다.
- 사람 칩을 처음 만질 때(성별 지정이나 슬라이더 변경) `AppModel`이 `document.set(change, forPersonAt: PersonAnchor(faceBox: faces[i].boundingBox))`로 보내 기록이 그때 만들어진다.
- 슬라이더: `AdjustmentSlider`에 `isOverridden: Bool = false`, `onReset: (() -> Void)? = nil`. scope가 `.all`이 아니면 패널이 `PortraitResolver.resolve(...)`의 값을 보이고 `overriddenKeys`에 든 키에 점과 "재설정"(컨텍스트 메뉴·Mac은 작은 x 버튼)을 붙인다. 패널 위에 안내 한 줄: 그룹이면 "전체 값을 바탕으로 바뀐 항목만 저장돼요", 개인이면 "전체·그룹 값을 바탕으로…". 메이크업 룩 칩은 scope 층의 `makeupLookID`를 선택으로 보인다.
- `faceAvailability`의 `noLandmarks` 판정은 scope가 가리키는 얼굴(전체·그룹이면 해당 얼굴 전부, 개인이면 그 얼굴)로 한다.
- 캔버스: `tool`이 `.beauty`·`.makeup`일 때 탭을 `touch(from:to:)`에서 받아 `outputTransform.toOriginal`로 바꾼 점이 들어 있는 가장 작은 얼굴 상자를 고르고 그 사람을 scope로 한다(얼굴 밖이면 `.all`). 비교 모드·렌더 중·자르기 화면에서는 지금처럼 막는다.
- `UserMessage`: `targetLabel`("대상"), `targetAll`("전체"), `genderMale`("남성"), `genderFemale`("여성"), `genderUnset`("미지정"), `personOrdinal(n)`("사람 n"), `genderEstimated`("추정"), `genderManual`("지정"), `overrideReset`("재설정"), `resetScope`("이 대상 초기화"), `personUnmatched`("사진에서 찾지 못함"), `rebindPerson`("이 얼굴에 연결"), `removePerson`("삭제"), `scopeHintGroup`, `scopeHintPerson`, `assignGenderHint`("성별을 지정하면 그룹 값이 적용돼요"). `faceCount`·`faceOrdinal`·`allFaces`는 쓰는 곳이 없어지면 지운다.
- `Theme`: 칩 높이·점 크기.

### 2. 테스트 전략

| 범주 | 확인 | 위치 |
|---|---|---|
| 레시피 | 층·기록 왕복, 없는 키는 상속(인코드에 안 나옴), `targetFace = i` 읽기 이행(전체 층 비고 개인 층에 값·legacyIndex), 범위 밖 `targetFace`, 실행 취소 기록도 이행, v1 픽스처(`selectedFace 1`, skin 0.3, faceSlim 0.2 → 개인 층 `smoothing 0.3`·`face.width −0.2`), `dependsOnFaces`·`hasEffect`·`allValuesFinite`, 스키마 키 집합(`people`·`$defs/portraitLayer`), 프리셋에 `groups`만, 딕셔너리 키가 rawValue | `MellowSharedTests`, `MellowLibraryTests/SessionFileMigrationTests` |
| 해석 | 전체 ⊕ 그룹 ⊕ 개인 키 단위, 미지정은 그룹 건너뜀, 메이크업 부위 단위·`colorID` null 덮어쓰기, `effectiveGender` 우선순위 | `PortraitResolverTests` |
| 짝짓기 | 같은 상자는 같은 사람, 얼굴 하나가 사라져도 나머지 유지(인덱스가 밀려도), 허용치 밖은 짝 없음, 크기 비 초과는 짝 없음, 1:1(두 기록이 한 얼굴을 다투면 가까운 쪽), legacyIndex 폴백, 결정적 | `PersonMatcherTests` |
| 편집 | scope별 set·클램프, 상속으로 재설정, 층 전체 초기화(성별 유지), 빈 기록 자동 제거, `person(at:)` 중복 방지, 성별 지정 잠금 거절, 얼굴형 키 재설정 잠금 거절, 실행 취소 한 단계, 프리셋이 개인 층·성별을 보존, 동기화가 그룹을 복사하고 얼굴 의존 항목의 개인 키를 지우며 성별·anchor 유지, `unknownPerson`, `bindLegacyPeople` | `MellowEditingTests`, `MellowLibraryTests/ProjectSessionTests` |
| 렌더 | 얼굴 셋 합성(`SyntheticFace` 셋을 가로로 배치): 개인 층만 바꾼 얼굴만 바뀌고 다른 두 얼굴은 같은 바이트, 그룹 층은 그 성별 얼굴만, 미지정 얼굴은 전체 값만, 짝 없는 기록은 어떤 얼굴도 안 바꿈, 자동 잡티가 얼굴별로 켜짐, 메이크업·얼굴형도 같은 검사, 추정 포트 스텁(신뢰도·폭·yaw 임계값), `faceTargets` 구성, 캐시 항목 수 불변, 기존 `targetFaces` 테스트 이식 | `RenderContextTests`, `SkinStageTests`, `FeatureStageTests`, `MakeupStageTests`, `ShapeWarpStageTests`, `PhotoPipelineTests` |
| 앱 | 칩 목록 구성(추정·지정·미지정·찾지 못함), scope 전환이 레시피를 바꾸지 않음, 사람 칩 첫 변경이 기록을 만들고 실행 취소 한 단계, 성별 메뉴, 재설정, 캔버스 탭 → scope, 사진 전환 시 scope 기억·삭제 시 제거, 잠금 안내, 문구 | `AppModelTests` |
| 시나리오 | 생성 사진 `couple-01`·`group-01`(실제 Vision): 얼굴 수가 라벨과 같은지(다르면 그 사진은 자동 시나리오에서 빼고 VALIDATION에 적음), 라벨대로 성별 수동 지정 → 여성 그룹 피부 0.5 → 사람 1 얼굴 폭 −0.3 → 동기화(피부만)로 다른 사진에 그룹 값 복사·개인 값 미복사 → 저장 성공 | `EditorScenarioTests`(macOS) |
| H4 | 라벨 대비 추정 정확도(사진별·전체), 임계값 아래 얼굴은 nil, 모듈 표·스크립트 | `GenderEstimatorEvaluationTests` |

### 3. 생성 사진 세트 (H3 Task)

- **도구**: codex CLI 0.158.0(`/Users/mj/.local/bin/codex`, image_generation 사용 가능) 또는 `codex:rescue` 스킬. 생성은 에이전트가 하되 결과마다 사람이 보듯 눈으로 확인한다(아래 절차).
- **구성(최소)**: `couple-01`(남 1·여 1, 정면, 실내), `couple-02`(남 1·여 1, 한 명 안경·한 명 45° 측면, 야외 역광), `group-01`(5명 남녀 혼합, 피부톤 세 가지 이상, 20대~60대, 정면 위주), `group-02`(6명, 한 명 옆얼굴·한 명 손이나 머리카락으로 일부 가림·어린이 1명 포함 여부는 선택), `group-03`(4명, 두 명이 겹쳐 서서 얼굴 일부 가림). 성별 추정과 사람 식별의 어려운 경우(작은 얼굴·옆얼굴·가림·안경·다양한 피부톤·나이)가 적어도 한 번씩 들어가게 한다.
- **프롬프트 제약**: 실존 인물·유명인을 닮지 않은 가상의 인물, 문자·워터마크 없음, 사진처럼 보이는 자연광, 얼굴이 긴 변의 5% 이상 크기, 생성 결과에 손가락·얼굴 왜곡이 있으면 다시 만든다.
- **확인 절차(필수)**: 결과 이미지를 열어 (1) 인원 수가 의도와 같은지, (2) 왼쪽부터 각 사람의 성별이 명확한지(모호하면 다시 만들거나 라벨에 `ambiguous: true`), (3) 실존 인물을 떠올리게 하지 않는지 확인한 뒤 라벨을 쓴다. 확인하지 않은 사진은 쓰지 않는다.
- **파일**: `shared/fixtures/people/<이름>.jpg`(긴 변 1024px, JPEG 품질 0.9, 장당 600 KB 이내, 합계 5 MB 이내), `shared/fixtures/people/labels.json`, `shared/fixtures/people/README.md`(생성 도구·모델·날짜·프롬프트 요지·"가상 인물이며 실존 인물과 무관"·저장소 안 테스트·데모·수동 확인 용도로만 사용·생성물의 권리와 사용 조건은 OpenAI 이용 약관을 따르며 최종 확인은 사용자 조치). 테스트 타깃 `apple/Tests/MellowRenderingTests/Fixtures/people/`에는 `couple-01.jpg`·`group-01.jpg`·`labels.json`만 복사하고 바이트 동일성 테스트를 둔다(`demo-portrait.png`와 같은 방식).
- **라벨 형식**:

```json
{
  "version": 1,
  "photos": [
    { "file": "couple-01.jpg", "people": [
        { "gender": "male",   "ageBand": "adult", "glasses": false, "pose": "frontal", "occlusion": "none", "ambiguous": false },
        { "gender": "female", "ageBand": "adult", "glasses": false, "pose": "frontal", "occlusion": "none", "ambiguous": false } ] }
  ]
}
```

`people`은 왼쪽부터(얼굴 상자 `minX` 오름차순, `VisionFaceAnalyzer.orderedLeftToRight`와 같음). `ageBand`는 `child`·`young`·`adult`·`senior`, `pose`는 `frontal`·`turned`·`profile`, `occlusion`은 `none`·`partial`.

- **용도**: H3 시나리오 테스트(얼굴 수 대조·수동 지정 흐름), 수동 확인(칩·메뉴·캔버스 탭), H4 정확도 측정(`정확도 = 추정이 라벨과 같은 얼굴 수 / 추정을 낸 얼굴 수`, 그리고 `추정 비율`을 함께 적음). Vision이 라벨과 다른 얼굴 수를 내는 사진은 자동 테스트에서 빼고 VALIDATION에 사진 이름과 수를 적는다.

### 4. VALIDATION.md 항목 (H3 마지막 Task가 씀)

`## 인물 보정 H (2026-10-XX)` 절: 자동 검증(명령·종료 코드·테스트 수), 자동 테스트가 확인하는 것(2절 요약), 옛 세션 이행 결과(전체 칩이 0으로 보이는 것 포함), 생성 사진 세트(장수·용량·Vision 얼굴 수가 라벨과 같은지 사진별 표), 스펙과 다르게 한 것, 미검증(실사진에서 칩·성별 지정·그룹 값·개인 값·동기화, iPhone 폭에서 칩 줄, 캔버스 탭 정확도, 자동 추정은 H4 전까지 "없음"). 수행하지 않은 검증을 통과로 쓰지 않는다. 배포는 하지 않았다고 적는다. H4를 하면 같은 절에 정확도 표(사진별·피부톤별·나이대별·자세별)를 더한다.

### 5. 계획 분할

| 계획 | 파일 | 주요 Task |
|---|---|---|
| H1 (4 Task, 더하기만) | `docs/superpowers/plans/2026-10-21-beauty-h1-recipe.md` | `Gender`·`PersonID`·`PersonAnchor`·`PortraitKey`·`PortraitLayer`, `PersonRecord`·`PeopleAdjustments`·`EditRecipe.people`·`PresetValues.people`·스키마 두 파일·README, `PortraitScope`·`PortraitResolver`, `PersonMatcher`·`PersonMatching`. `targetFace`는 건드리지 않는다 |
| H2 (5 Task) | `docs/superpowers/plans/2026-10-21-beauty-h2-rules-render.md` | `FaceTarget`·`RenderContext.faceTargets`·네 단계, `GenderEstimator`·`PhotoAnalysis.genderEstimates`·`PreparedPhoto.genders`·`RenderTuning` 3개, `EditChange.gender`·`set(_:in:)`·`set(_:forPersonAt:)`·`resetOverrides`·`rebindPerson`·`removePerson`·`bindLegacyPeople`·`applyMakeupLook(_:in:)`, 프리셋·동기화 층 규칙(G3 `merged` 변경), 마지막 Task에서 `targetFace` 읽기 이행·제거와 앱 최소 변경(임시 대상 피커) |
| H3 (4 Task) | `docs/superpowers/plans/2026-10-21-beauty-h3-app-validation.md` | 생성 사진 세트(codex CLI, 눈 확인, 라벨, README, 테스트 타깃 복사), `AppModel.BeautyTarget`·칩 모델·`PhotoInfo.genders`·legacy 연결·캔버스 얼굴 탭, `TargetChips`·`PersonGenderMenu`·슬라이더 덮어쓰기 표시·`UserMessage`·`Theme`, 시나리오 테스트·`modules.md`·VALIDATION·전체 검증 |
| H4 (선택, 4 Task) | `docs/superpowers/plans/2026-10-21-beauty-h4-gender-estimator.md` | 후보 모델 비교표(크기·라이선스·학습 데이터·편향 보고)와 사용자 승인 관문, Core ML 변환·번들·모듈 표 Rendering 행 CoreML 허용 + `verify-modules.sh`, `CoreMLGenderEstimator`(Vision `VNCoreMLRequest`로 얼굴 상자 잘라 추론), 라벨 정확도 측정·VALIDATION 표 |

네 계획은 H1 → H2 → H3 → (사용자 승인 뒤) H4 순서로 같은 브랜치에서 실행한다. 각 계획의 첫 Task는 앞 계획이 머지된 상태에서 시작한다. H1~H3 어디에서도 모델 파일을 더하거나 모듈 표를 바꾸지 않는다.
