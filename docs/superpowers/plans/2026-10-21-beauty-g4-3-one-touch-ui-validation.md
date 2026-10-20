# 인물 보정 G4-3 원터치 화면·검증 구현 계획

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 뷰티 패널을 "대상 칩 → 원터치 버튼 + 강도 슬라이더 → 안내 → 세부 조정(접기)"으로 재구성한다. 원터치는 현재 대상(전체·그룹·사람)에 적용되고 강도 슬라이더는 그 층의 `oneTouch` 표시를 보인다. 질문 2의 답에 따라 "자동" 버튼이 원터치를 포함한다. 시나리오 테스트·모듈 지도·VALIDATION으로 G4를 마친다.

**Architecture:** `AppModel`이 H2의 `BeautyTarget`·`scope(for:)`·`anchor(forFace:)`로 `EditDocument.applyOneTouch`를 라우팅하고, 화면은 새 `OneTouchRow` 하나가 버튼·슬라이더·안내를 그린다. 세부 슬라이더(`AdjustmentSlider`)는 `tag` 하나를 더해 "원터치" 꼬리표를 보인다. 자동 버튼은 `AppModel.Policy.autoIncludesOneTouch` 상수 하나로 두 선택지를 가른다. 렌더·레시피·모듈 표 변경 없음.

**Tech Stack:** SwiftUI + Observation, XCTest, XcodeGen 2.46.0.

**Spec:** `docs/superpowers/specs/2026-10-21-beauty-g4-one-touch-design.md` (3.4, 4절, 7.1의 G4-3 행, 7.2). 선행: G4-2, H3 Task 2·3 머지(`TargetChips`·`scopedValues`·`overriddenKeys`·`AdjustmentSlider(isOverridden:onReset:)`).

## 사람이 확인할 것

- **순서.** Task 1 `AppModel` 원터치 상태·라우팅·자동 연동 → 2 `OneTouchRow`·패널 재구성·문구 → 3 시나리오·문서·VALIDATION. 3개 Task, Task마다 Opus 구현 → 리뷰 → 수정, 끝에 전체 리뷰.
- **외부 효과가 있는 단계.** 없음. CI 복구·TestFlight는 사용자 조치.
- **질문 2의 답이 필요하다.** 답이 "포함"이면 `Policy.autoIncludesOneTouch = true`, "분리"면 `false`. 이 계획은 두 경우의 테스트를 모두 적고 하나만 남긴다. 답이 없으면 권고(포함)로 간다.
- **스펙이 정하지 않아 이 계획이 정한 것.**

| 결정 | 이유 | 바꾸면 비용 |
|---|---|---|
| 원터치 버튼은 표시가 없으면 기본 강도 0.6, 있으면 그 강도로 다시 적용한다(손으로 바꾼 값을 표로 되돌림) | "다시 원터치"가 가장 흔한 의도 | 작음 |
| 강도 슬라이더는 표시가 nil이면 손잡이를 0에 두고 값 자리에 "—"를 보인다. 드래그를 시작하면 그 자리에서 적용된다 | nil을 숫자로 속이지 않는다 | 작음 |
| 세부 조정 접기 상태는 `AppModel.showsDetailAdjustments`(세션 상태, 기본 접힘)이고 사진을 바꿔도 유지한다 | 자주 펼치는 사용자는 계속 펼쳐 둔다 | 작음 |
| "원터치" 꼬리표는 묶인 키이고 현재 대상 층에 표시가 있을 때만 붙는다. 상속 중인 아래 층의 표시는 꼬리표를 만들지 않는다 | 표시는 층 단위이고 H의 "덮어쓴 것만 표시"와 같은 결 | 작음 |
| 자동 버튼이 원터치를 포함할 때 얼굴이 없으면 색감·디테일만 적용하고 상태 문구는 지금과 같다 | 얼굴이 없으면 표를 쓸 곳이 없다 | 작음 |

- **범위 밖.** 메이크업 패널 변경(H3 칩만), 자동 성별 추정(H4).
- **위험.** iPhone 폭에서 "원터치 보정" 버튼 + 슬라이더 한 줄이 좁을 수 있다(세로 스택으로 접히게 `ViewThatFits`). 화면 품질은 자동 테스트로 판정할 수 없다 — 실기기 확인은 사용자 조치.
- **사용자 조치.** Task 3 뒤 CI 요금 한도 해제 → CI 통과 확인 → TestFlight(1.4.0) → 기기에서 커플 사진 성별 지정 → 원터치 → 남녀 차이·강도·세부 조정 접기·꼬리표 확인. 표 값 취향 피드백.

---

## 에이전트 참조

## Global Constraints

G4-1 계획의 Global Constraints를 그대로 따른다(브랜치·`DEVELOPER_DIR`·모듈 표 불변·lint·커밋 서명·`git add` 경로 제한·**로컬 iOS 시뮬레이터 금지**). 이 계획에서 다른 것:

- 시작 조건: G4-2와 H3 Task 3 머지. 기준 테스트 수는 **시작 전에 실측해 이 줄에 적는다**. 이 계획이 더하는 수: **앱 Mac +4**(Task 1 +2, Task 2 +1, Task 3 +1). 패키지 0.
- 새 앱 파일: `apple/MellowPhoto/Features/Editor/OneTouchRow.swift`, 테스트 `apple/MellowPhotoTests/OneTouchRowTests.swift`. Task 2에서 `cd apple && xcodegen generate --quiet`를 돌리고 `apple/MellowPhoto.xcodeproj`를 함께 커밋한다(`project.yml`은 고치지 않는다).
- `Theme` 새 상수: `oneTouchButtonMinWidth` 96. `AppModel.Policy` 새 상수: `autoIncludesOneTouch`(질문 2), `oneTouchDefaultStrength`는 `EditingPolicy` 것을 쓴다(중복 정의 금지).
- 한국어 문구는 `UserMessage`에만.

## Review Focus

1. **"전체" 대상에서 원터치 → "사람 1" 칩 → 강도 슬라이더.** 사람 1의 표시는 nil(개인 층에 표시 없음)이라 "—"이고, 드래그하면 그 사람 층에만 그 사람의 성별 표가 쓰인다. → Task 1 `testOneTouchRoutesToTheCurrentTargetAndRemembersStrength`.
2. **원터치 뒤 세부 조정에서 다크서클을 움직인다.** 전체 층 표시가 사라지고 꼬리표가 떨어지며 강도 슬라이더가 "—"가 된다. → Task 1 같은 테스트, Task 3 시나리오.
3. **얼굴 없는 사진에서 자동.** (포함) 색감만 바뀌고 오류 없음. → Task 1 `testAutoEnhanceIncludesOneTouchOnlyWhenFacesExist`.
4. **잠긴 사진(수동 편집)에서 원터치.** 허용되고 얼굴형은 그대로. → Task 1 같은 테스트 끝.
5. **실행 취소 한 번.** 원터치(세 층 + 몸 피부)가 한 단계로 되돌아간다. → Task 1.

## 인터페이스 요약 (모든 Task가 공유하는 이름)

```swift
// 앱 (Task 1)
AppModel.Policy.autoIncludesOneTouch: Bool
AppModel.showsDetailAdjustments: Bool = false
AppModel.oneTouchStrength: Double?                              // 현재 대상 층의 표시
AppModel.applyOneTouch(strength: Double? = nil)                 // nil = 표시 ?? 기본 강도. 대상 라우팅
AppModel.isOneTouchTagged(_ key: PortraitKey) -> Bool
AppModel.applyAutoSuggestion(_:)                                // Policy에 따라 oneTouchStrength 전달
// 앱 (Task 2)
struct OneTouchRow: View { static func strengthText(for strength: Double?) -> String; static func hint(for target: AppModel.BeautyTarget) -> String }
AdjustmentSlider(title:value:range:snapsToZero:isOverridden:onReset:tag:change:)
UserMessage.oneTouch, oneTouchStrength, oneTouchTag, oneTouchHintAll, oneTouchHintGroup, oneTouchHintPerson, assignGenderForOneTouch, detailAdjustments, strengthUnset
Theme.oneTouchButtonMinWidth
```

---

### Task 1: AppModel — 원터치 상태·라우팅·자동 연동

**Files:**
- Modify: `apple/MellowPhoto/Application/AppModel.swift`, `AppModel+Editing.swift`, `AppModel+Looks.swift`
- Test: `apple/MellowPhotoTests/AppModelTests.swift`

- [ ] **Step 1: 실패하는 테스트 작성**

`AppModelTests.swift` 끝에 추가:

```swift
    func testOneTouchRoutesToTheCurrentTargetAndRemembersStrength() async throws {
        let staged = try TestSupport.solidPNG(in: root)
        let faces = twoFaces()
        let model = TestSupport.makeModel(
            root: root, analyzer: StubFaceAnalyzer(result: .success(faces)),
            importer: FakeImporter(staged: [.success(StagedPhoto(url: staged, displayName: nil))]))
        try await importOne(model, staged)
        XCTAssertFalse(model.showsDetailAdjustments, "세부 조정은 접혀서 시작")
        XCTAssertNil(model.oneTouchStrength)
        model.applyOneTouch()
        XCTAssertEqual(model.oneTouchStrength, EditingPolicy.oneTouchDefaultStrength)
        XCTAssertEqual(model.currentRecipe.people.groups[.female]?.oneTouch, EditingPolicy.oneTouchDefaultStrength)
        XCTAssertEqual(model.currentRecipe.bodySkin.brightness, OneTouchBundle.Table.bodyBrightness * EditingPolicy.oneTouchDefaultStrength, accuracy: 1e-12)
        XCTAssertEqual(model.session.selected?.document.undoStack.count, 1, "세 층 + 몸 피부가 한 단계")
        XCTAssertTrue(model.isOneTouchTagged(.skinRefinement(.darkCircles)))
        XCTAssertFalse(model.isOneTouchTagged(.faceShape(.width)), "얼굴형은 묶음 밖")
        model.setBeautyTarget(.face(0))
        XCTAssertNil(model.oneTouchStrength, "개인 층에는 표시가 없다(그룹 값 상속)")
        XCTAssertFalse(model.isOneTouchTagged(.skinRefinement(.darkCircles)), "상속 중인 표시는 꼬리표가 아니다")
        model.setGender(.female)
        model.beginSliderEdit()
        model.applyOneTouch(strength: 0.3)
        model.applyOneTouch(strength: 1)
        model.endSliderEdit()
        XCTAssertEqual(model.oneTouchStrength, 1)
        let person = try XCTUnwrap(model.currentRecipe.people.individuals.first)
        XCTAssertEqual(person.layer, OneTouchBundle.layer(for: .female, strength: 1), "사람 대상은 그 사람의 성별 표")
        XCTAssertEqual(model.session.selected?.document.undoStack.count, 3, "성별 지정 1 + 드래그 1")
        model.setBeautyTarget(.all)
        XCTAssertEqual(model.oneTouchStrength, EditingPolicy.oneTouchDefaultStrength, "전체 층 표시는 그대로")
        model.edit(.skinRefinement(.darkCircles, 0.1))
        XCTAssertNil(model.oneTouchStrength, "묶인 키를 손으로 바꾸면 표시가 사라진다")
        XCTAssertFalse(model.isOneTouchTagged(.skinRefinement(.darkCircles)))
        XCTAssertEqual(model.currentRecipe.people.groups[.male]?.oneTouch, EditingPolicy.oneTouchDefaultStrength, "그룹 표시는 남는다")
        model.applyOneTouch()
        XCTAssertEqual(model.oneTouchStrength, EditingPolicy.oneTouchDefaultStrength, "표시가 없으면 기본 강도로 다시 적용")
        model.setBeautyTarget(.gender(.male))
        model.applyOneTouch(strength: 0)
        XCTAssertNil(model.currentRecipe.people.groups[.male], "강도 0은 그룹의 묶인 키를 지운다")
        model.setBeautyTarget(.all)
        model.tool = .retouch
        try await waitUntil { !model.isRendering }
        model.touch(from: NormalizedPoint(x: 0.5, y: 0.1), to: NormalizedPoint(x: 0.5, y: 0.1))
        model.touch(from: NormalizedPoint(x: 0.52, y: 0.1), to: NormalizedPoint(x: 0.52, y: 0.1))
        try await waitUntil { !model.isRendering }
        XCTAssertTrue(model.isGeometryLocked)
        model.applyOneTouch(strength: 1)
        XCTAssertEqual(model.oneTouchStrength, 1, "잠긴 사진에서도 원터치는 된다")
        XCTAssertEqual(model.currentRecipe.portrait.face, FaceShapeAdjustments())
        XCTAssertNil(model.presentedError)
        model.showsDetailAdjustments = true
        model.select(model.session.photos[0].id)
        XCTAssertTrue(model.showsDetailAdjustments, "접기 상태는 사진과 무관")
    }

    // 질문 2 = "포함"일 때. "분리"면 아래 testAutoEnhanceLeavesOneTouchAlone을 대신 쓴다.
    func testAutoEnhanceIncludesOneTouchOnlyWhenFacesExist() async throws {
        XCTAssertTrue(AppModel.Policy.autoIncludesOneTouch)
        let staged = try TestSupport.solidPNG(in: root)
        let model = TestSupport.makeModel(
            root: root, analyzer: StubFaceAnalyzer(result: .success(twoFaces())),
            importer: FakeImporter(staged: [.success(StagedPhoto(url: staged, displayName: nil))]))
        try await importOne(model, staged)
        await model.autoEnhance()
        try await waitUntil { !model.isRendering }
        XCTAssertEqual(model.oneTouchStrength, EditingPolicy.oneTouchDefaultStrength, "자동이 원터치를 포함한다")
        XCTAssertEqual(model.currentRecipe.people.groups[.female]?.oneTouch, EditingPolicy.oneTouchDefaultStrength)
        XCTAssertEqual(model.session.selected?.document.undoStack.count, 1)
        XCTAssertEqual(model.statusMessage, UserMessage.autoEnhanced)
        let faceless = try TestSupport.solidPNG(in: root, name: "faceless")
        let plain = TestSupport.makeModel(
            root: root, importer: FakeImporter(staged: [.success(StagedPhoto(url: faceless, displayName: nil))]))
        try await importOne(plain, faceless)
        await plain.autoEnhance()
        try await waitUntil { !plain.isRendering }
        XCTAssertNil(plain.oneTouchStrength, "얼굴이 없으면 색감만")
        XCTAssertTrue(plain.currentRecipe.people.groups.isEmpty)
        XCTAssertNotEqual(plain.currentRecipe.color, ColorAdjustments())
        XCTAssertNil(plain.presentedError)
    }

    // 질문 2 = "분리"일 때만 쓴다(위 테스트는 지운다).
    // func testAutoEnhanceLeavesOneTouchAlone() async throws {
    //     XCTAssertFalse(AppModel.Policy.autoIncludesOneTouch)
    //     … 얼굴 둘 사진에서 autoEnhance() 뒤 oneTouchStrength == nil, groups 비어 있음, skin.smoothing == RenderTuning().autoSkinSmoothing.
    // }
```

기존 `testAutoEnhanceIsOneUndoStepAndIdempotent`가 피부 보정 0.3을 단언하면 "포함"에서는 `OneTouchBundle.Table.common.smoothing × oneTouchDefaultStrength`로 바꾼다(얼굴이 있는 모델일 때).

- [ ] **Step 2: 실패 확인**

Run: Mac 앱 테스트 → 컴파일 실패(`applyOneTouch` 없음).

- [ ] **Step 3: 구현**

`AppModel.swift`:

```swift
    enum Policy {
        …
        /// 질문 2의 답. true면 자동 버튼이 색감·디테일 자동 + 얼굴이 있으면 원터치 기본 강도를 한 단계로 적용한다.
        static let autoIncludesOneTouch = true
    }

    /// 뷰티 패널의 세부 조정 접기. 세션 상태이고 사진과 무관하다.
    var showsDetailAdjustments = false

    /// 현재 대상 층의 원터치 표시. 전체는 portrait.oneTouch, 그룹·개인은 그 층의 oneTouch, 기록 없는 얼굴은 nil.
    var oneTouchStrength: Double? {
        switch beautyTarget {
        case .all: return currentRecipe.portrait.oneTouch
        default: return scope(for: beautyTarget).flatMap { PortraitResolver.layer(currentRecipe, scope: $0) }?.oneTouch
        }
    }

    /// 세부 슬라이더에 "원터치" 꼬리표를 붙일지. 묶인 키이고 현재 대상 층에 표시가 있을 때만.
    func isOneTouchTagged(_ key: PortraitKey) -> Bool {
        OneTouchBundle.keys.contains(key) && oneTouchStrength != nil
    }
```

`AppModel+Editing.swift`:

```swift
    /// 원터치를 현재 대상에 적용한다. strength가 nil이면 표시(없으면 기본 강도). 찾은 얼굴을 처음 만지면 기록이 생긴다.
    func applyOneTouch(strength: Double? = nil) {
        let value = strength ?? oneTouchStrength ?? EditingPolicy.oneTouchDefaultStrength
        switch beautyTarget {
        case .face(let index):
            let boxes = faces.map(\.boundingBox)
            mutateSelected { $0.applyOneTouch(strength: value, forFace: index, of: boxes) }
        default:
            guard let scope = scope(for: beautyTarget) else { return }
            mutateSelected { $0.applyOneTouch(strength: value, in: scope) }
        }
    }

    @discardableResult
    func applyAutoSuggestion(_ suggestion: AutoEnhanceSuggestion) -> Bool {
        endSliderEditIfActive()
        let oneTouch = Policy.autoIncludesOneTouch && !faces.isEmpty ? EditingPolicy.oneTouchDefaultStrength : nil
        var applied = false
        mutateSelected { document in
            applied = document.applyAuto(suggestion, oneTouchStrength: oneTouch)
            return nil
        }
        return applied
    }
```

(`applyOneTouch(strength:)`는 드래그 중이면 `mutateSelected`가 연속 변경 안에서 돌아 한 단계가 된다 — `set`과 같은 길.)

- [ ] **Step 4: 통과 확인**

Run: Mac 앱 테스트 → 기준 +2, `TEST SUCCEEDED`. `cd apple && swift test` 불변. lint 출력 없음.

- [ ] **Step 5: 커밋**

```bash
git add apple/MellowPhoto/Application/AppModel.swift apple/MellowPhoto/Application/AppModel+Editing.swift apple/MellowPhoto/Application/AppModel+Looks.swift apple/MellowPhotoTests/AppModelTests.swift
git commit -m "feat(app): 원터치를 현재 대상(전체·그룹·사람)에 라우팅하고 강도 표시·세부 조정 접기 상태를 둠

자동 버튼은 Policy.autoIncludesOneTouch에 따라 얼굴이 있으면 원터치 기본 강도를 함께 적용한다.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 2: 화면 — OneTouchRow, 뷰티 패널 재구성, 꼬리표, 문구

**Files:**
- Create: `apple/MellowPhoto/Features/Editor/OneTouchRow.swift`
- Modify: `apple/MellowPhoto/Features/Editor/BeautyPanel.swift`, `apple/MellowPhoto/Features/Shared/AdjustmentSlider.swift`, `Theme.swift`, `apple/MellowPhoto/Application/UserMessage.swift`, `apple/MellowPhoto.xcodeproj`
- Create: `apple/MellowPhotoTests/OneTouchRowTests.swift`

- [ ] **Step 1: 실패하는 테스트 작성**

`apple/MellowPhotoTests/OneTouchRowTests.swift`:

```swift
import MellowShared
import XCTest

@testable import Mellow_Photo

@MainActor
final class OneTouchRowTests: XCTestCase {
    func testStrengthTextAndHintsFollowTheTarget() {
        XCTAssertEqual(OneTouchRow.strengthText(for: nil), UserMessage.strengthUnset)
        XCTAssertEqual(OneTouchRow.strengthText(for: 0.6), "0.60")
        XCTAssertEqual(OneTouchRow.hint(for: .all), UserMessage.oneTouchHintAll)
        XCTAssertEqual(OneTouchRow.hint(for: .gender(.male)), UserMessage.oneTouchHintGroup)
        XCTAssertEqual(OneTouchRow.hint(for: .face(0)), UserMessage.oneTouchHintPerson)
        XCTAssertEqual(OneTouchRow.hint(for: .person(PersonID())), UserMessage.oneTouchHintPerson)
        XCTAssertEqual(UserMessage.oneTouch, "원터치 보정")
        XCTAssertEqual(UserMessage.oneTouchStrength, "강도")
        XCTAssertEqual(UserMessage.oneTouchTag, "원터치")
        XCTAssertEqual(UserMessage.detailAdjustments, "세부 조정")
        XCTAssertEqual(UserMessage.strengthUnset, "—")
        XCTAssertEqual(UserMessage.assignGenderForOneTouch, "성별을 지정하면 남녀가 다르게 보정돼요")
        XCTAssertEqual(Theme.oneTouchButtonMinWidth, 96)
    }
}
```

- [ ] **Step 2: 실패 확인**

Run: Mac 앱 테스트 → 컴파일 실패(`OneTouchRow` 없음).

- [ ] **Step 3: 구현**

`UserMessage`:

```swift
    static let oneTouch = "원터치 보정"
    static let oneTouchStrength = "강도"
    static let oneTouchTag = "원터치"
    static let strengthUnset = "—"
    static let detailAdjustments = "세부 조정"
    static let oneTouchHintAll = "남성·여성으로 지정한 사람은 각 성별 표로, 미지정은 공통 표로 보정돼요. 성별은 사람 칩에서 지정해요."
    static let oneTouchHintGroup = "이 그룹의 표만 다시 써요. 다른 그룹과 전체는 그대로예요."
    static let oneTouchHintPerson = "이 사람에게 지정한 성별의 표를 써요. 미지정이면 공통 표예요."
    static let assignGenderForOneTouch = "성별을 지정하면 남녀가 다르게 보정돼요"
```

`Theme.oneTouchButtonMinWidth: CGFloat = 96`.

`AdjustmentSlider`: `var tag: String? = nil`. 제목 `Text(title)` 옆에 `if let tag { Text(tag).font(.caption2).padding(.horizontal, 4).background(Theme.accent.opacity(0.2), in: Capsule()) }`.

`OneTouchRow.swift`:

```swift
import MellowEditing
import MellowShared
import SwiftUI

/// 뷰티 패널의 원터치 줄: 버튼 + 강도 슬라이더 + 대상 안내. 표시가 없으면 손잡이는 0, 값 자리는 "—".
struct OneTouchRow: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 12) {
                    button
                    slider
                }
                VStack(alignment: .leading, spacing: 8) {
                    button
                    slider
                }
            }
            Text(Self.hint(for: model.beautyTarget)).font(.caption2).foregroundStyle(.secondary)
            if case .face = model.beautyTarget, model.personChips.first(where: { $0.target == model.beautyTarget })?.gender == nil {
                Text(UserMessage.assignGenderForOneTouch).font(.caption2).foregroundStyle(.secondary)
            }
        }
    }

    private var button: some View {
        Button {
            model.applyOneTouch()
        } label: {
            Label(UserMessage.oneTouch, systemImage: "wand.and.sparkles").frame(minWidth: Theme.oneTouchButtonMinWidth)
        }
        .buttonStyle(.borderedProminent)
        .tint(Theme.accent)
    }

    private var slider: some View {
        let strength = model.oneTouchStrength
        return VStack(spacing: 5) {
            HStack {
                Text(UserMessage.oneTouchStrength)
                Spacer()
                Text(Self.strengthText(for: strength)).monospacedDigit().foregroundStyle(.secondary)
            }
            .font(.caption)
            Slider(
                value: Binding(get: { strength ?? 0 }, set: { model.applyOneTouch(strength: $0) }),
                in: 0...OneTouchBundle.maximumStrength
            ) { editing in
                if editing {
                    model.beginSliderEdit()
                } else {
                    model.endSliderEdit()
                }
            }
            .accessibilityLabel(UserMessage.oneTouchStrength)
        }
    }

    static func strengthText(for strength: Double?) -> String {
        strength.map { String(format: "%.2f", $0) } ?? UserMessage.strengthUnset
    }

    static func hint(for target: AppModel.BeautyTarget) -> String {
        switch target {
        case .all: return UserMessage.oneTouchHintAll
        case .gender: return UserMessage.oneTouchHintGroup
        case .face, .person: return UserMessage.oneTouchHintPerson
        }
    }
}
```

`BeautyPanel`: `.ready`·`.noLandmarks` 분기 안을 다음 순서로 — `TargetChips()` → `OneTouchRow()` → `noLandmarksHint`(해당 시) → `DisclosureGroup(UserMessage.detailAdjustments, isExpanded: $model.showsDetailAdjustments) { 탭 피커 + switch }`. 세 탭의 묶인 키 슬라이더에 `tag: model.isOneTouchTagged(key) ? UserMessage.oneTouchTag : nil`을 넘긴다(피부 보정·자동 잡티 토글 옆에도 같은 꼬리표 `Text`). `cd apple && xcodegen generate --quiet`.

- [ ] **Step 4: 통과 확인**

Run: Mac 앱 테스트 → 기준 +3, `TEST SUCCEEDED`. lint 출력 없음. `cd apple && xcodegen generate --quiet && git diff --exit-code --stat MellowPhoto.xcodeproj` → 출력 없음.

- [ ] **Step 5: 커밋**

```bash
git add apple/MellowPhoto/Features/Editor/OneTouchRow.swift apple/MellowPhoto/Features/Editor/BeautyPanel.swift apple/MellowPhoto/Features/Shared/AdjustmentSlider.swift apple/MellowPhoto/Features/Shared/Theme.swift apple/MellowPhoto/Application/UserMessage.swift apple/MellowPhoto.xcodeproj apple/MellowPhotoTests/OneTouchRowTests.swift
git commit -m "feat(app): 뷰티 패널을 대상 칩 → 원터치 버튼·강도 → 세부 조정(접기)으로 재구성

원터치 줄은 현재 대상에 적용하고 그 층의 표시를 보인다. 묶인 세부 슬라이더에 원터치 꼬리표.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 3: 시나리오·문서·VALIDATION

**Files:**
- Modify: `apple/MellowPhotoTests/EditorScenarioTests.swift`
- Modify: `docs/architecture/modules.md`, `docs/superpowers/specs/2026-10-21-beauty-g4-one-touch-design.md`, `VALIDATION.md`

- [ ] **Step 1: 시나리오 테스트**

`EditorScenarioTests.swift`에 추가(기존 도우미 `previewBytes`·`exportedPixelSize`·`waitUntil`·`demoPortraitCopy`·`Self.demoFace` 사용):

```swift
    /// 원터치 → 강도 → 세부 조정에서 묶인 키 변경(꼬리표 해제) → 저장.
    func testOneTouchThenStrengthThenDetailOverrideThenExportSucceeds() async throws {
        let model = TestSupport.makeModel(
            root: root, analyzer: StubFaceAnalyzer(result: .success([Self.demoFace])),
            importer: FakeImporter(passesThroughFileURLs: true))
        await model.importFromFiles([try demoPortraitCopy()])
        try await waitUntil { model.isReady && model.preview != nil }
        model.selectTool(.beauty)
        let baseline = previewBytes(model)
        model.applyOneTouch()
        try await waitUntil { !model.isRendering && self.previewBytes(model) != baseline }
        XCTAssertEqual(model.oneTouchStrength, EditingPolicy.oneTouchDefaultStrength)
        let defaultBytes = previewBytes(model)
        model.beginSliderEdit()
        model.applyOneTouch(strength: 1)
        model.endSliderEdit()
        try await waitUntil { !model.isRendering && self.previewBytes(model) != defaultBytes }
        XCTAssertEqual(model.oneTouchStrength, 1)
        model.showsDetailAdjustments = true
        model.beginSliderEdit()
        model.edit(.skinRefinement(.darkCircles, 0.1))
        model.endSliderEdit()
        try await waitUntil { !model.isRendering }
        XCTAssertNil(model.oneTouchStrength, "세부 조정이 표시를 지운다")
        XCTAssertFalse(model.isOneTouchTagged(.skinRefinement(.darkCircles)))
        XCTAssertEqual(model.currentRecipe.people.groups[.female]?.oneTouch, 1, "그룹 표시는 남는다")
        model.undo()
        XCTAssertEqual(model.oneTouchStrength, 1, "실행 취소 한 번에 표시가 돌아온다")
        let size = try await exportedPixelSize(model)
        XCTAssertGreaterThan(size.width, 0)
        XCTAssertNil(model.presentedError)
    }
```

Run: Mac 앱 테스트 → 기준 +4, `TEST SUCCEEDED`.

- [ ] **Step 2: 문서**

- `docs/architecture/modules.md`: MellowShared 공개 API에 `OneTouchBundle`, 규칙에 "원터치 표는 `OneTouchBundle.Table` 한 곳(강도 1 = 상한, 기본 0.6), `oneTouch`는 렌더가 읽지 않는 표시". MellowEditing 규칙에 "`applyOneTouch(strength:in:)`는 전체 대상에서 전체 층·남성·여성 그룹 층·몸 피부를 한 단계로 쓰고, 묶인 키(`OneTouchBundle.keys`)를 손으로 바꾸면 그 층의 표시를 지우며, 동기화는 피부·눈입·메이크업을 모두 복사할 때만 표시를 복사, `applyAuto(_:oneTouchStrength:)`". 앱 타깃: `OneTouchRow`, `AppModel.Policy.autoIncludesOneTouch`, `showsDetailAdjustments`, 뷰티 패널 구성 순서.
- G4 스펙: 질문 2의 답을 결정 표 "자동" 행에 적고(권고/분리), 구현 중 바뀐 표 값·문구가 있으면 반영.

- [ ] **Step 3: 전체 검증과 VALIDATION**

Run: `export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer && ./scripts/test-apple.sh` → 종료 코드 0(로컬은 iOS 건너뜀, `MELLOW_IOS_TESTS` 금지).

`VALIDATION.md` 끝에 `## 인물 보정 G4 원터치 (2026-10-XX)`:
- 날짜·커밋·환경. "iOS 시뮬레이터·실기기는 하지 않았다(CI 요금 한도)".
- 자동 검증: 명령·종료 코드·테스트 수(모듈별·Mac).
- 원터치 실측(G4-2 Task 3 결과): 데모 여성·남성·공통의 기본 0.6과 최대 1에서 바뀐 비율·피부 평균 ΔY·질감 비·99백분위·색차·눈썹·얼굴 밖·입술, 커플 사진의 남녀 바뀐 비율. 상한에 걸려 내린 표 값이 있으면 이전 → 새 값.
- 자동 버튼 결정(질문 2)과 그 테스트.
- 자동 테스트가 확인하는 것(테스트 이름).
- 스펙과 다르게 한 것(없으면 "없음").
- 미검증: 실기기에서 남녀 차이·강도 슬라이더·세부 조정 접기·꼬리표·iPhone 폭의 원터치 줄, 저장본, CI iOS 테스트, 표 값 취향.
- "배포(릴리스 노트·태그·TestFlight)는 하지 않았다."

- [ ] **Step 4: 커밋**

```bash
git add apple/MellowPhotoTests/EditorScenarioTests.swift docs/architecture/modules.md docs/superpowers/specs/2026-10-21-beauty-g4-one-touch-design.md VALIDATION.md
git commit -m "docs: G4 원터치 시나리오·모듈 지도·검증 기록

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

## 자체 검토 결과

- **스펙 대조:** §3.4 자동 두 선택지 → Task 1 `Policy.autoIncludesOneTouch`와 두 테스트 중 하나. §4 화면(칩 → 원터치 줄 → 안내 → 세부 조정 접기, 꼬리표, 문구, `Theme`) → Task 1·2. §7.1 G4-3 행 → Task 1~3. §7.2 G4 VALIDATION → Task 3. §8 "G4-3 3 Task"와 같다.
- **타입 일관성:** `AppModel.Policy.autoIncludesOneTouch`·`showsDetailAdjustments`·`oneTouchStrength`·`applyOneTouch(strength:)`·`isOneTouchTagged`, `OneTouchRow.strengthText`·`hint`, `AdjustmentSlider(tag:)`, `UserMessage` 9개, `Theme.oneTouchButtonMinWidth`를 정의한 Task와 쓰는 Task에서 같게 썼다. 테스트 수: 앱 Mac +2 → +3 → +4.
- **Review Focus 매핑:** 1→Task 1, 2→Task 1·3, 3→Task 1, 4→Task 1, 5→Task 1. 모두 테스트 코드가 있다.
- **플레이스홀더 점검:** 질문 2의 답에 따른 두 테스트 중 하나를 지운다고 명시했다. "TBD/TODO/나중에" 없음.
