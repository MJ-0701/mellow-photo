import CoreImage
import ImageIO
import MellowEditing
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
    private func demoPortraitCopy(named name: String = "demo-portrait") throws -> URL {
        let copy = root.appendingPathComponent("\(name).png")
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

    /// 공용 픽스처에는 전신이 없다(Vision은 0명을 찾는다). 다리 띠가 사진 아래쪽에 걸리도록 놓은 스텁 사람이다.
    private static let demoBody = TestSupport.standingBody(in: NormalizedRect(x: 0.15, y: 0, width: 0.7, height: 0.9))

    private func previewBytes(_ model: AppModel) -> [UInt8] {
        model.preview.map { Array($0.dataProvider!.data! as Data) } ?? []
    }

    func testBeautySkinFaceFeaturesBackgroundBodyThenMakeupThenExportSucceeds() async throws {
        let model = TestSupport.makeModel(
            root: root, analyzer: StubFaceAnalyzer(result: .success([Self.demoFace])),
            personAnalyzer: StubPersonAnalyzer(result: .success(Self.demoPersonMask)),
            bodyAnalyzer: StubBodyAnalyzer(result: .success([Self.demoBody])),
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
        for (key, value) in [(SkinRefinementKey.darkCircles, 0.6), (.toneEvening, 0.5)] {
            model.beginSliderEdit()
            model.edit(.skinRefinement(key, value))
            model.endSliderEdit()
        }
        // 피부 정밀만 바꿔도 미리보기가 바뀌어야 한다.
        try await waitUntil { !model.isRendering && self.previewBytes(model) != skinned }
        let refined = previewBytes(model)

        model.beautyTab = .skinTone
        XCTAssertTrue(model.canAdjustBodySkin(.brightness))
        model.beginSliderEdit()
        model.edit(.bodySkin(.brightness, 0.6))
        model.endSliderEdit()
        // 몸 피부 밝기만 바꿔도 미리보기가 바뀌어야 한다(스텁 인물 마스크가 얼굴을 덮는다).
        try await waitUntil { !model.isRendering && self.previewBytes(model) != refined }
        let toned = previewBytes(model)

        model.selectTool(.adjust)
        model.beginSliderEdit()
        model.edit(.effect(.grain, 0.5))
        model.endSliderEdit()
        // 그레인만 바꿔도 미리보기가 바뀌어야 한다.
        try await waitUntil { !model.isRendering && self.previewBytes(model) != toned }
        let grained = previewBytes(model)
        model.isComparing = true
        XCTAssertTrue(model.displayImage === model.original, "전체 토글은 원본을 보인다")
        model.toggleSplitCompare()
        XCTAssertEqual(model.compareMode, .split)
        model.toggleSplitCompare()
        XCTAssertEqual(model.compareMode, .off)

        model.selectTool(.beauty)
        model.beautyTab = .face
        let faceEdits: [(FaceShapeKey, Double)] = [(.width, -0.5), (.eyeSize, 0.3), (.smile, 0.4)]
        for (key, value) in faceEdits {
            model.beginSliderEdit()
            model.edit(.faceShape(key, value))
            model.endSliderEdit()
        }
        // 얼굴형만 바꿔도 미리보기가 바뀌어야 한다(바뀌지 않으면 시간 초과로 실패).
        try await waitUntil { !model.isRendering && self.previewBytes(model) != grained }

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
        let blurred = previewBytes(model)

        model.selectTool(.body)
        XCTAssertEqual(model.bodyAvailability, .ready)
        model.beginSliderEdit()
        model.edit(.bodyShape(.legLength, 0.5))
        model.endSliderEdit()
        // 다리 길게만 바꿔도 미리보기가 바뀌어야 한다.
        try await waitUntil { !model.isRendering && self.previewBytes(model) != blurred }
        let bodied = previewBytes(model)

        model.selectTool(.makeup)
        model.applyMakeupLook(id: "daily")
        // 메이크업 룩만 골라도 미리보기가 바뀌어야 한다.
        try await waitUntil { !model.isRendering && self.previewBytes(model) != bodied }
        // 선택 동기화가 색감을 실제로 옮기는지 보려고 색감 하나를 바꿔 둔다.
        model.selectTool(.adjust)
        model.beginSliderEdit()
        model.edit(.warmth(0.3))
        model.endSliderEdit()

        let recipe = model.currentRecipe
        XCTAssertEqual(recipe.color.warmth, 0.3, accuracy: 1e-9)
        XCTAssertEqual(recipe.effects, EffectAdjustments(grain: 0.5))
        XCTAssertEqual(
            recipe.portrait.skin,
            SkinAdjustments(smoothing: 0.5, autoBlemish: true, darkCircles: 0.6, toneEvening: 0.5))
        XCTAssertEqual(recipe.portrait.face, FaceShapeAdjustments(width: -0.5, eyeSize: 0.3, smile: 0.4))
        XCTAssertEqual(recipe.portrait.features, FeatureAdjustments(eyeBrighten: 0.5))
        XCTAssertEqual(recipe.bodySkin, BodySkinAdjustments(brightness: 0.6))
        XCTAssertEqual(recipe.background.blur, 0.5, accuracy: 1e-9)
        XCTAssertEqual(recipe.body, BodyShapeAdjustments(legLength: 0.5))
        XCTAssertEqual(recipe.makeup, try XCTUnwrap(model.makeupCatalog.look(id: "daily")).adjustments)

        // 선택 동기화: 두 번째 사진은 색감만 받아야 한다.
        await model.importFromFiles([try demoPortraitCopy(named: "demo-second")])
        try await waitUntil { model.session.photos.count == 2 && !model.isImporting }
        let firstID = model.session.photos[0].id
        model.select(firstID)
        try await waitUntil { model.isReady && model.preview != nil }
        // 기다림이 실패했을 때 느린 렌더와 렌더 실패를 구분한다.
        XCTAssertNil(model.selectionFailure)
        XCTAssertNil(model.lastRenderFailure)
        for category in SyncCategory.allCases where category != .color {
            model.setSyncCategory(category, enabled: false)
        }
        model.applyToAll()
        let second = model.session.photos[1].document.recipe
        XCTAssertEqual(second.color, recipe.color, "색감만 복사")
        XCTAssertEqual(second.portrait.skin, SkinAdjustments(), "피부는 복사하지 않음")
        XCTAssertEqual(second.effects, EffectAdjustments(), "효과도 복사하지 않음")
        XCTAssertEqual(model.currentRecipe, recipe, "보낸 사진의 레시피는 그대로")

        let size = try await exportedPixelSize(model)
        XCTAssertEqual(size.width, size.height, "다리를 늘리고 메이크업을 해도 정사각형 원본 크기 그대로 저장된다")
    }

    /// 원터치 → 강도 → 세부 조정에서 묶인 키 변경(꼬리표 해제) → 저장.
    func testOneTouchThenStrengthThenDetailOverrideThenExportSucceeds() async throws {
        let model = TestSupport.makeModel(
            root: root, analyzer: StubFaceAnalyzer(result: .success([Self.demoFace])),
            importer: FakeImporter(passesThroughFileURLs: true))
        await model.importFromFiles([try demoPortraitCopy()])
        try await waitUntil { model.isReady && model.preview != nil }
        model.selectTool(.beauty)
        let baseline = previewBytes(model)
        model.applyOneTouch()
        try await waitUntil { !model.isRendering && self.previewBytes(model) != baseline }
        XCTAssertEqual(model.oneTouchStrength, EditingPolicy.oneTouchDefaultStrength)
        XCTAssertTrue(model.isOneTouchTagged(.skinRefinement(.darkCircles)))
        let defaultBytes = previewBytes(model)
        model.beginSliderEdit()
        model.applyOneTouch(strength: 1)
        model.endSliderEdit()
        try await waitUntil { !model.isRendering && self.previewBytes(model) != defaultBytes }
        XCTAssertEqual(model.oneTouchStrength, 1)
        model.showsDetailAdjustments = true
        model.beginSliderEdit()
        model.edit(.skinRefinement(.darkCircles, 0.1))
        model.endSliderEdit()
        try await waitUntil { !model.isRendering }
        XCTAssertNil(model.oneTouchStrength, "세부 조정이 표시를 지운다")
        XCTAssertFalse(model.isOneTouchTagged(.skinRefinement(.darkCircles)))
        XCTAssertEqual(model.currentRecipe.people.groups[.female]?.oneTouch, 1, "그룹 표시는 남는다")
        model.undo()
        XCTAssertEqual(model.oneTouchStrength, 1, "실행 취소 한 번에 표시가 돌아온다")
        let size = try await exportedPixelSize(model)
        XCTAssertGreaterThan(size.width, 0)
        XCTAssertNil(model.presentedError)
    }

    /// 생성 사진 라벨 중 시나리오가 읽는 부분.
    /// 전체 형식(PeopleLabels)은 렌더링 테스트 타깃에 있다.
    private struct ScenarioLabels: Decodable {
        struct Photo: Decodable {
            struct Person: Decodable {
                let gender: String
            }
            let file: String
            let people: [Person]
        }
        let photos: [Photo]
    }

    private var peopleFixtureFolder: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("shared/fixtures/people")
    }

    private func scenarioLabels() throws -> ScenarioLabels {
        let data = try Data(contentsOf: peopleFixtureFolder.appendingPathComponent("labels.json"))
        return try JSONDecoder().decode(ScenarioLabels.self, from: data)
    }

    /// 가져오기는 받은 파일을 옮기므로 생성 사진을 임시 폴더에 복사해서 넘긴다.
    private func peopleFixtureCopy(_ name: String) throws -> URL {
        let copy = root.appendingPathComponent(name)
        try FileManager.default.copyItem(at: peopleFixtureFolder.appendingPathComponent(name), to: copy)
        return copy
    }

    /// 스텁 커플(얼굴 둘·몸 둘·짝): 사람 2를 여성으로 지정하고 여성 그룹에 부유방을 넣으면 렌더 대상에서 그 사람 몸만 받는다.
    func testCoupleScenarioSideChestOnlyOnTheWoman() async throws {
        let staged = try TestSupport.solidPNG(in: root)
        let faces = TestSupport.coupleFaces()
        let bodies = TestSupport.coupleBodies()
        let model = TestSupport.makeModel(
            root: root, analyzer: StubFaceAnalyzer(result: .success(faces)),
            bodyAnalyzer: StubBodyAnalyzer(result: .success(bodies)),
            importer: FakeImporter(staged: [.success(StagedPhoto(url: staged, displayName: nil))]))
        await model.importFromFiles([staged])
        try await waitUntil { model.isReady && model.preview != nil }
        model.selectTool(.body)
        model.setBeautyTarget(.face(1))
        model.setGender(.female)
        model.setBeautyTarget(.gender(.female))
        XCTAssertTrue(model.showsBodyShape(.sideChest))
        XCTAssertTrue(model.canAdjustBodyShape(.sideChest))
        model.beginSliderEdit()
        model.edit(.bodyShape(.sideChest, 1))
        model.endSliderEdit()
        try await waitUntil { !model.isRendering }
        XCTAssertNil(model.presentedError)
        let info = try XCTUnwrap(model.selectedInfo)
        // 렌더와 같은 RenderContext가 준비 때 저장한 짝으로 몸마다 체형을 건다.
        let context = RenderContext(
            extent: CGRect(origin: .zero, size: info.pixelSize), recipe: model.currentRecipe,
            analysis: PhotoAnalysis(faces: info.faces, bodies: bodies, bodyFaceMatches: info.bodyFaceMatches),
            tuning: RenderTuning())
        XCTAssertEqual(context.bodyTargets.map(\.faceIndex), [0, 1])
        XCTAssertEqual(context.bodyTargets.map(\.adjustments.sideChest), [0, 1], "여성 몸만 부유방을 받는다")
        model.setBeautyTarget(.all)
        XCTAssertFalse(model.showsBodyShape(.sideChest))
    }

    /// 생성 커플 사진(실제 Vision): 라벨대로 성별을 지정하고 여성 그룹·개인 값을 넣은 뒤 단체 사진에 피부만 동기화하고 저장한다.
    func testCoupleFixtureManualGenderGroupAndIndividualThenSyncAndExport() async throws {
        let labels = try scenarioLabels()
        let couple = try XCTUnwrap(labels.photos.first { $0.file == "couple-01.jpg" })
        let group = try XCTUnwrap(labels.photos.first { $0.file == "group-01.jpg" })
        let model = TestSupport.makeModel(
            root: root, analyzer: VisionFaceAnalyzer(), importer: FakeImporter(passesThroughFileURLs: true))
        await model.importFromFiles([try peopleFixtureCopy("couple-01.jpg"), try peopleFixtureCopy("group-01.jpg")])
        try await waitUntil({ model.session.photos.count == 2 && model.isReady && model.preview != nil }, timeout: 30)
        XCTAssertEqual(model.session.selectedPhotoID, model.session.photos[0].id, "처음 가져오면 첫 사진(커플)을 고른다")
        XCTAssertEqual(model.faces.count, couple.people.count, "Vision 얼굴 수가 라벨 인원과 같다(PeopleFixturesTests가 보증)")
        let baseline = previewBytes(model)
        model.selectTool(.beauty)
        for (index, person) in couple.people.enumerated() {
            model.setBeautyTarget(.face(index))
            model.setGender(person.gender == "male" ? .male : .female)
        }
        XCTAssertEqual(model.personChips.map(\.source), Array(repeating: .manual, count: couple.people.count))
        XCTAssertEqual(
            model.personChips.map(\.gender), couple.people.map { $0.gender == "male" ? Gender.male : .female },
            "칩의 성별이 라벨과 같다")
        model.setBeautyTarget(.gender(.female))
        model.beginSliderEdit()
        model.edit(.skinSmoothing(0.8))
        model.endSliderEdit()
        try await waitUntil({ !model.isRendering && self.previewBytes(model) != baseline }, timeout: 30)
        let femaleIndex = try XCTUnwrap(couple.people.firstIndex { $0.gender == "female" })
        let maleIndex = try XCTUnwrap(couple.people.firstIndex { $0.gender == "male" })
        model.setBeautyTarget(.face(maleIndex))
        XCTAssertEqual(model.scopedValues.portrait.skin.smoothing, 0, "남성은 여성 그룹 값을 받지 않는다")
        model.setBeautyTarget(.face(femaleIndex))
        XCTAssertEqual(model.scopedValues.portrait.skin.smoothing, 0.8)
        model.beginSliderEdit()
        model.edit(.faceShape(.width, -0.3))
        model.endSliderEdit()
        try await waitUntil({ !model.isRendering }, timeout: 30)
        XCTAssertEqual(model.overriddenKeys, [.faceShape(.width)])
        let coupleRecipe = model.currentRecipe
        XCTAssertEqual(coupleRecipe.people.individuals.count, couple.people.count)
        for category in SyncCategory.allCases where category != .skin {
            model.setSyncCategory(category, enabled: false)
        }
        model.applyToAll()
        let groupRecipe = model.session.photos[1].document.recipe
        XCTAssertEqual(groupRecipe.people.groups[.female], PortraitLayer(skinSmoothing: 0.8), "그룹 층은 복사")
        XCTAssertTrue(groupRecipe.people.individuals.isEmpty, "개인 층·성별 지정은 복사하지 않는다")
        XCTAssertEqual(model.currentRecipe, coupleRecipe, "보낸 사진의 레시피는 그대로")
        model.select(model.session.photos[1].id)
        try await waitUntil({ model.isReady && model.preview != nil }, timeout: 30)
        XCTAssertEqual(model.faces.count, group.people.count)
        XCTAssertTrue(model.personChips.allSatisfy { $0.source == .none }, "단체 사진은 아직 모두 미지정")
        model.select(model.session.photos[0].id)
        try await waitUntil({ model.isReady && model.preview != nil }, timeout: 30)
        let size = try await exportedPixelSize(model)
        XCTAssertGreaterThan(size.width, 0)
        XCTAssertNil(model.presentedError)
    }
}
