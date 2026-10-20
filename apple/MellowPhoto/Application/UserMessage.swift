import Foundation
import MellowEditing
import MellowRendering
import MellowShared

/// 모든 한국어 사용자 문구. 모듈은 문구를 모른다.
enum UserMessage {
    static let welcomeStatus = "사진을 골라 시작해보세요."
    static let geometryLocked = "수동 보정 위치를 유지하려고 얼굴형·체형 조정을 잠갔어요. 실행 취소 또는 초기화하면 다시 조정할 수 있어요."
    static let chooseCloneSource = "① 깨끗한 피부를 톡 눌러 샘플을 골라주세요."
    static let chooseCloneTarget = "② 지우고 싶은 작은 잡티를 톡 눌러주세요."
    static let appliedToAll = "전체 사진에 슬라이더 설정을 적용했어요."
    static let syncMenuLabel = "동기화 항목"
    static let splitCompare = "분할"
    static let splitCompareDone = "분할 끝"
    static let compareDividerLabel = "원본과 보정본의 경계"
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
    static let toolBackground = "배경"
    static let backgroundBlur = "배경 흐림"
    static let backgroundHint = "사람은 그대로 두고 뒤 배경만 흐려요."
    static let noPersonDetected = "사진에서 사람을 찾지 못했어요"
    static let noPersonHint = "배경 흐림은 사람이 보이는 사진에서 동작해요."
    static let personAnalysisUnavailableTitle = "인물 영역 분석을 사용할 수 없어요"
    static let toolBody = "체형"
    static let bodyHint = "다리 길게는 왼쪽 끝, 나머지는 가운데가 원래 모양이에요(왼쪽은 가늘게·좁게, 오른쪽은 넓게·길게). 다리 길게는 골반과 발목이 보여야 바뀌어요."
    static let noBodyDetected = "몸의 관절을 찾지 못했어요"
    static let noBodyHint = "전신이 보이는 사진에서 동작합니다."
    static let bodyAnalysisUnavailableTitle = "체형 분석을 사용할 수 없어요"
    static let toolMakeup = "메이크업"
    static let makeupNoLook = "없음"
    static let makeupPartsLabel = "메이크업 부위"
    static let makeupIntensity = "강도"
    static let makeupHint = "룩을 고른 뒤 부위마다 색과 강도를 바꿀 수 있어요. 부위를 바꾸면 룩 선택은 풀려요."
    static let makeupCatalogUnavailable = "메이크업 목록을 읽지 못해 룩과 색을 쓸 수 없습니다."
    static let beautyTabSkin = "피부"
    static let beautyTabFace = "얼굴"
    static let beautyTabFeatures = "눈·입"
    static let beautyTabSkinTone = "피부톤"
    static let bodySkinHint =
        "얼굴·목·팔처럼 보이는 피부 전체에 적용돼요. 기준 피부색은 가장 큰 얼굴의 볼에서 읽고, 옷과 배경은 그대로 둬요. 피부 톤은 가운데가 원래 색이에요."
    static let beautyTabsLabel = "뷰티 항목"
    static let skinSmoothing = "피부 보정"
    static let autoBlemish = "자동 잡티"
    static let skinHint = "피부 보정은 모공 질감을 남기고 얼룩만 고르게 합니다. 자동 잡티는 사진을 준비할 때 찾은 작은 잡티를 지웁니다."
    static let skinRefinementHint =
        "다크서클·팔자주름·마리오네트 주름·미간 주름은 특징점으로 어림한 띠 안에서 어두운 만큼만 밝힙니다. 붉은기는 왼쪽이 맑게, 오른쪽이 혈색이에요."
    static let effectsHint = "그레인과 글로우는 필터와 선명도 뒤에 사진 전체에 얹어요."
    static let faceHint = "미소는 왼쪽 끝, 나머지는 가운데가 원래 모양이에요. 얼굴 형태를 먼저 조정한 뒤 잡티를 보정해 주세요."
    static let featureHint = "치아 미백은 치아가 보이는 사진에서만 바뀌어요. 눈·입 보정은 얼굴 특징점을 찾은 얼굴에 적용돼요."
    static let faceAnalysisUnavailableTitle = "자동 얼굴 분석을 사용할 수 없어요"
    static let noFaceDetected = "감지된 얼굴이 없어요"
    static let noFaceHint = "정면에 가까운 사진을 선택하거나 잡티·변형 도구를 직접 사용해 주세요."
    static let noLandmarksHint =
        "얼굴 특징점을 찾지 못해 얼굴형·눈·입·메이크업은 바뀌지 않아요. 피부 보정·얼룩 고르기·붉은기·번들거림과 잡티·변형 도구는 쓸 수 있고, 주름 밝히기 4종은 특징점이 있어야 바뀌어요."
    static let beautyTargetLabel = "대상"
    static let beautyTargetAll = "전체"
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

    /// 성별 그룹 대상 이름.
    static func beautyTargetGender(_ gender: Gender) -> String {
        switch gender {
        case .male: return "남성 그룹"
        case .female: return "여성 그룹"
        }
    }

    /// 찾은 얼굴 대상 이름.
    /// 왼쪽부터 센 번호다.
    static func beautyTargetFace(_ number: Int) -> String {
        "사람 \(number)"
    }

    /// 뷰티 › 얼굴 탭 슬라이더 이름. 화면 순서는 FaceShapeKey.allCases.
    static func faceShapeTitle(_ key: FaceShapeKey) -> String {
        switch key {
        case .width: return "얼굴 폭"
        case .jaw: return "턱선"
        case .cheekbone: return "광대"
        case .eyeSize: return "눈 크기"
        case .eyeDistance: return "눈 간격"
        case .noseWidth: return "코 폭"
        case .mouthSize: return "입 크기"
        case .smile: return "미소"
        case .forehead: return "이마"
        case .chinLength: return "턱 길이"
        }
    }

    /// 뷰티 › 눈·입 탭 슬라이더 이름. 화면 순서는 FeatureKey.allCases.
    static func featureTitle(_ key: FeatureKey) -> String {
        switch key {
        case .eyeBrighten: return "눈 또렷하게"
        case .teethWhiten: return "치아 미백"
        case .lipVitality: return "입술 생기"
        }
    }

    /// 뷰티 › 피부톤 탭 맨 위 상태 줄.
    /// 사람 영역과 기준 얼굴 조건을 한 줄로 보인다.
    static func bodySkinStatus(_ status: AppModel.BodySkinStatus) -> String {
        switch status {
        case .ready: return "사람 영역 ✓ · 기준 얼굴 ✓"
        case .fallback: return "사람 영역 없음 → 얼굴 둘레로 대신 적용해요"
        case .noFace: return "기준 얼굴이 없어 피부 밝기·톤·매끄럽게가 적용되지 않아요"
        case .faceAnalysisUnavailable: return faceAnalysisUnavailableTitle
        case .personAnalysisUnavailable: return "인물 영역 분석 실패 → 얼굴 둘레로 대신 적용해요"
        }
    }

    /// 정보 시트 진단 절 제목과 복사 버튼.
    static let diagnosticsTitle = "진단"
    static let copyDiagnostics = "복사"

    /// 진단 줄 앞에 붙는 라벨.
    /// 값과 키 경로는 영어 식별자로 둔다.
    static func diagnosticLabel(_ item: AppModel.DiagnosticItem) -> String {
        switch item {
        case .build: return "앱"
        case .device: return "기기"
        case .photo: return "사진"
        case .preview: return "미리보기"
        case .analysis: return "분석"
        case .failure: return "마지막 오류"
        }
    }

    /// 뷰티 › 피부톤 탭 슬라이더 이름. 화면 순서는 BodySkinKey.allCases.
    static func bodySkinTitle(_ key: BodySkinKey) -> String {
        switch key {
        case .brightness: return "피부 밝기"
        case .tone: return "피부 톤"
        case .smoothing: return "바디 피부 매끄럽게"
        }
    }

    /// 뷰티 › 피부 탭의 정밀 슬라이더 이름. 화면 순서는 SkinRefinementKey.allCases.
    static func skinRefinementTitle(_ key: SkinRefinementKey) -> String {
        switch key {
        case .darkCircles: return "다크서클"
        case .nasolabial: return "팔자주름"
        case .marionette: return "마리오네트 주름"
        case .glabella: return "미간 주름"
        case .toneEvening: return "피부 얼룩 고르기"
        case .redness: return "붉은기"
        case .shine: return "번들거림"
        }
    }

    /// 조정 패널 효과 슬라이더 이름. 화면 순서는 EffectKey.allCases.
    static func effectTitle(_ key: EffectKey) -> String {
        switch key {
        case .grain: return "그레인"
        case .glow: return "글로우"
        }
    }

    /// 캔버스 왼쪽 위 배지.
    static func compareBadge(_ mode: AppModel.CompareMode) -> String {
        switch mode {
        case .off: return "보정본"
        case .full: return "원본"
        case .split: return "원본 | 보정본"
        }
    }

    /// 전부 골랐으면 기존 문구, 아니면 고른 개수를 알린다.
    static func appliedToAll(categoryCount: Int, total: Int) -> String {
        categoryCount == total ? appliedToAll : "전체 사진에 고른 \(categoryCount)개 항목을 적용했어요."
    }

    /// 동기화 메뉴 항목 이름. 화면 순서는 SyncCategory.allCases.
    static func syncCategoryTitle(_ category: SyncCategory) -> String {
        switch category {
        case .color: return "색감·디테일"
        case .effects: return "효과"
        case .skin: return "피부"
        case .faceShape: return "얼굴형"
        case .features: return "눈·입"
        case .makeup: return "메이크업"
        case .background: return "배경"
        case .body: return "체형"
        case .bodySkin: return "피부톤"
        }
    }

    /// 체형 도구 슬라이더 이름. 화면 순서는 BodyShapeKey.allCases. 스펙의 "전체 날씬"은 양방향이라 "몸 전체"로 부른다.
    static func bodyShapeTitle(_ key: BodyShapeKey) -> String {
        switch key {
        case .legLength: return "다리 길게"
        case .waist: return "허리"
        case .overall: return "몸 전체"
        case .arms: return "팔"
        case .thighs: return "허벅지"
        case .shoulders: return "어깨"
        case .neck: return "목"
        }
    }

    /// 메이크업 부위 탭 이름. 화면 순서는 MakeupPart.allCases.
    static func makeupPartTitle(_ part: MakeupPart) -> String {
        switch part {
        case .lip: return "립"
        case .blush: return "블러셔"
        case .eyeshadow: return "아이섀도"
        case .brow: return "눈썹"
        case .contour: return "쉐딩"
        }
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
        case .personAnalysisUnavailable(let reason):
            return "인물 영역을 분석할 수 없어 배경 흐림을 쓸 수 없습니다. 다른 보정은 사용할 수 있어요. (\(reason))"
        case .bodyAnalysisUnavailable(let reason):
            return "몸의 관절을 분석할 수 없어 체형 보정을 쓸 수 없습니다. 다른 보정은 사용할 수 있어요. (\(reason))"
        case .sessionUnreadable: return sessionUnreadable
        case .sessionWriteFailed(let reason): return "편집 기록 저장 실패: \(reason)"
        case .photoLibraryAccessDenied:
            return "사진 저장 권한이 꺼져 있습니다. 설정 → 앱 → Mellow Photo → 사진에서 사진 추가를 허용해 주세요."
        }
    }
}
