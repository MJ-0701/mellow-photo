import Foundation
import MellowShared

/// 원자적으로 쓰고, 읽을 수 없는 파일은 복구 사본을 남긴 뒤에만 덮어쓴다.
public final class JSONSessionStore: SessionStore, @unchecked Sendable {
    public let fileURL: URL
    private let lock = NSLock()
    private var _recoveryFileURL: URL?
    /// 읽을 수 없는 파일을 발견했지만 아직 복구 사본을 만들지 못했다. 이 동안은 덮어쓰지 않는다.
    private var needsRecoveryCopy = false

    public init(fileURL: URL) {
        self.fileURL = fileURL
    }

    /// 읽을 수 없던 세션을 보관한 사본. 복구 사본이 없으면 nil.
    public var recoveryFileURL: URL? {
        lock.withLock { _recoveryFileURL }
    }

    /// 읽기·해석 실패는 모두 sessionUnreadable이다. 복구 사본 실패는 save가 다시 시도한다.
    public func load() throws -> SessionSnapshot? {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return nil }
        do {
            let data = try Data(contentsOf: fileURL)
            return SessionFileMapper.snapshot(from: try SessionFile.decode(data))
        } catch {
            lock.withLock { needsRecoveryCopy = true }
            try? preserveUnreadableFile()
            throw MellowError.sessionUnreadable
        }
    }

    /// 밀린 복구 사본이 있으면 먼저 만든다. 만들 수 없으면 아무것도 쓰지 않는다.
    public func save(_ snapshot: SessionSnapshot) throws {
        if lock.withLock({ needsRecoveryCopy }) {
            try preserveUnreadableFile()
        }
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
        lock.withLock {
            _recoveryFileURL = backup
            needsRecoveryCopy = false
        }
    }
}
