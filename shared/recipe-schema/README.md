# 레시피·세션 파일 스키마

Apple·Android·Windows 구현이 함께 읽고 쓰는 파일 형식의 계약입니다. 기준 구현은 Apple 코드이며, 형식을 바꾸면 이 폴더의 스키마도 같은 커밋에서 고칩니다.

| 파일 | 기술하는 것 | Apple 기준 구현 |
|---|---|---|
| `edit-recipe.v2.schema.json` | 사진 한 장의 보정 레시피 `EditRecipe` | `apple/Sources/MellowShared/API/EditRecipe.swift`, `Adjustments.swift`, `SkinAdjustments.swift`, `FaceShapeAdjustments.swift`, `FeatureAdjustments.swift`, `BackgroundAdjustments.swift`, `BodySkinAdjustments.swift`, `BodyShapeAdjustments.swift`, `MakeupAdjustments.swift`, `EffectAdjustments.swift`, `PeopleAdjustments.swift`, `DetailAdjustments.swift`, `LookSelection.swift`, `GeometryAdjustments.swift`, `LocalEdit.swift` |
| `session-file.v2.schema.json` | 작업 세션 파일 `session.json` 전체(사진 목록, 사진별 레시피와 실행 취소·다시 실행 기록, 선택한 사진, 사용자 프리셋) | `apple/Sources/MellowLibrary/Infrastructure/SessionFile.swift` |

`session-file.v2`는 레시피 부분을 `edit-recipe.v2.schema.json`의 `$ref`로 가리킵니다. 검증기에는 두 스키마를 각자의 `$id`로 등록하거나, 같은 폴더에서 파일 이름으로 읽게 하세요. 어느 방식이든 `$ref`가 풀리도록 두 `$id`(`https://mellow.photo/schema/edit-recipe.v2.schema.json`, `…/session-file.v2.schema.json`)를 파일 이름과 같게 맞췄습니다.

두 테스트가 실제 Apple 인코드 결과의 **키 집합**을 스키마의 `properties` 키 집합과 비교합니다.

- `apple/Tests/MellowSharedTests/RecipeSchemaTests.swift`: 피부·얼굴형·디테일·배경·체형·메이크업까지 채운 레시피를 인코드해 최상위 키, 각 그룹 키, `portrait.skin/face/features`, `makeup`의 부위 키를 비교합니다. `deprecated: true`인 읽기 전용 옛 키는 비교에서 뺍니다. `geometry.crop` 키, 그리고 각 `operations` 항목의 키를 `type.const`가 같은 `oneOf` 분기의 `properties` 키와 비교하고 `$id`도 확인합니다.
- `apple/Tests/MellowLibraryTests/SessionSchemaTests.swift`: 사진 한 장(실행 취소·다시 실행 기록 포함)과 프리셋 하나가 든 세션을 `SessionFile.encode`로 인코드해 최상위 키, `photos` 항목 키, `presets` 항목 키, 프리셋 `values` 키를 비교합니다. `$id`도 확인합니다.

값의 범위(`minimum`·`maximum`·`maxItems`·`maxLength`), 타입, `required` 목록, `$ref`가 가리키는 하위 구조의 키는 기계로 검사하지 않습니다. 키를 추가하거나 고치면 위 키 집합이 어긋나 테스트가 스키마 갱신을 요구하지만, 범위나 필수 여부를 바꿀 때는 사람이 스키마를 직접 맞춰야 합니다.

## v2 형식 요점

- 좌표(`x`, `y`, `sourceX`, `sourceY`, `dx`, `dy`, `radius`)는 방향 보정된 이미지 기준 0~1 정규화 값이고, 원점은 왼쪽 아래입니다.
- B0~G의 `portrait.targetFace`(왼쪽부터 센 얼굴 인덱스, "이 값을 i번 얼굴에만")는 읽기만 합니다(`deprecated: true`). `people.individuals`가 비어 있을 때만 `portrait`(`skin`·`face`·`features`)와 `makeup` 중 기본값과 다른 키 전부를 `people.individuals[0].layer`로 옮기고 전체 층은 기본값으로 둡니다. 그 기록은 `legacyIndex = i`와 결정적 id(`B0000000-0000-0000-0000-` 뒤 12자리 인덱스)를 갖고 anchor가 없습니다. 인덱스가 0…999 999 999 999 밖이면(음수·손상 파일) 범위의 마지막 값으로 모아 어느 얼굴과도 짝이 되지 않게 합니다. 옮길 값이 없으면 기록을 만들지 않습니다. 렌더 결과는 옛 뜻과 같습니다. 사진을 준비한 뒤 `legacyIndex`의 얼굴로 anchor를 채우면 `legacyIndex`를 지웁니다. 쓸 때는 `targetFace`를 쓰지 않습니다.
- `portrait`는 `skin`(피부 보정 `smoothing` 0~1, 자동 잡티 `autoBlemish`, G의 피부 정밀 `darkCircles`·`nasolabial`·`marionette`·`glabella`·`toneEvening`·`shine` 0~1과 `redness` −1~1), `face`(얼굴형 10개, 가운데 0인 양방향, `smile`만 0~1), `features`(눈 또렷하게·치아 미백·입술 생기 0~1)로 나뉩니다.
- 최상위 `background`(배경 흐림), `bodySkin`(몸 피부 밝기·톤·매끄럽게, `tone`만 −1~1), `body`(체형 7개, `legLength`만 0~1), `makeup`(룩 id와 부위별 색 id·강도), `effects`(그레인·글로우 0~1, 룩 뒤 마지막 단계)가 있습니다. 렌더는 단계별로 들어오며 값이 기본이면 결과가 바뀌지 않습니다.
- `people`은 사람별·성별 그룹 보정(H)입니다. `portrait`·`makeup`이 전체 층, `people.groups.male/female`이 성별 그룹 층, `people.individuals[].layer`가 개인 층이며 위 층이 아래 층을 키 단위로 덮어씁니다. 층은 있는 키만 담습니다(없음 = 상속). 층의 메이크업은 부위 단위로 덮어쓰고 부위 객체의 `colorID`가 없거나 `null`이면 "색 없음"으로 덮어씁니다. 층 스키마는 `$defs/portraitLayer` 하나입니다. `individuals[].anchor`는 정규화 얼굴 상자의 중심·폭이고 `gender`는 사용자가 지정한 성별만 담습니다(자동 추정은 저장하지 않음). `legacyIndex`는 옛 `targetFace`에서 이행한 기록에만 있습니다. 기록에는 `anchor`와 `legacyIndex` 중 하나가 있어야 합니다(`anyOf`). 읽는 쪽은 관대하게 읽습니다: `layer`가 없으면 빈 층, 모르는 `gender` 문자열은 미지정이고, `id`나 `anchor`가 잘못된 기록은 그 기록만 버리며, 같은 `id`의 기록이 둘 이상이면 앞의 것만 남깁니다. 편집과 렌더는 같은 전역 1:1 짝짓기 결과로 얼굴의 사람을 정합니다. Apple 구현은 레시피에 `people` 키를 늘 쓰고(`{}` 포함), 비어 있는 `groups`·`individuals`와 층의 빈 그룹 객체는 생략합니다.
- B0까지 쓰던 `portrait.skinSmoothing`·`portrait.faceSlim`은 읽기만 합니다. `skin`이 없으면 `skin.smoothing = skinSmoothing`, `face`가 없으면 `face.width = −faceSlim`(0은 0)으로 읽고, 쓸 때는 새 키만 씁니다. 스키마에는 `deprecated: true`로 남아 있어 이전 파일도 검증을 통과합니다.
- `detail`은 하이라이트·그림자·선명도·비네팅입니다. 기본값은 모두 0입니다.
- `look`은 필터 선택입니다. `id`는 `shared/looks/looks.v1.json`의 룩 id이고, 값이 없으면 필터를 쓰지 않습니다. `intensity`는 원본과 룩 결과의 혼합 비율이며 기본값은 1입니다.
- `geometry`는 반전(`flipHorizontal`) → 시계 방향 90° 회전(`quarterTurns`, 0~3) → 수평 보정(`straightenDegrees`, 양수면 시계 방향) → 자르기(`crop`) 순서로 적용합니다. `crop`은 그 앞 단계가 끝난 이미지 기준 정규화 사각형(`x`, `y`, `width`, `height`)이고, 값이 없으면 자르지 않습니다.
- 사용자가 회전·반전을 누르면 자르기 영역과 수평 보정도 이미지와 함께 옮겨 같은 부분이 계속 보이게 합니다. 모든 플랫폼이 같은 규칙으로 `geometry`를 고칩니다(Apple 기준 구현 `GeometryAdjustments.turnedClockwise()`·`flippedHorizontally()`).
  - 시계 방향 90° 회전: `quarterTurns` → (`quarterTurns` mod 4 + 1) mod 4, `crop` (x, y, w, h) → (y, 1 − x − w, h, w). `straightenDegrees`는 그대로입니다.
  - 좌우 반전은 화면에 보이는 그대로의 좌우입니다. `flipHorizontal`을 뒤집고, 회전이 홀수(1·3)면 `quarterTurns`에 2를 더합니다(mod 4). `crop`은 x → 1 − x − w, `straightenDegrees`는 부호를 바꿉니다(0은 0 그대로).
  - 렌더할 때 `crop`의 픽셀 경계는 변마다 가장 가까운 픽셀로 반올림합니다. 바깥으로 넓히지 않습니다.
- 프리셋 `values`는 `color`·`portrait`·`detail`·`background`·`bodySkin`·`body`·`makeup`·`effects`·`people`을 담습니다. 없는 그룹은 기본값으로 읽습니다. 룩과 기하는 프리셋에 담지 않습니다. `people`은 `groups`만 담고 `individuals`는 읽을 때 버립니다.
- `operations`는 사용자가 기록한 순서대로 재생합니다. 각 항목은 `"type": "spot"` 또는 `"type": "warp"`와 그 값을 같은 객체에 평평하게 담습니다.
- 사진별 `undo`는 최대 40개입니다(`EditingPolicy.historyLimit`). 프리셋 이름은 최대 30자입니다(`LibraryPolicy.presetNameLimit`).
- `filename`은 작업 사본의 파일 이름만 담습니다. 폴더는 플랫폼이 정합니다. Apple은 `Application Support/MellowPhoto/Library/<uuid>.<확장자>`에 둡니다.
- Apple 구현은 값이 없는 선택 키(`look.id`, `geometry.crop`, `makeup.lookID`, `makeup.*.colorID`, `people.individuals[].anchor`·`legacyIndex`·`gender`, `selectedPhotoID`)를 `null`로 쓰지 않고 키 자체를 생략합니다. 읽는 쪽은 생략과 `null`을 같은 뜻으로 받아야 합니다.
- 읽을 때는 빠진 키를 기본값으로 채웁니다. 기본값은 스키마의 `default`와 같습니다.

### 값의 범위: 스키마 한계와 UI 권장 범위

스키마의 `minimum`·`maximum`은 **하드 한계**입니다. 이 밖의 값은 잘못된 파일입니다. 앱 슬라이더는 그보다 좁은 **권장 범위**만 보여 줍니다. 권장 범위는 화면 정책이지 파일 형식의 제약이 아니므로, 읽는 쪽은 권장 범위를 벗어났지만 스키마 한계 안에 있는 값(예: 다른 플랫폼이나 이후 버전이 쓴 노출 2.0)을 거부하지 말고 그대로 렌더해야 합니다.

| 키 | 스키마 한계 | UI 권장 범위 (Apple 슬라이더) |
|---|---|---|
| `color.exposure` | −3 … 3 | −1.5 … 1.5 |
| `color.contrast` | 0 … 2 | 0.7 … 1.3 |
| `color.saturation` | 0 … 2 | 0 … 1.5 |
| `color.warmth` | −1 … 1 | −1 … 1 |
| `portrait.skin.smoothing` | 0 … 1 | 0 … 1 |
| `portrait.skin.{darkCircles,nasolabial,marionette,glabella,toneEvening,shine}` | 0 … 1 | 0 … 1 |
| `portrait.skin.redness` | −1 … 1 | −1 … 1 |
| `portrait.face.*` | −1 … 1 (`smile` 0 … 1) | 같음 |
| `portrait.features.*` | 0 … 1 | 0 … 1 |
| `background.blur` | 0 … 1 | 0 … 1 |
| `bodySkin.{brightness,smoothing}` | 0 … 1 | 0 … 1 |
| `bodySkin.tone` | −1 … 1 | −1 … 1 |
| `body.*` | −1 … 1 (`legLength` 0 … 1) | 같음 |
| `makeup.*.intensity` | 0 … 1 | 0 … 1 |
| `effects.*` | 0 … 1 | 0 … 1 |
| `detail.highlights` | −1 … 1 | −1 … 1 |
| `detail.shadows` | −1 … 1 | −1 … 1 |
| `detail.sharpness` | 0 … 1 | 0 … 1 |
| `detail.vignette` | 0 … 1 | 0 … 1 |
| `look.intensity` | 0 … 1 | 0 … 1 |
| `geometry.straightenDegrees` | −15 … 15 | −15 … 15 (`GeometryAdjustments.maxStraightenDegrees`) |

Apple의 권장 범위는 `apple/MellowPhoto/Features/Editor/ColorPanel.swift`와 `BeautyPanel.swift`의 슬라이더 `range`이고, 권장 범위는 `EditingPolicy`의 명명 상수입니다. `detail`·`look`·`geometry` 행은 B0 기본 편집 패널이 따를 값입니다. 다른 플랫폼도 같은 권장 범위를 쓰는 것을 원칙으로 합니다.

## v1: 출시된 iPhone 앱의 형식

iPhone 1.0.0이 쓰던 `session.json`은 `schemaVersion` 키가 없습니다. 이 키가 없으면 v1로 판별합니다. 실제 예시는 `shared/fixtures/session-v1.json`이며, 출시 기준 커밋의 코드로 인코드해 만든 파일입니다(손으로 쓰지 않았습니다).

```json
{
  "photos": [
    { "id": "UUID", "filename": "UUID.heic", "name": "사진 1",
      "recipe": {
        "adjustments": { "exposure": 0.4, "contrast": 1, "saturation": 1, "warmth": 0, "skin": 0.3, "faceSlim": 0.2 },
        "operations": [ { "spot": { "_0": { "x": 0.5, "y": 0.4, "sourceX": 0.45, "sourceY": 0.4, "radius": 0.02 } } },
                        { "warp": { "_0": { "x": 0.5, "y": 0.4, "dx": 0.01, "dy": 0, "radius": 0.08 } } } ],
        "selectedFace": 1 } }
  ],
  "selectedID": "UUID",
  "presets": [ { "id": "UUID", "name": "포근한", "adjustments": { "…": "위와 같은 여섯 값" } } ],
  "undoHistory": [ "UUID", [ { "adjustments": {}, "operations": [] } ] ],
  "redoHistory": [ "UUID", [ ] ]
}
```

주의할 점:

- **`undoHistory`와 `redoHistory`는 객체가 아니라 평탄 배열입니다.** Swift가 키가 문자열이 아닌 딕셔너리(`[UUID: [Recipe]]`)를 `[키1, 값1, 키2, 값2, …]` 순서로 인코드했기 때문입니다. 짝수 칸은 사진 ID 문자열, 홀수 칸은 그 사진의 레시피 배열입니다. JSON 객체로 읽으려 하면 실패합니다.
- `operations`의 각 항목은 Swift 합성 Codable의 enum 표현 `{"spot": {"_0": {…}}}`입니다.
- 두 기록 키는 없을 수도 있습니다.

v1 → v2 변환 규칙(`apple/Sources/MellowLibrary/Infrastructure/SessionFileV1.swift`):

| v1 | v2 |
|---|---|
| `photos[].name` | `photos[].displayName` |
| `recipe.adjustments.{exposure,contrast,saturation,warmth}` | `recipe.color.*` |
| `recipe.adjustments.skin` | `recipe.portrait.skin.smoothing` |
| `recipe.adjustments.faceSlim` | `recipe.portrait.face.width` (부호 반대, 0은 0) |
| `recipe.selectedFace` | `recipe.people.individuals[0]`(`legacyIndex`, 전체 층 값을 개인 층으로, 위 `targetFace` 이행과 같음) |
| `{"spot":{"_0":{…}}}` | `{"type":"spot", …}` (warp도 같음) |
| `undoHistory`/`redoHistory`의 해당 사진 항목 | 각 사진의 `undo`/`redo` |
| `selectedID` | `selectedPhotoID` (목록에 없으면 첫 사진) |
| `presets[].adjustments` | `presets[].values.{color,portrait}` |

v1은 읽기만 합니다. 저장은 항상 v2로 합니다.

## 키를 추가할 때의 규칙 (B~H)

B 단계에서 B~F의 레시피 골격(`portrait.skin/face/features`, `background`, `body`, `makeup`)을 한 번에 넣었습니다. 이후 단계는 렌더만 채웁니다. 새 키가 더 필요하면 다음을 지킵니다. G 단계는 `portrait.skin`에 피부 정밀 7개, 최상위 `bodySkin`·`effects`를 같은 규칙으로 더했습니다(기본값 0, schemaVersion 2 유지). H 단계는 최상위 `people`을 같은 규칙으로 더했습니다(기본값 비어 있음, schemaVersion 2 유지).

1. **새 키는 반드시 기본값을 가집니다.** 키가 없는 기존 파일은 기본값으로 읽혀 지금과 같은 결과를 내야 합니다. 스키마에도 `default`를 적고 `required`에 넣지 않습니다.
2. **키를 지우거나 이름을 바꾸지 않습니다.** 더 쓰지 않는 값도 읽기는 계속합니다. 의미를 바꿔야 하면 새 키를 만듭니다.
3. **`schemaVersion`은 호환이 깨질 때만 올립니다.** 키 추가는 호환을 깨지 않으므로 v2를 유지합니다. 버전을 올리면 이전 버전 디코더(v1 포함)를 계속 유지하고, 새 스키마 파일(`*.v3.schema.json`)을 따로 둡니다.
4. 스키마는 `additionalProperties: false`이므로 키를 추가하는 커밋에서 스키마도 함께 고칩니다. `RecipeSchemaTests`·`SessionSchemaTests`가 키 집합의 어긋남을 잡습니다.
5. 모든 플랫폼이 같은 키 이름과 기본값을 씁니다. 다른 플랫폼은 `shared/fixtures/`의 파일로 읽기 호환을 테스트합니다.
