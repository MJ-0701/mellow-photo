import PhotosUI
import SwiftUI

struct PhotoPickerButton: View {
    @Environment(AppModel.self) private var model
    @State private var items: [PhotosPickerItem] = []
    @State private var showingFiles = false
    var prominent = false

    var body: some View {
        Menu {
            PhotosPicker(
                selection: $items, maxSelectionCount: max(1, model.session.remainingCapacity), matching: .images,
                preferredItemEncoding: .current
            ) {
                Label("사진 앱에서 고르기", systemImage: "photo.on.rectangle")
            }
            Button {
                showingFiles = true
            } label: {
                Label("파일에서 고르기", systemImage: "folder")
            }
        } label: {
            Label("사진 가져오기", systemImage: "plus")
        }
        .keyboardShortcut("o")
        .disabled(model.isBusy || model.session.remainingCapacity == 0)
        .onChange(of: items) { _, newItems in
            guard !newItems.isEmpty else { return }
            let selected = newItems
            items = []
            Task { await model.importFromPicker(selected) }
        }
        .fileImporter(isPresented: $showingFiles, allowedContentTypes: [.image], allowsMultipleSelection: true) {
            result in
            if case .success(let urls) = result {
                Task { await model.importFromFiles(urls) }
            }
        }
    }
}
