# 인물 보정 H1 레시피(층·사람 기록·해석·짝짓기) 구현 계획

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** MellowShared에 사람별·성별 그룹 보정의 값 모델을 더한다. 성긴 층(`PortraitLayer`), 사람 기록(`PersonRecord`), 레시피의 `people`, 프리셋의 그룹 층, 층 해석(`PortraitResolver`), 사람 짝짓기(`PersonMatcher`)까지다. 이 계획은 **더하기만** 한다. 렌더·편집·앱 동작과 `targetFace`는 바뀌지 않는다.

**Architecture:** `recipe.portrait`·`recipe.makeup`은 그대로 전체 층이고, 새 최상위 `people`이 성별 그룹 층 둘과 개인 기록 목록을 가진다. 층은 전체 층과 같은 중첩 모양의 성긴 JSON이며 있는 키만 덮어쓴다. 해석과 짝짓기는 순수 값 계산이라 MellowShared에 두어 Rendering·Editing·앱이 같은 함수를 쓴다. `schemaVersion`은 2 유지, 키 추가만.

**Tech Stack:** Swift 5.9 tools / Swift 5 언어 모드, Foundation Codable(직접 구현), XCTest.

**Spec:** `docs/superpowers/specs/2026-10-21-beauty-h-per-person-design.md` (H1에 해당하는 절: 1.1, 1.2, 1.3, 2의 레시피·해석·짝짓기 행, 5). 선행: G4-1과 H3 Task 1 머지(main `74fb2df` 이후). G4 개정은 아래 절.

## 사람이 확인할 것

### G4 개정 (2026-10-21)

[G4 스펙](../specs/2026-10-21-beauty-g4-one-touch-design.md) 5절에 따라 이 계획의 제약을 고쳤다. 결정은 바뀌지 않았다.

- 기준 코드: main `74fb2df`(1.3.0 (8.1) TestFlight, G 머지됨). 브랜치 `beauty-g4`(worktree를 쓰면 `.claude/worktrees/beauty-g4`). `beauty-g-evoto`·`.claude/worktrees/beauty-g`는 더 쓰지 않는다.
- **iOS 시뮬레이터 테스트는 로컬에서 돌리지 않는다**(SpringBoard 오류 창이 사용자를 방해함). `MELLOW_IOS_TESTS`를 켜지 않는다. `./scripts/test-apple.sh`는 로컬에서 iOS를 건너뛰며 iOS 검증은 CI(사용자가 요금 한도를 푼 뒤)다.
- 실행 순서: G4-1 → H3 Task 1(생성 사진) → H1 → H2 → G4-2 → H3 Task 2·3 → G4-3 → H3 Task 4 → (승인 시) H4.
- G4-2가 뒤에 `PortraitLayer.oneTouch`(표시 키)를 더한다. H1은 더하지 않는다(더하기만 규칙 유지).

- **순서.** Task 1 층 값 타입 → 2 사람 기록·레시피·프리셋·스키마 → 3 층 해석 → 4 사람 짝짓기. 4개 Task, Task마다 Opus 구현 → 리뷰 → 수정, 끝에 전체 리뷰.
- **외부 효과가 있는 단계.** 없음. 푸시·태그·TestFlight는 H 범위 밖(스펙 "돈·시간·외부 효과가 있는 단계").
- **스펙이 정하지 않아 이 계획이 정한 것.**

| 결정 | 이유 | 바꾸면 비용 |
|---|---|---|
| 층의 딕셔너리(`[SkinRefinementKey: Double]` 등)는 Codable을 직접 구현해 enum `rawValue`를 JSON 키로 쓴다 | Swift 기본 `[Enum: T]` 인코딩은 `[키, 값, 키, 값]` 배열이라 다른 플랫폼이 읽기 어렵고 스키마 `properties`와 맞지 않음(v1 `undoHistory`의 교훈) | 작음 |
| `EditRecipe`는 `people` 키를 항상 쓰고(`{}` 포함), `PeopleAdjustments`는 비어 있는 `groups`·`individuals` 키를 생략한다. 층은 비어 있는 그룹 객체(`skin`·`face`·`features`·`makeup`)를 쓰지 않는다 | 스키마 키 집합 테스트가 최상위 키를 비교하므로 레시피 수준은 늘 있어야 하고, 안쪽은 "없음 = 상속"이라 빈 객체가 뜻을 흐림 | 작음 |
| `PersonID.legacy(index:)`는 `B0000000-0000-0000-0000-` 뒤 12자리 인덱스인 고정 UUID | 이행 id가 디코드마다 달라지면 실행 취소 기록과 현재 레시피의 `==`가 깨져 불필요한 체크포인트가 생김(스펙 1.2). H2가 쓰지만 타입은 여기서 정의 | 작음 |
| `PortraitScope`는 MellowShared에 둔다(스펙 1.3의 수정 내용) | Rendering·Editing·앱이 함께 쓰는 값 타입이고 Rendering은 Editing을 import할 수 없음 | 작음 |
| 짝짓기 동률은 (거리, 사람 배열 순서, 얼굴 인덱스) 순이고, anchor 없는 legacy 기록의 후보 거리는 허용치(0.5)로 친다 | 결정적이어야 테스트와 플랫폼 간 결과가 같고, 실제 anchor가 legacy 추정보다 먼저 얼굴을 가져가야 함 | 작음 |
| 0으로 덮어쓴 키는 `overriddenKeys`에는 들지만 `hasEffect`에는 들지 않는다 | "상속을 끊고 0으로" 둔 사람은 화면에 덮어씀 표시가 필요하지만 렌더는 바뀌지 않으므로 얼굴 분석 요구(`dependsOnFaces`)를 일으키지 않아야 함 | 작음 |
| `PresetValues`는 `people.groups`만 담고 파일에 `individuals`가 와도 버린다 | 스펙 1.2. 다른 플랫폼이나 손으로 고친 파일이 개인 층을 끼워 넣어도 프리셋 적용이 특정 사람을 만들지 않음 | 작음 |

- **범위 밖(다른 계획).** `targetFace` 읽기 이행·제거, 렌더·편집이 `people`을 읽는 것(H2), 화면·생성 사진·VALIDATION(H3), 자동 추정(H4).
- **위험.** 없음에 가깝다. 이 계획이 끝나도 앱 동작은 그대로이고 `people`은 아무도 읽지 않는다. 세션 파일에 `"people":{}`가 더 쓰일 뿐이다.
- **사용자 조치.** 없음.

---

## 에이전트 참조

## Global Constraints

- 작업 위치: main `74fb2df` 이후에서 분기한 브랜치 `beauty-g4`(worktree를 쓰면 `/Users/mj/IdeaProjects/mellow-photo/.claude/worktrees/beauty-g4`, 부모 저장소로 `cd`하지 않는다). `PhotoPickerButton.swift`·`project.yml`·`scripts/test-apple.sh`·UI 테스트 타깃은 건드리지 않는다. 모든 Swift·xcodebuild 명령 전에 `export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`.
- 시작 조건: G4-1·H3 Task 1이 머지된 상태(`SkinRefinementKey` 7종, `BodySkinAdjustments`, `EffectAdjustments`, `SyncCategory`, `applyFromBatch(_:categories:)`, `DisplayScale`·`RealPortrait`, `PeopleFixtures`가 있다). 시작 전에 `git log --oneline -5`와 `cd apple && swift test`로 확인한다.
- 모듈 의존성 표(`docs/architecture/modules.md`)와 `scripts/verify-modules.sh`는 바뀌지 않는다. 이 계획은 MellowShared 소스, `shared/recipe-schema/` 두 스키마와 README, MellowShared·MellowLibrary 테스트만 고친다. MellowShared는 Foundation·CoreGraphics만 import한다.
- 레시피 `schemaVersion`은 2 유지, 키 추가만. `targetFace`의 읽기·쓰기·의미는 이 계획에서 바꾸지 않는다(H2 Task 5). 렌더·편집 코드는 이 계획에서 한 줄도 바꾸지 않는다.
- 새 파일: `apple/Sources/MellowShared/API/PeopleAdjustments.swift`(Task 1·2), `PortraitResolver.swift`(Task 3), `PersonMatcher.swift`(Task 4). 새 테스트 파일: `apple/Tests/MellowSharedTests/PortraitLayerTests.swift`, `PortraitResolverTests.swift`, `PersonMatcherTests.swift`. 패키지 테스트는 폴더 전체가 타깃이라 `Package.swift`를 고치지 않는다.
- 매직 넘버는 명명 상수: 짝짓기 허용치는 `PersonMatching`, legacy id 접두사는 `PersonID` 안 `private static let`.
- 한 줄 한 문장, 세미콜론 금지. 한국어 사용자 문구 없음(모듈). `MellowError` 새 case 없음.
- `cd apple && swift format lint --strict --recursive Sources Tests MellowPhoto MellowPhotoTests` 출력 없음(한도 120자). 새 빌드 경고 없음.
- `./scripts/verify-modules.sh` 통과. 패키지 테스트: `cd apple && swift test`(모듈마다 `Executed N tests`). 이 계획은 앱 파일을 건드리지 않으므로 Mac 앱 테스트는 Task 4 끝에 한 번만 돌려 회귀가 없음을 확인한다(`xcodebuild -project apple/MellowPhoto.xcodeproj -scheme MellowPhoto -derivedDataPath apple/build -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO test 2>&1 | grep -E "Executed|TEST (SUCCEEDED|FAILED)|error:"`).
- iOS 시뮬레이터 테스트는 로컬에서 돌리지 않는다(CI만, `MELLOW_IOS_TESTS` 금지). Xcode를 열거나 앱·시뮬레이터를 띄우지 않는다. 푸시·태그·`scripts/release.sh` 금지.
- 커밋: 한국어 Conventional Commits, 마지막 줄 `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`. `git add`는 Task에 나열한 경로만. 다른 에이전트가 같은 worktree에서 커밋할 수 있으므로 `git add -A`·`git commit -a`를 쓰지 않는다.
- 기준 테스트 수: **시작 전에 `swift test`와 Mac 앱 테스트로 실측해 이 줄에 적는다**(G 계획의 목표값과 실제가 이미 다르다 — G1 끝 Rendering 246·Mac 72, G2 Task 4 뒤 Rendering 256). 이 계획이 더하는 수는 **Shared +9, Library +1**(Task 1 +2, Task 2 +3·Library +1, Task 3 +2, Task 4 +2)이고 다른 모듈·앱은 0이다. 아래 Task의 "Executed N tests"는 G3 계획 목표값(Shared 49 · Rendering 257 · Library 31 · Export 4 · Editing 36, 앱 Mac 78)을 기준으로 적은 명목치이므로 실측 기준값에 같은 증분을 더해 읽는다.

## Review Focus

스펙이 암시하지만 스펙의 테스트 표가 직접 다루지 않는 입력. 각 줄의 테스트를 소유 Task에 넣었다.

1. **G까지 저장한 세션(`people` 없음)을 연다.** `people`은 비어 있고 `dependsOnFaces`·`isDefault`가 그대로여야 한다. → Task 2 `testPeopleRoundTripAndDefaultToEmpty`.
2. **층에서 메이크업 색만 "없음"으로 덮어쓴다(`"colorID": null`).** 상속이 아니라 "색 없음"으로 읽혀야 한다. → Task 1 `testLayerEncodesOnlyOverriddenKeysAndRoundTrips`.
3. **키를 0으로 덮어쓴 사람만 있는 레시피.** `overriddenKeys`에는 있고 `hasEffect`·`dependsOnFaces`는 false여야 한다. → Task 1 `testLayerAppliesRemovesAndDiffs`, Task 2 `testPeopleRoundTripAndDefaultToEmpty`.
4. **프리셋 파일에 `individuals`가 들어 있다.** 읽을 때 버려야 한다. → Task 2 `testPeopleScalarsAreCheckedForFinitenessAndPresetsCarryGroupsOnly`.
5. **성별을 모르는 사람.** 그룹 층을 건너뛰고 전체 ⊕ 개인만 적용해야 한다. → Task 3 `testLayersOverlayKeyByKeyAndUndeterminedGenderSkipsGroups`.
6. **기록 둘이 한 얼굴을 다툰다.** 가까운 쪽 하나만 짝이 되고 결과가 결정적이어야 한다. → Task 4 `testMatchingIsOneToOneDeterministicAndFallsBackToLegacyIndex`.

## 인터페이스 요약 (모든 Task가 공유하는 이름)

```swift
// MellowShared/API/PeopleAdjustments.swift (Task 1)
public enum Gender: String, CaseIterable, Codable, Sendable { male, female }
public struct PersonID: Hashable, Codable, Sendable { rawValue: UUID; init(); init(rawValue:); static func legacy(index: Int) -> PersonID }
public struct PersonAnchor: Codable, Equatable, Sendable { x, y, width; init(x:y:width:); init(faceBox: NormalizedRect) }
public enum PortraitKey: Hashable, Sendable {
    skinSmoothing, autoBlemish, skinRefinement(SkinRefinementKey), faceShape(FaceShapeKey), feature(FeatureKey), makeupPart(MakeupPart)
    var isFaceShape: Bool; static let skin, faceShape, features, makeup, all: Set<PortraitKey> }
public struct PortraitLayer: Codable, Equatable, Sendable {
    skinSmoothing: Double?, autoBlemish: Bool?, skinRefinement: [SkinRefinementKey: Double], face: [FaceShapeKey: Double],
    features: [FeatureKey: Double], makeup: [MakeupPart: MakeupTint], makeupLookID: String?
    init(모두 기본값); isEmpty; hasEffect; overriddenKeys; numericValues
    func applied(to: inout PortraitAdjustments, makeup: inout MakeupAdjustments); mutating func remove(Set<PortraitKey>)
    static func difference(portrait:makeup:) -> PortraitLayer }

// (Task 2)
public struct PersonRecord: Codable, Equatable, Identifiable, Sendable { id, anchor?, legacyIndex?, gender?, layer; init(id:anchor:legacyIndex:gender:layer:); isEmpty }
public struct PeopleAdjustments: Codable, Equatable, Sendable {
    groups: [Gender: PortraitLayer], individuals: [PersonRecord]; init(groups:individuals:)
    hasEffect; numericValues; func person(_:) -> PersonRecord?; func personID(at:) -> PersonID?; mutating func prune() }
EditRecipe.people, init(…effects:people:operations:), dependsOnFaces·allValuesFinite 포함
PresetValues.people (groups만), init(…effects:people:)

// MellowShared/API/PortraitResolver.swift (Task 3)
public enum PortraitScope: Hashable, Sendable { all, gender(Gender), person(PersonID) }
public enum PortraitResolver {
    struct Resolved { portrait, makeup }
    static func resolve(_ recipe:, person: PersonRecord?, gender: Gender?) -> Resolved
    static func resolve(_ recipe:, scope: PortraitScope, estimate: Gender?) -> Resolved
    static func effectiveGender(person: PersonRecord?, estimate: Gender?) -> Gender?
    static func layer(_ recipe:, scope:) -> PortraitLayer?
    static func overriddenKeys(_ recipe:, scope:) -> Set<PortraitKey> }

// MellowShared/API/PersonMatcher.swift (Task 4)
public enum PersonMatching { static let centerTolerance = 0.5; static let sizeRatioLimit = 2.0 }
public enum PersonMatcher {
    struct Match: Equatable, Sendable { person: PersonID; faceIndex: Int }
    static func match(_ people: [PersonRecord], faces: [NormalizedRect]) -> [Match]
    static func isMatch(_: PersonAnchor, _: PersonAnchor) -> Bool }
```

---

### Task 1: 층 값 타입 — Gender, PersonID, PersonAnchor, PortraitKey, PortraitLayer

**Files:**
- Create: `apple/Sources/MellowShared/API/PeopleAdjustments.swift`
- Test: `apple/Tests/MellowSharedTests/PortraitLayerTests.swift` (새 파일)

**Interfaces:**
- Consumes: `SkinRefinementKey`, `FaceShapeKey`, `FeatureKey`, `MakeupPart`·`MakeupTint`, `PortraitAdjustments`, `MakeupAdjustments`(`setColorID`·`setIntensity`·`colorID(of:)`·`intensity(of:)`), `NormalizedRect`.
- Produces: 인터페이스 요약의 Task 1 항목.

설계 근거: 스펙 1.2·1.3. 층은 "있는 키만 덮어씀"이라 모든 잎이 선택이다. 메이크업은 부위 단위(색+강도)로 덮어쓴다.

- [ ] **Step 1: 실패하는 테스트 작성**

`apple/Tests/MellowSharedTests/PortraitLayerTests.swift`:

```swift
import XCTest

@testable import MellowShared

final class PortraitLayerTests: XCTestCase {
    func testLayerEncodesOnlyOverriddenKeysAndRoundTrips() throws {
        var layer = PortraitLayer()
        XCTAssertTrue(layer.isEmpty)
        XCTAssertFalse(layer.hasEffect)
        layer.skinSmoothing = 0.6
        layer.skinRefinement[.darkCircles] = 0.3
        layer.face[.width] = -0.3
        layer.makeup[.lip] = MakeupTint(colorID: "lip-rose", intensity: 0.5)
        layer.makeup[.brow] = MakeupTint(intensity: 0.2)
        layer.makeupLookID = "daily"
        XCTAssertEqual(
            layer.overriddenKeys,
            [.skinSmoothing, .skinRefinement(.darkCircles), .faceShape(.width), .makeupPart(.lip), .makeupPart(.brow)])
        XCTAssertTrue(layer.hasEffect)
        let data = try JSONEncoder().encode(layer)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(Set(json.keys), ["skin", "face", "makeup"], "비어 있는 features 그룹은 쓰지 않는다")
        let skin = try XCTUnwrap(json["skin"] as? [String: Any])
        XCTAssertEqual(Set(skin.keys), ["smoothing", "darkCircles"], "덮어쓰지 않은 키는 없다")
        XCTAssertEqual((json["face"] as? [String: Any])?["width"] as? Double, -0.3)
        let makeup = try XCTUnwrap(json["makeup"] as? [String: Any])
        XCTAssertEqual(Set(makeup.keys), ["lookID", "lip", "brow"])
        XCTAssertEqual(try JSONDecoder().decode(PortraitLayer.self, from: data), layer)
        let sparse = #"{"skin":{"autoBlemish":true},"makeup":{"lip":{"colorID":null,"intensity":0.4}}}"#
        let decoded = try JSONDecoder().decode(PortraitLayer.self, from: Data(sparse.utf8))
        XCTAssertEqual(decoded.autoBlemish, true)
        XCTAssertNil(decoded.skinSmoothing)
        XCTAssertEqual(decoded.makeup[.lip], MakeupTint(colorID: nil, intensity: 0.4), "colorID null은 색 없음으로 덮어쓴다")
        XCTAssertEqual(decoded.overriddenKeys, [.autoBlemish, .makeupPart(.lip)])
        XCTAssertEqual(try JSONDecoder().decode(PortraitLayer.self, from: Data("{}".utf8)), PortraitLayer())
    }

    func testLayerAppliesRemovesAndDiffs() {
        var portrait = PortraitAdjustments(
            skin: SkinAdjustments(smoothing: 0.2, autoBlemish: true), face: FaceShapeAdjustments(width: -0.1))
        var makeup = MakeupAdjustments(lookID: "cool", lip: MakeupTint(colorID: "lip-coral", intensity: 0.3))
        var layer = PortraitLayer(
            skinSmoothing: 0.6, face: [.jaw: 0.4],
            makeup: [.lip: MakeupTint(colorID: nil, intensity: 0.5), .contour: MakeupTint(intensity: 0.1)],
            makeupLookID: "daily")
        layer.applied(to: &portrait, makeup: &makeup)
        XCTAssertEqual(portrait.skin.smoothing, 0.6)
        XCTAssertTrue(portrait.skin.autoBlemish, "덮어쓰지 않은 키는 아래 층 값")
        XCTAssertEqual(portrait.face.width, -0.1)
        XCTAssertEqual(portrait.face.jaw, 0.4)
        XCTAssertNil(makeup.lip.colorID)
        XCTAssertEqual(makeup.lip.intensity, 0.5)
        XCTAssertEqual(makeup.contour.intensity, 0.1)
        XCTAssertEqual(makeup.lookID, "daily")
        layer.remove([.faceShape(.jaw), .makeupPart(.lip), .makeupPart(.contour)])
        XCTAssertEqual(layer.overriddenKeys, [.skinSmoothing])
        XCTAssertNil(layer.makeupLookID, "메이크업 키가 모두 빠지면 룩 이름도 지운다")
        var zero = PortraitLayer()
        zero.face[.width] = 0
        XCTAssertFalse(zero.isEmpty)
        XCTAssertFalse(zero.hasEffect, "0으로 덮어쓴 키는 상속을 끊지만 렌더는 바꾸지 않는다")
        let diff = PortraitLayer.difference(
            portrait: PortraitAdjustments(skin: SkinAdjustments(smoothing: 0.3), face: FaceShapeAdjustments(width: -0.2)),
            makeup: MakeupAdjustments(lookID: "rosy", blush: MakeupTint(colorID: "blush-pink", intensity: 0.4)))
        XCTAssertEqual(
            diff,
            PortraitLayer(
                skinSmoothing: 0.3, face: [.width: -0.2],
                makeup: [.blush: MakeupTint(colorID: "blush-pink", intensity: 0.4)], makeupLookID: "rosy"))
        XCTAssertEqual(PortraitLayer.difference(portrait: PortraitAdjustments(), makeup: MakeupAdjustments()), PortraitLayer())
        XCTAssertEqual(PortraitKey.all.count, 2 + 7 + 10 + 3 + 5)
        XCTAssertEqual(PortraitKey.skin.count, 9)
        XCTAssertTrue(PortraitKey.faceShape(.smile).isFaceShape)
        XCTAssertFalse(PortraitKey.feature(.teethWhiten).isFaceShape)
        XCTAssertEqual(PersonID.legacy(index: 1), PersonID.legacy(index: 1))
        XCTAssertNotEqual(PersonID.legacy(index: 1), PersonID.legacy(index: 2))
        XCTAssertEqual(
            PersonAnchor(faceBox: NormalizedRect(x: 0.2, y: 0.4, width: 0.2, height: 0.3)),
            PersonAnchor(x: 0.3, y: 0.55, width: 0.2))
    }
}
```

- [ ] **Step 2: 실패 확인**

Run: `cd apple && swift test --filter PortraitLayerTests`
Expected: 컴파일 실패 (`cannot find 'PortraitLayer' in scope`).

- [ ] **Step 3: 구현**

`apple/Sources/MellowShared/API/PeopleAdjustments.swift`(Task 2가 같은 파일에 `PersonRecord`·`PeopleAdjustments`를 더한다):

```swift
import Foundation

/// 성별 그룹. 레시피 JSON 키와 같다. 지정하지 않은 사람은 nil이다.
public enum Gender: String, CaseIterable, Codable, Sendable {
    case male
    case female
}

/// 레시피 안 사람 기록의 키. 편집이 사람을 가리킬 때 쓴다.
public struct PersonID: Hashable, Codable, Sendable {
    /// 옛 targetFace에서 이행한 기록의 id 접두사. 뒤 12자리가 얼굴 인덱스다.
    private static let legacyPrefix = "B0000000-0000-0000-0000-"

    public let rawValue: UUID

    public init() {
        rawValue = UUID()
    }

    public init(rawValue: UUID) {
        self.rawValue = rawValue
    }

    /// 옛 targetFace 이행용 결정적 id. 같은 파일을 두 번 읽어도 같다.
    public static func legacy(index: Int) -> PersonID {
        let suffix = String(format: "%012d", max(0, index))
        return PersonID(rawValue: UUID(uuidString: legacyPrefix + suffix)!)
    }

    public init(from decoder: Decoder) throws {
        rawValue = try decoder.singleValueContainer().decode(UUID.self)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

/// 사람을 다시 찾는 열쇠. 정규화 얼굴 상자의 중심과 폭(원점 왼쪽 아래, 원본 기준).
public struct PersonAnchor: Codable, Equatable, Sendable {
    public var x: Double
    public var y: Double
    public var width: Double

    public init(x: Double, y: Double, width: Double) {
        self.x = x
        self.y = y
        self.width = width
    }

    public init(faceBox: NormalizedRect) {
        self.init(x: faceBox.midX, y: faceBox.midY, width: faceBox.width)
    }
}

/// 층이 덮어쓸 수 있는 키. 편집·화면·동기화가 같은 이름을 쓴다.
public enum PortraitKey: Hashable, Sendable {
    case skinSmoothing
    case autoBlemish
    case skinRefinement(SkinRefinementKey)
    case faceShape(FaceShapeKey)
    case feature(FeatureKey)
    case makeupPart(MakeupPart)

    public var isFaceShape: Bool {
        if case .faceShape = self {
            return true
        }
        return false
    }

    /// 피부 보정·자동 잡티·정밀 7종.
    public static let skin: Set<PortraitKey> =
        [.skinSmoothing, .autoBlemish] + SkinRefinementKey.allCases.map(PortraitKey.skinRefinement)
    public static let faceShape = Set(FaceShapeKey.allCases.map(PortraitKey.faceShape))
    public static let features = Set(FeatureKey.allCases.map(PortraitKey.feature))
    public static let makeup = Set(MakeupPart.allCases.map(PortraitKey.makeupPart))
    public static let all = skin.union(faceShape).union(features).union(makeup)
}

/// 성긴 층. 있는 키만 아래 층을 덮어쓰고 없는 키는 상속한다. 메이크업은 부위 단위다.
/// JSON은 전체 층과 같은 중첩(skin·face·features·makeup)이되 모든 잎이 선택이다.
public struct PortraitLayer: Codable, Equatable, Sendable {
    public var skinSmoothing: Double?
    public var autoBlemish: Bool?
    public var skinRefinement: [SkinRefinementKey: Double]
    public var face: [FaceShapeKey: Double]
    public var features: [FeatureKey: Double]
    public var makeup: [MakeupPart: MakeupTint]
    /// 이 층에서 마지막으로 적용한 룩. 부위를 바꾸면 지운다(전체 층과 같은 규칙).
    public var makeupLookID: String?

    public init(
        skinSmoothing: Double? = nil, autoBlemish: Bool? = nil, skinRefinement: [SkinRefinementKey: Double] = [:],
        face: [FaceShapeKey: Double] = [:], features: [FeatureKey: Double] = [:],
        makeup: [MakeupPart: MakeupTint] = [:], makeupLookID: String? = nil
    ) {
        self.skinSmoothing = skinSmoothing
        self.autoBlemish = autoBlemish
        self.skinRefinement = skinRefinement
        self.face = face
        self.features = features
        self.makeup = makeup
        self.makeupLookID = makeupLookID
    }

    public var isEmpty: Bool { overriddenKeys.isEmpty && makeupLookID == nil }

    /// 이 층이 덮어쓰는 키. 0으로 덮어쓴 키도 들어간다(상속을 끊음).
    public var overriddenKeys: Set<PortraitKey> {
        var keys = Set<PortraitKey>()
        if skinSmoothing != nil {
            keys.insert(.skinSmoothing)
        }
        if autoBlemish != nil {
            keys.insert(.autoBlemish)
        }
        keys.formUnion(skinRefinement.keys.map(PortraitKey.skinRefinement))
        keys.formUnion(face.keys.map(PortraitKey.faceShape))
        keys.formUnion(features.keys.map(PortraitKey.feature))
        keys.formUnion(makeup.keys.map(PortraitKey.makeupPart))
        return keys
    }

    /// 기본값과 다른 값이 하나라도 있는지. 0으로 덮어쓴 키는 렌더를 바꾸지 않는다.
    public var hasEffect: Bool {
        if let skinSmoothing, skinSmoothing != 0 {
            return true
        }
        if autoBlemish == true {
            return true
        }
        if skinRefinement.values.contains(where: { $0 != 0 }) {
            return true
        }
        if face.values.contains(where: { $0 != 0 }) {
            return true
        }
        if features.values.contains(where: { $0 != 0 }) {
            return true
        }
        return makeup.values.contains { $0.intensity != 0 }
    }

    public var numericValues: [Double] {
        [skinSmoothing ?? 0] + Array(skinRefinement.values) + Array(face.values) + Array(features.values)
            + makeup.values.map(\.intensity)
    }

    /// 이 층의 키로 아래 층 값을 덮어쓴다.
    public func applied(to portrait: inout PortraitAdjustments, makeup target: inout MakeupAdjustments) {
        if let skinSmoothing {
            portrait.skin.smoothing = skinSmoothing
        }
        if let autoBlemish {
            portrait.skin.autoBlemish = autoBlemish
        }
        for (key, value) in skinRefinement {
            portrait.skin[key] = value
        }
        for (key, value) in face {
            portrait.face[key] = value
        }
        for (key, value) in features {
            portrait.features[key] = value
        }
        for (part, tint) in makeup {
            if part.hasColor {
                target.setColorID(tint.colorID, of: part)
            }
            target.setIntensity(tint.intensity, of: part)
        }
        if let makeupLookID {
            target.lookID = makeupLookID
        }
    }

    /// 키를 지워 상속으로 되돌린다. 메이크업 키가 모두 빠지면 룩 이름도 지운다.
    public mutating func remove(_ keys: Set<PortraitKey>) {
        for key in keys {
            switch key {
            case .skinSmoothing: skinSmoothing = nil
            case .autoBlemish: autoBlemish = nil
            case .skinRefinement(let refinement): skinRefinement[refinement] = nil
            case .faceShape(let shape): face[shape] = nil
            case .feature(let feature): features[feature] = nil
            case .makeupPart(let part): makeup[part] = nil
            }
        }
        if makeup.isEmpty {
            makeupLookID = nil
        }
    }

    /// 전체 층 값 중 기본값과 다른 것만 담은 층. 옛 targetFace 이행(H2)에 쓴다.
    public static func difference(portrait: PortraitAdjustments, makeup: MakeupAdjustments) -> PortraitLayer {
        var layer = PortraitLayer()
        if portrait.skin.smoothing != 0 {
            layer.skinSmoothing = portrait.skin.smoothing
        }
        if portrait.skin.autoBlemish {
            layer.autoBlemish = true
        }
        for key in SkinRefinementKey.allCases where portrait.skin[key] != 0 {
            layer.skinRefinement[key] = portrait.skin[key]
        }
        for key in FaceShapeKey.allCases where portrait.face[key] != 0 {
            layer.face[key] = portrait.face[key]
        }
        for key in FeatureKey.allCases where portrait.features[key] != 0 {
            layer.features[key] = portrait.features[key]
        }
        for part in MakeupPart.allCases {
            let colorID = part.hasColor ? makeup.colorID(of: part) : nil
            let tint = MakeupTint(colorID: colorID, intensity: makeup.intensity(of: part))
            if tint != MakeupTint() {
                layer.makeup[part] = tint
            }
        }
        layer.makeupLookID = layer.makeup.isEmpty ? nil : makeup.lookID
        return layer
    }

    // MARK: Codable — enum rawValue를 JSON 키로 쓴다. Swift 기본 [Enum: T] 인코딩은 배열이라 쓰지 않는다.

    private enum CodingKeys: String, CodingKey {
        case skin
        case face
        case features
        case makeup
    }

    private struct RawKey: CodingKey {
        let stringValue: String
        var intValue: Int? { nil }

        init(stringValue: String) {
            self.stringValue = stringValue
        }

        init?(intValue: Int) {
            nil
        }

        init(_ raw: String) {
            stringValue = raw
        }
    }

    private static let smoothingKey = RawKey("smoothing")
    private static let autoBlemishKey = RawKey("autoBlemish")
    private static let lookIDKey = RawKey("lookID")

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        skinRefinement = [:]
        makeup = [:]
        if container.contains(.skin) {
            let skin = try container.nestedContainer(keyedBy: RawKey.self, forKey: .skin)
            skinSmoothing = try skin.decodeIfPresent(Double.self, forKey: Self.smoothingKey)
            autoBlemish = try skin.decodeIfPresent(Bool.self, forKey: Self.autoBlemishKey)
            for key in SkinRefinementKey.allCases {
                skinRefinement[key] = try skin.decodeIfPresent(Double.self, forKey: RawKey(key.rawValue))
            }
        }
        face = try Self.decodeNumbers(FaceShapeKey.self, in: container, forKey: .face)
        features = try Self.decodeNumbers(FeatureKey.self, in: container, forKey: .features)
        if container.contains(.makeup) {
            let parts = try container.nestedContainer(keyedBy: RawKey.self, forKey: .makeup)
            makeupLookID = try parts.decodeIfPresent(String.self, forKey: Self.lookIDKey)
            for part in MakeupPart.allCases {
                makeup[part] = try parts.decodeIfPresent(MakeupTint.self, forKey: RawKey(part.rawValue))
            }
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        if skinSmoothing != nil || autoBlemish != nil || !skinRefinement.isEmpty {
            var skin = container.nestedContainer(keyedBy: RawKey.self, forKey: .skin)
            try skin.encodeIfPresent(skinSmoothing, forKey: Self.smoothingKey)
            try skin.encodeIfPresent(autoBlemish, forKey: Self.autoBlemishKey)
            for key in SkinRefinementKey.allCases {
                try skin.encodeIfPresent(skinRefinement[key], forKey: RawKey(key.rawValue))
            }
        }
        try Self.encodeNumbers(face, in: &container, forKey: .face)
        try Self.encodeNumbers(features, in: &container, forKey: .features)
        if makeupLookID != nil || !makeup.isEmpty {
            var parts = container.nestedContainer(keyedBy: RawKey.self, forKey: .makeup)
            try parts.encodeIfPresent(makeupLookID, forKey: Self.lookIDKey)
            for part in MakeupPart.allCases {
                try parts.encodeIfPresent(makeup[part], forKey: RawKey(part.rawValue))
            }
        }
    }

    private static func decodeNumbers<Key: RawRepresentable & CaseIterable & Hashable>(
        _: Key.Type, in container: KeyedDecodingContainer<CodingKeys>, forKey key: CodingKeys
    ) throws -> [Key: Double] where Key.RawValue == String {
        guard container.contains(key) else { return [:] }
        let nested = try container.nestedContainer(keyedBy: RawKey.self, forKey: key)
        var values: [Key: Double] = [:]
        for item in Key.allCases {
            values[item] = try nested.decodeIfPresent(Double.self, forKey: RawKey(item.rawValue))
        }
        return values
    }

    private static func encodeNumbers<Key: RawRepresentable & CaseIterable & Hashable>(
        _ values: [Key: Double], in container: inout KeyedEncodingContainer<CodingKeys>, forKey key: CodingKeys
    ) throws where Key.RawValue == String {
        guard !values.isEmpty else { return }
        var nested = container.nestedContainer(keyedBy: RawKey.self, forKey: key)
        for item in Key.allCases {
            try nested.encodeIfPresent(values[item], forKey: RawKey(item.rawValue))
        }
    }
}
```

`MakeupTint` 인코드는 합성 Codable이라 `colorID`가 nil이면 키를 생략한다(README "생략과 null은 같은 뜻"). 디코드는 기존 `decodeIfPresent`라 `null`도 nil로 읽는다.

- [ ] **Step 4: 통과 확인**

Run: `cd apple && swift test --filter MellowSharedTests` → `Executed 51 tests, with 0 failures`. lint 출력 없음.

- [ ] **Step 5: 커밋**

```bash
git add apple/Sources/MellowShared/API/PeopleAdjustments.swift apple/Tests/MellowSharedTests/PortraitLayerTests.swift
git commit -m "feat(shared): 사람별 보정의 성긴 층 PortraitLayer와 Gender·PersonID·PersonAnchor·PortraitKey

있는 키만 아래 층을 덮어쓴다. 메이크업은 부위 단위. 딕셔너리 키는 enum rawValue로 직접 인코드.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 2: 사람 기록과 레시피 — PersonRecord, PeopleAdjustments, EditRecipe.people, PresetValues.people, 스키마

**Files:**
- Modify: `apple/Sources/MellowShared/API/PeopleAdjustments.swift` (타입 2개 추가)
- Modify: `apple/Sources/MellowShared/API/EditRecipe.swift`, `apple/Sources/MellowShared/API/Preset.swift`
- Modify: `shared/recipe-schema/edit-recipe.v2.schema.json`, `shared/recipe-schema/session-file.v2.schema.json`, `shared/recipe-schema/README.md`
- Test: `apple/Tests/MellowSharedTests/EditRecipeCodingTests.swift`, `apple/Tests/MellowSharedTests/RecipeSchemaTests.swift`, `apple/Tests/MellowLibraryTests/SessionFileMigrationTests.swift`

**Interfaces:**
- Consumes: Task 1 타입, `PersonMatcher.isMatch`는 아직 없으므로 `personID(at:)`는 Task 4에서 짝짓기 함수로 바꾸고 여기서는 같은 식을 `PersonAnchor` 확장 `private func isNear(_:)`로 둔다(Task 4가 지운다).
- Produces: 인터페이스 요약의 Task 2 항목.

설계 근거: 스펙 1.2. `people`은 최상위(층이 `portrait`와 `makeup`을 함께 덮으므로). 프리셋은 그룹만.

- [ ] **Step 1: 실패하는 테스트 작성**

`EditRecipeCodingTests.swift` 끝에 추가:

```swift
    func testPeopleRoundTripAndDefaultToEmpty() throws {
        let legacy = #"{"schemaVersion":2,"portrait":{"skin":{"smoothing":0.4}}}"#
        let decoded = try JSONDecoder().decode(EditRecipe.self, from: Data(legacy.utf8))
        XCTAssertEqual(decoded.people, PeopleAdjustments())
        XCTAssertFalse(decoded.people.hasEffect)
        XCTAssertTrue(decoded.dependsOnFaces, "전체 층의 피부 값은 그대로 얼굴이 필요하다")
        var recipe = EditRecipe()
        let anchor = PersonAnchor(x: 0.3, y: 0.6, width: 0.12)
        let id = PersonID()
        recipe.people.groups[.female] = PortraitLayer(skinSmoothing: 0.5)
        recipe.people.individuals = [
            PersonRecord(id: id, anchor: anchor, gender: .female, layer: PortraitLayer(face: [.width: -0.3]))
        ]
        XCTAssertTrue(recipe.people.hasEffect)
        XCTAssertTrue(recipe.dependsOnFaces, "층 값만 있어도 얼굴이 필요하다")
        XCTAssertFalse(recipe.isDefault)
        let data = try JSONEncoder().encode(recipe)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let people = try XCTUnwrap(json["people"] as? [String: Any])
        XCTAssertEqual(Set(people.keys), ["groups", "individuals"])
        XCTAssertEqual(Set((people["groups"] as? [String: Any])?.keys ?? []), ["female"], "비어 있는 male 그룹은 쓰지 않는다")
        let record = try XCTUnwrap((people["individuals"] as? [[String: Any]])?.first)
        XCTAssertEqual(Set(record.keys), ["id", "anchor", "gender", "layer"], "legacyIndex가 없으면 키도 없다")
        XCTAssertEqual(record["gender"] as? String, "female")
        XCTAssertEqual(try JSONDecoder().decode(EditRecipe.self, from: data), recipe)
        XCTAssertEqual(recipe.people.person(id)?.anchor, anchor)
        XCTAssertEqual(recipe.people.personID(at: PersonAnchor(x: 0.32, y: 0.61, width: 0.11)), id)
        XCTAssertNil(recipe.people.personID(at: PersonAnchor(x: 0.8, y: 0.6, width: 0.12)))
        let empty = try JSONDecoder().decode(EditRecipe.self, from: Data(#"{"schemaVersion":2,"people":{}}"#.utf8))
        XCTAssertTrue(empty.isDefault)
        XCTAssertTrue(
            try XCTUnwrap(String(data: JSONEncoder().encode(EditRecipe()), encoding: .utf8)).contains("\"people\":{}"),
            "레시피는 people 키를 늘 쓴다")
        let genderOnly = EditRecipe(
            people: PeopleAdjustments(individuals: [PersonRecord(id: id, anchor: anchor, gender: .male)]))
        XCTAssertFalse(genderOnly.people.hasEffect, "성별 지정만으로는 렌더가 바뀌지 않는다")
        XCTAssertFalse(genderOnly.dependsOnFaces)
        var pruned = genderOnly.people
        pruned.individuals.append(PersonRecord(id: PersonID(), anchor: anchor))
        pruned.prune()
        XCTAssertEqual(pruned.individuals.count, 1, "성별도 층도 없는 기록만 지운다")
    }

    func testPeopleScalarsAreCheckedForFinitenessAndPresetsCarryGroupsOnly() throws {
        var recipe = EditRecipe()
        recipe.people.groups[.male] = PortraitLayer(face: [.jaw: .nan])
        XCTAssertFalse(recipe.allValuesFinite)
        recipe.people.groups[.male] = PortraitLayer(face: [.jaw: 0.2])
        recipe.people.individuals = [
            PersonRecord(
                id: PersonID(), anchor: PersonAnchor(x: 0.5, y: 0.5, width: 0.2),
                layer: PortraitLayer(skinSmoothing: .infinity))
        ]
        XCTAssertFalse(recipe.allValuesFinite)
        recipe.people.individuals[0].layer.skinSmoothing = 0.7
        XCTAssertTrue(recipe.allValuesFinite)
        let values = PresetValues(of: recipe)
        XCTAssertEqual(values.people.groups[.male], PortraitLayer(face: [.jaw: 0.2]))
        XCTAssertTrue(values.people.individuals.isEmpty, "프리셋은 개인 층을 나르지 않는다")
        let data = try JSONEncoder().encode(values)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(Set((json["people"] as? [String: Any])?.keys ?? []), ["groups"])
        let smuggled = """
            {"color":{},"portrait":{},"people":{"individuals":[{"id":"44444444-4444-4444-4444-444444444444",\
            "anchor":{"x":0.5,"y":0.5,"width":0.2},"layer":{"skin":{"smoothing":1}}}]}}
            """
        let decoded = try JSONDecoder().decode(PresetValues.self, from: Data(smuggled.utf8))
        XCTAssertTrue(decoded.people.individuals.isEmpty, "파일에 든 개인 층은 무시한다")
    }
```

`RecipeSchemaTests.swift`: `encodedSampleRecipe()`의 `recipe.detail.sharpness = 0.2` 뒤에 추가:

```swift
        recipe.people.groups[.female] = PortraitLayer(skinSmoothing: 0.5)
        recipe.people.individuals = [
            PersonRecord(
                id: PersonID(), anchor: PersonAnchor(x: 0.3, y: 0.6, width: 0.12), legacyIndex: 0, gender: .female,
                layer: PortraitLayer(face: [.width: -0.3]))
        ]
```

`testRecipeSchemaPropertiesMatchEncodedKeys`의 최상위 그룹 반복문 배열에 `"people"`을 더하고(`for key in ["color", …, "makeup", "people"]`), 다음 테스트를 추가한다:

```swift
    func testPeopleSchemaDescribesLayersGroupsAndRecords() throws {
        let schema = try schema(named: "edit-recipe.v2.schema")
        let properties = try XCTUnwrap(schema["properties"] as? [String: Any])
        let people = try sectionProperties(properties["people"])
        XCTAssertEqual(Set(people.keys), ["groups", "individuals"])
        XCTAssertEqual(try propertyKeys(people["groups"]), Set(Gender.allCases.map(\.rawValue)))
        let item = try XCTUnwrap((people["individuals"] as? [String: Any])?["items"])
        XCTAssertEqual(try propertyKeys(item), ["id", "anchor", "legacyIndex", "gender", "layer"])
        let layer = try XCTUnwrap((schema["$defs"] as? [String: Any])?["portraitLayer"])
        let layerProperties = try sectionProperties(layer)
        XCTAssertEqual(Set(layerProperties.keys), ["skin", "face", "features", "makeup"])
        XCTAssertEqual(
            try propertyKeys(layerProperties["skin"]),
            Set(["smoothing", "autoBlemish"] + SkinRefinementKey.allCases.map(\.rawValue)))
        XCTAssertEqual(try propertyKeys(layerProperties["face"]), Set(FaceShapeKey.allCases.map(\.rawValue)))
        XCTAssertEqual(try propertyKeys(layerProperties["features"]), Set(FeatureKey.allCases.map(\.rawValue)))
        XCTAssertEqual(
            try propertyKeys(layerProperties["makeup"]), Set(["lookID"] + MakeupPart.allCases.map(\.rawValue)))
        let encodedLayer = try XCTUnwrap(
            ((try encodedSampleRecipe()["people"] as? [String: Any])?["individuals"] as? [[String: Any]])?.first?["layer"]
                as? [String: Any])
        XCTAssertTrue(Set(encodedLayer.keys).isSubset(of: Set(layerProperties.keys)))
    }
```

`SessionFileMigrationTests.swift` 끝에 추가:

```swift
    func testPresetPeopleGroupsPersistAndIndividualsAreDropped() throws {
        var values = PresetValues(color: ColorAdjustments(exposure: 0.2))
        values.people.groups[.male] = PortraitLayer(skinSmoothing: 0.2)
        let preset = Preset(name: "남녀", values: values)
        let snapshot = SessionSnapshot(photos: [], selectedPhotoID: nil, presets: [preset])
        let data = try SessionFile.encode(SessionFileMapper.file(from: snapshot))
        let restored = SessionFileMapper.snapshot(from: try SessionFile.decode(data))
        XCTAssertEqual(restored.presets[0].values.people.groups[.male], PortraitLayer(skinSmoothing: 0.2))
        let json = """
            {"schemaVersion":2,"photos":[],"presets":[{"id":"33333333-3333-3333-3333-333333333333","name":"옛",\
            "values":{"color":{},"portrait":{},"people":{"groups":{"female":{"face":{"jaw":0.1}}},\
            "individuals":[{"id":"44444444-4444-4444-4444-444444444444","anchor":{"x":0.5,"y":0.5,"width":0.2},\
            "layer":{"skin":{"smoothing":1}}}]}}}]}
            """
        let decoded = SessionFileMapper.snapshot(from: try SessionFile.decode(Data(json.utf8)))
        XCTAssertEqual(decoded.presets[0].values.people.groups[.female], PortraitLayer(face: [.jaw: 0.1]))
        XCTAssertTrue(decoded.presets[0].values.people.individuals.isEmpty)
    }
```

- [ ] **Step 2: 실패 확인**

Run: `cd apple && swift test --filter "EditRecipeCodingTests|RecipeSchemaTests|SessionFileMigrationTests"`
Expected: 컴파일 실패 (`cannot find 'PersonRecord' in scope`).

- [ ] **Step 3: 구현**

`PeopleAdjustments.swift` 끝에 추가:

```swift
/// 사진 안 한 사람. anchor로 다시 찾고, layer가 그 사람만의 값이다. gender는 수동 지정만 담는다(자동 추정은 분석 결과).
public struct PersonRecord: Codable, Equatable, Identifiable, Sendable {
    public var id: PersonID
    public var anchor: PersonAnchor?
    /// 옛 targetFace에서 온 기록만 가진다. anchor가 채워지면 지운다.
    public var legacyIndex: Int?
    public var gender: Gender?
    public var layer: PortraitLayer

    public init(
        id: PersonID = PersonID(), anchor: PersonAnchor? = nil, legacyIndex: Int? = nil, gender: Gender? = nil,
        layer: PortraitLayer = PortraitLayer()
    ) {
        self.id = id
        self.anchor = anchor
        self.legacyIndex = legacyIndex
        self.gender = gender
        self.layer = layer
    }

    /// 성별도 층도 없는 기록. 편집 규칙이 변경 뒤 지운다.
    public var isEmpty: Bool { gender == nil && layer.isEmpty }
}

/// 성별 그룹 층 둘과 개인 기록. 전체 층은 EditRecipe.portrait·makeup이다.
public struct PeopleAdjustments: Codable, Equatable, Sendable {
    public var groups: [Gender: PortraitLayer]
    public var individuals: [PersonRecord]

    public init(groups: [Gender: PortraitLayer] = [:], individuals: [PersonRecord] = []) {
        self.groups = groups
        self.individuals = individuals
    }

    /// 어느 층이든 렌더를 바꾸는 값이 있는지. 성별 지정만 있는 기록은 false.
    public var hasEffect: Bool {
        groups.values.contains(where: \.hasEffect) || individuals.contains { $0.layer.hasEffect }
    }

    public var numericValues: [Double] {
        groups.values.flatMap(\.numericValues) + individuals.flatMap(\.layer.numericValues)
    }

    public func person(_ id: PersonID) -> PersonRecord? {
        individuals.first { $0.id == id }
    }

    /// anchor와 같은 사람의 기록. Task 4가 PersonMatcher.isMatch로 바꾼다.
    public func personID(at anchor: PersonAnchor) -> PersonID? {
        individuals.first { $0.anchor.map { $0.isNear(anchor) } ?? false }?.id
    }

    /// 빈 기록을 지운다.
    public mutating func prune() {
        individuals.removeAll(where: \.isEmpty)
    }

    private enum CodingKeys: String, CodingKey {
        case groups
        case individuals
    }

    private struct GenderKey: CodingKey {
        let stringValue: String
        var intValue: Int? { nil }

        init(stringValue: String) {
            self.stringValue = stringValue
        }

        init?(intValue: Int) {
            nil
        }
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        groups = [:]
        if container.contains(.groups) {
            let nested = try container.nestedContainer(keyedBy: GenderKey.self, forKey: .groups)
            for gender in Gender.allCases {
                groups[gender] = try nested.decodeIfPresent(
                    PortraitLayer.self, forKey: GenderKey(stringValue: gender.rawValue))
            }
        }
        individuals = try container.decodeIfPresent([PersonRecord].self, forKey: .individuals) ?? []
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        let present = groups.filter { !$0.value.isEmpty }
        if !present.isEmpty {
            var nested = container.nestedContainer(keyedBy: GenderKey.self, forKey: .groups)
            for gender in Gender.allCases {
                try nested.encodeIfPresent(present[gender], forKey: GenderKey(stringValue: gender.rawValue))
            }
        }
        if !individuals.isEmpty {
            try container.encode(individuals, forKey: .individuals)
        }
    }
}

extension PersonAnchor {
    /// Task 4의 PersonMatcher.isMatch와 같은 조건. Task 4가 이 확장을 지우고 그 함수를 부른다.
    fileprivate func isNear(_ other: PersonAnchor) -> Bool {
        let reference = max(width, other.width)
        guard reference > 0, min(width, other.width) > 0 else { return false }
        guard reference / min(width, other.width) <= 2 else { return false }
        return ((x - other.x) * (x - other.x) + (y - other.y) * (y - other.y)).squareRoot() / reference <= 0.5
    }
}
```

`EditRecipe.swift`:
- 저장 속성 `public var people = PeopleAdjustments()`를 `makeup` 다음(G3 이후라면 `effects` 다음)에 추가.
- `init`에 `people: PeopleAdjustments = .init()` 인자를 `operations` 앞에 추가하고 대입.
- `CodingKeys`에 `case people`. 디코드: `people = try container.decodeIfPresent(PeopleAdjustments.self, forKey: .people) ?? .init()`. 인코드: `try container.encode(people, forKey: .people)`(항상).
- `dependsOnFaces`: `portrait.dependsOnFaces || makeup.hasEffect || people.hasEffect`.
- `allValuesFinite`의 `groups`에 `+ people.numericValues`.

`Preset.swift`(`PresetValues`):
- 저장 속성 `public var people: PeopleAdjustments` 추가, `init`에 `people: PeopleAdjustments = .init()` 인자 추가.
- `init(of recipe:)`: `people: PeopleAdjustments(groups: recipe.people.groups)`.
- `init(from:)`: `let decodedPeople = try container.decodeIfPresent(PeopleAdjustments.self, forKey: .people) ?? .init()` 뒤 `people = PeopleAdjustments(groups: decodedPeople.groups)`(개인 층은 버림).
- 인코드가 합성이면 `people`이 자동으로 들어간다. `PeopleAdjustments.encode`가 빈 `individuals`를 생략하므로 프리셋에는 `groups`만 쓰인다. 직접 구현한 `encode(to:)`가 있으면 `people`을 더한다.

`shared/recipe-schema/edit-recipe.v2.schema.json`:
- 최상위에 `"$defs": { "portraitLayer": { … } }` 추가. `portraitLayer`는 `type: object`, `additionalProperties: false`, `description: "성긴 층. 있는 키만 아래 층을 덮어쓰고 없는 키는 상속한다."`, `properties`: `skin`(`smoothing` 0~1, `autoBlemish` boolean, 정밀 7종 — 범위는 `portrait.skin`과 같고 `default` 없음), `face`(10개, 범위 같음), `features`(3개), `makeup`(`lookID` string|null, 부위 5개 — `lip`·`blush`·`eyeshadow`는 `colorID` string|null + `intensity`, `brow`·`contour`는 `intensity`만). 모두 `required` 없음.
- `properties.people`: `type: object`, `additionalProperties: false`, `properties`: `groups`(object, `additionalProperties: false`, `properties`: `male`·`female` 각 `{ "$ref": "#/$defs/portraitLayer" }`), `individuals`(array, `items`: object, `additionalProperties: false`, `required: ["id", "layer"]`, `properties`: `id`(string uuid), `anchor`(object `x`·`y` 0~1, `width` 0~1 exclusiveMinimum 0, `required` 셋), `legacyIndex`(integer ≥ 0, description "옛 targetFace에서 이행한 기록만. anchor가 채워지면 사라진다."), `gender`(enum male·female, description "수동 지정. 자동 추정은 저장하지 않는다."), `layer`(`$ref`)). `description`에 "전체(portrait·makeup) → 성별 그룹 → 개인 순서로 키 단위로 덮어쓴다. anchor는 정규화 얼굴 상자 중심과 폭이고 같은 사람 판정은 폭의 50% 거리·크기 비 2배 이내."
- `portrait.targetFace`는 이 Task에서 바꾸지 않는다(H2).

`shared/recipe-schema/session-file.v2.schema.json`: 프리셋 `values.properties`에 `"people": { "$ref": "edit-recipe.v2.schema.json#/properties/people" }` 추가(설명: 프리셋은 `groups`만 쓴다).

`shared/recipe-schema/README.md`:
- 표의 Apple 기준 구현 목록에 `PeopleAdjustments.swift` 추가.
- "v2 형식 요점"에 항목 추가: "`people`은 사람별·성별 그룹 보정(H)이다. `portrait`·`makeup`이 전체 층, `people.groups.male/female`이 성별 그룹 층, `people.individuals[].layer`가 개인 층이며 위 층이 아래 층을 키 단위로 덮어쓴다. 층은 있는 키만 담는다(없음 = 상속). `individuals[].anchor`는 정규화 얼굴 상자의 중심·폭이고 `gender`는 사용자가 지정한 성별만 담는다(자동 추정은 저장하지 않음). `legacyIndex`는 옛 `targetFace`에서 이행한 기록에만 있다."
- 프리셋 항목에 "`people`은 `groups`만 담고 `individuals`는 읽을 때 버린다" 추가.
- "키를 추가할 때의 규칙 (B~G)" 제목을 "(B~H)"로 바꾸고 "H 단계는 최상위 `people`을 같은 규칙으로 더했다(기본값 비어 있음, schemaVersion 2 유지)" 추가.

- [ ] **Step 4: 통과 확인**

Run: `cd apple && swift test` → Shared 54, Library 32, 나머지 불변(Rendering 257 · Export 4 · Editing 36), 0 failures. 기존 `SessionSchemaTests`가 `people` 키를 스키마에서 찾아 통과한다. lint 출력 없음. `./scripts/verify-modules.sh` 통과.

- [ ] **Step 5: 커밋**

```bash
git add apple/Sources/MellowShared/API/PeopleAdjustments.swift apple/Sources/MellowShared/API/EditRecipe.swift apple/Sources/MellowShared/API/Preset.swift shared/recipe-schema/edit-recipe.v2.schema.json shared/recipe-schema/session-file.v2.schema.json shared/recipe-schema/README.md apple/Tests/MellowSharedTests/EditRecipeCodingTests.swift apple/Tests/MellowSharedTests/RecipeSchemaTests.swift apple/Tests/MellowLibraryTests/SessionFileMigrationTests.swift
git commit -m "feat(shared): 레시피에 성별 그룹·개인 기록 people 추가

PersonRecord(anchor·수동 성별·층)와 PeopleAdjustments. 프리셋은 그룹 층만 나른다.
스키마 두 파일과 README 갱신. targetFace는 그대로(H2에서 이행).

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 3: 층 해석 — PortraitScope, PortraitResolver

**Files:**
- Create: `apple/Sources/MellowShared/API/PortraitResolver.swift`
- Test: `apple/Tests/MellowSharedTests/PortraitResolverTests.swift` (새 파일)

**Interfaces:**
- Consumes: `EditRecipe.people`, `PortraitLayer.applied(to:makeup:)`.
- Produces: 인터페이스 요약의 Task 3 항목.

설계 근거: 스펙 1.3. 전체 ⊕ 그룹(유효 성별) ⊕ 개인. 성별이 nil이면 그룹을 건너뛴다. `.person` scope의 유효 성별은 기록의 수동 성별이 먼저이고 호출자가 넘긴 추정이 그다음이다.

- [ ] **Step 1: 실패하는 테스트 작성**

`apple/Tests/MellowSharedTests/PortraitResolverTests.swift`:

```swift
import XCTest

@testable import MellowShared

final class PortraitResolverTests: XCTestCase {
    private let id = PersonID()

    private func sample() -> EditRecipe {
        var recipe = EditRecipe()
        recipe.portrait.skin.smoothing = 0.2
        recipe.portrait.skin.autoBlemish = true
        recipe.makeup.lip = MakeupTint(colorID: "lip-coral", intensity: 0.3)
        recipe.people.groups[.female] = PortraitLayer(
            skinSmoothing: 0.5, features: [.eyeBrighten: 0.4],
            makeup: [.lip: MakeupTint(colorID: "lip-rose", intensity: 0.6)])
        recipe.people.groups[.male] = PortraitLayer(skinSmoothing: 0.1)
        recipe.people.individuals = [
            PersonRecord(
                id: id, anchor: PersonAnchor(x: 0.3, y: 0.5, width: 0.2), gender: .female,
                layer: PortraitLayer(
                    skinSmoothing: 0.9, face: [.width: -0.3], makeup: [.lip: MakeupTint(colorID: nil, intensity: 0)]))
        ]
        return recipe
    }

    func testLayersOverlayKeyByKeyAndUndeterminedGenderSkipsGroups() {
        let recipe = sample()
        let person = recipe.people.person(id)
        let resolved = PortraitResolver.resolve(recipe, person: person, gender: .female)
        XCTAssertEqual(resolved.portrait.skin.smoothing, 0.9, "개인이 그룹·전체를 이긴다")
        XCTAssertTrue(resolved.portrait.skin.autoBlemish, "아무 층도 덮지 않은 키는 전체 값")
        XCTAssertEqual(resolved.portrait.features.eyeBrighten, 0.4, "개인이 덮지 않은 키는 그룹 값")
        XCTAssertEqual(resolved.portrait.face.width, -0.3)
        XCTAssertNil(resolved.makeup.lip.colorID, "개인 층의 색 없음이 그룹의 색을 이긴다")
        XCTAssertEqual(resolved.makeup.lip.intensity, 0)
        let groupOnly = PortraitResolver.resolve(recipe, person: nil, gender: .female)
        XCTAssertEqual(groupOnly.portrait.skin.smoothing, 0.5)
        XCTAssertEqual(groupOnly.makeup.lip, MakeupTint(colorID: "lip-rose", intensity: 0.6))
        let undetermined = PortraitResolver.resolve(recipe, person: nil, gender: nil)
        XCTAssertEqual(undetermined.portrait, recipe.portrait)
        XCTAssertEqual(undetermined.makeup, recipe.makeup)
        let male = PortraitResolver.resolve(recipe, person: nil, gender: .male)
        XCTAssertEqual(male.portrait.skin.smoothing, 0.1)
        XCTAssertEqual(male.portrait.features.eyeBrighten, 0, "다른 그룹의 키는 받지 않는다")
        var noGroups = recipe
        noGroups.people.groups = [:]
        XCTAssertEqual(PortraitResolver.resolve(noGroups, person: nil, gender: .female).portrait, recipe.portrait)
    }

    func testScopeResolutionEffectiveGenderAndOverriddenKeys() {
        let recipe = sample()
        let person = recipe.people.person(id)
        XCTAssertEqual(PortraitResolver.effectiveGender(person: person, estimate: .male), .female, "수동 지정이 추정을 이긴다")
        let unassigned = PersonRecord(anchor: PersonAnchor(x: 0.5, y: 0.5, width: 0.1))
        XCTAssertEqual(PortraitResolver.effectiveGender(person: unassigned, estimate: .male), .male)
        XCTAssertNil(PortraitResolver.effectiveGender(person: nil, estimate: nil))
        XCTAssertEqual(PortraitResolver.resolve(recipe, scope: .all, estimate: .female).portrait, recipe.portrait)
        XCTAssertEqual(PortraitResolver.resolve(recipe, scope: .gender(.female), estimate: nil).portrait.skin.smoothing, 0.5)
        let scoped = PortraitResolver.resolve(recipe, scope: .person(id), estimate: .male)
        XCTAssertEqual(scoped.portrait.skin.smoothing, 0.9)
        XCTAssertEqual(scoped.portrait.features.eyeBrighten, 0.4, "기록의 수동 성별(여성)로 그룹을 고른다")
        XCTAssertEqual(
            PortraitResolver.resolve(recipe, scope: .person(PersonID()), estimate: nil).portrait, recipe.portrait,
            "모르는 사람은 전체 값")
        XCTAssertEqual(PortraitResolver.overriddenKeys(recipe, scope: .all), [])
        XCTAssertEqual(PortraitResolver.overriddenKeys(recipe, scope: .gender(.male)), [.skinSmoothing])
        XCTAssertEqual(
            PortraitResolver.overriddenKeys(recipe, scope: .person(id)),
            [.skinSmoothing, .faceShape(.width), .makeupPart(.lip)])
        XCTAssertEqual(PortraitResolver.overriddenKeys(recipe, scope: .person(PersonID())), [])
        XCTAssertNil(PortraitResolver.layer(recipe, scope: .all))
        XCTAssertEqual(PortraitResolver.layer(recipe, scope: .gender(.male)), PortraitLayer(skinSmoothing: 0.1))
        var withoutMale = recipe
        withoutMale.people.groups[.male] = nil
        XCTAssertEqual(PortraitResolver.layer(withoutMale, scope: .gender(.male)), PortraitLayer(), "없는 그룹은 빈 층")
    }
}
```

- [ ] **Step 2: 실패 확인**

Run: `cd apple && swift test --filter PortraitResolverTests` → 컴파일 실패 (`cannot find 'PortraitResolver' in scope`).

- [ ] **Step 3: 구현**

`apple/Sources/MellowShared/API/PortraitResolver.swift`:

```swift
import Foundation

/// 편집·화면이 가리키는 층. 값 타입이라 여기 둔다(Rendering은 Editing을 import할 수 없다).
public enum PortraitScope: Hashable, Sendable {
    case all
    case gender(Gender)
    case person(PersonID)
}

/// 전체 → 성별 그룹 → 개인 순서로 키 단위로 겹친 값을 만든다. 렌더·편집·앱이 같은 함수를 쓴다.
public enum PortraitResolver {
    public struct Resolved: Equatable, Sendable {
        public var portrait: PortraitAdjustments
        public var makeup: MakeupAdjustments

        public init(portrait: PortraitAdjustments, makeup: MakeupAdjustments) {
            self.portrait = portrait
            self.makeup = makeup
        }
    }

    /// gender가 nil이면 그룹 층을 건너뛴다(미지정은 전체 값과 개인 값만 받는다).
    public static func resolve(_ recipe: EditRecipe, person: PersonRecord?, gender: Gender?) -> Resolved {
        var portrait = recipe.portrait
        var makeup = recipe.makeup
        if let gender, let group = recipe.people.groups[gender] {
            group.applied(to: &portrait, makeup: &makeup)
        }
        person?.layer.applied(to: &portrait, makeup: &makeup)
        return Resolved(portrait: portrait, makeup: makeup)
    }

    /// 화면용. .person은 기록의 수동 성별이 먼저이고 estimate가 그다음이다. 모르는 사람은 전체 값이다.
    public static func resolve(_ recipe: EditRecipe, scope: PortraitScope, estimate: Gender?) -> Resolved {
        switch scope {
        case .all:
            return Resolved(portrait: recipe.portrait, makeup: recipe.makeup)
        case .gender(let gender):
            return resolve(recipe, person: nil, gender: gender)
        case .person(let id):
            let person = recipe.people.person(id)
            return resolve(recipe, person: person, gender: person == nil ? nil : effectiveGender(person: person, estimate: estimate))
        }
    }

    /// 수동 지정이 있으면 그것, 없으면 추정값.
    public static func effectiveGender(person: PersonRecord?, estimate: Gender?) -> Gender? {
        person?.gender ?? estimate
    }

    /// 그 scope의 층. .all은 nil, 없는 그룹은 빈 층, 모르는 사람은 nil.
    public static func layer(_ recipe: EditRecipe, scope: PortraitScope) -> PortraitLayer? {
        switch scope {
        case .all: return nil
        case .gender(let gender): return recipe.people.groups[gender] ?? PortraitLayer()
        case .person(let id): return recipe.people.person(id)?.layer
        }
    }

    /// 그 층에서 덮어쓴 키. .all은 빈 집합.
    public static func overriddenKeys(_ recipe: EditRecipe, scope: PortraitScope) -> Set<PortraitKey> {
        layer(recipe, scope: scope)?.overriddenKeys ?? []
    }
}
```

- [ ] **Step 4: 통과 확인**

Run: `cd apple && swift test --filter MellowSharedTests` → `Executed 56 tests, with 0 failures`. lint 출력 없음.

- [ ] **Step 5: 커밋**

```bash
git add apple/Sources/MellowShared/API/PortraitResolver.swift apple/Tests/MellowSharedTests/PortraitResolverTests.swift
git commit -m "feat(shared): 전체·성별 그룹·개인 층을 키 단위로 겹치는 PortraitResolver

PortraitScope도 여기 둔다. 미지정 성별은 그룹 층을 건너뛰고 수동 성별이 추정을 이긴다.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 4: 사람 짝짓기 — PersonMatcher, PersonMatching

**Files:**
- Create: `apple/Sources/MellowShared/API/PersonMatcher.swift`
- Modify: `apple/Sources/MellowShared/API/PeopleAdjustments.swift` (`personID(at:)`가 `PersonMatcher.isMatch`를 쓰고 `isNear` 확장 삭제)
- Test: `apple/Tests/MellowSharedTests/PersonMatcherTests.swift` (새 파일)

**Interfaces:**
- Consumes: `PersonRecord`, `PersonAnchor`, `NormalizedRect`.
- Produces: 인터페이스 요약의 Task 4 항목.

설계 근거: 스펙 1.3. 거리 ≤ 폭(둘 중 큰 쪽)의 50%, 폭 비 ≤ 2배, 1:1 탐욕, 결정적. legacy 후보 거리는 허용치로 쳐서 실제 anchor가 먼저 얼굴을 가져간다.

- [ ] **Step 1: 실패하는 테스트 작성**

`apple/Tests/MellowSharedTests/PersonMatcherTests.swift`:

```swift
import XCTest

@testable import MellowShared

final class PersonMatcherTests: XCTestCase {
    private func box(_ x: Double, y: Double = 0.4, width: Double = 0.2) -> NormalizedRect {
        NormalizedRect(x: x, y: y, width: width, height: width * 1.3)
    }

    private func record(_ box: NormalizedRect) -> PersonRecord {
        PersonRecord(anchor: PersonAnchor(faceBox: box))
    }

    func testAnchorsSurviveIndexShiftsAndRejectFarOrOddSizedFaces() {
        let left = box(0.1)
        let middle = box(0.4)
        let right = box(0.7)
        let people = [record(left), record(right)]
        XCTAssertEqual(
            PersonMatcher.match(people, faces: [left, middle, right]),
            [.init(person: people[0].id, faceIndex: 0), .init(person: people[1].id, faceIndex: 2)])
        XCTAssertEqual(
            PersonMatcher.match(people, faces: [middle, right]), [.init(person: people[1].id, faceIndex: 1)],
            "왼쪽 얼굴이 사라져 인덱스가 밀려도 오른쪽 사람은 오른쪽 얼굴")
        // 폭 0.2의 50% = 0.1. 중심이 0.09 움직인 상자는 짝이고 0.11은 아니다.
        XCTAssertEqual(PersonMatcher.match([people[0]], faces: [box(0.19)]).count, 1)
        XCTAssertTrue(PersonMatcher.match([people[0]], faces: [box(0.21)]).isEmpty)
        XCTAssertTrue(PersonMatcher.match([people[0]], faces: [box(0.1, width: 0.41)]).isEmpty, "폭이 2배를 넘으면 다른 사람")
        XCTAssertEqual(PersonMatcher.match([people[0]], faces: [box(0.1, width: 0.39)]).count, 1)
        XCTAssertTrue(PersonMatcher.isMatch(PersonAnchor(faceBox: left), PersonAnchor(faceBox: box(0.15))))
        XCTAssertFalse(PersonMatcher.isMatch(PersonAnchor(faceBox: left), PersonAnchor(faceBox: right)))
        XCTAssertFalse(PersonMatcher.isMatch(PersonAnchor(x: 0.5, y: 0.5, width: 0), PersonAnchor(faceBox: left)))
        XCTAssertTrue(PersonMatcher.match(people, faces: []).isEmpty)
        XCTAssertTrue(PersonMatcher.match([], faces: [left]).isEmpty)
        XCTAssertEqual(PersonMatching.centerTolerance, 0.5)
        XCTAssertEqual(PersonMatching.sizeRatioLimit, 2)
    }

    func testMatchingIsOneToOneDeterministicAndFallsBackToLegacyIndex() {
        let face = box(0.4)
        let near = record(box(0.42))
        let nearer = record(box(0.41))
        let matches = PersonMatcher.match([near, nearer], faces: [face])
        XCTAssertEqual(matches, [.init(person: nearer.id, faceIndex: 0)], "한 얼굴은 가장 가까운 사람 하나만")
        XCTAssertEqual(PersonMatcher.match([near, nearer], faces: [face]), matches, "같은 입력은 같은 결과")
        let twoFaces = PersonMatcher.match([near, nearer], faces: [face, box(0.44)])
        XCTAssertEqual(twoFaces.map(\.faceIndex), [0, 1], "얼굴 인덱스 순서로 돌려준다")
        XCTAssertEqual(twoFaces.first { $0.person == nearer.id }?.faceIndex, 0)
        XCTAssertEqual(twoFaces.first { $0.person == near.id }?.faceIndex, 1)
        let legacy = PersonRecord(id: PersonID.legacy(index: 1), legacyIndex: 1)
        XCTAssertEqual(
            PersonMatcher.match([legacy], faces: [box(0.1), box(0.7)]), [.init(person: legacy.id, faceIndex: 1)])
        XCTAssertTrue(PersonMatcher.match([legacy], faces: [box(0.1)]).isEmpty, "인덱스가 범위 밖이면 짝 없음")
        let anchored = record(box(0.7))
        XCTAssertEqual(
            PersonMatcher.match([legacy, anchored], faces: [box(0.1), box(0.7)]).map(\.person), [anchored.id],
            "anchor가 먼저 얼굴을 가져가면 legacy 기록은 짝이 없다")
        var people = PeopleAdjustments(individuals: [anchored])
        XCTAssertEqual(people.personID(at: PersonAnchor(faceBox: box(0.72))), anchored.id)
        people.individuals.append(legacy)
        XCTAssertNil(people.personID(at: PersonAnchor(faceBox: box(0.1))), "anchor 없는 기록은 anchor로 찾지 못한다")
    }
}
```

- [ ] **Step 2: 실패 확인**

Run: `cd apple && swift test --filter PersonMatcherTests` → 컴파일 실패 (`cannot find 'PersonMatcher' in scope`).

- [ ] **Step 3: 구현**

`apple/Sources/MellowShared/API/PersonMatcher.swift`:

```swift
import Foundation

/// 같은 사람 판정 기준. 좌표는 정규화 얼굴 상자(원본 기준)라 해상도·자르기·회전과 무관하다.
public enum PersonMatching {
    /// 중심 거리 허용치. 두 폭 중 큰 쪽에 대한 비율.
    public static let centerTolerance = 0.5
    /// 폭 비(큰 쪽 / 작은 쪽) 상한.
    public static let sizeRatioLimit = 2.0
}

/// 저장된 사람 기록과 이번에 찾은 얼굴을 1:1로 짝짓는다. 결정적이다.
public enum PersonMatcher {
    public struct Match: Equatable, Sendable {
        public var person: PersonID
        public var faceIndex: Int

        public init(person: PersonID, faceIndex: Int) {
            self.person = person
            self.faceIndex = faceIndex
        }
    }

    private struct Candidate {
        let distance: Double
        let personIndex: Int
        let faceIndex: Int
    }

    /// 두 anchor가 같은 사람인지(거리·크기 조건).
    public static func isMatch(_ a: PersonAnchor, _ b: PersonAnchor) -> Bool {
        distance(a, b) != nil
    }

    /// 조건을 만족하면 큰 폭 대비 중심 거리, 아니면 nil.
    static func distance(_ a: PersonAnchor, _ b: PersonAnchor) -> Double? {
        let larger = max(a.width, b.width)
        let smaller = min(a.width, b.width)
        guard smaller > 0, larger / smaller <= PersonMatching.sizeRatioLimit else { return nil }
        let normalized = hypot(a.x - b.x, a.y - b.y) / larger
        return normalized <= PersonMatching.centerTolerance ? normalized : nil
    }

    /// 후보 (사람, 얼굴) 쌍을 거리 오름차순으로 고르며 이미 쓴 사람·얼굴은 건너뛴다. 동률은 사람 배열 순서, 얼굴 인덱스 순서.
    /// anchor 없는 기록(legacyIndex)은 그 인덱스의 얼굴이 있으면 허용치 거리의 후보가 된다(실제 anchor가 우선).
    /// 결과는 얼굴 인덱스 순서다.
    public static func match(_ people: [PersonRecord], faces: [NormalizedRect]) -> [Match] {
        let anchors = faces.map(PersonAnchor.init(faceBox:))
        var candidates: [Candidate] = []
        for (personIndex, person) in people.enumerated() {
            if let anchor = person.anchor {
                for (faceIndex, faceAnchor) in anchors.enumerated() {
                    if let distance = distance(anchor, faceAnchor) {
                        candidates.append(Candidate(distance: distance, personIndex: personIndex, faceIndex: faceIndex))
                    }
                }
            } else if let index = person.legacyIndex, faces.indices.contains(index) {
                candidates.append(
                    Candidate(distance: PersonMatching.centerTolerance, personIndex: personIndex, faceIndex: index))
            }
        }
        candidates.sort {
            ($0.distance, $0.personIndex, $0.faceIndex) < ($1.distance, $1.personIndex, $1.faceIndex)
        }
        var usedPeople = Set<Int>()
        var usedFaces = Set<Int>()
        var matches: [Match] = []
        for candidate in candidates
        where !usedPeople.contains(candidate.personIndex) && !usedFaces.contains(candidate.faceIndex) {
            usedPeople.insert(candidate.personIndex)
            usedFaces.insert(candidate.faceIndex)
            matches.append(Match(person: people[candidate.personIndex].id, faceIndex: candidate.faceIndex))
        }
        return matches.sorted { $0.faceIndex < $1.faceIndex }
    }
}
```

`PeopleAdjustments.swift`: `personID(at:)`를 다음으로 바꾸고 `extension PersonAnchor { isNear }`를 지운다.

```swift
    /// anchor와 같은 사람의 기록(PersonMatcher.isMatch). anchor 없는 기록은 찾지 못한다.
    public func personID(at anchor: PersonAnchor) -> PersonID? {
        individuals.first { record in record.anchor.map { PersonMatcher.isMatch($0, anchor) } ?? false }?.id
    }
```

- [ ] **Step 4: 통과 확인**

Run: `cd apple && swift test` → 패키지 387(Shared 58 · Rendering 257 · Library 32 · Export 4 · Editing 36), 0 failures. lint 출력 없음. `./scripts/verify-modules.sh` 통과. Mac 앱 테스트 → `Executed 78 tests, with 0 failures`, `TEST SUCCEEDED`(회귀 확인만, 앱 코드 변경 없음). `cd apple && xcodegen generate --quiet && git diff --exit-code --stat MellowPhoto.xcodeproj` → 출력 없음.

- [ ] **Step 5: 커밋**

```bash
git add apple/Sources/MellowShared/API/PersonMatcher.swift apple/Sources/MellowShared/API/PeopleAdjustments.swift apple/Tests/MellowSharedTests/PersonMatcherTests.swift
git commit -m "feat(shared): 저장된 사람과 찾은 얼굴을 anchor로 1:1 짝짓는 PersonMatcher

얼굴 폭 50% 거리·크기 비 2배 이내, 거리 오름차순 탐욕, legacyIndex 폴백. 결정적.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

## 자체 검토 결과

- **스펙 대조:** §1.1 → `Gender`·`PersonID`·`PersonAnchor`·`PortraitKey`·`PortraitLayer`(Task 1), `PersonRecord`·`PeopleAdjustments`·`EditRecipe.people`·`PresetValues.people`(Task 2), `PortraitResolver`·`PortraitScope`(Task 3), `PersonMatcher`·`PersonMatching`(Task 4), 새 import 없음·`verify-modules.sh` 불변. §1.2 → `people` JSON 모양·성긴 층·부위 단위 메이크업·`gender`는 수동만·`legacyIndex`·`dependsOnFaces`·`allValuesFinite`·`PresetValues`는 groups만·스키마 두 파일·README(Task 1·2), 이행은 H2(적용 순서 항목대로 이 계획은 더하기만). §1.3 → 타입·함수 이름이 인터페이스 요약과 같다(Task 1~4). §2 → 레시피·해석·짝짓기 행(Task 2·3·4). §5 → H1 "4 Task, 더하기만"과 같다.
- **타입 일관성:** `PortraitLayer.applied(to:makeup:)`·`remove`·`difference`·`overriddenKeys`·`hasEffect`·`isEmpty`, `PersonRecord.isEmpty`, `PeopleAdjustments.person`·`personID(at:)`·`prune`·`hasEffect`·`numericValues`, `PortraitResolver.resolve(_:person:gender:)`·`resolve(_:scope:estimate:)`·`effectiveGender`·`layer`·`overriddenKeys`, `PersonMatcher.match`·`isMatch`·`Match(person:faceIndex:)`, `PersonMatching.centerTolerance`·`sizeRatioLimit`, `PersonID.legacy(index:)`를 정의한 Task와 쓰는 Task에서 같게 썼다. 테스트 수: 패키지 377 → 379 → 383 → 385 → 387(Shared 49 → 51 → 54 → 56 → 58, Library 31 → 32), 앱 Mac 78 → 78.
- **Review Focus 매핑:** 1→Task 2, 2→Task 1, 3→Task 1·2, 4→Task 2, 5→Task 3, 6→Task 4. 모두 테스트 코드가 있다.
- **플레이스홀더 점검:** "TBD/TODO/나중에" 없음. Task 2의 임시 `isNear`는 Task 4가 지운다고 양쪽에 적었다.
