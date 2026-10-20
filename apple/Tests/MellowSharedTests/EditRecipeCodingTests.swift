import XCTest

@testable import MellowShared

final class EditRecipeCodingTests: XCTestCase {
    func testDefaultRecipeIsDefaultAndNeedsNoFaces() {
        let recipe = EditRecipe()
        XCTAssertTrue(recipe.isDefault)
        XCTAssertFalse(recipe.hasLocalEdits)
        XCTAssertFalse(recipe.dependsOnFaces)
    }

    func testRoundTripPreservesOperationsOrderAndSchemaVersion() throws {
        var recipe = EditRecipe()
        recipe.color.exposure = 0.4
        recipe.portrait.skin.smoothing = 0.3
        recipe.portrait.targetFace = 1
        recipe.operations = [
            .spot(RetouchSpot(x: 0.5, y: 0.4, sourceX: 0.45, sourceY: 0.4, radius: 0.02)),
            .warp(WarpStroke(x: 0.5, y: 0.4, dx: 0.01, dy: 0, radius: 0.08)),
        ]
        let data = try JSONEncoder().encode(recipe)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(json["schemaVersion"] as? Int, 2)
        let operations = try XCTUnwrap(json["operations"] as? [[String: Any]])
        XCTAssertEqual(operations[0]["type"] as? String, "spot")
        XCTAssertEqual(operations[1]["type"] as? String, "warp")
        XCTAssertEqual(operations[0]["sourceX"] as? Double, 0.45)
        let decoded = try JSONDecoder().decode(EditRecipe.self, from: data)
        XCTAssertEqual(decoded, recipe)
        XCTAssertTrue(decoded.dependsOnFaces)
        XCTAssertTrue(decoded.hasLocalEdits)
    }

    func testMissingKeysDecodeToDefaults() throws {
        let json = #"{"schemaVersion":2,"color":{"exposure":0.2}}"#
        let decoded = try JSONDecoder().decode(EditRecipe.self, from: Data(json.utf8))
        XCTAssertEqual(decoded.color.exposure, 0.2)
        XCTAssertEqual(decoded.color.contrast, 1)
        XCTAssertEqual(decoded.portrait, PortraitAdjustments())
        XCTAssertTrue(decoded.operations.isEmpty)
    }

    func testUnknownOperationTypeFailsLoudly() {
        let json = #"{"schemaVersion":2,"operations":[{"type":"glitter","x":0,"y":0}]}"#
        XCTAssertThrowsError(try JSONDecoder().decode(EditRecipe.self, from: Data(json.utf8)))
    }

    func testBuiltInPresetsMatchShippedIPhoneValues() {
        XCTAssertEqual(BuiltInPresets.all.map(\.name), ["내추럴", "포근한", "클린"])
        XCTAssertEqual(BuiltInPresets.cozy.values.color.warmth, 0.25)
        XCTAssertEqual(BuiltInPresets.cozy.values.portrait.skin.smoothing, 0.3)
        XCTAssertEqual(BuiltInPresets.clean.values.color.contrast, 1.05)
    }

    func testRecipeWithoutNewKeysDecodesToDefaults() throws {
        let json = #"{"schemaVersion":2,"color":{"exposure":0.2},"portrait":{},"operations":[]}"#
        let decoded = try JSONDecoder().decode(EditRecipe.self, from: Data(json.utf8))
        XCTAssertEqual(decoded.detail, DetailAdjustments())
        XCTAssertEqual(decoded.look, LookSelection())
        XCTAssertEqual(decoded.geometry, GeometryAdjustments())
        XCTAssertNil(decoded.look.id)
        XCTAssertEqual(decoded.look.intensity, 1)
        var plain = decoded
        plain.color.exposure = 0
        XCTAssertTrue(plain.isDefault)
    }

    func testNewFieldsRoundTripAndAffectDefaultness() throws {
        var recipe = EditRecipe()
        recipe.detail.highlights = -0.4
        recipe.look = LookSelection(id: "film", intensity: 0.7)
        recipe.geometry = GeometryAdjustments(
            flipHorizontal: true, quarterTurns: 1, straightenDegrees: -3,
            crop: NormalizedRect(x: 0.1, y: 0.2, width: 0.5, height: 0.5))
        XCTAssertFalse(recipe.isDefault)
        let data = try JSONEncoder().encode(recipe)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual((json["look"] as? [String: Any])?["id"] as? String, "film")
        XCTAssertEqual((json["geometry"] as? [String: Any])?["quarterTurns"] as? Int, 1)
        let decoded = try JSONDecoder().decode(EditRecipe.self, from: data)
        XCTAssertEqual(decoded, recipe)
    }

    func testNonFiniteGeometryIsNotFinite() {
        var recipe = EditRecipe()
        recipe.geometry.straightenDegrees = .infinity
        XCTAssertFalse(recipe.allValuesFinite)
        recipe.geometry.straightenDegrees = 0
        recipe.detail.vignette = .nan
        XCTAssertFalse(recipe.allValuesFinite)
    }

    func testPresetValuesCarryDetail() throws {
        let values = PresetValues(detail: DetailAdjustments(vignette: 0.3))
        let decoded = try JSONDecoder().decode(PresetValues.self, from: JSONEncoder().encode(values))
        XCTAssertEqual(decoded.detail.vignette, 0.3)
        let legacy = #"{"color":{},"portrait":{}}"#
        XCTAssertEqual(try JSONDecoder().decode(PresetValues.self, from: Data(legacy.utf8)).detail, DetailAdjustments())
    }

    func testLegacyPortraitKeysMigrateAndAreNotWritten() throws {
        let json = #"{"schemaVersion":2,"portrait":{"skinSmoothing":0.4,"faceSlim":0.3,"targetFace":1}}"#
        let decoded = try JSONDecoder().decode(EditRecipe.self, from: Data(json.utf8))
        XCTAssertEqual(decoded.portrait.skin, SkinAdjustments(smoothing: 0.4))
        XCTAssertEqual(decoded.portrait.face, FaceShapeAdjustments(width: -0.3))
        XCTAssertEqual(decoded.portrait.targetFace, 1)
        let data = try JSONEncoder().encode(decoded)
        let encoded = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let portrait = try XCTUnwrap(encoded["portrait"] as? [String: Any])
        XCTAssertEqual(Set(portrait.keys), ["targetFace", "skin", "face", "features"])
        XCTAssertEqual(try JSONDecoder().decode(EditRecipe.self, from: data), decoded)
    }

    func testNewPortraitKeysWinOverLegacyKeys() throws {
        let json =
            #"{"schemaVersion":2,"portrait":{"skinSmoothing":0.9,"skin":{"smoothing":0.2},"faceSlim":0.5,"face":{"jaw":0.1}}}"#
        let portrait = try JSONDecoder().decode(EditRecipe.self, from: Data(json.utf8)).portrait
        XCTAssertEqual(portrait.skin.smoothing, 0.2)
        XCTAssertEqual(portrait.face.width, 0)
        XCTAssertEqual(portrait.face.jaw, 0.1)
        XCTAssertEqual(FaceShapeAdjustments(legacyFaceSlim: 0).width.sign, .plus, "faceSlim 0은 −0이 아니라 0으로 옮긴다")
    }

    func testDependencyFlagsFollowEachGroup() {
        let base = EditRecipe()
        XCTAssertFalse(base.dependsOnFaces)
        XCTAssertFalse(base.dependsOnPerson)
        XCTAssertFalse(base.dependsOnBody)
        var recipe = base
        recipe.portrait.skin.autoBlemish = true
        XCTAssertTrue(recipe.dependsOnFaces, "자동 잡티만 켜도 얼굴이 필요하다")
        recipe = base
        recipe.portrait.face.width = -0.1
        XCTAssertTrue(recipe.dependsOnFaces)
        recipe = base
        recipe.portrait.features.teethWhiten = 0.1
        XCTAssertTrue(recipe.dependsOnFaces)
        recipe = base
        recipe.makeup.lip.intensity = 0.3
        XCTAssertTrue(recipe.dependsOnFaces)
        recipe = base
        recipe.makeup.lookID = "daily"
        XCTAssertFalse(recipe.dependsOnFaces, "룩 이름만으로는 렌더가 바뀌지 않는다")
        recipe = base
        recipe.background.blur = 0.5
        XCTAssertTrue(recipe.dependsOnPerson)
        XCTAssertFalse(recipe.dependsOnFaces)
        recipe = base
        recipe.body.waist = -0.2
        XCTAssertTrue(recipe.dependsOnBody)
    }

    func testEveryNewScalarIsCheckedForFiniteness() {
        let paths: [WritableKeyPath<EditRecipe, Double>] = [
            \.portrait.skin.smoothing, \.portrait.face.width, \.portrait.face.jaw, \.portrait.face.cheekbone,
            \.portrait.face.eyeSize, \.portrait.face.eyeDistance, \.portrait.face.noseWidth, \.portrait.face.mouthSize,
            \.portrait.face.smile, \.portrait.face.forehead, \.portrait.face.chinLength,
            \.portrait.features.eyeBrighten, \.portrait.features.teethWhiten, \.portrait.features.lipVitality,
            \.background.blur, \.body.legLength, \.body.waist, \.body.overall, \.body.arms, \.body.thighs,
            \.body.shoulders, \.body.neck, \.makeup.lip.intensity, \.makeup.blush.intensity,
            \.makeup.eyeshadow.intensity, \.makeup.brow.intensity, \.makeup.contour.intensity,
        ]
        for path in paths {
            var recipe = EditRecipe()
            recipe[keyPath: path] = .nan
            XCTAssertFalse(recipe.allValuesFinite, "\(path)")
        }
    }

    func testFullSkeletonRoundTrips() throws {
        var recipe = EditRecipe()
        recipe.portrait.skin = SkinAdjustments(smoothing: 0.5, autoBlemish: true)
        for key in FaceShapeKey.allCases {
            recipe.portrait.face[key] = -0.25
        }
        recipe.portrait.features = FeatureAdjustments(eyeBrighten: 0.2, teethWhiten: 0.3, lipVitality: 0.4)
        recipe.background.blur = 0.6
        for key in BodyShapeKey.allCases {
            recipe.body[key] = 0.1
        }
        recipe.makeup = MakeupAdjustments(
            lookID: "daily", lip: MakeupTint(colorID: "lip-coral", intensity: 0.5),
            blush: MakeupTint(colorID: "blush-peach", intensity: 0.3),
            eyeshadow: MakeupTint(colorID: "shadow-brown", intensity: 0.2), brow: MakeupStrength(intensity: 0.4),
            contour: MakeupStrength(intensity: 0.1))
        let data = try JSONEncoder().encode(recipe)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let portrait = try XCTUnwrap(json["portrait"] as? [String: Any])
        let face = try XCTUnwrap(portrait["face"] as? [String: Any])
        XCTAssertEqual(Set(face.keys), Set(FaceShapeKey.allCases.map(\.rawValue)))
        let body = try XCTUnwrap(json["body"] as? [String: Any])
        XCTAssertEqual(Set(body.keys), Set(BodyShapeKey.allCases.map(\.rawValue)))
        XCTAssertEqual((json["makeup"] as? [String: Any])?["lookID"] as? String, "daily")
        XCTAssertEqual(try JSONDecoder().decode(EditRecipe.self, from: data), recipe)
        XCTAssertFalse(recipe.isDefault)
    }

    func testPresetValuesCarryNewGroups() throws {
        var recipe = EditRecipe()
        recipe.portrait.skin.smoothing = 0.3
        recipe.background.blur = 0.4
        recipe.body.waist = -0.2
        recipe.makeup.brow.intensity = 0.5
        recipe.look.id = "film"
        let values = PresetValues(of: recipe)
        XCTAssertEqual(values.portrait.skin.smoothing, 0.3)
        XCTAssertEqual(values.background.blur, 0.4)
        XCTAssertEqual(values.body.waist, -0.2)
        XCTAssertEqual(values.makeup.brow.intensity, 0.5)
        XCTAssertEqual(try JSONDecoder().decode(PresetValues.self, from: JSONEncoder().encode(values)), values)
        let legacyJSON = #"{"color":{},"portrait":{"skinSmoothing":0.2}}"#
        let legacy = try JSONDecoder().decode(PresetValues.self, from: Data(legacyJSON.utf8))
        XCTAssertEqual(legacy.portrait.skin.smoothing, 0.2)
        XCTAssertEqual(legacy.background, BackgroundAdjustments())
        XCTAssertEqual(legacy.body, BodyShapeAdjustments())
        XCTAssertEqual(legacy.makeup, MakeupAdjustments())
    }

    func testShapeKeysAddressEveryValue() {
        var face = FaceShapeAdjustments()
        for (offset, key) in FaceShapeKey.allCases.enumerated() {
            face[key] = Double(offset + 1) / 10
        }
        XCTAssertEqual(face.numericValues, (1...10).map { Double($0) / 10 })
        XCTAssertEqual(face.width, Double(1) / 10)
        XCTAssertEqual(face.chinLength, Double(10) / 10)
        var body = BodyShapeAdjustments()
        for key in BodyShapeKey.allCases {
            body[key] = 0.5
        }
        XCTAssertEqual(body.numericValues, Array(repeating: 0.5, count: 7))
        var features = FeatureAdjustments()
        for key in FeatureKey.allCases {
            features[key] = 0.2
        }
        XCTAssertEqual(features.numericValues, [0.2, 0.2, 0.2])
        XCTAssertEqual(MakeupPart.allCases.filter(\.hasColor), [.lip, .blush, .eyeshadow])
    }

    func testSkinRefinementKeysRoundTripAndDefaultToIdentity() throws {
        let legacy = #"{"schemaVersion":2,"portrait":{"skin":{"smoothing":0.4,"autoBlemish":true}}}"#
        let decoded = try JSONDecoder().decode(EditRecipe.self, from: Data(legacy.utf8))
        XCTAssertEqual(decoded.portrait.skin, SkinAdjustments(smoothing: 0.4, autoBlemish: true), "G 이전 파일은 정밀 값이 0")
        XCTAssertEqual(decoded.portrait.skin.refinementValues, Array(repeating: 0, count: 7))
        XCTAssertFalse(decoded.portrait.skin.hasRefinement)
        var recipe = EditRecipe()
        for (offset, key) in SkinRefinementKey.allCases.enumerated() {
            recipe.portrait.skin[key] = Double(offset + 1) / 10
        }
        XCTAssertEqual(recipe.portrait.skin.refinementValues, (1...7).map { Double($0) / 10 })
        XCTAssertEqual(recipe.portrait.skin.darkCircles, 0.1)
        XCTAssertEqual(recipe.portrait.skin.marionette, 0.3)
        XCTAssertEqual(recipe.portrait.skin.shine, 0.7)
        XCTAssertEqual(recipe.portrait.skin.numericValues, [0] + (1...7).map { Double($0) / 10 })
        XCTAssertTrue(recipe.portrait.skin.hasEffect)
        XCTAssertTrue(recipe.dependsOnFaces, "정밀 값만 있어도 얼굴이 필요하다")
        XCTAssertFalse(recipe.dependsOnPerson)
        XCTAssertFalse(recipe.isDefault)
        let data = try JSONEncoder().encode(recipe)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let skin = try XCTUnwrap((json["portrait"] as? [String: Any])?["skin"] as? [String: Any])
        XCTAssertEqual(
            Set(skin.keys), Set(["smoothing", "autoBlemish"] + SkinRefinementKey.allCases.map(\.rawValue)))
        XCTAssertEqual(try JSONDecoder().decode(EditRecipe.self, from: data), recipe)
        XCTAssertEqual(AdjustmentRange.skinRefinement(.redness), AdjustmentRange.bipolar)
        for key in SkinRefinementKey.allCases where key != .redness {
            XCTAssertEqual(AdjustmentRange.skinRefinement(key), AdjustmentRange.unit, "\(key)")
        }
    }

    func testSkinRefinementScalarsAreCheckedForFinitenessAndCarriedByPresets() throws {
        let paths: [WritableKeyPath<EditRecipe, Double>] = [
            \.portrait.skin.darkCircles, \.portrait.skin.nasolabial, \.portrait.skin.marionette,
            \.portrait.skin.glabella, \.portrait.skin.toneEvening, \.portrait.skin.redness, \.portrait.skin.shine,
        ]
        for path in paths {
            var recipe = EditRecipe()
            recipe[keyPath: path] = .nan
            XCTAssertFalse(recipe.allValuesFinite, "\(path)")
        }
        var recipe = EditRecipe()
        recipe.portrait.skin.redness = -0.4
        let values = PresetValues(of: recipe)
        XCTAssertEqual(values.portrait.skin.redness, -0.4)
        XCTAssertEqual(try JSONDecoder().decode(PresetValues.self, from: JSONEncoder().encode(values)), values)
    }

    func testBodySkinRoundTripsDefaultsAndDependsOnPerson() throws {
        let legacy = #"{"schemaVersion":2,"background":{"blur":0.2}}"#
        let decoded = try JSONDecoder().decode(EditRecipe.self, from: Data(legacy.utf8))
        XCTAssertEqual(decoded.bodySkin, BodySkinAdjustments(), "G2 이전 파일은 몸 피부가 0")
        var recipe = EditRecipe()
        recipe.bodySkin = BodySkinAdjustments(brightness: 0.3, tone: -0.2, smoothing: 0.5)
        XCTAssertEqual(recipe.bodySkin.numericValues, [0.3, -0.2, 0.5])
        XCTAssertEqual(recipe.bodySkin[.tone], -0.2)
        XCTAssertTrue(recipe.bodySkin.hasEffect)
        XCTAssertTrue(recipe.dependsOnPerson, "몸 피부는 인물 마스크가 필요하다")
        XCTAssertFalse(recipe.dependsOnFaces, "얼굴 분석이 실패한 사진의 저장을 막지 않는다")
        XCTAssertFalse(recipe.isDefault)
        let data = try JSONEncoder().encode(recipe)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let bodySkin = try XCTUnwrap(json["bodySkin"] as? [String: Any])
        XCTAssertEqual(Set(bodySkin.keys), Set(BodySkinKey.allCases.map(\.rawValue)))
        XCTAssertEqual(try JSONDecoder().decode(EditRecipe.self, from: data), recipe)
        XCTAssertEqual(AdjustmentRange.bodySkin(.tone), AdjustmentRange.bipolar)
        XCTAssertEqual(AdjustmentRange.bodySkin(.brightness), AdjustmentRange.unit)
        XCTAssertEqual(AdjustmentRange.bodySkin(.smoothing), AdjustmentRange.unit)
    }

    func testBodySkinScalarsAreCheckedForFinitenessAndCarriedByPresets() throws {
        for path in [\EditRecipe.bodySkin.brightness, \EditRecipe.bodySkin.tone, \EditRecipe.bodySkin.smoothing] {
            var recipe = EditRecipe()
            recipe[keyPath: path] = .nan
            XCTAssertFalse(recipe.allValuesFinite, "\(path)")
        }
        var recipe = EditRecipe()
        recipe.bodySkin.tone = 0.4
        let values = PresetValues(of: recipe)
        XCTAssertEqual(values.bodySkin.tone, 0.4)
        XCTAssertEqual(try JSONDecoder().decode(PresetValues.self, from: JSONEncoder().encode(values)), values)
        let legacy = try JSONDecoder().decode(PresetValues.self, from: Data(#"{"color":{},"portrait":{}}"#.utf8))
        XCTAssertEqual(legacy.bodySkin, BodySkinAdjustments())
    }
}
