import CoreImage
import Foundation
import MellowShared

public struct PreparedPhoto: Sendable {
    public let pixelSize: CGSize
    public let thumbnail: CGImage
    public let faces: [FaceGeometry]
    /// 분석이 실패했으면 그 이유. 얼굴이 없는 것과 구분한다.
    public let faceAnalysisFailure: MellowError?

    public init(pixelSize: CGSize, thumbnail: CGImage, faces: [FaceGeometry], faceAnalysisFailure: MellowError?) {
        self.pixelSize = pixelSize
        self.thumbnail = thumbnail
        self.faces = faces
        self.faceAnalysisFailure = faceAnalysisFailure
    }
}

/// 무거운 이미지 작업을 메인 액터 밖에서 직렬로 수행한다. 미리보기는 캐시에서 렌더한다.
public actor PhotoPipeline {
    /// 준비 전 사진에 얼굴 보정을 저장하려 할 때의 사유 식별자. 사용자 문구는 앱이 정한다.
    public static let unpreparedReason = "photo-not-prepared"

    private struct Entry {
        /// 준비 때 계산한 분석 결과. 다각형 마스크 캐시도 함께 들고 있다.
        var analysis: PhotoAnalysis
        /// 렌더해 둔 작은 비트맵에서 만든다. 미리보기 CIImage를 참조하지 않아 LRU로 밀려난 미리보기를 붙잡지 않는다.
        var thumbnail: CIImage
    }

    private let loader = ImageLoader()
    private let renderer = Renderer()
    private let pipeline = RenderPipeline.standard
    private let analyzer: any FaceAnalyzer
    private let tuning: RenderTuning
    private let lookCatalog: LookCatalog
    /// 미리보기 이미지가 LRU로 밀려나도 일부러 남긴다. renderOriginal이 얼굴 좌표를 써야 한다.
    private var entries: [PhotoID: Entry] = [:]
    private var cache: PreviewCache

    public init(analyzer: any FaceAnalyzer, tuning: RenderTuning, lookCatalog: LookCatalog = .empty) {
        self.analyzer = analyzer
        self.tuning = tuning
        self.lookCatalog = lookCatalog
        cache = PreviewCache(capacity: tuning.previewCacheCapacity)
    }

    /// 테스트용. 캐시에 든 사진 ID.
    var cachedPreviewIDs: [PhotoID] { cache.ids }

    /// 테스트용. 준비 때 찾은 잡티.
    func preparedBlemishes(_ id: PhotoID) -> [BlemishSpot] {
        entries[id]?.analysis.blemishes ?? []
    }

    /// 테스트용. 준비 때 계산한 분석 묶음.
    func preparedAnalysis(_ id: PhotoID) -> PhotoAnalysis? {
        entries[id]?.analysis
    }

    public func prepare(_ id: PhotoID, at url: URL) throws -> PreparedPhoto {
        let metadata = try loader.metadata(url: url)
        let preview = try loader.load(url: url, maxDimension: tuning.previewMaxDimension)
        var faces: [FaceGeometry] = []
        var failure: MellowError?
        do {
            faces = try analyzer.analyze(preview)
        } catch let error as MellowError {
            failure = error
        } catch {
            failure = .faceAnalysisUnavailable(reason: error.localizedDescription)
        }
        let analysis = PhotoAnalysis(
            faces: faces, faceAnalysisFailure: failure, blemishes: detectBlemishes(in: preview, faces: faces))
        let thumbnail = try renderer.makeCGImage(Self.scaled(preview, maxDimension: tuning.thumbnailMaxDimension))
        entries[id] = Entry(analysis: analysis, thumbnail: CIImage(cgImage: thumbnail))
        cache.insert(preview, for: id)
        releaseMasksOfEvictedPreviews()
        return PreparedPhoto(
            pixelSize: metadata.pixelSize, thumbnail: thumbnail, faces: faces, faceAnalysisFailure: failure)
    }

    /// 캐시가 비었으면 cannotCreatePreview. 호출자가 prepare를 다시 한다.
    /// `showsUncropped`이면 자르기만 건너뛴다. 자르기 도구 화면이 전체 이미지 위에 자르기 틀을 그린다.
    public func preview(_ id: PhotoID, recipe: EditRecipe, showsUncropped: Bool = false) throws -> CGImage {
        guard let entry = entries[id], let image = cache.image(for: id) else {
            throw MellowError.cannotCreatePreview
        }
        let context = RenderContext(
            extent: image.extent, recipe: recipe, analysis: entry.analysis, tuning: tuning, lookCatalog: lookCatalog,
            skipsCrop: showsUncropped)
        return try renderer.makeCGImage(pipeline.render(image, context: context))
    }

    /// 카탈로그의 모든 룩을 강도 1로 입힌 썸네일. 룩 단계만 적용한다(전체 파이프라인이 아님).
    public func lookThumbnails(_ id: PhotoID) throws -> [String: CGImage] {
        guard let entry = entries[id] else { throw MellowError.cannotCreatePreview }
        var result: [String: CGImage] = [:]
        for look in lookCatalog.all {
            let styled = LookStage.styled(entry.thumbnail, look: look, tuning: tuning)
            result[look.id] = try renderer.makeCGImage(styled.cropped(to: entry.thumbnail.extent))
        }
        return result
    }

    /// 원본 분석 기준의 제안. 현재 레시피와 무관하다.
    public func autoEnhanceSuggestion(_ id: PhotoID, hasFaces: Bool) throws -> AutoEnhanceSuggestion {
        guard let image = cache.image(for: id) else { throw MellowError.cannotCreatePreview }
        return try AutoEnhancer(tuning: tuning, renderer: renderer).suggestion(for: image, hasFaces: hasFaces)
    }

    public func reprepareIfEvicted(_ id: PhotoID, at url: URL) throws {
        guard cache.image(for: id) == nil else { return }
        _ = try prepare(id, at: url)
    }

    /// 준비 때 얻은 정규화 얼굴 좌표를 원본 해상도에 그대로 쓴다. 얼굴을 다시 분석하지 않는다.
    public func renderOriginal(_ id: PhotoID, at url: URL, recipe: EditRecipe, maxDimension: Int?) throws -> CIImage {
        guard let entry = entries[id] else {
            // 얼굴 정보 없이 얼굴 보정을 저장하면 조용히 빠진다. 색감만이면 그대로 렌더한다.
            if recipe.dependsOnFaces {
                throw MellowError.faceAnalysisUnavailable(reason: Self.unpreparedReason)
            }
            return try render(url: url, recipe: recipe, analysis: PhotoAnalysis(), maxDimension: maxDimension)
        }
        if recipe.dependsOnFaces, entry.analysis.faces.isEmpty, let failure = entry.analysis.faceAnalysisFailure {
            throw failure
        }
        let rendered = try render(url: url, recipe: recipe, analysis: entry.analysis, maxDimension: maxDimension)
        // 원본 해상도 마스크는 다시 쓸 일이 드물다. 이미 만든 렌더 그래프는 비트맵을 붙잡고 있어 비워도 안전하다.
        releaseMasksOfEvictedPreviews()
        return rendered
    }

    private func render(url: URL, recipe: EditRecipe, analysis: PhotoAnalysis, maxDimension: Int?) throws -> CIImage {
        let image = try loader.load(url: url, maxDimension: maxDimension)
        let context = RenderContext(
            extent: image.extent, recipe: recipe, analysis: analysis, tuning: tuning, lookCatalog: lookCatalog)
        return try pipeline.render(image, context: context)
    }

    /// 잡티 분석이 실패해도 사진 준비는 막지 않는다. 자동 잡티만 동작하지 않는다.
    private func detectBlemishes(in image: CIImage, faces: [FaceGeometry]) -> [BlemishSpot] {
        guard !faces.isEmpty else { return [] }
        return (try? BlemishDetector(tuning: tuning, renderer: renderer).detect(image: image, faces: faces)) ?? []
    }

    /// 미리보기 캐시에 없는 사진의 마스크 비트맵을 놓는다. 메모리를 최근 사진 몇 장 몫으로 묶는다.
    private func releaseMasksOfEvictedPreviews() {
        let cached = Set(cache.ids)
        for (id, entry) in entries where !cached.contains(id) {
            entry.analysis.regionMasks.removeAll()
        }
    }

    public func makeCGImage(_ image: CIImage) throws -> CGImage {
        try renderer.makeCGImage(image)
    }

    public func evict(_ id: PhotoID) {
        entries[id] = nil
        cache.remove(id)
    }

    private static func scaled(_ image: CIImage, maxDimension: Int) -> CIImage {
        let longest = max(image.extent.width, image.extent.height)
        guard longest > CGFloat(maxDimension) else { return image }
        let scale = CGFloat(maxDimension) / longest
        return image.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
    }
}
