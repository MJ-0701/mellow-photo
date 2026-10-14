import MellowShared
import SwiftUI

/// 미리보기 표시, 잡티 탭, 변형 드래그, 샘플 위치 표시. 좌표는 정규화·원점 왼쪽 아래로 넘긴다.
struct PhotoCanvasView: View {
    @Environment(AppModel.self) private var model
    var zoom: Double = 1

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Theme.canvas
                if let image = model.displayImage {
                    let fit = min(
                        geometry.size.width / CGFloat(image.width), geometry.size.height / CGFloat(image.height))
                    let size = CGSize(
                        width: CGFloat(image.width) * fit * zoom, height: CGFloat(image.height) * fit * zoom)
                    ScrollView([.horizontal, .vertical]) {
                        Image(cgImage: image).resizable().interpolation(.high)
                            .frame(width: size.width, height: size.height)
                            .overlay { cloneSourceMarker(in: size) }
                            .overlay { touchLayer(in: size) }
                            .frame(minWidth: geometry.size.width, minHeight: geometry.size.height)
                    }
                    .scrollDisabled(zoom == 1)
                    .accessibilityLabel(model.isComparing ? "원본 사진" : "보정 미리보기")
                }
                if let message = model.selectionFailure {
                    recoveryActions(message)
                } else if !model.isReady || model.isRendering {
                    ProgressView().padding(12).background(.ultraThinMaterial, in: Capsule()).allowsHitTesting(false)
                }
            }
            .overlay(alignment: .topLeading) {
                if model.isReady {
                    Text(model.isComparing ? "원본" : "보정본")
                        .font(.caption2)
                        .padding(7)
                        .background(.ultraThinMaterial, in: Capsule())
                        .padding(10)
                }
            }
            .clipped()
        }
    }

    @ViewBuilder
    private func cloneSourceMarker(in size: CGSize) -> some View {
        if let source = model.cloneSource, model.tool == .retouch, !model.isComparing {
            let diameter = max(12, model.brushRadius * min(size.width, size.height) * 2)
            Circle().stroke(Theme.accent, lineWidth: 2)
                .frame(width: diameter, height: diameter)
                .position(x: source.x * size.width, y: (1 - source.y) * size.height)
                .allowsHitTesting(false)
        }
    }

    @ViewBuilder
    private func touchLayer(in size: CGSize) -> some View {
        if model.tool.usesCanvasTouch, !model.isComparing {
            Color.clear.contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0).onEnded { value in
                        guard size.width > 0, size.height > 0 else { return }
                        func normalized(_ point: CGPoint) -> NormalizedPoint {
                            NormalizedPoint(
                                x: max(0, min(1, point.x / size.width)), y: max(0, min(1, 1 - point.y / size.height)))
                        }
                        #if os(macOS)
                            if model.tool == .retouch, NSEvent.modifierFlags.contains(.option) {
                                model.resetCloneSource()
                            }
                        #endif
                        model.touch(from: normalized(value.startLocation), to: normalized(value.location))
                    })
        }
    }

    private func recoveryActions(_ message: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "photo.badge.exclamationmark").font(.title)
            Text(message).font(.callout).multilineTextAlignment(.center)
            HStack {
                Button("다시 시도") {
                    if let id = model.session.selectedPhotoID {
                        model.select(id)
                    }
                }
                Button("편집에서 빼기", role: .destructive) { model.removeSelectedPhoto() }
            }
            .buttonStyle(.bordered).disabled(model.isBusy)
        }
        .padding()
    }
}
