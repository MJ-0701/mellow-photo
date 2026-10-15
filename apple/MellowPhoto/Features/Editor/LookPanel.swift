import MellowShared
import SwiftUI

/// 필터 칩(썸네일은 처음 열 때 만든다)과 강도 슬라이더.
struct LookPanel: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let selection = model.currentRecipe.look
        let photoID = model.session.selectedPhotoID
        let thumbnails = photoID.flatMap { model.lookThumbnails[$0] } ?? [:]
        ScrollView(.horizontal) {
            HStack(spacing: 10) {
                chip(
                    id: nil, name: "원본", image: photoID.flatMap { model.thumbnails[$0] },
                    selected: selection.id == nil)
                ForEach(model.lookCatalog.all) { look in
                    chip(id: look.id, name: look.name, image: thumbnails[look.id], selected: selection.id == look.id)
                }
            }
            .padding(.vertical, 4)
        }
        .scrollIndicators(.hidden)
        .onAppear { model.loadLookThumbnails() }
        if selection.id != nil {
            AdjustmentSlider(title: "강도", value: selection.intensity, range: 0...1) { .lookIntensity($0) }
        }
        if model.lookCatalog.all.isEmpty {
            Text(UserMessage.lookCatalogUnavailable).font(.caption).foregroundStyle(.secondary)
        }
    }

    private func chip(id: String?, name: String, image: CGImage?, selected: Bool) -> some View {
        Button {
            model.edit(.lookID(selected ? nil : id))
        } label: {
            VStack(spacing: 4) {
                ZStack {
                    Rectangle().fill(.secondary.opacity(0.2))
                    if let image {
                        Image(cgImage: image).resizable().scaledToFill()
                    } else {
                        ProgressView().controlSize(.small)
                    }
                }
                .frame(width: Theme.lookChipSize.width, height: Theme.lookChipSize.width)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(selected ? Theme.accent : .clear, lineWidth: 2))
                Text(name).font(.caption2).foregroundStyle(selected ? Theme.accent : .secondary)
            }
            .frame(width: Theme.lookChipSize.width, height: Theme.lookChipSize.height)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(name)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
