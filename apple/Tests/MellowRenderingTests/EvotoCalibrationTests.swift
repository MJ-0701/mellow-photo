import CoreImage
import ImageIO
import MellowShared
import UniformTypeIdentifiers
import XCTest

@testable import MellowRendering

/// Evoto 전후 쌍의 before에 원터치를 걸어 Evoto after와 같은 픽셀에서 잰다(G5 보정 측정).
/// MELLOW_EVOTO_DIR(기능별 하위 폴더에 *before*·*after* 이미지)가 없으면 건너뛴다.
/// 이미지는 저장소에 두지 않는다.
/// 표(metrics.md·metrics.tsv)와 나란히 보기 PNG는 MELLOW_EVOTO_OUT에 쓰고 없으면 임시 폴더에 쓴다.
/// 단언하지 않는다.
/// 수치는 스펙 경계를 정하는 근거이고 macOS에서만 돌린다.
final class EvotoCalibrationTests: XCTestCase {
    typealias Support = RenderingTestSupport

    enum Environment {
        static let directory = "MELLOW_EVOTO_DIR"
        static let output = "MELLOW_EVOTO_OUT"
        /// 쉼표로 나눈 기능 폴더 이름.
        /// 없으면 Calibration.defaultFeatures다.
        static let features = "MELLOW_EVOTO_FEATURES"
        /// 1이면 나란히 보기 PNG를 쓰지 않는다.
        static let skipImages = "MELLOW_EVOTO_NO_IMAGES"
        /// 1이면 후보 표·시제품도 잰다.
        static let candidates = "MELLOW_EVOTO_CANDIDATES"
    }

    enum Calibration {
        static let defaultFeatures = [
            "ai-skin-retouching", "change-skin-color", "soften-skin", "blemish-removal", "frequency-separation",
            "rosy-complexion-ai-tool", "remove-dark-circles", "wrinkle-remover-for-face", "remove-frown-lines",
            "remove-marionette-lines",
        ]
        /// after가 before와 이 비율 안에서 크기가 다르면 before 크기로 맞추고 넘으면 건너뛴다.
        static let sizeTolerance: CGFloat = 0.01
        /// 세 채널 중 최대 |Δ|(8비트)가 이 값 이상이면 바뀐 픽셀이다.
        static let changedDelta: Float = 4
        /// 마스크 안으로 보는 가중치.
        static let maskInside: Float = 0.5
        /// 대역 분산을 재는 피부 안쪽 가중치.
        /// 마스크 흐림 가장자리의 머리카락·눈 대비를 덜 넣는다.
        static let interiorWeight: Float = 0.8
        /// 대역 경계 반지름.
        /// 얼굴 폭 비율.
        /// 모공(fine)은 렌더와 같은 fineBandFraction 아래다.
        static let midOuterFraction = 0.03
        static let evenInnerFraction = 0.01
        static let evenOuterFraction = 0.03
        static let lowOuterFraction = 0.12
        /// 결함 반지름.
        /// 얼굴 폭 비율.
        /// 주근깨·여드름 자국(지름 1~2%)은 spot으로, 모공(0.5% 안팎)은 pore로 지운다.
        static let spotRadiusFraction = 0.012
        static let poreRadiusFraction = 0.003
        /// 붉은 얼룩 기준 Cr을 재는 흐림 반지름.
        /// 얼굴 폭 비율.
        static let blotchTrendFraction = 0.06
        /// ΔY 지도 상관을 재기 전 두 지도를 흐리는 반지름.
        /// 얼굴 폭 비율.
        /// webp 압축 잡음을 걷어 낸다.
        static let correlationBlurFraction = 0.01
        /// 인물 마스크가 이 값보다 작으면 배경이다.
        static let backgroundPersonMaximum: Float = 0.05
        static let percentile = 0.99
        static let maximumByte: Float = 255
        /// 인물 마스크 흐림.
        /// 짧은 변 비율.
        static let personFeatherFraction: CGFloat = 0.004
        static let panelWidth: CGFloat = 500
        static let zoomPanelWidth: CGFloat = 900
        static let zoomPanelsPerRow = 2
        /// 확대 자르기는 피부 마스크 영역을 이만큼 넓힌다.
        static let zoomPadding: CGFloat = 0.05
        static let labelFontSize: CGFloat = 26
        static let labelMargin: CGFloat = 8
        static let previewMaxDimension = RenderTuning().previewMaxDimension
    }

    // MARK: 변형

    /// 원터치 한 벌.
    /// gender가 nil이면 앱의 전체 대상 원터치(전체 층 공통 표 + 성별 그룹 층 + 몸 피부 밝기, 성별 미지정 → 공통 표)다.
    /// 값이 있으면 같은 레시피에서 모든 얼굴을 그 성별로 지정한다(그룹 층이 성별 표를 준다).
    struct Variant {
        let name: String
        let strength: Double
        let gender: Gender?
        let table: (Gender?) -> OneTouchBundle.Values
        let bodyBrightness: Double
        let bodyTone: Double
        let tuning: RenderTuning
        /// 렌더 뒤에 거는 점 지우기 시제품의 강도 1 값(성별 표).
        /// nil이면 걸지 않는다.
        var spots: ((Gender?) -> Double)?
        /// 자동 잡티(복제 원) 스위치.
        var cloneHeal = true

        static func current(_ family: String, gender: Gender?, strength: Double) -> Variant {
            Variant(
                name: "\(family)-\(strength)", strength: strength, gender: gender, table: OneTouchBundle.values(for:),
                bodyBrightness: OneTouchBundle.Table.bodyBrightness, bodyTone: OneTouchBundle.Table.bodyTone,
                tuning: RenderTuning())
        }
    }

    /// 나란히 보기 한 줄.
    /// before·Evoto 뒤에 기본 강도와 최대 강도를 둔다.
    struct Family {
        let name: String
        let variants: [Variant]
    }

    static let currentFamilies: [Family] = [
        ("app", nil), ("female", Gender.female), ("male", Gender.male),
    ].map { name, gender in
        Family(
            name: name,
            variants: [OneTouchBundle.defaultStrength, OneTouchBundle.maximumStrength].map {
                Variant.current(name, gender: gender, strength: $0)
            })
    }

    /// 후보 표·상수(G5 제안 측정).
    /// MELLOW_EVOTO_CANDIDATES=1일 때만 잰다.
    static let candidateFamilies: [Family] = [
        candidate("spots", spots: Candidate.spots),
        candidate("calm", table: Candidate.calm, bodyBrightness: Candidate.calmBodyBrightness, spots: Candidate.spots),
        candidate(
            "calmNoClone", table: Candidate.calm, bodyBrightness: Candidate.calmBodyBrightness,
            spots: Candidate.spots, cloneHeal: false),
        candidate(
            "calmFemale", gender: .female, table: Candidate.calm, bodyBrightness: Candidate.calmBodyBrightness,
            spots: Candidate.spots, cloneHeal: false),
        candidate(
            "calmMale", gender: .male, table: Candidate.calm, bodyBrightness: Candidate.calmBodyBrightness,
            spots: Candidate.spots, cloneHeal: false),
    ]

    /// 후보 값.
    enum Candidate {
        /// 점 지우기 강도 1(성별 표).
        /// 1을 넘는 값은 기본 강도 0.6에서 거의 다 걸리게 하려는 것이다(시제품이 1에서 자른다).
        /// 남성은 질감을 더 남긴다.
        static let maleSpots = 1.2
        static let otherSpots = 1.6
        /// 중간·넓은 대역 평탄화를 Evoto 쪽(중간 대역 분산비 0.85~1.0)으로 낮춘 매끄럽게·얼룩 고르기.
        static let calmSmoothing: [Gender?: Double] = [nil: 0.16, .female: 0.2, .male: 0.12]
        static let calmToneEvening: [Gender?: Double] = [nil: 0.08, .female: 0.1, .male: 0.05]
        static let calmBodyBrightness = 0.08

        static func spots(_ gender: Gender?) -> Double {
            gender == .male ? maleSpots : otherSpots
        }

        static func calm(_ gender: Gender?) -> OneTouchBundle.Values {
            var values = OneTouchBundle.values(for: gender)
            values.smoothing = calmSmoothing[gender] ?? values.smoothing
            values.toneEvening = calmToneEvening[gender] ?? values.toneEvening
            return values
        }
    }

    static func candidate(
        _ name: String, gender: Gender? = nil,
        table: @escaping (Gender?) -> OneTouchBundle.Values = OneTouchBundle.values(for:),
        bodyBrightness: Double = OneTouchBundle.Table.bodyBrightness, spots: ((Gender?) -> Double)? = nil,
        cloneHeal: Bool = true
    ) -> Family {
        Family(
            name: name,
            variants: [OneTouchBundle.defaultStrength, OneTouchBundle.maximumStrength].map { strength in
                Variant(
                    name: "\(name)-\(strength)", strength: strength, gender: gender, table: table,
                    bodyBrightness: bodyBrightness, bodyTone: OneTouchBundle.Table.bodyTone, tuning: RenderTuning(),
                    spots: spots, cloneHeal: cloneHeal)
            })
    }

    /// OneTouchBundle.layer와 같은 규칙의 층.
    /// 후보 표를 넣으려고 따로 둔다(testLocalLayerMatchesTheBundle가 같음을 지킨다).
    static func layer(_ values: OneTouchBundle.Values, strength: Double) -> PortraitLayer {
        var layer = PortraitLayer()
        layer.skinSmoothing = AdjustmentRange.clamped(values.smoothing * strength, to: AdjustmentRange.unit)
        layer.autoBlemish = true
        let refinements: [SkinRefinementKey: Double] = [
            .darkCircles: values.darkCircles, .nasolabial: values.nasolabial, .marionette: values.marionette,
            .glabella: values.glabella, .toneEvening: values.toneEvening, .redness: values.redness,
            .shine: values.shine,
        ]
        for (key, value) in refinements {
            layer.skinRefinement[key] = AdjustmentRange.clamped(
                value * strength, to: AdjustmentRange.skinRefinement(key))
        }
        let features: [FeatureKey: Double] = [
            .eyeBrighten: values.eyeBrighten, .teethWhiten: values.teethWhiten, .lipVitality: values.lipVitality,
        ]
        for (key, value) in features {
            layer.features[key] = AdjustmentRange.clamped(value * strength, to: AdjustmentRange.unit)
        }
        layer.makeup[.blush] = MakeupTint(
            colorID: values.blushColorID,
            intensity: AdjustmentRange.clamped(values.blushIntensity * strength, to: AdjustmentRange.unit))
        layer.makeup[.lip] = MakeupTint(colorID: nil, intensity: 0)
        layer.oneTouch = strength
        return layer
    }

    /// 앱의 전체 대상 원터치와 같은 레시피(EditDocument.applyOneTouch(.all)).
    static func recipe(_ variant: Variant, faces: [FaceGeometry]) -> EditRecipe {
        var recipe = EditRecipe()
        recipe.bodySkin.brightness = AdjustmentRange.clamped(
            variant.bodyBrightness * variant.strength, to: AdjustmentRange.bodySkin(.brightness))
        recipe.bodySkin.tone = AdjustmentRange.clamped(
            variant.bodyTone * variant.strength, to: AdjustmentRange.bodySkin(.tone))
        var all = layer(variant.table(nil), strength: variant.strength)
        all.autoBlemish = variant.cloneHeal
        all.applied(to: &recipe.portrait, makeup: &recipe.makeup)
        for group in Gender.allCases {
            var grouped = layer(variant.table(group), strength: variant.strength)
            grouped.autoBlemish = variant.cloneHeal
            recipe.people.groups[group] = grouped
        }
        if let gender = variant.gender {
            recipe.people.individuals = faces.map {
                PersonRecord(anchor: PersonAnchor(faceBox: $0.boundingBox), gender: gender)
            }
        }
        return recipe
    }

    func testLocalLayerMatchesTheBundle() {
        for gender in [Gender?.none, .female, .male] {
            for strength in [OneTouchBundle.defaultStrength, OneTouchBundle.maximumStrength] {
                XCTAssertEqual(
                    Self.layer(OneTouchBundle.values(for: gender), strength: strength),
                    OneTouchBundle.layer(for: gender, strength: strength), "\(String(describing: gender)) \(strength)")
            }
        }
    }

    // MARK: 측정

    func testMeasureOneTouchAgainstEvotoPairs() throws {
        let environment = ProcessInfo.processInfo.environment
        guard let directory = environment[Environment.directory], !directory.isEmpty else {
            throw XCTSkip("\(Environment.directory)가 없어 Evoto 보정 측정을 건너뛴다")
        }
        let output = try outputFolder(environment[Environment.output])
        let features =
            environment[Environment.features].map { $0.split(separator: ",").map(String.init) }
            ?? Calibration.defaultFeatures
        let writesImages = environment[Environment.skipImages] != "1"
        let pairs = try EvotoPair.discover(in: URL(fileURLWithPath: directory), features: features)
        XCTAssertFalse(pairs.isEmpty, "쌍이 없다")
        let families =
            Self.currentFamilies + (environment[Environment.candidates] == "1" ? Self.candidateFamilies : [])
        var report = Report()
        for pair in pairs {
            guard let photo = try EvotoPhoto(pair: pair) else {
                report.skip(pair, reason: "크기 차이 또는 얼굴 없음")
                continue
            }
            let probe = try Probe(photo: photo)
            let before = try probe.readout(photo.original, tuning: RenderTuning())
            let evoto = try probe.readout(photo.after, tuning: RenderTuning())
            var rows = [("evoto", probe.metrics(before: before, after: evoto))]
            var rendered: [String: CIImage] = [:]
            for variant in families.flatMap(\.variants) {
                let image = try photo.render(variant)
                rendered[variant.name] = image
                let ours = try probe.readout(image, tuning: variant.tuning)
                var metrics = probe.metrics(before: before, after: ours)
                metrics.correlation = probe.correlation(before: before, ours: ours, evoto: evoto)
                rows.append((variant.name, metrics))
            }
            report.add(pair, photo: photo, rows: rows)
            if writesImages {
                for family in families {
                    try Board.write(
                        photo: photo, probe: probe, family: family, rendered: rendered,
                        to: output.appendingPathComponent("\(pair.feature)_\(pair.key)_\(family.name)"))
                }
            }
        }
        try report.markdown().write(to: output.appendingPathComponent("metrics.md"), atomically: true, encoding: .utf8)
        try report.tsv().write(to: output.appendingPathComponent("metrics.tsv"), atomically: true, encoding: .utf8)
        print("evoto-calibration output=\(output.path)")
    }

    private func outputFolder(_ path: String?) throws -> URL {
        let folder =
            path.map { URL(fileURLWithPath: $0) }
            ?? FileManager.default.temporaryDirectory.appendingPathComponent("evoto-calibration")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }
}

// MARK: 쌍

/// 기능 폴더 안 before·after 한 쌍.
/// 이름에서 "_before"·"_after" 앞(끝의 "_1" 제외)이 같으면 짝이다.
/// workspaceStep 화면 캡처는 뺀다.
struct EvotoPair {
    let feature: String
    let key: String
    let before: URL
    let after: URL

    private static let beforeMarker = "_before"
    private static let afterMarker = "_after"
    private static let duplicateSuffix = "_1"
    private static let screenshotMarker = "workspaceStep"
    private static let imageExtensions: Set<String> = ["webp", "png", "jpg", "jpeg"]

    static func discover(in root: URL, features: [String]) throws -> [EvotoPair] {
        var pairs: [EvotoPair] = []
        for feature in features {
            let folder = root.appendingPathComponent(feature)
            guard
                let names = try? FileManager.default.contentsOfDirectory(atPath: folder.path)
            else { continue }
            let images = names.filter {
                !$0.contains(screenshotMarker) && imageExtensions.contains(($0 as NSString).pathExtension.lowercased())
            }
            var befores: [String: URL] = [:]
            var afters: [String: URL] = [:]
            for name in images {
                if let key = key(name, marker: beforeMarker) {
                    befores[key] = folder.appendingPathComponent(name)
                } else if let key = key(name, marker: afterMarker) {
                    afters[key] = folder.appendingPathComponent(name)
                }
            }
            for key in befores.keys.sorted() {
                guard let before = befores[key], let after = afters[key] else { continue }
                pairs.append(EvotoPair(feature: feature, key: key, before: before, after: after))
            }
        }
        return pairs
    }

    private static func key(_ name: String, marker: String) -> String? {
        guard let range = name.range(of: marker) else { return nil }
        var key = String(name[..<range.lowerBound])
        if key.hasSuffix(duplicateSuffix) {
            key.removeLast(duplicateSuffix.count)
        }
        return key
    }
}

// MARK: 사진

/// 한 쌍을 앱처럼 준비한 것.
/// 분석(얼굴·인물·관절·잡티)은 미리보기 크기에서 하고 렌더와 측정은 원본 크기에서 한다(renderOriginal과 같다).
struct EvotoPhoto {
    typealias Support = RenderingTestSupport

    let pair: EvotoPair
    /// 8비트로 굳힌 원본 크기 before.
    let original: CIImage
    /// before 크기로 맞춘 8비트 Evoto after.
    let after: CIImage
    let extent: CGRect
    let preview: CIImage
    let faces: [FaceGeometry]
    let personMask: CIImage?
    let bodies: [BodyGeometry]
    /// 측정 기준 얼굴(가장 넓은 얼굴).
    let face: FaceGeometry
    let faceWidth: CGFloat

    /// 크기가 허용 밖이거나 얼굴이 없으면 nil.
    init?(pair: EvotoPair) throws {
        self.pair = pair
        let loader = ImageLoader()
        let before = try loader.load(url: pair.before)
        let afterSource = try loader.load(url: pair.after)
        let widthRatio = afterSource.extent.width / before.extent.width
        let heightRatio = afterSource.extent.height / before.extent.height
        guard abs(widthRatio - 1) <= EvotoCalibrationTests.Calibration.sizeTolerance,
            abs(heightRatio - 1) <= EvotoCalibrationTests.Calibration.sizeTolerance
        else { return nil }
        extent = before.extent
        original = try Self.baked(before)
        let resized = afterSource.transformed(by: CGAffineTransform(scaleX: 1 / widthRatio, y: 1 / heightRatio))
        after = try Self.baked(resized.cropped(to: extent))
        preview = try loader.load(url: pair.before, maxDimension: EvotoCalibrationTests.Calibration.previewMaxDimension)
        faces = try VisionFaceAnalyzer().analyze(preview)
        guard let widest = FaceRegions.widestFace(faces) else { return nil }
        face = widest
        faceWidth = FaceRegions.faceWidth(widest, extent: extent)
        personMask = try? VisionPersonAnalyzer().personMask(preview)
        bodies = (try? VisionBodyAnalyzer().analyze(preview)) ?? []
    }

    static func baked(_ image: CIImage) throws -> CIImage {
        CIImage(cgImage: try Support.renderer.makeCGImage(image))
    }

    /// 앱 준비와 같은 분석 묶음.
    /// 잡티는 tuning으로 미리보기에서 찾는다.
    func analysis(tuning: RenderTuning) throws -> PhotoAnalysis {
        let blemishes = try BlemishDetector(tuning: tuning, renderer: Support.renderer).detect(
            image: preview, faces: faces)
        return PhotoAnalysis(faces: faces, blemishes: blemishes, personMask: personMask, bodies: bodies)
    }

    /// 원본 크기 전체 파이프라인 결과(8비트).
    func render(_ variant: EvotoCalibrationTests.Variant) throws -> CIImage {
        let context = RenderContext(
            extent: extent, recipe: EvotoCalibrationTests.recipe(variant, faces: faces),
            analysis: try analysis(tuning: variant.tuning), tuning: variant.tuning,
            makeupCatalog: try Support.sharedMakeupCatalog())
        var output = try RenderPipeline.standard.render(original, context: context)
        if let spots = variant.spots {
            let amount = spots(variant.gender) * variant.strength
            output = try SpotPrototype.apply(
                output, faces: faces, extent: extent, amount: amount, tuning: variant.tuning)
        }
        return try Self.baked(output)
    }

    /// 미리보기 크기로 줄인 이미지(잡티 수를 앱과 같은 크기에서 센다).
    func previewSized(_ image: CIImage) -> CIImage {
        let scale = preview.extent.width / extent.width
        return image.applyingFilter(
            "CILanczosScaleTransform", parameters: [kCIInputScaleKey: scale, kCIInputAspectRatioKey: 1]
        ).cropped(to: preview.extent)
    }
}

// MARK: 판독

/// CPU에서 읽은 평면들.
/// 값은 8비트 눈금(0…255) sRGB 감마이고 행은 맨 위부터다.
struct Planes {
    let width: Int
    let height: Int
    let red: [Float]
    let green: [Float]
    let blue: [Float]

    var count: Int { width * height }

    func luma(_ index: Int) -> Float {
        Planes.lumaWeights.r * red[index] + Planes.lumaWeights.g * green[index] + Planes.lumaWeights.b * blue[index]
    }

    func cb(_ index: Int) -> Float {
        Planes.cbWeights.r * red[index] + Planes.cbWeights.g * green[index] + Planes.cbWeights.b * blue[index]
    }

    func cr(_ index: Int) -> Float {
        Planes.crWeights.r * red[index] + Planes.crWeights.g * green[index] + Planes.crWeights.b * blue[index]
    }

    /// BT.601 계수(sRGB 감마 값 기준).
    private static let lumaWeights: (r: Float, g: Float, b: Float) = (0.299, 0.587, 0.114)
    private static let cbWeights: (r: Float, g: Float, b: Float) = (-0.168736, -0.331264, 0.5)
    private static let crWeights: (r: Float, g: Float, b: Float) = (0.5, -0.418688, -0.081312)
}

enum PixelReader {
    private static let context = CIContext(options: [
        .workingColorSpace: CGColorSpace(name: CGColorSpace.extendedLinearSRGB)!,
        .outputColorSpace: CGColorSpace(name: CGColorSpace.sRGB)!,
    ])
    private static let channels = 4
    private static let encoded = CGColorSpace(name: CGColorSpace.sRGB)!
    /// 마스크는 작업 공간(선형) 값 그대로가 섞는 가중치다.
    private static let raw = CGColorSpace(name: CGColorSpace.linearSRGB)!

    private static func floats(_ image: CIImage, colorSpace: CGColorSpace) -> (width: Int, height: Int, data: [Float]) {
        let rect = image.extent.integral
        let width = Int(rect.width)
        let height = Int(rect.height)
        var data = [Float](repeating: 0, count: width * height * channels)
        data.withUnsafeMutableBytes { buffer in
            context.render(
                image, toBitmap: buffer.baseAddress!, rowBytes: width * channels * MemoryLayout<Float>.size,
                bounds: rect, format: .RGBAf, colorSpace: colorSpace)
        }
        return (width, height, data)
    }

    static func planes(_ image: CIImage) -> Planes {
        let read = floats(image, colorSpace: encoded)
        let scale = EvotoCalibrationTests.Calibration.maximumByte
        let pixels = read.width * read.height
        var red = [Float](repeating: 0, count: pixels)
        var green = [Float](repeating: 0, count: pixels)
        var blue = [Float](repeating: 0, count: pixels)
        for index in 0..<pixels {
            red[index] = read.data[index * channels] * scale
            green[index] = read.data[index * channels + 1] * scale
            blue[index] = read.data[index * channels + 2] * scale
        }
        return Planes(width: read.width, height: read.height, red: red, green: green, blue: blue)
    }

    static func luma(_ image: CIImage) -> [Float] {
        let planes = planes(image)
        return (0..<planes.count).map { planes.luma($0) }
    }

    /// 회색 마스크의 R(0…1).
    static func mask(_ image: CIImage) -> [Float] {
        let read = floats(image, colorSpace: raw)
        return (0..<(read.width * read.height)).map { min(1, max(0, read.data[$0 * channels])) }
    }
}

// MARK: 측정기

/// 한 사진의 측정 영역과 지표 계산.
/// 색·바뀐 비율·상관은 폰 화면 배율(가로 1170px), 대역 분산은 원본 배율(피부 마스크 영역)에서 잰다.
struct Probe {
    typealias Calibration = EvotoCalibrationTests.Calibration

    let photo: EvotoPhoto
    let phoneSize: CGSize
    /// 폰 배율 가중치.
    let skin: [Float]
    let body: [Float]
    let faceBox: [Float]
    let darkCircles: [Float]
    let nasolabial: [Float]
    let background: [Float]?
    /// 원본 배율 대역 영역(피부 마스크 영역)과 그 안쪽 가중치.
    let bandRect: CGRect
    let bandWeight: [Float]
    let radii: (fine: Double, even: Double, mid: Double, low: Double, spot: Double, pore: Double, blotch: Double)
    let correlationRadius: Double

    /// 한 이미지의 판독.
    struct Readout {
        let phone: Planes
        let smoothLuma: [Float]
        /// 원본 배율 대역 분산(fine·mid·even·low).
        let bands: [Double]
        /// 원본 배율 결함 평균(어두운 점·밝은 점·모공 크기 어두운 점·붉은 얼룩).
        let defects: [Double]
        let blemishes: Int
    }

    /// 지표 한 줄.
    struct Metrics {
        var skinLuma = 0.0
        var skinCb = 0.0
        var skinCr = 0.0
        var skinChanged = 0.0
        var bodyLuma = 0.0
        var bandRatios: [Double] = []
        var defectRatios: [Double] = []
        var crSpreadRatio = 0.0
        var blemishRatio = 0.0
        var darkCircleLuma = 0.0
        var nasolabialLuma = 0.0
        var faceP99 = 0.0
        var backgroundChanged = Double.nan
        /// ΔY 지도와 Evoto ΔY 지도의 피부 가중 상관.
        /// evoto 줄은 1이다.
        var correlation = 1.0
        var deltaLuma: [Float] = []
    }

    init(photo: EvotoPhoto) throws {
        self.photo = photo
        let extent = photo.extent
        let tuning = RenderTuning()
        let scale = DisplayScale.phoneWidth / extent.width
        phoneSize = CGSize(width: DisplayScale.phoneWidth, height: (extent.height * scale).rounded(.down))
        let black = CIImage(color: .black).cropped(to: extent)
        let face = photo.face
        let skinImage = try FaceRegions.skinMask(face: face, image: photo.original, extent: extent, tuning: tuning)
        let area = try Self.bodySkinArea(photo: photo, tuning: tuning)
        let wholeFace =
            FaceRegions.wholeFaceMask(faces: photo.faces, extent: extent, tuning: tuning)?.image.composited(over: black)
            ?? black
        let bodyOnly = area.applyingFilter(
            "CIMultiplyCompositing",
            parameters: [kCIInputBackgroundImageKey: wholeFace.applyingFilter("CIColorInvert").cropped(to: extent)])
        let box = CIImage(color: .white).cropped(to: FaceRegions.pixelRect(face.boundingBox, in: extent))
            .composited(over: black)
        func region(_ mask: FaceRegions.RegionMask?) -> CIImage {
            mask.map { $0.image.cropped(to: extent).composited(over: black) } ?? black
        }
        let size = phoneSize
        func phone(_ image: CIImage) -> [Float] { PixelReader.mask(Self.phone(image, size: size)) }
        skin = phone(skinImage)
        body = phone(bodyOnly.cropped(to: extent))
        faceBox = phone(box)
        darkCircles = phone(region(FaceRegions.darkCircleMask(face: face, extent: extent, tuning: tuning)))
        nasolabial = phone(region(FaceRegions.nasolabialMask(face: face, extent: extent, tuning: tuning)))
        background = photo.personMask.map { person in
            let feather = min(extent.width, extent.height) * Calibration.personFeatherFraction
            return phone(BackgroundStage.personMask(person, extent: extent, feather: feather)).map {
                $0 < Calibration.backgroundPersonMaximum ? 1 : 0
            }
        }
        bandRect = FaceRegions.maskBounds(face: face, extent: extent, tuning: tuning)
        bandWeight = PixelReader.mask(skinImage.cropped(to: bandRect)).map { $0 >= Calibration.interiorWeight ? $0 : 0 }
        let width = Double(photo.faceWidth)
        let fine = FrequencySeparation.radii(faceWidth: photo.faceWidth, tuning: tuning).fine
        radii = (
            fine, width * Calibration.evenInnerFraction, width * Calibration.midOuterFraction,
            width * Calibration.lowOuterFraction, width * Calibration.spotRadiusFraction,
            max(tuning.skinBlurMinimumRadius, width * Calibration.poreRadiusFraction),
            width * Calibration.blotchTrendFraction
        )
        correlationRadius = width * Calibration.correlationBlurFraction
    }

    static func phone(_ image: CIImage, size: CGSize) -> CIImage {
        let scale = size.width / image.extent.width
        return image.applyingFilter(
            "CILanczosScaleTransform", parameters: [kCIInputScaleKey: scale, kCIInputAspectRatioKey: 1]
        ).cropped(to: CGRect(origin: .zero, size: size))
    }

    /// 몸 피부 단계가 밝기를 거는 영역(인물 마스크 × 볼 기준 피부색 가중치).
    /// RealPortrait.bodySkinArea와 같은 규칙이다.
    static func bodySkinArea(photo: EvotoPhoto, tuning: RenderTuning) throws -> CIImage {
        let extent = photo.extent
        let encoded = photo.original.applyingFilter("CILinearToSRGBToneCurve")
        let black = CIImage(color: .black).cropped(to: extent)
        guard let cheeks = FaceRegions.cheekAverages(of: encoded, face: photo.face, extent: extent) else {
            return black
        }
        let area: CIImage
        if let person = photo.personMask {
            let shortSide = min(extent.width, extent.height)
            let feather = max(CGFloat(tuning.skinBlurMinimumRadius), shortSide * CGFloat(tuning.bodySkinMaskFeather))
            area = BackgroundStage.personMask(person, extent: extent, feather: feather)
        } else {
            area = BodySkinStage.fallbackPersonRegion(face: photo.face, extent: extent, tuning: tuning)
        }
        let chroma = try SkinKernels.shared.chromaWeight(
            of: encoded, left: cheeks.left, right: cheeks.right, sigma: tuning.bodySkinChromaSigma, extent: extent)
        return area.composited(over: black)
            .applyingFilter("CIMultiplyCompositing", parameters: [kCIInputBackgroundImageKey: chroma])
            .cropped(to: extent)
    }

    func readout(_ image: CIImage, tuning: RenderTuning) throws -> Readout {
        let phone = PixelReader.planes(Self.phone(image, size: phoneSize))
        let smooth = PixelReader.luma(
            Self.phone(
                FrequencySeparation.blurred(image, radius: correlationRadius).cropped(to: photo.extent), size: phoneSize
            ))
        let original = PixelReader.luma(image.cropped(to: bandRect))
        func blurred(_ radius: Double) -> [Float] {
            PixelReader.luma(FrequencySeparation.blurred(image, radius: radius).cropped(to: bandRect))
        }
        let fine = blurred(radii.fine)
        let even = blurred(radii.even)
        let mid = blurred(radii.mid)
        let low = blurred(radii.low)
        let bands = [
            variance(zip(original, fine).map { $0 - $1 }),
            variance(zip(fine, mid).map { $0 - $1 }),
            variance(zip(even, mid).map { $0 - $1 }),
            variance(zip(mid, low).map { $0 - $1 }),
        ]
        let faceIndex = photo.faces.firstIndex { $0.boundingBox == photo.face.boundingBox } ?? 0
        let spots = try BlemishDetector(tuning: tuning, renderer: RenderingTestSupport.renderer).detect(
            image: photo.previewSized(image), faces: photo.faces)
        return Readout(
            phone: phone, smoothLuma: smooth, bands: bands, defects: defects(image, original: original),
            blemishes: spots.filter { $0.faceIndex == faceIndex }.count)
    }

    /// 매끈한 면에서 튀는 결함의 평균 크기(8비트).
    /// 어두운 점 = 닫힘(최대 → 최소) − 원본, 밝은 점 = 원본 − 열림(최소 → 최대).
    /// 닫힘·열림은 반지름보다 작은 점만 지우고 큰 명암(광대 그림자·조명)은 남긴다.
    /// 붉은 얼룩 = 넓게 흐린 Cr 위로 솟은 Cr의 양수 부분.
    /// 순서는 어두운 점·밝은 점·모공 크기 어두운 점·붉은 얼룩이다.
    private func defects(_ image: CIImage, original: [Float]) -> [Double] {
        func morphology(_ first: String, _ second: String, radius: Double) -> [Float] {
            let filtered = image.clampedToExtent()
                .applyingFilter(first, parameters: [kCIInputRadiusKey: radius])
                .applyingFilter(second, parameters: [kCIInputRadiusKey: radius])
            return PixelReader.luma(filtered.cropped(to: bandRect))
        }
        let maximum = "CIMorphologyMaximum"
        let minimum = "CIMorphologyMinimum"
        let darkSpots = zip(morphology(maximum, minimum, radius: radii.spot), original).map { $0 - $1 }
        let brightSpots = zip(original, morphology(minimum, maximum, radius: radii.spot)).map { $0 - $1 }
        let darkPores = zip(morphology(maximum, minimum, radius: radii.pore), original).map { $0 - $1 }
        let planes = PixelReader.planes(image.cropped(to: bandRect))
        let trend = PixelReader.planes(
            FrequencySeparation.blurred(image, radius: radii.blotch).cropped(to: bandRect))
        let blotches = (0..<planes.count).map { max(0, planes.cr($0) - trend.cr($0)) }
        return [darkSpots, brightSpots, darkPores, blotches].map(weightedMean)
    }

    private func weightedMean(_ values: [Float]) -> Double {
        var total = 0.0
        var sum = 0.0
        for (value, weight) in zip(values, bandWeight) where weight > 0 {
            total += Double(weight)
            sum += Double(weight) * Double(value)
        }
        return total > 0 ? sum / total : 0
    }

    /// 대역 안쪽 피부 가중 분산.
    private func variance(_ band: [Float]) -> Double {
        var total = 0.0
        var sum = 0.0
        var squares = 0.0
        for (value, weight) in zip(band, bandWeight) where weight > 0 {
            let w = Double(weight)
            total += w
            sum += w * Double(value)
            squares += w * Double(value) * Double(value)
        }
        guard total > 0 else { return 0 }
        let mean = sum / total
        return squares / total - mean * mean
    }

    func metrics(before: Readout, after: Readout) -> Metrics {
        let a = before.phone
        let b = after.phone
        var metrics = Metrics()
        metrics.deltaLuma = (0..<a.count).map { b.luma($0) - a.luma($0) }
        let skinDelta = Self.weightedMeans(a, b, weight: skin)
        metrics.skinLuma = skinDelta.luma
        metrics.skinCb = skinDelta.cb
        metrics.skinCr = skinDelta.cr
        metrics.skinChanged = changedFraction(a, b, weight: skin)
        metrics.bodyLuma = Self.weightedMeans(a, b, weight: body).luma
        metrics.bandRatios = zip(after.bands, before.bands).map { $1 > 0 ? $0 / $1 : 1 }
        metrics.defectRatios = zip(after.defects, before.defects).map { $1 > 0 ? $0 / $1 : 1 }
        metrics.crSpreadRatio = crSpread(b) / max(crSpread(a), Double.ulpOfOne)
        metrics.blemishRatio = before.blemishes > 0 ? Double(after.blemishes) / Double(before.blemishes) : .nan
        metrics.darkCircleLuma = Self.weightedMeans(a, b, weight: darkCircles).luma
        metrics.nasolabialLuma = Self.weightedMeans(a, b, weight: nasolabial).luma
        metrics.faceP99 = percentileAbsolute(metrics.deltaLuma, weight: faceBox)
        if let background {
            metrics.backgroundChanged = changedFraction(a, b, weight: background)
        }
        return metrics
    }

    /// ΔY 지도 두 개의 피부 가중 피어슨 상관.
    /// smoothBefore·smoothAfter는 흐린 휘도다.
    func correlation(before: Readout, ours: Readout, evoto: Readout) -> Double {
        let ourDelta = zip(ours.smoothLuma, before.smoothLuma).map { $0 - $1 }
        let evotoDelta = zip(evoto.smoothLuma, before.smoothLuma).map { $0 - $1 }
        var total = 0.0
        var sumA = 0.0
        var sumB = 0.0
        for index in skin.indices where skin[index] >= Calibration.maskInside {
            let w = Double(skin[index])
            total += w
            sumA += w * Double(ourDelta[index])
            sumB += w * Double(evotoDelta[index])
        }
        guard total > 0 else { return .nan }
        let meanA = sumA / total
        let meanB = sumB / total
        var covariance = 0.0
        var varianceA = 0.0
        var varianceB = 0.0
        for index in skin.indices where skin[index] >= Calibration.maskInside {
            let w = Double(skin[index])
            let da = Double(ourDelta[index]) - meanA
            let db = Double(evotoDelta[index]) - meanB
            covariance += w * da * db
            varianceA += w * da * da
            varianceB += w * db * db
        }
        guard varianceA > 0, varianceB > 0 else { return 0 }
        return covariance / (varianceA * varianceB).squareRoot()
    }

    private static func weightedMeans(_ a: Planes, _ b: Planes, weight: [Float]) -> (
        luma: Double, cb: Double, cr: Double
    ) {
        var total = 0.0
        var luma = 0.0
        var cb = 0.0
        var cr = 0.0
        for index in weight.indices where weight[index] > 0 {
            let w = Double(weight[index])
            total += w
            luma += w * Double(b.luma(index) - a.luma(index))
            cb += w * Double(b.cb(index) - a.cb(index))
            cr += w * Double(b.cr(index) - a.cr(index))
        }
        guard total > 0 else { return (.nan, .nan, .nan) }
        return (luma / total, cb / total, cr / total)
    }

    private func changedFraction(_ a: Planes, _ b: Planes, weight: [Float]) -> Double {
        var inside = 0
        var changed = 0
        for index in weight.indices where weight[index] >= Calibration.maskInside {
            inside += 1
            let delta = max(
                abs(b.red[index] - a.red[index]), abs(b.green[index] - a.green[index]),
                abs(b.blue[index] - a.blue[index]))
            if delta >= Calibration.changedDelta {
                changed += 1
            }
        }
        return inside > 0 ? Double(changed) / Double(inside) : .nan
    }

    /// 피부 안 Cr 표준편차(8비트).
    /// 붉은 반점·홍조가 줄면 작아진다.
    private func crSpread(_ planes: Planes) -> Double {
        var total = 0.0
        var sum = 0.0
        var squares = 0.0
        for index in skin.indices where skin[index] >= Calibration.maskInside {
            let w = Double(skin[index])
            let value = Double(planes.cr(index))
            total += w
            sum += w * value
            squares += w * value * value
        }
        guard total > 0 else { return 0 }
        let mean = sum / total
        return max(0, squares / total - mean * mean).squareRoot()
    }

    private func percentileAbsolute(_ delta: [Float], weight: [Float]) -> Double {
        let values = delta.indices.filter { weight[$0] >= Calibration.maskInside }.map { abs(delta[$0]) }.sorted()
        guard !values.isEmpty else { return .nan }
        return Double(values[min(values.count - 1, Int(Double(values.count - 1) * Calibration.percentile))])
    }
}

// MARK: 보고서

struct Report {
    private struct Section {
        let pair: EvotoPair
        let faces: Int
        let faceWidth: CGFloat
        let rows: [(name: String, metrics: Probe.Metrics)]
    }

    private var sections: [Section] = []
    private var skipped: [(EvotoPair, String)] = []

    mutating func skip(_ pair: EvotoPair, reason: String) {
        skipped.append((pair, reason))
    }

    mutating func add(_ pair: EvotoPair, photo: EvotoPhoto, rows: [(String, Probe.Metrics)]) {
        sections.append(Section(pair: pair, faces: photo.faces.count, faceWidth: photo.faceWidth, rows: rows))
    }

    private static let header = [
        "variant", "skinΔY", "skinΔCb", "skinΔCr", "skinChg", "bodyΔY", "fine", "mid", "even", "low", "dSpot",
        "bSpot", "dPore", "redBl", "Crσ",
        "blem", "corr", "DCΔY", "NLΔY", "p99", "bgChg",
    ]

    private static func format(_ value: Double, digits: Int = 2) -> String {
        value.isNaN ? "-" : String(format: "%.\(digits)f", value)
    }

    private static func cells(_ name: String, _ metrics: Probe.Metrics) -> [String] {
        [
            name, format(metrics.skinLuma), format(metrics.skinCb), format(metrics.skinCr),
            format(metrics.skinChanged, digits: 3), format(metrics.bodyLuma),
        ] + (metrics.bandRatios + metrics.defectRatios).map { format($0, digits: 3) } + [
            format(metrics.crSpreadRatio, digits: 3), format(metrics.blemishRatio), format(metrics.correlation),
            format(metrics.darkCircleLuma), format(metrics.nasolabialLuma), format(metrics.faceP99, digits: 1),
            format(metrics.backgroundChanged, digits: 3),
        ]
    }

    func markdown() -> String {
        var lines = [
            "# Evoto 보정 측정", "",
            "ΔY·ΔCb·ΔCr: 피부 마스크 가중 평균(8비트, 폰 배율).",
            "skinChg: 피부(가중치 ≥ 0.5) 중 세 채널 최대 |Δ| ≥ 4 비율.",
            "bodyΔY: 얼굴 밖 몸 피부 영역 평균 ΔY.",
            "fine·mid·even·low: 원본 배율 피부 안쪽 휘도 대역 분산 후/전 비(<0.6% · 0.6–3% · 1–3% · 3–12% 얼굴 폭).",
            "dSpot·bSpot: 반지름 1.2% 얼굴 폭 닫힘·열림으로 잰 어두운·밝은 점 평균 크기 후/전 비(주근깨·여드름 자국·땀 반사점).",
            "dPore: 반지름 0.3% 닫힘 어두운 점(모공 크기) 후/전 비. redBl: 6% 흐린 Cr 위로 솟은 붉은 얼룩 평균 후/전 비.",
            "Crσ: 피부 Cr 표준편차 후/전 비. blem: 잡티 검출 수 후/전 비.",
            "corr: Evoto ΔY 지도(1% 얼굴 폭 흐림)와의 피부 가중 상관.",
            "DCΔY·NLΔY: 다크서클·팔자 띠 평균 ΔY. p99: 얼굴 상자 |ΔY| 99분위. bgChg: 배경 바뀐 비율.", "",
        ]
        for section in sections {
            lines.append(
                "## \(section.pair.feature) / \(section.pair.key) (얼굴 \(section.faces), 얼굴 폭 \(Int(section.faceWidth))px)"
            )
            lines.append("")
            lines.append("| " + Self.header.joined(separator: " | ") + " |")
            lines.append("|" + Array(repeating: "---", count: Self.header.count).joined(separator: "|") + "|")
            for row in section.rows {
                lines.append("| " + Self.cells(row.name, row.metrics).joined(separator: " | ") + " |")
            }
            lines.append("")
        }
        for (pair, reason) in skipped {
            lines.append("- 건너뜀: \(pair.feature) / \(pair.key) — \(reason)")
        }
        return lines.joined(separator: "\n") + "\n"
    }

    func tsv() -> String {
        var lines = [(["feature", "key"] + Self.header).joined(separator: "\t")]
        for section in sections {
            for row in section.rows {
                lines.append(
                    ([section.pair.feature, section.pair.key] + Self.cells(row.name, row.metrics)).joined(
                        separator: "\t"))
            }
        }
        return lines.joined(separator: "\n") + "\n"
    }
}

// MARK: 나란히 보기

/// [before | Evoto | 기본 강도 | 최대 강도] 전체 띠와 피부 영역 확대 2×2.
enum Board {
    typealias Calibration = EvotoCalibrationTests.Calibration

    static func write(
        photo: EvotoPhoto, probe: Probe, family: EvotoCalibrationTests.Family, rendered: [String: CIImage], to base: URL
    ) throws {
        let panels: [(String, CIImage)] =
            [("before", photo.original), ("Evoto", photo.after)]
            + family.variants.compactMap { variant in rendered[variant.name].map { (variant.name, $0) } }
        let strip = tiled(
            panels.map { labeled(scaled($0.1, width: Calibration.panelWidth), $0.0) }, columns: panels.count)
        try writePNG(strip, to: base.appendingPathExtension("png"))
        let padding = photo.faceWidth * Calibration.zoomPadding
        let crop = probe.bandRect.insetBy(dx: -padding, dy: -padding).intersection(photo.extent).integral
        let zoom = tiled(
            panels.map { labeled(scaled($0.1.cropped(to: crop), width: Calibration.zoomPanelWidth), $0.0) },
            columns: Calibration.zoomPanelsPerRow)
        try writePNG(zoom, to: base.appendingPathExtension("zoom.png"))
    }

    private static func scaled(_ image: CIImage, width: CGFloat) -> CIImage {
        let moved = image.transformed(
            by: CGAffineTransform(translationX: -image.extent.minX, y: -image.extent.minY))
        let scale = width / moved.extent.width
        let size = CGSize(width: width, height: (moved.extent.height * scale).rounded(.down))
        return moved.applyingFilter(
            "CILanczosScaleTransform", parameters: [kCIInputScaleKey: scale, kCIInputAspectRatioKey: 1]
        ).cropped(to: CGRect(origin: .zero, size: size))
    }

    private static func labeled(_ image: CIImage, _ text: String) -> CIImage {
        guard
            let label = CIFilter(
                name: "CITextImageGenerator",
                parameters: ["inputText": text, "inputFontSize": Calibration.labelFontSize, "inputScaleFactor": 1]
            )?.outputImage
        else { return image }
        let margin = Calibration.labelMargin
        let box = label.extent.insetBy(dx: -margin, dy: -margin)
        let backdrop = CIImage(color: .white).cropped(to: box)
        let tag = label.composited(over: backdrop)
            .transformed(
                by: CGAffineTransform(translationX: margin - box.minX, y: image.extent.maxY - box.maxY - margin))
        return tag.composited(over: image).cropped(to: image.extent)
    }

    /// 왼쪽 위부터 채운다.
    private static func tiled(_ panels: [CIImage], columns: Int) -> CIImage {
        guard let first = panels.first else { return CIImage.empty() }
        let size = first.extent.size
        let rows = (panels.count + columns - 1) / columns
        var canvas = CIImage(color: .black).cropped(
            to: CGRect(x: 0, y: 0, width: size.width * CGFloat(columns), height: size.height * CGFloat(rows)))
        for (index, panel) in panels.enumerated() {
            let column = index % columns
            let row = rows - 1 - index / columns
            let placed = panel.transformed(
                by: CGAffineTransform(translationX: size.width * CGFloat(column), y: size.height * CGFloat(row)))
            canvas = placed.composited(over: canvas)
        }
        return canvas
    }

    private static func writePNG(_ image: CIImage, to url: URL) throws {
        let cgImage = try RenderingTestSupport.renderer.makeCGImage(image)
        guard
            let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)
        else { throw MellowError.renderFailed }
        CGImageDestinationAddImage(destination, cgImage, nil)
        guard CGImageDestinationFinalize(destination) else { throw MellowError.renderFailed }
    }
}

// MARK: 점 지우기 시제품

/// 새 렌더 능력 후보(G5 제안)의 측정용 시제품.
/// 렌더 단계가 아니고 측정 하네스 안에서만 렌더 결과 뒤에 건다.
/// 점 = 닫힘(spot 반지름) − 닫힘(pore 반지름)이라 모공 크기 명암은 그대로 두고 그보다 큰 주근깨·여드름 자국만 채운다.
/// 밝은 점(땀 반사점·좁쌀)은 열림으로 같은 방식이다.
/// 상대 깊이가 문턱보다 얕은 차이(피부 결)는 건드리지 않는다.
enum SpotPrototype {
    typealias Support = RenderingTestSupport

    static let spotRadiusFraction = 0.012
    static let poreRadiusFraction = 0.003
    /// 보정 지도를 흐리는 반지름.
    /// pore 반지름의 배수.
    /// 닫힘의 평평한 꼭대기 계단을 지운다.
    static let correctionBlurInPores = 1.0
    /// 국소 휘도 대비 상대 깊이 문턱(시작·끝).
    static let thresholdStart = 0.008
    static let thresholdEnd = 0.04
    static let lumaFloor = 0.01
    /// 이보다 깊은 상대 깊이(콧구멍·눈꼬리·입꼬리 같은 진짜 구조)는 점이 아니라서 건드리지 않는다.
    static let depthCapStart = 0.25
    static let depthCapEnd = 0.4
    /// 형태 필터 입력 여유.
    /// spot 반지름의 배수.
    static let morphologyPaddingInSpots = 3.0

    private static let floatContext = CIContext(options: [
        .workingColorSpace: CGColorSpace(name: CGColorSpace.extendedLinearSRGB)!
    ])

    private static let correctionKernel = CIColorKernel(
        source: """
            kernel vec4 spotCorrection(__sample darkFill, __sample darkPore, __sample brightCut, __sample brightPore,
                                       float start, float end, float capStart, float capEnd, float floorLuma) {
                vec3 luma = vec3(0.2126, 0.7152, 0.0722);
                vec3 dark = max(darkFill.rgb - darkPore.rgb, vec3(0.0));
                vec3 bright = max(brightPore.rgb - brightCut.rgb, vec3(0.0));
                float base = max(dot(darkPore.rgb, luma), floorLuma);
                float depth = dot(dark, luma) / base;
                float height = dot(bright, luma) / base;
                float wd = smoothstep(start, end, depth) * (1.0 - smoothstep(capStart, capEnd, depth));
                float wb = smoothstep(start, end, height) * (1.0 - smoothstep(capStart, capEnd, height));
                return vec4(dark * wd - bright * wb, 1.0);
            }
            """)

    private static let applyKernel = CIColorKernel(
        source: """
            kernel vec4 spotApply(__sample image, __sample correction, __sample mask, float amount) {
                return vec4(image.rgb + correction.rgb * mask.r * amount, image.a);
            }
            """)

    static func apply(_ image: CIImage, faces: [FaceGeometry], extent: CGRect, amount: Double, tuning: RenderTuning)
        throws -> CIImage
    {
        guard amount > 0, let correctionKernel, let applyKernel else { return image }
        var result = try EvotoPhoto.baked(image)
        for face in faces {
            let width = Double(FaceRegions.faceWidth(face, extent: extent))
            let spot = width * spotRadiusFraction
            let pore = max(tuning.skinBlurMinimumRadius, width * poreRadiusFraction)
            let bounds = FaceRegions.maskBounds(face: face, extent: extent, tuning: tuning)
            guard !bounds.isEmpty else { continue }
            // 형태 필터 입력은 가장자리 여유를 둔 유한 영역으로 자른다.
            let padding = CGFloat(spot * morphologyPaddingInSpots)
            let area = bounds.insetBy(dx: -padding, dy: -padding)
            let source = result.clampedToExtent().cropped(to: area)
            func morphology(_ first: String, _ second: String, _ radius: Double) -> CIImage {
                source.applyingFilter(first, parameters: [kCIInputRadiusKey: radius])
                    .applyingFilter(second, parameters: [kCIInputRadiusKey: radius]).cropped(to: bounds)
            }
            let maximum = "CIMorphologyMaximum"
            let minimum = "CIMorphologyMinimum"
            let arguments: [Any] = [
                morphology(maximum, minimum, spot), morphology(maximum, minimum, pore),
                morphology(minimum, maximum, spot), morphology(minimum, maximum, pore), thresholdStart, thresholdEnd,
                depthCapStart, depthCapEnd, lumaFloor,
            ]
            guard let raw = correctionKernel.apply(extent: bounds, arguments: arguments),
                let floats = floatContext.createCGImage(
                    raw, from: bounds, format: .RGBAf, colorSpace: CGColorSpace(name: CGColorSpace.extendedLinearSRGB))
            else { throw MellowError.renderFailed }
            // 형태 필터와 원본 합성을 한 그래프로 렌더하면 영역 밖이 늘어난 픽셀이 되어 보정 지도를 부동소수 비트맵으로 먼저 굳힌다.
            let correction = CIImage(
                cgImage: floats, options: [.colorSpace: CGColorSpace(name: CGColorSpace.extendedLinearSRGB)!]
            ).transformed(by: CGAffineTransform(translationX: bounds.minX, y: bounds.minY))
            let smoothed = correction.clampedToExtent()
                .applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: pore * correctionBlurInPores])
            let mask = try FaceRegions.skinMask(face: face, image: result, extent: extent, tuning: tuning)
            guard let fixed = applyKernel.apply(extent: bounds, arguments: [result, smoothed, mask, min(1, amount)])
            else { throw MellowError.renderFailed }
            let patch = try Support.renderer.makeCGImage(fixed.cropped(to: bounds))
            // 보정한 얼굴 영역만 비트맵으로 굳혀 원본 위에 얹는다.
            let placed = CIImage(cgImage: patch).transformed(
                by: CGAffineTransform(translationX: bounds.minX, y: bounds.minY))
            result = try EvotoPhoto.baked(placed.composited(over: result).cropped(to: extent))
        }
        return result
    }
}
