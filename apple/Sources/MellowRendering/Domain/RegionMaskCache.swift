import CoreImage
import Foundation

/// 다각형 마스크 비트맵 캐시. 같은 사진을 다시 렌더할 때 CGContext 래스터를 다시 그리지 않는다.
/// RenderContext가 Sendable이라 잠금으로 보호한다. 같은 키를 동시에 처음 물으면 둘 다 그릴 수 있지만 결과는 같다.
final class RegionMaskCache: @unchecked Sendable {
    /// 얼굴 하나가 한 해상도에서 쓰는 다각형 비트맵 수의 상한. 피부·눈·입술·치아·아이섀도·왼눈썹·오른눈썹·눈입(몸 피부) 8개에 여유 1.
    /// 블러셔·쉐딩·하이라이터·주름은 피부 비트맵을, 립은 입술 비트맵을 함께 쓴다. 눈입 비트맵은 사진마다 하나라 얼굴당으로는 넉넉하다.
    static let entriesPerFacePerResolution = 9
    /// 미리보기와 원본 두 해상도.
    static let resolutions = 2
    /// 얼굴이 적어도 이만큼은 담는다(D의 고정 상한).
    static let minimumEntries = 32

    /// 얼굴 수에 맞춘 상한. 비트맵 하나는 긴 변 512 이하 회색이라 최대 256KB다.
    static func capacity(forFaces count: Int) -> Int {
        max(minimumEntries, count * entriesPerFacePerResolution * resolutions)
    }

    /// 항목 수 상한. 넘으면 모두 비운다.
    let maximumEntries: Int

    init(maximumEntries: Int = minimumEntries) {
        self.maximumEntries = maximumEntries
    }

    private let lock = NSLock()
    private var masks: [RegionMaskKey: CIImage] = [:]

    var count: Int { lock.withLock { masks.count } }

    func mask(for key: RegionMaskKey, make: () -> CIImage) -> CIImage {
        if let cached = lock.withLock({ masks[key] }) {
            return cached
        }
        let made = make()
        lock.withLock {
            if masks.count >= maximumEntries {
                masks.removeAll()
            }
            masks[key] = made
        }
        return made
    }

    func removeAll() {
        lock.withLock { masks.removeAll() }
    }
}

/// polygonMask 입력 전체. 다각형 점·넓힘 폭·extent·비트맵 크기가 같으면 같은 비트맵이다.
struct RegionMaskKey: Hashable {
    private let values: [Double]

    init(fill: [[CGPoint]], cut: [[CGPoint]], cutWidth: CGFloat, extent: CGRect, maxDimension: Int) {
        var values = [
            Double(extent.minX), Double(extent.minY), Double(extent.width), Double(extent.height), Double(cutWidth),
            Double(maxDimension), Double(fill.count),
        ]
        for polygon in fill + cut {
            values.append(Double(polygon.count))
            for point in polygon {
                values.append(Double(point.x))
                values.append(Double(point.y))
            }
        }
        self.values = values
    }
}
