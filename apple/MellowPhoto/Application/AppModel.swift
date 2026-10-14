import CoreGraphics
import Foundation
import MellowEditing
import MellowExport
import MellowLibrary
import MellowRendering
import MellowShared
import Observation

struct PresentedError: Identifiable, Equatable {
    let id = UUID()
    let message: String
}

/// composition root. 세션·파이프라인·어댑터를 묶고 화면이 읽는 상태를 가진다.
@MainActor
@Observable
final class AppModel {
    struct PhotoInfo {
        var pixelSize: CGSize
        var faces: [FaceGeometry]
        var faceAnalysisFailure: MellowError?
    }

    enum Policy {
        static let brushRadiusRange = 0.008...0.07
        static let defaultBrushRadius = 0.025
        static let warpRadiusMultiplier = 3.0
        static let warpMaxDelta = 0.08
        static let warpMinimumDelta = 0.001
        static let renderDebounce = Duration.milliseconds(100)
        /// 알림에 나열하는 실패·경고 줄 수. 나머지는 개수로만 알린다.
        static let listedIssueLimit = 3
    }

    let session: ProjectSession
    let pipeline: PhotoPipeline
    let copies: WorkingCopyStore
    let importer: any PhotoImporter
    let exporter: Exporter

    var thumbnails: [PhotoID: CGImage] = [:]
    var photoInfo: [PhotoID: PhotoInfo] = [:]
    var preview: CGImage?
    var original: CGImage?
    var isReady = false
    var isRendering = false
    var isImporting = false
    var isExporting = false
    var isRestoring = false
    /// 창을 새로 열 때마다 화면의 `.task`가 restore()를 다시 부르므로 한 번만 실행한다.
    private(set) var hasRestored = false
    var exportProgress = 0.0
    var statusMessage = UserMessage.welcomeStatus
    var presentedError: PresentedError?
    var selectionFailure: String?

    var tool: EditorTool = .color
    var brushRadius = Policy.defaultBrushRadius
    var cloneSource: NormalizedPoint?
    var isChoosingCloneSource = true
    var isComparing = false
    var exportOptions = ExportOptions()

    /// 세션을 읽은 직후(읽기에 성공했을 때만) 부르는 조립용 훅. 구 데이터 흡수처럼 복원된 상태 위에 더해야 하는 일을 맡긴다.
    var afterSessionRestored: (@MainActor (ProjectSession) -> Void)?

    let renderScheduler: RenderScheduler
    private var selectionTask: Task<Void, Never>?
    var exportTask: Task<Void, Never>?

    init(
        session: ProjectSession, pipeline: PhotoPipeline, copies: WorkingCopyStore, importer: any PhotoImporter,
        exporter: Exporter, renderDebounce: Duration = Policy.renderDebounce
    ) {
        self.session = session
        self.pipeline = pipeline
        self.copies = copies
        self.importer = importer
        self.exporter = exporter
        renderScheduler = RenderScheduler(debounce: renderDebounce)
    }

    var isBusy: Bool { isImporting || isExporting || isRestoring }
    var currentRecipe: EditRecipe { session.selected?.document.recipe ?? EditRecipe() }
    var canUndo: Bool { session.selected?.document.canUndo ?? false }
    var canRedo: Bool { session.selected?.document.canRedo ?? false }
    var isGeometryLocked: Bool { session.selected?.document.isGeometryLocked ?? false }
    var displayImage: CGImage? { isComparing ? original : (preview ?? original) }
    var selectedInfo: PhotoInfo? { session.selectedPhotoID.flatMap { photoInfo[$0] } }
    var faces: [FaceGeometry] { selectedInfo?.faces ?? [] }

    func present(_ error: Error) {
        presentedError = PresentedError(message: UserMessage.text(for: error))
    }

    func present(message: String) {
        presentedError = PresentedError(message: message)
    }

    /// 앱 시작. 세션을 읽고 모든 사진의 썸네일·얼굴을 다시 준비한다.
    func restore() async {
        guard !hasRestored else { return }
        hasRestored = true
        isRestoring = true
        defer { isRestoring = false }
        do {
            try session.restore()
            afterSessionRestored?(session)
        } catch {
            present(error)
        }
        for entry in session.photos {
            do {
                let prepared = try await pipeline.prepare(entry.id, at: copies.url(for: entry.filename))
                remember(entry.id, prepared)
            } catch {
                present(message: UserMessage.somePhotosUnreadable)
            }
        }
        if !session.photos.isEmpty {
            statusMessage = UserMessage.photosStatus(count: session.photos.count)
        }
        if let id = session.selectedPhotoID {
            select(id)
        }
    }

    func remember(_ id: PhotoID, _ prepared: PreparedPhoto) {
        thumbnails[id] = prepared.thumbnail
        photoInfo[id] = PhotoInfo(
            pixelSize: prepared.pixelSize, faces: prepared.faces, faceAnalysisFailure: prepared.faceAnalysisFailure)
    }

    func select(_ id: PhotoID) {
        guard !isExporting, session.index(of: id) != nil else { return }
        selectionTask?.cancel()
        renderScheduler.cancel()
        endContinuousChangeOnSelected()
        session.selectedPhotoID = id
        preview = nil
        original = nil
        isReady = false
        isRendering = false
        selectionFailure = nil
        isComparing = false
        cloneSource = nil
        isChoosingCloneSource = true
        guard let entry = session.selected else { return }
        selectionTask = Task {
            do {
                try await pipeline.reprepareIfEvicted(id, at: copies.url(for: entry.filename))
                let base = try await pipeline.preview(id, recipe: EditRecipe())
                guard !Task.isCancelled, session.selectedPhotoID == id else { return }
                original = base
                isReady = true
                scheduleRender()
            } catch {
                guard !Task.isCancelled, session.selectedPhotoID == id else { return }
                selectionFailure = UserMessage.selectionUnreadable
                present(error)
            }
        }
    }

    /// 드래그가 끝나지 않은 채 사진을 바꾸면 이전 사진의 연속 변경과 미룬 저장을 마무리한다.
    private func endContinuousChangeOnSelected() {
        if let previous = session.selectedPhotoID {
            session.edit(previous) { document in
                document.endContinuousChange()
                return nil
            }
        }
        if session.isPersistenceDeferred {
            session.endDeferredPersistence()
        }
    }

    func scheduleRender() {
        guard let entry = session.selected, isReady else { return }
        isRendering = true
        let pipeline = self.pipeline
        let recipe = entry.document.recipe
        let id = entry.id
        let url = copies.url(for: entry.filename)
        renderScheduler.schedule {
            // 다른 사진을 가져오는 동안 미리보기 캐시에서 밀려났을 수 있다.
            try await pipeline.reprepareIfEvicted(id, at: url)
            return try await pipeline.preview(id, recipe: recipe)
        } completion: { [weak self] result in
            guard let self, session.selectedPhotoID == id else { return }
            isRendering = false
            switch result {
            case .success(let image): preview = image
            case .failure(let error): present(error)
            }
        }
    }

    /// 취소된 렌더는 완료 콜백을 부르지 않으므로 진행 표시를 여기서 내린다.
    func cancelSelectionWork() {
        selectionTask?.cancel()
        renderScheduler.cancel()
        isRendering = false
    }

    func stopWork() {
        cancelSelectionWork()
        exportTask?.cancel()
    }

    /// 앱이 다시 활성화되면 멈췄던 미리보기를 현재 레시피로 다시 그린다.
    func resumeWork() {
        guard isReady, session.selected != nil else { return }
        scheduleRender()
    }
}
