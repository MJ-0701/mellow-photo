# 인물 보정 G5 (원터치 Evoto 보정 재조정·점 지우기·복구 결함 수정) 설계

작성 2026-10-21. 선행: [인물 보정 G4](2026-10-21-beauty-g4-one-touch-design.md)(머지, 1.4.0 TestFlight), [인물 보정 H](2026-10-21-beauty-h-per-person-design.md), [인물 보정 G](2026-10-20-beauty-g-evoto-design.md). 근거: Phase A 측정(`EvotoCalibrationTests`, 커밋 `c7b548b`, 로컬 전용 Evoto 전후 쌍 17개). 기준 코드: `beauty-g5` `c7b548b`(main `8accbf6` 위).

사용자 요구(원문): "Evoto 특유의 한번에 보정되는 성능이 안 나온다". 이전 요구: 자연스럽게, 과하지 않게.

이 문서는 G4 스펙을 대체하지 않는다. G4의 결정(매크로 + 표시, 세 층 쓰기, 자동 포함, 보이는 강도·자연스러움 두 방향 테스트)은 그대로이고, 이 문서는 표 값·경계·렌더 능력을 Evoto 실측에 맞춰 다시 정한다. 바뀌는 G4 결정은 G4 스펙 결정 표에 "(G5에서 변경)" 행으로 함께 적었다.

## 사람이 확인할 것

### 한 줄 결론

"표를 올리면 Evoto가 된다"는 전제는 측정과 맞지 않았다.
우리 기본 강도 0.6은 밝기와 중간·넓은 대역 평탄화에서 이미 Evoto보다 세다.
Evoto가 "한 번에 끝난" 느낌을 주는 차이는 점(주근깨·여드름 자국·땀 반사점) 제거이고, 우리는 점을 거의 지우지 못한다(크기 비 0.97, Evoto 0.59).
게다가 1.4.0 원터치는 자동 잡티 복제 원을 켜는데, 그 복제 원이 분홍 원반으로 보이는 결함이 있다.
그래서 G5는 (1) 점 지우기 렌더 능력을 새로 넣고, (2) 복제 복구 결함을 고치고, (3) 평탄화·밝기 표는 오히려 내린다.

### 측정 요약 (Evoto 피부 보정 계열 7쌍 중앙값, 폰 배율 1170px, 같은 픽셀)

| 차원 | 우리 0.6 | 우리 1.0 | Evoto | 판정 |
|---|---|---|---|---|
| 얼굴 피부 평균 ΔY(/255) | +2.4 | +3.9 | +1.9 | 이미 같거나 큼 |
| 몸 피부 평균 ΔY | +1.7 | +2.9 | +0.3 | 우리가 큼 |
| 어두운 점 크기 후/전 비 | 0.97 | 0.95 | 0.59 | **가장 큰 간극** |
| 밝은 점 비 | 0.99 | 0.99 | 0.63 | **큰 간극** |
| 중간 대역(0.6–3%) 분산 비 | 0.66 | 0.52 | 0.99 | 우리가 과하게 평탄 |
| 넓은 대역(3–12%) 분산 비 | 0.79 | 0.68 | 1.07 | 우리가 입체감을 지움 |
| 질감(<0.6%) 분산 비 | 0.74 | 0.64 | 0.67 | 비슷 |
| 다크서클 띠 ΔY(전용 도구 2쌍) | +11.0 | +16.1 | +8.0 | 1.0이 과함 |
| 팔자 띠 ΔY(전용 도구 2쌍) | +7.0 | +11.2 | +5.1 | 1.0이 과함 |

눈으로 본 것(스크래치패드 `g5/final/*.zoom.png`): Evoto는 점·반사점을 지우고 나머지는 거의 그대로다. 우리는 얼굴 전체가 약간 하얗고 평평해지며 점은 남고, 손등·턱 경계에 복제 원 두 개가 분홍 원반으로 보인다. 점 지우기 시제품(`calmNoClone`)은 주근깨 대부분을 지우고 질감을 남기지만 볼의 보라 얼룩은 남기고 콧구멍을 조금 밝힌다.

### 결정

"판정"이 붙은 행은 사용자가 자리를 비운 동안 코디네이터가 권고안대로 정했다. 틀렸을 때의 비용을 함께 적었다.

| 결정 | 이유 | 바꾸면 비용 |
|---|---|---|
| **밝기 과녁은 Evoto 원클릭(ai-skin-retouching 계열, 얼굴 피부 +1~3/255)**이고 change-skin-color(+17~21/255)는 과녁이 아니다 (판정 1) | change-skin-color는 어두운 피부를 밝은 피부로 바꾸는 별도 도구다. 자동으로 걸면 인물의 피부색을 바꾼다. 밝기를 원하면 "피부 밝기" 슬라이더로 올린다 | 작음 (표 값) |
| **점 지우기를 렌더 능력으로 신설한다**: `skin` 단계 안 첫 하위 단계 `SpotRemoval`(자동 잡티 복구 뒤, 주름 밝히기 앞), 고전 형태 연산(닫힘·열림 차이), 모공 대역 보존, 상대 깊이 상한, 콧구멍·눈꼬리·입꼬리 제외, 강도는 문턱을 움직임. 레시피 키 `portrait.skin.spots`(0…1) (판정 2) | 간극의 핵심이고 표로는 못 닫는다. 시제품이 어두운 점 0.97 → 0.75, 밝은 점 0.99 → 0.80을 질감 손실 없이 만들었다. 새 파이프라인 단계가 아니라 `skin` 안인 이유: 피부 마스크·대상 얼굴 반복·캐시를 그대로 쓰고, 주름 밝히기(곱셈)보다 앞에 와야 점이 함께 증폭되지 않으며, 단계 순서는 G 결정 표에서 "바꾸면 큼"이다 | **큼** (새 하위 단계·마스크·커널·테스트) |
| **평탄화를 내린다**: 매끄럽게 0.35/0.45/0.25 → 0.16/0.20/0.12, 얼룩 고르기 0.25/0.35/0.15 → 0.08/0.10/0.05, 몸 피부 밝기 0.15 → 0.08 (판정 3) | Evoto는 중간·넓은 대역을 거의 그대로 둔다(0.99·1.07). 우리 평탄화가 "뿌연" 느낌의 원인이다. 후보 측정: 중간 대역 0.66 → 0.75, 넓은 대역 0.79 → 0.90, 얼굴 ΔY +2.4 → +1.0 | 작음 (표 값) |
| **복제 복구를 색 맞춤 복구로 고친다**: 원본 패치의 질감(고주파)만 옮기고 밝기·색(저주파)은 대상 둘레 피부 고리 평균에 맞춘다. 수동 잡티(`operations`의 spot)도 같은 함수라 함께 고쳐진다. 잡티 검출은 피부 가장자리(마스크 < 0.9)와 길쭉한 영역(종횡비 > 2 또는 채움 비 < 0.4)을 거절한다 (판정 4a) | 지금 복제 원은 원본 위치의 밝기를 그대로 가져와 원반으로 보인다(1.4.0 출시 결함). 손등·턱 경계 오검출은 피부 다각형 가장자리의 그늘 선이 잡티로 잡힌 것이다 | 중간 (복구 식·검출 조건) |
| **원터치는 점 지우기가 들어오면 자동 잡티를 끈다**: 표의 `autoBlemish`는 세 성별 모두 `false`이고 층이 `false`를 **덮어쓴다**(상속이 아님) (판정 4b) | 1.4.0 세션의 전체 층에 `autoBlemish: true`가 남아 있어도 원터치를 다시 걸면 꺼져야 원반이 사라진다. 점 지우기가 같은 결함을 더 넓게 덮는다. 사용자가 세부 조정에서 자동 잡티를 켜면 고친 복구로 돈다 | 작음 (표 한 줄) |
| **다크서클·팔자 표를 내려 강도 1이 Evoto 전용 도구 × 1.3을 넘지 않게 한다**: 다크서클 0.55/0.6/0.5 → 0.42/0.45/0.38, 팔자 0.4/0.45/0.35 → 0.32/0.36/0.28 (판정 5) | 1.0이 Evoto 전용 도구의 1.6~2배다(+16.1 vs +8.0, +11.2 vs +5.1). 선형 추정 +10.1·+7.0이 상한 +10.5·+6.7 안이다 | 작음 (표 값, 미측정이라 하네스로 다시 잰다) |
| **강도 1 상한 배수는 Evoto × 1.3**이다. 하네스 경계(1절)와 수용 테스트 상한이 이 배수로 정해진다 (판정 6) | 0.6이 Evoto 크기면 비례로 1.0은 1.67배가 된다. 1.3배면 끝값이 Evoto가 가장 세게 보정한 쌍 근처에 머문다(어두운 점 Evoto 최강 0.52, 1.3배 경계 0.47). 그 너머는 Evoto 사진에도 없어 자연스러움 근거가 없다 | 작음 |
| **얼룩 색 고르기를 넣는다**: 새 키 `portrait.skin.chromaEvening`(0…1). 얼굴 폭 6% 흐림의 Cb·Cr이 12% 피부 가중 평균에서 벗어난 만큼을 되돌리고 휘도(Y)는 그대로 둔다. 기존 대역 합성 커널(`toneMix`)에 항을 더한다 (판정 7, 가능하다고 판단) | 볼의 보라·붉은 얼룩(얼굴 폭 5~10%)은 시제품이 남긴 간극이다. 선형 RGB에서 BT.601 역행렬로 Cb·Cr만 옮기면 Y가 정확히 보존되므로 고전 기법으로 된다. 기존 얼룩 고르기는 휘도까지 평평하게 해 쓸 수 없다. 시제품이 없어 표 시작값(0.5/0.5/0.35)은 하네스 실측으로 고친다. 자연 홍조(15% 이상)는 띠 밖이라 대부분 남는다 | 중간 (커널 인자·키 하나. 실측이 나쁘면 표 값 0으로 두고 키는 남긴다) |
| **ML 없이는 어려운 것은 범위 밖**: 남성 수염 그늘, 눈 밑 지방(부피), 재조명·입체 조각, 잔머리 정리 (판정 8) | 표·고전 기법으로 닫히지 않는다 | — |
| **남성 표는 더 절제하되 보정이 보여야 한다**: 점 지우기 0.75(여성·공통 1.0), 매끄럽게 0.12, 얼룩 고르기 0.05, 얼룩 색 고르기 0.35. 하네스 경계는 0.6에서 어두운 점 비 ≤ 0.80·≥ 0.85는 안 됨(보임 하한), 중간 대역 ≥ 0.85, 질감 ≥ 0.70, 피부 바뀐 비율 ≥ 0.15 | 사용자 결정("남자는 덜 매끄럽게"). 후보 calmMale 0.6은 점 0.80, 중간 대역 0.80, 질감 0.76, 피부 바뀐 비율 0.18이었다 | 작음 (표 값) |
| **점 지우기 강도는 깊이 문턱을 움직인다**: 강도 1에서 상대 깊이 0.8%부터 채우고 강도가 내려가면 시작 문턱이 2.0%까지 올라간다. 문턱을 넘은 점은 완전히 채운다(반쯤 남긴 유령 없음). 강도 0.3 아래는 채움 비율도 선형으로 준다 | 시제품은 보정 지도에 강도를 곱해 0.6에서 이미 포화했고 0.6과 1.0 차이가 없었다. "덜 세게"는 "얕은 점은 두고 깊은 점만"이어야 자연스럽다 | 작음 (상수) |
| **보정 지도를 유한 영역에서 만들고 중간 결과로 굳힌다**(`insertingIntermediate`), 굳혀도 얼굴 밖이 바뀌면 `RenderContext`에 선택 `Renderer`를 더해 부동소수 비트맵으로 굳힌다(대안, 같은 Task) | 시제품은 형태 필터와 전체 합성을 한 그래프로 렌더하면 영역 밖이 늘어난 픽셀이 됐다. 제품 단계는 Core Image 그래프 안이라 CIContext가 없다. 유한 extent + 중간 결과 굳히기가 먼저이고, "얼굴 상자 밖 바이트 불변" 단위 테스트가 실패하면 대안으로 간다 | 중간 (대안이면 `RenderContext` 생성자 인자 하나) |
| **하네스는 환경 변수로 막힌 채 두고 단언하지 않는다**. 경계는 (a) 하네스 결과 표를 VALIDATION에 옮겨 기록하고 (b) 데모·커플 사진에서 잴 수 있는 것은 `RealPhotoAcceptanceTests`에 단언으로 둔다(합성 점을 심어 회복률, 모공·질감 비, 원반 잔차, 중간·넓은 대역 비, 띠 ΔY 상한) | Evoto 이미지는 저장소에 넣을 수 없다. CI에서 도는 테스트는 저장소 안 사진만 쓴다 | 작음 |
| **원터치 보임 하한을 다시 정한다**(수용 테스트 `OneTouchVisibility`): 여성 0.6 ≥ 0.04, 남성·공통 0.6 ≥ 0.03, 여성 1 ≥ 0.08, 남성 1 ≥ 0.05, 남녀 차이 ≥ 0.015, 커플 ≥ 0.02 (판정, **사용자 확인 필요**) | 옛 하한(0.05/0.05/0.10/0.06/0.02/0.03)은 옛 표로 정했고 판정 3이 표를 내렸다. 보임의 본질은 G5에서 "점이 지워지고 피부가 +0.5/255 이상 밝아짐"이라 심은 점 회복률과 밝기 하한이 받친다. 실측이 옛 하한을 넘는 항목은 옛 하한을 유지하고, 내린 항목만 VALIDATION에 적는다 | 작음 (문턱은 테스트 상수 한 곳) |
| 다각형 비트맵 캐시 상한을 얼굴당 해상도마다 10 → 11 | 점 지우기 제외 영역(콧구멍 띠·눈꼬리·입꼬리) 비트맵 하나가 는다 | 작음 |
| `SkinKernels`는 커널 5 → 8(`heal`·`spot`·`spotApply` 추가, `toneMix`에 색 고르기 인자) | 피부 CIKL 색 커널은 한 곳 규칙 | 작음 |
| **얼굴형·체형 변형 코드는 건드리지 않는다**(조정 제약) | 다른 세션이 이중 턱·몸 윤곽을 같은 파일(`ShapeWarpStage`·`FaceShapeRig`·`BodyShapeRig`·`DisplacementWarp`·`ShapePrimitive`)에서 작업 중이다. G5는 `SkinStage`·`LocalEditStage.applySpot`·`BlemishDetector`·`FaceRegions`(제외 영역 추가만)·`SkinKernels`·`FrequencySeparation`·`RenderTuning`·Shared 레시피·테스트만 바꾼다 | — |
| 배포는 1.4.1 TestFlight. 버전 올림(`scripts/release.sh apple 1.4.1`)·푸시·태그는 코디네이터가 CI 통과 뒤 한다. 계획의 Task는 하지 않는다 | G4 규칙 | — |

### 범위

| 계획 | 들어가는 것 | 선행 |
|---|---|---|
| G5-1 복구 결함·표 | 색 맞춤 복구(`heal` 커널·`applySpot`), 잡티 오검출 거절, 표 값 인하(매끄럽게·얼룩 고르기·몸 밝기·다크서클·팔자), 중간·넓은 대역 비·띠 상한·색 분산 비 측정 도우미, 원터치 수용 테스트 재조정 | 없음(`c7b548b`) |
| G5-2 점 지우기 | 키 `skin.spots`, 제외 영역, `SpotRemoval`과 커널, 표의 `spots`·`autoBlemish false`, 심은 점 수용 테스트, 하네스에서 시제품 제거 | G5-1 |
| G5-3 얼룩 색 고르기·검증 | 키 `skin.chromaEvening`, `toneMix` 확장, 심은 보라 얼룩 수용 테스트, 하네스 실행과 결과 표, VALIDATION·문서 | G5-2 |

### 범위 밖

남성 수염 그늘 지우기, 눈 밑 지방 정리, 재조명·입체 조각(Evoto는 넓은 대역 분산을 7~41% 키운다), 잔머리 정리(모두 ML), 점마다 질감을 옮겨 심는 2세대 점 지우기(시제품이 Evoto 제거량의 60%이고 나머지는 국소 대비 정규화와 질감 이식이 필요), change-skin-color 수준의 피부 밝히기, 얼굴형·체형 변형(다른 세션), 사진별 자동 강도, 다른 플랫폼 구현.

### 위험과 대응

- **표본이 작다**(얼굴 있는 쌍 17, 피부 보정 계열 7, 원클릭 1). Evoto 홍보 사진이라 효과가 잘 보이는 쪽으로 골랐을 수 있다. 대응: 경계는 중앙값과 최소·최대를 함께 보고 정했고, 수용 테스트는 데모·커플 사진에서 따로 잰다.
- **다크서클·팔자·얼룩 색 고르기 값은 미측정 추정이다.** 대응: G5-3 하네스 실행으로 다시 재고 경계를 넘으면 표 값을 내린다(상한 우선 규칙).
- **점 지우기가 모공·수염·속눈썹 옆을 건드릴 수 있다.** 대응: 모공 대역(0.3% 닫힘)은 차이에서 빠지고, 상대 깊이 25~40%보다 깊은 구조는 건드리지 않으며, 눈·눈썹·입술 보호 영역에 콧구멍 띠·눈꼬리·입꼬리를 더한다. 심은 점 테스트가 콧구멍 띠·눈꼬리 불변을 단언한다.
- **점 지우기가 0.6에서 목표(어두운 점 비 ≤ 0.70)에 못 미칠 수 있다.** 시제품 실측은 0.75다. 대응: 하네스 경계는 0.6에서 ≤ 0.76(시제품 + 여유)이 합격선이고 0.70은 목표로 적는다. 못 미치면 `spotRadiusFraction`을 0.012 → 0.015로 올려 다시 재고, 그래도 안 되면 VALIDATION에 적는다.
- **원본 해상도 렌더 비용.** 형태 필터 8번(닫힘·열림 × 두 반지름)이 얼굴 영역에서 돈다. 대응: 얼굴 마스크 영역(`maskBounds` + 여유)으로 자르고 미리보기 긴 변 1600에서 잰다. 렌더 시간 측정은 VALIDATION에 적는다.
- **복구 식 변경이 수동 잡티 결과를 바꾼다.** 대응: 의도된 변경이다(같은 원반 결함). 합성 경사 테스트가 잔차 ≤ 1/255를 고정한다.
- **보임 하한을 내리는 판정.** 대응: 실측이 옛 하한을 넘으면 내리지 않는다. 내린 항목은 VALIDATION에 이유와 함께 적는다.
- **CI Xcode 26.3 타입 검사 시간.** 대응: 커널 인자 배열과 긴 식은 지역 상수로 나눈다(G4 교훈).

### 사용자 조치

- 판정 1~8과 "보임 하한 재조정" 판정을 확인한다(바꾸려면 알려 주기).
- 나란히 보기 PNG(스크래치패드 `g5/final/`)를 직접 본다: `blemish-removal_blemishRemover_section01_01_app.zoom.png`(원반 결함), 같은 이름 `calmNoClone`(후보), `ai-skin-retouching_section01_01_app.zoom.png`, `frequency-separation_frequencySeparation_section01_01_calmNoClone.zoom.png`(보라 얼룩 남음), `wrinkle-remover-for-face_section01_01_calmNoClone.zoom.png`(콧구멍).
- 1.4.1 TestFlight 뒤 기기에서: 주근깨·여드름 자국이 있는 사진에 원터치 → 점이 지워지고 원반이 없는지, 남성 사진에서 절제됐으되 보정이 보이는지, 세부 조정의 "점 지우기"·"얼룩 색 고르기" 슬라이더, 수동 잡티 복구에 원반이 없는지.
- Evoto 이미지와 하네스 출력은 로컬 전용이다. 저장소에 넣지 않는다.

### 돈·시간·외부 효과가 있는 단계

- 계획 안의 Task는 푸시·태그·TestFlight 업로드·버전 올림을 하지 않는다.
- 코디네이터가 세 계획 머지 뒤 CI 통과를 확인하고 `scripts/release.sh apple 1.4.1`·푸시·태그로 TestFlight에 올린다.
- 하네스 실행(G5-2·G5-3)은 Evoto 이미지가 있는 이 Mac에서만 약 16분이 든다. CI에서는 건너뛴다.

## 에이전트 참조

### 1. 경계

#### 1.1 하네스 경계 (Evoto 7쌍 중앙값, `EvotoCalibrationTests`, 단언하지 않고 VALIDATION에 기록)

지표 정의는 하네스 `metrics.md` 머리말과 같다(피부 마스크 가중, 원본 배율 대역, 1.2% 닫힘·열림 점, 0.3% 닫힘 모공).

| 차원 | 기본 0.6 | 강도 1 상한(Evoto × 1.3) | Evoto 근거(7쌍) |
|---|---|---|---|
| 얼굴 피부 평균 ΔY(/255) | +0.5 ~ +3.0 | ≤ +4.0 | 중앙값 +1.9, 75분위 +3.0 |
| 몸 피부 평균 ΔY | ≤ +1.5 | ≤ +2.5 | +0.3 |
| 어두운 점 비 | ≤ 0.76 (목표 0.70) | ≥ 0.47 | 0.59 |
| 밝은 점 비 | ≤ 0.80 (목표 0.75) | ≥ 0.52 | 0.63 |
| 중간 대역 비(0.6–3%) | ≥ 0.80 | ≥ 0.70 | 0.99(최소 0.81) |
| 넓은 대역 비(3–12%) | ≥ 0.85 | ≥ 0.80 | 1.07 |
| 질감 비(<0.6%) | ≥ 0.65 | ≥ 0.55 | 0.67(최소 0.57) |
| 모공 크기 점 비 | ≥ 0.90 | ≥ 0.85 | 0.62 (우리는 모공을 더 남긴다) |
| 다크서클 띠 ΔY(전용 2쌍) | +5 ~ +9 | ≤ +10.5 | +8.0 |
| 팔자 띠 ΔY(전용 2쌍) | +3 ~ +6 | ≤ +6.7 | +5.1 |
| 피부 Cr 표준편차 비 | ≥ 0.80 | ≥ 0.70 | 0.90 |
| 피부 평균 \|ΔCb\|·\|ΔCr\| | ≤ 1.5/255 | ≤ 2.0/255 | ΔCr −0.9 |
| 얼굴 상자 p99 \|ΔY\| | — | ≤ 25 | 17.9 |
| 배경 바뀐 비율 | ≤ 0.002 | ≤ 0.002 | (재압축 잡음 0.005~0.1) |
| 붉은 얼룩 비(redBl) | ≤ 0.90 | ≤ 0.80 | 0.98 (얼룩 색 고르기 효과를 보는 보조 지표) |

남성(`male` 계열): 밝기·주름 경계는 같다. 0.6에서 어두운 점 비 ≤ 0.80, 보임 하한으로 어두운 점 비 ≤ 0.85와 피부 바뀐 비율(skinChg) ≥ 0.15. 중간 대역 ≥ 0.85, 질감 ≥ 0.70.

#### 1.2 수용 테스트 경계 (데모·커플 사진, `RealPhotoAcceptanceTests`, 단언)

G4 1.2·1.4의 원터치 행을 다음으로 바꾼다. 다른 항목(슬라이더별 하한·상한)은 그대로다.

하한(`OneTouchVisibility`, 몸 피부 없이 얼굴만, 화면 배율 얼굴 상자 changedFraction):

| 항목 | 옛 문턱 | 새 문턱(실측이 옛 문턱을 넘으면 옛 문턱 유지) |
|---|---|---|
| 여성 0.6 | ≥ 0.05 | ≥ 0.04 |
| 남성 0.6 · 공통 0.6 | ≥ 0.05 | ≥ 0.03 |
| 여성 1 | ≥ 0.10 | ≥ 0.08 |
| 남성 1 | ≥ 0.06 | ≥ 0.05 |
| 여성 1 vs 남성 1 | ≥ 0.02 | ≥ 0.015 |
| 커플(남·여·미지정) | ≥ 0.03 | ≥ 0.02 |

상한·새 하한(`OneTouchNaturalness`, 몸 피부 포함 전체 대상 결과):

| 조건 | 측정 | 경계 |
|---|---|---|
| 기본 0.6(세 성별) | 얼굴 피부 마스크 평균 ΔY | +0.5/255 ≤ ΔY ≤ +3.0/255 (옛 1.275~12.75) |
| 강도 1 | 얼굴 피부 평균 ΔY | ≤ +4.0/255 (신설) |
| 기본 0.6 / 강도 1 | 피부 마스크 fine 분산 비 | ≥ 0.9 / ≥ 0.85 (그대로) |
| 기본 0.6 / 강도 1 | 피부 안쪽(가중치 ≥ 0.8) 중간 대역(fine 반지름 ~ 얼굴 폭 3%) 분산 비 | ≥ 0.80 / ≥ 0.70 (신설) |
| 기본 0.6 / 강도 1 | 피부 안쪽 넓은 대역(3% ~ 12%) 분산 비 | ≥ 0.85 / ≥ 0.80 (신설) |
| 강도 1 | 다크서클 띠 가중 평균 ΔY | ≤ +10.5/255 (신설) |
| 강도 1 | 팔자 띠 가중 평균 ΔY | ≤ +6.7/255 (신설) |
| 기본 0.6 / 강도 1 | 피부 가중 Cr 표준편차 비 | ≥ 0.80 / ≥ 0.70 (신설) |
| 강도 1 | 얼굴 상자 p99 \|ΔY\| | ≤ 60/255 (그대로. 하네스는 25) |
| 강도 1 | 피부 meanChromaDelta | ≤ 0.015 (그대로) |
| 강도 1 | 얼굴 밖·눈썹·입술·변형 | 그대로 |
| 모든 강도 | `SkinStage.healSpots(in:)`가 빈 배열 | 원터치 레시피는 복제 원을 만들지 않음 (G5-2부터) |

심은 결함(데모 사진, 실제 특징점, 선형 공간):

| 항목 | 결함 | 측정 | 경계 |
|---|---|---|---|
| 점 지우기 1 | 어두운 원 6개(반지름 얼굴 폭 0.9%, 휘도 × 0.85)와 밝은 원 3개(반지름 0.7%, 휘도 + 0.10), 피부 마스크 ≥ 0.9인 볼·이마 격자, 서로 얼굴 폭 8% 이상 | 원 안 가중 휘도 회복률 | 어두운 ≥ 0.7, 밝은 ≥ 0.6 |
| 점 지우기 1 | 같은 사진 | 원 밖 피부 fine 분산 비, 모공 크기 점 비(0.3% 닫힘 평균) | ≥ 0.9, ≥ 0.9 |
| 점 지우기 1 | 같은 사진 | 콧구멍 띠·눈꼬리·입꼬리 원 안 평균 \|ΔY\| | ≤ 1.0/255 |
| 점 지우기 1 | 같은 사진 | 얼굴 마스크 영역 밖 채널 차이 | ≤ 1바이트 |
| 원터치 0.6(여성·공통) | 같은 사진 | 어두운 원 회복률 | ≥ 0.6 |
| 원터치 0.6(남성) | 같은 사진 | 어두운 원 회복률 | ≥ 0.4, 여성보다 작음 |
| 자동 잡티 복구 | 턱 쪽 볼 경사면에 어두운 원 1개(반지름 1.2%, × 0.80)를 심고 잡티로 넘김 | 복구 뒤 원 안 평균 Y와 고리(반지름 1~1.5배) 평균 Y의 차 | ≤ 3/255 (원반 잔차 없음) |
| 수동 잡티 복구 | 합성 얼굴에 휘도 경사(왼쪽 0.4 → 오른쪽 0.6) + 원 | 복구 원 안 평균 Y − 고리 평균 Y | ≤ 1/255 (옛 복제는 경사 × 2.5r만큼 어긋남) |
| 얼룩 색 고르기 1 | 볼에 반지름 얼굴 폭 6% 원, 감마 Cb +0.04·Cr +0.03, Y 유지 | 원 안 \|ΔCb\|·\|ΔCr\| 제거율 | ≥ 0.5 |
| 얼룩 색 고르기 1 | 같은 사진 | 원 안 평균 \|ΔY\|, 피부 fine 비, 피부 중간 대역 휘도 비 | ≤ 1.5/255, ≥ 0.9, ≥ 0.95 |

문턱 수정 규칙은 G4와 같다: 상수를 고쳐 넘기고, 문턱을 내리는 것은 VALIDATION에 이유를 적고 사용자 승인을 받는다. 위 표의 "새 문턱"은 이 스펙의 판정으로 미리 승인된 범위다.

### 2. 표 (`OneTouchBundle.Table`, 강도 1 = 허용 상한)

| 항목 | 공통 | 여성 | 남성 | 변경 |
|---|---|---|---|---|
| skin.smoothing | 0.16 | 0.20 | 0.12 | 0.35/0.45/0.25에서 |
| skin.autoBlemish | false | false | false | true에서 (G5-2) |
| skin.spots | 1.0 | 1.0 | 0.75 | 신설 (G5-2) |
| skin.darkCircles | 0.42 | 0.45 | 0.38 | 0.55/0.6/0.5에서 |
| skin.nasolabial | 0.32 | 0.36 | 0.28 | 0.4/0.45/0.35에서 |
| skin.marionette | 0.25 | 0.3 | 0.25 | 그대로 |
| skin.glabella | 0.3 | 0.3 | 0.3 | 그대로 |
| skin.toneEvening | 0.08 | 0.10 | 0.05 | 0.25/0.35/0.15에서 |
| skin.chromaEvening | 0.5 | 0.5 | 0.35 | 신설 (G5-3, 시작값) |
| skin.redness | −0.2 | −0.25 | −0.2 | 그대로 |
| skin.shine | 0.45 | 0.4 | 0.5 | 그대로 |
| features.* · makeup.* | 그대로 | 그대로 | 그대로 | — |
| bodySkin.brightness(전체 대상만) | 0.08 | — | — | 0.15에서 |
| bodySkin.tone | 0 | — | — | 그대로 |

- `OneTouchBundle.Values`에 `spots`·`chromaEvening` 필드가 는다. `refinements`가 두 키를 포함한다.
- `layer(for:strength:)`는 `autoBlemish = false`를 쓴다(G5-2부터, 그 전 G5-1은 `true` 유지). 강도 0은 빈 층(그대로).
- `keys`는 `PortraitKey.skin`이 `SkinRefinementKey.allCases`로 자라므로 자동으로 두 키를 포함한다.
- README 표와 `OneTouchBundleTests`의 구조 단언(남성 메이크업 없음, 매끄럽게 ≤ 0.5, 남성 < 여성)은 그대로이고 값 단언은 표 상수를 참조한다.

### 3. 레시피 키

```json
"portrait": { "skin": { "smoothing": 0, "autoBlemish": false, "spots": 0, "chromaEvening": 0, … } }
```

- `SkinRefinementKey`에 `case spots`(G5-2)와 `case chromaEvening`(G5-3)을 더한다. 순서: `darkCircles, nasolabial, marionette, glabella, toneEvening, chromaEvening, redness, shine, spots`. 화면(뷰티 › 피부)이 `allCases` 순서로 슬라이더를 그리므로 `UserMessage.skinRefinementTitle`에 "점 지우기"·"얼룩 색 고르기"를 더한다(switch가 전수라 컴파일이 강제한다).
- `SkinAdjustments`에 `spots`·`chromaEvening` 저장 속성·init 인자·decode(없으면 0)·subscript 분기. `AdjustmentRange.skinRefinement`는 unit(기본 분기). `hasRefinement`·`numericValues`·`refinementValues`는 `allCases`로 자동 포함.
- 스키마 `portrait.skin.spots`·`chromaEvening`(number 0~1 default 0)과 `$defs/portraitLayer.skin`에 같은 키. README "키를 추가할 때의 규칙"에 G5 한 줄, `portrait` 설명 줄에 두 키, 원터치 표를 2절 값으로. schemaVersion 2 유지.
- `EditDocument`: `applyAuto`의 "정밀 7종 보존"은 `allCases` 기반이라 9종이 된다. 재설정·클램프·동기화도 `allCases`·`PortraitKey.skin`을 돌아 자동이다. 바뀌는 코드는 없고 테스트의 "7종" 주석·상수만 고친다.
- `modules.md`: MellowShared 규칙의 "피부 정밀 7종" → 9종, "묶인 키는 피부 9종·눈입 3종" → 피부 11종. MellowRendering 규칙의 `skin` 단계 순서에 "점 지우기" 추가, `SkinKernels` 커널 8개, 캐시 10 → 11.

### 4. 점 지우기 (`MellowRendering/Domain/SpotRemoval.swift`, G5-2)

#### 4.1 상수 (`RenderTuning`)

| 상수 | 값 | 뜻 |
|---|---|---|
| `spotRadiusFraction` | 0.012 | 점 닫힘·열림 반지름(얼굴 폭 비율). 지름 2.4%까지의 점을 채운다 |
| `spotPoreRadiusFraction` | 0.003 | 모공 닫힘·열림 반지름. 이 크기의 명암은 차이에서 빠져 남는다(하한 `skinBlurMinimumRadius`) |
| `spotCorrectionBlurInPores` | 1.0 | 보정 지도 흐림 반지름(모공 반지름 배수). 닫힘의 평평한 계단을 지운다 |
| `spotDepthStart` | 0.008 | 강도 1의 상대 깊이 시작 문턱 |
| `spotDepthStartWeak` | 0.020 | 강도 0의 시작 문턱(강도로 선형 보간) |
| `spotDepthRamp` | 0.032 | 끝 문턱 = 시작 + 램프 |
| `spotDepthCapStart` | 0.25 | 이보다 깊으면 점이 아니라 구조(콧구멍·눈꼬리)라 가중치가 줄기 시작 |
| `spotDepthCapEnd` | 0.40 | 가중치 0 |
| `spotLumaFloor` | 0.01 | 상대 깊이 분모 하한(선형 휘도) |
| `spotFullFillStrength` | 0.3 | 이 강도부터 채움 비율 1. 아래는 강도/0.3 |
| `spotMorphologyPaddingInSpots` | 3 | 형태 필터 입력 여유(점 반지름 배수) |
| `spotExclusionRadiusFraction` | 0.03 | 눈꼬리·입꼬리 제외 원 반지름(얼굴 폭 비율) |
| `spotNostrilBandFraction` | 0.4 | 코 다각형 아래쪽 이 비율 높이를 콧구멍 띠로 제외 |

#### 4.2 마스크 (`FaceRegions+Spots.swift`)

- `FaceRegions.spotExclusionPolygons(face:extent:tuning:) -> [[CGPoint]]`: (a) 코 다각형(`.nose`)의 아래 `spotNostrilBandFraction` 높이를 자른 사각형과 코 다각형의 교집합 대신, 코 다각형 점 중 v가 `minY + height × spotNostrilBandFraction` 아래인 점들의 볼록 껍질(점이 3개 미만이면 코 상자 아래 40% 사각형). (b) 두 눈 다각형의 u 최소·최대 점 중심의 24각형 원(반지름 `faceWidth × spotExclusionRadiusFraction`). (c) 바깥 입술(`.outerLips`) u 최소·최대 점 중심의 같은 원. 특징점이 없는 부위는 뺀다(빈 목록 가능).
- `FaceRegions.spotExclusionRaster(face:extent:tuning:cache:)`: `polygonMask(fill: exclusions, cut: [], cutWidth: 0, …)` 캐시 항목 1(`entriesPerFacePerResolution` 11).
- 점 마스크 = `unitMask × (1 − blur(exclusionRaster, featherRadius))`. `unitMask`는 `SkinStage.refine`가 이미 만든 피부 마스크(세기 1)다.

#### 4.3 식 (`SkinKernels.spot`·`spotApply`)

```
dark   = max(close(spotR) − close(poreR), 0)      // 채널별, 선형 RGB
bright = max(open(poreR) − open(spotR), 0)
base   = max(Y(close(poreR)), lumaFloor)
depth  = Y(dark) / base,  height = Y(bright) / base
w(x)   = smoothstep(start, end, x) × (1 − smoothstep(capStart, capEnd, x))
correction = dark × w(depth) − bright × w(height)
start  = mix(spotDepthStartWeak, spotDepthStart, s),  end = start + spotDepthRamp
fill   = min(1, s / spotFullFillStrength)
out    = image + blur(correction, poreR × spotCorrectionBlurInPores) × spotMask × fill
```

- `close = CIMorphologyMaximum → CIMorphologyMinimum`, `open = Minimum → Maximum`(반지름 픽셀). Y는 BT.709 선형 계수(주석으로 이름).
- 입력은 `image.clampedToExtent().cropped(to: area)`(`area = maskBounds.insetBy(−spotR × padding)`), 형태 필터 출력은 `bounds`로 자른다.
- 보정 지도는 `spot` 커널 출력(`extent: bounds`)에 `.insertingIntermediate()`를 걸어 굳힌 뒤 `clampedToExtent().blur`한다. `spotApply`는 `bounds`에서만 계산하고 `MaskBuilder.blend` 없이 `image.rgb + correction × mask × fill`을 돌려 `composited(over: image).cropped(to: extent)`.
- 대안(단위 테스트 `testSpotRemovalLeavesPixelsOutsideTheFaceBoundsUntouched`가 실패할 때만): `RenderContext.init`에 `renderer: Renderer? = nil`을 더하고 `PhotoPipeline`이 자기 `renderer`를 넘기며, `SpotRemoval`은 `renderer`가 있으면 보정 지도를 `readPixels` 대신 `CIContext.createCGImage(…, format: .RGBAf, colorSpace: extendedLinearSRGB)`로 굳힌 `CIImage(cgImage:)`를 쓴다(시제품과 같음). `Renderer`에 `makeFloatImage(_:) -> CIImage`를 더한다. nil이면 중간 결과 방식.
- `SkinStage.refine` 순서: 점 지우기 → 주름 밝히기 → 대역 합성 → 붉은기. `skin.spots > 0`일 때만. `hasEffect`는 `allCases`라 자동.

#### 4.4 단위 테스트 (`SpotRemovalTests.swift`, 합성 피부 질감 `Support.skinTexture` + 합성 얼굴)

- 심은 어두운 점(반지름 얼굴 폭 1%, × 0.85)·밝은 점(+0.1)이 강도 1에서 70% 이상 회복, 모공 크기 점(0.3%)은 90% 이상 남음.
- 강도 0.3과 1의 회복률 차이 ≥ 0.1(얕은 점 깊이 3%), 강도 0은 바이트 동일.
- 콧구멍 띠·눈꼬리 원 안은 바이트 1 이내, 얼굴 마스크 영역 밖은 바이트 동일(굳히기 검사).
- 대상 얼굴만(H 규칙).

### 5. 색 맞춤 복구와 오검출 거절 (G5-1)

#### 5.1 `LocalEditStage.applySpot` (수동·자동 공통)

```
r        = min(spotMaxRadiusFraction, spot.radius) × shortSide
S        = image.clampedToExtent().transformed(by: offset)          // 원본 패치 (지금과 같음)
Slow     = blur(S, r × healLowBandScale)
ring     = 1 − ellipse(center, r × healRingInnerScale)  (extent 안)   // 대상 둘레 고리 가중치
ringMean = maskedMean(image, mask: ring, radius: r × healRingRadiusScale)   // 분자·분모
gain     = clamp(ringMean.rgb / max(Slow.rgb, floor), 1/healMaxGain, healMaxGain)   // 채널별
healed   = S.rgb × gain
out      = blend(healed, over: image, mask: ellipse(center, r))
```

- 상수(`RenderTuning`): `healLowBandScale` 0.6, `healRingInnerScale` 1.0, `healRingRadiusScale` 1.5, `healMaxGain` 2.0, `healLumaFloor` 0.01.
- 커널 `SkinKernels.heal(source:sourceLow:ringNumerator:ringDenominator:floor:maxGain:extent:)`. 분모 `max(den, 0.001)`.
- 원본의 고주파(질감)는 비율로 옮겨지고 저주파(밝기·색)는 대상 고리 평균이 된다. 경사 위에서도 원반이 생기지 않는다.
- `RenderPipelineTests`의 기존 spot 테스트는 "바뀐다"만 보므로 유지. `SkinStageTests.testAutoBlemishHealsPlantedSpots`(+20 밝아짐)는 유지.

#### 5.2 `BlemishDetector` 거절 조건

- 중심 픽셀의 피부 마스크 ≥ `blemishCenterMaskMinimum` 0.9(후보 픽셀 문턱 `blemishMaskThreshold` 0.5는 그대로). 피부 다각형 가장자리(흐림 폭 안)와 손·턱 경계가 빠진다.
- 연결 영역의 상자 종횡비 ≤ `blemishMaxAspect` 2.0이고 채움 비(픽셀 수 ÷ 상자 넓이) ≥ `blemishMinFill` 0.4. 원은 0.785, 그늘 선·주름은 낮다.
- 단위 테스트: 합성 얼굴 턱 경계에 심은 그늘 선(폭 1%, 길이 10%)은 잡히지 않고 옆의 원은 잡힌다. 피부 다각형 가장자리 1.5% 안의 원은 잡히지 않는다.

### 6. 얼룩 색 고르기 (`toneMix` 확장, G5-3)

- `FrequencySeparation.refined`에 `chromaEvening` 인자. `even > 0 || gloss > 0 || chroma > 0`일 때 `toneMix` 경로.
- 추가 입력: `blotchBlur = blurred(image, radius: faceWidth × chromaBlotchFraction)`(`chromaBlotchFraction` 0.06), 기준은 기존 `wide`(마스크 가중 12% 평균).
- 커널 항(선형 RGB, BT.601 계수를 선형 값에 그대로 씀 — 휘도 보존이 목적이지 표준 YCbCr이 아니다):

```
dcb = dot(blotchBlur.rgb − wide, cbv),  dcr = dot(blotchBlur.rgb − wide, crv)
shift = chroma × (dcb × invCb + dcr × invCr)       // invCb = (0, −0.344136, 1.772), invCr = (1.402, −0.714136, 0)
result = low + mid × keep + fine − shift
```

- `invCb`·`invCr`는 Y 성분이 0인 역변환 열이라 `dot(result, yv)`가 `shift`에 영향받지 않는다(Y 보존).
- `chroma = min(1, max(0, chromaEvening)) × chromaEveningMax`(`chromaEveningMax` 1.0).
- 단위 테스트: 심은 보라 얼룩 Cb·Cr 50% 이상 감소, 같은 픽셀 Y 바이트 1 이내, `chromaEvening = 0`이면 기존 경로와 같은 바이트.

### 7. 테스트 지원·하네스

- `RenderingTestSupport`: `bandVarianceRatio(before:after:weight:in:innerRadius:outerRadius:)`(가중 분산 비, `fineVarianceRatio`와 같은 방식으로 `blur(inner) − blur(outer)` 대역), `DisplayScale.chromaStandardDeviationRatio(before:after:weight:)`, `SyntheticDefect.spotted(_:centers:radius:factor:extent:)`(선형 곱 단단한 원), `SyntheticDefect.tinted(_:center:radius:cb:cr:extent:)`(감마 Cb·Cr 이동, Y 유지), `RealPortrait.spotGrid(count:radiusFraction:spacingFraction:) -> [CGPoint]`(피부 마스크 ≥ 0.9인 격자 점), `RealPortrait.spotExclusionMask()`.
- `EvotoCalibrationTests`: `SpotPrototype` 삭제(G5-2), `Variant.spots`·`cloneHeal` 삭제, `Candidate`를 `Legacy`(1.4.0 표 값 상수: 매끄럽게 0.35/0.45/0.25, 얼룩 고르기 0.25/0.35/0.15, 다크서클 0.55/0.6/0.5, 팔자 0.4/0.45/0.35, 점 0, 색 고르기 0, autoBlemish true, 몸 0.15)로 바꿔 `MELLOW_EVOTO_CANDIDATES=1`에서 `legacy` 계열을 잰다. `app`·`female`·`male` 계열은 늘 현재 표다. `testLocalLayerMatchesTheBundle`은 유지.
- 하네스 실행(이 Mac, 이미지 있을 때): `MELLOW_EVOTO_DIR=<evimg> MELLOW_EVOTO_OUT=<out> MELLOW_EVOTO_CANDIDATES=1 swift test --filter EvotoCalibrationTests`. 결과 `metrics.md`의 묶음별 중앙값(retouch·spots·dark-circles·wrinkles)을 VALIDATION 표로 옮긴다.

### 8. VALIDATION

`## 인물 보정 G5 Evoto 보정 재조정 (2026-10-XX)`: 자동 검증(명령·종료 코드·테스트 수), 1.2절 수용 경계의 실측값(데모·커플·심은 결함), 1.1절 하네스 경계의 실측 표(1.4.0 표 / G5 표 / Evoto, 7쌍 중앙값), 내린 보임 문턱과 이유, 바뀐 상수·표 값, 스펙과 다르게 한 것, 렌더 시간(데모 미리보기 원터치 0.6, 전후), 미검증(실기기·CI·다른 피부톤). 수행하지 않은 검증을 통과로 쓰지 않고 배포는 하지 않았다고 적는다.

### 9. 계획 분할

| 계획 | 파일 | Task |
|---|---|---|
| G5-1 | `docs/superpowers/plans/2026-10-21-beauty-g5-1-heal-fix-and-tables.md` | 1 색 맞춤 복구 → 2 오검출 거절 → 3 표 인하와 README → 4 측정 도우미·수용 테스트 재조정·VALIDATION 초안 |
| G5-2 | `docs/superpowers/plans/2026-10-21-beauty-g5-2-spot-removal.md` | 1 키·표·화면 이름 → 2 제외 영역·캐시 → 3 `SpotRemoval`·커널·단계 → 4 심은 점 수용·원터치 무복제 → 5 하네스 정리·실행 |
| G5-3 | `docs/superpowers/plans/2026-10-21-beauty-g5-3-chroma-evening-validation.md` | 1 키·표·화면 이름 → 2 커널·대역 합성 → 3 심은 얼룩 수용 → 4 하네스 실행·VALIDATION·문서 |
