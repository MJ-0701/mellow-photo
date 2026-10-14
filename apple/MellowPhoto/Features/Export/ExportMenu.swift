import MellowExport
import SwiftUI

struct ExportMenu: View {
    @Environment(AppModel.self) private var model
    @Binding var removeConfirmation: Bool
    @State private var pendingAll = false
    @State private var choosingFolder = false

    var body: some View {
        @Bindable var model = model
        Menu {
            Button("현재 사진 저장", systemImage: "square.and.arrow.down") { start(all: false) }
                .disabled(!model.isReady)
                .keyboardShortcut("s", modifiers: [.command, .shift])
            Button("전체 \(model.session.photos.count)장 저장") { start(all: true) }.disabled(!model.isReady)
            Picker("형식", selection: $model.exportOptions.format) {
                Text("JPEG · 추천").tag(ExportFormat.jpeg)
                Text("PNG").tag(ExportFormat.png)
            }
            Toggle("원본 해상도", isOn: $model.exportOptions.fullResolution)
            Text("기본: 긴 변 최대 \(ExportOptions.defaultMaxDimension)px")
            Divider()
            Button("편집에서 사진 빼기", role: .destructive) { removeConfirmation = true }
        } label: {
            Label("저장", systemImage: "square.and.arrow.down").font(.body.weight(.semibold))
        }
        .disabled(!model.canRemoveSelected)
        #if os(macOS)
            .fileImporter(isPresented: $choosingFolder, allowedContentTypes: [.folder]) { result in
                if case .success(let folder) = result {
                    model.export(all: pendingAll, to: FolderDestination(folder: folder))
                }
            }
        #endif
    }

    private func start(all: Bool) {
        pendingAll = all
        #if os(iOS)
            model.export(all: all, to: PhotoLibraryDestination())
        #else
            choosingFolder = true
        #endif
    }
}
