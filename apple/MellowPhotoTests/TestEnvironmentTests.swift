import MachO
import XCTest

/// 테스트 실행 환경 자체를 확인한다.
final class TestEnvironmentTests: XCTestCase {
    /// iOS 18 시뮬레이터의 스레드 성능 검사기(libRPAC)는 Core Image 타일 렌더 중 자기 내부에서 죽는다.
    /// project.yml의 postGenCommand가 테스트 액션에서 끄므로 테스트 프로세스에 올라오면 안 된다.
    func testThreadPerformanceCheckerIsNotLoaded() {
        let loaded = (0..<_dyld_image_count()).map { String(cString: _dyld_get_image_name($0)) }
        XCTAssertFalse(loaded.contains { $0.hasSuffix("/libRPAC.dylib") }, "스레드 성능 검사기가 테스트에 올라왔다")
    }
}
