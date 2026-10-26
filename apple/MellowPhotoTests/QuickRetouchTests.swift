import CoreImage
import Foundation
import MellowEditing
import MellowLibrary
import MellowRendering
import MellowShared
import XCTest

@testable import Mellow_Photo

/// 분석만 멈추며 메인 스레드는 차단하지 않는다. 가져오기가 끝난 뒤 다음 분석을 제어한다.
private final class ControlledFaceAnalyzer: FaceAnalyzer, @unchecked Sendable {
    private let condition = NSCondition()
    private var blocked = false
    private var blockedCall = 0
    private var entered = false
    private var callCount = 0
    var results = AnalysisResultQueue<[FaceGeometry]>([.success([])])

    var calls: Int {
        condition.lock()
        defer { condition.unlock() }
        return callCount
    }

    var isWaiting: Bool {
        condition.lock()
        defer { condition.unlock() }
        return entered
    }

    func blockNext(offset: Int = 1) {
        condition.lock()
        blocked = true
        blockedCall = callCount + offset
        entered = false
        condition.unlock()
    }

    func release() {
        condition.lock()
        blocked = false
        condition.broadcast()
        condition.unlock()
    }

    func analyze(_ image: CIImage) throws -> [FaceGeometry] {
        condition.lock()
        callCount += 1
        if blocked && callCount == blockedCall {
            entered = true
            condition.broadcast()
            while blocked { condition.wait() }
        }
        condition.unlock()
        return try results.next().get()
    }
}

@MainActor
final class QuickRetouchTests: XCTestCase {
    private var root: URL!

    override func setUp() async throws { root = try TestSupport.temporaryDirectory() }
    override func tearDown() async throws { try? FileManager.default.removeItem(at: root) }

    private func imported(analyzer: any FaceAnalyzer = StubFaceAnalyzer(), count: Int = 1) async throws -> AppModel {
        let urls = try (0..<count).map { try TestSupport.solidPNG(in: root, name: "photo-\($0)") }
        let model = TestSupport.makeModel(
            root: root, analyzer: analyzer, importer: FakeImporter(passesThroughFileURLs: true))
        await model.importFromFiles(urls)
        try await waitUntil { model.isReady && !model.isRendering }
        return model
    }

    func testDefaultPanelAndUnavailableActions() async throws {
        let model = try await imported()
        XCTAssertEqual(model.tool, .quick)
        XCTAssertNotNil(model.quickUnavailableReason(.portrait))
        XCTAssertNotNil(model.quickUnavailableReason(.background))
        XCTAssertNil(model.quickUnavailableReason(.automatic))
        await model.applyQuickAction(.portrait)
        XCTAssertTrue(model.currentRecipe.isDefault)
        model.stopWork()
    }

    func testNightIsAtomicIdempotentAndPreservesOtherEdits() async throws {
        let model = try await imported()
        model.edit(.exposure(0.3))
        let before = model.currentRecipe
        let undoCount = model.session.selected!.document.undoStack.count
        await model.applyQuickAction(.night)
        XCTAssertEqual(model.currentRecipe.color, before.color)
        XCTAssertEqual(model.currentRecipe.geometry, before.geometry)
        XCTAssertEqual(model.currentRecipe.look, LookSelection(id: "night", intensity: 0.6))
        XCTAssertEqual(model.session.selected!.document.undoStack.count, undoCount + 1)
        await model.applyQuickAction(.night)
        XCTAssertEqual(model.session.selected!.document.undoStack.count, undoCount + 1)
        model.undo()
        XCTAssertEqual(model.currentRecipe, before)
        model.redo()
        XCTAssertEqual(model.currentRecipe.look.id, "night")
        model.stopWork()
    }

    func testBrightenKeepsHigherExposureAndOtherValues() async throws {
        let model = try await imported()
        model.edit(.exposure(2))
        model.edit(.saturation(0.7))
        let before = model.currentRecipe
        let count = model.session.selected!.document.undoStack.count
        await model.applyQuickAction(.brighten)
        XCTAssertEqual(model.currentRecipe, before)
        XCTAssertEqual(model.session.selected!.document.undoStack.count, count)
        XCTAssertEqual(model.statusMessage, UserMessage.quickBrightenUnchanged)
        model.stopWork()
    }

    func testBatchUsesEachPhotosFacesAndOneCheckpointThenRestores() async throws {
        let analyzer = ControlledFaceAnalyzer()
        let model = try await imported(analyzer: analyzer, count: 2)
        let face = TestSupport.landmarkedFace(in: NormalizedRect(x: 0.2, y: 0.2, width: 0.6, height: 0.6))
        analyzer.results = AnalysisResultQueue([.success([face]), .success([])])
        let ids = model.session.photos.map(\.id)
        await model.autoEnhanceAll()
        XCTAssertEqual(model.quickRetouchProgress?.changed, 2)
        XCTAssertEqual(model.quickRetouchProgress?.processed, 2)
        XCTAssertEqual(model.session.photos[0].document.recipe.portrait.oneTouch, 0.6)
        XCTAssertNil(model.session.photos[1].document.recipe.portrait.oneTouch)
        XCTAssertEqual(model.session.photos.map { $0.document.undoStack.count }, [1, 1])
        XCTAssertEqual(model.session.photos.map(\.id), ids)
        model.undo()
        XCTAssertTrue(model.currentRecipe.isDefault)
        model.stopWork()
    }

    func testReanalysisFailureRefreshesAvailabilityAndDoesNotEdit() async throws {
        let analyzer = ControlledFaceAnalyzer()
        let face = TestSupport.landmarkedFace(in: NormalizedRect(x: 0.2, y: 0.2, width: 0.6, height: 0.6))
        analyzer.results = AnalysisResultQueue([.success([face])])
        let model = try await imported(analyzer: analyzer)
        XCTAssertNil(model.quickUnavailableReason(.portrait))
        analyzer.results = AnalysisResultQueue([.failure(.faceAnalysisUnavailable(reason: "test"))])
        let before = model.session.selected!.document
        await model.autoEnhance()
        XCTAssertEqual(model.session.selected!.document, before)
        XCTAssertNotNil(model.quickUnavailableReason(.portrait))
        XCTAssertEqual(model.quickRetouchProgress?.failed, 1)
        XCTAssertNotNil(model.selectedInfo?.faceAnalysisFailure)
        model.stopWork()
    }

    func testCancelRestartCancelDrainsOnlyStartedPhotoAndKeepsUnprocessed() async throws {
        let analyzer = ControlledFaceAnalyzer()
        let model = try await imported(analyzer: analyzer, count: 3)
        let before = model.session.photos.map(\.document)
        let calls = analyzer.calls
        analyzer.blockNext()
        defer { analyzer.release() }
        let work = Task { await model.autoEnhanceAll() }
        try await waitUntil { analyzer.isWaiting }
        model.cancelQuickRetouch()
        await model.autoEnhanceAll()
        model.cancelQuickRetouch()
        XCTAssertTrue(model.isQuickRetouching, "이미 시작한 분석이 끝날 때까지 새 요청을 받지 않는다")
        XCTAssertEqual(analyzer.calls, calls + 1)
        analyzer.release()
        await work.value
        XCTAssertFalse(model.isQuickRetouching)
        XCTAssertEqual(analyzer.calls, calls + 1)
        XCTAssertEqual(model.session.photos.map(\.document), before)
        XCTAssertEqual(model.quickRetouchProgress?.processed, 0)
        XCTAssertEqual(model.quickRetouchProgress?.cancelled, true)
        model.stopWork()
    }

    func testManualEditAndBackgroundStopPreventLateResult() async throws {
        let analyzer = ControlledFaceAnalyzer()
        let model = try await imported(analyzer: analyzer)
        analyzer.blockNext()
        defer { analyzer.release() }
        let work = Task { await model.autoEnhance() }
        try await waitUntil { analyzer.isWaiting }
        model.edit(.exposure(0.45))
        let edited = model.currentRecipe
        model.stopWork()
        analyzer.release()
        await work.value
        XCTAssertEqual(model.currentRecipe, edited)
        XCTAssertEqual(model.quickRetouchProgress?.changed, 0)
        XCTAssertTrue(model.quickRetouchProgress!.cancelled)
    }
    func testDifferentOriginalBrightnessAndPartialFailure() async throws {
        let analyzer = ControlledFaceAnalyzer()
        let dark = try TestSupport.solidPNG(in: root, name: "dark", color: CIColor(red: 0.04, green: 0.04, blue: 0.04))
        let bright = try TestSupport.solidPNG(in: root, name: "bright", color: CIColor(red: 0.8, green: 0.8, blue: 0.8))
        let failed = try TestSupport.solidPNG(in: root, name: "failed")
        let model = TestSupport.makeModel(
            root: root, analyzer: analyzer, importer: FakeImporter(passesThroughFileURLs: true))
        await model.importFromFiles([dark, bright, failed])
        try await waitUntil { model.isReady && !model.isRendering }
        analyzer.results = AnalysisResultQueue([
            .success([]), .success([]), .failure(.faceAnalysisUnavailable(reason: "test")),
        ])
        await model.autoEnhanceAll()
        XCTAssertNotEqual(
            model.session.photos[0].document.recipe.color.exposure,
            model.session.photos[1].document.recipe.color.exposure)
        XCTAssertEqual(model.quickRetouchProgress?.changed, 2)
        XCTAssertEqual(model.quickRetouchProgress?.failed, 1)
        XCTAssertEqual(model.quickRetouchProgress?.processed, 3)
        XCTAssertTrue(model.session.photos[2].document.recipe.isDefault)
        XCTAssertEqual(model.session.photos[2].document.undoStack.count, 0)
        model.stopWork()
    }

    func testPartialCancellationPreservesCompletedAndDoesNotStartRemaining() async throws {
        let analyzer = ControlledFaceAnalyzer()
        let model = try await imported(analyzer: analyzer, count: 3)
        let before = model.session.photos.map(\.document)
        analyzer.blockNext(offset: 2)
        defer { analyzer.release() }
        let work = Task { await model.autoEnhanceAll() }
        try await waitUntil { analyzer.isWaiting }
        XCTAssertEqual(model.quickRetouchProgress?.changed, 1)
        model.cancelQuickRetouch()
        analyzer.release()
        await work.value
        XCTAssertNotEqual(model.session.photos[0].document, before[0])
        XCTAssertEqual(Array(model.session.photos.dropFirst().map(\.document)), Array(before.dropFirst()))
        XCTAssertEqual(model.quickRetouchProgress?.processed, 1)
        model.stopWork()
    }

    func testSelectionABARejectsLateResult() async throws {
        let analyzer = ControlledFaceAnalyzer()
        let model = try await imported(analyzer: analyzer, count: 2)
        let ids = model.session.photos.map(\.id)
        let before = model.session.photos.map(\.document)
        analyzer.blockNext()
        defer { analyzer.release() }
        let work = Task { await model.autoEnhance() }
        try await waitUntil { analyzer.isWaiting }
        model.select(ids[1])
        model.select(ids[0])
        analyzer.release()
        await work.value
        try await waitUntil { model.isReady }
        XCTAssertEqual(model.session.photos.map(\.document), before)
        XCTAssertEqual(model.quickRetouchProgress?.cancelled, true)
        model.stopWork()
    }

    func testBatchPreservesGeometryBrushShapesPeopleAndPersistedHistory() async throws {
        let store = MemorySessionStore()
        let face = TestSupport.landmarkedFace(in: NormalizedRect(x: 0.2, y: 0.2, width: 0.6, height: 0.6))
        let urls = try (0..<2).map { try TestSupport.solidPNG(in: root, name: "preserve-\($0)") }
        let model = TestSupport.makeModel(
            root: root, analyzer: StubFaceAnalyzer(result: .success([face])),
            importer: FakeImporter(passesThroughFileURLs: true), store: store)
        await model.importFromFiles(urls)
        try await waitUntil { model.isReady && !model.isRendering }
        for entry in model.session.photos {
            model.session.edit(entry.id) { document in
                _ = document.set(.crop(NormalizedRect(x: 0.1, y: 0.1, width: 0.8, height: 0.8)))
                _ = document.set(.faceShape(.width, -0.2))
                _ = document.set(.skinSmoothing(0.83), forFace: 0, of: [face.boundingBox])
                _ = document.appendLocalEdit(.warp(WarpStroke(x: 0.5, y: 0.5, dx: 0.01, dy: 0, radius: 0.1)))
                return nil
            }
        }
        let before = model.session.photos.map(\.document)
        await model.autoEnhanceAll()
        let after = model.session.photos.map(\.document)
        for index in 0..<2 {
            XCTAssertEqual(after[index].recipe.geometry, before[index].recipe.geometry)
            XCTAssertEqual(after[index].recipe.operations, before[index].recipe.operations)
            XCTAssertEqual(after[index].recipe.portrait.face, before[index].recipe.portrait.face)
            XCTAssertEqual(after[index].recipe.people.individuals, before[index].recipe.people.individuals)
            XCTAssertEqual(after[index].undoStack.count, before[index].undoStack.count + 1)
            var copy = after[index]
            copy.undo()
            XCTAssertEqual(copy.recipe, before[index].recipe)
            copy.redo()
            XCTAssertEqual(copy.recipe, after[index].recipe)
        }
        let reopened = ProjectSession(store: store, maxPhotos: 40)
        try reopened.restore()
        XCTAssertEqual(reopened.photos.map(\.document), after)
        model.stopWork()
    }

    func testPortraitQuickActionUsesAllFacesAndKeepsIndividualOverride() async throws {
        let face = TestSupport.landmarkedFace(in: NormalizedRect(x: 0.2, y: 0.2, width: 0.6, height: 0.6))
        let model = try await imported(analyzer: StubFaceAnalyzer(result: .success([face])))
        model.setBeautyTarget(.face(0))
        model.edit(.skinSmoothing(0.83))
        let people = model.currentRecipe.people.individuals
        let steps = model.session.selected!.document.undoStack.count
        await model.applyQuickAction(.portrait)
        XCTAssertEqual(model.currentRecipe.portrait.oneTouch, 0.6)
        XCTAssertEqual(model.currentRecipe.people.individuals, people)
        XCTAssertEqual(model.session.selected!.document.undoStack.count, steps + 1)
        await model.applyQuickAction(.portrait)
        XCTAssertEqual(model.session.selected!.document.undoStack.count, steps + 1)
        model.stopWork()
    }

    func testBackgroundQuickActionReplacesStrengthOnce() async throws {
        let staged = try TestSupport.solidPNG(in: root)
        let mask = CIImage(color: .white).cropped(to: CGRect(x: 0, y: 0, width: 128, height: 128))
        let model = TestSupport.makeModel(
            root: root, personAnalyzer: StubPersonAnalyzer(result: .success(mask)),
            importer: FakeImporter(passesThroughFileURLs: true))
        await model.importFromFiles([staged])
        try await waitUntil { model.isReady && !model.isRendering }
        XCTAssertNil(model.quickUnavailableReason(.background))
        model.edit(.backgroundBlur(0.8))
        let steps = model.session.selected!.document.undoStack.count
        await model.applyQuickAction(.background)
        XCTAssertEqual(model.currentRecipe.background.blur, 0.35)
        await model.applyQuickAction(.background)
        XCTAssertEqual(model.session.selected!.document.undoStack.count, steps + 1)
        model.undo()
        XCTAssertEqual(model.currentRecipe.background.blur, 0.8)
        model.stopWork()
    }

}
