import Foundation
import MellowShared

/// 원자적으로 쓰고, 읽을 수 없는 파일은 복구 사본을 남긴 뒤에만 덮어쓴다.
public final class JSONSessionStore: SessionStore, @unchecked Sendable {
    public let fileURL: URL
    private let lock = NSLock()
    private var _recoveryFileURL: URL?

    public init(fileURL: URL) {
        self.fileURL = fileURL
    }

    /// 읽을 수 없던 세션을 보관한 사본. 복구 사본이 없으면 nil.
    public var recoveryFileURL: URL? {
        lock.withLock { _recoveryFileURL }
    }

    public func load() throws -> SessionSnapshot? {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return nil }
        let data = try Data(contentsOf: fileURL)
        do {
            return SessionFileMapper.snapshot(from: try SessionFile.decode(data))
        } catch {
            try preserveUnreadableFile()
            throw MellowError.sessionUnreadable
        }
    }

    public func save(_ snapshot: SessionSnapshot) throws {
        do {
            let data = try SessionFile.encode(SessionFileMapper.file(from: snapshot))
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: fileURL, options: Self.writeOptions)
        } catch {
            throw MellowError.sessionWriteFailed(reason: error.localizedDescription)
        }
    }

    private static var writeOptions: Data.WritingOptions {
        #if os(iOS)
            return [.atomic, .completeFileProtectionUnlessOpen]
        #else
            return [.atomic]
        #endif
    }

    private func preserveUnreadableFile() throws {
        let backup = fileURL.deletingLastPathComponent()
            .appendingPathComponent("session-recovery-\(UUID().uuidString).json")
        do {
            try FileManager.default.copyItem(at: fileURL, to: backup)
        } catch {
            throw MellowError.sessionWriteFailed(reason: error.localizedDescription)
        }
        lock.withLock { _recoveryFileURL = backup }
    }
}
