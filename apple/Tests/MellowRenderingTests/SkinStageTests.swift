import CoreImage
import MellowShared
import XCTest

@testable import MellowRendering

final class SkinStageTests: XCTestCase {
    typealias Support = RenderingTestSupport

    private let size = Double(SyntheticFace.size)

    private func render(
        _ synthetic: SyntheticFace, skin: SkinAdjustments, blemishes: [BlemishSpot] = [], faces: [FaceGeometry]? = nil,
        targetFace: Int? = nil
    ) throws -> CIImage {
        var recipe = EditRecipe()
        recipe.portrait.skin = skin
        recipe.portrait.targetFace = targetFace
        let context = RenderContext(
            extent: synthetic.image.extent, recipe: recipe, faces: faces ?? [synthetic.face], tuning: RenderTuning(),
            blemishes: blemishes)
        return try SkinStage().apply(synthetic.image, in: context)
    }

    private func spot(_ center: CGPoint, face: Int = 0) -> BlemishSpot {
        BlemishSpot(
            x: Double(center.x) / size, y: Double(center.y) / size, radius: Double(SyntheticFace.blemishRadius) / size,
            faceIndex: face)
    }

    func testNoSmoothingAndNoAutoBlemishIsIdentity() throws {
        let synthetic = SyntheticFace.make(withBlemishes: true)
        let output = try render(synthetic, skin: SkinAdjustments())
        XCTAssertEqual(try Support.bytes(output), try Support.bytes(synthetic.image))
    }

    func testSmoothingLeavesEyesAndNonSkinUntouchedAndChangesCheeks() throws {
        let synthetic = SyntheticFace.make()
        let before = try Support.grid(synthetic.image)
        let after = try Support.grid(render(synthetic, skin: SkinAdjustments(smoothing: 1)))
        for point in [
            SyntheticFace.leftEye, SyntheticFace.rightEye, SyntheticFace.mouth, SyntheticFace.backgroundInsideContour,
            SyntheticFace.outside,
        ] {
            XCTAssertEqual(after.rgba(point), before.rgba(point), "\(point)")
        }
        let patch = SyntheticFace.skinPatch
        var changed = 0
        for y in Int(patch.minY)..<Int(patch.maxY) {
            for x in Int(patch.minX)..<Int(patch.maxX) {
                let point = CGPoint(x: x, y: y)
                if after.rgba(point) != before.rgba(point) {
                    changed += 1
                }
            }
        }
        XCTAssertGreaterThan(changed, Int(patch.width * patch.height) / 2, "볼 픽셀 대부분이 바뀐다")
    }

    func testSmoothingCutsMidBandAndKeepsPores() throws {
        let synthetic = SyntheticFace.make()
        let output = try render(synthetic, skin: SkinAdjustments(smoothing: 1))
        let radii = FrequencySeparation.radii(
            faceWidth: FaceRegions.faceWidth(synthetic.face, extent: synthetic.image.extent), tuning: RenderTuning())
        let patch = SyntheticFace.skinPatch
        let before = try Support.bandVariances(synthetic.image, in: patch, fineRadius: radii.fine, midRadius: radii.mid)
        let after = try Support.bandVariances(output, in: patch, fineRadius: radii.fine, midRadius: radii.mid)
        XCTAssertLessThan(after.mid, before.mid * 0.6, "마스크 안 중간 대역이 준다")
        XCTAssertEqual(after.fine / before.fine, 1, accuracy: 0.1, "모공 대역은 ±10% 안")
    }

    func testAutoBlemishHealsPlantedSpots() throws {
        let synthetic = SyntheticFace.make(withBlemishes: true)
        let before = try Support.grid(synthetic.image)
        let planted = SyntheticFace.blemishes.map { spot($0) }
        let after = try Support.grid(render(synthetic, skin: SkinAdjustments(autoBlemish: true), blemishes: planted))
        for center in SyntheticFace.blemishes {
            XCTAssertGreaterThanOrEqual(Int(after.red(center)), Int(before.red(center)) + 20, "\(center)의 잡티가 밝아진다")
        }
    }

    func testHealSourceAvoidsNoseAndLips() throws {
        let base = SyntheticFace.make()
        // 코 왼쪽 피부. 얼굴 가운데 쪽으로 2.5r(15.75px) 옮기면 코 다각형 안이다.
        let besideNose = CGPoint(x: 226, y: 200)
        // 입술 안. 양쪽 어느 방향으로 옮겨도 입술이다.
        let inLips = CGPoint(x: 256, y: 150)
        let spotColor = CIImage(color: CIColor(red: 0.56, green: 0.32, blue: 0.27))
        let radii = CGSize(width: SyntheticFace.blemishRadius, height: SyntheticFace.blemishRadius)
        let spotMask = Support.hardEllipse(center: besideNose, radii: radii, extent: SyntheticFace.extent)
        let image = spotColor.applyingFilter(
            "CIBlendWithMask", parameters: [kCIInputBackgroundImageKey: base.image, kCIInputMaskImageKey: spotMask]
        ).cropped(to: SyntheticFace.extent)
        var recipe = EditRecipe()
        recipe.portrait.skin.autoBlemish = true
        let context = RenderContext(
            extent: image.extent, recipe: recipe, faces: [base.face], tuning: RenderTuning(),
            blemishes: [spot(besideNose), spot(inLips)])
        let heals = SkinStage.healSpots(in: context)
        XCTAssertEqual(heals.count, 1, "양쪽 원본이 다 입술인 잡티는 건너뛴다")
        let heal = try XCTUnwrap(heals.first)
        XCTAssertLessThan(heal.sourceX, heal.x, "가운데 쪽은 코라 바깥쪽 피부를 원본으로 쓴다")
        let before = try Support.grid(image)
        let after = try Support.grid(SkinStage().apply(image, in: context))
        XCTAssertGreaterThanOrEqual(Int(after.red(besideNose)), Int(before.red(besideNose)) + 20)
        XCTAssertEqual(after.rgba(inLips), before.rgba(inLips))
    }

    func testAutoBlemishHealsOnlyTargetFace() throws {
        let synthetic = SyntheticFace.make(withBlemishes: true)
        let first = SyntheticFace.blemishes[0]
        let second = SyntheticFace.blemishes[1]
        let blemishes = [spot(first, face: 0), spot(second, face: 1)]
        let before = try Support.grid(synthetic.image)
        let output = try render(
            synthetic, skin: SkinAdjustments(autoBlemish: true), blemishes: blemishes,
            faces: [synthetic.face, synthetic.face], targetFace: 0)
        let after = try Support.grid(output)
        XCTAssertGreaterThanOrEqual(Int(after.red(first)), Int(before.red(first)) + 20)
        XCTAssertEqual(after.rgba(second), before.rgba(second), "대상이 아닌 얼굴의 잡티는 그대로")
    }
}
