# 생성 사진 세트(가상 인물)

모든 인물은 가상이며 실존 인물과 무관하다.

## 생성

- 도구: codex-cli 0.163.0(`codex exec`), OpenAI 이미지 생성 도구(codex 내장 `image_gen`).
- 날짜: 2026-10-20.
- 원본: 1024×1024 PNG. 저장소에는 `sips -Z 1024 -s format jpeg -s formatOptions 90`으로 바꾼 JPEG만 둔다.
- 모든 프롬프트에 "fictional people who do not resemble any real person or celebrity, no text, no watermark"를 넣었다.

| 파일 | 프롬프트 요지 |
| --- | --- |
| `couple-01.jpg` | 성인 남 1·여 1, 왼쪽 남자, 정면, 실내 부드러운 햇빛 |
| `couple-02.jpg` | 성인 남 1(안경)·여 1(약 45° 돌림), 야외 해 질 녘 역광 |
| `group-01.jpg` | 5명 한 줄(여·남·여·남·여), 피부톤 세 가지 이상, 20대~60대, 모두 정면 |
| `group-02.jpg` | 6명 공원, 나이대 섞임, 넷째 여자는 손으로 볼 가림, 여섯째 여자는 옆얼굴 |
| `group-03.jpg` | 4명 실내 따뜻한 조명, 첫째 여자 안경, 셋째 여자는 둘째 남자 뒤에서 얼굴 일부 가림 |

## 용도

- 저장소 안 자동 시나리오 테스트(`couple-01`·`group-01`은 `apple/Tests/MellowRenderingTests/Fixtures/people/`에 사본).
- 수동 확인.
- H4 성별 추정 정확도 측정.

Vision이 생성 얼굴에서 실사진과 다르게 동작할 수 있어 자동 테스트의 1차 근거는 `SyntheticFace`다.

## 사용 조건

생성물의 권리와 사용 조건은 OpenAI 이용 약관을 따른다.
저장소 밖 배포·마케팅에 쓰지 않는다.
최종 확인은 사용자 조치다.

## 라벨 형식(`labels.json`)

- `version`: 형식 버전(현재 1).
- `photos[].file`: 이 폴더의 파일 이름.
- `photos[].people`: 사진 속 사람을 왼쪽부터 나열한다. 눈으로 확인한 값이다.
  - `gender`: `male`·`female`.
  - `ageBand`: `child`·`young`·`adult`·`senior`.
  - `glasses`: 안경 착용 여부.
  - `pose`: `frontal`·`turned`·`profile`.
  - `occlusion`: `none`·`partial`(손·다른 사람 등으로 얼굴 일부 가림).
  - `ambiguous`: 눈으로 봐도 성별이 모호하면 `true`.
