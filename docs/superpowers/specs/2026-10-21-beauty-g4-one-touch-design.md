# 인물 보정 G4 (원터치 인물 보정·주름 재설계·보이는 강도) 설계

작성 2026-10-21. 선행: [인물 보정 G](2026-10-20-beauty-g-evoto-design.md)(머지, 1.3.0 (8.1) TestFlight), [인물 보정 H](2026-10-21-beauty-h-per-person-design.md)(스펙·계획 승인, 미구현). 근거: [Evoto 기능 역공학 분석](../../research/2026-10-20-evoto-analysis.md). 기준 코드: main `74fb2df`.

이 문서는 H 스펙을 대체하지 않는다. H의 결정(세 층·수동 성별 지정 필수·anchor 짝짓기·동기화 규칙)은 그대로이고, 이 문서는 그 위에 원터치 묶음을 얹고, G1 주름 밝히기의 실사진 실패를 고치고, 모든 보정의 "보이는 강도" 기준을 세운다. H 계획 네 개는 5절대로 순서와 제약만 고친다.

## 사람이 확인할 것

### 기기에서 본 것과 원인

| 관찰(1.3.0, iPhone) | Mac 측정(실제 Vision, `demo-portrait.png`, 값 1) | 원인 | 이 문서의 대응 |
|---|---|---|---|
| 그레인은 끝까지 올려도 뭔지 모르겠음 | 바뀐 픽셀 73%, 최대 15/255, 알갱이 약 1.4px | 진폭 ±6%(감마)에 알갱이가 폰 화면 축소에서 평균돼 사라짐 | 알갱이 크기·진폭 재조정(2절·3절) |
| 글로우는 변화 있음 | 93%, 최대 75 | 정상 | 그대로 |
| 다크서클·팔자·마리오네트·미간이 안 바뀜 | 0.05% · 0.06% · 0% · 0% | (1) 띠가 눈·입 보호 영역(얼굴 폭 5%)에 잘려 조각만 남음 (2) 둘레 평균이 눈·눈썹·속눈썹을 포함해 "주변 − 국소" 차이가 0 또는 음수 | 띠 위치·크기와 밝히기 기준을 피부 전용으로 재설계(2절) |
| 피부 밝기(몸 피부) 변화 없음(추정) | 52%, 최대 48 | 사람 영역 + 기준 얼굴이 둘 다 있어야 동작. 조건이 안 맞으면 조용히 빠짐 | 조건을 화면에 보이고, 사람 영역이 없어도 얼굴이 있으면 대체 영역으로 동작(2절) |
| 붉은기 +1 | 10.9%, 최대 9 | 가산량 0.03이 작음 | 상수 2배 |
| 피부 톤 ±1(몸) | 51%, 최대 11 | 가산량 0.025가 작음 | 상수 1.4배(처음 2배, G4-1 구현 중 0.035로 내림) |

기기와 Mac의 렌더 경로 차이는 아니다(글로우가 기기에서 바뀜). 그래서 기기 전용 진단은 최소(앱 정보 시트의 "진단" 줄)만 둔다.

### 결정

"판정"이 붙은 행은 사용자가 자리를 비운 동안(2026-10-20, "쭉 진행하고 TestFlight 배포까지") 코디네이터가 권고안대로 정했다. 각 판정과 틀렸을 때의 비용은 아래 "질문과 판정"에 있다. 기기 확인 뒤 바꿀 수 있다.

| 결정 | 이유 | 바꾸면 비용 |
|---|---|---|
| **보이는 강도 원칙.** 원터치 항목 전부와 세부 슬라이더 전부는 최댓값에서 폰 화면 배율(미리보기를 가로 1170px로 맞춘 뒤)에서 사람이 알아볼 수 있는 변화를 내야 한다. 수치 문턱은 2절 표에 두고 macOS 패키지 테스트가 실제 Vision으로 `demo-portrait.png`에서 잰다 | 1.3.0에서 "움직여도 안 바뀌는" 슬라이더가 나왔다. 합성 얼굴 테스트는 통과했으므로 실사진·화면 배율 기준이 따로 있어야 한다 | **큼** (상수 조정이 테스트로 묶임) |
| **자연스러움 원칙(상한).** "보이는 강도"의 과녁은 "최대한 세게"가 아니라 **Evoto 전후 측정치**다(연구 문서 측정값 표: 주름·다크서클은 면적 1~4%에 평균 ΔY +0.02~0.03, 고주파(질감) 비 0.9~1.0, 피부색 변경은 피부 전체 +0.066). 원터치 **기본 강도(0.6)가 이 크기**를 내고, 강도 1(끝)도 성형 느낌이 나지 않게 표 값 자체를 상한으로 잡는다. 하한(보임) 테스트 옆에 **상한(자연) 테스트**를 둔다: 피부 마스크 안 질감(모공 대역 분산) 비 ≥ 0.85(기본 강도에서는 ≥ 0.9), 어느 띠도 평균 ΔY +0.08을 넘지 않음, 피부 색차 변화 ≤ 0.015, 얼굴 다각형 밖·눈썹·(남성) 입술은 그대로 | 사용자 결정("과하면 안 됨, 성괴 아님"). 수치가 없으면 "자연스럽다"는 리뷰에서 판정할 수 없다 | **큼** (표 값·상수가 두 방향 테스트에 묶임) |
| **얼굴형·체형 변형(C·E)은 원터치 묶음에 넣지 않는다.** 묶음은 피부·주름·눈입·블러셔·몸 피부색뿐이다 | 변형은 "성형"으로 보이는 바로 그 항목이고 수동 편집 잠금과도 얽힌다. 원하면 세부 조정의 얼굴 탭에서 직접 한다 | 작음 |
| 결함이 있어야 뜻이 있는 항목(주름 4종, 붉은기 −, 번들거림)은 실사진에 **합성 결함을 심어** 회복률로 재고, 결함이 없는 사진에서 억지로 바꾸지 않는다 | 깨끗한 얼굴에서 미간 주름 슬라이더가 뭔가를 바꾸면 그것이 오히려 결함이다 | 작음 |
| **주름 띠는 얼굴 폭 기준 크기로 다시 놓고, 주름용 피부 비트맵은 눈·입 보호 영역을 얼굴 폭 1.2%만 넓힌다(피부 보정용 5%와 분리).** 다크서클은 눈 아래 얼굴 폭 5.5% 지점, 팔자 띠는 코 날개에서 입꼬리를 지나 25% 더 내려가며 바깥쪽 4.5% 밀림, 마리오네트는 14% 길이 | 측정 결과 띠의 대부분이 보호 영역 넓힘에 잘려 나갔다(팔자는 코 쪽 조각 둘만, 다크서클은 가는 조각). 실제 주름은 입꼬리 아래까지 이어진다 | 작음 (캐시 항목 얼굴당 1개 추가) |
| **밝히기 기준은 "피부 마스크 × (1 − 띠)"로 가중한 넓은 평균 휘도**다(얼룩 고르기의 마스크 가중 평균과 같은 방식). 밝히는 방식(휘도 비율 곱, 상한 1.6)은 그대로 | 지금 기준은 가중치 없는 흐림이라 눈·눈썹·속눈썹·머리카락이 섞여 주변이 그늘보다 어둡게 나왔다(측정: 다크 0.025, 팔자 0.002, 미간 −0.058). 피부만 평균하고 띠 자신을 빼면 "주변 피부 수준"이 된다. 곱셈이라 색조·질감은 그대로 | 작음 |
| **그레인 재조정: 알갱이 한 변 0.0012 → 0.0025(짧은 변 비율, 1200px에서 3px), 진폭 0.12 → 0.30**. 화면 배율에서 휘도 차이 표준편차 ≥ 5/255를 테스트로 고정 | 폰 화면에서 안 보였다. Evoto 그레인은 고주파 비 6.75로 뚜렷하다 | 작음 |
| **원터치는 레시피 항목 값을 쓰는 매크로**다(렌더 시점에 펼치는 값이 아님). 층마다 `oneTouch` 표시(마지막 강도, 0…1 또는 없음)만 레시피에 남기고 렌더는 이 키를 읽지 않는다. 묶인 항목을 손으로 바꾸면 그 층의 표시는 지워진다(메이크업 `lookID`와 같은 규칙) (판정: 권고 채택) | "레시피가 곧 렌더"라는 지금 구조(프리셋·동기화·층·테스트 전부)가 그대로 선다. 세부 슬라이더가 실제 값을 보여 "왜 이렇게 보이나"를 설명한다. 대안(렌더 시점 펼침)은 항목마다 값의 출처가 둘이 되고 표를 Shared·앱·다른 플랫폼이 중복으로 들어야 한다 | **큼** (파일 형식·조작 모델) |
| **원터치 대상이 "전체"면 전체 층에 공통 표, 남성·여성 그룹 층에 각 성별 표를 한 번에 쓴다(체크포인트 하나).** 대상이 그룹이면 그 그룹 층만, 사람이면 그 사람 층에 그 사람의 유효 성별 표를 쓴다 (판정: 권고 채택) | "버튼 하나로 남녀가 다르게"가 요구다. 전체 층만 쓰면 성별 칩을 하나씩 눌러야 한다. 성별 미지정인 사람은 H 규칙대로 공통 표를 받는다 | 중간 |
| 성별 표(강도 1 = 허용 상한): 남성은 매끄럽게 0.25(질감 유지)·얼룩 고르기 0.15(최소)·번들거림 0.5·블러셔·립 없음, 여성은 매끄럽게 0.45·블러셔(복숭아) 0.15·입술 생기 0.2, 공통(미지정)은 그 사이. 표 전체는 3.2절 (판정: 권고 채택, 취향 피드백으로 조정) | 사용자 결정("남자는 덜 매끄럽게, 블러셔·립 없음", "자연스럽게"). 남성은 유분이 많아 번들거림을 더 누르고 피부 결을 남긴다 | 작음 (상수 한 곳) |
| 강도 슬라이더(0…1)는 표의 모든 값에 선형으로 곱한다(자동 잡티는 강도 > 0이면 켬). **기본 강도 0.6**이 Evoto 크기, **1은 표 값 그대로이며 그것이 상한**이다(슬라이더가 표를 넘는 값을 만들지 않음). 강도 0은 묶인 항목을 그 층에서 지운다(전체 층은 기본값, 그룹·개인은 상속) | 끝까지 올려도 성형 느낌이 나지 않아야 한다. 상한은 표 값이고 상한 테스트가 지킨다 | 작음 |
| 몸 피부 밝기·톤은 사진 단위라 대상이 "전체"일 때만 원터치가 쓴다(그룹·사람 대상에서는 건너뜀) | H 결정(체형·몸 피부는 사진 단위) 유지 | 작음 |
| 세부 슬라이더는 뷰티 패널의 "세부 조정" 접기 안으로 들어간다(기본 접힘, 펼침 상태는 세션 기억). 접기 안은 지금의 탭 4개(피부·얼굴·눈·입·피부톤) 그대로 | 첫 화면은 "대상 칩 → 원터치 버튼 + 강도" 한 줄이어야 Evoto와 같다 | 작음 |
| **자동 = 색감·디테일 자동 + 얼굴이 있으면 원터치 강도 0.6(전체 대상: 전체 층 공통 표, 남성·여성 그룹 층 각 성별 표, 몸 피부 밝기)을 한 체크포인트로 쓴다.** 예전에 자동이 쓰던 피부 보정 0.3·자동 잡티·눈 0.2는 원터치 공통 표에 흡수된다. 얼굴이 없으면 색감·디테일만 (질문 2, 판정: 권고 채택) | 사용자가 기억한 Evoto는 "버튼 하나로 자동 보정"이었다. 대가: 색감만 맞추려던 사용자도 피부·눈입·블러셔·립이 바뀌고, 그룹 층에서 손으로 바꾼 묶인 키 값이 성별 표 값으로 덮인다(실행 취소 한 번으로 되돌림) | 작음 (`AppModel.Policy.autoIncludesOneTouch` 상수 하나로 분리로 돌아감) |
| 프리셋은 원터치가 쓴 값(전체 층·그룹 층)과 `oneTouch` 표시를 함께 나른다(지금 규칙 그대로). 동기화는 피부·눈입·메이크업·몸 피부 네 항목을 모두 복사할 때만 표시를 복사하고(G4-2 구현 중 변경: 몸 피부 추가) 일부만 복사하면 받는 사진의 표시를 지운다 | 표시는 "이 층의 묶인 항목이 표와 같다"는 뜻이라 일부만 바뀌면 거짓이 된다 | 작음 |
| 사람 영역을 못 찾았지만 얼굴이 있으면 몸 피부는 **가장 큰 얼굴 상자를 가로 3배·아래로 4배 늘린 부드러운 영역**을 사람 영역 대신 쓴다. 피부톤 탭 맨 위에 "사람 영역 · 기준 얼굴" 상태 한 줄을 보인다 | 조건이 안 맞아 조용히 빠지는 것이 "안 바뀐다"로 보였다. 얼굴 없음 규칙(G 결정, 건너뜀)은 그대로 | 작음 |
| 붉은기 +1 가산 0.03 → 0.06, 붉은기 − 비율 0.7 → 1.0에 기준 Cr 여유 0.01, 번들거림 시작 0.12 → 0.08·폭 0.1 → 0.08, 몸 피부 톤 0.025 → 0.035(G4-1 구현 중 0.05에서 내림, 아래 행). 나머지 G 상수는 측정상 충분해 유지(2절 표) | 보이는 강도 원칙 | 작음 |
| 기기 진단은 앱 정보 시트의 "진단" 절(앱 버전·빌드, 기기, 선택 사진·미리보기 크기, 얼굴·사람·관절 유무, 기본값이 아닌 레시피 키, 마지막 렌더 오류)과 "복사" 버튼만. 렌더 파이프라인은 바꾸지 않는다 | 기기 렌더 경로는 정상으로 확인됐다. 다음 기기 확인 때 스크린샷 한 장으로 전제 조건(사람 영역·얼굴)을 볼 수 있으면 충분하다 | 작음 |
| H 계획은 유지하되 **H3 Task 1(생성 사진 세트)을 H1 앞으로 당기고**, 모든 H 계획에서 로컬 iOS 시뮬레이터 실행을 없애며(CI만), 기준 브랜치·커밋을 main `74fb2df` 기준으로 고친다. H4는 선택 그대로 | 원터치 성별 수용 테스트가 커플 사진을 쓴다. 시뮬레이터 창이 사용자를 방해한다 | 작음 |
| **(G4-1 구현 중 변경)** 눈 또렷하게 상수 `eyeWhiteLift` 0.2 → 0.3, `eyeIrisSharpen` 0.8 → 1.0 | 눈 마스크 평균 |ΔY|가 2.41로 하한 3에 못 미쳤다. 1.2절 조정 후보 안에서 눈이 어두워지지 않는 조합이 이것이었다(3.20, 평균 ΔY +0.01) | 작음 (여유 0.20뿐이라 기기·CI에서 흔들릴 수 있음) |
| **(G4-1 구현 중 변경)** 입술 생기 하한은 휘도가 아니라 입술 마스크 가중 \|ΔCr\| ≥ 0.02 | 입술 커널은 Cb·Cr만 바꾸고 휘도를 지킨다. 휘도 지표는 상수를 올려도 넘을 수 없는 테스트 설계 오류였다(실측 \|ΔCr\| 0.047) | 작음 |
| **(G4-1 구현 중 변경)** G1 단위 테스트 "그늘 없는 피부에 얼룩·색 번짐 없음"을 "띠 안 색차 ≤ 0.01, 띠 안 평균 ΔY ≤ +0.08, 띠 밖 1바이트 이내"로 다시 정의 | 피부 전용 기준은 띠 안의 어두운 결 얼룩도 주변 피부 수준으로 고른다(합성 얼굴에서 6~10바이트). 실사진 자연스러움 상한은 모두 통과한다 | 작음 (값 1에서 깨끗한 피부가 조금 밝아질 수 있음) |
| **(G4-1 구현 중 변경)** 사람 분석이 실패해도 얼굴이 있으면 몸 피부 슬라이더를 켠다 | 렌더가 대체 영역으로 실제 적용하므로 슬라이더를 끄면 상태 줄과 어긋난다 | 작음 |
| **(G4-1 구현 중 변경)** 합성 반사광 도우미를 "빛 층 더하기"에서 "밝힌 사본을 가우시안 봉우리로 섞기"로 고침 | 알파 0 빛 층은 사전곱에서 사라져 반사광이 하나도 심어지지 않았다(고친 뒤 +28/255) | 작음 (테스트 도우미만) |
| **(G4-1 구현 중 변경)** "띠 밖·마스크 밖 불변"은 바이트 완전 일치가 아니라 채널 차이 1바이트 이내 | 같은 이미지를 마스크로 자기 자신과 섞기만 해도 작업 색공간 반올림으로 1바이트가 바뀐다(G4 전에도 같음). 2바이트 이상 바뀐 픽셀은 없다 | 작음 |
| **(G4-1 구현 중 변경)** 몸 피부 톤 상수 `bodySkinToneMax`는 0.05가 아니라 0.035. 1.4절에 상한 "피부 톤(몸) ±1: 피부 가중 \|ΔR − ΔB\| ≤ 30/255"를 더한다 | 최종 리뷰: 0.025도 이미 보임 하한(6/255)의 3.3배(19.8/255)였다. 0.05는 피부 전체에 R 약 +18·B 약 −23을 더해 얼굴 전체가 주황빛으로 뜰 위험이 있고 막을 상한 테스트가 없었다. 자연스러움 우선 원칙에 따라 하한의 약 4.7배(예상 약 28/255)에 멈추고 상한을 테스트로 묶는다 | 작음 (상수 한 줄. 기기에서 약하면 상한 30/255 안에서 올린다) |
| **(G4-2 구현 중 변경)** 원터치 표의 몸 피부 밝기 0.2 → 0.15(기본 0.6에서 0.09) | 강도 1에서 몸 피부 밝기가 눈썹 가장자리를 밝혀 눈썹 마스크 changedFraction이 9.1%로 상한 5%를 넘었다(얼굴 항목만이면 0%). 0.16에서 3.9%, 0.14에서 1.9%라 두 방향 여유가 고른 0.15를 골랐다(눈썹 2.8%, 기본 0.6 남성 피부 평균 ΔY 1.79 ≥ 하한 1.275) | 작음 (표 상수 한 줄. 기기에서 약하면 눈썹 상한 안에서 올린다) |
| **(G4-2 구현 중 변경)** 원터치 실사진 수용 테스트는 하한(얼굴 상자 보임·남녀 차이·커플)을 몸 피부 없이 얼굴만, 상한(1.4 원터치 행 전부)을 몸 피부를 포함한 전체 대상 결과로 잰다 | 1.4의 "위 항목들의 합"과 "사람 영역 밖"은 몸 피부 포함을 전제한다. 몸 피부 없이 재면 기본 0.6 피부 평균 ΔY가 0.24~0.81/255로 하한 1.275/255에 못 미치는데 이는 얼굴 표 값을 올려 맞출 성질이 아니다(매끄럽게·얼룩 고르기는 밝히지 않고 번들거림은 어둡게 한다). 하한은 얼굴만 재는 쪽이 더 엄격하고 상한은 몸 피부를 넣는 쪽이 더 엄격하다 | 작음 (테스트 설계만) |
| **(G4-2 구현 중 변경)** 몸 피부 밝기는 전체 층 원터치 표시에 묶이고(손으로 바꾸면 표시 해제, 강도 0은 0으로), 몸 피부 톤은 표 값이 0인 동안 원터치가 쓰지 않는다 | 원터치 결정 행이 묶음을 "피부·주름·눈입·블러셔·몸 피부색"으로 정했으므로 표시도 몸 피부 밝기를 대변해야 한다. 톤 표 값 0을 매번 쓰면 사용자가 맞춘 몸 피부 톤이 조용히 지워진다 | 작음 |

### 범위

| 계획 | 들어가는 것 | 선행 |
|---|---|---|
| G4-1 주름·강도 | 화면 배율 측정 도우미, 실사진 수용 테스트(G 항목 전부), 주름 띠·밝히기 재설계, 그레인·붉은기·번들거림·몸 피부 톤 상수, 몸 피부 대체 영역과 상태 줄, 진단 절, VALIDATION | 없음(main) |
| H3 Task 1 | 생성 커플·단체 사진과 라벨(기존 계획 그대로) | G4-1 |
| H1 → H2 | 기존 계획 그대로(5절의 개정 사항만 반영) | 위 |
| G4-2 원터치 레시피·규칙 | `OneTouchBundle` 표, `oneTouch` 표시 키·스키마, `applyOneTouch`, 프리셋·동기화 규칙, 실사진 원터치 수용 테스트(데모 + 커플) | H2 |
| H3 Task 2~3 | 대상 칩·성별 메뉴·덮어쓰기 표시(기존 계획 그대로) | G4-2 |
| G4-3 원터치 화면·검증 | 원터치 버튼·강도 슬라이더·세부 조정 접기, (질문 2에 따라) 자동 버튼 연동, 시나리오, 문서, VALIDATION | H3 Task 3 |
| H3 Task 4, H4 | 기존 계획 그대로(로컬 iOS 제외) | G4-3 |

### 범위 밖

다크서클의 청자색 보정(지금은 휘도만), 주름 깊이 자동 추정, 원터치의 사진별 자동 강도, 사진 사이 같은 사람 인식, 나이·표정 추정, 자동 성별 추정 모델(H4 그대로 선택).

### 위험과 대응

- **문턱이 데모 사진 한 장 기준이다.** 다른 피부톤·조명에서 과하거나 약할 수 있다. 대응: 커플·단체 생성 사진으로 2차 측정을 추가하고(G4-2), 상수는 전부 `RenderTuning`·`OneTouchBundle` 한 곳이라 기기 확인 뒤 한 커밋으로 고친다.
- **문턱을 못 넘으면 테스트가 빨갛다.** 대응 규칙: 렌더 상수를 올려 넘긴다(2절 표의 "조정 후보"). 문턱을 내리는 것은 VALIDATION에 이유를 적고 사용자가 동의할 때만.
- **주름 띠를 키우면 밝은 얼룩이 생길 수 있다.** 대응: 밝히는 양은 여전히 "주변 피부보다 어두운 만큼"이고 상한 1.6이다. 합성 결함 없는 데모 사진에서 띠 안 색차(Cb·Cr) 변화 ≤ 0.01을 테스트로 고정한다.
- **그레인을 키우면 저장본에서 거칠 수 있다.** 대응: 알갱이는 짧은 변 비례라 저장본과 미리보기가 같은 비율이다. 기기 확인 항목으로 남긴다.
- **원터치가 그룹 층을 쓰면 "전체" 슬라이더를 움직여도 성별 지정된 사람은 안 바뀐다**(그룹 값이 덮어씀). 블러셔·립도 그룹 층이 덮어써서 뒤에 "전체"에 건 메이크업 룩이 성별 지정된 사람에게는 안 보인다(G4-3 구현 중 추가). 대응: 그룹 칩에 점 표시와 "재설정"(H3)이 있고, 전체 대상의 강도 슬라이더는 세 층을 함께 다시 쓴다. 안내 문구 한 줄이 피부·눈입·메이크업을 함께 말한다.
- **성별을 지정하지 않으면 남녀 차이가 없다.** 대응: 원터치 줄 아래 "성별을 지정하면 남녀가 다르게 보정돼요" 안내. 자동 추정은 질문 3.
- **CI가 요금 한도로 막혀 있다.** 대응: 모든 계획은 로컬 패키지·Mac 테스트까지만 검증하고, iOS 시뮬레이터·실기기 검증은 CI 복구와 TestFlight 뒤 사용자 조치로 적는다.

### 사용자 조치

- 아래 판정 4개 확인(바꾸려면 알려 주기).
- G4-1 뒤(질문 4에 따라 1.3.1) 기기에서: 그레인·다크서클·팔자·피부 밝기를 끝까지 올린 스크린샷, 피부톤 탭 상태 줄, 정보 시트 "진단" 스크린샷, 그레인 1로 저장한 사진 1장.
- G4-3 뒤 기기에서: 커플 사진에서 성별 두 번 지정 → 원터치 → 남녀 차이, 강도 슬라이더, 세부 조정 펼침.
- 성별 표 값(3.2절)의 취향 피드백.

### 돈·시간·외부 효과가 있는 단계

- H3 Task 1의 이미지 생성(codex CLI, OpenAI 사용량)은 기존 H 계획 그대로.
- 계획 안의 Task는 푸시·태그·TestFlight 업로드를 하지 않는다.
- 사용자가 2026-10-20 "TestFlight 배포까지 끝내놔"로 허락해, 코디네이터가 G4-1 뒤 1.3.1, 전부 끝난 뒤 1.4.0을 main 푸시·태그로 TestFlight에 올린다.
- CI 요금 한도는 저장소 공개로 풀렸다(2026-10-20).

### 질문과 판정 (각각 권고 포함, 판정은 2026-10-20 코디네이터)

1. **원터치 저장 방식.** 권고: 항목 값을 쓰는 매크로 + 층별 `oneTouch` 표시(위 결정). 대안: `portrait.oneTouch` 강도만 저장하고 렌더가 표로 펼침 — 세부 슬라이더와 두 출처가 생겨 권하지 않음.
   - **판정: 권고(매크로 + 표시).** 틀리면 비용: 렌더 시점 펼침으로 바꾸려면 레시피 키 의미와 프리셋·동기화 규칙을 다시 짜야 한다(큼). 사용자 요구("버튼 하나 + 세부는 숨김")는 두 방식 모두 만족하므로 구조가 덜 흔들리는 쪽을 골랐다.
2. **"자동" 버튼이 원터치를 포함할지.** 권고: 포함한다 — 자동 = 색감·디테일 자동 + 얼굴이 있으면 원터치 강도 0.6(전체 대상, 세 층). 기존의 "자동이 피부 보정 0.3·자동 잡티·눈 0.2를 쓰던 것"은 원터치 공통 표에 흡수된다. 대안: 지금처럼 분리(자동은 색감만, 원터치는 뷰티 안).
   - **판정: 포함.** 사용자가 기억한 Evoto는 "버튼 하나로 자동 보정"이었다. 틀리면 비용: `Policy.autoIncludesOneTouch` 상수 하나를 끄면 된다(작음).
3. **자동 성별 추정(H4)을 지금 당길지.** 권고: 지금은 아니다. 수동 지정은 필수로 들어가고 미지정은 공통 표를 받으므로 원터치가 막히지 않는다. H4 Task 1(후보 모델 조사, 문서만)은 G4-1과 병행해 미리 해 두고, 모델 도입은 G4-3 기기 확인 뒤 정한다. 당기면 모듈 표 변경·모델 라이선스·편향 검토가 원터치와 같은 배포에 섞인다.
   - **판정: 미룸(수동 지정 필수만 넣음).** 사용자 지시("자동으로 안 하더라도 매뉴얼은 넣어라")와 같다. 틀리면 비용: H4를 다음 배포로 진행(포트는 H2에 이미 있음).
4. **배포 순서.** 권고: G4-1(주름·그레인·강도·몸 피부 조건)을 먼저 1.3.1로 TestFlight에 올려 기기에서 확인하고, 그 피드백으로 상수를 고친 뒤 H·원터치를 1.4.0으로. 대안: 전부 끝내고 한 번에.
   - **판정: 둘 다.** G4-1이 CI를 통과하면 1.3.1을 먼저 올리고(밤사이 나머지가 막혀도 폰에서 볼 것이 생김), 나머지를 끝내 1.4.0을 올린다. 1.3.1 기기 피드백은 1.4.0 뒤 상수 조정으로 받는다. 틀리면 비용: TestFlight 빌드 하나가 더 생길 뿐(작음).

## 에이전트 참조

### 1. 보이는 강도 원칙과 측정

#### 1.1 측정 방법 (테스트 지원 `DisplayScale`, `apple/Tests/MellowRenderingTests/RenderingTestSupport.swift`)

- 입력: 실제 Vision(`VisionFaceAnalyzer`·`VisionPersonAnalyzer`·`VisionBodyAnalyzer`)으로 분석한 `Fixtures/demo-portrait.png`(`ImageLoader.load(maxDimension: 1600)`), G4-2부터는 `Fixtures/people/couple-01.jpg`도.
- 화면 배율: 비교할 두 CGImage를 `CILanczosScaleTransform`으로 **가로 1170px**(iPhone 390pt × 3)로 맞춘 뒤 `PixelGrid`로 읽는다(`DisplayScale.phoneWidth = 1170`). 세로 사진은 가로가 1170이 되도록, 가로 사진도 같은 규칙(화면 폭에 맞춘다).
- 지표(모두 화면 배율 8비트):
  - `changedFraction(before, after, in rect, minimumDelta: 4)`: rect 안에서 세 채널 중 최대 |Δ| ≥ 4인 픽셀 비율. rect는 얼굴 상자(얼굴 항목)나 전체(효과·몸).
  - `meanAbsoluteDelta(before, after, weight:)`: 마스크(회색 CGImage, 같은 배율) 가중 평균 |ΔY|(BT.601, 8비트).
  - `meanLumaDelta(before, after, weight:)`: 가중 평균 ΔY(부호 있음).
  - `meanChromaDelta(before, after, weight:)`: 가중 평균 |ΔCb|·|ΔCr|(0…1).
  - `lumaDeltaStandardDeviation(before, after, in rect)`: ΔY의 표준편차(그레인).
  - `recovery(original, defective, repaired, weight:)` = (Y_repaired − Y_defective) / (Y_original − Y_defective), 가중 평균 휘도 기준.
  - `fineBandVarianceRatio(before, after, in rect, radius:)`: 기존 `bandVariances`의 fine 분산 비(질감 보존).
- 합성 결함(실사진 위에, 실제 특징점 마스크로): 그늘 = `image × (1 − depth × mask)`(선형, depth 0.25), 붉은 반점 = 볼 상자 안 지름 얼굴 폭 8% 원에 감마 Cr +0.05, 반사광 = 이마(얼굴 좌표 눈 높이 위 얼굴 폭 25%) 지름 얼굴 폭 12% 가우시안 선형 휘도 +0.3(피부 마스크 안에서만). 반사광은 휘도를 더한 사본을 가우시안 봉우리 마스크로 원본 위에 섞어 `image + lift × 봉우리`로 만든다(G4-1 구현 중 변경: 알파 0 빛 층을 더하는 처음 방식은 사전곱에서 RGB가 0이 되어 아무것도 심지 못했다).

#### 1.2 항목별 문턱 (값 1 또는 끝값, 화면 배율, 시작값)

| 항목 | 측정 | 문턱 | Mac 1.3.0 측정(원본 배율, Δ>2) | 조정 후보(문턱 미달 시 올릴 상수) |
|---|---|---|---|---|
| 피부 보정 1 | 얼굴 상자 changedFraction | ≥ 0.04 | 8.45% | `midReductionMax` |
| 다크서클 1 | 자연: 얼굴 상자 changedFraction ≥ 0.010, 띠 가중 meanLumaDelta ≥ +3/255. 합성(depth 0.25): recovery ≥ 0.5. 띠 가중 meanChromaDelta ≤ 0.01, fine 분산 비 ≥ 0.85 | 위 | 0.05%, 최대 4 | `foldLiftMax`, `foldSurroundFraction`, `FoldShape.darkCircle*` |
| 팔자 1 | 자연: changedFraction ≥ 0.005. 합성 recovery ≥ 0.5 | 위 | 0.06% | 같음 + `FoldShape.nasolabial*` |
| 마리오네트 1 | 합성 recovery ≥ 0.5 | 위 | 0% | `FoldShape.marionette*` |
| 미간 1 | 합성 recovery ≥ 0.5 | 위 | 0% | `FoldShape.glabella*` |
| 얼룩 고르기 1 | 얼굴 상자 changedFraction ≥ 0.04, 피부 마스크 가중 meanAbsoluteDelta ≥ 3/255 | 위 | 10%, 최대 72 | `toneEveningMax` |
| 붉은기 −1 | 합성 반점: 반점 안 Cr 초과분 제거율 ≥ 0.5 | 위 | 0.35%, 최대 8 | `rednessClearMax`(1.0), `rednessReferenceOffset` |
| 붉은기 +1 | 피부 마스크 가중 평균 ΔR ≥ +5/255 | 위 | 10.9%, 최대 9 | `rednessFlushMax`(0.06) |
| 번들거림 1 | 합성 반사광: 반사광 안 휘도 초과분 감소율 ≥ 0.4 | 위 | 0.33%, 최대 28 | `shineLumaOffset`(0.08), `shineLumaRamp`(0.08), `shineReductionMax` |
| 피부 밝기(몸) 1 | 전체 changedFraction ≥ 0.15 | 위 | 52%, 최대 48 | `bodySkinLiftMax` |
| 피부 톤(몸) +1 | 피부 영역 가중 평균 (ΔR − ΔB) ≥ 6/255 | 위 | 51%, 최대 11 | `bodySkinToneMax`(0.035, G4-1 구현 중 0.05에서 내림) |
| 바디 매끄럽게 1 | 전체 changedFraction ≥ 0.10 | 위 | 23%, 최대 115 | `bodySkinMidBandFraction` |
| 그레인 1 | 전체 lumaDeltaStandardDeviation ≥ 5/255, 알갱이 한 변 ≥ 2.5px(화면 배율) | 위 | 73%, 최대 15, 1.4px | `grainMaxAmplitude`(0.30), `grainSizeFraction`(0.0025) |
| 글로우 1 | 전체 changedFraction ≥ 0.40 | 위 | 93%, 최대 75 | `glowMaxIntensity` |
| 눈 또렷하게 1 | 눈 마스크 가중 meanAbsoluteDelta ≥ 3/255 | 위 | 미측정 | `eyeWhiteLift`(0.3), `eyeIrisSharpen`(1.0) (G4-1 구현 중 0.2·0.8에서 올림) |
| 치아 미백 1 | 치아가 보이는 사진에서만(데모는 다문 입 → 건너뜀, XCTSkip) | — | — | `teethLift` |
| 입술 생기 1 | 입술 마스크 가중 meanChromaDelta의 Cr ≥ 0.02 (G4-1 구현 중 변경: 입술 커널은 Cb·Cr만 바꾸고 휘도를 지키므로 휘도 지표로는 잴 수 없다) | 위 | 미측정 | `lipSaturationMax`, `lipRednessMax` |
| 블러셔(복숭아) 1 | 블러셔 마스크 가중 meanAbsoluteDelta ≥ 3/255 | 위 | 미측정 | `makeupBlushMaxOpacity` |
| 원터치 여성 기본 0.6 | 얼굴 상자 changedFraction ≥ 0.05 | — | — | 표 값 |
| 원터치 남성·공통 기본 0.6 (G4-2 구현 중 추가) | 얼굴 상자 changedFraction ≥ 0.05(몸 피부 없이 얼굴만) | — | — | 표 값 |
| 원터치 여성 1 | 얼굴 상자 changedFraction ≥ 0.10 | — | — | 표 값 |
| 원터치 남성 1 | 얼굴 상자 changedFraction ≥ 0.06, 입술 마스크 가중 meanChromaDelta ≤ 0.01(립 없음) | — | — | 표 값 |
| 원터치 여성 vs 남성 | 두 결과 사이 얼굴 상자 changedFraction ≥ 0.02 | — | — | 표 값 |

문턱 수정 규칙: 상수를 올려서 넘긴다. 문턱을 내릴 때는 테스트 주석과 VALIDATION에 이유를 적고 사용자 승인을 받는다. 수치는 테스트 파일의 `enum Visibility` 명명 상수다. 상수를 올릴 때는 1.4절 상한도 함께 통과해야 한다.

#### 1.4 자연스러움 상한 (같은 측정, `enum Naturalness` 명명 상수)

Evoto 측정치(연구 문서 측정값 표)를 과녁으로 한 상한이다. 하한 테스트와 같은 파일에서 같은 입력으로 잰다.

| 조건 | 측정 | 상한 | Evoto 측정 근거 |
|---|---|---|---|
| 각 주름 슬라이더 1(자연 사진) | 띠 가중 meanLumaDelta | ≤ +0.08(약 20/255) | 다크서클 +0.022, 미간 +0.021, 팔자 +0.029 |
| 각 주름 슬라이더 1 | 띠 가중 meanChromaDelta(|ΔCb|, |ΔCr|) | ≤ 0.01 | ΔCr −0.005~0 |
| 각 주름 슬라이더 1 | 띠 영역 fine 분산 비 | ≥ 0.85 | 고주파 비 0.94~1.08 |
| 피부 보정 1 | 피부 마스크 안 fine(모공) 분산 비 | ≥ 0.85 | 부드러운 피부 고주파 비 1.02 |
| 얼룩 고르기 1 | 피부 마스크 안 fine 분산 비 ≥ 0.85, 피부 평균 ΔY | ≤ +0.03 | 주파수 분리 +0.013, 비 0.91 |
| 피부 밝기(몸) 1 | 피부 영역 평균 ΔY | ≤ +0.10 | 피부색 변경 +0.066 |
| 피부 톤(몸) ±1 (G4-1 구현 중 추가) | 피부 가중 \|ΔR − ΔB\| | ≤ 30/255 | 피부색 변경 +0.066(약 17/255)의 두 배 안쪽. 얼굴 전체 주황·푸른 기 없음 |
| 원터치 기본 강도 0.6(여성·남성·공통) | 얼굴 피부 마스크 평균 ΔY(전체 대상 결과, 몸 피부 포함 — G4-2 구현 중 명시) | +0.005 ≤ ΔY ≤ +0.05 | 위 항목들의 합이 피부색 변경보다 작아야 함 |
| 원터치 기본 강도 0.6 | 피부 마스크 fine 분산 비 | ≥ 0.9 | 질감 유지 |
| 원터치 강도 1(상한) | 피부 마스크 fine 분산 비 | ≥ 0.85 | 끝까지 올려도 플라스틱 아님 |
| 원터치 강도 1 | 얼굴 상자 안 |ΔY| 99백분위 | ≤ 60/255 | 국소 폭주 없음 |
| 원터치 강도 1 | 피부 마스크(여성은 블러셔 띠 제외) meanChromaDelta | ≤ 0.015 | 색 기 없음 |
| 원터치 강도 1 | 얼굴 다각형(이마 호 포함)을 얼굴 폭 5% 넓힌 영역 밖(몸 피부는 전체 대상에서 켜지므로 몸 피부 영역 = 인물 마스크(없으면 대체 영역) × 몸 피부색 가중치가 0이 아닌 곳도 뺀다 — G4-2 구현 중 명시). 얼굴 항목(피부·눈입·메이크업)은 몸 피부 없는 결과에서 넓힌 얼굴 다각형 밖 전체(뺌 없음)로도 잰다(G4-2 구현 중 추가) changedFraction | ≤ 0.002 | 머리카락·배경 불변 |
| 원터치 강도 1 | 눈썹 마스크 changedFraction | ≤ 0.05 | 눈썹 불변(보호 영역) |
| 원터치 강도 1 | 남성·공통: 입술 마스크 meanChromaDelta ≤ 0.01. 여성: ≤ 0.03(입술 생기 0.2) | 위 | 립 없음 |
| 원터치 강도 1 | 얼굴형·체형 키 전부 0 | = 0 | 변형은 묶음 밖 |

상한에 걸리면 **표 값이나 상수를 내려서** 맞추고, 그 뒤 하한을 다시 확인한다. 두 방향을 동시에 못 맞추면 그 항목은 표에서 빼고 VALIDATION에 적는다.

#### 1.3 바뀌는 상수 (`RenderTuning`, 시작값 → 새 값)

| 상수 | 이전 | 새 값 | 이유 |
|---|---|---|---|
| `grainMaxAmplitude` | 0.12 | 0.30 | 화면 배율 표준편차 ≥ 5/255 |
| `grainSizeFraction` | 0.0012 | 0.0025 | 알갱이 ≥ 2.5px |
| `rednessFlushMax` | 0.03 | 0.06 | ΔR ≥ 5/255 |
| `rednessClearMax` | 0.7 | 1.0 | 반점 제거율 |
| `rednessReferenceOffset` (신설) | — | 0.01 | 볼 평균보다 이만큼 낮은 Cr을 기준으로 삼아 고르게 붉은 피부도 맑게 |
| `shineLumaOffset` | 0.12 | 0.08 | 부드러운 조명의 번들거림도 잡음 |
| `shineLumaRamp` | 0.1 | 0.08 | 같음 |
| `bodySkinToneMax` (G4-1 구현 중 변경) | 0.025 | 0.035 | (ΔR − ΔB) ≥ 6/255, 1.4절 \|ΔR − ΔB\| ≤ 30/255. 처음 정한 0.05는 하한의 약 7배라 얼굴 전체 주황빛 위험이 있어 내렸다(최종 리뷰) |
| `foldSurroundFraction` | 0.12 | 0.18 | 피부 가중 평균이라 넓혀도 눈·입이 안 섞이고 띠 자신의 비중이 줄어듦 |
| `foldFeatureFeather` (신설) | — | 0.012 | 주름용 피부 비트맵의 보호 영역 넓힘(얼굴 폭 비율). 흐림 반지름 0.015와 비슷해 눈·입 안은 0 유지 |
| `bodySkinFallbackWidthScale` (신설) | — | 3 | 사람 영역 없을 때 얼굴 상자 가로 배수 |
| `bodySkinFallbackHeightScale` (신설) | — | 4 | 얼굴 상자 위끝에서 아래로의 높이 배수 |
| `bodySkinFallbackFeather` (신설) | — | 0.05 | 대체 영역 가장자리 흐림(짧은 변 비율) |
| `eyeWhiteLift` (G4-1 구현 중 변경) | 0.2 | 0.3 | 눈 마스크 평균 \|ΔY\| ≥ 3/255(0.2에서 2.41) |
| `eyeIrisSharpen` (G4-1 구현 중 변경) | 0.8 | 1.0 | 같음. 흰자만 올리면 평균이 모자라고 홍채만 올리면 눈이 어두워진다 |
| 유지 | `midReductionMax`, `toneEveningMax`, `toneBandFraction`, `foldLiftMax`, `foldLiftMaxGain`, `foldLumaFloor`, `bodySkinLiftMax`, `glow*`, 입·메이크업 상수와 위 둘을 뺀 눈 상수 | — | 측정상 충분. 테스트가 미달이면 위 표의 후보를 올린다 |

`FoldShape`(`FaceRegions+Folds.swift`) 변경: 2.1절.

### 2. 주름 재설계와 몸 피부 조건

#### 2.1 띠 마스크 (`FaceRegions+Folds.swift`)

모두 `FaceFrame` 얼굴 좌표(u = 눈 방향, v = 입 → 눈)이고 `softMask(ovals, face:frame:extent:tuning:cache:raster:)`로 만든다. `softMask`에 `raster` 인자를 더해 주름은 **`foldSkinRaster`**(보호 영역 넓힘 `faceWidth × foldFeatureFeather × 2`)를 쓰고 메이크업은 지금처럼 `skinPolygonRaster`(5%)를 쓴다. `foldSkinRaster`는 `polygonMask(fill: [skinPolygon], cut: protectedPolygons, cutWidth:)`라 캐시 항목이 얼굴당 해상도마다 1개 는다(`entriesPerFacePerResolution` 9 → 10).

| 마스크 | 이전 | 새 위치·크기(얼굴 폭 W 기준) | 측정 실패와의 관계 |
|---|---|---|---|
| 다크서클 | 중심 = 눈 아래끝 − 눈 높이 × 0.6, 반지름 (눈 폭 × 0.6, 눈 높이 × 0.8) | 중심 v = 눈 다각형 아래끝 − **W × 0.055**, 반지름 (눈 폭 × 0.65, **W × 0.045**) | 눈 높이(뜬 정도에 따라 W의 6~9%)에 매단 띠가 눈 보호 영역 넓힘(W 5%)에 거의 다 잘렸다. W 기준으로 놓고 넓힘을 1.2%로 줄이면 눈 아래 2~10% 구간이 띠가 된다 |
| 팔자 | 코 날개 → 입꼬리 선분, 반 길이 0.55 × 길이, 반 폭 W 0.035, 바깥 밀기 W 0.02 | 선분 끝을 입꼬리에서 **25% 더 연장**(끝 = 입꼬리 + (입꼬리 − 코 날개) × 0.25), 중심 = 코 날개 → 연장 끝의 중점, 반 길이 0.55 × 연장 길이, 반 폭 **W 0.03**, 바깥 밀기 **W 0.045** | 실사진의 선분은 W의 20% 안팎으로 짧고 입술 넓힘(5%)이 아래 절반을 잘라 코 쪽 조각 둘만 남았다(마스크 그림 확인). 주름은 선분보다 바깥·아래로 이어진다 |
| 마리오네트 | 입꼬리에서 −v로 15° 바깥 기움, 길이 W 0.12, 반지름 (0.07, 0.03), 밀기 0.02 | 길이 **W 0.14**, 반지름 (**0.08**, 0.03), 바깥 밀기 **W 0.03** | 입술 넓힘에 위쪽이 잘렸다. 방향은 그대로(특징점 없음) |
| 미간 | 그대로 | 그대로 | 위치는 맞았다(그림 확인). 실패는 밝히기 기준 때문 |

`FoldShape` 새 이름: `darkCircleDropFraction` 0.055, `darkCircleRadiusU` 0.65(눈 폭 배수, 이름 유지), `darkCircleRadiusVFraction` 0.045, `nasolabialOverrun` 0.25, `nasolabialHalfWidth` 0.03, `nasolabialOutset` 0.045, `marionetteLength` 0.14, `marionetteRadiusU` 0.08, `marionetteOutset` 0.03. `darkCircleDrop`·`darkCircleRadiusV`(눈 높이 배수)는 지운다. `bandOval`에 `outset` 인자를 더해 팔자·마리오네트가 다른 값을 쓴다.

합성 얼굴 표본 점(`SyntheticFace`, 얼굴 폭 280, 계산은 G4-1 계획 Task 2, G4-1 구현 중 격자를 찍어 확정한 값):
- `underLeftEye`·`underRightEye`(200·312, 262)는 새 띠(중심 v 270.6, 반지름 12.6) 안이라 유지한다.
- `leftNasolabial`·`rightNasolabial`은 (202, 156)·(309, 156)이다. 계획의 (206, 162)·(306, 162)는 그늘 없는 피부 상승이 4바이트였고 오른쪽이 픽셀 거울상이 아니어서 대칭(127 vs 118)이 깨졌다. 확정 점은 띠 값 239, 마리오네트 띠 0이다.
- `leftMarionette`·`rightMarionette`는 (196, 120)·(315, 120)이다. 512px 이미지의 픽셀 거울상은 x → 511 − x라 196의 거울은 315다(316에서는 대칭 차이가 4였다).
- 팔자 "밖" 목록에서 `leftMarionette`를 빼고 `CGPoint(x: 186, y: 100)`를 넣는다(연장된 띠 끝에서 3 흐림 이상 떨어진 곳).
- 팔자 띠가 입꼬리 옆까지 이어지는지 보는 점은 (202, 136)이다(값 86, 문턱 64). 계획의 (204, 136)은 값이 정확히 64였다.
- 표본이 어긋나면 G1 규칙대로 격자를 찍어 옮기고 문턱(128·64·0)은 낮추지 않는다.

#### 2.2 밝히기 (`SkinRefinement.liftFold`, `SkinKernels.foldLift`)

- `SkinStage.refine`는 **피부 마스크(`unitMask`)를 주름보다 먼저** 만든다(캐시된 비트맵이라 비용 없음).
- 주변 기준: `surround = FrequencySeparation.maskedMean(image, mask: unitMask × (1 − region.image), radius: W × foldSurroundFraction)` → 분자·분모 두 이미지. 커널 `foldLift`는 `surround` 대신 `wideNumerator`·`wideDenominator`를 받아 `surroundLuma = dot(num.rgb / max(den.r, 0.001), luma601)`로 계산한다. 나머지(`gap = max(surroundLuma − lowLuma, 0)`, `gain = min(1 + amount × gap / max(lowLuma, floor), maxGain)`, `rgb × gain`)는 그대로.
- G1 단위 테스트 `testFoldLiftOnUnshadowedSkinAddsNoBlotchOrColorCast`(그늘 없는 합성 피부, 허용 3바이트)는 G4-1 구현 중 바뀐다. 피부 전용 기준은 띠 안의 어두운 결 얼룩도 주변 피부 수준으로 고르므로 6~10바이트 오른다. 이 테스트는 "색 번짐 없음(띠 안 Cb·Cr 변화 ≤ 0.01)"과 "띠 안 평균 ΔY ≤ +0.08(1.4절 상한)"과 "띠 밖 채널 차이 1바이트 이내"를 단언한다. 띠 밖의 1바이트는 마스크 섞기의 작업 색공간 반올림이고 G4 전에도 있었다(2바이트 이상 바뀐 픽셀 없음). 주변 피부가 없는 띠를 보는 테스트도 같은 이유로 바이트 완전 일치가 아니라 1바이트 이내를 단언하고, 가중치 합이 `foldMinimumCoverage` 아래인 경우(피부 마스크 × 0.01)를 잰다.
- 왜 고쳐지나: 측정된 gap(다크 0.025, 팔자 0.002, 미간 −0.058)은 가중치 없는 반지름 12% 흐림에 눈·눈썹·속눈썹·콧구멍·입술이 들어가 주변이 그늘보다 어둡게 잡힌 값이다. 피부 마스크는 보호 영역과 피부색 가중치로 그것들을 0으로 두고, (1 − 띠)가 그늘 자신을 빼므로 기준이 "띠 둘레의 피부 밝기"가 된다. 반지름을 18%로 넓혀도 피부만 평균되므로 안전하다.
- 질감·색: 곱셈 배율이라 모공 상대 대비와 색조·채도는 그대로다(G1 결정 유지). 합성 결함 없는 띠에서 Cb·Cr 평균 변화 ≤ 0.01을 테스트로 고정한다.
- 마스크 가중 평균의 분모가 0에 가까운 곳(띠 둘레가 전부 보호 영역)은 커널의 `max(den, 0.001)`로 폭주를 막고, 그 경우 `gap`이 음수가 되어 배율 1이다.

#### 2.3 붉은기·번들거림 (상수와 식의 작은 변경)

- 붉은기 −: `excess = max(cr − (cr_ref − rednessReferenceOffset), 0)`, `cr' = cr − excess × clear`(`clear = |v| × rednessClearMax`, 최대 1.0이라 −1에서 기준 아래로 눌림). 커널 `skinRedness`에 `referenceOffset` 인자 추가.
- 번들거림: 상수만(`shineLumaOffset` 0.08, `shineLumaRamp` 0.08).

#### 2.4 몸 피부 조건 (`BodySkinStage`, 앱 피부톤 탭)

- `personMask`가 nil이고 `faces`가 비어 있지 않으면 `BackgroundStage.personMask(...)` 대신 `BodySkinStage.fallbackPersonRegion(face: widest, extent:, tuning:)`을 쓴다: 가장 넓은 얼굴 상자를 중심 x 기준 가로 `bodySkinFallbackWidthScale`배, 상자 위끝에서 아래로 상자 높이 × `bodySkinFallbackHeightScale`만큼의 직사각형을 `MaskBuilder.ellipse`가 아니라 모서리가 둥근 부드러운 사각형(직사각형을 `shortSide × bodySkinFallbackFeather`로 흐림)으로 만든 마스크. 피부색 가중치와 눈·입 제외는 그대로 곱하므로 옷·배경은 가중치가 뺀다. 얼굴이 없으면 지금처럼 건너뛴다(G 결정).
- `PreparedPhoto`·`PhotoInfo`는 바뀌지 않는다. 앱 `AppModel.bodySkinStatus: BodySkinStatus { ready, fallback(noPersonMask), noFace, faceAnalysisUnavailable, personAnalysisUnavailable }`를 계산해 피부톤 탭 맨 위에 한 줄로 보인다(`UserMessage.bodySkinStatus(_:)`: "사람 영역 ✓ · 기준 얼굴 ✓", "사람 영역 없음 → 얼굴 둘레로 대신 적용해요", …). `canAdjustBodySkin`은 `.ready`·`.fallback`·`.personAnalysisUnavailable`에서 켠다(G4-1 구현 중 변경: 사람 분석이 실패해도 얼굴이 있으면 렌더가 대체 영역을 쓰므로 슬라이더를 막지 않는다).

### 3. 원터치 묶음

#### 3.1 레시피 (schemaVersion 2 유지, 키 추가만)

```json
"portrait": { "oneTouch": 0.6, "skin": {…}, "face": {…}, "features": {…} },
"people": { "groups": { "female": { "oneTouch": 0.6, "skin": {…}, "features": {…}, "makeup": {…} },
                        "male":   { "oneTouch": 0.6, "skin": {…}, "features": {…} } },
            "individuals": [ { "id": "…", "anchor": {…}, "gender": "female", "layer": { "oneTouch": 1, "skin": {…} } } ] }
```

- `PortraitAdjustments.oneTouch: Double?`(전체 층), `PortraitLayer.oneTouch: Double?`(그룹·개인 층). 뜻: 이 층의 묶인 항목이 `OneTouchBundle` 표 × 이 강도와 같다는 표시. **렌더는 읽지 않는다.** `hasEffect`·`dependsOnFaces`·`isDefault`·`numericValues`(유한성 검사에는 포함)에서 렌더 의미를 갖지 않는다 — `isDefault`는 `EditRecipe()`와의 비교라 표시만 있는 레시피는 기본이 아니지만, 그런 상태는 규칙상 생기지 않는다(강도 0은 표시도 지움).
- `PortraitLayer.isEmpty`는 `overriddenKeys.isEmpty && makeupLookID == nil && oneTouch == nil`. `overriddenKeys`에는 들지 않는다(키가 아님).
- 스키마: `portrait.oneTouch`(number 0~1 | null, default null), `$defs/portraitLayer.oneTouch` 같음. README "키를 추가할 때의 규칙 (B~H)"에 G4 항목.
- 다른 플랫폼: 같은 키. 표(`OneTouchBundle`)는 플랫폼 공통 계약으로 README에 값 표를 옮겨 적는다.

#### 3.2 표 (`MellowShared/API/OneTouchBundle.swift`)

```swift
public enum OneTouchBundle {
    /// 묶인 키. 이 키를 손으로 바꾸면 그 층의 oneTouch 표시가 지워진다.
    public static let keys: Set<PortraitKey>   // skin 9종 전부, features 3종, makeupPart(.blush), makeupPart(.lip)
    /// 성별 표를 강도만큼 곱한 층. gender nil은 공통 표. 강도는 0…1로 자른다.
    public static func layer(for gender: Gender?, strength: Double) -> PortraitLayer
    /// 사진 단위 몸 피부. 전체 대상에서만 쓴다.
    public static func bodySkin(strength: Double) -> BodySkinAdjustments
    /// 표 값(강도 1).
    public enum Table { … }
}
```

| 항목(강도 1 = 허용 상한) | 공통(미지정) | 여성 | 남성 | 기본 강도 0.6에서 여성 값 |
|---|---|---|---|---|
| skin.smoothing | 0.35 | 0.45 | 0.25 | 0.27 |
| skin.autoBlemish | true | true | true | true |
| skin.darkCircles | 0.55 | 0.6 | 0.5 | 0.36 |
| skin.nasolabial | 0.4 | 0.45 | 0.35 | 0.27 |
| skin.marionette | 0.25 | 0.3 | 0.25 | 0.18 |
| skin.glabella | 0.3 | 0.3 | 0.3 | 0.18 |
| skin.toneEvening | 0.25 | 0.35 | 0.15 | 0.21 |
| skin.redness | −0.2 | −0.25 | −0.2 | −0.15 |
| skin.shine | 0.45 | 0.4 | 0.5 | 0.24 |
| features.eyeBrighten | 0.25 | 0.3 | 0.2 | 0.18 |
| features.teethWhiten | 0.25 | 0.3 | 0.25 | 0.18 |
| features.lipVitality | 0 | 0.2 | 0 | 0.12 |
| makeup.blush | 없음 | `blush-peach` 0.15 | 없음 | 0.09 |
| makeup.lip | 없음 | 없음 | 없음 | 없음 |
| face.* · body.* (변형) | 없음 | 없음 | 없음 | — |
| bodySkin.brightness (전체 대상만) | 0.15 (G4-2 구현 중 0.2에서 내림) | — | — | 0.09 |
| bodySkin.tone (전체 대상만) | 0 (0이면 쓰지 않음, G4-2 구현 중 변경) | — | — | 쓰지 않음 |

- 강도 s: 숫자 × s(`AdjustmentRange`로 자름), `autoBlemish = s > 0`, 블러셔 강도 × s(색은 고정). 남성·공통의 블러셔·립은 층에 `MakeupTint(colorID: nil, intensity: 0)`으로 **덮어쓴다**(상속이 아님 — 전체 층에 블러셔가 있어도 남성은 받지 않게). 여성 층의 `lip`도 0으로 덮어쓴다(립은 묶음 밖이지만 "립 없음"을 보장).
- 표는 `Table` 안 `static let` 상수다(매직 넘버 금지). 값은 취향 결정(사용자 조치)이되 1.4절 상한 테스트를 통과하는 범위 안에서만 고친다.
- 남성 표가 자연스러운 이유: 매끄럽게 0.25는 중간 대역을 21%만 줄여 수염·모공 결이 남고, 얼룩 고르기 0.15는 거의 보이지 않으며, 색 변화는 붉은기 −0.2뿐이다. 여성 표도 매끄럽게 0.45(중간 대역 38%)에서 멈춰 모공 대역은 손대지 않는다. Evoto "부드러운 피부"의 고주파 비 1.02가 과녁이다.
- `OneTouchBundle.maximumStrength = 1`과 `OneTouchBundle.defaultStrength = 0.6`(G4-2 구현 중 변경: Shared에 두고 `EditingPolicy.oneTouchDefaultStrength`가 같은 값을 내보낸다. 렌더 테스트가 숫자를 따로 적지 않게). 슬라이더 범위는 0…`maximumStrength`.

#### 3.3 편집 규칙 (`MellowEditing`)

```swift
public enum EditingPolicy { public static let oneTouchDefaultStrength = OneTouchBundle.defaultStrength }

extension EditDocument {
    /// 대상 층에 표 × 강도를 쓴다. 체크포인트 하나(연속 변경 중이면 없음). 강도 0은 묶인 키를 지운다(전체 층은 기본값, 그 외 상속)와 표시 제거.
    /// .all: 전체 층 ← 공통 표, groups[.male] ← 남성 표, groups[.female] ← 여성 표, bodySkin ← 표. 세 층의 다른 키는 그대로.
    /// .gender(g): 그 그룹 층 ← g 표. .person(id): 그 기록 층 ← 기록의 수동 성별 표(없으면 공통). 모르는 사람은 .unknownPerson.
    /// 잠긴 사진에서도 허용(얼굴형 키는 묶음에 없음).
    @discardableResult public mutating func applyOneTouch(strength: Double, in scope: PortraitScope = .all) -> Rejection?
    /// faces[index]와 짝이 된 사람에게. 기록이 없으면 그 얼굴 anchor로 만든다(H2의 set(_:forFace:of:)와 같은 길, 렌더와 같은 짝짓기).
    /// index가 범위 밖이면 .unknownPerson (H2 구현 중 변경: forPersonAt anchor 대신).
    @discardableResult public mutating func applyOneTouch(strength: Double, forFace index: Int, of faces: [NormalizedRect]) -> Rejection?
}
```

- `.all`에서 그룹 층에 쓸 때 그룹 층의 묶음 밖 키(얼굴형 등)는 보존한다. 개인 층은 건드리지 않는다(사람이 따로 조정한 값은 남고, 그 사람에게는 개인 값이 이긴다 — H 규칙).
- 표시 해제: `set(_:in:)`·`set(_:forFace:of:)`·`applyMakeupLook(_:in:)`·`applyAuto`·`resetOverrides`·`merged`(프리셋·동기화)가 어떤 층의 묶인 키(`OneTouchBundle.keys`)를 실제로 바꾸면 **그 층의** `oneTouch`를 nil로 둔다. 같은 값이면 유지. 구현은 `commit` 전에 `clearOneTouchMarks(where:)`가 이전 레시피와 비교한다.
- (G4-2 구현 중 변경) 몸 피부 밝기는 전체 층 표시의 묶인 항목이다. 손으로 몸 피부 밝기를 바꾸면(동기화의 몸 피부 항목 포함) 전체 층 표시를 지운다. 강도 0은 몸 피부 밝기를 0으로 둔다. 몸 피부 톤은 표 값이 0인 동안 원터치가 쓰지 않고(사용자 톤을 지우지 않음) 표시에도 들지 않는다. 그래서 동기화가 표시를 복사하는 조건에 몸 피부 항목이 든다(아래 동기화 줄).
- (G4-2 구현 중 추가) 표시의 뜻에서 나오는 세 규칙: 개인 기록의 수동 성별을 바꾸면 그 사람 층의 표시를 지운다(표가 달라져 거짓이 됨, 값은 그대로). `resetOverrides(nil, in:)`(층 전체 재설정)는 표시도 지운다. 원터치가 쓰는 층의 룩 이름(`lookID`·`makeupLookID`)은 블러셔·립 값이 실제로 바뀔 때만 지운다(같은 값이면 룩 유지, 기존 룩 규칙과 같음).
- `applyOneTouch`는 `face`·`body` 키를 절대 쓰지 않는다(변형은 묶음 밖, 1.4절 상한 테스트가 고정).
- `applyAuto`: 질문 2가 "포함"이면 `applyAuto(_:oneTouch:)`가 색·디테일을 쓰고 얼굴이 있으면 `applyOneTouch(strength: oneTouchDefaultStrength, in: .all)`을 같은 체크포인트에서 한다(기존 피부 0.3·자동 잡티·눈 0.2 대입은 지움). "분리"면 지금 그대로이고 자동은 전체 층의 표시를 지운다(피부 보정이 바뀌므로).
- 프리셋: `PresetValues`는 `portrait.oneTouch`와 `people.groups[*].oneTouch`를 그대로 나른다(값과 함께). `apply(_:)`는 통째로 바꾸므로 표시도 프리셋 것이 된다.
- 동기화(`merged(..., clearsIndividuals: true)`): `categories`가 `.skin`·`.features`·`.makeup`·`.bodySkin`을 **모두** 포함하면(G4-2 구현 중 변경: `.bodySkin` 추가, 전체 층 표시가 몸 피부 밝기를 대변하므로) 전체 층·그룹 층의 표시를 원본 것으로 복사하고, 하나라도 빠지면 받는 사진의 전체 층·그룹 층 표시를 nil로 둔다. 개인 층은 묶인 키가 지워지므로 표시도 nil.
- `SyncCategory.oneTouchCategories = [.skin, .features, .makeup, .bodySkin]` 상수.

#### 3.4 "자동"과의 관계 (질문 2)

| 선택 | 자동 버튼 | 원터치 버튼 |
|---|---|---|
| 포함(권고) | 색감·디테일 자동 + 얼굴이 있으면 원터치 0.6(전체 대상, 세 층 + 몸 피부) | 뷰티 패널에서 대상별 적용과 강도 |
| 분리 | 지금 그대로(색감·디테일, 피부 0.3, 자동 잡티, 눈 0.2) | 같음 |

G4-3 계획은 두 경우를 모두 적고 사용자의 답으로 하나를 고른다.

### 4. 화면 (`apple/MellowPhoto`)

뷰티 패널(`BeautyPanel`) 위에서 아래로:

1. 얼굴 없음·분석 실패 안내(지금과 같음).
2. `TargetChips`(H3) — 전체 · 남성 · 여성 · 사람 1…n.
3. **원터치 줄** `OneTouchRow`(새 파일 `Features/Editor/OneTouchRow.swift`): 왼쪽 버튼 "원터치 보정"(`wand.and.sparkles`), 오른쪽 `AdjustmentSlider`와 같은 모양의 강도 슬라이더(0…1). 슬라이더 값은 현재 대상 층의 `oneTouch`(전체 대상이면 `portrait.oneTouch`)이고 nil이면 손잡이는 0에 두고 값 자리에 "—"를 보인다. 버튼은 nil이면 `oneTouchDefaultStrength`로 적용, 값이 있으면 그 값으로 다시 적용(사용자 조정을 표로 되돌림). 슬라이더 드래그는 `beginSliderEdit`/`applyOneTouch(strength:)`/`endSliderEdit`로 연속 변경 한 단계.
4. 안내 한 줄: 전체 대상이면 "남성·여성으로 지정한 사람은 각 성별 표로, 미지정은 공통 표로 보정돼요. 성별은 사람 칩에서 지정해요", 그룹이면 "이 그룹 표만 다시 써요", 사람이면 "이 사람의 성별 표를 써요". (G4-3 구현 중 변경) 전체 문구는 원터치 뒤 전체에서 바꾼 피부·눈입·블러셔·립(메이크업 룩 포함)이 성별을 지정한 사람에게는 그룹 값에 가린다는 것을, 그룹·사람 문구는 몸 피부 밝기를 바꾸지 않는다는 것(전체 대상에서만)을 함께 말한다. 문구는 `UserMessage.oneTouchHintAll`·`oneTouchHintGroup`·`oneTouchHintPerson`에 G4-3 Task 1이 둔다.
5. `DisclosureGroup("세부 조정", isExpanded: $model.showsDetailAdjustments)` 안에 지금의 탭 피커와 네 탭 내용. `showsDetailAdjustments`는 세션 상태(기본 false, 파일에 저장 안 함). 세부 슬라이더가 묶인 키이고 그 층의 표시가 있으면 제목 옆에 작은 "원터치" 꼬리표(`Theme.oneTouchTagFont`)를 둔다 — 손으로 바꾸면 꼬리표와 표시가 사라진다.
6. 피부톤 탭 맨 위 상태 줄(2.4절).

`AppModel`: `applyOneTouch(strength:)`(대상 라우팅: `.face(i)` → `forFace: i, of: 얼굴 상자들`, 그 외 `in: scope`, 강도 nil은 버튼이라 열린 드래그를 먼저 끝냄), `oneTouchStrength: Double?`(현재 대상 층의 표시, G4-3 구현 중 변경: 손상 파일 값도 0…`maximumStrength`로 잘라 슬라이더에 넘김), `isOneTouchTagged(_: PortraitKey)`·`isOneTouchTagged(_: BodySkinKey)`(몸 피부 밝기는 전체 층 표시가 있을 때), `showsDetailAdjustments: Bool`, `bodySkinStatus`, 질문 2에 따라 `autoEnhance()`가 `applyAuto(_:oneTouch:)`를 부름. `UserMessage`: `oneTouch`("원터치 보정"), `oneTouchStrength`("강도"), `oneTouchTag`("원터치"), `oneTouchHintAll`·`oneTouchHintGroup`·`oneTouchHintPerson`, `assignGenderForOneTouch`("성별을 지정하면 남녀가 다르게 보정돼요"), `detailAdjustments`("세부 조정"), `bodySkinStatus(_:)`, `diagnosticsTitle`("진단"), `copyDiagnostics`("복사"). `Theme.oneTouchButtonMinWidth` 96, `oneTouchTagFont` caption2.

메이크업 도구는 바꾸지 않는다(H3 칩만).

### 5. H 계획과의 병합

| H 항목 | 처리 | 이유 |
|---|---|---|
| H 스펙 결정 표 | 그대로. 머리말에 "G4가 원터치를 얹는다" 한 줄 | 결정 변경 없음 |
| H1 Task 1~4 | **재사용**. 단 Global Constraints의 브랜치·기준 커밋·iOS 금지 문구 개정 | `PortraitLayer.oneTouch`는 G4-2가 더한다(H1은 더하기만) |
| H2 Task 1~5 | **재사용**(같은 개정) | 원터치는 `set(_:in:)`·`merged` 위에 얹힌다 |
| H3 Task 1 (생성 사진) | **순서 변경**: G4-1 뒤, H1 앞으로 | G4-2 수용 테스트가 커플 사진을 쓴다. 다른 Task와 독립 |
| H3 Task 2 (AppModel 칩) | 재사용 | — |
| H3 Task 3 (TargetChips·BeautyPanel) | **변경**: 칩은 패널 맨 위, 탭 피커는 그대로 두되 G4-3가 "세부 조정" 접기 안으로 옮긴다는 주석. 슬라이더 `isOverridden`·`onReset`은 그대로 | G4-3가 바로 뒤에 패널을 재구성한다 |
| H3 Task 4 (시나리오·문서·VALIDATION) | **변경**: `MELLOW_IOS_TESTS=1` 제거, VALIDATION은 H 절을 쓰되 "iOS 시뮬레이터는 CI에서"로 적음. G4-3 Task 3이 그 뒤에 G4 절을 더함 | 로컬 시뮬레이터 금지 |
| H4 | 그대로 선택. Task 1(조사)은 언제든 병행 가능. Task 4의 로컬 iOS 제거 | 질문 3 |
| 모든 H 계획 Global Constraints | worktree `.claude/worktrees/beauty-g`·브랜치 `beauty-g-evoto` → main `74fb2df`에서 분기한 `beauty-g4`(worktree 선택), "iOS 시뮬레이터 테스트는 로컬에서 돌리지 않는다. CI만" | 기준이 바뀌었다 |

실행 순서: **G4-1 → (H4 Task 1 병행 가능) → H3 Task 1 → H1 → H2 → G4-2 → H3 Task 2 → H3 Task 3 → G4-3 → H3 Task 4 → (승인 시) H4 Task 2~4**. G4-1 뒤 1.3.1 배포 여부는 질문 4.

### 6. 진단 (최소)

- `AppModel.diagnosticLines: [String]`: 앱 버전·빌드(`Bundle.main`), 기기 모델(`DeviceModel.identifier`: macOS `hw.model`, iOS `uname`, 시뮬레이터 `SIMULATOR_MODEL_IDENTIFIER`)·OS(`ProcessInfo`), 선택 사진 픽셀 크기와 미리보기 크기(`preview`), 얼굴 수·사람 영역·관절(`PhotoInfo`), `RecipeSummary.nonDefaultLines(currentRecipe)`(JSON을 펼쳐 기본 레시피와 다른 잎만 `effects.grain=1.00` 형식, 수동 편집 배열은 점·획마다 적지 않고 `operations=N` 한 줄 — G4-1 구현 중 변경), 마지막 오류(`presentedError`가 아닌 `lastRenderFailure: String?`, `scheduleRender` 실패 때 기록). 한국어 라벨은 `UserMessage`, 키 경로는 영어 식별자.
- `InfoSheet`에 `Section(UserMessage.diagnosticsTitle)`과 "복사" 버튼(`UIPasteboard`/`NSPasteboard`, `#if os`). 렌더 파이프라인·모듈 변경 없음.

### 7. 실사진 수용 테스트와 VALIDATION

#### 7.1 테스트 파일

| 파일 | 내용 | 계획 |
|---|---|---|
| `apple/Tests/MellowRenderingTests/RenderingTestSupport.swift` | `DisplayScale`(1.1절 지표), `RealPortrait`(데모 사진 + 실제 Vision 분석 한 번 캐시), 합성 결함 도우미 | G4-1 |
| `apple/Tests/MellowRenderingTests/RealPhotoAcceptanceTests.swift` | 1.2절 하한과 1.4절 상한의 G 항목 전부(원터치 행 제외). 항목마다 테스트 하나, 문턱은 `enum Visibility`·`enum Naturalness` | G4-1 |
| `apple/Tests/MellowRenderingTests/FoldRegionsTests.swift`·`SkinStageTests.swift`·`RegionMaskCacheTests.swift`·`EffectStageTests.swift`·`BodySkinStageTests.swift` | 표본 점·캐시 수·상수 변경 반영, 몸 피부 대체 영역 | G4-1 |
| `apple/Tests/MellowSharedTests/OneTouchBundleTests.swift`, `EditRecipeCodingTests.swift`, `RecipeSchemaTests.swift` | 표·강도 곱·표시 키 왕복·스키마 | G4-2 |
| `apple/Tests/MellowEditingTests/EditDocumentTests.swift` | `applyOneTouch` 대상별, 표시 해제, 강도 0, 프리셋·동기화 표시 규칙, 자동 | G4-2 |
| `apple/Tests/MellowRenderingTests/RealPhotoAcceptanceTests.swift`(확장) | 원터치 기본·최대의 하한(1.2)과 상한(1.4): 여성·남성·공통·차이(데모), 커플 사진(`couple-01.jpg`): 라벨대로 성별 지정 → 전체 원터치 → 남성 얼굴 상자 변화 > 0, 여성 > 남성, 남성 입술 색차 ≤ 0.01 | G4-2 |
| `apple/MellowPhotoTests/AppModelTests.swift`, `EditorScenarioTests.swift`, `OneTouchRowTests.swift` | 원터치 라우팅·강도 표시·세부 조정 접기·상태 줄·진단 줄·시나리오(데모: 원터치 → 강도 → 세부 슬라이더 변경으로 꼬리표 사라짐 → 저장) | G4-1(진단·상태 줄), G4-3 |

실행은 모두 `cd apple && swift test`(macOS)와 Mac 앱 테스트. iOS 시뮬레이터는 CI.

#### 7.2 VALIDATION.md

- G4-1 뒤 `## 인물 보정 G4-1 주름·보이는 강도 (2026-10-XX)`: 자동 검증(명령·종료 코드·테스트 수), 1.2절 표의 **실측값**(문턱 옆에 측정값을 적는다 — 이것이 이번 검증의 핵심), 바뀐 상수, 스펙과 다르게 한 것, 미검증(실기기 화면·저장본 그레인·커플 사진 2차 측정·CI).
- G4-3 뒤 `## 인물 보정 G4 원터치 (2026-10-XX)`: 자동 검증, 원터치 실측(데모·커플), 자동 버튼 결정, 미검증(실기기 남녀 차이·강도·세부 조정 접기·iPhone 폭).
- 수행하지 않은 검증을 통과로 쓰지 않는다. 배포는 하지 않았다고 적는다.

### 8. 계획 분할

| 계획 | 파일 | Task |
|---|---|---|
| G4-1 | `docs/superpowers/plans/2026-10-21-beauty-g4-1-folds-visible-strength.md` | 1 측정 도우미·수용 테스트(빨강) → 2 주름 띠 → 3 밝히기 기준 → 4 상수·몸 피부 대체 영역·상태 줄 → 5 진단 절 → 6 문서·VALIDATION |
| G4-2 | `docs/superpowers/plans/2026-10-21-beauty-g4-2-one-touch-recipe-rules.md` | 1 `OneTouchBundle`·표시 키·스키마 → 2 `applyOneTouch`·표시 해제·프리셋·동기화·자동 → 3 실사진 원터치 수용(데모·커플) |
| G4-3 | `docs/superpowers/plans/2026-10-21-beauty-g4-3-one-touch-ui-validation.md` | 1 `AppModel` 원터치·세부 조정 상태 → 2 `OneTouchRow`·패널 재구성·(질문 2) 자동 연동 → 3 시나리오·문서·VALIDATION |
| H1~H4 개정 | 기존 파일에 "G4 개정" 절과 Global Constraints 수정 | — |
