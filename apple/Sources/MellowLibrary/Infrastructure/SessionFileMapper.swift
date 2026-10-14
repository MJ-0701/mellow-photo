import MellowEditing
import MellowShared

enum SessionFileMapper {
    static func snapshot(from file: SessionFile) -> SessionSnapshot {
        let photos = file.photos.map { photo in
            PhotoEntry(
                id: PhotoID(rawValue: photo.id),
                filename: photo.filename,
                displayName: photo.displayName,
                document: EditDocument(recipe: photo.recipe, undoStack: photo.undo, redoStack: photo.redo))
        }
        let selected = file.selectedPhotoID.map(PhotoID.init(rawValue:))
        let validSelection = photos.contains { $0.id == selected } ? selected : photos.first?.id
        return SessionSnapshot(photos: photos, selectedPhotoID: validSelection, presets: file.presets)
    }

    static func file(from snapshot: SessionSnapshot) -> SessionFile {
        let photos = snapshot.photos.map { entry in
            SessionFile.Photo(
                id: entry.id.rawValue,
                filename: entry.filename,
                displayName: entry.displayName,
                recipe: entry.document.recipe,
                undo: entry.document.undoStack,
                redo: entry.document.redoStack)
        }
        return SessionFile(
            photos: photos, selectedPhotoID: snapshot.selectedPhotoID?.rawValue, presets: snapshot.presets)
    }
}
