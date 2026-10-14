import MellowExport
import SwiftUI

#if os(macOS)
    import AppKit
#endif

struct ExportMenu: View {
    @Environment(AppModel.self) private var model
    @Binding var removeConfirmation: Bool
    @State private var pendingAll = false
    @State private var choosingFolder = false
    /// 폴더 저장이 끝나면 Finder로 한 번 열어 보여준다.
    @State private var exportedFolder: URL?

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
                    exportedFolder = folder
                    model.export(all: pendingAll, to: FolderDestination(folder: folder))
                    if !model.isExporting {
                        // 바빠서 시작하지 않았다면 열 폴더도 없다.
                        exportedFolder = nil
                    }
                }
            }
            .onChange(of: model.isExporting) { _, exporting in
                guard !exporting, let folder = exportedFolder else { return }
                exportedFolder = nil
                guard model.lastExportSavedCount > 0 else { return }
                revealInFinder(folder)
            }
        #endif
    }

    #if os(macOS)
        private func revealInFinder(_ folder: URL) {
            let accessed = folder.startAccessingSecurityScopedResource()
            defer {
                if accessed {
                    folder.stopAccessingSecurityScopedResource()
                }
            }
            NSWorkspace.shared.open(folder)
        }
    #endif

    private func start(all: Bool) {
        pendingAll = all
        #if os(iOS)
            model.export(all: all, to: PhotoLibraryDestination())
        #else
            choosingFolder = true
        #endif
    }
}
