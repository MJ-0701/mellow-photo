import MellowShared
import SwiftUI

/// 미리보기 표시, 핀치 확대, 잡티 탭, 변형 드래그, 샘플 위치 표시. 좌표는 정규화·원점 왼쪽 아래로 넘긴다.
struct PhotoCanvasView: View {
    @Environment(AppModel.self) private var model
    @Binding var zoom: Double
    /// 복구 화면의 "편집에서 빼기"도 툴바와 같은 확인 대화상자를 거친다.
    @Binding var removeConfirmation: Bool
    /// 핀치를 시작할 때의 배율. 핀치 중이 아니면 nil.
    @State private var pinchBase: Double?
    @State private var isDragging = false
    /// 진행 중인 드래그 도중 핀치가 있었으면 손을 뗄 때 잡티·변형으로 처리하지 않는다.
    @State private var dragSawPinch = false

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
                            .overlay { splitOverlay(in: size) }
                            .overlay { cropOverlay(in: size) }
                            .coordinateSpace(.named(Theme.canvasCoordinateSpace))
                            .frame(minWidth: geometry.size.width, minHeight: geometry.size.height)
                    }
                    .scrollDisabled(zoom == Theme.zoomRange.lowerBound)
                    .simultaneousGesture(magnify)
                    .accessibilityLabel(model.compareMode == .full ? "원본 사진" : "보정 미리보기")
                }
                if let message = model.selectionFailure {
                    recoveryActions(message)
                } else if !model.isReady || model.isRendering {
                    ProgressView().padding(12).background(.ultraThinMaterial, in: Capsule()).allowsHitTesting(false)
                }
            }
            .overlay(alignment: .topLeading) {
                if model.isReady {
                    Text(UserMessage.compareBadge(model.compareMode))
                        .font(.caption2)
                        .padding(7)
                        .background(.ultraThinMaterial, in: Capsule())
                        .padding(10)
                        .allowsHitTesting(false)
                }
            }
            .clipped()
        }
    }

    /// 어느 도구에서든 쓸 수 있다. 드래그 층은 그대로 두고 동시에 인식한다.
    private var magnify: some Gesture {
        MagnifyGesture()
            .onChanged { value in
                let base = pinchBase ?? zoom
                pinchBase = base
                if isDragging {
                    dragSawPinch = true
                }
                zoom = Theme.clampedZoom(base * value.magnification)
            }
            .onEnded { _ in
                pinchBase = nil
            }
    }

    @ViewBuilder
    private func cloneSourceMarker(in size: CGSize) -> some View {
        if let source = model.cloneSourceOnCanvas, model.tool == .retouch, !model.blocksCanvasTouch {
            let diameter = max(
                Theme.brushMarkerMinimumDiameter,
                model.brushRadius * min(size.width, size.height) * 2 * outputToOriginalScale)
            Circle().stroke(Theme.accent, lineWidth: 2)
                .frame(width: diameter, height: diameter)
                .position(x: source.x * size.width, y: (1 - source.y) * size.height)
                .allowsHitTesting(false)
        }
    }

    /// 브러시 반지름은 원본 정규화 단위다. 자른 캔버스에서는 그만큼 크게 보여야 실제 적용 범위와 맞는다.
    private var outputToOriginalScale: CGFloat {
        guard let crop = model.outputTransform?.geometry.crop, crop.width > 0 else { return 1 }
        return 1 / crop.width
    }

    /// 자르기 손잡이 드래그가 확대 제스처보다 우선하도록 가장 위에 둔다.
    @ViewBuilder
    private func cropOverlay(in size: CGSize) -> some View {
        if model.tool == .crop, !model.blocksCanvasTouch {
            CropOverlay(size: size)
        }
    }

    /// 분할 모드: 보정본 위에 원본을 왼쪽 compareSplit 비율만 보이게 얹고 경계에 분할선을 둔다.
    /// 원본은 미리보기와 같은 기하로 그린 것만 받으므로(AppModel.splitCompareOriginal) 같은 크기(size)에 겹치면 화소 위치가 맞는다.
    @ViewBuilder
    private func splitOverlay(in size: CGSize) -> some View {
        if model.compareMode == .split {
            if let original = model.splitCompareOriginal {
                Image(cgImage: original).resizable().interpolation(.high)
                    .frame(width: size.width, height: size.height)
                    .mask(alignment: .leading) { Rectangle().frame(width: size.width * model.compareSplit) }
                    .allowsHitTesting(false)
            }
            CompareDivider(size: size)
        }
    }

    /// 뷰티·메이크업은 탭 제스처만 붙여 확대한 사진의 한 손가락 이동을 스크롤 뷰에 남긴다.
    /// 잡티·변형은 드래그가 곧 편집이라 드래그 층을 쓴다.
    @ViewBuilder
    private func touchLayer(in size: CGSize) -> some View {
        if model.tool.usesCanvasTouch, !model.blocksCanvasTouch, model.tool.selectsTargetByTap {
            Color.clear.contentShape(Rectangle())
                .gesture(
                    SpatialTapGesture().onEnded { value in
                        guard size.width > 0, size.height > 0 else { return }
                        let point = Self.normalized(value.location, in: size)
                        model.touch(from: point, to: point)
                    })
        } else if model.tool.usesCanvasTouch, !model.blocksCanvasTouch {
            Color.clear.contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0).onChanged { _ in
                        if !isDragging {
                            isDragging = true
                            dragSawPinch = pinchBase != nil
                        }
                    }
                    .onEnded { value in
                        let pinched = dragSawPinch
                        isDragging = false
                        dragSawPinch = false
                        guard !pinched, size.width > 0, size.height > 0 else { return }
                        #if os(macOS)
                            if model.tool == .retouch, NSEvent.modifierFlags.contains(.option) {
                                model.resetCloneSource()
                            }
                        #endif
                        model.touch(
                            from: Self.normalized(value.startLocation, in: size),
                            to: Self.normalized(value.location, in: size))
                    })
        }
    }

    /// 이미지 위 점(원점 왼쪽 위)을 정규화·원점 왼쪽 아래로 바꾼다.
    private static func normalized(_ point: CGPoint, in size: CGSize) -> NormalizedPoint {
        NormalizedPoint(x: max(0, min(1, point.x / size.width)), y: max(0, min(1, 1 - point.y / size.height)))
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
                Button("편집에서 빼기", role: .destructive) { removeConfirmation = true }
            }
            .buttonStyle(.bordered).disabled(model.isBusy)
        }
        .padding()
    }
}
