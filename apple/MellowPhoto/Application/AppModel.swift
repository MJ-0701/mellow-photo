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
        /// 인물 마스크가 있는지. 배경 도구 안내에 쓴다.
        var hasPerson = false
        /// 인물 분석이 실패했으면 그 이유. 사람이 없는 것과 구분한다.
        var personAnalysisFailure: MellowError?
    }

    /// 배경 도구가 보여줄 상태. 분석 실패가 사람 없음보다 먼저다.
    enum BackgroundAvailability: Equatable {
        case ready
        case noPerson
        case unavailable(MellowError)
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
        /// 앱 번들에 든 룩 카탈로그 파일. shared/looks/looks.v1.json과 같은 내용이다.
        static let bundledLookCatalogName = "looks.v1"
        static let bundledLookCatalogExtension = "json"
    }

    let session: ProjectSession
    let pipeline: PhotoPipeline
    let copies: WorkingCopyStore
    let importer: any PhotoImporter
    let exporter: Exporter
    let lookCatalog: LookCatalog

    var thumbnails: [PhotoID: CGImage] = [:]
    /// 사진별 룩 썸네일. 키가 사진 id라서 늦게 온 결과가 다른 사진에 붙지 않는다.
    var lookThumbnails: [PhotoID: [String: CGImage]] = [:]
    /// 만드는 중인 룩 썸네일. 같은 사진을 두 번 요청하지 않는다.
    var lookThumbnailRequests: Set<PhotoID> = []
    var cropAspect: CropAspect?
    /// 자르기 손잡이를 끄는 중. 자르기 화면은 자르기 전 이미지라 드래그 중에는 다시 그리지 않는다.
    var isCropDragging = false
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

    var tool: EditorTool = .look
    /// 뷰티 도구에서 마지막으로 본 탭. 도구를 바꿔도 유지한다.
    var beautyTab: BeautyTab = .skin
    var brushRadius = Policy.defaultBrushRadius
    var cloneSource: NormalizedPoint?
    var isChoosingCloneSource = true
    var isComparing = false
    var exportOptions = ExportOptions()
    /// 이름 입력 시트가 떠 있는 동안 true. 메뉴의 ⌘Z/⇧⌘Z가 입력란의 실행 취소를 가로채지 않게 한다.
    var isTextEntryActive = false
    /// 마지막 저장 작업에서 실제로 저장된 장수. Mac 폴더 저장 뒤 Finder를 열지 판단한다.
    var lastExportSavedCount = 0

    /// 세션을 읽은 직후(읽기에 성공했을 때만) 부르는 조립용 훅. 구 데이터 흡수처럼 복원된 상태 위에 더해야 하는 일을 맡긴다.
    var afterSessionRestored: (@MainActor (ProjectSession) -> Void)?

    let renderScheduler: RenderScheduler
    private var selectionTask: Task<Void, Never>?
    var exportTask: Task<Void, Never>?
    /// 비교 화면의 원본에 마지막으로 입힌 기하. 같으면 원본을 다시 그리지 않는다.
    private var originalGeometry: GeometryAdjustments?

    init(
        session: ProjectSession, pipeline: PhotoPipeline, copies: WorkingCopyStore, importer: any PhotoImporter,
        exporter: Exporter, lookCatalog: LookCatalog = .empty, renderDebounce: Duration = Policy.renderDebounce
    ) {
        self.session = session
        self.pipeline = pipeline
        self.copies = copies
        self.importer = importer
        self.exporter = exporter
        self.lookCatalog = lookCatalog
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
    /// 선택 사진의 배경 도구 상태.
    var backgroundAvailability: BackgroundAvailability {
        if let failure = selectedInfo?.personAnalysisFailure {
            return .unavailable(failure)
        }
        return selectedInfo?.hasPerson == true ? .ready : .noPerson
    }
    /// 자르기 도구에서는 자르기 전 이미지를 보여준다.
    var canvasShowsUncropped: Bool { tool == .crop }

    /// 캔버스(출력) 좌표와 원본 좌표 사이의 변환. 자르기 도구에서는 자르기만 뺀 기하를 쓴다.
    var outputTransform: GeometryTransform? {
        guard let size = selectedInfo?.pixelSize, size.height > 0 else { return nil }
        var geometry = currentRecipe.geometry
        if canvasShowsUncropped {
            geometry.crop = nil
        }
        return GeometryTransform(geometry: geometry, sourceAspect: size.width / size.height)
    }

    /// 복제 샘플 마커를 그릴 캔버스 좌표. 자른 영역 밖이면 nil.
    var cloneSourceOnCanvas: NormalizedPoint? {
        guard let source = cloneSource else { return nil }
        guard let transform = outputTransform else { return source }
        return transform.toOutput(source)
    }

    /// 도구를 바꾼다. 자르기 화면을 드나들면 미리보기를 다시 그리고, 필터 도구는 썸네일을 준비한다.
    func selectTool(_ newTool: EditorTool) {
        let showedUncropped = canvasShowsUncropped
        tool = newTool
        if canvasShowsUncropped != showedUncropped {
            scheduleRender()
        }
        if newTool == .look {
            loadLookThumbnails()
        }
    }

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
            pixelSize: prepared.pixelSize, faces: prepared.faces, faceAnalysisFailure: prepared.faceAnalysisFailure,
            hasPerson: prepared.hasPerson, personAnalysisFailure: prepared.personAnalysisFailure)
    }

    func select(_ id: PhotoID) {
        guard !isExporting, session.index(of: id) != nil else { return }
        selectionTask?.cancel()
        renderScheduler.cancel()
        endContinuousChangeOnSelected()
        // 고른 비율은 화면 상태라 다른 사진으로 넘어가지 않는다.
        if session.selectedPhotoID != id {
            cropAspect = nil
        }
        session.selectedPhotoID = id
        preview = nil
        original = nil
        isReady = false
        isRendering = false
        selectionFailure = nil
        isComparing = false
        cloneSource = nil
        isChoosingCloneSource = true
        originalGeometry = nil
        guard let entry = session.selected else { return }
        selectionTask = Task {
            do {
                try await pipeline.reprepareIfEvicted(id, at: copies.url(for: entry.filename))
                let baseRecipe = EditRecipe()
                let base = try await pipeline.preview(id, recipe: baseRecipe)
                guard !Task.isCancelled, session.selectedPhotoID == id else { return }
                original = base
                originalGeometry = baseRecipe.geometry
                isReady = true
                scheduleRender()
                if tool == .look {
                    loadLookThumbnails()
                }
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
            session.endContinuousChange(previous)
        }
        if session.isPersistenceDeferred {
            session.endDeferredPersistence()
        }
    }

    /// 백그라운드 진입처럼 드래그 종료 이벤트가 오지 않을 수 있는 시점에 열린 작업을 저장한다.
    func flushPendingEdits() {
        endContinuousChangeOnSelected()
        if let error = session.lastPersistenceError {
            present(error)
        }
    }

    func scheduleRender() {
        guard let entry = session.selected, isReady else { return }
        isRendering = true
        let pipeline = self.pipeline
        let recipe = entry.document.recipe
        let id = entry.id
        let url = copies.url(for: entry.filename)
        let showsUncropped = canvasShowsUncropped
        var shownGeometry = recipe.geometry
        if showsUncropped {
            shownGeometry.crop = nil
        }
        renderScheduler.schedule {
            // 다른 사진을 가져오는 동안 미리보기 캐시에서 밀려났을 수 있다.
            try await pipeline.reprepareIfEvicted(id, at: url)
            return try await pipeline.preview(id, recipe: recipe, showsUncropped: showsUncropped)
        } completion: { [weak self] result in
            guard let self, session.selectedPhotoID == id else { return }
            isRendering = false
            switch result {
            case .success(let image):
                preview = image
                refreshOriginalIfNeeded(id: id, geometry: shownGeometry)
            case .failure(let error): present(error)
            }
        }
    }

    /// 비교 화면의 원본은 미리보기와 같은 기하(자르기·회전)로 보여야 한다.
    private func refreshOriginalIfNeeded(id: PhotoID, geometry: GeometryAdjustments) {
        guard originalGeometry != geometry else { return }
        originalGeometry = geometry
        let recipe = EditRecipe(geometry: geometry)
        let pipeline = self.pipeline
        Task { [weak self] in
            let image = try? await pipeline.preview(id, recipe: recipe)
            guard let self, session.selectedPhotoID == id, originalGeometry == geometry else { return }
            // 실패하면 다음 렌더가 다시 시도하도록 기록을 지운다. 그동안은 이전 원본을 보여준다.
            guard let image else {
                originalGeometry = nil
                return
            }
            original = image
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
