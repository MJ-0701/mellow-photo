import CoreImage
import Foundation
import ImageIO
import MellowExport
import MellowLibrary
import MellowRendering
import MellowShared
import PhotosUI
import SwiftUI
import XCTest

@testable import Mellow_Photo

final class MemorySessionStore: SessionStore, @unchecked Sendable {
    var saved: SessionSnapshot?
    var saveCount = 0
    func load() throws -> SessionSnapshot? { saved }
    func save(_ snapshot: SessionSnapshot) throws {
        saveCount += 1
        saved = snapshot
    }
}

/// 얼굴 분석 호출 횟수. 값 타입인 StubFaceAnalyzer가 복사돼도 같은 기록을 공유한다.
final class AnalysisLog: @unchecked Sendable {
    var calls = 0
}

struct StubFaceAnalyzer: FaceAnalyzer {
    var result: Result<[FaceGeometry], MellowError> = .success([])
    var log = AnalysisLog()
    func analyze(_ image: CIImage) throws -> [FaceGeometry] {
        log.calls += 1
        return try result.get()
    }
}

/// 호출마다 다음 분석 결과를 돌려주고 마지막 결과는 계속 되풀이한다.
/// 값 타입인 스텁 분석기가 복사돼도 같은 순서와 호출 횟수를 공유한다.
final class AnalysisResultQueue<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var results: [Result<Value, MellowError>]
    private var callCount = 0

    init(_ results: [Result<Value, MellowError>]) {
        self.results = results
    }

    var calls: Int {
        lock.lock()
        defer { lock.unlock() }
        return callCount
    }

    func next() -> Result<Value, MellowError> {
        lock.lock()
        defer { lock.unlock() }
        callCount += 1
        return results.count > 1 ? results.removeFirst() : results[0]
    }
}

typealias PersonResultQueue = AnalysisResultQueue<CIImage?>
typealias BodyResultQueue = AnalysisResultQueue<[BodyGeometry]>

struct StubPersonAnalyzer: PersonAnalyzer {
    var result: Result<CIImage?, MellowError> = .success(nil)
    /// 있으면 result 대신 호출마다 이 순서의 다음 결과를 쓴다.
    var queue: PersonResultQueue?
    func personMask(_ image: CIImage) throws -> CIImage? { try (queue?.next() ?? result).get() }
}

struct StubBodyAnalyzer: BodyAnalyzer {
    var result: Result<[BodyGeometry], MellowError> = .success([])
    /// 있으면 result 대신 호출마다 이 순서의 다음 결과를 쓴다.
    var queue: BodyResultQueue?
    func analyze(_ image: CIImage) throws -> [BodyGeometry] { try (queue?.next() ?? result).get() }
}

/// 성별 추정 스텁.
/// 얼굴 수와 같은 길이의 결과를 넘기면 파이프라인이 임계값을 적용해 받아들인다.
struct StubGenderEstimator: GenderEstimator {
    var result: Result<[GenderEstimate?], MellowError> = .success([])
    func estimate(_ image: CIImage, faces: [FaceGeometry]) throws -> [GenderEstimate?] { try result.get() }
}

/// 스테이징 호출 횟수. 값 타입인 FakeImporter가 복사돼도 같은 기록을 공유한다.
final class StagingLog: @unchecked Sendable {
    var calls = 0
}

struct FakeImporter: PhotoImporter {
    var staged: [Result<StagedPhoto, Error>] = []
    /// true면 `staged` 대신 받은 파일 URL을 그대로 스테이징 결과로 돌려준다. 여러 번 가져오기 테스트용.
    var passesThroughFileURLs = false
    var log = StagingLog()
    func stage(_ items: [PhotosPickerItem]) async -> [Result<StagedPhoto, Error>] {
        log.calls += 1
        return staged
    }
    func stage(fileURLs: [URL]) async -> [Result<StagedPhoto, Error>] {
        log.calls += 1
        guard passesThroughFileURLs else { return staged }
        return fileURLs.map {
            .success(StagedPhoto(url: $0, displayName: $0.deletingPathExtension().lastPathComponent))
        }
    }
}

final class RecordingDestination: ExportDestination, @unchecked Sendable {
    var published: [(name: String, bytes: Int)] = []
    var failOnNames: Set<String> = []
    var delayNanoseconds: UInt64 = 0

    func publish(fileURL: URL, suggestedName: String) async throws {
        if delayNanoseconds > 0 { try await Task.sleep(nanoseconds: delayNanoseconds) }
        if failOnNames.contains(suggestedName) { throw MellowError.exportFailed(reason: "test") }
        published.append((suggestedName, try Data(contentsOf: fileURL).count))
    }
}

extension XCTestCase {
    /// 조건이 참이 될 때까지 짧게 쉬며 기다린다. 시간 안에 참이 되지 않으면 실패로 남긴다.
    @MainActor
    func waitUntil(
        _ condition: @escaping () -> Bool, timeout: TimeInterval = 10, file: StaticString = #filePath,
        line: UInt = #line
    ) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() && Date() < deadline {
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        XCTAssertTrue(condition(), file: file, line: line)
    }
}

enum TestSupport {
    static func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// 단색 PNG를 임시 폴더에 쓴다. 가져오기 테스트의 "선택된 사진" 역할.
    static func solidPNG(in directory: URL, name: String = UUID().uuidString, size: Int = 128) throws -> URL {
        let url = directory.appendingPathComponent("\(name).png")
        let image = CIImage(color: CIColor(red: 0.5, green: 0.4, blue: 0.3)).cropped(
            to: CGRect(x: 0, y: 0, width: size, height: size))
        let cg = try Renderer().makeCGImage(image)
        let destination = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil)!
        CGImageDestinationAddImage(destination, cg, nil)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        return url
    }

    /// 저장소의 공용 룩 카탈로그. 앱 번들과 같은 파일이다.
    static func sharedLookCatalog() throws -> LookCatalog {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("shared/looks/looks.v1.json")
        return try LookCatalog(data: Data(contentsOf: url))
    }

    /// 저장소의 공용 메이크업 카탈로그. 앱 번들과 같은 파일이다.
    static func sharedMakeupCatalog() throws -> MakeupCatalog {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("shared/makeup/makeup.v1.json")
        return try MakeupCatalog(data: Data(contentsOf: url))
    }

    /// box 안에 비율로 놓은 가짜 특징점 얼굴. 윤곽은 Vision처럼 한쪽 관자놀이에서 턱을 지나 반대쪽까지 17점이다.
    static func landmarkedFace(in box: NormalizedRect) -> FaceGeometry {
        func point(_ x: Double, _ y: Double) -> NormalizedPoint {
            NormalizedPoint(x: box.minX + box.width * x, y: box.minY + box.height * y)
        }
        func ellipse(_ centerX: Double, _ centerY: Double, _ radiusX: Double, _ radiusY: Double) -> [NormalizedPoint] {
            (0..<12).map { step in
                let angle = 2 * Double.pi * Double(step) / 12
                return point(centerX + radiusX * cos(angle), centerY + radiusY * sin(angle))
            }
        }
        let contour = (0...16).map { step -> NormalizedPoint in
            let angle = Double.pi + Double.pi * Double(step) / 16
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

    /// 스텁 인물 마스크의 한 변(픽셀). Vision 마스크처럼 사진과 크기·비율이 다르다.
    static let personMaskSide = 64.0

    /// 검은 바탕에 흰 사각형 사람이 있는 정사각형 인물 마스크. person은 정규화 사각형(원점 왼쪽 아래).
    static func personMask(_ person: NormalizedRect) -> CIImage {
        let extent = CGRect(x: 0, y: 0, width: personMaskSide, height: personMaskSide)
        let rect = CGRect(
            x: person.x * personMaskSide, y: person.y * personMaskSide, width: person.width * personMaskSide,
            height: person.height * personMaskSide)
        return CIImage(color: .white).cropped(to: rect).composited(over: CIImage(color: .black)).cropped(to: extent)
    }

    /// 정면으로 선 사람의 관절점(box 비율, 신뢰도 1). 패키지 테스트의 RenderingTestSupport.standingBody와 같은 배치다.
    static func standingBody(in box: NormalizedRect) -> BodyGeometry {
        let layout: [BodyJoint: (x: Double, y: Double)] = [
            .neck: (0.5, 0.82), .rightShoulder: (0.25, 0.8), .leftShoulder: (0.75, 0.8),
            .rightElbow: (0.18, 0.62), .leftElbow: (0.82, 0.62), .rightWrist: (0.15, 0.45), .leftWrist: (0.85, 0.45),
            .rightHip: (0.38, 0.5), .leftHip: (0.62, 0.5), .rightKnee: (0.39, 0.27), .leftKnee: (0.61, 0.27),
            .rightAnkle: (0.4, 0.05), .leftAnkle: (0.6, 0.05), .root: (0.5, 0.5),
        ]
        var joints: [BodyJoint: NormalizedPoint] = [:]
        for (joint, spot) in layout {
            joints[joint] = NormalizedPoint(x: box.minX + box.width * spot.x, y: box.minY + box.height * spot.y)
        }
        return BodyGeometry(joints: joints, confidence: joints.mapValues { _ in 1 })
    }

    /// 나란히 선 두 사람의 얼굴(왼쪽부터).
    /// coupleBodies와 짝이 맞게 놓았다.
    static func coupleFaces() -> [FaceGeometry] {
        [
            landmarkedFace(in: NormalizedRect(x: 0.12, y: 0.62, width: 0.2, height: 0.2)),
            landmarkedFace(in: NormalizedRect(x: 0.62, y: 0.62, width: 0.2, height: 0.2)),
        ]
    }

    /// 나란히 선 두 사람의 몸(큰 몸이 앞).
    /// 몸마다 목이 coupleFaces 같은 인덱스 얼굴의 기대 목 위치에 있어 준비가 몸 0 → 얼굴 0, 몸 1 → 얼굴 1로 짝짓는다.
    static func coupleBodies() -> [BodyGeometry] {
        [
            standingBody(in: NormalizedRect(x: 0, y: 0, width: 0.44, height: 0.7)),
            standingBody(in: NormalizedRect(x: 0.52, y: 0.05, width: 0.4, height: 0.635)),
        ]
    }

    /// makeupCatalog가 nil이면 공용 파일을 읽는다. 카탈로그가 없는 경우는 .empty를 넘긴다.
    @MainActor
    static func makeModel(
        root: URL, maxPhotos: Int = 40, analyzer: any FaceAnalyzer = StubFaceAnalyzer(),
        personAnalyzer: StubPersonAnalyzer = StubPersonAnalyzer(), bodyAnalyzer: StubBodyAnalyzer = StubBodyAnalyzer(),
        genderEstimator: StubGenderEstimator? = nil, makeupCatalog: MakeupCatalog? = nil,
        importer: FakeImporter = FakeImporter(),
        store: MemorySessionStore = MemorySessionStore()
    ) -> AppModel {
        let copies = WorkingCopyStore(directory: root.appendingPathComponent("Library"))
        try? copies.prepareDirectory()
        let catalog = (try? sharedLookCatalog()) ?? .empty
        let makeup = makeupCatalog ?? (try? sharedMakeupCatalog()) ?? .empty
        return AppModel(
            session: ProjectSession(store: store, maxPhotos: maxPhotos),
            pipeline: PhotoPipeline(
                analyzer: analyzer, personAnalyzer: personAnalyzer, bodyAnalyzer: bodyAnalyzer,
                genderEstimator: genderEstimator, tuning: RenderTuning(),
                lookCatalog: catalog, makeupCatalog: makeup),
            copies: copies,
            importer: importer,
            exporter: Exporter(renderer: Renderer()),
            lookCatalog: catalog,
            makeupCatalog: makeup,
            renderDebounce: .milliseconds(10))
    }
}
