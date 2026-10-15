import MellowShared
import SwiftUI

/// 자르기 전 이미지 위의 사각형과 손잡이 8개. 좌표는 정규화·원점 왼쪽 아래로 모델에 넘긴다.
struct CropOverlay: View {
    @Environment(AppModel.self) private var model
    let size: CGSize
    @State private var dragStartRect: NormalizedRect?

    enum Handle: CaseIterable {
        case topLeft, top, topRight, left, right, bottomLeft, bottom, bottomRight

        /// 위쪽 변(정규화 maxY)을 움직이는 손잡이.
        var movesTop: Bool { self == .topLeft || self == .top || self == .topRight }
        /// 아래쪽 변(정규화 minY)을 움직이는 손잡이.
        var movesBottom: Bool { self == .bottomLeft || self == .bottom || self == .bottomRight }
        var movesLeft: Bool { self == .topLeft || self == .left || self == .bottomLeft }
        var movesRight: Bool { self == .topRight || self == .right || self == .bottomRight }
    }

    private var rect: NormalizedRect {
        model.currentRecipe.geometry.crop ?? NormalizedRect(x: 0, y: 0, width: 1, height: 1)
    }

    var body: some View {
        let frame = pixelFrame(rect)
        ZStack(alignment: .topLeading) {
            Path { path in
                path.addRect(CGRect(origin: .zero, size: size))
                path.addRect(frame)
            }
            .fill(Color.black.opacity(0.45), style: FillStyle(eoFill: true))
            .allowsHitTesting(false)
            Rectangle().stroke(Theme.accent, lineWidth: 1.5)
                .frame(width: frame.width, height: frame.height)
                .position(x: frame.midX, y: frame.midY)
                .allowsHitTesting(false)
            // 손잡이가 이동 영역 위에 있어야 모서리 드래그가 이동으로 먹히지 않는다.
            Color.clear.contentShape(Rectangle())
                .frame(width: frame.width, height: frame.height)
                .position(x: frame.midX, y: frame.midY)
                .gesture(moveDrag)
            ForEach(Handle.allCases, id: \.self) { handle in
                Circle().fill(Theme.accent)
                    .frame(width: Theme.cropHandleSize, height: Theme.cropHandleSize)
                    .position(handlePosition(handle, in: frame))
                    .gesture(handleDrag(handle))
            }
        }
        .frame(width: size.width, height: size.height)
    }

    /// 정규화(원점 왼쪽 아래) → 뷰 픽셀(원점 왼쪽 위).
    private func pixelFrame(_ rect: NormalizedRect) -> CGRect {
        CGRect(
            x: rect.x * size.width, y: (1 - rect.maxY) * size.height,
            width: rect.width * size.width, height: rect.height * size.height)
    }

    private func handlePosition(_ handle: Handle, in frame: CGRect) -> CGPoint {
        switch handle {
        case .topLeft: return CGPoint(x: frame.minX, y: frame.minY)
        case .top: return CGPoint(x: frame.midX, y: frame.minY)
        case .topRight: return CGPoint(x: frame.maxX, y: frame.minY)
        case .left: return CGPoint(x: frame.minX, y: frame.midY)
        case .right: return CGPoint(x: frame.maxX, y: frame.midY)
        case .bottomLeft: return CGPoint(x: frame.minX, y: frame.maxY)
        case .bottom: return CGPoint(x: frame.midX, y: frame.maxY)
        case .bottomRight: return CGPoint(x: frame.maxX, y: frame.maxY)
        }
    }

    /// 드래그 이동량을 정규화(원점 왼쪽 아래) 단위로.
    private func normalizedTranslation(_ value: DragGesture.Value) -> (dx: Double, dy: Double) {
        guard size.width > 0, size.height > 0 else { return (0, 0) }
        return (Double(value.translation.width / size.width), -Double(value.translation.height / size.height))
    }

    /// 드래그 첫 이벤트에서 시작 사각형을 기억하고 실행 취소 단계를 연다.
    private func startDragIfNeeded() -> NormalizedRect {
        if let start = dragStartRect {
            return start
        }
        let start = rect
        dragStartRect = start
        model.beginCropDrag()
        return start
    }

    private func finishDrag() {
        dragStartRect = nil
        model.endCropDrag()
    }

    /// 움직임 없는 탭은 빈 실행 취소 단계를 만들지 않도록 드래그로 치지 않는다.
    private func handleDrag(_ handle: Handle) -> some Gesture {
        DragGesture(minimumDistance: 1)
            .onChanged { value in
                let start = startDragIfNeeded()
                let delta = normalizedTranslation(value)
                let resized = Self.resized(
                    start, handle: handle, dx: delta.dx, dy: delta.dy, lockedRatio: lockedRatio)
                model.edit(.crop(resized))
            }
            .onEnded { _ in finishDrag() }
    }

    private var moveDrag: some Gesture {
        DragGesture(minimumDistance: 1)
            .onChanged { value in
                let start = startDragIfNeeded()
                let delta = normalizedTranslation(value)
                let x = min(max(0, start.x + delta.dx), 1 - start.width)
                let y = min(max(0, start.y + delta.dy), 1 - start.height)
                model.edit(.crop(NormalizedRect(x: x, y: y, width: start.width, height: start.height)))
            }
            .onEnded { _ in finishDrag() }
    }

    /// 비율 고정 시 정규화 공간에서의 width/height 비(이미지 비율 반영).
    private var lockedRatio: Double? {
        guard let ratio = model.cropAspect?.ratio, let transform = model.outputTransform else { return nil }
        return ratio / transform.turnedAspect
    }

    /// 손잡이를 끈 결과. 최소 변 Theme.cropMinimumSide, 0…1로 제한.
    /// 비율 고정이면 모서리·좌우 손잡이는 너비로, 위아래 손잡이는 높이로 크기를 정하고 반대쪽 변을 고정한다.
    static func resized(
        _ start: NormalizedRect, handle: Handle, dx: Double, dy: Double, lockedRatio: Double?
    ) -> NormalizedRect {
        var minX = start.minX
        var maxX = start.maxX
        var minY = start.minY
        var maxY = start.maxY
        if handle.movesLeft {
            minX += dx
        }
        if handle.movesRight {
            maxX += dx
        }
        if handle.movesTop {
            maxY += dy
        }
        if handle.movesBottom {
            minY += dy
        }
        minX = max(0, min(minX, maxX - Theme.cropMinimumSide))
        maxX = min(1, max(maxX, minX + Theme.cropMinimumSide))
        minY = max(0, min(minY, maxY - Theme.cropMinimumSide))
        maxY = min(1, max(maxY, minY + Theme.cropMinimumSide))
        guard let lockedRatio, lockedRatio > 0 else {
            return NormalizedRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
        }
        let drivenByHeight = handle == .top || handle == .bottom
        let availableWidth = handle.movesLeft ? maxX : 1 - minX
        let availableHeight = handle.movesTop ? 1 - minY : maxY
        let requested = drivenByHeight ? (maxY - minY) * lockedRatio : maxX - minX
        let minimumWidth = Theme.cropMinimumSide * max(1, lockedRatio)
        let width = max(minimumWidth, min(requested, availableWidth, availableHeight * lockedRatio))
        let height = width / lockedRatio
        if handle.movesLeft {
            minX = maxX - width
        } else {
            maxX = minX + width
        }
        if handle.movesTop {
            maxY = minY + height
        } else {
            minY = maxY - height
        }
        return NormalizedRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }
}
