import Foundation
import MellowRendering
import MellowShared

/// 모든 한국어 사용자 문구. 모듈은 문구를 모른다.
enum UserMessage {
    static let welcomeStatus = "사진을 골라 시작해보세요."
    static let geometryLocked = "수동 보정 위치를 유지하려고 얼굴 조정을 잠갔어요. 실행 취소 또는 초기화하면 다시 조정할 수 있어요."
    static let chooseCloneSource = "① 깨끗한 피부를 톡 눌러 샘플을 골라주세요."
    static let chooseCloneTarget = "② 지우고 싶은 작은 잡티를 톡 눌러주세요."
    static let appliedToAll = "전체 사진에 슬라이더 설정을 적용했어요."
    static let sessionUnreadable = "작업 기록을 읽지 못해 복구용 사본을 보관했습니다. 기존 작업 사진도 보존됩니다. 사진을 다시 골라 편집할 수 있어요."
    static let somePhotosUnreadable = "일부 작업 사진을 열지 못했습니다. 해당 사진을 다시 가져오세요."
    static let selectionUnreadable = "이 작업 사진을 열 수 없습니다. 다시 시도하거나 편집에서 뺀 뒤 사진을 다시 골라주세요."
    /// 사진 앱에서 고른 항목은 파일 이름을 알 수 없어 오류 문구에 이 이름을 쓴다.
    static let photoLibraryItemName = "사진 앱 항목"
    /// 사진 앱이 새 항목을 만들지 못했을 때 저장 실패 사유.
    static let photoLibraryCouldNotCreateAsset = "사진 앱에 새 사진을 만들지 못했습니다."
    /// PhotoPipeline.unpreparedReason을 사용자에게 보여줄 때의 문구.
    static let photoNotPrepared = "사진이 아직 준비되지 않았습니다"
    static let toolLook = "필터"
    static let toolCrop = "자르기"
    static let toolAdjust = "조정"
    static let toolAuto = "자동"
    static let toolRetouch = "잡티"
    static let toolWarp = "변형"
    static let toolBeauty = "뷰티"
    static let beautyTabSkin = "피부"
    static let beautyTabFace = "얼굴"
    static let beautyTabsLabel = "뷰티 항목"
    static let skinSmoothing = "피부 보정"
    static let autoBlemish = "자동 잡티"
    static let faceWidth = "얼굴 폭"
    static let skinHint = "피부 보정은 모공 질감을 남기고 얼룩만 고르게 합니다. 자동 잡티는 사진을 준비할 때 찾은 작은 잡티를 지웁니다."
    static let faceHint = "얼굴 형태를 먼저 조정한 뒤 잡티를 보정해 주세요."
    static let faceAnalysisUnavailableTitle = "자동 얼굴 분석을 사용할 수 없어요"
    static let noFaceDetected = "감지된 얼굴이 없어요"
    static let noFaceHint = "정면에 가까운 사진을 선택하거나 잡티·변형 도구를 직접 사용해 주세요."
    static let allFaces = "모든 얼굴"
    static let autoEnhanced = "자동 보정을 적용했어요. 실행 취소로 되돌릴 수 있어요."
    static let lookCatalogUnavailable = "필터 목록을 읽지 못해 필터를 쓸 수 없습니다."

    static func workingFolderUnavailable(_ reason: String) -> String {
        "작업 폴더를 열지 못했습니다: \(reason)"
    }

    static func photosStatus(count: Int) -> String {
        "\(count)장 · 편집 기록은 이 기기에 저장됩니다."
    }

    static func importing(_ index: Int, of total: Int) -> String {
        "사진 가져오는 중 \(index) / \(total)"
    }

    static func exporting(_ index: Int, of total: Int) -> String {
        "저장 중 \(index) / \(total)"
    }

    static func exported(saved: Int, cancelled: Bool) -> String {
        "\(saved)장 저장 완료" + (cancelled ? " · 나머지 취소" : "") + " · 원본은 그대로예요."
    }

    /// 파일 이름을 알 수 없는 사진의 표시 이름. 번호는 1부터.
    static func defaultPhotoName(number: Int) -> String {
        "사진 \(number)"
    }

    /// 가져오기 실패·경고 목록의 한 줄.
    static func photoLine(ordinal: Int, _ message: String) -> String {
        "사진 \(ordinal): \(message)"
    }

    static func importFailures(count: Int) -> String {
        "\(count)장을 가져오지 못했습니다."
    }

    static func skippedForCapacity(_ count: Int) -> String {
        "한 번에 편집할 수 있는 사진 수를 넘어 \(count)장은 건너뛰었습니다."
    }

    static func removeFailed(_ reason: String) -> String {
        "사진을 빼지 못했습니다. 작업 사진과 보정 기록은 그대로 유지됩니다: \(reason)"
    }

    static func workingCopyCleanupFailed(_ reason: String) -> String {
        "편집 목록에서 뺐지만 작업 사본을 정리하지 못했습니다: \(reason)"
    }

    static func exportFailures(count: Int) -> String {
        "\(count)장을 저장하지 못했습니다."
    }

    static func faceCount(_ count: Int) -> String {
        "얼굴 \(count)명"
    }

    static func faceOrdinal(_ number: Int) -> String {
        "왼쪽부터 \(number)번째"
    }

    static func text(for error: Error) -> String {
        guard let error = error as? MellowError else { return error.localizedDescription }
        switch error {
        case .cannotOpenPhoto(let filename): return "사진 파일을 열 수 없습니다: \(filename)"
        case .unsupportedOrCorruptPhoto: return "지원하지 않거나 손상된 사진입니다."
        case .cannotCreatePreview: return "사진 미리보기를 만들 수 없습니다."
        case .invalidImageSize: return "사진 크기가 올바르지 않습니다."
        case .invalidRecipeValues: return "보정 수치가 올바르지 않습니다."
        case .warpUnavailable: return "얼굴·체형 보정 기능을 초기화하지 못했습니다."
        case .renderFailed: return "사진을 렌더링할 수 없습니다."
        case .cannotWriteToFolder: return "저장할 폴더를 열 수 없습니다."
        case .exportVerificationFailed: return "저장된 사진을 검증하지 못했습니다."
        case .fileAlreadyExists: return "같은 이름의 파일이 이미 있습니다. 다른 이름을 선택하세요."
        case .exportFailed(let reason): return "사진을 저장하지 못했습니다: \(reason)"
        case .faceAnalysisUnavailable(let reason):
            let detail = reason == PhotoPipeline.unpreparedReason ? photoNotPrepared : reason
            return "얼굴 분석을 사용할 수 없습니다. 색감·수동 보정은 사용할 수 있어요. (\(detail))"
        case .sessionUnreadable: return sessionUnreadable
        case .sessionWriteFailed(let reason): return "편집 기록 저장 실패: \(reason)"
        case .photoLibraryAccessDenied:
            return "사진 저장 권한이 꺼져 있습니다. 설정 → 앱 → Mellow Photo → 사진에서 사진 추가를 허용해 주세요."
        }
    }
}
