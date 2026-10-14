# B0 기본 편집 세트 구현 계획

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 필터(룩) 10종, 자동 보정 한 번, 자르기·회전·수평, 하이라이트·그림자·선명도·비네팅을 A의 모듈 구조 위에 얹어 SNOW식 원탭 기본 편집을 완성한다.

**Architecture:** 레시피 v2에 `detail`·`look`·`geometry`를 추가(기본값, schemaVersion 유지)하고, 렌더 파이프라인에 `DetailStage`→`LookStage`→`GeometryStage`를 뒤에 붙인다. 룩은 `shared/looks/looks.v1.json`의 파라미터 데이터이며 `LookStage`가 Core Image 기본 필터로 조립한다. 자르기는 맨 마지막 단계라 얼굴·수동 편집 좌표는 원본 기준 그대로이고, 순수 수학 `GeometryTransform`이 화면 좌표와 원본 좌표를 오간다. 자동 보정은 `AutoEnhancer`가 히스토그램으로 슬라이더 값을 제안하고 `EditDocument.applyAuto`가 체크포인트 한 번으로 적용한다.

**Tech Stack:** Swift 5.9 tools / Swift 5 언어 모드, SwiftUI + Observation, Core Image(CIHighlightShadowAdjust·CISharpenLuminance·CIVignette·CIToneCurve·CIColorControls·CITemperatureAndTint·CIMix·CIAreaHistogram·CIAreaAverage), XCTest, XcodeGen 2.46.0.

**Spec:** `docs/superpowers/specs/2026-10-14-b0-basic-editing-design.md`

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

> **작성 중단 지점 (2026-10-14, 사용량 한도):** Task 1~5 작성 완료. 남은 Task 6 DetailStage, 7 LookStage(+RenderContext.lookCatalog, PhotoPipeline lookCatalog), 8 GeometryStage(+파이프라인 extent·skipsCrop·preview showsUncropped), 9 AutoEnhancer(+PhotoPipeline.autoEnhanceSuggestion), 10 룩 썸네일(PhotoPipeline.lookThumbnails), 11 AppModel(autoEnhance·lookThumbnails·cropAspect·canvasShowsUncropped·outputTransform·탭 역변환·EditorTool 재구성), 12 화면(ToolStrip·LookPanel·AdjustPanel·CropPanel·CropOverlay), 13 문서·VALIDATION. 인터페이스 요약 절의 이름을 그대로 쓴다.
