# 메이크업 카탈로그

메이크업 팔레트와 룩은 이 폴더의 데이터로 정의합니다. Apple·Android·Windows 구현은 모두 `makeup.v1.json`을 그대로 읽습니다. 색이나 룩을 플랫폼 코드 안에 따로 적지 않습니다.

레시피는 `makeup.lookID`와 부위별 `colorID`로 이 파일을 가리킵니다(`shared/recipe-schema/README.md`의 `makeup` 항목). id는 고정이며, 지우거나 바꾸면 기존 레시피의 색이 빠집니다. 이름과 수치는 실제 사진으로 보며 조정할 수 있습니다.

Apple 기준 구현은 `apple/Sources/MellowShared/API/MakeupCatalog.swift`(`MakeupColor`, `MakeupLook`, `MakeupCatalog`)입니다.

## 파일 형식

```json
{ "schemaVersion": 1,
  "colors": { "lip": [ { "id": "lip-coral", "name": "코랄", "rgb": [0.96, 0.45, 0.38] }, … ], "blush": [ … ], "eyeshadow": [ … ] },
  "looks": [ { "id": "daily", "name": "데일리", "lip": { "colorID": "lip-mlbb", "intensity": 0.5 }, …, "brow": { "intensity": 0.3 }, "contour": { "intensity": 0.2 } } ] }
```

- `schemaVersion`: 지금은 `1`입니다. 읽는 쪽은 모르는 버전을 거부합니다(`MakeupCatalog.currentSchemaVersion`).
- `colors`: 색을 고르는 세 부위(`lip` 6색, `blush` 4색, `eyeshadow` 4색)의 팔레트. 배열 순서가 화면 순서입니다. 눈썹·쉐딩은 색이 없습니다.
- `looks`: 화면 순서대로 둔 룩 5개(`daily`, `cool`, `warm-peach`, `rosy`, `smoky`, `MakeupCatalog.builtInLookIDs`).

| 필드 | 범위 | 의미 |
|---|---|---|
| 색 `id` | 문자열, 파일 전체에서 유일 | 레시피가 저장하는 식별자. 바꾸지 않습니다. |
| 색 `name` | 문자열 | 화면에 보여 줄 이름(한국어). |
| 색 `rgb` | 숫자 3개, 각 0 … 1 | sRGB 감마 값. |
| 룩 `id`·`name` | 문자열 | 룩 식별자와 이름. |
| 룩 `lip`·`blush`·`eyeshadow` | `{ colorID, intensity }` | `colorID`는 그 부위 팔레트의 색(다른 부위 색은 거부), `intensity` 0 … 1. |
| 룩 `brow`·`contour` | `{ intensity }` | 0 … 1. |

읽는 쪽은 형식이 틀린 파일(모르는 부위, rgb 개수·범위, 중복 id, 다른 부위 색을 쓰는 룩, 범위 밖 강도) 전체를 거부하고 메이크업 없이 동작합니다.

## 룩 적용 규칙

룩을 고르면 룩의 부위 값 다섯 개를 레시피 `makeup`에 그대로 써 넣고 `lookID`를 기록합니다(실행 취소 한 단계). 이후 부위 하나라도 값을 바꾸면 `lookID`를 비웁니다. 룩 "없음"은 메이크업을 모두 지웁니다. 색을 처음 고를 때 그 부위 강도가 0이면 0.5로 둡니다.

## 렌더

메이크업은 렌더 파이프라인의 `feature`(눈·치아·입술 생기) 다음, `background` 앞 단계입니다. 얼굴 특징점에서 만든 영역 안에서만 바꾸고, 강도 = 부위 강도 × 부위 최대 불투명도(Apple `RenderTuning`)로 원본과 섞습니다. 섞기는 작업 색공간(선형 sRGB)에서 합니다.

| 부위 | 영역 | 섞기 | 최대 불투명도 |
|---|---|---|---|
| 립 | 바깥 입술 − 안쪽 입술 | 소프트 라이트(고른 색) | 0.85 |
| 블러셔 | 두 눈 아래·코 옆 볼 타원 × 얼굴 피부 영역 | 소프트 라이트(고른 색) | 0.6 |
| 아이섀도 | 윗눈꺼풀부터 눈썹 아래까지 거리의 75% 띠 − 눈 | 곱하기(고른 색) | 0.45 |
| 눈썹 | 눈썹을 가로 1.15배·세로 1.6배 넓힌 영역 | 곱하기(원래 눈썹 평균색) | 0.5 |
| 쉐딩 | 광대 아래·턱선·코 옆 타원 × 얼굴 피부 영역 | 곱하기(회갈색 `[0.72, 0.6, 0.52]`) | 0.4 |
| 하이라이터 | 콧대·이마 가운데·턱 끝 타원 × 얼굴 피부 영역 | 스크린(`[1, 0.97, 0.92]`) | 0.3 |

순서는 쉐딩·하이라이터 → 블러셔 → 아이섀도 → 눈썹 → 립입니다. 위치 비율은 Apple `apple/Sources/MellowRendering/Domain/FaceRegions+Makeup.swift`의 `MakeupShape`에 있습니다.

## 앱 번들 사본

Apple 앱은 `apple/MellowPhoto/Resources/makeup.v1.json` 사본을 번들에 넣어 읽습니다. 이 파일을 고치면 사본도 같은 커밋에서 복사합니다.

```bash
cp shared/makeup/makeup.v1.json apple/MellowPhoto/Resources/makeup.v1.json
```

두 테스트가 지킵니다.

- `apple/Tests/MellowSharedTests/MakeupCatalogTests.swift`: 이 파일을 읽어 룩·색 id 순서, 값 범위, 룩이 자기 부위 색만 쓰는지, 형식 위반 거부를 확인합니다.
- `apple/MellowPhotoTests/BundledLooksTests.swift`: 앱 번들 사본이 이 파일과 바이트 단위로 같은지 확인합니다.
