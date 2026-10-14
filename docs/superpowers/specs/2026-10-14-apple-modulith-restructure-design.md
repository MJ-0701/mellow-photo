# Mellow Photo 구조 리팩토링 (하위 프로젝트 A) 설계

작성일 2026-10-14. 기준 커밋 `1cbab20`. 설계 모델 Claude Fable 5.1, 구현은 Claude Opus 5.5로 진행한다.

## 1. 배경과 목표

Mellow Photo는 Evoto를 참고해 만든 로컬 인물 사진 보정 앱이다. 현재 Mac 앱(`Sources/MellowApp`, AppKit+SwiftUI, SwiftPM 실행 파일)과 iPhone 앱(`iOS/`, SwiftUI, Xcode 프로젝트)이 `MellowCore` 하나를 공유한다. iPhone 앱은 App Store 심사에 접수된 상태다.

문제는 세 가지다.

1. 편집 세션 로직(실행 취소, 얼굴 형태 잠금, 프리셋 보존, 전체 적용)이 `StudioStore`와 `MobileStore`에 따로 구현되어 있고 내장 프리셋 값마저 서로 다르다.
2. `ImageEngine.render()`가 마스크 생성·워프·복제·색감을 70줄 한 함수에 담고 있어 새 효과를 넣을 자리가 없다. Vision이 주는 76개 얼굴 랜드마크를 버리고 사각형 4개만 쓴다.
3. 한 줄에 여러 문장을 욱여넣은 압축 스타일과 매직 넘버 때문에 읽고 고치기 어렵다. iOS는 슬라이더를 움직일 때마다 디스크에서 사진을 다시 읽는다.

이번 하위 프로젝트 A의 목표는 **구조**다. 보정 효과는 바꾸지 않는다. 결과물은 다음과 같다.

- 모노레포 배치: `apple/`, `android/`, `windows/`, `shared/`. 플랫폼별 태그(`apple-v1.0.0`)로 배포.
- Apple 코드는 능력 단위 Swift 모듈 5개 + iPhone·iPad·Mac을 한 번에 빌드하는 SwiftUI 앱 타깃 하나.
- 편집 규칙은 한 곳에만 존재하고 GPU 없이 테스트된다.
- 렌더 엔진은 단계(stage) 파이프라인으로 분해되어 B~F가 단계만 추가하면 된다.
- 출시된 iPhone 앱의 `session.json`(v1)을 읽어 그대로 이어서 편집할 수 있다.

### 결정 기록

| 질문 | 결정 |
|---|---|
| 품질 우선순위 | 구조 먼저(A), 효과 다음(B~F). Evoto 수준 효과는 반드시 포함. |
| 플랫폼 전략 | 크로스플랫폼 프레임워크 없음. Apple=Swift, Android=Kotlin, Windows=C/C++. 모노레포, 플랫폼별 버전·태그. |
| Apple 앱 구성 | SwiftUI 멀티플랫폼 앱 하나(iPhone·iPad·Mac). AppKit Mac 앱 폐기. |
| 아키텍처 | Spring Modulith 원칙(능력 단위 모듈, 공개 API/내부 구분, 선언된 의존성, CI 검증, 모듈 캔버스). Clean의 의존성 방향 규칙·플랫폼 경계 포트·영속 포맷 분리. 3-tier는 모듈 내부 폴더 규칙. |
| 채택하지 않은 형식 | 전역 이벤트 버스, 기능마다 유스케이스 클래스, Entity/Model/DTO 삼중 타입, 전방위 Repository, 화면마다 ViewModel. |
| 후속 순서 | B 피부 → C 얼굴 리셰이프 → D 디테일·배경 → E 체형 → F 메이크업. |

## 2. 모노레포 배치

```
mellow-photo/
  apple/
    Package.swift                 MellowKit: MellowShared · MellowEditing · MellowLibrary · MellowRendering · MellowExport
    Sources/<모듈>/{API,Domain,Infrastructure}/
    Tests/<모듈>Tests/
    project.yml                   XcodeGen 정의 (진실의 원천)
    MellowPhoto.xcodeproj         생성 결과. 커밋하며 CI가 재생성 결과와 비교
    MellowPhoto/
      App/                        MellowPhotoApp, 씬, 명령(단축키)
      Application/                AppModel, ImportPhotos, ExportPhotos, RenderScheduler
      Features/Library, Editor, Export, Presets, Info   SwiftUI 뷰
      Platform/                   PhotoImporter·ExportDestination 구현, 기기 정책
      Resources/                  Assets.xcassets, Localizable.xcstrings, Info.plist, PrivacyInfo.xcprivacy, 엔타이틀먼트
    MellowPhotoTests/             AppModel·유스케이스 테스트 (가짜 어댑터)
    Config/Version.xcconfig       MARKETING_VERSION 단일 출처
  android/README.md               자리 표시자. 모듈 지도와 shared/ 계약을 따른다고 명시
  windows/README.md               동일
  shared/
    recipe-schema/edit-recipe.v2.schema.json
    recipe-schema/session-file.v2.schema.json
    fixtures/session-v1.json      기준 커밋 코드로 생성한 실제 v1 세션
    fixtures/demo-portrait.png    현재 docs/store-assets/demo-portrait.png 이동
  docs/
    architecture/modules.md       모듈 캔버스 (모듈당 이름·책임·공개 API·의존·포트)
    superpowers/specs, plans
    (기존 문서는 새 경로에 맞게 갱신)
  scripts/                        test-apple.sh, build-apple.sh, package-mac.sh, verify-modules.sh, release.sh
  fastlane/  .github/workflows/  website/
```

폐기: `Package.swift`(루트), `Sources/`, `Tests/`, `iOS/`, `scripts/build-app.sh`, `scripts/make-icon.swift`, `scripts/make-ios-icon.swift`(아이콘은 생성된 PNG를 Assets에 커밋하고 스크립트는 `scripts/tools/`로 이동). `dist/`와 `.build/`는 gitignore 유지.

## 3. 모듈 지도와 의존성 규칙

```
MellowShared ◄── MellowEditing ◄── MellowLibrary
     ▲                                   
     ├──────── MellowRendering ◄── MellowExport
     └──────── (앱 타깃은 다섯 모듈 모두 import)
```

허용 의존성은 다음 표가 전부다. 역방향, 수평(예: Rendering→Library), 앱 타깃을 향한 의존은 금지한다.

| 모듈 | import 허용 | 금지 프레임워크 |
|---|---|---|
| MellowShared | Foundation, CoreGraphics | 그 외 전부 |
| MellowEditing | MellowShared | CoreImage, Vision, SwiftUI, UIKit, AppKit, Photos |
| MellowLibrary | MellowShared, MellowEditing | CoreImage, Vision, SwiftUI, UIKit, AppKit, Photos |
| MellowRendering | MellowShared, CoreImage, Vision, ImageIO, UniformTypeIdentifiers | SwiftUI, UIKit, AppKit, Photos |
| MellowExport | MellowShared, MellowRendering, ImageIO, UniformTypeIdentifiers | SwiftUI, UIKit, AppKit, Photos |
| 앱 타깃 | 전부 | 없음 |

`scripts/verify-modules.sh`가 `swift package describe --type json`의 의존 그래프를 위 표와 비교하고, 각 모듈 소스의 `import` 문을 grep해 금지 프레임워크가 없는지 확인한다. CI 필수 단계다.

모듈 내부는 폴더 세 개로 나눈다. `API/`에는 `public` 타입만, `Domain/`과 `Infrastructure/`는 `internal`이다. 다른 모듈은 `API/`의 타입만 볼 수 있다.

### 모듈 캔버스

**MellowShared (공유 커널)**
- 책임: 플랫폼 간 계약이 되는 값 타입과 오류.
- 공개 API: `EditRecipe`, `ColorAdjustments`, `PortraitAdjustments`, `LocalEdit`(`RetouchSpot`, `WarpStroke`), `NormalizedPoint`, `NormalizedRect`, `FaceGeometry`, `FaceLandmark`, `Preset`, `PresetValues`, `BuiltInPresets`, `MellowError`, `PhotoID`.
- 의존: 없음.

**MellowEditing (편집)**
- 책임: 사진 한 장의 편집 상태와 그 규칙.
- 공개 API: `EditDocument`(값 타입), `EditingPolicy`(상수: 히스토리 상한 40).
- 규칙(모두 `EditDocument` 안에만 존재):
  - 변경 전 체크포인트. 같은 레시피가 연속이면 중복 저장 안 함. 슬라이더 드래그는 시작 시 한 번만 체크포인트(`beginContinuousChange`/`endContinuousChange`).
  - 수동 편집(`operations`)이 하나라도 있으면 얼굴 형태(`faceSlim`)와 대상 얼굴(`targetFace`)은 잠긴다. 잠긴 동안 변경 요청은 무시하고 `EditDocument.Rejection`을 돌려준다.
  - 프리셋 적용과 전체 적용은 잠긴 사진의 `faceSlim`을 보존한다. 잠기지 않은 사진에 전체 적용하면 `targetFace`를 `nil`로 되돌린다.
  - 초기화는 체크포인트 후 레시피를 기본값으로.
- 의존: Shared.

**MellowLibrary (사진 관리)**
- 책임: 사진 목록, 선택, 작업 사본, 세션 영속화와 복구, 프리셋 보관, 사진 수 정책.
- 공개 API: `ProjectSession`(`@Observable`, MainActor), `PhotoEntry`, `SessionStore`(포트), `JSONSessionStore`, `LibraryPolicy`(사진 수 상한), `WorkingCopyStore`.
- 포트 `SessionStore`: `load() throws -> SessionFile?`, `save(SessionFile) throws`. 구현 `JSONSessionStore`는 원자적 쓰기, 읽을 수 없는 파일은 `session-recovery-<uuid>.json`으로 보존한 뒤에만 덮어쓰기, 쓰기 실패 시 호출자에게 오류 전달(사진 제거는 저장 성공 후에만 상태 반영).
- `SessionFile`은 Infrastructure의 Codable DTO다. v1(`MobileSession` 포맷)과 v2를 모두 디코드하고 v2로만 인코드한다. `ProjectSession`은 DTO를 모른다. 변환은 `SessionFileMapper`.
- 사진 수 정책: 물리 메모리 4GB 미만 12장, 8GB 미만 24장, 그 외 40장. 테스트에서 주입 가능.
- 의존: Shared, Editing.

**MellowRendering (분석·렌더)**
- 책임: 사진 읽기, 얼굴 분석, 레시피 렌더, 미리보기 캐시.
- 공개 API: `PhotoPipeline`(actor), `PreparedPhoto`, `RenderPipeline`, `RenderStage`(프로토콜), `RenderContext`, `FaceAnalyzer`(포트), `VisionFaceAnalyzer`, `ImageLoader`, `RenderTuning`.
- 파이프라인 순서(A에서 고정): `SkinStage` → `FaceReshapeStage` → `LocalEditStage` → `ColorStage`. 현재 `render()`와 동일한 출력을 내야 하며 기존 GPU 회귀 테스트 8개가 그 증거다.
- `PhotoPipeline`은 사진별 미리보기 `CIImage`를 LRU 3장까지 캐시하고, 모든 사진의 썸네일과 얼굴 기하를 보관한다. 미리보기 렌더는 디스크를 읽지 않는다. 원본 해상도 렌더는 호출 시 읽는다. 내보내기 시 얼굴을 다시 분석하지 않고 준비 때 얻은 정규화 좌표를 재사용한다.
- `WarpKernel`은 `CIWarpKernel` 문자열 소스를 감싸는 유일한 타입이다. 나중에 Metal로 교체할 때 이 타입만 바꾼다.
- 미리보기 긴 변: 메모리 8GB 이상 1600px, 미만 1200px.
- 의존: Shared.

**MellowExport (내보내기)**
- 책임: 렌더 결과를 파일로 안전하게 쓰기, 이름 충돌 정책, 저장 대상 추상화.
- 공개 API: `Exporter`, `ExportFormat`, `ExportOptions`(형식, 원본 해상도 여부, 품질), `ExportDestination`(포트), `FileNamingPolicy`.
- `Exporter`는 임시 파일에 쓰고 재해독으로 검증한 뒤 `renameatx_np(RENAME_EXCL)`로 공개한다(현재 동작 유지). 출력은 8bit sRGB, EXIF 방향 1, GPS 없음.
- 포트 `ExportDestination`: `publish(fileURL: URL, suggestedName: String) async throws`. 구현은 앱 타깃의 Platform에 있다.
- 의존: Shared, Rendering.

## 4. 데이터 모델

### EditRecipe v2

```json
{
  "schemaVersion": 2,
  "color":    { "exposure": 0.0, "contrast": 1.0, "saturation": 1.0, "warmth": 0.0 },
  "portrait": { "skinSmoothing": 0.0, "faceSlim": 0.0, "targetFace": null },
  "operations": [
    { "type": "spot", "x": 0.5, "y": 0.4, "sourceX": 0.45, "sourceY": 0.4, "radius": 0.02 },
    { "type": "warp", "x": 0.5, "y": 0.4, "dx": 0.01, "dy": 0.0, "radius": 0.08 }
  ]
}
```

- 좌표는 방향 보정된 이미지 기준 정규화 좌표, 원점은 왼쪽 아래(현재와 동일).
- `targetFace`는 왼쪽부터 센 얼굴 인덱스, `null`이면 모든 얼굴.
- v1(`adjustments{exposure,contrast,saturation,warmth,skin,faceSlim}`, `operations[{spot:{_0:{…}}}|{warp:{_0:{…}}}]`, `selectedFace`)은 `SessionFile` 디코더가 읽어 v2로 올린다. `EditRecipe` 자체는 v2만 안다.
- B~F는 `skin`, `reshape`, `detail`, `body`, `makeup` 키를 추가한다. 없는 키는 기본값으로 디코드되어야 하므로 모든 하위 구조는 기본값을 가진다.
- `shared/recipe-schema/edit-recipe.v2.schema.json`이 이 형식을 JSON Schema로 기술한다. 테스트가 샘플 레시피를 인코드해 스키마와 대조한다.

### SessionFile v2

```json
{
  "schemaVersion": 2,
  "photos": [
    { "id": "UUID", "filename": "UUID.heic", "displayName": "사진 1",
      "recipe": { …v2… }, "undo": [ {…} ], "redo": [ {…} ] }
  ],
  "selectedPhotoID": "UUID",
  "presets": [ { "id": "UUID", "name": "포근한", "values": { "color": {…}, "portrait": {…} } } ]
}
```

v1 → v2 변환 규칙: `name`→`displayName`, `undoHistory[id]`/`redoHistory[id]`→각 사진의 `undo`/`redo`, `presets[].adjustments`→`values`(skin→portrait.skinSmoothing). 선택 ID가 목록에 없으면 첫 사진. 변환은 `shared/fixtures/session-v1.json`으로 테스트하며, 이 픽스처는 기준 커밋의 코드로 실제 인코드해 만든다(손으로 쓰지 않는다).

### FaceGeometry

```swift
public struct FaceGeometry: Sendable, Equatable {
    public var boundingBox: NormalizedRect
    public var landmarks: [FaceLandmark: [NormalizedPoint]]   // 이미지 좌표계, 얼굴 상대 좌표 아님
    public var roll: Double?
    public var yaw: Double?
}
public enum FaceLandmark: String, CaseIterable, Sendable {
    case faceContour, leftEye, rightEye, leftEyebrow, rightEyebrow,
         nose, noseCrest, medianLine, outerLips, innerLips, leftPupil, rightPupil
}
```

영속화하지 않는다. 사진을 준비할 때마다 다시 계산한다. 얼굴 순서는 `boundingBox.minX` 오름차순(현재와 동일)이라 `targetFace` 인덱스 의미가 유지된다. A에서 `SkinStage`는 눈·입 보호에 `leftEye`·`rightEye`·`outerLips`의 경계 사각형을 써서 현재 결과를 재현하고, C 이후가 전체 점을 쓴다.

### 내장 프리셋

`BuiltInPresets`에 한 번만 정의한다. iPhone 출시본 값을 기준으로 한다.

| 이름 | exposure | contrast | saturation | warmth | skinSmoothing |
|---|---|---|---|---|---|
| 내추럴 | 0.10 | 1.00 | 1.00 | 0.00 | 0.20 |
| 포근한 | 0.15 | 1.00 | 0.92 | 0.25 | 0.30 |
| 클린 | 0.20 | 1.05 | 1.00 | -0.10 | 0.00 |

## 5. 렌더 파이프라인

```swift
public struct RenderContext: Sendable {
    public let extent: CGRect
    public let recipe: EditRecipe
    public let faces: [FaceGeometry]        // 전체
    public var targetFaces: [FaceGeometry]  // recipe.portrait.targetFace 적용 결과
}
public protocol RenderStage: Sendable {
    var name: String { get }
    func apply(_ image: CIImage, in context: RenderContext) throws -> CIImage
}
public struct RenderPipeline: Sendable {
    public init(stages: [any RenderStage])
    public static let standard: RenderPipeline   // Skin → FaceReshape → LocalEdit → Color
    public func render(_ image: CIImage, context: RenderContext) throws -> CIImage
}
```

- `render`는 먼저 extent와 레시피 수치의 유효성을 검사한다(비유한수 거부). 그 다음 단계를 순서대로 적용하고 마지막에 원래 extent로 자른다.
- `FaceReshapeStage`는 A에서 현재 `faceSlim` 동작(얼굴 양옆 워프 2회)만 담는다. `LocalEditStage`는 사용자의 수동 편집을 기록 순서대로 재생한다. 두 단계는 `WarpKernel`을 공유한다.
- 모든 수치 상수는 `RenderTuning`에 이름 붙여 모은다(예: `skinBlurRadiusFraction = 0.0015`, `warpDisplacementLimit = 0.25`).

`PhotoPipeline` API:

```swift
public actor PhotoPipeline {
    public init(analyzer: any FaceAnalyzer, tuning: RenderTuning = .forCurrentDevice())
    public func prepare(_ id: PhotoID, at url: URL) async throws -> PreparedPhoto
    public func preview(_ id: PhotoID, recipe: EditRecipe) async throws -> CGImage
    public func renderOriginal(_ id: PhotoID, at url: URL, recipe: EditRecipe, maxDimension: Int?) async throws -> CIImage
    public func evict(_ id: PhotoID)
}
public struct PreparedPhoto: Sendable {
    public let pixelSize: CGSize           // 방향 보정 후 원본 크기
    public let thumbnail: CGImage
    public let faces: [FaceGeometry]
    public let faceAnalysisFailure: MellowError?
}
```

얼굴 분석 실패는 오류가 아니라 `faceAnalysisFailure`로 전달한다. `renderOriginal`은 레시피에 얼굴 의존 값(`skinSmoothing > 0` 또는 `faceSlim > 0`)이 있는데 얼굴이 비어 있고 분석이 실패했었다면 `MellowError.faceAnalysisUnavailable`을 던진다(현재 iOS 정책 유지).

## 6. 앱 구성

### 조립과 상태

`AppModel`(`@Observable`, `@MainActor`)이 composition root다. `ProjectSession`, `PhotoPipeline`, `PhotoImporter`, `ExportDestination`, `SessionStore`를 생성자로 받는다. 기능별 extension 파일로 나눈다(`AppModel+Editing`, `+Library`, `+Export`). 400줄을 넘기면 그때 기능 모델로 분리한다.

편집 흐름: 뷰 → `AppModel.edit { document in document.set(exposure:) }` → 결과가 `Rejection`이면 상태 메시지 → 아니면 `RenderScheduler.request()`(100ms 디바운스, 세대 토큰으로 늦은 결과 폐기) → `PhotoPipeline.preview` → 화면 갱신 → 세션 저장.

### 유스케이스 두 개

`ImportPhotos`: 입력은 `PhotoImporter`가 돌려준 임시 파일 URL 목록. 정책 상한만큼만 받고, 사진마다 (1) 작업 사본으로 이동, iOS에서는 파일 보호 속성 설정 (2) `PhotoPipeline.prepare` (3) 세션에 추가 (4) 저장. 어느 단계든 실패하면 사본을 지우고 실패 목록에 단계 이름과 함께 기록한다. 결과는 `ImportReport { added, failures, warnings }`.

`ExportPhotos`: 입력은 사진 ID 목록, `ExportOptions`, `ExportDestination`. 사진마다 렌더 → `Exporter`로 임시 파일 작성 → 대상에 공개 → 임시 파일 정리. 진행률은 `AsyncStream<Progress>`, 취소는 `Task` 취소(현재의 `cancelExport` 플래그 폐기). 백그라운드 진입 시 앱이 Task를 취소한다. 결과는 `ExportReport { saved, failures }`.

### 플랫폼 어댑터 (앱 타깃 `Platform/`)

| 포트 | iOS·iPadOS | macOS |
|---|---|---|
| `PhotoImporter` | `PhotosPicker` + `fileImporter` | `PhotosPicker` + `fileImporter` + 드래그 앤 드롭 |
| `ExportDestination` | `PhotoLibraryDestination`(사진 앱 추가, addOnly 권한) | `FolderDestination`(폴더 선택, `FileNamingPolicy`로 충돌 회피, 완료 후 Finder 열기) |
| 작업 사본 위치 | Application Support/MellowPhoto/Library, 백업 제외 | 동일 경로 |

Mac도 작업 사본을 만든다. 원본 직접 참조 방식은 폐기한다. 그 대가로 Mac에서도 세션이 재실행 후 복원된다. Mac의 기존 `presets.json`은 첫 실행 때 세션 프리셋으로 흡수하고 `presets.json.imported`로 이름을 바꾼다.

Mac 앱은 App Sandbox를 켠다(user-selected 파일 읽기·쓰기). 임시 서명으로 로컬 실행이 가능해야 하며, 안 되면 A 범위에서 샌드박스를 끄고 기록한다.

### 화면

`horizontalSizeClass`로 적응한다.

- compact(iPhone 세로): 상단 스트립, 캔버스, 액션 바, 하단 도구 패널(세그먼트: 색감·인물·잡티·변형). 현재 iPhone 화면과 같은 구성.
- regular(iPad·Mac): 3단. 왼쪽 라이브러리(썸네일 목록), 가운데 캔버스(도구 바·확대 컨트롤), 오른쪽 인스펙터(탭: 색감·인물·도구).

공통 컴포넌트: `PhotoCanvasView`(확대는 `MagnifyGesture`+`ScrollView`, 잡티 탭·변형 드래그·샘플 위치 표시), `ThumbnailCell`, `ColorPanel`, `PortraitPanel`, `BrushPanel`, `ExportMenu`, `PresetSheet`, `InfoSheet`, `StatusBar`. 키보드 단축키는 `.commands`로 ⌘O·⌘Z·⇧⌘Z·⇧⌘S. Mac에서는 Option+클릭, iOS에서는 "샘플 다시 고르기" 버튼으로 복제 샘플을 바꾼다. 테마 색은 `Theme` 한 곳. 다크 모드 강제는 유지.

문자열은 `Localizable.xcstrings`로 추출한다(`SWIFT_EMIT_LOC_STRINGS` 유지). 번역은 범위 밖.

## 7. 오류 처리

```swift
public enum MellowError: Error, Equatable, Sendable {
    case cannotOpenPhoto(filename: String)
    case unsupportedOrCorruptPhoto
    case cannotCreatePreview
    case invalidImageSize
    case invalidRecipeValues
    case warpUnavailable
    case renderFailed
    case cannotWriteToFolder
    case exportVerificationFailed
    case fileAlreadyExists
    case exportFailed(reason: String)
    case faceAnalysisUnavailable(reason: String)
    case sessionUnreadable
    case sessionWriteFailed(reason: String)
    case photoLibraryAccessDenied
}
```

사용자 문구는 앱 타깃의 `MellowError+UserMessage.swift` 한 곳에서 매핑한다. 모듈은 문구를 모른다. 유지할 정책: 얼굴 분석 실패 시 색감·수동 편집 허용, 얼굴 보정 포함 저장은 거부. 세션 쓰기 실패 시 사진 제거 중단. 읽을 수 없는 세션은 복구 사본 보존 후 새 세션.

## 8. 테스트

| 층 | 대상 | 실행 | 내용 |
|---|---|---|---|
| 모듈(순수) | Editing, Library | `swift test`, GPU 불필요 | 현재 `MobileStoreTests` 6개의 행동(영속·실행취소 복원, 잠금과 프리셋·전체 적용 보존, 사본만 삭제, 손상 세션 보존, 쓰기 실패 시 제거 중단, 준비 전 제거)을 세션 계층으로 이식. v1 픽스처 마이그레이션. 스키마 대조. 사진 수 정책. |
| 모듈(GPU) | Rendering, Export | `swift test`, macOS | 현재 엔진 회귀 8개(항등·색감, 국소 워프·복제, 내보내기·충돌·GPS 없음, 방향·썸네일, 따뜻함 방향, 편집 순서, 인물 파이프라인, 잘못된 수치 거부)를 단계별로 재배치. 추가: 단계 순서가 바뀌면 결과가 달라진다, 캐시된 미리보기와 디스크 재로드 결과가 같다, 데모 인물 사진에서 랜드마크 12종 중 눈·입·윤곽이 채워진다. |
| 앱 | AppModel, ImportPhotos, ExportPhotos | xcodebuild test: iPhone 시뮬레이터, iPad 시뮬레이터, Mac | 가짜 `PhotoImporter`·`ExportDestination`·`FaceAnalyzer`로 가져오기 롤백, 내보내기 취소·실패 보고, 얼굴 분석 실패 시 저장 거부, 디바운스 후 마지막 레시피만 렌더. |

TDD로 진행한다. 각 규칙은 실패하는 테스트를 먼저 쓴다. 기존 `ENGINE_STANDALONE` swiftc 실행 방식은 폐기하고 `swift test`만 쓴다. 스크립트는 `DEVELOPER_DIR`이 Command Line Tools를 가리키면 `/Applications/Xcode.app`으로 바꿔 실행한다.

## 9. 빌드·CI·배포

- `apple/project.yml`(XcodeGen)이 앱 타깃을 정의한다. 타깃 하나, `SUPPORTED_PLATFORMS = iphoneos iphonesimulator macosx`, `TARGETED_DEVICE_FAMILY = 1,2`, 최소 iOS 17·macOS 14, 번들 ID `com.mj.mellowphoto`(iOS·Mac 동일, 통합 구매 대비), `MARKETING_VERSION`은 `Config/Version.xcconfig`에서. 생성된 `.xcodeproj`를 커밋하고 CI가 `xcodegen generate` 후 `git diff --exit-code`로 동기화를 확인한다. 로컬은 `brew install xcodegen`.
- `scripts/test-apple.sh`: verify-modules → swift format lint → `swift test` → iPhone·iPad·Mac 앱 테스트.
- `scripts/build-apple.sh [ios-simulator|ios-device|mac]`: 서명 없는 Release 빌드와 번들 검사(현재 `build-ios.sh device`의 검사 유지).
- `scripts/package-mac.sh`: Mac Release 빌드를 임시 서명해 `dist/Mellow-Photo-Mac.zip`으로 묶는다. 공증은 범위 밖.
- `scripts/release.sh apple 1.0.0`: `Version.xcconfig` 갱신, 커밋, `apple-v1.0.0` 태그. 사용자가 push하면 릴리스 워크플로가 돈다.
- 워크플로: `apple-checks.yml`(PR·main: 위 테스트 스크립트 + Release 빌드 검사), `apple-release.yml`(`apple-v*` 태그: 검증 후 fastlane으로 iOS App Store 업로드, Mac zip은 아티팩트). 현재 `ios-release.yml`의 서명·업로드 레인과 비밀값 처리는 경로만 바꿔 유지한다. `ios-v*` 태그는 더 이상 트리거하지 않는다.
- 릴리스 노트 자동화(`fastlane/release_notes.rb`)는 유지.

## 10. 코드 규칙

- 한 줄 한 문장. 세미콜론으로 문장을 잇지 않는다. 함수는 40줄 안쪽을 목표로 한다.
- 매직 넘버 금지. `RenderTuning`, `EditingPolicy`, `LibraryPolicy`, `Theme`에 이름 붙여 둔다.
- 툴체인 내장 `swift format`(`.swift-format` 설정 커밋)을 CI에서 `lint --strict`로 검사한다.
- Swift tools 5.9, Swift 5 언어 모드, `-strict-concurrency=complete`를 켜고 경고 0을 유지한다. 모듈 공개 타입은 `Sendable`.
- 주석은 "왜"만 쓴다. 한국어 사용자 문구는 앱 타깃에만 둔다.

## 11. 이행 순서 (계획 문서가 세분화)

1. `apple/` 패키지 생성. Shared 타입과 Editing 규칙을 TDD로 작성.
2. Library: `ProjectSession`, `JSONSessionStore`, `SessionFile` v1·v2, 기준 커밋 코드로 v1 픽스처 생성, 마이그레이션 테스트.
3. Rendering: 현재 엔진을 옮겨 단계로 분해. 회귀 8개 통과 유지. `PhotoPipeline` 캐시.
4. Export: `Exporter`, `FileNamingPolicy`, `ExportDestination` 포트.
5. 앱 타깃: XcodeGen 정의, `AppModel`, 유스케이스 2개, 어댑터, 적응형 화면. 세 플랫폼 빌드.
6. 구 코드 삭제(`Sources/`, `Tests/`, `iOS/`), 자산·테스트 이동.
7. 스크립트·CI·`verify-modules`·모듈 캔버스·README·IOS.md·MAC_INSTALL.md·VALIDATION.md 갱신.
8. 검증: iPhone·iPad 시뮬레이터와 Mac에서 가져오기→편집→실행취소→저장. v1 세션 복원 실기동 확인.

각 단계는 독립 커밋이며 CI가 녹색이어야 다음으로 간다.

## 12. 범위 밖과 위험

범위 밖: 새 보정 효과(B~F), Android·Windows 코드, 영어 번역, Mac App Store 제출·공증, 핀치 확대 외 새 UI 기능, HDR·RAW.

| 위험 | 대응 |
|---|---|
| 단계 분해 후 출력이 미세하게 달라짐 | 회귀 테스트가 바이트 동일성을 보는 항목(항등, 순서)을 유지. 바이트 비교가 불가한 항목은 방향성 검사. |
| LRU 3장 캐시로 사진 전환 시 첫 렌더 지연 | 썸네일은 전부 보관. 선택 변경 시 준비를 먼저 끝내고 렌더. 현재 iOS도 매번 읽으므로 악화는 아님. |
| Mac 샌드박스와 임시 서명 충돌 | 실패 시 A에서는 샌드박스를 끄고 VALIDATION에 기록. |
| XcodeGen이 CI에 없음 | brew로 설치. 느리면 생성 결과 비교 단계만 별도 job으로. |
| iPhone 출시본 세션 호환 | 실제 인코드한 픽스처로 테스트하고, 시뮬레이터에 출시본 세션 파일을 넣어 복원 실기동 확인. |
| Swift 6 strict concurrency 경고 폭증 | 5 모드 + complete 경고로 시작. 모듈 단위로 해결. |
