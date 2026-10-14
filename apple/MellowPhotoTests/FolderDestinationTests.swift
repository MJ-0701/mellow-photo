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
