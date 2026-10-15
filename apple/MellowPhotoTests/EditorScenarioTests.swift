import CoreImage
import ImageIO
import MellowExport
import MellowRendering
import MellowShared
import XCTest

@testable import Mellow_Photo

/// 받은 파일을 임시 폴더에 그대로 복사한다. 저장 결과의 픽셀 크기를 읽기 위한 대상.
final class CopyingDestination: ExportDestination, @unchecked Sendable {
    let folder: URL
    var savedURLs: [URL] = []

    init(folder: URL) {
        self.folder = folder
    }

    func publish(fileURL: URL, suggestedName: String) async throws {
        let target = folder.appendingPathComponent(suggestedName).appendingPathExtension(fileURL.pathExtension)
        try FileManager.default.copyItem(at: fileURL, to: target)
        savedURLs.append(target)
    }
}

/// 화면 없이 AppModel로 편집 한 바퀴(필터 → 자동 → 조정 → 자르기 → 저장)를 돈다.
@MainActor
final class EditorScenarioTests: XCTestCase {
    /// 가로로 긴 사진 시나리오용. 공용 픽스처(1254×1254)의 아래쪽을 3:2로 잘라 쓴다.
    private static let wideSize = CGSize(width: 1254, height: 836)

    private var root: URL!

    override func setUp() async throws {
        root = try TestSupport.temporaryDirectory()
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: root)
    }

    private var demoPortraitURL: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("shared/fixtures/demo-portrait.png")
    }

    /// 가져오기는 받은 파일을 옮기므로 공용 픽스처를 임시 폴더에 복사해서 넘긴다.
    private func demoPortraitCopy() throws -> URL {
        let copy = root.appendingPathComponent("demo-portrait.png")
        try FileManager.default.copyItem(at: demoPortraitURL, to: copy)
        return copy
    }

    /// 공용 픽스처를 3:2로 잘라 임시 폴더에 PNG로 쓴다.
    private func widePortraitCopy() throws -> URL {
        let source = try XCTUnwrap(CIImage(contentsOf: demoPortraitURL))
        let cropped = source.cropped(to: CGRect(origin: .zero, size: Self.wideSize))
        let image = try Renderer().makeCGImage(cropped)
        let url = root.appendingPathComponent("demo-wide.png")
        let destination = try XCTUnwrap(
            CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, nil)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        return url
    }

    private func importedModel(_ staged: URL) async throws -> AppModel {
        let model = TestSupport.makeModel(root: root, importer: FakeImporter(passesThroughFileURLs: true))
        await model.importFromFiles([staged])
        try await waitUntil { model.isReady && model.preview != nil }
        return model
    }

    /// 자른 영역의 픽셀 가로/세로.
    private func outputAspect(_ model: AppModel) throws -> Double {
        let size = try XCTUnwrap(model.selectedInfo?.pixelSize)
        let transform = GeometryTransform(
            geometry: model.currentRecipe.geometry, sourceAspect: Double(size.width / size.height))
        return transform.outputAspect
    }

    /// 현재 사진을 저장하고 저장 파일의 픽셀 크기를 돌려준다.
    private func exportedPixelSize(_ model: AppModel) async throws -> (width: Int, height: Int) {
        let output = root.appendingPathComponent("out-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let destination = CopyingDestination(folder: output)
        model.export(all: false, to: destination)
        try await waitUntil({ !model.isExporting }, timeout: 30)
        XCTAssertEqual(model.lastExportSavedCount, 1)
        let saved = try XCTUnwrap(destination.savedURLs.first)
        let source = try XCTUnwrap(CGImageSourceCreateWithURL(saved as CFURL, nil))
        let properties = try XCTUnwrap(CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any])
        let width = try XCTUnwrap(properties[kCGImagePropertyPixelWidth] as? Int)
        let height = try XCTUnwrap(properties[kCGImagePropertyPixelHeight] as? Int)
        XCTAssertGreaterThan(width, 0)
        return (width, height)
    }

    func testLookAutoAdjustCropRotateExportProducesSquareImage() async throws {
        let model = try await importedModel(demoPortraitCopy())

        model.selectTool(.look)
        model.edit(.lookID("film"))
        model.beginSliderEdit()
        model.edit(.lookIntensity(0.5))
        model.endSliderEdit()
        let beforeAuto = model.currentRecipe
        await model.autoEnhance()
        XCTAssertNotEqual(model.currentRecipe, beforeAuto, "자동 보정이 레시피를 바꿨다")
        XCTAssertEqual(model.statusMessage, UserMessage.autoEnhanced)
        model.selectTool(.adjust)
        model.beginSliderEdit()
        model.edit(.highlights(-0.5))
        model.endSliderEdit()
        model.selectTool(.crop)
        model.setCropAspect(.square)
        model.beginSliderEdit()
        model.edit(.straightenDegrees(5))
        model.endSliderEdit()
        model.turnClockwise()
        model.selectTool(.adjust)
        try await waitUntil { !model.isRendering }

        let recipe = model.currentRecipe
        XCTAssertEqual(recipe.look.id, "film")
        XCTAssertEqual(recipe.look.intensity, 0.5, accuracy: 1e-9)
        XCTAssertEqual(recipe.detail.highlights, -0.5, accuracy: 1e-9)
        XCTAssertEqual(recipe.geometry.straightenDegrees, 5, accuracy: 1e-9)
        XCTAssertEqual(recipe.geometry.quarterTurns, 1)
        XCTAssertEqual(model.cropAspect, .square)
        XCTAssertNotNil(recipe.geometry.crop)
        XCTAssertEqual(try outputAspect(model), 1, accuracy: 1e-6, "자른 영역은 픽셀 기준 정사각형")
        let size = try await exportedPixelSize(model)
        XCTAssertEqual(size.width, size.height, "저장 파일이 정사각형이다")
    }

    func testWidePhotoSquareCropThenTurnExportsSquare() async throws {
        let model = try await importedModel(widePortraitCopy())
        model.selectTool(.crop)
        model.setCropAspect(.square)
        model.turnClockwise()
        model.selectTool(.adjust)
        XCTAssertEqual(try outputAspect(model), 1, accuracy: 1e-6, "회전해도 자른 영역은 정사각형으로 남는다")
        let size = try await exportedPixelSize(model)
        XCTAssertEqual(size.width, size.height, "저장 파일이 정사각형이다")
    }

    func testWidePhotoSquareCropThenFlipKeepsSamePixelsFramed() async throws {
        let model = try await importedModel(widePortraitCopy())
        model.selectTool(.crop)
        model.setCropAspect(.square)
        let centered = try XCTUnwrap(model.currentRecipe.geometry.crop)
        // 정사각형을 왼쪽 끝으로 옮겨 두면 반전 뒤 오른쪽 끝으로 가야 같은 픽셀이 보인다.
        model.edit(.crop(NormalizedRect(x: 0, y: centered.y, width: centered.width, height: centered.height)))
        model.edit(.flipHorizontal(true))
        model.selectTool(.adjust)
        let crop = try XCTUnwrap(model.currentRecipe.geometry.crop)
        XCTAssertEqual(crop.x, 1 - centered.width, accuracy: 1e-9, "자르기 영역이 이미지와 함께 반전된다")
        XCTAssertEqual(try outputAspect(model), 1, accuracy: 1e-6)
        let size = try await exportedPixelSize(model)
        XCTAssertEqual(size.width, size.height, "저장 파일이 정사각형이다")
    }

    /// 공용 픽스처의 얼굴 위치를 어림한 스텁 얼굴. 얼굴형이 동작하도록 상자 비율로 놓은 가짜 특징점을 단다.
    private static let demoFace = TestSupport.landmarkedFace(
        in: NormalizedRect(x: 0.33, y: 0.36, width: 0.38, height: 0.4))

    /// 공용 픽스처에서 사람이 있는 영역을 어림한 스텁 인물 마스크. 얼굴과 어깨를 덮는다.
    private static let demoPersonMask = TestSupport.personMask(NormalizedRect(x: 0.2, y: 0, width: 0.65, height: 0.85))

    private func previewBytes(_ model: AppModel) -> [UInt8] {
        model.preview.map { Array($0.dataProvider!.data! as Data) } ?? []
    }

    func testBeautySkinFaceFeaturesThenBackgroundThenExportSucceeds() async throws {
        let model = TestSupport.makeModel(
            root: root, analyzer: StubFaceAnalyzer(result: .success([Self.demoFace])),
            personAnalyzer: StubPersonAnalyzer(result: .success(Self.demoPersonMask)),
            importer: FakeImporter(passesThroughFileURLs: true))
        await model.importFromFiles([try demoPortraitCopy()])
        try await waitUntil { model.isReady && model.preview != nil }
        let plain = previewBytes(model)

        model.selectTool(.beauty)
        model.beginSliderEdit()
        model.edit(.skinSmoothing(0.5))
        model.endSliderEdit()
        model.edit(.autoBlemish(true))
        try await waitUntil { !model.isRendering && self.previewBytes(model) != plain }
        let skinned = previewBytes(model)

        model.beautyTab = .face
        let faceEdits: [(FaceShapeKey, Double)] = [(.width, -0.5), (.eyeSize, 0.3), (.smile, 0.4)]
        for (key, value) in faceEdits {
            model.beginSliderEdit()
            model.edit(.faceShape(key, value))
            model.endSliderEdit()
        }
        // 얼굴형만 바꿔도 미리보기가 바뀌어야 한다(바뀌지 않으면 시간 초과로 실패).
        try await waitUntil { !model.isRendering && self.previewBytes(model) != skinned }

        model.beautyTab = .features
        model.beginSliderEdit()
        model.edit(.feature(.eyeBrighten, 0.5))
        model.endSliderEdit()
        try await waitUntil { !model.isRendering }
        let featured = previewBytes(model)

        model.selectTool(.background)
        XCTAssertEqual(model.backgroundAvailability, .ready)
        model.beginSliderEdit()
        model.edit(.backgroundBlur(0.5))
        model.endSliderEdit()
        // 배경 흐림만 바꿔도 미리보기가 바뀌어야 한다.
        try await waitUntil { !model.isRendering && self.previewBytes(model) != featured }

        let recipe = model.currentRecipe
        XCTAssertEqual(recipe.portrait.skin, SkinAdjustments(smoothing: 0.5, autoBlemish: true))
        XCTAssertEqual(recipe.portrait.face, FaceShapeAdjustments(width: -0.5, eyeSize: 0.3, smile: 0.4))
        XCTAssertEqual(recipe.portrait.features, FeatureAdjustments(eyeBrighten: 0.5))
        XCTAssertEqual(recipe.background.blur, 0.5, accuracy: 1e-9)
        let size = try await exportedPixelSize(model)
        XCTAssertEqual(size.width, size.height, "정사각형 원본이 그대로 저장된다")
    }
}
