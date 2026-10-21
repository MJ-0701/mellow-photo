# 인물 보정 I (이중턱·부유방·사람별 체형) 설계

작성 2026-10-21. 선행: [인물 보정 B~F](2026-10-15-beauty-b-to-f-design.md)(C 얼굴형·E 체형), [인물 보정 H](2026-10-21-beauty-h-per-person-design.md)(사람별·성별 층). 기준 코드: `main` `8accbf6`(apple 1.4.0). 작업 브랜치 `beauty-body`.

사용자 요구는 다음과 같다.
- Evoto에서 본 이중턱 제거·부유방 제거·몸매 보정을 넣는다.
- 결과는 과하지 않고 자연스러워야 한다("성괴도 아니고").
- 체형 전체를 사람별·성별 층으로 옮긴다(2026-10-21 사용자 결정).
- 부유방은 여성 그룹이나 지정한 사람에게만 건다(같은 날 사용자 결정).

## 사람이 확인할 것

### Evoto와 지금 기능 비교

| Evoto | 전후 사진에서 보인 것 | 지금 Mellow | I에서 |
|---|---|---|---|
| 이중턱 제거 | 턱 아래 처진 선을 턱선 쪽으로 당긴다. 입과 턱 끝 모양은 그대로다 | 없음 (`jaw`는 V라인, `chinLength`는 턱 끝 길이) | 새 얼굴형 항목 |
| 몸매 보정 | 허리·팔·옆가슴·허벅지 윤곽선만 움직이고 배경은 그대로다 | 항목은 있다. 밀기 반경이 어깨 폭의 0.2~0.3배라 몸 옆 배경까지 휜다. 가장 큰 사람 한 명에게만 걸린다 | 배경·팔 보호, 사람별 |
| 부유방 | 겨드랑이 앞 옆가슴 윤곽을 안으로 정리한다 | 없음 | 새 체형 항목 |
| 배 납작하게 | 옆모습에서 배 윤곽을 들인다 | 없음 (옆모습은 체형이 꺼짐) | 범위 밖 |

### 결정

"사용자 결정"은 사용자가 확정한 것이고 나머지는 설계자 판단이다.

| 결정 | 이유 | 바꾸면 비용 |
|---|---|---|
| **체형 전체를 사람별·성별 층으로 옮긴다.** 체형 8개 항목이 피부·얼굴형처럼 전체 → 성별 그룹 → 개인 순서로 키 단위로 겹친다 (사용자 결정) | 커플 사진에서 남녀를 따로 보정해야 한다. 지금 구조에서는 가장 큰 사람에게만 걸려 부유방이 남자에게 걸릴 수 있다 | **큼** (파일 형식·편집 규칙·렌더·화면) |
| **부유방은 여성 그룹 층과 개인 층에서만 설정한다.** 전체 층과 남성 그룹 층에서는 편집이 거절하고, 파일·프리셋에 값이 있어도 렌더가 무시한다. 개인 층은 성별과 무관하게 허용한다 (사용자 결정) | "여성 그룹이나 지정한 사람에게만". 규칙을 한 곳(`PortraitScope.allows`)에 두어 편집·해석·화면이 같은 답을 낸다 | 작음 |
| **이중턱은 얼굴형 항목 `doubleChin`(0…1) 하나다.** 턱선 아래 띠를 위로 접어 올리는 국소 워프와 그 띠의 그늘 밝히기를 함께 건다. 턱선과 입은 움직이지 않는다. 남녀 모두에 쓸 수 있다 | Evoto 전후 사진이 주로 워프였다. 워프만으로는 접힌 그늘 선이 위로 옮겨 남아 그늘을 조금 밝힌다. 얼굴형이라 사람별·성별 층과 잠금 규칙을 그대로 받는다 | 작음 |
| **부유방은 체형 항목 `sideChest`(0…1, 줄이기만) 하나다.** 겨드랑이 아래 몸통 옆선(어깨~엉덩이의 27% 높이)을 안으로 좁은 반경으로 민다 | 옆가슴 군살은 몸통 옆선 위쪽의 작은 볼록이다. 넓은 반경은 가슴 모양과 팔까지 바꾼다. 키우는 방향은 요구가 없다 | 작음 |
| **모든 모양 워프에 배경 보호를 건다.** 사람 밖으로 나가는 이동은 실루엣 바깥 얇은 띠(최대 이동의 약 4배) 안에서 0이 된다. 넓히는 방향도 목표 이동을 다 내도록 실루엣 바로 바깥은 이동을 줄이지 않는다. 인물 마스크가 없으면 배경·팔·이웃 보호를 모두 끄고 지금과 같은 바이트를 낸다 | Evoto의 차이 지도는 윤곽선만 바뀌었다. 지금은 몸 옆 문틀·수평선이 휜다. 기존 허리·팔·얼굴형 결과도 함께 좋아지므로 기존 테스트 기대값 일부가 바뀐다 | 중간 |
| **몸통 항목(허리·몸 전체·부유방)은 팔을 피해 간다.** 어깨~팔꿈치~손목 선을 따라 팔 반폭 안을 보호하고 그 안에서는 몸통 이동을 0으로 줄인다. 팔이 몸에 붙어 있으면 붙은 부분의 몸통 옆선은 움직이지 않고, 팔이 몸통에서 팔 폭의 1/4쯤만 떨어져도 옆선은 움직인다. 어깨·목 항목은 어깨 관절 자체를 밀므로 보호하지 않는다 | 팔·옷 경계 끌림을 막는다. 팔 자체는 `arms` 항목만 움직인다 | 작음 |
| **사람마다 인물 마스크를 따로 쓴다** (Vision 사람 인스턴스 마스크, 최대 4명). 사람 A의 워프는 A의 마스크 밖에서 사라지고 다른 사람의 마스크 안에서는 0이라 옆 사람이 끌려가지 않는다. 맞닿은 곳의 빈틈은 옆 사람 가장자리가 조금 늘어나 메운다. 인스턴스 분석이 실패하거나 5명 이상이면 전체 인물 마스크로 배경만 보호한다 | 단체 사진에서 전체 층 체형이 모두에게 걸리면 옆 사람의 팔·어깨가 같이 움직인다 | 중간 (분석 단계 추가) |
| 얼굴과 몸은 **목 관절과 얼굴 상자 아래쪽의 거리로 1:1 짝짓는다**(렌더 안에서만, 저장 안 함). 짝이 된 몸은 그 얼굴의 사람·성별로 해석한 체형 값을 받는다. 얼굴이 없는 몸(뒷모습 등)은 전체 층 값만 받는다 | Vision 몸 관절에는 얼굴 점이 없다. 목은 얼굴 바로 아래라 거리로 충분하다 | 작음 |
| 전체 층 체형은 이제 **사진의 모든 사람**에게 걸린다. 옛 세션의 체형 값은 전체 층으로 읽고 가장 큰 사람에게 옮기는 이행은 하지 않는다 | 얼굴형의 전체 층과 같은 뜻이 된다. 옛 세션에서 단체 사진에 체형을 쓴 경우만 결과가 달라지고, 사람 보호가 있어 망가지지는 않는다 | 작음 |
| 다리 길게는 지금처럼 **가장 큰 사람 한 명**에게만 걸고 그 사람에게 해석한 값을 쓴다. 다른 사람을 대상으로 고르면 다리 슬라이더를 끄고 안내한다 | 다리 길게는 사진 가로 전체를 늘리는 띠라 사람마다 다르게 걸 수 없다 | 작음 |
| 수동 편집으로 이미 잠긴 옛 세션도 렌더가 조금 바뀌는 것을 받아들인다(배경 보호, 전체 층 체형이 모든 사람에게). 옛 경로는 남기지 않는다 | 수동 편집이 있고 체형·얼굴형도 쓴 사진은 TestFlight 사용자에게만 있고 드물다. 바뀌는 곳은 실루엣 바깥 띠와 단체 사진의 다른 사람이다. 옛 경로를 남기면 렌더 코드가 둘이 된다 | 작음 |
| 원터치(G4)에는 넣지 않는다 | 원터치는 원래 얼굴형·체형을 쓰지 않는다(잠긴 사진에서도 허용하기 위해). `OneTouchBundle`은 다른 세션(`beauty-g5`)이 고치는 중이다 | 작음 |
| 잠금·동기화·프리셋 규칙은 얼굴형과 같다. 수동 편집이 있는 사진은 모든 층의 체형 변경·재설정·사람 연결 변경을 거절한다. 체형 동기화는 전체·그룹 층을 나르고 받는 사진의 개인 체형 덮어쓰기를 지운다 | H의 얼굴형 규칙을 그대로 넓힌다. 사용자가 배울 규칙이 늘지 않는다 | 작음 |
| 실사진 수용 테스트는 **codex CLI로 새로 만든 가상 인물 사진 4장**으로 한다. 이중턱이 보이는 남성 정면, 몸에 붙는 옷의 여성 상반신, 남녀 커플 상반신, 문틀·타일처럼 직선이 많은 배경 앞 상반신이다. 직선 검사는 사람을 격자 배경에 합성한 사진으로도 한다 | 지금 테스트 사진 3장에는 이중턱·몸통 윤곽이 보이는 사진이 없다. H와 같은 방식이다 | 작음 |

### 자연스러움 기준 (수용 테스트가 묶는 값)

모든 값은 사진 폭을 폰 화면 1170px로 줄였을 때의 픽셀(폰 px)이다.

| 항목(값 1) | 보여야 함(하한) | 과하면 안 됨(상한) |
|---|---|---|
| 이중턱 | 턱밑 띠의 최대 위쪽 이동 ≥ 3 폰 px | 최대 이동 ≤ 얼굴 폭의 4.5%, 턱선·턱 끝 이동 ≤ 0.5 폰 px, 입술 이동 0, 그늘 밝기 증가 ≤ 휘도 12/255 |
| 부유방 | 옆가슴 윤곽 이동 ≥ 2 폰 px | 이동 ≤ 어깨 폭의 3.5%, 팔 영역 이동 ≤ 몸통 윤곽 이동의 15% |
| 기존 체형 ±1 | 윤곽 이동 ≥ 2 폰 px (보호 포함, 새로 정함) | 실루엣 바깥 띠 밖 배경 변화 비율 ≤ 0.2%, 격자 직선의 휨 ≤ 0.5px(미리보기 해상도) |
| 남녀 규칙 | 여성 그룹 부유방은 여성에게 보인다 | 같은 값이 남성 몸에서 0, 전체·남성 그룹 부유방은 사진을 1바이트도 바꾸지 않음 |

### 범위 밖

- 배 납작하게. 옆모습 체형 인식(한쪽 어깨만 보이는 몸)이 먼저 필요하다.
- 가슴 볼륨·힙·다리 슬림·키·머리 크기.
- 목주름 제거. 피부 단계(`SkinStage`)는 다른 세션이 고치는 중이다.
- 원터치 몸매.
- Android·Windows 구현. 레시피 스키마만 함께 고친다.

### 위험과 대응

- **배경 보호 띠가 좁으면 실루엣 바로 바깥이 늘어나 보일 수 있다.** 대응은 띠 너비를 이동의 3배 이상으로 두고 격자 합성 사진으로 휨을 재는 것이다.
- **Vision 목 관절이 흔들리면 얼굴–몸 짝이 틀릴 수 있다.** 대응은 거리 상한(얼굴 폭 1배)을 두고 짝이 없으면 전체 층 값만 주는 것이다. 다른 사람의 개인 값은 붙지 않는다.
- **사람 인스턴스 마스크는 4명까지이고 CI 가상 머신에서 동작하지 않을 수 있다.** 대응은 전체 마스크로 대체하는 것이다. 인스턴스가 필요한 수용 테스트는 결과가 없을 때 통과로 쓰지 않고 건너뜀으로 기록한다.
- **수염 아래 이중턱은 그늘 밝히기가 수염을 회색으로 만들 수 있다.** 대응은 볼 피부색과 먼 픽셀을 밝히지 않는 것이다(피부색 가중치).
- **기존 체형 결과가 바뀐다.** 배경 보호 때문이다. 기존 렌더 테스트 기대값을 고칠 때 그 이유를 커밋에 적는다. 수동 편집으로 잠긴 옛 세션도 조금 바뀐다(결정 표).
- **생성 사진은 실사진과 다르게 분석될 수 있다.** 실제 폰 사진 확인은 사용자 조치로 남긴다.

### 사용자 조치

- 실제 커플·상반신 사진으로 이중턱·부유방·허리를 켜 보고 과한지 판단한다(TestFlight 빌드).
- 다른 세션(`beauty-g5`)과 병합 순서를 정한다. 겹치는 파일은 `RenderTuning.swift`(서로 다른 절에 상수 추가), `docs/architecture/modules.md`, `VALIDATION.md`다.

### 돈·시간·외부 효과가 있는 단계

- 테스트 사진 4장 생성에 codex CLI 이미지 생성(OpenAI 사용량)이 든다.
- CI는 `gh workflow run apple-checks.yml --ref beauty-body`로 돌린다.
- main 병합, 버전 올림, TestFlight 업로드는 사용자에게 물은 뒤에만 한다.

## 에이전트 참조

### 1. 묶음과 순서

| 묶음 | 계획 | 들어가는 것 |
|---|---|---|
| I1 레시피·규칙 | `docs/superpowers/plans/2026-10-21-beauty-i1-recipe-rules.md` | 새 키 두 개, `PortraitLayer.body`, `PortraitKey.bodyShape`, `PortraitScope.allows`, 해석, 편집·잠금·동기화, 스키마 |
| I2 렌더 | `docs/superpowers/plans/2026-10-21-beauty-i2-render.md` | 인스턴스 마스크 분석, 얼굴–몸 짝짓기, 사람별 체형 대상, 보호 워프, 이중턱·부유방 원소, `chinShade` 단계 |
| I3 화면·검증 | `docs/superpowers/plans/2026-10-21-beauty-i3-app-validation.md` | 체형 패널 대상 칩, 슬라이더·문구, 생성 사진, 수용 테스트, 문서·VALIDATION |

I1 → I2 → I3 순서다. 다른 세션이 고치는 `OneTouchBundle.swift`, `SkinStage.swift`, `BodySkinStage.swift`, `RenderTuning`의 피부 상수, `RealPhotoAcceptanceTests.swift`는 건드리지 않는다. 새 수용 테스트는 `ShapeAcceptanceTests.swift`에 둔다.

### 2. 모듈 배치 (의존성 표 변경 없음)

| 새 타입·변경 | 모듈·폴더 |
|---|---|
| `FaceShapeKey.doubleChin`, `FaceShapeAdjustments.doubleChin`, `BodyShapeKey.sideChest`, `BodyShapeAdjustments.sideChest`, `AdjustmentRange` 두 항목 unit | MellowShared/API |
| `PortraitKey.bodyShape(BodyShapeKey)`, `PortraitKey.bodyShapes`, `PortraitKey.isShape`, `PortraitLayer.body`, `PortraitScope.allows(_:)`, `PortraitResolver.Resolved.body` | MellowShared/API |
| `EditRecipe.dependsOnBody`가 층의 체형도 봄 | MellowShared/API |
| `EditChange.bodyShape`의 `portraitKey`, `EditDocument.Rejection.scopeNotAllowed`, 잠금 검사의 `isShape`, `SyncCategory.body`의 층 규칙 | MellowEditing/API |
| `PersonInstanceAnalyzer` 포트, `VisionPersonInstanceAnalyzer`(Infrastructure, public), `PhotoAnalysis.personInstances`, `PreparedPhoto.bodyFaceMatches` | MellowRendering/API·Infrastructure |
| `BodyFaceMatcher`, `BodyTarget`, `RenderContext.bodyTargets`, `FaceTarget.body`, `ShapeGroup`, `ShapeGuard`, `ChinShadeStage`, `FaceRegions+Chin.swift` | MellowRendering/API·Domain |
| 체형 패널 대상 칩, 문구 | 앱 타깃 |

### 3. 레시피 (I1)

#### 3.1 키

- `FaceShapeKey`에 `doubleChin`을 **마지막에** 더한다. 범위는 `AdjustmentRange.unit`이다(`faceShape(_:)`가 `.smile`·`.doubleChin`에 unit).
- `BodyShapeKey`에 `sideChest`를 **마지막에** 더한다. 범위는 unit이다(`bodyShape(_:)`가 `.legLength`·`.sideChest`에 unit).
- 두 구조체의 디코드는 빠진 키를 0으로 읽는다. `schemaVersion`은 2로 둔다.

#### 3.2 층

- `PortraitKey.bodyShape(BodyShapeKey)`를 더한다. `PortraitKey.bodyShapes = Set(BodyShapeKey.allCases.map(PortraitKey.bodyShape))`이고 `PortraitKey.all`에 넣는다.
- `PortraitKey.isShape`는 `.faceShape`와 `.bodyShape`에서 true다. 잠금 검사는 `isFaceShape` 대신 `isShape`를 쓴다. `isFaceShape`는 남긴다.
- `PortraitLayer.body: [BodyShapeKey: Double]`를 더한다. JSON 키는 `body`이고 `face`와 같은 숫자 사전 형식이다. `overriddenKeys`·`hasEffect`·`numericValues`·`remove`에 넣는다. `difference`는 바꾸지 않는다(옛 `targetFace`에는 체형이 없었다).
- `PortraitLayer.applied(to:makeup:)`는 `applied(to:makeup:body:)`가 된다. 셋째 인자 `inout BodyShapeAdjustments`에 층의 체형 키를 덮어쓴다.

#### 3.3 허용 층

```swift
extension PortraitScope {
    /// 이 층에 그 키를 둘 수 있는지. 편집·해석·화면이 같은 답을 쓴다.
    public func allows(_ key: PortraitKey) -> Bool {
        guard key == .bodyShape(.sideChest) else { return true }
        switch self {
        case .all, .gender(.male): return false
        case .gender(.female), .person: return true
        }
    }
}
```

#### 3.4 해석

- `PortraitResolver.Resolved`에 `body: BodyShapeAdjustments`를 더한다.
- `resolve(_:person:gender:)`는 `recipe.body`에서 시작하고 허용되지 않는 키(전체 층의 `sideChest`)를 0으로 둔다.
- 그룹 층은 `PortraitScope.gender(gender).allows(_:)`가 false인 체형 키를 건너뛴다(남성 그룹의 `sideChest`).
- 개인 층은 모두 덮어쓴다.
- 짝 없는 몸용으로 `PortraitResolver.allLayerBody(_ recipe:) -> BodyShapeAdjustments`를 둔다(전체 층 값에서 허용되지 않는 키를 0으로).

#### 3.5 의존 플래그

`EditRecipe.dependsOnBody`는 `allLayerBody(self).hasEffect || people.groups.values.contains { $0.body.values.contains { $0 != 0 } } || people.individuals.contains { $0.layer.body.values.contains { $0 != 0 } }`다. 계산은 이 식 그대로 한 줄 한 묶음으로 나눈다(Xcode 26.3 타입 검사).

#### 3.6 스키마

`shared/recipe-schema/edit-recipe.v2.schema.json`의 얼굴형·체형 객체에 `doubleChin`·`sideChest`를, 층 객체에 `body`를 더한다. README에 허용 층 규칙과 "전체 층 체형은 모든 사람"을 적는다. 스키마 키 대조 테스트를 고친다.

### 4. 편집 (I1)

- `EditChange.bodyShape(key, value).portraitKey`는 `.bodyShape(key)`다. 그래서 `set(_:in:)`·`set(_:forFace:of:)`가 층으로 보낸다.
- `set(_:in:)`은 `scope.allows(portraitKey)`가 false면 바꾸지 않고 `Rejection.scopeNotAllowed`를 돌려준다. `set(_:forFace:of:)`는 개인 층이라 늘 허용이다.
- 전체 층 체형 쓰기는 지금처럼 `recipe.body[key]`이고 범위는 `EditingPolicy.bodyShapeRange`다. 층 쓰기도 같은 클램프다.
- 잠금: `carriesFaceShape`를 `carriesShape`(`isShape`)로 넓힌다. 재설정·연결·삭제·`resetOverrides`의 잠금 판정이 체형 키도 본다.
- `SyncCategory.body`는 얼굴 의존 항목이 된다(`dependsOnFaces` true, `portraitKeys`는 `PortraitKey.bodyShapes`). 동기화는 전체 층 `body`와 그룹 층 체형 키를 복사하고 받는 사진의 개인 층 체형 키를 지운다. 잠긴 사진은 지금처럼 건너뛴다.
- 프리셋은 `PresetValues.people.groups`로 그룹 층 체형을 나른다. 프리셋의 전체 층 `sideChest`가 0이 아니어도 렌더가 무시한다.
- 원터치는 체형 키를 쓰지도 지우지도 않는다. 원터치 테스트의 "얼굴형·체형 불변" 검사는 그대로 통과해야 한다.

### 5. 렌더 (I2)

#### 5.1 분석

- 새 포트 `PersonInstanceAnalyzer`(`instanceMasks(CIImage) throws -> [CIImage]`)를 둔다. 결과는 사람마다 0…1 회색 마스크이고 extent는 입력 이미지 extent다.
- 기본 구현 `VisionPersonInstanceAnalyzer`는 `VNGeneratePersonInstanceMaskRequest`를 쓴다. 인스턴스마다 `generateScaledMaskForImage(forInstances:from:)`가 아니라 저해상도 마스크(`generateMask(forInstances:)`)를 받아 입력 extent로 늘린다.
- `PhotoPipeline.init`에 `instanceAnalyzer: (any PersonInstanceAnalyzer)? = nil`을 더한다. 앱은 Vision 구현을 넘긴다.
- 실패는 조용히 빈 배열이다. `PhotoAnalysis.personInstances: [CIImage]`에 두고 영속화하지 않는다.
- 인스턴스 분석은 레시피가 체형이나 얼굴형을 쓸 때만이 아니라 사진 준비 때 늘 돈다(인물 마스크와 같은 정책).

#### 5.2 얼굴–몸 짝짓기

- `BodyFaceMatcher.match(bodies:faces:extent:tuning:) -> [Int: Int]`(몸 인덱스 → 얼굴 인덱스)를 Domain에 둔다.
- 몸의 기준점은 목 관절이고 없으면 두 어깨 중점이다. 신뢰도는 `bodyJointMinConfidence`를 쓴다.
- 얼굴의 기대점은 얼굴 상자 아래 가운데에서 얼굴 상자 높이 × `bodyFaceNeckDrop`(0.25)만큼 아래다.
- 거리를 얼굴 폭으로 나눈 값이 `bodyFaceMatchTolerance`(1.0) 이하인 쌍만 후보다.
- 거리 오름차순 탐욕 1:1이고 같은 거리는 (몸 인덱스, 얼굴 인덱스) 순이다. 결정적이어야 한다.
- `PreparedPhoto.bodyFaceMatches: [Int: Int]`로 앱에도 준다.

#### 5.3 대상

- `FaceTarget.body: BodyShapeAdjustments`를 더한다. 값은 `PortraitResolver.resolve`의 `body`다.
- `BodyTarget`(몸 인덱스, `BodyGeometry`, 짝 얼굴 인덱스?, 해석한 `BodyShapeAdjustments`, 사람 마스크 `CIImage?`)을 `RenderContext.bodyTargets`로 만든다. 모든 몸이 대상이다.
- 짝 얼굴이 있으면 그 `FaceTarget.body`를 쓰고 없으면 `PortraitResolver.allLayerBody(recipe)`를 쓴다.
- 사람 마스크는 그 몸의 목·두 어깨·두 엉덩이 중 있는 점에서 인스턴스 마스크를 표본해 평균이 `instanceMatchMinimum`(0.5) 이상인 것 중 가장 큰 것이다. 없으면 전체 인물 마스크, 그것도 없으면 nil이다.
- 얼굴 대상의 사람 마스크는 얼굴 상자 중심에서 같은 방법으로 고른다.

#### 5.4 보호 워프

- `ShapeGroup`은 원소 배열, 사람 마스크 `CIImage?`, 팔 보호 `[ShapeGuard]`를 가진다. `ShapeGuard.capsule(start:end:radius:feather:)`다.
- `DisplacementWarp.apply(groups:to:extent:limit:)`가 그룹마다 이동량 지도를 그리고 가중치를 곱해 더한 뒤 한 번만 샘플링한다. 기존 `apply(_:to:extent:limit:region:)`는 보호 없는 그룹 하나로 남긴다.
- 배경 가중치 w(p) = clamp(`shapeBackgroundGain`(4) × G(m)(p), 0, 1) × (1 − o(p))다.
- m은 그 그룹의 사람 마스크이고 G는 표준편차 σ의 가우스 흐림이다. 흐림은 마스크 원래 해상도에서 한 뒤 늘린다.
- σ = max(그룹 최대 이동 × `shapeBackgroundSigmaRatio`(1.5), 짧은 변 × `shapeBackgroundSigmaMinimum`(0.002))다. 이득 4는 Φ(−1/1.5) ≈ 0.25의 역수라 실루엣에서 최대 이동만큼 바깥까지 w = 1이다. 그래서 넓히기도 목표 이동을 다 낸다.
- o(p)는 다른 사람 인스턴스 마스크의 최댓값이다(전체 마스크로 대체한 경우 0).
- 팔 보호 가중치는 1 − Π(1 − c_i(p))이고 c_i는 캡슐 반지름 안 1, 반지름 + feather 밖 0인 smoothstep이다. 몸통 그룹의 지도에 (1 − 팔 보호)를 곱한다.
- 그룹의 사람 마스크가 nil이면 배경·이웃·팔 보호를 모두 끈다(가중치 1, 기존 결과와 같은 바이트).
- 이동 상한 `shapeDisplacementLimit`과 띠(다리 길게) 처리는 지금과 같다. 다리 띠는 가장 큰 몸 하나만 만든다(`maximumBands` 1 유지). 다리 띠는 보호를 받지 않는다.

#### 5.5 그룹 구성 (`ShapeWarpStage`)

- 얼굴 대상마다 얼굴형 원소 그룹 하나(그 얼굴의 사람 마스크, 보호 없음).
- 몸 대상마다 몸통 그룹(허리·몸 전체·부유방, 그 몸의 팔 캡슐 보호), 팔다리 그룹(팔·허벅지·어깨·목, 팔 보호 없음, 배경·이웃 보호는 받음), 다리 띠(가장 큰 몸 하나, 그 몸의 해석값 `legLength`).
- 팔 캡슐은 어깨–팔꿈치(반지름 = 어깨 폭 × `upperArmHalfWidth` × `armGuardScale`(1.0))와 팔꿈치–손목(`forearmHalfWidth` × 1.0)이고 feather는 어깨 폭 × `armGuardFeather`(0.03)다. 관절이 없는 선분은 빠진다.

#### 5.6 이중턱 원소 (`FaceShapeRig`)

- 아래턱 윤곽점(얼굴 좌표 y < 입 높이) 중 좌우 입꼬리 x 사이에 있는 점을 고른다. 점이 3개 미만이면 원소가 없다.
- 고른 점마다 얼굴 좌표 아래로 얼굴 폭 × `doubleChinOffset`(0.10) 내려간 곳을 중심으로, 반지름 얼굴 폭 × `doubleChinRadius`(0.10)의 위쪽 push를 둔다. 턱선 위 이동은 감쇠 끝(0)이라 턱선이 움직이지 않는다.
- 그 아래 얼굴 폭 × 0.22 높이에 반지름 0.16의 위쪽 push를 이동 절반으로 하나 더 둔다. 목이 한 곳에서 늘어나지 않게 늘림을 나눈다.
- 점마다의 이동은 겹침을 나눠 턱 끝 아래 최대 이동이 shift = 값 × `faceShapeMaxShift(.doubleChin)`(0.035) × 얼굴 폭 × yaw 약화가 되게 한다. CPU 참조로 ±10%를 테스트한다.

#### 5.7 턱밑 그늘 (`ChinShadeStage`, 이름 `chinShade`)

- 단계 순서는 `skin` → `bodySkin` → `feature` → `makeup` → `background` → `chinShade` → `shapeWarp` → 이후 같다.
- `doubleChin`이 0보다 큰 얼굴 대상만 처리하고 없으면 입력을 그대로 돌려준다.
- 마스크는 아래턱 윤곽에서 얼굴 폭 × 0.03 아래부터 0.20 아래까지의 띠다. 가로는 입꼬리 x 바깥 얼굴 폭 × 0.08까지이고 가장자리는 얼굴 폭 × 0.03으로 부드럽게 한다.
- 마스크에 볼 기준 피부색 가중치(`FaceRegions`의 기존 Cb·Cr 거리)를 곱한다. 마스크 코드는 `FaceRegions+Chin.swift`에 둔다.
- 밝히기는 L' = L + 값 × `chinShadeMaxGain`(0.5) × max(0, R − L)이다. R은 마스크 가중 넓은 평균 휘도(반지름 얼굴 폭 × 0.15)다. 어둡게 하지 않는다.
- 결과 휘도 증가는 `chinShadeMaxLift`(12/255)에서 자른다.

#### 5.8 부유방 원소 (`BodyShapeRig`)

- 같은 쪽 어깨와 엉덩이가 있는 쪽마다 `torsoSides(level: sideChestLevel 0.27)` 점을 몸통 가로축 안쪽으로 민다.
- 반지름은 어깨 폭 × `sideChestRadius`(0.14)와 |이동| / limit 중 큰 값이다.
- 이동은 값 × min(`bodySideChestMaxShift`(0.03), `bodyShapeMaxShift`) × 어깨 폭이다.
- 두 엉덩이가 없으면 원소가 없다.

#### 5.9 새 `RenderTuning` 상수

`shapeBackgroundGain` 4, `shapeBackgroundSigmaRatio` 1.5, `shapeBackgroundSigmaMinimum` 0.002, `armGuardScale` 1.0, `armGuardFeather` 0.03, `bodyFaceNeckDrop` 0.25, `bodyFaceMatchTolerance` 1.0, `instanceMatchMinimum` 0.5, `faceDoubleChinMaxShift` 0.035, `bodySideChestMaxShift` 0.03, `chinShadeMaxGain` 0.5, `chinShadeMaxLift` 12/255. 기존 체형 상수 바로 아래 절에 둔다. 피부 상수 절은 건드리지 않는다. 원소 배치 비율(오프셋·반지름·높이)은 각 rig의 `private static let`이다.

### 6. 화면 (I3)

- `BodyPanel` 맨 위에 `TargetChips`를 둔다. 값은 `model.scopedValues.body`이고 변경은 대상 층으로 간다.
- `sideChest` 슬라이더는 `scope.allows(.bodyShape(.sideChest))`가 true일 때만 보인다. 전체·남성 대상에서는 "부유방은 여성 그룹이나 사람을 골라 조정해요" 안내를 보인다.
- 다리 길게는 대상이 전체·성별 그룹이거나 가장 큰 몸과 짝인 사람일 때만 켜고, 그 밖의 사람 대상에서는 끄고 "다리 길게는 사진에서 가장 큰 사람에게만 걸려요"를 보인다(0이 아닌 값은 되돌릴 수 있게 켬).
- 사람 대상인데 그 얼굴과 짝인 몸이 없으면 "이 사람의 몸을 찾지 못했어요"를 보이고 슬라이더를 끈다. 0이 아닌 값은 되돌릴 수 있게 켠다(지금 `canAdjustBodyShape` 규칙).
- 덮어쓴 체형 슬라이더에 기존 덮어쓰기 표시와 재설정을 붙인다.
- 문구는 `UserMessage`에 둔다. 제목은 "이중턱"·"부유방"이다. 체형 패널 설명 문구 "가장 큰 사람"을 "선택한 대상"으로 고친다.
- 얼굴형 패널은 `FaceShapeKey.allCases`로 그리므로 이중턱 슬라이더가 자동으로 생긴다. 제목만 더한다.

### 7. 검증 (I3)

#### 7.1 생성 사진

`shared/fixtures/body/`에 긴 변 1024px JPEG 4장과 `labels.json`, README(출처·사용 조건)를 둔다. 테스트 타깃 `apple/Tests/MellowRenderingTests/Fixtures/body/`에는 4장을 모두 복사한다(합계 2 MB 이내).

| 파일 | 내용 |
|---|---|
| `chin-01.jpg` | 30~40대 남성 정면, 이중턱이 보임, 단색 배경, 셔츠 깃 |
| `torso-01.jpg` | 20~30대 여성 상반신 정면, 몸에 붙는 민소매 상의, 팔이 몸통에서 조금 떨어짐, 단색 배경 |
| `couple-body-01.jpg` | 남녀 상반신 정면 나란히, 두 사람 어깨가 맞닿거나 거의 닿음, 몸통이 보임, 실내 배경 |
| `lines-01.jpg` | 여성 상반신, 뒤에 문틀·타일·창틀 직선, 팔이 몸통에서 떨어짐 |

#### 7.2 수용 테스트 (`ShapeAcceptanceTests.swift`, 실제 Vision)

- 이중턱·부유방·기존 체형의 하한·상한은 1절 "자연스러움 기준" 표 값이다. 이동량은 그 사진의 실제 분석으로 만든 GPU 이동량 지도(보호 가중치 포함, 렌더와 같은 지도)를 읽어 잰다. 지도 읽기는 `DisplacementWarp`의 테스트용 internal 함수로 연다. 그늘 밝기·배경 변화·남녀 규칙은 렌더 픽셀로 잰다.
- 격자 합성: `torso-01.jpg`의 전체 인물 마스크로 사람을 8px 간격 검은 격자 배경 위에 얹은 이미지를 만든다. 분석은 원본 사진으로 하고 렌더는 합성 이미지에 같은 분석을 넘긴다. 체형 전 항목 ±1과 이중턱 1에서, 실루엣에서 띠 너비 + 4px 밖의 격자선 위치가 0.5px 넘게 움직이면 실패다.
- 팔 끌림: `torso-01.jpg`에서 허리 −1·부유방 1의 전체 지도가 팔 영역(팔 캡슐 반지름 안 × 그 사람 마스크)에서 몸통 윤곽 최대 이동의 15% 이하다. 같은 값에서 부유방·허리 윤곽 하한도 함께 확인해 보호가 효과를 지우지 않았는지 본다.
- 남녀: `couple-body-01.jpg`에서 여성 그룹 부유방 1은 여성 몸 윤곽을 바꾸고 남성 몸 영역(남성 인스턴스 마스크)은 바꾸지 않는다. 전체 층·남성 그룹 부유방 1은 렌더가 원본과 같은 바이트다. 남성 개인 층 부유방 1은 남성 몸을 바꾼다. 인스턴스 마스크가 없으면 남성 영역 검사는 `XCTSkip`으로 건너뛰고 나머지는 한다.
- 이웃 보호: `couple-body-01.jpg`에서 여성 개인 층 허리 −1이 남성 인스턴스 마스크 안을 바꾸는 비율 ≤ 0.2%다. 인스턴스 마스크가 없으면 `XCTSkip`.
- 잠금: 편집 테스트에서 수동 편집이 있는 사진의 모든 층 체형 변경이 `.geometryLocked`이고, `scopeNotAllowed` 판정이 잠금보다 먼저다.

#### 7.3 기록

`VALIDATION.md`에 자동 테스트 결과(로컬 `./scripts/test-apple.sh`, CI 실행 번호), 건너뛴 테스트와 이유, 사용자 기기 확인 항목을 적는다. 수행하지 않은 검증은 통과로 쓰지 않는다.

### 8. 문서

- `docs/architecture/modules.md`: Shared·Editing·Rendering 캔버스 규칙과 공개 API, 단계 순서, 새 포트.
- `shared/recipe-schema/README.md`와 스키마 JSON.
- 앱 변경사항 문서(1.4.0 변경사항을 적은 곳)에 다음 버전 항목.
