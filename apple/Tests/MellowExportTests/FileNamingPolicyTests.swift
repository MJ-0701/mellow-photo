import XCTest

@testable import MellowExport

final class FileNamingPolicyTests: XCTestCase {
    func testAppendsMellowSuffixAndCountsUpOnCollision() {
        let folder = URL(fileURLWithPath: "/tmp/out")
        let taken: Set<String> = ["IMG_1_mellow.jpg", "IMG_1_mellow_2.jpg"]
        let url = FileNamingPolicy.availableURL(in: folder, stem: "IMG_1", fileExtension: "jpg") {
            taken.contains($0.lastPathComponent)
        }
        XCTAssertEqual(url.lastPathComponent, "IMG_1_mellow_3.jpg")
        let free = FileNamingPolicy.availableURL(in: folder, stem: "IMG_2", fileExtension: "png") { _ in false }
        XCTAssertEqual(free.lastPathComponent, "IMG_2_mellow.png")
    }
}
