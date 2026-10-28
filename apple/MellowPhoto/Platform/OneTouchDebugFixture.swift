#if DEBUG
    import CoreImage
    import CryptoKit
    import Foundation
    import ImageIO
    import MellowEditing
    import MellowExport
    import MellowLibrary
    import MellowRendering
    import MellowShared
    import PhotosUI
    import SwiftUI

    /// 기존 UI 검사 진입의 명시 modifier 전용 합성 표본. 실제 피부 품질의 증거로 쓰지 않는다.
    extension AppModel {
        static func oneTouchDebugFixture() throws -> AppModel {
            let root = FileManager.default.temporaryDirectory.appendingPathComponent(
                "MellowOneTouch-\(UUID().uuidString)")
            let copies = WorkingCopyStore(directory: root.appendingPathComponent("Library"))
            try copies.prepareDirectory()
            let store = OneTouchDebugStore(fileURL: root.appendingPathComponent("session.json"))
            let session = ProjectSession(store: store, maxPhotos: 2)
            let face = OneTouchDebugAnalyzer.face
            for index in 0..<2 {
                let image = CIImage(color: CIColor(red: 0.5 + Double(index) * 0.1, green: 0.4, blue: 0.3))
                    .cropped(to: CGRect(x: 0, y: 0, width: 480, height: 640))
                let filename = "synthetic-portrait-\(index).png"
                let cg = try Renderer().makeCGImage(image)
                guard
                    let destination = CGImageDestinationCreateWithURL(
                        copies.url(for: filename) as CFURL, "public.png" as CFString, 1, nil)
                else { throw MellowError.cannotWriteToFolder }
                CGImageDestinationAddImage(destination, cg, nil)
                guard CGImageDestinationFinalize(destination) else { throw MellowError.cannotWriteToFolder }
                var seed = EditDocument()
                seed.applyOneTouch(strength: 1)
                seed.set(.gender(.female), forFace: 0, of: [face.boundingBox])
                seed.applyOneTouch(strength: 0.2, forFace: 0, of: [face.boundingBox])
                try session.add(
                    PhotoEntry(
                        id: PhotoID(), filename: filename, displayName: "합성 인물 \(index + 1)",
                        document: EditDocument(recipe: seed.recipe)))
            }
            session.selectedPhotoID = session.photos.first?.id
            let looks = bundledLookCatalog() ?? .empty
            let makeup = bundledMakeupCatalog() ?? .empty
            let model = AppModel(
                session: session,
                pipeline: PhotoPipeline(
                    analyzer: OneTouchDebugAnalyzer(), tuning: RenderTuning(),
                    lookCatalog: looks, makeupCatalog: makeup), copies: copies,
                importer: OneTouchDebugImporter(), exporter: Exporter(renderer: Renderer()),
                lookCatalog: looks, makeupCatalog: makeup)
            model.isOneTouchUIFixture = true
            model.oneTouchFixtureSaveCount = { store.saves }
            return model
        }

        /// 합성 fixture에서만 접근하는 읽기 전용 계측. 레시피를 주입하거나 설정을 바꾸지 않는다.
        var oneTouchFixtureSnapshot: String {
            guard isOneTouchUIFixture else { return "" }
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            let recipe = (try? encoder.encode(currentRecipe)) ?? Data()
            func sha(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }
            let person = peopleByFace[0]
            let resolved = PortraitResolver.resolve(currentRecipe, person: person, gender: effectiveGender(forFace: 0))
            let value: [String: Any] = [
                "fixture": "synthetic-one-touch-overrides", "photo": session.selectedPhotoID?.rawValue.uuidString ?? "",
                "recipeSHA": sha(recipe), "previewSHA": preview.map { sha($0.dataProvider!.data! as Data) } ?? "",
                "sourceSHA": session.selected.flatMap { try? Data(contentsOf: copies.url(for: $0.filename)) }.map(sha)
                    ?? "",
                "requestCurrent": requestedOneTouchStrength(for: beautyTarget),
                "bodyBrightness": currentRecipe.bodySkin.brightness,
                "decisionID": pendingOneTouchDecision.flatMap { oneTouchDecision(for: $0.target) }?.id.uuidString ?? "",
                "context": portraitPurposeContext.uuidString,
                "ready": isReady && !isBusy && !isRendering && lastRenderFailure == nil,
                "target": String(describing: beautyTarget), "requestAll": requestedOneTouchStrength(for: .all),
                "resolvedSmoothing": resolved.portrait.skin.smoothing, "resolvedSpots": resolved.portrait.skin.spots,
                "undo": session.selected?.document.undoStack.count ?? 0,
                "redo": session.selected?.document.redoStack.count ?? 0,
                "saves": oneTouchFixtureSaveCount?() ?? 0, "compare": String(describing: compareMode),
                "feedbackAll": oneTouchFeedback(for: .all).map { String(describing: $0.phase) } ?? "none",
            ]
            guard let data = try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]) else {
                return ""
            }
            return String(data: data, encoding: .utf8) ?? ""
        }
    }

    private final class OneTouchDebugStore: SessionStore, @unchecked Sendable {
        let base: JSONSessionStore
        var saves = 0
        init(fileURL: URL) { base = JSONSessionStore(fileURL: fileURL) }
        func load() throws -> SessionSnapshot? { try base.load() }
        func save(_ snapshot: SessionSnapshot) throws {
            saves += 1
            try base.save(snapshot)
        }
    }
    private struct OneTouchDebugImporter: PhotoImporter {
        func stage(_ items: [PhotosPickerItem]) async -> [Result<StagedPhoto, Error>] { [] }
        func stage(fileURLs: [URL]) async -> [Result<StagedPhoto, Error>] { [] }
    }
    private struct OneTouchDebugAnalyzer: FaceAnalyzer {
        func analyze(_ image: CIImage) throws -> [FaceGeometry] { [Self.face] }
        static var face: FaceGeometry {
            let box = NormalizedRect(x: 0.2, y: 0.2, width: 0.6, height: 0.6)
            func point(_ x: Double, _ y: Double) -> NormalizedPoint {
                NormalizedPoint(x: box.minX + box.width * x, y: box.minY + box.height * y)
            }
            func ellipse(_ x: Double, _ y: Double, _ rx: Double, _ ry: Double) -> [NormalizedPoint] {
                (0..<12).map { index in
                    let angle = 2 * Double.pi * Double(index) / 12
                    return point(x + rx * cos(angle), y + ry * sin(angle))
                }
            }
            let contour = (0...16).map { index in
                let angle = Double.pi + Double.pi * Double(index) / 16
                return point(0.5 + 0.5 * cos(angle), 0.6 + 0.6 * sin(angle))
            }
            return FaceGeometry(
                boundingBox: box,
                landmarks: [
                    .faceContour: contour,
                    .leftEye: ellipse(0.3, 0.63, 0.1, 0.04), .rightEye: ellipse(0.7, 0.63, 0.1, 0.04),
                    .leftPupil: [point(0.3, 0.63)], .rightPupil: [point(0.7, 0.63)],
                    .leftEyebrow: ellipse(0.3, 0.75, 0.12, 0.02), .rightEyebrow: ellipse(0.7, 0.75, 0.12, 0.02),
                    .nose: [point(0.42, 0.4), point(0.58, 0.4), point(0.5, 0.55)],
                    .noseCrest: [point(0.5, 0.55), point(0.5, 0.45)],
                    .outerLips: ellipse(0.5, 0.27, 0.17, 0.06), .innerLips: ellipse(0.5, 0.27, 0.13, 0.02),
                ])
        }
    }
#endif
