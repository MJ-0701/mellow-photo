import CoreImage
import MellowShared
import XCTest

@testable import MellowRendering

/// 생성 사진 세트(가상 인물)가 저장소 원본과 같고 라벨이 맞는지.
/// 자동 테스트의 1차 근거는 SyntheticFace이고 이 사진은 시나리오·수동 확인·H4 측정용이다.
final class PeopleFixturesTests: XCTestCase {
    private static let copied = ["couple-01.jpg", "group-01.jpg"]
    private static let maximumBytesPerPhoto = 600 * 1024
    private static let maximumTotalBytes = 5 * 1024 * 1024
    private static let maximumLongSide = 1024
    private static let analysisMaxDimension = 1200

    func testPeopleFixturesMatchSharedCopiesAndLabelsDescribeEveryPhoto() throws {
        let labels = try PeopleFixtures.labels()
        XCTAssertEqual(labels.version, 1)
        let sharedLabels = try Data(contentsOf: PeopleFixtures.sharedFolder.appendingPathComponent("labels.json"))
        XCTAssertEqual(try Data(contentsOf: PeopleFixtures.url("labels.json")), sharedLabels, "라벨은 저장소 원본과 바이트가 같다")
        var total = 0
        for photo in labels.photos {
            let shared = PeopleFixtures.sharedFolder.appendingPathComponent(photo.file)
            let data = try Data(contentsOf: shared)
            total += data.count
            XCTAssertLessThanOrEqual(data.count, Self.maximumBytesPerPhoto, photo.file)
            XCTAssertGreaterThanOrEqual(photo.people.count, 2, "\(photo.file): 커플 이상")
            XCTAssertTrue(photo.people.allSatisfy { ["male", "female"].contains($0.gender) }, photo.file)
            let image = try XCTUnwrap(CIImage(contentsOf: shared))
            let longSide = Int(max(image.extent.width, image.extent.height))
            XCTAssertLessThanOrEqual(longSide, Self.maximumLongSide, photo.file)
            if Self.copied.contains(photo.file) {
                XCTAssertEqual(try Data(contentsOf: PeopleFixtures.url(photo.file)), data, "\(photo.file) 사본은 원본과 같다")
            }
        }
        XCTAssertLessThanOrEqual(total, Self.maximumTotalBytes)
        XCTAssertEqual(Set(labels.photos.map(\.file)).intersection(Self.copied).count, 2)
        let genders = labels.photos.flatMap(\.people).map(\.gender)
        XCTAssertTrue(genders.contains("male") && genders.contains("female"), "남녀가 섞여 있다")
        let coupleFiles = labels.photos.filter { $0.people.count == 2 }
        XCTAssertFalse(coupleFiles.isEmpty)
        XCTAssertTrue(coupleFiles.allSatisfy { Set($0.people.map(\.gender)) == ["male", "female"] }, "커플은 남 1·여 1")
        XCTAssertTrue(labels.photos.contains { $0.people.count >= 4 && $0.people.count <= 6 }, "단체 4~6명")
        let people = labels.photos.flatMap(\.people)
        XCTAssertTrue(people.contains(where: \.glasses), "안경 한 명 이상")
        XCTAssertTrue(people.contains { $0.pose != "frontal" }, "돌아간 얼굴 한 명 이상")
        XCTAssertTrue(people.contains { $0.occlusion != "none" }, "가림 한 명 이상")
        XCTAssertGreaterThanOrEqual(Set(people.map(\.ageBand)).count, 2, "나이대 둘 이상")
    }

    /// Vision이 라벨과 같은 얼굴 수를 찾아야 시나리오 테스트에 쓸 수 있다.
    /// 실패하면 단언을 낮추지 말고 사진을 다시 만든다.
    func testVisionFindsTheLabelledNumberOfFaces() throws {
        let labels = try PeopleFixtures.labels()
        for file in Self.copied {
            let photo = try XCTUnwrap(labels.photos.first { $0.file == file })
            let url = try PeopleFixtures.url(file)
            let image = try ImageLoader().load(url: url, maxDimension: Self.analysisMaxDimension)
            let faces = try VisionFaceAnalyzer().analyze(image)
            XCTAssertEqual(faces.count, photo.people.count, "\(file): Vision 얼굴 수가 라벨 인원과 같아야 한다")
            XCTAssertEqual(faces.map(\.boundingBox.minX), faces.map(\.boundingBox.minX).sorted(), "왼쪽부터 정렬")
        }
    }
}
