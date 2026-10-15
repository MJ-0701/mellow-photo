# B0 기본 편집 세트 구현 계획

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 필터(룩) 10종, 자동 보정 한 번, 자르기·회전·수평, 하이라이트·그림자·선명도·비네팅을 A의 모듈 구조 위에 얹어 SNOW식 원탭 기본 편집을 완성한다.

**Architecture:** 레시피 v2에 `detail`·`look`·`geometry`를 추가(기본값, schemaVersion 유지)하고, 렌더 파이프라인에 `DetailStage`→`LookStage`→`GeometryStage`를 뒤에 붙인다. 룩은 `shared/looks/looks.v1.json`의 파라미터 데이터이며 `LookStage`가 Core Image 기본 필터로 조립한다. 자르기는 맨 마지막 단계라 얼굴·수동 편집 좌표는 원본 기준 그대로이고, 순수 수학 `GeometryTransform`이 화면 좌표와 원본 좌표를 오간다. 자동 보정은 `AutoEnhancer`가 히스토그램으로 슬라이더 값을 제안하고 `EditDocument.applyAuto`가 체크포인트 한 번으로 적용한다.

**Tech Stack:** Swift 5.9 tools / Swift 5 언어 모드, SwiftUI + Observation, Core Image(CIHighlightShadowAdjust·CISharpenLuminance·CIVignette·CIToneCurve·CIColorControls·CITemperatureAndTint·CIMix·CIAreaHistogram·CIAreaAverage), XCTest, XcodeGen 2.46.0.

**Spec:** `docs/superpowers/specs/2026-10-14-b0-basic-editing-design.md`

## 사람이 확인할 것

- **순서.** Task 1(A에서 보류한 결함 3건) → 2~5 데이터·규칙 → 6~10 렌더 단계·자동 보정·썸네일 → 11 AppModel → 12 화면 → 13 문서·검증. 13개 Task, 각 Task마다 Opus 구현 → 리뷰 → 수정 루프, 끝에 전체 리뷰.
- **외부 효과가 있는 단계.** 없음. 푸시·태그·심사 제출은 이 계획에 없다(B0 뒤 사용자 결정).
- **사용자 검증이 필요한 것.** 룩 10종의 실제 느낌(Task 12 실기동 캡처를 보고 수치 조정 요청 가능), iOS 대화형 실기동(셸에서 불가, 사용자가 시뮬레이터 패널로).
- **되돌리기 쉬운 결정.** 룩 수치, 자동 보정 게인(`RenderTuning`), 도구 줄 순서. 되돌리기 어려운 결정은 스펙의 "사람이 확인할 것" 표 참조.
- **예상 리스크.** 자르기 오버레이 제스처(iPad 핀치와 손잡이 드래그 충돌)는 실기동에서만 드러남. Core Image `CIHighlightShadowAdjust`가 원본 해상도에서 느릴 수 있음(진행률로 표시).

---

## 에이전트 참조

## Global Constraints

- 작업 위치: 저장소 루트 `/Users/mj/IdeaProjects/mellow-photo`의 `main`에서 분기한 브랜치(worktree는 실행 시 using-git-worktrees가 만든다). 모든 명령 전에 `export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`. XcodeGen 2.46.0이 설치돼 있고 `apple/.xcodegen-version`이 그 버전을 고정한다.
- 모듈 의존성 표(스펙 A §3)와 `scripts/verify-modules.sh`는 바뀌지 않는다. Shared는 Foundation·CoreGraphics만, Editing·Library는 CoreImage·Vision·SwiftUI·UIKit·AppKit·Photos 금지, Rendering·Export는 SwiftUI·UIKit·AppKit·Photos 금지.
- `schemaVersion`은 2 유지. 새 레시피 필드는 전부 기본값이 있어 A에서 저장한 세션과 v1 마이그레이션 결과가 그대로 읽힌다.
- 좌표는 정규화·원점 왼쪽 아래. `geometry.crop`은 반전·회전·수평 보정이 끝난 이미지 기준. 기하 단계는 파이프라인 맨 마지막.
- 파이프라인 단계 이름 순서: `skin, faceReshape, localEdit, color, detail, look, geometry`.
- 값 범위: highlights·shadows −1…1, sharpness·vignette 0…1, look.intensity 0…1, quarterTurns 0…3, straightenDegrees −15…15.
- 자동 보정 상수(`RenderTuning`): autoTargetLuminance 0.45, autoWarmthGain 0.5, autoWarmthLimit 0.3, autoHighlightThreshold 0.97, autoShadowThreshold 0.03, autoSaturation 1.08, autoContrast 1.04, autoSkinSmoothing 0.3, autoFaceSlim 0.15.
- 룩 id 10개 고정: clear, film, cozy, calm, mono, sepia, vintage, vivid, pastel, night. 이름: 맑음·필름·포근·차분·모노·세피아·빈티지·선명·파스텔·밤.
- 한국어 사용자 문구는 `UserMessage`와 뷰에만. 한 줄 한 문장, 세미콜론 금지, 매직 넘버는 `RenderTuning`·`Theme`·`AppModel.Policy`·`EditingPolicy`에. `swift format lint --strict --recursive apple/Sources apple/Tests apple/MellowPhoto apple/MellowPhotoTests` 경고 0. 허용된 기존 경고: `CIWarpKernel` deprecation, 시뮬레이터 `usesCPUOnly`.
- 커밋: 한국어 Conventional Commits, 마지막 줄 `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`. `git add`는 나열한 경로만.
- 각 Task 끝에 `cd apple && swift test`(패키지) 또는 지정된 앱 테스트가 통과해야 다음으로 간다. 최종 검증은 `./scripts/test-apple.sh`.

## Review Focus

스펙이 암시하지만 어느 Task의 테스트도 직접 다루지 않던 입력. 각 줄의 테스트를 소유 Task에 추가했다.

1. **A에서 저장한 세션(detail·look·geometry 키 없음)을 B0가 읽는다.** 키가 없으면 전부 기본값이어야 하고 `isDefault`가 true여야 한다. → Task 2 `testRecipeWithoutNewKeysDecodesToDefaults`.
2. **자른 상태에서 잡티를 탭하면 원본 좌표로 기록돼야 하고, 자르기를 되돌려도 잡티가 같은 자리에 있어야 한다.** → Task 11 `testRetouchTapWhileCroppedIsStoredInOriginalCoordinates`.
3. **룩 썸네일을 만드는 동안 사진을 바꾸면 이전 사진의 썸네일이 새 사진에 붙으면 안 된다.** → Task 11 `testLookThumbnailsIgnoreStaleResults`.
4. **자동 보정을 두 번 누르면 값이 누적되지 않고 두 번째도 같은 결과여야 한다(제안은 원본 분석 기준).** → Task 9 `testSuggestionDoesNotDependOnCurrentRecipe` + Task 11 `testAutoEnhanceTwiceIsIdempotent`.
5. **수평 보정 ±15°와 90° 회전을 섞어도 내보낸 파일 크기가 미리보기 비율과 같아야 한다.** → Task 8 `testGeometryOutputAspectMatchesTransform`.

## 인터페이스 요약 (모든 Task가 공유하는 이름)

```swift
// MellowShared
public struct DetailAdjustments: Codable, Equatable, Sendable { highlights, shadows, sharpness, vignette: Double; isDefault }
public struct LookSelection: Codable, Equatable, Sendable { id: String?; intensity: Double (기본 1) }
public struct GeometryAdjustments: Codable, Equatable, Sendable { flipHorizontal, quarterTurns, straightenDegrees, crop: NormalizedRect?; isIdentity }
public struct EditRecipe { … + detail, look, geometry }
public struct PresetValues { color, portrait, detail }
public struct Look: Codable, Equatable, Sendable, Identifiable { id, name, toneCurve: [[Double]], saturation, contrast, warmth, tint, vignette, fade }
public struct LookCatalog: Equatable, Sendable { init(data:) throws; init(looks:); static let empty; all; look(id:) }
public struct GeometryTransform: Sendable { init(geometry:sourceAspect:); outputAspect; toOriginal(_:); toOutput(_:) -> NormalizedPoint? }
public struct AutoEnhanceSuggestion: Equatable, Sendable { color, detail, portrait }

// MellowEditing
public enum EditChange { … + highlights, shadows, sharpness, vignette, lookID(String?), lookIntensity, flipHorizontal(Bool), quarterTurns(Int), straightenDegrees, crop(NormalizedRect?) }
public struct EditDocument { … + applyAuto(_ suggestion: AutoEnhanceSuggestion) }

// MellowLibrary
ProjectSession: + endContinuousChange(_ id: PhotoID)   // 저장 없이 플래그만

// MellowRendering
RenderTuning: + detail/look/geometry/auto 상수
RenderContext: + lookCatalog: LookCatalog, skipsCrop: Bool
RenderPipeline.standard: 7단계; render()는 마지막 crop을 제거하고 단계 결과를 그대로 돌려줌
PhotoPipeline: init(analyzer:tuning:lookCatalog:); preview(_:recipe:showsUncropped:); autoEnhanceSuggestion(_:hasFaces:); lookThumbnails(_:) -> [String: CGImage]
public struct AutoEnhancer { init(tuning:renderer:); suggestion(for image: CIImage, hasFaces: Bool) throws -> AutoEnhanceSuggestion }

// 앱
EditorTool: look, crop, adjust, portrait, retouch, warp
AppModel: + lookCatalog, lookThumbnails, cropAspect, canvasShowsUncropped, outputTransform, autoEnhance(), loadLookThumbnails(), flushPendingEdits(), beginCropDrag()/endCropDrag()
```

---

### Task 1: A에서 보류된 결함 3건 정리

**Files:**
- Modify: `apple/Sources/MellowLibrary/API/ProjectSession.swift` (`endContinuousChange(_:)` 추가)
- Modify: `apple/MellowPhoto/Application/AppModel.swift` (`endContinuousChangeOnSelected` 교체, `flushPendingEdits()` 추가)
- Modify: `apple/MellowPhoto/App/MellowPhotoApp.swift` (`.background`에서 `flushPendingEdits()`)
- Modify: `docs/APPLE.md` (핀치 확대 문장 삭제, 테스트 수 갱신)
- Test: `apple/Tests/MellowLibraryTests/ProjectSessionTests.swift`
- Test: `apple/MellowPhotoTests/AppModelTests.swift`

**Interfaces:**
- Consumes: `ProjectSession.edit`, `isPersistenceDeferred`, `endDeferredPersistence()`, `MemorySessionStore.saveCount`(앱 테스트 지원).
- Produces: `ProjectSession.endContinuousChange(_ id: PhotoID)`(저장 없이 문서의 연속 변경만 끝냄), `AppModel.flushPendingEdits()`(연속 변경 종료 + 미룬 저장 수행).

- [ ] **Step 1: 실패하는 테스트 작성**

`apple/Tests/MellowLibraryTests/ProjectSessionTests.swift`에 추가:

```swift
    func testEndContinuousChangeDoesNotSave() throws {
        let store = MemorySessionStore()
        let session = ProjectSession(store: store, maxPhotos: 40)
        let photo = entry("A")
        try session.add(photo)
        session.edit(photo.id) { document in
            document.beginContinuousChange()
            return nil
        }
        let before = store.saveCount
        session.endContinuousChange(photo.id)
        XCTAssertEqual(store.saveCount, before, "플래그만 끄고 파일은 쓰지 않는다")
        session.edit(photo.id) { $0.set(.exposure(0.2)) }
        XCTAssertEqual(session.photos[0].document.undoStack.count, 2, "연속 변경이 끝났으므로 다음 편집은 체크포인트한다")
    }
```

`apple/MellowPhotoTests/AppModelTests.swift`에 추가:

```swift
    func testSelectingAnotherPhotoSavesOnceNotTwice() async throws {
        let first = try TestSupport.solidPNG(in: root, name: "A")
        let second = try TestSupport.solidPNG(in: root, name: "B")
        let store = MemorySessionStore()
        let importer = FakeImporter(staged: [
            .success(StagedPhoto(url: first, displayName: "A")), .success(StagedPhoto(url: second, displayName: "B")),
        ])
        let model = TestSupport.makeModel(root: root, importer: importer, store: store)
        await model.importFromFiles([first, second])
        try await waitUntil { model.isReady }
        let before = store.saveCount
        model.select(model.session.photos[1].id)
        XCTAssertEqual(store.saveCount, before + 1, "선택 변경은 세션을 한 번만 저장한다")
    }

    func testFlushPendingEditsSavesOpenDrag() async throws {
        let staged = try TestSupport.solidPNG(in: root)
        let store = MemorySessionStore()
        let model = TestSupport.makeModel(
            root: root, importer: FakeImporter(staged: [.success(StagedPhoto(url: staged, displayName: nil))]), store: store)
        await model.importFromFiles([staged])
        try await waitUntil { model.isReady && model.preview != nil }
        model.beginSliderEdit()
        model.edit(.exposure(0.5))
        let before = store.saveCount
        model.flushPendingEdits()
        XCTAssertEqual(store.saveCount, before + 1)
        XCTAssertEqual(store.saved?.photos.first?.document.recipe.color.exposure, 0.5)
        XCTAssertFalse(model.session.isPersistenceDeferred)
    }
```

- [ ] **Step 2: 실패 확인**

Run: `cd apple && swift test --filter ProjectSessionTests/testEndContinuousChangeDoesNotSave`
Expected: 컴파일 실패 (`endContinuousChange` 없음). 앱 테스트는 Step 4에서 함께 확인한다.

- [ ] **Step 3: 구현**

`ProjectSession.swift`에 추가 (`edit(_:_:)` 아래):

```swift
    /// 연속 변경 플래그는 영속 상태가 아니므로 파일을 쓰지 않고 끝낸다.
    public func endContinuousChange(_ id: PhotoID) {
        guard let index = index(of: id) else { return }
        photos[index].document.endContinuousChange()
    }
```

`AppModel.swift`의 `endContinuousChangeOnSelected()`를 다음으로 교체하고 `flushPendingEdits()`를 추가:

```swift
    /// 드래그가 끝나지 않은 채 사진을 바꾸면 이전 사진의 연속 변경과 미룬 저장을 마무리한다.
    private func endContinuousChangeOnSelected() {
        if let previous = session.selectedPhotoID {
            session.endContinuousChange(previous)
        }
        if session.isPersistenceDeferred {
            session.endDeferredPersistence()
        }
    }

    /// 백그라운드 진입처럼 드래그 종료 이벤트가 오지 않을 수 있는 시점에 열린 작업을 저장한다.
    func flushPendingEdits() {
        endContinuousChangeOnSelected()
        if let error = session.lastPersistenceError {
            present(error)
        }
    }
```

`MellowPhotoApp.swift`의 `.background` 분기:

```swift
                    if phase == .background {
                        model.cancelExport()
                        model.stopWork()
                        model.flushPendingEdits()
                    }
```

`docs/APPLE.md`: "핀치 확대는 아직 없습니다." 문장을 삭제하고, 테스트 수를 "패키지 71 / 앱 iPhone 26 · iPad 26 · macOS 27"로 바꾼다.

- [ ] **Step 4: 통과 확인**

Run: `cd apple && swift test` → 전부 PASS. 그리고 `xcodebuild -project apple/MellowPhoto.xcodeproj -scheme MellowPhoto -destination 'platform=macOS' test 2>&1 | grep -E "Executed|TEST"` → `Executed 29 tests, with 0 failures`.

- [ ] **Step 5: 커밋**

```bash
git add apple/Sources/MellowLibrary/API/ProjectSession.swift apple/MellowPhoto/Application/AppModel.swift apple/MellowPhoto/App/MellowPhotoApp.swift apple/Tests/MellowLibraryTests/ProjectSessionTests.swift apple/MellowPhotoTests/AppModelTests.swift docs/APPLE.md
git commit -m "fix(app): 백그라운드 진입 시 열린 드래그를 저장하고 사진 전환의 중복 저장 제거

구조 리팩토링 최종 리뷰에서 보류한 세 건을 정리한다. 연속 변경 종료는
영속 상태가 아니므로 파일을 쓰지 않게 하고, 문서의 핀치 확대 문장을 지운다.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 2: 레시피 확장 — detail·look·geometry와 프리셋 detail

**Files:**
- Create: `apple/Sources/MellowShared/API/DetailAdjustments.swift`
- Create: `apple/Sources/MellowShared/API/LookSelection.swift`
- Create: `apple/Sources/MellowShared/API/GeometryAdjustments.swift`
- Modify: `apple/Sources/MellowShared/API/EditRecipe.swift`
- Modify: `apple/Sources/MellowShared/API/Preset.swift` (`PresetValues.detail`)
- Modify: `shared/recipe-schema/edit-recipe.v2.schema.json`, `shared/recipe-schema/session-file.v2.schema.json`, `shared/recipe-schema/README.md`
- Test: `apple/Tests/MellowSharedTests/EditRecipeCodingTests.swift` (추가), `apple/Tests/MellowSharedTests/RecipeSchemaTests.swift` (확장), `apple/Tests/MellowLibraryTests/SessionFileMigrationTests.swift` (추가)

**Interfaces:**
- Consumes: `NormalizedRect`, `ColorAdjustments`, `PortraitAdjustments`.
- Produces: `DetailAdjustments(highlights:shadows:sharpness:vignette:)`·`isDefault`, `LookSelection(id:intensity:)`, `GeometryAdjustments(flipHorizontal:quarterTurns:straightenDegrees:crop:)`·`isIdentity`, `EditRecipe.detail/look/geometry`, `PresetValues(color:portrait:detail:)`.

- [ ] **Step 1: 실패하는 테스트 작성**

`EditRecipeCodingTests.swift`에 추가:

```swift
    func testRecipeWithoutNewKeysDecodesToDefaults() throws {
        let json = #"{"schemaVersion":2,"color":{"exposure":0.2},"portrait":{},"operations":[]}"#
        let decoded = try JSONDecoder().decode(EditRecipe.self, from: Data(json.utf8))
        XCTAssertEqual(decoded.detail, DetailAdjustments())
        XCTAssertEqual(decoded.look, LookSelection())
        XCTAssertEqual(decoded.geometry, GeometryAdjustments())
        XCTAssertNil(decoded.look.id)
        XCTAssertEqual(decoded.look.intensity, 1)
        var plain = decoded
        plain.color.exposure = 0
        XCTAssertTrue(plain.isDefault)
    }

    func testNewFieldsRoundTripAndAffectDefaultness() throws {
        var recipe = EditRecipe()
        recipe.detail.highlights = -0.4
        recipe.look = LookSelection(id: "film", intensity: 0.7)
        recipe.geometry = GeometryAdjustments(
            flipHorizontal: true, quarterTurns: 1, straightenDegrees: -3,
            crop: NormalizedRect(x: 0.1, y: 0.2, width: 0.5, height: 0.5))
        XCTAssertFalse(recipe.isDefault)
        let data = try JSONEncoder().encode(recipe)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual((json["look"] as? [String: Any])?["id"] as? String, "film")
        XCTAssertEqual((json["geometry"] as? [String: Any])?["quarterTurns"] as? Int, 1)
        let decoded = try JSONDecoder().decode(EditRecipe.self, from: data)
        XCTAssertEqual(decoded, recipe)
    }

    func testNonFiniteGeometryIsNotFinite() {
        var recipe = EditRecipe()
        recipe.geometry.straightenDegrees = .infinity
        XCTAssertFalse(recipe.allValuesFinite)
        recipe.geometry.straightenDegrees = 0
        recipe.detail.vignette = .nan
        XCTAssertFalse(recipe.allValuesFinite)
    }

    func testPresetValuesCarryDetail() throws {
        let values = PresetValues(detail: DetailAdjustments(vignette: 0.3))
        let decoded = try JSONDecoder().decode(PresetValues.self, from: JSONEncoder().encode(values))
        XCTAssertEqual(decoded.detail.vignette, 0.3)
        let legacy = #"{"color":{},"portrait":{}}"#
        XCTAssertEqual(try JSONDecoder().decode(PresetValues.self, from: Data(legacy.utf8)).detail, DetailAdjustments())
    }
```

`RecipeSchemaTests.swift`의 `encodedSampleRecipe()`에 새 필드를 채우고(`recipe.look = LookSelection(id: "film", intensity: 0.5)`, `recipe.geometry.crop = NormalizedRect(x: 0, y: 0, width: 1, height: 1)`, `recipe.detail.sharpness = 0.2`), `testRecipeSchemaPropertiesMatchEncodedKeys`에 다음을 추가:

```swift
        for key in ["detail", "look", "geometry"] {
            let encodedSection = try XCTUnwrap(encoded[key] as? [String: Any], "\(key) 누락")
            XCTAssertEqual(try propertyKeys(properties[key]), Set(encodedSection.keys), key)
        }
        let geometryProperties = try XCTUnwrap((properties["geometry"] as? [String: Any])?["properties"] as? [String: Any])
        let encodedCrop = try XCTUnwrap((encoded["geometry"] as? [String: Any])?["crop"] as? [String: Any])
        XCTAssertEqual(try propertyKeys(geometryProperties["crop"]), Set(encodedCrop.keys))
```

`SessionFileMigrationTests.swift`에 추가:

```swift
    func testPresetWithoutDetailDecodes() throws {
        let json = """
            {"schemaVersion":2,"photos":[],"presets":[{"id":"33333333-3333-3333-3333-333333333333","name":"옛","values":{"color":{"exposure":0.1},"portrait":{}}}]}
            """
        let snapshot = SessionFileMapper.snapshot(from: try SessionFile.decode(Data(json.utf8)))
        XCTAssertEqual(snapshot.presets[0].values.detail, DetailAdjustments())
    }
```

- [ ] **Step 2: 실패 확인**

Run: `cd apple && swift test --filter EditRecipeCodingTests`
Expected: 컴파일 실패 (`DetailAdjustments` 없음).

- [ ] **Step 3: 구현**

`apple/Sources/MellowShared/API/DetailAdjustments.swift`:

```swift
import Foundation

/// 하이라이트·그림자 −1…1, 선명도·비네팅 0…1.
public struct DetailAdjustments: Codable, Equatable, Sendable {
    public var highlights: Double = 0
    public var shadows: Double = 0
    public var sharpness: Double = 0
    public var vignette: Double = 0

    public init(highlights: Double = 0, shadows: Double = 0, sharpness: Double = 0, vignette: Double = 0) {
        self.highlights = highlights
        self.shadows = shadows
        self.sharpness = sharpness
        self.vignette = vignette
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        highlights = try container.decodeIfPresent(Double.self, forKey: .highlights) ?? 0
        shadows = try container.decodeIfPresent(Double.self, forKey: .shadows) ?? 0
        sharpness = try container.decodeIfPresent(Double.self, forKey: .sharpness) ?? 0
        vignette = try container.decodeIfPresent(Double.self, forKey: .vignette) ?? 0
    }

    public var isDefault: Bool { self == DetailAdjustments() }
    public var numericValues: [Double] { [highlights, shadows, sharpness, vignette] }
}
```

`apple/Sources/MellowShared/API/LookSelection.swift`:

```swift
import Foundation

/// 필터(룩) 선택. id가 nil이면 없음. intensity는 원본과 룩 결과의 혼합 비율.
public struct LookSelection: Codable, Equatable, Sendable {
    public var id: String?
    public var intensity: Double

    public init(id: String? = nil, intensity: Double = 1) {
        self.id = id
        self.intensity = intensity
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(String.self, forKey: .id)
        intensity = try container.decodeIfPresent(Double.self, forKey: .intensity) ?? 1
    }

    public var isDefault: Bool { self == LookSelection() }
}
```

`apple/Sources/MellowShared/API/GeometryAdjustments.swift`:

```swift
import Foundation

/// 반전 → 90° 회전 → 수평 보정 → 자르기 순서로 적용된다. crop은 그 앞 단계가 끝난 이미지 기준.
public struct GeometryAdjustments: Codable, Equatable, Sendable {
    public static let maxStraightenDegrees = 15.0

    public var flipHorizontal: Bool
    /// 시계 방향 90° 회전 횟수 0…3.
    public var quarterTurns: Int
    /// 양수면 시계 방향.
    public var straightenDegrees: Double
    public var crop: NormalizedRect?

    public init(flipHorizontal: Bool = false, quarterTurns: Int = 0, straightenDegrees: Double = 0, crop: NormalizedRect? = nil) {
        self.flipHorizontal = flipHorizontal
        self.quarterTurns = quarterTurns
        self.straightenDegrees = straightenDegrees
        self.crop = crop
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        flipHorizontal = try container.decodeIfPresent(Bool.self, forKey: .flipHorizontal) ?? false
        quarterTurns = try container.decodeIfPresent(Int.self, forKey: .quarterTurns) ?? 0
        straightenDegrees = try container.decodeIfPresent(Double.self, forKey: .straightenDegrees) ?? 0
        crop = try container.decodeIfPresent(NormalizedRect.self, forKey: .crop)
    }

    public var isIdentity: Bool { self == GeometryAdjustments() }

    /// 0…3으로 정규화한 회전 횟수.
    public var normalizedQuarterTurns: Int { ((quarterTurns % 4) + 4) % 4 }

    public var numericValues: [Double] {
        var values = [straightenDegrees]
        if let crop {
            values += [crop.x, crop.y, crop.width, crop.height]
        }
        return values
    }
}
```

`EditRecipe.swift`: 프로퍼티·init·CodingKeys·decode·encode·`allValuesFinite`를 확장한다.

```swift
    public var color = ColorAdjustments()
    public var portrait = PortraitAdjustments()
    public var detail = DetailAdjustments()
    public var look = LookSelection()
    public var geometry = GeometryAdjustments()
    public var operations: [LocalEdit] = []

    public init(
        color: ColorAdjustments = .init(), portrait: PortraitAdjustments = .init(), detail: DetailAdjustments = .init(),
        look: LookSelection = .init(), geometry: GeometryAdjustments = .init(), operations: [LocalEdit] = []
    ) { … 모두 대입 … }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case color
        case portrait
        case detail
        case look
        case geometry
        case operations
    }
    // decode: detail/look/geometry도 decodeIfPresent ?? .init()
    // encode: detail, look, geometry를 color·portrait 뒤에 encode

    public var allValuesFinite: Bool {
        let scalars = [
            color.exposure, color.contrast, color.saturation, color.warmth, portrait.skinSmoothing, portrait.faceSlim,
            look.intensity,
        ]
        let locals = operations.flatMap(\.numericValues)
        return (scalars + detail.numericValues + geometry.numericValues + locals).allSatisfy(\.isFinite)
    }
```

`Preset.swift`의 `PresetValues`:

```swift
public struct PresetValues: Codable, Equatable, Sendable {
    public var color: ColorAdjustments
    public var portrait: PortraitAdjustments
    public var detail: DetailAdjustments

    public init(color: ColorAdjustments = .init(), portrait: PortraitAdjustments = .init(), detail: DetailAdjustments = .init()) {
        self.color = color
        self.portrait = portrait
        self.detail = detail
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        color = try container.decodeIfPresent(ColorAdjustments.self, forKey: .color) ?? .init()
        portrait = try container.decodeIfPresent(PortraitAdjustments.self, forKey: .portrait) ?? .init()
        detail = try container.decodeIfPresent(DetailAdjustments.self, forKey: .detail) ?? .init()
    }
}
```

스키마 `edit-recipe.v2.schema.json`의 `properties`에 추가:

```json
    "detail": {
      "type": "object", "additionalProperties": false,
      "properties": {
        "highlights": { "type": "number", "default": 0, "minimum": -1, "maximum": 1 },
        "shadows": { "type": "number", "default": 0, "minimum": -1, "maximum": 1 },
        "sharpness": { "type": "number", "default": 0, "minimum": 0, "maximum": 1 },
        "vignette": { "type": "number", "default": 0, "minimum": 0, "maximum": 1 }
      }
    },
    "look": {
      "type": "object", "additionalProperties": false,
      "properties": {
        "id": { "type": ["string", "null"], "default": null, "description": "shared/looks/looks.v1.json의 룩 id" },
        "intensity": { "type": "number", "default": 1, "minimum": 0, "maximum": 1 }
      }
    },
    "geometry": {
      "type": "object", "additionalProperties": false,
      "description": "반전 → 90° 회전 → 수평 보정 → 자르기 순서. crop은 그 앞 단계가 끝난 이미지 기준 정규화 사각형.",
      "properties": {
        "flipHorizontal": { "type": "boolean", "default": false },
        "quarterTurns": { "type": "integer", "default": 0, "minimum": 0, "maximum": 3 },
        "straightenDegrees": { "type": "number", "default": 0, "minimum": -15, "maximum": 15 },
        "crop": {
          "type": ["object", "null"], "default": null, "additionalProperties": false,
          "required": ["x", "y", "width", "height"],
          "properties": {
            "x": { "type": "number", "minimum": 0, "maximum": 1 }, "y": { "type": "number", "minimum": 0, "maximum": 1 },
            "width": { "type": "number", "exclusiveMinimum": 0, "maximum": 1 }, "height": { "type": "number", "exclusiveMinimum": 0, "maximum": 1 }
          }
        }
      }
    },
```

`session-file.v2.schema.json`의 preset `values.properties`에 `"detail": { "$ref": "edit-recipe.v2.schema.json#/properties/detail" }`를 추가하고 `required`에 넣지 않는다. `shared/recipe-schema/README.md`의 필드 표와 UI 권장 범위 표에 세 구조를 추가한다(하이라이트·그림자 −1…1, 선명도·비네팅 0…1, 룩 강도 0…1, 수평 −15…15).

- [ ] **Step 4: 통과 확인**

Run: `cd apple && swift test` → PASS. `swift format lint --strict --recursive apple/Sources apple/Tests` → 출력 없음.

- [ ] **Step 5: 커밋**

```bash
git add apple/Sources/MellowShared apple/Tests/MellowSharedTests apple/Tests/MellowLibraryTests/SessionFileMigrationTests.swift shared/recipe-schema
git commit -m "feat(shared): 레시피에 디테일·룩·기하 조정을 추가하고 프리셋에 디테일 포함

schemaVersion 2를 유지한 추가 전용 확장이다. 기본값이 있어 기존 세션과
v1 마이그레이션 결과를 그대로 읽는다. 스키마와 README를 함께 갱신한다.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 3: GeometryTransform — 화면 좌표 ↔ 원본 좌표

**Files:**
- Create: `apple/Sources/MellowShared/API/GeometryTransform.swift`
- Test: `apple/Tests/MellowSharedTests/GeometryTransformTests.swift`

**Interfaces:**
- Consumes: `GeometryAdjustments`, `NormalizedPoint`, `NormalizedRect`.
- Produces: `GeometryTransform(geometry:sourceAspect:)`, `outputAspect`, `toOriginal(_:)`, `toOutput(_:) -> NormalizedPoint?`, `static func straightenScale(degrees:aspect:) -> Double`. Task 8의 `GeometryStage`와 Task 11의 캔버스 탭이 쓴다.

좌표 규약: 정규화, 원점 왼쪽 아래. 순서는 반전 → 회전 → 수평 → 자르기. 시계 방향 90° 회전 한 번은 `(x, y) → (y, 1 − x)`, 가로세로비는 역수가 된다. 수평 보정은 중심 기준으로 이미지를 시계 방향 θ만큼 돌리고 배율 `s = cos|θ| + sin|θ| × max(A, 1/A)`로 확대해 빈 모서리를 없앤다(A = 그 시점의 가로/세로).

- [ ] **Step 1: 실패하는 테스트 작성**

`apple/Tests/MellowSharedTests/GeometryTransformTests.swift`:

```swift
import XCTest

@testable import MellowShared

final class GeometryTransformTests: XCTestCase {
    private let tolerance = 1e-9

    private func assertEqual(_ a: NormalizedPoint, _ b: NormalizedPoint, _ message: String = "") {
        XCTAssertEqual(a.x, b.x, accuracy: tolerance, message)
        XCTAssertEqual(a.y, b.y, accuracy: tolerance, message)
    }

    func testIdentityMapsPointsToThemselves() {
        let transform = GeometryTransform(geometry: GeometryAdjustments(), sourceAspect: 1.5)
        let point = NormalizedPoint(x: 0.3, y: 0.8)
        assertEqual(transform.toOriginal(point), point)
        assertEqual(try XCTUnwrap(transform.toOutput(point)), point)
        XCTAssertEqual(transform.outputAspect, 1.5, accuracy: tolerance)
    }

    func testFlipMirrorsX() {
        let transform = GeometryTransform(geometry: GeometryAdjustments(flipHorizontal: true), sourceAspect: 1)
        assertEqual(transform.toOriginal(NormalizedPoint(x: 0.2, y: 0.7)), NormalizedPoint(x: 0.8, y: 0.7))
    }

    func testOneClockwiseTurnMapsTopLeftToTopRight() throws {
        let transform = GeometryTransform(geometry: GeometryAdjustments(quarterTurns: 1), sourceAspect: 2)
        // 원본의 왼쪽 위 (0,1)은 시계 방향으로 돌리면 오른쪽 위 (1,1).
        assertEqual(try XCTUnwrap(transform.toOutput(NormalizedPoint(x: 0, y: 1))), NormalizedPoint(x: 1, y: 1))
        assertEqual(transform.toOriginal(NormalizedPoint(x: 1, y: 1)), NormalizedPoint(x: 0, y: 1))
        XCTAssertEqual(transform.outputAspect, 0.5, accuracy: tolerance)
    }

    func testStraightenKeepsCenterAndAspectAndScalesCorners() throws {
        let geometry = GeometryAdjustments(straightenDegrees: 10)
        let transform = GeometryTransform(geometry: geometry, sourceAspect: 1.5)
        let center = NormalizedPoint(x: 0.5, y: 0.5)
        assertEqual(transform.toOriginal(center), center)
        XCTAssertEqual(transform.outputAspect, 1.5, accuracy: tolerance)
        // 출력 모서리는 원본 안쪽에서 온다 (빈 모서리가 없다는 뜻).
        let corner = transform.toOriginal(NormalizedPoint(x: 0, y: 0))
        XCTAssertGreaterThan(corner.x, 0)
        XCTAssertGreaterThan(corner.y, 0)
        let expectedScale = cos(10 * .pi / 180) + sin(10 * .pi / 180) * 1.5
        XCTAssertEqual(GeometryTransform.straightenScale(degrees: 10, aspect: 1.5), expectedScale, accuracy: tolerance)
    }

    func testCropRemapsAndRejectsPointsOutside() throws {
        let crop = NormalizedRect(x: 0.25, y: 0.5, width: 0.5, height: 0.5)
        let transform = GeometryTransform(geometry: GeometryAdjustments(crop: crop), sourceAspect: 1)
        assertEqual(transform.toOriginal(NormalizedPoint(x: 0, y: 0)), NormalizedPoint(x: 0.25, y: 0.5))
        assertEqual(transform.toOriginal(NormalizedPoint(x: 1, y: 1)), NormalizedPoint(x: 0.75, y: 1))
        XCTAssertNil(transform.toOutput(NormalizedPoint(x: 0.1, y: 0.1)))
        assertEqual(try XCTUnwrap(transform.toOutput(NormalizedPoint(x: 0.5, y: 0.75))), NormalizedPoint(x: 0.5, y: 0.5))
        XCTAssertEqual(transform.outputAspect, 1, accuracy: tolerance)
    }

    func testRoundTripAcrossCombinations() throws {
        let crops: [NormalizedRect?] = [nil, NormalizedRect(x: 0.1, y: 0.2, width: 0.6, height: 0.5)]
        let samples = [NormalizedPoint(x: 0.5, y: 0.5), NormalizedPoint(x: 0.37, y: 0.61), NormalizedPoint(x: 0.5, y: 0.52)]
        for flip in [false, true] {
            for turns in 0...3 {
                for degrees in [0.0, -7.5, 12] {
                    for crop in crops {
                        let geometry = GeometryAdjustments(
                            flipHorizontal: flip, quarterTurns: turns, straightenDegrees: degrees, crop: crop)
                        let transform = GeometryTransform(geometry: geometry, sourceAspect: 4.0 / 3.0)
                        for point in samples {
                            let original = transform.toOriginal(point)
                            let back = try XCTUnwrap(transform.toOutput(original), "\(geometry) \(point)")
                            assertEqual(back, point, "\(geometry)")
                        }
                    }
                }
            }
        }
    }
}
```

- [ ] **Step 2: 실패 확인**

Run: `cd apple && swift test --filter GeometryTransformTests`
Expected: 컴파일 실패.

- [ ] **Step 3: 구현**

`apple/Sources/MellowShared/API/GeometryTransform.swift`:

```swift
import Foundation

/// 출력(자른 화면) 정규화 좌표와 원본 정규화 좌표를 오간다. 순수 수학이라 모든 플랫폼이 같은 식을 쓴다.
/// 순서: 반전 → 시계 방향 90° 회전 → 수평 보정(중심 회전 + 확대) → 자르기.
public struct GeometryTransform: Sendable {
    private struct Aspect {
        var value: Double
    }

    public let geometry: GeometryAdjustments
    public let sourceAspect: Double
    /// 반전·회전 뒤의 가로/세로.
    public let turnedAspect: Double
    public let outputAspect: Double

    public init(geometry: GeometryAdjustments, sourceAspect: Double) {
        self.geometry = geometry
        self.sourceAspect = sourceAspect
        let turns = geometry.normalizedQuarterTurns
        turnedAspect = turns % 2 == 0 ? sourceAspect : 1 / sourceAspect
        if let crop = geometry.crop {
            outputAspect = turnedAspect * crop.width / crop.height
        } else {
            outputAspect = turnedAspect
        }
    }

    /// 빈 모서리가 생기지 않는 최소 확대 배율.
    public static func straightenScale(degrees: Double, aspect: Double) -> Double {
        let radians = abs(degrees) * .pi / 180
        return cos(radians) + sin(radians) * max(aspect, 1 / aspect)
    }

    public func toOriginal(_ point: NormalizedPoint) -> NormalizedPoint {
        var current = point
        if let crop = geometry.crop {
            current = NormalizedPoint(x: crop.x + current.x * crop.width, y: crop.y + current.y * crop.height)
        }
        current = unstraighten(current)
        for _ in 0..<geometry.normalizedQuarterTurns {
            current = Self.turnCounterclockwise(current)
        }
        if geometry.flipHorizontal {
            current = NormalizedPoint(x: 1 - current.x, y: current.y)
        }
        return current
    }

    /// 원본 좌표가 자른 영역 밖이면 nil.
    public func toOutput(_ point: NormalizedPoint) -> NormalizedPoint? {
        var current = point
        if geometry.flipHorizontal {
            current = NormalizedPoint(x: 1 - current.x, y: current.y)
        }
        for _ in 0..<geometry.normalizedQuarterTurns {
            current = Self.turnClockwise(current)
        }
        current = straighten(current)
        if let crop = geometry.crop {
            current = NormalizedPoint(x: (current.x - crop.x) / crop.width, y: (current.y - crop.y) / crop.height)
        }
        let range = -1e-9...(1 + 1e-9)
        guard range.contains(current.x), range.contains(current.y) else { return nil }
        return current
    }

    /// 시계 방향 90°: (x, y) → (y, 1 − x).
    private static func turnClockwise(_ point: NormalizedPoint) -> NormalizedPoint {
        NormalizedPoint(x: point.y, y: 1 - point.x)
    }

    private static func turnCounterclockwise(_ point: NormalizedPoint) -> NormalizedPoint {
        NormalizedPoint(x: 1 - point.y, y: point.x)
    }

    /// 수평 보정: 이미지를 시계 방향 θ만큼 돌리고 s배 확대. 가로세로비를 반영한 중심 좌표에서 계산한다.
    private func straighten(_ point: NormalizedPoint) -> NormalizedPoint {
        guard geometry.straightenDegrees != 0 else { return point }
        let radians = -geometry.straightenDegrees * .pi / 180
        let scale = Self.straightenScale(degrees: geometry.straightenDegrees, aspect: turnedAspect)
        let u = (point.x - 0.5) * turnedAspect
        let v = point.y - 0.5
        let ru = (u * cos(radians) - v * sin(radians)) * scale
        let rv = (u * sin(radians) + v * cos(radians)) * scale
        return NormalizedPoint(x: ru / turnedAspect + 0.5, y: rv + 0.5)
    }

    private func unstraighten(_ point: NormalizedPoint) -> NormalizedPoint {
        guard geometry.straightenDegrees != 0 else { return point }
        let radians = geometry.straightenDegrees * .pi / 180
        let scale = Self.straightenScale(degrees: geometry.straightenDegrees, aspect: turnedAspect)
        let u = (point.x - 0.5) * turnedAspect / scale
        let v = (point.y - 0.5) / scale
        let ru = u * cos(radians) - v * sin(radians)
        let rv = u * sin(radians) + v * cos(radians)
        return NormalizedPoint(x: ru / turnedAspect + 0.5, y: rv + 0.5)
    }
}
```

`private struct Aspect`는 쓰지 않으면 지운다(초안 잔재). 회전 방향 검증: `turnClockwise((0,1)) = (1, 1)` — 왼쪽 위가 오른쪽 위로 가므로 시계 방향이 맞다.

- [ ] **Step 4: 통과 확인**

Run: `cd apple && swift test --filter GeometryTransformTests` → 6 tests PASS. 전체 `swift test`와 lint도 PASS.

- [ ] **Step 5: 커밋**

```bash
git add apple/Sources/MellowShared/API/GeometryTransform.swift apple/Tests/MellowSharedTests/GeometryTransformTests.swift
git commit -m "feat(shared): 자르기·회전·수평 보정 좌표 변환을 순수 수학으로 추가

캔버스 탭과 렌더 단계가 같은 식을 쓰도록 플랫폼 독립 모듈에 둔다.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 4: 룩 카탈로그 — Look·LookCatalog와 shared/looks/looks.v1.json

**Files:**
- Create: `shared/looks/looks.v1.json`
- Create: `shared/looks/README.md`
- Create: `apple/Sources/MellowShared/API/Look.swift` (Look, LookCatalog)
- Create: `apple/MellowPhoto/Resources/looks.v1.json` (shared 파일의 복사본)
- Test: `apple/Tests/MellowSharedTests/LookCatalogTests.swift`
- Test: `apple/MellowPhotoTests/BundledLooksTests.swift`

**Interfaces:**
- Consumes: 없음.
- Produces: `Look`(`id`, `name`, `toneCurve: [[Double]]`, `saturation`, `contrast`, `warmth`, `tint`, `vignette`, `fade`), `LookCatalog(data:) throws`, `LookCatalog(looks:)`, `LookCatalog.empty`, `all: [Look]`, `look(id:) -> Look?`, `LookCatalog.builtInIDs`(10개 id 배열). Task 7·10·11이 쓴다.

- [ ] **Step 1: 룩 데이터 작성**

`shared/looks/looks.v1.json` (수치는 시작값이다. Task 7에서 데모 사진으로 보며 조정할 수 있으나 id·이름·순서는 고정):

```json
{
  "schemaVersion": 1,
  "looks": [
    { "id": "clear",   "name": "맑음",   "toneCurve": [[0,0],[0.25,0.23],[0.5,0.52],[0.75,0.78],[1,1]], "saturation": 1.05, "contrast": 1.03, "warmth": -0.05, "tint": 0,    "vignette": 0,    "fade": 0 },
    { "id": "film",    "name": "필름",   "toneCurve": [[0,0.03],[0.25,0.2],[0.5,0.5],[0.75,0.8],[1,0.97]], "saturation": 0.92, "contrast": 1.08, "warmth": 0.12, "tint": 0.02, "vignette": 0.15, "fade": 0.25 },
    { "id": "cozy",    "name": "포근",   "toneCurve": [[0,0.02],[0.25,0.26],[0.5,0.53],[0.75,0.77],[1,1]], "saturation": 0.95, "contrast": 0.98, "warmth": 0.3,  "tint": 0.04, "vignette": 0.05, "fade": 0.1 },
    { "id": "calm",    "name": "차분",   "toneCurve": [[0,0.02],[0.25,0.27],[0.5,0.5],[0.75,0.74],[1,0.98]], "saturation": 0.85, "contrast": 0.92, "warmth": -0.25, "tint": -0.03, "vignette": 0.08, "fade": 0.15 },
    { "id": "mono",    "name": "모노",   "toneCurve": [[0,0],[0.25,0.22],[0.5,0.5],[0.75,0.79],[1,1]], "saturation": 0,    "contrast": 1.1,  "warmth": 0,    "tint": 0,    "vignette": 0.12, "fade": 0.05 },
    { "id": "sepia",   "name": "세피아", "toneCurve": [[0,0.03],[0.25,0.24],[0.5,0.5],[0.75,0.77],[1,0.97]], "saturation": 0.2,  "contrast": 1.02, "warmth": 0.6,  "tint": 0.1,  "vignette": 0.15, "fade": 0.2 },
    { "id": "vintage", "name": "빈티지", "toneCurve": [[0,0.06],[0.25,0.24],[0.5,0.5],[0.75,0.76],[1,0.94]], "saturation": 0.75, "contrast": 0.95, "warmth": 0.15, "tint": 0.05, "vignette": 0.3,  "fade": 0.4 },
    { "id": "vivid",   "name": "선명",   "toneCurve": [[0,0],[0.25,0.21],[0.5,0.5],[0.75,0.8],[1,1]], "saturation": 1.25, "contrast": 1.12, "warmth": 0.05, "tint": 0,    "vignette": 0,    "fade": 0 },
    { "id": "pastel",  "name": "파스텔", "toneCurve": [[0,0.08],[0.25,0.32],[0.5,0.56],[0.75,0.8],[1,1]], "saturation": 0.8,  "contrast": 0.88, "warmth": 0.05, "tint": 0.03, "vignette": 0,    "fade": 0.2 },
    { "id": "night",   "name": "밤",     "toneCurve": [[0,0],[0.25,0.18],[0.5,0.44],[0.75,0.72],[1,0.95]], "saturation": 0.9,  "contrast": 1.1,  "warmth": -0.2, "tint": -0.05, "vignette": 0.35, "fade": 0.05 }
  ]
}
```

`shared/looks/README.md`: 필드 의미(톤 커브는 휘도 입력→출력 점 5개, x 오름차순, 0…1; saturation 0…2; contrast 0.5…1.5; warmth·tint −1…1(색감 단계와 같은 켈빈 환산, tint는 CITemperatureAndTint의 y); vignette 0…1; fade 0…1 = 커브 시작점을 `fade × 0.15`만큼 올림), 렌더 순서(톤 커브 → 색 조정 → 색온도·틴트 → 비네팅 → 강도 혼합), 다른 플랫폼이 같은 파일을 읽어야 한다는 규칙, 앱 번들 사본과 동일성 테스트 설명.

`apple/MellowPhoto/Resources/looks.v1.json`: `cp shared/looks/looks.v1.json apple/MellowPhoto/Resources/looks.v1.json`.

- [ ] **Step 2: 실패하는 테스트 작성**

`apple/Tests/MellowSharedTests/LookCatalogTests.swift`:

```swift
import XCTest

@testable import MellowShared

final class LookCatalogTests: XCTestCase {
    private func sharedLooksData() throws -> Data {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("shared/looks/looks.v1.json")
        return try Data(contentsOf: url)
    }

    func testSharedCatalogHasTenLooksInFixedOrder() throws {
        let catalog = try LookCatalog(data: sharedLooksData())
        XCTAssertEqual(catalog.all.map(\.id), LookCatalog.builtInIDs)
        XCTAssertEqual(LookCatalog.builtInIDs, ["clear", "film", "cozy", "calm", "mono", "sepia", "vintage", "vivid", "pastel", "night"])
        XCTAssertEqual(catalog.look(id: "film")?.name, "필름")
        XCTAssertNil(catalog.look(id: "nope"))
    }

    func testEveryLookHasValidToneCurveAndRanges() throws {
        for look in try LookCatalog(data: sharedLooksData()).all {
            XCTAssertEqual(look.toneCurve.count, 5, look.id)
            XCTAssertEqual(look.toneCurve.first?[0], 0, look.id)
            XCTAssertEqual(look.toneCurve.last?[0], 1, look.id)
            let xs = look.toneCurve.map { $0[0] }
            XCTAssertEqual(xs, xs.sorted(), "\(look.id) 톤 커브 x는 오름차순")
            XCTAssertTrue((0...2).contains(look.saturation), look.id)
            XCTAssertTrue((0.5...1.5).contains(look.contrast), look.id)
            XCTAssertTrue((-1...1).contains(look.warmth), look.id)
            XCTAssertTrue((0...1).contains(look.vignette), look.id)
            XCTAssertTrue((0...1).contains(look.fade), look.id)
        }
    }

    func testEmptyCatalogAndUnknownSchemaVersion() {
        XCTAssertTrue(LookCatalog.empty.all.isEmpty)
        XCTAssertThrowsError(try LookCatalog(data: Data(#"{"schemaVersion":9,"looks":[]}"#.utf8)))
    }
}
```

`apple/MellowPhotoTests/BundledLooksTests.swift`:

```swift
import MellowShared
import XCTest

@testable import Mellow_Photo

final class BundledLooksTests: XCTestCase {
    func testBundledLooksAreIdenticalToSharedFile() throws {
        let bundled = try XCTUnwrap(Bundle.main.url(forResource: "looks.v1", withExtension: "json"))
        let shared = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("shared/looks/looks.v1.json")
        XCTAssertEqual(try Data(contentsOf: bundled), try Data(contentsOf: shared))
        XCTAssertEqual(try LookCatalog(data: Data(contentsOf: bundled)).all.count, 10)
    }
}
```

(`apple/MellowPhotoTests/이 파일` → 세 단계 위가 저장소 루트.)

- [ ] **Step 3: 실패 확인**

Run: `cd apple && swift test --filter LookCatalogTests` → 컴파일 실패.

- [ ] **Step 4: 구현**

`apple/Sources/MellowShared/API/Look.swift`:

```swift
import Foundation

/// 필터 한 개의 파라미터. shared/looks/looks.v1.json과 같은 형식이며 모든 플랫폼이 같은 파일을 읽는다.
public struct Look: Codable, Equatable, Sendable, Identifiable {
    public var id: String
    public var name: String
    /// 휘도 입력→출력 점 5개. x 오름차순, 0…1.
    public var toneCurve: [[Double]]
    public var saturation: Double
    public var contrast: Double
    public var warmth: Double
    public var tint: Double
    public var vignette: Double
    /// 블랙 리프트. 커브 시작점을 fade × fadeLift만큼 올린다.
    public var fade: Double

    public static let fadeLift = 0.15

    public init(
        id: String, name: String, toneCurve: [[Double]], saturation: Double = 1, contrast: Double = 1,
        warmth: Double = 0, tint: Double = 0, vignette: Double = 0, fade: Double = 0
    ) {
        self.id = id
        self.name = name
        self.toneCurve = toneCurve
        self.saturation = saturation
        self.contrast = contrast
        self.warmth = warmth
        self.tint = tint
        self.vignette = vignette
        self.fade = fade
    }
}

public struct LookCatalog: Equatable, Sendable {
    public static let currentSchemaVersion = 1
    public static let builtInIDs = ["clear", "film", "cozy", "calm", "mono", "sepia", "vintage", "vivid", "pastel", "night"]
    public static let empty = LookCatalog(looks: [])

    private struct File: Decodable {
        var schemaVersion: Int
        var looks: [Look]
    }

    public let all: [Look]
    private let byID: [String: Look]

    public init(looks: [Look]) {
        all = looks
        byID = Dictionary(looks.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    }

    public init(data: Data) throws {
        let file = try JSONDecoder().decode(File.self, from: data)
        guard file.schemaVersion == Self.currentSchemaVersion else {
            throw DecodingError.dataCorrupted(
                DecodingError.Context(codingPath: [], debugDescription: "unsupported looks schemaVersion \(file.schemaVersion)"))
        }
        self.init(looks: file.looks)
    }

    public func look(id: String?) -> Look? {
        guard let id else { return nil }
        return byID[id]
    }
}
```

`Resources/looks.v1.json`은 XcodeGen이 `MellowPhoto/` 하위를 자동 수집하므로 `xcodegen generate`만 다시 실행하면 번들에 포함된다. 생성된 `.xcodeproj`를 커밋한다.

- [ ] **Step 5: 통과 확인**

Run: `cd apple && swift test --filter LookCatalogTests` → 3 PASS. `xcodegen generate` 후 `xcodebuild -project apple/MellowPhoto.xcodeproj -scheme MellowPhoto -destination 'platform=macOS' test 2>&1 | grep -E "Executed|TEST"` → 30 tests, 0 failures.

- [ ] **Step 6: 커밋**

```bash
git add shared/looks apple/Sources/MellowShared/API/Look.swift apple/Tests/MellowSharedTests/LookCatalogTests.swift apple/MellowPhoto/Resources/looks.v1.json apple/MellowPhotoTests/BundledLooksTests.swift apple/MellowPhoto.xcodeproj
git commit -m "feat(shared): 룩 10종을 파라미터 데이터로 정의하고 카탈로그 타입 추가

필터를 Apple 필터 이름이 아니라 shared/looks/의 JSON으로 두어
Android·Windows가 같은 룩을 재현할 수 있게 한다. 앱 번들 사본은
테스트로 동일성을 보장한다.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 5: 편집 규칙 — 새 EditChange와 applyAuto

**Files:**
- Create: `apple/Sources/MellowShared/API/AutoEnhanceSuggestion.swift`
- Modify: `apple/Sources/MellowEditing/API/EditChange.swift`
- Modify: `apple/Sources/MellowEditing/API/EditDocument.swift` (`set` 케이스 추가, `apply`에 detail, `applyFromBatch`에 detail, `applyAuto`)
- Test: `apple/Tests/MellowEditingTests/EditDocumentTests.swift`

**Interfaces:**
- Consumes: Task 2의 타입.
- Produces: `AutoEnhanceSuggestion(color:detail:portrait:)`(Shared), `EditChange` 새 케이스 `highlights(Double)`, `shadows(Double)`, `sharpness(Double)`, `vignette(Double)`, `lookID(String?)`, `lookIntensity(Double)`, `flipHorizontal(Bool)`, `quarterTurns(Int)`, `straightenDegrees(Double)`, `crop(NormalizedRect?)`; `EditDocument.applyAuto(_:)`.

- [ ] **Step 1: 실패하는 테스트 작성**

`EditDocumentTests.swift`에 추가:

```swift
    func testNewChangesAreNotLockedByLocalEdits() {
        var document = EditDocument()
        document.appendLocalEdit(.spot(RetouchSpot(x: 0.5, y: 0.4, sourceX: 0.4, sourceY: 0.4, radius: 0.02)))
        XCTAssertNil(document.set(.highlights(-0.5)))
        XCTAssertNil(document.set(.lookID("film")))
        XCTAssertNil(document.set(.lookIntensity(0.4)))
        XCTAssertNil(document.set(.quarterTurns(1)))
        XCTAssertNil(document.set(.crop(NormalizedRect(x: 0, y: 0, width: 0.5, height: 0.5))))
        XCTAssertEqual(document.recipe.detail.highlights, -0.5)
        XCTAssertEqual(document.recipe.look.id, "film")
        XCTAssertEqual(document.recipe.look.intensity, 0.4)
        XCTAssertEqual(document.recipe.geometry.quarterTurns, 1)
        XCTAssertEqual(document.recipe.geometry.crop?.width, 0.5)
    }

    func testQuarterTurnsWrapAndStraightenClamps() {
        var document = EditDocument()
        document.set(.quarterTurns(5))
        XCTAssertEqual(document.recipe.geometry.quarterTurns, 1)
        document.set(.straightenDegrees(40))
        XCTAssertEqual(document.recipe.geometry.straightenDegrees, GeometryAdjustments.maxStraightenDegrees)
    }

    func testPresetCarriesDetailButNotLookOrGeometry() {
        var document = EditDocument()
        document.set(.lookID("mono"))
        document.set(.quarterTurns(2))
        document.apply(PresetValues(detail: DetailAdjustments(vignette: 0.4)))
        XCTAssertEqual(document.recipe.detail.vignette, 0.4)
        XCTAssertEqual(document.recipe.look.id, "mono")
        XCTAssertEqual(document.recipe.geometry.quarterTurns, 2)
    }

    func testApplyAutoIsOneUndoStepAndKeepsLockedGeometry() {
        var document = EditDocument()
        document.set(.faceSlim(0.2))
        document.set(.targetFace(1))
        document.appendLocalEdit(.warp(WarpStroke(x: 0.5, y: 0.5, dx: 0.01, dy: 0, radius: 0.1)))
        document.set(.lookID("film"))
        let before = document.undoStack.count
        let suggestion = AutoEnhanceSuggestion(
            color: ColorAdjustments(exposure: 0.3, saturation: 1.08),
            detail: DetailAdjustments(highlights: -0.2),
            portrait: PortraitAdjustments(skinSmoothing: 0.3, faceSlim: 0.15))
        document.applyAuto(suggestion)
        XCTAssertEqual(document.undoStack.count, before + 1)
        XCTAssertEqual(document.recipe.color.exposure, 0.3)
        XCTAssertEqual(document.recipe.detail.highlights, -0.2)
        XCTAssertEqual(document.recipe.portrait.skinSmoothing, 0.3)
        XCTAssertEqual(document.recipe.portrait.faceSlim, 0.2, "잠긴 사진은 얼굴 형태 유지")
        XCTAssertEqual(document.recipe.portrait.targetFace, 1)
        XCTAssertEqual(document.recipe.look.id, "film", "자동 보정은 룩을 건드리지 않는다")
        XCTAssertEqual(document.recipe.operations.count, 1)
        document.undo()
        XCTAssertEqual(document.recipe.color.exposure, 0)
    }
```

- [ ] **Step 2: 실패 확인**

Run: `cd apple && swift test --filter EditDocumentTests` → 컴파일 실패.

- [ ] **Step 3: 구현**

`apple/Sources/MellowShared/API/AutoEnhanceSuggestion.swift`:

```swift
import Foundation

/// 자동 보정이 제안하는 슬라이더 값. 적용은 EditDocument가 규칙에 따라 한다.
public struct AutoEnhanceSuggestion: Equatable, Sendable {
    public var color: ColorAdjustments
    public var detail: DetailAdjustments
    public var portrait: PortraitAdjustments

    public init(color: ColorAdjustments, detail: DetailAdjustments, portrait: PortraitAdjustments) {
        self.color = color
        self.detail = detail
        self.portrait = portrait
    }
}
```

`EditChange.swift`:

```swift
import MellowShared

public enum EditChange: Equatable, Sendable {
    case exposure(Double)
    case contrast(Double)
    case saturation(Double)
    case warmth(Double)
    case skinSmoothing(Double)
    case faceSlim(Double)
    case targetFace(Int?)
    case highlights(Double)
    case shadows(Double)
    case sharpness(Double)
    case vignette(Double)
    case lookID(String?)
    case lookIntensity(Double)
    case flipHorizontal(Bool)
    case quarterTurns(Int)
    case straightenDegrees(Double)
    case crop(NormalizedRect?)

    /// 수동 편집이 있는 동안 바꿀 수 없는 변경. 자르기·회전은 원본 좌표를 바꾸지 않으므로 잠기지 않는다.
    public var affectsGeometry: Bool {
        switch self {
        case .faceSlim, .targetFace:
            return true
        default:
            return false
        }
    }
}
```

`EditDocument.set`의 switch에 추가:

```swift
        case .highlights(let value): updated.detail.highlights = value
        case .shadows(let value): updated.detail.shadows = value
        case .sharpness(let value): updated.detail.sharpness = value
        case .vignette(let value): updated.detail.vignette = value
        case .lookID(let id): updated.look.id = id
        case .lookIntensity(let value): updated.look.intensity = value
        case .flipHorizontal(let flag): updated.geometry.flipHorizontal = flag
        case .quarterTurns(let turns): updated.geometry.quarterTurns = ((turns % 4) + 4) % 4
        case .straightenDegrees(let degrees):
            let limit = GeometryAdjustments.maxStraightenDegrees
            updated.geometry.straightenDegrees = max(-limit, min(limit, degrees))
        case .crop(let rect): updated.geometry.crop = rect
```

`apply(_:)`와 `applyFromBatch(_:)`에 `recipe.detail = values.detail`를 추가한다(둘 다 `recipe.color = values.color` 옆). 그리고 `applyAuto`:

```swift
    /// 자동 보정 제안을 한 번의 체크포인트로 적용한다. 룩·기하·수동 편집은 건드리지 않는다.
    public mutating func applyAuto(_ suggestion: AutoEnhanceSuggestion) {
        checkpoint()
        var portrait = suggestion.portrait
        portrait.targetFace = recipe.portrait.targetFace
        if isGeometryLocked {
            portrait.faceSlim = recipe.portrait.faceSlim
        }
        recipe.color = suggestion.color
        recipe.detail = suggestion.detail
        recipe.portrait = portrait
    }
```

- [ ] **Step 4: 통과 확인**

Run: `cd apple && swift test` → PASS (Editing 15). lint PASS.

- [ ] **Step 5: 커밋**

```bash
git add apple/Sources/MellowShared/API/AutoEnhanceSuggestion.swift apple/Sources/MellowEditing apple/Tests/MellowEditingTests
git commit -m "feat(editing): 디테일·룩·기하 변경과 자동 보정 적용 규칙 추가

자르기·회전은 원본 좌표를 바꾸지 않으므로 수동 편집 잠금에 걸리지 않고,
자동 보정은 체크포인트 한 번으로 적용돼 ⌘Z 한 번에 되돌아간다.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 6: DetailStage — 하이라이트·그림자·선명도·비네팅

**Files:**
- Create: `apple/Sources/MellowRendering/Domain/DetailStage.swift`
- Modify: `apple/Sources/MellowRendering/API/RenderTuning.swift` (디테일 상수)
- Modify: `apple/Sources/MellowRendering/API/RenderPipeline.swift` (`standard`에 `DetailStage()` 추가)
- Test: `apple/Tests/MellowRenderingTests/DetailStageTests.swift`
- Modify: `apple/Tests/MellowRenderingTests/RenderPipelineTests.swift` (`testStageOrderMatters`의 이름 배열)

**Interfaces:**
- Consumes: `DetailAdjustments`(Task 2), `RenderContext`, `RenderStage`.
- Produces: `DetailStage`(internal, name `"detail"`), `RenderTuning.highlightReductionRange`(0.7), `highlightLiftAmount`(0.12), `sharpnessMax`(1.5), `vignetteRadius`(1.5). `RenderPipeline.standard` = `[SkinStage, FaceReshapeStage, LocalEditStage, ColorStage, DetailStage]`(Task 7·8이 뒤에 더 붙인다).

- [ ] **Step 1: 실패하는 테스트 작성**

`apple/Tests/MellowRenderingTests/DetailStageTests.swift`:

```swift
import CoreImage
import MellowShared
import XCTest

@testable import MellowRendering

final class DetailStageTests: XCTestCase {
    typealias Support = RenderingTestSupport

    /// 한 줄(y=0)의 RGBA 바이트에서 R 채널의 최대·최소.
    private func redRange(_ image: CIImage) throws -> (min: UInt8, max: UInt8) {
        let bytes = try Support.bytes(image)
        let reds = stride(from: 0, to: bytes.count, by: 4).map { bytes[$0] }
        return (reds.min()!, reds.max()!)
    }

    func testDefaultDetailIsIdentity() throws {
        let input = Support.gradient()
        XCTAssertEqual(try Support.bytes(Support.render(input, recipe: EditRecipe())), try Support.bytes(input))
    }

    func testNegativeHighlightsLowerTheBrightestPixels() throws {
        let input = Support.gradient()
        var recipe = EditRecipe()
        recipe.detail.highlights = -1
        let result = try Support.render(input, recipe: recipe)
        XCTAssertEqual(result.extent, input.extent)
        XCTAssertLessThan(try redRange(result).max, try redRange(input).max)
    }

    func testPositiveShadowsRaiseTheDarkestPixels() throws {
        let input = Support.gradient()
        var recipe = EditRecipe()
        recipe.detail.shadows = 1
        XCTAssertGreaterThan(try redRange(Support.render(input, recipe: recipe)).min, try redRange(input).min)
    }

    func testVignetteDarkensCornersMoreThanCenter() throws {
        let gray = Support.solid(CIColor(red: 0.6, green: 0.6, blue: 0.6), size: 128)
        var recipe = EditRecipe()
        recipe.detail.vignette = 1
        let bytes = try Support.bytes(Support.render(gray, recipe: recipe))
        let corner = bytes[0]
        let centerIndex = (64 * 128 + 64) * 4
        XCTAssertLessThan(corner, bytes[centerIndex])
    }

    func testSharpnessChangesBytesOnGradient() throws {
        let input = Support.gradient()
        var recipe = EditRecipe()
        recipe.detail.sharpness = 1
        XCTAssertNotEqual(try Support.bytes(Support.render(input, recipe: recipe)), try Support.bytes(input))
    }
}
```

`RenderPipelineTests.testStageOrderMatters`의 기대 이름 배열을 `["skin", "faceReshape", "localEdit", "color", "detail"]`로 바꾼다(Task 7·8에서 다시 늘린다).

- [ ] **Step 2: 실패 확인**

Run: `cd apple && swift test --filter DetailStageTests` → `testDefaultDetailIsIdentity`는 통과하고 나머지 4개는 실패(단계가 없어 항등).

- [ ] **Step 3: 구현**

`RenderTuning.swift`에 추가:

```swift
    /// highlights −1에서 CIHighlightShadowAdjust의 highlightAmount가 1 − 이 값까지 내려간다.
    public var highlightReductionRange: Double = 0.7
    /// highlights +1에서 밝은 구간 톤 커브를 이만큼 올린다.
    public var highlightLiftAmount: Double = 0.12
    public var sharpnessMax: Double = 1.5
    public var vignetteRadius: Double = 1.5
```

`apple/Sources/MellowRendering/Domain/DetailStage.swift`:

```swift
import CoreImage
import MellowShared

/// 하이라이트·그림자·선명도·비네팅. 값이 전부 기본이면 항등.
struct DetailStage: RenderStage {
    let name = "detail"

    func apply(_ image: CIImage, in context: RenderContext) throws -> CIImage {
        let detail = context.recipe.detail
        guard !detail.isDefault else { return image }
        let tuning = context.tuning
        var result = image
        if detail.highlights < 0 || detail.shadows != 0 {
            let highlightAmount = 1 + min(0, detail.highlights) * tuning.highlightReductionRange
            result = result.applyingFilter(
                "CIHighlightShadowAdjust",
                parameters: ["inputHighlightAmount": highlightAmount, "inputShadowAmount": detail.shadows, "inputRadius": 0])
        }
        if detail.highlights > 0 {
            let lift = detail.highlights * tuning.highlightLiftAmount
            result = result.applyingFilter(
                "CIToneCurve",
                parameters: [
                    "inputPoint0": CIVector(x: 0, y: 0), "inputPoint1": CIVector(x: 0.25, y: 0.25),
                    "inputPoint2": CIVector(x: 0.5, y: 0.5), "inputPoint3": CIVector(x: 0.75, y: min(1, 0.75 + lift)),
                    "inputPoint4": CIVector(x: 1, y: 1),
                ])
        }
        if detail.sharpness > 0 {
            result = result.applyingFilter(
                "CISharpenLuminance", parameters: ["inputSharpness": detail.sharpness * tuning.sharpnessMax])
        }
        if detail.vignette > 0 {
            result = result.applyingFilter(
                "CIVignette", parameters: ["inputIntensity": detail.vignette, "inputRadius": tuning.vignetteRadius])
        }
        return result.cropped(to: context.extent)
    }
}
```

`RenderPipeline.standard`: `[SkinStage(), FaceReshapeStage(), LocalEditStage(), ColorStage(), DetailStage()]`.

- [ ] **Step 4: 통과 확인**

Run: `cd apple && swift test --filter 'DetailStageTests|RenderPipelineTests'` → PASS. 전체 `swift test` PASS, lint PASS.

- [ ] **Step 5: 커밋**

```bash
git add apple/Sources/MellowRendering apple/Tests/MellowRenderingTests
git commit -m "feat(rendering): 하이라이트·그림자·선명도·비네팅 디테일 단계 추가

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 7: LookStage — 룩 렌더와 강도 혼합

**Files:**
- Create: `apple/Sources/MellowRendering/Domain/LookStage.swift`
- Modify: `apple/Sources/MellowRendering/API/RenderStage.swift` (`RenderContext.lookCatalog`, `skipsCrop`)
- Modify: `apple/Sources/MellowRendering/API/RenderTuning.swift` (`lookTintRange`)
- Modify: `apple/Sources/MellowRendering/API/RenderPipeline.swift` (`standard`에 `LookStage()`)
- Modify: `apple/Sources/MellowRendering/API/PhotoPipeline.swift` (`init(analyzer:tuning:lookCatalog:)`, 두 `RenderContext` 생성에 카탈로그 전달)
- Modify: `apple/Tests/MellowRenderingTests/RenderingTestSupport.swift` (`sharedLookCatalog()`, `render(_:recipe:faces:catalog:)`)
- Test: `apple/Tests/MellowRenderingTests/LookStageTests.swift`
- Modify: `apple/Tests/MellowRenderingTests/RenderPipelineTests.swift` (이름 배열에 `"look"`)

**Interfaces:**
- Consumes: `Look`, `LookCatalog`(Task 4), `LookSelection`(Task 2).
- Produces: `RenderContext.init(extent:recipe:faces:tuning:lookCatalog:skipsCrop:)`(둘 다 기본값 `.empty`/`false`), `RenderContext.lookCatalog`, `RenderContext.skipsCrop`, `PhotoPipeline.init(analyzer:tuning:lookCatalog: LookCatalog = .empty)`, `LookStage`(name `"look"`), `RenderTuning.lookTintRange`(60).

- [ ] **Step 1: 테스트 지원과 실패하는 테스트**

`RenderingTestSupport.swift`에 추가:

```swift
    static func sharedLookCatalog() throws -> LookCatalog {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("shared/looks/looks.v1.json")
        return try LookCatalog(data: Data(contentsOf: url))
    }

    static func render(_ image: CIImage, recipe: EditRecipe, faces: [FaceGeometry] = [], catalog: LookCatalog) throws -> CIImage {
        let context = RenderContext(
            extent: image.extent, recipe: recipe, faces: faces, tuning: RenderTuning(), lookCatalog: catalog)
        return try RenderPipeline.standard.render(image, context: context)
    }
```

`apple/Tests/MellowRenderingTests/LookStageTests.swift`:

```swift
import CoreImage
import MellowShared
import XCTest

@testable import MellowRendering

final class LookStageTests: XCTestCase {
    typealias Support = RenderingTestSupport

    func testIntensityZeroIsIdentityAndOneIsNot() throws {
        let catalog = try Support.sharedLookCatalog()
        let input = Support.gradient()
        var recipe = EditRecipe()
        recipe.look = LookSelection(id: "film", intensity: 0)
        XCTAssertEqual(try Support.bytes(Support.render(input, recipe: recipe, catalog: catalog)), try Support.bytes(input))
        recipe.look.intensity = 1
        XCTAssertNotEqual(try Support.bytes(Support.render(input, recipe: recipe, catalog: catalog)), try Support.bytes(input))
    }

    func testEveryBuiltInLookRendersAndChangesTheImage() throws {
        let catalog = try Support.sharedLookCatalog()
        let input = Support.gradient()
        let original = try Support.bytes(input)
        for id in LookCatalog.builtInIDs {
            var recipe = EditRecipe()
            recipe.look = LookSelection(id: id, intensity: 1)
            let result = try Support.render(input, recipe: recipe, catalog: catalog)
            XCTAssertEqual(result.extent, input.extent, id)
            XCTAssertNotEqual(try Support.bytes(result), original, "\(id)는 원본과 달라야 한다")
        }
    }

    func testUnknownLookOrEmptyCatalogIsIdentity() throws {
        let input = Support.gradient()
        var recipe = EditRecipe()
        recipe.look = LookSelection(id: "glitter", intensity: 1)
        XCTAssertEqual(try Support.bytes(Support.render(input, recipe: recipe, catalog: try Support.sharedLookCatalog())), try Support.bytes(input))
        recipe.look.id = "film"
        XCTAssertEqual(try Support.bytes(Support.render(input, recipe: recipe, catalog: .empty)), try Support.bytes(input))
    }

    func testHalfIntensityLiesBetweenOriginalAndFullLook() throws {
        let catalog = try Support.sharedLookCatalog()
        let gray = Support.solid(CIColor(red: 0.5, green: 0.5, blue: 0.5), size: 8)
        func red(_ intensity: Double) throws -> Int {
            var recipe = EditRecipe()
            recipe.look = LookSelection(id: "sepia", intensity: intensity)
            return Int(try Support.bytes(Support.render(gray, recipe: recipe, catalog: catalog))[0])
        }
        let zero = try red(0)
        let half = try red(0.5)
        let full = try red(1)
        XCTAssertNotEqual(zero, full)
        XCTAssertTrue((min(zero, full)...max(zero, full)).contains(half))
    }
}
```

`RenderPipelineTests.testStageOrderMatters`의 이름 배열을 `[…, "color", "detail", "look"]`로.

- [ ] **Step 2: 실패 확인**

Run: `cd apple && swift test --filter LookStageTests` → 컴파일 실패(`lookCatalog:` 인자 없음).

- [ ] **Step 3: 구현**

`RenderStage.swift`의 `RenderContext`:

```swift
public struct RenderContext: Sendable {
    public let extent: CGRect
    public let recipe: EditRecipe
    public let faces: [FaceGeometry]
    public let targetFaces: [FaceGeometry]
    public let tuning: RenderTuning
    public let lookCatalog: LookCatalog
    /// 자르기 도구 화면용. 기하 단계가 자르기만 건너뛴다.
    public let skipsCrop: Bool

    public init(
        extent: CGRect, recipe: EditRecipe, faces: [FaceGeometry], tuning: RenderTuning,
        lookCatalog: LookCatalog = .empty, skipsCrop: Bool = false
    ) {
        … 기존 대입 + lookCatalog, skipsCrop …
    }
```

`RenderTuning.swift`에 `public var lookTintRange: Double = 60`(tint ±1 → CITemperatureAndTint y ±60).

`apple/Sources/MellowRendering/Domain/LookStage.swift`:

```swift
import CoreImage
import MellowShared

/// 룩 파라미터를 Core Image 기본 필터로 조립하고 강도만큼 원본과 섞는다.
struct LookStage: RenderStage {
    let name = "look"

    func apply(_ image: CIImage, in context: RenderContext) throws -> CIImage {
        let selection = context.recipe.look
        guard selection.intensity > 0, let look = context.lookCatalog.look(id: selection.id) else { return image }
        let styled = Self.styled(image, look: look, tuning: context.tuning).cropped(to: context.extent)
        if selection.intensity >= 1 {
            return styled
        }
        return styled.applyingFilter(
            "CIMix", parameters: [kCIInputBackgroundImageKey: image, "inputAmount": selection.intensity]
        ).cropped(to: context.extent)
    }

    /// 강도 1의 룩 결과. 룩 썸네일도 이 함수를 쓴다.
    static func styled(_ image: CIImage, look: Look, tuning: RenderTuning) -> CIImage {
        var result = image
        if let curve = Self.curveParameters(look) {
            result = result.applyingFilter("CIToneCurve", parameters: curve)
        }
        if look.saturation != 1 || look.contrast != 1 {
            result = result.applyingFilter(
                "CIColorControls", parameters: [kCIInputSaturationKey: look.saturation, kCIInputContrastKey: look.contrast])
        }
        if look.warmth != 0 || look.tint != 0 {
            let warmth = max(-1, min(1, look.warmth))
            result = result.applyingFilter(
                "CITemperatureAndTint",
                parameters: [
                    "inputNeutral": CIVector(x: tuning.neutralKelvin, y: 0),
                    "inputTargetNeutral": CIVector(
                        x: tuning.neutralKelvin - warmth * tuning.warmthKelvinRange, y: look.tint * tuning.lookTintRange),
                ])
        }
        if look.vignette > 0 {
            result = result.applyingFilter(
                "CIVignette", parameters: ["inputIntensity": look.vignette, "inputRadius": tuning.vignetteRadius])
        }
        return result
    }

    /// 점 5개짜리 커브. 첫 점은 fade만큼 올린다. 점이 5개가 아니면 커브를 건너뛴다.
    private static func curveParameters(_ look: Look) -> [String: Any]? {
        guard look.toneCurve.count == 5, look.toneCurve.allSatisfy({ $0.count == 2 }) else { return nil }
        var parameters: [String: Any] = [:]
        for (index, point) in look.toneCurve.enumerated() {
            var y = point[1]
            if index == 0 {
                y = min(1, y + look.fade * Look.fadeLift)
            }
            parameters["inputPoint\(index)"] = CIVector(x: point[0], y: y)
        }
        return parameters
    }
}
```

`RenderPipeline.standard`: `[…, DetailStage(), LookStage()]`.

`PhotoPipeline.swift`: `private let lookCatalog: LookCatalog`, `public init(analyzer: any FaceAnalyzer, tuning: RenderTuning, lookCatalog: LookCatalog = .empty)`, `preview`와 `render(url:…)`의 `RenderContext(…, tuning: tuning, lookCatalog: lookCatalog)`.

- [ ] **Step 4: 통과 확인**

Run: `cd apple && swift test` → PASS(LookStageTests 4). 데모 인물 사진으로 10종을 눈으로 확인하는 것은 Task 12 실기동에서 한다. lint PASS.

- [ ] **Step 5: 커밋**

```bash
git add apple/Sources/MellowRendering apple/Tests/MellowRenderingTests
git commit -m "feat(rendering): 룩 단계 추가 — 데이터 정의 필터를 기본 필터로 조립하고 강도로 혼합

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 8: GeometryStage — 반전·회전·수평·자르기 (파이프라인 마지막)

**Files:**
- Create: `apple/Sources/MellowRendering/Domain/GeometryStage.swift`
- Modify: `apple/Sources/MellowRendering/API/RenderPipeline.swift` (`standard`에 `GeometryStage()`, 마지막 `cropped(to:)` 제거)
- Modify: `apple/Sources/MellowRendering/API/PhotoPipeline.swift` (`preview(_:recipe:showsUncropped:)`)
- Test: `apple/Tests/MellowRenderingTests/GeometryStageTests.swift`
- Modify: `apple/Tests/MellowRenderingTests/RenderPipelineTests.swift` (이름 배열 7개), `PhotoPipelineTests.swift` (`showsUncropped` 테스트)

**Interfaces:**
- Consumes: `GeometryAdjustments`, `GeometryTransform.straightenScale`(Task 3), `RenderContext.skipsCrop`(Task 7).
- Produces: `GeometryStage`(name `"geometry"`), `PhotoPipeline.preview(_ id: PhotoID, recipe: EditRecipe, showsUncropped: Bool = false)`. 파이프라인 결과 extent는 기하 결과이며 원점 0.

- [ ] **Step 1: 실패하는 테스트 작성**

`apple/Tests/MellowRenderingTests/GeometryStageTests.swift`:

```swift
import CoreImage
import MellowShared
import XCTest

@testable import MellowRendering

final class GeometryStageTests: XCTestCase {
    typealias Support = RenderingTestSupport

    private func render(_ geometry: GeometryAdjustments, skipsCrop: Bool = false, input: CIImage = RenderingTestSupport.gradient()) throws -> CIImage {
        var recipe = EditRecipe()
        recipe.geometry = geometry
        let context = RenderContext(
            extent: input.extent, recipe: recipe, faces: [], tuning: RenderTuning(), skipsCrop: skipsCrop)
        return try RenderPipeline.standard.render(input, context: context)
    }

    func testIdentityKeepsExtentAndBytes() throws {
        let input = Support.gradient()
        let result = try render(GeometryAdjustments(), input: input)
        XCTAssertEqual(result.extent, input.extent)
        XCTAssertEqual(try Support.bytes(result), try Support.bytes(input))
    }

    func testSquareCropOf128By80Is80By80AtOrigin() throws {
        let side = 80.0 / 128.0
        let crop = NormalizedRect(x: (1 - side) / 2, y: 0, width: side, height: 1)
        let result = try render(GeometryAdjustments(crop: crop))
        XCTAssertEqual(result.extent, CGRect(x: 0, y: 0, width: 80, height: 80))
    }

    func testQuarterTurnSwapsWidthAndHeight() throws {
        let result = try render(GeometryAdjustments(quarterTurns: 1))
        XCTAssertEqual(result.extent, CGRect(x: 0, y: 0, width: 80, height: 128))
        let threeTurns = try render(GeometryAdjustments(quarterTurns: 3))
        XCTAssertEqual(threeTurns.extent, CGRect(x: 0, y: 0, width: 80, height: 128))
        XCTAssertNotEqual(try Support.bytes(result), try Support.bytes(threeTurns), "1회와 3회 회전은 다른 방향")
    }

    func testFlipSwapsLeftAndRightColumns() throws {
        let input = Support.gradient()
        let original = try Support.bytes(input)
        let flipped = try Support.bytes(render(GeometryAdjustments(flipHorizontal: true), input: input))
        // 첫 행의 첫 픽셀 R과 마지막 픽셀 R이 서로 바뀐다.
        let lastPixel = (128 - 1) * 4
        XCTAssertEqual(Int(flipped[0]), Int(original[lastPixel]), accuracy: 2)
        XCTAssertEqual(Int(flipped[lastPixel]), Int(original[0]), accuracy: 2)
    }

    func testStraightenKeepsExtentAndLeavesNoTransparentCorner() throws {
        let gray = Support.solid(CIColor(red: 0.5, green: 0.5, blue: 0.5), size: 128)
        let result = try render(GeometryAdjustments(straightenDegrees: 5), input: gray)
        XCTAssertEqual(result.extent, gray.extent)
        let bytes = try Support.bytes(result)
        for cornerIndex in [0, (128 - 1) * 4, (128 * 127) * 4, (128 * 128 - 1) * 4] {
            XCTAssertEqual(bytes[cornerIndex + 3], 255, "모서리 알파가 불투명해야 한다")
        }
    }

    func testSkipsCropLeavesOnlyCropOut() throws {
        let crop = NormalizedRect(x: 0.25, y: 0.25, width: 0.5, height: 0.5)
        let geometry = GeometryAdjustments(flipHorizontal: true, quarterTurns: 1, crop: crop)
        let cropped = try render(geometry)
        let uncropped = try render(geometry, skipsCrop: true)
        XCTAssertEqual(uncropped.extent, CGRect(x: 0, y: 0, width: 80, height: 128))
        XCTAssertEqual(cropped.extent, CGRect(x: 0, y: 0, width: 40, height: 64))
    }

    func testGeometryOutputAspectMatchesTransform() throws {
        let crop = NormalizedRect(x: 0.1, y: 0.2, width: 0.6, height: 0.5)
        let geometry = GeometryAdjustments(quarterTurns: 1, straightenDegrees: 10, crop: crop)
        let result = try render(geometry)
        let transform = GeometryTransform(geometry: geometry, sourceAspect: 128.0 / 80.0)
        XCTAssertEqual(Double(result.extent.width / result.extent.height), transform.outputAspect, accuracy: 0.02)
    }
}
```

`PhotoPipelineTests.swift`에 추가:

```swift
    func testPreviewShowsUncroppedWhenRequested() async throws {
        let url = try writeSolidPNG()
        let id = PhotoID()
        let pipeline = PhotoPipeline(analyzer: StubFaceAnalyzer(result: .success([])), tuning: RenderTuning())
        _ = try await pipeline.prepare(id, at: url)
        var recipe = EditRecipe()
        recipe.geometry.crop = NormalizedRect(x: 0, y: 0, width: 0.5, height: 0.5)
        XCTAssertEqual(try await pipeline.preview(id, recipe: recipe).width, 128)
        XCTAssertEqual(try await pipeline.preview(id, recipe: recipe, showsUncropped: true).width, 256)
    }
```

`RenderPipelineTests.testStageOrderMatters`의 이름 배열을 7개 전체로.

- [ ] **Step 2: 실패 확인**

Run: `cd apple && swift test --filter GeometryStageTests` → 항등 외 실패.

- [ ] **Step 3: 구현**

`apple/Sources/MellowRendering/Domain/GeometryStage.swift`:

```swift
import CoreImage
import MellowShared

/// 반전 → 시계 방향 90° 회전 → 수평 보정(중심 회전 + 확대) → 자르기. 결과 extent는 원점 0.
struct GeometryStage: RenderStage {
    let name = "geometry"

    func apply(_ image: CIImage, in context: RenderContext) throws -> CIImage {
        let geometry = context.recipe.geometry
        guard !geometry.isIdentity else { return image }
        var result = image
        var extent = context.extent
        if geometry.flipHorizontal {
            let flip = CGAffineTransform(a: -1, b: 0, c: 0, d: 1, tx: extent.minX + extent.maxX, ty: 0)
            result = result.transformed(by: flip).cropped(to: extent)
        }
        for _ in 0..<geometry.normalizedQuarterTurns {
            // (x, y) → (y, w − x): 시계 방향 90°.
            let turn = CGAffineTransform(a: 0, b: -1, c: 1, d: 0, tx: -extent.minY, ty: extent.maxX)
            result = result.transformed(by: turn)
            extent = CGRect(x: 0, y: 0, width: extent.height, height: extent.width)
            result = Self.moveToOrigin(result).cropped(to: extent)
        }
        if geometry.straightenDegrees != 0 {
            let radians = -geometry.straightenDegrees * .pi / 180
            let scale = GeometryTransform.straightenScale(degrees: geometry.straightenDegrees, aspect: extent.width / extent.height)
            let center = CGPoint(x: extent.midX, y: extent.midY)
            let transform = CGAffineTransform(translationX: center.x, y: center.y)
                .rotated(by: radians)
                .scaledBy(x: scale, y: scale)
                .translatedBy(x: -center.x, y: -center.y)
            result = result.transformed(by: transform).cropped(to: extent)
        }
        if let crop = geometry.crop, !context.skipsCrop {
            let pixelRect = CGRect(
                x: extent.minX + crop.x * extent.width, y: extent.minY + crop.y * extent.height,
                width: crop.width * extent.width, height: crop.height * extent.height
            ).integral.intersection(extent)
            guard !pixelRect.isEmpty else { throw MellowError.invalidRecipeValues }
            result = Self.moveToOrigin(result.cropped(to: pixelRect))
        }
        return result
    }

    private static func moveToOrigin(_ image: CIImage) -> CIImage {
        image.transformed(by: CGAffineTransform(translationX: -image.extent.minX, y: -image.extent.minY))
    }
}
```

회전 변환 검증: extent 원점이 0일 때 `tx = 0, ty = w`가 되어 `(x, y) → (y, w − x)`다. 회전 뒤 `moveToOrigin`으로 음수 원점을 없앤다.

`RenderPipeline.render`: 마지막 줄을 `return result`로 바꾼다(각 단계가 자기 extent로 자른다). `standard`에 `GeometryStage()`를 마지막에 추가.

`PhotoPipeline.preview`:

```swift
    public func preview(_ id: PhotoID, recipe: EditRecipe, showsUncropped: Bool = false) throws -> CGImage {
        guard let entry = entries[id], let image = cache.image(for: id) else {
            throw MellowError.cannotCreatePreview
        }
        let context = RenderContext(
            extent: image.extent, recipe: recipe, faces: entry.faces, tuning: tuning, lookCatalog: lookCatalog,
            skipsCrop: showsUncropped)
        return try renderer.makeCGImage(pipeline.render(image, context: context))
    }
```

- [ ] **Step 4: 통과 확인**

Run: `cd apple && swift test` → PASS(기존 회귀 포함). `testStraighten…`의 알파가 255가 아니면 `scale`을 `1.001`배 더 곱해 경계 보간을 덮고 그 이유를 보고서에 적는다. lint PASS.

- [ ] **Step 5: 커밋**

```bash
git add apple/Sources/MellowRendering apple/Tests/MellowRenderingTests
git commit -m "feat(rendering): 반전·회전·수평·자르기 기하 단계를 파이프라인 마지막에 추가

얼굴·수동 편집 좌표는 원본 기준을 유지하고 출력 크기만 바뀐다.
자르기 도구 화면을 위해 자르기만 건너뛰는 미리보기를 제공한다.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 9: AutoEnhancer — 히스토그램 기반 슬라이더 값 제안

**Files:**
- Create: `apple/Sources/MellowRendering/API/AutoEnhancer.swift`
- Modify: `apple/Sources/MellowRendering/API/Renderer.swift` (`readPixels(_:)`)
- Modify: `apple/Sources/MellowRendering/API/RenderTuning.swift` (auto 상수)
- Modify: `apple/Sources/MellowRendering/API/PhotoPipeline.swift` (`autoEnhanceSuggestion(_:hasFaces:)`)
- Test: `apple/Tests/MellowRenderingTests/AutoEnhancerTests.swift`, `PhotoPipelineTests.swift` (추가)

**Interfaces:**
- Consumes: `AutoEnhanceSuggestion`(Task 5), `Renderer`.
- Produces: `Renderer.readPixels(_ image: CIImage) throws -> [Float]`(RGBAf, 행 우선, 좌하단부터), `AutoEnhancer(tuning:renderer:)`, `AutoEnhancer.suggestion(for:hasFaces:) throws -> AutoEnhanceSuggestion`, `PhotoPipeline.autoEnhanceSuggestion(_ id: PhotoID, hasFaces: Bool) throws -> AutoEnhanceSuggestion`(캐시된 미리보기 기준; 캐시 없으면 `cannotCreatePreview`), `RenderTuning` auto 상수 9개.

- [ ] **Step 1: 실패하는 테스트 작성**

`apple/Tests/MellowRenderingTests/AutoEnhancerTests.swift`:

```swift
import CoreImage
import MellowShared
import XCTest

@testable import MellowRendering

final class AutoEnhancerTests: XCTestCase {
    typealias Support = RenderingTestSupport
    private let enhancer = AutoEnhancer(tuning: RenderTuning(), renderer: RenderingTestSupport.renderer)

    func testDarkImageGetsPositiveExposureAndBrightImageNegative() throws {
        let dark = Support.solid(CIColor(red: 0.12, green: 0.12, blue: 0.12), size: 64)
        let bright = Support.solid(CIColor(red: 0.9, green: 0.9, blue: 0.9), size: 64)
        XCTAssertGreaterThan(try enhancer.suggestion(for: dark, hasFaces: false).color.exposure, 0)
        XCTAssertLessThan(try enhancer.suggestion(for: bright, hasFaces: false).color.exposure, 0)
    }

    func testSolidImageOnlyAdjustsExposure() throws {
        let gray = Support.solid(CIColor(red: 0.3, green: 0.3, blue: 0.3), size: 64)
        let suggestion = try enhancer.suggestion(for: gray, hasFaces: false)
        XCTAssertEqual(suggestion.detail, DetailAdjustments())
        XCTAssertEqual(suggestion.color.warmth, 0)
        XCTAssertEqual(suggestion.color.saturation, 1)
        XCTAssertEqual(suggestion.color.contrast, 1)
    }

    func testGradientGetsHighlightAndShadowRecoveryWithinRanges() throws {
        let suggestion = try enhancer.suggestion(for: Support.gradient(), hasFaces: false)
        XCTAssertTrue((-1...0).contains(suggestion.detail.highlights))
        XCTAssertTrue((0...1).contains(suggestion.detail.shadows))
        XCTAssertEqual(suggestion.color.saturation, RenderTuning().autoSaturation)
        XCTAssertEqual(suggestion.color.contrast, RenderTuning().autoContrast)
        XCTAssertTrue((-1...1).contains(suggestion.color.exposure))
    }

    func testWarmCastIsNeutralizedTowardCool() throws {
        let warm = Support.solid(CIColor(red: 0.7, green: 0.5, blue: 0.3), size: 64)
        let suggestion = try enhancer.suggestion(for: warm, hasFaces: false)
        XCTAssertLessThan(suggestion.color.warmth, 0, "붉은 캐스트는 차갑게 보정")
        XCTAssertGreaterThanOrEqual(suggestion.color.warmth, -RenderTuning().autoWarmthLimit)
    }

    func testFacesAddPortraitValues() throws {
        let image = Support.gradient()
        XCTAssertEqual(try enhancer.suggestion(for: image, hasFaces: false).portrait, PortraitAdjustments())
        let withFaces = try enhancer.suggestion(for: image, hasFaces: true).portrait
        XCTAssertEqual(withFaces.skinSmoothing, RenderTuning().autoSkinSmoothing)
        XCTAssertEqual(withFaces.faceSlim, RenderTuning().autoFaceSlim)
        XCTAssertNil(withFaces.targetFace)
    }

    func testSuggestionDoesNotDependOnCurrentRecipe() throws {
        let image = Support.gradient()
        XCTAssertEqual(try enhancer.suggestion(for: image, hasFaces: true), try enhancer.suggestion(for: image, hasFaces: true))
    }
}
```

`PhotoPipelineTests.swift`에 추가:

```swift
    func testAutoEnhanceSuggestionUsesCachedPreview() async throws {
        let url = try writeSolidPNG()
        let id = PhotoID()
        let pipeline = PhotoPipeline(analyzer: StubFaceAnalyzer(result: .success([])), tuning: RenderTuning())
        _ = try await pipeline.prepare(id, at: url)
        let suggestion = try await pipeline.autoEnhanceSuggestion(id, hasFaces: false)
        XCTAssertTrue(suggestion.color.exposure.isFinite)
        await pipeline.evict(id)
        do {
            _ = try await pipeline.autoEnhanceSuggestion(id, hasFaces: false)
            XCTFail("캐시가 없으면 제안할 수 없다")
        } catch {
            XCTAssertEqual(error as? MellowError, .cannotCreatePreview)
        }
    }
```

- [ ] **Step 2: 실패 확인**

Run: `cd apple && swift test --filter AutoEnhancerTests` → 컴파일 실패.

- [ ] **Step 3: 구현**

`RenderTuning.swift`에 추가:

```swift
    public var autoTargetLuminance: Double = 0.45
    public var autoWarmthGain: Double = 0.5
    public var autoWarmthLimit: Double = 0.3
    public var autoHighlightThreshold: Double = 0.97
    public var autoShadowThreshold: Double = 0.03
    public var autoSaturation: Double = 1.08
    public var autoContrast: Double = 1.04
    public var autoSkinSmoothing: Double = 0.3
    public var autoFaceSlim: Double = 0.15
    /// 상·하위 백분위 차이가 이보다 작으면 단색으로 보고 노출만 조정한다.
    public var autoFlatRange: Double = 0.05
    public var autoExposureLimit: Double = 1
    public var autoHistogramBins: Int = 64
```

`Renderer.swift`에 추가:

```swift
    /// RGBAf로 읽는다. 행 우선, 왼쪽 아래 픽셀부터. 히스토그램·평균처럼 작은 이미지에만 쓴다.
    public func readPixels(_ image: CIImage) throws -> [Float] {
        let width = Int(image.extent.width.rounded())
        let height = Int(image.extent.height.rounded())
        guard width > 0, height > 0 else { throw MellowError.renderFailed }
        var pixels = [Float](repeating: 0, count: width * height * 4)
        let rowBytes = width * 4 * MemoryLayout<Float>.size
        pixels.withUnsafeMutableBytes { buffer in
            context.render(
                image, toBitmap: buffer.baseAddress!, rowBytes: rowBytes, bounds: image.extent, format: .RGBAf,
                colorSpace: CGColorSpace(name: CGColorSpace.linearSRGB))
        }
        return pixels
    }
```

`apple/Sources/MellowRendering/API/AutoEnhancer.swift`:

```swift
import CoreImage
import Foundation
import MellowShared

/// 휘도 히스토그램과 평균색으로 슬라이더 값을 제안한다. 같은 수식을 다른 플랫폼이 재현할 수 있다.
public struct AutoEnhancer: Sendable {
    private let tuning: RenderTuning
    private let renderer: Renderer

    public init(tuning: RenderTuning, renderer: Renderer) {
        self.tuning = tuning
        self.renderer = renderer
    }

    public func suggestion(for image: CIImage, hasFaces: Bool) throws -> AutoEnhanceSuggestion {
        let bins = try luminanceHistogram(image)
        let mean = bins.enumerated().reduce(0.0) { $0 + (Double($1.offset) + 0.5) / Double(bins.count) * $1.element }
        let low = percentile(bins, 0.01)
        let high = percentile(bins, 0.99)
        var color = ColorAdjustments()
        var detail = DetailAdjustments()
        let limit = tuning.autoExposureLimit
        color.exposure = max(-limit, min(limit, log2(tuning.autoTargetLuminance / max(mean, 0.001))))
        if high - low >= tuning.autoFlatRange {
            if high >= tuning.autoHighlightThreshold {
                detail.highlights = -min(1, (high - 0.9) * 5)
            }
            if low <= tuning.autoShadowThreshold {
                detail.shadows = min(1, (0.1 - low) * 5)
            }
            color.saturation = tuning.autoSaturation
            color.contrast = tuning.autoContrast
            color.warmth = try warmthCorrection(image)
        }
        var portrait = PortraitAdjustments()
        if hasFaces {
            portrait.skinSmoothing = tuning.autoSkinSmoothing
            portrait.faceSlim = tuning.autoFaceSlim
        }
        return AutoEnhanceSuggestion(color: color, detail: detail, portrait: portrait)
    }

    /// 정규화된 휘도 히스토그램(합 1).
    private func luminanceHistogram(_ image: CIImage) throws -> [Double] {
        let gray = image.applyingFilter("CIColorControls", parameters: [kCIInputSaturationKey: 0])
        let histogram = gray.applyingFilter(
            "CIAreaHistogram",
            parameters: [
                "inputExtent": CIVector(cgRect: image.extent), "inputCount": tuning.autoHistogramBins, "inputScale": 1,
            ])
        let pixels = try renderer.readPixels(histogram)
        let counts = stride(from: 0, to: pixels.count, by: 4).map { Double(pixels[$0]) }
        let total = counts.reduce(0, +)
        guard total > 0 else { throw MellowError.renderFailed }
        return counts.map { $0 / total }
    }

    private func percentile(_ bins: [Double], _ fraction: Double) -> Double {
        var cumulative = 0.0
        for (index, weight) in bins.enumerated() {
            cumulative += weight
            if cumulative >= fraction {
                return (Double(index) + 0.5) / Double(bins.count)
            }
        }
        return 1
    }

    /// 그레이 월드: 평균 R이 B보다 크면(따뜻한 캐스트) 차갑게, 반대면 따뜻하게.
    private func warmthCorrection(_ image: CIImage) throws -> Double {
        let average = image.applyingFilter("CIAreaAverage", parameters: ["inputExtent": CIVector(cgRect: image.extent)])
        let pixels = try renderer.readPixels(average)
        let red = Double(pixels[0])
        let blue = Double(pixels[2])
        guard red + blue > 0 else { return 0 }
        let cast = (red - blue) / (red + blue)
        let correction = -cast * tuning.autoWarmthGain
        return max(-tuning.autoWarmthLimit, min(tuning.autoWarmthLimit, correction))
    }
}
```

`PhotoPipeline.swift`에 추가:

```swift
    /// 원본 분석 기준의 제안. 현재 레시피와 무관하다.
    public func autoEnhanceSuggestion(_ id: PhotoID, hasFaces: Bool) throws -> AutoEnhanceSuggestion {
        guard let image = cache.image(for: id) else { throw MellowError.cannotCreatePreview }
        return try AutoEnhancer(tuning: tuning, renderer: renderer).suggestion(for: image, hasFaces: hasFaces)
    }
```

- [ ] **Step 4: 통과 확인**

Run: `cd apple && swift test` → PASS. 단색 테스트에서 `high - low`가 0.05를 넘으면(필터 보간 노이즈) `autoFlatRange`를 0.08까지 올릴 수 있으나 그 이유를 보고서에 적는다. lint PASS.

- [ ] **Step 5: 커밋**

```bash
git add apple/Sources/MellowRendering apple/Tests/MellowRenderingTests
git commit -m "feat(rendering): 히스토그램 기반 자동 보정 제안 추가

Apple의 불투명한 자동 필터 대신 재현 가능한 수식으로 노출·하이라이트·
그림자·따뜻함과 인물 값을 제안한다.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 10: 룩 썸네일

**Files:**
- Modify: `apple/Sources/MellowRendering/API/PhotoPipeline.swift` (`Entry.thumbnail`, `lookThumbnails(_:)`)
- Test: `apple/Tests/MellowRenderingTests/PhotoPipelineTests.swift` (추가)

**Interfaces:**
- Consumes: `LookStage.styled(_:look:tuning:)`(Task 7), `LookCatalog`.
- Produces: `PhotoPipeline.lookThumbnails(_ id: PhotoID) throws -> [String: CGImage]`(카탈로그의 모든 룩 id → 강도 1 썸네일; 준비 안 된 사진이면 `cannotCreatePreview`).

- [ ] **Step 1: 실패하는 테스트 작성**

`PhotoPipelineTests.swift`에 추가:

```swift
    func testLookThumbnailsCoverCatalogAndDiffer() async throws {
        let url = try writeSolidPNG(size: 512)
        let id = PhotoID()
        let catalog = try RenderingTestSupport.sharedLookCatalog()
        let pipeline = PhotoPipeline(analyzer: StubFaceAnalyzer(result: .success([])), tuning: RenderTuning(), lookCatalog: catalog)
        _ = try await pipeline.prepare(id, at: url)
        let thumbnails = try await pipeline.lookThumbnails(id)
        XCTAssertEqual(Set(thumbnails.keys), Set(LookCatalog.builtInIDs))
        for (lookID, image) in thumbnails {
            XCTAssertLessThanOrEqual(max(image.width, image.height), RenderTuning().thumbnailMaxDimension, lookID)
        }
        let mono = try XCTUnwrap(thumbnails["mono"])
        let vivid = try XCTUnwrap(thumbnails["vivid"])
        XCTAssertNotEqual(Array(mono.dataProvider!.data! as Data), Array(vivid.dataProvider!.data! as Data))
    }

    func testLookThumbnailsRequirePreparedPhoto() async throws {
        let pipeline = PhotoPipeline(analyzer: StubFaceAnalyzer(result: .success([])), tuning: RenderTuning(), lookCatalog: try RenderingTestSupport.sharedLookCatalog())
        do {
            _ = try await pipeline.lookThumbnails(PhotoID())
            XCTFail()
        } catch {
            XCTAssertEqual(error as? MellowError, .cannotCreatePreview)
        }
    }
```

- [ ] **Step 2: 실패 확인**

Run: `cd apple && swift test --filter PhotoPipelineTests` → 컴파일 실패.

- [ ] **Step 3: 구현**

`PhotoPipeline.swift`: `Entry`에 `var thumbnail: CIImage`를 추가하고 `prepare`에서 `let thumbnailImage = Self.scaled(preview, maxDimension: tuning.thumbnailMaxDimension)`를 만들어 `Entry(faces:faceAnalysisFailure:thumbnail: thumbnailImage)`로 저장한 뒤 `renderer.makeCGImage(thumbnailImage)`를 돌려준다. 추가:

```swift
    /// 카탈로그의 모든 룩을 강도 1로 입힌 썸네일. 룩 단계만 적용한다(전체 파이프라인이 아님).
    public func lookThumbnails(_ id: PhotoID) throws -> [String: CGImage] {
        guard let entry = entries[id] else { throw MellowError.cannotCreatePreview }
        var result: [String: CGImage] = [:]
        for look in lookCatalog.all {
            let styled = LookStage.styled(entry.thumbnail, look: look, tuning: tuning).cropped(to: entry.thumbnail.extent)
            result[look.id] = try renderer.makeCGImage(styled)
        }
        return result
    }
```

- [ ] **Step 4: 통과 확인**

Run: `cd apple && swift test` → PASS. lint PASS.

- [ ] **Step 5: 커밋**

```bash
git add apple/Sources/MellowRendering/API/PhotoPipeline.swift apple/Tests/MellowRenderingTests/PhotoPipelineTests.swift
git commit -m "feat(rendering): 룩 썸네일 렌더 추가

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 11: AppModel — 자동 보정·룩·자르기 상태와 좌표 역변환

**Files:**
- Modify: `apple/MellowPhoto/Application/EditorTool.swift` (케이스 재구성)
- Modify: `apple/MellowPhoto/Application/UserMessage.swift` (문구 추가)
- Modify: `apple/MellowPhoto/Application/AppModel.swift` (`lookCatalog`, `lookThumbnails`, `cropAspect`, `canvasShowsUncropped`, `outputTransform`, `cloneSourceOnCanvas`, `selectTool`, `select`의 원본 렌더)
- Create: `apple/MellowPhoto/Application/AppModel+Looks.swift` (`loadLookThumbnails`, `autoEnhance`)
- Create: `apple/MellowPhoto/Application/AppModel+Geometry.swift` (`CropAspect`, `setCropAspect`, `beginCropDrag`, `endCropDrag`, `resetGeometry`)
- Modify: `apple/MellowPhoto/Application/AppModel+Editing.swift` (`touch` 역변환, `.color`→`.adjust`)
- Modify: `apple/MellowPhoto/Platform/AppModel+Live.swift` (번들 카탈로그 로드)
- Modify: `apple/MellowPhoto/Features/Editor/EditorScene.swift`, `AppModel+Library.swift` 등 `.color` 참조(컴파일 유지만; 화면 교체는 Task 12)
- Modify: `apple/MellowPhotoTests/TestSupport.swift` (`makeModel`이 shared 카탈로그 주입)
- Test: `apple/MellowPhotoTests/AppModelTests.swift` (추가)

**Interfaces:**
- Consumes: Task 5·8·9·10의 API, `GeometryTransform`(Task 3).
- Produces: `EditorTool { look, crop, adjust, portrait, retouch, warp }`, `AppModel.lookCatalog`, `lookThumbnails: [PhotoID: [String: CGImage]]`, `cropAspect: CropAspect?`, `canvasShowsUncropped`, `outputTransform: GeometryTransform?`, `cloneSourceOnCanvas: NormalizedPoint?`, `selectTool(_:)`, `autoEnhance() async`, `loadLookThumbnails()`, `setCropAspect(_:)`, `beginCropDrag()`, `endCropDrag()`, `resetGeometry()`, `UserMessage.autoEnhanced/toolLook/toolCrop/toolAdjust/toolAuto/lookCatalogUnavailable`. Task 12 화면이 쓴다.

- [ ] **Step 1: 실패하는 테스트 작성**

`TestSupport.swift`의 `makeModel`에 카탈로그를 넣는다:

```swift
    static func sharedLookCatalog() throws -> LookCatalog {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("shared/looks/looks.v1.json")
        return try LookCatalog(data: Data(contentsOf: url))
    }
    // makeModel: let catalog = (try? sharedLookCatalog()) ?? .empty
    //   pipeline: PhotoPipeline(analyzer: analyzer, tuning: RenderTuning(), lookCatalog: catalog)
    //   AppModel(…, lookCatalog: catalog, renderDebounce: …)
```

`AppModelTests.swift`에 추가:

```swift
    private func importOne(_ model: AppModel, _ url: URL) async throws {
        await model.importFromFiles([url])
        try await waitUntil { model.isReady && model.preview != nil }
    }

    func testAutoEnhanceIsOneUndoStepAndIdempotent() async throws {
        let staged = try TestSupport.solidPNG(in: root)
        let model = TestSupport.makeModel(root: root, importer: FakeImporter(staged: [.success(StagedPhoto(url: staged, displayName: nil))]))
        try await importOne(model, staged)
        await model.autoEnhance()
        let first = model.currentRecipe
        XCTAssertNotEqual(first, EditRecipe())
        XCTAssertEqual(model.session.selected?.document.undoStack.count, 1)
        await model.autoEnhance()
        XCTAssertEqual(model.currentRecipe, first, "두 번 눌러도 누적되지 않는다")
        model.undo()
        model.undo()
        XCTAssertTrue(model.currentRecipe.isDefault)
    }

    func testCropToolShowsUncroppedPreview() async throws {
        let staged = try TestSupport.solidPNG(in: root, size: 200)
        let model = TestSupport.makeModel(root: root, importer: FakeImporter(staged: [.success(StagedPhoto(url: staged, displayName: nil))]))
        try await importOne(model, staged)
        model.edit(.crop(NormalizedRect(x: 0, y: 0, width: 0.5, height: 0.5)))
        try await waitUntil { !model.isRendering }
        XCTAssertEqual(model.preview?.width, 100)
        model.selectTool(.crop)
        try await waitUntil { !model.isRendering && model.preview?.width == 200 }
        XCTAssertTrue(model.canvasShowsUncropped)
        model.selectTool(.adjust)
        try await waitUntil { !model.isRendering && model.preview?.width == 100 }
    }

    func testRetouchTapWhileCroppedIsStoredInOriginalCoordinates() async throws {
        let staged = try TestSupport.solidPNG(in: root, size: 200)
        let model = TestSupport.makeModel(root: root, importer: FakeImporter(staged: [.success(StagedPhoto(url: staged, displayName: nil))]))
        try await importOne(model, staged)
        model.edit(.crop(NormalizedRect(x: 0.5, y: 0.5, width: 0.5, height: 0.5)))
        try await waitUntil { !model.isRendering }
        model.selectTool(.retouch)
        // 화면 중앙(0.5, 0.5)은 원본의 (0.75, 0.75).
        model.touch(from: NormalizedPoint(x: 0.5, y: 0.5), to: NormalizedPoint(x: 0.5, y: 0.5))
        XCTAssertEqual(model.cloneSource?.x ?? 0, 0.75, accuracy: 1e-9)
        XCTAssertEqual(model.cloneSourceOnCanvas?.x ?? 0, 0.5, accuracy: 1e-9)
        model.touch(from: NormalizedPoint(x: 0.2, y: 0.2), to: NormalizedPoint(x: 0.2, y: 0.2))
        let spot = try XCTUnwrap(model.currentRecipe.spots.first)
        XCTAssertEqual(spot.x, 0.6, accuracy: 1e-9)
        XCTAssertEqual(spot.sourceX, 0.75, accuracy: 1e-9)
    }

    func testLookThumbnailsIgnoreStaleResults() async throws {
        let first = try TestSupport.solidPNG(in: root, name: "A", size: 300)
        let second = try TestSupport.solidPNG(in: root, name: "B", size: 300)
        let importer = FakeImporter(staged: [
            .success(StagedPhoto(url: first, displayName: "A")), .success(StagedPhoto(url: second, displayName: "B")),
        ])
        let model = TestSupport.makeModel(root: root, importer: importer)
        await model.importFromFiles([first, second])
        try await waitUntil { model.isReady }
        let a = model.session.photos[0].id
        let b = model.session.photos[1].id
        model.selectTool(.look)
        model.select(b)
        try await waitUntil { model.lookThumbnails[a]?.count == 10 || model.lookThumbnails[b]?.count == 10 }
        try await waitUntil { model.lookThumbnails[b]?.count == 10 }
        XCTAssertNotNil(model.lookThumbnails[b]?["mono"])
        if let aThumbs = model.lookThumbnails[a] {
            XCTAssertEqual(aThumbs.count, 10, "A의 결과가 왔다면 A 키 아래에만 있다")
        }
    }

    func testCropAspectSetsCenteredRectAndResetGeometryIsOneUndoStep() async throws {
        let staged = try TestSupport.solidPNG(in: root, size: 200)
        let model = TestSupport.makeModel(root: root, importer: FakeImporter(staged: [.success(StagedPhoto(url: staged, displayName: nil))]))
        try await importOne(model, staged)
        model.setCropAspect(.square)
        XCTAssertEqual(model.currentRecipe.geometry.crop, NormalizedRect(x: 0, y: 0, width: 1, height: 1))
        model.edit(.quarterTurns(1))
        model.setCropAspect(.nineSixteen)
        let crop = try XCTUnwrap(model.currentRecipe.geometry.crop)
        XCTAssertEqual(crop.width, 9.0 / 16.0, accuracy: 1e-9)
        XCTAssertEqual(crop.x, (1 - 9.0 / 16.0) / 2, accuracy: 1e-9)
        let before = model.session.selected?.document.undoStack.count ?? 0
        model.resetGeometry()
        XCTAssertTrue(model.currentRecipe.geometry.isIdentity)
        XCTAssertEqual(model.session.selected?.document.undoStack.count, before + 1)
    }
```

- [ ] **Step 2: 실패 확인**

Run: `xcodegen generate && xcodebuild -project apple/MellowPhoto.xcodeproj -scheme MellowPhoto -destination 'platform=macOS' build-for-testing 2>&1 | grep -c "error:"` → 0보다 큼.

- [ ] **Step 3: 구현**

`EditorTool.swift`:

```swift
enum EditorTool: CaseIterable, Identifiable {
    case look
    case crop
    case adjust
    case portrait
    case retouch
    case warp

    var id: Self { self }

    var title: String {
        switch self {
        case .look: return UserMessage.toolLook
        case .crop: return UserMessage.toolCrop
        case .adjust: return UserMessage.toolAdjust
        case .portrait: return UserMessage.toolPortrait
        case .retouch: return UserMessage.toolRetouch
        case .warp: return UserMessage.toolWarp
        }
    }

    var symbol: String {
        switch self {
        case .look: return "camera.filters"
        case .crop: return "crop.rotate"
        case .adjust: return "slider.horizontal.3"
        case .portrait: return "face.smiling"
        case .retouch: return "bandage"
        case .warp: return "arrow.up.left.and.arrow.down.right"
        }
    }

    var usesCanvasTouch: Bool { self == .retouch || self == .warp }
}
```

`UserMessage.swift`에 추가: `toolLook = "필터"`, `toolCrop = "자르기"`, `toolAdjust = "조정"`, `toolAuto = "자동"`, `autoEnhanced = "자동 보정을 적용했어요. 실행 취소로 되돌릴 수 있어요."`, `lookCatalogUnavailable = "필터 목록을 읽지 못해 필터를 쓸 수 없습니다."`, `toolColor` 삭제.

`AppModel.swift` 변경:

```swift
    let lookCatalog: LookCatalog
    var lookThumbnails: [PhotoID: [String: CGImage]] = [:]
    var cropAspect: CropAspect?
    var tool: EditorTool = .look
    /// 자르기 도구에서는 자르기 전 이미지를 보여준다.
    var canvasShowsUncropped: Bool { tool == .crop }
    // init에 `lookCatalog: LookCatalog = .empty` 추가 (renderDebounce 앞)

    /// 캔버스(출력) 좌표와 원본 좌표 사이의 변환. 자르기 도구에서는 자르기만 뺀 기하를 쓴다.
    var outputTransform: GeometryTransform? {
        guard let size = selectedInfo?.pixelSize, size.height > 0 else { return nil }
        var geometry = currentRecipe.geometry
        if canvasShowsUncropped {
            geometry.crop = nil
        }
        return GeometryTransform(geometry: geometry, sourceAspect: size.width / size.height)
    }

    /// 복제 샘플 마커를 그릴 캔버스 좌표. 자른 영역 밖이면 nil.
    var cloneSourceOnCanvas: NormalizedPoint? {
        guard let source = cloneSource else { return nil }
        guard let transform = outputTransform else { return source }
        return transform.toOutput(source)
    }

    func selectTool(_ newTool: EditorTool) {
        let showedUncropped = canvasShowsUncropped
        tool = newTool
        if canvasShowsUncropped != showedUncropped {
            scheduleRender()
        }
        if newTool == .look {
            loadLookThumbnails()
        }
    }
```

`scheduleRender`의 렌더 클로저는 `showsUncropped`를 캡처해 `pipeline.preview(id, recipe: recipe, showsUncropped: showsUncropped)`를 부르고, 성공 콜백에서 `refreshOriginalIfNeeded(id:geometry:)`를 호출한다. 원본(비교용)은 기하만 적용한 레시피로 그린다:

```swift
    /// 비교 화면의 원본은 같은 기하(자르기·회전)로 보여야 한다.
    private var originalGeometry: GeometryAdjustments?

    private func refreshOriginalIfNeeded(id: PhotoID, showsUncropped: Bool) {
        var geometry = currentRecipe.geometry
        if showsUncropped {
            geometry.crop = nil
        }
        guard originalGeometry != geometry else { return }
        originalGeometry = geometry
        let recipe = EditRecipe(geometry: geometry)
        let pipeline = self.pipeline
        Task { [weak self] in
            guard let image = try? await pipeline.preview(id, recipe: recipe) else { return }
            guard let self, session.selectedPhotoID == id else { return }
            original = image
        }
    }
```

`select`에서 `originalGeometry = nil`로 초기화하고, 기존 `pipeline.preview(id, recipe: EditRecipe())`로 `original`을 처음 채우는 부분은 유지한다(기하가 없을 때의 기본). `lookThumbnails`는 사진을 빼면(`removeSelectedPhoto`) 해당 키를 지운다.

`AppModel+Looks.swift`:

```swift
import MellowEditing
import MellowShared

extension AppModel {
    /// 선택 사진의 룩 썸네일을 한 번만 만든다. 늦게 온 결과는 사진 id 키로 들어가므로 다른 사진에 붙지 않는다.
    func loadLookThumbnails() {
        guard let entry = session.selected, isReady, lookThumbnails[entry.id] == nil, !lookCatalog.all.isEmpty else { return }
        let id = entry.id
        let pipeline = self.pipeline
        let url = copies.url(for: entry.filename)
        Task { [weak self] in
            do {
                try await pipeline.reprepareIfEvicted(id, at: url)
                let thumbnails = try await pipeline.lookThumbnails(id)
                self?.lookThumbnails[id] = thumbnails
            } catch {
                self?.present(error)
            }
        }
    }

    /// 원본 분석으로 제안을 받아 체크포인트 한 번으로 적용한다.
    func autoEnhance() async {
        guard let entry = session.selected, isReady, !isBusy else { return }
        do {
            try await pipeline.reprepareIfEvicted(entry.id, at: copies.url(for: entry.filename))
            let suggestion = try await pipeline.autoEnhanceSuggestion(entry.id, hasFaces: !faces.isEmpty)
            guard session.selectedPhotoID == entry.id else { return }
            applyAutoSuggestion(suggestion)
            statusMessage = UserMessage.autoEnhanced
        } catch {
            present(error)
        }
    }
}
```

`AppModel+Editing.swift`에 `applyAutoSuggestion`을 추가(`mutateSelected { $0.applyAuto(suggestion); return nil }`)하고, `touch`를 역변환하도록 바꾼다:

```swift
    func touch(from: NormalizedPoint, to: NormalizedPoint) {
        guard isReady, !isBusy, !isComparing, !isRendering, !canvasShowsUncropped else { return }
        let transform = outputTransform
        let fromOriginal = transform?.toOriginal(from) ?? from
        let toOriginal = transform?.toOriginal(to) ?? to
        switch tool {
        case .retouch: … 기존 로직에서 `to`→`toOriginal` …
        case .warp: … `from`/`to` → `fromOriginal`/`toOriginal` …
        case .look, .crop, .adjust, .portrait:
            return
        }
    }
```

`AppModel+Geometry.swift`:

```swift
import MellowEditing
import MellowShared

enum CropAspect: CaseIterable, Identifiable {
    case original
    case square
    case fourFive
    case threeFour
    case nineSixteen

    var id: Self { self }

    /// 가로/세로. original은 nil(회전 뒤 이미지 비율 그대로).
    var ratio: Double? {
        switch self {
        case .original: return nil
        case .square: return 1
        case .fourFive: return 4.0 / 5.0
        case .threeFour: return 3.0 / 4.0
        case .nineSixteen: return 9.0 / 16.0
        }
    }
}

extension AppModel {
    /// 비율에 맞는 가장 큰 중앙 사각형을 자르기로 넣는다. 원본 비율이면 자르기를 없앤다.
    func setCropAspect(_ aspect: CropAspect) {
        cropAspect = aspect
        guard let transform = outputTransform else { return }
        guard let ratio = aspect.ratio else {
            edit(.crop(nil))
            return
        }
        edit(.crop(Self.centeredCrop(ratio: ratio, imageAspect: transform.turnedAspect)))
    }

    /// 정규화 공간에서 가로/세로 = ratio가 되는 가장 큰 중앙 사각형.
    static func centeredCrop(ratio: Double, imageAspect: Double) -> NormalizedRect {
        let width = min(1, ratio / imageAspect)
        let height = min(1, imageAspect / ratio)
        return NormalizedRect(x: (1 - width) / 2, y: (1 - height) / 2, width: width, height: height)
    }

    func beginCropDrag() {
        beginSliderEdit()
    }

    func endCropDrag() {
        endSliderEdit()
    }

    /// 기하만 기본값으로. 실행 취소 한 단계.
    func resetGeometry() {
        cropAspect = nil
        beginSliderEdit()
        edit(.crop(nil))
        edit(.straightenDegrees(0))
        edit(.quarterTurns(0))
        edit(.flipHorizontal(false))
        endSliderEdit()
    }
}
```

`setCropAspect(.square)` 검증: 이미지 비율 1(200×200)에 ratio 1 → width 1, height 1, 원점 0 ✓. 회전 1회 뒤 `turnedAspect` 1에 ratio 9/16 → width 9/16, height 1, x=(1−9/16)/2 ✓.

`AppModel+Live.swift`: 번들에서 카탈로그를 읽어 `PhotoPipeline(…, lookCatalog:)`와 `AppModel(…, lookCatalog:)`에 넘긴다. 실패하면 `.empty`로 만들고 `model.present(message: UserMessage.lookCatalogUnavailable)`.

`.color` 참조는 전부 `.adjust`로 바꾼다(`EditorScene`의 `toolPanel`, 기타). 화면 자체는 Task 12에서 교체하므로 여기서는 컴파일만 유지한다.

- [ ] **Step 4: 통과 확인**

Run: macOS와 iPhone 시뮬레이터 앱 테스트 → TEST SUCCEEDED(30 + 5 = 35, iPhone 34). lint PASS. `./scripts/verify-modules.sh` PASS.

- [ ] **Step 5: 커밋**

```bash
git add apple/MellowPhoto apple/MellowPhotoTests apple/MellowPhoto.xcodeproj
git commit -m "feat(app): 자동 보정·룩 썸네일·자르기 상태와 캔버스 좌표 역변환 추가

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 12: 화면 — 도구 줄, 필터·조정·자르기 패널, 자르기 오버레이

**Files:**
- Create: `apple/MellowPhoto/Features/Editor/ToolStrip.swift`
- Create: `apple/MellowPhoto/Features/Editor/LookPanel.swift`
- Create: `apple/MellowPhoto/Features/Editor/CropPanel.swift`
- Create: `apple/MellowPhoto/Features/Editor/CropOverlay.swift`
- Rename: `apple/MellowPhoto/Features/Editor/ColorPanel.swift` → `AdjustPanel.swift` (내용 교체)
- Modify: `apple/MellowPhoto/Features/Editor/EditorScene.swift` (세그먼트 피커 → `ToolStrip`, `toolPanel` 분기)
- Modify: `apple/MellowPhoto/Features/Editor/PhotoCanvasView.swift` (자르기 오버레이, `cloneSourceOnCanvas`)
- Modify: `apple/MellowPhoto/Features/Shared/Theme.swift` (`lookChipSize`, `cropHandleSize`, `toolButtonSize`)
- Modify: `apple/MellowPhoto/Features/Shared/AdjustmentSlider.swift` (변경 없음이면 그대로)
- Test: 없음 (실기동으로 검증; Step 6)

**Interfaces:**
- Consumes: Task 11의 `AppModel` API 전체, `CropAspect`, `EditorTool`, `Theme`.
- Produces: 화면. 이후 Task가 참조하지 않는다.

- [ ] **Step 1: Theme 상수와 도구 줄**

`Theme.swift`에 추가:

```swift
    static let toolButtonSize = CGSize(width: 64, height: 56)
    static let lookChipSize = CGSize(width: 64, height: 76)
    static let cropHandleSize: CGFloat = 22
    static let cropMinimumSide = 0.1
```

`apple/MellowPhoto/Features/Editor/ToolStrip.swift`:

```swift
import SwiftUI

/// 가로 스크롤 도구 줄. '자동'은 도구가 아니라 즉시 적용 버튼이다.
struct ToolStrip: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 4) {
                toolButton(.look)
                Button {
                    Task { await model.autoEnhance() }
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: "wand.and.stars").font(.title3)
                        Text(UserMessage.toolAuto).font(.caption2)
                    }
                    .frame(width: Theme.toolButtonSize.width, height: Theme.toolButtonSize.height)
                }
                .buttonStyle(.plain)
                .foregroundStyle(Theme.accent)
                .accessibilityLabel("자동 보정")
                ForEach([EditorTool.crop, .adjust, .portrait, .retouch, .warp]) { toolButton($0) }
            }
            .padding(.horizontal, 8)
        }
        .scrollIndicators(.hidden)
    }

    private func toolButton(_ tool: EditorTool) -> some View {
        let selected = model.tool == tool
        return Button {
            model.selectTool(tool)
        } label: {
            VStack(spacing: 4) {
                Image(systemName: tool.symbol).font(.title3)
                Text(tool.title).font(.caption2)
            }
            .frame(width: Theme.toolButtonSize.width, height: Theme.toolButtonSize.height)
            .background(selected ? Color.white.opacity(0.1) : .clear, in: RoundedRectangle(cornerRadius: 10))
            .foregroundStyle(selected ? Theme.accent : .secondary)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(tool.title)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
```

- [ ] **Step 2: 필터·조정 패널**

`apple/MellowPhoto/Features/Editor/LookPanel.swift`:

```swift
import MellowShared
import SwiftUI

struct LookPanel: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let selection = model.currentRecipe.look
        let thumbnails = model.session.selectedPhotoID.flatMap { model.lookThumbnails[$0] } ?? [:]
        ScrollView(.horizontal) {
            HStack(spacing: 10) {
                chip(id: nil, name: "원본", image: model.session.selectedPhotoID.flatMap { model.thumbnails[$0] }, selected: selection.id == nil)
                ForEach(model.lookCatalog.all) { look in
                    chip(id: look.id, name: look.name, image: thumbnails[look.id], selected: selection.id == look.id)
                }
            }
            .padding(.vertical, 4)
        }
        .scrollIndicators(.hidden)
        .onAppear { model.loadLookThumbnails() }
        if selection.id != nil {
            AdjustmentSlider(title: "강도", value: selection.intensity, range: 0...1) { .lookIntensity($0) }
        }
        if model.lookCatalog.all.isEmpty {
            Text(UserMessage.lookCatalogUnavailable).font(.caption).foregroundStyle(.secondary)
        }
    }

    private func chip(id: String?, name: String, image: CGImage?, selected: Bool) -> some View {
        Button {
            model.edit(.lookID(selected ? nil : id))
        } label: {
            VStack(spacing: 4) {
                ZStack {
                    Rectangle().fill(.secondary.opacity(0.2))
                    if let image {
                        Image(cgImage: image).resizable().scaledToFill()
                    } else {
                        ProgressView().controlSize(.small)
                    }
                }
                .frame(width: Theme.lookChipSize.width, height: Theme.lookChipSize.width)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(selected ? Theme.accent : .clear, lineWidth: 2))
                Text(name).font(.caption2).foregroundStyle(selected ? Theme.accent : .secondary)
            }
            .frame(width: Theme.lookChipSize.width, height: Theme.lookChipSize.height)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(name)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
```

`apple/MellowPhoto/Features/Editor/AdjustPanel.swift`(`ColorPanel.swift`를 `git mv`로 이름 바꾼 뒤 내용 교체; 구조체 이름 `AdjustPanel`):

```swift
import MellowShared
import SwiftUI

/// 분위기 프리셋 + 색감 슬라이더 + 디테일 슬라이더.
struct AdjustPanel: View {
    @Environment(AppModel.self) private var model
    @Binding var presetSheet: Bool

    var body: some View {
        let recipe = model.currentRecipe
        ScrollView(.horizontal) {
            HStack {
                ForEach(BuiltInPresets.all + model.session.presets) { preset in
                    Button(preset.name) { model.applyPreset(preset.values) }
                }
                Button {
                    presetSheet = true
                } label: {
                    Label("저장", systemImage: "plus")
                }
            }
            .buttonStyle(.bordered).font(.caption)
        }
        .scrollIndicators(.hidden)
        AdjustmentSlider(title: "노출", value: recipe.color.exposure, range: -1.5...1.5) { .exposure($0) }
        AdjustmentSlider(title: "대비", value: recipe.color.contrast, range: 0.7...1.3) { .contrast($0) }
        AdjustmentSlider(title: "채도", value: recipe.color.saturation, range: 0...1.5) { .saturation($0) }
        AdjustmentSlider(title: "따뜻함", value: recipe.color.warmth, range: -1...1) { .warmth($0) }
        Divider().opacity(0.4)
        AdjustmentSlider(title: "하이라이트", value: recipe.detail.highlights, range: -1...1) { .highlights($0) }
        AdjustmentSlider(title: "그림자", value: recipe.detail.shadows, range: -1...1) { .shadows($0) }
        AdjustmentSlider(title: "선명도", value: recipe.detail.sharpness, range: 0...1) { .sharpness($0) }
        AdjustmentSlider(title: "비네팅", value: recipe.detail.vignette, range: 0...1) { .vignette($0) }
    }
}
```

`savePreset`은 Task 11 전에 이미 `PresetValues(color:portrait:)`를 쓰므로 `detail: currentRecipe.detail`을 추가한다(`AppModel+Editing.swift`).

- [ ] **Step 3: 자르기 패널과 오버레이**

`apple/MellowPhoto/Features/Editor/CropPanel.swift`:

```swift
import MellowShared
import SwiftUI

struct CropPanel: View {
    @Environment(AppModel.self) private var model

    private static let aspectTitles: [CropAspect: String] = [
        .original: "원본", .square: "1:1", .fourFive: "4:5", .threeFour: "3:4", .nineSixteen: "9:16",
    ]

    var body: some View {
        let geometry = model.currentRecipe.geometry
        ScrollView(.horizontal) {
            HStack {
                ForEach(CropAspect.allCases) { aspect in
                    Button(Self.aspectTitles[aspect] ?? "") { model.setCropAspect(aspect) }
                        .tint(model.cropAspect == aspect ? Theme.accent : .secondary)
                }
            }
            .buttonStyle(.bordered).font(.caption)
        }
        .scrollIndicators(.hidden)
        HStack(spacing: 16) {
            Button {
                model.edit(.quarterTurns(geometry.quarterTurns + 1))
            } label: {
                Label("90° 회전", systemImage: "rotate.right")
            }
            Button {
                model.edit(.flipHorizontal(!geometry.flipHorizontal))
            } label: {
                Label("좌우 반전", systemImage: "arrow.left.and.right.righttriangle.left.righttriangle.right")
            }
            Spacer()
            Button("되돌리기") { model.resetGeometry() }.disabled(geometry.isIdentity)
        }
        .buttonStyle(.bordered).font(.caption)
        AdjustmentSlider(
            title: "수평", value: geometry.straightenDegrees,
            range: -GeometryAdjustments.maxStraightenDegrees...GeometryAdjustments.maxStraightenDegrees
        ) { .straightenDegrees($0) }
        Text("사각형의 모서리를 끌어 자를 부분을 정해요. 잡티·변형 위치는 원본 기준으로 그대로 남아요.")
            .font(.caption).foregroundStyle(.secondary)
    }
}
```

`apple/MellowPhoto/Features/Editor/CropOverlay.swift`:

```swift
import MellowShared
import SwiftUI

/// 자르기 전 이미지 위의 사각형과 손잡이 8개. 좌표는 정규화·원점 왼쪽 아래로 모델에 넘긴다.
struct CropOverlay: View {
    @Environment(AppModel.self) private var model
    let size: CGSize
    @State private var dragStartRect: NormalizedRect?

    private enum Handle: CaseIterable {
        case topLeft, top, topRight, left, right, bottomLeft, bottom, bottomRight
    }

    private var rect: NormalizedRect {
        model.currentRecipe.geometry.crop ?? NormalizedRect(x: 0, y: 0, width: 1, height: 1)
    }

    var body: some View {
        let frame = pixelFrame(rect)
        ZStack(alignment: .topLeading) {
            Color.black.opacity(0.45)
                .mask(
                    Rectangle().overlay(Rectangle().frame(width: frame.width, height: frame.height).position(x: frame.midX, y: frame.midY).blendMode(.destinationOut))
                )
                .allowsHitTesting(false)
            Rectangle().stroke(Theme.accent, lineWidth: 1.5)
                .frame(width: frame.width, height: frame.height)
                .position(x: frame.midX, y: frame.midY)
                .allowsHitTesting(false)
            ForEach(Handle.allCases, id: \.self) { handle in
                Circle().fill(Theme.accent)
                    .frame(width: Theme.cropHandleSize, height: Theme.cropHandleSize)
                    .position(handlePosition(handle, in: frame))
                    .gesture(handleDrag(handle))
            }
            Color.clear.contentShape(Rectangle())
                .frame(width: frame.width, height: frame.height)
                .position(x: frame.midX, y: frame.midY)
                .gesture(moveDrag)
        }
        .frame(width: size.width, height: size.height)
    }

    /// 정규화(원점 왼쪽 아래) → 뷰 픽셀(원점 왼쪽 위).
    private func pixelFrame(_ rect: NormalizedRect) -> CGRect {
        CGRect(
            x: rect.x * size.width, y: (1 - rect.maxY) * size.height,
            width: rect.width * size.width, height: rect.height * size.height)
    }

    private func handlePosition(_ handle: Handle, in frame: CGRect) -> CGPoint {
        switch handle {
        case .topLeft: return CGPoint(x: frame.minX, y: frame.minY)
        case .top: return CGPoint(x: frame.midX, y: frame.minY)
        case .topRight: return CGPoint(x: frame.maxX, y: frame.minY)
        case .left: return CGPoint(x: frame.minX, y: frame.midY)
        case .right: return CGPoint(x: frame.maxX, y: frame.midY)
        case .bottomLeft: return CGPoint(x: frame.minX, y: frame.maxY)
        case .bottom: return CGPoint(x: frame.midX, y: frame.maxY)
        case .bottomRight: return CGPoint(x: frame.maxX, y: frame.maxY)
        }
    }

    private func handleDrag(_ handle: Handle) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                if dragStartRect == nil {
                    dragStartRect = rect
                    model.beginCropDrag()
                }
                guard let start = dragStartRect else { return }
                let dx = Double(value.translation.width / size.width)
                let dy = -Double(value.translation.height / size.height)
                model.edit(.crop(Self.resized(start, handle: handle, dx: dx, dy: dy, lockedRatio: lockedRatio)))
            }
            .onEnded { _ in
                dragStartRect = nil
                model.endCropDrag()
            }
    }

    private var moveDrag: some Gesture {
        DragGesture(minimumDistance: 1)
            .onChanged { value in
                if dragStartRect == nil {
                    dragStartRect = rect
                    model.beginCropDrag()
                }
                guard let start = dragStartRect else { return }
                let dx = Double(value.translation.width / size.width)
                let dy = -Double(value.translation.height / size.height)
                let x = min(max(0, start.x + dx), 1 - start.width)
                let y = min(max(0, start.y + dy), 1 - start.height)
                model.edit(.crop(NormalizedRect(x: x, y: y, width: start.width, height: start.height)))
            }
            .onEnded { _ in
                dragStartRect = nil
                model.endCropDrag()
            }
    }

    /// 비율 고정 시 정규화 공간에서의 width/height 비(이미지 비율 반영).
    private var lockedRatio: Double? {
        guard let ratio = model.cropAspect?.ratio, let transform = model.outputTransform else { return nil }
        return ratio / transform.turnedAspect
    }

    /// 손잡이를 끈 결과. 최소 변 Theme.cropMinimumSide, 0…1로 제한. 비율 고정이면 높이를 너비에 맞춘다.
    static func resized(_ start: NormalizedRect, handle: Handle, dx: Double, dy: Double, lockedRatio: Double?) -> NormalizedRect {
        var minX = start.minX
        var maxX = start.maxX
        var minY = start.minY
        var maxY = start.maxY
        switch handle {
        case .topLeft: minX += dx; maxY += dy
        case .top: maxY += dy
        case .topRight: maxX += dx; maxY += dy
        case .left: minX += dx
        case .right: maxX += dx
        case .bottomLeft: minX += dx; minY += dy
        case .bottom: minY += dy
        case .bottomRight: maxX += dx; minY += dy
        }
        minX = max(0, min(minX, maxX - Theme.cropMinimumSide))
        maxX = min(1, max(maxX, minX + Theme.cropMinimumSide))
        minY = max(0, min(minY, maxY - Theme.cropMinimumSide))
        maxY = min(1, max(maxY, minY + Theme.cropMinimumSide))
        if let lockedRatio {
            let width = maxX - minX
            let height = min(1, width / lockedRatio)
            if [.top, .topLeft, .topRight].contains(handle) {
                maxY = min(1, minY + height)
            } else {
                minY = max(0, maxY - height)
            }
        }
        return NormalizedRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }
}
```

`switch`의 한 줄 두 문장(`minX += dx; maxY += dy`)은 세미콜론 금지 규칙에 걸리므로 각각 두 줄로 쓴다.

- [ ] **Step 4: 캔버스와 장면 연결**

`PhotoCanvasView.swift`: `.overlay { touchLayer(in: size) }` 뒤에 `.overlay { if model.tool == .crop, !model.isComparing { CropOverlay(size: size) } }`를 추가한다. `cloneSourceMarker`는 `model.cloneSourceOnCanvas`를 쓴다. 자르기 도구에서는 `touchLayer`가 비활성(`usesCanvasTouch`가 false라 이미 그렇다). `MagnifyGesture`는 자르기 도구에서도 동작하되 오버레이 손잡이 드래그가 우선이도록 오버레이를 가장 위에 둔다.

`EditorScene.swift`: compact·regular 모두 `Picker(…).pickerStyle(.segmented)`를 `ToolStrip()`으로 바꾸고, `toolPanel`을

```swift
        switch model.tool {
        case .look: LookPanel()
        case .crop: CropPanel()
        case .adjust: AdjustPanel(presetSheet: $presetSheet)
        case .portrait: PortraitPanel()
        case .retouch, .warp: BrushPanel()
        }
```

로. compact의 `Theme.compactControlsHeight`는 182에서 200으로 올린다(슬라이더 8개 스크롤).

- [ ] **Step 5: 빌드·테스트**

Run: `xcodegen generate`, iOS 시뮬레이터 빌드, macOS 빌드, macOS·iPhone 앱 테스트 → 모두 성공, 새 경고 없음, lint PASS.

- [ ] **Step 6: 실기동 (Task 14 상당)**

Mac Release 앱을 접근성 액션으로 구동(Task 11·14 보고서의 방법 재사용, 전역 키 입력 금지): `shared/fixtures/demo-portrait.png` 가져오기(파일 열기 패널이 자동화되지 않으면 Mac 컨테이너에 세션을 시드), 필터 "필름" 선택 → 강도 0.5 → "자동" → 조정 탭에서 하이라이트 −0.5 → 자르기 1:1 → 수평 5° → 90° 회전 → 저장 → 저장 파일 크기가 정사각형인지 확인. 화면 캡처를 SDD 작업 폴더에 둔다. iPhone·iPad 시뮬레이터는 시드된 세션으로 필터 패널·자르기 패널 화면을 캡처한다. 결과를 보고서에 적는다(통과하지 않은 것은 통과로 적지 않는다).

- [ ] **Step 7: 커밋**

```bash
git add apple/MellowPhoto apple/MellowPhoto.xcodeproj
git commit -m "feat(app): 도구 줄·필터·조정·자르기 화면 추가

세그먼트 피커를 가로 도구 줄로 바꾸고 필터 칩, 자동 보정 버튼,
자르기 오버레이를 더한다.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 13: 문서·검증 기록

**Files:**
- Modify: `README.md`(기능 목록·첫 보정 단계), `docs/APPLE.md`(사용법·테스트 수), `docs/architecture/modules.md`(Shared·Rendering 캔버스에 새 타입·단계, Rendering 규칙에 "기하 단계는 마지막"), `shared/recipe-schema/README.md`(Task 2에서 갱신했는지 확인), `shared/looks/README.md`(확인), `VALIDATION.md`(새 절)
- Test: 없음

- [ ] **Step 1: 문서 갱신**

README "구현된 범위"에 필터 10종·자동 보정·자르기·디테일 슬라이더를 추가하고 "첫 보정" 단계를 필터 → 자동 → 자르기 → 조정 순으로 다시 쓴다. "첫 버전의 한계"에서 "자동 잡티 탐지 없음"은 유지한다. `docs/APPLE.md`의 사용 절에 도구 줄 순서와 자르기 도구 설명, 테스트 수(`./scripts/test-apple.sh` 결과)를 적는다. `modules.md`: Shared 공개 API에 `DetailAdjustments, LookSelection, GeometryAdjustments, Look, LookCatalog, GeometryTransform, AutoEnhanceSuggestion`, Rendering 공개 API에 `AutoEnhancer`, 파이프라인 7단계 이름, `PhotoPipeline`의 새 메서드. `scripts/verify-modules.sh`는 바뀌지 않는다.

- [ ] **Step 2: VALIDATION.md**

`## B0 기본 편집 세트 (2026-10-15)` 절: 자동 검증 수(패키지·앱별), Task 12의 실기동 결과(플랫폼별, 방법별), 룩 10종을 데모 사진에서 본 결과(좋지 않은 룩이 있으면 수치 조정 여부와 근거), 미검증 목록(실기기, iOS 대화형, 48MP에서 CIHighlightShadowAdjust 속도, Option+클릭 등 이전 미검증 항목 승계).

- [ ] **Step 3: 최종 검증과 커밋**

Run: `./scripts/test-apple.sh && ./scripts/build-apple.sh ios-device && ./scripts/build-apple.sh mac` → 전부 성공.

```bash
git add README.md docs/APPLE.md docs/architecture/modules.md VALIDATION.md shared
git commit -m "docs: 기본 편집 세트 사용법·모듈 캔버스·검증 기록 갱신

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

## 자체 검토 결과

- **스펙 대조:** §2 레시피 → Task 2. §3 룩 데이터 → Task 4. §4 파이프라인·좌표 변환 → Task 3·6·7·8. §5 자동 보정 → Task 5(applyAuto)·9(AutoEnhancer)·11(autoEnhance). §6 화면 → Task 11(상태)·12(뷰). §7 오류 → Task 9(renderFailed)·11(lookCatalogUnavailable). §8 테스트 → 각 Task. §9 선행 작업 → Task 1. §10 위험 → Task 7 Step 4(수치 조정 근거), Task 10(썸네일은 룩 단계만), Task 9(클램프·보수적 게인).
- **스펙과 다르게 정한 점:** `RenderContext.skipsCrop`과 `PhotoPipeline.preview(_:recipe:showsUncropped:)`는 스펙 §6의 "RenderContext.skipsCrop" 그대로. 비교용 원본은 "기하만 적용한 레시피"로 그려 자른 결과와 크기가 맞게 했다(스펙은 명시하지 않음). `AutoEnhancer`는 Rendering `API/`에 public으로 둔다(스펙은 모듈 내부 위치를 정하지 않음).
- **타입 일관성:** `GeometryTransform.turnedAspect`는 Task 3에서 public으로 선언하고 Task 11·12가 쓴다. `LookStage.styled`는 internal static이며 Task 10이 같은 모듈에서 쓴다. `EditChange` 케이스 이름(`lookID`, `lookIntensity`, `quarterTurns`, `straightenDegrees`, `crop`)을 Task 5·11·12에서 동일하게 썼다. `PhotoPipeline.init`의 `lookCatalog` 기본값 `.empty`로 기존 테스트가 그대로 컴파일된다. `CropAspect`는 Task 11에 정의되고 Task 12가 쓴다. `Theme.cropMinimumSide`·`cropHandleSize`·`lookChipSize`·`toolButtonSize`는 Task 12 Step 1에서 정의된다.
- **Review Focus 매핑:** 1→Task 2, 2→Task 11, 3→Task 11, 4→Task 9+11, 5→Task 8. 모두 테스트 코드가 있다.
- **플레이스홀더 점검:** "TBD/TODO/나중에" 없음. Task 11의 `touch` 변경은 바뀌는 부분만 적었으므로 구현자는 기존 본문(Task 9에서 작성된 `AppModel+Editing.swift`)을 읽고 `to`/`from`을 원본 좌표로 치환한다.
