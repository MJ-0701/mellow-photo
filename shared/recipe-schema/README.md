# 레시피·세션 파일 스키마

Apple·Android·Windows 구현이 함께 읽고 쓰는 파일 형식의 계약입니다. 기준 구현은 Apple 코드이며, 형식을 바꾸면 이 폴더의 스키마도 같은 커밋에서 고칩니다.

| 파일 | 기술하는 것 | Apple 기준 구현 |
|---|---|---|
| `edit-recipe.v2.schema.json` | 사진 한 장의 보정 레시피 `EditRecipe` | `apple/Sources/MellowShared/API/EditRecipe.swift`, `Adjustments.swift`, `LocalEdit.swift` |
| `session-file.v2.schema.json` | 작업 세션 파일 `session.json` 전체(사진 목록, 사진별 레시피와 실행 취소·다시 실행 기록, 선택한 사진, 사용자 프리셋) | `apple/Sources/MellowLibrary/Infrastructure/SessionFile.swift` |

`session-file.v2`는 레시피 부분을 `edit-recipe.v2.schema.json`의 `$ref`로 가리킵니다. 검증기에는 두 스키마를 각자의 `$id`로 등록하거나, 같은 폴더에서 파일 이름으로 읽게 하세요. 어느 방식이든 `$ref`가 풀리도록 두 `$id`(`https://mellow.photo/schema/edit-recipe.v2.schema.json`, `…/session-file.v2.schema.json`)를 파일 이름과 같게 맞췄습니다.

두 테스트가 실제 Apple 인코드 결과의 **키 집합**을 스키마의 `properties` 키 집합과 비교합니다.

- `apple/Tests/MellowSharedTests/RecipeSchemaTests.swift`: `targetFace`, spot 하나, warp 하나를 넣은 레시피를 인코드해 최상위 키, `color` 키, `portrait` 키, 그리고 각 `operations` 항목의 키를 `type.const`가 같은 `oneOf` 분기의 `properties` 키와 비교합니다. `$id`도 확인합니다.
- `apple/Tests/MellowLibraryTests/SessionSchemaTests.swift`: 사진 한 장(실행 취소·다시 실행 기록 포함)과 프리셋 하나가 든 세션을 `SessionFile.encode`로 인코드해 최상위 키, `photos` 항목 키, `presets` 항목 키, 프리셋 `values` 키를 비교합니다. `$id`도 확인합니다.

값의 범위(`minimum`·`maximum`·`maxItems`·`maxLength`), 타입, `required` 목록, `$ref`가 가리키는 하위 구조의 키는 기계로 검사하지 않습니다. 키를 추가하거나 고치면 위 키 집합이 어긋나 테스트가 스키마 갱신을 요구하지만, 범위나 필수 여부를 바꿀 때는 사람이 스키마를 직접 맞춰야 합니다.

## v2 형식 요점

- 좌표(`x`, `y`, `sourceX`, `sourceY`, `dx`, `dy`, `radius`)는 방향 보정된 이미지 기준 0~1 정규화 값이고, 원점은 왼쪽 아래입니다.
- `portrait.targetFace`는 왼쪽부터 센 얼굴 인덱스입니다. 값이 없으면 모든 얼굴에 적용합니다.
- `operations`는 사용자가 기록한 순서대로 재생합니다. 각 항목은 `"type": "spot"` 또는 `"type": "warp"`와 그 값을 같은 객체에 평평하게 담습니다.
- 사진별 `undo`는 최대 40개입니다(`EditingPolicy.historyLimit`). 프리셋 이름은 최대 30자입니다(`LibraryPolicy.presetNameLimit`).
- `filename`은 작업 사본의 파일 이름만 담습니다. 폴더는 플랫폼이 정합니다. Apple은 `Application Support/MellowPhoto/Library/<uuid>.<확장자>`에 둡니다.
- Apple 구현은 값이 없는 선택 키(`portrait.targetFace`, `selectedPhotoID`)를 `null`로 쓰지 않고 키 자체를 생략합니다. 읽는 쪽은 생략과 `null`을 같은 뜻으로 받아야 합니다.
- 읽을 때는 빠진 키를 기본값으로 채웁니다. 기본값은 스키마의 `default`와 같습니다.

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
| `recipe.adjustments.skin` | `recipe.portrait.skinSmoothing` |
| `recipe.adjustments.faceSlim` | `recipe.portrait.faceSlim` |
| `recipe.selectedFace` | `recipe.portrait.targetFace` |
| `{"spot":{"_0":{…}}}` | `{"type":"spot", …}` (warp도 같음) |
| `undoHistory`/`redoHistory`의 해당 사진 항목 | 각 사진의 `undo`/`redo` |
| `selectedID` | `selectedPhotoID` (목록에 없으면 첫 사진) |
| `presets[].adjustments` | `presets[].values.{color,portrait}` |

v1은 읽기만 합니다. 저장은 항상 v2로 합니다.

## 키를 추가할 때의 규칙 (B~F)

후속 작업은 `skin`, `reshape`, `detail`, `body`, `makeup` 같은 키를 레시피에 더합니다. 다음을 지킵니다.

1. **새 키는 반드시 기본값을 가집니다.** 키가 없는 기존 파일은 기본값으로 읽혀 지금과 같은 결과를 내야 합니다. 스키마에도 `default`를 적고 `required`에 넣지 않습니다.
2. **키를 지우거나 이름을 바꾸지 않습니다.** 더 쓰지 않는 값도 읽기는 계속합니다. 의미를 바꿔야 하면 새 키를 만듭니다.
3. **`schemaVersion`은 호환이 깨질 때만 올립니다.** 키 추가는 호환을 깨지 않으므로 v2를 유지합니다. 버전을 올리면 이전 버전 디코더(v1 포함)를 계속 유지하고, 새 스키마 파일(`*.v3.schema.json`)을 따로 둡니다.
4. 스키마는 `additionalProperties: false`이므로 키를 추가하는 커밋에서 스키마도 함께 고칩니다. `RecipeSchemaTests`·`SessionSchemaTests`가 키 집합의 어긋남을 잡습니다.
5. 모든 플랫폼이 같은 키 이름과 기본값을 씁니다. 다른 플랫폼은 `shared/fixtures/`의 파일로 읽기 호환을 테스트합니다.
