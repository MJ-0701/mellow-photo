import CoreImage
import MellowShared

/// 최근 사용 순서를 유지하는 작은 캐시. 미리보기 CIImage는 수 MB라 몇 장만 든다.
struct PreviewCache {
    /// 용량이 0 이하로 설정돼도 방금 준비한 사진 한 장은 남긴다.
    private static let minimumCapacity = 1

    private(set) var capacity: Int
    private var images: [PhotoID: CIImage] = [:]
    private var order: [PhotoID] = []

    init(capacity: Int) {
        self.capacity = max(Self.minimumCapacity, capacity)
    }

    var ids: [PhotoID] { order }

    mutating func image(for id: PhotoID) -> CIImage? {
        guard let image = images[id] else { return nil }
        touch(id)
        return image
    }

    mutating func insert(_ image: CIImage, for id: PhotoID) {
        images[id] = image
        touch(id)
        while order.count > capacity, let oldest = order.first {
            order.removeFirst()
            images[oldest] = nil
        }
    }

    mutating func remove(_ id: PhotoID) {
        images[id] = nil
        order.removeAll { $0 == id }
    }

    private mutating func touch(_ id: PhotoID) {
        order.removeAll { $0 == id }
        order.append(id)
    }
}
