# Apple 앱 구조 리팩토링 (하위 프로젝트 A) 구현 계획

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Mac·iPhone 두 앱과 한 덩어리 엔진을, 능력 단위 Swift 모듈 5개와 iPhone·iPad·Mac 단일 SwiftUI 앱으로 재구성한다. 보정 결과는 바꾸지 않고, 출시된 iPhone 앱의 세션 파일을 그대로 읽는다.

**Architecture:** `apple/Package.swift`의 MellowKit 패키지가 MellowShared(공유 커널) ← MellowEditing(편집 규칙) ← MellowLibrary(사진 관리·영속화), MellowShared ← MellowRendering(분석·렌더 단계 파이프라인) ← MellowExport(저장)를 담는다. 앱 타깃은 XcodeGen으로 생성하며 `AppModel`이 composition root, `ImportPhotos`·`ExportPhotos` 두 유스케이스가 모듈을 가로지르고, 플랫폼 차이는 `PhotoImporter`·`ExportDestination` 포트 뒤에 둔다.

**Tech Stack:** Swift 5.9 tools(Swift 5 언어 모드, strict-concurrency complete 경고), SwiftUI + Observation(iOS 17 / macOS 14), Core Image, Vision, ImageIO, PhotosUI, XCTest, XcodeGen, 툴체인 내장 `swift format`, GitHub Actions macos-15, fastlane.

**Spec:** `docs/superpowers/specs/2026-10-14-apple-modulith-restructure-design.md`

## Global Constraints

- 최소 OS: iOS 17.0, macOS 14.0. 번들 ID `com.mj.mellowphoto` (iOS·Mac 동일).
- 모듈 의존성은 스펙 3절 표가 전부다. Editing·Library는 CoreImage·Vision·SwiftUI·UIKit·AppKit·Photos를 import하지 않는다. Rendering·Export는 SwiftUI·UIKit·AppKit·Photos를 import하지 않는다.
- 모듈 내부는 `API/`(public만), `Domain/`, `Infrastructure/` 폴더. 다른 모듈은 `API/`만 본다.
- 한 줄 한 문장. 세미콜론으로 문장을 잇지 않는다. 매직 넘버는 `RenderTuning`·`EditingPolicy`·`LibraryPolicy`·`Theme`에 이름 붙인다.
- 좌표는 방향 보정된 이미지 기준 정규화 좌표, 원점 왼쪽 아래. 얼굴 순서는 boundingBox.minX 오름차순.
- 사용자 문구(한국어)는 앱 타깃에만 둔다. 모듈은 `MellowError` 열거형만 던진다.
- 모든 공개 타입은 `Sendable`. `swift format lint --strict` 경고 0.
- 모든 명령은 `export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`를 먼저 설정한 셸에서 실행한다. Command Line Tools에는 XCTest와 iOS SDK가 없다.
- 커밋 메시지는 저장소 관례(한국어 Conventional Commits, 예: `refactor(editing): …`)를 따르고 마지막 줄에 `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`를 붙인다.
- 각 Task 끝에 `swift test` 또는 지정된 xcodebuild 명령이 통과해야 다음 Task로 간다.

## Review Focus

스펙이 암시하지만 어느 Task의 테스트도 직접 다루지 않던 입력. 각 줄의 테스트를 소유 Task에 추가했다.

1. **v1 세션의 `undoHistory`가 평탄 배열(`[키, 값, …]`)로 저장돼 있다.** 디코더가 객체를 기대하면 출시본 사용자의 기록이 전부 사라진다. → Task 3 `testV1UndoHistoryFlatArrayDecodes`.
2. **v1 세션에서 `selectedID`가 가리키는 사진이 목록에 없다.** 첫 사진이 선택돼야 하고 앱이 빈 화면에 멈추면 안 된다. → Task 3 `testV1DanglingSelectionFallsBackToFirstPhoto`.
3. **사진 수 상한에 도달한 상태에서 가져오기.** 상한을 넘는 항목은 조용히 버려지지 않고 보고서에 남아야 한다. → Task 9 `testImportStopsAtCapacityAndReportsSkipped`.
4. **얼굴 분석은 성공했지만 얼굴이 0명인 사진에 `skinSmoothing > 0`으로 저장.** 분석 실패와 달리 오류가 아니라 색감만 적용된 결과를 저장해야 한다. → Task 6 `testRenderOriginalWithNoFacesAndSkinValueSucceeds`.
5. **내보내기 중 취소 후 같은 사진을 다시 저장.** 취소된 사진의 임시 파일이 남아 디스크를 채우면 안 되고, 재저장은 정상 동작해야 한다. → Task 9 `testCancelledExportCleansTemporaryFilesAndCanRunAgain`.

## 인터페이스 요약 (모든 Task가 공유하는 이름)

```swift
// MellowShared
public struct NormalizedPoint: Codable, Hashable, Sendable { public var x: Double; public var y: Double }
public struct NormalizedRect: Codable, Equatable, Sendable { public var x, y, width, height: Double }
public struct PhotoID: Hashable, Codable, Sendable { public let rawValue: UUID }
public struct ColorAdjustments: Codable, Equatable, Sendable   // exposure 0, contrast 1, saturation 1, warmth 0
public struct PortraitAdjustments: Codable, Equatable, Sendable // skinSmoothing 0, faceSlim 0, targetFace nil
public struct RetouchSpot / WarpStroke: Codable, Equatable, Sendable
public enum LocalEdit: Codable, Equatable, Sendable { case spot(RetouchSpot), warp(WarpStroke) } // "type" 판별자
public struct EditRecipe: Codable, Equatable, Sendable { color, portrait, operations; spots, warps, hasLocalEdits, dependsOnFaces, isDefault }
public struct PresetValues: Codable, Equatable, Sendable { color, portrait }
public struct Preset: Codable, Identifiable, Equatable, Sendable { id: UUID, name, values }
public enum BuiltInPresets { natural, cozy, clean, all }
public enum FaceLandmark: String, CaseIterable, Codable, Sendable
public struct FaceGeometry: Equatable, Sendable { boundingBox, landmarks: [FaceLandmark: [NormalizedPoint]], roll, yaw; bounds(of:) }
public enum MellowError: Error, Equatable, Sendable

// MellowEditing
public enum EditChange: Equatable, Sendable { exposure, contrast, saturation, warmth, skinSmoothing, faceSlim (Double), targetFace(Int?) }
public struct EditDocument: Equatable, Sendable { recipe, undoStack, redoStack; canUndo, canRedo, isGeometryLocked, hasEdits
    enum Rejection { geometryLocked }
    beginContinuousChange(), endContinuousChange(), set(_:) -> Rejection?, apply(_:), applyFromBatch(_:), appendLocalEdit(_:), undo(), redo(), reset() }
public enum EditingPolicy { historyLimit = 40 }

// MellowLibrary
public struct PhotoEntry: Identifiable, Equatable, Sendable { id: PhotoID, filename, displayName, document }
public struct SessionSnapshot: Equatable, Sendable { photos, selectedPhotoID, presets }
public protocol SessionStore: Sendable { load() throws -> SessionSnapshot?; save(_:) throws }
public final class JSONSessionStore: SessionStore { init(fileURL:); recoveryFileURL }
public struct WorkingCopyStore: Sendable { init(directory:); url(for:); adopt(temporaryFile:as:) -> String; remove(filename:) }
public enum LibraryPolicy { maxPhotos(physicalMemory:) }
@MainActor public final class ProjectSession (@Observable) { photos, selectedPhotoID, presets, selected, remainingCapacity, lastPersistenceError
    restore() throws, add(_:) throws, remove(_:) throws, edit(_:_:) -> Rejection?, applyToAll(from:), addPreset(named:values:), save() throws }

// MellowRendering
public struct RenderTuning: Sendable { …상수…; forCurrentDevice(physicalMemory:) }
public struct RenderContext: Sendable { extent, recipe, faces, targetFaces, tuning }
public protocol RenderStage: Sendable { name; apply(_:in:) throws -> CIImage }
public struct RenderPipeline: Sendable { init(stages:); standard; render(_:context:) throws -> CIImage }
public struct ImageMetadata: Sendable { pixelSize: CGSize }
public struct ImageLoader: Sendable { load(url:maxDimension:) throws -> CIImage; metadata(url:) throws -> ImageMetadata }
public final class Renderer: @unchecked Sendable { makeCGImage(_:) throws -> CGImage }
public protocol FaceAnalyzer: Sendable { analyze(_:) throws -> [FaceGeometry] }
public struct VisionFaceAnalyzer: FaceAnalyzer
public struct PreparedPhoto: Sendable { pixelSize, thumbnail: CGImage, faces, faceAnalysisFailure: MellowError? }
public actor PhotoPipeline { init(analyzer:tuning:); prepare(_:at:), preview(_:recipe:), renderOriginal(_:at:recipe:maxDimension:), evict(_:) }

// MellowExport
public enum ExportFormat: String, CaseIterable, Codable, Sendable { jpeg, png; fileExtension }
public struct ExportOptions: Equatable, Sendable { format, fullResolution, quality; static defaultMaxDimension = 4096 }
public struct Exporter: Sendable { init(renderer:); write(_:to:format:quality:) throws }
public enum FileNamingPolicy { availableURL(in:stem:fileExtension:exists:) }
public protocol ExportDestination: Sendable { publish(fileURL:suggestedName:) async throws }
```

---

### Task 1: `apple/` 패키지 골격과 MellowShared

**Files:**
- Create: `apple/Package.swift`
- Create: `apple/.swift-format`
- Create: `apple/Sources/MellowShared/API/Geometry.swift` (NormalizedPoint, NormalizedRect, PhotoID)
- Create: `apple/Sources/MellowShared/API/Adjustments.swift` (ColorAdjustments, PortraitAdjustments)
- Create: `apple/Sources/MellowShared/API/LocalEdit.swift` (RetouchSpot, WarpStroke, LocalEdit)
- Create: `apple/Sources/MellowShared/API/EditRecipe.swift`
- Create: `apple/Sources/MellowShared/API/Preset.swift` (PresetValues, Preset, BuiltInPresets)
- Create: `apple/Sources/MellowShared/API/FaceGeometry.swift` (FaceLandmark, FaceGeometry)
- Create: `apple/Sources/MellowShared/API/MellowError.swift`
- Test: `apple/Tests/MellowSharedTests/EditRecipeCodingTests.swift`
- Test: `apple/Tests/MellowSharedTests/FaceGeometryTests.swift`
- Modify: `.gitignore` (`apple/.build/`, `apple/*.xcodeproj/xcuserdata/` 추가)

**Interfaces:**
- Consumes: 없음.
- Produces: 인터페이스 요약의 MellowShared 전부. 이후 모든 Task가 import한다.

- [ ] **Step 1: 패키지 매니페스트와 포맷 설정 작성**

`apple/Package.swift`:

```swift
// swift-tools-version: 5.9
import PackageDescription

let strictConcurrency: [SwiftSetting] = [.enableExperimentalFeature("StrictConcurrency=complete")]

let package = Package(
    name: "MellowKit",
    platforms: [.macOS(.v14), .iOS(.v17)],
    products: [
        .library(name: "MellowShared", targets: ["MellowShared"]),
        .library(name: "MellowEditing", targets: ["MellowEditing"]),
        .library(name: "MellowLibrary", targets: ["MellowLibrary"]),
        .library(name: "MellowRendering", targets: ["MellowRendering"]),
        .library(name: "MellowExport", targets: ["MellowExport"]),
    ],
    targets: [
        .target(name: "MellowShared", swiftSettings: strictConcurrency),
        .target(name: "MellowEditing", dependencies: ["MellowShared"], swiftSettings: strictConcurrency),
        .target(name: "MellowLibrary", dependencies: ["MellowShared", "MellowEditing"], swiftSettings: strictConcurrency),
        .target(name: "MellowRendering", dependencies: ["MellowShared"], swiftSettings: strictConcurrency),
        .target(name: "MellowExport", dependencies: ["MellowShared", "MellowRendering"], swiftSettings: strictConcurrency),
        .testTarget(name: "MellowSharedTests", dependencies: ["MellowShared"]),
        .testTarget(name: "MellowEditingTests", dependencies: ["MellowEditing"]),
        .testTarget(name: "MellowLibraryTests", dependencies: ["MellowLibrary"], resources: [.copy("Fixtures")]),
        .testTarget(name: "MellowRenderingTests", dependencies: ["MellowRendering"], resources: [.copy("Fixtures")]),
        .testTarget(name: "MellowExportTests", dependencies: ["MellowExport"]),
    ]
)
```

Task 1에서는 Editing·Library·Rendering·Export 타깃 폴더에 빈 `Placeholder.swift`(`// Filled in later tasks.` 한 줄)를 두어 매니페스트가 컴파일되게 한다. 각 모듈의 Task가 이 파일을 삭제한다. 테스트 타깃도 같은 방식으로 `PlaceholderTests.swift`(빈 `XCTestCase` 하위 클래스)를 둔다. `Fixtures` 폴더는 빈 `.gitkeep`으로 만든다.

`apple/.swift-format`:

```json
{
  "version": 1,
  "lineLength": 120,
  "indentation": { "spaces": 4 },
  "maximumBlankLines": 1,
  "respectsExistingLineBreaks": true,
  "lineBreakBeforeEachArgument": false,
  "rules": {
    "AlwaysUseLowerCamelCase": true,
    "DoNotUseSemicolons": true,
    "NoBlockComments": true,
    "OrderedImports": true,
    "UseEarlyExits": true,
    "NeverForceUnwrap": false,
    "NeverUseImplicitlyUnwrappedOptionals": false
  }
}
```

- [ ] **Step 2: 실패하는 테스트 작성**

`apple/Tests/MellowSharedTests/EditRecipeCodingTests.swift`:

```swift
import XCTest
@testable import MellowShared

final class EditRecipeCodingTests: XCTestCase {
    func testDefaultRecipeIsDefaultAndNeedsNoFaces() {
        let recipe = EditRecipe()
        XCTAssertTrue(recipe.isDefault)
        XCTAssertFalse(recipe.hasLocalEdits)
        XCTAssertFalse(recipe.dependsOnFaces)
    }

    func testRoundTripPreservesOperationsOrderAndSchemaVersion() throws {
        var recipe = EditRecipe()
        recipe.color.exposure = 0.4
        recipe.portrait.skinSmoothing = 0.3
        recipe.portrait.targetFace = 1
        recipe.operations = [
            .spot(RetouchSpot(x: 0.5, y: 0.4, sourceX: 0.45, sourceY: 0.4, radius: 0.02)),
            .warp(WarpStroke(x: 0.5, y: 0.4, dx: 0.01, dy: 0, radius: 0.08)),
        ]
        let data = try JSONEncoder().encode(recipe)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(json["schemaVersion"] as? Int, 2)
        let operations = try XCTUnwrap(json["operations"] as? [[String: Any]])
        XCTAssertEqual(operations[0]["type"] as? String, "spot")
        XCTAssertEqual(operations[1]["type"] as? String, "warp")
        XCTAssertEqual(operations[0]["sourceX"] as? Double, 0.45)
        let decoded = try JSONDecoder().decode(EditRecipe.self, from: data)
        XCTAssertEqual(decoded, recipe)
        XCTAssertTrue(decoded.dependsOnFaces)
        XCTAssertTrue(decoded.hasLocalEdits)
    }

    func testMissingKeysDecodeToDefaults() throws {
        let json = #"{"schemaVersion":2,"color":{"exposure":0.2}}"#
        let decoded = try JSONDecoder().decode(EditRecipe.self, from: Data(json.utf8))
        XCTAssertEqual(decoded.color.exposure, 0.2)
        XCTAssertEqual(decoded.color.contrast, 1)
        XCTAssertEqual(decoded.portrait, PortraitAdjustments())
        XCTAssertTrue(decoded.operations.isEmpty)
    }

    func testUnknownOperationTypeFailsLoudly() {
        let json = #"{"schemaVersion":2,"operations":[{"type":"glitter","x":0,"y":0}]}"#
        XCTAssertThrowsError(try JSONDecoder().decode(EditRecipe.self, from: Data(json.utf8)))
    }

    func testBuiltInPresetsMatchShippedIPhoneValues() {
        XCTAssertEqual(BuiltInPresets.all.map(\.name), ["내추럴", "포근한", "클린"])
        XCTAssertEqual(BuiltInPresets.cozy.values.color.warmth, 0.25)
        XCTAssertEqual(BuiltInPresets.cozy.values.portrait.skinSmoothing, 0.3)
        XCTAssertEqual(BuiltInPresets.clean.values.color.contrast, 1.05)
    }
}
```

`apple/Tests/MellowSharedTests/FaceGeometryTests.swift`:

```swift
import XCTest
@testable import MellowShared

final class FaceGeometryTests: XCTestCase {
    func testBoundsOfLandmarkReturnsEnclosingRectInImageSpace() {
        let face = FaceGeometry(
            boundingBox: NormalizedRect(x: 0.2, y: 0.1, width: 0.6, height: 0.8),
            landmarks: [.leftEye: [NormalizedPoint(x: 0.3, y: 0.6), NormalizedPoint(x: 0.4, y: 0.65)]])
        let bounds = face.bounds(of: .leftEye)
        XCTAssertEqual(bounds, NormalizedRect(x: 0.3, y: 0.6, width: 0.1, height: 0.05))
        XCTAssertNil(face.bounds(of: .outerLips), "없는 랜드마크는 nil")
    }

    func testNormalizedRectConvertsToAndFromCGRect() {
        let rect = NormalizedRect(cgRect: CGRect(x: 0.1, y: 0.2, width: 0.3, height: 0.4))
        XCTAssertEqual(rect.cgRect, CGRect(x: 0.1, y: 0.2, width: 0.3, height: 0.4))
        XCTAssertEqual(rect.midX, 0.25, accuracy: 1e-9)
    }
}
```

- [ ] **Step 3: 테스트가 실패하는지 확인**

Run: `cd apple && swift test --filter MellowSharedTests`
Expected: 컴파일 실패 (`EditRecipe` 없음).

- [ ] **Step 4: MellowShared 구현**

`apple/Sources/MellowShared/API/Geometry.swift`:

```swift
import CoreGraphics
import Foundation

/// 방향 보정된 이미지 기준 정규화 좌표. 원점은 왼쪽 아래.
public struct NormalizedPoint: Codable, Hashable, Sendable {
    public var x: Double
    public var y: Double

    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }
}

public struct NormalizedRect: Codable, Equatable, Sendable {
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }

    public init(cgRect: CGRect) {
        self.init(x: cgRect.minX, y: cgRect.minY, width: cgRect.width, height: cgRect.height)
    }

    public var cgRect: CGRect { CGRect(x: x, y: y, width: width, height: height) }
    public var minX: Double { x }
    public var minY: Double { y }
    public var maxX: Double { x + width }
    public var maxY: Double { y + height }
    public var midX: Double { x + width / 2 }
    public var midY: Double { y + height / 2 }
}

public struct PhotoID: Hashable, Codable, Sendable {
    public let rawValue: UUID

    public init() {
        rawValue = UUID()
    }

    public init(rawValue: UUID) {
        self.rawValue = rawValue
    }

    public init(from decoder: Decoder) throws {
        rawValue = try decoder.singleValueContainer().decode(UUID.self)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}
```

`apple/Sources/MellowShared/API/Adjustments.swift`:

```swift
import Foundation

public struct ColorAdjustments: Codable, Equatable, Sendable {
    public var exposure: Double = 0
    public var contrast: Double = 1
    public var saturation: Double = 1
    public var warmth: Double = 0

    public init(exposure: Double = 0, contrast: Double = 1, saturation: Double = 1, warmth: Double = 0) {
        self.exposure = exposure
        self.contrast = contrast
        self.saturation = saturation
        self.warmth = warmth
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        exposure = try container.decodeIfPresent(Double.self, forKey: .exposure) ?? 0
        contrast = try container.decodeIfPresent(Double.self, forKey: .contrast) ?? 1
        saturation = try container.decodeIfPresent(Double.self, forKey: .saturation) ?? 1
        warmth = try container.decodeIfPresent(Double.self, forKey: .warmth) ?? 0
    }

    public var isDefault: Bool { self == ColorAdjustments() }
}

public struct PortraitAdjustments: Codable, Equatable, Sendable {
    public var skinSmoothing: Double = 0
    public var faceSlim: Double = 0
    /// 왼쪽부터 센 얼굴 인덱스. nil이면 모든 얼굴.
    public var targetFace: Int? = nil

    public init(skinSmoothing: Double = 0, faceSlim: Double = 0, targetFace: Int? = nil) {
        self.skinSmoothing = skinSmoothing
        self.faceSlim = faceSlim
        self.targetFace = targetFace
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        skinSmoothing = try container.decodeIfPresent(Double.self, forKey: .skinSmoothing) ?? 0
        faceSlim = try container.decodeIfPresent(Double.self, forKey: .faceSlim) ?? 0
        targetFace = try container.decodeIfPresent(Int.self, forKey: .targetFace)
    }

    public var dependsOnFaces: Bool { skinSmoothing > 0 || faceSlim > 0 }
}
```

`apple/Sources/MellowShared/API/LocalEdit.swift`:

```swift
import Foundation

public struct RetouchSpot: Codable, Equatable, Sendable {
    public var x: Double
    public var y: Double
    public var sourceX: Double
    public var sourceY: Double
    public var radius: Double

    public init(x: Double, y: Double, sourceX: Double, sourceY: Double, radius: Double) {
        self.x = x
        self.y = y
        self.sourceX = sourceX
        self.sourceY = sourceY
        self.radius = radius
    }
}

public struct WarpStroke: Codable, Equatable, Sendable {
    public var x: Double
    public var y: Double
    public var dx: Double
    public var dy: Double
    public var radius: Double

    public init(x: Double, y: Double, dx: Double, dy: Double, radius: Double) {
        self.x = x
        self.y = y
        self.dx = dx
        self.dy = dy
        self.radius = radius
    }
}

/// 사용자가 기록한 순서대로 재생되는 수동 편집.
public enum LocalEdit: Equatable, Sendable {
    case spot(RetouchSpot)
    case warp(WarpStroke)
}

extension LocalEdit: Codable {
    private enum CodingKeys: String, CodingKey {
        case type
    }

    private enum Kind: String, Codable {
        case spot
        case warp
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(Kind.self, forKey: .type) {
        case .spot:
            self = .spot(try RetouchSpot(from: decoder))
        case .warp:
            self = .warp(try WarpStroke(from: decoder))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .spot(let spot):
            try container.encode(Kind.spot, forKey: .type)
            try spot.encode(to: encoder)
        case .warp(let stroke):
            try container.encode(Kind.warp, forKey: .type)
            try stroke.encode(to: encoder)
        }
    }

    public var numericValues: [Double] {
        switch self {
        case .spot(let spot):
            return [spot.x, spot.y, spot.sourceX, spot.sourceY, spot.radius]
        case .warp(let stroke):
            return [stroke.x, stroke.y, stroke.dx, stroke.dy, stroke.radius]
        }
    }
}
```

`apple/Sources/MellowShared/API/EditRecipe.swift`:

```swift
import Foundation

/// 사진 한 장의 보정 레시피. shared/recipe-schema/edit-recipe.v2.schema.json과 같은 형식.
public struct EditRecipe: Codable, Equatable, Sendable {
    public static let currentSchemaVersion = 2

    public var color = ColorAdjustments()
    public var portrait = PortraitAdjustments()
    public var operations: [LocalEdit] = []

    public init(color: ColorAdjustments = .init(), portrait: PortraitAdjustments = .init(), operations: [LocalEdit] = []) {
        self.color = color
        self.portrait = portrait
        self.operations = operations
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case color
        case portrait
        case operations
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        color = try container.decodeIfPresent(ColorAdjustments.self, forKey: .color) ?? .init()
        portrait = try container.decodeIfPresent(PortraitAdjustments.self, forKey: .portrait) ?? .init()
        operations = try container.decodeIfPresent([LocalEdit].self, forKey: .operations) ?? []
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(Self.currentSchemaVersion, forKey: .schemaVersion)
        try container.encode(color, forKey: .color)
        try container.encode(portrait, forKey: .portrait)
        try container.encode(operations, forKey: .operations)
    }

    public var spots: [RetouchSpot] {
        operations.compactMap { edit in
            if case .spot(let spot) = edit { return spot }
            return nil
        }
    }

    public var warps: [WarpStroke] {
        operations.compactMap { edit in
            if case .warp(let stroke) = edit { return stroke }
            return nil
        }
    }

    public var hasLocalEdits: Bool { !operations.isEmpty }
    public var dependsOnFaces: Bool { portrait.dependsOnFaces }
    public var isDefault: Bool { self == EditRecipe() }

    /// 렌더 전 검증용. 비유한수가 하나라도 있으면 false.
    public var allValuesFinite: Bool {
        let scalars = [color.exposure, color.contrast, color.saturation, color.warmth, portrait.skinSmoothing, portrait.faceSlim]
        let locals = operations.flatMap(\.numericValues)
        return (scalars + locals).allSatisfy(\.isFinite)
    }
}
```

`apple/Sources/MellowShared/API/Preset.swift`:

```swift
import Foundation

public struct PresetValues: Codable, Equatable, Sendable {
    public var color: ColorAdjustments
    public var portrait: PortraitAdjustments

    public init(color: ColorAdjustments = .init(), portrait: PortraitAdjustments = .init()) {
        self.color = color
        self.portrait = portrait
    }
}

public struct Preset: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID
    public var name: String
    public var values: PresetValues

    public init(id: UUID = UUID(), name: String, values: PresetValues) {
        self.id = id
        self.name = name
        self.values = values
    }
}

/// iPhone 출시본 값. Mac 앱이 쓰던 다른 값은 폐기했다.
public enum BuiltInPresets {
    public static let natural = Preset(
        id: UUID(uuidString: "A0000000-0000-0000-0000-000000000001")!,
        name: "내추럴",
        values: PresetValues(color: ColorAdjustments(exposure: 0.1), portrait: PortraitAdjustments(skinSmoothing: 0.2)))
    public static let cozy = Preset(
        id: UUID(uuidString: "A0000000-0000-0000-0000-000000000002")!,
        name: "포근한",
        values: PresetValues(
            color: ColorAdjustments(exposure: 0.15, saturation: 0.92, warmth: 0.25),
            portrait: PortraitAdjustments(skinSmoothing: 0.3)))
    public static let clean = Preset(
        id: UUID(uuidString: "A0000000-0000-0000-0000-000000000003")!,
        name: "클린",
        values: PresetValues(color: ColorAdjustments(exposure: 0.2, contrast: 1.05, warmth: -0.1)))
    public static let all: [Preset] = [natural, cozy, clean]
}
```

`apple/Sources/MellowShared/API/FaceGeometry.swift`:

```swift
import Foundation

/// Vision VNFaceLandmarks2D의 영역 이름과 1:1.
public enum FaceLandmark: String, CaseIterable, Codable, Sendable {
    case faceContour
    case leftEye
    case rightEye
    case leftEyebrow
    case rightEyebrow
    case nose
    case noseCrest
    case medianLine
    case outerLips
    case innerLips
    case leftPupil
    case rightPupil
}

/// 영속화하지 않는다. 사진을 준비할 때마다 다시 계산한다.
public struct FaceGeometry: Equatable, Sendable {
    public var boundingBox: NormalizedRect
    /// 이미지 좌표계의 점. 얼굴 상대 좌표가 아니다.
    public var landmarks: [FaceLandmark: [NormalizedPoint]]
    public var roll: Double?
    public var yaw: Double?

    public init(boundingBox: NormalizedRect, landmarks: [FaceLandmark: [NormalizedPoint]] = [:], roll: Double? = nil, yaw: Double? = nil) {
        self.boundingBox = boundingBox
        self.landmarks = landmarks
        self.roll = roll
        self.yaw = yaw
    }

    public func bounds(of landmark: FaceLandmark) -> NormalizedRect? {
        guard let points = landmarks[landmark], let first = points.first else { return nil }
        var minX = first.x
        var maxX = first.x
        var minY = first.y
        var maxY = first.y
        for point in points.dropFirst() {
            minX = min(minX, point.x)
            maxX = max(maxX, point.x)
            minY = min(minY, point.y)
            maxY = max(maxY, point.y)
        }
        return NormalizedRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }
}
```

`apple/Sources/MellowShared/API/MellowError.swift`:

```swift
import Foundation

/// 모듈이 던지는 유일한 오류 타입. 사용자 문구는 앱 타깃이 매핑한다.
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

- [ ] **Step 5: 테스트 통과 확인**

Run: `cd apple && swift test --filter MellowSharedTests`
Expected: 7 tests PASS.

Run: `cd apple && swift format lint --strict --recursive Sources Tests`
Expected: 출력 없음(경고 0). 경고가 있으면 `swift format --in-place --recursive Sources Tests`로 고친다.

- [ ] **Step 6: 커밋**

```bash
git add apple .gitignore
git commit -m "refactor(shared): MellowKit 패키지 골격과 공유 커널 타입 추가

레시피 v2, 프리셋, 얼굴 기하, 오류 타입을 플랫폼 독립 모듈로 분리해
이후 편집·렌더·앱 모듈이 같은 계약을 쓰게 한다.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 2: MellowEditing — EditDocument와 편집 규칙

**Files:**
- Delete: `apple/Sources/MellowEditing/Placeholder.swift`, `apple/Tests/MellowEditingTests/PlaceholderTests.swift`
- Create: `apple/Sources/MellowEditing/API/EditChange.swift`
- Create: `apple/Sources/MellowEditing/API/EditDocument.swift`
- Create: `apple/Sources/MellowEditing/API/EditingPolicy.swift`
- Test: `apple/Tests/MellowEditingTests/EditDocumentTests.swift`

**Interfaces:**
- Consumes: `EditRecipe`, `PresetValues`, `LocalEdit` (Task 1).
- Produces: `EditChange`, `EditDocument`(`recipe`, `undoStack`, `redoStack`, `canUndo`, `canRedo`, `isGeometryLocked`, `hasEdits`, `Rejection`, `beginContinuousChange()`, `endContinuousChange()`, `set(_:) -> Rejection?`, `apply(_:)`, `applyFromBatch(_:)`, `appendLocalEdit(_:)`, `undo()`, `redo()`, `reset()`), `EditingPolicy.historyLimit`.

- [ ] **Step 1: 실패하는 테스트 작성**

`apple/Tests/MellowEditingTests/EditDocumentTests.swift`:

```swift
import MellowShared
import XCTest
@testable import MellowEditing

final class EditDocumentTests: XCTestCase {
    func testSetCheckpointsOnceAndUndoRestores() {
        var document = EditDocument()
        XCTAssertNil(document.set(.exposure(0.4)))
        XCTAssertEqual(document.recipe.color.exposure, 0.4)
        XCTAssertTrue(document.canUndo)
        document.undo()
        XCTAssertEqual(document.recipe.color.exposure, 0)
        XCTAssertTrue(document.canRedo)
        document.redo()
        XCTAssertEqual(document.recipe.color.exposure, 0.4)
    }

    func testContinuousChangeCheckpointsOnlyAtBegin() {
        var document = EditDocument()
        document.beginContinuousChange()
        document.set(.exposure(0.1))
        document.set(.exposure(0.2))
        document.set(.exposure(0.3))
        document.endContinuousChange()
        XCTAssertEqual(document.undoStack.count, 1)
        document.undo()
        XCTAssertEqual(document.recipe.color.exposure, 0)
    }

    func testIdenticalRecipeIsNotCheckpointedTwice() {
        var document = EditDocument()
        document.set(.exposure(0.4))
        document.set(.exposure(0.4))
        XCTAssertEqual(document.undoStack.count, 1)
    }

    func testNewEditClearsRedo() {
        var document = EditDocument()
        document.set(.exposure(0.4))
        document.undo()
        document.set(.contrast(1.1))
        XCTAssertFalse(document.canRedo)
    }

    func testHistoryIsCappedAtPolicyLimit() {
        var document = EditDocument()
        for step in 1...(EditingPolicy.historyLimit + 10) {
            document.set(.exposure(Double(step) / 100))
        }
        XCTAssertEqual(document.undoStack.count, EditingPolicy.historyLimit)
    }

    func testLocalEditLocksFaceSlimAndTargetFace() {
        var document = EditDocument()
        document.set(.faceSlim(0.2))
        document.set(.targetFace(1))
        document.appendLocalEdit(.spot(RetouchSpot(x: 0.5, y: 0.4, sourceX: 0.4, sourceY: 0.4, radius: 0.02)))
        XCTAssertTrue(document.isGeometryLocked)
        XCTAssertEqual(document.set(.faceSlim(0.9)), .geometryLocked)
        XCTAssertEqual(document.set(.targetFace(nil)), .geometryLocked)
        XCTAssertEqual(document.recipe.portrait.faceSlim, 0.2)
        XCTAssertEqual(document.recipe.portrait.targetFace, 1)
        XCTAssertNil(document.set(.skinSmoothing(0.5)))
        document.undo()
        XCTAssertFalse(document.isGeometryLocked)
    }

    func testPresetPreservesFaceSlimWhenLocked() {
        var document = EditDocument()
        document.set(.faceSlim(0.2))
        document.appendLocalEdit(.warp(WarpStroke(x: 0.5, y: 0.5, dx: 0.01, dy: 0, radius: 0.1)))
        let preset = PresetValues(color: ColorAdjustments(exposure: 0.5), portrait: PortraitAdjustments(faceSlim: 0.7))
        document.apply(preset)
        XCTAssertEqual(document.recipe.color.exposure, 0.5)
        XCTAssertEqual(document.recipe.portrait.faceSlim, 0.2)
        XCTAssertEqual(document.recipe.operations.count, 1)
    }

    func testPresetReplacesEverythingWhenUnlocked() {
        var document = EditDocument()
        document.set(.targetFace(2))
        document.apply(PresetValues(portrait: PortraitAdjustments(faceSlim: 0.7)))
        XCTAssertEqual(document.recipe.portrait.faceSlim, 0.7)
        XCTAssertNil(document.recipe.portrait.targetFace, "프리셋은 대상 얼굴을 갖지 않으므로 전체 얼굴로 돌아간다")
    }

    func testBatchApplyKeepsLockedGeometryAndResetsTargetOtherwise() {
        var locked = EditDocument()
        locked.set(.faceSlim(0.2))
        locked.set(.targetFace(1))
        locked.appendLocalEdit(.spot(RetouchSpot(x: 0.5, y: 0.4, sourceX: 0.4, sourceY: 0.4, radius: 0.02)))
        var unlocked = EditDocument()
        unlocked.set(.targetFace(0))
        let values = PresetValues(color: ColorAdjustments(exposure: 0.3), portrait: PortraitAdjustments(faceSlim: 0.9, targetFace: 3))
        locked.applyFromBatch(values)
        unlocked.applyFromBatch(values)
        XCTAssertEqual(locked.recipe.portrait.faceSlim, 0.2)
        XCTAssertEqual(locked.recipe.portrait.targetFace, 1)
        XCTAssertEqual(locked.recipe.color.exposure, 0.3)
        XCTAssertEqual(unlocked.recipe.portrait.faceSlim, 0.9)
        XCTAssertNil(unlocked.recipe.portrait.targetFace)
        XCTAssertTrue(locked.canUndo)
        XCTAssertTrue(unlocked.canUndo)
    }

    func testResetIsUndoable() {
        var document = EditDocument()
        document.set(.exposure(0.4))
        document.appendLocalEdit(.warp(WarpStroke(x: 0.5, y: 0.5, dx: 0.01, dy: 0, radius: 0.1)))
        document.reset()
        XCTAssertTrue(document.recipe.isDefault)
        document.undo()
        XCTAssertEqual(document.recipe.operations.count, 1)
    }
}
```

- [ ] **Step 2: 실패 확인**

Run: `cd apple && swift test --filter MellowEditingTests`
Expected: 컴파일 실패 (`EditDocument` 없음).

- [ ] **Step 3: 구현**

`apple/Sources/MellowEditing/API/EditingPolicy.swift`:

```swift
public enum EditingPolicy {
    /// 사진 한 장당 보관하는 실행 취소 단계 수.
    public static let historyLimit = 40
}
```

`apple/Sources/MellowEditing/API/EditChange.swift`:

```swift
public enum EditChange: Equatable, Sendable {
    case exposure(Double)
    case contrast(Double)
    case saturation(Double)
    case warmth(Double)
    case skinSmoothing(Double)
    case faceSlim(Double)
    case targetFace(Int?)

    /// 수동 편집이 있는 동안 바꿀 수 없는 변경.
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

`apple/Sources/MellowEditing/API/EditDocument.swift`:

```swift
import MellowShared

/// 사진 한 장의 편집 상태. 체크포인트·잠금·보존 규칙은 전부 여기에만 있다.
public struct EditDocument: Equatable, Sendable {
    public enum Rejection: Equatable, Sendable {
        case geometryLocked
    }

    public private(set) var recipe: EditRecipe
    public private(set) var undoStack: [EditRecipe]
    public private(set) var redoStack: [EditRecipe]
    private var isContinuousChange = false

    public init(recipe: EditRecipe = EditRecipe(), undoStack: [EditRecipe] = [], redoStack: [EditRecipe] = []) {
        self.recipe = recipe
        self.undoStack = undoStack
        self.redoStack = redoStack
    }

    public var canUndo: Bool { !undoStack.isEmpty }
    public var canRedo: Bool { !redoStack.isEmpty }
    public var hasEdits: Bool { !recipe.isDefault }
    /// 수동 편집 좌표가 어긋나지 않도록 얼굴 형태와 대상 얼굴을 고정한다.
    public var isGeometryLocked: Bool { recipe.hasLocalEdits }

    public mutating func beginContinuousChange() {
        checkpoint()
        isContinuousChange = true
    }

    public mutating func endContinuousChange() {
        isContinuousChange = false
    }

    @discardableResult
    public mutating func set(_ change: EditChange) -> Rejection? {
        if change.affectsGeometry, isGeometryLocked {
            return .geometryLocked
        }
        checkpointUnlessContinuous()
        switch change {
        case .exposure(let value): recipe.color.exposure = value
        case .contrast(let value): recipe.color.contrast = value
        case .saturation(let value): recipe.color.saturation = value
        case .warmth(let value): recipe.color.warmth = value
        case .skinSmoothing(let value): recipe.portrait.skinSmoothing = value
        case .faceSlim(let value): recipe.portrait.faceSlim = value
        case .targetFace(let index): recipe.portrait.targetFace = index
        }
        return nil
    }

    /// 사용자가 고른 프리셋. 잠긴 사진은 얼굴 형태 값을 유지한다.
    public mutating func apply(_ values: PresetValues) {
        checkpoint()
        var portrait = values.portrait
        if isGeometryLocked {
            portrait.faceSlim = recipe.portrait.faceSlim
            portrait.targetFace = recipe.portrait.targetFace
        }
        recipe.color = values.color
        recipe.portrait = portrait
    }

    /// 다른 사진의 설정을 일괄 복사. 잠기지 않은 사진은 대상 얼굴을 전체로 되돌린다.
    public mutating func applyFromBatch(_ values: PresetValues) {
        checkpoint()
        var portrait = values.portrait
        if isGeometryLocked {
            portrait.faceSlim = recipe.portrait.faceSlim
            portrait.targetFace = recipe.portrait.targetFace
        } else {
            portrait.targetFace = nil
        }
        recipe.color = values.color
        recipe.portrait = portrait
    }

    public mutating func appendLocalEdit(_ edit: LocalEdit) {
        checkpoint()
        recipe.operations.append(edit)
    }

    public mutating func undo() {
        guard let previous = undoStack.popLast() else { return }
        redoStack.append(recipe)
        recipe = previous
    }

    public mutating func redo() {
        guard let next = redoStack.popLast() else { return }
        undoStack.append(recipe)
        recipe = next
    }

    public mutating func reset() {
        checkpoint()
        recipe = EditRecipe()
    }

    private mutating func checkpointUnlessContinuous() {
        if !isContinuousChange {
            checkpoint()
        }
    }

    private mutating func checkpoint() {
        if undoStack.last != recipe {
            undoStack.append(recipe)
        }
        if undoStack.count > EditingPolicy.historyLimit {
            undoStack.removeFirst(undoStack.count - EditingPolicy.historyLimit)
        }
        redoStack.removeAll()
    }
}
```

`Equatable` 합성에 `isContinuousChange`가 끼면 안 되므로 `==`를 직접 구현한다: `recipe`, `undoStack`, `redoStack`만 비교.

- [ ] **Step 4: 통과 확인**

Run: `cd apple && swift test --filter MellowEditingTests`
Expected: 10 tests PASS.

- [ ] **Step 5: 커밋**

```bash
git add apple/Sources/MellowEditing apple/Tests/MellowEditingTests
git commit -m "refactor(editing): 편집 규칙을 EditDocument 한 곳으로 모음

실행 취소, 얼굴 형태 잠금, 프리셋·일괄 적용 시 보존 규칙이 Mac과
iPhone 저장소에 따로 있던 것을 GPU 없이 테스트되는 값 타입으로 옮긴다.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 3: MellowLibrary — SessionFile DTO(v1·v2)와 마이그레이션

**Files:**
- Delete: `apple/Sources/MellowLibrary/Placeholder.swift`, `apple/Tests/MellowLibraryTests/PlaceholderTests.swift`
- Create: `apple/Sources/MellowLibrary/API/PhotoEntry.swift`
- Create: `apple/Sources/MellowLibrary/API/SessionSnapshot.swift`
- Create: `apple/Sources/MellowLibrary/Infrastructure/SessionFile.swift` (v2 DTO)
- Create: `apple/Sources/MellowLibrary/Infrastructure/SessionFileV1.swift` (v1 DTO)
- Create: `apple/Sources/MellowLibrary/Infrastructure/SessionFileMapper.swift`
- Create: `shared/fixtures/session-v1.json` (아래 내용 그대로)
- Create: `apple/Tests/MellowLibraryTests/Fixtures/session-v1.json` (shared 파일의 복사본. 심볼릭 링크는 SwiftPM 리소스 복사에서 깨질 수 있으므로 복사한다)
- Test: `apple/Tests/MellowLibraryTests/SessionFileMigrationTests.swift`

**Interfaces:**
- Consumes: `EditDocument` (Task 2), `EditRecipe`, `Preset`, `PhotoID` (Task 1).
- Produces: `PhotoEntry(id:filename:displayName:document:)`, `SessionSnapshot(photos:selectedPhotoID:presets:)`, internal `SessionFile`, `SessionFileMapper.snapshot(from:)`, `SessionFileMapper.file(from:)`, `SessionFile.decode(_ data: Data) throws -> SessionFile` (v1·v2 자동 판별).

- [ ] **Step 1: v1 픽스처 저장**

`shared/fixtures/session-v1.json`은 기준 커밋 `1cbab20`의 `Sources/MellowCore/Models.swift`와 `iOS/MellowPhoto/MobileStore.swift`의 타입으로 실제 인코드한 결과다. **`undoHistory`·`redoHistory`가 객체가 아니라 평탄 배열인 것이 Swift `JSONEncoder`의 실제 동작이다.** 손으로 고치지 않는다.

```json
{
  "photos" : [
    {
      "filename" : "11111111-1111-1111-1111-111111111111.heic",
      "id" : "11111111-1111-1111-1111-111111111111",
      "name" : "사진 1",
      "recipe" : {
        "adjustments" : { "contrast" : 1, "exposure" : 0.4, "faceSlim" : 0.2, "saturation" : 1, "skin" : 0.3, "warmth" : 0 },
        "operations" : [
          { "spot" : { "_0" : { "radius" : 0.02, "sourceX" : 0.45, "sourceY" : 0.4, "x" : 0.5, "y" : 0.4 } } },
          { "warp" : { "_0" : { "dx" : 0.01, "dy" : 0, "radius" : 0.08, "x" : 0.5, "y" : 0.4 } } }
        ],
        "selectedFace" : 1
      }
    },
    {
      "filename" : "22222222-2222-2222-2222-222222222222.jpg",
      "id" : "22222222-2222-2222-2222-222222222222",
      "name" : "사진 2",
      "recipe" : {
        "adjustments" : { "contrast" : 1, "exposure" : 0, "faceSlim" : 0, "saturation" : 1, "skin" : 0, "warmth" : -0.1 },
        "operations" : [ ]
      }
    }
  ],
  "presets" : [
    {
      "adjustments" : { "contrast" : 1, "exposure" : 0.15, "faceSlim" : 0, "saturation" : 0.92, "skin" : 0.3, "warmth" : 0.25 },
      "id" : "33333333-3333-3333-3333-333333333333",
      "name" : "포근한"
    }
  ],
  "redoHistory" : [
    "11111111-1111-1111-1111-111111111111",
    [
      {
        "adjustments" : { "contrast" : 1, "exposure" : 0.6, "faceSlim" : 0.2, "saturation" : 1, "skin" : 0.3, "warmth" : 0 },
        "operations" : [
          { "spot" : { "_0" : { "radius" : 0.02, "sourceX" : 0.45, "sourceY" : 0.4, "x" : 0.5, "y" : 0.4 } } },
          { "warp" : { "_0" : { "dx" : 0.01, "dy" : 0, "radius" : 0.08, "x" : 0.5, "y" : 0.4 } } }
        ],
        "selectedFace" : 1
      }
    ]
  ],
  "selectedID" : "11111111-1111-1111-1111-111111111111",
  "undoHistory" : [
    "11111111-1111-1111-1111-111111111111",
    [
      { "adjustments" : { "contrast" : 1, "exposure" : 0, "faceSlim" : 0, "saturation" : 1, "skin" : 0, "warmth" : 0 }, "operations" : [ ] },
      { "adjustments" : { "contrast" : 1, "exposure" : 0.1, "faceSlim" : 0, "saturation" : 1, "skin" : 0, "warmth" : 0 }, "operations" : [ ] }
    ]
  ]
}
```

- [ ] **Step 2: 실패하는 테스트 작성**

`apple/Tests/MellowLibraryTests/SessionFileMigrationTests.swift`:

```swift
import MellowEditing
import MellowShared
import XCTest
@testable import MellowLibrary

final class SessionFileMigrationTests: XCTestCase {
    private func fixture(_ name: String) throws -> Data {
        let url = try XCTUnwrap(Bundle.module.url(forResource: name, withExtension: "json"))
        return try Data(contentsOf: url)
    }

    func testV1SessionDecodesToV2Snapshot() throws {
        let file = try SessionFile.decode(fixture("session-v1"))
        let snapshot = SessionFileMapper.snapshot(from: file)
        XCTAssertEqual(snapshot.photos.count, 2)
        let first = snapshot.photos[0]
        XCTAssertEqual(first.id.rawValue.uuidString, "11111111-1111-1111-1111-111111111111")
        XCTAssertEqual(first.filename, "11111111-1111-1111-1111-111111111111.heic")
        XCTAssertEqual(first.displayName, "사진 1")
        XCTAssertEqual(first.document.recipe.color.exposure, 0.4)
        XCTAssertEqual(first.document.recipe.portrait.skinSmoothing, 0.3)
        XCTAssertEqual(first.document.recipe.portrait.faceSlim, 0.2)
        XCTAssertEqual(first.document.recipe.portrait.targetFace, 1)
        XCTAssertEqual(first.document.recipe.operations, [
            .spot(RetouchSpot(x: 0.5, y: 0.4, sourceX: 0.45, sourceY: 0.4, radius: 0.02)),
            .warp(WarpStroke(x: 0.5, y: 0.4, dx: 0.01, dy: 0, radius: 0.08)),
        ])
        XCTAssertEqual(snapshot.photos[1].document.recipe.color.warmth, -0.1)
        XCTAssertEqual(snapshot.selectedPhotoID, first.id)
        XCTAssertEqual(snapshot.presets.count, 1)
        XCTAssertEqual(snapshot.presets[0].name, "포근한")
        XCTAssertEqual(snapshot.presets[0].values.portrait.skinSmoothing, 0.3)
        XCTAssertEqual(snapshot.presets[0].values.color.warmth, 0.25)
    }

    func testV1UndoHistoryFlatArrayDecodes() throws {
        let file = try SessionFile.decode(fixture("session-v1"))
        let snapshot = SessionFileMapper.snapshot(from: file)
        let first = snapshot.photos[0].document
        XCTAssertEqual(first.undoStack.count, 2)
        XCTAssertEqual(first.undoStack[1].color.exposure, 0.1)
        XCTAssertEqual(first.redoStack.count, 1)
        XCTAssertEqual(first.redoStack[0].color.exposure, 0.6)
        XCTAssertTrue(snapshot.photos[1].document.undoStack.isEmpty)
    }

    func testV1DanglingSelectionFallsBackToFirstPhoto() throws {
        var json = try XCTUnwrap(String(data: fixture("session-v1"), encoding: .utf8))
        json = json.replacingOccurrences(
            of: "\"selectedID\" : \"11111111-1111-1111-1111-111111111111\"",
            with: "\"selectedID\" : \"99999999-9999-9999-9999-999999999999\"")
        let snapshot = SessionFileMapper.snapshot(from: try SessionFile.decode(Data(json.utf8)))
        XCTAssertEqual(snapshot.selectedPhotoID, snapshot.photos[0].id)
    }

    func testV2RoundTripIsLossless() throws {
        var document = EditDocument()
        document.set(.exposure(0.3))
        document.appendLocalEdit(.warp(WarpStroke(x: 0.5, y: 0.5, dx: 0.01, dy: 0, radius: 0.1)))
        let entry = PhotoEntry(id: PhotoID(), filename: "a.heic", displayName: "A", document: document)
        let preset = Preset(name: "P", values: PresetValues(color: ColorAdjustments(exposure: 0.2)))
        let snapshot = SessionSnapshot(photos: [entry], selectedPhotoID: entry.id, presets: [preset])
        let data = try SessionFile.encode(SessionFileMapper.file(from: snapshot))
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(json["schemaVersion"] as? Int, 2)
        let restored = SessionFileMapper.snapshot(from: try SessionFile.decode(data))
        XCTAssertEqual(restored, snapshot)
    }

    func testV1DecodeNeverProducesSchemaVersion1OnEncode() throws {
        let file = try SessionFile.decode(fixture("session-v1"))
        let data = try SessionFile.encode(file)
        XCTAssertTrue(try XCTUnwrap(String(data: data, encoding: .utf8)).contains("\"schemaVersion\":2"))
    }
}
```

- [ ] **Step 3: 실패 확인**

Run: `cd apple && swift test --filter MellowLibraryTests`
Expected: 컴파일 실패.

- [ ] **Step 4: 구현**

`apple/Sources/MellowLibrary/API/PhotoEntry.swift`:

```swift
import MellowEditing
import MellowShared

public struct PhotoEntry: Identifiable, Equatable, Sendable {
    public let id: PhotoID
    /// 작업 사본 파일 이름. 디렉터리는 WorkingCopyStore가 안다.
    public let filename: String
    public var displayName: String
    public var document: EditDocument

    public init(id: PhotoID, filename: String, displayName: String, document: EditDocument = EditDocument()) {
        self.id = id
        self.filename = filename
        self.displayName = displayName
        self.document = document
    }
}
```

`apple/Sources/MellowLibrary/API/SessionSnapshot.swift`:

```swift
import MellowShared

public struct SessionSnapshot: Equatable, Sendable {
    public var photos: [PhotoEntry]
    public var selectedPhotoID: PhotoID?
    public var presets: [Preset]

    public init(photos: [PhotoEntry] = [], selectedPhotoID: PhotoID? = nil, presets: [Preset] = []) {
        self.photos = photos
        self.selectedPhotoID = selectedPhotoID
        self.presets = presets
    }
}
```

`apple/Sources/MellowLibrary/Infrastructure/SessionFile.swift`:

```swift
import Foundation
import MellowShared

/// 디스크 포맷 v2. 런타임 타입과 분리되어 있어 런타임이 바뀌어도 파일 호환을 따로 관리한다.
struct SessionFile: Codable, Equatable {
    static let currentSchemaVersion = 2

    struct Photo: Codable, Equatable {
        var id: UUID
        var filename: String
        var displayName: String
        var recipe: EditRecipe
        var undo: [EditRecipe]
        var redo: [EditRecipe]
    }

    var schemaVersion: Int = currentSchemaVersion
    var photos: [Photo]
    var selectedPhotoID: UUID?
    var presets: [Preset]

    private struct VersionProbe: Decodable {
        var schemaVersion: Int?
    }

    /// v1(출시본 iPhone 포맷)과 v2를 자동 판별한다.
    static func decode(_ data: Data) throws -> SessionFile {
        let decoder = JSONDecoder()
        let version = try decoder.decode(VersionProbe.self, from: data).schemaVersion ?? 1
        switch version {
        case 1:
            return try decoder.decode(SessionFileV1.self, from: data).upgraded()
        case currentSchemaVersion:
            return try decoder.decode(SessionFile.self, from: data)
        default:
            throw MellowError.sessionUnreadable
        }
    }

    static func encode(_ file: SessionFile) throws -> Data {
        var copy = file
        copy.schemaVersion = currentSchemaVersion
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(copy)
    }
}
```

`apple/Sources/MellowLibrary/Infrastructure/SessionFileV1.swift`:

```swift
import Foundation
import MellowShared

/// 출시된 iPhone 앱(MobileSession)의 포맷. 타입 구조를 그대로 흉내 내야 Swift가
/// `[UUID: [Recipe]]`를 평탄 배열로 저장한 것까지 올바르게 읽는다. 손으로 파싱하지 않는다.
struct SessionFileV1: Decodable {
    struct Adjustments: Decodable {
        var exposure: Double = 0
        var contrast: Double = 1
        var saturation: Double = 1
        var warmth: Double = 0
        var skin: Double = 0
        var faceSlim: Double = 0
    }

    struct Spot: Decodable {
        var x: Double
        var y: Double
        var sourceX: Double
        var sourceY: Double
        var radius: Double
    }

    struct Warp: Decodable {
        var x: Double
        var y: Double
        var dx: Double
        var dy: Double
        var radius: Double
    }

    /// Swift 합성 Codable의 enum 표현: {"spot":{"_0":{…}}}
    enum Operation: Decodable {
        case spot(Spot)
        case warp(Warp)

        private enum CodingKeys: String, CodingKey {
            case spot
            case warp
        }

        private enum PayloadKeys: String, CodingKey {
            case value = "_0"
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            if container.contains(.spot) {
                let payload = try container.nestedContainer(keyedBy: PayloadKeys.self, forKey: .spot)
                self = .spot(try payload.decode(Spot.self, forKey: .value))
            } else {
                let payload = try container.nestedContainer(keyedBy: PayloadKeys.self, forKey: .warp)
                self = .warp(try payload.decode(Warp.self, forKey: .value))
            }
        }
    }

    struct Recipe: Decodable {
        var adjustments = Adjustments()
        var operations: [Operation] = []
        var selectedFace: Int?
    }

    struct Photo: Decodable {
        var id: UUID
        var filename: String
        var name: String
        var recipe: Recipe
    }

    struct SavedPreset: Decodable {
        var id: UUID
        var name: String
        var adjustments: Adjustments
    }

    var photos: [Photo]
    var selectedID: UUID?
    var presets: [SavedPreset]
    var undoHistory: [UUID: [Recipe]]?
    var redoHistory: [UUID: [Recipe]]?

    func upgraded() -> SessionFile {
        let photos = self.photos.map { photo in
            SessionFile.Photo(
                id: photo.id,
                filename: photo.filename,
                displayName: photo.name,
                recipe: Self.recipe(photo.recipe),
                undo: (undoHistory?[photo.id] ?? []).map(Self.recipe),
                redo: (redoHistory?[photo.id] ?? []).map(Self.recipe))
        }
        let presets = self.presets.map { preset in
            Preset(id: preset.id, name: preset.name, values: Self.values(preset.adjustments))
        }
        let selected = photos.contains { $0.id == selectedID } ? selectedID : photos.first?.id
        return SessionFile(photos: photos, selectedPhotoID: selected, presets: presets)
    }

    private static func values(_ adjustments: Adjustments) -> PresetValues {
        PresetValues(
            color: ColorAdjustments(
                exposure: adjustments.exposure, contrast: adjustments.contrast,
                saturation: adjustments.saturation, warmth: adjustments.warmth),
            portrait: PortraitAdjustments(skinSmoothing: adjustments.skin, faceSlim: adjustments.faceSlim))
    }

    private static func recipe(_ recipe: Recipe) -> EditRecipe {
        var converted = values(recipe.adjustments)
        converted.portrait.targetFace = recipe.selectedFace
        let operations = recipe.operations.map { operation -> LocalEdit in
            switch operation {
            case .spot(let spot):
                return .spot(RetouchSpot(x: spot.x, y: spot.y, sourceX: spot.sourceX, sourceY: spot.sourceY, radius: spot.radius))
            case .warp(let warp):
                return .warp(WarpStroke(x: warp.x, y: warp.y, dx: warp.dx, dy: warp.dy, radius: warp.radius))
            }
        }
        return EditRecipe(color: converted.color, portrait: converted.portrait, operations: operations)
    }
}
```

`apple/Sources/MellowLibrary/Infrastructure/SessionFileMapper.swift`:

```swift
import MellowEditing
import MellowShared

enum SessionFileMapper {
    static func snapshot(from file: SessionFile) -> SessionSnapshot {
        let photos = file.photos.map { photo in
            PhotoEntry(
                id: PhotoID(rawValue: photo.id),
                filename: photo.filename,
                displayName: photo.displayName,
                document: EditDocument(recipe: photo.recipe, undoStack: photo.undo, redoStack: photo.redo))
        }
        let selected = file.selectedPhotoID.map(PhotoID.init(rawValue:))
        let validSelection = photos.contains { $0.id == selected } ? selected : photos.first?.id
        return SessionSnapshot(photos: photos, selectedPhotoID: validSelection, presets: file.presets)
    }

    static func file(from snapshot: SessionSnapshot) -> SessionFile {
        let photos = snapshot.photos.map { entry in
            SessionFile.Photo(
                id: entry.id.rawValue,
                filename: entry.filename,
                displayName: entry.displayName,
                recipe: entry.document.recipe,
                undo: entry.document.undoStack,
                redo: entry.document.redoStack)
        }
        return SessionFile(photos: photos, selectedPhotoID: snapshot.selectedPhotoID?.rawValue, presets: snapshot.presets)
    }
}
```

- [ ] **Step 5: 통과 확인**

Run: `cd apple && swift test --filter MellowLibraryTests`
Expected: 5 tests PASS.

- [ ] **Step 6: 커밋**

```bash
git add apple/Sources/MellowLibrary apple/Tests/MellowLibraryTests shared/fixtures/session-v1.json
git commit -m "refactor(library): 세션 파일 v2 포맷과 출시본 v1 마이그레이션 추가

디스크 포맷을 런타임 타입과 분리하고, iPhone 출시본이 평탄 배열로
저장한 실행 취소 기록까지 실제 인코드한 픽스처로 검증한다.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 4: MellowLibrary — 저장소·작업 사본·정책·ProjectSession

**Files:**
- Create: `apple/Sources/MellowLibrary/API/SessionStore.swift` (프로토콜)
- Create: `apple/Sources/MellowLibrary/API/JSONSessionStore.swift`
- Create: `apple/Sources/MellowLibrary/API/WorkingCopyStore.swift`
- Create: `apple/Sources/MellowLibrary/API/LibraryPolicy.swift`
- Create: `apple/Sources/MellowLibrary/API/ProjectSession.swift`
- Test: `apple/Tests/MellowLibraryTests/JSONSessionStoreTests.swift`
- Test: `apple/Tests/MellowLibraryTests/ProjectSessionTests.swift`
- Test: `apple/Tests/MellowLibraryTests/LibraryPolicyTests.swift`

**Interfaces:**
- Consumes: Task 3의 `SessionFile`, `SessionFileMapper`, `SessionSnapshot`, `PhotoEntry`.
- Produces: `SessionStore`, `JSONSessionStore(fileURL:)`, `WorkingCopyStore(directory:)`, `LibraryPolicy.maxPhotos(physicalMemory:)`, `ProjectSession(store:maxPhotos:)`와 그 메서드. Task 9·10·11이 쓴다.

- [ ] **Step 1: 실패하는 테스트 작성**

`apple/Tests/MellowLibraryTests/JSONSessionStoreTests.swift`:

```swift
import MellowShared
import XCTest
@testable import MellowLibrary

final class JSONSessionStoreTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    func testMissingFileLoadsAsNil() throws {
        let store = JSONSessionStore(fileURL: root.appendingPathComponent("session.json"))
        XCTAssertNil(try store.load())
    }

    func testSaveThenLoadRoundTrips() throws {
        let store = JSONSessionStore(fileURL: root.appendingPathComponent("session.json"))
        let entry = PhotoEntry(id: PhotoID(), filename: "a.heic", displayName: "A")
        let snapshot = SessionSnapshot(photos: [entry], selectedPhotoID: entry.id, presets: [])
        try store.save(snapshot)
        XCTAssertEqual(try store.load(), snapshot)
    }

    func testMalformedFileIsPreservedAsRecoveryCopyBeforeAnythingIsWritten() throws {
        let fileURL = root.appendingPathComponent("session.json")
        let malformed = Data("{ interrupted session".utf8)
        try malformed.write(to: fileURL)
        let store = JSONSessionStore(fileURL: fileURL)
        XCTAssertThrowsError(try store.load()) { error in
            XCTAssertEqual(error as? MellowError, .sessionUnreadable)
        }
        let recovery = try XCTUnwrap(store.recoveryFileURL)
        XCTAssertEqual(try Data(contentsOf: recovery), malformed)
        XCTAssertEqual(try Data(contentsOf: fileURL), malformed, "복구 사본을 만든 뒤에도 원본은 아직 그대로다")
        try store.save(SessionSnapshot())
        XCTAssertEqual(try Data(contentsOf: recovery), malformed)
        XCTAssertNotNil(try store.load())
    }

    func testSaveFailureIsReportedAsSessionWriteFailed() throws {
        let fileURL = root.appendingPathComponent("session.json")
        try FileManager.default.createDirectory(at: fileURL, withIntermediateDirectories: false)
        let store = JSONSessionStore(fileURL: fileURL)
        XCTAssertThrowsError(try store.save(SessionSnapshot())) { error in
            guard case .sessionWriteFailed = error as? MellowError else {
                return XCTFail("예상과 다른 오류: \(error)")
            }
        }
    }
}
```

`apple/Tests/MellowLibraryTests/LibraryPolicyTests.swift`:

```swift
import XCTest
@testable import MellowLibrary

final class LibraryPolicyTests: XCTestCase {
    func testPhotoLimitTiersByPhysicalMemory() {
        let gigabyte: UInt64 = 1 << 30
        XCTAssertEqual(LibraryPolicy.maxPhotos(physicalMemory: 3 * gigabyte), 12)
        XCTAssertEqual(LibraryPolicy.maxPhotos(physicalMemory: 4 * gigabyte), 24)
        XCTAssertEqual(LibraryPolicy.maxPhotos(physicalMemory: 6 * gigabyte), 24)
        XCTAssertEqual(LibraryPolicy.maxPhotos(physicalMemory: 8 * gigabyte), 40)
        XCTAssertEqual(LibraryPolicy.maxPhotos(physicalMemory: 64 * gigabyte), 40)
    }
}
```

`apple/Tests/MellowLibraryTests/ProjectSessionTests.swift`:

```swift
import MellowEditing
import MellowShared
import XCTest
@testable import MellowLibrary

/// 저장 실패를 흉내 내는 메모리 저장소.
final class MemorySessionStore: SessionStore, @unchecked Sendable {
    var saved: SessionSnapshot?
    var failNextSave = false
    var saveCount = 0

    func load() throws -> SessionSnapshot? { saved }

    func save(_ snapshot: SessionSnapshot) throws {
        saveCount += 1
        if failNextSave {
            failNextSave = false
            throw MellowError.sessionWriteFailed(reason: "test")
        }
        saved = snapshot
    }
}

@MainActor
final class ProjectSessionTests: XCTestCase {
    private func entry(_ name: String) -> PhotoEntry {
        PhotoEntry(id: PhotoID(), filename: "\(name).heic", displayName: name)
    }

    func testRestoreLoadsSnapshotAndSelection() throws {
        let store = MemorySessionStore()
        let photo = entry("A")
        store.saved = SessionSnapshot(photos: [photo], selectedPhotoID: photo.id, presets: [BuiltInPresets.cozy])
        let session = ProjectSession(store: store, maxPhotos: 40)
        try session.restore()
        XCTAssertEqual(session.photos, [photo])
        XCTAssertEqual(session.selectedPhotoID, photo.id)
        XCTAssertEqual(session.presets, [BuiltInPresets.cozy])
    }

    func testAddSelectsFirstPhotoAndPersists() throws {
        let store = MemorySessionStore()
        let session = ProjectSession(store: store, maxPhotos: 40)
        let photo = entry("A")
        try session.add(photo)
        XCTAssertEqual(session.selectedPhotoID, photo.id)
        XCTAssertEqual(store.saved?.photos, [photo])
    }

    func testAddRollsBackWhenSaveFails() throws {
        let store = MemorySessionStore()
        let session = ProjectSession(store: store, maxPhotos: 40)
        store.failNextSave = true
        XCTAssertThrowsError(try session.add(entry("A")))
        XCTAssertTrue(session.photos.isEmpty)
        XCTAssertNil(session.selectedPhotoID)
    }

    func testAddBeyondCapacityIsRejected() throws {
        let session = ProjectSession(store: MemorySessionStore(), maxPhotos: 1)
        try session.add(entry("A"))
        XCTAssertEqual(session.remainingCapacity, 0)
        XCTAssertThrowsError(try session.add(entry("B"))) { error in
            XCTAssertEqual(error as? ProjectSession.Failure, .capacityReached)
        }
    }

    func testEditAppliesRulesAndPersists() throws {
        let store = MemorySessionStore()
        let session = ProjectSession(store: store, maxPhotos: 40)
        let photo = entry("A")
        try session.add(photo)
        let rejection = session.edit(photo.id) { document in document.set(.exposure(0.4)) }
        XCTAssertNil(rejection)
        XCTAssertEqual(session.selected?.document.recipe.color.exposure, 0.4)
        XCTAssertEqual(store.saved?.photos.first?.document.recipe.color.exposure, 0.4)
        XCTAssertNil(session.lastPersistenceError)
    }

    func testEditSaveFailureIsExposedButStateIsKept() throws {
        let store = MemorySessionStore()
        let session = ProjectSession(store: store, maxPhotos: 40)
        let photo = entry("A")
        try session.add(photo)
        store.failNextSave = true
        session.edit(photo.id) { document in document.set(.exposure(0.4)) }
        XCTAssertEqual(session.selected?.document.recipe.color.exposure, 0.4)
        XCTAssertNotNil(session.lastPersistenceError)
    }

    func testRemoveSavesFirstAndKeepsStateOnFailure() throws {
        let store = MemorySessionStore()
        let session = ProjectSession(store: store, maxPhotos: 40)
        let photo = entry("A")
        try session.add(photo)
        session.edit(photo.id) { document in document.set(.exposure(0.4)) }
        store.failNextSave = true
        XCTAssertThrowsError(try session.remove(photo.id))
        XCTAssertEqual(session.photos.map(\.id), [photo.id])
        XCTAssertTrue(session.selected?.document.canUndo ?? false)
        try session.remove(photo.id)
        XCTAssertTrue(session.photos.isEmpty)
        XCTAssertNil(session.selectedPhotoID)
        XCTAssertEqual(store.saved?.photos.count, 0)
    }

    func testRemoveSelectsNextPhoto() throws {
        let session = ProjectSession(store: MemorySessionStore(), maxPhotos: 40)
        let a = entry("A")
        let b = entry("B")
        try session.add(a)
        try session.add(b)
        try session.remove(a.id)
        XCTAssertEqual(session.selectedPhotoID, b.id)
    }

    func testApplyToAllCopiesValuesWithBatchRules() throws {
        let session = ProjectSession(store: MemorySessionStore(), maxPhotos: 40)
        let source = entry("A")
        var locked = entry("B")
        locked.document.set(.faceSlim(0.2))
        locked.document.set(.targetFace(1))
        locked.document.appendLocalEdit(.spot(RetouchSpot(x: 0.5, y: 0.4, sourceX: 0.4, sourceY: 0.4, radius: 0.02)))
        var plain = entry("C")
        plain.document.set(.targetFace(0))
        try session.add(source)
        try session.add(locked)
        try session.add(plain)
        session.edit(source.id) { $0.set(.exposure(0.3)) }
        session.edit(source.id) { $0.set(.faceSlim(0.9)) }
        session.applyToAll(from: source.id)
        XCTAssertEqual(session.photos[1].document.recipe.portrait.faceSlim, 0.2)
        XCTAssertEqual(session.photos[1].document.recipe.portrait.targetFace, 1)
        XCTAssertEqual(session.photos[1].document.recipe.color.exposure, 0.3)
        XCTAssertEqual(session.photos[2].document.recipe.portrait.faceSlim, 0.9)
        XCTAssertNil(session.photos[2].document.recipe.portrait.targetFace)
        XCTAssertEqual(session.photos[0].document.recipe.color.exposure, 0.3, "원본 사진은 바뀌지 않는다")
    }

    func testAddPresetTrimsAndLimitsName() throws {
        let session = ProjectSession(store: MemorySessionStore(), maxPhotos: 40)
        session.addPreset(named: "  " + String(repeating: "가", count: 40) + "  ", values: PresetValues())
        XCTAssertEqual(session.presets.count, 1)
        XCTAssertEqual(session.presets[0].name.count, LibraryPolicy.presetNameLimit)
        session.addPreset(named: "   ", values: PresetValues())
        XCTAssertEqual(session.presets.count, 1, "빈 이름은 무시")
    }
}
```

- [ ] **Step 2: 실패 확인**

Run: `cd apple && swift test --filter MellowLibraryTests`
Expected: 컴파일 실패.

- [ ] **Step 3: 구현**

`apple/Sources/MellowLibrary/API/SessionStore.swift`:

```swift
public protocol SessionStore: Sendable {
    /// 파일이 없으면 nil. 읽을 수 없으면 MellowError.sessionUnreadable.
    func load() throws -> SessionSnapshot?
    func save(_ snapshot: SessionSnapshot) throws
}
```

`apple/Sources/MellowLibrary/API/JSONSessionStore.swift`:

```swift
import Foundation
import MellowShared

/// 원자적으로 쓰고, 읽을 수 없는 파일은 복구 사본을 남긴 뒤에만 덮어쓴다.
public final class JSONSessionStore: SessionStore, @unchecked Sendable {
    public let fileURL: URL
    private let lock = NSLock()
    private var _recoveryFileURL: URL?

    public init(fileURL: URL) {
        self.fileURL = fileURL
    }

    /// 읽을 수 없던 세션을 보관한 사본. 복구 사본이 없으면 nil.
    public var recoveryFileURL: URL? {
        lock.withLock { _recoveryFileURL }
    }

    public func load() throws -> SessionSnapshot? {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return nil }
        let data = try Data(contentsOf: fileURL)
        do {
            return SessionFileMapper.snapshot(from: try SessionFile.decode(data))
        } catch {
            try preserveUnreadableFile()
            throw MellowError.sessionUnreadable
        }
    }

    public func save(_ snapshot: SessionSnapshot) throws {
        do {
            let data = try SessionFile.encode(SessionFileMapper.file(from: snapshot))
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: fileURL, options: Self.writeOptions)
        } catch {
            throw MellowError.sessionWriteFailed(reason: error.localizedDescription)
        }
    }

    private static var writeOptions: Data.WritingOptions {
        #if os(iOS)
        return [.atomic, .completeFileProtectionUnlessOpen]
        #else
        return [.atomic]
        #endif
    }

    private func preserveUnreadableFile() throws {
        let backup = fileURL.deletingLastPathComponent().appendingPathComponent("session-recovery-\(UUID().uuidString).json")
        do {
            try FileManager.default.copyItem(at: fileURL, to: backup)
        } catch {
            throw MellowError.sessionWriteFailed(reason: error.localizedDescription)
        }
        lock.withLock { _recoveryFileURL = backup }
    }
}
```

`apple/Sources/MellowLibrary/API/WorkingCopyStore.swift`:

```swift
import Foundation
import MellowShared

/// 가져온 사진의 작업 사본을 보관하는 폴더. 사진 앱·사용자 파일 원본은 절대 건드리지 않는다.
public struct WorkingCopyStore: Sendable {
    public let directory: URL

    public init(directory: URL) {
        self.directory = directory
    }

    public func prepareDirectory() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var folder = directory
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try folder.setResourceValues(values)
    }

    public func url(for filename: String) -> URL {
        directory.appendingPathComponent(filename)
    }

    /// 임시 파일을 사본 폴더로 옮기고 파일 이름을 돌려준다. iOS에서는 파일 보호를 건다.
    public func adopt(temporaryFile: URL, as id: PhotoID) throws -> String {
        let fileExtension = temporaryFile.pathExtension.isEmpty ? "image" : temporaryFile.pathExtension
        let filename = "\(id.rawValue.uuidString).\(fileExtension)"
        let destination = url(for: filename)
        try FileManager.default.moveItem(at: temporaryFile, to: destination)
        #if os(iOS)
        try FileManager.default.setAttributes(
            [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication], ofItemAtPath: destination.path)
        #endif
        return filename
    }

    public func remove(filename: String) throws {
        let target = url(for: filename)
        guard FileManager.default.fileExists(atPath: target.path) else { return }
        try FileManager.default.removeItem(at: target)
    }
}
```

`apple/Sources/MellowLibrary/API/LibraryPolicy.swift`:

```swift
import Foundation

public enum LibraryPolicy {
    public static let presetNameLimit = 30

    /// 물리 메모리 기준 동시 편집 사진 수.
    public static func maxPhotos(physicalMemory: UInt64) -> Int {
        let gigabyte: UInt64 = 1 << 30
        if physicalMemory < 4 * gigabyte { return 12 }
        if physicalMemory < 8 * gigabyte { return 24 }
        return 40
    }

    public static var maxPhotosForCurrentDevice: Int {
        maxPhotos(physicalMemory: ProcessInfo.processInfo.physicalMemory)
    }
}
```

`apple/Sources/MellowLibrary/API/ProjectSession.swift`:

```swift
import Foundation
import MellowEditing
import MellowShared
import Observation

/// 사진 목록·선택·프리셋의 단일 출처. 모든 변경은 저장소에 반영한다.
@MainActor
@Observable
public final class ProjectSession {
    public enum Failure: Error, Equatable {
        case capacityReached
    }

    public private(set) var photos: [PhotoEntry] = []
    public var selectedPhotoID: PhotoID? {
        didSet { persistQuietly() }
    }
    public private(set) var presets: [Preset] = []
    /// 편집 중 저장 실패. 상태는 유지되고 다음 저장에서 다시 시도한다.
    public private(set) var lastPersistenceError: MellowError?

    private let store: any SessionStore
    private let maxPhotos: Int

    public init(store: any SessionStore, maxPhotos: Int) {
        self.store = store
        self.maxPhotos = maxPhotos
    }

    public var selected: PhotoEntry? {
        photos.first { $0.id == selectedPhotoID }
    }

    public var remainingCapacity: Int {
        max(0, maxPhotos - photos.count)
    }

    public func index(of id: PhotoID) -> Int? {
        photos.firstIndex { $0.id == id }
    }

    /// 읽을 수 없는 세션은 오류를 던지되 빈 세션으로 계속 쓸 수 있다.
    public func restore() throws {
        guard let snapshot = try store.load() else { return }
        photos = snapshot.photos
        presets = snapshot.presets
        selectedPhotoID = snapshot.selectedPhotoID
    }

    public func add(_ entry: PhotoEntry) throws {
        guard remainingCapacity > 0 else { throw Failure.capacityReached }
        photos.append(entry)
        let previousSelection = selectedPhotoID
        if selectedPhotoID == nil {
            selectedPhotoID = entry.id
        }
        do {
            try save()
        } catch {
            photos.removeLast()
            selectedPhotoID = previousSelection
            throw error
        }
    }

    /// 저장이 성공한 뒤에만 상태를 바꾼다. 실패하면 사진·기록은 그대로다.
    public func remove(_ id: PhotoID) throws {
        let remaining = photos.filter { $0.id != id }
        let nextSelection = selectedPhotoID == id ? remaining.first?.id : selectedPhotoID
        try store.save(SessionSnapshot(photos: remaining, selectedPhotoID: nextSelection, presets: presets))
        photos = remaining
        selectedPhotoID = nextSelection
    }

    @discardableResult
    public func edit(_ id: PhotoID, _ body: (inout EditDocument) -> EditDocument.Rejection?) -> EditDocument.Rejection? {
        guard let index = index(of: id) else { return nil }
        let rejection = body(&photos[index].document)
        persistQuietly()
        return rejection
    }

    public func applyToAll(from id: PhotoID) {
        guard let source = photos.first(where: { $0.id == id }) else { return }
        let values = PresetValues(color: source.document.recipe.color, portrait: source.document.recipe.portrait)
        for index in photos.indices where photos[index].id != id {
            photos[index].document.applyFromBatch(values)
        }
        persistQuietly()
    }

    public func addPreset(named rawName: String, values: PresetValues) {
        let trimmed = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        presets.append(Preset(name: String(trimmed.prefix(LibraryPolicy.presetNameLimit)), values: values))
        persistQuietly()
    }

    public func save() throws {
        try store.save(SessionSnapshot(photos: photos, selectedPhotoID: selectedPhotoID, presets: presets))
        lastPersistenceError = nil
    }

    private func persistQuietly() {
        do {
            try save()
        } catch let error as MellowError {
            lastPersistenceError = error
        } catch {
            lastPersistenceError = .sessionWriteFailed(reason: error.localizedDescription)
        }
    }
}
```

주의: `edit`의 클로저는 `Rejection?`을 돌려줘야 하므로 테스트처럼 `{ $0.set(.exposure(0.3)) }`로 쓴다. `appendLocalEdit`·`undo` 같은 반환값 없는 호출은 `{ $0.undo(); return nil }`로 감싼다.

- [ ] **Step 4: 통과 확인**

Run: `cd apple && swift test --filter MellowLibraryTests`
Expected: 모두 PASS (Task 3의 5개 + 신규 15개).

- [ ] **Step 5: 커밋**

```bash
git add apple/Sources/MellowLibrary apple/Tests/MellowLibraryTests
git commit -m "refactor(library): 세션 저장소와 ProjectSession으로 사진 관리 통합

원자적 저장, 손상 세션 복구 사본, 저장 실패 시 제거 중단 같은 iPhone
저장소의 보호 동작을 플랫폼 독립 모듈로 옮겨 Mac도 같은 보호를 받는다.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 5: MellowRendering — 로더·렌더러·단계 파이프라인 (기존 엔진 이식)

**Files:**
- Delete: `apple/Sources/MellowRendering/Placeholder.swift`, `apple/Tests/MellowRenderingTests/PlaceholderTests.swift`
- Create: `apple/Sources/MellowRendering/API/RenderTuning.swift`
- Create: `apple/Sources/MellowRendering/API/RenderStage.swift` (RenderContext, RenderStage)
- Create: `apple/Sources/MellowRendering/API/RenderPipeline.swift`
- Create: `apple/Sources/MellowRendering/API/ImageLoader.swift`
- Create: `apple/Sources/MellowRendering/API/Renderer.swift`
- Create: `apple/Sources/MellowRendering/Domain/MaskBuilder.swift`
- Create: `apple/Sources/MellowRendering/Domain/WarpKernel.swift`
- Create: `apple/Sources/MellowRendering/Domain/SkinStage.swift`
- Create: `apple/Sources/MellowRendering/Domain/FaceReshapeStage.swift`
- Create: `apple/Sources/MellowRendering/Domain/LocalEditStage.swift`
- Create: `apple/Sources/MellowRendering/Domain/ColorStage.swift`
- Test: `apple/Tests/MellowRenderingTests/RenderingTestSupport.swift`
- Test: `apple/Tests/MellowRenderingTests/RenderPipelineTests.swift`
- Test: `apple/Tests/MellowRenderingTests/ImageLoaderTests.swift`

**Interfaces:**
- Consumes: `EditRecipe`, `FaceGeometry`, `NormalizedRect`, `MellowError` (Task 1).
- Produces: `RenderTuning`, `RenderContext(extent:recipe:faces:tuning:)`(targetFaces는 init이 계산), `RenderStage`, `RenderPipeline.standard`, `RenderPipeline.render(_:context:)`, `ImageLoader.load(url:maxDimension:)`, `ImageLoader.metadata(url:)`, `ImageMetadata.pixelSize`, `Renderer.makeCGImage(_:)`. Task 6·7이 쓴다.

기존 `Sources/MellowCore/ImageEngine.swift`를 옮기되 동작은 바꾸지 않는다. 기존 테스트 8개가 그 증거다. 테스트는 `swift test`로만 돌린다 (`ENGINE_STANDALONE` 폐기).

- [ ] **Step 1: 테스트 지원 코드와 실패하는 테스트 작성**

`apple/Tests/MellowRenderingTests/RenderingTestSupport.swift`:

```swift
import CoreImage
import Foundation
import MellowShared
@testable import MellowRendering

enum RenderingTestSupport {
    static let renderer = Renderer()

    static func gradient() -> CIImage {
        let filter = CIFilter(name: "CILinearGradient", parameters: [
            "inputPoint0": CIVector(x: 0, y: 0),
            "inputPoint1": CIVector(x: 128, y: 0),
            "inputColor0": CIColor(red: 0.1, green: 0.2, blue: 0.3),
            "inputColor1": CIColor(red: 0.9, green: 0.6, blue: 0.4),
        ])!
        return filter.outputImage!.cropped(to: CGRect(x: 0, y: 0, width: 128, height: 80))
    }

    static func solid(_ color: CIColor, size: Int = 256) -> CIImage {
        CIImage(color: color).cropped(to: CGRect(x: 0, y: 0, width: size, height: size))
    }

    static func bytes(_ image: CIImage) throws -> [UInt8] {
        let cg = try renderer.makeCGImage(image)
        return Array(cg.dataProvider!.data! as Data)
    }

    static func render(_ image: CIImage, recipe: EditRecipe, faces: [FaceGeometry] = []) throws -> CIImage {
        let context = RenderContext(extent: image.extent, recipe: recipe, faces: faces, tuning: RenderTuning())
        return try RenderPipeline.standard.render(image, context: context)
    }

    static func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
```

`apple/Tests/MellowRenderingTests/RenderPipelineTests.swift`:

```swift
import CoreImage
import MellowShared
import XCTest
@testable import MellowRendering

final class RenderPipelineTests: XCTestCase {
    typealias Support = RenderingTestSupport

    func testIdentityRecipeLeavesBytesUntouched() throws {
        let input = Support.gradient()
        let output = try Support.render(input, recipe: EditRecipe())
        XCTAssertEqual(output.extent, input.extent)
        XCTAssertEqual(try Support.bytes(output), try Support.bytes(input))
    }

    func testExposureChangesBytes() throws {
        var recipe = EditRecipe()
        recipe.color.exposure = 1
        XCTAssertNotEqual(try Support.bytes(Support.render(Support.gradient(), recipe: recipe)), try Support.bytes(Support.gradient()))
    }

    func testWarpAndCloneAreLocalAndEffective() throws {
        let image = Support.gradient()
        let original = try Support.bytes(image)
        let edits: [LocalEdit] = [
            .warp(WarpStroke(x: 0.5, y: 0.5, dx: 0.03, dy: 0, radius: 0.2)),
            .spot(RetouchSpot(x: 0.5, y: 0.5, sourceX: 0.2, sourceY: 0.5, radius: 0.2)),
        ]
        for edit in edits {
            var recipe = EditRecipe()
            recipe.operations = [edit]
            let result = try Support.bytes(Support.render(image, recipe: recipe))
            XCTAssertNotEqual(result, original)
            XCTAssertEqual(Array(result.prefix(128 * 4 * 10)), Array(original.prefix(128 * 4 * 10)), "아래쪽 10줄은 그대로")
        }
    }

    func testLocalEditsReplayInRecordedOrder() throws {
        let input = Support.gradient()
        let spot = LocalEdit.spot(RetouchSpot(x: 0.5, y: 0.5, sourceX: 0.15, sourceY: 0.5, radius: 0.2))
        let warp = LocalEdit.warp(WarpStroke(x: 0.5, y: 0.5, dx: 0.05, dy: 0, radius: 0.3))
        var forward = EditRecipe()
        forward.operations = [spot, warp]
        var reverse = EditRecipe()
        reverse.operations = [warp, spot]
        let forwardBytes = try Support.bytes(Support.render(input, recipe: forward))
        XCTAssertNotEqual(forwardBytes, try Support.bytes(Support.render(input, recipe: reverse)))
        var onlySpot = EditRecipe()
        onlySpot.operations = [spot]
        var onlyWarp = EditRecipe()
        onlyWarp.operations = [warp]
        let staged = try Support.render(Support.render(input, recipe: onlySpot), recipe: onlyWarp)
        XCTAssertEqual(forwardBytes, try Support.bytes(staged))
    }

    func testWarmthPositiveMakesGrayRedder() throws {
        let gray = Support.solid(CIColor(red: 0.5, green: 0.5, blue: 0.5), size: 8)
        var recipe = EditRecipe()
        recipe.color.warmth = 1
        let bytes = try Support.bytes(Support.render(gray, recipe: recipe))
        XCTAssertGreaterThan(bytes[0], bytes[2])
    }

    func testPortraitStagesChangeOnlyWhenFacesExist() throws {
        let input = Support.gradient()
        let face = FaceGeometry(boundingBox: NormalizedRect(x: 0.15, y: 0.05, width: 0.7, height: 0.9))
        var recipe = EditRecipe()
        recipe.portrait.skinSmoothing = 0.5
        recipe.portrait.faceSlim = 0.7
        recipe.color.contrast = 1.05
        recipe.color.saturation = 0.8
        recipe.color.warmth = -0.3
        let withFace = try Support.render(input, recipe: recipe, faces: [face])
        XCTAssertEqual(withFace.extent, input.extent)
        XCTAssertNotEqual(try Support.bytes(withFace), try Support.bytes(input))
        var portraitOnly = EditRecipe()
        portraitOnly.portrait.skinSmoothing = 1
        portraitOnly.portrait.faceSlim = 1
        XCTAssertEqual(try Support.bytes(Support.render(input, recipe: portraitOnly, faces: [])), try Support.bytes(input))
    }

    func testTargetFaceLimitsPortraitStagesToOneFace() throws {
        let input = Support.gradient()
        let left = FaceGeometry(boundingBox: NormalizedRect(x: 0.05, y: 0.1, width: 0.35, height: 0.8))
        let right = FaceGeometry(boundingBox: NormalizedRect(x: 0.6, y: 0.1, width: 0.35, height: 0.8))
        var all = EditRecipe()
        all.portrait.skinSmoothing = 1
        var onlyLeft = all
        onlyLeft.portrait.targetFace = 0
        var outOfRange = all
        outOfRange.portrait.targetFace = 7
        XCTAssertNotEqual(try Support.bytes(Support.render(input, recipe: all, faces: [left, right])), try Support.bytes(Support.render(input, recipe: onlyLeft, faces: [left, right])))
        XCTAssertEqual(try Support.bytes(Support.render(input, recipe: outOfRange, faces: [left, right])), try Support.bytes(input), "범위 밖 인덱스는 아무 얼굴도 고치지 않는다")
    }

    func testStageOrderMatters() throws {
        let input = Support.gradient()
        var recipe = EditRecipe()
        recipe.color.exposure = 0.8
        recipe.operations = [.spot(RetouchSpot(x: 0.5, y: 0.5, sourceX: 0.15, sourceY: 0.5, radius: 0.2))]
        let context = RenderContext(extent: input.extent, recipe: recipe, faces: [], tuning: RenderTuning())
        let standard = try RenderPipeline.standard.render(input, context: context)
        let reversed = try RenderPipeline(stages: RenderPipeline.standard.stages.reversed()).render(input, context: context)
        XCTAssertEqual(RenderPipeline.standard.stages.map(\.name), ["skin", "faceReshape", "localEdit", "color"])
        XCTAssertNotEqual(try Support.bytes(standard), try Support.bytes(reversed))
    }

    func testNonFiniteRecipeIsRejected() {
        var recipe = EditRecipe()
        recipe.portrait.skinSmoothing = .nan
        XCTAssertThrowsError(try Support.render(Support.gradient(), recipe: recipe)) { error in
            XCTAssertEqual(error as? MellowError, .invalidRecipeValues)
        }
    }

    func testEmptyExtentIsRejected() {
        let empty = CIImage.empty()
        XCTAssertThrowsError(try Support.render(empty, recipe: EditRecipe())) { error in
            XCTAssertEqual(error as? MellowError, .invalidImageSize)
        }
    }
}
```

`apple/Tests/MellowRenderingTests/ImageLoaderTests.swift`:

```swift
import CoreImage
import ImageIO
import MellowShared
import UniformTypeIdentifiers
import XCTest
@testable import MellowRendering

final class ImageLoaderTests: XCTestCase {
    typealias Support = RenderingTestSupport

    func testOrientationIsAppliedForFullAndThumbnailLoads() throws {
        let directory = try Support.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("rotated.jpg")
        let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.jpeg.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(destination, try Support.renderer.makeCGImage(Support.gradient()), [kCGImagePropertyOrientation: 6] as CFDictionary)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        let loader = ImageLoader()
        XCTAssertEqual(try loader.load(url: url).extent, CGRect(x: 0, y: 0, width: 80, height: 128))
        XCTAssertEqual(try loader.load(url: url, maxDimension: 64).extent, CGRect(x: 0, y: 0, width: 40, height: 64))
        XCTAssertEqual(try loader.metadata(url: url).pixelSize, CGSize(width: 80, height: 128))
    }

    func testUnreadableFileThrowsTypedError() throws {
        let directory = try Support.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("broken.png")
        try Data([0, 1, 2]).write(to: url)
        XCTAssertThrowsError(try ImageLoader().load(url: url)) { error in
            XCTAssertEqual(error as? MellowError, .unsupportedOrCorruptPhoto)
        }
        XCTAssertThrowsError(try ImageLoader().load(url: directory.appendingPathComponent("missing.png"))) { error in
            XCTAssertEqual(error as? MellowError, .cannotOpenPhoto(filename: "missing.png"))
        }
    }
}
```

- [ ] **Step 2: 실패 확인**

Run: `cd apple && swift test --filter MellowRenderingTests`
Expected: 컴파일 실패.

- [ ] **Step 3: 구현**

`apple/Sources/MellowRendering/API/RenderTuning.swift` — 기존 엔진의 숫자를 전부 이름 붙여 옮긴다. 값은 바꾸지 않는다.

```swift
import Foundation

public struct RenderTuning: Sendable {
    /// 미리보기 긴 변. 8GB 이상 1600, 미만 1200.
    public var previewMaxDimension: Int = 1600
    public var previewCacheCapacity: Int = 3
    public var thumbnailMaxDimension: Int = 220

    public var skinMaskMaxStrength: Double = 0.85
    public var skinFaceInsetX: Double = 0.08
    public var skinFaceInsetY: Double = 0.03
    public var skinFeatureInset: Double = 0.045
    public var skinNoiseLevel: Double = 0.06
    public var skinNoiseSharpness: Double = 0.3
    public var skinBlurRadiusFraction: Double = 0.0015
    public var skinBlurMinimumRadius: Double = 0.5

    public var faceSlimShiftFraction: Double = 0.035
    public var faceSlimRadiusFraction: Double = 0.34
    public var faceSlimAnchorX: Double = 0.12
    public var faceSlimAnchorY: Double = 0.36

    public var warpMaxRadiusFraction: Double = 0.5
    public var warpDisplacementLimit: Double = 0.25
    public var spotMaxRadiusFraction: Double = 0.3
    public var warmthKelvinRange: Double = 2000
    public var neutralKelvin: Double = 6500

    public init() {}

    public static func forCurrentDevice(physicalMemory: UInt64 = ProcessInfo.processInfo.physicalMemory) -> RenderTuning {
        var tuning = RenderTuning()
        let gigabyte: UInt64 = 1 << 30
        tuning.previewMaxDimension = physicalMemory >= 8 * gigabyte ? 1600 : 1200
        return tuning
    }
}
```

`apple/Sources/MellowRendering/API/RenderStage.swift`:

```swift
import CoreImage
import MellowShared

public struct RenderContext: Sendable {
    public let extent: CGRect
    public let recipe: EditRecipe
    public let faces: [FaceGeometry]
    /// recipe.portrait.targetFace를 적용한 결과. 범위 밖 인덱스면 비어 있다.
    public let targetFaces: [FaceGeometry]
    public let tuning: RenderTuning

    public init(extent: CGRect, recipe: EditRecipe, faces: [FaceGeometry], tuning: RenderTuning) {
        self.extent = extent
        self.recipe = recipe
        self.faces = faces
        self.tuning = tuning
        if let index = recipe.portrait.targetFace {
            targetFaces = faces.indices.contains(index) ? [faces[index]] : []
        } else {
            targetFaces = faces
        }
    }

    /// 정규화 사각형을 픽셀 좌표로.
    public func pixelRect(_ rect: NormalizedRect) -> CGRect {
        CGRect(
            x: extent.minX + rect.x * extent.width,
            y: extent.minY + rect.y * extent.height,
            width: rect.width * extent.width,
            height: rect.height * extent.height)
    }

    public func pixelPoint(x: Double, y: Double) -> CGPoint {
        CGPoint(x: extent.minX + x * extent.width, y: extent.minY + y * extent.height)
    }

    public var shortSide: CGFloat { min(extent.width, extent.height) }
}

public protocol RenderStage: Sendable {
    var name: String { get }
    func apply(_ image: CIImage, in context: RenderContext) throws -> CIImage
}
```

`apple/Sources/MellowRendering/API/RenderPipeline.swift`:

```swift
import CoreImage
import MellowShared

public struct RenderPipeline: Sendable {
    public let stages: [any RenderStage]

    public init(stages: [any RenderStage]) {
        self.stages = stages
    }

    /// 자동 보정이 기반이 되고 수동 편집이 그 위에, 색감은 마지막에.
    public static let standard = RenderPipeline(stages: [SkinStage(), FaceReshapeStage(), LocalEditStage(), ColorStage()])

    public func render(_ image: CIImage, context: RenderContext) throws -> CIImage {
        guard !context.extent.isEmpty, !context.extent.isInfinite else { throw MellowError.invalidImageSize }
        guard context.recipe.allValuesFinite else { throw MellowError.invalidRecipeValues }
        var result = image
        for stage in stages {
            result = try stage.apply(result, in: context)
        }
        return result.cropped(to: context.extent)
    }
}
```

`apple/Sources/MellowRendering/API/ImageLoader.swift`:

```swift
import CoreImage
import Foundation
import ImageIO
import MellowShared

public struct ImageMetadata: Sendable {
    /// 방향 보정 후 픽셀 크기.
    public let pixelSize: CGSize
}

public struct ImageLoader: Sendable {
    public init() {}

    /// maxDimension이 있으면 방향이 적용된 축소본, 없으면 방향을 보정한 원본.
    public func load(url: URL, maxDimension: Int? = nil) throws -> CIImage {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else {
            throw MellowError.cannotOpenPhoto(filename: url.lastPathComponent)
        }
        let image: CIImage
        if let maxDimension {
            let options: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: maxDimension,
                kCGImageSourceShouldCacheImmediately: true,
            ]
            guard maxDimension > 0, let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
                throw MellowError.cannotCreatePreview
            }
            image = CIImage(cgImage: cg)
        } else {
            let options: [CFString: Any] = [kCGImageSourceShouldCacheImmediately: true]
            guard let cg = CGImageSourceCreateImageAtIndex(source, 0, options as CFDictionary) else {
                throw MellowError.unsupportedOrCorruptPhoto
            }
            let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
            let orientation = (properties?[kCGImagePropertyOrientation] as? NSNumber)?.int32Value ?? 1
            image = CIImage(cgImage: cg).oriented(forExifOrientation: orientation)
        }
        return image.transformed(by: CGAffineTransform(translationX: -image.extent.minX, y: -image.extent.minY))
    }

    public func metadata(url: URL) throws -> ImageMetadata {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else {
            throw MellowError.cannotOpenPhoto(filename: url.lastPathComponent)
        }
        guard let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
            let width = properties[kCGImagePropertyPixelWidth] as? Int,
            let height = properties[kCGImagePropertyPixelHeight] as? Int
        else {
            throw MellowError.unsupportedOrCorruptPhoto
        }
        let orientation = (properties[kCGImagePropertyOrientation] as? Int) ?? 1
        let rotated = orientation >= 5
        return ImageMetadata(pixelSize: CGSize(width: rotated ? height : width, height: rotated ? width : height))
    }
}
```

`apple/Sources/MellowRendering/API/Renderer.swift`:

```swift
import CoreImage
import MellowShared

/// CIContext 소유자. 출력은 8bit sRGB.
public final class Renderer: @unchecked Sendable {
    private let context: CIContext
    private let outputColorSpace = CGColorSpace(name: CGColorSpace.sRGB)!

    public init() {
        context = CIContext(options: [
            .workingColorSpace: CGColorSpace(name: CGColorSpace.extendedLinearSRGB)!,
            .outputColorSpace: CGColorSpace(name: CGColorSpace.sRGB)!,
        ])
    }

    public func makeCGImage(_ image: CIImage) throws -> CGImage {
        guard let cg = context.createCGImage(image, from: image.extent, format: .RGBA8, colorSpace: outputColorSpace) else {
            throw MellowError.renderFailed
        }
        return cg
    }
}
```

`apple/Sources/MellowRendering/Domain/MaskBuilder.swift`:

```swift
import CoreImage

enum MaskBuilder {
    /// 중심 0.65까지 strength, 가장자리 1.0에서 0으로 떨어지는 타원.
    static func ellipse(_ rect: CGRect, extent: CGRect, strength: Double = 1) -> CIImage {
        let gradient = CIFilter(name: "CIRadialGradient", parameters: [
            "inputCenter": CIVector(x: 0, y: 0),
            "inputRadius0": 0.65,
            "inputRadius1": 1.0,
            "inputColor0": CIColor(red: strength, green: strength, blue: strength),
            "inputColor1": CIColor.black,
        ])!.outputImage!
        let transform = CGAffineTransform(a: max(1, rect.width / 2), b: 0, c: 0, d: max(1, rect.height / 2), tx: rect.midX, ty: rect.midY)
        return gradient.transformed(by: transform).cropped(to: extent)
    }

    static func blend(_ foreground: CIImage, over background: CIImage, mask: CIImage) -> CIImage {
        foreground.applyingFilter("CIBlendWithMask", parameters: [kCIInputBackgroundImageKey: background, kCIInputMaskImageKey: mask])
    }
}
```

`apple/Sources/MellowRendering/Domain/WarpKernel.swift`:

```swift
import CoreImage
import MellowShared

/// CIWarpKernel 문자열 소스를 감싸는 유일한 자리. Metal로 바꿀 때 이 타입만 바꾼다.
/// 런타임 Metal 커널은 동적 라이브러리를 지원하는 기기가 필요해 iOS 17 하한보다 좁다.
final class WarpKernel: @unchecked Sendable {
    static let shared = WarpKernel()

    private let kernel: CIWarpKernel?

    private init() {
        kernel = CIWarpKernel(source: """
            kernel vec2 localWarp(vec2 center, vec2 delta, float radius) {
                vec2 p = destCoord();
                float t = clamp(1.0 - distance(p, center) / radius, 0.0, 1.0);
                float w = t * t * (3.0 - 2.0 * t);
                return p - delta * w;
            }
            """)
    }

    /// center·delta는 픽셀 좌표. delta 길이는 radius * displacementLimit로 제한한다.
    func apply(to image: CIImage, extent: CGRect, center: CGPoint, delta: CGVector, radius: CGFloat, displacementLimit: Double) throws -> CIImage {
        guard let kernel else { throw MellowError.warpUnavailable }
        var dx = delta.dx
        var dy = delta.dy
        let length = hypot(dx, dy)
        let limit = radius * displacementLimit
        if length > limit {
            dx *= limit / length
            dy *= limit / length
        }
        let margin = max(abs(dx), abs(dy)) + 2
        let arguments: [Any] = [CIVector(x: center.x, y: center.y), CIVector(x: dx, y: dy), radius]
        let warped = kernel.apply(
            extent: extent,
            roiCallback: { _, rect in rect.insetBy(dx: -margin, dy: -margin) },
            image: image.clampedToExtent(),
            arguments: arguments)
        guard let warped else { throw MellowError.renderFailed }
        return warped.cropped(to: extent)
    }
}
```

`apple/Sources/MellowRendering/Domain/SkinStage.swift`:

```swift
import CoreImage
import MellowShared

/// 얼굴 타원 마스크 안을 노이즈 제거·블러로 고르게 한다. 눈·입은 보호한다.
struct SkinStage: RenderStage {
    let name = "skin"

    func apply(_ image: CIImage, in context: RenderContext) throws -> CIImage {
        let strength = context.recipe.portrait.skinSmoothing
        guard strength > 0, !context.targetFaces.isEmpty else { return image }
        let extent = context.extent
        let tuning = context.tuning
        var mask = CIImage(color: .black).cropped(to: extent)
        for face in context.targetFaces {
            let faceRect = context.pixelRect(face.boundingBox)
            let inset = faceRect.insetBy(dx: faceRect.width * tuning.skinFaceInsetX, dy: faceRect.height * tuning.skinFaceInsetY)
            var local = MaskBuilder.ellipse(inset, extent: extent, strength: min(tuning.skinMaskMaxStrength, strength * tuning.skinMaskMaxStrength))
            for feature in protectedFeatures(of: face) {
                let featureRect = context.pixelRect(feature).insetBy(dx: -faceRect.width * tuning.skinFeatureInset, dy: -faceRect.height * tuning.skinFeatureInset)
                local = MaskBuilder.blend(CIImage(color: .black), over: local, mask: MaskBuilder.ellipse(featureRect, extent: extent))
            }
            mask = local.applyingFilter("CIMaximumCompositing", parameters: [kCIInputBackgroundImageKey: mask])
        }
        let blurRadius = max(tuning.skinBlurMinimumRadius, context.shortSide * tuning.skinBlurRadiusFraction)
        let smooth = image.clampedToExtent()
            .applyingFilter("CINoiseReduction", parameters: ["inputNoiseLevel": tuning.skinNoiseLevel, "inputSharpness": tuning.skinNoiseSharpness])
            .applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: blurRadius])
        return MaskBuilder.blend(smooth, over: image, mask: mask).cropped(to: extent)
    }

    /// 랜드마크가 없으면 얼굴 상자 비율로 어림한 위치를 보호한다.
    private func protectedFeatures(of face: FaceGeometry) -> [NormalizedRect] {
        let box = face.boundingBox
        let leftEye = face.bounds(of: .leftEye)
            ?? NormalizedRect(x: box.minX + box.width * 0.15, y: box.minY + box.height * 0.56, width: box.width * 0.28, height: box.height * 0.14)
        let rightEye = face.bounds(of: .rightEye)
            ?? NormalizedRect(x: box.minX + box.width * 0.57, y: box.minY + box.height * 0.56, width: box.width * 0.28, height: box.height * 0.14)
        let mouth = face.bounds(of: .outerLips)
            ?? NormalizedRect(x: box.minX + box.width * 0.25, y: box.minY + box.height * 0.18, width: box.width * 0.5, height: box.height * 0.18)
        return [leftEye, rightEye, mouth]
    }
}
```

`apple/Sources/MellowRendering/Domain/FaceReshapeStage.swift`:

```swift
import CoreImage
import MellowShared

/// A 범위에서는 얼굴 양옆을 안쪽으로 미는 faceSlim만 담는다. C에서 부위별로 확장된다.
struct FaceReshapeStage: RenderStage {
    let name = "faceReshape"

    func apply(_ image: CIImage, in context: RenderContext) throws -> CIImage {
        let amount = context.recipe.portrait.faceSlim
        guard amount > 0, !context.targetFaces.isEmpty else { return image }
        var result = image
        for face in context.targetFaces {
            for stroke in slimStrokes(for: face, amount: amount, context: context) {
                result = try LocalEditStage.applyWarp(stroke, to: result, context: context)
            }
        }
        return result
    }

    private func slimStrokes(for face: FaceGeometry, amount: Double, context: RenderContext) -> [WarpStroke] {
        let box = face.boundingBox
        let tuning = context.tuning
        let shift = min(1, amount) * box.width * tuning.faceSlimShiftFraction
        let radius = box.width * context.extent.width / context.shortSide * tuning.faceSlimRadiusFraction
        let y = box.minY + box.height * tuning.faceSlimAnchorY
        return [
            WarpStroke(x: box.minX + box.width * tuning.faceSlimAnchorX, y: y, dx: shift, dy: 0, radius: radius),
            WarpStroke(x: box.maxX - box.width * tuning.faceSlimAnchorX, y: y, dx: -shift, dy: 0, radius: radius),
        ]
    }
}
```

`apple/Sources/MellowRendering/Domain/LocalEditStage.swift`:

```swift
import CoreImage
import MellowShared

/// 사용자의 잡티·변형을 기록 순서대로 재생한다.
struct LocalEditStage: RenderStage {
    let name = "localEdit"

    func apply(_ image: CIImage, in context: RenderContext) throws -> CIImage {
        var result = image
        for operation in context.recipe.operations {
            switch operation {
            case .warp(let stroke):
                result = try Self.applyWarp(stroke, to: result, context: context)
            case .spot(let spot):
                result = Self.applySpot(spot, to: result, context: context)
            }
        }
        return result
    }

    static func applyWarp(_ stroke: WarpStroke, to image: CIImage, context: RenderContext) throws -> CIImage {
        guard stroke.radius > 0 else { return image }
        let tuning = context.tuning
        let radius = max(1, min(tuning.warpMaxRadiusFraction, stroke.radius) * context.shortSide)
        return try WarpKernel.shared.apply(
            to: image,
            extent: context.extent,
            center: context.pixelPoint(x: stroke.x, y: stroke.y),
            delta: CGVector(dx: stroke.dx * context.extent.width, dy: stroke.dy * context.extent.height),
            radius: radius,
            displacementLimit: tuning.warpDisplacementLimit)
    }

    static func applySpot(_ spot: RetouchSpot, to image: CIImage, context: RenderContext) -> CIImage {
        guard spot.radius > 0 else { return image }
        let extent = context.extent
        let radius = min(context.tuning.spotMaxRadiusFraction, spot.radius) * context.shortSide
        let center = context.pixelPoint(x: spot.x, y: spot.y)
        let offset = CGAffineTransform(translationX: (spot.x - spot.sourceX) * extent.width, y: (spot.y - spot.sourceY) * extent.height)
        let source = image.clampedToExtent().transformed(by: offset)
        let mask = MaskBuilder.ellipse(CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2), extent: extent)
        return MaskBuilder.blend(source, over: image, mask: mask).cropped(to: extent)
    }
}
```

`apple/Sources/MellowRendering/Domain/ColorStage.swift`:

```swift
import CoreImage
import MellowShared

struct ColorStage: RenderStage {
    let name = "color"

    func apply(_ image: CIImage, in context: RenderContext) throws -> CIImage {
        let color = context.recipe.color
        let tuning = context.tuning
        var result = image
        if color.exposure != 0 {
            result = result.applyingFilter("CIExposureAdjust", parameters: [kCIInputEVKey: color.exposure])
        }
        if color.contrast != 1 || color.saturation != 1 {
            result = result.applyingFilter("CIColorControls", parameters: [kCIInputContrastKey: color.contrast, kCIInputSaturationKey: color.saturation])
        }
        if color.warmth != 0 {
            let clamped = max(-1, min(1, color.warmth))
            result = result.applyingFilter("CITemperatureAndTint", parameters: [
                "inputNeutral": CIVector(x: tuning.neutralKelvin, y: 0),
                "inputTargetNeutral": CIVector(x: tuning.neutralKelvin - clamped * tuning.warmthKelvinRange, y: 0),
            ])
        }
        return result
    }
}
```

- [ ] **Step 4: 통과 확인**

Run: `cd apple && swift test --filter MellowRenderingTests`
Expected: 12 tests PASS. GPU 접근이 막힌 환경이면 실패하므로 로컬 Mac에서 실행한다.

- [ ] **Step 5: 커밋**

```bash
git add apple/Sources/MellowRendering apple/Tests/MellowRenderingTests
git commit -m "refactor(rendering): 렌더 엔진을 단계 파이프라인으로 분해

70줄짜리 render()를 피부·얼굴 형태·수동 편집·색감 네 단계로 나누고
상수를 RenderTuning에 모은다. 출력은 기존 회귀 테스트로 동일함을 확인한다.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 6: MellowRendering — 얼굴 분석기와 PhotoPipeline 캐시

**Files:**
- Create: `apple/Sources/MellowRendering/API/FaceAnalyzer.swift` (프로토콜)
- Create: `apple/Sources/MellowRendering/Infrastructure/VisionFaceAnalyzer.swift`
- Create: `apple/Sources/MellowRendering/API/PhotoPipeline.swift` (PreparedPhoto 포함)
- Create: `apple/Sources/MellowRendering/Domain/PreviewCache.swift`
- Create: `apple/Tests/MellowRenderingTests/Fixtures/demo-portrait.png` (`docs/store-assets/demo-portrait.png` 복사. 원본 이동은 Task 12)
- Test: `apple/Tests/MellowRenderingTests/VisionFaceAnalyzerTests.swift`
- Test: `apple/Tests/MellowRenderingTests/PhotoPipelineTests.swift`

**Interfaces:**
- Consumes: Task 5 전부, `FaceGeometry`, `FaceLandmark`.
- Produces: `FaceAnalyzer.analyze(_:) throws -> [FaceGeometry]`, `VisionFaceAnalyzer()`, `PreparedPhoto(pixelSize:thumbnail:faces:faceAnalysisFailure:)`, `PhotoPipeline(analyzer:tuning:)`, `prepare(_:at:)`, `preview(_:recipe:)`, `renderOriginal(_:at:recipe:maxDimension:)`, `evict(_:)`. Task 7·9가 쓴다.

- [ ] **Step 1: 실패하는 테스트 작성**

`apple/Tests/MellowRenderingTests/VisionFaceAnalyzerTests.swift`:

```swift
import CoreImage
import MellowShared
import XCTest
@testable import MellowRendering

final class VisionFaceAnalyzerTests: XCTestCase {
    func testDemoPortraitYieldsFullLandmarksInImageSpace() throws {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "demo-portrait", withExtension: "png"))
        let image = try ImageLoader().load(url: url, maxDimension: 1200)
        let faces = try VisionFaceAnalyzer().analyze(image)
        let face = try XCTUnwrap(faces.first)
        for landmark in [FaceLandmark.faceContour, .leftEye, .rightEye, .outerLips, .nose] {
            let points = try XCTUnwrap(face.landmarks[landmark], "\(landmark) 누락")
            XCTAssertGreaterThan(points.count, 2)
            for point in points {
                XCTAssertGreaterThanOrEqual(point.x, face.boundingBox.minX - 0.05)
                XCTAssertLessThanOrEqual(point.x, face.boundingBox.maxX + 0.05)
                XCTAssertGreaterThanOrEqual(point.y, face.boundingBox.minY - 0.05)
                XCTAssertLessThanOrEqual(point.y, face.boundingBox.maxY + 0.05)
            }
        }
        let leftEye = try XCTUnwrap(face.bounds(of: .leftEye))
        let mouth = try XCTUnwrap(face.bounds(of: .outerLips))
        XCTAssertGreaterThan(leftEye.midY, mouth.midY, "눈은 입보다 위(원점이 왼쪽 아래)")
    }

    func testFacesAreOrderedLeftToRight() throws {
        let analyzer = VisionFaceAnalyzer()
        let blank = CIImage(color: CIColor(red: 0.5, green: 0.4, blue: 0.3)).cropped(to: CGRect(x: 0, y: 0, width: 64, height: 64))
        XCTAssertEqual(try analyzer.analyze(blank).count, 0)
        let faces = [
            FaceGeometry(boundingBox: NormalizedRect(x: 0.6, y: 0, width: 0.2, height: 0.2)),
            FaceGeometry(boundingBox: NormalizedRect(x: 0.1, y: 0, width: 0.2, height: 0.2)),
        ]
        XCTAssertEqual(VisionFaceAnalyzer.orderedLeftToRight(faces).map(\.boundingBox.minX), [0.1, 0.6])
    }
}
```

`apple/Tests/MellowRenderingTests/PhotoPipelineTests.swift`:

```swift
import CoreImage
import MellowShared
import XCTest
@testable import MellowRendering

struct StubFaceAnalyzer: FaceAnalyzer {
    var result: Result<[FaceGeometry], MellowError>
    func analyze(_ image: CIImage) throws -> [FaceGeometry] { try result.get() }
}

final class PhotoPipelineTests: XCTestCase {
    typealias Support = RenderingTestSupport

    private func writeSolidPNG(size: Int = 256) throws -> URL {
        let directory = try Support.temporaryDirectory()
        let url = directory.appendingPathComponent("solid.png")
        let cg = try Support.renderer.makeCGImage(Support.solid(CIColor(red: 0.5, green: 0.4, blue: 0.3), size: size))
        let destination = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil)!
        CGImageDestinationAddImage(destination, cg, nil)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        return url
    }

    func testPrepareReportsSizeThumbnailAndFaces() async throws {
        let url = try writeSolidPNG()
        let face = FaceGeometry(boundingBox: NormalizedRect(x: 0.2, y: 0.2, width: 0.6, height: 0.6))
        let pipeline = PhotoPipeline(analyzer: StubFaceAnalyzer(result: .success([face])), tuning: RenderTuning())
        let prepared = try await pipeline.prepare(PhotoID(), at: url)
        XCTAssertEqual(prepared.pixelSize, CGSize(width: 256, height: 256))
        XCTAssertEqual(prepared.faces, [face])
        XCTAssertNil(prepared.faceAnalysisFailure)
        XCTAssertLessThanOrEqual(max(prepared.thumbnail.width, prepared.thumbnail.height), RenderTuning().thumbnailMaxDimension)
    }

    func testFaceAnalysisFailureIsReportedNotThrown() async throws {
        let url = try writeSolidPNG()
        let pipeline = PhotoPipeline(analyzer: StubFaceAnalyzer(result: .failure(.faceAnalysisUnavailable(reason: "test"))), tuning: RenderTuning())
        let prepared = try await pipeline.prepare(PhotoID(), at: url)
        XCTAssertTrue(prepared.faces.isEmpty)
        XCTAssertEqual(prepared.faceAnalysisFailure, .faceAnalysisUnavailable(reason: "test"))
    }

    func testPreviewUsesCacheAndMatchesFreshRender() async throws {
        let url = try writeSolidPNG()
        let id = PhotoID()
        let pipeline = PhotoPipeline(analyzer: StubFaceAnalyzer(result: .success([])), tuning: RenderTuning())
        _ = try await pipeline.prepare(id, at: url)
        try FileManager.default.removeItem(at: url)
        var recipe = EditRecipe()
        recipe.color.exposure = 0.5
        let cached = try await pipeline.preview(id, recipe: recipe)
        XCTAssertEqual(cached.width, 256, "파일이 지워져도 캐시로 렌더된다")
        let fresh = try Support.renderer.makeCGImage(Support.render(Support.solid(CIColor(red: 0.5, green: 0.4, blue: 0.3)), recipe: recipe))
        XCTAssertEqual(Array(cached.dataProvider!.data! as Data), Array(fresh.dataProvider!.data! as Data))
    }

    func testPreviewOfUnpreparedPhotoThrows() async throws {
        let pipeline = PhotoPipeline(analyzer: StubFaceAnalyzer(result: .success([])), tuning: RenderTuning())
        do {
            _ = try await pipeline.preview(PhotoID(), recipe: EditRecipe())
            XCTFail("준비되지 않은 사진은 렌더할 수 없다")
        } catch {
            XCTAssertEqual(error as? MellowError, .cannotCreatePreview)
        }
    }

    func testCacheEvictsLeastRecentlyUsedBeyondCapacity() async throws {
        var tuning = RenderTuning()
        tuning.previewCacheCapacity = 2
        let pipeline = PhotoPipeline(analyzer: StubFaceAnalyzer(result: .success([])), tuning: tuning)
        let ids = [PhotoID(), PhotoID(), PhotoID()]
        for id in ids {
            _ = try await pipeline.prepare(id, at: try writeSolidPNG())
        }
        let cached = await pipeline.cachedPreviewIDs
        XCTAssertEqual(Set(cached), Set(ids.dropFirst()))
    }

    func testRenderOriginalRefusesFaceEditsWhenAnalysisFailed() async throws {
        let url = try writeSolidPNG()
        let id = PhotoID()
        let pipeline = PhotoPipeline(analyzer: StubFaceAnalyzer(result: .failure(.faceAnalysisUnavailable(reason: "test"))), tuning: RenderTuning())
        _ = try await pipeline.prepare(id, at: url)
        var recipe = EditRecipe()
        recipe.portrait.skinSmoothing = 0.3
        do {
            _ = try await pipeline.renderOriginal(id, at: url, recipe: recipe, maxDimension: nil)
            XCTFail("얼굴 보정이 조용히 빠지면 안 된다")
        } catch {
            XCTAssertEqual(error as? MellowError, .faceAnalysisUnavailable(reason: "test"))
        }
        recipe.portrait.skinSmoothing = 0
        recipe.color.exposure = 0.2
        let rendered = try await pipeline.renderOriginal(id, at: url, recipe: recipe, maxDimension: nil)
        XCTAssertEqual(rendered.extent.size, CGSize(width: 256, height: 256))
    }

    func testRenderOriginalWithNoFacesAndSkinValueSucceeds() async throws {
        let url = try writeSolidPNG()
        let id = PhotoID()
        let pipeline = PhotoPipeline(analyzer: StubFaceAnalyzer(result: .success([])), tuning: RenderTuning())
        _ = try await pipeline.prepare(id, at: url)
        var recipe = EditRecipe()
        recipe.portrait.skinSmoothing = 0.3
        recipe.color.exposure = 0.2
        let rendered = try await pipeline.renderOriginal(id, at: url, recipe: recipe, maxDimension: 128)
        XCTAssertEqual(rendered.extent.size, CGSize(width: 128, height: 128), "분석은 성공했고 얼굴만 없으면 색감만 적용해 저장한다")
    }
}
```

- [ ] **Step 2: 실패 확인**

Run: `cd apple && swift test --filter 'VisionFaceAnalyzerTests|PhotoPipelineTests'`
Expected: 컴파일 실패.

- [ ] **Step 3: 구현**

`apple/Sources/MellowRendering/API/FaceAnalyzer.swift`:

```swift
import CoreImage
import MellowShared

public protocol FaceAnalyzer: Sendable {
    /// 왼쪽부터 정렬된 얼굴. 분석 자체가 불가능하면 MellowError.faceAnalysisUnavailable.
    func analyze(_ image: CIImage) throws -> [FaceGeometry]
}
```

`apple/Sources/MellowRendering/Infrastructure/VisionFaceAnalyzer.swift`:

```swift
import CoreImage
import MellowShared
import Vision

public struct VisionFaceAnalyzer: FaceAnalyzer {
    public init() {}

    public func analyze(_ image: CIImage) throws -> [FaceGeometry] {
        let request = VNDetectFaceLandmarksRequest()
        #if targetEnvironment(simulator)
        // 시뮬레이터는 실기기의 모든 추론 백엔드를 쓰지 못한다.
        request.usesCPUOnly = true
        #endif
        do {
            try VNImageRequestHandler(ciImage: image, options: [:]).perform([request])
        } catch {
            throw MellowError.faceAnalysisUnavailable(reason: error.localizedDescription)
        }
        let faces = (request.results ?? []).map(Self.geometry(from:))
        return Self.orderedLeftToRight(faces)
    }

    public static func orderedLeftToRight(_ faces: [FaceGeometry]) -> [FaceGeometry] {
        faces.sorted { $0.boundingBox.minX < $1.boundingBox.minX }
    }

    private static func geometry(from observation: VNFaceObservation) -> FaceGeometry {
        let box = observation.boundingBox
        var landmarks: [FaceLandmark: [NormalizedPoint]] = [:]
        if let all = observation.landmarks {
            let regions: [(FaceLandmark, VNFaceLandmarkRegion2D?)] = [
                (.faceContour, all.faceContour), (.leftEye, all.leftEye), (.rightEye, all.rightEye),
                (.leftEyebrow, all.leftEyebrow), (.rightEyebrow, all.rightEyebrow), (.nose, all.nose),
                (.noseCrest, all.noseCrest), (.medianLine, all.medianLine), (.outerLips, all.outerLips),
                (.innerLips, all.innerLips), (.leftPupil, all.leftPupil), (.rightPupil, all.rightPupil),
            ]
            for (landmark, region) in regions {
                guard let region, region.pointCount > 0 else { continue }
                // normalizedPoints는 얼굴 상자 기준. 이미지 좌표로 옮긴다.
                landmarks[landmark] = region.normalizedPoints.map { point in
                    NormalizedPoint(x: box.minX + Double(point.x) * box.width, y: box.minY + Double(point.y) * box.height)
                }
            }
        }
        return FaceGeometry(
            boundingBox: NormalizedRect(cgRect: box),
            landmarks: landmarks,
            roll: observation.roll.map(\.doubleValue),
            yaw: observation.yaw.map(\.doubleValue))
    }
}
```

`apple/Sources/MellowRendering/Domain/PreviewCache.swift`:

```swift
import CoreImage
import MellowShared

/// 최근 사용 순서를 유지하는 작은 캐시. 미리보기 CIImage는 수 MB라 몇 장만 든다.
struct PreviewCache {
    private(set) var capacity: Int
    private var images: [PhotoID: CIImage] = [:]
    private var order: [PhotoID] = []

    init(capacity: Int) {
        self.capacity = max(1, capacity)
    }

    var ids: [PhotoID] { order }

    mutating func image(for id: PhotoID) -> CIImage? {
        guard let image = images[id] else { return nil }
        touch(id)
        return image
    }

    mutating func insert(_ image: CIImage, for id: PhotoID) {
        images[id] = image
        touch(id)
        while order.count > capacity, let oldest = order.first {
            order.removeFirst()
            images[oldest] = nil
        }
    }

    mutating func remove(_ id: PhotoID) {
        images[id] = nil
        order.removeAll { $0 == id }
    }

    private mutating func touch(_ id: PhotoID) {
        order.removeAll { $0 == id }
        order.append(id)
    }
}
```

`apple/Sources/MellowRendering/API/PhotoPipeline.swift`:

```swift
import CoreImage
import Foundation
import MellowShared

public struct PreparedPhoto: Sendable {
    public let pixelSize: CGSize
    public let thumbnail: CGImage
    public let faces: [FaceGeometry]
    /// 분석이 실패했으면 그 이유. 얼굴이 없는 것과 구분한다.
    public let faceAnalysisFailure: MellowError?
}

/// 무거운 이미지 작업을 메인 액터 밖에서 직렬로 수행한다. 미리보기는 캐시에서 렌더한다.
public actor PhotoPipeline {
    private struct Entry {
        var faces: [FaceGeometry]
        var faceAnalysisFailure: MellowError?
    }

    private let loader = ImageLoader()
    private let renderer = Renderer()
    private let pipeline = RenderPipeline.standard
    private let analyzer: any FaceAnalyzer
    private let tuning: RenderTuning
    private var entries: [PhotoID: Entry] = [:]
    private var cache: PreviewCache

    public init(analyzer: any FaceAnalyzer, tuning: RenderTuning) {
        self.analyzer = analyzer
        self.tuning = tuning
        cache = PreviewCache(capacity: tuning.previewCacheCapacity)
    }

    /// 테스트용. 캐시에 든 사진 ID.
    var cachedPreviewIDs: [PhotoID] { cache.ids }

    public func prepare(_ id: PhotoID, at url: URL) throws -> PreparedPhoto {
        let metadata = try loader.metadata(url: url)
        let preview = try loader.load(url: url, maxDimension: tuning.previewMaxDimension)
        var faces: [FaceGeometry] = []
        var failure: MellowError?
        do {
            faces = try analyzer.analyze(preview)
        } catch let error as MellowError {
            failure = error
        } catch {
            failure = .faceAnalysisUnavailable(reason: error.localizedDescription)
        }
        entries[id] = Entry(faces: faces, faceAnalysisFailure: failure)
        cache.insert(preview, for: id)
        let thumbnail = try renderer.makeCGImage(Self.scaled(preview, maxDimension: tuning.thumbnailMaxDimension))
        return PreparedPhoto(pixelSize: metadata.pixelSize, thumbnail: thumbnail, faces: faces, faceAnalysisFailure: failure)
    }

    /// 캐시가 비었으면 cannotCreatePreview. 호출자가 prepare를 다시 한다.
    public func preview(_ id: PhotoID, recipe: EditRecipe) throws -> CGImage {
        guard let entry = entries[id], let image = cache.image(for: id) else { throw MellowError.cannotCreatePreview }
        let context = RenderContext(extent: image.extent, recipe: recipe, faces: entry.faces, tuning: tuning)
        return try renderer.makeCGImage(pipeline.render(image, context: context))
    }

    public func reprepareIfEvicted(_ id: PhotoID, at url: URL) throws {
        guard cache.image(for: id) == nil else { return }
        _ = try prepare(id, at: url)
    }

    /// 준비 때 얻은 정규화 얼굴 좌표를 원본 해상도에 그대로 쓴다. 얼굴을 다시 분석하지 않는다.
    public func renderOriginal(_ id: PhotoID, at url: URL, recipe: EditRecipe, maxDimension: Int?) throws -> CIImage {
        let entry = entries[id] ?? Entry(faces: [], faceAnalysisFailure: nil)
        if recipe.dependsOnFaces, entry.faces.isEmpty, let failure = entry.faceAnalysisFailure {
            throw failure
        }
        let image = try loader.load(url: url, maxDimension: maxDimension)
        let context = RenderContext(extent: image.extent, recipe: recipe, faces: entry.faces, tuning: tuning)
        return try pipeline.render(image, context: context)
    }

    public func makeCGImage(_ image: CIImage) throws -> CGImage {
        try renderer.makeCGImage(image)
    }

    public func evict(_ id: PhotoID) {
        entries[id] = nil
        cache.remove(id)
    }

    private static func scaled(_ image: CIImage, maxDimension: Int) -> CIImage {
        let longest = max(image.extent.width, image.extent.height)
        guard longest > CGFloat(maxDimension) else { return image }
        let scale = CGFloat(maxDimension) / longest
        return image.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
    }
}
```

- [ ] **Step 4: 통과 확인**

Run: `cd apple && swift test --filter MellowRenderingTests`
Expected: 21 tests PASS.

- [ ] **Step 5: 커밋**

```bash
git add apple/Sources/MellowRendering apple/Tests/MellowRenderingTests
git commit -m "feat(rendering): 전체 랜드마크 얼굴 분석기와 미리보기 캐시 추가

Vision이 주는 76개 점을 버리지 않고 보관해 후속 리셰이프 작업의
기반을 만들고, 슬라이더마다 디스크를 다시 읽던 iPhone 동작을 없앤다.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 7: MellowExport — 저장기·이름 정책·대상 포트

**Files:**
- Delete: `apple/Sources/MellowExport/Placeholder.swift`, `apple/Tests/MellowExportTests/PlaceholderTests.swift`
- Create: `apple/Sources/MellowExport/API/ExportFormat.swift` (ExportFormat, ExportOptions)
- Create: `apple/Sources/MellowExport/API/Exporter.swift`
- Create: `apple/Sources/MellowExport/API/FileNamingPolicy.swift`
- Create: `apple/Sources/MellowExport/API/ExportDestination.swift`
- Test: `apple/Tests/MellowExportTests/ExporterTests.swift`
- Test: `apple/Tests/MellowExportTests/FileNamingPolicyTests.swift`

**Interfaces:**
- Consumes: `Renderer`, `ImageLoader` (Task 5), `MellowError`.
- Produces: `ExportFormat`(`jpeg`, `png`, `fileExtension`), `ExportOptions(format:fullResolution:quality:)`, `ExportOptions.defaultMaxDimension`, `ExportOptions.maxDimension`, `Exporter(renderer:)`, `Exporter.write(_:to:format:quality:)`, `FileNamingPolicy.availableURL(in:stem:fileExtension:exists:)`, `ExportDestination.publish(fileURL:suggestedName:)`. Task 9·10이 쓴다.

- [ ] **Step 1: 실패하는 테스트 작성**

`apple/Tests/MellowExportTests/ExporterTests.swift`:

```swift
import CoreImage
import ImageIO
import MellowRendering
import MellowShared
import XCTest
@testable import MellowExport

final class ExporterTests: XCTestCase {
    private let renderer = Renderer()

    private func gradient() -> CIImage {
        CIFilter(name: "CILinearGradient", parameters: [
            "inputPoint0": CIVector(x: 0, y: 0), "inputPoint1": CIVector(x: 128, y: 0),
            "inputColor0": CIColor(red: 0.1, green: 0.2, blue: 0.3), "inputColor1": CIColor(red: 0.9, green: 0.6, blue: 0.4),
        ])!.outputImage!.cropped(to: CGRect(x: 0, y: 0, width: 128, height: 80))
    }

    func testWritesVerifiableSRGB8BitWithoutGPSAndRefusesOverwrite() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let exporter = Exporter(renderer: renderer)
        for format in ExportFormat.allCases {
            let url = directory.appendingPathComponent("photo.\(format.fileExtension)")
            try exporter.write(gradient(), to: url, format: format, quality: 0.94)
            let before = try Data(contentsOf: url)
            XCTAssertThrowsError(try exporter.write(gradient(), to: url, format: format, quality: 0.94)) { error in
                XCTAssertEqual(error as? MellowError, .fileAlreadyExists)
            }
            XCTAssertEqual(try Data(contentsOf: url), before)
            XCTAssertEqual(try ImageLoader().load(url: url).extent.size, CGSize(width: 128, height: 80))
            let source = CGImageSourceCreateWithURL(url as CFURL, nil)!
            let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil)! as NSDictionary
            XCTAssertNil(properties[kCGImagePropertyGPSDictionary])
            let cg = CGImageSourceCreateImageAtIndex(source, 0, nil)!
            XCTAssertEqual(cg.bitsPerComponent, 8)
            XCTAssertEqual(cg.colorSpace?.name, CGColorSpace.sRGB)
        }
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: directory.path).filter { $0.hasPrefix(".mellow-") }.count, 0, "임시 파일이 남지 않는다")
    }

    func testWriteIntoMissingFolderFails() {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent("x.jpg")
        XCTAssertThrowsError(try Exporter(renderer: renderer).write(gradient(), to: url, format: .jpeg, quality: 0.9)) { error in
            XCTAssertEqual(error as? MellowError, .cannotWriteToFolder)
        }
    }

    func testOptionsResolveMaxDimension() {
        XCTAssertNil(ExportOptions(format: .jpeg, fullResolution: true).maxDimension)
        XCTAssertEqual(ExportOptions(format: .jpeg, fullResolution: false).maxDimension, ExportOptions.defaultMaxDimension)
    }
}
```

`apple/Tests/MellowExportTests/FileNamingPolicyTests.swift`:

```swift
import XCTest
@testable import MellowExport

final class FileNamingPolicyTests: XCTestCase {
    func testAppendsMellowSuffixAndCountsUpOnCollision() {
        let folder = URL(fileURLWithPath: "/tmp/out")
        let taken: Set<String> = ["IMG_1_mellow.jpg", "IMG_1_mellow_2.jpg"]
        let url = FileNamingPolicy.availableURL(in: folder, stem: "IMG_1", fileExtension: "jpg") { taken.contains($0.lastPathComponent) }
        XCTAssertEqual(url.lastPathComponent, "IMG_1_mellow_3.jpg")
        let free = FileNamingPolicy.availableURL(in: folder, stem: "IMG_2", fileExtension: "png") { _ in false }
        XCTAssertEqual(free.lastPathComponent, "IMG_2_mellow.png")
    }
}
```

- [ ] **Step 2: 실패 확인**

Run: `cd apple && swift test --filter MellowExportTests`
Expected: 컴파일 실패.

- [ ] **Step 3: 구현**

`apple/Sources/MellowExport/API/ExportFormat.swift`:

```swift
import UniformTypeIdentifiers

public enum ExportFormat: String, CaseIterable, Codable, Sendable {
    case jpeg
    case png

    public var fileExtension: String {
        switch self {
        case .jpeg: return "jpg"
        case .png: return "png"
        }
    }

    var typeIdentifier: String {
        switch self {
        case .jpeg: return UTType.jpeg.identifier
        case .png: return UTType.png.identifier
        }
    }
}

public struct ExportOptions: Equatable, Sendable {
    /// 원본 해상도를 끄면 긴 변을 이 값으로 제한한다. 오래된 iPhone을 위한 보수적 기본값.
    public static let defaultMaxDimension = 4096
    public static let defaultQuality = 0.94

    public var format: ExportFormat
    public var fullResolution: Bool
    public var quality: Double

    public init(format: ExportFormat = .jpeg, fullResolution: Bool = false, quality: Double = ExportOptions.defaultQuality) {
        self.format = format
        self.fullResolution = fullResolution
        self.quality = quality
    }

    public var maxDimension: Int? {
        fullResolution ? nil : Self.defaultMaxDimension
    }
}
```

`apple/Sources/MellowExport/API/Exporter.swift`:

```swift
import CoreImage
import Darwin
import Foundation
import ImageIO
import MellowRendering
import MellowShared

/// 임시 파일에 쓰고 재해독으로 검증한 뒤 배타적 rename으로 공개한다.
public struct Exporter: Sendable {
    private let renderer: Renderer

    public init(renderer: Renderer) {
        self.renderer = renderer
    }

    public func write(_ image: CIImage, to url: URL, format: ExportFormat, quality: Double) throws {
        let cg = try renderer.makeCGImage(image)
        let temporary = url.deletingLastPathComponent().appendingPathComponent(".mellow-\(UUID().uuidString).tmp")
        defer { try? FileManager.default.removeItem(at: temporary) }
        guard let destination = CGImageDestinationCreateWithURL(temporary as CFURL, format.typeIdentifier as CFString, 1, nil) else {
            throw MellowError.cannotWriteToFolder
        }
        let properties: [CFString: Any] = [
            kCGImageDestinationLossyCompressionQuality: max(0, min(1, quality)),
            kCGImagePropertyOrientation: 1,
        ]
        CGImageDestinationAddImage(destination, cg, properties as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw MellowError.exportVerificationFailed }
        try verify(temporary, width: cg.width, height: cg.height)
        try publishExclusively(temporary, to: url)
    }

    private func verify(_ url: URL, width: Int, height: Int) throws {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
            let decoded = CGImageSourceCreateImageAtIndex(source, 0, nil),
            decoded.width == width, decoded.height == height
        else {
            throw MellowError.exportVerificationFailed
        }
    }

    /// 같은 폴더 안의 배타적 rename은 하드링크 없는 exFAT에서도 원자적이다.
    private func publishExclusively(_ source: URL, to destination: URL) throws {
        let status = source.withUnsafeFileSystemRepresentation { from in
            destination.withUnsafeFileSystemRepresentation { to in
                renameatx_np(AT_FDCWD, from!, AT_FDCWD, to!, UInt32(RENAME_EXCL))
            }
        }
        guard status == 0 else {
            if errno == EEXIST { throw MellowError.fileAlreadyExists }
            throw MellowError.exportFailed(reason: String(cString: strerror(errno)))
        }
    }
}
```

`apple/Sources/MellowExport/API/FileNamingPolicy.swift`:

```swift
import Foundation

public enum FileNamingPolicy {
    public static let suffix = "_mellow"

    /// "<stem>_mellow.<ext>", 충돌하면 "_2", "_3"… 을 붙인다.
    public static func availableURL(in folder: URL, stem: String, fileExtension: String, exists: (URL) -> Bool) -> URL {
        let base = stem + suffix
        var candidate = folder.appendingPathComponent(base).appendingPathExtension(fileExtension)
        var counter = 2
        while exists(candidate) {
            candidate = folder.appendingPathComponent("\(base)_\(counter)").appendingPathExtension(fileExtension)
            counter += 1
        }
        return candidate
    }
}
```

`apple/Sources/MellowExport/API/ExportDestination.swift`:

```swift
import Foundation

/// 완성된 파일을 사용자가 보는 곳(사진 앱, 폴더)으로 옮긴다. 구현은 앱 타깃에 있다.
public protocol ExportDestination: Sendable {
    func publish(fileURL: URL, suggestedName: String) async throws
}
```

- [ ] **Step 4: 통과 확인**

Run: `cd apple && swift test`
Expected: 전 모듈 PASS. 이어서 `swift format lint --strict --recursive apple/Sources apple/Tests` 경고 0.

- [ ] **Step 5: 커밋**

```bash
git add apple/Sources/MellowExport apple/Tests/MellowExportTests
git commit -m "refactor(export): 저장기와 이름 충돌 정책을 내보내기 모듈로 분리

원자적 저장·검증은 기존 동작 그대로 두고, Mac 저장소에 있던 이름 충돌
규칙을 플랫폼 독립 정책으로 옮긴다. 저장 대상은 포트로 추상화한다.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 8: 멀티플랫폼 앱 타깃 골격 (XcodeGen)

**Files:**
- Create: `apple/project.yml`
- Create: `apple/Config/Version.xcconfig`
- Create: `apple/MellowPhoto/App/MellowPhotoApp.swift`
- Create: `apple/MellowPhoto/App/RootView.swift` (임시 셸. Task 11이 교체)
- Create: `apple/MellowPhoto/Resources/Info-iOS.plist`, `Info-macOS.plist`
- Create: `apple/MellowPhoto/Resources/MellowPhoto-macOS.entitlements`
- Create: `apple/MellowPhoto/Resources/PrivacyInfo.xcprivacy` (`iOS/MellowPhoto/PrivacyInfo.xcprivacy` 복사)
- Create: `apple/MellowPhoto/Resources/Assets.xcassets/` (`iOS/MellowPhoto/Assets.xcassets` 복사 후 AppIcon에 macOS 항목 추가)
- Create: `apple/MellowPhoto/Resources/Localizable.xcstrings` (빈 카탈로그 `{"sourceLanguage":"ko","strings":{},"version":"1.0"}`)
- Create: `apple/MellowPhotoTests/SmokeTests.swift`
- Generate: `apple/MellowPhoto.xcodeproj` (커밋)
- Modify: `.gitignore` (`apple/MellowPhoto.xcodeproj/xcuserdata/`, `apple/MellowPhoto.xcodeproj/project.xcworkspace/xcuserdata/`)

**Interfaces:**
- Consumes: MellowKit 패키지 (Task 1~7).
- Produces: 스킴 `MellowPhoto`(앱)와 테스트 번들 `MellowPhotoTests`. Task 9~11이 이 타깃에 파일을 추가하고 `xcodegen generate`를 다시 실행한다.

- [ ] **Step 1: XcodeGen 설치 확인**

Run: `which xcodegen || brew install xcodegen`
Expected: `/opt/homebrew/bin/xcodegen`. 2.38 이상이어야 `supportedDestinations`를 지원한다 (`xcodegen --version`).

- [ ] **Step 2: 프로젝트 정의 작성**

`apple/Config/Version.xcconfig`:

```
// scripts/release.sh가 갱신한다. 직접 고치지 않는다.
MARKETING_VERSION = 0.3.0
CURRENT_PROJECT_VERSION = 1
```

`apple/project.yml`:

```yaml
name: MellowPhoto
options:
  bundleIdPrefix: com.mj
  deploymentTarget:
    iOS: "17.0"
    macOS: "14.0"
  xcodeVersion: "16.0"
  createIntermediateGroups: true
  generateEmptyDirectories: true
configFiles:
  Debug: Config/Version.xcconfig
  Release: Config/Version.xcconfig
packages:
  MellowKit:
    path: .
settings:
  base:
    SWIFT_VERSION: "5.0"
    SWIFT_STRICT_CONCURRENCY: complete
    ENABLE_USER_SCRIPT_SANDBOXING: YES
    SWIFT_EMIT_LOC_STRINGS: YES
    DEVELOPMENT_TEAM: ""
  configs:
    Debug:
      ONLY_ACTIVE_ARCH: YES
targets:
  MellowPhoto:
    type: application
    supportedDestinations: [iOS, macOS]
    sources:
      - path: MellowPhoto
        excludes: ["Resources/Info-*.plist"]
    dependencies:
      - package: MellowKit
        product: MellowShared
      - package: MellowKit
        product: MellowEditing
      - package: MellowKit
        product: MellowLibrary
      - package: MellowKit
        product: MellowRendering
      - package: MellowKit
        product: MellowExport
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: com.mj.mellowphoto
        PRODUCT_NAME: Mellow Photo
        TARGETED_DEVICE_FAMILY: "1,2"
        SUPPORTS_MACCATALYST: NO
        SUPPORTS_MAC_DESIGNED_FOR_IPHONE_IPAD: NO
        ASSETCATALOG_COMPILER_APPICON_NAME: AppIcon
        GENERATE_INFOPLIST_FILE: NO
        "INFOPLIST_FILE[sdk=iphoneos*]": MellowPhoto/Resources/Info-iOS.plist
        "INFOPLIST_FILE[sdk=iphonesimulator*]": MellowPhoto/Resources/Info-iOS.plist
        "INFOPLIST_FILE[sdk=macosx*]": MellowPhoto/Resources/Info-macOS.plist
        "CODE_SIGN_ENTITLEMENTS[sdk=macosx*]": MellowPhoto/Resources/MellowPhoto-macOS.entitlements
        CODE_SIGN_STYLE: Automatic
        "CODE_SIGN_IDENTITY[sdk=macosx*]": "-"
        ENABLE_HARDENED_RUNTIME: NO
        LD_RUNPATH_SEARCH_PATHS: "$(inherited) @executable_path/Frameworks @executable_path/../Frameworks"
  MellowPhotoTests:
    type: bundle.unit-test
    supportedDestinations: [iOS, macOS]
    sources: [MellowPhotoTests]
    dependencies:
      - target: MellowPhoto
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: com.mj.mellowphoto.tests
        GENERATE_INFOPLIST_FILE: YES
        TARGETED_DEVICE_FAMILY: "1,2"
schemes:
  MellowPhoto:
    build:
      targets:
        MellowPhoto: all
        MellowPhotoTests: [test]
    run:
      config: Debug
    test:
      config: Debug
      targets: [MellowPhotoTests]
    archive:
      config: Release
```

`apple/MellowPhoto/Resources/Info-iOS.plist`는 현재 `iOS/MellowPhoto/Info.plist`와 같되 `UISupportedInterfaceOrientations`에 iPad용 가로 두 값을 더한다:

```xml
<key>UISupportedInterfaceOrientations</key>
<array>
    <string>UIInterfaceOrientationPortrait</string>
</array>
<key>UISupportedInterfaceOrientations~ipad</key>
<array>
    <string>UIInterfaceOrientationPortrait</string>
    <string>UIInterfaceOrientationPortraitUpsideDown</string>
    <string>UIInterfaceOrientationLandscapeLeft</string>
    <string>UIInterfaceOrientationLandscapeRight</string>
</array>
```

`apple/MellowPhoto/Resources/Info-macOS.plist`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDisplayName</key><string>Mellow Photo</string>
    <key>CFBundleExecutable</key><string>$(EXECUTABLE_NAME)</string>
    <key>CFBundleIdentifier</key><string>$(PRODUCT_BUNDLE_IDENTIFIER)</string>
    <key>CFBundleName</key><string>$(PRODUCT_NAME)</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>$(MARKETING_VERSION)</string>
    <key>CFBundleVersion</key><string>$(CURRENT_PROJECT_VERSION)</string>
    <key>ITSAppUsesNonExemptEncryption</key><false/>
    <key>LSApplicationCategoryType</key><string>public.app-category.photography</string>
    <key>LSMinimumSystemVersion</key><string>$(MACOSX_DEPLOYMENT_TARGET)</string>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSPhotoLibraryAddUsageDescription</key><string>보정한 사진을 사진 앱에 새 사진으로 저장합니다. 원본은 변경하지 않습니다.</string>
</dict>
</plist>
```

`apple/MellowPhoto/Resources/MellowPhoto-macOS.entitlements`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>com.apple.security.app-sandbox</key><true/>
    <key>com.apple.security.files.user-selected.read-write</key><true/>
</dict>
</plist>
```

Assets의 `AppIcon.appiconset/Contents.json`에 macOS 항목을 추가한다 (같은 1024 PNG를 쓴다):

```json
{
  "images": [
    { "filename": "AppIcon.png", "idiom": "universal", "platform": "ios", "size": "1024x1024" },
    { "filename": "AppIcon.png", "idiom": "mac", "scale": "1x", "size": "512x512" },
    { "filename": "AppIcon.png", "idiom": "mac", "scale": "2x", "size": "512x512" }
  ],
  "info": { "author": "xcode", "version": 1 }
}
```

- [ ] **Step 3: 앱 진입점과 임시 셸 작성**

`apple/MellowPhoto/App/MellowPhotoApp.swift`:

```swift
import SwiftUI

@main
struct MellowPhotoApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
        }
    }
}
```

`apple/MellowPhoto/App/RootView.swift`:

```swift
import MellowShared
import SwiftUI

/// Task 11이 EditorScene으로 교체한다.
struct RootView: View {
    var body: some View {
        Text("Mellow Photo · \(BuiltInPresets.all.count)개 프리셋")
            .padding()
    }
}
```

`apple/MellowPhotoTests/SmokeTests.swift`:

```swift
import MellowShared
import XCTest
@testable import Mellow_Photo

final class SmokeTests: XCTestCase {
    func testAppTargetLinksMellowKit() {
        XCTAssertEqual(BuiltInPresets.all.count, 3)
    }
}
```

주의: 제품 이름이 `Mellow Photo`이므로 모듈 이름은 `Mellow_Photo`다. 이후 테스트 파일은 모두 `@testable import Mellow_Photo`를 쓴다.

- [ ] **Step 4: 프로젝트 생성과 세 플랫폼 빌드**

Run:
```bash
cd apple && xcodegen generate
xcodebuild -project MellowPhoto.xcodeproj -scheme MellowPhoto -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build | tail -3
xcodebuild -project MellowPhoto.xcodeproj -scheme MellowPhoto -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO build | tail -3
xcodebuild -project MellowPhoto.xcodeproj -scheme MellowPhoto -destination "platform=iOS Simulator,name=iPhone 17" test | tail -5
xcodebuild -project MellowPhoto.xcodeproj -scheme MellowPhoto -destination "platform=iOS Simulator,name=iPad Pro 11-inch (M5)" test | tail -5
xcodebuild -project MellowPhoto.xcodeproj -scheme MellowPhoto -destination 'platform=macOS' test | tail -5
```
Expected: 세 빌드 `** BUILD SUCCEEDED **`, 세 테스트 `** TEST SUCCEEDED **`. 시뮬레이터 이름은 `xcrun simctl list devices available`로 확인한다. macOS에서 샌드박스 + 임시 서명으로 테스트 실행이 실패하면 `CODE_SIGN_ENTITLEMENTS[sdk=macosx*]`를 비우고 스펙 12절 위험 항목에 따라 VALIDATION.md에 기록한다.

Run: `open MellowPhoto.xcodeproj` 없이 `xcodebuild ... -destination 'platform=macOS' build` 결과물 `open "$(xcodebuild -project MellowPhoto.xcodeproj -scheme MellowPhoto -showBuildSettings -destination 'platform=macOS' | awk '/ BUILT_PRODUCTS_DIR/ {print $3}')/Mellow Photo.app"`
Expected: 창에 "Mellow Photo · 3개 프리셋"이 뜬다.

- [ ] **Step 5: 커밋**

```bash
git add apple/project.yml apple/Config apple/MellowPhoto apple/MellowPhotoTests apple/MellowPhoto.xcodeproj .gitignore
git commit -m "build(app): iPhone·iPad·Mac 단일 앱 타깃을 XcodeGen으로 정의

project.yml을 진실의 원천으로 두고 생성된 프로젝트를 함께 커밋해
Xcode 없이도 CI가 동일한 프로젝트로 세 플랫폼을 빌드하게 한다.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 9: Application 계층 — AppModel·RenderScheduler·유스케이스 2개

**Files:**
- Create: `apple/MellowPhoto/Application/Ports.swift` (PhotoImporter, StagedPhoto)
- Create: `apple/MellowPhoto/Application/UserMessage.swift` (MellowError → 한국어 문구)
- Create: `apple/MellowPhoto/Application/RenderScheduler.swift`
- Create: `apple/MellowPhoto/Application/ImportPhotos.swift`
- Create: `apple/MellowPhoto/Application/ExportPhotos.swift`
- Create: `apple/MellowPhoto/Application/EditorTool.swift`
- Create: `apple/MellowPhoto/Application/AppModel.swift`
- Create: `apple/MellowPhoto/Application/AppModel+Editing.swift`
- Create: `apple/MellowPhoto/Application/AppModel+Library.swift`
- Create: `apple/MellowPhoto/Application/AppModel+Export.swift`
- Test: `apple/MellowPhotoTests/TestSupport.swift`
- Test: `apple/MellowPhotoTests/RenderSchedulerTests.swift`
- Test: `apple/MellowPhotoTests/ImportPhotosTests.swift`
- Test: `apple/MellowPhotoTests/ExportPhotosTests.swift`
- Test: `apple/MellowPhotoTests/AppModelTests.swift`
- Delete: `apple/MellowPhotoTests/SmokeTests.swift`

**Interfaces:**
- Consumes: `ProjectSession`, `WorkingCopyStore`, `JSONSessionStore`, `LibraryPolicy` (Task 4), `PhotoPipeline`, `PreparedPhoto`, `RenderTuning`, `VisionFaceAnalyzer` (Task 5·6), `Exporter`, `ExportOptions`, `ExportDestination`, `FileNamingPolicy` (Task 7), `EditDocument`, `EditChange` (Task 2).
- Produces: `PhotoImporter`, `StagedPhoto(url:displayName:)`, `UserMessage.text(for:)`, `RenderScheduler`, `ImportPhotos.run(staged:onProgress:) -> ImportReport`, `ExportPhotos.run(entries:options:destination:onProgress:) -> ExportReport`, `EditorTool`, `AppModel`과 그 상태·메서드(아래 코드). Task 10·11이 쓴다.

- [ ] **Step 1: 테스트 지원 코드 작성**

`apple/MellowPhotoTests/TestSupport.swift`:

```swift
import CoreImage
import Foundation
import ImageIO
import MellowExport
import MellowLibrary
import MellowRendering
import MellowShared
import PhotosUI
import XCTest
@testable import Mellow_Photo

final class MemorySessionStore: SessionStore, @unchecked Sendable {
    var saved: SessionSnapshot?
    func load() throws -> SessionSnapshot? { saved }
    func save(_ snapshot: SessionSnapshot) throws { saved = snapshot }
}

struct StubFaceAnalyzer: FaceAnalyzer {
    var result: Result<[FaceGeometry], MellowError> = .success([])
    func analyze(_ image: CIImage) throws -> [FaceGeometry] { try result.get() }
}

struct FakeImporter: PhotoImporter {
    var staged: [Result<StagedPhoto, Error>] = []
    func stage(_ items: [PhotosPickerItem]) async -> [Result<StagedPhoto, Error>] { staged }
    func stage(fileURLs: [URL]) async -> [Result<StagedPhoto, Error>] { staged }
}

final class RecordingDestination: ExportDestination, @unchecked Sendable {
    var published: [(name: String, bytes: Int)] = []
    var failOnNames: Set<String> = []
    var delayNanoseconds: UInt64 = 0

    func publish(fileURL: URL, suggestedName: String) async throws {
        if delayNanoseconds > 0 { try await Task.sleep(nanoseconds: delayNanoseconds) }
        if failOnNames.contains(suggestedName) { throw MellowError.exportFailed(reason: "test") }
        published.append((suggestedName, try Data(contentsOf: fileURL).count))
    }
}

enum TestSupport {
    static func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// 단색 PNG를 임시 폴더에 쓴다. 가져오기 테스트의 "선택된 사진" 역할.
    static func solidPNG(in directory: URL, name: String = UUID().uuidString, size: Int = 128) throws -> URL {
        let url = directory.appendingPathComponent("\(name).png")
        let image = CIImage(color: CIColor(red: 0.5, green: 0.4, blue: 0.3)).cropped(to: CGRect(x: 0, y: 0, width: size, height: size))
        let cg = try Renderer().makeCGImage(image)
        let destination = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil)!
        CGImageDestinationAddImage(destination, cg, nil)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        return url
    }

    @MainActor
    static func makeModel(root: URL, maxPhotos: Int = 40, analyzer: StubFaceAnalyzer = StubFaceAnalyzer(), importer: FakeImporter = FakeImporter(), store: MemorySessionStore = MemorySessionStore()) -> AppModel {
        let copies = WorkingCopyStore(directory: root.appendingPathComponent("Library"))
        try? copies.prepareDirectory()
        return AppModel(
            session: ProjectSession(store: store, maxPhotos: maxPhotos),
            pipeline: PhotoPipeline(analyzer: analyzer, tuning: RenderTuning()),
            copies: copies,
            importer: importer,
            exporter: Exporter(renderer: Renderer()),
            renderDebounce: .milliseconds(10))
    }
}
```

- [ ] **Step 2: 실패하는 테스트 작성**

`apple/MellowPhotoTests/RenderSchedulerTests.swift`:

```swift
import CoreImage
import MellowRendering
import XCTest
@testable import Mellow_Photo

@MainActor
final class RenderSchedulerTests: XCTestCase {
    func testOnlyLatestRequestCompletes() async throws {
        let scheduler = RenderScheduler(debounce: .milliseconds(20))
        let renderer = Renderer()
        var completed: [Int] = []
        for index in 1...3 {
            scheduler.schedule {
                try renderer.makeCGImage(CIImage(color: .red).cropped(to: CGRect(x: 0, y: 0, width: index, height: 1)))
            } completion: { result in
                if case .success(let image) = result { completed.append(image.width) }
            }
        }
        try await Task.sleep(for: .milliseconds(300))
        XCTAssertEqual(completed, [3])
    }

    func testCancelDropsPendingWork() async throws {
        let scheduler = RenderScheduler(debounce: .milliseconds(20))
        var calls = 0
        scheduler.schedule { throw MellowError.renderFailed } completion: { _ in calls += 1 }
        scheduler.cancel()
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertEqual(calls, 0)
    }
}
```

`apple/MellowPhotoTests/ImportPhotosTests.swift`:

```swift
import MellowLibrary
import MellowRendering
import MellowShared
import XCTest
@testable import Mellow_Photo

@MainActor
final class ImportPhotosTests: XCTestCase {
    private var root: URL!
    private var copies: WorkingCopyStore!
    private var session: ProjectSession!
    private var pipeline: PhotoPipeline!

    override func setUpWithError() throws {
        root = try TestSupport.temporaryDirectory()
        copies = WorkingCopyStore(directory: root.appendingPathComponent("Library"))
        try copies.prepareDirectory()
        session = ProjectSession(store: MemorySessionStore(), maxPhotos: 2)
        pipeline = PhotoPipeline(analyzer: StubFaceAnalyzer(), tuning: RenderTuning())
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    private func useCase() -> ImportPhotos {
        ImportPhotos(session: session, pipeline: pipeline, copies: copies)
    }

    func testImportMovesCopyPreparesAndAddsToSession() async throws {
        let staged = try TestSupport.solidPNG(in: root, name: "IMG_1")
        let report = await useCase().run(staged: [.success(StagedPhoto(url: staged, displayName: "IMG_1"))]) { _, _ in }
        XCTAssertEqual(report.added.count, 1)
        XCTAssertTrue(report.failures.isEmpty)
        XCTAssertEqual(session.photos.count, 1)
        XCTAssertEqual(session.photos[0].displayName, "IMG_1")
        XCTAssertFalse(FileManager.default.fileExists(atPath: staged.path), "임시 파일은 사본으로 이동된다")
        XCTAssertTrue(FileManager.default.fileExists(atPath: copies.url(for: session.photos[0].filename).path))
        XCTAssertEqual(report.added[0].prepared.pixelSize, CGSize(width: 128, height: 128))
    }

    func testImportStopsAtCapacityAndReportsSkipped() async throws {
        let files = try (1...3).map { try TestSupport.solidPNG(in: root, name: "IMG_\($0)") }
        let staged = files.map { Result<StagedPhoto, Error>.success(StagedPhoto(url: $0, displayName: nil)) }
        let report = await useCase().run(staged: staged) { _, _ in }
        XCTAssertEqual(report.added.count, 2)
        XCTAssertEqual(report.skippedForCapacity, 1)
        XCTAssertEqual(session.photos.map(\.displayName), ["사진 1", "사진 2"])
        XCTAssertFalse(FileManager.default.fileExists(atPath: files[2].path), "건너뛴 임시 파일도 정리한다")
    }

    func testBrokenFileIsReportedAndCopyIsRemoved() async throws {
        let broken = root.appendingPathComponent("broken.png")
        try Data([0, 1, 2]).write(to: broken)
        let report = await useCase().run(staged: [.success(StagedPhoto(url: broken, displayName: nil))]) { _, _ in }
        XCTAssertEqual(report.failures.count, 1)
        XCTAssertEqual(report.failures[0].stage, .prepare)
        XCTAssertTrue(session.photos.isEmpty)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: copies.directory.path), [], "실패한 사본은 남지 않는다")
    }

    func testStagingFailureIsReportedWithStage() async throws {
        let report = await useCase().run(staged: [.failure(MellowError.cannotOpenPhoto(filename: "x"))]) { _, _ in }
        XCTAssertEqual(report.failures.first?.stage, .stage)
    }

    func testFaceAnalysisFailureBecomesWarningNotFailure() async throws {
        pipeline = PhotoPipeline(analyzer: StubFaceAnalyzer(result: .failure(.faceAnalysisUnavailable(reason: "test"))), tuning: RenderTuning())
        let staged = try TestSupport.solidPNG(in: root)
        let report = await useCase().run(staged: [.success(StagedPhoto(url: staged, displayName: nil))]) { _, _ in }
        XCTAssertEqual(report.added.count, 1)
        XCTAssertEqual(report.warnings.count, 1)
    }
}
```

`apple/MellowPhotoTests/ExportPhotosTests.swift`:

```swift
import MellowEditing
import MellowExport
import MellowLibrary
import MellowRendering
import MellowShared
import XCTest
@testable import Mellow_Photo

@MainActor
final class ExportPhotosTests: XCTestCase {
    private var root: URL!
    private var copies: WorkingCopyStore!
    private var pipeline: PhotoPipeline!

    override func setUpWithError() throws {
        root = try TestSupport.temporaryDirectory()
        copies = WorkingCopyStore(directory: root.appendingPathComponent("Library"))
        try copies.prepareDirectory()
        pipeline = PhotoPipeline(analyzer: StubFaceAnalyzer(), tuning: RenderTuning())
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    private func entry(named name: String, recipe: EditRecipe = EditRecipe()) async throws -> PhotoEntry {
        let id = PhotoID()
        let filename = try copies.adopt(temporaryFile: try TestSupport.solidPNG(in: root, name: name), as: id)
        _ = try await pipeline.prepare(id, at: copies.url(for: filename))
        return PhotoEntry(id: id, filename: filename, displayName: name, document: EditDocument(recipe: recipe))
    }

    private func useCase() -> ExportPhotos {
        ExportPhotos(pipeline: pipeline, copies: copies, exporter: Exporter(renderer: Renderer()))
    }

    private func temporaryExports() throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: FileManager.default.temporaryDirectory.path).filter { $0.hasPrefix("mellow-export-") }
    }

    func testExportPublishesEachPhotoAndReportsFailures() async throws {
        let a = try await entry(named: "A")
        let b = try await entry(named: "B")
        let destination = RecordingDestination()
        destination.failOnNames = ["B_mellow"]
        var progress: [Double] = []
        let report = await useCase().run(entries: [a, b], options: ExportOptions(format: .jpeg), destination: destination) { progress.append($0) }
        XCTAssertEqual(report.saved, 1)
        XCTAssertEqual(report.failures.count, 1)
        XCTAssertEqual(destination.published.map(\.name), ["A_mellow"])
        XCTAssertGreaterThan(destination.published[0].bytes, 0)
        XCTAssertEqual(progress, [0.5, 1.0])
        XCTAssertEqual(try temporaryExports(), [])
    }

    func testCancelledExportCleansTemporaryFilesAndCanRunAgain() async throws {
        let entries = try await [entry(named: "A"), entry(named: "B"), entry(named: "C")]
        let destination = RecordingDestination()
        destination.delayNanoseconds = 150_000_000
        let useCase = useCase()
        let task = Task { await useCase.run(entries: entries, options: ExportOptions(), destination: destination) { _ in } }
        try await Task.sleep(nanoseconds: 50_000_000)
        task.cancel()
        let report = await task.value
        XCTAssertTrue(report.cancelled)
        XCTAssertLessThan(report.saved, 3)
        XCTAssertEqual(try temporaryExports(), [])
        destination.delayNanoseconds = 0
        let second = await useCase.run(entries: entries, options: ExportOptions(), destination: destination) { _ in }
        XCTAssertEqual(second.saved, 3)
        XCTAssertFalse(second.cancelled)
    }

    func testFaceEditsWithFailedAnalysisAreRefused() async throws {
        pipeline = PhotoPipeline(analyzer: StubFaceAnalyzer(result: .failure(.faceAnalysisUnavailable(reason: "test"))), tuning: RenderTuning())
        var recipe = EditRecipe()
        recipe.portrait.skinSmoothing = 0.3
        let photo = try await entry(named: "A", recipe: recipe)
        let destination = RecordingDestination()
        let report = await useCase().run(entries: [photo], options: ExportOptions(), destination: destination) { _ in }
        XCTAssertEqual(report.saved, 0)
        XCTAssertEqual(report.failures.first?.error, .faceAnalysisUnavailable(reason: "test"))
        XCTAssertTrue(destination.published.isEmpty)
    }
}
```

`apple/MellowPhotoTests/AppModelTests.swift`:

```swift
import MellowEditing
import MellowLibrary
import MellowShared
import XCTest
@testable import Mellow_Photo

@MainActor
final class AppModelTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = try TestSupport.temporaryDirectory()
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    private func waitUntil(_ condition: @escaping () -> Bool, timeout: TimeInterval = 5) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() && Date() < deadline {
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        XCTAssertTrue(condition())
    }

    func testImportSelectsFirstPhotoAndRendersPreview() async throws {
        let staged = try TestSupport.solidPNG(in: root, name: "IMG_1")
        let model = TestSupport.makeModel(root: root, importer: FakeImporter(staged: [.success(StagedPhoto(url: staged, displayName: "IMG_1"))]))
        await model.importFromFiles([staged])
        XCTAssertEqual(model.session.photos.count, 1)
        XCTAssertNotNil(model.thumbnails[model.session.photos[0].id])
        try await waitUntil { model.isReady && model.preview != nil }
        XCTAssertEqual(model.statusMessage, "1장 · 편집 기록은 이 기기에 저장됩니다.")
    }

    func testSliderEditUpdatesRecipeAndRerenders() async throws {
        let staged = try TestSupport.solidPNG(in: root)
        let model = TestSupport.makeModel(root: root, importer: FakeImporter(staged: [.success(StagedPhoto(url: staged, displayName: nil))]))
        await model.importFromFiles([staged])
        try await waitUntil { model.isReady && model.preview != nil }
        model.beginSliderEdit()
        model.edit(.exposure(0.5))
        model.edit(.exposure(0.6))
        model.endSliderEdit()
        XCTAssertEqual(model.currentRecipe.color.exposure, 0.6)
        XCTAssertEqual(model.session.selected?.document.undoStack.count, 1)
        XCTAssertTrue(model.canUndo)
        model.undo()
        XCTAssertEqual(model.currentRecipe.color.exposure, 0)
    }

    func testGeometryLockShowsStatusInsteadOfChanging() async throws {
        let staged = try TestSupport.solidPNG(in: root)
        let model = TestSupport.makeModel(root: root, importer: FakeImporter(staged: [.success(StagedPhoto(url: staged, displayName: nil))]))
        await model.importFromFiles([staged])
        try await waitUntil { model.isReady && model.preview != nil }
        model.edit(.faceSlim(0.2))
        try await waitUntil { !model.isRendering }
        model.tool = .retouch
        model.touch(from: NormalizedPoint(x: 0.3, y: 0.3), to: NormalizedPoint(x: 0.3, y: 0.3))
        XCTAssertFalse(model.isChoosingCloneSource)
        model.touch(from: NormalizedPoint(x: 0.5, y: 0.5), to: NormalizedPoint(x: 0.5, y: 0.5))
        XCTAssertEqual(model.currentRecipe.operations.count, 1)
        try await waitUntil { !model.isRendering }
        model.edit(.faceSlim(0.9))
        XCTAssertEqual(model.currentRecipe.portrait.faceSlim, 0.2)
        XCTAssertEqual(model.statusMessage, UserMessage.geometryLocked)
    }

    func testRemoveSelectedDeletesWorkingCopyAndSelectsNext() async throws {
        let first = try TestSupport.solidPNG(in: root, name: "A")
        let second = try TestSupport.solidPNG(in: root, name: "B")
        let importer = FakeImporter(staged: [.success(StagedPhoto(url: first, displayName: "A")), .success(StagedPhoto(url: second, displayName: "B"))])
        let model = TestSupport.makeModel(root: root, importer: importer)
        await model.importFromFiles([first, second])
        let removed = try XCTUnwrap(model.session.photos.first)
        model.removeSelectedPhoto()
        XCTAssertEqual(model.session.photos.map(\.displayName), ["B"])
        XCTAssertEqual(model.session.selectedPhotoID, model.session.photos[0].id)
        XCTAssertFalse(FileManager.default.fileExists(atPath: model.copies.url(for: removed.filename).path))
        XCTAssertNil(model.thumbnails[removed.id])
    }

    func testRestoreRebuildsThumbnailsFromSession() async throws {
        let store = MemorySessionStore()
        let copies = WorkingCopyStore(directory: root.appendingPathComponent("Library"))
        try copies.prepareDirectory()
        let id = PhotoID()
        let filename = try copies.adopt(temporaryFile: try TestSupport.solidPNG(in: root), as: id)
        store.saved = SessionSnapshot(photos: [PhotoEntry(id: id, filename: filename, displayName: "복원")], selectedPhotoID: id, presets: [])
        let model = TestSupport.makeModel(root: root, store: store)
        await model.restore()
        XCTAssertNotNil(model.thumbnails[id])
        try await waitUntil { model.isReady }
        XCTAssertEqual(model.session.selectedPhotoID, id)
    }

    func testRestoreWithUnreadableSessionKeepsAppUsable() async throws {
        let store = JSONSessionStore(fileURL: root.appendingPathComponent("session.json"))
        try Data("{ broken".utf8).write(to: store.fileURL)
        let copies = WorkingCopyStore(directory: root.appendingPathComponent("Library"))
        try copies.prepareDirectory()
        let model = AppModel(
            session: ProjectSession(store: store, maxPhotos: 40),
            pipeline: PhotoPipeline(analyzer: StubFaceAnalyzer(), tuning: RenderTuning()),
            copies: copies, importer: FakeImporter(), exporter: Exporter(renderer: Renderer()), renderDebounce: .milliseconds(10))
        await model.restore()
        XCTAssertNotNil(model.presentedError)
        XCTAssertNotNil(store.recoveryFileURL)
        XCTAssertFalse(model.isBusy)
    }
}
```

- [ ] **Step 3: 실패 확인**

Run: `cd apple && xcodegen generate && xcodebuild -project MellowPhoto.xcodeproj -scheme MellowPhoto -destination 'platform=macOS' build-for-testing 2>&1 | grep -E "error:" | head`
Expected: `AppModel`, `ImportPhotos` 등 미정의 오류.

- [ ] **Step 4: 구현**

`apple/MellowPhoto/Application/Ports.swift`:

```swift
import Foundation
import PhotosUI

/// 사용자가 고른 사진을 앱 임시 폴더로 옮긴 결과.
struct StagedPhoto: Sendable {
    let url: URL
    /// 원본 파일 이름 줄기. 사진 앱에서 고르면 알 수 없어 nil.
    let displayName: String?
}

/// 플랫폼별 가져오기 구현. 선택 항목을 임시 파일로 바꾸는 일만 한다.
protocol PhotoImporter: Sendable {
    func stage(_ items: [PhotosPickerItem]) async -> [Result<StagedPhoto, Error>]
    func stage(fileURLs: [URL]) async -> [Result<StagedPhoto, Error>]
}
```

`apple/MellowPhoto/Application/UserMessage.swift`:

```swift
import Foundation
import MellowShared

/// 모든 한국어 사용자 문구. 모듈은 문구를 모른다.
enum UserMessage {
    static let welcomeStatus = "사진을 골라 시작해보세요."
    static let geometryLocked = "수동 보정 위치를 유지하려고 얼굴 조정을 잠갔어요. 실행 취소 또는 초기화하면 다시 조정할 수 있어요."
    static let chooseCloneSource = "① 깨끗한 피부를 톡 눌러 샘플을 골라주세요."
    static let chooseCloneTarget = "② 지우고 싶은 작은 잡티를 톡 눌러주세요."
    static let appliedToAll = "전체 사진에 슬라이더 설정을 적용했어요."
    static let sessionUnreadable = "작업 기록을 읽지 못해 복구용 사본을 보관했습니다. 기존 작업 사진도 보존됩니다. 사진을 다시 골라 편집할 수 있어요."

    static func photosStatus(count: Int) -> String {
        "\(count)장 · 편집 기록은 이 기기에 저장됩니다."
    }

    static func importing(_ index: Int, of total: Int) -> String {
        "사진 가져오는 중 \(index) / \(total)"
    }

    static func exporting(_ index: Int, of total: Int) -> String {
        "저장 중 \(index) / \(total)"
    }

    static func exported(saved: Int, cancelled: Bool) -> String {
        "\(saved)장 저장 완료" + (cancelled ? " · 나머지 취소" : "") + " · 원본은 그대로예요."
    }

    static func text(for error: Error) -> String {
        guard let error = error as? MellowError else { return error.localizedDescription }
        switch error {
        case .cannotOpenPhoto(let filename): return "사진 파일을 열 수 없습니다: \(filename)"
        case .unsupportedOrCorruptPhoto: return "지원하지 않거나 손상된 사진입니다."
        case .cannotCreatePreview: return "사진 미리보기를 만들 수 없습니다."
        case .invalidImageSize: return "사진 크기가 올바르지 않습니다."
        case .invalidRecipeValues: return "보정 수치가 올바르지 않습니다."
        case .warpUnavailable: return "얼굴·체형 보정 기능을 초기화하지 못했습니다."
        case .renderFailed: return "사진을 렌더링할 수 없습니다."
        case .cannotWriteToFolder: return "저장할 폴더를 열 수 없습니다."
        case .exportVerificationFailed: return "저장된 사진을 검증하지 못했습니다."
        case .fileAlreadyExists: return "같은 이름의 파일이 이미 있습니다. 다른 이름을 선택하세요."
        case .exportFailed(let reason): return "사진을 저장하지 못했습니다: \(reason)"
        case .faceAnalysisUnavailable(let reason): return "얼굴 분석을 사용할 수 없습니다. 색감·수동 보정은 사용할 수 있어요. (\(reason))"
        case .sessionUnreadable: return sessionUnreadable
        case .sessionWriteFailed(let reason): return "편집 기록 저장 실패: \(reason)"
        case .photoLibraryAccessDenied: return "사진 저장 권한이 꺼져 있습니다. 설정 → 앱 → Mellow Photo → 사진에서 사진 추가를 허용해 주세요."
        }
    }
}
```

`apple/MellowPhoto/Application/RenderScheduler.swift`:

```swift
import CoreGraphics
import Foundation

/// 디바운스와 세대 토큰으로 마지막 요청만 완료시킨다.
@MainActor
final class RenderScheduler {
    private let debounce: Duration
    private var task: Task<Void, Never>?
    private var generation = 0

    init(debounce: Duration) {
        self.debounce = debounce
    }

    func schedule(_ render: @escaping @Sendable () async throws -> CGImage, completion: @escaping @MainActor (Result<CGImage, Error>) -> Void) {
        task?.cancel()
        generation += 1
        let ticket = generation
        task = Task {
            do {
                try await Task.sleep(for: debounce)
            } catch {
                return
            }
            let result: Result<CGImage, Error>
            do {
                result = .success(try await render())
            } catch {
                result = .failure(error)
            }
            guard !Task.isCancelled, ticket == generation else { return }
            completion(result)
        }
    }

    func cancel() {
        task?.cancel()
        generation += 1
    }
}
```

`apple/MellowPhoto/Application/ImportPhotos.swift`:

```swift
import Foundation
import MellowEditing
import MellowLibrary
import MellowRendering
import MellowShared

struct ImportedPhoto {
    let id: PhotoID
    let prepared: PreparedPhoto
}

struct ImportFailure: Equatable {
    enum Stage: Equatable {
        case stage
        case copy
        case prepare
        case save
    }

    let ordinal: Int
    let stage: Stage
    let message: String
}

struct ImportReport {
    var added: [ImportedPhoto] = []
    var failures: [ImportFailure] = []
    var warnings: [String] = []
    var skippedForCapacity = 0
}

/// 사본 저장 → 분석 → 세션 추가. 어디서 실패하든 사본을 지운다.
@MainActor
struct ImportPhotos {
    let session: ProjectSession
    let pipeline: PhotoPipeline
    let copies: WorkingCopyStore

    func run(staged: [Result<StagedPhoto, Error>], onProgress: @MainActor (Int, Int) -> Void) async -> ImportReport {
        var report = ImportReport()
        for (offset, item) in staged.enumerated() {
            let ordinal = offset + 1
            onProgress(ordinal, staged.count)
            guard session.remainingCapacity > 0 else {
                report.skippedForCapacity += 1
                if case .success(let photo) = item { try? FileManager.default.removeItem(at: photo.url) }
                continue
            }
            switch item {
            case .failure(let error):
                report.failures.append(ImportFailure(ordinal: ordinal, stage: .stage, message: UserMessage.text(for: error)))
            case .success(let photo):
                await importOne(photo, ordinal: ordinal, into: &report)
            }
        }
        return report
    }

    private func importOne(_ photo: StagedPhoto, ordinal: Int, into report: inout ImportReport) async {
        let id = PhotoID()
        var filename: String?
        do {
            filename = try copies.adopt(temporaryFile: photo.url, as: id)
        } catch {
            try? FileManager.default.removeItem(at: photo.url)
            report.failures.append(ImportFailure(ordinal: ordinal, stage: .copy, message: UserMessage.text(for: error)))
            return
        }
        guard let filename else { return }
        let prepared: PreparedPhoto
        do {
            prepared = try await pipeline.prepare(id, at: copies.url(for: filename))
        } catch {
            await pipeline.evict(id)
            try? copies.remove(filename: filename)
            report.failures.append(ImportFailure(ordinal: ordinal, stage: .prepare, message: UserMessage.text(for: error)))
            return
        }
        let displayName = photo.displayName ?? "사진 \(session.photos.count + 1)"
        do {
            try session.add(PhotoEntry(id: id, filename: filename, displayName: displayName))
        } catch {
            await pipeline.evict(id)
            try? copies.remove(filename: filename)
            report.failures.append(ImportFailure(ordinal: ordinal, stage: .save, message: UserMessage.text(for: error)))
            return
        }
        if let failure = prepared.faceAnalysisFailure {
            report.warnings.append("사진 \(ordinal): \(UserMessage.text(for: failure))")
        }
        report.added.append(ImportedPhoto(id: id, prepared: prepared))
    }
}
```

`apple/MellowPhoto/Application/ExportPhotos.swift`:

```swift
import Foundation
import MellowExport
import MellowLibrary
import MellowRendering
import MellowShared

struct ExportFailure: Equatable {
    let displayName: String
    let error: MellowError?
    let message: String
}

struct ExportReport: Equatable {
    var saved = 0
    var failures: [ExportFailure] = []
    var cancelled = false
}

/// 렌더 → 임시 파일 → 대상 공개 → 임시 파일 정리. 취소는 Task 취소로 받는다.
struct ExportPhotos: Sendable {
    let pipeline: PhotoPipeline
    let copies: WorkingCopyStore
    let exporter: Exporter

    func run(entries: [PhotoEntry], options: ExportOptions, destination: any ExportDestination, onProgress: @MainActor @Sendable (Double) -> Void) async -> ExportReport {
        var report = ExportReport()
        for (index, entry) in entries.enumerated() {
            if Task.isCancelled {
                report.cancelled = true
                break
            }
            let temporary = FileManager.default.temporaryDirectory.appendingPathComponent("mellow-export-\(UUID().uuidString).\(options.format.fileExtension)")
            defer { try? FileManager.default.removeItem(at: temporary) }
            do {
                let image = try await pipeline.renderOriginal(entry.id, at: copies.url(for: entry.filename), recipe: entry.document.recipe, maxDimension: options.maxDimension)
                try exporter.write(image, to: temporary, format: options.format, quality: options.quality)
                try Task.checkCancellation()
                try await destination.publish(fileURL: temporary, suggestedName: entry.displayName + FileNamingPolicy.suffix)
                report.saved += 1
            } catch is CancellationError {
                report.cancelled = true
                break
            } catch {
                report.failures.append(ExportFailure(displayName: entry.displayName, error: error as? MellowError, message: UserMessage.text(for: error)))
            }
            await onProgress(Double(index + 1) / Double(entries.count))
        }
        return report
    }
}
```

`apple/MellowPhoto/Application/EditorTool.swift`:

```swift
enum EditorTool: String, CaseIterable, Identifiable {
    case color = "색감"
    case portrait = "인물"
    case retouch = "잡티"
    case warp = "변형"

    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .color: return "slider.horizontal.3"
        case .portrait: return "face.smiling"
        case .retouch: return "bandage"
        case .warp: return "arrow.up.left.and.arrow.down.right"
        }
    }

    var usesCanvasTouch: Bool { self == .retouch || self == .warp }
}
```

`apple/MellowPhoto/Application/AppModel.swift`:

```swift
import CoreGraphics
import Foundation
import MellowEditing
import MellowExport
import MellowLibrary
import MellowRendering
import MellowShared
import Observation

struct PresentedError: Identifiable, Equatable {
    let id = UUID()
    let message: String
}

/// composition root. 세션·파이프라인·어댑터를 묶고 화면이 읽는 상태를 가진다.
@MainActor
@Observable
final class AppModel {
    struct PhotoInfo {
        var pixelSize: CGSize
        var faces: [FaceGeometry]
        var faceAnalysisFailure: MellowError?
    }

    enum Policy {
        static let brushRadiusRange = 0.008...0.07
        static let defaultBrushRadius = 0.025
        static let warpRadiusMultiplier = 3.0
        static let warpMaxDelta = 0.08
        static let warpMinimumDelta = 0.001
    }

    let session: ProjectSession
    let pipeline: PhotoPipeline
    let copies: WorkingCopyStore
    let importer: any PhotoImporter
    let exporter: Exporter

    var thumbnails: [PhotoID: CGImage] = [:]
    var photoInfo: [PhotoID: PhotoInfo] = [:]
    var preview: CGImage?
    var original: CGImage?
    var isReady = false
    var isRendering = false
    var isImporting = false
    var isExporting = false
    var isRestoring = false
    var exportProgress = 0.0
    var statusMessage = UserMessage.welcomeStatus
    var presentedError: PresentedError?
    var selectionFailure: String?

    var tool: EditorTool = .color
    var brushRadius = Policy.defaultBrushRadius
    var cloneSource: NormalizedPoint?
    var isChoosingCloneSource = true
    var isComparing = false
    var exportOptions = ExportOptions()

    let renderScheduler: RenderScheduler
    private var selectionTask: Task<Void, Never>?
    var exportTask: Task<Void, Never>?

    init(session: ProjectSession, pipeline: PhotoPipeline, copies: WorkingCopyStore, importer: any PhotoImporter, exporter: Exporter, renderDebounce: Duration = .milliseconds(100)) {
        self.session = session
        self.pipeline = pipeline
        self.copies = copies
        self.importer = importer
        self.exporter = exporter
        renderScheduler = RenderScheduler(debounce: renderDebounce)
    }

    var isBusy: Bool { isImporting || isExporting || isRestoring }
    var currentRecipe: EditRecipe { session.selected?.document.recipe ?? EditRecipe() }
    var canUndo: Bool { session.selected?.document.canUndo ?? false }
    var canRedo: Bool { session.selected?.document.canRedo ?? false }
    var isGeometryLocked: Bool { session.selected?.document.isGeometryLocked ?? false }
    var displayImage: CGImage? { isComparing ? original : (preview ?? original) }
    var selectedInfo: PhotoInfo? { session.selectedPhotoID.flatMap { photoInfo[$0] } }
    var faces: [FaceGeometry] { selectedInfo?.faces ?? [] }

    func present(_ error: Error) {
        presentedError = PresentedError(message: UserMessage.text(for: error))
    }

    func present(message: String) {
        presentedError = PresentedError(message: message)
    }

    /// 앱 시작. 세션을 읽고 모든 사진의 썸네일·얼굴을 다시 준비한다.
    func restore() async {
        isRestoring = true
        defer { isRestoring = false }
        do {
            try session.restore()
        } catch {
            present(error)
        }
        for entry in session.photos {
            do {
                let prepared = try await pipeline.prepare(entry.id, at: copies.url(for: entry.filename))
                remember(entry.id, prepared)
            } catch {
                present(message: "일부 작업 사진을 열지 못했습니다. 해당 사진을 다시 가져오세요.")
            }
        }
        if !session.photos.isEmpty {
            statusMessage = UserMessage.photosStatus(count: session.photos.count)
        }
        if let id = session.selectedPhotoID {
            select(id)
        }
    }

    func remember(_ id: PhotoID, _ prepared: PreparedPhoto) {
        thumbnails[id] = prepared.thumbnail
        photoInfo[id] = PhotoInfo(pixelSize: prepared.pixelSize, faces: prepared.faces, faceAnalysisFailure: prepared.faceAnalysisFailure)
    }

    func select(_ id: PhotoID) {
        guard !isExporting, session.index(of: id) != nil else { return }
        selectionTask?.cancel()
        renderScheduler.cancel()
        session.selectedPhotoID = id
        preview = nil
        original = nil
        isReady = false
        isRendering = false
        selectionFailure = nil
        isComparing = false
        cloneSource = nil
        isChoosingCloneSource = true
        guard let entry = session.selected else { return }
        selectionTask = Task {
            do {
                try await pipeline.reprepareIfEvicted(id, at: copies.url(for: entry.filename))
                let base = try await pipeline.preview(id, recipe: EditRecipe())
                guard !Task.isCancelled, session.selectedPhotoID == id else { return }
                original = base
                isReady = true
                scheduleRender()
            } catch {
                guard !Task.isCancelled, session.selectedPhotoID == id else { return }
                selectionFailure = "이 작업 사진을 열 수 없습니다. 다시 시도하거나 편집에서 뺀 뒤 사진을 다시 골라주세요."
                present(error)
            }
        }
    }

    func scheduleRender() {
        guard let entry = session.selected, isReady else { return }
        isRendering = true
        let pipeline = self.pipeline
        let recipe = entry.document.recipe
        let id = entry.id
        renderScheduler.schedule {
            try await pipeline.preview(id, recipe: recipe)
        } completion: { [weak self] result in
            guard let self, session.selectedPhotoID == id else { return }
            isRendering = false
            switch result {
            case .success(let image): preview = image
            case .failure(let error): present(error)
            }
        }
    }

    func cancelSelectionWork() {
        selectionTask?.cancel()
        renderScheduler.cancel()
    }

    func stopWork() {
        cancelSelectionWork()
        exportTask?.cancel()
    }
}
```

`apple/MellowPhoto/Application/AppModel+Editing.swift`:

```swift
import MellowEditing
import MellowShared

extension AppModel {
    private func mutateSelected(_ body: (inout EditDocument) -> EditDocument.Rejection?) {
        guard let id = session.selectedPhotoID, isReady, !isBusy else { return }
        if session.edit(id, body) == .geometryLocked {
            statusMessage = UserMessage.geometryLocked
            return
        }
        if let error = session.lastPersistenceError {
            present(error)
        }
        scheduleRender()
    }

    func beginSliderEdit() {
        guard let id = session.selectedPhotoID else { return }
        session.edit(id) { document in
            document.beginContinuousChange()
            return nil
        }
    }

    func endSliderEdit() {
        guard let id = session.selectedPhotoID else { return }
        session.edit(id) { document in
            document.endContinuousChange()
            return nil
        }
    }

    func edit(_ change: EditChange) {
        mutateSelected { $0.set(change) }
    }

    func applyPreset(_ values: PresetValues) {
        mutateSelected { document in
            document.apply(values)
            return nil
        }
    }

    func applyToAll() {
        guard let id = session.selectedPhotoID, !isBusy else { return }
        session.applyToAll(from: id)
        statusMessage = UserMessage.appliedToAll
    }

    func undo() {
        mutateSelected { document in
            document.undo()
            return nil
        }
    }

    func redo() {
        mutateSelected { document in
            document.redo()
            return nil
        }
    }

    func reset() {
        cloneSource = nil
        isChoosingCloneSource = true
        mutateSelected { document in
            document.reset()
            return nil
        }
    }

    func savePreset(named name: String) {
        session.addPreset(named: name, values: PresetValues(color: currentRecipe.color, portrait: currentRecipe.portrait))
    }

    func resetCloneSource() {
        cloneSource = nil
        isChoosingCloneSource = true
        statusMessage = UserMessage.chooseCloneSource
    }

    /// 캔버스 탭·드래그. 좌표는 정규화, 원점 왼쪽 아래.
    func touch(from: NormalizedPoint, to: NormalizedPoint) {
        guard isReady, !isBusy, !isComparing, !isRendering else { return }
        switch tool {
        case .retouch:
            if isChoosingCloneSource || cloneSource == nil {
                cloneSource = to
                isChoosingCloneSource = false
                statusMessage = UserMessage.chooseCloneTarget
                return
            }
            guard let source = cloneSource else { return }
            let spot = RetouchSpot(x: to.x, y: to.y, sourceX: source.x, sourceY: source.y, radius: brushRadius)
            mutateSelected { document in
                document.appendLocalEdit(.spot(spot))
                return nil
            }
        case .warp:
            let dx = max(-Policy.warpMaxDelta, min(Policy.warpMaxDelta, to.x - from.x))
            let dy = max(-Policy.warpMaxDelta, min(Policy.warpMaxDelta, to.y - from.y))
            guard abs(dx) + abs(dy) > Policy.warpMinimumDelta else { return }
            let stroke = WarpStroke(x: from.x, y: from.y, dx: dx, dy: dy, radius: brushRadius * Policy.warpRadiusMultiplier)
            mutateSelected { document in
                document.appendLocalEdit(.warp(stroke))
                return nil
            }
        case .color, .portrait:
            return
        }
    }
}
```

`apple/MellowPhoto/Application/AppModel+Library.swift`:

```swift
import Foundation
import MellowLibrary
import MellowShared
import PhotosUI

extension AppModel {
    func importFromPicker(_ items: [PhotosPickerItem]) async {
        guard !items.isEmpty else { return }
        await runImport(await importer.stage(items))
    }

    func importFromFiles(_ urls: [URL]) async {
        guard !urls.isEmpty else { return }
        await runImport(await importer.stage(fileURLs: urls))
    }

    private func runImport(_ staged: [Result<StagedPhoto, Error>]) async {
        guard !isBusy else { return }
        isImporting = true
        defer { isImporting = false }
        let hadSelection = session.selectedPhotoID != nil
        let report = await ImportPhotos(session: session, pipeline: pipeline, copies: copies).run(staged: staged) { [weak self] index, total in
            self?.statusMessage = UserMessage.importing(index, of: total)
        }
        for imported in report.added {
            remember(imported.id, imported.prepared)
        }
        statusMessage = UserMessage.photosStatus(count: session.photos.count)
        if !hadSelection, let id = session.selectedPhotoID {
            select(id)
        }
        var lines: [String] = []
        if !report.failures.isEmpty {
            lines.append("\(report.failures.count)장을 가져오지 못했습니다.")
            lines += report.failures.prefix(3).map { "사진 \($0.ordinal): \($0.message)" }
        }
        if report.skippedForCapacity > 0 {
            lines.append("한 번에 편집할 수 있는 사진 수를 넘어 \(report.skippedForCapacity)장은 건너뛰었습니다.")
        }
        if lines.isEmpty {
            lines += report.warnings.prefix(3)
        }
        if !lines.isEmpty {
            present(message: lines.joined(separator: "\n"))
        }
    }

    var canRemoveSelected: Bool { !isBusy && session.selected != nil }

    /// 앱의 작업 사본만 지운다. 사진 앱·사용자 파일 원본은 건드리지 않는다.
    func removeSelectedPhoto() {
        guard canRemoveSelected, let entry = session.selected else { return }
        do {
            try session.remove(entry.id)
        } catch {
            present(message: "사진을 빼지 못했습니다. 작업 사진과 보정 기록은 그대로 유지됩니다: \(UserMessage.text(for: error))")
            return
        }
        cancelSelectionWork()
        thumbnails[entry.id] = nil
        photoInfo[entry.id] = nil
        preview = nil
        original = nil
        isReady = false
        selectionFailure = nil
        Task { await pipeline.evict(entry.id) }
        do {
            try copies.remove(filename: entry.filename)
        } catch {
            present(message: "편집 목록에서 뺐지만 작업 사본을 정리하지 못했습니다: \(error.localizedDescription)")
        }
        if let next = session.selectedPhotoID {
            select(next)
        } else {
            statusMessage = UserMessage.welcomeStatus
        }
    }
}
```

`cancelSelectionWork()`는 `AppModel.swift` 본체에 있다 (`selectionTask`가 `private`이기 때문).

`apple/MellowPhoto/Application/AppModel+Export.swift`:

```swift
import Foundation
import MellowExport
import MellowLibrary

extension AppModel {
    /// 선택한 대상으로 현재 사진 또는 전체를 저장한다. 백그라운드 진입 시 cancelExport()를 부른다.
    func export(all: Bool, to destination: any ExportDestination) {
        guard !isBusy, isReady, let current = session.selected else { return }
        let entries = all ? session.photos : [current]
        let options = exportOptions
        let useCase = ExportPhotos(pipeline: pipeline, copies: copies, exporter: exporter)
        isExporting = true
        exportProgress = 0
        exportTask = Task { [weak self] in
            let report = await useCase.run(entries: entries, options: options, destination: destination) { progress in
                self?.exportProgress = progress
                self?.statusMessage = UserMessage.exporting(Int(progress * Double(entries.count)), of: entries.count)
            }
            guard let self else { return }
            isExporting = false
            statusMessage = UserMessage.exported(saved: report.saved, cancelled: report.cancelled)
            if !report.failures.isEmpty {
                present(message: "\(report.failures.count)장을 저장하지 못했습니다.\n" + report.failures.prefix(3).map { "\($0.displayName): \($0.message)" }.joined(separator: "\n"))
            }
        }
    }

    func cancelExport() {
        exportTask?.cancel()
    }
}
```

- [ ] **Step 5: 통과 확인**

Run:
```bash
cd apple && xcodegen generate
xcodebuild -project MellowPhoto.xcodeproj -scheme MellowPhoto -destination 'platform=macOS' test 2>&1 | grep -E "Test Suite|passed|failed|error:" | tail -20
xcodebuild -project MellowPhoto.xcodeproj -scheme MellowPhoto -destination "platform=iOS Simulator,name=iPhone 17" test 2>&1 | grep -E "Test Suite|passed|failed|error:" | tail -20
```
Expected: 두 플랫폼 모두 `** TEST SUCCEEDED **`, 16 tests passed.

- [ ] **Step 6: 커밋**

```bash
git add apple/MellowPhoto/Application apple/MellowPhotoTests apple/MellowPhoto.xcodeproj
git commit -m "feat(app): AppModel과 가져오기·내보내기 유스케이스 추가

Mac·iPhone 저장소에 흩어져 있던 조립 로직을 composition root 하나로
모으고, 모듈을 가로지르는 두 흐름만 유스케이스로 분리해 가짜 어댑터로
롤백·취소·거부 규칙을 검증한다.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 10: 플랫폼 어댑터와 실제 조립

**Files:**
- Create: `apple/MellowPhoto/Platform/SystemPhotoImporter.swift`
- Create: `apple/MellowPhoto/Platform/PhotoLibraryDestination.swift` (iOS·iPadOS)
- Create: `apple/MellowPhoto/Platform/FolderDestination.swift` (macOS)
- Create: `apple/MellowPhoto/Platform/LegacyMacPresets.swift`
- Create: `apple/MellowPhoto/Platform/AppModel+Live.swift`
- Test: `apple/MellowPhotoTests/SystemPhotoImporterTests.swift`
- Test: `apple/MellowPhotoTests/LegacyMacPresetsTests.swift`
- Test: `apple/MellowPhotoTests/FolderDestinationTests.swift`

**Interfaces:**
- Consumes: `PhotoImporter`, `StagedPhoto`, `AppModel` (Task 9), `ExportDestination`, `FileNamingPolicy` (Task 7), `JSONSessionStore`, `WorkingCopyStore`, `LibraryPolicy`, `ProjectSession` (Task 4), `VisionFaceAnalyzer`, `RenderTuning` (Task 5·6).
- Produces: `SystemPhotoImporter()`, `PhotoLibraryDestination()`, `FolderDestination(folder:)`, `LegacyMacPresets.importIfPresent(into:applicationSupport:)`, `AppModel.live()`. Task 11이 쓴다.

- [ ] **Step 1: 실패하는 테스트 작성**

`apple/MellowPhotoTests/SystemPhotoImporterTests.swift`:

```swift
import XCTest
@testable import Mellow_Photo

final class SystemPhotoImporterTests: XCTestCase {
    func testStagingFileURLsCopiesIntoTemporaryFolderAndKeepsStem() async throws {
        let root = try TestSupport.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let original = try TestSupport.solidPNG(in: root, name: "IMG_0042")
        let results = await SystemPhotoImporter().stage(fileURLs: [original, root.appendingPathComponent("missing.png")])
        XCTAssertEqual(results.count, 2)
        let staged = try results[0].get()
        XCTAssertEqual(staged.displayName, "IMG_0042")
        XCTAssertNotEqual(staged.url, original)
        XCTAssertEqual(try Data(contentsOf: staged.url), try Data(contentsOf: original), "원본은 복사만 하고 건드리지 않는다")
        XCTAssertTrue(FileManager.default.fileExists(atPath: original.path))
        XCTAssertThrowsError(try results[1].get())
        try? FileManager.default.removeItem(at: staged.url)
    }
}
```

`apple/MellowPhotoTests/LegacyMacPresetsTests.swift`:

```swift
import MellowLibrary
import XCTest
@testable import Mellow_Photo

@MainActor
final class LegacyMacPresetsTests: XCTestCase {
    func testLegacyPresetsFileIsImportedOnceAndRenamed() throws {
        let support = try TestSupport.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: support) }
        let legacy = support.appendingPathComponent("MellowPhoto/presets.json")
        try FileManager.default.createDirectory(at: legacy.deletingLastPathComponent(), withIntermediateDirectories: true)
        let json = #"[{"id":"44444444-4444-4444-4444-444444444444","name":"옛날","adjustments":{"exposure":0.2,"contrast":1,"saturation":0.9,"warmth":0.1,"skin":0.4,"faceSlim":0}}]"#
        try Data(json.utf8).write(to: legacy)
        let session = ProjectSession(store: MemorySessionStore(), maxPhotos: 40)
        LegacyMacPresets.importIfPresent(into: session, applicationSupport: support)
        XCTAssertEqual(session.presets.map(\.name), ["옛날"])
        XCTAssertEqual(session.presets[0].values.portrait.skinSmoothing, 0.4)
        XCTAssertFalse(FileManager.default.fileExists(atPath: legacy.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: legacy.path + ".imported"))
        LegacyMacPresets.importIfPresent(into: session, applicationSupport: support)
        XCTAssertEqual(session.presets.count, 1, "두 번째 실행은 아무것도 하지 않는다")
    }
}
```

`apple/MellowPhotoTests/FolderDestinationTests.swift`:

```swift
#if os(macOS)
import XCTest
@testable import Mellow_Photo

final class FolderDestinationTests: XCTestCase {
    func testPublishCopiesWithMellowNameAndAvoidsCollisions() async throws {
        let root = try TestSupport.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let source = try TestSupport.solidPNG(in: root, name: "render")
        let folder = root.appendingPathComponent("out")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let destination = FolderDestination(folder: folder)
        try await destination.publish(fileURL: source, suggestedName: "IMG_1_mellow")
        try await destination.publish(fileURL: source, suggestedName: "IMG_1_mellow")
        let names = try FileManager.default.contentsOfDirectory(atPath: folder.path).sorted()
        XCTAssertEqual(names, ["IMG_1_mellow.png", "IMG_1_mellow_2.png"])
        XCTAssertTrue(FileManager.default.fileExists(atPath: source.path), "임시 파일 정리는 유스케이스 몫이다")
    }
}
#endif
```

- [ ] **Step 2: 실패 확인**

Run: `cd apple && xcodegen generate && xcodebuild -project MellowPhoto.xcodeproj -scheme MellowPhoto -destination 'platform=macOS' build-for-testing 2>&1 | grep -c "error:"`
Expected: 0보다 큰 수 (미정의 타입).

- [ ] **Step 3: 구현**

`apple/MellowPhoto/Platform/SystemPhotoImporter.swift`:

```swift
import CoreTransferable
import Foundation
import MellowShared
import PhotosUI
import UniformTypeIdentifiers

/// PhotosPicker 항목을 임시 파일로 받는 Transferable.
private struct ImportedPhotoFile: Transferable {
    let url: URL

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(importedContentType: .image) { received in
            let url = try SystemPhotoImporter.stagingURL(extension: received.file.pathExtension)
            try FileManager.default.copyItem(at: received.file, to: url)
            return ImportedPhotoFile(url: url)
        }
    }
}

struct SystemPhotoImporter: PhotoImporter {
    static let stagingFolder = FileManager.default.temporaryDirectory.appendingPathComponent("MellowImports", isDirectory: true)

    static func stagingURL(extension fileExtension: String) throws -> URL {
        try FileManager.default.createDirectory(at: stagingFolder, withIntermediateDirectories: true)
        return stagingFolder.appendingPathComponent(UUID().uuidString).appendingPathExtension(fileExtension.isEmpty ? "image" : fileExtension)
    }

    func stage(_ items: [PhotosPickerItem]) async -> [Result<StagedPhoto, Error>] {
        var results: [Result<StagedPhoto, Error>] = []
        for item in items {
            do {
                guard let file = try await item.loadTransferable(type: ImportedPhotoFile.self) else {
                    throw MellowError.cannotOpenPhoto(filename: "사진 앱 항목")
                }
                results.append(.success(StagedPhoto(url: file.url, displayName: nil)))
            } catch {
                results.append(.failure(error))
            }
        }
        return results
    }

    /// fileImporter·드롭으로 받은 파일. 보안 범위 접근 안에서 복사만 한다.
    func stage(fileURLs: [URL]) async -> [Result<StagedPhoto, Error>] {
        fileURLs.map { url in
            let accessed = url.startAccessingSecurityScopedResource()
            defer { if accessed { url.stopAccessingSecurityScopedResource() } }
            do {
                guard FileManager.default.fileExists(atPath: url.path) else {
                    throw MellowError.cannotOpenPhoto(filename: url.lastPathComponent)
                }
                let staged = try Self.stagingURL(extension: url.pathExtension)
                try FileManager.default.copyItem(at: url, to: staged)
                return .success(StagedPhoto(url: staged, displayName: url.deletingPathExtension().lastPathComponent))
            } catch {
                return .failure(error)
            }
        }
    }
}
```

`apple/MellowPhoto/Platform/PhotoLibraryDestination.swift`:

```swift
#if os(iOS)
import Foundation
import MellowExport
import MellowShared
import Photos

/// 사진 앱에 새 사진으로 추가한다. 원본 자산은 건드리지 않는다.
struct PhotoLibraryDestination: ExportDestination {
    func publish(fileURL: URL, suggestedName: String) async throws {
        let permission = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard permission == .authorized || permission == .limited else {
            throw MellowError.photoLibraryAccessDenied
        }
        do {
            try await PHPhotoLibrary.shared().performChanges {
                PHAssetChangeRequest.creationRequestForAssetFromImage(atFileURL: fileURL)
            }
        } catch {
            throw MellowError.exportFailed(reason: error.localizedDescription)
        }
    }
}
#endif
```

`apple/MellowPhoto/Platform/FolderDestination.swift`:

```swift
#if os(macOS)
import Foundation
import MellowExport
import MellowShared

/// 사용자가 고른 폴더에 "<이름>.<확장자>"로 복사한다. 충돌하면 번호를 붙인다.
struct FolderDestination: ExportDestination {
    let folder: URL

    func publish(fileURL: URL, suggestedName: String) async throws {
        let accessed = folder.startAccessingSecurityScopedResource()
        defer { if accessed { folder.stopAccessingSecurityScopedResource() } }
        let stem = String(suggestedName.dropLast(suggestedName.hasSuffix(FileNamingPolicy.suffix) ? FileNamingPolicy.suffix.count : 0))
        let target = FileNamingPolicy.availableURL(in: folder, stem: stem, fileExtension: fileURL.pathExtension) {
            FileManager.default.fileExists(atPath: $0.path)
        }
        do {
            try FileManager.default.copyItem(at: fileURL, to: target)
        } catch {
            throw MellowError.exportFailed(reason: error.localizedDescription)
        }
    }
}
#endif
```

`apple/MellowPhoto/Platform/LegacyMacPresets.swift`:

```swift
import Foundation
import MellowLibrary
import MellowShared

/// 구 Mac 앱의 presets.json을 한 번만 세션으로 흡수한다.
enum LegacyMacPresets {
    private struct LegacyPreset: Decodable {
        struct Adjustments: Decodable {
            var exposure = 0.0
            var contrast = 1.0
            var saturation = 1.0
            var warmth = 0.0
            var skin = 0.0
            var faceSlim = 0.0
        }

        var id: UUID
        var name: String
        var adjustments: Adjustments
    }

    @MainActor
    static func importIfPresent(into session: ProjectSession, applicationSupport: URL) {
        let file = applicationSupport.appendingPathComponent("MellowPhoto/presets.json")
        guard FileManager.default.fileExists(atPath: file.path) else { return }
        defer { try? FileManager.default.moveItem(at: file, to: file.appendingPathExtension("imported")) }
        guard let data = try? Data(contentsOf: file), let presets = try? JSONDecoder().decode([LegacyPreset].self, from: data) else { return }
        for preset in presets {
            let values = PresetValues(
                color: ColorAdjustments(exposure: preset.adjustments.exposure, contrast: preset.adjustments.contrast, saturation: preset.adjustments.saturation, warmth: preset.adjustments.warmth),
                portrait: PortraitAdjustments(skinSmoothing: preset.adjustments.skin, faceSlim: preset.adjustments.faceSlim))
            session.addPreset(named: preset.name, values: values)
        }
    }
}
```

`apple/MellowPhoto/Platform/AppModel+Live.swift`:

```swift
import Foundation
import MellowExport
import MellowLibrary
import MellowRendering

extension AppModel {
    /// 실제 기기용 조립. 테스트는 TestSupport.makeModel을 쓴다.
    static func live() -> AppModel {
        let applicationSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let root = applicationSupport.appendingPathComponent("MellowPhoto", isDirectory: true)
        let copies = WorkingCopyStore(directory: root.appendingPathComponent("Library", isDirectory: true))
        let session = ProjectSession(store: JSONSessionStore(fileURL: root.appendingPathComponent("session.json")), maxPhotos: LibraryPolicy.maxPhotosForCurrentDevice)
        let model = AppModel(
            session: session,
            pipeline: PhotoPipeline(analyzer: VisionFaceAnalyzer(), tuning: RenderTuning.forCurrentDevice()),
            copies: copies,
            importer: SystemPhotoImporter(),
            exporter: Exporter(renderer: Renderer()))
        do {
            try copies.prepareDirectory()
        } catch {
            model.present(message: "작업 폴더를 열지 못했습니다: \(error.localizedDescription)")
        }
        #if os(macOS)
        LegacyMacPresets.importIfPresent(into: session, applicationSupport: applicationSupport)
        #endif
        return model
    }
}
```

주의: 구 iPhone 앱은 작업 사본을 `MellowPhoto/` 바로 아래에 두었고 새 코드는 `MellowPhoto/Library/`를 쓴다. 출시본 세션 호환을 위해 `WorkingCopyStore.url(for:)`는 `Library/<filename>`이 없고 `../<filename>`이 있으면 그 경로를 돌려준다. Task 4의 `url(for:)`를 다음으로 바꾸고 `JSONSessionStoreTests`에 `testLegacyWorkingCopyLocationIsFound`를 추가한다:

```swift
public func url(for filename: String) -> URL {
    let current = directory.appendingPathComponent(filename)
    if FileManager.default.fileExists(atPath: current.path) { return current }
    let legacy = directory.deletingLastPathComponent().appendingPathComponent(filename)
    return FileManager.default.fileExists(atPath: legacy.path) ? legacy : current
}
```

```swift
func testLegacyWorkingCopyLocationIsFound() throws {
    let root = try FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let store = WorkingCopyStore(directory: root.appendingPathComponent("Library"))
    try store.prepareDirectory()
    try Data([1]).write(to: root.appendingPathComponent("old.heic"))
    XCTAssertEqual(store.url(for: "old.heic"), root.appendingPathComponent("old.heic"))
    XCTAssertEqual(store.url(for: "new.heic"), root.appendingPathComponent("Library/new.heic"))
}
```

- [ ] **Step 4: 통과 확인**

Run: Task 9 Step 5와 같은 두 명령.
Expected: macOS 19 tests, iPhone 18 tests PASS (FolderDestination은 macOS만).

- [ ] **Step 5: 커밋**

```bash
git add apple
git commit -m "feat(app): 사진 가져오기·저장 어댑터와 실기기 조립 추가

PhotosPicker·파일 가져오기는 세 플랫폼 공통 코드로, 저장 대상만
사진 앱(iOS)과 폴더(Mac)로 나눈다. 구 Mac 프리셋 파일은 한 번만 흡수한다.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 11: 적응형 화면 (compact·regular)

**Files:**
- Modify: `apple/MellowPhoto/App/MellowPhotoApp.swift` (전면 교체)
- Delete: `apple/MellowPhoto/App/RootView.swift`
- Create: `apple/MellowPhoto/Features/Shared/Theme.swift`
- Create: `apple/MellowPhoto/Features/Shared/AdjustmentSlider.swift`
- Create: `apple/MellowPhoto/Features/Shared/StatusBar.swift`
- Create: `apple/MellowPhoto/Features/Editor/EditorScene.swift`
- Create: `apple/MellowPhoto/Features/Editor/PhotoCanvasView.swift`
- Create: `apple/MellowPhoto/Features/Editor/ColorPanel.swift`
- Create: `apple/MellowPhoto/Features/Editor/PortraitPanel.swift`
- Create: `apple/MellowPhoto/Features/Editor/BrushPanel.swift`
- Create: `apple/MellowPhoto/Features/Editor/ActionBar.swift`
- Create: `apple/MellowPhoto/Features/Library/WelcomeView.swift`
- Create: `apple/MellowPhoto/Features/Library/ThumbnailCell.swift`
- Create: `apple/MellowPhoto/Features/Library/PhotoStripView.swift`
- Create: `apple/MellowPhoto/Features/Library/LibrarySidebar.swift`
- Create: `apple/MellowPhoto/Features/Library/PhotoPickerButton.swift`
- Create: `apple/MellowPhoto/Features/Export/ExportMenu.swift`
- Create: `apple/MellowPhoto/Features/Presets/PresetSheet.swift`
- Create: `apple/MellowPhoto/Features/Info/InfoSheet.swift`
- Test: 없음 (화면은 Task 14에서 시뮬레이터·Mac 실기동으로 검증)

**Interfaces:**
- Consumes: `AppModel` 전체 (Task 9·10), `EditorTool`, `BuiltInPresets`, `ExportFormat`, `ExportOptions`.
- Produces: 화면. 다른 Task가 참조하지 않는다.

- [ ] **Step 1: 공통 요소**

`apple/MellowPhoto/Features/Shared/Theme.swift`:

```swift
import SwiftUI

enum Theme {
    static let accent = Color(red: 0.78, green: 0.88, blue: 0.69)
    static let panel = Color(red: 0.11, green: 0.12, blue: 0.12)
    static let canvas = Color(red: 0.075, green: 0.083, blue: 0.083)
    static let sidebarWidth: CGFloat = 174
    static let inspectorWidth: CGFloat = 292
    static let compactControlsHeight: CGFloat = 182
    static let thumbnailCompact = CGSize(width: 52, height: 60)
    static let thumbnailRegular = CGSize(width: 130, height: 152)
}

extension Image {
    init(cgImage: CGImage) {
        self.init(decorative: cgImage, scale: 1, orientation: .up)
    }
}
```

`apple/MellowPhoto/Features/Shared/AdjustmentSlider.swift`:

```swift
import MellowEditing
import SwiftUI

struct AdjustmentSlider: View {
    @Environment(AppModel.self) private var model
    let title: String
    let value: Double
    let range: ClosedRange<Double>
    let change: (Double) -> EditChange

    var body: some View {
        VStack(spacing: 5) {
            HStack {
                Text(title)
                Spacer()
                Text(value, format: .number.precision(.fractionLength(2))).monospacedDigit().foregroundStyle(.secondary)
            }
            .font(.caption)
            Slider(value: Binding(get: { value }, set: { model.edit(change($0)) }), in: range) { editing in
                if editing { model.beginSliderEdit() } else { model.endSliderEdit() }
            }
            .accessibilityLabel(title)
        }
    }
}
```

`apple/MellowPhoto/Features/Shared/StatusBar.swift`:

```swift
import SwiftUI

struct StatusBar: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(spacing: 6) {
            if model.isExporting { ProgressView(value: model.exportProgress) }
            HStack {
                Text(model.statusMessage).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                Spacer()
                if model.isExporting {
                    Button("나머지 취소") { model.cancelExport() }.font(.caption)
                }
            }
        }
        .padding(.horizontal).padding(.vertical, 8)
    }
}
```

- [ ] **Step 2: 라이브러리 뷰**

`apple/MellowPhoto/Features/Library/PhotoPickerButton.swift`:

```swift
import PhotosUI
import SwiftUI

struct PhotoPickerButton: View {
    @Environment(AppModel.self) private var model
    @State private var items: [PhotosPickerItem] = []
    @State private var showingFiles = false
    var prominent = false

    var body: some View {
        Menu {
            PhotosPicker(selection: $items, maxSelectionCount: max(1, model.session.remainingCapacity), matching: .images, preferredItemEncoding: .current) {
                Label("사진 앱에서 고르기", systemImage: "photo.on.rectangle")
            }
            Button { showingFiles = true } label: { Label("파일에서 고르기", systemImage: "folder") }
        } label: {
            Label("사진 가져오기", systemImage: "plus")
        }
        .disabled(model.isBusy || model.session.remainingCapacity == 0)
        .onChange(of: items) { _, newItems in
            guard !newItems.isEmpty else { return }
            let selected = newItems
            items = []
            Task { await model.importFromPicker(selected) }
        }
        .fileImporter(isPresented: $showingFiles, allowedContentTypes: [.image], allowsMultipleSelection: true) { result in
            if case .success(let urls) = result {
                Task { await model.importFromFiles(urls) }
            }
        }
    }
}
```

`apple/MellowPhoto/Features/Library/ThumbnailCell.swift`:

```swift
import MellowLibrary
import SwiftUI

struct ThumbnailCell: View {
    @Environment(AppModel.self) private var model
    let entry: PhotoEntry
    let size: CGSize

    var body: some View {
        Button { model.select(entry.id) } label: {
            ZStack(alignment: .bottomTrailing) {
                if let image = model.thumbnails[entry.id] {
                    Image(cgImage: image).resizable().scaledToFill()
                } else {
                    Rectangle().fill(.secondary.opacity(0.2)).overlay(Image(systemName: "photo"))
                }
                if entry.document.hasEdits {
                    Image(systemName: "slider.horizontal.3").font(.caption2).padding(4).background(.black.opacity(0.6), in: Circle()).padding(3)
                }
            }
            .frame(width: size.width, height: size.height)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(entry.id == model.session.selectedPhotoID ? Theme.accent : .clear, lineWidth: 2))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(entry.displayName)
        .accessibilityAddTraits(entry.id == model.session.selectedPhotoID ? .isSelected : [])
    }
}
```

`apple/MellowPhoto/Features/Library/PhotoStripView.swift`:

```swift
import SwiftUI

struct PhotoStripView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 10) {
                ForEach(model.session.photos) { entry in
                    ThumbnailCell(entry: entry, size: Theme.thumbnailCompact)
                }
            }
            .padding(.horizontal).padding(.vertical, 8)
        }
        .scrollIndicators(.hidden)
        .disabled(model.isBusy)
    }
}
```

`apple/MellowPhoto/Features/Library/LibrarySidebar.swift`:

```swift
import SwiftUI

struct LibrarySidebar: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("내 사진").font(.system(size: 13, weight: .semibold))
                Spacer()
                Text("\(model.session.photos.count)").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            }
            .padding(18)
            ScrollView {
                LazyVStack(spacing: 15) {
                    ForEach(model.session.photos) { entry in
                        VStack(alignment: .leading, spacing: 7) {
                            ThumbnailCell(entry: entry, size: Theme.thumbnailRegular)
                            Text(entry.displayName).font(.system(size: 10)).lineLimit(1).foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(.horizontal, 16).padding(.bottom, 16)
            }
            Spacer(minLength: 0)
            Text("HEIC · JPEG · PNG\n원본은 늘 그대로").font(.system(size: 10)).foregroundStyle(.secondary).lineSpacing(5).padding(18)
        }
        .frame(width: Theme.sidebarWidth)
        .disabled(model.isBusy)
    }
}
```

`apple/MellowPhoto/Features/Library/WelcomeView.swift`:

```swift
import SwiftUI

struct WelcomeView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            Image(systemName: "camera.macro").font(.system(size: 68, weight: .ultraLight)).foregroundStyle(Theme.accent)
            Text("좋아하는 순간을,\n조금 더 부드럽게.").font(.largeTitle.weight(.light)).multilineTextAlignment(.center)
            Text("인물 사진을 나답게 다듬어보세요.").font(.subheadline).foregroundStyle(.secondary)
            PhotoPickerButton(prominent: true).buttonStyle(.borderedProminent).controlSize(.large)
            Text("사진은 기기 안에서 처리해요.\n편집 기록 자동 저장").font(.caption).multilineTextAlignment(.center).foregroundStyle(.secondary)
            if model.isRestoring || model.isImporting { ProgressView() }
            Spacer()
        }
        .padding().frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
```

- [ ] **Step 3: 캔버스와 패널**

`apple/MellowPhoto/Features/Editor/PhotoCanvasView.swift`:

```swift
import MellowShared
import SwiftUI

/// 미리보기 표시, 잡티 탭, 변형 드래그, 샘플 위치 표시. 좌표는 정규화·원점 왼쪽 아래로 넘긴다.
struct PhotoCanvasView: View {
    @Environment(AppModel.self) private var model
    var zoom: Double = 1

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Theme.canvas
                if let image = model.displayImage {
                    let fit = min(geometry.size.width / CGFloat(image.width), geometry.size.height / CGFloat(image.height))
                    let size = CGSize(width: CGFloat(image.width) * fit * zoom, height: CGFloat(image.height) * fit * zoom)
                    ScrollView([.horizontal, .vertical]) {
                        Image(cgImage: image).resizable().interpolation(.high)
                            .frame(width: size.width, height: size.height)
                            .overlay { cloneSourceMarker(in: size) }
                            .overlay { touchLayer(in: size) }
                            .frame(minWidth: geometry.size.width, minHeight: geometry.size.height)
                    }
                    .scrollDisabled(zoom == 1)
                    .accessibilityLabel(model.isComparing ? "원본 사진" : "보정 미리보기")
                }
                if let message = model.selectionFailure {
                    recoveryActions(message)
                } else if !model.isReady || model.isRendering {
                    ProgressView().padding(12).background(.ultraThinMaterial, in: Capsule()).allowsHitTesting(false)
                }
            }
            .overlay(alignment: .topLeading) {
                if model.isReady {
                    Text(model.isComparing ? "원본" : "보정본").font(.caption2).padding(7).background(.ultraThinMaterial, in: Capsule()).padding(10)
                }
            }
            .clipped()
        }
    }

    @ViewBuilder
    private func cloneSourceMarker(in size: CGSize) -> some View {
        if let source = model.cloneSource, model.tool == .retouch, !model.isComparing {
            let diameter = max(12, model.brushRadius * min(size.width, size.height) * 2)
            Circle().stroke(Theme.accent, lineWidth: 2)
                .frame(width: diameter, height: diameter)
                .position(x: source.x * size.width, y: (1 - source.y) * size.height)
                .allowsHitTesting(false)
        }
    }

    @ViewBuilder
    private func touchLayer(in size: CGSize) -> some View {
        if model.tool.usesCanvasTouch, !model.isComparing {
            Color.clear.contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 0).onEnded { value in
                    guard size.width > 0, size.height > 0 else { return }
                    func normalized(_ point: CGPoint) -> NormalizedPoint {
                        NormalizedPoint(x: max(0, min(1, point.x / size.width)), y: max(0, min(1, 1 - point.y / size.height)))
                    }
                    #if os(macOS)
                    if model.tool == .retouch, NSEvent.modifierFlags.contains(.option) {
                        model.resetCloneSource()
                    }
                    #endif
                    model.touch(from: normalized(value.startLocation), to: normalized(value.location))
                })
        }
    }

    private func recoveryActions(_ message: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "photo.badge.exclamationmark").font(.title)
            Text(message).font(.callout).multilineTextAlignment(.center)
            HStack {
                Button("다시 시도") { if let id = model.session.selectedPhotoID { model.select(id) } }
                Button("편집에서 빼기", role: .destructive) { model.removeSelectedPhoto() }
            }
            .buttonStyle(.bordered).disabled(model.isBusy)
        }
        .padding()
    }
}
```

`apple/MellowPhoto/Features/Editor/ColorPanel.swift`:

```swift
import MellowShared
import SwiftUI

struct ColorPanel: View {
    @Environment(AppModel.self) private var model
    @Binding var presetSheet: Bool

    var body: some View {
        let recipe = model.currentRecipe
        ScrollView(.horizontal) {
            HStack {
                ForEach(BuiltInPresets.all + model.session.presets) { preset in
                    Button(preset.name) { model.applyPreset(preset.values) }
                }
                Button { presetSheet = true } label: { Label("저장", systemImage: "plus") }
            }
            .buttonStyle(.bordered).font(.caption)
        }
        .scrollIndicators(.hidden)
        AdjustmentSlider(title: "노출", value: recipe.color.exposure, range: -1.5...1.5) { .exposure($0) }
        AdjustmentSlider(title: "대비", value: recipe.color.contrast, range: 0.7...1.3) { .contrast($0) }
        AdjustmentSlider(title: "채도", value: recipe.color.saturation, range: 0...1.5) { .saturation($0) }
        AdjustmentSlider(title: "따뜻함", value: recipe.color.warmth, range: -1...1) { .warmth($0) }
    }
}
```

`apple/MellowPhoto/Features/Editor/PortraitPanel.swift`:

```swift
import SwiftUI

struct PortraitPanel: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let recipe = model.currentRecipe
        if let failure = model.selectedInfo?.faceAnalysisFailure {
            Label("자동 얼굴 분석을 사용할 수 없어요", systemImage: "exclamationmark.triangle")
            Text(UserMessage.text(for: failure)).font(.caption).foregroundStyle(.secondary)
        } else if model.faces.isEmpty {
            Label("감지된 얼굴이 없어요", systemImage: "person.crop.rectangle.badge.questionmark")
            Text("정면에 가까운 사진을 선택하거나 잡티·변형 도구를 직접 사용해 주세요.").font(.caption).foregroundStyle(.secondary)
        } else {
            Picker("얼굴 \(model.faces.count)명", selection: Binding(get: { recipe.portrait.targetFace ?? -1 }, set: { model.edit(.targetFace($0 == -1 ? nil : $0)) })) {
                Text("모든 얼굴").tag(-1)
                ForEach(model.faces.indices, id: \.self) { Text("왼쪽부터 \($0 + 1)번째").tag($0) }
            }
            .disabled(model.isGeometryLocked)
            AdjustmentSlider(title: "피부 정돈", value: recipe.portrait.skinSmoothing, range: 0...1) { .skinSmoothing($0) }
            AdjustmentSlider(title: "얼굴 미세 조정", value: recipe.portrait.faceSlim, range: 0...1) { .faceSlim($0) }
                .disabled(model.isGeometryLocked)
            Text(model.isGeometryLocked ? UserMessage.geometryLocked : "얼굴 형태를 먼저 조정한 뒤 잡티를 보정해 주세요. 피부 정돈은 부드러운 필터이며 자동 잡티 제거는 아닙니다.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}
```

`apple/MellowPhoto/Features/Editor/BrushPanel.swift`:

```swift
import SwiftUI

struct BrushPanel: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        Text(instruction).font(.subheadline)
        if model.tool == .retouch {
            Button("샘플 위치 다시 고르기") { model.resetCloneSource() }.buttonStyle(.bordered)
            #if os(macOS)
            Text("⌥ Option + 클릭으로도 샘플 위치를 바꿀 수 있습니다.").font(.caption2).foregroundStyle(.secondary)
            #endif
        }
        HStack {
            Text("브러시 크기").font(.caption)
            Slider(value: $model.brushRadius, in: AppModel.Policy.brushRadiusRange).accessibilityLabel("브러시 크기")
        }
        Text(model.tool == .retouch ? "자동 탐지가 아닌 수동 복제 브러시입니다. 가까운 피부를 샘플로 선택하면 더 자연스러워요." : "배경도 함께 움직일 수 있어요. 조금씩 조정하고 원본과 비교해 주세요.")
            .font(.caption).foregroundStyle(.secondary)
        Text("잡티 보정 \(model.currentRecipe.spots.count)회 · 부분 변형 \(model.currentRecipe.warps.count)회").font(.caption2).foregroundStyle(.secondary)
    }

    private var instruction: String {
        if model.tool == .retouch {
            return model.isChoosingCloneSource ? UserMessage.chooseCloneSource : UserMessage.chooseCloneTarget
        }
        return "조정할 부분을 원하는 방향으로 살짝 밀어주세요."
    }
}
```

`apple/MellowPhoto/Features/Editor/ActionBar.swift`:

```swift
import SwiftUI

struct ActionBar: View {
    @Environment(AppModel.self) private var model
    @Binding var zoom: Double
    var showsZoom = false

    var body: some View {
        HStack {
            Button { model.undo() } label: { Image(systemName: "arrow.uturn.backward").frame(width: 40, height: 40) }
                .disabled(!model.canUndo).accessibilityLabel("실행 취소").help("실행 취소 ⌘Z")
            Button { model.redo() } label: { Image(systemName: "arrow.uturn.forward").frame(width: 40, height: 40) }
                .disabled(!model.canRedo).accessibilityLabel("다시 실행").help("다시 실행 ⇧⌘Z")
            Spacer()
            if let size = model.selectedInfo?.pixelSize {
                Text("\(Int(size.width)) × \(Int(size.height))").font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
            }
            if showsZoom {
                Button("−") { zoom = max(1, zoom - 0.5) }
                Text(zoom == 1 ? "화면에 맞춤" : "\(Int(zoom * 100))%").font(.caption2).frame(width: 75)
                Button("+") { zoom = min(4, zoom + 0.5) }
            }
            Button { model.isComparing.toggle() } label: {
                Text(model.isComparing ? "보정본" : "원본 비교").font(.caption.weight(.medium)).frame(minWidth: 65, minHeight: 40)
            }
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 12)
        .disabled(model.isBusy || !model.isReady)
    }
}
```

- [ ] **Step 4: 내보내기·시트**

`apple/MellowPhoto/Features/Export/ExportMenu.swift`:

```swift
import MellowExport
import SwiftUI

struct ExportMenu: View {
    @Environment(AppModel.self) private var model
    @Binding var removeConfirmation: Bool
    @State private var pendingAll = false
    @State private var choosingFolder = false

    var body: some View {
        @Bindable var model = model
        Menu {
            Button("현재 사진 저장", systemImage: "square.and.arrow.down") { start(all: false) }.disabled(!model.isReady)
            Button("전체 \(model.session.photos.count)장 저장") { start(all: true) }.disabled(!model.isReady)
            Picker("형식", selection: $model.exportOptions.format) {
                Text("JPEG · 추천").tag(ExportFormat.jpeg)
                Text("PNG").tag(ExportFormat.png)
            }
            Toggle("원본 해상도", isOn: $model.exportOptions.fullResolution)
            Text("기본: 긴 변 최대 \(ExportOptions.defaultMaxDimension)px")
            Divider()
            Button("편집에서 사진 빼기", role: .destructive) { removeConfirmation = true }
        } label: {
            Label("저장", systemImage: "square.and.arrow.down").font(.body.weight(.semibold))
        }
        .disabled(!model.canRemoveSelected)
        #if os(macOS)
        .fileImporter(isPresented: $choosingFolder, allowedContentTypes: [.folder]) { result in
            if case .success(let folder) = result {
                model.export(all: pendingAll, to: FolderDestination(folder: folder))
            }
        }
        #endif
    }

    private func start(all: Bool) {
        pendingAll = all
        #if os(iOS)
        model.export(all: all, to: PhotoLibraryDestination())
        #else
        choosingFolder = true
        #endif
    }
}
```

`apple/MellowPhoto/Features/Presets/PresetSheet.swift`:

```swift
import SwiftUI

struct PresetSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""

    var body: some View {
        NavigationStack {
            Form {
                TextField("분위기 이름", text: $name)
                Text("색감·피부·얼굴 슬라이더 값만 저장합니다. 잡티 위치와 수동 변형은 포함하지 않습니다.").font(.caption).foregroundStyle(.secondary)
            }
            .navigationTitle("분위기 저장")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("취소") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("저장") {
                        model.savePreset(named: name)
                        dismiss()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .presentationDetents([.medium])
        .frame(minWidth: 360, minHeight: 200)
    }
}
```

`apple/MellowPhoto/Features/Info/InfoSheet.swift`:

```swift
import SwiftUI

struct InfoSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section("Mellow Photo") {
                    Text("사진과 얼굴 분석은 기기 내부에서 처리합니다. 작업 기록은 앱에 저장되고, 사진 앱·파일 원본은 변경하지 않습니다.")
                    Text("앱 삭제 시 내부 작업 기록은 사라집니다. 완성한 사진은 저장해 주세요.")
                }
                Section("도움말") {
                    Link("지원 페이지", destination: URL(string: "https://mj-0701.github.io/mellow-photo-support/")!)
                    Link("개인정보 안내", destination: URL(string: "https://mj-0701.github.io/mellow-photo-support/privacy.html")!)
                    Link("이메일 문의", destination: URL(string: "mailto:jack2718@naver.com")!)
                }
            }
            .navigationTitle("도움말과 개인정보")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("닫기") { dismiss() } } }
        }
        .frame(minWidth: 420, minHeight: 320)
    }
}
```

- [ ] **Step 5: 적응형 루트와 앱 진입점**

`apple/MellowPhoto/Features/Editor/EditorScene.swift`:

```swift
import SwiftUI

/// compact(iPhone 세로)는 세로 스택, regular(iPad·Mac)는 3단.
struct EditorScene: View {
    @Environment(AppModel.self) private var model
    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var zoom = 1.0
    @State private var presetSheet = false
    @State private var infoSheet = false
    @State private var resetConfirmation = false
    @State private var removeConfirmation = false

    var body: some View {
        @Bindable var model = model
        NavigationStack {
            Group {
                if model.session.photos.isEmpty {
                    WelcomeView()
                } else if sizeClass == .compact {
                    compactLayout
                } else {
                    regularLayout
                }
            }
            .navigationTitle("mellow")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .navigation) {
                    HStack {
                        Button { infoSheet = true } label: { Image(systemName: "info.circle") }.accessibilityLabel("도움말과 개인정보")
                        PhotoPickerButton().labelStyle(.iconOnly)
                    }
                }
                ToolbarItem(placement: .primaryAction) {
                    ExportMenu(removeConfirmation: $removeConfirmation)
                }
            }
        }
        .tint(Theme.accent)
        .alert("확인해주세요", isPresented: Binding(get: { model.presentedError != nil }, set: { if !$0 { model.presentedError = nil } })) {
            Button("확인") { model.presentedError = nil }
        } message: {
            Text(model.presentedError?.message ?? "")
        }
        .confirmationDialog("이 사진을 처음 상태로 돌릴까요?", isPresented: $resetConfirmation, titleVisibility: .visible) {
            Button("보정 초기화", role: .destructive) { model.reset() }
        } message: {
            Text("원본은 바뀌지 않습니다. 실행 취소로 복구할 수 있어요.")
        }
        .confirmationDialog("편집에서 사진을 뺄까요?", isPresented: $removeConfirmation, titleVisibility: .visible) {
            Button("편집에서 빼기", role: .destructive) { model.removeSelectedPhoto() }
        } message: {
            Text("이 앱의 작업 사본과 보정 기록이 삭제됩니다. 원본은 남아 있습니다.")
        }
        .sheet(isPresented: $infoSheet) { InfoSheet() }
        .sheet(isPresented: $presetSheet) { PresetSheet() }
        .onDrop(of: [.fileURL], isTargeted: nil) { providers in
            Task {
                var urls: [URL] = []
                for provider in providers {
                    if let url = try? await provider.loadItem(forTypeIdentifier: "public.file-url") as? URL { urls.append(url) }
                    else if let data = try? await provider.loadItem(forTypeIdentifier: "public.file-url") as? Data, let url = URL(dataRepresentation: data, relativeTo: nil) { urls.append(url) }
                }
                await model.importFromFiles(urls)
            }
            return true
        }
    }

    private var compactLayout: some View {
        VStack(spacing: 0) {
            PhotoStripView()
            PhotoCanvasView().frame(maxHeight: .infinity).frame(minHeight: 130)
            ActionBar(zoom: $zoom)
            compactControls
            StatusBar()
        }
    }

    private var compactControls: some View {
        @Bindable var model = model
        return VStack(spacing: 12) {
            Picker("보정 도구", selection: $model.tool) {
                ForEach(EditorTool.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            ScrollView {
                VStack(alignment: .leading, spacing: 16) { toolPanel }.padding(.vertical, 5)
            }
            .frame(height: Theme.compactControlsHeight)
            HStack {
                Button("전체 사진에 적용") { model.applyToAll() }.disabled(model.session.photos.count < 2)
                Spacer()
                Button("초기화") { resetConfirmation = true }
            }
            .font(.caption).padding(.bottom, 4)
        }
        .padding(.horizontal).padding(.top, 10)
        .background(Theme.panel)
        .disabled(model.isBusy || !model.isReady)
    }

    private var regularLayout: some View {
        @Bindable var model = model
        return HStack(spacing: 0) {
            LibrarySidebar()
            Divider()
            VStack(spacing: 0) {
                PhotoCanvasView(zoom: zoom).frame(maxWidth: .infinity, maxHeight: .infinity)
                ActionBar(zoom: $zoom, showsZoom: true).padding(.vertical, 6)
                StatusBar()
            }
            Divider()
            VStack(spacing: 0) {
                Picker("보정 도구", selection: $model.tool) {
                    ForEach(EditorTool.allCases) { Label($0.rawValue, systemImage: $0.symbol).tag($0) }
                }
                .pickerStyle(.segmented).padding(14)
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) { toolPanel }.padding(20)
                }
                Divider()
                VStack(spacing: 10) {
                    Button { model.applyToAll() } label: { Label("이 설정을 전체 사진에", systemImage: "square.on.square").frame(maxWidth: .infinity) }
                        .buttonStyle(.bordered).disabled(model.session.photos.count < 2)
                    Button("이 사진 초기화") { resetConfirmation = true }.font(.caption).buttonStyle(.plain)
                }
                .padding(18)
            }
            .frame(width: Theme.inspectorWidth)
            .background(Theme.panel)
            .disabled(model.isBusy || !model.isReady)
        }
    }

    @ViewBuilder
    private var toolPanel: some View {
        switch model.tool {
        case .color: ColorPanel(presetSheet: $presetSheet)
        case .portrait: PortraitPanel()
        case .retouch, .warp: BrushPanel()
        }
    }
}
```

`apple/MellowPhoto/App/MellowPhotoApp.swift`:

```swift
import SwiftUI

@main
struct MellowPhotoApp: App {
    @State private var model = AppModel.live()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            EditorScene()
                .environment(model)
                .preferredColorScheme(.dark)
                #if os(macOS)
                .frame(minWidth: 1040, minHeight: 700)
                #endif
                .task { await model.restore() }
                .onChange(of: scenePhase) { _, phase in
                    // 현재 사진은 마무리하고, 백그라운드에서는 일괄 저장을 멈춘다.
                    if phase == .background { model.cancelExport() }
                }
        }
        #if os(macOS)
        .defaultSize(width: 1320, height: 860)
        #endif
        .commands {
            CommandGroup(replacing: .undoRedo) {
                Button("실행 취소") { model.undo() }.keyboardShortcut("z").disabled(!model.canUndo)
                Button("다시 실행") { model.redo() }.keyboardShortcut("z", modifiers: [.command, .shift]).disabled(!model.canRedo)
            }
        }
    }
}
```

⌘O(가져오기)와 ⇧⌘S(저장)는 뷰 안의 버튼에 `.keyboardShortcut("o")`, `.keyboardShortcut("s", modifiers: [.command, .shift])`를 달아 제공한다 (PhotoPickerButton의 Menu 라벨, ExportMenu의 "현재 사진 저장").

- [ ] **Step 6: 세 플랫폼 빌드와 실기동**

Run:
```bash
cd apple && xcodegen generate
xcodebuild -project MellowPhoto.xcodeproj -scheme MellowPhoto -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build | tail -2
xcodebuild -project MellowPhoto.xcodeproj -scheme MellowPhoto -destination 'platform=macOS' build | tail -2
xcodebuild -project MellowPhoto.xcodeproj -scheme MellowPhoto -destination 'platform=macOS' test | tail -3
```
Expected: 빌드 성공, 테스트 성공. 이어서 Mac 앱을 열어 사진 가져오기 → 노출 변경 → 실행 취소 → 잡티 2회 탭 → 폴더에 저장까지 눈으로 확인한다. iPhone 시뮬레이터(`xcrun simctl install booted <app>` 후 `launch`)에서 compact 레이아웃, iPad에서 regular 레이아웃이 나오는지 스크린샷을 찍어 `docs/superpowers/plans/screenshots/`가 아니라 임시 폴더에만 보관한다.

- [ ] **Step 7: 커밋**

```bash
git add apple
git commit -m "feat(app): iPhone·iPad·Mac 적응형 편집 화면 구현

크기 클래스에 따라 세로 스택과 3단 스튜디오로 바뀌는 공통 SwiftUI
화면으로 AppKit Mac 앱과 iPhone 전용 화면을 대체한다.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 12: 구 코드 제거, 스크립트, CI, 배포 경로

**Files:**
- Delete: `Package.swift`, `Sources/`, `Tests/`, `iOS/`, `scripts/build-app.sh`, `scripts/build-ios.sh`, `scripts/test.sh`, `.github/workflows/ios-ci.yml`, `.github/workflows/ios-release.yml`
- Move: `scripts/make-icon.swift`, `scripts/make-ios-icon.swift` → `scripts/tools/`
- Move: `docs/store-assets/demo-portrait.png` → `shared/fixtures/demo-portrait.png` (`docs/store-assets/README.md`의 경로 갱신)
- Create: `scripts/env.sh` (DEVELOPER_DIR 보정, 공용 함수)
- Create: `scripts/verify-modules.sh`
- Create: `scripts/test-apple.sh`
- Create: `scripts/build-apple.sh`
- Modify: `scripts/package-mac.sh` (전면 교체)
- Create: `scripts/release.sh`
- Create: `.github/workflows/apple-checks.yml`, `.github/workflows/apple-release.yml`
- Modify: `fastlane/Fastfile:114-117` (프로젝트 경로·스킴·산출물 이름)
- Modify: `.gitignore`

**Interfaces:**
- Consumes: `apple/` 전체.
- Produces: 스크립트 5개와 워크플로 2개. Task 13 문서가 이 이름을 안내한다.

- [ ] **Step 1: 구 코드 삭제와 자산 이동**

```bash
git rm -r Package.swift Sources Tests iOS scripts/build-app.sh scripts/build-ios.sh scripts/test.sh .github/workflows/ios-ci.yml .github/workflows/ios-release.yml
mkdir -p scripts/tools
git mv scripts/make-icon.swift scripts/tools/make-icon.swift
git mv scripts/make-ios-icon.swift scripts/tools/make-ios-icon.swift
git mv docs/store-assets/demo-portrait.png shared/fixtures/demo-portrait.png
rm -rf .build .swiftpm dist
```

`docs/store-assets/README.md`에서 `demo-portrait.png` 경로를 `shared/fixtures/demo-portrait.png`로 바꾼다. `.gitignore`에 `apple/.build/`, `apple/.swiftpm/`, `apple/build/`, `dist/`를 둔다.

- [ ] **Step 2: 스크립트 작성**

`scripts/env.sh`:

```bash
#!/bin/bash
# 모든 Apple 스크립트가 source한다. Command Line Tools에는 XCTest와 iOS SDK가 없다.
set -euo pipefail
MELLOW_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export MELLOW_ROOT
if [[ -z "${DEVELOPER_DIR:-}" || "$DEVELOPER_DIR" == *CommandLineTools* ]]; then
  if [[ -d /Applications/Xcode.app/Contents/Developer ]]; then
    export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
  else
    echo 'Xcode가 필요합니다. /Applications/Xcode.app을 설치하거나 DEVELOPER_DIR을 지정하세요.' >&2
    exit 2
  fi
fi
MELLOW_PROJECT=(-project "$MELLOW_ROOT/apple/MellowPhoto.xcodeproj" -scheme MellowPhoto -derivedDataPath "$MELLOW_ROOT/apple/build")
export MELLOW_PROJECT
mellow_first_simulator() {
  xcrun simctl list devices available -j | python3 -c "
import json, sys
devices = json.load(sys.stdin)['devices']
prefix = sys.argv[1]
for runtime, items in devices.items():
    if 'iOS' not in runtime: continue
    for item in items:
        if item['name'].startswith(prefix) and item['isAvailable']:
            print(item['udid']); sys.exit(0)
sys.exit('no simulator starting with ' + prefix)
" "$1"
}
```

`scripts/verify-modules.sh`:

```bash
#!/bin/bash
# 스펙 3절의 의존성 표를 강제한다. 위반하면 종료 코드 1.
source "$(dirname "$0")/env.sh"
cd "$MELLOW_ROOT/apple"
swift package describe --type json | python3 - "$MELLOW_ROOT/apple/Sources" <<'PY'
import json, os, re, sys
allowed = {
    "MellowShared": set(),
    "MellowEditing": {"MellowShared"},
    "MellowLibrary": {"MellowShared", "MellowEditing"},
    "MellowRendering": {"MellowShared"},
    "MellowExport": {"MellowShared", "MellowRendering"},
}
forbidden = {
    "MellowShared": {"CoreImage", "Vision", "SwiftUI", "UIKit", "AppKit", "Photos", "PhotosUI", "ImageIO"},
    "MellowEditing": {"CoreImage", "Vision", "SwiftUI", "UIKit", "AppKit", "Photos", "PhotosUI"},
    "MellowLibrary": {"CoreImage", "Vision", "SwiftUI", "UIKit", "AppKit", "Photos", "PhotosUI"},
    "MellowRendering": {"SwiftUI", "UIKit", "AppKit", "Photos", "PhotosUI"},
    "MellowExport": {"SwiftUI", "UIKit", "AppKit", "Photos", "PhotosUI"},
}
package = json.load(sys.stdin)
failures = []
for target in package["targets"]:
    name = target["name"]
    if name not in allowed: continue
    actual = {d for d in target.get("target_dependencies", [])}
    extra = actual - allowed[name]
    if extra: failures.append(f"{name} depends on {sorted(extra)}")
    missing = allowed[name] - actual
    if missing: failures.append(f"{name} must declare {sorted(missing)}")
sources = sys.argv[1]
for module, banned in forbidden.items():
    for root, _, files in os.walk(os.path.join(sources, module)):
        for file in files:
            if not file.endswith(".swift"): continue
            with open(os.path.join(root, file)) as handle:
                for line in handle:
                    match = re.match(r"\s*import\s+(\w+)", line)
                    if match and match.group(1) in banned:
                        failures.append(f"{module}/{file} imports {match.group(1)}")
for module in allowed:
    api = os.path.join(sources, module, "API")
    if not os.path.isdir(api): failures.append(f"{module} has no API/ folder")
if failures:
    print("\n".join("✗ " + f for f in failures)); sys.exit(1)
print("✓ module dependencies and imports match docs/architecture/modules.md")
PY
```

`scripts/test-apple.sh`:

```bash
#!/bin/bash
source "$(dirname "$0")/env.sh"
cd "$MELLOW_ROOT"
bash scripts/verify-modules.sh
(cd apple && swift format lint --strict --recursive Sources Tests MellowPhoto MellowPhotoTests)
(cd apple && xcodegen generate --quiet && git diff --exit-code --stat MellowPhoto.xcodeproj) || { echo 'project.yml과 xcodeproj가 다릅니다. xcodegen generate 결과를 커밋하세요.' >&2; exit 1; }
(cd apple && swift test)
IPHONE="$(mellow_first_simulator iPhone)"
IPAD="$(mellow_first_simulator iPad)"
for destination in "platform=iOS Simulator,id=$IPHONE" "platform=iOS Simulator,id=$IPAD" "platform=macOS"; do
  echo "== app tests: $destination"
  xcodebuild "${MELLOW_PROJECT[@]}" -destination "$destination" CODE_SIGNING_ALLOWED=NO test 2>&1 | grep -E "Executed|TEST (SUCCEEDED|FAILED)|error:"
  [[ "${PIPESTATUS[0]}" -eq 0 ]]
done
```

`scripts/build-apple.sh`:

```bash
#!/bin/bash
# 서명 없는 Release 빌드와 번들 검사.
source "$(dirname "$0")/env.sh"
cd "$MELLOW_ROOT"
MODE="${1:-ios-device}"
case "$MODE" in
  ios-simulator) xcodebuild "${MELLOW_PROJECT[@]}" -configuration Release -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build -quiet ;;
  ios-device)
    xcodebuild "${MELLOW_PROJECT[@]}" -configuration Release -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build -quiet
    APP="$MELLOW_ROOT/apple/build/Build/Products/Release-iphoneos/Mellow Photo.app"
    /usr/bin/plutil -lint "$APP/Info.plist" "$APP/PrivacyInfo.xcprivacy"
    [[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$APP/Info.plist")" == com.mj.mellowphoto ]]
    [[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleSupportedPlatforms:0' "$APP/Info.plist")" == iPhoneOS ]]
    [[ " $(/usr/bin/lipo -archs "$APP/Mellow Photo") " == *" arm64 "* ]]
    test -s "$APP/Assets.car"
    echo 'Unsigned Release iPhone/iPad arm64 app, assets and privacy manifest verified.' ;;
  mac)
    xcodebuild "${MELLOW_PROJECT[@]}" -configuration Release -destination 'platform=macOS' ARCHS='arm64 x86_64' ONLY_ACTIVE_ARCH=NO build -quiet
    APP="$MELLOW_ROOT/apple/build/Build/Products/Release/Mellow Photo.app"
    [[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$APP/Contents/Info.plist")" == com.mj.mellowphoto ]]
    ARCHS="$(/usr/bin/lipo -archs "$APP/Contents/MacOS/Mellow Photo")"
    [[ " $ARCHS " == *" arm64 "* && " $ARCHS " == *" x86_64 "* ]]
    codesign --verify --deep --strict "$APP"
    echo "Built: $APP" ;;
  *) echo 'Usage: scripts/build-apple.sh [ios-simulator|ios-device|mac]' >&2; exit 2 ;;
esac
```

`scripts/package-mac.sh`:

```bash
#!/bin/bash
source "$(dirname "$0")/env.sh"
cd "$MELLOW_ROOT"
bash scripts/build-apple.sh mac
APP="$MELLOW_ROOT/apple/build/Build/Products/Release/Mellow Photo.app"
mkdir -p dist
STAGE="$(mktemp -d "$MELLOW_ROOT/dist/mac-package.XXXXXX")"
trap 'rm -rf "$STAGE"' EXIT
ditto "$APP" "$STAGE/Mellow Photo.app"
cp docs/MAC_INSTALL.md "$STAGE/설치와 사용 안내.txt"
ditto -c -k --sequesterRsrc "$STAGE" dist/Mellow-Photo-Mac.zip
(cd dist && shasum -a 256 Mellow-Photo-Mac.zip > Mellow-Photo-Mac.zip.sha256)
echo "Package: dist/Mellow-Photo-Mac.zip (임시 서명, 공증 전)"
```

`scripts/release.sh`:

```bash
#!/bin/bash
# 사용법: scripts/release.sh apple 1.0.0  →  Version.xcconfig 갱신, 커밋, 태그 apple-v1.0.0
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PLATFORM="${1:-}"
VERSION="${2:-}"
[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo 'Usage: scripts/release.sh <apple|android|windows> X.Y.Z' >&2; exit 2; }
[[ -z "$(git -C "$ROOT" status --porcelain)" ]] || { echo '작업 트리가 깨끗해야 합니다.' >&2; exit 1; }
case "$PLATFORM" in
  apple)
    FILE="$ROOT/apple/Config/Version.xcconfig"
    sed -i '' "s/^MARKETING_VERSION = .*/MARKETING_VERSION = $VERSION/" "$FILE"
    git -C "$ROOT" add "$FILE" ;;
  android|windows) echo "$PLATFORM 버전 파일은 아직 없습니다. 태그만 만듭니다." ;;
  *) echo 'Usage: scripts/release.sh <apple|android|windows> X.Y.Z' >&2; exit 2 ;;
esac
TAG="$PLATFORM-v$VERSION"
git -C "$ROOT" tag -l "$TAG" | grep -q . && { echo "태그 $TAG가 이미 있습니다." >&2; exit 1; }
git -C "$ROOT" commit -q -m "chore(release): $PLATFORM $VERSION" --allow-empty
git -C "$ROOT" tag -a "$TAG" -m "$PLATFORM $VERSION"
echo "태그 $TAG 생성. 푸시: git push origin main $TAG"
```

`chmod +x scripts/*.sh`.

- [ ] **Step 3: 워크플로와 Fastfile**

`.github/workflows/apple-checks.yml`:

```yaml
name: Apple checks
on:
  pull_request:
  push:
    branches: [main]
  workflow_dispatch:
permissions:
  contents: read
concurrency:
  group: apple-checks-${{ github.ref }}
  cancel-in-progress: true
jobs:
  check:
    runs-on: macos-15
    timeout-minutes: 45
    env:
      DEVELOPER_DIR: /Applications/Xcode_26.3.app/Contents/Developer
    steps:
      - uses: actions/checkout@v4
      - name: Tools
        run: |
          xcodebuild -version
          brew install xcodegen
      - name: Release notes automation tests
        run: /usr/bin/ruby fastlane/test/release_notes_test.rb
      - name: Modules, format, package and app tests
        run: ./scripts/test-apple.sh
      - name: Unsigned Release builds
        run: |
          ./scripts/build-apple.sh ios-device
          ./scripts/build-apple.sh mac
      - name: Preserve failing results
        if: failure()
        uses: actions/upload-artifact@v4
        with:
          name: apple-test-results-${{ github.run_id }}-${{ github.run_attempt }}
          path: apple/build/Logs/Test
          if-no-files-found: ignore
          retention-days: 7
```

`.github/workflows/apple-release.yml`은 현재 `ios-release.yml`을 복사해 다음만 바꾼다: `name: Apple App Store release`, 트리거 `tags: ['apple-v*']`, 버전 추출 `version="${GITHUB_REF_NAME#apple-v}"`, 검증 단계를 `brew install xcodegen` 후 `./scripts/test-apple.sh`로, 아티팩트 경로를 `apple/build/Logs/Test`로, 마지막에 Mac zip 단계를 추가한다:

```yaml
      - name: Mac package (ad-hoc signed)
        run: ./scripts/package-mac.sh
      - uses: actions/upload-artifact@v4
        with:
          name: mellow-photo-mac-${{ env.APP_VERSION }}
          path: dist/Mellow-Photo-Mac.zip*
```

`fastlane/Fastfile`의 114~117행을 다음으로 바꾼다:

```ruby
    archive = File.join(root, 'dist', 'MellowPhoto.xcarchive')
    ipa = build_app(project: File.join(root, 'apple/MellowPhoto.xcodeproj'), scheme: 'MellowPhoto',
      configuration: 'Release', clean: true, archive_path: archive, destination: 'generic/platform=iOS',
      output_directory: File.join(root, 'dist'), output_name: 'MellowPhoto.ipa',
```

`verify_bundle`의 `Dir[...*.app]` 글롭은 "Mellow Photo.app"도 잡으므로 그대로 둔다.

- [ ] **Step 4: 전체 검증**

Run: `./scripts/test-apple.sh && ./scripts/build-apple.sh ios-device && ./scripts/build-apple.sh mac && ./scripts/package-mac.sh`
Expected: 모두 성공. `dist/Mellow-Photo-Mac.zip` 생성. `git status`에 `apple/MellowPhoto.xcodeproj` 변경이 없어야 한다.

Run: `/usr/bin/ruby fastlane/test/release_notes_test.rb`
Expected: 통과 (경로 변경이 릴리스 노트 로직에 영향 없음).

- [ ] **Step 5: 커밋**

```bash
git add -A
git commit -m "build: 구 Mac·iPhone 코드를 제거하고 Apple 공통 스크립트와 CI로 교체

루트 SwiftPM 실행 파일과 iOS 전용 프로젝트를 지우고, 모듈 의존성 검사·
포맷 검사·세 플랫폼 테스트를 한 스크립트로 묶는다. 배포 태그는
apple-v* 접두사로 바꿔 이후 android-v*·windows-v*와 나란히 둔다.

BREAKING CHANGE: ios-v* 태그는 더 이상 배포를 트리거하지 않는다.
scripts/release.sh apple X.Y.Z 로 apple-vX.Y.Z 태그를 만들어 푸시한다.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

커밋 제목에 `build!:`를 쓴다 (호환성 변경 표기).

---

### Task 13: 문서, 레시피 스키마, 모듈 캔버스, 자리 표시자

**Files:**
- Create: `shared/recipe-schema/edit-recipe.v2.schema.json`
- Create: `shared/recipe-schema/session-file.v2.schema.json`
- Create: `shared/recipe-schema/README.md`
- Create: `docs/architecture/modules.md`
- Create: `android/README.md`, `windows/README.md`
- Modify: `README.md` (전면 개정), `docs/IOS.md` → `docs/APPLE.md`로 이름 변경 후 개정, `docs/MAC_INSTALL.md`, `docs/IOS_RELEASE.md`(경로·태그), `docs/APP_STORE_SUBMISSION.md`(경로), `VALIDATION.md`(새 절 추가는 Task 14)
- Test: `apple/Tests/MellowSharedTests/RecipeSchemaTests.swift`

**Interfaces:**
- Consumes: Task 1의 `EditRecipe`, Task 3의 `SessionFile` 키 이름.
- Produces: 문서. Android·Windows 작업이 읽는 계약.

- [ ] **Step 1: 스키마 테스트 작성**

`apple/Tests/MellowSharedTests/RecipeSchemaTests.swift`:

```swift
import XCTest
@testable import MellowShared

/// JSON Schema 검증기 없이, 스키마가 선언한 속성과 실제 인코드 키가 같은지 확인한다.
final class RecipeSchemaTests: XCTestCase {
    private func schema(named name: String) throws -> [String: Any] {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("shared/recipe-schema/\(name).json")
        return try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
    }

    func testRecipeSchemaPropertiesMatchEncodedKeys() throws {
        let schema = try schema(named: "edit-recipe.v2.schema")
        let properties = try XCTUnwrap(schema["properties"] as? [String: Any])
        var recipe = EditRecipe()
        recipe.operations = [.spot(RetouchSpot(x: 0, y: 0, sourceX: 0, sourceY: 0, radius: 0.1))]
        let encoded = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(recipe)) as? [String: Any])
        XCTAssertEqual(Set(properties.keys), Set(encoded.keys))
        let schemaColor = try XCTUnwrap((properties["color"] as? [String: Any])?["properties"] as? [String: Any])
        let encodedColor = try XCTUnwrap(encoded["color"] as? [String: Any])
        XCTAssertEqual(Set(schemaColor.keys), Set(encodedColor.keys))
        XCTAssertEqual(schema["$id"] as? String, "https://mellow.photo/schema/edit-recipe.v2.json")
    }
}
```

- [ ] **Step 2: 스키마 작성**

`shared/recipe-schema/edit-recipe.v2.schema.json`:

```json
{
  "$schema": "https://json-schema.org/draft/2020-12/schema",
  "$id": "https://mellow.photo/schema/edit-recipe.v2.json",
  "title": "Mellow Photo EditRecipe v2",
  "description": "사진 한 장의 보정 레시피. 좌표는 방향 보정된 이미지 기준 정규화(0~1), 원점은 왼쪽 아래. 모든 플랫폼 구현이 같은 파일을 읽고 쓴다.",
  "type": "object",
  "additionalProperties": false,
  "required": ["schemaVersion"],
  "properties": {
    "schemaVersion": { "const": 2 },
    "color": {
      "type": "object",
      "additionalProperties": false,
      "properties": {
        "exposure": { "type": "number", "default": 0, "minimum": -3, "maximum": 3 },
        "contrast": { "type": "number", "default": 1, "minimum": 0, "maximum": 2 },
        "saturation": { "type": "number", "default": 1, "minimum": 0, "maximum": 2 },
        "warmth": { "type": "number", "default": 0, "minimum": -1, "maximum": 1 }
      }
    },
    "portrait": {
      "type": "object",
      "additionalProperties": false,
      "properties": {
        "skinSmoothing": { "type": "number", "default": 0, "minimum": 0, "maximum": 1 },
        "faceSlim": { "type": "number", "default": 0, "minimum": 0, "maximum": 1 },
        "targetFace": { "type": ["integer", "null"], "default": null, "description": "왼쪽부터 센 얼굴 인덱스. null이면 모든 얼굴." }
      }
    },
    "operations": {
      "type": "array",
      "description": "사용자가 기록한 순서대로 재생한다.",
      "items": {
        "oneOf": [
          {
            "type": "object", "additionalProperties": false,
            "required": ["type", "x", "y", "sourceX", "sourceY", "radius"],
            "properties": {
              "type": { "const": "spot" },
              "x": { "type": "number" }, "y": { "type": "number" },
              "sourceX": { "type": "number" }, "sourceY": { "type": "number" },
              "radius": { "type": "number", "exclusiveMinimum": 0 }
            }
          },
          {
            "type": "object", "additionalProperties": false,
            "required": ["type", "x", "y", "dx", "dy", "radius"],
            "properties": {
              "type": { "const": "warp" },
              "x": { "type": "number" }, "y": { "type": "number" },
              "dx": { "type": "number" }, "dy": { "type": "number" },
              "radius": { "type": "number", "exclusiveMinimum": 0 }
            }
          }
        ]
      }
    }
  }
}
```

`shared/recipe-schema/session-file.v2.schema.json`:

```json
{
  "$schema": "https://json-schema.org/draft/2020-12/schema",
  "$id": "https://mellow.photo/schema/session-file.v2.json",
  "title": "Mellow Photo SessionFile v2",
  "type": "object",
  "additionalProperties": false,
  "required": ["schemaVersion", "photos", "presets"],
  "properties": {
    "schemaVersion": { "const": 2 },
    "selectedPhotoID": { "type": ["string", "null"], "format": "uuid" },
    "photos": {
      "type": "array",
      "items": {
        "type": "object", "additionalProperties": false,
        "required": ["id", "filename", "displayName", "recipe", "undo", "redo"],
        "properties": {
          "id": { "type": "string", "format": "uuid" },
          "filename": { "type": "string", "description": "작업 사본 파일 이름. 폴더는 플랫폼이 정한다." },
          "displayName": { "type": "string" },
          "recipe": { "$ref": "edit-recipe.v2.schema.json" },
          "undo": { "type": "array", "items": { "$ref": "edit-recipe.v2.schema.json" }, "maxItems": 40 },
          "redo": { "type": "array", "items": { "$ref": "edit-recipe.v2.schema.json" } }
        }
      }
    },
    "presets": {
      "type": "array",
      "items": {
        "type": "object", "additionalProperties": false,
        "required": ["id", "name", "values"],
        "properties": {
          "id": { "type": "string", "format": "uuid" },
          "name": { "type": "string", "maxLength": 30 },
          "values": {
            "type": "object", "additionalProperties": false,
            "required": ["color", "portrait"],
            "properties": {
              "color": { "$ref": "edit-recipe.v2.schema.json#/properties/color" },
              "portrait": { "$ref": "edit-recipe.v2.schema.json#/properties/portrait" }
            }
          }
        }
      }
    }
  }
}
```

`shared/recipe-schema/README.md`에는 두 스키마의 역할, v1(출시본 iPhone)의 모양과 평탄 배열 주의, 후속 B~F가 키를 추가할 때 규칙(기본값 필수, 키 삭제 금지, `schemaVersion`은 호환 깨질 때만 올림)을 적는다. `shared/fixtures/session-v1.json`을 v1 예시로 가리킨다.

- [ ] **Step 3: 모듈 캔버스**

`docs/architecture/modules.md`는 스펙 3절의 다이어그램·의존성 표를 옮긴 뒤 모듈마다 다음 캔버스를 둔다 (다섯 모듈 전부):

```markdown
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
```

끝에 "검증: `scripts/verify-modules.sh`가 이 문서의 의존성 표와 소스의 import를 대조한다"를 적고, 앱 타깃의 `Application/`(유스케이스 2개와 AppModel)과 `Platform/`(어댑터) 역할을 설명한다.

- [ ] **Step 4: README와 안내 문서**

`README.md`는 다음 구조로 다시 쓴다: 한 줄 소개 → 저장소 구조(`apple/ android/ windows/ shared/`) → 실행(`scripts/build-apple.sh mac` 후 `open apple/build/Build/Products/Release/Mellow\ Photo.app`, Xcode에서는 `apple/MellowPhoto.xcodeproj`) → 첫 보정(기존 6단계, 키보드 단축키) → 구현된 범위와 한계(기존 내용, "Mac도 편집 기록을 복원" 추가) → 검증(`scripts/test-apple.sh`) → 아키텍처(`docs/architecture/modules.md` 링크, 로드맵 B~F 한 줄씩) → 배포(`scripts/release.sh apple X.Y.Z`).

`docs/IOS.md`를 `git mv docs/IOS.md docs/APPLE.md`로 옮기고 iPhone·iPad·Mac 공통 안내로 고친다. `docs/MAC_INSTALL.md`의 빌드 명령을 `scripts/package-mac.sh`로, `docs/IOS_RELEASE.md`의 태그를 `apple-v*`와 `scripts/release.sh`로, 워크플로 이름을 `apple-release.yml`로 바꾼다.

`android/README.md`:

```markdown
# Android (예정)

Kotlin 네이티브 앱. 아직 코드가 없다. 시작할 때 지킬 것:

- 모듈은 `docs/architecture/modules.md`의 다섯 모듈과 1:1 (`:shared`, `:editing`, `:library`, `:rendering`, `:export`).
- 레시피·세션 파일은 `shared/recipe-schema/`의 스키마를 그대로 읽고 쓴다. `shared/fixtures/`로 호환을 테스트한다.
- 편집 규칙은 `apple/Sources/MellowEditing/API/EditDocument.swift`가 기준 구현이다. 테스트 케이스 이름을 맞춘다.
- 배포 태그는 `android-vX.Y.Z` (`scripts/release.sh android X.Y.Z`).
```

`windows/README.md`도 같은 형식으로 C/C++ 기준(`mellow_shared` 등 CMake 타깃, 태그 `windows-v*`).

- [ ] **Step 5: 확인과 커밋**

Run: `cd apple && swift test --filter RecipeSchemaTests && cd .. && ./scripts/verify-modules.sh && grep -rn "iOS/MellowPhoto\|build-ios.sh\|scripts/test.sh\|ios-v" README.md docs fastlane .github | grep -v superpowers`
Expected: 테스트 통과, 모듈 검사 통과, grep 결과 없음.

```bash
git add shared docs README.md android windows apple/Tests/MellowSharedTests/RecipeSchemaTests.swift
git commit -m "docs: 모듈 캔버스, 레시피 스키마, 플랫폼 자리 표시자 추가

Android·Windows 구현이 같은 모듈 경계와 파일 포맷을 따르도록 계약을
문서와 스키마로 고정하고, 안내 문서를 새 저장소 구조에 맞춘다.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 14: 실기동 검증과 기록

**Files:**
- Modify: `VALIDATION.md` (새 절 추가)

**Interfaces:**
- Consumes: 전체.
- Produces: 검증 기록.

- [ ] **Step 1: 자동 검증 전체 실행**

Run: `./scripts/test-apple.sh 2>&1 | tail -15 && ./scripts/build-apple.sh ios-device && ./scripts/build-apple.sh mac`
Expected: 전부 성공. 실패하면 고친 뒤 다시 돈다. 테스트 수를 기록한다.

- [ ] **Step 2: 출시본 v1 세션 복원 실기동 (iPhone 시뮬레이터)**

```bash
source scripts/env.sh
SIM="$(mellow_first_simulator iPhone)"
xcrun simctl boot "$SIM" 2>/dev/null || true
xcodebuild "${MELLOW_PROJECT[@]}" -destination "platform=iOS Simulator,id=$SIM" build -quiet
APP="$MELLOW_ROOT/apple/build/Build/Products/Debug-iphonesimulator/Mellow Photo.app"
xcrun simctl install "$SIM" "$APP"
xcrun simctl launch "$SIM" com.mj.mellowphoto && sleep 2 && xcrun simctl terminate "$SIM" com.mj.mellowphoto
CONTAINER="$(xcrun simctl get_app_container "$SIM" com.mj.mellowphoto data)"
ROOT="$CONTAINER/Library/Application Support/MellowPhoto"
mkdir -p "$ROOT"
# 출시본 레이아웃: session.json과 사본이 MellowPhoto/ 바로 아래
cp shared/fixtures/session-v1.json "$ROOT/session.json"
cp shared/fixtures/demo-portrait.png "$ROOT/11111111-1111-1111-1111-111111111111.heic"
cp shared/fixtures/demo-portrait.png "$ROOT/22222222-2222-2222-2222-222222222222.jpg"
xcrun simctl launch "$SIM" com.mj.mellowphoto
```

(확장자와 내용이 달라도 ImageIO는 내용으로 판별하므로 PNG 사본이 열린다.)

확인 항목: 사진 2장 복원, 첫 사진 선택, 노출 0.4·피부 0.3 반영된 미리보기, 실행 취소 가능(2단계), 두 번째 사진 따뜻함 -0.1, 프리셋 "포근한" 목록 노출, 얼굴 1명 감지. `xcrun simctl io "$SIM" screenshot /tmp/v1-restore.png`로 캡처한다. 종료 후 `session.json`이 `"schemaVersion":2`로 다시 쓰였는지 `grep -c schemaVersion "$ROOT/session.json"`으로 확인한다.

- [ ] **Step 3: 세 플랫폼 수동 흐름**

iPhone 시뮬레이터, iPad 시뮬레이터, Mac 각각에서: 파일에서 `shared/fixtures/demo-portrait.png` 가져오기 → 얼굴 1명 → 노출 슬라이더 → 실행 취소·다시 실행 → 잡티 샘플 탭 + 잡티 탭 → 얼굴 미세 조정 슬라이더 비활성 확인 → 원본 비교 → 저장(iOS는 사진 앱 권한 허용, Mac은 폴더) → 앱 종료 후 재실행에서 복원. iPad는 가로에서 3단 레이아웃, iPhone은 세로 스택을 확인한다.

- [ ] **Step 4: 기록과 커밋**

`VALIDATION.md` 끝에 "## 구조 리팩토링 A (2026-MM-DD)" 절을 추가하고 다음을 적는다: 테스트 수(모듈별·앱별), 세 플랫폼 실기동 결과, v1 세션 복원 결과, Mac 샌드박스 상태, 미검증 항목(실기기, 48MP, HDR). 사실만 적고 하지 않은 검증을 통과로 쓰지 않는다.

```bash
git add VALIDATION.md
git commit -m "docs: 구조 리팩토링 후 세 플랫폼 실기동과 v1 세션 복원 검증 기록

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

## 자체 검토 결과

- **스펙 대조:** 2절 배치 → Task 1·8·12·13. 3절 모듈·의존성 → Task 1~7·12(verify-modules). 4절 데이터 모델 → Task 1·3·13. 5절 파이프라인 → Task 5·6. 6절 앱 구성 → Task 9·10·11. 7절 오류 → Task 1(MellowError)·9(UserMessage). 8절 테스트 → 각 Task. 9절 빌드·CI → Task 8·12. 10절 코드 규칙 → Task 1(.swift-format)·12(lint). 11절 이행 순서 → Task 순서 동일. 12절 위험 → Task 8 Step 4(샌드박스), Task 6(LRU), Task 12(XcodeGen CI).
- **스펙과 다르게 정한 점 (의도적):** `SessionStore` 포트는 DTO(`SessionFile`)가 아니라 도메인 `SessionSnapshot`을 주고받는다. DTO를 모듈 내부에 가두는 편이 Clean의 영속 분리 의도에 더 맞다. `PreparedPhoto`에 `pixelSize`를 넣고 미리보기 원본 CGImage는 `pipeline.preview(id, recipe: EditRecipe())`로 얻는다. 출시본 사본 위치(`MellowPhoto/` 바로 아래) 호환을 위해 `WorkingCopyStore.url(for:)`가 구 경로를 조회한다 (Task 10에서 Task 4를 보완).
- **타입 일관성:** `EditDocument.set(_:) -> Rejection?`, `ProjectSession.edit(_:_:)`의 클로저 반환형, `PhotoPipeline.prepare/preview/renderOriginal`, `ExportDestination.publish(fileURL:suggestedName:)`, `StagedPhoto(url:displayName:)`, `ImportReport.added[].prepared`를 Task 간 동일하게 사용했다. `AppModel`의 `selectionTask`·`exportTask`는 extension에서 접근하므로 `private`이 아닌 internal로 둔다고 Task 9에 명시했다.
- **Review Focus 매핑:** 1→Task 3, 2→Task 3, 3→Task 9(ImportPhotosTests), 4→Task 6, 5→Task 9(ExportPhotosTests). 모두 테스트 코드가 있다.
