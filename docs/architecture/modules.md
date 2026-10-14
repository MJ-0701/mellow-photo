# 모듈 지도와 캔버스

Mellow Photo Apple 코드는 능력 단위 Swift 모듈 다섯 개(`apple/Package.swift`의 MellowKit)와 iPhone·iPad·Mac을 한 번에 빌드하는 SwiftUI 앱 타깃 하나(`apple/MellowPhoto/`)로 이루어집니다. Android(Kotlin)와 Windows(C/C++) 구현도 같은 다섯 모듈 경계를 따릅니다. 설계 근거는 [구조 리팩토링 설계](../superpowers/specs/2026-10-14-apple-modulith-restructure-design.md) 3절입니다.

## 의존성 지도

```
MellowShared ◄── MellowEditing ◄── MellowLibrary
     ▲
     ├──────── MellowRendering ◄── MellowExport
     └──────── (앱 타깃은 다섯 모듈 모두 import)
```

허용 의존성은 다음 표가 전부입니다. 역방향, 수평(예: Rendering→Library), 앱 타깃을 향한 의존은 금지합니다.

| 모듈 | import 허용 | 금지 프레임워크 |
|---|---|---|
| MellowShared | Foundation, CoreGraphics | 그 외 전부 |
| MellowEditing | MellowShared | CoreImage, Vision, SwiftUI, UIKit, AppKit, Photos |
| MellowLibrary | MellowShared, MellowEditing | CoreImage, Vision, SwiftUI, UIKit, AppKit, Photos |
| MellowRendering | MellowShared, CoreImage, Vision, ImageIO, UniformTypeIdentifiers | SwiftUI, UIKit, AppKit, Photos |
| MellowExport | MellowShared, MellowRendering, ImageIO, UniformTypeIdentifiers | SwiftUI, UIKit, AppKit, Photos |
| 앱 타깃 | 전부 | 없음 |

모듈 내부는 폴더 세 개로 나눕니다. `API/`에는 `public` 타입만 두고, `Domain/`과 `Infrastructure/`는 `internal`입니다. 다른 모듈과 앱은 `API/`의 타입만 씁니다. 아래 캔버스의 "공개 API"는 각 모듈 `API/` 폴더의 타입 전부입니다.

## 모듈 캔버스

### MellowShared
| 항목 | 내용 |
|---|---|
| 책임 | 플랫폼 간 계약이 되는 값 타입과 오류 (공유 커널) |
| 공개 API | `EditRecipe`, `ColorAdjustments`, `PortraitAdjustments`, `LocalEdit`, `RetouchSpot`, `WarpStroke`, `NormalizedPoint`, `NormalizedRect`, `PhotoID`, `FaceGeometry`, `FaceLandmark`, `Preset`, `PresetValues`, `BuiltInPresets`, `MellowError` |
| 의존 | 없음 (Foundation, CoreGraphics) |
| 포트 | 없음 |
| 규칙 | 레시피는 v2로만 인코드하고 빠진 키는 기본값으로 디코드, 좌표는 방향 보정 이미지 기준 정규화(원점 왼쪽 아래), 내장 프리셋(내추럴·포근한·클린)은 `BuiltInPresets` 한 곳, 한국어 사용자 문구 없음 |
| 테스트 | `apple/Tests/MellowSharedTests` (레시피 코딩, 얼굴 기하, `edit-recipe.v2` 스키마 키 대조. GPU 불필요) |
| 다른 플랫폼 대응 | Kotlin `:shared`, C++ `mellow_shared` |

### MellowEditing
| 항목 | 내용 |
|---|---|
| 책임 | 사진 한 장의 편집 상태와 규칙 |
| 공개 API | `EditDocument`, `EditChange`, `EditingPolicy` |
| 의존 | MellowShared |
| 포트 | 없음 |
| 규칙 | 변경 전 체크포인트, 수동 편집 시 얼굴 형태·대상 잠금, 프리셋·일괄 적용 시 잠긴 값 보존, 히스토리 40 |
| 테스트 | `apple/Tests/MellowEditingTests` (GPU 불필요) |
| 다른 플랫폼 대응 | Kotlin `:editing`, C++ `mellow_editing` |

규칙은 모두 `EditDocument` 안에만 있습니다. 슬라이더 드래그는 `beginContinuousChange`/`endContinuousChange`로 시작할 때 한 번만 체크포인트합니다. 잠긴 동안의 얼굴 형태·대상 변경은 무시하고 `EditDocument.Rejection`을 돌려줍니다. 잠기지 않은 사진에 일괄 적용하면 대상 얼굴을 모든 얼굴로 되돌립니다.

### MellowLibrary
| 항목 | 내용 |
|---|---|
| 책임 | 사진 목록과 선택, 작업 사본, 세션 영속화와 복구, 프리셋 보관, 사진 수 정책 |
| 공개 API | `ProjectSession`, `PhotoEntry`, `SessionSnapshot`, `SessionStore`, `JSONSessionStore`, `WorkingCopyStore`, `LibraryPolicy` |
| 의존 | MellowShared, MellowEditing |
| 포트 | `SessionStore` (`load() throws -> SessionSnapshot?`, `save(SessionSnapshot) throws`). 구현은 같은 모듈의 `JSONSessionStore` |
| 규칙 | 세션 파일은 v1(출시본 iPhone)·v2를 읽고 v2로만 씀, 원자적 쓰기, 읽을 수 없는 파일은 `session-recovery-<uuid>.json`으로 보존한 뒤 새 세션, 사진 제거는 저장 성공 후에만 반영, 사진 수 상한은 물리 메모리 4GB 미만 12장·8GB 미만 24장·그 외 40장, 프리셋 이름 30자, 작업 사본은 `Library/<uuid>.<확장자>`이고 출시본 iPhone의 상위 폴더 사본도 찾음 |
| 테스트 | `apple/Tests/MellowLibraryTests` (v1 픽스처 이행, `session-file.v2` 스키마 키 대조, 손상 세션 보존, 쓰기 실패 시 제거 중단, 사진 수 정책. GPU 불필요) |
| 다른 플랫폼 대응 | Kotlin `:library`, C++ `mellow_library` |

디스크 포맷 `SessionFile`(v2)과 `SessionFileV1`은 `Infrastructure/`의 DTO이며, `SessionFileMapper`가 `SessionSnapshot`과 변환합니다. `ProjectSession`은 DTO를 모릅니다. 형식은 [`shared/recipe-schema/`](../../shared/recipe-schema/README.md)가 기술합니다.

### MellowRendering
| 항목 | 내용 |
|---|---|
| 책임 | 사진 읽기, 얼굴 분석, 레시피 렌더, 미리보기 캐시 |
| 공개 API | `PhotoPipeline`, `PreparedPhoto`, `RenderPipeline`, `RenderStage`, `RenderContext`, `RenderTuning`, `Renderer`, `FaceAnalyzer`, `ImageLoader`, `ImageMetadata` |
| 의존 | MellowShared (CoreImage, Vision, ImageIO) |
| 포트 | `FaceAnalyzer` (`analyze(CIImage) throws -> [FaceGeometry]`). 기본 구현 `VisionFaceAnalyzer`는 `Infrastructure/`에 있으며 앱이 조립할 수 있도록 `public`입니다 |
| 규칙 | 단계 순서 `SkinStage` → `FaceReshapeStage` → `LocalEditStage` → `ColorStage` 고정, 미리보기 LRU 3장 캐시(미리보기 렌더는 디스크를 읽지 않음), 미리보기 긴 변은 메모리 8GB 이상 1600px·미만 1200px, 원본 렌더는 준비 때의 정규화 얼굴 좌표 재사용, 얼굴 의존 레시피인데 분석이 실패했거나 준비 전이면 `faceAnalysisUnavailable`, 수치 상수는 `RenderTuning`, `CIWarpKernel`은 `WarpKernel` 하나만 감쌈 |
| 테스트 | `apple/Tests/MellowRenderingTests` (GPU 회귀, 단계 순서, 캐시 동등성, 데모 인물 랜드마크. macOS) |
| 다른 플랫폼 대응 | Kotlin `:rendering`, C++ `mellow_rendering` |

얼굴 분석 실패는 오류가 아니라 `PreparedPhoto.faceAnalysisFailure`로 전달합니다. 색감·수동 편집은 계속할 수 있습니다. 오류 사유는 영어 식별자(예: `PhotoPipeline.unpreparedReason` = `photo-not-prepared`)이며 사용자 문구는 앱의 `UserMessage`가 정합니다.

### MellowExport
| 항목 | 내용 |
|---|---|
| 책임 | 렌더 결과를 파일로 안전하게 쓰기, 이름 충돌 정책, 저장 대상 추상화 |
| 공개 API | `Exporter`, `ExportFormat`, `ExportOptions`, `ExportDestination`, `FileNamingPolicy` |
| 의존 | MellowShared, MellowRendering (ImageIO, UniformTypeIdentifiers) |
| 포트 | `ExportDestination` (`publish(fileURL:suggestedName:) async throws`). 구현은 앱 타깃 `Platform/` |
| 규칙 | 임시 파일에 쓰고 재해독으로 검증한 뒤 `renameatx_np(RENAME_EXCL)`로 공개(덮어쓰기 없음), 출력은 8bit sRGB JPEG/PNG·EXIF 방향 1·원본 GPS와 카메라 EXIF 복사 안 함, 원본 해상도를 끄면 긴 변 최대 4096px, 파일 이름은 `<이름>_mellow`에 충돌 시 번호 |
| 테스트 | `apple/Tests/MellowExportTests` (내보내기·충돌·GPS 없음, 이름 정책. macOS) |
| 다른 플랫폼 대응 | Kotlin `:export`, C++ `mellow_export` |

## 앱 타깃

`apple/MellowPhoto/`는 다섯 모듈을 모두 import하는 유일한 곳입니다. 정의는 `apple/project.yml`(XcodeGen)이고 생성된 `apple/MellowPhoto.xcodeproj`를 커밋합니다.

| 폴더 | 역할 |
|---|---|
| `App/` | `MellowPhotoApp`, 창, 명령(⌘Z·⇧⌘Z). 장면 전환 시 내보내기 취소와 작업 중단·재개 |
| `Application/` | `AppModel`(composition root, `@Observable`·`@MainActor`)과 기능별 extension(`+Editing`, `+Library`, `+Export`), 유스케이스 `ImportPhotos`·`ExportPhotos`, `RenderScheduler`(디바운스와 세대 토큰으로 마지막 요청만 렌더), 포트 `PhotoImporter`(`Ports.swift`), 모든 한국어 문구 `UserMessage` |
| `Features/` | SwiftUI 화면. `Library`, `Editor`, `Export`, `Presets`, `Info`, `Shared`. compact(iPhone 세로)는 세로 스택, regular(iPad·Mac)는 라이브러리·캔버스·인스펙터 3단 |
| `Platform/` | 포트 어댑터와 실기기 조립 |
| `Resources/` | 에셋, `Localizable.xcstrings`, Info.plist(iOS·macOS), `PrivacyInfo.xcprivacy`, Mac 엔타이틀먼트(App Sandbox), `container-migration.plist` |

`AppModel`은 `ProjectSession`(안에 `SessionStore`), `PhotoPipeline`(안에 `FaceAnalyzer`), `WorkingCopyStore`, `PhotoImporter`, `Exporter`를 생성자로 받습니다. `ExportDestination`은 내보낼 때마다 넘깁니다. 테스트(`apple/MellowPhotoTests`)는 가짜 어댑터로 같은 생성자를 씁니다.

유스케이스는 두 개뿐입니다.

- `ImportPhotos`: `PhotoImporter`가 임시 폴더에 옮긴 파일을 정책 상한만큼 받아, 사진마다 작업 사본으로 이동 → `PhotoPipeline.prepare` → 세션에 추가 → 저장합니다. 어느 단계에서 실패해도 사본을 지우고 단계 이름과 함께 `ImportReport`에 기록합니다.
- `ExportPhotos`: 사진마다 원본 렌더 → `Exporter`로 임시 파일 작성 → `ExportDestination`에 공개 → 임시 파일 정리. 취소는 `Task` 취소이며 결과는 `ExportReport`입니다.

`Platform/` 어댑터:

| 파일 | 역할 |
|---|---|
| `SystemPhotoImporter` | `PhotoImporter` 구현. PhotosPicker 항목과 파일 선택·드래그 앤 드롭으로 받은 파일을 임시 폴더로 복사 |
| `PhotoLibraryDestination` | iOS·iPadOS `ExportDestination`. 사진 앱에 새 사진으로 추가(addOnly 권한) |
| `FolderDestination` | macOS `ExportDestination`. 사용자가 고른 폴더에 복사, `FileNamingPolicy`로 충돌 회피 |
| `LegacyMacPresets` | 구 Mac 앱의 `presets.json`을 세션 복원 뒤 한 번 흡수하고 `presets.json.imported`로 이름 변경 |
| `AppModel+Live` | 실기기 조립. `Application Support/MellowPhoto/session.json`, `…/Library/` 작업 사본, `VisionFaceAnalyzer`, 기기별 `LibraryPolicy`·`RenderTuning` |

## 검증

`scripts/verify-modules.sh`가 이 문서의 의존성 표와 소스의 import를 대조합니다. 표의 값을 스크립트 안에 그대로 옮겨 두고 `swift package describe --type json`의 타깃 의존성과 비교하며, 각 모듈 소스의 `import` 문에서 금지 프레임워크(Shared는 ImageIO, 모든 모듈은 PhotosUI 포함)를 찾고, 모듈마다 `API/` 폴더가 있는지 확인합니다. 위반하면 종료 코드 1이며 `scripts/test-apple.sh`와 CI의 필수 단계입니다. 이 표를 바꾸면 스크립트의 표도 같은 커밋에서 고칩니다.
