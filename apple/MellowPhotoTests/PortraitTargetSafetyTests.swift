import MellowEditing
import MellowLibrary
import MellowRendering
import MellowShared
import XCTest

@testable import Mellow_Photo

@MainActor
final class PortraitTargetSafetyTests: XCTestCase {
    func testUnassignedGenderGroupCannotCreateAnInvisibleEdit() async throws {
        let root = try TestSupport.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let file = try TestSupport.solidPNG(in: root)
        let face = TestSupport.landmarkedFace(in: NormalizedRect(x: 0.2, y: 0.2, width: 0.6, height: 0.6))
        let store = MemorySessionStore()
        let model = TestSupport.makeModel(
            root: root, analyzer: StubFaceAnalyzer(result: .success([face])),
            importer: FakeImporter(passesThroughFileURLs: true), store: store)
        defer { model.stopWork() }
        await model.importFromFiles([file])
        try await waitUntil { model.isReady && !model.isRendering }
        for gender in Gender.allCases {
            model.setBeautyTarget(.gender(gender))
            XCTAssertEqual(model.faces.indices.filter { model.effectiveGender(forFace: $0) == gender }.count, 0)
            let before = model.session.selected!.document
            let saves = store.saveCount
            let output = model.preview!.dataProvider!.data! as Data
            model.applyOneTouch()
            try await waitUntil { !model.isRendering }
            XCTAssertEqual(model.preview!.dataProvider!.data! as Data, output, "0명에게 적용한 레이어는 실제 렌더를 바꾸지 않는다")
            print(
                "portrait-target-red group=\(gender.rawValue) targets=0 documentChanged=\(before != model.session.selected!.document) outputIdentical=\(model.preview!.dataProvider!.data! as Data == output)"
            )
            XCTAssertEqual(model.session.selected!.document, before, "대상0명인 원터치는 보이지 않는 편집 이력을 만들지 않아야 한다")
            XCTAssertEqual(store.saveCount, saves, "0명 무효조작은 저장도 하지 않는다")
        }
    }
    private func modelWithUnassignedFace() async throws -> (AppModel, URL, MemorySessionStore) {
        let root = try TestSupport.temporaryDirectory()
        let file = try TestSupport.solidPNG(in: root)
        let face = TestSupport.landmarkedFace(in: NormalizedRect(x: 0.2, y: 0.2, width: 0.6, height: 0.6))
        let store = MemorySessionStore()
        let model = TestSupport.makeModel(
            root: root, analyzer: StubFaceAnalyzer(result: .success([face])),
            importer: FakeImporter(passesThroughFileURLs: true), store: store)
        await model.importFromFiles([file])
        try await waitUntil { model.isReady && !model.isRendering }
        model.setBeautyTarget(.gender(.female))
        return (model, root, store)
    }

    func testEmptyGroupClearWithoutStoredValuesIsAnExactNoOp() async throws {
        let (model, root, store) = try await modelWithUnassignedFace()
        defer {
            model.stopWork()
            try? FileManager.default.removeItem(at: root)
        }
        let before = model.session.selected!.document
        let saves = store.saveCount
        model.applyOneTouch(strength: 0)
        XCTAssertEqual(model.session.selected!.document, before)
        XCTAssertEqual(store.saveCount, saves, "제거할 원터치가 없으면 저장하지 않는다")
        model.applyMakeupLook(id: nil)
        XCTAssertEqual(model.session.selected!.document, before, "없는 메이크업을 끈다고 zero override를 만들지 않는다")
        XCTAssertEqual(store.saveCount, saves)
    }

    func testExistingEmptyGroupClearIsUndoableAndPreservesOtherLayers() async throws {
        let (model, root, _) = try await modelWithUnassignedFace()
        defer {
            model.stopWork()
            try? FileManager.default.removeItem(at: root)
        }
        let id = model.session.selectedPhotoID!
        model.edit(.exposure(0.3))
        model.session.edit(id) { document in
            document.applyOneTouch(strength: 0.6, in: .gender(.female))
        }
        let before = model.session.selected!.document
        model.applyOneTouch(strength: 0)
        XCTAssertNotEqual(model.currentRecipe, before.recipe)
        XCTAssertEqual(model.currentRecipe.color, before.recipe.color)
        XCTAssertEqual(model.currentRecipe.people.individuals, before.recipe.people.individuals)
        XCTAssertEqual(model.session.selected!.document.undoStack.count, before.undoStack.count + 1)
        model.undo()
        XCTAssertEqual(model.currentRecipe, before.recipe)
        model.applyMakeupLook(id: nil)
        XCTAssertEqual(
            model.currentRecipe.people.groups[.female]?.skinSmoothing,
            before.recipe.people.groups[.female]?.skinSmoothing)
        XCTAssertTrue(
            model.currentRecipe.people.groups[.female]?.makeup.values.allSatisfy { $0.intensity == 0 } ?? true)
        model.undo()
        XCTAssertEqual(model.currentRecipe, before.recipe)
    }

    func testScopedDetailAndMakeupRejectZeroTargetsButGlobalFieldsRemainEditable() async throws {
        let (model, root, store) = try await modelWithUnassignedFace()
        defer {
            model.stopWork()
            try? FileManager.default.removeItem(at: root)
        }
        let before = model.session.selected!.document
        let saves = store.saveCount
        for change in [
            EditChange.skinSmoothing(0.8), .skinRefinement(.spots, 1), .faceShape(.doubleChin, 1),
            .feature(.eyeBrighten, 0.5), .bodyShape(.waist, -0.4),
        ] {
            model.edit(change)
            XCTAssertEqual(model.session.selected!.document, before)
        }
        model.applyMakeupLook(id: try XCTUnwrap(model.makeupCatalog.looks.first?.id))
        XCTAssertEqual(model.session.selected!.document, before)
        XCTAssertEqual(store.saveCount, saves)
        model.edit(.bodySkin(.brightness, 0.4))
        XCTAssertEqual(model.currentRecipe.bodySkin.brightness, 0.4)
        model.edit(.exposure(0.2))
        XCTAssertEqual(model.currentRecipe.color.exposure, 0.2)
    }

    func testExplicitFaceGenderEnablesOnlyTheActuallyMatchedGroup() async throws {
        let (model, root, _) = try await modelWithUnassignedFace()
        defer {
            model.stopWork()
            try? FileManager.default.removeItem(at: root)
        }
        model.setBeautyTarget(.face(0))
        model.setGender(.female)
        model.setBeautyTarget(.gender(.female))
        XCTAssertEqual(model.portraitFaceCount(for: model.beautyTarget), 1)
        model.applyOneTouch()
        XCTAssertEqual(model.currentRecipe.people.groups[.female]?.oneTouch, 0.6)
        let before = model.currentRecipe
        model.setBeautyTarget(.gender(.male))
        XCTAssertEqual(model.portraitFaceCount(for: model.beautyTarget), 0)
        model.applyOneTouch()
        XCTAssertEqual(model.currentRecipe, before)
    }

    func testRejectedAndDuplicateSliderEndNeverSaveAnEmptyGesture() async throws {
        let (model, root, store) = try await modelWithUnassignedFace()
        defer {
            model.stopWork()
            try? FileManager.default.removeItem(at: root)
        }
        model.selectTool(.beauty)
        model.beautyTab = .skin
        let before = model.session.selected!.document
        let saves = store.saveCount
        model.beginSliderEdit()
        XCTAssertFalse(model.session.isPersistenceDeferred)
        model.edit(.skinSmoothing(0.7))
        model.endSliderEdit()
        model.endSliderEdit()
        XCTAssertEqual(model.session.selected!.document, before)
        XCTAssertEqual(store.saveCount, saves)
        model.beautyTab = .skinTone
        model.beginSliderEdit()
        model.edit(.bodySkin(.brightness, 0.3))
        model.endSliderEdit()
        XCTAssertEqual(store.saveCount, saves + 1, "사진 단위 몸 피부 조정은 막지 않는다")
    }

    func testMembershipDisappearingDuringDragDrainsOnceAndKeepsAppliedValue() async throws {
        let (model, root, store) = try await modelWithUnassignedFace()
        defer {
            model.stopWork()
            try? FileManager.default.removeItem(at: root)
        }
        let id = model.session.selectedPhotoID!
        let info = model.selectedInfo!
        let thumbnail = model.thumbnails[id]!
        func remember(_ genders: [Gender?]) {
            model.remember(
                id,
                PreparedPhoto(
                    pixelSize: info.pixelSize, thumbnail: thumbnail, faces: info.faces, faceAnalysisFailure: nil,
                    genders: genders), bindsLegacyPeople: false)
        }
        remember([.female])
        model.selectTool(.beauty)
        model.beautyTab = .skin
        let saves = store.saveCount
        model.beginSliderEdit()
        model.edit(.skinSmoothing(0.4))
        XCTAssertTrue(model.session.isPersistenceDeferred)
        remember([nil])
        XCTAssertEqual(model.portraitFaceCount(for: .gender(.female)), 0)
        model.edit(.skinSmoothing(0.8))
        XCTAssertFalse(model.session.isPersistenceDeferred)
        XCTAssertEqual(model.currentRecipe.people.groups[.female]?.skinSmoothing, 0.4)
        model.endSliderEdit()
        model.endSliderEdit()
        XCTAssertEqual(store.saveCount, saves + 1)
    }

    func testUnmatchedDoesNotCountAndManualGenderWinsOverEstimate() async throws {
        let (model, root, _) = try await modelWithUnassignedFace()
        defer {
            model.stopWork()
            try? FileManager.default.removeItem(at: root)
        }
        let id = model.session.selectedPhotoID!
        let outside = NormalizedRect(x: 0.92, y: 0.92, width: 0.05, height: 0.05)
        model.session.edit(id) { document in
            document.set(.gender(.female), forFace: 0, of: [outside])
        }
        let orphan = model.currentRecipe.people.individuals[0]
        XCTAssertEqual(model.portraitFaceCount(for: .gender(.female)), 0)
        model.setBeautyTarget(.person(orphan.id))
        let before = model.currentRecipe
        model.openRetouchDestination(.skin)
        XCTAssertEqual(model.currentRecipe, before)
        let info = model.selectedInfo!
        model.remember(
            id,
            PreparedPhoto(
                pixelSize: info.pixelSize, thumbnail: model.thumbnails[id]!, faces: info.faces,
                faceAnalysisFailure: nil, genders: [.male]), bindsLegacyPeople: false)
        XCTAssertEqual(model.portraitFaceCount(for: .gender(.male)), 1)
        model.setBeautyTarget(.face(0))
        model.setGender(.female)
        XCTAssertEqual(model.portraitFaceCount(for: .gender(.female)), 1)
        XCTAssertEqual(model.portraitFaceCount(for: .gender(.male)), 0)
        model.setGender(nil)
        XCTAssertEqual(model.portraitFaceCount(for: .gender(.female)), 0)
        XCTAssertEqual(model.portraitFaceCount(for: .gender(.male)), 1)
        XCTAssertTrue(model.currentRecipe.people.individuals.contains { $0.id == orphan.id && $0 == orphan })
    }

    func testInactiveClearRedoAndReloadKeepIndividualOverride() async throws {
        let (model, root, store) = try await modelWithUnassignedFace()
        defer {
            model.stopWork()
            try? FileManager.default.removeItem(at: root)
        }
        let id = model.session.selectedPhotoID!
        model.session.edit(id) { document in
            _ = document.set(.skinSmoothing(0.83), forFace: 0, of: model.faces.map(\.boundingBox))
            return document.applyOneTouch(strength: 0.6, in: .gender(.female))
        }
        let people = model.currentRecipe.people.individuals
        model.applyOneTouch(strength: 0)
        let cleared = model.session.selected!.document
        model.undo()
        model.redo()
        XCTAssertEqual(model.session.selected!.document, cleared)
        XCTAssertEqual(model.currentRecipe.people.individuals, people)
        let reopened = ProjectSession(store: store, maxPhotos: 40)
        try reopened.restore()
        XCTAssertEqual(reopened.selected?.document, cleared)
        XCTAssertEqual(reopened.selected?.document.recipe.people.individuals, people)
    }

    func testBodyClickUsesMatchedPersonAndNavigatesWithoutEditing() async throws {
        let (model, root, store) = try await modelWithUnassignedFace()
        defer {
            model.stopWork()
            try? FileManager.default.removeItem(at: root)
        }
        let id = model.session.selectedPhotoID!
        let info = model.selectedInfo!
        let body = TestSupport.standingBody(in: NormalizedRect(x: 0.1, y: 0, width: 0.8, height: 0.6))
        let shoulder = body.joints[.leftShoulder]!
        let elbow = body.joints[.leftElbow]!
        let armMiddle = NormalizedPoint(x: (shoulder.x + elbow.x) / 2, y: (shoulder.y + elbow.y) / 2)
        model.remember(
            id,
            PreparedPhoto(
                pixelSize: info.pixelSize, thumbnail: model.thumbnails[id]!,
                faces: [TestSupport.landmarkedFace(in: NormalizedRect(x: 0.35, y: 0.75, width: 0.3, height: 0.2))],
                faceAnalysisFailure: nil, hasBody: true,
                bodyFaceMatches: [0: 0], bodyRegions: [0: body]))
        let before = model.session.selected!.document
        let saves = store.saveCount
        model.selectRetouchRegion(at: armMiddle)
        XCTAssertEqual(model.focusedRetouchDestination, .bodyShape(.arms))
        XCTAssertEqual(model.beautyTarget, .face(0))
        XCTAssertEqual(model.tool, .body)
        XCTAssertEqual(model.session.selected!.document, before)
        XCTAssertEqual(store.saveCount, saves)
        model.openRetouchDestination(.sideChest)
        XCTAssertTrue(model.showsBodyShape(.sideChest), "개인 scope에서 실제 부유방 행을 보여 준다")
        XCTAssertEqual(model.session.selected!.document, before)
    }

    func testUnmatchedOrOverlappingBodiesNeverGuessAPerson() async throws {
        let (model, root, store) = try await modelWithUnassignedFace()
        defer {
            model.stopWork()
            try? FileManager.default.removeItem(at: root)
        }
        let id = model.session.selectedPhotoID!
        let info = model.selectedInfo!
        let body = TestSupport.standingBody(in: NormalizedRect(x: 0.1, y: 0, width: 0.8, height: 0.6))
        for regions in [[0: body], [0: body, 1: body]] {
            model.remember(
                id,
                PreparedPhoto(
                    pixelSize: info.pixelSize, thumbnail: model.thumbnails[id]!,
                    faces: info.faces, faceAnalysisFailure: nil, hasBody: true, bodyRegions: regions))
            model.selectTool(.region)
            model.focusedRetouchDestination = nil
            let before = model.session.selected!.document
            let saves = store.saveCount
            model.selectRetouchRegion(at: body.joints[.leftElbow]!)
            XCTAssertNil(model.focusedRetouchDestination)
            XCTAssertEqual(model.tool, .region)
            XCTAssertEqual(model.session.selected!.document, before)
            XCTAssertEqual(store.saveCount, saves)
        }
    }

    func testSideChestDirectoryRequiresExplicitPersonForMultipleFaces() async throws {
        let (model, root, store) = try await modelWithUnassignedFace()
        defer {
            model.stopWork()
            try? FileManager.default.removeItem(at: root)
        }
        let id = model.session.selectedPhotoID!
        let info = model.selectedInfo!
        model.remember(
            id,
            PreparedPhoto(
                pixelSize: info.pixelSize, thumbnail: model.thumbnails[id]!,
                faces: TestSupport.coupleFaces(), faceAnalysisFailure: nil))
        model.setBeautyTarget(.all)
        let before = model.session.selected!.document
        let saves = store.saveCount
        model.openRetouchDestination(.sideChest)
        XCTAssertEqual(model.tool, .region)
        XCTAssertEqual(model.beautyTarget, .all)
        model.chooseRetouchPerson(1)
        XCTAssertEqual(model.tool, .body)
        XCTAssertEqual(model.beautyTarget, .face(1))
        XCTAssertTrue(model.showsBodyShape(.sideChest))
        XCTAssertEqual(model.session.selected!.document, before)
        XCTAssertEqual(store.saveCount, saves)
        XCTAssertTrue(model.faces.indices.allSatisfy { model.effectiveGender(forFace: $0) == nil })
    }

    func testFaceRoutesUseExistingGeometryInverseAndNeverEdit() async throws {
        let (model, root, store) = try await modelWithUnassignedFace()
        defer {
            model.stopWork()
            try? FileManager.default.removeItem(at: root)
        }
        let face = model.faces[0]
        func center(_ key: FaceLandmark) throws -> NormalizedPoint {
            let box = try XCTUnwrap(face.bounds(of: key))
            return NormalizedPoint(x: box.x + box.width / 2, y: box.y + box.height / 2)
        }
        let eye = try center(.leftEye)
        let mouth = try center(.outerLips)
        let chin = try XCTUnwrap(face.landmarks[.faceContour]?.min { $0.y < $1.y })
        let underChin = NormalizedPoint(x: chin.x, y: chin.y - 0.03)
        let cheek = NormalizedPoint(x: face.boundingBox.x + 0.08, y: face.boundingBox.y + 0.25)
        let routes: [(NormalizedPoint, RetouchDestination)] = [
            (eye, .feature(.eyeBrighten)), (mouth, .feature(.lipVitality)), (cheek, .skin), (underChin, .doubleChin),
        ]
        let combinations = (0..<4).flatMap { turns in [false, true].map { (turns, $0) } }
        for (turns, flip) in combinations {
            model.edit(.quarterTurns(turns))
            model.edit(.flipHorizontal(flip))
            model.edit(.crop(NormalizedRect(x: 0.05, y: 0.05, width: 0.9, height: 0.9)))
            try await waitUntil { !model.isRendering }
            let transform = try XCTUnwrap(model.outputTransform)
            for (original, destination) in routes {
                let output = try XCTUnwrap(transform.toOutput(original))
                model.selectTool(.region)
                model.setBeautyTarget(.all)
                let before = model.session.selected!.document
                let saves = store.saveCount
                model.touch(from: output, to: output)
                XCTAssertEqual(model.focusedRetouchDestination, destination)
                XCTAssertEqual(model.beautyTarget, .face(0))
                XCTAssertTrue(model.showsDetailAdjustments)
                XCTAssertEqual(model.session.selected!.document, before)
                XCTAssertEqual(store.saveCount, saves)
            }
        }
    }

    func testCompareAndNonlinearWarpUseExplicitListFallback() async throws {
        let (model, root, _) = try await modelWithUnassignedFace()
        defer {
            model.stopWork()
            try? FileManager.default.removeItem(at: root)
        }
        model.compareMode = .split
        XCTAssertNotNil(model.regionSelectionUnavailableReason)
        model.focusedRetouchDestination = nil
        model.selectRetouchRegion(at: NormalizedPoint(x: 0.5, y: 0.5))
        XCTAssertNil(model.focusedRetouchDestination)
        model.compareMode = .off
        model.session.edit(model.session.selectedPhotoID!) { document in
            document.appendLocalEdit(.warp(WarpStroke(x: 0.5, y: 0.5, dx: 0.02, dy: 0, radius: 0.1)))
            return nil
        }
        let before = model.session.selected!.document
        XCTAssertNotNil(model.regionSelectionUnavailableReason)
        model.selectRetouchRegion(at: NormalizedPoint(x: 0.5, y: 0.5))
        XCTAssertNil(model.focusedRetouchDestination)
        model.openRetouchDestination(.doubleChin)
        XCTAssertEqual(model.focusedRetouchDestination, .doubleChin, "위치 클릭이 막혀도 목록 진입은 유지한다")
        XCTAssertTrue(model.isGeometryLocked, "기존 수동 브러시 보호를 해제하지 않는다")
        XCTAssertEqual(model.session.selected!.document, before)
    }

    func testRegionSelectionRejectsPendingFailedAndStoppedPreview() async throws {
        let (model, root, store) = try await modelWithUnassignedFace()
        defer {
            model.stopWork()
            try? FileManager.default.removeItem(at: root)
        }
        model.selectTool(.region)
        model.edit(.quarterTurns(1))
        XCTAssertTrue(model.isRendering)
        let point = NormalizedPoint(x: 0.5, y: 0.5)
        model.focusedRetouchDestination = nil
        let before = model.session.selected!.document
        let saves = store.saveCount
        model.touch(from: point, to: point)
        XCTAssertNil(model.focusedRetouchDestination, "새 기하를 그리기 전의 화면 좌표로 대상을 선택하면 안 된다")
        XCTAssertNotNil(model.regionSelectionUnavailableReason)
        XCTAssertEqual(model.session.selected!.document, before)
        XCTAssertEqual(store.saveCount, saves)
        try await waitUntil { !model.isRendering }
        model.focusedRetouchDestination = nil
        model.lastRenderFailure = "검사용 렌더 실패"
        model.selectRetouchRegion(at: point)
        XCTAssertNil(model.focusedRetouchDestination, "렌더 실패 뒤 남아 있는 이전 화면도 거절한다")
        XCTAssertNotNil(model.regionSelectionUnavailableReason)
        model.scheduleRender()
        XCTAssertNotNil(model.lastRenderFailure, "요청만으로 이전 실패 표시를 지우지 않는다")
        model.selectRetouchRegion(at: point)
        XCTAssertNil(model.focusedRetouchDestination)
        try await waitUntil { !model.isRendering }
        XCTAssertNil(model.lastRenderFailure, "실제 성공 completion만 실패 표시를 지운다")
        model.stopWork()
        model.selectRetouchRegion(at: point)
        XCTAssertNil(model.focusedRetouchDestination, "중단된 미리보기에서 선택을 재개하지 않는다")
        XCTAssertNotNil(model.regionSelectionUnavailableReason)
        model.resumeWork()
        XCTAssertTrue(model.isRendering)
        model.selectRetouchRegion(at: point)
        XCTAssertNil(model.focusedRetouchDestination, "재개 직후에도 이전 표시를 새 상태로 오인하지 않는다")
        try await waitUntil { !model.isRendering }
        XCTAssertNil(model.lastRenderFailure)
        XCTAssertNil(model.regionSelectionUnavailableReason)
        model.selectRetouchRegion(at: point)
        XCTAssertNotNil(model.focusedRetouchDestination, "실제 최신 렌더 완료 뒤 선택을 다시 허용한다")
    }

    func testWarpUndoRejectsOldWarpedDisplayUntilRenderCompletes() async throws {
        let (model, root, _) = try await modelWithUnassignedFace()
        defer {
            model.stopWork()
            try? FileManager.default.removeItem(at: root)
        }
        model.selectTool(.warp)
        model.touch(from: NormalizedPoint(x: 0.5, y: 0.5), to: NormalizedPoint(x: 0.55, y: 0.5))
        try await waitUntil { !model.isRendering }
        XCTAssertFalse(model.currentRecipe.warps.isEmpty)
        model.undo()
        XCTAssertTrue(model.currentRecipe.warps.isEmpty)
        XCTAssertTrue(model.isRendering)
        model.selectTool(.region)
        model.focusedRetouchDestination = nil
        let point = NormalizedPoint(x: 0.5, y: 0.5)
        model.touch(from: point, to: point)
        XCTAssertNil(model.focusedRetouchDestination)
        try await waitUntil { !model.isRendering }
        model.touch(from: point, to: point)
        XCTAssertNotNil(model.focusedRetouchDestination)
    }

}
