import CoreImage
import MellowShared
import XCTest

@testable import MellowRendering

struct StubFaceAnalyzer: FaceAnalyzer {
    var result: Result<[FaceGeometry], MellowError>
    func analyze(_ image: CIImage) throws -> [FaceGeometry] { try result.get() }
}

struct StubPersonAnalyzer: PersonAnalyzer {
    var result: Result<CIImage?, MellowError>
    func personMask(_ image: CIImage) throws -> CIImage? { try result.get() }
}

struct StubBodyAnalyzer: BodyAnalyzer {
    var result: Result<[BodyGeometry], MellowError>
    func analyze(_ image: CIImage) throws -> [BodyGeometry] { try result.get() }
}

struct StubInstanceAnalyzer: PersonInstanceAnalyzer {
    var result: Result<[CIImage], MellowError>
    func instanceMasks(_ image: CIImage) throws -> [CIImage] { try result.get() }
}

struct StubGenderEstimator: GenderEstimator {
    var result: Result<[GenderEstimate?], MellowError>
    func estimate(_ image: CIImage, faces: [FaceGeometry]) throws -> [GenderEstimate?] { try result.get() }
}

/// 호출마다 다음 결과를 돌려주고 마지막 결과는 계속 되풀이한다. 다시 준비할 때 분석이 달라지는 경우를 흉내 낸다.
final class SequencedBodyAnalyzer: BodyAnalyzer, @unchecked Sendable {
    private let lock = NSLock()
    private var results: [Result<[BodyGeometry], MellowError>]

    init(_ results: [Result<[BodyGeometry], MellowError>]) {
        self.results = results
    }

    func analyze(_ image: CIImage) throws -> [BodyGeometry] {
        lock.lock()
        let result = results.count > 1 ? results.removeFirst() : results[0]
        lock.unlock()
        return try result.get()
    }
}

final class PhotoPipelineTests: XCTestCase {
    typealias Support = RenderingTestSupport

    private func writeSolidPNG(size: Int = 256) throws -> URL {
        let directory = try Support.temporaryDirectory()
        let url = directory.appendingPathComponent("solid.png")
        let cg = try Support.renderer.makeCGImage(Support.solid(CIColor(red: 0.5, green: 0.4, blue: 0.3), size: size))
        let destination = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil)!
        CGImageDestinationAddImage(destination, cg, nil)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        return url
    }

    /// 4px 폭 세로 줄무늬 PNG(256×192). 배경 흐림이 바뀐 것을 바이트로 알 수 있다.
    private func writeStripesPNG() throws -> URL {
        let image = CIFilter(name: "CIStripesGenerator", parameters: ["inputWidth": 4, "inputSharpness": 1])!
            .outputImage!.cropped(to: CGRect(x: 0, y: 0, width: 256, height: 192))
        return try Support.writePNG(image, name: "stripes")
    }

    func testPrepareReportsSizeThumbnailAndFaces() async throws {
        let url = try writeSolidPNG()
        let face = FaceGeometry(boundingBox: NormalizedRect(x: 0.2, y: 0.2, width: 0.6, height: 0.6))
        let pipeline = PhotoPipeline(analyzer: StubFaceAnalyzer(result: .success([face])), tuning: RenderTuning())
        let prepared = try await pipeline.prepare(PhotoID(), at: url)
        XCTAssertEqual(prepared.pixelSize, CGSize(width: 256, height: 256))
        XCTAssertEqual(prepared.faces, [face])
        XCTAssertNil(prepared.faceAnalysisFailure)
        XCTAssertLessThanOrEqual(
            max(prepared.thumbnail.width, prepared.thumbnail.height), RenderTuning().thumbnailMaxDimension)
    }

    func testPrepareStoresBlemishesOnlyWhenFacesExist() async throws {
        let synthetic = SyntheticFace.make(withBlemishes: true)
        let url = try Support.writePNG(synthetic.image, name: "face")
        let withFace = PhotoPipeline(
            analyzer: StubFaceAnalyzer(result: .success([synthetic.face])), tuning: RenderTuning())
        let id = PhotoID()
        _ = try await withFace.prepare(id, at: url)
        let spots = await withFace.preparedBlemishes(id)
        XCTAssertEqual(spots.count, SyntheticFace.blemishes.count)
        let noFace = PhotoPipeline(analyzer: StubFaceAnalyzer(result: .success([])), tuning: RenderTuning())
        let other = PhotoID()
        _ = try await noFace.prepare(other, at: url)
        let none = await noFace.preparedBlemishes(other)
        XCTAssertTrue(none.isEmpty)
    }

    func testPreviewHealsDetectedBlemishes() async throws {
        let synthetic = SyntheticFace.make(withBlemishes: true)
        let url = try Support.writePNG(synthetic.image, name: "face")
        let pipeline = PhotoPipeline(
            analyzer: StubFaceAnalyzer(result: .success([synthetic.face])), tuning: RenderTuning())
        let id = PhotoID()
        _ = try await pipeline.prepare(id, at: url)
        let plainImage = try await pipeline.preview(id, recipe: EditRecipe())
        var recipe = EditRecipe()
        recipe.portrait.skin.autoBlemish = true
        let healedImage = try await pipeline.preview(id, recipe: recipe)
        let plain = PixelGrid(plainImage)
        let healed = PixelGrid(healedImage)
        let center = SyntheticFace.blemishes[0]
        XCTAssertGreaterThanOrEqual(Int(healed.red(center)), Int(plain.red(center)) + 20)
    }

    func testRenderOriginalRefusesAutoBlemishOnlyWhenAnalysisFailed() async throws {
        let url = try writeSolidPNG()
        let id = PhotoID()
        let pipeline = PhotoPipeline(
            analyzer: StubFaceAnalyzer(result: .failure(.faceAnalysisUnavailable(reason: "test"))),
            tuning: RenderTuning())
        _ = try await pipeline.prepare(id, at: url)
        var recipe = EditRecipe()
        recipe.portrait.skin.autoBlemish = true
        do {
            _ = try await pipeline.renderOriginal(id, at: url, recipe: recipe, maxDimension: nil)
            XCTFail("자동 잡티만 켠 저장도 조용히 빠지면 안 된다")
        } catch {
            XCTAssertEqual(error as? MellowError, .faceAnalysisUnavailable(reason: "test"))
        }
    }

    func testFaceAnalysisFailureIsReportedNotThrown() async throws {
        let url = try writeSolidPNG()
        let pipeline = PhotoPipeline(
            analyzer: StubFaceAnalyzer(result: .failure(.faceAnalysisUnavailable(reason: "test"))),
            tuning: RenderTuning())
        let prepared = try await pipeline.prepare(PhotoID(), at: url)
        XCTAssertTrue(prepared.faces.isEmpty)
        XCTAssertEqual(prepared.faceAnalysisFailure, .faceAnalysisUnavailable(reason: "test"))
    }

    func testPreviewUsesCacheAndMatchesFreshRender() async throws {
        let url = try writeSolidPNG()
        let id = PhotoID()
        let pipeline = PhotoPipeline(analyzer: StubFaceAnalyzer(result: .success([])), tuning: RenderTuning())
        _ = try await pipeline.prepare(id, at: url)
        try FileManager.default.removeItem(at: url)
        var recipe = EditRecipe()
        recipe.color.exposure = 0.5
        let cached = try await pipeline.preview(id, recipe: recipe)
        XCTAssertEqual(cached.width, 256, "파일이 지워져도 캐시로 렌더된다")
        let fresh = try Support.renderer.makeCGImage(
            Support.render(Support.solid(CIColor(red: 0.5, green: 0.4, blue: 0.3)), recipe: recipe))
        XCTAssertEqual(Array(cached.dataProvider!.data! as Data), Array(fresh.dataProvider!.data! as Data))
    }

    func testPreviewShowsUncroppedWhenRequested() async throws {
        let url = try writeSolidPNG()
        let id = PhotoID()
        let pipeline = PhotoPipeline(analyzer: StubFaceAnalyzer(result: .success([])), tuning: RenderTuning())
        _ = try await pipeline.prepare(id, at: url)
        var recipe = EditRecipe()
        recipe.geometry.crop = NormalizedRect(x: 0, y: 0, width: 0.5, height: 0.5)
        let cropped = try await pipeline.preview(id, recipe: recipe)
        let uncropped = try await pipeline.preview(id, recipe: recipe, showsUncropped: true)
        XCTAssertEqual(cropped.width, 128)
        XCTAssertEqual(uncropped.width, 256)
    }

    func testPreviewOfUnpreparedPhotoThrows() async throws {
        let pipeline = PhotoPipeline(analyzer: StubFaceAnalyzer(result: .success([])), tuning: RenderTuning())
        do {
            _ = try await pipeline.preview(PhotoID(), recipe: EditRecipe())
            XCTFail("준비되지 않은 사진은 렌더할 수 없다")
        } catch {
            XCTAssertEqual(error as? MellowError, .cannotCreatePreview)
        }
    }

    func testCacheEvictsLeastRecentlyUsedBeyondCapacity() async throws {
        var tuning = RenderTuning()
        tuning.previewCacheCapacity = 2
        let pipeline = PhotoPipeline(analyzer: StubFaceAnalyzer(result: .success([])), tuning: tuning)
        let ids = [PhotoID(), PhotoID(), PhotoID()]
        for id in ids {
            _ = try await pipeline.prepare(id, at: try writeSolidPNG())
        }
        let cached = await pipeline.cachedPreviewIDs
        XCTAssertEqual(Set(cached), Set(ids.dropFirst()))
    }

    func testRenderOriginalRefusesFaceEditsWhenAnalysisFailed() async throws {
        let url = try writeSolidPNG()
        let id = PhotoID()
        let pipeline = PhotoPipeline(
            analyzer: StubFaceAnalyzer(result: .failure(.faceAnalysisUnavailable(reason: "test"))),
            tuning: RenderTuning())
        _ = try await pipeline.prepare(id, at: url)
        var recipe = EditRecipe()
        recipe.portrait.skin.smoothing = 0.3
        do {
            _ = try await pipeline.renderOriginal(id, at: url, recipe: recipe, maxDimension: nil)
            XCTFail("얼굴 보정이 조용히 빠지면 안 된다")
        } catch {
            XCTAssertEqual(error as? MellowError, .faceAnalysisUnavailable(reason: "test"))
        }
        recipe.portrait.skin.smoothing = 0
        recipe.color.exposure = 0.2
        let rendered = try await pipeline.renderOriginal(id, at: url, recipe: recipe, maxDimension: nil)
        XCTAssertEqual(rendered.extent.size, CGSize(width: 256, height: 256))
    }

    func testRenderOriginalWithNoFacesAndSkinValueSucceeds() async throws {
        let url = try writeSolidPNG()
        let id = PhotoID()
        let pipeline = PhotoPipeline(analyzer: StubFaceAnalyzer(result: .success([])), tuning: RenderTuning())
        _ = try await pipeline.prepare(id, at: url)
        var recipe = EditRecipe()
        recipe.portrait.skin.smoothing = 0.3
        recipe.color.exposure = 0.2
        let rendered = try await pipeline.renderOriginal(id, at: url, recipe: recipe, maxDimension: 128)
        XCTAssertEqual(rendered.extent.size, CGSize(width: 128, height: 128), "분석은 성공했고 얼굴만 없으면 색감만 적용해 저장한다")
    }

    func testRenderOriginalOfUnpreparedPhotoRefusesFaceEditsButAllowsColor() async throws {
        let url = try writeSolidPNG()
        let id = PhotoID()
        let pipeline = PhotoPipeline(analyzer: StubFaceAnalyzer(result: .success([])), tuning: RenderTuning())
        var faceRecipe = EditRecipe()
        faceRecipe.portrait.skin.smoothing = 0.3
        do {
            _ = try await pipeline.renderOriginal(id, at: url, recipe: faceRecipe, maxDimension: nil)
            XCTFail("준비되지 않은 사진의 얼굴 보정이 조용히 빠지면 안 된다")
        } catch {
            // 앱이 이 식별자를 사용자 문구로 바꾼다. 모듈은 한국어 문구를 갖지 않는다.
            XCTAssertEqual(error as? MellowError, .faceAnalysisUnavailable(reason: "photo-not-prepared"))
            XCTAssertEqual(PhotoPipeline.unpreparedReason, "photo-not-prepared")
        }
        var colorRecipe = EditRecipe()
        colorRecipe.color.exposure = 0.2
        let rendered = try await pipeline.renderOriginal(id, at: url, recipe: colorRecipe, maxDimension: nil)
        XCTAssertEqual(rendered.extent.size, CGSize(width: 256, height: 256), "색감만이면 준비 없이도 저장한다")
    }

    func testAutoEnhanceSuggestionUsesCachedPreview() async throws {
        let url = try writeSolidPNG()
        let id = PhotoID()
        let pipeline = PhotoPipeline(analyzer: StubFaceAnalyzer(result: .success([])), tuning: RenderTuning())
        _ = try await pipeline.prepare(id, at: url)
        let suggestion = try await pipeline.autoEnhanceSuggestion(id, hasFaces: false)
        XCTAssertTrue(suggestion.color.exposure.isFinite)
        await pipeline.evict(id)
        do {
            _ = try await pipeline.autoEnhanceSuggestion(id, hasFaces: false)
            XCTFail("캐시가 없으면 제안할 수 없다")
        } catch {
            XCTAssertEqual(error as? MellowError, .cannotCreatePreview)
        }
    }

    func testLookThumbnailsCoverCatalogAndDiffer() async throws {
        let url = try writeSolidPNG(size: 512)
        let id = PhotoID()
        let catalog = try Support.sharedLookCatalog()
        let pipeline = PhotoPipeline(
            analyzer: StubFaceAnalyzer(result: .success([])), tuning: RenderTuning(), lookCatalog: catalog)
        _ = try await pipeline.prepare(id, at: url)
        let thumbnails = try await pipeline.lookThumbnails(id)
        XCTAssertEqual(Set(thumbnails.keys), Set(LookCatalog.builtInIDs))
        for (lookID, image) in thumbnails {
            XCTAssertLessThanOrEqual(max(image.width, image.height), RenderTuning().thumbnailMaxDimension, lookID)
        }
        let mono = try XCTUnwrap(thumbnails["mono"])
        let vivid = try XCTUnwrap(thumbnails["vivid"])
        XCTAssertNotEqual(Array(mono.dataProvider!.data! as Data), Array(vivid.dataProvider!.data! as Data))
    }

    func testLookThumbnailsRequirePreparedPhoto() async throws {
        let pipeline = PhotoPipeline(
            analyzer: StubFaceAnalyzer(result: .success([])), tuning: RenderTuning(),
            lookCatalog: try Support.sharedLookCatalog())
        do {
            _ = try await pipeline.lookThumbnails(PhotoID())
            XCTFail("준비 안 된 사진은 썸네일을 만들 수 없다")
        } catch {
            XCTAssertEqual(error as? MellowError, .cannotCreatePreview)
        }
    }

    func testEvictedPreviewReleasesRegionMasks() async throws {
        let synthetic = SyntheticFace.make()
        let url = try Support.writePNG(synthetic.image, name: "face")
        var tuning = RenderTuning()
        tuning.previewCacheCapacity = 1
        let pipeline = PhotoPipeline(analyzer: StubFaceAnalyzer(result: .success([synthetic.face])), tuning: tuning)
        let first = PhotoID()
        _ = try await pipeline.prepare(first, at: url)
        var recipe = EditRecipe()
        recipe.portrait.skin.smoothing = 0.5
        _ = try await pipeline.preview(first, recipe: recipe)
        let prepared = await pipeline.preparedAnalysis(first)
        let analysis = try XCTUnwrap(prepared)
        XCTAssertEqual(analysis.regionMasks.count, 1)
        _ = try await pipeline.prepare(PhotoID(), at: try writeSolidPNG())
        XCTAssertEqual(analysis.regionMasks.count, 0, "미리보기가 캐시에서 밀려나면 마스크 비트맵도 놓는다")
    }

    func testPrepareStoresPersonMaskAndReportsPresence() async throws {
        let url = try writeSolidPNG()
        let mask = Support.personMask(
            size: CGSize(width: 64, height: 48), person: CGRect(x: 16, y: 8, width: 32, height: 32))
        let pipeline = PhotoPipeline(
            analyzer: StubFaceAnalyzer(result: .success([])),
            personAnalyzer: StubPersonAnalyzer(result: .success(mask)), tuning: RenderTuning())
        let id = PhotoID()
        let prepared = try await pipeline.prepare(id, at: url)
        XCTAssertTrue(prepared.hasPerson)
        XCTAssertNil(prepared.personAnalysisFailure)
        let analysis = await pipeline.preparedAnalysis(id)
        XCTAssertEqual(analysis?.personMask?.extent, mask.extent, "마스크는 받은 크기 그대로 보관한다")
    }

    func testPersonAnalysisFailureIsReportedNotThrown() async throws {
        let url = try writeSolidPNG()
        let face = FaceGeometry(boundingBox: NormalizedRect(x: 0.2, y: 0.2, width: 0.6, height: 0.6))
        let pipeline = PhotoPipeline(
            analyzer: StubFaceAnalyzer(result: .success([face])),
            personAnalyzer: StubPersonAnalyzer(result: .failure(.personAnalysisUnavailable(reason: "test"))),
            tuning: RenderTuning())
        let prepared = try await pipeline.prepare(PhotoID(), at: url)
        XCTAssertFalse(prepared.hasPerson)
        XCTAssertEqual(prepared.personAnalysisFailure, .personAnalysisUnavailable(reason: "test"))
        XCTAssertEqual(prepared.faces, [face], "인물 분석 실패가 얼굴 분석에 영향을 주지 않는다")
        XCTAssertNil(prepared.faceAnalysisFailure)
    }

    func testWithoutPersonAnalyzerThereIsNoPerson() async throws {
        let url = try writeSolidPNG()
        let pipeline = PhotoPipeline(analyzer: StubFaceAnalyzer(result: .success([])), tuning: RenderTuning())
        let id = PhotoID()
        let prepared = try await pipeline.prepare(id, at: url)
        XCTAssertFalse(prepared.hasPerson)
        XCTAssertNil(prepared.personAnalysisFailure)
        let analysis = await pipeline.preparedAnalysis(id)
        XCTAssertNil(analysis?.personMask)
    }

    func testPrepareStoresBodiesAndReportsUsableBody() async throws {
        let url = try writeSolidPNG()
        let large = Support.standingBody(in: Support.standingBox)
        let small = Support.standingBody(in: NormalizedRect(x: 0.7, y: 0.5, width: 0.2, height: 0.3))
        let pipeline = PhotoPipeline(
            analyzer: StubFaceAnalyzer(result: .success([])),
            bodyAnalyzer: StubBodyAnalyzer(result: .success([large, small])), tuning: RenderTuning())
        let id = PhotoID()
        let prepared = try await pipeline.prepare(id, at: url)
        XCTAssertTrue(prepared.hasBody)
        XCTAssertNil(prepared.bodyAnalysisFailure)
        let analysis = await pipeline.preparedAnalysis(id)
        XCTAssertEqual(analysis?.bodies, [large, small], "분석기가 준 순서 그대로 보관한다")
    }

    func testBodyWithoutBothShouldersIsNotUsable() async throws {
        let url = try writeSolidPNG()
        let body = Support.standingBody(in: Support.standingBox, omitting: [.leftShoulder])
        let pipeline = PhotoPipeline(
            analyzer: StubFaceAnalyzer(result: .success([])),
            bodyAnalyzer: StubBodyAnalyzer(result: .success([body])), tuning: RenderTuning())
        let id = PhotoID()
        let prepared = try await pipeline.prepare(id, at: url)
        XCTAssertFalse(prepared.hasBody, "체형 이동량의 기준인 어깨 폭이 없다")
        let analysis = await pipeline.preparedAnalysis(id)
        XCTAssertEqual(analysis?.bodies.count, 1, "관절은 그대로 보관한다")
    }

    func testBodyAnalysisFailureIsReportedNotThrown() async throws {
        let url = try writeSolidPNG()
        let face = FaceGeometry(boundingBox: NormalizedRect(x: 0.2, y: 0.2, width: 0.6, height: 0.6))
        let mask = Support.personMask(
            size: CGSize(width: 64, height: 48), person: CGRect(x: 16, y: 8, width: 32, height: 32))
        let pipeline = PhotoPipeline(
            analyzer: StubFaceAnalyzer(result: .success([face])),
            personAnalyzer: StubPersonAnalyzer(result: .success(mask)),
            bodyAnalyzer: StubBodyAnalyzer(result: .failure(.bodyAnalysisUnavailable(reason: "test"))),
            tuning: RenderTuning())
        let prepared = try await pipeline.prepare(PhotoID(), at: url)
        XCTAssertFalse(prepared.hasBody)
        XCTAssertEqual(prepared.bodyAnalysisFailure, .bodyAnalysisUnavailable(reason: "test"))
        XCTAssertEqual(prepared.faces, [face], "체형 분석 실패가 얼굴 분석에 영향을 주지 않는다")
        XCTAssertTrue(prepared.hasPerson, "인물 분석에도 영향을 주지 않는다")
    }

    func testWithoutBodyAnalyzerThereIsNoBody() async throws {
        let url = try writeSolidPNG()
        let pipeline = PhotoPipeline(analyzer: StubFaceAnalyzer(result: .success([])), tuning: RenderTuning())
        let id = PhotoID()
        let prepared = try await pipeline.prepare(id, at: url)
        XCTAssertFalse(prepared.hasBody)
        XCTAssertNil(prepared.bodyAnalysisFailure)
        let analysis = await pipeline.preparedAnalysis(id)
        XCTAssertEqual(analysis?.bodies, [])
    }

    func testAnyUsableBodyReportsBody() async throws {
        let url = try writeSolidPNG()
        let unusable = Support.standingBody(in: Support.standingBox, omitting: [.leftShoulder])
        let usable = Support.standingBody(in: NormalizedRect(x: 0.6, y: 0.3, width: 0.3, height: 0.5))
        let pipeline = PhotoPipeline(
            analyzer: StubFaceAnalyzer(result: .success([])),
            bodyAnalyzer: StubBodyAnalyzer(result: .success([unusable, usable])), tuning: RenderTuning())
        let prepared = try await pipeline.prepare(PhotoID(), at: url)
        XCTAssertTrue(prepared.hasBody, "가장 큰 몸이 아니어도 쓸 수 있는 몸이 있으면 체형 도구를 쓴다")
    }

    func testPrepareStoresBodyFaceMatchesAndInstances() async throws {
        let url = try writeSolidPNG()
        // 왼쪽 몸의 목(0.2, 0.492)은 얼굴 기대점(0.2, 0.5) 바로 아래이고 오른쪽 몸은 얼굴 폭의 2.5배 떨어져 있다.
        let face = FaceGeometry(boundingBox: NormalizedRect(x: 0.1, y: 0.55, width: 0.2, height: 0.2))
        let left = Support.standingBody(in: NormalizedRect(x: 0, y: 0, width: 0.4, height: 0.6))
        let right = Support.standingBody(in: NormalizedRect(x: 0.5, y: 0, width: 0.4, height: 0.6))
        // Vision처럼 사진과 비율이 다른 작은 마스크다. 인스턴스 0이 오른쪽 절반, 1이 왼쪽 절반이다.
        let maskSize = CGSize(width: 64, height: 48)
        let rightHalf = Support.personMask(size: maskSize, person: CGRect(x: 32, y: 0, width: 32, height: 48))
        let leftHalf = Support.personMask(size: maskSize, person: CGRect(x: 0, y: 0, width: 32, height: 48))
        let pipeline = PhotoPipeline(
            analyzer: StubFaceAnalyzer(result: .success([face])),
            bodyAnalyzer: StubBodyAnalyzer(result: .success([left, right])),
            instanceAnalyzer: StubInstanceAnalyzer(result: .success([rightHalf, leftHalf])), tuning: RenderTuning())
        let id = PhotoID()
        let prepared = try await pipeline.prepare(id, at: url)
        XCTAssertEqual(prepared.bodyFaceMatches, [0: 0], "얼굴 아래 몸만 짝이 된다")
        let stored = await pipeline.preparedAnalysis(id)
        let analysis = try XCTUnwrap(stored)
        XCTAssertEqual(analysis.bodyFaceMatches, [0: 0])
        XCTAssertEqual(analysis.personInstances.count, 2, "인스턴스 마스크는 받은 그대로 보관한다")
        XCTAssertEqual(analysis.personInstances.first?.extent, rightHalf.extent, "Vision 원래 해상도")
        XCTAssertEqual(analysis.bodyInstances, [0: 1, 1: 0], "두 몸이 서로 다른 인스턴스에 놓인다")
        XCTAssertEqual(analysis.faceInstances, [0: 1], "얼굴은 상자 중심이 든 인스턴스")
    }

    func testMoreBodiesThanInstancesUsesTheCombinedMask() async throws {
        let url = try writeSolidPNG()
        // 쓸 수 있는 몸 다섯이 가로로 늘어서 있고 인스턴스는 넷뿐이다(Vision 인스턴스 상한).
        let bodies = (0..<5).map { index in
            Support.standingBody(in: NormalizedRect(x: 0.2 * Double(index), y: 0, width: 0.2, height: 0.6))
        }
        let maskSize = CGSize(width: 80, height: 48)
        let instances = (0..<4).map { index in
            Support.personMask(size: maskSize, person: CGRect(x: 16 * index, y: 0, width: 16, height: 48))
        }
        let pipeline = PhotoPipeline(
            analyzer: StubFaceAnalyzer(result: .success([])),
            bodyAnalyzer: StubBodyAnalyzer(result: .success(bodies)),
            instanceAnalyzer: StubInstanceAnalyzer(result: .success(instances)), tuning: RenderTuning())
        let id = PhotoID()
        _ = try await pipeline.prepare(id, at: url)
        let stored = await pipeline.preparedAnalysis(id)
        let analysis = try XCTUnwrap(stored)
        XCTAssertEqual(analysis.bodyInstances, [:], "사람이 인스턴스보다 많으면 모든 몸이 전체 마스크를 쓴다")
        XCTAssertEqual(analysis.faceInstances, [:])
    }

    func testFacesWithoutBodiesDoNotCountAgainstInstances() async throws {
        let url = try writeSolidPNG()
        // 커플(얼굴–몸 두 쌍)과 오른쪽 위에 작게 찍힌 행인 얼굴 하나. 행인은 몸이 없다.
        let faces = [
            FaceGeometry(boundingBox: NormalizedRect(x: 0.1, y: 0.55, width: 0.2, height: 0.2)),
            FaceGeometry(boundingBox: NormalizedRect(x: 0.6, y: 0.55, width: 0.2, height: 0.2)),
            FaceGeometry(boundingBox: NormalizedRect(x: 0.92, y: 0.9, width: 0.04, height: 0.04)),
        ]
        let left = Support.standingBody(in: NormalizedRect(x: 0, y: 0, width: 0.4, height: 0.6))
        let right = Support.standingBody(in: NormalizedRect(x: 0.5, y: 0, width: 0.4, height: 0.6))
        let maskSize = CGSize(width: 64, height: 48)
        let rightHalf = Support.personMask(size: maskSize, person: CGRect(x: 32, y: 0, width: 32, height: 48))
        let leftHalf = Support.personMask(size: maskSize, person: CGRect(x: 0, y: 0, width: 32, height: 48))
        let pipeline = PhotoPipeline(
            analyzer: StubFaceAnalyzer(result: .success(faces)),
            bodyAnalyzer: StubBodyAnalyzer(result: .success([left, right])),
            instanceAnalyzer: StubInstanceAnalyzer(result: .success([rightHalf, leftHalf])), tuning: RenderTuning())
        let id = PhotoID()
        let prepared = try await pipeline.prepare(id, at: url)
        XCTAssertEqual(prepared.bodyFaceMatches, [0: 0, 1: 1], "행인 얼굴은 몸과 짝이 되지 않는다")
        let stored = await pipeline.preparedAnalysis(id)
        let analysis = try XCTUnwrap(stored)
        XCTAssertEqual(analysis.bodyInstances, [0: 1, 1: 0], "얼굴 셋·인스턴스 둘이어도 몸과 짝인 사람은 둘이라 배정한다")
        XCTAssertEqual(analysis.faceInstances[0], 1)
        XCTAssertEqual(analysis.faceInstances[1], 0)
    }

    func testFacesWithoutAnyBodyStillGetInstances() async throws {
        let url = try writeSolidPNG()
        let faces = (0..<3).map { index in
            FaceGeometry(boundingBox: NormalizedRect(x: 0.3 * Double(index), y: 0.6, width: 0.2, height: 0.2))
        }
        let maskSize = CGSize(width: 64, height: 48)
        let instances = [
            Support.personMask(size: maskSize, person: CGRect(x: 0, y: 0, width: 32, height: 48)),
            Support.personMask(size: maskSize, person: CGRect(x: 32, y: 0, width: 32, height: 48)),
        ]
        let pipeline = PhotoPipeline(
            analyzer: StubFaceAnalyzer(result: .success(faces)),
            instanceAnalyzer: StubInstanceAnalyzer(result: .success(instances)), tuning: RenderTuning())
        let id = PhotoID()
        _ = try await pipeline.prepare(id, at: url)
        let stored = await pipeline.preparedAnalysis(id)
        let analysis = try XCTUnwrap(stored)
        XCTAssertEqual(analysis.faceInstances, [0: 0, 1: 0, 2: 1], "몸이 없는 얼굴은 사람 수에 들지 않고 상자 중심 인스턴스를 받는다")
        XCTAssertEqual(analysis.bodyInstances, [:])
    }

    func testInstanceFailureIsSilent() async throws {
        let url = try writeSolidPNG()
        let body = Support.standingBody(in: Support.standingBox)
        let pipeline = PhotoPipeline(
            analyzer: StubFaceAnalyzer(result: .success([])), bodyAnalyzer: StubBodyAnalyzer(result: .success([body])),
            instanceAnalyzer: StubInstanceAnalyzer(result: .failure(.personAnalysisUnavailable(reason: "test"))),
            tuning: RenderTuning())
        let id = PhotoID()
        let prepared = try await pipeline.prepare(id, at: url)
        XCTAssertTrue(prepared.hasBody, "인스턴스 실패가 체형 분석에 영향을 주지 않는다")
        XCTAssertNil(prepared.personAnalysisFailure, "인스턴스 실패는 사유를 남기지 않는다")
        let stored = await pipeline.preparedAnalysis(id)
        let analysis = try XCTUnwrap(stored)
        XCTAssertTrue(analysis.personInstances.isEmpty)
        XCTAssertEqual(analysis.bodyInstances, [:])
    }

    /// 스펙 5.8: 몸통 옆선은 준비 때 그 몸의 사람 마스크(인스턴스 ?? 전체)에서 찾는다.
    func testPrepareProbesBodyOutlinesFromEachBodysOwnMask() async throws {
        let url = try writeSolidPNG()
        let body = Support.standingBody(in: Support.standingBox)
        let noHips = Support.standingBody(in: Support.standingBox, omitting: [.leftHip])
        let everywhere = try OutlineTestSupport.mask(people: [CGRect(x: 0, y: 0, width: 512, height: 512)])
        func outlines(person: CIImage?, instances: [CIImage], bodies: [BodyGeometry]) async throws -> [Int: BodyOutline]
        {
            let pipeline = PhotoPipeline(
                analyzer: StubFaceAnalyzer(result: .success([])),
                personAnalyzer: person.map { StubPersonAnalyzer(result: .success($0)) },
                bodyAnalyzer: StubBodyAnalyzer(result: .success(bodies)),
                instanceAnalyzer: StubInstanceAnalyzer(result: .success(instances)), tuning: RenderTuning())
            let id = PhotoID()
            let prepared = try await pipeline.prepare(id, at: url)
            let analysis = await pipeline.preparedAnalysis(id)
            let stored = try XCTUnwrap(analysis).bodyOutlines
            XCTAssertEqual(prepared.bodyOutlines, stored, "앱이 받는 옆선은 렌더 분석과 같다")
            return stored
        }
        let combined = try await outlines(
            person: try OutlineTestSupport.detachedMask(), instances: [], bodies: [body, noHips])
        XCTAssertEqual(combined.keys.sorted(), [0], "두 엉덩이가 없는 몸은 찾지 않는다")
        XCTAssertEqual(combined[0]?.points.count, 4, "27%·30% × 두 쪽")
        XCTAssertEqual(combined[0]?.hasSideChestPoint, true)
        // 쓸 수 있는 몸이 인스턴스보다 많으면 배정하지 않으므로 몸 하나로 본다.
        let owned = try await outlines(
            person: everywhere, instances: [try OutlineTestSupport.detachedMask()], bodies: [body])
        XCTAssertEqual(owned[0]?.points.count, 4, "배정된 인스턴스 마스크를 쓴다(전체 마스크는 모두 사람이라 점이 없다)")
        let whole = try await outlines(person: everywhere, instances: [], bodies: [body])
        XCTAssertEqual(whole[0]?.points.count, 0, "마스크는 있는데 배경을 못 만나면 빈 옆선이다")
        XCTAssertEqual(whole[0]?.hasSideChestPoint, false, "부유방 높이 점이 없다")
        let none = try await outlines(person: nil, instances: [], bodies: [body])
        XCTAssertTrue(none.isEmpty, "마스크가 없으면 옆선이 없다")
    }

    func testReprepareReturnsNothingWhilePreviewIsCached() async throws {
        let url = try writeSolidPNG()
        let pipeline = PhotoPipeline(analyzer: StubFaceAnalyzer(result: .success([])), tuning: RenderTuning())
        let id = PhotoID()
        _ = try await pipeline.prepare(id, at: url)
        let reprepared = try await pipeline.reprepareIfEvicted(id, at: url)
        XCTAssertNil(reprepared, "캐시에 남아 있으면 다시 준비하지 않는다")
    }

    func testReprepareAfterEvictionReturnsFreshAnalysis() async throws {
        let firstURL = try writeSolidPNG()
        let secondURL = try writeSolidPNG()
        var tuning = RenderTuning()
        tuning.previewCacheCapacity = 1
        let body = Support.standingBody(in: Support.standingBox)
        let bodyAnalyzer = SequencedBodyAnalyzer([
            .failure(.bodyAnalysisUnavailable(reason: "first")), .success([body]),
        ])
        let pipeline = PhotoPipeline(
            analyzer: StubFaceAnalyzer(result: .success([])), bodyAnalyzer: bodyAnalyzer, tuning: tuning)
        let first = PhotoID()
        let initial = try await pipeline.prepare(first, at: firstURL)
        XCTAssertEqual(initial.bodyAnalysisFailure, .bodyAnalysisUnavailable(reason: "first"))
        _ = try await pipeline.prepare(PhotoID(), at: secondURL)
        let cached = await pipeline.cachedPreviewIDs
        XCTAssertFalse(cached.contains(first), "두 번째 사진이 첫 사진을 밀어낸다")
        let reprepared = try await pipeline.reprepareIfEvicted(first, at: firstURL)
        let fresh = try XCTUnwrap(reprepared, "밀려난 사진은 다시 준비한 결과를 돌려준다")
        XCTAssertNil(fresh.bodyAnalysisFailure, "다시 준비한 분석이 이전 실패를 대신한다")
        XCTAssertTrue(fresh.hasBody)
        let analysis = await pipeline.preparedAnalysis(first)
        XCTAssertEqual(analysis?.bodies, [body])
    }

    func testPersonAnalysisFailureSkipsOnlyBackgroundBlur() async throws {
        let url = try writeStripesPNG()
        let id = PhotoID()
        let pipeline = PhotoPipeline(
            analyzer: StubFaceAnalyzer(result: .success([])),
            personAnalyzer: StubPersonAnalyzer(result: .failure(.personAnalysisUnavailable(reason: "test"))),
            tuning: RenderTuning())
        _ = try await pipeline.prepare(id, at: url)
        var colorOnly = EditRecipe()
        colorOnly.color.exposure = 0.2
        var blurred = colorOnly
        blurred.background.blur = 0.6
        let previewBlurred = try await pipeline.preview(id, recipe: blurred)
        let previewColor = try await pipeline.preview(id, recipe: colorOnly)
        XCTAssertEqual(
            Array(previewBlurred.dataProvider!.data! as Data), Array(previewColor.dataProvider!.data! as Data),
            "미리보기는 흐림만 빼고 그린다")
        let original = try await pipeline.renderOriginal(id, at: url, recipe: blurred, maxDimension: nil)
        let originalColor = try await pipeline.renderOriginal(id, at: url, recipe: colorOnly, maxDimension: nil)
        XCTAssertEqual(try Support.bytes(original), try Support.bytes(originalColor), "저장도 오류 없이 흐림만 건너뛴다")
        let unprepared = try await pipeline.renderOriginal(PhotoID(), at: url, recipe: blurred, maxDimension: nil)
        XCTAssertEqual(unprepared.extent.size, CGSize(width: 256, height: 192), "준비 전 사진도 흐림 때문에 저장을 막지 않는다")
    }

    func testOriginalRenderScalesPreviewMaskToOutputSize() async throws {
        let url = try writeStripesPNG()
        let id = PhotoID()
        let mask = Support.personMask(
            size: CGSize(width: 64, height: 64), person: CGRect(x: 24, y: 16, width: 16, height: 32))
        let pipeline = PhotoPipeline(
            analyzer: StubFaceAnalyzer(result: .success([])),
            personAnalyzer: StubPersonAnalyzer(result: .success(mask)), tuning: RenderTuning())
        _ = try await pipeline.prepare(id, at: url)
        var plain = EditRecipe()
        plain.color.exposure = 0.2
        var blurred = plain
        blurred.background.blur = 1
        let sharpImage = try await pipeline.renderOriginal(id, at: url, recipe: plain, maxDimension: 128)
        let softImage = try await pipeline.renderOriginal(id, at: url, recipe: blurred, maxDimension: 128)
        XCTAssertEqual(softImage.extent.size, CGSize(width: 128, height: 96))
        let sharp = try Support.grid(sharpImage)
        let soft = try Support.grid(softImage)
        // 128×96 출력에서 사람은 x 48…80, y 24…72다.
        XCTAssertEqual(soft.rgba(CGPoint(x: 64, y: 48)), sharp.rgba(CGPoint(x: 64, y: 48)), "작은 출력에서도 사람 가운데는 그대로")
        XCTAssertNotEqual(soft.rgba(CGPoint(x: 10, y: 10)), sharp.rgba(CGPoint(x: 10, y: 10)), "배경은 흐려진다")
    }

    func testBodyAnalysisFailureSkipsOnlyBodyWarp() async throws {
        let url = try writeStripesPNG()
        var colorOnly = EditRecipe()
        colorOnly.color.exposure = 0.2
        var shaped = colorOnly
        shaped.body = BodyShapeAdjustments(legLength: 1, waist: -1)

        let working = PhotoPipeline(
            analyzer: StubFaceAnalyzer(result: .success([])),
            bodyAnalyzer: StubBodyAnalyzer(result: .success([Support.standingBody(in: Support.standingBox)])),
            tuning: RenderTuning())
        let workingID = PhotoID()
        _ = try await working.prepare(workingID, at: url)
        let reshaped = try await working.preview(workingID, recipe: shaped)
        let plain = try await working.preview(workingID, recipe: colorOnly)
        XCTAssertNotEqual(
            Array(reshaped.dataProvider!.data! as Data), Array(plain.dataProvider!.data! as Data), "관절이 있으면 허리가 바뀐다")

        let failing = PhotoPipeline(
            analyzer: StubFaceAnalyzer(result: .success([])),
            bodyAnalyzer: StubBodyAnalyzer(result: .failure(.bodyAnalysisUnavailable(reason: "test"))),
            tuning: RenderTuning())
        let id = PhotoID()
        _ = try await failing.prepare(id, at: url)
        let previewShaped = try await failing.preview(id, recipe: shaped)
        let previewColor = try await failing.preview(id, recipe: colorOnly)
        XCTAssertEqual(
            Array(previewShaped.dataProvider!.data! as Data), Array(previewColor.dataProvider!.data! as Data),
            "미리보기는 체형만 빼고 그린다")
        let original = try await failing.renderOriginal(id, at: url, recipe: shaped, maxDimension: nil)
        let originalColor = try await failing.renderOriginal(id, at: url, recipe: colorOnly, maxDimension: nil)
        XCTAssertEqual(try Support.bytes(original), try Support.bytes(originalColor), "저장도 오류 없이 체형만 건너뛴다")
        let unprepared = try await working.renderOriginal(PhotoID(), at: url, recipe: shaped, maxDimension: nil)
        let unpreparedColor = try await working.renderOriginal(PhotoID(), at: url, recipe: colorOnly, maxDimension: nil)
        XCTAssertEqual(unprepared.extent.size, CGSize(width: 256, height: 192), "준비 전 사진도 체형 때문에 저장을 막지 않는다")
        XCTAssertEqual(
            try Support.bytes(unprepared), try Support.bytes(unpreparedColor), "관절을 아는 파이프라인도 준비 전 사진은 체형을 건너뛴다")
    }

    func testPreviewAndOriginalPaintMakeupOnlyWithPipelineCatalog() async throws {
        let synthetic = SyntheticFace.makeFeatures()
        let url = try Support.writePNG(synthetic.image, name: "face")
        func bytes(_ image: CGImage) -> [UInt8] { Array(image.dataProvider!.data! as Data) }
        var recipe = EditRecipe()
        recipe.makeup.lip = MakeupTint(colorID: "lip-red", intensity: 1)
        let id = PhotoID()
        let painted = PhotoPipeline(
            analyzer: StubFaceAnalyzer(result: .success([synthetic.face])), tuning: RenderTuning(),
            makeupCatalog: try Support.sharedMakeupCatalog())
        _ = try await painted.prepare(id, at: url)
        let plain = try await painted.preview(id, recipe: EditRecipe())
        let lipped = try await painted.preview(id, recipe: recipe)
        XCTAssertNotEqual(bytes(lipped), bytes(plain), "미리보기에 립이 들어간다")
        let plainOriginal = try await painted.renderOriginal(id, at: url, recipe: EditRecipe(), maxDimension: nil)
        let lippedOriginal = try await painted.renderOriginal(id, at: url, recipe: recipe, maxDimension: nil)
        XCTAssertNotEqual(try Support.bytes(lippedOriginal), try Support.bytes(plainOriginal), "저장에도 립이 들어간다")
        let bare = PhotoPipeline(analyzer: StubFaceAnalyzer(result: .success([synthetic.face])), tuning: RenderTuning())
        _ = try await bare.prepare(id, at: url)
        let skipped = try await bare.preview(id, recipe: recipe)
        XCTAssertEqual(bytes(skipped), bytes(plain), "카탈로그가 없으면 립만 건너뛰고 오류를 던지지 않는다")
    }

    func testGenderEstimatesAreThresholdedAndFailuresAreSilent() async throws {
        let tuning = RenderTuning()
        let big = FaceGeometry(boundingBox: NormalizedRect(x: 0.1, y: 0.2, width: 0.3, height: 0.4), yaw: 0.1)
        let small = FaceGeometry(boundingBox: NormalizedRect(x: 0.5, y: 0.2, width: 0.03, height: 0.04))
        let turned = FaceGeometry(boundingBox: NormalizedRect(x: 0.6, y: 0.2, width: 0.3, height: 0.4), yaw: 0.9)
        let faces = [big, small, turned]
        let estimates: [GenderEstimate?] = [
            GenderEstimate(gender: .female, confidence: 0.9), GenderEstimate(gender: .male, confidence: 0.99),
            GenderEstimate(gender: .male, confidence: 0.95),
        ]
        let accepted = PhotoPipeline.acceptedEstimates(estimates, faces: faces, tuning: tuning)
        XCTAssertEqual(accepted.map { $0?.gender }, [.female, nil, nil], "작은 얼굴·돌아간 얼굴은 버린다")
        let weak: [GenderEstimate?] = [GenderEstimate(gender: .female, confidence: 0.6), nil, nil]
        XCTAssertEqual(PhotoPipeline.acceptedEstimates(weak, faces: faces, tuning: tuning), [nil, nil, nil])
        XCTAssertEqual(
            PhotoPipeline.acceptedEstimates(
                [GenderEstimate(gender: .female, confidence: 1)], faces: faces, tuning: tuning),
            [nil, nil, nil], "길이가 다르면 모두 버린다")
        let url = try Support.writePNG(Support.skinTexture(size: 256), name: "genders")
        let pipeline = PhotoPipeline(
            analyzer: StubFaceAnalyzer(result: .success(faces)),
            genderEstimator: StubGenderEstimator(result: .success(estimates)), tuning: tuning)
        let id = PhotoID()
        let prepared = try await pipeline.prepare(id, at: url)
        XCTAssertEqual(prepared.genders, [.female, nil, nil])
        let analysis = await pipeline.preparedAnalysis(id)
        XCTAssertEqual(analysis?.genderEstimates.map { $0?.gender }, [.female, nil, nil])
        let failing = PhotoPipeline(
            analyzer: StubFaceAnalyzer(result: .success(faces)),
            genderEstimator: StubGenderEstimator(result: .failure(.faceAnalysisUnavailable(reason: "stub"))),
            tuning: tuning)
        let silent = try await failing.prepare(PhotoID(), at: url)
        XCTAssertEqual(silent.genders, [nil, nil, nil], "추정 실패는 준비를 막지 않는다")
        XCTAssertNil(silent.faceAnalysisFailure)
        let none = PhotoPipeline(analyzer: StubFaceAnalyzer(result: .success(faces)), tuning: tuning)
        let unestimated = try await none.prepare(PhotoID(), at: url)
        XCTAssertEqual(unestimated.genders, [nil, nil, nil], "추정기가 없으면 모두 미지정")
    }

    func testEstimatedGenderSelectsGroupLayerUnlessManuallyAssigned() {
        let left = FaceGeometry(boundingBox: NormalizedRect(x: 0.05, y: 0.1, width: 0.35, height: 0.8))
        let right = FaceGeometry(boundingBox: NormalizedRect(x: 0.6, y: 0.1, width: 0.35, height: 0.8))
        var recipe = EditRecipe()
        recipe.people.groups[.female] = PortraitLayer(skinSmoothing: 0.5)
        recipe.people.groups[.male] = PortraitLayer(skinSmoothing: 0.1)
        recipe.people.individuals = [PersonRecord(anchor: PersonAnchor(faceBox: right.boundingBox), gender: .male)]
        let analysis = PhotoAnalysis(
            faces: [left, right],
            genderEstimates: [
                GenderEstimate(gender: .female, confidence: 0.9), GenderEstimate(gender: .female, confidence: 0.9),
            ])
        let context = RenderContext(
            extent: CGRect(x: 0, y: 0, width: 64, height: 64), recipe: recipe, analysis: analysis,
            tuning: RenderTuning())
        XCTAssertEqual(context.faceTargets[0].gender, .female, "추정만 있는 얼굴은 추정 성별")
        XCTAssertEqual(context.faceTargets[0].portrait.skin.smoothing, 0.5)
        XCTAssertEqual(context.faceTargets[1].gender, .male, "수동 지정이 추정을 이긴다")
        XCTAssertEqual(context.faceTargets[1].portrait.skin.smoothing, 0.1)
    }
}
