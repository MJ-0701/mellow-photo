import XCTest
import CoreImage
import MellowCore
@testable import MellowPhotoIOS

final class MobileStoreTests: XCTestCase {
    @MainActor private func makeStore(_ directory: URL) -> MobileStore {
        let store = MobileStore(root: directory)
        store.restoring = false; store.ready = true
        return store
    }
    @MainActor func testSessionPersistsRecipeAndUndoAcrossRestart() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = makeStore(root)
        let photo = MobilePhoto(id: UUID(), filename: "test.png", name: "시험")
        store.photos = [photo]; store.selectedID = photo.id
        store.change(\.exposure, 0.4)
        store.stopWork()
        let restored = makeStore(root)
        XCTAssertEqual(restored.recipe.adjustments.exposure, 0.4)
        XCTAssertTrue(restored.canUndo)
        restored.undo(); restored.stopWork()
        XCTAssertEqual(restored.recipe.adjustments.exposure, 0)
        XCTAssertTrue(restored.canRedo)
        let again = makeStore(root)
        XCTAssertTrue(again.canRedo)
        again.redo(); again.stopWork()
        XCTAssertEqual(again.recipe.adjustments.exposure, 0.4)
    }
    @MainActor func testManualRetouchLocksGeometryAcrossPresetAndBatch() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = makeStore(root)
        var first = MobilePhoto(id: UUID(), filename: "first.png", name: "1")
        first.recipe.adjustments.faceSlim = 0.2
        first.recipe.operations = [.spot(RetouchSpot(x: 0.5, y: 0.4, sourceX: 0.4, sourceY: 0.4, radius: 0.02))]
        first.recipe.selectedFace = 1
        let second = MobilePhoto(id: UUID(), filename: "second.png", name: "2")
        store.photos = [first, second]; store.selectedID = first.id
        store.change(\.faceSlim, 0.9); store.setFace(nil)
        XCTAssertEqual(store.recipe.adjustments.faceSlim, 0.2)
        XCTAssertEqual(store.recipe.selectedFace, 1)
        var preset = Adjustments(); preset.faceSlim = 0.7; preset.exposure = 0.5
        store.apply(preset); store.stopWork()
        XCTAssertEqual(store.recipe.adjustments.faceSlim, 0.2)
        XCTAssertEqual(store.recipe.adjustments.exposure, 0.5)
        store.selectedID = second.id; store.apply(preset); store.stopWork(); store.applyAll()
        XCTAssertEqual(store.photos[0].recipe.adjustments.faceSlim, 0.2)
        XCTAssertEqual(store.photos[0].recipe.selectedFace, 1)
        XCTAssertEqual(store.photos[0].recipe.operations.count, 1)
    }
    @MainActor func testRemoveOnlyDeletesWorkingCopy() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let original = root.deletingLastPathComponent().appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root); try? FileManager.default.removeItem(at: original) }
        let data = Data([1, 2, 3])
        try data.write(to: original)
        let store = makeStore(root)
        let photo = MobilePhoto(id: UUID(), filename: "working.png", name: "1")
        try data.write(to: store.url(photo))
        store.photos = [photo]; store.selectedID = photo.id
        store.removeSelected()
        XCTAssertTrue(store.photos.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.url(photo).path))
        XCTAssertEqual(try Data(contentsOf: original), data)
        let restored = makeStore(root)
        XCTAssertTrue(restored.photos.isEmpty)
    }
    func testPortraitEngineOnIOS() throws {
        let engine = ImageEngine()
        let image = CIImage(color: CIColor(red: 0.5, green: 0.4, blue: 0.3)).cropped(to: CGRect(x: 0, y: 0, width: 256, height: 256))
        var recipe = EditRecipe(); recipe.adjustments.skin = 0.5; recipe.adjustments.faceSlim = 0.5
        recipe.operations = [.warp(WarpStroke(x: 0.5, y: 0.4, dx: 0.01, dy: 0.01, radius: 0.15))]
        let output = try engine.render(image, recipe: recipe, faces: [FaceRegion(rect: CGRect(x: 0.2, y: 0.2, width: 0.6, height: 0.6))])
        let cg = try engine.cgImage(output)
        XCTAssertEqual(cg.width, 256); XCTAssertEqual(cg.height, 256)
    }
}
