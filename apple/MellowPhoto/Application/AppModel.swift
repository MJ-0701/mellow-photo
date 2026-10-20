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
        /// 가장 큰 사람의 두 어깨가 보이는지. 체형 도구 안내에 쓴다.
        var hasBody = false
        /// 체형 분석이 실패했으면 그 이유. 사람이 없는 것과 구분한다.
        var bodyAnalysisFailure: MellowError?
    }

    /// 배경 도구가 보여줄 상태. 분석 실패가 사람 없음보다 먼저다.
    enum BackgroundAvailability: Equatable {
        case ready
        case noPerson
        case unavailable(MellowError)
    }

    /// 체형 도구가 보여줄 상태. 분석 실패가 전신 없음보다 먼저다.
    enum BodyAvailability: Equatable {
        case ready
        case noBody
        case unavailable(MellowError)
    }

    /// 피부톤 탭이 보여줄 몸 피부 조건.
    /// 얼굴 분석 실패 → 얼굴 없음 → 인물 분석 실패 → 대체 → 준비 순서로 판정한다.
    enum BodySkinStatus: Equatable {
        case ready
        /// 사람 영역이 없어 얼굴 둘레 대체 영역을 쓴다.
        case fallback
        case noFace
        case faceAnalysisUnavailable(MellowError)
        case personAnalysisUnavailable(MellowError)
    }

    /// 뷰티·메이크업 도구가 보여줄 얼굴 상태. 분석 실패가 얼굴 없음보다 먼저다.
    enum FaceAvailability: Equatable {
        case ready
        /// 대상 얼굴에 특징점이 하나도 없다. 피부 보정·얼룩 고르기·붉은기·번들거림만 동작하고 주름 밝히기 4종은 빠진다.
        case noLandmarks
        case noFace
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
        /// 앱 번들에 든 메이크업 카탈로그 파일. shared/makeup/makeup.v1.json과 같은 내용이다.
        static let bundledMakeupCatalogName = "makeup.v1"
        static let bundledMakeupCatalogExtension = "json"
        /// 분할 비교의 처음 분할선 위치와 범위(원본이 보이는 왼쪽 폭 비율).
        static let compareSplitDefault = 0.5
        static let compareSplitRange = 0.0...1.0
        /// 보조 기술로 분할선을 한 번 옮기는 폭.
        static let compareSplitAccessibilityStep = 0.1
    }

    /// 전후 비교 모드. full은 기존 전체 토글, split은 분할선.
    enum CompareMode: Equatable {
        case off, full, split
    }

    let session: ProjectSession
    let pipeline: PhotoPipeline
    let copies: WorkingCopyStore
    let importer: any PhotoImporter
    let exporter: Exporter
    let lookCatalog: LookCatalog
    let makeupCatalog: MakeupCatalog

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
    /// 마지막 미리보기 렌더 실패 문구.
    /// 알림(presentedError)과 달리 닫아도 남아 진단 절에 보인다.
    /// 렌더가 성공하거나 선택 사진이 바뀌면 지운다(다른 사진의 오류를 보이지 않는다).
    var lastRenderFailure: String?

    var tool: EditorTool = .look
    /// 뷰티 도구에서 마지막으로 본 탭. 도구를 바꿔도 유지한다.
    var beautyTab: BeautyTab = .skin
    /// 메이크업 도구에서 마지막으로 본 부위. 도구를 바꿔도 유지한다.
    var makeupPart: MakeupPart = .lip
    var brushRadius = Policy.defaultBrushRadius
    var cloneSource: NormalizedPoint?
    var isChoosingCloneSource = true
    var compareMode: CompareMode = .off
    /// 원본이 보이는 왼쪽 폭 비율. 분할을 끄고 켜도 유지한다.
    var compareSplit = Policy.compareSplitDefault
    /// 기존 전체 토글. 분할 중에 true로 두면 전체로 바뀐다.
    var isComparing: Bool {
        get { compareMode == .full }
        set { compareMode = newValue ? .full : .off }
    }
    /// 비교 중에는 캔버스 탭·브러시·자르기 틀을 막는다(두 모드 모두).
    var blocksCanvasTouch: Bool { compareMode != .off }
    /// 분할 모드에서 보정본 위에 겹칠 원본. 들고 있는 원본의 기하가 보이는 미리보기의 기하와 같을 때만 겹친다.
    /// 기하를 바꾼 뒤 원본을 다시 그리는 중이거나 다시 그리지 못했으면 nil이다(뒤집기처럼 비율이 같아도).
    var splitCompareOriginal: CGImage? {
        guard compareMode == .split, let original, let heldOriginalGeometry else { return nil }
        return heldOriginalGeometry == previewGeometry ? original : nil
    }
    /// 전체 사진에 적용이 복사할 항목. 세션 상태라 파일에 저장하지 않고 실행할 때마다 전부로 시작한다.
    var syncCategories: Set<SyncCategory> = SyncCategory.all
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
    /// 비교 화면의 원본에 마지막으로 입힌 기하. 같으면 원본을 다시 그리지 않는다. 요청할 때 기록하므로 그리는 중에도 바뀌어 있다.
    private var originalGeometry: GeometryAdjustments?
    /// 지금 들고 있는 원본(original)을 그린 기하. 원본을 받을 때만 바뀐다.
    private var heldOriginalGeometry: GeometryAdjustments?
    /// 지금 들고 있는 미리보기(preview)를 그린 기하. 자르기 화면이면 자르기를 뺀 기하다.
    private var previewGeometry: GeometryAdjustments?
    /// 기하를 바꾼 뒤 비교 화면의 원본을 다시 그린다. 테스트가 늦추거나 실패시키려고 바꿔 끼운다.
    var renderOriginal: @MainActor (PhotoID, EditRecipe) async throws -> CGImage

    init(
        session: ProjectSession, pipeline: PhotoPipeline, copies: WorkingCopyStore, importer: any PhotoImporter,
        exporter: Exporter, lookCatalog: LookCatalog = .empty, makeupCatalog: MakeupCatalog = .empty,
        renderDebounce: Duration = Policy.renderDebounce
    ) {
        self.session = session
        self.pipeline = pipeline
        self.copies = copies
        self.importer = importer
        self.exporter = exporter
        self.lookCatalog = lookCatalog
        self.makeupCatalog = makeupCatalog
        renderScheduler = RenderScheduler(debounce: renderDebounce)
        renderOriginal = { id, recipe in try await pipeline.preview(id, recipe: recipe) }
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
    /// 선택 사진의 체형 도구 상태.
    var bodyAvailability: BodyAvailability {
        if let failure = selectedInfo?.bodyAnalysisFailure {
            return .unavailable(failure)
        }
        return selectedInfo?.hasBody == true ? .ready : .noBody
    }
    /// 선택 사진의 뷰티·메이크업 얼굴 상태. 대상 얼굴(모든 얼굴이면 전부)에 특징점이 없으면 noLandmarks다.
    var faceAvailability: FaceAvailability {
        if let failure = selectedInfo?.faceAnalysisFailure {
            return .unavailable(failure)
        }
        guard !faces.isEmpty else { return .noFace }
        let targets =
            currentRecipe.portrait.targetFace.map { index in faces.indices.contains(index) ? [faces[index]] : [] }
            ?? faces
        let lacksLandmarks = !targets.isEmpty && targets.allSatisfy { $0.landmarks.isEmpty }
        return lacksLandmarks ? .noLandmarks : .ready
    }
    /// 슬라이더 드래그가 열려 있는지. 드래그 중에 슬라이더를 끄면 끝 이벤트가 오지 않아 연속 변경과 미룬 저장이 남는다.
    var isSliderEditActive: Bool { session.isPersistenceDeferred }
    /// 배경 흐림 슬라이더를 움직일 수 있는지. 사람이 없어도 프리셋으로 들어온 값은 0으로 되돌릴 수 있게 켠다.
    /// 드래그 중에는 0에 닿아도 끄지 않는다.
    var canAdjustBackgroundBlur: Bool {
        isSliderEditActive || backgroundAvailability == .ready || currentRecipe.background.blur != 0
    }
    /// 선택 사진의 몸 피부 조건.
    /// 피부톤 탭 맨 위 상태 줄이 보인다.
    var bodySkinStatus: BodySkinStatus {
        if let failure = selectedInfo?.faceAnalysisFailure {
            return .faceAnalysisUnavailable(failure)
        }
        guard !faces.isEmpty else { return .noFace }
        if let failure = selectedInfo?.personAnalysisFailure {
            return .personAnalysisUnavailable(failure)
        }
        return selectedInfo?.hasPerson == true ? .ready : .fallback
    }
    /// 피부톤 슬라이더를 움직일 수 있는지.
    /// 사람 영역이 있거나 얼굴 둘레 대체 영역을 쓸 때 켠다.
    /// 인물 분석이 실패해도 얼굴이 있으면 렌더가 대체 영역을 쓰므로 켠다.
    /// 드래그 중이거나 0이 아닌 값(프리셋)도 되돌릴 수 있게 켠다.
    func canAdjustBodySkin(_ key: BodySkinKey) -> Bool {
        let active: Bool
        switch bodySkinStatus {
        case .ready, .fallback, .personAnalysisUnavailable: active = true
        case .noFace, .faceAnalysisUnavailable: active = false
        }
        return isSliderEditActive || active || currentRecipe.bodySkin[key] != 0
    }
    /// 체형 슬라이더를 움직일 수 있는지. 잠금이 먼저이고, 관절이 없어도 0이 아닌 값은 되돌릴 수 있게 켠다.
    /// 드래그 중에는 0을 지나도 끄지 않는다.
    func canAdjustBodyShape(_ key: BodyShapeKey) -> Bool {
        !isGeometryLocked && (isSliderEditActive || bodyAvailability == .ready || currentRecipe.body[key] != 0)
    }
    /// 메이크업 룩·색·강도를 바꿀 수 있는지. 얼굴 분석이 실패한 사진에 메이크업을 넣으면 저장이 실패하므로 끈다.
    /// 이미 들어온 메이크업은 줄이거나 지울 수 있게 켜고, 드래그 중에는 0에 닿아도 끄지 않는다. 얼굴이 없을 뿐이면 저장은 되므로 켠다.
    var canAdjustMakeup: Bool {
        guard case .unavailable = faceAvailability else { return true }
        return isSliderEditActive || currentRecipe.makeup.hasEffect
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

    /// 도구를 바꾼다. 열린 드래그는 먼저 끝낸다. 자르기 화면을 드나들면 미리보기를 다시 그리고, 필터 도구는 썸네일을 준비한다.
    func selectTool(_ newTool: EditorTool) {
        endSliderEditIfActive()
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
            hasPerson: prepared.hasPerson, personAnalysisFailure: prepared.personAnalysisFailure,
            hasBody: prepared.hasBody, bodyAnalysisFailure: prepared.bodyAnalysisFailure)
    }

    /// 미리보기 캐시에서 밀려난 사진을 다시 준비한다. 다시 준비하면 분석도 새로 하므로 사진 정보를 함께 바꾼다.
    /// 기다리는 동안 사진을 뺐으면 결과를 버린다.
    func reprepareIfEvicted(_ id: PhotoID, at url: URL) async throws {
        guard let prepared = try await pipeline.reprepareIfEvicted(id, at: url) else { return }
        guard session.index(of: id) != nil else { return }
        remember(id, prepared)
    }

    func toggleSplitCompare() {
        compareMode = compareMode == .split ? .off : .split
    }

    func setCompareSplit(_ fraction: Double) {
        compareSplit = min(Policy.compareSplitRange.upperBound, max(Policy.compareSplitRange.lowerBound, fraction))
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
        lastRenderFailure = nil
        preview = nil
        original = nil
        isReady = false
        isRendering = false
        selectionFailure = nil
        compareMode = .off
        cloneSource = nil
        isChoosingCloneSource = true
        originalGeometry = nil
        heldOriginalGeometry = nil
        previewGeometry = nil
        guard let entry = session.selected else { return }
        selectionTask = Task {
            do {
                try await reprepareIfEvicted(id, at: copies.url(for: entry.filename))
                let baseRecipe = EditRecipe()
                let base = try await pipeline.preview(id, recipe: baseRecipe)
                guard !Task.isCancelled, session.selectedPhotoID == id else { return }
                original = base
                originalGeometry = baseRecipe.geometry
                heldOriginalGeometry = baseRecipe.geometry
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
        renderScheduler.schedule { [weak self] in
            // 다른 사진을 가져오는 동안 미리보기 캐시에서 밀려났을 수 있다.
            try await self?.reprepareIfEvicted(id, at: url)
            return try await pipeline.preview(id, recipe: recipe, showsUncropped: showsUncropped)
        } completion: { [weak self] result in
            guard let self, session.selectedPhotoID == id else { return }
            isRendering = false
            switch result {
            case .success(let image):
                preview = image
                previewGeometry = shownGeometry
                lastRenderFailure = nil
                refreshOriginalIfNeeded(id: id, geometry: shownGeometry)
            case .failure(let error):
                lastRenderFailure = UserMessage.text(for: error)
                present(error)
            }
        }
    }

    /// 비교 화면의 원본은 미리보기와 같은 기하(자르기·회전)로 보여야 한다.
    private func refreshOriginalIfNeeded(id: PhotoID, geometry: GeometryAdjustments) {
        guard originalGeometry != geometry else { return }
        originalGeometry = geometry
        let recipe = EditRecipe(geometry: geometry)
        let render = renderOriginal
        Task { [weak self] in
            let image = try? await render(id, recipe)
            guard let self, session.selectedPhotoID == id, originalGeometry == geometry else { return }
            // 실패하면 다음 렌더가 다시 시도하도록 기록을 지운다. 이전 원본은 기하가 달라 분할 비교에 겹치지 않는다.
            guard let image else {
                originalGeometry = nil
                return
            }
            original = image
            heldOriginalGeometry = geometry
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
