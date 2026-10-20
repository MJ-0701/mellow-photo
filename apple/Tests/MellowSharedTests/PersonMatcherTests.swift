import XCTest

@testable import MellowShared

final class PersonMatcherTests: XCTestCase {
    private func box(_ x: Double, y: Double = 0.4, width: Double = 0.2) -> NormalizedRect {
        NormalizedRect(x: x, y: y, width: width, height: width * 1.3)
    }

    private func record(_ box: NormalizedRect) -> PersonRecord {
        PersonRecord(anchor: PersonAnchor(faceBox: box))
    }

    func testAnchorsSurviveIndexShiftsAndRejectFarOrOddSizedFaces() {
        let left = box(0.1)
        let middle = box(0.4)
        let right = box(0.7)
        let people = [record(left), record(right)]
        XCTAssertEqual(
            PersonMatcher.match(people, faces: [left, middle, right]),
            [.init(person: people[0].id, faceIndex: 0), .init(person: people[1].id, faceIndex: 2)])
        XCTAssertEqual(
            PersonMatcher.match(people, faces: [middle, right]), [.init(person: people[1].id, faceIndex: 1)],
            "왼쪽 얼굴이 사라져 인덱스가 밀려도 오른쪽 사람은 오른쪽 얼굴")
        // 폭 0.2의 50% = 0.1.
        // 중심이 0.09 움직인 상자는 짝이고 0.11은 아니다.
        XCTAssertEqual(PersonMatcher.match([people[0]], faces: [box(0.19)]).count, 1)
        XCTAssertTrue(PersonMatcher.match([people[0]], faces: [box(0.21)]).isEmpty)
        XCTAssertTrue(
            PersonMatcher.match([people[0]], faces: [box(0.1, width: 0.41)]).isEmpty, "폭이 2배를 넘으면 다른 사람")
        XCTAssertEqual(PersonMatcher.match([people[0]], faces: [box(0.1, width: 0.39)]).count, 1)
        XCTAssertTrue(PersonMatcher.isMatch(PersonAnchor(faceBox: left), PersonAnchor(faceBox: box(0.15))))
        XCTAssertFalse(PersonMatcher.isMatch(PersonAnchor(faceBox: left), PersonAnchor(faceBox: right)))
        XCTAssertFalse(PersonMatcher.isMatch(PersonAnchor(x: 0.5, y: 0.5, width: 0), PersonAnchor(faceBox: left)))
        XCTAssertTrue(PersonMatcher.match(people, faces: []).isEmpty)
        XCTAssertTrue(PersonMatcher.match([], faces: [left]).isEmpty)
        XCTAssertEqual(PersonMatching.centerTolerance, 0.5)
        XCTAssertEqual(PersonMatching.sizeRatioLimit, 2)
    }

    func testMatchingIsOneToOneDeterministicAndFallsBackToLegacyIndex() {
        let face = box(0.4)
        let near = record(box(0.42))
        let nearer = record(box(0.41))
        let matches = PersonMatcher.match([near, nearer], faces: [face])
        XCTAssertEqual(matches, [.init(person: nearer.id, faceIndex: 0)], "한 얼굴은 가장 가까운 사람 하나만")
        XCTAssertEqual(PersonMatcher.match([near, nearer], faces: [face]), matches, "같은 입력은 같은 결과")
        let twoFaces = PersonMatcher.match([near, nearer], faces: [face, box(0.44)])
        XCTAssertEqual(twoFaces.map(\.faceIndex), [0, 1], "얼굴 인덱스 순서로 돌려준다")
        XCTAssertEqual(twoFaces.first { $0.person == nearer.id }?.faceIndex, 0)
        XCTAssertEqual(twoFaces.first { $0.person == near.id }?.faceIndex, 1)
        let legacy = PersonRecord(id: PersonID.legacy(index: 1), legacyIndex: 1)
        XCTAssertEqual(
            PersonMatcher.match([legacy], faces: [box(0.1), box(0.7)]), [.init(person: legacy.id, faceIndex: 1)])
        XCTAssertTrue(PersonMatcher.match([legacy], faces: [box(0.1)]).isEmpty, "인덱스가 범위 밖이면 짝 없음")
        let anchored = record(box(0.7))
        XCTAssertEqual(
            PersonMatcher.match([legacy, anchored], faces: [box(0.1), box(0.7)]).map(\.person), [anchored.id],
            "anchor가 먼저 얼굴을 가져가면 legacy 기록은 짝이 없다")
        var people = PeopleAdjustments(individuals: [anchored])
        XCTAssertEqual(people.personID(at: PersonAnchor(faceBox: box(0.72))), anchored.id)
        people.individuals.append(legacy)
        XCTAssertNil(people.personID(at: PersonAnchor(faceBox: box(0.1))), "anchor 없는 기록은 anchor로 찾지 못한다")
    }

    func testPersonIDAtAnchorPicksTheNearestRecordForOverlappingFaces() {
        // 앞사람(폭 0.10, 중심 0.45)과 뒷사람(폭 0.08, 중심 0.47)은 서로의 허용치 안에 있다.
        let front = PersonAnchor(x: 0.45, y: 0.5, width: 0.10)
        let back = PersonAnchor(x: 0.47, y: 0.5, width: 0.08)
        XCTAssertTrue(PersonMatcher.isMatch(front, back))
        let first = PersonRecord(anchor: front)
        let second = PersonRecord(anchor: back)
        let people = PeopleAdjustments(individuals: [first, second])
        XCTAssertEqual(people.personID(at: back), second.id, "배열 앞 기록이 아니라 가장 가까운 기록")
        XCTAssertEqual(people.personID(at: front), first.id)
        let faces = [
            NormalizedRect(x: 0.40, y: 0.45, width: 0.10, height: 0.10),
            NormalizedRect(x: 0.43, y: 0.46, width: 0.08, height: 0.08),
        ]
        XCTAssertEqual(
            PersonMatcher.match(people.individuals, faces: faces),
            [.init(person: first.id, faceIndex: 0), .init(person: second.id, faceIndex: 1)], "렌더 짝짓기와 같은 사람")
        let twin = PersonRecord(anchor: back)
        XCTAssertEqual(
            PeopleAdjustments(individuals: [twin, second]).personID(at: back), twin.id, "같은 거리는 배열 순서")
    }

    func testLegacyIDNeverCrashesOnOutOfRangeIndices() {
        let last = PersonID.legacy(index: PersonID.legacyIndexRange.upperBound)
        XCTAssertEqual(PersonID.legacy(index: Int.max), last)
        XCTAssertEqual(PersonID.legacy(index: -1), last, "음수는 어느 얼굴과도 짝이 되지 않는 마지막 값으로 모은다")
        XCTAssertNotEqual(PersonID.legacy(index: 0), last)
        XCTAssertEqual(PersonID.legacy(index: 7).rawValue.uuidString, "B0000000-0000-0000-0000-000000000007")
    }
}
