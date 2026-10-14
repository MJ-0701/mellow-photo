import MellowEditing
import MellowShared

public struct PhotoEntry: Identifiable, Equatable, Sendable {
    public let id: PhotoID
    /// 작업 사본 파일 이름. 디렉터리는 WorkingCopyStore가 안다.
    public let filename: String
    public var displayName: String
    public var document: EditDocument

    public init(id: PhotoID, filename: String, displayName: String, document: EditDocument = EditDocument()) {
        self.id = id
        self.filename = filename
        self.displayName = displayName
        self.document = document
    }
}
