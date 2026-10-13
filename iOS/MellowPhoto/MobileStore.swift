import SwiftUI
import PhotosUI
import Photos
import CoreTransferable
import UniformTypeIdentifiers
import CoreImage
import ImageIO
import MellowCore

struct ImportedPhoto: Transferable {
    let url: URL
    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(importedContentType: .image) { received in
            let folder = FileManager.default.temporaryDirectory.appendingPathComponent("MellowImports", isDirectory: true)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let url = folder.appendingPathComponent(UUID().uuidString).appendingPathExtension(received.file.pathExtension)
            try FileManager.default.copyItem(at: received.file, to: url)
            return ImportedPhoto(url: url)
        }
    }
}

struct MobilePhoto: Identifiable, Codable {
    let id: UUID
    let filename: String
    let name: String
    var recipe = EditRecipe()
}
struct MobileSession: Codable {
    var photos: [MobilePhoto]
    var selectedID: UUID?
    var presets: [SavedPreset]
    var undoHistory: [UUID: [EditRecipe]]? = nil
    var redoHistory: [UUID: [EditRecipe]]? = nil
}
struct PreparedPhoto {
    let original: CGImage
    let faces: [FaceRegion]
    let width: Int
    let height: Int
}

// All expensive image work is serialized off the main actor, including export.
actor MobileProcessor {
    let engine = ImageEngine()
    func prepare(_ url: URL) throws -> PreparedPhoto {
        let image = try engine.load(url: url, maxDimension: 1200)
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = props[kCGImagePropertyPixelWidth] as? Int,
              let height = props[kCGImagePropertyPixelHeight] as? Int else {
            throw ImageEngineError.message("사진 크기를 읽을 수 없습니다.")
        }
        let orientation = (props[kCGImagePropertyOrientation] as? Int) ?? 1
        return PreparedPhoto(original: try engine.cgImage(image), faces: try engine.detectFaces(in: image),
                             width: orientation >= 5 ? height : width, height: orientation >= 5 ? width : height)
    }
    func preview(_ url: URL, recipe: EditRecipe, faces: [FaceRegion]) throws -> CGImage {
        let image = try engine.load(url: url, maxDimension: 1200)
        return try engine.cgImage(engine.render(image, recipe: recipe, faces: faces))
    }
    func export(_ url: URL, recipe: EditRecipe, output: URL, fullResolution: Bool) throws {
        // A conservative default for older iPhones; original resolution is an explicit option.
        let image = try engine.load(url: url, maxDimension: fullResolution ? nil : 4096)
        let faceImage = try engine.load(url: url, maxDimension: 1200)
        let faces = try engine.detectFaces(in: faceImage)
        try engine.export(engine.render(image, recipe: recipe, faces: faces), to: output, format: .jpeg)
    }
}

enum MobileTool: String, CaseIterable { case color = "색감", portrait = "인물", retouch = "잡티", warp = "변형" }

@MainActor final class MobileStore: ObservableObject {
    @Published var photos: [MobilePhoto] = []
    @Published var selectedID: UUID?
    @Published var pickerItems: [PhotosPickerItem] = []
    @Published var preview: UIImage?
    @Published var original: UIImage?
    @Published var thumbnails: [UUID: UIImage] = [:]
    @Published var faces: [FaceRegion] = []
    @Published var dimensions = ""
    @Published var importing = false
    @Published var exporting = false
    @Published var rendering = false
    @Published var ready = false
    @Published var restoring = true
    @Published var compare = false
    @Published var tool = MobileTool.color
    @Published var brushRadius = 0.025
    @Published var cloneSource: CGPoint?
    @Published var choosingSource = true
    @Published var status = "사진을 골라 시작해보세요."
    @Published var error: String?
    @Published var undoHistory: [UUID: [EditRecipe]] = [:]
    @Published var redoHistory: [UUID: [EditRecipe]] = [:]
    @Published var presets: [SavedPreset] = []
    @Published var presetName = ""
    @Published var presetSheet = false
    @Published var resetConfirmation = false
    @Published var removeConfirmation = false
    @Published var fullResolution = false
    @Published var cancelExport = false
    @Published var progress = 0.0
    private let processor = MobileProcessor()
    private var renderTask: Task<Void, Never>?
    private var selectionTask: Task<Void, Never>?
    private var generation = 0
    private var sliding = false
    let root: URL
    var sessionURL: URL { root.appendingPathComponent("session.json") }
    var selectedIndex: Int? { photos.firstIndex { $0.id == selectedID } }
    var selected: MobilePhoto? { selectedIndex.map { photos[$0] } }
    var recipe: EditRecipe { selected?.recipe ?? EditRecipe() }
    var busy: Bool { importing || exporting || restoring }
    var canUndo: Bool { selectedID.map { !(undoHistory[$0] ?? []).isEmpty } ?? false }
    var canRedo: Bool { selectedID.map { !(redoHistory[$0] ?? []).isEmpty } ?? false }
    var geometryLocked: Bool { !recipe.operations.isEmpty }
    var displayImage: UIImage? { compare ? original : (preview ?? original) }
    func url(_ photo: MobilePhoto) -> URL { root.appendingPathComponent(photo.filename) }

    init(root: URL? = nil) {
        self.root = root ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("MellowPhoto", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: self.root, withIntermediateDirectories: true)
            // Private working copies should not be included in device cloud backups.
            var folder = self.root
            var values = URLResourceValues(); values.isExcludedFromBackup = true
            try folder.setResourceValues(values)
            if FileManager.default.fileExists(atPath: sessionURL.path) {
                let session = try JSONDecoder().decode(MobileSession.self, from: Data(contentsOf: sessionURL))
                photos = session.photos
                presets = session.presets
                undoHistory = session.undoHistory ?? [:]
                redoHistory = session.redoHistory ?? [:]
                selectedID = photos.contains(where: { $0.id == session.selectedID }) ? session.selectedID : photos.first?.id
            }
        } catch { self.error = "작업 기록을 불러오지 못했습니다: \(error.localizedDescription)" }
    }
    func stopWork() { renderTask?.cancel(); selectionTask?.cancel(); generation += 1 }
    func restore() async {
        guard restoring else { return }
        for photo in photos {
            do {
                let prepared = try await processor.prepare(url(photo))
                thumbnails[photo.id] = thumbnail(prepared.original)
            } catch { self.error = "일부 작업 사진을 열지 못했습니다. 해당 사진을 다시 가져오세요." }
        }
        restoring = false
        if let id = selectedID { select(id) }
    }
    private func thumbnail(_ image: CGImage) -> UIImage {
        let scale = min(90 / CGFloat(image.width), 110 / CGFloat(image.height))
        let size = CGSize(width: CGFloat(image.width) * scale, height: CGFloat(image.height) * scale)
        return UIGraphicsImageRenderer(size: size).image { _ in UIImage(cgImage: image).draw(in: CGRect(origin: .zero, size: size)) }
    }
    func persist() {
        do {
            let session = MobileSession(photos: photos, selectedID: selectedID, presets: presets, undoHistory: undoHistory, redoHistory: redoHistory)
            try JSONEncoder().encode(session).write(to: sessionURL, options: [.atomic, .completeFileProtectionUnlessOpen])
        } catch { self.error = "편집 기록 저장 실패: \(error.localizedDescription)" }
    }
    func importSelected() async {
        guard !busy else { return }
        let items = pickerItems; pickerItems = []
        guard !items.isEmpty else { return }
        importing = true
        defer { importing = false }
        var failures = 0
        for (index, item) in items.prefix(max(0, 12 - photos.count)).enumerated() {
            status = "사진 가져오는 중 \(index + 1) / \(items.count)"
            var importedURL: URL?
            var destination: URL?
            do {
                guard let imported = try await item.loadTransferable(type: ImportedPhoto.self) else { throw ImageEngineError.message("사진을 다운로드하지 못했습니다.") }
                importedURL = imported.url
                let id = UUID()
                let filename = id.uuidString + "." + (imported.url.pathExtension.isEmpty ? "image" : imported.url.pathExtension)
                let photo = MobilePhoto(id: id, filename: filename, name: "사진 \(photos.count + 1)")
                destination = url(photo)
                try FileManager.default.moveItem(at: imported.url, to: url(photo))
                try FileManager.default.setAttributes([.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication], ofItemAtPath: url(photo).path)
                let prepared = try await processor.prepare(url(photo))
                photos.append(photo)
                thumbnails[id] = thumbnail(prepared.original)
                destination = nil
                if selectedID == nil { select(id) }
                persist()
            } catch { failures += 1 }
            if let importedURL { try? FileManager.default.removeItem(at: importedURL) }
            if let destination { try? FileManager.default.removeItem(at: destination) }
        }
        status = "\(photos.count)장 · 편집 기록은 이 iPhone에 저장됩니다."
        if failures > 0 { error = "\(failures)장을 가져오지 못했습니다. iCloud 사진은 다운로드 가능한 상태에서 다시 선택해 주세요." }
    }
    func select(_ id: UUID) {
        guard !exporting, photos.contains(where: { $0.id == id }) else { return }
        selectedID = id; preview = nil; original = nil; faces = []; ready = false
        compare = false; cloneSource = nil; choosingSource = true; sliding = false
        renderTask?.cancel(); selectionTask?.cancel(); generation += 1
        guard let photo = selected else { return }
        let ticket = generation
        selectionTask = Task {
            do {
                let prepared = try await processor.prepare(url(photo))
                guard !Task.isCancelled, generation == ticket, selectedID == id else { return }
                original = UIImage(cgImage: prepared.original); faces = prepared.faces
                dimensions = "\(prepared.width) × \(prepared.height)"
                ready = true; scheduleRender()
            } catch { if selectedID == id { self.error = error.localizedDescription } }
        }
        persist()
    }
    func checkpoint() {
        guard let id = selectedID else { return }
        var history = undoHistory[id] ?? []
        if history.last != recipe { history.append(recipe) }
        undoHistory[id] = Array(history.suffix(40)); redoHistory[id] = []
    }
    func sliderEditing(_ editing: Bool) {
        if editing { checkpoint() }
        sliding = editing
        if !editing { persist() }
    }
    func change(_ key: WritableKeyPath<Adjustments, Double>, _ value: Double) {
        guard let index = selectedIndex, ready, !busy else { return }
        guard key != \.faceSlim || !geometryLocked else { return }
        if !sliding { checkpoint() }
        photos[index].recipe.adjustments[keyPath: key] = value
        scheduleRender(); persist()
    }
    func setFace(_ index: Int?) {
        guard let i = selectedIndex, !geometryLocked, !busy else { return }
        checkpoint(); photos[i].recipe.selectedFace = index; changed()
    }
    func apply(_ adjustments: Adjustments) {
        guard let i = selectedIndex, !busy else { return }
        checkpoint()
        var values = adjustments
        if geometryLocked { values.faceSlim = recipe.adjustments.faceSlim }
        photos[i].recipe.adjustments = values; changed()
    }
    func applyAll() {
        guard selected != nil, !busy else { return }
        let values = recipe.adjustments
        for i in photos.indices where photos[i].id != selectedID {
            let id = photos[i].id
            undoHistory[id] = Array(((undoHistory[id] ?? []) + [photos[i].recipe]).suffix(40)); redoHistory[id] = []
            var adjusted = values
            if !photos[i].recipe.operations.isEmpty { adjusted.faceSlim = photos[i].recipe.adjustments.faceSlim }
            else { photos[i].recipe.selectedFace = nil }
            photos[i].recipe.adjustments = adjusted
        }
        persist(); status = "전체 사진에 슬라이더 설정을 적용했어요."
    }
    func undo() {
        guard !busy, let i = selectedIndex, let old = undoHistory[photos[i].id]?.popLast() else { return }
        redoHistory[photos[i].id, default: []].append(recipe); photos[i].recipe = old; changed()
    }
    func redo() {
        guard !busy, let i = selectedIndex, let next = redoHistory[photos[i].id]?.popLast() else { return }
        undoHistory[photos[i].id, default: []].append(recipe); photos[i].recipe = next; changed()
    }
    func reset() {
        guard !busy, let i = selectedIndex else { return }
        checkpoint(); photos[i].recipe = EditRecipe(); cloneSource = nil; choosingSource = true; changed()
    }
    func removeSelected() {
        guard !busy, let photo = selected else { return }
        // Only the app's working copy is removed. The Photos library original is untouched.
        photos.removeAll { $0.id == photo.id }; thumbnails[photo.id] = nil
        undoHistory[photo.id] = nil; redoHistory[photo.id] = nil
        selectedID = nil; preview = nil; original = nil; ready = false
        generation += 1; selectionTask?.cancel(); renderTask?.cancel(); rendering = false
        persist()
        try? FileManager.default.removeItem(at: url(photo))
        if let next = photos.first { select(next.id) }
    }
    func savePreset() {
        let name = presetName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        presets.append(SavedPreset(name: String(name.prefix(30)), adjustments: recipe.adjustments))
        persist(); presetSheet = false; presetName = ""
    }
    func touch(from: CGPoint, to: CGPoint) {
        guard let i = selectedIndex, ready, !busy, !compare, !rendering else { return }
        if tool == .retouch {
            if choosingSource || cloneSource == nil {
                cloneSource = to; choosingSource = false; status = "이제 보정할 작은 잡티를 톡 눌러주세요."; return
            }
            guard let source = cloneSource else { return }
            checkpoint()
            photos[i].recipe.operations.append(.spot(RetouchSpot(x: to.x, y: to.y, sourceX: source.x, sourceY: source.y, radius: brushRadius)))
        } else if tool == .warp {
            let dx = max(-0.08, min(0.08, to.x - from.x)), dy = max(-0.08, min(0.08, to.y - from.y))
            guard abs(dx) + abs(dy) > 0.001 else { return }
            checkpoint(); photos[i].recipe.operations.append(.warp(WarpStroke(x: from.x, y: from.y, dx: dx, dy: dy, radius: brushRadius * 3)))
        } else { return }
        changed()
    }
    private func changed() { scheduleRender(); persist() }
    func scheduleRender() {
        renderTask?.cancel(); generation += 1
        guard let photo = selected, ready else { return }
        let ticket = generation, faceSnapshot = faces
        rendering = true
        renderTask = Task {
            do {
                try await Task.sleep(nanoseconds: 130_000_000)
                guard !Task.isCancelled else { return }
                let image = try await processor.preview(url(photo), recipe: photo.recipe, faces: faceSnapshot)
                guard !Task.isCancelled, generation == ticket else { return }
                preview = UIImage(cgImage: image); rendering = false
            } catch {
                guard !Task.isCancelled, generation == ticket else { return }
                rendering = false; self.error = error.localizedDescription
            }
        }
    }
    func saveToPhotos(all: Bool) async {
        guard !busy, ready, let current = selected else { return }
        exporting = true; cancelExport = false; progress = 0
        defer { exporting = false }
        let permission = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard permission == .authorized || permission == .limited else {
            error = "사진 저장 권한이 꺼져 있습니다. iPhone 설정 → 앱 → Mellow Photo → 사진에서 사진 추가를 허용해 주세요."; return
        }
        let items = all ? photos : [current], useFullResolution = fullResolution
        var saved = 0
        var failures = 0
        for (index, photo) in items.enumerated() {
            if cancelExport || Task.isCancelled { break }
            status = "사진에 저장 중 \(index + 1) / \(items.count)"
            let output = FileManager.default.temporaryDirectory.appendingPathComponent("mellow-\(UUID().uuidString).jpg")
            do {
                try await processor.export(url(photo), recipe: photo.recipe, output: output, fullResolution: useFullResolution)
                try await PHPhotoLibrary.shared().performChanges {
                    PHAssetChangeRequest.creationRequestForAssetFromImage(atFileURL: output)
                }
                saved += 1
            } catch { failures += 1 }
            try? FileManager.default.removeItem(at: output)
            progress = Double(index + 1) / Double(items.count)
        }
        status = "\(saved)장 저장 완료 · 원본은 그대로예요."
        if failures > 0 { error = "\(failures)장을 저장하지 못했습니다. 저장 공간을 확인하거나 원본 해상도 옵션을 끄고 다시 시도해 주세요." }
    }
}
