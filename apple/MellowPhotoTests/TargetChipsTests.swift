import MellowShared
import XCTest

@testable import Mellow_Photo

/// 대상 칩의 글자·아이콘·접근성 문구만 확인한다.
/// 칩 줄의 모양과 가로 스크롤은 사람이 본다.
@MainActor
final class TargetChipsTests: XCTestCase {
    private func chip(
        face: Int? = 0, gender: Gender? = nil, source: AppModel.GenderSource = .none, overrides: Int = 0
    ) -> AppModel.PersonChip {
        AppModel.PersonChip(
            id: face.map { "face-\($0)" } ?? "person-x",
            target: face.map(AppModel.BeautyTarget.face) ?? .person(PersonID()),
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
        XCTAssertEqual(
            TargetChips.accessibilityLabel(for: chip(face: 1, gender: .female, source: .manual, overrides: 2)),
            "사람 2, 여성, 지정, 바꾼 항목 2개")
        XCTAssertEqual(
            TargetChips.accessibilityLabel(for: chip(face: 0, gender: .male, source: .estimated)), "사람 1, 남성, 추정")
        XCTAssertEqual(TargetChips.accessibilityLabel(for: chip(face: 0)), "사람 1, 미지정")
        XCTAssertEqual(UserMessage.personOrdinal(3), "사람 3")
        XCTAssertEqual(UserMessage.genderTitle(.male), "남성")
        XCTAssertEqual(UserMessage.genderTitle(.female), "여성")
        XCTAssertEqual(UserMessage.genderTitle(nil), "미지정")
        XCTAssertEqual(UserMessage.rebindToFace(2), "사람 2에 연결")
        XCTAssertEqual(
            TargetChips.statusLine(for: chip(face: 1, gender: .female, source: .manual, overrides: 2)),
            "사람 2 · 지정 · 바꾼 항목 2개", "성별은 옆 단추가 보인다")
        XCTAssertEqual(TargetChips.statusLine(for: chip(face: 0)), "사람 1")
        XCTAssertEqual(UserMessage.genderButton(nil), "성별: 미지정")
        XCTAssertEqual(UserMessage.genderButton(.male), "성별: 남성")
    }
}
