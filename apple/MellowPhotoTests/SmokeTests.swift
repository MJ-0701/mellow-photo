import MellowShared
import XCTest
@testable import Mellow_Photo

final class SmokeTests: XCTestCase {
    func testAppTargetLinksMellowKit() {
        XCTAssertEqual(BuiltInPresets.all.count, 3)
    }
}
