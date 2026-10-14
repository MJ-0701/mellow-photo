import SwiftUI

struct PhotoStripView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 10) {
                ForEach(model.session.photos) { entry in
                    ThumbnailCell(entry: entry, size: Theme.thumbnailCompact)
                }
            }
            .padding(.horizontal).padding(.vertical, 8)
        }
        .scrollIndicators(.hidden)
        .disabled(model.isBusy)
    }
}
