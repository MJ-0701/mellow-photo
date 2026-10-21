import CoreImage
import MellowShared

/// 분석기 원래 해상도의 회색 마스크를 CPU 8비트 바이트로 한 번 읽어 두고 이미지 정규화 좌표로 표본한다.
/// 배치는 BackgroundStage.personMask(_:extent:feather: 0)와 같다(마스크를 이미지에 가로·세로 따로 늘림).
/// 표본은 이웃 네 픽셀 중심의 쌍선형 보간이다(Core Image가 늘린 마스크를 표본하는 방식과 같다).
/// 마스크 밖 좌표는 가장자리 픽셀 값이다(clampedToExtent와 같다).
struct MaskSampler {
    /// 마스크 픽셀 수.
    let width: Int
    let height: Int
    /// 행 우선, 맨 위 행부터(Core Image의 가장 큰 y가 첫 행).
    private let bytes: [UInt8]

    /// 바이트 0…255를 0…1로 바꾸는 나눗수.
    private static let byteScale: Double = 255
    /// 픽셀 중심은 픽셀 경계에서 반 픽셀 안쪽이다.
    private static let pixelCenter: Double = 0.5

    /// bytes 개수가 width × height가 아니거나 크기가 0이면 nil이다.
    init?(width: Int, height: Int, bytes: [UInt8]) {
        guard width > 0, height > 0, bytes.count == width * height else { return nil }
        self.width = width
        self.height = height
        self.bytes = bytes
    }

    /// mask의 extent 전체를 renderer로 한 번 읽는다. 읽지 못하면 nil이다.
    init?(mask: CIImage, renderer: Renderer) {
        guard let read = try? renderer.readMaskBytes(mask) else { return nil }
        self.init(width: read.width, height: read.height, bytes: read.bytes)
    }

    /// 이미지 정규화 좌표(원점 왼쪽 아래)의 마스크 값(0…1).
    /// 유한하지 않은 좌표는 0이다.
    func value(at point: NormalizedPoint) -> Double {
        guard point.x.isFinite, point.y.isFinite else { return 0 }
        let column = Self.clamped(point.x * Double(width) - Self.pixelCenter, count: width)
        let row = Self.clamped(point.y * Double(height) - Self.pixelCenter, count: height)
        let left = Int(column.rounded(.down))
        let bottom = Int(row.rounded(.down))
        let right = min(left + 1, width - 1)
        let top = min(bottom + 1, height - 1)
        let tx = column - Double(left)
        let ty = row - Double(bottom)
        let lower = Self.mix(byte(column: left, row: bottom), byte(column: right, row: bottom), tx)
        let upper = Self.mix(byte(column: left, row: top), byte(column: right, row: top), tx)
        return Self.mix(lower, upper, ty) / Self.byteScale
    }

    /// 아래에서 row번째 행의 바이트.
    private func byte(column: Int, row: Int) -> Double {
        Double(bytes[(height - 1 - row) * width + column])
    }

    /// 픽셀 중심 좌표를 첫 중심과 마지막 중심 사이로 자른다.
    private static func clamped(_ value: Double, count: Int) -> Double {
        min(max(value, 0), Double(count - 1))
    }

    private static func mix(_ first: Double, _ second: Double, _ t: Double) -> Double {
        first + (second - first) * t
    }
}
