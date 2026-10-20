import MellowShared
import XCTest

@testable import Mellow_Photo

/// 원터치 줄의 값 글자와 대상별 안내만 확인한다. 버튼·슬라이더 배치는 사람이 본다.
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
