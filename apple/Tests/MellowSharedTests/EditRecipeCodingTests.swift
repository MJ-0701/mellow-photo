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
        recipe.people.individuals = [
            PersonRecord(id: .legacy(index: 1), legacyIndex: 1, layer: PortraitLayer(skinSmoothing: 0.3))
        ]
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
        XCTAssertEqual(decoded.portrait, PortraitAdjustments(), "옛 targetFace가 있어 값은 개인 층으로 간다")
        XCTAssertEqual(
            decoded.people.individuals.first?.layer, PortraitLayer(skinSmoothing: 0.4, face: [.width: -0.3]),
            "옛 키를 먼저 옮긴 뒤 개인 층으로 옮긴다")
        let data = try JSONEncoder().encode(decoded)
        let encoded = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let portrait = try XCTUnwrap(encoded["portrait"] as? [String: Any])
        XCTAssertEqual(Set(portrait.keys), ["skin", "face", "features"])
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
            \.portrait.face.smile, \.portrait.face.forehead, \.portrait.face.chinLength, \.portrait.face.doubleChin,
            \.portrait.features.eyeBrighten, \.portrait.features.teethWhiten, \.portrait.features.lipVitality,
            \.background.blur, \.body.legLength, \.body.waist, \.body.overall, \.body.arms, \.body.thighs,
            \.body.shoulders, \.body.neck, \.body.sideChest, \.makeup.lip.intensity, \.makeup.blush.intensity,
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
        XCTAssertEqual(face.numericValues, (1...11).map { Double($0) / 10 })
        XCTAssertEqual(face.width, Double(1) / 10)
        XCTAssertEqual(face.chinLength, Double(10) / 10)
        var body = BodyShapeAdjustments()
        for key in BodyShapeKey.allCases {
            body[key] = 0.5
        }
        XCTAssertEqual(body.numericValues, Array(repeating: 0.5, count: 8))
        var features = FeatureAdjustments()
        for key in FeatureKey.allCases {
            features[key] = 0.2
        }
        XCTAssertEqual(features.numericValues, [0.2, 0.2, 0.2])
        XCTAssertEqual(MakeupPart.allCases.filter(\.hasColor), [.lip, .blush, .eyeshadow])
    }

    func testDoubleChinAndSideChestDecodeAsZeroWhenMissing() throws {
        let json = #"{"schemaVersion":2,"portrait":{"face":{"width":-0.2}},"body":{"waist":-0.4,"neck":0.1}}"#
        let recipe = try JSONDecoder().decode(EditRecipe.self, from: Data(json.utf8))
        XCTAssertEqual(recipe.portrait.face.doubleChin, 0, "I 이전 파일은 이중턱이 0")
        XCTAssertEqual(recipe.body.sideChest, 0, "I 이전 파일은 부유방이 0")
        XCTAssertEqual(recipe.portrait.face.width, -0.2)
        XCTAssertEqual(recipe.body.waist, -0.4)
    }

    func testDoubleChinAndSideChestRoundTrip() throws {
        var recipe = EditRecipe()
        recipe.portrait.face.doubleChin = 0.4
        recipe.body.sideChest = 0.7
        let data = try JSONEncoder().encode(recipe)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let body = try XCTUnwrap(json["body"] as? [String: Any])
        XCTAssertEqual(body["sideChest"] as? Double, 0.7)
        let decoded = try JSONDecoder().decode(EditRecipe.self, from: data)
        XCTAssertEqual(decoded, recipe)
        XCTAssertEqual(decoded.portrait.face[.doubleChin], 0.4)
        XCTAssertEqual(decoded.body[.sideChest], 0.7)
    }

    func testNewShapeKeysAreUnitRange() {
        XCTAssertEqual(AdjustmentRange.faceShape(.doubleChin), 0...1)
        XCTAssertEqual(AdjustmentRange.bodyShape(.sideChest), 0...1)
        XCTAssertEqual(AdjustmentRange.faceShape(.smile), AdjustmentRange.unit)
        XCTAssertEqual(AdjustmentRange.bodyShape(.legLength), AdjustmentRange.unit)
        XCTAssertEqual(AdjustmentRange.faceShape(.chinLength), AdjustmentRange.bipolar)
        XCTAssertEqual(AdjustmentRange.bodyShape(.neck), AdjustmentRange.bipolar)
        XCTAssertEqual(FaceShapeKey.allCases.last, .doubleChin, "새 키는 마지막에 둔다")
        XCTAssertEqual(BodyShapeKey.allCases.last, .sideChest, "새 키는 마지막에 둔다")
    }

    func testSkinRefinementKeysRoundTripAndDefaultToIdentity() throws {
        let legacy = #"{"schemaVersion":2,"portrait":{"skin":{"smoothing":0.4,"autoBlemish":true}}}"#
        let decoded = try JSONDecoder().decode(EditRecipe.self, from: Data(legacy.utf8))
        XCTAssertEqual(decoded.portrait.skin, SkinAdjustments(smoothing: 0.4, autoBlemish: true), "G 이전 파일은 정밀 값이 0")
        let count = SkinRefinementKey.allCases.count
        XCTAssertEqual(decoded.portrait.skin.refinementValues, Array(repeating: 0, count: count))
        XCTAssertEqual(decoded.portrait.skin.spots, 0, "G5 이전 파일은 점 지우기가 0")
        XCTAssertEqual(decoded.portrait.skin.chromaEvening, 0, "G5 이전 파일은 얼룩 색 고르기가 0")
        XCTAssertFalse(decoded.portrait.skin.hasRefinement)
        var recipe = EditRecipe()
        for (offset, key) in SkinRefinementKey.allCases.enumerated() {
            recipe.portrait.skin[key] = Double(offset + 1) / 10
        }
        XCTAssertEqual(recipe.portrait.skin.refinementValues, (1...count).map { Double($0) / 10 })
        XCTAssertEqual(recipe.portrait.skin.darkCircles, 0.1)
        XCTAssertEqual(recipe.portrait.skin.marionette, 0.3)
        XCTAssertEqual(recipe.portrait.skin.chromaEvening, 0.6)
        XCTAssertEqual(recipe.portrait.skin.shine, 0.8)
        XCTAssertEqual(recipe.portrait.skin.spots, 0.9)
        XCTAssertEqual(recipe.portrait.skin.numericValues, [0] + (1...count).map { Double($0) / 10 })
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
        var spotted = EditRecipe()
        spotted.portrait.skin.spots = 0.4
        spotted.portrait.skin.chromaEvening = 0.3
        let spottedData = try JSONEncoder().encode(spotted)
        let spottedSkin = try JSONDecoder().decode(EditRecipe.self, from: spottedData).portrait.skin
        XCTAssertEqual(spottedSkin.spots, 0.4)
        XCTAssertEqual(spottedSkin.chromaEvening, 0.3)
        XCTAssertEqual(AdjustmentRange.skinRefinement(.redness), AdjustmentRange.bipolar)
        for key in SkinRefinementKey.allCases where key != .redness {
            XCTAssertEqual(AdjustmentRange.skinRefinement(key), AdjustmentRange.unit, "\(key)")
        }
    }

    func testSkinRefinementScalarsAreCheckedForFinitenessAndCarriedByPresets() throws {
        let paths: [WritableKeyPath<EditRecipe, Double>] = [
            \.portrait.skin.darkCircles, \.portrait.skin.nasolabial, \.portrait.skin.marionette,
            \.portrait.skin.glabella, \.portrait.skin.toneEvening, \.portrait.skin.chromaEvening,
            \.portrait.skin.redness, \.portrait.skin.shine, \.portrait.skin.spots,
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

    func testEffectsRoundTripDefaultsAndNeedNoAnalysis() throws {
        let legacy = #"{"schemaVersion":2,"look":{"id":"film"}}"#
        let decoded = try JSONDecoder().decode(EditRecipe.self, from: Data(legacy.utf8))
        XCTAssertEqual(decoded.effects, EffectAdjustments(), "G3 이전 파일은 효과가 0")
        var recipe = EditRecipe()
        recipe.effects = EffectAdjustments(grain: 0.3, glow: 0.6)
        XCTAssertEqual(recipe.effects.numericValues, [0.3, 0.6])
        XCTAssertEqual(recipe.effects[.glow], 0.6)
        XCTAssertTrue(recipe.effects.hasEffect)
        XCTAssertFalse(recipe.dependsOnFaces)
        XCTAssertFalse(recipe.dependsOnPerson)
        XCTAssertFalse(recipe.dependsOnBody)
        XCTAssertFalse(recipe.isDefault)
        let data = try JSONEncoder().encode(recipe)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(
            Set(try XCTUnwrap(json["effects"] as? [String: Any]).keys), Set(EffectKey.allCases.map(\.rawValue)))
        XCTAssertEqual(try JSONDecoder().decode(EditRecipe.self, from: data), recipe)
    }

    func testEffectScalarsAreCheckedForFinitenessAndCarriedByPresets() throws {
        for path in [\EditRecipe.effects.grain, \EditRecipe.effects.glow] {
            var recipe = EditRecipe()
            recipe[keyPath: path] = .nan
            XCTAssertFalse(recipe.allValuesFinite, "\(path)")
        }
        var recipe = EditRecipe()
        recipe.effects.grain = 0.2
        let values = PresetValues(of: recipe)
        XCTAssertEqual(values.effects.grain, 0.2)
        XCTAssertEqual(try JSONDecoder().decode(PresetValues.self, from: JSONEncoder().encode(values)), values)
        let legacy = try JSONDecoder().decode(PresetValues.self, from: Data(#"{"color":{},"portrait":{}}"#.utf8))
        XCTAssertEqual(legacy.effects, EffectAdjustments())
    }

    func testPeopleRoundTripAndDefaultToEmpty() throws {
        let legacy = #"{"schemaVersion":2,"portrait":{"skin":{"smoothing":0.4}}}"#
        let decoded = try JSONDecoder().decode(EditRecipe.self, from: Data(legacy.utf8))
        XCTAssertEqual(decoded.people, PeopleAdjustments())
        XCTAssertFalse(decoded.people.hasEffect)
        XCTAssertTrue(decoded.dependsOnFaces, "전체 층의 피부 값은 그대로 얼굴이 필요하다")
        var recipe = EditRecipe()
        let anchor = PersonAnchor(x: 0.3, y: 0.6, width: 0.12)
        let id = PersonID()
        recipe.people.groups[.female] = PortraitLayer(skinSmoothing: 0.5)
        recipe.people.individuals = [
            PersonRecord(id: id, anchor: anchor, gender: .female, layer: PortraitLayer(face: [.width: -0.3]))
        ]
        XCTAssertTrue(recipe.people.hasEffect)
        XCTAssertTrue(recipe.dependsOnFaces, "층 값만 있어도 얼굴이 필요하다")
        XCTAssertFalse(recipe.isDefault)
        let data = try JSONEncoder().encode(recipe)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let people = try XCTUnwrap(json["people"] as? [String: Any])
        XCTAssertEqual(Set(people.keys), ["groups", "individuals"])
        XCTAssertEqual(
            (people["groups"] as? [String: Any]).map { Set($0.keys) } ?? [], ["female"], "비어 있는 male 그룹은 쓰지 않는다")
        let record = try XCTUnwrap((people["individuals"] as? [[String: Any]])?.first)
        XCTAssertEqual(Set(record.keys), ["id", "anchor", "gender", "layer"], "legacyIndex가 없으면 키도 없다")
        XCTAssertEqual(record["gender"] as? String, "female")
        XCTAssertEqual(try JSONDecoder().decode(EditRecipe.self, from: data), recipe)
        XCTAssertEqual(recipe.people.person(id)?.anchor, anchor)
        let nearby = NormalizedRect(x: 0.32 - 0.055, y: 0.61 - 0.07, width: 0.11, height: 0.14)
        let far = NormalizedRect(x: 0.8 - 0.06, y: 0.6 - 0.07, width: 0.12, height: 0.14)
        XCTAssertEqual(recipe.people.personID(forFace: 0, of: [nearby]), id)
        XCTAssertNil(recipe.people.personID(forFace: 0, of: [far]))
        let empty = try JSONDecoder().decode(EditRecipe.self, from: Data(#"{"schemaVersion":2,"people":{}}"#.utf8))
        XCTAssertTrue(empty.isDefault)
        XCTAssertTrue(
            try XCTUnwrap(String(data: JSONEncoder().encode(EditRecipe()), encoding: .utf8)).contains("\"people\":{}"),
            "레시피는 people 키를 늘 쓴다")
        let genderOnly = EditRecipe(
            people: PeopleAdjustments(individuals: [PersonRecord(id: id, anchor: anchor, gender: .male)]))
        XCTAssertFalse(genderOnly.people.hasEffect, "성별 지정만으로는 렌더가 바뀌지 않는다")
        XCTAssertFalse(genderOnly.dependsOnFaces)
        var pruned = genderOnly.people
        pruned.individuals.append(PersonRecord(id: PersonID(), anchor: anchor))
        pruned.prune()
        XCTAssertEqual(pruned.individuals.count, 1, "성별도 층도 없는 기록만 지운다")
    }

    func testPeopleScalarsAreCheckedForFinitenessAndPresetsCarryGroupsOnly() throws {
        var recipe = EditRecipe()
        recipe.people.groups[.male] = PortraitLayer(face: [.jaw: .nan])
        XCTAssertFalse(recipe.allValuesFinite)
        recipe.people.groups[.male] = PortraitLayer(face: [.jaw: 0.2])
        recipe.people.individuals = [
            PersonRecord(
                id: PersonID(), anchor: PersonAnchor(x: 0.5, y: 0.5, width: 0.2),
                layer: PortraitLayer(skinSmoothing: .infinity))
        ]
        XCTAssertFalse(recipe.allValuesFinite)
        recipe.people.individuals[0].layer.skinSmoothing = 0.7
        XCTAssertTrue(recipe.allValuesFinite)
        let values = PresetValues(of: recipe)
        XCTAssertEqual(values.people.groups[.male], PortraitLayer(face: [.jaw: 0.2]))
        XCTAssertTrue(values.people.individuals.isEmpty, "프리셋은 개인 층을 나르지 않는다")
        let data = try JSONEncoder().encode(values)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual((json["people"] as? [String: Any]).map { Set($0.keys) } ?? [], ["groups"])
        let smuggled = """
            {"color":{},"portrait":{},"people":{"individuals":[{"id":"44444444-4444-4444-4444-444444444444",\
            "anchor":{"x":0.5,"y":0.5,"width":0.2},"layer":{"skin":{"smoothing":1}}}]}}
            """
        let decoded = try JSONDecoder().decode(PresetValues.self, from: Data(smuggled.utf8))
        XCTAssertTrue(decoded.people.individuals.isEmpty, "파일에 든 개인 층은 무시한다")
    }

    func testPruneDropsEmptyGroupLayersSoTheRecipeStaysDefault() throws {
        var recipe = EditRecipe()
        recipe.people.groups[.male] = PortraitLayer(skinSmoothing: 0.3)
        recipe.people.groups[.female] = PortraitLayer(face: [.jaw: 0.1])
        recipe.people.groups[.male]?.remove([.skinSmoothing])
        recipe.people.groups[.female]?.remove([.faceShape(.jaw)])
        XCTAssertFalse(recipe.isDefault, "빈 층이 남아 있으면 기본과 다르다")
        recipe.people.prune()
        XCTAssertTrue(recipe.people.groups.isEmpty)
        XCTAssertTrue(recipe.isDefault)
        XCTAssertEqual(try JSONDecoder().decode(EditRecipe.self, from: JSONEncoder().encode(recipe)), recipe)
        recipe.people.groups[.female] = PortraitLayer(skinSmoothing: 0.2)
        recipe.people.groups[.male] = PortraitLayer()
        recipe.people.prune()
        XCTAssertEqual(recipe.people.groups, [.female: PortraitLayer(skinSmoothing: 0.2)], "값이 있는 그룹은 남긴다")
        XCTAssertEqual(try JSONDecoder().decode(EditRecipe.self, from: JSONEncoder().encode(recipe)), recipe)
    }

    func testPersonRecordsDecodeLenientlyAndOnlyBrokenRecordsAreDropped() throws {
        let json = """
            {"schemaVersion":2,"people":{"individuals":[\
            {"id":"11111111-1111-1111-1111-111111111111","anchor":{"x":0.3,"y":0.5,"width":0.1},"gender":"other"},\
            {"id":"not-a-uuid","anchor":{"x":0.5,"y":0.5,"width":0.1},"layer":{"skin":{"smoothing":0.4}}},\
            {"anchor":{"x":0.7,"y":0.5,"width":0.1},"layer":{}},\
            {"id":"22222222-2222-2222-2222-222222222222","legacyIndex":1,"gender":"female",\
            "layer":{"face":{"width":-0.2}}}]}}
            """
        let recipe = try JSONDecoder().decode(EditRecipe.self, from: Data(json.utf8))
        XCTAssertEqual(recipe.people.individuals.count, 2, "id가 없거나 잘못된 기록만 버린다")
        let first = recipe.people.individuals[0]
        XCTAssertEqual(first.layer, PortraitLayer(), "layer가 없으면 빈 층")
        XCTAssertNil(first.gender, "모르는 성별 문자열은 미지정")
        XCTAssertEqual(first.anchor, PersonAnchor(x: 0.3, y: 0.5, width: 0.1))
        let second = recipe.people.individuals[1]
        XCTAssertEqual(second.gender, .female)
        XCTAssertEqual(second.legacyIndex, 1)
        XCTAssertEqual(second.layer, PortraitLayer(face: [.width: -0.2]))
    }

    func testLegacyTargetFaceMigratesIntoAPersonRecord() throws {
        let legacy = """
            {"schemaVersion":2,"portrait":{"targetFace":1,"skin":{"smoothing":0.5,"autoBlemish":true,"darkCircles":0.2},\
            "face":{"width":-0.3},"features":{"eyeBrighten":0.4}},\
            "makeup":{"lookID":"daily","lip":{"colorID":"lip-coral","intensity":0.5},"brow":{"intensity":0.2}},\
            "color":{"exposure":0.1}}
            """
        let decoded = try JSONDecoder().decode(EditRecipe.self, from: Data(legacy.utf8))
        XCTAssertEqual(decoded.portrait, PortraitAdjustments(), "전체 층은 비운다")
        XCTAssertEqual(decoded.makeup, MakeupAdjustments())
        XCTAssertEqual(decoded.color.exposure, 0.1)
        XCTAssertEqual(decoded.people.individuals.count, 1)
        let record = decoded.people.individuals[0]
        XCTAssertEqual(record.id, .legacy(index: 1))
        XCTAssertEqual(record.legacyIndex, 1)
        XCTAssertNil(record.anchor)
        XCTAssertNil(record.gender)
        XCTAssertEqual(
            record.layer,
            PortraitLayer(
                skinSmoothing: 0.5, autoBlemish: true, skinRefinement: [.darkCircles: 0.2], face: [.width: -0.3],
                features: [.eyeBrighten: 0.4],
                makeup: [.lip: MakeupTint(colorID: "lip-coral", intensity: 0.5), .brow: MakeupTint(intensity: 0.2)],
                makeupLookID: "daily"))
        XCTAssertTrue(decoded.dependsOnFaces)
        XCTAssertEqual(try JSONDecoder().decode(EditRecipe.self, from: Data(legacy.utf8)), decoded, "이행은 결정적이다")
        let reencoded = try XCTUnwrap(String(data: JSONEncoder().encode(decoded), encoding: .utf8))
        XCTAssertFalse(reencoded.contains("targetFace"), "다시 쓰면 옛 키가 없다")
        XCTAssertTrue(reencoded.contains("\"legacyIndex\":1"))
        let bare = #"{"schemaVersion":2,"portrait":{"targetFace":0}}"#
        XCTAssertTrue(try JSONDecoder().decode(EditRecipe.self, from: Data(bare.utf8)).isDefault, "옮길 값이 없으면 기록도 없다")
        let outOfRange = #"{"schemaVersion":2,"portrait":{"targetFace":7,"skin":{"smoothing":0.5}}}"#
        XCTAssertEqual(
            try JSONDecoder().decode(EditRecipe.self, from: Data(outOfRange.utf8)).people.individuals[0].legacyIndex, 7,
            "범위 밖 인덱스도 그대로 옮긴다(짝이 없어 렌더에서 빠짐, 옛 결과와 같음)")
        let both = """
            {"schemaVersion":2,"portrait":{"targetFace":0,"skin":{"smoothing":0.5}},\
            "people":{"individuals":[{"id":"44444444-4444-4444-4444-444444444444","anchor":{"x":0.5,"y":0.5,"width":0.2},\
            "layer":{"skin":{"smoothing":0.1}}}]}}
            """
        let kept = try JSONDecoder().decode(EditRecipe.self, from: Data(both.utf8))
        XCTAssertEqual(kept.portrait.skin.smoothing, 0.5, "people이 이미 있으면 이행하지 않는다")
        XCTAssertEqual(kept.people.individuals.count, 1)
        for corrupt in ["-1", "9999999999999"] {
            let json = #"{"schemaVersion":2,"portrait":{"targetFace":"# + corrupt + #","skin":{"smoothing":0.5}}}"#
            let record = try XCTUnwrap(
                JSONDecoder().decode(EditRecipe.self, from: Data(json.utf8)).people.individuals.first)
            XCTAssertEqual(record.legacyIndex, PersonID.legacyIndexRange.upperBound, "손상된 인덱스 \(corrupt)는 범위 끝으로")
            XCTAssertTrue(
                PersonMatcher.match([record], faces: [NormalizedRect(x: 0.1, y: 0.1, width: 0.2, height: 0.2)]).isEmpty)
        }
        var manual = EditRecipe()
        manual.portrait.skin.smoothing = 0.3
        manual.migrateLegacyTargetFace(2)
        XCTAssertEqual(manual.people.individuals[0].id, .legacy(index: 2))
        XCTAssertEqual(manual.portrait.skin.smoothing, 0)
        var withPeople = EditRecipe()
        withPeople.portrait.skin.smoothing = 0.3
        withPeople.people.individuals = [PersonRecord(anchor: PersonAnchor(x: 0.5, y: 0.5, width: 0.2), gender: .male)]
        let before = withPeople
        withPeople.migrateLegacyTargetFace(0)
        XCTAssertEqual(withPeople, before, "사람 기록이 이미 있으면 이행하지 않고 기존 기록을 덮어쓰지 않는다")
    }

    func testPortraitAdjustmentsNoLongerCarryATargetFace() throws {
        let json = try XCTUnwrap(
            JSONSerialization.jsonObject(
                with: JSONEncoder().encode(PortraitAdjustments(skin: SkinAdjustments(smoothing: 0.2))))
                as? [String: Any])
        XCTAssertEqual(Set(json.keys), ["skin", "face", "features"])
        let schemaURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("shared/recipe-schema/edit-recipe.v2.schema.json")
        let schema = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: schemaURL)) as? [String: Any])
        let portrait = try XCTUnwrap(
            ((schema["properties"] as? [String: Any])?["portrait"] as? [String: Any])?["properties"] as? [String: Any])
        XCTAssertEqual((portrait["targetFace"] as? [String: Any])?["deprecated"] as? Bool, true)
    }

    func testPresetValuesCarryOneTouchMarksAndLegacyMigrationDropsThem() throws {
        var recipe = EditRecipe()
        OneTouchBundle.layer(for: nil, strength: 0.6).applied(to: &recipe.portrait, makeup: &recipe.makeup)
        recipe.portrait.oneTouch = 0.6
        recipe.people.groups[.male] = OneTouchBundle.layer(for: .male, strength: 0.6)
        recipe.people.individuals = [PersonRecord(layer: PortraitLayer(oneTouch: 1))]
        let values = PresetValues(of: recipe)
        let decoded = try JSONDecoder().decode(PresetValues.self, from: JSONEncoder().encode(values))
        XCTAssertEqual(decoded, values)
        XCTAssertEqual(decoded.portrait.oneTouch, 0.6, "프리셋은 전체 층 표시를 나른다")
        XCTAssertEqual(decoded.people.groups[.male]?.oneTouch, 0.6, "프리셋은 그룹 층 표시를 나른다")
        XCTAssertTrue(decoded.people.individuals.isEmpty, "개인 층 표시는 나르지 않는다")
        let legacy = #"{"schemaVersion":2,"portrait":{"targetFace":1,"oneTouch":0.6,"skin":{"smoothing":0.4}}}"#
        let migrated = try JSONDecoder().decode(EditRecipe.self, from: Data(legacy.utf8))
        XCTAssertNil(migrated.portrait.oneTouch, "옛 대상 이행은 전체 층을 비우므로 표시도 사라진다")
        XCTAssertNil(migrated.people.individuals.first?.layer.oneTouch, "표시는 개인 층으로 옮기지 않는다")
        XCTAssertEqual(migrated.people.individuals.first?.layer.skinSmoothing, 0.4)
    }
}
