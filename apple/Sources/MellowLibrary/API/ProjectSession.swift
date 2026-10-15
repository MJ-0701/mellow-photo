import Foundation
import MellowEditing
import MellowShared
import Observation

/// 사진 목록·선택·프리셋의 단일 출처. 모든 변경은 저장소에 반영한다.
@MainActor
@Observable
public final class ProjectSession {
    public enum Failure: Error, Equatable {
        case capacityReached
    }

    public private(set) var photos: [PhotoEntry] = []
    /// 외부에서 선택을 바꾸면 조용히 저장한다. 내부 변경은 `selection`을 직접 써서 저장 시점을 스스로 정한다.
    public var selectedPhotoID: PhotoID? {
        get { selection }
        set {
            selection = newValue
            persistQuietly()
        }
    }
    public private(set) var presets: [Preset] = []
    /// 편집 중 저장 실패. 상태는 유지되고 다음 저장에서 다시 시도한다.
    public private(set) var lastPersistenceError: MellowError?
    /// true인 동안 조용한 저장(`edit`, 선택 변경 등)은 미룬다. `endDeferredPersistence()`가 한 번 저장한다.
    public private(set) var isPersistenceDeferred = false

    private var selection: PhotoID?
    private let store: any SessionStore
    private let maxPhotos: Int

    public init(store: any SessionStore, maxPhotos: Int) {
        self.store = store
        self.maxPhotos = maxPhotos
    }

    public var selected: PhotoEntry? {
        photos.first { $0.id == selectedPhotoID }
    }

    public var remainingCapacity: Int {
        max(0, maxPhotos - photos.count)
    }

    public func index(of id: PhotoID) -> Int? {
        photos.firstIndex { $0.id == id }
    }

    /// 읽을 수 없는 세션은 오류를 던지되 빈 세션으로 계속 쓸 수 있다.
    public func restore() throws {
        guard let snapshot = try store.load() else { return }
        photos = snapshot.photos
        presets = snapshot.presets
        selection = snapshot.selectedPhotoID
    }

    public func add(_ entry: PhotoEntry) throws {
        guard remainingCapacity > 0 else { throw Failure.capacityReached }
        photos.append(entry)
        let previousSelection = selection
        if selection == nil {
            selection = entry.id
        }
        do {
            try save()
        } catch {
            photos.removeLast()
            selection = previousSelection
            throw error
        }
    }

    /// 저장이 성공한 뒤에만 상태를 바꾼다. 실패하면 사진·기록은 그대로다.
    public func remove(_ id: PhotoID) throws {
        let remaining = photos.filter { $0.id != id }
        let nextSelection = selection == id ? remaining.first?.id : selection
        try store.save(SessionSnapshot(photos: remaining, selectedPhotoID: nextSelection, presets: presets))
        photos = remaining
        selection = nextSelection
        lastPersistenceError = nil
    }

    @discardableResult
    public func edit(_ id: PhotoID, _ body: (inout EditDocument) -> EditDocument.Rejection?)
        -> EditDocument.Rejection?
    {
        guard let index = index(of: id) else { return nil }
        let rejection = body(&photos[index].document)
        persistQuietly()
        return rejection
    }

    /// 연속 변경 플래그는 영속 상태가 아니므로 파일을 쓰지 않고 끝낸다.
    public func endContinuousChange(_ id: PhotoID) {
        guard let index = index(of: id) else { return }
        photos[index].document.endContinuousChange()
    }

    public func applyToAll(from id: PhotoID) {
        guard let source = photos.first(where: { $0.id == id }) else { return }
        let values = PresetValues(color: source.document.recipe.color, portrait: source.document.recipe.portrait)
        for index in photos.indices where photos[index].id != id {
            photos[index].document.applyFromBatch(values)
        }
        persistQuietly()
    }

    public func addPreset(named rawName: String, values: PresetValues) {
        let trimmed = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        presets.append(Preset(name: String(trimmed.prefix(LibraryPolicy.presetNameLimit)), values: values))
        persistQuietly()
    }

    /// 슬라이더 드래그처럼 짧은 간격으로 이어지는 변경은 끝날 때 한 번만 저장한다.
    public func beginDeferredPersistence() {
        isPersistenceDeferred = true
    }

    /// 미룬 동안 바뀐 것이 없어도 저장한다. 실패는 `lastPersistenceError`로 남긴다.
    public func endDeferredPersistence() {
        isPersistenceDeferred = false
        persistQuietly()
    }

    public func save() throws {
        try store.save(SessionSnapshot(photos: photos, selectedPhotoID: selection, presets: presets))
        lastPersistenceError = nil
    }

    private func persistQuietly() {
        guard !isPersistenceDeferred else { return }
        do {
            try save()
        } catch let error as MellowError {
            lastPersistenceError = error
        } catch {
            lastPersistenceError = .sessionWriteFailed(reason: error.localizedDescription)
        }
    }
}
