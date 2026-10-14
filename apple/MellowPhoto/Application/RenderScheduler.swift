import CoreGraphics
import Foundation

/// 디바운스와 세대 토큰으로 마지막 요청만 완료시킨다.
@MainActor
final class RenderScheduler {
    private let debounce: Duration
    private var task: Task<Void, Never>?
    private var generation = 0

    init(debounce: Duration) {
        self.debounce = debounce
    }

    func schedule(
        _ render: @escaping @Sendable () async throws -> CGImage,
        completion: @escaping @MainActor (Result<CGImage, Error>) -> Void
    ) {
        task?.cancel()
        generation += 1
        let ticket = generation
        task = Task {
            do {
                try await Task.sleep(for: debounce)
            } catch {
                return
            }
            let result: Result<CGImage, Error>
            do {
                result = .success(try await render())
            } catch {
                result = .failure(error)
            }
            guard !Task.isCancelled, ticket == generation else { return }
            completion(result)
        }
    }

    func cancel() {
        task?.cancel()
        generation += 1
    }
}
