# 룩(필터) 카탈로그

룩은 Apple 필터 이름이 아니라 이 폴더의 파라미터 데이터로 정의합니다. Apple·Android·Windows 구현은 모두 `looks.v1.json`을 그대로 읽어 같은 룩을 재현해야 합니다. 룩을 플랫폼 코드 안에 따로 적지 않습니다.

레시피는 `look.id`로 이 파일의 룩을 가리킵니다(`shared/recipe-schema/README.md`의 `look` 항목). id·이름·순서는 고정이며, id를 지우거나 바꾸면 기존 레시피가 룩을 잃습니다. 수치는 데모 사진으로 보며 조정할 수 있습니다.

Apple 기준 구현은 `apple/Sources/MellowShared/API/Look.swift`(`Look`, `LookCatalog`)입니다.

## 파일 형식

```json
{ "schemaVersion": 1, "looks": [ { "id": "film", "name": "필름", "toneCurve": [[0,0.03], …], "saturation": 0.92, … } ] }
```

- `schemaVersion`: 지금은 `1`입니다. 읽는 쪽은 모르는 버전을 거부합니다(`LookCatalog.currentSchemaVersion`).
- `looks`: 화면에 보여 줄 순서대로 둔 룩 목록입니다. 순서는 `LookCatalog.builtInIDs`와 같습니다.

| 필드 | 범위 | 의미 |
|---|---|---|
| `id` | 문자열 | 레시피가 저장하는 식별자. 바꾸지 않습니다. |
| `name` | 문자열 | 화면에 보여 줄 이름(한국어). |
| `toneCurve` | 점 5개, 각 `[x, y]`, 0 … 1 | 휘도 입력(x) → 출력(y) 곡선. x는 오름차순이고 첫 점 x는 0, 끝 점 x는 1입니다. |
| `saturation` | 0 … 2 | 채도 배율. 1이 원본, 0이 흑백입니다. |
| `contrast` | 0.5 … 1.5 | 대비 배율. 1이 원본입니다. |
| `warmth` | −1 … 1 | 색온도. 색감 단계의 `color.warmth`와 같은 켈빈 환산을 씁니다. 양수면 따뜻하게. |
| `tint` | −1 … 1 | 틴트. Core Image `CITemperatureAndTint`의 y 성분에 해당합니다. 양수면 마젠타 쪽. |
| `vignette` | 0 … 1 | 가장자리 어둡게 하는 정도. |
| `fade` | 0 … 1 | 블랙 리프트. 톤 커브 시작점(첫 점 y)을 `fade × 0.15`만큼 올립니다(`Look.fadeLift`). |

## 렌더 순서

1. 톤 커브 (`fade`로 시작점을 올린 커브)
2. 색 조정 (`saturation`, `contrast`)
3. 색온도·틴트 (`warmth`, `tint`)
4. 비네팅 (`vignette`)
5. 강도 혼합: 원본과 룩 결과를 레시피의 `look.intensity` 비율로 섞습니다.

다른 플랫폼도 이 순서를 지킵니다. 순서가 다르면 같은 수치라도 결과가 달라집니다.

## 수치 환산

다른 플랫폼이 같은 결과를 내도록 Apple 구현(`apple/Sources/MellowRendering/Domain/LookStage.swift`)의 환산식을 그대로 적습니다. 상수는 `RenderTuning`에 있습니다.

| 항목 | 환산 |
|---|---|
| 톤 커브 | 다섯 점을 그대로 쓰되 첫 점 y만 `min(1, y + fade × 0.15)`로 올립니다(`Look.fadeLift` = 0.15). |
| 채도·대비 | Core Image `CIColorControls`의 `inputSaturation = saturation`, `inputContrast = contrast`. |
| 색온도 | 기준 중립 6500 K(`neutralKelvin`). 목표 중립 = `6500 − warmth × 2000` K(`warmthKelvinRange` = 2000). 색감 단계의 `color.warmth`와 같은 식입니다. `warmth`는 −1 … 1로 잘라 씁니다. |
| 틴트 | `CITemperatureAndTint`의 목표 중립 y = `tint × 60`(`lookTintRange` = 60). 기준 중립 y는 0입니다. |
| 비네팅 | `CIVignette`의 `inputIntensity = vignette`, `inputRadius = 1.5`(`vignetteRadius`). 디테일 단계 비네팅과 같은 반경입니다. |
| 강도 혼합 | `결과 = 원본 + (룩 결과 − 원본) × intensity`(`CIMix`). intensity 0이면 원본, 1이면 룩 결과 그대로입니다. |

룩은 렌더 파이프라인 맨 끝 단계라 자르기·회전이 끝난 현재 이미지 범위에 적용됩니다. 비네팅도 잘린 프레임 기준입니다.

## 수치 변경 기록

- 2026-10-15(B0 구현 중): `sepia`의 `warmth` 0.6 → 0.7, `vignette` 0.15 → 0.1. 작은 회색 이미지의 모서리에서 따뜻함과 비네팅이 서로 상쇄돼 강도 0.5 결과가 원본과 같아졌기 때문입니다. 실제 사진으로 본 조정은 아직 없습니다.

## 앱 번들 사본

Apple 앱은 `apple/MellowPhoto/Resources/looks.v1.json` 사본을 번들에 넣어 읽습니다. 이 파일을 고치면 사본도 같은 커밋에서 복사합니다.

```bash
cp shared/looks/looks.v1.json apple/MellowPhoto/Resources/looks.v1.json
```

두 테스트가 지킵니다.

- `apple/Tests/MellowSharedTests/LookCatalogTests.swift`: 이 파일을 읽어 룩 10개의 id 순서, 톤 커브 점 개수·x 오름차순·끝점, 값의 범위, 모르는 `schemaVersion` 거부를 확인합니다.
- `apple/MellowPhotoTests/BundledLooksTests.swift`: 앱 번들 사본이 이 파일과 바이트 단위로 같은지 확인합니다.
