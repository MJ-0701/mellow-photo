import SwiftUI
import AppKit
import UniformTypeIdentifiers
import MellowCore

private let accent = Color(red: 0.78, green: 0.88, blue: 0.69)
private let panel = Color(red: 0.11, green: 0.12, blue: 0.12)
private let canvas = Color(red: 0.075, green: 0.083, blue: 0.083)

struct StudioView: View {
    @ObservedObject var store: StudioStore
    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().opacity(0.35)
            HStack(spacing: 0) {
                library.frame(width: 174)
                Divider().opacity(0.3)
                VStack(spacing: 0) {
                    canvasToolbar
                    if store.selected != nil {
                        PhotoCanvas(store: store)
                    } else { welcome }
                    photoFooter
                }.frame(maxWidth: .infinity, maxHeight: .infinity).background(canvas)
                Divider().opacity(0.3)
                inspector.frame(width: 292).background(panel)
            }
            Divider().opacity(0.3)
            statusBar
        }
        .background(panel)
        .tint(accent)
        .onDrop(of: [.fileURL], isTargeted: $store.dropTargeted) { providers in
            let group = DispatchGroup()
            let lock = NSLock()
            var urls: [URL] = []
            for provider in providers {
                group.enter()
                provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { value, _ in
                    var found: URL?
                    if let data = value as? Data { found = URL(dataRepresentation: data, relativeTo: nil) }
                    if let url = value as? URL { found = url }
                    if let found = found { lock.lock(); urls.append(found); lock.unlock() }
                    group.leave()
                }
            }
            group.notify(queue: .main) { store.importPhotos(urls) }
            return true
        }
        .overlay { if store.dropTargeted { RoundedRectangle(cornerRadius: 18).stroke(accent, lineWidth: 3).padding(8).allowsHitTesting(false) } }
        .alert("확인이 필요합니다", isPresented: Binding(get: { store.error != nil }, set: { if !$0 { store.error = nil } })) {
            Button("확인") { store.error = nil }
        } message: { Text(store.error ?? "") }
        .confirmationDialog("이 사진의 보정을 초기화할까요?", isPresented: $store.resetConfirmation) {
            Button("보정 초기화", role: .destructive) { store.reset() }
        } message: { Text("실행 취소로 되돌릴 수 있습니다. 원본 파일은 바뀌지 않습니다.") }
        .sheet(isPresented: $store.presetSheet) {
            VStack(alignment: .leading, spacing: 18) {
                Text("이 분위기를 기억하기").font(.title2.bold())
                Text("색감·피부·얼굴 슬라이더 값을 저장합니다. 잡티 위치와 수동 변형은 포함하지 않습니다.").foregroundStyle(.secondary)
                TextField("프리셋 이름", text: $store.presetName).textFieldStyle(.roundedBorder)
                HStack { Spacer(); Button("취소") { store.presetSheet = false }; Button("저장") { store.savePreset(name: store.presetName); store.presetSheet = false }.buttonStyle(.borderedProminent).disabled(store.presetName.trimmingCharacters(in: .whitespaces).isEmpty) }
            }.padding(28).frame(width: 400)
        }
    }
    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "circle.lefthalf.filled").font(.system(size: 25, weight: .light)).foregroundStyle(accent)
            VStack(alignment: .leading, spacing: 1) {
                Text("mellow").font(.system(size: 24, weight: .semibold, design: .rounded)).tracking(-0.8)
                Text("PHOTO STUDIO").font(.system(size: 8, weight: .medium)).tracking(2.8).foregroundStyle(.secondary)
            }
            Text("조금 더, 나답게.").font(.system(size: 12)).foregroundStyle(.secondary).padding(.leading, 24)
            Spacer()
            Label("사진은 이 Mac 안에", systemImage: "lock.shield").font(.system(size: 11)).foregroundStyle(.secondary)
            Button { store.choosePhotos() } label: { Label("사진 가져오기", systemImage: "plus") }.buttonStyle(.bordered).disabled(store.importing || store.exporting)
            Menu {
                Button("현재 사진 저장…") { store.export(all: false) }
                Button("전체 \(store.photos.count)장 저장…") { store.export(all: true) }
                Divider()
                Picker("저장 형식", selection: $store.exportFormat) {
                    Text("JPEG · 추천").tag(ExportFormat.jpeg)
                    Text("PNG").tag(ExportFormat.png)
                }
            } label: { Label("내보내기", systemImage: "square.and.arrow.up").frame(minWidth: 90) }
                .menuStyle(.borderedButton).fixedSize().tint(accent)
                .disabled(store.selected == nil || store.exporting || store.importing)
        }.padding(.leading, 24).padding(.trailing, 20).padding(.top, 28).padding(.bottom, 18)
    }
    private var library: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack { Text("내 사진").font(.system(size: 13, weight: .semibold)); Spacer(); Text("\(store.photos.count)").font(.caption.monospacedDigit()).foregroundStyle(.secondary) }.padding(18)
            if store.photos.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "photo.stack").font(.system(size: 28, weight: .ultraLight))
                    Text("오늘의 사진을\n여기에 담아주세요.").font(.caption).multilineTextAlignment(.center)
                }.foregroundStyle(.secondary).frame(maxWidth: .infinity).padding(.top, 50)
            }
            ScrollView {
                LazyVStack(spacing: 15) {
                    ForEach(store.photos) { item in
                        Button { store.select(item.id) } label: {
                            VStack(alignment: .leading, spacing: 7) {
                                Image(nsImage: item.original).resizable().scaledToFill().frame(width: 130, height: 152).clipped()
                                    .overlay(alignment: .topTrailing) { if item.recipe != EditRecipe() { Image(systemName: "slider.horizontal.3").font(.caption2).padding(6).background(.black.opacity(0.7), in: Circle()).padding(6) } }
                                    .clipShape(RoundedRectangle(cornerRadius: 7))
                                    .overlay(RoundedRectangle(cornerRadius: 7).stroke(store.selectedID == item.id ? accent : .clear, lineWidth: 2))
                                Text(item.url.lastPathComponent).font(.system(size: 10)).lineLimit(1).foregroundStyle(store.selectedID == item.id ? .primary : .secondary)
                            }.padding(3)
                        }.buttonStyle(.plain).accessibilityLabel("사진 \(item.url.lastPathComponent)")
                    }
                }.padding(.horizontal, 16).padding(.bottom, 16)
            }
            Spacer(minLength: 0)
            Text("HEIC · JPEG · PNG\n원본은 늘 그대로").font(.system(size: 10)).foregroundStyle(.secondary).lineSpacing(5).padding(18)
        }
    }
    private var canvasToolbar: some View {
        HStack(spacing: 8) {
            ForEach(EditorTool.allCases, id: \.self) { tool in
                Button { store.tool = tool } label: {
                    Image(systemName: tool.symbol).font(.system(size: 14)).frame(width: 34, height: 32)
                        .background(store.tool == tool ? Color.white.opacity(0.1) : .clear, in: RoundedRectangle(cornerRadius: 7))
                        .foregroundStyle(store.tool == tool ? accent : .secondary)
                }.buttonStyle(.plain).help(tool.rawValue).accessibilityLabel(tool.rawValue)
            }
            Divider().frame(height: 18).padding(.horizontal, 8)
            Button { store.undo() } label: { Image(systemName: "arrow.uturn.backward") }.disabled(!store.canUndo).help("실행 취소 ⌘Z")
            Button { store.redo() } label: { Image(systemName: "arrow.uturn.forward") }.disabled(!store.canRedo).help("다시 실행 ⇧⌘Z")
            Spacer()
            Button { store.compare.toggle() } label: { Label(store.compare ? "보정본 보기" : "원본 보기", systemImage: "rectangle.lefthalf.inset.filled") }.buttonStyle(.bordered).disabled(store.selected == nil)
        }.buttonStyle(.plain).padding(.horizontal, 20).padding(.vertical, 12)
    }
    private var welcome: some View {
        VStack(spacing: 0) {
            Spacer()
            ZStack {
                RoundedRectangle(cornerRadius: 60).fill(LinearGradient(colors: [accent.opacity(0.2), Color(red: 0.58, green: 0.63, blue: 0.48).opacity(0.04)], startPoint: .topLeading, endPoint: .bottomTrailing)).frame(width: 164, height: 194).rotationEffect(.degrees(-8))
                RoundedRectangle(cornerRadius: 52).stroke(accent.opacity(0.4), lineWidth: 1).frame(width: 164, height: 194).rotationEffect(.degrees(8))
                Image(systemName: "camera.macro").font(.system(size: 63, weight: .ultraLight)).foregroundStyle(accent)
            }.padding(.bottom, 40)
            Text("좋아하는 순간을,\n조금 더 부드럽게.").font(.system(size: 31, weight: .light)).lineSpacing(8).multilineTextAlignment(.center)
            Text("아이폰 사진을 끌어놓고 보정을 시작하세요.").font(.system(size: 13)).foregroundStyle(.secondary).padding(.top, 20)
            Button { store.choosePhotos() } label: { Label("사진 선택하기", systemImage: "plus").padding(.horizontal, 22).padding(.vertical, 10) }.buttonStyle(.borderedProminent).foregroundStyle(.black).clipShape(Capsule()).padding(.top, 28).disabled(store.importing)
            Text("별도 가입 없이 · 사진 업로드 없이").font(.system(size: 10)).foregroundStyle(.secondary).padding(.top, 16)
            Spacer()
            HStack(spacing: 25) { Label("피부 정돈", systemImage: "sparkles"); Label("미세한 조정", systemImage: "slider.horizontal.3"); Label("나만의 색감", systemImage: "circle.lefthalf.filled") }.font(.system(size: 11)).foregroundStyle(.secondary).padding(.bottom, 38)
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    private var photoFooter: some View {
        HStack {
            if let item = store.selected {
                Text("\(Int(item.fullSize.width)) × \(Int(item.fullSize.height))").font(.system(size: 10, design: .monospaced)).foregroundStyle(.secondary)
                Spacer()
                if store.rendering { ProgressView().controlSize(.mini); Text("보정 중").font(.caption2).foregroundStyle(.secondary) }
                Button("−") { store.zoom = max(1, store.zoom - 0.5) }.buttonStyle(.plain)
                Text(store.zoom == 1 ? "화면에 맞춤" : "\(Int(store.zoom * 100))% 확대").font(.caption2).frame(width: 75)
                Button("+") { store.zoom = min(4, store.zoom + 0.5) }.buttonStyle(.plain)
            } else { Text("MELLOW PHOTO  /  01").font(.system(size: 9, design: .monospaced)).tracking(2).foregroundStyle(.tertiary); Spacer() }
        }.padding(.horizontal, 22).frame(height: 38)
    }
    private var inspector: some View {
        VStack(spacing: 0) {
            HStack {
                ForEach(Array(["색감", "인물", "도구"].enumerated()), id: \.offset) { i, title in
                    Button { store.activeTab = i } label: { Text(title).font(.system(size: 12, weight: .medium)).frame(maxWidth: .infinity).padding(.vertical, 13).foregroundStyle(store.activeTab == i ? accent : .secondary).overlay(alignment: .bottom) { if store.activeTab == i { Rectangle().fill(accent).frame(height: 2) } } }.buttonStyle(.plain)
                }
            }.padding(.horizontal, 14)
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    if store.activeTab == 0 { colorPanel }
                    else if store.activeTab == 1 { portraitPanel }
                    else { toolsPanel }
                }.padding(20).disabled(store.selected == nil || store.exporting)
            }
            Divider().opacity(0.3)
            VStack(spacing: 10) {
                Button { store.copyAdjustmentsToAll() } label: { Label("이 설정을 전체 사진에", systemImage: "square.on.square").frame(maxWidth: .infinity) }.buttonStyle(.bordered).disabled(store.photos.count < 2 || store.exporting)
                Button("이 사진 초기화") { store.resetConfirmation = true }.font(.caption).foregroundStyle(.secondary).buttonStyle(.plain).disabled(store.selected == nil || store.exporting)
            }.padding(18)
        }
    }
    private var colorPanel: some View {
        Group {
            VStack(alignment: .leading, spacing: 12) {
                sectionTitle("분위기", subtitle: "사진에 어울리는 시작점")
                HStack(spacing: 8) {
                    presetButton("내추럴", colors: [Color(red: 0.62, green: 0.68, blue: 0.53), .gray]) { var a = Adjustments(); a.exposure = 0.08; a.saturation = 0.97; return a }
                    presetButton("포근한", colors: [.orange.opacity(0.7), .brown]) { var a = Adjustments(); a.warmth = 0.22; a.contrast = 0.96; a.saturation = 0.94; return a }
                    presetButton("클린", colors: [.gray, .blue.opacity(0.5)]) { var a = Adjustments(); a.exposure = 0.18; a.contrast = 1.06; a.saturation = 0.9; return a }
                }
                if !store.presets.isEmpty {
                    Menu("저장한 프리셋 \(store.presets.count)개") { ForEach(store.presets) { p in Button(p.name) { store.applyPreset(p.adjustments) } } }.font(.caption)
                }
                Button { store.presetName = ""; store.presetSheet = true } label: { Label("현재 설정 저장", systemImage: "plus.circle") }.font(.caption).buttonStyle(.plain).foregroundStyle(accent)
            }
            Divider().opacity(0.4)
            VStack(alignment: .leading, spacing: 19) {
                sectionTitle("빛과 색", subtitle: "자연스러운 느낌을 찾아보세요")
                adjustment("노출", key: \.exposure, range: -1.5...1.5, value: String(format: "%+.2f", store.recipe.adjustments.exposure))
                adjustment("대비", key: \.contrast, range: 0.7...1.3, value: "\(Int((store.recipe.adjustments.contrast - 1) * 100))")
                adjustment("채도", key: \.saturation, range: 0...1.6, value: "\(Int(store.recipe.adjustments.saturation * 100))")
                adjustment("따뜻함", key: \.warmth, range: -1...1, value: "\(Int(store.recipe.adjustments.warmth * 100))")
            }
        }
    }
    private var portraitPanel: some View {
        Group {
            sectionTitle("인물 보정", subtitle: "나다운 표정과 피부 결을 남기세요")
            if let photo = store.selected, !photo.faces.isEmpty {
                Label("얼굴 \(photo.faces.count)명 감지", systemImage: "face.smiling").font(.caption).foregroundStyle(accent)
                Picker("보정할 얼굴", selection: Binding<Int>(get: { store.recipe.selectedFace ?? -1 }, set: { store.selectFace($0 == -1 ? nil : $0) })) {
                    Text("모든 얼굴").tag(-1)
                    ForEach(photo.faces.indices, id: \.self) { Text("얼굴 \($0 + 1)").tag($0) }
                }.font(.caption).disabled(!store.recipe.operations.isEmpty)
                adjustment("피부 정돈", key: \.skin, range: 0...1, value: "\(Int(store.recipe.adjustments.skin * 100))")
                adjustment("얼굴 미세 조정", key: \.faceSlim, range: 0...1, value: "\(Int(store.recipe.adjustments.faceSlim * 100))").disabled(!store.recipe.operations.isEmpty)
                if !store.recipe.operations.isEmpty { Text("얼굴 조정은 수동 보정 전에 해주세요. 다시 조정하려면 수동 작업을 실행 취소하거나 사진을 초기화하세요.").font(.caption).foregroundStyle(accent) }
                Text("피부 정돈은 얼굴 영역을 부드럽게 처리합니다. 자동 잡티 탐지는 포함되어 있지 않습니다.").font(.system(size: 11)).foregroundStyle(.secondary).lineSpacing(5)
            } else {
                Label("감지된 얼굴이 없어요", systemImage: "person.crop.rectangle.badge.questionmark").font(.caption).foregroundStyle(.secondary)
                Text("정면에 가까운 사진에서 더 잘 인식됩니다. 잡티 보정과 부분 변형은 도구 탭에서 직접 사용할 수 있습니다.").font(.caption).foregroundStyle(.secondary).lineSpacing(5)
            }
            Divider().opacity(0.3)
            Button { store.activeTab = 2; store.tool = .retouch } label: { Label("작은 잡티 직접 보정하기", systemImage: "bandage") }.font(.caption).buttonStyle(.bordered)
        }
    }
    private var toolsPanel: some View {
        Group {
            sectionTitle("손끝으로 다듬기", subtitle: "필요한 부분만 조심스럽게")
            toolCard(.retouch, title: "잡티 보정", detail: "깨끗한 피부를 먼저 클릭한 다음 잡티를 클릭하세요. 주변 질감을 복제해 부드럽게 합칩니다.")
            if store.tool == .retouch {
                Button { store.cloneSource = nil } label: { Label(store.cloneSource == nil ? "깨끗한 피부를 클릭하세요" : "샘플 위치 다시 선택", systemImage: "scope") }.font(.caption).buttonStyle(.bordered)
                Text("⌥ Option + 클릭으로도 샘플 위치를 바꿀 수 있습니다.").font(.system(size: 10)).foregroundStyle(.secondary)
            }
            toolCard(.warp, title: "얼굴·체형 부분 변형", detail: "조정할 곳을 살짝 드래그하세요. 배경도 함께 움직일 수 있으니 작은 변화부터 시작하세요.")
            VStack(alignment: .leading, spacing: 10) {
                HStack { Text("브러시 크기"); Spacer(); Text("\(Int(store.brushRadius * 1000))").monospacedDigit().foregroundStyle(.secondary) }.font(.caption)
                Slider(value: $store.brushRadius, in: 0.008...0.09)
            }
            Text("잡티 보정 \(store.recipe.spots.count)회 · 부분 변형 \(store.recipe.warps.count)회").font(.caption2).foregroundStyle(.secondary)
        }
    }
    private func toolCard(_ tool: EditorTool, title: String, detail: String) -> some View {
        Button { store.tool = tool } label: {
            VStack(alignment: .leading, spacing: 10) {
                Label(title, systemImage: tool.symbol).font(.system(size: 12, weight: .semibold)).foregroundStyle(store.tool == tool ? accent : .primary)
                Text(detail).font(.system(size: 11)).foregroundStyle(.secondary).lineSpacing(4).multilineTextAlignment(.leading)
            }.frame(maxWidth: .infinity, alignment: .leading).padding(14).background(Color.white.opacity(store.tool == tool ? 0.07 : 0.025), in: RoundedRectangle(cornerRadius: 10))
        }.buttonStyle(.plain)
    }
    private func sectionTitle(_ title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 5) { Text(title).font(.system(size: 15, weight: .semibold)); Text(subtitle).font(.system(size: 10)).foregroundStyle(.secondary) }
    }
    private func adjustment(_ name: String, key: WritableKeyPath<Adjustments, Double>, range: ClosedRange<Double>, value: String) -> some View {
        VStack(spacing: 7) {
            HStack { Text(name); Spacer(); Text(value).monospacedDigit().foregroundStyle(.secondary) }.font(.system(size: 12))
            Slider(value: Binding(get: { store.recipe.adjustments[keyPath: key] }, set: { store.change(key, $0) }), in: range, onEditingChanged: { editing in if editing { store.checkpoint() } }).accessibilityLabel(name)
        }
    }
    private func presetButton(_ name: String, colors: [Color], adjustments: @escaping () -> Adjustments) -> some View {
        Button { store.applyPreset(adjustments()) } label: {
            VStack(spacing: 6) {
                RoundedRectangle(cornerRadius: 7).fill(LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing)).frame(height: 64).overlay { Image(systemName: "sun.horizon").font(.system(size: 20, weight: .ultraLight)).foregroundStyle(.white.opacity(0.7)) }
                Text(name).font(.system(size: 10)).foregroundStyle(.secondary)
            }.frame(maxWidth: .infinity)
        }.buttonStyle(.plain)
    }
    private var statusBar: some View {
        HStack(spacing: 9) {
            Circle().fill(accent.opacity(0.8)).frame(width: 5, height: 5)
            Text(store.status).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1)
            Spacer()
            if store.exporting {
                ProgressView(value: store.progress).frame(width: 110)
                Button("취소") { store.cancelExport = true }.font(.caption).buttonStyle(.plain)
            }
            Text("v0.1  ·  로컬 전용").font(.system(size: 9, design: .monospaced)).foregroundStyle(.tertiary)
        }.padding(.horizontal, 20).frame(height: 30)
    }
}

struct PhotoCanvas: View {
    @ObservedObject var store: StudioStore
    var body: some View {
        GeometryReader { area in
            if let image = store.displayImage, let photo = store.selected {
                let fit = min((area.size.width - 50) / photo.image.extent.width, (area.size.height - 36) / photo.image.extent.height)
                let width = max(1, photo.image.extent.width * fit * store.zoom)
                let height = max(1, photo.image.extent.height * fit * store.zoom)
                ScrollView([.horizontal, .vertical]) {
                    Image(nsImage: image).resizable().interpolation(.high).frame(width: width, height: height)
                        .overlay(alignment: .topLeading) { Text(store.compare ? "원본" : "보정본").font(.system(size: 10, weight: .medium)).padding(.horizontal, 10).padding(.vertical, 6).background(.black.opacity(0.55), in: Capsule()).padding(12) }
                        .overlay {
                            if !store.compare, let source = store.cloneSource, store.tool == .retouch {
                                Image(systemName: "plus.circle").font(.system(size: 20)).foregroundStyle(.white).shadow(color: .black, radius: 2).position(x: source.x * width, y: (1 - source.y) * height).allowsHitTesting(false)
                            }
                        }
                        .overlay {
                            if !store.compare, store.tool != .adjust {
                                Rectangle().fill(.clear).contentShape(Rectangle()).gesture(DragGesture(minimumDistance: 0).onEnded { value in
                                    func normal(_ p: CGPoint) -> CGPoint { CGPoint(x: max(0, min(1, p.x / width)), y: max(0, min(1, 1 - p.y / height))) }
                                    if store.tool == .retouch { store.retouch(at: normal(value.location), setSource: NSEvent.modifierFlags.contains(.option)) }
                                    else { store.warp(from: normal(value.startLocation), to: normal(value.location)) }
                                })
                            }
                        }
                        .shadow(color: .black.opacity(0.25), radius: 14, y: 6)
                        .padding(18)
                        .frame(minWidth: area.size.width, minHeight: area.size.height)
                }
            }
        }
    }
}
