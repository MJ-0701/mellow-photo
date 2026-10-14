import SwiftUI

struct LibrarySidebar: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("내 사진").font(.system(size: 13, weight: .semibold))
                Spacer()
                Text("\(model.session.photos.count)").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            }
            .padding(18)
            ScrollView {
                LazyVStack(spacing: 15) {
                    ForEach(model.session.photos) { entry in
                        VStack(alignment: .leading, spacing: 7) {
                            ThumbnailCell(entry: entry, size: Theme.thumbnailRegular)
                            Text(entry.displayName).font(.system(size: 10)).lineLimit(1).foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(.horizontal, 16).padding(.bottom, 16)
            }
            Spacer(minLength: 0)
            Text("HEIC · JPEG · PNG\n원본은 늘 그대로")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .lineSpacing(5)
                .padding(18)
        }
        .frame(width: Theme.sidebarWidth)
        .disabled(model.isBusy)
    }
}
