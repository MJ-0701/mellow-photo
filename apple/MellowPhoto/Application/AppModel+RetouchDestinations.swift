import CoreGraphics
import Foundation
import MellowRendering
import MellowShared

extension AppModel {
    func openRetouchDestination(_ destination: RetouchDestination) {
        endSliderEditIfActive()
        if destination == .sideChest, !showsBodyShape(.sideChest) {
            guard faces.count == 1 else {
                focusedRetouchDestination = destination
                selectTool(.region)
                statusMessage = "부유방을 조절할 사람을 아래에서 먼저 골라주세요. 성별을 자동으로 지정하지 않아요."
                return
            }
            setBeautyTarget(.face(0))
        }
        focusedRetouchDestination = destination
        retouchNavigationID = UUID()
        showsDetailAdjustments = true
        switch destination {
        case .skin, .skinRefinement:
            beautyTab = .skin
            selectTool(.beauty)
        case .bodySkin:
            beautyTab = .skinTone
            selectTool(.beauty)
        case .faceShape:
            beautyTab = .face
            selectTool(.beauty)
        case .feature:
            beautyTab = .features
            selectTool(.beauty)
        case .bodyShape:
            selectTool(.body)
        case .tool(let tool): selectTool(tool)
        }
        statusMessage = "\(destination.title): 값을 조절해 적용하세요. 부위 선택만으로 사진은 바뀌지 않아요."
    }

    var regionSelectionUnavailableReason: String? {
        guard isReady else { return "사진을 준비한 뒤 사용할 수 있어요." }
        guard !isRendering, !isWorkStopped, lastRenderFailure == nil else {
            return "보정 화면이 완성된 뒤 부위를 선택해 주세요. 기다리는 동안 아래 목록은 이용할 수 있어요."
        }
        let recipe = currentRecipe
        let personalShape = recipe.people.individuals.contains {
            $0.layer.face.values.contains { $0 != 0 } || $0.layer.body.values.contains { $0 != 0 }
        }
        let groupShape = recipe.people.groups.values.contains {
            $0.face.values.contains { $0 != 0 } || $0.body.values.contains { $0 != 0 }
        }
        if !recipe.warps.isEmpty || recipe.portrait.face.hasEffect || recipe.body.hasEffect || personalShape
            || groupShape
        {
            return "형태를 변형한 사진은 클릭 위치를 정확히 찾을 수 없어요. 아래 목록에서 사람과 도구를 골라주세요."
        }
        if compareMode != .off { return "원본 비교를 끄고 보정 화면에서 부위를 선택해 주세요." }
        if selectedInfo?.faceAnalysisFailure != nil { return UserMessage.quickFaceUnavailable }
        return nil
    }

    func selectRetouchRegion(at point: NormalizedPoint) {
        guard regionSelectionUnavailableReason == nil else {
            statusMessage = regionSelectionUnavailableReason ?? "부위를 선택할 수 없어요."
            return
        }
        endSliderEditIfActive()
        let candidates = faces.indices.filter { index in
            let box = faces[index].boundingBox.cgRect
            return box.insetBy(dx: 0, dy: -box.height * RegionPolicy.chinReach).contains(
                CGPoint(x: point.x, y: point.y))
        }
        let bodyCandidates = (selectedInfo?.bodyRegions ?? [:]).filter { _, body in
            body.boundingBox.cgRect.contains(CGPoint(x: point.x, y: point.y))
        }
        // 얼굴과 다른 사람의 몸이 겹친 위치도 임의로 한 사람에게 배정하지 않는다.
        let bodyFaces = bodyCandidates.keys.compactMap { bodyFaceMatches[$0] }
        if candidates.isEmpty {
            selectBodyRetouchRegion(at: point, candidates: bodyCandidates)
            return
        }
        guard candidates.count == 1, let index = candidates.first,
            bodyFaces.allSatisfy({ $0 == index }), bodyFaces.count == bodyCandidates.count
        else {
            statusMessage =
                candidates.isEmpty ? "이 위치에서 보정할 부위를 찾지 못했어요. 아래 목록을 이용해 주세요." : "사람이 겹쳐 있어요. 목록에서 보정할 사람을 먼저 골라주세요."
            return
        }
        let face = faces[index]
        let tap = CGPoint(x: point.x, y: point.y)
        let padding = face.boundingBox.width * RegionPolicy.featurePadding
        let eyes = [FaceLandmark.leftEye, .rightEye].compactMap {
            face.bounds(of: $0)?.cgRect.insetBy(dx: -padding, dy: -padding)
        }
        let mouth = face.bounds(of: .outerLips)?.cgRect.insetBy(dx: -padding, dy: -padding)
        let chin = face.landmarks[.faceContour]?.min(by: { $0.y < $1.y })
        let destination: RetouchDestination
        if eyes.contains(where: { $0.contains(tap) }) {
            destination = .feature(.eyeBrighten)
        } else if mouth?.contains(tap) == true {
            destination = .feature(.lipVitality)
        } else if let chin, point.y < chin.y, chin.y - point.y <= face.boundingBox.height * RegionPolicy.chinReach,
            abs(point.x - chin.x) <= face.boundingBox.width * RegionPolicy.chinWidth
        {
            destination = .doubleChin
        } else if face.boundingBox.cgRect.contains(tap) {
            destination = .skin
        } else {
            statusMessage = "턱 윤곽을 정확히 찾지 못했어요. 목록에서 부위를 골라주세요."
            return
        }
        setBeautyTarget(.face(index))
        openRetouchDestination(destination)
    }

    /// 목록의 사람 선택은 UI 대상만 바꾸고, 기다리던 부유방 항목으로 이동한다.
    func chooseRetouchPerson(_ index: Int) {
        guard faces.indices.contains(index) else { return }
        setBeautyTarget(.face(index))
        if let destination = focusedRetouchDestination { openRetouchDestination(destination) }
    }

    private func selectBodyRetouchRegion(at tap: NormalizedPoint, candidates: [Int: BodyGeometry]) {
        guard selectedInfo?.bodyAnalysisFailure == nil, candidates.count == 1,
            let (bodyIndex, body) = candidates.first,
            let faceIndex = bodyFaceMatches[bodyIndex], faces.indices.contains(faceIndex)
        else {
            statusMessage = "이 몸의 사람을 확실히 연결할 수 없어요. 목록에서 사람과 부위를 골라주세요."
            return
        }
        let size = selectedInfo?.pixelSize ?? .zero
        func distance(_ a: NormalizedPoint, _ b: NormalizedPoint) -> Double {
            hypot((a.x - b.x) * size.width, (a.y - b.y) * size.height)
        }
        let confidence = RenderTuning().bodyJointMinConfidence
        guard let left = body.point(.leftShoulder, minimumConfidence: confidence),
            let right = body.point(.rightShoulder, minimumConfidence: confidence)
        else { return }
        let reach = distance(left, right) * RegionPolicy.bodyReach
        let sidePoints = selectedInfo?.bodyOutlines[bodyIndex]?.sideChestPoints ?? []
        let destination: RetouchDestination
        if sidePoints.contains(where: { distance(tap, $0) <= reach }) {
            destination = .sideChest
        } else {
            // 관절 점뿐 아니라 팔·허벅지 한가운데도 같은 신뢰 관절 선분으로 찾는다.
            let segments: [(BodyJoint, BodyJoint, BodyShapeKey)] = [
                (.leftShoulder, .leftElbow, .arms), (.leftElbow, .leftWrist, .arms),
                (.rightShoulder, .rightElbow, .arms), (.rightElbow, .rightWrist, .arms),
                (.leftHip, .leftKnee, .thighs), (.rightHip, .rightKnee, .thighs),
                (.leftHip, .rightHip, .waist), (.leftShoulder, .rightShoulder, .shoulders),
            ]
            func segmentDistance(_ a: NormalizedPoint, _ b: NormalizedPoint) -> Double {
                let vx = (b.x - a.x) * size.width
                let vy = (b.y - a.y) * size.height
                let denominator = vx * vx + vy * vy
                guard denominator > 0 else { return distance(tap, a) }
                let projection = ((tap.x - a.x) * size.width * vx + (tap.y - a.y) * size.height * vy) / denominator
                let fraction = min(1, max(0, projection))
                return distance(tap, NormalizedPoint(x: a.x + fraction * (b.x - a.x), y: a.y + fraction * (b.y - a.y)))
            }
            let hits = segments.compactMap { first, second, key -> (Double, BodyShapeKey)? in
                guard let a = body.point(first, minimumConfidence: confidence),
                    let b = body.point(second, minimumConfidence: confidence)
                else { return nil }
                let value = segmentDistance(a, b)
                return value <= reach ? (value, key) : nil
            }.sorted { $0.0 < $1.0 }
            guard let hit = hits.first else {
                statusMessage = "이 위치의 부위를 정확히 나눌 수 없어요. 목록에서 허리·팔·부유방 등 원하는 항목을 골라주세요."
                return
            }
            destination = .bodyShape(hit.1)
        }
        setBeautyTarget(.face(faceIndex))
        openRetouchDestination(destination)
    }

    private enum RegionPolicy {
        static let bodyReach = 0.22
        static let featurePadding = 0.04
        static let chinReach = 0.22
        static let chinWidth = 0.3
    }
}
