import Foundation

/// 완성된 파일을 사용자가 보는 곳(사진 앱, 폴더)으로 옮긴다. 구현은 앱 타깃에 있다.
public protocol ExportDestination: Sendable {
    func publish(fileURL: URL, suggestedName: String) async throws
}
