import PhotosUI
import SwiftUI

struct PhotoPickerButton: View {
    @Environment(AppModel.self) private var model
    @State private var items: [PhotosPickerItem] = []
    @State private var showingPhotos = false
    @State private var showingFiles = false
    var prominent = false

    var body: some View {
        Menu {
            // 메뉴 항목 안에 PhotosPicker를 두면 iOS에서 메뉴가 닫히며 피커도 사라진다.
            // fileImporter처럼 플래그만 켜고 표시는 메뉴 바깥 modifier가 맡는다.
            Button {
                showingPhotos = true
            } label: {
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
        .photosPicker(
            isPresented: $showingPhotos, selection: $items,
            maxSelectionCount: max(1, model.session.remainingCapacity), matching: .images,
            preferredItemEncoding: .current
        )
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
