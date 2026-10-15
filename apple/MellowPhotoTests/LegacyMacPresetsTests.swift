import MellowLibrary
import XCTest

@testable import Mellow_Photo

@MainActor
final class LegacyMacPresetsTests: XCTestCase {
    func testLegacyPresetsFileIsImportedOnceAndRenamed() throws {
        let support = try TestSupport.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: support) }
        let legacy = support.appendingPathComponent("MellowPhoto/presets.json")
        try FileManager.default.createDirectory(
            at: legacy.deletingLastPathComponent(), withIntermediateDirectories: true)
        let json =
            #"[{"id":"44444444-4444-4444-4444-444444444444","name":"옛날","adjustments":{"exposure":0.2,"contrast":1,"saturation":0.9,"warmth":0.1,"skin":0.4,"faceSlim":0}}]"#
        try Data(json.utf8).write(to: legacy)
        let session = ProjectSession(store: MemorySessionStore(), maxPhotos: 40)
        LegacyMacPresets.importIfPresent(into: session, applicationSupport: support)
        XCTAssertEqual(session.presets.map(\.name), ["옛날"])
        XCTAssertEqual(session.presets[0].values.portrait.skin.smoothing, 0.4)
        XCTAssertFalse(FileManager.default.fileExists(atPath: legacy.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: legacy.path + ".imported"))
        LegacyMacPresets.importIfPresent(into: session, applicationSupport: support)
        XCTAssertEqual(session.presets.count, 1, "두 번째 실행은 아무것도 하지 않는다")
    }

    func testCorruptLegacyPresetsFileIsLeftInPlace() throws {
        let support = try TestSupport.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: support) }
        let legacy = support.appendingPathComponent("MellowPhoto/presets.json")
        try FileManager.default.createDirectory(
            at: legacy.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("{ broken".utf8).write(to: legacy)
        let session = ProjectSession(store: MemorySessionStore(), maxPhotos: 40)
        LegacyMacPresets.importIfPresent(into: session, applicationSupport: support)
        XCTAssertTrue(session.presets.isEmpty)
        XCTAssertTrue(FileManager.default.fileExists(atPath: legacy.path), "읽지 못한 파일은 그대로 둔다")
        XCTAssertFalse(FileManager.default.fileExists(atPath: legacy.path + ".imported"))
    }
}
