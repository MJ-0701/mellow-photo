import XCTest

@testable import Mellow_Photo

final class SystemPhotoImporterTests: XCTestCase {
    func testStagingFileURLsCopiesIntoTemporaryFolderAndKeepsStem() async throws {
        let root = try TestSupport.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let original = try TestSupport.solidPNG(in: root, name: "IMG_0042")
        let results = await SystemPhotoImporter().stage(fileURLs: [
            original, root.appendingPathComponent("missing.png"),
        ])
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
