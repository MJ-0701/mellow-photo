import MellowEditing
import MellowShared

enum CropAspect: CaseIterable, Identifiable {
    case original
    case square
    case fourFive
    case threeFour
    case nineSixteen

    var id: Self { self }

    /// 가로/세로. original은 nil(비율 제한 없음, 자르기를 없앤다).
    var ratio: Double? {
        switch self {
        case .original: return nil
        case .square: return 1
        case .fourFive: return 4.0 / 5.0
        case .threeFour: return 3.0 / 4.0
        case .nineSixteen: return 9.0 / 16.0
        }
    }
}

extension AppModel {
    /// 비율에 맞는 가장 큰 중앙 사각형을 자르기로 넣는다. 원본 비율이면 자르기를 없앤다.
    func setCropAspect(_ aspect: CropAspect) {
        cropAspect = aspect
        guard let transform = outputTransform else { return }
        guard let ratio = aspect.ratio else {
            edit(.crop(nil))
            return
        }
        edit(.crop(Self.centeredCrop(ratio: ratio, imageAspect: transform.turnedAspect)))
    }

    /// 정규화 공간에서 픽셀 가로/세로 = ratio가 되는 가장 큰 중앙 사각형.
    static func centeredCrop(ratio: Double, imageAspect: Double) -> NormalizedRect {
        let width = min(1, ratio / imageAspect)
        let height = min(1, imageAspect / ratio)
        return NormalizedRect(x: (1 - width) / 2, y: (1 - height) / 2, width: width, height: height)
    }

    func beginCropDrag() {
        beginSliderEdit()
    }

    func endCropDrag() {
        endSliderEdit()
    }

    /// 기하만 기본값으로. 실행 취소 한 단계. 이미 기본값이면 빈 단계를 만들지 않는다.
    func resetGeometry() {
        cropAspect = nil
        guard isReady, !isBusy, !currentRecipe.geometry.isIdentity else { return }
        beginSliderEdit()
        edit(.crop(nil))
        edit(.straightenDegrees(0))
        edit(.quarterTurns(0))
        edit(.flipHorizontal(false))
        endSliderEdit()
    }
}
