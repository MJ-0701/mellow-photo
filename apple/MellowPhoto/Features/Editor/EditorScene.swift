import SwiftUI

/// compact(iPhone 세로)는 세로 스택, regular(iPad·Mac)는 3단.
struct EditorScene: View {
    @Environment(AppModel.self) private var model
    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var zoom = 1.0
    @State private var presetSheet = false
    @State private var infoSheet = false
    @State private var resetConfirmation = false
    @State private var removeConfirmation = false

    var body: some View {
        @Bindable var model = model
        NavigationStack {
            Group {
                if model.session.photos.isEmpty {
                    WelcomeView()
                } else if sizeClass == .compact {
                    compactLayout
                } else {
                    regularLayout
                }
            }
            .navigationTitle("mellow")
            #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .navigation) {
                    HStack {
                        Button {
                            infoSheet = true
                        } label: {
                            Image(systemName: "info.circle")
                        }.accessibilityLabel("도움말과 개인정보")
                        PhotoPickerButton().labelStyle(.iconOnly)
                    }
                }
                ToolbarItem(placement: .primaryAction) {
                    ExportMenu(removeConfirmation: $removeConfirmation)
                }
            }
        }
        .tint(Theme.accent)
        .alert(
            "확인해주세요",
            isPresented: Binding(get: { model.presentedError != nil }, set: { if !$0 { model.presentedError = nil } })
        ) {
            Button("확인") { model.presentedError = nil }
        } message: {
            Text(model.presentedError?.message ?? "")
        }
        .confirmationDialog("이 사진을 처음 상태로 돌릴까요?", isPresented: $resetConfirmation, titleVisibility: .visible) {
            Button("보정 초기화", role: .destructive) { model.reset() }
        } message: {
            Text("원본은 바뀌지 않습니다. 실행 취소로 복구할 수 있어요.")
        }
        .confirmationDialog("편집에서 사진을 뺄까요?", isPresented: $removeConfirmation, titleVisibility: .visible) {
            Button("편집에서 빼기", role: .destructive) { model.removeSelectedPhoto() }
        } message: {
            Text("이 앱의 작업 사본과 보정 기록이 삭제됩니다. 원본은 남아 있습니다.")
        }
        .sheet(isPresented: $infoSheet) { InfoSheet() }
        .sheet(isPresented: $presetSheet) { PresetSheet() }
        .onDrop(of: [.fileURL], isTargeted: nil) { providers in
            Task {
                var urls: [URL] = []
                for provider in providers {
                    if let url = try? await provider.loadItem(forTypeIdentifier: "public.file-url") as? URL {
                        urls.append(url)
                    } else if let data = try? await provider.loadItem(forTypeIdentifier: "public.file-url") as? Data,
                        let url = URL(dataRepresentation: data, relativeTo: nil)
                    {
                        urls.append(url)
                    }
                }
                await model.importFromFiles(urls)
            }
            return true
        }
    }

    private var compactLayout: some View {
        VStack(spacing: 0) {
            PhotoStripView()
            PhotoCanvasView(zoom: $zoom, removeConfirmation: $removeConfirmation)
                .frame(maxHeight: .infinity).frame(minHeight: 130)
            ActionBar(zoom: $zoom)
            compactControls
            StatusBar()
        }
    }

    /// 도구 전환은 selectTool을 거쳐야 자르기 화면의 미리보기와 필터 썸네일이 준비된다.
    private var toolSelection: Binding<EditorTool> {
        Binding(get: { model.tool }, set: { model.selectTool($0) })
    }

    private var compactControls: some View {
        VStack(spacing: 12) {
            Picker("보정 도구", selection: toolSelection) {
                ForEach(EditorTool.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            ScrollView {
                VStack(alignment: .leading, spacing: 16) { toolPanel }.padding(.vertical, 5)
            }
            .frame(height: Theme.compactControlsHeight)
            HStack {
                Button("전체 사진에 적용") { model.applyToAll() }.disabled(model.session.photos.count < 2)
                Spacer()
                Button("초기화") { resetConfirmation = true }
            }
            .font(.caption).padding(.bottom, 4)
        }
        .padding(.horizontal).padding(.top, 10)
        .background(Theme.panel)
        .disabled(model.isBusy || !model.isReady)
    }

    private var regularLayout: some View {
        HStack(spacing: 0) {
            LibrarySidebar()
            Divider()
            VStack(spacing: 0) {
                PhotoCanvasView(zoom: $zoom, removeConfirmation: $removeConfirmation)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                ActionBar(zoom: $zoom, showsZoom: true).padding(.vertical, 6)
                StatusBar()
            }
            Divider()
            VStack(spacing: 0) {
                Picker("보정 도구", selection: toolSelection) {
                    ForEach(EditorTool.allCases) { Label($0.title, systemImage: $0.symbol).tag($0) }
                }
                .pickerStyle(.segmented).padding(14)
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) { toolPanel }.padding(20)
                }
                Divider()
                VStack(spacing: 10) {
                    Button {
                        model.applyToAll()
                    } label: {
                        Label("이 설정을 전체 사진에", systemImage: "square.on.square").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered).disabled(model.session.photos.count < 2)
                    Button("이 사진 초기화") { resetConfirmation = true }.font(.caption).buttonStyle(.plain)
                }
                .padding(18)
            }
            .frame(width: Theme.inspectorWidth)
            .background(Theme.panel)
            .disabled(model.isBusy || !model.isReady)
        }
    }

    @ViewBuilder
    private var toolPanel: some View {
        switch model.tool {
        // 필터·자르기 화면은 Task 12에서 붙인다. 그때까지는 조정 패널을 보여준다.
        case .look, .crop, .adjust: ColorPanel(presetSheet: $presetSheet)
        case .portrait: PortraitPanel()
        case .retouch, .warp: BrushPanel()
        }
    }
}
