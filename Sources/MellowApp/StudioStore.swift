import SwiftUI
import AppKit
import CoreImage
import UniformTypeIdentifiers
import MellowCore

enum EditorTool: String, CaseIterable {
    case adjust = "둘러보기", retouch = "잡티 보정", warp = "부분 변형"
    var symbol: String { switch self { case .adjust: return "cursorarrow"; case .retouch: return "bandage"; case .warp: return "arrow.up.left.and.arrow.down.right" } }
}

struct PhotoItem: Identifiable {
    let id = UUID()
    let url: URL
    let original: NSImage
    let image: CIImage
    let faces: [FaceRegion]
    let fullSize: CGSize
    var recipe = EditRecipe()
    var undo: [EditRecipe] = []
    var redo: [EditRecipe] = []
}

@MainActor final class StudioStore: ObservableObject {
    @Published var activeTab = 0
    @Published var presetSheet = false
    @Published var presetName = ""
    @Published var dropTargeted = false
    @Published var resetConfirmation = false
    @Published var photos: [PhotoItem] = []
    @Published var selectedID: UUID?
    @Published var rendered: NSImage?
    @Published var importing = false
    @Published var exporting = false
    @Published var rendering = false
    @Published var progress = 0.0
    @Published var status = "사진을 가져와 나만의 분위기를 만들어보세요."
    @Published var error: String?
    @Published var tool: EditorTool = .adjust
    @Published var brushRadius = 0.035
    @Published var cloneSource: CGPoint?
    @Published var compare = false
    @Published var zoom = 1.0
    @Published var presets: [SavedPreset] = []
    @Published var exportFormat: ExportFormat = .jpeg
    @Published var cancelExport = false
    private let engine = ImageEngine()
    private var renderTask: Task<Void, Never>?
    private var generation = 0
    private let renderQueue = DispatchQueue(label: "mellow.render", qos: .userInitiated)
    var selectedIndex: Int? { photos.firstIndex { $0.id == selectedID } }
    var selected: PhotoItem? { selectedIndex.map { photos[$0] } }
    var recipe: EditRecipe { selected?.recipe ?? EditRecipe() }
    var canUndo: Bool { !(selected?.undo.isEmpty ?? true) }
    var canRedo: Bool { !(selected?.redo.isEmpty ?? true) }
    var hasEdits: Bool { photos.contains { $0.recipe != EditRecipe() } }
    var displayImage: NSImage? { compare ? selected?.original : (rendered ?? selected?.original) }
    var presetURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("MellowPhoto", isDirectory: true).appendingPathComponent("presets.json")
    }
    init() {
        if let d = try? Data(contentsOf: presetURL), let p = try? JSONDecoder().decode([SavedPreset].self, from: d) { presets = p }
    }
    func choosePhotos() {
        let panel = NSOpenPanel()
        panel.title = "보정할 사진 선택"
        panel.allowedContentTypes = [.jpeg, .png, .heic, .heif, .tiff]
        panel.allowsMultipleSelection = true
        if panel.runModal() == .OK { importPhotos(panel.urls) }
    }
    func importPhotos(_ urls: [URL]) {
        guard !importing, !exporting else { return }
        let current = Set(photos.map { $0.url.standardizedFileURL.path })
        var seen = current
        let candidates = urls.filter { seen.insert($0.standardizedFileURL.path).inserted }
        let unique = Array(candidates.prefix(max(0, 40 - photos.count)))
        if candidates.count > unique.count { error = "첫 버전은 한 번에 최대 40장을 편집할 수 있습니다. 이번에는 \(unique.count)장을 추가합니다." }
        guard !unique.isEmpty else { status = "이미 가져온 사진입니다."; return }
        importing = true
        Task {
            var failures: [String] = []
            for (offset, url) in unique.enumerated() {
                status = "사진 가져오는 중 \(offset + 1) / \(unique.count)"
                do {
                    let engine = self.engine
                    let prepared = try await Task.detached(priority: .userInitiated) { () -> (CIImage, CGImage, [FaceRegion], CGSize, Bool) in
                        let full = try engine.load(url: url)
                        let image = try engine.load(url: url, maxDimension: 1600)
                        var faces: [FaceRegion] = []
                        var faceFailed = false
                        do { faces = try engine.detectFaces(in: image) } catch { faceFailed = true }
                        return (image, try engine.cgImage(image), faces, full.extent.size, faceFailed)
                    }.value
                    let item = PhotoItem(url: url, original: NSImage(cgImage: prepared.1, size: prepared.0.extent.size), image: prepared.0, faces: prepared.2, fullSize: prepared.3)
                    photos.append(item)
                    if selectedID == nil { select(item.id) }
                    if prepared.4 { failures.append("\(url.lastPathComponent): 얼굴을 찾지 못해 수동 도구만 사용할 수 있습니다.") }
                } catch { failures.append("\(url.lastPathComponent): \(error.localizedDescription)") }
            }
            importing = false
            status = "\(photos.count)장의 사진 · 모든 보정은 이 Mac에서 처리됩니다."
            if !failures.isEmpty { error = failures.joined(separator: "\n") }
        }
    }
    func select(_ id: UUID) {
        selectedID = id; rendered = nil; compare = false; cloneSource = nil; zoom = 1
        scheduleRender()
    }
    func checkpoint() {
        guard let i = selectedIndex else { return }
        if photos[i].undo.last != photos[i].recipe { photos[i].undo.append(photos[i].recipe) }
        if photos[i].undo.count > 60 { photos[i].undo.removeFirst() }
        photos[i].redo.removeAll()
    }
    func change(_ key: WritableKeyPath<Adjustments, Double>, _ value: Double) {
        guard let i = selectedIndex else { return }
        if key == \Adjustments.faceSlim, !photos[i].recipe.operations.isEmpty {
            status = "수동 보정 위치를 유지하려면 얼굴 슬림은 수동 작업을 되돌린 뒤 변경하세요."
            return
        }
        photos[i].recipe.adjustments[keyPath: key] = value
        scheduleRender()
    }
    func selectFace(_ index: Int?) {
        guard let i = selectedIndex else { return }
        if !photos[i].recipe.operations.isEmpty, photos[i].recipe.adjustments.faceSlim != 0 {
            status = "수동 보정 위치를 유지하기 위해 얼굴 슬림 대상이 고정되어 있습니다."
            return
        }
        checkpoint()
        photos[i].recipe.selectedFace = index
        scheduleRender()
    }
    func undo() {
        guard let i = selectedIndex, let old = photos[i].undo.popLast() else { return }
        photos[i].redo.append(photos[i].recipe); photos[i].recipe = old; scheduleRender()
    }
    func redo() {
        guard let i = selectedIndex, let next = photos[i].redo.popLast() else { return }
        photos[i].undo.append(photos[i].recipe); photos[i].recipe = next; scheduleRender()
    }
    func reset() {
        checkpoint(); guard let i = selectedIndex else { return }
        photos[i].recipe = EditRecipe(); cloneSource = nil; scheduleRender()
    }
    func applyPreset(_ adjustments: Adjustments) {
        checkpoint(); guard let i = selectedIndex else { return }
        var safeAdjustments = adjustments
        if !photos[i].recipe.operations.isEmpty {
            safeAdjustments.faceSlim = photos[i].recipe.adjustments.faceSlim
            status = "프리셋을 적용했습니다. 수동 보정 위치를 위해 얼굴 슬림은 유지합니다."
        }
        photos[i].recipe.adjustments = safeAdjustments; scheduleRender()
    }
    func savePreset(name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let new = SavedPreset(name: String(trimmed.prefix(32)), adjustments: recipe.adjustments)
        let next = presets + [new]
        do {
            try FileManager.default.createDirectory(at: presetURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(next).write(to: presetURL, options: .atomic)
            presets = next; status = "‘\(new.name)’ 프리셋을 저장했습니다."
        } catch { self.error = "프리셋 저장 실패: \(error.localizedDescription)" }
    }
    func copyAdjustmentsToAll() {
        guard selected != nil else { return }
        let values = recipe.adjustments
        for i in photos.indices where photos[i].id != selectedID {
            photos[i].undo.append(photos[i].recipe); photos[i].redo.removeAll()
            var safeValues = values
            if photos[i].recipe.operations.isEmpty {
                photos[i].recipe.selectedFace = nil
            } else {
                // Both strength and face target define the geometry beneath local edits.
                safeValues.faceSlim = photos[i].recipe.adjustments.faceSlim
            }
            photos[i].recipe.adjustments = safeValues
        }
        status = "전체 사진에 설정을 적용했습니다. 수동 보정 사진의 얼굴 슬림은 유지하며 잡티·드래그 위치는 복사하지 않습니다."
    }
    func retouch(at point: CGPoint, setSource: Bool) {
        guard selected != nil, !compare else { return }
        if setSource || cloneSource == nil { cloneSource = point; status = "샘플 위치를 지정했습니다. 보정할 잡티를 클릭하세요."; return }
        guard let source = cloneSource, let i = selectedIndex else { return }
        checkpoint()
        photos[i].recipe.operations.append(.spot(RetouchSpot(x: point.x, y: point.y, sourceX: source.x, sourceY: source.y, radius: brushRadius)))
        scheduleRender()
    }
    func warp(from: CGPoint, to: CGPoint) {
        guard let i = selectedIndex, !compare else { return }
        let dx = max(-0.08, min(0.08, to.x - from.x))
        let dy = max(-0.08, min(0.08, to.y - from.y))
        guard abs(dx) + abs(dy) > 0.0005 else { return }
        checkpoint()
        photos[i].recipe.operations.append(.warp(WarpStroke(x: from.x, y: from.y, dx: dx, dy: dy, radius: brushRadius * 3)))
        scheduleRender()
    }
    func scheduleRender() {
        renderTask?.cancel(); generation += 1
        guard let item = selected else { rendered = nil; return }
        let ticket = generation
        rendering = true
        renderTask = Task {
            do { try await Task.sleep(nanoseconds: 120_000_000) } catch { return }
            if Task.isCancelled { return }
            let engine = self.engine
            let result: Result<CGImage, Error> = await withCheckedContinuation { continuation in
                renderQueue.async {
                    continuation.resume(returning: Result { try engine.cgImage(engine.render(item.image, recipe: item.recipe, faces: item.faces)) })
                }
            }
            guard ticket == generation, selectedID == item.id, !Task.isCancelled else { return }
            rendering = false
            switch result {
            case .success(let cg): rendered = NSImage(cgImage: cg, size: item.image.extent.size)
            case .failure(let e): error = "미리보기 생성 실패: \(e.localizedDescription)"
            }
        }
    }
    func export(all: Bool) {
        guard !exporting, !importing, let current = selected else { return }
        let items = all ? photos : [current]
        let panel = NSOpenPanel()
        panel.title = "보정된 사진을 저장할 폴더 선택"
        panel.prompt = "여기에 저장"
        panel.canChooseFiles = false; panel.canChooseDirectories = true; panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let folder = panel.url else { return }
        let format = exportFormat
        exporting = true; cancelExport = false; progress = 0
        Task {
            var failures: [String] = []
            var count = 0
            for (index, item) in items.enumerated() {
                if cancelExport { break }
                status = "원본 해상도로 저장 중 \(index + 1) / \(items.count)"
                do {
                    let engine = self.engine
                    try await Task.detached(priority: .userInitiated) {
                        let full = try engine.load(url: item.url)
                        // Normalized preview landmarks map to full resolution without changing face ordering.
                        let output = try engine.render(full, recipe: item.recipe, faces: item.faces)
                        let stem = item.url.deletingPathExtension().lastPathComponent + "_mellow"
                        var target = folder.appendingPathComponent(stem).appendingPathExtension(format.fileExtension)
                        var suffix = 2
                        while FileManager.default.fileExists(atPath: target.path) {
                            target = folder.appendingPathComponent("\(stem)_\(suffix)").appendingPathExtension(format.fileExtension); suffix += 1
                        }
                        try engine.export(output, to: target, format: format)
                    }.value
                    count += 1
                } catch { failures.append("\(item.url.lastPathComponent): \(error.localizedDescription)") }
                progress = Double(index + 1) / Double(items.count)
            }
            exporting = false
            status = "\(count)장 저장 완료\(cancelExport ? " · 나머지 작업 취소" : "") · 원본은 그대로 유지됩니다."
            if !failures.isEmpty { error = failures.joined(separator: "\n") }
            if count > 0 { NSWorkspace.shared.open(folder) }
        }
    }
}
