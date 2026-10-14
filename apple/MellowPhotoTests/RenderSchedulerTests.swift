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
            scheduler.schedule {
                try renderer.makeCGImage(CIImage(color: .red).cropped(to: CGRect(x: 0, y: 0, width: index, height: 1)))
            } completion: { result in
                if case .success(let image) = result { completed.append(image.width) }
            }
        }
        try await Task.sleep(for: .milliseconds(300))
        XCTAssertEqual(completed, [3])
    }

    func testCancelDropsPendingWork() async throws {
        let scheduler = RenderScheduler(debounce: .milliseconds(20))
        var calls = 0
        scheduler.schedule {
            throw MellowError.renderFailed
        } completion: { _ in
            calls += 1
        }
        scheduler.cancel()
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertEqual(calls, 0)
    }
}
