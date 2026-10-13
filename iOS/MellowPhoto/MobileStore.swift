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
    var faceAnalysisWarning: String? = nil
}

// All expensive image work is serialized off the main actor, including export.
actor MobileProcessor {
    let engine: ImageEngine
    private let detectFaces: @Sendable (CIImage) throws -> [FaceRegion]
    init(faceDetector: (@Sendable (CIImage) throws -> [FaceRegion])? = nil) {
        let engine = ImageEngine()
        self.engine = engine
        self.detectFaces = faceDetector ?? { try engine.detectFaces(in: $0) }
    }
    func prepare(_ url: URL) throws -> PreparedPhoto {
        let image = try engine.load(url: url, maxDimension: 1200)
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = props[kCGImagePropertyPixelWidth] as? Int,
              let height = props[kCGImagePropertyPixelHeight] as? Int else {
            throw ImageEngineError.message("사진 크기를 읽을 수 없습니다.")
        }
        let orientation = (props[kCGImagePropertyOrientation] as? Int) ?? 1
        let original = try engine.cgImage(image)
        var faces: [FaceRegion] = []
        var warning: String?
        do { faces = try detectFaces(image) }
        catch { warning = "자동 얼굴 분석을 사용할 수 없습니다. 색감·수동 보정은 사용할 수 있어요. (\(error.localizedDescription))" }
        return PreparedPhoto(original: original, faces: faces,
                             width: orientation >= 5 ? height : width, height: orientation >= 5 ? width : height,
                             faceAnalysisWarning: warning)
    }
    func preview(_ url: URL, recipe: EditRecipe, faces: [FaceRegion]) throws -> CGImage {
        let image = try engine.load(url: url, maxDimension: 1200)
        return try engine.cgImage(engine.render(image, recipe: recipe, faces: faces))
    }
    func export(_ url: URL, recipe: EditRecipe, output: URL, fullResolution: Bool) throws {
        // A conservative default for older iPhones; original resolution is an explicit option.
        let image = try engine.load(url: url, maxDimension: fullResolution ? nil : 4096)
        var faces: [FaceRegion] = []
        if recipe.adjustments.skin > 0 || recipe.adjustments.faceSlim > 0 {
            let faceImage = try engine.load(url: url, maxDimension: 1200)
            do { faces = try detectFaces(faceImage) }
            catch { throw ImageEngineError.message("얼굴 보정을 적용할 수 없어 저장을 중단했습니다. 얼굴 분석을 다시 시도하거나 피부·얼굴 보정을 끄세요. (\(error.localizedDescription))") }
        }
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
    @Published private(set) var faceAnalysisWarning: String?
    @Published var dimensions = ""
    @Published var importing = false
    @Published var exporting = false
    @Published var rendering = false
    @Published var ready = false
    @Published private(set) var selectionError: String?
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
    @Published var infoSheet = false
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
    private var sessionNeedsRecovery = false
    private(set) var recoverySessionURL: URL?
    let root: URL
    var sessionURL: URL { root.appendingPathComponent("session.json") }
    var selectedIndex: Int? { photos.firstIndex { $0.id == selectedID } }
    var selected: MobilePhoto? { selectedIndex.map { photos[$0] } }
    var recipe: EditRecipe { selected?.recipe ?? EditRecipe() }
    var busy: Bool { importing || exporting || restoring }
    var canUndo: Bool { selectedID.map { !(undoHistory[$0] ?? []).isEmpty } ?? false }
    var canRedo: Bool { selectedID.map { !(redoHistory[$0] ?? []).isEmpty } ?? false }
    var canRemoveSelected: Bool { !busy && selected != nil }
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
                do {
                    let session = try JSONDecoder().decode(MobileSession.self, from: Data(contentsOf: sessionURL))
                    photos = session.photos
                    presets = session.presets
                    undoHistory = session.undoHistory ?? [:]
                    redoHistory = session.redoHistory ?? [:]
                    selectedID = photos.contains(where: { $0.id == session.selectedID }) ? session.selectedID : photos.first?.id
                } catch {
                    // Preserve the exact unreadable bytes before allowing a new session to replace them.
                    sessionNeedsRecovery = true
                    do {
                        try preserveUnreadableSession()
                        self.error = "작업 기록을 읽지 못해 복구용 사본을 보관했습니다. 기존 작업 사진도 보존됩니다. 사진을 다시 골라 편집할 수 있어요."
                    } catch {
                        self.error = "기존 작업 기록을 보관하지 못했습니다. 기록을 보호하기 위해 저장을 중단합니다: \(error.localizedDescription)"
                    }
                }
            }
        } catch { self.error = "작업 폴더를 열지 못했습니다: \(error.localizedDescription)" }
    }
    private func preserveUnreadableSession() throws {
        guard sessionNeedsRecovery else { return }
        let backup = root.appendingPathComponent("session-recovery-\(UUID().uuidString).json")
        try FileManager.default.copyItem(at: sessionURL, to: backup)
        recoverySessionURL = backup
        sessionNeedsRecovery = false
    }
    private func writeSession(_ session: MobileSession) throws {
        try preserveUnreadableSession()
        try JSONEncoder().encode(session).write(to: sessionURL, options: [.atomic, .completeFileProtectionUnlessOpen])
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
    @discardableResult func persist() -> Bool {
        do {
            let session = MobileSession(photos: photos, selectedID: selectedID, presets: presets, undoHistory: undoHistory, redoHistory: redoHistory)
            try writeSession(session)
            return true
        } catch {
            self.error = "편집 기록 저장 실패: \(error.localizedDescription)"
            return false
        }
    }
    func importSelected() async {
        guard !busy else { return }
        let items = pickerItems; pickerItems = []
        guard !items.isEmpty else { return }
        importing = true
        defer { importing = false }
        var failures: [String] = []
        var warnings: [String] = []
        for (index, item) in items.prefix(max(0, 12 - photos.count)).enumerated() {
            status = "사진 가져오는 중 \(index + 1) / \(items.count)"
            var importedURL: URL?
            var destination: URL?
            var stage = "사진 전달"
            do {
                guard let imported = try await item.loadTransferable(type: ImportedPhoto.self) else { throw ImageEngineError.message("사진을 다운로드하지 못했습니다.") }
                importedURL = imported.url
                let id = UUID()
                let filename = id.uuidString + "." + (imported.url.pathExtension.isEmpty ? "image" : imported.url.pathExtension)
                let photo = MobilePhoto(id: id, filename: filename, name: "사진 \(photos.count + 1)")
                destination = url(photo)
                stage = "작업 사본 저장"
                try FileManager.default.moveItem(at: imported.url, to: url(photo))
                stage = "사진 파일 보호 설정"
                try FileManager.default.setAttributes([.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication], ofItemAtPath: url(photo).path)
                stage = "사진 읽기·미리보기 준비"
                let prepared = try await processor.prepare(url(photo))
                if let warning = prepared.faceAnalysisWarning { warnings.append("사진 \(index + 1): \(warning)") }
                photos.append(photo)
                thumbnails[id] = thumbnail(prepared.original)
                destination = nil
                if selectedID == nil { select(id) }
                persist()
            } catch { failures.append("사진 \(index + 1) · \(stage): \(error.localizedDescription)") }
            if let importedURL { try? FileManager.default.removeItem(at: importedURL) }
            if let destination { try? FileManager.default.removeItem(at: destination) }
        }
        status = "\(photos.count)장 · 편집 기록은 이 iPhone에 저장됩니다."
        if !failures.isEmpty { error = "\(failures.count)장을 가져오지 못했습니다.\n" + failures.prefix(3).joined(separator: "\n") }
        else if !warnings.isEmpty { error = warnings.prefix(3).joined(separator: "\n") }
    }
    func select(_ id: UUID) {
        guard !exporting, photos.contains(where: { $0.id == id }) else { return }
        selectedID = id; preview = nil; original = nil; faces = []; ready = false
        selectionError = nil; faceAnalysisWarning = nil; dimensions = ""; rendering = false
        compare = false; cloneSource = nil; choosingSource = true; sliding = false
        renderTask?.cancel(); selectionTask?.cancel(); generation += 1
        guard let photo = selected else { return }
        let ticket = generation
        selectionTask = Task {
            do {
                let prepared = try await processor.prepare(url(photo))
                guard !Task.isCancelled, generation == ticket, selectedID == id else { return }
                original = UIImage(cgImage: prepared.original); faces = prepared.faces
                faceAnalysisWarning = prepared.faceAnalysisWarning
                dimensions = "\(prepared.width) × \(prepared.height)"
                ready = true; scheduleRender()
            } catch {
                guard !Task.isCancelled, generation == ticket, selectedID == id else { return }
                selectionError = "이 작업 사진을 열 수 없습니다. 다시 시도하거나 편집에서 뺀 뒤 사진을 다시 골라주세요."
                rendering = false
                self.error = error.localizedDescription
            }
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
        guard canRemoveSelected, let photo = selected else { return }
        let remaining = photos.filter { $0.id != photo.id }
        var remainingUndo = undoHistory, remainingRedo = redoHistory
        remainingUndo[photo.id] = nil; remainingRedo[photo.id] = nil
        // Commit the updated record first. On failure the current photo, history and file stay intact.
        do {
            try writeSession(MobileSession(photos: remaining, selectedID: remaining.first?.id, presets: presets,
                                           undoHistory: remainingUndo, redoHistory: remainingRedo))
        } catch {
            self.error = "사진을 빼지 못했습니다. 작업 사진과 보정 기록은 그대로 유지됩니다: \(error.localizedDescription)"
            return
        }
        photos = remaining; thumbnails[photo.id] = nil
        undoHistory = remainingUndo; redoHistory = remainingRedo
        selectedID = nil; preview = nil; original = nil; ready = false; selectionError = nil; faceAnalysisWarning = nil; dimensions = ""
        generation += 1; selectionTask?.cancel(); renderTask?.cancel(); rendering = false
        // Only the app's working copy is removed. The Photos library original is untouched.
        if FileManager.default.fileExists(atPath: url(photo).path) {
            do { try FileManager.default.removeItem(at: url(photo)) }
            catch { self.error = "편집 목록에서 뺐지만 작업 사본을 정리하지 못했습니다: \(error.localizedDescription)" }
        }
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
        var failures: [String] = []
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
            } catch { failures.append("\(photo.name): \(error.localizedDescription)") }
            try? FileManager.default.removeItem(at: output)
            progress = Double(index + 1) / Double(items.count)
        }
        status = "\(saved)장 저장 완료 · 원본은 그대로예요."
        if !failures.isEmpty { error = "\(failures.count)장을 저장하지 못했습니다.\n" + failures.prefix(3).joined(separator: "\n") }
    }
}
