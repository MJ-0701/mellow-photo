import Foundation

/// 같은 사람 판정 기준.
/// 좌표는 정규화 얼굴 상자(원본 기준)라 해상도·자르기·회전과 무관하다.
public enum PersonMatching {
    /// 중심 거리 허용치.
    /// 두 폭 중 큰 쪽에 대한 비율이다.
    public static let centerTolerance = 0.5
    /// 폭 비(큰 쪽 / 작은 쪽) 상한.
    public static let sizeRatioLimit = 2.0
}

/// 저장된 사람 기록과 이번에 찾은 얼굴을 1:1로 짝짓는다.
/// 결정적이다.
public enum PersonMatcher {
    public struct Match: Equatable, Sendable {
        public var person: PersonID
        public var faceIndex: Int

        public init(person: PersonID, faceIndex: Int) {
            self.person = person
            self.faceIndex = faceIndex
        }
    }

    private struct Candidate {
        let distance: Double
        let personIndex: Int
        let faceIndex: Int
    }

    /// 두 anchor가 같은 사람인지(거리·크기 조건).
    public static func isMatch(_ a: PersonAnchor, _ b: PersonAnchor) -> Bool {
        distance(a, b) != nil
    }

    /// 조건을 만족하면 큰 폭 대비 중심 거리, 아니면 nil.
    static func distance(_ a: PersonAnchor, _ b: PersonAnchor) -> Double? {
        let larger = max(a.width, b.width)
        let smaller = min(a.width, b.width)
        guard smaller > 0, larger / smaller <= PersonMatching.sizeRatioLimit else { return nil }
        let normalized = hypot(a.x - b.x, a.y - b.y) / larger
        return normalized <= PersonMatching.centerTolerance ? normalized : nil
    }

    /// 후보 (사람, 얼굴) 쌍을 거리 오름차순으로 고르며 이미 쓴 사람·얼굴은 건너뛴다.
    /// 동률은 사람 배열 순서, 얼굴 인덱스 순서로 정한다.
    /// anchor 없는 기록(legacyIndex)은 그 인덱스의 얼굴이 있으면 허용치 거리의 후보가 된다(실제 anchor가 우선).
    /// 결과는 얼굴 인덱스 순서다.
    public static func match(_ people: [PersonRecord], faces: [NormalizedRect]) -> [Match] {
        let anchors = faces.map(PersonAnchor.init(faceBox:))
        var candidates: [Candidate] = []
        for (personIndex, person) in people.enumerated() {
            if let anchor = person.anchor {
                for (faceIndex, faceAnchor) in anchors.enumerated() {
                    if let distance = distance(anchor, faceAnchor) {
                        candidates.append(Candidate(distance: distance, personIndex: personIndex, faceIndex: faceIndex))
                    }
                }
            } else if let index = person.legacyIndex, faces.indices.contains(index) {
                candidates.append(
                    Candidate(distance: PersonMatching.centerTolerance, personIndex: personIndex, faceIndex: index))
            }
        }
        candidates.sort {
            ($0.distance, $0.personIndex, $0.faceIndex) < ($1.distance, $1.personIndex, $1.faceIndex)
        }
        var usedPeople = Set<Int>()
        var usedFaces = Set<Int>()
        var matches: [Match] = []
        for candidate in candidates
        where !usedPeople.contains(candidate.personIndex) && !usedFaces.contains(candidate.faceIndex) {
            usedPeople.insert(candidate.personIndex)
            usedFaces.insert(candidate.faceIndex)
            matches.append(Match(person: people[candidate.personIndex].id, faceIndex: candidate.faceIndex))
        }
        return matches.sorted { $0.faceIndex < $1.faceIndex }
    }
}
