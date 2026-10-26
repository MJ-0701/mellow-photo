import Foundation

extension UserMessage {
    static let toolQuick = "빠른 보정"
    static let quickAutomatic = "사진에 맞게 자동"
    static let quickPortrait = "인물 원터치"
    static let quickBackground = "배경 흐림"
    static let quickBrighten = "어두운 사진 밝히기"
    static let quickNight = "밤 색감"
    static let quickBatch = "사진마다 자동 보정"
    static let quickCopySettings = "이 설정 복사"
    static let quickCancel = "나머지 취소"
    static let quickCancelling = "진행 중인 사진 분석이 끝나면 멈춰요. 완료한 사진은 유지해요."
    static let quickAutomaticDetail = "원본을 분석해 밝기·색감·선명도 등 기존 조정값을 교체해요. 얼굴이 있으면 인물 원터치도 적용해요."
    static let quickPortraitDetail = "이 사진의 모든 얼굴에 피부·눈·입·메이크업과 몸 피부 밝기를 묶어 적용해요. 얼굴형·체형은 유지해요."
    static let quickBackgroundDetail = "사람은 선명하게 두고 배경을 흐려요. 배경 흐림 강도를 35%로 교체해요."
    static let quickBrightenDetail = "원본 분석의 밝기 추천으로 노출만 올려요. 이미 더 밝게 조정했다면 유지해요."
    static let quickNightDetail = "밤 필터와 강도 60%로 현재 필터를 교체해요. 색감 표현이며 낮 사진의 조명을 밤으로 바꾸지 않아요."
    static let quickBatchDetail = "선택한 사진을 포함해 사진마다 원본을 따로 분석해요. 밝기·색감·선명도 등 기존 조정값은 교체되며, 자르기·얼굴형·체형·수동 브러시는 유지해요."
    static let quickBatchNeedsPhotos = "사진이 두 장 이상일 때 사용할 수 있어요."
    static let quickNoFace = "얼굴을 찾지 못해 인물 원터치를 적용할 수 없어요."
    static let quickFaceUnavailable = "얼굴 분석을 사용할 수 없어 인물 원터치를 적용하지 않아요."
    static let quickPersonUnavailable = "사람을 분석하지 못해 배경을 나눌 수 없어요."
    static let quickNoPerson = "사람을 찾지 못해 배경을 나눌 수 없어요."
    static let quickNightUnavailable = "밤 필터를 불러오지 못했어요."
    static let quickBrightenUnchanged = "이미 밝게 조정했거나 더 밝힐 필요가 없어요."
    static let quickNoChange = "이미 같은 값이어서 변경하지 않았어요."
    static let quickChangedWhileAnalyzing = "분석 중 편집이 바뀌어 기존 작업을 유지했어요."

    static func quickApplied(_ title: String) -> String {
        "\(title)을 적용했어요. 실행 취소로 되돌릴 수 있어요."
    }

    static func quickProcessing(_ index: Int, total: Int) -> String {
        "사진별 보정 중 \(index)/\(total)"
    }

    static func quickSummary(_ report: AppModel.QuickRetouchProgress) -> String {
        let state = report.cancelled ? "취소됨" : "완료"
        return
            "\(state): 보정 \(report.changed)장 · 같은 값 \(report.unchanged)장 · 실패 \(report.failed)장 · 기존 편집 유지 \(report.skipped)장 · 미처리 \(report.total - report.processed)장"
    }
}
