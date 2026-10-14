import MellowEditing
import MellowShared
import XCTest

@testable import MellowLibrary

/// 저장 실패를 흉내 내는 메모리 저장소.
final class MemorySessionStore: SessionStore, @unchecked Sendable {
    var saved: SessionSnapshot?
    var failNextSave = false
    var saveCount = 0

    func load() throws -> SessionSnapshot? { saved }

    func save(_ snapshot: SessionSnapshot) throws {
        saveCount += 1
        if failNextSave {
            failNextSave = false
            throw MellowError.sessionWriteFailed(reason: "test")
        }
        saved = snapshot
    }
}

@MainActor
final class ProjectSessionTests: XCTestCase {
    private func entry(_ name: String) -> PhotoEntry {
        PhotoEntry(id: PhotoID(), filename: "\(name).heic", displayName: name)
    }

    func testRestoreLoadsSnapshotAndSelection() throws {
        let store = MemorySessionStore()
        let photo = entry("A")
        store.saved = SessionSnapshot(photos: [photo], selectedPhotoID: photo.id, presets: [BuiltInPresets.cozy])
        let session = ProjectSession(store: store, maxPhotos: 40)
        try session.restore()
        XCTAssertEqual(session.photos, [photo])
        XCTAssertEqual(session.selectedPhotoID, photo.id)
        XCTAssertEqual(session.presets, [BuiltInPresets.cozy])
    }

    func testAddSelectsFirstPhotoAndPersists() throws {
        let store = MemorySessionStore()
        let session = ProjectSession(store: store, maxPhotos: 40)
        let photo = entry("A")
        try session.add(photo)
        XCTAssertEqual(session.selectedPhotoID, photo.id)
        XCTAssertEqual(store.saved?.photos, [photo])
    }

    func testAddRollsBackWhenSaveFails() throws {
        let store = MemorySessionStore()
        let session = ProjectSession(store: store, maxPhotos: 40)
        store.failNextSave = true
        XCTAssertThrowsError(try session.add(entry("A")))
        XCTAssertTrue(session.photos.isEmpty)
        XCTAssertNil(session.selectedPhotoID)
    }

    func testAddBeyondCapacityIsRejected() throws {
        let session = ProjectSession(store: MemorySessionStore(), maxPhotos: 1)
        try session.add(entry("A"))
        XCTAssertEqual(session.remainingCapacity, 0)
        XCTAssertThrowsError(try session.add(entry("B"))) { error in
            XCTAssertEqual(error as? ProjectSession.Failure, .capacityReached)
        }
    }

    func testEditAppliesRulesAndPersists() throws {
        let store = MemorySessionStore()
        let session = ProjectSession(store: store, maxPhotos: 40)
        let photo = entry("A")
        try session.add(photo)
        let rejection = session.edit(photo.id) { document in document.set(.exposure(0.4)) }
        XCTAssertNil(rejection)
        XCTAssertEqual(session.selected?.document.recipe.color.exposure, 0.4)
        XCTAssertEqual(store.saved?.photos.first?.document.recipe.color.exposure, 0.4)
        XCTAssertNil(session.lastPersistenceError)
    }

    func testEditSaveFailureIsExposedButStateIsKept() throws {
        let store = MemorySessionStore()
        let session = ProjectSession(store: store, maxPhotos: 40)
        let photo = entry("A")
        try session.add(photo)
        store.failNextSave = true
        session.edit(photo.id) { document in document.set(.exposure(0.4)) }
        XCTAssertEqual(session.selected?.document.recipe.color.exposure, 0.4)
        XCTAssertNotNil(session.lastPersistenceError)
    }

    func testRemoveSavesFirstAndKeepsStateOnFailure() throws {
        let store = MemorySessionStore()
        let session = ProjectSession(store: store, maxPhotos: 40)
        let photo = entry("A")
        try session.add(photo)
        session.edit(photo.id) { document in document.set(.exposure(0.4)) }
        store.failNextSave = true
        XCTAssertThrowsError(try session.remove(photo.id))
        XCTAssertEqual(session.photos.map(\.id), [photo.id])
        XCTAssertTrue(session.selected?.document.canUndo ?? false)
        try session.remove(photo.id)
        XCTAssertTrue(session.photos.isEmpty)
        XCTAssertNil(session.selectedPhotoID)
        XCTAssertEqual(store.saved?.photos.count, 0)
    }

    func testRemoveSelectsNextPhoto() throws {
        let session = ProjectSession(store: MemorySessionStore(), maxPhotos: 40)
        let a = entry("A")
        let b = entry("B")
        try session.add(a)
        try session.add(b)
        try session.remove(a.id)
        XCTAssertEqual(session.selectedPhotoID, b.id)
    }

    func testApplyToAllCopiesValuesWithBatchRules() throws {
        let session = ProjectSession(store: MemorySessionStore(), maxPhotos: 40)
        let source = entry("A")
        var locked = entry("B")
        locked.document.set(.faceSlim(0.2))
        locked.document.set(.targetFace(1))
        locked.document.appendLocalEdit(.spot(RetouchSpot(x: 0.5, y: 0.4, sourceX: 0.4, sourceY: 0.4, radius: 0.02)))
        var plain = entry("C")
        plain.document.set(.targetFace(0))
        try session.add(source)
        try session.add(locked)
        try session.add(plain)
        session.edit(source.id) { $0.set(.exposure(0.3)) }
        session.edit(source.id) { $0.set(.faceSlim(0.9)) }
        session.applyToAll(from: source.id)
        XCTAssertEqual(session.photos[1].document.recipe.portrait.faceSlim, 0.2)
        XCTAssertEqual(session.photos[1].document.recipe.portrait.targetFace, 1)
        XCTAssertEqual(session.photos[1].document.recipe.color.exposure, 0.3)
        XCTAssertEqual(session.photos[2].document.recipe.portrait.faceSlim, 0.9)
        XCTAssertNil(session.photos[2].document.recipe.portrait.targetFace)
        XCTAssertEqual(session.photos[0].document.recipe.color.exposure, 0.3, "원본 사진은 바뀌지 않는다")
    }

    func testAddPresetTrimsAndLimitsName() throws {
        let session = ProjectSession(store: MemorySessionStore(), maxPhotos: 40)
        session.addPreset(named: "  " + String(repeating: "가", count: 40) + "  ", values: PresetValues())
        XCTAssertEqual(session.presets.count, 1)
        XCTAssertEqual(session.presets[0].name.count, LibraryPolicy.presetNameLimit)
        session.addPreset(named: "   ", values: PresetValues())
        XCTAssertEqual(session.presets.count, 1, "빈 이름은 무시")
    }
}
