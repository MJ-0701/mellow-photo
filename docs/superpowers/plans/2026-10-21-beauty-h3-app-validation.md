# 인물 보정 H3 화면·생성 사진·검증 구현 계획

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 뷰티·메이크업 패널에 대상 칩(전체 · 남성 · 여성 · 사람 1…n · 찾지 못한 사람)과 사람 칩의 성별 메뉴·"이 대상 초기화"·"이 얼굴에 연결"·"삭제", 덮어쓴 슬라이더 표시와 재설정, 캔버스 얼굴 탭을 만든다. codex CLI로 가상 커플·단체 사진 세트와 정답 라벨을 만들어 저장소에 두고, 시나리오 테스트·모듈 지도·VALIDATION·전체 검증으로 H를 마친다.

**Architecture:** 앱은 H2의 `BeautyTarget` 위에 칩 모델(`PersonChip`)·성별 지정·재설정·연결·삭제·캔버스 탭을 `AppModel`에 두고, 화면은 `TargetChips`(새 파일) 하나가 칩과 메뉴를 그린다. 슬라이더는 `PortraitResolver`가 겹친 값을 보이고 `overriddenKeys`로 표시한다. 생성 사진은 `shared/fixtures/people/`(원본)과 테스트 타깃 사본 2장이며 라벨 JSON이 정답이다. 자동 테스트의 1차 근거는 기존 `SyntheticFace`이고 생성 사진은 시나리오·수동 확인·H4 측정용이다.

**Tech Stack:** SwiftUI + Observation, XCTest, codex-cli 0.158.0(`/Users/mj/.local/bin/codex`, image_generation), `sips`, XcodeGen 2.46.0.

**Spec:** `docs/superpowers/specs/2026-10-21-beauty-h-per-person-design.md` (H3에 해당하는 절: 1.6, 2의 앱·시나리오 행, 3, 4, 5). 선행: H1·H2 계획 전부 머지.

## 사람이 확인할 것

### G4 개정 (2026-10-21)

[G4 스펙](../specs/2026-10-21-beauty-g4-one-touch-design.md) 5절에 따라 이 계획의 제약을 고쳤다. 결정은 바뀌지 않았다.

- 기준 코드: main `74fb2df`(1.3.0 (8.1) TestFlight, G 머지됨). 브랜치 `beauty-g4`(worktree를 쓰면 `.claude/worktrees/beauty-g4`). `beauty-g-evoto`·`.claude/worktrees/beauty-g`는 더 쓰지 않는다.
- **iOS 시뮬레이터 테스트는 로컬에서 돌리지 않는다**(SpringBoard 오류 창이 사용자를 방해함). `MELLOW_IOS_TESTS`를 켜지 않는다. `./scripts/test-apple.sh`는 로컬에서 iOS를 건너뛰며 iOS 검증은 CI(사용자가 요금 한도를 푼 뒤)다.
- 실행 순서: G4-1 → H3 Task 1(생성 사진) → H1 → H2 → G4-2 → H3 Task 2·3 → G4-3 → H3 Task 4 → (승인 시) H4.
- Task 1의 생성 사진은 G4-2 `RealPeople`(테스트 지원)도 쓴다. `labels.json`의 `gender`는 `Gender.rawValue`(`male`·`female`)와 같아야 한다(이미 그렇다).
- Task 4의 VALIDATION H 절 뒤에 G4-3 Task 3이 G4 절을 더한다. 두 절 모두 "iOS 시뮬레이터는 CI"로 적는다.

- **순서(G4 개정).** Task 1 생성 사진 세트·라벨·README·테스트 타깃 사본은 **G4-1 직후, H1 앞에** 따로 실행한다(G4-2 수용 테스트가 커플 사진을 쓴다). Task 2 `AppModel`(칩 모델·성별·재설정·연결·삭제·캔버스 탭·legacy 연결) → 3 화면(`TargetChips`·성별 메뉴·슬라이더 표시·문구)은 G4-2 뒤, Task 4 시나리오·문서·VALIDATION·전체 검증은 G4-3 뒤. Task마다 Opus 구현 → 리뷰 → 수정, 끝에 전체 리뷰.
- **돈·시간·외부 효과가 있는 단계.** Task 1의 이미지 생성은 codex CLI(OpenAI 사용량)를 쓴다. 6~10장 규모. 푸시·태그·TestFlight는 없다.
- **스펙이 정하지 않아 이 계획이 정한 것.**

| 결정 | 이유 | 바꾸면 비용 |
|---|---|---|
| 생성 사진은 5장(커플 2·단체 3)을 목표로 하고, 눈 확인을 통과한 것만 남긴다. 시나리오 테스트는 `couple-01`·`group-01`만 쓴다 | 스펙 최소(커플 1·단체 1)를 넘기되 저장소 5 MB 상한 안. 두 장만 테스트 타깃에 복사 | 작음 |
| Vision이 라벨과 다른 얼굴 수를 내는 사진은 다시 만들거나 다른 사진으로 바꾼다. 테스트 단언을 약하게 하지 않는다 | 시나리오 테스트의 "얼굴 수 = 라벨 인원"은 사진의 쓸모를 보증하는 최소 조건 | 작음 |
| 칩 순서: 전체 · 남성 · 여성 · 사람 1…n(왼쪽부터) · 찾지 못한 기록(경고 아이콘). 사람 칩 라벨은 번호이고 성별 아이콘(`person`·`person.fill`·물음표)과 덮어쓰기 점을 붙인다 | 글자가 짧아 iPhone 폭에 맞고, 성별·덮어씀 상태가 한눈에 보인다 | 작음 |
| 성별 메뉴·초기화·연결·삭제는 칩의 `contextMenu`(iPhone은 길게 누르기)이고, 선택된 사람 칩에는 메뉴 단추를 따로 둔다((H3 리뷰 변경) 단추는 "…"가 아니라 현재 성별이 보이는 "성별: 미지정 ⌄" 글자 단추) | 길게 누르기를 모르는 사용자도 단추로 열 수 있다 | 작음 |
| 찾은 얼굴에 기록이 없을 때 "이 사람"에 룩을 적용하면 기록을 만들며 룩을 쓴다(`applyMakeupLook(_:forFace:of:)`, 체크포인트 한 번, 짝짓기는 렌더와 같음 — H2 구현 중 변경) | H2 Task 5의 임시 안내 문구를 없애고 스펙 "룩 적용은 체크포인트 한 번"을 지킨다. MellowEditing에 메서드 하나를 더한다 | 작음 |
| 캔버스 탭은 뷰티·메이크업 도구에서 탭 위치가 든 가장 작은 얼굴 상자를 고르고, 어느 얼굴도 아니면 전체로 돌아간다 | 겹친 얼굴에서 앞사람(작은 상자)이 우선 | 작음 |
| 슬라이더 덮어쓰기 표시는 제목 앞 작은 점(강조색)과 컨텍스트 메뉴 "재설정"(Mac은 제목 옆 x 단추). 상속 중인 값은 평소 모양 | 덮어쓴 것만 눈에 띄게 | 작음 |
| 생성 사진 README의 사용 조건은 "저장소 안 테스트·데모·수동 확인용, 가상 인물, 권리는 OpenAI 이용 약관에 따름(최종 확인은 사용자)" | 약관 해석은 에이전트가 단정하지 않는다 | 작음 |

- **범위 밖(다른 계획).** Core ML 추정기(H4). 추정 배지는 이번에 만들지만 H4 전까지 보일 일이 없다.
- **위험.** 이미지 생성 결과가 의도와 다를 수 있어(인원·성별·왜곡) 눈 확인을 필수로 둔다. Vision이 생성 얼굴에서 특징점을 다르게 줄 수 있다. 칩 줄이 iPhone 폭에서 가로 스크롤이 되는지는 실기기 확인(VALIDATION 미검증). 화면 품질은 자동 테스트로 판정할 수 없다.
- **사용자 조치.** Task 4 뒤 실제 커플·단체 사진으로 칩·성별 지정·그룹 값·개인 값·재설정·동기화 결과 확인. 생성 사진 README의 사용 조건 확인.

---

## 에이전트 참조

## Global Constraints

H1 계획의 Global Constraints를 그대로 따른다. 이 계획에서 다른 것:

- 시작 조건: H2 머지(`BeautyTarget`·임시 대상 피커·`PreparedPhoto.genders` 존재). 기준 테스트 수는 **시작 전에 실측해 이 줄에 적는다**(H1 Global Constraints 참고). 이 계획이 더하는 수는 **Rendering +2, Editing +1, 앱 Mac +7**(Task 1 Rendering +2, Task 2 Editing +1·Mac +4, Task 3 Mac +2, Task 4 Mac +1). 아래의 "Executed N tests"는 명목치(H2 끝 명목 403 → 406, Mac 78 → 85)이므로 실측 기준값에 같은 증분을 더해 읽는다.
- 앱 파일을 더하는 Task는 3(`TargetChips.swift`, 테스트 `TargetChipsTests.swift`)뿐이며 그 Task만 `cd apple && xcodegen generate --quiet`를 돌리고 `apple/MellowPhoto.xcodeproj`를 함께 커밋한다(`project.yml`은 고치지 않는다).
- Task 1의 생성 파일은 `shared/fixtures/people/`(JPEG 1024px, 장당 600 KB 이내, 합계 5 MB 이내, `labels.json`, `README.md`)과 `apple/Tests/MellowRenderingTests/Fixtures/people/`(`couple-01.jpg`, `group-01.jpg`, `labels.json`)뿐이다. 중간 PNG는 스크래치 폴더에 두고 저장소에 넣지 않는다. 다운로드·생성물은 새 빈 폴더에 두고 그 폴더 안에서 인터프리터를 실행하지 않는다.
- 생성 프롬프트에는 늘 "fictional people who do not resemble any real person or celebrity, no text, no watermark"를 넣는다. 실존 인물을 떠올리게 하는 결과는 버린다.
- `Theme` 새 상수(Task 3): `targetChipHeight` 30, `targetChipPadding` 10, `overrideDotSize` 6. `AppModel.Policy` 새 상수(Task 2): 없음(얼굴 상자 히트테스트는 상자 그대로).
- iOS 시뮬레이터 테스트는 로컬에서 돌리지 않는다(CI만, `MELLOW_IOS_TESTS` 금지). Task 4는 `./scripts/test-apple.sh`(로컬은 iOS 건너뜀)로 검증한다. Xcode를 열거나 앱·시뮬레이터를 띄우지 않는다.
- 패키지 테스트: `cd apple && swift test`. Mac 앱 테스트 명령은 H1과 같다.

## Review Focus

1. **라벨이 "남 1·여 1"인 커플 사진을 가져와 두 사람의 성별을 라벨대로 지정하고 여성 그룹에 피부 값을 넣는다.** 여성으로 지정한 얼굴만 바뀌고 사람 칩의 성별 아이콘이 바뀌어야 한다. → Task 4 시나리오.
2. **아직 기록이 없는 사람 칩을 고르고 룩을 적용한다.** 실행 취소 한 번에 기록이 사라져야 한다. → Task 2 `testUnmatchedPersonCanBeReboundOrRemovedAndLookAppliesToAFace`.
3. **옛 세션(legacyIndex 기록)을 열고 사진을 준비한다.** anchor가 채워지고 체크포인트는 생기지 않아야 한다. → Task 2 `testCanvasTapSelectsTheFaceAndLegacyPeopleAreBoundOnPrepare`.
4. **캔버스에서 겹친 두 얼굴 중 앞사람(작은 상자)을 탭한다.** 작은 상자의 사람이 대상이어야 한다. → Task 2 같은 테스트.
5. **찾지 못한 기록을 다른 얼굴에 연결한 뒤 그 얼굴을 지운다.** 연결은 체크포인트 한 번, 삭제 뒤 대상은 전체로. → Task 2 `testUnmatchedPersonCanBeReboundOrRemovedAndLookAppliesToAFace`.
6. **Vision이 `group-01`에서 라벨과 다른 얼굴 수를 낸다.** 테스트가 실패해야 하고(단언을 낮추지 않음), 사진을 바꾼다. → Task 1 `testVisionFindsTheLabelledNumberOfFaces`.

## 인터페이스 요약 (모든 Task가 공유하는 이름)

```swift
// 테스트 지원 (Task 1)
enum PeopleFixtures { static func url(_ name: String) -> URL; static func labels() throws -> PeopleLabels }   // Rendering 테스트 타깃
struct PeopleLabels: Decodable { version: Int; photos: [Photo]; struct Photo { file: String; people: [Person] }
    struct Person { gender: String; ageBand: String; glasses: Bool; pose: String; occlusion: String; ambiguous: Bool } }

// MellowEditing (Task 2)
EditDocument.applyMakeupLook(_ look: MakeupLook?, forFace index: Int, of faces: [NormalizedRect])   // 기록이 없으면 만들며 적용, 체크포인트 한 번

// 앱 (Task 2)
AppModel.PhotoInfo.genders: [Gender?]
AppModel.GenderSource { manual, estimated, none }
AppModel.PersonChip: Identifiable, Equatable { id: String; target: BeautyTarget; faceIndex: Int?; personID: PersonID?;
    gender: Gender?; source: GenderSource; overriddenCount: Int; isUnmatched: Bool }
AppModel.personChips: [PersonChip]
AppModel.effectiveGender(forFace:) -> Gender?, genderSource(forFace:) -> GenderSource
AppModel.scopedValues: PortraitResolver.Resolved, overriddenKeys: Set<PortraitKey>
AppModel.setGender(_:), resetOverrides(_: Set<PortraitKey>? = nil), rebindPerson(_:toFace:), removePerson(_:)
AppModel.touch(from:to:): .beauty·.makeup에서 얼굴 선택
TestSupport.makeModel(..., genderEstimator: StubGenderEstimator? = nil), StubGenderEstimator (앱 테스트)

// 앱 (Task 3)
struct TargetChips: View { static func title(for chip: PersonChip) -> String; static func symbolName(for chip: PersonChip) -> String }
struct PersonGenderMenu: View
AdjustmentSlider(title:value:range:snapsToZero:isOverridden:onReset:change:)
UserMessage.targetLabel, targetAll, genderMale, genderFemale, genderUnset, personOrdinal(_:), genderEstimated, genderManual,
    overrideReset, resetScope, personUnmatched, rebindPerson, rebindToFace(_:), removePerson, scopeHintGroup, scopeHintPerson,
    assignGenderHint
Theme.targetChipHeight, targetChipPadding, overrideDotSize
```

---

### Task 1: 생성 사진 세트 — codex CLI, 눈 확인, 라벨, README, 테스트 타깃 사본

**Files:**
- Create: `shared/fixtures/people/couple-01.jpg`, `couple-02.jpg`, `group-01.jpg`, `group-02.jpg`, `group-03.jpg`, `labels.json`, `README.md`
- Create: `apple/Tests/MellowRenderingTests/Fixtures/people/couple-01.jpg`, `group-01.jpg`, `labels.json`
- Create: `apple/Tests/MellowRenderingTests/PeopleFixturesTests.swift`
- Modify: `apple/Tests/MellowRenderingTests/RenderingTestSupport.swift` (`PeopleFixtures`·`PeopleLabels`)

**Interfaces:**
- Consumes: `VisionFaceAnalyzer`, `ImageLoader`.
- Produces: 인터페이스 요약의 Task 1 항목.

설계 근거: 스펙 3절. 어려운 경우(작은 얼굴·옆얼굴·가림·안경·피부톤·나이)가 적어도 한 번씩 들어가고, 모든 사진은 눈으로 확인한 뒤 라벨을 쓴다.

- [ ] **Step 1: 실패하는 테스트 작성**

`RenderingTestSupport.swift` 끝에 추가:

```swift
/// 생성 사진 세트의 정답 라벨(shared/fixtures/people/labels.json). people은 왼쪽부터.
struct PeopleLabels: Decodable {
    struct Person: Decodable {
        var gender: String
        var ageBand: String
        var glasses: Bool
        var pose: String
        var occlusion: String
        var ambiguous: Bool
    }

    struct Photo: Decodable {
        var file: String
        var people: [Person]
    }

    var version: Int
    var photos: [Photo]
}

/// 테스트 타깃에 복사한 생성 사진(couple-01·group-01)과 라벨.
enum PeopleFixtures {
    static func url(_ name: String) throws -> URL {
        try XCTUnwrap(Bundle.module.url(forResource: name, withExtension: nil, subdirectory: "Fixtures/people"))
    }

    static func labels() throws -> PeopleLabels {
        try JSONDecoder().decode(PeopleLabels.self, from: Data(contentsOf: url("labels.json")))
    }

    /// 저장소 원본 폴더. apple/Tests/MellowRenderingTests/RenderingTestSupport.swift → 네 단계 위가 저장소 루트.
    static var sharedFolder: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("shared/fixtures/people")
    }
}
```

`apple/Tests/MellowRenderingTests/PeopleFixturesTests.swift`:

```swift
import CoreImage
import MellowShared
import XCTest

@testable import MellowRendering

/// 생성 사진 세트(가상 인물)가 저장소 원본과 같고 라벨이 맞는지. 자동 테스트의 1차 근거는 SyntheticFace이고 이 사진은 시나리오·수동 확인·H4 측정용이다.
final class PeopleFixturesTests: XCTestCase {
    private static let copied = ["couple-01.jpg", "group-01.jpg"]
    private static let maximumBytesPerPhoto = 600 * 1024
    private static let maximumTotalBytes = 5 * 1024 * 1024
    private static let maximumLongSide = 1024

    func testPeopleFixturesMatchSharedCopiesAndLabelsDescribeEveryPhoto() throws {
        let labels = try PeopleFixtures.labels()
        XCTAssertEqual(labels.version, 1)
        let sharedLabels = try Data(contentsOf: PeopleFixtures.sharedFolder.appendingPathComponent("labels.json"))
        XCTAssertEqual(try Data(contentsOf: PeopleFixtures.url("labels.json")), sharedLabels, "라벨은 저장소 원본과 바이트가 같다")
        var total = 0
        for photo in labels.photos {
            let shared = PeopleFixtures.sharedFolder.appendingPathComponent(photo.file)
            let data = try Data(contentsOf: shared)
            total += data.count
            XCTAssertLessThanOrEqual(data.count, Self.maximumBytesPerPhoto, photo.file)
            XCTAssertGreaterThanOrEqual(photo.people.count, 2, "\(photo.file): 커플 이상")
            XCTAssertTrue(photo.people.allSatisfy { ["male", "female"].contains($0.gender) }, photo.file)
            let image = try XCTUnwrap(CIImage(contentsOf: shared))
            XCTAssertLessThanOrEqual(Int(max(image.extent.width, image.extent.height)), Self.maximumLongSide, photo.file)
            if Self.copied.contains(photo.file) {
                XCTAssertEqual(try Data(contentsOf: PeopleFixtures.url(photo.file)), data, "\(photo.file) 사본은 원본과 같다")
            }
        }
        XCTAssertLessThanOrEqual(total, Self.maximumTotalBytes)
        XCTAssertEqual(Set(labels.photos.map(\.file)).intersection(Self.copied).count, 2)
        let genders = labels.photos.flatMap(\.people).map(\.gender)
        XCTAssertTrue(genders.contains("male") && genders.contains("female"), "남녀가 섞여 있다")
        let coupleFiles = labels.photos.filter { $0.people.count == 2 }
        XCTAssertFalse(coupleFiles.isEmpty)
        XCTAssertTrue(coupleFiles.allSatisfy { Set($0.people.map(\.gender)) == ["male", "female"] }, "커플은 남 1·여 1")
        XCTAssertTrue(labels.photos.contains { $0.people.count >= 4 && $0.people.count <= 6 }, "단체 4~6명")
        let people = labels.photos.flatMap(\.people)
        XCTAssertTrue(people.contains(where: \.glasses), "안경 한 명 이상")
        XCTAssertTrue(people.contains { $0.pose != "frontal" }, "돌아간 얼굴 한 명 이상")
        XCTAssertTrue(people.contains { $0.occlusion != "none" }, "가림 한 명 이상")
        XCTAssertGreaterThanOrEqual(Set(people.map(\.ageBand)).count, 2, "나이대 둘 이상")
    }

    /// Vision이 라벨과 같은 얼굴 수를 찾아야 시나리오 테스트에 쓸 수 있다. 실패하면 단언을 낮추지 말고 사진을 다시 만든다.
    func testVisionFindsTheLabelledNumberOfFaces() throws {
        let labels = try PeopleFixtures.labels()
        for file in Self.copied {
            let photo = try XCTUnwrap(labels.photos.first { $0.file == file })
            let image = try ImageLoader().load(url: try PeopleFixtures.url(file), maxDimension: 1200)
            let faces = try VisionFaceAnalyzer().analyze(image)
            XCTAssertEqual(faces.count, photo.people.count, "\(file): Vision 얼굴 수가 라벨 인원과 같아야 한다")
            XCTAssertEqual(faces.map(\.boundingBox.minX), faces.map(\.boundingBox.minX).sorted(), "왼쪽부터 정렬")
        }
    }
}
```

- [ ] **Step 2: 실패 확인**

Run: `cd apple && swift test --filter PeopleFixturesTests` → 실패(`Fixtures/people/labels.json` 없음).

- [ ] **Step 3: 생성·확인·변환·라벨·README**

1. 스크래치 폴더에 새 빈 폴더 `people-raw/`를 만든다(세션 스크래치 디렉터리 아래). 생성물은 모두 여기에만 둔다.
2. codex CLI로 사진마다 한 번씩 생성한다. 기본 형태(플래그는 `codex exec --help`로 확인하고, 이미지 생성 도구가 켜져 있어야 한다):

```bash
/Users/mj/.local/bin/codex exec --cd <스크래치>/people-raw "Use the image generation tool to create ONE photorealistic photo and save it to ./couple-01.png. Content: a couple, one man and one woman, both adults, standing side by side facing the camera indoors in soft daylight, faces at least 10% of the image width, natural expressions. They are fictional people who do not resemble any real person or celebrity. No text, no watermark, no logos. Square 1024x1024."
```

사진별 내용(모두 "fictional people who do not resemble any real person or celebrity, no text, no watermark" 포함):
- `couple-01`: 남 1·여 1, 정면, 실내, 성인.
- `couple-02`: 남 1·여 1, 한 명은 안경, 한 명은 45° 측면, 야외 역광.
- `group-01`: 5명 남녀 혼합(남 2·여 3 또는 남 3·여 2), 피부톤 세 가지 이상, 20대~60대, 정면 위주, 한 줄로 서서.
- `group-02`: 6명, 한 명 옆얼굴(profile), 한 명 손이나 머리카락으로 얼굴 일부 가림, 나이대 섞임.
- `group-03`: 4명, 두 명이 앞뒤로 겹쳐 서서 뒷사람 얼굴 일부 가림, 한 명 안경.

codex가 파일을 쓰지 못하고 이미지를 응답에만 보이면 `codex:rescue` 스킬로 같은 요청을 보내 파일로 받는다. 어느 쪽이든 결과 파일이 `people-raw/`에 있는지 `ls -la`로 확인한다.

3. **눈 확인(필수).** 각 PNG를 Read 도구로 열어 (1) 인원 수가 의도와 같은지, (2) 왼쪽부터 각 사람의 성별이 분명한지(모호하면 다시 만들거나 라벨에 `"ambiguous": true`), (3) 손가락·얼굴 왜곡·글자·워터마크가 없는지, (4) 실존 인물·유명인을 떠올리게 하지 않는지 확인한다. 하나라도 어긋나면 프롬프트를 고쳐 다시 만든다. 확인 결과(사진별 인원·성별·특이점)를 Step 5 커밋 메시지 본문에 적는다.

4. 변환: `sips -Z 1024 -s format jpeg -s formatOptions 90 people-raw/couple-01.png --out shared/fixtures/people/couple-01.jpg`(사진마다). `du -k shared/fixtures/people/*.jpg`로 장당 600 KB 이내·합계 5 MB 이내를 확인하고 넘으면 `formatOptions`를 85로 낮춘다. `sips -g pixelWidth -g pixelHeight`로 긴 변 1024 확인.

5. `shared/fixtures/people/labels.json`(사람은 왼쪽부터, 눈 확인 결과대로):

```json
{
  "version": 1,
  "photos": [
    { "file": "couple-01.jpg", "people": [
        { "gender": "male",   "ageBand": "adult", "glasses": false, "pose": "frontal", "occlusion": "none", "ambiguous": false },
        { "gender": "female", "ageBand": "adult", "glasses": false, "pose": "frontal", "occlusion": "none", "ambiguous": false } ] },
    { "file": "couple-02.jpg", "people": [ … ] },
    { "file": "group-01.jpg", "people": [ … ] },
    { "file": "group-02.jpg", "people": [ … ] },
    { "file": "group-03.jpg", "people": [ … ] }
  ]
}
```

`ageBand`는 `child`·`young`·`adult`·`senior`, `pose`는 `frontal`·`turned`·`profile`, `occlusion`은 `none`·`partial`. 값은 실제 사진을 보고 적는다(위의 `…`는 실제 값으로 채운다).

6. `shared/fixtures/people/README.md`: 제목 "생성 사진 세트(가상 인물)", 생성 도구(codex-cli 0.158.0, OpenAI 이미지 생성 도구)·날짜·프롬프트 요지(사진별 한 줄)·"모든 인물은 가상이며 실존 인물과 무관하다"·용도(저장소 안 자동 시나리오 테스트·수동 확인·H4 성별 추정 정확도 측정)·사용 조건("생성물의 권리와 사용 조건은 OpenAI 이용 약관을 따른다. 저장소 밖 배포·마케팅에 쓰지 않는다. 최종 확인은 사용자 조치")·라벨 형식 설명·"Vision이 생성 얼굴에서 실사진과 다르게 동작할 수 있어 자동 테스트의 1차 근거는 `SyntheticFace`다".

7. 테스트 타깃 사본: `mkdir -p apple/Tests/MellowRenderingTests/Fixtures/people && cp shared/fixtures/people/{couple-01.jpg,group-01.jpg,labels.json} apple/Tests/MellowRenderingTests/Fixtures/people/`.

- [ ] **Step 4: 통과 확인**

Run: `cd apple && swift test --filter PeopleFixturesTests` → `Executed 2 tests, with 0 failures`. `testVisionFindsTheLabelledNumberOfFaces`가 실패하면 그 사진을 다시 만들어(3~7 반복) 통과시킨다. 전체: `cd apple && swift test` → Rendering 265, 나머지 불변. lint 출력 없음.

- [ ] **Step 5: 커밋**

```bash
git add shared/fixtures/people apple/Tests/MellowRenderingTests/Fixtures/people apple/Tests/MellowRenderingTests/PeopleFixturesTests.swift apple/Tests/MellowRenderingTests/RenderingTestSupport.swift
git commit -m "test(fixtures): codex로 만든 가상 커플·단체 사진 5장과 성별 라벨

커플 2·단체 3(4~6명), 피부톤·나이·안경·옆얼굴·가림 포함. 눈으로 인원·성별 확인:
<사진별 인원·성별·특이점 한 줄씩>
1024px JPEG 합계 <N> KB. 테스트 타깃에는 couple-01·group-01만 복사.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 2: AppModel — 칩 모델, 성별 지정, 재설정, 연결·삭제, 캔버스 얼굴 탭, legacy 연결

**Files:**
- Modify: `apple/Sources/MellowEditing/API/EditDocument.swift` (`applyMakeupLook(_:forFace:of:)`)
- Modify: `apple/MellowPhoto/Application/AppModel.swift`, `AppModel+Editing.swift`, `AppModel+Library.swift`
- Modify: `apple/MellowPhotoTests/TestSupport.swift`
- Test: `apple/Tests/MellowEditingTests/EditDocumentTests.swift`, `apple/MellowPhotoTests/AppModelTests.swift`

**Interfaces:**
- Consumes: H2의 `BeautyTarget`·`scope(for:)`·`anchor(forFace:)`·`targetedFaces`, `PersonMatcher.match`, `PortraitResolver`, `PreparedPhoto.genders`.
- Produces: 인터페이스 요약의 Task 2 항목.

- [ ] **Step 1: 실패하는 테스트 작성**

`EditDocumentTests.swift` 끝에 추가:

```swift
    // twoFaces는 H2가 EditDocumentTests에 둔 두 얼굴 상자(중심 x 0.3·0.7)다.
    func testLookForAFaceWithoutARecordCreatesItInOneStep() {
        let look = MakeupLook(
            id: "daily", name: "데일리", lip: MakeupTint(colorID: "lip-coral", intensity: 0.5),
            blush: MakeupTint(colorID: "blush-peach", intensity: 0.3),
            eyeshadow: MakeupTint(colorID: "shadow-brown", intensity: 0.2), brow: MakeupStrength(intensity: 0.4),
            contour: MakeupStrength(intensity: 0.1))
        var document = EditDocument()
        document.applyMakeupLook(look, forFace: 0, of: twoFaces)
        XCTAssertEqual(document.undoStack.count, 1)
        XCTAssertEqual(document.recipe.people.individuals.count, 1)
        XCTAssertEqual(document.recipe.people.individuals[0].layer.makeupLookID, "daily")
        XCTAssertEqual(document.recipe.people.individuals[0].layer.makeup[.lip], MakeupTint(colorID: "lip-coral", intensity: 0.5))
        document.applyMakeupLook(look, forFace: 0, of: twoFaces)
        XCTAssertEqual(document.undoStack.count, 1, "같은 룩은 단계를 만들지 않는다")
        document.undo()
        XCTAssertTrue(document.recipe.people.individuals.isEmpty)
    }
```

`TestSupport.swift`: `StubGenderEstimator`를 더하고 `makeModel`에 `genderEstimator: StubGenderEstimator? = nil` 인자를 넣어 `PhotoPipeline(..., genderEstimator: genderEstimator, ...)`로 넘긴다.

```swift
struct StubGenderEstimator: GenderEstimator {
    var result: Result<[GenderEstimate?], MellowError> = .success([])

    func estimate(_ image: CIImage, faces: [FaceGeometry]) throws -> [GenderEstimate?] { try result.get() }
}
```

`AppModelTests.swift` 끝에 추가:

```swift
    private func twoFaces() -> [FaceGeometry] {
        [
            TestSupport.landmarkedFace(in: NormalizedRect(x: 0.05, y: 0.3, width: 0.35, height: 0.4)),
            TestSupport.landmarkedFace(in: NormalizedRect(x: 0.55, y: 0.3, width: 0.35, height: 0.4)),
        ]
    }

    func testPersonChipsReflectEstimatesManualGenderAndOverrides() async throws {
        let staged = try TestSupport.solidPNG(in: root)
        let faces = twoFaces()
        let model = TestSupport.makeModel(
            root: root, analyzer: StubFaceAnalyzer(result: .success(faces)),
            genderEstimator: StubGenderEstimator(result: .success([GenderEstimate(gender: .female, confidence: 0.9), nil])),
            importer: FakeImporter(staged: [.success(StagedPhoto(url: staged, displayName: nil))]))
        try await importOne(model, staged)
        XCTAssertEqual(model.selectedInfo?.genders, [.female, nil])
        var chips = model.personChips
        XCTAssertEqual(chips.map(\.faceIndex), [0, 1])
        XCTAssertEqual(chips[0].gender, .female)
        XCTAssertEqual(chips[0].source, .estimated)
        XCTAssertEqual(chips[1].source, .none)
        XCTAssertEqual(chips.map(\.overriddenCount), [0, 0])
        XCTAssertEqual(model.effectiveGender(forFace: 0), .female)
        model.setBeautyTarget(.face(1))
        model.setGender(.male)
        chips = model.personChips
        XCTAssertEqual(chips[1].gender, .male)
        XCTAssertEqual(chips[1].source, .manual)
        XCTAssertNotNil(chips[1].personID)
        XCTAssertEqual(model.session.selected?.document.undoStack.count, 1)
        model.setBeautyTarget(.face(0))
        model.setGender(.male)
        XCTAssertEqual(model.personChips[0].source, .manual, "추정 위에 수동 지정")
        XCTAssertEqual(model.effectiveGender(forFace: 0), .male)
        model.setBeautyTarget(.gender(.male))
        model.beginSliderEdit()
        model.edit(.skinSmoothing(0.6))
        model.endSliderEdit()
        XCTAssertEqual(model.scopedValues.portrait.skin.smoothing, 0.6)
        XCTAssertEqual(model.overriddenKeys, [.skinSmoothing])
        model.setBeautyTarget(.face(1))
        XCTAssertEqual(model.scopedValues.portrait.skin.smoothing, 0.6, "남성 그룹 값을 상속한다")
        XCTAssertEqual(model.overriddenKeys, [], "상속 중이라 덮어쓴 키가 없다")
        model.edit(.faceShape(.width, -0.3))
        XCTAssertEqual(model.overriddenKeys, [.faceShape(.width)])
        XCTAssertEqual(model.personChips[1].overriddenCount, 1)
        model.setBeautyTarget(.all)
        XCTAssertEqual(model.scopedValues.portrait.skin.smoothing, 0, "전체 층은 그룹 값을 모른다")
        XCTAssertEqual(model.overriddenKeys, [])
        try await waitUntil { !model.isRendering }
        XCTAssertNil(model.presentedError)
    }

    func testGenderAndResetAreRoutedToTheCurrentTargetAndUndoOneStep() async throws {
        let staged = try TestSupport.solidPNG(in: root)
        let faces = twoFaces()
        let model = TestSupport.makeModel(
            root: root, analyzer: StubFaceAnalyzer(result: .success(faces)),
            importer: FakeImporter(staged: [.success(StagedPhoto(url: staged, displayName: nil))]))
        try await importOne(model, staged)
        model.setBeautyTarget(.all)
        model.setGender(.female)
        XCTAssertTrue(model.currentRecipe.people.individuals.isEmpty, "전체·그룹 대상에서는 성별 지정이 없다")
        XCTAssertFalse(model.canUndo)
        model.setBeautyTarget(.gender(.female))
        model.edit(.skinSmoothing(0.5))
        model.edit(.feature(.eyeBrighten, 0.4))
        XCTAssertEqual(model.overriddenKeys, [.skinSmoothing, .feature(.eyeBrighten)])
        model.resetOverrides([.skinSmoothing])
        XCTAssertEqual(model.overriddenKeys, [.feature(.eyeBrighten)])
        XCTAssertEqual(model.session.selected?.document.undoStack.count, 3)
        model.resetOverrides()
        XCTAssertEqual(model.overriddenKeys, [])
        XCTAssertNil(model.currentRecipe.people.groups[.female])
        model.undo()
        XCTAssertEqual(model.overriddenKeys, [.feature(.eyeBrighten)])
        model.setBeautyTarget(.face(0))
        model.resetOverrides()
        XCTAssertEqual(model.session.selected?.document.undoStack.count, 3, "기록이 없는 얼굴의 초기화는 아무것도 안 한다")
        model.edit(.faceShape(.width, -0.2))
        model.tool = .retouch
        model.touch(from: NormalizedPoint(x: 0.5, y: 0.1), to: NormalizedPoint(x: 0.5, y: 0.1))
        model.touch(from: NormalizedPoint(x: 0.52, y: 0.1), to: NormalizedPoint(x: 0.52, y: 0.1))
        try await waitUntil { !model.isRendering }
        XCTAssertTrue(model.isGeometryLocked)
        model.setGender(.male)
        XCTAssertEqual(model.statusMessage, UserMessage.geometryLocked, "잠긴 사진의 성별 변경은 안내만")
        XCTAssertNil(model.personChips[0].gender)
    }

    func testCanvasTapSelectsTheFaceAndLegacyPeopleAreBoundOnPrepare() async throws {
        let staged = try TestSupport.solidPNG(in: root)
        let big = TestSupport.landmarkedFace(in: NormalizedRect(x: 0.1, y: 0.1, width: 0.6, height: 0.7))
        let small = TestSupport.landmarkedFace(in: NormalizedRect(x: 0.4, y: 0.3, width: 0.2, height: 0.25))
        let store = MemorySessionStore()
        let model = TestSupport.makeModel(
            root: root, analyzer: StubFaceAnalyzer(result: .success([big, small])),
            importer: FakeImporter(staged: [.success(StagedPhoto(url: staged, displayName: nil))]), store: store)
        try await importOne(model, staged)
        model.selectTool(.beauty)
        model.touch(from: NormalizedPoint(x: 0.5, y: 0.4), to: NormalizedPoint(x: 0.5, y: 0.4))
        XCTAssertEqual(model.beautyTarget, .face(1), "겹친 영역은 작은 상자(앞사람)")
        model.touch(from: NormalizedPoint(x: 0.15, y: 0.15), to: NormalizedPoint(x: 0.15, y: 0.15))
        XCTAssertEqual(model.beautyTarget, .face(0))
        model.touch(from: NormalizedPoint(x: 0.95, y: 0.95), to: NormalizedPoint(x: 0.95, y: 0.95))
        XCTAssertEqual(model.beautyTarget, .all, "얼굴 밖은 전체")
        model.selectTool(.makeup)
        model.touch(from: NormalizedPoint(x: 0.5, y: 0.4), to: NormalizedPoint(x: 0.5, y: 0.4))
        XCTAssertEqual(model.beautyTarget, .face(1))
        XCTAssertFalse(model.canUndo, "대상 선택은 편집이 아니다")
        model.selectTool(.adjust)
        model.touch(from: NormalizedPoint(x: 0.15, y: 0.15), to: NormalizedPoint(x: 0.15, y: 0.15))
        XCTAssertEqual(model.beautyTarget, .face(1), "다른 도구에서는 바뀌지 않는다")

        var legacy = EditRecipe()
        legacy.people.individuals = [
            PersonRecord(id: .legacy(index: 1), legacyIndex: 1, layer: PortraitLayer(skinSmoothing: 0.4))
        ]
        let id = model.session.photos[0].id
        let filename = model.session.photos[0].filename
        store.saved = SessionSnapshot(
            photos: [PhotoEntry(id: id, filename: filename, displayName: "옛", document: EditDocument(recipe: legacy))],
            selectedPhotoID: id, presets: [])
        let reopened = TestSupport.makeModel(
            root: root, analyzer: StubFaceAnalyzer(result: .success([big, small])), store: store)
        await reopened.restore()
        try await waitUntil { reopened.isReady && reopened.preview != nil }
        let bound = try XCTUnwrap(reopened.currentRecipe.people.individuals.first)
        XCTAssertEqual(bound.anchor, PersonAnchor(faceBox: small.boundingBox), "준비 뒤 legacy 기록에 anchor가 채워진다")
        XCTAssertNil(bound.legacyIndex)
        XCTAssertFalse(reopened.canUndo, "연결은 체크포인트가 아니다")
        XCTAssertEqual(reopened.personChips[1].personID, bound.id)
        XCTAssertEqual(reopened.personChips[1].overriddenCount, 1)
    }

    func testUnmatchedPersonCanBeReboundOrRemovedAndLookAppliesToAFace() async throws {
        let staged = try TestSupport.solidPNG(in: root)
        let faces = twoFaces()
        let model = TestSupport.makeModel(
            root: root, analyzer: StubFaceAnalyzer(result: .success(faces)),
            importer: FakeImporter(staged: [.success(StagedPhoto(url: staged, displayName: nil))]))
        try await importOne(model, staged)
        let strayID = PersonID()
        model.session.edit(model.session.photos[0].id) { document in
            // 사진의 어느 얼굴과도 짝이 되지 않는 상자(중심 0.5·0.97, 폭 0.03)에 기록을 만든다.
            let stray = NormalizedRect(x: 0.485, y: 0.955, width: 0.03, height: 0.03)
            document.set(.skinSmoothing(0.8), forFace: 0, of: [stray])
            return nil
        }
        let stray = try XCTUnwrap(model.currentRecipe.people.individuals.first)
        _ = strayID
        var chips = model.personChips
        XCTAssertEqual(chips.count, 3)
        XCTAssertTrue(chips[2].isUnmatched)
        XCTAssertEqual(chips[2].personID, stray.id)
        XCTAssertEqual(chips[2].target, .person(stray.id))
        model.setBeautyTarget(.person(stray.id))
        XCTAssertEqual(model.scopedValues.portrait.skin.smoothing, 0.8)
        XCTAssertEqual(model.faceAvailability, .ready, "짝이 없는 사람은 얼굴이 없지만 분석 실패가 아니다")
        model.rebindPerson(stray.id, toFace: 0)
        chips = model.personChips
        XCTAssertEqual(chips.count, 2)
        XCTAssertEqual(chips[0].personID, stray.id)
        XCTAssertEqual(model.beautyTarget, .face(0), "연결한 얼굴이 대상이 된다")
        XCTAssertEqual(model.session.selected?.document.undoStack.count, 2)
        model.removePerson(stray.id)
        XCTAssertTrue(model.currentRecipe.people.individuals.isEmpty)
        XCTAssertEqual(model.beautyTarget, .all)
        model.setBeautyTarget(.face(1))
        model.applyMakeupLook(id: "daily")
        XCTAssertEqual(model.currentRecipe.people.individuals.count, 1, "기록이 없던 얼굴에 룩을 적용하면 기록이 생긴다")
        XCTAssertEqual(model.scopedValues.makeup.lookID, "daily")
        XCTAssertEqual(model.currentRecipe.makeup, MakeupAdjustments(), "전체 층은 그대로")
        model.undo()
        XCTAssertTrue(model.currentRecipe.people.individuals.isEmpty, "실행 취소 한 번에 기록이 사라진다")
    }
```

(`XCTAssertEqual(model.faceAvailability, .ready, …)` 줄은 `targetedFaces`가 빈 배열이면 `.noLandmarks`가 아니라 `.ready`여야 한다는 뜻이다 — `lacksLandmarks`는 `!targets.isEmpty &&`로 이미 그렇게 계산한다.)

- [ ] **Step 2: 실패 확인**

Run: Mac 앱 테스트 → 컴파일 실패(`personChips` 없음). `cd apple && swift test --filter EditDocumentTests` → 컴파일 실패(`applyMakeupLook(_:forFace:of:)` 없음).

- [ ] **Step 3: 구현**

`EditDocument.swift`에 추가:

```swift
    /// faces[index]와 짝이 된 사람에게 룩을 적용한다.
    /// 기록이 없으면 그 얼굴 anchor로 만들며 적용한다(체크포인트 한 번).
    /// 짝짓기는 set(_:forFace:of:)·렌더와 같다.
    /// 같은 값이면 아무것도 하지 않는다.
    public mutating func applyMakeupLook(_ look: MakeupLook?, forFace faceIndex: Int, of faces: [NormalizedRect]) {
        guard faces.indices.contains(faceIndex) else { return }
        var updated = recipe
        let id =
            updated.people.personID(forFace: faceIndex, of: faces)
            ?? Self.appendPerson(at: PersonAnchor(faceBox: faces[faceIndex]), to: &updated)
        guard var layer = PortraitResolver.layer(updated, scope: .person(id)) else { return }
        let adjustments = look?.adjustments ?? MakeupAdjustments()
        for part in MakeupPart.allCases {
            layer.makeup[part] = Self.inherited(part, from: adjustments)
        }
        layer.makeupLookID = look?.id
        Self.store(layer, in: &updated, scope: .person(id))
        updated.people.prune()
        guard updated != recipe else { return }
        checkpoint()
        recipe = updated
    }
```

`AppModel.swift`:
- `PhotoInfo`에 `var genders: [Gender?] = []`. `remember(_:_:)`에 `genders: prepared.genders`를 넘기고, 마지막에 legacy 연결:

```swift
        session.edit(id) { document in
            _ = document.bindLegacyPeople(faces: prepared.faces.map(\.boundingBox))
            return nil
        }
```

(`session.edit`는 저장을 일으킨다. 바뀐 것이 없어도 한 번 쓰므로 `bindLegacyPeople`이 false면 건너뛰도록 먼저 `document`를 읽어 legacy 기록이 있는지 확인한다: `guard session.photos[index].document.recipe.people.individuals.contains(where: { $0.anchor == nil }) else { return }`.)

- 칩 모델:

```swift
    enum GenderSource: Equatable {
        case manual
        case estimated
        case none
    }

    /// 대상 칩 하나. 찾은 얼굴(기록 유무 무관)과 짝이 없는 기록.
    struct PersonChip: Identifiable, Equatable {
        let id: String
        let target: BeautyTarget
        let faceIndex: Int?
        let personID: PersonID?
        let gender: Gender?
        let source: GenderSource
        let overriddenCount: Int
        var isUnmatched: Bool { faceIndex == nil }
    }

    /// 선택 사진의 사람 기록과 얼굴의 짝.
    var personMatches: [PersonMatcher.Match] {
        PersonMatcher.match(currentRecipe.people.individuals, faces: faces.map(\.boundingBox))
    }

    func effectiveGender(forFace index: Int) -> Gender? {
        let record = personMatches.first { $0.faceIndex == index }.flatMap { currentRecipe.people.person($0.person) }
        return PortraitResolver.effectiveGender(person: record, estimate: estimatedGender(forFace: index))
    }

    func genderSource(forFace index: Int) -> GenderSource {
        let record = personMatches.first { $0.faceIndex == index }.flatMap { currentRecipe.people.person($0.person) }
        if record?.gender != nil {
            return .manual
        }
        return estimatedGender(forFace: index) == nil ? .none : .estimated
    }

    private func estimatedGender(forFace index: Int) -> Gender? {
        let genders = selectedInfo?.genders ?? []
        return genders.indices.contains(index) ? genders[index] : nil
    }

    /// 왼쪽부터 찾은 얼굴, 그 뒤 짝이 없는 기록.
    var personChips: [PersonChip] {
        let recipe = currentRecipe
        let matches = personMatches
        var chips = faces.indices.map { index -> PersonChip in
            let record = matches.first { $0.faceIndex == index }.flatMap { recipe.people.person($0.person) }
            return PersonChip(
                id: "face-\(index)", target: .face(index), faceIndex: index, personID: record?.id,
                gender: effectiveGender(forFace: index), source: genderSource(forFace: index),
                overriddenCount: record?.layer.overriddenKeys.count ?? 0)
        }
        let matched = Set(matches.map(\.person))
        for record in recipe.people.individuals where !matched.contains(record.id) {
            chips.append(
                PersonChip(
                    id: "person-\(record.id.rawValue.uuidString)", target: .person(record.id), faceIndex: nil,
                    personID: record.id, gender: record.gender, source: record.gender == nil ? .none : .manual,
                    overriddenCount: record.layer.overriddenKeys.count))
        }
        return chips
    }

    /// 현재 대상에서 슬라이더가 보일 값(전체 → 그룹 → 개인을 겹친 것).
    var scopedValues: PortraitResolver.Resolved {
        let recipe = currentRecipe
        switch beautyTarget {
        case .face(let index):
            if let scope = scope(for: .face(index)) {
                return PortraitResolver.resolve(recipe, scope: scope, estimate: estimatedGender(forFace: index))
            }
            return PortraitResolver.resolve(recipe, person: nil, gender: estimatedGender(forFace: index))
        default:
            return PortraitResolver.resolve(recipe, scope: scope(for: beautyTarget) ?? .all, estimate: nil)
        }
    }

    /// 현재 대상 층에서 덮어쓴 키. 기록이 없는 얼굴·전체는 빈 집합.
    var overriddenKeys: Set<PortraitKey> {
        scope(for: beautyTarget).map { PortraitResolver.overriddenKeys(currentRecipe, scope: $0) } ?? []
    }
```

`AppModel+Editing.swift`:

```swift
    /// 현재 대상(얼굴 또는 찾지 못한 사람)의 성별을 지정한다. 전체·그룹 대상에서는 아무것도 하지 않는다.
    func setGender(_ gender: Gender?) {
        switch beautyTarget {
        case .face, .person: edit(.gender(gender))
        case .all, .gender: return
        }
    }

    /// 현재 대상 층에서 keys를 상속으로 되돌린다(nil이면 층 전체). 기록이 없는 얼굴은 아무것도 하지 않는다.
    func resetOverrides(_ keys: Set<PortraitKey>? = nil) {
        guard let scope = scope(for: beautyTarget) else { return }
        endSliderEditIfActive()
        mutateSelected { $0.resetOverrides(keys, in: scope) }
    }

    /// 찾지 못한 기록을 얼굴에 연결하고 그 얼굴을 대상으로 한다.
    func rebindPerson(_ id: PersonID, toFace index: Int) {
        guard let anchor = anchor(forFace: index) else { return }
        endSliderEditIfActive()
        mutateSelected { $0.rebindPerson(id, to: anchor) }
        setBeautyTarget(.face(index))
    }

    func removePerson(_ id: PersonID) {
        endSliderEditIfActive()
        mutateSelected { $0.removePerson(id) }
        if case .person(id) = beautyTarget {
            setBeautyTarget(.all)
        }
    }
```

`applyMakeupLook(id:)`를 대상별로 바꾼다: `.face(index)`면 `document.applyMakeupLook(look, forFace: index, of: faces.map(\.boundingBox))`, 그 외는 `document.applyMakeupLook(look, in: scope(for: beautyTarget) ?? .all)`. H2 Task 5의 `pickASliderFirst` 분기와 문구를 지운다.

`touch(from:to:)`의 `switch tool`에 `.beauty, .makeup` 분기를 추가하고 `case .look, .crop, .adjust, .body, .background: return`으로 나머지를 정리한다:

```swift
        case .beauty, .makeup:
            let hit = faces.indices
                .filter { faces[$0].boundingBox.cgRect.contains(CGPoint(x: toOriginal.x, y: toOriginal.y)) }
                .min { faces[$0].boundingBox.width * faces[$0].boundingBox.height < faces[$1].boundingBox.width * faces[$1].boundingBox.height }
            setBeautyTarget(hit.map(BeautyTarget.face) ?? .all)
```

`touch`의 첫 guard(`!isRendering`)는 대상 선택에는 과하지만 그대로 둔다(기존 테스트가 `waitUntil { !model.isRendering }` 뒤에 탭한다). `EditorTool.usesCanvasTouch`가 `.beauty`·`.makeup`에서 true를 돌려주도록 고친다(캔버스가 탭 층을 그려야 한다).

- [ ] **Step 4: 통과 확인**

Run: `cd apple && swift test` → Editing 44, 나머지 불변(패키지 406). Mac 앱 테스트 → `Executed 82 tests, with 0 failures`. lint 출력 없음. `./scripts/verify-modules.sh` 통과.

- [ ] **Step 5: 커밋**

```bash
git add apple/Sources/MellowEditing/API/EditDocument.swift apple/Tests/MellowEditingTests/EditDocumentTests.swift apple/MellowPhoto/Application/AppModel.swift apple/MellowPhoto/Application/AppModel+Editing.swift apple/MellowPhoto/Application/AppModel+Library.swift apple/MellowPhoto/Application/EditorTool.swift apple/MellowPhotoTests/TestSupport.swift apple/MellowPhotoTests/AppModelTests.swift
git commit -m "feat(app): 사람 칩 모델, 성별 지정, 층 재설정, 사람 연결·삭제, 캔버스 얼굴 탭

추정·수동·미지정 출처와 덮어쓴 키 수를 칩으로 묶고, 준비 뒤 legacy 기록에 anchor를 채운다.
기록 없는 얼굴에 룩을 적용하면 기록을 만들며 한 단계로 적용한다.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 3: 화면 — TargetChips, 성별 메뉴, 덮어쓴 슬라이더 표시, 문구

**Files:**
- Create: `apple/MellowPhoto/Features/Editor/TargetChips.swift`
- Modify: `apple/MellowPhoto/Features/Shared/AdjustmentSlider.swift`, `apple/MellowPhoto/Features/Shared/Theme.swift`, `apple/MellowPhoto/Features/Editor/BeautyPanel.swift`, `MakeupPanel.swift`, `apple/MellowPhoto/Application/UserMessage.swift`, `apple/MellowPhoto.xcodeproj`
- Test: `apple/MellowPhotoTests/TargetChipsTests.swift` (새 파일), `apple/MellowPhotoTests/AppModelTests.swift`

**Interfaces:**
- Consumes: Task 2의 `personChips`·`scopedValues`·`overriddenKeys`·`setGender`·`resetOverrides`·`rebindPerson`·`removePerson`.
- Produces: 인터페이스 요약의 Task 3 항목.

- [ ] **Step 1: 실패하는 테스트 작성**

`apple/MellowPhotoTests/TargetChipsTests.swift`:

```swift
import MellowShared
import XCTest

@testable import Mellow_Photo

@MainActor
final class TargetChipsTests: XCTestCase {
    private func chip(
        face: Int? = 0, gender: Gender? = nil, source: AppModel.GenderSource = .none, overrides: Int = 0
    ) -> AppModel.PersonChip {
        AppModel.PersonChip(
            id: face.map { "face-\($0)" } ?? "person-x", target: face.map(AppModel.BeautyTarget.face) ?? .person(PersonID()),
            faceIndex: face, personID: nil, gender: gender, source: source, overriddenCount: overrides)
    }

    func testChipTitlesAndSymbolsFollowGenderSourceAndMatching() {
        XCTAssertEqual(TargetChips.title(for: chip(face: 0)), "1")
        XCTAssertEqual(TargetChips.title(for: chip(face: 4)), "5")
        XCTAssertEqual(TargetChips.title(for: chip(face: nil)), UserMessage.personUnmatched)
        XCTAssertEqual(TargetChips.symbolName(for: chip(gender: nil)), "person.crop.circle.badge.questionmark")
        XCTAssertEqual(TargetChips.symbolName(for: chip(gender: .male, source: .manual)), "person.crop.circle.fill")
        XCTAssertEqual(TargetChips.symbolName(for: chip(gender: .female, source: .estimated)), "person.crop.circle")
        XCTAssertEqual(TargetChips.symbolName(for: chip(face: nil)), "person.crop.circle.badge.exclamationmark")
        XCTAssertEqual(TargetChips.accessibilityLabel(for: chip(face: 1, gender: .female, source: .manual, overrides: 2)),
            "사람 2, 여성, 지정, 바꾼 항목 2개")
        XCTAssertEqual(TargetChips.accessibilityLabel(for: chip(face: 0, gender: .male, source: .estimated)), "사람 1, 남성, 추정")
        XCTAssertEqual(TargetChips.accessibilityLabel(for: chip(face: 0)), "사람 1, 미지정")
        XCTAssertEqual(UserMessage.personOrdinal(3), "사람 3")
        XCTAssertEqual(UserMessage.genderTitle(.male), "남성")
        XCTAssertEqual(UserMessage.genderTitle(.female), "여성")
        XCTAssertEqual(UserMessage.genderTitle(nil), "미지정")
        XCTAssertEqual(UserMessage.rebindToFace(2), "사람 2에 연결")
    }
}
```

`AppModelTests.swift` 끝에 추가:

```swift
    func testScopedPanelValuesShowInheritedAndOverriddenKeysPerTarget() async throws {
        let staged = try TestSupport.solidPNG(in: root)
        let faces = twoFaces()
        let model = TestSupport.makeModel(
            root: root, analyzer: StubFaceAnalyzer(result: .success(faces)),
            importer: FakeImporter(staged: [.success(StagedPhoto(url: staged, displayName: nil))]))
        try await importOne(model, staged)
        model.edit(.skinSmoothing(0.2))
        model.setBeautyTarget(.face(0))
        model.setGender(.female)
        model.setBeautyTarget(.gender(.female))
        model.applyMakeupLook(id: "daily")
        XCTAssertEqual(model.scopedValues.makeup.lookID, "daily")
        XCTAssertEqual(model.overriddenKeys, PortraitKey.makeup)
        model.setBeautyTarget(.face(0))
        XCTAssertEqual(model.scopedValues.makeup.lookID, "daily", "여성 그룹의 룩을 상속")
        XCTAssertEqual(model.scopedValues.portrait.skin.smoothing, 0.2, "전체 층의 피부를 상속")
        XCTAssertEqual(model.overriddenKeys, [])
        model.edit(.makeupIntensity(.lip, 0.9))
        XCTAssertEqual(model.overriddenKeys, [.makeupPart(.lip)])
        XCTAssertNil(model.scopedValues.makeup.lookID, "부위를 바꾸면 그 층의 룩 선택이 풀린다")
        model.resetOverrides([.makeupPart(.lip)])
        XCTAssertEqual(model.scopedValues.makeup.lookID, "daily")
        XCTAssertEqual(
            UserMessage.scopeHint(for: .face(0)), UserMessage.scopeHintPerson)
        XCTAssertEqual(UserMessage.scopeHint(for: .gender(.male)), UserMessage.scopeHintGroup)
        XCTAssertNil(UserMessage.scopeHint(for: .all))
    }
```

- [ ] **Step 2: 실패 확인**

Run: Mac 앱 테스트 → 컴파일 실패(`TargetChips` 없음).

- [ ] **Step 3: 구현**

`UserMessage.swift`에 추가(H2 Task 5의 `beautyTargetLabel`·`beautyTargetAll`·`beautyTargetGender`·`beautyTargetFace`는 아래 이름으로 바꾸고 호출부를 고친다):

```swift
    static let targetLabel = "대상"
    static let targetAll = "전체"
    static let genderMale = "남성"
    static let genderFemale = "여성"
    static let genderUnset = "미지정"
    static let genderEstimated = "추정"
    static let genderManual = "지정"
    static let overrideReset = "재설정"
    static let resetScope = "이 대상 초기화"
    static let personUnmatched = "사진에서 찾지 못함"
    static let rebindPerson = "이 얼굴에 연결"
    static let removePerson = "삭제"
    static let scopeHintGroup = "전체 값을 바탕으로 이 그룹에서 바꾼 항목만 저장돼요. 점이 있는 항목이 바꾼 것이에요."
    static let scopeHintPerson = "전체·그룹 값을 바탕으로 이 사람에게서 바꾼 항목만 저장돼요. 점이 있는 항목이 바꾼 것이에요."
    static let assignGenderHint = "성별을 지정하면 그 그룹의 값이 함께 적용돼요. 자동 추정이 틀리면 여기서 고칠 수 있어요."

    static func personOrdinal(_ number: Int) -> String { "사람 \(number)" }
    static func genderTitle(_ gender: Gender?) -> String {
        switch gender {
        case .male: return genderMale
        case .female: return genderFemale
        case nil: return genderUnset
        }
    }
    static func groupTitle(_ gender: Gender) -> String { "\(genderTitle(gender)) 그룹" }
    static func rebindToFace(_ number: Int) -> String { "\(personOrdinal(number))에 연결" }
    static func overriddenCount(_ count: Int) -> String { "바꾼 항목 \(count)개" }
    /// 전체는 안내가 없다.
    static func scopeHint(for target: AppModel.BeautyTarget) -> String? {
        switch target {
        case .all: return nil
        case .gender: return scopeHintGroup
        case .face, .person: return scopeHintPerson
        }
    }
```

`Theme.swift`: `targetChipHeight: CGFloat = 30`, `targetChipPadding: CGFloat = 10`, `overrideDotSize: CGFloat = 6`.

`AdjustmentSlider.swift`: `var isOverridden = false`, `var onReset: (() -> Void)? = nil` 추가. 제목 앞에 `if isOverridden { Circle().fill(Theme.accent).frame(width: Theme.overrideDotSize, height: Theme.overrideDotSize) }`. `onReset`이 있고 `isOverridden`이면 `.contextMenu { Button(UserMessage.overrideReset) { onReset() } }`와 macOS에서 제목 옆 작은 `Button { onReset() } label: { Image(systemName: "xmark.circle") }.buttonStyle(.plain).accessibilityLabel(UserMessage.overrideReset)`.

`apple/MellowPhoto/Features/Editor/TargetChips.swift`:

```swift
import MellowShared
import SwiftUI

/// 뷰티·메이크업 패널 맨 위의 대상 칩: 전체 · 남성 · 여성 · 사람 1…n · 찾지 못한 사람. 사람 칩에는 성별 메뉴가 있다.
struct TargetChips: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    chip(title: UserMessage.targetAll, symbol: "person.3", target: .all)
                    ForEach(Gender.allCases, id: \.self) { gender in
                        chip(title: UserMessage.groupTitle(gender), symbol: Self.groupSymbol(gender), target: .gender(gender))
                    }
                    ForEach(model.personChips) { person in
                        chip(
                            title: Self.title(for: person), symbol: Self.symbolName(for: person), target: person.target,
                            dot: person.overriddenCount > 0, accessibility: Self.accessibilityLabel(for: person)
                        )
                        .contextMenu { PersonGenderMenu(chip: person) }
                    }
                }
                .padding(.vertical, 4)
            }
            .scrollIndicators(.hidden)
            .accessibilityLabel(UserMessage.targetLabel)
            if let selected = model.personChips.first(where: { $0.target == model.beautyTarget }) {
                HStack {
                    Text(Self.statusLine(for: selected)).font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Menu {
                        PersonGenderMenu(chip: selected)
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                    .accessibilityLabel(UserMessage.targetLabel)
                }
            }
            if let hint = UserMessage.scopeHint(for: model.beautyTarget) {
                Text(hint).font(.caption2).foregroundStyle(.secondary)
            }
        }
    }

    private func chip(
        title: String, symbol: String, target: AppModel.BeautyTarget, dot: Bool = false, accessibility: String? = nil
    ) -> some View {
        let selected = model.beautyTarget == target
        return Button {
            model.setBeautyTarget(target)
        } label: {
            HStack(spacing: 4) {
                Image(systemName: symbol)
                Text(title)
                if dot {
                    Circle().fill(Theme.accent).frame(width: Theme.overrideDotSize, height: Theme.overrideDotSize)
                }
            }
            .font(.caption)
            .padding(.horizontal, Theme.targetChipPadding)
            .frame(minHeight: Theme.targetChipHeight)
            .background(selected ? Theme.accent.opacity(0.2) : Color.secondary.opacity(0.15), in: Capsule())
            .overlay(Capsule().stroke(selected ? Theme.accent : .clear, lineWidth: 2))
            .foregroundStyle(selected ? Theme.accent : .primary)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibility ?? title)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    static func title(for chip: AppModel.PersonChip) -> String {
        chip.faceIndex.map { String($0 + 1) } ?? UserMessage.personUnmatched
    }

    static func symbolName(for chip: AppModel.PersonChip) -> String {
        if chip.isUnmatched {
            return "person.crop.circle.badge.exclamationmark"
        }
        switch chip.source {
        case .manual: return "person.crop.circle.fill"
        case .estimated: return "person.crop.circle"
        case .none: return "person.crop.circle.badge.questionmark"
        }
    }

    static func accessibilityLabel(for chip: AppModel.PersonChip) -> String {
        var parts = [chip.faceIndex.map { UserMessage.personOrdinal($0 + 1) } ?? UserMessage.personUnmatched]
        parts.append(UserMessage.genderTitle(chip.gender))
        switch chip.source {
        case .manual: parts.append(UserMessage.genderManual)
        case .estimated: parts.append(UserMessage.genderEstimated)
        case .none: break
        }
        if chip.overriddenCount > 0 {
            parts.append(UserMessage.overriddenCount(chip.overriddenCount))
        }
        return parts.joined(separator: ", ")
    }

    static func statusLine(for chip: AppModel.PersonChip) -> String {
        accessibilityLabel(for: chip)
    }

    private static func groupSymbol(_ gender: Gender) -> String {
        gender == .male ? "figure.stand" : "figure.stand.dress"
    }
}

/// 사람 칩의 메뉴: 성별(남성·여성·미지정, 추정이면 표시), 이 대상 초기화, 찾지 못한 기록은 연결·삭제.
struct PersonGenderMenu: View {
    @Environment(AppModel.self) private var model
    let chip: AppModel.PersonChip

    var body: some View {
        Section(UserMessage.genderTitle(nil) == UserMessage.genderUnset ? UserMessage.targetLabel : UserMessage.targetLabel) {
            ForEach([Gender.male, Gender.female], id: \.self) { gender in
                Button {
                    model.setBeautyTarget(chip.target)
                    model.setGender(gender)
                } label: {
                    Label(
                        UserMessage.genderTitle(gender) + (chip.gender == gender && chip.source == .estimated ? " · \(UserMessage.genderEstimated)" : ""),
                        systemImage: chip.gender == gender ? "checkmark" : "")
                }
            }
            Button {
                model.setBeautyTarget(chip.target)
                model.setGender(nil)
            } label: {
                Label(UserMessage.genderUnset, systemImage: chip.gender == nil ? "checkmark" : "")
            }
        }
        Button(UserMessage.resetScope) {
            model.setBeautyTarget(chip.target)
            model.resetOverrides()
        }
        .disabled(chip.overriddenCount == 0)
        if chip.isUnmatched, let id = chip.personID {
            Menu(UserMessage.rebindPerson) {
                ForEach(model.faces.indices, id: \.self) { index in
                    Button(UserMessage.rebindToFace(index + 1)) { model.rebindPerson(id, toFace: index) }
                }
            }
            Button(UserMessage.removePerson, role: .destructive) { model.removePerson(id) }
        }
    }
}
```

(`Section` 제목의 삼항식은 쓰지 않는다 — `Section(UserMessage.targetLabel) { … }`로 단순하게 쓴다. 위 코드에서 그 줄은 `Section(UserMessage.targetLabel) {`로 고쳐 넣는다.)

`BeautyPanel.swift`: H2의 임시 `Picker`를 `TargetChips()`로 바꾸고(칩은 패널 맨 위. 바로 뒤 G4-3가 칩 아래에 원터치 줄을 넣고 탭 피커 이하를 "세부 조정" 접기 안으로 옮기므로 탭 피커는 그대로 둔다), 세 탭의 슬라이더가 `model.scopedValues.portrait`를 보이며 `isOverridden: model.overriddenKeys.contains(key)`와 `onReset: { model.resetOverrides([key]) }`를 넘긴다(전체 대상에서는 `overriddenKeys`가 비어 표시가 없다). 자동 잡티 토글은 `scopedValues.portrait.skin.autoBlemish`. 얼굴 없음·분석 실패 안내는 그대로. 성별 안내 `UserMessage.assignGenderHint`는 사람 칩이 선택됐고 성별이 미지정일 때 한 줄.

`MakeupPanel.swift`: 룩 칩 위에 `TargetChips()`, `makeup`은 `model.scopedValues.makeup`, 룩 칩 선택은 그 값의 `lookID`, 강도 슬라이더에 `isOverridden: model.overriddenKeys.contains(.makeupPart(part))`·`onReset`. "없음" 칩의 선택 조건은 `makeup == MakeupAdjustments()`에서 대상별로: 전체는 그대로, 그룹·개인은 `overriddenKeys.isSuperset(of: PortraitKey.makeup) && makeup.hasEffect == false`.

`cd apple && xcodegen generate --quiet` 뒤 `MellowPhoto.xcodeproj`가 바뀐다.

- [ ] **Step 4: 통과 확인**

Run: Mac 앱 테스트 → `Executed 84 tests, with 0 failures`. `cd apple && swift test` → 406 불변. lint 출력 없음. `cd apple && xcodegen generate --quiet && git diff --exit-code --stat MellowPhoto.xcodeproj` → 출력 없음(이미 생성 결과를 커밋 대상에 포함).

- [ ] **Step 5: 커밋**

```bash
git add apple/MellowPhoto/Features/Editor/TargetChips.swift apple/MellowPhoto/Features/Shared/AdjustmentSlider.swift apple/MellowPhoto/Features/Shared/Theme.swift apple/MellowPhoto/Features/Editor/BeautyPanel.swift apple/MellowPhoto/Features/Editor/MakeupPanel.swift apple/MellowPhoto/Application/UserMessage.swift apple/MellowPhoto/Application/AppModel+Editing.swift apple/MellowPhoto.xcodeproj apple/MellowPhotoTests/TargetChipsTests.swift apple/MellowPhotoTests/AppModelTests.swift
git commit -m "feat(app): 대상 칩(전체·남성·여성·사람 n)과 성별 메뉴, 덮어쓴 슬라이더 표시·재설정

사람 칩은 성별 출처(지정·추정·미지정)와 바꾼 항목 수를 보이고, 찾지 못한 사람은 연결·삭제.
뷰티·메이크업 슬라이더는 전체·그룹·개인을 겹친 값을 보인다.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 4: 시나리오·문서·VALIDATION·전체 검증

**Files:**
- Modify: `apple/MellowPhotoTests/EditorScenarioTests.swift`
- Modify: `docs/architecture/modules.md`, `docs/superpowers/specs/2026-10-21-beauty-h-per-person-design.md`, `VALIDATION.md`

- [ ] **Step 1: 시나리오 테스트**

`EditorScenarioTests.swift`에 `shared/fixtures/people/` 파일을 임시 폴더로 복사하는 도우미 `peopleFixtureCopy(_ name: String) throws -> URL`(demoPortraitCopy와 같은 방식, 경로는 `…/shared/fixtures/people/<name>`)와 라벨 디코더(`PeopleLabels`는 Rendering 테스트 타깃에 있으므로 앱 테스트에는 최소 구조체 `ScenarioLabels { photos: [{ file, people: [{ gender }] }] }`를 따로 둔다)를 더하고 테스트를 추가한다:

```swift
    /// 생성 커플 사진(실제 Vision): 라벨대로 성별을 지정하고 여성 그룹·개인 값을 넣은 뒤 단체 사진에 피부만 동기화하고 저장한다.
    func testCoupleFixtureManualGenderGroupAndIndividualThenSyncAndExport() async throws {
        let labels = try scenarioLabels()
        let couple = try XCTUnwrap(labels.photos.first { $0.file == "couple-01.jpg" })
        let group = try XCTUnwrap(labels.photos.first { $0.file == "group-01.jpg" })
        let destination = CopyingDestination(folder: try TestSupport.temporaryDirectory())
        let model = TestSupport.makeModel(
            root: root, analyzer: VisionFaceAnalyzer(),
            importer: FakeImporter(staged: [
                .success(StagedPhoto(url: try peopleFixtureCopy("couple-01.jpg"), displayName: "couple")),
                .success(StagedPhoto(url: try peopleFixtureCopy("group-01.jpg"), displayName: "group")),
            ]))
        await model.importFromFiles([])
        try await waitUntil { model.session.photos.count == 2 && model.isReady && model.preview != nil }
        XCTAssertEqual(model.faces.count, couple.people.count, "Vision 얼굴 수가 라벨 인원과 같다(PeopleFixturesTests가 보증)")
        let baseline = previewBytes(model)
        for (index, person) in couple.people.enumerated() {
            model.setBeautyTarget(.face(index))
            model.setGender(person.gender == "male" ? .male : .female)
        }
        XCTAssertEqual(model.personChips.map(\.source), Array(repeating: .manual, count: couple.people.count))
        model.setBeautyTarget(.gender(.female))
        model.beginSliderEdit()
        model.edit(.skinSmoothing(0.8))
        model.endSliderEdit()
        try await waitUntil { !model.isRendering && self.previewBytes(model) != baseline }
        let femaleIndex = try XCTUnwrap(couple.people.firstIndex { $0.gender == "female" })
        let maleIndex = try XCTUnwrap(couple.people.firstIndex { $0.gender == "male" })
        model.setBeautyTarget(.face(maleIndex))
        XCTAssertEqual(model.scopedValues.portrait.skin.smoothing, 0, "남성은 여성 그룹 값을 받지 않는다")
        model.setBeautyTarget(.face(femaleIndex))
        XCTAssertEqual(model.scopedValues.portrait.skin.smoothing, 0.8)
        model.beginSliderEdit()
        model.edit(.faceShape(.width, -0.3))
        model.endSliderEdit()
        try await waitUntil { !model.isRendering }
        XCTAssertEqual(model.overriddenKeys, [.faceShape(.width)])
        let coupleRecipe = model.currentRecipe
        XCTAssertEqual(coupleRecipe.people.individuals.count, couple.people.count)
        for category in SyncCategory.allCases where category != .skin {
            model.setSyncCategory(category, enabled: false)
        }
        model.applyToAll()
        let groupRecipe = model.session.photos[1].document.recipe
        XCTAssertEqual(groupRecipe.people.groups[.female], PortraitLayer(skinSmoothing: 0.8), "그룹 층은 복사")
        XCTAssertTrue(groupRecipe.people.individuals.isEmpty, "개인 층·성별 지정은 복사하지 않는다")
        model.select(model.session.photos[1].id)
        try await waitUntil { model.isReady && model.preview != nil }
        XCTAssertEqual(model.faces.count, group.people.count)
        XCTAssertTrue(model.personChips.allSatisfy { $0.source == .none }, "단체 사진은 아직 모두 미지정")
        model.select(model.session.photos[0].id)
        try await waitUntil { model.isReady && model.preview != nil }
        let size = try await exportedPixelSize(model, destination: destination)
        XCTAssertGreaterThan(size.width, 0)
        XCTAssertNil(model.presentedError)
    }
```

(`previewBytes`·`exportedPixelSize`·`waitUntil`은 기존 시나리오 테스트의 도우미를 그대로 쓴다. `importFromFiles([])`가 빈 배열 guard로 끝나면 기존 시나리오가 쓰는 가져오기 호출 형태(`importFromFiles([url1, url2])`)를 따른다.)

Run: Mac 앱 테스트 → `Executed 85 tests, with 0 failures`.

- [ ] **Step 2: 문서**

`docs/architecture/modules.md`:
- MellowShared 공개 API에 `Gender`, `PersonID`, `PersonAnchor`, `PortraitKey`, `PortraitLayer`, `PersonRecord`, `PeopleAdjustments`, `PortraitScope`, `PortraitResolver`, `PersonMatcher`, `PersonMatching` 추가. 규칙에 "H 레시피 `people`(성별 그룹 층 둘·개인 기록, 성긴 층은 있는 키만 덮어씀, 메이크업은 부위 단위), 전체 → 그룹 → 개인 해석은 `PortraitResolver` 한 곳, 사람 짝짓기는 `PersonMatcher`(anchor 거리 ≤ 폭 50%·크기 비 ≤ 2, 1:1 탐욕, legacyIndex 폴백) 한 곳, `portrait.targetFace`는 읽기 전용이고 `people`이 없을 때 개인 층(`legacyIndex`, 결정적 `PersonID.legacy`)으로 이행, 프리셋은 `people.groups`만" 추가.
- MellowEditing 공개 API 그대로(`EditChange.gender` 케이스 추가 언급). 규칙에 "얼굴 의존 변경은 `set(_:in:)`·`set(_:forFace:of:)`로 층을 가리킴(얼굴의 사람은 렌더와 같은 전역 짝짓기)(같은 클램프), 빈 기록은 변경 뒤 제거, 성별 변경·얼굴형 키 재설정·얼굴형 키가 든 기록의 연결·삭제는 수동 편집 잠금 대상, `resetOverrides`는 상속으로(전체는 기본값으로), 프리셋·동기화는 전체·그룹 층만 나르고 동기화한 얼굴 의존 항목의 개인 키를 지움, 룩은 `applyMakeupLook(_:in:)`·`(_:forFace:of:)`" 추가. 기존 "일괄 적용하면 대상 얼굴을 모든 얼굴로 되돌림" 문장은 위 문장으로 대체.
- MellowRendering 공개 API에 `FaceTarget`, `GenderEstimator`, `GenderEstimate` 추가. 규칙에 "`RenderContext.faceTargets`가 얼굴마다 해석한 값이고 `skin`·`feature`·`makeup`·`shapeWarp`가 그 목록을 돎(자동 잡티도 사람별), `GenderEstimator`는 포트만(기본 nil = 모두 미지정), 추정은 준비 때 신뢰도 0.75·얼굴 폭 5%·yaw 0.6rad 임계값을 거쳐 `PhotoAnalysis.genderEstimates`에 두고 영속화하지 않음, 수동 지정이 추정을 이김" 추가. 테스트 목록에 H 항목 요약(얼굴별 값, 그룹·개인, 짝 없는 기록, 임계값, 생성 사진 세트 검사).
- 앱 타깃: `AppModel.BeautyTarget`·`PersonChip`, `TargetChips`·`PersonGenderMenu`, "대상은 사진별 세션 상태(저장 안 함)", 캔버스 탭(뷰티·메이크업).
- 검증 절은 그대로(의존성 표 불변).

스펙 `2026-10-21-beauty-h-per-person-design.md`: 구현 중 스펙과 달라진 것이 있으면 결정 표에 "(H 구현 중 변경)" 행을 더하고 해당 에이전트 참조 절을 고친다(`PortraitScope`를 Shared에 둔 것, `EditChange.gender`·`set(_:forPersonAt:)`·`applyMakeupLook(_:forPersonAt:)`은 이미 반영됨). 없으면 바꾸지 않는다.

- [ ] **Step 3: 전체 검증과 VALIDATION**

Run: `export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer && ./scripts/test-apple.sh` → 종료 코드 0(모듈 검사, lint, xcodegen 차이 없음, 패키지, Mac 앱 테스트 `TEST SUCCEEDED`. 로컬은 iOS 시뮬레이터를 건너뛴다 — `MELLOW_IOS_TESTS`를 켜지 않는다). 실패하면 고치고 다시 돌린다. iPhone·iPad 시뮬레이터 테스트는 CI에서 확인한다(사용자 조치).

`VALIDATION.md` 끝에 `## 인물 보정 H 사람별·성별 그룹 보정 (2026-10-XX)` 절을 G 절과 같은 소제목으로 쓴다:
- 날짜·커밋·환경.
- 자동 검증: 명령·종료 코드·테스트 수(모듈별). "iOS 시뮬레이터 테스트는 로컬에서 돌리지 않았고 CI 확인은 사용자 조치"라고 적는다.
- 자동 테스트가 확인하는 것: 스펙 §2 표를 실제 테스트 이름으로(층 왕복·이행·해석·짝짓기·층 편집·잠금·프리셋·동기화·얼굴별 렌더·그룹·짝 없는 기록·임계값·칩·캔버스 탭·시나리오·생성 사진 세트).
- 옛 세션 이행: `targetFace`가 있던 사진은 "전체" 칩에서 값이 0으로 보이고 "사람 i" 칩에서 보인다. 렌더 바이트가 같음(H2 Task 5의 비교 절차 결과).
- 생성 사진 세트: 장수·용량 합계·사진별 라벨 인원과 Vision 얼굴 수 표(5장 모두 실행해 적되 자동 테스트는 2장만 단언)·눈 확인 결과·사용 조건 README 위치.
- 스펙과 다르게 한 것(없으면 "없음").
- 미검증(사용자 확인 필요): 실사진에서 칩·성별 지정·그룹 값·개인 값·재설정·동기화, iPhone 폭에서 칩 줄 가로 스크롤과 메뉴, 캔버스 탭 정확도(겹친 얼굴), 자동 추정은 H4 전까지 "없음"(모두 미지정으로 시작), 실기기.
- "배포(릴리스 노트·태그·TestFlight)는 H 범위가 아니며 실행하지 않았다." 수행하지 않은 검증을 통과로 쓰지 않는다.

- [ ] **Step 4: 커밋**

```bash
git add apple/MellowPhotoTests/EditorScenarioTests.swift docs/architecture/modules.md docs/superpowers/specs/2026-10-21-beauty-h-per-person-design.md VALIDATION.md
git commit -m "docs: 인물 보정 H 모듈 지도·스펙 반영·검증 기록과 커플 사진 시나리오

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

## 자체 검토 결과

- **스펙 대조:** §1.6 → `BeautyTarget` 라우팅(H2)·`PhotoInfo.genders`·legacy 연결·`personChips`·`TargetChips`·`PersonGenderMenu`·슬라이더 덮어쓰기 표시·`scopedValues`·`overriddenKeys`·`faceAvailability`·캔버스 탭·`UserMessage`·`Theme`(Task 2·3). §2 앱·시나리오 행 → Task 2·3·4. §3 생성 사진 세트(도구·구성·프롬프트 제약·눈 확인·파일·라벨 형식·용도·Vision 불일치 처리) → Task 1. §4 VALIDATION 항목 → Task 4. §5 → H3 "4 Task"와 같다.
- **타입 일관성:** `PeopleFixtures.url`·`labels`·`sharedFolder`, `PeopleLabels`, `StubGenderEstimator`(앱 테스트), `TestSupport.makeModel(genderEstimator:)`, `EditDocument.applyMakeupLook(_:forFace:of:)`, `AppModel.PhotoInfo.genders`·`GenderSource`·`PersonChip`·`personMatches`·`personChips`·`effectiveGender(forFace:)`·`genderSource(forFace:)`·`scopedValues`·`overriddenKeys`·`setGender`·`resetOverrides`·`rebindPerson(_:toFace:)`·`removePerson`, `EditorTool.usesCanvasTouch`, `TargetChips.title`·`symbolName`·`accessibilityLabel`·`statusLine`, `PersonGenderMenu`, `AdjustmentSlider(isOverridden:onReset:)`, `UserMessage.targetLabel`·`targetAll`·`genderTitle`·`groupTitle`·`personOrdinal`·`genderEstimated`·`genderManual`·`overrideReset`·`resetScope`·`personUnmatched`·`rebindPerson`·`rebindToFace`·`removePerson`·`scopeHint(for:)`·`scopeHintGroup`·`scopeHintPerson`·`assignGenderHint`·`overriddenCount`, `Theme.targetChipHeight`·`targetChipPadding`·`overrideDotSize`를 정의한 Task와 쓰는 Task에서 같게 썼다. 테스트 수: 패키지 403 → 405(T1) → 406(T2) → 406 → 406, 앱 Mac 78 → 78(T1) → 82(T2) → 84(T3) → 85(T4).
- **Review Focus 매핑:** 1→Task 4, 2→Task 2, 3→Task 2, 4→Task 2, 5→Task 2, 6→Task 1. 모두 테스트 코드가 있다.
- **플레이스홀더 점검:** Task 1의 라벨 JSON `…`과 커밋 메시지의 `<사진별 …>`·`<N>`은 실제 생성 결과로 채우는 자리이며 그렇게 명시했다. 그 밖에 "TBD/TODO/나중에" 없음.
