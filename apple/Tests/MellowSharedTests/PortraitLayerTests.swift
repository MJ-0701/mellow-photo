import XCTest

@testable import MellowShared

final class PortraitLayerTests: XCTestCase {
    func testLayerEncodesOnlyOverriddenKeysAndRoundTrips() throws {
        var layer = PortraitLayer()
        XCTAssertTrue(layer.isEmpty)
        XCTAssertFalse(layer.hasEffect)
        layer.skinSmoothing = 0.6
        layer.skinRefinement[.darkCircles] = 0.3
        layer.face[.width] = -0.3
        layer.makeup[.lip] = MakeupTint(colorID: "lip-rose", intensity: 0.5)
        layer.makeup[.brow] = MakeupTint(intensity: 0.2)
        layer.makeupLookID = "daily"
        XCTAssertEqual(
            layer.overriddenKeys,
            [.skinSmoothing, .skinRefinement(.darkCircles), .faceShape(.width), .makeupPart(.lip), .makeupPart(.brow)])
        XCTAssertTrue(layer.hasEffect)
        let data = try JSONEncoder().encode(layer)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(Set(json.keys), ["skin", "face", "makeup"], "비어 있는 features 그룹은 쓰지 않는다")
        let skin = try XCTUnwrap(json["skin"] as? [String: Any])
        XCTAssertEqual(Set(skin.keys), ["smoothing", "darkCircles"], "덮어쓰지 않은 키는 없다")
        XCTAssertEqual((json["face"] as? [String: Any])?["width"] as? Double, -0.3)
        let makeup = try XCTUnwrap(json["makeup"] as? [String: Any])
        XCTAssertEqual(Set(makeup.keys), ["lookID", "lip", "brow"])
        XCTAssertEqual(try JSONDecoder().decode(PortraitLayer.self, from: data), layer)
        let sparse = #"{"skin":{"autoBlemish":true},"makeup":{"lip":{"colorID":null,"intensity":0.4}}}"#
        let decoded = try JSONDecoder().decode(PortraitLayer.self, from: Data(sparse.utf8))
        XCTAssertEqual(decoded.autoBlemish, true)
        XCTAssertNil(decoded.skinSmoothing)
        XCTAssertEqual(decoded.makeup[.lip], MakeupTint(colorID: nil, intensity: 0.4), "colorID null은 색 없음으로 덮어쓴다")
        XCTAssertEqual(decoded.overriddenKeys, [.autoBlemish, .makeupPart(.lip)])
        XCTAssertEqual(try JSONDecoder().decode(PortraitLayer.self, from: Data("{}".utf8)), PortraitLayer())
    }

    func testLayerAppliesRemovesAndDiffs() {
        var portrait = PortraitAdjustments(
            skin: SkinAdjustments(smoothing: 0.2, autoBlemish: true), face: FaceShapeAdjustments(width: -0.1))
        var makeup = MakeupAdjustments(lookID: "cool", lip: MakeupTint(colorID: "lip-coral", intensity: 0.3))
        var layer = PortraitLayer(
            skinSmoothing: 0.6, face: [.jaw: 0.4],
            makeup: [.lip: MakeupTint(colorID: nil, intensity: 0.5), .contour: MakeupTint(intensity: 0.1)],
            makeupLookID: "daily")
        layer.applied(to: &portrait, makeup: &makeup)
        XCTAssertEqual(portrait.skin.smoothing, 0.6)
        XCTAssertTrue(portrait.skin.autoBlemish, "덮어쓰지 않은 키는 아래 층 값")
        XCTAssertEqual(portrait.face.width, -0.1)
        XCTAssertEqual(portrait.face.jaw, 0.4)
        XCTAssertNil(makeup.lip.colorID)
        XCTAssertEqual(makeup.lip.intensity, 0.5)
        XCTAssertEqual(makeup.contour.intensity, 0.1)
        XCTAssertEqual(makeup.lookID, "daily")
        layer.remove([.faceShape(.jaw), .makeupPart(.lip), .makeupPart(.contour)])
        XCTAssertEqual(layer.overriddenKeys, [.skinSmoothing])
        XCTAssertNil(layer.makeupLookID, "메이크업 키가 모두 빠지면 룩 이름도 지운다")
        var zero = PortraitLayer()
        zero.face[.width] = 0
        XCTAssertFalse(zero.isEmpty)
        XCTAssertFalse(zero.hasEffect, "0으로 덮어쓴 키는 상속을 끊지만 렌더는 바꾸지 않는다")
        let diff = PortraitLayer.difference(
            portrait: PortraitAdjustments(
                skin: SkinAdjustments(smoothing: 0.3), face: FaceShapeAdjustments(width: -0.2)),
            makeup: MakeupAdjustments(lookID: "rosy", blush: MakeupTint(colorID: "blush-pink", intensity: 0.4)))
        XCTAssertEqual(
            diff,
            PortraitLayer(
                skinSmoothing: 0.3, face: [.width: -0.2],
                makeup: [.blush: MakeupTint(colorID: "blush-pink", intensity: 0.4)], makeupLookID: "rosy"))
        XCTAssertEqual(
            PortraitLayer.difference(portrait: PortraitAdjustments(), makeup: MakeupAdjustments()), PortraitLayer())
        XCTAssertEqual(PortraitKey.all.count, 2 + 7 + 11 + 3 + 5 + 8)
        XCTAssertEqual(PortraitKey.skin.count, 9)
        XCTAssertTrue(PortraitKey.faceShape(.smile).isFaceShape)
        XCTAssertFalse(PortraitKey.feature(.teethWhiten).isFaceShape)
        XCTAssertEqual(PersonID.legacy(index: 1), PersonID.legacy(index: 1))
        XCTAssertNotEqual(PersonID.legacy(index: 1), PersonID.legacy(index: 2))
        // 이진수로 딱 떨어지는 값이라 중심 계산에 반올림 오차가 없다.
        XCTAssertEqual(
            PersonAnchor(faceBox: NormalizedRect(x: 0.25, y: 0.5, width: 0.25, height: 0.375)),
            PersonAnchor(x: 0.375, y: 0.6875, width: 0.25))
    }

    func testBodyLayerRoundTripsAndOmitsWhenEmpty() throws {
        let layer = PortraitLayer(body: [.waist: -0.5])
        let data = try JSONEncoder().encode(layer)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let body = try XCTUnwrap(json["body"] as? [String: Any])
        XCTAssertEqual(body as? [String: Double], ["waist": -0.5])
        XCTAssertEqual(try JSONDecoder().decode(PortraitLayer.self, from: data), layer)
        let empty = try XCTUnwrap(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(PortraitLayer())) as? [String: Any])
        XCTAssertNil(empty["body"], "빈 체형 사전은 쓰지 않는다")
        let legacy = #"{"skin":{"smoothing":0.3}}"#
        XCTAssertEqual(
            try JSONDecoder().decode(PortraitLayer.self, from: Data(legacy.utf8)).body, [:], "I 이전 층은 체형이 없다")
    }

    func testBodyKeysCountAsOverriddenAndEffect() {
        var zero = PortraitLayer(body: [.arms: 0])
        XCTAssertEqual(zero.overriddenKeys, [.bodyShape(.arms)])
        XCTAssertFalse(zero.hasEffect, "0으로 덮어쓴 체형은 렌더를 바꾸지 않는다")
        let moved = PortraitLayer(body: [.arms: 0.2])
        XCTAssertTrue(moved.hasEffect)
        XCTAssertTrue(moved.numericValues.contains(0.2))
        zero.remove([.bodyShape(.arms)])
        XCTAssertTrue(zero.body.isEmpty)
        XCTAssertTrue(zero.isEmpty)
        var portrait = PortraitAdjustments()
        var makeup = MakeupAdjustments()
        var body = BodyShapeAdjustments(waist: -0.1, arms: -0.4)
        moved.applied(to: &portrait, makeup: &makeup, body: &body)
        XCTAssertEqual(body.arms, 0.2, "층의 체형 키가 아래 값을 덮는다")
        XCTAssertEqual(body.waist, -0.1, "덮지 않은 체형 키는 아래 층 값")
    }

    func testIsShapeCoversFaceAndBody() {
        XCTAssertTrue(PortraitKey.faceShape(.jaw).isShape)
        XCTAssertTrue(PortraitKey.bodyShape(.waist).isShape)
        XCTAssertFalse(PortraitKey.skinSmoothing.isShape)
        XCTAssertFalse(PortraitKey.bodyShape(.waist).isFaceShape)
        XCTAssertTrue(PortraitKey.all.isSuperset(of: PortraitKey.bodyShapes))
        XCTAssertEqual(PortraitKey.bodyShapes.count, BodyShapeKey.allCases.count)
    }
}
