import Foundation
import MellowShared

/// 가져온 사진의 작업 사본을 보관하는 폴더. 사진 앱·사용자 파일 원본은 절대 건드리지 않는다.
public struct WorkingCopyStore: Sendable {
    public let directory: URL

    public init(directory: URL) {
        self.directory = directory
    }

    public func prepareDirectory() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var folder = directory
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try folder.setResourceValues(values)
    }

    /// 새 위치에 없고 출시본 iPhone 앱이 쓰던 상위 폴더에만 있으면 그 경로를 돌려준다.
    public func url(for filename: String) -> URL {
        let current = directory.appendingPathComponent(filename)
        if FileManager.default.fileExists(atPath: current.path) { return current }
        let legacy = directory.deletingLastPathComponent().appendingPathComponent(filename)
        return FileManager.default.fileExists(atPath: legacy.path) ? legacy : current
    }

    /// 임시 파일을 사본 폴더로 옮기고 파일 이름을 돌려준다. iOS에서는 파일 보호를 건다.
    public func adopt(temporaryFile: URL, as id: PhotoID) throws -> String {
        let fileExtension = temporaryFile.pathExtension.isEmpty ? "image" : temporaryFile.pathExtension
        let filename = "\(id.rawValue.uuidString).\(fileExtension)"
        let destination = url(for: filename)
        try FileManager.default.moveItem(at: temporaryFile, to: destination)
        #if os(iOS)
            try FileManager.default.setAttributes(
                [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
                ofItemAtPath: destination.path)
        #endif
        return filename
    }

    public func remove(filename: String) throws {
        let target = url(for: filename)
        guard FileManager.default.fileExists(atPath: target.path) else { return }
        try FileManager.default.removeItem(at: target)
    }
}
