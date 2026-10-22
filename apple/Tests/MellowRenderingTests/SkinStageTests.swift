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
        let faces = faces ?? [synthetic.face]
        if let targetFace {
            recipe = Support.restricted(recipe, toFace: targetFace, of: faces)
        }
        let context = RenderContext(
            extent: synthetic.image.extent, recipe: recipe, faces: faces, tuning: RenderTuning(), blemishes: blemishes)
        return try SkinStage().apply(synthetic.image, in: context)
    }

    private func spot(_ center: CGPoint, face: Int = 0) -> BlemishSpot {
        BlemishSpot(
            x: Double(center.x) / size, y: Double(center.y) / size, radius: Double(SyntheticFace.blemishRadius) / size,
            faceIndex: face)
    }

    private func paintSpot(at centers: [CGPoint], over image: CIImage) -> CIImage {
        let spotColor = CIImage(color: CIColor(red: 0.56, green: 0.32, blue: 0.27))
        let radii = CGSize(width: SyntheticFace.blemishRadius, height: SyntheticFace.blemishRadius)
        return centers.reduce(image) { result, center in
            let mask = Support.hardEllipse(center: center, radii: radii, extent: SyntheticFace.extent)
            return spotColor.applyingFilter(
                "CIBlendWithMask", parameters: [kCIInputBackgroundImageKey: result, kCIInputMaskImageKey: mask]
            ).cropped(to: SyntheticFace.extent)
        }
    }

    private func normalized(_ point: CGPoint) -> NormalizedPoint {
        NormalizedPoint(x: Double(point.x) / size, y: Double(point.y) / size)
    }

    private func ellipse(_ center: CGPoint, _ radii: CGSize) -> [NormalizedPoint] {
        (0..<12).map { step in
            let angle = 2 * Double.pi * Double(step) / 12
            return normalized(
                CGPoint(
                    x: center.x + radii.width * CGFloat(cos(angle)), y: center.y + radii.height * CGFloat(sin(angle))))
        }
    }

    /// Vision 윤곽처럼 한쪽 관자놀이에서 턱을 지나 반대쪽까지 17점.
    private func lowerHalfEllipse(_ center: CGPoint, _ radii: CGSize) -> [NormalizedPoint] {
        (0...16).map { step in
            let angle = Double.pi + Double.pi * Double(step) / 16
            return normalized(
                CGPoint(
                    x: center.x + radii.width * CGFloat(cos(angle)), y: center.y + radii.height * CGFloat(sin(angle))))
        }
    }

    /// center 둘레 타원 안 픽셀을 factor배 어둡게 한다(그늘·주름 흉내).
    private func darkened(_ image: CIImage, at center: CGPoint, radii: CGSize, factor: Double) -> CIImage {
        let dim = image.applyingFilter(
            "CIColorMatrix",
            parameters: [
                "inputRVector": CIVector(x: factor, y: 0, z: 0, w: 0),
                "inputGVector": CIVector(x: 0, y: factor, z: 0, w: 0),
                "inputBVector": CIVector(x: 0, y: 0, z: factor, w: 0),
            ])
        let mask = Support.hardEllipse(center: center, radii: radii, extent: SyntheticFace.extent)
        return dim.applyingFilter(
            "CIBlendWithMask", parameters: [kCIInputBackgroundImageKey: image, kCIInputMaskImageKey: mask]
        ).cropped(to: SyntheticFace.extent)
    }

    /// 주름 띠 테스트의 그늘 밝기 배율(선형).
    private static let shadowFactor = 0.6
    /// 밝힌 뒤 기대하는 최소 빨강 증가(바이트).
    private static let liftMinimum = 12

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

    func testTempleSpotWithoutSkinSourceIsSkipped() throws {
        let base = SyntheticFace.make()
        // 피부 타원 가장자리 안쪽의 관자놀이 잡티. 윤곽을 피부 타원에 맞추고 왼쪽 눈을 바깥으로 옮긴 얼굴이다.
        // 가운데 쪽 원본(x 145.75)은 눈, 바깥쪽 원본(x 114.25)은 피부 다각형 밖 배경이다.
        let temple = CGPoint(x: 130, y: 300)
        var face = base.face
        face.landmarks[.faceContour] = lowerHalfEllipse(SyntheticFace.skinCenter, SyntheticFace.skinRadii)
        face.landmarks[.leftEye] = ellipse(CGPoint(x: 155, y: 300), SyntheticFace.eyeRadii)
        let image = paintSpot(at: [temple], over: base.image)
        var recipe = EditRecipe()
        recipe.portrait.skin.autoBlemish = true
        let context = RenderContext(
            extent: image.extent, recipe: recipe, faces: [face], tuning: RenderTuning(), blemishes: [spot(temple)])
        XCTAssertTrue(SkinStage.healSpots(in: context).isEmpty, "피부 안 원본이 없으면 건너뛴다")
        let output = try SkinStage().apply(image, in: context)
        // 실패 시 바이트 배열 전체를 출력하지 않게 Bool로 비교한다.
        XCTAssertTrue(try Support.bytes(output) == Support.bytes(image), "픽셀이 그대로다")
    }

    func testHealSourceAvoidsAnotherBlemish() throws {
        // 첫 잡티의 가운데 쪽 원본(x 191.75)이 이웃 잡티 위다. 이웃의 원본(x 207.75)은 맨 피부다.
        let first = SyntheticFace.blemishes[0]
        let neighbor = CGPoint(x: 192, y: first.y)
        let base = SyntheticFace.make()
        let image = paintSpot(at: [first, neighbor], over: base.image)
        var recipe = EditRecipe()
        recipe.portrait.skin.autoBlemish = true
        let context = RenderContext(
            extent: image.extent, recipe: recipe, faces: [base.face], tuning: RenderTuning(),
            blemishes: [spot(first), spot(neighbor)])
        let heals = SkinStage.healSpots(in: context)
        XCTAssertEqual(heals.count, 2)
        let firstHeal = try XCTUnwrap(heals.first)
        XCTAssertLessThan(firstHeal.sourceX, firstHeal.x, "가운데 쪽은 이웃 잡티라 바깥쪽 피부를 원본으로 쓴다")
        let neighborHeal = try XCTUnwrap(heals.last)
        XCTAssertGreaterThan(neighborHeal.sourceX, neighborHeal.x, "이웃 잡티는 가운데 쪽 피부를 쓴다")
        let before = try Support.grid(image)
        let after = try Support.grid(SkinStage().apply(image, in: context))
        for center in [first, neighbor] {
            XCTAssertGreaterThanOrEqual(Int(after.red(center)), Int(before.red(center)) + 20, "\(center)의 잡티가 밝아진다")
        }
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

    func testSkinRenderReusesCachedMaskAcrossRenders() throws {
        let synthetic = SyntheticFace.make()
        var recipe = EditRecipe()
        recipe.portrait.skin.smoothing = 0.6
        let analysis = PhotoAnalysis(faces: [synthetic.face])
        let context = RenderContext(
            extent: synthetic.image.extent, recipe: recipe, analysis: analysis, tuning: RenderTuning())
        let first = try Support.bytes(SkinStage().apply(synthetic.image, in: context))
        let second = try Support.bytes(SkinStage().apply(synthetic.image, in: context))
        XCTAssertEqual(analysis.regionMasks.count, 1, "얼굴 하나의 피부 다각형은 한 번만 그린다")
        XCTAssertEqual(first, second)
        let fresh = RenderContext(
            extent: synthetic.image.extent, recipe: recipe, faces: [synthetic.face], tuning: RenderTuning())
        XCTAssertEqual(first, try Support.bytes(SkinStage().apply(synthetic.image, in: fresh)), "캐시 여부와 결과가 같다")
    }

    func testDarkCirclesLiftOnlyTheShadowUnderTheEyes() throws {
        let base = SyntheticFace.make()
        let radii = CGSize(width: 30, height: 10)
        var image = darkened(base.image, at: SyntheticFace.underLeftEye, radii: radii, factor: Self.shadowFactor)
        image = darkened(image, at: SyntheticFace.underRightEye, radii: radii, factor: Self.shadowFactor)
        let synthetic = SyntheticFace(image: image, face: base.face)
        let before = try Support.grid(image)
        let after = try Support.grid(render(synthetic, skin: SkinAdjustments(darkCircles: 1)))
        for point in [SyntheticFace.underLeftEye, SyntheticFace.underRightEye] {
            XCTAssertGreaterThanOrEqual(
                Int(after.red(point)), Int(before.red(point)) + Self.liftMinimum, "\(point) 그늘이 밝아진다")
        }
        let outside = [
            SyntheticFace.leftEye, SyntheticFace.scleraPoint, SyntheticFace.cheek, SyntheticFace.mouth,
            SyntheticFace.forehead, SyntheticFace.backgroundInsideContour, SyntheticFace.outside,
        ]
        for point in outside {
            XCTAssertEqual(after.rgba(point), before.rgba(point), "다크서클 띠 밖 \(point)")
        }
        let half = try Support.grid(render(synthetic, skin: SkinAdjustments(darkCircles: 0.5)))
        XCTAssertGreaterThan(half.red(SyntheticFace.underLeftEye), before.red(SyntheticFace.underLeftEye))
        XCTAssertLessThan(half.red(SyntheticFace.underLeftEye), after.red(SyntheticFace.underLeftEye), "0.5는 사이")
    }

    func testNasolabialAndMarionetteLiftTheirOwnFoldOnly() throws {
        let base = SyntheticFace.make()
        let radii = CGSize(width: 7, height: 7)
        var image = base.image
        for center in [SyntheticFace.leftNasolabial, SyntheticFace.leftMarionette] {
            image = darkened(image, at: center, radii: radii, factor: Self.shadowFactor)
        }
        let synthetic = SyntheticFace(image: image, face: base.face)
        let before = try Support.grid(image)
        let nasolabial = try Support.grid(render(synthetic, skin: SkinAdjustments(nasolabial: 1)))
        XCTAssertGreaterThanOrEqual(
            Int(nasolabial.red(SyntheticFace.leftNasolabial)),
            Int(before.red(SyntheticFace.leftNasolabial)) + Self.liftMinimum, "팔자주름이 밝아진다")
        XCTAssertEqual(
            nasolabial.rgba(SyntheticFace.leftMarionette), before.rgba(SyntheticFace.leftMarionette),
            "팔자 슬라이더는 마리오네트 띠를 건드리지 않는다")
        let marionette = try Support.grid(render(synthetic, skin: SkinAdjustments(marionette: 1)))
        XCTAssertGreaterThanOrEqual(
            Int(marionette.red(SyntheticFace.leftMarionette)),
            Int(before.red(SyntheticFace.leftMarionette)) + Self.liftMinimum, "마리오네트 주름이 밝아진다")
        XCTAssertEqual(
            marionette.rgba(SyntheticFace.leftNasolabial), before.rgba(SyntheticFace.leftNasolabial),
            "마리오네트 슬라이더는 팔자 띠를 건드리지 않는다")
        let outside = [
            SyntheticFace.mouth, SyntheticFace.lipPoint, SyntheticFace.philtrum, SyntheticFace.leftEye,
            SyntheticFace.forehead, SyntheticFace.chinTip, SyntheticFace.outside,
        ]
        for point in outside {
            XCTAssertEqual(nasolabial.rgba(point), before.rgba(point), "팔자 띠 밖 \(point)")
            XCTAssertEqual(marionette.rgba(point), before.rgba(point), "마리오네트 띠 밖 \(point)")
        }
    }

    func testGlabellaLiftsBetweenTheBrowsOnly() throws {
        let base = SyntheticFace.make()
        let image = darkened(
            base.image, at: SyntheticFace.glabella, radii: CGSize(width: 8, height: 8), factor: Self.shadowFactor)
        let synthetic = SyntheticFace(image: image, face: base.face)
        let before = try Support.grid(image)
        let after = try Support.grid(render(synthetic, skin: SkinAdjustments(glabella: 1)))
        XCTAssertGreaterThanOrEqual(
            Int(after.red(SyntheticFace.glabella)), Int(before.red(SyntheticFace.glabella)) + Self.liftMinimum)
        let outside = [
            SyntheticFace.leftBrowCenter, SyntheticFace.leftEye, SyntheticFace.forehead, SyntheticFace.bridge,
            SyntheticFace.cheek, SyntheticFace.mouth,
        ]
        for point in outside {
            XCTAssertEqual(after.rgba(point), before.rgba(point), "미간 밖 \(point)")
        }
    }

    /// 그늘 없는 피부에서 띠 안 색차(|ΔCb|·|ΔCr|, 0…1) 상한.
    /// 세 채널에 같은 배율을 곱하므로 색이 번지지 않는다.
    private static let unshadowedFoldMaximumChroma = 0.01
    /// 그늘 없는 피부에서 띠 가중 평균 ΔY(8비트) 상한.
    /// 스펙 G4 1.4의 주름 상한 +0.08이다.
    private static let unshadowedFoldMaximumMeanLift = 0.08 * byteRange

    /// 그늘 없는 피부에서 주름 밝히기는 색 번짐이 없고 띠 평균 밝힘이 상한 안이며 띠 밖은 그대로다(스펙 G4 2.2).
    /// 피부 전용 기준은 띠 안의 어두운 결 얼룩도 주변 피부 수준으로 고르므로 얼룩 픽셀은 6~10바이트 오른다(설계대로).
    /// 그래서 표본 점마다의 바이트 허용치 대신 띠 가중 평균과 색차로 단언한다.
    func testFoldLiftOnUnshadowedSkinAddsNoBlotchOrColorCast() throws {
        let synthetic = SyntheticFace.make()
        let extent = synthetic.image.extent
        let tuning = RenderTuning()
        let before = try Support.grid(synthetic.image)
        let cases: [(String, SkinAdjustments, FaceRegions.RegionMask?)] = [
            (
                "darkCircles", SkinAdjustments(darkCircles: 1),
                FaceRegions.darkCircleMask(face: synthetic.face, extent: extent, tuning: tuning)
            ),
            (
                "nasolabial", SkinAdjustments(nasolabial: 1),
                FaceRegions.nasolabialMask(face: synthetic.face, extent: extent, tuning: tuning)
            ),
            (
                "marionette", SkinAdjustments(marionette: 1),
                FaceRegions.marionetteMask(face: synthetic.face, extent: extent, tuning: tuning)
            ),
            (
                "glabella", SkinAdjustments(glabella: 1),
                FaceRegions.glabellaMask(face: synthetic.face, extent: extent, tuning: tuning)
            ),
        ]
        for (name, skin, region) in cases {
            let band = try Support.grid(XCTUnwrap(region, "\(name) 띠").image)
            let after = try Support.grid(render(synthetic, skin: skin))
            let chroma = DisplayScale.chromaDelta(before, after, weight: band)
            XCTAssertLessThanOrEqual(max(chroma.cb, chroma.cr), Self.unshadowedFoldMaximumChroma, "\(name) 색 번짐 없음")
            XCTAssertLessThanOrEqual(
                DisplayScale.lumaDelta(before, after, weight: band).mean, Self.unshadowedFoldMaximumMeanLift,
                "\(name) 띠 평균 밝힘 상한")
            var outsideDifference = 0
            for y in 0..<before.height {
                for x in 0..<before.width {
                    let point = CGPoint(x: x, y: y)
                    guard band.red(point) == 0 else { continue }
                    let a = before.rgba(point)
                    let b = after.rgba(point)
                    outsideDifference = max(outsideDifference, (0..<3).map { abs(Int(a[$0]) - Int(b[$0])) }.max() ?? 0)
                }
            }
            XCTAssertLessThanOrEqual(outsideDifference, Self.blendRoundingTolerance, "\(name) 띠 밖은 그대로(섞기 반올림만)")
        }
    }

    /// 밝힌 그늘의 (R − G) / (R + G)가 바뀌어도 되는 최대값. 세 채널에 같은 값을 더하면 0.05쯤 줄어 회색 쪽으로 간다.
    private static let liftedChromaTolerance = 0.01

    func testFoldLiftKeepsShadowChroma() throws {
        let base = SyntheticFace.make()
        let radii = CGSize(width: 30, height: 10)
        var image = darkened(base.image, at: SyntheticFace.underLeftEye, radii: radii, factor: Self.shadowFactor)
        image = darkened(image, at: SyntheticFace.underRightEye, radii: radii, factor: Self.shadowFactor)
        let before = try Support.grid(image)
        let after = try Support.grid(
            render(SyntheticFace(image: image, face: base.face), skin: SkinAdjustments(darkCircles: 1)))
        func chroma(_ pixel: [UInt8]) -> Double {
            (Double(pixel[0]) - Double(pixel[1])) / (Double(pixel[0]) + Double(pixel[1]))
        }
        for point in [SyntheticFace.underLeftEye, SyntheticFace.underRightEye] {
            XCTAssertGreaterThan(after.red(point), before.red(point), "\(point) 그늘이 밝아진다")
            XCTAssertEqual(
                chroma(after.rgba(point)), chroma(before.rgba(point)), accuracy: Self.liftedChromaTolerance,
                "\(point) 밝힌 그늘의 색조·채도가 그대로다")
        }
        XCTAssertThrowsError(
            try SkinKernels.shared.foldLift(
                image: image, low: image, wideNumerator: image, wideDenominator: image, amount: 1,
                maxGain: Self.darkeningGain, lumaFloor: RenderTuning().foldLumaFloor, extent: image.extent),
            "배율 상한이 1보다 작으면 그늘을 어둡게 하므로 렌더 실패")
    }

    /// 1보다 작은(어둡게 만드는) 배율 상한.
    private static let darkeningGain = 0.9

    func testMissingLandmarksSkipOnlyThatFold() throws {
        let base = SyntheticFace.make()
        let image = darkened(
            base.image, at: SyntheticFace.glabella, radii: CGSize(width: 8, height: 8), factor: Self.shadowFactor)
        let shaded = darkened(
            image, at: SyntheticFace.leftMarionette, radii: CGSize(width: 7, height: 7), factor: Self.shadowFactor)
        let noNose = SyntheticFace(image: shaded, face: base.face.removing([.nose]))
        let three = SkinAdjustments(nasolabial: 1, marionette: 1, glabella: 1)
        let before = try Support.grid(shaded)
        let after = try Support.grid(render(noNose, skin: three))
        XCTAssertGreaterThanOrEqual(
            Int(after.red(SyntheticFace.glabella)), Int(before.red(SyntheticFace.glabella)) + Self.liftMinimum,
            "코가 없어도 미간은 밝힌다")
        XCTAssertGreaterThanOrEqual(
            Int(after.red(SyntheticFace.leftMarionette)),
            Int(before.red(SyntheticFace.leftMarionette)) + Self.liftMinimum,
            "코가 없어도 마리오네트는 밝힌다(방향 고정)")
        XCTAssertEqual(after.rgba(SyntheticFace.leftNasolabial), before.rgba(SyntheticFace.leftNasolabial), "팔자만 건너뛴다")
        let boxOnly = SyntheticFace.make(landmarks: false)
        let folds = SkinAdjustments(darkCircles: 1, nasolabial: 1, marionette: 1, glabella: 1)
        XCTAssertTrue(try Support.bytes(render(boxOnly, skin: folds)) == Support.bytes(boxOnly.image), "특징점 없으면 그대로")
    }

    /// 번들거림 테스트의 반사광 색. 피부색 가중치(σ 0.04) 안에 들면서 선형 휘도가 피부(0.44)보다 0.28 밝다.
    private static let glossColor = CIColor(red: 0.98, green: 0.84, blue: 0.74)
    /// 번들거림을 눌렀을 때 기대하는 최소 빨강 감소(바이트).
    private static let mattifyMinimum = 15

    func testToneEveningFlattensBlotchesAndKeepsPores() throws {
        let synthetic = SyntheticFace.make()
        let output = try render(synthetic, skin: SkinAdjustments(toneEvening: 1))
        let radii = FrequencySeparation.radii(
            faceWidth: FaceRegions.faceWidth(synthetic.face, extent: synthetic.image.extent), tuning: RenderTuning())
        let patch = SyntheticFace.skinPatch
        let before = try Support.bandVariances(synthetic.image, in: patch, fineRadius: radii.fine, midRadius: radii.mid)
        let after = try Support.bandVariances(output, in: patch, fineRadius: radii.fine, midRadius: radii.mid)
        XCTAssertEqual(after.fine / before.fine, 1, accuracy: 0.1, "모공 대역은 ±10% 안")
        XCTAssertEqual(after.mid / before.mid, 1, accuracy: 0.25, "중간 대역은 피부 보정 0이라 거의 그대로")
        let lowBefore = Support.variance(
            try Support.luma(FrequencySeparation.blurred(synthetic.image, radius: radii.mid).cropped(to: patch)))
        let lowAfter = Support.variance(
            try Support.luma(FrequencySeparation.blurred(output, radius: radii.mid).cropped(to: patch)))
        XCTAssertLessThan(lowAfter, lowBefore * 0.5, "저주파 얼룩이 준다")
        let beforeGrid = try Support.grid(synthetic.image)
        let afterGrid = try Support.grid(output)
        for point in [
            SyntheticFace.leftEye, SyntheticFace.mouth, SyntheticFace.backgroundInsideContour, SyntheticFace.outside,
        ] {
            XCTAssertEqual(afterGrid.rgba(point), beforeGrid.rgba(point), "피부 마스크 밖 \(point)")
        }
    }

    func testShineMattifiesOnlyBrightSkinSpots() throws {
        let base = SyntheticFace.make()
        let gloss = Support.hardEllipse(
            center: SyntheticFace.forehead, radii: CGSize(width: 12, height: 12), extent: SyntheticFace.extent)
        let image = CIImage(color: Self.glossColor).applyingFilter(
            "CIBlendWithMask", parameters: [kCIInputBackgroundImageKey: base.image, kCIInputMaskImageKey: gloss]
        ).cropped(to: SyntheticFace.extent)
        let synthetic = SyntheticFace(image: image, face: base.face)
        let before = try Support.grid(image)
        let after = try Support.grid(render(synthetic, skin: SkinAdjustments(shine: 1)))
        XCTAssertLessThanOrEqual(
            Int(after.red(SyntheticFace.forehead)), Int(before.red(SyntheticFace.forehead)) - Self.mattifyMinimum,
            "반사광이 눌린다")
        for point in [SyntheticFace.cheek, CGPoint(x: 180, y: 220)] {
            let expected = before.rgba(point)
            let actual = after.rgba(point)
            for channel in 0..<3 {
                XCTAssertEqual(Int(actual[channel]), Int(expected[channel]), accuracy: 1, "보통 피부 \(point)는 거의 그대로")
            }
        }
        for point in [SyntheticFace.leftEye, SyntheticFace.mouth, SyntheticFace.outside] {
            XCTAssertEqual(after.rgba(point), before.rgba(point), "피부 마스크 밖 \(point)")
        }
    }

    func testSmoothingOnlyUsesTheLegacyBandMixPath() throws {
        let synthetic = SyntheticFace.make()
        let extent = synthetic.image.extent
        let tuning = RenderTuning()
        let faceWidth = FaceRegions.faceWidth(synthetic.face, extent: extent)
        let bounds = FaceRegions.maskBounds(face: synthetic.face, extent: extent, tuning: tuning)
        let mask = try FaceRegions.skinMask(
            face: synthetic.face, image: synthetic.image, extent: extent, tuning: tuning)
        let reference = try XCTUnwrap(
            SkinStage.cheekReference(of: synthetic.image, face: synthetic.face, extent: extent))
        let legacy = try FrequencySeparation.smoothed(
            synthetic.image, bounds: bounds, faceWidth: faceWidth, smoothing: 0.7, tuning: tuning)
        let refined = try FrequencySeparation.refined(
            synthetic.image, bounds: bounds, faceWidth: faceWidth, mask: mask, reference: reference, smoothing: 0.7,
            toneEvening: 0, chromaEvening: 0, shine: 0, tuning: tuning)
        XCTAssertTrue(try Support.bytes(refined) == Support.bytes(legacy), "얼룩·번들거림 0이면 기존 경로와 같은 바이트")
        let combined = try render(synthetic, skin: SkinAdjustments(smoothing: 0.7, toneEvening: 0.5))
        XCTAssertFalse(
            try Support.bytes(combined) == Support.bytes(render(synthetic, skin: SkinAdjustments(smoothing: 0.7))))
    }

    /// 얼룩 색 고르기 테스트의 보라 얼룩 자리. 왼볼이고 눈·입·분산 측정 패치에서 떨어져 있다.
    private static let chromaBlotchCenter = CGPoint(x: 200, y: 220)
    /// 보라 얼룩의 감마 Cb·Cr 이동(스펙 G5 1.2).
    private static let plantedCb = 0.04
    private static let plantedCr = 0.03
    /// 얼룩 반지름(얼굴 폭 비율)과 측정 원반 비율(가장자리 흐림을 뺀 안쪽).
    private static let chromaBlotchFraction: CGFloat = 0.06
    private static let chromaDiscFraction: CGFloat = 0.65
    /// 얼룩 색 고르기 1의 최소 제거율.
    private static let chromaRemovalMinimum = 0.5
    /// 같은 픽셀의 평균 ΔY 상한(8비트).
    private static let chromaLumaTolerance = 1.0

    func testChromaEveningPullsBlotchChromaAndKeepsLuma() throws {
        let base = SyntheticFace.make()
        let extent = base.image.extent
        let center = Self.chromaBlotchCenter
        let radius = FaceRegions.faceWidth(base.face, extent: extent) * Self.chromaBlotchFraction
        let tinted = SyntheticDefect.tinted(
            base.image, center: center, radius: radius, cb: Self.plantedCb, cr: Self.plantedCr, extent: extent)
        let blotchy = CIImage(cgImage: try Support.renderer.makeCGImage(tinted))
        let skin = SkinAdjustments(chromaEvening: 1)
        let before = try Support.grid(blotchy)
        let after = try Support.grid(render(SyntheticFace(image: blotchy, face: base.face), skin: skin))
        let clean = try Support.grid(base.image)
        // 남은 색은 깨끗한 얼굴을 같은 값으로 렌더한 결과와 비교한다(피부 결의 색 고르기는 빼고 얼룩만 본다).
        let cleanAfter = try Support.grid(render(base, skin: skin))
        let discRadius = radius * Self.chromaDiscFraction
        let disc = try Support.grid(
            Support.hardEllipse(center: center, radii: CGSize(width: discRadius, height: discRadius), extent: extent))
        let planted = DisplayScale.chromaDelta(clean, before, weight: disc)
        let remaining = DisplayScale.chromaDelta(cleanAfter, after, weight: disc)
        XCTAssertGreaterThanOrEqual(1 - remaining.cb / planted.cb, Self.chromaRemovalMinimum, "Cb 절반 이상")
        XCTAssertGreaterThanOrEqual(1 - remaining.cr / planted.cr, Self.chromaRemovalMinimum, "Cr 절반 이상")
        XCTAssertLessThanOrEqual(
            abs(DisplayScale.lumaDelta(before, after, weight: disc).mean), Self.chromaLumaTolerance, "휘도는 그대로")
    }

    func testZeroChromaEveningKeepsTheToneMixBytes() throws {
        let base = SyntheticFace.make()
        let withEven = try Support.bytes(render(base, skin: SkinAdjustments(toneEvening: 0.5)))
        let withZeroChroma = try Support.bytes(render(base, skin: SkinAdjustments(toneEvening: 0.5, chromaEvening: 0)))
        XCTAssertEqual(withEven, withZeroChroma)
        let withChroma = try Support.bytes(render(base, skin: SkinAdjustments(toneEvening: 0.5, chromaEvening: 1)))
        XCTAssertNotEqual(withEven, withChroma, "0이 아니면 경로가 실제로 바뀐다")
    }

    /// 붉은기 테스트의 반점 색. 피부보다 감마 Cr이 0.037 높고 피부색 가중치 안이다.
    private static let blotchColor = CIColor(red: 0.84, green: 0.58, blue: 0.52)
    /// 오른볼 위 반점 자리. 잡티·특징·분산 측정 패치에서 떨어져 있다.
    private static let blotchPoint = CGPoint(x: 320, y: 210)

    /// 기준(볼 평균 − rednessReferenceOffset)보다 덜 붉은 창백한 피부 조각의 색과 자리.
    /// 피부보다 감마 Cr이 약 0.03 낮고 피부색 가중치(σ 0.04) 안이다.
    /// 이마 오른쪽이라 볼 기준 상자·반점·주름 띠에서 떨어져 있다.
    private static let paleColor = CIColor(red: 0.80, green: 0.68, blue: 0.60)
    private static let palePoint = CGPoint(x: 300, y: 372)
    private static let paleRadius: CGFloat = 8

    /// BT.601 역변환에서 Cr 1이 바꾸는 R·G·B(감마 값).
    private static let crToRGB = [1.402, -0.714136, 0]
    /// 감마 값 1을 8비트 바이트로.
    private static let byteRange = 255.0

    func testRednessClearsOnlyRedderThanCheeksAndFlushAddsEvenly() throws {
        let base = SyntheticFace.make()
        let blotch = Support.hardEllipse(
            center: Self.blotchPoint, radii: CGSize(width: 10, height: 10), extent: SyntheticFace.extent)
        let blotched = CIImage(color: Self.blotchColor).applyingFilter(
            "CIBlendWithMask", parameters: [kCIInputBackgroundImageKey: base.image, kCIInputMaskImageKey: blotch]
        ).cropped(to: SyntheticFace.extent)
        let pale = Support.hardEllipse(
            center: Self.palePoint, radii: CGSize(width: Self.paleRadius, height: Self.paleRadius),
            extent: SyntheticFace.extent)
        let image = CIImage(color: Self.paleColor).applyingFilter(
            "CIBlendWithMask", parameters: [kCIInputBackgroundImageKey: blotched, kCIInputMaskImageKey: pale]
        ).cropped(to: SyntheticFace.extent)
        let synthetic = SyntheticFace(image: image, face: base.face)
        func gap(_ pixel: [UInt8]) -> Int { Int(pixel[0]) - Int(pixel[1]) }
        let before = try Support.grid(image)
        let clear = try Support.grid(render(synthetic, skin: SkinAdjustments(redness: -1)))
        XCTAssertLessThanOrEqual(
            gap(clear.rgba(Self.blotchPoint)), gap(before.rgba(Self.blotchPoint)) - 10, "반점의 붉은기가 준다")
        // 기준이 볼 평균보다 rednessReferenceOffset 낮아 볼과 같은 붉기의 피부도 그만큼만 맑아진다(G4).
        let tuning = RenderTuning()
        let referenceShift = -tuning.rednessReferenceOffset * tuning.skinMaskMaxStrength
        for channel in 0..<3 {
            let expected =
                Double(before.rgba(SyntheticFace.cheek)[channel]) + referenceShift * Self.crToRGB[channel]
                * Self.byteRange
            XCTAssertEqual(
                Double(clear.rgba(SyntheticFace.cheek)[channel]), expected, accuracy: 2,
                "볼과 같은 붉기의 피부는 기준 여유만큼만 맑아진다")
        }
        for channel in 0..<3 {
            XCTAssertEqual(
                Int(clear.rgba(Self.palePoint)[channel]), Int(before.rgba(Self.palePoint)[channel]),
                accuracy: Self.blendRoundingTolerance, "기준 − 여유보다 덜 붉은 피부는 그대로")
        }
        let flush = try Support.grid(render(synthetic, skin: SkinAdjustments(redness: 1)))
        // 창백한 조각도 혈색이 오르므로 피부 마스크 안이다(위 "그대로"가 마스크 밖이라서 통과한 것이 아니다).
        for point in [SyntheticFace.cheek, Self.blotchPoint, SyntheticFace.forehead, Self.palePoint] {
            XCTAssertGreaterThanOrEqual(gap(flush.rgba(point)), gap(before.rgba(point)) + 5, "혈색은 피부 전체에 고르게 \(point)")
        }
        for point in [
            SyntheticFace.leftEye, SyntheticFace.mouth, SyntheticFace.backgroundInsideContour, SyntheticFace.outside,
        ] {
            XCTAssertEqual(clear.rgba(point), before.rgba(point), "피부 마스크 밖 \(point)")
            XCTAssertEqual(flush.rgba(point), before.rgba(point), "피부 마스크 밖 \(point)")
        }
    }

    func testZeroRefinementsAreIdentityAndOutOfRangeValuesRenderClamped() throws {
        let synthetic = SyntheticFace.make()
        let input = try Support.bytes(synthetic.image)
        XCTAssertTrue(try Support.bytes(render(synthetic, skin: SkinAdjustments())) == input)
        XCTAssertTrue(try Support.bytes(render(synthetic, skin: SkinAdjustments(shine: -1))) == input, "음수는 0")
        let outOfRange = SkinAdjustments(darkCircles: 3, marionette: 2, toneEvening: 2, redness: -5)
        let inRange = SkinAdjustments(darkCircles: 1, marionette: 1, toneEvening: 1, redness: -1)
        XCTAssertTrue(
            try Support.bytes(render(synthetic, skin: outOfRange)) == Support.bytes(render(synthetic, skin: inRange)),
            "범위 밖 값은 자른 값과 같은 바이트")
        XCTAssertEqual(
            SkinStage.clamped(SkinAdjustments(smoothing: 4, marionette: -2, glabella: -1, redness: 2)),
            SkinAdjustments(smoothing: 1, redness: 1))
    }

    func testBoxOnlyFaceSkipsFoldsButStillEvensTone() throws {
        let boxOnly = SyntheticFace.make(landmarks: false)
        let input = try Support.bytes(boxOnly.image)
        let folds = SkinAdjustments(darkCircles: 1, nasolabial: 1, marionette: 1, glabella: 1)
        XCTAssertTrue(try Support.bytes(render(boxOnly, skin: folds)) == input, "주름 띠는 특징점이 없으면 빠진다")
        let before = try Support.grid(boxOnly.image)
        let evened = try Support.grid(render(boxOnly, skin: SkinAdjustments(toneEvening: 1, redness: 1)))
        XCTAssertNotEqual(evened.rgba(SyntheticFace.cheek), before.rgba(SyntheticFace.cheek), "대체 타원 마스크로 동작")
        XCTAssertEqual(evened.rgba(SyntheticFace.outside), before.rgba(SyntheticFace.outside))
    }

    /// 반 크기 합성 얼굴 둘을 좌우에 놓는다. 비트맵으로 굳혀 마스크 밖 바이트를 그대로 비교한다.
    func testTargetFaceRefinesOnlyThatFace() throws {
        let synthetic = SyntheticFace.make()
        let side = CGFloat(SyntheticFace.size)
        let half = CGAffineTransform(scaleX: 0.5, y: 0.5)
        let left = synthetic.image.transformed(by: half.concatenating(CGAffineTransform(translationX: 0, y: side / 4)))
        let right = synthetic.image.transformed(
            by: half.concatenating(CGAffineTransform(translationX: side / 2, y: side / 4)))
        let composed = left.composited(over: right).composited(over: CIImage(color: .gray))
            .cropped(to: SyntheticFace.extent)
        let image = CIImage(cgImage: try Support.renderer.makeCGImage(composed))
        let faces = [
            synthetic.face.transformed(scale: 0.5, offset: NormalizedPoint(x: 0, y: 0.25)),
            synthetic.face.transformed(scale: 0.5, offset: NormalizedPoint(x: 0.5, y: 0.25)),
        ]
        var recipe = EditRecipe()
        recipe.portrait.skin = SkinAdjustments(
            darkCircles: 1, nasolabial: 1, marionette: 1, glabella: 1, toneEvening: 1, redness: 1, shine: 1)
        recipe = Support.restricted(recipe, toFace: 0, of: faces)
        let context = RenderContext(extent: image.extent, recipe: recipe, faces: faces, tuning: RenderTuning())
        let before = try Support.grid(image)
        let after = try Support.grid(SkinStage().apply(image, in: context))
        var leftChanged = 0
        var rightChanged = 0
        for y in 0..<SyntheticFace.size {
            for x in 0..<SyntheticFace.size {
                let point = CGPoint(x: x, y: y)
                guard after.rgba(point) != before.rgba(point) else { continue }
                if x < SyntheticFace.size / 2 {
                    leftChanged += 1
                } else {
                    rightChanged += 1
                }
            }
        }
        XCTAssertGreaterThan(leftChanged, 0, "고른 얼굴은 보정된다")
        XCTAssertEqual(rightChanged, 0, "다른 얼굴은 한 픽셀도 바뀌지 않는다")
    }

    func testRefinementsUseOneSkinRasterAndOneFoldRaster() throws {
        let synthetic = SyntheticFace.make()
        var recipe = EditRecipe()
        recipe.portrait.skin = SkinAdjustments(
            smoothing: 0.5, darkCircles: 1, nasolabial: 1, marionette: 1, glabella: 1, toneEvening: 1, redness: -1,
            shine: 1)
        let analysis = PhotoAnalysis(faces: [synthetic.face])
        let context = RenderContext(
            extent: synthetic.image.extent, recipe: recipe, analysis: analysis, tuning: RenderTuning())
        let first = try Support.bytes(SkinStage().apply(synthetic.image, in: context))
        let second = try Support.bytes(SkinStage().apply(synthetic.image, in: context))
        XCTAssertEqual(analysis.regionMasks.count, 2, "피부 다각형 비트맵 하나와 주름용 비트맵 하나")
        XCTAssertTrue(first == second, "같은 입력은 같은 바이트")
        var spotted = recipe
        spotted.portrait.skin.spots = 1
        let spotContext = RenderContext(
            extent: synthetic.image.extent, recipe: spotted, analysis: analysis, tuning: RenderTuning())
        _ = try Support.bytes(SkinStage().apply(synthetic.image, in: spotContext))
        _ = try Support.bytes(SkinStage().apply(synthetic.image, in: spotContext))
        XCTAssertEqual(analysis.regionMasks.count, 3, "점 지우기는 제외 비트맵 하나를 더한다(G5)")
    }

    /// 띠 둘레 피부 가중치 합이 SkinKernels.foldMinimumCoverage보다 작으면 기준이 없어 배율 1이어야 한다.
    /// 옅게 만든 피부 마스크는 평균 색(분자 ÷ 분모)이 그대로라 커버리지 문턱만 밝힘을 막는다.
    /// 같은 그늘을 세기 1 피부 마스크로 밝히는 대조가 있어 문턱이 없으면 이 테스트가 실패한다.
    func testFoldLiftWithTooLittleSurroundSkinLeavesTheBandUnchanged() throws {
        let base = SyntheticFace.make()
        let extent = base.image.extent
        let tuning = RenderTuning()
        let image = darkened(
            base.image, at: SyntheticFace.underLeftEye, radii: CGSize(width: 40, height: 14), factor: Self.shadowFactor)
        let region = try XCTUnwrap(FaceRegions.darkCircleMask(face: base.face, extent: extent, tuning: tuning))
        let skin = try FaceRegions.skinMask(face: base.face, image: image, extent: extent, tuning: tuning)
        func lifted(_ mask: CIImage) throws -> [UInt8] {
            try Support.bytes(
                SkinRefinement.liftFold(
                    image, region: region, skinMask: mask, faceWidth: SyntheticFace.box.width, amount: 1,
                    tuning: tuning, extent: extent))
        }
        let input = try Support.bytes(image)
        let full = try lifted(skin)
        XCTAssertGreaterThanOrEqual(
            zip(full, input).map { Int($0) - Int($1) }.max() ?? 0, Self.liftMinimum, "피부 기준이 있으면 그늘을 밝힌다(대조)")
        let faint = try lifted(MaskBuilder.scaled(skin, by: Self.faintSkinWeight))
        let difference = zip(faint, input).map { abs(Int($0) - Int($1)) }.max() ?? 0
        XCTAssertLessThanOrEqual(difference, Self.blendRoundingTolerance, "피부 가중치 합이 문턱 아래면 바꾸지 않는다")
    }

    /// 피부 마스크에 곱하는 옅은 가중치.
    /// 커버리지 문턱(foldMinimumCoverage)의 절반이다.
    private static let faintSkinWeight = SkinKernels.foldMinimumCoverage / 2

    /// 배율 1로 띠를 섞어도 남는 채널 차이(바이트).
    /// 같은 이미지를 마스크로 섞기만 해도 작업 색공간 반올림으로 1바이트가 달라진다.
    /// 실측은 6144픽셀이 1바이트이고 2바이트 이상은 없다.
    /// 밝힘 폭주나 검정 번짐은 이보다 훨씬 크다.
    private static let blendRoundingTolerance = 1

    /// 둘레에 어두운 눈·눈썹이 있어도 기준은 피부만 본다: 눈 아래 그늘을 심으면 밝아져야 한다(실사진 실패의 재현).
    func testFoldLiftIgnoresDarkFeaturesInTheSurround() throws {
        let synthetic = SyntheticFace.make()
        let center = SyntheticFace.underLeftEye
        let shadowed = darkened(
            synthetic.image, at: center, radii: CGSize(width: 40, height: 14), factor: Self.shadowFactor)
        let before = try Support.grid(shadowed)
        let after = try Support.grid(
            render(SyntheticFace(image: shadowed, face: synthetic.face), skin: SkinAdjustments(darkCircles: 1)))
        XCTAssertGreaterThanOrEqual(
            Int(after.red(center)), Int(before.red(center)) + Self.liftMinimum, "눈 옆 그늘도 피부 기준으로 밝힌다")
        XCTAssertEqual(after.rgba(SyntheticFace.leftEye), before.rgba(SyntheticFace.leftEye), "눈 안은 그대로")
    }

    func testIndividualLayerSmoothsOnlyThatFace() throws {
        let pair = try SyntheticFace.pair(SyntheticFace.make(), renderer: Support.renderer)
        var recipe = EditRecipe()
        recipe.people.individuals = [
            PersonRecord(
                anchor: PersonAnchor(faceBox: pair.faces[0].boundingBox), layer: PortraitLayer(skinSmoothing: 1))
        ]
        let context = RenderContext(
            extent: pair.image.extent, recipe: recipe, faces: pair.faces, tuning: RenderTuning())
        let before = try Support.grid(pair.image)
        let after = try Support.grid(SkinStage().apply(pair.image, in: context))
        let changed = Support.changedPixelsByHalf(before, after)
        XCTAssertGreaterThan(changed.left, 0, "개인 층이 있는 왼쪽 얼굴만 바뀐다")
        XCTAssertEqual(changed.right, 0, "다른 얼굴은 한 픽셀도 바뀌지 않는다")
        var unmatched = EditRecipe()
        unmatched.people.individuals = [
            PersonRecord(anchor: PersonAnchor(x: 0.5, y: 0.98, width: 0.02), layer: PortraitLayer(skinSmoothing: 1))
        ]
        let idle = RenderContext(
            extent: pair.image.extent, recipe: unmatched, faces: pair.faces, tuning: RenderTuning())
        XCTAssertEqual(
            try Support.bytes(SkinStage().apply(pair.image, in: idle)), try Support.bytes(pair.image),
            "짝이 없는 기록은 아무 얼굴도 바꾸지 않는다")
        var perFaceBlemish = EditRecipe()
        perFaceBlemish.people.individuals = [
            PersonRecord(
                anchor: PersonAnchor(faceBox: pair.faces[1].boundingBox), layer: PortraitLayer(autoBlemish: true))
        ]
        let spots = [
            BlemishSpot(x: 0.2, y: 0.5, radius: 0.004, faceIndex: 0),
            BlemishSpot(x: 0.7, y: 0.5, radius: 0.004, faceIndex: 1),
        ]
        let healing = RenderContext(
            extent: pair.image.extent, recipe: perFaceBlemish, faces: pair.faces, tuning: RenderTuning(),
            blemishes: spots)
        XCTAssertEqual(Set(SkinStage.healSpots(in: healing).map(\.x)), [0.7], "자동 잡티가 켜진 사람의 잡티만 지운다")
    }
}
