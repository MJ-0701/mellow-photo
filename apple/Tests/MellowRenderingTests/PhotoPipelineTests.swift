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
        let unprepared = try await failing.renderOriginal(PhotoID(), at: url, recipe: shaped, maxDimension: nil)
        XCTAssertEqual(unprepared.extent.size, CGSize(width: 256, height: 192), "준비 전 사진도 체형 때문에 저장을 막지 않는다")
    }
}
