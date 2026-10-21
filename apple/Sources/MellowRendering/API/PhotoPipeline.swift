import CoreImage
import Foundation
import MellowShared

public struct PreparedPhoto: Sendable {
    public let pixelSize: CGSize
    public let thumbnail: CGImage
    public let faces: [FaceGeometry]
    /// 분석이 실패했으면 그 이유. 얼굴이 없는 것과 구분한다.
    public let faceAnalysisFailure: MellowError?
    /// 인물 마스크가 있으면 true. 배경 도구의 "사람 없음" 안내에 쓴다.
    public let hasPerson: Bool
    /// 인물 분석이 실패했으면 그 이유. 사람이 없는 것과 구분한다.
    public let personAnalysisFailure: MellowError?
    /// 쓸 수 있는 몸(두 어깨가 보여 BodySkeleton이 만들어지는 몸)이 하나라도 있으면 true.
    /// 체형 도구의 "전신 없음" 안내에 쓴다.
    public let hasBody: Bool
    /// 체형 분석이 실패했으면 그 이유. 사람이 없는 것과 구분한다.
    public let bodyAnalysisFailure: MellowError?
    /// 임계값을 통과한 추정 성별.
    /// 얼굴과 같은 길이이거나 빈 배열이다.
    public let genders: [Gender?]
    /// 몸 인덱스 → 얼굴 인덱스.
    /// 짝이 없는 몸은 키가 없다.
    public let bodyFaceMatches: [Int: Int]

    public init(
        pixelSize: CGSize, thumbnail: CGImage, faces: [FaceGeometry], faceAnalysisFailure: MellowError?,
        hasPerson: Bool = false, personAnalysisFailure: MellowError? = nil, hasBody: Bool = false,
        bodyAnalysisFailure: MellowError? = nil, genders: [Gender?] = [], bodyFaceMatches: [Int: Int] = [:]
    ) {
        self.pixelSize = pixelSize
        self.thumbnail = thumbnail
        self.faces = faces
        self.faceAnalysisFailure = faceAnalysisFailure
        self.hasPerson = hasPerson
        self.personAnalysisFailure = personAnalysisFailure
        self.hasBody = hasBody
        self.bodyAnalysisFailure = bodyAnalysisFailure
        self.genders = genders
        self.bodyFaceMatches = bodyFaceMatches
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
    private let personAnalyzer: (any PersonAnalyzer)?
    private let bodyAnalyzer: (any BodyAnalyzer)?
    private let instanceAnalyzer: (any PersonInstanceAnalyzer)?
    private let genderEstimator: (any GenderEstimator)?
    private let tuning: RenderTuning
    private let lookCatalog: LookCatalog
    private let makeupCatalog: MakeupCatalog
    /// 미리보기 이미지가 LRU로 밀려나도 일부러 남긴다. renderOriginal이 얼굴 좌표를 써야 한다.
    private var entries: [PhotoID: Entry] = [:]
    private var cache: PreviewCache

    /// personAnalyzer·bodyAnalyzer·instanceAnalyzer가 nil이면 그 분석을 하지 않는다(사람 없음과 같다). 앱은 Vision 구현을 넘긴다.
    /// genderEstimator가 nil이면 모든 얼굴의 추정 성별이 미지정이다.
    /// makeupCatalog가 비어 있으면 색을 고르는 메이크업 부위만 빠진다.
    public init(
        analyzer: any FaceAnalyzer, personAnalyzer: (any PersonAnalyzer)? = nil,
        bodyAnalyzer: (any BodyAnalyzer)? = nil, instanceAnalyzer: (any PersonInstanceAnalyzer)? = nil,
        genderEstimator: (any GenderEstimator)? = nil, tuning: RenderTuning, lookCatalog: LookCatalog = .empty,
        makeupCatalog: MakeupCatalog = .empty
    ) {
        self.analyzer = analyzer
        self.personAnalyzer = personAnalyzer
        self.bodyAnalyzer = bodyAnalyzer
        self.instanceAnalyzer = instanceAnalyzer
        self.genderEstimator = genderEstimator
        self.tuning = tuning
        self.lookCatalog = lookCatalog
        self.makeupCatalog = makeupCatalog
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
        let person = analyzePerson(in: preview)
        let body = analyzeBodies(in: preview)
        let instances = analyzeInstances(in: preview)
        let people = assignInstances(instances, bodies: body.bodies, faces: faces, extent: preview.extent)
        let outlines = probeOutlines(
            bodies: body.bodies, personMask: person.mask, instances: instances, owners: people.bodies,
            extent: preview.extent)
        let matches = BodyFaceMatcher.match(bodies: body.bodies, faces: faces, extent: preview.extent, tuning: tuning)
        let genders = estimateGenders(in: preview, faces: faces)
        let analysis = PhotoAnalysis(
            faces: faces, faceAnalysisFailure: failure, blemishes: detectBlemishes(in: preview, faces: faces),
            personMask: person.mask, personAnalysisFailure: person.failure, bodies: body.bodies,
            bodyAnalysisFailure: body.failure, genderEstimates: genders, personInstances: instances,
            bodyFaceMatches: matches, bodyInstances: people.bodies, faceInstances: people.faces,
            bodyOutlines: outlines)
        let thumbnail = try renderer.makeCGImage(Self.scaled(preview, maxDimension: tuning.thumbnailMaxDimension))
        entries[id] = Entry(analysis: analysis, thumbnail: CIImage(cgImage: thumbnail))
        cache.insert(preview, for: id)
        releaseMasksOfEvictedPreviews()
        // 렌더(BodyShapeRig)와 같은 판정이라 앱 안내와 실제 동작이 어긋나지 않는다.
        let usable = body.bodies.contains { BodySkeleton(body: $0, extent: preview.extent, tuning: tuning) != nil }
        return PreparedPhoto(
            pixelSize: metadata.pixelSize, thumbnail: thumbnail, faces: faces, faceAnalysisFailure: failure,
            hasPerson: person.mask != nil, personAnalysisFailure: person.failure, hasBody: usable,
            bodyAnalysisFailure: body.failure, genders: genders.map { $0?.gender }, bodyFaceMatches: matches)
    }

    /// 캐시가 비었으면 cannotCreatePreview. 호출자가 prepare를 다시 한다.
    /// `showsUncropped`이면 자르기만 건너뛴다. 자르기 도구 화면이 전체 이미지 위에 자르기 틀을 그린다.
    public func preview(_ id: PhotoID, recipe: EditRecipe, showsUncropped: Bool = false) throws -> CGImage {
        guard let entry = entries[id], let image = cache.image(for: id) else {
            throw MellowError.cannotCreatePreview
        }
        let context = RenderContext(
            extent: image.extent, recipe: recipe, analysis: entry.analysis, tuning: tuning, lookCatalog: lookCatalog,
            makeupCatalog: makeupCatalog, skipsCrop: showsUncropped)
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

    /// 미리보기가 캐시에서 밀려났으면 다시 준비하고 새 결과를 돌려준다. 캐시에 남아 있으면 nil.
    /// 다시 준비하면 분석도 새로 하므로 호출자는 돌려받은 결과로 사진 정보(얼굴·인물·체형과 그 실패)를 갱신한다.
    @discardableResult
    public func reprepareIfEvicted(_ id: PhotoID, at url: URL) throws -> PreparedPhoto? {
        guard cache.image(for: id) == nil else { return nil }
        return try prepare(id, at: url)
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
        // 미리보기가 밀려난 사진의 마스크만 놓는다. 캐시에 남은 이 사진은 원본 해상도 마스크를 RegionMaskCache 상한까지 계속 들고 있다.
        // 이미 만든 렌더 그래프는 비트맵을 붙잡고 있어 놓아도 안전하다.
        releaseMasksOfEvictedPreviews()
        return rendered
    }

    private func render(url: URL, recipe: EditRecipe, analysis: PhotoAnalysis, maxDimension: Int?) throws -> CIImage {
        let image = try loader.load(url: url, maxDimension: maxDimension)
        let context = RenderContext(
            extent: image.extent, recipe: recipe, analysis: analysis, tuning: tuning, lookCatalog: lookCatalog,
            makeupCatalog: makeupCatalog)
        return try pipeline.render(image, context: context)
    }

    /// 잡티 분석이 실패해도 사진 준비는 막지 않는다. 자동 잡티만 동작하지 않는다.
    /// 자동 잡티가 꺼져 있어도 준비 때 찾는다(사진당 약 0.06초). 분석은 준비 때 한 번이고(스펙 1.4) 스위치를 켤 때 지연이 없다.
    private func detectBlemishes(in image: CIImage, faces: [FaceGeometry]) -> [BlemishSpot] {
        guard !faces.isEmpty else { return [] }
        return (try? BlemishDetector(tuning: tuning, renderer: renderer).detect(image: image, faces: faces)) ?? []
    }

    /// 인물 분석이 실패해도 사진 준비는 막지 않는다. 배경 흐림 단계만 건너뛴다(스펙 1.4).
    private func analyzePerson(in image: CIImage) -> (mask: CIImage?, failure: MellowError?) {
        guard let personAnalyzer else { return (nil, nil) }
        do {
            return (try personAnalyzer.personMask(image), nil)
        } catch let error as MellowError {
            return (nil, error)
        } catch {
            return (nil, .personAnalysisUnavailable(reason: error.localizedDescription))
        }
    }

    /// 추정 실패는 준비를 막지 않는다.
    /// 추정은 보조 정보라 실패 사유도 남기지 않고 모든 얼굴을 미지정으로 둔다.
    private func estimateGenders(in image: CIImage, faces: [FaceGeometry]) -> [GenderEstimate?] {
        guard let genderEstimator, !faces.isEmpty else { return Array(repeating: nil, count: faces.count) }
        let raw = (try? genderEstimator.estimate(image, faces: faces)) ?? []
        return Self.acceptedEstimates(raw, faces: faces, tuning: tuning)
    }

    /// 임계값(신뢰도·얼굴 폭·yaw)을 적용한다.
    /// 길이가 얼굴 수와 다르면 모두 nil이다.
    /// yaw를 모르는 얼굴은 정면으로 본다.
    public static func acceptedEstimates(_ estimates: [GenderEstimate?], faces: [FaceGeometry], tuning: RenderTuning)
        -> [GenderEstimate?]
    {
        guard estimates.count == faces.count else { return Array(repeating: nil, count: faces.count) }
        return zip(estimates, faces).map { estimate, face in
            guard let estimate, estimate.confidence >= tuning.genderMinConfidence,
                face.boundingBox.width >= tuning.genderMinFaceWidth, abs(face.yaw ?? 0) <= tuning.genderMaxYaw
            else { return nil }
            return estimate
        }
    }

    /// 체형 분석이 실패해도 사진 준비는 막지 않는다. 체형 원소만 빠진다(스펙 1.4).
    private func analyzeBodies(in image: CIImage) -> (bodies: [BodyGeometry], failure: MellowError?) {
        guard let bodyAnalyzer else { return ([], nil) }
        do {
            return (try bodyAnalyzer.analyze(image), nil)
        } catch let error as MellowError {
            return ([], error)
        } catch {
            return ([], .bodyAnalysisUnavailable(reason: error.localizedDescription))
        }
    }

    /// 인스턴스 분석이 실패해도 사진 준비는 막지 않는다.
    /// 보조 정보라 실패 사유를 남기지 않고 빈 배열로 둔다(스펙 5.1).
    private func analyzeInstances(in image: CIImage) -> [CIImage] {
        guard let instanceAnalyzer else { return [] }
        return (try? instanceAnalyzer.instanceMasks(image)) ?? []
    }

    /// 몸·얼굴마다 그 표본점이 든 인스턴스를 고른다.
    /// 몸은 목·두 어깨·두 엉덩이, 얼굴은 상자 중심이다.
    /// 쓸 수 있는 몸이나 얼굴이 인스턴스보다 많으면 아무것도 배정하지 않는다(스펙 결정: 5명 이상이면 전체 마스크).
    /// 인스턴스가 없는 사람의 이웃 보호가 빠져 그 사람이 옆 사람 인스턴스를 끌 수 있기 때문이다.
    private func assignInstances(_ instances: [CIImage], bodies: [BodyGeometry], faces: [FaceGeometry], extent: CGRect)
        -> (bodies: [Int: Int], faces: [Int: Int])
    {
        guard !instances.isEmpty else { return ([:], [:]) }
        let usableBodies = bodies.filter { BodySkeleton(body: $0, extent: extent, tuning: tuning) != nil }.count
        guard usableBodies <= instances.count, faces.count <= instances.count else { return ([:], [:]) }
        var bodyOwners: [Int: Int] = [:]
        for (index, body) in bodies.enumerated() {
            let points = InstanceAssignment.samplePoints(of: body, extent: extent, tuning: tuning)
            bodyOwners[index] = InstanceAssignment.owner(
                of: points, in: instances, extent: extent, renderer: renderer, tuning: tuning)
        }
        var faceOwners: [Int: Int] = [:]
        for (index, face) in faces.enumerated() {
            let points = InstanceAssignment.samplePoints(of: face, extent: extent)
            faceOwners[index] = InstanceAssignment.owner(
                of: points, in: instances, extent: extent, renderer: renderer, tuning: tuning)
        }
        return (bodyOwners, faceOwners)
    }

    /// 몸마다 그 사람 마스크에서 몸통 옆선을 찾는다(스펙 5.8).
    /// 마스크는 배정된 인스턴스 ?? 전체 인물 마스크다(RenderContext.personMask(forBody:)의 own과 같은 규칙).
    /// 두 엉덩이가 있는 쓸 수 있는 몸만 찾는다.
    /// 마스크가 없거나 읽지 못하면 그 몸은 키가 없다.
    /// 마스크마다 CPU 바이트로 한 번만 읽는다.
    private func probeOutlines(
        bodies: [BodyGeometry], personMask: CIImage?, instances: [CIImage], owners: [Int: Int], extent: CGRect
    ) -> [Int: BodyOutline] {
        var samplers: [Int: MaskSampler] = [:]
        var result: [Int: BodyOutline] = [:]
        for (index, body) in bodies.enumerated() {
            guard let skeleton = BodySkeleton(body: body, extent: extent, tuning: tuning), skeleton.hipCenter != nil
            else { continue }
            let owner = owners[index].flatMap { instances.indices.contains($0) ? $0 : nil }
            let key = owner ?? Self.combinedMaskKey
            if samplers[key] == nil {
                guard let mask = owner.map({ instances[$0] }) ?? personMask else { continue }
                samplers[key] = MaskSampler(mask: mask, renderer: renderer)
            }
            guard let sampler = samplers[key] else { continue }
            result[index] = BodyOutlineProbe.probe(
                skeleton: skeleton, mask: sampler, extent: extent, levels: BodyShapeRig.outlineLevels, tuning: tuning)
        }
        return result
    }

    /// probeOutlines의 표본기 캐시에서 전체 인물 마스크의 열쇠. 인스턴스 인덱스는 0 이상이다.
    private static let combinedMaskKey = -1

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
