import SwiftUI
import PhotosUI
import MellowCore

private let mint = Color(red: 0.78, green: 0.88, blue: 0.69)

struct MobileEditor: View {
    @ObservedObject var store: MobileStore
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if store.photos.isEmpty { welcome }
                else {
                    photoStrip
                    canvas.frame(maxHeight: .infinity)
                    actionBar
                    controls
                }
                if store.importing || store.exporting {
                    VStack(spacing: 6) {
                        if store.exporting { ProgressView(value: store.progress) }
                        HStack {
                            Text(store.status).font(.caption)
                            if store.exporting { Spacer(); Button("나머지 취소") { store.cancelExport = true }.font(.caption) }
                        }
                    }.padding(.horizontal).padding(.vertical, 8)
                } else {
                    Text(store.status).font(.caption2).foregroundStyle(.secondary)
                        .lineLimit(2).frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal).padding(.vertical, 8)
                }
            }
            .background(Color(uiColor: .systemBackground))
            .navigationTitle("mellow")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    HStack {
                        Button { store.infoSheet = true } label: { Image(systemName: "info.circle") }.accessibilityLabel("도움말과 개인정보")
                        picker.labelStyle(.iconOnly).disabled(store.busy || store.photos.count >= 12)
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button("현재 사진 저장", systemImage: "square.and.arrow.down") { Task { await store.saveToPhotos(all: false) } }.disabled(!store.ready)
                        Button("전체 \(store.photos.count)장 저장") { Task { await store.saveToPhotos(all: true) } }.disabled(!store.ready)
                        Toggle("원본 해상도", isOn: $store.fullResolution)
                        Text("기본: 긴 변 최대 4096px · JPEG")
                        Divider()
                        Button("편집에서 사진 빼기", role: .destructive) { store.removeConfirmation = true }
                    } label: { Label("저장", systemImage: "square.and.arrow.down").font(.body.weight(.semibold)) }
                    .disabled(!store.canRemoveSelected)
                }
            }
        }
        .tint(mint)
        .onChange(of: store.pickerItems) { _, items in
            if !items.isEmpty { Task { await store.importSelected() } }
        }
        .alert("확인해주세요", isPresented: Binding(get: { store.error != nil }, set: { if !$0 { store.error = nil } })) {
            Button("확인") { store.error = nil }
        } message: { Text(store.error ?? "") }
        .confirmationDialog("이 사진을 처음 상태로 돌릴까요?", isPresented: $store.resetConfirmation, titleVisibility: .visible) {
            Button("보정 초기화", role: .destructive) { store.reset() }
        } message: { Text("원본은 바뀌지 않습니다. 실행 취소로 복구할 수 있어요.") }
        .confirmationDialog("편집에서 사진을 뺄까요?", isPresented: $store.removeConfirmation, titleVisibility: .visible) {
            Button("편집에서 빼기", role: .destructive) { store.removeSelected() }
        } message: { Text("이 앱의 작업 사본과 보정 기록이 삭제됩니다. 사진 앱의 원본은 남아 있습니다.") }
        .sheet(isPresented: $store.infoSheet) {
            NavigationStack {
                List {
                    Section("Mellow Photo") {
                        Text("사진과 얼굴 분석은 기기 내부에서 처리합니다. 작업 기록은 앱에 저장되고, 사진 앱의 원본은 변경하지 않습니다.")
                        Text("앱 삭제 시 내부 작업 기록은 사라집니다. 완성한 사진은 사진 앱에 저장해 주세요.")
                    }
                    Section("도움말") {
                        Link("지원 페이지", destination: URL(string: "https://mj-0701.github.io/mellow-photo-support/")!)
                        Link("개인정보 안내", destination: URL(string: "https://mj-0701.github.io/mellow-photo-support/privacy.html")!)
                        Link("이메일 문의", destination: URL(string: "mailto:jack2718@naver.com")!)
                    }
                }.navigationTitle("도움말과 개인정보").navigationBarTitleDisplayMode(.inline)
                    .toolbar { ToolbarItem(placement: .confirmationAction) { Button("닫기") { store.infoSheet = false } } }
            }
        }
        .sheet(isPresented: $store.presetSheet) {
            NavigationStack {
                Form {
                    TextField("분위기 이름", text: $store.presetName)
                    Text("색감·피부·얼굴 슬라이더 값만 저장합니다. 잡티 위치와 수동 변형은 포함하지 않습니다.").font(.caption).foregroundStyle(.secondary)
                }
                .navigationTitle("분위기 저장")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("취소") { store.presetSheet = false } }
                    ToolbarItem(placement: .confirmationAction) { Button("저장") { store.savePreset() }.disabled(store.presetName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) }
                }
            }.presentationDetents([.medium])
        }
    }
    private var picker: some View {
        PhotosPicker(selection: $store.pickerItems, maxSelectionCount: max(1, 12 - store.photos.count),
                     matching: .images, preferredItemEncoding: .current) {
            Label("사진 고르기", systemImage: "plus")
        }
    }
    private var welcome: some View {
        VStack(spacing: 24) {
            Spacer()
            Image(systemName: "camera.macro").font(.system(size: 68, weight: .ultraLight)).foregroundStyle(mint)
            Text("좋아하는 순간을,\n조금 더 부드럽게.").font(.largeTitle.weight(.light)).multilineTextAlignment(.center)
            Text("아이폰 인물 사진을 나답게 다듬어보세요.").font(.subheadline).foregroundStyle(.secondary)
            picker.buttonStyle(.borderedProminent).foregroundStyle(.black).controlSize(.large).disabled(store.busy)
            Text("사진은 기기 안에서 처리해요.\n최대 12장 · 편집 기록 자동 저장").font(.caption).multilineTextAlignment(.center).foregroundStyle(.secondary)
            if store.restoring || store.importing { ProgressView() }
            Spacer()
        }.padding().frame(maxWidth: .infinity)
    }
    private var photoStrip: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 10) {
                ForEach(store.photos) { photo in
                    Button { store.select(photo.id) } label: {
                        ZStack(alignment: .bottomTrailing) {
                            if let image = store.thumbnails[photo.id] {
                                Image(uiImage: image).resizable().scaledToFill()
                            } else { Rectangle().fill(.secondary.opacity(0.2)).overlay(Image(systemName: "photo")) }
                            if photo.recipe != EditRecipe() { Image(systemName: "slider.horizontal.3").font(.caption2).padding(4).background(.black.opacity(0.6), in: Circle()).padding(3) }
                        }
                        .frame(width: 52, height: 60).clipped().clipShape(RoundedRectangle(cornerRadius: 8))
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(photo.id == store.selectedID ? mint : .clear, lineWidth: 2))
                    }.buttonStyle(.plain).accessibilityLabel(photo.name).accessibilityAddTraits(photo.id == store.selectedID ? .isSelected : [])
                }
            }.padding(.horizontal).padding(.vertical, 8)
        }.disabled(store.busy).scrollIndicators(.hidden)
    }
    private var canvas: some View {
        GeometryReader { geo in
            ZStack {
                Color(uiColor: .secondarySystemBackground)
                if let image = store.displayImage {
                    let scale = min(geo.size.width / image.size.width, geo.size.height / image.size.height)
                    let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
                    Image(uiImage: image).resizable().frame(width: size.width, height: size.height)
                        .overlay {
                            ZStack {
                                Color.clear.contentShape(Rectangle())
                                if let source = store.cloneSource, store.tool == .retouch, !store.compare {
                                    Circle().stroke(mint, lineWidth: 2)
                                        .frame(width: max(12, store.brushRadius * min(size.width, size.height) * 2), height: max(12, store.brushRadius * min(size.width, size.height) * 2))
                                        .position(x: source.x * size.width, y: (1 - source.y) * size.height)
                                        .allowsHitTesting(false)
                                }
                            }
                            .gesture(DragGesture(minimumDistance: 0).onEnded { value in
                                guard size.width > 0, size.height > 0 else { return }
                                func point(_ p: CGPoint) -> CGPoint {
                                    CGPoint(x: max(0, min(1, p.x / size.width)), y: max(0, min(1, 1 - p.y / size.height)))
                                }
                                store.touch(from: point(value.startLocation), to: point(value.location))
                            })
                        }
                        .accessibilityLabel(store.compare ? "원본 사진" : "보정 미리보기")
                }
                if let message = store.selectionError {
                    VStack(spacing: 12) {
                        Image(systemName: "photo.badge.exclamationmark").font(.title)
                        Text(message).font(.callout).multilineTextAlignment(.center)
                        HStack {
                            Button("다시 시도") { if let id = store.selectedID { store.select(id) } }
                            Button("편집에서 빼기", role: .destructive) { store.removeConfirmation = true }
                        }.buttonStyle(.bordered).disabled(store.busy)
                    }.padding().accessibilityIdentifier("photoRecoveryActions")
                } else if !store.ready || store.rendering {
                    ProgressView().padding(12).background(.ultraThinMaterial, in: Capsule()).allowsHitTesting(false)
                }
            }.overlay(alignment: .topLeading) {
                if store.ready { Text(store.compare ? "원본" : "보정본").font(.caption2).padding(7).background(.ultraThinMaterial, in: Capsule()).padding(10) }
            }.clipped()
        }
        .frame(minHeight: 130)
    }
    private var actionBar: some View {
        HStack {
            Button { store.undo() } label: { Image(systemName: "arrow.uturn.backward").frame(width: 40, height: 40) }.disabled(!store.canUndo).accessibilityLabel("실행 취소")
            Button { store.redo() } label: { Image(systemName: "arrow.uturn.forward").frame(width: 40, height: 40) }.disabled(!store.canRedo).accessibilityLabel("다시 실행")
            Spacer()
            Text(store.dimensions).font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
            Button { store.compare.toggle() } label: { Text(store.compare ? "보정본" : "원본 비교").font(.caption.weight(.medium)).frame(minWidth: 65, minHeight: 40) }
        }.padding(.horizontal, 12).disabled(store.busy || !store.ready)
    }
    private var controls: some View {
        VStack(spacing: 12) {
            Picker("보정 도구", selection: $store.tool) {
                ForEach(MobileTool.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }.pickerStyle(.segmented)
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    switch store.tool {
                    case .color: colorControls
                    case .portrait: portraitControls
                    case .retouch, .warp: brushControls
                    }
                }.padding(.vertical, 5)
            }.frame(height: 182)
            HStack {
                Button("전체 사진에 적용") { store.applyAll() }.disabled(store.photos.count < 2)
                Spacer()
                Button("초기화") { store.resetConfirmation = true }
            }.font(.caption).padding(.bottom, 4)
        }.padding(.horizontal).padding(.top, 10)
            .background(Color(uiColor: .secondarySystemBackground))
            .disabled(store.busy || !store.ready)
    }
    private var colorControls: some View {
        Group {
            ScrollView(.horizontal) {
                HStack {
                    Button("내추럴") { var a = Adjustments(); a.exposure = 0.1; a.skin = 0.2; store.apply(a) }
                    Button("포근한") { var a = Adjustments(); a.exposure = 0.15; a.warmth = 0.25; a.saturation = 0.92; a.skin = 0.3; store.apply(a) }
                    Button("클린") { var a = Adjustments(); a.exposure = 0.2; a.contrast = 1.05; a.warmth = -0.1; store.apply(a) }
                    ForEach(store.presets) { preset in Button(preset.name) { store.apply(preset.adjustments) } }
                    Button { store.presetSheet = true } label: { Label("저장", systemImage: "plus") }
                }.buttonStyle(.bordered).font(.caption)
            }.scrollIndicators(.hidden)
            adjustment("노출", key: \.exposure, range: -1.5...1.5)
            adjustment("대비", key: \.contrast, range: 0.7...1.3)
            adjustment("채도", key: \.saturation, range: 0...1.5)
            adjustment("따뜻함", key: \.warmth, range: -1...1)
        }
    }
    private var portraitControls: some View {
        Group {
            if store.faces.isEmpty {
                Label("감지된 얼굴이 없어요", systemImage: "person.crop.rectangle.badge.questionmark")
                Text("정면에 가까운 사진을 선택하거나 잡티·변형 도구를 직접 사용해 주세요.").font(.caption).foregroundStyle(.secondary)
            } else {
                Picker("얼굴 \(store.faces.count)명", selection: Binding(get: { store.recipe.selectedFace ?? -1 }, set: { store.setFace($0 == -1 ? nil : $0) })) {
                    Text("모든 얼굴").tag(-1)
                    ForEach(store.faces.indices, id: \.self) { Text("왼쪽부터 \($0 + 1)번째").tag($0) }
                }.disabled(store.geometryLocked)
                adjustment("피부 정돈", key: \.skin, range: 0...1)
                adjustment("얼굴 미세 조정", key: \.faceSlim, range: 0...1).disabled(store.geometryLocked)
                Text(store.geometryLocked ? "수동 보정 위치를 유지하려고 얼굴 조정을 잠갔어요. 실행 취소 또는 초기화하면 다시 조정할 수 있어요." : "얼굴 형태를 먼저 조정한 뒤 잡티를 보정해 주세요. 피부 정돈은 부드러운 필터이며 자동 잡티 제거는 아닙니다.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }
    private var brushControls: some View {
        Group {
            Text(store.tool == .retouch ? (store.choosingSource ? "① 깨끗한 피부를 톡 눌러 샘플을 골라주세요." : "② 지우고 싶은 작은 잡티를 톡 눌러주세요.") : "조정할 부분을 원하는 방향으로 살짝 밀어주세요.").font(.subheadline)
            if store.tool == .retouch {
                Button("샘플 위치 다시 고르기") { store.choosingSource = true; store.cloneSource = nil }.buttonStyle(.bordered)
            }
            HStack { Text("브러시 크기").font(.caption); Slider(value: $store.brushRadius, in: 0.008...0.07).accessibilityLabel("브러시 크기") }
            Text(store.tool == .retouch ? "자동 탐지가 아닌 수동 복제 브러시입니다. 가까운 피부를 샘플로 선택하면 더 자연스러워요." : "배경도 함께 움직일 수 있어요. 조금씩 조정하고 원본과 비교해 주세요.").font(.caption).foregroundStyle(.secondary)
        }
    }
    private func adjustment(_ name: String, key: WritableKeyPath<Adjustments, Double>, range: ClosedRange<Double>) -> some View {
        VStack(spacing: 5) {
            HStack { Text(name); Spacer(); Text(store.recipe.adjustments[keyPath: key], format: .number.precision(.fractionLength(2))).monospacedDigit().foregroundStyle(.secondary) }.font(.caption)
            Slider(value: Binding(get: { store.recipe.adjustments[keyPath: key] }, set: { store.change(key, $0) }), in: range, onEditingChanged: store.sliderEditing).accessibilityLabel(name)
        }
    }
}
