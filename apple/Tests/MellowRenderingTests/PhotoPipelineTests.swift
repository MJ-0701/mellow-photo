import CoreImage
import MellowShared
import XCTest

@testable import MellowRendering

struct StubFaceAnalyzer: FaceAnalyzer {
    var result: Result<[FaceGeometry], MellowError>
    func analyze(_ image: CIImage) throws -> [FaceGeometry] { try result.get() }
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
        recipe.portrait.skinSmoothing = 0.3
        do {
            _ = try await pipeline.renderOriginal(id, at: url, recipe: recipe, maxDimension: nil)
            XCTFail("얼굴 보정이 조용히 빠지면 안 된다")
        } catch {
            XCTAssertEqual(error as? MellowError, .faceAnalysisUnavailable(reason: "test"))
        }
        recipe.portrait.skinSmoothing = 0
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
        recipe.portrait.skinSmoothing = 0.3
        recipe.color.exposure = 0.2
        let rendered = try await pipeline.renderOriginal(id, at: url, recipe: recipe, maxDimension: 128)
        XCTAssertEqual(rendered.extent.size, CGSize(width: 128, height: 128), "분석은 성공했고 얼굴만 없으면 색감만 적용해 저장한다")
    }

    func testRenderOriginalOfUnpreparedPhotoRefusesFaceEditsButAllowsColor() async throws {
        let url = try writeSolidPNG()
        let id = PhotoID()
        let pipeline = PhotoPipeline(analyzer: StubFaceAnalyzer(result: .success([])), tuning: RenderTuning())
        var faceRecipe = EditRecipe()
        faceRecipe.portrait.skinSmoothing = 0.3
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
}
