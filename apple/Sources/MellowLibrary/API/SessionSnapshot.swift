import MellowShared

public struct SessionSnapshot: Equatable, Sendable {
    public var photos: [PhotoEntry]
    public var selectedPhotoID: PhotoID?
    public var presets: [Preset]

    public init(photos: [PhotoEntry] = [], selectedPhotoID: PhotoID? = nil, presets: [Preset] = []) {
        self.photos = photos
        self.selectedPhotoID = selectedPhotoID
        self.presets = presets
    }
}
