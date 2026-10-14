import Foundation

public enum LibraryPolicy {
    public static let presetNameLimit = 30

    /// 물리 메모리 기준 동시 편집 사진 수.
    public static func maxPhotos(physicalMemory: UInt64) -> Int {
        let gigabyte: UInt64 = 1 << 30
        if physicalMemory < 4 * gigabyte { return 12 }
        if physicalMemory < 8 * gigabyte { return 24 }
        return 40
    }

    public static var maxPhotosForCurrentDevice: Int {
        maxPhotos(physicalMemory: ProcessInfo.processInfo.physicalMemory)
    }
}
