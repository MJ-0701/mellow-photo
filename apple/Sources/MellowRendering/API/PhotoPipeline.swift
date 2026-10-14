import CoreImage
import Foundation
import MellowShared

public struct PreparedPhoto: Sendable {
    public let pixelSize: CGSize
    public let thumbnail: CGImage
    public let faces: [FaceGeometry]
    /// 분석이 실패했으면 그 이유. 얼굴이 없는 것과 구분한다.
    public let faceAnalysisFailure: MellowError?
}

/// 무거운 이미지 작업을 메인 액터 밖에서 직렬로 수행한다. 미리보기는 캐시에서 렌더한다.
public actor PhotoPipeline {
    private struct Entry {
        var faces: [FaceGeometry]
        var faceAnalysisFailure: MellowError?
    }

    private let loader = ImageLoader()
    private let renderer = Renderer()
    private let pipeline = RenderPipeline.standard
    private let analyzer: any FaceAnalyzer
    private let tuning: RenderTuning
    private var entries: [PhotoID: Entry] = [:]
    private var cache: PreviewCache

    public init(analyzer: any FaceAnalyzer, tuning: RenderTuning) {
        self.analyzer = analyzer
        self.tuning = tuning
        cache = PreviewCache(capacity: tuning.previewCacheCapacity)
    }

    /// 테스트용. 캐시에 든 사진 ID.
    var cachedPreviewIDs: [PhotoID] { cache.ids }

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
        entries[id] = Entry(faces: faces, faceAnalysisFailure: failure)
        cache.insert(preview, for: id)
        let thumbnail = try renderer.makeCGImage(Self.scaled(preview, maxDimension: tuning.thumbnailMaxDimension))
        return PreparedPhoto(
            pixelSize: metadata.pixelSize, thumbnail: thumbnail, faces: faces, faceAnalysisFailure: failure)
    }

    /// 캐시가 비었으면 cannotCreatePreview. 호출자가 prepare를 다시 한다.
    public func preview(_ id: PhotoID, recipe: EditRecipe) throws -> CGImage {
        guard let entry = entries[id], let image = cache.image(for: id) else {
            throw MellowError.cannotCreatePreview
        }
        let context = RenderContext(extent: image.extent, recipe: recipe, faces: entry.faces, tuning: tuning)
        return try renderer.makeCGImage(pipeline.render(image, context: context))
    }

    public func reprepareIfEvicted(_ id: PhotoID, at url: URL) throws {
        guard cache.image(for: id) == nil else { return }
        _ = try prepare(id, at: url)
    }

    /// 준비 때 얻은 정규화 얼굴 좌표를 원본 해상도에 그대로 쓴다. 얼굴을 다시 분석하지 않는다.
    public func renderOriginal(_ id: PhotoID, at url: URL, recipe: EditRecipe, maxDimension: Int?) throws -> CIImage {
        let entry = entries[id] ?? Entry(faces: [], faceAnalysisFailure: nil)
        if recipe.dependsOnFaces, entry.faces.isEmpty, let failure = entry.faceAnalysisFailure {
            throw failure
        }
        let image = try loader.load(url: url, maxDimension: maxDimension)
        let context = RenderContext(extent: image.extent, recipe: recipe, faces: entry.faces, tuning: tuning)
        return try pipeline.render(image, context: context)
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
