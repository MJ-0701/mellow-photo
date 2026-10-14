import MellowLibrary
import SwiftUI

struct ThumbnailCell: View {
    @Environment(AppModel.self) private var model
    let entry: PhotoEntry
    let size: CGSize

    var body: some View {
        Button {
            model.select(entry.id)
        } label: {
            ZStack(alignment: .bottomTrailing) {
                if let image = model.thumbnails[entry.id] {
                    Image(cgImage: image).resizable().scaledToFill()
                } else {
                    Rectangle().fill(.secondary.opacity(0.2)).overlay(Image(systemName: "photo"))
                }
                if entry.document.hasEdits {
                    Image(systemName: "slider.horizontal.3")
                        .font(.caption2)
                        .padding(4)
                        .background(.black.opacity(0.6), in: Circle())
                        .padding(3)
                }
            }
            .frame(width: size.width, height: size.height)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(entry.id == model.session.selectedPhotoID ? Theme.accent : .clear, lineWidth: 2)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(entry.displayName)
        .accessibilityAddTraits(entry.id == model.session.selectedPhotoID ? .isSelected : [])
    }
}
