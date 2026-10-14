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
