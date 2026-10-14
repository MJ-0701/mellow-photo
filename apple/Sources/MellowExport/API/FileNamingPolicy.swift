import Foundation

public enum FileNamingPolicy: Sendable {
    public static let suffix = "_mellow"

    /// "<stem>_mellow.<ext>", 충돌하면 "_2", "_3"… 을 붙인다.
    public static func availableURL(in folder: URL, stem: String, fileExtension: String, exists: (URL) -> Bool) -> URL {
        let base = stem + suffix
        var candidate = folder.appendingPathComponent(base).appendingPathExtension(fileExtension)
        var counter = 2
        while exists(candidate) {
            candidate = folder.appendingPathComponent("\(base)_\(counter)").appendingPathExtension(fileExtension)
            counter += 1
        }
        return candidate
    }
}
