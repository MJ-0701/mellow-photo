import Foundation

/// 모듈이 던지는 유일한 오류 타입. 사용자 문구는 앱 타깃이 매핑한다.
public enum MellowError: Error, Equatable, Sendable {
    case cannotOpenPhoto(filename: String)
    case unsupportedOrCorruptPhoto
    case cannotCreatePreview
    case invalidImageSize
    case invalidRecipeValues
    case warpUnavailable
    case renderFailed
    case cannotWriteToFolder
    case exportVerificationFailed
    case fileAlreadyExists
    case exportFailed(reason: String)
    case faceAnalysisUnavailable(reason: String)
    case personAnalysisUnavailable(reason: String)
    case sessionUnreadable
    case sessionWriteFailed(reason: String)
    case photoLibraryAccessDenied
}
