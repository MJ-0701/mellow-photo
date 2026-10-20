import CoreImage
import MellowRendering
import MellowShared
import XCTest

@testable import Mellow_Photo

@MainActor
final class RenderSchedulerTests: XCTestCase {
    func testOnlyLatestRequestCompletes() async throws {
        let scheduler = RenderScheduler(debounce: .milliseconds(20))
        let renderer = Renderer()
        var completed: [Int] = []
        for index in 1...3 {
            scheduler.schedule(render: {
                try renderer.makeCGImage(CIImage(color: .red).cropped(to: CGRect(x: 0, y: 0, width: index, height: 1)))
            }) { result in
                if case .success(let image) = result { completed.append(image.width) }
            }
        }
        try await Task.sleep(for: .milliseconds(300))
        XCTAssertEqual(completed, [3])
    }

    func testCancelDropsPendingWork() async throws {
        let scheduler = RenderScheduler(debounce: .milliseconds(20))
        var calls = 0
        scheduler.schedule(render: {
            throw MellowError.renderFailed
        }) { _ in
            calls += 1
        }
        scheduler.cancel()
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertEqual(calls, 0)
    }

    /// 준비(캐시에서 밀려난 사진 다시 준비)를 기다리는 동안 취소된 요청은 렌더하지 않는다.
    /// 파이프라인은 직렬이라 버릴 렌더가 돌면 다음 사진 선택의 렌더가 그만큼 늦는다.
    func testCancelWhilePreparingSkipsRender() async throws {
        let scheduler = RenderScheduler(debounce: .milliseconds(1))
        let entered = AsyncStream<Void>.makeStream()
        let gate = AsyncStream<Void>.makeStream()
        let renders = AnalysisLog()
        var completions = 0
        scheduler.schedule(
            prepare: {
                entered.continuation.yield()
                for await _ in gate.stream { break }
            },
            render: {
                renders.calls += 1
                throw MellowError.renderFailed
            },
            completion: { _ in completions += 1 })
        for await _ in entered.stream { break }
        scheduler.cancel()
        gate.continuation.yield()
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertEqual(renders.calls, 0, "취소된 요청은 준비가 끝나도 렌더하지 않는다")
        XCTAssertEqual(completions, 0)
    }

    func testPrepareRunsBeforeRender() async throws {
        let scheduler = RenderScheduler(debounce: .milliseconds(1))
        let order = StepLog()
        var completed = false
        scheduler.schedule(
            prepare: { order.append("prepare") },
            render: {
                order.append("render")
                let pixel = CIImage(color: .red).cropped(to: CGRect(x: 0, y: 0, width: 1, height: 1))
                return try Renderer().makeCGImage(pixel)
            },
            completion: { _ in completed = true })
        try await waitUntil { completed }
        XCTAssertEqual(order.entries, ["prepare", "render"])
    }
}

/// 렌더 일정의 단계 순서를 모은다.
private final class StepLog: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: [String] = []
    var entries: [String] { lock.withLock { stored } }
    func append(_ entry: String) { lock.withLock { stored.append(entry) } }
}
