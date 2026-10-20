import CoreGraphics
import Foundation

/// 디바운스와 세대 토큰으로 마지막 요청만 완료시킨다.
/// 요청은 준비(prepare) 뒤 렌더(render) 순서로 돈다.
/// 준비 중에 취소된 요청은 렌더하지 않는다.
@MainActor
final class RenderScheduler {
    private let debounce: Duration
    private var task: Task<Void, Never>?
    private var generation = 0

    init(debounce: Duration) {
        self.debounce = debounce
    }

    func schedule(
        prepare: @escaping @Sendable () async throws -> Void = {},
        render: @escaping @Sendable () async throws -> CGImage,
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
                try await prepare()
                // 준비를 기다리는 동안 취소됐으면 버릴 렌더로 직렬 파이프라인을 붙잡지 않는다.
                try Task.checkCancellation()
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
