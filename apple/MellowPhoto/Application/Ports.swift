import Foundation
import PhotosUI
import SwiftUI

/// 사용자가 고른 사진을 앱 임시 폴더로 옮긴 결과.
struct StagedPhoto: Sendable {
    let url: URL
    /// 원본 파일 이름 줄기. 사진 앱에서 고르면 알 수 없어 nil.
    let displayName: String?
}

/// 플랫폼별 가져오기 구현. 선택 항목을 임시 파일로 바꾸는 일만 한다.
protocol PhotoImporter: Sendable {
    func stage(_ items: [PhotosPickerItem]) async -> [Result<StagedPhoto, Error>]
    func stage(fileURLs: [URL]) async -> [Result<StagedPhoto, Error>]
}
