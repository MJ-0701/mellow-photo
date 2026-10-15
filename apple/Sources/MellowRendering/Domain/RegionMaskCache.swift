import CoreImage
import Foundation

/// 다각형 마스크 비트맵 캐시. 같은 사진을 다시 렌더할 때 CGContext 래스터를 다시 그리지 않는다.
/// RenderContext가 Sendable이라 잠금으로 보호한다. 같은 키를 동시에 처음 물으면 둘 다 그릴 수 있지만 결과는 같다.
final class RegionMaskCache: @unchecked Sendable {
    /// 항목 수 상한. 얼굴 몇 개 × 영역 4종(피부·눈·입술·치아) × 해상도 2가지(미리보기·원본)를 담는다. 넘으면 모두 비운다.
    static let maximumEntries = 32

    private let lock = NSLock()
    private var masks: [RegionMaskKey: CIImage] = [:]

    var count: Int { lock.withLock { masks.count } }

    func mask(for key: RegionMaskKey, make: () -> CIImage) -> CIImage {
        if let cached = lock.withLock({ masks[key] }) {
            return cached
        }
        let made = make()
        lock.withLock {
            if masks.count >= Self.maximumEntries {
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
