# 체형 생성 사진 세트(가상 인물)

모든 인물은 가상이며 실존 인물과 무관하다.

## 생성

- 도구: codex-cli 0.163.0(`codex exec`), OpenAI 이미지 생성 도구(codex 내장 `image_gen`).
- 날짜: 2026-10-21.
- 원본: 1024×1024 PNG. 저장소에는 `sips -Z 1024 -s format jpeg -s formatOptions 90`으로 바꾼 JPEG만 둔다.
- 모든 프롬프트에 "fictional people who do not resemble any real person or celebrity, no text, no watermark, no logos"를 넣었다.
- 생성 호출은 다섯 번이었다.
- `torso-01`의 첫 프롬프트("fitted sleeveless black top … arms held slightly away from the torso")는 이미지 도구의 안전 필터가 거절해 사진이 나오지 않았다. 옷차림과 팔 자세를 풀어 쓴 두 번째 프롬프트로 만들었다.

| 파일 | 프롬프트 요지 |
| --- | --- |
| `chin-01.jpg` | 30대 후반 남자, 정면 머리·어깨, 옅은 미소, 턱선 아래 부드러운 이중턱, 밝은 회색 무지 배경, 깃 셔츠, 얼굴 폭 사진의 약 35% |
| `torso-01.jpg` | 20대 후반 여자, 정면 머리부터 엉덩이까지, 검은 민소매 상의와 청바지, 팔은 자연스럽게 내리되 손을 몸에서 조금 떼어 팔과 허리 사이로 배경이 보임, 밝은 회색 무지 배경 |
| `couple-body-01.jpg` | 30대 남녀가 나란히 정면, 머리부터 엉덩이까지, 어깨가 거의 닿음, 왼쪽 남자, 몸에 맞는 티셔츠, 단순한 실내 배경 |
| `lines-01.jpg` | 30대 여자, 정면 머리부터 엉덩이까지, 팔을 몸통에서 조금 뗌, 흰 타일 벽 앞, 좌우에 곧은 세로 문틀과 가로 타일선, 고른 조명 |

## 용도

- 저장소 안 자동 수용 테스트(`apple/Tests/MellowRenderingTests/Fixtures/body/`에 사본).
  - `chin-01`: 이중턱 워프와 턱밑 그늘.
  - `torso-01`: 허리·팔 보호와 실루엣 이동.
  - `couple-body-01`: 얼굴과 몸의 짝, 사람별 체형 값.
  - `lines-01`: 실루엣 근처를 뺀 배경 직선 보존.
- 수동 확인.

Vision이 생성 사진에서 실사진과 다르게 동작할 수 있다.

## 사용 조건

생성물의 권리와 사용 조건은 OpenAI 이용 약관을 따른다.
저장소 밖 배포·마케팅에 쓰지 않는다.
최종 확인은 사용자 조치다.

## 라벨 형식(`labels.json`)

- `version`: 형식 버전(현재 1).
- `photos[].file`: 이 폴더의 파일 이름.
- `photos[].notes`: 생성 조건을 눈으로 확인한 결과다.
- `photos[].people`: 사진 속 사람을 왼쪽부터 나열한다. 눈으로 확인한 값이다.
  - `gender`: `male`·`female`.
  - `ageBand`: `child`·`young`·`adult`·`senior`.
  - `glasses`: 안경 착용 여부.
  - `pose`: `frontal`·`turned`·`profile`.
  - `occlusion`: `none`·`partial`(손·다른 사람 등으로 몸이나 얼굴 일부 가림).
  - `ambiguous`: 눈으로 봐도 성별이 모호하면 `true`.
