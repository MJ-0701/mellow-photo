import CoreImage
import XCTest

@testable import MellowRendering

final class MaskBuilderTests: XCTestCase {
    typealias Support = RenderingTestSupport

    private let extent = CGRect(x: 0, y: 0, width: 512, height: 512)
    private let center = CGPoint(x: 256, y: 256)
    /// 큰 타원과 떨어진 곳의 작은 타원. 같은 strength라 한 그래프에서 합쳐지기 쉽다.
    private let smallRect = CGRect(x: 30, y: 30, width: 20, height: 20)

    private func withSmallEllipse(_ mask: CIImage) -> CIImage {
        MaskBuilder.ellipse(smallRect, extent: extent)
            .applyingFilter("CIMaximumCompositing", parameters: [kCIInputBackgroundImageKey: mask])
            .cropped(to: extent)
    }

    func testLargeEllipseProfileIsUnchangedByAnotherEllipseInTheSameGraph() throws {
        let radius: CGFloat = 150
        let rect = CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)
        let alone = try Support.grid(MaskBuilder.ellipse(rect, extent: extent))
        let combined = try Support.grid(withSmallEllipse(MaskBuilder.ellipse(rect, extent: extent)))
        for fraction: CGFloat in [0, 0.5, 0.65, 0.8, 0.95] {
            let point = CGPoint(x: center.x + fraction * radius, y: center.y)
            let difference = abs(Int(alone.red(point)) - Int(combined.red(point)))
            XCTAssertLessThanOrEqual(
                difference, 2, "r = \(fraction): 단독 \(alone.red(point)), 합성 \(combined.red(point))")
        }
    }

    func testNonCircularEllipseKeepsSolidCoreAndEdge() throws {
        let radii = CGSize(width: 100, height: 50)
        let rect = CGRect(
            x: center.x - radii.width, y: center.y - radii.height, width: radii.width * 2, height: radii.height * 2)
        let grid = try Support.grid(withSmallEllipse(MaskBuilder.ellipse(rect, extent: extent)))
        XCTAssertGreaterThanOrEqual(grid.red(CGPoint(x: center.x + 0.6 * radii.width, y: center.y)), 250)
        XCTAssertGreaterThanOrEqual(grid.red(CGPoint(x: center.x, y: center.y + 0.6 * radii.height)), 250)
        XCTAssertLessThanOrEqual(grid.red(CGPoint(x: rect.maxX + 2, y: center.y)), 5)
        XCTAssertLessThanOrEqual(grid.red(CGPoint(x: center.x, y: rect.maxY + 2)), 5)
    }
}
