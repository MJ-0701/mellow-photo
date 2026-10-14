public protocol SessionStore: Sendable {
    /// 파일이 없으면 nil. 읽을 수 없으면 MellowError.sessionUnreadable.
    func load() throws -> SessionSnapshot?
    func save(_ snapshot: SessionSnapshot) throws
}
