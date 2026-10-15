import ImageIO
import MellowExport
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
    private var root: URL!

    override func setUp() async throws {
        root = try TestSupport.temporaryDirectory()
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: root)
    }

    private func waitUntil(_ condition: @escaping () -> Bool, timeout: TimeInterval = 10) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() && Date() < deadline {
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        XCTAssertTrue(condition())
    }

    /// 가져오기는 받은 파일을 옮기므로 공용 픽스처를 임시 폴더에 복사해서 넘긴다.
    private func demoPortraitCopy() throws -> URL {
        let fixture = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("shared/fixtures/demo-portrait.png")
        let copy = root.appendingPathComponent("demo-portrait.png")
        try FileManager.default.copyItem(at: fixture, to: copy)
        return copy
    }

    func testLookAutoAdjustCropRotateExportProducesSquareImage() async throws {
        let staged = try demoPortraitCopy()
        let model = TestSupport.makeModel(root: root, importer: FakeImporter(passesThroughFileURLs: true))
        await model.importFromFiles([staged])
        try await waitUntil { model.isReady && model.preview != nil }

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
        model.edit(.quarterTurns(model.currentRecipe.geometry.quarterTurns + 1))
        model.selectTool(.adjust)
        try await waitUntil { !model.isRendering }

        let recipe = model.currentRecipe
        XCTAssertEqual(recipe.look.id, "film")
        XCTAssertEqual(recipe.look.intensity, 0.5, accuracy: 1e-9)
        XCTAssertEqual(recipe.detail.highlights, -0.5, accuracy: 1e-9)
        XCTAssertEqual(recipe.geometry.straightenDegrees, 5, accuracy: 1e-9)
        XCTAssertEqual(recipe.geometry.quarterTurns, 1)
        XCTAssertEqual(model.cropAspect, .square)
        let crop = try XCTUnwrap(recipe.geometry.crop)
        let size = try XCTUnwrap(model.selectedInfo?.pixelSize)
        let turnedAspect = Double(size.height / size.width)
        XCTAssertEqual(turnedAspect * crop.width / crop.height, 1, accuracy: 1e-6, "자른 영역은 픽셀 기준 정사각형")

        let output = root.appendingPathComponent("out")
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
        XCTAssertEqual(width, height, "저장 파일이 정사각형이다")
    }
}
