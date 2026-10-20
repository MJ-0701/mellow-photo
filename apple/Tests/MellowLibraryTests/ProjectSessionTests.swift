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

    func testDeferredPersistenceSavesOnceAtEnd() throws {
        let store = MemorySessionStore()
        let session = ProjectSession(store: store, maxPhotos: 40)
        let photo = entry("A")
        try session.add(photo)
        let before = store.saveCount
        session.beginDeferredPersistence()
        for step in 1...5 {
            session.edit(photo.id) { document in document.set(.exposure(Double(step) / 10)) }
        }
        XCTAssertEqual(store.saveCount, before)
        session.endDeferredPersistence()
        XCTAssertEqual(store.saveCount, before + 1)
        XCTAssertEqual(store.saved?.photos.first?.document.recipe.color.exposure, 0.5)
        session.beginDeferredPersistence()
        session.endDeferredPersistence()
        XCTAssertEqual(store.saveCount, before + 2, "바뀐 것이 없어도 끝낼 때 저장한다")
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
        locked.document.set(.faceShape(.width, -0.2))
        locked.document.set(.targetFace(1))
        locked.document.appendLocalEdit(.spot(RetouchSpot(x: 0.5, y: 0.4, sourceX: 0.4, sourceY: 0.4, radius: 0.02)))
        var plain = entry("C")
        plain.document.set(.targetFace(0))
        try session.add(source)
        try session.add(locked)
        try session.add(plain)
        session.edit(source.id) { $0.set(.exposure(0.3)) }
        session.edit(source.id) { $0.set(.faceShape(.width, -0.9)) }
        session.edit(source.id) { document in
            var values = PresetValues(of: document.recipe)
            values.background.blur = 0.4
            document.apply(values)
            return nil
        }
        session.applyToAll(from: source.id)
        XCTAssertEqual(session.photos[1].document.recipe.portrait.face.width, -0.2)
        XCTAssertEqual(session.photos[1].document.recipe.portrait.targetFace, 1)
        XCTAssertEqual(session.photos[1].document.recipe.color.exposure, 0.3)
        XCTAssertEqual(session.photos[2].document.recipe.portrait.face.width, -0.9)
        XCTAssertNil(session.photos[2].document.recipe.portrait.targetFace)
        XCTAssertEqual(session.photos[0].document.recipe.color.exposure, 0.3, "원본 사진은 바뀌지 않는다")
        XCTAssertEqual(session.photos[1].document.recipe.background.blur, 0.4, "잠긴 사진도 배경 값은 복사한다")
        XCTAssertEqual(session.photos[2].document.recipe.background.blur, 0.4)
    }

    func testApplyToAllWithCategoriesCopiesOnlyThose() throws {
        let session = ProjectSession(store: MemorySessionStore(), maxPhotos: 40)
        let source = entry("A")
        let other = entry("B")
        try session.add(source)
        try session.add(other)
        session.edit(source.id) { $0.set(.exposure(0.3)) }
        session.edit(source.id) { $0.set(.skinSmoothing(0.5)) }
        session.edit(other.id) { $0.set(.targetFace(0)) }
        session.applyToAll(from: source.id, categories: [.color])
        XCTAssertEqual(session.photos[1].document.recipe.color.exposure, 0.3)
        XCTAssertEqual(session.photos[1].document.recipe.portrait.skin.smoothing, 0, "피부는 고르지 않았다")
        XCTAssertEqual(session.photos[1].document.recipe.portrait.targetFace, 0, "얼굴 항목이 없으면 대상 얼굴 유지")
        session.applyToAll(from: source.id)
        XCTAssertEqual(session.photos[1].document.recipe.portrait.skin.smoothing, 0.5, "기본은 전부")
        XCTAssertNil(session.photos[1].document.recipe.portrait.targetFace)
    }

    func testAddPresetTrimsAndLimitsName() throws {
        let session = ProjectSession(store: MemorySessionStore(), maxPhotos: 40)
        session.addPreset(named: "  " + String(repeating: "가", count: 40) + "  ", values: PresetValues())
        XCTAssertEqual(session.presets.count, 1)
        XCTAssertEqual(session.presets[0].name.count, LibraryPolicy.presetNameLimit)
        session.addPreset(named: "   ", values: PresetValues())
        XCTAssertEqual(session.presets.count, 1, "빈 이름은 무시")
    }

    func testEndContinuousChangeDoesNotSave() throws {
        let store = MemorySessionStore()
        let session = ProjectSession(store: store, maxPhotos: 40)
        let photo = entry("A")
        try session.add(photo)
        session.edit(photo.id) { document in
            document.beginContinuousChange()
            return document.set(.exposure(0.1))
        }
        let before = store.saveCount
        session.endContinuousChange(photo.id)
        XCTAssertEqual(store.saveCount, before, "플래그만 끄고 파일은 쓰지 않는다")
        session.edit(photo.id) { $0.set(.exposure(0.2)) }
        XCTAssertEqual(session.photos[0].document.undoStack.count, 2, "연속 변경이 끝났으므로 다음 편집은 체크포인트한다")
    }

    func testApplyToAllCopiesDetail() throws {
        let session = ProjectSession(store: MemorySessionStore(), maxPhotos: 40)
        let source = entry("A")
        let other = entry("B")
        try session.add(source)
        try session.add(other)
        session.edit(source.id) { $0.set(.vignette(0.4)) }
        session.applyToAll(from: source.id)
        XCTAssertEqual(session.photos[1].document.recipe.detail.vignette, 0.4)
    }

    func testApplyToAllSkipsSavingWhenNothingChanged() throws {
        let store = MemorySessionStore()
        let session = ProjectSession(store: store, maxPhotos: 40)
        let source = entry("A")
        let other = entry("B")
        try session.add(source)
        try session.add(other)
        session.edit(source.id) { $0.set(.exposure(0.3)) }
        session.applyToAll(from: source.id, categories: [.color])
        let saves = store.saveCount
        session.applyToAll(from: source.id, categories: [.color])
        XCTAssertEqual(store.saveCount, saves, "다시 복사해도 바뀐 사진이 없으면 저장하지 않는다")
        session.applyToAll(from: source.id, categories: [])
        XCTAssertEqual(store.saveCount, saves, "빈 선택은 저장하지 않는다")
        XCTAssertEqual(session.photos[1].document.undoStack.count, 1, "바뀐 것이 없는 복사는 단계를 만들지 않는다")
        session.edit(source.id) { $0.set(.exposure(0.5)) }
        let edited = store.saveCount
        session.applyToAll(from: source.id, categories: [.color])
        XCTAssertEqual(store.saveCount, edited + 1, "바뀐 사진이 있으면 한 번 저장한다")
    }

    func testApplyToAllCarriesGroupLayersNotIndividuals() throws {
        let session = ProjectSession(store: MemorySessionStore(), maxPhotos: 40)
        let source = entry("A")
        let other = entry("B")
        try session.add(source)
        try session.add(other)
        let anchor = PersonAnchor(x: 0.3, y: 0.5, width: 0.2)
        session.edit(source.id) { $0.set(.skinSmoothing(0.6), in: .gender(.female)) }
        session.edit(source.id) { $0.set(.skinSmoothing(0.9), forPersonAt: anchor) }
        session.edit(other.id) { $0.set(.gender(.male), forPersonAt: anchor) }
        session.edit(other.id) { $0.set(.skinSmoothing(0.2), forPersonAt: anchor) }
        session.applyToAll(from: source.id, categories: [.skin])
        let received = session.photos[1].document.recipe
        XCTAssertEqual(received.people.groups[.female], PortraitLayer(skinSmoothing: 0.6), "그룹 층은 복사")
        XCTAssertEqual(received.people.individuals.count, 1)
        XCTAssertEqual(received.people.individuals[0].gender, .male, "받는 사진의 성별 지정은 남는다")
        XCTAssertTrue(received.people.individuals[0].layer.isEmpty, "받는 사진의 개인 피부 키는 빠진다")
        XCTAssertEqual(
            session.photos[0].document.recipe.people.individuals[0].layer.skinSmoothing, 0.9,
            "원본의 개인 층은 복사되지 않고 그대로")
    }
}
